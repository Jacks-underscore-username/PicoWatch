const std = @import("std");
const microzig = @import("microzig");
const qspi_pio = @import("qspi_pio.zig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const Pio = rp2xxx.pio.Pio;
const StateMachine = rp2xxx.pio.StateMachine;

// Quad SPI 4-wire data program
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

// Single-wire command program
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

// Display dimensions
const WIDTH: u16 = 172;
const HEIGHT: u16 = 320;

// GPIO pins based on C code
const sclk_pin = gpio.num(6); // SCLK/CLK
const data_base_pin = gpio.num(2); // D0-D3 for 4-wire
const cmd_pin = gpio.num(7); // Command pin (MOSI in 1-wire)
const dc_pin = gpio.num(8); // Data/Command pin
const cs_pin = gpio.num(9); // Chip Select
const rst_pin = gpio.num(10); // Reset pin

const pio: Pio = rp2xxx.pio.num(0);
const sm: StateMachine = .sm0;

// Helper function for chip select
fn cs_select() void {
    // Active low
    cs_pin.put(0);
}

fn cs_deselect() void {
    cs_pin.put(1);
}

// Helper function for data/command
fn dc_command() void {
    dc_pin.put(0);
}

fn dc_data() void {
    dc_pin.put(1);
}

// Initialize GPIO pins
fn init_gpio() void {
    // Initialize CS, DC, RST pins as regular GPIO outputs
    cs_pin.set_function(.sio);
    cs_pin.set_direction(.out);
    cs_pin.put(1); // Deselect

    dc_pin.set_function(.sio);
    dc_pin.set_direction(.out);
    dc_pin.put(0); // Command mode by default

    rst_pin.set_function(.sio);
    rst_pin.set_direction(.out);
    rst_pin.put(1); // Release reset
}

// Reset the display
fn amoled_reset() void {
    // Reset sequence from C code
    rst_pin.put(1);
    rp2xxx.time.sleep_ms(50);
    rst_pin.put(0);
    rp2xxx.time.sleep_ms(50);
    rst_pin.put(1);
    rp2xxx.time.sleep_ms(300);
}

// Write command in 1-wire mode
fn write_command(cmd: u8) void {
    dc_command();
    cs_select();
    pio.sm_blocking_write(sm, cmd);
    cs_deselect();
}

// Write data in 1-wire mode
fn write_data1(data: u8) void {
    dc_data();
    cs_select();
    pio.sm_blocking_write(sm, data);
    cs_deselect();
}

// Write multiple data bytes in 1-wire mode
fn write_data1_multiple(data: []const u8) void {
    dc_data();
    cs_select();
    for (data) |byte|
        pio.sm_blocking_write(sm, byte);
    cs_deselect();
}

// Write data in 4-wire mode
fn write_data4(data: []const u16) void {
    dc_data();
    cs_select();
    for (data) |color| {
        // Send 16-bit color: high byte first, then low byte
        pio.sm_blocking_write(sm, @as(u8, @truncate(color >> 8)));
        pio.sm_blocking_write(sm, @as(u8, @truncate(color & 0xFF)));
    }
    cs_deselect();
}

// Set display window
fn set_window(x_start: u16, y_start: u16, x_end: u16, y_end: u16) void {
    // Column address set (0x2A)
    write_command(0x2A);
    write_data1_multiple(&[_]u8{
        @as(u8, @truncate(x_start >> 8)),
        @as(u8, @truncate(x_start & 0xFF)),
        @as(u8, @truncate((x_end - 1) >> 8)),
        @as(u8, @truncate((x_end - 1) & 0xFF)),
    });

    // Row address set (0x2B)
    write_command(0x2B);
    write_data1_multiple(&[_]u8{
        @as(u8, @truncate(y_start >> 8)),
        @as(u8, @truncate(y_start & 0xFF)),
        @as(u8, @truncate((y_end - 1) >> 8)),
        @as(u8, @truncate((y_end - 1) & 0xFF)),
    });

    // Memory write (0x2C)
    write_command(0x2C);
}

// Initialize display registers
fn amoled_init_reg() void {
    // Exit sleep mode (0x11)
    write_command(0x11);
    rp2xxx.time.sleep_ms(120);

    // Set TE scan line (0x44)
    write_command(0x44);
    write_data1(0x01);
    write_data1(0xC5);

    // Set TE signal line (0x35)
    write_command(0x35);
    write_data1(0x00);

    // Interface pixel format (0x3A) - RGB565
    write_command(0x3A);
    write_data1(0x55); // 16-bit/pixel

    // Display control (0xC4)
    write_command(0xC4);
    write_data1(0x80);

    // Brightness control (0x53)
    write_command(0x53);
    write_data1(0x20);

    // Write brightness (0x51)
    write_command(0x51);
    write_data1(0xFF); // Max brightness

    // Display on (0x29)
    write_command(0x29);
    rp2xxx.time.sleep_ms(10);
}

fn write_pixel_4wire(color: u16) void {
    // Send high byte then low byte
    pio.sm_blocking_write(sm, @as(u8, @truncate(color >> 8)));
    pio.sm_blocking_write(sm, @as(u8, @truncate(color & 0xFF)));
}

// Clear the screen with a color
fn amoled_clear(color: u16) void {
    // Set window to full screen
    set_window(0, 0, WIDTH, HEIGHT);

    // Switch to 4-wire mode for data
    pio.sm_set_enabled(sm, false);
    initQspi4WireData();

    // Prepare the color (swap bytes for little-endian)
    const color_le = (color >> 8) | (color << 8);

    dc_data();
    cs_select();

    // Fill the entire screen
    var y: u16 = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: u16 = 0;
        while (x < WIDTH) : (x += 1)
            write_pixel_4wire(color_le);
    }

    cs_deselect();

    // Switch back to 1-wire mode for commands
    pio.sm_set_enabled(sm, false);
    initQspi1WriteCmd();
}

fn QSPI_CMD_Write(val: u32) void {
    var cmd_buf: [4]u8 = undefined;
    //   uint8_t cmd_buf[4];
    // var buf_temp:u8 = undefined;
    //   uint8_t buf_temp;
    var i: u2 = 0;
    while (i < 4) : (i += 1) {
        //   for (int i = 0; i < 4; ++i) {
        const bit1: u8 = if (val & (@as(u100, 1) << (2 * i)) > 0) 1 else 0;
        // uint8_t bit1 = (val & (1 << (2 * i))) ? 1 : 0;
        const bit2: u8 = if (val & (@as(u100, 1) << (2 * i + 1)) > 0) 1 else 0;
        // uint8_t bit2 = (val & (1 << (2 * i + 1))) ? 1 : 0;
        cmd_buf[3 - i] = bit1 | (bit2 << 4);
    }

    for (cmd_buf) |b|
        pio.sm_blocking_write(sm, b << 24);

    //   for (int i = 0; i < 4; i++) {
    //     QSPI_PIO_Write(qspi, cmd_buf[i]);
    //   }
}

fn QSPI_REGISTER_Write(addr: u32) void {
    // 1 WIRE CMD
    QSPI_CMD_Write(0x02);

    // 1 WIRE ADDR
    QSPI_CMD_Write(0x00);
    QSPI_CMD_Write(addr);
    QSPI_CMD_Write(0x00);
}

// Set brightness (0-100)
fn amoled_set_brightness(brightness: u8) void {
    var b = brightness;
    if (b > 100) b = 100;
    // const scaled = b * 255 / 100;

    // dc_command();
    // cs_select();
    // pio.sm_blocking_write(sm, 0x51);
    // dc_data();
    // // pio.sm_blocking_write(sm, scaled);
    // cs_deselect();

    // write_command(0x51);
    // write_data1(scaled);

    cs_select();
    QSPI_REGISTER_Write(0x51);
    // QSPI_CMD_Write(brightness);
    cs_deselect();
}

// Initialize the display
fn amoled_init() void {
    // Initialize GPIO
    init_gpio();

    // Hardware reset
    amoled_reset();

    // Initialize 1-wire mode for commands
    initQspi1WriteCmd();

    // Set initialization registers
    amoled_init_reg();
}

fn initQspi1WriteCmd() void {
    pio.gpio_init(sclk_pin);
    pio.gpio_init(cmd_pin);

    // Set pin directions
    sm_set_consecutive_pindirs(@intFromEnum(cmd_pin), 1, true);
    sm_set_consecutive_pindirs(@intFromEnum(sclk_pin), 1, true);

    pio.sm_load_and_start_program(sm, qspi_1write_cmd_program, .{
        .clkdiv = rp2xxx.pio.ClkDivOptions.from_float(1.0),
        .pin_mappings = .{
            .side_set = .single(sclk_pin),
            .out = .single(cmd_pin),
        },
        .shift = .{
            .out_shiftdir = .left,
            .autopull = true,
            .pull_threshold = 8,
        },
    }) catch unreachable;
    pio.sm_set_enabled(sm, true);
}

fn initQspi4WireData() void {
    pio.gpio_init(sclk_pin);

    for (0..4) |i| {
        pio.gpio_init(gpio.num(@as(u9, @intCast(@intFromEnum(data_base_pin) + i))));
    }

    sm_set_consecutive_pindirs(@intFromEnum(data_base_pin), 4, true);
    sm_set_consecutive_pindirs(@intFromEnum(sclk_pin), 1, true);

    pio.sm_load_and_start_program(sm, qspi_4wire_data_program, .{
        .clkdiv = rp2xxx.pio.ClkDivOptions.from_float(1.0),
        .pin_mappings = .{
            .side_set = .single(sclk_pin),
            .out = .{
                .low = data_base_pin,
                .high = gpio.num(@as(u9, @intCast(@intFromEnum(data_base_pin) + 3))),
            },
        },
        .shift = .{
            .out_shiftdir = .left,
            .autopull = true,
            .pull_threshold = 8,
        },
    }) catch unreachable;
    pio.sm_set_enabled(sm, true);
}

fn sm_set_consecutive_pindirs(pin: u5, count: u3, is_out: bool) void {
    const sm_regs = pio.get_sm_regs(sm);
    const pinctrl_saved = sm_regs.pinctrl.raw;
    sm_regs.pinctrl.modify(.{
        .SET_BASE = pin,
        .SET_COUNT = count,
    });
    pio.sm_exec(sm, rp2xxx.pio.Instruction{
        .tag = .set,
        .delay_side_set = 0,
        .payload = .{
            .set = .{
                .data = @intFromBool(is_out),
                .destination = .pindirs,
            },
        },
    });
    sm_regs.pinctrl.raw = pinctrl_saved;
}

pub fn main() !void {
    // Initialize display
    amoled_init();

    rp2xxx.time.sleep_ms(1000);

    // Set brightness to 50%
    amoled_set_brightness(50);

    // Clear screen with different colors
    // amoled_clear(0x0000); // Black
    // rp2xxx.time.sleep_ms(1000);

    // amoled_clear(0xF800); // Red
    // rp2xxx.time.sleep_ms(1000);

    // amoled_clear(0x07E0); // Green
    // rp2xxx.time.sleep_ms(1000);

    // amoled_clear(0x001F); // Blue
    // rp2xxx.time.sleep_ms(1000);

    amoled_clear(0xFFFF); // White
    // rp2xxx.time.sleep_ms(1000);

    // amoled_clear(0x0000); // Black

    // while (true) {
    //     // Your main application here
    // }
}

pub fn init() !void {
    try main();
    // qspi_pio.QSPI_GPIO_Init();
}
