const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("../usb.zig");
const amoled = @import("../amoled.zig");
const types = @import("../types.zig");
const profiler = @import("../profiler.zig");
const main = @import("../main.zig");
const use_simulator = @import("build_options").use_simulator;

const PULSE_STEPS = 100;

const Cell = struct {
    x: u16,
    y: u16,
    hue: u8,
    brightness: u8,
    is_alive: bool,
    distance: u16,
    offset: u16,
};

var cells: std.ArrayList(*Cell) = .empty;
const pulse_values: [PULSE_STEPS]f32 = blk: {
    var values: [PULSE_STEPS]f32 = undefined;
    for (0..PULSE_STEPS) |i|
        values[i] = @max(0, @min(1, @sin(@as(comptime_float, i) * std.math.pi * 2 / @as(comptime_float, @floatFromInt(PULSE_STEPS))) * 2 - 1));

    break :blk values;
};

var ticks_since_grow: u64 = 0;
var sub_pulse_offset: u4 = 0;
var pulse_offset: u16 = 0;

var has_started = false;

pub const screen: main.Screen = .{
    .init = &init,
    .deinit = &deinit,
    .update = &update,
};

fn init(screen_api: main.ScreenApi) !void {
    _ = screen_api;
    has_started = false;
}

fn deinit(screen_api: main.ScreenApi) !void {
    for (cells.items) |cell|
        screen_api.alloc.destroy(cell);
    cells.deinit(screen_api.alloc);
}

fn update(screen_api: main.ScreenApi) !void {
    profiler.enter("veins.update");
    defer profiler.exit();

    const alloc = screen_api.alloc;
    const random = screen_api.random;
    const time = screen_api.time;

    var image = amoled.Image_8.create();

    var blocked_points: [135 * 4]main.Point = undefined;

    @memcpy(blocked_points[135 * 0 .. 135 * 1], &main.num_patterns.digits[0][(if (time.hour > 12) time.hour - 12 else time.hour) / 10]);
    @memcpy(blocked_points[135 * 1 .. 135 * 2], &main.num_patterns.digits[1][(if (time.hour > 12) time.hour - 12 else time.hour) % 10]);
    @memcpy(blocked_points[135 * 2 .. 135 * 3], &main.num_patterns.digits[2][time.minute / 10]);
    @memcpy(blocked_points[135 * 3 .. 135 * 4], &main.num_patterns.digits[3][time.minute % 10]);

    image.fill(@intFromEnum(amoled.Colors.Black));

    ticks_since_grow += 1;

    sub_pulse_offset = @mod(sub_pulse_offset + 1, 2);
    if (sub_pulse_offset == 0)
        pulse_offset = @mod(pulse_offset + 1, PULSE_STEPS);

    var cells_to_remove: std.ArrayList(u16) = .empty;
    defer cells_to_remove.deinit(alloc);

    const start_len = cells.items.len;
    for (0..start_len) |cell_index| {
        var cell = cells.items[cell_index];
        const cell_x = cell.x;
        const cell_y = cell.y;
        const pulse = pulse_values[
            @intCast(@mod(PULSE_STEPS * 10 + pulse_offset -
                cell.offset * (200 / PULSE_STEPS), PULSE_STEPS))
        ];
        var render_pulse = pulse;
        if (cell.is_alive)
            render_pulse = 1;

        const hue: u8 = cell.hue;
        const saturation: u8 = @intFromFloat(render_pulse * (255 - 128) + 128);
        const vibrance: u8 = @intFromFloat(@as(f32, @floatFromInt(cell.brightness)) / ((1 - (pulse + render_pulse) / 2) * 2 + 1));

        image.pixel(cell_x, cell_y, amoled.packRgb(amoled.hsvToRgb(hue, saturation, vibrance)));

        if (cell.is_alive) {
            if (random.float(f32) <= pulse and random.intRangeLessThan(u5, 0, 10) == 0 and time.second < 55) {
                var directions: [4]u2 = .{ 0, 1, 2, 3 };
                random.shuffle(u2, &directions);
                var has_grown = false;
                for (directions) |direction| {
                    if (has_grown) break;

                    const new_x, const new_y, const moved = image.pixelOffset(cell_x, cell_y, @enumFromInt(direction));
                    if (!moved) continue;

                    var is_valid = true;

                    for (blocked_points) |blocked_point| {
                        if (blocked_point.x == new_x and blocked_point.y == new_y) {
                            is_valid = false;
                            break;
                        }
                    }

                    for (cells.items) |sub_cell| {
                        if (sub_cell.x == new_x and sub_cell.y == new_y) {
                            is_valid = false;
                            break;
                        }
                    }

                    var check_x = if (new_x == 0) 0 else new_x - 1;
                    while (check_x <= new_x + 1 and is_valid and check_x < image.width) : (check_x += 1) {
                        var check_y = if (new_y == 0) 0 else new_y - 1;
                        while (check_y <= new_y + 1 and is_valid and check_y < image.height) : (check_y += 1) {
                            if (check_x == cell_x and check_y == cell_y)
                                continue;

                            var sub_cell_index: u16 = 0;
                            while (sub_cell_index < cells.items.len and is_valid) : (sub_cell_index += 1) {
                                const sub_cell = cells.items[sub_cell_index];
                                if (sub_cell.x == check_x and sub_cell.y == check_y and amoled.difference(u16, cell.distance, sub_cell.distance) != 1) is_valid = false;
                            }
                        }
                    }

                    if (is_valid) {
                        has_grown = true;
                        ticks_since_grow = 0;

                        const new_cell = try alloc.create(Cell);
                        new_cell.x = new_x;
                        new_cell.y = new_y;
                        new_cell.hue = @intCast(@mod(255 + @as(u16, @intCast(cell.hue)) + random.intRangeAtMost(u16, 0, 16) - 8, 256));
                        new_cell.brightness = if (cell.brightness >= 1) cell.brightness - 1 else 0;
                        new_cell.is_alive = true;
                        new_cell.distance = cell.distance + 1;
                        new_cell.offset = @mod(cell.offset + random.intRangeAtMost(u2, 0, 3), PULSE_STEPS);
                        try cells.append(alloc, new_cell);
                    } else cell.is_alive = false;
                }
            }
        } else if (random.intRangeLessThan(u4, 0, 5) == 0 and time.second > 50) {
            if (cell.brightness >= 10) {
                cell.brightness -= 10;
            } else {
                cell.brightness = 0;
            }
        }
        if (cell.brightness == 0 or time.second == 59)
            try cells_to_remove.append(alloc, @intCast(cell_index));
    }

    while (cells_to_remove.pop()) |index| {
        const removed = cells.orderedRemove(index);
        alloc.destroy(removed);
    }

    if (cells.items.len == 0 and (time.second < 5 or !has_started)) {
        has_started = true;
        var hue: u9 = random.intRangeAtMost(u8, 0, 255);
        var start_points: [8]main.Point = undefined;

        @memcpy(start_points[2 * 0 .. 2 * 1], &main.num_patterns.blocked_centers[0][(if (time.hour > 12) time.hour - 12 else time.hour) / 10]);
        @memcpy(start_points[2 * 1 .. 2 * 2], &main.num_patterns.blocked_centers[1][(if (time.hour > 12) time.hour - 12 else time.hour) % 10]);
        @memcpy(start_points[2 * 2 .. 2 * 3], &main.num_patterns.blocked_centers[2][time.minute / 10]);
        @memcpy(start_points[2 * 3 .. 2 * 4], &main.num_patterns.blocked_centers[3][time.minute % 10]);

        var point_count: u9 = 1;
        for (start_points) |point| {
            if (point.x != 0 or point.y != 0) point_count += 1;
        }

        random.shuffle(main.Point, &start_points);
        for (start_points) |point| {
            if (point.x == 0 and point.y == 0) continue;
            const cell = try alloc.create(Cell);
            cell.x = point.x;
            cell.y = point.y;
            cell.brightness = 255;
            cell.distance = 0;
            cell.hue = @intCast(hue);
            cell.is_alive = true;
            cell.offset = 0;
            try cells.append(alloc, cell);
            hue = @mod(hue + 256 / point_count, 256);
        }

        const cell = try alloc.create(Cell);
        cell.x = image.width / 2;
        cell.y = image.height / 2;
        cell.brightness = 255;
        cell.distance = 0;
        cell.hue = @intCast(hue);
        cell.is_alive = true;
        cell.offset = 0;
        try cells.append(alloc, cell);
    }

    image.render();
}
