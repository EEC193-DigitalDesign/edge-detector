//=======================================================
//  line_buffer_3x3.v
//  Simple streaming 3x3 window generator
//=======================================================
module line_buffer_3x3 #(
    parameter IMAGE_WIDTH = 640
)(
    input            clk,
    input            rst_n,
    input            de,
    input      [7:0] pix_in,
    output reg [7:0] w00, output reg [7:0] w01, output reg [7:0] w02,
    output reg [7:0] w10, output reg [7:0] w11, output reg [7:0] w12,
    output reg [7:0] w20, output reg [7:0] w21, output reg [7:0] w22,
    output reg       win_valid
);

    reg [7:0] line1 [0:IMAGE_WIDTH-1];
    reg [7:0] line2 [0:IMAGE_WIDTH-1];

    reg [10:0] col_cnt;
    reg [10:0] row_cnt;

    reg [7:0] p_line1;
    reg [7:0] p_line2;

    integer idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_cnt   <= 11'd0;
            row_cnt   <= 11'd0;
            p_line1   <= 8'd0;
            p_line2   <= 8'd0;
            w00 <= 8'd0; w01 <= 8'd0; w02 <= 8'd0;
            w10 <= 8'd0; w11 <= 8'd0; w12 <= 8'd0;
            w20 <= 8'd0; w21 <= 8'd0; w22 <= 8'd0;
            win_valid <= 1'b0;

            for (idx = 0; idx < IMAGE_WIDTH; idx = idx + 1) begin
                line1[idx] <= 8'd0;
                line2[idx] <= 8'd0;
            end
        end else begin
            if (de) begin
                p_line1 <= line1[col_cnt];
                p_line2 <= line2[col_cnt];

                line2[col_cnt] <= line1[col_cnt];
                line1[col_cnt] <= pix_in;

                // shift window left
                w00 <= w01; w01 <= w02; w02 <= p_line2;
                w10 <= w11; w11 <= w12; w12 <= p_line1;
                w20 <= w21; w21 <= w22; w22 <= pix_in;

                if (col_cnt == IMAGE_WIDTH-1) begin
                    col_cnt <= 11'd0;
                    row_cnt <= row_cnt + 11'd1;
                end else begin
                    col_cnt <= col_cnt + 11'd1;
                end

                win_valid <= (row_cnt >= 11'd2) && (col_cnt >= 11'd2);
            end else begin
                col_cnt   <= 11'd0;
                win_valid <= 1'b0;
                // do not reset row_cnt here; keeps stream stable across active lines
            end
        end
    end

endmodule
