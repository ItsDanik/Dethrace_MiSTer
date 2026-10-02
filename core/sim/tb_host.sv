// Testbench for dethrace_host: DDR model with random waitrequest and read
// latency, checks scanout pixels against framebuffer+palette in both video
// modes, sync timings and the status block.
`timescale 1ns/1ps

module tb_host;

reg clk = 0;
always #10 clk = ~clk; // 50MHz

reg reset = 1;

wire        ddr_busy;
wire  [7:0] ddr_burstcnt;
wire [28:0] ddr_addr;
reg  [63:0] ddr_dout;
reg         ddr_dout_ready;
wire        ddr_rd;
wire [63:0] ddr_din;
wire  [7:0] ddr_be;
wire        ddr_we;

reg  [31:0] joystick_0 = 32'h00000012, joystick_1 = 32'h00000034;
reg  [10:0] ps2_key = 0;
reg  [24:0] ps2_mouse = 0;

wire ce_pix, hsync, vsync, hblank, vblank;
wire [15:0] audio_l, audio_r;
wire [7:0] r, g, b;

dethrace_host dut
(
	.clk(clk), .reset(reset),
	.ddr_busy(ddr_busy), .ddr_burstcnt(ddr_burstcnt), .ddr_addr(ddr_addr), .ddr_dout(ddr_dout),
	.ddr_dout_ready(ddr_dout_ready), .ddr_rd(ddr_rd), .ddr_din(ddr_din), .ddr_be(ddr_be), .ddr_we(ddr_we),
	.joystick_0(joystick_0), .joystick_1(joystick_1),
	.joy_l_analog_0(16'h1122), .joy_r_analog_0(16'h3344), .joy_l_analog_1(16'h5566), .joy_r_analog_1(16'h7788),
	.osd_status(64'hCAFE), .ps2_key(ps2_key), .ps2_mouse(ps2_mouse), .ps2_mouse_ext(16'd0),
	.ce_pix(ce_pix), .r(r), .g(g), .b(b), .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
	.audio_l(audio_l), .audio_r(audio_r)
);

//////////////////////////////////////////////////////////////////
// DDR model. mem index = word address - BASE

localparam [28:0] BASE = 29'h06000000;
reg [63:0] mem[0:524287];

// random waitrequest
reg busy_r = 0;
always @(posedge clk) busy_r <= ($random & 3) == 0;
assign ddr_busy = busy_r;

// read queue: bursts become readable after a random latency
reg [28:0] rq_addr[0:15];
reg  [7:0] rq_len[0:15];
integer    rq_head = 0, rq_tail = 0;
integer    cur_beat = 0;
integer    lat = 0;
integer    reads_issued = 0;

// write burst tracking
reg        wr_active = 0;
reg [28:0] wr_addr;
integer    wr_left = 0, wr_idx = 0;
integer    stat_writes = 0;

always @(posedge clk) begin
	ddr_dout_ready <= 0;
	if (!ddr_busy) begin
		if (ddr_rd) begin
			rq_addr[rq_tail % 16] = ddr_addr;
			rq_len[rq_tail % 16]  = ddr_burstcnt;
			rq_tail = rq_tail + 1;
			reads_issued = reads_issued + 1;
			if (ddr_burstcnt == 0 || ddr_burstcnt > 128) begin
				$display("FAIL: bad burst count %0d", ddr_burstcnt); $finish;
			end
		end
		if (ddr_we) begin
			if (ddr_rd) begin $display("FAIL: rd and we together"); $finish; end
			if (!wr_active) begin
				wr_active = 1;
				wr_addr = ddr_addr;
				wr_left = ddr_burstcnt;
				wr_idx = 0;
			end
			mem[wr_addr - BASE + wr_idx] = ddr_din;
			wr_idx = wr_idx + 1;
			wr_left = wr_left - 1;
			if (wr_left == 0) begin
				wr_active = 0;
				stat_writes = stat_writes + 1;
			end
		end
	end
	// return read data with latency and random gaps
	if (rq_head != rq_tail) begin
		if (lat < 12) lat = lat + 1;
		else if (($random & 7) != 0) begin
			ddr_dout <= mem[rq_addr[rq_head % 16] - BASE + cur_beat];
			ddr_dout_ready <= 1;
			cur_beat = cur_beat + 1;
			if (cur_beat == rq_len[rq_head % 16]) begin
				cur_beat = 0;
				rq_head = rq_head + 1;
				lat = 0;
			end
		end
	end
end

//////////////////////////////////////////////////////////////////
// Shared memory contents

function [7:0] fb_pixel(input integer fb, input integer x, input integer y);
	fb_pixel = (x * 3 + y * 7 + fb * 50) & 8'hFF;
endfunction

function [23:0] pal_rgb(input integer slot, input integer i);
	pal_rgb = {i[7:0], ~i[7:0], i[7:0] ^ (slot ? 8'h55 : 8'hAA)};
endfunction

task set_ctrl(input integer fb, input integer mode, input integer slot, input integer seq);
	mem[0] = {7'd0, 1'b1, 7'd0, slot[0], 7'd0, mode[0], fb[7:0], 32'h48544544};
	mem[1] = {32'd0, seq[31:0]};
endtask

integer i, x, y, f, s;
initial begin
	for (i = 0; i < 524288; i = i + 1) mem[i] = 0;
	for (s = 0; s < 2; s = s + 1)
		for (i = 0; i < 256; i = i + 2)
			mem[29'h200 + s * 29'h80 + i / 2] = {8'd0, pal_rgb(s, i + 1), 8'd0, pal_rgb(s, i)};
	// audio ring: frame n = {R = ~n, L = n * 3}
	for (i = 0; i < 16384; i = i + 1)
		mem[29'h2000 + i / 2][(i % 2) * 32 +: 32] = {~i[15:0], i[15:0] * 16'd3};
	for (f = 0; f < 3; f = f + 1)
		for (y = 0; y < 480; y = y + 1)
			for (x = 0; x < 640; x = x + 1) begin
				// row stride differs per mode: fill for mode 0 in fb0/fb1, mode 1 in fb2
				if (f < 2 && x < 320 && y < 200)
					mem[29'h20000 * (f + 1) + (y * 320 + x) / 8][((x % 8) * 8) +: 8] = fb_pixel(f, x, y);
				if (f == 2 && x < 320 && y < 200)
					mem[29'h20000 * (f + 1) + (y * 320 + x) / 8][((x % 8) * 8) +: 8] = fb_pixel(f, x, y);
			end
end

//////////////////////////////////////////////////////////////////
// Output checker

integer cur_fb = 0, cur_mode = 0, cur_slot = 1;
integer px = 0, py = 0;
integer errors = 0, checked = 0;
integer fields_seen = 0;
integer check_enable = 0;
reg     old_hblank = 1, old_vblank = 1, old_vsync = 0;
integer ce_count = 0, last_hs_ce = 0, hs_period = 0, last_vs_ce = 0, vs_period = 0;
reg     old_hsync = 0;
integer field_rows = 0;


always @(posedge clk) if (ce_pix) begin
	ce_count = ce_count + 1;
	old_hsync <= hsync;
	if (hsync && !old_hsync) begin
		hs_period = ce_count - last_hs_ce;
		last_hs_ce = ce_count;
	end
	old_vsync <= vsync;
	if (vsync && !old_vsync) begin
		vs_period = ce_count - last_vs_ce;
		last_vs_ce = ce_count;
	end

	old_hblank <= hblank;
	old_vblank <= vblank;
	if (!vblank && old_vblank) begin
		py = 0;
	end
	if (!hblank && old_hblank) px = 0;

	if (!hblank && !vblank) begin
		if (check_enable) begin : chk
			integer row;
			reg [23:0] exp;
			row = py;
			exp = pal_rgb(cur_slot, fb_pixel(cur_fb, px, row));
			if ({r, g, b} !== exp) begin
				if (errors < 10) $display("FAIL: fb %0d px %0d py %0d got %h exp %h", cur_fb, px, py, {r, g, b}, exp);
				errors = errors + 1;
			end
			checked = checked + 1;
		end
		px = px + 1;
	end
	if (hblank && !old_hblank && !vblank) py = py + 1;
	if (vblank && !old_vblank) begin
		fields_seen = fields_seen + 1;
		field_rows = py;
	end
end

task wait_fields(input integer n);
	integer target;
	begin
		target = fields_seen + n;
		while (fields_seen < target) @(posedge clk);
	end
endtask

initial begin
	$display("tb_host: start");
	set_ctrl(0, 0, 0, 0);
	mem[0][31:0] = 0; // invalid control block: test pattern
	repeat (20) @(posedge clk);
	reset = 0;

	// mode 0 from framebuffer index 0
	wait_fields(1);
	if (dut.ctrl_valid) begin $display("FAIL: ctrl valid without magic"); $finish; end
	set_ctrl(0, 0, 1, 7);
	cur_fb = 0; cur_mode = 0; cur_slot = 1;
	// key press and joystick for the status block
	ps2_key = {~ps2_key[10], 1'b1, 1'b1, 8'h75}; // extended up arrow pressed
	wait_fields(2);
	check_enable = 1;
	wait_fields(2);
	check_enable = 0;
	$display("video: checked %0d pixels, %0d errors, rows/field %0d, hsync period %0d, vsync period %0d",
		checked, errors, field_rows, hs_period, vs_period);
	if (field_rows != 200 || hs_period != 400 || vs_period != 400 * 262) begin $display("FAIL: video timing"); $finish; end

	// status block
	if (mem[8][31:0] != 32'h53485444) begin $display("FAIL: status magic %h", mem[8]); $finish; end
	if (mem[10] != {32'h34, 32'h12}) begin $display("FAIL: status joystick %h", mem[10]); $finish; end
	if (mem[11] != 64'h7788556633441122) begin $display("FAIL: status analog %h", mem[11]); $finish; end
	if (mem[12] != 64'hCAFE) begin $display("FAIL: status osd %h", mem[12]); $finish; end
	if (!mem[8 + 8 + (9'h175 / 64)][9'h175 % 64]) begin $display("FAIL: key bitmap"); $finish; end
	$display("status: frame counter %0d, writes %0d", mem[8][63:32], stat_writes);

	// page flip + palette slot change
	set_ctrl(1, 0, 0, 8);
	wait_fields(2);
	cur_fb = 1; cur_slot = 0;
	check_enable = 1;
	wait_fields(2);
	check_enable = 0;
	$display("flip: checked %0d pixels, %0d errors", checked, errors);

	// third framebuffer, palette slot 1 again
	set_ctrl(2, 0, 1, 9);
	wait_fields(2);
	cur_fb = 2; cur_slot = 1;
	check_enable = 1;
	wait_fields(2);
	check_enable = 0;
	$display("fb2: checked %0d pixels, %0d errors", checked, errors);

	$display("audio: %0d samples, %0d errors, rate %0d Hz, fetch pointer %0d",
		aud_samples, aud_errors,
		(aud_samples - 1) * 64'd1000000000 / (aud_last_tick_time - aud_first_tick_time) , mem[24][31:0]);
	if (aud_samples < 1000 || aud_errors != 0) errors = errors + 1;
	if (mem[24][31:0] < aud_samples || mem[24][31:0] > aud_samples + 200) begin
		$display("FAIL: audio fetch pointer"); errors = errors + 1;
	end
	if (errors != 0) $display("FAIL: %0d errors", errors);
	else $display("PASS");
	$finish;
end

//////////////////////////////////////////////////////////////////
// Audio checker: every output sample must be the next ring frame

integer aud_next = -1, aud_samples = 0, aud_errors = 0;
integer aud_first_tick_time = 0, aud_last_tick_time = 0;
reg     aud_check = 0;
always @(posedge clk) if (dut.aud_tick2 && dut.audio_en) begin
	// outputs update on this edge, look at them one clock later
	@(posedge clk);
	if (audio_l != 0 || audio_r != 0 || aud_next >= 0) begin
		if (aud_next < 0) begin
			aud_next = audio_l / 3;
			aud_first_tick_time = $time;
		end
		if (audio_l !== aud_next[15:0] * 16'd3 || audio_r !== ~aud_next[15:0]) begin
			if (aud_errors < 10) $display("FAIL: audio sample %0d got %h/%h", aud_next, audio_l, audio_r);
			aud_errors = aud_errors + 1;
		end
		aud_next = (aud_next + 1) % 16384;
		aud_samples = aud_samples + 1;
		aud_last_tick_time = $time;
	end
end

initial begin
	#1_000_000_000;
	$display("FAIL: timeout");
	$finish;
end

endmodule
