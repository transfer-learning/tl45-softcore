`default_nettype none

module tl45_prefetch(
    i_clk, i_reset,
    i_pipe_stall,
    i_pipe_flush,
    i_new_pc, i_pc,
    // Wishbone stuff
    o_wb_cyc, o_wb_stb, o_wb_we,
    o_wb_addr, o_wb_data, o_wb_sel,
    i_wb_ack, i_wb_stall, i_wb_err,
    i_wb_data,
    // Buffer
    o_buf_pc, o_buf_inst
);
input wire i_clk, i_reset; // Sys CLK, Reset
input wire i_pipe_stall, i_pipe_flush; // Stall, Flush

// PC Override stuff
input wire i_new_pc;
input wire [31:0] i_pc;

// Wishbone
output reg o_wb_stb, o_wb_we;
output wire o_wb_cyc;
output wire [29:0] o_wb_addr; // WB Address
output reg [31:0] o_wb_data; // WB Data
output reg [3:0]  o_wb_sel; // WB Byte Sel (One hot)
initial begin
    o_wb_stb = 0;
    o_wb_we = 0;
    o_wb_sel = 0;
    o_wb_data = 0;
end

input wire i_wb_ack, i_wb_stall, i_wb_err;
input wire [31:0] i_wb_data;

// Buffer
output reg [31:0] o_buf_pc, o_buf_inst;
initial begin
    o_buf_pc = 0;
    o_buf_inst = 0;
end

// Internal PC
reg [31:0] current_pc;
assign o_wb_addr = current_pc[31:2];
initial current_pc = 0;
localparam IDLE = 0,
           FETCH_STROBE = 1,
           FETCH_WAIT_ACK = 2,
           WRITE_OUT = 3,
           LAST_STATE = 4;
integer current_state;
initial current_state = IDLE;

// STATE MACHINE
// IDLE -> FETCH_STROBE -> FETCH_WAIT_ACK -> WRITE_OUT ->(Clear Local Buffer) IDLE

always @(posedge i_clk) begin
    if (i_reset) begin // STALL
        current_state <= IDLE;
        current_pc <= 0;
        o_buf_pc <= 0;
        o_buf_inst <= 0;
    end 
    else if (i_pipe_flush || i_new_pc) begin // FLUSH 
        current_state <= IDLE;
        o_buf_pc <= 0;
        o_buf_inst <= 0;
        if (i_new_pc)
            current_pc <= i_pc;
    end
    else if ((current_state == IDLE)) begin // IDLE && Wishbone not stalled
        current_state <= FETCH_STROBE;
    end
    else if (current_state == FETCH_STROBE && !i_wb_stall)
        current_state <= FETCH_WAIT_ACK;
    else if ((current_state == FETCH_WAIT_ACK) && (i_wb_ack) && (!i_wb_err) && (!i_wb_stall)) begin // not stall, and ack & no error
        current_pc <= current_pc + 4; // PC Increment
        o_buf_pc <= current_pc; // Load PC into buf
        o_buf_inst <= i_wb_data;
        current_state <= WRITE_OUT;
    end
    else if ((current_state == FETCH_WAIT_ACK) && (i_wb_err)) begin // ACK With Error
        current_state <= IDLE;
        o_buf_pc <= 0;
        o_buf_inst <= 0;
    end
    else if ((current_state == WRITE_OUT) && (!i_pipe_stall)) begin
        o_buf_inst <= 0;
        o_buf_pc <= 0;
        current_state <= IDLE;
    end
end

assign o_wb_cyc = current_state == FETCH_STROBE 
                ||current_state == FETCH_WAIT_ACK;

always @(*) begin
    case(current_state)
        FETCH_STROBE: begin
            o_wb_stb = 1;
        end
        default: begin
            o_wb_stb = 0;
        end
    endcase
end

// Buffer: PC, Instruction



`ifdef FORMAL
    reg f_past_valid;
    initial f_past_valid = 0;
    always @(posedge i_clk)
        f_past_valid <= 1;
    always @(*)
        assert(current_state < LAST_STATE);

    initial assume(i_reset); // start in reset
	initial	assume(!i_wb_ack);
	initial	assume(!i_wb_err);

    initial assert(current_state == IDLE);// Let's start in idle

    always @(*) begin // Stall then NoAck / Err
        if (i_wb_stall)
            assume(!i_wb_err);
            assume(!i_wb_ack);
    end

    always @(posedge i_clk) begin
        if ($past(i_reset)) begin
            assert(current_state == IDLE); // We Can Reset
        end
    end

    always @(*)
        if (current_state == IDLE) begin // When we idle, we dont have anything raised
            assert(!o_wb_cyc);
            assert(!o_wb_stb);
        end

    always @(*) begin // Strobe always comes with cycle
        if(o_wb_stb)
            assert(o_wb_cyc);
    end

    always @(*)
        if (i_wb_err) // Err always comes with ack
            assume(i_wb_ack);

    always @(*) begin
        if (current_state == FETCH_STROBE || current_state == FETCH_WAIT_ACK)
            assert(o_wb_cyc); // From Strobe to ACK we should cycle
    end

    always @(posedge i_clk) 
    if (f_past_valid) begin
        if (($past(i_pipe_flush) || $past(i_new_pc)) && !$past(i_reset)) begin // IF flush / load new pc then clear
            assert(o_buf_pc == 0);
            assert(o_buf_inst == 0);
            assert(current_state == IDLE);
            if ($past(i_new_pc)) begin // new PC loads pc
                assert(current_pc == $past(i_pc));
            end else // flush preserves pc
                assert(current_pc == $past(current_pc));
        end
    end

    always @(posedge i_clk)
        if (f_past_valid) begin
            // IF error, we should retry
            if (($past(current_state) == FETCH_WAIT_ACK) && $past(i_wb_err)) begin
                assert(current_state == IDLE);
                assert(current_pc == $past(current_pc));
                assert(o_buf_pc == 0);
                assert(o_buf_inst == 0);
            end
        end
    
    always @(posedge i_clk)
        if (f_past_valid) begin // IF Success, we should see past pc in current buf, and pc should +4
            if (current_state == WRITE_OUT) begin
                assert(o_buf_pc == $past(current_pc));
                assert(current_pc == $past(current_pc + 4));
            end         
        end

    always @(*) begin
        if ((current_state == FETCH_STROBE || current_state == FETCH_WAIT_ACK) && i_wb_stall)
            assert(o_wb_cyc);
    end

// BUS Verify
    wire [3:0] f_nreqs, f_nacks, f_outstanding;
    fwb_master #(
            .AW(30),
            .DW(32),
            .F_MAX_STALL(0),
			.F_MAX_ACK_DELAY(0),
			.F_OPT_RMW_BUS_OPTION(0),
			.F_OPT_DISCONTINUOUS(1))
		f_wbm(i_clk, i_reset,
			o_wb_cyc, o_wb_stb, o_wb_we, o_wb_addr, o_wb_data, o_wb_sel,
			i_wb_ack, i_wb_stall, 32'h0, i_wb_err,
			f_nreqs, f_nacks, f_outstanding);
`endif
endmodule
