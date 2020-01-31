`include "wishbone.sv"
/*
    Processes Intel Hex and Response with Single Letter ACK
    -------
    ACK Codes
    E: Checksum Error
    U: Unknown Command
    S: 32bit mode offset Set
    M: Malformed Command
    R: END OF FILE, offset reset;
    W: Wishbone Error;
    K: Write Complete
*/

module ihex(
    input wire i_clk, i_reset,
    input wire [7:0] i_rx_data,
    input wire i_rx_stb,
    output reg [7:0] o_tx_data,
    output wire o_tx_stb,
    input wire i_tx_busy,
    wishbone.master wb
);


assign o_tx_stb = state == EXEC_ACK;

function [3:0] hex_to_val;
input [7:0] ascii;
begin
    case(ascii)
        "0": hex_to_val = 4'h0;
        "1": hex_to_val = 4'h1;
        "2": hex_to_val = 4'h2;
        "3": hex_to_val = 4'h3;
        "4": hex_to_val = 4'h4;
        "5": hex_to_val = 4'h5;
        "6": hex_to_val = 4'h6;
        "7": hex_to_val = 4'h7;
        "8": hex_to_val = 4'h8;
        "9": hex_to_val = 4'h9;
        "a", "A": hex_to_val = 4'ha;
        "b", "B": hex_to_val = 4'hb;
        "c", "C": hex_to_val = 4'hc;
        "d", "D": hex_to_val = 4'hd;
        "e", "E": hex_to_val = 4'he;
        "f", "F": hex_to_val = 4'hf;
        default: hex_to_val = 4'h0;
    endcase
end
endfunction

localparam  IDLE=0,
            CMD1=1, CMD2=2,
            LEN1=3, LEN2=4,
            ADDR1=5, ADDR2=6, ADDR3=7, ADDR4=8,
            EXEC=9, EXEC2=10,
            CHKSUM=11, CHKSUM2=12,
            EXEC_ACK=13, EXEC_WB_REQ=14, EXEC_WB_WAIT=15
;

reg [3:0] state;
initial begin
    state = IDLE;
end

reg [7:0] buffer [256];
reg [7:0] computed_sum;
reg [7:0] cmd;
reg [7:0] len;
reg [15:0] addr;
reg [7:0] buffer_fill;
reg filled_high;
reg [7:0] cmp_sum;
reg [15:0] addr_offset; initial addr_offset = 0; // 32bit mode offset
wire [7:0] computed_sum_tcmp = (~computed_sum + 1); // 2's complement of computed_sum
wire [15:0] write_addr = addr + {8'h0, buffer_fill};

reg [3:0] wb_sel;
reg [29:0] wb_addr;
reg [31:0] wb_mosi_data;

assign wb.stb = state == EXEC_WB_REQ;
assign wb.cyc = (state == EXEC_WB_REQ || state == EXEC_WB_WAIT);
assign wb.sel = wb_sel;
assign wb.addr = wb_addr;
assign wb.mosi_data = wb_mosi_data;
assign wb.we = 1;

always @(posedge i_clk) begin
    if (i_rx_stb) begin
        if (state == IDLE) begin
            if (i_rx_data == ":") begin
                computed_sum <= 0;
                cmd <= 0;
                state <= LEN1;
            end
        end else if (state == CMD1) begin
            cmd <= {hex_to_val(i_rx_data), 4'h0};
            state <= CMD2;
        end else if (state == CMD2) begin
            cmd <= {cmd[7:4], hex_to_val(i_rx_data)};
            computed_sum <= computed_sum + {cmd[7:4], hex_to_val(i_rx_data)};
            buffer_fill <= 0;
            filled_high <= 0;
            if (len > 0)
                state <= EXEC;
            else
                state <= CHKSUM;
        end else if (state == LEN1) begin
            len <= {hex_to_val(i_rx_data), 4'h0};
            state <= LEN2;
        end else if (state == LEN2) begin
            len <= {len[7:4], hex_to_val(i_rx_data)};
            computed_sum <= computed_sum + {len[7:4], hex_to_val(i_rx_data)};
            state <= ADDR1;
        end else if (state == ADDR1) begin
            addr <= {hex_to_val(i_rx_data), 12'h0};
            state <= ADDR2;
        end else if (state == ADDR2) begin
            addr <= {addr[15:12], hex_to_val(i_rx_data), 8'h0};
            computed_sum <= computed_sum + {addr[15:12], hex_to_val(i_rx_data)};
            state <= ADDR3;
        end else if (state == ADDR3) begin
            addr <= {addr[15:8], hex_to_val(i_rx_data), 4'h0};
            state <= ADDR4;
        end else if (state == ADDR4) begin
            addr <= {addr[15:4], hex_to_val(i_rx_data)};
            computed_sum <= computed_sum + {addr[7:4], hex_to_val(i_rx_data)};
            state <= CMD1;
        end else if (state == EXEC) begin
            if (filled_high) begin
                buffer[buffer_fill] <= {buffer[buffer_fill][7:4], hex_to_val(i_rx_data)};
                computed_sum <= computed_sum + {buffer[buffer_fill][7:4], hex_to_val(i_rx_data)};
                filled_high <= 0;
                if (buffer_fill + 1 < len)
                    buffer_fill <= buffer_fill + 1;
                else
                    state <= CHKSUM;
            end else begin
                buffer[buffer_fill] <= {hex_to_val(i_rx_data), 4'h0};
                filled_high <= 1;
            end
        end else if (state == CHKSUM) begin
            cmp_sum <= {hex_to_val(i_rx_data), 4'h0};
            state <= CHKSUM2;
        end else if (state == CHKSUM2) begin
            cmp_sum <= {cmp_sum[7:4], hex_to_val(i_rx_data)};
            state <= EXEC2;
        end
    end
    if (state == EXEC2) begin
        if (!i_tx_busy) begin
            if (computed_sum_tcmp == cmp_sum) begin
                // Check Command Mode and Execute
                case(cmd)
                    8'h0: begin
                        if (len > 0) begin // WRITE
                            buffer_fill <= 1;
                            wb_addr <= {addr_offset, addr[15:2]};
                            case(addr[1:0])
                                2'h3: wb_sel <= 4'b0001;
                                2'h2: wb_sel <= 4'b0010;
                                2'h1: wb_sel <= 4'b0100;
                                2'h0: wb_sel <= 4'b1000;
                            endcase
                            case(addr[1:0])
                                2'h0: wb_mosi_data <= {buffer[0], 24'h0};
                                2'h1: wb_mosi_data <= {8'h0, buffer[0], 16'h0};
                                2'h2: wb_mosi_data <= {16'h0, buffer[0], 8'h0};
                                2'h3: wb_mosi_data <= {24'h0, buffer[0]};
                            endcase
                            state <= EXEC_WB_REQ;
                        end else begin
                            o_tx_data <= "K";
                            state <= EXEC_ACK;
                        end
                    end
                    8'h1: begin // END OF FILE
                        addr_offset <= 0;
                        o_tx_data <= "R";
                        state <= EXEC_ACK;
                    end
                    8'h4: // Offset SET
                        if (len == 8'h2) begin
                            addr_offset <= { buffer[0], buffer[1] };
                            o_tx_data <= "S";
                            state <= EXEC_ACK;
                        end else begin
                            o_tx_data <= "M";
                            state <= EXEC_ACK;
                        end
                    default: begin
                        o_tx_data <= "U";
                        state <= EXEC_ACK;
                    end
                endcase
            end else begin
                o_tx_data <= "E";
                state <= EXEC_ACK;                
            end
        end
    end
    if (state == EXEC_WB_REQ) begin
        if (!wb.stall) begin
            if (wb.err) begin
                o_tx_data <= "W";
                state <= EXEC_ACK;
            end
            else if (wb.ack) begin
                if (buffer_fill < len) begin
                    buffer_fill <= buffer_fill + 1; // INC Buffer Fill
                    wb_addr <= {addr_offset, write_addr[15:2]};
                    case(write_addr[1:0])
                        2'h3: wb_sel <= 4'b0001;
                        2'h2: wb_sel <= 4'b0010;
                        2'h1: wb_sel <= 4'b0100;
                        2'h0: wb_sel <= 4'b1000;
                    endcase
                    case(write_addr[1:0])
                        2'h0: wb_mosi_data <= {buffer[buffer_fill], 24'h0};
                        2'h1: wb_mosi_data <= {8'h0, buffer[buffer_fill], 16'h0};
                        2'h2: wb_mosi_data <= {16'h0, buffer[buffer_fill], 8'h0};
                        2'h3: wb_mosi_data <= {24'h0, buffer[buffer_fill]};
                    endcase
                    state <= EXEC_WB_REQ;
                end else begin
                    o_tx_data <= "K";
                    state <= EXEC_ACK;
                end
            end else begin
                state <= EXEC_WB_WAIT;
            end
        end
    end
    if (state == EXEC_WB_WAIT) begin
        if (wb.err) begin
                o_tx_data <= "W";
                state <= EXEC_ACK;
        end
        else if (wb.ack) begin
            if (buffer_fill < len) begin
                buffer_fill <= buffer_fill + 1; // INC Buffer Fill
                wb_addr <= {addr_offset, write_addr[15:2]};
                case(write_addr[1:0])
                    2'h3: wb_sel <= 4'b0001;
                    2'h2: wb_sel <= 4'b0010;
                    2'h1: wb_sel <= 4'b0100;
                    2'h0: wb_sel <= 4'b1000;
                endcase
                case(write_addr[1:0])
                    2'h0: wb_mosi_data <= {buffer[buffer_fill], 24'h0};
                    2'h1: wb_mosi_data <= {8'h0, buffer[buffer_fill], 16'h0};
                    2'h2: wb_mosi_data <= {16'h0, buffer[buffer_fill], 8'h0};
                    2'h3: wb_mosi_data <= {24'h0, buffer[buffer_fill]};
                endcase
                state <= EXEC_WB_REQ;
            end else begin
                o_tx_data <= "K";
                state <= EXEC_ACK;
            end
        end
    end
    if (state == EXEC_ACK) begin
        state <= IDLE; // Operation Complete
    end
    if (i_reset) begin
        state <= IDLE;
    end
end

endmodule
