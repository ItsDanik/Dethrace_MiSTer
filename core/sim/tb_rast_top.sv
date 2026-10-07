// Testbench for the rasteriser as it sits in the core: dethrace_rast_top
// (command ring) behind dethrace_ddr_arb, next to a stand-in for
// dethrace_host that keeps the bus busy with read and write bursts of its own
// and checks what it reads. The "HPS" writes the commands of a software
// model trace into the ring in chunks, respecting the ring size, and waits
// for the completed count. Buffers are compared with the model's.
//   vvp tb +trace=<dir>
`timescale 1ns/1ps

module tb_rast_top;

reg clk = 0;
always #10 clk = ~clk; // 50MHz

reg reset = 1;

wire        ddr_busy;
wire  [7:0] ddr_burstcnt;
wire [28:0] ddr_addr;
reg  [63:0] ddr_dout;
reg         ddr_dout_ready = 0;
wire        ddr_rd;
wire [63:0] ddr_din;
wire  [7:0] ddr_be;
wire        ddr_we;

// host stand-in
wire        h_busy;
reg   [7:0] h_burstcnt;
reg  [28:0] h_addr;
wire        h_dout_ready;
reg         h_rd = 0;
reg  [63:0] h_din;
reg         h_we = 0;

wire        r_busy, r_dout_ready, r_rd, r_we;
wire  [7:0] r_burstcnt, r_be;
wire [28:0] r_addr;
wire [63:0] r_din;
wire        f_busy, f_dout_ready, f_rd, f_we;
wire  [7:0] f_burstcnt, f_be;
wire [28:0] f_addr;
wire [63:0] f_din;

dethrace_ddr_arb arb
(
	.clk(clk), .reset(reset),
	.ddr_busy(ddr_busy), .ddr_burstcnt(ddr_burstcnt), .ddr_addr(ddr_addr), .ddr_dout(ddr_dout),
	.ddr_dout_ready(ddr_dout_ready), .ddr_rd(ddr_rd), .ddr_din(ddr_din), .ddr_be(ddr_be), .ddr_we(ddr_we),
	.c0_busy(h_busy), .c0_burstcnt(h_burstcnt), .c0_addr(h_addr), .c0_dout_ready(h_dout_ready),
	.c0_rd(h_rd), .c0_din(h_din), .c0_be(8'hFF), .c0_we(h_we),
	.c1_busy(r_busy), .c1_burstcnt(r_burstcnt), .c1_addr(r_addr), .c1_dout_ready(r_dout_ready),
	.c1_rd(r_rd), .c1_din(r_din), .c1_be(r_be), .c1_we(r_we),
	.c2_busy(f_busy), .c2_burstcnt(f_burstcnt), .c2_addr(f_addr), .c2_dout_ready(f_dout_ready),
	.c2_rd(f_rd), .c2_din(f_din), .c2_be(f_be), .c2_we(f_we)
);

dethrace_rast_top dut
(
	.clk(clk), .reset(reset), .mem_dout(ddr_dout),
	.r_busy(r_busy), .r_burstcnt(r_burstcnt), .r_addr(r_addr), .r_dout_ready(r_dout_ready),
	.r_rd(r_rd), .r_din(r_din), .r_be(r_be), .r_we(r_we),
	.f_busy(f_busy), .f_burstcnt(f_burstcnt), .f_addr(f_addr), .f_dout_ready(f_dout_ready),
	.f_rd(f_rd), .f_din(f_din), .f_be(f_be), .f_we(f_we)
);

//////////////////////////////////////////////////////////////////
// DDR model: the rasteriser's region and 64K words of host memory

localparam [28:0] RAST_BASE = 29'h06200000;
localparam [28:0] HOST_BASE = 29'h06000000;

reg [63:0] mem[0:2097151];
reg [63:0] hmem[0:65535];
reg [63:0] expect_mem[0:2097151];
reg [31:0] cmds[0:1048575];

reg busy_r = 0;
always @(posedge clk) busy_r <= ($random & 3) == 0;
assign ddr_busy = busy_r;

reg [28:0] rq_addr;
reg  [7:0] rq_len;
reg        rq_pending = 0;
integer    cur_beat = 0, lat = 0;
reg        wr_active = 0;
reg [28:0] wr_addr;
integer    wr_left = 0, wr_idx = 0, k;
reg [28:0] a;

always @(posedge clk) begin
	ddr_dout_ready <= 0;
	if (!ddr_busy) begin
		if (ddr_rd) begin
			if (rq_pending || wr_active) begin $display("FAIL: overlapping transactions"); $finish; end
			if (ddr_we) begin $display("FAIL: rd and we together"); $finish; end
			rq_addr = ddr_addr;
			rq_len = ddr_burstcnt;
			rq_pending = 1;
			cur_beat = 0;
			lat = 0;
		end
		else if (ddr_we) begin
			if (rq_pending) begin $display("FAIL: write with a read pending"); $finish; end
			if (!wr_active) begin
				wr_active = 1;
				wr_addr = ddr_addr;
				wr_left = ddr_burstcnt;
				wr_idx = 0;
			end
			a = wr_addr + wr_idx;
			for (k = 0; k < 8; k = k + 1) begin
				if (ddr_be[k]) begin
					if (a >= RAST_BASE) mem[a - RAST_BASE][k*8 +: 8] = ddr_din[k*8 +: 8];
					else hmem[a - HOST_BASE][k*8 +: 8] = ddr_din[k*8 +: 8];
				end
			end
			wr_idx = wr_idx + 1;
			wr_left = wr_left - 1;
			if (wr_left == 0) wr_active = 0;
		end
	end
	if (rq_pending) begin
		if (lat < 8) lat = lat + 1;
		else if (($random & 7) != 0) begin
			a = rq_addr + cur_beat;
			ddr_dout <= (a >= RAST_BASE) ? mem[a - RAST_BASE] : hmem[a - HOST_BASE];
			ddr_dout_ready <= 1;
			cur_beat = cur_beat + 1;
			if (cur_beat == rq_len) rq_pending = 0;
		end
	end
end

//////////////////////////////////////////////////////////////////
// Host stand-in: random bursts on its own memory, the way dethrace_host
// drives the bus (requests are raised and advanced only while not busy)

integer h_state = 0, h_cnt = 0, h_len = 0, h_checked = 0, h_wait = 0;
reg [15:0] h_base;

always @(posedge clk) begin
	if (h_dout_ready) begin
		if (ddr_dout !== {48'hC0FFEE000000, h_base + h_cnt[15:0]} && ddr_dout !== {48'hFACE00000000, h_base + h_cnt[15:0]}) begin
			$display("FAIL: host read %x at %x", ddr_dout, h_base + h_cnt); $finish;
		end
		h_cnt = h_cnt + 1;
		h_checked = h_checked + 1;
	end
	if (!h_busy && !reset) begin
		h_rd <= 0;
		case (h_state)
			0: if (h_wait != 0) h_wait = h_wait - 1;
			   else begin
				h_base = $random;
				if (h_base > 16'hFF00) h_base = 16'hFF00;
				h_len = 1 + ($random & 63);
				h_cnt = 0;
				h_addr <= HOST_BASE + h_base;
				h_burstcnt <= h_len;
				if ($random & 1) begin
					h_rd <= 1;
					h_state = 1;
				end else begin
					h_we <= 1;
					h_din <= {48'hFACE00000000, h_base};
					h_cnt = 1;
					h_state = 2;
				end
			end
			1: if (h_cnt == h_len) begin h_state = 0; h_wait = $random & 63; end
			2: if (h_cnt == h_len) begin
				h_we <= 0;
				h_state = 0;
				h_wait = $random & 63;
			end else begin
				h_din <= {48'hFACE00000000, h_base + h_cnt[15:0]};
				h_cnt = h_cnt + 1;
			end
		endcase
	end
end

//////////////////////////////////////////////////////////////////
// "HPS"

reg [1023:0] dir;
integer cmd_count, ci, n, produced, errors, checked, cycles, chunk, i, timeout;
reg [31:0] ring_word;

task ring_put(input [31:0] w);
	begin
		// 32 bit word `produced` of the ring
		if (produced[0]) mem[21'h10000 + ((produced >> 1) & 16'hFFFF)][63:32] = w;
		else mem[21'h10000 + ((produced >> 1) & 16'hFFFF)][31:0] = w;
		produced = produced + 1;
	end
endtask

always @(posedge clk) cycles = cycles + 1;

initial begin
	if (!$value$plusargs("trace=%s", dir)) begin
		$display("usage: +trace=<dir>"); $finish;
	end
	for (i = 0; i < 65536; i = i + 1) hmem[i] = {48'hC0FFEE000000, i[15:0]};
	$readmemh({dir, "/mem.hex"}, mem);
	$readmemh({dir, "/expect.hex"}, expect_mem);
	$readmemh({dir, "/cmds.hex"}, cmds);
	cmd_count = 0;
	while (cmds[cmd_count] !== 32'bx) cmd_count = cmd_count + 1;
	mem[0] = 0;
	mem[1] = 0;
	mem[2] = 0;

	repeat (4) @(posedge clk);
	reset <= 0;
	repeat (500) @(posedge clk);
	if (mem[1] !== 0 || mem[2] !== 0) begin $display("FAIL: wrote status while disabled"); $finish; end

	// start a session
	mem[0] = {32'd0, 32'h54534152};
	while (mem[2][31:0] !== 32'h4B4F5352) @(posedge clk);
	cycles = 0;

	produced = 0;
	ci = 0;
	while (ci < cmd_count) begin
		// a few commands at a time, as much as the ring holds
		chunk = 1 + ($random & 31);
		while (chunk > 0 && ci < cmd_count) begin
			n = (cmds[ci] >> 8) & 255;
			while (produced + n + 1 - mem[1][31:0] > 131072) @(posedge clk);
			for (i = 0; i < n; i = i + 1) ring_put(cmds[ci + i]);
			if (n & 1) ring_put(32'h00000100);
			ci = ci + n;
			chunk = chunk - 1;
		end
		mem[0][63:32] = produced;
		repeat ($random & 255) @(posedge clk);
	end

	timeout = 0;
	while (mem[1][63:32] !== produced) begin
		@(posedge clk);
		timeout = timeout + 1;
		if (timeout > 50000000) begin $display("FAIL: timeout, fetched %0d completed %0d of %0d", mem[1][31:0], mem[1][63:32], produced); $finish; end
	end

	errors = 0;
	checked = 0;
	for (i = 0; i < 2097152; i = i + 1) begin
		if (expect_mem[i] !== 64'bx) begin
			checked = checked + 1;
			if (mem[i] !== expect_mem[i]) begin
				errors = errors + 1;
				if (errors <= 10) $display("MISMATCH word %x (byte address %x): got %x expected %x", i, i * 8, mem[i], expect_mem[i]);
			end
		end
	end
	$display("%0d command words (%0d with padding), %0d cycles (%0d ms at 50MHz), host checked %0d words", cmd_count, produced, cycles, cycles / 50000, h_checked);
	if (errors == 0) $display("PASS: %0d words match the software model", checked);
	else $display("FAIL: %0d of %0d words differ", errors, checked);
	$finish;
end

endmodule
