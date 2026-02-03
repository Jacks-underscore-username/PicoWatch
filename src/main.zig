const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");
const types = @import("types.zig");
const profiler = @import("profiler.zig");
const use_emulator = @import("build_options").use_emulator;

const hal = microzig.hal;
const time = hal.time;
const Random = if (use_emulator) std.Random else hal.rand;

const Ball = struct {
    x: u16,
    y: u16,
    sx: u1,
    sy: u1,
    color: amoled.ColorSize,
    r: u16,
};

pub fn main() !void {
    var gpa = blk: {
        if (use_emulator) {
            const gpa: std.heap.DebugAllocator(.{}) = .init;
            break :blk gpa;
        }
        break :blk microzig.Allocator.init_with_heap(1_000) catch {
            unreachable;
        };
    };

    const alloc = gpa.allocator();

    profiler.init(alloc);
    defer profiler.deinit();

    usb.init();

    try amoled.init();
    defer amoled.deinit();

    var image: [amoled.PIXEL_COUNT]amoled.ColorSize align(@alignOf(amoled.ColorSize)) = undefined;
    try amoled.writeImage(&image);

    var random = blk: {
        if (use_emulator) {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            var prng = Random.DefaultPrng.init(seed);
            break :blk prng.random();
        } else {
            var prng = Random.Ascon.init();
            break :blk prng.random();
        }
    };

    var balls: [50]Ball = undefined;
    for (0..balls.len) |i|
        balls[i] = .{
            .x = random.intRangeLessThan(u16, 100, amoled.WIDTH - 100),
            .y = random.intRangeLessThan(u16, 100, amoled.HEIGHT - 100),
            .sx = if (random.boolean()) 1 else 0,
            .sy = if (random.boolean()) 1 else 0,
            .r = 25,
            .color = @intFromEnum(random.enumValue(if (amoled.ColorSize == u16) amoled.Colors else amoled.Colors2)),
        };

    var i: u64 = 0;
    while (!use_emulator or i < 2_000) : (i += 1) {
        usb.poll();

        amoled.fill(&image, @intFromEnum(amoled.Colors.Black));

        for (&balls) |*ball| {
            if (ball.sx == 1) {
                ball.x += 1;
            } else ball.x -= 1;
            if (ball.sy == 1) {
                ball.y += 1;
            } else ball.y -= 1;
            if (ball.x + ball.r >= amoled.WIDTH - 1 or ball.x - ball.r <= 0) ball.sx = if (ball.sx == 1) 0 else 1;
            if (ball.y + ball.r >= amoled.HEIGHT - 1 or ball.y - ball.r <= 0) ball.sy = if (ball.sy == 1) 0 else 1;
        }

        for (&balls) |*ball| amoled.circle(&image, ball.x, ball.y, ball.r, ball.color);

        try amoled.writeImage(&image);

        if (i % 10 == 0) {
            profiler.log(i + 1);
            usb.log("i: {}\r\n", .{i});
        }
    }
}
