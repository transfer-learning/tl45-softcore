module wb_vga
#(
    parameter H_RES = 640,
    parameter V_RES = 480,
    parameter SCALE = 2,
    parameter H_FP = 16,
    parameter H_SYNC = 96,
    parameter H_BP = 48,
    parameter V_FP = 10,
    parameter V_SYNC = 2,
    parameter V_BP = 33
)
(
    input wire i_clk, i_clk_25_125, i_reset,

    input wire i_wb_cyc, i_wb_stb, i_wb_we, 
    input wire [15:0] i_wb_addr, 
    input wire [31:0] i_wb_data,
    input wire [3:0] i_wb_sel,
    output wire o_wb_ack, 

    output wire [7:0] o_r, o_g, o_b,
    output wire o_hsync, o_vsync,
    output wire o_blank
);

localparam H_TOTAL = H_RES + H_FP + H_SYNC + H_BP;
localparam V_TOTAL = V_RES + H_FP + V_SYNC + V_BP;

integer h_cntr, v_cntr;
reg [16:0] ram_loc;
reg [16:0] h_pix;
reg [16:0] v_base;
initial ram_loc = 0;
initial h_pix = 0;
initial v_base = 0;
initial h_cntr = 0;
initial v_cntr = 0;

assign o_blank = h_cntr >= H_RES || v_cntr >= V_RES;
assign o_hsync = h_cntr >= (H_RES + H_FP) && h_cntr < (H_RES + H_FP + H_SYNC);
assign o_vsync = v_cntr >= (V_RES + V_FP) && v_cntr < (V_RES + V_FP + V_SYNC);


always @(posedge i_clk_25_125) begin
if (h_cntr < H_TOTAL) begin
    h_cntr <= h_cntr + 1;
    if (h_cntr[0]) begin
        h_pix <= h_pix + 1;
        ram_loc <= v_base + h_pix + 1;
	 end
end else begin
    h_cntr <= 0;
    h_pix <= 0;
    if (v_cntr < V_TOTAL) begin
        v_cntr <= v_cntr + 1;
        if (v_cntr[0]) begin
            v_base <= v_base + (H_RES / SCALE);
            ram_loc <= v_base + (H_RES / SCALE);
        end else begin
            ram_loc <= v_base;
        end
    end else begin
        v_cntr <= 0;
        v_base <= 0;
        ram_loc <= 0;
    end
end
end


localparam TOTAL_PIXEL = (H_RES / SCALE) * (V_RES / SCALE);
localparam RAM_DEPTH = TOTAL_PIXEL / 2;

// Byte
reg [3:0][7:0] p_buffer [RAM_DEPTH];
reg [15:0] pixel_data;
always @(*) begin
if (ram_loc[0])
    pixel_data = p_buffer[ram_loc[16:1]][1:0];
else
    pixel_data = p_buffer[ram_loc[16:1]][3:2];
end

assign o_r = {pixel_data[15:11], {3{pixel_data[11]}}};
assign o_g = {pixel_data[10: 5], {2{pixel_data[ 5]}}};
assign o_b = {pixel_data[ 4: 0], {3{pixel_data[ 0]}}};

localparam IDLE = 0,
           ACK = 1;
reg [3:0] state;
initial state = IDLE;

assign o_wb_ack = i_wb_cyc && i_wb_stb;

always @(posedge i_clk) begin
    if (i_wb_stb && i_wb_cyc) begin
        if (i_wb_we) begin
            if (i_wb_sel[0]) p_buffer[i_wb_addr][0] <= i_wb_data[7:  0];
            if (i_wb_sel[1]) p_buffer[i_wb_addr][1] <= i_wb_data[15: 8];
            if (i_wb_sel[2]) p_buffer[i_wb_addr][2] <= i_wb_data[23:16];
            if (i_wb_sel[3]) p_buffer[i_wb_addr][3] <= i_wb_data[31:24];
        end
    end
end

endmodule
