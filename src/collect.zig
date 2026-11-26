//! The repos to publish: `pull status --json` merged with wiki.toml.
const std = @import("std");
const config = @import("config.zig");
const Sys = @import("sys.zig").Sys;

pub const Repo = struct {
    name: []const u8,
    path: []const u8,
    branch: []const u8,
    head: []const u8,
    /// https://github.com/owner/repo, from the origin remote.
    web: ?[]const u8,
    /// File name of the README in the repo root.
    readme: ?[]const u8,
    config: config.RepoConfig,
};

const Status = struct {
    repos: []const struct {
        name: []const u8,
        path: []const u8,
        cloned: bool = false,
        branch: ?[]const u8 = null,
        head: ?[]const u8 = null,
    },
};

/// Every cloned repo that isn't skipped (wiki.toml `skip` or `$WIKI_SKIP`),
/// sorted by name (case-insensitively).
pub fn collect(sys: Sys, root: []const u8, cfg: *const config.Config) ![]Repo {
    const skipped = sys.getenv("WIKI_SKIP") orelse "";
    const pull = sys.getenv("WIKI_PULL") orelse "pull";
    const out = sys.run(&.{ pull, "status", "--json" }, root);
    if (!out.ok) {
        std.debug.print("wiki: pull status --json: {s}\n", .{out.stderr});
        return error.PullStatusFailed;
    }
    const status = try std.json.parseFromSliceLeaky(Status, sys.arena, out.stdout, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });

    var repos: std.ArrayList(Repo) = .empty;
    for (status.repos) |r| {
        const cfg_repo = cfg.repo(r.name);
        if (!r.cloned or cfg_repo.skip or listed(skipped, r.name)) continue;
        try repos.append(sys.arena, .{
            .name = r.name,
            .path = r.path,
            .branch = r.branch orelse "main",
            .head = r.head orelse "",
            .web = githubUrl(sys, r.path),
            .readme = try findReadme(sys, r.path),
            .config = cfg_repo,
        });
    }
    std.mem.sort(Repo, repos.items, {}, struct {
        fn lt(_: void, a: Repo, b: Repo) bool {
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.lt);
    return repos.items;
}

fn listed(list: []const u8, name: []const u8) bool {
    var it = std.mem.splitScalar(u8, list, ',');
    while (it.next()) |item| if (item.len > 0 and std.mem.eql(u8, item, name)) return true;
    return false;
}

fn findReadme(sys: Sys, path: []const u8) !?[]const u8 {
    var dir = std.Io.Dir.cwd().openDir(sys.io, path, .{ .iterate = true }) catch return null;
    defer dir.close(sys.io);
    var it = dir.iterate();
    while (try it.next(sys.io)) |entry| {
        if (entry.kind == .file and std.ascii.eqlIgnoreCase(entry.name, "readme.md")) return try sys.arena.dupe(u8, entry.name);
    }
    return null;
}

/// `github.com[:/]owner/repo(.git)?/?$` of the origin remote, as a web URL.
fn githubUrl(sys: Sys, path: []const u8) ?[]const u8 {
    const out = sys.run(&.{ "git", "config", "--get", "remote.origin.url" }, path);
    if (!out.ok) return null;
    return githubWeb(sys.arena, std.mem.trim(u8, out.stdout, " \r\n"));
}

pub fn githubWeb(arena: std.mem.Allocator, url: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, url, "github.com") orelse return null;
    var rest = url[at + "github.com".len ..];
    if (rest.len == 0 or (rest[0] != ':' and rest[0] != '/')) return null;
    rest = std.mem.trimEnd(u8, rest[1..], "/");
    if (std.mem.endsWith(u8, rest, ".git")) rest = rest[0 .. rest.len - 4];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    if (slash == 0 or slash + 1 >= rest.len or std.mem.indexOfScalar(u8, rest[slash + 1 ..], '/') != null) return null;
    return std.fmt.allocPrint(arena, "https://github.com/{s}", .{rest}) catch null;
}

test "github urls" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("https://github.com/jbisfun/pull", githubWeb(a, "https://github.com/jbisfun/pull").?);
    try std.testing.expectEqualStrings("https://github.com/jbisfun/pull", githubWeb(a, "git@github.com:jbisfun/pull.git").?);
    try std.testing.expect(githubWeb(a, "https://example.com/x/y") == null);
}
