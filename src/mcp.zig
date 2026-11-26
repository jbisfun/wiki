//! `wiki mcp`: an MCP server (stdio, parley) for agents.
//!
//!   wiki_build   incremental build of the site (what `wiki build` does);
//!                returns how many pages were rendered and which repos changed
//!   wiki_pages   a repo's entry page and doc pages, as urls on the live
//!                server (`wiki serve`) when it runs, else as paths
const std = @import("std");
const parley = @import("parley");
const discovery = @import("discovery");
const wiki = @import("wiki.zig");
const serve = @import("serve.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Ctx = struct {
    io: Io,
    gpa: Allocator,
    paths: wiki.Paths,
};

const Def = struct {
    name: []const u8,
    description: []const u8,
    schema: []const u8,
    run: *const fn (ctx: *const Ctx, a: Allocator, args: std.json.Value) anyerror!Result,
};

const Result = union(enum) { ok: []const u8, err: []const u8 };

pub const defs = [_]Def{
    .{
        .name = "wiki_build",
        .description = "wiki: build the workspace wiki incrementally (only repos whose sources changed, by git object id, are regenerated) into .pull/wiki/dist, which `wiki serve` serves live; returns the rendered/total page counts and the repos that changed. `force` rebuilds everything (slow: every repo's code reference).",
        .schema =
        \\{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{"force":{"description":"Ignore the build state and regenerate everything.","type":["boolean","null"]}},"type":"object"}
        ,
        .run = build,
    },
    .{
        .name = "wiki_pages",
        .description = "wiki: a repo's pages in the workspace wiki: its entry page and the page of each README/docs file, as urls on the live wiki server (paths when it isn't running).",
        .schema =
        \\{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{"repo":{"description":"Repo name from the pullfile (e.g. `pull`, `fossify-ios/commons-ios`).","type":"string"}},"required":["repo"],"type":"object"}
        ,
        .run = pages,
    },
};

fn build(ctx: *const Ctx, a: Allocator, args: std.json.Value) !Result {
    const force = if (args == .object) if (args.object.get("force")) |f| f == .bool and f.bool else false else false;
    const sys: wiki.Sys = .{ .io = ctx.io, .arena = a };
    const lock = try wiki.BuildLock.acquire(sys, ctx.paths);
    defer lock.release(ctx.io);
    const result = wiki.build(sys, ctx.paths, force) catch |e| return .{ .err = try std.fmt.allocPrint(a, "wiki build failed: {t} (the wiki's stderr has the details)", .{e}) };
    return .{ .ok = try std.json.Stringify.valueAlloc(a, .{ .rendered = result.rendered, .total = result.total, .changed = result.changed, .dist = ctx.paths.dist }, .{ .whitespace = .indent_2 }) };
}

fn pages(ctx: *const Ctx, a: Allocator, args: std.json.Value) !Result {
    const repo = if (args == .object) if (args.object.get("repo")) |r| (if (r == .string) r.string else null) else null else null;
    const name = repo orelse return .{ .err = "repo is required" };
    const sys: wiki.Sys = .{ .io = ctx.io, .arena = a };
    const m = wiki.manifest(sys, ctx.paths) orelse return .{ .err = "the wiki hasn't been built yet (wiki_build)" };
    const entry = m.repos.map.get(name) orelse return .{ .err = try std.fmt.allocPrint(a, "the wiki has no pages for {s}", .{name}) };
    const base = if (try discovery.read(ctx.io, a, ctx.paths.root, .wiki)) |addr| try discovery.baseUrl(a, addr) else "";
    const Doc = struct { file: []const u8, url: []const u8 };
    const docs = try a.alloc(Doc, entry.docs.len);
    for (entry.docs, docs) |d, *out| out.* = .{ .file = d.file, .url = try std.mem.concat(a, u8, &.{ base, d.url }) };
    return .{ .ok = try std.json.Stringify.valueAlloc(a, .{
        .repo = name,
        .running = base.len > 0,
        .url = try std.mem.concat(a, u8, &.{ base, entry.url }),
        .docs = docs,
    }, .{ .whitespace = .indent_2 }) };
}

const Tool = struct {
    h: parley.ToolHandler = .{ .callFn = call },
    ctx: *const Ctx,
    def: Def,

    fn call(h: *parley.ToolHandler, c: *parley.Call, raw: ?[]const u8) parley.Call.Error!parley.ToolResult {
        const t: *Tool = @fieldParentPtr("h", h);
        const a = c.arena;
        const args = std.json.parseFromSliceLeaky(std.json.Value, a, raw orelse "{}", .{}) catch return .failure("arguments must be a JSON object");
        const r = t.def.run(t.ctx, a, args) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return .failure(@errorName(e)),
        };
        return switch (r) {
            .ok => |s| .ofText(s),
            .err => |s| .failure(s),
        };
    }
};

/// Serve MCP on stdin/stdout until the client closes stdin.
pub fn run(io: Io, gpa: Allocator, paths: wiki.Paths) !void {
    const ctx: Ctx = .{ .io = io, .gpa = gpa, .paths = paths };
    var server = try parley.Server.init(gpa, io, .{
        .info = .{ .name = "wiki", .version = serve.version },
        .instructions = "The pull workspace's wiki: build it (wiki_build) and find a repo's pages on the live server (wiki_pages).",
        .logging = false,
        .validator = null,
    });
    defer server.deinit(io);
    var handlers: [defs.len]Tool = undefined;
    for (&handlers, defs) |*t, d| {
        t.* = .{ .ctx = &ctx, .def = d };
        try server.addDynamicTool(io, .{ .name = d.name, .description = d.description, .input_schema = d.schema }, &t.h);
    }
    var in_buffer: [64 * 1024]u8 = undefined;
    var out_buffer: [64 * 1024]u8 = undefined;
    var stdin = Io.File.stdin().readerStreaming(io, &in_buffer);
    var stdout = Io.File.stdout().writerStreaming(io, &out_buffer);
    try parley.stdio.serve(io, gpa, &server, .fromFile(&stdin), .fromFile(&stdout), .{});
}

test "tool schemas are JSON" {
    for (defs) |d| {
        const v = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, d.schema, .{});
        v.deinit();
    }
}
