`default_nettype none

module tl45_nofetch(
    i_clk, i_reset,
    i_pipe_stall,
    i_pipe_flush,
    i_new_pc, i_pc,

    // Buffer
    o_buf_pc, o_buf_inst
);

    input wire i_clk, i_reset; // Sys CLK, Reset
    input wire i_pipe_stall; // Stall
    input wire i_pipe_flush; // Stall

// PC Override stuff
    input wire i_new_pc;
    input wire [31:0] i_pc;

// Buffer
    output reg [31:0] o_buf_pc, o_buf_inst;
    initial begin
        o_buf_pc = 0;
        o_buf_inst = 0;
    end

// Internal PC
    reg [31:0] current_pc;
    initial current_pc = 0;

    wire [31:0] next_pc = i_new_pc ? i_pc : (current_pc + 4);

    always @(posedge i_clk) begin
        if (i_reset || i_pipe_flush) begin
            if (i_reset)
                current_pc <= 0;
            else
                current_pc <= next_pc;

            o_buf_pc <= 0;
            o_buf_inst <= 0;
        end
        else if (!i_pipe_stall) begin

            current_pc <= next_pc; // PC Increment
            o_buf_pc <= current_pc;

            // ADDI r1, r0, 1  :  0d 10 00 01
            // ADD r1, r1, r1  :  08 11 10 00
            case (current_pc[31:2])
                0: o_buf_inst <= 32'h0d106969;

                // 1: o_buf_inst <= 32'b01100101111100000000000000000000; // JMP 0
                1: o_buf_inst <= 32'b10101001000100000100001001000010;
                2: o_buf_inst <= 32'b10100001001000000100001001000010;
                3: o_buf_inst <= 32'b10100001001100000100001001000011;
                default: o_buf_inst <= 0; // 32'h08111000; // ADD r1, r1, r1
            endcase

        end
    end

endmodule
