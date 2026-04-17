//=======================================================
//  edge_enhancer.v
//  Streaming grayscale + optional Gaussian + Sobel + threshold + overlay
//=======================================================
module edge_enhancer #(
    parameter IMAGE_WIDTH = 640
)(
    input              clk,
    input              rst_n,
    input              de,
    input      [7:0]   r_in,
    input      [7:0]   g_in,
    input      [7:0]   b_in,
    input              enable_blur,
    input              overlay_mode,
    input              invert_edges,
    input      [7:0]   threshold,
    output reg [7:0]   edge_gray,
    output reg [7:0]   edge_r,
    output reg [7:0]   edge_g,
    output reg [7:0]   edge_b,
    output reg         edge_valid
);

    // ----------------------------------------------------
    // Stage 0: grayscale
    // gray ≈ 0.25R + 0.5G + 0.25B
    // ----------------------------------------------------
    wire [8:0] gray_wide;
    wire [7:0] gray_in;
    assign gray_wide = {1'b0, (r_in >> 2)} + {1'b0, (g_in >> 1)} + {1'b0, (b_in >> 2)};
    assign gray_in   = gray_wide[8] ? 8'hFF : gray_wide[7:0];

    // keep original pixel aligned for overlay output
    reg [7:0] r_d0, g_d0, b_d0;
    reg       de_d0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_d0  <= 8'd0;
            g_d0  <= 8'd0;
            b_d0  <= 8'd0;
            de_d0 <= 1'b0;
        end else begin
            r_d0  <= r_in;
            g_d0  <= g_in;
            b_d0  <= b_in;
            de_d0 <= de;
        end
    end

    // ----------------------------------------------------
    // Stage 1: optional 3x3 Gaussian blur
    // kernel = [1 2 1; 2 4 2; 1 2 1] / 16
    // ----------------------------------------------------
    wire [7:0] blur_gray;
    wire       blur_valid;

    gaussian3x3 #(
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_gauss (
        .clk      (clk),
        .rst_n    (rst_n),
        .de       (de),
        .pix_in   (gray_in),
        .pix_out  (blur_gray),
        .pix_valid(blur_valid)
    );

    wire [7:0] sobel_in  = enable_blur ? blur_gray  : gray_in;
    wire       sobel_de  = enable_blur ? blur_valid : de;

    // ----------------------------------------------------
    // Stage 2: Sobel
    // mag = max(|gx|, |gy|)  (hardware-friendly)
    // ----------------------------------------------------
    wire [7:0] sobel_mag;
    wire       sobel_valid;

    sobel3x3 #(
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_sobel (
        .clk      (clk),
        .rst_n    (rst_n),
        .de       (sobel_de),
        .pix_in   (sobel_in),
        .mag_out  (sobel_mag),
        .pix_valid(sobel_valid)
    );

    // align original RGB for overlay path
    localparam ALIGN_DEPTH = (IMAGE_WIDTH * 2) + 16;
    reg [7:0] r_pipe [0:ALIGN_DEPTH-1];
    reg [7:0] g_pipe [0:ALIGN_DEPTH-1];
    reg [7:0] b_pipe [0:ALIGN_DEPTH-1];
    reg       de_pipe[0:ALIGN_DEPTH-1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ALIGN_DEPTH; i = i + 1) begin
                r_pipe[i]  <= 8'd0;
                g_pipe[i]  <= 8'd0;
                b_pipe[i]  <= 8'd0;
                de_pipe[i] <= 1'b0;
            end
        end else begin
            r_pipe[0]  <= r_in;
            g_pipe[0]  <= g_in;
            b_pipe[0]  <= b_in;
            de_pipe[0] <= de;

            for (i = 1; i < ALIGN_DEPTH; i = i + 1) begin
                r_pipe[i]  <= r_pipe[i-1];
                g_pipe[i]  <= g_pipe[i-1];
                b_pipe[i]  <= b_pipe[i-1];
                de_pipe[i] <= de_pipe[i-1];
            end
        end
    end

    wire [7:0] base_r = r_pipe[ALIGN_DEPTH-1];
    wire [7:0] base_g = g_pipe[ALIGN_DEPTH-1];
    wire [7:0] base_b = b_pipe[ALIGN_DEPTH-1];

    wire edge_hit = (sobel_mag >= threshold);
    wire [7:0] edge_pixel = invert_edges ? (edge_hit ? 8'hFF : 8'h00)
                                         : (edge_hit ? 8'h00 : 8'hFF);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_gray  <= 8'd0;
            edge_r     <= 8'd0;
            edge_g     <= 8'd0;
            edge_b     <= 8'd0;
            edge_valid <= 1'b0;
        end else begin
            edge_gray  <= edge_pixel;
            edge_valid <= sobel_valid;

            if (overlay_mode) begin
                if (edge_hit) begin
                    edge_r <= 8'hFF;
                    edge_g <= 8'hFF;
                    edge_b <= 8'hFF;
                end else begin
                    edge_r <= base_r;
                    edge_g <= base_g;
                    edge_b <= base_b;
                end
            end else begin
                edge_r <= edge_pixel;
                edge_g <= edge_pixel;
                edge_b <= edge_pixel;
            end
        end
    end

endmodule
