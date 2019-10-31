`default_nettype none

module wb_switch_led(i_clk, i_reset,
i_wb_cyc, i_wb_stb, i_wb_we, 
i_wb_addr, i_wb_data, i_wb_sel,
o_wb_ack, o_wb_stall, 
o_wb_data,
o_leds,
i_switches);
    input	wire    i_clk, i_reset, i_wb_cyc, i_wb_stb, i_wb_we;
    input	wire	[29:0]	i_wb_addr;
    input	wire	[31:0]	i_wb_data;
    input	wire	[3:0]	i_wb_sel;
    output	reg	    o_wb_ack;
    output	wire		o_wb_stall;
    output	reg	    [31:0] o_wb_data;
    input   wire    [15:0] i_switches;
    output  wire     [15:0] o_leds;
    
    
    initial begin
        o_wb_data = 32'h0;
    end
	 
	 assign o_wb_stall = i_reset;


    localparam IDLE = 0,
                RESPOND_WRITE = 1,
                RESPOND_READ = 2,
                LAST_STATE = 3;
    integer current_state;
    initial current_state = IDLE;

    reg [15:0] internal_led_data;
    initial internal_led_data = 0;
    assign o_leds = internal_led_data;

    reg [15:0] switches, int_switches;
    initial begin
        switches = 0;
        int_switches = 0;
    end

    // Switch Clock Domain Crossing Logic
    // 2FF to prevent metastability
    always @(posedge i_clk) begin 
        { switches, int_switches } <= { int_switches, i_switches };
    end


    always @(*) begin
        // Selector for wback
        case(current_state)
            RESPOND_READ, RESPOND_WRITE: o_wb_ack = i_wb_cyc; // This is effectively a "1"
            default: o_wb_ack = 0;
        endcase
        // Selector for data
        case(current_state)
            RESPOND_READ: o_wb_data = {16'h0, switches};
            default: o_wb_data = 32'h0;
        endcase
    end

    always @(posedge i_clk) 
    if (i_reset) begin
        internal_led_data <= 0;
        current_state <= IDLE;
    end
    else if ((current_state == IDLE) && i_wb_cyc && i_wb_stb) begin
    // Strobe at idle
        if (i_wb_we) begin
            current_state <= RESPOND_WRITE;
            internal_led_data <= i_wb_data[15:0];
        end 
        else
            current_state <= RESPOND_READ;
    end else if ((current_state == RESPOND_WRITE || current_state == RESPOND_READ) && i_wb_cyc && i_wb_stb) begin
        // Strobe (Pipelined request)
        if (i_wb_we) begin
            internal_led_data <= i_wb_data[15:0];
            current_state <= RESPOND_WRITE;
        end
        else
            current_state <= RESPOND_READ;
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
        assert(internal_led_data == $past(i_wb_data));
    else if ($past(i_reset))
        assert(internal_led_data == 32'h0);
    else
        assert(internal_led_data == $past(internal_led_data));
end

`endif
endmodule