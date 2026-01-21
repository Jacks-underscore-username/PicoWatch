const std = @import("std");

// const arithmetic = @cImport({
//     @cInclude("arithmetic.c");
// });

fn add(x: i32, y: i32) i32 {
    // return arithmetic.add(x, y);
    return x + y;
}

pub fn main() !void {
    const x: i32 = 5;
    const y: i32 = 16;
    const z: i32 = add(x, y);

    std.debug.print("{d} + {d} = {d}.\n", .{ x, y, z });
}
