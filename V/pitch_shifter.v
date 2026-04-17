//=======================================================
//  pitch_shifter.v
//  Granular dual-pointer pitch shifter with triangular
//  crossfade window. Circular buffer in M10K block RAM.
//  Uses pipelined RAM access (7 MCLK cycles per sample).
//=======================================================
module pitch_shifter (
    input              clk,
    input              rst_n,
    input              sample_tick,
    input      [15:0]  ratio,        // 2.14 unsigned fixed-point (16384 = 1.0x)
    input              bypass,       // 1 = passthrough
    input      [15:0]  audio_in,     // mono signed 16-bit
    output reg [15:0]  audio_out     // mono signed 16-bit
);

    // ---- Parameters ----
    localparam BUF_BITS   = 11;                      // 2048-sample circular buffer
    localparam BUF_SIZE   = (1 << BUF_BITS);         // 2048
    localparam GRAIN_SIZE = 1024;                     // ~21ms at 48kHz
    localparam HALF_GRAIN = GRAIN_SIZE / 2;           // 512
    localparam FP_BITS    = 14;
    localparam PTR_WIDTH  = BUF_BITS + FP_BITS;      // 25

    // ============================================================
    // M10K RAM — simple dual-port (1 read + 1 write)
    // ============================================================
    (* ramstyle = "M10K" *) reg [15:0] buf_mem [0:BUF_SIZE-1];

    // Read port
    reg  [BUF_BITS-1:0] ram_rd_addr;
    reg  [15:0]         ram_rd_data;

    always @(posedge clk) begin
        ram_rd_data <= buf_mem[ram_rd_addr];
    end

    // Write port
    reg                  ram_wr_en;
    reg  [BUF_BITS-1:0] ram_wr_addr;
    reg  [15:0]          ram_wr_data;

    always @(posedge clk) begin
        if (ram_wr_en)
            buf_mem[ram_wr_addr] <= ram_wr_data;
    end

    // ============================================================
    // Pointers and grain state
    // ============================================================
    reg [BUF_BITS-1:0]  write_ptr;
    reg [PTR_WIDTH-1:0] read_ptr_a;
    reg [PTR_WIDTH-1:0] read_ptr_b;
    reg [10:0]          grain_pos_a;  // 0..1023
    reg [10:0]          grain_pos_b;  // 0..1023

    // Address computation (combinational, stable during pipeline)
    wire [BUF_BITS-1:0] addr_a0 = read_ptr_a[PTR_WIDTH-1:FP_BITS];
    wire [BUF_BITS-1:0] addr_a1 = addr_a0 + {{(BUF_BITS-1){1'b0}}, 1'b1};
    wire [BUF_BITS-1:0] addr_b0 = read_ptr_b[PTR_WIDTH-1:FP_BITS];
    wire [BUF_BITS-1:0] addr_b1 = addr_b0 + {{(BUF_BITS-1){1'b0}}, 1'b1};

    // Fractional parts for interpolation
    wire [FP_BITS-1:0] frac_a = read_ptr_a[FP_BITS-1:0];
    wire [FP_BITS-1:0] frac_b = read_ptr_b[FP_BITS-1:0];

    // ============================================================
    // Captured samples from RAM reads
    // ============================================================
    reg signed [15:0] samp_a0, samp_a1, samp_b0, samp_b1;

    // ---- Linear interpolation (combinational on captured samples) ----
    wire signed [15:0] diff_a = samp_a1 - samp_a0;
    wire signed [29:0] interp_a_prod = diff_a * $signed({1'b0, frac_a});
    wire signed [15:0] sample_a = samp_a0 + interp_a_prod[29:14];

    wire signed [15:0] diff_b = samp_b1 - samp_b0;
    wire signed [29:0] interp_b_prod = diff_b * $signed({1'b0, frac_b});
    wire signed [15:0] sample_b = samp_b0 + interp_b_prod[29:14];

    // ---- Triangular crossfade windows ----
    reg [9:0] window_a, window_b;

    always @(*) begin
        if (grain_pos_a < HALF_GRAIN)
            window_a = grain_pos_a[9:0];
        else
            window_a = GRAIN_SIZE[10:1] - grain_pos_a[9:0] - 10'd1;

        if (grain_pos_b < HALF_GRAIN)
            window_b = grain_pos_b[9:0];
        else
            window_b = GRAIN_SIZE[10:1] - grain_pos_b[9:0] - 10'd1;
    end

    // ---- Crossfade output ----
    wire signed [25:0] weighted_a = sample_a * $signed({1'b0, window_a});
    wire signed [25:0] weighted_b = sample_b * $signed({1'b0, window_b});
    wire signed [26:0] mixed = {weighted_a[25], weighted_a} + {weighted_b[25], weighted_b};
    wire signed [15:0] shifted_out = mixed[24:9];

    // ============================================================
    // Pipeline state machine
    //   S_IDLE:    wait for sample_tick, set addr=a0, write input
    //   S_PIPE1:   set addr=a1 (a0 data propagating through RAM)
    //   S_CAP_A0:  capture samp_a0 from RAM, set addr=b0
    //   S_CAP_A1:  capture samp_a1 from RAM, set addr=b1
    //   S_CAP_B0:  capture samp_b0 from RAM
    //   S_CAP_B1:  capture samp_b1 from RAM
    //   S_COMPUTE: all samples valid, compute output, update ptrs
    // ============================================================
    localparam [2:0] S_IDLE    = 3'd0,
                     S_PIPE1   = 3'd1,
                     S_CAP_A0  = 3'd2,
                     S_CAP_A1  = 3'd3,
                     S_CAP_B0  = 3'd4,
                     S_CAP_B1  = 3'd5,
                     S_COMPUTE = 3'd6;

    reg [2:0]  state;
    reg [15:0] audio_in_lat;
    reg [15:0] ratio_lat;
    reg        bypass_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            write_ptr    <= {BUF_BITS{1'b0}};
            read_ptr_a   <= {PTR_WIDTH{1'b0}};
            read_ptr_b   <= {{(PTR_WIDTH-FP_BITS-11){1'b0}}, HALF_GRAIN[10:0], {FP_BITS{1'b0}}};
            grain_pos_a  <= 11'd0;
            grain_pos_b  <= HALF_GRAIN[10:0];
            audio_out    <= 16'd0;
            ram_rd_addr  <= {BUF_BITS{1'b0}};
            ram_wr_en    <= 1'b0;
            ram_wr_addr  <= {BUF_BITS{1'b0}};
            ram_wr_data  <= 16'd0;
            samp_a0      <= 16'sd0;
            samp_a1      <= 16'sd0;
            samp_b0      <= 16'sd0;
            samp_b1      <= 16'sd0;
            audio_in_lat <= 16'd0;
            ratio_lat    <= 16'd16384;
            bypass_lat   <= 1'b1;
        end else begin
            ram_wr_en <= 1'b0;  // default: no write

            case (state)
                S_IDLE: begin
                    if (sample_tick) begin
                        // Latch inputs
                        audio_in_lat <= audio_in;
                        ratio_lat    <= ratio;
                        bypass_lat   <= bypass;
                        // Write input to circular buffer
                        ram_wr_en    <= 1'b1;
                        ram_wr_addr  <= write_ptr;
                        ram_wr_data  <= audio_in;
                        // Start RAM read pipeline: address a0
                        ram_rd_addr  <= addr_a0;
                        state        <= S_PIPE1;
                    end
                end

                S_PIPE1: begin
                    // a0 data propagating through RAM registered read
                    ram_rd_addr <= addr_a1;
                    state       <= S_CAP_A0;
                end

                S_CAP_A0: begin
                    samp_a0     <= ram_rd_data;  // buf_mem[addr_a0]
                    ram_rd_addr <= addr_b0;
                    state       <= S_CAP_A1;
                end

                S_CAP_A1: begin
                    samp_a1     <= ram_rd_data;  // buf_mem[addr_a1]
                    ram_rd_addr <= addr_b1;
                    state       <= S_CAP_B0;
                end

                S_CAP_B0: begin
                    samp_b0 <= ram_rd_data;      // buf_mem[addr_b0]
                    state   <= S_CAP_B1;
                end

                S_CAP_B1: begin
                    samp_b1 <= ram_rd_data;      // buf_mem[addr_b1]
                    state   <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    // All 4 samples captured, combinational output is valid
                    write_ptr <= write_ptr + {{(BUF_BITS-1){1'b0}}, 1'b1};

                    if (bypass_lat) begin
                        audio_out   <= audio_in_lat;
                        // Reset read pointers to track write pointer
                        read_ptr_a  <= {write_ptr, {FP_BITS{1'b0}}};
                        read_ptr_b  <= {write_ptr - HALF_GRAIN[BUF_BITS-1:0], {FP_BITS{1'b0}}};
                        grain_pos_a <= 11'd0;
                        grain_pos_b <= HALF_GRAIN[10:0];
                    end else begin
                        audio_out <= shifted_out;

                        // Advance read pointers by ratio
                        if (grain_pos_a == GRAIN_SIZE - 1) begin
                            grain_pos_a <= 11'd0;
                            read_ptr_a  <= {write_ptr, {FP_BITS{1'b0}}};
                        end else begin
                            grain_pos_a <= grain_pos_a + 11'd1;
                            read_ptr_a  <= read_ptr_a + {{(PTR_WIDTH-16){1'b0}}, ratio_lat};
                        end

                        if (grain_pos_b == GRAIN_SIZE - 1) begin
                            grain_pos_b <= 11'd0;
                            read_ptr_b  <= {write_ptr, {FP_BITS{1'b0}}};
                        end else begin
                            grain_pos_b <= grain_pos_b + 11'd1;
                            read_ptr_b  <= read_ptr_b + {{(PTR_WIDTH-16){1'b0}}, ratio_lat};
                        end
                    end

                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
