//! Machine translation of repo pages and short strings (descriptions,
//! categories) through any OpenAI-compatible chat API: local Ollama by
//! default, set in wiki.toml `[i18n.translator]`.
//!
//! Results are cached in `translations/<tag>/` and committed with the wiki:
//! one file per page at `<repo>/<path in repo>`, `sources.json` (page ->
//! blob id of the English it was translated from) and `strings.json`
//! (English -> translation), byte-compatible with the Rust wiki's cache. A
//! page is sent again only when its English blob id changed; until the new
//! translation lands, the old one is shown. Translating is opt-in with `WIKI_TRANSLATE=1`; otherwise (or with an
//! unreachable endpoint) builds use the cache alone.
const std = @import("std");
const config = @import("config.zig");
const sys_mod = @import("sys.zig");
const Sys = sys_mod.Sys;
const warn = sys_mod.warn;

const Map = std.StringArrayHashMapUnmanaged([]const u8);

pub const Cache = struct {
    sys: Sys,
    dir: []const u8,
    sources: Map = .empty,
    strings: Map = .empty,

    pub const Cached = struct {
        text: []const u8,
        /// Translated from the current English (else from an older version).
        current: bool,
    };

    pub fn load(sys: Sys, wiki: []const u8, tag: []const u8) Cache {
        const dir = sys.join(&.{ wiki, "translations", tag });
        return .{ .sys = sys, .dir = dir, .sources = readJson(sys, sys.join(&.{ dir, "sources.json" })), .strings = readJson(sys, sys.join(&.{ dir, "strings.json" })) };
    }

    /// The translation of page `key` ("<repo>/<path>"), whose English has blob id `source_id`.
    pub fn page(c: *const Cache, key: []const u8, source_id: []const u8) ?Cached {
        const from = c.sources.get(key) orelse return null;
        const text = c.sys.readFileOr(c.sys.join(&.{ c.dir, key })) orelse return null;
        return .{ .text = text, .current = std.mem.eql(u8, from, source_id) };
    }

    pub fn string(c: *const Cache, english: []const u8) ?[]const u8 {
        return c.strings.get(english);
    }

    fn putPage(c: *Cache, key: []const u8, source_id: []const u8, text: []const u8) !void {
        try c.sys.writeFile(c.sys.join(&.{ c.dir, key }), text);
        try c.sources.put(c.sys.arena, key, source_id);
        try writeJson(c.sys, c.sys.join(&.{ c.dir, "sources.json" }), &c.sources);
    }

    fn putString(c: *Cache, english: []const u8, text: []const u8) !void {
        try c.strings.put(c.sys.arena, english, text);
        try writeJson(c.sys, c.sys.join(&.{ c.dir, "strings.json" }), &c.strings);
    }

    /// Drop translations of pages under `repos` that are no longer in
    /// `pages`, and strings not in `strings`.
    pub fn prune(c: *Cache, repos: []const []const u8, pages: *const std.StringHashMapUnmanaged(void), strings: *const std.StringHashMapUnmanaged(void)) !void {
        var gone: std.ArrayList([]const u8) = .empty;
        for (c.sources.keys()) |key| {
            if (pages.contains(key)) continue;
            for (repos) |repo| {
                if (key.len > repo.len and std.mem.startsWith(u8, key, repo) and key[repo.len] == '/') {
                    try gone.append(c.sys.arena, key);
                    break;
                }
            }
        }
        for (gone.items) |key| {
            c.sys.removeFile(c.sys.join(&.{ c.dir, key }));
            _ = c.sources.orderedRemove(key);
        }
        var dropped = false;
        var i: usize = 0;
        while (i < c.strings.count()) {
            if (!strings.contains(c.strings.keys()[i])) {
                c.strings.orderedRemoveAt(i);
                dropped = true;
            } else i += 1;
        }
        if (gone.items.len > 0) try writeJson(c.sys, c.sys.join(&.{ c.dir, "sources.json" }), &c.sources);
        if (dropped) try writeJson(c.sys, c.sys.join(&.{ c.dir, "strings.json" }), &c.strings);
    }
};

fn readJson(sys: Sys, path: []const u8) Map {
    var map: Map = .empty;
    const bytes = sys.readFileOr(path) orelse return map;
    const parsed = std.json.parseFromSliceLeaky(std.json.ArrayHashMap([]const u8), sys.arena, bytes, .{ .allocate = .alloc_always }) catch return map;
    var it = parsed.map.iterator();
    while (it.next()) |e| map.put(sys.arena, e.key_ptr.*, e.value_ptr.*) catch {};
    return map;
}

/// serde_json::to_string_pretty of a BTreeMap, plus a newline.
fn writeJson(sys: Sys, path: []const u8, map: *Map) !void {
    const Ctx = struct {
        keys: []const []const u8,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return std.mem.lessThan(u8, ctx.keys[a], ctx.keys[b]);
        }
    };
    map.sort(Ctx{ .keys = map.keys() });
    var out: std.Io.Writer.Allocating = .init(sys.arena);
    const w = &out.writer;
    if (map.count() == 0) {
        try w.writeAll("{}");
    } else {
        try w.writeAll("{\n");
        for (map.keys(), map.values(), 0..) |k, v, i| {
            try w.writeAll("  ");
            try std.json.Stringify.value(k, .{}, w);
            try w.writeAll(": ");
            try std.json.Stringify.value(v, .{}, w);
            if (i + 1 < map.count()) try w.writeAll(",");
            try w.writeAll("\n");
        }
        try w.writeAll("}");
    }
    try w.writeAll("\n");
    try sys.writeFile(path, out.written());
}

pub const Job = union(enum) {
    /// A markdown or Jinja page: `key` is "<repo>/<path>", `source_id` its blob id.
    page: struct { key: []const u8, source_id: []const u8, text: []const u8 },
    /// A one-line string (description, category).
    string: []const u8,

    fn name(j: Job) []const u8 {
        return switch (j) {
            .page => |p| p.key,
            .string => |s| s,
        };
    }
};

/// Translate `jobs` into `language` (a description for the prompt), saving
/// each result to `cache` as it lands, so an interrupted run keeps what it
/// finished. Requests go one at a time.
pub fn run(sys: Sys, cfg: config.Translator, language: []const u8, cache: *Cache, jobs: []const Job) !void {
    if (jobs.len == 0) return;
    // opt-in: a translation run starts the local model, so builds (and the
    // live server) use the cache unless WIKI_TRANSLATE=1
    if (!std.mem.eql(u8, sys.getenv("WIKI_TRANSLATE") orelse "", "1")) {
        warn("{d} untranslated pages/strings for {s} (set WIKI_TRANSLATE=1 to translate)", .{ jobs.len, cache.dir });
        return;
    }
    var t: Translator = try .init(sys, cfg, language);
    defer t.client.deinit();
    for (jobs, 1..) |job, done| {
        const result = switch (job) {
            .page => |p| t.markdown(p.text),
            .string => |s| t.chat(t.string_prompt, s),
        };
        const text = result catch |err| switch (err) {
            error.Unreachable => {
                warn("translator at {s} unreachable; using cached translations", .{cfg.base_url});
                return;
            },
            else => {
                warn("translating {s}: {t}", .{ job.name(), err });
                continue;
            },
        };
        switch (job) {
            .page => |p| try cache.putPage(p.key, p.source_id, text),
            .string => |s| try cache.putString(s, text),
        }
        std.debug.print("wiki: translated {d}/{d} {s}\n", .{ done, jobs.len, job.name() });
    }
}

const Translator = struct {
    sys: Sys,
    client: std.http.Client,
    cfg: config.Translator,
    api_key: ?[]const u8,
    page_prompt: []const u8,
    string_prompt: []const u8,

    fn init(sys: Sys, cfg: config.Translator, language: []const u8) !Translator {
        var api_key: ?[]const u8 = null;
        if (cfg.api_key_env) |name| {
            api_key = sys.getenv(name) orelse {
                warn("${s} (translator API key) is not set", .{name});
                return error.MissingApiKey;
            };
        }
        return .{
            .sys = sys,
            .client = .{ .allocator = sys.arena, .io = sys.io },
            .cfg = cfg,
            .api_key = api_key,
            .page_prompt = try std.fmt.allocPrint(sys.arena, "You translate software documentation from English into {s}. The input is a fragment of a " ++
                "Markdown (or Jinja/HTML) file. Translate the prose only. Keep exactly as they are: the Markdown " ++
                "structure and line breaks, code blocks and inline code, URLs and link targets, HTML tags and " ++
                "attributes, front matter keys, template tags such as {{{{ ... }}}} and {{% ... %}}, file names, " ++
                "commands, and product, project and repo names. Reply with the translated fragment only: no " ++
                "commentary, no surrounding code fence.", .{language}),
            .string_prompt = try std.fmt.allocPrint(sys.arena, "Translate the user's text from English into {s}. It is a short label or one-sentence " ++
                "description on a software documentation site. Keep product, project and repo names, file names " ++
                "and code as they are. Reply with the translation only.", .{language}),
        };
    }

    fn chat(t: *Translator, system: []const u8, text: []const u8) ![]const u8 {
        const a = t.sys.arena;
        const Message = struct { role: []const u8, content: []const u8 };
        var body: std.Io.Writer.Allocating = .init(a);
        try std.json.Stringify.value(.{
            .model = t.cfg.model,
            .messages = [_]Message{ .{ .role = "system", .content = system }, .{ .role = "user", .content = text } },
            .temperature = 0.2,
            .reasoning_effort = t.cfg.reasoning_effort,
        }, .{ .emit_null_optional_fields = false }, &body.writer);
        var response: std.Io.Writer.Allocating = .init(a);
        const url = try std.fmt.allocPrint(a, "{s}/chat/completions", .{std.mem.trimEnd(u8, t.cfg.base_url, "/")});
        const auth = if (t.api_key) |k| try std.fmt.allocPrint(a, "Bearer {s}", .{k}) else null;
        const result = t.client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = body.written(),
            .response_writer = &response.writer,
            .headers = .{ .content_type = .{ .override = "application/json" }, .authorization = if (auth) |v| .{ .override = v } else .default },
        }) catch return error.Unreachable;
        if (result.status != .ok) {
            warn("translator: HTTP {d}: {s}", .{ @intFromEnum(result.status), response.written() });
            return error.TranslatorFailed;
        }
        const Reply = struct { choices: []const struct { message: struct { content: ?[]const u8 = null } } };
        const reply = try std.json.parseFromSliceLeaky(Reply, a, response.written(), .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        if (reply.choices.len == 0) return error.EmptyReply;
        var content = reply.choices[0].message.content orelse return error.EmptyReply;
        // drop <think>...</think>
        while (std.mem.indexOf(u8, content, "<think>")) |open| {
            const close = std.mem.indexOfPos(u8, content, open, "</think>") orelse break;
            content = try std.mem.concat(a, u8, &.{ content[0..open], content[close + "</think>".len ..] });
        }
        content = std.mem.trim(u8, content, " \t\r\n");
        // a reply wrapped in a code fence the input didn't have
        if (!std.mem.startsWith(u8, std.mem.trimStart(u8, text, " \t\r\n"), "```") and std.mem.startsWith(u8, content, "```") and std.mem.endsWith(u8, content, "\n```")) {
            if (std.mem.indexOfScalar(u8, content, '\n')) |nl| {
                const lang = content[3..nl];
                var plain = true;
                for (lang) |ch| if (ch < 'a' or ch > 'z') {
                    plain = false;
                };
                if (plain and nl + 1 <= content.len - 4) content = content[nl + 1 .. content.len - 4];
            }
        }
        return content;
    }

    /// Chunk by markdown structure, translate each chunk, and put the
    /// whitespace around each chunk back so the layout survives.
    fn markdown(t: *Translator, text: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        for (try chunks(t.sys.arena, text, @max(t.cfg.chunk, 500))) |chunk| {
            const body = std.mem.trim(u8, chunk, " \t\r\n");
            if (body.len == 0) {
                try out.appendSlice(t.sys.arena, chunk);
                continue;
            }
            const lead = chunk[0 .. chunk.len - std.mem.trimStart(u8, chunk, " \t\r\n").len];
            const tail = chunk[std.mem.trimEnd(u8, chunk, " \t\r\n").len..];
            try out.appendSlice(t.sys.arena, lead);
            try out.appendSlice(t.sys.arena, try t.chat(t.page_prompt, body));
            try out.appendSlice(t.sys.arena, tail);
        }
        return out.items;
    }
};

/// Untrimmed chunks of at most `max` bytes (unless one block is bigger) that
/// cover `text` exactly, cut between markdown blocks: at blank lines and
/// before headings, never inside fenced code. A simplified take on
/// text-splitter's MarkdownSplitter, which the Rust wiki used.
pub fn chunks(arena: std.mem.Allocator, text: []const u8, max: usize) ![]const []const u8 {
    // block boundaries: offsets where a new block may start
    var cuts: std.ArrayList(usize) = .empty;
    try cuts.append(arena, 0);
    var fenced = false;
    var start: usize = 0;
    var prev_blank = false;
    while (start < text.len) {
        const end = if (std.mem.indexOfScalarPos(u8, text, start, '\n')) |e| e + 1 else text.len;
        const line = text[start..end];
        const t = std.mem.trimStart(u8, line, " \t");
        const blank = std.mem.trim(u8, line, " \t\r\n").len == 0;
        if (std.mem.startsWith(u8, t, "```") or std.mem.startsWith(u8, t, "~~~")) {
            if (!fenced and start > 0) try cuts.append(arena, start);
            fenced = !fenced;
        } else if (!fenced and start > 0 and !blank and (prev_blank or t.len > 0 and t[0] == '#')) {
            try cuts.append(arena, start);
        }
        prev_blank = blank and !fenced;
        start = end;
    }
    try cuts.append(arena, text.len);
    var out: std.ArrayList([]const u8) = .empty;
    var from: usize = 0;
    var i: usize = 1;
    while (i < cuts.items.len) : (i += 1) {
        const cut = cuts.items[i];
        const next = if (i + 1 < cuts.items.len) cuts.items[i + 1] else cut;
        if (cut == text.len or next - from > max) {
            if (cut > from) try out.append(arena, text[from..cut]);
            from = cut;
        }
    }
    return out.items;
}

test "chunks cover the text" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text = "# Title\n\nPara one\nstill.\n\n```\ncode\n\nmore\n```\n\n## Next\n\nlast para\n";
    const parts = try chunks(a, text, 10);
    try std.testing.expect(parts.len > 3);
    try std.testing.expectEqualStrings(text, try std.mem.concat(a, u8, parts));
}
