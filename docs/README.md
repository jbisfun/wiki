# wiki

`wiki` turns the `docs/` folder of every repo in a [pull](https://github.com/jbisfun/pull) workspace into one static site, published at <https://jbisfun.github.io>.

## How it works

1. `bin/collect.sh` runs `pull status --json` and, with `jq`, writes a manifest of every cloned repo that has a `docs/` folder.
2. `src/render.js` renders each page into `.build/site/<repo>/...`. mdBook projects (a `docs/book.toml`) use the book's `src` folder.
   - `*.md` with [markdown-it](https://github.com/markdown-it/markdown-it) (front matter via gray-matter, `{#id}` heading attributes, highlight.js at build time).
   - `*.ejs` with [EJS](https://ejs.co): PHP-style `<% code %>` / `<%= escaped %>` / `<%- raw %>` tags.
   - Every other file is copied as an asset.
   - Links to `.md` files become `.html`; links to files outside `docs/` go to GitHub.
3. [Parcel](https://parceljs.org) bundles Bootstrap 5 and the one small JS module (mobile sidebar toggle) into `dist/_assets`.
4. `bin/publish.sh` mirrors `dist/` into the `jbisfun.github.io` repo with rsync and stages it.

## Commands

```sh
just build     # pnpm install, collect, render, bundle into dist/
just publish   # build, then copy into ../jbisfun.github.io and git add
just serve     # build and serve dist/ on http://localhost:8000
just clean
```

Environment: `PULL_ROOT` (workspace root, default `..`), `WIKI_SKIP` (comma-separated repos to leave out, default `jbisfun.github.io`), `WIKI_TITLE`, `WIKI_PUBLISH_DIR`.

## pull hook

The workspace `pullfile.plist` runs `just publish` as a `precommit` hook, so `pull commit` lands the regenerated site in `jbisfun.github.io` in the same commit and `pull push` deploys it to GitHub Pages.

See [Templating](templating.md) for writing pages.
