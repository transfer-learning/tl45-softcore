`ifndef __INTERFACE
`define __INTERFACE

interface wishbone#(AW=30, DW=32, SELW=4)
(
    input i_clk, i_reset
);

logic stb, cyc, we;
logic stall, ack, err;
logic [SELW-1:0] sel;
logic [AW-1:0] addr;
logic [DW-1:0] mosi_data, miso_data;

modport master(
    input i_clk, i_reset,
    input ack, err, stall, miso_data,
    output stb, cyc, sel, we, addr, mosi_data
);

modport slave(
    input i_clk, i_reset,
    output ack, err, stall, miso_data,
    input stb, cyc, sel, addr, we, mosi_data
);

endinterface //wishbone
`endif