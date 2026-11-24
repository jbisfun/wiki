//! Pages: every repo's README (its entry page) and docs/ folder, plus the
//! wiki's own pages/*.jinja, through minijinja templates (templates/).
//!
//! A repo's pages are re-rendered only when its key changed: the blob ids of
//! all its page sources, its code reference keys, its settings, and the global
//! key (templates, the repo list in the navbar, the wiki binary). `.jinja`
//! pages can show anything about the site, so they are rendered every time.
use std::collections::{BTreeMap, BTreeSet, HashMap};
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
static SUMMARY_H1: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^#\s+Summary\s*\n").expect("valid regex"));
static BODY_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)<body[^>]*>").expect("valid regex"));
static HEAD_END: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)</head>").expect("valid regex"));

type Data = serde_json::Map<String, serde_json::Value>;

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

/// `url` bound to one page, as the template function `url(path)`.
fn url_function(from: &str) -> Value {
    let from = from.to_owned();
    Value::from_function(move |to: String| url(&from, &to))
}

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

/// Output path of a source page: README/index.md -> index.html, x.md -> x.html,
/// x.jinja -> x.html (or x as is when it has its own extension), other files as is.
fn out_name(rel: &str) -> String {
    let (dir, base) = rel.rsplit_once('/').unwrap_or(("", rel));
    let name = if is_index(base) && base.to_lowercase().ends_with(".md") {
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

/// A folder's own page: README or index, markdown or Jinja.
fn is_index(base: &str) -> bool {
    ["readme.md", "index.md", "readme.jinja", "index.jinja"].contains(&base.to_lowercase().as_str())
}

/// Front matter as a JSON object and the body after it. YAML first; the loose
/// `key: value` lines mdBook accepts (e.g. unquoted colons) as a fallback.
fn front_matter(source: &str) -> (Data, String) {
    let Some(found) = FRONT_MATTER.captures(source) else {
        return (Data::new(), source.to_owned());
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

/// Front matter `title`, else the first `# heading`, else the file name.
fn title_of(data: &Data, body: &str, rel: &str) -> String {
    match data.get("title") {
        Some(serde_json::Value::String(title)) => return title.clone(),
        Some(serde_json::Value::Null) | None => {}
        Some(other) => return other.to_string(),
    }
    if let Some(found) = H1.captures(body) {
        return found[1].replace(['`', '*', '_'], "");
    }
    basename(rel).trim_end_matches(".md").trim_end_matches(".jinja").replace(['-', '_'], " ")
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
            if is_index(leaf) {
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
    /// The pull repo name, e.g. `fossify-ios/notes-ios`.
    name: String,
    /// The name without its pull group, e.g. `notes-ios`.
    title: String,
    index: String,
    web: Option<String>,
    blob: Option<String>,
    head: String,
    /// Header dropdown: wiki.toml `category`, else the pull group, else "Other".
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
    data: &'a Data,
    /// Plain markdown page: blocks map to source lines, so Radar works.
    radar: bool,
}

struct Page {
    repo: Option<usize>,
    rel: String,
    doc_rel: Option<String>,
    out: String,
    data: Data,
    /// The whole file (markdown is rendered from it so source lines match).
    source: String,
    body: String,
    title: String,
    readme: bool,
    /// Stand-in entry page of a repo without a README (templates/repo-index.html).
    placeholder: bool,
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

    fn page_ref(&self) -> PageRef {
        PageRef { title: self.title.clone(), out: self.out.clone() }
    }
}

/// A repo with its sources resolved.
struct SiteRepo<'a> {
    repo: &'a Repo,
    links: Arc<Links>,
    /// (repo-relative source, output path) of every docs file that isn't a page.
    assets: Vec<(String, String)>,
    /// Indexes into the page list, entry page first.
    pages: Vec<usize>,
    apis: Vec<Api>,
    docs_rel: Option<String>,
    book_title: Option<String>,
    summary: Option<String>,
    /// Key of the repo's own inputs; `render` folds in the global key.
    key: String,
}

impl<'a> SiteRepo<'a> {
    /// Read a repo's README and docs into `pages`; None when it has neither
    /// pages nor a code reference. `index` is its position in the site's repos.
    fn load(repo: &'a Repo, apis: Vec<Api>, index: usize, state: &State, pages: &mut Vec<Page>) -> Result<Option<Self>> {
        // (repo-relative source, docs-relative path, output path)
        let mut files: Vec<(String, Option<String>, String)> = Vec::new();
        if let Some(readme) = &repo.readme {
            files.push((readme.clone(), None, format!("{}/index.html", repo.name)));
        }
        let (mut docs_rel, mut book_title) = (None, None);
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
        if apis.is_empty() && !files.iter().any(|(rel, ..)| is_page(rel)) {
            return Ok(None);
        }

        let mut inputs = vec![serde_json::to_string(&repo.config)?, repo.branch.clone(), repo.web.clone().unwrap_or_default()];
        inputs.extend(apis.iter().map(|api| format!("{}\0{}", api.tool, api.path)));
        let prefix = format!("{}/", repo.name);
        inputs.extend(state.apidoc.iter().filter(|(id, _)| id.starts_with(&prefix)).map(|(_, api)| api.key.clone()));

        let links = Links {
            by_rel: files.iter().map(|(rel, _, out)| (rel.clone(), out.clone())).collect(),
            blob: repo.web.as_ref().map(|web| format!("{web}/blob/{}/", repo.branch)),
            raw: repo.web.as_ref().map(|web| format!("{web}/raw/{}/", repo.branch)),
        };
        let mut site = SiteRepo {
            repo,
            links: Arc::new(links),
            assets: Vec::new(),
            pages: Vec::new(),
            apis,
            docs_rel,
            book_title,
            summary: None,
            key: String::new(),
        };
        for (rel, doc_rel, out) in files {
            let src = repo.path.join(&rel);
            inputs.push(format!("{rel}\0{}", state::file_id(&src)));
            if doc_rel.as_deref() == Some("SUMMARY.md") {
                site.summary = Some(fs::read_to_string(&src)?);
            } else if !is_page(&rel) {
                site.assets.push((rel, out));
            } else {
                let source = fs::read_to_string(&src).with_context(|| format!("reading {}", src.display()))?;
                let (data, body) = front_matter(&source);
                let title = title_of(&data, &body, &rel);
                let readme = Some(&rel) == repo.readme.as_ref();
                site.pages.push(pages.len());
                pages.push(Page { repo: Some(index), rel, doc_rel, out, data, source, body, title, readme, placeholder: false });
            }
        }
        if repo.readme.is_none() {
            site.pages.insert(0, pages.len());
            pages.push(Page {
                repo: Some(index),
                rel: String::new(),
                doc_rel: None,
                out: format!("{}/index.html", repo.name),
                data: Data::new(),
                source: String::new(),
                body: String::new(),
                title: repo.name.clone(),
                readme: false,
                placeholder: true,
            });
        }
        site.key = state::key(inputs);
        Ok(Some(site))
    }

    fn view(&self, pages: &[Page], markdown: &Markdown) -> RepoView {
        let repo = self.repo;
        let readme = self.pages.iter().map(|at| &pages[*at]).find(|page| page.readme);
        let docs: Vec<(String, PageRef)> = self
            .pages
            .iter()
            .map(|at| &pages[*at])
            .filter_map(|page| page.doc_rel.clone().map(|doc_rel| (doc_rel, page.page_ref())))
            .collect();
        let apis: Vec<ApiView> = self
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
        let group = repo.name.rsplit_once('/').map(|(group, _)| group);
        RepoView {
            name: repo.name.clone(),
            title: basename(&repo.name).to_owned(),
            index: format!("{}/index.html", repo.name),
            web: repo.web.clone(),
            blob: self.links.blob.clone(),
            head: repo.head.clone(),
            category: repo.config.category.as_deref().or(group).unwrap_or("Other").to_owned(),
            description: repo.config.description.clone().or_else(|| readme.and_then(|page| markdown.blurb(&page.body))),
            readme_page: readme.map(Page::page_ref),
            doc_pages: docs.iter().map(|(_, page)| page.clone()).collect(),
            tree: TreeNode::build(&docs),
            apis,
            api_labels,
            book_title: self.book_title.clone(),
            has_summary: self.summary.is_some(),
        }
    }
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

/// Remove everything in dist/ except the bundled assets.
fn clear_pages(dist: &Path) -> Result<()> {
    for entry in fs::read_dir(dist)? {
        let entry = entry?;
        if entry.file_name() != "_assets" {
            let path = entry.path();
            if path.is_dir() { fs::remove_dir_all(&path)? } else { fs::remove_file(&path)? }
        }
    }
    Ok(())
}

pub fn render(paths: &Paths, repos: &[Repo], apis: &BTreeMap<String, Vec<Api>>, state: &mut State) -> Result<()> {
    let site_title = std::env::var("WIKI_TITLE").unwrap_or_else(|_| "jbisfun wiki".into());
    let markdown = Arc::new(Markdown::new());
    let dist = &paths.dist;

    let mut pages: Vec<Page> = Vec::new();
    let mut site_repos: Vec<SiteRepo> = Vec::new();
    for repo in repos {
        let repo_apis = apis.get(&repo.name).cloned().unwrap_or_default();
        if let Some(site) = SiteRepo::load(repo, repo_apis, site_repos.len(), state, &mut pages)? {
            site_repos.push(site);
        }
    }

    let mut global_inputs = state::dir_ids(&paths.wiki.join("templates"));
    global_inputs.push(state::file_id(&std::env::current_exe()?));
    global_inputs.push(site_title.clone());
    global_inputs.extend(site_repos.iter().map(|site| site.repo.name.clone()));
    let global = state::key(global_inputs);
    if state.global != global && dist.is_dir() {
        clear_pages(dist)?;
    }
    for site in &mut site_repos {
        site.key = state::key([global.as_str(), site.key.as_str()]);
    }

    for rel in walk(&paths.wiki.join("pages")).into_iter().filter(|rel| rel.ends_with(".jinja")) {
        let source = fs::read_to_string(paths.wiki.join("pages").join(&rel))?;
        let (data, body) = front_matter(&source);
        let title = data.get("title").and_then(serde_json::Value::as_str).unwrap_or(&site_title).to_owned();
        pages.push(Page { repo: None, out: out_name(&rel), rel, doc_rel: None, data, source, body, title, readme: false, placeholder: false });
    }

    let views: Vec<RepoView> = site_repos.iter().map(|site| site.view(&pages, &markdown)).collect();
    let mut env = Environment::new();
    env.set_loader(path_loader(paths.wiki.join("templates")));
    env.set_auto_escape_callback(|_| AutoEscape::Html);
    let all_pages: Vec<PageRef> = pages.iter().map(Page::page_ref).collect();
    let site = context! { title => site_title, repos => Value::from(Serde(&views)), pages => Value::from(Serde(&all_pages)) };
    let renderer = Renderer { env: &env, markdown: &markdown, site: &site, site_repos: &site_repos, views: &views };

    let mut rendered = 0;
    let mut kept = BTreeMap::new();
    let mut changed = Vec::new();
    for (index, site) in site_repos.iter().enumerate() {
        let name = &site.repo.name;
        let fresh = state.repos.get(name) == Some(&site.key) && dist.join(name).is_dir();
        if !fresh {
            changed.push(name.as_str());
            renderer.copy_files(paths, index)?;
        }
        for page in site.pages.iter().map(|at| &pages[*at]) {
            if fresh && !page.is_template() {
                continue;
            }
            write(dist, &page.out, &renderer.page(page)?)?;
            rendered += 1;
        }
        kept.insert(name.clone(), site.key.clone());
    }
    for page in pages.iter().filter(|page| page.repo.is_none()) {
        write(dist, &page.out, &renderer.page(page)?)?;
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
    println!("wiki: {rendered} of {} pages rendered, {api_count} code references; regenerated repos: {changed}", pages.len());
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
    /// Start a repo's dist/ folder over with its docs assets and code reference.
    fn copy_files(&self, paths: &Paths, index: usize) -> Result<()> {
        let site = &self.site_repos[index];
        let name = &site.repo.name;
        let dir = paths.dist.join(name);
        if dir.exists() {
            fs::remove_dir_all(&dir)?;
        }
        for (rel, out) in &site.assets {
            let dest = paths.dist.join(out);
            fs::create_dir_all(dest.parent().context("asset without dir")?)?;
            fs::copy(site.repo.path.join(rel), &dest)?;
        }
        let tools: BTreeSet<&str> = site.apis.iter().map(|api| api.tool.as_str()).collect();
        for tool in tools {
            let dest = dir.join("api").join(tool);
            copy_dir(&paths.build.join("api").join(name).join(tool), &dest)?;
            // rustdoc/LDoc pages are standalone documents, not rendered through
            // layout.html: embed the site header so they stay reachable. LDoc
            // has no dark mode, so its header stays light.
            match tool {
                "rust" => self.embed_headers(&dest, &paths.dist, index, None)?,
                "lua" => self.embed_headers(&dest, &paths.dist, index, Some("light"))?,
                _ => {}
            }
        }
        Ok(())
    }

    /// Every `.html` file under `dir` (a freshly copied rustdoc/LDoc output tree) gets
    /// the site header (partials/apidoc-header.html) spliced in after `<body>`. The
    /// header is a fixed element whose content lives in a shadow root, so the site's
    /// stylesheet styles it without touching the doc tool's own CSS; the only thing
    /// added to the page itself is room at the top for the header.
    fn embed_headers(&self, dir: &Path, dist: &Path, repo: usize, theme: Option<&str>) -> Result<()> {
        for entry in WalkDir::new(dir).into_iter().filter_map(Result::ok) {
            let path = entry.path();
            if entry.file_type().is_file() && path.extension().is_some_and(|ext| ext == "html") {
                let from = path.strip_prefix(dist)?.to_string_lossy().replace('\\', "/");
                self.embed_header(path, &from, repo, theme)?;
            }
        }
        Ok(())
    }

    fn embed_header(&self, path: &Path, from: &str, repo: usize, theme: Option<&str>) -> Result<()> {
        let html = fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let Some(body) = BODY_TAG.find(&html).map(|found| found.end()) else {
            return Ok(());
        };
        let header = self.env.get_template("partials/apidoc-header.html")?.render(context! {
            site => self.site.clone(),
            repo => Value::from(Serde(&self.views[repo])),
            url => url_function(from),
            theme => theme,
        })?;
        // header.js measures the header into --wiki-header-height. rustdoc's sidebar is
        // sticky at the top of the viewport, so it moves down by the same amount.
        let head = format!(
            "  <script type=\"module\" src=\"{}\"></script>\n  <style>\
             body{{padding-top:var(--wiki-header-height,3.5rem)!important}}\
             .rustdoc .sidebar{{top:var(--wiki-header-height,3.5rem);height:calc(100vh - var(--wiki-header-height,3.5rem))}}\
             </style>\n",
            url(from, "_assets/main.js"),
        );
        let mut out = String::with_capacity(html.len() + header.len() + head.len());
        match HEAD_END.find(&html) {
            Some(found) => {
                out.push_str(&html[..found.start()]);
                out.push_str(&head);
                out.push_str(&html[found.start()..body]);
            }
            None => out.push_str(&html[..body]),
        }
        out.push_str(&header);
        out.push_str(&html[body..]);
        fs::write(path, out).with_context(|| format!("writing {}", path.display()))
    }

    fn page(&self, page: &Page) -> Result<String> {
        let from = page.out.as_str();
        // Markdown with the repo's links resolved from this page.
        let md = {
            let markdown = self.markdown.clone();
            let base = page.rel.rsplit_once('/').map_or(".", |(dir, _)| dir).to_owned();
            let links = page.repo.map(|at| self.site_repos[at].links.clone());
            let from = from.to_owned();
            Arc::new(move |source: &str| -> Result<String> {
                let html = markdown.render(source);
                match &links {
                    Some(links) => markdown::rewrite_links(&html, |link| links.resolve(link, &base, &from)),
                    None => Ok(html),
                }
            })
        };
        let md_function = {
            let md = md.clone();
            Value::from_function(move |source: String| -> Result<Value, minijinja::Error> {
                md(&source)
                    .map(Value::from_safe_string)
                    .map_err(|err| minijinja::Error::new(minijinja::ErrorKind::InvalidOperation, err.to_string()))
            })
        };
        let url_value = url_function(from);
        let sidebar = match page.repo {
            Some(at) => self.sidebar(at, from, &url_value)?,
            None => String::new(),
        };
        let data = context! {
            site => self.site.clone(),
            page => Value::from(Serde(page.view())),
            repo => page.repo.map(|at| Value::from(Serde(&self.views[at]))),
            url => url_value,
            md => md_function,
            sidebar => Value::from_safe_string(sidebar),
        };

        let content = if page.placeholder {
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
                let html = self.markdown.render(&SUMMARY_H1.replace(source, ""));
                // Summary links are relative to the docs root.
                let base = site.docs_rel.as_deref().unwrap_or(".");
                Some(markdown::rewrite_links(&html, |link| site.links.resolve(link, base, from))?)
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
