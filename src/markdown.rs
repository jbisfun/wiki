//! Markdown for docs from many repos (comrak): GFM tables, autolinks, smart
//! punctuation, `{#id}` heading attributes, syntect highlighting at build
//! time (CSS classes, bat's syntaxes, no client JS), and `data-sourcepos` on
//! every block so Radar can map a selection back to its source line. Links are rewritten
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

    /// Home page blurb: the first sentence of the first paragraph as plain
    /// text (link and emphasis text kept, markup dropped), cut at its first
    /// top-level comma, semicolon or colon when it runs past `BLURB` chars.
    pub fn blurb(&self, source: &str) -> Option<String> {
        const BLURB: usize = 80;
        let arena = Arena::new();
        let root = parse_document(&arena, &preprocess(source), &self.options);
        let paragraph = root
            .descendants()
            .find(|node| matches!(node.data().value, NodeValue::Paragraph))?;
        let mut text = String::new();
        for node in paragraph.descendants() {
            match &node.data().value {
                NodeValue::Text(t) => text.push_str(t),
                NodeValue::Code(code) => text.push_str(&code.literal),
                NodeValue::SoftBreak | NodeValue::LineBreak => text.push(' '),
                _ => {}
            }
        }
        let text = text.trim();
        let end = [text.find(". ").map(|at| at + 1), text.find('。').map(|at| at + '。'.len_utf8())]
            .into_iter()
            .flatten()
            .min()
            .unwrap_or(text.len());
        let sentence = text[..end].trim();
        if sentence.is_empty() {
            return None;
        }
        // CJK characters are about two Latin ones wide.
        let width: usize = sentence.chars().map(|ch| if ch >= '\u{2E80}' { 2 } else { 1 }).sum();
        if width > BLURB {
            let mut depth = 0;
            for (at, ch) in sentence.char_indices() {
                match ch {
                    '(' | '[' | '（' | '「' => depth += 1,
                    ')' | ']' | '）' | '」' => depth -= 1,
                    ',' | ';' | ':' if depth == 0 => return Some(format!("{}.", &sentence[..at])),
                    '，' | '；' | '：' if depth == 0 => return Some(format!("{}。", &sentence[..at])),
                    _ => {}
                }
            }
        }
        Some(sentence.to_owned())
    }
}

/// Join soft line breaks between CJK characters (outside code blocks): a
/// browser renders a newline as a space, which CJK text doesn't have.
pub fn join_cjk_lines(source: &str) -> String {
    static BREAK: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"([\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}，。；：、！？）」』])\n[ \t]*([\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}（「『])")
            .expect("valid regex")
    });
    let mut out = String::with_capacity(source.len());
    let mut fenced = false;
    let mut prose = String::new();
    for line in source.split_inclusive('\n') {
        if line.trim_start().starts_with("```") || line.trim_start().starts_with("~~~") {
            if !fenced {
                out.push_str(&BREAK.replace_all(&prose, "$1$2"));
                prose.clear();
            }
            fenced = !fenced;
            out.push_str(line);
        } else if fenced {
            out.push_str(line);
        } else {
            prose.push_str(line);
        }
    }
    out.push_str(&BREAK.replace_all(&prose, "$1$2"));
    out
}

/// Replace the mdBook preprocessor commands used by the zed docs
/// (`{#kb action}` / `{#action action}`) with code spans.
fn preprocess(source: &str) -> String {
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

const HEADINGS: &str = "h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]";

/// Ids of the headings in rendered HTML, in document order.
pub fn heading_ids(html: &str) -> Result<Vec<String>> {
    let ids = std::cell::RefCell::new(Vec::new());
    let settings = RewriteStrSettings::new().append_element_content_handler(element!(HEADINGS, |el| {
        ids.borrow_mut().extend(el.get_attribute("id"));
        Ok(())
    }));
    rewrite_str(html, settings)?;
    Ok(ids.into_inner())
}

/// Give the headings of `html` the ids `ids` (in order) and point their `#`
/// links there too, so a translated page keeps the English anchors that links
/// from other pages use. Left alone when the heading counts differ.
pub fn set_heading_ids(html: &str, ids: &[String]) -> Result<String> {
    let current = heading_ids(html)?;
    if current.len() != ids.len() || current == ids {
        return Ok(html.to_owned());
    }
    let map: std::collections::HashMap<&str, &str> = current.iter().map(String::as_str).zip(ids.iter().map(String::as_str)).collect();
    let map = &map;
    let settings = RewriteStrSettings::new()
        .append_element_content_handler(element!(HEADINGS, move |el| {
            if let Some(id) = el.get_attribute("id").and_then(|id| map.get(id.as_str()).copied()) {
                el.set_attribute("id", id)?;
            }
            Ok(())
        }))
        .append_element_content_handler(element!("a[href^='#']", move |el| {
            if let Some(id) = el.get_attribute("href").and_then(|href| map.get(&href[1..]).copied()) {
                el.set_attribute("href", &format!("#{id}"))?;
            }
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
