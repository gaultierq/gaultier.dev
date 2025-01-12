---

title: Long-running requests and Nginx 
date: 2025-01-11 17:59 UTC
tags: 

---

Last week, I encountered an issue that caused unnecessary strain on our backend system. 
While the system stayed operational, this incident highlighted how a small configuration detail can significantly impact performance. 
Here's what happened.


## The incident

Our system was running on a Kubernetes cluster managed. Alerts suddenly indicated 100% CPU usage on the node hosting the database.
Quickly, the team could find suspicious requests that performs some heavy SQL calculation. 
One of our endpoint was performing 40 min of heavy SQL calculation **synchronously**.


This specific request is triggered when one customer request a yearly report on one of its specific dashboard.
The report was generated synchronously, and could take up to 40 minutes. 
Meaning that when the user ask for this report, he would watch a loader spinning for the next 40 minutes before seeing any result.
Hundreds of SQL transactions are sent to the database throughout this process. 
And of course after a few seconds the user would ask for another report. All these request would add up, eventually exhausting our system resources.

## The investigation

I tried it myself, generated a new yearly report and saw what happened. After 3 minutes, my browser received a 504 proxy timeout error.
Where is this timeout configured ? By digging into our nginx controller configuration, I found a nice: `proxy_read_timeout  60s;`
After reading a little more the configuration, I found: `proxy_next_upstream_tries 3;`

Oh, that’s intriguing! Essentially, when a user requests a report, Nginx forwards the request to our Rails application, 
which then inundates the database with queries. 
If there’s no response within 60 seconds, Nginx retries and sends the request to the backend a second time, and then a third time.

A 40-minute request is certainly a design flaw, but having our ingress controller exacerbate the issue by tripling the load is counterproductive to our team’s efforts.


Here's an improved version of your section:

---

## The Recovery Plan

The team quickly agreed that report generation should be handled asynchronously using a background job. 
However, implementing this solution would take several days, and we needed an immediate fix to prevent another CPU spike. 
To mitigate the issue temporarily, we decided to deactivate the Nginx retry mechanism. 
While this wouldn’t fully resolve the problem, it would reduce the load by two-thirds.

To achieve this, I decided to update our Nginx configuration. 
Rather than diving into the documentation myself, I opted to consult ChatGPT for guidance. 
The AI confidently suggested setting `proxy_next_upstream_tries 0;` to disable the retry mechanism entirely. 
Sounded simple enough, right?

I updated the ingress annotations accordingly and waited for the Nginx pods to reload their configuration. 
Then I ran a new test, expecting to see the request fail with a 504 error after 60 seconds. 
But to my surprise, the request didn’t time out. It continued running for 1, 2, 3, 4 minutes... 
Meanwhile, the database load began to rise again.

Realizing something was wrong, I quickly rolled back the Helm chart and deleted all the web pods, which restored the CPU usage to normal. 
Disaster averted—barely.

I went back to the Nginx documentation and finally read the relevant section properly. Here's what I found:

```
Limits the time during which a request can be passed to the next server. The 0 value turns off this limitation.
```

That’s when it hit me: by setting `proxy_next_upstream_tries` to `0`, I had configured Nginx to retry requests indefinitely! 
Every 60 seconds, Nginx would resend the request to our backend, compounding the problem exponentially. 
A single user’s request could have overwhelmed our resources entirely.

The fix? I updated the configuration to set `proxy_next_upstream_tries` to `1`, ensuring that Nginx would only retry the request once. 
After 60 seconds, the request would fail gracefully with a 504 error, preventing the backend from being overwhelmed.

---

### Key Learnings:

1. Always read the documentation carefully before making changes.
2. Test configuration updates in a staging environment before deploying them to production.
3. Be cautious with retry mechanisms in systems handling long-running or resource-intensive requests.


