module clk_divider(i_clk, i_reset, o_clk);
input wire i_clk, i_reset;
output wire o_clk;

parameter ICLK_FREQ = 50_000_000; // 50 MHz
parameter OCLK_FREQ = 64;
localparam COUNTER_TARGET = (ICLK_FREQ / OCLK_FREQ) - 1;

reg [31:0] counter;
initial begin
    counter = 0;
end

assign o_clk = (!i_reset) && (counter <= (COUNTER_TARGET / 2));

always @(posedge i_clk) begin
    if (i_reset)
        counter <= 0;
    else if (counter >= COUNTER_TARGET)
        counter <= 0;
    else
        counter <= counter + 1;
end

endmodule