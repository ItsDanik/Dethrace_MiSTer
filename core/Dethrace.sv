//============================================================================
//
//  Dethrace (Carmageddon) hybrid core for MiSTer
//
//  The game itself runs on the HPS. This core scans the game's paletted
//  framebuffer out of DDR3 with native 15kHz timings and hands input to
//  the HPS. See ../hybrid/rtl/hybrid_host.sv for the shared memory layout
//  and ../hybrid/README.md for what all hybrid cores share.
//
//  The triangle rasteriser (rtl/dethrace_rast_top.sv) draws into DDR3 from
//  commands the game writes to a ring. It shares the DDR3 port with the
//  host module through rtl/dethrace_ddr_arb.sv.
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

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

// Status bits [63:0] are forwarded to the HPS side, keep game options there
// (decoded in dethrace/src/harness/platforms/mister_fpga.h). Defaults are 0.
`include "build_id.v"
localparam CONF_STR = {
	"Dethrace;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[4:2],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	// Not with direct_video (the HDMI output is the analog one then), and
	// the CRT options not with forced_scandoubler: a VGA monitor has its own
	"H5O[0],HDMI Only,No,Yes;",
	"H4P1,CRT Options;",
	"P1-;",
	// Horizontal Size: entries 0..7 are 0..+7, entries 8..31 are -24..-1
	"P1O[68:64],Horizontal Size,0,+1,+2,+3,+4,+5,+6,+7,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[72:69],Horizontal Pos,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[76:73],Vertical Pos,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"O[6:5],Stereo Mix,None,25%,50%,100%;",
	"-;",
	"O[10:7],Sound Volume,100%,90%,80%,70%,60%,50%,40%,30%,20%,10%,0%;",
	"O[14:11],Music Volume,100%,90%,80%,70%,60%,50%,40%,30%,20%,10%,0%;",
	"O[27],Resolution,320x200,320x240;",
	"O[25:24],Renderer,Optimized,Fast,Original;",
	"O[26],Lock to 30 FPS,Off,On;",
	"O[28],Cutscenes,On,Off;",
	"-;",
	"O[19:16],Menu OK,MiSTer,A,B,X,Y,L,R,Select,Start;",
	"O[23:20],Menu Back,MiSTer,A,B,X,Y,L,R,Select,Start;",
	"-;",
	// MiSTer's default map only knows the SNES-style pad (no triggers). Main refuses
	// to map a button twice, so Menu OK/Back here are for spare buttons without a
	// race function and unmapped by default; the OSD Menu OK/Back options cover
	// buttons that have one (mister_joymap.c, which mirrors this "jn" list).
	// Pratcam is unmapped by default as well, and last: mappings made before it
	// was added stay valid.
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

// The video modes of 640x400 and above have two forms (hybrid_host.sv):
// interlaced at 15kHz for a 15kHz screen, progressive at 31kHz and more for
// everything else; 800x600 and 1024x768 only exist in the second. A 15kHz
// screen must never get the second, so it takes the player to say that none
// is there: forced_scandoubler=1 in MiSTer.ini (the analog output is a VGA
// monitor) or the option "HDMI Only", with which the analog output is
// switched off for as long as such a signal is on it. Modes of 15kHz still
// go to the analog output with "HDMI Only", and so does the OSD over them.
// With direct_video the HDMI output feeds an analog screen: no "HDMI Only".
wire       hdmi_only = status[0] & ~direct_video;
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

	.ddr_busy(h_busy),
	.ddr_burstcnt(h_burstcnt),
	.ddr_addr(h_addr),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(h_dout_ready),
	.ddr_rd(h_rd),
	.ddr_din(h_din),
	.ddr_be(h_be),
	.ddr_we(h_we),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joy_l_analog_0(joy_l_analog_0),
	.joy_r_analog_0(joy_r_analog_0),
	.joy_l_analog_1(joy_l_analog_1),
	.joy_r_analog_1(joy_r_analog_1),
	.osd_status(status[63:0]),
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
// Rasteriser and the DDR3 port shared with it

wire        h_busy, h_dout_ready, h_rd, h_we;
wire  [7:0] h_burstcnt, h_be;
wire [28:0] h_addr;
wire [63:0] h_din;
wire        r_busy, r_dout_ready, r_rd, r_we;
wire  [7:0] r_burstcnt, r_be;
wire [28:0] r_addr;
wire [63:0] r_din;
wire        f_busy, f_dout_ready, f_rd, f_we;
wire  [7:0] f_burstcnt, f_be;
wire [28:0] f_addr;
wire [63:0] f_din;

dethrace_ddr_arb ddr_arb
(
	.clk(clk_sys),
	.reset(reset),

	.ddr_busy(DDRAM_BUSY),
	.ddr_burstcnt(DDRAM_BURSTCNT),
	.ddr_addr(DDRAM_ADDR),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY),
	.ddr_rd(DDRAM_RD),
	.ddr_din(DDRAM_DIN),
	.ddr_be(DDRAM_BE),
	.ddr_we(DDRAM_WE),

	.c0_busy(h_busy), .c0_burstcnt(h_burstcnt), .c0_addr(h_addr), .c0_dout_ready(h_dout_ready),
	.c0_rd(h_rd), .c0_din(h_din), .c0_be(h_be), .c0_we(h_we),
	.c1_busy(r_busy), .c1_burstcnt(r_burstcnt), .c1_addr(r_addr), .c1_dout_ready(r_dout_ready),
	.c1_rd(r_rd), .c1_din(r_din), .c1_be(r_be), .c1_we(r_we),
	.c2_busy(f_busy), .c2_burstcnt(f_burstcnt), .c2_addr(f_addr), .c2_dout_ready(f_dout_ready),
	.c2_rd(f_rd), .c2_din(f_din), .c2_be(f_be), .c2_we(f_we)
);

dethrace_rast_top rast
(
	.clk(clk_sys),
	.reset(reset),
	.mem_dout(DDRAM_DOUT),

	.r_busy(r_busy), .r_burstcnt(r_burstcnt), .r_addr(r_addr), .r_dout_ready(r_dout_ready),
	.r_rd(r_rd), .r_din(r_din), .r_be(r_be), .r_we(r_we),
	.f_busy(f_busy), .f_burstcnt(f_burstcnt), .f_addr(f_addr), .f_dout_ready(f_dout_ready),
	.f_rd(f_rd), .f_din(f_din), .f_be(f_be), .f_we(f_we)
);

//////////////////////////////////////////////////////////////////
// Video output, on hybrid_host's video clock. The game uses 320x200 and,
// with the option "Resolution", 320x240 for the races.
// The native signal is 15kHz; video_mixer scandoubles it
// for VGA monitors (forced_scandoubler) or when a scandoubler effect is
// selected. Analog output is untouched otherwise so CRTs get the real
// 15kHz signal.

wire [2:0] scale = status[4:2];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign CLK_VIDEO = clk_vid;
assign VGA_SL = sl[1:0];
assign VGA_F1 = f1;

video_mixer #(.LINE_LENGTH(320), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
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
	.VGA_DE(VGA_DE)
);

endmodule
