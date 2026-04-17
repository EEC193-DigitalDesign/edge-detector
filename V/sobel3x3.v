//=======================================================
//  sobel3x3.v
//=======================================================
module sobel3x3 #(
    parameter IMAGE_WIDTH = 640
)(
    input            clk,
    input            rst_n,
    input            de,
    input      [7:0] pix_in,
    output reg [7:0] mag_out,
    output reg       pix_valid
);

    wire [7:0] w00, w01, w02;
    wire [7:0] w10, w11, w12;
    wire [7:0] w20, w21, w22;
    wire       win_valid;

    line_buffer_3x3 #(
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_lb (
        .clk       (clk),
        .rst_n     (rst_n),
        .de        (de),
        .pix_in    (pix_in),
        .w00       (w00), .w01(w01), .w02(w02),
        .w10       (w10), .w11(w11), .w12(w12),
        .w20       (w20), .w21(w21), .w22(w22),
        .win_valid (win_valid)
    );

    reg signed [11:0] gx, gy;
    reg [11:0] abs_gx, abs_gy, mag12;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx       <= 12'sd0;
            gy       <= 12'sd0;
            abs_gx   <= 12'd0;
            abs_gy   <= 12'd0;
            mag12    <= 12'd0;
            mag_out  <= 8'd0;
            pix_valid<= 1'b0;
        end else begin
            gx <= -$signed({1'b0,w00}) + $signed({1'b0,w02})
                  -($signed({1'b0,w10}) <<< 1) + ($signed({1'b0,w12}) <<< 1)
                  -$signed({1'b0,w20}) + $signed({1'b0,w22});

            gy <=  $signed({1'b0,w00}) + ($signed({1'b0,w01}) <<< 1) + $signed({1'b0,w02})
                  -$signed({1'b0,w20}) - ($signed({1'b0,w21}) <<< 1) - $signed({1'b0,w22});

            abs_gx <= gx[11] ? -gx : gx;
            abs_gy <= gy[11] ? -gy : gy;

            mag12 <= (abs_gx > abs_gy) ? abs_gx : abs_gy;

            if (mag12[11:8] != 4'd0)
                mag_out <= 8'hFF;
            else
                mag_out <= mag12[7:0];

            pix_valid <= win_valid;
        end
    end

endmodule
