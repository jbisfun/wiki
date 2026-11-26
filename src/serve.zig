//! `wiki serve`: the live wiki. Serves `<root>/.pull/wiki/dist` at `/`,
//! rebuilding what changed as pages are requested (at most every few
//! seconds; unchanged repos cost a `git status` each), plus the wiki's API:
//!
//!   GET /api/health                 {ok, tool, root, version}
//!   GET /api/pages?repo=R           {repo, url, docs: [{file, url}]}
//!   /_forge/...                     the forge proxies (forge.zig)
//!
//! Pages get two things on the way out, never in dist/ (which `wiki publish`
//! copies, so the published site stays static): `forge_meta`, which turns on
//! the forge features of assets/forge.js and radar.js, and the workspace tool
//! bar (Forge · CI · Wiki · Radar) after the navbar brand.
const std = @import("std");
const theme = @import("theme");
const discovery = @import("discovery");
const wiki = @import("wiki.zig");
const forge = @import("forge.zig");
const Sys = wiki.Sys;

pub const version = @import("build_options").version;

/// Seconds between rebuild checks triggered by page requests.
const rebuild_interval = 5;

pub const forge_meta = "<meta name=\"cpull-wiki\" content=\"" ++ forge.prefix ++ "\">";

pub const Options = struct {
    listen: []const u8 = "127.0.0.1:8090",
    /// Don't build on requests (tests, a read-only dist).
    rebuild: bool = true,
};

const Server = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    paths: wiki.Paths,
    rebuild: bool,
    mutex: std.Io.Mutex = .init,
    last_build: i64 = 0,
};

/// Bind, announce `.pull/wiki/serve.addr`, serve until killed.
pub fn run(io: std.Io, gpa: std.mem.Allocator, paths: wiki.Paths, options: Options) !void {
    const colon = std.mem.lastIndexOfScalar(u8, options.listen, ':') orelse return error.InvalidListenAddress;
    const port = std.fmt.parseInt(u16, options.listen[colon + 1 ..], 10) catch return error.InvalidListenAddress;
    const address = try std.Io.net.IpAddress.parseIp4(options.listen[0..colon], port);
    var net_server = try address.listen(io, .{ .reuse_address = true });
    defer net_server.deinit(io);
    const bound = try std.fmt.allocPrint(gpa, "{s}:{d}", .{ options.listen[0..colon], net_server.socket.address.getPort() });
    defer gpa.free(bound);
    var serving = discovery.announce(io, gpa, paths.root, .wiki, bound) catch |e| switch (e) {
        error.AlreadyServing => {
            std.debug.print("wiki: another `wiki serve` serves {s} already\n", .{paths.root});
            return error.AlreadyServing;
        },
        else => return e,
    };
    defer serving.release(io, gpa);
    installStopHandler(serving.addr_path);
    std.debug.print("wiki: serving {s} on http://{s}/\n", .{ paths.root, bound });

    var server: Server = .{ .io = io, .gpa = gpa, .paths = paths, .rebuild = options.rebuild };
    var tasks: std.Io.Group = .init;
    defer tasks.cancel(io);
    while (true) {
        const stream = net_server.accept(io) catch |e| {
            if (e == error.Canceled) return;
            std.debug.print("wiki: accept failed: {t}\n", .{e});
            continue;
        };
        tasks.concurrent(io, connection, .{ &server, stream }) catch |e| {
            std.debug.print("wiki: connection spawn failed: {t}\n", .{e});
            stream.close(io);
        };
    }
}

// SIGTERM/SIGINT (the pull job stopping): remove serve.addr, as
// Serving.release does on a clean stop; the kernel drops serve.lock.
var stop_addr_path: [std.fs.max_path_bytes:0]u8 = undefined;

fn installStopHandler(addr_path: []const u8) void {
    if (addr_path.len >= stop_addr_path.len) return;
    @memcpy(stop_addr_path[0..addr_path.len], addr_path);
    stop_addr_path[addr_path.len] = 0;
    const action: std.posix.Sigaction = .{ .handler = .{ .handler = onStop }, .mask = std.posix.sigemptyset(), .flags = 0 };
    std.posix.sigaction(std.posix.SIG.TERM, &action, null);
    std.posix.sigaction(std.posix.SIG.INT, &action, null);
}

fn onStop(_: std.posix.SIG) callconv(.c) void {
    _ = std.os.linux.unlink(&stop_addr_path);
    std.os.linux.exit_group(0);
}

fn connection(server: *Server, stream: std.Io.net.Stream) void {
    const io = server.io;
    defer stream.close(io);
    var send_buffer: [8192]u8 = undefined;
    var recv_buffer: [8192]u8 = undefined;
    var conn_br = stream.reader(io, &recv_buffer);
    var conn_bw = stream.writer(io, &send_buffer);
    var http = std.http.Server.init(&conn_br.interface, &conn_bw.interface);
    while (http.reader.state == .ready) {
        var request = http.receiveHead() catch break;
        handle(server, &request) catch |e| {
            std.debug.print("wiki: {s} failed: {t}\n", .{ request.head.target, e });
            request.respond(@errorName(e), .{ .status = .internal_server_error, .extra_headers = &.{.{ .name = "content-type", .value = "text/plain" }} }) catch {};
            break;
        };
    }
}

fn header(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    return null;
}

/// Writes are only taken from this server's own pages: a browser sends the
/// page's Origin, a server-to-server call none.
fn sameOrigin(request: *std.http.Server.Request) bool {
    const origin = header(request, "origin") orelse return true;
    const host = header(request, "host") orelse return false;
    const scheme_end = std.mem.indexOf(u8, origin, "://") orelse return false;
    return std.ascii.eqlIgnoreCase(origin[scheme_end + "://".len ..], host);
}

fn respondJson(request: *std.http.Server.Request, answer: forge.Answer) !void {
    try request.respond(answer.body, .{ .status = answer.status, .extra_headers = &.{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "cache-control", .value = "no-store" },
    } });
}

fn handle(server: *Server, request: *std.http.Server.Request) !void {
    const io = server.io;
    var arena_state = std.heap.ArenaAllocator.init(server.gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const sys: Sys = .{ .io = io, .arena = a };
    const target = request.head.target;
    const q = std.mem.indexOfScalar(u8, target, '?');
    const path = target[0 .. q orelse target.len];
    const query = if (q) |at| target[at + 1 ..] else "";
    const method = request.head.method;
    const get = method == .GET or method == .HEAD;

    if (std.mem.eql(u8, path, "/api/health") and get) {
        return respondJson(request, try forge.ok(a, .ok, .{ .ok = true, .tool = "wiki", .root = server.paths.root, .version = version }));
    }
    if (std.mem.eql(u8, path, "/api/pages") and get) {
        return respondJson(request, try pagesAnswer(sys, server.paths, try forge.queryParam(a, query, "repo")));
    }
    if (std.mem.startsWith(u8, path, "/api/")) return respondJson(request, try forge.err(a, .not_found, "no such api"));
    if (forge.matches(path)) {
        var body: ?[]const u8 = null;
        if (method == .POST) {
            if (!sameOrigin(request)) return respondJson(request, try forge.err(a, .forbidden, "cross-origin request"));
            const content_type = request.head.content_type orelse "";
            if (std.mem.indexOf(u8, content_type, "application/json") == null) return respondJson(request, try forge.err(a, .unsupported_media_type, "send application/json"));
            var buffer: [1024]u8 = undefined;
            body = request.readerExpectNone(&buffer).allocRemaining(a, .limited(256 * 1024)) catch return respondJson(request, try forge.err(a, .bad_request, "unreadable body"));
        }
        const upstream: forge.Upstream = .{ .io = io, .a = a, .root = server.paths.root };
        return respondJson(request, try forge.handle(upstream, method, target, body));
    }
    if (!get) return respondJson(request, try forge.err(a, .method_not_allowed, "GET only"));
    return serveFile(server, sys, request, path);
}

/// /api/pages: the wiki's pages of `repo` (paths on this server), from the
/// last build's manifest.
pub fn pagesAnswer(sys: Sys, paths: wiki.Paths, repo: ?[]const u8) !forge.Answer {
    const a = sys.arena;
    const name = repo orelse return forge.err(a, .bad_request, "repo is required");
    const m = wiki.manifest(sys, paths) orelse return forge.err(a, .service_unavailable, "the wiki hasn't been built yet");
    const entry = m.repos.map.get(name) orelse return forge.err(a, .not_found, "the wiki has no pages for that repo");
    return forge.ok(a, .ok, .{ .repo = name, .url = entry.url, .docs = entry.docs });
}

fn serveFile(server: *Server, sys: Sys, request: *std.http.Server.Request, path: []const u8) !void {
    const io = server.io;
    const a = sys.arena;
    var rel = try decode(a, path[1..]);
    if (rel.len == 0 or rel[rel.len - 1] == '/') rel = try std.mem.concat(a, u8, &.{ rel, "index.html" });
    if (std.mem.indexOf(u8, rel, "..") != null or std.mem.indexOfScalar(u8, rel, 0) != null) {
        return request.respond("bad path\n", .{ .status = .bad_request });
    }
    const paths = server.paths;
    const is_page = std.mem.endsWith(u8, rel, ".html");
    if (server.rebuild) {
        const now = std.Io.Timestamp.now(io, .real).toSeconds();
        if (!sys.isFile(sys.join(&.{ paths.dist, "index.html" }))) {
            // the first request waits for the first build
            try server.mutex.lock(io);
            defer server.mutex.unlock(io);
            if (!sys.isFile(sys.join(&.{ paths.dist, "index.html" }))) rebuild(server, true);
        } else if (is_page and now - @atomicLoad(i64, &server.last_build, .monotonic) >= rebuild_interval) {
            // other requests keep serving the current files while one rebuilds
            if (server.mutex.tryLock()) {
                defer server.mutex.unlock(io);
                rebuild(server, false);
            }
        }
    }

    const file = sys.join(&.{ paths.dist, rel });
    if (sys.isDir(file)) {
        const location = try std.fmt.allocPrint(a, "{s}/", .{path});
        return request.respond("", .{ .status = .moved_permanently, .extra_headers = &.{.{ .name = "location", .value = location }} });
    }
    const body = sys.readFile(file) catch {
        return request.respond("not found\n", .{ .status = .not_found, .extra_headers = &.{.{ .name = "content-type", .value = "text/plain; charset=utf-8" }} });
    };
    const out = if (is_page) try live(a, body, try toolBar(io, a, paths.root)) else body;
    try request.respond(out, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = contentType(rel) },
        .{ .name = "cache-control", .value = "no-cache" },
    } });
}

fn rebuild(server: *Server, wait: bool) void {
    const io = server.io;
    @atomicStore(i64, &server.last_build, std.Io.Timestamp.now(io, .real).toSeconds(), .monotonic);
    // a fresh arena per build: the request's one only lives as long as it
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const sys: Sys = .{ .io = io, .arena = arena_state.allocator() };
    // a `wiki build` (CLI, MCP) may hold the lock; pages keep being served from
    // what's there unless there is nothing yet
    const lock = (if (wait) wiki.BuildLock.acquire(sys, server.paths) catch null else wiki.BuildLock.tryAcquire(sys, server.paths) catch null) orelse return;
    defer lock.release(io);
    _ = wiki.build(sys, server.paths, false) catch |e| {
        std.debug.print("wiki: live rebuild failed: {t}\n", .{e});
    };
    @atomicStore(i64, &server.last_build, std.Io.Timestamp.now(io, .real).toSeconds(), .monotonic);
}

const tool_bar_template: []const theme.Template = &.{.{
    .name = "wiki/tools.html",
    .source = "{% import \"theme/macros.html\" as ui %}{{ ui.tools(tools) }}",
}};

/// The workspace tool bar's markup (theme macros.html `tools`), with this
/// server's own entry linking to `/`.
fn toolBar(io: std.Io, a: std.mem.Allocator, root: []const u8) ![]const u8 {
    const links = try theme.workspaceTools(io, a, root, .wiki, &.{});
    var out: std.Io.Writer.Allocating = .init(a);
    try theme.render(tool_bar_template, a, a, "wiki/tools.html", .{ .tools = links }, &out.writer);
    return out.written();
}

/// `page` with `forge_meta` before `</head>` and `tools` after the navbar
/// brand (the same place templates/partials/navbar.html calls the macro;
/// an API-doc page has its navbar in the header's shadow root).
pub fn live(a: std.mem.Allocator, page: []const u8, tools: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var rest = page;
    if (std.mem.indexOf(u8, rest, "</head>")) |head| {
        try out.appendSlice(a, rest[0..head]);
        try out.appendSlice(a, "  " ++ forge_meta ++ "\n");
        rest = rest[head..];
    }
    if (tools.len > 0) if (std.mem.indexOf(u8, rest, "class=\"navbar-brand")) |brand| if (std.mem.indexOfPos(u8, rest, brand, "</a>")) |end| {
        const after = end + "</a>".len;
        try out.appendSlice(a, rest[0..after]);
        try out.appendSlice(a, tools);
        rest = rest[after..];
    };
    try out.appendSlice(a, rest);
    return out.items;
}

fn decode(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '%') == null) return s;
    const raw = try a.dupe(u8, s);
    return std.Uri.percentDecodeInPlace(raw);
}

pub fn contentType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    const types = [_]struct { []const u8, []const u8 }{
        .{ ".html", "text/html; charset=utf-8" },
        .{ ".css", "text/css; charset=utf-8" },
        .{ ".js", "text/javascript; charset=utf-8" },
        .{ ".mjs", "text/javascript; charset=utf-8" },
        .{ ".json", "application/json" },
        .{ ".svg", "image/svg+xml" },
        .{ ".png", "image/png" },
        .{ ".jpg", "image/jpeg" },
        .{ ".jpeg", "image/jpeg" },
        .{ ".gif", "image/gif" },
        .{ ".webp", "image/webp" },
        .{ ".ico", "image/x-icon" },
        .{ ".woff2", "font/woff2" },
        .{ ".woff", "font/woff" },
        .{ ".ttf", "font/ttf" },
        .{ ".txt", "text/plain; charset=utf-8" },
        .{ ".md", "text/plain; charset=utf-8" },
        .{ ".xml", "application/xml" },
        .{ ".pdf", "application/pdf" },
    };
    for (types) |t| if (std.ascii.eqlIgnoreCase(ext, t[0])) return t[1];
    return "application/octet-stream";
}

test "live pages" {
    try std.testing.expectEqualStrings("text/css; charset=utf-8", contentType("_assets/style.css"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("<html><head><title>x</title>  " ++ forge_meta ++ "\n</head></html>", try live(a, "<html><head><title>x</title></head></html>", ""));
    try std.testing.expectEqualStrings("no head", try live(a, "no head", ""));
    try std.testing.expectEqualStrings(
        "<head>  " ++ forge_meta ++ "\n</head><nav><a class=\"navbar-brand x\" href=\"/\">W</a><ul>T</ul><a>y</a></nav>",
        try live(a, "<head></head><nav><a class=\"navbar-brand x\" href=\"/\">W</a><a>y</a></nav>", "<ul>T</ul>"),
    );
    var bar: std.Io.Writer.Allocating = .init(a);
    try theme.render(tool_bar_template, a, a, "wiki/tools.html", .{ .tools = try theme.toolNav(a, .initFill(null), .wiki) }, &bar.writer);
    try std.testing.expect(std.mem.indexOf(u8, bar.written(), "tool-switcher") != null);
    try std.testing.expect(std.mem.indexOf(u8, bar.written(), "href=\"/\"") != null);
}
