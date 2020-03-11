module wbuart_with_buffer
#(
    parameter I_CLOCK_FREQ = 50_000_000,
    parameter BAUD_RATE = 115200
)
(i_clk, i_reset,
i_rx_data, i_rx_stb,
o_tx_data, o_tx_stb, i_tx_busy,
// Wishbone
i_wb_cyc, i_wb_stb,
i_wb_we, i_wb_sel,
o_wb_stall, o_wb_ack, o_wb_err,
i_wb_addr, i_wb_data, o_wb_data
);

// ====== Begin IO ======
input wire i_clk, i_reset;
// RX
input wire [7:0] i_rx_data;
input wire i_rx_stb;
// TX
output reg [7:0] o_tx_data;
output reg o_tx_stb;
initial o_tx_stb = 0;
input wire i_tx_busy;
// Wishbone
input wire i_wb_cyc, i_wb_stb, i_wb_we;
input wire [3:0] i_wb_sel;
output wire o_wb_stall, o_wb_ack, o_wb_err;
input wire [29:0] i_wb_addr;
input wire [31:0] i_wb_data;
output reg [31:0] o_wb_data;
// ====== END IO ======


wire internal_stall;

// Rx Circular Buffer Related
reg [7:0] rx_buffer [512];
reg [8:0] rx_read_pointer, rx_write_pointer;
reg rx_overrun;
wire [8:0] rx_size = rx_write_pointer - rx_read_pointer;
wire [8:0] rx_next_write = rx_write_pointer + 1;
wire rx_full = rx_next_write == rx_read_pointer;

assign o_wb_stall = internal_stall;

initial begin
    rx_read_pointer = 0;
    rx_write_pointer = 0;
    rx_overrun = 0;
end

// ==== Wishbone Statemachine =====
localparam
    WBIDLE = 4'h0,
    WBEXEC = 4'h1,
    WBACK = 4'h2;
reg [3:0] wb_state;
initial begin
    wb_state = WBIDLE;
end

assign internal_stall = wb_state != WBIDLE;
assign o_wb_ack = wb_state == WBACK;

// Sequential Logic
always @(posedge i_clk) begin
    if (i_reset) begin
        rx_read_pointer <= 0;
        rx_write_pointer <= 0;
        rx_overrun <= 0;
    end
    else if (i_rx_stb) begin
        if (rx_full) begin
            rx_overrun <= 1;
            rx_read_pointer <= rx_read_pointer + 1;
        end
        rx_buffer[rx_write_pointer] <= i_rx_data;
        rx_write_pointer <= rx_next_write;
    end

    // Wishbone
    if (i_reset || (!i_wb_cyc)) begin // Abort transaction if !cyc
        wb_state <= WBIDLE;
        o_tx_stb <= 0;
    end else if (wb_state == WBIDLE) begin
        if (i_wb_stb && i_wb_cyc) begin
            if (i_wb_addr[0]) begin // Addr end in 1 is Data port
                if (i_wb_we) begin
                    o_tx_data <= i_wb_data[7:0];
                    if (!i_tx_busy) begin // if transimit is idle
                        o_tx_stb <= 1;
                        wb_state <= WBACK;
                    end else begin // TX is busy
                        wb_state <= WBEXEC;
                    end
                end else begin
                    // READ
                    wb_state <= WBACK;
                    if (rx_size > 0) begin
                        o_wb_data <= {24'h0, rx_buffer[rx_read_pointer]};
                        rx_read_pointer <= rx_read_pointer + 1;
                    end else
                        o_wb_data <= 32'h0;
                end
            end else begin // Data Port ends in 0
                if (i_wb_we) begin // Write Control
                    wb_state <= WBACK;
                end else begin // Read Control
                    // Control Format
                    // | 1' OVERRUN | 22' h0 | 9' AVAIL |
                    o_wb_data <= {rx_overrun, 22'h0, rx_size};
                    wb_state <= WBACK;
                end
            end
        end
    end else if (wb_state == WBEXEC) begin
        if (!i_tx_busy) begin
            o_tx_stb <= 1;
            wb_state <= WBACK;
        end
    end else if (wb_state == WBACK) begin
        wb_state <= WBIDLE;
        o_tx_stb <= 0; // Disable Serial Strobe
    end

    // Clear Overrun if the buffer is fully read
    if (rx_size == 0) begin
        rx_overrun <= 0;
    end
end


endmodule
