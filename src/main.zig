const std = @import("std");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const amoled = @import("amoled.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;

pub fn main() !void {
    usb.init();
    while (!usb.ready()) usb.poll();

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
    time.sleep_ms(500);
    amoled.circle(&image, 100, 100, 10, amoled.GREEN);
    amoled.writeImage(&image);
    // time.sleep_ms(500);

    while (true)
        usb.poll();
}
