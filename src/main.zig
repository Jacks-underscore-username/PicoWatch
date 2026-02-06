const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");
const types = @import("types.zig");
const profiler = @import("profiler.zig");
const veins = @import("screens/veins.zig");
const use_simulator = @import("build_options").use_simulator;

const hal = microzig.hal;
const Random = if (use_simulator) std.Random else hal.rand;

const Ball = struct {
    x: u16,
    y: u16,
    sx: u1,
    sy: u1,
    color: amoled.ColorSize,
    r: u16,
};

pub fn sleep(time: u32) void {
    if (use_simulator) {
        std.Thread.sleep(time * 1_000_000);
    } else hal.time.sleep_ms(time);
}

pub fn main() !void {
    var gpa = blk: {
        if (use_simulator) {
            // var buffer: [1000]u8 = undefined;
            // const fba: std.heap.FixedBufferAllocator = .init(&buffer);
            // break :blk fba;
            const gpa: std.heap.DebugAllocator(.{
                .enable_memory_limit = true,
            }) = .init;
            break :blk gpa;
        }
        break :blk microzig.Allocator.init_with_heap(1_000) catch {
            unreachable;
        };
    };

    defer if (use_simulator) std.testing.expect(gpa.deinit() == .ok) catch
        @panic("Memory leak detected!");

    const alloc = gpa.allocator();

    profiler.init(alloc);
    defer profiler.deinit();

    usb.init();

    try amoled.init();
    defer amoled.deinit();

    var random = blk: {
        if (use_simulator) {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            var prng = Random.DefaultPrng.init(seed);
            break :blk prng.random();
        } else {
            var prng = Random.Ascon.init();
            break :blk prng.random();
        }
    };

    random = random;

    defer veins.deinit(alloc);

    var i: u64 = 0;
    const target_fps = 60;
    const target_delta: u64 = 1_000_000 / target_fps;
    var last_start: u64 = 0;
    while (i < 400_000 or !use_simulator) : (i += 1) {
        last_start = if (use_simulator) @intCast(profiler.getNow()) else profiler.getNow().to_us();
        usb.poll();

        try veins.update(alloc, random);

        if (i % 10 == 0)
            profiler.log(i + 1);

        const now: u64 = if (use_simulator) @intCast(profiler.getNow()) else profiler.getNow().to_us();
        const delta = now - last_start;
        const delay = if (delta < target_delta) (target_delta - delta) / 1_000 else 0;
        usb.log("i: {}, delta: {}, target_delta: {}, delay: {}ms", .{ i, delta, target_delta, delay });
        if (delay > 0)
            sleep(@intCast(delay));
    }

    // var balls: [10]Ball = undefined;
    // for (0..balls.len) |i|
    //     balls[i] = .{
    //         .x = random.intRangeLessThan(u16, @divTrunc(25, amoled.SCALE), amoled.WIDTH - @divTrunc(25, amoled.SCALE)),
    //         .y = random.intRangeLessThan(u16, @divTrunc(25, amoled.SCALE), amoled.HEIGHT - @divTrunc(25, amoled.SCALE)),
    //         .sx = if (random.boolean()) 1 else 0,
    //         .sy = if (random.boolean()) 1 else 0,
    //         .r = @divTrunc(25, amoled.SCALE),
    //         .color = @intFromEnum(if (amoled.ColorSize == u16) amoled.Colors.White else amoled.Colors2.White), //  @intFromEnum(random.enumValue(if (amoled.ColorSize == u16) amoled.Colors else amoled.Colors2)),
    //     };

    // var i: u64 = 0;
    // while (!use_simulator or i < 2_000) : (i += 1) {
    //     usb.poll();

    //     amoled.fill(&image, @intFromEnum(amoled.Colors.Black));

    //     amoled.rect(&image, 0, 0, amoled.WIDTH, amoled.HEIGHT, @intFromEnum(if (amoled.ColorSize == u16) amoled.Colors.Red else amoled.Colors2.Red));
    //     amoled.rect(&image, 0, 0, @divTrunc(25, amoled.SCALE), amoled.HEIGHT, @intFromEnum(if (amoled.ColorSize == u16) amoled.Colors.Green else amoled.Colors2.Green));
    //     amoled.rect(&image, 0, 0, amoled.WIDTH, @divTrunc(25, amoled.SCALE), @intFromEnum(if (amoled.ColorSize == u16) amoled.Colors.Blue else amoled.Colors2.Blue));

    //     for (&balls) |*ball| {
    //         if (ball.sx == 1) {
    //             ball.x += 1;
    //         } else ball.x -= 1;
    //         if (ball.sy == 1) {
    //             ball.y += 1;
    //         } else ball.y -= 1;
    //         if (ball.x + ball.r >= amoled.WIDTH - 1 or ball.x - ball.r <= 0) ball.sx = if (ball.sx == 1) 0 else 1;
    //         if (ball.y + ball.r >= amoled.HEIGHT - 1 or ball.y - ball.r <= 0) ball.sy = if (ball.sy == 1) 0 else 1;
    //     }

    //     for (&balls) |*ball| amoled.circle(&image, ball.x, ball.y, ball.r, ball.color);

    //     try amoled.writeImage(&image);

    //     if (i % 10 == 0) {
    //         profiler.log(i + 1);
    //         usb.log("i: {}\r\n", .{i});
    //     }
    // }
}

test {
    @import("std").testing.refAllDecls(@This());
}
