//! `wiki`: the pull workspace's wiki (theme docs/workspace-tools.md §6).
//!
//!   wiki build [--force]        regenerate what changed into .pull/wiki/dist
//!   wiki publish [--force]      build, then stage dist/ in ../jbisfun.github.io
//!   wiki clean                  remove .pull/wiki/{build,dist}
//!   wiki serve [--listen ADDR]  the live site with the forge features
//!   wiki mcp                    MCP server on stdio (wiki_build, wiki_pages)
//!
//! Every command takes `--root DIR` (else $PULL_ROOT, else the pullfile.plist
//! above the current dir).
const std = @import("std");
const clap = @import("clap");
const wiki = @import("wiki.zig");
const serve = @import("serve.zig");
const mcp = @import("mcp.zig");

// superhtml's tokenizer logs every character at debug level
pub const std_options: std.Options = .{ .log_scope_levels = &.{.{ .scope = .@"html/tokenizer", .level = .info }} };

const usage =
    \\Usage: wiki <COMMAND> [OPTIONS]
    \\
    \\The pull workspace's wiki: a static site from every repo's README, docs/
    \\and code reference, with <workspace>/wiki as its data (wiki.toml,
    \\templates/, pages/, assets/, locales/, translations/).
    \\
    \\Commands:
    \\  build     Regenerate what changed (by git object id) into .pull/wiki/dist
    \\  publish   Build, then mirror dist/ into ../jbisfun.github.io and stage it
    \\  clean     Remove .pull/wiki/build and .pull/wiki/dist
    \\  serve     Serve the site live, with the forge features (default 127.0.0.1:8090)
    \\  mcp       MCP server on stdio (wiki_build, wiki_pages)
    \\
    \\Options:
    \\  --root DIR     The workspace (default: $PULL_ROOT, else the pullfile.plist above)
    \\  --force        build/publish: ignore the build state and regenerate everything
    \\  --listen ADDR  serve: host:port to bind
    \\  --no-rebuild   serve: serve dist/ as it is, without rebuilding on requests
    \\  -h, --help     Show this help
    \\  -V, --version  Show the version
    \\
    \\Environment: WIKI_DIR (output, default <root>/.pull/wiki), WIKI_PUBLISH_DIR,
    \\WIKI_SKIP, WIKI_TITLE, WIKI_ESBUILD, WIKI_TRANSLATE=1 (call the translator),
    \\CPULL_ADDR / IDLCI_ADDR / RADAR_ADDR (where `serve` reaches the other tools).
    \\
;

const params = clap.parseParamsComptime(
    \\-h, --help
    \\-V, --version
    \\--root <str>
    \\--workspace <str>
    \\--force
    \\--listen <str>
    \\--no-rebuild
    \\<str>...
    \\
);

pub fn main(init: std.process.Init) !u8 {
    const gpa = std.heap.smp_allocator;
    var threaded = std.Io.Threaded.init(gpa, .{ .environ = init.minimal.environ });
    defer threaded.deinit();
    const io = threaded.io();

    var stderr_writer = std.Io.File.stderr().writerStreaming(io, &.{});
    const err = &stderr_writer.interface;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    const out = &stdout_writer.interface;

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var args = try init.minimal.args.iterateAllocator(arena);
    _ = args.skip();
    var diag: clap.Diagnostic = .{};
    var res = clap.parseEx(clap.Help, &params, .{ .str = clap.parsers.string }, &args, .{ .diagnostic = &diag, .allocator = arena }) catch |e| {
        try diag.report(err, e);
        try err.writeAll(usage);
        return 2;
    };
    defer res.deinit();
    if (res.args.help != 0) {
        try out.writeAll(usage);
        return 0;
    }
    if (res.args.version != 0) {
        try out.print("wiki {s}\n", .{serve.version});
        return 0;
    }
    if (res.positionals[0].len != 1) {
        if (res.positionals[0].len > 1) try err.print("error: unexpected argument '{s}'\n\n", .{res.positionals[0][1]});
        try err.writeAll(usage);
        return 2;
    }
    const command = res.positionals[0][0];
    const Command = enum { build, publish, clean, serve, mcp };
    const cmd = std.meta.stringToEnum(Command, command) orelse {
        try err.print("error: unrecognized command '{s}'\n\n{s}", .{ command, usage });
        return 2;
    };

    const sys: wiki.Sys = .{ .io = io, .arena = arena };
    const cwd = try std.process.currentPathAlloc(io, arena);
    const paths = wiki.findPaths(sys, cwd, res.args.root orelse res.args.workspace) catch |e| {
        try err.print("wiki: no workspace with a wiki/wiki.toml at or above {s} ({t}); pass --root DIR\n", .{ cwd, e });
        return 1;
    };

    switch (cmd) {
        .clean => {
            try sys.removeTree(paths.build);
            try sys.removeTree(paths.dist);
        },
        .build, .publish => {
            const lock = try wiki.BuildLock.acquire(sys, paths);
            defer lock.release(io);
            _ = wiki.build(sys, paths, res.args.force != 0) catch |e| {
                try err.print("wiki: build failed: {t}\n", .{e});
                return 1;
            };
            if (cmd == .publish) wiki.publish(sys, paths) catch return 1;
        },
        .serve => serve.run(io, gpa, paths, .{
            .listen = res.args.listen orelse "127.0.0.1:8090",
            .rebuild = res.args.@"no-rebuild" == 0,
        }) catch |e| {
            try err.print("wiki: serve: {t}\n", .{e});
            return 1;
        },
        .mcp => mcp.run(io, gpa, paths) catch |e| {
            try err.print("wiki: mcp: {t}\n", .{e});
            return 1;
        },
    }
    return 0;
}

test {
    _ = wiki;
    _ = serve;
    _ = mcp;
    _ = @import("forge.zig");
}
