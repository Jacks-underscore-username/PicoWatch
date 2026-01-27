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

pub fn DEV_GPIO_Init() void {
    // gpio_init(Touch_RST_PIN);
    // gpio_set_dir(Touch_RST_PIN, GPIO_OUT);
}

pub fn DEV_Module_Init() void {
    // stdio_init_all();
    time.sleep_ms(100);

    //GPIO
    DEV_GPIO_Init();

    //DMA
    // dma_tx = dma_claim_unused_channel(true);
    // c = dma_channel_get_default_config(dma_tx);
    // channel_config_set_transfer_data_size(&c, DMA_SIZE_8);
    // channel_config_set_read_increment(&c, true);
    // channel_config_set_write_increment(&c, false);
    // channel_config_set_dreq(&c, pio_get_dreq(qspi.pio, qspi.sm, false));
    // irq_set_enabled(DMA_IRQ_0, false);

    // I2C Config
    // i2c_init(I2C_PORT, 400 * 1000);
    // gpio_set_function(DEV_SDA_PIN, GPIO_FUNC_I2C);
    // gpio_set_function(DEV_SCL_PIN, GPIO_FUNC_I2C);
    // gpio_pull_up(DEV_SDA_PIN);
    // gpio_pull_up(DEV_SCL_PIN);

}
