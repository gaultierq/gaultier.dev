---

title: The sidekiq quarantine queue 
date: 2025-04-08 19:46 UTC
tags: rails, sidekiq

---
# How to Stop a Buggy Sidekiq Job from Hogging Your App

Sidekiq is a powerful tool for background processing, but even the best systems can get tripped up by a single bad job. What happens when a job goes rogue? Maybe it enters an infinite loop, triggers a memory leak, or hammers your database with an unexpected N+1 query. These bugs are often subtle, introduced during development, and only manifest under specific inputs or load conditions.

So: **how do you stop a single misbehaving job from taking down your app?**


## A Real-World Example

Here's something that actually happened to us.

A user filled out a report form with a *large* time range. 
There was no input sanitization, and that led to a `ReportJob` being enqueued that queried **a massive amount of data**.

The job didn’t just run long—it choked the system. 
It used excessive CPU, blocked other threads, and starved more critical jobs from running. 
Restarting the Sidekiq processes (pods) doesn't help: the job just get picked up again on next restart.
So what can we do at this point ? ** How can we prevent a single job from breaking everything else? **


## A Quarantine Queue

A quarantine queue is a dedicated Sidekiq queue where you can isolate jobs that are known (or suspected) to cause problems. 
The goal is to prevent one bad job from degrading the performance or stability of your entire background job system.
So you assign modest resources to a sidekiq single-threaded process peeking from this "quarantine" queue.


## 1. Moving jobs to the quarantine queue manually

First, I wanted to be able to re-route some jobs to the quarantine queue from an env variable. This way, if some jobs start behaving having dubious behaviour (for instance, sending N+1 queries to the database), we can start piling these jobs in the quarantine queue. The damage they will cause will be limited as the concurrency and resources are limited. 

The following is a how we intercept jobs and change their queue before they are enqueued.

```ruby
class QuarantineMiddleware
    def call(worker, job, queue, redis_pool)
        job['queue'] = 'quarantine' if quarantined_jobs.include?(job['class'])
        yield
    end

    private

    def quarantined_jobs
        @quarantined_jobs ||= (ENV['QUARANTINED_JOBS'] || '').split(';')
    end
end
```

```ruby
Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add QuarantineMiddleware
  end
end
```

[This video](https://www.youtube.com/watch?v=bvdWPGQ8cEA&t=229s) describes how a quarantine queue can help you when investigating a memory leak, and was a strong inspiration for this article.


---

## 2. Infinite loop
Now let's assume you have jobs that are stuck in an infinite loop. What can we do about them ?
Well can we set `QUARANTINED_JOBS=MegaLoopJob` and restart the process ?
Well actually no, it won't work. The previous `Quarantine` middleware is re-routing jobs in the client, i.e. in your rails controller for instance. Once the job is in it's queue, this middleware is not going to help.

Actually when Sidekiq is stopped, it enqueue back the running jobs in their original queue. 
From sidekiq source:
```ruby
def hard_shutdown
    # ...
    capsule.fetcher.bulk_requeue(jobs)
```

So we need another strategy for this case. 

Consider the following server middleware

```ruby
class LongRunningJobInterceptor
        # We want long-running job to be rerouted to the quarantine queue when sidekiq process restarts.

        def call(worker, job, queue)
          jid = job['jid']

          if should_quarantine?(job, queue)
            # Re-enqueue job in quarantine and skip execution

            worker.class.set(queue: QUARANTINE_QUEUE).perform_async(*job['args'])
            return
          end

          # Mark the job as running in redis, and save the start time
          set! jid, Time.current

          shutdown = false
          begin
            yield
          rescue ::Sidekiq::Shutdown
            shutdown = true
            raise
          ensure
            # Only remove the key if the job has completed (not shutdown)
            unset!(jid) unless shutdown
          end
        end

        # picks what job should be re-scheduled in the quarantine queue
        def should_quarantine?(job, queue)
          # no need to re-schedule the job, it's already quarantined
          return false if queue == QUARANTINE_QUEUE 
          
          job_started_too_long_ago?(job, queue)
        end
      end
```

With this mechanism, if a job has been stuck in an infinite loop for hours, restarting the sidekiq process will
restart the job, but it will be run from the quarantine queue and free one spot from our `critical` queue.

# 3. Auto-detection

The previous is pretty useful, but still requires the manual action from system maintainer. 
We need to monitor long running jobs, and restart the system if we detect a long running job.
Can we do better ? And remove this manual intervention ?


## 3.a Timeouts

One option is to kill the job if it runs too long.

But timeouts come with their own set of issues:

- **They’re unreliable** — the job might get killed mid-way, leaving things half-done.
- **They can cause resource leaks** — for example, if the job held onto a DB connection and didn’t release it.

If your DB connection pool is small, one leaked connection can snowball into widespread failure across your app.

## 3.b. Soft timeouts: a monitoring thread coupled with health checks / liveness probes  

What we really wanted was a way to catch problematic jobs **before** they can do damage.

Imagine this flow:

We implemented a proactive strategy:

- We keep track of when job are started
- We set a **soft timeout threshold** in our app logic.
- If a job exceeds that threshold, we let the hyperviser know the process should be restarted.
- When Sidekiq requeues the job after the restart, we **detect** that it’s a repeat offender and move it to the quarantine queue (thanks to the `LongRunningJobInterceptor`)


```ruby
    class Monitor
      class ShuttingDown < StandardError; end

      # The monitor thread will periodically check what is the state of this sidekiq process
      SIDEKIQ_UNHEALTHY = Rails.root.join('tmp/sidekiq_unhealthy').freeze

      class << self
        def start
          @instance ||= new.tap(&:start)
        end
      end

      def start
        Thread.new do
          Thread.current.name = 'sidekiq-monitor'
          begin
            loop do
              running_jobs.each do |job|
                runtime = Time.now - job[:started_at]
                mark_unhealthy if runtime > 2.minutes
              end

              sleep 1
            end
          rescue => e
            Sidekiq.logger.error "Unexpected error in monitoring thread: #{e.class} - #{e.message}"
          ensure
            puts 'Monitoring finished'
          end
        end
      end

      def running_jobs
      end


      # this is our way to signal to kubernetes / systemd / hyperviser that this process needs to be stopped
      def mark_unhealthy
        FileUtils.touch(SIDEKIQ_UNHEALTHY)
      end
    end

    # keep track of when a job was started
    class RunningJobs
        JOBS = Concurrent::Map.new
        def call(worker, job, queue)
          thread_id = Thread.current.object_id
          JOBS[thread_id] = {
            job_id: job['jid'],
            class: job['class'],
            args: job['args'],
            queue: queue,
            started_at: Time.now,
          }
          yield
        ensure
          JOBS.delete(thread_id)
        end

        def self.running_jobs
          JOBS.values
        end
    end
```
