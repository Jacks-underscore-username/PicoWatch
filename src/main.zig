const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");
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

var startTimes: std.StringHashMap(microzig.drivers.time.Absolute) = undefined;

pub fn startTiming(comptime key: []const u8) void {
    startTimes.put(key, time.get_time_since_boot()) catch {
        unreachable;
    };
}

pub fn endTiming(comptime key: []const u8) void {
    defer _ = startTimes.remove(key);
    const diff = time.get_time_since_boot().diff(startTimes.get(key).?).to_us();
    if (diff < 1_000) {
        usb.log("{s} took {} US. ", .{ key, diff });
    } else if (diff < 1_000_000) {
        usb.log("{s} took {} MS. ", .{ key, diff / 1_000 });
    } else {
        usb.log("{s} took {} S. ", .{ key, diff / 1_000_000 });
    }
}

pub fn main() !void {
    var gpa = try microzig.Allocator.init_with_heap(1_000);
    const alloc = gpa.allocator();

    startTimes = .init(alloc);
    defer startTimes.deinit();

    usb.init();

    try amoled.init();
    defer amoled.deinit();

    var image: [amoled.PIXEL_COUNT]amoled.ColorSize = undefined;
    const image_ptr: *align(@alignOf(amoled.ColorSize)) [amoled.PIXEL_COUNT]amoled.ColorSize = @alignCast(&image);
    usb.log("{} is_aligned: {}\r\n", .{ @intFromPtr(image_ptr), std.mem.isAligned(@intFromPtr(image_ptr), @alignOf(amoled.ColorSize)) });
    amoled.fill(image_ptr, @intFromEnum(if (amoled.ColorSize == u16) amoled.Colors.Red else amoled.Colors2.Red));
    try amoled.writeImage(image_ptr);

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

    var balls: [25]Ball = undefined;
    for (0..balls.len) |i|
        balls[i] = .{
            .x = random.intRangeLessThan(u16, 50, amoled.WIDTH - 50),
            .y = random.intRangeLessThan(u16, 50, amoled.HEIGHT - 50),
            .sx = if (random.boolean()) 1 else 0,
            .sy = if (random.boolean()) 1 else 0,
            .r = 25,
            .color = @intFromEnum(random.enumValue(if (amoled.ColorSize == u16) amoled.Colors else amoled.Colors2)),
        };

    // for (0..100) |_| {
    while (true) {
        startTiming("Total");

        startTiming("Poll");
        usb.poll();
        endTiming("Poll");

        startTiming("Fill");
        amoled.fill(image_ptr, @intFromEnum(amoled.Colors.Black));
        endTiming("Fill");

        startTiming("Move");
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
        endTiming("Move");

        startTiming("Circles");
        for (&balls) |*ball| amoled.circle(image_ptr, ball.x, ball.y, ball.r, ball.color);
        endTiming("Circles");

        startTiming("Write");
        try amoled.writeImage(image_ptr);
        endTiming("Write");

        endTiming("Total");

        usb.log("\r\n", .{});
    }
}
