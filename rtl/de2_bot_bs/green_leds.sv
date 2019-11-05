module green_leds(iclk, iaddr, idata, icyc, iwr, leds);

parameter [15:0] IO_ADDR = 0;
input wire [7:0] iaddr;
input wire [15:0] idata;
input wire icyc, iwr, iclk;

output reg [7:0] leds;

always @(posedge iclk) begin
    if (icyc && iwr && iaddr == IO_ADDR)
        leds <= idata[7:0];
end

endmodule
