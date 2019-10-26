module tl45_register_read(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall, // If i_pipe_stall is high, don't clock buffer.
    i_pipe_flush, o_pipe_flush, // Forward the flush, and clear the buffer
    // Buffer from previous stage
    i_opcode, 
    i_ri, // Register Immediate Mode
    i_dr, i_sr1, i_sr2, i_imm32, i_pc,
    // DPRF Connections
    o_dprf_read_a1, o_dprf_read_a2,
    i_dprf_d1, i_dprf_d2,
    o_dprf_setbusy,
    i_dprf_busylist,
    // Operand Forwarding Buses
    i_of1_reg, i_of1_data,
    i_of2_reg, i_of2_data,

    // Output buffer from current stage
    o_opcode,
    o_dr, o_sr1, o_sr2,
    o_sr1_val, o_sr2_val,
    o_pc
);
// CPU Signals
input wire i_clk, i_reset;
input wire i_pipe_stall, i_pipe_flush;
output wire o_pipe_stall, o_pipe_flush;

// Previous stage input signal
input wire [4:0] i_opcode; // 5bit opcode
input wire i_ri; // Register(0) / Immediate(1) Addressing Mode
input wire [3:0] i_dr, i_sr1, i_sr2; // DR(FLAGS), SR1, SR2 address
input wire [31:0] i_imm32, i_pc;

// DPRF Signals
output wire [3:0] o_dprf_read_a1, o_dprf_read_a2;
input wire [31:0] i_dprf_d1, i_dprf_d2;
output wire [3:0] o_dprf_setbusy;
input wire [14:0] i_dprf_busylist; 

input wire [3:0] i_of1_reg, i_of2_reg;
input wire [31:0] i_of1_data, i_of2_data;

// Stage Buffer
output reg [4:0] o_opcode;
output reg [3:0] o_dr, o_sr1, o_sr2;
output reg [31:0] o_sr1_val, o_sr2_val, o_pc;

// Handle Stalls
// This module should not generate stalls or flush, so just pass through
assign o_pipe_stall = i_pipe_stall;
assign o_pipe_flush = i_pipe_flush;

// DPRF Reading Stuff
assign o_dprf_read_a1 = i_sr1;
assign o_dprf_read_a2 = i_sr2;

wire ignoreDRBusy;
assign ignoreDRBusy = (i_opcode == 5'h0C) || (i_opcode == 5'h0);

// If Busy is not ignored, then it should be set
assign o_dprf_setbusy = (ignoreDRBusy) ? (4'h0) : (i_dr);

always @(posedge i_clk)
if (i_reset || i_pipe_flush) begin
    { o_opcode, o_dr, o_sr1, o_sr2, o_sr1_val, o_sr2_val, o_pc } <= 0;
    // Clear Buffer
end
else if (!i_pipe_stall) begin
    o_opcode <= i_opcode;
    o_dr <= i_dr;
    // SR1 Operand Forwarding Checking
    if ((i_sr1 == 0) || (!i_dprf_busylist[i_sr1 - 1])) begin // SR1 Fully Decode
        o_sr1 <= 4'h0;
        o_sr1_val <= i_dprf_d1;
    end else if (i_of1_reg == i_sr1) begin
        o_sr1 <= 4'h0;
        o_sr1_val <= i_of1_data;
    end else if (i_of2_reg == i_sr1) begin
        o_sr1 <= 4'h0;
        o_sr1_val <= i_of2_data;
    end
    else begin
        o_sr1_val <= 0;
        o_sr1 <= i_sr1;
    end

    // SR2 Operand Forwarding Checking
    // Skip check if in IMM Mode
    if (i_ri) begin // IMM Mode
        o_sr2_val <= i_imm32;
        o_sr2 <= 0;
    end
    else if ((i_sr2 == 0) || (!i_dprf_busylist[i_sr2 - 1])) begin // SR2 Fully Decode
        o_sr2 <= 4'h0;
        o_sr2_val <= i_dprf_d2;
    end else if (i_of1_reg == i_sr2) begin // Operand Fwd from BUS#1
        o_sr2 <= 4'h0;
        o_sr2_val <= i_of1_data;
    end else if (i_of2_reg == i_sr2) begin // Operand Fwd from BUS#2
        o_sr2 <= 4'h0;
        o_sr2_val <= i_of2_data;
    end
    else begin // Failed to Fwd, honestly should not happen.
        o_sr1_val <= 0;
        o_sr1 <= i_sr1;
    end
end

endmodule