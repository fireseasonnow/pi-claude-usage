---
name: claude-usage
description: Check Claude subscription usage limits (5-hour session and weekly percentages, reset times) for the Anthropic account Pi is logged into. Use when asked about Claude usage, quota, rate limits, remaining plan allowance, or the equivalent of Claude Code's /usage.
---

# Claude usage

Run the bundled script (relative to this skill directory):

```sh
bash scripts/usage.sh          # formatted summary
bash scripts/usage.sh --json   # raw API response
```

(`--color` adds ANSI colors for the `/usage` command; don't use it here.)

The script gets a bearer token with `pi auth print-bearer-token --provider anthropic` and queries `https://api.anthropic.com/api/oauth/usage`, the undocumented endpoint behind Claude Code's `/usage`. It needs `curl` and `jq`.

The endpoint is rate limited (HTTP 429), so responses are cached for 60s. If the API fails, the script falls back to the cache and prints a note on stderr.

The tool result is already visible to the user, so don't repeat the output verbatim. Summarize it in a sentence (percent used and time until reset per limit) unless asked for more. Never print the bearer token.

For per-session tokens and cost in Pi, point the user to the footer or `/session`. This skill covers plan limits only.

If it fails with an auth error, the user needs to sign in to Pi with a Claude Pro/Max subscription (`/login`). If the response shape changed, run with `--json` and summarize `.limits[]` manually.
