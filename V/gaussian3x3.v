//=======================================================
//  gaussian3x3.v
//=======================================================
module gaussian3x3 #(
    parameter IMAGE_WIDTH = 640
)(
    input            clk,
    input            rst_n,
    input            de,
    input      [7:0] pix_in,
    output reg [7:0] pix_out,
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

    reg [11:0] sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_out   <= 8'd0;
            pix_valid <= 1'b0;
            sum       <= 12'd0;
        end else begin
            sum <=
                {4'd0, w00} + ({4'd0, w01} << 1) + {4'd0, w02} +
               ({4'd0, w10} << 1) + ({4'd0, w11} << 2) + ({4'd0, w12} << 1) +
                {4'd0, w20} + ({4'd0, w21} << 1) + {4'd0, w22};

            pix_out   <= sum[11:4]; // divide by 16
            pix_valid <= win_valid;
        end
    end

endmodule
