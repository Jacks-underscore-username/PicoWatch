const std = @import("std");
const microzig = @import("microzig");
const sdl3 = @import("sdl3");
const usb = @import("usb.zig");
const main = @import("main.zig");
const profiler = @import("profiler.zig");
const types = @import("types.zig");
const use_simulator = @import("build_options").use_simulator;

const math = std.math;
const mem = std.mem;
const hal = microzig.hal;
const time = hal.time;
const dma = hal.dma;
const gpio = hal.gpio;
const Pin = gpio.Pin;
const Pio = hal.pio.Pio;
const StateMachine = hal.pio.StateMachine;

const fourWireDataWrapTarget = 0;
const fourWireDataWrap = 1;
const fourWireDataPioVersion = 0;

pub const REAL_WIDTH = 368;
pub const REAL_HEIGHT = 448;
pub const REAL_PIXEL_COUNT = REAL_WIDTH * REAL_HEIGHT;
pub const SCALE = 8;

comptime {
    if (REAL_WIDTH % SCALE != 0 or REAL_HEIGHT % SCALE != 0)
        @compileError("Screen width / height must be divisible by scale.");
}

pub const WIDTH = REAL_WIDTH / SCALE;
pub const HEIGHT = REAL_HEIGHT / SCALE;
pub const PIXEL_COUNT = WIDTH * HEIGHT;

pub const AXIS = enum(@TypeOf(@max(WIDTH, HEIGHT))) {
    X = WIDTH,
    Y = HEIGHT,
};

pub const DIRECTION = enum(u4) {
    up,
    right,
    down,
    left,
};

pub const ColorSize = if (true) u16 else u24;

pub const Colors = enum(u16) {
    White = 0xFFFF,
    Black = 0x0000,
    Blue = 0x001F,
    Gblue = 0x07FF,
    Red = 0xF800,
    Magenta = 0xF81F,
    Green = 0x07E0,
    Cyan = 0x7FFF,
    Yellow = 0xFFE0,
    Brown = 0xBC40,
    Brred = 0xFC07,
    Gray = 0x8430,
    Darkblue = 0x01CF,
    Lightblue = 0x7D7C,
    Grayblue = 0x5458,
    Lightgreen = 0x841F,
    Lgray = 0xC618,
    Lgrayblue = 0xA651,
    Lbblue = 0x2B12,
};

pub const Colors2 = enum(u24) {
    White = 0xFFFFFF,
    Grey = 0x666666,
    Black = 0x000000,
    Red = 0xFF0000,
    Yellow = 0xFFFF00,
    Green = 0x00FF00,
    Cyan = 0x00FFFF,
    Blue = 0x0000FF,
    Purple = 0xFF00FF,
};

const AmoledConfig = struct {
    pio: Pio,
    sm: StateMachine,
    sm_4_wire: StateMachine,
    sm_1_wire: StateMachine,
    pin_cs: Pin,
    pin_sclk: Pin,
    pin_dio0: Pin,
    pin_dio1: Pin,
    pin_dio2: Pin,
    pin_dio3: Pin,
    pin_pwr_en: Pin,
    pin_rst: Pin,
};

const config: AmoledConfig = .{
    .pio = .pio0,
    .sm = StateMachine.sm0,
    .sm_4_wire = StateMachine.sm0,
    .sm_1_wire = StateMachine.sm1,
    .pin_cs = gpio.num(9),
    .pin_sclk = gpio.num(10),
    .pin_dio0 = gpio.num(11),
    .pin_dio1 = gpio.num(12),
    .pin_dio2 = gpio.num(13),
    .pin_dio3 = gpio.num(14),
    .pin_pwr_en = gpio.num(17),
    .pin_rst = gpio.num(15),
};

const four_wire_data_program = blk: {
    @setEvalBranchQuota(3000);
    break :blk hal.pio.assemble(
        \\.program qspi4wireData
        \\.side_set 1 opt
        \\.wrap_target
        \\    out pins, 4        side 0
        \\    nop                side 1
        \\.wrap
    , .{}).get_program_by_name("qspi4wireData");
};

const one_wire_cmd_program = blk: {
    @setEvalBranchQuota(3000);
    break :blk hal.pio.assemble(
        \\.program qspi1writeCmd
        \\.side_set 1 opt
        \\.wrap_target
        \\    out pins, 1        side 0
        \\    nop                side 1
        \\.wrap
    , .{}).get_program_by_name("qspi1writeCmd");
};

pub const Rgb = struct { r: u8, g: u8, b: u8 };

var window: sdl3.video.Window = undefined;
var renderer: sdl3.render.Renderer = undefined;
const init_flags = sdl3.InitFlags{ .video = true };

var dma_tx: dma.Channel = undefined;
const dma_config: dma.Channel.TransferConfig = .{
    .data_size = .size_8,
    .dreq = switch (config.pio) {
        .pio0 => switch (config.sm) {
            .sm0 => dma.Dreq.pio0_tx0,
            .sm1 => dma.Dreq.pio0_tx1,
            .sm2 => dma.Dreq.pio0_tx2,
            .sm3 => dma.Dreq.pio0_tx3,
        },
        .pio1 => switch (config.sm) {
            .sm0 => dma.Dreq.pio1_tx0,
            .sm1 => dma.Dreq.pio1_tx1,
            .sm2 => dma.Dreq.pio1_tx2,
            .sm3 => dma.Dreq.pio1_tx3,
        },
        else => unreachable,
    },
    .trigger = true,
    .read_increment = true,
    .write_increment = false,
    .enable = true,
};

fn dataWrite(val: u32) void {
    var cmdBuf: [4]u32 = undefined;

    inline for (0..4) |i| {
        const bit1: u8 = if (val & (1 << (2 * i)) > 0) 1 else 0;
        const bit2: u8 = if (val & (1 << (2 * i + 1)) > 0) 1 else 0;
        cmdBuf[3 - i] = bit1 | (bit2 << 4);
    }

    inline for (0..4) |i|
        config.pio.sm_blocking_write(config.sm, cmdBuf[i] << 24);
}

fn dataWriteCT(comptime val: u32) void {
    const cmdBuf = comptime blk: {
        var cmdBuf: [4]u32 = undefined;
        for (0..4) |i| {
            const bit1 = if (val & (1 << (2 * i)) > 0) 1 else 0;
            const bit2 = if (val & (1 << (2 * i + 1)) > 0) 1 else 0;
            cmdBuf[3 - i] = (bit1 | (bit2 << 4)) << 24;
        }
        break :blk cmdBuf;
    };

    inline for (0..4) |i|
        config.pio.sm_blocking_write(config.sm, cmdBuf[i]);
}

fn registerWrite(comptime addr: u32) void {
    dataWriteCT(0x02);

    dataWriteCT(0x00);
    dataWriteCT(addr);
    dataWriteCT(0x00);
}

fn pixelWrite(comptime addr: u32) void {
    dataWriteCT(0x32);

    dataWriteCT(0x00);
    dataWriteCT(addr);
    dataWriteCT(0x00);
}

inline fn select() void {
    config.pin_cs.put(0);
}

inline fn deselect() void {
    // Without this line builds in release mode don't write to the display.
    time.sleep_us(0);
    config.pin_cs.put(1);
}

fn initPio() !void {
    config.pin_cs.set_function(.sio);
    config.pin_cs.set_pull(.down);
    config.pin_cs.set_direction(.out);
    deselect();

    config.pin_pwr_en.set_function(.sio);
    config.pin_pwr_en.set_direction(.out);
    config.pin_pwr_en.put(1);

    config.pin_rst.set_function(.sio);
    config.pin_rst.set_direction(.out);

    const offset = try Pio.add_program(config.pio, four_wire_data_program);

    const pio_config: hal.pio.StateMachineInitOptions = .{
        .exec = .{
            .wrap_target = offset + fourWireDataWrapTarget,
            .wrap = offset + fourWireDataWrap,
            .side_set_optional = true,
            .side_pindir = false,
        },
        .pin_mappings = .{
            .side_set = .single(
                config.pin_sclk,
            ),
            .out = .{
                .low = config.pin_dio0,
                .high = @enumFromInt(@intFromEnum(config.pin_dio0) + 3),
            },
        },
        .shift = .{
            .out_shiftdir = .left,
            .autopull = true,
            .pull_threshold = 8,
        },
        .clkdiv = .{
            .int = 1,
        },
    };

    config.pio.gpio_init(config.pin_sclk);
    try config.pio.sm_set_pindir(config.sm_4_wire, config.pin_sclk, 1, .out);

    inline for (0..4) |pin_offset|
        config.pio.gpio_init(@enumFromInt(@intFromEnum(config.pin_dio0) + pin_offset));

    try config.pio.sm_set_pindir(config.sm_4_wire, config.pin_dio0, 4, .out);

    try config.pio.sm_init(config.sm_4_wire, offset, pio_config);
    config.pio.sm_clear_fifos(config.sm_4_wire);
    config.pio.sm_set_enabled(config.sm_4_wire, true);

    config.pio.sm_set_enabled(config.sm_4_wire, false);
    config.pio.sm_set_enabled(config.sm_1_wire, false);

    config.pio.sm_set_enabled(config.sm_4_wire, true);
    config.pio.sm_set_enabled(config.sm_1_wire, false);
}

fn initRegisters() void {
    select();
    registerWrite(0x11);
    time.sleep_ms(120);
    deselect();

    select();
    registerWrite(0x44);
    dataWriteCT(0x01);
    dataWriteCT(0xC5);
    deselect();

    select();
    registerWrite(0x35);
    dataWriteCT(0x00);
    deselect();

    select();
    registerWrite(0x3A);
    dataWriteCT(if (ColorSize == u16) 0x55 else 0x66);
    deselect();

    select();
    registerWrite(0xC4);
    dataWriteCT(0x80);
    deselect();

    select();
    registerWrite(0x53);
    dataWriteCT(0x20);
    deselect();

    select();
    registerWrite(0x51);
    dataWriteCT(0xFF);
    deselect();

    select();
    registerWrite(0x29);
    deselect();

    time.sleep_ms(10);
}

fn reset() void {
    config.pin_rst.put(1);
    time.sleep_ms(50);
    config.pin_rst.put(0);
    time.sleep_ms(50);
    config.pin_rst.put(1);
    time.sleep_ms(300);
}

fn handleSigInt(sig_num: c_int) callconv(.c) void {
    _ = sig_num;
    deinit();
    std.posix.exit(1);
}

pub fn init() !void {
    if (use_simulator) {
        try sdl3.init(init_flags);
        window, renderer = try sdl3.render.Renderer.initWithWindow("PicoWatch screen simulator [OPAQUE]", REAL_WIDTH, REAL_HEIGHT, .{});

        const action = std.posix.Sigaction{
            .handler = .{ .handler = handleSigInt },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };

        std.posix.sigaction(std.posix.SIG.INT, &action, null);

        return;
    }

    try initPio();

    reset();

    initRegisters();

    setWindowSize(0, 0, WIDTH, HEIGHT);

    dma_tx = dma.claim_unused_channel().?;
}

pub fn deinit() void {
    if (!use_simulator) return;
    window.deinit();
    sdl3.quit(init_flags);
    sdl3.shutdown();
}

pub fn setBrightness(brightness: u8) void {
    if (use_simulator) return;

    select();
    registerWrite(0x51);
    dataWrite(brightness);
    deselect();
}

fn setWindowSize(comptime start_x: u16, comptime start_y: u16, comptime end_x: u16, comptime end_y: u16) void {
    select();
    registerWrite(0x2a);
    dataWriteCT((start_x * SCALE) >> 8);
    dataWriteCT((start_x * SCALE) & 0xff);
    dataWriteCT((end_x * SCALE - 1) >> 8);
    dataWriteCT((end_x * SCALE - 1) & 0xff);
    deselect();

    select();
    registerWrite(0x2b);
    dataWriteCT((start_y * SCALE) >> 8);
    dataWriteCT((start_y * SCALE) & 0xff);
    dataWriteCT((end_y * SCALE - 1) >> 8);
    dataWriteCT((end_y * SCALE - 1) & 0xff);
    deselect();

    select();
    registerWrite(0x2c);
    deselect();
}

pub fn writeImage(alloc: std.mem.Allocator, image: *[PIXEL_COUNT]ColorSize) !void {
    profiler.enter("writeImage");
    defer profiler.exit();

    const real_image = try alloc.create([REAL_PIXEL_COUNT]ColorSize);
    defer alloc.destroy(real_image);
    if (SCALE > 1) {
        for (0..WIDTH) |x| {
            for (0..HEIGHT) |y| {
                for (0..SCALE) |offset| {
                    const slice_start = (x + (y * SCALE + offset) * WIDTH) * SCALE;
                    @memset(real_image[slice_start .. slice_start + SCALE], image.*[x + y * WIDTH]);
                }
            }
        }
    }

    if (use_simulator) {
        const surface = try window.getSurface();

        const texture = try renderer.createTexture(
            surface.getFormat().?,
            sdl3.render.Texture.Access.streaming,
            REAL_WIDTH,
            REAL_HEIGHT,
        );
        defer texture.deinit();

        const lock = try texture.lock(null);
        const pixels_ptr: [*]u8 = lock[0];
        const u32_pixels_ptr: [*]u32 = @ptrCast(@alignCast(pixels_ptr));

        for (0..REAL_PIXEL_COUNT) |i| {
            const color = @byteSwap(if (SCALE == 1) image.*[i] else real_image[i]);
            if (ColorSize == u16) {
                const rgb = unpackRgb(color);
                u32_pixels_ptr[i] = surface.mapRgb(rgb.r, rgb.g, rgb.b).value;
            } else {
                const r = @as(u8, @intCast((color >> 16) & 0xFF));
                const g = @as(u8, @intCast((color >> 8) & 0xFF));
                const b = @as(u8, @intCast(color & 0xFF));
                u32_pixels_ptr[i] = surface.mapRgb(r, g, b).value;
            }
        }

        texture.unlock();

        try renderer.clear();
        try renderer.renderTexture(texture, null, null);
        try renderer.present();

        return;
    }

    select();
    pixelWrite(0x2c);

    dma_tx.setup_transfer_raw(
        @intFromPtr(config.pio.sm_get_tx_fifo(config.sm)),
        @intFromPtr(@as(*volatile [REAL_PIXEL_COUNT]ColorSize, if (SCALE == 1) image else real_image)),
        REAL_PIXEL_COUNT * if (ColorSize == u16) 2 else 3,
        dma_config,
    );

    dma_tx.wait_for_finish_blocking();
    deselect();
}

pub fn packRgb(color: Rgb) ColorSize {
    profiler.enter("packRgb");
    defer profiler.exit();

    if (ColorSize == u16) {
        const r5 = (@as(u16, color.r) * 31 + 127) / 255;
        const g6 = (@as(u16, color.g) * 63 + 127) / 255;
        const b5 = (@as(u16, color.b) * 31 + 127) / 255;
        return (r5 << 11) | (g6 << 5) | b5;
    } else {
        return (@as(u24, color.r) << 16) | (@as(u24, color.g) << 8) | color.b;
    }
}

pub fn unpackRgb(color: ColorSize) Rgb {
    profiler.enter("unpackRgb");
    defer profiler.exit();

    if (ColorSize == u16) {
        const r5 = @as(u16, color >> 11) & 0x1F;
        const g6 = @as(u16, color >> 5) & 0x3F;
        const b5 = @as(u16, color) & 0x1F;

        const r8 = @as(u8, @intCast((r5 * 255 + 15) / 31));
        const g8 = @as(u8, @intCast((g6 * 255 + 31) / 63));
        const b8 = @as(u8, @intCast((b5 * 255 + 15) / 31));

        return .{ .r = r8, .g = g8, .b = b8 };
    } else {
        return .{
            .r = @as(u8, @intCast((color >> 16) & 0xFF)),
            .g = @as(u8, @intCast((color >> 8) & 0xFF)),
            .b = @as(u8, @intCast(color & 0xFF)),
        };
    }
}

pub fn hsvToRgb(h: u8, s: u8, v: u8) Rgb {
    profiler.enter("hsvToRgb");
    defer profiler.exit();

    if (s == 0)
        return .{ .r = v, .g = v, .b = v };

    const region = h / 43;
    const remainder = (h - (region * 43)) * 6;

    const s16: u16 = @intCast(s);
    const v16: u16 = @intCast(v);

    const p: u8 = @intCast((v16 * (255 - s)) >> 8);
    const q: u8 = @intCast((v16 * (255 - ((s16 * remainder) >> 8))) >> 8);
    const t: u8 = @intCast((v16 * (255 - ((s16 * (255 - remainder)) >> 8))) >> 8);

    return switch (region) {
        0 => .{ .r = v, .g = t, .b = p },
        1 => .{ .r = q, .g = v, .b = p },
        2 => .{ .r = p, .g = v, .b = t },
        3 => .{ .r = p, .g = q, .b = v },
        4 => .{ .r = t, .g = p, .b = v },
        else => .{ .r = v, .g = p, .b = q },
    };
}

pub inline fn isInRange(x: u16, y: u16) bool {
    return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT;
}

pub fn addInRange(comptime T: type, axis: AXIS, a: T, b: T) T {
    profiler.enter("addInRange");
    defer profiler.exit();

    if (b > 0) {
        const res: struct { T, u1 } = @addWithOverflow(a, b);
        if (res[1] == 1) return @intFromEnum(axis) - 1;
        return @min(@intFromEnum(axis) - 1, res[0]);
    } else {
        const res: struct { T, u1 } = @subWithOverflow(a, @as(T, @intCast(@abs(b))));
        if (res[1] == 1) return 0;
        return @max(0, res[0]);
    }
}

pub fn pixelOffset(x: u16, y: u16, dir: DIRECTION) struct { u16, u16, bool } {
    profiler.enter("pixelOffset");
    defer profiler.exit();

    return switch (dir) {
        .up => if (y == 0) .{ x, y, false } else .{ x, y - 1, true },
        .right => if (x == WIDTH - 1) .{ x, y, false } else .{ x + 1, y, true },
        .down => if (y == HEIGHT - 1) .{ x, y, false } else .{ x, y + 1, true },
        .left => if (x == 0) .{ x, y, false } else .{ x - 1, y, true },
    };
}

pub inline fn difference(comptime T: type, a: T, b: T) T {
    profiler.enter("difference");
    defer profiler.exit();

    return if (a > b) a - b else b - a;
}

pub inline fn pixel(image: *[PIXEL_COUNT]ColorSize, x: u16, y: u16, color: ColorSize) void {
    profiler.enter("pixel");
    defer profiler.exit();

    image.*[x + @as(u32, y) * WIDTH] = @byteSwap(color);
}

pub inline fn write_slice(image: *[PIXEL_COUNT]ColorSize, x_start: u16, x_end: u16, y: u16, color: ColorSize) void {
    profiler.enter("write_slice");
    defer profiler.exit();

    @memset(image[x_start + @as(u32, y) * WIDTH .. x_end + 1 + @as(u32, y) * WIDTH], @byteSwap(color));
}

pub fn rect(image: *[PIXEL_COUNT]ColorSize, x: u16, y: u16, width: u16, height: u16, color: ColorSize) void {
    profiler.enter("rect");
    defer profiler.exit();

    for (y..y + height) |y2|
        write_slice(image, x, x + width - 1, @intCast(y2), color);
}

pub fn circle(image: *[PIXEL_COUNT]ColorSize, x: u16, y: u16, r: u16, color: ColorSize) void {
    profiler.enter("circle");
    defer profiler.exit();

    const r_squared = math.pow(u16, r, 2);
    const r_neg = -@as(i32, @intCast(r));
    const x_range_min: usize = @intCast(addInRange(i64, .X, x, r_neg));
    const x_range_max: usize = @intCast(addInRange(i64, .X, x, r) + 1);
    const y_range_min: usize = @intCast(addInRange(i64, .Y, y, r_neg));
    const y_range_max: usize = @intCast(addInRange(i64, .Y, y, r) + 1);
    for (y_range_min..y_range_max) |y2| {
        const y_diff = difference(u16, y, @intCast(y2));
        const y_squared = math.pow(u16, y_diff, 2);
        const r_squared_minus_y = r_squared - y_squared;
        var max_x_diff: u16 = 0;
        var x_start: ?usize = null;
        var last_x: usize = 0;
        for (x_range_min..x_range_max) |x2| {
            const x_diff = difference(u16, x, @intCast(x2));
            if (x_diff < max_x_diff) {
                last_x = x2;
                continue;
            }
            const x_squared = math.pow(u16, x_diff, 2);
            if (x_squared <= r_squared_minus_y) {
                if (x_start) |_| {} else x_start = x2;
                last_x = x2;
                max_x_diff = x_diff;
            }
        }
        if (x_start) |start| {
            if (start == last_x) {
                pixel(image, @intCast(start), @intCast(y2), color);
            } else write_slice(image, @intCast(start), @intCast(last_x), @intCast(y2), color);
        }
    }
}

pub fn fill(image: *[PIXEL_COUNT]ColorSize, color: ColorSize) void {
    profiler.enter("fill");
    defer profiler.exit();

    @memset(image, color);
}

test "Colors" {
    const UnpackTest = struct {
        color: Colors,
        rgb: Rgb,
    };

    const HsvTest = struct {
        hsv: struct { h: u8, s: u8, v: u8 },
        rgb: Rgb,
    };

    const unpack_tests: [5]UnpackTest = .{
        .{
            .color = Colors.Red,
            .rgb = .{ .r = 255, .g = 0, .b = 0 },
        },
        .{
            .color = Colors.Green,
            .rgb = .{ .r = 0, .g = 255, .b = 0 },
        },
        .{
            .color = Colors.Blue,
            .rgb = .{ .r = 0, .g = 0, .b = 255 },
        },
        .{
            .color = Colors.Black,
            .rgb = .{ .r = 0, .g = 0, .b = 0 },
        },
        .{
            .color = Colors.White,
            .rgb = .{ .r = 255, .g = 255, .b = 255 },
        },
    };

    const hsv_tests: [3]HsvTest = .{
        .{
            .hsv = .{ .h = 0, .s = 255, .v = 255 },
            .rgb = .{ .r = 255, .g = 0, .b = 0 },
        },
        .{
            .hsv = .{ .h = 0, .s = 0, .v = 255 },
            .rgb = .{ .r = 255, .g = 255, .b = 255 },
        },
        .{
            .hsv = .{ .h = 0, .s = 255, .v = 0 },
            .rgb = .{ .r = 0, .g = 0, .b = 0 },
        },
    };

    for (unpack_tests) |unpack_test| {
        try std.testing.expectEqualDeep(unpack_test.rgb, unpackRgb(@intFromEnum(unpack_test.color)));
        try std.testing.expectEqual(@intFromEnum(unpack_test.color), packRgb(unpackRgb(@intFromEnum(unpack_test.color))));
    }

    for (hsv_tests) |hsv_test| {
        try std.testing.expectEqualDeep(hsv_test.rgb, hsvToRgb(hsv_test.hsv.h, hsv_test.hsv.s, hsv_test.hsv.v));
    }
}
