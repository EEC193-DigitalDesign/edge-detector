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