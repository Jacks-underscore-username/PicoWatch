const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .thumb,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
            .os_tag = .freestanding,
            .abi = .eabi,
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    // Define the SDK path - adjust this to your Pico SDK installation
    const pico_sdk_path = try std.process.getEnvVarOwned(b.allocator, "PICO_SDK_PATH");
    std.debug.print("PICO_SDK_PATH: {s}", .{pico_sdk_path});
    defer b.allocator.free(pico_sdk_path);
    const pico_board = "pico2";

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "RP2350-Touch-AMOLED-1.8",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.c"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // Set C/C++ standards
    // exe.addCSourceFlags(&.{
    //     "-std=c11",
    // });
    // exe.addCXXSourceFlags(&.{
    //     "-std=c++17",
    // });

    // Optimization level
    // exe.root_module.addCMacro("NDEBUG", null);
    // exe.root_module.addCMacro("PICO_XOSC_STARTUP_DELAY_MULTIPLIER=1", null);

    // Include directories
    exe.addIncludePath(b.path("."));
    exe.addIncludePath(b.path("lib/Config"));
    exe.addIncludePath(b.path("lib/QSPI_PIO"));
    exe.addIncludePath(b.path("lib/AMOLED"));
    // exe.addIncludePath(b.path("lib/Touch"));
    // exe.addIncludePath(b.path("lib/QMI8658"));
    // exe.addIncludePath(b.path("lib/PCF85063A"));
    // exe.addIncludePath(b.path("lib/lvgl"));

    // Pico SDK includes
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/common/pico_base/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/common/pico_stdlib/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_base/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_gpio/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_uart/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_spi/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_i2c/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_pwm/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_adc/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_pio/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_dma/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_multicore/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdlib/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdio/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdio_usb/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdio_uart/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_platform/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_unique_id/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_bit_ops/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_divider/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_sync/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_time/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_malloc/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_float/include" })));
    exe.addIncludePath(b.pathResolve(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_double/include" })));

    // Pico SDK source files
    exe.addCSourceFiles(.{
        .files = &.{
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdlib/stdlib.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_platform/platform.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_claim/claim.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_sync/sync.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_gpio/gpio.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_uart/uart.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_spi/spi.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_i2c/i2c.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_pwm/pwm.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_adc/adc.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_pio/pio.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/hardware_dma/dma.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_multicore/multicore.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdio/stdio.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdio_usb/stdio_usb.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdio_uart/stdio_uart.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_time/time.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_time/timeout_helper.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_sync/sem.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_sync/lock_core.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_sync/mutex.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_sync/critical_section.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_malloc/pico_malloc.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_unique_id/unique_id.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_divider/divider.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_bit_ops/bit_ops_aeabi.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_float/float_aeabi.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_float/float_math.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_float/float_v1_rom_shim.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_double/double_aeabi.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_double/double_math.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_double/double_v1_rom_shim.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_int64_ops/pico_int64_ops_aeabi.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_mem_ops/mem_ops_aeabi.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_standard_link/crt0.S" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_standard_link/binary_info.c" }),
            b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_standard_link/new_delete.cpp" }),
        },
        .flags = &.{
            "-O2",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-unused-parameter",
            "-Wno-unused-function",
            "-Wno-sign-compare",
        },
    });

    // Add your library source files
    const config_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "Config",
        .root_module = b.addModule("Config", .{
            .root_source_file = b.path("lib/Config/config.c"), // Adjust to actual source file
            .target = target,
            .optimize = optimize,
        }),
    });
    config_lib.addIncludePath(b.path("lib/Config"));
    // config_lib.addCSourceFlags(&.{"-O2"});

    const qspi_pio_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "QSPI_PIO",
        .root_module = b.addModule("QSPI_PIO", .{
            .root_source_file = b.path("lib/QSPI_PIO/qspi_pio.c"), // Adjust to actual source file
            .target = target,
            .optimize = optimize,
        }),
    });
    qspi_pio_lib.addIncludePath(b.path("lib/QSPI_PIO"));
    // qspi_pio_lib.addCSourceFlags(&.{"-O2"});

    const amoled_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "AMOLED",
        .root_module = b.addModule("AMOLED", .{
            .root_source_file = b.path("lib/AMOLED/amoled.c"), // Adjust to actual source file
            .target = target,
            .optimize = optimize,
        }),
    });
    amoled_lib.addIncludePath(b.path("lib/AMOLED"));
    // amoled_lib.addCSourceFlags(&.{"-O2"});

    // Link libraries
    exe.linkLibrary(config_lib);
    exe.linkLibrary(qspi_pio_lib);
    exe.linkLibrary(amoled_lib);

    // Linker script
    const linker_script = b.path(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_standard_link/memmap_default.ld" }));
    exe.setLinkerScript(linker_script);

    // Compiler and linker flags
    exe.root_module.addCMacro("PICO_BOARD", "\"" ++ pico_board ++ "\"");
    exe.root_module.addCMacro("PICO_TARGET_NAME", "\"RP2350-Touch-AMOLED-1.8\"");
    exe.root_module.addCMacro("PICO_NO_HARDWARE", "0");
    exe.root_module.addCMacro("LIB_PICO_STDIO_USB", "1");
    exe.root_module.addCMacro("LIB_PICO_STDIO_UART", "0");
    exe.root_module.addCMacro("PICO_USE_STACK_GUARDS", "0");

    exe.root_module.addCMacro("PICO_STDIO_USB_CONNECT_WAIT_TIMEOUT_MS", "-1");
    exe.root_module.addCMacro("PICO_STDIO_USB_LOW_PRIORITY_IRQ", "0x401");
    exe.root_module.addCMacro("PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE", "1");

    exe.addAssemblyFile(b.path(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_standard_link/crt0.S" })));

    exe.addObjectFile(b.path(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_standard_link/binary_info.c.o" })));
    exe.addObjectFile(b.path(b.pathJoin(&.{ pico_sdk_path, "/src/rp2_common/pico_stdlib/stdlib.c.o" })));

    // Compiler flags
    // exe.addCFlags(&.{
    //     "-O2",
    //     "-Wall",
    //     "-Wextra",
    //     "-Werror",
    //     "-Wno-unused-parameter",
    //     "-Wno-unused-function",
    //     "-Wno-sign-compare",
    //     "-mcpu=cortex-m0plus",
    //     "-mthumb",
    //     "-ffunction-sections",
    //     "-fdata-sections",
    //     "-fno-exceptions",
    //     "-fno-unwind-tables",
    //     "-fno-asynchronous-unwind-tables",
    //     "-nostdlib",
    //     "-nostartfiles",
    // });

    // Linker flags
    // exe.addLinkerFlags(&.{
    //     "--gc-sections",
    //     "--print-memory-usage",
    //     "--wrap=__aeabi_uldivmod",
    //     "--wrap=__aeabi_ldivmod",
    //     "--wrap=__aeabi_uldivmod",
    //     "--wrap=_exit",
    //     "--wrap=exit",
    //     "--wrap=main",
    //     "-nostdlib",
    //     "-nostartfiles",
    // });

    // Additional PIO handling (you'll need to generate the PIO header separately)
    // For PIO files, you need to run pioasm to generate the header
    const pioasm = b.addSystemCommand(&.{
        "pioasm",
        "lib/QSPI_PIO/qspi.pio",
        "lib/QSPI_PIO/qspi.pio.h",
    });
    exe.step.dependOn(&pioasm.step);

    // Install the executable
    b.installArtifact(exe);

    // Create UF2 file
    const elf_to_uf2 = b.addSystemCommand(&.{
        "elf2uf2",
        "-o",
        b.getInstallPath(.bin, "RP2350-Touch-AMOLED-1.8.uf2"),
        b.getInstallPath(.bin, "RP2350-Touch-AMOLED-1.8"),
    });
    elf_to_uf2.step.dependOn(b.getInstallStep());
    b.getInstallStep().dependOn(&elf_to_uf2.step);
}
