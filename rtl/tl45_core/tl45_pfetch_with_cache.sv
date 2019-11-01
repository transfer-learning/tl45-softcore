`default_nettype none

module tl45_pfetch_with_cache(
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
    o_buf_pc, o_buf_inst,
    o_cache_hit,
    current_state,
);

output wire o_cache_hit;

input wire i_clk, i_reset; // Sys CLK, Reset
input wire i_pipe_stall, i_pipe_flush; // Stall, Flush

// PC Override stuff
input wire i_new_pc;
input wire [31:0] i_pc;

// Wishbone
output reg o_wb_stb, o_wb_we;
output wire o_wb_cyc;
output reg [29:0] o_wb_addr; // WB Address
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
initial current_pc = 0;
localparam IDLE = 0,
           FETCH_STROBE = 1,
           FETCH_WAIT_ACK = 2,
           FETCH_NEXT = 3,
           LAST_STATE = 4;
output reg [3:0] current_state;
initial current_state = IDLE;

// Cache Process:
// Compare current_pc[31:14](18bits total) zero extended cache_tags[current_pc[13:2](12 bits)](9bits)
// Logical AND (&&) the above with cache_valid[current_pc[13:2]]
// If True then it's okay to load the cache
// else load zero to output (stall) and clock into fetch statemachine


// Quote RAMA: Designed the hardware in a brain damage way.
// This is exactally that "Brain Damage Way"
// CACHE
// We have 4K L1 Cache
// 4K is choosen because of we need 9Bit / Tag so it will use M4K
// Please check altera documentation for alternative choices

reg [8:0]  cache_tags [256]; //  9 Bits Tag
reg [31:0] cache_data [4096]; // 32 Bits Data
reg cache_valid [256];
integer i;
`ifndef FORMAL
initial begin    
    for (i=0; i<256; i=i+1)
        cache_valid[i] = 0;
end
`endif
wire cache_hit;
wire [7:0] cache_index;
wire [11:0] cache_word_index;
assign cache_index = current_pc[13:6];
assign cache_word_index = current_pc[13:2];
assign cache_hit = (current_pc[31:14] == {9'h0, cache_tags[cache_index]})
                && (cache_valid[cache_index]); // Cache Hit
// DEBUG CACHE HIT
assign o_cache_hit = cache_hit;
wire [31:0] next_o_buf_pc;
assign next_o_buf_pc = cache_valid[cache_index] ? current_pc : 32'h0;
wire [31:0] next_o_buf_inst;
assign next_o_buf_inst = cache_valid[cache_index] ? cache_data[cache_word_index] : 32'h0;

wire [31:0] cache_hit_data;
assign cache_hit_data = cache_data[cache_word_index];

wire [7:0] fetch_cache_index;
assign fetch_cache_index = o_wb_addr[11:4];
wire [11:0] fetch_cache_word_index;
assign fetch_cache_word_index = o_wb_addr[11:0];
wire [8:0] fetch_cache_tag;
assign fetch_cache_tag = o_wb_addr[20:12];

integer cacheline_fill_counter;
initial cacheline_fill_counter = 0;

always @(posedge i_clk) begin
    if (i_reset) begin // flush all cache
        current_state <= IDLE;
        cacheline_fill_counter <= 0;
`ifndef FORMAL
`ifndef VERILATOR
        for (i=0; i<256; i=i+1)
            cache_valid[i] <= 0;
`endif
`endif
    end
    else if (current_state == IDLE && (!cache_hit) && (!i_wb_stall || !o_wb_cyc)) begin
        // Don't begin untill unstall
        // On cache miss, go fetch
        cacheline_fill_counter <= 0;
        current_state <= FETCH_STROBE;
        o_wb_addr <= {current_pc[31:6], 4'b0};
    end else if (
        (current_state == FETCH_WAIT_ACK || current_state == FETCH_STROBE) 
        && (i_wb_ack) && (!i_wb_err)
    ) begin // Prioritize ack success
        // Succeed fetching
        cache_tags[fetch_cache_index] <= fetch_cache_tag;
        cache_data[fetch_cache_word_index] <= i_wb_data;
        if (cacheline_fill_counter == 15) begin
            current_state <= IDLE;
            cache_valid[fetch_cache_index] <= 1'b1;
        end
        else if (!i_wb_stall || !o_wb_cyc) begin
            o_wb_addr <= o_wb_addr + 1; // Fetch next instruction
            current_state <= FETCH_STROBE;
            cacheline_fill_counter <= cacheline_fill_counter + 1;
        end else
            current_state <= FETCH_NEXT;
    end
    else if ((current_state == FETCH_WAIT_ACK || current_state == FETCH_STROBE) && (i_wb_err)) begin
        current_state <= IDLE;
    end
    else if (current_state == FETCH_STROBE && (!i_wb_stall)) begin
        current_state <= FETCH_WAIT_ACK;
    end
    else if ((current_state == FETCH_NEXT) && (!i_wb_stall || !o_wb_cyc)) begin
        o_wb_addr <= o_wb_addr + 1;
        current_state <= FETCH_STROBE;
        cacheline_fill_counter <= cacheline_fill_counter + 1;
    end 
end

always @(posedge i_clk) begin
    if (i_reset) begin // STALL
        current_pc <= 0;
        o_buf_pc <= 0;
        o_buf_inst <= 0;
    end 
    else if (i_pipe_flush || i_new_pc) begin // FLUSH 
        o_buf_pc <= 0;
        o_buf_inst <= 0;
        if (i_new_pc)
            current_pc <= i_pc;
    end
    else if (!i_pipe_stall) begin
        if (current_state == IDLE && cache_hit) begin // IDLE Check is not nessary, but this improves performance
            o_buf_inst <= cache_hit_data;
            o_buf_pc <= current_pc;
            current_pc <= current_pc + 4;
        end else begin
            o_buf_inst <= 0;
            o_buf_pc <= 0;
        end
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
            if ($past(i_new_pc)) begin // new PC loads pc
                assert(current_pc == $past(i_pc));
            end else // flush preserves pc
                assert(current_pc == $past(current_pc));
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
