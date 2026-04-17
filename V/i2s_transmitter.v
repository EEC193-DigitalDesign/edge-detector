//=======================================================
//  i2s_transmitter.v
//  Generates BCLK, DACLRCK, DACDAT from MCLK
//  WM8731 in slave mode, I2S format, 16-bit stereo
//  MCLK ~12.288 MHz  ->  BCLK = MCLK/4  ->  LRCLK = BCLK/64 = ~48 kHz
//=======================================================
module i2s_transmitter (
    input              mclk,         // ~12.288 MHz audio master clock
    input              rst_n,
    input      [15:0]  left_data,    // 16-bit signed left channel
    input      [15:0]  right_data,   // 16-bit signed right channel
    output reg         aud_bclk,     // bit clock  (~3.072 MHz)
    output reg         aud_daclrck,  // L/R clock  (~48 kHz)
    output reg         aud_dacdat,   // serial data (MSB first)
    output reg         sample_tick   // pulse when new sample pair is needed
);

    // ---- BCLK divider: MCLK / 4 ----
    reg [1:0] mclk_cnt;

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) mclk_cnt <= 2'd0;
        else        mclk_cnt <= mclk_cnt + 2'd1;
    end

    // BCLK = mclk_cnt[1]:  00(L) 01(L) 10(H) 11(H) 00(L) ...
    // Falling edge of BCLK: mclk_cnt wraps 11 -> 00
    wire bclk_neg = (mclk_cnt == 2'd0);

    // ---- 64-bit frame counter (32 BCLK per channel x 2 channels) ----
    reg [5:0] bit_cnt;     // 0..63
    reg [15:0] shift_reg;

    always @(posedge mclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt     <= 6'd0;
            aud_bclk    <= 1'b0;
            aud_daclrck <= 1'b0;
            aud_dacdat  <= 1'b0;
            shift_reg   <= 16'd0;
            sample_tick <= 1'b0;
        end else begin
            aud_bclk    <= mclk_cnt[1];
            sample_tick <= 1'b0;

            if (bclk_neg) begin
                // ---- LRCLK generation ----
                // I2S: LRCLK low = left (bits 0-31), high = right (bits 32-63)
                aud_daclrck <= bit_cnt[5];

                // ---- data generation ----
                case (bit_cnt)
                    6'd0: begin
                        // left channel start: load sample, output delay bit
                        shift_reg   <= left_data;
                        aud_dacdat  <= 1'b0;
                        sample_tick <= 1'b1;
                    end
                    6'd32: begin
                        // right channel start: load sample, output delay bit
                        shift_reg  <= right_data;
                        aud_dacdat <= 1'b0;
                    end
                    default: begin
                        if ((bit_cnt >= 6'd1  && bit_cnt <= 6'd16) ||
                            (bit_cnt >= 6'd33 && bit_cnt <= 6'd48)) begin
                            // active data bits: MSB first
                            aud_dacdat <= shift_reg[15];
                            shift_reg  <= {shift_reg[14:0], 1'b0};
                        end else begin
                            // padding zeros (bits 17-31, 49-63)
                            aud_dacdat <= 1'b0;
                        end
                    end
                endcase

                bit_cnt <= bit_cnt + 6'd1;
            end
        end
    end

endmodule
