#!/bin/bash
# Mechanical checks on every handout in the repo.
#
# Three rules here were WRONG when first written and flagged good handouts.
# They are kept deliberately narrow, with the reason, so nobody re-broadens them:
#   * exclamation marks are banned in PROSE, not in shebangs or sample values;
#   * a conceptual lecture legitimately has no code block — only a lecture whose
#     video is a demo owes the student something copyable;
#   * "runbook" as a plain English word is legitimate student content.
#
# Do NOT run this while writer agents are still working — you will read a
# half-written file and report a defect that does not exist.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

MASTHEAD='<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>'
FOOTIMG='<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>'
FOOTCTA='<a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>'

# --- prove the instrument is pointed at something ---------------------------
# Without this, a missing or empty handouts/ printed "0 handouts checked /
# ALL CLEAN" and exited 0 — a green result from a run that read nothing. Every
# section must exist and hold at least one handout, so deleting a directory is
# a failure rather than a silently smaller corpus.
REQUIRED_SECTIONS="s01 s02 s03 s04 s05 s06 s07"
[ -d handouts ] || { echo "FATAL: handouts/ does not exist — nothing was checked"; exit 2; }
for s in $REQUIRED_SECTIONS; do
  [ -d "handouts/$s" ] || { echo "FATAL: handouts/$s is missing — the corpus is not what this check covers"; exit 2; }
  c=$(find "handouts/$s" -name '*.md' | wc -l | tr -d ' ')
  [ "$c" -gt 0 ] || { echo "FATAL: handouts/$s holds no handouts"; exit 2; }
done
total=$(find handouts -name '*.md' | wc -l | tr -d ' ')
[ "$total" -ge 40 ] || { echo "FATAL: found $total handouts, expected at least 40 — corpus shrank"; exit 2; }

fail=0
printf "%-58s %6s  %s\n" FILE WORDS ISSUES
for f in $(find handouts -name '*.md' | sort); do
  w=$(wc -w < "$f" | tr -d ' ')
  issues=""

  # --- shape ------------------------------------------------------------
  head -1 "$f" | grep -q '^---$'            || issues="${issues}no-frontmatter "
  grep -q '^title: "'   "$f"                || issues="${issues}no-title "
  grep -q '^kicker: "FLUX CD · SECTION ' "$f" || issues="${issues}no-kicker "
  grep -q '^description: "' "$f"            || issues="${issues}no-description "
  # The footer blocks are indented inside <p align="center">, so match the line
  # anywhere, not as a whole line. `grep -Fqx` here reported all 40 files as
  # missing a footer logo that every one of them had.
  grep -Fq "$MASTHEAD" "$f"                 || issues="${issues}NO-MASTHEAD "
  grep -Fq "$FOOTIMG"  "$f"                 || issues="${issues}NO-FOOTER-LOGO "
  grep -Fq "$FOOTCTA"  "$f"                 || issues="${issues}NO-FOOTER-CTA "

  # Headings are counted OUTSIDE fenced code only — a `# comment` line in a bash
  # block is not a second H1. Counting them naively flagged 11 good files.
  nh1=$(awk '/^```/{c=!c; next} !c && /^# /{n++} END{print n+0}' "$f")
  [ "$nh1" -ge 1 ] || issues="${issues}no-h1 "
  [ "$nh1" -le 1 ] || issues="${issues}MULTIPLE-H1 "

  # frontmatter title and the H1 must be the same string
  ft=$(sed -n 's/^title: "\(.*\)"$/\1/p' "$f" | head -1)
  h1=$(grep -m1 '^# ' "$f" | sed 's/^# //')
  [ "$ft" = "$h1" ] || issues="${issues}TITLE-MISMATCH "

  # body = after the frontmatter; prose = body minus fenced code
  body=$(awk 'f{print} /^---$/{c++; if(c==2) f=1}' "$f")
  prose=$(printf '%s\n' "$body" | awk '/^```/{c=!c; next} !c')

  # --- student-facing hygiene -------------------------------------------
  printf '%s\n' "$body" | grep -qiE '\b(show that you|as you saw|off-camera|the producer|re-record|reset the demo|screen guide|instructor runbook|demo_runbook|demo_agent)\b' \
    && issues="${issues}INSTRUCTOR-LEAK "
  printf '%s\n' "$body" | grep -qE '/Volumes/PCF|pcfv2|2026-update|_handouts-repo|/tmp/claude-' \
    && issues="${issues}PRIVATE-PATH "
  printf '%s\n' "$body" | grep -qE '\bS[0-9]{2}[ -]L[0-9]{2}\b' \
    && issues="${issues}LESSON-ID-IN-PROSE "
  printf '%s\n' "$prose" | grep -q '!' && issues="${issues}exclamation "

  # --- facts this course got wrong before -------------------------------
  # A removed apiVersion is only a defect when the handout PRESCRIBES it — i.e.
  # on an `apiVersion:` line inside a fenced block a student would copy. Naming
  # one in prose is how the "Since this video was recorded" notes and the whole
  # migration lecture do their job, and flagging that flagged five correct files.
  # ...and a block introduced as the "Before:" half of a before/after pair is
  # exempt, because showing the removed apiVersion IS the teaching point there.
  # Without this the migration lecture — the one handout whose whole job is the
  # old APIs — is the only file the rule can never pass.
  prescribed=$(awk '
    /^```/ {
      # No \b here: BSD awk does not support it, and a rule that silently
      # matches nothing is worse than no rule.
      if (!c) { c=1; exempt = (prev ~ /^(\*\*)?(Before|Old|Previously|Deprecated)[^a-zA-Z]/) }
      else    { c=0 }
      next
    }
    c && /^[[:space:]]*apiVersion:/ && !exempt { print }
    !c && NF { prev=$0 }
  ' "$f")
  printf '%s\n' "$prescribed" | grep -qE 'helm\.toolkit\.fluxcd\.io/v2beta[12]'      && issues="${issues}DEAD-HELM-API "
  printf '%s\n' "$prescribed" | grep -qE 'source\.toolkit\.fluxcd\.io/v1beta[12]'    && issues="${issues}DEAD-SOURCE-API "
  printf '%s\n' "$prescribed" | grep -qE 'kustomize\.toolkit\.fluxcd\.io/v1beta[12]' && issues="${issues}DEAD-KUSTOMIZE-API "
  printf '%s\n' "$prescribed" | grep -qE 'notification\.toolkit\.fluxcd\.io/v1beta2' && issues="${issues}DEAD-NOTIF-API "
  # Weave GitOps is discontinued. Naming it is fine ONLY alongside the reason.
  grep -qi 'weave gitops' "$f" \
    && ! grep -qiE 'shut down|discontinued|no longer|replaced|Flux Operator' "$f" \
    && issues="${issues}DEAD-WEAVE-GITOPS "
  grep -qE 'apt-key add' "$f" \
    && ! grep -qiE 'since this video was recorded|removed in|deprecated' "$f" \
    && issues="${issues}DEAD-APT-KEY "

  # --- secret-shaped strings --------------------------------------------
  # A handout must never print anything that LOOKS like a live credential,
  # even as a made-up example: GitHub's push protection blocks the push, and a
  # reader cannot tell a realistic fake from the real thing. Placeholders are
  # written in angle brackets. Caught on the first push attempt, by a Slack
  # token shape that was entirely fictional.
  grep -qE 'xox[baprs]-[A-Za-z0-9]{8,}|ghp_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{15,}|AKIA[0-9A-Z]{16}|hooks\.slack\.com/services/[A-Z0-9]{6,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' "$f" \
    && issues="${issues}SECRET-SHAPED-STRING "

  # A `kind: Secret` with a populated base64 `data:` block trips GitHub push
  # protection too, and a course that teaches secrets has these legitimately.
  # `stringData:` with an obvious placeholder is fine; real-looking base64 is not.
  # A handout SHOULD show the real shape of a dockerconfigjson, so the rule is not
  # "no base64" — it is "the base64 must decode to something visibly fake". The
  # first version of this flagged the private-registry handout, whose blob decodes
  # to REPLACE_ME:REPLACE_ME and is documented as a placeholder two lines above.
  for blob in $(awk '/^```/{c=!c;next} c' "$f" \
      | awk '/kind: Secret/{s=1} s&&/^[[:space:]]*data:/{d=1;next}
             d&&/^[[:space:]]+[A-Za-z0-9._-]+:[[:space:]]*[A-Za-z0-9+\/]{24,}={0,2}[[:space:]]*$/{print $2}'); do
    dec=$(printf '%s' "$blob" | base64 -d 2>/dev/null)
    printf '%s' "$dec" | grep -qiE 'REPLACE_ME|PLACEHOLDER|CHANGE_?ME|EXAMPLE|<your|your-(user|token|password)|dXNlcm5hbWU' \
      || issues="${issues}BASE64-SECRET-DATA "
  done

  # --- the handout's own job --------------------------------------------
  printf '%s\n' "$body" | grep -qE 'https?://' || issues="${issues}no-references "
  [ "$w" -ge 350 ] || issues="${issues}THIN($w) "
  [ "$w" -le 3000 ] || issues="${issues}BLOATED($w) "

  # image paths must resolve from the file's own directory
  for img in $(grep -o 'src="[^"]*"' "$f" | sed 's/src="//; s/"//' | sort -u); do
    case "$img" in http*) continue;; esac
    [ -e "$(dirname "$f")/$img" ] || issues="${issues}BROKEN-IMG($img) "
  done

  [ -z "$issues" ] && issues="clean" || fail=1
  printf "%-58s %6s  %s\n" "${f#handouts/}" "$w" "$issues"
done

echo
n=$(find handouts -name '*.md' | wc -l | tr -d ' ')
echo "$n handouts checked"
[ $fail -eq 0 ] && echo "ALL CLEAN" || echo "ISSUES FOUND"
exit $fail
