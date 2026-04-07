// edge_direction.v
// Calculates the gradient direction (0, 45, 90, or 135 degrees) for Canny Edge NMS.
// Uses an integer approximation (2 * |Gy| < |Gx|) to avoid arctan and division logic.

module edge_direction (
    input  wire               clk,           // 25 MHz VGA/Pixel clock
    input  wire               rst_n,         // Active-low reset
    input  wire               de_in,         // Data enable in
    input  wire signed [10:0] abs_gx,            // Signed X gradient from Sobel
    input  wire signed [10:0] abs_gy,            // Signed Y gradient from Sobel
    input  wire [7:0]         magnitude_in,  // 8-bit gradient magnitude from Sobel
    
    output reg                de_out,        // Data enable out (delayed 1 cycle)
    output reg  [7:0]         magnitude_out, // Magnitude out (delayed 1 cycle)
    output reg  [1:0]         dir_out        // Direction bin (00=0°, 01=45°, 10=90°, 11=135°)
);

    // ---------------------------------------------------------------
    // Direction Parameters for Readability
    // ---------------------------------------------------------------
    localparam DIR_0   = 2'b00; // Horizontal edge (Vertical gradient)
    localparam DIR_45  = 2'b01; // Positive diagonal edge
    localparam DIR_90  = 2'b10; // Vertical edge (Horizontal gradient)
    localparam DIR_135 = 2'b11; // Negative diagonal edge



    // ---------------------------------------------------------------
    // 2. Determine Direction Bin (Combinational)
    // ---------------------------------------------------------------
    reg [1:0] dir_comb;

    always @(*) begin
        // If 2*|Gy| < |Gx|, the gradient is mostly horizontal. 
        // This means the edge itself is Vertical (90 degrees).
        if ((abs_gy << 1) < abs_gx) begin
            dir_comb = DIR_90;
        end
        // If 2*|Gx| < |Gy|, the gradient is mostly vertical.
        // This means the edge itself is Horizontal (0 degrees).
        else if ((abs_gx << 1) < abs_gy) begin
            dir_comb = DIR_0;
        end
        // Otherwise, it's a diagonal edge.
        // If the signs of Gx and Gy match, it's a 135-degree edge.
        // If the signs are different, it's a 45-degree edge.
        else if (gx[10] == gy[10]) begin
            dir_comb = DIR_135;
        end
        else begin
            dir_comb = DIR_45;
        end
    end

    // ---------------------------------------------------------------
    // 3. Output Registers (1 Clock Cycle Latency)
    // Synchronizes the calculated direction with the magnitude and DE.
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_out       <= 2'b00;
            magnitude_out <= 8'd0;
            de_out        <= 1'b0;
        end else begin
            dir_out       <= dir_comb;
            magnitude_out <= magnitude_in;
            de_out        <= de_in;
        end
    end

endmodule