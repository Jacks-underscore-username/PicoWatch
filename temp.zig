const std = @import("std");
const amoled = @import("src/amoled.zig");
const math = std.math;

pub fn main() !void {
    var image: [amoled.PIXEL_COUNT]u16 = undefined;
    amoled.fill(&image, amoled.BLACK);
    amoled.rect(&image, 0, 0, 50, 50, amoled.BLUE);
    amoled.circle(&image, 100, 100, 10, amoled.GREEN);
}
