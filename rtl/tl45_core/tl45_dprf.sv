`default_nettype none

module tl45_dprf(
	input wire [3:0] readAdd1,
	input wire [3:0] readAdd2,
	input wire [3:0] writeAdd, 
	input wire [31:0] dataI,
	input wire clk,
	input wire reset,
	output reg [31:0] dataO1,
	output reg [31:0] dataO2
);

reg [31:0] registers[16];

initial begin
	for (integer i = 0; i < 16; i++)
		registers[i] = 0;
end

// Read Port 1 selection
always @(*)// TODO Maybe?
begin
	dataO1 = registers[readAdd1];
end

// Read Port 2 selection
always @(*)
begin
	dataO2 = registers[readAdd2];
end

// Write
always @(posedge clk)
begin
	if (writeAdd > 0) begin
		registers[writeAdd] <= dataI;
	end
end

`ifdef FORMAL

`endif

endmodule