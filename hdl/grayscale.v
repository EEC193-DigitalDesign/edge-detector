module grayscale (
  input        clk,        // VGA/pixel clock (25 MHz)
  input        rst_n,      // Active-low reset
  input  [7:0] r_in,       // 8-bit Red from Bayer-to-RGB
  input  [7:0] g_in,       // 8-bit Green
  input  [7:0] b_in,       // 8-bit Blue
  input        de,          // Data enable (HIGH during 640 active pixels)
  output [7:0] gray_out     // Grayscale output (0-255)
);

  // ---------------------------------------------------------------
  // RGB to Grayscale conversion using BT.601 luma formula:
  // Y = 0.299*R + 0.587*G + 0.114*B
  // We can approximate this with integer math:
  // Y = (R*77 + G*150 + B*29) >> 8
  // ---------------------------------------------------------------
  wire [15:0] gray_sum = r_in * 8'd77 + g_in * 8'd150 + b_in * 8'd29;
  assign gray_out = de ? gray_sum[15:8] : 8'b0; // Output grayscale only when DE is high
endmodule