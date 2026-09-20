#!/bin/bash
# Checks the direction the other tools do not: the links pointing INTO this repo
# from the live Udemy course.
#
# check.sh and check_links.sh both bind a handout to ITSELF — its shape, its
# hygiene, the URLs inside it. None of them knows the 38 live lecture links
# exist. Rename or move a handout and every one of those links 404s for students
# while every other check in this repo still reports ALL CLEAN. That is a gate
# written where the files are rather than where the risk is.
#
# So this reads udemy-links.tsv — the captured live link set — and asserts:
#   1. every linked path still exists as a file in this repo
#   2. every linked URL still resolves (200, and not a soft-404 page)
#   3. every handout on disk is actually linked from some lecture
#
# Regenerate udemy-links.tsv from the instructor API after changing any lecture
# resource; a stale manifest is itself a finding this cannot see.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MAN=udemy-links.tsv
PAGES=https://abohmeed.github.io/devcloudlab-fluxcd-handouts/handouts/
BLOB=https://github.com/abohmeed/devcloudlab-fluxcd-handouts/blob/main/handouts/

[ -f "$MAN" ]   || { echo "FATAL: $MAN is missing — the live link set is unknown"; exit 2; }
[ -d handouts ] || { echo "FATAL: handouts/ does not exist"; exit 2; }
rows=$(grep -vc '^#' "$MAN")
[ "$rows" -ge 38 ] || { echo "FATAL: $MAN holds $rows rows, expected 38+ — it did not load"; exit 2; }

fail=0
linked_files=$(mktemp)

echo "== 1. does every linked path still exist in the repo? =="
while IFS=$'\t' read -r idx lecture asset host path; do
  case "$idx" in \#*|"") continue;; esac
  # the live URL ends .html (Pages renders the .md); the file on disk is .md
  src="handouts/${path%.html}.md"
  [ "$host" = "G" ] && src="handouts/$path"
  echo "$src" >> "$linked_files"
  if [ ! -f "$src" ]; then
    echo "  BROKEN  lecture $lecture (idx $idx) -> $src does not exist"
    fail=1
  fi
done < "$MAN"
[ $fail -eq 0 ] && echo "  all linked paths present"

echo
echo "== 2. does every linked URL still resolve? =="
n=0; bad=0
while IFS=$'\t' read -r idx lecture asset host path; do
  case "$idx" in \#*|"") continue;; esac
  url="$PAGES$path"; [ "$host" = "G" ] && url="$BLOB$path"
  n=$((n+1))
  # 429 is rate limiting, not link rot — github.com returns it when this loop
  # runs hot. Retry with backoff; if it persists, it is reported as a FAILURE
  # rather than a pass, because "we could not find out" must never render as
  # green. Re-run when the limit clears.
  for attempt in 1 2 3; do
    code=$(curl -sS -o /tmp/.llb$$ -w '%{http_code}' -L --max-time 20 \
           -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0 Safari/537.36' "$url" 2>/dev/null)
    [ "$code" = "429" ] || break
    sleep $((attempt * 4))
  done
  if [ "$code" = "429" ]; then
    echo "  RATE-LIMITED  lecture $lecture -> $url (not verified; re-run later)"
    bad=$((bad+1)); fail=1; continue
  fi
  # host X = a link that is MEANT to 404, because the lecture teaches what a
  # missing target looks like. Asserted in both directions: if it starts
  # resolving, the lesson has quietly stopped demonstrating its point. There are
  # none today; the mechanism exists so the first one is declared, not skipped.
  if [ "$host" = "X" ]; then
    if [ "$code" = "200" ]; then
      echo "  UNEXPECTEDLY LIVE  lecture $lecture -> $url (declared as a deliberate 404)"; bad=$((bad+1)); fail=1
    fi
  elif [ "$code" != "200" ]; then
    echo "  HTTP $code  lecture $lecture -> $url"; bad=$((bad+1)); fail=1
  elif grep -qi '404: Page not found\|<title>Page not found' /tmp/.llb$$ 2>/dev/null; then
    # GitHub Pages serves its 404 page with a 200 in some configurations
    echo "  SOFT-404   lecture $lecture -> $url"; bad=$((bad+1)); fail=1
  fi
  sleep 0.2
done < "$MAN"
rm -f /tmp/.llb$$
echo "  checked $n live URLs; $bad bad"

echo
echo "== 3. is every handout on disk actually linked from a lecture? =="
sort -u "$linked_files" > "$linked_files.s"
unlinked=$(find handouts -name '*.md' | sort | comm -23 - "$linked_files.s")
if [ -n "$unlinked" ]; then
  echo "  not linked from any lecture:"
  printf '%s\n' "$unlinked" | sed 's/^/    /'
  echo "  (two are expected: the handouts for lectures that have not published yet)"
  cnt=$(printf '%s\n' "$unlinked" | grep -c .)
  [ "$cnt" -le 2 ] || { echo "  MORE THAN THE TWO EXPECTED — a handout has lost its link"; fail=1; }
else
  echo "  every handout is linked"
fi
rm -f "$linked_files" "$linked_files.s"

echo
[ $fail -eq 0 ] && echo "LIVE LINKS OK" || echo "LIVE LINK PROBLEMS FOUND"
exit $fail
