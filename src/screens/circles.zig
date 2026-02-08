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

const hour_radius = 2 * amoled.REAL_WIDTH / 7;
const minute_radius = amoled.REAL_WIDTH / 7;
const second_radius = amoled.REAL_WIDTH / 14;

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
    // _ = screen_api;

    var image = amoled.Image_1.create();
    image.fill(@intFromEnum(amoled.Colors.Black));

    const hue: u8 = @intCast(@as(u20, @intCast(time.millisecond)) * 256 / 1000);
    const hue_2: u8 = @intCast(@mod(@as(u20, @intCast(time.millisecond)) * 256 / 1000 + 256 / 2, 256));
    image.circle(image.width / 2, image.height / 2, hour_radius, amoled.packRgb(amoled.hsvToRgb(hue, 255, 128)));
    image.circleOutline(image.width / 2, image.height / 2, hour_radius, hour_radius - 10, amoled.packRgb(amoled.hsvToRgb(hue_2, 255, 128)));
    // image.circle(image.width / 2, image.height / 2, hour_radius, @intFromEnum(amoled.Colors.Green));

    // const hour_rad = @as(f32, @floatFromInt(time.hour)) / (12 * math.pi);
    // usb.log("{}", .{hour_rad});

    image.render();
}
