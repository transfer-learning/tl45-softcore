`default_nettype none



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
    // Operand Forwarding Buses
    i_of1_reg, i_of1_data, // Operand Forwarding Bus #1 BEFORE ALU BUF
    i_of2_reg, i_of2_data, // Operand Forwarding Bus #2 AT ALU BUF
    // Output buffer from current stage
    o_opcode,
    o_dr, o_jmp_cond,
    o_sr1_val, o_sr2_val,
    o_target_address_offset,
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

input wire [3:0] i_of1_reg, i_of2_reg;
input wire [31:0] i_of1_data, i_of2_data;

// Stage Buffer
output reg [4:0] o_opcode;
output reg [3:0] o_dr;
output reg [3:0] o_jmp_cond;
output reg [31:0] o_sr1_val, o_sr2_val, o_pc;
output reg [31:0] o_target_address_offset; // Target Jump Address Offset

initial begin
    o_opcode = 0;
    o_dr = 0;
    o_sr1_val = 0;
    o_sr2_val = 0;
    o_pc = 0;
    o_jmp_cond = 0;
    o_target_address_offset = 0;
end

// Handle Stalls
// This module should not generate stalls or flush, so just pass through
assign o_pipe_stall = i_pipe_stall;
assign o_pipe_flush = i_pipe_flush;

// DPRF Reading Stuff
assign o_dprf_read_a1 = i_sr1;
assign o_dprf_read_a2 = i_sr2;

wire is_branch;
assign is_branch = i_opcode == 5'h0C;

always @(posedge i_clk) begin
    if (i_reset || i_pipe_flush) begin
        // Clear Buffer
        o_opcode <= 0;
        o_dr <= 0;
        o_sr1_val <= 0;
        o_sr2_val <= 0;
        o_pc <= 0;
    end
    else if (!i_pipe_stall) begin
        o_target_address_offset <= i_imm32;
        o_opcode <= i_opcode;
        o_pc <= i_pc;
        if (is_branch) begin
            o_dr <= 4'h0;
            o_jmp_cond <= i_dr;
        end else begin
            o_dr <= i_dr;
            o_jmp_cond <= 4'h0;
        end
        // SR1 Operand Forwarding Checking
        // LOGIC:
        // -> 1) if OpFwdBus1 has the register value, load that
        //      it comes from the ALU BEFORE ALU Buffer
        // -> 2) if the OpFwdBus2 has the register value, load
        //      that. It comes from ALU AFTER ALU Buffer
        // -> 3) Otherwise trust the value coming from the DPRF
        if ((i_sr1 != 4'h0) && (i_of1_reg == i_sr1)) begin
            o_sr1_val <= i_of1_data;
        end else if ((i_sr1 != 4'h0) && (i_sr1 == i_of2_reg)) begin
            o_sr1_val <= i_of2_data;
        end
        else begin
            o_sr1_val <= i_dprf_d1;
        end

        // SR2 Operand Forwarding Checking
        // Skip check if in IMM Mode
        if (i_ri) begin // IMM Mode
            o_sr2_val <= i_imm32;
        end else if ((i_sr2 != 4'h0) && (i_sr2 == i_of1_reg)) begin // Operand Fwd from BUS#1
            o_sr2_val <= i_of1_data;
        end else if ((i_sr2 != 4'h0) && (i_sr2 == i_of2_reg)) begin // Operand Fwd from BUS#2
            o_sr2_val <= i_of2_data;
        end else begin // Trust the value from the dprf
            o_sr2_val <= i_dprf_d2;
        end
    end
end

`ifdef FORMAL

reg f_past_valid;
initial f_past_valid = 0;

always @(posedge i_clk)
    assume(i_reset == !f_past_valid);

always @(posedge i_clk)
    f_past_valid <= 1;

always @(*) begin
    if (i_pipe_stall) assert (o_pipe_stall);
    if (i_pipe_flush) assert (o_pipe_flush);
end

always @(posedge i_clk) begin
    if (f_past_valid && $past(i_pipe_flush)) begin
        assert(o_opcode == 0); // Check NoOp
    end
    if (f_past_valid && $past(i_pipe_stall) && !$past(i_pipe_flush) && !$past(i_reset))
        assert(o_opcode == $past(o_opcode));
end

always @(posedge i_clk) begin
    if (f_past_valid && !$past(i_pipe_flush) && !$past(i_pipe_stall) && !$past(i_reset)) begin
        assert ($past(i_opcode) == o_opcode);
        assert ($past(i_imm32) == o_target_address_offset);
        if ($past(is_branch)) begin
            assert(o_jmp_cond == $past(i_dr));
            assert(o_dr == 4'h0);
        end
        else
            assert (o_dr == $past(i_dr));
    end
end

always @(*) begin // DPRF Assumption
    if (o_dprf_read_a1 == 4'h0)
        assume(i_dprf_d1 == 0);
    if (o_dprf_read_a2 == 4'h0)
        assume(i_dprf_d2 == 0);
end

always @(posedge i_clk) begin
    // Check if Operand Forward works on SR1
    if (f_past_valid && !$past(i_pipe_stall) && !$past(i_pipe_flush) && !$past(i_reset)) begin
        if ($past(i_sr1) == 4'h0)
            assert(o_sr1_val == 32'h0); // Zero always produces zero
        else if ($past(i_of1_reg) == $past(i_sr1))
            assert(o_sr1_val == $past(i_of1_data));
        else if ($past(i_of2_reg) == $past(i_sr1))
            assert(o_sr1_val == $past(i_of2_data));
        else
            assert(o_sr1_val == $past(i_dprf_d1));
    end

    // Check if Operand Forward works on SR2
    if (f_past_valid && !$past(i_pipe_stall) && !$past(i_pipe_flush) && !$past(i_reset)) begin
        if ($past(i_ri)) // Immediate Mode SR2 Always gets immediate
            assert(o_sr2_val == $past(i_imm32));
        else if ($past(i_sr2) == 4'h0) // Zero produces zero
            assert(o_sr2_val == 32'h0);
        else if ($past(i_of1_reg) == $past(i_sr2)) // Bus 1 FWD
            assert(o_sr2_val == $past(i_of1_data));
        else if ($past(i_of2_reg) == $past(i_sr2)) // Bus 2 FWD
            assert(o_sr2_val == $past(i_of2_data));
        else
            assert(o_sr2_val == $past(i_dprf_d2)); // Reg Read
    end
end

`endif

endmodule