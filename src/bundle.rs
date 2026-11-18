//! Client assets into dist/_assets: rolldown (embedded) bundles and minifies
//! assets/main.js with its npm imports; lightningcss bundles assets/style.css
//! (Bootstrap via @import) plus syntect's CSS for the highlight classes.
use std::fs;
use std::path::Path;

use anyhow::{Context, Result, anyhow};
use lightningcss::bundler::{Bundler as CssBundler, FileProvider};
use lightningcss::stylesheet::{MinifyOptions, ParserOptions, PrinterOptions};
use rolldown::{Bundler, BundlerOptions, InputItem, OutputFormat, RawMinifyOptions};
use syntect::highlighting::ThemeSet;
use syntect::html::{ClassStyle, css_for_theme_with_class_style};

use crate::Paths;
use crate::markdown::HIGHLIGHT_PREFIX;
use crate::state::{self, State};

pub fn bundle(paths: &Paths, state: &mut State) -> Result<()> {
    let out = paths.dist.join("_assets");
    let mut inputs = state::dir_ids(&paths.wiki.join("assets"));
    inputs.push(state::file_id(&paths.wiki.join("pnpm-lock.yaml")));
    inputs.push(state::file_id(&std::env::current_exe()?));
    let key = state::key(inputs);
    if state.assets == key && out.join("main.js").is_file() && out.join("style.css").is_file() {
        return Ok(());
    }
    if out.exists() {
        fs::remove_dir_all(&out)?;
    }
    fs::create_dir_all(&out)?;
    javascript(paths, &out)?;
    fs::write(out.join("style.css"), stylesheet(&paths.wiki.join("assets/style.css"))?)?;
    state.assets = key;
    Ok(())
}

fn javascript(paths: &Paths, out: &Path) -> Result<()> {
    let mut bundler = Bundler::new(BundlerOptions {
        input: Some(vec![InputItem { name: Some("main".into()), import: "./assets/main.js".into() }]),
        cwd: Some(paths.wiki.clone()),
        dir: Some(out.to_string_lossy().into_owned()),
        format: Some(OutputFormat::Esm),
        minify: Some(RawMinifyOptions::Bool(true)),
        ..Default::default()
    })
    .map_err(|errors| anyhow!("rolldown: {errors:?}"))?;
    let runtime = tokio::runtime::Runtime::new()?;
    let output = runtime
        .block_on(bundler.write())
        .map_err(|errors| anyhow!("rolldown: {errors:?}"))?;
    for warning in output.warnings {
        crate::warn(format_args!("rolldown: {warning:?}"));
    }
    Ok(())
}

fn stylesheet(entry: &Path) -> Result<String> {
    let provider = FileProvider::new();
    let mut bundler = CssBundler::new(&provider, None, ParserOptions::default());
    let mut sheet = bundler
        .bundle(entry)
        .map_err(|err| anyhow!("lightningcss: {err}"))
        .with_context(|| format!("bundling {}", entry.display()))?;
    sheet.minify(MinifyOptions::default()).map_err(|err| anyhow!("lightningcss: {err}"))?;
    let mut css = sheet
        .to_css(PrinterOptions { minify: true, ..PrinterOptions::default() })
        .map_err(|err| anyhow!("lightningcss: {err}"))?
        .code;
    let themes = ThemeSet::load_defaults();
    let style = ClassStyle::SpacedPrefixed { prefix: HIGHLIGHT_PREFIX };
    for (scheme, theme) in [("light", "InspiredGitHub"), ("dark", "base16-ocean.dark")] {
        let rules = css_for_theme_with_class_style(&themes.themes[theme], style)?;
        css.push_str(&format!("\n@media (prefers-color-scheme: {scheme}) {{\n{rules}}}\n"));
    }
    Ok(css)
}
