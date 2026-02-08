const std = @import("std");

pub fn build(b: *std.Build) void {
    const options = b.addOptions();
    const use_simulator = b.option(bool, "use_simulator", "Runs in a semi simulator to allow access to logs / panics.") orelse false;
    options.addOption(bool, "use_simulator", use_simulator);

    const microzig = @import("microzig");

    const MicroBuild = microzig.MicroBuild(.{
        .rp2xxx = true,
    });

    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    if (use_simulator) {
        const sdl3_dep = b.dependency("sdl3", .{
            .target = target,
            .optimize = optimize,
        });

        const microzig_simulator_mod = b.addModule("microzig", .{
            .root_source_file = b.path("microzig_simulator/root.zig"),
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
            .use_llvm = true,
        });

        exe.root_module.addOptions("build_options", options);

        mod.addImport("sdl3", sdl3_dep.module("sdl3"));
        mod.addImport("microzig", microzig_simulator_mod);

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const mod_tests = b.addTest(.{
            .root_module = mod,
        });

        const run_mod_tests = b.addRunArtifact(mod_tests);

        const exe_tests = b.addTest(.{
            .root_module = exe.root_module,
        });

        const run_exe_tests = b.addRunArtifact(exe_tests);

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
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
