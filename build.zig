const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "blinky",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico2_arm,
        .optimize = .Debug,
        .root_source_file = b.path("src/main.zig"),
    });

    firmware.app_mod.addIncludePath(b.path("c_lib"));
    firmware.app_mod.addCSourceFile(.{ .file = b.path("c_lib/arithmetic.c") });

    const foundationlibc_dep = b.dependency("foundation_libc", .{
        .target = firmware.target.zig_target,
        .optimize = .Debug,
        .single_threaded = true,
    });

    firmware.app_mod.linkLibrary(foundationlibc_dep.artifact("foundation"));

    mb.install_firmware(firmware, .{});
}
