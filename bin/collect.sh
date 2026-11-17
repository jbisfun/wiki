#!/usr/bin/env bash
# Ask pull for the workspace repos and print a JSON manifest of every cloned
# one, sorted by name: [{name, path, branch, head, web, readme, docs, config}],
# where config is the repo's table from wiki.toml.
set -euo pipefail

wiki="$(cd "$(dirname "$0")/.." && pwd)"
root="${PULL_ROOT:-$(dirname "$wiki")}"
skip="${WIKI_SKIP:-}"

# wiki.toml -> JSON (python's tomllib; jq has no TOML reader).
config="$(python3 -c 'import json, sys, tomllib; print(json.dumps(tomllib.load(open(sys.argv[1], "rb")).get("repos", {})))' "$wiki/wiki.toml")"

cd "$root"
pull status --json |
  jq -r --arg skip "$skip" --argjson config "$config" '
    ($skip | split(",")) as $skipped
    | .repos[]
    | select(.cloned and (.name | IN($skipped[]) | not) and ($config[.name].skip != true))
    | [.name, .path, (.branch // "main"), (.head // "")] | @tsv' |
  while IFS=$'\t' read -r name path branch head; do
    readme="$(find "$path" -maxdepth 1 -type f -iname 'readme.md' -printf '%f\n' | head -n1)"
    origin="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    # https://github.com/o/r(.git) or git@github.com:o/r(.git) -> https://github.com/o/r
    web="$(sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#https://github.com/\1#p' <<<"${origin%.git}")"
    jq -n --arg name "$name" --arg path "$path" --arg branch "$branch" --arg head "$head" \
      --arg web "$web" --arg readme "$readme" --argjson docs "$([[ -d $path/docs ]] && echo true || echo false)" \
      --argjson config "$config" \
      '{name: $name, path: $path, branch: $branch, head: $head,
        web: (if $web == "" then null else $web end),
        readme: (if $readme == "" then null else $readme end),
        docs: $docs, config: ($config[$name] // {})}'
  done |
  jq -s --arg root "$root" '{root: $root, repos: sort_by(.name | ascii_downcase)}'
