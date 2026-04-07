// nms.v
// Non-Maximum Suppression for Canny Edge Detection.
// Thins thick Sobel edges down to exactly 1 pixel wide.
// 640x480 @ 25 MHz pixel clock

module nms (
    input  wire       clk,        // 25 MHz VGA/pixel clock
    input  wire       rst_n,      // Active-low reset
    input  wire       de_in,      // Data enable in
    input  wire [7:0] mag_in,     // 8-bit magnitude from edge_direction
    input  wire [1:0] dir_in,     // 2-bit direction from edge_direction
    
    output reg        de_out,     // Data enable out (aligned with center pixel)
    output reg  [7:0] mag_out     // Thinned magnitude out
);

    // ---------------------------------------------------------------
    // 1. Data Packing (Magnitude + Direction + DE)
    // 11 bits total: [10] = de, [9:8] = dir, [7:0] = mag
    // ---------------------------------------------------------------
    wire [10:0] packed_in = {de_in, dir_in, mag_in};

    // ---------------------------------------------------------------
    // 2. Horizontal pixel counter
    // ---------------------------------------------------------------
    reg [9:0] h_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    h_cnt <= 0;
        else if (!de_in) h_cnt <= 0;
        else           h_cnt <= h_cnt + 1;
    end

    // ---------------------------------------------------------------
    // 3. Line Buffers (Storage for 2 previous rows)
    // ---------------------------------------------------------------
    reg [10:0] line_buf0 [0:639];
    reg [10:0] line_buf1 [0:639];

    wire [10:0] lb0_data = line_buf0[h_cnt];
    wire [10:0] lb1_data = line_buf1[h_cnt];

    always @(posedge clk) begin
        if (de_in) begin
            line_buf0[h_cnt] <= packed_in;
            line_buf1[h_cnt] <= lb0_data;
        end
    end

    // ---------------------------------------------------------------
    // 4. 3x3 Window Shift Registers
    // ---------------------------------------------------------------
    reg [10:0] sr0_0, sr0_1, sr0_2; // Newest row (Bottom)
    reg [10:0] sr1_0, sr1_1, sr1_2; // Middle row (Center)
    reg [10:0] sr2_0, sr2_1, sr2_2; // Oldest row (Top)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {sr0_0, sr0_1, sr0_2} <= 33'd0;
            {sr1_0, sr1_1, sr1_2} <= 33'd0;
            {sr2_0, sr2_1, sr2_2} <= 33'd0;
        end else if (de_in) begin
            sr0_2 <= sr0_1; sr0_1 <= sr0_0; sr0_0 <= packed_in;
            sr1_2 <= sr1_1; sr1_1 <= sr1_0; sr1_0 <= lb0_data;
            sr2_2 <= sr2_1; sr2_1 <= sr2_0; sr2_0 <= lb1_data;
        end
    end

    // ---------------------------------------------------------------
    // 5. Unpack 3x3 Magnitude Window & Center Data
    // ---------------------------------------------------------------
    // Top Row
    wire [7:0] p00 = sr2_2[7:0]; // Top-Left
    wire [7:0] p01 = sr2_1[7:0]; // Top-Center
    wire [7:0] p02 = sr2_0[7:0]; // Top-Right
    
    // Middle Row
    wire [7:0] p10 = sr1_2[7:0]; // Mid-Left
    wire [7:0] p11 = sr1_1[7:0]; // CENTER PIXEL MAGNITUDE
    wire [7:0] p12 = sr1_0[7:0]; // Mid-Right
    
    // Bottom Row
    wire [7:0] p20 = sr0_2[7:0]; // Bottom-Left
    wire [7:0] p21 = sr0_1[7:0]; // Bottom-Center
    wire [7:0] p22 = sr0_0[7:0]; // Bottom-Right

    // Center Pixel Meta-Data
    wire [1:0] dir11 = sr1_1[9:8]; // Center pixel direction
    wire       de11  = sr1_1[10];  // Center pixel Data Enable

    // ---------------------------------------------------------------
    // 6. Non-Maximum Suppression Logic (Combinational)
    // ---------------------------------------------------------------
    reg [7:0] suppressed_mag;

    always @(*) begin
        suppressed_mag = 8'd0; // Default to suppressed (black)
        
        case (dir11)
            // 0° Edge (Horizontal line) -> Compare top and bottom pixels
            2'b00: begin 
                if (p11 >= p01 && p11 >= p21) suppressed_mag = p11;
            end
            
            // 45° Edge -> Compare top-right and bottom-left pixels
            2'b01: begin 
                if (p11 >= p02 && p11 >= p20) suppressed_mag = p11;
            end
            
            // 90° Edge (Vertical line) -> Compare left and right pixels
            2'b10: begin 
                if (p11 >= p10 && p11 >= p12) suppressed_mag = p11;
            end
            
            // 135° Edge -> Compare top-left and bottom-right pixels
            2'b11: begin 
                if (p11 >= p00 && p11 >= p22) suppressed_mag = p11;
            end
        endcase
    end

    // ---------------------------------------------------------------
    // 7. Output Registers
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mag_out <= 8'd0;
            de_out  <= 1'b0;
        end else begin
            mag_out <= suppressed_mag;
            de_out  <= de11; // Passes the delayed DE so VGA doesn't desync
        end
    end

endmodule