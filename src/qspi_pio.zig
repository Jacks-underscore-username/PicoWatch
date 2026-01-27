const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const Pin = gpio.Pin;
const Pio = rp2xxx.pio.Pio;
const StateMachine = rp2xxx.pio.StateMachine;

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

const qspi: pio_qspi = .{
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

fn QSPI_GPIO_Init() void {
    qspi.pin_cs.set_function(.spi);
    qspi.pin_cs.set_pull(.down);
    qspi.pin_cs.set_direction(.out);
    qspi.pin_cs.put(1);

    qspi.pin_pwr_en.set_function(.spi);
    qspi.pin_pwr_en.set_direction(.out);
    qspi.pin_pwr_en.put(1);

    qspi.pin_rst.set_function(.spi);
    qspi.pin_rst.set_direction(.out);
}

fn QSPI_Select() void {
    qspi.pin_cs.put(0);
}

fn QSPI_Deselect() void {
    qspi.pin_cs.put(1);
}

fn qspi_4wire_data_program_get_default_config(offset: u5) rp2xxx.pio.StateMachineInitOptions {
    //TODO: Do I need to use offset?
    _ = offset;
    return .{};
}

fn qspi_4wire_data_program_init(sm: StateMachine, offset: u5, pin_scl: Pin, out_base: Pin, out_pin_num: comptime_int) void {
    const c = qspi_4wire_data_program_get_default_config(offset);
    // pio_sm_config c = qspi_4wire_data_program_get_default_config( offset );
    // CLK

    qspi.pio.gpio_init(pin_scl);
    // pio_gpio_init(pio, pin_scl);

    //TODO: What direction is `true`?
    qspi.pio.sm_set_pindir(sm, pin_scl, 1, .out);
    // pio_sm_set_consecutive_pindirs(pio, sm, pin_scl, 1, true);

    c.pin_mappings.side_set = .single(pin_scl);
    // sm_config_set_sideset_pins(&c, pin_scl);
    // DAT
    c.pin_mappings.out = .{ .low = out_base, .high = gpio.num(@intFromEnum(out_base) + out_pin_num - 1) };
    // sm_config_set_out_pins(&c, out_base, out_pin_num);
    //TODO: ?
    c.shift = .{ .in_shiftdir = .left, .out_shiftdir = .left, .autopull = true, .pull_threshold = 8 };
    // sm_config_set_out_shift(&c, false, true, 8);

    var pin_offset: u2 = 0;
    while (pin_offset < out_pin_num) : (pin_offset += 1) {
        qspi.pio.gpio_init(gpio.num(@intFromEnum(out_base) + pin_offset));
    }
    // for (uint32_t pin_offset = 0; pin_offset < out_pin_num; pin_offset++) {
    //     pio_gpio_init(pio, out_base + pin_offset);
    // }
    //TODO: What direction is `true`?
    qspi.pio.sm_set_pindir(sm, out_base, out_pin_num, .out);
    // pio_sm_set_consecutive_pindirs(pio, sm, out_base, out_pin_num, true);
    // PIO CLK
    // sm_config_set_clkdiv( &c, 1.0f);
    qspi.pio.sm_set_clkdiv(sm, .{ .int = 1 });
    // INIT
    qspi.pio.sm_init(sm, offset, c);
    // pio_sm_init( pio, sm, offset, &c );
    qspi.pio.sm_clear_fifos(sm);
    // pio_sm_clear_fifos( pio , sm);
    qspi.pio.sm_set_enabled(sm, true);
    // pio_sm_set_enabled( pio, sm, true );
}

fn QSPI_PIO_Init() !void {
    const offset = try qspi.pio.add_program(qspi_4wire_data_program);
    qspi_4wire_data_program_init(qspi.sm_4wire, offset, qspi.pin_sclk, qspi.pin_dio0, 4);

    qspi.pio.sm_set_enabled(qspi.sm_4wire, false);
    qspi.pio.sm_set_enabled(qspi.sm_1wire, false);
    // pio_sm_set_enabled(qspi.pio, qspi.sm_4wire, false);
    // pio_sm_set_enabled(qspi.pio, qspi.sm_1wire, false);
}

fn QSPI_1Wrie_Mode() void {
    qspi.pio.sm_set_enabled(qspi.sm_4wire, false);
    qspi.pio.sm_set_enabled(qspi.sm_1wire, true);
    qspi.sm = qspi.sm_1wire;
}

fn QSPI_4Wrie_Mode() void {
    qspi.pio.sm_set_enabled(qspi.sm_4wire, true);
    qspi.pio.sm_set_enabled(qspi.sm_1wire, false);
    qspi.sm = qspi.sm_4wire;
}

fn QSPI_PIO_Write(val: u32) void {
    qspi.pio.sm_blocking_write(qspi.sm, val << 24);
}

fn QSPI_DATA_Write(val: u32) void {
    const cmd_buf: [4]u8 = undefined;
    var i: u2 = 0;
    while (i < 4) : (i += 1) {
        const bit1: u8 = if (val & (1 << (2 * i)) > 0) 1 else 0;
        const bit2: u8 = if (val & (1 << (2 * i + 1)) > 0) 1 else 0;
        cmd_buf[3 - i] = bit1 | (bit2 << 4);
    }

    i = 0;
    while (i < 4) : (i += 1) {
        QSPI_PIO_Write(cmd_buf[i]);
    }
}

fn QSPI_CMD_Write(val: u32) void {
    QSPI_DATA_Write(val);
}

fn QSPI_REGISTER_Write(addr: u32) void {
    // 1 WIRE CMD
    QSPI_CMD_Write(0x02);

    // 1 WIRE ADDR
    QSPI_DATA_Write(0x00);
    QSPI_DATA_Write(addr);
    QSPI_DATA_Write(0x00);
}

fn QSPI_Pixel_Write(addr: u32) void {
    // 1 WIRE CMD
    QSPI_CMD_Write(0x32);

    // 1 WIRE ADDR
    QSPI_DATA_Write(0x00);
    QSPI_DATA_Write(addr);
    QSPI_DATA_Write(0x00);
}
