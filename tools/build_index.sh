#!/bin/bash
# Regenerates README.md (what GitHub shows) and index.md (what Pages shows)
# from the handouts actually present on disk. Run it after adding or renaming
# a handout — the index is derived, never hand-edited.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

sec_title() {
  case "$1" in
    s01) echo "Introduction" ;;
    s02) echo "Getting started with Flux CD" ;;
    s03) echo "Flux CD and Helm" ;;
    s04) echo "Flux CD and Kustomize" ;;
    s05) echo "Flux CD security" ;;
    s06) echo "Image automation" ;;
    s07) echo "Flux CD notification automation" ;;
    *)   echo "$1" ;;
  esac
}

# Pulls the `title:` out of a handout's frontmatter.
title_of() {
  sed -n '2,6p' "$1" | sed -n 's/^title: "\(.*\)"$/\1/p' | head -1
}

emit_body() {
  for sec in $(find handouts -mindepth 1 -maxdepth 1 -type d | sed 's|handouts/||' | sort); do
    printf '\n## Section %s — %s\n\n' "$((10#${sec#s}))" "$(sec_title "$sec")"
    for f in $(find "handouts/$sec" -name '*.md' | sort); do
      les=$(basename "$f" | sed -n 's/^l\([0-9][0-9]\)-.*/\1/p')
      printf -- '- **%s.** [%s](%s)\n' "$((10#$les))" "$(title_of "$f")" "$f"
    done
  done
}

n=$(find handouts -name '*.md' | wc -l | tr -d ' ')

{
  cat <<'HEAD'
<p align="center">
  <a href="https://devcloudlab.com"><img src="assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="130"></a>
</p>

<h1 align="center">Flux CD — Course Handouts</h1>

<p align="center">
  The written companions to the <strong>Flux CD</strong> course by
  <a href="https://devcloudlab.com"><strong>DevCloudLab</strong></a>.<br>
  One handout per lecture: the concepts, the commands, the manifests — all copyable.
</p>

<p align="center">
  <a href="https://devcloudlab.com"><strong>→ More hands-on cloud-native courses at DevCloudLab.com</strong></a>
</p>

---

## How to use these

Each lecture in the course links to its handout here. Watch the lecture, then
keep the handout: every command and manifest is in a code block you can copy
straight out of the page with the button in its top-right corner.

Where a lecture was recorded before a tool changed, the handout gives the
**current working command** and flags what the video shows, in a note like this:

> **Since this video was recorded:** the older form no longer works on current
> versions. The command above is the current equivalent.

## Handouts
HEAD
  emit_body
  cat <<'FOOT'

---

<p align="center">
  <a href="https://devcloudlab.com"><img src="assets/img/devcloudlab-logo.png" alt="DevCloudLab" height="110"></a>
</p>

<p align="center">
  <strong>Built by DevCloudLab</strong><br>
  Hands-on cloud-native courses — Kubernetes, GitOps, CI/CD and the cloud.<br>
  <a href="https://devcloudlab.com"><strong>Visit DevCloudLab.com →</strong></a>
</p>
FOOT
} > README.md

# The Pages index reuses the same body under the site layout.
{
  printf -- '---\n'
  printf 'title: "Flux CD — Course Handouts"\n'
  printf 'kicker: "DEVCLOUDLAB · COURSE HANDOUTS"\n'
  printf 'description: "The written companions to the Flux CD course by DevCloudLab — one handout per lecture."\n'
  printf -- '---\n\n'
  sed -n '/^<p align="center">/,$p' README.md | sed 's|(handouts/\(.*\)\.md)|(handouts/\1.html)|'
} > index.md

echo "index rebuilt: $n handouts"
