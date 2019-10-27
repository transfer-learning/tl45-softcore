`default_nettype none

`define DO_INCLUDE

`ifdef DO_INCLUDE

`include "tl45_dprf.sv"
`include "tl45_nofetch.sv"
`include "tl45_decode.sv"
`include "tl45_register_read.sv"
`include "tl45_alu.sv"
`include "tl45_writeback.sv"
`include "tl45_memory.sv"
`include "memdev.v"

`endif

module tl45_comp(
    i_clk, i_reset,

    inst_decode_err
);
    input wire i_clk, i_reset;
    output wire inst_decode_err;
    
    wire o_wb_cyc, o_wb_stb, o_wb_we;
    wire [29:0] o_wb_addr;
    wire [31:0] o_wb_data;
    wire [3:0] o_wb_sel;
    
    wire i_wb_ack, i_wb_stall, i_wb_err;
    wire [31:0] i_wb_data;

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

    // ALU buffer
    wire [31:0] alu_buf_value;
    wire [3:0] alu_buf_dr;
    wire alu_buf_ld_newpc;
    wire [31:0] alu_buf_br_pc;

    // Mem buffer
    wire [31:0] mem_buf_value;
    wire [3:0] mem_buf_dr;

    // stalls & flushes
    wire stall_fetch_decode, stall_decode_rr, stall_rr_alu, stall_rr_mem, stall_alu_wb;
    wire flush_fetch_decode, flush_decode_rr, flush_rr_alu, flush_rr_mem;

    // Forwarding
    wire [3:0] of1_reg, of1_reg_alu, of1_reg_mem, of2_reg;
    wire [31:0] of1_val, of1_val_alu, of1_val_mem, of2_val;

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
        .i_pipe_flush(flush_fetch_decode),
        .i_new_pc(alu_buf_ld_newpc),
        .i_pc(alu_buf_br_pc),
        .o_buf_pc(fetch_buf_pc),
        .o_buf_inst(fetch_buf_inst)
    );

    tl45_decode decode(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .o_pipe_stall(stall_fetch_decode),
        .i_pipe_stall(stall_decode_rr),
        .o_pipe_flush(flush_fetch_decode),
        .i_pipe_flush(flush_decode_rr),

        .i_buf_pc(fetch_buf_pc),
        .i_buf_inst(fetch_buf_inst),

        .o_buf_pc(decode_buf_pc),
        .o_buf_opcode(decode_buf_opcode),
        .o_buf_ri(decode_buf_ri),
        .o_buf_dr(decode_buf_dr),
        .o_buf_sr1(decode_buf_sr1),
        .o_buf_sr2(decode_buf_sr2),
        .o_buf_imm(decode_buf_imm),

        .o_decode_err(inst_decode_err)
    );

    tl45_register_read rr(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pipe_stall(stall_rr_alu || stall_rr_mem),
        .o_pipe_stall(stall_decode_rr),
        .i_pipe_flush(flush_rr_alu || flush_rr_mem),
        .o_pipe_flush(flush_decode_rr),

        .i_opcode(decode_buf_opcode),
        .i_ri(decode_buf_ri),
        .i_dr(decode_buf_dr),
        .i_sr1(decode_buf_sr1),
        .i_sr2(decode_buf_sr2),
        .i_imm32(decode_buf_imm),
        .i_pc(decode_buf_pc),

        .o_dprf_read_a1(dprf_reg1),
        .o_dprf_read_a2(dprf_reg2),
        .i_dprf_d1(dprf_reg1_val),
        .i_dprf_d2(dprf_reg2_val),

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

    assign of1_reg = of1_reg_alu != 0 ? of1_reg_alu : of1_reg_mem;
    assign of1_val = of1_reg_alu != 0 ? of1_val_alu : of1_val_mem;

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

        .o_of_reg(of1_reg_alu),
        .o_of_val(of1_val_alu),

        .o_dr(alu_buf_dr),
        .o_value(alu_buf_value),
        .o_ld_newpc(alu_buf_ld_newpc),
        .o_br_pc(alu_buf_br_pc)
    );

    tl45_memory memory(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_pipe_stall(stall_alu_wb),
        .o_pipe_stall(stall_rr_mem),
        .i_pipe_flush(0),
        .o_pipe_flush(flush_rr_mem),

        // TOOD wishbone
        .o_wb_cyc(o_wb_cyc),
        .o_wb_stb(o_wb_stb),
        .o_wb_we(o_wb_we),
        .o_wb_addr(o_wb_addr),
        .o_wb_data(o_wb_data),
        .o_wb_sel(o_wb_sel),
        .i_wb_ack(i_wb_ack),
        .i_wb_stall(i_wb_stall),
        .i_wb_err(i_wb_err),
        .i_wb_data(i_wb_data),

        .i_buf_opcode(rr_buf_opcode),
        .i_buf_dr(rr_buf_dr),
        .i_buf_sr1_val(rr_buf_sr1_val),
        .i_buf_sr2_val(rr_buf_sr2_val),
        .i_buf_imm(rr_buf_target_address_offset),

        .o_fwd_dr(of1_reg_mem),
        .o_fwd_val(of1_val_mem),

        .o_buf_dr(mem_buf_dr),
        .o_buf_val(mem_buf_value)

    );

    tl45_writeback writeback(
        .i_clk(i_clk),
        .i_reset(i_reset),
        .o_pipe_stall(stall_alu_wb),

        .i_buf_dr(alu_buf_dr != 0 ? alu_buf_dr : mem_buf_dr),
        .i_buf_val(alu_buf_dr != 0 ? alu_buf_value : mem_buf_value),

        .o_fwd_reg(of2_reg),
        .o_fwd_val(of2_val),

        .o_rf_en(dprf_we_wreg),
        .o_rf_reg(dprf_wreg),
        .o_rf_val(dprf_wreg_val)
    );


    memdev #(16) my_mem(
        .i_clk(i_clk),
        .i_wb_cyc(o_wb_cyc),
        .i_wb_stb(o_wb_stb),
        .i_wb_we(o_wb_we),
        .i_wb_addr(o_wb_addr[15-2:0]),
        .i_wb_data(o_wb_data),
        .i_wb_sel(o_wb_sel),

        .o_wb_ack(i_wb_ack),
        .o_wb_stall(i_wb_stall),
        .o_wb_data(i_wb_data)
    );


    // Misc

//    wire		o_ram_cke;
//	wire		o_ram_cs_n,
//		o_ram_ras_n, o_ram_cas_n, o_ram_we_n;
//	wire	[1:0]	o_ram_bs;
//	wire	[12:0]	o_ram_addr;
//	wire		o_ram_dmod;
//	wire	[15:0]	i_ram_data;
//	wire	[15:0]	o_ram_data;
//	wire	[1:0]	o_ram_dqm;
//	wire [31:0]	o_debug;
//
//    wbsdram sdram(
//        .i_clk(i_clk),
//		.i_wb_cyc(o_wb_cyc),
//        .i_wb_stb(o_wb_stb),
//        .i_wb_we(o_wb_we),
//        .i_wb_addr(o_wb_addr),
//        .i_wb_data(o_wb_data),
//        .i_wb_sel(o_wb_sel),
//        .o_wb_ack(i_wb_ack),
//        .o_wb_stall(i_wb_stall),
//        .o_wb_data(i_wb_data),
//
//        .o_ram_cs_n(o_ram_cs_n),
//        .o_ram_cke(o_ram_cke),
//        .o_ram_ras_n(o_ram_ras_n),
//        .o_ram_cas_n(o_ram_cas_n),
//        .o_ram_we_n(o_ram_we_n),
//        .o_ram_bs(o_ram_bs),
//        .o_ram_addr(o_ram_addr),
//        .o_ram_dmod(o_ram_dmod),
//        .i_ram_data(i_ram_data),
//        .o_ram_data(o_ram_data),
//        .o_ram_dqm(o_ram_dqm),
//
//		.o_debug(o_debug)
//    );
//
//    wire [15:0] dq;
//
//    assign i_ram_data = dq;
//    assign dq = o_ram_we_n ? o_ram_data : 32'hzzzz;
//
//
//    IS42VM16400K issi(
//        .dq(dq),
//        .addr(o_ram_addr),
//        .ba(o_ram_bs),
//        .clk(i_clk),
//        .cke(o_ram_cke),
//        .csb(o_ram_cs_n),
//        .rasb(o_ram_ras_n),
//        .casb(o_ram_cas_n),
//        .web(o_ram_we_n),
//        .dqm(o_ram_dqm)
//    );

endmodule : tl45_comp

