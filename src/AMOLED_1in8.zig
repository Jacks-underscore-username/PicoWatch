const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const gpio = rp2xxx.gpio;
const time = rp2xxx.time;
const Pin = gpio.Pin;
const Pio = rp2xxx.pio.Pio;
const StateMachine = rp2xxx.pio.StateMachine;

const Qspi = @import("qspi_pio.zig");
const qspi = &Qspi.qspi;

pub fn AMOLED_1IN8_SetWindows(xStart: u32, yStart: u32, xEnd: u32, yEnd: u32) void {
    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x2a);
    Qspi.QSPI_DATA_Write(xStart >> 8);
    Qspi.QSPI_DATA_Write(xStart & 0xff);
    Qspi.QSPI_DATA_Write((xEnd - 1) >> 8);
    Qspi.QSPI_DATA_Write((xEnd - 1) & 0xff);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x2b);
    Qspi.QSPI_DATA_Write(yStart >> 8);
    Qspi.QSPI_DATA_Write(yStart & 0xff);
    Qspi.QSPI_DATA_Write((yEnd - 1) >> 8);
    Qspi.QSPI_DATA_Write((yEnd - 1) & 0xff);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x2c);
    Qspi.QSPI_Deselect();
}

pub fn AMOLED_1IN8_InitReg() void {
    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x11);
    time.sleep_ms(120);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x44);
    Qspi.QSPI_DATA_Write(0x01);
    Qspi.QSPI_DATA_Write(0xC5);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x35);
    Qspi.QSPI_DATA_Write(0x00);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x3A);
    Qspi.QSPI_DATA_Write(0x55);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0xC4);
    Qspi.QSPI_DATA_Write(0x80);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x53);
    Qspi.QSPI_DATA_Write(0x20);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x51);
    Qspi.QSPI_DATA_Write(0xFF);
    Qspi.QSPI_Deselect();

    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x29);
    Qspi.QSPI_Deselect();

    time.sleep_ms(10);
}

pub fn AMOLED_1IN8_Reset() void {
    qspi.pin_rst.put(1);
    time.sleep_ms(50);
    qspi.pin_rst.put(0);
    time.sleep_ms(50);
    qspi.pin_rst.put(1);
    time.sleep_ms(300);
}

pub fn AMOLED_1IN8_Init() void {
    //Hardware reset
    AMOLED_1IN8_Reset();

    //Set the initialization register
    AMOLED_1IN8_InitReg();
}

pub fn AMOLED_1IN8_SetBrightness(brightness: u8) void {
    var b = brightness;
    if (b > 100) b = 100;
    b = b * 255 / 100;

    // QSPI_1Wrie_Mode(&qspi);
    Qspi.QSPI_Select();
    Qspi.QSPI_REGISTER_Write(0x51);
    Qspi.QSPI_DATA_Write(b);
    Qspi.QSPI_Deselect();
}
