//
//
`default_nettype	none
`define SDR_RFSH_TIMER_W 12
`define SDR_RFSH_ROW_CNT_W 3
//
//
`define	UARTSETUP	434	// 115200 @ 50Mhz Baud
//
module	testbus(i_clk, i_reset, i_uart, o_uart,
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
done_led
`ifdef	VERILATOR
	, o_halt
`endif
	);

output wire sdram_clk;
assign sdram_clk = i_clk;
output wire sdr_cs_n;
output wire sdr_cke;
output wire sdr_ras_n;
output wire sdr_cas_n;
output wire sdr_we_n;
output wire [1:0] sdr_dqm;
output wire [1:0] sdr_ba;
output wire [11:0] sdr_addr;
inout wire [15:0] sdr_dq;

//MEME
wire [12:0] sdr_addr_fake;
assign sdr_addr = sdr_addr_fake[11:0];


	input	wire		i_clk;
	// verilator lint_off UNUSED
	input	wire		i_reset; // Ignored, but needed for our test infra.
	// verilator lint_on UNUSED
	input	wire		i_uart;
	output	wire		o_uart;
`ifdef	VERILATOR
	output	reg		o_halt; // Tell the SIM when to stop
`endif

	wire		rx_stb;
	wire	[7:0]	rx_data;
	rxuartlite #(`UARTSETUP) rxtransport(i_clk,
					i_uart, rx_stb, rx_data);

	wire		tx_stb, tx_busy;
	wire	[7:0]	tx_data;
	txuartlite #(`UARTSETUP) txtransport(i_clk,
					tx_stb, tx_data, o_uart, tx_busy);


	// Bus interface wires
	wire	wb_cyc, wb_stb, wb_we;
	wire	[29:0]	wb_addr;
	wire	[31:0]	wb_odata;
	wire	[3:0]	wb_sel;
	reg		wb_ack;
	wire		wb_stall;
	reg		wb_err;
	reg	[31:0]	wb_idata;
	wire		bus_interrupt;

	hbbus	genbus(i_clk,
		// The receive transport wires
		rx_stb, rx_data,
		// The bus control output wires
		wb_cyc, wb_stb, wb_we, wb_addr, wb_odata, wb_sel,
		//	The return bus wires
		  wb_ack, wb_stall, wb_err, wb_idata,
		// An interrupt line
		bus_interrupt,
		// The return transport wires
		tx_stb, tx_data, tx_busy);

	//
	// Define some wires for returning values to the bus from our various
	// components
	reg	[31:0]	smpl_data;
	wire	[31:0]	mem_data, scop_data;
	wire	smpl_stall, mem_stall, scop_stall;
	wire	scop_int;
	reg	smpl_interrupt;
	wire	scop_ack, mem_ack;
	reg	smpl_ack;

	wire	smpl_sel, scop_sel, mem_sel;

	// Nothing should be assigned to the null page
	assign	smpl_sel = (wb_addr[29:4] == 26'h081);
	assign	scop_sel = (wb_addr[29:4] == 26'h082);
	assign	mem_sel  = (wb_addr[29:12] == 18'h1);

	// The "null" device
	//
	// Replaced with looking for nothing being selected
	wire	none_sel;
	assign	none_sel = (!smpl_sel)&&(!scop_sel)&&(!mem_sel);

	always @(posedge i_clk)
		wb_err <= (wb_stb)&&(none_sel);


	// A "Simple" example device
	reg	[31:0]	smpl_register, power_counter;
	reg	[29:0]	bus_err_address;

	always @(posedge i_clk)
		smpl_ack <= ((wb_stb)&&(smpl_sel));
	assign	smpl_stall = 1'b0;
	initial	smpl_interrupt = 1'b0;
	always @(posedge i_clk)
		if ((wb_stb)&&(smpl_sel)&&(wb_we))
		begin
			case(wb_addr[3:0])
			4'h1: smpl_register  <= wb_odata;
			4'h4: smpl_interrupt <= wb_odata[0];
`ifdef	VERILATOR
			4'h5: o_halt         <= wb_odata[0];
`endif
			default: begin end
			endcase
		end

	always @(posedge i_clk)
		case(wb_addr[3:0])
		4'h0:    smpl_data <= 32'h20170622;
		4'h1:    smpl_data <= smpl_register;
		4'h2:    smpl_data <= { bus_err_address, 2'b00 };
		4'h3:    smpl_data <= power_counter;
		4'h4:    smpl_data <= { 31'h0, smpl_interrupt };
		default: smpl_data <= 32'h00;
		endcase

	// Start our clocks since power up counter from zero
	initial	power_counter = 0;
	always @(posedge i_clk)
		// Count up from zero until the top bit is set
		if (!power_counter[31])
			power_counter <= power_counter + 1'b1;
		else // Once the top bit is set, keep it set forever
			power_counter[30:0] <= power_counter[30:0] + 1'b1;

	initial	bus_err_address = 0;
	always @(posedge i_clk)
		if (wb_err)
			bus_err_address <= wb_addr;
	
	wire	[15:0]	ram_data;
	wire		ram_drive_data;
	reg	[15:0]	r_ram_data;
	
	assign sdr_dq = (ram_drive_data) ? ram_data : 16'bzzzz_zzzz_zzzz_zzzz;
	reg	[15:0]	r_ram_data_ext_clk;

	always @(posedge i_clk)
		r_ram_data_ext_clk <= sdr_dq;
	always @(posedge i_clk)
		r_ram_data <= r_ram_data_ext_clk;




	wire [31:0] sdram_debug;

	wbsdram yeetmemory(i_clk,
		wb_cyc, (mem_sel && wb_stb), wb_we, {11'b0, wb_addr[11:0]}, wb_odata, wb_sel,
			mem_ack, mem_stall, mem_data,
		sdr_cs_n, sdr_cke, sdr_ras_n, sdr_cas_n, sdr_we_n,
			sdr_ba, sdr_addr_fake,
			ram_drive_data, r_ram_data, ram_data, sdr_dqm,
		sdram_debug);
	//
	//
	// A wishbone scope
	//
	wire	scope_trigger;
	assign	scope_trigger = (mem_sel)&&(wb_stb);
	wire	[31:0]	debug_data;
	assign	debug_data    = { wb_cyc, wb_stb, wb_we, wb_ack, wb_stall,
			wb_addr[5:0], 1'b1,
				wb_odata[9:0],
				wb_idata[9:0] };
	wbscope	thescope(i_clk, 1'b1, scope_trigger, debug_data,
		i_clk, wb_cyc, (wb_stb)&&(scop_sel), wb_we, wb_addr[0],wb_odata,
		scop_ack, scop_stall, scop_data,
		scop_int);

	//
	//
	// Bus response composition
	//
	//
	// Now, let's put those bus responses together
	//
	always @(posedge i_clk)
		wb_ack <= (smpl_ack)||(scop_ack)||(mem_ack);

	always @(posedge i_clk)
		if (smpl_ack)
			wb_idata <= smpl_data;
		else if (scop_ack)
			wb_idata <= scop_data;
		else if (mem_ack)
			wb_idata <= mem_data;
		else
			wb_idata <= 32'h0;

	assign	wb_stall = ((smpl_sel)&&(smpl_stall))
			||((scop_sel)&&(scop_stall))
			||((mem_sel)&&(mem_stall));

	assign	bus_interrupt = (smpl_interrupt) | (scop_int);

endmodule
