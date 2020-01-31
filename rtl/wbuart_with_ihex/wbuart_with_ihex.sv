module wbuart_with_ihex
#(
    parameter I_CLOCK_FREQ=50_000000,
    parameter BAUD_RATE=115200
)
(
    i_clk, i_reset,
    i_rx, o_tx,
    // Master Wishbone
    o_mwb_cyc, o_mwb_stb,
    o_mwb_we, o_mwb_sel,
    i_mwb_stall, i_mwb_ack, i_mwb_err,
    o_mwb_addr, o_mwb_data, i_mwb_data,
    // Slave Wishbone
    i_wb_cyc, i_wb_stb,
    i_wb_we, i_wb_sel,
    o_wb_stall, o_wb_ack, o_wb_err,
    i_wb_addr, i_wb_data, o_wb_data
);

input wire i_clk, i_reset;
input wire i_rx;
output wire o_tx;


// Master Wishbone
output wire o_mwb_cyc, o_mwb_stb, o_mwb_we;
output wire [3:0] o_mwb_sel;
input wire i_mwb_stall, i_mwb_ack, i_mwb_err;
output wire [31:0] o_mwb_data;
input wire [31:0] i_mwb_data;
output wire [29:0] o_mwb_addr;

input wire i_wb_cyc, i_wb_stb, i_wb_we;
input wire [3:0] i_wb_sel;
output wire o_wb_stall, o_wb_ack, o_wb_err;
input wire [29:0] i_wb_addr;
input wire [31:0] i_wb_data;
output wire [31:0] o_wb_data;


reg slave_mode; initial slave_mode = 0;

/* SERIAL RX */
wire [7:0] rx_data;
wire rx_stb;
uart_rx rx_part(i_clk, i_rx, rx_stb, rx_data);
/* END SERIAL RX */

/* SERIAL TX */
reg [7:0] tx_data;
reg tx_stb;
wire tx_busy;
uart_tx tx_part (
 i_clk,
 tx_data, tx_stb,
 o_tx, tx_busy 
);
/* END SERIAL TX */


wishbone ihex_wb();

wb_master_breakout dbg_bus_breakout(
    i_mwb_ack, i_mwb_err, i_mwb_stall,
    i_mwb_data, o_mwb_stb, o_mwb_cyc, o_mwb_we,
    o_mwb_sel, o_mwb_addr, o_mwb_data,
    ihex_wb
);

wire ihex_reset = slave_mode ? 1 : i_reset;
/* IHEX CONTROLLER */
wire [7:0] ihex_tx_data;
wire ihex_tx_stb;
ihex intel_hex_controller(
    i_clk, ihex_reset,
    rx_data,
    rx_stb && (!slave_mode),
    ihex_tx_data,
    ihex_tx_stb,
    tx_busy,
    ihex_wb.master
);

/* WBUART CONTROLLER */
wire uart_tx_stb;
wire [7:0] uart_tx_data;
wbuart_with_buffer uart_ctrlr
(i_clk, i_reset,
rx_data, rx_stb && slave_mode,
uart_tx_data, uart_tx_stb, tx_busy,
// Wishbone
i_wb_cyc, i_wb_stb,
i_wb_we, i_wb_sel,
o_wb_stall, o_wb_ack, o_wb_err,
i_wb_addr, i_wb_data, o_wb_data
);

/* UART ARBITRATION */
always @(*) begin
    if (slave_mode) begin
        tx_stb = uart_tx_stb;
        tx_data = uart_tx_data;
    end else begin
        tx_stb = ihex_tx_stb;
        tx_data = ihex_tx_data;
    end
end

always @(posedge i_clk) begin
    if (i_reset) begin
        slave_mode <= 0;
    end
    if (i_wb_stb && i_wb_cyc && i_wb_we) begin
        slave_mode <= 1;
    end
end

endmodule
