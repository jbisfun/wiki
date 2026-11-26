//! A Project Fluent (https://projectfluent.org, syntax 1.0) subset for the
//! wiki's chrome strings, `locales/<tag>/*.ftl`. There is no Zig Fluent
//! library; this covers what the wiki's files use, following the spec and
//! fluent-rs (fluent-bundle) behaviour:
//!   - messages `key = value`, values continued on indented lines
//!   - `#` comments, blank lines
//!   - placeables `{ $var }`, `{ "literal" }`, `{ other-message }`
//!   - select expressions `{ $n -> [one] ... *[other] ... }` with numeric
//!     keys and CLDR plural categories (one/other; zh/ja/ko have only other)
//! Placeables are not wrapped in Unicode isolation marks
//! (fluent-templates' `set_use_isolating(false)`), and a key missing from a
//! locale falls back to the source locale, as fluent-templates does.
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Arg = struct {
    name: []const u8,
    value: Value,
};

pub const Value = union(enum) {
    string: []const u8,
    number: f64,
};

/// One locale's messages: key -> raw value (pattern source, with
/// continuation lines joined by "\n" and their common indent removed).
pub const Bundle = struct {
    lang: []const u8,
    messages: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub fn parse(arena: Allocator, lang: []const u8, source: []const u8) !Bundle {
        var b: Bundle = .{ .lang = lang };
        var lines: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, source, '\n');
        while (it.next()) |l| try lines.append(arena, std.mem.trimEnd(u8, l, "\r"));
        var i: usize = 0;
        while (i < lines.items.len) {
            const line = lines.items[i];
            i += 1;
            if (line.len == 0 or line[0] == '#' or line[0] == ' ' or line[0] == '\t') continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], " \t");
            if (key.len == 0) continue;
            var value: std.ArrayList(u8) = .empty;
            const first = std.mem.trim(u8, line[eq + 1 ..], " \t");
            try value.appendSlice(arena, first);
            // continuation lines: indented (or blank between indented ones)
            var block: std.ArrayList([]const u8) = .empty;
            while (i < lines.items.len) {
                const next = lines.items[i];
                if (next.len > 0 and next[0] != ' ' and next[0] != '\t') break;
                if (next.len == 0) {
                    // a blank line belongs to the value only when more indented lines follow
                    var j = i;
                    while (j < lines.items.len and lines.items[j].len == 0) j += 1;
                    if (j >= lines.items.len or (lines.items[j][0] != ' ' and lines.items[j][0] != '\t')) break;
                }
                try block.append(arena, next);
                i += 1;
            }
            var indent: usize = std.math.maxInt(usize);
            for (block.items) |l| {
                if (std.mem.trim(u8, l, " \t").len == 0) continue;
                const t = std.mem.trimStart(u8, l, " \t");
                indent = @min(indent, l.len - t.len);
            }
            for (block.items) |l| {
                if (value.items.len > 0) try value.append(arena, '\n');
                try value.appendSlice(arena, if (l.len >= indent) l[indent..] else std.mem.trim(u8, l, " \t"));
            }
            try b.messages.put(arena, key, std.mem.trimEnd(u8, value.items, " \t\n"));
        }
        return b;
    }

    /// The message formatted with `args`, or null when the key is missing.
    pub fn format(b: *const Bundle, arena: Allocator, key: []const u8, args: []const Arg) !?[]const u8 {
        const pattern = b.messages.get(key) orelse return null;
        var out: std.ArrayList(u8) = .empty;
        var p: Pattern = .{ .src = pattern, .bundle = b, .args = args, .arena = arena };
        try p.pattern(&out, null);
        return out.items;
    }
};

const Pattern = struct {
    src: []const u8,
    i: usize = 0,
    bundle: *const Bundle,
    args: []const Arg,
    arena: Allocator,
    depth: u8 = 0,

    /// Text and placeables up to `stop` (a variant's end) or the end.
    fn pattern(p: *Pattern, out: *std.ArrayList(u8), stop: ?u8) anyerror!void {
        while (p.i < p.src.len) {
            const ch = p.src[p.i];
            if (stop) |s| if (ch == s) return;
            if (ch == '{') {
                p.i += 1;
                try p.placeable(out);
            } else if (ch == '\n' and stop != null) {
                // inside a variant, a line starting with `[` or `*[` or `}` ends it
                const rest = std.mem.trimStart(u8, p.src[p.i + 1 ..], " \t");
                if (rest.len == 0 or rest[0] == '[' or rest[0] == '}' or std.mem.startsWith(u8, rest, "*[")) return;
                try out.append(p.arena, '\n');
                p.i += 1;
                while (p.i < p.src.len and (p.src[p.i] == ' ' or p.src[p.i] == '\t')) p.i += 1;
            } else {
                try out.append(p.arena, ch);
                p.i += 1;
            }
        }
    }

    fn skipWs(p: *Pattern) void {
        while (p.i < p.src.len and std.ascii.isWhitespace(p.src[p.i])) p.i += 1;
    }

    fn ident(p: *Pattern) []const u8 {
        const start = p.i;
        while (p.i < p.src.len and (std.ascii.isAlphanumeric(p.src[p.i]) or p.src[p.i] == '-' or p.src[p.i] == '_')) p.i += 1;
        return p.src[start..p.i];
    }

    fn arg(p: *Pattern, name: []const u8) ?Value {
        for (p.args) |a| if (std.mem.eql(u8, a.name, name)) return a.value;
        return null;
    }

    fn display(p: *Pattern, out: *std.ArrayList(u8), v: Value) !void {
        switch (v) {
            .string => |s| try out.appendSlice(p.arena, s),
            .number => |n| if (n == @trunc(n) and @abs(n) < 1e15)
                try out.print(p.arena, "{d}", .{@as(i64, @intFromFloat(n))})
            else
                try out.print(p.arena, "{d}", .{n}),
        }
    }

    /// After `{`: an expression, optionally a select, then `}`.
    fn placeable(p: *Pattern, out: *std.ArrayList(u8)) !void {
        p.skipWs();
        var selector: ?Value = null;
        if (p.i < p.src.len and p.src[p.i] == '$') {
            p.i += 1;
            const name = p.ident();
            selector = p.arg(name) orelse .{ .string = try std.fmt.allocPrint(p.arena, "{{${s}}}", .{name}) };
        } else if (p.i < p.src.len and p.src[p.i] == '"') {
            p.i += 1;
            const start = p.i;
            while (p.i < p.src.len and p.src[p.i] != '"') p.i += 1;
            selector = .{ .string = p.src[start..p.i] };
            p.i += 1;
        } else {
            const name = p.ident();
            if (p.depth < 8) if (p.bundle.messages.get(name)) |_| {
                var sub: Pattern = .{ .src = p.bundle.messages.get(name).?, .bundle = p.bundle, .args = p.args, .arena = p.arena, .depth = p.depth + 1 };
                var tmp: std.ArrayList(u8) = .empty;
                try sub.pattern(&tmp, null);
                selector = .{ .string = tmp.items };
            };
            if (selector == null) selector = .{ .string = try std.fmt.allocPrint(p.arena, "{{{s}}}", .{name}) };
        }
        p.skipWs();
        if (std.mem.startsWith(u8, p.src[p.i..], "->")) {
            p.i += 2;
            try p.select(out, selector.?);
        } else {
            try p.display(out, selector.?);
        }
        p.skipWs();
        if (p.i < p.src.len and p.src[p.i] == '}') p.i += 1;
    }

    /// Variants `[key] pattern` / `*[key] pattern` up to the closing `}`.
    fn select(p: *Pattern, out: *std.ArrayList(u8), selector: Value) !void {
        const category = switch (selector) {
            .number => |n| plural(p.bundle.lang, n),
            .string => "",
        };
        var chosen: ?[]const u8 = null;
        var default: ?[]const u8 = null;
        while (true) {
            p.skipWs();
            if (p.i >= p.src.len or p.src[p.i] == '}') break;
            const is_default = p.src[p.i] == '*';
            if (is_default) p.i += 1;
            if (p.i >= p.src.len or p.src[p.i] != '[') break;
            p.i += 1;
            p.skipWs();
            const key_start = p.i;
            while (p.i < p.src.len and p.src[p.i] != ']') p.i += 1;
            const key = std.mem.trim(u8, p.src[key_start..p.i], " \t");
            p.i += 1;
            while (p.i < p.src.len and (p.src[p.i] == ' ' or p.src[p.i] == '\t')) p.i += 1;
            var body: std.ArrayList(u8) = .empty;
            try p.pattern(&body, '}');
            const text = std.mem.trim(u8, body.items, " \t\n");
            const matches = switch (selector) {
                .number => |n| std.mem.eql(u8, key, category) or (if (std.fmt.parseFloat(f64, key)) |k| k == n else |_| false),
                .string => |s| std.mem.eql(u8, key, s),
            };
            if (matches and chosen == null) chosen = text;
            if (is_default) default = text;
        }
        try out.appendSlice(p.arena, chosen orelse default orelse "");
    }
};

/// CLDR cardinal plural category for the languages likely here.
fn plural(lang: []const u8, n: f64) []const u8 {
    const base = if (std.mem.indexOfAny(u8, lang, "-_")) |at| lang[0..at] else lang;
    const no_plural = [_][]const u8{ "zh", "ja", "ko", "th", "vi", "id", "ms", "lo", "my" };
    for (no_plural) |l| if (std.ascii.eqlIgnoreCase(base, l)) return "other";
    if (std.ascii.eqlIgnoreCase(base, "fr") or std.ascii.eqlIgnoreCase(base, "pt")) return if (n >= 0 and n < 2 and n == @trunc(n)) "one" else "other";
    return if (n == 1) "one" else "other";
}

/// The site's locales, the source language first.
pub const Loader = struct {
    bundles: []Bundle,

    /// `locales/<tag>/*.ftl` for every tag.
    pub fn load(arena: Allocator, io: std.Io, dir: std.Io.Dir, tags: []const []const u8) !Loader {
        var bundles: std.ArrayList(Bundle) = .empty;
        for (tags) |tag| {
            var bundle: Bundle = .{ .lang = tag };
            if (dir.openDir(io, tag, .{ .iterate = true })) |d| {
                var sub = d;
                defer sub.close(io);
                var names: std.ArrayList([]const u8) = .empty;
                var it = sub.iterate();
                while (try it.next(io)) |entry| {
                    if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".ftl")) try names.append(arena, try arena.dupe(u8, entry.name));
                }
                std.mem.sort([]const u8, names.items, {}, lessThan);
                for (names.items) |name| {
                    const text = try sub.readFileAlloc(io, name, arena, .limited(1 << 20));
                    const parsed = try Bundle.parse(arena, tag, text);
                    var mit = parsed.messages.iterator();
                    while (mit.next()) |e| try bundle.messages.put(arena, e.key_ptr.*, e.value_ptr.*);
                }
            } else |_| {}
            try bundles.append(arena, bundle);
        }
        return .{ .bundles = bundles.items };
    }

    /// `key` in locale `index`, else in the source locale, else a marker.
    pub fn lookup(l: *const Loader, arena: Allocator, index: usize, key: []const u8, args: []const Arg) ![]const u8 {
        if (index < l.bundles.len) if (try l.bundles[index].format(arena, key, args)) |s| return s;
        if (l.bundles.len > 0) if (try l.bundles[0].format(arena, key, args)) |s| return s;
        return try std.fmt.allocPrint(arena, "Unknown localization {s}", .{key});
    }
};

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

test "fluent" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const en = try Bundle.parse(a, "en", "# c\nname = English\ndoc-pages = { $count ->\n    [one] 1 doc page\n   *[other] { $count } doc pages\n}\ncopy = Copyright { $year }\n");
    try std.testing.expectEqualStrings("English", (try en.format(a, "name", &.{})).?);
    try std.testing.expectEqualStrings("1 doc page", (try en.format(a, "doc-pages", &.{.{ .name = "count", .value = .{ .number = 1 } }})).?);
    try std.testing.expectEqualStrings("3 doc pages", (try en.format(a, "doc-pages", &.{.{ .name = "count", .value = .{ .number = 3 } }})).?);
    try std.testing.expectEqualStrings("Copyright 2026", (try en.format(a, "copy", &.{.{ .name = "year", .value = .{ .number = 2026 } }})).?);
    const zh = try Bundle.parse(a, "zh-TW", "doc-pages = { $count } 頁文件\n");
    try std.testing.expectEqualStrings("1 頁文件", (try zh.format(a, "doc-pages", &.{.{ .name = "count", .value = .{ .number = 1 } }})).?);
}
