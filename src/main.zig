const std = @import("std");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const dma = rp2xxx.dma;
const Pio = rp2xxx.pio.Pio;

const qspi = &amoled.qspi;

pub fn main() !void {
    usb.init();
    while (!usb.ready()) usb.poll();

    // var log_i: u64 = 0;
    // var old: u64 = time.get_time_since_boot().to_us();
    // var new: u64 = 0;
    // while (log_i < 2) {
    //     usb.poll();
    //     new = time.get_time_since_boot().to_us();
    //     if (new - old > 1_000_000) {
    //         old = new;
    //         log_i += 1;
    //         usb.log("i: {}\r\n", .{log_i});
    //     }
    // }

    try amoled.init();

    amoled.fillColor(amoled.RED);
    time.sleep_ms(500);
    amoled.fillColor(amoled.GREEN);
    time.sleep_ms(500);
    amoled.fillColor(amoled.BLUE);

    time.sleep_ms(1_000);

    amoled.fillColor(amoled.WHITE);

    time.sleep_ms(1_000);

    var image: [amoled.PIXEL_COUNT]u16 = undefined;
    amoled.writeImage(&image);
    time.sleep_ms(500);
    amoled.fill(&image, amoled.BLACK);
    amoled.writeImage(&image);
    time.sleep_ms(500);
    amoled.rect(&image, 0, 0, 50, 50, amoled.BLUE);
    amoled.writeImage(&image);
    // time.sleep_ms(500);
    // amoled.circle(&image, 100, 100, 10, amoled.GREEN);
    // amoled.writeImage(&image);
    // time.sleep_ms(500);

    while (true)
        usb.poll();
}
