const std = @import("std");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const screen = @import("screen.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;

const arithmetic = @cImport({
    @cInclude("arithmetic.h");
});

pub fn main() !void {
    usb.init();
    screen.init();

    var i: u64 = 0;
    var old: u64 = time.get_time_since_boot().to_us();
    var new: u64 = 0;
    while (true) {
        usb.poll();

        new = time.get_time_since_boot().to_us();
        if (new - old > 1_000_000) {
            old = new;

            i += 1;
            if (usb.ready())
                usb.write("i: {}\r\n", .{i});
        }
    }
}
