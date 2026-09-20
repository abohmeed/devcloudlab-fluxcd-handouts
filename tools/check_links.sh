#!/bin/bash
# Verifies every reference URL in the handouts.
#
# A 200 is NOT sufficient. Docs sites keep moved pages live as stubs that read
# "This page has moved" and still return 200 — a link to one is dead for a
# reader even though every status check passes. So this greps the body too.
#
# Placeholder and illustrative hosts are expected to fail and are skipped.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# Illustrative and non-HTML endpoints are expected to fail and are skipped:
#   - github.com/example/*, hooks.slack.com/services/T123... : invented samples
#   - token.actions.githubusercontent.com : an OIDC issuer, not a web page
#   - stefanprodan.github.io/podinfo : a Helm repo index, 404s at /
#   - anything containing $( : a fragment of a shell command, not a URL
SKIP='example\.com|example-org|github\.com/example/|your-org|<your|my-org|localhost|127\.0\.0\.1|192\.168\.|cluster\.local|kubernetes\.default|:6443|\{|\$\(|registry\.gitlab\.com/<|ghcr\.io/<|hooks\.slack\.com/services/|token\.actions\.githubusercontent\.com|stefanprodan\.github\.io/podinfo|^https://$'

bad=0; n=0
tmp=$(mktemp)
for u in $(grep -rho 'https://[^)"`, <]*' handouts/ README.md 2>/dev/null \
          | sed 's/[.,;:]*$//' | sort -u); do
  echo "$u" | grep -qE "$SKIP" && continue
  n=$((n+1))
  code=$(curl -sS -o "$tmp" -w '%{http_code}' -L --max-time 20 -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36' "$u" 2>/dev/null)
  note=""
  case "$code" in
    200)
      if grep -qi 'this page has moved\|page has been moved\|no longer maintained' "$tmp"; then
        note="STUB (moved)"; bad=$((bad+1))
      fi
      ;;
    *) note="HTTP $code"; bad=$((bad+1)) ;;
  esac
  [ -n "$note" ] && printf '  %-18s %s\n' "$note" "$u"
  sleep 0.3
done
rm -f "$tmp"

echo
echo "checked $n URLs; $bad bad"
[ "$bad" -eq 0 ] && echo "all reference links good" || echo "BAD LINKS FOUND"
exit $bad
