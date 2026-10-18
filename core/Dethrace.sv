//============================================================================
//
//  Dethrace (Carmageddon) hybrid core for MiSTer
//
//  The game itself runs on the HPS. This core scans the game's
//  framebuffer out of DDR3 with native 15kHz timings, plays its audio and
//  hands input to the HPS. See ../hybrid/rtl/hybrid_host.sv for the shared
//  memory layout and ../hybrid/README.md for what all hybrid cores share.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_SCALER  = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
assign AUDIO_MIX = status[6:5];

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

// Status bits [127:0] are forwarded to the HPS side. Bits [23:0] mean the same
// in every hybrid core (MH_OSD_* in hybrid/hps/mister_hybrid.h), game options
// start at bit 24 (decoded in dethrace/src/harness/platforms/mister_fpga.h). Defaults are 0.
// The order of the options is the one in hybrid/README.md, "OSD".
`include "build_id.v"
localparam CONF_STR = {
	"Dethrace;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[125:123],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
	"O[4:2],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	// Not with direct_video (the HDMI output is the analog one then), and
	// the CRT options not with forced_scandoubler: a VGA monitor has its own
	// bit 1: bit 0 is the reset Main_MiSTer holds while it loads the core and
	// clears after, so an option there was never kept (up to host version 12)
	"H5O[1],HDMI Only,No,Yes;",
	"H4P1,CRT Options;",
	"P1-;",
	// Horizontal Size: entries 0..7 are 0..+7, entries 8..31 are -24..-1
	"P1O[68:64],Horizontal Size,0,+1,+2,+3,+4,+5,+6,+7,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[72:69],Horizontal Pos,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[76:73],Vertical Pos,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	// The HUD margins (MH_HudMargins(), hybrid/README.md "HUD margins"): how
	// far the instruments at the top and at the bottom of a race in 320x240
	// are from the edges, entry 0 is 10, the default. Greyed out (menu mask
	// bit 0) while races are not in 320x240.
	"P1-;",
	"D0P1O[81:77],HUD (Top),10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,0,1,2,3,4,5,6,7,8,9;",
	"D0P1O[86:82],HUD (Bottom),10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,0,1,2,3,4,5,6,7,8,9;",
	"O[6:5],Stereo Mix,None,25%,50%,100%;",
	// drawn by the hybrid library over the game's frames (MH_OSD_FPS)
	"O[15],FPS Counter,Off,On;",
	"-;",
	"O[10:7],Sound Volume,100%,90%,80%,70%,60%,50%,40%,30%,20%,10%,0%;",
	"O[14:11],Music Volume,100%,90%,80%,70%,60%,50%,40%,30%,20%,10%,0%;",
	// the game's options, read in dethrace/src/harness/platforms/mister.c
	"O[27],Resolution,320x200,320x240;",
	"O[25:24],Renderer,Optimized,Fast,Original;",
	"O[26],Lock to 30 FPS,Off,On;",
	"O[28],Cutscenes,On,Off;",
	// the gamepad's rumble when the car is hit (and the analog gas and brake
	// on the right and left triggers, which need no option)
	"O[30],Rumble,On,Off;",
	// Cheats: Invulnerability holds until switched off; the triggers (T, bits
	// 56..59, MH_OSDTriggers()) do their thing once each time, in a race
	"P2,Cheats;",
	"P2-;",
	"P2O[29],Invulnerability,Off,On;",
	"P2T[56],Instant Repair;",
	"P2T[57],Extra Credits;",
	"P2T[58],Finish Lap;",
	"-;",
	// Bits 16..23 were Menu OK / Menu Back up to host version 13: unused, a
	// saved setting may still have them set.
	// MiSTer's default map only knows the SNES-style pad. Main refuses to map a
	// button twice, so Menu OK/Back here are for spare buttons without a game
	// function and unmapped by default; menus also confirm and go back with
	// the MiSTer menu's own OK / Back (MH_MenuButtons()). The game knows this list as the JOY_*
	// bits of dethrace/src/harness/platforms/mister_input.c (Pratcam after
	// Menu OK/Back, without a default button); the launcher repeats "jn" as
	// MISTER_HYBRID_JN (package/games/Dethrace/danik_hybrid_launch.sh).
	"J1,Accelerate,Brake,Handbrake,Change View,Repair,Recover,Map,Pause,Menu OK,Menu Back,Pratcam;",
	"jn,B,Y,A,X,L,Select,R,Start;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire         direct_video;
wire   [3:0] menumask;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [24:0] ps2_mouse;
wire  [15:0] ps2_mouse_ext;
wire  [31:0] joystick_0, joystick_1;
wire  [15:0] joy_l_analog_0, joy_r_analog_0, joy_l_analog_1, joy_r_analog_1;
wire  [21:0] gamma_bus;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask({10'd0, direct_video, forced_scandoubler, menumask}),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_l_analog_0(joy_l_analog_0),
	.joystick_r_analog_0(joy_r_analog_0),
	.joystick_l_analog_1(joy_l_analog_1),
	.joystick_r_analog_1(joy_r_analog_1),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

wire reset = RESET | buttons[1];

//////////////////////////////////////////////////////////////////

// The video modes of 640x400 and 640x480 have two forms (hybrid_host.sv):
// interlaced at 15kHz for a 15kHz screen, progressive at 31kHz for
// everything else, the core's own picture without a game as well. A 15kHz
// screen must never get the second, so it takes the player to say that none
// is there: forced_scandoubler=1 in MiSTer.ini (the analog output is a VGA
// monitor) or the option "HDMI Only", with which the analog output is
// switched off for as long as such a signal is on it. Modes of 15kHz still
// go to the analog output with "HDMI Only", and so does the OSD over them.
// With direct_video the HDMI output feeds an analog screen: no "HDMI Only".
wire       hdmi_only = status[1] & ~direct_video;
wire       vga31 = forced_scandoubler | hdmi_only;

wire       clk_vid;
wire       ce_pix;
wire [7:0] r, g, b;
wire       hsync, vsync, hblank, vblank;
wire       hires, fast, f1;

// `fast` follows vga31, and falls only after the output has gone quiet
assign VGA_DISABLE = fast & ~forced_scandoubler;

hybrid_host host
(
	.clk(clk_sys),
	.reset(reset),
	.refclk(CLK_50M),

	.ddr_busy(DDRAM_BUSY),
	.ddr_burstcnt(DDRAM_BURSTCNT),
	.ddr_addr(DDRAM_ADDR),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY),
	.ddr_rd(DDRAM_RD),
	.ddr_din(DDRAM_DIN),
	.ddr_be(DDRAM_BE),
	.ddr_we(DDRAM_WE),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joy_l_analog_0(joy_l_analog_0),
	.joy_r_analog_0(joy_r_analog_0),
	.joy_l_analog_1(joy_l_analog_1),
	.joy_r_analog_1(joy_r_analog_1),
	.osd_status(status),
	.osd_open(OSD_STATUS),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext),

	.clk_vid(clk_vid),
	.ce_pix(ce_pix),
	.r(r),
	.g(g),
	.b(b),
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank),
	.vga31(vga31),
	// CRT options: for 15kHz screens
	.crt_hsize(forced_scandoubler ? 6'd0 : {|status[68:67], status[68:64]}),
	.crt_hpos(forced_scandoubler ? 4'd0 : status[72:69]),
	.crt_vpos(forced_scandoubler ? 4'd0 : status[76:73]),
	.hires(hires),
	.fast(fast),
	.f1(f1),
	.menumask(menumask),

	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R)
);

assign DDRAM_CLK = clk_sys;

//////////////////////////////////////////////////////////////////
// Video output, on hybrid_host's video clock. The native signal is 15kHz, in
// the video mode the game set (320x200 unless it asks hybrid_host for
// another); video_mixer scandoubles it for VGA monitors (forced_scandoubler)
// or when a scandoubler effect is selected, which is why its line buffer has
// room for the 640 pixels of the widest 15kHz mode. Analog output is
// untouched otherwise so CRTs get the real 15kHz signal. HDMI goes through
// the framework's scaler; video_freak gives it the aspect ratio and the
// integer scaling modes. The modes of 640x400 and above are not scandoubled
// (hires): interlaced, the scaler weaves the two fields (VGA_F1).

wire [1:0] ar = status[122:121];
wire [2:0] scale = status[4:2];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
wire       vga_de;

assign CLK_VIDEO = clk_vid;
assign VGA_SL = sl[1:0];
assign VGA_F1 = f1;

video_mixer #(.LINE_LENGTH(640), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix),

	.scandoubler(~hires & (scale || forced_scandoubler)),
	.hq2x(scale == 1),
	.gamma_bus(gamma_bus),

	.R(r),
	.G(g),
	.B(b),

	.HSync(hsync),
	.VSync(vsync),
	.HBlank(hblank),
	.VBlank(vblank),

	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de)
);

video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),

	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[125:123])
);

endmodule
