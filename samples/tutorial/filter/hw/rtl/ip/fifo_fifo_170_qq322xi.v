// (C) 2001-2017 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel MegaCore Function License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.



// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module  fifo_fifo_170_qq322xi  (
    clock,
    data,
    rdreq,
    wrreq,
    empty,
    full,
    q,
    usedw);

    input    clock;
    input  [511:0]  data;
    input    rdreq;
    input    wrreq;
    output   empty;
    output   full;
    output [511:0]  q;
    output [4:0]  usedw;

    wire  sub_wire0;
    wire  sub_wire1;
    wire [511:0] sub_wire2;
    wire [4:0] sub_wire3;
    wire  empty = sub_wire0;
    wire  full = sub_wire1;
    wire [511:0] q = sub_wire2[511:0];
    wire [4:0] usedw = sub_wire3[4:0];

    scfifo  scfifo_component (
                .clock (clock),
                .data (data),
                .rdreq (rdreq),
                .wrreq (wrreq),
                .empty (sub_wire0),
                .full (sub_wire1),
                .q (sub_wire2),
                .usedw (sub_wire3),
                .aclr (),
                .almost_empty (),
                .almost_full (),
                .eccstatus (),
                .sclr ());
    defparam
        scfifo_component.add_ram_output_register  = "OFF",
        scfifo_component.enable_ecc  = "FALSE",
        scfifo_component.intended_device_family  = "Arria 10",
        scfifo_component.lpm_numwords  = 32,
        scfifo_component.lpm_showahead  = "OFF",
        scfifo_component.lpm_type  = "scfifo",
        scfifo_component.lpm_width  = 512,
        scfifo_component.lpm_widthu  = 5,
        scfifo_component.overflow_checking  = "ON",
        scfifo_component.underflow_checking  = "ON",
        scfifo_component.use_eab  = "ON";


endmodule


