const std = @import("std");
const microzig = @import("microzig");
const usb = @import("usb.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const dma = rp2xxx.dma;
const gpio = rp2xxx.gpio;
const Pin = gpio.Pin;
const Pio = rp2xxx.pio.Pio;
const StateMachine = rp2xxx.pio.StateMachine;

const qspi_4wire_data_wrap_target = 0;
const qspi_4wire_data_wrap = 1;
const qspi_4wire_data_pio_version = 0;

const WIDTH = 368;
const HEIGHT = 448;
const RED = 0xF800;

const pio_qspi = struct {
    pio: Pio,
    sm: StateMachine,
    sm_4wire: StateMachine,
    sm_1wire: StateMachine,
    pin_cs: Pin,
    pin_sclk: Pin,
    pin_dio0: Pin,
    pin_dio1: Pin,
    pin_dio2: Pin,
    pin_dio3: Pin,
    pin_pwr_en: Pin,
    pin_rst: Pin,
};

var qspi: pio_qspi = .{
    .pio = .pio0,
    .sm = StateMachine.sm0,
    .sm_4wire = StateMachine.sm0,
    .sm_1wire = StateMachine.sm1,
    .pin_cs = gpio.num(9),
    .pin_sclk = gpio.num(10),
    .pin_dio0 = gpio.num(11),
    .pin_dio1 = gpio.num(12),
    .pin_dio2 = gpio.num(13),
    .pin_dio3 = gpio.num(14),
    .pin_pwr_en = gpio.num(17),
    .pin_rst = gpio.num(15),
};

const qspi_4wire_data_program = blk: {
    @setEvalBranchQuota(3000);
    break :blk rp2xxx.pio.assemble(
        \\.program qspi_4wire_data
        \\.side_set 1 opt
        \\.wrap_target
        \\    out pins, 4        side 0
        \\    nop                side 1
        \\.wrap
    , .{}).get_program_by_name("qspi_4wire_data");
};

const qspi_1write_cmd_program = blk: {
    @setEvalBranchQuota(3000);
    break :blk rp2xxx.pio.assemble(
        \\.program qspi_1write_cmd
        \\.side_set 1 opt
        \\.wrap_target
        \\    out pins, 1        side 0
        \\    nop                side 1
        \\.wrap
    , .{}).get_program_by_name("qspi_1write_cmd");
};

//TODO: make this function comptime?
fn data_write(val: u32) void {
    var cmd_buf: [4]u32 = undefined;
    inline for (0..4) |i| {
        const bit1: u8 = if (val & (1 << (2 * i)) > 0) 1 else 0;
        const bit2: u8 = if (val & (1 << (2 * i + 1)) > 0) 1 else 0;
        cmd_buf[3 - i] = bit1 | (bit2 << 4);
    }

    inline for (0..4) |i| {
        qspi.pio.sm_blocking_write(qspi.sm, cmd_buf[i] << 24);
    }
}

fn register_write(addr: u32) void {
    data_write(0x02);

    data_write(0x00);
    data_write(addr);
    data_write(0x00);
}

pub fn main() !void {
    usb.init();
    // while (!usb.ready()) usb.poll();

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

    time.sleep_ms(100);

    qspi.pin_cs.set_function(.sio);
    qspi.pin_cs.set_pull(.down);
    qspi.pin_cs.set_direction(.out);
    qspi.pin_cs.put(1);

    qspi.pin_pwr_en.set_function(.sio);
    qspi.pin_pwr_en.set_direction(.out);
    qspi.pin_pwr_en.put(1);

    qspi.pin_rst.set_function(.sio);
    qspi.pin_rst.set_direction(.out);

    const offset = try Pio.add_program(qspi.pio, qspi_4wire_data_program);

    const pio_config: rp2xxx.pio.StateMachineInitOptions = .{
        .exec = .{
            .wrap_target = offset + qspi_4wire_data_wrap_target,
            .wrap = offset + qspi_4wire_data_wrap,
            .side_set_optional = true,
            .side_pindir = false,
        },
        .pin_mappings = .{
            .side_set = .single(
                qspi.pin_sclk,
            ),
            .out = .{
                .low = qspi.pin_dio0,
                .high = @enumFromInt(@intFromEnum(qspi.pin_dio0) + 3),
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

    qspi.pio.gpio_init(qspi.pin_sclk);
    try qspi.pio.sm_set_pindir(qspi.sm_4wire, qspi.pin_sclk, 1, .out);

    inline for (0..4) |pin_offset|
        qspi.pio.gpio_init(@enumFromInt(@intFromEnum(qspi.pin_dio0) + pin_offset));

    try qspi.pio.sm_set_pindir(qspi.sm_4wire, qspi.pin_dio0, 4, .out);

    try qspi.pio.sm_init(qspi.sm_4wire, offset, pio_config);
    qspi.pio.sm_clear_fifos(qspi.sm_4wire);
    qspi.pio.sm_set_enabled(qspi.sm_4wire, true);

    qspi.pio.sm_set_enabled(qspi.sm_4wire, false);
    qspi.pio.sm_set_enabled(qspi.sm_1wire, false);

    qspi.pio.sm_set_enabled(qspi.sm_4wire, true);
    qspi.pio.sm_set_enabled(qspi.sm_1wire, false);
    qspi.sm = qspi.sm_4wire;

    qspi.pin_rst.put(1);
    time.sleep_ms(50);
    qspi.pin_rst.put(0);
    time.sleep_ms(50);
    qspi.pin_rst.put(1);
    time.sleep_ms(300);

    qspi.pin_cs.put(0);
    register_write(0x11);
    time.sleep_ms(120);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x44);
    data_write(0x01);
    data_write(0xC5);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x35);
    data_write(0x00);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x3A);
    data_write(0x55);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0xC4);
    data_write(0x80);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x53);
    data_write(0x20);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x51);
    data_write(0xFF);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x29);
    qspi.pin_cs.put(1);

    time.sleep_ms(10);

    qspi.pin_cs.put(0);
    register_write(0x51);
    data_write(255);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x2a);
    data_write(0 >> 8);
    data_write(0 & 0xff);
    data_write((WIDTH - 1) >> 8);
    data_write((WIDTH - 1) & 0xff);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x2b);
    data_write(0 >> 8);
    data_write(0 & 0xff);
    data_write((HEIGHT - 1) >> 8);
    data_write((HEIGHT - 1) & 0xff);
    qspi.pin_cs.put(1);

    qspi.pin_cs.put(0);
    register_write(0x2c);
    qspi.pin_cs.put(1);
    qspi.pin_cs.put(0);

    data_write(0x32);

    data_write(0x00);
    data_write(0x2c);
    data_write(0x00);

    var image: [HEIGHT]u16 = undefined;
    inline for (0..HEIGHT) |i|
        image[i] = RED >> 8 | (RED & 0xff) << 8;
    const read_addr = @intFromPtr(@as(*volatile [HEIGHT]u16, &image));

    const dma_tx = dma.claim_unused_channel().?;
    const dma_config: dma.Channel.TransferConfig = .{
        .data_size = .size_8,
        .dreq = switch (qspi.pio) {
            .pio0 => switch (qspi.sm) {
                .sm0 => dma.Dreq.pio0_tx0,
                .sm1 => dma.Dreq.pio0_tx1,
                .sm2 => dma.Dreq.pio0_tx2,
                .sm3 => dma.Dreq.pio0_tx3,
            },
            .pio1 => switch (qspi.sm) {
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

    for (0..HEIGHT) |_| {
        dma_tx.setup_transfer_raw(
            @intFromPtr(qspi.pio.sm_get_tx_fifo(qspi.sm)),
            read_addr,
            WIDTH * 2,
            dma_config,
        );
        dma_tx.wait_for_finish_blocking();
    }

    time.sleep_ms(1);
    qspi.pin_cs.put(1);

    while (true)
        usb.poll();
}
