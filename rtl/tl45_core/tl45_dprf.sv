`default_nettype none

module tl45_dprf(
	input wire [3:0] readAdd1,
	input wire [3:0] readAdd2,
	input wire [3:0] writeAdd, 
	input wire [31:0] dataI,
	input wire wrREG,
	input wire clk,
	input wire reset,
	output reg [31:0] dataO1,
	output reg [31:0] dataO2
);

reg [31:0] registers[15];

initial begin
	for (integer i = 0; i < 15; i++)
		registers[i] = 0;
end

// Read Port 1 selection
always @(*)// TODO Maybe?
begin
	if (readAdd1 == 0)
		dataO1 = 0;
	else
		dataO1 = registers[readAdd1 - 1];
end

// Read Port 2 selection
always @(*)
begin
	if (readAdd2 == 0)
		dataO2 = 0;
	else
		dataO2 = registers[readAdd2 - 1];
end

// Write
always @(posedge clk)
begin
	if (reset) begin
		for (integer i = 0; i < 15; i++)
			registers[i] <= 0;
	end
	else if (wrREG && (writeAdd > 0)) begin
		registers[writeAdd - 1] <= dataI;
	end
end

`ifdef FORMAL

`endif

endmodule