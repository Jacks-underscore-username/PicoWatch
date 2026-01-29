const std = @import("std");
const microzig = @import("microzig");

const math = std.math;
const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const dma = rp2xxx.dma;
const gpio = rp2xxx.gpio;
const Pin = gpio.Pin;
const Pio = rp2xxx.pio.Pio;
const StateMachine = rp2xxx.pio.StateMachine;

const fourWireDataWrapTarget = 0;
const fourWireDataWrap = 1;
const fourWireDataPioVersion = 0;

pub const WIDTH = 368;
pub const HEIGHT = 448;
pub const PIXEL_COUNT = WIDTH * HEIGHT;

pub const WHITE: u16 = 0xFFFF;
pub const BLACK: u16 = 0x0000;
pub const BLUE: u16 = 0x001F;
pub const BRED: u16 = 0xF81F;
pub const GRED: u16 = 0xFFE0;
pub const GBLUE: u16 = 0x07FF;
pub const RED: u16 = 0xF800;
pub const MAGENTA: u16 = 0xF81F;
pub const GREEN: u16 = 0x07E0;
pub const CYAN: u16 = 0x7FFF;
pub const YELLOW: u16 = 0xFFE0;
pub const BROWN: u16 = 0xBC40;
pub const BRRED: u16 = 0xFC07;
pub const GRAY: u16 = 0x8430;
pub const DARKBLUE: u16 = 0x01CF;
pub const LIGHTBLUE: u16 = 0x7D7C;
pub const GRAYBLUE: u16 = 0x5458;
pub const LIGHTGREEN: u16 = 0x841F;
pub const LGRAY: u16 = 0xC618;
pub const LGRAYBLUE: u16 = 0xA651;
pub const LBBLUE: u16 = 0x2B12;

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
    break :blk rp2xxx.pio.assemble(
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
    break :blk rp2xxx.pio.assemble(
        \\.program qspi1writeCmd
        \\.side_set 1 opt
        \\.wrap_target
        \\    out pins, 1        side 0
        \\    nop                side 1
        \\.wrap
    , .{}).get_program_by_name("qspi1writeCmd");
};

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

fn registerWrite(addr: u32) void {
    dataWrite(0x02);

    dataWrite(0x00);
    dataWrite(addr);
    dataWrite(0x00);
}

fn pixelWrite(addr: u32) void {
    dataWrite(0x32);

    dataWrite(0x00);
    dataWrite(addr);
    dataWrite(0x00);
}

inline fn select() void {
    config.pin_cs.put(0);
}

inline fn deselect() void {
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

    const pio_config: rp2xxx.pio.StateMachineInitOptions = .{
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
    dataWrite(0x01);
    dataWrite(0xC5);
    deselect();

    select();
    registerWrite(0x35);
    dataWrite(0x00);
    deselect();

    select();
    registerWrite(0x3A);
    dataWrite(0x55);
    deselect();

    select();
    registerWrite(0xC4);
    dataWrite(0x80);
    deselect();

    select();
    registerWrite(0x53);
    dataWrite(0x20);
    deselect();

    select();
    registerWrite(0x51);
    dataWrite(0xFF);
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

pub fn init() !void {
    try initPio();

    reset();

    initRegisters();

    dma_tx = dma.claim_unused_channel().?;
}

pub fn setBrightness(brightness: u8) void {
    select();
    registerWrite(0x51);
    dataWrite(brightness);
    deselect();
}

fn setWindowSize(start_x: u16, start_y: u16, end_x: u16, end_y: u16) void {
    select();
    registerWrite(0x2a);
    dataWrite(start_x >> 8);
    dataWrite(start_x & 0xff);
    dataWrite((end_x - 1) >> 8);
    dataWrite((end_x - 1) & 0xff);
    deselect();

    select();
    registerWrite(0x2b);
    dataWrite(start_y >> 8);
    dataWrite(start_y & 0xff);
    dataWrite((end_y - 1) >> 8);
    dataWrite((end_y - 1) & 0xff);
    deselect();

    select();
    registerWrite(0x2c);
    deselect();
}

pub fn fillColor(color: u16) void {
    setWindowSize(0, 0, WIDTH, HEIGHT);
    select();
    pixelWrite(0x2c);

    var image: [HEIGHT]u16 = undefined;
    inline for (0..HEIGHT) |i|
        image[i] = color >> 8 | (color & 0xff) << 8;
    const readAddr = @intFromPtr(@as(*volatile [HEIGHT]u16, &image));

    for (0..HEIGHT) |_| {
        dma_tx.setup_transfer_raw(
            @intFromPtr(config.pio.sm_get_tx_fifo(config.sm)),
            readAddr,
            WIDTH * 2,
            dma_config,
        );
        dma_tx.wait_for_finish_blocking();
    }

    deselect();
}

pub fn writeImage(image: *[PIXEL_COUNT]u16) void {
    setWindowSize(0, 0, WIDTH, HEIGHT);
    select();
    pixelWrite(0x2c);

    const readAddr = @intFromPtr(@as(*volatile [PIXEL_COUNT]u16, image));

    dma_tx.setup_transfer_raw(
        @intFromPtr(config.pio.sm_get_tx_fifo(config.sm)),
        readAddr,
        PIXEL_COUNT * 2,
        dma_config,
    );

    dma_tx.wait_for_finish_blocking();
    deselect();
}

pub inline fn isInRange(x: u16, y: u16) bool {
    return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT;
}

pub fn addInRange(a: u16, b: u16) u16 {
    return @min(WIDTH - 1, a + b);
}

pub fn subInRange(a: u16, b: u16) u16 {
    const res: struct { u16, u1 } = @subWithOverflow(a, b);
    if (res[1] == 1) return 0;
    return res[0];
}

pub fn difference(comptime T: type, a: T, b: T) T {
    return if (a > b) a - b else b - a;
}

pub fn pixel(image: *[PIXEL_COUNT]u16, x: u16, y: u16, color: u16) void {
    if (isInRange(x, y))
        image.*[x + y * WIDTH] = color >> 8 | (color & 0xff) << 8;
}

pub fn rect(image: *[PIXEL_COUNT]u16, x: u16, y: u16, width: u16, height: u16, color: u16) void {
    for (x..x + width) |x2| {
        for (y..y + height) |y2|
            pixel(image, @intCast(x2), @intCast(y2), color);
    }
}

pub fn circle(image: *[PIXEL_COUNT]u16, x: u16, y: u16, r: u16, color: u16) void {
    for (subInRange(x, r)..addInRange(x, r)) |x2| {
        for (subInRange(y, r)..addInRange(y, r)) |y2| {
            const d = @sqrt(@as(f64, @floatFromInt(math.pow(u16, difference(u16, x, @intCast(x2)), 2) + math.pow(u16, difference(u16, y, @intCast(y2)), 2))));
            if (d <= @as(@TypeOf(d), @floatFromInt(r)))
                pixel(image, @intCast(x2), @intCast(y2), color);
        }
    }
}

pub fn fill(image: *[PIXEL_COUNT]u16, color: u16) void {
    for (0..PIXEL_COUNT) |i| image.*[i] = color >> 8 | (color & 0xff) << 8;
}
