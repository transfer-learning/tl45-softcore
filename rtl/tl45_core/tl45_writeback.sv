`default_nettype none

module tl45_writeback(
    i_clk, i_reset,
    o_pipe_stall,

    // Buffer In
    i_buf_dr, i_buf_val,

    // Forwarding Out
    o_fwd_reg, o_fwd_val,

    // Reg Write
    o_rf_en, o_rf_reg, o_rf_val
);

input wire i_clk, i_reset;
input wire i_pipe_stall;
output wire o_pipe_stall;
initial o_pipe_stall = 0;

input wire [3:0] i_buf_dr;
input wire [31:0] i_buf_val;

output reg [3:0] o_fwd_reg;
output reg [31:0] o_fwd_val;

assign o_pipe_stall = 0;

initial begin
    o_fwd_reg = 0;
    o_fwd_val = 0;
end

wire do_write = i_buf_dr != 0;

always @(posedge i_clk) begin
    if (i_reset) begin
        o_fwd_reg <= 0;
        o_fwd_val <= 0;
        o_rf_en   <= 0;
        o_rf_reg  <= 0;
        o_rf_val  <= 0;
    else begin
        o_fwd_reg <= i_buf_dr;
        o_fwd_val <= i_buf_val;

        o_rf_en  <= do_write;
        o_rf_reg <= i_buf_dr;
        o_rf_val <= i_buf_val;
    end
end

endmodule


