//! Code reference per repo, by each language's own tool, into
//! `<build>/api/<repo>/<tool>/`:
//!   rust: `cargo doc --no-deps` (rustdoc)   lua: LDoc   js: JSDoc
//! A tool that is missing or fails only warns: the site still builds. A
//! reference is rebuilt only when the repo's source id (state.zig) or its
//! wiki.toml settings changed.
const std = @import("std");
const config = @import("config.zig");
const state_mod = @import("state.zig");
const Repo = @import("collect.zig").Repo;
const sys_mod = @import("sys.zig");
const Sys = sys_mod.Sys;
const warn = sys_mod.warn;

pub const Api = state_mod.Api;

pub const Paths = struct {
    wiki: []const u8,
    build: []const u8,
};

/// Repo name -> its code references.
pub fn generate(sys: Sys, paths: Paths, repos: []const Repo, state: *state_mod.State) !std.StringHashMapUnmanaged([]const Api) {
    var apis: std.StringHashMapUnmanaged([]const Api) = .empty;
    var kept: std.json.ArrayHashMap(state_mod.ApiState) = .{};
    for (repos) |*repo| {
        const source = state_mod.sourceId(sys, repo.path) catch |err| {
            warn("{s}: {t}", .{ repo.name, err });
            continue;
        };
        var entries: std.ArrayList(Api) = .empty;
        const tools = [_]struct { []const u8, config.Tool }{ .{ "rust", repo.config.rust }, .{ "lua", repo.config.lua }, .{ "js", repo.config.js } };
        for (tools) |t| {
            const tool, const settings = t;
            if (!settings.enabled) continue;
            const id = try std.fmt.allocPrint(sys.arena, "{s}/{s}", .{ repo.name, tool });
            var fp: std.Io.Writer.Allocating = .init(sys.arena);
            try std.json.Stringify.value(.{ .packages = settings.packages, .files = settings.files }, .{}, &fp.writer);
            const key = state_mod.key(sys.arena, &.{ source, tool, fp.written() });
            const dest = sys.join(&.{ paths.build, "api", repo.name, tool });
            const built: []const Api = blk: {
                if (state.apidoc.map.get(id)) |previous| {
                    if (std.mem.eql(u8, previous.key, key) and (previous.entries.len == 0 or sys.isDir(dest))) break :blk previous.entries;
                }
                const job: Job = .{ .sys = sys, .paths = paths, .repo = repo, .settings = settings, .dest = dest };
                break :blk if (std.mem.eql(u8, tool, "rust")) job.rust() else if (std.mem.eql(u8, tool, "lua")) job.lua() else job.js();
            };
            try entries.appendSlice(sys.arena, built);
            try kept.map.put(sys.arena, id, .{ .key = key, .entries = built });
        }
        if (entries.items.len > 0) try apis.put(sys.arena, repo.name, entries.items);
    }
    state.apidoc = kept;
    return apis;
}

const Job = struct {
    sys: Sys,
    paths: Paths,
    repo: *const Repo,
    settings: config.Tool,
    dest: []const u8,

    fn warnRepo(j: Job, comptime fmt: []const u8, args: anytype) void {
        std.debug.print("wiki: {s}: " ++ fmt ++ "\n", .{j.repo.name} ++ args);
    }

    fn entry(j: Job, tool: []const u8, title: []const u8, path: []const u8) Api {
        _ = j;
        return .{ .tool = tool, .title = title, .path = path };
    }

    /// Run a doc tool; on failure warn with its output and return false.
    fn run(j: Job, argv: []const []const u8, what: []const u8) bool {
        const out = j.sys.run(argv, j.repo.path);
        if (out.ok) return true;
        if (!out.spawned) {
            j.warnRepo("{s} not available ({s}), skipping", .{ what, out.stderr });
        } else {
            j.warnRepo("{s} failed", .{what});
            std.debug.print("{s}{s}", .{ out.stdout, out.stderr });
        }
        return false;
    }

    fn resetDest(j: Job) !void {
        try j.sys.removeTree(j.dest);
        try j.sys.mkdirs(j.dest);
    }

    /// Tracked files matching the `files` pathspecs, or the defaults.
    fn trackedFiles(j: Job, defaults: []const []const u8) []const []const u8 {
        const specs = if (j.settings.files.len == 0) defaults else j.settings.files;
        var argv: std.ArrayList([]const u8) = .empty;
        argv.appendSlice(j.sys.arena, &.{ "git", "ls-files", "-z", "--" }) catch return &.{};
        argv.appendSlice(j.sys.arena, specs) catch return &.{};
        const out = j.sys.run(argv.items, j.repo.path);
        if (!out.ok) return &.{};
        var files: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, out.stdout, 0);
        while (it.next()) |f| if (f.len > 0) files.append(j.sys.arena, f) catch {};
        return files.items;
    }

    fn anyFileContains(j: Job, files: []const []const u8, comptime pred: fn ([]const u8) bool) bool {
        for (files) |f| {
            const text = j.sys.readFileOr(j.sys.join(&.{ j.repo.path, f })) orelse continue;
            if (pred(text)) return true;
        }
        return false;
    }

    fn rust(j: Job) []const Api {
        if (!j.sys.isFile(j.sys.join(&.{ j.repo.path, "Cargo.toml" }))) return &.{};
        return j.tryRust() catch |err| {
            j.warnRepo("rustdoc: {t}", .{err});
            return &.{};
        };
    }

    fn tryRust(j: Job) ![]const Api {
        // the repo's own target dir, so dependency metadata is shared with its builds
        const meta = j.sys.run(&.{ "cargo", "metadata", "--format-version", "1", "--no-deps" }, j.repo.path);
        if (!meta.spawned) {
            j.warnRepo("cargo not available, skipping", .{});
            return &.{};
        }
        const Meta = struct { target_directory: []const u8 = "target" };
        const parsed = std.json.parseFromSliceLeaky(Meta, j.sys.arena, meta.stdout, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch Meta{};
        const target = if (std.fs.path.isAbsolute(parsed.target_directory)) parsed.target_directory else j.sys.join(&.{ j.repo.path, parsed.target_directory });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(j.sys.arena, &.{ "cargo", "doc", "--no-deps", "--quiet" });
        for (j.settings.packages) |p| try argv.appendSlice(j.sys.arena, &.{ "-p", p });
        if (!j.run(argv.items, "cargo doc")) return &.{};
        try j.resetDest();
        try j.sys.copyDir(j.sys.join(&.{ target, "doc" }), j.dest);
        const crates_js = try j.sys.readFile(j.sys.join(&.{ j.dest, "crates.js" }));
        // `window.ALL_CRATES = ["a","b"];` on a line of its own
        var names: []const []const u8 = &.{};
        var lines = std.mem.splitScalar(u8, crates_js, '\n');
        while (lines.next()) |line| {
            const prefix = "window.ALL_CRATES = ";
            if (std.mem.startsWith(u8, line, prefix) and std.mem.endsWith(u8, line, ";")) {
                names = std.json.parseFromSliceLeaky([]const []const u8, j.sys.arena, line[prefix.len .. line.len - 1], .{}) catch &.{};
            }
        }
        var out: std.ArrayList(Api) = .empty;
        for (names) |name| try out.append(j.sys.arena, j.entry("rust", name, try std.fmt.allocPrint(j.sys.arena, "rust/{s}/index.html", .{name})));
        return out.items;
    }

    fn hasLuaDoc(text: []const u8) bool {
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t\r"), "---")) return true;
        return false;
    }

    fn hasJsDoc(text: []const u8) bool {
        return std.mem.indexOf(u8, text, "/**") != null;
    }

    fn lua(j: Job) []const Api {
        // *.x.lua are preprocessed ycode hook scripts, not plain Lua modules
        const defaulted = j.settings.files.len == 0;
        var files: std.ArrayList([]const u8) = .empty;
        for (j.trackedFiles(&.{"*.lua"})) |f| {
            if (defaulted and std.mem.endsWith(u8, f, ".x.lua")) continue;
            files.append(j.sys.arena, f) catch {};
        }
        // LDoc only documents `---` comments; without any there is nothing to show
        if (files.items.len == 0 or !j.anyFileContains(files.items, hasLuaDoc)) return &.{};
        return j.tryLua(files.items) catch |err| {
            j.warnRepo("ldoc: {t}", .{err});
            return &.{};
        };
    }

    fn jsonString(j: Job, s: []const u8) []const u8 {
        var out: std.Io.Writer.Allocating = .init(j.sys.arena);
        std.json.Stringify.value(s, .{}, &out.writer) catch {};
        return out.written();
    }

    fn tryLua(j: Job, files: []const []const u8) ![]const Api {
        try j.resetDest();
        const name = j.repo.name;
        const conf = j.sys.join(&.{ std.fs.path.dirname(j.dest).?, "config.ld" });
        // JSON strings double as Lua string literals. "backtick": Debian ships
        // LDoc without its markdown module, so only `code` spans are formatted.
        var text: std.ArrayList(u8) = .empty;
        try text.print(j.sys.arena, "project = {s}\ntitle = {s}\ndir = {s}\nformat = \"backtick\"\nfile = {{\n", .{
            j.jsonString(name),
            j.jsonString(try std.fmt.allocPrint(j.sys.arena, "{s} Lua API", .{name})),
            j.jsonString(j.dest),
        });
        for (files) |f| try text.print(j.sys.arena, "  {s},\n", .{j.jsonString(j.sys.join(&.{ j.repo.path, f }))});
        try text.appendSlice(j.sys.arena, "}\n");
        try j.sys.writeFile(conf, text.items);
        const ok = j.run(&.{ "ldoc", "--testing", "-c", conf, "." }, "ldoc");
        j.sys.removeFile(conf);
        if (!ok) return &.{};
        const out = try j.sys.arena.alloc(Api, 1);
        out[0] = j.entry("lua", name, "lua/index.html");
        return out;
    }

    fn js(j: Job) []const Api {
        if (!j.sys.isFile(j.sys.join(&.{ j.repo.path, "package.json" }))) return &.{};
        const files = j.trackedFiles(&.{ "*.js", "*.mjs" });
        if (files.len == 0 or !j.anyFileContains(files, hasJsDoc)) return &.{};
        const jsdoc = j.sys.join(&.{ j.paths.wiki, "node_modules/.bin/jsdoc" });
        if (!j.sys.isFile(jsdoc)) {
            j.warnRepo("jsdoc not installed (pnpm install in the wiki repo), skipping", .{});
            return &.{};
        }
        j.resetDest() catch |err| {
            j.warnRepo("{t}", .{err});
            return &.{};
        };
        // jsdoc.json drops the generation date, so unchanged code gives unchanged pages
        var argv: std.ArrayList([]const u8) = .empty;
        argv.appendSlice(j.sys.arena, &.{ jsdoc, "-c", j.sys.join(&.{ j.paths.wiki, "jsdoc.json" }), "-d", j.dest }) catch return &.{};
        argv.appendSlice(j.sys.arena, files) catch return &.{};
        if (!j.run(argv.items, "jsdoc")) return &.{};
        const out = j.sys.arena.alloc(Api, 1) catch return &.{};
        out[0] = j.entry("js", j.repo.name, "js/index.html");
        return out;
    }
};
