#!/usr/bin/env bash
# Publish one or more files to the prancer-review-pages GitHub Pages site via git.
#
# Usage:  scripts/publish.sh "<commit message>" <file> [<file> ...]
#   Files are given as paths relative to the repo root (e.g. dayli-home.html,
#   assets/dayli-home/hero.jpg). They must already be copied into the repo.
#
# What it does: stages the files, commits, rebases on origin/main so the push
# is a thin pack, pushes, then polls the live URL of each .html file until
# GitHub Pages serves the new content (matched by git blob hash in a comment
# is not possible, so it matches on file size via Content-Length when
# available, otherwise just waits for a 200 after a short delay).
#
# Env: PUBLISH_NO_WAIT=1 skips the deploy poll.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="https://amybuchstaber-star.github.io/prancer-review-pages"

if [ $# -lt 2 ]; then
  echo "usage: $0 \"<commit message>\" <file> [<file> ...]" >&2
  exit 2
fi
MSG="$1"; shift

cd "$REPO_ROOT"
for f in "$@"; do
  [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
  git add -- "$f"
done

if git diff --cached --quiet; then
  echo "nothing to commit (files unchanged)"; exit 0
fi

git -c user.name="${GIT_AUTHOR_NAME:-Amy Buchstaber}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-amybuchstaber@gmail.com}" \
    commit -q -m "$MSG"
git fetch -q origin main
git rebase -q origin/main
git push -q origin HEAD:main
echo "pushed: $(git rev-parse --short HEAD)"

[ "${PUBLISH_NO_WAIT:-0}" = "1" ] && exit 0

# Poll GitHub Pages until each HTML file is served at its new size.
for f in "$@"; do
  case "$f" in *.html) ;; *) continue ;; esac
  want=$(wc -c < "$f" | tr -d ' ')
  url="$BASE_URL/$f"
  for i in $(seq 1 16); do
    sleep 15
    got=$(curl -sI "$url" | awk 'tolower($1)=="content-length:"{print $2}' | tr -d '\r')
    if [ "$got" = "$want" ]; then echo "LIVE: $url"; continue 2; fi
  done
  echo "WARNING: $url did not reach the new size ($want bytes) in 4 min; check manually" >&2
done
