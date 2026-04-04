const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "oneshot",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link GTK 3 and dependencies
    exe.linkSystemLibrary("gtk-3");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("pangocairo");
    exe.linkLibC();

    // Add common GTK include paths for cimport
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/gtk-3.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/pango-1.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/glib-2.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/lib/x86_64-linux-gnu/glib-2.0/include" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/cairo" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/harfbuzz" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/freetype2" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/libpng16" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/gdk-pixbuf-2.0" });
    exe.addIncludePath(.{ .cwd_relative = "/usr/include/atk-1.0" });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
