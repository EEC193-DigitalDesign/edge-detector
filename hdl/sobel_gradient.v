// sobel_gradient.v
// Combined Sobel magnitude and edge direction calculator.
// 640x480 @ 25 MHz pixel clock

module sobel_gradient (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] gray_in,
    input  wire       de_in,
    input  wire [7:0] threshold,
    
    output reg        de_out,   // Aligned Data Enable
    output reg  [7:0] mag_out,  // 8-bit Gradient Magnitude
    output reg  [1:0] dir_out   // 2-bit Direction (00=0°, 01=45°, 10=90°, 11=135°)
);

    // ---------------------------------------------------------------
    // 1. Line Buffers & 3x3 Window Shift Registers
    // ---------------------------------------------------------------
    reg [9:0] h_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    h_cnt <= 0;
        else if (!de_in) h_cnt <= 0;
        else           h_cnt <= h_cnt + 1;
    end

    reg [7:0] line_buf0 [0:639];
    reg [7:0] line_buf1 [0:639];
    wire [7:0] lb0_data = line_buf0[h_cnt];
    wire [7:0] lb1_data = line_buf1[h_cnt];

    always @(posedge clk) begin
        if (de_in) begin
            line_buf0[h_cnt] <= gray_in;
            line_buf1[h_cnt] <= lb0_data;
        end
    end

    reg [7:0] sr0_0, sr0_1, sr0_2;
    reg [7:0] sr1_0, sr1_1, sr1_2;
    reg [7:0] sr2_0, sr2_1, sr2_2;

    reg de_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_shift <= 0;
            {sr0_0, sr0_1, sr0_2} <= 24'd0;
            {sr1_0, sr1_1, sr1_2} <= 24'd0;
            {sr2_0, sr2_1, sr2_2} <= 24'd0;
        end else begin
            de_shift <= de_in;
            if (de_in) begin
                sr0_2 <= sr0_1; sr0_1 <= sr0_0; sr0_0 <= gray_in;
                sr1_2 <= sr1_1; sr1_1 <= sr1_0; sr1_0 <= lb0_data;
                sr2_2 <= sr2_1; sr2_1 <= sr2_0; sr2_0 <= lb1_data;
            end
        end
    end

    // ---------------------------------------------------------------
    // 2. Sobel Math (Combinational)
    // ---------------------------------------------------------------
    wire signed [10:0] p00 = {3'b0, sr2_2}; wire signed [10:0] p01 = {3'b0, sr2_1}; wire signed [10:0] p02 = {3'b0, sr2_0};
    wire signed [10:0] p10 = {3'b0, sr1_2};                                         wire signed [10:0] p12 = {3'b0, sr1_0};
    wire signed [10:0] p20 = {3'b0, sr0_2}; wire signed [10:0] p21 = {3'b0, sr0_1}; wire signed [10:0] p22 = {3'b0, sr0_0};

    wire signed [10:0] gx = (p02 - p00) + ((p12 - p10) <<< 1) + (p22 - p20);
    wire signed [10:0] gy = (p20 - p00) + ((p21 - p01) <<< 1) + (p22 - p02);

    wire [10:0] abs_gx    = gx[10] ? (~gx + 1'b1) : gx;
    wire [10:0] abs_gy    = gy[10] ? (~gy + 1'b1) : gy;
    wire [10:0] magnitude = abs_gx + abs_gy;

    // ---------------------------------------------------------------
    // 3. Direction Math (Combinational)
    // ---------------------------------------------------------------
    reg [1:0] dir_comb;
    always @(*) begin
        if      ((abs_gy << 1) < abs_gx) dir_comb = 2'b10; // 90°
        else if ((abs_gx << 1) < abs_gy) dir_comb = 2'b00; // 0°
        else if (gx[10] == gy[10])       dir_comb = 2'b11; // 135°
        else                             dir_comb = 2'b01; // 45°
    end

    wire [7:0] clamped_mag = (magnitude > 11'd255) ? 8'd255 : magnitude[7:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mag_out <= 8'd0;
            dir_out <= 2'b00;
            de_out  <= 1'b0;
        end
        else begin
            mag_out = (clamped_mag < threshold) ? 8'd0 : clamped_mag;
            dir_out = dir_comb;
            de_out  <= de_shift; 
        end
    end
endmodule