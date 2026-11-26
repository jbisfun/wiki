//! The wiki and the other workspace tools: what the live wiki's page scripts
//! (assets/forge.js, assets/radar.js) call on the wiki's own server, which
//! asks cpull, radar and idlci over their JSON APIs (theme
//! docs/workspace-tools.md §6). Browser pages never call another tool.
//!
//!   GET  /_forge/page?repo=R[&file=F]  R's cpull page and open issues (cpull
//!                                      /api/repos), the open reports anchored
//!                                      to F (radar /api/reports, else cpull's)
//!   GET  /_forge/repos                 every repo's cpull page and open issues
//!   GET  /_forge/ci/projects           idlci's /api/projects, links absolute
//!   POST /_forge/report                {repo, file, line, quote?, note?, title?}
//!                                      -> radar POST /api/reports (source "wiki")
//!
//! A tool that isn't running answers 503 `{"error":"<tool> isn't running"}`;
//! the scripts take any failure for "no forge". Links in the answers are
//! absolute (`http://<tool>/...`): the tools' APIs return paths on their own
//! servers.
const std = @import("std");
const discovery = @import("discovery");
const Allocator = std.mem.Allocator;
const Tool = discovery.Tool;
const Value = std.json.Value;

pub const prefix = "/_forge";

pub fn matches(path: []const u8) bool {
    return std.mem.startsWith(u8, path, prefix) and (path.len == prefix.len or path[prefix.len] == '/');
}

/// A response for the caller to send: status and a JSON body.
pub const Answer = struct {
    status: std.http.Status,
    body: []const u8,
};

/// Reaches another tool of the same workspace.
pub const Upstream = struct {
    io: std.Io,
    a: Allocator,
    root: []const u8,
    /// Overrides of the process environment (tests), else libc's.
    env: ?*const std.process.Environ.Map = null,

    pub const Reply = struct { status: std.http.Status, body: []const u8 };

    pub const Failure = union(enum) {
        /// not running, or running for another workspace
        down: []const u8,
        /// running, but the request failed or the answer isn't JSON
        failed: []const u8,
    };

    fn getenv(u: Upstream, name: []const u8) ?[]const u8 {
        if (u.env) |m| return m.get(name);
        const z = u.a.dupeSentinel(u8, name, 0) catch return null;
        const v = std.c.getenv(z) orelse return null;
        return std.mem.span(v);
    }

    /// `http://<addr>` of `tool`: its env var (CPULL_ADDR, ...), else its
    /// serve.addr while it holds serve.lock; null when it isn't running.
    pub fn base(u: Upstream, tool: Tool) !?[]const u8 {
        const addr = if (u.getenv(tool.envVar())) |x| (if (x.len > 0) try u.a.dupe(u8, x) else null) else null;
        const found = addr orelse (try discovery.read(u.io, u.a, u.root, tool)) orelse return null;
        return try discovery.baseUrl(u.a, found);
    }

    pub fn send(u: Upstream, method: std.http.Method, url: []const u8, payload: ?[]const u8) !Reply {
        var client: std.http.Client = .{ .allocator = u.a, .io = u.io };
        defer client.deinit();
        var out: std.Io.Writer.Allocating = .init(u.a);
        const res = try client.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = payload,
            .response_writer = &out.writer,
            .keep_alive = false,
            .headers = .{ .content_type = if (payload != null) .{ .override = "application/json" } else .default },
        });
        return .{ .status = res.status, .body = out.written() };
    }

    /// The tool's base url once its /api/health names this workspace.
    pub fn connect(u: Upstream, tool: Tool, failure: *Failure) !?[]const u8 {
        const url = (try u.base(tool)) orelse {
            failure.* = .{ .down = try std.fmt.allocPrint(u.a, "{s} isn't running", .{@tagName(tool)}) };
            return null;
        };
        const health = u.send(.GET, try std.fmt.allocPrint(u.a, "{s}/api/health", .{url}), null) catch {
            failure.* = .{ .down = try std.fmt.allocPrint(u.a, "{s} isn't running", .{@tagName(tool)}) };
            return null;
        };
        const v = std.json.parseFromSliceLeaky(Value, u.a, health.body, .{}) catch Value{ .null = {} };
        const served = if (v == .object) str(v.object, "root") else null;
        if (served == null or !sameDir(u, served.?, u.root)) {
            failure.* = .{ .down = try std.fmt.allocPrint(u.a, "{s} at {s} serves another workspace ({s})", .{ @tagName(tool), url, served orelse "?" }) };
            return null;
        }
        return url;
    }

    /// GET/POST `path` on `tool` and parse the JSON answer.
    pub fn json(u: Upstream, tool: Tool, method: std.http.Method, path: []const u8, payload: ?[]const u8, failure: *Failure) !?struct { base: []const u8, status: std.http.Status, value: Value } {
        const url = (try u.connect(tool, failure)) orelse return null;
        const reply = u.send(method, try std.fmt.allocPrint(u.a, "{s}{s}", .{ url, path }), payload) catch |e| {
            failure.* = .{ .failed = try std.fmt.allocPrint(u.a, "{s}{s}: {t}", .{ url, path, e }) };
            return null;
        };
        const value = std.json.parseFromSliceLeaky(Value, u.a, reply.body, .{}) catch {
            failure.* = .{ .failed = try std.fmt.allocPrint(u.a, "{s}{s} answered {d} with no JSON", .{ url, path, @intFromEnum(reply.status) }) };
            return null;
        };
        return .{ .base = url, .status = reply.status, .value = value };
    }
};

fn sameDir(u: Upstream, x: []const u8, y: []const u8) bool {
    if (std.mem.eql(u8, std.mem.trimEnd(u8, x, "/"), std.mem.trimEnd(u8, y, "/"))) return true;
    const rx = std.Io.Dir.cwd().realPathFileAlloc(u.io, x, u.a) catch return false;
    const ry = std.Io.Dir.cwd().realPathFileAlloc(u.io, y, u.a) catch return false;
    return std.mem.eql(u8, rx, ry);
}

fn str(o: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = o.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn int(o: std.json.ObjectMap, key: []const u8) ?i64 {
    const v = o.get(key) orelse return null;
    return switch (v) {
        .integer => |n| n,
        else => null,
    };
}

/// `base` ++ `path` for a path on that server; anything else as it is.
fn absolute(a: Allocator, base: []const u8, path: []const u8) ![]const u8 {
    if (path.len == 0 or path[0] != '/') return path;
    return std.fmt.allocPrint(a, "{s}{s}", .{ base, path });
}

/// Every `url`/`href` string under `v` made absolute against `base`.
pub fn absolutize(a: Allocator, base: []const u8, v: *Value) !void {
    switch (v.*) {
        .array => |*arr| for (arr.items) |*item| try absolutize(a, base, item),
        .object => |*obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                const is_link = std.mem.eql(u8, key, "url") or std.mem.eql(u8, key, "href") or std.mem.endsWith(u8, key, "_url") or std.mem.endsWith(u8, key, "_href");
                if (is_link and entry.value_ptr.* == .string) {
                    entry.value_ptr.* = .{ .string = try absolute(a, base, entry.value_ptr.string) };
                } else try absolutize(a, base, entry.value_ptr);
            }
        },
        else => {},
    }
}

const RepoInfo = struct {
    name: []const u8,
    url: []const u8,
    issues_url: []const u8,
    open_issues: i64 = 0,
    open_reports: i64 = 0,
    cloned: bool = false,
};

const PageReport = struct {
    id: []const u8,
    title: []const u8,
    line: i64,
    line_text: []const u8,
    quote: ?[]const u8,
    note: ?[]const u8,
    url: []const u8,
    created: []const u8,
};

const PageInfo = struct {
    workspace: []const u8,
    repo: ?RepoInfo,
    reports: []const PageReport,
};

fn repoInfo(a: Allocator, base: []const u8, v: Value) !?RepoInfo {
    if (v != .object) return null;
    const o = v.object;
    const cloned = if (o.get("cloned")) |c| c == .bool and c.bool else false;
    return .{
        .name = str(o, "name") orelse return null,
        .url = try absolute(a, base, str(o, "url") orelse ""),
        .issues_url = try absolute(a, base, str(o, "issues_url") orelse ""),
        .open_issues = int(o, "open_issues") orelse 0,
        .open_reports = int(o, "open_reports") orelse 0,
        .cloned = cloned,
    };
}

fn sameRepo(x: []const u8, y: []const u8) bool {
    const dot = struct {
        fn f(s: []const u8) []const u8 {
            return if (s.len == 0) "." else s;
        }
    }.f;
    return std.mem.eql(u8, dot(x), dot(y));
}

/// Answer a request under `prefix`. `target` is path and query; `body` is
/// the request body of a POST (already checked for origin and content type).
pub fn handle(u: Upstream, method: std.http.Method, target: []const u8, body: ?[]const u8) !Answer {
    const a = u.a;
    const q = std.mem.indexOfScalar(u8, target, '?');
    const path = target[0 .. q orelse target.len];
    const query = if (q) |at| target[at + 1 ..] else "";
    const sub = path[prefix.len..];
    const get = method == .GET or method == .HEAD;
    var failure: Upstream.Failure = .{ .down = "" };

    if (std.mem.eql(u8, sub, "/page") and get) {
        const name = try queryParam(a, query, "repo") orelse return err(a, .bad_request, "repo is required");
        const file = try queryParam(a, query, "file");
        const repos = (try u.json(.cpull, .GET, "/api/repos", null, &failure)) orelse return fail(a, failure);
        if (repos.value != .array) return err(a, .bad_gateway, "cpull /api/repos isn't a list");
        var info: ?RepoInfo = null;
        for (repos.value.array.items) |r| {
            const ri = (try repoInfo(a, repos.base, r)) orelse continue;
            if (sameRepo(ri.name, name)) info = ri;
        }
        var reports: std.ArrayList(PageReport) = .empty;
        if (info != null) if (file) |f| try pageReports(u, repos.base, name, f, &reports);
        return ok(a, .ok, PageInfo{ .workspace = std.fs.path.basename(u.root), .repo = info, .reports = reports.items });
    }
    if (std.mem.eql(u8, sub, "/repos") and get) {
        const repos = (try u.json(.cpull, .GET, "/api/repos", null, &failure)) orelse return fail(a, failure);
        if (repos.value != .array) return err(a, .bad_gateway, "cpull /api/repos isn't a list");
        var out: std.ArrayList(RepoInfo) = .empty;
        for (repos.value.array.items) |r| if (try repoInfo(a, repos.base, r)) |ri| try out.append(a, ri);
        return ok(a, .ok, out.items);
    }
    if (std.mem.eql(u8, sub, "/ci/projects") and get) {
        var projects = (try u.json(.idlci, .GET, "/api/projects", null, &failure)) orelse return fail(a, failure);
        if (projects.value == .array) for (projects.value.array.items) |*p| {
            if (p.* != .object) continue;
            // the project's page, which ProjectView doesn't carry
            if (str(p.object, "path")) |pp| if (p.object.get("url") == null) {
                try p.object.put(a, "url", .{ .string = try std.fmt.allocPrint(a, "/projects/{s}", .{pp}) });
            };
        };
        try absolutize(a, projects.base, &projects.value);
        return ok(a, projects.status, projects.value);
    }
    if (std.mem.eql(u8, sub, "/report") and method == .POST) {
        const New = struct { repo: []const u8, file: []const u8, line: u64, quote: ?[]const u8 = null, note: ?[]const u8 = null, title: ?[]const u8 = null };
        const new = std.json.parseFromSliceLeaky(New, a, body orelse "", .{ .ignore_unknown_fields = true }) catch return err(a, .bad_request, "expected {repo, file, line, quote?, note?, title?}");
        const payload = try std.json.Stringify.valueAlloc(a, .{
            .repo = new.repo,
            .file = new.file,
            .line = new.line,
            .quote = new.quote,
            .note = new.note,
            .title = new.title,
            .source = "wiki",
        }, .{ .emit_null_optional_fields = false });
        var filed = (try u.json(.radar, .POST, "/api/reports", payload, &failure)) orelse return fail(a, failure);
        // radar's report links are cpull issue pages
        if (filed.status.class() == .success) {
            if (try u.base(.cpull)) |cpull| try absolutize(a, cpull, &filed.value);
        }
        return ok(a, filed.status, filed.value);
    }
    return err(a, .not_found, "no such forge api");
}

/// The open reports anchored to `file`: radar's (relocated to the line the
/// text is on now), else cpull's as filed when radar isn't running.
fn pageReports(u: Upstream, cpull_base: []const u8, repo: []const u8, file: []const u8, out: *std.ArrayList(PageReport)) !void {
    const a = u.a;
    const query = try std.fmt.allocPrint(a, "/api/reports?status=open&repo={f}&file={f}", .{ std.fmt.alt(Component{ .s = repo }, .fmt), std.fmt.alt(Component{ .s = file }, .fmt) });
    var failure: Upstream.Failure = .{ .down = "" };
    const got = (try u.json(.radar, .GET, query, null, &failure)) orelse
        (try u.json(.cpull, .GET, query, null, &failure)) orelse return;
    if (got.value != .array) return;
    for (got.value.array.items) |r| {
        if (r != .object) continue;
        const o = r.object;
        if (!sameRepo(str(o, "repo") orelse repo, repo) or !std.mem.eql(u8, str(o, "file") orelse file, file)) continue;
        const status = str(o, "status") orelse "open";
        if (!std.mem.eql(u8, status, "open")) continue;
        const line = int(o, "current_line") orelse int(o, "line") orelse continue;
        try out.append(a, .{
            .id = str(o, "id") orelse "",
            .title = str(o, "title") orelse "",
            .line = line,
            .line_text = str(o, "line_text") orelse "",
            .quote = str(o, "quote"),
            .note = str(o, "note"),
            .url = try absolute(a, cpull_base, str(o, "url") orelse ""),
            .created = str(o, "created") orelse "",
        });
    }
    std.mem.sort(PageReport, out.items, {}, struct {
        fn lessThan(_: void, x: PageReport, y: PageReport) bool {
            return x.line < y.line;
        }
    }.lessThan);
}

/// A query string component, percent-encoded.
const Component = struct {
    s: []const u8,
    pub fn fmt(c: Component, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (c.s) |ch| {
            if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == '~' or ch == '/') {
                try w.writeByte(ch);
            } else try w.print("%{X:0>2}", .{ch});
        }
    }
};

fn fail(a: Allocator, failure: Upstream.Failure) !Answer {
    return switch (failure) {
        .down => |m| err(a, .service_unavailable, m),
        .failed => |m| err(a, .bad_gateway, m),
    };
}

pub fn ok(a: Allocator, status: std.http.Status, value: anytype) !Answer {
    return .{ .status = status, .body = try std.json.Stringify.valueAlloc(a, value, .{}) };
}

pub fn err(a: Allocator, status: std.http.Status, message: []const u8) !Answer {
    return .{ .status = status, .body = try std.json.Stringify.valueAlloc(a, .{ .@"error" = message }, .{}) };
}

/// The decoded value of `key` in a query string, or null.
pub fn queryParam(a: Allocator, query: []const u8, key: []const u8) !?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (!std.mem.eql(u8, pair[0..eq], key)) continue;
        const raw = try a.dupe(u8, pair[eq + 1 ..]);
        std.mem.replaceScalar(u8, raw, '+', ' ');
        return std.Uri.percentDecodeInPlace(raw);
    }
    return null;
}

test "forge paths and links" {
    try std.testing.expect(matches("/_forge/page"));
    try std.testing.expect(matches("/_forge"));
    try std.testing.expect(!matches("/_forgex"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("docs/a b.md", (try queryParam(a, "repo=fossify-ios%2Fcommons-ios&file=docs/a+b.md", "file")).?);
    try std.testing.expect(try queryParam(a, "", "repo") == null);
    var v = try std.json.parseFromSliceLeaky(Value, a,
        \\[{"path":"idl","url":"/projects/idl","last_build":{"href":"/jobs/4","n":1},"web":"https://x/y"}]
    , .{});
    try absolutize(a, "http://127.0.0.1:8737", &v);
    const o = v.array.items[0].object;
    try std.testing.expectEqualStrings("http://127.0.0.1:8737/projects/idl", o.get("url").?.string);
    try std.testing.expectEqualStrings("http://127.0.0.1:8737/jobs/4", o.get("last_build").?.object.get("href").?.string);
    try std.testing.expectEqualStrings("https://x/y", o.get("web").?.string);
    const encoded = try std.fmt.allocPrint(a, "{f}", .{std.fmt.alt(Component{ .s = "docs/a b&c.md" }, .fmt)});
    try std.testing.expectEqualStrings("docs/a%20b%26c.md", encoded);
}
