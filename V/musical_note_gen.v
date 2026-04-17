//=======================================================
//  musical_note_gen.v
//  Additive synthesis (3 harmonics) + ADSR envelope
//  + Proximity-based volume control
//  Drop-in replacement for tone_generator.v
//  Quadrant -> G4/C4/E4/A4 musical notes
//=======================================================
module musical_note_gen (
    input              clk,          // ~12.288 MHz (MCLK)
    input              rst_n,
    input              sample_tick,  // ~48 kHz
    input              enable,       // object_detected (CDC'd)
    input      [1:0]   quadrant,     // (CDC'd)
    input      [7:0]   proximity,    // 0=far/silent, 255=near/loud (CDC'd)
    output reg [15:0]  audio_out     // 16-bit signed
);

    // ---- DDS tuning words (freq * 2^32 / 48000) ----
    localparam [31:0] TW_G4 = 32'd35_075_404;   // 392.00 Hz  (TL)
    localparam [31:0] TW_C4 = 32'd23_407_170;   // 261.63 Hz  (TR)
    localparam [31:0] TW_E4 = 32'd29_494_987;   // 329.63 Hz  (BL)
    localparam [31:0] TW_A4 = 32'd39_370_534;   // 440.00 Hz  (BR)

    // ---- ADSR parameters ----
    localparam [15:0] ATTACK_RATE    = 16'd34;    // +34/sample, ~20ms attack
    localparam [15:0] DECAY_RATE     = 16'd3;     // -3/sample, ~80ms decay
    localparam [15:0] SUSTAIN_LEVEL  = 16'd22937; // 70% of 32767
    localparam [15:0] RELEASE_RATE   = 16'd3;     // -3/sample, ~150ms release

    // ADSR states
    localparam [2:0] ST_IDLE    = 3'd0,
                     ST_ATTACK  = 3'd1,
                     ST_DECAY   = 3'd2,
                     ST_SUSTAIN = 3'd3,
                     ST_RELEASE = 3'd4;

    // ---- 256-entry quarter-wave sine LUT (16-bit unsigned, 0..32767) ----
    reg [15:0] qsin [0:255];
    initial begin
        qsin[  0]=16'd    0; qsin[  1]=16'd  201; qsin[  2]=16'd  402; qsin[  3]=16'd  603; qsin[  4]=16'd  804; qsin[  5]=16'd 1005; qsin[  6]=16'd 1206; qsin[  7]=16'd 1407;
        qsin[  8]=16'd 1608; qsin[  9]=16'd 1809; qsin[ 10]=16'd 2009; qsin[ 11]=16'd 2210; qsin[ 12]=16'd 2410; qsin[ 13]=16'd 2611; qsin[ 14]=16'd 2811; qsin[ 15]=16'd 3012;
        qsin[ 16]=16'd 3212; qsin[ 17]=16'd 3412; qsin[ 18]=16'd 3612; qsin[ 19]=16'd 3811; qsin[ 20]=16'd 4011; qsin[ 21]=16'd 4210; qsin[ 22]=16'd 4410; qsin[ 23]=16'd 4609;
        qsin[ 24]=16'd 4808; qsin[ 25]=16'd 5007; qsin[ 26]=16'd 5205; qsin[ 27]=16'd 5404; qsin[ 28]=16'd 5602; qsin[ 29]=16'd 5800; qsin[ 30]=16'd 5998; qsin[ 31]=16'd 6195;
        qsin[ 32]=16'd 6393; qsin[ 33]=16'd 6590; qsin[ 34]=16'd 6786; qsin[ 35]=16'd 6983; qsin[ 36]=16'd 7179; qsin[ 37]=16'd 7375; qsin[ 38]=16'd 7571; qsin[ 39]=16'd 7767;
        qsin[ 40]=16'd 7962; qsin[ 41]=16'd 8157; qsin[ 42]=16'd 8351; qsin[ 43]=16'd 8545; qsin[ 44]=16'd 8739; qsin[ 45]=16'd 8933; qsin[ 46]=16'd 9126; qsin[ 47]=16'd 9319;
        qsin[ 48]=16'd 9512; qsin[ 49]=16'd 9704; qsin[ 50]=16'd 9896; qsin[ 51]=16'd10087; qsin[ 52]=16'd10278; qsin[ 53]=16'd10469; qsin[ 54]=16'd10659; qsin[ 55]=16'd10849;
        qsin[ 56]=16'd11039; qsin[ 57]=16'd11228; qsin[ 58]=16'd11417; qsin[ 59]=16'd11605; qsin[ 60]=16'd11793; qsin[ 61]=16'd11980; qsin[ 62]=16'd12167; qsin[ 63]=16'd12353;
        qsin[ 64]=16'd12539; qsin[ 65]=16'd12725; qsin[ 66]=16'd12910; qsin[ 67]=16'd13094; qsin[ 68]=16'd13279; qsin[ 69]=16'd13462; qsin[ 70]=16'd13645; qsin[ 71]=16'd13828;
        qsin[ 72]=16'd14010; qsin[ 73]=16'd14191; qsin[ 74]=16'd14372; qsin[ 75]=16'd14553; qsin[ 76]=16'd14732; qsin[ 77]=16'd14912; qsin[ 78]=16'd15090; qsin[ 79]=16'd15269;
        qsin[ 80]=16'd15446; qsin[ 81]=16'd15623; qsin[ 82]=16'd15800; qsin[ 83]=16'd15976; qsin[ 84]=16'd16151; qsin[ 85]=16'd16325; qsin[ 86]=16'd16499; qsin[ 87]=16'd16673;
        qsin[ 88]=16'd16846; qsin[ 89]=16'd17018; qsin[ 90]=16'd17189; qsin[ 91]=16'd17360; qsin[ 92]=16'd17530; qsin[ 93]=16'd17700; qsin[ 94]=16'd17869; qsin[ 95]=16'd18037;
        qsin[ 96]=16'd18204; qsin[ 97]=16'd18371; qsin[ 98]=16'd18537; qsin[ 99]=16'd18703; qsin[100]=16'd18868; qsin[101]=16'd19032; qsin[102]=16'd19195; qsin[103]=16'd19357;
        qsin[104]=16'd19519; qsin[105]=16'd19680; qsin[106]=16'd19841; qsin[107]=16'd20000; qsin[108]=16'd20159; qsin[109]=16'd20317; qsin[110]=16'd20475; qsin[111]=16'd20631;
        qsin[112]=16'd20787; qsin[113]=16'd20942; qsin[114]=16'd21096; qsin[115]=16'd21250; qsin[116]=16'd21403; qsin[117]=16'd21554; qsin[118]=16'd21705; qsin[119]=16'd21856;
        qsin[120]=16'd22005; qsin[121]=16'd22154; qsin[122]=16'd22301; qsin[123]=16'd22448; qsin[124]=16'd22594; qsin[125]=16'd22739; qsin[126]=16'd22884; qsin[127]=16'd23027;
        qsin[128]=16'd23170; qsin[129]=16'd23311; qsin[130]=16'd23452; qsin[131]=16'd23592; qsin[132]=16'd23731; qsin[133]=16'd23870; qsin[134]=16'd24007; qsin[135]=16'd24143;
        qsin[136]=16'd24279; qsin[137]=16'd24413; qsin[138]=16'd24547; qsin[139]=16'd24680; qsin[140]=16'd24811; qsin[141]=16'd24942; qsin[142]=16'd25072; qsin[143]=16'd25201;
        qsin[144]=16'd25329; qsin[145]=16'd25456; qsin[146]=16'd25582; qsin[147]=16'd25708; qsin[148]=16'd25832; qsin[149]=16'd25955; qsin[150]=16'd26077; qsin[151]=16'd26198;
        qsin[152]=16'd26319; qsin[153]=16'd26438; qsin[154]=16'd26556; qsin[155]=16'd26674; qsin[156]=16'd26790; qsin[157]=16'd26905; qsin[158]=16'd27019; qsin[159]=16'd27133;
        qsin[160]=16'd27245; qsin[161]=16'd27356; qsin[162]=16'd27466; qsin[163]=16'd27575; qsin[164]=16'd27683; qsin[165]=16'd27790; qsin[166]=16'd27896; qsin[167]=16'd28001;
        qsin[168]=16'd28105; qsin[169]=16'd28208; qsin[170]=16'd28310; qsin[171]=16'd28411; qsin[172]=16'd28510; qsin[173]=16'd28609; qsin[174]=16'd28706; qsin[175]=16'd28803;
        qsin[176]=16'd28898; qsin[177]=16'd28992; qsin[178]=16'd29085; qsin[179]=16'd29177; qsin[180]=16'd29268; qsin[181]=16'd29358; qsin[182]=16'd29447; qsin[183]=16'd29534;
        qsin[184]=16'd29621; qsin[185]=16'd29706; qsin[186]=16'd29791; qsin[187]=16'd29874; qsin[188]=16'd29956; qsin[189]=16'd30037; qsin[190]=16'd30117; qsin[191]=16'd30195;
        qsin[192]=16'd30273; qsin[193]=16'd30349; qsin[194]=16'd30424; qsin[195]=16'd30498; qsin[196]=16'd30571; qsin[197]=16'd30643; qsin[198]=16'd30714; qsin[199]=16'd30783;
        qsin[200]=16'd30852; qsin[201]=16'd30919; qsin[202]=16'd30985; qsin[203]=16'd31050; qsin[204]=16'd31113; qsin[205]=16'd31176; qsin[206]=16'd31237; qsin[207]=16'd31297;
        qsin[208]=16'd31356; qsin[209]=16'd31414; qsin[210]=16'd31470; qsin[211]=16'd31526; qsin[212]=16'd31580; qsin[213]=16'd31633; qsin[214]=16'd31685; qsin[215]=16'd31736;
        qsin[216]=16'd31785; qsin[217]=16'd31833; qsin[218]=16'd31880; qsin[219]=16'd31926; qsin[220]=16'd31971; qsin[221]=16'd32014; qsin[222]=16'd32057; qsin[223]=16'd32098;
        qsin[224]=16'd32137; qsin[225]=16'd32176; qsin[226]=16'd32213; qsin[227]=16'd32250; qsin[228]=16'd32285; qsin[229]=16'd32318; qsin[230]=16'd32351; qsin[231]=16'd32382;
        qsin[232]=16'd32412; qsin[233]=16'd32441; qsin[234]=16'd32469; qsin[235]=16'd32495; qsin[236]=16'd32521; qsin[237]=16'd32545; qsin[238]=16'd32567; qsin[239]=16'd32589;
        qsin[240]=16'd32609; qsin[241]=16'd32628; qsin[242]=16'd32646; qsin[243]=16'd32663; qsin[244]=16'd32678; qsin[245]=16'd32692; qsin[246]=16'd32705; qsin[247]=16'd32717;
        qsin[248]=16'd32728; qsin[249]=16'd32737; qsin[250]=16'd32745; qsin[251]=16'd32752; qsin[252]=16'd32757; qsin[253]=16'd32761; qsin[254]=16'd32765; qsin[255]=16'd32766;
    end

    // ---- Quarter-wave sine reconstruction function ----
    // Input: 10-bit phase (top 10 bits of 32-bit accumulator)
    // Output: 16-bit signed value
    function [15:0] sine_lookup;
        input [9:0] phase10;
        reg [7:0] addr;
        reg       mirror;
        reg       negate;
        reg [15:0] mag;
    begin
        negate = phase10[9];          // upper half -> negate
        mirror = phase10[8];          // 2nd quarter -> mirror
        addr   = mirror ? ~phase10[7:0] : phase10[7:0];
        mag    = qsin[addr];
        sine_lookup = negate ? (~mag + 16'd1) : mag;
    end
    endfunction

    // ---- Tuning word mux ----
    reg [31:0] tuning_word_mux;
    always @(*) begin
        case (quadrant)
            2'b00:   tuning_word_mux = TW_G4;
            2'b01:   tuning_word_mux = TW_C4;
            2'b10:   tuning_word_mux = TW_E4;
            2'b11:   tuning_word_mux = TW_A4;
        endcase
    end

    // ---- State registers ----
    reg [31:0] phase_acc;
    reg [31:0] active_tuning_word;
    reg [1:0]  active_quadrant;
    reg [2:0]  adsr_state;
    reg [15:0] envelope;          // 0..32767
    reg        enable_prev;

    // ---- Harmonic phase computation (combinational) ----
    wire [31:0] phase_h1 = phase_acc;
    wire [31:0] phase_h2 = phase_acc << 1;
    wire [31:0] phase_h3 = phase_acc + (phase_acc << 1); // 3x fundamental

    // ---- Sine lookups for each harmonic ----
    wire [15:0] sine_h1 = sine_lookup(phase_h1[31:22]);
    wire [15:0] sine_h2 = sine_lookup(phase_h2[31:22]);
    wire [15:0] sine_h3 = sine_lookup(phase_h3[31:22]);

    // ---- Additive synthesis: weighted sum ----
    // h1 * 0.5 + h2 * 0.25 + h3 * 0.125
    // Use arithmetic right shift (signed)
    wire signed [15:0] s_h1 = sine_h1;
    wire signed [15:0] s_h2 = sine_h2;
    wire signed [15:0] s_h3 = sine_h3;
    wire signed [15:0] mix_h1 = s_h1 >>> 1;    // fundamental / 2
    wire signed [15:0] mix_h2 = s_h2 >>> 2;    // 2nd harmonic / 4
    wire signed [15:0] mix_h3 = s_h3 >>> 3;    // 3rd harmonic / 8

    wire signed [17:0] raw_sum = {mix_h1[15], mix_h1[15], mix_h1} +
                                 {mix_h2[15], mix_h2[15], mix_h2} +
                                 {mix_h3[15], mix_h3[15], mix_h3};
    // raw_sum max magnitude = 16383 + 8191 + 4095 = 28669 < 32767
    wire signed [15:0] raw_sample = raw_sum[15:0];

    // ---- Envelope multiplication ----
    // audio = (raw_sample * envelope) >>> 15
    wire signed [31:0] env_product = raw_sample * $signed({1'b0, envelope});
    wire signed [15:0] env_scaled = env_product[30:15];

    // ---- Distance-based volume scaling ----
    // final = (env_scaled * proximity) >>> 8
    // proximity=255 -> full volume, proximity=0 -> silent
    wire signed [23:0] vol_product = env_scaled * $signed({1'b0, proximity});
    wire signed [15:0] vol_scaled  = vol_product[23:8];

    // ---- Main FSM ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc         <= 32'd0;
            active_tuning_word<= 32'd0;
            active_quadrant   <= 2'd0;
            adsr_state        <= ST_IDLE;
            envelope          <= 16'd0;
            enable_prev       <= 1'b0;
            audio_out         <= 16'd0;
        end else if (sample_tick) begin
            enable_prev <= enable;

            case (adsr_state)
                ST_IDLE: begin
                    audio_out <= 16'd0;
                    if (enable && !enable_prev) begin
                        // Rising edge of enable -> start attack
                        active_quadrant    <= quadrant;
                        active_tuning_word <= tuning_word_mux;
                        adsr_state         <= ST_ATTACK;
                        envelope           <= 16'd0;
                    end else if (enable) begin
                        // Was already enabled but we were idle (release finished)
                        active_quadrant    <= quadrant;
                        active_tuning_word <= tuning_word_mux;
                        adsr_state         <= ST_ATTACK;
                        envelope           <= 16'd0;
                    end
                end

                ST_ATTACK: begin
                    audio_out <= vol_scaled;
                    phase_acc <= phase_acc + active_tuning_word;

                    if (!enable) begin
                        adsr_state <= ST_RELEASE;
                    end else if (quadrant != active_quadrant) begin
                        adsr_state <= ST_RELEASE;
                    end else if (envelope >= 16'd32767 - ATTACK_RATE) begin
                        envelope   <= 16'd32767;
                        adsr_state <= ST_DECAY;
                    end else begin
                        envelope <= envelope + ATTACK_RATE;
                    end
                end

                ST_DECAY: begin
                    audio_out <= vol_scaled;
                    phase_acc <= phase_acc + active_tuning_word;

                    if (!enable) begin
                        adsr_state <= ST_RELEASE;
                    end else if (quadrant != active_quadrant) begin
                        adsr_state <= ST_RELEASE;
                    end else if (envelope <= SUSTAIN_LEVEL + DECAY_RATE) begin
                        envelope   <= SUSTAIN_LEVEL;
                        adsr_state <= ST_SUSTAIN;
                    end else begin
                        envelope <= envelope - DECAY_RATE;
                    end
                end

                ST_SUSTAIN: begin
                    audio_out <= vol_scaled;
                    phase_acc <= phase_acc + active_tuning_word;

                    if (!enable) begin
                        adsr_state <= ST_RELEASE;
                    end else if (quadrant != active_quadrant) begin
                        adsr_state <= ST_RELEASE;
                    end
                    // else hold at sustain level
                end

                ST_RELEASE: begin
                    audio_out <= vol_scaled;
                    phase_acc <= phase_acc + active_tuning_word;

                    if (envelope <= RELEASE_RATE) begin
                        envelope   <= 16'd0;
                        adsr_state <= ST_IDLE;
                    end else begin
                        envelope <= envelope - RELEASE_RATE;
                    end
                end

                default: begin
                    adsr_state <= ST_IDLE;
                    envelope   <= 16'd0;
                end
            endcase
        end
    end

endmodule
