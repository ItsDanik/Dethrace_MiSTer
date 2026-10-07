//============================================================================
//
//  Dethrace hybrid core - triangle rasteriser
//
//  Executes the command stream described in
//  dethrace/lib/BRender-v1.3.2/drivers/pentprim/fpgarast.h: the HPS does the
//  triangle setup, this module walks the edges and fills colour and depth in
//  DDR3. The arithmetic is that of the software model in fpgarast.c, bit for
//  bit; sim/tb_rast.sv checks it against traces of the model.
//
//  A span (one scanline of a triangle) is processed as
//    1. burst read of the depth words under the span into a line buffer
//    2. the pixels, one after the other: depth test, texel and shade table
//       lookups through a cache of 64 bit memory words, results collected in
//       colour and depth line buffers with byte enables
//    3. burst writes of the depth and colour words, skipped if no pixel passed
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//============================================================================

module dethrace_rast
(
	input             clk,
	input             reset,

	// command words, head first
	input      [31:0] cmd_data,
	input             cmd_valid,
	output            cmd_ready,
	output            idle,

	// memory: 64 bit words, word address inside the rasteriser's region
	// (Avalon-MM as on the MiSTer DDR3 port: a beat is taken when !mem_busy)
	input             mem_busy,
	output reg [20:0] mem_addr,
	output reg  [7:0] mem_burstcnt,
	output reg        mem_rd,
	input      [63:0] mem_dout,
	input             mem_dout_ready,
	output     [63:0] mem_din,
	output      [7:0] mem_be,
	output reg        mem_we
);

localparam [7:0] OP_TARGET = 8'd1;
localparam [7:0] OP_TRI    = 8'd2;
localparam [7:0] OP_PTRI   = 8'd3;
localparam [7:0] OP_FLUSH  = 8'd4;
localparam [7:0] OP_FILL   = 8'd5;
localparam [7:0] OP_ATRI   = 8'd6;
localparam [7:0] OP_FOG    = 8'd7;

localparam [7:0] MAX_BURST = 8'd64;

//////////////////////////////////////////////////////////////////
// Command registers

reg  [7:0] op;
reg  [7:0] words;
reg  [7:0] wi;              // index of the next word
reg  [3:0] fi;              // optional field index of the next word (FR_OP_TRI)

reg        f_rl, f_i, f_t;
reg        f_p;             // perspective triangle (FR_OP_PTRI)
reg        f_a;             // arbitrary width texture (FR_OP_ATRI)
reg        f_g;             // fog pass (FR_OP_FOG): rows as spans, colour read as well
reg  [3:0] f_pow2;
wire       f_flat = !f_i && !f_t;

reg [23:0] colour_stride, depth_stride;

reg [23:0] scan, zscan;
reg [31:0] xm, d_xm, xm_f, d_xm_f;
reg [31:0] x1, d_x1, x2, d_x2;
reg [15:0] top_count, bottom_count;
reg [31:0] s_z, d_z_x, d_z_y_0, d_z_y_1;
reg [31:0] s_i, d_i_x, d_i_y_0, d_i_y_1;
reg [31:0] s_u, d_u_x, d_u_y_0, d_u_y_1;
reg [31:0] s_v, d_v_x, d_v_y_0, d_v_y_1;
reg  [7:0] flat_colour;

// FR_OP_PTRI keeps its state in the registers above where the meaning is the
// same (xm = main edge, d_z_x = dz, d_i_x = di, s_u/d_u_x/d_u_y_0 = u and its
// gradient and nocarry delta, likewise v) and adds the denominator and the
// texel of the scanline start
// FR_OP_ATRI likewise: s_u/d_u_x/d_u_y_0/d_u_y_1 = su/dux/duy0/duy1,
// s_v/d_v_x/d_v_y_0/d_v_y_1 = sv/dvx/dvy0/dvy1
reg [31:0] a_svf, a_dvxc, a_dvxf, a_dvy0c, a_dvy1c, a_dvy0f, a_dvy1f;
reg [31:0] a_ubound, a_vbound, a_size;

// FR_OP_FOG (shade_addr is its table)
reg  [9:0] fg_width_m1;
reg [15:0] fg_rows, fg_start, fg_near;
reg  [5:0] fg_shift;

reg [31:0] pq, q_grad, q_nocarry, q_carry;
reg  [7:0] tu, tv;
reg [16:0] norm_u_steps, norm_v_steps;
reg [23:0] tex_addr, shade_addr;

//////////////////////////////////////////////////////////////////
// Line buffers
//
// zline: depth words read from memory. wz/wc: depth and colour words to
// write, with byte enables. Read addresses are presented one clock early so
// the outputs always belong to the current index.

localparam LB = 9;          // line buffers hold up to 512 words (spans up to 1024 pixels)

reg [63:0] zline[0:(1<<LB)-1];
reg [63:0] zline_q;
wire       zline_we;
reg [LB-1:0] zr_idx;
wire [LB-1:0] zr_next;

// cline: colour words read from memory (fog only)
reg [63:0] cline[0:(1<<LB)-1];
reg [63:0] cline_q;
wire       cline_we;
reg [LB-1:0] cr_idx;
wire [LB-1:0] cr_next;

reg [71:0] wz[0:(1<<LB)-1];
reg [71:0] wc[0:(1<<LB)-1];
reg [71:0] wz_q, wc_q;
reg [LB-1:0] wz_waddr, wc_waddr;
reg [71:0] wz_wdata, wc_wdata;
reg        wz_we, wc_we;
reg [LB-1:0] wr_idx;        // word being written to memory
wire [LB-1:0] wr_next;

always @(posedge clk) begin
	if (zline_we) zline[zrecv[LB-1:0]] <= mem_dout;
	zline_q <= zline[zr_next];
	if (cline_we) cline[crecv[LB-1:0]] <= mem_dout;
	cline_q <= cline[cr_next];
	if (wz_we) wz[wz_waddr] <= wz_wdata;
	if (wc_we) wc[wc_waddr] <= wc_wdata;
	wz_q <= wz[wr_next];
	wc_q <= wc[wr_next];
end

//////////////////////////////////////////////////////////////////
// Memory word caches: one for textures (two ways of 2^CB words, index =
// word address [CB-1:0], the way not used last is replaced) and a direct
// mapped one for shade and fog tables (index [CS-1:0]), so that the texel
// and the table entry of a pixel never push each other out

localparam CB = 14;
localparam CS = 13;

reg [63:0] cache_data0[0:(1<<CB)-1];
reg [63:0] cache_data1[0:(1<<CB)-1];
reg [21-CB:0] cache_tag0[0:(1<<CB)-1];  // {valid, word address [20:CB]}
reg [21-CB:0] cache_tag1[0:(1<<CB)-1];
reg        cache_lru[0:(1<<CB)-1];       // the way to replace
reg [63:0] scache_data[0:(1<<CS)-1];
reg [21-CS:0] scache_tag[0:(1<<CS)-1];
reg [63:0] cache_data_q, cache_ram_data0, cache_ram_data1, scache_ram_data, cache_byp_data;
reg [21-CB:0] cache_ram_tag0, cache_ram_tag1;
reg [21-CS:0] scache_ram_tag;
reg        cache_lru_q;
reg        cache_bypass;
reg [20:0] cache_addr;                   // word address looked up
reg        cache_table;                  // in the table cache
reg        cache_we;                     // write the word at cache_waddr
reg        cache_wtable;
reg        cache_wway;
reg        cache_wvalid;
reg [20:0] cache_waddr;
reg [63:0] cache_wdata;
reg [20:0] lookup_word;                  // comb: word address to look up next
reg        lookup_table;                 // comb: in the table cache

wire cache_hit0 = (cache_ram_tag0 == {1'b1, cache_addr[20:CB]});
wire cache_hit1 = (cache_ram_tag1 == {1'b1, cache_addr[20:CB]});

always @(posedge clk) begin
	if (cache_we && !cache_wtable && !cache_wway) begin
		cache_data0[cache_waddr[CB-1:0]] <= cache_wdata;
		cache_tag0[cache_waddr[CB-1:0]]  <= {cache_wvalid, cache_waddr[20:CB]};
	end
	if (cache_we && !cache_wtable && cache_wway) begin
		cache_data1[cache_waddr[CB-1:0]] <= cache_wdata;
		cache_tag1[cache_waddr[CB-1:0]]  <= {cache_wvalid, cache_waddr[20:CB]};
	end
	if (cache_we && cache_wtable) begin
		scache_data[cache_waddr[CS-1:0]] <= cache_wdata;
		scache_tag[cache_waddr[CS-1:0]]  <= {cache_wvalid, cache_waddr[20:CS]};
	end
	// a way just written or just hit is not the one to replace
	if (cache_we && !cache_wtable) cache_lru[cache_waddr[CB-1:0]] <= !cache_wway;
	else if (!cache_table && (cache_hit0 || cache_hit1)) cache_lru[cache_addr[CB-1:0]] <= cache_hit0;

	cache_ram_data0 <= cache_data0[lookup_word[CB-1:0]];
	cache_ram_data1 <= cache_data1[lookup_word[CB-1:0]];
	cache_ram_tag0  <= cache_tag0[lookup_word[CB-1:0]];
	cache_ram_tag1  <= cache_tag1[lookup_word[CB-1:0]];
	cache_lru_q     <= cache_lru[lookup_word[CB-1:0]];
	scache_ram_data <= scache_data[lookup_word[CS-1:0]];
	scache_ram_tag  <= scache_tag[lookup_word[CS-1:0]];
	// the word written is the word looked up
	cache_bypass    <= cache_we && cache_wvalid && (cache_wtable == lookup_table) && (cache_waddr == lookup_word);
	cache_byp_data  <= cache_wdata;
end

reg cache_ram_hit;
always_comb begin
	if (cache_table) begin
		cache_data_q  = scache_ram_data;
		cache_ram_hit = (scache_ram_tag == {1'b1, cache_addr[20:CS]});
	end else begin
		cache_data_q  = cache_hit0 ? cache_ram_data0 : cache_ram_data1;
		cache_ram_hit = cache_hit0 || cache_hit1;
	end
	if (cache_bypass) cache_data_q = cache_byp_data;
end

wire cache_hit = cache_bypass || cache_ram_hit;

//////////////////////////////////////////////////////////////////
// State

localparam M_CLEAR   = 0;   // invalidate the cache
localparam M_IDLE    = 1;
localparam M_LOAD    = 2;
localparam M_HALF    = 3;
localparam M_LINE    = 4;
localparam M_SPAN    = 5;
localparam M_ZREQ    = 6;
localparam M_ZWAIT   = 7;
localparam M_PIX0    = 8;
localparam M_PIX     = 9;   // depth test
localparam M_TEXEL   = 10;  // texel lookup result
localparam M_SHADE   = 11;  // shade table lookup result
localparam M_FILL    = 12;  // cache miss: read the word
localparam M_FILLW   = 13;
localparam M_WZ0     = 14;
localparam M_WZ      = 15;
localparam M_WC0     = 16;
localparam M_WC      = 17;
localparam M_STEP    = 18;
localparam M_WZP     = 19;
localparam M_PNORM   = 20;  // perspective: bring u and v into 0..q
localparam M_FL0     = 21;  // FR_OP_FILL: one row
localparam M_FL1     = 22;
localparam M_FL2     = 23;
localparam M_AWRAP   = 24;  // FR_OP_ATRI: wrap u and v
localparam M_ASTORE  = 25;
localparam M_FOGROW  = 26;  // FR_OP_FOG: next row
localparam M_CREQ    = 27;  // colour words under the row
localparam M_CWAIT   = 28;

reg  [4:0] state = M_CLEAR;
reg  [4:0] fill_return;
reg [CB+1:0] clear_idx = 0;

assign cmd_ready = (state == M_IDLE) || (state == M_LOAD);
assign idle = (state == M_IDLE) && !cmd_valid;

reg        half;                    // 0 = top, 1 = bottom trapezium
reg [31:0] minor, d_minor;
reg [16:0] count;                   // signed scanline counter

// span geometry
wire [15:0] x_major = f_p ? xm[15:0] : xm[31:16];
wire [15:0] x_minor = minor[31:16];
wire [16:0] span_n  = {1'b0, x_major} - {1'b0, x_minor};      // signed
wire        span_draw = f_rl ? !span_n[16] : (span_n[16] || span_n == 0);
wire [15:0] x_left  = f_rl ? x_minor : x_major;
wire [16:0] span_abs = span_n[16] ? -span_n : span_n;

reg  [9:0] len_m1;                  // pixels in the span - 1
reg  [9:0] pos;                     // pixel position from the left
reg  [9:0] left;                    // pixels left after this one
reg [20:0] zw0, cw0;                // first depth / colour word address
reg  [1:0] zlane0;                  // depth lane of the leftmost pixel
reg  [2:0] clane0;                  // byte lane of the leftmost pixel
reg [LB-1:0] zwords_m1, cwords_m1;  // words under the span - 1
reg [LB:0] zreq;                    // depth words requested so far
reg [LB:0] zrecv;                   // depth words received so far
reg [LB:0] zburst_end;
reg [LB:0] creq, crecv, cburst_end; // the same for the colour words of a fog row
reg  [7:0] wburst_left;             // beats left in the current write burst

wire [10:0] span_zend = {9'd0, zlane0} + {1'b0, len_m1};      // lane of the rightmost pixel
wire [10:0] span_cend = {8'd0, clane0} + {1'b0, len_m1};
wire [23:0] cleft = scan + {8'd0, x_left};
assign zline_we = (state == M_ZWAIT) && mem_dout_ready;
assign cline_we = (state == M_CWAIT) && mem_dout_ready;
wire [23:0] zleft = zscan + {7'd0, x_left, 1'b0};

// position of the current pixel in the line buffers: depth in 16 bit
// lanes, colour in bytes
wire [10:0] zpos = {9'd0, zlane0} + {1'b0, pos};
wire [10:0] cpos = {8'd0, clane0} + {1'b0, pos};
wire [LB-1:0] zword = zpos[10:2];
wire  [1:0] zlane = zpos[1:0];
wire [LB-1:0] cword = {1'b0, cpos[10:3]};
wire  [2:0] clane = cpos[2:0];

// the same for the next pixel
wire  [9:0] pos_next = f_rl ? pos - 1'd1 : pos + 1'd1;
wire [10:0] zpos_next = {9'd0, zlane0} + {1'b0, pos_next};
wire [10:0] cpos_next = {8'd0, clane0} + {1'b0, pos_next};

//////////////////////////////////////////////////////////////////
// Pixel datapath

reg [31:0] pz, pi, pu, pv;
reg        pcarry;

// FR_OP_ATRI: pu is u (16.16), pv the texture row offset, pcv its fraction
reg [31:0] pcv;
reg        a_first;         // first pixel of the span
reg        au_phase, av_phase;
reg [16:0] au_left, av_left;
reg  [4:0] awrap_return, step_next;

wire [32:0] acv_add = {1'b0, pcv} + {1'b0, a_dvxf};
wire        acv_borrow = (pcv < a_dvxf);

// wrapping: up from below zero first, then down from the bound, never back
wire        av_neg = !av_phase && pv[31] && (av_left != 0);
wire        av_ge  = (pv >= a_vbound) && (av_left != 0);
wire        au_neg = !au_phase && pu[31] && (au_left != 0);
wire        au_ge  = ($signed(pu) >= $signed(a_ubound)) && (au_left != 0);

wire [15:0] z_old = zline_q[{zlane, 4'b0} +: 16];

// textured: z has its fraction in the upper half, the carry out of the
// fraction wraps around into the integer
wire [32:0] zt_add = {1'b0, pz} + {1'b0, d_z_x};
wire [31:0] zt_inc = zt_add[31:0] + {31'd0, zt_add[32]};
wire        zt_borrow = (pz < d_z_x);
wire [31:0] zt_dec = pz - d_z_x - {31'd0, zt_borrow};
wire        zt_pass = (pz[15:0] <= z_old);

// flat and Gouraud: the carry of a step is applied at the next pixel, the
// test compares all 32 bits with the buffered depth as the integer part
wire [31:0] zp_cur = f_rl ? pz - {31'd0, pcarry} : pz + {31'd0, pcarry};
wire        zp_pass = (zp_cur <= {pz[31:16], z_old});
wire [32:0] zp_add = {1'b0, zp_cur} + {1'b0, d_z_x};
wire        zp_borrow = (zp_cur < d_z_x);
wire [31:0] zp_sub = zp_cur - d_z_x;

// Gouraud intensity step, with its own end around carry
wire [32:0] gi_add = {1'b0, pi} + {1'b0, d_i_x};
wire [31:0] gi_inc = gi_add[31:0] + {31'd0, gi_add[32]};
wire        gi_borrow = (pi < d_i_x);
wire [31:0] gi_dec = pi - d_i_x - {31'd0, gi_borrow};
wire [31:0] gi_cur = f_rl ? gi_dec : gi_inc;

// start of span: step the intensity back one pixel
wire [31:0] si_rot = {s_i[15:0], s_i[31:16]};
wire        gp_borrow = (si_rot < d_i_x);
wire [31:0] gp_sub = si_rot - d_i_x;
wire [31:0] gp_dec = gp_sub - {31'd0, gp_borrow};
wire        gp_dec_carry = (gp_sub < {31'd0, gp_borrow});
wire [32:0] gp_add = {1'b0, si_rot} + {1'b0, d_i_x};
wire [32:0] gp_inc = {1'b0, gp_add[31:0]} + {32'd0, gp_add[32]};

// fog: table[(depth - start, shifted) & 0xFF00 | colour] for depths in range
wire  [7:0] c_old = cline_q[{clane, 3'b0} +: 8];
wire [15:0] fg_dv = z_old - fg_start;
wire        fg_pass = (z_old != 16'hFFFF) && (fg_dv < fg_near);
wire  [5:0] fg_shift_neg = -fg_shift;
wire [15:0] fg_index = fg_shift[5] ? fg_dv >> fg_shift_neg[4:0] : fg_dv << fg_shift[4:0];
wire [23:0] fg_addr = shade_addr + {8'd0, fg_index[15:8], c_old};

wire        pass = f_g ? fg_pass : f_a ? (pz[31:16] <= z_old) : f_t ? zt_pass : zp_pass;
wire [15:0] z_new = f_a ? pz[31:16] : f_t ? pz[15:0] : zp_cur[15:0];

// texel and shade table addresses
wire  [7:0] tmask = ~(8'hFF << f_pow2);
wire  [7:0] div_u, div_v, div_u_next, div_v_next;
wire        div_valid, div_next_valid;
wire  [7:0] tindex_u = f_p ? tu + div_u : pu[23:16];
wire  [7:0] tindex_v = f_p ? tv + div_v : pv[23:16];
wire [15:0] tindex = ({8'd0, tindex_v & tmask} << f_pow2) | {8'd0, tindex_u & tmask};
wire [23:0] taddr = f_a ? tex_addr + pv[23:0] + {a_first ? 8'd0 : {8{pu[31]}}, pu[31:16]} : tex_addr + {8'd0, tindex};
reg   [2:0] tlane, slane;
reg  [63:0] fill_word;
reg         use_fill;
wire [63:0] lookup_data = use_fill ? fill_word : cache_data_q;
wire        lookup_hit = use_fill || cache_hit;
wire  [7:0] texel = lookup_data[{tlane, 3'b0} +: 8];
wire [23:0] saddr = shade_addr + {8'd0, pi[23:16], texel};
wire  [7:0] shaded = lookup_data[{slane, 3'b0} +: 8];

// The texel of a pixel is looked up a clock ahead where its address is
// known: when the pixel before it finishes (the address of the next pixel),
// at the start of a span, or after the wrap of FR_OP_ATRI. tex_ready says
// the cache output belongs to the current pixel's texel.
reg         tex_ready;
wire [31:0] pu_n = f_rl ? pu - d_u_x : pu + d_u_x;
wire [31:0] pv_n = f_rl ? pv - d_v_x : pv + d_v_x;
wire  [7:0] tindex_u_n = f_p ? tu + div_u_next : pu_n[23:16];
wire  [7:0] tindex_v_n = f_p ? tv + div_v_next : pv_n[23:16];
wire [15:0] tindex_n = ({8'd0, tindex_v_n & tmask} << f_pow2) | {8'd0, tindex_u_n & tmask};
wire [23:0] taddr_n = tex_addr + {8'd0, tindex_n};
wire        next_known = !f_a && (!f_p || div_next_valid);
wire        cur_known = !f_p || div_valid;

wire        tp_miss  = pass && !lookup_hit;
wire        tp_zero  = pass && lookup_hit && (texel == 0);
wire        tp_shade = pass && lookup_hit && (texel != 0) && f_i;
wire        tp_draw  = pass && lookup_hit && (texel != 0) && !f_i;
wire        awrap_done = !av_neg && !av_ge && !au_neg && !au_ge;

reg  [23:0] look;
reg         look_valid, look_tex;
always_comb begin
	look = taddr;
	look_valid = 0;
	look_tex = 0;
	case (state)
		M_PIX0: if (f_t && !f_g && cur_known) begin
			look_valid = 1;
			look_tex = 1;
		end
		M_PIX: begin
			if (f_g) begin
				look = fg_addr;
				look_valid = 1;
			end
			else if (f_t) begin
				if (!tex_ready) begin
					look_valid = cur_known;
					look_tex = cur_known;
				end
				else if (tp_shade) begin
					look = saddr;
					look_valid = 1;
				end
				else if (commit && !last_pixel && next_known) begin
					look = taddr_n;
					look_valid = 1;
					look_tex = 1;
				end
			end
		end
		M_SHADE: if (commit && !last_pixel && !f_g && next_known) begin
			look = taddr_n;
			look_valid = 1;
			look_tex = 1;
		end
		M_AWRAP: if (awrap_done && awrap_return == M_PIX) begin
			look_valid = 1;
			look_tex = 1;
		end
		default: ;
	endcase
	lookup_word = look_valid ? look[23:3] : cache_addr;
	lookup_table = look_valid ? !look_tex : cache_table;
end

//////////////////////////////////////////////////////////////////
// Perspective
//
// At the start of a scanline u and v are brought into 0..q by stepping the
// texel, one step per clock. Along the scanline the texel of a pixel is
// that texel plus floor(u/q), floor(v/q): the divider below runs ahead of
// the pixels and queues the quotients.

wire        q_positive = !pq[31] && (pq != 0);
wire        nu_down = q_positive && ($signed(s_u) >= $signed(pq)) && (norm_u_steps != 0);
wire        nu_up   = q_positive && s_u[31] && (norm_u_steps != 0);
wire        nv_down = q_positive && ($signed(s_v) >= $signed(pq)) && (norm_v_steps != 0);
wire        nv_up   = q_positive && s_v[31] && (norm_v_steps != 0);

reg         div_start;
wire        div_pop;

dethrace_rast_div div
(
	.clk(clk),
	.reset(reset),
	.start(div_start),
	.backwards(f_rl),
	.pixels({1'b0, len_m1} + 1'd1),
	.u(s_u), .v(s_v), .q(pq),
	.u_grad(d_u_x), .v_grad(d_v_x), .q_grad(q_grad),
	.quot_u(div_u), .quot_v(div_v),
	.valid(div_valid),
	.quot_u_next(div_u_next), .quot_v_next(div_v_next),
	.next_valid(div_next_valid),
	.pop(div_pop)
);

//////////////////////////////////////////////////////////////////
// Write line buffers: the word under the current pixel is collected in
// registers and stored when the span moves on to the next word

reg [63:0] zacc, cacc;
reg  [7:0] zacc_be, cacc_be;
reg        span_dirty;

reg        commit;          // comb: the current pixel is finished
reg        commit_write;    // comb: and it is drawn
reg  [7:0] commit_colour;

wire [63:0] zacc_m = commit_write ? (zacc & ~(64'hFFFF << {zlane, 4'b0})) | ({48'd0, z_new} << {zlane, 4'b0}) : zacc;
wire  [7:0] zacc_be_m = (commit_write && !f_g) ? zacc_be | (8'h03 << {zlane, 1'b0}) : zacc_be;
wire [63:0] cacc_m = commit_write ? (cacc & ~(64'hFF << {clane, 3'b0})) | ({56'd0, commit_colour} << {clane, 3'b0}) : cacc;
wire  [7:0] cacc_be_m = commit_write ? cacc_be | (8'h01 << clane) : cacc_be;

assign div_pop = commit && f_p;

wire last_pixel = (left == 0);
wire z_leave = last_pixel || (zpos_next[10:2] != zpos[10:2]);
wire c_leave = last_pixel || (cpos_next[10:3] != cpos[10:3]);

assign zr_next = (state == M_PIX0) ? zword : (commit && !last_pixel) ? zpos_next[10:2] : zr_idx;
assign cr_next = (state == M_PIX0) ? cword : (commit && !last_pixel) ? {1'b0, cpos_next[10:3]} : cr_idx;

//////////////////////////////////////////////////////////////////
// FR_OP_FILL: rows of the pattern, the first and last word of a row masked

reg [23:0] fl_addr, fl_stride;
reg [12:0] fl_bytes;
reg [15:0] fl_rows, fl_pat;
wire [23:0] fl_end = fl_addr + {11'd0, fl_bytes} - 1'd1;
reg  [LB-1:0] fl_words_m1;
reg  [7:0] fl_be_first, fl_be_last;
wire       filling = (state == M_FL1) || (state == M_FL2);
wire [7:0] fl_be = ((wr_idx == 0) ? fl_be_first : 8'hFF) & ((wr_idx == fl_words_m1) ? fl_be_last : 8'hFF);

//////////////////////////////////////////////////////////////////
// Memory write bursts

wire wr_beat = mem_we && !mem_busy;
assign wr_next = wr_beat ? wr_idx + 1'd1 : wr_idx;
wire wr_colour = (state == M_WC0) || (state == M_WC);
assign mem_din = filling ? {4{fl_pat}} : wr_colour ? wc_q[63:0] : wz_q[63:0];
assign mem_be  = filling ? fl_be : wr_colour ? wc_q[71:64] : wz_q[71:64];

//////////////////////////////////////////////////////////////////
// Per scanline deltas: the carry out of the major edge fraction selects them

wire [32:0] xm_f_add = {1'b0, xm_f} + {1'b0, d_xm_f};
wire        line_carry = xm_f_add[32];
wire [31:0] dzy = line_carry ? d_z_y_1 : d_z_y_0;
wire [32:0] sz_add = {1'b0, s_z} + {1'b0, dzy};

// FR_OP_ATRI: the carry out of the v fraction selects a second set of v deltas
wire [32:0] asvf_add = {1'b0, a_svf} + {1'b0, line_carry ? a_dvy1f : a_dvy0f};
wire [31:0] asv_delta = line_carry ? (asvf_add[32] ? a_dvy1c : d_v_y_1) : (asvf_add[32] ? a_dvy0c : d_v_y_0);

// perspective: the main edge has its fraction in the upper half
wire [32:0] pm_add = {1'b0, xm} + {1'b0, d_xm};
wire        pline_carry = pm_add[32];

always_comb begin
	commit = 0;
	commit_write = 0;
	commit_colour = 0;
	case (state)
		M_PIX: begin
			if (f_g) begin
				if (!pass) commit = 1;
			end
			else if (!f_t) begin
				commit = 1;
				commit_write = pass;
				commit_colour = f_i ? gi_cur[7:0] : flat_colour;
			end
			else if (tex_ready) begin
				if (!pass || tp_zero) commit = 1;
				else if (tp_draw) begin
					commit = 1;
					commit_write = 1;
					commit_colour = texel;
				end
			end
		end
		M_SHADE: if (lookup_hit) begin
			commit = 1;
			commit_write = 1;
			commit_colour = shaded;
		end
		default: ;
	endcase
end

always @(posedge clk) begin
	wz_we <= 0;
	wc_we <= 0;
	cache_we <= 0;
	div_start <= 0;

	case (state)
		M_CLEAR: begin
			// both caches at once (the table cache more than once)
			cache_we     <= 1;
			cache_wtable <= clear_idx[0];
			cache_wway   <= clear_idx[1];
			cache_wvalid <= 0;
			cache_waddr  <= {{(21-CB){1'b0}}, clear_idx[CB+1:2]};
			clear_idx    <= clear_idx + 1'd1;
			if (&clear_idx) state <= M_IDLE;
		end

		M_IDLE: if (cmd_valid) begin
			op     <= cmd_data[7:0];
			words  <= cmd_data[15:8];
			f_rl   <= cmd_data[16] && (cmd_data[7:0] != OP_FOG);
			f_i    <= cmd_data[17] && (cmd_data[7:0] != OP_ATRI) && (cmd_data[7:0] != OP_FOG);
			f_t    <= cmd_data[18] || (cmd_data[7:0] == OP_PTRI) || (cmd_data[7:0] == OP_ATRI) || (cmd_data[7:0] == OP_FOG);
			f_g    <= (cmd_data[7:0] == OP_FOG);
			f_p    <= (cmd_data[7:0] == OP_PTRI);
			f_a    <= (cmd_data[7:0] == OP_ATRI);
			f_pow2 <= cmd_data[23:20];
			wi     <= 8'd1;
			fi     <= cmd_data[17] ? 4'd1 : cmd_data[18] ? 4'd5 : 4'd0;
			if (cmd_data[7:0] == OP_FLUSH) begin
				// texture memory changed: forget the cached words
				clear_idx <= 0;
				state     <= M_CLEAR;
			end
			else if (cmd_data[15:8] > 8'd1) state <= M_LOAD;
		end

		M_LOAD: if (cmd_valid) begin
			wi <= wi + 1'd1;
			if (op == OP_TARGET) begin
				if (wi == 8'd1) colour_stride <= cmd_data[23:0];
				if (wi == 8'd2) depth_stride  <= cmd_data[23:0];
			end
			if (op == OP_TRI) begin
				if (wi < 8'd16) begin
					case (wi[3:0])
						4'd1:  scan    <= cmd_data[23:0];
						4'd2:  zscan   <= cmd_data[23:0];
						4'd3:  xm      <= cmd_data;
						4'd4:  d_xm    <= cmd_data;
						4'd5:  xm_f    <= cmd_data;
						4'd6:  d_xm_f  <= cmd_data;
						4'd7:  x1      <= cmd_data;
						4'd8:  d_x1    <= cmd_data;
						4'd9:  x2      <= cmd_data;
						4'd10: d_x2    <= cmd_data;
						4'd11: {bottom_count, top_count} <= cmd_data;
						4'd12: s_z     <= cmd_data;
						4'd13: d_z_x   <= cmd_data;
						4'd14: d_z_y_0 <= cmd_data;
						4'd15: d_z_y_1 <= cmd_data;
						default: ;
					endcase
				end else begin
					case (fi)
						4'd0:  flat_colour <= cmd_data[7:0];
						4'd1:  s_i     <= cmd_data;
						4'd2:  d_i_x   <= cmd_data;
						4'd3:  d_i_y_0 <= cmd_data;
						4'd4:  d_i_y_1 <= cmd_data;
						4'd5:  s_u     <= cmd_data;
						4'd6:  d_u_x   <= cmd_data;
						4'd7:  d_u_y_0 <= cmd_data;
						4'd8:  d_u_y_1 <= cmd_data;
						4'd9:  s_v     <= cmd_data;
						4'd10: d_v_x   <= cmd_data;
						4'd11: d_v_y_0 <= cmd_data;
						4'd12: d_v_y_1 <= cmd_data;
						4'd13: tex_addr   <= cmd_data[23:0];
						4'd14: shade_addr <= cmd_data[23:0];
						default: ;
					endcase
					// the intensity block is followed by the texture block if there is one
					fi <= (fi == 4'd4 && !f_t) ? 4'd15 : fi + 1'd1;
				end
			end
			if (op == OP_PTRI) begin
				case (wi[4:0])
					5'd1:  scan    <= cmd_data[23:0];
					5'd2:  zscan   <= cmd_data[23:0];
					5'd3:  xm      <= cmd_data;
					5'd4:  d_xm    <= cmd_data;
					5'd5:  x1      <= cmd_data;
					5'd6:  d_x1    <= cmd_data;
					5'd7:  x2      <= cmd_data;
					5'd8:  d_x2    <= cmd_data;
					5'd9:  {bottom_count, top_count} <= cmd_data;
					5'd10: s_z     <= cmd_data;
					5'd11: d_z_y_0 <= cmd_data;
					5'd12: d_z_y_1 <= cmd_data;
					5'd13: d_z_x   <= cmd_data;
					5'd14: pq      <= cmd_data;
					5'd15: q_grad  <= cmd_data;
					5'd16: q_nocarry <= cmd_data;
					5'd17: q_carry <= cmd_data;
					5'd18: s_u     <= cmd_data;
					5'd19: d_u_x   <= cmd_data;
					5'd20: d_u_y_0 <= cmd_data;
					5'd21: s_v     <= cmd_data;
					5'd22: d_v_x   <= cmd_data;
					5'd23: d_v_y_0 <= cmd_data;
					5'd24: begin
						tu <= cmd_data[7:0];
						tv <= cmd_data[15:0] >> f_pow2;
					end
					5'd25: tex_addr <= cmd_data[23:0];
					5'd26: s_i     <= cmd_data;
					5'd27: d_i_y_0 <= cmd_data;
					5'd28: d_i_y_1 <= cmd_data;
					5'd29: d_i_x   <= cmd_data;
					5'd30: shade_addr <= cmd_data[23:0];
					default: ;
				endcase
			end
			if (op == OP_ATRI) begin
				case (wi[5:0])
					6'd1:  scan    <= cmd_data[23:0];
					6'd2:  zscan   <= cmd_data[23:0];
					6'd3:  xm      <= cmd_data;
					6'd4:  d_xm    <= cmd_data;
					6'd5:  xm_f    <= cmd_data;
					6'd6:  d_xm_f  <= cmd_data;
					6'd7:  x1      <= cmd_data;
					6'd8:  d_x1    <= cmd_data;
					6'd9:  x2      <= cmd_data;
					6'd10: d_x2    <= cmd_data;
					6'd11: {bottom_count, top_count} <= cmd_data;
					6'd12: s_z     <= cmd_data;
					6'd13: d_z_x   <= cmd_data;
					6'd14: d_z_y_0 <= cmd_data;
					6'd15: d_z_y_1 <= cmd_data;
					6'd16: s_u     <= cmd_data;
					6'd17: d_u_x   <= cmd_data;
					6'd18: d_u_y_0 <= cmd_data;
					6'd19: d_u_y_1 <= cmd_data;
					6'd20: s_v     <= cmd_data;
					6'd21: a_svf   <= cmd_data;
					6'd22: d_v_x   <= cmd_data;
					6'd23: a_dvxc  <= cmd_data;
					6'd24: a_dvxf  <= cmd_data;
					6'd25: d_v_y_0 <= cmd_data;
					6'd26: a_dvy0c <= cmd_data;
					6'd27: d_v_y_1 <= cmd_data;
					6'd28: a_dvy1c <= cmd_data;
					6'd29: a_dvy0f <= cmd_data;
					6'd30: a_dvy1f <= cmd_data;
					6'd31: a_ubound <= cmd_data;
					6'd32: a_vbound <= cmd_data;
					6'd33: a_size  <= cmd_data;
					6'd34: tex_addr <= cmd_data[23:0];
					default: ;
				endcase
			end
			if (op == OP_FOG) begin
				case (wi[3:0])
					4'd1: scan  <= cmd_data[23:0];
					4'd2: zscan <= cmd_data[23:0];
					4'd3: begin
						fg_width_m1 <= cmd_data[9:0] - 1'd1;
						fg_rows     <= cmd_data[31:16];
					end
					4'd4: colour_stride <= cmd_data[23:0];
					4'd5: depth_stride  <= cmd_data[23:0];
					4'd6: {fg_near, fg_start} <= cmd_data;
					4'd7: fg_shift   <= cmd_data[5:0];
					4'd8: shade_addr <= cmd_data[23:0];
					default: ;
				endcase
			end
			if (op == OP_FILL) begin
				case (wi[2:0])
					3'd1: fl_addr   <= cmd_data[23:0];
					3'd2: fl_bytes  <= cmd_data[12:0];
					3'd3: fl_rows   <= cmd_data[15:0];
					3'd4: fl_stride <= cmd_data[23:0];
					3'd5: fl_pat    <= cmd_data[15:0];
					default: ;
				endcase
			end
			if (wi + 1'd1 == words) begin
				half  <= 0;
				state <= (op == OP_TRI || op == OP_PTRI || op == OP_ATRI) ? M_HALF : (op == OP_FILL) ? M_FL0 : (op == OP_FOG) ? M_FOGROW : M_IDLE;
			end
		end

		M_HALF: begin
			minor   <= half ? x2 : x1;
			d_minor <= half ? d_x2 : d_x1;
			count   <= half ? {bottom_count[15], bottom_count} : {top_count[15], top_count};
			if (half ? bottom_count[15] : top_count[15]) begin
				// nothing in this half
				half  <= 1;
				state <= half ? M_IDLE : M_HALF;
			end else begin
				state <= M_LINE;
			end
		end

		M_LINE: begin
			len_m1    <= span_abs[9:0];
			left      <= span_abs[9:0];
			pos       <= f_rl ? span_abs[9:0] : 10'd0;
			zw0       <= zleft[23:3];
			zlane0    <= zleft[2:1];
			cw0       <= cleft[23:3];
			clane0    <= cleft[2:0];
			norm_u_steps <= 17'h10000;
			norm_v_steps <= 17'h10000;
			state     <= !span_draw ? M_STEP : f_p ? M_PNORM : M_SPAN;
		end

		M_PNORM: begin
			if (nu_down) begin
				tu      <= tu + 1'd1;
				d_u_x   <= d_u_x - q_grad;
				d_u_y_0 <= d_u_y_0 - q_nocarry;
				s_u     <= s_u - pq;
			end else if (nu_up) begin
				tu      <= tu - 1'd1;
				d_u_x   <= d_u_x + q_grad;
				d_u_y_0 <= d_u_y_0 + q_nocarry;
				s_u     <= s_u + pq;
			end
			if (nu_down || nu_up) norm_u_steps <= norm_u_steps - 1'd1;
			if (nv_down) begin
				tv      <= tv + 1'd1;
				d_v_x   <= d_v_x - q_grad;
				d_v_y_0 <= d_v_y_0 - q_nocarry;
				s_v     <= s_v - pq;
			end else if (nv_up) begin
				tv      <= tv - 1'd1;
				d_v_x   <= d_v_x + q_grad;
				d_v_y_0 <= d_v_y_0 + q_nocarry;
				s_v     <= s_v + pq;
			end
			if (nv_down || nv_up) norm_v_steps <= norm_v_steps - 1'd1;
			if (!nu_down && !nu_up && !nv_down && !nv_up) begin
				div_start <= 1;
				state     <= M_SPAN;
			end
		end

		M_FOGROW: begin
			len_m1 <= fg_width_m1;
			left   <= fg_width_m1;
			pos    <= 0;
			zw0    <= zscan[23:3];
			zlane0 <= zscan[2:1];
			cw0    <= scan[23:3];
			clane0 <= scan[2:0];
			state  <= (fg_rows == 0) ? M_IDLE : M_SPAN;
		end

		M_SPAN: begin
			creq  <= 0;
			crecv <= 0;
			zwords_m1 <= span_zend[10:2];
			cwords_m1 <= {1'b0, span_cend[10:3]};
			zreq      <= 0;
			zrecv     <= 0;
			// first pixel
			pz <= f_a ? s_z : {s_z[15:0], s_z[31:16]};
			if (!f_p) begin
				pu <= s_u;
				pv <= s_v;
			end
			pcv     <= a_svf;
			a_first <= 1;
			if (f_t) begin
				pi     <= s_i;
				pcarry <= 0;
			end else if (!f_i) begin
				pcarry <= 0;
			end else if (!f_rl) begin
				pi     <= gp_dec;
				pcarry <= gp_dec_carry;
			end else begin
				pi     <= gp_inc[31:0];
				pcarry <= gp_inc[32];
			end
			zacc_be    <= 0;
			cacc_be    <= 0;
			zacc       <= 0;
			cacc       <= 0;
			span_dirty <= 0;
			state      <= M_ZREQ;
		end

		// depth words under the span, in bursts
		M_ZREQ: begin
			mem_rd       <= 1;
			mem_addr     <= zw0 + {{(21-LB-1){1'b0}}, zreq};
			if ({1'b0, zwords_m1} - zreq >= {1'b0, MAX_BURST}) begin
				mem_burstcnt <= MAX_BURST;
				zreq         <= zreq + MAX_BURST;
				zburst_end   <= zreq + MAX_BURST;
			end else begin
				mem_burstcnt <= zwords_m1 - zreq[LB-1:0] + 1'd1;
				zreq         <= {1'b0, zwords_m1} + 1'd1;
				zburst_end   <= {1'b0, zwords_m1} + 1'd1;
			end
			state <= M_ZWAIT;
		end

		M_ZWAIT: begin
			if (!mem_busy) mem_rd <= 0;
			if (mem_dout_ready) zrecv <= zrecv + 1'd1;
			if (zrecv == zburst_end && !mem_rd) begin
				state <= (zreq != {1'b0, zwords_m1} + 1'd1) ? M_ZREQ : f_g ? M_CREQ : M_PIX0;
			end
		end

		M_CREQ: begin
			mem_rd   <= 1;
			mem_addr <= cw0 + {{(21-LB-1){1'b0}}, creq};
			if ({1'b0, cwords_m1} - creq >= {1'b0, MAX_BURST}) begin
				mem_burstcnt <= MAX_BURST;
				creq         <= creq + MAX_BURST;
				cburst_end   <= creq + MAX_BURST;
			end else begin
				mem_burstcnt <= cwords_m1 - creq[LB-1:0] + 1'd1;
				creq         <= {1'b0, cwords_m1} + 1'd1;
				cburst_end   <= {1'b0, cwords_m1} + 1'd1;
			end
			state <= M_CWAIT;
		end

		M_CWAIT: begin
			if (!mem_busy) mem_rd <= 0;
			if (mem_dout_ready) crecv <= crecv + 1'd1;
			if (crecv == cburst_end && !mem_rd) begin
				state <= (creq != {1'b0, cwords_m1} + 1'd1) ? M_CREQ : M_PIX0;
			end
		end

		// the depth word of the first pixel appears on zline_q
		M_PIX0: begin
			cr_idx <= cword;
			zr_idx <= zword;
			state  <= M_PIX;
		end

		M_PIX: begin
			if (f_g) begin
				if (pass) state <= M_SHADE;
			end
			else if (f_t && tex_ready) begin
				if (tp_miss) begin
					fill_return <= M_PIX;
					state       <= M_FILL;
				end
				else if (tp_shade) begin
					use_fill <= 0;
					state    <= M_SHADE;
				end
			end
		end

		M_SHADE: begin
			if (!lookup_hit) begin
				fill_return <= M_SHADE;
				state       <= M_FILL;
			end
		end

		M_FILL: begin
			mem_rd       <= 1;
			mem_addr     <= cache_addr;
			mem_burstcnt <= 8'd1;
			state        <= M_FILLW;
		end

		M_FILLW: begin
			if (!mem_busy) mem_rd <= 0;
			if (mem_dout_ready) begin
				fill_word   <= mem_dout;
				use_fill    <= 1;
				cache_we     <= 1;
				cache_wtable <= cache_table;
				cache_wway   <= cache_lru_q;
				cache_wvalid <= 1;
				cache_waddr  <= cache_addr;
				cache_wdata  <= mem_dout;
				state       <= fill_return;
			end
		end

		// depth then colour, only if a pixel was drawn. M_WZP lets the last
		// line buffer word land before it is read back.
		M_WZP: state <= f_g ? M_WC0 : M_WZ0;

		M_WZ0: begin
			mem_we       <= 1;
			mem_addr     <= zw0 + {{(21-LB){1'b0}}, wr_idx};
			mem_burstcnt <= (zwords_m1 - wr_idx >= {1'b0, MAX_BURST}) ? MAX_BURST : zwords_m1[7:0] - wr_idx[7:0] + 1'd1;
			wburst_left  <= (zwords_m1 - wr_idx >= {1'b0, MAX_BURST}) ? MAX_BURST : zwords_m1[7:0] - wr_idx[7:0] + 1'd1;
			state        <= M_WZ;
		end

		M_WZ: if (wr_beat) begin
			wr_idx      <= wr_idx + 1'd1;
			wburst_left <= wburst_left - 1'd1;
			if (wburst_left == 8'd1) begin
				mem_we <= 0;
				if (wr_idx == zwords_m1) begin
					wr_idx <= 0;
					state  <= M_WC0;
				end else begin
					state  <= M_WZ0;
				end
			end
		end

		M_WC0: begin
			mem_we       <= 1;
			mem_addr     <= cw0 + {{(21-LB){1'b0}}, wr_idx};
			mem_burstcnt <= (cwords_m1 - wr_idx >= {1'b0, MAX_BURST}) ? MAX_BURST : cwords_m1[7:0] - wr_idx[7:0] + 1'd1;
			wburst_left  <= (cwords_m1 - wr_idx >= {1'b0, MAX_BURST}) ? MAX_BURST : cwords_m1[7:0] - wr_idx[7:0] + 1'd1;
			state        <= M_WC;
		end

		M_WC: if (wr_beat) begin
			wr_idx      <= wr_idx + 1'd1;
			wburst_left <= wburst_left - 1'd1;
			if (wburst_left == 8'd1) begin
				mem_we <= 0;
				state  <= (wr_idx == cwords_m1) ? M_STEP : M_WC0;
			end
		end

		M_FL0: begin
			fl_words_m1 <= fl_end[3+LB-1:3] - fl_addr[3+LB-1:3];
			fl_be_first <= 8'hFF << fl_addr[2:0];
			fl_be_last  <= 8'hFF >> (3'd7 - fl_end[2:0]);
			wr_idx      <= 0;
			state       <= (fl_rows == 0 || fl_bytes == 0) ? M_IDLE : M_FL1;
		end

		M_FL1: begin
			mem_we       <= 1;
			mem_addr     <= fl_addr[23:3] + {{(21-LB){1'b0}}, wr_idx};
			mem_burstcnt <= (fl_words_m1 - wr_idx >= {1'b0, MAX_BURST}) ? MAX_BURST : fl_words_m1[7:0] - wr_idx[7:0] + 1'd1;
			wburst_left  <= (fl_words_m1 - wr_idx >= {1'b0, MAX_BURST}) ? MAX_BURST : fl_words_m1[7:0] - wr_idx[7:0] + 1'd1;
			state        <= M_FL2;
		end

		M_FL2: if (wr_beat) begin
			wburst_left <= wburst_left - 1'd1;
			if (wburst_left == 8'd1) begin
				mem_we <= 0;
				if (wr_idx != fl_words_m1) begin
					wr_idx <= wr_idx + 1'd1;
					state  <= M_FL1;
				end else begin
					fl_addr <= fl_addr + fl_stride;
					fl_rows <= fl_rows - 1'd1;
					state   <= (fl_rows == 16'd1) ? M_IDLE : M_FL0;
				end
			end else begin
				wr_idx <= wr_idx + 1'd1;
			end
		end

		// next scanline
		// FR_OP_ATRI: one correction per clock until u and v are in range
		M_AWRAP: begin
			if (av_neg) begin
				pv      <= pv + a_size;
				av_left <= av_left - 1'd1;
			end else if (av_ge) begin
				pv       <= pv - a_size;
				av_phase <= 1;
				av_left  <= av_left - 1'd1;
			end
			if (au_neg) begin
				pu      <= pu + a_ubound;
				au_left <= au_left - 1'd1;
			end else if (au_ge) begin
				pu       <= pu - a_ubound;
				au_phase <= 1;
				au_left  <= au_left - 1'd1;
			end
			if (awrap_done) state <= awrap_return;
		end

		// u and v of the next scanline, wrapped
		M_ASTORE: begin
			s_u   <= pu;
			s_v   <= pv;
			state <= step_next;
		end

		M_STEP: if (f_g) begin
			scan    <= scan + colour_stride;
			zscan   <= zscan + depth_stride;
			fg_rows <= fg_rows - 1'd1;
			state   <= (fg_rows == 16'd1) ? M_IDLE : M_FOGROW;
		end else begin
			if (f_a) begin
				xm_f  <= xm_f_add[31:0];
				s_z   <= sz_add[31:0];
				a_svf <= asvf_add[31:0];
				pu    <= s_u + (line_carry ? d_u_y_1 : d_u_y_0);
				pv    <= s_v + asv_delta;
				xm    <= xm + d_xm;
			end else if (!f_p) begin
				xm_f <= xm_f_add[31:0];
				s_z  <= f_flat ? sz_add[31:0] + {31'd0, sz_add[32]} : sz_add[31:0];
				s_i  <= s_i + (line_carry ? d_i_y_1 : d_i_y_0);
				s_u  <= s_u + (line_carry ? d_u_y_1 : d_u_y_0);
				s_v  <= s_v + (line_carry ? d_v_y_1 : d_v_y_0);
				xm   <= xm + d_xm;
			end else begin
				// u and v have no carry delta of their own: nocarry + one step along x
				xm   <= pm_add[31:0] + {31'd0, pline_carry};
				pq   <= pq + (pline_carry ? q_carry : q_nocarry);
				s_z  <= s_z + (pline_carry ? d_z_y_1 : d_z_y_0);
				s_i  <= s_i + (pline_carry ? d_i_y_1 : d_i_y_0);
				s_u  <= s_u + d_u_y_0 + (pline_carry ? d_u_x : 32'd0);
				s_v  <= s_v + d_v_y_0 + (pline_carry ? d_v_x : 32'd0);
			end
			scan  <= scan + colour_stride;
			zscan <= zscan + depth_stride;
			minor <= minor + d_minor;
			count <= count - 1'd1;
			if (count == 0) half <= 1;
			if (f_a) begin
				au_phase     <= 0;
				av_phase     <= 0;
				au_left      <= 17'h10000;
				av_left      <= 17'h10000;
				awrap_return <= M_ASTORE;
				step_next    <= (count != 0) ? M_LINE : half ? M_IDLE : M_HALF;
				state        <= M_AWRAP;
			end
			else if (count == 0) state <= half ? M_IDLE : M_HALF;
			else state <= M_LINE;
		end

		default: state <= M_IDLE;
	endcase

	// a finished pixel: collect it and move on
	if (commit) begin
		zacc    <= zacc_m;
		zacc_be <= zacc_be_m;
		cacc    <= cacc_m;
		cacc_be <= cacc_be_m;
		if (commit_write) span_dirty <= 1;
		if (z_leave) begin
			wz_we    <= 1;
			wz_waddr <= zword;
			wz_wdata <= {zacc_be_m, zacc_m};
			zacc     <= 0;
			zacc_be  <= 0;
		end
		if (c_leave) begin
			wc_we    <= 1;
			wc_waddr <= cword;
			wc_wdata <= {cacc_be_m, cacc_m};
			cacc     <= 0;
			cacc_be  <= 0;
		end

		// interpolants of the next pixel
		a_first <= 0;
		if (f_a) begin
			pz  <= f_rl ? pz - d_z_x : pz + d_z_x;
			pu  <= f_rl ? pu - d_u_x : pu + d_u_x;
			pcv <= f_rl ? pcv - a_dvxf : acv_add[31:0];
			pv  <= f_rl ? pv - (acv_borrow ? a_dvxc : d_v_x) : pv + (acv_add[32] ? a_dvxc : d_v_x);
			au_phase     <= 0;
			av_phase     <= 0;
			au_left      <= 17'h10000;
			av_left      <= 17'h10000;
			awrap_return <= M_PIX;
		end else if (f_t) begin
			pz <= f_rl ? zt_dec : zt_inc;
			pi <= f_rl ? pi - d_i_x : pi + d_i_x;
			pu <= f_rl ? pu - d_u_x : pu + d_u_x;
			pv <= f_rl ? pv - d_v_x : pv + d_v_x;
		end else begin
			pz     <= f_rl ? zp_sub : zp_add[31:0];
			pcarry <= f_rl ? zp_borrow : zp_add[32];
			if (f_i) pi <= gi_cur;
		end

		pos    <= pos_next;
		left   <= left - 1'd1;
		zr_idx <= zr_next;
		cr_idx <= cr_next;
		if (last_pixel) begin
			wr_idx <= 0;
			state  <= (span_dirty || commit_write) ? M_WZP : M_STEP;
		end else begin
			state  <= f_a ? M_AWRAP : M_PIX;
		end
		tex_ready <= 0;
		use_fill  <= 0;
	end

	// lookups started this clock
	if (look_valid) begin
		cache_addr  <= look[23:3];
		cache_table <= !look_tex;
		if (look_tex) begin
			tlane     <= look[2:0];
			tex_ready <= 1;
		end else begin
			slane     <= look[2:0];
		end
	end
	if (state == M_SPAN) begin
		tex_ready <= 0;
		use_fill  <= 0;
	end

	if (reset) begin
		state     <= M_CLEAR;
		clear_idx <= 0;
		mem_rd    <= 0;
		mem_we    <= 0;
	end
end

endmodule

//============================================================================
//
//  Perspective divider: floor(u/q) and floor(v/q) for every pixel of a span,
//  queued in pixel order. Only the low 8 bits of the quotients are needed
//  (texel coordinates wrap at the texture size, 256 at most), but they are
//  those of a 16 bit signed quotient: beyond +-32768 texels the result
//  saturates, and with q <= 0 it is 0, as in the software model.
//
//============================================================================

module dethrace_rast_div
(
	input             clk,
	input             reset,

	input             start,        // load a span; the previous one has been popped completely
	input             backwards,
	input      [10:0] pixels,
	input      [31:0] u, v, q,
	input      [31:0] u_grad, v_grad, q_grad,

	output      [7:0] quot_u,       // of the oldest pixel not popped yet
	output      [7:0] quot_v,
	output            valid,
	output      [7:0] quot_u_next,  // of the pixel after it
	output      [7:0] quot_v_next,
	output            next_valid,
	input             pop
);

localparam N = 16;          // quotient bits
localparam FB = 5;          // queue of 32 pixels

// one pixel per clock while the queue has room for everything in flight
reg signed [47:0] gu, gv;
reg        [31:0] gq;
reg         [10:0] gleft = 0;
reg                gback;
reg signed [47:0] gdu, gdv;
reg        [31:0] gdq;
reg        [FB:0] outstanding = 0;
wire              issue = (gleft != 0) && !outstanding[FB];

// stage A: bias the numerators by 32768 * q so they are positive
reg               a_valid = 0;
reg signed [48:0] a_u, a_v;
reg        [31:0] a_q;

// stage B..: restoring division, one quotient bit per stage
reg        [N:0] d_valid = 0;
reg       [31:0] d_q[0:N];
reg       [31:0] d_ru[0:N], d_rv[0:N];
reg       [15:0] d_lu[0:N], d_lv[0:N];
reg        [7:0] d_qu[0:N], d_qv[0:N];
reg        [1:0] d_fu[0:N], d_fv[0:N];   // 1 = result 0, 2 = result saturated

wire              a_q_bad = a_q[31] || (a_q == 0);
wire       [32:0] su[0:N-1], sv[0:N-1], du[0:N-1], dv[0:N-1];

genvar g;
generate
	for (g = 0; g < N; g = g + 1) begin : stage
		assign su[g] = {d_ru[g], d_lu[g][15]};
		assign sv[g] = {d_rv[g], d_lv[g][15]};
		assign du[g] = su[g] - {1'b0, d_q[g]};
		assign dv[g] = sv[g] - {1'b0, d_q[g]};
	end
endgenerate

reg [15:0] fifo[0:(1<<FB)-1];
reg [FB-1:0] fifo_wr = 0, fifo_rd = 0;
reg [FB:0] fifo_count = 0;

assign valid = (fifo_count != 0);
assign {quot_v, quot_u} = fifo[fifo_rd];
wire [FB-1:0] fifo_rd1 = fifo_rd + 1'd1;
assign next_valid = (fifo_count > 1);
assign {quot_v_next, quot_u_next} = fifo[fifo_rd1];

integer i;
always @(posedge clk) begin
	if (start) begin
		gu    <= {{16{u[31]}}, u};
		gv    <= {{16{v[31]}}, v};
		gq    <= q;
		gdu   <= {{16{u_grad[31]}}, u_grad};
		gdv   <= {{16{v_grad[31]}}, v_grad};
		gdq   <= q_grad;
		gback <= backwards;
		gleft <= pixels;
	end else if (issue) begin
		gu    <= gback ? gu - gdu : gu + gdu;
		gv    <= gback ? gv - gdv : gv + gdv;
		gq    <= gback ? gq - gdq : gq + gdq;
		gleft <= gleft - 1'd1;
	end

	a_valid <= issue && !start;
	a_u     <= {gu[47], gu} + $signed({2'b00, gq, 15'd0});
	a_v     <= {gv[47], gv} + $signed({2'b00, gq, 15'd0});
	a_q     <= gq;

	d_valid[0] <= a_valid;
	d_q[0]     <= a_q;
	d_ru[0]    <= a_u[47:16];
	d_rv[0]    <= a_v[47:16];
	d_lu[0]    <= a_u[15:0];
	d_lv[0]    <= a_v[15:0];
	d_fu[0]    <= (a_q_bad || a_u[48]) ? 2'd1 : (a_u[47:16] >= a_q) ? 2'd2 : 2'd0;
	d_fv[0]    <= (a_q_bad || a_v[48]) ? 2'd1 : (a_v[47:16] >= a_q) ? 2'd2 : 2'd0;

	for (i = 0; i < N; i = i + 1) begin
		d_valid[i+1] <= d_valid[i];
		d_q[i+1]     <= d_q[i];
		d_fu[i+1]    <= d_fu[i];
		d_fv[i+1]    <= d_fv[i];
		d_ru[i+1]    <= du[i][32] ? su[i][31:0] : du[i][31:0];
		d_rv[i+1]    <= dv[i][32] ? sv[i][31:0] : dv[i][31:0];
		d_lu[i+1]    <= {d_lu[i][14:0], 1'b0};
		d_lv[i+1]    <= {d_lv[i][14:0], 1'b0};
		d_qu[i+1]    <= {d_qu[i][6:0], !du[i][32]};
		d_qv[i+1]    <= {d_qv[i][6:0], !dv[i][32]};
	end

	if (d_valid[N]) begin
		fifo[fifo_wr] <= {d_fv[N] == 2'd1 ? 8'h00 : d_fv[N] == 2'd2 ? 8'hFF : d_qv[N],
		                  d_fu[N] == 2'd1 ? 8'h00 : d_fu[N] == 2'd2 ? 8'hFF : d_qu[N]};
		fifo_wr <= fifo_wr + 1'd1;
	end
	if (pop) fifo_rd <= fifo_rd + 1'd1;
	fifo_count  <= fifo_count + (d_valid[N] ? 1'd1 : 1'd0) - (pop ? 1'd1 : 1'd0);
	outstanding <= outstanding + ((issue && !start) ? 1'd1 : 1'd0) - (pop ? 1'd1 : 1'd0);

	if (reset) begin
		gleft       <= 0;
		a_valid     <= 0;
		d_valid     <= 0;
		fifo_wr     <= 0;
		fifo_rd     <= 0;
		fifo_count  <= 0;
		outstanding <= 0;
	end
end

endmodule
