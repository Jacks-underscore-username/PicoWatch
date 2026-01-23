#ifndef HARDWARE_DMA_H
#define HARDWARE_DMA_H

#include <stdbool.h>
#include <stdint.h>

typedef uint32_t dma_channel_t;

dma_channel_t dma_channel_claim(void);
void dma_channel_release(dma_channel_t channel);
void dma_channel_configure(dma_channel_t channel, const void *read_addr,
                           void *write_addr, uint32_t transfer_count,
                           uint32_t ctrl);

#endif