//=======================================================
//  i2s_transceiver.v
//  Extends i2s_transmitter with ADC receive path
//  Generates BCLK, DACLRCK, DACDAT; captures ADCDAT
//  WM8731 in slave mode, I2S format, 16-bit stereo
//  MCLK ~12.288 MHz -> BCLK = MCLK/4 -> LRCLK = BCLK/64 = ~48 kHz
//=======================================================
module i2s_transceiver (
    input              mclk,         // ~12.288 MHz audio master clock
    input              rst_n,
    // DAC (transmit)
    input      [15:0]  left_data,    // 16-bit signed left channel
    input      [15:0]  right_data,   // 16-bit signed right channel
    output reg         aud_bclk,     // bit clock  (~3.072 MHz)
    output reg         aud_daclrck,  // L/R clock  (~48 kHz)
    output reg         aud_dacdat,   // serial DAC data (MSB first)
    output reg         sample_tick,  // pulse when new sample pair is needed
    // ADC (receive)
    input              adcdat,       // serial ADC data from codec
    output             aud_adclrck,  // ADC L/R clock (same as DACLRCK)
    output reg [15:0]  adc_left,     // received left channel
    output reg [15:0]  adc_right,    // received right channel
    output reg         adc_valid     // pulse when new ADC sample pair is ready
);

    // ADCLRCK = DACLRCK (shared word clock)
    assign aud_adclrck = aud_daclrck;

    // ---- BCLK divider: MCLK / 4 ----
    reg [1:0] mclk_cnt;

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) mclk_cnt <= 2'd0;
        else        mclk_cnt <= mclk_cnt + 2'd1;
    end

    // BCLK = mclk_cnt[1]:  00(L) 01(L) 10(H) 11(H) 00(L) ...
    // Falling edge of BCLK: mclk_cnt wraps 11 -> 00
    wire bclk_fall = (mclk_cnt == 2'd0);
    // Rising edge of BCLK: mclk_cnt == 10
    wire bclk_rise = (mclk_cnt == 2'd2);

    // ---- 64-bit frame counter (32 BCLK per channel x 2 channels) ----
    reg [5:0] bit_cnt;     // 0..63
    reg [15:0] tx_shift;   // TX shift register

    // ---- ADC receive shift registers ----
    reg [15:0] rx_shift;
    reg [15:0] adc_left_buf;
    reg [15:0] adc_right_buf;

    // ---- TX path (on BCLK falling edge, same as original i2s_transmitter) ----
    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt     <= 6'd0;
            aud_bclk    <= 1'b0;
            aud_daclrck <= 1'b0;
            aud_dacdat  <= 1'b0;
            tx_shift    <= 16'd0;
            sample_tick <= 1'b0;
            adc_valid   <= 1'b0;
            rx_shift    <= 16'd0;
            adc_left    <= 16'd0;
            adc_right   <= 16'd0;
            adc_left_buf  <= 16'd0;
            adc_right_buf <= 16'd0;
        end else begin
            aud_bclk    <= mclk_cnt[1];
            sample_tick <= 1'b0;
            adc_valid   <= 1'b0;

            // ---- TX on BCLK falling edge ----
            if (bclk_fall) begin
                // LRCLK generation: low = left (0-31), high = right (32-63)
                aud_daclrck <= bit_cnt[5];

                case (bit_cnt)
                    6'd0: begin
                        // Left channel start: load sample, output I2S delay bit
                        tx_shift    <= left_data;
                        aud_dacdat  <= 1'b0;
                        sample_tick <= 1'b1;
                    end
                    6'd32: begin
                        // Right channel start: load sample, output delay bit
                        tx_shift   <= right_data;
                        aud_dacdat <= 1'b0;
                    end
                    default: begin
                        if ((bit_cnt >= 6'd1  && bit_cnt <= 6'd16) ||
                            (bit_cnt >= 6'd33 && bit_cnt <= 6'd48)) begin
                            aud_dacdat <= tx_shift[15];
                            tx_shift   <= {tx_shift[14:0], 1'b0};
                        end else begin
                            aud_dacdat <= 1'b0;
                        end
                    end
                endcase

                bit_cnt <= bit_cnt + 6'd1;
            end

            // ---- RX on BCLK rising edge ----
            if (bclk_rise) begin
                // I2S format: MSB appears on 2nd rising edge after LRCLK transition
                // (1st rising edge is the I2S delay bit — must skip it)
                //   LRCLK changes at bclk_fall bit_cnt==0 → bit_cnt becomes 1
                //   Rise at bit_cnt 1: delay bit (codec set ADCDAT at fall 0)
                //   Rise at bit_cnt 2: MSB       (codec set ADCDAT at fall 1)
                // Left channel data: bit_cnt 2..17, Right: 34..49

                if ((bit_cnt >= 6'd2  && bit_cnt <= 6'd17) ||
                    (bit_cnt >= 6'd34 && bit_cnt <= 6'd49)) begin
                    rx_shift <= {rx_shift[14:0], adcdat};
                end

                // Capture completed left channel (16 bits shifted in)
                if (bit_cnt == 6'd18) begin
                    adc_left_buf <= rx_shift;
                end

                // Capture completed right channel (16 bits shifted in)
                if (bit_cnt == 6'd50) begin
                    adc_right_buf <= rx_shift;
                end

                // Output valid ADC samples at start of new frame
                if (bit_cnt == 6'd0) begin
                    adc_left  <= adc_left_buf;
                    adc_right <= adc_right_buf;
                    adc_valid <= 1'b1;
                end
            end
        end
    end

endmodule
