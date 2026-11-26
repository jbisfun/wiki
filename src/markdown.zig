//! Markdown for docs from many repos: GFM (tables, strikethrough, autolinks,
//! task lists, footnotes) and smart punctuation, parsed by cmark-gfm, the
//! GFM reference implementation. The HTML is written here rather than by
//! cmark's renderer, following comrak's (comrak 1.0 `html.rs`, the renderer the
//! Rust wiki used): `data-sourcepos` on every block and most inlines (so
//! Radar can map a selection back to its source line), GitHub-style heading
//! ids with anchor links, `{#id .class key=value}` heading attributes, and
//! code blocks highlighted at build time (the theme package's `highlight` module).
//!
//! Front matter is blanked out before parsing (line count kept), so source
//! positions count lines of the whole file, as comrak's do.
const std = @import("std");
const uucode = @import("uucode");
const c = @import("cmark.zig");
const highlight = @import("highlight");

const Allocator = std.mem.Allocator;
const Out = std.ArrayList(u8);

/// HTML of a markdown document.
pub fn render(arena: Allocator, source: []const u8) ![]u8 {
    var attrs: std.AutoHashMapUnmanaged(u32, Attrs) = .empty;
    const text = try prepare(arena, source, &attrs);
    const doc = parse(text) orelse return error.MarkdownParse;
    defer c.cmark_node_free(doc);

    var r: Renderer = .{ .arena = arena, .attrs = &attrs, .source = text };
    try r.footnotes(doc);
    try r.reserveIds(doc);
    try r.node(doc);
    if (r.footnote_ix > 0) {
        try r.write("</ol>");
        try r.lf();
        try r.write("</section>");
        try r.lf();
    }
    return r.out.toOwnedSlice(arena);
}

var registered = std.atomic.Value(bool).init(false);

fn parse(text: []const u8) ?*c.Node {
    if (!registered.swap(true, .acq_rel)) c.cmark_gfm_core_extensions_ensure_registered();
    const parser = c.cmark_parser_new(c.OPT_SOURCEPOS | c.OPT_UNSAFE | c.OPT_SMART | c.OPT_FOOTNOTES) orelse return null;
    defer c.cmark_parser_free(parser);
    inline for (.{ "table", "strikethrough", "autolink", "tasklist" }) |name| {
        if (c.cmark_find_syntax_extension(name)) |ext| _ = c.cmark_parser_attach_syntax_extension(parser, ext);
    }
    c.cmark_parser_feed(parser, text.ptr, text.len);
    return c.cmark_parser_finish(parser);
}

// ------------------------------------------------------------ preprocessing

/// The source as cmark gets it: mdBook commands as code spans, front matter
/// blanked, heading attributes cut off (and kept in `attrs` by line).
fn prepare(arena: Allocator, source: []const u8, attrs: *std.AutoHashMapUnmanaged(u32, Attrs)) ![]u8 {
    const pre = try preprocess(arena, source);
    var text = try arena.dupe(u8, pre);
    const fm = frontMatterLen(text);
    for (text[0..fm]) |*ch| {
        if (ch.* != '\n') ch.* = ' ';
    }
    // heading attributes on ATX headings outside fenced code
    var line_no: u32 = 1;
    var fence: ?Fence = null;
    var start: usize = 0;
    while (start < text.len) : (line_no += 1) {
        const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const line = text[start..end];
        if (fence) |f| {
            if (f.closes(line)) fence = null;
        } else if (Fence.opens(line)) |f| {
            fence = f;
        } else if (start >= fm) {
            if (atxContent(line)) |content_start| {
                if (parseOff(arena, try arena.dupe(u8, line[content_start..]))) |found| {
                    try attrs.put(arena, line_no, found.attrs);
                    for (text[start + content_start + found.cut .. end]) |*ch| ch.* = ' ';
                }
            }
        }
        start = end + 1;
    }
    return text;
}

const Fence = struct {
    char: u8,
    len: usize,

    fn opens(line: []const u8) ?Fence {
        const trimmed = std.mem.trimStart(u8, line, " ");
        if (line.len - trimmed.len > 3 or trimmed.len < 3) return null;
        const ch = trimmed[0];
        if (ch != '`' and ch != '~') return null;
        var n: usize = 0;
        while (n < trimmed.len and trimmed[n] == ch) n += 1;
        if (n < 3) return null;
        if (ch == '`' and std.mem.indexOfScalar(u8, trimmed[n..], '`') != null) return null;
        return .{ .char = ch, .len = n };
    }

    fn closes(f: Fence, line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len < f.len) return false;
        for (trimmed) |ch| if (ch != f.char) return false;
        return true;
    }
};

/// Where the text of an ATX heading line starts, or null.
fn atxContent(line: []const u8) ?usize {
    var i: usize = 0;
    while (i < line.len and i < 3 and line[i] == ' ') i += 1;
    var hashes: usize = 0;
    while (i < line.len and line[i] == '#') : (i += 1) hashes += 1;
    if (hashes == 0 or hashes > 6) return null;
    if (i < line.len and line[i] != ' ' and line[i] != '\t') return null;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    return i;
}

/// Replace the mdBook preprocessor commands used by the zed docs
/// (`{#kb action}` / `{#action action}`) with code spans.
pub fn preprocess(arena: Allocator, source: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, source, "{#") == null) return source;
    var out: Out = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, source, i, "{#")) |at| {
        const rest = source[at + 2 ..];
        const kw: ?[]const u8 = if (std.mem.startsWith(u8, rest, "kb")) "kb" else if (std.mem.startsWith(u8, rest, "action")) "action" else null;
        if (kw) |k| {
            const after = rest[k.len..];
            var ws: usize = 0;
            while (ws < after.len and std.ascii.isWhitespace(after[ws])) ws += 1;
            if (ws > 0) if (std.mem.indexOfScalar(u8, after[ws..], '}')) |close| if (close > 0) {
                try out.appendSlice(arena, source[i..at]);
                try out.append(arena, '`');
                try out.appendSlice(arena, std.mem.trim(u8, after[ws .. ws + close], " \t\r\n"));
                try out.append(arena, '`');
                i = at + 2 + k.len + ws + close + 1;
                continue;
            };
        }
        try out.appendSlice(arena, source[i .. at + 2]);
        i = at + 2;
    }
    try out.appendSlice(arena, source[i..]);
    return out.items;
}

/// Length of a leading `---` front matter block (with its closing line), or 0.
pub fn frontMatterLen(source: []const u8) usize {
    const first_end = std.mem.indexOfScalar(u8, source, '\n') orelse return 0;
    if (!std.mem.eql(u8, std.mem.trimEnd(u8, source[0..first_end], "\r"), "---")) return 0;
    var start = first_end + 1;
    while (start <= source.len) {
        const end = std.mem.indexOfScalarPos(u8, source, start, '\n') orelse source.len;
        if (std.mem.eql(u8, std.mem.trimEnd(u8, source[start..end], "\r"), "---")) {
            return @min(end + 1, source.len);
        }
        if (end == source.len) break;
        start = end + 1;
    }
    return 0;
}

// ------------------------------------------------------- heading attributes

pub const Attrs = struct {
    id: ?[]const u8 = null,
    classes: []const []const u8 = &.{},
    pairs: []const [2][]const u8 = &.{},
};

/// `{#id .class key=value}` at the end of a heading (comrak's
/// attributes::parse_off): the attributes and where the cut starts.
fn parseOff(arena: Allocator, content: []const u8) ?struct { attrs: Attrs, cut: usize } {
    const trimmed = std.mem.trimEnd(u8, content, " \t\r");
    if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '}') return null;
    const open = std.mem.lastIndexOfScalar(u8, trimmed, '{') orelse return null;
    if (open > 0 and trimmed[open - 1] != ' ' and trimmed[open - 1] != '\t') return null;
    const inner = trimmed[open + 1 .. trimmed.len - 1];
    var attrs: Attrs = .{};
    var classes: std.ArrayList([]const u8) = .empty;
    var pairs: std.ArrayList([2][]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, inner, " \t");
    var any = false;
    while (it.next()) |tok| {
        any = true;
        if (tok[0] == '#' and tok.len > 1) {
            attrs.id = tok[1..];
        } else if (tok[0] == '.' and tok.len > 1) {
            classes.append(arena, tok[1..]) catch return null;
        } else if (std.mem.indexOfScalar(u8, tok, '=')) |eq| {
            var value = tok[eq + 1 ..];
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') value = value[1 .. value.len - 1];
            pairs.append(arena, .{ tok[0..eq], value }) catch return null;
        } else return null;
    }
    if (!any) return null;
    attrs.classes = classes.items;
    attrs.pairs = pairs.items;
    var cut = open;
    while (cut > 0 and (content[cut - 1] == ' ' or content[cut - 1] == '\t')) cut -= 1;
    return .{ .attrs = attrs, .cut = cut };
}

// ----------------------------------------------------------------- renderer

const Renderer = struct {
    arena: Allocator,
    source: []const u8 = "",
    lines: std.ArrayList([]const u8) = .empty,
    out: Out = .empty,
    last_lf: bool = true,
    attrs: *std.AutoHashMapUnmanaged(u32, Attrs),
    ids: std.StringHashMapUnmanaged(void) = .empty,
    next_suffix: std.StringHashMapUnmanaged(usize) = .empty,
    footnote_ix: u32 = 0,
    written_footnote_ix: u32 = 0,
    // footnote definition -> its number of references; reference -> its ref number
    fn_totals: std.AutoHashMapUnmanaged(*c.Node, u32) = .empty,
    fn_refnum: std.AutoHashMapUnmanaged(*c.Node, u32) = .empty,

    fn write(r: *Renderer, s: []const u8) !void {
        if (s.len == 0) return;
        try r.out.appendSlice(r.arena, s);
        r.last_lf = s[s.len - 1] == '\n';
    }

    fn print(r: *Renderer, comptime fmt: []const u8, args: anytype) !void {
        try r.write(try std.fmt.allocPrint(r.arena, fmt, args));
    }

    fn cr(r: *Renderer) !void {
        if (!r.last_lf) try r.write("\n");
    }

    fn lf(r: *Renderer) !void {
        try r.write("\n");
    }

    fn escape(r: *Renderer, s: []const u8) !void {
        try escapeHtml(r.arena, &r.out, s);
        if (s.len > 0) r.last_lf = r.out.items[r.out.items.len - 1] == '\n';
    }

    fn escapeHref(r: *Renderer, s: []const u8) !void {
        try escapeHrefTo(r.arena, &r.out, s);
        r.last_lf = false;
    }

    fn sourcepos(r: *Renderer, n: *c.Node) !void {
        const sl = c.cmark_node_get_start_line(n);
        if (sl <= 0) return;
        var el = c.cmark_node_get_end_line(n);
        var ec = c.cmark_node_get_end_column(n);
        // cmark ends some blocks at column 0 of the line after them; comrak
        // ends them on their last non-blank line
        if (ec == 0 and el > sl) {
            el -= 1;
            while (el > sl and std.mem.trim(u8, r.line(el) orelse "", " \t\r").len == 0) el -= 1;
            const last: []const u8 = r.line(el) orelse "";
            ec = @intCast(last.len);
        }
        try r.print(" data-sourcepos=\"{d}:{d}-{d}:{d}\"", .{ sl, c.cmark_node_get_start_column(n), el, ec });
    }

    /// comrak's code span positions include the backticks; cmark's cover the
    /// content only, so widen them over the delimiters in the source.
    fn codeSourcepos(r: *Renderer, n: *c.Node) !void {
        const sl = c.cmark_node_get_start_line(n);
        const el = c.cmark_node_get_end_line(n);
        if (sl <= 0) return;
        var sc = c.cmark_node_get_start_column(n);
        var ec = c.cmark_node_get_end_column(n);
        if (r.line(sl)) |text| {
            var i: usize = @intCast(@max(sc - 1, 0));
            if (i > 0 and i <= text.len and text[i - 1] == ' ' and i >= 2 and text[i - 2] == '`') i -= 1;
            while (i > 0 and i <= text.len and text[i - 1] == '`') i -= 1;
            sc = @intCast(i + 1);
        }
        if (el != sl) ec += r.indent(el);
        if (r.line(el)) |text| {
            var i: usize = @intCast(@max(ec, 0));
            if (i < text.len and text[i] == ' ' and i + 1 < text.len and text[i + 1] == '`') i += 1;
            while (i < text.len and text[i] == '`') i += 1;
            ec = @intCast(i);
        }
        try r.print(" data-sourcepos=\"{d}:{d}-{d}:{d}\"", .{ sl, sc, el, ec });
    }

    /// cmark-gfm's autolink extension starts a bare URL's link one column
    /// early (on the space before it); comrak starts it on the URL.
    fn linkSourcepos(r: *Renderer, n: *c.Node) !void {
        const sl = c.cmark_node_get_start_line(n);
        if (sl <= 0) return;
        var sc = c.cmark_node_get_start_column(n);
        const el = c.cmark_node_get_end_line(n);
        var ec = c.cmark_node_get_end_column(n);
        if (el != sl) ec += r.indent(el);
        if (r.line(sl)) |text| {
            var label: Out = .empty;
            try r.collectText(n, &label);
            const i: usize = @intCast(@max(sc - 1, 0));
            if (label.items.len > 0 and i + 1 < text.len and text[i] != '[' and text[i] != '<' and !std.mem.startsWith(u8, text[i..], label.items) and std.mem.startsWith(u8, text[i + 1 ..], label.items)) sc += 1;
        }
        try r.print(" data-sourcepos=\"{d}:{d}-{d}:{d}\"", .{ sl, sc, el, ec });
    }

    /// Leading whitespace of a line: cmark's columns on an inline's later
    /// lines leave it out, comrak's count it.
    fn indent(r: *Renderer, number: c_int) c_int {
        const text = r.line(number) orelse return 0;
        var i: usize = 0;
        while (i < text.len and (text[i] == ' ' or text[i] == '\t')) i += 1;
        return @intCast(i);
    }

    fn line(r: *Renderer, number: c_int) ?[]const u8 {
        if (number < 1) return null;
        if (r.lines.items.len == 0) {
            var it = std.mem.splitScalar(u8, r.source, '\n');
            while (it.next()) |l| r.lines.append(r.arena, std.mem.trimEnd(u8, l, "\r")) catch return null;
        }
        const i: usize = @intCast(number - 1);
        return if (i < r.lines.items.len) r.lines.items[i] else null;
    }

    fn typeString(n: *c.Node) []const u8 {
        return std.mem.span(c.cmark_node_get_type_string(n));
    }

    fn literal(n: *c.Node) []const u8 {
        return if (c.cmark_node_get_literal(n)) |l| std.mem.span(l) else "";
    }

    fn children(r: *Renderer, n: *c.Node) anyerror!void {
        var child = c.cmark_node_first_child(n);
        while (child) |ch| : (child = c.cmark_node_next(ch)) try r.node(ch);
    }

    /// Children as plain text (image alt text).
    fn plain(r: *Renderer, n: *c.Node) !void {
        var child = c.cmark_node_first_child(n);
        while (child) |ch| : (child = c.cmark_node_next(ch)) {
            switch (c.cmark_node_get_type(ch)) {
                .text, .code, .html_inline => try r.escape(literal(ch)),
                .linebreak, .softbreak => try r.write(" "),
                else => try r.plain(ch),
            }
        }
    }

    fn footnotes(r: *Renderer, doc: *c.Node) !void {
        var stack: std.ArrayList(*c.Node) = .empty;
        try stack.append(r.arena, doc);
        // document order: depth first, children in order
        var order: std.ArrayList(*c.Node) = .empty;
        while (stack.pop()) |n| {
            try order.append(r.arena, n);
            var child = c.cmark_node_last_child(n);
            while (child) |ch| : (child = c.cmark_node_previous(ch)) try stack.append(r.arena, ch);
        }
        for (order.items) |n| {
            if (c.cmark_node_get_type(n) != .footnote_reference) continue;
            const def = c.cmark_node_parent_footnote_def(n) orelse continue;
            const gop = try r.fn_totals.getOrPut(r.arena, def);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
            try r.fn_refnum.put(r.arena, n, gop.value_ptr.*);
        }
    }

    fn reserveIds(r: *Renderer, doc: *c.Node) !void {
        var it = r.attrs.valueIterator();
        while (it.next()) |a| if (a.id) |id| try r.ids.put(r.arena, id, {});
        _ = doc;
    }

    /// GitHub's anchor algorithm, as comrak's Anchorizer.
    fn anchorize(r: *Renderer, header: []const u8) ![]const u8 {
        var id: Out = .empty;
        var view = std.unicode.Utf8View.init(header) catch std.unicode.Utf8View.initUnchecked(header);
        var cps = view.iterator();
        while (cps.nextCodepoint()) |cp0| {
            const cp: u21 = if (cp0 < 128) std.ascii.toLower(@intCast(cp0)) else uucode.get(.simple_lowercase_mapping, cp0);
            const permitted = cp == ' ' or cp == '-' or switch (uucode.get(.general_category, cp)) {
                .letter_uppercase, .letter_lowercase, .letter_titlecase, .letter_modifier, .letter_other => true,
                .mark_nonspacing, .mark_spacing_combining, .mark_enclosing => true,
                .number_decimal_digit, .number_letter, .number_other => true,
                .punctuation_connector => true,
                else => false,
            };
            if (!permitted) continue;
            if (cp == ' ') {
                try id.append(r.arena, '-');
            } else {
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(cp, &buf) catch continue;
                try id.appendSlice(r.arena, buf[0..len]);
            }
        }
        const base = id.items;
        var uniq: usize = r.next_suffix.get(base) orelse 0;
        const chosen = while (true) : (uniq += 1) {
            const anchor = if (uniq == 0) base else try std.fmt.allocPrint(r.arena, "{s}-{d}", .{ base, uniq });
            if (!r.ids.contains(anchor)) break anchor;
        };
        try r.ids.put(r.arena, chosen, {});
        try r.next_suffix.put(r.arena, base, uniq + 1);
        return chosen;
    }

    fn node(r: *Renderer, n: *c.Node) anyerror!void {
        switch (c.cmark_node_get_type(n)) {
            .document => try r.children(n),
            .block_quote => {
                try r.cr();
                try r.write("<blockquote");
                try r.sourcepos(n);
                try r.write(">");
                try r.lf();
                try r.children(n);
                try r.cr();
                try r.write("</blockquote>");
                try r.lf();
            },
            .list => {
                try r.cr();
                const ordered = c.cmark_node_get_list_type(n) == c.ORDERED_LIST;
                try r.write(if (ordered) "<ol" else "<ul");
                try r.sourcepos(n);
                const start = c.cmark_node_get_list_start(n);
                if (ordered and start != 1) try r.print(" start=\"{d}\"", .{start});
                try r.write(">");
                try r.lf();
                try r.children(n);
                try r.write(if (ordered) "</ol>" else "</ul>");
                try r.lf();
            },
            .item => {
                try r.cr();
                try r.write("<li");
                try r.sourcepos(n);
                try r.write(">");
                if (std.mem.eql(u8, typeString(n), "tasklist")) {
                    try r.write("<input type=\"checkbox\"");
                    if (c.cmark_gfm_extensions_get_tasklist_item_checked(n)) try r.write(" checked=\"\"");
                    try r.write(" disabled=\"\" /> ");
                }
                try r.children(n);
                try r.write("</li>");
                try r.lf();
            },
            .code_block => try r.codeBlock(n),
            .html_block => {
                try r.cr();
                try r.write(literal(n));
                try r.cr();
            },
            .paragraph => try r.paragraph(n),
            .heading => try r.heading(n),
            .thematic_break => {
                try r.cr();
                try r.write("<hr");
                try r.sourcepos(n);
                try r.write(" />");
                try r.lf();
            },
            .footnote_definition => {
                if (!r.fn_totals.contains(n)) return; // never referenced: dropped
                if (r.footnote_ix == 0) {
                    try r.write("<section");
                    try r.sourcepos(n);
                    try r.write(" class=\"footnotes\" data-footnotes>");
                    try r.lf();
                    try r.write("<ol>");
                    try r.lf();
                }
                r.footnote_ix += 1;
                try r.write("<li");
                try r.sourcepos(n);
                try r.write(" id=\"fn-");
                try r.escapeHref(literal(n));
                try r.write("\">");
                try r.children(n);
                if (try r.backref(n)) try r.lf();
                try r.write("</li>");
                try r.lf();
            },
            .text => try r.escape(literal(n)),
            .softbreak => try r.write("\n"),
            .linebreak => {
                try r.write("<br");
                try r.sourcepos(n);
                try r.write(" />");
                try r.lf();
            },
            .code => {
                try r.write("<code");
                try r.codeSourcepos(n);
                try r.write(">");
                try r.escape(literal(n));
                try r.write("</code>");
            },
            .html_inline => try r.write(literal(n)),
            .emph => {
                try r.write("<em");
                try r.sourcepos(n);
                try r.write(">");
                try r.children(n);
                try r.write("</em>");
            },
            .strong => {
                try r.write("<strong");
                try r.sourcepos(n);
                try r.write(">");
                try r.children(n);
                try r.write("</strong>");
            },
            .link => {
                try r.write("<a");
                try r.linkSourcepos(n);
                try r.write(" href=\"");
                try r.escapeHref(if (c.cmark_node_get_url(n)) |u| std.mem.span(u) else "");
                const title = if (c.cmark_node_get_title(n)) |t| std.mem.span(t) else "";
                if (title.len > 0) {
                    try r.write("\" title=\"");
                    try r.escape(title);
                }
                try r.write("\">");
                try r.children(n);
                try r.write("</a>");
            },
            .image => {
                try r.write("<img");
                try r.sourcepos(n);
                try r.write(" src=\"");
                try r.escapeHref(if (c.cmark_node_get_url(n)) |u| std.mem.span(u) else "");
                try r.write("\" alt=\"");
                try r.plain(n);
                const title = if (c.cmark_node_get_title(n)) |t| std.mem.span(t) else "";
                if (title.len > 0) {
                    try r.write("\" title=\"");
                    try r.escape(title);
                }
                try r.write("\" />");
            },
            .footnote_reference => {
                const def = c.cmark_node_parent_footnote_def(n) orelse return r.escape(literal(n));
                const label = literal(def);
                const ref_num = r.fn_refnum.get(n) orelse 1;
                try r.write("<sup");
                try r.sourcepos(n);
                try r.write(" class=\"footnote-ref\"><a href=\"#fn-");
                try r.escapeHref(label);
                try r.write("\" id=\"");
                try r.escapeHref(if (ref_num > 1) try std.fmt.allocPrint(r.arena, "fnref-{s}-{d}", .{ label, ref_num }) else try std.fmt.allocPrint(r.arena, "fnref-{s}", .{label}));
                try r.print("\" data-footnote-ref>{s}</a></sup>", .{literal(n)});
            },
            else => {
                const kind = typeString(n);
                if (std.mem.eql(u8, kind, "table")) {
                    try r.cr();
                    try r.write("<table");
                    try r.sourcepos(n);
                    try r.write(">");
                    try r.lf();
                    try r.children(n);
                    if (c.cmark_node_last_child(n) != c.cmark_node_first_child(n)) {
                        try r.cr();
                        try r.write("</tbody>");
                        try r.lf();
                    }
                    try r.cr();
                    try r.write("</table>");
                    try r.lf();
                } else if (std.mem.eql(u8, kind, "table_header") or std.mem.eql(u8, kind, "table_row")) {
                    const thead = std.mem.eql(u8, kind, "table_header");
                    try r.cr();
                    if (thead) {
                        try r.write("<thead>");
                        try r.lf();
                    } else if (c.cmark_node_previous(n)) |prev| if (std.mem.eql(u8, typeString(prev), "table_header")) {
                        try r.write("<tbody>");
                        try r.lf();
                    };
                    try r.write("<tr");
                    try r.sourcepos(n);
                    try r.write(">");
                    try r.children(n);
                    try r.cr();
                    try r.write("</tr>");
                    if (thead) {
                        try r.cr();
                        try r.write("</thead>");
                    }
                } else if (std.mem.eql(u8, kind, "table_cell")) {
                    const row = c.cmark_node_parent(n).?;
                    const thead = std.mem.eql(u8, typeString(row), "table_header");
                    const table = c.cmark_node_parent(row).?;
                    var index: usize = 0;
                    var prev = c.cmark_node_previous(n);
                    while (prev) |p| : (prev = c.cmark_node_previous(p)) index += 1;
                    try r.cr();
                    try r.write(if (thead) "<th" else "<td");
                    try r.sourcepos(n);
                    if (c.cmark_gfm_extensions_get_table_alignments(table)) |aligns| {
                        if (index < c.cmark_gfm_extensions_get_table_columns(table)) switch (aligns[index]) {
                            'l' => try r.write(" align=\"left\""),
                            'r' => try r.write(" align=\"right\""),
                            'c' => try r.write(" align=\"center\""),
                            else => {},
                        };
                    }
                    try r.write(">");
                    try r.children(n);
                    try r.write(if (thead) "</th>" else "</td>");
                } else if (std.mem.eql(u8, kind, "strikethrough")) {
                    try r.write("<del");
                    try r.sourcepos(n);
                    try r.write(">");
                    try r.children(n);
                    try r.write("</del>");
                } else {
                    try r.children(n);
                }
            },
        }
    }

    fn backref(r: *Renderer, def: *c.Node) !bool {
        if (r.written_footnote_ix >= r.footnote_ix) return false;
        r.written_footnote_ix = r.footnote_ix;
        const total = r.fn_totals.get(def) orelse 1;
        const label = literal(def);
        const fnix = r.footnote_ix;
        var ref_num: u32 = 1;
        while (ref_num <= total) : (ref_num += 1) {
            const suffix = if (ref_num > 1) try std.fmt.allocPrint(r.arena, "-{d}", .{ref_num}) else "";
            const sup = if (ref_num > 1) try std.fmt.allocPrint(r.arena, "<sup class=\"footnote-ref\">{d}</sup>", .{ref_num}) else "";
            if (ref_num > 1) try r.write(" ");
            try r.write("<a href=\"#fnref-");
            try r.escapeHref(label);
            try r.print("{s}\" class=\"footnote-backref\" data-footnote-backref data-footnote-backref-idx=\"{d}{s}\" aria-label=\"Back to reference {d}{s}\">\u{21a9}{s}</a>", .{ suffix, fnix, suffix, fnix, suffix, sup });
        }
        return true;
    }

    fn paragraph(r: *Renderer, n: *c.Node) !void {
        const tight = if (c.cmark_node_parent(n)) |item| if (c.cmark_node_parent(item)) |list|
            c.cmark_node_get_type(list) == .list and c.cmark_node_get_list_tight(list) != 0
        else
            false else false;
        if (tight) {
            if (c.cmark_node_previous(n)) |prev| if (c.cmark_node_get_type(prev) == .paragraph) try r.write("\n");
            try r.children(n);
            return;
        }
        try r.cr();
        try r.write("<p");
        try r.sourcepos(n);
        try r.write(">");
        try r.children(n);
        if (c.cmark_node_parent(n)) |parent| if (c.cmark_node_get_type(parent) == .footnote_definition and c.cmark_node_next(n) == null) {
            try r.write(" ");
            _ = try r.backref(parent);
        };
        try r.write("</p>");
        try r.lf();
    }

    fn collectText(r: *Renderer, n: *c.Node, out: *Out) !void {
        var child = c.cmark_node_first_child(n);
        while (child) |ch| : (child = c.cmark_node_next(ch)) {
            switch (c.cmark_node_get_type(ch)) {
                .text, .code => try out.appendSlice(r.arena, literal(ch)),
                .linebreak, .softbreak => try out.append(r.arena, ' '),
                else => try r.collectText(ch, out),
            }
        }
    }

    fn heading(r: *Renderer, n: *c.Node) !void {
        const level = c.cmark_node_get_heading_level(n);
        var text: Out = .empty;
        try r.collectText(n, &text);
        const attrs: Attrs = r.attrs.get(@intCast(c.cmark_node_get_start_line(n))) orelse .{};
        const id = attrs.id orelse try r.anchorize(text.items);
        try r.cr();
        try r.print("<h{d} id=\"", .{level});
        try r.escape(id);
        try r.write("\"");
        try r.sourcepos(n);
        if (attrs.classes.len > 0) {
            try r.write(" class=\"");
            try r.escape(try std.mem.join(r.arena, " ", attrs.classes));
            try r.write("\"");
        }
        for (attrs.pairs) |pair| {
            try r.print(" {s}=\"", .{pair[0]});
            try r.escape(pair[1]);
            try r.write("\"");
        }
        try r.write(">");
        try r.children(n);
        try r.write("<a href=\"#");
        try r.escape(id);
        try r.write("\" aria-label=\"Link to heading '");
        try r.escape(text.items);
        try r.write("'\" data-heading-content=\"");
        try r.escape(text.items);
        try r.write("\" class=\"anchor\"></a>");
        try r.print("</h{d}>", .{level});
        try r.lf();
    }

    fn codeBlock(r: *Renderer, n: *c.Node) !void {
        const info = if (c.cmark_node_get_fence_info(n)) |i| std.mem.span(i) else "";
        var first: usize = 0;
        while (first < info.len and !std.ascii.isWhitespace(info[first])) first += 1;
        const lang = info[0..first];
        try r.cr();
        try r.write("<pre class=\"syntax-highlighting\"");
        try r.sourcepos(n);
        try r.write("><code");
        if (info.len > 0) {
            try r.write(" class=\"language-");
            try r.escape(lang);
            try r.write("\"");
        }
        try r.write(">");
        try highlight.write(r.arena, &r.out, lang, literal(n));
        try r.write("</code></pre>");
        try r.lf();
    }
};

/// comrak's html::escape: `"`, `&`, `<`, `>` and NUL.
pub fn escapeHtml(arena: Allocator, out: *Out, s: []const u8) !void {
    var last: usize = 0;
    for (s, 0..) |ch, i| {
        const esc: []const u8 = switch (ch) {
            '"' => "&quot;",
            '&' => "&amp;",
            '<' => "&lt;",
            '>' => "&gt;",
            0 => "\u{fffd}",
            else => continue,
        };
        try out.appendSlice(arena, s[last..i]);
        try out.appendSlice(arena, esc);
        last = i + 1;
    }
    try out.appendSlice(arena, s[last..]);
}

/// comrak's html::escape_href.
pub fn escapeHrefTo(arena: Allocator, out: *Out, s: []const u8) !void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (std.ascii.isAlphanumeric(ch) or std.mem.indexOfScalar(u8, "-_.+!*(),#@?=;:/,+$~", ch) != null) {
            try out.append(arena, ch);
            continue;
        }
        switch (ch) {
            '&' => try out.appendSlice(arena, "&amp;"),
            '\'' => try out.appendSlice(arena, "&#x27;"),
            '%' => if (i + 2 < s.len and std.ascii.isHex(s[i + 1]) and std.ascii.isHex(s[i + 2])) {
                try out.appendSlice(arena, s[i .. i + 3]);
                i += 2;
            } else try out.appendSlice(arena, "%25"),
            0 => try out.appendSlice(arena, "%EF%BF%BD"),
            else => try out.print(arena, "%{X:0>2}", .{ch}),
        }
    }
}

// --------------------------------------------------------------- the blurb

/// Home page blurb: the first sentence of the first paragraph as plain text
/// (link and emphasis text kept, markup dropped), cut at its first top-level
/// comma, semicolon or colon when it runs past 80 columns.
pub fn blurb(arena: Allocator, source: []const u8) !?[]const u8 {
    var attrs: std.AutoHashMapUnmanaged(u32, Attrs) = .empty;
    const text_src = try prepare(arena, source, &attrs);
    const doc = parse(text_src) orelse return null;
    defer c.cmark_node_free(doc);
    const para = findParagraph(doc) orelse return null;
    var text: Out = .empty;
    try plainText(arena, para, &text);
    const t = std.mem.trim(u8, text.items, " \t\r\n");
    var end = t.len;
    if (std.mem.indexOf(u8, t, ". ")) |at| end = @min(end, at + 1);
    if (std.mem.indexOf(u8, t, "\u{3002}")) |at| end = @min(end, at + 3);
    const sentence = std.mem.trim(u8, t[0..end], " \t\r\n");
    if (sentence.len == 0) return null;
    var width: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(sentence);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| width += if (cp >= 0x2E80) 2 else 1;
    if (width > 80) {
        var depth: i32 = 0;
        it = view.iterator();
        var at: usize = 0;
        while (it.nextCodepointSlice()) |slice| : (at += slice.len) {
            const cp = std.unicode.utf8Decode(slice) catch continue;
            switch (cp) {
                '(', '[', 0xFF08, 0x300C => depth += 1,
                ')', ']', 0xFF09, 0x300D => depth -= 1,
                ',', ';', ':' => if (depth == 0) return try std.fmt.allocPrint(arena, "{s}.", .{sentence[0..at]}),
                0xFF0C, 0xFF1B, 0xFF1A => if (depth == 0) return try std.fmt.allocPrint(arena, "{s}\u{3002}", .{sentence[0..at]}),
                else => {},
            }
        }
    }
    return try arena.dupe(u8, sentence);
}

fn findParagraph(n: *c.Node) ?*c.Node {
    if (c.cmark_node_get_type(n) == .paragraph) return n;
    var child = c.cmark_node_first_child(n);
    while (child) |ch| : (child = c.cmark_node_next(ch)) {
        if (findParagraph(ch)) |p| return p;
    }
    return null;
}

fn plainText(arena: Allocator, n: *c.Node, out: *Out) !void {
    var child = c.cmark_node_first_child(n);
    while (child) |ch| : (child = c.cmark_node_next(ch)) {
        switch (c.cmark_node_get_type(ch)) {
            .text, .code => try out.appendSlice(arena, Renderer.literal(ch)),
            .softbreak, .linebreak => try out.append(arena, ' '),
            else => try plainText(arena, ch, out),
        }
    }
}

// ------------------------------------------------------------- CJK joining

fn isCjk(cp: u21) bool {
    return switch (uucode.get(.script, cp)) {
        .han, .hiragana, .katakana, .hangul => true,
        else => false,
    };
}

fn endsCjk(cp: u21) bool {
    return isCjk(cp) or std.mem.indexOfScalar(u21, &.{ 0xFF0C, 0x3002, 0xFF1B, 0xFF1A, 0x3001, 0xFF01, 0xFF1F, 0xFF09, 0x300D, 0x300F }, cp) != null;
}

fn startsCjk(cp: u21) bool {
    return isCjk(cp) or std.mem.indexOfScalar(u21, &.{ 0xFF08, 0x300C, 0x300E }, cp) != null;
}

/// Join soft line breaks between CJK characters (outside code blocks): a
/// browser renders a newline as a space, which CJK text doesn't have.
pub fn joinCjkLines(arena: Allocator, source: []const u8) ![]const u8 {
    var out: Out = .empty;
    var fenced = false;
    var start: usize = 0;
    while (start < source.len) {
        const nl = std.mem.indexOfScalarPos(u8, source, start, '\n');
        const end = if (nl) |e| e + 1 else source.len;
        const line = source[start..end];
        const t = std.mem.trimStart(u8, line, " \t");
        const is_fence = std.mem.startsWith(u8, t, "```") or std.mem.startsWith(u8, t, "~~~");
        if (is_fence) fenced = !fenced;
        try out.appendSlice(arena, line);
        // a prose line ending in CJK, followed by a prose line starting with CJK
        if (!fenced and !is_fence and nl != null and end < source.len) {
            const next_end = std.mem.indexOfScalarPos(u8, source, end, '\n') orelse source.len;
            const next = source[end..next_end];
            const next_t = std.mem.trimStart(u8, next, " \t");
            const next_fence = std.mem.startsWith(u8, next_t, "```") or std.mem.startsWith(u8, next_t, "~~~");
            const last = lastCp(line[0 .. line.len - 1]);
            const first = firstCp(next_t);
            if (!next_fence and last != null and first != null and endsCjk(last.?) and startsCjk(first.?)) {
                out.items.len -= 1; // the newline
                start = end + (next.len - next_t.len); // and the next line's indent
                continue;
            }
        }
        start = end;
    }
    return out.items;
}

fn lastCp(s: []const u8) ?u21 {
    if (s.len == 0) return null;
    var i = s.len - 1;
    while (i > 0 and s[i] & 0xC0 == 0x80) i -= 1;
    return std.unicode.utf8Decode(s[i..]) catch null;
}

fn firstCp(s: []const u8) ?u21 {
    if (s.len == 0) return null;
    const len = std.unicode.utf8ByteSequenceLength(s[0]) catch return null;
    if (len > s.len) return null;
    return std.unicode.utf8Decode(s[0..len]) catch null;
}

test "render basics" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const html = try render(a, "---\ntitle: x\n---\n# Hello `world`\n\nA *b* [c](d.md \"t\").\n\n## Custom {#here .cls}\n\n| a | b |\n|:-|-:|\n| 1 | 2 |\n");
    try std.testing.expect(std.mem.indexOf(u8, html, "<h1 id=\"hello-world\" data-sourcepos=\"4:1-4:15\">Hello <code data-sourcepos=\"4:9-4:15\">world</code><a href=\"#hello-world\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<h2 id=\"here\" data-sourcepos=\"8:1-8:") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, " class=\"cls\">Custom<a href=\"#here\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "<th data-sourcepos=\"10:2-10:4\" align=\"left\">a</th>") != null);
    try std.testing.expectEqualStrings("A sentence.", (try blurb(a, "A sentence. Another one.")).?);
    try std.testing.expectEqualStrings("中文句子。下一行", try joinCjkLines(a, "中文句子。\n下一行"));
}
