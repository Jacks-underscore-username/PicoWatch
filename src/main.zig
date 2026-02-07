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

const temp_num_patterns = blk: {
    @setEvalBranchQuota(15_000);

    const digits: [10][15]bool = .{
        .{ // 0
            true, true,  true,
            true, false, true,
            true, false, true,
            true, false, true,
            true, true,  true,
        },
        .{ // 1
            false, false, true,
            false, false, true,
            false, false, true,
            false, false, true,
            false, false, true,
        },
        .{ // 2
            true,  true,  true,
            false, false, true,
            true,  true,  true,
            true,  false, false,
            true,  true,  true,
        },
        .{ // 3
            true,  true,  true,
            false, false, true,
            true,  true,  true,
            false, false, true,
            true,  true,  true,
        },
        .{ // 4
            true,  false, true,
            true,  false, true,
            true,  true,  true,
            false, false, true,
            false, false, true,
        },
        .{ // 5
            true,  true,  true,
            true,  false, false,
            true,  true,  true,
            false, false, true,
            true,  true,  true,
        },
        .{ // 6
            true, true,  true,
            true, false, false,
            true, true,  true,
            true, false, true,
            true, true,  true,
        },
        .{ // 7
            true,  true,  true,
            false, false, true,
            false, false, true,
            false, false, true,
            false, false, true,
        },
        .{ // 8
            true, true,  true,
            true, false, true,
            true, true,  true,
            true, false, true,
            true, true,  true,
        },
        .{ // 9
            true,  true,  true,
            true,  false, true,
            true,  true,  true,
            false, false, true,
            false, false, true,
        },
    };

    var scaled_digits: [10][135]bool = undefined;

    for (0..10) |num| {
        for (0..3) |x| {
            for (0..5) |y| {
                for (0..3) |x2| {
                    for (0..3) |y2|
                        scaled_digits[num][x * 3 + y * 27 + x2 + y2 * 9] = digits[num][x + y * 3];
                }
            }
        }
    }

    // Asserts there is no undefined values in the scaled_digits array.
    for (0..10) |num| {
        for (0..135) |index| {
            if (scaled_digits[num][index] != true and scaled_digits[num][index] != false) @compileError("Num has incomplete mappings");
        }
    }

    const x1: comptime_int = @ceil(@as(comptime_float, @floatFromInt((amoled.WIDTH) * 1)) / 5.0);
    const x2: comptime_int = @floor(@as(comptime_float, @floatFromInt((amoled.WIDTH) * 3)) / 5.0);
    const y1: comptime_int = @ceil(@as(comptime_float, @floatFromInt((amoled.WIDTH) * 1)) / 5.0);
    const y2: comptime_int = @floor(@as(comptime_float, @floatFromInt((amoled.HEIGHT) * 3)) / 5.0);

    const digit_start_points: [4]struct { x: comptime_int, y: comptime_int } = .{
        .{ .x = x1, .y = y1 },
        .{ .x = x2, .y = y1 },
        .{ .x = x1, .y = y2 },
        .{ .x = x2, .y = y2 },
    };

    // Asserts none of the start points are too close to the edge.
    for (digit_start_points) |point| {
        if (point.x == 0 or point.x + 9 >= amoled.WIDTH or point.y == 0 or point.y + 15 >= amoled.HEIGHT)
            @compileError("Point is too close to the edge");
    }

    var result: [4][10][135]Point = undefined;

    for (0..4) |point_index| {
        const start_point = digit_start_points[point_index];
        for (0..10) |num| {
            var index = 0;
            for (0..9) |x| {
                for (0..15) |y| {
                    if (scaled_digits[num][x + y * 9]) {
                        result[point_index][num][index] = .{ .x = start_point.x + x, .y = start_point.y + y };
                        index += 1;
                    }
                }
            }
            for (index..135) |blank_index|
                result[point_index][num][blank_index] = .{ .x = amoled.WIDTH, .y = 0 };
        }
    }

    var centers: [8]Point = undefined;
    for (0..4) |point_index| {
        const point = digit_start_points[point_index];
        centers[point_index * 2] = .{ .x = point.x + 4, .y = point.y + 4 };
        centers[point_index * 2 + 1] = .{ .x = point.x + 4, .y = point.y + 10 };
    }

    break :blk .{ centers, result };
};

pub const num_pattern_centers = temp_num_patterns[0];
pub const num_patterns = temp_num_patterns[1];
pub const num_patterns_no_zero = blk: {
    var result: [4][10][135]Point = undefined;
    result = result;
    for (0..4) |point_index| {
        for (0..135) |index|
            result[point_index][0][index] = .{ .x = amoled.WIDTH, .y = 0 };

        for (1..10) |num|
            @memcpy(&result[point_index][num], &num_patterns[point_index][num]);
    }
    break :blk result;
};

pub const Point = struct { x: u16, y: u16 };

pub const ScreenApi = struct {
    time: Time,
    alloc: std.mem.Allocator,
    random: std.Random,
    image: *[amoled.PIXEL_COUNT]amoled.ColorSize,
};

pub const Time = struct {
    year: u16,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
};

pub fn getCurrentTime() Time {
    const ms: u64 = if (use_simulator) @intCast(std.time.milliTimestamp()) else hal.rtc.get_time();
    const seconds: u64 = @divTrunc(ms, std.time.ms_per_s);

    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds - std.time.s_per_hour * 6) };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return .{
        .year = year_day.year,
        .month = month_day.month.numeric(),
        .day = month_day.day_index + 1,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

pub fn sleep(time: u32) void {
    if (use_simulator) {
        std.Thread.sleep(time * 1_000_000);
    } else hal.time.sleep_ms(time);
}

pub fn main() !void {
    var gpa = blk: {
        if (use_simulator) {
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

    try usb.init();
    // while (!usb.ready()) usb.poll();
    // for (0..10) |_| usb.log("\r\n", .{});

    // if (!use_simulator) {
    //     const epoch_time: u64 = 1770423278;
    //     var buffer: [128]u8 = undefined;
    //     _ = try microzig.drivers.DateTime.from_timestamp(epoch_time).to_rfc_7231(&buffer);
    //     hal.rtc.set_time(epoch_time);
    // }

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
        // usb.log("{}", .{getCurrentTime()});

        last_start = if (use_simulator) @intCast(profiler.getNow()) else profiler.getNow().to_us();
        usb.poll();

        const time = getCurrentTime();
        var image: [amoled.PIXEL_COUNT]amoled.ColorSize = undefined;

        try veins.update(.{
            .alloc = alloc,
            .image = &image,
            .random = random,
            .time = time,
        });

        try amoled.writeImage(alloc, &image);

        if (i % 10 == 0)
            profiler.log(i + 1);

        const now: u64 = if (use_simulator) @intCast(profiler.getNow()) else profiler.getNow().to_us();
        const delta = now - last_start;
        const delay = if (delta < target_delta) (target_delta - delta) / 1_000 else 0;
        // usb.log("i: {}, delta: {}, target_delta: {}, delay: {}ms", .{ i, delta, target_delta, delay });
        if (delay > 0)
            sleep(@intCast(delay));
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
