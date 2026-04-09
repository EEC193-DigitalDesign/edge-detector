// hysteresis.v
// Double-thresholding and local 3x3 edge tracking for Canny Edge Detection.
// 640x480 @ 25 MHz pixel clock

module hyster (
    input  wire       clk,          // 25 MHz VGA/pixel clock
    input  wire       rst_n,        // Active-low reset
    input  wire       de,           // Data enable (active region)
    input  wire [7:0] mag_in,       // 8-bit gradient magnitude input
    input  wire [7:0] high_thresh,  // Upper threshold for strong edges
    input  wire [7:0] low_thresh,   // Lower threshold for weak edges

    output reg        de_out,       // Data enable out (aligned with center pixel)
    output reg  [7:0] edge_out      // Final binary edge (0 or 255)
);

    // ---------------------------------------------------------------
    // 1. Horizontal pixel counter
    // ---------------------------------------------------------------
    reg [9:0] h_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    h_cnt <= 0;
        else if (!de)  h_cnt <= 0;
        else           h_cnt <= h_cnt + 1;
    end

    // ---------------------------------------------------------------
    // 2. Line Buffers (Storage for 2 previous rows)
    // ---------------------------------------------------------------
    reg [7:0] line_buf0 [0:639];
    reg [7:0] line_buf1 [0:639];

    wire [7:0] lb0_data = line_buf0[h_cnt];
    wire [7:0] lb1_data = line_buf1[h_cnt];

    always @(posedge clk) begin
        if (de) begin
            line_buf0[h_cnt] <= mag_in;
            line_buf1[h_cnt] <= lb0_data;
        end
    end

    // ---------------------------------------------------------------
    // 3. 3x3 Window Shift Registers
    // ---------------------------------------------------------------
    // p0x = Oldest row (Top)
    // p1x = Middle row (Center)
    // p2x = Newest row (Bottom)
    
    reg [7:0] p00, p01, p02; 
    reg [7:0] p10, p11, p12; 
    reg [7:0] p20, p21, p22;

    reg de_shift; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_shift <= 1'b0;
            {p00, p01, p02} <= 24'd0;
            {p10, p11, p12} <= 24'd0;
            {p20, p21, p22} <= 24'd0;
        end else begin
            de_shift <= de;
            if (de) begin
                p02 <= p01; p01 <= p00; p00 <= lb1_data;
                p12 <= p11; p11 <= p10; p10 <= lb0_data;
                p22 <= p21; p21 <= p20; p20 <= mag_in;
            end
        end
    end

    // ---------------------------------------------------------------
    // 4. Hysteresis Thresholding Logic (Combinational)
    // ---------------------------------------------------------------
    
    // Evaluate the center pixel
    wire is_strong = (p11 >= high_thresh);
    wire is_weak   = (p11 >= low_thresh) && (p11 < high_thresh);

    // Check if ANY of the 8 neighbors are strong
    wire neighbor_strong = (p00 >= high_thresh) | (p01 >= high_thresh) | (p02 >= high_thresh) |
                           (p10 >= high_thresh) |                        (p12 >= high_thresh) |
                           (p20 >= high_thresh) | (p21 >= high_thresh) | (p22 >= high_thresh);

    // A pixel survives if it is already strong, OR if it's weak but touching a strong pixel
    wire final_pixel = is_strong | (is_weak & neighbor_strong);

    // ---------------------------------------------------------------
    // 5. Output Register
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_out <= 8'd0;
            de_out   <= 1'b0;
        end else begin
            edge_out <= final_pixel ? 8'd255 : 8'd0;
            de_out <= de_shift; // Align DE with the center pixel (p11)
        end
    end

endmodule