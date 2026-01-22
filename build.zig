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

    firmware.add_include_path(b.path("c_lib"));
    firmware.add_c_source_file(.{ .file = b.path("c_lib/arithmetic2.c") });

    mb.install_firmware(firmware, .{});
}
