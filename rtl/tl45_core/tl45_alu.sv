`default_nettype none

module tl45_alu(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall, // If i_pipe_stall is high, don't clock buffer.
    i_pipe_flush, o_pipe_flush, // Forward the flush, and clear the buffer
    // Buffer from previous stage
    i_opcode,
    i_dr,
    i_jmp_cond,
    i_sr1_val, i_sr2_val,
    i_target_offset,
    i_pc,
    // Operand Forward Outputs
    o_of_reg, o_of_val,
    // Current stage buffer
    o_dr, o_value, o_ld_newpc, o_br_pc
);
input wire i_clk, i_reset;
input wire i_pipe_stall, i_pipe_flush;
output wire o_pipe_flush, o_pipe_stall;

reg stall_previous_stage;
wire flush_previous_stage;
initial begin
    stall_previous_stage = 0;
end
// Flush Previous Stages when 1) we stall OR Upper stage stalls
assign o_pipe_stall = i_pipe_stall || stall_previous_stage;
// Same with flush
assign o_pipe_flush = flush_previous_stage || i_pipe_flush;

// Input From previous stage
input wire [4:0] i_opcode;
input wire [3:0] i_dr;
input wire [31:0] i_sr1_val, i_sr2_val,
                  i_target_offset, i_pc;
input wire [3:0] i_jmp_cond;

// Operand Forward
output wire [3:0] o_of_reg;
output wire [31:0] o_of_val;

// Output to Next Stage
output reg [31:0] o_value;
output reg [3:0] o_dr;
output wire o_ld_newpc;
output reg [31:0] o_br_pc;

initial begin
    o_value = 0;
    o_dr = 0;
    o_br_pc = 0;
end

// Core ALU Logic

// TL45 Opcodes
localparam OP_ADD = 5'h1,
           OP_SUB = 5'h2,
           OP_OR  = 5'h6,
           OP_XOR = 5'h7,
           OP_AND = 5'h8,
           OP_NOT = 5'h9;

// Check if branch is executing
wire is_branch;
assign is_branch = i_opcode == 5'h0C; // Branch

// ALU Operation Decode from Opcode
reg [3:0] alu_op;
localparam ALUOP_NOP = 0,
           ALUOP_ADD = 1,
           ALUOP_SUB = 2,
           ALUOP_AND = 3,
           ALUOP_OR  = 4,
           ALUOP_XOR = 5,
           ALUOP_NOTA= 6,
           ALUOP_AINC= 7;

// select alu op
always @(*)
    case(i_opcode)
    OP_ADD: alu_op = ALUOP_ADD;
    OP_SUB: alu_op = ALUOP_SUB;
    OP_AND: alu_op = ALUOP_AND;
    OP_OR: alu_op = ALUOP_OR;
    OP_XOR: alu_op = ALUOP_XOR;
    OP_NOT: alu_op = ALUOP_NOTA;
    default: alu_op = ALUOP_NOP;
    endcase

// optional b 2complememt
reg [31:0] opt_b_2complement;
// ALU Computaion Result
reg [31:0] alu_result;

// Handle Flags
wire flg_overflow;
wire flg_carry;
wire flg_zero;
wire flg_sign;

reg set_overflow;
reg carry_value;
reg set_flags;

// set flags
always @(*) begin
    case(i_opcode)
        OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_NOT: set_flags = 1;
        default: set_flags = 0;
    endcase
    case (i_opcode)
        OP_ADD, OP_SUB: set_overflow = 1;
        default: set_overflow = 0;
    endcase
end


// Combinational Logic for calculating opt_b_2comp
// 2 complement is computed if op==subtract
always @(*) begin
    opt_b_2complement = (alu_op == ALUOP_SUB) ? (~i_sr2_val + 1) : i_sr2_val;
end

// Main ALU
always @(*) begin
    case(alu_op)
        ALUOP_ADD, ALUOP_SUB: {carry_value, alu_result} = i_sr1_val + opt_b_2complement;
        ALUOP_AND: alu_result = i_sr1_val & i_sr2_val;
        ALUOP_OR: alu_result = i_sr1_val | i_sr2_val;
        ALUOP_XOR: alu_result = i_sr1_val ^ i_sr2_val;
        ALUOP_NOTA: alu_result = ~i_sr1_val;
        default: alu_result = i_sr1_val;
    endcase
end

// Actual Flags
assign flg_overflow = set_overflow & 
                      ((i_sr1_val[31] & opt_b_2complement[31]) ^ alu_result[31]) &
                       (i_sr1_val[31] & opt_b_2complement[31]
                      );
assign flg_carry = set_overflow & carry_value;
assign flg_zero = (alu_result == 0);
assign flg_sign = alu_result[31];

// Flag Register
reg [3:0] flags; // {of, zf, cf, sf}
initial flags = 0;

// JUMP Logic
wire j_OF, j_ZF, j_CF, j_SF;
assign {j_OF, j_ZF, j_CF, j_SF} = flags;
reg do_jump;

always @(*) begin
    case(i_jmp_cond)
        0: do_jump = j_OF; // jo
        1: do_jump = ~j_OF; // jno
        2: do_jump = j_SF; // js
        3: do_jump = ~j_SF; // jns
        4: do_jump = j_ZF; // je
        5: do_jump = ~j_ZF; // jne
        6: do_jump = j_CF; // je
        7: do_jump = ~j_CF; // jne
        8: do_jump = (j_CF|j_ZF); // jbe
        9: do_jump = (~j_CF) && (~j_ZF); // ja
        10:do_jump = j_SF ^ j_OF; // jl
        11:do_jump = (j_SF == j_OF); // jge
        12:do_jump = j_ZF || (j_SF ^ j_OF); // jle
        13:do_jump = (~j_ZF) && (j_SF == j_OF); // jg
        default: do_jump = 1; // jmp
    endcase
end

// Target Address Computation
always @(*) begin
    o_br_pc = i_sr1_val + i_target_offset;
end

assign flush_previous_stage = is_branch && do_jump; // Controlls JUMP
assign o_ld_newpc = is_branch && do_jump; // when jump happens, loads new PC

always @(posedge i_clk) begin
    if (is_branch) begin
        // Branch Logic
        o_dr <= 4'h0; // Branch never writes to DR
        o_value <= 0;
    end
    else begin
        // ALU Logic
        if (set_flags)
            flags <= {flg_overflow, flg_zero, flg_carry, flg_sign};
        o_dr <= i_dr;
        o_value <= alu_result;
    end 
end

assign o_of_reg = i_dr;
assign o_of_val = alu_result;

`ifdef FORMAL

reg f_past_valid;
initial f_past_valid = 0;

always @(posedge i_clk)
    f_past_valid <= 1;

always @(posedge i_clk) begin
if (f_past_valid)
    if ($past(o_pipe_flush)) begin // Assume correct previous stage flush behavior
        assume(i_dr == 0);
        assume(i_jmp_cond == 0);
        assume(i_sr1_val == 0);
        assume(i_sr2_val == 0);
        assume(i_target_offset == 0);
        assume(i_opcode == 0);
    end else if ($past(o_pipe_stall)) begin // Assume correct behavior from previous stage for stall
        assume(i_dr == $past(i_dr));
        assume(i_jmp_cond == $past(i_jmp_cond));
        assume(i_opcode == $past(i_opcode));
        assume(i_target_offset == $past(i_target_offset));
        assume(i_sr1_val == $past(i_sr1_val));
        assume(i_sr2_val == $past(i_sr2_val));
    end
end

always @(posedge i_clk) begin
if(f_past_valid)
    if ($past(is_branch)) begin
        assert(o_dr == 0);
        assert(o_value == 0);
    end
end

always @(*) begin
    if (do_jump && is_branch) begin
        assert(o_pipe_flush);
        assert(o_ld_newpc);
        assert(o_br_pc == i_sr1_val + i_target_offset);
    end
end

`endif

endmodule