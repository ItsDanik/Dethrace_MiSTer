// Testbench for dethrace_rast: replays a command trace of the software model
// (PENTPRIM_FPGA_TRACE, see fpgarast.c) against a DDR model with random
// waitrequest and read latency, and compares the buffers with what the model
// left (expect.hex, written by PENTPRIM_FPGA_REPLAY).
//   vvp tb +trace=<dir> [+fast] (+fast: no random waits, for cycle counts)
`timescale 1ns/1ps

module tb_rast;

reg clk = 0;
always #10 clk = ~clk; // 50MHz

reg reset = 1;

reg  [31:0] cmd_data;
reg         cmd_valid = 0;
wire        cmd_ready;
wire        idle;

wire        mem_busy;
wire [20:0] mem_addr;
wire  [7:0] mem_burstcnt;
wire        mem_rd;
reg  [63:0] mem_dout;
reg         mem_dout_ready = 0;
wire [63:0] mem_din;
wire  [7:0] mem_be;
wire        mem_we;

dethrace_rast dut
(
	.clk(clk), .reset(reset),
	.cmd_data(cmd_data), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .idle(idle),
	.mem_busy(mem_busy), .mem_addr(mem_addr), .mem_burstcnt(mem_burstcnt), .mem_rd(mem_rd),
	.mem_dout(mem_dout), .mem_dout_ready(mem_dout_ready), .mem_din(mem_din), .mem_be(mem_be), .mem_we(mem_we)
);

//////////////////////////////////////////////////////////////////
// Memory model: the rasteriser's 16MB region

reg [63:0] mem[0:2097151];
reg [63:0] expect_mem[0:2097151];
reg [31:0] cmds[0:1048575];

reg     fast = 0;
integer read_latency = 8;

reg busy_r = 0;
always @(posedge clk) busy_r <= !fast && ($random & 3) == 0;
assign mem_busy = busy_r;

reg [20:0] rq_addr[0:15];
reg  [7:0] rq_len[0:15];
integer    rq_head = 0, rq_tail = 0;
integer    cur_beat = 0;
integer    lat = 0;

reg        wr_active = 0;
reg [20:0] wr_addr;
integer    wr_left = 0, wr_idx = 0;
integer    k;
integer    reads = 0, read_words = 0, writes = 0, write_words = 0;

always @(posedge clk) begin
	mem_dout_ready <= 0;
	if (!mem_busy) begin
		if (mem_rd) begin
			rq_addr[rq_tail % 16] = mem_addr;
			rq_len[rq_tail % 16]  = mem_burstcnt;
			rq_tail = rq_tail + 1;
			reads = reads + 1;
			read_words = read_words + mem_burstcnt;
			if (mem_burstcnt == 0 || mem_burstcnt > 128) begin
				$display("FAIL: bad read burst count %0d", mem_burstcnt); $finish;
			end
			if (wr_active) begin $display("FAIL: read inside a write burst"); $finish; end
		end
		if (mem_we) begin
			if (mem_rd) begin $display("FAIL: rd and we together"); $finish; end
			if (!wr_active) begin
				wr_active = 1;
				wr_addr = mem_addr;
				wr_left = mem_burstcnt;
				wr_idx = 0;
				writes = writes + 1;
				if (mem_burstcnt == 0 || mem_burstcnt > 128) begin
					$display("FAIL: bad write burst count %0d", mem_burstcnt); $finish;
				end
				if (rq_head != rq_tail) begin $display("FAIL: write with a read pending"); $finish; end
			end
			for (k = 0; k < 8; k = k + 1) begin
				if (mem_be[k]) mem[wr_addr + wr_idx][k*8 +: 8] = mem_din[k*8 +: 8];
			end
			if (^{mem_be, mem_din} === 1'bx && ^mem_be === 1'bx) begin $display("FAIL: undefined byte enables"); $finish; end
			write_words = write_words + 1;
			wr_idx = wr_idx + 1;
			wr_left = wr_left - 1;
			if (wr_left == 0) wr_active = 0;
		end
	end
	// read data after a latency, with random gaps
	if (rq_head != rq_tail) begin
		if (lat < read_latency) lat = lat + 1;
		else if (fast || ($random & 7) != 0) begin
			mem_dout <= mem[rq_addr[rq_head % 16] + cur_beat];
			mem_dout_ready <= 1;
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

reg [1023:0] dir;
integer cmd_count, ci, errors, checked, cycles;
integer i;

integer pixels = 0, drawn = 0, spans = 0, fills = 0;
integer state_cycles[0:31];
integer si;
initial for (si = 0; si < 32; si = si + 1) state_cycles[si] = 0;
always @(posedge clk) state_cycles[dut.state] = state_cycles[dut.state] + 1;
// stuck in one state without a pixel: give up
integer watchdog = 0;
reg [4:0] last_state = 0;
always @(posedge clk) begin
	last_state <= dut.state;
	watchdog = (dut.state != last_state || dut.commit || dut.state == dut.M_IDLE) ? 0 : watchdog + 1;
	if (watchdog > 100000) begin
		$display("FAIL: stuck in state %0d (op %0d flags t%b i%b p%b a%b g%b, tex_ready %b pass %b hit %b use_fill %b texel %h tlane %h cache_addr %h left %0d div_valid %b)", dut.state, dut.op, dut.f_t, dut.f_i, dut.f_p, dut.f_a, dut.f_g, dut.tex_ready, dut.pass, dut.lookup_hit, dut.use_fill, dut.texel, dut.tlane, dut.cache_addr, dut.left, dut.div_valid);
		$finish;
	end
end

always @(posedge clk) begin
	cycles = cycles + 1;
	if (dut.commit) pixels = pixels + 1;
	if (dut.commit && dut.commit_write) drawn = drawn + 1;
	if (dut.state == dut.M_SPAN) spans = spans + 1;
	if (dut.state == dut.M_FILL) fills = fills + 1;
end

initial begin
	if (!$value$plusargs("trace=%s", dir)) begin
		$display("usage: +trace=<dir>"); $finish;
	end
	if ($test$plusargs("fast")) fast = 1;
	$readmemh({dir, "/mem.hex"}, mem);
	$readmemh({dir, "/expect.hex"}, expect_mem);
	$readmemh({dir, "/cmds.hex"}, cmds);
	cmd_count = 0;
	while (cmds[cmd_count] !== 32'bx) cmd_count = cmd_count + 1;

	repeat (4) @(posedge clk);
	reset <= 0;
	cycles = 0;

	ci = 0;
	while (ci < cmd_count) begin
		@(posedge clk);
		if (cmd_valid && cmd_ready) ci = ci + 1;
		if (ci < cmd_count && (fast || ($random & 3) != 0)) begin
			cmd_valid <= 1;
			cmd_data  <= cmds[ci];
		end else begin
			cmd_valid <= 0;
		end
	end
	cmd_valid <= 0;
	@(posedge clk);
	while (!idle) @(posedge clk);
	watchdog = 0;
	repeat (4) @(posedge clk);

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
	$display("%0d command words, %0d cycles (%0d ms at 50MHz), %0d reads (%0d words), %0d writes (%0d words)",
		cmd_count, cycles, cycles / 50000, reads, read_words, writes, write_words);
	$display("%0d spans, %0d pixels (%0d drawn), %0d cache fills, %0d.%02d cycles per pixel",
		spans, pixels, drawn, fills, cycles / pixels, (cycles * 100 / pixels) % 100);
	if ($test$plusargs("states")) for (si = 0; si < 32; si = si + 1) if (state_cycles[si] != 0) $display("  state %0d: %0d cycles", si, state_cycles[si]);
	if (errors == 0) $display("PASS: %0d words match the software model", checked);
	else $display("FAIL: %0d of %0d words differ", errors, checked);
	$finish;
end

endmodule
