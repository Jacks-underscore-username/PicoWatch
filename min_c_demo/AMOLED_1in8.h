#ifndef _AMOLED_1IN8_H_
#define _AMOLED_1IN8_H_

#include "qspi_pio.h"

#define AMOLED_1IN8_WIDTH 368
#define AMOLED_1IN8_HEIGHT 448

#define HORIZONTAL 0
#define VERTICAL 1

#define WHITE 0xFFFF
#define BLACK 0x0000
#define BLUE 0x001F
#define BRED 0XF81F
#define GRED 0XFFE0
#define GBLUE 0X07FF
#define RED 0xF800
#define MAGENTA 0xF81F
#define GREEN 0x07E0
#define CYAN 0x7FFF
#define YELLOW 0xFFE0
#define BROWN 0XBC40
#define BRRED 0XFC07
#define GRAY 0X8430
#define DARKBLUE 0X01CF
#define LIGHTBLUE 0X7D7C
#define GRAYBLUE 0X5458
#define LIGHTGREEN 0X841F
#define LGRAY 0XC618
#define LGRAYBLUE 0XA651
#define LBBLUE 0X2B12

typedef struct {
  UWORD WIDTH;
  UWORD HEIGHT;
  UBYTE SCAN_DIR;
} AMOLED_1IN8_ATTRIBUTES;
extern AMOLED_1IN8_ATTRIBUTES AMOLED_1IN8;

void AMOLED_1IN8_Init();
void AMOLED_1IN8_SetBrightness(uint8_t brightness);
void AMOLED_1IN8_SetWindows(uint32_t Xstart, uint32_t Ystart, uint32_t Xend,
                            uint32_t Yend);
void AMOLED_1IN8_Clear(UWORD Color);

#endif // !_AMOLED_1IN8_H_
