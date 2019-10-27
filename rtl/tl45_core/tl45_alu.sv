`default_nettype none

module tl45_alu(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall, // If i_pipe_stall is high, don't clock buffer.
    i_pipe_flush, o_pipe_flush, // Forward the flush, and clear the buffer
    // Buffer from previous stage
    i_opcode,
    i_dr, i_sr1, i_sr2,
    i_sr1_val, i_sr2_val,
    i_pc,
    // Current stage buffer
    o_dr, o_val;
);
input wire i_clk, i_reset;
input wire i_pipe_stall, i_pipe_flush;
output wire o_pipe_flush, o_pipe_stall;

reg stall_previous_stage;
reg flush_previous_stage;
initial begin
    stall_previous_stage = 0;
    flush_previous_stage = 0;
end

// Flush Previous Stages when 1) we stall OR Upper stage stalls
assign o_pipe_stall = i_pipe_stall || stall_previous_stage;
// Same with flush
assign o_pipe_flush = flush_previous_stage || i_pipe_flush;



endmodule