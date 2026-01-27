const std = @import("std");
const microzig = @import("microzig");
const usb = @import("usb.zig");
const screen = @import("screen.zig");
const Qspi = @import("qspi_pio.zig");
const AMOLED_1in8 = @import("AMOLED_1in8.zig");

const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const dma = rp2xxx.dma;

pub fn main() !void {
    usb.init();

    while (!usb.ready()) usb.poll();

    // const dma_tx = dma.claim_unused_channel() orelse unreachable;
    // dma_tx.apply()
    // //   dma_tx = dma_claim_unused_channel(true);
    // const c: dma.Channel.TransferConfig = .{
    //     .read_increment = true,
    //     .write_increment = false,
    //     .data_size = .size_8,
    //     .dreq = @enumFromInt(0x63),
    // };
    // //   c = dma_channel_get_default_config(dma_tx);
    // try dma_tx.setup_transfer_raw(0, 0, 0, c);
    // //   channel_config_set_transfer_data_size(&c, DMA_SIZE_8);

    // Qspi.QSPI_GPIO_Init();
    // try Qspi.QSPI_PIO_Init();
    // Qspi.QSPI_4Wrie_Mode();

    // AMOLED_1in8.AMOLED_1IN8_Init();
    // AMOLED_1in8.AMOLED_1IN8_SetBrightness(100);

    var i: u64 = 0;
    var old: u64 = time.get_time_since_boot().to_us();
    var new: u64 = 0;
    while (true) {
        usb.poll();

        new = time.get_time_since_boot().to_us();
        if (new - old > 1_000_000) {
            old = new;

            i += 1;

            usb.log("i: {}\r\n", .{i});
        }
    }
}
