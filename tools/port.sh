#!/bin/bash
# Ports one source handout into the repo's branded Markdown shape.
#
#   tools/port.sh <sec> <lesson> <title> <source.md> <slug>
#
# It only reshapes: frontmatter, the DevCloudLab masthead, one H1, and the
# closing call-to-action. The body is copied through untouched, minus whatever
# H1 the source already carried (the shape supplies exactly one).
#
# The masthead and footer are written into the MARKDOWN, not into the Jekyll
# layout, because the lecture links point at github.com, where no layout runs.
# A handout has to be branded when GitHub renders it raw.
set -euo pipefail

sec="$1"; les="$2"; title="$3"; src="$4"; slug="$5"
repo="$(cd "$(dirname "$0")/.." && pwd)"
dst="$repo/handouts/$sec/$les-$slug.md"
mkdir -p "$(dirname "$dst")"

secnum=$((10#${sec#s})); lesnum=$((10#${les#l}))

# Body = source minus its own first H1 and minus any leading blank lines.
body="$(awk 'BEGIN{done=0} /^# /&&!done{done=1;next} {print}' "$src" \
        | awk 'NF{f=1} f')"

# A one-line description for <meta> and for the Pages lede: the first real
# sentence of the body, capped. Falls back to the title.
desc="$(printf '%s\n' "$body" \
        | awk '/^[A-Za-z]/{print; exit}' \
        | cut -c1-175 | sed -E 's/ [^ ]*$//; s/[,;:]$//' | sed 's/"/\\"/g')"
[ -n "$desc" ] || desc="$title"

{
  printf -- '---\n'
  printf 'title: "%s"\n' "$(printf '%s' "$title" | sed 's/"/\\"/g')"
  printf 'kicker: "FLUX CD · SECTION %s · LECTURE %s"\n' "$secnum" "$lesnum"
  printf 'description: "%s"\n' "$desc"
  printf -- '---\n\n'

  printf '<a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="72"></a>\n\n'
  printf '# %s\n\n' "$title"
  printf '*Section %s, Lecture %s — from the **Flux CD** course by [DevCloudLab](https://devcloudlab.com).*\n\n' "$secnum" "$lesnum"
  printf -- '---\n\n'

  printf '%s\n' "$body"

  printf '\n---\n\n'
  printf '<p align="center">\n'
  printf '  <a href="https://devcloudlab.com"><img src="../../assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="88"></a>\n'
  printf '</p>\n\n'
  printf '<p align="center">\n'
  printf '  <strong>Built by DevCloudLab</strong><br>\n'
  printf '  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>\n'
  printf '  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>\n'
  printf '</p>\n'
} > "$dst"

echo "$dst"
