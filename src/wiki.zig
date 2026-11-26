//! The generator: one static site from every repo in a pull workspace (the
//! Zig port of the Rust `wiki` tool, which lived in cpull's src/wiki before
//! the workspace tools split).
//!
//! Each repo's README is its entry page, its `docs/` folder becomes pages, and
//! rustdoc / LDoc / JSDoc produce its code reference. Git object ids decide
//! what has to be regenerated (state.zig). The wiki repo (`<root>/wiki`) is
//! the site's data: wiki.toml, templates/, pages/, assets/, locales/ and the
//! translations/ cache. Output and state live under `<root>/.pull/wiki/`
//! (`dist/`, `build/`); `wiki serve` serves `dist/` live (serve.zig).
const std = @import("std");
const sys_mod = @import("sys.zig");
const config = @import("config.zig");
const collect = @import("collect.zig");
const apidoc = @import("apidoc.zig");
const bundle = @import("bundle.zig");
const render = @import("render.zig");
const state_mod = @import("state.zig");

pub const Sys = sys_mod.Sys;
pub const Paths = render.Paths;
pub const Result = render.Result;
pub const Manifest = render.Manifest;

/// The workspace root: `explicit` (--root), else `$PULL_ROOT`, else the
/// nearest ancestor of `cwd` holding `pullfile.plist`, else the parent of
/// the wiki repo found above `cwd`.
pub fn findRoot(sys: Sys, cwd: []const u8, explicit: ?[]const u8) ?[]const u8 {
    if (explicit) |w| return std.Io.Dir.path.resolve(sys.arena, &.{ cwd, w }) catch null;
    if (sys.getenv("PULL_ROOT")) |r| if (r.len > 0) return r;
    var dir: ?[]const u8 = cwd;
    while (dir) |d| : (dir = std.Io.Dir.path.dirname(d)) {
        if (sys.isFile(sys.join(&.{ d, "pullfile.plist" }))) return d;
    }
    dir = cwd;
    while (dir) |d| : (dir = std.Io.Dir.path.dirname(d)) {
        if (sys.isFile(sys.join(&.{ d, "wiki.toml" }))) return std.Io.Dir.path.dirname(d);
    }
    return null;
}

/// The wiki repo, the workspace root and the output dirs.
pub fn findPaths(sys: Sys, cwd: []const u8, explicit_root: ?[]const u8) !Paths {
    const r = findRoot(sys, cwd, explicit_root) orelse return error.NoWorkspace;
    var wiki: ?[]const u8 = null;
    if (sys.isFile(sys.join(&.{ r, "wiki", "wiki.toml" }))) {
        wiki = sys.join(&.{ r, "wiki" });
    } else {
        // a wiki.toml above the current dir (a wiki checkout of its own)
        var dir: ?[]const u8 = cwd;
        while (dir) |d| : (dir = std.Io.Dir.path.dirname(d)) {
            if (sys.isFile(sys.join(&.{ d, "wiki.toml" }))) {
                wiki = d;
                break;
            }
        }
    }
    const w = wiki orelse return error.NoWikiToml;
    const out = outDir(sys, r);
    return .{ .wiki = w, .root = r, .build = sys.join(&.{ out, "build" }), .dist = sys.join(&.{ out, "dist" }) };
}

/// `$WIKI_DIR`, else `<root>/.pull/wiki` (`$CPULL_WIKI_DIR`, cpull's name for
/// it, still works).
pub fn outDir(sys: Sys, root: []const u8) []const u8 {
    if (sys.getenv("WIKI_DIR")) |d| if (d.len > 0) return d;
    if (sys.getenv("CPULL_WIKI_DIR")) |d| if (d.len > 0) return d;
    return sys.join(&.{ root, ".pull", "wiki" });
}

/// Before the split, cpull built the site into `<root>/.pull/cpull/wiki`.
/// The first build here starts from a copy of that state, so the code
/// references (cargo doc, the slow part) aren't regenerated. The old
/// directory stays for the cpull build still serving /wiki/.
fn adoptCpullOutput(sys: Sys, paths: Paths) void {
    if (sys.isFile(sys.join(&.{ paths.build, "state.json" }))) return;
    const old = sys.join(&.{ paths.root, ".pull", "cpull", "wiki" });
    if (!sys.isFile(sys.join(&.{ old, "build", "state.json" }))) return;
    const out = std.Io.Dir.path.dirname(paths.build) orelse return;
    sys.mkdirs(out) catch return;
    inline for (.{ "build", "dist" }) |sub| {
        if (sys.isDir(sys.join(&.{ old, sub })) and !sys.exists(sys.join(&.{ out, sub }))) {
            const copied = sys.run(&.{ "cp", "-a", sys.join(&.{ old, sub }), sys.join(&.{ out, sub }) }, null);
            if (!copied.ok) std.debug.print("wiki: copying {s}/{s}: {s}\n", .{ old, sub, copied.stderr });
        }
    }
    std.debug.print("wiki: started from cpull's build in {s}\n", .{old});
}

/// Holds `<out>/build.lock`, so a CLI or MCP build and the live server's
/// rebuilds never write the same dist/ at once.
pub const BuildLock = struct {
    file: std.Io.File,

    fn open(sys: Sys, paths: Paths) !std.Io.File {
        const out = std.Io.Dir.path.dirname(paths.build) orelse paths.build;
        try sys.mkdirs(out);
        return std.Io.Dir.cwd().createFile(sys.io, sys.join(&.{ out, "build.lock" }), .{ .truncate = false });
    }

    pub fn acquire(sys: Sys, paths: Paths) !BuildLock {
        const file = try open(sys, paths);
        errdefer file.close(sys.io);
        try file.lock(sys.io, .exclusive);
        return .{ .file = file };
    }

    /// null while another process builds.
    pub fn tryAcquire(sys: Sys, paths: Paths) !?BuildLock {
        const file = try open(sys, paths);
        if (!(try file.tryLock(sys.io, .exclusive))) {
            file.close(sys.io);
            return null;
        }
        return .{ .file = file };
    }

    pub fn release(l: BuildLock, io: std.Io) void {
        l.file.unlock(io);
        l.file.close(io);
    }
};

/// Build the site into `paths.dist`, regenerating only what changed. The
/// caller holds the BuildLock.
pub fn build(sys: Sys, paths: Paths, force: bool) !Result {
    adoptCpullOutput(sys, paths);
    const state_path = sys.join(&.{ paths.build, "state.json" });
    var state: state_mod.State = if (force) .{} else state_mod.State.load(sys, state_path);
    const toml_path = sys.join(&.{ paths.wiki, "wiki.toml" });
    const cfg = config.parse(sys.arena, try sys.readFile(toml_path)) catch |err| {
        std.debug.print("wiki: parsing {s}: {t}\n", .{ toml_path, err });
        return err;
    };
    const repos = try collect.collect(sys, paths.root, &cfg);
    const apis = try apidoc.generate(sys, .{ .wiki = paths.wiki, .build = paths.build }, repos, &state);
    try bundle.bundle(sys, paths.wiki, paths.dist, &state);
    const result = try render.render(sys, paths, &cfg, repos, &apis, &state, bundle.selfId(sys));
    try state.save(sys, state_path);
    return result;
}

/// Mirror dist/ into the GitHub Pages repo and stage it, so the pull
/// precommit hook lands the site in the same `pull commit`.
pub fn publish(sys: Sys, paths: Paths) !void {
    const target = sys.getenv("WIKI_PUBLISH_DIR") orelse sys.join(&.{ paths.root, "jbisfun.github.io" });
    const from = try std.fmt.allocPrint(sys.arena, "{s}/", .{paths.dist});
    const to = try std.fmt.allocPrint(sys.arena, "{s}/", .{target});
    const rsync = sys.run(&.{ "rsync", "-a", "--delete", "--exclude", ".git", "--exclude", "CNAME", "--exclude", "README.md", from, to }, null);
    if (!rsync.ok) {
        std.debug.print("wiki: rsync into {s} failed: {s}\n", .{ target, rsync.stderr });
        return error.PublishFailed;
    }
    try sys.writeFile(sys.join(&.{ target, ".nojekyll" }), "");
    const add = sys.run(&.{ "git", "add", "-A", "." }, target);
    if (!add.ok) {
        std.debug.print("wiki: git add in {s} failed: {s}\n", .{ target, add.stderr });
        return error.PublishFailed;
    }
    const staged = sys.run(&.{ "git", "diff", "--cached", "--name-only", "-z" }, target);
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, staged.stdout, 0);
    while (it.next()) |name| {
        if (name.len > 0) count += 1;
    }
    std.debug.print("wiki: published to {s} ({d} files staged)\n", .{ target, count });
}

/// The page list render.zig writes to `build/pages.json` on every build: a
/// repo's entry page and every page from its README and docs/, as paths on
/// the server.
pub fn manifest(sys: Sys, paths: Paths) ?Manifest {
    const bytes = sys.readFileOr(sys.join(&.{ paths.build, "pages.json" })) orelse return null;
    return std.json.parseFromSliceLeaky(Manifest, sys.arena, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch null;
}

test {
    _ = @import("markdown.zig");
    _ = @import("html.zig");
    _ = @import("fluent.zig");
    _ = @import("state.zig");
    _ = @import("config.zig");
    _ = @import("collect.zig");
    _ = @import("translate.zig");
    _ = @import("render.zig");
    _ = @import("apidoc.zig");
    _ = @import("bundle.zig");
}

test "workspace root" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const io = std.testing.io;
    const root = try tmp.dir.realPathFileAlloc(io, ".", arena_state.allocator());
    var env: std.process.Environ.Map = .init(arena_state.allocator());
    const sys: Sys = .{ .io = io, .arena = arena_state.allocator(), .env = &env };
    try sys.writeFile(sys.join(&.{ root, "pullfile.plist" }), "");
    try sys.writeFile(sys.join(&.{ root, "wiki", "wiki.toml" }), "");
    try sys.mkdirs(sys.join(&.{ root, "a", "b" }));
    try std.testing.expectEqualStrings(root, findRoot(sys, sys.join(&.{ root, "a", "b" }), null).?);
    const paths = try findPaths(sys, sys.join(&.{ root, "a" }), null);
    try std.testing.expectEqualStrings(sys.join(&.{ root, "wiki" }), paths.wiki);
    try std.testing.expectEqualStrings(sys.join(&.{ root, ".pull", "wiki", "dist" }), paths.dist);
    try env.put("PULL_ROOT", "/elsewhere");
    try std.testing.expectEqualStrings("/elsewhere", findRoot(sys, root, null).?);
    try std.testing.expectEqualStrings(root, findRoot(sys, "/", root).?);
}
