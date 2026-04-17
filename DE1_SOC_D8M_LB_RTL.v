//=======================================================
//  DE1-SoC / D8M  edge detector + checkerboard object
//  detection + audio quadrant feedback
//=======================================================

module DE1_SOC_D8M_LB_RTL(

	//////////// CLOCK //////////
	input 		          		CLOCK2_50,
	input 		          		CLOCK3_50,
	input 		          		CLOCK4_50,
	input 		          		CLOCK_50,

	//////////// SEG7 //////////
	output		     [6:0]		HEX0,
	output		     [6:0]		HEX1,
	output		     [6:0]		HEX2,
	output		     [6:0]		HEX3,
	output		     [6:0]		HEX4,
	output		     [6:0]		HEX5,

	//////////// KEY //////////
	input 		     [3:0]		KEY,

	//////////// LED //////////
	output		     [9:0]		LEDR,

	//////////// SW //////////
	input 		     [9:0]		SW,

	//////////// VGA //////////
	output		          		VGA_BLANK_N,
	output		     [7:0]		VGA_B,
	output		          		VGA_CLK,
	output		     [7:0]		VGA_G,
	output	reg	          		VGA_HS,
	output		     [7:0]		VGA_R,
	output		          		VGA_SYNC_N,
	output	reg	          		VGA_VS,

	//////////// Audio //////////
	input 		          		AUD_ADCDAT,
	inout 		          		AUD_ADCLRCK,
	inout 		          		AUD_BCLK,
	output		          		AUD_DACDAT,
	inout 		          		AUD_DACLRCK,
	output		          		AUD_XCK,

	//////////// FPGA I2C (WM8731) //////////
	output		          		FPGA_I2C_SCLK,
	inout 		          		FPGA_I2C_SDAT,

	//////////// GPIO_1, GPIO_1 connect to D8M-GPIO //////////
	inout 		          		CAMERA_I2C_SCL,
	inout 		          		CAMERA_I2C_SDA,
	output		          		CAMERA_PWDN_n,
	output		          		MIPI_CS_n,
	inout 		          		MIPI_I2C_SCL,
	inout 		          		MIPI_I2C_SDA,
	output		          		MIPI_MCLK,
	input 		          		MIPI_PIXEL_CLK,
	input 		     [9:0]		MIPI_PIXEL_D,
	input 		          		MIPI_PIXEL_HS,
	input 		          		MIPI_PIXEL_VS,
	output		          		MIPI_REFCLK,
	output		          		MIPI_RESET_n
);

//=============================================================================
// REG/WIRE declarations
//=============================================================================
wire        AUTO_FOC;
wire        READ_Request;
wire  [7:0] VGA_B_A;
wire  [7:0] VGA_G_A;
wire  [7:0] VGA_R_A;
wire  [7:0] VGA_R_unfilt;
wire  [7:0] VGA_G_unfilt;
wire  [7:0] VGA_B_unfilt;
wire        VGA_CLK_25M;
wire        RESET_N;
wire  [7:0] sCCD_R;
wire  [7:0] sCCD_G;
wire  [7:0] sCCD_B;
wire [15:0] H_Cont;
wire [15:0] V_Cont;
wire        I2C_RELEASE;
wire        CAMERA_I2C_SCL_MIPI;
wire        CAMERA_I2C_SCL_AF;
wire        CAMERA_MIPI_RELAESE;
wire        MIPI_BRIDGE_RELEASE;
wire        D8M_CK_HZ;
wire        D8M_CK_HZ2;
wire        D8M_CK_HZ3;
wire        RESET_KEY;

wire        LUT_MIPI_PIXEL_HS;
wire        LUT_MIPI_PIXEL_VS;
wire [9:0]  LUT_MIPI_PIXEL_D;
wire        MIPI_PIXEL_CLK_;

// ---------- upgraded edge path ----------
wire [7:0] edge_gray;
wire [7:0] edge_r;
wire [7:0] edge_g;
wire [7:0] edge_b;
wire       edge_valid;

// ---------- detection ----------
wire        obj_detected;
wire [1:0]  obj_quadrant;
wire [19:0] cnt_tl, cnt_tr, cnt_bl, cnt_br;
wire        audio_cfg_done;

// ---------- audio mode toggle (KEY[3]) ----------
reg         audio_mode;      // 0=line-in FX, 1=musical notes
reg         key3_d;
reg [19:0]  key3_lockout;

// -------- switch map --------
// SW[0] = 1 enable edge path, 0 show normal camera
// SW[1] = 1 overlay edges on original image, 0 show edge-only
// SW[2] = 1 enable Gaussian blur, 0 bypass blur
// SW[3] = autofocus assist mode
// SW[4] = 1 use focus-adjusted video as edge input, 0 use raw camera RGB
// SW[5:8] = edge threshold (4-bit -> 0,16,32,...,240)
// SW[9] = 1 edge polarity white-on-black, 0 black-on-white
wire [7:0] edge_threshold;
assign edge_threshold = {4'b0000, SW[8:5]} << 4;

wire [7:0] edge_src_r = SW[4] ? VGA_R_unfilt : VGA_R_A;
wire [7:0] edge_src_g = SW[4] ? VGA_G_unfilt : VGA_G_A;
wire [7:0] edge_src_b = SW[4] ? VGA_B_unfilt : VGA_B_A;

// ---- detection threshold (KEY[1] = down, KEY[2] = up) ----
// Proper debounce: 20ms lockout after any press (~1M cycles at 50 MHz)
reg [7:0]  detect_thresh;
reg        key1_d, key2_d;
reg [19:0] key_lockout;

always @(posedge CLOCK_50 or negedge RESET_N) begin
	if (!RESET_N) begin
		detect_thresh <= 8'd30;
		key1_d <= 1'b1;
		key2_d <= 1'b1;
		key_lockout <= 20'd0;
	end else begin
		key1_d <= KEY[1];
		key2_d <= KEY[2];
		if (key_lockout > 20'd0) begin
			key_lockout <= key_lockout - 20'd1;
		end else begin
			// KEY active-low: falling edge = press
			if (~KEY[1] & key1_d) begin
				if (detect_thresh > 8'd8)
					detect_thresh <= detect_thresh - 8'd8;
				key_lockout <= 20'hFFFFF;
			end
			if (~KEY[2] & key2_d) begin
				if (detect_thresh < 8'd248)
					detect_thresh <= detect_thresh + 8'd8;
				key_lockout <= 20'hFFFFF;
			end
		end
	end
end

// ---- KEY[3] audio mode toggle with 20ms debounce ----
always @(posedge CLOCK_50 or negedge RESET_N) begin
	if (!RESET_N) begin
		audio_mode   <= 1'b0;
		key3_d       <= 1'b1;
		key3_lockout <= 20'd0;
	end else begin
		key3_d <= KEY[3];
		if (key3_lockout > 20'd0) begin
			key3_lockout <= key3_lockout - 20'd1;
		end else begin
			if (~KEY[3] & key3_d) begin
				audio_mode   <= ~audio_mode;
				key3_lockout <= 20'hFFFFF;
			end
		end
	end
end

//=======================================================
// Structural coding
//=======================================================

assign MIPI_PIXEL_CLK_  = MIPI_PIXEL_CLK;
assign LUT_MIPI_PIXEL_HS = MIPI_PIXEL_HS;
assign LUT_MIPI_PIXEL_VS = MIPI_PIXEL_VS;
assign LUT_MIPI_PIXEL_D  = MIPI_PIXEL_D;

assign RESET_KEY = KEY[0];

//----- RESET RELAY  --
RESET_DELAY u2(
	.iRST  ( RESET_KEY ),
	.iCLK  ( CLOCK2_50 ),
	.oREADY( RESET_N)
);

assign MIPI_RESET_n  = RESET_N;
assign CAMERA_PWDN_n = RESET_KEY;
assign MIPI_CS_n     = 1'b0;

//------ CAMERA I2C COM BUS --------------------
assign I2C_RELEASE    = CAMERA_MIPI_RELAESE & MIPI_BRIDGE_RELEASE;
assign CAMERA_I2C_SCL = (I2C_RELEASE) ? CAMERA_I2C_SCL_AF : CAMERA_I2C_SCL_MIPI;

//------ MIPI BRIDGE  I2C SETTING---------------
MIPI_BRIDGE_CAMERA_Config cfin(
   .RESET_N           ( RESET_N ),
   .CLK_50            ( CLOCK2_50 ),
   .MIPI_I2C_SCL      ( MIPI_I2C_SCL ),
   .MIPI_I2C_SDA      ( MIPI_I2C_SDA ),
   .MIPI_I2C_RELEASE  ( MIPI_BRIDGE_RELEASE ),
   .CAMERA_I2C_SCL    ( CAMERA_I2C_SCL_MIPI ),
   .CAMERA_I2C_SDA    ( CAMERA_I2C_SDA ),
   .CAMERA_I2C_RELAESE( CAMERA_MIPI_RELAESE )
);

//-- Video PLL ---
pll_test ref(
	.refclk   ( CLOCK_50 ),
	.rst      ( 1'b0 ),
	.outclk_0 ( MIPI_REFCLK )
);

vga_pll pllv(
	.refclk   ( CLOCK4_50 ),
	.rst      ( 1'b0 ),
	.outclk_0 ( VGA_CLK_25M )
);

//--- D8M RAWDATA to RGB ---
D8M_SET ccd(
	.RESET_SYS_N  ( RESET_N ),
    .CLOCK_50     ( CLOCK2_50 ),
	.CCD_DATA     ( LUT_MIPI_PIXEL_D[9:0] ),
	.CCD_FVAL     ( LUT_MIPI_PIXEL_VS ),
	.CCD_LVAL	  ( LUT_MIPI_PIXEL_HS ),
	.CCD_PIXCLK   ( MIPI_PIXEL_CLK_ ),
	.READ_EN      ( READ_Request ),
    .VGA_HS       ( VGA_HS ),
    .VGA_VS       ( VGA_VS ),
	.X_Cont       ( H_Cont ),
    .Y_Cont       ( V_Cont ),
    .sCCD_R       ( sCCD_R ),
    .sCCD_G       ( sCCD_G ),
    .sCCD_B       ( sCCD_B )
);

//--- VGA interface signals ---
assign VGA_CLK    = MIPI_PIXEL_CLK_;
assign VGA_SYNC_N = 1'b0;

// READ_Request: active during valid pixel region
assign READ_Request = ((H_Cont > 16'd160 && H_Cont < 16'd800) &&
                       (V_Cont > 16'd045 && V_Cont < 16'd525));

// Blanking signal (active low)
assign VGA_BLANK_N = ~((H_Cont < 16'd160) || (V_Cont < 16'd045));

// Pixel data gated by blanking
assign VGA_R_A = VGA_BLANK_N ? sCCD_R : 8'h00;
assign VGA_G_A = VGA_BLANK_N ? sCCD_G : 8'h00;
assign VGA_B_A = VGA_BLANK_N ? sCCD_B : 8'h00;

// Generate horizontal and vertical sync signals
always @(*) begin
   if ((H_Cont >= 16'd002) && (H_Cont <= 16'd097))
      VGA_HS = 1'b0;
   else
      VGA_HS = 1'b1;

   if ((V_Cont >= 16'd013) && (V_Cont <= 16'd014))
      VGA_VS = 1'b0;
   else
      VGA_VS = 1'b1;
end

//------ AUTO FOCUS ENABLE  --
AUTO_FOCUS_ON adj(
    .CLK_50      ( CLOCK2_50 ),
    .I2C_RELEASE ( I2C_RELEASE ),
    .AUTO_FOC    ( AUTO_FOC )
);

//------ Auto focus -------
FOCUS_ADJ adl(
     .CLK_50        ( CLOCK2_50 ),
     .RESET_N       ( I2C_RELEASE ),
     .RESET_SUB_N   ( I2C_RELEASE ),
     .AUTO_FOC      ( AUTO_FOC ),
     .SW_FUC_LINE   ( SW[3] ),
     .SW_FUC_ALL_CEN( SW[3] ),
     .VIDEO_HS      ( VGA_HS ),
     .VIDEO_VS      ( VGA_VS ),
     .VIDEO_CLK     ( VGA_CLK ),
     .VIDEO_DE      ( READ_Request ),
     .iR            ( VGA_R_A ),
     .iG            ( VGA_G_A ),
     .iB            ( VGA_B_A ),
     .oR            ( VGA_R_unfilt ),
     .oG            ( VGA_G_unfilt ),
     .oB            ( VGA_B_unfilt ),
     .READY         ( READY ),
     .SCL           ( CAMERA_I2C_SCL_AF ),
     .SDA           ( CAMERA_I2C_SDA )
);

//--- Upgraded edge detector ---
edge_enhancer #(
    .IMAGE_WIDTH(640)
) edge_inst (
    .clk           ( MIPI_PIXEL_CLK_ ),
    .rst_n         ( RESET_N ),
    .de            ( READ_Request ),
    .r_in          ( edge_src_r ),
    .g_in          ( edge_src_g ),
    .b_in          ( edge_src_b ),
    .enable_blur   ( SW[2] ),
    .overlay_mode  ( SW[1] ),
    .invert_edges  ( SW[9] ),
    .threshold     ( edge_threshold ),
    .edge_gray     ( edge_gray ),
    .edge_r        ( edge_r ),
    .edge_g        ( edge_g ),
    .edge_b        ( edge_b ),
    .edge_valid    ( edge_valid )
);

//=======================================================
//  Object detection  (checkerboard -> edge-density)
//=======================================================
edge_detect_tracker #(
    .H_CENTER(16'd481),
    .V_CENTER(16'd286)
) u_detect (
    .clk           ( MIPI_PIXEL_CLK_ ),
    .rst_n         ( RESET_N ),
    .de            ( READ_Request ),
    .r_in          ( edge_src_r ),
    .g_in          ( edge_src_g ),
    .b_in          ( edge_src_b ),
    .h_count       ( H_Cont ),
    .v_count       ( V_Cont ),
    .vs            ( VGA_VS ),
    .detect_thresh ( detect_thresh ),
    .min_count     ( 16'd200 ),
    .object_detected( obj_detected ),
    .quadrant      ( obj_quadrant ),
    .count_tl      ( cnt_tl ),
    .count_tr      ( cnt_tr ),
    .count_bl      ( cnt_bl ),
    .count_br      ( cnt_br )
);

//=======================================================
//  Audio controller v2 (dual mode: line-in FX / musical notes)
//=======================================================
audio_controller_v2 u_audio (
    .clk_50          ( CLOCK_50 ),
    .rst_n           ( RESET_N ),
    .audio_mode      ( audio_mode ),
    .object_detected ( obj_detected ),
    .quadrant        ( obj_quadrant ),
    .aud_xck         ( AUD_XCK ),
    .aud_bclk        ( AUD_BCLK ),
    .aud_daclrck     ( AUD_DACLRCK ),
    .aud_dacdat      ( AUD_DACDAT ),
    .aud_adclrck     ( AUD_ADCLRCK ),
    .aud_adcdat      ( AUD_ADCDAT ),
    .i2c_sclk        ( FPGA_I2C_SCLK ),
    .i2c_sdat        ( FPGA_I2C_SDAT ),
    .audio_config_done( audio_cfg_done )
);

//=======================================================
//  VGA output with crosshair overlay
//=======================================================

// crosshair lines at screen center (1 px green lines)
wire is_h_center = (H_Cont >= 16'd480 && H_Cont <= 16'd482);
wire is_v_center = (V_Cont >= 16'd285 && V_Cont <= 16'd287);
wire is_crosshair = VGA_BLANK_N & (is_h_center | is_v_center);

// detected-quadrant highlight: thin green border (2 px) around active quadrant
wire in_left  = (H_Cont < 16'd481);
wire in_top   = (V_Cont < 16'd286);
wire in_quad_tl = in_top  &  in_left;
wire in_quad_tr = in_top  & ~in_left;
wire in_quad_bl = ~in_top &  in_left;
wire in_quad_br = ~in_top & ~in_left;

wire in_active_quad = (obj_quadrant == 2'b00 && in_quad_tl) |
                      (obj_quadrant == 2'b01 && in_quad_tr) |
                      (obj_quadrant == 2'b10 && in_quad_bl) |
                      (obj_quadrant == 2'b11 && in_quad_br);

// edge of active quadrant (2 px border)
wire near_h_edge = (H_Cont <= 16'd163) | (H_Cont >= 16'd798) |
                   (H_Cont >= 16'd479 && H_Cont <= 16'd483);
wire near_v_edge = (V_Cont <= 16'd048) | (V_Cont >= 16'd523) |
                   (V_Cont >= 16'd284 && V_Cont <= 16'd288);
wire quad_border = VGA_BLANK_N & obj_detected & in_active_quad &
                   (near_h_edge | near_v_edge);

// base video (edge mode or camera mode)
wire [7:0] base_r = SW[0] ? edge_r : VGA_R_unfilt;
wire [7:0] base_g = SW[0] ? edge_g : VGA_G_unfilt;
wire [7:0] base_b = SW[0] ? edge_b : VGA_B_unfilt;

// final output with overlay
assign VGA_R = ~VGA_BLANK_N ? 8'h00 :
               quad_border   ? 8'h00 :
               is_crosshair  ? 8'h00 :
                               base_r;

assign VGA_G = ~VGA_BLANK_N ? 8'h00 :
               quad_border   ? 8'hFF :
               is_crosshair  ? 8'hFF :
                               base_g;

assign VGA_B = ~VGA_BLANK_N ? 8'h00 :
               quad_border   ? 8'h00 :
               is_crosshair  ? 8'h00 :
                               base_b;

//=======================================================
//  HEX displays
//=======================================================
// HEX1-HEX0: frame rate (existing)
FpsMonitor uFps2(
	  .clk50    ( CLOCK2_50 ),
	  .vs       ( VGA_VS ),
	  .fps      ( ),
	  .hex_fps_h( HEX1 ),
	  .hex_fps_l( HEX0 )
);

// HEX3-HEX2: detection threshold (hex)
SEG7_LUT h2( .iDIG( detect_thresh[3:0] ), .oSEG( HEX2 ) );
SEG7_LUT h3( .iDIG( detect_thresh[7:4] ), .oSEG( HEX3 ) );

// HEX4: detected quadrant (0=TL,1=TR,2=BL,3=BR), blank if none
wire [6:0] quad_seg;
SEG7_LUT h4( .iDIG( {2'b00, obj_quadrant} ), .oSEG( quad_seg ) );
assign HEX4 = obj_detected ? quad_seg : 7'h7F;

// HEX5: audio mode indicator ("1" = line-in FX, "2" = musical notes)
wire [6:0] hex5_mode1, hex5_mode2;
SEG7_LUT h5a( .iDIG( 4'd1 ), .oSEG( hex5_mode1 ) );
SEG7_LUT h5b( .iDIG( 4'd2 ), .oSEG( hex5_mode2 ) );
assign HEX5 = audio_mode ? hex5_mode2 : hex5_mode1;

//--FREQUENCY TEST--
CLOCKMEM ck1 ( .CLK(VGA_CLK_25M    ), .CLK_FREQ(25000000), .CK_1HZ(D8M_CK_HZ)  );
CLOCKMEM ck2 ( .CLK(MIPI_REFCLK    ), .CLK_FREQ(20000000), .CK_1HZ(D8M_CK_HZ2) );
CLOCKMEM ck3 ( .CLK(MIPI_PIXEL_CLK_), .CLK_FREQ(25000000), .CK_1HZ(D8M_CK_HZ3) );

// debug: max edge count across quadrants (top 5 bits -> LED[4:0])
wire [19:0] dbg_max_a = (cnt_tl >= cnt_tr) ? cnt_tl : cnt_tr;
wire [19:0] dbg_max_b = (cnt_bl >= cnt_br) ? cnt_bl : cnt_br;
wire [19:0] dbg_max   = (dbg_max_a >= dbg_max_b) ? dbg_max_a : dbg_max_b;

//--LED STATUS-----
assign LEDR[9:0] = {
    audio_mode,       // [9] audio mode (0=FX, 1=notes)
    obj_detected,     // [8] object detected
    obj_quadrant,     // [7:6] detected quadrant
    audio_cfg_done,   // [5] audio codec configured
    dbg_max[19:15]    // [4:0] top 5 bits of max edge count (debug)
};

endmodule
