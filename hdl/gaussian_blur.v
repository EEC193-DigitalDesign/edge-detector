module gaussian_blur (
    input        clk,      // 25 MHz pixel clock
    input        rst_n,    // Active-low reset
    input  [7:0] gray_in,  // Grayscale input from RGB-to-Gray
    input        de_in,       // Data enable (active region)

    output reg   de_out,
    output reg [7:0] gray_out  // Smoothed grayscale output
);

    // ---------------------------------------------------------------
    // 1. Horizontal pixel counter
    // ---------------------------------------------------------------
    reg [9:0] h_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    h_cnt <= 0;
        else if (!de_in)  h_cnt <= 0;
        else           h_cnt <= h_cnt + 1;
    end

    // ---------------------------------------------------------------
    // 2. Line Buffers (Storage for 4 previous rows for a 5x5 window)
    // ---------------------------------------------------------------
    reg [7:0] line_buf0 [0:639];
    reg [7:0] line_buf1 [0:639];
    reg [7:0] line_buf2 [0:639];
    reg [7:0] line_buf3 [0:639];

    wire [7:0] lb0_data = line_buf0[h_cnt];
    wire [7:0] lb1_data = line_buf1[h_cnt];
    wire [7:0] lb2_data = line_buf2[h_cnt];
    wire [7:0] lb3_data = line_buf3[h_cnt];

    always @(posedge clk) begin
        if (de_in) begin
            line_buf0[h_cnt] <= gray_in;
            line_buf1[h_cnt] <= lb0_data;
            line_buf2[h_cnt] <= lb1_data;
            line_buf3[h_cnt] <= lb2_data;
        end
    end

    // ---------------------------------------------------------------
    // 3. 5x5 Window Shift Registers
    // ---------------------------------------------------------------
    reg [7:0] g00, g01, g02, g03, g04; // Row 0 (Newest)
    reg [7:0] g10, g11, g12, g13, g14; // Row 1 
    reg [7:0] g20, g21, g22, g23, g24; // Row 2 (Center)
    reg [7:0] g30, g31, g32, g33, g34; // Row 3 
    reg [7:0] g40, g41, g42, g43, g44; // Row 4 (Oldest)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {g00, g01, g02, g03, g04} <= 40'd0;
            {g10, g11, g12, g13, g14} <= 40'd0;
            {g20, g21, g22, g23, g24} <= 40'd0;
            {g30, g31, g32, g33, g34} <= 40'd0;
            {g40, g41, g42, g43, g44} <= 40'd0;
        end else if (de_in) begin
            g04 <= g03; g03 <= g02; g02 <= g01; g01 <= g00; g00 <= gray_in;
            g14 <= g13; g13 <= g12; g12 <= g11; g11 <= g10; g10 <= lb0_data;
            g24 <= g23; g23 <= g22; g22 <= g21; g21 <= g20; g20 <= lb1_data;
            g34 <= g33; g33 <= g32; g32 <= g31; g31 <= g30; g30 <= lb2_data;
            g44 <= g43; g43 <= g42; g42 <= g41; g41 <= g40; g40 <= lb3_data;
        end
    end

    // ---------------------------------------------------------------
    // 4. Data Enable (DE) Synchronization Pipeline
    // ---------------------------------------------------------------
    // The center pixel (g22) is delayed by 2 clocks inside the shift 
    // register. We must delay de_in by 2 clocks to match it exactly.
    reg de_shift1, de_shift2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_shift1 <= 1'b0;
            de_shift2 <= 1'b0;
        end else begin
            // Unconditional shift so DE turns off during blanking
            de_shift1 <= de_in;
            de_shift2 <= de_shift1; 
        end
    end

    // ---------------------------------------------------------------
    // 4. Gaussian Kernel Math (Combinational)
    // ---------------------------------------------------------------
    // Quartus will easily synthesize constants like *6 and *24 into 
    // optimized shift-and-add logic behind the scenes.
    
    // Row 0: [1 4 6 4 1] -> Max 255 * 16 = 4080 (12 bits)
    wire [11:0] row0 = g00 + (g01 << 2) + (g02 * 6) + (g03 << 2) + g04;
    
    // Row 1: [4 16 24 16 4] -> Max 255 * 64 = 16320 (14 bits)
    wire [13:0] row1 = (g10 << 2) + (g11 << 4) + (g12 * 24) + (g13 << 4) + (g14 << 2);
    
    // Row 2: [6 24 36 24 6] -> Max 255 * 96 = 24480 (15 bits)
    wire [14:0] row2 = (g20 * 6) + (g21 * 24) + (g22 * 36) + (g23 * 24) + (g24 * 6);
    
    // Row 3: [4 16 24 16 4] -> Matches Row 1
    wire [13:0] row3 = (g30 << 2) + (g31 << 4) + (g32 * 24) + (g33 << 4) + (g34 << 2);
    
    // Row 4: [1 4 6 4 1] -> Matches Row 0
    wire [11:0] row4 = g40 + (g41 << 2) + (g42 * 6) + (g43 << 2) + g44;

    // Total Sum -> Max 255 * 256 = 65280 (16 bits)
    wire [15:0] total_sum = row0 + row1 + row2 + row3 + row4;

    // ---------------------------------------------------------------
    // 6. Output Registers (Adds 1 final clock cycle of latency)
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_out <= 8'd0;
            de_out   <= 1'b0;
        end else begin
            gray_out <= total_sum[15:8];
            
            // Pass the perfectly synced DE out to the next module
            de_out   <= de_shift2; 
        end
    end

endmodule