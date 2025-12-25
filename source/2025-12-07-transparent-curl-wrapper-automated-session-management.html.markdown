---

title: Testing authenticated endpoints with Claude
date: 2025-12-07 20:00 UTC
tags: claude, tip
toc: false

---

# Testing authenticated endpoints with Claude

<div class="tldr">
<strong>TL;DR</strong>: I wrap curl and share a cookie jar so Claude can test authenticated endpoints without interactive login.
</div>

While working on a backend app, I wanted Claude to be able to **test the API it’s implementing**.

Most endpoints are authenticated. Claude can run `curl`, but it can’t log in interactively or keep cookies across commands. That means it gets stuck as soon as auth is involved.

The trick is to log in once as a human, persist the session cookies, and make every curl call reuse them.

## Wrap curl

I shadow `curl` inside the project with a small wrapper:

```bash
#!/bin/sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/curl -K "$SCRIPT_DIR/.curlrc" "$@"
```

Saved as `${project_root}/bin/xcurl`, this behaves like curl but always loads a local `.curlrc`.

## Share cookies

The `.curlrc` file persists the session:

```ini
cookie-jar = "./tmp/cookies.txt"
cookie = "./tmp/cookies.txt"
location
```

Once the cookie is there, all requests are authenticated.

## Log in once

A simple `bin/login` script performs the login flow (CSRF + POST credentials) using `xcurl`, which populates the cookie jar:

```bash
bin/login admin password
```

I do this once per session.

## Make it available

I use `direnv` to add `bin/` to `PATH`:

```bash
# .envrc
PATH_add bin
```

Now when Claude runs commands in the project, it automatically uses `xcurl`.

## Usage

Claude can test authenticated endpoints directly:

```bash
xcurl http://localhost:5000/api/users
xcurl -X POST http://localhost:5000/api/sync
```

I usually document this in `CLAUDE.md` to avoid confusion:

```markdown
# Testing
- use xcurl for API calls
- if you get a 302 redirect, run `login admin password`
```

## Notes

* Cookie-based auth only
* Cookie file should not be committed

Claude can verify what it generates, yay !
