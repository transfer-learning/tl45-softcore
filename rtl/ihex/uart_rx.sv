module uart_rx
#(
    parameter I_CLOCK_FREQ = 50_000000,
    parameter BAUD_RATE = 115200
)
(i_clk, i_rx, o_rdy, o_data);

localparam QUARTER_CLK = (I_CLOCK_FREQ / BAUD_RATE / 4);
// The interval has a subtract 1 because it's 0 starting counter
localparam SAMPLE_INTERVAL = (I_CLOCK_FREQ / BAUD_RATE) - 1;

input wire i_clk, i_rx;
output wire o_rdy;
output reg [7:0] o_data;

reg i_rx_db, i_rx_int, i_rx_prev;

integer clk_counter;
wire sample = clk_counter >= SAMPLE_INTERVAL;

reg [3:0] internal_state;

localparam  IDLE = 0,
            RX_START = 2,
            RX_0 = 3,
            RX_1 = 4,
            RX_2 = 5,
            RX_3 = 6,
            RX_4 = 7,
            RX_5 = 8,
            RX_6 = 9,
            RX_7 = 10,
            RX_STOP = 11,
            RX_LAST_STATE = 12;

initial begin
    o_data = 0;
    i_rx_prev = 1;
    i_rx_db = 1;
    i_rx_int = 1;
    internal_state = IDLE;
    clk_counter = 0;
end

assign o_rdy = (internal_state == RX_STOP) && (clk_counter == 0);

// 2FF Sync
always @(posedge i_clk) begin
    {i_rx_prev, i_rx_db, i_rx_int} <= {i_rx_db, i_rx_int, i_rx};
end

always @(posedge i_clk) begin
    if (internal_state == IDLE) begin
        if (i_rx_prev && (!i_rx_db)) begin
            // Start Bit
            clk_counter <= 0;
            internal_state <= RX_START;
        end
    end
    else if (internal_state == RX_START) begin
        if (clk_counter < QUARTER_CLK)
            clk_counter <= clk_counter + 1;
        else begin
            clk_counter <= 0;
            internal_state <= RX_0;
        end
    end
    else begin
        if (!sample)
            clk_counter <= clk_counter + 1;
        else begin
            clk_counter <= 0;
            if (internal_state < RX_STOP)
                internal_state <= internal_state + 1;
            else
                internal_state <= IDLE;
            if (internal_state > RX_START && internal_state < RX_STOP)
                o_data <= {i_rx_db, o_data[7:1]};
        end
    end
end


`ifdef FORMAL

always @(*)
    assert(internal_state < RX_LAST_STATE);

`endif

endmodule