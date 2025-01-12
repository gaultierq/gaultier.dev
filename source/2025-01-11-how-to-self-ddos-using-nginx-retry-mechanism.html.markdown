---

title: Self DDOS-ing with long-running requests and Nginx 
date: 2025-01-11 17:59 UTC
tags: 

---

Last week, I encountered an issue that caused a huge CPU spike on our backend system leading to congestion and potentially unhappy users. 
While the system stayed operational, this incident highlighted how a small configuration detail can significantly impact performance. 
Here's a breakdown of what happened. 


## The Incident

Our system operates on a Kubernetes cluster and was functioning normally until alerts flagged 100% CPU usage on the node hosting the database.

The team quickly identified long-running requests executing heavy SQL calculations. These requests were triggered when customers generated yearly reports for their dashboards.

Ideally, the system should delegate such intensive calculations to background jobs, allowing the requests to return immediately. 
However, the implementation was building the report synchronously (within the request lifecycle).

Since generating a report can take up to 40 minutes (a reasonable processing time for this task), users often assume the system has stalled. 
In response, they refresh the page, unintentionally triggering new requests. Over time, these repeated requests overwhelmed the system, exhausting its resources.


## The investigation

To understand the issue, I tested it myself by generating a new yearly report. After about 3 minutes, my browser encountered a 504 proxy timeout error.
Curious about whree this timeout was configured, I dug into our Nginx controller settings and found: 

```
proxy_read_timeout 60s;
proxy_next_upstream_tries 3;
```

This behavior was eye-opening! When a user requests a report, Nginx forwards the request to our Rails application, 
which then generates lots of database queries. If the backend doesn’t respond within 60 seconds, Nginx retries the request—up to three times.


In essence, our own system (Nginx) was resending requests every minute while (understandably) frustrated users were refreshing the page, sending additional requests. 
This compounded the problem, overwhelming the system from both internal retries and external user actions.

While the 40-minute request time is undeniably a design flaw that requires immediate attention, 
the **ingress controller's retry logic unintentionally magnified the issue by tripling the load**. 

This made it even harder for our team to manage the situation effectively.


## The Fix

The team quickly agreed that report generation should be handled asynchronously using a background job. 
However, implementing this solution would take several days, and we needed an immediate fix to prevent another CPU spike. 
To mitigate the issue temporarily, we decided to deactivate the Nginx retry mechanism. 
While this wouldn’t fully resolve the problem, it would reduce the load by two-thirds.

Rather than diving into the documentation myself, I opted to consult ChatGPT for guidance. 
The AI confidently suggested setting `proxy_next_upstream_tries 0;` to disable the retry mechanism entirely. 
Sounded simple enough, right?

I updated the ingress annotations accordingly and waited for the Nginx pods to reload their configuration. 
Then I ran a new test, expecting to see the request fail with a 504 error after 60 seconds. 

But to my surprise, the request didn’t time out. It continued running for 1, 2, 3, 4 minutes... 
Meanwhile, the database load began to rise again.

Realizing something was wrong, I quickly rolled back the Helm chart and deleted all the web pods, which restored the CPU usage to normal. 
Disaster (barely) averted.

I went back to the Nginx documentation and finally read the relevant section properly. Here's what I found:

```
Limits the time during which a request can be passed to the next server. The 0 value turns off this limitation.
```

That’s when it hit me: by setting `proxy_next_upstream_tries` to `0`, I had configured Nginx to retry requests indefinitely! 
Every 60 seconds, Nginx would resend the request to our backend, compounding the problem exponentially: a single user’s request could have overwhelmed our resources entirely.

The fix? I updated the configuration to set `proxy_next_upstream_tries` to `1`, ensuring that Nginx would only try the request once (no retry). 

After 60 seconds, the request did fail gracefully with a 504 error, preventing the backend from being overwhelmed.

---

### Key Learnings:

1. Double check ChatGPT answers for critical config - RTFM.
2. Test configuration updates in a staging environment before deploying them to production.
3. Be cautious with retry mechanisms in systems handling long-running or resource-intensive requests.


