//=======================================================
//  wm8731_config.v
//  I2C configuration for WM8731 audio codec on DE1-SoC
//  Writes 9 registers at startup, then asserts config_done
//=======================================================
module wm8731_config (
    input        clk,           // 50 MHz system clock
    input        rst_n,
    output reg   i2c_sclk,
    inout        i2c_sdat,
    output reg   config_done
);

    // ---- I2C timing: ~100 kHz SCL ----
    // 4 phases per SCL bit, each phase = 125 system clocks
    // full bit = 500 clocks = 10 us -> 100 kHz
    localparam PHASE_MAX = 7'd124;

    // ---- SDA open-drain ----
    reg sda_oe;                             // 1 = drive low, 0 = release (pull-up)
    assign i2c_sdat = sda_oe ? 1'b0 : 1'bz;

    // ---- config ROM (9 entries) ----
    // each entry = {reg_addr[6:0], data[8:0]} = 16 bits
    // WM8731 write address = 0x34 (7'h1A << 1 | 0)
    localparam NUM_REGS = 4'd9;

    reg [15:0] cfg_word;
    reg [3:0]  reg_idx;

    always @(*) begin
        case (reg_idx)
            4'd0: cfg_word = {7'd15, 9'h000}; // Reset
            4'd1: cfg_word = {7'd2,  9'h079}; // Left  HP Out 0 dB
            4'd2: cfg_word = {7'd3,  9'h079}; // Right HP Out 0 dB
            4'd3: cfg_word = {7'd4,  9'h012}; // Analogue: DAC sel, mic mute
            4'd4: cfg_word = {7'd5,  9'h000}; // Digital: defaults
            4'd5: cfg_word = {7'd6,  9'h007}; // Power: line-in/mic/ADC off
            4'd6: cfg_word = {7'd7,  9'h002}; // Format: I2S 16-bit slave
            4'd7: cfg_word = {7'd8,  9'h000}; // Sampling: normal 256fs 48 kHz
            4'd8: cfg_word = {7'd9,  9'h001}; // Active
            default: cfg_word = 16'd0;
        endcase
    end

    // ---- 3 bytes per transaction ----
    wire [7:0] tx_byte0 = 8'h34;              // device write address
    wire [7:0] tx_byte1 = cfg_word[15:8];     // {reg[6:0], data[8]}
    wire [7:0] tx_byte2 = cfg_word[7:0];      // data[7:0]

    reg [7:0] cur_byte;
    always @(*) begin
        case (byte_idx)
            2'd0:    cur_byte = tx_byte0;
            2'd1:    cur_byte = tx_byte1;
            2'd2:    cur_byte = tx_byte2;
            default: cur_byte = 8'h00;
        endcase
    end

    // ---- state machine ----
    localparam S_IDLE  = 3'd0,
               S_START = 3'd1,
               S_DATA  = 3'd2,
               S_ACK   = 3'd3,
               S_STOP  = 3'd4,
               S_PAUSE = 3'd5,
               S_DONE  = 3'd6;

    reg [2:0]  state;
    reg [1:0]  phase;       // 0..3 within each SCL bit
    reg [6:0]  phase_cnt;   // counter within each phase
    reg [1:0]  byte_idx;    // which byte (0..2)
    reg [2:0]  bit_idx;     // which bit in byte (7 = MSB)
    reg [19:0] pause_cnt;   // inter-register / startup delay

    wire phase_done = (phase_cnt == PHASE_MAX);

    // ---- SCL generation ----
    always @(*) begin
        case (state)
            S_IDLE, S_DONE, S_PAUSE:
                i2c_sclk = 1'b1;
            S_START:
                i2c_sclk = (phase != 2'd3);   // high except phase 3
            S_STOP:
                i2c_sclk = (phase != 2'd0);   // low only phase 0
            default: // S_DATA, S_ACK
                i2c_sclk = (phase == 2'd1 || phase == 2'd2); // high phases 1-2
        endcase
    end

    // ---- main FSM ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            phase       <= 2'd0;
            phase_cnt   <= 7'd0;
            reg_idx     <= 4'd0;
            byte_idx    <= 2'd0;
            bit_idx     <= 3'd7;
            sda_oe      <= 1'b0;
            config_done <= 1'b0;
            pause_cnt   <= 20'd0;
        end else begin
            case (state)
                // ---------- IDLE: startup delay (~20 ms) ----------
                S_IDLE: begin
                    sda_oe <= 1'b0;
                    if (pause_cnt == 20'd999_999) begin   // 20 ms at 50 MHz
                        state     <= S_START;
                        phase     <= 2'd0;
                        phase_cnt <= 7'd0;
                    end else begin
                        pause_cnt <= pause_cnt + 20'd1;
                    end
                end

                // ---------- START condition ----------
                S_START: begin
                    // ph0-1: SDA high, SCL high
                    // ph2:   SDA low  (START), SCL high
                    // ph3:   SDA low, SCL low  -> ready for data
                    if (phase < 2'd2)  sda_oe <= 1'b0;  // SDA high
                    else               sda_oe <= 1'b1;  // SDA low

                    if (phase_done) begin
                        phase_cnt <= 7'd0;
                        if (phase == 2'd3) begin
                            state   <= S_DATA;
                            phase   <= 2'd0;
                            bit_idx <= 3'd7;
                        end else begin
                            phase <= phase + 2'd1;
                        end
                    end else begin
                        phase_cnt <= phase_cnt + 7'd1;
                    end
                end

                // ---------- DATA: clock out 8 bits MSB first ----------
                S_DATA: begin
                    // SDA changes in phase 0 (SCL low), stable phases 1-3
                    if (phase == 2'd0 && phase_cnt == 7'd0)
                        sda_oe <= ~cur_byte[bit_idx]; // 0->release, 1->drive low

                    if (phase_done) begin
                        phase_cnt <= 7'd0;
                        if (phase == 2'd3) begin
                            phase <= 2'd0;
                            if (bit_idx == 3'd0) begin
                                state <= S_ACK;
                            end else begin
                                bit_idx <= bit_idx - 3'd1;
                            end
                        end else begin
                            phase <= phase + 2'd1;
                        end
                    end else begin
                        phase_cnt <= phase_cnt + 7'd1;
                    end
                end

                // ---------- ACK: release SDA, ignore slave response ----------
                S_ACK: begin
                    if (phase == 2'd0 && phase_cnt == 7'd0)
                        sda_oe <= 1'b0;  // release for ACK

                    if (phase_done) begin
                        phase_cnt <= 7'd0;
                        if (phase == 2'd3) begin
                            phase <= 2'd0;
                            if (byte_idx == 2'd2) begin
                                state <= S_STOP;
                            end else begin
                                byte_idx <= byte_idx + 2'd1;
                                bit_idx  <= 3'd7;
                                state    <= S_DATA;
                            end
                        end else begin
                            phase <= phase + 2'd1;
                        end
                    end else begin
                        phase_cnt <= phase_cnt + 7'd1;
                    end
                end

                // ---------- STOP condition ----------
                S_STOP: begin
                    // ph0: SDA low, SCL low
                    // ph1: SDA low, SCL high
                    // ph2: SDA high (STOP), SCL high
                    // ph3: SDA high, SCL high
                    if (phase < 2'd2)  sda_oe <= 1'b1;  // SDA low
                    else               sda_oe <= 1'b0;  // SDA high (STOP)

                    if (phase_done) begin
                        phase_cnt <= 7'd0;
                        if (phase == 2'd3) begin
                            state     <= S_PAUSE;
                            pause_cnt <= 20'd0;
                        end else begin
                            phase <= phase + 2'd1;
                        end
                    end else begin
                        phase_cnt <= phase_cnt + 7'd1;
                    end
                end

                // ---------- PAUSE between registers ----------
                S_PAUSE: begin
                    sda_oe <= 1'b0;
                    if (pause_cnt == 20'd49_999) begin     // 1 ms pause
                        if (reg_idx == NUM_REGS - 4'd1) begin
                            state       <= S_DONE;
                            config_done <= 1'b1;
                        end else begin
                            reg_idx   <= reg_idx + 4'd1;
                            byte_idx  <= 2'd0;
                            bit_idx   <= 3'd7;
                            phase     <= 2'd0;
                            phase_cnt <= 7'd0;
                            state     <= S_START;
                        end
                    end else begin
                        pause_cnt <= pause_cnt + 20'd1;
                    end
                end

                // ---------- DONE ----------
                S_DONE: begin
                    config_done <= 1'b1;
                    sda_oe      <= 1'b0;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
