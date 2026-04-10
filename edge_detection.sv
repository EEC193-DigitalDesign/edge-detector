// VGA_X_OUT = luminance (all the colors are equal to each other)
// step 1-get grayscaled frame into matrix form
// step 2-convolute to get Gx and Gy

// line buffers to store rows of the output

module PE (
	input logic clk, clr_n,
	input logic [7:0] PE_in1, PE_in2,
	output logic [7:0] PE_out
);

always_ff @(posedge clk or negedge clr) begin
	if (!clr_n) begin
		PE_out <= '0;
	end else begin
		PE_out <= buffer + (PE_in1 * PE_in2);
	end
end
endmodule

module edge_detector #(
	parameter int num_PE = 8
)
(
	input logic clk,
	input logic [7:0] pixel_input,
	output logic [7:0] pixel_output
);

logic [7:0] pixel_output_X, pixel_output_Y;

logic [7:0] line_memory [639:0][2:0]; //line buffer

// create a line buffer to store rows of the input
always_ff @(posedge clk) begin
	line_memory <= pixel_input;
end

// generate PEs
for (genvar g = 0, g < num_PE, g++) 
	begin: gen_pe_array
		PE PE_inst_X (
			.clk(clk),
			.PE_in1(line_memory[g]),
			.PE_in2(SOBEL_X[g])
		);
		
		PE PE_inst_Y (
			.clk(clk),
			.PE_in1(line_memory[g]),
			.PE_in2(SOBEL_Y[g])
		);
	end
endgenerate
	
// store Gx and Gy filters as local params
localparam logic signed [7:0] SOBEL_X [0:2][0:2] = '{
    '{-1,  0,  1},
    '{-2,  0,  2},
    '{-1,  0,  1}
};

localparam logic signed [7:0] SOBEL_Y [0:2][0:2] = '{
    '{1,  2,  1},
    '{0,  0,  0},
    '{-1,  -2,  -1}
};

// loop counters for convolution
// i = row, j = col, k = dot product accumulation
localparam logic [1:0] i, j, k;

// loop through the counters for convolution
always_ff @(posedge clk) begin
	if (k == 3) begin
		k <= '0;
		clr_n <= 
		if (j == 3) begin
			j <= '0;
			if (i == 3) begin
				i <= '0;
			end else begin
				i <= i + '1;
			end
		end else begin
			j <= j + '1;
		end
	end else begin
		k <= k + '1;
	end
end

// find Gx (Gx = SOBEL_X * A)
always_comb begin
	for (int h = 0, h < num_PE, h++) begin
		PE_in1[h] = line_memory[k][j];
		PE_in2[h] = SOBEL_X[k][j];
		pixel_output_X = PE_out[h];
		clr_n[h] = (k == '0);
	end
end

// find Gy
always_comb begin
	for (int h = 1, h < num_PE, h++) begin
		PE_in1[h] = line_memory[k][j];
		PE_in2[h] = SOBEL_Y[k][j];
		pixel_output_Y = PE_out[h];
		clr_n[h] = (k == '0);
	end
end

// find G (use approx bc sqrt and squaring is expensive)
// if MSB = 0, the absolute value number is itself
// if MSB = 1, the absolute value is the two's complement (invert all bits + 1)

logic [7:0] abs_Gx, abs_Gy, G_out;

always_comb begin
	if (pixel_output_X[7] == 0) begin
		abs_Gx = pixel_output_X;
	end else begin
		abs_Gx = ~pixel_output_X + '1;
	end
	if (pixel_output_Y[7] == 0) begin
	abs_Gy = pixel_output_Y;
	end else begin
		abs_Gy = ~pixel_output_Y + '1;
	end
	G_out = abs_Gx + abs_Gy;
end

assign pixel_output = G_out;

endmodule

// module to find which neighboring pixel to check

module angle (
	input logic [7:0] Gx, Gy,
	output logic [1:0] Dir
);

logic [1:0] Dir_int;

typedef enum logic [1:0] {
	DIR_0, DIR_45, DIR_90, DIR_135
} edge_dir_t;

edge_dir_t Dir_int;

// use absolute value for solving angles
logic [7:0] abs_gx, abs_gy;
assign abs_gx = (Gx[7]) ? -Gx : Gx;
assign abs_gy = (Gy[7]) ? -Gy : Gy;

always_comb begin
	// check 90 dergree case
	if (abs_gx == 0' || abs_gy > (abs_gx << 1) + (abs_gx >> 1))) begin
		Dir_int = DIR_90;
	end
	// check 0 degree case
	else if (abs_gy < (abs_gx >> 1)) begin
		Dir_int = DIR_0;
	end else begin //check diagonal case
		if (Gx[7] ^ Gy[7]) begin
			Dir_int = DIR_135;
		end else begin
			Dir_int = DIR_45;
		end
	end
end

assign Dir = Dir_int;

endmodule