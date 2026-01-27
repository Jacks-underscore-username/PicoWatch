#ifndef _DEV_CONFIG_H_
#define _DEV_CONFIG_H_

#include "hardware/dma.h"
#include "pico/stdlib.h"
#include <stdio.h>
#include <stdlib.h>

#define UBYTE uint8_t
#define UWORD uint16_t
#define UDOUBLE uint32_t

#define SPI_PORT spi1
#define I2C_PORT i2c1

#define LCD_CS_PIN 9

#define DEV_SDA_PIN 6
#define DEV_SCL_PIN 7
#define DOF_INT1 8

#define Touch_RST_PIN 5
#define Touch_INT_PIN 4

extern uint dma_tx;
extern dma_channel_config c;

/*------------------------------------------------------------------------------------------------------*/
void DEV_Module_Init(void);

#endif
