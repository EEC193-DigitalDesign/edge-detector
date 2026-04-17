//=======================================================
//  echo_delay.v
//  Feedback delay line: 250ms delay, 50% feedback
//  16384 x 16-bit circular buffer in M10K block RAM
//  Uses pipelined RAM access for proper M10K inference
//=======================================================
module echo_delay (
    input              clk,
    input              rst_n,
    input              sample_tick,
    input              bypass,
    input      [15:0]  audio_in,     // mono signed 16-bit
    output reg [15:0]  audio_out     // mono signed 16-bit
);

    // ---- Parameters ----
    localparam BUF_BITS    = 14;                    // 16384-sample buffer
    localparam BUF_SIZE    = (1 << BUF_BITS);       // 16384
    localparam DELAY_LEN   = 14'd12000;             // 250ms at 48kHz

    // ============================================================
    // M10K RAM — simple dual-port (1 read + 1 write)
    // Separate always blocks for guaranteed inference
    // ============================================================
    (* ramstyle = "M10K" *) reg [15:0] delay_buf [0:BUF_SIZE-1];

    // Read port signals
    reg  [BUF_BITS-1:0] ram_rd_addr;
    reg  [15:0]         ram_rd_data;

    // Registered read — M10K inference pattern
    always @(posedge clk) begin
        ram_rd_data <= delay_buf[ram_rd_addr];
    end

    // Write port signals
    reg                  ram_wr_en;
    reg  [BUF_BITS-1:0] ram_wr_addr;
    reg  [15:0]          ram_wr_data;

    // Registered write — M10K inference pattern
    always @(posedge clk) begin
        if (ram_wr_en)
            delay_buf[ram_wr_addr] <= ram_wr_data;
    end

    // ============================================================
    // Pipeline state machine
    // Cycle 0 (S_IDLE+tick): set read address, latch inputs
    // Cycle 1 (S_WAIT):      RAM read latency
    // Cycle 2 (S_PROCESS):   read data valid, compute, trigger write
    // ============================================================
    localparam [1:0] S_IDLE    = 2'd0,
                     S_WAIT    = 2'd1,
                     S_PROCESS = 2'd2;

    reg [1:0]          state;
    reg [BUF_BITS-1:0] write_ptr;
    reg [15:0]         audio_in_lat;
    reg                bypass_lat;

    // ---- Saturation arithmetic (combinational, uses ram_rd_data) ----
    wire signed [15:0] delayed     = ram_rd_data;
    wire signed [16:0] out_sum     = $signed(audio_in_lat) + $signed(delayed);
    wire signed [15:0] out_sat     = (out_sum > 17'sd32767)  ? 16'sd32767 :
                                     (out_sum < -17'sd32768) ? -16'sd32768 :
                                     out_sum[15:0];

    wire signed [15:0] delayed_half = $signed(delayed) >>> 1;
    wire signed [16:0] fb_sum      = $signed(audio_in_lat) + $signed(delayed_half);
    wire signed [15:0] fb_sat      = (fb_sum > 17'sd32767)  ? 16'sd32767 :
                                     (fb_sum < -17'sd32768) ? -16'sd32768 :
                                     fb_sum[15:0];

    // ---- State machine ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            write_ptr    <= {BUF_BITS{1'b0}};
            audio_out    <= 16'd0;
            ram_rd_addr  <= {BUF_BITS{1'b0}};
            ram_wr_en    <= 1'b0;
            ram_wr_addr  <= {BUF_BITS{1'b0}};
            ram_wr_data  <= 16'd0;
            audio_in_lat <= 16'd0;
            bypass_lat   <= 1'b0;
        end else begin
            ram_wr_en <= 1'b0;  // default: no write

            case (state)
                S_IDLE: begin
                    if (sample_tick) begin
                        audio_in_lat <= audio_in;
                        bypass_lat   <= bypass;
                        ram_rd_addr  <= write_ptr - DELAY_LEN;
                        state        <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    // RAM read data will be valid next cycle
                    state <= S_PROCESS;
                end

                S_PROCESS: begin
                    // ram_rd_data now has the delayed sample
                    if (bypass_lat) begin
                        audio_out   <= audio_in_lat;
                        ram_wr_data <= audio_in_lat;
                    end else begin
                        audio_out   <= out_sat;
                        ram_wr_data <= fb_sat;
                    end
                    ram_wr_en   <= 1'b1;
                    ram_wr_addr <= write_ptr;
                    write_ptr   <= write_ptr + {{(BUF_BITS-1){1'b0}}, 1'b1};
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
