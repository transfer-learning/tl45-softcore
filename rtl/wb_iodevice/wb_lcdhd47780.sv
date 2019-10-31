`default_nettype none

module wb_sevenseg(i_clk, i_reset,
i_wb_cyc, i_wb_stb, i_wb_we, 
i_wb_addr, i_wb_data, i_wb_sel,
o_wb_ack, o_wb_stall, 
o_wb_data,
o_disp_data,
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
    output reg [7:0] o_disp_data;

    parameter COMMAND_DELAY = 50;

	assign o_wb_stall = i_reset; 
    initial begin
        o_wb_data = 32'h0;

        o_disp_data = 0; // DATA BUS
        o_disp_on_n = 0; // TURN ON
        o_disp_blon = 1; // BACK_LIGHT
        o_disp_en_n = 1; // EN(CLK)
        o_disp_rw = 0; // 0 = Write, 1 = READ
    end

    integer clk_counter;
    initial clk_counter = 0;

    localparam IDLE = 0,
                RESPOND = 1,
                LAST_STATE = 2;
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
    if (i_reset) begin
        internal_data <= 0;
        current_state <= IDLE;
    end
    else if ((current_state == IDLE) && i_wb_cyc && i_wb_stb) begin
    // Strobe at idle
        current_state <= RESPOND;
        if (i_wb_we)
            internal_data <= i_wb_data;
    end else if ((current_state == RESPOND) && i_wb_cyc && i_wb_stb) begin
        // Strobe (Pipelined request)
        if (i_wb_we)
            internal_data <= i_wb_data;
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
        .F_MAX_STALL(0),
        .F_MAX_ACK_DELAY(0),
        .F_OPT_RMW_BUS_OPTION(1),
        .F_OPT_DISCONTINUOUS(1),
        .F_OPT_MINCLOCK_DELAY(1'b1))
    f_wba(i_clk, i_reset,
        i_wb_cyc, i_wb_stb, i_wb_we, i_wb_addr, i_wb_data, i_wb_sel, 
        o_wb_ack, o_wb_stall, o_wb_data, 0,
        f_wb_nreqs, f_wb_nacks, f_wb_outstanding);

always @(*)
    assert(current_state < LAST_STATE);

always @(posedge i_clk)
if (f_past_valid) begin
    if (!$past(i_reset) && $past(i_wb_we) && $past(i_wb_cyc) && $past(i_wb_stb))
        assert(internal_data == $past(i_wb_data));
    else if ($past(i_reset))
        assert(internal_data == 32'h0);
    else
        assert(internal_data == $past(internal_data));
end

`endif
endmodule : wb_sevenseg