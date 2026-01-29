#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/pio.h"
#include "pico/stdlib.h"
#include <stdio.h>
#include <stdlib.h>

#define PIN_CS 9
#define PIN_SCLK 10
#define PIN_DIO0 11
#define PIN_DIO1 12
#define PIN_DIO2 13
#define PIN_DIO3 14
#define PIN_PWR_EN 17
#define PIN_RST 15

typedef struct pio_qspi {
  PIO pio;
  uint8_t sm;
  uint8_t sm_4wire;
  uint8_t sm_1wire;
  uint8_t pin_cs;
  uint8_t pin_sclk;
  uint8_t pin_dio0;
  uint8_t pin_dio1;
  uint8_t pin_dio2;
  uint8_t pin_dio3;
  uint8_t pin_pwr_en;
  uint8_t pin_rst;
} pio_qspi_t;

pio_qspi_t qspi = {.pio = pio0,
                   .sm = 0,
                   .sm_4wire = 0,
                   .sm_1wire = 1,
                   .pin_cs = PIN_CS,
                   .pin_sclk = PIN_SCLK,
                   .pin_dio0 = PIN_DIO0,
                   .pin_dio1 = PIN_DIO1,
                   .pin_dio2 = PIN_DIO2,
                   .pin_dio3 = PIN_DIO3,
                   .pin_pwr_en = PIN_PWR_EN,
                   .pin_rst = PIN_RST};

#define WIDTH 368
#define HEIGHT 448
#define RED 0xF800

#define UBYTE uint8_t
#define UWORD uint16_t
#define UDOUBLE uint32_t

#define qspi_4wire_data_wrap_target 0
#define qspi_4wire_data_wrap 1
#define qspi_4wire_data_pio_version 0

uint dma_tx;
dma_channel_config dma_config;

static const uint16_t qspi_4wire_data_program_instructions[] = {
    //     .wrap_target
    0x7004, //  0: out    pins, 4         side 0
    0xb842, //  1: nop                    side 1
            //     .wrap
};

static const struct pio_program qspi_4wire_data_program = {
    .instructions = qspi_4wire_data_program_instructions,
    .length = 2,
    .origin = -1,
    .pio_version = qspi_4wire_data_pio_version,
};

void data_write(pio_qspi_t qspi, uint32_t val) {
  uint8_t cmd_buf[4];
  uint8_t buf_temp;
  for (int i = 0; i < 4; ++i) {
    uint8_t bit1 = (val & (1 << (2 * i))) ? 1 : 0;
    uint8_t bit2 = (val & (1 << (2 * i + 1))) ? 1 : 0;
    cmd_buf[3 - i] = bit1 | (bit2 << 4);
  }

  for (int i = 0; i < 4; i++)
    pio_sm_put_blocking(qspi.pio, qspi.sm, cmd_buf[i] << 24);
}

void register_write(pio_qspi_t qspi, uint32_t addr) {
  data_write(qspi, 0x02);

  data_write(qspi, 0x00);
  data_write(qspi, addr);
  data_write(qspi, 0x00);
}

int main(void) {
  stdio_init_all();
  sleep_ms(100);

  dma_tx = dma_claim_unused_channel(true);
  dma_config = dma_channel_get_default_config(dma_tx);
  channel_config_set_transfer_data_size(&dma_config, DMA_SIZE_8);

  gpio_init(qspi.pin_cs);
  gpio_pull_down(qspi.pin_cs);
  gpio_set_dir(qspi.pin_cs, GPIO_OUT);
  gpio_put(qspi.pin_cs, 1);

  gpio_init(qspi.pin_pwr_en);
  gpio_set_dir(qspi.pin_pwr_en, GPIO_OUT);
  gpio_put(qspi.pin_pwr_en, 1);

  gpio_init(qspi.pin_rst);
  gpio_set_dir(qspi.pin_rst, GPIO_OUT);
  uint offset = pio_add_program(qspi.pio, &qspi_4wire_data_program);

  pio_sm_config pio_config = pio_get_default_sm_config();
  sm_config_set_wrap(&pio_config, offset + qspi_4wire_data_wrap_target,
                     offset + qspi_4wire_data_wrap);
  sm_config_set_sideset(&pio_config, 2, true, false);

  pio_gpio_init(qspi.pio, PIN_SCLK);
  pio_sm_set_consecutive_pindirs(qspi.pio, qspi.sm_4wire, PIN_SCLK, 1, true);
  sm_config_set_sideset_pins(&pio_config, PIN_SCLK);

  sm_config_set_out_pins(&pio_config, PIN_DIO0, 4);
  sm_config_set_out_shift(&pio_config, false, true, 8);
  for (uint32_t pin_offset = 0; pin_offset < 4; pin_offset++)
    pio_gpio_init(qspi.pio, PIN_DIO0 + pin_offset);
  pio_sm_set_consecutive_pindirs(qspi.pio, qspi.sm_4wire, PIN_DIO0, 4, true);

  sm_config_set_clkdiv(&pio_config, 1.0f);

  pio_sm_init(qspi.pio, qspi.sm_4wire, offset, &pio_config);
  pio_sm_clear_fifos(qspi.pio, qspi.sm_4wire);
  pio_sm_set_enabled(qspi.pio, qspi.sm_4wire, true);

  pio_sm_set_enabled(qspi.pio, qspi.sm_4wire, false);
  pio_sm_set_enabled(qspi.pio, qspi.sm_1wire, false);

  pio_sm_set_enabled(qspi.pio, qspi.sm_4wire, true);
  pio_sm_set_enabled(qspi.pio, qspi.sm_1wire, false);
  qspi.sm = qspi.sm_4wire;

  gpio_put(qspi.pin_rst, 1);
  sleep_ms(50);
  gpio_put(qspi.pin_rst, 0);
  sleep_ms(50);
  gpio_put(qspi.pin_rst, 1);
  sleep_ms(300);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x11);
  sleep_ms(120);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x44);
  data_write(qspi, 0x01);
  data_write(qspi, 0xC5);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x35);
  data_write(qspi, 0x00);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x3A);
  data_write(qspi, 0x55);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0xC4);
  data_write(qspi, 0x80);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x53);
  data_write(qspi, 0x20);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x51);
  data_write(qspi, 0xFF);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x29);
  gpio_put(qspi.pin_cs, 1);

  sleep_ms(10);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x51);
  data_write(qspi, 255);
  gpio_put(qspi.pin_cs, 1);

  UWORD i;
  UWORD image[HEIGHT];
  for (i = 0; i < HEIGHT; i++)
    image[i] = RED >> 8 | (RED & 0xff) << 8;
  UBYTE *partial_image = (UBYTE *)(image);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x2a);
  data_write(qspi, 0 >> 8);
  data_write(qspi, 0 & 0xff);
  data_write(qspi, (WIDTH - 1) >> 8);
  data_write(qspi, (WIDTH - 1) & 0xff);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x2b);
  data_write(qspi, 0 >> 8);
  data_write(qspi, 0 & 0xff);
  data_write(qspi, (HEIGHT - 1) >> 8);
  data_write(qspi, (HEIGHT - 1) & 0xff);
  gpio_put(qspi.pin_cs, 1);

  gpio_put(qspi.pin_cs, 0);
  register_write(qspi, 0x2c);
  gpio_put(qspi.pin_cs, 1);
  gpio_put(qspi.pin_cs, 0);

  data_write(qspi, 0x32);

  data_write(qspi, 0x00);
  data_write(qspi, 0x2c);
  data_write(qspi, 0x00);

  for (uint16_t i = 0; i < HEIGHT; i++)
    printf("image[%d]: %d\r\n", i, image[i]);
  printf("read_addr: %d\r\n", partial_image);

  printf("dreq: %d\r\n", pio_get_dreq(qspi.pio, qspi.sm, true));

  channel_config_set_dreq(&dma_config, pio_get_dreq(qspi.pio, qspi.sm, true));
  for (int i = 0; i < HEIGHT; i++) {
    dma_channel_configure(
        dma_tx, &dma_config,
        &qspi.pio->txf[qspi.sm], // Destination pointer (PIO TX FIFO)
        partial_image,           // Source pointer (data buffer)
        WIDTH * 2,               // Data length (unit: number of transmissions)
        true                     // Start transferring immediately
    );

    while (dma_channel_is_busy(dma_tx))
      ;
  }

  sleep_ms(1);
  gpio_put(qspi.pin_cs, 1);

  while (true) {
    sleep_ms(1);
  }
}