module wbuart_with_ihex
#(
    parameter I_CLOCK_FREQ=50_000000,
    parameter BAUD_RATE=115200,
    parameter WB_CTRL_REG_ADDR=30'h7FFF_FFFE,
    parameter WB_DATA_REG_ADDR=30'h7FFF_FFFF,
)
(
    i_clk, i_reset,
    i_rx, o_tx,
    master,
    slave,
    o_device_sel,
);

input wire i_clk, i_reset;
input wire i_rx;
output wire o_tx;
wishbone.master ihex_master;
wishbone.slave uart_slave;

reg slave_mode; initial slave_mode = 0;

/* SERIAL RX */
wire [7:0] rx_data;
wire rx_stb;
uart_rx rx_part
#(.CLK_SPEED, .BAUD)
(i_clk, i_rx, rx_stb, rx_data);
/* END SERIAL RX */

/* SERIAL TX */
wire [7:0] tx_data;
wire tx_stb, tx_busy;
uart_tx tx_part
#(.CLK_SPEED,.BAUD)
(
 i_clk,
 tx_data, tx_stb,
 o_tx, tx_busy 
);
/* END SERIAL TX */

wire ihex_reset = slave_mode ? 1 : i_reset;
/* IHEX CONTROLLER */
wire [7:0] ihex_tx_data;
wire ihex_tx_stb;
ihex intel_hex_controller(
    i_clk, i_reset,
    rx_data,
    rx_stb && (~slave_mode),
    ihex_tx_data,
    ihex_tx_stb,
    tx_busy,
    ihex_master 
);

/* UART ARBITRATION */

always @(posedge i_clk) begin
    if (i_reset) begin
        slave_mode <= 0;
    end
    else if (uart_slave.addr == WB_CTRL_REG_ADDR) begin
        if (uart_slave.stb && uart_slave.cyc && uart_slave.we) begin
            slave_mode <= 1;
        end
    end
end

endmodule
