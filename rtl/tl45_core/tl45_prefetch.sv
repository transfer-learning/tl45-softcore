`default_nettype none

module tl45_prefetch(
    i_clk, i_reset,
    i_pipe_stall,
    i_new_pc, i_pc
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

enum integer { IDLE = 0, FETCH_STROBE, FETCH_WAIT_ACK, WRITE_OUT } current_state;
initial current_state = IDLE;

// STATE MACHINE
// IDLE -> FETCH_STROBE -> FETCH_WAIT_ACK -> WRITE_OUT ->(Clear Local Buffer) IDLE

always @(posedge i_clk) begin
    if (i_reset) begin
        current_state <= IDLE;
        current_pc <= 0;
        o_buf_pc <= 0;
        o_buf_inst <= 0;
    end else 
    if ((current_state == IDLE) && (!i_wb_stall)) // IDLE && Wishbone not stalled
        current_state <= FETCH_STROBE;
    else if (current_state == FETCH_STROBE)
        current_state <= FETCH_WAIT_ACK;
    else if ((current_state == FETCH_WAIT_ACK) && (i_wb_ack) && (!i_wb_err)) begin // ACK with data
        current_pc <= current_pc + 4; // PC Increment
        o_buf_pc <= current_pc; // Load PC into buf
        o_buf_inst <= i_wb_data;
        current_state <= WRITE_OUT;
    end
    else if ((current_state == FETCH_WAIT_ACK) && (i_wb_ack) && (i_wb_err)) begin // ACK With Error
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
            o_wb_cyc = 1;
            o_wb_stb = 1;
        end
        default: begin
            o_wb_cyc = 0;
            o_wb_stb = 0;
        end
    endcase
end

// Buffer: PC, Instruction

endmodule
