`default_nettype none

module wb_lcdhd47780(i_clk, i_reset,
i_wb_cyc, i_wb_stb, i_wb_we, 
i_wb_addr, i_wb_data, i_wb_sel,
o_wb_ack, o_wb_stall, 
o_wb_data,
io_disp_data,
o_disp_rw,
o_disp_en_n,
o_disp_rs,
o_disp_on_n,
o_disp_blon
);
    input	wire    i_clk, i_reset, i_wb_cyc, i_wb_stb, i_wb_we;
    input	wire	[29:0]	i_wb_addr;
    input	wire	[31:0]	i_wb_data;
    input	wire	[3:0]	i_wb_sel;
    output	reg	    o_wb_ack;
    output	wire    o_wb_stall;
    output	reg	    [31:0] o_wb_data;

    output reg o_disp_blon, o_disp_rw, o_disp_en_n, o_disp_rs, o_disp_on_n;
    inout wire [7:0] io_disp_data;

`ifdef FORMAL
    parameter COMMAND_DELAY = 6;
`else
    parameter COMMAND_DELAY = 50;
`endif


    reg [7:0] i_disp_ext, i_disp;
    reg [7:0] o_disp_data;
    initial begin
        i_disp_ext = 0;
        i_disp = 0;
        o_disp_data = 0;
    end
    // 2FF Sync, I know this is not suitable, but it's better than not syncing
    always @(posedge i_clk) begin
        {i_disp, i_disp_ext} <= {i_disp_ext, io_disp_data};
    end

    assign io_disp_data = (!o_disp_rw) ? o_disp_data : 8'bzzzz_zzzz;

	assign o_wb_stall = i_reset || (current_state != IDLE) ; 
    initial begin
        o_wb_data = 32'h0;

        o_disp_on_n = 1; // TURN ON
        o_disp_blon = 1; // BACK_LIGHT
        o_disp_en_n = 0; // EN(CLK)
        o_disp_rw = 1; // 0 = Write, 1 = READ
    end

    integer clk_counter;
    initial clk_counter = 0;

    localparam IDLE = 0,
                WRITE_LCD = 1,
                WRITE_LCD_2 = 2,
                RESPOND = 3,
                LAST_STATE = 4;
    integer current_state;
    initial current_state = IDLE;


    always @(*) begin
        // Selector for wback
        case(current_state)
            RESPOND: o_wb_ack = i_wb_cyc; // This is effectively a "1"
            default: o_wb_ack = 0;
        endcase
    end

    always @(posedge i_clk) 
    if (i_reset || !i_wb_cyc) begin
        o_disp_data <= 0;
        current_state <= IDLE;
        o_disp_rw <= 1;
        o_disp_en_n <= 1;
    end
    else if ((current_state == IDLE) && i_wb_cyc && i_wb_stb) begin
    // Strobe at idle
        clk_counter <= 0;
        o_disp_rs <= i_wb_addr[0]; // Last bit of addr (r shifted) select data / control
        if (i_wb_we) begin
            o_disp_data <= i_wb_data[7:0];
            current_state <= WRITE_LCD;
            o_disp_rw <= 0; // SWITCH TO WRITE MODE
        end else begin
            o_wb_data <= {24'h0, i_disp};
            current_state <= RESPOND;
        end
	 end
    else if (current_state == WRITE_LCD) begin
        clk_counter <= clk_counter + 1;
        if (clk_counter == COMMAND_DELAY / 2) begin
            // RAISE EDGE
            o_disp_en_n <= 0;
            current_state <= WRITE_LCD_2;
        end
    end
    else if (current_state == WRITE_LCD_2) begin
        if (clk_counter == COMMAND_DELAY) begin
            o_disp_en_n <= 1;
            current_state <= RESPOND;
            o_disp_rw <= 1; // Switch back to read mode
            clk_counter <= 0;
            o_wb_data <= 0;
        end else
            clk_counter <= clk_counter + 1;
    end else if ((current_state == RESPOND) && i_wb_cyc) begin
        current_state <= IDLE;
    end else 
        current_state <= IDLE;

`ifdef FORMAL

reg f_past_valid;
initial f_past_valid = 0;

always @(posedge i_clk)
    f_past_valid <= 1;

// Let's keep it reset untill past is valid
always @(*)
    if (!f_past_valid)
        assume(i_reset);

wire [3:0] f_wb_nreqs, f_wb_nacks, f_wb_outstanding;

fwb_slave  #(.DW(32), .AW(30),
        .F_MAX_STALL(10),
        .F_MAX_ACK_DELAY(10),
        .F_OPT_RMW_BUS_OPTION(1),
        .F_OPT_DISCONTINUOUS(1),
        .F_OPT_MINCLOCK_DELAY(1'b0))
    f_wba(i_clk, i_reset,
        i_wb_cyc, i_wb_stb, i_wb_we, i_wb_addr, i_wb_data, i_wb_sel, 
        o_wb_ack, o_wb_stall, o_wb_data, 0,
        f_wb_nreqs, f_wb_nacks, f_wb_outstanding);

always @(*)
    assert(current_state < LAST_STATE);

// always @(posedge i_clk)
// if (f_past_valid) begin
//     if (!$past(i_reset) && $past(i_wb_we) && $past(i_wb_cyc) && $past(i_wb_stb))
//         assert(internal_data == $past(i_wb_data));
//     else if ($past(i_reset))
//         assert(internal_data == 32'h0);
//     else
//         assert(internal_data == $past(internal_data));
// end

`endif
endmodule
