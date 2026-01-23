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
// #include <stdio.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

// Helper function to clamp a float value between a minimum and maximum
float clamp(float value, float min_val, float max_val) {
  if (value < min_val)
    return min_val;
  if (value > max_val)
    return max_val;
  return value;
}

// Helper function for the hue channel calculation
float hue2rgb(float p, float q, float t) {
  if (t < 0.0f)
    t += 1.0f;
  if (t > 1.0f)
    t -= 1.0f;
  if (t < 1.0f / 6.0f)
    return p + (q - p) * 6.0f * t;
  if (t < 1.0f / 2.0f)
    return q;
  if (t < 2.0f / 3.0f)
    return p + (q - p) * (2.0f / 3.0f - t) * 6.0f;
  return p;
}

uint16_t hslToRgb565(float h, float s, float l) {
  // 1. Clamp S and L to 0.0-1.0
  s = clamp(s, 0.0f, 1.0f);
  l = clamp(l, 0.0f, 1.0f);

  // 2. Handle Hue wrapping (0-360 degrees) and normalize to 0.0-1.0
  h = fmodf(h, 360.0f);
  if (h < 0.0f)
    h += 360.0f;
  h /= 360.0f; // Normalize H to 0.0-1.0

  float r, g, b;

  if (s == 0.0f) {
    r = g = b = l; // achromatic
  } else {
    float q = l < 0.5f ? l * (1.0f + s) : l + s - l * s;
    float p = 2.0f * l - q;
    r = hue2rgb(p, q, h + 1.0f / 3.0f);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1.0f / 3.0f);
  }

  // 3. Scale RGB floats (0-1) to 8-bit integers (0-255)
  // Ensure we round to the nearest integer before casting to avoid truncation
  uint8_t r8 = (uint8_t)roundf(r * 255.0f);
  uint8_t g8 = (uint8_t)roundf(g * 255.0f);
  uint8_t b8 = (uint8_t)roundf(b * 255.0f);

  // 4. Pack into RGB565 (5 bits Red, 6 bits Green, 5 bits Blue)
  // (R << 11) | (G << 5) | B
  //
  // Red:  Take the most significant 5 bits of r8 (r8 >> 3) and shift left by 11
  // Green: Take the most significant 6 bits of g8 (g8 >> 2) and shift left by 5
  // Blue: Take the most significant 5 bits of b8 (b8 >> 3)
  uint16_t packed = ((uint16_t)(r8 >> 3) << 11) | ((uint16_t)(g8 >> 2) << 5) |
                    ((uint16_t)(b8 >> 3));

  return packed;
}

int main(void) {
  if (DEV_Module_Init() != 0) {
    return -1;
  }

  // printf("AMOLED_1IN8_LCGL_test Demo\r\n");
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

  uint16_t hue = 0;

  while (1) {
    AMOLED_1IN8_Clear(hslToRgb565(hue, 1, 0.5f));

    hue = (hue + 1) % 360;

    //   lv_task_handler();
    DEV_Delay_ms(1);
  }

  DEV_Module_Exit();
  return 0;
}