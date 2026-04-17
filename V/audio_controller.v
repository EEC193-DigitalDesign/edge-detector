//=======================================================
//  audio_controller.v
//  Top-level audio wrapper: PLL + codec config + DDS + I2S
//  Bridges pixel-clock detection to audio-clock output
//=======================================================
module audio_controller (
    input        clk_50,           // 50 MHz system clock
    input        rst_n,
    // detection results (pixel-clock domain)
    input        object_detected,
    input  [1:0] quadrant,

    // WM8731 audio codec pins
    output       aud_xck,          // MCLK ~12.288 MHz
    output       aud_bclk,         // bit clock
    output       aud_daclrck,      // L/R channel clock
    output       aud_dacdat,       // serial DAC data

    // I2C to WM8731
    output       i2c_sclk,
    inout        i2c_sdat,

    // status
    output       audio_config_done
);

    // ---- Audio PLL: 50 MHz -> ~12.288 MHz ----
    wire aud_mclk;
    wire pll_locked;

    audio_pll u_pll (
        .refclk   (clk_50),
        .rst      (~rst_n),
        .outclk_0 (aud_mclk),
        .locked   (pll_locked)
    );

    assign aud_xck = aud_mclk;

    // ---- WM8731 I2C configuration (50 MHz domain) ----
    wire cfg_done;

    wm8731_config u_cfg (
        .clk         (clk_50),
        .rst_n       (rst_n & pll_locked),
        .i2c_sclk    (i2c_sclk),
        .i2c_sdat    (i2c_sdat),
        .config_done (cfg_done)
    );

    assign audio_config_done = cfg_done;

    // ---- clock domain crossing: pixel_clk -> aud_mclk ----
    reg [1:0] q_s1, q_s2;
    reg       d_s1, d_s2;

    always @(posedge aud_mclk or negedge rst_n) begin
        if (!rst_n) begin
            q_s1 <= 2'd0;  q_s2 <= 2'd0;
            d_s1 <= 1'b0;  d_s2 <= 1'b0;
        end else begin
            q_s1 <= quadrant;         q_s2 <= q_s1;
            d_s1 <= object_detected;  d_s2 <= d_s1;
        end
    end

    // ---- DDS tone generator (MCLK domain) ----
    wire        sample_tick;
    wire [15:0] audio_sample;

    tone_generator u_tone (
        .clk         (aud_mclk),
        .rst_n       (rst_n & cfg_done),
        .sample_tick (sample_tick),
        .enable      (d_s2),
        .quadrant    (q_s2),
        .audio_out   (audio_sample)
    );

    // ---- I2S transmitter (MCLK domain) ----
    i2s_transmitter u_i2s (
        .mclk        (aud_mclk),
        .rst_n       (rst_n & cfg_done),
        .left_data   (audio_sample),
        .right_data  (audio_sample),
        .aud_bclk    (aud_bclk),
        .aud_daclrck (aud_daclrck),
        .aud_dacdat  (aud_dacdat),
        .sample_tick (sample_tick)
    );

endmodule
