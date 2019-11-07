module wb_quad_encoder(
    i_clk, i_reset, 
    i_wb_cyc, i_wb_stb, i_wb_we, 
    i_wb_addr, i_wb_data, i_wb_sel,
    o_wb_ack, o_wb_stall, 
    o_wb_data,
    quadA, quadB, count);
input	wire    i_clk, i_reset, i_wb_cyc, i_wb_stb, i_wb_we;
input	wire	[29:0]	i_wb_addr;
input	wire	[31:0]	i_wb_data;
input	wire	[3:0]	i_wb_sel;
output	wire	 o_wb_ack;
output	wire    o_wb_stall;
output	reg	    [31:0] o_wb_data;

input wire quadA, quadB;
output reg [31:0] count;

reg [2:0] quadA_delayed, quadB_delayed;
initial begin
    count = 0;
    quadA_delayed = 0;
    quadB_delayed = 0;
end
// 2FF Sync
always @(posedge i_clk) quadA_delayed <= {quadA_delayed[1:0], quadA};
always @(posedge i_clk) quadB_delayed <= {quadB_delayed[1:0], quadB};

wire count_enable = quadA_delayed[1] ^ quadA_delayed[2] ^ quadB_delayed[1] ^ quadB_delayed[2];
wire count_direction = quadA_delayed[1] ^ quadB_delayed[2];

always @(posedge i_clk)
begin
    if (i_reset || (i_wb_stb && i_wb_we && i_wb_cyc)) // Reset Counter on System reset or write
        count <= 0;
    else if(count_enable)
        if(count_direction) count<=count+1; else count<=count-1;
end

localparam IDLE = 0,
            WBACK = 1;
reg [3:0] current_state;
initial begin
    current_state = IDLE;
end

assign o_wb_ack = current_state == WBACK;
assign o_wb_stall = current_state != IDLE;

// WB State Machine
always @(posedge i_clk) begin
    if (i_reset) begin
        current_state <= IDLE;
        o_wb_data <= 0;
    end else if (current_state == IDLE && i_wb_stb && i_wb_cyc) begin
        o_wb_data <= count;
        current_state <= WBACK;
    end else if (current_state == WBACK) begin
        o_wb_data <= 0;
        current_state <= IDLE;
    end
end

endmodule