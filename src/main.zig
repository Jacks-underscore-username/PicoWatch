const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");
const types = @import("types.zig");
const profiler = @import("profiler.zig");
const veins_screen = @import("screens/veins.zig").screen;
const circles_screen = @import("screens/circles.zig").screen;
const use_simulator = @import("build_options").use_simulator;

const hal = microzig.hal;
const Random = if (use_simulator) std.Random else hal.rand;

pub const num_patterns = blk: {
    @setEvalBranchQuota(15_000);

    const raw_digits: [10][15]bool = .{
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
                        scaled_digits[num][x * 3 + y * 27 + x2 + y2 * 9] = raw_digits[num][x + y * 3];
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

    const x1: comptime_int = @ceil(@as(comptime_float, @floatFromInt((amoled.REAL_WIDTH / 8) * 1)) / 5.0);
    const x2: comptime_int = @floor(@as(comptime_float, @floatFromInt((amoled.REAL_WIDTH / 8) * 3)) / 5.0);
    const y1: comptime_int = @ceil(@as(comptime_float, @floatFromInt((amoled.REAL_HEIGHT / 8) * 1)) / 5.0);
    const y2: comptime_int = @floor(@as(comptime_float, @floatFromInt((amoled.REAL_HEIGHT / 8) * 3)) / 5.0);

    const digit_start_points: [4]struct { x: comptime_int, y: comptime_int } = .{
        .{ .x = x1, .y = y1 },
        .{ .x = x2, .y = y1 },
        .{ .x = x1, .y = y2 },
        .{ .x = x2, .y = y2 },
    };

    var digits: [4][10][135]Point = undefined;
    var digits_no_zero: [4][10][135]Point = undefined;

    for (0..4) |point_index| {
        const start_point = digit_start_points[point_index];
        for (0..10) |num| {
            var index = 0;
            var index_no_zero = 0;
            for (0..9) |x| {
                for (0..15) |y| {
                    if (scaled_digits[num][x + y * 9]) {
                        digits[point_index][num][index] = .{ .x = start_point.x + x, .y = start_point.y + y };
                        index += 1;
                        if (num > 0) {
                            digits_no_zero[point_index][num][index] = .{ .x = start_point.x + x, .y = start_point.y + y };
                            index_no_zero += 1;
                        }
                    }
                }
            }
            for (index..135) |blank_index|
                digits[point_index][num][blank_index] = .{ .x = 0, .y = 0 };
            for (index_no_zero..135) |blank_index|
                digits_no_zero[point_index][num][blank_index] = .{ .x = 0, .y = 0 };
        }
    }

    var centers: [8]Point = undefined;
    for (0..4) |point_index| {
        const start_point = digit_start_points[point_index];
        centers[point_index * 2] = .{ .x = start_point.x + 4, .y = start_point.y + 4 };
        centers[point_index * 2 + 1] = .{ .x = start_point.x + 4, .y = start_point.y + 10 };
    }

    var blocked_centers: [4][10][2]Point = undefined;
    var blocked_centers_no_zero: [4][10][2]Point = undefined;

    for (0..4) |point_index| {
        const start_point = digit_start_points[point_index];
        for (0..10) |num| {
            const first = .{ true, false, false, false, false, false, false, false, true, true }[num];
            const second = .{ true, false, false, false, false, false, true, false, true, false }[num];
            const first_no_zero = .{ false, false, false, false, false, false, false, false, true, true }[num];
            const second_no_zero = .{ false, false, false, false, false, false, true, false, true, false }[num];
            if (first and second) {
                if (num == 0) {
                    blocked_centers[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 7 };
                    blocked_centers[point_index][num][1] = .{ .x = 0, .y = 0 };
                } else {
                    blocked_centers[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 4 };
                    blocked_centers[point_index][num][1] = .{ .x = start_point.x + 4, .y = start_point.y + 10 };
                }
            } else if (first) {
                blocked_centers[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 4 };
                blocked_centers[point_index][num][1] = .{ .x = 0, .y = 0 };
            } else if (second) {
                blocked_centers[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 10 };
                blocked_centers[point_index][num][1] = .{ .x = 0, .y = 0 };
            } else {
                blocked_centers[point_index][num][0] = .{ .x = 0, .y = 0 };
                blocked_centers[point_index][num][1] = .{ .x = 0, .y = 0 };
            }
            if (first_no_zero and second_no_zero) {
                blocked_centers_no_zero[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 4 };
                blocked_centers_no_zero[point_index][num][1] = .{ .x = start_point.x + 4, .y = start_point.y + 10 };
            } else if (first_no_zero) {
                blocked_centers_no_zero[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 4 };
                blocked_centers_no_zero[point_index][num][1] = .{ .x = 0, .y = 0 };
            } else if (second_no_zero) {
                blocked_centers_no_zero[point_index][num][0] = .{ .x = start_point.x + 4, .y = start_point.y + 10 };
                blocked_centers_no_zero[point_index][num][1] = .{ .x = 0, .y = 0 };
            } else {
                blocked_centers_no_zero[point_index][num][0] = .{ .x = 0, .y = 0 };
                blocked_centers_no_zero[point_index][num][1] = .{ .x = 0, .y = 0 };
            }
        }
    }

    break :blk struct {
        digits: [4][10][135]Point,
        digits_no_zero: [4][10][135]Point,
        centers: [8]Point,
        blocked_centers: [4][10][2]Point,
        blocked_centers_no_zero: [4][10][2]Point,
    }{
        .digits = digits,
        .digits_no_zero = digits_no_zero,
        .centers = centers,
        .blocked_centers = blocked_centers,
        .blocked_centers_no_zero = blocked_centers_no_zero,
    };
};

pub const Point = struct { x: u16, y: u16 };

pub const Time = struct {
    year: u16,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
    millisecond: u10,
};

pub const ScreenApi = struct {
    time: Time,
    alloc: std.mem.Allocator,
    random: std.Random,
};

pub const Screen = struct {
    init: *const fn (ScreenApi) anyerror!void,
    deinit: *const fn (ScreenApi) anyerror!void,
    update: *const fn (ScreenApi) anyerror!void,
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
        .millisecond = @intCast(ms % 1000),
    };
}

pub fn sleep(time: u32) void {
    if (use_simulator) {
        std.Thread.sleep(time * 1_000_000);
    } else hal.time.sleep_ms(time);
}

var open_screen: ?Screen = null;

pub fn setScreen(screen: Screen, screen_api: ScreenApi) !void {
    if (open_screen) |last| {
        try last.deinit(screen_api);
    }
    open_screen = screen;
    try screen.init(screen_api);
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

    try setScreen(circles_screen, .{
        .alloc = alloc,
        .random = random,
        .time = getCurrentTime(),
    });

    var i: u64 = 0;
    const target_fps = 30;
    const target_delta: u64 = 1_000_000 / target_fps;
    var last_start: u64 = 0;
    while (i < 400_000 or !use_simulator) : (i += 1) {
        last_start = if (use_simulator) @intCast(profiler.getNow()) else profiler.getNow().to_us();
        usb.poll();

        const time = getCurrentTime();

        if (open_screen) |screen| {
            try screen.update(.{
                .alloc = alloc,
                .random = random,
                .time = time,
            });
        }

        if (i % 10 == 0)
            profiler.log(i + 1);

        const now: u64 = if (use_simulator) @intCast(profiler.getNow()) else profiler.getNow().to_us();
        const delta = now - last_start;
        const delay = if (delta < target_delta) (target_delta - delta) / 1_000 else 0;
        usb.log("i: {}, delta: {}, target_delta: {}, delay: {}ms", .{ i, delta, target_delta, delay });
        if (delay > 0)
            sleep(@intCast(delay));
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
