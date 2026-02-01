const std = @import("std");

pub fn build(b: *std.Build) void {
    const options = b.addOptions();
    const use_emulator = b.option(bool, "use_emulator", "Runs in a semi emulator to allow access to logs / panics.") orelse false;
    options.addOption(bool, "use_emulator", use_emulator);

    const microzig = @import("microzig");

    const MicroBuild = microzig.MicroBuild(.{
        .rp2xxx = true,
    });

    const optimize = b.standardOptimizeOption(.{});

    if (use_emulator) {
        const target = b.standardTargetOptions(.{});

        const sdl3_dep = b.dependency("sdl3", .{
            .target = target,
            .optimize = optimize,
        });

        const microzig_emulator_mod = b.addModule("microzig", .{
            .root_source_file = b.path("microzig_emulator/root.zig"),
            .target = target,
        });

        const mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{
            .name = "PicoWatch",
            .root_module = mod,
        });

        exe.root_module.addOptions("build_options", options);

        mod.addImport("sdl3", sdl3_dep.module("sdl3"));
        mod.addImport("microzig", microzig_emulator_mod);

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    } else {
        const mz_dep = b.dependency("microzig", .{});
        const mb = MicroBuild.init(b, mz_dep) orelse return;

        const firmware = mb.add_firmware(.{
            .name = "program",
            .target = mb.ports.rp2xxx.boards.raspberrypi.pico2_arm,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
        });

        firmware.app_mod.addOptions("build_options", options);

        mb.install_firmware(firmware, .{});
    }
}
