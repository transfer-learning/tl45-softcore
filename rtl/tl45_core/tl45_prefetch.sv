`default_nettype none

module tl45_prefetch(
    i_clk, i_reset,
    i_pipe_stall,
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
input wire i_pipe_stall; // Stall

// PC Override stuff
input wire i_new_pc;
input wire [31:0] i_pc;

// Wishbone
output reg o_wb_cyc, o_wb_stb, o_wb_we;
output wire [29:0] o_wb_addr; // WB Address
output reg [31:0] o_wb_data; // WB Data
output reg [3:0]  o_wb_sel; // WB Byte Sel (One hot)
initial begin
    o_wb_cyc = 0;
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
    if (i_reset) begin
        current_state <= IDLE;
        current_pc <= 0;
        o_wb_cyc <= 0;
        o_buf_pc <= 0;
        o_buf_inst <= 0;
    end 
    else if ((current_state == IDLE) && (!i_wb_stall)) begin // IDLE && Wishbone not stalled
        current_state <= FETCH_STROBE;
        o_wb_cyc <= 1'b1;
    end
    else if (current_state == FETCH_STROBE)
        current_state <= FETCH_WAIT_ACK;
    else if ((current_state == FETCH_WAIT_ACK) && (i_wb_ack) && (!i_wb_err)) begin // ACK with data
        current_pc <= current_pc + 4; // PC Increment
        o_buf_pc <= current_pc; // Load PC into buf
        o_buf_inst <= i_wb_data;
        o_wb_cyc <= 1'b0;
        current_state <= WRITE_OUT;
    end
    else if ((current_state == FETCH_WAIT_ACK) && (i_wb_ack) && (i_wb_err)) begin // ACK With Error
        o_wb_cyc <= 1'b0;
        current_state <= IDLE;
    end
    else if ((current_state == WRITE_OUT) && (!i_pipe_stall)) begin
        o_buf_inst <= 0;
        o_buf_pc <= 0;
        current_state <= IDLE;
    end
end

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

    initial assume(i_reset);
    initial assume(!i_wb_ack);
    initial assume(!i_wb_err);
    initial assume(!i_wb_stall);

    initial assert(!o_wb_cyc);
    initial assert(!o_wb_stb);

    always @(posedge i_clk) begin
        if ($past(i_reset)) begin
            assert(current_state == IDLE); // We Can Reset
        end
    end

    always @(*)
        if (current_state == IDLE) begin
            assert(!o_wb_cyc);
            assert(!o_wb_stb);
        end

    always @(*) begin
        if(o_wb_stb)
            assert(o_wb_cyc);
    end

    always @(*) begin
        if (current_state == FETCH_STROBE || current_state == FETCH_WAIT_ACK)
            assert(o_wb_cyc);
    end

    always @(posedge i_clk) begin
        if (f_past_valid && $past(o_wb_stb))
            assert(!o_wb_stb); // Assert stb will only last one clock
    end

    always @(*) begin
        if ((current_state == FETCH_STROBE || current_state == FETCH_WAIT_ACK) && i_wb_stall)
            assert(o_wb_cyc);
    end
`endif
endmodule
