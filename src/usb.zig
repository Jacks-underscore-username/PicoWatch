const std = @import("std");
const microzig = @import("microzig");
const main = @import("main.zig");
const use_simulator = @import("build_options").use_simulator;

const io = std.io;
const Writer = io.Writer;
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

const pin_config: hal.pins.GlobalConfiguration = .{
    .GPIO0 = .{ .function = .UART0_TX },
};

pub fn init() !void {
    if (use_simulator) return;

    _ = pin_config.apply();

    usb_device = .init();

    const deadline = hal.time.deadline_in_ms(5_000);
    while (!ready() and !deadline.is_reached_by(hal.time.get_time_since_boot())) poll();
    if (ready()) for (0..10) |_| rawLog("\r\n", .{});
    while (!deadline.is_reached_by(hal.time.get_time_since_boot())) {
        const value = read();
        if (value.len == 11) {
            const whitespace_chars = &[_]u8{ ' ', '\t', '\n', '\r' };
            const epoch = try std.fmt.parseInt(u64, std.mem.trim(u8, value, whitespace_chars), 10) * 1_000;
            default_log.info("Got epoch {}", .{epoch});
            hal.rtc.set_time(epoch);
            hal.rtc.enable();
            const now = main.getCurrentTime();
            default_log.info("Set time to {}/{:0>2}/{:0>2} {:0>2}:{:0>2}:{:0>2}:{:0>4}", .{ now.year, now.month, now.day, now.hour, now.minute, now.second, now.millisecond });
            return;
        } else {
            default_log.info("Waiting for epoch...", .{});
            hal.time.sleep_ms(500);
        }
    }
}

pub fn poll() void {
    if (use_simulator) return;

    usb_device.poll(&usb_controller);
}

pub fn ready() bool {
    if (use_simulator) return true;

    return if (usb_controller.drivers()) |_| true else false;
}

pub fn defaultLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (use_simulator) {
        std.log.defaultLog(message_level, scope, format, args);

        return;
    }

    if (!ready()) return;

    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    usbCdcWrite(&(usb_controller.drivers().?).serial, level_txt ++ prefix2 ++ format ++ "\n", args);
    poll();
}

fn rawLog(comptime format: []const u8, args: anytype) void {
    usbCdcWrite(&(usb_controller.drivers().?).serial, format, args);
    poll();
}

pub fn ScopedLog(comptime scope: @Type(.enum_literal)) type {
    return struct {
        pub fn err(comptime format: []const u8, args: anytype) void {
            @branchHint(.cold);
            defaultLog(.err, scope, format, args);
        }

        pub fn warn(comptime format: []const u8, args: anytype) void {
            defaultLog(.warn, scope, format, args);
        }

        pub fn info(comptime format: []const u8, args: anytype) void {
            defaultLog(.info, scope, format, args);
        }

        pub fn debug(comptime format: []const u8, args: anytype) void {
            defaultLog(.debug, scope, format, args);
        }
    };
}

pub const default_log = ScopedLog(std.log.default_log_scope);

pub fn read() []const u8 {
    if (use_simulator) return;

    return usbCdcRead(&(usb_controller.drivers().?).serial);
}

var writer_buff: [1024]u8 = undefined;
pub var writer: io.Writer = .{
    .vtable = &.{
        .drain = Writer.fixedDrain,
        .flush = flushWriter,
        .rebase = Writer.failingRebase,
    },
    .end = 0,
    .buffer = &writer_buff,
};

fn flushWriter(w: *Writer) Writer.Error!void {
    const serial: *USB_Serial = &(usb_controller.drivers().?).serial;
    var tx = w.buffer;

    while (tx.len > 0) {
        tx = tx[serial.write(tx)..];
        usb_device.poll(&usb_controller);
    }

    while (!serial.flush())
        usb_device.poll(&usb_controller);

    w.end = 0;
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
