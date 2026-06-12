module h264_core (
	clk,
	rst_n,
	in_valid,
	in_word,
	in_bytes,
	in_ready,
	cfg_mb_w,
	cfg_mb_h,
	cfg_qp,
	cfg_cqp_off,
	cfg_a_off,
	cfg_b_off,
	cfg_deblock,
	cfg_is_p,
	start,
	align_valid,
	align_bits,
	out_valid,
	out_mbx,
	out_mby,
	out_plane,
	out_row,
	out_data,
	mc_req_valid,
	mc_req_plane,
	mc_req_x,
	mc_req_y,
	mc_req_w,
	mc_rsp_valid,
	mc_rsp_data,
	frame_done,
	err
);
	parameter signed [31:0] MAX_MBW = 120;
	input wire clk;
	input wire rst_n;
	input wire in_valid;
	input wire [31:0] in_word;
	input wire [2:0] in_bytes;
	output wire in_ready;
	input wire [7:0] cfg_mb_w;
	input wire [7:0] cfg_mb_h;
	input wire [5:0] cfg_qp;
	input wire signed [5:0] cfg_cqp_off;
	input wire signed [5:0] cfg_a_off;
	input wire signed [5:0] cfg_b_off;
	input wire cfg_deblock;
	input wire cfg_is_p;
	input wire start;
	input wire align_valid;
	input wire [4:0] align_bits;
	output wire out_valid;
	output wire [7:0] out_mbx;
	output wire [7:0] out_mby;
	output wire [1:0] out_plane;
	output wire [3:0] out_row;
	output wire [127:0] out_data;
	output wire mc_req_valid;
	output wire [1:0] mc_req_plane;
	output wire signed [12:0] mc_req_x;
	output wire signed [11:0] mc_req_y;
	output wire [3:0] mc_req_w;
	input wire mc_rsp_valid;
	input wire [71:0] mc_rsp_data;
	output wire frame_done;
	output wire err;
	wire br_req_valid;
	wire [4:0] br_req_bits;
	wire br_req_ready;
	wire [23:0] show;
	wire [6:0] avail;
	wire m_req_valid;
	wire b_req_valid;
	wire [4:0] m_req_bits;
	wire [4:0] b_req_bits;
	assign br_req_valid = (align_valid | m_req_valid) | b_req_valid;
	assign br_req_bits = (align_valid ? align_bits : (b_req_valid ? b_req_bits : m_req_bits));
	bitreader u_br(
		.clk(clk),
		.rst_n(rst_n),
		.in_valid(in_valid),
		.in_word(in_word),
		.in_bytes(in_bytes),
		.in_ready(in_ready),
		.req_valid(br_req_valid),
		.req_bits(br_req_bits),
		.req_ready(br_req_ready),
		.show(show),
		.avail(avail)
	);
	wire blk_start;
	wire blk_chroma_dc;
	wire [1:0] blk_nc_class;
	wire [4:0] blk_maxc;
	wire blk_busy;
	wire blk_done;
	wire blk_err;
	wire [4:0] blk_tc;
	wire blk_coef_we;
	wire [3:0] blk_coef_addr;
	wire signed [15:0] blk_coef_data;
	cavlc_block u_blk(
		.clk(clk),
		.rst_n(rst_n),
		.req_valid(b_req_valid),
		.req_bits(b_req_bits),
		.req_ready(br_req_ready),
		.show(show),
		.avail(avail),
		.start(blk_start),
		.chroma_dc(blk_chroma_dc),
		.nc_class(blk_nc_class),
		.maxc(blk_maxc),
		.busy(blk_busy),
		.done(blk_done),
		.tc_out(blk_tc),
		.err(blk_err),
		.coef_we(blk_coef_we),
		.coef_addr(blk_coef_addr),
		.coef_data(blk_coef_data)
	);
	wire mb_valid;
	wire [7:0] mb_x;
	wire [7:0] mb_y;
	wire mb_i16;
	wire [5:0] mb_cbp;
	wire [5:0] mb_qp;
	wire [1:0] mb_i16_mode;
	wire [1:0] mb_cmode;
	wire [63:0] mb_i4m;
	wire coef_we;
	wire [4:0] coef_blk;
	wire [3:0] coef_addr;
	wire signed [15:0] coef_data;
	wire mb_err;
	wire rec_valid;
	wire rec_err;
	wire rec_accept;
	wire [7:0] rec_x;
	wire [7:0] rec_yc;
	wire [5:0] rec_qp;
	wire mb_skip;
	wire mb_inter;
	wire skip_go_w;
	wire mvd_valid;
	wire [15:0] mb_nz_w;
	wire [2:0] mb_ptype;
	wire [7:0] mb_sub;
	wire signed [15:0] mvd_x;
	wire signed [15:0] mvd_y;
	wire signed [255:0] mv_x_w;
	wire signed [255:0] mv_y_w;
	wire slice_done;
	mb_dec #(.MAX_MBW(MAX_MBW)) u_mb(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.cfg_mb_h(cfg_mb_h),
		.cfg_qp(cfg_qp),
		.cfg_is_p(cfg_is_p),
		.start(start),
		.req_valid(m_req_valid),
		.req_bits(m_req_bits),
		.req_ready(br_req_ready),
		.show(show),
		.avail(avail),
		.blk_start(blk_start),
		.blk_chroma_dc(blk_chroma_dc),
		.blk_nc_class(blk_nc_class),
		.blk_maxc(blk_maxc),
		.blk_busy(blk_busy),
		.blk_done(blk_done),
		.blk_err(blk_err),
		.blk_tc(blk_tc),
		.blk_coef_we(blk_coef_we),
		.blk_coef_addr(blk_coef_addr),
		.blk_coef_data(blk_coef_data),
		.mb_skip(mb_skip),
		.mb_inter(mb_inter),
		.mb_ptype(mb_ptype),
		.mb_sub(mb_sub),
		.mvd_valid(mvd_valid),
		.mvd_x(mvd_x),
		.mvd_y(mvd_y),
		.skip_go(skip_go_w),
		.mb_nz(mb_nz_w),
		.mb_valid(mb_valid),
		.mb_x(mb_x),
		.mb_y(mb_y),
		.mb_i16(mb_i16),
		.mb_cbp(mb_cbp),
		.mb_qp(mb_qp),
		.mb_i16_mode(mb_i16_mode),
		.mb_cmode(mb_cmode),
		.mb_i4m(mb_i4m),
		.coef_we(coef_we),
		.coef_blk(coef_blk),
		.coef_addr(coef_addr),
		.coef_data(coef_data),
		.slice_done(slice_done),
		.err(mb_err),
		.rec_done(rec_accept)
	);
	mv_pred #(.MAX_MBW(MAX_MBW)) u_mv(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.start(start),
		.mb_ptype(mb_ptype),
		.mb_sub(mb_sub),
		.mvd_valid(mvd_valid),
		.mvd_x(mvd_x),
		.mvd_y(mvd_y),
		.skip_go(skip_go_w),
		.commit(rec_accept),
		.mb_inter(mb_inter),
		.mb_skip(mb_skip),
		.mv_out_x(mv_x_w),
		.mv_out_y(mv_y_w)
	);
	wire [2047:0] rec_py;
	wire [511:0] rec_pu;
	wire [511:0] rec_pv;
	wire dbf_ready;
	wire rec_busy;
	wire rec_inter;
	wire signed [255:0] rec_mvx;
	wire signed [255:0] rec_mvy;
	wire [15:0] rec_nz;
	mb_recon #(.MAX_MBW(MAX_MBW)) u_rec(
		.mb_inter(mb_inter),
		.mb_nz(mb_nz_w),
		.mb_mvx(mv_x_w),
		.mb_mvy(mv_y_w),
		.mc_req_valid(mc_req_valid),
		.mc_req_plane(mc_req_plane),
		.mc_req_x(mc_req_x),
		.mc_req_y(mc_req_y),
		.mc_req_w(mc_req_w),
		.mc_rsp_valid(mc_rsp_valid),
		.mc_rsp_data(mc_rsp_data),
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.cfg_cqp_off(cfg_cqp_off),
		.coef_we(coef_we),
		.coef_blk(coef_blk),
		.coef_addr(coef_addr),
		.coef_data(coef_data),
		.mb_valid(mb_valid),
		.mb_x(mb_x),
		.mb_y(mb_y),
		.mb_i16(mb_i16),
		.mb_cbp(mb_cbp),
		.mb_qp(mb_qp),
		.mb_i16_mode(mb_i16_mode),
		.mb_cmode(mb_cmode),
		.mb_i4m(mb_i4m),
		.busy(rec_busy),
		.accepted(rec_accept),
		.out_ready(dbf_ready),
		.rec_x(rec_x),
		.rec_yc(rec_yc),
		.rec_qp(rec_qp),
		.rec_valid(rec_valid),
		.rec_y(rec_py),
		.rec_u(rec_pu),
		.rec_v(rec_pv),
		.rec_inter(rec_inter),
		.rec_nz(rec_nz),
		.rec_mvx(rec_mvx),
		.rec_mvy(rec_mvy),
		.err(rec_err)
	);
	reg slice_done_q;
	reg flush_q;
	wire dbf_done;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			slice_done_q <= 1'b0;
			flush_q <= 1'b0;
		end
		else begin
			if (slice_done)
				slice_done_q <= 1'b1;
			if ((((slice_done_q && !rec_busy) && !rec_valid) && dbf_ready) && !flush_q)
				flush_q <= 1'b1;
		end
	deblock_stream #(.MAX_MBW(MAX_MBW)) u_dbf(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.cfg_mb_h(cfg_mb_h),
		.cfg_cqp_off(cfg_cqp_off),
		.cfg_a_off(cfg_a_off),
		.cfg_b_off(cfg_b_off),
		.cfg_enable(cfg_deblock),
		.mb_push(rec_valid),
		.mb_x(rec_x),
		.mb_y(rec_yc),
		.mb_qp(rec_qp),
		.mb_inter(rec_inter),
		.mb_nz(rec_nz),
		.mb_mvx(rec_mvx),
		.mb_mvy(rec_mvy),
		.in_y(rec_py),
		.in_u(rec_pu),
		.in_v(rec_pv),
		.mb_ready(dbf_ready),
		.flush(flush_q && !dbf_done),
		.flush_done(dbf_done),
		.out_valid(out_valid),
		.out_mbx(out_mbx),
		.out_mby(out_mby),
		.out_plane(out_plane),
		.out_row(out_row),
		.out_data(out_data)
	);
	assign frame_done = dbf_done;
	assign err = (mb_err | rec_err) | blk_err;
endmodule
module bitreader (
	clk,
	rst_n,
	in_valid,
	in_word,
	in_bytes,
	in_ready,
	req_valid,
	req_bits,
	req_ready,
	show,
	avail
);
	input wire clk;
	input wire rst_n;
	input wire in_valid;
	input wire [31:0] in_word;
	input wire [2:0] in_bytes;
	output wire in_ready;
	input wire req_valid;
	input wire [4:0] req_bits;
	output wire req_ready;
	output wire [23:0] show;
	output wire [6:0] avail;
	reg [95:0] buf_q;
	reg [6:0] fill_q;
	assign in_ready = fill_q <= 7'd64;
	assign req_ready = req_valid && (fill_q >= {2'b00, req_bits});
	assign show = buf_q[95:72];
	assign avail = fill_q;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			buf_q <= 1'sb0;
			fill_q <= 1'sb0;
		end
		else begin : sv2v_autoblock_1
			reg [95:0] b;
			reg [6:0] f;
			b = buf_q;
			f = fill_q;
			if (req_valid && (f >= {2'b00, req_bits})) begin
				b = b << req_bits;
				f = f - {2'b00, req_bits};
			end
			if (in_valid && (fill_q <= 7'd64)) begin : sv2v_autoblock_2
				reg [31:0] wd;
				(* full_case, parallel_case *)
				case (in_bytes)
					3'd1: wd = {in_word[31:24], 24'b000000000000000000000000};
					3'd2: wd = {in_word[31:16], 16'b0000000000000000};
					3'd3: wd = {in_word[31:8], 8'b00000000};
					default: wd = in_word;
				endcase
				b = b | ({64'b0000000000000000000000000000000000000000000000000000000000000000, wd} << (7'd64 - f));
				f = f + {2'b00, in_bytes, 3'b000};
			end
			buf_q <= b;
			fill_q <= f;
		end
endmodule
module expgolomb (
	show,
	ue_val,
	se_val,
	len,
	ok
);
	reg _sv2v_0;
	input wire [23:0] show;
	output wire [11:0] ue_val;
	output wire signed [11:0] se_val;
	output wire [4:0] len;
	output wire ok;
	reg [3:0] lz;
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg [0:1] _sv2v_jump;
		_sv2v_jump = 2'b00;
		if (_sv2v_0)
			;
		lz = 4'd12;
		begin : sv2v_autoblock_2
			reg signed [31:0] i;
			begin : sv2v_autoblock_3
				reg signed [31:0] _sv2v_value_on_break;
				for (i = 0; i <= 11; i = i + 1)
					if (_sv2v_jump < 2'b10) begin
						_sv2v_jump = 2'b00;
						if (show[23 - i]) begin
							lz = sv2v_cast_4_signed(i);
							_sv2v_jump = 2'b10;
						end
						_sv2v_value_on_break = i;
					end
				if (!(_sv2v_jump < 2'b10))
					i = _sv2v_value_on_break;
				if (_sv2v_jump != 2'b11)
					_sv2v_jump = 2'b00;
			end
		end
	end
	reg [11:0] suffix;
	always @(*) begin : sv2v_autoblock_4
		reg [23:0] sh;
		if (_sv2v_0)
			;
		sh = show << (lz + 4'd1);
		suffix = sh[23-:12] >> (4'd12 - lz);
	end
	assign ok = lz <= 4'd11;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	assign len = (sv2v_cast_5(lz) * 5'd2) + 5'd1;
	assign ue_val = ((12'd1 << lz) - 12'd1) + suffix;
	assign se_val = (ue_val[0] ? $signed({1'b0, ue_val[11:1]} + 12'd1) : -$signed({1'b0, ue_val[11:1]}));
	initial _sv2v_0 = 0;
endmodule
module cavlc_block (
	clk,
	rst_n,
	req_valid,
	req_bits,
	req_ready,
	show,
	avail,
	start,
	chroma_dc,
	nc_class,
	maxc,
	busy,
	done,
	tc_out,
	err,
	coef_we,
	coef_addr,
	coef_data
);
	reg _sv2v_0;
	input wire clk;
	input wire rst_n;
	output reg req_valid;
	output reg [4:0] req_bits;
	input wire req_ready;
	input wire [23:0] show;
	input wire [6:0] avail;
	input wire start;
	input wire chroma_dc;
	input wire [1:0] nc_class;
	input wire [4:0] maxc;
	output wire busy;
	output wire done;
	output wire [4:0] tc_out;
	output wire err;
	output reg coef_we;
	output reg [3:0] coef_addr;
	output reg signed [15:0] coef_data;
	reg [3:0] st_q;
	wire win_ok;
	assign win_ok = avail >= 7'd24;
	reg cdc_q;
	reg [4:0] clz;
	wire [4:0] ctzl;
	reg [4:0] i_q;
	reg [4:0] maxc_q;
	wire [8:0] runl;
	reg [4:0] sfx_size;
	reg [1:0] t1_q;
	reg [4:0] tc_q;
	wire [12:0] tok;
	wire [8:0] tzl;
	reg [4:0] zl_q;
	always @(*) begin
		if (_sv2v_0)
			;
		req_valid = 1'b0;
		req_bits = 1'sb0;
		if (win_ok)
			(* full_case, parallel_case *)
			case (st_q)
				4'd1:
					if (tok[12]) begin
						req_valid = 1'b1;
						req_bits = tok[4:0];
					end
				4'd2:
					if (i_q < {3'b000, t1_q}) begin
						req_valid = 1'b1;
						req_bits = 5'd1;
					end
				4'd3:
					if (clz < 5'd24) begin
						req_valid = 1'b1;
						req_bits = clz + 5'd1;
					end
				4'd4:
					if (sfx_size != 5'd0) begin
						req_valid = 1'b1;
						req_bits = sfx_size;
					end
				4'd5:
					if (tc_q < maxc_q) begin
						if ((cdc_q ? ctzl[4] : tzl[8])) begin
							req_valid = 1'b1;
							req_bits = (cdc_q ? {3'b000, ctzl[1:0]} : {1'b0, tzl[3:0]});
						end
					end
				4'd6:
					if (((i_q != (tc_q - 5'd1)) && (zl_q > 5'd0)) && runl[8]) begin
						req_valid = 1'b1;
						req_bits = {1'b0, runl[3:0]};
					end
				default:
					;
			endcase
	end
	reg [2:0] sl_q;
	reg [4:0] pfx_q;
	reg signed [15:0] level_q [0:15];
	reg signed [5:0] pos_q;
	reg [4:0] run_i_q;
	reg [1:0] ncc_q;
	function automatic [12:0] cavlc_coeff_token;
		input reg [2:0] tab;
		input reg [15:0] win;
		reg [12:0] r;
		begin
			r = 1'sb0;
			(* full_case, parallel_case *)
			case (tab)
				3'd0:
					casez (win)
						16'b0000000000001111: r = 13'h1690;
						16'b0000000000001011: r = 13'h1710;
						16'b0000000000001110: r = 13'h1730;
						16'b0000000000001101: r = 13'h1750;
						16'b0000000000000111: r = 13'h1790;
						16'b0000000000001010: r = 13'h17b0;
						16'b0000000000001001: r = 13'h17d0;
						16'b0000000000001100: r = 13'h17f0;
						16'b0000000000000100: r = 13'h1810;
						16'b0000000000000110: r = 13'h1830;
						16'b0000000000000101: r = 13'h1850;
						16'b0000000000001000: r = 13'h1870;
						16'b000000000001111z: r = 13'h158f;
						16'b000000000001110z: r = 13'h15af;
						16'b000000000001011z: r = 13'h160f;
						16'b000000000001010z: r = 13'h162f;
						16'b000000000001101z: r = 13'h164f;
						16'b000000000000001z: r = 13'h16af;
						16'b000000000001001z: r = 13'h16cf;
						16'b000000000001100z: r = 13'h16ef;
						16'b000000000001000z: r = 13'h176f;
						16'b00000000001111zz: r = 13'h148e;
						16'b00000000001110zz: r = 13'h14ae;
						16'b00000000001011zz: r = 13'h150e;
						16'b00000000001010zz: r = 13'h152e;
						16'b00000000001101zz: r = 13'h154e;
						16'b00000000001001zz: r = 13'h15ce;
						16'b00000000001100zz: r = 13'h15ee;
						16'b00000000001000zz: r = 13'h166e;
						16'b0000000001111zzz: r = 13'h130d;
						16'b0000000001011zzz: r = 13'h138d;
						16'b0000000001110zzz: r = 13'h13ad;
						16'b0000000001000zzz: r = 13'h140d;
						16'b0000000001010zzz: r = 13'h142d;
						16'b0000000001101zzz: r = 13'h144d;
						16'b0000000001001zzz: r = 13'h14cd;
						16'b0000000001100zzz: r = 13'h156d;
						16'b00000000111zzzzz: r = 13'h128b;
						16'b00000000110zzzzz: r = 13'h132b;
						16'b00000000101zzzzz: r = 13'h13cb;
						16'b00000000100zzzzz: r = 13'h14eb;
						16'b0000000111zzzzzz: r = 13'h120a;
						16'b0000000110zzzzzz: r = 13'h12aa;
						16'b0000000101zzzzzz: r = 13'h134a;
						16'b0000000100zzzzzz: r = 13'h146a;
						16'b000000111zzzzzzz: r = 13'h1189;
						16'b000000110zzzzzzz: r = 13'h1229;
						16'b000000101zzzzzzz: r = 13'h12c9;
						16'b000000100zzzzzzz: r = 13'h13e9;
						16'b00000111zzzzzzzz: r = 13'h1108;
						16'b00000110zzzzzzzz: r = 13'h11a8;
						16'b00000101zzzzzzzz: r = 13'h1248;
						16'b00000100zzzzzzzz: r = 13'h1368;
						16'b0000101zzzzzzzzz: r = 13'h11c7;
						16'b0000100zzzzzzzzz: r = 13'h12e7;
						16'b000101zzzzzzzzzz: r = 13'h1086;
						16'b000100zzzzzzzzzz: r = 13'h1126;
						16'b000011zzzzzzzzzz: r = 13'h1266;
						16'b00011zzzzzzzzzzz: r = 13'h11e5;
						16'b001zzzzzzzzzzzzz: r = 13'h1143;
						16'b01zzzzzzzzzzzzzz: r = 13'h10a2;
						16'b1zzzzzzzzzzzzzzz: r = 13'h1001;
						default: r = 1'sb0;
					endcase
				3'd1:
					casez (win)
						16'b00000000001011zz: r = 13'h172e;
						16'b00000000001001zz: r = 13'h178e;
						16'b00000000001000zz: r = 13'h17ae;
						16'b00000000001010zz: r = 13'h17ce;
						16'b00000000000111zz: r = 13'h180e;
						16'b00000000000110zz: r = 13'h182e;
						16'b00000000000101zz: r = 13'h184e;
						16'b00000000000100zz: r = 13'h186e;
						16'b0000000001111zzz: r = 13'h160d;
						16'b0000000001110zzz: r = 13'h162d;
						16'b0000000001101zzz: r = 13'h164d;
						16'b0000000001011zzz: r = 13'h168d;
						16'b0000000001010zzz: r = 13'h16ad;
						16'b0000000001001zzz: r = 13'h16cd;
						16'b0000000001100zzz: r = 13'h16ed;
						16'b0000000000111zzz: r = 13'h170d;
						16'b0000000000110zzz: r = 13'h174d;
						16'b0000000001000zzz: r = 13'h176d;
						16'b0000000000001zzz: r = 13'h17ed;
						16'b000000001111zzzz: r = 13'h148c;
						16'b000000001011zzzz: r = 13'h150c;
						16'b000000001110zzzz: r = 13'h152c;
						16'b000000001101zzzz: r = 13'h154c;
						16'b000000001000zzzz: r = 13'h158c;
						16'b000000001010zzzz: r = 13'h15ac;
						16'b000000001001zzzz: r = 13'h15cc;
						16'b000000001100zzzz: r = 13'h166c;
						16'b00000001111zzzzz: r = 13'h138b;
						16'b00000001011zzzzz: r = 13'h140b;
						16'b00000001110zzzzz: r = 13'h142b;
						16'b00000001101zzzzz: r = 13'h144b;
						16'b00000001010zzzzz: r = 13'h14ab;
						16'b00000001001zzzzz: r = 13'h14cb;
						16'b00000001100zzzzz: r = 13'h156b;
						16'b00000001000zzzzz: r = 13'h15eb;
						16'b000000111zzzzzzz: r = 13'h1309;
						16'b000000110zzzzzzz: r = 13'h13a9;
						16'b000000101zzzzzzz: r = 13'h13c9;
						16'b000000100zzzzzzz: r = 13'h14e9;
						16'b00000111zzzzzzzz: r = 13'h1208;
						16'b00000100zzzzzzzz: r = 13'h1288;
						16'b00000110zzzzzzzz: r = 13'h1328;
						16'b00000101zzzzzzzz: r = 13'h1348;
						16'b0000111zzzzzzzzz: r = 13'h1187;
						16'b0000110zzzzzzzzz: r = 13'h12a7;
						16'b0000101zzzzzzzzz: r = 13'h12c7;
						16'b0000100zzzzzzzzz: r = 13'h1467;
						16'b001011zzzzzzzzzz: r = 13'h1086;
						16'b000111zzzzzzzzzz: r = 13'h1106;
						16'b001010zzzzzzzzzz: r = 13'h11a6;
						16'b001001zzzzzzzzzz: r = 13'h11c6;
						16'b000110zzzzzzzzzz: r = 13'h1226;
						16'b000101zzzzzzzzzz: r = 13'h1246;
						16'b001000zzzzzzzzzz: r = 13'h1366;
						16'b000100zzzzzzzzzz: r = 13'h13e6;
						16'b00111zzzzzzzzzzz: r = 13'h1125;
						16'b00110zzzzzzzzzzz: r = 13'h12e5;
						16'b0101zzzzzzzzzzzz: r = 13'h11e4;
						16'b0100zzzzzzzzzzzz: r = 13'h1264;
						16'b011zzzzzzzzzzzzz: r = 13'h1143;
						16'b11zzzzzzzzzzzzzz: r = 13'h1002;
						16'b10zzzzzzzzzzzzzz: r = 13'h10a2;
						default: r = 1'sb0;
					endcase
				3'd2:
					casez (win)
						16'b0000001101zzzzzz: r = 13'h168a;
						16'b0000001001zzzzzz: r = 13'h170a;
						16'b0000001100zzzzzz: r = 13'h172a;
						16'b0000001011zzzzzz: r = 13'h174a;
						16'b0000001010zzzzzz: r = 13'h176a;
						16'b0000000101zzzzzz: r = 13'h178a;
						16'b0000001000zzzzzz: r = 13'h17aa;
						16'b0000000111zzzzzz: r = 13'h17ca;
						16'b0000000110zzzzzz: r = 13'h17ea;
						16'b0000000001zzzzzz: r = 13'h180a;
						16'b0000000100zzzzzz: r = 13'h182a;
						16'b0000000011zzzzzz: r = 13'h184a;
						16'b0000000010zzzzzz: r = 13'h186a;
						16'b000001111zzzzzzz: r = 13'h1509;
						16'b000001011zzzzzzz: r = 13'h1589;
						16'b000001110zzzzzzz: r = 13'h15a9;
						16'b000001000zzzzzzz: r = 13'h1609;
						16'b000001010zzzzzzz: r = 13'h1629;
						16'b000001101zzzzzzz: r = 13'h1649;
						16'b000000111zzzzzzz: r = 13'h16a9;
						16'b000001001zzzzzzz: r = 13'h16c9;
						16'b000001100zzzzzzz: r = 13'h16e9;
						16'b00001111zzzzzzzz: r = 13'h1408;
						16'b00001011zzzzzzzz: r = 13'h1488;
						16'b00001110zzzzzzzz: r = 13'h14a8;
						16'b00001010zzzzzzzz: r = 13'h1528;
						16'b00001101zzzzzzzz: r = 13'h1548;
						16'b00001001zzzzzzzz: r = 13'h15c8;
						16'b00001100zzzzzzzz: r = 13'h15e8;
						16'b00001000zzzzzzzz: r = 13'h1668;
						16'b0001111zzzzzzzzz: r = 13'h1207;
						16'b0001011zzzzzzzzz: r = 13'h1287;
						16'b0001001zzzzzzzzz: r = 13'h1307;
						16'b0001000zzzzzzzzz: r = 13'h1387;
						16'b0001110zzzzzzzzz: r = 13'h1427;
						16'b0001101zzzzzzzzz: r = 13'h1447;
						16'b0001010zzzzzzzzz: r = 13'h14c7;
						16'b0001100zzzzzzzzz: r = 13'h1567;
						16'b001111zzzzzzzzzz: r = 13'h1086;
						16'b001011zzzzzzzzzz: r = 13'h1106;
						16'b001000zzzzzzzzzz: r = 13'h1186;
						16'b001110zzzzzzzzzz: r = 13'h1326;
						16'b001101zzzzzzzzzz: r = 13'h1346;
						16'b001010zzzzzzzzzz: r = 13'h13a6;
						16'b001001zzzzzzzzzz: r = 13'h13c6;
						16'b001100zzzzzzzzzz: r = 13'h14e6;
						16'b01111zzzzzzzzzzz: r = 13'h1125;
						16'b01100zzzzzzzzzzz: r = 13'h11a5;
						16'b01110zzzzzzzzzzz: r = 13'h11c5;
						16'b01010zzzzzzzzzzz: r = 13'h1225;
						16'b01011zzzzzzzzzzz: r = 13'h1245;
						16'b01000zzzzzzzzzzz: r = 13'h12a5;
						16'b01001zzzzzzzzzzz: r = 13'h12c5;
						16'b01101zzzzzzzzzzz: r = 13'h1465;
						16'b1111zzzzzzzzzzzz: r = 13'h1004;
						16'b1110zzzzzzzzzzzz: r = 13'h10a4;
						16'b1101zzzzzzzzzzzz: r = 13'h1144;
						16'b1100zzzzzzzzzzzz: r = 13'h11e4;
						16'b1011zzzzzzzzzzzz: r = 13'h1264;
						16'b1010zzzzzzzzzzzz: r = 13'h12e4;
						16'b1001zzzzzzzzzzzz: r = 13'h1364;
						16'b1000zzzzzzzzzzzz: r = 13'h13e4;
						default: r = 1'sb0;
					endcase
				3'd3:
					casez (win)
						16'b000011zzzzzzzzzz: r = 13'h1006;
						16'b000000zzzzzzzzzz: r = 13'h1086;
						16'b000001zzzzzzzzzz: r = 13'h10a6;
						16'b000100zzzzzzzzzz: r = 13'h1106;
						16'b000101zzzzzzzzzz: r = 13'h1126;
						16'b000110zzzzzzzzzz: r = 13'h1146;
						16'b001000zzzzzzzzzz: r = 13'h1186;
						16'b001001zzzzzzzzzz: r = 13'h11a6;
						16'b001010zzzzzzzzzz: r = 13'h11c6;
						16'b001011zzzzzzzzzz: r = 13'h11e6;
						16'b001100zzzzzzzzzz: r = 13'h1206;
						16'b001101zzzzzzzzzz: r = 13'h1226;
						16'b001110zzzzzzzzzz: r = 13'h1246;
						16'b001111zzzzzzzzzz: r = 13'h1266;
						16'b010000zzzzzzzzzz: r = 13'h1286;
						16'b010001zzzzzzzzzz: r = 13'h12a6;
						16'b010010zzzzzzzzzz: r = 13'h12c6;
						16'b010011zzzzzzzzzz: r = 13'h12e6;
						16'b010100zzzzzzzzzz: r = 13'h1306;
						16'b010101zzzzzzzzzz: r = 13'h1326;
						16'b010110zzzzzzzzzz: r = 13'h1346;
						16'b010111zzzzzzzzzz: r = 13'h1366;
						16'b011000zzzzzzzzzz: r = 13'h1386;
						16'b011001zzzzzzzzzz: r = 13'h13a6;
						16'b011010zzzzzzzzzz: r = 13'h13c6;
						16'b011011zzzzzzzzzz: r = 13'h13e6;
						16'b011100zzzzzzzzzz: r = 13'h1406;
						16'b011101zzzzzzzzzz: r = 13'h1426;
						16'b011110zzzzzzzzzz: r = 13'h1446;
						16'b011111zzzzzzzzzz: r = 13'h1466;
						16'b100000zzzzzzzzzz: r = 13'h1486;
						16'b100001zzzzzzzzzz: r = 13'h14a6;
						16'b100010zzzzzzzzzz: r = 13'h14c6;
						16'b100011zzzzzzzzzz: r = 13'h14e6;
						16'b100100zzzzzzzzzz: r = 13'h1506;
						16'b100101zzzzzzzzzz: r = 13'h1526;
						16'b100110zzzzzzzzzz: r = 13'h1546;
						16'b100111zzzzzzzzzz: r = 13'h1566;
						16'b101000zzzzzzzzzz: r = 13'h1586;
						16'b101001zzzzzzzzzz: r = 13'h15a6;
						16'b101010zzzzzzzzzz: r = 13'h15c6;
						16'b101011zzzzzzzzzz: r = 13'h15e6;
						16'b101100zzzzzzzzzz: r = 13'h1606;
						16'b101101zzzzzzzzzz: r = 13'h1626;
						16'b101110zzzzzzzzzz: r = 13'h1646;
						16'b101111zzzzzzzzzz: r = 13'h1666;
						16'b110000zzzzzzzzzz: r = 13'h1686;
						16'b110001zzzzzzzzzz: r = 13'h16a6;
						16'b110010zzzzzzzzzz: r = 13'h16c6;
						16'b110011zzzzzzzzzz: r = 13'h16e6;
						16'b110100zzzzzzzzzz: r = 13'h1706;
						16'b110101zzzzzzzzzz: r = 13'h1726;
						16'b110110zzzzzzzzzz: r = 13'h1746;
						16'b110111zzzzzzzzzz: r = 13'h1766;
						16'b111000zzzzzzzzzz: r = 13'h1786;
						16'b111001zzzzzzzzzz: r = 13'h17a6;
						16'b111010zzzzzzzzzz: r = 13'h17c6;
						16'b111011zzzzzzzzzz: r = 13'h17e6;
						16'b111100zzzzzzzzzz: r = 13'h1806;
						16'b111101zzzzzzzzzz: r = 13'h1826;
						16'b111110zzzzzzzzzz: r = 13'h1846;
						16'b111111zzzzzzzzzz: r = 13'h1866;
						default: r = 1'sb0;
					endcase
				3'd4:
					casez (win)
						16'b00000011zzzzzzzz: r = 13'h1228;
						16'b00000010zzzzzzzz: r = 13'h1248;
						16'b0000011zzzzzzzzz: r = 13'h11a7;
						16'b0000010zzzzzzzzz: r = 13'h11c7;
						16'b0000000zzzzzzzzz: r = 13'h1267;
						16'b000111zzzzzzzzzz: r = 13'h1086;
						16'b000100zzzzzzzzzz: r = 13'h1106;
						16'b000110zzzzzzzzzz: r = 13'h1126;
						16'b000011zzzzzzzzzz: r = 13'h1186;
						16'b000101zzzzzzzzzz: r = 13'h11e6;
						16'b000010zzzzzzzzzz: r = 13'h1206;
						16'b001zzzzzzzzzzzzz: r = 13'h1143;
						16'b01zzzzzzzzzzzzzz: r = 13'h1002;
						16'b1zzzzzzzzzzzzzzz: r = 13'h10a1;
						default: r = 1'sb0;
					endcase
				default: r = 1'sb0;
			endcase
			cavlc_coeff_token = r;
		end
	endfunction
	assign tok = cavlc_coeff_token((cdc_q ? 3'd4 : {1'b0, ncc_q}), show[23:8]);
	function automatic [8:0] cavlc_total_zeros;
		input reg [3:0] tc_m1;
		input reg [8:0] win;
		reg [8:0] r;
		begin
			r = 1'sb0;
			(* full_case, parallel_case *)
			case (tc_m1)
				4'd0:
					casez (win)
						9'b000000011: r = 9'h1d9;
						9'b000000010: r = 9'h1e9;
						9'b000000001: r = 9'h1f9;
						9'b00000011z: r = 9'h1b8;
						9'b00000010z: r = 9'h1c8;
						9'b0000011zz: r = 9'h197;
						9'b0000010zz: r = 9'h1a7;
						9'b000011zzz: r = 9'h176;
						9'b000010zzz: r = 9'h186;
						9'b00011zzzz: r = 9'h155;
						9'b00010zzzz: r = 9'h165;
						9'b0011zzzzz: r = 9'h134;
						9'b0010zzzzz: r = 9'h144;
						9'b011zzzzzz: r = 9'h113;
						9'b010zzzzzz: r = 9'h123;
						9'b1zzzzzzzz: r = 9'h101;
						default: r = 1'sb0;
					endcase
				4'd1:
					casez (win)
						9'b000011zzz: r = 9'h1b6;
						9'b000010zzz: r = 9'h1c6;
						9'b000001zzz: r = 9'h1d6;
						9'b000000zzz: r = 9'h1e6;
						9'b00011zzzz: r = 9'h195;
						9'b00010zzzz: r = 9'h1a5;
						9'b0101zzzzz: r = 9'h154;
						9'b0100zzzzz: r = 9'h164;
						9'b0011zzzzz: r = 9'h174;
						9'b0010zzzzz: r = 9'h184;
						9'b111zzzzzz: r = 9'h103;
						9'b110zzzzzz: r = 9'h113;
						9'b101zzzzzz: r = 9'h123;
						9'b100zzzzzz: r = 9'h133;
						9'b011zzzzzz: r = 9'h143;
						default: r = 1'sb0;
					endcase
				4'd2:
					casez (win)
						9'b000001zzz: r = 9'h1b6;
						9'b000000zzz: r = 9'h1d6;
						9'b00011zzzz: r = 9'h195;
						9'b00010zzzz: r = 9'h1a5;
						9'b00001zzzz: r = 9'h1c5;
						9'b0101zzzzz: r = 9'h104;
						9'b0100zzzzz: r = 9'h144;
						9'b0011zzzzz: r = 9'h154;
						9'b0010zzzzz: r = 9'h184;
						9'b111zzzzzz: r = 9'h113;
						9'b110zzzzzz: r = 9'h123;
						9'b101zzzzzz: r = 9'h133;
						9'b100zzzzzz: r = 9'h163;
						9'b011zzzzzz: r = 9'h173;
						default: r = 1'sb0;
					endcase
				4'd3:
					casez (win)
						9'b00011zzzz: r = 9'h105;
						9'b00010zzzz: r = 9'h1a5;
						9'b00001zzzz: r = 9'h1b5;
						9'b00000zzzz: r = 9'h1c5;
						9'b0101zzzzz: r = 9'h124;
						9'b0100zzzzz: r = 9'h134;
						9'b0011zzzzz: r = 9'h174;
						9'b0010zzzzz: r = 9'h194;
						9'b111zzzzzz: r = 9'h113;
						9'b110zzzzzz: r = 9'h143;
						9'b101zzzzzz: r = 9'h153;
						9'b100zzzzzz: r = 9'h163;
						9'b011zzzzzz: r = 9'h183;
						default: r = 1'sb0;
					endcase
				4'd4:
					casez (win)
						9'b00001zzzz: r = 9'h195;
						9'b00000zzzz: r = 9'h1b5;
						9'b0101zzzzz: r = 9'h104;
						9'b0100zzzzz: r = 9'h114;
						9'b0011zzzzz: r = 9'h124;
						9'b0010zzzzz: r = 9'h184;
						9'b0001zzzzz: r = 9'h1a4;
						9'b111zzzzzz: r = 9'h133;
						9'b110zzzzzz: r = 9'h143;
						9'b101zzzzzz: r = 9'h153;
						9'b100zzzzzz: r = 9'h163;
						9'b011zzzzzz: r = 9'h173;
						default: r = 1'sb0;
					endcase
				4'd5:
					casez (win)
						9'b000001zzz: r = 9'h106;
						9'b000000zzz: r = 9'h1a6;
						9'b00001zzzz: r = 9'h115;
						9'b0001zzzzz: r = 9'h184;
						9'b111zzzzzz: r = 9'h123;
						9'b110zzzzzz: r = 9'h133;
						9'b101zzzzzz: r = 9'h143;
						9'b100zzzzzz: r = 9'h153;
						9'b011zzzzzz: r = 9'h163;
						9'b010zzzzzz: r = 9'h173;
						9'b001zzzzzz: r = 9'h193;
						default: r = 1'sb0;
					endcase
				4'd6:
					casez (win)
						9'b000001zzz: r = 9'h106;
						9'b000000zzz: r = 9'h196;
						9'b00001zzzz: r = 9'h115;
						9'b0001zzzzz: r = 9'h174;
						9'b101zzzzzz: r = 9'h123;
						9'b100zzzzzz: r = 9'h133;
						9'b011zzzzzz: r = 9'h143;
						9'b010zzzzzz: r = 9'h163;
						9'b001zzzzzz: r = 9'h183;
						9'b11zzzzzzz: r = 9'h152;
						default: r = 1'sb0;
					endcase
				4'd7:
					casez (win)
						9'b000001zzz: r = 9'h106;
						9'b000000zzz: r = 9'h186;
						9'b00001zzzz: r = 9'h125;
						9'b0001zzzzz: r = 9'h114;
						9'b011zzzzzz: r = 9'h133;
						9'b010zzzzzz: r = 9'h163;
						9'b001zzzzzz: r = 9'h173;
						9'b11zzzzzzz: r = 9'h142;
						9'b10zzzzzzz: r = 9'h152;
						default: r = 1'sb0;
					endcase
				4'd8:
					casez (win)
						9'b000001zzz: r = 9'h106;
						9'b000000zzz: r = 9'h116;
						9'b00001zzzz: r = 9'h175;
						9'b0001zzzzz: r = 9'h124;
						9'b001zzzzzz: r = 9'h153;
						9'b11zzzzzzz: r = 9'h132;
						9'b10zzzzzzz: r = 9'h142;
						9'b01zzzzzzz: r = 9'h162;
						default: r = 1'sb0;
					endcase
				4'd9:
					casez (win)
						9'b00001zzzz: r = 9'h105;
						9'b00000zzzz: r = 9'h115;
						9'b0001zzzzz: r = 9'h164;
						9'b001zzzzzz: r = 9'h123;
						9'b11zzzzzzz: r = 9'h132;
						9'b10zzzzzzz: r = 9'h142;
						9'b01zzzzzzz: r = 9'h152;
						default: r = 1'sb0;
					endcase
				4'd10:
					casez (win)
						9'b0000zzzzz: r = 9'h104;
						9'b0001zzzzz: r = 9'h114;
						9'b001zzzzzz: r = 9'h123;
						9'b010zzzzzz: r = 9'h133;
						9'b011zzzzzz: r = 9'h153;
						9'b1zzzzzzzz: r = 9'h141;
						default: r = 1'sb0;
					endcase
				4'd11:
					casez (win)
						9'b0000zzzzz: r = 9'h104;
						9'b0001zzzzz: r = 9'h114;
						9'b001zzzzzz: r = 9'h143;
						9'b01zzzzzzz: r = 9'h122;
						9'b1zzzzzzzz: r = 9'h131;
						default: r = 1'sb0;
					endcase
				4'd12:
					casez (win)
						9'b000zzzzzz: r = 9'h103;
						9'b001zzzzzz: r = 9'h113;
						9'b01zzzzzzz: r = 9'h132;
						9'b1zzzzzzzz: r = 9'h121;
						default: r = 1'sb0;
					endcase
				4'd13:
					casez (win)
						9'b00zzzzzzz: r = 9'h102;
						9'b01zzzzzzz: r = 9'h112;
						9'b1zzzzzzzz: r = 9'h121;
						default: r = 1'sb0;
					endcase
				4'd14:
					casez (win)
						9'b0zzzzzzzz: r = 9'h101;
						9'b1zzzzzzzz: r = 9'h111;
						default: r = 1'sb0;
					endcase
				default: r = 1'sb0;
			endcase
			cavlc_total_zeros = r;
		end
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	assign tzl = cavlc_total_zeros(sv2v_cast_4(tc_q - 5'd1), show[23:15]);
	function automatic [4:0] cavlc_cdc_total_zeros;
		input reg [1:0] tc_m1;
		input reg [2:0] win;
		reg [4:0] r;
		begin
			r = 1'sb0;
			(* full_case, parallel_case *)
			case (tc_m1)
				2'd0:
					casez (win)
						3'b001: r = 5'h1b;
						3'b000: r = 5'h1f;
						3'b01z: r = 5'h16;
						3'b1zz: r = 5'h11;
						default: r = 1'sb0;
					endcase
				2'd1:
					casez (win)
						3'b01z: r = 5'h16;
						3'b00z: r = 5'h1a;
						3'b1zz: r = 5'h11;
						default: r = 1'sb0;
					endcase
				2'd2:
					casez (win)
						3'b1zz: r = 5'h11;
						3'b0zz: r = 5'h15;
						default: r = 1'sb0;
					endcase
				default: r = 1'sb0;
			endcase
			cavlc_cdc_total_zeros = r;
		end
	endfunction
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	assign ctzl = cavlc_cdc_total_zeros(sv2v_cast_2(tc_q - 5'd1), show[23:21]);
	wire [2:0] zl_row;
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	assign zl_row = (zl_q < 5'd7 ? sv2v_cast_3(zl_q - 5'd1) : 3'd6);
	function automatic [8:0] cavlc_run_before;
		input reg [2:0] zl_m1;
		input reg [10:0] win;
		reg [8:0] r;
		begin
			r = 1'sb0;
			(* full_case, parallel_case *)
			case (zl_m1)
				3'd0:
					casez (win)
						11'b1zzzzzzzzzz: r = 9'h101;
						11'b0zzzzzzzzzz: r = 9'h111;
						default: r = 1'sb0;
					endcase
				3'd1:
					casez (win)
						11'b01zzzzzzzzz: r = 9'h112;
						11'b00zzzzzzzzz: r = 9'h122;
						11'b1zzzzzzzzzz: r = 9'h101;
						default: r = 1'sb0;
					endcase
				3'd2:
					casez (win)
						11'b11zzzzzzzzz: r = 9'h102;
						11'b10zzzzzzzzz: r = 9'h112;
						11'b01zzzzzzzzz: r = 9'h122;
						11'b00zzzzzzzzz: r = 9'h132;
						default: r = 1'sb0;
					endcase
				3'd3:
					casez (win)
						11'b001zzzzzzzz: r = 9'h133;
						11'b000zzzzzzzz: r = 9'h143;
						11'b11zzzzzzzzz: r = 9'h102;
						11'b10zzzzzzzzz: r = 9'h112;
						11'b01zzzzzzzzz: r = 9'h122;
						default: r = 1'sb0;
					endcase
				3'd4:
					casez (win)
						11'b011zzzzzzzz: r = 9'h123;
						11'b010zzzzzzzz: r = 9'h133;
						11'b001zzzzzzzz: r = 9'h143;
						11'b000zzzzzzzz: r = 9'h153;
						11'b11zzzzzzzzz: r = 9'h102;
						11'b10zzzzzzzzz: r = 9'h112;
						default: r = 1'sb0;
					endcase
				3'd5:
					casez (win)
						11'b000zzzzzzzz: r = 9'h113;
						11'b001zzzzzzzz: r = 9'h123;
						11'b011zzzzzzzz: r = 9'h133;
						11'b010zzzzzzzz: r = 9'h143;
						11'b101zzzzzzzz: r = 9'h153;
						11'b100zzzzzzzz: r = 9'h163;
						11'b11zzzzzzzzz: r = 9'h102;
						default: r = 1'sb0;
					endcase
				3'd6:
					casez (win)
						11'b00000000001: r = 9'h1eb;
						11'b0000000001z: r = 9'h1da;
						11'b000000001zz: r = 9'h1c9;
						11'b00000001zzz: r = 9'h1b8;
						11'b0000001zzzz: r = 9'h1a7;
						11'b000001zzzzz: r = 9'h196;
						11'b00001zzzzzz: r = 9'h185;
						11'b0001zzzzzzz: r = 9'h174;
						11'b111zzzzzzzz: r = 9'h103;
						11'b110zzzzzzzz: r = 9'h113;
						11'b101zzzzzzzz: r = 9'h123;
						11'b100zzzzzzzz: r = 9'h133;
						11'b011zzzzzzzz: r = 9'h143;
						11'b010zzzzzzzz: r = 9'h153;
						11'b001zzzzzzzz: r = 9'h163;
						default: r = 1'sb0;
					endcase
				default: r = 1'sb0;
			endcase
			cavlc_run_before = r;
		end
	endfunction
	assign runl = cavlc_run_before(zl_row, show[23:13]);
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg [0:1] _sv2v_jump;
		_sv2v_jump = 2'b00;
		if (_sv2v_0)
			;
		clz = 5'd24;
		begin : sv2v_autoblock_2
			reg signed [31:0] k;
			begin : sv2v_autoblock_3
				reg signed [31:0] _sv2v_value_on_break;
				for (k = 0; k <= 23; k = k + 1)
					if (_sv2v_jump < 2'b10) begin
						_sv2v_jump = 2'b00;
						if (show[23 - k]) begin
							clz = sv2v_cast_5_signed(k);
							_sv2v_jump = 2'b10;
						end
						_sv2v_value_on_break = k;
					end
				if (!(_sv2v_jump < 2'b10))
					k = _sv2v_value_on_break;
				if (_sv2v_jump != 2'b11)
					_sv2v_jump = 2'b00;
			end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		if ((pfx_q == 5'd14) && (sl_q == 3'd0))
			sfx_size = 5'd4;
		else if (pfx_q >= 5'd15)
			sfx_size = pfx_q - 5'd3;
		else
			sfx_size = {2'b00, sl_q};
	end
	reg signed [15:0] lvl_new;
	reg [15:0] level_code;
	always @(*) begin : sv2v_autoblock_4
		reg [15:0] lc;
		reg [15:0] sfx;
		if (_sv2v_0)
			;
		lc = {11'b00000000000, (pfx_q < 5'd15 ? pfx_q : 5'd15)} << sl_q;
		sfx = show[23:8] >> (5'd16 - sfx_size);
		if ((sl_q > 0) || (pfx_q >= 5'd14))
			lc = lc + sfx;
		if ((pfx_q >= 5'd15) && (sl_q == 3'd0))
			lc = lc + 16'd15;
		if (pfx_q >= 5'd16)
			lc = (lc + (16'd1 << (pfx_q - 5'd3))) - 16'd4096;
		if ((i_q == {3'b000, t1_q}) && (t1_q < 2'd3))
			lc = lc + 16'd2;
		level_code = lc;
		lvl_new = (lc[0] ? -$signed({1'b0, (lc + 16'd1) >> 1}) : $signed({1'b0, (lc + 16'd2) >> 1}));
	end
	wire [15:0] abs_lvl;
	assign abs_lvl = (lvl_new[15] ? -lvl_new : lvl_new);
	assign busy = ((st_q != 4'd0) && (st_q != 4'd7)) && (st_q != 4'd8);
	assign done = st_q == 4'd7;
	assign err = st_q == 4'd8;
	assign tc_out = tc_q;
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 4'd0;
			coef_we <= 1'b0;
			coef_addr <= 1'sb0;
			coef_data <= 1'sb0;
			tc_q <= 1'sb0;
			t1_q <= 1'sb0;
			sl_q <= 1'sb0;
			i_q <= 1'sb0;
			pfx_q <= 1'sb0;
			zl_q <= 1'sb0;
			pos_q <= 1'sb0;
			run_i_q <= 1'sb0;
			maxc_q <= 1'sb0;
			cdc_q <= 1'b0;
			ncc_q <= 1'sb0;
		end
		else begin
			coef_we <= 1'b0;
			(* full_case, parallel_case *)
			case (st_q)
				4'd0:
					if (start) begin
						cdc_q <= chroma_dc;
						ncc_q <= nc_class;
						maxc_q <= maxc;
						tc_q <= 1'sb0;
						st_q <= 4'd1;
					end
				4'd1:
					if (win_ok) begin
						if (!tok[12])
							st_q <= 4'd8;
						else begin
							tc_q <= tok[11:7];
							t1_q <= tok[6:5];
							if (tok[11:7] == 5'd0)
								st_q <= 4'd7;
							else begin
								sl_q <= ((tok[11:7] > 5'd10) && (tok[6:5] < 2'd3) ? 3'd1 : 3'd0);
								i_q <= 1'sb0;
								st_q <= 4'd2;
							end
						end
					end
				4'd2:
					if (win_ok) begin
						if (i_q < {3'b000, t1_q}) begin
							level_q[i_q[3:0]] <= (show[23] ? -16'sd1 : 16'sd1);
							i_q <= i_q + 5'd1;
							if ((i_q + 5'd1) == {3'b000, t1_q})
								st_q <= ({3'b000, t1_q} < tc_q ? 4'd3 : 4'd5);
						end
						else if (i_q < tc_q)
							st_q <= 4'd3;
						else
							st_q <= 4'd5;
					end
				4'd3:
					if (win_ok) begin
						if (clz >= 5'd24)
							st_q <= 4'd8;
						else begin
							pfx_q <= clz;
							st_q <= 4'd4;
						end
					end
				4'd4:
					if (win_ok) begin
						level_q[i_q[3:0]] <= lvl_new;
						if (sl_q == 3'd0)
							sl_q <= (abs_lvl > 16'd3 ? 3'd2 : 3'd1);
						else if ((abs_lvl > (16'd3 << (sl_q - 3'd1))) && (sl_q < 3'd6))
							sl_q <= sl_q + 3'd1;
						i_q <= i_q + 5'd1;
						st_q <= ((i_q + 5'd1) < tc_q ? 4'd3 : 4'd5);
					end
				4'd5:
					if (win_ok) begin
						if (tc_q < maxc_q) begin : sv2v_autoblock_5
							reg [4:0] tzv;
							reg [4:0] tzlen;
							reg tzok;
							if (cdc_q) begin
								tzok = ctzl[4];
								tzv = {3'b000, ctzl[3:2]};
								tzlen = {3'b000, ctzl[1:0]};
							end
							else begin
								tzok = tzl[8];
								tzv = {1'b0, tzl[7:4]};
								tzlen = {1'b0, tzl[3:0]};
							end
							if (!tzok || ({1'b0, tzv} > sv2v_cast_6(maxc_q - tc_q)))
								st_q <= 4'd8;
							else begin
								zl_q <= tzv;
								pos_q <= (sv2v_cast_6(tc_q) + sv2v_cast_6(tzv)) - 6'd1;
								run_i_q <= 1'sb0;
								i_q <= 1'sb0;
								st_q <= 4'd6;
							end
						end
						else begin
							zl_q <= 1'sb0;
							pos_q <= sv2v_cast_6(tc_q) - 6'd1;
							run_i_q <= 1'sb0;
							i_q <= 1'sb0;
							st_q <= 4'd6;
						end
					end
				4'd6:
					if (win_ok) begin : sv2v_autoblock_6
						reg [4:0] run;
						reg bad;
						run = 1'sb0;
						bad = 1'b0;
						if (i_q == (tc_q - 5'd1))
							run = zl_q;
						else if (zl_q > 5'd0) begin
							if (!runl[8] || ({4'b0000, runl[7:4]} > {4'b0000, zl_q}))
								bad = 1'b1;
							run = {1'b0, runl[7:4]};
						end
						if (bad)
							st_q <= 4'd8;
						else begin
							coef_we <= 1'b1;
							coef_addr <= pos_q[3:0];
							coef_data <= level_q[i_q[3:0]];
							if ((i_q + 5'd1) >= tc_q)
								st_q <= 4'd7;
							else begin
								pos_q <= (pos_q - 6'sd1) - $signed({1'b0, run});
								zl_q <= zl_q - run;
								i_q <= i_q + 5'd1;
							end
						end
					end
				4'd7: st_q <= 4'd0;
				4'd8: st_q <= 4'd0;
				default: st_q <= 4'd0;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module mb_dec (
	clk,
	rst_n,
	cfg_mb_w,
	cfg_mb_h,
	cfg_qp,
	cfg_is_p,
	start,
	req_valid,
	req_bits,
	req_ready,
	show,
	avail,
	blk_start,
	blk_chroma_dc,
	blk_nc_class,
	blk_maxc,
	blk_busy,
	blk_done,
	blk_err,
	blk_tc,
	blk_coef_we,
	blk_coef_addr,
	blk_coef_data,
	mb_skip,
	mb_inter,
	mb_ptype,
	mb_sub,
	mvd_valid,
	mvd_x,
	mvd_y,
	skip_go,
	mb_nz,
	mb_valid,
	mb_x,
	mb_y,
	mb_i16,
	mb_cbp,
	mb_qp,
	mb_i16_mode,
	mb_cmode,
	mb_i4m,
	coef_we,
	coef_blk,
	coef_addr,
	coef_data,
	slice_done,
	err,
	rec_done
);
	reg _sv2v_0;
	parameter signed [31:0] MAX_MBW = 120;
	input wire clk;
	input wire rst_n;
	input wire [7:0] cfg_mb_w;
	input wire [7:0] cfg_mb_h;
	input wire [5:0] cfg_qp;
	input wire cfg_is_p;
	input wire start;
	output reg req_valid;
	output reg [4:0] req_bits;
	input wire req_ready;
	input wire [23:0] show;
	input wire [6:0] avail;
	output reg blk_start;
	output reg blk_chroma_dc;
	output reg [1:0] blk_nc_class;
	output reg [4:0] blk_maxc;
	input wire blk_busy;
	input wire blk_done;
	input wire blk_err;
	input wire [4:0] blk_tc;
	input wire blk_coef_we;
	input wire [3:0] blk_coef_addr;
	input wire signed [15:0] blk_coef_data;
	output wire mb_skip;
	output wire mb_inter;
	output wire [2:0] mb_ptype;
	output wire [7:0] mb_sub;
	output wire mvd_valid;
	output wire signed [15:0] mvd_x;
	output wire signed [15:0] mvd_y;
	output wire skip_go;
	output reg [15:0] mb_nz;
	output wire mb_valid;
	output wire [7:0] mb_x;
	output wire [7:0] mb_y;
	output wire mb_i16;
	output wire [5:0] mb_cbp;
	output wire [5:0] mb_qp;
	output wire [1:0] mb_i16_mode;
	output wire [1:0] mb_cmode;
	output reg [63:0] mb_i4m;
	output wire coef_we;
	output wire [4:0] coef_blk;
	output wire [3:0] coef_addr;
	output wire signed [15:0] coef_data;
	output wire slice_done;
	output wire err;
	input wire rec_done;
	function automatic [1:0] zsx;
		input reg [3:0] k;
		zsx = {k[2], k[0]};
	endfunction
	function automatic [1:0] zsy;
		input reg [3:0] k;
		zsy = {k[3], k[1]};
	endfunction
	function automatic [3:0] zidx;
		input reg [1:0] bx;
		input reg [1:0] by;
		zidx = {by[1], bx[1], by[0], bx[0]};
	endfunction
	reg [4:0] st_q;
	reg [4:0] ret_q;
	reg [7:0] mbx_q;
	reg [7:0] mby_q;
	reg [15:0] skip_q;
	reg coded_next_q;
	wire skip_rd_q;
	reg inter_q;
	reg [2:0] ptype_q;
	reg [7:0] sub_q;
	reg [2:0] part_q;
	reg [4:0] nmvd_q;
	reg signed [15:0] mvdx_q;
	reg skip_flag_q;
	reg i16_q;
	reg [1:0] i16m_q;
	reg [1:0] cmode_q;
	reg [5:0] cbp_q;
	reg [5:0] qp_q;
	reg [3:0] k_q;
	reg [1:0] comp_q;
	reg [3:0] i4m_q [0:15];
	reg [4:0] nz_q [0:15];
	reg [55:0] nbr_top [0:MAX_MBW - 1];
	reg [15:0] i4t_q;
	reg [19:0] nzlt_q;
	reg [9:0] nzct_q [0:1];
	wire [55:0] nbr_w = nbr_top[mbx_q];
	reg [3:0] i4_left [0:3];
	reg [4:0] nzl_left [0:3];
	reg [4:0] nzc_left [0:1][0:1];
	reg have_left;
	reg [4:0] nzc_q [0:1][0:3];
	wire win_ok;
	assign win_ok = avail >= 7'd24;
	wire [4:0] eg_len;
	wire eg_ok;
	wire [11:0] eg_ue;
	always @(*) begin
		if (_sv2v_0)
			;
		req_valid = 1'b0;
		req_bits = 1'sb0;
		if (win_ok)
			(* full_case, parallel_case *)
			case (st_q)
				5'd2, 5'd16, 5'd17, 5'd18, 5'd19:
					if (eg_ok) begin
						req_valid = 1'b1;
						req_bits = eg_len;
					end
				5'd3: begin
					req_valid = 1'b1;
					req_bits = (show[23] ? 5'd1 : 5'd4);
				end
				5'd4:
					if (eg_ok && (eg_ue <= 12'd3)) begin
						req_valid = 1'b1;
						req_bits = eg_len;
					end
				5'd5:
					if (eg_ok && (eg_ue <= 12'd47)) begin
						req_valid = 1'b1;
						req_bits = eg_len;
					end
				5'd6:
					if (eg_ok) begin
						req_valid = 1'b1;
						req_bits = eg_len;
					end
				default:
					;
			endcase
	end
	wire signed [11:0] eg_se;
	expgolomb u_eg(
		.show(show),
		.ue_val(eg_ue),
		.se_val(eg_se),
		.len(eg_len),
		.ok(eg_ok)
	);
	reg [3:0] predA;
	reg [3:0] predB;
	reg availA;
	reg availB;
	always @(*) begin : sv2v_autoblock_1
		reg [1:0] bx;
		reg [1:0] by;
		if (_sv2v_0)
			;
		bx = zsx(k_q);
		by = zsy(k_q);
		availA = (bx != 0) || have_left;
		availB = (by != 0) || (mby_q != 0);
		if (bx != 0)
			predA = i4m_q[zidx(bx - 2'd1, by)];
		else
			predA = i4_left[by];
		if (by != 0)
			predB = i4m_q[zidx(bx, by - 2'd1)];
		else
			predB = i4t_q[bx * 4+:4];
	end
	wire [3:0] i4_pred;
	assign i4_pred = (!availA || !availB ? 4'd2 : (predA < predB ? predA : predB));
	reg [4:0] nc_l;
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_2
		reg [1:0] bx;
		reg [1:0] by;
		reg [4:0] nA;
		reg [4:0] nB;
		reg aA;
		reg aB;
		if (_sv2v_0)
			;
		bx = zsx(k_q);
		by = zsy(k_q);
		aA = (bx != 0) || have_left;
		aB = (by != 0) || (mby_q != 0);
		nA = (bx != 0 ? nz_q[zidx(bx - 2'd1, by)] : nzl_left[by]);
		nB = (by != 0 ? nz_q[zidx(bx, by - 2'd1)] : nzlt_q[bx * 5+:5]);
		if (aA && aB)
			nc_l = sv2v_cast_5((({1'b0, nA} + {1'b0, nB}) + 6'd1) >> 1);
		else if (aA)
			nc_l = nA;
		else if (aB)
			nc_l = nB;
		else
			nc_l = 1'sb0;
	end
	reg [4:0] nc_c;
	always @(*) begin : sv2v_autoblock_3
		reg cx;
		reg cy;
		reg [4:0] nA;
		reg [4:0] nB;
		reg aA;
		reg aB;
		if (_sv2v_0)
			;
		cx = k_q[0];
		cy = k_q[1];
		aA = cx || have_left;
		aB = cy || (mby_q != 0);
		nA = (cx ? nzc_q[comp_q][{cy, 1'b0}] : nzc_left[comp_q][cy]);
		nB = (cy ? nzc_q[comp_q][{1'b0, cx}] : nzct_q[comp_q][cx * 5+:5]);
		if (aA && aB)
			nc_c = sv2v_cast_5((({1'b0, nA} + {1'b0, nB}) + 6'd1) >> 1);
		else if (aA)
			nc_c = nA;
		else if (aB)
			nc_c = nB;
		else
			nc_c = 1'sb0;
	end
	function automatic [1:0] nc_class_of;
		input reg [4:0] nc;
		if (nc < 5'd2)
			nc_class_of = 2'd0;
		else if (nc < 5'd4)
			nc_class_of = 2'd1;
		else if (nc < 5'd8)
			nc_class_of = 2'd2;
		else
			nc_class_of = 2'd3;
	endfunction
	reg ac15_q;
	assign coef_we = blk_coef_we && (st_q == 5'd9);
	reg [4:0] cur_blk_q;
	assign coef_blk = cur_blk_q;
	function automatic [3:0] zz4;
		input reg [3:0] s;
		reg [3:0] r;
		begin
			(* full_case, parallel_case *)
			case (s)
				4'd0: r = 4'd0;
				4'd1: r = 4'd1;
				4'd2: r = 4'd4;
				4'd3: r = 4'd8;
				4'd4: r = 4'd5;
				4'd5: r = 4'd2;
				4'd6: r = 4'd3;
				4'd7: r = 4'd6;
				4'd8: r = 4'd9;
				4'd9: r = 4'd12;
				4'd10: r = 4'd13;
				4'd11: r = 4'd10;
				4'd12: r = 4'd7;
				4'd13: r = 4'd11;
				4'd14: r = 4'd14;
				4'd15: r = 4'd15;
			endcase
			zz4 = r;
		end
	endfunction
	assign coef_addr = (blk_chroma_dc ? blk_coef_addr : zz4((ac15_q ? blk_coef_addr + 4'd1 : blk_coef_addr)));
	assign coef_data = blk_coef_data;
	assign mb_x = mbx_q;
	assign mb_y = mby_q;
	assign mb_i16 = i16_q;
	assign mb_cbp = cbp_q;
	assign mb_qp = qp_q;
	assign mb_i16_mode = i16m_q;
	assign mb_cmode = cmode_q;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_4
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				mb_i4m[i * 4+:4] = i4m_q[i];
		end
	end
	assign mb_valid = (st_q == 5'd12) || (st_q == 5'd13);
	assign mb_skip = skip_flag_q;
	assign skip_go = st_q == 5'd20;
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_5
		reg signed [31:0] r;
		if (_sv2v_0)
			;
		for (r = 0; r < 16; r = r + 1)
			mb_nz[r] = nz_q[zidx(sv2v_cast_2_signed(r & 3), sv2v_cast_2_signed(r >> 2))] != 5'd0;
	end
	assign mvd_valid = ((st_q == 5'd19) && win_ok) && eg_ok;
	assign mvd_x = mvdx_q;
	function automatic signed [15:0] sv2v_cast_16_signed;
		input reg signed [15:0] inp;
		sv2v_cast_16_signed = inp;
	endfunction
	assign mvd_y = sv2v_cast_16_signed(eg_se);
	assign mb_inter = inter_q;
	assign mb_ptype = ptype_q;
	assign mb_sub = sub_q;
	assign slice_done = st_q == 5'd14;
	assign err = st_q == 5'd15;
	function automatic cbp_l_bit;
		input reg [3:0] k;
		cbp_l_bit = cbp_q[{k[3], k[2]}];
	endfunction
	function automatic [5:0] cavlc_inter_cbp;
		input reg [5:0] code;
		reg [5:0] r;
		begin
			(* full_case, parallel_case *)
			case (code)
				6'd0: r = 6'd0;
				6'd1: r = 6'd16;
				6'd2: r = 6'd1;
				6'd3: r = 6'd2;
				6'd4: r = 6'd4;
				6'd5: r = 6'd8;
				6'd6: r = 6'd32;
				6'd7: r = 6'd3;
				6'd8: r = 6'd5;
				6'd9: r = 6'd10;
				6'd10: r = 6'd12;
				6'd11: r = 6'd15;
				6'd12: r = 6'd47;
				6'd13: r = 6'd7;
				6'd14: r = 6'd11;
				6'd15: r = 6'd13;
				6'd16: r = 6'd14;
				6'd17: r = 6'd6;
				6'd18: r = 6'd9;
				6'd19: r = 6'd31;
				6'd20: r = 6'd35;
				6'd21: r = 6'd37;
				6'd22: r = 6'd42;
				6'd23: r = 6'd44;
				6'd24: r = 6'd33;
				6'd25: r = 6'd34;
				6'd26: r = 6'd36;
				6'd27: r = 6'd40;
				6'd28: r = 6'd39;
				6'd29: r = 6'd43;
				6'd30: r = 6'd45;
				6'd31: r = 6'd46;
				6'd32: r = 6'd17;
				6'd33: r = 6'd18;
				6'd34: r = 6'd20;
				6'd35: r = 6'd24;
				6'd36: r = 6'd19;
				6'd37: r = 6'd21;
				6'd38: r = 6'd26;
				6'd39: r = 6'd28;
				6'd40: r = 6'd23;
				6'd41: r = 6'd27;
				6'd42: r = 6'd29;
				6'd43: r = 6'd30;
				6'd44: r = 6'd22;
				6'd45: r = 6'd25;
				6'd46: r = 6'd38;
				6'd47: r = 6'd41;
				default: r = 6'd63;
			endcase
			cavlc_inter_cbp = r;
		end
	endfunction
	function automatic [5:0] cavlc_intra_cbp;
		input reg [5:0] code;
		reg [5:0] r;
		begin
			(* full_case, parallel_case *)
			case (code)
				6'd0: r = 6'd47;
				6'd1: r = 6'd31;
				6'd2: r = 6'd15;
				6'd3: r = 6'd0;
				6'd4: r = 6'd23;
				6'd5: r = 6'd27;
				6'd6: r = 6'd29;
				6'd7: r = 6'd30;
				6'd8: r = 6'd7;
				6'd9: r = 6'd11;
				6'd10: r = 6'd13;
				6'd11: r = 6'd14;
				6'd12: r = 6'd39;
				6'd13: r = 6'd43;
				6'd14: r = 6'd45;
				6'd15: r = 6'd46;
				6'd16: r = 6'd16;
				6'd17: r = 6'd3;
				6'd18: r = 6'd5;
				6'd19: r = 6'd10;
				6'd20: r = 6'd12;
				6'd21: r = 6'd19;
				6'd22: r = 6'd21;
				6'd23: r = 6'd26;
				6'd24: r = 6'd28;
				6'd25: r = 6'd35;
				6'd26: r = 6'd37;
				6'd27: r = 6'd42;
				6'd28: r = 6'd44;
				6'd29: r = 6'd1;
				6'd30: r = 6'd2;
				6'd31: r = 6'd4;
				6'd32: r = 6'd8;
				6'd33: r = 6'd17;
				6'd34: r = 6'd18;
				6'd35: r = 6'd20;
				6'd36: r = 6'd24;
				6'd37: r = 6'd6;
				6'd38: r = 6'd9;
				6'd39: r = 6'd22;
				6'd40: r = 6'd25;
				6'd41: r = 6'd32;
				6'd42: r = 6'd33;
				6'd43: r = 6'd34;
				6'd44: r = 6'd36;
				6'd45: r = 6'd40;
				6'd46: r = 6'd38;
				6'd47: r = 6'd41;
				default: r = 6'd63;
			endcase
			cavlc_intra_cbp = r;
		end
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	function automatic signed [12:0] sv2v_cast_13_signed;
		input reg signed [12:0] inp;
		sv2v_cast_13_signed = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 5'd0;
			ret_q <= 5'd0;
			blk_start <= 1'b0;
			blk_chroma_dc <= 1'b0;
			blk_nc_class <= 1'sb0;
			blk_maxc <= 1'sb0;
			mbx_q <= 1'sb0;
			mby_q <= 1'sb0;
			i16_q <= 1'b0;
			i16m_q <= 1'sb0;
			cmode_q <= 1'sb0;
			cbp_q <= 1'sb0;
			qp_q <= 1'sb0;
			k_q <= 1'sb0;
			comp_q <= 1'sb0;
			have_left <= 1'b0;
			ac15_q <= 1'b0;
			cur_blk_q <= 1'sb0;
		end
		else begin
			blk_start <= 1'b0;
			(* full_case, parallel_case *)
			case (st_q)
				5'd0:
					if (start) begin
						mbx_q <= 1'sb0;
						mby_q <= 1'sb0;
						qp_q <= cfg_qp;
						have_left <= 1'b0;
						skip_q <= 1'sb0;
						coded_next_q <= 1'b0;
						st_q <= 5'd1;
					end
				5'd1: begin
					i4t_q <= nbr_w[15:0];
					nzlt_q <= nbr_w[35:16];
					nzct_q[0] <= nbr_w[45:36];
					nzct_q[1] <= nbr_w[55:46];
					skip_flag_q <= 1'b0;
					inter_q <= 1'b0;
					ptype_q <= 1'sb0;
					sub_q <= 1'sb0;
					if (cfg_is_p && (skip_q != 16'd0)) begin
						skip_q <= skip_q - 16'd1;
						if (skip_q == 16'd1)
							coded_next_q <= 1'b1;
						skip_flag_q <= 1'b1;
						inter_q <= 1'b1;
						st_q <= 5'd20;
					end
					else begin
						st_q <= (cfg_is_p && !coded_next_q ? 5'd16 : 5'd2);
						coded_next_q <= 1'b0;
					end
				end
				5'd16:
					if (win_ok && eg_ok) begin
						if (eg_ue != 12'd0) begin
							skip_q <= eg_ue - 12'd1;
							if (eg_ue == 12'd1)
								coded_next_q <= 1'b1;
							skip_flag_q <= 1'b1;
							inter_q <= 1'b1;
							st_q <= 5'd20;
						end
						else
							st_q <= 5'd2;
					end
				5'd20: begin
					begin : sv2v_autoblock_6
						reg signed [31:0] k;
						for (k = 0; k < 16; k = k + 1)
							begin
								i4m_q[k] <= 4'd2;
								nz_q[k] <= 1'sb0;
							end
					end
					nzc_q[0][0] <= 1'sb0;
					nzc_q[0][1] <= 1'sb0;
					nzc_q[0][2] <= 1'sb0;
					nzc_q[0][3] <= 1'sb0;
					nzc_q[1][0] <= 1'sb0;
					nzc_q[1][1] <= 1'sb0;
					nzc_q[1][2] <= 1'sb0;
					nzc_q[1][3] <= 1'sb0;
					cbp_q <= 1'sb0;
					i16_q <= 1'b0;
					cmode_q <= 1'sb0;
					st_q <= 5'd12;
				end
				5'd2:
					if (win_ok) begin : sv2v_autoblock_7
						reg [11:0] eff;
						eff = (cfg_is_p && (eg_ue >= 12'd5) ? eg_ue - 12'd5 : eg_ue);
						if (!eg_ok)
							st_q <= 5'd15;
						else if (cfg_is_p && (eg_ue < 12'd5)) begin
							inter_q <= 1'b1;
							ptype_q <= sv2v_cast_3(eg_ue);
							i16_q <= 1'b0;
							begin : sv2v_autoblock_8
								reg signed [31:0] i;
								for (i = 0; i < 16; i = i + 1)
									i4m_q[i] <= 4'd2;
							end
							part_q <= 1'sb0;
							if (eg_ue >= 12'd3) begin
								nmvd_q <= 1'sb0;
								st_q <= 5'd17;
							end
							else begin
								nmvd_q <= (eg_ue == 12'd0 ? 5'd1 : 5'd2);
								st_q <= 5'd18;
							end
						end
						else if (eff == 12'd0) begin
							i16_q <= 1'b0;
							i16m_q <= 1'sb0;
							k_q <= 1'sb0;
							st_q <= 5'd3;
						end
						else if (eff <= 12'd24) begin : sv2v_autoblock_9
							reg [11:0] m;
							reg [1:0] cc;
							m = eff - 12'd1;
							cc = sv2v_cast_2((m >> 2) % 12'd3);
							i16_q <= 1'b1;
							i16m_q <= sv2v_cast_2(m & 12'd3);
							cbp_q <= {cc, (m >= 12'd12 ? 4'hf : 4'h0)};
							begin : sv2v_autoblock_10
								reg signed [31:0] i;
								for (i = 0; i < 16; i = i + 1)
									i4m_q[i] <= 4'd2;
							end
							st_q <= 5'd4;
						end
						else
							st_q <= 5'd15;
					end
				5'd17:
					if (win_ok) begin
						if (!eg_ok || (eg_ue > 12'd3))
							st_q <= 5'd15;
						else begin : sv2v_autoblock_11
							reg [4:0] add;
							sub_q[part_q[1:0] * 2+:2] <= sv2v_cast_2(eg_ue);
							add = (eg_ue == 12'd0 ? 5'd1 : (eg_ue == 12'd3 ? 5'd4 : 5'd2));
							nmvd_q <= nmvd_q + add;
							if (part_q == 3'd3) begin
								part_q <= 1'sb0;
								st_q <= 5'd18;
							end
							else
								part_q <= part_q + 3'd1;
						end
					end
				5'd18:
					if (win_ok) begin
						if (!eg_ok)
							st_q <= 5'd15;
						else begin
							mvdx_q <= sv2v_cast_16_signed(eg_se);
							st_q <= 5'd19;
						end
					end
				5'd19:
					if (win_ok) begin
						if (!eg_ok)
							st_q <= 5'd15;
						else begin
							nmvd_q <= nmvd_q - 5'd1;
							st_q <= (nmvd_q == 5'd1 ? 5'd5 : 5'd18);
						end
					end
				5'd3:
					if (win_ok) begin : sv2v_autoblock_12
						reg [3:0] mode;
						if (show[23])
							mode = i4_pred;
						else begin : sv2v_autoblock_13
							reg [3:0] rem;
							rem = {1'b0, show[22:20]};
							mode = (rem < i4_pred ? rem : rem + 4'd1);
						end
						i4m_q[k_q] <= mode;
						if (k_q == 4'd15)
							st_q <= 5'd4;
						k_q <= k_q + 4'd1;
					end
				5'd4:
					if (win_ok) begin
						if (!eg_ok || (eg_ue > 12'd3))
							st_q <= 5'd15;
						else begin
							cmode_q <= sv2v_cast_2(eg_ue);
							st_q <= (i16_q ? 5'd6 : 5'd5);
						end
					end
				5'd5:
					if (win_ok) begin : sv2v_autoblock_14
						reg [5:0] cbp;
						cbp = (inter_q ? cavlc_inter_cbp(sv2v_cast_6(eg_ue)) : cavlc_intra_cbp(sv2v_cast_6(eg_ue)));
						if ((!eg_ok || (eg_ue > 12'd47)) || (cbp == 6'd63))
							st_q <= 5'd15;
						else begin
							cbp_q <= cbp;
							if (cbp == 6'd0) begin
								begin : sv2v_autoblock_15
									reg signed [31:0] k;
									for (k = 0; k < 16; k = k + 1)
										nz_q[k] <= 1'sb0;
								end
								begin : sv2v_autoblock_16
									reg signed [31:0] k;
									for (k = 0; k < 4; k = k + 1)
										begin
											nzc_q[0][k[1:0]] <= 1'sb0;
											nzc_q[1][k[1:0]] <= 1'sb0;
										end
								end
								st_q <= 5'd12;
							end
							else
								st_q <= 5'd6;
						end
					end
				5'd6:
					if (win_ok) begin
						if (!eg_ok)
							st_q <= 5'd15;
						else begin
							qp_q <= sv2v_cast_6(((sv2v_cast_13_signed($signed({1'b0, qp_q})) + sv2v_cast_13_signed(eg_se)) + 13'd52) % 13'd52);
							k_q <= 1'sb0;
							st_q <= (i16_q ? 5'd7 : 5'd8);
						end
					end
				5'd7: begin
					blk_start <= 1'b1;
					blk_chroma_dc <= 1'b0;
					blk_nc_class <= nc_class_of(nc_l);
					blk_maxc <= 5'd16;
					ac15_q <= 1'b0;
					cur_blk_q <= 5'd16;
					ret_q <= 5'd8;
					st_q <= 5'd9;
				end
				5'd8:
					if (cbp_l_bit(k_q)) begin
						blk_start <= 1'b1;
						blk_chroma_dc <= 1'b0;
						blk_nc_class <= nc_class_of(nc_l);
						blk_maxc <= (i16_q ? 5'd15 : 5'd16);
						ac15_q <= i16_q;
						cur_blk_q <= {1'b0, k_q};
						ret_q <= 5'd8;
						st_q <= 5'd9;
					end
					else begin
						nz_q[k_q] <= 1'sb0;
						if (k_q == 4'd15) begin
							k_q <= 1'sb0;
							comp_q <= 1'sb0;
							st_q <= (cbp_q[5:4] != 2'd0 ? 5'd10 : 5'd12);
						end
						else
							k_q <= k_q + 4'd1;
					end
				5'd10: begin
					blk_start <= 1'b1;
					blk_chroma_dc <= 1'b1;
					blk_nc_class <= 1'sb0;
					blk_maxc <= 5'd4;
					ac15_q <= 1'b0;
					cur_blk_q <= 5'd17 + {4'b0000, comp_q[0]};
					ret_q <= 5'd10;
					st_q <= 5'd9;
				end
				5'd11:
					if (cbp_q[5:4] == 2'd2) begin
						blk_start <= 1'b1;
						blk_chroma_dc <= 1'b0;
						blk_nc_class <= nc_class_of(nc_c);
						blk_maxc <= 5'd15;
						ac15_q <= 1'b1;
						cur_blk_q <= (5'd19 + {2'b00, comp_q[0], 2'b00}) + {3'b000, k_q[1:0]};
						ret_q <= 5'd11;
						st_q <= 5'd9;
					end
					else begin
						nzc_q[comp_q][k_q[1:0]] <= 1'sb0;
						if (k_q[1:0] == 2'd3) begin
							k_q <= 1'sb0;
							if (comp_q[0])
								st_q <= 5'd12;
							comp_q <= comp_q + 2'd1;
						end
						else
							k_q <= k_q + 4'd1;
					end
				5'd9:
					if (blk_err)
						st_q <= 5'd15;
					else if (blk_done)
						(* full_case, parallel_case *)
						case (ret_q)
							5'd8:
								if (cur_blk_q == 5'd16) begin
									k_q <= 1'sb0;
									st_q <= 5'd8;
								end
								else begin
									nz_q[k_q] <= blk_tc;
									if (k_q == 4'd15) begin
										k_q <= 1'sb0;
										comp_q <= 1'sb0;
										st_q <= (cbp_q[5:4] != 2'd0 ? 5'd10 : 5'd12);
									end
									else begin
										k_q <= k_q + 4'd1;
										st_q <= 5'd8;
									end
								end
							5'd10:
								if (comp_q[0]) begin
									comp_q <= 1'sb0;
									k_q <= 1'sb0;
									st_q <= (cbp_q[5:4] == 2'd2 ? 5'd11 : 5'd12);
								end
								else begin
									comp_q <= 2'd1;
									st_q <= 5'd10;
								end
							5'd11: begin
								nzc_q[comp_q][k_q[1:0]] <= blk_tc;
								if (k_q[1:0] == 2'd3) begin
									k_q <= 1'sb0;
									if (comp_q[0])
										st_q <= 5'd12;
									else
										st_q <= 5'd11;
									comp_q <= comp_q + 2'd1;
								end
								else begin
									k_q <= k_q + 4'd1;
									st_q <= 5'd11;
								end
							end
							default: st_q <= 5'd15;
						endcase
				5'd12: begin
					begin : sv2v_autoblock_17
						reg [55:0] w;
						begin : sv2v_autoblock_18
							reg signed [31:0] b;
							for (b = 0; b < 4; b = b + 1)
								begin
									w[b * 4+:4] = i4m_q[zidx(sv2v_cast_2_signed(b), 2'd3)];
									w[16 + (b * 5)+:5] = nz_q[zidx(sv2v_cast_2_signed(b), 2'd3)];
									i4_left[b] <= i4m_q[zidx(2'd3, sv2v_cast_2_signed(b))];
									nzl_left[b] <= nz_q[zidx(2'd3, sv2v_cast_2_signed(b))];
								end
						end
						begin : sv2v_autoblock_19
							reg signed [31:0] b;
							for (b = 0; b < 2; b = b + 1)
								begin
									w[36 + (b * 5)+:5] = (cbp_q[5:4] == 2'd2 ? nzc_q[0][{1'b1, b[0]}] : 5'd0);
									w[46 + (b * 5)+:5] = (cbp_q[5:4] == 2'd2 ? nzc_q[1][{1'b1, b[0]}] : 5'd0);
									nzc_left[0][b] <= (cbp_q[5:4] == 2'd2 ? nzc_q[0][{b[0], 1'b1}] : 5'd0);
									nzc_left[1][b] <= (cbp_q[5:4] == 2'd2 ? nzc_q[1][{b[0], 1'b1}] : 5'd0);
								end
						end
						nbr_top[mbx_q] <= w;
					end
					if (rec_done) begin
						if ((mbx_q + 8'd1) == cfg_mb_w) begin
							have_left <= 1'b0;
							mbx_q <= 1'sb0;
							if ((mby_q + 8'd1) == cfg_mb_h)
								st_q <= 5'd14;
							else begin
								mby_q <= mby_q + 8'd1;
								st_q <= 5'd1;
							end
						end
						else begin
							have_left <= 1'b1;
							mbx_q <= mbx_q + 8'd1;
							st_q <= 5'd1;
						end
					end
					else
						st_q <= 5'd13;
				end
				5'd13:
					if (rec_done) begin
						if ((mbx_q + 8'd1) == cfg_mb_w) begin
							have_left <= 1'b0;
							mbx_q <= 1'sb0;
							if ((mby_q + 8'd1) == cfg_mb_h)
								st_q <= 5'd14;
							else begin
								mby_q <= mby_q + 8'd1;
								st_q <= 5'd1;
							end
						end
						else begin
							have_left <= 1'b1;
							mbx_q <= mbx_q + 8'd1;
							st_q <= 5'd1;
						end
					end
				5'd14: st_q <= 5'd0;
				5'd15: st_q <= 5'd15;
				default: st_q <= 5'd15;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module dequant4x4 (
	c,
	qp,
	d
);
	reg _sv2v_0;
	input wire signed [255:0] c;
	input wire [5:0] qp;
	output reg signed [511:0] d;
	reg [2:0] rem;
	reg [3:0] per;
	function automatic [4:0] transform_pkg_dq_v;
		input reg [2:0] rem;
		input reg [1:0] cls;
		reg [4:0] r;
		begin
			(* full_case, parallel_case *)
			case ({rem, cls})
				5'h00: r = 5'd10;
				5'h01: r = 5'd16;
				5'h02: r = 5'd13;
				5'h04: r = 5'd11;
				5'h05: r = 5'd18;
				5'h06: r = 5'd14;
				5'h08: r = 5'd13;
				5'h09: r = 5'd20;
				5'h0a: r = 5'd16;
				5'h0c: r = 5'd14;
				5'h0d: r = 5'd23;
				5'h0e: r = 5'd18;
				5'h10: r = 5'd16;
				5'h11: r = 5'd25;
				5'h12: r = 5'd20;
				5'h14: r = 5'd18;
				5'h15: r = 5'd29;
				5'h16: r = 5'd23;
				default: r = 5'd0;
			endcase
			transform_pkg_dq_v = r;
		end
	endfunction
	function automatic [1:0] transform_pkg_vclass;
		input reg [3:0] pos;
		reg re;
		reg ce;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			re = ~pos[2];
			ce = ~pos[0];
			if (re && ce) begin
				transform_pkg_vclass = 2'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (!re && !ce) begin
					transform_pkg_vclass = 2'd1;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					transform_pkg_vclass = 2'd2;
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		per = sv2v_cast_4(qp / 6);
		rem = sv2v_cast_3(qp % 6);
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				d[(15 - i) * 32+:32] = (sv2v_cast_32(c[(15 - i) * 16+:16]) * $signed({27'b000000000000000000000000000, transform_pkg_dq_v(rem, transform_pkg_vclass(sv2v_cast_4_signed(i)))})) <<< per;
		end
	end
	initial _sv2v_0 = 0;
endmodule
module luma_dc_dequant (
	c,
	qp,
	dc
);
	reg _sv2v_0;
	input wire signed [255:0] c;
	input wire [5:0] qp;
	output reg signed [511:0] dc;
	function automatic [4:0] transform_pkg_dq_v;
		input reg [2:0] rem;
		input reg [1:0] cls;
		reg [4:0] r;
		begin
			(* full_case, parallel_case *)
			case ({rem, cls})
				5'h00: r = 5'd10;
				5'h01: r = 5'd16;
				5'h02: r = 5'd13;
				5'h04: r = 5'd11;
				5'h05: r = 5'd18;
				5'h06: r = 5'd14;
				5'h08: r = 5'd13;
				5'h09: r = 5'd20;
				5'h0a: r = 5'd16;
				5'h0c: r = 5'd14;
				5'h0d: r = 5'd23;
				5'h0e: r = 5'd18;
				5'h10: r = 5'd16;
				5'h11: r = 5'd25;
				5'h12: r = 5'd20;
				5'h14: r = 5'd18;
				5'h15: r = 5'd29;
				5'h16: r = 5'd23;
				default: r = 5'd0;
			endcase
			transform_pkg_dq_v = r;
		end
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg signed [31:0] t [0:15];
		reg signed [31:0] f [0:15];
		reg [2:0] rem;
		reg [3:0] per;
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_2
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin : sv2v_autoblock_3
					reg signed [31:0] s0;
					reg signed [31:0] s1;
					reg signed [31:0] s2;
					reg signed [31:0] s3;
					s0 = sv2v_cast_32(c[(15 - ((i * 4) + 0)) * 16+:16]) + sv2v_cast_32(c[(15 - ((i * 4) + 2)) * 16+:16]);
					s1 = sv2v_cast_32(c[(15 - ((i * 4) + 0)) * 16+:16]) - sv2v_cast_32(c[(15 - ((i * 4) + 2)) * 16+:16]);
					s2 = sv2v_cast_32(c[(15 - ((i * 4) + 1)) * 16+:16]) - sv2v_cast_32(c[(15 - ((i * 4) + 3)) * 16+:16]);
					s3 = sv2v_cast_32(c[(15 - ((i * 4) + 1)) * 16+:16]) + sv2v_cast_32(c[(15 - ((i * 4) + 3)) * 16+:16]);
					t[(i * 4) + 0] = s0 + s3;
					t[(i * 4) + 1] = s1 + s2;
					t[(i * 4) + 2] = s1 - s2;
					t[(i * 4) + 3] = s0 - s3;
				end
		end
		begin : sv2v_autoblock_4
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_5
					reg signed [31:0] s0;
					reg signed [31:0] s1;
					reg signed [31:0] s2;
					reg signed [31:0] s3;
					s0 = t[0 + j] + t[8 + j];
					s1 = t[0 + j] - t[8 + j];
					s2 = t[4 + j] - t[12 + j];
					s3 = t[4 + j] + t[12 + j];
					f[0 + j] = s0 + s3;
					f[4 + j] = s1 + s2;
					f[8 + j] = s1 - s2;
					f[12 + j] = s0 - s3;
				end
		end
		per = sv2v_cast_4(qp / 6);
		rem = sv2v_cast_3(qp % 6);
		begin : sv2v_autoblock_6
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				dc[(15 - i) * 32+:32] = ((((f[i] * $signed({27'b000000000000000000000000000, transform_pkg_dq_v(rem, 2'd0)})) * 32'sd16) <<< per) + 32'sd32) >>> 6;
		end
	end
	initial _sv2v_0 = 0;
endmodule
module chroma_dc_dequant (
	c,
	qp,
	dc
);
	reg _sv2v_0;
	input wire signed [63:0] c;
	input wire [5:0] qp;
	output reg signed [127:0] dc;
	function automatic [4:0] transform_pkg_dq_v;
		input reg [2:0] rem;
		input reg [1:0] cls;
		reg [4:0] r;
		begin
			(* full_case, parallel_case *)
			case ({rem, cls})
				5'h00: r = 5'd10;
				5'h01: r = 5'd16;
				5'h02: r = 5'd13;
				5'h04: r = 5'd11;
				5'h05: r = 5'd18;
				5'h06: r = 5'd14;
				5'h08: r = 5'd13;
				5'h09: r = 5'd20;
				5'h0a: r = 5'd16;
				5'h0c: r = 5'd14;
				5'h0d: r = 5'd23;
				5'h0e: r = 5'd18;
				5'h10: r = 5'd16;
				5'h11: r = 5'd25;
				5'h12: r = 5'd20;
				5'h14: r = 5'd18;
				5'h15: r = 5'd29;
				5'h16: r = 5'd23;
				default: r = 5'd0;
			endcase
			transform_pkg_dq_v = r;
		end
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg signed [31:0] f0;
		reg signed [31:0] f1;
		reg signed [31:0] f2;
		reg signed [31:0] f3;
		reg [2:0] rem;
		reg [3:0] per;
		if (_sv2v_0)
			;
		f0 = ((sv2v_cast_32(c[48+:16]) + sv2v_cast_32(c[32+:16])) + sv2v_cast_32(c[16+:16])) + sv2v_cast_32(c[0+:16]);
		f1 = ((sv2v_cast_32(c[48+:16]) - sv2v_cast_32(c[32+:16])) + sv2v_cast_32(c[16+:16])) - sv2v_cast_32(c[0+:16]);
		f2 = ((sv2v_cast_32(c[48+:16]) + sv2v_cast_32(c[32+:16])) - sv2v_cast_32(c[16+:16])) - sv2v_cast_32(c[0+:16]);
		f3 = ((sv2v_cast_32(c[48+:16]) - sv2v_cast_32(c[32+:16])) - sv2v_cast_32(c[16+:16])) + sv2v_cast_32(c[0+:16]);
		per = sv2v_cast_4(qp / 6);
		rem = sv2v_cast_3(qp % 6);
		dc[96+:32] = (((f0 * $signed({27'b000000000000000000000000000, transform_pkg_dq_v(rem, 2'd0)})) * 32'sd16) <<< per) >>> 5;
		dc[64+:32] = (((f1 * $signed({27'b000000000000000000000000000, transform_pkg_dq_v(rem, 2'd0)})) * 32'sd16) <<< per) >>> 5;
		dc[32+:32] = (((f2 * $signed({27'b000000000000000000000000000, transform_pkg_dq_v(rem, 2'd0)})) * 32'sd16) <<< per) >>> 5;
		dc[0+:32] = (((f3 * $signed({27'b000000000000000000000000000, transform_pkg_dq_v(rem, 2'd0)})) * 32'sd16) <<< per) >>> 5;
	end
	initial _sv2v_0 = 0;
endmodule
module idct4x4_add (
	d,
	pred,
	out
);
	reg _sv2v_0;
	input wire signed [511:0] d;
	input wire [127:0] pred;
	output reg [127:0] out;
	function automatic [7:0] clip8;
		input reg signed [31:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < 0) begin
				clip8 = 8'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > 255) begin
					clip8 = 8'd255;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip8 = v[7:0];
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg signed [31:0] t [0:15];
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_2
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin : sv2v_autoblock_3
					reg signed [31:0] e0;
					reg signed [31:0] e1;
					reg signed [31:0] e2;
					reg signed [31:0] e3;
					e0 = d[(15 - ((i * 4) + 0)) * 32+:32] + d[(15 - ((i * 4) + 2)) * 32+:32];
					e1 = d[(15 - ((i * 4) + 0)) * 32+:32] - d[(15 - ((i * 4) + 2)) * 32+:32];
					e2 = (d[(15 - ((i * 4) + 1)) * 32+:32] >>> 1) - d[(15 - ((i * 4) + 3)) * 32+:32];
					e3 = d[(15 - ((i * 4) + 1)) * 32+:32] + (d[(15 - ((i * 4) + 3)) * 32+:32] >>> 1);
					t[(i * 4) + 0] = e0 + e3;
					t[(i * 4) + 1] = e1 + e2;
					t[(i * 4) + 2] = e1 - e2;
					t[(i * 4) + 3] = e0 - e3;
				end
		end
		begin : sv2v_autoblock_4
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_5
					reg signed [31:0] e0;
					reg signed [31:0] e1;
					reg signed [31:0] e2;
					reg signed [31:0] e3;
					reg signed [31:0] g0;
					reg signed [31:0] g1;
					reg signed [31:0] g2;
					reg signed [31:0] g3;
					e0 = t[0 + j] + t[8 + j];
					e1 = t[0 + j] - t[8 + j];
					e2 = (t[4 + j] >>> 1) - t[12 + j];
					e3 = t[4 + j] + (t[12 + j] >>> 1);
					g0 = e0 + e3;
					g1 = e1 + e2;
					g2 = e1 - e2;
					g3 = e0 - e3;
					out[(15 - (0 + j)) * 8+:8] = clip8($signed({24'b000000000000000000000000, pred[(15 - (0 + j)) * 8+:8]}) + ((g0 + 32'sd32) >>> 6));
					out[(15 - (4 + j)) * 8+:8] = clip8($signed({24'b000000000000000000000000, pred[(15 - (4 + j)) * 8+:8]}) + ((g1 + 32'sd32) >>> 6));
					out[(15 - (8 + j)) * 8+:8] = clip8($signed({24'b000000000000000000000000, pred[(15 - (8 + j)) * 8+:8]}) + ((g2 + 32'sd32) >>> 6));
					out[(15 - (12 + j)) * 8+:8] = clip8($signed({24'b000000000000000000000000, pred[(15 - (12 + j)) * 8+:8]}) + ((g3 + 32'sd32) >>> 6));
				end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module mb_recon (
	clk,
	rst_n,
	cfg_mb_w,
	cfg_cqp_off,
	coef_we,
	coef_blk,
	coef_addr,
	coef_data,
	mb_valid,
	mb_x,
	mb_y,
	mb_inter,
	mb_nz,
	mb_mvx,
	mb_mvy,
	mb_i16,
	mb_cbp,
	mb_qp,
	mb_i16_mode,
	mb_cmode,
	mb_i4m,
	busy,
	accepted,
	rec_x,
	rec_yc,
	rec_qp,
	out_ready,
	rec_valid,
	rec_y,
	rec_u,
	rec_v,
	rec_inter,
	rec_nz,
	rec_mvx,
	rec_mvy,
	err,
	mc_req_valid,
	mc_req_plane,
	mc_req_x,
	mc_req_y,
	mc_req_w,
	mc_rsp_valid,
	mc_rsp_data
);
	reg _sv2v_0;
	parameter signed [31:0] MAX_MBW = 120;
	input wire clk;
	input wire rst_n;
	input wire [7:0] cfg_mb_w;
	input wire signed [5:0] cfg_cqp_off;
	input wire coef_we;
	input wire [4:0] coef_blk;
	input wire [3:0] coef_addr;
	input wire signed [15:0] coef_data;
	input wire mb_valid;
	input wire [7:0] mb_x;
	input wire [7:0] mb_y;
	input wire mb_inter;
	input wire [15:0] mb_nz;
	input wire signed [255:0] mb_mvx;
	input wire signed [255:0] mb_mvy;
	input wire mb_i16;
	input wire [5:0] mb_cbp;
	input wire [5:0] mb_qp;
	input wire [1:0] mb_i16_mode;
	input wire [1:0] mb_cmode;
	input wire [63:0] mb_i4m;
	output wire busy;
	output wire accepted;
	output wire [7:0] rec_x;
	output wire [7:0] rec_yc;
	output wire [5:0] rec_qp;
	input wire out_ready;
	output wire rec_valid;
	output reg [2047:0] rec_y;
	output reg [511:0] rec_u;
	output reg [511:0] rec_v;
	output wire rec_inter;
	output wire [15:0] rec_nz;
	output reg signed [255:0] rec_mvx;
	output reg signed [255:0] rec_mvy;
	output wire err;
	output wire mc_req_valid;
	output wire [1:0] mc_req_plane;
	output wire signed [12:0] mc_req_x;
	output wire signed [11:0] mc_req_y;
	output wire [3:0] mc_req_w;
	input wire mc_rsp_valid;
	input wire [71:0] mc_rsp_data;
	function automatic [5:0] chroma_qp;
		input reg [5:0] q;
		reg [5:0] r;
		begin
			(* full_case, parallel_case *)
			case (q)
				6'd30: r = 6'd29;
				6'd31: r = 6'd30;
				6'd32: r = 6'd31;
				6'd33: r = 6'd32;
				6'd34: r = 6'd32;
				6'd35: r = 6'd33;
				6'd36: r = 6'd34;
				6'd37: r = 6'd34;
				6'd38: r = 6'd35;
				6'd39: r = 6'd35;
				6'd40: r = 6'd36;
				6'd41: r = 6'd36;
				6'd42: r = 6'd37;
				6'd43: r = 6'd37;
				6'd44: r = 6'd37;
				6'd45: r = 6'd38;
				6'd46: r = 6'd38;
				6'd47: r = 6'd38;
				6'd48: r = 6'd39;
				6'd49: r = 6'd39;
				6'd50: r = 6'd39;
				6'd51: r = 6'd39;
				default: r = q;
			endcase
			chroma_qp = r;
		end
	endfunction
	function automatic [1:0] zsx;
		input reg [3:0] k;
		zsx = {k[2], k[0]};
	endfunction
	function automatic [1:0] zsy;
		input reg [3:0] k;
		zsy = {k[3], k[1]};
	endfunction
	function automatic [3:0] zidx;
		input reg [1:0] bx;
		input reg [1:0] by;
		zidx = {by[1], bx[1], by[0], bx[0]};
	endfunction
	reg [255:0] cramA [0:26];
	reg [255:0] cramB [0:26];
	reg wb_q;
	reg [4:0] clr_q;
	reg [4:0] dq_row;
	wire [255:0] cramA_wr_old = cramA[coef_blk];
	wire [255:0] cramB_wr_old = cramB[coef_blk];
	reg [255:0] cram_wr_new;
	always @(*) begin
		if (_sv2v_0)
			;
		cram_wr_new = (wb_q ? cramB_wr_old : cramA_wr_old);
		cram_wr_new[coef_addr * 16+:16] = coef_data;
	end
	wire [255:0] cram_ldc_w = (wb_q ? cramA[16] : cramB[16]);
	reg comp_q;
	wire [255:0] cram_cdc_w = (wb_q ? cramA[{4'b1000, comp_q} + 5'd1] : cramB[{4'b1000, comp_q} + 5'd1]);
	wire [255:0] cram_dq_w = (wb_q ? cramA[dq_row] : cramB[dq_row]);
	reg [127:0] top_y [0:MAX_MBW - 1];
	reg [63:0] top_u [0:MAX_MBW - 1];
	reg [63:0] top_v [0:MAX_MBW - 1];
	reg [127:0] tyc_q;
	reg [127:0] tyn_q;
	reg [63:0] tuc_q;
	reg [63:0] tvc_q;
	wire [127:0] ty_cur_w = top_y[mb_x];
	wire [127:0] ty_nxt_w = top_y[mb_x + 8'd1];
	wire [63:0] tu_cur_w = top_u[mb_x];
	wire [63:0] tv_cur_w = top_v[mb_x];
	reg [7:0] left_y [0:15];
	reg [7:0] left_u [0:7];
	reg [7:0] left_v [0:7];
	reg [7:0] tl_y;
	reg [7:0] tl_u;
	reg [7:0] tl_v;
	reg [7:0] tlq_y;
	reg [7:0] tlq_u;
	reg [7:0] tlq_v;
	reg [7:0] mbx_q;
	reg [7:0] mby_q;
	reg i16_q;
	reg [5:0] cbp_q;
	reg [5:0] qp_q;
	reg [1:0] i16m_q;
	reg [1:0] cmode_q;
	reg [3:0] i4m_q [0:15];
	reg have_left;
	reg have_top;
	reg [3:0] st_q;
	reg [4:0] k_q;
	reg inter_q;
	reg signed [15:0] mvq_x [0:15];
	reg signed [15:0] mvq_y [0:15];
	reg [5:0] mk_q;
	reg [15:0] nz_q;
	localparam signed [511:0] Z2R = 512'h100000004000000050000000200000003000000060000000700000008000000090000000c0000000d0000000a0000000b0000000e0000000f;
	assign rec_inter = inter_q;
	assign rec_nz = nz_q;
	always @(*) begin : sv2v_autoblock_1
		reg signed [31:0] r;
		if (_sv2v_0)
			;
		for (r = 0; r < 16; r = r + 1)
			begin
				rec_mvx[(15 - r) * 16+:16] = mvq_x[Z2R[(15 - r) * 32+:32]];
				rec_mvy[(15 - r) * 16+:16] = mvq_y[Z2R[(15 - r) * 32+:32]];
			end
	end
	wire mc_start_w;
	wire mc_busy_w;
	wire mc_done_w;
	wire [127:0] mc_pred_w;
	wire [3:0] mck;
	wire mc_is_c;
	reg [11:0] mc_px;
	reg [10:0] mc_py;
	assign mck = mk_q[3:0];
	assign mc_is_c = mk_q[5:4] != 2'd0;
	function automatic [11:0] sv2v_cast_12;
		input reg [11:0] inp;
		sv2v_cast_12 = inp;
	endfunction
	function automatic [10:0] sv2v_cast_11;
		input reg [10:0] inp;
		sv2v_cast_11 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		if (mc_is_c) begin
			mc_px = {1'b0, mbx_q, 3'b000} + sv2v_cast_12({zsx(mck), 1'b0});
			mc_py = {mby_q, 3'b000} + sv2v_cast_11({zsy(mck), 1'b0});
		end
		else begin
			mc_px = {mbx_q, 4'b0000} + sv2v_cast_12({zsx(mck), 2'b00});
			mc_py = sv2v_cast_11({mby_q, 4'b0000}) + sv2v_cast_11({zsy(mck), 2'b00});
		end
	end
	assign mc_start_w = ((st_q == 4'd13) && !mc_busy_w) && !mc_done_w;
	assign mc_req_plane = mk_q[5:4];
	mc_fetch u_mc(
		.clk(clk),
		.rst_n(rst_n),
		.start(mc_start_w),
		.is_chroma(mc_is_c),
		.px(mc_px),
		.py(mc_py),
		.mvx(mvq_x[mck]),
		.mvy(mvq_y[mck]),
		.busy(mc_busy_w),
		.done(mc_done_w),
		.req_valid(mc_req_valid),
		.req_x(mc_req_x),
		.req_y(mc_req_y),
		.req_w(mc_req_w),
		.rsp_valid(mc_rsp_valid),
		.rsp_data(mc_rsp_data),
		.pred(mc_pred_w)
	);
	assign busy = st_q != 4'd0;
	assign accepted = (st_q == 4'd0) && mb_valid;
	assign rec_x = mbx_q;
	assign rec_yc = mby_q;
	assign rec_qp = qp_q;
	assign rec_valid = st_q == 4'd11;
	assign err = st_q == 4'd12;
	reg signed [255:0] ldc_in;
	wire signed [511:0] ldc_out;
	always @(*) begin : sv2v_autoblock_2
		reg signed [31:0] i;
		if (_sv2v_0)
			;
		for (i = 0; i < 16; i = i + 1)
			ldc_in[(15 - i) * 16+:16] = cram_ldc_w[i * 16+:16];
	end
	luma_dc_dequant u_ldc(
		.c(ldc_in),
		.qp(qp_q),
		.dc(ldc_out)
	);
	reg signed [31:0] ldc_q [0:15];
	reg signed [63:0] cdc_in;
	wire signed [127:0] cdc_out;
	reg [5:0] qpc;
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	function automatic signed [5:0] sv2v_cast_6_signed;
		input reg signed [5:0] inp;
		sv2v_cast_6_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_3
		reg signed [7:0] qsum;
		if (_sv2v_0)
			;
		qsum = $signed({2'b00, qp_q}) + sv2v_cast_8_signed(cfg_cqp_off);
		if (qsum < 0)
			qsum = 0;
		if (qsum > 51)
			qsum = 51;
		qpc = chroma_qp(sv2v_cast_6_signed(qsum));
		begin : sv2v_autoblock_4
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				cdc_in[(3 - i) * 16+:16] = cram_cdc_w[i * 16+:16];
		end
	end
	chroma_dc_dequant u_cdc(
		.c(cdc_in),
		.qp(qpc),
		.dc(cdc_out)
	);
	reg signed [31:0] cdc_q [0:3];
	always @(*) begin
		if (_sv2v_0)
			;
		if ((st_q == 4'd7) || (st_q == 4'd8))
			dq_row = (5'd19 + ({3'b000, comp_q} * 5'd4)) + (k_q & 5'd3);
		else
			dq_row = k_q;
	end
	reg signed [255:0] dq_in;
	wire signed [511:0] dq_out;
	wire [5:0] dq_qp;
	assign dq_qp = ((st_q == 4'd7) || (st_q == 4'd8) ? qpc : qp_q);
	dequant4x4 u_dq(
		.c(dq_in),
		.qp(dq_qp),
		.d(dq_out)
	);
	reg signed [31:0] id_in [0:15];
	reg [7:0] id_pred [0:15];
	reg signed [511:0] id_in_q;
	reg [127:0] id_pred_q;
	wire [127:0] id_out;
	idct4x4_add u_id(
		.d(id_in_q),
		.pred(id_pred_q),
		.out(id_out)
	);
	wire [1:0] bx4;
	wire [1:0] by4;
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	assign bx4 = zsx(sv2v_cast_4(k_q));
	assign by4 = zsy(sv2v_cast_4(k_q));
	reg [31:0] n_l;
	reg [63:0] n_t;
	reg [7:0] n_tl;
	reg a_l;
	reg a_t;
	reg a_tl;
	reg a_tr;
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_5
		reg signed [31:0] px;
		reg signed [31:0] py;
		if (_sv2v_0)
			;
		px = sv2v_cast_32_signed(bx4) * 4;
		py = sv2v_cast_32_signed(by4) * 4;
		a_l = (bx4 != 0) || have_left;
		a_t = (by4 != 0) || have_top;
		a_tl = ((bx4 != 0) || have_left) && ((by4 != 0) || have_top);
		if (by4 == 0)
			a_tr = have_top && (bx4 != 2'd3 ? 1'b1 : ({mbx_q, 2'b00} + 8'd4) < {cfg_mb_w, 2'b00});
		else
			a_tr = (bx4 != 2'd3) && (zidx(bx4 + 2'd1, by4 - 2'd1) < sv2v_cast_4(k_q));
		begin : sv2v_autoblock_6
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				n_l[(3 - i) * 8+:8] = (bx4 == 0 ? left_y[py + i] : rec_y[(256 - (((py + i) * 16) + px)) * 8+:8]);
		end
		begin : sv2v_autoblock_7
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				n_t[(7 - i) * 8+:8] = (by4 == 0 ? tyc_q[(px + i) * 8+:8] : rec_y[(255 - ((((py - 1) * 16) + px) + i)) * 8+:8]);
		end
		begin : sv2v_autoblock_8
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin : sv2v_autoblock_9
					reg [7:0] e;
					if (!a_tr)
						e = n_t[32+:8];
					else if (by4 == 0)
						e = (((px + 4) + i) < 16 ? tyc_q[((px + 4) + i) * 8+:8] : tyn_q[(((px + 4) + i) - 16) * 8+:8]);
					else
						e = rec_y[(255 - (((((py - 1) * 16) + px) + 4) + i)) * 8+:8];
					n_t[(7 - (4 + i)) * 8+:8] = e;
				end
		end
		if ((bx4 == 0) && (by4 == 0))
			n_tl = tlq_y;
		else if (bx4 == 0)
			n_tl = left_y[py - 1];
		else if (by4 == 0)
			n_tl = tyc_q[(px - 1) * 8+:8];
		else
			n_tl = rec_y[(256 - (((py - 1) * 16) + px)) * 8+:8];
	end
	wire [127:0] p4;
	wire p4_ok;
	intra4x4_pred u_i4(
		.l(n_l),
		.t(n_t),
		.tl(n_tl),
		.avail_left(a_l),
		.avail_top(a_t),
		.avail_topleft(a_tl),
		.mode(i4m_q[sv2v_cast_4(k_q)]),
		.pred(p4),
		.ok(p4_ok)
	);
	reg [127:0] i16_l;
	reg [127:0] i16_t;
	wire [2047:0] p16;
	wire p16_ok;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_10
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				begin
					i16_l[(15 - i) * 8+:8] = left_y[i];
					i16_t[(15 - i) * 8+:8] = tyc_q[i * 8+:8];
				end
		end
	end
	intra16_pred u_i16(
		.l(i16_l),
		.t(i16_t),
		.tl(tlq_y),
		.avail_left(have_left),
		.avail_top(have_top),
		.mode(i16m_q),
		.pred(p16),
		.ok(p16_ok)
	);
	reg [63:0] ch_l;
	reg [63:0] ch_t;
	reg [7:0] ch_tl;
	wire [511:0] pch;
	wire pch_ok;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_11
			reg signed [31:0] i;
			for (i = 0; i < 8; i = i + 1)
				begin
					ch_l[(7 - i) * 8+:8] = (comp_q ? left_v[i] : left_u[i]);
					ch_t[(7 - i) * 8+:8] = (comp_q ? tvc_q[i * 8+:8] : tuc_q[i * 8+:8]);
				end
		end
		ch_tl = (comp_q ? tlq_v : tlq_u);
	end
	chroma_pred u_ch(
		.l(ch_l),
		.t(ch_t),
		.tl(ch_tl),
		.avail_left(have_left),
		.avail_top(have_top),
		.mode(cmode_q),
		.pred(pch),
		.ok(pch_ok)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_12
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				begin
					dq_in[(15 - i) * 16+:16] = 1'sb0;
					id_pred[i] = 1'sb0;
				end
		end
		if ((st_q == 4'd3) || (st_q == 4'd4)) begin : sv2v_autoblock_13
			reg signed [31:0] px;
			reg signed [31:0] py;
			px = sv2v_cast_32_signed(bx4) * 4;
			py = sv2v_cast_32_signed(by4) * 4;
			begin : sv2v_autoblock_14
				reg signed [31:0] i;
				for (i = 0; i < 16; i = i + 1)
					dq_in[(15 - i) * 16+:16] = cram_dq_w[i * 16+:16];
			end
			begin : sv2v_autoblock_15
				reg signed [31:0] y;
				for (y = 0; y < 4; y = y + 1)
					begin : sv2v_autoblock_16
						reg signed [31:0] x;
						for (x = 0; x < 4; x = x + 1)
							id_pred[(y * 4) + x] = (i16_q || inter_q ? rec_y[(255 - ((((py + y) * 16) + px) + x)) * 8+:8] : p4[(15 - ((y * 4) + x)) * 8+:8]);
					end
			end
		end
		else if ((st_q == 4'd7) || (st_q == 4'd8)) begin : sv2v_autoblock_17
			reg signed [31:0] px;
			reg signed [31:0] py;
			px = (sv2v_cast_32_signed(k_q) & 1) * 4;
			py = ((sv2v_cast_32_signed(k_q) >> 1) & 1) * 4;
			begin : sv2v_autoblock_18
				reg signed [31:0] i;
				for (i = 0; i < 16; i = i + 1)
					dq_in[(15 - i) * 16+:16] = cram_dq_w[i * 16+:16];
			end
			begin : sv2v_autoblock_19
				reg signed [31:0] y;
				for (y = 0; y < 4; y = y + 1)
					begin : sv2v_autoblock_20
						reg signed [31:0] x;
						for (x = 0; x < 4; x = x + 1)
							id_pred[(y * 4) + x] = (comp_q ? rec_v[(63 - ((((py + y) * 8) + px) + x)) * 8+:8] : rec_u[(63 - ((((py + y) * 8) + px) + x)) * 8+:8]);
					end
			end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_21
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				id_in[i] = dq_out[(15 - i) * 32+:32];
		end
		if (((st_q == 4'd3) || (st_q == 4'd4)) && i16_q)
			id_in[0] = ldc_q[{by4, bx4}];
		if ((st_q == 4'd7) || (st_q == 4'd8))
			id_in[0] = cdc_q[k_q & 5'd3];
	end
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 4'd0;
			k_q <= 1'sb0;
			comp_q <= 1'b0;
			mbx_q <= 1'sb0;
			mby_q <= 1'sb0;
			i16_q <= 1'b0;
			cbp_q <= 1'sb0;
			qp_q <= 1'sb0;
			i16m_q <= 1'sb0;
			cmode_q <= 1'sb0;
			have_left <= 1'b0;
			have_top <= 1'b0;
			tl_y <= 1'sb0;
			tl_u <= 1'sb0;
			tl_v <= 1'sb0;
			tlq_y <= 1'sb0;
			tlq_u <= 1'sb0;
			tlq_v <= 1'sb0;
			clr_q <= 1'sb0;
			wb_q <= 1'b0;
			inter_q <= 1'b0;
			mk_q <= 1'sb0;
		end
		else begin
			if (wb_q) begin
				if (coef_we)
					cramB[coef_blk] <= cram_wr_new;
				if (st_q == 4'd10)
					cramA[clr_q] <= 1'sb0;
			end
			else begin
				if (coef_we)
					cramA[coef_blk] <= cram_wr_new;
				if (st_q == 4'd10)
					cramB[clr_q] <= 1'sb0;
			end
			(* full_case, parallel_case *)
			case (st_q)
				4'd0:
					if (mb_valid) begin
						wb_q <= ~wb_q;
						mbx_q <= mb_x;
						mby_q <= mb_y;
						i16_q <= mb_i16;
						cbp_q <= mb_cbp;
						qp_q <= mb_qp;
						i16m_q <= mb_i16_mode;
						cmode_q <= mb_cmode;
						begin : sv2v_autoblock_22
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								i4m_q[i] <= mb_i4m[i * 4+:4];
						end
						inter_q <= mb_inter;
						nz_q <= mb_nz;
						begin : sv2v_autoblock_23
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								begin
									mvq_x[i] <= mb_mvx[(15 - i) * 16+:16];
									mvq_y[i] <= mb_mvy[(15 - i) * 16+:16];
								end
						end
						mk_q <= 1'sb0;
						have_left <= mb_x != 8'd0;
						have_top <= mb_y != 8'd0;
						tlq_y <= tl_y;
						tlq_u <= tl_u;
						tlq_v <= tl_v;
						tl_y <= ty_cur_w[127:120];
						tl_u <= tu_cur_w[63:56];
						tl_v <= tv_cur_w[63:56];
						tyc_q <= ty_cur_w;
						tyn_q <= ((mb_x + 8'd1) < cfg_mb_w ? ty_nxt_w : {128 {1'sb0}});
						tuc_q <= tu_cur_w;
						tvc_q <= tv_cur_w;
						st_q <= (mb_i16 ? 4'd1 : (mb_inter ? 4'd13 : 4'd3));
						k_q <= 1'sb0;
					end
				4'd13:
					if (mc_done_w) begin
						if (!mc_is_c) begin : sv2v_autoblock_24
							reg signed [31:0] y;
							for (y = 0; y < 4; y = y + 1)
								begin : sv2v_autoblock_25
									reg signed [31:0] x;
									for (x = 0; x < 4; x = x + 1)
										rec_y[(255 - (((((sv2v_cast_32_signed(zsy(mck)) * 4) + y) * 16) + (sv2v_cast_32_signed(zsx(mck)) * 4)) + x)) * 8+:8] <= mc_pred_w[(15 - ((y * 4) + x)) * 8+:8];
								end
						end
						else if (!mk_q[5]) begin : sv2v_autoblock_26
							reg signed [31:0] y;
							for (y = 0; y < 2; y = y + 1)
								begin : sv2v_autoblock_27
									reg signed [31:0] x;
									for (x = 0; x < 2; x = x + 1)
										rec_u[(63 - (((((sv2v_cast_32_signed(zsy(mck)) * 2) + y) * 8) + (sv2v_cast_32_signed(zsx(mck)) * 2)) + x)) * 8+:8] <= mc_pred_w[(15 - ((y * 4) + x)) * 8+:8];
								end
						end
						else begin : sv2v_autoblock_28
							reg signed [31:0] y;
							for (y = 0; y < 2; y = y + 1)
								begin : sv2v_autoblock_29
									reg signed [31:0] x;
									for (x = 0; x < 2; x = x + 1)
										rec_v[(63 - (((((sv2v_cast_32_signed(zsy(mck)) * 2) + y) * 8) + (sv2v_cast_32_signed(zsx(mck)) * 2)) + x)) * 8+:8] <= mc_pred_w[(15 - ((y * 4) + x)) * 8+:8];
								end
						end
						if (mk_q == 6'd47) begin
							mk_q <= 1'sb0;
							k_q <= 1'sb0;
							st_q <= 4'd3;
						end
						else
							mk_q <= mk_q + 6'd1;
					end
				4'd1: begin
					begin : sv2v_autoblock_30
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							ldc_q[i] <= ldc_out[(15 - i) * 32+:32];
					end
					st_q <= 4'd2;
				end
				4'd2:
					if (!p16_ok)
						st_q <= 4'd12;
					else begin
						begin : sv2v_autoblock_31
							reg signed [31:0] i;
							for (i = 0; i < 256; i = i + 1)
								rec_y[(255 - i) * 8+:8] <= p16[(255 - i) * 8+:8];
						end
						st_q <= 4'd3;
					end
				4'd3:
					if ((!i16_q && !inter_q) && !p4_ok)
						st_q <= 4'd12;
					else begin
						begin : sv2v_autoblock_32
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								begin
									id_in_q[(15 - i) * 32+:32] <= id_in[i];
									id_pred_q[(15 - i) * 8+:8] <= id_pred[i];
								end
						end
						st_q <= 4'd4;
					end
				4'd4: begin : sv2v_autoblock_33
					reg signed [31:0] px;
					reg signed [31:0] py;
					px = sv2v_cast_32_signed(bx4) * 4;
					py = sv2v_cast_32_signed(by4) * 4;
					begin : sv2v_autoblock_34
						reg signed [31:0] y;
						for (y = 0; y < 4; y = y + 1)
							begin : sv2v_autoblock_35
								reg signed [31:0] x;
								for (x = 0; x < 4; x = x + 1)
									rec_y[(255 - ((((py + y) * 16) + px) + x)) * 8+:8] <= id_out[(15 - ((y * 4) + x)) * 8+:8];
							end
					end
					if (k_q == 5'd15) begin
						k_q <= 1'sb0;
						comp_q <= 1'b0;
						st_q <= (inter_q ? (cbp_q[5:4] != 2'd0 ? 4'd6 : 4'd9) : 4'd5);
					end
					else begin
						k_q <= k_q + 5'd1;
						st_q <= 4'd3;
					end
				end
				4'd5:
					if (!pch_ok)
						st_q <= 4'd12;
					else if (!comp_q) begin
						begin : sv2v_autoblock_36
							reg signed [31:0] i;
							for (i = 0; i < 64; i = i + 1)
								rec_u[(63 - i) * 8+:8] <= pch[(63 - i) * 8+:8];
						end
						comp_q <= 1'b1;
					end
					else begin
						begin : sv2v_autoblock_37
							reg signed [31:0] i;
							for (i = 0; i < 64; i = i + 1)
								rec_v[(63 - i) * 8+:8] <= pch[(63 - i) * 8+:8];
						end
						comp_q <= 1'b0;
						k_q <= 1'sb0;
						st_q <= (cbp_q[5:4] != 2'd0 ? 4'd6 : 4'd9);
					end
				4'd6: begin
					begin : sv2v_autoblock_38
						reg signed [31:0] i;
						for (i = 0; i < 4; i = i + 1)
							cdc_q[i] <= cdc_out[(3 - i) * 32+:32];
					end
					k_q <= 1'sb0;
					st_q <= 4'd7;
				end
				4'd7: begin
					begin : sv2v_autoblock_39
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							begin
								id_in_q[(15 - i) * 32+:32] <= id_in[i];
								id_pred_q[(15 - i) * 8+:8] <= id_pred[i];
							end
					end
					st_q <= 4'd8;
				end
				4'd8: begin : sv2v_autoblock_40
					reg signed [31:0] px;
					reg signed [31:0] py;
					px = (sv2v_cast_32_signed(k_q) & 1) * 4;
					py = ((sv2v_cast_32_signed(k_q) >> 1) & 1) * 4;
					if (comp_q) begin : sv2v_autoblock_41
						reg signed [31:0] y;
						for (y = 0; y < 4; y = y + 1)
							begin : sv2v_autoblock_42
								reg signed [31:0] x;
								for (x = 0; x < 4; x = x + 1)
									rec_v[(63 - ((((py + y) * 8) + px) + x)) * 8+:8] <= id_out[(15 - ((y * 4) + x)) * 8+:8];
							end
					end
					else begin : sv2v_autoblock_43
						reg signed [31:0] y;
						for (y = 0; y < 4; y = y + 1)
							begin : sv2v_autoblock_44
								reg signed [31:0] x;
								for (x = 0; x < 4; x = x + 1)
									rec_u[(63 - ((((py + y) * 8) + px) + x)) * 8+:8] <= id_out[(15 - ((y * 4) + x)) * 8+:8];
							end
					end
					if (k_q == 5'd3) begin
						if (comp_q)
							st_q <= 4'd9;
						else begin
							comp_q <= 1'b1;
							st_q <= 4'd6;
						end
					end
					else begin
						k_q <= k_q + 5'd1;
						st_q <= 4'd7;
					end
				end
				4'd9: begin : sv2v_autoblock_45
					reg [127:0] wy;
					reg [63:0] wu;
					reg [63:0] wv;
					begin : sv2v_autoblock_46
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							begin
								wy[i * 8+:8] = rec_y[(255 - (240 + i)) * 8+:8];
								left_y[i] <= rec_y[(255 - ((i * 16) + 15)) * 8+:8];
							end
					end
					begin : sv2v_autoblock_47
						reg signed [31:0] i;
						for (i = 0; i < 8; i = i + 1)
							begin
								wu[i * 8+:8] = rec_u[(63 - (56 + i)) * 8+:8];
								wv[i * 8+:8] = rec_v[(63 - (56 + i)) * 8+:8];
								left_u[i] <= rec_u[(63 - ((i * 8) + 7)) * 8+:8];
								left_v[i] <= rec_v[(63 - ((i * 8) + 7)) * 8+:8];
							end
					end
					top_y[mbx_q] <= wy;
					top_u[mbx_q] <= wu;
					top_v[mbx_q] <= wv;
					clr_q <= 1'sb0;
					st_q <= 4'd11;
				end
				4'd11:
					if (out_ready)
						st_q <= 4'd10;
				4'd10: begin
					clr_q <= clr_q + 5'd1;
					if (clr_q == 5'd26)
						st_q <= 4'd0;
				end
				4'd12: st_q <= 4'd12;
				default: st_q <= 4'd12;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module mc_fetch (
	clk,
	rst_n,
	start,
	is_chroma,
	px,
	py,
	mvx,
	mvy,
	busy,
	done,
	req_valid,
	req_x,
	req_y,
	req_w,
	rsp_valid,
	rsp_data,
	pred
);
	reg _sv2v_0;
	input wire clk;
	input wire rst_n;
	input wire start;
	input wire is_chroma;
	input wire [11:0] px;
	input wire [10:0] py;
	input wire signed [15:0] mvx;
	input wire signed [15:0] mvy;
	output wire busy;
	output wire done;
	output wire req_valid;
	output wire signed [12:0] req_x;
	output wire signed [11:0] req_y;
	output wire [3:0] req_w;
	input wire rsp_valid;
	input wire [71:0] rsp_data;
	output reg [127:0] pred;
	reg [647:0] lwin;
	reg [199:0] cwin;
	reg chroma_q;
	reg signed [12:0] x0_q;
	reg signed [11:0] y0_q;
	reg [1:0] lfx_q;
	reg [1:0] lfy_q;
	reg [2:0] cfx_q;
	reg [2:0] cfy_q;
	reg [3:0] row_q;
	reg [3:0] got_q;
	reg [1:0] st_q;
	assign busy = st_q != 2'd0;
	assign done = st_q == 2'd2;
	wire [3:0] nrows;
	assign nrows = (chroma_q ? 4'd5 : 4'd9);
	assign req_valid = (st_q == 2'd1) && (row_q < nrows);
	assign req_x = x0_q;
	function automatic [11:0] sv2v_cast_12;
		input reg [11:0] inp;
		sv2v_cast_12 = inp;
	endfunction
	assign req_y = y0_q + sv2v_cast_12(row_q);
	assign req_w = (chroma_q ? 4'd5 : 4'd9);
	wire [127:0] lpred;
	wire [127:0] cpred;
	mc4x4_luma u_l(
		.win(lwin),
		.fx(lfx_q),
		.fy(lfy_q),
		.pred(lpred)
	);
	mc4x4_chroma u_c(
		.win(cwin),
		.fx(cfx_q),
		.fy(cfy_q),
		.pred(cpred)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				pred[(15 - i) * 8+:8] = (chroma_q ? cpred[(15 - i) * 8+:8] : lpred[(15 - i) * 8+:8]);
		end
	end
	function automatic signed [12:0] sv2v_cast_13_signed;
		input reg signed [12:0] inp;
		sv2v_cast_13_signed = inp;
	endfunction
	function automatic signed [11:0] sv2v_cast_12_signed;
		input reg signed [11:0] inp;
		sv2v_cast_12_signed = inp;
	endfunction
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 2'd0;
			row_q <= 1'sb0;
			got_q <= 1'sb0;
			chroma_q <= 1'b0;
			x0_q <= 1'sb0;
			y0_q <= 1'sb0;
			lfx_q <= 1'sb0;
			lfy_q <= 1'sb0;
			cfx_q <= 1'sb0;
			cfy_q <= 1'sb0;
		end
		else
			(* full_case, parallel_case *)
			case (st_q)
				2'd0:
					if (start) begin
						chroma_q <= is_chroma;
						if (is_chroma) begin
							x0_q <= sv2v_cast_13_signed($signed({1'b0, px}) + (mvx >>> 3));
							y0_q <= sv2v_cast_12_signed($signed({1'b0, py}) + (mvy >>> 3));
							cfx_q <= sv2v_cast_3_signed(mvx & 16'sd7);
							cfy_q <= sv2v_cast_3_signed(mvy & 16'sd7);
						end
						else begin
							x0_q <= sv2v_cast_13_signed(($signed({1'b0, px}) + (mvx >>> 2)) - 13'sd2);
							y0_q <= sv2v_cast_12_signed(($signed({1'b0, py}) + (mvy >>> 2)) - 12'sd2);
							lfx_q <= sv2v_cast_2_signed(mvx & 16'sd3);
							lfy_q <= sv2v_cast_2_signed(mvy & 16'sd3);
						end
						row_q <= 1'sb0;
						got_q <= 1'sb0;
						st_q <= 2'd1;
					end
				2'd1: begin
					if (req_valid)
						row_q <= row_q + 4'd1;
					if (rsp_valid) begin
						if (chroma_q) begin : sv2v_autoblock_2
							reg signed [31:0] i;
							for (i = 0; i < 5; i = i + 1)
								cwin[(((4 - got_q[2:0]) * 5) + (4 - i)) * 8+:8] <= rsp_data[71 - (i * 8)-:8];
						end
						else begin : sv2v_autoblock_3
							reg signed [31:0] i;
							for (i = 0; i < 9; i = i + 1)
								lwin[(((8 - got_q[3:0]) * 9) + (8 - i)) * 8+:8] <= rsp_data[71 - (i * 8)-:8];
						end
						got_q <= got_q + 4'd1;
						if ((got_q + 4'd1) == nrows)
							st_q <= 2'd2;
					end
				end
				2'd2: st_q <= 2'd0;
				default: st_q <= 2'd0;
			endcase
	initial _sv2v_0 = 0;
endmodule
module mc4x4_luma (
	win,
	fx,
	fy,
	pred
);
	reg _sv2v_0;
	input wire [647:0] win;
	input wire [1:0] fx;
	input wire [1:0] fy;
	output reg [127:0] pred;
	function automatic signed [15:0] sv2v_cast_16_signed;
		input reg signed [15:0] inp;
		sv2v_cast_16_signed = inp;
	endfunction
	function automatic signed [15:0] tap6;
		input reg [7:0] a;
		input reg [7:0] b;
		input reg [7:0] c;
		input reg [7:0] d;
		input reg [7:0] e;
		input reg [7:0] f;
		tap6 = sv2v_cast_16_signed((((($signed({8'b00000000, a}) - (16'sd5 * $signed({8'b00000000, b}))) + (16'sd20 * $signed({8'b00000000, c}))) + (16'sd20 * $signed({8'b00000000, d}))) - (16'sd5 * $signed({8'b00000000, e}))) + $signed({8'b00000000, f}));
	endfunction
	function automatic [7:0] clip8;
		input reg signed [31:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < 0) begin
				clip8 = 8'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > 255) begin
					clip8 = 8'd255;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip8 = v[7:0];
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	function automatic [7:0] avg2;
		input reg [7:0] a;
		input reg [7:0] b;
		avg2 = sv2v_cast_8((({1'b0, a} + {1'b0, b}) + 9'd1) >> 1);
	endfunction
	reg signed [15:0] hrow [0:8][0:3];
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] j;
			for (j = 0; j < 9; j = j + 1)
				begin : sv2v_autoblock_2
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						hrow[j][i] = tap6(win[(((8 - j) * 9) + (8 - i)) * 8+:8], win[(((8 - j) * 9) + (8 - (i + 1))) * 8+:8], win[(((8 - j) * 9) + (8 - (i + 2))) * 8+:8], win[(((8 - j) * 9) + (8 - (i + 3))) * 8+:8], win[(((8 - j) * 9) + (8 - (i + 4))) * 8+:8], win[(((8 - j) * 9) + (8 - (i + 5))) * 8+:8]);
				end
		end
	end
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_3
			reg signed [31:0] idx;
			for (idx = 0; idx < 16; idx = idx + 1)
				pred[(15 - idx) * 8+:8] = 1'sb0;
		end
		if ((fx == 0) && (fy == 0)) begin : sv2v_autoblock_4
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_5
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						pred[(15 - ((j * 4) + i)) * 8+:8] = win[(((8 - (j + 2)) * 9) + (8 - (i + 2))) * 8+:8];
				end
		end
		else if (fy == 0) begin : sv2v_autoblock_6
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_7
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						begin : sv2v_autoblock_8
							reg [7:0] b;
							reg [7:0] g;
							b = clip8((sv2v_cast_32(hrow[j + 2][i]) + 32'sd16) >>> 5);
							if (fx == 2)
								pred[(15 - ((j * 4) + i)) * 8+:8] = b;
							else begin
								g = (fx == 1 ? win[(((8 - (j + 2)) * 9) + (8 - (i + 2))) * 8+:8] : win[(((8 - (j + 2)) * 9) + (8 - (i + 3))) * 8+:8]);
								pred[(15 - ((j * 4) + i)) * 8+:8] = avg2(g, b);
							end
						end
				end
		end
		else if (fx == 0) begin : sv2v_autoblock_9
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_10
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						begin : sv2v_autoblock_11
							reg [7:0] h;
							reg [7:0] g;
							h = clip8((sv2v_cast_32_signed(tap6(win[(((8 - j) * 9) + (8 - (i + 2))) * 8+:8], win[(((8 - (j + 1)) * 9) + (8 - (i + 2))) * 8+:8], win[(((8 - (j + 2)) * 9) + (8 - (i + 2))) * 8+:8], win[(((8 - (j + 3)) * 9) + (8 - (i + 2))) * 8+:8], win[(((8 - (j + 4)) * 9) + (8 - (i + 2))) * 8+:8], win[(((8 - (j + 5)) * 9) + (8 - (i + 2))) * 8+:8])) + 32'sd16) >>> 5);
							if (fy == 2)
								pred[(15 - ((j * 4) + i)) * 8+:8] = h;
							else begin
								g = (fy == 1 ? win[(((8 - (j + 2)) * 9) + (8 - (i + 2))) * 8+:8] : win[(((8 - (j + 3)) * 9) + (8 - (i + 2))) * 8+:8]);
								pred[(15 - ((j * 4) + i)) * 8+:8] = avg2(g, h);
							end
						end
				end
		end
		else begin : sv2v_autoblock_12
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_13
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						begin : sv2v_autoblock_14
							reg signed [31:0] j1;
							reg [7:0] jj;
							reg [7:0] b;
							reg [7:0] h;
							reg signed [31:0] col;
							reg signed [31:0] row;
							j1 = ((((sv2v_cast_32(hrow[j][i]) - (32'sd5 * sv2v_cast_32(hrow[j + 1][i]))) + (32'sd20 * sv2v_cast_32(hrow[j + 2][i]))) + (32'sd20 * sv2v_cast_32(hrow[j + 3][i]))) - (32'sd5 * sv2v_cast_32(hrow[j + 4][i]))) + sv2v_cast_32(hrow[j + 5][i]);
							jj = clip8((j1 + 32'sd512) >>> 10);
							if ((fx == 2) && (fy == 2))
								pred[(15 - ((j * 4) + i)) * 8+:8] = jj;
							else if (fy == 2) begin
								col = (fx == 1 ? i + 2 : i + 3);
								h = clip8((sv2v_cast_32_signed(tap6(win[(((8 - j) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 1)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 2)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 3)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 4)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 5)) * 9) + (8 - col)) * 8+:8])) + 32'sd16) >>> 5);
								pred[(15 - ((j * 4) + i)) * 8+:8] = avg2(h, jj);
							end
							else if (fx == 2) begin
								row = (fy == 1 ? j + 2 : j + 3);
								b = clip8((sv2v_cast_32(hrow[row][i]) + 32'sd16) >>> 5);
								pred[(15 - ((j * 4) + i)) * 8+:8] = avg2(b, jj);
							end
							else begin
								row = (fy == 1 ? j + 2 : j + 3);
								col = (fx == 1 ? i + 2 : i + 3);
								b = clip8((sv2v_cast_32(hrow[row][i]) + 32'sd16) >>> 5);
								h = clip8((sv2v_cast_32_signed(tap6(win[(((8 - j) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 1)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 2)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 3)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 4)) * 9) + (8 - col)) * 8+:8], win[(((8 - (j + 5)) * 9) + (8 - col)) * 8+:8])) + 32'sd16) >>> 5);
								pred[(15 - ((j * 4) + i)) * 8+:8] = avg2(b, h);
							end
						end
				end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module mc4x4_chroma (
	win,
	fx,
	fy,
	pred
);
	reg _sv2v_0;
	input wire [199:0] win;
	input wire [2:0] fx;
	input wire [2:0] fy;
	output reg [127:0] pred;
	function automatic [17:0] sv2v_cast_18;
		input reg [17:0] inp;
		sv2v_cast_18 = inp;
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg [3:0] xf;
		reg [3:0] yf;
		reg [3:0] xi;
		reg [3:0] yi;
		if (_sv2v_0)
			;
		xf = {1'b0, fx};
		yf = {1'b0, fy};
		xi = 4'd8 - xf;
		yi = 4'd8 - yf;
		begin : sv2v_autoblock_2
			reg signed [31:0] j;
			for (j = 0; j < 4; j = j + 1)
				begin : sv2v_autoblock_3
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						begin : sv2v_autoblock_4
							reg [17:0] s;
							s = (((sv2v_cast_18(xi * yi) * sv2v_cast_18(win[(((4 - j) * 5) + (4 - i)) * 8+:8])) + (sv2v_cast_18(xf * yi) * sv2v_cast_18(win[(((4 - j) * 5) + (4 - (i + 1))) * 8+:8]))) + (sv2v_cast_18(xi * yf) * sv2v_cast_18(win[(((4 - (j + 1)) * 5) + (4 - i)) * 8+:8]))) + (sv2v_cast_18(xf * yf) * sv2v_cast_18(win[(((4 - (j + 1)) * 5) + (4 - (i + 1))) * 8+:8]));
							pred[(15 - ((j * 4) + i)) * 8+:8] = sv2v_cast_8((s + 18'd32) >> 6);
						end
				end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module mv_pred (
	clk,
	rst_n,
	cfg_mb_w,
	start,
	mb_ptype,
	mb_sub,
	mvd_valid,
	mvd_x,
	mvd_y,
	skip_go,
	commit,
	mb_inter,
	mb_skip,
	mv_out_x,
	mv_out_y
);
	reg _sv2v_0;
	parameter signed [31:0] MAX_MBW = 120;
	input wire clk;
	input wire rst_n;
	input wire [7:0] cfg_mb_w;
	input wire start;
	input wire [2:0] mb_ptype;
	input wire [7:0] mb_sub;
	input wire mvd_valid;
	input wire signed [15:0] mvd_x;
	input wire signed [15:0] mvd_y;
	input wire skip_go;
	input wire commit;
	input wire mb_inter;
	input wire mb_skip;
	output reg signed [255:0] mv_out_x;
	output reg signed [255:0] mv_out_y;
	reg signed [15:0] top_mvx [0:(MAX_MBW * 4) - 1];
	reg signed [15:0] top_mvy [0:(MAX_MBW * 4) - 1];
	reg [(MAX_MBW * 4) - 1:0] top_int;
	reg signed [15:0] left_mvx [0:3];
	reg signed [15:0] left_mvy [0:3];
	reg [3:0] left_int;
	reg signed [15:0] tl_mvx;
	reg signed [15:0] tl_mvy;
	reg tl_int;
	reg [7:0] mbx_q;
	reg [7:0] mby_q;
	reg have_left_q;
	reg signed [15:0] cur_mvx [0:15];
	reg signed [15:0] cur_mvy [0:15];
	reg [15:0] cur_w;
	reg [1:0] b_q;
	reg [1:0] s_q;
	reg [2:0] g_bx0;
	reg [2:0] g_by0;
	reg [2:0] g_w4;
	reg [2:0] g_h4;
	reg [2:0] g_dir;
	reg [1:0] sub2;
	reg [2:0] nsub;
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		sub2 = mb_sub[{b_q, 1'b0}+:2];
		nsub = (sub2 == 2'd0 ? 3'd1 : (sub2 == 2'd3 ? 3'd4 : 3'd2));
		g_bx0 = 1'sb0;
		g_by0 = 1'sb0;
		g_w4 = 3'd4;
		g_h4 = 3'd4;
		g_dir = 1'sb0;
		(* full_case, parallel_case *)
		case (mb_ptype)
			3'd0:
				;
			3'd1: begin
				g_by0 = {1'b0, b_q[0], 1'b0};
				g_h4 = 3'd2;
				g_dir = 3'd1 + sv2v_cast_3(b_q[0]);
			end
			3'd2: begin
				g_bx0 = {1'b0, b_q[0], 1'b0};
				g_w4 = 3'd2;
				g_dir = 3'd3 + sv2v_cast_3(b_q[0]);
			end
			default: begin
				g_bx0 = {2'b00, b_q[0]} << 1;
				g_by0 = {2'b00, b_q[1]} << 1;
				(* full_case, parallel_case *)
				case (sub2)
					2'd0: begin
						g_w4 = 3'd2;
						g_h4 = 3'd2;
					end
					2'd1: begin
						g_w4 = 3'd2;
						g_h4 = 3'd1;
						g_by0 = g_by0 + sv2v_cast_3(s_q[0]);
					end
					2'd2: begin
						g_w4 = 3'd1;
						g_h4 = 3'd2;
						g_bx0 = g_bx0 + sv2v_cast_3(s_q[0]);
					end
					default: begin
						g_w4 = 3'd1;
						g_h4 = 3'd1;
						g_bx0 = g_bx0 + sv2v_cast_3(s_q[0]);
						g_by0 = g_by0 + sv2v_cast_3(s_q[1]);
					end
				endcase
			end
		endcase
	end
	reg [2:0] p_bx0;
	reg [2:0] p_by0;
	reg [2:0] p_w4;
	reg [2:0] p_dir;
	always @(*) begin
		if (_sv2v_0)
			;
		p_bx0 = (skip_go ? 3'd0 : g_bx0);
		p_by0 = (skip_go ? 3'd0 : g_by0);
		p_w4 = (skip_go ? 3'd4 : g_w4);
		p_dir = (skip_go ? 3'd0 : g_dir);
	end
	wire prewrite;
	assign prewrite = mvd_valid && (((mb_ptype == 3'd1) || (mb_ptype == 3'd2)) || (mb_ptype == 3'd3));
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [33:0] nbr;
		input reg signed [31:0] bx;
		input reg signed [31:0] by;
		reg [33:0] n;
		reg signed [31:0] r;
		begin
			n[33] = 1'b0;
			n[32] = 1'b0;
			n[31-:16] = 1'sb0;
			n[15-:16] = 1'sb0;
			if ((bx < 0) && (by < 0)) begin
				if (have_left_q && (mby_q != 8'd0)) begin
					n[33] = 1'b1;
					n[32] = tl_int;
					if (tl_int) begin
						n[31-:16] = tl_mvx;
						n[15-:16] = tl_mvy;
					end
				end
			end
			else if (bx < 0) begin
				if (have_left_q) begin
					n[33] = 1'b1;
					n[32] = left_int[by[1:0]];
					if (left_int[by[1:0]]) begin
						n[31-:16] = left_mvx[by[1:0]];
						n[15-:16] = left_mvy[by[1:0]];
					end
				end
			end
			else if (by < 0) begin
				if ((mby_q != 8'd0) && ((bx < 4) || (mbx_q != (cfg_mb_w - 8'd1)))) begin
					n[33] = 1'b1;
					n[32] = top_int[(sv2v_cast_32(mbx_q) * 4) + bx];
					if (n[32]) begin
						n[31-:16] = top_mvx[(sv2v_cast_32(mbx_q) * 4) + bx];
						n[15-:16] = top_mvy[(sv2v_cast_32(mbx_q) * 4) + bx];
					end
				end
			end
			else if (bx > 3)
				;
			else begin
				r = (by * 4) + bx;
				if (cur_w[r]) begin
					n[33] = 1'b1;
					n[32] = 1'b1;
					n[31-:16] = cur_mvx[r];
					n[15-:16] = cur_mvy[r];
				end
				else if (prewrite) begin
					n[33] = 1'b1;
					n[32] = 1'b1;
				end
			end
			nbr = n;
		end
	endfunction
	function automatic signed [15:0] med3;
		input reg signed [15:0] a;
		input reg signed [15:0] b;
		input reg signed [15:0] c;
		reg signed [15:0] x;
		reg signed [15:0] y;
		begin
			x = a;
			y = b;
			if (x > y) begin
				x = b;
				y = a;
			end
			if (y > c)
				y = c;
			med3 = (x > y ? x : y);
		end
	endfunction
	reg [33:0] na;
	reg [33:0] nb;
	reg [33:0] nc;
	reg signed [15:0] pmx;
	reg signed [15:0] pmy;
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @($signed(nc[15-:16]) or $signed(nb[15-:16]) or $signed(na[15-:16]) or $signed(nc[31-:16]) or $signed(nb[31-:16]) or $signed(na[31-:16]) or $signed(nc[15-:16]) or $signed(nc[31-:16]) or $signed(nb[15-:16]) or $signed(nb[31-:16]) or nb[32] or $signed(na[15-:16]) or $signed(na[31-:16]) or na[32] or nc[32] or nb[32] or na[32] or $signed(na[15-:16]) or $signed(na[31-:16]) or na[33] or nc[33] or nb[33] or $signed(nc[15-:16]) or $signed(nc[31-:16]) or nc[32] or p_dir or $signed(na[15-:16]) or $signed(na[31-:16]) or na[32] or p_dir or p_dir or $signed(nb[15-:16]) or $signed(nb[31-:16]) or nb[32] or p_dir or p_by0 or p_bx0 or prewrite or cur_mvy or cur_mvx or cur_w or mbx_q or top_mvy or mbx_q or top_mvx or mbx_q or top_int or cfg_mb_w or mbx_q or mby_q or left_mvy or left_mvx or left_int or left_int or have_left_q or tl_mvy or tl_mvx or tl_int or tl_int or mby_q or have_left_q or p_by0 or p_w4 or p_bx0 or prewrite or cur_mvy or cur_mvx or cur_w or mbx_q or top_mvy or mbx_q or top_mvx or mbx_q or top_int or cfg_mb_w or mbx_q or mby_q or left_mvy or left_mvx or left_int or left_int or have_left_q or tl_mvy or tl_mvx or tl_int or tl_int or mby_q or have_left_q or p_by0 or p_bx0 or prewrite or cur_mvy or cur_mvx or cur_w or mbx_q or top_mvy or mbx_q or top_mvx or mbx_q or top_int or cfg_mb_w or mbx_q or mby_q or left_mvy or left_mvx or left_int or left_int or have_left_q or tl_mvy or tl_mvx or tl_int or tl_int or mby_q or have_left_q or p_by0 or p_bx0 or prewrite or cur_mvy or cur_mvx or cur_w or mbx_q or top_mvy or mbx_q or top_mvx or mbx_q or top_int or cfg_mb_w or mbx_q or mby_q or left_mvy or left_mvx or left_int or left_int or have_left_q or tl_mvy or tl_mvx or tl_int or tl_int or mby_q or have_left_q or _sv2v_0) begin : sv2v_autoblock_1
		reg [33:0] nc0;
		reg [1:0] match;
		if (_sv2v_0)
			;
		na = nbr(sv2v_cast_32_signed(p_bx0) - 1, sv2v_cast_32_signed(p_by0));
		nb = nbr(sv2v_cast_32_signed(p_bx0), sv2v_cast_32_signed(p_by0) - 1);
		nc0 = nbr(sv2v_cast_32_signed(p_bx0) + sv2v_cast_32_signed(p_w4), sv2v_cast_32_signed(p_by0) - 1);
		nc = (nc0[33] ? nc0 : nbr(sv2v_cast_32_signed(p_bx0) - 1, sv2v_cast_32_signed(p_by0) - 1));
		if ((p_dir == 3'd1) && nb[32]) begin
			pmx = $signed(nb[31-:16]);
			pmy = $signed(nb[15-:16]);
		end
		else if (((p_dir == 3'd2) || (p_dir == 3'd3)) && na[32]) begin
			pmx = $signed(na[31-:16]);
			pmy = $signed(na[15-:16]);
		end
		else if ((p_dir == 3'd4) && nc[32]) begin
			pmx = $signed(nc[31-:16]);
			pmy = $signed(nc[15-:16]);
		end
		else if ((!nb[33] && !nc[33]) && na[33]) begin
			pmx = $signed(na[31-:16]);
			pmy = $signed(na[15-:16]);
		end
		else begin
			match = (sv2v_cast_2(na[32]) + sv2v_cast_2(nb[32])) + sv2v_cast_2(nc[32]);
			if (match == 2'd1) begin
				if (na[32]) begin
					pmx = $signed(na[31-:16]);
					pmy = $signed(na[15-:16]);
				end
				else if (nb[32]) begin
					pmx = $signed(nb[31-:16]);
					pmy = $signed(nb[15-:16]);
				end
				else begin
					pmx = $signed(nc[31-:16]);
					pmy = $signed(nc[15-:16]);
				end
			end
			else begin
				pmx = med3($signed(na[31-:16]), $signed(nb[31-:16]), $signed(nc[31-:16]));
				pmy = med3($signed(na[15-:16]), $signed(nb[15-:16]), $signed(nc[15-:16]));
			end
		end
	end
	wire skip_zero;
	assign skip_zero = ((!na[33] || !nb[33]) || ((na[32] && ($signed(na[31-:16]) == 16'sd0)) && ($signed(na[15-:16]) == 16'sd0))) || ((nb[32] && ($signed(nb[31-:16]) == 16'sd0)) && ($signed(nb[15-:16]) == 16'sd0));
	reg signed [15:0] fin_x;
	reg signed [15:0] fin_y;
	always @(*) begin
		if (_sv2v_0)
			;
		if (skip_go) begin
			fin_x = (skip_zero ? 16'sd0 : pmx);
			fin_y = (skip_zero ? 16'sd0 : pmy);
		end
		else begin
			fin_x = pmx + mvd_x;
			fin_y = pmy + mvd_y;
		end
	end
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			mbx_q <= 1'sb0;
			mby_q <= 1'sb0;
			have_left_q <= 1'b0;
			cur_w <= 1'sb0;
			b_q <= 1'sb0;
			s_q <= 1'sb0;
			left_int <= 1'sb0;
			tl_int <= 1'b0;
			tl_mvx <= 1'sb0;
			tl_mvy <= 1'sb0;
		end
		else begin
			if (start) begin
				mbx_q <= 1'sb0;
				mby_q <= 1'sb0;
				have_left_q <= 1'b0;
				cur_w <= 1'sb0;
				b_q <= 1'sb0;
				s_q <= 1'sb0;
			end
			if (mvd_valid || skip_go) begin
				begin : sv2v_autoblock_2
					reg signed [31:0] j;
					for (j = 0; j < 4; j = j + 1)
						begin : sv2v_autoblock_3
							reg signed [31:0] i;
							for (i = 0; i < 4; i = i + 1)
								if ((((i >= sv2v_cast_32_signed(p_bx0)) && (i < (sv2v_cast_32_signed(p_bx0) + sv2v_cast_32_signed(p_w4)))) && (j >= sv2v_cast_32_signed(p_by0))) && (j < (sv2v_cast_32_signed(p_by0) + sv2v_cast_32_signed((skip_go ? 3'd4 : g_h4))))) begin
									cur_mvx[(j * 4) + i] <= fin_x;
									cur_mvy[(j * 4) + i] <= fin_y;
									cur_w[(j * 4) + i] <= 1'b1;
								end
						end
				end
				if (mvd_valid) begin
					if ((mb_ptype == 3'd1) || (mb_ptype == 3'd2))
						b_q <= b_q + 2'd1;
					else if (mb_ptype >= 3'd3) begin
						if ((sv2v_cast_3(s_q) + 3'd1) == nsub) begin
							s_q <= 1'sb0;
							b_q <= b_q + 2'd1;
						end
						else
							s_q <= s_q + 2'd1;
					end
				end
			end
			if (commit) begin
				tl_mvx <= top_mvx[(sv2v_cast_32(mbx_q) * 4) + 3];
				tl_mvy <= top_mvy[(sv2v_cast_32(mbx_q) * 4) + 3];
				tl_int <= top_int[(sv2v_cast_32(mbx_q) * 4) + 3];
				if (mb_inter || mb_skip) begin
					begin : sv2v_autoblock_4
						reg signed [31:0] j;
						for (j = 0; j < 4; j = j + 1)
							begin
								left_mvx[j] <= cur_mvx[(j * 4) + 3];
								left_mvy[j] <= cur_mvy[(j * 4) + 3];
								left_int[j] <= 1'b1;
							end
					end
					begin : sv2v_autoblock_5
						reg signed [31:0] i;
						for (i = 0; i < 4; i = i + 1)
							begin
								top_mvx[(sv2v_cast_32(mbx_q) * 4) + i] <= cur_mvx[12 + i];
								top_mvy[(sv2v_cast_32(mbx_q) * 4) + i] <= cur_mvy[12 + i];
								top_int[(sv2v_cast_32(mbx_q) * 4) + i] <= 1'b1;
							end
					end
				end
				else begin
					left_int <= 1'sb0;
					begin : sv2v_autoblock_6
						reg signed [31:0] i;
						for (i = 0; i < 4; i = i + 1)
							top_int[(sv2v_cast_32(mbx_q) * 4) + i] <= 1'b0;
					end
				end
				cur_w <= 1'sb0;
				b_q <= 1'sb0;
				s_q <= 1'sb0;
				if (mbx_q == (cfg_mb_w - 8'd1)) begin
					mbx_q <= 1'sb0;
					mby_q <= mby_q + 8'd1;
					have_left_q <= 1'b0;
				end
				else begin
					mbx_q <= mbx_q + 8'd1;
					have_left_q <= 1'b1;
				end
			end
		end
	localparam signed [511:0] Z2R = 512'h100000004000000050000000200000003000000060000000700000008000000090000000c0000000d0000000a0000000b0000000e0000000f;
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_7
			reg signed [31:0] k;
			for (k = 0; k < 16; k = k + 1)
				begin
					mv_out_x[(15 - k) * 16+:16] = (cur_w[Z2R[(15 - k) * 32+:32]] ? cur_mvx[Z2R[(15 - k) * 32+:32]] : 16'sd0);
					mv_out_y[(15 - k) * 16+:16] = (cur_w[Z2R[(15 - k) * 32+:32]] ? cur_mvy[Z2R[(15 - k) * 32+:32]] : 16'sd0);
				end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module intra4x4_pred (
	l,
	t,
	tl,
	avail_left,
	avail_top,
	avail_topleft,
	mode,
	pred,
	ok
);
	reg _sv2v_0;
	input wire [31:0] l;
	input wire [63:0] t;
	input wire [7:0] tl;
	input wire avail_left;
	input wire avail_top;
	input wire avail_topleft;
	input wire [3:0] mode;
	output reg [127:0] pred;
	output reg ok;
	function automatic [7:0] tx;
		input reg signed [31:0] i;
		tx = (i < 0 ? tl : t[(7 - i) * 8+:8]);
	endfunction
	function automatic [7:0] lx;
		input reg signed [31:0] i;
		lx = (i < 0 ? tl : l[(3 - i) * 8+:8]);
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	function automatic [7:0] avg2;
		input reg [7:0] a;
		input reg [7:0] b;
		avg2 = sv2v_cast_8((({1'b0, a} + {1'b0, b}) + 9'd1) >> 1);
	endfunction
	function automatic [7:0] avg3;
		input reg [7:0] a;
		input reg [7:0] b;
		input reg [7:0] c;
		avg3 = sv2v_cast_8(((({2'b00, a} + {1'b0, b, 1'b0}) + {2'b00, c}) + 10'd2) >> 2);
	endfunction
	always @(l or l or l or l or l or l[0+:8] or l[0+:8] or l[8+:8] or l[0+:8] or avail_left or t or t or t or t or t or avail_top or t or tl or t or tl or t or tl or t[56+:8] or tl or l[24+:8] or l or tl or l or tl or l or tl or l or tl or l or tl or avail_topleft or avail_left or avail_top or l or tl or l or tl or l or tl or t[56+:8] or tl or l[24+:8] or t or tl or t or tl or t or tl or t or tl or t or tl or avail_topleft or avail_left or avail_top or l[24+:8] or tl or t[56+:8] or l or tl or l or tl or l or tl or t or tl or t or tl or t or tl or avail_topleft or avail_left or avail_top or t or t or t or t[0+:8] or t[0+:8] or t[8+:8] or avail_top or avail_left or avail_top or avail_left or avail_top or l[0+:8] or l[8+:8] or l[16+:8] or l[24+:8] or avail_left or t[32+:8] or t[40+:8] or t[48+:8] or t[56+:8] or avail_top or l or avail_left or t or avail_top or mode or _sv2v_0) begin
		if (_sv2v_0)
			;
		ok = 1'b1;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				pred[(15 - i) * 8+:8] = 8'd128;
		end
		(* full_case, parallel_case *)
		case (mode)
			4'd0: begin
				if (!avail_top)
					ok = 1'b0;
				begin : sv2v_autoblock_2
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_3
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								pred[(15 - ((y * 4) + x)) * 8+:8] = t[(7 - x) * 8+:8];
						end
				end
			end
			4'd1: begin
				if (!avail_left)
					ok = 1'b0;
				begin : sv2v_autoblock_4
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_5
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								pred[(15 - ((y * 4) + x)) * 8+:8] = l[(3 - y) * 8+:8];
						end
				end
			end
			4'd2: begin : sv2v_autoblock_6
				reg [10:0] sum;
				reg [7:0] v;
				sum = 1'sb0;
				if (avail_top)
					sum = (((sum + {3'b000, t[56+:8]}) + {3'b000, t[48+:8]}) + {3'b000, t[40+:8]}) + {3'b000, t[32+:8]};
				if (avail_left)
					sum = (((sum + {3'b000, l[24+:8]}) + {3'b000, l[16+:8]}) + {3'b000, l[8+:8]}) + {3'b000, l[0+:8]};
				v = (avail_top && avail_left ? sv2v_cast_8((sum + 11'd4) >> 3) : (avail_top || avail_left ? sv2v_cast_8((sum + 11'd2) >> 2) : 8'd128));
				begin : sv2v_autoblock_7
					reg signed [31:0] i;
					for (i = 0; i < 16; i = i + 1)
						pred[(15 - i) * 8+:8] = v;
				end
			end
			4'd3: begin
				if (!avail_top)
					ok = 1'b0;
				begin : sv2v_autoblock_8
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_9
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								if ((x == 3) && (y == 3))
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(t[8+:8], t[0+:8], t[0+:8]);
								else
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(t[(7 - (x + y)) * 8+:8], t[(7 - ((x + y) + 1)) * 8+:8], t[(7 - ((x + y) + 2)) * 8+:8]);
						end
				end
			end
			4'd4: begin
				if ((!avail_top || !avail_left) || !avail_topleft)
					ok = 1'b0;
				begin : sv2v_autoblock_10
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_11
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								if (x > y)
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(tx((x - y) - 2), tx((x - y) - 1), tx(x - y));
								else if (x < y)
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(lx((y - x) - 2), lx((y - x) - 1), lx(y - x));
								else
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(t[56+:8], tl, l[24+:8]);
						end
				end
			end
			4'd5: begin
				if ((!avail_top || !avail_left) || !avail_topleft)
					ok = 1'b0;
				begin : sv2v_autoblock_12
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_13
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								begin : sv2v_autoblock_14
									reg signed [31:0] z;
									z = (2 * x) - y;
									if ((z >= 0) && ((z % 2) == 0))
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg2(tx((x - (y >> 1)) - 1), tx(x - (y >> 1)));
									else if (z >= 0)
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(tx((x - (y >> 1)) - 2), tx((x - (y >> 1)) - 1), tx(x - (y >> 1)));
									else if (z == -1)
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(l[24+:8], tl, t[56+:8]);
									else
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(lx((y - (2 * x)) - 3), lx((y - (2 * x)) - 2), lx((y - (2 * x)) - 1));
								end
						end
				end
			end
			4'd6: begin
				if ((!avail_top || !avail_left) || !avail_topleft)
					ok = 1'b0;
				begin : sv2v_autoblock_15
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_16
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								begin : sv2v_autoblock_17
									reg signed [31:0] z;
									z = (2 * y) - x;
									if ((z >= 0) && ((z % 2) == 0))
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg2(lx((y - (x >> 1)) - 1), lx(y - (x >> 1)));
									else if (z >= 0)
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(lx((y - (x >> 1)) - 2), lx((y - (x >> 1)) - 1), lx(y - (x >> 1)));
									else if (z == -1)
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(l[24+:8], tl, t[56+:8]);
									else
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(tx((x - (2 * y)) - 3), tx((x - (2 * y)) - 2), tx((x - (2 * y)) - 1));
								end
						end
				end
			end
			4'd7: begin
				if (!avail_top)
					ok = 1'b0;
				begin : sv2v_autoblock_18
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_19
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								if ((y % 2) == 0)
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg2(t[(7 - (x + (y >> 1))) * 8+:8], t[(7 - ((x + (y >> 1)) + 1)) * 8+:8]);
								else
									pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(t[(7 - (x + (y >> 1))) * 8+:8], t[(7 - ((x + (y >> 1)) + 1)) * 8+:8], t[(7 - ((x + (y >> 1)) + 2)) * 8+:8]);
						end
				end
			end
			4'd8: begin
				if (!avail_left)
					ok = 1'b0;
				begin : sv2v_autoblock_20
					reg signed [31:0] y;
					for (y = 0; y < 4; y = y + 1)
						begin : sv2v_autoblock_21
							reg signed [31:0] x;
							for (x = 0; x < 4; x = x + 1)
								begin : sv2v_autoblock_22
									reg signed [31:0] z;
									z = x + (2 * y);
									if (z > 5)
										pred[(15 - ((y * 4) + x)) * 8+:8] = l[0+:8];
									else if (z == 5)
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(l[8+:8], l[0+:8], l[0+:8]);
									else if ((z % 2) == 0)
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg2(l[(3 - (y + (x >> 1))) * 8+:8], l[(3 - ((y + (x >> 1)) + 1)) * 8+:8]);
									else
										pred[(15 - ((y * 4) + x)) * 8+:8] = avg3(l[(3 - (y + (x >> 1))) * 8+:8], l[(3 - ((y + (x >> 1)) + 1)) * 8+:8], l[(3 - ((y + (x >> 1)) + 2)) * 8+:8]);
								end
						end
				end
			end
			default: ok = 1'b0;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module intra16_pred (
	l,
	t,
	tl,
	avail_left,
	avail_top,
	mode,
	pred,
	ok
);
	reg _sv2v_0;
	input wire [127:0] l;
	input wire [127:0] t;
	input wire [7:0] tl;
	input wire avail_left;
	input wire avail_top;
	input wire [1:0] mode;
	output reg [2047:0] pred;
	output reg ok;
	function automatic [7:0] clip8;
		input reg signed [31:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < 0) begin
				clip8 = 8'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > 255) begin
					clip8 = 8'd255;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip8 = v[7:0];
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	function automatic [7:0] txp;
		input reg signed [31:0] i;
		txp = (i < 0 ? tl : t[(15 - i) * 8+:8]);
	endfunction
	function automatic [7:0] lxp;
		input reg signed [31:0] i;
		lxp = (i < 0 ? tl : l[(15 - i) * 8+:8]);
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	always @(t[0+:8] or l[0+:8] or l or tl or l or t or tl or t or avail_left or avail_top or avail_left or avail_top or avail_left or avail_top or l or avail_left or t or avail_top or l or avail_left or t or avail_top or mode or _sv2v_0) begin
		if (_sv2v_0)
			;
		ok = 1'b1;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 256; i = i + 1)
				pred[(255 - i) * 8+:8] = 8'd128;
		end
		(* full_case, parallel_case *)
		case (mode)
			2'd0: begin
				if (!avail_top)
					ok = 1'b0;
				begin : sv2v_autoblock_2
					reg signed [31:0] y;
					for (y = 0; y < 16; y = y + 1)
						begin : sv2v_autoblock_3
							reg signed [31:0] x;
							for (x = 0; x < 16; x = x + 1)
								pred[(255 - ((y * 16) + x)) * 8+:8] = t[(15 - x) * 8+:8];
						end
				end
			end
			2'd1: begin
				if (!avail_left)
					ok = 1'b0;
				begin : sv2v_autoblock_4
					reg signed [31:0] y;
					for (y = 0; y < 16; y = y + 1)
						begin : sv2v_autoblock_5
							reg signed [31:0] x;
							for (x = 0; x < 16; x = x + 1)
								pred[(255 - ((y * 16) + x)) * 8+:8] = l[(15 - y) * 8+:8];
						end
				end
			end
			2'd2: begin : sv2v_autoblock_6
				reg [12:0] sum;
				reg [7:0] v;
				sum = 1'sb0;
				if (avail_top) begin : sv2v_autoblock_7
					reg signed [31:0] x;
					for (x = 0; x < 16; x = x + 1)
						sum = sum + {5'b00000, t[(15 - x) * 8+:8]};
				end
				if (avail_left) begin : sv2v_autoblock_8
					reg signed [31:0] y;
					for (y = 0; y < 16; y = y + 1)
						sum = sum + {5'b00000, l[(15 - y) * 8+:8]};
				end
				v = (avail_top && avail_left ? sv2v_cast_8((sum + 13'd16) >> 5) : (avail_top || avail_left ? sv2v_cast_8((sum + 13'd8) >> 4) : 8'd128));
				begin : sv2v_autoblock_9
					reg signed [31:0] i;
					for (i = 0; i < 256; i = i + 1)
						pred[(255 - i) * 8+:8] = v;
				end
			end
			2'd3: begin : sv2v_autoblock_10
				reg signed [31:0] h;
				reg signed [31:0] v;
				reg signed [31:0] a;
				reg signed [31:0] b;
				reg signed [31:0] c;
				if (!avail_top || !avail_left)
					ok = 1'b0;
				h = 1'sb0;
				v = 1'sb0;
				begin : sv2v_autoblock_11
					reg signed [31:0] i;
					for (i = 0; i < 8; i = i + 1)
						begin
							h = h + ((i + 1) * ($signed({24'b000000000000000000000000, t[(15 - (8 + i)) * 8+:8]}) - $signed({24'b000000000000000000000000, txp(6 - i)})));
							v = v + ((i + 1) * ($signed({24'b000000000000000000000000, l[(15 - (8 + i)) * 8+:8]}) - $signed({24'b000000000000000000000000, lxp(6 - i)})));
						end
				end
				a = 32'sd16 * ($signed({24'b000000000000000000000000, l[0+:8]}) + $signed({24'b000000000000000000000000, t[0+:8]}));
				b = ((32'sd5 * h) + 32'sd32) >>> 6;
				c = ((32'sd5 * v) + 32'sd32) >>> 6;
				begin : sv2v_autoblock_12
					reg signed [31:0] y;
					for (y = 0; y < 16; y = y + 1)
						begin : sv2v_autoblock_13
							reg signed [31:0] x;
							for (x = 0; x < 16; x = x + 1)
								pred[(255 - ((y * 16) + x)) * 8+:8] = clip8((((a + (b * (x - 7))) + (c * (y - 7))) + 32'sd16) >>> 5);
						end
				end
			end
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module chroma_pred (
	l,
	t,
	tl,
	avail_left,
	avail_top,
	mode,
	pred,
	ok
);
	reg _sv2v_0;
	input wire [63:0] l;
	input wire [63:0] t;
	input wire [7:0] tl;
	input wire avail_left;
	input wire avail_top;
	input wire [1:0] mode;
	output reg [511:0] pred;
	output reg ok;
	function automatic [7:0] clip8;
		input reg signed [31:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < 0) begin
				clip8 = 8'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > 255) begin
					clip8 = 8'd255;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip8 = v[7:0];
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	function automatic [7:0] txp;
		input reg signed [31:0] i;
		txp = (i < 0 ? tl : t[(7 - i) * 8+:8]);
	endfunction
	function automatic [7:0] lxp;
		input reg signed [31:0] i;
		lxp = (i < 0 ? tl : l[(7 - i) * 8+:8]);
	endfunction
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	always @(t[0+:8] or l[0+:8] or l or tl or l or t or tl or t or avail_left or avail_top or t or avail_top or l or avail_left or l or t or avail_left or avail_top or avail_top or avail_left or avail_left or avail_left or avail_top or avail_top or mode or _sv2v_0) begin
		if (_sv2v_0)
			;
		ok = 1'b1;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 64; i = i + 1)
				pred[(63 - i) * 8+:8] = 8'd128;
		end
		(* full_case, parallel_case *)
		case (mode)
			2'd0: begin : sv2v_autoblock_2
				reg signed [31:0] sb;
				for (sb = 0; sb < 4; sb = sb + 1)
					begin : sv2v_autoblock_3
						reg signed [31:0] bx;
						reg signed [31:0] by;
						reg use_top;
						reg use_left;
						reg [10:0] s;
						reg [7:0] v;
						bx = (sb & 1) * 4;
						by = (sb >> 1) * 4;
						if (sb == 1) begin
							use_top = avail_top;
							use_left = !avail_top && avail_left;
						end
						else if (sb == 2) begin
							use_left = avail_left;
							use_top = !avail_left && avail_top;
						end
						else begin
							use_top = avail_top;
							use_left = avail_left;
						end
						s = 1'sb0;
						if (use_top) begin : sv2v_autoblock_4
							reg signed [31:0] i;
							for (i = 0; i < 4; i = i + 1)
								s = s + {3'b000, t[(7 - (bx + i)) * 8+:8]};
						end
						if (use_left) begin : sv2v_autoblock_5
							reg signed [31:0] i;
							for (i = 0; i < 4; i = i + 1)
								s = s + {3'b000, l[(7 - (by + i)) * 8+:8]};
						end
						v = (use_top && use_left ? sv2v_cast_8((s + 11'd4) >> 3) : (use_top || use_left ? sv2v_cast_8((s + 11'd2) >> 2) : 8'd128));
						begin : sv2v_autoblock_6
							reg signed [31:0] y;
							for (y = 0; y < 4; y = y + 1)
								begin : sv2v_autoblock_7
									reg signed [31:0] x;
									for (x = 0; x < 4; x = x + 1)
										pred[(63 - ((((by + y) * 8) + bx) + x)) * 8+:8] = v;
								end
						end
					end
			end
			2'd1: begin
				if (!avail_left)
					ok = 1'b0;
				begin : sv2v_autoblock_8
					reg signed [31:0] y;
					for (y = 0; y < 8; y = y + 1)
						begin : sv2v_autoblock_9
							reg signed [31:0] x;
							for (x = 0; x < 8; x = x + 1)
								pred[(63 - ((y * 8) + x)) * 8+:8] = l[(7 - y) * 8+:8];
						end
				end
			end
			2'd2: begin
				if (!avail_top)
					ok = 1'b0;
				begin : sv2v_autoblock_10
					reg signed [31:0] y;
					for (y = 0; y < 8; y = y + 1)
						begin : sv2v_autoblock_11
							reg signed [31:0] x;
							for (x = 0; x < 8; x = x + 1)
								pred[(63 - ((y * 8) + x)) * 8+:8] = t[(7 - x) * 8+:8];
						end
				end
			end
			2'd3: begin : sv2v_autoblock_12
				reg signed [31:0] h;
				reg signed [31:0] v;
				reg signed [31:0] a;
				reg signed [31:0] b;
				reg signed [31:0] c;
				if (!avail_top || !avail_left)
					ok = 1'b0;
				h = 1'sb0;
				v = 1'sb0;
				begin : sv2v_autoblock_13
					reg signed [31:0] i;
					for (i = 0; i < 4; i = i + 1)
						begin
							h = h + ((i + 1) * ($signed({24'b000000000000000000000000, t[(7 - (4 + i)) * 8+:8]}) - $signed({24'b000000000000000000000000, txp(2 - i)})));
							v = v + ((i + 1) * ($signed({24'b000000000000000000000000, l[(7 - (4 + i)) * 8+:8]}) - $signed({24'b000000000000000000000000, lxp(2 - i)})));
						end
				end
				a = 32'sd16 * ($signed({24'b000000000000000000000000, l[0+:8]}) + $signed({24'b000000000000000000000000, t[0+:8]}));
				b = ((32'sd34 * h) + 32'sd32) >>> 6;
				c = ((32'sd34 * v) + 32'sd32) >>> 6;
				begin : sv2v_autoblock_14
					reg signed [31:0] y;
					for (y = 0; y < 8; y = y + 1)
						begin : sv2v_autoblock_15
							reg signed [31:0] x;
							for (x = 0; x < 8; x = x + 1)
								pred[(63 - ((y * 8) + x)) * 8+:8] = clip8((((a + (b * (x - 3))) + (c * (y - 3))) + 32'sd16) >>> 5);
						end
				end
			end
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module deblock_edge (
	p3,
	p2,
	p1,
	p0,
	q0,
	q1,
	q2,
	q3,
	alpha,
	beta,
	bs,
	tc0,
	chroma,
	o_p2,
	o_p1,
	o_p0,
	o_q0,
	o_q1,
	o_q2
);
	reg _sv2v_0;
	input wire [7:0] p3;
	input wire [7:0] p2;
	input wire [7:0] p1;
	input wire [7:0] p0;
	input wire [7:0] q0;
	input wire [7:0] q1;
	input wire [7:0] q2;
	input wire [7:0] q3;
	input wire [7:0] alpha;
	input wire [7:0] beta;
	input wire [2:0] bs;
	input wire [4:0] tc0;
	input wire chroma;
	output reg [7:0] o_p2;
	output reg [7:0] o_p1;
	output reg [7:0] o_p0;
	output reg [7:0] o_q0;
	output reg [7:0] o_q1;
	output reg [7:0] o_q2;
	function automatic [7:0] clip8;
		input reg signed [15:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < 0) begin
				clip8 = 8'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > 255) begin
					clip8 = 8'd255;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip8 = v[7:0];
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	function automatic signed [15:0] clip3;
		input reg signed [15:0] lo;
		input reg signed [15:0] hi;
		input reg signed [15:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < lo) begin
				clip3 = lo;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > hi) begin
					clip3 = hi;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip3 = v;
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	function automatic signed [15:0] sabs;
		input reg signed [15:0] v;
		sabs = (v < 0 ? -v : v);
	endfunction
	wire signed [15:0] sp3;
	wire signed [15:0] sp2;
	wire signed [15:0] sp1;
	wire signed [15:0] sp0;
	wire signed [15:0] sq0;
	wire signed [15:0] sq1;
	wire signed [15:0] sq2;
	wire signed [15:0] sq3;
	assign sp3 = $signed({8'b00000000, p3});
	assign sp2 = $signed({8'b00000000, p2});
	assign sp1 = $signed({8'b00000000, p1});
	assign sp0 = $signed({8'b00000000, p0});
	assign sq0 = $signed({8'b00000000, q0});
	assign sq1 = $signed({8'b00000000, q1});
	assign sq2 = $signed({8'b00000000, q2});
	assign sq3 = $signed({8'b00000000, q3});
	function automatic signed [7:0] sv2v_cast_8_signed;
		input reg signed [7:0] inp;
		sv2v_cast_8_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg filt;
		if (_sv2v_0)
			;
		o_p2 = p2;
		o_p1 = p1;
		o_p0 = p0;
		o_q0 = q0;
		o_q1 = q1;
		o_q2 = q2;
		filt = (((bs != 3'd0) && (sabs(sp0 - sq0) < $signed({8'b00000000, alpha}))) && (sabs(sp1 - sp0) < $signed({8'b00000000, beta}))) && (sabs(sq1 - sq0) < $signed({8'b00000000, beta}));
		if (filt && (bs == 3'd4)) begin
			if (chroma) begin
				o_p0 = sv2v_cast_8_signed(((((2 * sp1) + sp0) + sq1) + 16'sd2) >> 2);
				o_q0 = sv2v_cast_8_signed(((((2 * sq1) + sq0) + sp1) + 16'sd2) >> 2);
			end
			else begin : sv2v_autoblock_2
				reg ssmall;
				ssmall = sabs(sp0 - sq0) < (($signed({8'b00000000, alpha}) >>> 2) + 16'sd2);
				if (ssmall && (sabs(sp2 - sp0) < $signed({8'b00000000, beta}))) begin
					o_p0 = sv2v_cast_8_signed((((((sp2 + (2 * sp1)) + (2 * sp0)) + (2 * sq0)) + sq1) + 16'sd4) >> 3);
					o_p1 = sv2v_cast_8_signed(((((sp2 + sp1) + sp0) + sq0) + 16'sd2) >> 2);
					o_p2 = sv2v_cast_8_signed(((((((2 * sp3) + (3 * sp2)) + sp1) + sp0) + sq0) + 16'sd4) >> 3);
				end
				else
					o_p0 = sv2v_cast_8_signed(((((2 * sp1) + sp0) + sq1) + 16'sd2) >> 2);
				if (ssmall && (sabs(sq2 - sq0) < $signed({8'b00000000, beta}))) begin
					o_q0 = sv2v_cast_8_signed((((((sq2 + (2 * sq1)) + (2 * sq0)) + (2 * sp0)) + sp1) + 16'sd4) >> 3);
					o_q1 = sv2v_cast_8_signed(((((sq2 + sq1) + sq0) + sp0) + 16'sd2) >> 2);
					o_q2 = sv2v_cast_8_signed(((((((2 * sq3) + (3 * sq2)) + sq1) + sq0) + sp0) + 16'sd4) >> 3);
				end
				else
					o_q0 = sv2v_cast_8_signed(((((2 * sq1) + sq0) + sp1) + 16'sd2) >> 2);
			end
		end
		else if (filt) begin : sv2v_autoblock_3
			reg signed [15:0] ap;
			reg signed [15:0] aq;
			reg signed [15:0] tc;
			reg signed [15:0] delta;
			ap = sabs(sp2 - sp0);
			aq = sabs(sq2 - sq0);
			if (chroma)
				tc = $signed({11'b00000000000, tc0}) + 16'sd1;
			else
				tc = ($signed({11'b00000000000, tc0}) + (ap < $signed({8'b00000000, beta}) ? 16'sd1 : 16'sd0)) + (aq < $signed({8'b00000000, beta}) ? 16'sd1 : 16'sd0);
			delta = clip3(-tc, tc, ((((sq0 - sp0) <<< 2) + (sp1 - sq1)) + 16'sd4) >>> 3);
			o_p0 = clip8(sp0 + delta);
			o_q0 = clip8(sq0 - delta);
			if (!chroma) begin
				if (ap < $signed({8'b00000000, beta}))
					o_p1 = sv2v_cast_8_signed(sp1 + clip3(-$signed({11'b00000000000, tc0}), $signed({11'b00000000000, tc0}), ((sp2 + (((sp0 + sq0) + 16'sd1) >>> 1)) - (2 * sp1)) >>> 1));
				if (aq < $signed({8'b00000000, beta}))
					o_q1 = sv2v_cast_8_signed(sq1 + clip3(-$signed({11'b00000000000, tc0}), $signed({11'b00000000000, tc0}), ((sq2 + (((sp0 + sq0) + 16'sd1) >>> 1)) - (2 * sq1)) >>> 1));
			end
		end
	end
	initial _sv2v_0 = 0;
endmodule
module deblock_stream (
	clk,
	rst_n,
	cfg_mb_w,
	cfg_mb_h,
	cfg_cqp_off,
	cfg_a_off,
	cfg_b_off,
	cfg_enable,
	mb_push,
	mb_x,
	mb_y,
	mb_qp,
	mb_inter,
	mb_nz,
	mb_mvx,
	mb_mvy,
	in_y,
	in_u,
	in_v,
	mb_ready,
	flush,
	flush_done,
	out_valid,
	out_mbx,
	out_mby,
	out_plane,
	out_row,
	out_data
);
	reg _sv2v_0;
	parameter signed [31:0] MAX_MBW = 120;
	input wire clk;
	input wire rst_n;
	input wire [7:0] cfg_mb_w;
	input wire [7:0] cfg_mb_h;
	input wire signed [5:0] cfg_cqp_off;
	input wire signed [5:0] cfg_a_off;
	input wire signed [5:0] cfg_b_off;
	input wire cfg_enable;
	input wire mb_push;
	input wire [7:0] mb_x;
	input wire [7:0] mb_y;
	input wire [5:0] mb_qp;
	input wire mb_inter;
	input wire [15:0] mb_nz;
	input wire signed [255:0] mb_mvx;
	input wire signed [255:0] mb_mvy;
	input wire [2047:0] in_y;
	input wire [511:0] in_u;
	input wire [511:0] in_v;
	output wire mb_ready;
	input wire flush;
	output wire flush_done;
	output reg out_valid;
	output reg [7:0] out_mbx;
	output reg [7:0] out_mby;
	output reg [1:0] out_plane;
	output reg [3:0] out_row;
	output reg [127:0] out_data;
	function automatic [5:0] chroma_qp;
		input reg [5:0] q;
		reg [5:0] r;
		begin
			(* full_case, parallel_case *)
			case (q)
				6'd30: r = 6'd29;
				6'd31: r = 6'd30;
				6'd32: r = 6'd31;
				6'd33: r = 6'd32;
				6'd34: r = 6'd32;
				6'd35: r = 6'd33;
				6'd36: r = 6'd34;
				6'd37: r = 6'd34;
				6'd38: r = 6'd35;
				6'd39: r = 6'd35;
				6'd40: r = 6'd36;
				6'd41: r = 6'd36;
				6'd42: r = 6'd37;
				6'd43: r = 6'd37;
				6'd44: r = 6'd37;
				6'd45: r = 6'd38;
				6'd46: r = 6'd38;
				6'd47: r = 6'd38;
				6'd48: r = 6'd39;
				6'd49: r = 6'd39;
				6'd50: r = 6'd39;
				6'd51: r = 6'd39;
				default: r = q;
			endcase
			chroma_qp = r;
		end
	endfunction
	function automatic [5:0] clip51;
		input reg signed [8:0] v;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (v < 0) begin
				clip51 = 6'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (v > 51) begin
					clip51 = 6'd51;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					clip51 = v[5:0];
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	reg [7:0] cur_y [0:255];
	reg [7:0] cur_u [0:63];
	reg [7:0] cur_v [0:63];
	reg [7:0] lft_y [0:255];
	reg [7:0] lft_u [0:63];
	reg [7:0] lft_v [0:63];
	reg lft_valid;
	reg [5:0] cur_qp;
	reg [5:0] lft_qp;
	reg [7:0] cur_x;
	reg [7:0] cur_yc;
	reg [127:0] row_y [0:(MAX_MBW * 16) - 1];
	reg [63:0] row_u [0:(MAX_MBW * 8) - 1];
	reg [63:0] row_v [0:(MAX_MBW * 8) - 1];
	reg [5:0] row_qp [0:MAX_MBW - 1];
	reg [MAX_MBW - 1:0] row_vld;
	reg cur_int;
	reg lft_int;
	reg top_int;
	reg [15:0] cur_nz;
	reg [15:0] lft_nz;
	reg [3:0] top_nz;
	reg signed [15:0] cur_mvx [0:15];
	reg signed [15:0] cur_mvy [0:15];
	reg signed [15:0] lft_mvx [0:15];
	reg signed [15:0] lft_mvy [0:15];
	reg signed [15:0] top_mvx [0:3];
	reg signed [15:0] top_mvy [0:3];
	reg [132:0] row_mi [0:MAX_MBW - 1];
	wire [132:0] row_mi_rd = row_mi[cur_x];
	reg [132:0] lft_mi_pack;
	always @(*) begin
		if (_sv2v_0)
			;
		lft_mi_pack[0] = lft_int;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin
					lft_mi_pack[1 + i] = lft_nz[12 + i];
					lft_mi_pack[5 + (i * 32)+:16] = lft_mvx[12 + i];
					lft_mi_pack[21 + (i * 32)+:16] = lft_mvy[12 + i];
				end
		end
	end
	reg [7:0] top_y_q [0:3][0:15];
	reg [7:0] top_u_q [0:3][0:7];
	reg [7:0] top_v_q [0:3][0:7];
	reg [3:0] st_q;
	reg dir_h;
	reg [1:0] e_q;
	reg [4:0] line_q;
	reg comp_q;
	reg [4:0] emit_q;
	reg [7:0] fl_x;
	assign mb_ready = st_q == 4'd0;
	assign flush_done = st_q == 4'd12;
	reg [5:0] qpav;
	reg [5:0] qpcav;
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	function automatic signed [8:0] sv2v_cast_9_signed;
		input reg signed [8:0] inp;
		sv2v_cast_9_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_2
		reg [8:0] s;
		reg [5:0] qn;
		reg [5:0] qc;
		reg [5:0] qcn;
		if (_sv2v_0)
			;
		qn = (dir_h ? row_qp[cur_x] : lft_qp);
		s = ({3'b000, cur_qp} + {3'b000, qn}) + 9'd1;
		qpav = (e_q == 0 ? sv2v_cast_6(s >> 1) : cur_qp);
		qc = chroma_qp(clip51($signed({3'b000, cur_qp}) + sv2v_cast_9_signed(cfg_cqp_off)));
		qcn = chroma_qp(clip51($signed({3'b000, qn}) + sv2v_cast_9_signed(cfg_cqp_off)));
		s = ({3'b000, qc} + {3'b000, qcn}) + 9'd1;
		qpcav = (e_q == 0 ? sv2v_cast_6(s >> 1) : qc);
	end
	wire chroma_phase;
	assign chroma_phase = (st_q == 4'd2) || (st_q == 4'd5);
	wire [5:0] ia;
	wire [5:0] ib;
	assign ia = clip51($signed({3'b000, (chroma_phase ? qpcav : qpav)}) + sv2v_cast_9_signed(cfg_a_off));
	assign ib = clip51($signed({3'b000, (chroma_phase ? qpcav : qpav)}) + sv2v_cast_9_signed(cfg_b_off));
	reg [2:0] bs;
	function automatic signed [16:0] sv2v_cast_17_signed;
		input reg signed [16:0] inp;
		sv2v_cast_17_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_3
		reg [1:0] brow;
		reg [1:0] bcol;
		reg p_intra;
		reg q_intra;
		reg p_nz;
		reg q_nz;
		reg signed [15:0] pmx;
		reg signed [15:0] pmy;
		reg signed [15:0] qmx;
		reg signed [15:0] qmy;
		reg signed [16:0] dmx;
		reg signed [16:0] dmy;
		reg [3:0] qi;
		if (_sv2v_0)
			;
		brow = 1'sb0;
		bcol = 1'sb0;
		(* full_case, parallel_case *)
		case (st_q)
			4'd1: begin
				brow = line_q[3:2];
				bcol = e_q;
			end
			4'd2: begin
				brow = line_q[2:1];
				bcol = {e_q[0], 1'b0};
			end
			4'd4: begin
				brow = e_q;
				bcol = line_q[3:2];
			end
			4'd5: begin
				brow = {e_q[0], 1'b0};
				bcol = line_q[2:1];
			end
			default:
				;
		endcase
		qi = {brow, bcol};
		q_intra = !cur_int;
		q_nz = cur_nz[qi];
		qmx = cur_mvx[qi];
		qmy = cur_mvy[qi];
		if (!dir_h) begin
			if (bcol == 2'd0) begin
				p_intra = !lft_int;
				p_nz = lft_nz[{brow, 2'd3}];
				pmx = lft_mvx[{brow, 2'd3}];
				pmy = lft_mvy[{brow, 2'd3}];
			end
			else begin
				p_intra = !cur_int;
				p_nz = cur_nz[{brow, bcol - 2'd1}];
				pmx = cur_mvx[{brow, bcol - 2'd1}];
				pmy = cur_mvy[{brow, bcol - 2'd1}];
			end
		end
		else if (brow == 2'd0) begin
			p_intra = !top_int;
			p_nz = top_nz[bcol];
			pmx = top_mvx[bcol];
			pmy = top_mvy[bcol];
		end
		else begin
			p_intra = !cur_int;
			p_nz = cur_nz[{brow - 2'd1, bcol}];
			pmx = cur_mvx[{brow - 2'd1, bcol}];
			pmy = cur_mvy[{brow - 2'd1, bcol}];
		end
		dmx = sv2v_cast_17_signed(pmx) - sv2v_cast_17_signed(qmx);
		if (dmx < 0)
			dmx = -dmx;
		dmy = sv2v_cast_17_signed(pmy) - sv2v_cast_17_signed(qmy);
		if (dmy < 0)
			dmy = -dmy;
		if (p_intra || q_intra)
			bs = (e_q == 2'd0 ? 3'd4 : 3'd3);
		else if (p_nz || q_nz)
			bs = 3'd2;
		else if ((dmx >= 17'sd4) || (dmy >= 17'sd4))
			bs = 3'd1;
		else
			bs = 3'd0;
	end
	wire [4:0] tc0;
	function automatic [4:0] dbf_tc0;
		input reg [5:0] idx;
		input reg [1:0] bsm1;
		reg [4:0] r;
		begin
			(* full_case, parallel_case *)
			case ({idx, bsm1})
				8'h00: r = 5'd0;
				8'h01: r = 5'd0;
				8'h02: r = 5'd0;
				8'h04: r = 5'd0;
				8'h05: r = 5'd0;
				8'h06: r = 5'd0;
				8'h08: r = 5'd0;
				8'h09: r = 5'd0;
				8'h0a: r = 5'd0;
				8'h0c: r = 5'd0;
				8'h0d: r = 5'd0;
				8'h0e: r = 5'd0;
				8'h10: r = 5'd0;
				8'h11: r = 5'd0;
				8'h12: r = 5'd0;
				8'h14: r = 5'd0;
				8'h15: r = 5'd0;
				8'h16: r = 5'd0;
				8'h18: r = 5'd0;
				8'h19: r = 5'd0;
				8'h1a: r = 5'd0;
				8'h1c: r = 5'd0;
				8'h1d: r = 5'd0;
				8'h1e: r = 5'd0;
				8'h20: r = 5'd0;
				8'h21: r = 5'd0;
				8'h22: r = 5'd0;
				8'h24: r = 5'd0;
				8'h25: r = 5'd0;
				8'h26: r = 5'd0;
				8'h28: r = 5'd0;
				8'h29: r = 5'd0;
				8'h2a: r = 5'd0;
				8'h2c: r = 5'd0;
				8'h2d: r = 5'd0;
				8'h2e: r = 5'd0;
				8'h30: r = 5'd0;
				8'h31: r = 5'd0;
				8'h32: r = 5'd0;
				8'h34: r = 5'd0;
				8'h35: r = 5'd0;
				8'h36: r = 5'd0;
				8'h38: r = 5'd0;
				8'h39: r = 5'd0;
				8'h3a: r = 5'd0;
				8'h3c: r = 5'd0;
				8'h3d: r = 5'd0;
				8'h3e: r = 5'd0;
				8'h40: r = 5'd0;
				8'h41: r = 5'd0;
				8'h42: r = 5'd0;
				8'h44: r = 5'd0;
				8'h45: r = 5'd0;
				8'h46: r = 5'd1;
				8'h48: r = 5'd0;
				8'h49: r = 5'd0;
				8'h4a: r = 5'd1;
				8'h4c: r = 5'd0;
				8'h4d: r = 5'd0;
				8'h4e: r = 5'd1;
				8'h50: r = 5'd0;
				8'h51: r = 5'd0;
				8'h52: r = 5'd1;
				8'h54: r = 5'd0;
				8'h55: r = 5'd1;
				8'h56: r = 5'd1;
				8'h58: r = 5'd0;
				8'h59: r = 5'd1;
				8'h5a: r = 5'd1;
				8'h5c: r = 5'd1;
				8'h5d: r = 5'd1;
				8'h5e: r = 5'd1;
				8'h60: r = 5'd1;
				8'h61: r = 5'd1;
				8'h62: r = 5'd1;
				8'h64: r = 5'd1;
				8'h65: r = 5'd1;
				8'h66: r = 5'd1;
				8'h68: r = 5'd1;
				8'h69: r = 5'd1;
				8'h6a: r = 5'd1;
				8'h6c: r = 5'd1;
				8'h6d: r = 5'd1;
				8'h6e: r = 5'd2;
				8'h70: r = 5'd1;
				8'h71: r = 5'd1;
				8'h72: r = 5'd2;
				8'h74: r = 5'd1;
				8'h75: r = 5'd1;
				8'h76: r = 5'd2;
				8'h78: r = 5'd1;
				8'h79: r = 5'd1;
				8'h7a: r = 5'd2;
				8'h7c: r = 5'd1;
				8'h7d: r = 5'd2;
				8'h7e: r = 5'd3;
				8'h80: r = 5'd1;
				8'h81: r = 5'd2;
				8'h82: r = 5'd3;
				8'h84: r = 5'd2;
				8'h85: r = 5'd2;
				8'h86: r = 5'd3;
				8'h88: r = 5'd2;
				8'h89: r = 5'd2;
				8'h8a: r = 5'd4;
				8'h8c: r = 5'd2;
				8'h8d: r = 5'd3;
				8'h8e: r = 5'd4;
				8'h90: r = 5'd2;
				8'h91: r = 5'd3;
				8'h92: r = 5'd4;
				8'h94: r = 5'd3;
				8'h95: r = 5'd3;
				8'h96: r = 5'd5;
				8'h98: r = 5'd3;
				8'h99: r = 5'd4;
				8'h9a: r = 5'd6;
				8'h9c: r = 5'd3;
				8'h9d: r = 5'd4;
				8'h9e: r = 5'd6;
				8'ha0: r = 5'd4;
				8'ha1: r = 5'd5;
				8'ha2: r = 5'd7;
				8'ha4: r = 5'd4;
				8'ha5: r = 5'd5;
				8'ha6: r = 5'd8;
				8'ha8: r = 5'd4;
				8'ha9: r = 5'd6;
				8'haa: r = 5'd9;
				8'hac: r = 5'd5;
				8'had: r = 5'd7;
				8'hae: r = 5'd10;
				8'hb0: r = 5'd6;
				8'hb1: r = 5'd8;
				8'hb2: r = 5'd11;
				8'hb4: r = 5'd6;
				8'hb5: r = 5'd8;
				8'hb6: r = 5'd13;
				8'hb8: r = 5'd7;
				8'hb9: r = 5'd10;
				8'hba: r = 5'd14;
				8'hbc: r = 5'd8;
				8'hbd: r = 5'd11;
				8'hbe: r = 5'd16;
				8'hc0: r = 5'd9;
				8'hc1: r = 5'd12;
				8'hc2: r = 5'd18;
				8'hc4: r = 5'd10;
				8'hc5: r = 5'd13;
				8'hc6: r = 5'd20;
				8'hc8: r = 5'd11;
				8'hc9: r = 5'd15;
				8'hca: r = 5'd23;
				8'hcc: r = 5'd13;
				8'hcd: r = 5'd17;
				8'hce: r = 5'd25;
				default: r = 5'd0;
			endcase
			dbf_tc0 = r;
		end
	endfunction
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	assign tc0 = ((bs != 3'd0) && (bs < 3'd4) ? dbf_tc0(ia, sv2v_cast_2(bs - 3'd1)) : 5'd0);
	reg [7:0] smp [0:7];
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_4
		reg signed [31:0] e4;
		reg signed [31:0] ln;
		if (_sv2v_0)
			;
		e4 = sv2v_cast_32_signed(e_q) * 4;
		ln = sv2v_cast_32_signed(line_q);
		begin : sv2v_autoblock_5
			reg signed [31:0] i;
			for (i = 0; i < 8; i = i + 1)
				smp[i] = 1'sb0;
		end
		(* full_case, parallel_case *)
		case (st_q)
			4'd1: begin : sv2v_autoblock_6
				reg signed [31:0] i;
				for (i = 0; i < 8; i = i + 1)
					begin : sv2v_autoblock_7
						reg signed [31:0] x;
						x = (e4 - 4) + i;
						smp[i] = (x < 0 ? lft_y[((ln * 16) + 16) + x] : cur_y[(ln * 16) + x]);
					end
			end
			4'd2: begin : sv2v_autoblock_8
				reg signed [31:0] i;
				for (i = 0; i < 8; i = i + 1)
					begin : sv2v_autoblock_9
						reg signed [31:0] x;
						x = (e4 - 4) + i;
						if (comp_q)
							smp[i] = (x < 0 ? lft_v[((ln * 8) + 8) + x] : cur_v[(ln * 8) + x]);
						else
							smp[i] = (x < 0 ? lft_u[((ln * 8) + 8) + x] : cur_u[(ln * 8) + x]);
					end
			end
			4'd4: begin : sv2v_autoblock_10
				reg signed [31:0] i;
				for (i = 0; i < 8; i = i + 1)
					begin : sv2v_autoblock_11
						reg signed [31:0] y;
						y = (e4 - 4) + i;
						smp[i] = (y < 0 ? top_y_q[4 + y][ln] : cur_y[(y * 16) + ln]);
					end
			end
			4'd5: begin : sv2v_autoblock_12
				reg signed [31:0] i;
				for (i = 0; i < 8; i = i + 1)
					begin : sv2v_autoblock_13
						reg signed [31:0] y;
						y = (e4 - 4) + i;
						if (comp_q)
							smp[i] = (y < 0 ? top_v_q[4 + y][ln] : cur_v[(y * 8) + ln]);
						else
							smp[i] = (y < 0 ? top_u_q[4 + y][ln] : cur_u[(y * 8) + ln]);
					end
			end
			default:
				;
		endcase
	end
	wire [7:0] o_p2;
	wire [7:0] o_p1;
	wire [7:0] o_p0;
	wire [7:0] o_q0;
	wire [7:0] o_q1;
	wire [7:0] o_q2;
	function automatic [7:0] dbf_alpha;
		input reg [5:0] idx;
		reg [7:0] r;
		begin
			(* full_case, parallel_case *)
			case (idx)
				6'd0: r = 8'd0;
				6'd1: r = 8'd0;
				6'd2: r = 8'd0;
				6'd3: r = 8'd0;
				6'd4: r = 8'd0;
				6'd5: r = 8'd0;
				6'd6: r = 8'd0;
				6'd7: r = 8'd0;
				6'd8: r = 8'd0;
				6'd9: r = 8'd0;
				6'd10: r = 8'd0;
				6'd11: r = 8'd0;
				6'd12: r = 8'd0;
				6'd13: r = 8'd0;
				6'd14: r = 8'd0;
				6'd15: r = 8'd0;
				6'd16: r = 8'd4;
				6'd17: r = 8'd4;
				6'd18: r = 8'd5;
				6'd19: r = 8'd6;
				6'd20: r = 8'd7;
				6'd21: r = 8'd8;
				6'd22: r = 8'd9;
				6'd23: r = 8'd10;
				6'd24: r = 8'd12;
				6'd25: r = 8'd13;
				6'd26: r = 8'd15;
				6'd27: r = 8'd17;
				6'd28: r = 8'd20;
				6'd29: r = 8'd22;
				6'd30: r = 8'd25;
				6'd31: r = 8'd28;
				6'd32: r = 8'd32;
				6'd33: r = 8'd36;
				6'd34: r = 8'd40;
				6'd35: r = 8'd45;
				6'd36: r = 8'd50;
				6'd37: r = 8'd56;
				6'd38: r = 8'd63;
				6'd39: r = 8'd71;
				6'd40: r = 8'd80;
				6'd41: r = 8'd90;
				6'd42: r = 8'd101;
				6'd43: r = 8'd113;
				6'd44: r = 8'd127;
				6'd45: r = 8'd144;
				6'd46: r = 8'd162;
				6'd47: r = 8'd182;
				6'd48: r = 8'd203;
				6'd49: r = 8'd226;
				6'd50: r = 8'd255;
				6'd51: r = 8'd255;
				default: r = 8'd255;
			endcase
			dbf_alpha = r;
		end
	endfunction
	function automatic [7:0] dbf_beta;
		input reg [5:0] idx;
		reg [7:0] r;
		begin
			(* full_case, parallel_case *)
			case (idx)
				6'd0: r = 8'd0;
				6'd1: r = 8'd0;
				6'd2: r = 8'd0;
				6'd3: r = 8'd0;
				6'd4: r = 8'd0;
				6'd5: r = 8'd0;
				6'd6: r = 8'd0;
				6'd7: r = 8'd0;
				6'd8: r = 8'd0;
				6'd9: r = 8'd0;
				6'd10: r = 8'd0;
				6'd11: r = 8'd0;
				6'd12: r = 8'd0;
				6'd13: r = 8'd0;
				6'd14: r = 8'd0;
				6'd15: r = 8'd0;
				6'd16: r = 8'd2;
				6'd17: r = 8'd2;
				6'd18: r = 8'd2;
				6'd19: r = 8'd3;
				6'd20: r = 8'd3;
				6'd21: r = 8'd3;
				6'd22: r = 8'd3;
				6'd23: r = 8'd4;
				6'd24: r = 8'd4;
				6'd25: r = 8'd4;
				6'd26: r = 8'd6;
				6'd27: r = 8'd6;
				6'd28: r = 8'd7;
				6'd29: r = 8'd7;
				6'd30: r = 8'd8;
				6'd31: r = 8'd8;
				6'd32: r = 8'd9;
				6'd33: r = 8'd9;
				6'd34: r = 8'd10;
				6'd35: r = 8'd10;
				6'd36: r = 8'd11;
				6'd37: r = 8'd11;
				6'd38: r = 8'd12;
				6'd39: r = 8'd12;
				6'd40: r = 8'd13;
				6'd41: r = 8'd13;
				6'd42: r = 8'd14;
				6'd43: r = 8'd14;
				6'd44: r = 8'd15;
				6'd45: r = 8'd15;
				6'd46: r = 8'd16;
				6'd47: r = 8'd16;
				6'd48: r = 8'd17;
				6'd49: r = 8'd17;
				6'd50: r = 8'd18;
				6'd51: r = 8'd18;
				default: r = 8'd18;
			endcase
			dbf_beta = r;
		end
	endfunction
	deblock_edge u_edge(
		.p3(smp[0]),
		.p2(smp[1]),
		.p1(smp[2]),
		.p0(smp[3]),
		.q0(smp[4]),
		.q1(smp[5]),
		.q2(smp[6]),
		.q3(smp[7]),
		.alpha(dbf_alpha(ia)),
		.beta(dbf_beta(ib)),
		.bs(bs),
		.tc0(tc0),
		.chroma(chroma_phase),
		.o_p2(o_p2),
		.o_p1(o_p1),
		.o_p0(o_p0),
		.o_q0(o_q0),
		.o_q1(o_q1),
		.o_q2(o_q2)
	);
	wire skip_v0;
	wire skip_h0;
	assign skip_v0 = !lft_valid || !cfg_enable;
	assign skip_h0 = !row_vld[cur_x] || !cfg_enable;
	wire [7:0] emit_x;
	assign emit_x = (st_q == 4'd11 ? fl_x : cur_x);
	function automatic signed [11:0] sv2v_cast_12_signed;
		input reg signed [11:0] inp;
		sv2v_cast_12_signed = inp;
	endfunction
	function automatic signed [10:0] sv2v_cast_11_signed;
		input reg signed [10:0] inp;
		sv2v_cast_11_signed = inp;
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [11:0] sv2v_cast_12;
		input reg [11:0] inp;
		sv2v_cast_12 = inp;
	endfunction
	function automatic [10:0] sv2v_cast_11;
		input reg [10:0] inp;
		sv2v_cast_11 = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 4'd0;
			dir_h <= 1'b0;
			e_q <= 1'sb0;
			line_q <= 1'sb0;
			comp_q <= 1'b0;
			emit_q <= 1'sb0;
			lft_valid <= 1'b0;
			cur_qp <= 1'sb0;
			lft_qp <= 1'sb0;
			cur_x <= 1'sb0;
			cur_yc <= 1'sb0;
			fl_x <= 1'sb0;
			out_valid <= 1'b0;
			row_vld <= 1'sb0;
		end
		else begin
			out_valid <= 1'b0;
			(* full_case, parallel_case *)
			case (st_q)
				4'd0:
					if (flush) begin
						fl_x <= 1'sb0;
						emit_q <= 1'sb0;
						st_q <= 4'd11;
					end
					else if (mb_push) begin
						begin : sv2v_autoblock_14
							reg signed [31:0] i;
							for (i = 0; i < 256; i = i + 1)
								cur_y[i] <= in_y[(255 - i) * 8+:8];
						end
						begin : sv2v_autoblock_15
							reg signed [31:0] i;
							for (i = 0; i < 64; i = i + 1)
								begin
									cur_u[i] <= in_u[(63 - i) * 8+:8];
									cur_v[i] <= in_v[(63 - i) * 8+:8];
								end
						end
						cur_qp <= mb_qp;
						cur_int <= mb_inter;
						cur_nz <= mb_nz;
						begin : sv2v_autoblock_16
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								begin
									cur_mvx[i] <= mb_mvx[(15 - i) * 16+:16];
									cur_mvy[i] <= mb_mvy[(15 - i) * 16+:16];
								end
						end
						cur_x <= mb_x;
						cur_yc <= mb_y;
						if (mb_x == 8'd0)
							lft_valid <= 1'b0;
						dir_h <= 1'b0;
						e_q <= 1'sb0;
						line_q <= 1'sb0;
						st_q <= 4'd1;
					end
				4'd1: begin
					if (cfg_enable && !((e_q == 0) && skip_v0)) begin
						if (bs != 3'd0) begin : sv2v_autoblock_17
							reg signed [31:0] e4;
							reg signed [31:0] ln;
							e4 = sv2v_cast_32_signed(e_q) * 4;
							ln = sv2v_cast_32_signed(line_q);
							begin : sv2v_autoblock_18
								reg signed [31:0] i;
								for (i = 1; i < 7; i = i + 1)
									begin : sv2v_autoblock_19
										reg signed [31:0] x;
										reg [7:0] v;
										x = (e4 - 4) + i;
										(* full_case, parallel_case *)
										case (i)
											1: v = o_p2;
											2: v = o_p1;
											3: v = o_p0;
											4: v = o_q0;
											5: v = o_q1;
											default: v = o_q2;
										endcase
										if (x < 0)
											lft_y[((ln * 16) + 16) + x] <= v;
										else
											cur_y[(ln * 16) + x] <= v;
									end
							end
						end
					end
					if (((e_q == 0) && skip_v0) || (line_q == 5'd15)) begin
						line_q <= 1'sb0;
						if (e_q == 2'd3) begin
							e_q <= 1'sb0;
							comp_q <= 1'b0;
							st_q <= 4'd2;
						end
						else
							e_q <= e_q + 2'd1;
					end
					else
						line_q <= line_q + 5'd1;
				end
				4'd2: begin
					if (cfg_enable && !((e_q == 0) && skip_v0)) begin
						if (bs != 3'd0) begin : sv2v_autoblock_20
							reg signed [31:0] e4;
							reg signed [31:0] ln;
							e4 = sv2v_cast_32_signed(e_q) * 4;
							ln = sv2v_cast_32_signed(line_q);
							begin : sv2v_autoblock_21
								reg signed [31:0] i;
								for (i = 2; i < 6; i = i + 1)
									begin : sv2v_autoblock_22
										reg signed [31:0] x;
										reg [7:0] v;
										x = (e4 - 4) + i;
										(* full_case, parallel_case *)
										case (i)
											2: v = o_p1;
											3: v = o_p0;
											4: v = o_q0;
											default: v = o_q1;
										endcase
										if (x < 0) begin
											if (comp_q)
												lft_v[((ln * 8) + 8) + x] <= v;
											else
												lft_u[((ln * 8) + 8) + x] <= v;
										end
										else if (comp_q)
											cur_v[(ln * 8) + x] <= v;
										else
											cur_u[(ln * 8) + x] <= v;
									end
							end
						end
					end
					if (((e_q == 0) && skip_v0) || (line_q == 5'd7)) begin
						line_q <= 1'sb0;
						if (!comp_q)
							comp_q <= 1'b1;
						else begin
							comp_q <= 1'b0;
							if (e_q == 2'd1) begin
								e_q <= 1'sb0;
								emit_q <= 1'sb0;
								dir_h <= 1'b1;
								st_q <= 4'd3;
							end
							else
								e_q <= e_q + 2'd1;
						end
					end
					else
						line_q <= line_q + 5'd1;
				end
				4'd3: begin
					begin : sv2v_autoblock_23
						reg signed [31:0] r;
						for (r = 0; r < 4; r = r + 1)
							begin
								begin : sv2v_autoblock_24
									reg signed [31:0] c;
									for (c = 0; c < 16; c = c + 1)
										top_y_q[r][c] <= row_y[{cur_x, 4'b0000} + sv2v_cast_12_signed(12 + r)][c * 8+:8];
								end
								begin : sv2v_autoblock_25
									reg signed [31:0] c;
									for (c = 0; c < 8; c = c + 1)
										begin
											top_u_q[r][c] <= row_u[{cur_x, 3'b000} + sv2v_cast_11_signed(4 + r)][c * 8+:8];
											top_v_q[r][c] <= row_v[{cur_x, 3'b000} + sv2v_cast_11_signed(4 + r)][c * 8+:8];
										end
								end
							end
					end
					top_int <= row_mi_rd[0];
					begin : sv2v_autoblock_26
						reg signed [31:0] i;
						for (i = 0; i < 4; i = i + 1)
							begin
								top_nz[i] <= row_mi_rd[1 + i];
								top_mvx[i] <= row_mi_rd[5 + (i * 32)+:16];
								top_mvy[i] <= row_mi_rd[21 + (i * 32)+:16];
							end
					end
					dir_h <= 1'b1;
					e_q <= 1'sb0;
					line_q <= 1'sb0;
					st_q <= 4'd4;
				end
				4'd4: begin
					if (cfg_enable && !((e_q == 0) && skip_h0)) begin
						if (bs != 3'd0) begin : sv2v_autoblock_27
							reg signed [31:0] e4;
							reg signed [31:0] ln;
							e4 = sv2v_cast_32_signed(e_q) * 4;
							ln = sv2v_cast_32_signed(line_q);
							begin : sv2v_autoblock_28
								reg signed [31:0] i;
								for (i = 1; i < 7; i = i + 1)
									begin : sv2v_autoblock_29
										reg signed [31:0] y;
										reg [7:0] v;
										y = (e4 - 4) + i;
										(* full_case, parallel_case *)
										case (i)
											1: v = o_p2;
											2: v = o_p1;
											3: v = o_p0;
											4: v = o_q0;
											5: v = o_q1;
											default: v = o_q2;
										endcase
										if (y < 0)
											top_y_q[4 + y][ln] <= v;
										else
											cur_y[(y * 16) + ln] <= v;
									end
							end
						end
					end
					if (((e_q == 0) && skip_h0) || (line_q == 5'd15)) begin
						line_q <= 1'sb0;
						if (e_q == 2'd3) begin
							e_q <= 1'sb0;
							comp_q <= 1'b0;
							st_q <= 4'd5;
						end
						else
							e_q <= e_q + 2'd1;
					end
					else
						line_q <= line_q + 5'd1;
				end
				4'd5: begin
					if (cfg_enable && !((e_q == 0) && skip_h0)) begin
						if (bs != 3'd0) begin : sv2v_autoblock_30
							reg signed [31:0] e4;
							reg signed [31:0] ln;
							e4 = sv2v_cast_32_signed(e_q) * 4;
							ln = sv2v_cast_32_signed(line_q);
							begin : sv2v_autoblock_31
								reg signed [31:0] i;
								for (i = 2; i < 6; i = i + 1)
									begin : sv2v_autoblock_32
										reg signed [31:0] y;
										reg [7:0] v;
										y = (e4 - 4) + i;
										(* full_case, parallel_case *)
										case (i)
											2: v = o_p1;
											3: v = o_p0;
											4: v = o_q0;
											default: v = o_q1;
										endcase
										if (y < 0) begin
											if (comp_q)
												top_v_q[4 + y][ln] <= v;
											else
												top_u_q[4 + y][ln] <= v;
										end
										else if (comp_q)
											cur_v[(y * 8) + ln] <= v;
										else
											cur_u[(y * 8) + ln] <= v;
									end
							end
						end
					end
					if (((e_q == 0) && skip_h0) || (line_q == 5'd7)) begin
						line_q <= 1'sb0;
						if (!comp_q)
							comp_q <= 1'b1;
						else begin
							comp_q <= 1'b0;
							if (e_q == 2'd1) begin
								e_q <= 1'sb0;
								emit_q <= 1'sb0;
								st_q <= 4'd6;
							end
							else
								e_q <= e_q + 2'd1;
						end
					end
					else
						line_q <= line_q + 5'd1;
				end
				4'd6: begin
					begin : sv2v_autoblock_33
						reg signed [31:0] r;
						for (r = 0; r < 4; r = r + 1)
							begin : sv2v_autoblock_34
								reg [127:0] wy;
								reg [63:0] wu;
								reg [63:0] wv;
								begin : sv2v_autoblock_35
									reg signed [31:0] c;
									for (c = 0; c < 16; c = c + 1)
										wy[c * 8+:8] = top_y_q[r][c];
								end
								begin : sv2v_autoblock_36
									reg signed [31:0] c;
									for (c = 0; c < 8; c = c + 1)
										begin
											wu[c * 8+:8] = top_u_q[r][c];
											wv[c * 8+:8] = top_v_q[r][c];
										end
								end
								row_y[{cur_x, 4'b0000} + sv2v_cast_12_signed(12 + r)] <= wy;
								row_u[{cur_x, 3'b000} + sv2v_cast_11_signed(4 + r)] <= wu;
								row_v[{cur_x, 3'b000} + sv2v_cast_11_signed(4 + r)] <= wv;
							end
					end
					emit_q <= 1'sb0;
					st_q <= (row_vld[cur_x] ? 4'd7 : 4'd8);
				end
				4'd7: begin
					out_valid <= 1'b1;
					out_mbx <= cur_x;
					out_mby <= cur_yc - 8'd1;
					if (emit_q < 5'd16) begin
						out_plane <= 2'd0;
						out_row <= sv2v_cast_4(emit_q);
						out_data <= row_y[{cur_x, 4'b0000} + sv2v_cast_12(emit_q)];
					end
					else if (emit_q < 5'd24) begin
						out_plane <= 2'd1;
						out_row <= sv2v_cast_4(emit_q - 5'd16);
						out_data <= {64'b0000000000000000000000000000000000000000000000000000000000000000, row_u[{cur_x, 3'b000} + sv2v_cast_11(emit_q - 5'd16)]};
					end
					else begin
						out_plane <= 2'd2;
						out_row <= sv2v_cast_4(emit_q - 5'd24);
						out_data <= {64'b0000000000000000000000000000000000000000000000000000000000000000, row_v[{cur_x, 3'b000} + sv2v_cast_11(emit_q - 5'd24)]};
					end
					if (emit_q == 5'd31) begin
						emit_q <= 1'sb0;
						st_q <= 4'd8;
					end
					else
						emit_q <= emit_q + 5'd1;
				end
				4'd8:
					if (lft_valid) begin
						if (emit_q < 5'd16) begin : sv2v_autoblock_37
							reg [127:0] w;
							begin : sv2v_autoblock_38
								reg signed [31:0] i;
								for (i = 0; i < 16; i = i + 1)
									w[i * 8+:8] = lft_y[(sv2v_cast_32_signed(emit_q) * 16) + i];
							end
							row_y[{cur_x - 8'd1, 4'b0000} + sv2v_cast_12(emit_q)] <= w;
							emit_q <= emit_q + 5'd1;
						end
						else if (emit_q < 5'd24) begin : sv2v_autoblock_39
							reg [63:0] wu;
							reg [63:0] wv;
							begin : sv2v_autoblock_40
								reg signed [31:0] i;
								for (i = 0; i < 8; i = i + 1)
									begin
										wu[i * 8+:8] = lft_u[((sv2v_cast_32_signed(emit_q) - 16) * 8) + i];
										wv[i * 8+:8] = lft_v[((sv2v_cast_32_signed(emit_q) - 16) * 8) + i];
									end
							end
							row_u[{cur_x - 8'd1, 3'b000} + sv2v_cast_11(emit_q - 5'd16)] <= wu;
							row_v[{cur_x - 8'd1, 3'b000} + sv2v_cast_11(emit_q - 5'd16)] <= wv;
							emit_q <= emit_q + 5'd1;
						end
						else begin
							row_qp[cur_x - 8'd1] <= lft_qp;
							row_mi[cur_x - 8'd1] <= lft_mi_pack;
							row_vld[cur_x - 8'd1] <= 1'b1;
							emit_q <= 1'sb0;
							st_q <= 4'd9;
						end
					end
					else begin
						emit_q <= 1'sb0;
						st_q <= 4'd9;
					end
				4'd9: begin
					begin : sv2v_autoblock_41
						reg signed [31:0] i;
						for (i = 0; i < 256; i = i + 1)
							lft_y[i] <= cur_y[i];
					end
					begin : sv2v_autoblock_42
						reg signed [31:0] i;
						for (i = 0; i < 64; i = i + 1)
							begin
								lft_u[i] <= cur_u[i];
								lft_v[i] <= cur_v[i];
							end
					end
					lft_qp <= cur_qp;
					lft_int <= cur_int;
					lft_nz <= cur_nz;
					begin : sv2v_autoblock_43
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							begin
								lft_mvx[i] <= cur_mvx[i];
								lft_mvy[i] <= cur_mvy[i];
							end
					end
					lft_valid <= 1'b1;
					if ((cur_x + 8'd1) == cfg_mb_w) begin
						emit_q <= 1'sb0;
						st_q <= 4'd10;
					end
					else
						st_q <= 4'd0;
				end
				4'd10:
					if (emit_q < 5'd16) begin : sv2v_autoblock_44
						reg [127:0] w;
						begin : sv2v_autoblock_45
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								w[i * 8+:8] = lft_y[(sv2v_cast_32_signed(emit_q) * 16) + i];
						end
						row_y[{cur_x, 4'b0000} + sv2v_cast_12(emit_q)] <= w;
						emit_q <= emit_q + 5'd1;
					end
					else if (emit_q < 5'd24) begin : sv2v_autoblock_46
						reg [63:0] wu;
						reg [63:0] wv;
						begin : sv2v_autoblock_47
							reg signed [31:0] i;
							for (i = 0; i < 8; i = i + 1)
								begin
									wu[i * 8+:8] = lft_u[((sv2v_cast_32_signed(emit_q) - 16) * 8) + i];
									wv[i * 8+:8] = lft_v[((sv2v_cast_32_signed(emit_q) - 16) * 8) + i];
								end
						end
						row_u[{cur_x, 3'b000} + sv2v_cast_11(emit_q - 5'd16)] <= wu;
						row_v[{cur_x, 3'b000} + sv2v_cast_11(emit_q - 5'd16)] <= wv;
						emit_q <= emit_q + 5'd1;
					end
					else begin
						row_qp[cur_x] <= lft_qp;
						row_mi[cur_x] <= lft_mi_pack;
						row_vld[cur_x] <= 1'b1;
						lft_valid <= 1'b0;
						emit_q <= 1'sb0;
						st_q <= 4'd0;
					end
				4'd11:
					if (!row_vld[fl_x]) begin
						if ((fl_x + 8'd1) == cfg_mb_w)
							st_q <= 4'd12;
						else
							fl_x <= fl_x + 8'd1;
					end
					else begin
						out_valid <= 1'b1;
						out_mbx <= fl_x;
						out_mby <= cur_yc;
						if (emit_q < 5'd16) begin
							out_plane <= 2'd0;
							out_row <= sv2v_cast_4(emit_q);
							out_data <= row_y[{fl_x, 4'b0000} + sv2v_cast_12(emit_q)];
						end
						else if (emit_q < 5'd24) begin
							out_plane <= 2'd1;
							out_row <= sv2v_cast_4(emit_q - 5'd16);
							out_data <= {64'b0000000000000000000000000000000000000000000000000000000000000000, row_u[{fl_x, 3'b000} + sv2v_cast_11(emit_q - 5'd16)]};
						end
						else begin
							out_plane <= 2'd2;
							out_row <= sv2v_cast_4(emit_q - 5'd24);
							out_data <= {64'b0000000000000000000000000000000000000000000000000000000000000000, row_v[{fl_x, 3'b000} + sv2v_cast_11(emit_q - 5'd24)]};
						end
						if (emit_q == 5'd31) begin
							emit_q <= 1'sb0;
							row_vld[fl_x] <= 1'b0;
							if ((fl_x + 8'd1) == cfg_mb_w)
								st_q <= 4'd12;
							else
								fl_x <= fl_x + 8'd1;
						end
						else
							emit_q <= emit_q + 5'd1;
					end
				4'd12: st_q <= 4'd12;
				default: st_q <= 4'd0;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
