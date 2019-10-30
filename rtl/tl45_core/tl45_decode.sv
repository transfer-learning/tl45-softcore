`default_nettype none

module tl45_decode(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall,
    i_pipe_flush, o_pipe_flush,

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
input wire i_pipe_flush;
output reg o_pipe_flush;
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
assign sr2 = i_buf_inst[15:12];
assign low_imm = i_buf_inst[11:0];
assign mode = {ri, lh, zs};


reg [31:0] resolved_imm;

always @(*)
    case ({lh, zs})
        2'b00: resolved_imm = {16'b0, imm};
        2'b01: resolved_imm = {{16{imm[15]}}, imm};
        default: resolved_imm = {imm, 16'b0}; // lh = 1
    endcase

wire sr2_force_sp;
assign sr2_force_sp = (opcode == 5'h0D) || (opcode == 5'h0E); // CALL and RET require sr2 == sp

// SW must be re-ordered for further stages.
// It is encoded as SW dr, sr1, imm => dr -> MEM[sr1+imm]
// which won't be understood by operand forwarding because
// dr is treated as a read operand.
//
// We fix this by moving dr into sr2 and clearing dr.
// Further stages will execute sr2 -> MEM[sr1+imm].
//
wire inst_sw;
assign inst_sw = (opcode == 5'h15) || (opcode == 5'h13);


reg decode_err;

always @(*)
    case (opcode)
        5'h00: decode_err = i_buf_inst != 0;                            //  NOP
        5'h01,                                                          //  ADD 
        5'h02: decode_err = !ri && ((mode != 0) || (low_imm != 0));     //  SUB

        5'h05: decode_err = ri ? (imm >= 32) : mode != 0;               // SHRA

        5'h06,                                                          //   OR
        5'h07,                                                          //  XOR
        5'h08: decode_err = !ri && ((mode != 0) || (low_imm != 0));     //  AND
        5'h09: decode_err = (mode != 0) || (low_imm != 0);              //  NOT

        5'h0A: decode_err = ri ? (imm >= 32) : mode != 0;               //  SHL
        5'h0B: decode_err = ri ? (imm >= 32) : mode != 0;               //  SHR

        5'h0C: decode_err = (mode != 3'b101);                           //  JMP
        5'h0D: decode_err = (mode != 3'b000);                           // CALL
        5'h0E: decode_err = (mode != 3'b000) || (dr != 4'b1111)         //  RET 
                                || (sr1 != 0) || (imm != 0);
        5'h10: decode_err = (mode != 0) || (sr1 != 0);                  //   IN
        5'h11: decode_err = (mode != 0) || (dr != 0);                   //  OUT

        5'h0F,                                                          //   LBSE
        5'h12,                                                          //   LB
        5'h13,                                                          //   SB
        5'h14,                                                          //   LW
        5'h15: decode_err = (mode != 3'b001);                           //   SW

        default: decode_err = 1'b1;
    endcase

assign o_pipe_stall = i_pipe_stall;
assign o_pipe_flush = i_pipe_flush;

always @(posedge i_clk) begin
    if (i_reset || i_pipe_flush || (decode_err && !i_pipe_stall)) begin
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
        o_buf_pc     <= i_buf_pc;
        o_buf_opcode <= opcode;

        o_buf_ri     <= ri;
        o_buf_dr     <= inst_sw ? 4'b0000 : dr; // dr is moved to sr2 for SW instruction.
        o_buf_sr1    <= sr1;
        o_buf_sr2    <= sr2_force_sp ? 4'b1111 : // CALL/RET: sr2 <- sp
                        (inst_sw ? dr :          //       SW: sr2 <- dr
                        (ri ? 4'b0 :             // I/R flag: sr2 <- 0
                        sr2));                   //     else: sr2 <- sr2  
        o_buf_imm    <= resolved_imm; // ri ? resolved_imm : 32'b0;

    end
end

`ifdef FORMAL
    initial restrict(i_reset);

    reg f_past_valid;

    initial f_past_valid = 1'b0;
    always @(posedge i_clk)
        f_past_valid <= 1'b1;

    always @(posedge i_clk)
    begin
        
        if (f_past_valid && !$past(i_reset) && $past(o_pipe_stall)) begin
            assume($past(i_buf_pc) == i_buf_pc);
            assume($past(i_buf_inst) == i_buf_inst);
        end

        if (f_past_valid && !$past(i_reset) && $past(i_pipe_stall)) begin

            assert($past(o_buf_pc) == o_buf_pc);
            assert($past(o_buf_opcode) == o_buf_opcode);
            assert($past(o_buf_ri) == o_buf_ri);
            assert($past(o_buf_dr) == o_buf_dr);
            assert($past(o_buf_sr1) == o_buf_sr1);
            assert($past(o_buf_sr2) == o_buf_sr2);
            assert($past(o_buf_imm) == o_buf_imm);
        end

        if (f_past_valid && $past(i_reset)) begin
            assert({o_buf_pc, o_buf_opcode, o_buf_ri, o_buf_dr, o_buf_sr1, o_buf_sr2, o_buf_imm, o_decode_err} == 0);
        end


    end


`endif


endmodule : tl45_decode







