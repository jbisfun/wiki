//! wiki.toml: per-repo settings and `[i18n]`.
const std = @import("std");
const toml = @import("toml");
const Allocator = std.mem.Allocator;

/// `tool = false` turns a doc tool off; a table configures it.
pub const Tool = struct {
    enabled: bool = true,
    /// rust: cargo packages (`-p`); default: the workspace's default members.
    packages: []const []const u8 = &.{},
    /// lua/js: pathspecs of tracked files; translate: pathspecs of pages.
    files: []const []const u8 = &.{},
};

pub const RepoConfig = struct {
    skip: bool = false,
    title: ?[]const u8 = null,
    category: ?[]const u8 = null,
    description: ?[]const u8 = null,
    rust: Tool = .{},
    lua: Tool = .{},
    js: Tool = .{},
    translate: Tool = .{},

    /// Stable text of the settings, for build keys.
    pub fn fingerprint(c: RepoConfig, arena: Allocator) []const u8 {
        var out: std.Io.Writer.Allocating = .init(arena);
        std.json.Stringify.value(c, .{}, &out.writer) catch @panic("OOM");
        return out.written();
    }
};

pub const Translator = struct {
    base_url: []const u8 = "http://localhost:11434/v1",
    model: []const u8 = "huihui_ai/qwen3.6-abliterated:35b-a3b",
    api_key_env: ?[]const u8 = null,
    reasoning_effort: ?[]const u8 = null,
    jobs: usize = 2,
    chunk: usize = 4000,
};

pub const I18n = struct {
    locales: []const []const u8 = &.{},
    translator: Translator = .{},
};

pub const Config = struct {
    repos: std.StringHashMapUnmanaged(RepoConfig) = .empty,
    i18n: I18n = .{},

    pub fn repo(c: *const Config, name: []const u8) RepoConfig {
        return c.repos.get(name) orelse .{};
    }
};

pub fn parse(arena: Allocator, text: []const u8) !Config {
    var parser = toml.Parser(toml.Table).init(arena);
    const parsed = parser.parseString(text) catch |err| {
        if (parser.error_info) |info| if (info == .parse) {
            std.debug.print("wiki: wiki.toml: parse error at line {d}, column {d}\n", .{ info.parse.line, info.parse.pos });
        };
        return err;
    };
    const root = parsed.value;
    var config: Config = .{};
    if (root.get("repos")) |repos| if (repos == .table) {
        var it = repos.table.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* != .table) continue;
            try config.repos.put(arena, e.key_ptr.*, try repoConfig(arena, e.value_ptr.table));
        }
    };
    if (root.get("i18n")) |i18n| if (i18n == .table) {
        const t = i18n.table;
        if (t.get("locales")) |v| config.i18n.locales = try strings(arena, v);
        if (t.get("translator")) |tr| if (tr == .table) {
            const x = tr.table;
            if (str(x.get("base_url"))) |s| config.i18n.translator.base_url = s;
            if (str(x.get("model"))) |s| config.i18n.translator.model = s;
            config.i18n.translator.api_key_env = str(x.get("api_key_env"));
            config.i18n.translator.reasoning_effort = str(x.get("reasoning_effort"));
            if (x.get("jobs")) |v| if (v == .integer) {
                config.i18n.translator.jobs = @intCast(@max(1, v.integer));
            };
            if (x.get("chunk")) |v| if (v == .integer) {
                config.i18n.translator.chunk = @intCast(@max(100, v.integer));
            };
        };
    };
    return config;
}

fn str(v: ?toml.Value) ?[]const u8 {
    const value = v orelse return null;
    return if (value == .string) value.string else null;
}

fn strings(arena: Allocator, v: toml.Value) ![]const []const u8 {
    if (v != .array) return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    for (v.array.items) |item| if (item == .string) try out.append(arena, item.string);
    return out.items;
}

fn tool(arena: Allocator, v: ?toml.Value) !Tool {
    const value = v orelse return .{};
    return switch (value) {
        .boolean => |b| .{ .enabled = b },
        .table => |t| .{
            .packages = if (t.get("packages")) |p| try strings(arena, p) else &.{},
            .files = if (t.get("files")) |f| try strings(arena, f) else &.{},
        },
        else => .{},
    };
}

fn repoConfig(arena: Allocator, t: *toml.Table) !RepoConfig {
    return .{
        .skip = if (t.get("skip")) |v| v == .boolean and v.boolean else false,
        .title = str(t.get("title")),
        .category = str(t.get("category")),
        .description = str(t.get("description")),
        .rust = try tool(arena, t.get("rust")),
        .lua = try tool(arena, t.get("lua")),
        .js = try tool(arena, t.get("js")),
        .translate = try tool(arena, t.get("translate")),
    };
}

/// git pathspec matching for the `files` settings: glob patterns where `*`
/// also crosses `/` (git's default, no `:(glob)` magic), or a literal
/// prefix directory.
pub fn pathspecMatches(specs: []const []const u8, path: []const u8) bool {
    for (specs) |spec| {
        if (globMatch(spec, path)) return true;
        const dir = std.mem.trimEnd(u8, spec, "/");
        if (dir.len > 0 and std.mem.startsWith(u8, path, dir) and path.len > dir.len and path[dir.len] == '/') return true;
    }
    return false;
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var mark: usize = 0;
    while (t < text.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            mark = t;
            p += 1;
        } else if (star) |s| {
            p = s + 1;
            mark += 1;
            t = mark;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

test "wiki.toml" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const c = try parse(a, "[i18n]\nlocales = [\"zh-TW\"]\n[repos.ycode]\nrust = { packages = [\"lua_hooks\"] }\ntranslate = { files = [\"README.md\"] }\n[repos.\"fossify-ios/clock-ios\"]\ntitle = \"Clock\"\n[repos.x]\nskip = true\nlua = false\n");
    try std.testing.expectEqualStrings("zh-TW", c.i18n.locales[0]);
    try std.testing.expectEqualStrings("lua_hooks", c.repo("ycode").rust.packages[0]);
    try std.testing.expectEqualStrings("Clock", c.repo("fossify-ios/clock-ios").title.?);
    try std.testing.expect(c.repo("x").skip and !c.repo("x").lua.enabled);
    try std.testing.expect(pathspecMatches(&.{"*.lua"}, "lib/a.lua"));
    try std.testing.expect(pathspecMatches(&.{"README.md"}, "README.md"));
    try std.testing.expect(!pathspecMatches(&.{"README.md"}, "docs/README.md"));
}
