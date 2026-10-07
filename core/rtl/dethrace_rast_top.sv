//============================================================================
//
//  Dethrace hybrid core - rasteriser with its command ring
//
//  The HPS writes rasteriser commands (see fpgarast.h) into a ring in the
//  shared DDR3 memory. This module fetches them and feeds dethrace_rast.
//
//  Rasteriser region (physical address 0x31000000 + offset), see fpgarast.h
//  for the rest of it:
//    0x000000  control (HPS -> FPGA), 64 bit
//              [31:0]  magic "RAST" (0x54534152): the rasteriser is in use.
//                      Anything else: it is idle and writes nothing
//              [63:32] number of command words written to the ring so far
//                      (always even: commands are padded to 64 bit)
//    0x000008  status (FPGA -> HPS), 64 bit, written after every change
//              [31:0]  number of command words fetched from the ring
//              [63:32] number of command words completed: equals the number
//                      written once everything is drawn and in memory
//    0x000010  [31:0] magic "RSOK" (0x4B4F5352), [63:32] version; written
//              when the control magic appears, which also resets the counts
//    0x080000  command ring: 65536 x 64 bit, command word n is at 32 bit
//              word n mod 131072
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================

module dethrace_rast_top
(
	input             clk,
	input             reset,

	input      [63:0] mem_dout,

	// rasteriser memory port
	input             r_busy,
	output      [7:0] r_burstcnt,
	output     [28:0] r_addr,
	input             r_dout_ready,
	output            r_rd,
	output     [63:0] r_din,
	output      [7:0] r_be,
	output            r_we,

	// command fetcher memory port
	input             f_busy,
	output reg  [7:0] f_burstcnt,
	output reg [28:0] f_addr,
	input             f_dout_ready,
	output reg        f_rd,
	output reg [63:0] f_din,
	output      [7:0] f_be,
	output reg        f_we
);

localparam [31:0] CTRL_MAGIC   = 32'h54534152; // "RAST"
localparam [31:0] STATUS_MAGIC = 32'h4B4F5352; // "RSOK"
localparam [31:0] VERSION      = 32'd1;

localparam [28:0] BASE      = 29'h06200000;    // 0x31000000 >> 3
localparam [28:0] RING_ADDR = BASE + 29'h10000;
localparam  [4:0] FETCH_MAX = 5'd16;

assign f_be = 8'hFF;

//////////////////////////////////////////////////////////////////
// Command FIFO: 64 x 64 bit, handed out as 32 bit words, low half first

reg [63:0] fifo[0:63];
reg  [6:0] fifo_wr = 0, fifo_rd = 0;
reg        fifo_half = 0;

wire  [6:0] fifo_level = fifo_wr - fifo_rd;
wire        fifo_empty = (fifo_level == 0);
wire [63:0] fifo_q = fifo[fifo_rd[5:0]];

wire [31:0] cmd_data = fifo_half ? fifo_q[63:32] : fifo_q[31:0];
wire        cmd_valid = !fifo_empty;
wire        cmd_ready;
wire        rast_idle;
reg         rast_reset = 1;

wire [20:0] rast_addr;
assign r_addr = BASE + {8'd0, rast_addr};

dethrace_rast rast
(
	.clk(clk),
	.reset(reset || rast_reset),

	.cmd_data(cmd_data),
	.cmd_valid(cmd_valid),
	.cmd_ready(cmd_ready),
	.idle(rast_idle),

	.mem_busy(r_busy),
	.mem_addr(rast_addr),
	.mem_burstcnt(r_burstcnt),
	.mem_rd(r_rd),
	.mem_dout(mem_dout),
	.mem_dout_ready(r_dout_ready),
	.mem_din(r_din),
	.mem_be(r_be),
	.mem_we(r_we)
);

//////////////////////////////////////////////////////////////////
// Fetcher

localparam F_WAIT    = 0;
localparam F_POLL    = 1;
localparam F_POLLW   = 2;
localparam F_DECIDE  = 3;
localparam F_FETCH   = 4;
localparam F_FETCHW  = 5;
localparam F_STATUS  = 6;
localparam F_STATUS2 = 7;

reg  [2:0] state = F_WAIT;
reg        enabled = 0;
reg        announce = 0;
reg [31:0] produced, fetched, completed;
reg  [5:0] timer = 0;
reg  [4:0] burst, beats;

// 64 bit words: waiting in the ring, up to the end of the ring, free in the FIFO
wire [30:0] avail = (produced - fetched) >> 1;
wire [15:0] ring_idx = fetched[16:1];
wire [16:0] to_end = 17'h10000 - {1'b0, ring_idx};
wire  [6:0] fifo_free = 7'd64 - fifo_level;

reg  [4:0] fetch_n;
always @(*) begin
	fetch_n = FETCH_MAX;
	if (avail < {26'd0, fetch_n}) fetch_n = avail[4:0];
	if (to_end < {12'd0, fetch_n}) fetch_n = to_end[4:0];
	if (fifo_free < {2'd0, fetch_n}) fetch_n = fifo_free[4:0];
end

always @(posedge clk) begin
	rast_reset <= 0;

	if (cmd_valid && cmd_ready) begin
		fifo_half <= ~fifo_half;
		if (fifo_half) fifo_rd <= fifo_rd + 1'd1;
	end

	case (state)
		F_WAIT: begin
			timer <= timer + 1'd1;
			if (&timer) state <= F_POLL;
		end

		F_POLL: begin
			f_rd       <= 1;
			f_addr     <= BASE;
			f_burstcnt <= 8'd1;
			state      <= F_POLLW;
		end

		F_POLLW: begin
			if (!f_busy) f_rd <= 0;
			if (f_dout_ready) begin
				if (mem_dout[31:0] == CTRL_MAGIC) begin
					produced <= mem_dout[63:32];
					if (!enabled) begin
						// a new session
						enabled    <= 1;
						announce   <= 1;
						produced   <= 0;
						fetched    <= 0;
						completed  <= 0;
						fifo_wr    <= 0;
						fifo_rd    <= 0;
						fifo_half  <= 0;
						rast_reset <= 1;
					end
				end else begin
					enabled <= 0;
				end
				state <= F_DECIDE;
			end
		end

		F_DECIDE: begin
			state <= F_WAIT;
			if (enabled) begin
				if (announce) state <= F_STATUS;
				else if (fetched != produced) begin
					if (fetch_n != 0) state <= F_FETCH;
				end
				else if (rast_idle && fifo_empty && completed != fetched) begin
					completed <= fetched;
					state     <= F_STATUS;
				end
			end
		end

		F_FETCH: begin
			f_rd       <= 1;
			f_addr     <= RING_ADDR + {13'd0, ring_idx};
			f_burstcnt <= {3'd0, fetch_n};
			burst      <= fetch_n;
			beats      <= 0;
			state      <= F_FETCHW;
		end

		F_FETCHW: begin
			if (!f_busy) f_rd <= 0;
			if (f_dout_ready) begin
				fifo[fifo_wr[5:0]] <= mem_dout;
				fifo_wr <= fifo_wr + 1'd1;
				beats   <= beats + 1'd1;
			end
			if (beats == burst) begin
				fetched <= fetched + {26'd0, burst, 1'b0};
				state   <= F_STATUS;
			end
		end

		// status, and the announcement after it for a new session
		F_STATUS: begin
			f_we       <= 1;
			f_addr     <= BASE + 29'd1;
			f_burstcnt <= announce ? 8'd2 : 8'd1;
			f_din      <= {completed, fetched};
			state      <= F_STATUS2;
		end

		F_STATUS2: if (!f_busy) begin
			if (announce) begin
				f_din    <= {VERSION, STATUS_MAGIC};
				announce <= 0;
			end else begin
				f_we  <= 0;
				state <= F_DECIDE;
			end
		end

		default: state <= F_WAIT;
	endcase

	if (reset) begin
		state      <= F_WAIT;
		enabled    <= 0;
		announce   <= 0;
		f_rd       <= 0;
		f_we       <= 0;
		fifo_wr    <= 0;
		fifo_rd    <= 0;
		fifo_half  <= 0;
		rast_reset <= 1;
	end
end

endmodule
