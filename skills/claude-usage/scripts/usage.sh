#!/usr/bin/env bash
# Show Claude subscription usage limits (5-hour session, weekly) for the
# Anthropic account Pi is logged into.
# Usage: usage.sh [--json] [--color] [--input FILE]
#   --input FILE  render a saved --json response instead of calling the API
set -euo pipefail

json=0 color=0 input=
while (( $# )); do
  case $1 in
    --json)  json=1 ;;
    --color) color=1 ;;
    --input) input=${2:?--input needs a file}; shift ;;
    *) echo "usage: usage.sh [--json] [--color] [--input FILE]" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "error: $*" >&2; exit 1; }

needs=(jq); [[ -z "$input" ]] && needs+=(pi curl)
for bin in "${needs[@]}"; do
  command -v "$bin" >/dev/null || die "$bin is required"
done

# The endpoint is rate limited: reuse a response younger than 60s, and fall back
# to an older cached one (with a note) if a request fails.
umask 077
cache="${TMPDIR:-/tmp}/claude-usage-cache-$(id -u).json"
cache_age() { echo $(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || stat -c %Y "$cache" 2>/dev/null || echo 0) )); }

# Sets $resp on success; sets $err to a readable reason on failure.
fetch() {
  local token body code
  token=$(pi auth print-bearer-token --provider anthropic 2>/dev/null) || {
    err="Pi has no Anthropic OAuth login. Sign in with a Claude Pro/Max subscription (/login)."; return 1; }
  body=$(mktemp)
  code=$(curl -sS --max-time 15 -o "$body" -w '%{http_code}' https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null) || code=000
  resp=$(<"$body"); rm -f "$body"
  case $code in
    200)     printf '%s' "$resp" > "$cache"; return 0 ;;
    401|403) err="Anthropic rejected the login. Sign in again (/login)." ;;
    429)     err="Rate limited by Anthropic. Try again in a minute." ;;
    000)     err="Couldn't reach api.anthropic.com." ;;
    *)       err="Request failed (HTTP $code)." ;;
  esac
  return 1
}

if [[ -n "$input" ]]; then
  resp=$(<"$input")
elif [[ -s "$cache" ]] && (( $(cache_age) < 60 )); then
  resp=$(<"$cache")
elif ! fetch; then
  [[ -s "$cache" ]] || die "$err"
  echo "note: $err Showing data from $(( $(cache_age) / 60 ))m ago." >&2
  resp=$(<"$cache")
fi

if (( json )); then echo "$resp" | jq .; exit 0; fi

# --color: mid-tone ANSI 256 colors, readable on light and dark themes.
# Every segment sets its own color, because a host may wrap the output in its own color.
echo "$resp" | jq -r --argjson color "$color" '
  def c(n): if $color == 1 then "\u001b[38;5;\(n)m" + . + "\u001b[39m" else . end;
  def plain: if $color == 1 then "\u001b[39m" + . else . end;   # terminal default fg
  def dim: c(244);
  def level(p): if p >= 80 then 167 elif p >= 50 then 172 else 71 end;
  def pct: (. // 0) | round | [., 0] | max;
  def pad(n): . + (" " * ([n - length, 0] | max) // "");
  def ts: if . == null then null else sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdate end;
  def rel: if . == null then "" else
      (. - now) as $s
      | def two(a; ua; b; ub): "\(a)\(ua)" + (if b > 0 then " \(b)\(ub)" else "" end);
        if $s <= 0 then "(resets now)"
        elif $s < 60 then "(resets in <1m)"
        elif $s < 3600 then "(resets in \($s/60|floor)m)"
        elif $s < 86400 then "(resets in " + two($s/3600|floor; "h"; ($s%3600)/60|floor; "m") + ")"
        else "(resets in " + two($s/86400|floor; "d"; ($s%86400)/3600|floor; "h") + ")" end end;
  def bar(p): ([p/5|floor, 20] | min) as $n
    | ("█" * $n // "" | c(level(p))) + ("░" * (20 - $n) // "" | dim);
  # amounts are in minor units (cents): 21548 with 2 decimals -> "215.48"
  def money(d): (. // 0 | round) as $v | (pow(10; d) | round) as $m
    | if d == 0 then "\($v)"
      else "\($v / $m | floor).\(($v % $m | tostring) as $f | ("0" * (d - ($f|length)) // "") + $f)" end;
  def name:
    if .kind == "session" then "5-hour session"
    elif .kind == "weekly_all" then "Weekly (all models)"
    elif .kind == "weekly_scoped" then "Weekly (\(.scope.model.display_name // "model"))"
    else .kind // "limit" | gsub("_"; " ") | (.[0:1] | ascii_upcase) + .[1:] end;

  [ ((.limits // [])[]
      | {label: name, p: (.percent | pct), detail: (.resets_at | ts | rel),
         tag: (if .severity == null or .severity == "normal" then null else .severity end)}),
    (.extra_usage // {} | select(.is_enabled == true)
      | (.decimal_places // 2) as $d | (.currency // "") as $cur
      | {label: "Extra usage",
         p: (if (.monthly_limit // 0) > 0
             then (.utilization // (100 * (.used_credits // 0) / .monthly_limit)) | pct
             else null end),
         detail: (if (.monthly_limit // 0) > 0
                  then "(\(.used_credits | money($d)) / \(.monthly_limit | money($d)) \($cur))"
                  else "(\(.used_credits | money($d)) \($cur) used, no limit)" end),
         tag: (if .spend_limit_reached == true then "limit reached" else null end)})
  ] as $rows
  | ($rows | map(.label | length) | max // 0) as $w
  | ("Claude plan usage" | c(68)),
    (if ($rows | length) == 0 then ("  No limits reported." | dim) else empty end),
    ($rows[] | .p as $p |
       ("  " + (.label | pad($w + 4)) | plain)
       + (if $p == null then ""
          else bar($p) + " " + ($p | tostring | ("  " + .)[-3:] + "%" | c(level($p))) + " " end)
       + (.detail | dim)
       + (if .tag then "  " + ("[\(.tag)]" | c(167)) else "" end)),
    (if ([.seven_day_breakdown.rows // [] | .[] | select(.percent > 0)] | length) > 0 then
       ("  Weekly breakdown: " | dim)
       + ([.seven_day_breakdown.rows[] | select(.percent > 0) | "\(.display_name) \(.percent)%"] | join(", ") | dim)
     else empty end)
'
