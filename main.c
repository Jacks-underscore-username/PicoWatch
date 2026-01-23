#include "DEV_Config.h"

#include "AMOLED_1in8.h"
// #include "FT3168.h"
// #include "LCD_test.h"
#include "AMOLED_1in8.h"
// #include "FT3168.h"
// #include "LVGL_example.h"
// #include "PCF85063A.h"
// #include "QMI8658.h"
// #include "lvgl.h"
#include "pico/stdlib.h"
#include "qspi_pio.h"
#include <stdio.h>

int main(void) {
  if (DEV_Module_Init() != 0) {
    return -1;
  }

  printf("AMOLED_1IN8_LCGL_test Demo\r\n");
  /*QSPI PIO Init*/
  QSPI_GPIO_Init(qspi);
  QSPI_PIO_Init(qspi);
  QSPI_4Wrie_Mode(&qspi);
  /*Init LCD*/
  AMOLED_1IN8_Init();
  AMOLED_1IN8_SetBrightness(100);
  AMOLED_1IN8_Clear(WHITE);
  /*Init touch screen*/
  //   FT3168_Init(FT3168_Point_Mode);
  /*Init RTC*/
  // PCF85063A_Init();
  /*Init IMU*/
  // QMI8658_init();
  /*Init LVGL*/
  // LVGL_Init();
  // Widgets_Init();

  uint64_t c = 0;

  while (1) {
    AMOLED_1IN8_Clear(c);

    c++;

    //   lv_task_handler();
    DEV_Delay_ms(5);
  }

  DEV_Module_Exit();
  return 0;
}
