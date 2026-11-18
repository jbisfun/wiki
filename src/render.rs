//! Pages: every repo's README (its entry page) and docs/ folder, plus the
//! wiki's own pages/*.jinja, through minijinja templates (templates/).
//!
//! A repo's pages are re-rendered only when its key changed: the blob ids of
//! all its page sources, its code reference keys, its settings, and the global
//! key (templates, the repo list in the navbar, the wiki binary). `.jinja`
//! pages can show anything about the site, so they are rendered every time.
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};

use anyhow::{Context, Result};
use minijinja::value::{Serde, Value};
use minijinja::{AutoEscape, Environment, context, path_loader};
use regex::Regex;
use serde::Serialize;
use walkdir::WalkDir;

use crate::Paths;
use crate::apidoc::{Api, copy_dir};
use crate::collect::Repo;
use crate::markdown::{self, Markdown, SCHEME};
use crate::state::{self, State};

static IMAGE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\.(png|jpe?g|gif|svg|webp|avif|ico)$").expect("valid regex"));
static H1: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?m)^#\s+(.+?)\s*(\{#[^}]*\})?\s*$").expect("valid regex"));
static FRONT_MATTER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^---\r?\n([\s\S]*?)\r?\n---\r?\n?").expect("valid regex"));
static BODY_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)<body[^>]*>").expect("valid regex"));
static HEAD_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)</head>").expect("valid regex"));

/// Relative URL from one output page to another, both site-relative.
pub fn url(from: &str, to: &str) -> String {
    if SCHEME.is_match(to) {
        return to.to_owned();
    }
    let mut to = to.trim_start_matches('/').to_owned();
    if to.is_empty() || to.ends_with('/') {
        to.push_str("index.html");
    }
    let dir = Path::new(from).parent().unwrap_or(Path::new(""));
    match pathdiff::diff_paths(&to, dir) {
        Some(path) if !path.as_os_str().is_empty() => path.to_string_lossy().into_owned(),
        _ => basename(&to).to_owned(),
    }
}

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

/// Output path of a source page: README/index.md -> index.html, x.md -> x.html,
/// x.jinja -> x.html (or x as is when it has its own extension), other files as is.
fn out_name(rel: &str) -> String {
    let (dir, base) = rel.rsplit_once('/').map_or(("", rel), |(dir, base)| (dir, base));
    let lower = base.to_lowercase();
    let name = if lower == "readme.md" || lower == "index.md" {
        "index.html".to_owned()
    } else if let Some(stem) = base.strip_suffix(".md") {
        format!("{stem}.html")
    } else if let Some(stem) = base.strip_suffix(".jinja") {
        if stem.contains('.') { stem.to_owned() } else { format!("{stem}.html") }
    } else {
        base.to_owned()
    };
    if dir.is_empty() { name } else { format!("{dir}/{name}") }
}

fn is_page(rel: &str) -> bool {
    rel.ends_with(".md") || rel.ends_with(".jinja")
}

/// Front matter as a JSON object and the body after it. YAML first; the loose
/// `key: value` lines mdBook accepts (e.g. unquoted colons) as a fallback.
fn front_matter(source: &str) -> (serde_json::Map<String, serde_json::Value>, String) {
    let Some(found) = FRONT_MATTER.captures(source) else {
        return (serde_json::Map::new(), source.to_owned());
    };
    let body = source[found[0].len()..].to_owned();
    let matter = gray_matter::Matter::<gray_matter::engine::YAML>::new();
    if let Ok(parsed) = matter.parse::<serde_json::Value>(source)
        && let Some(serde_json::Value::Object(data)) = parsed.data
    {
        return (data, body);
    }
    let data = found[1]
        .lines()
        .filter_map(|line| line.split_once(':'))
        .filter(|(key, _)| !key.trim().is_empty())
        .map(|(key, value)| (key.trim().to_owned(), serde_json::Value::String(value.trim().to_owned())))
        .collect();
    (data, body)
}

fn title_of(data: &serde_json::Map<String, serde_json::Value>, body: &str, rel: &str) -> String {
    match data.get("title") {
        Some(serde_json::Value::String(title)) => return title.clone(),
        Some(serde_json::Value::Null) | None => {}
        Some(other) => return other.to_string(),
    }
    if let Some(found) = H1.captures(body) {
        return found[1].replace(['`', '*', '_'], "");
    }
    let base = basename(rel);
    base.trim_end_matches(".md").trim_end_matches(".jinja").replace(['-', '_'], " ")
}

/// Where links inside one repo's pages go.
struct Links {
    /// Repo-relative source path -> site-relative output path.
    by_rel: HashMap<String, String>,
    blob: Option<String>,
    raw: Option<String>,
}

impl Links {
    /// .md links become pages; links to other repo files go to GitHub (images to their raw URL).
    fn resolve(&self, link: &str, base: &str, from: &str) -> Option<String> {
        if link.is_empty() || SCHEME.is_match(link) {
            return None;
        }
        let cut = link.find(['?', '#']).unwrap_or(link.len());
        let (path, suffix) = link.split_at(cut);
        if path.is_empty() {
            return None;
        }
        if path.starts_with('/') {
            return Some(url(from, path) + suffix);
        }
        let decoded = percent_encoding::percent_decode_str(path).decode_utf8_lossy();
        let joined = path_clean::clean(format!("{base}/{decoded}"));
        let target = joined.to_string_lossy();
        let target = target.trim_end_matches('/');
        for candidate in [target.to_owned(), format!("{target}/README.md"), format!("{target}/readme.md"), format!("{target}/index.md")] {
            if let Some(out) = self.by_rel.get(&candidate) {
                return Some(url(from, out) + suffix);
            }
        }
        if target != ".." && !target.starts_with("../") {
            let prefix = if IMAGE.is_match(target) { &self.raw } else { &self.blob };
            if let Some(prefix) = prefix {
                return Some(format!("{prefix}{}{suffix}", if target == "." { "" } else { target }));
            }
        }
        None
    }
}

#[derive(Serialize, Clone)]
struct PageRef {
    title: String,
    out: String,
}

#[derive(Serialize)]
struct ApiView {
    tool: String,
    title: String,
    label: String,
    out: String,
}

#[derive(Serialize, Default)]
struct TreeNode {
    name: String,
    page: Option<PageRef>,
    children: Vec<TreeNode>,
}

impl TreeNode {
    /// Nested tree of a repo's docs pages, for docs without SUMMARY.md.
    fn build(pages: &[(String, PageRef)]) -> Self {
        let mut root = TreeNode::default();
        for (doc_rel, page) in pages {
            let parts: Vec<&str> = doc_rel.split('/').collect();
            let (leaf, dirs) = parts.split_last().expect("split yields one part");
            let mut node = &mut root;
            for dir in dirs {
                let at = match node.children.iter().position(|child| child.name == *dir) {
                    Some(at) => at,
                    None => {
                        node.children.push(TreeNode { name: (*dir).to_owned(), ..Default::default() });
                        node.children.len() - 1
                    }
                };
                node = &mut node.children[at];
            }
            let lower = leaf.to_lowercase();
            if ["readme.md", "index.md", "readme.jinja", "index.jinja"].contains(&lower.as_str()) {
                node.page = Some(page.clone());
            } else {
                node.children.push(TreeNode { name: (*leaf).to_owned(), page: Some(page.clone()), children: Vec::new() });
            }
        }
        root
    }
}

/// What templates see as `repo`.
#[derive(Serialize)]
struct RepoView {
    name: String,
    title: String,
    index: String,
    web: Option<String>,
    blob: Option<String>,
    head: String,
    /// Group label for the wiki header's dropdowns (wiki.toml `category`, default "Other").
    category: String,
    description: Option<String>,
    readme_page: Option<PageRef>,
    doc_pages: Vec<PageRef>,
    apis: Vec<ApiView>,
    api_labels: Vec<String>,
    book_title: Option<String>,
    has_summary: bool,
    tree: TreeNode,
}

/// What templates see as `page`.
#[derive(Serialize)]
struct PageView<'a> {
    title: &'a str,
    out: &'a str,
    rel: &'a str,
    data: &'a serde_json::Map<String, serde_json::Value>,
    /// Plain markdown page: blocks map to source lines, so Radar works.
    radar: bool,
}

struct Page {
    repo: Option<usize>,
    rel: String,
    doc_rel: Option<String>,
    out: String,
    data: serde_json::Map<String, serde_json::Value>,
    /// The whole file (markdown is rendered from it so source lines match).
    source: String,
    body: String,
    title: String,
    readme: bool,
    synthetic: bool,
}

impl Page {
    fn is_template(&self) -> bool {
        self.rel.ends_with(".jinja") || self.data.get("jinja").and_then(serde_json::Value::as_bool) == Some(true)
    }

    fn view(&self) -> PageView<'_> {
        PageView {
            title: &self.title,
            out: &self.out,
            rel: &self.rel,
            data: &self.data,
            radar: self.repo.is_some() && self.rel.ends_with(".md") && !self.is_template(),
        }
    }
}

/// A repo with its sources resolved.
struct SiteRepo<'a> {
    repo: &'a Repo,
    links: Arc<Links>,
    /// (repo-relative source, output path) of every docs file that isn't a page.
    assets: Vec<(String, String)>,
    pages: Vec<usize>,
    apis: Vec<Api>,
    docs_rel: Option<String>,
    book_title: Option<String>,
    summary: Option<String>,
    key: String,
}

/// mdBook projects keep pages in book.toml's `src` (default "src").
fn docs_root(docs: &Path) -> (PathBuf, Option<String>) {
    let Ok(text) = fs::read_to_string(docs.join("book.toml")) else { return (docs.to_path_buf(), None) };
    let book: toml::Table = toml::from_str(&text).unwrap_or_default();
    let book = book.get("book").and_then(toml::Value::as_table);
    let src = book.and_then(|book| book.get("src")).and_then(toml::Value::as_str).unwrap_or("src");
    let title = book.and_then(|book| book.get("title")).and_then(toml::Value::as_str).map(str::to_owned);
    (docs.join(src), title)
}

/// Files under `dir`, sorted, skipping hidden and git-ignored ones.
fn walk(dir: &Path) -> Vec<String> {
    let mut files: Vec<String> = ignore::WalkBuilder::new(dir)
        .build()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_some_and(|kind| kind.is_file()))
        .filter_map(|entry| entry.path().strip_prefix(dir).ok().map(|rel| rel.to_string_lossy().into_owned()))
        .filter(|rel| !rel.split('/').any(|part| part == "node_modules"))
        .collect();
    files.sort();
    files
}

fn write(dist: &Path, out: &str, html: &str) -> Result<()> {
    let dest = dist.join(out);
    if let Some(dir) = dest.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(&dest, html).with_context(|| format!("writing {}", dest.display()))
}

pub fn render(paths: &Paths, repos: &[Repo], apis: &BTreeMap<String, Vec<Api>>, state: &mut State) -> Result<()> {
    let site_title = std::env::var("WIKI_TITLE").unwrap_or_else(|_| "jbisfun wiki".into());
    let markdown = Arc::new(Markdown::new());
    let dist = &paths.dist;

    // Sources of every repo: (repo-relative source, docs-relative path, output path).
    let mut site_repos = Vec::new();
    let mut pages: Vec<Page> = Vec::new();
    let mut sources = Vec::new();
    for repo in repos {
        let mut files: Vec<(String, Option<String>, String)> = Vec::new();
        if let Some(readme) = &repo.readme {
            files.push((readme.clone(), None, format!("{}/index.html", repo.name)));
        }
        let mut docs_rel = None;
        let mut book_title = None;
        let docs = repo.path.join("docs");
        if docs.is_dir() {
            let (root, title) = docs_root(&docs);
            let rel = root.strip_prefix(&repo.path).unwrap_or(&root).to_string_lossy().into_owned();
            for file in walk(&root) {
                files.push((format!("{rel}/{file}"), Some(file.clone()), format!("{}/docs/{}", repo.name, out_name(&file))));
            }
            docs_rel = Some(rel);
            book_title = title;
        }
        let repo_apis = apis.get(&repo.name).cloned().unwrap_or_default();
        if !files.iter().any(|(rel, ..)| is_page(rel)) && repo_apis.is_empty() {
            continue;
        }
        sources.push(files);
        let blob = repo.web.as_ref().map(|web| format!("{web}/blob/{}/", repo.branch));
        let raw = repo.web.as_ref().map(|web| format!("{web}/raw/{}/", repo.branch));
        site_repos.push(SiteRepo {
            repo,
            links: Arc::new(Links { by_rel: HashMap::new(), blob, raw }),
            assets: Vec::new(),
            pages: Vec::new(),
            apis: repo_apis,
            docs_rel,
            book_title,
            summary: None,
            key: String::new(),
        });
    }

    let mut global_inputs = state::dir_ids(&paths.wiki.join("templates"));
    global_inputs.push(state::file_id(&std::env::current_exe()?));
    global_inputs.push(site_title.clone());
    global_inputs.extend(site_repos.iter().map(|site| site.repo.name.clone()));
    let global = state::key(global_inputs);
    if state.global != global && dist.is_dir() {
        // Everything but the bundled assets is stale.
        for entry in fs::read_dir(dist)? {
            let entry = entry?;
            if entry.file_name() != "_assets" {
                let path = entry.path();
                if path.is_dir() { fs::remove_dir_all(&path)? } else { fs::remove_file(&path)? }
            }
        }
    }

    for (index, (site, files)) in site_repos.iter_mut().zip(sources).enumerate() {
        let repo = site.repo;
        let mut key_inputs = vec![global.clone(), serde_json::to_string(&repo.config)?, repo.branch.clone(), repo.web.clone().unwrap_or_default()];
        key_inputs.extend(site.apis.iter().map(|api| format!("{}\0{}", api.tool, api.path)));
        key_inputs.extend(state.apidoc.iter().filter(|(id, _)| id.starts_with(&format!("{}/", repo.name))).map(|(_, api)| api.key.clone()));
        let mut by_rel = HashMap::new();
        for (rel, doc_rel, out) in files {
            let src = repo.path.join(&rel);
            key_inputs.push(format!("{rel}\0{}", state::file_id(&src)));
            by_rel.insert(rel.clone(), out.clone());
            if doc_rel.as_deref() == Some("SUMMARY.md") {
                site.summary = Some(fs::read_to_string(&src)?);
                continue;
            }
            if !is_page(&rel) {
                site.assets.push((rel, out));
                continue;
            }
            let source = fs::read_to_string(&src).with_context(|| format!("reading {}", src.display()))?;
            let (data, body) = front_matter(&source);
            let title = title_of(&data, &body, &rel);
            site.pages.push(pages.len());
            pages.push(Page { repo: Some(index), readme: Some(&rel) == repo.readme.as_ref(), rel, doc_rel, out, data, source, body, title, synthetic: false });
        }
        if repo.readme.is_none() {
            site.pages.insert(0, pages.len());
            pages.push(Page {
                repo: Some(index),
                rel: String::new(),
                doc_rel: None,
                out: format!("{}/index.html", repo.name),
                data: Default::default(),
                source: String::new(),
                body: String::new(),
                title: repo.name.clone(),
                readme: false,
                synthetic: true,
            });
        }
        if let Some(links) = Arc::get_mut(&mut site.links) {
            links.by_rel = by_rel;
        }
        site.key = state::key(key_inputs);
    }

    for rel in walk(&paths.wiki.join("pages")).into_iter().filter(|rel| rel.ends_with(".jinja")) {
        let source = fs::read_to_string(paths.wiki.join("pages").join(&rel))?;
        let (data, body) = front_matter(&source);
        let title = data.get("title").and_then(serde_json::Value::as_str).unwrap_or(&site_title).to_owned();
        pages.push(Page { repo: None, out: out_name(&rel), rel, doc_rel: None, data, source, body, title, readme: false, synthetic: false });
    }

    let views: Vec<RepoView> = site_repos
        .iter()
        .map(|site| {
            let repo = site.repo;
            let page_ref = |at: &usize| PageRef { title: pages[*at].title.clone(), out: pages[*at].out.clone() };
            let readme = site.pages.iter().find(|at| pages[**at].readme);
            let docs: Vec<(String, PageRef)> = site
                .pages
                .iter()
                .filter_map(|at| pages[*at].doc_rel.clone().map(|doc_rel| (doc_rel, page_ref(at))))
                .collect();
            let apis: Vec<ApiView> = site
                .apis
                .iter()
                .map(|api| ApiView {
                    tool: api.tool.clone(),
                    title: api.title.clone(),
                    label: match api.tool.as_str() {
                        "rust" => "Rust",
                        "lua" => "Lua",
                        "js" => "JavaScript",
                        other => other,
                    }
                    .to_owned(),
                    out: format!("{}/api/{}", repo.name, api.path),
                })
                .collect();
            let mut api_labels: Vec<String> = apis.iter().map(|api| api.label.clone()).collect();
            api_labels.dedup();
            RepoView {
                name: repo.name.clone(),
                title: repo.name.clone(),
                index: format!("{}/index.html", repo.name),
                web: repo.web.clone(),
                blob: site.links.blob.clone(),
                head: repo.head.clone(),
                category: repo.config.category.clone().unwrap_or_else(|| "Other".into()),
                description: readme.and_then(|at| markdown.first_paragraph(&pages[*at].body)),
                readme_page: readme.map(page_ref),
                doc_pages: docs.iter().map(|(_, page)| page.clone()).collect(),
                tree: TreeNode::build(&docs),
                apis,
                api_labels,
                book_title: site.book_title.clone(),
                has_summary: site.summary.is_some(),
            }
        })
        .collect();

    let mut env = Environment::new();
    env.set_loader(path_loader(paths.wiki.join("templates")));
    env.set_auto_escape_callback(|_| AutoEscape::Html);
    let all_pages: Vec<PageRef> = pages.iter().map(|page| PageRef { title: page.title.clone(), out: page.out.clone() }).collect();
    let site_value = context! { title => site_title, repos => Value::from(Serde(&views)), pages => Value::from(Serde(&all_pages)) };

    let renderer = Renderer { env: &env, markdown: &markdown, site: &site_value, site_repos: &site_repos, views: &views };
    let mut rendered = 0;
    let mut kept = BTreeMap::new();
    let mut changed = Vec::new();
    for (index, site) in site_repos.iter().enumerate() {
        let name = &site.repo.name;
        let fresh = state.repos.get(name) == Some(&site.key) && dist.join(name).is_dir();
        if !fresh {
            changed.push(name.as_str());
            let dir = dist.join(name);
            if dir.exists() {
                fs::remove_dir_all(&dir)?;
            }
            for (rel, out) in &site.assets {
                let dest = dist.join(out);
                fs::create_dir_all(dest.parent().context("asset without dir")?)?;
                fs::copy(site.repo.path.join(rel), &dest)?;
            }
            let tools: std::collections::BTreeSet<&str> = site.apis.iter().map(|api| api.tool.as_str()).collect();
            for tool in tools {
                let dest = dir.join("api").join(tool);
                copy_dir(&paths.build.join("api").join(name).join(tool), &dest)?;
                // rustdoc/LDoc pages are standalone documents, not rendered through
                // layout.html: embed a small header directly so they stay reachable.
                if tool == "rust" || tool == "lua" {
                    renderer.embed_headers(&dest, dist, index)?;
                }
            }
        }
        for at in &site.pages {
            let page = &pages[*at];
            if fresh && !page.is_template() {
                continue;
            }
            write(dist, &page.out, &renderer.page(page, Some(index))?)?;
            rendered += 1;
        }
        kept.insert(name.clone(), site.key.clone());
    }
    for page in pages.iter().filter(|page| page.repo.is_none()) {
        write(dist, &page.out, &renderer.page(page, None)?)?;
        rendered += 1;
    }
    for name in state.repos.keys().filter(|name| !kept.contains_key(*name)) {
        let dir = dist.join(name);
        if dir.is_dir() {
            fs::remove_dir_all(dir)?;
        }
    }
    state.repos = kept;
    state.global = global;

    let api_count: usize = site_repos.iter().map(|site| site.apis.len()).sum();
    let changed = if changed.is_empty() { "none".to_owned() } else { changed.join(", ") };
    println!(
        "wiki: {rendered} of {} pages rendered, {api_count} code references; regenerated repos: {changed}",
        pages.len(),
    );
    Ok(())
}

struct Renderer<'a> {
    env: &'a Environment<'a>,
    markdown: &'a Arc<Markdown>,
    site: &'a Value,
    site_repos: &'a [SiteRepo<'a>],
    views: &'a [RepoView],
}

impl Renderer<'_> {
    /// Every `.html` file under `dir` (a freshly copied rustdoc/LDoc output tree) gets
    /// the site's own navbar spliced in after `<body>`, plus the site stylesheet and
    /// script linked into `<head>`, so these pages match the rest of the wiki instead
    /// of standing apart in the doc tool's bare look.
    fn embed_headers(&self, dir: &Path, dist: &Path, repo_index: usize) -> Result<()> {
        for entry in WalkDir::new(dir).into_iter().filter_map(Result::ok) {
            if !entry.file_type().is_file() {
                continue;
            }
            let path = entry.path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("html") {
                continue;
            }
            let from = path.strip_prefix(dist)?.to_string_lossy().replace('\\', "/");
            self.embed_header(path, &from, repo_index)?;
        }
        Ok(())
    }

    fn embed_header(&self, path: &Path, from: &str, repo_index: usize) -> Result<()> {
        let html = fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let Some(body_end) = BODY_TAG.find(&html).map(|found| found.end()) else {
            return Ok(());
        };
        let url_value = {
            let from = from.to_owned();
            Value::from_function(move |to: String| url(&from, &to))
        };
        let header = self.env.get_template("partials/navbar.html")?.render(context! {
            site => self.site.clone(),
            repo => Value::from(Serde(&self.views[repo_index])),
            url => url_value,
        })?;
        let mut out = String::with_capacity(html.len() + header.len() + 200);
        match HEAD_TAG.find(&html) {
            Some(found) => {
                out.push_str(&html[..found.start()]);
                out.push_str(&format!(
                    "  <link rel=\"stylesheet\" href=\"{}\">\n  <script type=\"module\" src=\"{}\"></script>\n",
                    url(from, "_assets/style.css"),
                    url(from, "_assets/main.js"),
                ));
                out.push_str(&html[found.start()..body_end]);
            }
            None => out.push_str(&html[..body_end]),
        }
        out.push_str(&header);
        out.push_str(&html[body_end..]);
        fs::write(path, out).with_context(|| format!("writing {}", path.display()))
    }

    fn page(&self, page: &Page, repo: Option<usize>) -> Result<String> {
        let from = page.out.clone();
        let base = page.rel.rsplit_once('/').map_or(".", |(dir, _)| dir).to_owned();
        let links = repo.map(|at| self.site_repos[at].links.clone());
        let markdown = self.markdown.clone();
        let md = {
            let (from, base, links) = (from.clone(), base.clone(), links.clone());
            move |source: &str| -> Result<String> {
                let html = markdown.render(source);
                match &links {
                    Some(links) => markdown::rewrite_links(&html, |link| links.resolve(link, &base, &from)),
                    None => Ok(html),
                }
            }
        };
        let md = Arc::new(md);
        let md_value = {
            let md = md.clone();
            Value::from_function(move |source: String| -> Result<Value, minijinja::Error> {
                md(&source)
                    .map(Value::from_safe_string)
                    .map_err(|err| minijinja::Error::new(minijinja::ErrorKind::InvalidOperation, err.to_string()))
            })
        };
        let url_value = {
            let from = from.clone();
            Value::from_function(move |to: String| url(&from, &to))
        };
        let repo_view = repo.map(|at| Value::from(Serde(&self.views[at])));
        let sidebar = match repo {
            Some(at) => self.sidebar(at, &from, &url_value)?,
            None => String::new(),
        };
        let data = context! {
            site => self.site.clone(),
            page => Value::from(Serde(page.view())),
            repo => repo_view,
            url => url_value,
            md => md_value,
            sidebar => Value::from_safe_string(sidebar),
        };

        let content = if page.synthetic {
            self.env.get_template("repo-index.html")?.render(&data)?
        } else if page.is_template() {
            let html = self.env.render_named_str(&page.rel, &page.body, &data)?;
            if page.rel.ends_with(".md") { md(&html)? } else { html }
        } else {
            md(&page.source)?
        };
        let layout = match page.data.get("layout") {
            Some(serde_json::Value::Bool(false)) => return Ok(content),
            Some(serde_json::Value::String(name)) => name.as_str(),
            _ => "layout.html",
        };
        let data = context! { content => Value::from_safe_string(content), ..data };
        Ok(self.env.get_template(layout)?.render(data)?)
    }

    /// Repo navigation: README, code reference, then the docs (mdBook's
    /// SUMMARY.md when there is one, else the folder tree).
    fn sidebar(&self, at: usize, from: &str, url_value: &Value) -> Result<String> {
        let site = &self.site_repos[at];
        let summary = match &site.summary {
            Some(source) => {
                let source = Regex::new(r"(?i)^#\s+Summary\s*\n")?.replace(source, "");
                // Summary links are relative to the docs root.
                let html = self.markdown.render(&source);
                let base = site.docs_rel.clone().unwrap_or_else(|| ".".into());
                Some(markdown::rewrite_links(&html, |link| site.links.resolve(link, &base, from))?)
            }
            None => None,
        };
        let html = self.env.get_template("partials/repo-nav.html")?.render(context! {
            repo => Value::from(Serde(&self.views[at])),
            summary => summary.map(Value::from_safe_string),
            url => url_value.clone(),
        })?;
        markdown::mark_active(&html, basename(from))
    }
}
