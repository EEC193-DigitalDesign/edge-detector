//=======================================================
//  tone_generator.v
//  DDS sine-wave generator with quarter-wave LUT
//  Frequency selected by 2-bit quadrant input
//=======================================================
module tone_generator (
    input              clk,          // audio master clock (~12.288 MHz)
    input              rst_n,
    input              sample_tick,  // pulse at sample rate (~48 kHz)
    input              enable,       // 1 = output tone, 0 = silence
    input      [1:0]   quadrant,     // 00=TL, 01=TR, 10=BL, 11=BR
    output reg [15:0]  audio_out     // 16-bit signed sample
);

    // ---- DDS tuning words (freq * 2^32 / 48000) ----
    localparam [31:0] TW_TL = 32'd71582788;    //  800 Hz  mid range
    localparam [31:0] TW_TR = 32'd178956971;    // 2000 Hz  high pitch
    localparam [31:0] TW_BL = 32'd4473924;      //   50 Hz  sub bass
    localparam [31:0] TW_BR = 32'd17895697;     //  200 Hz  low

    // ---- tuning-word mux ----
    reg [31:0] tuning_word;
    always @(*) begin
        case (quadrant)
            2'b00:   tuning_word = TW_TL;
            2'b01:   tuning_word = TW_TR;
            2'b10:   tuning_word = TW_BL;
            2'b11:   tuning_word = TW_BR;
        endcase
    end

    // ---- 32-bit phase accumulator ----
    reg [31:0] phase_acc;

    // ---- quarter-wave sine table (64 entries, 15-bit unsigned 0..32767) ----
    reg [14:0] qsin [0:63];
    initial begin
        qsin[ 0]=15'd0;     qsin[ 1]=15'd804;   qsin[ 2]=15'd1608;  qsin[ 3]=15'd2410;
        qsin[ 4]=15'd3212;  qsin[ 5]=15'd4011;   qsin[ 6]=15'd4808;  qsin[ 7]=15'd5602;
        qsin[ 8]=15'd6393;  qsin[ 9]=15'd7179;   qsin[10]=15'd7962;  qsin[11]=15'd8739;
        qsin[12]=15'd9512;  qsin[13]=15'd10278;  qsin[14]=15'd11039; qsin[15]=15'd11793;
        qsin[16]=15'd12539; qsin[17]=15'd13279;  qsin[18]=15'd14010; qsin[19]=15'd14732;
        qsin[20]=15'd15446; qsin[21]=15'd16151;  qsin[22]=15'd16846; qsin[23]=15'd17530;
        qsin[24]=15'd18204; qsin[25]=15'd18868;  qsin[26]=15'd19519; qsin[27]=15'd20159;
        qsin[28]=15'd20787; qsin[29]=15'd21403;  qsin[30]=15'd22005; qsin[31]=15'd22594;
        qsin[32]=15'd23170; qsin[33]=15'd23731;  qsin[34]=15'd24279; qsin[35]=15'd24811;
        qsin[36]=15'd25329; qsin[37]=15'd25832;  qsin[38]=15'd26319; qsin[39]=15'd26790;
        qsin[40]=15'd27245; qsin[41]=15'd27683;  qsin[42]=15'd28105; qsin[43]=15'd28510;
        qsin[44]=15'd28898; qsin[45]=15'd29268;  qsin[46]=15'd29621; qsin[47]=15'd29956;
        qsin[48]=15'd30273; qsin[49]=15'd30571;  qsin[50]=15'd30852; qsin[51]=15'd31113;
        qsin[52]=15'd31356; qsin[53]=15'd31580;  qsin[54]=15'd31785; qsin[55]=15'd31971;
        qsin[56]=15'd32137; qsin[57]=15'd32285;  qsin[58]=15'd32412; qsin[59]=15'd32521;
        qsin[60]=15'd32609; qsin[61]=15'd32678;  qsin[62]=15'd32728; qsin[63]=15'd32757;
    end

    // ---- quarter-wave reconstruction ----
    wire [7:0]  ph       = phase_acc[31:24];        // 8-bit phase index
    wire [5:0]  q_addr   = ph[6] ? ~ph[5:0] : ph[5:0]; // mirror in 2nd quarter
    wire        negate   = ph[7];                    // negate in 2nd half
    wire [14:0] q_val    = qsin[q_addr];

    // signed 16-bit output: +q_val or -q_val
    wire [15:0] sine_pos = {1'b0, q_val};            // 0 .. +32757
    wire [15:0] sine_neg = (~{1'b0, q_val}) + 16'd1; // -32757 .. 0
    wire [15:0] sine_val = negate ? sine_neg : sine_pos;

    // ---- phase advance + output register ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 32'd0;
            audio_out <= 16'd0;
        end else if (sample_tick) begin
            if (enable) begin
                audio_out <= sine_val;
                phase_acc <= phase_acc + tuning_word;
            end else begin
                audio_out <= 16'd0;
                phase_acc <= 32'd0;
            end
        end
    end

endmodule
