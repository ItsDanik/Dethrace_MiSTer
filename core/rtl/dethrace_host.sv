//============================================================================
//
//  Dethrace hybrid core - HPS <-> FPGA bridge
//
//  The game runs on the HPS (ARM). It renders 8bpp paletted frames into
//  DDR3 and this module scans them out with native 15kHz timings. Input
//  state is published back to the HPS through the same memory.
//
//  Shared memory layout (physical address 0x30000000 + offset):
//    0x000000  control (HPS -> FPGA), 2 x 64-bit words
//              w0[31:0]  magic "DETH" (0x48544544)
//              w0[39:32] framebuffer index to display (0..2)
//              w0[40]    reserved (was video mode)
//              w0[48]    palette slot (0..1)
//              w0[56]    audio enable
//              w1[31:0]  palette sequence number (reload when changed)
//    0x000040  status (FPGA -> HPS), 16 x 64-bit words, written every vblank
//              w0  {frame counter, magic "DTHS" (0x53485444)}
//              w1  {version, 21'b0, ctrl_valid, 2'b0, 6'b0, fb_index[1:0]}
//              w2  {joystick_1, joystick_0}
//              w3  {r_analog_1, l_analog_1, r_analog_0, l_analog_0}
//              w4  OSD status[63:0]
//              w5  {mouse y accumulator, mouse x accumulator}
//              w6  {wheel accumulator[15:0], 13'b0, mouse buttons[2:0]}
//              w7  reserved
//              w8..w15 keyboard bitmap, bit index = {extended, PS/2 set 2 code}
//    0x0000C0  audio fetch pointer (FPGA -> HPS), 32-bit count of stereo
//              frames read from the ring, written after every audio fetch
//    0x001000  palette slot 0: 256 x 32-bit 0x00RRGGBB
//    0x001400  palette slot 1
//    0x010000  audio ring: 16384 stereo frames, 16-bit signed {R, L}, 44.1kHz
//    0x100000  framebuffer 0 (row stride = width)
//    0x200000  framebuffer 1
//    0x300000  framebuffer 2
//
//============================================================================

module dethrace_host
(
	input             clk,
	input             reset,

	// DDR3 via the MiSTer framework (Avalon-MM, 64 bit, address in 8-byte units)
	input             ddr_busy,
	output reg  [7:0] ddr_burstcnt,
	output reg [28:0] ddr_addr,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	output reg        ddr_rd,
	output reg [63:0] ddr_din,
	output      [7:0] ddr_be,
	output reg        ddr_we,

	// input state published to the HPS
	input      [31:0] joystick_0,
	input      [31:0] joystick_1,
	input      [15:0] joy_l_analog_0,
	input      [15:0] joy_r_analog_0,
	input      [15:0] joy_l_analog_1,
	input      [15:0] joy_r_analog_1,
	input      [63:0] osd_status,
	input      [10:0] ps2_key,
	input      [24:0] ps2_mouse,
	input      [15:0] ps2_mouse_ext,

	// video out, one clk_sys domain, 1 pixel = ce_pix
	output reg        ce_pix,
	output reg  [7:0] r,
	output reg  [7:0] g,
	output reg  [7:0] b,
	output reg        hsync,
	output reg        vsync,
	output reg        hblank,
	output reg        vblank,

	// audio, 44.1kHz signed
	output reg [15:0] audio_l,
	output reg [15:0] audio_r
);

localparam [31:0] CTRL_MAGIC   = 32'h48544544; // "DETH"
localparam [31:0] STATUS_MAGIC = 32'h53485444; // "DTHS"
localparam [31:0] VERSION      = 32'd1;

localparam [28:0] BASE       = 29'h06000000;   // 0x30000000 >> 3
localparam [28:0] CTRL_ADDR  = BASE;
localparam [28:0] STAT_ADDR  = BASE + 29'h8;
localparam [28:0] PAL_ADDR   = BASE + 29'h200;
localparam [28:0] FB_ADDR    = BASE + 29'h20000;
localparam [28:0] AUD_ADDR   = BASE + 29'h2000;   // ring, 8192 words
localparam [28:0] AUD_PTR    = BASE + 29'h18;
localparam  [7:0] AUD_BURST  = 8'd16;             // 32 frames
localparam  [7:0] LINE_BURST = 8'd40;          // 320 bytes

assign ddr_be = 8'hFF;

//////////////////////////////////////////////////////////////////
// Video timing
//
// 320x200 progressive. 50MHz/8 = 6.25MHz pixel clock, 400 x 262 lines
// -> 15.625kHz / 59.6Hz. Line and frame counters run on the pixel enable.

localparam [9:0] H_TOTAL  = 10'd400;
localparam [9:0] H_ACTIVE = 10'd320;
localparam [9:0] HS_START = 10'd336;
localparam [9:0] HS_END   = 10'd368;
localparam [9:0] V_TOTAL  = 10'd262;
localparam [9:0] V_ACTIVE = 10'd200;
localparam [9:0] VS_START = 10'd228;
localparam [9:0] VS_END   = 10'd231;

reg  [2:0] ce_div = 0;
reg  [9:0] hc = 0;
reg  [9:0] vc = 0;

wire       ce = (ce_div == 3'd7);
wire       line_start = ce && (hc == H_TOTAL - 1'd1);   // next ce begins a new line
wire [9:0] next_vc  = (vc == V_TOTAL - 1'd1) ? 10'd0 : vc + 1'd1;
wire [9:0] next2_vc = (next_vc == V_TOTAL - 1'd1) ? 10'd0 : next_vc + 1'd1;

// vblank tasks start at the first blank line
wire       vbl_start = line_start && (next_vc == V_ACTIVE);

always @(posedge clk) begin
	ce_div <= ce_div + 1'd1;
	if (ce) begin
		if (hc == H_TOTAL - 1'd1) begin
			hc <= 0;
			vc <= next_vc;
		end else begin
			hc <= hc + 1'd1;
		end
	end
end

//////////////////////////////////////////////////////////////////
// Control state (latched from DDR during vblank)

reg        ctrl_valid = 0;
reg        audio_en = 0;
reg  [1:0] fb_index = 0;
reg [31:0] pal_seq = 0;
reg        pal_loaded = 0;
reg [31:0] frame_cnt = 0;

reg [63:0] ctrl_w0, ctrl_w1;

//////////////////////////////////////////////////////////////////
// Memories

// line buffer: two banks of up to 128 x 64-bit words
reg [63:0] lbuf[0:255];
reg  [7:0] lbuf_waddr;
reg        lbuf_we;
reg [63:0] lbuf_wdata;
reg [63:0] lbuf_q;
always @(posedge clk) begin
	if (lbuf_we) lbuf[lbuf_waddr] <= lbuf_wdata;
	lbuf_q <= lbuf[{vc[0], hc[9:3]}];
end

// palette: 128 x 64-bit words, two 0x00RRGGBB entries per word
reg [63:0] pal[0:127];
reg  [6:0] pal_waddr;
reg        pal_we;
reg [63:0] pal_wdata;
reg [63:0] pal_q;
reg  [2:0] byte_sel;
reg        pal_hi;
wire [7:0] pix_index = lbuf_q[{byte_sel, 3'b0} +: 8];
always @(posedge clk) begin
	if (pal_we) pal[pal_waddr] <= pal_wdata;
	pal_q  <= pal[pix_index[7:1]];
	pal_hi <= pix_index[0];
end

//////////////////////////////////////////////////////////////////
// Audio
//
// 64 word FIFO (128 frames) refilled from the DDR ring in bursts of 16
// words. Samples leave at exactly 44.1kHz: 50MHz * 441 / 500000. The game's
// sound effects (11/22kHz) and CD music (44.1kHz) all share that clock family.

reg [63:0] afifo[0:63];
reg  [6:0] afifo_wr = 0;      // one extra bit for full/empty
reg  [6:0] afifo_rd = 0;
reg        afifo_we;
reg [63:0] afifo_wdata;
reg [63:0] afifo_q;
reg [31:0] aud_fetch = 0;     // frames fetched from the ring
reg        aud_half = 0;
reg [18:0] aud_acc = 0;
reg        aud_tick = 0;
reg        aud_tick2 = 0;

wire [6:0] afifo_level = afifo_wr - afifo_rd;

always @(posedge clk) begin
	if (afifo_we) begin
		afifo[afifo_wr[5:0]] <= afifo_wdata;
		afifo_wr <= afifo_wr + 1'd1;
	end
	afifo_q <= afifo[afifo_rd[5:0]];
end

always @(posedge clk) begin
	aud_tick <= 0;
	if (aud_acc + 19'd441 >= 19'd500000) begin
		aud_acc  <= aud_acc + 19'd441 - 19'd500000;
		aud_tick <= 1;
	end else begin
		aud_acc <= aud_acc + 19'd441;
	end

	// afifo_q is valid one clock after afifo_rd changes; ticks are ~1134 clocks apart
	aud_tick2 <= aud_tick;
	if (aud_tick2) begin
		if (!audio_en) begin
			audio_l <= 0;
			audio_r <= 0;
			aud_half <= 0;
		end else if (afifo_level != 0) begin
			{audio_r, audio_l} <= aud_half ? afifo_q[63:32] : afifo_q[31:0];
			aud_half <= ~aud_half;
			if (aud_half) afifo_rd <= afifo_rd + 1'd1;
		end
		// on underrun the last sample is held
	end

	if (!audio_en) afifo_rd <= afifo_wr;
end

//////////////////////////////////////////////////////////////////
// Input state

reg [511:0] keys = 0;
reg         old_key_stb = 0;
reg  [31:0] mouse_x = 0, mouse_y = 0;
reg  [15:0] mouse_wheel = 0;
reg   [2:0] mouse_btn = 0;
reg         old_mouse_stb = 0;

always @(posedge clk) begin
	old_key_stb <= ps2_key[10];
	if (old_key_stb != ps2_key[10]) keys[{ps2_key[8], ps2_key[7:0]}] <= ps2_key[9];

	old_mouse_stb <= ps2_mouse[24];
	if (old_mouse_stb != ps2_mouse[24]) begin
		mouse_x     <= mouse_x + {{23{ps2_mouse[4]}}, ps2_mouse[15:8]};
		mouse_y     <= mouse_y + {{23{ps2_mouse[5]}}, ps2_mouse[23:16]};
		mouse_wheel <= mouse_wheel + {{8{ps2_mouse_ext[7]}}, ps2_mouse_ext[7:0]};
		mouse_btn   <= ps2_mouse[2:0];
	end

	if (reset) keys <= 0;
end

//////////////////////////////////////////////////////////////////
// DDR engine

localparam S_IDLE      = 0;
localparam S_CTRL      = 1;
localparam S_CTRL_WAIT = 2;
localparam S_PAL_WAIT  = 3;
localparam S_STAT      = 4;
localparam S_LINE_WAIT = 5;
localparam S_AUD_WAIT  = 6;
localparam S_AUD_PTR   = 7;

reg  [2:0] state = S_IDLE;
reg        line_req = 0;
reg        vbl_req = 0;
reg  [9:0] fetch_row;
reg        fetch_bank;
reg  [7:0] rd_cnt;          // beats received in the current burst
reg  [7:0] rd_len;          // beats expected in the current burst
reg  [7:0] line_words;      // words fetched so far for the current line
reg  [3:0] wr_beat;


// framebuffer address of a row: FB_ADDR + index * 0x20000 + row * 320 / 8
wire [28:0] row_addr = FB_ADDR + {10'd0, fb_index, 17'd0}
                     + {14'd0, fetch_row, 5'd0} + {16'd0, fetch_row, 3'd0};

reg [63:0] stat_word;
always @(*) begin
	case (wr_beat)
		4'd0:  stat_word = {frame_cnt, STATUS_MAGIC};
		4'd1:  stat_word = {VERSION, 21'd0, ctrl_valid, 2'd0, 6'd0, fb_index};
		4'd2:  stat_word = {joystick_1, joystick_0};
		4'd3:  stat_word = {joy_r_analog_1, joy_l_analog_1, joy_r_analog_0, joy_l_analog_0};
		4'd4:  stat_word = osd_status;
		4'd5:  stat_word = {mouse_y, mouse_x};
		4'd6:  stat_word = {32'd0, mouse_wheel, 13'd0, mouse_btn};
		4'd7:  stat_word = 64'd0;
		default: stat_word = keys[{wr_beat[2:0], 6'd0} +: 64];
	endcase
end

always @(posedge clk) begin
	lbuf_we <= 0;
	pal_we <= 0;
	afifo_we <= 0;

	// requests from the video timing: fetch the line after the one starting now
	if (line_start && next2_vc < V_ACTIVE) begin
		line_req   <= 1;
		fetch_row  <= next2_vc;
		fetch_bank <= next2_vc[0];
	end
	if (vbl_start) begin
		vbl_req   <= 1;
		frame_cnt <= frame_cnt + 1'd1;
	end

	// read data (Avalon readdatavalid is independent of waitrequest)
	if (ddr_dout_ready) begin
		rd_cnt <= rd_cnt + 1'd1;
		case (state)
			S_CTRL_WAIT: if (rd_cnt == 0) ctrl_w0 <= ddr_dout; else ctrl_w1 <= ddr_dout;
			S_PAL_WAIT: begin
				pal_we    <= 1;
				pal_waddr <= rd_cnt[6:0];
				pal_wdata <= ddr_dout;
			end
			S_AUD_WAIT: begin
				afifo_we    <= 1;
				afifo_wdata <= ddr_dout;
			end
			S_LINE_WAIT: begin
				lbuf_we    <= 1;
				lbuf_waddr <= {fetch_bank, line_words[6:0]};
				lbuf_wdata <= ddr_dout;
				line_words <= line_words + 1'd1;
			end
			default: ;
		endcase
	end

	if (!ddr_busy) begin
		ddr_rd <= 0;

		case (state)
			S_IDLE:
				if (line_req) begin
					line_req     <= 0;
					line_words   <= 0;
					rd_cnt       <= 0;
					rd_len       <= LINE_BURST;
					ddr_addr     <= row_addr;
					ddr_burstcnt <= LINE_BURST;
					ddr_rd       <= 1;
					state        <= S_LINE_WAIT;
				end
				else if (audio_en && afifo_level <= 7'd48) begin
					rd_cnt       <= 0;
					rd_len       <= AUD_BURST;
					ddr_addr     <= AUD_ADDR + {16'd0, aud_fetch[13:1]};
					ddr_burstcnt <= AUD_BURST;
					ddr_rd       <= 1;
					state        <= S_AUD_WAIT;
				end
				else if (vbl_req) begin
					vbl_req      <= 0;
					rd_cnt       <= 0;
					rd_len       <= 8'd2;
					ddr_addr     <= CTRL_ADDR;
					ddr_burstcnt <= 8'd2;
					ddr_rd       <= 1;
					state        <= S_CTRL_WAIT;
				end

			S_LINE_WAIT:
				if (rd_cnt == rd_len) state <= S_IDLE;

			S_AUD_WAIT:
				// wait for the FIFO write of the last beat as well
				if (rd_cnt == rd_len && !afifo_we) begin
					aud_fetch <= aud_fetch + 32'd32;
					state     <= S_AUD_PTR;
				end

			S_AUD_PTR:
				// publish the fetch pointer: single beat write
				if (!ddr_we) begin
					ddr_we       <= 1;
					ddr_addr     <= AUD_PTR;
					ddr_burstcnt <= 8'd1;
					ddr_din      <= {32'd0, aud_fetch};
				end else begin
					ddr_we <= 0;
					state  <= S_IDLE;
				end

			S_CTRL_WAIT:
				if (rd_cnt == rd_len) state <= S_CTRL;

			S_CTRL: begin
				ctrl_valid <= (ctrl_w0[31:0] == CTRL_MAGIC);
				audio_en <= (ctrl_w0[31:0] == CTRL_MAGIC) && ctrl_w0[56];
				if (ctrl_w0[31:0] == CTRL_MAGIC) begin
					fb_index <= (ctrl_w0[39:32] > 8'd2) ? 2'd0 : ctrl_w0[33:32];
				end
				if (ctrl_w0[31:0] == CTRL_MAGIC && (!pal_loaded || ctrl_w1[31:0] != pal_seq)) begin
					pal_loaded   <= 1;
					pal_seq      <= ctrl_w1[31:0];
					rd_cnt       <= 0;
					rd_len       <= 8'd128;
					ddr_addr     <= PAL_ADDR + (ctrl_w0[48] ? 29'h80 : 29'h0);
					ddr_burstcnt <= 8'd128;
					ddr_rd       <= 1;
					state        <= S_PAL_WAIT;
				end else begin
					state <= S_STAT;
					wr_beat <= 0;
				end
			end

			S_PAL_WAIT:
				if (rd_cnt == rd_len) begin
					state   <= S_STAT;
					wr_beat <= 0;
				end

			S_STAT: begin
				// write burst: first beat carries address and burst count
				if (!ddr_we) begin
					ddr_we       <= 1;
					ddr_addr     <= STAT_ADDR;
					ddr_burstcnt <= 8'd16;
					ddr_din      <= stat_word;
					wr_beat      <= 1;
				end else if (wr_beat == 0) begin
					// beat 15 accepted on the previous cycle
					ddr_we <= 0;
					state  <= S_IDLE;
				end else begin
					ddr_din <= stat_word;
					wr_beat <= wr_beat + 1'd1;
				end
			end

			default: state <= S_IDLE;
		endcase
	end

	if (reset) begin
		state      <= S_IDLE;
		ddr_rd     <= 0;
		ddr_we     <= 0;
		line_req   <= 0;
		vbl_req    <= 0;
		ctrl_valid <= 0;
		pal_loaded <= 0;
		audio_en   <= 0;
	end
	if (!audio_en) aud_fetch <= 0;
end

//////////////////////////////////////////////////////////////////
// Pixel pipeline
//
// ce edge E0: counters advance. E1: line buffer word read. E2: palette
// read. Next ce: RGB and syncs for the same pixel are registered.

wire active_now = (hc < H_ACTIVE) && (vc < V_ACTIVE);

always @(posedge clk) byte_sel <= hc[2:0];

// test pattern (colour bars) until the HPS side publishes a valid control block
wire [2:0] bar = hc[8:6];

always @(posedge clk) begin
	ce_pix <= ce;
	if (ce) begin
		hblank <= (hc >= H_ACTIVE);
		vblank <= (vc >= V_ACTIVE);
		hsync  <= (hc >= HS_START && hc < HS_END);
		vsync  <= (vc >= VS_START && vc < VS_END);

		if (!active_now) begin
			{r, g, b} <= 24'd0;
		end else if (!ctrl_valid) begin
			r <= bar[1] ? 8'hC0 : 8'h00;
			g <= bar[2] ? 8'hC0 : 8'h00;
			b <= bar[0] ? 8'hC0 : 8'h00;
		end else begin
			{r, g, b} <= pal_hi ? pal_q[55:32] : pal_q[23:0];
		end
	end
end

endmodule
