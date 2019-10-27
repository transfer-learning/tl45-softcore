`default_nettype none

// `define VERILATOR

`ifdef VERILATOR

`include "tl45_dprf.sv"
`include "tl45_nofetch.sv"
`include "tl45_decode.sv"
`include "tl45_register_read.sv"
`include "tl45_alu.sv"
`include "tl45_writeback.sv"

`endif

module tl45_comp(
    i_clk, i_reset,

    inst_decode_err
);
    input wire i_clk, i_reset;
    output wire decode_err;

    // fetch buffer
    wire [31:0] fetch_buf_pc, fetch_buf_inst;

    // decode buffer
    wire [31:0] decode_buf_pc;
    wire [4:0] decode_buf_opcode;
    wire decode_buf_ri;
    wire [3:0] decode_buf_dr, decode_buf_sr1, decode_buf_sr2;
    wire [31:0] decode_buf_imm;

    // rr buffer
    wire [4:0] rr_buf_opcode;
    wire [3:0] rr_buf_dr;
    wire [3:0] rr_buf_jmp_cond;
    wire [31:0] rr_buf_sr1_val, rr_buf_sr2_val, rr_buf_pc;
    wire [31:0] rr_buf_target_address_offset; // Target Jump Address Offset

    // ALU/Ex buffer
    wire [31:0] alu_buf_value;
    wire [3:0] alu_buf_dr;
    wire alu_buf_ld_newpc;
    wire [31:0] alu_buf_br_pc;

    // stalls & flushes
    wire stall_fetch_decode, stall_decode_rr, stall_rr_alu, stall_alu_wb;
    wire flush_fetch_decode, flush_decode_rr, flush_rr_alu;

    // Forwarding
    wire [3:0] of1_reg, of2_reg;
    wire [31:0] of1_val, of2_val;

    // Shared components

    wire [3:0] dprf_reg1, dprf_reg2, dprf_wreg;
    wire [31:0] dprf_reg1_val, dprf_reg2_val, dprf_wreg_val;
    wire dprf_we_wreg;

    tl45_dprf dprf(
        .clk(i_clk),
        .reset(i_reset),
        .readAdd1(dprf_reg1),
        .readAdd2(dprf_reg2),
        .dataO1(dprf_reg1_val),
        .dataO2(dprf_reg2_val),
        .writeAdd(dprf_wreg),
        .dataI(dprf_wreg_val),
        .wrREG(dprf_we_wreg)
    );


    // Stages

    tl45_nofetch fetch(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pipe_stall(stall_fetch_decode),
        .i_new_pc(0),
        .i_pc(0),
        .o_buf_pc(fetch_buf_pc),
        .o_buf_inst(fetch_buf_inst)
    );

    tl45_decode decode(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .o_pipe_stall(stall_fetch_decode),
        .i_pipe_stall(stall_decode_rr),

        .i_buf_pc(fetch_buf_pc),
        .i_buf_inst(fetch_buf_inst),

        .o_buf_pc(decode_buf_pc),
        .o_buf_opcode(decode_buf_opcode),
        .o_buf_ri(decode_buf_ri),
        .o_buf_dr(decode_buf_dr),
        .o_buf_sr1(decode_buf_sr1),
        .o_buf_sr2(decode_buf_sr2),
        .o_buf_imm(decode_buf_imm),

        .o_decode_err(decode_err)
    );

    tl45_register_read rr(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pipe_stall(stall_rr_alu),
        .o_pipe_stall(stall_decode_rr),
        .i_pipe_flush(flush_rr_alu),
        .o_pipe_flush(flush_decode_rr),

        .i_opcode(decode_buf_opcode),
        .i_ri(decode_buf_ri),
        .i_dr(decode_buf_dr),
        .i_sr1(decode_buf_sr1),
        .i_sr2(decode_buf_sr2),
        .i_imm32(decode_buf_imm),
        .i_pc(decode_buf_pc),

        .i_of1_reg(of1_reg),
        .i_of1_data(of1_val),
        .i_of2_reg(of2_reg),
        .i_of2_data(of2_val),

        .o_opcode(rr_buf_opcode),
        .o_dr(rr_buf_dr),
        .o_jmp_cond(rr_buf_jmp_cond),
        .o_sr1_val(rr_buf_sr1_val),
        .o_sr2_val(rr_buf_sr2_val),
        .o_target_address_offset(rr_buf_target_address_offset),
        .o_pc(rr_buf_pc)
    );

    tl45_alu alu(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pipe_stall(stall_alu_wb),
        .o_pipe_stall(stall_rr_alu),
        .i_pipe_flush(0),
        .o_pipe_flush(flush_rr_alu),

        .i_opcode(rr_buf_opcode),
        .i_dr(rr_buf_dr),
        .i_jmp_cond(rr_buf_jmp_cond),
        .i_sr1_val(rr_buf_sr1_val),
        .i_sr2_val(rr_buf_sr2_val),
        .i_target_offset(rr_buf_target_address_offset),
        .i_pc(rr_buf_pc),

        .o_dr(alu_buf_dr),
        .o_value(alu_buf_value),
        .o_ld_newpc(alu_buf_ld_newpc),
        .o_br_pc(alu_buf_br_pc)
    );

    assign of1_reg = alu_buf_dr;
    assign of1_val = alu_buf_value;

    tl45_writeback writeback(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .o_pipe_stall(stall_alu_wb),

        .i_buf_dr(alu_buf_dr),
        .i_buf_val(alu_buf_value),

        .o_fwd_reg(of2_reg),
        .o_fwd_val(of2_val),

        .o_rf_en(dprf_we_wreg),
        .o_rf_reg(dprf_wreg),
        .o_rf_val(dprf_wreg_val)
    );



endmodule : tl45_comp

