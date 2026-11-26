//! Rewriting attributes in rendered HTML (the Rust wiki used lol_html):
//! superhtml's HTML5 tokenizer finds every start tag and its attributes, and
//! edits are spliced into the original text, so everything else is kept byte
//! for byte. Covers markdown output and raw HTML alike.
const std = @import("std");
const Tokenizer = @import("superhtml").html.Tokenizer;
const Allocator = std.mem.Allocator;

pub const Attr = struct {
    name: []const u8,
    // raw (not entity-decoded), like lol_html's get_attribute
    value: ?[]const u8,
    // the whole attribute, `name="value"`
    start: u32,
    end: u32,
};

pub const Tag = struct {
    name: []const u8,
    attrs: []const Attr,
    // where a new attribute goes (before `>` or `/>`)
    insert_at: u32,

    pub fn get(tag: Tag, name: []const u8) ?[]const u8 {
        for (tag.attrs) |a| if (std.ascii.eqlIgnoreCase(a.name, name)) return a.value orelse "";
        return null;
    }

    fn find(tag: Tag, name: []const u8) ?Attr {
        for (tag.attrs) |a| if (std.ascii.eqlIgnoreCase(a.name, name)) return a;
        return null;
    }
};

const Edit = struct { start: u32, end: u32, text: []const u8 };

pub const Editor = struct {
    arena: Allocator,
    edits: std.ArrayList(Edit) = .empty,

    /// lol_html's set_attribute: replace the value, or add the attribute.
    pub fn set(e: *Editor, tag: Tag, name: []const u8, value: []const u8) !void {
        var text: std.ArrayList(u8) = .empty;
        try text.print(e.arena, "{s}=\"", .{name});
        for (value) |ch| if (ch == '"') try text.appendSlice(e.arena, "&quot;") else try text.append(e.arena, ch);
        try text.append(e.arena, '"');
        if (tag.find(name)) |a| {
            try e.edits.append(e.arena, .{ .start = a.start, .end = a.end, .text = text.items });
        } else {
            try e.edits.append(e.arena, .{ .start = tag.insert_at, .end = tag.insert_at, .text = try std.fmt.allocPrint(e.arena, " {s}", .{text.items}) });
        }
    }
};

/// Calls `visit(ctx, editor, tag)` for every start tag and applies its edits.
pub fn rewrite(arena: Allocator, html: []const u8, ctx: anytype, comptime visit: fn (@TypeOf(ctx), *Editor, Tag) anyerror!void) ![]const u8 {
    var editor: Editor = .{ .arena = arena };
    // tags first; then each start tag's own source again for its attributes
    // (superhtml's tokenizer only reports attributes in return_attrs mode,
    // which in turn leaves out the tag tokens)
    var tok: Tokenizer = .{ .language = .html };
    var attrs: std.ArrayList(Attr) = .empty;
    while (tok.next(html)) |t| switch (t) {
        .tag => |tag| {
            if (tag.kind != .start and tag.kind != .start_self) continue;
            const tag_name = tag.name.slice(html);
            attrs.clearRetainingCapacity();
            const src = html[0..tag.loc.end];
            var at: Tokenizer = .{ .language = .html, .return_attrs = true, .idx = tag.loc.start };
            while (at.next(src)) |a| switch (a) {
                .attr => |attr| try attrs.append(arena, .{
                    .name = attr.name.slice(src),
                    .value = if (attr.value) |v| v.loc.slice(src) else null,
                    .start = attr.name.start,
                    .end = attr.loc().end,
                }),
                .tag_name, .parse_error => {},
                else => break,
            };
            var insert_at: u32 = tag.loc.end - 1;
            if (insert_at > 0 and html[insert_at - 1] == '/') insert_at -= 1;
            while (insert_at > 0 and std.ascii.isWhitespace(html[insert_at - 1]) and insert_at - 1 > tag.name.end) insert_at -= 1;
            try visit(ctx, &editor, .{ .name = tag_name, .attrs = try arena.dupe(Attr, attrs.items), .insert_at = insert_at });
            if (tag.kind == .start) {
                if (std.ascii.eqlIgnoreCase(tag_name, "script")) {
                    tok.gotoScriptData();
                } else if (std.ascii.eqlIgnoreCase(tag_name, "style") or std.ascii.eqlIgnoreCase(tag_name, "xmp") or std.ascii.eqlIgnoreCase(tag_name, "iframe") or std.ascii.eqlIgnoreCase(tag_name, "noembed") or std.ascii.eqlIgnoreCase(tag_name, "noframes")) {
                    tok.gotoRawText(tag_name);
                } else if (std.ascii.eqlIgnoreCase(tag_name, "textarea") or std.ascii.eqlIgnoreCase(tag_name, "title")) {
                    tok.gotoRcData(tag_name);
                }
            }
        },
        else => {},
    };
    if (editor.edits.items.len == 0) return html;
    std.mem.sort(Edit, editor.edits.items, {}, struct {
        fn lt(_: void, a: Edit, b: Edit) bool {
            return a.start < b.start;
        }
    }.lt);
    var out: std.ArrayList(u8) = .empty;
    var last: u32 = 0;
    for (editor.edits.items) |e| {
        if (e.start < last) continue;
        try out.appendSlice(arena, html[last..e.start]);
        try out.appendSlice(arena, e.text);
        last = e.end;
    }
    try out.appendSlice(arena, html[last..]);
    return out.items;
}

fn isTag(tag: Tag, name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(tag.name, name);
}

/// Rewrite every `a[href]` / `img[src]` through `resolve(ctx, link)` (null
/// keeps the link) and give tables Bootstrap's look.
pub fn rewriteLinks(arena: Allocator, html: []const u8, ctx: anytype, comptime resolve: fn (@TypeOf(ctx), []const u8) anyerror!?[]const u8) ![]const u8 {
    const Visit = struct {
        fn visit(c: @TypeOf(ctx), e: *Editor, tag: Tag) anyerror!void {
            if (isTag(tag, "a")) {
                if (tag.get("href")) |href| if (try resolve(c, href)) |link| try e.set(tag, "href", link);
            } else if (isTag(tag, "img")) {
                if (tag.get("src")) |src| if (try resolve(c, src)) |link| try e.set(tag, "src", link);
            } else if (isTag(tag, "table")) {
                try e.set(tag, "class", "table table-sm table-striped");
            }
        }
    };
    return rewrite(arena, html, ctx, Visit.visit);
}

fn isHeading(tag: Tag) bool {
    return tag.name.len == 2 and (tag.name[0] == 'h' or tag.name[0] == 'H') and tag.name[1] >= '1' and tag.name[1] <= '6';
}

/// Ids of the headings in rendered HTML, in document order.
pub fn headingIds(arena: Allocator, html: []const u8) ![]const []const u8 {
    var ids: std.ArrayList([]const u8) = .empty;
    const Visit = struct {
        fn visit(list: *std.ArrayList([]const u8), e: *Editor, tag: Tag) anyerror!void {
            if (isHeading(tag)) if (tag.get("id")) |id| try list.append(e.arena, id);
        }
    };
    _ = try rewrite(arena, html, &ids, Visit.visit);
    return ids.items;
}

/// Give the headings of `html` the ids `ids` (in order) and point their `#`
/// links there too, so a translated page keeps the English anchors that links
/// from other pages use. Left alone when the heading counts differ.
pub fn setHeadingIds(arena: Allocator, html: []const u8, ids: []const []const u8) ![]const u8 {
    const current = try headingIds(arena, html);
    if (current.len != ids.len) return html;
    var same = true;
    for (current, ids) |a, b| {
        if (!std.mem.eql(u8, a, b)) same = false;
    }
    if (same) return html;
    var map: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (current, ids) |from, to| try map.put(arena, from, to);
    const Visit = struct {
        fn visit(m: *std.StringHashMapUnmanaged([]const u8), e: *Editor, tag: Tag) anyerror!void {
            if (isHeading(tag)) {
                if (tag.get("id")) |id| if (m.get(id)) |to| try e.set(tag, "id", to);
            } else if (isTag(tag, "a")) {
                if (tag.get("href")) |href| if (href.len > 0 and href[0] == '#') if (m.get(href[1..])) |to| {
                    try e.set(tag, "href", try std.fmt.allocPrint(e.arena, "#{s}", .{to}));
                };
            }
        }
    };
    return rewrite(arena, html, &map, Visit.visit);
}

/// Mark the links to `href` (the current page) as active.
pub fn markActive(arena: Allocator, html: []const u8, href: []const u8) ![]const u8 {
    const Visit = struct {
        fn visit(target: []const u8, e: *Editor, tag: Tag) anyerror!void {
            if (!isTag(tag, "a")) return;
            const h = tag.get("href") orelse return;
            if (!std.mem.eql(u8, h, target)) return;
            try e.set(tag, "class", "active");
            try e.set(tag, "aria-current", "page");
        }
    };
    return rewrite(arena, html, href, Visit.visit);
}

test "rewrite links" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const Ctx = struct {
        fn resolve(_: void, link: []const u8) anyerror!?[]const u8 {
            if (std.mem.eql(u8, link, "x.md")) return "x.html";
            return null;
        }
    };
    const out = try rewriteLinks(a, "<p><a href=\"x.md\" class=b>x</a><img src='y.png'/><table>\n<script>if (a<b) {}</script><a href=x.md>", {}, Ctx.resolve);
    try std.testing.expectEqualStrings("<p><a href=\"x.html\" class=b>x</a><img src='y.png'/><table class=\"table table-sm table-striped\">\n<script>if (a<b) {}</script><a href=\"x.html\">", out);
    const ids = try headingIds(a, "<h1 id=\"a\">A</h1><h2 id=\"b\">B</h2>");
    try std.testing.expectEqual(@as(usize, 2), ids.len);
    const moved = try setHeadingIds(a, "<h1 id=\"x\">A<a href=\"#x\"></a></h1>", &.{"a"});
    try std.testing.expectEqualStrings("<h1 id=\"a\">A<a href=\"#a\"></a></h1>", moved);
    try std.testing.expectEqualStrings("<a href=\"p.html\" class=\"active\" aria-current=\"page\">", try markActive(a, "<a href=\"p.html\">", "p.html"));
}
