#!/usr/bin/env bash
# Mirror dist/ into the GitHub Pages repo and stage it, so the pull
# precommit hook lands the site in the same `pull commit`.
set -euo pipefail

wiki="$(cd "$(dirname "$0")/.." && pwd)"
target="${WIKI_PUBLISH_DIR:-${PULL_ROOT:-$(dirname "$wiki")}/jbisfun.github.io}"

rsync -a --delete --exclude .git --exclude CNAME --exclude README.md "$wiki/dist/" "$target/"
touch "$target/.nojekyll"
git -C "$target" add -A .
echo "wiki: published to $target ($(git -C "$target" diff --cached --name-only | wc -l) files staged)"
