# wiki

Static site built from the `docs/` folder of every repo in a [pull](https://github.com/jbisfun/pull) workspace, published to <https://jbisfun.github.io>.

pnpm, Parcel, Bootstrap 5, markdown-it, and EJS templates; shell scripts and a justfile drive the build.

```sh
just build     # dist/
just publish   # stage into ../jbisfun.github.io
```

Docs: [docs/README.md](docs/README.md), [templating](docs/templating.ejs).
