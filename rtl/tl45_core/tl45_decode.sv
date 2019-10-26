`default_nettype none

module tl45_decode(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall,

    // Buffer In
    i_buf_pc, i_buf_inst,

    // Buffer Out
    o_buf_pc,
    o_buf_opcode, o_buf_ri,
    o_buf_dr, o_buf_sr1, o_buf_sr2,
    o_buf_imm,
    
    // Misc
    o_decode_err
);

input wire i_clk, i_reset;
input wire i_pipe_stall;
output reg o_pipe_stall;
initial o_pipe_stall = 0;

input wire [31:0] i_buf_pc, i_buf_inst;

output reg [31:0] o_buf_pc;
output reg [4:0] o_buf_opcode;
output reg o_buf_ri;
output reg [3:0] o_buf_dr, o_buf_sr1, o_buf_sr2;
output reg [31:0] o_buf_imm;

output reg o_decode_err;

initial begin
    o_buf_pc = 0;
    o_buf_opcode = 0;
    o_buf_ri = 0;
    o_buf_dr = 0;
    o_buf_sr1 = 0;
    o_buf_sr2 = 0;
    o_buf_imm = 0;
end

// internal decoding, not always valid
wire [4:0] opcode;
wire ri, lh, zs;
wire [2:0] mode;
wire [3:0] dr, sr1, sr2;
wire [15:0] imm;
wire [11:0] low_imm; // portion of imm not conflicting with sr2
assign {opcode, ri, lh, zs, dr, sr1, imm} = i_buf_inst;
assign sr2 = i_buf_inst[19:16];
assign mode = {ri, lh, zs};


wire [31:0] resolved_imm;

always @(*)
    case ({lh, zs})
        2'b00: resolved_imm = {16'b0, imm};
        2'b01: resolved_imm = {{16{imm[15]}}, imm};
        default: resolved_imm = {imm, 16'b0}; // lh = 1
    endcase

wire decode_err;

always @(*)
    case (opcode)
        5'h00: decode_err = i_buf_inst != 0;                                   //  NOP
        5'h01,                                                          //  ADD 
        5'h02,                                                          //  SUB
        
        5'h05,                                                          //  CMP
        5'h06,                                                          //   OR
        5'h07,                                                          //  XOR
        5'h08: decode_err = !ri && ((mode != 0) || (low_imm != 0));    //  AND
        5'h09: decode_err = (mode != 0) || (low_imm != 0);             //  NOT
    
        5'h0C,                                                          //  JMP
        5'h0D: decode_err = (mode != 3'b001);                          // CALL
        5'h0E: decode_err = (mode != 3'b000) || (dr != 4'b1111)        //  RET 
                                || (sr1 != 0) || (imm != 0);
        5'h10: decode_err = (mode != 0) || (sr1 != 0);                 //   IN
        5'h11: decode_err = (mode != 0) || (dr != 0);                  //  OUT

        5'h14,                                                          //   LW
        5'h15: decode_err = (mode != 3'b001);                          //   SW

        default: decode_err = 1'b1;
    endcase


always @(posedge i_clk) begin
    if (i_reset || decode_err) begin
        o_pipe_stall <= 0;
        o_buf_pc     <= 0;
        o_buf_opcode <= 0;
        o_buf_ri     <= 0;
        o_buf_dr     <= 0;
        o_buf_sr1    <= 0;
        o_buf_sr2    <= 0;
        o_buf_imm    <= 0;
        o_decode_err <= !i_reset && decode_err;
    end
    else if (!i_pipe_stall) begin
        o_pipe_stall <= 0;
        o_buf_pc     <= i_buf_pc;
        o_buf_opcode <= opcode;

        o_buf_ri     <= ri;
        o_buf_dr     <= dr;
        o_buf_sr1    <= sr1;
        o_buf_sr2    <= ri ? 4'b0 : sr2;
        o_buf_imm    <= ri ? resolved_imm : 32'b0;

    end
end

endmodule







