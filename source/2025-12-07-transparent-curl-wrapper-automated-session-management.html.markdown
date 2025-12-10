---

title: Transparent curl Wrapper for Automated Session Management
date: 2025-12-07 20:00 UTC
tags: curl, testing, authentication, devops
toc: false

---

# Transparent curl Wrapper for Automated Session Management

**TL;DR**: PATH wrapper + shared .curlrc + login script = Claude can test authenticated endpoints without manual auth.

I wanted Claude to test my local web app. Problem: every API endpoint needs authentication. Claude can run curl, but can't handle interactive login or cookie management. Solution: intercept all curl commands and inject session cookies automatically.

The wrapper script lives in `${project_root}/bin/curl` and shadows the system curl via PATH. It delegates to `/usr/bin/curl` but injects `-K .curlrc` to load shared config:

```bash
#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/curl -K "$SCRIPT_DIR/../.curlrc" "$@"
```

The `.curlrc` config tells curl to read/write cookies from `./tmp/cookies.txt`:

```
cookie-jar = "./tmp/cookies.txt"
cookie = "./tmp/cookies.txt"
location
```

A separate login script (`${project_root}/bin/login`) handles the bootstrap: fetch login page, extract CSRF token, POST credentials, save session to cookie jar. From that point on, every curl command automatically includes the session cookie.

Add `bin/` to PATH via direnv:

```bash
# .envrc
PATH_add bin
```

Now the flow is simple. I run `${project_root}/bin/login admin password` once. Claude can immediately test any endpoint:

```bash
curl http://localhost:5000/api/users
curl -X POST http://localhost:5000/api/sync
```

All authenticated, no manual cookie handling. Session persists until app timeout, then re-run login. The cookie jar goes in `.gitignore` since it contains active session tokens.

This pattern works for AI e2e testing, CI/CD smoke tests, or just making API docs runnable without auth boilerplate.


Next step: Playwright MCP for full browser automation when curl isn't enough.
