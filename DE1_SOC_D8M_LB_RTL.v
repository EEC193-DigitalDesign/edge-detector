//=======================================================
//  DE10-SoC / D8M upgraded edge detector top-level
//  Drop-in replacement for your existing top file
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

// -------- switch map --------
// SW[0] = 1 enable edge path, 0 show normal camera
// SW[1] = 1 overlay edges on original image, 0 show edge-only
// SW[2] = 1 enable Gaussian blur, 0 bypass blur
// SW[3] = autofocus assist mode (preserved from your original top)
// SW[4] = 1 use focus-adjusted video as edge input, 0 use raw camera RGB
// SW[5] = threshold bit 0
// SW[6] = threshold bit 1
// SW[7] = threshold bit 2
// SW[8] = threshold bit 3
// SW[9] = 1 edge polarity white-on-black, 0 black-on-white
wire [7:0] edge_threshold;
assign edge_threshold = {4'b0000, SW[8:5]} << 4;   // 0,16,32,...,240

wire [7:0] edge_src_r = SW[4] ? VGA_R_unfilt : VGA_R_A;
wire [7:0] edge_src_g = SW[4] ? VGA_G_unfilt : VGA_G_A;
wire [7:0] edge_src_b = SW[4] ? VGA_B_unfilt : VGA_B_A;

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
     .AUTO_FOC      ( KEY[3] & AUTO_FOC ),
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

// Output select
assign VGA_R = VGA_BLANK_N ? (SW[0] ? edge_r : VGA_R_unfilt) : 8'h00;
assign VGA_G = VGA_BLANK_N ? (SW[0] ? edge_g : VGA_G_unfilt) : 8'h00;
assign VGA_B = VGA_BLANK_N ? (SW[0] ? edge_b : VGA_B_unfilt) : 8'h00;

//--Frame Counter --
FpsMonitor uFps2(
	  .clk50    ( CLOCK2_50 ),
	  .vs       ( VGA_VS ),
	  .fps      ( ),
	  .hex_fps_h( HEX1 ),
	  .hex_fps_l( HEX0 )
);

assign HEX2 = 7'h7F;
assign HEX3 = 7'h7F;
assign HEX4 = 7'h7F;
assign HEX5 = 7'h7F;

//--FREQUENCY TEST--
CLOCKMEM ck1 ( .CLK(VGA_CLK_25M    ), .CLK_FREQ(25000000), .CK_1HZ(D8M_CK_HZ)  );
CLOCKMEM ck2 ( .CLK(MIPI_REFCLK    ), .CLK_FREQ(20000000), .CK_1HZ(D8M_CK_HZ2) );
CLOCKMEM ck3 ( .CLK(MIPI_PIXEL_CLK_), .CLK_FREQ(25000000), .CK_1HZ(D8M_CK_HZ3) );

//--LED STATUS-----
assign LEDR[9:0] = {
    SW[0],        // edge enabled
    SW[1],        // overlay mode
    SW[2],        // blur mode
    SW[4],        // source select
    SW[9],        // polarity
    1'b0,
    CAMERA_MIPI_RELAESE,
    MIPI_BRIDGE_RELEASE,
    D8M_CK_HZ,
    D8M_CK_HZ3
};

endmodule
