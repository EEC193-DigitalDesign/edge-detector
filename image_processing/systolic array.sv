// processing element module
// 8*4 bit input = 12 bit output + log2(28^2) [=10] = 22 bit result_output

module PE (
	input logic clk, rst_n, en,
	input logic [7:0] pixel_input,
	input logic [3:0] filter_input,
	output logic [7:0] pixel_output,
	output logic [3:0] filter_output,
	output logic [21:0] result_output
);

always_ff @(posedge clk) begin
	if (~rst_n) begin
		result_output <= '0;
		pixel_output <= '0;
		filter_output <= '0;
	end else if (en) begin
		result_output <= (pixel_input * filter_input) + result_output;
		pixel_output <= pixel_input;
		filter_output <= filter_input;
	end
end

endmodule

// 28x28 systolic array, can make smaller but do full thing for now
// pixel input goes left to right, filter weight goes top to bottom

module systolic_array (
	input logic clk,
    input logic rst_n,
	input logic en_PE,
    input logic [7:0] top_pixel_in [27:0],
    input logic [3:0] top_filter_in[27:0],
    output logic [21:0] result_output_net[27:0][27:0]
);

logic [7:0] pixel_bus [27:0][27:0];
logic [3:0] filter_bus [27:0][27:0];

genvar i, j;

// i = row, j = column

generate 
	for (i = 0; i < 28; i++) begin : row
		for (j = 0; j < 28; j++) begin : col
			PE u_PE (
				.clk (clk),
				.rst_n (rst_n),
				.en (en_PE),
				.pixel_input ((j == 0) ? top_pixel_in[i] : row[i].col[j-1].pixel_output), // if left most, use bias as input
				.filter_input ((i == 0) ? top_filter_in[j] : row[i-1].col[j].filter_output), //if top most, use bias as input
				.pixel_output (pixel_bus[i][j]),
				.filter_output (filter_bus[i][j]),
				.result_output (result_output_net[i][j])
			);			
		end
	end
endgenerate

endmodule