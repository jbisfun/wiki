# Static wiki from the docs/ of every repo in the pull workspace.
# `wiki` (src/, Zig) is the generator, the live server and the MCP server; this
# file installs the npm side (esbuild, bootstrap, clipboard, jsdoc) and wires it up.

set shell := ["bash", "-euo", "pipefail", "-c"]

wiki := "zig-out/bin/wiki"

default: build

# Install the client packages esbuild bundles (bootstrap, clipboard), esbuild itself and jsdoc.
deps:
    pnpm install --frozen-lockfile

# The binary in zig-out/bin.
compile:
    zig build

# Site in <workspace>/.pull/wiki/dist; only repos whose sources changed (by git object id) are regenerated.
build: deps compile
    {{wiki}} build

# Rebuild everything, ignoring the build state.
rebuild: deps compile
    {{wiki}} build --force

# Build and stage the site in ../jbisfun.github.io (the pull precommit hook runs `wiki publish`).
publish: deps compile
    {{wiki}} publish

# Serve the live site with the forge features (the workspace's `wiki` pull job does this on 8090).
serve listen="127.0.0.1:8090": deps compile
    {{wiki}} serve --listen {{listen}}

clean:
    {{wiki}} clean

test:
    zig build test

# Install the release binary to ~/.local/bin.
install:
    zig build -Doptimize=ReleaseSafe --prefix ~/.local
