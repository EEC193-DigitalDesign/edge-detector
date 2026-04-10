//=======================================================
//  edge_detect_tracker.v
//  Lightweight horizontal-gradient edge detector with
//  per-quadrant pixel counting for checkerboard detection
//=======================================================
module edge_detect_tracker #(
    parameter H_CENTER = 16'd481,   // center H_Cont (161 + 320)
    parameter V_CENTER = 16'd286    // center V_Cont (46 + 240)
)(
    input              clk,
    input              rst_n,
    input              de,          // READ_Request (active during valid pixels)
    input      [7:0]   r_in,
    input      [7:0]   g_in,
    input      [7:0]   b_in,
    input      [15:0]  h_count,     // H_Cont from VGA timing
    input      [15:0]  v_count,     // V_Cont from VGA timing
    input              vs,          // VGA_VS (active-low sync pulse)
    input      [7:0]   detect_thresh, // gradient magnitude threshold
    input      [15:0]  min_count,     // minimum edge count to declare detection

    output reg         object_detected,
    output reg [1:0]   quadrant,      // 00=TL, 01=TR, 10=BL, 11=BR
    output reg [19:0]  count_tl,      // latched per-frame counts (debug)
    output reg [19:0]  count_tr,
    output reg [19:0]  count_bl,
    output reg [19:0]  count_br
);

    // ---- grayscale: 0.25R + 0.5G + 0.25B ----
    wire [8:0] gray_w = {1'b0, r_in[7:2]} + {1'b0, g_in[7:1]} + {1'b0, b_in[7:2]};
    wire [7:0] gray   = gray_w[8] ? 8'hFF : gray_w[7:0];

    // ---- 1-pixel delay for horizontal gradient ----
    reg [7:0] gray_prev;
    reg       de_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_prev <= 8'd0;
            de_prev   <= 1'b0;
        end else begin
            gray_prev <= gray;
            de_prev   <= de;
        end
    end

    // ---- absolute horizontal gradient ----
    wire [7:0] abs_diff = (gray >= gray_prev) ? (gray - gray_prev)
                                               : (gray_prev - gray);

    // ---- edge pixel detection ----
    wire is_edge = de & de_prev & (abs_diff >= detect_thresh);

    // ---- quadrant classification ----
    wire is_left = (h_count < H_CENTER);
    wire is_top  = (v_count < V_CENTER);

    // ---- running accumulators (cleared each frame) ----
    reg [19:0] run_tl, run_tr, run_bl, run_br;

    // ---- VS rising-edge detector (VS is active-low) ----
    reg vs_d1, vs_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin vs_d1 <= 1'b1; vs_d2 <= 1'b1; end
        else        begin vs_d1 <= vs;    vs_d2 <= vs_d1; end
    end
    wire frame_end = vs_d1 & ~vs_d2;   // rising edge = new frame start

    // ---- combinational max finder ----
    wire [19:0] max_tl_tr = (run_tl >= run_tr) ? run_tl : run_tr;
    wire [19:0] max_bl_br = (run_bl >= run_br) ? run_bl : run_br;
    wire [19:0] max_val   = (max_tl_tr >= max_bl_br) ? max_tl_tr : max_bl_br;

    wire [1:0] max_quad = (max_val == run_tl) ? 2'b00 :
                          (max_val == run_tr) ? 2'b01 :
                          (max_val == run_bl) ? 2'b10 : 2'b11;

    // ---- main sequential logic ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run_tl <= 20'd0;  run_tr <= 20'd0;
            run_bl <= 20'd0;  run_br <= 20'd0;
            count_tl <= 20'd0; count_tr <= 20'd0;
            count_bl <= 20'd0; count_br <= 20'd0;
            object_detected <= 1'b0;
            quadrant <= 2'b00;
        end else if (frame_end) begin
            // latch results for display / downstream
            count_tl <= run_tl;
            count_tr <= run_tr;
            count_bl <= run_bl;
            count_br <= run_br;

            // detection decision
            if (max_val >= {4'd0, min_count})  begin
                object_detected <= 1'b1;
                quadrant        <= max_quad;
            end else begin
                object_detected <= 1'b0;
            end

            // reset for next frame
            run_tl <= 20'd0;  run_tr <= 20'd0;
            run_bl <= 20'd0;  run_br <= 20'd0;
        end else if (is_edge) begin
            if      ( is_top &  is_left) run_tl <= run_tl + 20'd1;
            else if ( is_top & ~is_left) run_tr <= run_tr + 20'd1;
            else if (~is_top &  is_left) run_bl <= run_bl + 20'd1;
            else                         run_br <= run_br + 20'd1;
        end
    end

endmodule
