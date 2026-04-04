module VGA_Controller_trig(
    input     [15:0] H_Cont,
    input     [15:0] V_Cont,
    input       [7:0] iRed,
    input       [7:0] iGreen,
    input       [7:0] iBlue,
    output      [7:0] oVGA_R,
    output      [7:0] oVGA_G,
    output      [7:0] oVGA_B,
    output            oVGA_H_SYNC,
    output            oVGA_V_SYNC,
    output            oVGA_SYNC,
    output            oVGA_BLANK,
    output            READ_Request, 
    
    // Control Signal
    input             iCLK,
    input             iRST_N,
    output            oVGA_CLOCK
);

parameter V_MARK = 9; 
`include "VGA_Param.h"

//=============================================================================
// REG/WIRE declarations
//=============================================================================
wire    [7:0]   mVGA_R;
wire    [7:0]   mVGA_G;
wire    [7:0]   mVGA_B;
wire            mVGA_H_SYNC;
wire            mVGA_V_SYNC;

//=======================================================
// Structural coding
//=======================================================   

// VGA DAC Connections
assign oVGA_R     = mVGA_R;
assign oVGA_G     = mVGA_G;
assign oVGA_B     = mVGA_B;
assign oVGA_SYNC  = 1'b0; // No Sync-on-Green
assign oVGA_CLOCK = iCLK;

// IMPORTANT: Inverting syncs for standard VGA-to-HDMI compatibility
assign oVGA_H_SYNC = ~mVGA_H_SYNC;
assign oVGA_V_SYNC = ~mVGA_V_SYNC;

// Read Request Logic (Requesting pixels from the Camera/Buffer)
assign READ_Request = (
    (H_Cont > H_BLANK && H_Cont < H_SYNC_TOTAL) &&
    (V_Cont > V_BLANK + V_MARK && V_Cont < V_SYNC_TOTAL)
); 

// Blanking logic: High during active video, Low during porches/sync
assign oVGA_BLANK = ~((H_Cont < H_BLANK ) || ( V_Cont < V_BLANK ));

// Sync Pulse Generation (Active High internally, inverted at output)
assign mVGA_H_SYNC = (H_Cont < H_SYNC_CYC) ? 1'b1 : 1'b0;
assign mVGA_V_SYNC = (V_Cont < V_SYNC_CYC) ? 1'b1 : 1'b0;

// Color Output Logic
assign mVGA_R = (oVGA_BLANK) ? iRed   : 8'h00;
assign mVGA_G = (oVGA_BLANK) ? iGreen : 8'h00;
assign mVGA_B = (oVGA_BLANK) ? iBlue  : 8'h00;

endmodule