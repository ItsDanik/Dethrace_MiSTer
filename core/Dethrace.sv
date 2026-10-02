//============================================================================
//
//  Dethrace (Carmageddon) hybrid core for MiSTer
//
//  The game itself runs on the HPS. This core scans the game's paletted
//  framebuffer out of DDR3 with native 15kHz timings and hands input to
//  the HPS. See rtl/dethrace_host.sv for the shared memory layout.
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
assign VGA_DISABLE = 0;
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
	"O[6:5],Stereo Mix,None,25%,50%,100%;",
	"-;",
	"O[10:7],Sound Volume,100%,90%,80%,70%,60%,50%,40%,30%,20%,10%,0%;",
	"O[14:11],Music Volume,100%,90%,80%,70%,60%,50%,40%,30%,20%,10%,0%;",
	"O[15],Renderer,Optimized,Original;",
	"-;",
	"J1,Accelerate,Brake,Handbrake,Change View,Repair,Recover,Map,Pause;",
	"jn,A,B,X,Y,R,L,Select,Start;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
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

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

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

wire       ce_pix;
wire [7:0] r, g, b;
wire       hsync, vsync, hblank, vblank;

dethrace_host host
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

	.ce_pix(ce_pix),
	.r(r),
	.g(g),
	.b(b),
	.hsync(hsync),
	.vsync(vsync),
	.hblank(hblank),
	.vblank(vblank),

	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R)
);

assign DDRAM_CLK = clk_sys;

//////////////////////////////////////////////////////////////////
// Video output. The native signal is 15kHz; video_mixer scandoubles it
// for VGA monitors (forced_scandoubler) or when a scandoubler effect is
// selected. Analog output is untouched otherwise so CRTs get the real
// 15kHz signal.

wire [2:0] scale = status[4:2];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign CLK_VIDEO = clk_sys;
assign VGA_SL = sl[1:0];
assign VGA_F1 = 0;

video_mixer #(.LINE_LENGTH(320), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(ce_pix),

	.scandoubler(scale || forced_scandoubler),
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
