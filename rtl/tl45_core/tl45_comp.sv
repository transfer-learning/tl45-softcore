`default_nettype none

`define	UARTSETUP	434	// Must match testbus_tb, =4Mb w/ a 100MHz ck
module tl45_comp(
    i_clk, i_reset,
    i_halt_proc,
    i_uart, o_uart,
    sdram_clk   ,
    sdr_cs_n    ,
    sdr_cke     ,
    sdr_ras_n   ,
    sdr_cas_n   ,
    sdr_we_n    ,
    sdr_dqm     ,
    sdr_ba      ,
    sdr_addr    ,
    sdr_dq      ,
    inst_decode_err,
	 o_valid,
`ifndef VERILATOR
	ssegs,
`endif
    i_sw16,

    o_leds,
    i_switches,

    io_disp_data,
    o_disp_rw,
    o_disp_en_n,
    o_disp_rs,
    o_disp_on_n,
    o_disp_blon,

    sdc_o_cs,
    sdc_o_sck,
    sdc_o_mosi,
    sdc_i_miso,
	 
	 sd_rep_cs,
	 sd_rep_sck,
	 sd_rep_mosi,
	 sd_rep_miso,

    o_vga_hsync,
    o_vga_vsync,
    o_vga_blank,
    o_vga_sync,
    o_vga_clk,
    o_vga_r, o_vga_g, o_vga_b
);
    input i_sw16;
	 
    inout wire [7:0] io_disp_data;
    output wire o_valid;
    output wire o_disp_rw, o_disp_blon, o_disp_en_n, o_disp_on_n, o_disp_rs;
    input wire [15:0] i_switches;
    output wire [15:0] o_leds;
`ifndef VERILATOR
    output wire [6:0] ssegs[8];
`else
    wire [6:0] ssegs[8];
`endif
	input wire i_uart;
	output wire o_uart;
    input wire i_halt_proc;
    input wire i_clk, i_reset;
    output wire inst_decode_err;

    // SDRAM IO
    output wire sdram_clk;
    wire dram_clk_source;
`ifndef VERILATOR
    dram_pll dram_clock_pll(i_clk, sdram_clk);
`endif
    // assign sdram_clk = i_clk;
    output wire sdr_cs_n;
    output wire sdr_cke;
    output wire sdr_ras_n;
    output wire sdr_cas_n;
    output wire sdr_we_n;
    output wire [3:0] sdr_dqm;
    output wire [1:0] sdr_ba;
    output wire [12:0] sdr_addr;
    inout wire [31:0] sdr_dq;

    // SD Card SPI
    output	wire sdc_o_sck, sdc_o_mosi;
    input	wire sdc_i_miso;
    output wire sdc_o_cs;
	 
    output wire sd_rep_cs = sdc_o_cs;
    output wire sd_rep_sck = sdc_o_sck;
    output wire sd_rep_mosi = sdc_o_mosi;
    output wire sd_rep_miso = sdc_i_miso;

    // VGA
    output wire o_vga_blank, o_vga_hsync, o_vga_vsync, o_vga_sync, o_vga_clk;
    output wire [7:0] o_vga_r, o_vga_g, o_vga_b;

	 // RESET
`ifdef VERILATOR
	 wire reset;
    assign reset = i_reset;
`else
	reg reset, reset_buf;
	initial reset = 1;
	initial reset_buf = 1;
	always @(posedge i_clk)
		{reset, reset_buf} <= {reset_buf, ~i_reset};
`endif

	 
    //MEME
    //wire [12:0] sdr_addr_fake;
    //assign sdr_addr = sdr_addr_fake[11:0];

    // Memory Bus Hierarchy
    // * - denotes higher priority
    // Right side are masters, left are slaves
    //
    // Memory - | - debug
    //          |
    //          |
    //     IO - |*-*| - ifetch
    //          :   |
    //          :   |
    //          :   |*-*dfetch
    //
    //     main ^   ^ internal
    //   (master)       (ibus)
    //

    // master Wishbone
    wire master_o_wb_cyc, master_o_wb_stb, master_o_wb_we;
    wire [29:0] master_o_wb_addr;
    wire [31:0] master_o_wb_data;
    wire [3:0] master_o_wb_sel;

    reg master_i_wb_ack, master_i_wb_err;
    wire master_i_wb_stall;
    reg [31:0] master_i_wb_data;


    // dbgbus Wishbone
    wire dbgbus_o_wb_cyc, dbgbus_o_wb_stb, dbgbus_o_wb_we;
    wire [29:0] dbgbus_o_wb_addr;
    wire [31:0] dbgbus_o_wb_data;
    wire [3:0] dbgbus_o_wb_sel;

    wire dbgbus_i_wb_ack, dbgbus_i_wb_stall, dbgbus_i_wb_err;
    wire [31:0] dbgbus_i_wb_data;
    // ibus Wishbone
    wire ibus_o_wb_cyc, ibus_o_wb_stb, ibus_o_wb_we;
    wire [29:0] ibus_o_wb_addr;
    wire [31:0] ibus_o_wb_data;
    wire [3:0] ibus_o_wb_sel;

    wire ibus_i_wb_ack, ibus_i_wb_stall, ibus_i_wb_err;
    wire [31:0] ibus_i_wb_data;

    // ifetch Wishbone
    wire ifetch_o_wb_cyc, ifetch_o_wb_stb, ifetch_o_wb_we;
    wire [29:0] ifetch_o_wb_addr;
    wire [31:0] ifetch_o_wb_data;
    wire [3:0] ifetch_o_wb_sel;

    wire ifetch_i_wb_ack, ifetch_i_wb_stall, ifetch_i_wb_err;
    wire [31:0] ifetch_i_wb_data;

    // dfetch Wishbone
    wire dfetch_o_wb_cyc, dfetch_o_wb_stb, dfetch_o_wb_we;
    wire [29:0] dfetch_o_wb_addr;
    wire [31:0] dfetch_o_wb_data;
    wire [3:0] dfetch_o_wb_sel;
    
    wire dfetch_i_wb_ack, dfetch_i_wb_stall, dfetch_i_wb_err;
    wire [31:0] dfetch_i_wb_data;

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

    wire mem_buf_ld_newpc;
    wire [31:0] mem_buf_br_pc;

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
        .reset(reset),
        .readAdd1(dprf_reg1),
        .readAdd2(dprf_reg2),
        .dataO1(dprf_reg1_val),
        .dataO2(dprf_reg2_val),
        .writeAdd(dprf_wreg),
        .dataI(dprf_wreg_val)
	  );


    // Stages

    // tl45_prefetch
    tl45_pfetch_with_cache fetch(
        .i_clk(i_clk),
        .i_reset(reset),
        .i_pipe_stall(stall_fetch_decode),
        .i_pipe_flush(flush_fetch_decode || i_halt_proc),
        .i_new_pc(alu_buf_ld_newpc || mem_buf_ld_newpc),
        .i_pc(alu_buf_ld_newpc ? alu_buf_br_pc : mem_buf_br_pc),

        .o_wb_cyc(ifetch_o_wb_cyc),
        .o_wb_stb(ifetch_o_wb_stb),
        .o_wb_we(ifetch_o_wb_we),
        .o_wb_addr(ifetch_o_wb_addr),
        .o_wb_data(ifetch_o_wb_data),
        .o_wb_sel(ifetch_o_wb_sel),
        .i_wb_ack(ifetch_i_wb_ack),
        .i_wb_stall(ifetch_i_wb_stall),
        .i_wb_err(ifetch_i_wb_err),
        .i_wb_data(ifetch_i_wb_data),

        .o_buf_pc(fetch_buf_pc),
        .o_buf_inst(fetch_buf_inst)
    );

    wire decode_decode_err;

    tl45_decode decode(
        .i_clk(i_clk),
        .i_reset(reset),
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

        .o_decode_err(decode_decode_err)
    );

    tl45_register_read rr(
        .i_clk(i_clk),
        .i_reset(reset),
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
        .i_decode_err(decode_decode_err),

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
        .o_pc(rr_buf_pc),
        .o_decode_err(rr_decode_err)
    );

    wire rr_decode_err;
    assign inst_decode_err = rr_decode_err;

    assign o_valid = !(stall_rr_alu || stall_rr_mem);

    assign of1_reg = of1_reg_alu != 0 ? of1_reg_alu : of1_reg_mem;
    assign of1_val = of1_reg_alu != 0 ? of1_val_alu : of1_val_mem;

    tl45_alu alu(
        .i_clk(i_clk),
        .i_reset(reset),
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
        .i_decode_err(rr_decode_err),

        .o_of_reg(of1_reg_alu),
        .o_of_val(of1_val_alu),

        .o_dr(alu_buf_dr),
        .o_value(alu_buf_value),
        .o_ld_newpc(alu_buf_ld_newpc),
        .o_br_pc(alu_buf_br_pc)
    );

    tl45_memory memory(
        .i_clk(i_clk),
        .i_reset(reset),
        .i_pipe_stall(stall_alu_wb),
        .o_pipe_stall(stall_rr_mem),
        .i_pipe_flush(0),
        .o_pipe_flush(flush_rr_mem),

        .o_wb_cyc(dfetch_o_wb_cyc),
        .o_wb_stb(dfetch_o_wb_stb),
        .o_wb_we(dfetch_o_wb_we),
        .o_wb_addr(dfetch_o_wb_addr),
        .o_wb_data(dfetch_o_wb_data),
        .o_wb_sel(dfetch_o_wb_sel),
        .i_wb_ack(dfetch_i_wb_ack),
        .i_wb_stall(dfetch_i_wb_stall),
        .i_wb_err(dfetch_i_wb_err),
        .i_wb_data(dfetch_i_wb_data),

        .i_buf_opcode(rr_buf_opcode),
        .i_buf_dr(rr_buf_dr),
        .i_buf_sr1_val(rr_buf_sr1_val),
        .i_buf_sr2_val(rr_buf_sr2_val),
        .i_buf_imm(rr_buf_target_address_offset),
        .i_buf_pc(rr_buf_pc),

        .o_fwd_dr(of1_reg_mem),
        .o_fwd_val(of1_val_mem),

        .o_buf_dr(mem_buf_dr),
        .o_buf_val(mem_buf_value),
        .o_ld_newpc(mem_buf_ld_newpc),
        .o_br_pc(mem_buf_br_pc)
    );

    tl45_writeback writeback(
        .i_clk(i_clk),
        .i_reset(reset),
        .o_pipe_stall(stall_alu_wb),

        .i_buf_dr(alu_buf_dr != 0 ? alu_buf_dr : mem_buf_dr),
        .i_buf_val(alu_buf_dr != 0 ? alu_buf_value : mem_buf_value),

        .o_fwd_reg(of2_reg),
        .o_fwd_val(of2_val),

        .o_rf_en(dprf_we_wreg),
        .o_rf_reg(dprf_wreg),
        .o_rf_val(dprf_wreg_val)
    );

    // Wishbone master arbitration
    assign dfetch_i_wb_data = ibus_i_wb_data;
    assign ifetch_i_wb_data = ibus_i_wb_data;

    wbpriarbiter #(32, 30) ibus_arbiter(
        .i_clk(i_clk),
        // A
        .i_a_cyc(dfetch_o_wb_cyc),
        .i_a_stb(dfetch_o_wb_stb),
        .i_a_we(dfetch_o_wb_we),
        .i_a_adr(dfetch_o_wb_addr),
        .i_a_dat(dfetch_o_wb_data),
        .i_a_sel(dfetch_o_wb_sel),

        .o_a_ack(dfetch_i_wb_ack),
        .o_a_stall(dfetch_i_wb_stall),
        .o_a_err(dfetch_i_wb_err),

        // B
        .i_b_cyc(ifetch_o_wb_cyc),
        .i_b_stb(ifetch_o_wb_stb),
        .i_b_we(ifetch_o_wb_we),
        .i_b_adr(ifetch_o_wb_addr),
        .i_b_dat(ifetch_o_wb_data),
        .i_b_sel(ifetch_o_wb_sel),

        .o_b_ack(ifetch_i_wb_ack),
        .o_b_stall(ifetch_i_wb_stall),
        .o_b_err(ifetch_i_wb_err),

        // Merged
        .o_cyc(ibus_o_wb_cyc),
        .o_stb(ibus_o_wb_stb),
        .o_we(ibus_o_wb_we),
        .o_adr(ibus_o_wb_addr),
        .o_dat(ibus_o_wb_data),
        .o_sel(ibus_o_wb_sel),

        .i_ack(ibus_i_wb_ack),
        .i_stall(ibus_i_wb_stall),
        .i_err(ibus_i_wb_err)
    );

assign ibus_i_wb_data = master_i_wb_data;
assign dbgbus_i_wb_data = master_i_wb_data;
wbpriarbiter #(32, 30) mbus_arbiter(
        .i_clk(i_clk),
        // A
        .i_a_cyc(ibus_o_wb_cyc),
        .i_a_stb(ibus_o_wb_stb),
        .i_a_we(ibus_o_wb_we),
        .i_a_adr(ibus_o_wb_addr),
        .i_a_dat(ibus_o_wb_data),
        .i_a_sel(ibus_o_wb_sel),

        .o_a_ack(ibus_i_wb_ack),
        .o_a_stall(ibus_i_wb_stall),
        .o_a_err(ibus_i_wb_err),

        // B
        .i_b_cyc(dbgbus_o_wb_cyc),
        .i_b_stb(dbgbus_o_wb_stb),
        .i_b_we(dbgbus_o_wb_we),
        .i_b_adr(dbgbus_o_wb_addr),
        .i_b_dat(dbgbus_o_wb_data),
        .i_b_sel(dbgbus_o_wb_sel),

        .o_b_ack(dbgbus_i_wb_ack),
        .o_b_stall(dbgbus_i_wb_stall),
        .o_b_err(dbgbus_i_wb_err),

        // Merged
        .o_cyc(master_o_wb_cyc),
        .o_stb(master_o_wb_stb),
        .o_we(master_o_wb_we),
        .o_adr(master_o_wb_addr),
        .o_dat(master_o_wb_data),
        .o_sel(master_o_wb_sel),

        .i_ack(master_i_wb_ack),
        .i_stall(master_i_wb_stall),
        .i_err(master_i_wb_err)
    );

// Master Bus Address Decoding
//
// Define some wires for returning values to the bus from our various
// components
reg [31:0] wb_err_addr;
wire [31:0] mem_data, sseg_data, sw_led_data, lcd_data, timer_data, sdc_data;
wire	    mem_stall, sseg_stall, sw_led_stall, lcd_stall, timer_stall, sdc_stall;
wire	    mem_ack, sseg_ack, sw_led_ack, lcd_ack, timer_ack, sdc_ack, vga_ack;

wire	    mem_sel, sseg_sel, sw_led_sel, lcd_sel, timer_sel, sdc_sel, vga_sel;

`ifdef VERILATOR
reg	    [31:0]	v_hook_data; // Simple Device
reg v_hook_ack;
reg v_hook_stall;

    wire v_hook_stb;
    assign v_hook_stb = (master_o_wb_addr[29:12] == 18'h4ff) && master_o_wb_stb;
`endif

// Yaotian's Memory Map
// ------- BUS ADDRESS SAPCE ----------- --SEL
//
// 00 0000 0000 0000 0000 0000 0000 0000 00
// 00 000x xxxx xxxx xxxx xxxx xxxx xxxx xx - DRAM 128 MB (0x0000_0000 -> 0x07ff_ffff)
// 11 1111 1111 1110 xxxx xxxx xxxx xxxx xx - VGA Controller (0xFFF8_0000 --> 0xFFFB_0000)
// 11 1111 1111 1111 1111 1111 1111 01xx xx - SDC    (16 Bytes) (0xFFFF_FFD0 -> 0xFFFF_FFDF)
// 11 1111 1111 1111 1111 1111 1111 100x xx - LCD    (8 Bytes) (0xFFFF_FFE0 -> 0xFFFF_FFE7)
// 11 1111 1111 1111 1111 1111 1111 1010 xx - SW/LED (4 Bytes) (0xFFFF_FFE8 -> 0xFFFF_FFEB)
// 11 1111 1111 1111 1111 1111 1111 1011 xx - SSEG   (4 Bytes) (0xFFFF_FFEC -> 0xFFFF_FFEF)
// 11 1111 1111 1111 1111 1111 1111 110x xx - TIMR (8 Bytes) (0xFFFF_FFF0 -> 0xFFFF_FFF7)
// 11 1111 1111 1111 1111 1111 1111 111x xx - UART (8 Bytes) (0xFFFF_FFF8 -> 0xFFFF_FFFF)
//(31)

assign	mem_sel     = (master_o_wb_addr[29:25] == 5'b00_000); // mem selected

// MMIO
assign vga_sel      = (master_o_wb_addr[29:16] == 14'b11_1111_1111_1110);
assign sdc_sel      = (master_o_wb_addr[29:2 ] == 28'b11_1111_1111_1111_1111_1111_1111_01__); // SDC
assign lcd_sel      = (master_o_wb_addr[29:1 ] == 29'b11_1111_1111_1111_1111_1111_1111_100_); // LCD
assign sw_led_sel   = (master_o_wb_addr[29:0 ] == 30'b11_1111_1111_1111_1111_1111_1111_1010); // SWITCH LED
assign sseg_sel     = (master_o_wb_addr[29:0 ] == 30'b11_1111_1111_1111_1111_1111_1111_1011); // SSEG
assign timer_sel    = (master_o_wb_addr[29:1 ] == 29'b11_1111_1111_1111_1111_1111_1111_110_);
// UART
wire uart_sel;
assign uart_sel = (master_o_wb_addr[29:1] ==  29'b11_1111_1111_1111_1111_1111_1111_111);
wire uart_ack, uart_stall, uart_err;
wire [31:0] uart_data;

// SEL
wire	none_sel;
assign	none_sel =
    (!mem_sel)
    &&(!sseg_sel)
    &&(!sw_led_sel)
    &&(!lcd_sel)
    && (!timer_sel)
    && (!uart_sel)
    && (!sdc_sel)
    && (!vga_sel)
`ifdef VERILATOR
    && (!v_hook_stb)
`endif
    ;

always @(posedge i_clk)
    if (reset)
        master_i_wb_err <= 0;
    else
        master_i_wb_err <= (master_o_wb_stb) && (none_sel);
always @(posedge i_clk)
	if (reset)
		wb_err_addr <= 32'h0;
	else if (master_i_wb_err || master_i_wb_stall)
		wb_err_addr <= {master_o_wb_addr, 2'h0};
		  
// Master Bus Respond
always @(posedge i_clk)
    master_i_wb_ack <=
           mem_ack
        || sseg_ack
        || sw_led_ack
        || lcd_ack
        || timer_ack
        || uart_ack
        || sdc_ack
        || vga_ack
`ifdef VERILATOR
        || v_hook_ack
`endif
        ;

always @(posedge i_clk)
`ifdef VERILATOR
    if (v_hook_ack)
        master_i_wb_data <= v_hook_data;
    else
`endif
    if (mem_ack)
        master_i_wb_data <= mem_data;
    else if (sseg_ack)
        master_i_wb_data <= sseg_data;
    else if (sw_led_ack)
        master_i_wb_data <= sw_led_data;
    else if (lcd_ack)
        master_i_wb_data <= lcd_data;
    else if (timer_ack)
        master_i_wb_data <= timer_data;
    else if (uart_ack)
        master_i_wb_data <= uart_data;
    else if (sdc_ack)
        master_i_wb_data <= sdc_data;
    else
        master_i_wb_data <= 32'h0;

assign	master_i_wb_stall = 
           ((mem_sel)  && (mem_stall))
        || (sseg_sel) && (sseg_stall)
        || lcd_sel && lcd_stall
        || sw_led_sel && sw_led_stall
        || timer_sel && timer_stall
        || uart_sel && uart_stall
        || sdc_sel && sdc_stall;


wire sd_int;
wire [31:0] sddbg;
// Wishbone SDCard
sdspi #(
    .OPT_CARD_DETECT(1'b0),
    .OPT_SPI_ARBITRATION(1'b0)
)
sdcard(
    .i_clk(i_clk), 
    .i_sd_reset(reset),
	 .i_wb_cyc(master_o_wb_cyc), .i_wb_stb(master_o_wb_stb && sdc_sel), 
    .i_wb_we(master_o_wb_we), .i_wb_addr(master_o_wb_addr[1:0]), 
    .i_wb_data(master_o_wb_data), .i_wb_sel(master_o_wb_sel),
	 .o_wb_stall(sdc_stall), .o_wb_ack(sdc_ack),
    .o_wb_data(sdc_data),
    // SDCard interface
    .o_cs_n(sdc_o_cs), .o_sck(sdc_o_sck), .o_mosi(sdc_o_mosi), .i_miso(sdc_i_miso),
    .i_card_detect(1'b1),
    // Our interrupt
    .o_int(sd_int),
    // And whether or not we own the bus
    .i_bus_grant(1'b1),
    // And some wires for debugging it all
    .o_debug(sddbg));


// Wishbone Timer
wb_timer timer1(
    i_clk, reset, 
    master_o_wb_cyc, 
    (master_o_wb_stb && timer_sel),
    master_o_wb_we, 
    master_o_wb_addr, master_o_wb_data,
    master_o_wb_sel,
    timer_ack, timer_stall, 
    timer_data);

// SevenSeg
wb_sevenseg sevenseg_disp(
    i_clk,
    reset,
    master_o_wb_cyc,
    (master_o_wb_stb && sseg_sel),
    master_o_wb_we,
    master_o_wb_addr,
    master_o_wb_data,
    master_o_wb_sel,
    sseg_ack,
    sseg_stall,
    sseg_data,
`ifndef VERILATOR
    ssegs,
`endif
    (i_sw16 && inst_decode_err) ? fetch_buf_inst : rr_buf_pc,
    i_sw16 || inst_decode_err
);

// LCDHD47780
wb_lcdhd47780 de2_lcd(
    i_clk,
    reset,
    master_o_wb_cyc,
    (master_o_wb_stb && lcd_sel),
    master_o_wb_we,
    master_o_wb_addr,
    master_o_wb_data,
    master_o_wb_sel,
    lcd_ack,
    lcd_stall,
    lcd_data,
    io_disp_data,
    o_disp_rw,
    o_disp_en_n,
    o_disp_rs,
    o_disp_on_n,
    o_disp_blon
);

// Sw_LED
wb_switch_led de2_switch_led(
    i_clk,
    reset,
    master_o_wb_cyc,
    (master_o_wb_stb && sw_led_sel),
    master_o_wb_we,
    master_o_wb_addr,
    master_o_wb_data,
    master_o_wb_sel,
    sw_led_ack,
    sw_led_stall,
    sw_led_data,
    o_leds,
    i_switches
);

wire vga_blank;
assign o_vga_sync = ~(o_vga_hsync | o_vga_vsync);
assign o_vga_blank = ~vga_blank;

wire vga_clk_25_125;
assign o_vga_clk = vga_clk_25_125;
vga_pll vga_clk_source(i_clk, vga_clk_25_125);

wb_vga vga_controller (
    .i_clk,
    .i_clk_25_125(vga_clk_25_125),
    .i_reset(reset),
    .i_wb_cyc(master_o_wb_cyc),
    .i_wb_stb(master_o_wb_stb && vga_sel),
    .i_wb_we(master_o_wb_we),
    .i_wb_addr(master_o_wb_addr[15:0]),
    .i_wb_data(master_o_wb_addr),
    .i_wb_sel(master_o_wb_sel),
    .o_wb_ack(vga_ack),
    .o_r(o_vga_r), 
    .o_g(o_vga_g),
    .o_b(o_vga_b),
    .o_hsync(o_vga_hsync), 
    .o_vsync(o_vga_vsync),
    .o_blank(vga_blank)
);

`ifdef VERILATOR
    memdev #(20) my_mem(
        .i_clk(i_clk),
        .i_wb_cyc(ibus_o_wb_cyc),
        .i_wb_stb(ibus_o_wb_stb && mem_sel),
        .i_wb_we(ibus_o_wb_we),
        .i_wb_addr(ibus_o_wb_addr[19-2:0]),
        .i_wb_data(ibus_o_wb_data),
        .i_wb_sel(ibus_o_wb_sel),

        .o_wb_ack(mem_ack),
        .o_wb_stall(mem_stall),
        .o_wb_data(mem_data)
    );
`else
    sdram #(
        .SDRAM_MHZ(50),
        .SDRAM_ADDR_W(25),
        .SDRAM_COL_W(10),
        .SDRAM_TARGET("ALTERA") // This is fake news, but whatever
    ) memram (
        i_clk,
        reset,
        
        (mem_sel && master_o_wb_stb),
        master_o_wb_we,
        master_o_wb_sel,
        master_o_wb_cyc,
        {master_o_wb_addr, 2'h0},
        master_o_wb_data,
        mem_data,
        mem_stall,
        mem_ack,

        dram_clk_source,
        sdr_cke,
        sdr_cs_n,
        sdr_ras_n,
        sdr_cas_n,
        sdr_we_n,
        sdr_dqm,
        sdr_addr,
        sdr_ba,
        sdr_dq
    );

`endif

wbuart_with_ihex 
 `ifdef VERILATOR
#(
        .BAUD_RATE(10000000)
)
    `endif
hexuart
(
    i_clk, reset,
    i_uart, o_uart,
    // Master Wishbone
    dbgbus_o_wb_cyc, dbgbus_o_wb_stb,
    dbgbus_o_wb_we, dbgbus_o_wb_sel,
    dbgbus_i_wb_stall, dbgbus_i_wb_ack, dbgbus_i_wb_err,
    dbgbus_o_wb_addr, dbgbus_o_wb_data, dbgbus_i_wb_data,
    // Slave Wishbone
    master_o_wb_cyc, (master_o_wb_stb && uart_sel),
    master_o_wb_we, master_o_wb_sel,
    uart_stall, uart_ack, uart_err,
    master_o_wb_addr, master_o_wb_data, uart_data
);

endmodule : tl45_comp


