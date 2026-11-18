//! Markdown for docs from many repos (comrak): GFM tables, autolinks, smart
//! punctuation, `{#id}` heading attributes, syntect highlighting at build
//! time (CSS classes, bat's syntaxes, no client JS), and `data-sourcepos` on every block so
//! Radar can map a selection back to its source line. Links are rewritten
//! afterwards with lol_html, which covers markdown and raw HTML alike.
use std::sync::LazyLock;

use anyhow::Result;
use comrak::nodes::NodeValue;
use comrak::options::Plugins;
use comrak::plugins::syntect::{SyntectAdapter, SyntectAdapterBuilder};
use comrak::{Arena, Options, parse_document};
use lol_html::{RewriteStrSettings, element, rewrite_str};
use regex::Regex;

/// Class prefix of highlighted tokens; the bundle generates the matching CSS.
pub const HIGHLIGHT_PREFIX: &str = "hl-";

pub static SCHEME: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^([a-z][a-z0-9+.-]*:|//|#)").expect("valid regex"));

pub struct Markdown {
    options: Options<'static>,
    highlighter: SyntectAdapter,
}

impl Markdown {
    pub fn new() -> Self {
        let mut options = Options::default();
        let extension = &mut options.extension;
        extension.table = true;
        extension.strikethrough = true;
        extension.autolink = true;
        extension.tasklist = true;
        extension.footnotes = true;
        extension.header_attributes = true;
        extension.header_id_prefix = Some(String::new());
        extension.front_matter_delimiter = Some("---".into());
        options.parse.smart = true;
        options.render.r#unsafe = true;
        options.render.attributes = true;
        options.render.sourcepos = true;
        // bat's syntax set (two-face): syntect's defaults lack TOML, TypeScript, Zig, ...
        let highlighter = SyntectAdapterBuilder::new()
            .syntax_set(two_face::syntax::extra_newlines())
            .css_with_class_prefix(HIGHLIGHT_PREFIX)
            .build();
        Self { options, highlighter }
    }

    /// HTML of a markdown document (front matter is skipped; source positions
    /// count from the document's first line).
    pub fn render(&self, source: &str) -> String {
        let mut plugins = Plugins::default();
        plugins.render.codefence_syntax_highlighter = Some(&self.highlighter);
        comrak::markdown_to_html_with_plugins(&preprocess(source), &self.options, &plugins)
    }

    /// Plain text of the first paragraph with text (not just badges), for the home page cards.
    pub fn first_paragraph(&self, source: &str) -> Option<String> {
        let arena = Arena::new();
        let root = parse_document(&arena, &preprocess(source), &self.options);
        root.descendants().find_map(|node| {
            if !matches!(node.data().value, NodeValue::Paragraph) {
                return None;
            }
            let text: String = node
                .children()
                .map(|child| match &child.data().value {
                    NodeValue::Text(text) => text.to_string(),
                    NodeValue::Code(code) => code.literal.clone(),
                    NodeValue::SoftBreak => " ".into(),
                    _ => String::new(),
                })
                .collect();
            let text = text.trim();
            (!text.is_empty()).then(|| text.to_owned())
        })
    }
}

/// Replace the mdBook preprocessor commands used by the zed docs
/// (`{#kb action}` / `{#action action}`) with code spans.
pub fn preprocess(source: &str) -> String {
    static COMMAND: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\{#(?:kb|action)\s+([^}]+)\}").expect("valid regex"));
    COMMAND.replace_all(source, |found: &regex::Captures| format!("`{}`", found[1].trim())).into_owned()
}

/// Rewrite every `a[href]` / `img[src]` through `resolve` (None keeps the
/// link) and give tables Bootstrap's look.
pub fn rewrite_links(html: &str, resolve: impl Fn(&str) -> Option<String>) -> Result<String> {
    let resolve = &resolve;
    let settings = RewriteStrSettings::new()
        .append_element_content_handler(element!("a[href]", move |el| {
            if let Some(link) = el.get_attribute("href").and_then(|href| resolve(&href)) {
                el.set_attribute("href", &link)?;
            }
            Ok(())
        }))
        .append_element_content_handler(element!("img[src]", move |el| {
            if let Some(link) = el.get_attribute("src").and_then(|src| resolve(&src)) {
                el.set_attribute("src", &link)?;
            }
            Ok(())
        }))
        .append_element_content_handler(element!("table", |el| {
            el.set_attribute("class", "table table-sm table-striped")?;
            Ok(())
        }));
    Ok(rewrite_str(html, settings)?)
}

/// Mark the links to `href` (the current page) as active.
pub fn mark_active(html: &str, href: &str) -> Result<String> {
    let settings = RewriteStrSettings::new().append_element_content_handler(element!("a[href]", |el| {
        if el.get_attribute("href").as_deref() == Some(href) {
            el.set_attribute("class", "active")?;
            el.set_attribute("aria-current", "page")?;
        }
        Ok(())
    }));
    Ok(rewrite_str(html, settings)?)
}
