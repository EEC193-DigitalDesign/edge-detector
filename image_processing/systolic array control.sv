// control and data alignment module for systolic array

// control module

module array_controller (
	input logic clk,
    input logic rst_n,
    input logic start,
    output logic pe_en,
    output logic pe_rst_n,
    output logic ready
);

typedef enum logic [1:0] {IDLE, COMPUTE, DONE} state_t;

state_t state;

logic [9:0] cycle_count // count up to 784 (2^10=1024)

always_ff @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state <= IDLE;
		cycle_count <= '0;
		pe_en <= 1'b0;
		pe_rst_n <= 1'b0;
		ready <= 1'b1;
	end else begin
		case (state) begin
			IDLE begin:
				if (start) begin
					pe_en_rst <= '1;
					pe_en <= '1;
					ready <= '0;
					state <= COMPUTE;
				end
			COMPUTE begin:
				if (cycle_count == 783) begin
					cycle_count <= '0;
					pe_en <= 0'
					state <= DONE;
				end else begin
					cycle_count <= cycle_count + '1;
				end
			DONE begin:
				ready <= '1;
				if (!start) state <= IDLE;
			end
		endcase
	end
end
endmodule

// data alignment module

module data_aligntment (
	input logic clk,
    input logic rst_n,
    input logic [7:0] pixel_raw  [27:0],
    input logic [3:0] filter_raw [27:0],
    output logic [7:0] pixel_skew [27:0],
    output logic [3:0] filter_skew[27:0]
);

// i = row, j = column

