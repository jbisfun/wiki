//! `wiki`: the workspace wiki's generator (src/), its live server and its MCP
//! server. This repo is also the site's data (wiki.toml, templates/, pages/,
//! assets/, locales/, translations/), which the binary reads at run time.
//!
//!   zig build                                    zig-out/bin/wiki
//!   zig build test                               unit tests
//!   zig build -Doptimize=ReleaseSafe --prefix ~/.local   install
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};

    const options = b.addOptions();
    options.addOption([]const u8, "version", "0.1.0");

    const exe = b.addExecutable(.{
        .name = "wiki",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    addImports(b, exe.root_module, target, optimize, options);
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run wiki").dependOn(&run.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .filters = test_filters,
        // tree-sitter's grammars (the theme's highlight module) need LLVM
        .use_llvm = true,
    });
    addImports(b, tests.root_module, target, optimize, options);
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}

// cmark-gfm (C, built here; adapted from abhinav/libcmark-gfm.zig), uucode,
// superhtml's html tokenizer, zig-toml, clap, parley and the theme package
// (../theme: zig-vin, the tool bar, serve.addr discovery, the highlighter)
fn addImports(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, options: *std.Build.Step.Options) void {
    module.addOptions("build_options", options);
    const cmark = b.dependency("cmark_gfm", .{});
    const config = b.addConfigHeader(.{ .style = .{ .cmake = cmark.path("src/config.h.in") } }, .{
        .HAVE_STDBOOL_H = true,
        .HAVE___BUILTIN_EXPECT = true,
        .HAVE___ATTRIBUTE__ = true,
    });
    const version = b.addConfigHeader(.{ .style = .{ .cmake = cmark.path("src/cmark-gfm_version.h.in") } }, .{
        .PROJECT_VERSION_MAJOR = "0",
        .PROJECT_VERSION_MINOR = "29",
        .PROJECT_VERSION_PATCH = "0",
        .PROJECT_VERSION_GFM = "13",
    });
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "cmark-gfm",
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    lib.root_module.addConfigHeader(config);
    lib.root_module.addConfigHeader(version);
    lib.root_module.addIncludePath(b.path("src/c"));
    lib.root_module.addIncludePath(cmark.path("src"));
    lib.root_module.addIncludePath(cmark.path("extensions"));
    lib.root_module.addCMacro("CMARK_GFM_STATIC_DEFINE", "1");
    lib.root_module.addCMacro("CMARK_GFM_EXTENSIONS_STATIC_DEFINE", "1");
    lib.root_module.addCSourceFiles(.{
        .root = cmark.path("src"),
        .files = &.{ "xml.c", "cmark.c", "man.c", "buffer.c", "blocks.c", "cmark_ctype.c", "inlines.c", "latex.c", "houdini_href_e.c", "syntax_extension.c", "houdini_html_e.c", "plaintext.c", "utf8.c", "references.c", "render.c", "iterator.c", "arena.c", "linked_list.c", "commonmark.c", "map.c", "html.c", "plugin.c", "scanners.c", "footnotes.c", "houdini_html_u.c", "registry.c", "node.c" },
        .flags = &.{"-std=c99"},
    });
    lib.root_module.addCSourceFiles(.{
        .root = cmark.path("extensions"),
        .files = &.{ "core-extensions.c", "table.c", "strikethrough.c", "autolink.c", "tagfilter.c", "ext_scanners.c", "tasklist.c" },
        .flags = &.{"-std=c99"},
    });
    module.linkLibrary(lib);

    const theme = b.dependency("theme", .{ .target = target, .optimize = optimize, .highlight = true });
    module.addImport("theme", theme.module("theme"));
    module.addImport("discovery", theme.module("discovery"));
    module.addImport("highlight", theme.module("highlight"));
    module.addImport("toml", b.dependency("toml", .{ .target = target, .optimize = optimize }).module("toml"));
    module.addImport("superhtml", b.dependency("superhtml", .{ .target = target, .optimize = optimize }).module("superhtml"));
    module.addImport("uucode", b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        .fields = @as([]const []const u8, &.{ "general_category", "simple_lowercase_mapping", "script" }),
    }).module("uucode"));
    module.addImport("clap", b.dependency("clap", .{ .target = target, .optimize = optimize }).module("clap"));
    module.addImport("parley", b.dependency("parley", .{ .target = target, .optimize = optimize }).module("parley"));
}
