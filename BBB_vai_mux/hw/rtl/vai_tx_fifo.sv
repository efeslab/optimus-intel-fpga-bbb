import ccip_if_pkg::*;
`include "vendor_defines.vh"

module vai_tx_fifo #(parameter DATA_WIDTH=32)
(
    input logic                         clk,
    input logic                         reset,
    input logic [DATA_WIDTH-1:0]        data_in,
    input logic                         rd_req,
    input logic                         wr_req,

    input logic [15:0]                  add_block_cycle,
    input logic                         add_block_cycle_valid,

    output logic [DATA_WIDTH-1:0]       data_out,
    output logic                        need_rd,
    output logic                        alm_full
)

    wire fifo_empty;
    wire [7:0] usedw;
    logic [15:0] block_cycles;

    scfifo  scfifo_component (
        .aclr (~reset),
        .data (data_in),
        .rdreq (rd_req),
        .clock (clk),
        .wrreq (wr_req),
        .q (data_out),
        .empty(fifo_empty),
        .usedw(usedw)
    );
    defparam
    scfifo_component.enable_ecc  = "FALSE",
    scfifo_component.lpm_hint  = "DISABLE_DCFIFO_EMBEDDED_TIMING_CONSTRAINT=TRUE",
    scfifo_component.lpm_numwords  = 2**8,
    scfifo_component.lpm_showahead  = "ON",
    scfifo_component.lpm_type  = "scfifo",
    scfifo_component.lpm_width  = DATA_WIDTH,
    scfifo_component.lpm_widthu  = 8,
    scfifo_component.overflow_checking  = "ON",
    scfifo_component.underflow_checking  = "ON",
    scfifo_component.use_eab  = "ON";
 
    assign need_rd = (block_cycles == 0) & ~fifo_empty;
    assign alm_full = usedw > ((2**8)-8);

    always_ff @(posedge)
    begin
        if (reset)
        begin
            block_cycles <= 0;
        end
        else
        begin
            if (add_block_cycle_valid)
            begin
                block_cycles <= block_cycles + add_block_cycle;
            end
            else if (block_cycles != 0)
            begin
                block_cycles <= block_cycles - 1;
            end
        end 
    end

endmodule
