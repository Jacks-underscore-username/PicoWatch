const std = @import("std");
const math = std.math;
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("../usb.zig");
const amoled = @import("../amoled.zig");
const types = @import("../types.zig");
const profiler = @import("../profiler.zig");
const main = @import("../main.zig");
const use_simulator = @import("build_options").use_simulator;

// const hour_radius = 2 * (amoled.REAL_WIDTH - 20) / 7;
// const minute_radius = (amoled.REAL_WIDTH - 20) / 7;
// const second_radius = (amoled.REAL_WIDTH - 20) / 14;

const t = 0.25;

const hour_radius: comptime_int = @intFromFloat((amoled.REAL_WIDTH - 20) / 6 * (1 + t));
const minute_radius: comptime_int = @intFromFloat((amoled.REAL_WIDTH - 20) / 6 * (1));
const second_radius: comptime_int = @intFromFloat((amoled.REAL_WIDTH - 20) / 6 * (1 - t));

comptime {
    if ((hour_radius + minute_radius + second_radius) * 2 > amoled.REAL_WIDTH) @compileError("Uh oh");
}

// const hour_radius = (amoled.REAL_WIDTH - 20) / 14;
// const minute_radius = (amoled.REAL_WIDTH - 20) / 7;
// const second_radius = 2 * (amoled.REAL_WIDTH - 20) / 7;

const color_steps = blk: {
    var results: [100]u8 = undefined;
    for (0..results.len) |i| {
        const rads = math.pi * 2 * @as(comptime_float, @floatFromInt(i)) / @as(comptime_float, @floatFromInt(results.len));
        results[i] = @intFromFloat(@max(@sin(rads) * 255, 0));
    }
    break :blk results;
};

pub const screen: main.Screen = .{
    .init = &init,
    .deinit = &deinit,
    .update = &update,
};

fn init(screen_api: main.ScreenApi) !void {
    _ = screen_api;
}

fn deinit(screen_api: main.ScreenApi) !void {
    _ = screen_api;
}

fn update(screen_api: main.ScreenApi) !void {
    profiler.enter("circles.update");
    defer profiler.exit();

    // const alloc = screen_api.alloc;
    // const random = screen_api.random;
    const time = screen_api.time;
    const full_time: f32 = @floatFromInt(@as(u64, @intCast(time.millisecond)) + @as(u64, @intCast(time.second)) * 1_000 + @as(u64, @intCast(time.minute)) * 1_000 * 60 + @as(u64, @intCast(time.hour)) * 1_000 * 60 * 60);

    var image = amoled.Image_1.create();
    image.fill(@intFromEnum(amoled.Colors.Black));

    const second_scale = full_time / 1_000.0;
    const minute_scale = second_scale / 60.0;
    const hour_scale = minute_scale / 60.0;
    const second: f32 = @mod(second_scale, 60);
    const minute: f32 = @mod(minute_scale, 60);
    const hour: f32 = @mod(hour_scale, 60);

    const rad_const_offset = math.pi * 1.5;

    const second_t = math.pow(f32, @sin(math.pi * 2 * @as(f32, @floatFromInt(time.millisecond)) / 4_000), 15);
    const minute_t = math.pow(f32, @sin(math.pi * 2 * @mod(@as(f32, @floatFromInt(time.millisecond)) + 1_000 / 3, 1_000) / 4_000), 15);
    const hour_t = math.pow(f32, @sin(math.pi * 2 * @mod(@as(f32, @floatFromInt(time.millisecond)) + 1_000 / 3 * 2, 1_000) / 4_000), 15);

    const second_rad = second / 60 * math.pi * 2 + rad_const_offset + second_t * math.pi * 2;
    const minute_rad = minute / 60 * math.pi * 2 + rad_const_offset + minute_t * math.pi * 2;
    const hour_rad = hour / 12 * math.pi * 2 + rad_const_offset + hour_t * math.pi * 2;

    const hour_x = @cos(hour_rad) * @as(f32, @floatFromInt(hour_radius)) + @as(f32, @floatFromInt(image.width / 2));
    const hour_y = @sin(hour_rad) * @as(f32, @floatFromInt(hour_radius)) + @as(f32, @floatFromInt(image.height / 2));
    const minute_x = @cos(minute_rad) * @as(f32, @floatFromInt(minute_radius)) + hour_x;
    const minute_y = @sin(minute_rad) * @as(f32, @floatFromInt(minute_radius)) + hour_y;
    const second_x = @cos(second_rad) * @as(f32, @floatFromInt(second_radius)) + minute_x;
    const second_y = @sin(second_rad) * @as(f32, @floatFromInt(second_radius)) + minute_y;

    const marks: [3]struct { x: u16, y: u16, scale: u8, hue: u8, rads: f32 } = .{
        .{
            .x = image.width / 2,
            .y = image.height / 2,
            .scale = hour_radius,
            .hue = 0,
            .rads = hour_rad,
        },
        .{
            .x = @intFromFloat(hour_x),
            .y = @intFromFloat(hour_y),
            .scale = minute_radius,
            .hue = 256 / 3,
            .rads = minute_rad,
        },
        .{
            .x = @intFromFloat(minute_x),
            .y = @intFromFloat(minute_y),
            .scale = second_radius,
            .hue = 256 / 3 * 2,
            .rads = second_rad,
        },
    };

    for (marks) |mark| {
        for (main.dial_rotations) |rot| {
            const color_index: u8 = @intFromFloat(@mod((rot.rads + mark.rads) * color_steps.len / math.pi / 2, color_steps.len));
            const vibrance = color_steps[color_index];
            if (vibrance > 0) {
                const color = amoled.hsvToRgb(mark.hue, if (rot.is_hour) 255 else 128, vibrance);
                const scale: u8 = if (rot.is_hour) mark.scale else mark.scale + 10;
                const x = rot.x * (@as(f16, @floatFromInt(scale))) + @as(f16, @floatFromInt(mark.x));
                const y = rot.y * (@as(f16, @floatFromInt(scale))) + @as(f16, @floatFromInt(mark.y));
                image.circle(@intFromFloat(x), @intFromFloat(y), if (rot.is_hour) 4 else 1, amoled.packRgb(color));
            }
        }
    }

    image.circle(@intFromFloat(hour_x), @intFromFloat(hour_y), 5, @intFromEnum(amoled.Colors.White));
    image.circle(@intFromFloat(minute_x), @intFromFloat(minute_y), 5, @intFromEnum(amoled.Colors.White));
    image.circle(@intFromFloat(second_x), @intFromFloat(second_y), 5, @intFromEnum(amoled.Colors.White));

    image.render();
}
