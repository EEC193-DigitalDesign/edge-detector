// sobel_edge_detector.v
// Real-time Sobel edge detection for DE1-SoC FPGA video pipeline
// 640x480 @ 25 MHz pixel clock
// Converts RGB to grayscale, builds a 3x3 window via line buffers
// and shift registers, then computes |Gx| + |Gy| gradient magnitude.

module sobel_edge_detector (
  input        clk,        // VGA/pixel clock (25 MHz)
  input        rst_n,      // Active-low reset
  input  [7:0] r_in,       // 8-bit Red from Bayer-to-RGB
  input  [7:0] g_in,       // 8-bit Green
  input  [7:0] b_in,       // 8-bit Blue
  input        de,          // Data enable (HIGH during 640 active pixels)
  output [7:0] edge_out     // Gradient magnitude (0=no edge, 255=strong)
);

  // ---------------------------------------------------------------
  // 1. RGB to Grayscale (BT.601 luma, combinational)
  // ---------------------------------------------------------------
  wire [15:0] gray_sum = r_in * 8'd77 + g_in * 8'd150 + b_in * 8'd29;
  wire  [7:0] gray     = gray_sum[15:8];

  // ---------------------------------------------------------------
  // 2. Horizontal pixel counter (0-639 during active region)
  // ---------------------------------------------------------------
  reg [9:0] h_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)    h_cnt <= 0;
    else if (!de)  h_cnt <= 0;
    else           h_cnt <= h_cnt + 1;
  end

  // ---------------------------------------------------------------
  // 3. Two line-delay buffers (distributed RAM)
  //    Combinational read, registered write.
  // ---------------------------------------------------------------
  reg [7:0] line_buf0 [0:639]; // Previous line
  reg [7:0] line_buf1 [0:639]; // 2 lines ago

  wire [7:0] line0_data = line_buf0[h_cnt]; // Combinational read
  wire [7:0] line1_data = line_buf1[h_cnt]; // Combinational read

  always @(posedge clk) begin
    if (de) begin
      line_buf0[h_cnt] <= gray;       // Store current grayscale
      line_buf1[h_cnt] <= line0_data; // Cascade previous line down
    end
  end

  // ---------------------------------------------------------------
  // 4. Three 3-tap shift registers (builds 3x3 window)
  // ---------------------------------------------------------------
  reg [7:0] sr0_0, sr0_1, sr0_2; // Current line  (newest)
  reg [7:0] sr1_0, sr1_1, sr1_2; // Previous line
  reg [7:0] sr2_0, sr2_1, sr2_2; // 2 lines ago   (oldest)

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      {sr0_0, sr0_1, sr0_2} <= 24'd0;
      {sr1_0, sr1_1, sr1_2} <= 24'd0;
      {sr2_0, sr2_1, sr2_2} <= 24'd0;
    end else if (de) begin
      sr0_2 <= sr0_1; sr0_1 <= sr0_0; sr0_0 <= gray;
      sr1_2 <= sr1_1; sr1_1 <= sr1_0; sr1_0 <= line0_data;
      sr2_2 <= sr2_1; sr2_1 <= sr2_0; sr2_0 <= line1_data;
    end
  end

  // ---------------------------------------------------------------
  // 5. Sobel kernels (combinational)
  //    Window mapping (after shift registers settle):
  //      sr2_2  sr2_1  sr2_0   =  p00  p01  p02  (top / oldest)
  //      sr1_2  sr1_1  sr1_0   =  p10  p11  p12  (middle)
  //      sr0_2  sr0_1  sr0_0   =  p20  p21  p22  (bottom / newest)
  // ---------------------------------------------------------------
  wire signed [10:0] p00 = {3'b0, sr2_2};
  wire signed [10:0] p01 = {3'b0, sr2_1};
  wire signed [10:0] p02 = {3'b0, sr2_0};
  wire signed [10:0] p10 = {3'b0, sr1_2};
  // p11 not used in Sobel
  wire signed [10:0] p12 = {3'b0, sr1_0};
  wire signed [10:0] p20 = {3'b0, sr0_2};
  wire signed [10:0] p21 = {3'b0, sr0_1};
  wire signed [10:0] p22 = {3'b0, sr0_0};

  // Gx = [-1 0 1; -2 0 2; -1 0 1]
  wire signed [10:0] gx = (p02 - p00) + ((p12 - p10) <<< 1) + (p22 - p20);

  // Gy = [-1 -2 -1; 0 0 0; 1 2 1]
  wire signed [10:0] gy = (p20 - p00) + ((p21 - p01) <<< 1) + (p22 - p02);

  // ---------------------------------------------------------------
  // 6. Gradient magnitude: |Gx| + |Gy|  (range 0-2040)
  // ---------------------------------------------------------------
  wire [10:0] abs_gx    = gx[10] ? (~gx + 1'b1) : gx;
  wire [10:0] abs_gy    = gy[10] ? (~gy + 1'b1) : gy;
  wire [10:0] magnitude = abs_gx + abs_gy;

  // ---------------------------------------------------------------
  // 7. Clamp to 8 bits
  // ---------------------------------------------------------------
  assign edge_out = (magnitude > 11'd255) ? 8'd255 : magnitude[7:0];

endmodule
