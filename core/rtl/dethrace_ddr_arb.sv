//============================================================================
//
//  Dethrace hybrid core - DDR3 port arbiter
//
//  Shares the framework's DDR3 Avalon-MM port between dethrace_host (video,
//  audio, input) and two more clients (the rasteriser and its command
//  fetcher), one transaction at a time: a read burst until its last data
//  beat, a write burst until its last beat.
//
//  The host is connected whenever the bus is free and has priority, so its
//  requests are never held up by more than the transaction in progress. The
//  other clients hold their request while they see busy.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================

module dethrace_ddr_arb
(
	input             clk,
	input             reset,

	// DDR3 (MiSTer framework)
	input             ddr_busy,
	output      [7:0] ddr_burstcnt,
	output     [28:0] ddr_addr,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	output            ddr_rd,
	output     [63:0] ddr_din,
	output      [7:0] ddr_be,
	output            ddr_we,

	// client 0: host
	output            c0_busy,
	input       [7:0] c0_burstcnt,
	input      [28:0] c0_addr,
	output            c0_dout_ready,
	input             c0_rd,
	input      [63:0] c0_din,
	input       [7:0] c0_be,
	input             c0_we,

	// client 1
	output            c1_busy,
	input       [7:0] c1_burstcnt,
	input      [28:0] c1_addr,
	output            c1_dout_ready,
	input             c1_rd,
	input      [63:0] c1_din,
	input       [7:0] c1_be,
	input             c1_we,

	// client 2
	output            c2_busy,
	input       [7:0] c2_burstcnt,
	input      [28:0] c2_addr,
	output            c2_dout_ready,
	input             c2_rd,
	input      [63:0] c2_din,
	input       [7:0] c2_be,
	input             c2_we
);

localparam A_FREE  = 0;     // nothing in progress, owner connected
localparam A_READ  = 1;     // read accepted, data beats outstanding
localparam A_WRITE = 2;     // write burst in progress

reg  [1:0] owner = 0;
reg  [1:0] state = A_FREE;
reg  [7:0] left;
reg        last = 0;        // of clients 1 and 2, the one granted last

wire        o_rd  = (owner == 2'd1) ? c1_rd : (owner == 2'd2) ? c2_rd : c0_rd;
wire        o_we  = (owner == 2'd1) ? c1_we : (owner == 2'd2) ? c2_we : c0_we;
wire  [7:0] o_cnt = (owner == 2'd1) ? c1_burstcnt : (owner == 2'd2) ? c2_burstcnt : c0_burstcnt;

// no new request reaches the DDR while read data is outstanding
wire gate = (state == A_READ);

assign ddr_rd       = o_rd && !gate;
assign ddr_we       = o_we && !gate;
assign ddr_burstcnt = o_cnt;
assign ddr_addr     = (owner == 2'd1) ? c1_addr : (owner == 2'd2) ? c2_addr : c0_addr;
assign ddr_din      = (owner == 2'd1) ? c1_din  : (owner == 2'd2) ? c2_din  : c0_din;
assign ddr_be       = (owner == 2'd1) ? c1_be   : (owner == 2'd2) ? c2_be   : c0_be;

// the host follows the bus also while it waits for its read data: its state
// machine only runs when it is not busy, and it does not ask again before
// the data is in
assign c0_busy = (owner != 2'd0) || ddr_busy;
assign c1_busy = (owner != 2'd1) || gate || ddr_busy;
assign c2_busy = (owner != 2'd2) || gate || ddr_busy;

assign c0_dout_ready = ddr_dout_ready && (owner == 2'd0);
assign c1_dout_ready = ddr_dout_ready && (owner == 2'd1);
assign c2_dout_ready = ddr_dout_ready && (owner == 2'd2);

wire c0_req = c0_rd || c0_we;
wire c1_req = c1_rd || c1_we;
wire c2_req = c2_rd || c2_we;

always @(posedge clk) begin
	case (state)
		A_FREE: begin
			if (o_rd && !ddr_busy) begin
				left  <= o_cnt;
				state <= A_READ;
			end
			else if (o_we && !ddr_busy) begin
				left <= o_cnt - 1'd1;
				if (o_cnt != 8'd1) state <= A_WRITE;
				else owner <= 2'd0;
			end
			else if (owner == 2'd0 && !c0_req) begin
				// the host is quiet: let the others in, taking turns
				if (c1_req && (!c2_req || last)) begin
					owner <= 2'd1;
					last  <= 0;
				end
				else if (c2_req) begin
					owner <= 2'd2;
					last  <= 1;
				end
			end
			else if (owner != 2'd0 && !o_rd && !o_we) begin
				// request withdrawn
				owner <= 2'd0;
			end
		end

		A_READ: if (ddr_dout_ready) begin
			left <= left - 1'd1;
			if (left == 8'd1) begin
				owner <= 2'd0;
				state <= A_FREE;
			end
		end

		A_WRITE: if (o_we && !ddr_busy) begin
			left <= left - 1'd1;
			if (left == 8'd1) begin
				owner <= 2'd0;
				state <= A_FREE;
			end
		end

		default: state <= A_FREE;
	endcase

	if (reset) begin
		owner <= 0;
		state <= A_FREE;
	end
end

endmodule
