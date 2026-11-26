//! Pages: every repo's README (its entry page) and docs/ folder, plus the
//! wiki's own pages/*.jinja, through the wiki repo's Jinja templates
//! (templates/, rendered with zig-vin).
//!
//! A repo's pages are re-rendered only when its key changed: the blob ids of
//! all its page sources, its code reference keys, its settings, and the global
//! key (templates, the repo list in the navbar, the binary). `.jinja` pages can
//! show anything about the site, so they are rendered every time.
//!
//! The site is rendered once per language: the source language at the root,
//! every other one under its prefix with the repo pages swapped for their
//! machine translations (translate.zig).
const std = @import("std");
const theme = @import("theme");
const vin = theme.vin;
const config = @import("config.zig");
const markdown = @import("markdown.zig");
const html = @import("html.zig");
const fluent = @import("fluent.zig");
const translate = @import("translate.zig");
const state_mod = @import("state.zig");
const collect = @import("collect.zig");
const sys_mod = @import("sys.zig");
const Sys = sys_mod.Sys;
const warn = sys_mod.warn;
const Allocator = std.mem.Allocator;
const Api = state_mod.Api;
const Repo = collect.Repo;
const Json = std.json.Value;
const no_tools: []const theme.ToolLink = &.{};

pub const Paths = struct {
    /// The wiki repo: wiki.toml, templates/, pages/, assets/, locales/, translations/.
    wiki: []const u8,
    /// The pull workspace root.
    root: []const u8,
    /// state.json and the code reference per repo.
    build: []const u8,
    dist: []const u8,
};

// ------------------------------------------------------------------- paths

/// `^([a-z][a-z0-9+.-]*:|//|#)`, case-insensitively.
pub fn hasScheme(link: []const u8) bool {
    if (std.mem.startsWith(u8, link, "//") or std.mem.startsWith(u8, link, "#")) return true;
    if (link.len == 0 or !std.ascii.isAlphabetic(link[0])) return false;
    for (link[1..]) |ch| {
        if (ch == ':') return true;
        if (!(std.ascii.isAlphanumeric(ch) or ch == '+' or ch == '.' or ch == '-')) return false;
    }
    return false;
}

fn basename(path: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, path, '/')) |at| path[at + 1 ..] else path;
}

fn dirname(path: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, path, '/')) |at| path[0..at] else "";
}

/// Relative URL from one output page to another, both site-relative.
pub fn url(arena: Allocator, from: []const u8, to_in: []const u8) ![]const u8 {
    if (hasScheme(to_in)) return to_in;
    var to = std.mem.trimStart(u8, to_in, "/");
    if (to.len == 0 or to[to.len - 1] == '/') to = try std.mem.concat(arena, u8, &.{ to, "index.html" });
    // pathdiff::diff_paths(to, dirname(from))
    var base_parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, dirname(from), '/');
    while (it.next()) |p| if (!std.mem.eql(u8, p, ".")) try base_parts.append(arena, p);
    var to_parts: std.ArrayList([]const u8) = .empty;
    it = std.mem.tokenizeScalar(u8, to, '/');
    while (it.next()) |p| if (!std.mem.eql(u8, p, ".")) try to_parts.append(arena, p);
    var common: usize = 0;
    while (common < base_parts.items.len and common < to_parts.items.len and std.mem.eql(u8, base_parts.items[common], to_parts.items[common])) common += 1;
    var out: std.ArrayList(u8) = .empty;
    for (base_parts.items[common..]) |_| {
        if (out.items.len > 0) try out.append(arena, '/');
        try out.appendSlice(arena, "..");
    }
    for (to_parts.items[common..]) |p| {
        if (out.items.len > 0) try out.append(arena, '/');
        try out.appendSlice(arena, p);
    }
    if (out.items.len == 0) return basename(to);
    return out.items;
}

/// path_clean::clean: resolve `.` and `..`, drop empty parts.
fn cleanPath(arena: Allocator, path: []const u8) ![]const u8 {
    const absolute = path.len > 0 and path[0] == '/';
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |p| {
        if (std.mem.eql(u8, p, ".")) continue;
        if (std.mem.eql(u8, p, "..")) {
            if (parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
                continue;
            }
            if (absolute) continue;
        }
        try parts.append(arena, p);
    }
    const joined = try std.mem.join(arena, "/", parts.items);
    if (absolute) return std.mem.concat(arena, u8, &.{ "/", joined });
    return if (joined.len == 0) "." else joined;
}

fn percentDecode(arena: Allocator, s: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '%') == null) return s;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '%' and i + 2 < s.len + 0 and i + 2 <= s.len - 1 and std.ascii.isHex(s[i + 1]) and std.ascii.isHex(s[i + 2])) {
            try out.append(arena, std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16) catch unreachable);
            i += 2;
        } else try out.append(arena, s[i]);
    }
    return out.items;
}

fn endsWithIgnoreCase(s: []const u8, suffix: []const u8) bool {
    return s.len >= suffix.len and std.ascii.eqlIgnoreCase(s[s.len - suffix.len ..], suffix);
}

/// A folder's own page: README or index, markdown or Jinja.
fn isIndex(base: []const u8) bool {
    inline for (.{ "readme.md", "index.md", "readme.jinja", "index.jinja" }) |n| if (std.ascii.eqlIgnoreCase(base, n)) return true;
    return false;
}

fn isPage(rel: []const u8) bool {
    return std.mem.endsWith(u8, rel, ".md") or std.mem.endsWith(u8, rel, ".jinja");
}

fn isImage(path: []const u8) bool {
    inline for (.{ ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".avif", ".ico" }) |ext| if (endsWithIgnoreCase(path, ext)) return true;
    return false;
}

/// Output path of a source page: README/index.md -> index.html, x.md -> x.html,
/// x.jinja -> x.html (or x as is when it has its own extension), other files as is.
pub fn outName(arena: Allocator, rel: []const u8) ![]const u8 {
    const dir = dirname(rel);
    const base = basename(rel);
    const name = if (isIndex(base) and endsWithIgnoreCase(base, ".md"))
        "index.html"
    else if (std.mem.endsWith(u8, base, ".md"))
        try std.fmt.allocPrint(arena, "{s}.html", .{base[0 .. base.len - 3]})
    else if (std.mem.endsWith(u8, base, ".jinja")) blk: {
        const stem = base[0 .. base.len - 6];
        break :blk if (std.mem.indexOfScalar(u8, stem, '.') != null) stem else try std.fmt.allocPrint(arena, "{s}.html", .{stem});
    } else base;
    return if (dir.len == 0) name else try std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, name });
}

// ------------------------------------------------------------ front matter

/// Front matter as a JSON object and the body after it. YAML scalars only
/// (`key: value` lines: strings, quoted strings, booleans, numbers, null);
/// that covers the docs here, including the loose lines mdBook accepts.
pub fn frontMatter(arena: Allocator, source: []const u8) !struct { data: std.json.ObjectMap, body: []const u8 } {
    var data: std.json.ObjectMap = .empty;
    const len = markdown.frontMatterLen(source);
    if (len == 0) return .{ .data = data, .body = source };
    const first_nl = std.mem.indexOfScalar(u8, source, '\n').?;
    const inner_end = std.mem.lastIndexOfScalar(u8, std.mem.trimEnd(u8, source[0..len], "\r\n"), '\n') orelse first_nl;
    const inner = if (inner_end > first_nl) source[first_nl + 1 .. inner_end] else "";
    var it = std.mem.splitScalar(u8, inner, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0 or line[0] == '#' or line[0] == ' ' or line[0] == '\t') continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        if (key.len == 0) continue;
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        try data.put(arena, key, scalar(value));
    }
    return .{ .data = data, .body = source[len..] };
}

fn scalar(v: []const u8) Json {
    if (v.len >= 2 and ((v[0] == '"' and v[v.len - 1] == '"') or (v[0] == '\'' and v[v.len - 1] == '\''))) return .{ .string = v[1 .. v.len - 1] };
    if (v.len == 0 or std.mem.eql(u8, v, "null") or std.mem.eql(u8, v, "~")) return .null;
    if (std.mem.eql(u8, v, "true")) return .{ .bool = true };
    if (std.mem.eql(u8, v, "false")) return .{ .bool = false };
    if (std.fmt.parseInt(i64, v, 10)) |n| return .{ .integer = n } else |_| {}
    return .{ .string = v };
}

/// Front matter `title`, else the first `# heading`, else the file name.
fn titleOf(arena: Allocator, data: *const std.json.ObjectMap, body: []const u8, rel: []const u8) ![]const u8 {
    if (data.get("title")) |t| switch (t) {
        .string => |s| return s,
        .null => {},
        .integer => |n| return std.fmt.allocPrint(arena, "{d}", .{n}),
        .bool => |b| return if (b) "true" else "false",
        else => {},
    };
    // (?m)^#\s+(.+?)\s*(\{#[^}]*\})?\s*$
    var it = std.mem.splitScalar(u8, body, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len < 2 or line[0] != '#' or !std.ascii.isWhitespace(line[1])) continue;
        var text = std.mem.trim(u8, line[1..], " \t");
        if (std.mem.endsWith(u8, text, "}")) if (std.mem.lastIndexOf(u8, text, "{#")) |at| {
            text = std.mem.trimEnd(u8, text[0..at], " \t");
        };
        if (text.len == 0) continue;
        var out: std.ArrayList(u8) = .empty;
        for (text) |ch| if (ch != '`' and ch != '*' and ch != '_') try out.append(arena, ch);
        return out.items;
    }
    var name = basename(rel);
    if (std.mem.endsWith(u8, name, ".md")) name = name[0 .. name.len - 3];
    if (std.mem.endsWith(u8, name, ".jinja")) name = name[0 .. name.len - 6];
    const out = try arena.dupe(u8, name);
    for (out) |*ch| if (ch.* == '-' or ch.* == '_') {
        ch.* = ' ';
    };
    return out;
}

// ----------------------------------------------------------------- models

/// Where links inside one repo's pages go.
const Links = struct {
    /// Repo-relative source path -> site-relative output path.
    by_rel: std.StringHashMapUnmanaged([]const u8) = .empty,
    blob: ?[]const u8,
    raw: ?[]const u8,

    /// .md links become pages (in the language `prefix`); links to other repo
    /// files go to GitHub (images to their raw URL).
    fn resolve(l: *const Links, arena: Allocator, link: []const u8, base: []const u8, from: []const u8, prefix: []const u8) !?[]const u8 {
        if (link.len == 0 or hasScheme(link)) return null;
        const cut = std.mem.indexOfAny(u8, link, "?#") orelse link.len;
        const path = link[0..cut];
        const suffix = link[cut..];
        if (path.len == 0) return null;
        if (path[0] == '/') return try std.mem.concat(arena, u8, &.{ try url(arena, from, path), suffix });
        const decoded = try percentDecode(arena, path);
        const joined = try cleanPath(arena, try std.fmt.allocPrint(arena, "{s}/{s}", .{ base, decoded }));
        const target = std.mem.trimEnd(u8, joined, "/");
        const candidates = [_][]const u8{ target, try std.fmt.allocPrint(arena, "{s}/README.md", .{target}), try std.fmt.allocPrint(arena, "{s}/readme.md", .{target}), try std.fmt.allocPrint(arena, "{s}/index.md", .{target}) };
        for (candidates) |candidate| {
            if (l.by_rel.get(candidate)) |out| {
                const dest = if (isPage(candidate)) try std.mem.concat(arena, u8, &.{ prefix, out }) else out;
                return try std.mem.concat(arena, u8, &.{ try url(arena, from, dest), suffix });
            }
        }
        if (!std.mem.eql(u8, target, "..") and !std.mem.startsWith(u8, target, "../")) {
            const web = if (isImage(target)) l.raw else l.blob;
            if (web) |w| return try std.mem.concat(arena, u8, &.{ w, if (std.mem.eql(u8, target, ".")) "" else target, suffix });
        }
        return null;
    }
};

const PageRef = struct {
    title: []const u8,
    out: []const u8,
};

const ApiView = struct {
    tool: []const u8,
    title: []const u8,
    label: []const u8,
    out: []const u8,
};

const TreeNode = struct {
    name: []const u8 = "",
    page: ?PageRef = null,
    children: []TreeNode = &.{},

    /// Nested tree of a repo's docs pages, for docs without SUMMARY.md.
    fn build(arena: Allocator, pages: []const DocPage) !TreeNode {
        var root: Builder = .{};
        for (pages) |p| {
            var node = &root;
            var parts = std.mem.splitScalar(u8, p.doc_rel, '/');
            var list: std.ArrayList([]const u8) = .empty;
            while (parts.next()) |part| try list.append(arena, part);
            const leaf = list.items[list.items.len - 1];
            for (list.items[0 .. list.items.len - 1]) |dir| {
                var found: ?*Builder = null;
                for (node.children.items) |child| if (std.mem.eql(u8, child.name, dir)) {
                    found = child;
                };
                if (found == null) {
                    const child = try arena.create(Builder);
                    child.* = .{ .name = dir };
                    try node.children.append(arena, child);
                    found = child;
                }
                node = found.?;
            }
            if (isIndex(leaf)) {
                node.page = p.page;
            } else {
                const child = try arena.create(Builder);
                child.* = .{ .name = leaf, .page = p.page };
                try node.children.append(arena, child);
            }
        }
        return root.freeze(arena);
    }

    const Builder = struct {
        name: []const u8 = "",
        page: ?PageRef = null,
        children: std.ArrayList(*Builder) = .empty,

        fn freeze(b: *const Builder, arena: Allocator) !TreeNode {
            const kids = try arena.alloc(TreeNode, b.children.items.len);
            for (b.children.items, kids) |c, *k| k.* = try c.freeze(arena);
            return .{ .name = b.name, .page = b.page, .children = kids };
        }
    };
};

const DocPage = struct { doc_rel: []const u8, page: PageRef };

/// What templates see as `repo`.
const RepoView = struct {
    name: []const u8,
    title: []const u8,
    index: []const u8,
    web: ?[]const u8,
    blob: ?[]const u8,
    head: []const u8,
    category: []const u8,
    category_key: []const u8,
    description: ?[]const u8,
    readme_page: ?PageRef,
    doc_pages: []const PageRef,
    apis: []const ApiView,
    api_labels: []const []const u8,
    book_title: ?[]const u8,
    has_summary: bool,
    tree: TreeNode,
};

const Alternate = struct {
    lang: []const u8,
    name: []const u8,
    out: []const u8,
    current: bool,
};

/// What templates see as `page`.
const PageView = struct {
    title: []const u8,
    out: []const u8,
    rel: []const u8,
    data: vin.Value,
    radar: bool,
    lang: []const u8,
    translation: ?[]const u8,
    original: ?[]const u8,
    alternates: []const Alternate,
};

const Page = struct {
    repo: ?usize = null,
    rel: []const u8 = "",
    doc_rel: ?[]const u8 = null,
    out: []const u8 = "",
    data: std.json.ObjectMap = .empty,
    /// The whole file (markdown is rendered from it so source lines match).
    source: []const u8 = "",
    body: []const u8 = "",
    title: []const u8 = "",
    readme: bool = false,
    /// Stand-in entry page of a repo without a README (templates/repo-index.html).
    placeholder: bool = false,
    lang: []const u8 = "",
    translation: ?[]const u8 = null,
    original: ?[]const u8 = null,
    /// Heading ids of the source-language page, given to a translation's headings.
    heading_ids: ?[]const []const u8 = null,

    fn isTemplate(p: *const Page) bool {
        if (std.mem.endsWith(u8, p.rel, ".jinja")) return true;
        if (p.data.get("jinja")) |j| return j == .bool and j.bool;
        return false;
    }

    fn pageRef(p: *const Page) PageRef {
        return .{ .title = p.title, .out = p.out };
    }
};

/// A repo with its sources resolved.
const SiteRepo = struct {
    repo: *const Repo,
    links: *Links,
    /// (repo-relative source, output path) of every docs file that isn't a page.
    assets: []const [2][]const u8,
    /// Indexes into the page list, entry page first.
    pages: []const usize,
    apis: []const Api,
    docs_rel: ?[]const u8,
    book_title: ?[]const u8,
    summary: ?[]const u8,
    /// Key of the repo's own inputs; `render` folds in the global key.
    key: []const u8,

    /// Read a repo's README and docs into `pages`; null when it has neither
    /// pages nor a code reference. `index` is its position in the site's repos.
    fn load(sys: Sys, repo: *const Repo, apis: []const Api, index: usize, state: *const state_mod.State, pages: *std.ArrayList(Page)) !?SiteRepo {
        const a = sys.arena;
        const File = struct { rel: []const u8, doc_rel: ?[]const u8, out: []const u8 };
        var files: std.ArrayList(File) = .empty;
        if (repo.readme) |readme| try files.append(a, .{ .rel = readme, .doc_rel = null, .out = try std.fmt.allocPrint(a, "{s}/index.html", .{repo.name}) });
        var docs_rel: ?[]const u8 = null;
        var book_title: ?[]const u8 = null;
        const docs = sys.join(&.{ repo.path, "docs" });
        if (sys.isDir(docs)) {
            const root, const title = try docsRoot(sys, docs);
            const rel = if (std.mem.startsWith(u8, root, repo.path) and root.len > repo.path.len) root[repo.path.len + 1 ..] else root;
            for (try walk(sys, root)) |file| {
                try files.append(a, .{ .rel = try std.fmt.allocPrint(a, "{s}/{s}", .{ rel, file }), .doc_rel = file, .out = try std.fmt.allocPrint(a, "{s}/docs/{s}", .{ repo.name, try outName(a, file) }) });
            }
            docs_rel = rel;
            book_title = title;
        }
        var any_page = false;
        for (files.items) |f| if (isPage(f.rel)) {
            any_page = true;
        };
        if (apis.len == 0 and !any_page) return null;

        var inputs: std.ArrayList([]const u8) = .empty;
        try inputs.appendSlice(a, &.{ repo.config.fingerprint(a), repo.branch, repo.web orelse "" });
        for (apis) |api| try inputs.append(a, try std.fmt.allocPrint(a, "{s}\x00{s}", .{ api.tool, api.path }));
        const prefix = try std.fmt.allocPrint(a, "{s}/", .{repo.name});
        var api_ids: std.ArrayList([]const u8) = .empty;
        for (state.apidoc.map.keys()) |id| if (std.mem.startsWith(u8, id, prefix)) try api_ids.append(a, id);
        std.mem.sort([]const u8, api_ids.items, {}, sys_mod.lessThan);
        for (api_ids.items) |id| try inputs.append(a, state.apidoc.map.get(id).?.key);

        const links = try a.create(Links);
        links.* = .{
            .blob = if (repo.web) |w| try std.fmt.allocPrint(a, "{s}/blob/{s}/", .{ w, repo.branch }) else null,
            .raw = if (repo.web) |w| try std.fmt.allocPrint(a, "{s}/raw/{s}/", .{ w, repo.branch }) else null,
        };
        for (files.items) |f| try links.by_rel.put(a, f.rel, f.out);

        var site_pages: std.ArrayList(usize) = .empty;
        var assets: std.ArrayList([2][]const u8) = .empty;
        var summary: ?[]const u8 = null;
        for (files.items) |f| {
            const src = sys.join(&.{ repo.path, f.rel });
            try inputs.append(a, try std.fmt.allocPrint(a, "{s}\x00{s}", .{ f.rel, state_mod.fileId(sys, src) }));
            if (f.doc_rel != null and std.mem.eql(u8, f.doc_rel.?, "SUMMARY.md")) {
                summary = try sys.readFile(src);
            } else if (!isPage(f.rel)) {
                try assets.append(a, .{ f.rel, f.out });
            } else {
                const source = try sys.readFile(src);
                const fm = try frontMatter(a, source);
                try site_pages.append(a, pages.items.len);
                try pages.append(a, .{
                    .repo = index,
                    .rel = f.rel,
                    .doc_rel = f.doc_rel,
                    .out = f.out,
                    .data = fm.data,
                    .source = source,
                    .body = fm.body,
                    .title = try titleOf(a, &fm.data, fm.body, f.rel),
                    .readme = repo.readme != null and std.mem.eql(u8, f.rel, repo.readme.?),
                });
            }
        }
        if (repo.readme == null) {
            try site_pages.insert(a, 0, pages.items.len);
            try pages.append(a, .{
                .repo = index,
                .out = try std.fmt.allocPrint(a, "{s}/index.html", .{repo.name}),
                .title = repo.config.title orelse repo.name,
                .placeholder = true,
            });
        }
        return .{
            .repo = repo,
            .links = links,
            .assets = assets.items,
            .pages = site_pages.items,
            .apis = apis,
            .docs_rel = docs_rel,
            .book_title = book_title,
            .summary = summary,
            .key = state_mod.key(a, inputs.items),
        };
    }

    /// Whether wiki.toml `translate` covers the repo file `rel`.
    fn translates(s: *const SiteRepo, rel: []const u8) bool {
        const t = s.repo.config.translate;
        if (!t.enabled) return false;
        return t.files.len == 0 or config.pathspecMatches(t.files, rel);
    }

    fn group(s: *const SiteRepo) ?[]const u8 {
        const name = s.repo.name;
        return if (std.mem.lastIndexOfScalar(u8, name, '/')) |at| name[0..at] else null;
    }

    /// The repo as templates see it in a locale; `strings` translates the
    /// wiki.toml strings (descriptions, categories, book titles).
    fn view(s: *const SiteRepo, r: *const Renderer, pages: []const Page, strings: *const std.StringHashMapUnmanaged([]const u8)) !RepoView {
        const a = r.sys.arena;
        const repo = s.repo;
        var readme: ?*const Page = null;
        var docs: std.ArrayList(DocPage) = .empty;
        for (s.pages) |at| {
            const p = &pages[at];
            if (p.readme and readme == null) readme = p;
            if (p.doc_rel) |d| try docs.append(a, .{ .doc_rel = d, .page = p.pageRef() });
        }
        var apis: std.ArrayList(ApiView) = .empty;
        var labels: std.ArrayList([]const u8) = .empty;
        for (s.apis) |api| {
            const label = if (std.mem.eql(u8, api.tool, "rust")) "Rust" else if (std.mem.eql(u8, api.tool, "lua")) "Lua" else if (std.mem.eql(u8, api.tool, "js")) "JavaScript" else api.tool;
            try apis.append(a, .{ .tool = api.tool, .title = api.title, .label = label, .out = try std.fmt.allocPrint(a, "{s}/api/{s}", .{ repo.name, api.path }) });
            if (labels.items.len == 0 or !std.mem.eql(u8, labels.items[labels.items.len - 1], label)) try labels.append(a, label);
        }
        const doc_pages = try a.alloc(PageRef, docs.items.len);
        for (docs.items, doc_pages) |d, *p| p.* = d.page;
        const category_src = repo.config.category orelse s.group();
        const tr = struct {
            fn f(m: *const std.StringHashMapUnmanaged([]const u8), text: []const u8) []const u8 {
                return m.get(text) orelse text;
            }
        }.f;
        return .{
            .name = repo.name,
            .title = repo.config.title orelse basename(repo.name),
            .index = try std.fmt.allocPrint(a, "{s}{s}/index.html", .{ r.locale.prefix, repo.name }),
            .web = repo.web,
            .blob = s.links.blob,
            .head = repo.head,
            .category_key = category_src orelse "Other",
            .category = if (category_src) |c| tr(strings, c) else try r.t("category-other", &.{}),
            .description = if (repo.config.description) |d| tr(strings, d) else if (readme) |p| try markdown.blurb(a, p.body) else null,
            .readme_page = if (readme) |p| p.pageRef() else null,
            .doc_pages = doc_pages,
            .tree = try TreeNode.build(a, docs.items),
            .apis = apis.items,
            .api_labels = labels.items,
            .book_title = if (s.book_title) |b| tr(strings, b) else null,
            .has_summary = s.summary != null,
        };
    }
};

/// mdBook projects keep pages in book.toml's `src` (default "src").
fn docsRoot(sys: Sys, docs: []const u8) !struct { []const u8, ?[]const u8 } {
    const text = sys.readFileOr(sys.join(&.{ docs, "book.toml" })) orelse return .{ docs, null };
    const toml = @import("toml");
    var parser = toml.Parser(toml.Table).init(sys.arena);
    const parsed = parser.parseString(text) catch return .{ sys.join(&.{ docs, "src" }), null };
    var src: []const u8 = "src";
    var title: ?[]const u8 = null;
    if (parsed.value.get("book")) |book| if (book == .table) {
        if (book.table.get("src")) |v| if (v == .string) {
            src = v.string;
        };
        if (book.table.get("title")) |v| if (v == .string) {
            title = v.string;
        };
    };
    return .{ sys.join(&.{ docs, src }), title };
}

/// Files under `dir`, sorted, skipping hidden and git-ignored ones (git's
/// own ignore rules via `git ls-files`), and node_modules.
fn walk(sys: Sys, dir: []const u8) ![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    const out = sys.run(&.{ "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "." }, dir);
    if (out.ok) {
        var it = std.mem.splitScalar(u8, out.stdout, 0);
        while (it.next()) |rel| {
            if (rel.len == 0) continue;
            if (!sys.isFile(sys.join(&.{ dir, rel }))) continue; // deleted, or a submodule
            try files.append(sys.arena, rel);
        }
    } else {
        try files.appendSlice(sys.arena, try sys.walkFiles(dir));
    }
    var kept: std.ArrayList([]const u8) = .empty;
    for (files.items) |rel| {
        var hidden = false;
        var parts = std.mem.splitScalar(u8, rel, '/');
        while (parts.next()) |part| if ((part.len > 0 and part[0] == '.') or std.mem.eql(u8, part, "node_modules")) {
            hidden = true;
        };
        if (!hidden) try kept.append(sys.arena, rel);
    }
    std.mem.sort([]const u8, kept.items, {}, sys_mod.lessThan);
    // git lists each path once; dedupe anyway (cached + others overlap)
    var unique: std.ArrayList([]const u8) = .empty;
    for (kept.items) |rel| if (unique.items.len == 0 or !std.mem.eql(u8, unique.items[unique.items.len - 1], rel)) try unique.append(sys.arena, rel);
    return unique.items;
}

/// Remove everything in dist/ except the bundled assets.
fn clearPages(sys: Sys, dist: []const u8) !void {
    var dir = std.Io.Dir.cwd().openDir(sys.io, dist, .{ .iterate = true }) catch return;
    defer dir.close(sys.io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (try it.next(sys.io)) |entry| if (!std.mem.eql(u8, entry.name, "_assets")) try names.append(sys.arena, try sys.arena.dupe(u8, entry.name));
    for (names.items) |n| try sys.removeTree(sys.join(&.{ dist, n }));
}

// --------------------------------------------------------------- locales

pub const Locale = struct {
    tag: []const u8,
    index: usize,
    /// Output path prefix: "" for the source language, else "<tag lowercased>/".
    prefix: []const u8,

    fn isSource(l: Locale) bool {
        return l.prefix.len == 0;
    }
};

pub const source_lang = "en";

// --------------------------------------------------------------- rendering

pub const Result = struct {
    rendered: usize,
    total: usize,
    changed: []const []const u8,
};

pub fn render(sys: Sys, paths: Paths, cfg: *const config.Config, repos: []const Repo, apis: *const std.StringHashMapUnmanaged([]const Api), state: *state_mod.State, self_id: []const u8) !Result {
    const a = sys.arena;
    const site_title = sys.getenv("WIKI_TITLE") orelse "jbisfun wiki";

    var tags: std.ArrayList([]const u8) = .empty;
    try tags.append(a, source_lang);
    try tags.appendSlice(a, cfg.i18n.locales);
    var locales: std.ArrayList(Locale) = .empty;
    for (tags.items, 0..) |tag, i| {
        const prefix = if (i == 0) "" else blk: {
            const lower = try std.ascii.allocLowerString(a, tag);
            break :blk try std.fmt.allocPrint(a, "{s}/", .{lower});
        };
        try locales.append(a, .{ .tag = tag, .index = i, .prefix = prefix });
    }
    var locales_dir = try std.Io.Dir.cwd().openDir(sys.io, sys.join(&.{ paths.wiki, "locales" }), .{});
    defer locales_dir.close(sys.io);
    const loader = try fluent.Loader.load(a, sys.io, locales_dir, tags.items);

    var pages: std.ArrayList(Page) = .empty;
    var site_repos: std.ArrayList(SiteRepo) = .empty;
    for (repos) |*repo| {
        const repo_apis = apis.get(repo.name) orelse &.{};
        if (try SiteRepo.load(sys, repo, repo_apis, site_repos.items.len, state, &pages)) |site| try site_repos.append(a, site);
    }

    var global_inputs: std.ArrayList([]const u8) = .empty;
    try global_inputs.appendSlice(a, try state_mod.dirIds(sys, sys.join(&.{ paths.wiki, "templates" })));
    try global_inputs.append(a, self_id);
    try global_inputs.append(a, site_title);
    try global_inputs.appendSlice(a, try state_mod.dirIds(sys, sys.join(&.{ paths.wiki, "locales" })));
    try global_inputs.append(a, try std.mem.join(a, ",", cfg.i18n.locales));
    for (site_repos.items) |s| try global_inputs.append(a, s.repo.name);
    const global = state_mod.key(a, global_inputs.items);
    if (!std.mem.eql(u8, state.global, global) and sys.isDir(paths.dist)) try clearPages(sys, paths.dist);
    for (site_repos.items) |*s| s.key = state_mod.key(a, &.{ global, s.key });

    const pages_dir = sys.join(&.{ paths.wiki, "pages" });
    for (try walk(sys, pages_dir)) |rel| {
        if (!std.mem.endsWith(u8, rel, ".jinja")) continue;
        const source = try sys.readFile(sys.join(&.{ pages_dir, rel }));
        const fm = try frontMatter(a, source);
        const title = if (fm.data.get("title")) |t| (if (t == .string) t.string else site_title) else site_title;
        try pages.append(a, .{ .out = try outName(a, rel), .rel = rel, .data = fm.data, .source = source, .body = fm.body, .title = title });
    }
    for (pages.items) |*p| p.lang = source_lang;

    const templates_dir = try std.Io.Dir.cwd().openDir(sys.io, sys.join(&.{ paths.wiki, "templates" }), .{});
    const dir_loader = try vin.DirLoader.create(a, sys.io, templates_dir, .{});
    // the wiki's templates, then the theme package's (theme/macros.html: the
    // navbar's workspace tool bar)
    const theme_loader = try vin.MapLoader.create(a, &theme.templates);
    const loaders = try vin.MultiLoader.create(a);
    try loaders.add(dir_loader.loader());
    try loaders.add(theme_loader.loader());
    var env = try vin.Environment.initWithLoader(a, .{ .autoescape = true, .undefined_policy = .lenient }, loaders.loader());
    env.withIo(sys.io);
    var diag: vin.Diagnostic = .{};
    env.withDiag(&diag);

    var run: Run = .{ .sys = sys, .paths = paths, .state = state };
    const year = currentYear(sys.io);
    for (locales.items) |locale| {
        var strings: std.StringHashMapUnmanaged([]const u8) = .empty;
        const localized = if (locale.isSource()) try a.dupe(Page, pages.items) else try localize(sys, paths, cfg, &loader, locale, site_repos.items, pages.items, &strings);
        var r: Renderer = .{
            .sys = sys,
            .env = &env,
            .diag = &diag,
            .loader = &loader,
            .locales = locales.items,
            .locale = locale,
            .site_repos = site_repos.items,
            .views = &.{},
            .site = .none,
        };
        const views = try a.alloc(RepoView, site_repos.items.len);
        for (site_repos.items, views) |*s, *v| v.* = try s.view(&r, localized, &strings);
        r.views = views;
        const all_pages = try a.alloc(PageRef, localized.len);
        for (localized, all_pages) |*p, *ref| ref.* = p.pageRef();
        r.site = try vin.valueFrom(a, .{
            .title = site_title,
            .home = try std.fmt.allocPrint(a, "{s}index.html", .{locale.prefix}),
            .year = year,
            .lang = locale.tag,
            .repos = views,
            .pages = all_pages,
        });
        try run.locale(&r, localized, pages.items);
    }

    // drop the folders of repos that left the site
    for (state.repos.map.keys()) |name| {
        if (!run.kept.map.contains(name)) try sys.removeTree(sys.join(&.{ paths.dist, name }));
    }
    state.repos = run.kept;
    state.global = global;

    try writeManifest(sys, paths, site_repos.items, pages.items);

    var api_count: usize = 0;
    for (site_repos.items) |s| api_count += s.apis.len;
    const changed = if (run.changed.items.len == 0) "none" else try std.mem.join(a, ", ", run.changed.items);
    std.debug.print("wiki: {d} of {d} pages rendered, {d} code references; regenerated: {s}\n", .{ run.rendered, run.total, api_count, changed });
    return .{ .rendered = run.rendered, .total = run.total, .changed = run.changed.items };
}

/// `build/pages.json`: what `wiki serve`'s /api/pages and `wiki mcp`'s
/// wiki_pages answer (the source-language pages; paths on the server).
pub const Manifest = struct {
    repos: std.json.ArrayHashMap(ManifestRepo) = .{},
};

pub const ManifestRepo = struct {
    url: []const u8,
    docs: []const ManifestDoc,
};

pub const ManifestDoc = struct {
    /// The source file, relative to the repo (`README.md`, `docs/x.md`).
    file: []const u8,
    url: []const u8,
};

fn writeManifest(sys: Sys, paths: Paths, site_repos: []const SiteRepo, pages: []const Page) !void {
    const a = sys.arena;
    var m: Manifest = .{};
    for (site_repos, 0..) |s, at| {
        var docs: std.ArrayList(ManifestDoc) = .empty;
        for (pages) |p| {
            if (p.repo == null or p.repo.? != at or p.placeholder) continue;
            try docs.append(a, .{ .file = p.rel, .url = try serverPath(a, p.out) });
        }
        try m.repos.map.put(a, s.repo.name, .{
            .url = try serverPath(a, try std.fmt.allocPrint(a, "{s}/index.html", .{s.repo.name})),
            .docs = docs.items,
        });
    }
    var out: std.Io.Writer.Allocating = .init(a);
    try std.json.Stringify.value(m, .{ .whitespace = .indent_2 }, &out.writer);
    try sys.writeFile(sys.join(&.{ paths.build, "pages.json" }), out.written());
}

/// `/<out>`, with a trailing `index.html` dropped.
fn serverPath(a: Allocator, out: []const u8) ![]const u8 {
    const trimmed = if (std.mem.eql(u8, basename(out), "index.html")) out[0 .. out.len - "index.html".len] else out;
    return std.fmt.allocPrint(a, "/{s}", .{trimmed});
}

test "server paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("/pull/", try serverPath(arena.allocator(), "pull/index.html"));
    try std.testing.expectEqualStrings("/a/b/docs/x.html", try serverPath(arena.allocator(), "a/b/docs/x.html"));
}

fn currentYear(io: std.Io) i64 {
    const secs = std.Io.Timestamp.now(io, .real).toSeconds();
    const days = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(secs, 0)) };
    return days.getEpochDay().calculateYearDay().year;
}

/// Swap the repo pages for their `locale` translations (translating what's
/// missing or outdated first) and move every page under the locale's prefix.
/// Also fills `strings` with the wiki.toml strings' translations.
fn localize(sys: Sys, paths: Paths, cfg: *const config.Config, loader: *const fluent.Loader, locale: Locale, site_repos: []const SiteRepo, pages: []const Page, strings_out: *std.StringHashMapUnmanaged([]const u8)) ![]Page {
    const a = sys.arena;
    var cache = translate.Cache.load(sys, paths.wiki, locale.tag);
    const KeyIds = struct { key: []const u8, source_id: []const u8 };
    var keys: std.AutoHashMapUnmanaged(usize, KeyIds) = .empty;
    var strings: std.StringHashMapUnmanaged(void) = .empty;
    var string_list: std.ArrayList([]const u8) = .empty;
    var jobs: std.ArrayList(translate.Job) = .empty;
    var page_keys: std.StringHashMapUnmanaged(void) = .empty;
    for (site_repos) |*s| {
        for (s.pages) |at| {
            const p = &pages[at];
            if (p.placeholder or !s.translates(p.rel)) continue;
            const key = try std.fmt.allocPrint(a, "{s}/{s}", .{ s.repo.name, p.rel });
            const source_id = state_mod.blobId(a, p.source);
            const cached = cache.page(key, source_id);
            if (cached == null or !cached.?.current) try jobs.append(a, .{ .page = .{ .key = key, .source_id = source_id, .text = p.source } });
            try keys.put(a, at, .{ .key = key, .source_id = source_id });
            try page_keys.put(a, key, {});
        }
        const conf = s.repo.config;
        for ([_]?[]const u8{ conf.description, conf.category orelse s.group(), s.book_title }) |maybe| {
            const text = maybe orelse continue;
            if (!strings.contains(text)) {
                try strings.put(a, text, {});
                try string_list.append(a, text);
            }
        }
    }
    std.mem.sort([]const u8, string_list.items, {}, sys_mod.lessThan);
    for (string_list.items) |text| if (cache.string(text) == null) try jobs.append(a, .{ .string = text });
    var repo_names: std.ArrayList([]const u8) = .empty;
    for (site_repos) |s| try repo_names.append(a, s.repo.name);
    try cache.prune(repo_names.items, &page_keys, &strings);
    try translate.run(sys, cfg.i18n.translator, try loader.lookup(a, locale.index, "translator-language", &.{}), &cache, jobs.items);

    const out = try a.alloc(Page, pages.len);
    for (pages, 0..) |src, at| {
        var p = src;
        p.original = src.out;
        p.out = try std.mem.concat(a, u8, &.{ locale.prefix, src.out });
        p.lang = locale.tag;
        if (keys.get(at)) |k| {
            if (cache.page(k.key, k.source_id)) |cached| {
                if (!cached.current) warn("{s}: {s} translation is outdated", .{ k.key, locale.tag });
                if (!p.isTemplate()) p.heading_ids = try html.headingIds(a, try markdown.render(a, src.source));
                const text = try markdown.joinCjkLines(a, cached.text);
                const fm = try frontMatter(a, text);
                p.title = try titleOf(a, &fm.data, fm.body, p.rel);
                p.data = fm.data;
                p.body = fm.body;
                p.source = text;
                p.translation = "machine";
            } else p.translation = "missing";
        } else if (p.repo != null and !p.placeholder) {
            p.translation = "missing";
        }
        out[at] = p;
    }
    for (string_list.items) |text| if (cache.string(text)) |done| try strings_out.put(a, text, done);
    return out;
}

/// Bookkeeping across the languages of one render.
const Run = struct {
    sys: Sys,
    paths: Paths,
    state: *const state_mod.State,
    /// "<prefix><repo>" -> key of its rendered pages.
    kept: std.json.ArrayHashMap([]const u8) = .{},
    changed: std.ArrayList([]const u8) = .empty,
    rendered: usize = 0,
    total: usize = 0,

    /// Render `pages` (the site in `r.locale`; `sources` is the same list in
    /// the source language).
    fn locale(run: *Run, r: *Renderer, pages: []const Page, sources: []const Page) !void {
        const a = run.sys.arena;
        const dist = run.paths.dist;
        run.total += pages.len;
        for (r.site_repos, 0..) |*s, index| {
            const name = try std.mem.concat(a, u8, &.{ r.locale.prefix, s.repo.name });
            const key = if (r.locale.isSource()) s.key else blk: {
                // translations and translated strings are inputs too
                var inputs: std.ArrayList([]const u8) = .empty;
                var view_json: std.Io.Writer.Allocating = .init(a);
                try std.json.Stringify.value(r.views[index], .{}, &view_json.writer);
                try inputs.appendSlice(a, &.{ s.key, r.locale.tag, view_json.written() });
                for (s.pages) |at| try inputs.append(a, state_mod.blobId(a, pages[at].source));
                break :blk state_mod.key(a, inputs.items);
            };
            const dir = run.sys.join(&.{ dist, name });
            const previous = run.state.repos.map.get(name);
            const fresh = previous != null and std.mem.eql(u8, previous.?, key) and run.sys.isDir(dir);
            if (!fresh) {
                if (r.locale.isSource()) {
                    try r.copyFiles(run.paths, index);
                } else {
                    try run.sys.removeTree(dir);
                }
                try run.changed.append(a, name);
            }
            for (s.pages) |at| {
                const page = &pages[at];
                if (fresh and !page.isTemplate()) continue;
                try run.sys.writeFile(run.sys.join(&.{ dist, page.out }), try r.pageOrOriginal(page, &sources[at]));
                run.rendered += 1;
            }
            try run.kept.map.put(a, name, key);
        }
        for (pages) |*page| {
            if (page.repo != null) continue;
            try run.sys.writeFile(run.sys.join(&.{ dist, page.out }), try r.page(page));
            run.rendered += 1;
        }
    }
};

const Renderer = struct {
    sys: Sys,
    env: *vin.Environment,
    diag: *vin.Diagnostic,
    loader: *const fluent.Loader,
    locales: []const Locale,
    locale: Locale,
    site_repos: []const SiteRepo,
    views: []const RepoView,
    site: vin.Value,

    fn t(r: *const Renderer, key: []const u8, args: []const fluent.Arg) ![]const u8 {
        return r.loader.lookup(r.sys.arena, r.locale.index, key, args);
    }

    fn tIn(r: *const Renderer, locale: Locale, key: []const u8) ![]const u8 {
        return r.loader.lookup(r.sys.arena, locale.index, key, &.{});
    }

    // ---- template functions

    const UrlFn = struct {
        arena: Allocator,
        from: []const u8,

        fn call(ctx: *anyopaque, _: *vin.Ctx, args: vin.Args) vin.value.Error!vin.Value {
            const self: *UrlFn = @ptrCast(@alignCast(ctx));
            const to = (args.get(0, "path") orelse return error.BadArgument).toStrings() orelse return error.BadArgument;
            return vin.Value.fromString(url(self.arena, self.from, to) catch return error.OutOfMemory);
        }
    };

    fn urlFn(r: *const Renderer, from: []const u8) !vin.Callable {
        const f = try r.sys.arena.create(UrlFn);
        f.* = .{ .arena = r.sys.arena, .from = from };
        return .{ .ctx = f, .call = UrlFn.call };
    }

    const TFn = struct {
        r: *const Renderer,

        fn call(ctx: *anyopaque, _: *vin.Ctx, args: vin.Args) vin.value.Error!vin.Value {
            const self: *TFn = @ptrCast(@alignCast(ctx));
            const a = self.r.sys.arena;
            const key = (args.get(0, "key") orelse return error.BadArgument).toStrings() orelse return error.BadArgument;
            var fargs: std.ArrayList(fluent.Arg) = .empty;
            for (args.kw) |kw| {
                const value: fluent.Value = switch (kw.value) {
                    .integer => |n| .{ .number = @floatFromInt(n) },
                    .float => |f| .{ .number = f },
                    else => .{ .string = vin.value.strAlloc(a, kw.value) catch return error.OutOfMemory },
                };
                fargs.append(a, .{ .name = kw.name, .value = value }) catch return error.OutOfMemory;
            }
            return vin.Value.fromString(self.r.t(key, fargs.items) catch return error.OutOfMemory);
        }
    };

    fn tFn(r: *const Renderer) !vin.Callable {
        const f = try r.sys.arena.create(TFn);
        f.* = .{ .r = r };
        return .{ .ctx = f, .call = TFn.call };
    }

    /// Markdown with the repo's links resolved from one page.
    const Md = struct {
        r: *const Renderer,
        base: []const u8,
        from: []const u8,
        links: ?*const Links,
        heading_ids: ?[]const []const u8,

        fn render(m: *const Md, source: []const u8) ![]const u8 {
            const a = m.r.sys.arena;
            var out = try markdown.render(a, source);
            var result: []const u8 = out;
            if (m.heading_ids) |ids| result = try html.setHeadingIds(a, result, ids);
            if (m.links != null) result = try html.rewriteLinks(a, result, m, resolve);
            out = @constCast(result);
            return result;
        }

        fn resolve(m: *const Md, link: []const u8) anyerror!?[]const u8 {
            return m.links.?.resolve(m.r.sys.arena, link, m.base, m.from, m.r.locale.prefix);
        }

        fn call(ctx: *anyopaque, _: *vin.Ctx, args: vin.Args) vin.value.Error!vin.Value {
            const self: *Md = @ptrCast(@alignCast(ctx));
            const source = (args.get(0, "source") orelse return error.BadArgument).toStrings() orelse return error.BadArgument;
            const out = self.render(source) catch return error.InvalidExec;
            return vin.Value.fromMarkup(out);
        }
    };

    const Ctx = struct {
        site: vin.Value,
        page: PageView,
        repo: ?RepoView,
        url: vin.Callable,
        t: vin.Callable,
        md: vin.Callable,
        sidebar: vin.Str,
        content: vin.Str,
        // the workspace tool bar: always empty here; `wiki serve` puts the
        // live one into the pages it serves (serve.zig)
        tools: []const theme.ToolLink = no_tools,
    };

    fn renderNamed(r: *const Renderer, name: []const u8, ctx: anytype) ![]const u8 {
        const value = try vin.valueFrom(r.sys.arena, ctx);
        var tmpl = r.env.getTemplate(name) catch |err| {
            warn("template {s}: {t}: {f}", .{ name, err, r.diag.* });
            return err;
        };
        return tmpl.render(value) catch |err| {
            warn("template {s}: {t}: {f}", .{ name, err, r.diag.* });
            return err;
        };
    }

    fn renderString(r: *const Renderer, name: []const u8, source: []const u8, ctx: anytype) ![]const u8 {
        const value = try vin.valueFrom(r.sys.arena, ctx);
        var tmpl = r.env.fromString(source) catch |err| {
            warn("{s}: {t}: {f}", .{ name, err, r.diag.* });
            return err;
        };
        return tmpl.render(value) catch |err| {
            warn("{s}: {t}: {f}", .{ name, err, r.diag.* });
            return err;
        };
    }

    /// Start a repo's dist/ folder over with its docs assets and code reference.
    fn copyFiles(r: *const Renderer, paths: Paths, index: usize) !void {
        const sys = r.sys;
        const s = &r.site_repos[index];
        const name = s.repo.name;
        const dir = sys.join(&.{ paths.dist, name });
        try sys.removeTree(dir);
        for (s.assets) |asset| try sys.copyFile(sys.join(&.{ s.repo.path, asset[0] }), sys.join(&.{ paths.dist, asset[1] }));
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        for (s.apis) |api| {
            if (seen.contains(api.tool)) continue;
            try seen.put(sys.arena, api.tool, {});
            const dest = sys.join(&.{ dir, "api", api.tool });
            try sys.copyDir(sys.join(&.{ paths.build, "api", name, api.tool }), dest);
            // rustdoc/LDoc pages are standalone documents, not rendered
            // through layout.html: embed the site header so they stay
            // reachable. LDoc has no dark mode, so its header stays light.
            if (std.mem.eql(u8, api.tool, "rust")) try r.embedHeaders(dest, paths.dist, index, null);
            if (std.mem.eql(u8, api.tool, "lua")) try r.embedHeaders(dest, paths.dist, index, "light");
        }
    }

    /// Every `.html` file under `dir` (a freshly copied rustdoc/LDoc tree)
    /// gets the site header (partials/apidoc-header.html) spliced in after
    /// `<body>`: a fixed element whose content lives in a shadow root, so the
    /// site's stylesheet styles it without touching the doc tool's own CSS.
    fn embedHeaders(r: *const Renderer, dir: []const u8, dist: []const u8, repo: usize, doc_theme: ?[]const u8) !void {
        const sys = r.sys;
        const a = sys.arena;
        for (try sys.walkFiles(dir)) |rel| {
            if (!std.mem.endsWith(u8, rel, ".html")) continue;
            const path = sys.join(&.{ dir, rel });
            const from = path[dist.len + 1 ..];
            const doc = try sys.readFile(path);
            const body_at = findTag(doc, "<body") orelse continue;
            const body_end = (std.mem.indexOfScalarPos(u8, doc, body_at, '>') orelse continue) + 1;
            const header = try r.renderNamed("partials/apidoc-header.html", .{
                .site = r.site,
                .repo = r.views[repo],
                .url = try r.urlFn(from),
                .t = try r.tFn(),
                .theme = doc_theme,
                .tools = no_tools,
            });
            // header.js measures the header into --wiki-header-height; rustdoc's
            // sticky sidebar moves down by the same amount
            const head = try std.fmt.allocPrint(a, "  <script type=\"module\" src=\"{s}\"></script>\n  <style>" ++
                "body{{padding-top:var(--wiki-header-height,3.5rem)!important}}" ++
                ".rustdoc .sidebar{{top:var(--wiki-header-height,3.5rem);height:calc(100vh - var(--wiki-header-height,3.5rem))}}" ++
                "</style>\n", .{try url(a, from, "_assets/main.js")});
            var out: std.ArrayList(u8) = .empty;
            if (findTag(doc, "</head>")) |head_at| if (head_at < body_at) {
                try out.appendSlice(a, doc[0..head_at]);
                try out.appendSlice(a, head);
                try out.appendSlice(a, doc[head_at..body_end]);
            };
            if (out.items.len == 0) try out.appendSlice(a, doc[0..body_end]);
            try out.appendSlice(a, header);
            try out.appendSlice(a, doc[body_end..]);
            try sys.writeFile(path, out.items);
        }
    }

    /// A translated page whose translation doesn't render (a Jinja page the
    /// translator broke) falls back to the source language.
    fn pageOrOriginal(r: *const Renderer, p: *const Page, source: *const Page) ![]const u8 {
        return r.page(p) catch |err| {
            if (p.translation == null or !std.mem.eql(u8, p.translation.?, "machine")) return err;
            warn("{s} ({s}): {t}; showing the original", .{ p.out, r.locale.tag, err });
            var fallback = source.*;
            fallback.out = p.out;
            fallback.lang = p.lang;
            fallback.original = p.original;
            fallback.translation = "missing";
            return r.page(&fallback);
        };
    }

    /// The same page in every language.
    fn alternates(r: *const Renderer, p: *const Page) ![]const Alternate {
        const a = r.sys.arena;
        const path = if (std.mem.startsWith(u8, p.out, r.locale.prefix)) p.out[r.locale.prefix.len..] else p.out;
        const out = try a.alloc(Alternate, r.locales.len);
        for (r.locales, out) |l, *alt| alt.* = .{
            .lang = l.tag,
            .name = try r.tIn(l, "language-name"),
            .out = try std.mem.concat(a, u8, &.{ l.prefix, path }),
            .current = std.mem.eql(u8, l.tag, r.locale.tag),
        };
        return out;
    }

    fn page(r: *const Renderer, p: *const Page) anyerror![]const u8 {
        const a = r.sys.arena;
        const from = p.out;
        const md = try a.create(Md);
        md.* = .{
            .r = r,
            .base = if (std.mem.lastIndexOfScalar(u8, p.rel, '/')) |at| p.rel[0..at] else ".",
            .from = from,
            .links = if (p.repo) |at| r.site_repos[at].links else null,
            .heading_ids = p.heading_ids,
        };
        const url_fn = try r.urlFn(from);
        const side = if (p.repo) |at| try r.sidebar(at, from, url_fn) else "";
        var ctx: Ctx = .{
            .site = r.site,
            .page = .{
                .title = p.title,
                .out = p.out,
                .rel = p.rel,
                .data = try vin.value.fromJson(a, .{ .object = p.data }),
                .radar = p.original == null and p.repo != null and std.mem.endsWith(u8, p.rel, ".md") and !p.isTemplate(),
                .lang = p.lang,
                .translation = p.translation,
                .original = p.original,
                .alternates = try r.alternates(p),
            },
            .repo = if (p.repo) |at| r.views[at] else null,
            .url = url_fn,
            .t = try r.tFn(),
            .md = .{ .ctx = md, .call = Md.call },
            .sidebar = .{ .bytes = side, .safe = true },
            .content = .{ .bytes = "", .safe = true },
        };
        const content = if (p.placeholder)
            try r.renderNamed("repo-index.html", ctx)
        else if (p.isTemplate()) blk: {
            const out = try r.renderString(p.rel, p.body, ctx);
            break :blk if (std.mem.endsWith(u8, p.rel, ".md")) try md.render(out) else out;
        } else try md.render(p.source);
        var layout: []const u8 = "layout.html";
        if (p.data.get("layout")) |l| switch (l) {
            .bool => |b| if (!b) return content,
            .string => |s| layout = s,
            else => {},
        };
        ctx.content = .{ .bytes = content, .safe = true };
        return r.renderNamed(layout, ctx);
    }

    /// Repo navigation: README, code reference, then the docs (mdBook's
    /// SUMMARY.md when there is one, else the folder tree).
    fn sidebar(r: *const Renderer, at: usize, from: []const u8, url_fn: vin.Callable) ![]const u8 {
        const a = r.sys.arena;
        const s = &r.site_repos[at];
        var summary: ?vin.Str = null;
        if (s.summary) |source| {
            var text = source;
            // (?i)^#\s+Summary\s*\n
            if (text.len > 1 and text[0] == '#') {
                const nl = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
                if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, text[1..nl], " \t\r"), "summary")) text = text[@min(nl + 1, text.len)..];
            }
            const rendered = try markdown.render(a, text);
            const md: Md = .{ .r = r, .base = s.docs_rel orelse ".", .from = from, .links = s.links, .heading_ids = null };
            summary = .{ .bytes = try html.rewriteLinks(a, rendered, &md, Md.resolve), .safe = true };
        }
        const out = try r.renderNamed("partials/repo-nav.html", .{
            .repo = r.views[at],
            .summary = summary,
            .url = url_fn,
            .t = try r.tFn(),
        });
        return html.markActive(a, out, basename(from));
    }
};

/// Index of an HTML tag opening like `<body` (ASCII case-insensitive).
fn findTag(doc: []const u8, tag: []const u8) ?usize {
    var i: usize = 0;
    while (i + tag.len <= doc.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(doc[i .. i + tag.len], tag)) {
            if (tag[tag.len - 1] == '>') return i;
            if (i + tag.len < doc.len and (doc[i + tag.len] == '>' or std.ascii.isWhitespace(doc[i + tag.len]))) return i;
        }
    }
    return null;
}

test "urls" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("../_assets/style.css", try url(a, "pull/index.html", "_assets/style.css"));
    try std.testing.expectEqualStrings("index.html", try url(a, "pull/index.html", "pull/index.html"));
    try std.testing.expectEqualStrings("../../index.html", try url(a, "zh-tw/pull/index.html", "index.html"));
    try std.testing.expectEqualStrings("docs/a.html", try url(a, "pull/index.html", "pull/docs/a.html"));
    try std.testing.expectEqualStrings("https://x", try url(a, "pull/index.html", "https://x"));
    try std.testing.expectEqualStrings("index.html", try url(a, "index.html", ""));
    try std.testing.expectEqualStrings("docs/x.md", try cleanPath(a, "./docs/./x.md"));
    try std.testing.expectEqualStrings("../x", try cleanPath(a, "./../x"));
    try std.testing.expectEqualStrings("a/b.html", try outName(a, "a/b.md"));
    try std.testing.expectEqualStrings("index.html", try outName(a, "README.md"));
    try std.testing.expectEqualStrings("feed.xml", try outName(a, "feed.xml.jinja"));
}
