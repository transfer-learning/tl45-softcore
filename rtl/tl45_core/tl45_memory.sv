`default_nettype none

module tl45_memory(
    i_clk, i_reset,
    i_pipe_stall, o_pipe_stall,
    i_pipe_flush, o_pipe_flush,

    // Wishbone
    o_wb_cyc, o_wb_stb, o_wb_we,
    o_wb_addr, o_wb_data, o_wb_sel,
    i_wb_ack, i_wb_stall, i_wb_err,
    i_wb_data,

    // Buffer In
    i_buf_opcode,
    i_buf_dr, i_buf_sr1_val, i_buf_sr2_val, i_buf_imm,
    i_buf_pc,

    // Forwarding
    o_fwd_dr, o_fwd_val,

    // Buffer Out
    o_buf_dr, o_buf_val, o_ld_newpc, o_br_pc
);

input wire i_clk, i_reset;
input wire i_pipe_stall;
output reg o_pipe_stall;
input wire i_pipe_flush;
output reg o_pipe_flush;

// Wishbone 
output reg o_wb_cyc, o_wb_stb, o_wb_we;
output reg [29:0] o_wb_addr;
output reg [31:0] o_wb_data;
output reg [3:0] o_wb_sel;
initial begin
    o_wb_cyc = 0;
    o_wb_stb = 0;
    o_wb_we = 0;
    o_wb_data = 0;
    o_wb_addr = 0;
end

input wire i_wb_ack, i_wb_stall, i_wb_err;
input wire [31:0] i_wb_data;

// Buffer In
input wire [4:0] i_buf_opcode;
input wire [3:0] i_buf_dr;
input wire [31:0] i_buf_sr1_val, i_buf_sr2_val, i_buf_imm, i_buf_pc;

// Forwarding
output reg [3:0] o_fwd_dr;
output reg [31:0] o_fwd_val;
initial begin
    o_fwd_dr = 0;
    o_fwd_val = 0;
end

// Buffer Out
output reg [3:0] o_buf_dr;
output reg [31:0] o_buf_val;
output reg o_ld_newpc;
output reg [31:0] o_br_pc;
initial begin
    o_buf_dr = 0;
    o_buf_val = 0;
    o_ld_newpc = 0;
    o_br_pc = 0;
end


// Internal

// Small inconsistencies between LW, SW, IN, and OUT make this a little
// annoying. Here we generate a bunch of combinational logic so that the state
// machine is simpler.
//
// Buffer Layout:
//  LW: dr <- MEM[sr1+imm]
//  SW: MEM[sr1+imm] <- sr2
//  IN: dr <- IO[imm]
// OUT: IO[imm] <- sr1
//
// However IO is mapped onto the memory bus so mem_addr will hold the mapped
// address for IO. The correct write value will be resolved into wr_val.
//
// IO is mapped into the highest 16 bits of memory however the memory bus is
// only 30 bits wide. To reconcile this, the top 2 bits of the IO imm are
// ignored. 16 + 14 = 30 bits. mem_addr is 32 bits wide. The bottom two bits
// select within a 32 bit word for instruction where this is supported. (none
// right now). When sent on the wishbone bus, only the top 30 bits of mem_addr
// are sent.

wire start_tx;
assign start_tx = (i_buf_opcode == 5'h10 ||   // IN
                   i_buf_opcode == 5'h11 ||   // OUT
                   i_buf_opcode == 5'h14 ||   // LW
                   i_buf_opcode == 5'h15 ||   // SW
                   i_buf_opcode == 5'h12 ||   // LB
                   i_buf_opcode == 5'h0F ||   // LBSE
                   i_buf_opcode == 5'h13 ||     // SB
                   is_call || is_ret);

wire is_io;
assign is_io =    (i_buf_opcode == 5'h10 ||   // IN
                   i_buf_opcode == 5'h11);    // OUT

wire is_write;
assign is_write = (i_buf_opcode == 5'h11 ||   // OUT
                   i_buf_opcode == 5'h15 ||   // SW
                   i_buf_opcode == 5'h13 ||   // SB
                   is_call);

wire is_byte_operation;
assign is_byte_operation = (i_buf_opcode == 5'h12 ||  // LB
                            i_buf_opcode == 5'h0F ||  // LBSE
                            i_buf_opcode == 5'h13 );  // SB

wire is_call, is_ret;
assign is_call = i_buf_opcode == 5'h0D;
assign is_ret = i_buf_opcode == 5'h0E;

reg [31:0] mem_addr;
always @(*)
    if (is_io)
        mem_addr = {16'hff, i_buf_imm[13:0], 2'b00};
    else if (is_call)
        mem_addr = i_buf_sr2_val - 4;
    else if (is_ret)
        mem_addr = i_buf_sr2_val;
    else
        mem_addr = i_buf_sr1_val + i_buf_imm;

wire [31:0] wr_val;
assign wr_val = is_io ? i_buf_sr1_val : i_buf_sr2_val;

reg [3:0] wb_sel_val;
always @(*)
    if (is_byte_operation)
        case(mem_addr[1:0])
            3: wb_sel_val = 4'b0001;
            2: wb_sel_val = 4'b0010;
            1: wb_sel_val = 4'b0100;
            default: wb_sel_val = 4'b1000;
        endcase
    else
        wb_sel_val = 4'b1111;

reg [31:0] write_data;
always @(*)
    if (is_byte_operation)
        case(mem_addr[1:0])
            3: write_data = wr_val;
            2: write_data = wr_val << 8;
            1: write_data = wr_val << 16;
            default: write_data = wr_val << 24;
        endcase
    else if (is_call)
        write_data = i_buf_pc + 4;
    else
        write_data = wr_val;


// WOW Verilog, you are like Tiger
function [7:0] trunc_32_to_8(input [31:0] val32);
  trunc_32_to_8 = val32[7:0];
endfunction


reg [31:0] in_data;
reg [7:0] shifted_i_data;
always @(*)
    if (is_byte_operation) begin
        case(mem_addr[1:0])
            3: shifted_i_data = trunc_32_to_8(i_wb_data);
            2: shifted_i_data = trunc_32_to_8(i_wb_data >> 8);
            1: shifted_i_data = trunc_32_to_8(i_wb_data >> 16);
            default: shifted_i_data = trunc_32_to_8(i_wb_data >> 24);
        endcase
        if (i_buf_opcode == 5'h0F) // LWSE
            in_data = {{24{shifted_i_data[7]}}, shifted_i_data};
        else
            in_data = {24'h0, shifted_i_data};
    end
    else
        in_data = i_wb_data;


localparam
    IDLE = 0,
    READ_STROBE = 1,
    READ_WAIT_ACK = 2,
    READ_STALLED_OUT = 3,
    READ_OUT = 4,
    WRITE_STROBE = 5,
    WRITE_WAIT_ACK = 6,
    LAST_STATE = 7;

reg [3:0] current_state;
initial current_state = IDLE;

// wishbone combinational control signals
assign o_wb_stb = (current_state == READ_STROBE) || (current_state == WRITE_STROBE);
assign o_wb_we  = (current_state == WRITE_STROBE);
assign o_wb_cyc = (current_state != IDLE && current_state != LAST_STATE);

reg internal_stall;
initial internal_stall = 0;
assign o_pipe_stall = i_pipe_stall || internal_stall;

// internal state machine control signals
wire state_strobe, state_wait_ack;
assign state_strobe = (current_state == READ_STROBE) || (current_state == WRITE_STROBE);
assign state_wait_ack = (current_state == READ_WAIT_ACK) || (current_state == WRITE_WAIT_ACK);

always @(*)
    case (current_state)
        IDLE: internal_stall = start_tx;
        READ_STROBE,
        WRITE_STROBE: internal_stall = 1;
        READ_WAIT_ACK,
        WRITE_WAIT_ACK: internal_stall = 1;
        READ_STALLED_OUT: internal_stall = 1;
        READ_OUT: internal_stall = 0;
        default: internal_stall = 1;
    endcase

reg [31:0] temp_read;

always @(*)
    case (current_state)
        READ_STALLED_OUT: begin
            o_fwd_dr = !is_write ? i_buf_dr : 0;
            o_fwd_val = !is_write ? temp_read : 0;
        end
        READ_WAIT_ACK: begin
            o_fwd_dr = !i_pipe_stall ? i_buf_dr : 0;
            o_fwd_val = !i_pipe_stall ? (i_wb_err ? 32'h13371337 : i_wb_data) : 0;
        end
        default: begin
            o_fwd_dr = 0;
            o_fwd_val = 0;
        end
    endcase

always @(posedge i_clk) begin
    if (i_reset || i_pipe_flush) begin // TODO i_pipe_flush not handled properly
        current_state <= IDLE;

        o_wb_addr <= 0;
        o_wb_data <= 0;
        o_wb_sel <= 0;

        o_buf_dr <= 0;
        o_buf_val <= 0;
    end
    if (i_pipe_stall) begin
    end
    else if ((current_state == IDLE) && start_tx) begin
        current_state <= is_write ? WRITE_STROBE : READ_STROBE;
        o_wb_addr <= mem_addr[31:2];
        o_wb_sel <= wb_sel_val;

        if (is_write)
            o_wb_data <= write_data;
    end
    else if (state_strobe && !i_wb_stall) begin
        current_state <= current_state == READ_STROBE ? READ_WAIT_ACK : WRITE_WAIT_ACK;
        o_wb_addr <= 0;

        o_wb_data <= 0;
    end
    // TODO probably not correct when wb response is on the same clock as the
    // request.
    else if (state_wait_ack && i_wb_err) begin
        // for now we'll just squash bus error as a special read value.
        // for write, whatever.
        current_state <= current_state == READ_WAIT_ACK ? (i_pipe_stall ? READ_STALLED_OUT : READ_OUT) : IDLE;

        if (!is_write) begin
            if (i_pipe_stall)
                temp_read <= 32'h13371337;
            else begin
                o_buf_dr <= i_buf_dr;
                o_buf_val <= 32'h13371337;
            end
        end
    end
    else if (state_wait_ack && i_wb_ack && !i_wb_err) begin

        if (current_state == READ_WAIT_ACK)
            current_state <= i_pipe_stall ? READ_STALLED_OUT : READ_OUT;
        else if (is_call)
            current_state <= READ_OUT;
        else
            current_state <= READ_OUT;

        o_wb_sel <= 0;

        if (is_call) begin
            o_ld_newpc <= 1;
            o_br_pc <= i_buf_sr1_val + i_buf_imm;
        end

        if (is_call || is_ret)
            o_pipe_flush <= 1;

        if (!is_write) begin
            if (i_pipe_stall)
                temp_read <= in_data;
            else begin
                if (is_ret) begin
                    o_ld_newpc <= 1;
                    o_br_pc <= in_data;
                end
                else begin
                    o_buf_dr <= i_buf_dr;
                    o_buf_val <= in_data;
                end
            end
        end
    end
    else if (current_state == READ_STALLED_OUT && !i_pipe_stall) begin
        current_state <= READ_OUT;

        if (is_ret) begin
            o_ld_newpc <= 1;
            o_br_pc <= temp_read;
        end
        else begin
            o_buf_dr <= i_buf_dr;
            o_buf_val <= temp_read;
        end

        temp_read <= 0;
    end
    else if (current_state == READ_OUT) begin
        current_state <= IDLE;
        o_buf_dr <= 0;
        o_buf_val <= 0;
        o_ld_newpc <= 0;
        o_br_pc <= 0;
        o_pipe_flush <= 0;
    end
end





endmodule : tl45_memory


