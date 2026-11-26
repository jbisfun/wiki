# Static wiki from the docs/ of every repo in the pull workspace.
# The generator is cpull's (`cpull wiki`, src/wiki in jbisfun/cpull); this repo
# holds its data, and this file only installs the npm side and wires it up.

set shell := ["bash", "-euo", "pipefail", "-c"]

# where cpull writes the site (cpull wiki honours the same variable)
dist := env_var_or_default("CPULL_WIKI_DIR", "../.pull/cpull/wiki") + "/dist"

default: build

# Install the client packages esbuild bundles (bootstrap, clipboard), esbuild itself and jsdoc.
install:
    pnpm install --frozen-lockfile

# Site in <workspace>/.pull/cpull/wiki/dist; only repos whose sources changed (by git object id) are regenerated.
build: install
    cpull wiki build

# Rebuild everything, ignoring the build state.
rebuild: install
    cpull wiki build --force

# Build and stage the site in ../jbisfun.github.io (the pull precommit hook runs `cpull wiki publish`).
publish: install
    cpull wiki publish

# Build and serve the static site on localhost (the live one, with the forge features, is
# the workspace server's /wiki/: pull cpull open --web-listen 127.0.0.1:8080).
serve port="8000": build
    python3 -m http.server {{port}} --directory {{dist}}

clean:
    cpull wiki clean
