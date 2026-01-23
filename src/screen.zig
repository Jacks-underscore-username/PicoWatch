const std = @import("std");
const microzig = @import("microzig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;

const pio_qspi = struct {
    pio: rp2xxx.pio.Pio,
    sm: u8,
    sm_4wire: u8,
    sm_1wire: u8,
    pin_cs: u8,
    pin_sclk: u8,
    pin_dio0: u8,
    pin_dio1: u8,
    pin_dio2: u8,
    pin_dio3: u8,
    pin_pwr_en: u8,
    pin_rst: u8,
};

fn reset(qspi: pio_qspi) void {
    gpio.num(qspi.pin_rst).put(1);
    time.sleep_ms(50);
    gpio.num(qspi.pin_rst).put(0);
    time.sleep_ms(50);
    gpio.num(qspi.pin_rst).put(1);
    time.sleep_ms(300);
}

pub fn init() void {}
