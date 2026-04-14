// use the angle and the output of sobel for hysteresis thresholding

// remember to set threshold values
module hysteresis #(parameter int THRESHOLD_H = , parameter int THRESHOLD_L = ) (
	input logic clk,
	input logic [1:0] angle,
	input logic [7:0] sobel_in,
	output logic thresholding_out // figure out width of the output
);

typedef enum [1:0] {
	Strong, Weak, Discarded
} pixel_encoding;

pixel_encoding pixel_encoded;

logic [31:0] line_buffer_angle [639:0][2:0]; // create a line buffer to store values to check for connected pixels
logic [31:0] line_buffer_sobel [639:0][2:0];
logic [1:0] line_buffer_encoded [639:0];

always_ff @(posedge clk) begin
	if (sobel_in > THRESHOLD_H) begin
		pixel_encoded <= Strong;
	end else if (sobel_in < THRESHOLD_L) begin
		pixel_encoded <= Discarded;
	end else if ((sobel_in < THRESHOLD_H) && (angle == line_buffer_angle[match_i][match_j])) // figure out how to see if an intermediate pixel is connected to a strong/weak pixel
		pixel_encoded <= Weak;
	end
end

always_ff @(posedge clk) begin
	line_buffer_angle <= angle;
	line_buffer_sobel <= sobel_in;
	line_buffer_encoded <= pixel_encoded;
end

logic center;
logic match_found;
logic match_i;
logic match_j;

always_comb begin
	center = [k]line_buffer_angle[i][j];
	match_found = 0;
	if (sobel_in < THRESHOLD_H) begin
		// for loop to loop through the 3x3
		for (int k = 0, k < 640, k++) begin //loop through entire row
			for (int i = 0, i < 2, i++) begin //loop through cols
				for (int j = 0, j < 2, j++) begin //loop through rows
					if (line_buffer_angle == center) begin
						match_found = 1;
						match_i = i;
						match_j = j;
					end
				end
			end			
		end
	end
end

always_ff @(posedge clk) begin
	for (int h, h < 640, h++) begin
		if (pixel_encoded == (Strong or Weak)) begin
			thresholding_out <= 1';
		end else if (pixel_encoded == Discarded) begin
			thresholding_out <= 0';
		end
	end
end