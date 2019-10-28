module sevenSegmentDisp(segs, data);
input [3:0] data;
output [6:0] segs;
reg [6:0] leds;

assign segs = ~leds;

always @(*)
begin
	case(data)
		4'h0: leds = 7'b1111110;
		4'h1: leds = 7'b0110000;
		4'h2: leds = 7'b1101101;
		4'h3: leds = 7'b1111001;
		4'h4: leds = 7'b0110011;
		4'h5: leds = 7'b1011011;
		4'h6: leds = 7'b1011111;
		4'h7: leds = 7'b1110000;
		4'h8: leds = 7'b1111111;
		4'h9: leds = 7'b1111011;
		4'hA: leds = 7'b1110111;
		4'hB: leds = 7'b0011111;
		4'hC: leds = 7'b1001110;
		4'hD: leds = 7'b0111101;
		4'hE: leds = 7'b1001111;
		4'hF: leds = 7'b1000111;
	endcase
end
endmodule