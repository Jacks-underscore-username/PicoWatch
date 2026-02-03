const std = @import("std");
const builtin = @import("builtin");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");
const types = @import("types.zig");
const use_emulator = @import("build_options").use_emulator;

var start_times: std.StringHashMap(if (use_emulator) i64 else microzig.drivers.time.Absolute) = undefined;
var total_times: std.StringHashMap(u64) = undefined;
var stack: std.ArrayList([]const u8) = .empty;

var allocator: std.mem.Allocator = undefined;

const ENABLED = true;

pub fn init(alloc: std.mem.Allocator) void {
    if (!ENABLED) return;
    allocator = alloc;
    start_times = .init(alloc);
    total_times = .init(alloc);
}

pub fn deinit() void {
    if (!ENABLED) return;
    start_times.deinit();
    total_times.deinit();
    stack.clearAndFree(allocator);
}

fn getNow() if (use_emulator) i64 else microzig.drivers.time.Absolute {
    return if (use_emulator) std.time.milliTimestamp() else microzig.hal.time.get_time_since_boot();
}

pub fn enter(comptime func_name: []const u8) void {
    if (!ENABLED) return;
    const now = getNow();
    start_times.put(func_name, now) catch {
        unreachable;
    };
    stack.append(allocator, func_name) catch {
        unreachable;
    };
}

pub fn exit() void {
    if (!ENABLED) return;
    const func_name = stack.pop().?;
    const start_time = start_times.get(func_name).?;
    const now = getNow();
    const diff: u64 = if (use_emulator) @intCast(now - start_time) else now.diff(start_time).to_us();
    const old_total = total_times.get(func_name);
    if (old_total) |old| {
        total_times.put(func_name, old + diff) catch {
            unreachable;
        };
    } else {
        total_times.put(func_name, diff) catch {
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
    usb.log("\r\n", .{});
    for (entries.items) |entry| {
        const percent: f64 = @as(f64, @floatFromInt(entry.value_ptr.* * 100)) / total_time;
        const scaled_time: f64 = @as(f64, @floatFromInt(entry.value_ptr.*)) / @as(f64, @floatFromInt(scale));
        usb.log("\"{s}\" took {d:.2}% or {d:.0}US\r\n", .{ entry.key_ptr.*, percent, scaled_time });
    }
}
