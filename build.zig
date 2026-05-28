const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link GTK 3 and dependencies
    exe_mod.linkSystemLibrary("gtk-3", .{});
    exe_mod.linkSystemLibrary("cairo", .{});
    exe_mod.linkSystemLibrary("pangocairo", .{});
    exe_mod.link_libc = true;

    // Add common GTK include paths for cimport
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/gtk-3.0" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/pango-1.0" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/cairo" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/harfbuzz" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/freetype2" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/libpng16" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/gdk-pixbuf-2.0" });
    exe_mod.addIncludePath(.{ .cwd_relative = "/usr/include/atk-1.0" });

    const exe = b.addExecutable(.{
        .name = "oneshot",
        .use_lld = true,
        .use_llvm = true,
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
