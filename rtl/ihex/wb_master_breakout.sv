module wb_master_breakout
(
    input ack, err, stall,
    input [31:0] miso_data,
    output wire stb, cyc, we,
    output wire [3:0] sel, 
    output wire [29:0] addr, 
    output wire [31:0] mosi_data,
    wishbone wb
);

assign wb.ack = ack;
assign wb.err = err;
assign wb.stall = stall;
assign wb.miso_data = miso_data;
assign we = wb.we;
assign stb = wb.stb;
assign cyc = wb.cyc;
assign sel = wb.sel;
assign addr = wb.addr;
assign mosi_data = wb.mosi_data;

endmodule
