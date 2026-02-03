const std = @import("std");
const microzig = @import("microzig");
const sdl3 = @import("sdl3");
const usb = @import("usb.zig");
const main = @import("main.zig");
const profiler = @import("profiler.zig");
const use_emulator = @import("build_options").use_emulator;

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

pub const WIDTH = 368;
pub const HEIGHT = 448;
pub const PIXEL_COUNT = WIDTH * HEIGHT;

pub const DIRECTION = enum(@TypeOf(@max(WIDTH, HEIGHT))) {
    X = WIDTH,
    Y = HEIGHT,
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
    dataWriteCT(0x55);
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
    if (use_emulator) {
        try sdl3.init(init_flags);
        window, renderer = try sdl3.render.Renderer.initWithWindow("PicoWatch screen emulator [OPAQUE]", WIDTH, HEIGHT, .{});

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
    if (!use_emulator) return;
    window.deinit();
    sdl3.quit(init_flags);
    sdl3.shutdown();
}

pub fn setBrightness(brightness: u8) void {
    if (use_emulator) return;

    select();
    registerWrite(0x51);
    dataWrite(brightness);
    deselect();
}

fn setWindowSize(comptime start_x: u16, comptime start_y: u16, comptime end_x: u16, comptime end_y: u16) void {
    select();
    registerWrite(0x2a);
    dataWriteCT(start_x >> 8);
    dataWriteCT(start_x & 0xff);
    dataWriteCT((end_x - 1) >> 8);
    dataWriteCT((end_x - 1) & 0xff);
    deselect();

    select();
    registerWrite(0x2b);
    dataWriteCT(start_y >> 8);
    dataWriteCT(start_y & 0xff);
    dataWriteCT((end_y - 1) >> 8);
    dataWriteCT((end_y - 1) & 0xff);
    deselect();

    select();
    registerWrite(0x2c);
    deselect();
}

pub fn writeImage(image: *[PIXEL_COUNT]ColorSize) !void {
    profiler.enter("writeImage");
    defer profiler.exit();

    if (use_emulator) {
        const surface = try window.getSurface();

        const texture = try renderer.createTexture(
            surface.getFormat().?,
            sdl3.render.Texture.Access.streaming,
            WIDTH,
            HEIGHT,
        );

        const lock = try texture.lock(null);
        const pixels_ptr: [*]u8 = lock[0];
        const u32_pixels_ptr: [*]u32 = @ptrCast(@alignCast(pixels_ptr));

        for (0..PIXEL_COUNT) |i| {
            const color = image.*[i];
            const rgb = unpackRgb(color);
            u32_pixels_ptr[i] = surface.mapRgb(rgb.r, rgb.g, rgb.b).value;
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
        @intFromPtr(@as(*volatile [PIXEL_COUNT]ColorSize, image)),
        PIXEL_COUNT * if (ColorSize == u16) 2 else 3,
        dma_config,
    );

    dma_tx.wait_for_finish_blocking();
    deselect();
}

pub fn packRgb(r: u8, g: u8, b: u8) u16 {
    profiler.enter("packRgb");
    defer profiler.exit();

    const r5 = (@as(u16, r) * 31 + 127) / 255;
    const g6 = (@as(u16, g) * 63 + 127) / 255;
    const b5 = (@as(u16, b) * 31 + 127) / 255;

    return (r5 << 11) | (g6 << 5) | b5;
}

pub fn unpackRgb(color: u16) struct { r: u8, g: u8, b: u8 } {
    profiler.enter("unpackRgb");
    defer profiler.exit();

    const r5 = @as(u16, color >> 11) & 0x1F;
    const g6 = @as(u16, color >> 5) & 0x3F;
    const b5 = @as(u16, color) & 0x1F;

    const r8 = @as(u8, @intCast((r5 * 255 + 15) / 31));
    const g8 = @as(u8, @intCast((g6 * 255 + 31) / 63));
    const b8 = @as(u8, @intCast((b5 * 255 + 15) / 31));

    return .{ .r = r8, .g = g8, .b = b8 };
}

pub inline fn isInRange(x: u16, y: u16) bool {
    return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT;
}

pub fn addInRange(comptime T: type, dir: DIRECTION, a: T, b: T) T {
    profiler.enter("addInRange");
    defer profiler.exit();

    if (b > 0) {
        const res: struct { T, u1 } = @addWithOverflow(a, b);
        if (res[1] == 1) return @intFromEnum(dir) - 1;
        return @min(@intFromEnum(dir) - 1, res[0]);
    } else {
        const res: struct { T, u1 } = @subWithOverflow(a, @as(T, @intCast(@abs(b))));
        if (res[1] == 1) return 0;
        return @max(0, res[0]);
    }
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

pub fn rect(image: *[PIXEL_COUNT]ColorSize, x: u16, y: u16, width: u16, height: u16, color: ColorSize) void {
    profiler.enter("rect");
    defer profiler.exit();

    for (x..x + width) |x2| {
        for (y..y + height) |y2|
            pixel(image, @intCast(x2), @intCast(y2), color);
    }
}

pub fn circle(image: *[PIXEL_COUNT]ColorSize, x: u16, y: u16, r: u16, color: ColorSize) void {
    profiler.enter("circle");
    defer profiler.exit();

    const r_squared = math.pow(u16, r, 2);
    const r_neg = -@as(i32, @intCast(r));
    const x_range_min: usize = @intCast(addInRange(i64, .X, x, r_neg));
    const x_range_max: usize = @intCast(addInRange(i64, .X, x, r));
    const y_range_min: usize = @intCast(addInRange(i64, .Y, y, r_neg));
    const y_range_max: usize = @intCast(addInRange(i64, .Y, y, r));
    for (x_range_min..x_range_max) |x2| {
        const x_diff = difference(u16, x, @intCast(x2));
        const x_squared = math.pow(u16, x_diff, 2);
        const r_squared_minus_x = r_squared - x_squared;
        var max_y_diff: u16 = 0;
        for (y_range_min..y_range_max) |y2| {
            const y_diff = difference(u16, y, @intCast(y2));
            if (y_diff < max_y_diff) {
                pixel(image, @intCast(x2), @intCast(y2), color);
                continue;
            }
            const y_squared = math.pow(u16, y_diff, 2);
            if (y_squared <= r_squared_minus_x) {
                max_y_diff = y_diff;
                pixel(image, @intCast(x2), @intCast(y2), color);
            }
        }
    }
}

pub fn fill(image: *[PIXEL_COUNT]ColorSize, color: ColorSize) void {
    profiler.enter("fill");
    defer profiler.exit();

    @memset(image, color);
}
