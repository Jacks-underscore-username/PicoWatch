const std = @import("std");
const microzig = @import("microzig");
const use_simulator = @import("build_options").use_simulator;

const hal = microzig.hal;
const time = hal.time;
const gpio = hal.gpio;
const usb = microzig.core.usb;
const USB_Device = hal.usb.Polled(.{});
const USB_Serial = usb.drivers.CDC;

var usb_device: USB_Device = undefined;

var usb_controller: usb.DeviceController(.{
    .bcd_usb = USB_Device.max_supported_bcd_usb,
    .device_triple = .unspecified,
    .vendor = USB_Device.default_vendor_id,
    .product = USB_Device.default_product_id,
    .bcd_device = .v1_00,
    .serial = "someserial",
    .max_supported_packet_size = USB_Device.max_supported_packet_size,
    .configurations = &.{.{
        .attributes = .{ .self_powered = false },
        .max_current_ma = 50,
        .Drivers = struct { serial: USB_Serial, reset: hal.usb.ResetDriver(null, 0) },
    }},
}, .{.{
    .serial = .{ .itf_notifi = "Board CDC", .itf_data = "Board CDC Data" },
    .reset = "",
}}) = .init;

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .log_scope_levels = &.{
        .{ .scope = .usb_dev, .level = .warn },
        .{ .scope = .usb_ctrl, .level = .warn },
        .{ .scope = .usb_cdc, .level = .warn },
    },
    .logFn = hal.uart.log,
};

const pin_config: hal.pins.GlobalConfiguration = .{
    .GPIO0 = .{ .function = .UART0_TX },
    .GPIO25 = .{ .name = "led", .direction = .out },
};

pub fn init() void {
    if (use_simulator) return;

    const pins = pin_config.apply();

    const uart = hal.uart.instance.num(0);
    uart.apply(.{
        .clock_config = hal.clock_config,
    });
    hal.uart.init_logger(uart);

    pins.led.put(1);

    usb_device = .init();

    while (!ready()) poll();

    for (0..10) |_| log("\r\n", .{});
}

pub fn poll() void {
    if (use_simulator) return;

    usb_device.poll(&usb_controller);
}

pub fn ready() bool {
    if (use_simulator) return true;

    return if (usb_controller.drivers()) |_| true else false;
}

pub fn log(comptime fmt: []const u8, args: anytype) void {
    if (use_simulator) {
        std.log.info(fmt, args);
        return;
    }

    usbCdcWrite(&(usb_controller.drivers().?).serial, fmt ++ "\r\n", args);
    poll();
}

pub fn read() []const u8 {
    if (use_simulator) return;

    return usbCdcRead(&(usb_controller.drivers().?).serial);
}

var usb_tx_buff: [1024]u8 = undefined;

// Transfer data to host
// NOTE: After each USB chunk transfer, we have to call the USB task so that bus TX events can be handled
fn usbCdcWrite(serial: *USB_Serial, comptime fmt: []const u8, args: anytype) void {
    var tx = std.fmt.bufPrint(&usb_tx_buff, fmt, args) catch &.{};

    while (tx.len > 0) {
        tx = tx[serial.write(tx)..];
        usb_device.poll(&usb_controller);
    }
    // Short messages are not sent right away; instead, they accumulate in a buffer, so we have to force a flush to send them
    while (!serial.flush())
        usb_device.poll(&usb_controller);
}

var usb_rx_buff: [1024]u8 = undefined;

// Receive data from host
// NOTE: Read code was not tested extensively. In case of issues, try to call USB task before every read operation
fn usbCdcRead(serial: *USB_Serial) []const u8 {
    var rx_len: usize = 0;

    while (true) {
        const len = serial.read(usb_rx_buff[rx_len..]);
        rx_len += len;
        if (len == 0) break;
    }

    return usb_rx_buff[0..rx_len];
}
