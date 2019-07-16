`include "platform_if.vh"

`ifndef DMA_ENGINE_VH
    `define DMA_ENGINE_VH

    typedef struct packed {
        t_ccip_clAddr  rd_addr;
        t_ccip_clAddr  wr_addr;
        logic [64:0]   rd_len;
        logic [64:0]   wr_len;

        logic          begin_copy;

        logic          rd_ready;
        logic          wr_out;
        logic [512:0]  wr_data;
    } dma_in;

    typedef struct packed {
        logic           finished;

        logic           wr_ready;
        logic           rd_out;
        logic [512:0]   rd_data;
    } dma_out;

    typedef struct packed {
        dma_in         d_in;
        t_if_ccip_Rx   sRx;
    } from_afu;

    typedef struct packed {
        dma_out        d_out;
        t_if_ccip_Tx   sTx;
    } to_afu;

`endif
