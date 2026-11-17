#!/usr/bin/env bash
# Generate code docs for every repo in the manifest with the language's own
# tool, into OUT/<repo>/<tool>/, and print {repo: [{tool, title, path}]}
# (path relative to OUT/<repo>) for render.js.
#   rust: cargo doc --no-deps (rustdoc)   lua: LDoc   js: JSDoc
# A tool that is missing or fails only warns: the site still builds.
# Usage: bin/apidoc.sh MANIFEST OUT
set -euo pipefail

wiki="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$(realpath "$1")"
out="$(realpath -m "$2")"
mkdir -p "$out"

warn() { echo "wiki: $*" >&2; }
entry() { jq -nc --arg repo "$1" --arg tool "$2" --arg title "$3" --arg path "$4" '{$repo, $tool, $title, $path}'; }
# Tracked files matching the config's `files` (dirs and globs) or the default pathspecs.
files_for() {
  local path="$1" cfg="$2"; shift 2
  local -a specs
  mapfile -t specs < <(jq -r '(.files // empty)[]' <<<"$cfg")
  ((${#specs[@]})) || specs=("$@")
  git -C "$path" ls-files -- "${specs[@]}"
}

rust() {
  local name="$1" path="$2" cfg="$3" dest="$out/$1/rust"
  [[ -f $path/Cargo.toml ]] || return 0
  command -v cargo >/dev/null || { warn "$name: cargo not found, skipping rustdoc"; return 0; }
  local -a args=(doc --no-deps --quiet)
  local pkg
  for pkg in $(jq -r '(.packages // [])[]' <<<"$cfg"); do args+=(-p "$pkg"); done
  # The repo's own target dir, so dependency metadata is shared with its builds.
  local target
  target="$(cd "$path" && cargo metadata --format-version 1 --no-deps | jq -r .target_directory)"
  (cd "$path" && cargo "${args[@]}") || { warn "$name: cargo doc failed"; return 0; }
  mkdir -p "$dest"
  rsync -a --delete "$target/doc/" "$dest/"
  sed -nE 's/^window\.ALL_CRATES = (.*);$/\1/p' "$dest/crates.js" | jq -r '.[]' |
    while read -r crate; do entry "$name" rust "$crate" "rust/$crate/index.html"; done
}

lua() {
  local name="$1" path="$2" cfg="$3" dest="$out/$1/lua"
  # *.x.lua are preprocessed ycode hook scripts, not plain Lua modules.
  local -a files
  mapfile -t files < <(files_for "$path" "$cfg" '*.lua' ':!:*.x.lua')
  ((${#files[@]})) || return 0
  # LDoc only documents `---` comments; without any there is nothing to show.
  (cd "$path" && grep -qE '^\s*---' -- "${files[@]}") || return 0
  command -v ldoc >/dev/null || { warn "$name: ldoc not found (apt install lua-ldoc), skipping"; return 0; }
  local conf="$out/$name/config.ld"
  rm -rf "$dest" && mkdir -p "$dest"
  {
    # JSON strings double as Lua string literals. "backtick": Debian ships LDoc
    # without its markdown module, so only `code` spans are formatted.
    jq -nr --arg name "$name" --arg dest "$dest" '"project = \($name | @json)\ntitle = \("\($name) Lua API" | @json)\ndir = \($dest | @json)\nformat = \"backtick\""'
    printf '%s\n' "${files[@]/#/$path/}" | jq -Rnr '"file = {", (inputs | "  \(@json),"), "}"'
  } >"$conf"
  local log
  log="$(ldoc --testing -c "$conf" . 2>&1)" || { warn "$name: ldoc failed"; echo "$log" >&2; return 0; }
  rm -f "$conf"
  entry "$name" lua "$name" "lua/index.html"
}

js() {
  local name="$1" path="$2" cfg="$3" dest="$out/$1/js"
  [[ -f $path/package.json ]] || return 0
  local -a files
  mapfile -t files < <(files_for "$path" "$cfg" '*.js' '*.mjs')
  ((${#files[@]})) || return 0
  (cd "$path" && grep -qF '/**' -- "${files[@]}") || return 0
  # jsdoc.json drops the generation date, so unchanged code gives unchanged pages.
  local jsdoc="$wiki/node_modules/.bin/jsdoc"
  [[ -x $jsdoc ]] || { warn "$name: jsdoc not installed (just install), skipping"; return 0; }
  rm -rf "$dest" && mkdir -p "$(dirname "$dest")"
  local log
  log="$(cd "$path" && "$jsdoc" -c "$wiki/jsdoc.json" -d "$dest" "${files[@]}" 2>&1)" || { warn "$name: jsdoc failed"; echo "$log" >&2; return 0; }
  entry "$name" js "$name" "js/index.html"
}

jq -c '.repos[]' "$manifest" |
  while read -r repo; do
    name="$(jq -r .name <<<"$repo")"
    path="$(jq -r .path <<<"$repo")"
    for tool in rust lua js; do
      cfg="$(jq -c --arg t "$tool" '.config[$t] // {}' <<<"$repo")"
      [[ $cfg == false ]] && continue
      "$tool" "$name" "$path" "$cfg"
    done
  done |
  jq -s 'group_by(.repo) | map({(.[0].repo): map(del(.repo))}) | add // {}'
