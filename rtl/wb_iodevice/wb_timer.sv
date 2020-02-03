`default_nettype none

module wb_timer(i_clk, i_reset,
i_wb_cyc, i_wb_stb, i_wb_we, 
i_wb_addr, i_wb_data, i_wb_sel,
o_wb_ack, o_wb_stall, 
o_wb_data);
    input	wire    i_clk, i_reset, i_wb_cyc, i_wb_stb, i_wb_we;
    input	wire	[29:0]	i_wb_addr;
    input	wire	[31:0]	i_wb_data;
    input	wire	[3:0]	i_wb_sel;
    output	reg	    o_wb_ack;
    output	wire		o_wb_stall;
    output	reg	    [31:0] o_wb_data;
    
    parameter CLOCK_FREQ = 50_000_000;
    localparam COUNTER_TOP = CLOCK_FREQ / 1_000_000;
    
    reg [63:0] timer_counter;
    reg [31:0] div_counter;

    initial begin
        o_wb_data = 32'h0;
        timer_counter = 0;
        div_counter = 0;
    end
	 
	assign o_wb_stall = i_reset;


    localparam IDLE = 0,
                RESPOND_WRITE = 1,
                RESPOND_READ = 2,
                LAST_STATE = 3;
    integer current_state;
    initial current_state = IDLE;


    always @(*) begin
        // Selector for wback
        case(current_state)
            RESPOND_READ, RESPOND_WRITE: o_wb_ack = i_wb_cyc; // This is effectively a "1"
            default: o_wb_ack = 0;
        endcase
    end

    always @(posedge i_clk) 
    if (i_reset) begin
        current_state <= IDLE;
        timer_counter <= 0;
        div_counter <= 0;
    end
    else if ((current_state == IDLE) && i_wb_cyc && i_wb_stb) begin
        // Strobe at idle
        if (i_wb_we) begin
            current_state <= RESPOND_WRITE;
            timer_counter <= i_wb_data;
            div_counter <= 0;
        end
        else begin
            o_wb_data <= i_wb_addr[0] ? timer_counter[63:32] : timer_counter[31:0];
            current_state <= RESPOND_READ;
            if (div_counter >= COUNTER_TOP) begin
                timer_counter <= timer_counter + 1;
                div_counter <= 0;
            end else
                div_counter <= div_counter + 1;
        end
    end else if ((current_state == RESPOND_WRITE || current_state == RESPOND_READ) && i_wb_cyc && i_wb_stb) begin
        // Strobe (Pipelined request)
        if (i_wb_we) begin
            timer_counter <= i_wb_data;
            div_counter <= 0;
            current_state <= RESPOND_WRITE;
        end
        else begin
            current_state <= RESPOND_READ;
            if (div_counter >= COUNTER_TOP) begin
                timer_counter <= timer_counter + 1;
                div_counter <= 0;
            end else
                div_counter <= div_counter + 1;
        end
    end else begin
        current_state <= IDLE;
        if (div_counter >= COUNTER_TOP) begin
            timer_counter <= timer_counter + 1;
            div_counter <= 0;
        end else
            div_counter <= div_counter + 1;
    end

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