---

title: sidekiq-buggy-jobs
date: 2025-04-08 19:46 UTC
tags: 

---


# How to Stop a Buggy Sidekiq Job from Hogging Your App

Imagine this: you have a background job that works fine most of the time—but for a very specific set of inputs, it goes rogue and starts hammering your database with thousands of queries.

That happened to us.

A user filled out a report form with a *very large* time range. There was no input sanitization, and that input ended up kicking off a job that queried way more data than we expected.

## The Problem

The job didn't just run long—it essentially took over the CPU. It blocked other threads and starved more important jobs from running.

We tried restarting the Sidekiq process, but it didn’t help. The job would just get requeued and picked up again after the restart, repeating the same destructive behavior.

So we asked ourselves: **how do we prevent one buggy job from breaking everything else?**

## Sidekiq Job Timeouts: Not the Best Fix

One option is to use a timeout. If a job takes too long, you kill it. But that has its own problems:

- **It’s unreliable.**
- **It doesn't allow for cleanup.**

If the thread gets killed mid-way, it might not release the database connection. If you have a limited DB connection pool, this can quickly cascade into connection exhaustion—affecting other jobs and parts of your app.

## A Better Solution: The Quarantine Queue

What we really wanted was a "quarantine queue." If a job starts misbehaving, we want to move it somewhere safe for analysis and debugging.

Here’s the ideal flow:

1. A job runs.
2. If it's taking too long or using too many resources, we *gracefully* stop it.
3. Instead of retrying it in the same queue, we move it to a **quarantine queue** for further inspection.

The dream would be for Sidekiq to automatically detect a SIGINT shutdown and move in-progress jobs to a quarantine queue before exiting. But Sidekiq doesn’t offer a hook at that moment—it’s too late in the shutdown process to do anything fancy.

## What We Did Instead

We took a more proactive approach:

- We set a **global timeout threshold** in our app logic.
- If a job runs longer than that threshold, we *manually restart* the Sidekiq process.
- When the job starts again (because Sidekiq requeues it), we detect that it's a repeat offender—and move it to the quarantine queue **at the start of execution**, *before* it does anything dangerous.

This way, we protect the system from runaway jobs **without losing important cleanup steps**, and we isolate problematic inputs for debugging.

## Key Takeaways

- A single bad job shouldn't be allowed to bring down your system.
- Timeouts alone aren’t enough if they leave things half-finished.
- Having a **quarantine strategy** for suspicious jobs gives you better visibility and safety.
- Sometimes, letting a job restart *intentionally* can be your best defense—if you're ready to catch it on the second run.

