#!/usr/bin/env bash
# Ask pull for the workspace repos and print a JSON manifest of the ones
# that have a docs/ folder: [{name, path, branch, head, web}].
set -euo pipefail

root="${PULL_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
skip="${WIKI_SKIP:-jbisfun.github.io}"

cd "$root"
pull status --json |
  jq -r --arg skip "$skip" '
    ($skip | split(",")) as $skipped
    | .repos[]
    | select(.cloned and (.name | IN($skipped[]) | not))
    | [.name, .path, (.branch // "main"), (.head // "")] | @tsv' |
  while IFS=$'\t' read -r name path branch head; do
    [[ -d "$path/docs" ]] || continue
    origin="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    # https://github.com/o/r(.git) or git@github.com:o/r(.git) -> https://github.com/o/r
    web="$(sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#https://github.com/\1#p' <<<"${origin%.git}")"
    jq -n --arg name "$name" --arg path "$path" --arg branch "$branch" --arg head "$head" --arg web "$web" \
      '{name: $name, path: $path, branch: $branch, head: $head, web: (if $web == "" then null else $web end)}'
  done |
  jq -s --arg root "$root" '{root: $root, repos: .}'
