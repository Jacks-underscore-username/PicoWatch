const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("../usb.zig");
const amoled = @import("../amoled.zig");
const types = @import("../types.zig");
const profiler = @import("../profiler.zig");
const use_simulator = @import("build_options").use_simulator;

const PULSE_STEPS = 100;

inline fn scale(value: f32, comptime min: u16, comptime max: u16) u16 {
    return @intFromFloat(value * (max - min) + min);
}

inline fn constrain(value: anytype, min: @TypeOf(value), max: @TypeOf(value)) @TypeOf(value) {
    return @min(max, @max(min, value));
}

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

pub fn deinit(alloc: std.mem.Allocator) void {
    for (cells.items) |cell|
        alloc.destroy(cell);
    cells.deinit(alloc);
}

var pulse_offset: u16 = 0;

pub fn update(alloc: std.mem.Allocator, random: std.Random) !void {
    profiler.enter("veins.update");
    defer profiler.exit();

    const image = try alloc.create([amoled.PIXEL_COUNT]amoled.ColorSize);
    defer alloc.destroy(image);
    amoled.fill(image, @intFromEnum(amoled.Colors.Black));

    ticks_since_grow += 1;

    pulse_offset = @mod(pulse_offset + 1, PULSE_STEPS);

    var cells_to_remove: std.ArrayList(u16) = .empty;
    defer cells_to_remove.deinit(alloc);

    const start_len = cells.items.len;
    for (0..start_len) |cell_index| {
        var cell = cells.items[cell_index];
        const cell_x = cell.x;
        const cell_y = cell.y;
        const pulse = pulse_values[
            @intCast(@mod(PULSE_STEPS + pulse_offset -
                cell.offset * 100 / PULSE_STEPS, PULSE_STEPS))
        ];
        var render_pulse = pulse;
        if (cell.is_alive)
            render_pulse = 1;

        const hue: u8 = cell.hue;
        const saturation: u8 = @intCast(scale(render_pulse, 64, 255));
        const vibrance: u8 = @intFromFloat(@as(f32, @floatFromInt(cell.brightness)) / ((1 - (pulse + render_pulse) / 2) * 2 + 1));

        amoled.pixel(image, cell_x, cell_y, amoled.packRgb(amoled.hsvToRgb(hue, saturation, vibrance)));

        if (cell.is_alive) {
            if (random.float(f32) <= pulse and random.intRangeAtMost(u8, 0, 10) == 0) {
                var directions: [4]u2 = .{ 0, 1, 2, 3 };
                random.shuffle(u2, &directions);
                var has_grown = false;
                for (directions) |direction| {
                    if (has_grown) break;

                    const new_x, const new_y, const moved = amoled.pixelOffset(cell_x, cell_y, @enumFromInt(direction));
                    if (!moved) continue;

                    var is_valid = true;

                    for (cells.items) |sub_cell| {
                        if (sub_cell.x == new_x and sub_cell.y == new_y) {
                            is_valid = false;
                            break;
                        }
                    }

                    var check_x = if (new_x == 0) 0 else new_x - 1;
                    while (check_x <= new_x + 1 and is_valid and check_x < amoled.WIDTH) : (check_x += 1) {
                        var check_y = if (new_y == 0) 0 else new_y - 1;
                        while (check_y <= new_y + 1 and is_valid and check_y < amoled.HEIGHT) : (check_y += 1) {
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
                        if (random.boolean())
                            cell.is_alive = false;

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
        } else if (random.intRangeAtMost(u4, 0, 10) == 0 and ticks_since_grow > 250) {
            if (cell.brightness >= 10) {
                cell.brightness -= 10;
            } else {
                cell.brightness = 0;
            }
            if (cell.brightness == 0)
                try cells_to_remove.append(alloc, @intCast(cell_index));
        }
    }

    while (cells_to_remove.pop()) |index| {
        const removed = cells.orderedRemove(index);
        alloc.destroy(removed);
    }

    if (cells.items.len == 0) {
        const cell = try alloc.create(Cell);
        cell.x = random.intRangeAtMost(u16, 0, amoled.WIDTH - 1);
        cell.y = random.intRangeAtMost(u16, 0, amoled.HEIGHT - 1);
        cell.brightness = 255;
        cell.distance = 0;
        cell.hue = random.intRangeAtMost(u8, 0, 255);
        cell.is_alive = true;
        cell.offset = 0;
        try cells.append(alloc, cell);
    }

    try amoled.writeImage(alloc, image);
}
