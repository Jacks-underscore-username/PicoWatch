
cmake_minimum_required(VERSION 3.13)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

set(PICO_BOARD pico2 CACHE STRING "Board type")

include(pico_sdk_import.cmake)

project(RP2350-Touch-AMOLED-1.8 C CXX ASM)

pico_sdk_init()

aux_source_directory(. DIR)

add_executable(RP2350-Touch-AMOLED-1.8 ${DIR})

pico_generate_pio_header(RP2350-Touch-AMOLED-1.8 ${CMAKE_CURRENT_LIST_DIR}/qspi.pio
  OUTPUT_DIR ${CMAKE_CURRENT_LIST_DIR})

pico_set_program_name(RP2350-Touch-AMOLED-1.8 "RP2350-Touch-AMOLED-1.8")
pico_set_program_version(RP2350-Touch-AMOLED-1.8 "0.1")

pico_enable_stdio_uart(RP2350-Touch-AMOLED-1.8 0)
pico_enable_stdio_usb(RP2350-Touch-AMOLED-1.8 1)

add_compile_options(-O2)

target_link_libraries(RP2350-Touch-AMOLED-1.8
  pico_stdlib
  hardware_pio
  hardware_dma
)

target_include_directories(RP2350-Touch-AMOLED-1.8 PRIVATE
  ${CMAKE_CURRENT_LIST_DIR}
)

pico_add_extra_outputs(RP2350-Touch-AMOLED-1.8)

