`ifndef __INTERFACE
`define __INTERFACE

interface wishbone#(AW=30, DW=32, SELW=4)();

logic stb, cyc, we;
logic stall, ack, err;
logic [SELW-1:0] sel;
logic [AW-1:0] addr;
logic [DW-1:0] mosi_data, miso_data;

modport master(
    input ack, err, stall, miso_data,
    output stb, cyc, sel, we, addr, mosi_data
);

modport slave(
    output ack, err, stall, miso_data,
    input stb, cyc, sel, addr, we, mosi_data
);

endinterface //wishbone
`endif