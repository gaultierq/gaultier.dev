---

title: The sidekiq quarantine queue 
date: 2025-04-08 19:46 UTC
tags: rails, sidekiq

---
# How to Shield Your App from a Rogue Sidekiq Job

Sidekiq is great for background processing—but a single misbehaving job (infinite loops, massive data scans, N+1 storms…) can choke your entire pipeline. Restarting Sidekiq only brings the offender right back. 

**How do you quarantine a bad job so that it can’t block all your critical work?**


## A Real-World Incident

A user submitted a report with a huge date range—no sanitization—and our `ReportJob` tried to load terabytes of data. CPU spiked, threads stalled, and everything ground to a halt. Killing and restarting Sidekiq pods simply requeued the same job, and the outage persisted. We needed a way to isolate that single problematic worker.


## Introducing a “Quarantine” Queue

The idea is simple: route suspect jobs into a low-concurrency queue serviced by a dedicated Sidekiq process. They’re still retried, but can’t block your high-priority queues.


### 1. Moving jobs to the quarantine queue manually

We begin by intercepting job enqueuing and swapping their queue name if they match an ENV-driven “quarantine” list:

```ruby
class QuarantineMiddleware
  def call(worker, job, queue, redis_pool)
    if ENV.fetch('QUARANTINED_JOBS', '').split(';').include?(job['class'])
      job['queue'] = 'quarantine'
    end
    yield
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware { |chain| chain.add QuarantineMiddleware }
end
```
Set
```
QUARANTINED_JOBS=ReportJob;MegaLoopJob
```
to start shunting those jobs into quarantine.

[Inspired by this deep-dive on isolating memory-leak jobs.](https://www.youtube.com/watch?v=bvdWPGQ8cEA&t=229s).


### 2. Handling Infinite Loops on Restart
That client middleware only works on new enqueues; it can’t catch jobs Sidekiq auto-requeues on shutdown. To trap long-running jobs after a pod restart, we use a server middleware:

```ruby
class LongRunningJobInterceptor
  QUARANTINE_QUEUE = 'quarantine'

  def call(worker, job, queue)
    jid = job['jid']
    if queue != QUARANTINE_QUEUE && should_quarantine?(jid)
      # Requeue safely into quarantine
      worker.class.set(queue: QUARANTINE_QUEUE).perform_async(*job['args'])
      return
    end

    track_start(jid)
    begin
      yield
    rescue Sidekiq::Shutdown
      raise
    ensure
      untrack(jid)
    end
  end

  private

  def should_quarantine?(jid)
    start_time = Sidekiq.redis { |r| r.get("job:#{jid}:started_at").to_time }
    (Time.current - start_time) > 1.hour
  end

  def track_start(jid)
    Sidekiq.redis { |r| r.set("job:#{jid}:started_at", Time.current) }
  end

  def untrack(jid)
    Sidekiq.redis { |r| r.del("job:#{jid}:started_at") }
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware { |chain| chain.add LongRunningJobInterceptor }
end
```

Now, whenever you restart Sidekiq, any job that had been running “too long” automatically moves into your quarantine queue instead of clogging default or critical queues.

### 3. Automating Detection & Restart

Maintaining a list of known bad actors is helpful, but it still leaves you manually updating ENV variables and restarting processes when things go awry. What if we could automate both detection and remediation of runaway jobs?
Let’s watch for runaway jobs and trigger a graceful process restart.

#### 3.a Why Not Simple Timeouts?

Some teams rely on hard timeouts (`Sidekiq::JobTimeout`) or even OS-level kills. Unfortunately, these can:

- Abort mid-transaction, leaving partial writes or queued messages.
- Leak resources (DB connections, file handles), causing pool exhaustion.

#### 3.b Soft Timeout Monitoring

Instead of killing the job mid-flight, let’s signal our orchestrator to restart the entire Sidekiq process, then quarantine repeat offenders on the next run.

1. Track job start times in a shared registry.
2. Periodically scan for jobs exceeding a configurable threshold (e.g. 2 minutes).
3. Flag the Sidekiq process as unhealthy (e.g. by touching a file).
4. Let Kubernetes or Systemd detect the unhealthy marker and recycle the pod or service.

```ruby
class SidekiqMonitor
  HEALTH_FILE = Rails.root.join('tmp/sidekiq_unhealthy').freeze

  def self.start
    Thread.new(name: 'sidekiq-monitor') do
      loop do
        RunningJobs.list.each do |job|
          if Time.current - job[:started_at] > 2.minutes
            FileUtils.touch(HEALTH_FILE)
            break
          end
        end
        sleep 1
      end
    end
  end
end

class RunningJobs
  @jobs = Concurrent::Map.new

  def call(worker, job, queue)
    @jobs[Thread.current.object_id] = { jid: job['jid'], started_at: Time.current }
    yield
  ensure
    @jobs.delete(Thread.current.object_id)
  end

  def self.list
    @jobs.values
  end
end

# In config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.server_middleware { |chain| chain.add RunningJobs }
  SidekiqMonitor.start
end
```

- Kubernetes (or Systemd) watches `tmp/sidekiq_unhealthy` and gracefully restarts the process.

- On restart, our `LongRunningJobInterceptor` (from step 2) reroutes any job that previously ran too long into the quarantine queue.


## Conclusion

By combining:

1. Client-side queue rerouting (for future enqueues),
2. Server-side interception (for jobs requeued on shutdown), and
3. Automated health monitoring with liveness probes,

you can ensure that one rogue Sidekiq job never brings down your entire background pipeline.