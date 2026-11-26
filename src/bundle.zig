//! Client assets into <dist>/_assets: esbuild bundles and minifies
//! assets/main.js with its npm imports (bootstrap, clipboard) and
//! assets/style.css with its `@import`s (Bootstrap), to which the code
//! highlighting CSS is appended. assets/icons/ is copied as is.
//!
//! The Rust wiki embedded rolldown and lightningcss; there is no Zig
//! bundler. esbuild is a devDependency of the wiki repo, so the same
//! `pnpm install` that fetches bootstrap and clipboard (and jsdoc) also
//! brings the bundler, pinned by pnpm-lock.yaml: nothing else has to be on
//! the PATH of whatever runs the build (the pull job serving /wiki/, the
//! precommit hook). `$WIKI_ESBUILD` overrides the binary.
const std = @import("std");
const state_mod = @import("state.zig");
const highlight = @import("highlight");
const Sys = @import("sys.zig").Sys;

pub fn bundle(sys: Sys, wiki: []const u8, dist: []const u8, state: *state_mod.State) !void {
    const out = sys.join(&.{ dist, "_assets" });
    var inputs: std.ArrayList([]const u8) = .empty;
    try inputs.appendSlice(sys.arena, try state_mod.dirIds(sys, sys.join(&.{ wiki, "assets" })));
    try inputs.append(sys.arena, state_mod.fileId(sys, sys.join(&.{ wiki, "pnpm-lock.yaml" })));
    try inputs.append(sys.arena, selfId(sys));
    const key = state_mod.key(sys.arena, inputs.items);
    if (std.mem.eql(u8, state.assets, key) and sys.isFile(sys.join(&.{ out, "main.js" })) and sys.isFile(sys.join(&.{ out, "style.css" }))) return;

    const esbuild = sys.getenv("WIKI_ESBUILD") orelse sys.join(&.{ wiki, "node_modules", "esbuild", "bin", "esbuild" });
    if (sys.getenv("WIKI_ESBUILD") == null and !sys.isFile(esbuild)) {
        std.debug.print("wiki: {s} is missing; run `pnpm install` in {s}\n", .{ esbuild, wiki });
        return error.BundleFailed;
    }
    try sys.removeTree(out);
    try sys.mkdirs(out);
    const js = sys.run(&.{ esbuild, "./assets/main.js", "--bundle", "--minify", "--format=esm", "--log-level=warning", try std.fmt.allocPrint(sys.arena, "--outfile={s}", .{sys.join(&.{ out, "main.js" })}) }, wiki);
    if (!js.ok) {
        std.debug.print("wiki: esbuild assets/main.js failed\n{s}{s}\n", .{ js.stdout, js.stderr });
        return error.BundleFailed;
    }
    const css_path = sys.join(&.{ out, "style.css" });
    const css = sys.run(&.{ esbuild, "./assets/style.css", "--bundle", "--minify", "--log-level=warning", try std.fmt.allocPrint(sys.arena, "--outfile={s}", .{css_path}) }, wiki);
    if (!css.ok) {
        std.debug.print("wiki: esbuild assets/style.css failed\n{s}{s}\n", .{ css.stdout, css.stderr });
        return error.BundleFailed;
    }
    const sheet = try sys.readFile(css_path);
    try sys.writeFile(css_path, try std.mem.concat(sys.arena, u8, &.{ sheet, highlight.css }));
    const icons = sys.join(&.{ wiki, "assets", "icons" });
    if (sys.isDir(icons)) try sys.copyDir(icons, sys.join(&.{ out, "icons" }));
    state.assets = key;
}

/// Blob id of the running binary: a new build re-renders everything.
pub fn selfId(sys: Sys) []const u8 {
    const path = std.process.executablePathAlloc(sys.io, sys.arena) catch return "";
    return state_mod.fileId(sys, path);
}
