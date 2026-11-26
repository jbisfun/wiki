//! What needs regenerating, decided with git object ids.
//!
//! Every input is identified the way git identifies it: files by their blob id
//! (`git hash-object`), a repo's sources by its HEAD tree id plus a hash of
//! its uncommitted changes (the diff against HEAD and the untracked files'
//! blob ids). A unit of work (a repo's pages, a code reference, the asset
//! bundle) gets a key hashed from the ids of its inputs; `state.json` keeps
//! the key each unit was last built with, and a unit whose key is unchanged
//! is left alone.
const std = @import("std");
const Sys = @import("sys.zig").Sys;
const Allocator = std.mem.Allocator;

pub const Api = struct {
    tool: []const u8,
    title: []const u8,
    path: []const u8,
};

pub const ApiState = struct {
    key: []const u8,
    entries: []const Api,
};

pub const State = struct {
    /// Key of everything every page depends on (templates, nav, the binary).
    global: []const u8 = "",
    assets: []const u8 = "",
    /// Repo name (with language prefix) -> key of its rendered pages.
    repos: std.json.ArrayHashMap([]const u8) = .{},
    /// "<repo>/<tool>" -> code reference built with that key.
    apidoc: std.json.ArrayHashMap(ApiState) = .{},

    pub fn load(sys: Sys, path: []const u8) State {
        const bytes = sys.readFileOr(path) orelse return .{};
        return std.json.parseFromSliceLeaky(State, sys.arena, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch .{};
    }

    pub fn save(state: *const State, sys: Sys, path: []const u8) !void {
        var out: std.Io.Writer.Allocating = .init(sys.arena);
        try std.json.Stringify.value(state, .{ .whitespace = .indent_2 }, &out.writer);
        try sys.writeFile(path, out.written());
    }
};

/// Blob id of bytes (`git hash-object --stdin`), as hex.
pub fn blobId(arena: Allocator, bytes: []const u8) []const u8 {
    var h = std.crypto.hash.Sha1.init(.{});
    var header_buf: [32]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "blob {d}\x00", .{bytes.len}) catch unreachable;
    h.update(header);
    h.update(bytes);
    var digest: [20]u8 = undefined;
    h.final(&digest);
    return std.fmt.allocPrint(arena, "{x}", .{&digest}) catch @panic("OOM");
}

/// Blob id of several parts, each followed by a NUL.
pub fn key(arena: Allocator, parts: []const []const u8) []const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    for (parts) |part| {
        bytes.appendSlice(arena, part) catch @panic("OOM");
        bytes.append(arena, 0) catch @panic("OOM");
    }
    return blobId(arena, bytes.items);
}

/// Blob id of a file (`git hash-object FILE`); empty when it can't be read.
pub fn fileId(sys: Sys, path: []const u8) []const u8 {
    const bytes = sys.readFileOr(path) orelse return "";
    return blobId(sys.arena, bytes);
}

/// Blob ids of every file under `dir`, as "relative path\0id" parts.
pub fn dirIds(sys: Sys, dir: []const u8) ![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    for (try sys.walkFiles(dir)) |rel| {
        try parts.append(sys.arena, try std.fmt.allocPrint(sys.arena, "{s}\x00{s}", .{ rel, fileId(sys, sys.join(&.{ dir, rel })) }));
    }
    return parts.items;
}

/// Id of a repo's current sources: HEAD's tree id plus a hash of everything
/// uncommitted (staged, unstaged and untracked).
pub fn sourceId(sys: Sys, repo: []const u8) ![]const u8 {
    const tree = sys.run(&.{ "git", "rev-parse", "-q", "--verify", "HEAD^{tree}" }, repo);
    if (!tree.spawned) return error.GitNotFound;
    const tree_id = std.mem.trim(u8, tree.stdout, " \n");
    const status = sys.run(&.{ "git", "status", "--porcelain", "-z", "--untracked-files=all" }, repo);
    if (!status.ok) return error.NotAGitRepo;
    if (status.stdout.len == 0) return key(sys.arena, &.{ tree_id, "" });
    var parts: std.ArrayList([]const u8) = .empty;
    const diff = sys.run(&.{ "git", "diff", "HEAD", "--no-color", "--no-ext-diff", "--binary", "--full-index" }, repo);
    try parts.append(sys.arena, blobId(sys.arena, diff.stdout));
    const untracked = sys.run(&.{ "git", "ls-files", "-z", "--others", "--exclude-standard" }, repo);
    var it = std.mem.splitScalar(u8, untracked.stdout, 0);
    while (it.next()) |path| {
        if (path.len == 0) continue;
        try parts.append(sys.arena, try std.fmt.allocPrint(sys.arena, "{s}\x00{s}", .{ path, fileId(sys, sys.join(&.{ repo, path })) }));
    }
    return key(sys.arena, &.{ tree_id, key(sys.arena, parts.items) });
}

test "blob ids" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // `printf hello | git hash-object --stdin`
    try std.testing.expectEqualStrings("b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0", blobId(arena_state.allocator(), "hello"));
}
