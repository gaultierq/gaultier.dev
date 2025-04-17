---

title: The sidekiq quarantine queue 
date: 2025-04-08 19:46 UTC
tags: rails, sidekiq

---
# How to Stop a Buggy Sidekiq Job from Hogging Your App

[This video](https://www.youtube.com/watch?v=bvdWPGQ8cEA&t=229s) explores the idea of using a quarantine queue to isolate problematic Sidekiq jobs—a concept that inspired this article.

Sidekiq is a powerful tool for background processing, but even the best systems can get tripped up by a single bad job. What happens when a job goes rogue? Maybe it enters an infinite loop, triggers a memory leak, or hammers your database with an unexpected N+1 query. These bugs are often subtle, introduced during development, and only manifest under specific inputs or load conditions.

So: **how do you stop a single misbehaving job from taking down your app?**

## Why You Might Need a Quarantine Queue

A quarantine queue is a dedicated Sidekiq queue where you can isolate jobs that are known (or suspected) to cause problems. The goal is to prevent one bad job from degrading the performance or stability of your entire background job system.

Here are a few scenarios where a quarantine queue can help:

- A job triggers a **missing index or N+1 query**, overloading your database.
- A job enters an **infinite loop**, and hangs forever, preventing other jobs to be picked  
- A job causes a **memory leak**, slowly killing your workers.
- A new deployment introduces a **regression** that makes a specific job 10x longer for certain inputs.

Mistakes happen—especially during development. But when they hit production, you need a strategy that protects the rest of your system.

## A Real-World Example

Here’s something that actually happened to us.

A user filled out a report form with a *very large* time range. There was no input sanitization, and that led to a `ReportJob` being enqueued that queried **a massive amount of data**.

The job didn’t just run long—it choked the system. It used excessive CPU, blocked other threads, and starved more critical jobs from running. We restarted the Sidekiq process (pod), but the job just got picked up again and repeated the same behavior.

We asked ourselves: **how can we prevent a single job from breaking everything else?**

## Why Timeouts Aren’t Enough

One option is to use job timeouts. Kill the job if it runs too long.

But timeouts come with their own set of issues:

- **They’re unreliable** — the job might get killed mid-way, leaving things half-done.
- **They can cause resource leaks** — for example, if the job held onto a DB connection and didn’t release it.

If your DB connection pool is small, one leaked connection can snowball into widespread failure across your app.

## A Better Approach: The Quarantine Queue

What we really wanted was a way to catch problematic jobs **before** they can do damage.

Imagine this flow:

1. A job starts running.
2. If it's detected as a repeat offender (based on input or context), we move it to a **quarantine queue**.
3. That queue runs in isolation and doesn’t affect the rest of your app.

Sidekiq doesn't offer a shutdown hook where you can intercept in-progress jobs before they're killed. So, we had to get creative.

## What We Did Instead

We implemented a proactive strategy:

- We set a **soft timeout threshold** in our app logic.
- If a job exceeds that threshold, we **manually restart** the Sidekiq process.
- When Sidekiq requeues the job after the restart, we **detect** that it’s a repeat offender.
- At the start of the job execution, we check its input and **move it to the quarantine queue** if needed—**before it does any real work**.

This lets us:

- Prevent cascading failures.
- Preserve cleanup logic.
- Debug bad jobs in isolation.

## Key Takeaways

- A single bad job **shouldn’t** be allowed to bring down your app.
- A **quarantine queue** gives you visibility, safety, and a path to resolution.
- Sometimes, letting a job restart *intentionally* is the best move—if you're prepared to catch it the second time.

---

Having a quarantine strategy in your Sidekiq setup is like having an airlock in your spaceship. You isolate the threat before it spreads—and keep the rest of your system breathing easy.
