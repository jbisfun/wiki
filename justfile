# Static wiki from the docs/ of every repo in the pull workspace.

set shell := ["bash", "-euo", "pipefail", "-c"]

build_dir := ".build"
site := build_dir / "site"

default: build

# Install node dependencies (parcel, bootstrap, markdown-it, ejs).
install:
    pnpm install --frozen-lockfile

# Ask pull for the workspace repos and write the manifest.
collect:
    mkdir -p {{build_dir}}
    bin/collect.sh > {{build_dir}}/manifest.json

# Code reference per repo: rustdoc, LDoc, JSDoc into .build/api.
apidoc: collect
    bin/apidoc.sh {{build_dir}}/manifest.json {{build_dir}}/api > {{build_dir}}/api.json

# Render READMEs, markdown and EJS pages into .build/site, with the code reference.
render: apidoc
    node src/render.js {{build_dir}}/manifest.json {{build_dir}}/api.json {{build_dir}}/api {{site}}

# Bundle Bootstrap CSS and JS with parcel, then assemble dist/.
bundle:
    pnpm exec parcel build assets/style.css assets/main.js --dist-dir {{build_dir}}/assets --no-source-maps --no-content-hash --no-autoinstall
    rsync -a --delete {{site}}/ dist/
    rsync -a {{build_dir}}/assets/ dist/_assets/

# Full site in dist/.
build: install render bundle

# Build and stage the site in ../jbisfun.github.io (used by the pull precommit hook).
publish: build
    bin/publish.sh

# Build and serve dist/ on localhost.
serve port="8000": build
    python3 -m http.server {{port}} --directory dist

clean:
    rm -rf {{build_dir}} dist .parcel-cache
