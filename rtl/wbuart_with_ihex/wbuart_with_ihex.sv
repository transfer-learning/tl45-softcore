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


endmodule
