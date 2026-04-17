//=======================================================
//  audio_controller_v2.v
//  Top-level audio wrapper with two modes:
//    Mode 0: Line-in FX (pitch shift / echo per quadrant)
//    Mode 1: Musical notes (additive synth + ADSR)
//  Bridges pixel-clock detection to audio-clock output
//=======================================================
module audio_controller_v2 (
    input        clk_50,           // 50 MHz system clock
    input        rst_n,
    input        audio_mode,       // 0=line-in FX, 1=musical notes
    // detection results (pixel-clock domain)
    input        object_detected,
    input  [1:0] quadrant,

    // WM8731 audio codec pins
    output       aud_xck,          // MCLK ~12.288 MHz
    output       aud_bclk,         // bit clock
    output       aud_daclrck,      // DAC L/R channel clock
    output       aud_dacdat,       // serial DAC data
    output       aud_adclrck,      // ADC L/R clock (= DACLRCK)
    input        aud_adcdat,       // serial ADC data

    // I2C to WM8731
    output       i2c_sclk,
    inout        i2c_sdat,

    // status
    output       audio_config_done
);

    // ============================================================
    // Audio PLL: 50 MHz -> ~12.288 MHz
    // ============================================================
    wire aud_mclk;
    wire pll_locked;

    audio_pll u_pll (
        .refclk   (clk_50),
        .rst      (~rst_n),
        .outclk_0 (aud_mclk),
        .locked   (pll_locked)
    );

    assign aud_xck = aud_mclk;

    // ============================================================
    // WM8731 I2C configuration (50 MHz domain)
    // ============================================================
    wire cfg_done;

    wm8731_config u_cfg (
        .clk         (clk_50),
        .rst_n       (rst_n & pll_locked),
        .i2c_sclk    (i2c_sclk),
        .i2c_sdat    (i2c_sdat),
        .config_done (cfg_done)
    );

    assign audio_config_done = cfg_done;

    // ============================================================
    // I2S Transceiver (MCLK domain)
    // ============================================================
    wire        sample_tick;
    wire [15:0] adc_left, adc_right;
    wire        adc_valid;
    reg  [15:0] dac_left, dac_right;

    i2s_transceiver u_i2s (
        .mclk        (aud_mclk),
        .rst_n       (rst_n & cfg_done),
        .left_data   (dac_left),
        .right_data  (dac_right),
        .aud_bclk    (aud_bclk),
        .aud_daclrck (aud_daclrck),
        .aud_dacdat  (aud_dacdat),
        .sample_tick (sample_tick),
        .adcdat      (aud_adcdat),
        .aud_adclrck (aud_adclrck),
        .adc_left    (adc_left),
        .adc_right   (adc_right),
        .adc_valid   (adc_valid)
    );

    // ============================================================
    // CDC: pixel_clk -> aud_mclk (2-FF synchronizer)
    // ============================================================
    reg [1:0] q_s1, q_s2;
    reg       d_s1, d_s2;
    reg       mode_s1, mode_s2;

    always @(posedge aud_mclk or negedge rst_n) begin
        if (!rst_n) begin
            q_s1 <= 2'd0;  q_s2 <= 2'd0;
            d_s1 <= 1'b0;  d_s2 <= 1'b0;
            mode_s1 <= 1'b0; mode_s2 <= 1'b0;
        end else begin
            q_s1 <= quadrant;         q_s2 <= q_s1;
            d_s1 <= object_detected;  d_s2 <= d_s1;
            mode_s1 <= audio_mode;    mode_s2 <= mode_s1;
        end
    end

    wire        det_sync  = d_s2;
    wire [1:0]  quad_sync = q_s2;
    wire        mode_sync = mode_s2;

    // ============================================================
    // Mode 2: Musical Note Generator
    // ============================================================
    wire [15:0] note_audio;

    musical_note_gen u_note (
        .clk         (aud_mclk),
        .rst_n       (rst_n & cfg_done),
        .sample_tick (sample_tick),
        .enable      (det_sync),
        .quadrant    (quad_sync),
        .audio_out   (note_audio)
    );

    // ============================================================
    // Mode 1: Line-in FX path
    // ============================================================

    // Mono mix of ADC L+R
    wire signed [15:0] adc_l_signed = adc_left;
    wire signed [15:0] adc_r_signed = adc_right;
    wire signed [15:0] mono_in = (adc_l_signed >>> 1) + (adc_r_signed >>> 1);

    // Effect selection based on quadrant
    // TL(00): pitch up 5th,  TR(01): pitch up octave
    // BL(10): pitch down 5th, BR(11): echo 250ms
    // No detect: passthrough

    // Pitch ratio mux
    reg [15:0] pitch_ratio;
    always @(*) begin
        if (!det_sync) begin
            pitch_ratio = 16'd16384;  // 1.0x passthrough
        end else begin
            case (quad_sync)
                2'b00:   pitch_ratio = 16'd24576;  // 1.5x (perfect 5th up)
                2'b01:   pitch_ratio = 16'd32768;  // 2.0x (octave up)
                2'b10:   pitch_ratio = 16'd10923;  // 0.667x (perfect 5th down)
                2'b11:   pitch_ratio = 16'd16384;  // 1.0x (echo mode, pitch pass)
            endcase
        end
    end

    // Bypass flags
    wire pitch_bypass = !det_sync || (quad_sync == 2'b11);
    wire echo_bypass  = !det_sync || (quad_sync != 2'b11);

    // Pitch shifter
    wire [15:0] pitch_out;

    pitch_shifter u_pitch (
        .clk         (aud_mclk),
        .rst_n       (rst_n & cfg_done),
        .sample_tick (sample_tick),
        .ratio       (pitch_ratio),
        .bypass      (pitch_bypass),
        .audio_in    (mono_in),
        .audio_out   (pitch_out)
    );

    // Echo delay
    wire [15:0] echo_out;

    echo_delay u_echo (
        .clk         (aud_mclk),
        .rst_n       (rst_n & cfg_done),
        .sample_tick (sample_tick),
        .bypass      (echo_bypass),
        .audio_in    (mono_in),
        .audio_out   (echo_out)
    );

    // Mode 1 output mux: select pitch or echo based on quadrant
    wire [15:0] fx_audio = (!det_sync)           ? mono_in :
                           (quad_sync == 2'b11)  ? echo_out :
                                                   pitch_out;

    // ============================================================
    // Mode transition blanking (1024-sample zero fade)
    // ============================================================
    reg        mode_prev;
    reg [10:0] blank_cnt;  // 0 = not blanking, >0 = blanking countdown

    always @(posedge aud_mclk or negedge rst_n) begin
        if (!rst_n) begin
            mode_prev <= 1'b0;
            blank_cnt <= 11'd0;
        end else if (sample_tick) begin
            mode_prev <= mode_sync;
            if (mode_sync != mode_prev) begin
                blank_cnt <= 11'd1024;
            end else if (blank_cnt > 11'd0) begin
                blank_cnt <= blank_cnt - 11'd1;
            end
        end
    end

    wire blanking = (blank_cnt > 11'd0);

    // ============================================================
    // Output mux: select mode, apply blanking
    // ============================================================
    wire [15:0] selected_audio = mode_sync ? note_audio : fx_audio;
    wire [15:0] final_audio    = blanking  ? 16'd0      : selected_audio;

    always @(posedge aud_mclk or negedge rst_n) begin
        if (!rst_n) begin
            dac_left  <= 16'd0;
            dac_right <= 16'd0;
        end else if (sample_tick) begin
            dac_left  <= final_audio;
            dac_right <= final_audio;
        end
    end

endmodule
