module fuck_timer(
    i_clk,
    i_rst,
    o_stb_de2
);

input wire i_clk, i_rst;

output reg o_stb_de2;
initial begin
    o_stb_de2 = 0;
end

parameter counts_per_strobe = 5_000_0000;

reg [32:0] counter;
initial counter = 0;

always @(posedge i_clk) begin
    if (i_rst) begin
        counter <= 0;
        o_stb_de2 <= 0;
    end
    else if (counter < counts_per_strobe)
        counter <= counter + 1;
    else begin
        counter <= 0;
        o_stb_de2 <= !o_stb_de2;
    end
end

endmodule
