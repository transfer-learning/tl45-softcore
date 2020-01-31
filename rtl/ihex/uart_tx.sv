module uart_tx
#(
    parameter I_CLOCK_FREQ = 50_000000,
    parameter BAUD_RATE = 115200
)
(
 i_clk,
 i_data, i_stb,
 o_tx, o_busy
);

input wire i_clk;
input wire [7:0] i_data;
input wire i_stb;

output reg o_tx;
output wire o_busy;

initial begin
    o_tx = 1;
end

// Subtract 1 due to counter is zero starting
localparam SAMPLE_INTERVAL = (I_CLOCK_FREQ / BAUD_RATE) - 1;
integer counter;
reg [3:0] state;
reg [7:0] data;

initial begin
    counter = 0;
    state = 0;
end

assign o_busy = state != IDLE;

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

always @(posedge i_clk) begin
    if (state == IDLE) begin
        if (i_stb) begin
            counter <= 0;
            state <= RX_START;
            data <= i_data;
        end
    end
    else begin
        if (counter == SAMPLE_INTERVAL) begin
            counter <= 0;
            if (state == RX_STOP)
                state <= IDLE;
            else
                state <= state + 1;
        end
        else
            counter <= counter + 1;
    end
end

always @(*) begin
    case(state)
        RX_START: o_tx = 0;
        IDLE,
        RX_STOP: o_tx = 1;
        default: o_tx = data[state - 3];
    endcase
end

`ifdef FORMAL

always @(*) begin
    assert(counter <= SAMPLE_INTERVAL);
    assert(state < RX_LAST_STATE);
end

reg past_valid;
initial past_valid = 0;
always @(posedge i_clk) past_valid <= 1;

always @(posedge i_clk) begin
    if (past_valid && $past(state) != IDLE) begin
        assert(counter != $past(counter));
    end
end

`endif

endmodule
