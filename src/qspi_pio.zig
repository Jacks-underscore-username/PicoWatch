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
    sm_4wire: u8,
    sm_1wire: u8,
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
    .sm_4wire = 0,
    .sm_1wire = 1,
    .pin_cs = gpio.num(9),
    .pin_sclk = gpio.num(10),
    .pin_dio0 = gpio.num(11),
    .pin_dio1 = gpio.num(12),
    .pin_dio2 = gpio.num(13),
    .pin_dio3 = gpio.num(14),
    .pin_pwr_en = gpio.num(17),
    .pin_rst = gpio.num(15),
};

pub fn QSPI_GPIO_Init() void {
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
