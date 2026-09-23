#!/usr/bin/env bash
# Show Claude subscription usage limits (5-hour session, weekly) for the
# Anthropic account Pi is logged into.
# Usage: usage.sh [--json] [--color]
set -euo pipefail

json=0 color=0
for a in "$@"; do
  case $a in
    --json)  json=1 ;;
    --color) color=1 ;;
    *) echo "usage: usage.sh [--json] [--color]" >&2; exit 2 ;;
  esac
done

for bin in pi curl jq; do
  command -v "$bin" >/dev/null || { echo "error: $bin is required" >&2; exit 1; }
done

# The endpoint is rate limited: reuse a response younger than 60s, and fall back
# to an older cached one (with a note) if the API refuses.
umask 077
cache="${TMPDIR:-/tmp}/claude-usage-cache-$(id -u).json"
cache_age() { echo $(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0) )); }

if [[ -s "$cache" ]] && (( $(cache_age) < 60 )); then
  resp=$(<"$cache")
else
  token=$(pi auth print-bearer-token --provider anthropic 2>/dev/null) || {
    echo "error: Pi has no Anthropic OAuth login. Sign in with a Claude Pro/Max subscription (/login)." >&2; exit 1; }

  if resp=$(curl -sS --fail-with-body --max-time 15 https://api.anthropic.com/api/oauth/usage \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" 2>&1); then
    printf '%s' "$resp" > "$cache"
  elif [[ -s "$cache" ]]; then
    echo "note: API request failed, showing data from $(( $(cache_age) / 60 ))m ago" >&2
    resp=$(<"$cache")
  else
    echo "error: request failed: $resp" >&2; exit 1
  fi
fi

if (( json )); then echo "$resp" | jq .; exit 0; fi

# --color: mid-tone ANSI 256 colors, readable on light and dark themes.
# Every segment sets its own color, because a host may wrap the output in its own color.
echo "$resp" | jq -r --argjson color "$color" '
  def c(n): if $color == 1 then "\u001b[38;5;\(n)m" + . + "\u001b[39m" else . end;
  def plain: if $color == 1 then "\u001b[39m" + . else . end;   # terminal default fg
  def dim: c(244);
  def level(p): if p >= 80 then 167 elif p >= 50 then 172 else 71 end;
  def ts: if . == null then null else sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdate end;
  def rel: if . == null then "" else
      (. - now) as $s
      | if $s <= 0 then "(resets now)"
        elif $s < 3600 then "(resets in \($s/60|floor)m)"
        elif $s < 86400 then "(resets in \($s/3600|floor)h \(($s%3600)/60|floor)m)"
        else "(resets in \($s/86400|floor)d \(($s%86400)/3600|floor)h)" end end;
  def bar(p): ([p/5|floor, 20] | min) as $n
    | (("█" * $n) // "" | c(level(p))) + (("░" * (20 - $n)) // "" | dim);
  def pretty: {session:"5-hour session", weekly_all:"Weekly (all models)",
               weekly_opus:"Weekly (Opus)", weekly_sonnet:"Weekly (Sonnet)"}[.] // .;
  def sev: if . == "normal" or . == null then "" else "  " + ("[\(.)]" | c(167)) end;

  ("Claude plan usage" | c(68)),
  (.limits[]? | .percent as $p |
     ("  " + (.kind | pretty | . + " " * 30 | .[0:22]) | plain) + " "
     + bar($p) + " "
     + ($p | tostring | ("  " + .)[-3:] + "%" | c(level($p)))
     + " " + (.resets_at | ts | rel | dim)
     + (.severity | sev)),
  (if .extra_usage.is_enabled then
     "  Extra usage: \(.extra_usage.used_credits // 0) / \(.extra_usage.monthly_limit // "?") \(.extra_usage.currency // "")" | plain
   else empty end),
  (if (.seven_day_breakdown.rows // []) | length > 0 then
     ("  Weekly breakdown: " | dim)
     + ([.seven_day_breakdown.rows[] | select(.percent > 0) | "\(.display_name) \(.percent)%"] | join(", ") | dim)
   else empty end)
'
