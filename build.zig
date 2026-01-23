const std = @import("std");
const microzig = @import("microzig");
const eql = std.mem.eql;
const ArrayList = std.ArrayList;

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) !void {
    const mz_dep = b.dependency("microzig", .{});
    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "blinky",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico2_arm,
        .optimize = .Debug,
        .root_source_file = b.path("src/main.zig"),
    });

    const foundationlibc_dep = b.dependency("foundation_libc", .{
        .target = firmware.target.zig_target,
        .optimize = .Debug,
        .single_threaded = true,
    });

    firmware.app_mod.linkLibrary(foundationlibc_dep.artifact("foundation"));

    const allocator = b.allocator;

    var rootDir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer rootDir.close();

    var dirsToScan: ArrayList([]const u8) = .empty;
    defer dirsToScan.deinit(allocator);

    try dirsToScan.append(allocator, "lib");

    while (dirsToScan.pop()) |dirName| {
        var dir = try rootDir.openDir(dirName, .{ .iterate = true });
        var iterator = dir.iterate();
        while (try iterator.next()) |item| {
            const path = b.pathJoin(&.{ dirName, item.name });
            if (item.kind == .directory) {
                firmware.app_mod.addIncludePath(b.path(path));
                try dirsToScan.append(allocator, path);
            } else if (item.kind == .file and std.mem.eql(u8, std.fs.path.extension(item.name), ".c")) {
                std.debug.print("Added C source file: {s}\n", .{path});
                firmware.app_mod.addCSourceFile(.{ .file = b.path(path) });
            }
        }
    }

    firmware.app_mod.addIncludePath(b.path("lib"));

    firmware.app_mod.addIncludePath(b.path("c_lib"));
    firmware.app_mod.addCSourceFile(.{ .file = b.path("c_lib/arithmetic.c") });

    mb.install_firmware(firmware, .{});
}
