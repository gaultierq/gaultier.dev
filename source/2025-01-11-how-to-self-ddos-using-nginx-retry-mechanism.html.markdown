---

title: Self DDOS-ing with long-running requests and Nginx 
date: 2025-01-11 17:59 UTC
tags: 

---

# Self DDOS-ing with long-running requests and Nginx

What if I told you that a single Nginx setting turned a long running request into a self-DoS?
That's exactly what happened on our cluster… Here's a breakdown of what happened.


## The Incident

Last week, our monitoring alerted us to a sudden CPU spike on the database node. The culprit: long-running SQL queries triggered when customers generated PDF reports for their dashboards.

Instead of enqueueing these tasks as background jobs, our Rails app processed them synchronously within the request lifecycle. Since report generation can take up to 40 minutes, frustrated users refreshed their browsers after a few seconds—triggering new requests and compounding the load.

Over time, these repeated attempts exhausted both web and database resources, degrading performance cluster-wide.


## Investigation

I reproduced the issue by generating a report myself. 
After about three minutes, my browser returned a 504 Gateway Timeout. 
Curious about where that timeout lived, I inspected our Nginx Ingress Controller settings and found: 

```nginx
proxy_read_timeout 60s;
proxy_next_upstream_tries 3;
```

Here’s what happened:

1. A request hits Nginx and is proxied to our Rails app.
2. If no response arrives within 60 seconds, Nginx retries—up to three times.
3. Meanwhile, the Rails process keeps generating the report for its full duration.
4. Frustrated users hit refresh, spawning new requests on top of Nginx’s retries.


The result? Each report could be processed 3 times per user refresh, quickly overwhelming the cluster.

## The Fix

While moving report generation to a background job remains the long-term solution, we needed a quick mitigation to prevent another CPU spike.
We decided to deactivate Nginx’s retry logic temporarily. By reducing tries from three to none, we could immediately cut the redundant load by two-thirds.

```yaml
# Ingress annotations
nginx.ingress.kubernetes.io/proxy-next-upstream-tries: "1"
```

## Bonus: a Cautionary AI Tale

Eager for a quick fix, I turned to ChatGPT for advice. 
It confidently recommended `proxy_next_upstream_tries: 0`, which I assumed would disable retries completely.
However, the Nginx docs revealed that setting this value to 0 actually causes Nginx to retry the request infinitely every 60 seconds. The change sent our CPU usage through the roof until I reverted the Helm chart.


## Next Steps

- Asynchronous Processing: Refactor report generation into background jobs with progress notifications.
- Timeouts and Circuit Breakers: Implement application-level timeouts to fail fast.
- User Feedback: Show a progress indicator and prevent manual refreshes during long-running tasks.

This incident reinforced how a small misconfiguration in Nginx can amplify inherent flaws in application design. A careful read of documentation and a temporary tweak saved us from another spike—while we work on the long-term fix.





