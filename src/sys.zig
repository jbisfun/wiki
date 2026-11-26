//! File and process helpers for one wiki build (absolute paths throughout).
const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

pub const Sys = struct {
    io: std.Io,
    arena: Allocator,
    /// Overrides of the process environment (tests, the server), else libc's.
    env: ?*const std.process.Environ.Map = null,

    pub fn getenv(s: Sys, name: []const u8) ?[]const u8 {
        if (s.env) |m| return m.get(name);
        const z = s.arena.dupeSentinel(u8, name, 0) catch return null;
        const v = std.c.getenv(z) orelse return null;
        return std.mem.span(v);
    }

    pub fn join(s: Sys, parts: []const []const u8) []const u8 {
        return Dir.path.join(s.arena, parts) catch @panic("OOM");
    }

    pub fn readFile(s: Sys, path: []const u8) ![]u8 {
        return Dir.cwd().readFileAlloc(s.io, path, s.arena, .limited(256 << 20));
    }

    pub fn readFileOr(s: Sys, path: []const u8) ?[]u8 {
        return s.readFile(path) catch null;
    }

    pub fn writeFile(s: Sys, path: []const u8, data: []const u8) !void {
        if (Dir.path.dirname(path)) |dir| try Dir.cwd().createDirPath(s.io, dir);
        try Dir.cwd().writeFile(s.io, .{ .sub_path = path, .data = data });
    }

    pub fn kind(s: Sys, path: []const u8) ?std.Io.File.Kind {
        const st = Dir.cwd().statFile(s.io, path, .{}) catch return null;
        return st.kind;
    }

    pub fn isFile(s: Sys, path: []const u8) bool {
        return s.kind(path) == .file;
    }

    pub fn isDir(s: Sys, path: []const u8) bool {
        return s.kind(path) == .directory;
    }

    pub fn exists(s: Sys, path: []const u8) bool {
        return s.kind(path) != null;
    }

    pub fn mkdirs(s: Sys, path: []const u8) !void {
        try Dir.cwd().createDirPath(s.io, path);
    }

    pub fn removeTree(s: Sys, path: []const u8) !void {
        try Dir.cwd().deleteTree(s.io, path);
    }

    pub fn removeFile(s: Sys, path: []const u8) void {
        Dir.cwd().deleteFile(s.io, path) catch {};
    }

    pub fn copyFile(s: Sys, from: []const u8, to: []const u8) !void {
        if (Dir.path.dirname(to)) |dir| try Dir.cwd().createDirPath(s.io, dir);
        try Dir.cwd().copyFile(from, Dir.cwd(), to, s.io, .{});
    }

    /// Files under `dir` (recursively, following no symlinked dirs), as
    /// sorted paths relative to it. Empty when it doesn't exist.
    pub fn walkFiles(s: Sys, dir: []const u8) ![]const []const u8 {
        var files: std.ArrayList([]const u8) = .empty;
        var d = Dir.cwd().openDir(s.io, dir, .{ .iterate = true }) catch return files.items;
        defer d.close(s.io);
        var walker = try d.walk(s.arena);
        defer walker.deinit();
        while (try walker.next(s.io)) |entry| {
            if (entry.kind == .file or entry.kind == .sym_link) {
                if (entry.kind == .sym_link and s.kind(s.join(&.{ dir, entry.path })) != .file) continue;
                try files.append(s.arena, try s.arena.dupe(u8, entry.path));
            }
        }
        std.mem.sort([]const u8, files.items, {}, lessThan);
        return files.items;
    }

    /// Copy the files under `from` into `to`, keeping the layout.
    pub fn copyDir(s: Sys, from: []const u8, to: []const u8) !void {
        for (try s.walkFiles(from)) |rel| try s.copyFile(s.join(&.{ from, rel }), s.join(&.{ to, rel }));
    }

    pub const Output = struct {
        ok: bool,
        stdout: []const u8,
        stderr: []const u8,
        spawned: bool = true,
    };

    /// Run to completion; a program that can't be started gives `spawned = false`.
    pub fn run(s: Sys, argv: []const []const u8, cwd: ?[]const u8) Output {
        const result = std.process.run(s.arena, s.io, .{
            .argv = argv,
            .cwd = if (cwd) |p| .{ .path = p } else .inherit,
            .environ_map = s.env,
        }) catch |err| return .{ .ok = false, .stdout = "", .stderr = @errorName(err), .spawned = false };
        const ok = switch (result.term) {
            .exited => |code| code == 0,
            else => false,
        };
        return .{ .ok = ok, .stdout = result.stdout, .stderr = result.stderr };
    }
};

pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("wiki: " ++ fmt ++ "\n", args);
}
