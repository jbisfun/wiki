# Static wiki from the docs/ of every repo in the pull workspace.
# The work is done by the `wiki` binary (src/); this only installs and wires it up.

set shell := ["bash", "-euo", "pipefail", "-c"]

wiki := "cargo run --release --quiet --"

default: build

# Install the client packages rolldown bundles (bootstrap, clipboard) and jsdoc.
install:
    pnpm install --frozen-lockfile

# Site in dist/; only repos whose sources changed (by git object id) are regenerated.
build: install
    {{wiki}} build

# Rebuild everything, ignoring .build/state.json.
rebuild: install
    {{wiki}} build --force

# Build and stage the site in ../jbisfun.github.io (used by the pull precommit hook).
publish: install
    {{wiki}} publish

# Build and serve dist/ on localhost.
serve port="8000": build
    python3 -m http.server {{port}} --directory dist

clean:
    {{wiki}} clean
