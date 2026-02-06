const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");
const types = @import("types.zig");
const use_simulator = @import("build_options").use_simulator;

const Item = struct {
    key: []const u8,
    start_time: if (use_simulator) i64 else microzig.drivers.time.Absolute,
};

var total_times: std.StringHashMap(u64) = undefined;
var stack: std.ArrayList(Item) = .empty;

var allocator: std.mem.Allocator = undefined;

const ENABLED = false;

pub fn init(alloc: std.mem.Allocator) void {
    if (!ENABLED) return;
    allocator = alloc;
    total_times = .init(alloc);
}

pub fn deinit() void {
    if (!ENABLED) return;
    total_times.deinit();
    stack.clearAndFree(allocator);
}

pub inline fn getNow() if (use_simulator) i64 else microzig.drivers.time.Absolute {
    return if (use_simulator) std.time.microTimestamp() else microzig.hal.time.get_time_since_boot();
}

pub fn enter(comptime func_name: []const u8) void {
    if (!ENABLED) return;
    const now = getNow();
    stack.append(allocator, .{
        .key = func_name,
        .start_time = now,
    }) catch {
        unreachable;
    };
}

pub fn exit() void {
    if (!ENABLED) return;
    const item = stack.pop().?;
    const start_time = item.start_time;
    const now = getNow();
    const diff: u64 = if (use_simulator) @intCast(now - start_time) else now.diff(start_time).to_us();
    const old_total = total_times.get(item.key);
    if (old_total) |old| {
        total_times.put(item.key, old + diff) catch {
            unreachable;
        };
    } else {
        total_times.put(item.key, diff) catch {
            unreachable;
        };
    }
}

pub fn log(scale: u64) void {
    if (!ENABLED) return;
    var total_time: f64 = 0;
    var entries: std.ArrayList(std.StringHashMap(u64).Entry) = .empty;
    defer entries.deinit(allocator);
    var iterator = total_times.iterator();
    while (iterator.next()) |entry| {
        total_time += @as(f64, @floatFromInt(entry.value_ptr.*));
        entries.append(allocator, entry) catch {
            unreachable;
        };
    }
    std.mem.sort(std.StringHashMap(u64).Entry, entries.items, {}, comptime struct {
        fn f(T: @TypeOf({}), a: std.StringHashMap(u64).Entry, b: std.StringHashMap(u64).Entry) bool {
            _ = T;
            return a.value_ptr.* < b.value_ptr.*;
        }
    }.f);
    usb.log("", .{});
    for (entries.items) |entry| {
        const percent: f64 = @as(f64, @floatFromInt(entry.value_ptr.* * 100)) / total_time;
        const scaled_time: f64 = @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(scale));
        usb.log("\"{s}\" took {d:.2}% or {d:.0}US", .{ entry.key_ptr.*, percent, scaled_time });
    }
}
