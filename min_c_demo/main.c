#include "DEV_Config.h"

#include "AMOLED_1in8.h"
#include "pico/stdlib.h"
#include "qspi_pio.h"

int main(void) {
  stdio_init_all();
  sleep_ms(100);

  dma_tx = dma_claim_unused_channel(true);
  c = dma_channel_get_default_config(dma_tx);
  channel_config_set_transfer_data_size(&c, DMA_SIZE_8);

  QSPI_GPIO_Init(qspi);
  QSPI_PIO_Init(qspi);
  QSPI_4Wrie_Mode(&qspi);

  AMOLED_1IN8_Init();
  AMOLED_1IN8_SetBrightness(100);
  AMOLED_1IN8_Clear(RED);

  while (true) {
  }
}