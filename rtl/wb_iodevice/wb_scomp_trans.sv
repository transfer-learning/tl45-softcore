module wb_scomp_trans(
    i_clk, i_reset,
    i_wb_cyc, i_wb_stb, i_wb_we, 
    i_wb_addr, i_wb_data, i_wb_sel,
    o_wb_ack, o_wb_stall, 
    o_wb_data,

    o_sc_iocyc,
    o_sc_iowr,
    o_sc_ioaddr,
    io_sc_iodata
);
    input	wire    i_clk, i_reset, i_wb_cyc, i_wb_stb, i_wb_we;
    input	wire	[29:0]	i_wb_addr;
    input	wire	[31:0]	i_wb_data;
    input	wire	[3:0]	i_wb_sel;
    output	reg	    o_wb_ack;
    output	wire		o_wb_stall;
    output	reg	    [31:0] o_wb_data;

    output reg o_sc_iocyc, o_sc_iowr;
    output reg [7:0] o_sc_ioaddr;
    inout wire [15:0] io_sc_iodata;

    initial begin
        o_wb_ack = 0;
        o_wb_data = 0;
    end

    always @(posedge i_clk) begin
        
    end

endmodule