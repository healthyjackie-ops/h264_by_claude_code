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
	cfg_cabac,
	cfg_init_idc,
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
	input wire cfg_cabac;
	input wire [1:0] cfg_init_idc;
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
	wire c_req_valid;
	wire [4:0] m_req_bits;
	wire [4:0] b_req_bits;
	wire [4:0] c_req_bits;
	assign br_req_valid = ((align_valid | m_req_valid) | b_req_valid) | c_req_valid;
	assign br_req_bits = (align_valid ? align_bits : (c_req_valid ? c_req_bits : (b_req_valid ? b_req_bits : m_req_bits)));
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
	wire mb_valid_v;
	wire [7:0] mb_x;
	wire [7:0] mb_y;
	wire [7:0] mb_x_v;
	wire [7:0] mb_y_v;
	wire mb_i16;
	wire mb_i16_v;
	wire [5:0] mb_cbp;
	wire [5:0] mb_qp;
	wire [5:0] mb_cbp_v;
	wire [5:0] mb_qp_v;
	wire [1:0] mb_i16_mode;
	wire [1:0] mb_cmode;
	wire [1:0] mb_i16_mode_v;
	wire [1:0] mb_cmode_v;
	wire [63:0] mb_i4m;
	wire [63:0] mb_i4m_v;
	wire coef_we;
	wire coef_we_v;
	wire [4:0] coef_blk;
	wire [4:0] coef_blk_v;
	wire [3:0] coef_addr;
	wire [3:0] coef_addr_v;
	wire signed [15:0] coef_data;
	wire signed [15:0] coef_data_v;
	wire [15:0] mb_nz_v;
	wire slice_done_v;
	wire mb_err_v;
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
	mb_dec #(.MAX_MBW(MAX_MBW)) u_mb(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.cfg_mb_h(cfg_mb_h),
		.cfg_qp(cfg_qp),
		.cfg_is_p(cfg_is_p),
		.start(start && !cfg_cabac),
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
		.mb_nz(mb_nz_v),
		.mb_valid(mb_valid_v),
		.mb_x(mb_x_v),
		.mb_y(mb_y_v),
		.mb_i16(mb_i16_v),
		.mb_cbp(mb_cbp_v),
		.mb_qp(mb_qp_v),
		.mb_i16_mode(mb_i16_mode_v),
		.mb_cmode(mb_cmode_v),
		.mb_i4m(mb_i4m_v),
		.coef_we(coef_we_v),
		.coef_blk(coef_blk_v),
		.coef_addr(coef_addr_v),
		.coef_data(coef_data_v),
		.slice_done(slice_done_v),
		.err(mb_err_v),
		.rec_done(rec_accept)
	);
	wire mb_valid_c;
	wire slice_done_c;
	wire mb_err_c;
	wire coef_we_c;
	wire [7:0] mb_x_c;
	wire [7:0] mb_y_c;
	wire mb_i16_c;
	wire [5:0] mb_cbp_c;
	wire [5:0] mb_qp_c;
	wire [1:0] mb_i16_mode_c;
	wire [1:0] mb_cmode_c;
	wire [63:0] mb_i4m_c;
	wire [4:0] coef_blk_c;
	wire [3:0] coef_addr_c;
	wire signed [15:0] coef_data_c;
	wire mb_skip_c;
	wire mb_inter_c;
	wire mvd_valid_c;
	wire skip_go_c;
	wire [2:0] mb_ptype_c;
	wire [7:0] mb_sub_c;
	wire signed [15:0] mvd_x_c;
	wire signed [15:0] mvd_y_c;
	wire [15:0] mb_nz_c;
	cabac_mb #(.MAX_MBW(MAX_MBW)) u_cm(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.cfg_mb_h(cfg_mb_h),
		.cfg_qp(cfg_qp),
		.start(start && cfg_cabac),
		.req_valid(c_req_valid),
		.req_bits(c_req_bits),
		.req_ready(br_req_ready),
		.show(show),
		.avail(avail),
		.cfg_is_p(cfg_is_p),
		.cfg_init_idc(cfg_init_idc),
		.mb_skip(mb_skip_c),
		.mb_inter(mb_inter_c),
		.mb_ptype(mb_ptype_c),
		.mb_sub(mb_sub_c),
		.mvd_valid(mvd_valid_c),
		.mvd_x(mvd_x_c),
		.mvd_y(mvd_y_c),
		.skip_go(skip_go_c),
		.mb_nz(mb_nz_c),
		.mb_valid(mb_valid_c),
		.mb_x(mb_x_c),
		.mb_y(mb_y_c),
		.mb_i16(mb_i16_c),
		.mb_cbp(mb_cbp_c),
		.mb_qp(mb_qp_c),
		.mb_i16_mode(mb_i16_mode_c),
		.mb_cmode(mb_cmode_c),
		.mb_i4m(mb_i4m_c),
		.coef_we(coef_we_c),
		.coef_blk(coef_blk_c),
		.coef_addr(coef_addr_c),
		.coef_data(coef_data_c),
		.slice_done(slice_done_c),
		.err(mb_err_c),
		.rec_done(rec_accept)
	);
	assign mb_valid = (cfg_cabac ? mb_valid_c : mb_valid_v);
	assign mb_x = (cfg_cabac ? mb_x_c : mb_x_v);
	assign mb_y = (cfg_cabac ? mb_y_c : mb_y_v);
	assign mb_i16 = (cfg_cabac ? mb_i16_c : mb_i16_v);
	assign mb_cbp = (cfg_cabac ? mb_cbp_c : mb_cbp_v);
	assign mb_qp = (cfg_cabac ? mb_qp_c : mb_qp_v);
	assign mb_i16_mode = (cfg_cabac ? mb_i16_mode_c : mb_i16_mode_v);
	assign mb_cmode = (cfg_cabac ? mb_cmode_c : mb_cmode_v);
	assign mb_i4m = (cfg_cabac ? mb_i4m_c : mb_i4m_v);
	assign coef_we = (cfg_cabac ? coef_we_c : coef_we_v);
	assign coef_blk = (cfg_cabac ? coef_blk_c : coef_blk_v);
	assign coef_addr = (cfg_cabac ? coef_addr_c : coef_addr_v);
	assign coef_data = (cfg_cabac ? coef_data_c : coef_data_v);
	wire slice_done;
	assign slice_done = (cfg_cabac ? slice_done_c : slice_done_v);
	assign mb_err = (cfg_cabac ? mb_err_c : mb_err_v);
	assign mb_nz_w = (cfg_cabac ? mb_nz_c : mb_nz_v);
	wire mb_skip_m;
	wire mb_inter_m;
	wire mvd_valid_m;
	wire skip_go_m;
	wire [2:0] mb_ptype_m;
	wire [7:0] mb_sub_m;
	wire signed [15:0] mvd_x_m;
	wire signed [15:0] mvd_y_m;
	assign mb_skip_m = (cfg_cabac ? mb_skip_c : mb_skip);
	assign mb_inter_m = (cfg_cabac ? mb_inter_c : mb_inter);
	assign mb_ptype_m = (cfg_cabac ? mb_ptype_c : mb_ptype);
	assign mb_sub_m = (cfg_cabac ? mb_sub_c : mb_sub);
	assign mvd_valid_m = (cfg_cabac ? mvd_valid_c : mvd_valid);
	assign mvd_x_m = (cfg_cabac ? mvd_x_c : mvd_x);
	assign mvd_y_m = (cfg_cabac ? mvd_y_c : mvd_y);
	assign skip_go_m = (cfg_cabac ? skip_go_c : skip_go_w);
	mv_pred #(.MAX_MBW(MAX_MBW)) u_mv(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.start(start),
		.mb_ptype(mb_ptype_m),
		.mb_sub(mb_sub_m),
		.mvd_valid(mvd_valid_m),
		.mvd_x(mvd_x_m),
		.mvd_y(mvd_y_m),
		.skip_go(skip_go_m),
		.commit(rec_accept),
		.mb_inter(mb_inter_m),
		.mb_skip(mb_skip_m),
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
		.mb_inter(mb_inter_m),
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
	wire [5:0] mlk;
	wire [3:0] mck;
	wire mc_is_c;
	reg [11:0] mc_px;
	reg [10:0] mc_py;
	assign mlk = (mc_done_w ? mk_q + 6'd1 : mk_q);
	assign mck = mlk[3:0];
	assign mc_is_c = mlk[5:4] != 2'd0;
	wire [3:0] wck;
	assign wck = mk_q[3:0];
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
	assign mc_start_w = (st_q == 4'd13) && (!mc_busy_w || (mc_done_w && (mk_q != 6'd47)));
	assign mc_req_plane = mk_q[5:4];
	mc_fetch u_mc(
		.clk(clk),
		.rst_n(rst_n),
		.start(mc_start_w),
		.is_chroma(mc_is_c),
		.c2x2(mc_is_c),
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
						if (mk_q[5:4] == 2'd0) begin : sv2v_autoblock_24
							reg signed [31:0] y;
							for (y = 0; y < 4; y = y + 1)
								begin : sv2v_autoblock_25
									reg signed [31:0] x;
									for (x = 0; x < 4; x = x + 1)
										rec_y[(255 - (((((sv2v_cast_32_signed(zsy(wck)) * 4) + y) * 16) + (sv2v_cast_32_signed(zsx(wck)) * 4)) + x)) * 8+:8] <= mc_pred_w[(15 - ((y * 4) + x)) * 8+:8];
								end
						end
						else if (!mk_q[5]) begin : sv2v_autoblock_26
							reg signed [31:0] y;
							for (y = 0; y < 2; y = y + 1)
								begin : sv2v_autoblock_27
									reg signed [31:0] x;
									for (x = 0; x < 2; x = x + 1)
										rec_u[(63 - (((((sv2v_cast_32_signed(zsy(wck)) * 2) + y) * 8) + (sv2v_cast_32_signed(zsx(wck)) * 2)) + x)) * 8+:8] <= mc_pred_w[(15 - ((y * 4) + x)) * 8+:8];
								end
						end
						else begin : sv2v_autoblock_28
							reg signed [31:0] y;
							for (y = 0; y < 2; y = y + 1)
								begin : sv2v_autoblock_29
									reg signed [31:0] x;
									for (x = 0; x < 2; x = x + 1)
										rec_v[(63 - (((((sv2v_cast_32_signed(zsy(wck)) * 2) + y) * 8) + (sv2v_cast_32_signed(zsx(wck)) * 2)) + x)) * 8+:8] <= mc_pred_w[(15 - ((y * 4) + x)) * 8+:8];
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
	c2x2,
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
	input wire c2x2;
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
	reg c2_q;
	assign nrows = (c2_q ? 4'd3 : (chroma_q ? 4'd5 : 4'd9));
	assign req_valid = (st_q == 2'd1) && (row_q < nrows);
	assign req_x = x0_q;
	function automatic [11:0] sv2v_cast_12;
		input reg [11:0] inp;
		sv2v_cast_12 = inp;
	endfunction
	assign req_y = y0_q + sv2v_cast_12(row_q);
	assign req_w = (c2_q ? 4'd3 : (chroma_q ? 4'd5 : 4'd9));
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
			c2_q <= 1'b0;
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
						c2_q <= c2x2;
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
				2'd2:
					if (start) begin
						chroma_q <= is_chroma;
						c2_q <= c2x2;
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
					else
						st_q <= 2'd0;
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
module cabac_mb (
	clk,
	rst_n,
	cfg_mb_w,
	cfg_mb_h,
	cfg_qp,
	cfg_is_p,
	cfg_init_idc,
	start,
	req_valid,
	req_bits,
	req_ready,
	show,
	avail,
	mb_valid,
	mb_x,
	mb_y,
	mb_i16,
	mb_cbp,
	mb_qp,
	mb_i16_mode,
	mb_cmode,
	mb_i4m,
	mb_skip,
	mb_inter,
	mb_ptype,
	mb_sub,
	mvd_valid,
	mvd_x,
	mvd_y,
	skip_go,
	mb_nz,
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
	input wire [1:0] cfg_init_idc;
	input wire start;
	output wire req_valid;
	output wire [4:0] req_bits;
	input wire req_ready;
	input wire [23:0] show;
	input wire [6:0] avail;
	output wire mb_valid;
	output wire [7:0] mb_x;
	output wire [7:0] mb_y;
	output wire mb_i16;
	output wire [5:0] mb_cbp;
	output wire [5:0] mb_qp;
	output wire [1:0] mb_i16_mode;
	output wire [1:0] mb_cmode;
	output reg [63:0] mb_i4m;
	output wire mb_skip;
	output wire mb_inter;
	output wire [2:0] mb_ptype;
	output wire [7:0] mb_sub;
	output wire mvd_valid;
	output wire signed [15:0] mvd_x;
	output wire signed [15:0] mvd_y;
	output wire skip_go;
	output wire [15:0] mb_nz;
	output reg coef_we;
	output reg [4:0] coef_blk;
	output reg [3:0] coef_addr;
	output reg signed [15:0] coef_data;
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
	reg ci_start;
	wire ci_busy;
	reg op_valid;
	wire op_ready;
	wire bin;
	reg [1:0] op;
	reg [8:0] op_ctx;
	cabac_core u_core(
		.clk(clk),
		.rst_n(rst_n),
		.req_valid(req_valid),
		.req_bits(req_bits),
		.req_ready(req_ready),
		.show(show),
		.avail(avail),
		.init_start(ci_start),
		.init_qp(cfg_qp),
		.init_model((cfg_is_p ? cfg_init_idc : 2'd3)),
		.init_busy(ci_busy),
		.op_valid(op_valid),
		.op(op),
		.op_ctx(op_ctx),
		.op_ready(op_ready),
		.bin(bin),
		.dbg_range(),
		.dbg_value()
	);
	wire step;
	assign step = op_valid && op_ready;
	reg [91:0] nrow [0:MAX_MBW - 1];
	reg [7:0] mbx_q;
	wire [91:0] nrow_rd = nrow[mbx_q];
	reg [91:0] nrow_q;
	reg l_valid;
	reg l_cat;
	reg l_cmode;
	reg [5:0] l_cbp;
	reg l_ldc;
	reg [1:0] l_cdc;
	reg [3:0] l_cbfl;
	reg [1:0] l_cbfc [0:1];
	reg [3:0] l_i4m [0:3];
	reg l_skip;
	reg [6:0] l_avx [0:3];
	reg [6:0] l_avy [0:3];
	reg [7:0] mby_q;
	reg i16_q;
	reg [1:0] i16m_q;
	reg [1:0] cmode_q;
	reg [5:0] cbp_q;
	reg [5:0] qp_q;
	reg [3:0] i4m_q [0:15];
	reg [15:0] cbfl_q;
	reg [3:0] cbfc_q [0:1];
	reg [1:0] cdc_q;
	reg ldc_q;
	reg lastqpd_q;
	reg skip_q;
	reg inter_q;
	reg [2:0] ptype_q;
	reg [7:0] sub_q;
	reg [1:0] pb_q;
	reg [1:0] ps_q;
	reg axis_q;
	reg [15:0] uegv_q;
	reg [2:0] uctx_q;
	reg [4:0] egk3_q;
	reg [15:0] egv3_q;
	reg signed [15:0] mvdx_q;
	reg signed [15:0] mvdy_q;
	reg mvdv_q;
	reg [6:0] cur_avx [0:15];
	reg [6:0] cur_avy [0:15];
	reg [15:0] av_w;
	wire have_left;
	wire have_top;
	assign have_left = mbx_q != 8'd0;
	assign have_top = mby_q != 8'd0;
	reg [4:0] st_q;
	reg [2:0] bcnt_q;
	reg [4:0] t_q;
	reg [3:0] k_q;
	reg [2:0] m_q;
	reg [6:0] uval_q;
	reg [1:0] rph_q;
	reg comp_q;
	reg [2:0] rcat;
	reg [4:0] rmax;
	reg [3:0] ridx [0:15];
	reg [4:0] rcnt_q;
	reg [4:0] rsig_q;
	reg [2:0] node_q;
	reg [4:0] abs_q;
	reg [4:0] egk_q;
	reg [15:0] egv_q;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (rph_q)
			2'd0: begin
				rcat = 3'd0;
				rmax = 5'd16;
			end
			2'd1: begin
				rcat = (i16_q ? 3'd1 : 3'd2);
				rmax = (i16_q ? 5'd15 : 5'd16);
			end
			2'd2: begin
				rcat = 3'd3;
				rmax = 5'd4;
			end
			default: begin
				rcat = 3'd4;
				rmax = 5'd15;
			end
		endcase
	end
	localparam [29:0] SIG_OFF = 30'h003ddb2f;
	localparam [29:0] LVL_OFF = 30'h002947a7;
	function automatic [3:0] l1ctx;
		input reg [2:0] n;
		(* full_case, parallel_case *)
		case (n)
			3'd0: l1ctx = 4'd1;
			3'd1: l1ctx = 4'd2;
			3'd2: l1ctx = 4'd3;
			3'd3: l1ctx = 4'd4;
			default: l1ctx = 4'd0;
		endcase
	endfunction
	function automatic [3:0] sv2v_cast_4;
		input reg [3:0] inp;
		sv2v_cast_4 = inp;
	endfunction
	function automatic [3:0] gt1ctx;
		input reg [2:0] n;
		gt1ctx = (n < 3'd4 ? 4'd5 : sv2v_cast_4(4'd2 + sv2v_cast_4(n)));
	endfunction
	function automatic [2:0] tr_eq1;
		input reg [2:0] n;
		(* full_case, parallel_case *)
		case (n)
			3'd0: tr_eq1 = 3'd1;
			3'd1: tr_eq1 = 3'd2;
			3'd2: tr_eq1 = 3'd3;
			3'd3: tr_eq1 = 3'd3;
			3'd4: tr_eq1 = 3'd4;
			3'd5: tr_eq1 = 3'd5;
			3'd6: tr_eq1 = 3'd6;
			default: tr_eq1 = 3'd7;
		endcase
	endfunction
	function automatic [2:0] tr_gt1;
		input reg [2:0] n;
		tr_gt1 = (n < 3'd4 ? 3'd4 : (n == 3'd7 ? 3'd7 : n + 3'd1));
	endfunction
	reg [2:0] g_bx0;
	reg [2:0] g_by0;
	reg [2:0] g_w4;
	reg [2:0] g_h4;
	reg [1:0] sub2;
	reg [2:0] nsub;
	function automatic [2:0] sv2v_cast_3;
		input reg [2:0] inp;
		sv2v_cast_3 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		sub2 = sub_q[{pb_q, 1'b0}+:2];
		nsub = (sub2 == 2'd0 ? 3'd1 : (sub2 == 2'd3 ? 3'd4 : 3'd2));
		g_bx0 = 1'sb0;
		g_by0 = 1'sb0;
		g_w4 = 3'd4;
		g_h4 = 3'd4;
		(* full_case, parallel_case *)
		case (ptype_q)
			3'd0:
				;
			3'd1: begin
				g_by0 = {1'b0, pb_q[0], 1'b0};
				g_h4 = 3'd2;
			end
			3'd2: begin
				g_bx0 = {1'b0, pb_q[0], 1'b0};
				g_w4 = 3'd2;
			end
			default: begin
				g_bx0 = {2'b00, pb_q[0]} << 1;
				g_by0 = {2'b00, pb_q[1]} << 1;
				(* full_case, parallel_case *)
				case (sub2)
					2'd0: begin
						g_w4 = 3'd2;
						g_h4 = 3'd2;
					end
					2'd1: begin
						g_w4 = 3'd2;
						g_h4 = 3'd1;
						g_by0 = g_by0 + sv2v_cast_3(ps_q[0]);
					end
					2'd2: begin
						g_w4 = 3'd1;
						g_h4 = 3'd2;
						g_bx0 = g_bx0 + sv2v_cast_3(ps_q[0]);
					end
					default: begin
						g_w4 = 3'd1;
						g_h4 = 3'd1;
						g_bx0 = g_bx0 + sv2v_cast_3(ps_q[0]);
						g_by0 = g_by0 + sv2v_cast_3(ps_q[1]);
					end
				endcase
			end
		endcase
	end
	reg [8:0] amvd;
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_1
		reg [6:0] aa;
		reg [6:0] bb;
		reg [1:0] bx;
		reg [1:0] by;
		if (_sv2v_0)
			;
		bx = g_bx0[1:0];
		by = g_by0[1:0];
		aa = 1'sb0;
		bb = 1'sb0;
		if (bx != 2'd0) begin
			if (av_w[{by, bx - 2'd1}])
				aa = (axis_q ? cur_avy[{by, bx - 2'd1}] : cur_avx[{by, bx - 2'd1}]);
		end
		else if (have_left)
			aa = (axis_q ? l_avy[by] : l_avx[by]);
		if (by != 2'd0) begin
			if (av_w[{by - 2'd1, bx}])
				bb = (axis_q ? cur_avy[{by - 2'd1, bx}] : cur_avx[{by - 2'd1, bx}]);
		end
		else if (have_top)
			bb = (axis_q ? nrow_q[(36 + (bx * 14)) + 7+:7] : nrow_q[36 + (bx * 14)+:7]);
		amvd = sv2v_cast_9(aa) + sv2v_cast_9(bb);
	end
	wire [1:0] mvd_inc;
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	assign mvd_inc = sv2v_cast_2(amvd > 9'd2) + sv2v_cast_2(amvd > 9'd32);
	reg cond_a;
	reg cond_b;
	always @(*) begin : sv2v_autoblock_2
		reg [1:0] bx;
		reg [1:0] by;
		if (_sv2v_0)
			;
		bx = zsx(k_q);
		by = zsy(k_q);
		cond_a = !inter_q;
		cond_b = !inter_q;
		(* full_case, parallel_case *)
		case (rph_q)
			2'd0: begin
				if (have_left)
					cond_a = (l_cat ? l_ldc : 1'b0);
				if (have_top)
					cond_b = (nrow_q[0] ? nrow_q[8] : 1'b0);
			end
			2'd1: begin
				if (bx != 2'd0)
					cond_a = cbfl_q[{by, bx - 2'd1}];
				else if (have_left)
					cond_a = l_cbfl[by];
				if (by != 2'd0)
					cond_b = cbfl_q[{by - 2'd1, bx}];
				else if (have_top)
					cond_b = nrow_q[11 + bx];
			end
			2'd2: begin
				if (have_left)
					cond_a = l_cdc[comp_q];
				if (have_top)
					cond_b = nrow_q[9 + comp_q];
			end
			default: begin
				if (k_q[0])
					cond_a = cbfc_q[comp_q][{k_q[1], 1'b0}];
				else if (have_left)
					cond_a = l_cbfc[comp_q][k_q[1]];
				if (k_q[1])
					cond_b = cbfc_q[comp_q][{1'b0, k_q[0]}];
				else if (have_top)
					cond_b = nrow_q[(15 + (comp_q * 2)) + k_q[0]];
			end
		endcase
	end
	reg [1:0] mbt_inc;
	reg [1:0] cmd_inc;
	reg [1:0] skp_inc;
	always @(*) begin
		if (_sv2v_0)
			;
		mbt_inc = sv2v_cast_2(have_left && l_cat) + sv2v_cast_2(have_top && nrow_q[0]);
		cmd_inc = sv2v_cast_2(have_left && l_cmode) + sv2v_cast_2(have_top && nrow_q[1]);
		skp_inc = sv2v_cast_2(have_left && !l_skip) + sv2v_cast_2(have_top && !nrow_q[35]);
	end
	wire [5:0] cbp_a;
	wire [5:0] cbp_b;
	assign cbp_a = (have_left ? l_cbp : 6'h0f);
	assign cbp_b = (have_top ? nrow_q[7:2] : 6'h0f);
	reg [1:0] cbp_ctx;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (bcnt_q)
			3'd0: cbp_ctx = sv2v_cast_2(!cbp_a[1]) + {!cbp_b[2], 1'b0};
			3'd1: cbp_ctx = sv2v_cast_2(!cbp_q[0]) + {!cbp_b[3], 1'b0};
			3'd2: cbp_ctx = sv2v_cast_2(!cbp_a[3]) + {!cbp_q[0], 1'b0};
			3'd3: cbp_ctx = sv2v_cast_2(!cbp_q[2]) + {!cbp_q[1], 1'b0};
			3'd4: cbp_ctx = sv2v_cast_2(cbp_a[5:4] != 2'd0) + {cbp_b[5:4] != 2'd0, 1'b0};
			default: cbp_ctx = sv2v_cast_2(cbp_a[5:4] == 2'd2) + {cbp_b[5:4] == 2'd2, 1'b0};
		endcase
	end
	reg [3:0] predA;
	reg [3:0] predB;
	reg availA;
	reg availB;
	always @(*) begin : sv2v_autoblock_3
		reg [1:0] bx;
		reg [1:0] by;
		if (_sv2v_0)
			;
		bx = zsx(k_q);
		by = zsy(k_q);
		availA = (bx != 0) || have_left;
		availB = (by != 0) || have_top;
		predA = (bx != 0 ? i4m_q[zidx(bx - 2'd1, by)] : l_i4m[by]);
		predB = (by != 0 ? i4m_q[zidx(bx, by - 2'd1)] : nrow_q[19 + (bx * 4)+:4]);
	end
	wire [3:0] i4_pred;
	assign i4_pred = (!availA || !availB ? 4'd2 : (predA < predB ? predA : predB));
	always @(*) begin
		if (_sv2v_0)
			;
		op_valid = 1'b0;
		op = 2'd0;
		op_ctx = 1'sb0;
		(* full_case, parallel_case *)
		case (st_q)
			5'd3: begin
				op_valid = 1'b1;
				(* full_case, parallel_case *)
				case (bcnt_q)
					3'd0: op_ctx = 9'd3 + sv2v_cast_9(mbt_inc);
					3'd1: op = 2'd2;
					3'd2: op_ctx = 9'd6;
					3'd3: op_ctx = 9'd7;
					3'd4: op_ctx = 9'd8;
					3'd5: op_ctx = 9'd9;
					default: op_ctx = 9'd10;
				endcase
			end
			5'd21: begin
				op_valid = 1'b1;
				op_ctx = 9'd11 + sv2v_cast_9(skp_inc);
			end
			5'd22: begin
				op_valid = 1'b1;
				(* full_case, parallel_case *)
				case (bcnt_q)
					3'd0: op_ctx = 9'd14;
					3'd1: op_ctx = 9'd15;
					3'd2: op_ctx = 9'd16;
					default: op_ctx = 9'd17;
				endcase
			end
			5'd23: begin
				op_valid = 1'b1;
				(* full_case, parallel_case *)
				case (bcnt_q)
					3'd0: op_ctx = 9'd17;
					3'd1: op = 2'd2;
					3'd2: op_ctx = 9'd18;
					3'd3: op_ctx = 9'd19;
					3'd4: op_ctx = 9'd19;
					3'd5: op_ctx = 9'd20;
					default: op_ctx = 9'd20;
				endcase
			end
			5'd24: begin
				op_valid = 1'b1;
				op_ctx = (bcnt_q == 3'd0 ? 9'd21 : (bcnt_q == 3'd1 ? 9'd22 : 9'd23));
			end
			5'd25: begin
				op_valid = 1'b1;
				op_ctx = (axis_q ? 9'd47 : 9'd40) + sv2v_cast_9(mvd_inc);
			end
			5'd26: begin
				op_valid = 1'b1;
				op_ctx = ((axis_q ? 9'd47 : 9'd40) + 9'd3) + sv2v_cast_9(uctx_q);
			end
			5'd27, 5'd28, 5'd29: begin
				op_valid = 1'b1;
				op = 2'd1;
			end
			5'd4: begin
				op_valid = 1'b1;
				op_ctx = (bcnt_q == 3'd0 ? 9'd68 : 9'd69);
			end
			5'd5: begin
				op_valid = 1'b1;
				op_ctx = (bcnt_q == 3'd0 ? 9'd64 + sv2v_cast_9(cmd_inc) : 9'd67);
			end
			5'd6: begin
				op_valid = 1'b1;
				op_ctx = (bcnt_q < 3'd4 ? 9'd73 + sv2v_cast_9(cbp_ctx) : (bcnt_q == 3'd4 ? 9'd77 + sv2v_cast_9(cbp_ctx) : 9'd81 + sv2v_cast_9(cbp_ctx)));
			end
			5'd7: begin
				op_valid = 1'b1;
				op_ctx = (bcnt_q == 3'd0 ? (lastqpd_q ? 9'd61 : 9'd60) : (bcnt_q == 3'd1 ? 9'd62 : 9'd63));
			end
			5'd9: begin
				op_valid = 1'b1;
				op_ctx = ((9'd85 + (sv2v_cast_9(rcat) * 4)) + sv2v_cast_9(cond_a)) + (sv2v_cast_9(cond_b) * 2);
			end
			5'd10: begin
				op_valid = 1'b1;
				op_ctx = (9'd105 + sv2v_cast_9(SIG_OFF[(4 - rcat) * 6+:6])) + sv2v_cast_9(rsig_q);
			end
			5'd11: begin
				op_valid = 1'b1;
				op_ctx = (9'd166 + sv2v_cast_9(SIG_OFF[(4 - rcat) * 6+:6])) + sv2v_cast_9(rsig_q);
			end
			5'd12: begin
				op_valid = 1'b1;
				op_ctx = (9'd227 + sv2v_cast_9(LVL_OFF[(4 - rcat) * 6+:6])) + sv2v_cast_9(l1ctx(node_q));
			end
			5'd13: begin
				op_valid = 1'b1;
				op_ctx = (9'd227 + sv2v_cast_9(LVL_OFF[(4 - rcat) * 6+:6])) + sv2v_cast_9(gt1ctx(node_q));
			end
			5'd14, 5'd15, 5'd16: begin
				op_valid = 1'b1;
				op = 2'd1;
			end
			5'd17: begin
				op_valid = 1'b1;
				op = 2'd2;
			end
			default:
				;
		endcase
	end
	wire [3:0] wpos;
	assign wpos = ridx[rcnt_q - 5'd1];
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
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		coef_we = (st_q == 5'd16) && step;
		(* full_case, parallel_case *)
		case (rph_q)
			2'd0: begin
				coef_blk = 5'd16;
				coef_addr = zz4(wpos);
			end
			2'd1: begin
				coef_blk = sv2v_cast_5(k_q);
				coef_addr = (i16_q ? zz4(wpos + 4'd1) : zz4(wpos));
			end
			2'd2: begin
				coef_blk = 5'd17 + sv2v_cast_5(comp_q);
				coef_addr = wpos;
			end
			default: begin
				coef_blk = (5'd19 + (sv2v_cast_5(comp_q) * 4)) + sv2v_cast_5(k_q);
				coef_addr = zz4(wpos + 4'd1);
			end
		endcase
		coef_data = (bin ? -sv2v_cast_16(abs_q) : sv2v_cast_16(abs_q));
		if (((st_q == 5'd16) && (abs_q == 5'd15)) && (egv_q != 16'd0))
			coef_data = (bin ? -(egv_q + 16'd14) : egv_q + 16'd14);
	end
	assign mb_x = mbx_q;
	assign mb_y = mby_q;
	assign mb_i16 = i16_q;
	assign mb_cbp = cbp_q;
	assign mb_qp = qp_q;
	assign mb_i16_mode = i16m_q;
	assign mb_cmode = cmode_q;
	always @(*) begin : sv2v_autoblock_4
		reg signed [31:0] i;
		if (_sv2v_0)
			;
		for (i = 0; i < 16; i = i + 1)
			mb_i4m[i * 4+:4] = i4m_q[i];
	end
	assign mb_valid = st_q == 5'd18;
	assign slice_done = st_q == 5'd19;
	assign err = st_q == 5'd20;
	assign mb_skip = skip_q;
	assign mb_inter = inter_q;
	assign mb_ptype = ptype_q;
	assign mb_sub = sub_q;
	assign mvd_valid = mvdv_q;
	assign mvd_x = mvdx_q;
	assign mvd_y = mvdy_q;
	assign mb_nz = cbfl_q;
	reg skipgo_q;
	assign skip_go = skipgo_q;
	wire [4:0] eff;
	assign eff = t_q - 5'd1;
	task automatic adv_block;
		(* full_case, parallel_case *)
		case (rph_q)
			2'd0: begin
				rph_q <= 2'd1;
				k_q <= 1'sb0;
				st_q <= 5'd8;
			end
			2'd1:
				if (k_q == 4'd15) begin
					rph_q <= 2'd2;
					comp_q <= 1'b0;
					st_q <= 5'd8;
				end
				else begin
					k_q <= k_q + 4'd1;
					st_q <= 5'd8;
				end
			2'd2:
				if (!comp_q) begin
					comp_q <= 1'b1;
					st_q <= 5'd8;
				end
				else begin
					rph_q <= 2'd3;
					comp_q <= 1'b0;
					k_q <= 1'sb0;
					st_q <= 5'd8;
				end
			default:
				if ((k_q == 4'd3) && comp_q)
					st_q <= 5'd17;
				else if (k_q == 4'd3) begin
					comp_q <= 1'b1;
					k_q <= 1'sb0;
					st_q <= 5'd8;
				end
				else begin
					k_q <= k_q + 4'd1;
					st_q <= 5'd8;
				end
		endcase
	endtask
	reg [6:0] avxc_q;
	function automatic [1:0] chroma_part;
		input reg [4:0] e;
		reg [4:0] r;
		begin
			r = (e >= 5'd12 ? e - 5'd12 : e);
			chroma_part = (r < 5'd4 ? 2'd0 : (r < 5'd8 ? 2'd1 : 2'd2));
		end
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	task automatic finish_comp;
		input reg signed [15:0] v;
		input reg [6:0] vclip;
		if (!axis_q) begin
			mvdx_q <= v;
			avxc_q <= vclip;
			axis_q <= 1'b1;
			st_q <= 5'd25;
		end
		else begin
			mvdy_q <= v;
			mvdv_q <= 1'b1;
			begin : sv2v_autoblock_5
				reg signed [31:0] j;
				for (j = 0; j < 4; j = j + 1)
					begin : sv2v_autoblock_6
						reg signed [31:0] i;
						for (i = 0; i < 4; i = i + 1)
							if ((((i >= sv2v_cast_32_signed(g_bx0)) && (i < (sv2v_cast_32_signed(g_bx0) + sv2v_cast_32_signed(g_w4)))) && (j >= sv2v_cast_32_signed(g_by0))) && (j < (sv2v_cast_32_signed(g_by0) + sv2v_cast_32_signed(g_h4)))) begin
								cur_avx[(j * 4) + i] <= avxc_q;
								cur_avy[(j * 4) + i] <= vclip;
								av_w[(j * 4) + i] <= 1'b1;
							end
					end
			end
			axis_q <= 1'b0;
			if (ptype_q == 3'd0)
				st_q <= 5'd6;
			else if ((ptype_q == 3'd1) || (ptype_q == 3'd2)) begin
				if (pb_q[0])
					st_q <= 5'd6;
				else begin
					pb_q <= 2'd1;
					st_q <= 5'd25;
				end
			end
			else if ((sv2v_cast_3(ps_q) + 3'd1) == nsub) begin
				if (pb_q == 2'd3)
					st_q <= 5'd6;
				else begin
					pb_q <= pb_q + 2'd1;
					ps_q <= 1'sb0;
					st_q <= 5'd25;
				end
			end
			else begin
				ps_q <= ps_q + 2'd1;
				st_q <= 5'd25;
			end
		end
	endtask
	function automatic [3:0] luma_part;
		input reg [4:0] e;
		luma_part = (e >= 5'd12 ? 4'hf : 4'h0);
	endfunction
	task automatic set_cbf;
		(* full_case, parallel_case *)
		case (rph_q)
			2'd0: ldc_q <= 1'b1;
			2'd1: cbfl_q[{zsy(k_q), zsx(k_q)}] <= 1'b1;
			2'd2: cdc_q[comp_q] <= 1'b1;
			default: cbfc_q[comp_q][{k_q[1], k_q[0]}] <= 1'b1;
		endcase
	endtask
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	function automatic signed [12:0] sv2v_cast_13_signed;
		input reg signed [12:0] inp;
		sv2v_cast_13_signed = inp;
	endfunction
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 5'd0;
			ci_start <= 1'b0;
			mbx_q <= 1'sb0;
			mby_q <= 1'sb0;
			qp_q <= 1'sb0;
			lastqpd_q <= 1'b0;
			l_valid <= 1'b0;
			bcnt_q <= 1'sb0;
			t_q <= 1'sb0;
			k_q <= 1'sb0;
			m_q <= 1'sb0;
			rph_q <= 1'sb0;
			comp_q <= 1'b0;
			rcnt_q <= 1'sb0;
			rsig_q <= 1'sb0;
			node_q <= 1'sb0;
			abs_q <= 1'sb0;
			egk_q <= 1'sb0;
			egv_q <= 1'sb0;
			uval_q <= 1'sb0;
			i16_q <= 1'b0;
			i16m_q <= 1'sb0;
			cmode_q <= 1'sb0;
			cbp_q <= 1'sb0;
			cbfl_q <= 1'sb0;
			cdc_q <= 1'sb0;
			ldc_q <= 1'b0;
			l_cat <= 1'b0;
			l_cmode <= 1'b0;
			l_cbp <= 1'sb0;
			l_ldc <= 1'b0;
			l_cdc <= 1'sb0;
			l_cbfl <= 1'sb0;
			nrow_q <= 1'sb0;
			skip_q <= 1'b0;
			inter_q <= 1'b0;
			ptype_q <= 1'sb0;
			sub_q <= 1'sb0;
			pb_q <= 1'sb0;
			ps_q <= 1'sb0;
			axis_q <= 1'b0;
			uegv_q <= 1'sb0;
			uctx_q <= 1'sb0;
			egk3_q <= 1'sb0;
			egv3_q <= 1'sb0;
			mvdx_q <= 1'sb0;
			mvdy_q <= 1'sb0;
			mvdv_q <= 1'b0;
			av_w <= 1'sb0;
			avxc_q <= 1'sb0;
			skipgo_q <= 1'b0;
			l_skip <= 1'b0;
		end
		else begin
			ci_start <= 1'b0;
			mvdv_q <= 1'b0;
			skipgo_q <= 1'b0;
			(* full_case, parallel_case *)
			case (st_q)
				5'd0:
					if (start) begin
						mbx_q <= 1'sb0;
						mby_q <= 1'sb0;
						qp_q <= cfg_qp;
						lastqpd_q <= 1'b0;
						l_valid <= 1'b0;
						ci_start <= 1'b1;
						st_q <= 5'd1;
					end
				5'd1:
					if (!ci_start && !ci_busy)
						st_q <= 5'd2;
				5'd2: begin
					nrow_q <= nrow_rd;
					begin : sv2v_autoblock_7
						reg signed [31:0] k;
						for (k = 0; k < 16; k = k + 1)
							i4m_q[k] <= 4'd2;
					end
					cbfl_q <= 1'sb0;
					cbfc_q[0] <= 1'sb0;
					cbfc_q[1] <= 1'sb0;
					cdc_q <= 1'sb0;
					ldc_q <= 1'b0;
					cmode_q <= 1'sb0;
					cbp_q <= 1'sb0;
					i16_q <= 1'b0;
					i16m_q <= 1'sb0;
					t_q <= 1'sb0;
					bcnt_q <= 1'sb0;
					k_q <= 1'sb0;
					skip_q <= 1'b0;
					inter_q <= 1'b0;
					ptype_q <= 1'sb0;
					sub_q <= 1'sb0;
					pb_q <= 1'sb0;
					ps_q <= 1'sb0;
					axis_q <= 1'b0;
					av_w <= 1'sb0;
					begin : sv2v_autoblock_8
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							begin
								cur_avx[i] <= 1'sb0;
								cur_avy[i] <= 1'sb0;
							end
					end
					st_q <= (cfg_is_p ? 5'd21 : 5'd3);
				end
				5'd21:
					if (step) begin
						if (bin) begin
							skip_q <= 1'b1;
							inter_q <= 1'b1;
							cbp_q <= 1'sb0;
							lastqpd_q <= 1'b0;
							skipgo_q <= 1'b1;
							st_q <= 5'd17;
						end
						else
							st_q <= 5'd22;
					end
				5'd22:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (bin) begin
									bcnt_q <= 1'sb0;
									st_q <= 5'd23;
								end
								else begin
									inter_q <= 1'b1;
									bcnt_q <= 3'd1;
								end
							3'd1: bcnt_q <= (bin ? 3'd3 : 3'd2);
							3'd2: begin
								ptype_q <= (bin ? 3'd3 : 3'd0);
								bcnt_q <= 1'sb0;
								pb_q <= 1'sb0;
								ps_q <= 1'sb0;
								axis_q <= 1'b0;
								st_q <= (bin ? 5'd24 : 5'd25);
							end
							default: begin
								ptype_q <= (bin ? 3'd1 : 3'd2);
								bcnt_q <= 1'sb0;
								pb_q <= 1'sb0;
								ps_q <= 1'sb0;
								axis_q <= 1'b0;
								st_q <= 5'd25;
							end
						endcase
				5'd23:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (!bin) begin
									k_q <= 1'sb0;
									bcnt_q <= 1'sb0;
									st_q <= 5'd4;
								end
								else begin
									t_q <= 5'd1;
									bcnt_q <= 3'd1;
								end
							3'd1:
								if (bin)
									st_q <= 5'd20;
								else
									bcnt_q <= 3'd2;
							3'd2: begin
								if (bin)
									t_q <= t_q + 5'd12;
								bcnt_q <= 3'd3;
							end
							3'd3: bcnt_q <= (bin ? 3'd4 : 3'd5);
							3'd4: begin
								t_q <= t_q + (bin ? 5'd8 : 5'd4);
								bcnt_q <= 3'd5;
							end
							3'd5: begin
								if (bin)
									t_q <= t_q + 5'd2;
								bcnt_q <= 3'd6;
							end
							default: begin
								i16_q <= 1'b1;
								st_q <= 5'd5;
								bcnt_q <= 1'sb0;
								if (bin)
									t_q <= t_q + 5'd1;
							end
						endcase
				5'd24:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (bin) begin
									sub_q[{pb_q, 1'b0}+:2] <= 2'd0;
									if (pb_q == 2'd3) begin
										pb_q <= 1'sb0;
										ps_q <= 1'sb0;
										axis_q <= 1'b0;
										st_q <= 5'd25;
									end
									else
										pb_q <= pb_q + 2'd1;
								end
								else
									bcnt_q <= 3'd1;
							3'd1:
								if (!bin) begin
									sub_q[{pb_q, 1'b0}+:2] <= 2'd1;
									bcnt_q <= 1'sb0;
									if (pb_q == 2'd3) begin
										pb_q <= 1'sb0;
										ps_q <= 1'sb0;
										axis_q <= 1'b0;
										st_q <= 5'd25;
									end
									else
										pb_q <= pb_q + 2'd1;
								end
								else
									bcnt_q <= 3'd2;
							default: begin
								sub_q[{pb_q, 1'b0}+:2] <= (bin ? 2'd2 : 2'd3);
								bcnt_q <= 1'sb0;
								if (pb_q == 2'd3) begin
									pb_q <= 1'sb0;
									ps_q <= 1'sb0;
									axis_q <= 1'b0;
									st_q <= 5'd25;
								end
								else
									pb_q <= pb_q + 2'd1;
							end
						endcase
				5'd25:
					if (step) begin
						if (!bin)
							finish_comp(16'd0, 7'd0);
						else begin
							uegv_q <= 16'd1;
							uctx_q <= 1'sb0;
							st_q <= 5'd26;
						end
					end
				5'd26:
					if (step) begin
						if (bin) begin
							if (uegv_q == 16'd8) begin
								uegv_q <= 16'd9;
								egk3_q <= 5'd3;
								st_q <= 5'd27;
							end
							else begin
								if (uegv_q < 16'd4)
									uctx_q <= uctx_q + 3'd1;
								uegv_q <= uegv_q + 16'd1;
							end
						end
						else
							st_q <= 5'd29;
					end
				5'd27:
					if (step) begin
						if (bin) begin
							uegv_q <= uegv_q + (16'd1 << egk3_q);
							egk3_q <= egk3_q + 5'd1;
							if (egk3_q > 5'd24)
								st_q <= 5'd20;
						end
						else if (egk3_q == 5'd0)
							st_q <= 5'd29;
						else
							st_q <= 5'd28;
					end
				5'd28:
					if (step) begin
						uegv_q <= uegv_q + (sv2v_cast_16(bin) << (egk3_q - 5'd1));
						if (egk3_q == 5'd1)
							st_q <= 5'd29;
						else
							egk3_q <= egk3_q - 5'd1;
					end
				5'd29:
					if (step)
						finish_comp((bin ? -uegv_q : uegv_q), (uegv_q < 16'd70 ? uegv_q[6:0] : 7'd70));
				5'd3:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (!bin) begin
									k_q <= 1'sb0;
									bcnt_q <= 1'sb0;
									st_q <= 5'd4;
								end
								else begin
									t_q <= 5'd1;
									bcnt_q <= 3'd1;
								end
							3'd1:
								if (bin)
									st_q <= 5'd20;
								else
									bcnt_q <= 3'd2;
							3'd2: begin
								if (bin)
									t_q <= t_q + 5'd12;
								bcnt_q <= 3'd3;
							end
							3'd3: bcnt_q <= (bin ? 3'd4 : 3'd5);
							3'd4: begin
								t_q <= t_q + (bin ? 5'd8 : 5'd4);
								bcnt_q <= 3'd5;
							end
							3'd5: begin
								if (bin)
									t_q <= t_q + 5'd2;
								bcnt_q <= 3'd6;
							end
							default: begin
								i16_q <= 1'b1;
								st_q <= 5'd5;
								bcnt_q <= 1'sb0;
								if (bin)
									t_q <= t_q + 5'd1;
							end
						endcase
				5'd4:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (bin) begin
									i4m_q[k_q] <= i4_pred;
									if (k_q == 4'd15) begin
										bcnt_q <= 1'sb0;
										st_q <= 5'd5;
									end
									else
										k_q <= k_q + 4'd1;
								end
								else begin
									m_q <= 1'sb0;
									bcnt_q <= 3'd1;
								end
							3'd1: begin
								m_q[0] <= bin;
								bcnt_q <= 3'd2;
							end
							3'd2: begin
								m_q[1] <= bin;
								bcnt_q <= 3'd3;
							end
							default: begin : sv2v_autoblock_9
								reg [3:0] m;
								m = {1'b0, bin, m_q[1], m_q[0]};
								i4m_q[k_q] <= m + sv2v_cast_4({1'b0, m} >= {1'b0, i4_pred});
								bcnt_q <= 1'sb0;
								if (k_q == 4'd15)
									st_q <= 5'd5;
								else
									k_q <= k_q + 4'd1;
							end
						endcase
				5'd5:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (!bin) begin
									cmode_q <= 2'd0;
									st_q <= (i16_q ? 5'd7 : 5'd6);
									bcnt_q <= 1'sb0;
									if (i16_q) begin
										i16m_q <= eff[1:0];
										cbp_q <= {chroma_part(eff), luma_part(eff)};
									end
								end
								else
									bcnt_q <= 3'd1;
							3'd1:
								if (!bin) begin
									cmode_q <= 2'd1;
									st_q <= (i16_q ? 5'd7 : 5'd6);
									bcnt_q <= 1'sb0;
									if (i16_q) begin
										i16m_q <= eff[1:0];
										cbp_q <= {chroma_part(eff), luma_part(eff)};
									end
								end
								else
									bcnt_q <= 3'd2;
							default: begin
								cmode_q <= (bin ? 2'd3 : 2'd2);
								st_q <= (i16_q ? 5'd7 : 5'd6);
								bcnt_q <= 1'sb0;
								if (i16_q) begin
									i16m_q <= eff[1:0];
									cbp_q <= {chroma_part(eff), luma_part(eff)};
								end
							end
						endcase
				5'd6:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0, 3'd1, 3'd2, 3'd3: begin
								cbp_q[sv2v_cast_2(bcnt_q)] <= bin;
								bcnt_q <= bcnt_q + 3'd1;
							end
							3'd4:
								if (!bin) begin
									bcnt_q <= 1'sb0;
									if (cbp_q[3:0] != 4'd0)
										st_q <= 5'd7;
									else begin
										lastqpd_q <= 1'b0;
										rph_q <= 2'd1;
										k_q <= 1'sb0;
										comp_q <= 1'b0;
										st_q <= 5'd8;
									end
								end
								else
									bcnt_q <= 3'd5;
							default: begin
								cbp_q[5:4] <= (bin ? 2'd2 : 2'd1);
								bcnt_q <= 1'sb0;
								st_q <= 5'd7;
							end
						endcase
				5'd7:
					if (step)
						(* full_case, parallel_case *)
						case (bcnt_q)
							3'd0:
								if (!bin) begin
									lastqpd_q <= 1'b0;
									st_q <= 5'd8;
									rph_q <= (i16_q ? 2'd0 : 2'd1);
									k_q <= 1'sb0;
									comp_q <= 1'b0;
								end
								else begin
									uval_q <= 7'd1;
									bcnt_q <= 3'd1;
								end
							default:
								if (bin) begin
									uval_q <= uval_q + 7'd1;
									bcnt_q <= 3'd2;
									if (uval_q > 7'd104)
										st_q <= 5'd20;
								end
								else begin : sv2v_autoblock_10
									reg signed [7:0] d;
									d = (uval_q[0] ? sv2v_cast_8(({1'b0, uval_q} + 8'd1) >> 1) : -sv2v_cast_8(({1'b0, uval_q} + 8'd1) >> 1));
									if ((d < -26) || (d > 25))
										st_q <= 5'd20;
									else begin
										qp_q <= sv2v_cast_6(((sv2v_cast_13_signed($signed({1'b0, qp_q})) + sv2v_cast_13_signed(d)) + 13'd52) % 13'd52);
										lastqpd_q <= 1'b1;
										st_q <= 5'd8;
										rph_q <= (i16_q ? 2'd0 : 2'd1);
										k_q <= 1'sb0;
										comp_q <= 1'b0;
									end
								end
						endcase
				5'd8: begin : sv2v_autoblock_11
					reg skip_blk;
					skip_blk = 1'b0;
					(* full_case, parallel_case *)
					case (rph_q)
						2'd0:
							;
						2'd1: skip_blk = !cbp_q[{k_q[3], k_q[2]}];
						2'd2: skip_blk = cbp_q[5:4] == 2'd0;
						default: skip_blk = cbp_q[5:4] != 2'd2;
					endcase
					if (skip_blk)
						adv_block;
					else begin
						rsig_q <= 1'sb0;
						rcnt_q <= 1'sb0;
						node_q <= 1'sb0;
						st_q <= 5'd9;
					end
				end
				5'd9:
					if (step) begin
						if (!bin)
							adv_block;
						else begin
							set_cbf;
							st_q <= (rmax == 5'd1 ? 5'd12 : 5'd10);
							if (rmax == 5'd1) begin
								ridx[0] <= 1'sb0;
								rcnt_q <= 5'd1;
							end
						end
					end
				5'd10:
					if (step) begin
						if (bin) begin
							ridx[rcnt_q[3:0]] <= sv2v_cast_4(rsig_q);
							rcnt_q <= rcnt_q + 5'd1;
							st_q <= 5'd11;
						end
						else if (rsig_q == (rmax - 5'd2)) begin
							ridx[rcnt_q[3:0]] <= sv2v_cast_4(rmax - 5'd1);
							rcnt_q <= rcnt_q + 5'd1;
							st_q <= 5'd12;
						end
						else
							rsig_q <= rsig_q + 5'd1;
					end
				5'd11:
					if (step) begin
						if (bin)
							st_q <= 5'd12;
						else if (rsig_q == (rmax - 5'd2)) begin
							ridx[rcnt_q[3:0]] <= sv2v_cast_4(rmax - 5'd1);
							rcnt_q <= rcnt_q + 5'd1;
							st_q <= 5'd12;
						end
						else begin
							rsig_q <= rsig_q + 5'd1;
							st_q <= 5'd10;
						end
					end
				5'd12:
					if (step) begin
						egv_q <= 1'sb0;
						if (!bin) begin
							abs_q <= 5'd1;
							node_q <= tr_eq1(node_q);
							st_q <= 5'd16;
						end
						else begin
							abs_q <= 5'd2;
							st_q <= 5'd13;
						end
					end
				5'd13:
					if (step) begin
						if (bin) begin
							if (abs_q == 5'd14) begin
								abs_q <= 5'd15;
								egk_q <= 1'sb0;
								node_q <= tr_gt1(node_q);
								st_q <= 5'd14;
							end
							else
								abs_q <= abs_q + 5'd1;
						end
						else begin
							node_q <= tr_gt1(node_q);
							st_q <= 5'd16;
						end
					end
				5'd14:
					if (step) begin
						if (bin && (egk_q < 5'd23))
							egk_q <= egk_q + 5'd1;
						else begin
							egv_q <= 16'd1;
							if (egk_q == 5'd0)
								st_q <= 5'd16;
							else
								st_q <= 5'd15;
						end
					end
				5'd15:
					if (step) begin
						egv_q <= {egv_q[14:0], bin};
						if (egk_q == 5'd1)
							st_q <= 5'd16;
						else
							egk_q <= egk_q - 5'd1;
					end
				5'd16:
					if (step) begin
						rcnt_q <= rcnt_q - 5'd1;
						if (rcnt_q == 5'd1)
							adv_block;
						else
							st_q <= 5'd12;
					end
				5'd17:
					if (step) begin
						if (bin && !((mbx_q == (cfg_mb_w - 8'd1)) && (mby_q == (cfg_mb_h - 8'd1))))
							st_q <= 5'd20;
						else if (!bin && ((mbx_q == (cfg_mb_w - 8'd1)) && (mby_q == (cfg_mb_h - 8'd1))))
							st_q <= 5'd20;
						else
							st_q <= 5'd18;
					end
				5'd18:
					if (rec_done) begin
						l_valid <= 1'b1;
						l_cat <= i16_q;
						l_cmode <= cmode_q != 2'd0;
						l_cbp <= cbp_q;
						l_ldc <= ldc_q;
						l_cdc <= cdc_q;
						begin : sv2v_autoblock_12
							reg signed [31:0] j;
							for (j = 0; j < 4; j = j + 1)
								begin
									l_cbfl[j] <= cbfl_q[{sv2v_cast_2_signed(j), 2'd3}];
									l_i4m[j] <= i4m_q[zidx(2'd3, sv2v_cast_2_signed(j))];
								end
						end
						l_cbfc[0] <= {cbfc_q[0][3], cbfc_q[0][1]};
						l_cbfc[1] <= {cbfc_q[1][3], cbfc_q[1][1]};
						l_skip <= skip_q;
						begin : sv2v_autoblock_13
							reg signed [31:0] j;
							for (j = 0; j < 4; j = j + 1)
								begin
									l_avx[j] <= cur_avx[(j * 4) + 3];
									l_avy[j] <= cur_avy[(j * 4) + 3];
								end
						end
						nrow[mbx_q] <= {cur_avy[15], cur_avx[15], cur_avy[14], cur_avx[14], cur_avy[13], cur_avx[13], cur_avy[12], cur_avx[12], skip_q, i4m_q[zidx(2'd3, 2'd3)], i4m_q[zidx(2'd2, 2'd3)], i4m_q[zidx(2'd1, 2'd3)], i4m_q[zidx(2'd0, 2'd3)], cbfc_q[1][3:2], cbfc_q[0][3:2], cbfl_q[15:12], cdc_q, ldc_q, cbp_q, cmode_q != 2'd0, i16_q};
						if ((mbx_q == (cfg_mb_w - 8'd1)) && (mby_q == (cfg_mb_h - 8'd1)))
							st_q <= 5'd19;
						else begin
							if (mbx_q == (cfg_mb_w - 8'd1)) begin
								mbx_q <= 1'sb0;
								mby_q <= mby_q + 8'd1;
								l_valid <= 1'b0;
							end
							else
								mbx_q <= mbx_q + 8'd1;
							st_q <= 5'd2;
						end
					end
				5'd19: st_q <= 5'd19;
				5'd20: st_q <= 5'd20;
				default: st_q <= 5'd20;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
module cabac_core (
	clk,
	rst_n,
	req_valid,
	req_bits,
	req_ready,
	show,
	avail,
	init_start,
	init_qp,
	init_model,
	init_busy,
	op_valid,
	op,
	op_ctx,
	op_ready,
	bin,
	dbg_range,
	dbg_value
);
	reg _sv2v_0;
	input wire clk;
	input wire rst_n;
	output reg req_valid;
	output reg [4:0] req_bits;
	input wire req_ready;
	input wire [23:0] show;
	input wire [6:0] avail;
	input wire init_start;
	input wire [5:0] init_qp;
	input wire [1:0] init_model;
	output wire init_busy;
	input wire op_valid;
	input wire [1:0] op;
	input wire [8:0] op_ctx;
	output wire op_ready;
	output reg bin;
	output wire [8:0] dbg_range;
	output wire [8:0] dbg_value;
	reg [8:0] range_q;
	reg [8:0] value_q;
	reg [5:0] pstate [0:435];
	reg [435:0] mps;
	reg [1:0] st_q;
	reg [8:0] ictx_q;
	reg [1:0] model_q;
	assign init_busy = st_q != 2'd0;
	assign dbg_range = range_q;
	assign dbg_value = value_q;
	wire [15:0] mn;
	reg signed [15:0] pre_raw;
	reg [6:0] pre;
	function automatic [15:0] cabac_init_mn;
		input reg [1:0] model;
		input reg [8:0] ctx;
		reg [10:0] key;
		begin
			key = {model, ctx};
			(* full_case, parallel_case *)
			case (key)
				11'd0: cabac_init_mn = 16'h14f1;
				11'd1: cabac_init_mn = 16'h0236;
				11'd2: cabac_init_mn = 16'h034a;
				11'd3: cabac_init_mn = 16'h14f1;
				11'd4: cabac_init_mn = 16'h0236;
				11'd5: cabac_init_mn = 16'h034a;
				11'd6: cabac_init_mn = 16'he47f;
				11'd7: cabac_init_mn = 16'he968;
				11'd8: cabac_init_mn = 16'hfa35;
				11'd9: cabac_init_mn = 16'hff36;
				11'd10: cabac_init_mn = 16'h0733;
				11'd11: cabac_init_mn = 16'h1721;
				11'd12: cabac_init_mn = 16'h1702;
				11'd13: cabac_init_mn = 16'h1500;
				11'd14: cabac_init_mn = 16'h0109;
				11'd15: cabac_init_mn = 16'h0031;
				11'd16: cabac_init_mn = 16'hdb76;
				11'd17: cabac_init_mn = 16'h0539;
				11'd18: cabac_init_mn = 16'hf34e;
				11'd19: cabac_init_mn = 16'hf541;
				11'd20: cabac_init_mn = 16'h013e;
				11'd21: cabac_init_mn = 16'h0c31;
				11'd22: cabac_init_mn = 16'hfc49;
				11'd23: cabac_init_mn = 16'h1132;
				11'd24: cabac_init_mn = 16'h1240;
				11'd25: cabac_init_mn = 16'h092b;
				11'd26: cabac_init_mn = 16'h1d00;
				11'd27: cabac_init_mn = 16'h1a43;
				11'd28: cabac_init_mn = 16'h105a;
				11'd29: cabac_init_mn = 16'h0968;
				11'd30: cabac_init_mn = 16'hd27f;
				11'd31: cabac_init_mn = 16'hec68;
				11'd32: cabac_init_mn = 16'h0143;
				11'd33: cabac_init_mn = 16'hf34e;
				11'd34: cabac_init_mn = 16'hf541;
				11'd35: cabac_init_mn = 16'h013e;
				11'd36: cabac_init_mn = 16'hfa56;
				11'd37: cabac_init_mn = 16'hef5f;
				11'd38: cabac_init_mn = 16'hfa3d;
				11'd39: cabac_init_mn = 16'h092d;
				11'd40: cabac_init_mn = 16'hfd45;
				11'd41: cabac_init_mn = 16'hfa51;
				11'd42: cabac_init_mn = 16'hf560;
				11'd43: cabac_init_mn = 16'h0637;
				11'd44: cabac_init_mn = 16'h0743;
				11'd45: cabac_init_mn = 16'hfb56;
				11'd46: cabac_init_mn = 16'h0258;
				11'd47: cabac_init_mn = 16'h003a;
				11'd48: cabac_init_mn = 16'hfd4c;
				11'd49: cabac_init_mn = 16'hf65e;
				11'd50: cabac_init_mn = 16'h0536;
				11'd51: cabac_init_mn = 16'h0445;
				11'd52: cabac_init_mn = 16'hfd51;
				11'd53: cabac_init_mn = 16'h0058;
				11'd54: cabac_init_mn = 16'hf943;
				11'd55: cabac_init_mn = 16'hfb4a;
				11'd56: cabac_init_mn = 16'hfc4a;
				11'd57: cabac_init_mn = 16'hfb50;
				11'd58: cabac_init_mn = 16'hf948;
				11'd59: cabac_init_mn = 16'h013a;
				11'd60: cabac_init_mn = 16'h0029;
				11'd61: cabac_init_mn = 16'h003f;
				11'd62: cabac_init_mn = 16'h003f;
				11'd63: cabac_init_mn = 16'h003f;
				11'd64: cabac_init_mn = 16'hf753;
				11'd65: cabac_init_mn = 16'h0456;
				11'd66: cabac_init_mn = 16'h0061;
				11'd67: cabac_init_mn = 16'hf948;
				11'd68: cabac_init_mn = 16'h0d29;
				11'd69: cabac_init_mn = 16'h033e;
				11'd70: cabac_init_mn = 16'h002d;
				11'd71: cabac_init_mn = 16'hfc4e;
				11'd72: cabac_init_mn = 16'hfd60;
				11'd73: cabac_init_mn = 16'he57e;
				11'd74: cabac_init_mn = 16'he462;
				11'd75: cabac_init_mn = 16'he765;
				11'd76: cabac_init_mn = 16'he943;
				11'd77: cabac_init_mn = 16'he452;
				11'd78: cabac_init_mn = 16'hec5e;
				11'd79: cabac_init_mn = 16'hf053;
				11'd80: cabac_init_mn = 16'hea6e;
				11'd81: cabac_init_mn = 16'heb5b;
				11'd82: cabac_init_mn = 16'hee66;
				11'd83: cabac_init_mn = 16'hf35d;
				11'd84: cabac_init_mn = 16'he37f;
				11'd85: cabac_init_mn = 16'hf95c;
				11'd86: cabac_init_mn = 16'hfb59;
				11'd87: cabac_init_mn = 16'hf960;
				11'd88: cabac_init_mn = 16'hf36c;
				11'd89: cabac_init_mn = 16'hfd2e;
				11'd90: cabac_init_mn = 16'hff41;
				11'd91: cabac_init_mn = 16'hff39;
				11'd92: cabac_init_mn = 16'hf75d;
				11'd93: cabac_init_mn = 16'hfd4a;
				11'd94: cabac_init_mn = 16'hf75c;
				11'd95: cabac_init_mn = 16'hf857;
				11'd96: cabac_init_mn = 16'he97e;
				11'd97: cabac_init_mn = 16'h0536;
				11'd98: cabac_init_mn = 16'h063c;
				11'd99: cabac_init_mn = 16'h063b;
				11'd100: cabac_init_mn = 16'h0645;
				11'd101: cabac_init_mn = 16'hff30;
				11'd102: cabac_init_mn = 16'h0044;
				11'd103: cabac_init_mn = 16'hfc45;
				11'd104: cabac_init_mn = 16'hf858;
				11'd105: cabac_init_mn = 16'hfe55;
				11'd106: cabac_init_mn = 16'hfa4e;
				11'd107: cabac_init_mn = 16'hff4b;
				11'd108: cabac_init_mn = 16'hf94d;
				11'd109: cabac_init_mn = 16'h0236;
				11'd110: cabac_init_mn = 16'h0532;
				11'd111: cabac_init_mn = 16'hfd44;
				11'd112: cabac_init_mn = 16'h0132;
				11'd113: cabac_init_mn = 16'h062a;
				11'd114: cabac_init_mn = 16'hfc51;
				11'd115: cabac_init_mn = 16'h013f;
				11'd116: cabac_init_mn = 16'hfc46;
				11'd117: cabac_init_mn = 16'h0043;
				11'd118: cabac_init_mn = 16'h0239;
				11'd119: cabac_init_mn = 16'hfe4c;
				11'd120: cabac_init_mn = 16'h0b23;
				11'd121: cabac_init_mn = 16'h0440;
				11'd122: cabac_init_mn = 16'h013d;
				11'd123: cabac_init_mn = 16'h0b23;
				11'd124: cabac_init_mn = 16'h1219;
				11'd125: cabac_init_mn = 16'h0c18;
				11'd126: cabac_init_mn = 16'h0d1d;
				11'd127: cabac_init_mn = 16'h0d24;
				11'd128: cabac_init_mn = 16'hf65d;
				11'd129: cabac_init_mn = 16'hf949;
				11'd130: cabac_init_mn = 16'hfe49;
				11'd131: cabac_init_mn = 16'h0d2e;
				11'd132: cabac_init_mn = 16'h0931;
				11'd133: cabac_init_mn = 16'hf964;
				11'd134: cabac_init_mn = 16'h0935;
				11'd135: cabac_init_mn = 16'h0235;
				11'd136: cabac_init_mn = 16'h0535;
				11'd137: cabac_init_mn = 16'hfe3d;
				11'd138: cabac_init_mn = 16'h0038;
				11'd139: cabac_init_mn = 16'h0038;
				11'd140: cabac_init_mn = 16'hf33f;
				11'd141: cabac_init_mn = 16'hfb3c;
				11'd142: cabac_init_mn = 16'hff3e;
				11'd143: cabac_init_mn = 16'h0439;
				11'd144: cabac_init_mn = 16'hfa45;
				11'd145: cabac_init_mn = 16'h0439;
				11'd146: cabac_init_mn = 16'h0e27;
				11'd147: cabac_init_mn = 16'h0433;
				11'd148: cabac_init_mn = 16'h0d44;
				11'd149: cabac_init_mn = 16'h0340;
				11'd150: cabac_init_mn = 16'h013d;
				11'd151: cabac_init_mn = 16'h093f;
				11'd152: cabac_init_mn = 16'h0732;
				11'd153: cabac_init_mn = 16'h1027;
				11'd154: cabac_init_mn = 16'h052c;
				11'd155: cabac_init_mn = 16'h0434;
				11'd156: cabac_init_mn = 16'h0b30;
				11'd157: cabac_init_mn = 16'hfb3c;
				11'd158: cabac_init_mn = 16'hff3b;
				11'd159: cabac_init_mn = 16'h003b;
				11'd160: cabac_init_mn = 16'h1621;
				11'd161: cabac_init_mn = 16'h052c;
				11'd162: cabac_init_mn = 16'h0e2b;
				11'd163: cabac_init_mn = 16'hff4e;
				11'd164: cabac_init_mn = 16'h003c;
				11'd165: cabac_init_mn = 16'h0945;
				11'd166: cabac_init_mn = 16'h0b1c;
				11'd167: cabac_init_mn = 16'h0228;
				11'd168: cabac_init_mn = 16'h032c;
				11'd169: cabac_init_mn = 16'h0031;
				11'd170: cabac_init_mn = 16'h002e;
				11'd171: cabac_init_mn = 16'h022c;
				11'd172: cabac_init_mn = 16'h0233;
				11'd173: cabac_init_mn = 16'h002f;
				11'd174: cabac_init_mn = 16'h0427;
				11'd175: cabac_init_mn = 16'h023e;
				11'd176: cabac_init_mn = 16'h062e;
				11'd177: cabac_init_mn = 16'h0036;
				11'd178: cabac_init_mn = 16'h0336;
				11'd179: cabac_init_mn = 16'h023a;
				11'd180: cabac_init_mn = 16'h043f;
				11'd181: cabac_init_mn = 16'h0633;
				11'd182: cabac_init_mn = 16'h0639;
				11'd183: cabac_init_mn = 16'h0735;
				11'd184: cabac_init_mn = 16'h0634;
				11'd185: cabac_init_mn = 16'h0637;
				11'd186: cabac_init_mn = 16'h0b2d;
				11'd187: cabac_init_mn = 16'h0e24;
				11'd188: cabac_init_mn = 16'h0835;
				11'd189: cabac_init_mn = 16'hff52;
				11'd190: cabac_init_mn = 16'h0737;
				11'd191: cabac_init_mn = 16'hfd4e;
				11'd192: cabac_init_mn = 16'h0f2e;
				11'd193: cabac_init_mn = 16'h161f;
				11'd194: cabac_init_mn = 16'hff54;
				11'd195: cabac_init_mn = 16'h1907;
				11'd196: cabac_init_mn = 16'h1ef9;
				11'd197: cabac_init_mn = 16'h1c03;
				11'd198: cabac_init_mn = 16'h1c04;
				11'd199: cabac_init_mn = 16'h2000;
				11'd200: cabac_init_mn = 16'h22ff;
				11'd201: cabac_init_mn = 16'h1e06;
				11'd202: cabac_init_mn = 16'h1e06;
				11'd203: cabac_init_mn = 16'h2009;
				11'd204: cabac_init_mn = 16'h1f13;
				11'd205: cabac_init_mn = 16'h1a1b;
				11'd206: cabac_init_mn = 16'h1a1e;
				11'd207: cabac_init_mn = 16'h2514;
				11'd208: cabac_init_mn = 16'h1c22;
				11'd209: cabac_init_mn = 16'h1146;
				11'd210: cabac_init_mn = 16'h0143;
				11'd211: cabac_init_mn = 16'h053b;
				11'd212: cabac_init_mn = 16'h0943;
				11'd213: cabac_init_mn = 16'h101e;
				11'd214: cabac_init_mn = 16'h1220;
				11'd215: cabac_init_mn = 16'h1223;
				11'd216: cabac_init_mn = 16'h161d;
				11'd217: cabac_init_mn = 16'h181f;
				11'd218: cabac_init_mn = 16'h1726;
				11'd219: cabac_init_mn = 16'h122b;
				11'd220: cabac_init_mn = 16'h1429;
				11'd221: cabac_init_mn = 16'h0b3f;
				11'd222: cabac_init_mn = 16'h093b;
				11'd223: cabac_init_mn = 16'h0940;
				11'd224: cabac_init_mn = 16'hff5e;
				11'd225: cabac_init_mn = 16'hfe59;
				11'd226: cabac_init_mn = 16'hf76c;
				11'd227: cabac_init_mn = 16'hfa4c;
				11'd228: cabac_init_mn = 16'hfe2c;
				11'd229: cabac_init_mn = 16'h002d;
				11'd230: cabac_init_mn = 16'h0034;
				11'd231: cabac_init_mn = 16'hfd40;
				11'd232: cabac_init_mn = 16'hfe3b;
				11'd233: cabac_init_mn = 16'hfc46;
				11'd234: cabac_init_mn = 16'hfc4b;
				11'd235: cabac_init_mn = 16'hf852;
				11'd236: cabac_init_mn = 16'hef66;
				11'd237: cabac_init_mn = 16'hf74d;
				11'd238: cabac_init_mn = 16'h0318;
				11'd239: cabac_init_mn = 16'h002a;
				11'd240: cabac_init_mn = 16'h0030;
				11'd241: cabac_init_mn = 16'h0037;
				11'd242: cabac_init_mn = 16'hfa3b;
				11'd243: cabac_init_mn = 16'hf947;
				11'd244: cabac_init_mn = 16'hf453;
				11'd245: cabac_init_mn = 16'hf557;
				11'd246: cabac_init_mn = 16'he277;
				11'd247: cabac_init_mn = 16'h013a;
				11'd248: cabac_init_mn = 16'hfd1d;
				11'd249: cabac_init_mn = 16'hff24;
				11'd250: cabac_init_mn = 16'h0126;
				11'd251: cabac_init_mn = 16'h022b;
				11'd252: cabac_init_mn = 16'hfa37;
				11'd253: cabac_init_mn = 16'h003a;
				11'd254: cabac_init_mn = 16'h0040;
				11'd255: cabac_init_mn = 16'hfd4a;
				11'd256: cabac_init_mn = 16'hf65a;
				11'd257: cabac_init_mn = 16'h0046;
				11'd258: cabac_init_mn = 16'hfc1d;
				11'd259: cabac_init_mn = 16'h051f;
				11'd260: cabac_init_mn = 16'h072a;
				11'd261: cabac_init_mn = 16'h013b;
				11'd262: cabac_init_mn = 16'hfe3a;
				11'd263: cabac_init_mn = 16'hfd48;
				11'd264: cabac_init_mn = 16'hfd51;
				11'd265: cabac_init_mn = 16'hf561;
				11'd266: cabac_init_mn = 16'h003a;
				11'd267: cabac_init_mn = 16'h0805;
				11'd268: cabac_init_mn = 16'h0a0e;
				11'd269: cabac_init_mn = 16'h0e12;
				11'd270: cabac_init_mn = 16'h0d1b;
				11'd271: cabac_init_mn = 16'h0228;
				11'd272: cabac_init_mn = 16'h003a;
				11'd273: cabac_init_mn = 16'hfd46;
				11'd274: cabac_init_mn = 16'hfa4f;
				11'd275: cabac_init_mn = 16'hf855;
				11'd276: cabac_init_mn = 16'h0000;
				11'd277: cabac_init_mn = 16'hf36a;
				11'd278: cabac_init_mn = 16'hf06a;
				11'd279: cabac_init_mn = 16'hf657;
				11'd280: cabac_init_mn = 16'heb72;
				11'd281: cabac_init_mn = 16'hee6e;
				11'd282: cabac_init_mn = 16'hf262;
				11'd283: cabac_init_mn = 16'hea6e;
				11'd284: cabac_init_mn = 16'heb6a;
				11'd285: cabac_init_mn = 16'hee67;
				11'd286: cabac_init_mn = 16'heb6b;
				11'd287: cabac_init_mn = 16'he96c;
				11'd288: cabac_init_mn = 16'he670;
				11'd289: cabac_init_mn = 16'hf660;
				11'd290: cabac_init_mn = 16'hf45f;
				11'd291: cabac_init_mn = 16'hfb5b;
				11'd292: cabac_init_mn = 16'hf75d;
				11'd293: cabac_init_mn = 16'hea5e;
				11'd294: cabac_init_mn = 16'hfb56;
				11'd295: cabac_init_mn = 16'h0943;
				11'd296: cabac_init_mn = 16'hfc50;
				11'd297: cabac_init_mn = 16'hf655;
				11'd298: cabac_init_mn = 16'hff46;
				11'd299: cabac_init_mn = 16'h073c;
				11'd300: cabac_init_mn = 16'h093a;
				11'd301: cabac_init_mn = 16'h053d;
				11'd302: cabac_init_mn = 16'h0c32;
				11'd303: cabac_init_mn = 16'h0f32;
				11'd304: cabac_init_mn = 16'h1231;
				11'd305: cabac_init_mn = 16'h1136;
				11'd306: cabac_init_mn = 16'h0a29;
				11'd307: cabac_init_mn = 16'h072e;
				11'd308: cabac_init_mn = 16'hff33;
				11'd309: cabac_init_mn = 16'h0731;
				11'd310: cabac_init_mn = 16'h0834;
				11'd311: cabac_init_mn = 16'h0929;
				11'd312: cabac_init_mn = 16'h062f;
				11'd313: cabac_init_mn = 16'h0237;
				11'd314: cabac_init_mn = 16'h0d29;
				11'd315: cabac_init_mn = 16'h0a2c;
				11'd316: cabac_init_mn = 16'h0632;
				11'd317: cabac_init_mn = 16'h0535;
				11'd318: cabac_init_mn = 16'h0d31;
				11'd319: cabac_init_mn = 16'h043f;
				11'd320: cabac_init_mn = 16'h0640;
				11'd321: cabac_init_mn = 16'hfe45;
				11'd322: cabac_init_mn = 16'hfe3b;
				11'd323: cabac_init_mn = 16'h0646;
				11'd324: cabac_init_mn = 16'h0a2c;
				11'd325: cabac_init_mn = 16'h091f;
				11'd326: cabac_init_mn = 16'h0c2b;
				11'd327: cabac_init_mn = 16'h0335;
				11'd328: cabac_init_mn = 16'h0e22;
				11'd329: cabac_init_mn = 16'h0a26;
				11'd330: cabac_init_mn = 16'hfd34;
				11'd331: cabac_init_mn = 16'h0d28;
				11'd332: cabac_init_mn = 16'h1120;
				11'd333: cabac_init_mn = 16'h072c;
				11'd334: cabac_init_mn = 16'h0726;
				11'd335: cabac_init_mn = 16'h0d32;
				11'd336: cabac_init_mn = 16'h0a39;
				11'd337: cabac_init_mn = 16'h1a2b;
				11'd338: cabac_init_mn = 16'h0e0b;
				11'd339: cabac_init_mn = 16'h0b0e;
				11'd340: cabac_init_mn = 16'h090b;
				11'd341: cabac_init_mn = 16'h120b;
				11'd342: cabac_init_mn = 16'h1509;
				11'd343: cabac_init_mn = 16'h17fe;
				11'd344: cabac_init_mn = 16'h20f1;
				11'd345: cabac_init_mn = 16'h20f1;
				11'd346: cabac_init_mn = 16'h22eb;
				11'd347: cabac_init_mn = 16'h27e9;
				11'd348: cabac_init_mn = 16'h2adf;
				11'd349: cabac_init_mn = 16'h29e1;
				11'd350: cabac_init_mn = 16'h2ee4;
				11'd351: cabac_init_mn = 16'h26f4;
				11'd352: cabac_init_mn = 16'h151d;
				11'd353: cabac_init_mn = 16'h2de8;
				11'd354: cabac_init_mn = 16'h35d3;
				11'd355: cabac_init_mn = 16'h30e6;
				11'd356: cabac_init_mn = 16'h41d5;
				11'd357: cabac_init_mn = 16'h2bed;
				11'd358: cabac_init_mn = 16'h27f6;
				11'd359: cabac_init_mn = 16'h1e09;
				11'd360: cabac_init_mn = 16'h121a;
				11'd361: cabac_init_mn = 16'h141b;
				11'd362: cabac_init_mn = 16'h0039;
				11'd363: cabac_init_mn = 16'hf252;
				11'd364: cabac_init_mn = 16'hfb4b;
				11'd365: cabac_init_mn = 16'hed61;
				11'd366: cabac_init_mn = 16'hdd7d;
				11'd367: cabac_init_mn = 16'h1b00;
				11'd368: cabac_init_mn = 16'h1c00;
				11'd369: cabac_init_mn = 16'h1ffc;
				11'd370: cabac_init_mn = 16'h1b06;
				11'd371: cabac_init_mn = 16'h2208;
				11'd372: cabac_init_mn = 16'h1e0a;
				11'd373: cabac_init_mn = 16'h1816;
				11'd374: cabac_init_mn = 16'h2113;
				11'd375: cabac_init_mn = 16'h1620;
				11'd376: cabac_init_mn = 16'h1a1f;
				11'd377: cabac_init_mn = 16'h1529;
				11'd378: cabac_init_mn = 16'h1a2c;
				11'd379: cabac_init_mn = 16'h172f;
				11'd380: cabac_init_mn = 16'h1041;
				11'd381: cabac_init_mn = 16'h0e47;
				11'd382: cabac_init_mn = 16'h083c;
				11'd383: cabac_init_mn = 16'h063f;
				11'd384: cabac_init_mn = 16'h1141;
				11'd385: cabac_init_mn = 16'h1518;
				11'd386: cabac_init_mn = 16'h1714;
				11'd387: cabac_init_mn = 16'h1a17;
				11'd388: cabac_init_mn = 16'h1b20;
				11'd389: cabac_init_mn = 16'h1c17;
				11'd390: cabac_init_mn = 16'h1c18;
				11'd391: cabac_init_mn = 16'h1728;
				11'd392: cabac_init_mn = 16'h1820;
				11'd393: cabac_init_mn = 16'h1c1d;
				11'd394: cabac_init_mn = 16'h172a;
				11'd395: cabac_init_mn = 16'h1339;
				11'd396: cabac_init_mn = 16'h1635;
				11'd397: cabac_init_mn = 16'h163d;
				11'd398: cabac_init_mn = 16'h0b56;
				11'd399: cabac_init_mn = 16'h0c28;
				11'd400: cabac_init_mn = 16'h0b33;
				11'd401: cabac_init_mn = 16'h0e3b;
				11'd402: cabac_init_mn = 16'hfc4f;
				11'd403: cabac_init_mn = 16'hf947;
				11'd404: cabac_init_mn = 16'hfb45;
				11'd405: cabac_init_mn = 16'hf746;
				11'd406: cabac_init_mn = 16'hf842;
				11'd407: cabac_init_mn = 16'hf644;
				11'd408: cabac_init_mn = 16'hed49;
				11'd409: cabac_init_mn = 16'hf445;
				11'd410: cabac_init_mn = 16'hf046;
				11'd411: cabac_init_mn = 16'hf143;
				11'd412: cabac_init_mn = 16'hec3e;
				11'd413: cabac_init_mn = 16'hed46;
				11'd414: cabac_init_mn = 16'hf042;
				11'd415: cabac_init_mn = 16'hea41;
				11'd416: cabac_init_mn = 16'hec3f;
				11'd417: cabac_init_mn = 16'h09fe;
				11'd418: cabac_init_mn = 16'h1af7;
				11'd419: cabac_init_mn = 16'h21f7;
				11'd420: cabac_init_mn = 16'h27f9;
				11'd421: cabac_init_mn = 16'h29fe;
				11'd422: cabac_init_mn = 16'h2d03;
				11'd423: cabac_init_mn = 16'h3109;
				11'd424: cabac_init_mn = 16'h2d1b;
				11'd425: cabac_init_mn = 16'h243b;
				11'd426: cabac_init_mn = 16'hfa42;
				11'd427: cabac_init_mn = 16'hf923;
				11'd428: cabac_init_mn = 16'hf92a;
				11'd429: cabac_init_mn = 16'hf82d;
				11'd430: cabac_init_mn = 16'hfb30;
				11'd431: cabac_init_mn = 16'hf438;
				11'd432: cabac_init_mn = 16'hfa3c;
				11'd433: cabac_init_mn = 16'hfb3e;
				11'd434: cabac_init_mn = 16'hf842;
				11'd435: cabac_init_mn = 16'hf84c;
				11'd512: cabac_init_mn = 16'h14f1;
				11'd513: cabac_init_mn = 16'h0236;
				11'd514: cabac_init_mn = 16'h034a;
				11'd515: cabac_init_mn = 16'h14f1;
				11'd516: cabac_init_mn = 16'h0236;
				11'd517: cabac_init_mn = 16'h034a;
				11'd518: cabac_init_mn = 16'he47f;
				11'd519: cabac_init_mn = 16'he968;
				11'd520: cabac_init_mn = 16'hfa35;
				11'd521: cabac_init_mn = 16'hff36;
				11'd522: cabac_init_mn = 16'h0733;
				11'd523: cabac_init_mn = 16'h1619;
				11'd524: cabac_init_mn = 16'h2200;
				11'd525: cabac_init_mn = 16'h1000;
				11'd526: cabac_init_mn = 16'hfe09;
				11'd527: cabac_init_mn = 16'h0429;
				11'd528: cabac_init_mn = 16'he376;
				11'd529: cabac_init_mn = 16'h0241;
				11'd530: cabac_init_mn = 16'hfa47;
				11'd531: cabac_init_mn = 16'hf34f;
				11'd532: cabac_init_mn = 16'h0534;
				11'd533: cabac_init_mn = 16'h0932;
				11'd534: cabac_init_mn = 16'hfd46;
				11'd535: cabac_init_mn = 16'h0a36;
				11'd536: cabac_init_mn = 16'h1a22;
				11'd537: cabac_init_mn = 16'h1316;
				11'd538: cabac_init_mn = 16'h2800;
				11'd539: cabac_init_mn = 16'h3902;
				11'd540: cabac_init_mn = 16'h2924;
				11'd541: cabac_init_mn = 16'h1a45;
				11'd542: cabac_init_mn = 16'hd37f;
				11'd543: cabac_init_mn = 16'hf165;
				11'd544: cabac_init_mn = 16'hfc4c;
				11'd545: cabac_init_mn = 16'hfa47;
				11'd546: cabac_init_mn = 16'hf34f;
				11'd547: cabac_init_mn = 16'h0534;
				11'd548: cabac_init_mn = 16'h0645;
				11'd549: cabac_init_mn = 16'hf35a;
				11'd550: cabac_init_mn = 16'h0034;
				11'd551: cabac_init_mn = 16'h082b;
				11'd552: cabac_init_mn = 16'hfe45;
				11'd553: cabac_init_mn = 16'hfb52;
				11'd554: cabac_init_mn = 16'hf660;
				11'd555: cabac_init_mn = 16'h023b;
				11'd556: cabac_init_mn = 16'h024b;
				11'd557: cabac_init_mn = 16'hfd57;
				11'd558: cabac_init_mn = 16'hfd64;
				11'd559: cabac_init_mn = 16'h0138;
				11'd560: cabac_init_mn = 16'hfd4a;
				11'd561: cabac_init_mn = 16'hfa55;
				11'd562: cabac_init_mn = 16'h003b;
				11'd563: cabac_init_mn = 16'hfd51;
				11'd564: cabac_init_mn = 16'hf956;
				11'd565: cabac_init_mn = 16'hfb5f;
				11'd566: cabac_init_mn = 16'hff42;
				11'd567: cabac_init_mn = 16'hff4d;
				11'd568: cabac_init_mn = 16'h0146;
				11'd569: cabac_init_mn = 16'hfe56;
				11'd570: cabac_init_mn = 16'hfb48;
				11'd571: cabac_init_mn = 16'h003d;
				11'd572: cabac_init_mn = 16'h0029;
				11'd573: cabac_init_mn = 16'h003f;
				11'd574: cabac_init_mn = 16'h003f;
				11'd575: cabac_init_mn = 16'h003f;
				11'd576: cabac_init_mn = 16'hf753;
				11'd577: cabac_init_mn = 16'h0456;
				11'd578: cabac_init_mn = 16'h0061;
				11'd579: cabac_init_mn = 16'hf948;
				11'd580: cabac_init_mn = 16'h0d29;
				11'd581: cabac_init_mn = 16'h033e;
				11'd582: cabac_init_mn = 16'h0d0f;
				11'd583: cabac_init_mn = 16'h0733;
				11'd584: cabac_init_mn = 16'h0250;
				11'd585: cabac_init_mn = 16'hd97f;
				11'd586: cabac_init_mn = 16'hee5b;
				11'd587: cabac_init_mn = 16'hef60;
				11'd588: cabac_init_mn = 16'he651;
				11'd589: cabac_init_mn = 16'hdd62;
				11'd590: cabac_init_mn = 16'he866;
				11'd591: cabac_init_mn = 16'he961;
				11'd592: cabac_init_mn = 16'he577;
				11'd593: cabac_init_mn = 16'he863;
				11'd594: cabac_init_mn = 16'heb6e;
				11'd595: cabac_init_mn = 16'hee66;
				11'd596: cabac_init_mn = 16'hdc7f;
				11'd597: cabac_init_mn = 16'h0050;
				11'd598: cabac_init_mn = 16'hfb59;
				11'd599: cabac_init_mn = 16'hf95e;
				11'd600: cabac_init_mn = 16'hfc5c;
				11'd601: cabac_init_mn = 16'h0027;
				11'd602: cabac_init_mn = 16'h0041;
				11'd603: cabac_init_mn = 16'hf154;
				11'd604: cabac_init_mn = 16'hdd7f;
				11'd605: cabac_init_mn = 16'hfe49;
				11'd606: cabac_init_mn = 16'hf468;
				11'd607: cabac_init_mn = 16'hf75b;
				11'd608: cabac_init_mn = 16'he17f;
				11'd609: cabac_init_mn = 16'h0337;
				11'd610: cabac_init_mn = 16'h0738;
				11'd611: cabac_init_mn = 16'h0737;
				11'd612: cabac_init_mn = 16'h083d;
				11'd613: cabac_init_mn = 16'hfd35;
				11'd614: cabac_init_mn = 16'h0044;
				11'd615: cabac_init_mn = 16'hf94a;
				11'd616: cabac_init_mn = 16'hf758;
				11'd617: cabac_init_mn = 16'hf367;
				11'd618: cabac_init_mn = 16'hf35b;
				11'd619: cabac_init_mn = 16'hf759;
				11'd620: cabac_init_mn = 16'hf25c;
				11'd621: cabac_init_mn = 16'hf84c;
				11'd622: cabac_init_mn = 16'hf457;
				11'd623: cabac_init_mn = 16'he96e;
				11'd624: cabac_init_mn = 16'he869;
				11'd625: cabac_init_mn = 16'hf64e;
				11'd626: cabac_init_mn = 16'hec70;
				11'd627: cabac_init_mn = 16'hef63;
				11'd628: cabac_init_mn = 16'hb27f;
				11'd629: cabac_init_mn = 16'hba7f;
				11'd630: cabac_init_mn = 16'hce7f;
				11'd631: cabac_init_mn = 16'hd27f;
				11'd632: cabac_init_mn = 16'hfc42;
				11'd633: cabac_init_mn = 16'hfb4e;
				11'd634: cabac_init_mn = 16'hfc47;
				11'd635: cabac_init_mn = 16'hf848;
				11'd636: cabac_init_mn = 16'h023b;
				11'd637: cabac_init_mn = 16'hff37;
				11'd638: cabac_init_mn = 16'hf946;
				11'd639: cabac_init_mn = 16'hfa4b;
				11'd640: cabac_init_mn = 16'hf859;
				11'd641: cabac_init_mn = 16'hde77;
				11'd642: cabac_init_mn = 16'hfd4b;
				11'd643: cabac_init_mn = 16'h2014;
				11'd644: cabac_init_mn = 16'h1e16;
				11'd645: cabac_init_mn = 16'hd47f;
				11'd646: cabac_init_mn = 16'h0036;
				11'd647: cabac_init_mn = 16'hfb3d;
				11'd648: cabac_init_mn = 16'h003a;
				11'd649: cabac_init_mn = 16'hff3c;
				11'd650: cabac_init_mn = 16'hfd3d;
				11'd651: cabac_init_mn = 16'hf843;
				11'd652: cabac_init_mn = 16'he754;
				11'd653: cabac_init_mn = 16'hf24a;
				11'd654: cabac_init_mn = 16'hfb41;
				11'd655: cabac_init_mn = 16'h0534;
				11'd656: cabac_init_mn = 16'h0239;
				11'd657: cabac_init_mn = 16'h003d;
				11'd658: cabac_init_mn = 16'hf745;
				11'd659: cabac_init_mn = 16'hf546;
				11'd660: cabac_init_mn = 16'h1237;
				11'd661: cabac_init_mn = 16'hfc47;
				11'd662: cabac_init_mn = 16'h003a;
				11'd663: cabac_init_mn = 16'h073d;
				11'd664: cabac_init_mn = 16'h0929;
				11'd665: cabac_init_mn = 16'h1219;
				11'd666: cabac_init_mn = 16'h0920;
				11'd667: cabac_init_mn = 16'h052b;
				11'd668: cabac_init_mn = 16'h092f;
				11'd669: cabac_init_mn = 16'h002c;
				11'd670: cabac_init_mn = 16'h0033;
				11'd671: cabac_init_mn = 16'h022e;
				11'd672: cabac_init_mn = 16'h1326;
				11'd673: cabac_init_mn = 16'hfc42;
				11'd674: cabac_init_mn = 16'h0f26;
				11'd675: cabac_init_mn = 16'h0c2a;
				11'd676: cabac_init_mn = 16'h0922;
				11'd677: cabac_init_mn = 16'h0059;
				11'd678: cabac_init_mn = 16'h042d;
				11'd679: cabac_init_mn = 16'h0a1c;
				11'd680: cabac_init_mn = 16'h0a1f;
				11'd681: cabac_init_mn = 16'h21f5;
				11'd682: cabac_init_mn = 16'h34d5;
				11'd683: cabac_init_mn = 16'h120f;
				11'd684: cabac_init_mn = 16'h1c00;
				11'd685: cabac_init_mn = 16'h23ea;
				11'd686: cabac_init_mn = 16'h26e7;
				11'd687: cabac_init_mn = 16'h2200;
				11'd688: cabac_init_mn = 16'h27ee;
				11'd689: cabac_init_mn = 16'h20f4;
				11'd690: cabac_init_mn = 16'h66a2;
				11'd691: cabac_init_mn = 16'h0000;
				11'd692: cabac_init_mn = 16'h38f1;
				11'd693: cabac_init_mn = 16'h21fc;
				11'd694: cabac_init_mn = 16'h1d0a;
				11'd695: cabac_init_mn = 16'h25fb;
				11'd696: cabac_init_mn = 16'h33e3;
				11'd697: cabac_init_mn = 16'h27f7;
				11'd698: cabac_init_mn = 16'h34de;
				11'd699: cabac_init_mn = 16'h45c6;
				11'd700: cabac_init_mn = 16'h43c1;
				11'd701: cabac_init_mn = 16'h2cfb;
				11'd702: cabac_init_mn = 16'h2007;
				11'd703: cabac_init_mn = 16'h37e3;
				11'd704: cabac_init_mn = 16'h2001;
				11'd705: cabac_init_mn = 16'h0000;
				11'd706: cabac_init_mn = 16'h1b24;
				11'd707: cabac_init_mn = 16'h21e7;
				11'd708: cabac_init_mn = 16'h22e2;
				11'd709: cabac_init_mn = 16'h24e4;
				11'd710: cabac_init_mn = 16'h26e4;
				11'd711: cabac_init_mn = 16'h26e5;
				11'd712: cabac_init_mn = 16'h22ee;
				11'd713: cabac_init_mn = 16'h23f0;
				11'd714: cabac_init_mn = 16'h22f2;
				11'd715: cabac_init_mn = 16'h20f8;
				11'd716: cabac_init_mn = 16'h25fa;
				11'd717: cabac_init_mn = 16'h2300;
				11'd718: cabac_init_mn = 16'h1e0a;
				11'd719: cabac_init_mn = 16'h1c12;
				11'd720: cabac_init_mn = 16'h1a19;
				11'd721: cabac_init_mn = 16'h1d29;
				11'd722: cabac_init_mn = 16'h004b;
				11'd723: cabac_init_mn = 16'h0248;
				11'd724: cabac_init_mn = 16'h084d;
				11'd725: cabac_init_mn = 16'h0e23;
				11'd726: cabac_init_mn = 16'h121f;
				11'd727: cabac_init_mn = 16'h1123;
				11'd728: cabac_init_mn = 16'h151e;
				11'd729: cabac_init_mn = 16'h112d;
				11'd730: cabac_init_mn = 16'h142a;
				11'd731: cabac_init_mn = 16'h122d;
				11'd732: cabac_init_mn = 16'h1b1a;
				11'd733: cabac_init_mn = 16'h1036;
				11'd734: cabac_init_mn = 16'h0742;
				11'd735: cabac_init_mn = 16'h1038;
				11'd736: cabac_init_mn = 16'h0b49;
				11'd737: cabac_init_mn = 16'h0a43;
				11'd738: cabac_init_mn = 16'hf674;
				11'd739: cabac_init_mn = 16'he970;
				11'd740: cabac_init_mn = 16'hf147;
				11'd741: cabac_init_mn = 16'hf93d;
				11'd742: cabac_init_mn = 16'h0035;
				11'd743: cabac_init_mn = 16'hfb42;
				11'd744: cabac_init_mn = 16'hf54d;
				11'd745: cabac_init_mn = 16'hf750;
				11'd746: cabac_init_mn = 16'hf754;
				11'd747: cabac_init_mn = 16'hf657;
				11'd748: cabac_init_mn = 16'hde7f;
				11'd749: cabac_init_mn = 16'heb65;
				11'd750: cabac_init_mn = 16'hfd27;
				11'd751: cabac_init_mn = 16'hfb35;
				11'd752: cabac_init_mn = 16'hf93d;
				11'd753: cabac_init_mn = 16'hf54b;
				11'd754: cabac_init_mn = 16'hf14d;
				11'd755: cabac_init_mn = 16'hef5b;
				11'd756: cabac_init_mn = 16'he76b;
				11'd757: cabac_init_mn = 16'he76f;
				11'd758: cabac_init_mn = 16'he47a;
				11'd759: cabac_init_mn = 16'hf54c;
				11'd760: cabac_init_mn = 16'hf62c;
				11'd761: cabac_init_mn = 16'hf634;
				11'd762: cabac_init_mn = 16'hf639;
				11'd763: cabac_init_mn = 16'hf73a;
				11'd764: cabac_init_mn = 16'hf048;
				11'd765: cabac_init_mn = 16'hf945;
				11'd766: cabac_init_mn = 16'hfc45;
				11'd767: cabac_init_mn = 16'hfb4a;
				11'd768: cabac_init_mn = 16'hf756;
				11'd769: cabac_init_mn = 16'h0242;
				11'd770: cabac_init_mn = 16'hf722;
				11'd771: cabac_init_mn = 16'h0120;
				11'd772: cabac_init_mn = 16'h0b1f;
				11'd773: cabac_init_mn = 16'h0534;
				11'd774: cabac_init_mn = 16'hfe37;
				11'd775: cabac_init_mn = 16'hfe43;
				11'd776: cabac_init_mn = 16'h0049;
				11'd777: cabac_init_mn = 16'hf859;
				11'd778: cabac_init_mn = 16'h0334;
				11'd779: cabac_init_mn = 16'h0704;
				11'd780: cabac_init_mn = 16'h0a08;
				11'd781: cabac_init_mn = 16'h1108;
				11'd782: cabac_init_mn = 16'h1013;
				11'd783: cabac_init_mn = 16'h0325;
				11'd784: cabac_init_mn = 16'hff3d;
				11'd785: cabac_init_mn = 16'hfb49;
				11'd786: cabac_init_mn = 16'hff46;
				11'd787: cabac_init_mn = 16'hfc4e;
				11'd788: cabac_init_mn = 16'h0000;
				11'd789: cabac_init_mn = 16'heb7e;
				11'd790: cabac_init_mn = 16'he97c;
				11'd791: cabac_init_mn = 16'hec6e;
				11'd792: cabac_init_mn = 16'he67e;
				11'd793: cabac_init_mn = 16'he77c;
				11'd794: cabac_init_mn = 16'hef69;
				11'd795: cabac_init_mn = 16'he579;
				11'd796: cabac_init_mn = 16'he575;
				11'd797: cabac_init_mn = 16'hef66;
				11'd798: cabac_init_mn = 16'he675;
				11'd799: cabac_init_mn = 16'he574;
				11'd800: cabac_init_mn = 16'hdf7a;
				11'd801: cabac_init_mn = 16'hf65f;
				11'd802: cabac_init_mn = 16'hf264;
				11'd803: cabac_init_mn = 16'hf85f;
				11'd804: cabac_init_mn = 16'hef6f;
				11'd805: cabac_init_mn = 16'he472;
				11'd806: cabac_init_mn = 16'hfa59;
				11'd807: cabac_init_mn = 16'hfe50;
				11'd808: cabac_init_mn = 16'hfc52;
				11'd809: cabac_init_mn = 16'hf755;
				11'd810: cabac_init_mn = 16'hf851;
				11'd811: cabac_init_mn = 16'hff48;
				11'd812: cabac_init_mn = 16'h0540;
				11'd813: cabac_init_mn = 16'h0143;
				11'd814: cabac_init_mn = 16'h0938;
				11'd815: cabac_init_mn = 16'h0045;
				11'd816: cabac_init_mn = 16'h0145;
				11'd817: cabac_init_mn = 16'h0745;
				11'd818: cabac_init_mn = 16'hf945;
				11'd819: cabac_init_mn = 16'hfa43;
				11'd820: cabac_init_mn = 16'hf04d;
				11'd821: cabac_init_mn = 16'hfe40;
				11'd822: cabac_init_mn = 16'h023d;
				11'd823: cabac_init_mn = 16'hfa43;
				11'd824: cabac_init_mn = 16'hfd40;
				11'd825: cabac_init_mn = 16'h0239;
				11'd826: cabac_init_mn = 16'hfd41;
				11'd827: cabac_init_mn = 16'hfd42;
				11'd828: cabac_init_mn = 16'h003e;
				11'd829: cabac_init_mn = 16'h0933;
				11'd830: cabac_init_mn = 16'hff42;
				11'd831: cabac_init_mn = 16'hfe47;
				11'd832: cabac_init_mn = 16'hfe4b;
				11'd833: cabac_init_mn = 16'hff46;
				11'd834: cabac_init_mn = 16'hf748;
				11'd835: cabac_init_mn = 16'h0e3c;
				11'd836: cabac_init_mn = 16'h1025;
				11'd837: cabac_init_mn = 16'h002f;
				11'd838: cabac_init_mn = 16'h1223;
				11'd839: cabac_init_mn = 16'h0b25;
				11'd840: cabac_init_mn = 16'h0c29;
				11'd841: cabac_init_mn = 16'h0a29;
				11'd842: cabac_init_mn = 16'h0230;
				11'd843: cabac_init_mn = 16'h0c29;
				11'd844: cabac_init_mn = 16'h0d29;
				11'd845: cabac_init_mn = 16'h003b;
				11'd846: cabac_init_mn = 16'h0332;
				11'd847: cabac_init_mn = 16'h1328;
				11'd848: cabac_init_mn = 16'h0342;
				11'd849: cabac_init_mn = 16'h1232;
				11'd850: cabac_init_mn = 16'h13fa;
				11'd851: cabac_init_mn = 16'h12fa;
				11'd852: cabac_init_mn = 16'h0e00;
				11'd853: cabac_init_mn = 16'h1af4;
				11'd854: cabac_init_mn = 16'h1ff0;
				11'd855: cabac_init_mn = 16'h21e7;
				11'd856: cabac_init_mn = 16'h21ea;
				11'd857: cabac_init_mn = 16'h25e4;
				11'd858: cabac_init_mn = 16'h27e2;
				11'd859: cabac_init_mn = 16'h2ae2;
				11'd860: cabac_init_mn = 16'h2fd6;
				11'd861: cabac_init_mn = 16'h2ddc;
				11'd862: cabac_init_mn = 16'h31de;
				11'd863: cabac_init_mn = 16'h29ef;
				11'd864: cabac_init_mn = 16'h2009;
				11'd865: cabac_init_mn = 16'h45b9;
				11'd866: cabac_init_mn = 16'h3fc1;
				11'd867: cabac_init_mn = 16'h42c0;
				11'd868: cabac_init_mn = 16'h4db6;
				11'd869: cabac_init_mn = 16'h36d9;
				11'd870: cabac_init_mn = 16'h34dd;
				11'd871: cabac_init_mn = 16'h29f6;
				11'd872: cabac_init_mn = 16'h2400;
				11'd873: cabac_init_mn = 16'h28ff;
				11'd874: cabac_init_mn = 16'h1e0e;
				11'd875: cabac_init_mn = 16'h1c1a;
				11'd876: cabac_init_mn = 16'h1725;
				11'd877: cabac_init_mn = 16'h0c37;
				11'd878: cabac_init_mn = 16'h0b41;
				11'd879: cabac_init_mn = 16'h25df;
				11'd880: cabac_init_mn = 16'h27dc;
				11'd881: cabac_init_mn = 16'h28db;
				11'd882: cabac_init_mn = 16'h26e2;
				11'd883: cabac_init_mn = 16'h2edf;
				11'd884: cabac_init_mn = 16'h2ae2;
				11'd885: cabac_init_mn = 16'h28e8;
				11'd886: cabac_init_mn = 16'h31e3;
				11'd887: cabac_init_mn = 16'h26f4;
				11'd888: cabac_init_mn = 16'h28f6;
				11'd889: cabac_init_mn = 16'h26fd;
				11'd890: cabac_init_mn = 16'h2efb;
				11'd891: cabac_init_mn = 16'h1f14;
				11'd892: cabac_init_mn = 16'h1d1e;
				11'd893: cabac_init_mn = 16'h192c;
				11'd894: cabac_init_mn = 16'h0c30;
				11'd895: cabac_init_mn = 16'h0b31;
				11'd896: cabac_init_mn = 16'h1a2d;
				11'd897: cabac_init_mn = 16'h1616;
				11'd898: cabac_init_mn = 16'h1716;
				11'd899: cabac_init_mn = 16'h1b15;
				11'd900: cabac_init_mn = 16'h2114;
				11'd901: cabac_init_mn = 16'h1a1c;
				11'd902: cabac_init_mn = 16'h1e18;
				11'd903: cabac_init_mn = 16'h1b22;
				11'd904: cabac_init_mn = 16'h122a;
				11'd905: cabac_init_mn = 16'h1927;
				11'd906: cabac_init_mn = 16'h1232;
				11'd907: cabac_init_mn = 16'h0c46;
				11'd908: cabac_init_mn = 16'h1536;
				11'd909: cabac_init_mn = 16'h0e47;
				11'd910: cabac_init_mn = 16'h0b53;
				11'd911: cabac_init_mn = 16'h1920;
				11'd912: cabac_init_mn = 16'h1531;
				11'd913: cabac_init_mn = 16'h1536;
				11'd914: cabac_init_mn = 16'hfb55;
				11'd915: cabac_init_mn = 16'hfa51;
				11'd916: cabac_init_mn = 16'hf64d;
				11'd917: cabac_init_mn = 16'hf951;
				11'd918: cabac_init_mn = 16'hef50;
				11'd919: cabac_init_mn = 16'hee49;
				11'd920: cabac_init_mn = 16'hfc4a;
				11'd921: cabac_init_mn = 16'hf653;
				11'd922: cabac_init_mn = 16'hf747;
				11'd923: cabac_init_mn = 16'hf743;
				11'd924: cabac_init_mn = 16'hff3d;
				11'd925: cabac_init_mn = 16'hf842;
				11'd926: cabac_init_mn = 16'hf242;
				11'd927: cabac_init_mn = 16'h003b;
				11'd928: cabac_init_mn = 16'h023b;
				11'd929: cabac_init_mn = 16'h11f6;
				11'd930: cabac_init_mn = 16'h20f3;
				11'd931: cabac_init_mn = 16'h2af7;
				11'd932: cabac_init_mn = 16'h31fb;
				11'd933: cabac_init_mn = 16'h3500;
				11'd934: cabac_init_mn = 16'h4003;
				11'd935: cabac_init_mn = 16'h440a;
				11'd936: cabac_init_mn = 16'h421b;
				11'd937: cabac_init_mn = 16'h2f39;
				11'd938: cabac_init_mn = 16'hfb47;
				11'd939: cabac_init_mn = 16'h0018;
				11'd940: cabac_init_mn = 16'hff24;
				11'd941: cabac_init_mn = 16'hfe2a;
				11'd942: cabac_init_mn = 16'hfe34;
				11'd943: cabac_init_mn = 16'hf739;
				11'd944: cabac_init_mn = 16'hfa3f;
				11'd945: cabac_init_mn = 16'hfc41;
				11'd946: cabac_init_mn = 16'hfc43;
				11'd947: cabac_init_mn = 16'hf952;
				11'd1024: cabac_init_mn = 16'h14f1;
				11'd1025: cabac_init_mn = 16'h0236;
				11'd1026: cabac_init_mn = 16'h034a;
				11'd1027: cabac_init_mn = 16'h14f1;
				11'd1028: cabac_init_mn = 16'h0236;
				11'd1029: cabac_init_mn = 16'h034a;
				11'd1030: cabac_init_mn = 16'he47f;
				11'd1031: cabac_init_mn = 16'he968;
				11'd1032: cabac_init_mn = 16'hfa35;
				11'd1033: cabac_init_mn = 16'hff36;
				11'd1034: cabac_init_mn = 16'h0733;
				11'd1035: cabac_init_mn = 16'h1d10;
				11'd1036: cabac_init_mn = 16'h1900;
				11'd1037: cabac_init_mn = 16'h0e00;
				11'd1038: cabac_init_mn = 16'hf633;
				11'd1039: cabac_init_mn = 16'hfd3e;
				11'd1040: cabac_init_mn = 16'he563;
				11'd1041: cabac_init_mn = 16'h1a10;
				11'd1042: cabac_init_mn = 16'hfc55;
				11'd1043: cabac_init_mn = 16'he866;
				11'd1044: cabac_init_mn = 16'h0539;
				11'd1045: cabac_init_mn = 16'h0639;
				11'd1046: cabac_init_mn = 16'hef49;
				11'd1047: cabac_init_mn = 16'h0e39;
				11'd1048: cabac_init_mn = 16'h1428;
				11'd1049: cabac_init_mn = 16'h140a;
				11'd1050: cabac_init_mn = 16'h1d00;
				11'd1051: cabac_init_mn = 16'h3600;
				11'd1052: cabac_init_mn = 16'h252a;
				11'd1053: cabac_init_mn = 16'h0c61;
				11'd1054: cabac_init_mn = 16'he07f;
				11'd1055: cabac_init_mn = 16'hea75;
				11'd1056: cabac_init_mn = 16'hfe4a;
				11'd1057: cabac_init_mn = 16'hfc55;
				11'd1058: cabac_init_mn = 16'he866;
				11'd1059: cabac_init_mn = 16'h0539;
				11'd1060: cabac_init_mn = 16'hfa5d;
				11'd1061: cabac_init_mn = 16'hf258;
				11'd1062: cabac_init_mn = 16'hfa2c;
				11'd1063: cabac_init_mn = 16'h0437;
				11'd1064: cabac_init_mn = 16'hf559;
				11'd1065: cabac_init_mn = 16'hf167;
				11'd1066: cabac_init_mn = 16'heb74;
				11'd1067: cabac_init_mn = 16'h1339;
				11'd1068: cabac_init_mn = 16'h143a;
				11'd1069: cabac_init_mn = 16'h0454;
				11'd1070: cabac_init_mn = 16'h0660;
				11'd1071: cabac_init_mn = 16'h013f;
				11'd1072: cabac_init_mn = 16'hfb55;
				11'd1073: cabac_init_mn = 16'hf36a;
				11'd1074: cabac_init_mn = 16'h053f;
				11'd1075: cabac_init_mn = 16'h064b;
				11'd1076: cabac_init_mn = 16'hfd5a;
				11'd1077: cabac_init_mn = 16'hff65;
				11'd1078: cabac_init_mn = 16'h0337;
				11'd1079: cabac_init_mn = 16'hfc4f;
				11'd1080: cabac_init_mn = 16'hfe4b;
				11'd1081: cabac_init_mn = 16'hf461;
				11'd1082: cabac_init_mn = 16'hf932;
				11'd1083: cabac_init_mn = 16'h013c;
				11'd1084: cabac_init_mn = 16'h0029;
				11'd1085: cabac_init_mn = 16'h003f;
				11'd1086: cabac_init_mn = 16'h003f;
				11'd1087: cabac_init_mn = 16'h003f;
				11'd1088: cabac_init_mn = 16'hf753;
				11'd1089: cabac_init_mn = 16'h0456;
				11'd1090: cabac_init_mn = 16'h0061;
				11'd1091: cabac_init_mn = 16'hf948;
				11'd1092: cabac_init_mn = 16'h0d29;
				11'd1093: cabac_init_mn = 16'h033e;
				11'd1094: cabac_init_mn = 16'h0722;
				11'd1095: cabac_init_mn = 16'hf758;
				11'd1096: cabac_init_mn = 16'hec7f;
				11'd1097: cabac_init_mn = 16'hdc7f;
				11'd1098: cabac_init_mn = 16'hef5b;
				11'd1099: cabac_init_mn = 16'hf25f;
				11'd1100: cabac_init_mn = 16'he754;
				11'd1101: cabac_init_mn = 16'he756;
				11'd1102: cabac_init_mn = 16'hf459;
				11'd1103: cabac_init_mn = 16'hef5b;
				11'd1104: cabac_init_mn = 16'he17f;
				11'd1105: cabac_init_mn = 16'hf24c;
				11'd1106: cabac_init_mn = 16'hee67;
				11'd1107: cabac_init_mn = 16'hf35a;
				11'd1108: cabac_init_mn = 16'hdb7f;
				11'd1109: cabac_init_mn = 16'h0b50;
				11'd1110: cabac_init_mn = 16'h054c;
				11'd1111: cabac_init_mn = 16'h0254;
				11'd1112: cabac_init_mn = 16'h054e;
				11'd1113: cabac_init_mn = 16'hfa37;
				11'd1114: cabac_init_mn = 16'h043d;
				11'd1115: cabac_init_mn = 16'hf253;
				11'd1116: cabac_init_mn = 16'hdb7f;
				11'd1117: cabac_init_mn = 16'hfb4f;
				11'd1118: cabac_init_mn = 16'hf568;
				11'd1119: cabac_init_mn = 16'hf55b;
				11'd1120: cabac_init_mn = 16'he27f;
				11'd1121: cabac_init_mn = 16'h0041;
				11'd1122: cabac_init_mn = 16'hfe4f;
				11'd1123: cabac_init_mn = 16'h0048;
				11'd1124: cabac_init_mn = 16'hfc5c;
				11'd1125: cabac_init_mn = 16'hfa38;
				11'd1126: cabac_init_mn = 16'h0344;
				11'd1127: cabac_init_mn = 16'hf847;
				11'd1128: cabac_init_mn = 16'hf362;
				11'd1129: cabac_init_mn = 16'hfc56;
				11'd1130: cabac_init_mn = 16'hf458;
				11'd1131: cabac_init_mn = 16'hfb52;
				11'd1132: cabac_init_mn = 16'hfd48;
				11'd1133: cabac_init_mn = 16'hfc43;
				11'd1134: cabac_init_mn = 16'hf848;
				11'd1135: cabac_init_mn = 16'hf059;
				11'd1136: cabac_init_mn = 16'hf745;
				11'd1137: cabac_init_mn = 16'hff3b;
				11'd1138: cabac_init_mn = 16'h0542;
				11'd1139: cabac_init_mn = 16'h0439;
				11'd1140: cabac_init_mn = 16'hfc47;
				11'd1141: cabac_init_mn = 16'hfe47;
				11'd1142: cabac_init_mn = 16'h023a;
				11'd1143: cabac_init_mn = 16'hff4a;
				11'd1144: cabac_init_mn = 16'hfc2c;
				11'd1145: cabac_init_mn = 16'hff45;
				11'd1146: cabac_init_mn = 16'h003e;
				11'd1147: cabac_init_mn = 16'hf933;
				11'd1148: cabac_init_mn = 16'hfc2f;
				11'd1149: cabac_init_mn = 16'hfa2a;
				11'd1150: cabac_init_mn = 16'hfd29;
				11'd1151: cabac_init_mn = 16'hfa35;
				11'd1152: cabac_init_mn = 16'h084c;
				11'd1153: cabac_init_mn = 16'hf74e;
				11'd1154: cabac_init_mn = 16'hf553;
				11'd1155: cabac_init_mn = 16'h0934;
				11'd1156: cabac_init_mn = 16'h0043;
				11'd1157: cabac_init_mn = 16'hfb5a;
				11'd1158: cabac_init_mn = 16'h0143;
				11'd1159: cabac_init_mn = 16'hf148;
				11'd1160: cabac_init_mn = 16'hfb4b;
				11'd1161: cabac_init_mn = 16'hf850;
				11'd1162: cabac_init_mn = 16'heb53;
				11'd1163: cabac_init_mn = 16'heb40;
				11'd1164: cabac_init_mn = 16'hf31f;
				11'd1165: cabac_init_mn = 16'he740;
				11'd1166: cabac_init_mn = 16'he35e;
				11'd1167: cabac_init_mn = 16'h094b;
				11'd1168: cabac_init_mn = 16'h113f;
				11'd1169: cabac_init_mn = 16'hf84a;
				11'd1170: cabac_init_mn = 16'hfb23;
				11'd1171: cabac_init_mn = 16'hfe1b;
				11'd1172: cabac_init_mn = 16'h0d5b;
				11'd1173: cabac_init_mn = 16'h0341;
				11'd1174: cabac_init_mn = 16'hf945;
				11'd1175: cabac_init_mn = 16'h084d;
				11'd1176: cabac_init_mn = 16'hf642;
				11'd1177: cabac_init_mn = 16'h033e;
				11'd1178: cabac_init_mn = 16'hfd44;
				11'd1179: cabac_init_mn = 16'hec51;
				11'd1180: cabac_init_mn = 16'h001e;
				11'd1181: cabac_init_mn = 16'h0107;
				11'd1182: cabac_init_mn = 16'hfd17;
				11'd1183: cabac_init_mn = 16'heb4a;
				11'd1184: cabac_init_mn = 16'h1042;
				11'd1185: cabac_init_mn = 16'he97c;
				11'd1186: cabac_init_mn = 16'h1125;
				11'd1187: cabac_init_mn = 16'h2cee;
				11'd1188: cabac_init_mn = 16'h32de;
				11'd1189: cabac_init_mn = 16'hea7f;
				11'd1190: cabac_init_mn = 16'h0427;
				11'd1191: cabac_init_mn = 16'h002a;
				11'd1192: cabac_init_mn = 16'h0722;
				11'd1193: cabac_init_mn = 16'h0b1d;
				11'd1194: cabac_init_mn = 16'h081f;
				11'd1195: cabac_init_mn = 16'h0625;
				11'd1196: cabac_init_mn = 16'h072a;
				11'd1197: cabac_init_mn = 16'h0328;
				11'd1198: cabac_init_mn = 16'h0821;
				11'd1199: cabac_init_mn = 16'h0d2b;
				11'd1200: cabac_init_mn = 16'h0d24;
				11'd1201: cabac_init_mn = 16'h042f;
				11'd1202: cabac_init_mn = 16'h0337;
				11'd1203: cabac_init_mn = 16'h023a;
				11'd1204: cabac_init_mn = 16'h063c;
				11'd1205: cabac_init_mn = 16'h082c;
				11'd1206: cabac_init_mn = 16'h0b2c;
				11'd1207: cabac_init_mn = 16'h0e2a;
				11'd1208: cabac_init_mn = 16'h0730;
				11'd1209: cabac_init_mn = 16'h0438;
				11'd1210: cabac_init_mn = 16'h0434;
				11'd1211: cabac_init_mn = 16'h0d25;
				11'd1212: cabac_init_mn = 16'h0931;
				11'd1213: cabac_init_mn = 16'h133a;
				11'd1214: cabac_init_mn = 16'h0a30;
				11'd1215: cabac_init_mn = 16'h0c2d;
				11'd1216: cabac_init_mn = 16'h0045;
				11'd1217: cabac_init_mn = 16'h1421;
				11'd1218: cabac_init_mn = 16'h083f;
				11'd1219: cabac_init_mn = 16'h23ee;
				11'd1220: cabac_init_mn = 16'h21e7;
				11'd1221: cabac_init_mn = 16'h1cfd;
				11'd1222: cabac_init_mn = 16'h180a;
				11'd1223: cabac_init_mn = 16'h1b00;
				11'd1224: cabac_init_mn = 16'h22f2;
				11'd1225: cabac_init_mn = 16'h34d4;
				11'd1226: cabac_init_mn = 16'h27e8;
				11'd1227: cabac_init_mn = 16'h1311;
				11'd1228: cabac_init_mn = 16'h1f19;
				11'd1229: cabac_init_mn = 16'h241d;
				11'd1230: cabac_init_mn = 16'h1821;
				11'd1231: cabac_init_mn = 16'h220f;
				11'd1232: cabac_init_mn = 16'h1e14;
				11'd1233: cabac_init_mn = 16'h1649;
				11'd1234: cabac_init_mn = 16'h1422;
				11'd1235: cabac_init_mn = 16'h131f;
				11'd1236: cabac_init_mn = 16'h1b2c;
				11'd1237: cabac_init_mn = 16'h1310;
				11'd1238: cabac_init_mn = 16'h0f24;
				11'd1239: cabac_init_mn = 16'h0f24;
				11'd1240: cabac_init_mn = 16'h151c;
				11'd1241: cabac_init_mn = 16'h1915;
				11'd1242: cabac_init_mn = 16'h1e14;
				11'd1243: cabac_init_mn = 16'h1f0c;
				11'd1244: cabac_init_mn = 16'h1b10;
				11'd1245: cabac_init_mn = 16'h182a;
				11'd1246: cabac_init_mn = 16'h005d;
				11'd1247: cabac_init_mn = 16'h0e38;
				11'd1248: cabac_init_mn = 16'h0f39;
				11'd1249: cabac_init_mn = 16'h1a26;
				11'd1250: cabac_init_mn = 16'he87f;
				11'd1251: cabac_init_mn = 16'he873;
				11'd1252: cabac_init_mn = 16'hea52;
				11'd1253: cabac_init_mn = 16'hf73e;
				11'd1254: cabac_init_mn = 16'h0035;
				11'd1255: cabac_init_mn = 16'h003b;
				11'd1256: cabac_init_mn = 16'hf255;
				11'd1257: cabac_init_mn = 16'hf359;
				11'd1258: cabac_init_mn = 16'hf35e;
				11'd1259: cabac_init_mn = 16'hf55c;
				11'd1260: cabac_init_mn = 16'he37f;
				11'd1261: cabac_init_mn = 16'heb64;
				11'd1262: cabac_init_mn = 16'hf239;
				11'd1263: cabac_init_mn = 16'hf443;
				11'd1264: cabac_init_mn = 16'hf547;
				11'd1265: cabac_init_mn = 16'hf64d;
				11'd1266: cabac_init_mn = 16'heb55;
				11'd1267: cabac_init_mn = 16'hf058;
				11'd1268: cabac_init_mn = 16'he968;
				11'd1269: cabac_init_mn = 16'hf162;
				11'd1270: cabac_init_mn = 16'hdb7f;
				11'd1271: cabac_init_mn = 16'hf652;
				11'd1272: cabac_init_mn = 16'hf830;
				11'd1273: cabac_init_mn = 16'hf83d;
				11'd1274: cabac_init_mn = 16'hf842;
				11'd1275: cabac_init_mn = 16'hf946;
				11'd1276: cabac_init_mn = 16'hf24b;
				11'd1277: cabac_init_mn = 16'hf64f;
				11'd1278: cabac_init_mn = 16'hf753;
				11'd1279: cabac_init_mn = 16'hf45c;
				11'd1280: cabac_init_mn = 16'hee6c;
				11'd1281: cabac_init_mn = 16'hfc4f;
				11'd1282: cabac_init_mn = 16'hea45;
				11'd1283: cabac_init_mn = 16'hf04b;
				11'd1284: cabac_init_mn = 16'hfe3a;
				11'd1285: cabac_init_mn = 16'h013a;
				11'd1286: cabac_init_mn = 16'hf34e;
				11'd1287: cabac_init_mn = 16'hf753;
				11'd1288: cabac_init_mn = 16'hfc51;
				11'd1289: cabac_init_mn = 16'hf363;
				11'd1290: cabac_init_mn = 16'hf351;
				11'd1291: cabac_init_mn = 16'hfa26;
				11'd1292: cabac_init_mn = 16'hf33e;
				11'd1293: cabac_init_mn = 16'hfa3a;
				11'd1294: cabac_init_mn = 16'hfe3b;
				11'd1295: cabac_init_mn = 16'hf049;
				11'd1296: cabac_init_mn = 16'hf64c;
				11'd1297: cabac_init_mn = 16'hf356;
				11'd1298: cabac_init_mn = 16'hf753;
				11'd1299: cabac_init_mn = 16'hf657;
				11'd1300: cabac_init_mn = 16'h0000;
				11'd1301: cabac_init_mn = 16'hea7f;
				11'd1302: cabac_init_mn = 16'he77f;
				11'd1303: cabac_init_mn = 16'he778;
				11'd1304: cabac_init_mn = 16'he57f;
				11'd1305: cabac_init_mn = 16'hed72;
				11'd1306: cabac_init_mn = 16'he975;
				11'd1307: cabac_init_mn = 16'he776;
				11'd1308: cabac_init_mn = 16'he675;
				11'd1309: cabac_init_mn = 16'he871;
				11'd1310: cabac_init_mn = 16'he476;
				11'd1311: cabac_init_mn = 16'he178;
				11'd1312: cabac_init_mn = 16'hdb7c;
				11'd1313: cabac_init_mn = 16'hf65e;
				11'd1314: cabac_init_mn = 16'hf166;
				11'd1315: cabac_init_mn = 16'hf663;
				11'd1316: cabac_init_mn = 16'hf36a;
				11'd1317: cabac_init_mn = 16'hce7f;
				11'd1318: cabac_init_mn = 16'hfb5c;
				11'd1319: cabac_init_mn = 16'h1139;
				11'd1320: cabac_init_mn = 16'hfb56;
				11'd1321: cabac_init_mn = 16'hf35e;
				11'd1322: cabac_init_mn = 16'hf45b;
				11'd1323: cabac_init_mn = 16'hfe4d;
				11'd1324: cabac_init_mn = 16'h0047;
				11'd1325: cabac_init_mn = 16'hff49;
				11'd1326: cabac_init_mn = 16'h0440;
				11'd1327: cabac_init_mn = 16'hf951;
				11'd1328: cabac_init_mn = 16'h0540;
				11'd1329: cabac_init_mn = 16'h0f39;
				11'd1330: cabac_init_mn = 16'h0143;
				11'd1331: cabac_init_mn = 16'h0044;
				11'd1332: cabac_init_mn = 16'hf643;
				11'd1333: cabac_init_mn = 16'h0144;
				11'd1334: cabac_init_mn = 16'h004d;
				11'd1335: cabac_init_mn = 16'h0240;
				11'd1336: cabac_init_mn = 16'h0044;
				11'd1337: cabac_init_mn = 16'hfb4e;
				11'd1338: cabac_init_mn = 16'h0737;
				11'd1339: cabac_init_mn = 16'h053b;
				11'd1340: cabac_init_mn = 16'h0241;
				11'd1341: cabac_init_mn = 16'h0e36;
				11'd1342: cabac_init_mn = 16'h0f2c;
				11'd1343: cabac_init_mn = 16'h053c;
				11'd1344: cabac_init_mn = 16'h0246;
				11'd1345: cabac_init_mn = 16'hfe4c;
				11'd1346: cabac_init_mn = 16'hee56;
				11'd1347: cabac_init_mn = 16'h0c46;
				11'd1348: cabac_init_mn = 16'h0540;
				11'd1349: cabac_init_mn = 16'hf446;
				11'd1350: cabac_init_mn = 16'h0b37;
				11'd1351: cabac_init_mn = 16'h0538;
				11'd1352: cabac_init_mn = 16'h0045;
				11'd1353: cabac_init_mn = 16'h0241;
				11'd1354: cabac_init_mn = 16'hfa4a;
				11'd1355: cabac_init_mn = 16'h0536;
				11'd1356: cabac_init_mn = 16'h0736;
				11'd1357: cabac_init_mn = 16'hfa4c;
				11'd1358: cabac_init_mn = 16'hf552;
				11'd1359: cabac_init_mn = 16'hfe4d;
				11'd1360: cabac_init_mn = 16'hfe4d;
				11'd1361: cabac_init_mn = 16'h192a;
				11'd1362: cabac_init_mn = 16'h11f3;
				11'd1363: cabac_init_mn = 16'h10f7;
				11'd1364: cabac_init_mn = 16'h11f4;
				11'd1365: cabac_init_mn = 16'h1beb;
				11'd1366: cabac_init_mn = 16'h25e2;
				11'd1367: cabac_init_mn = 16'h29d8;
				11'd1368: cabac_init_mn = 16'h2ad7;
				11'd1369: cabac_init_mn = 16'h30d1;
				11'd1370: cabac_init_mn = 16'h27e0;
				11'd1371: cabac_init_mn = 16'h2ed8;
				11'd1372: cabac_init_mn = 16'h34cd;
				11'd1373: cabac_init_mn = 16'h2ed7;
				11'd1374: cabac_init_mn = 16'h34d9;
				11'd1375: cabac_init_mn = 16'h2bed;
				11'd1376: cabac_init_mn = 16'h200b;
				11'd1377: cabac_init_mn = 16'h3dc9;
				11'd1378: cabac_init_mn = 16'h38d2;
				11'd1379: cabac_init_mn = 16'h3ece;
				11'd1380: cabac_init_mn = 16'h51bd;
				11'd1381: cabac_init_mn = 16'h2dec;
				11'd1382: cabac_init_mn = 16'h23fe;
				11'd1383: cabac_init_mn = 16'h1c0f;
				11'd1384: cabac_init_mn = 16'h2201;
				11'd1385: cabac_init_mn = 16'h2701;
				11'd1386: cabac_init_mn = 16'h1e11;
				11'd1387: cabac_init_mn = 16'h1426;
				11'd1388: cabac_init_mn = 16'h122d;
				11'd1389: cabac_init_mn = 16'h0f36;
				11'd1390: cabac_init_mn = 16'h004f;
				11'd1391: cabac_init_mn = 16'h24f0;
				11'd1392: cabac_init_mn = 16'h25f2;
				11'd1393: cabac_init_mn = 16'h25ef;
				11'd1394: cabac_init_mn = 16'h2001;
				11'd1395: cabac_init_mn = 16'h220f;
				11'd1396: cabac_init_mn = 16'h1d0f;
				11'd1397: cabac_init_mn = 16'h1819;
				11'd1398: cabac_init_mn = 16'h2216;
				11'd1399: cabac_init_mn = 16'h1f10;
				11'd1400: cabac_init_mn = 16'h2312;
				11'd1401: cabac_init_mn = 16'h1f1c;
				11'd1402: cabac_init_mn = 16'h2129;
				11'd1403: cabac_init_mn = 16'h241c;
				11'd1404: cabac_init_mn = 16'h1b2f;
				11'd1405: cabac_init_mn = 16'h153e;
				11'd1406: cabac_init_mn = 16'h121f;
				11'd1407: cabac_init_mn = 16'h131a;
				11'd1408: cabac_init_mn = 16'h2418;
				11'd1409: cabac_init_mn = 16'h1817;
				11'd1410: cabac_init_mn = 16'h1b10;
				11'd1411: cabac_init_mn = 16'h181e;
				11'd1412: cabac_init_mn = 16'h1f1d;
				11'd1413: cabac_init_mn = 16'h1629;
				11'd1414: cabac_init_mn = 16'h162a;
				11'd1415: cabac_init_mn = 16'h103c;
				11'd1416: cabac_init_mn = 16'h0f34;
				11'd1417: cabac_init_mn = 16'h0e3c;
				11'd1418: cabac_init_mn = 16'h034e;
				11'd1419: cabac_init_mn = 16'hf07b;
				11'd1420: cabac_init_mn = 16'h1535;
				11'd1421: cabac_init_mn = 16'h1638;
				11'd1422: cabac_init_mn = 16'h193d;
				11'd1423: cabac_init_mn = 16'h1521;
				11'd1424: cabac_init_mn = 16'h1332;
				11'd1425: cabac_init_mn = 16'h113d;
				11'd1426: cabac_init_mn = 16'hfd4e;
				11'd1427: cabac_init_mn = 16'hf84a;
				11'd1428: cabac_init_mn = 16'hf748;
				11'd1429: cabac_init_mn = 16'hf648;
				11'd1430: cabac_init_mn = 16'hee4b;
				11'd1431: cabac_init_mn = 16'hf447;
				11'd1432: cabac_init_mn = 16'hf53f;
				11'd1433: cabac_init_mn = 16'hfb46;
				11'd1434: cabac_init_mn = 16'hef4b;
				11'd1435: cabac_init_mn = 16'hf248;
				11'd1436: cabac_init_mn = 16'hf043;
				11'd1437: cabac_init_mn = 16'hf835;
				11'd1438: cabac_init_mn = 16'hf23b;
				11'd1439: cabac_init_mn = 16'hf734;
				11'd1440: cabac_init_mn = 16'hf544;
				11'd1441: cabac_init_mn = 16'h09fe;
				11'd1442: cabac_init_mn = 16'h1ef6;
				11'd1443: cabac_init_mn = 16'h1ffc;
				11'd1444: cabac_init_mn = 16'h21ff;
				11'd1445: cabac_init_mn = 16'h2107;
				11'd1446: cabac_init_mn = 16'h1f0c;
				11'd1447: cabac_init_mn = 16'h2517;
				11'd1448: cabac_init_mn = 16'h1f26;
				11'd1449: cabac_init_mn = 16'h1440;
				11'd1450: cabac_init_mn = 16'hf747;
				11'd1451: cabac_init_mn = 16'hf925;
				11'd1452: cabac_init_mn = 16'hf82c;
				11'd1453: cabac_init_mn = 16'hf531;
				11'd1454: cabac_init_mn = 16'hf638;
				11'd1455: cabac_init_mn = 16'hf43b;
				11'd1456: cabac_init_mn = 16'hf83f;
				11'd1457: cabac_init_mn = 16'hf743;
				11'd1458: cabac_init_mn = 16'hfa44;
				11'd1459: cabac_init_mn = 16'hf64f;
				11'd1536: cabac_init_mn = 16'h14f1;
				11'd1537: cabac_init_mn = 16'h0236;
				11'd1538: cabac_init_mn = 16'h034a;
				11'd1539: cabac_init_mn = 16'h14f1;
				11'd1540: cabac_init_mn = 16'h0236;
				11'd1541: cabac_init_mn = 16'h034a;
				11'd1542: cabac_init_mn = 16'he47f;
				11'd1543: cabac_init_mn = 16'he968;
				11'd1544: cabac_init_mn = 16'hfa35;
				11'd1545: cabac_init_mn = 16'hff36;
				11'd1546: cabac_init_mn = 16'h0733;
				11'd1547: cabac_init_mn = 16'h0000;
				11'd1548: cabac_init_mn = 16'h0000;
				11'd1549: cabac_init_mn = 16'h0000;
				11'd1550: cabac_init_mn = 16'h0000;
				11'd1551: cabac_init_mn = 16'h0000;
				11'd1552: cabac_init_mn = 16'h0000;
				11'd1553: cabac_init_mn = 16'h0000;
				11'd1554: cabac_init_mn = 16'h0000;
				11'd1555: cabac_init_mn = 16'h0000;
				11'd1556: cabac_init_mn = 16'h0000;
				11'd1557: cabac_init_mn = 16'h0000;
				11'd1558: cabac_init_mn = 16'h0000;
				11'd1559: cabac_init_mn = 16'h0000;
				11'd1560: cabac_init_mn = 16'h0000;
				11'd1561: cabac_init_mn = 16'h0000;
				11'd1562: cabac_init_mn = 16'h0000;
				11'd1563: cabac_init_mn = 16'h0000;
				11'd1564: cabac_init_mn = 16'h0000;
				11'd1565: cabac_init_mn = 16'h0000;
				11'd1566: cabac_init_mn = 16'h0000;
				11'd1567: cabac_init_mn = 16'h0000;
				11'd1568: cabac_init_mn = 16'h0000;
				11'd1569: cabac_init_mn = 16'h0000;
				11'd1570: cabac_init_mn = 16'h0000;
				11'd1571: cabac_init_mn = 16'h0000;
				11'd1572: cabac_init_mn = 16'h0000;
				11'd1573: cabac_init_mn = 16'h0000;
				11'd1574: cabac_init_mn = 16'h0000;
				11'd1575: cabac_init_mn = 16'h0000;
				11'd1576: cabac_init_mn = 16'h0000;
				11'd1577: cabac_init_mn = 16'h0000;
				11'd1578: cabac_init_mn = 16'h0000;
				11'd1579: cabac_init_mn = 16'h0000;
				11'd1580: cabac_init_mn = 16'h0000;
				11'd1581: cabac_init_mn = 16'h0000;
				11'd1582: cabac_init_mn = 16'h0000;
				11'd1583: cabac_init_mn = 16'h0000;
				11'd1584: cabac_init_mn = 16'h0000;
				11'd1585: cabac_init_mn = 16'h0000;
				11'd1586: cabac_init_mn = 16'h0000;
				11'd1587: cabac_init_mn = 16'h0000;
				11'd1588: cabac_init_mn = 16'h0000;
				11'd1589: cabac_init_mn = 16'h0000;
				11'd1590: cabac_init_mn = 16'h0000;
				11'd1591: cabac_init_mn = 16'h0000;
				11'd1592: cabac_init_mn = 16'h0000;
				11'd1593: cabac_init_mn = 16'h0000;
				11'd1594: cabac_init_mn = 16'h0000;
				11'd1595: cabac_init_mn = 16'h0000;
				11'd1596: cabac_init_mn = 16'h0029;
				11'd1597: cabac_init_mn = 16'h003f;
				11'd1598: cabac_init_mn = 16'h003f;
				11'd1599: cabac_init_mn = 16'h003f;
				11'd1600: cabac_init_mn = 16'hf753;
				11'd1601: cabac_init_mn = 16'h0456;
				11'd1602: cabac_init_mn = 16'h0061;
				11'd1603: cabac_init_mn = 16'hf948;
				11'd1604: cabac_init_mn = 16'h0d29;
				11'd1605: cabac_init_mn = 16'h033e;
				11'd1606: cabac_init_mn = 16'h000b;
				11'd1607: cabac_init_mn = 16'h0137;
				11'd1608: cabac_init_mn = 16'h0045;
				11'd1609: cabac_init_mn = 16'hef7f;
				11'd1610: cabac_init_mn = 16'hf366;
				11'd1611: cabac_init_mn = 16'h0052;
				11'd1612: cabac_init_mn = 16'hf94a;
				11'd1613: cabac_init_mn = 16'heb6b;
				11'd1614: cabac_init_mn = 16'he57f;
				11'd1615: cabac_init_mn = 16'he17f;
				11'd1616: cabac_init_mn = 16'he87f;
				11'd1617: cabac_init_mn = 16'hee5f;
				11'd1618: cabac_init_mn = 16'he57f;
				11'd1619: cabac_init_mn = 16'heb72;
				11'd1620: cabac_init_mn = 16'he27f;
				11'd1621: cabac_init_mn = 16'hef7b;
				11'd1622: cabac_init_mn = 16'hf473;
				11'd1623: cabac_init_mn = 16'hf07a;
				11'd1624: cabac_init_mn = 16'hf573;
				11'd1625: cabac_init_mn = 16'hf43f;
				11'd1626: cabac_init_mn = 16'hfe44;
				11'd1627: cabac_init_mn = 16'hf154;
				11'd1628: cabac_init_mn = 16'hf368;
				11'd1629: cabac_init_mn = 16'hfd46;
				11'd1630: cabac_init_mn = 16'hf85d;
				11'd1631: cabac_init_mn = 16'hf65a;
				11'd1632: cabac_init_mn = 16'he27f;
				11'd1633: cabac_init_mn = 16'hff4a;
				11'd1634: cabac_init_mn = 16'hfa61;
				11'd1635: cabac_init_mn = 16'hf95b;
				11'd1636: cabac_init_mn = 16'hec7f;
				11'd1637: cabac_init_mn = 16'hfc38;
				11'd1638: cabac_init_mn = 16'hfb52;
				11'd1639: cabac_init_mn = 16'hf94c;
				11'd1640: cabac_init_mn = 16'hea7d;
				11'd1641: cabac_init_mn = 16'hf95d;
				11'd1642: cabac_init_mn = 16'hf557;
				11'd1643: cabac_init_mn = 16'hfd4d;
				11'd1644: cabac_init_mn = 16'hfb47;
				11'd1645: cabac_init_mn = 16'hfc3f;
				11'd1646: cabac_init_mn = 16'hfc44;
				11'd1647: cabac_init_mn = 16'hf454;
				11'd1648: cabac_init_mn = 16'hf93e;
				11'd1649: cabac_init_mn = 16'hf941;
				11'd1650: cabac_init_mn = 16'h083d;
				11'd1651: cabac_init_mn = 16'h0538;
				11'd1652: cabac_init_mn = 16'hfe42;
				11'd1653: cabac_init_mn = 16'h0140;
				11'd1654: cabac_init_mn = 16'h003d;
				11'd1655: cabac_init_mn = 16'hfe4e;
				11'd1656: cabac_init_mn = 16'h0132;
				11'd1657: cabac_init_mn = 16'h0734;
				11'd1658: cabac_init_mn = 16'h0a23;
				11'd1659: cabac_init_mn = 16'h002c;
				11'd1660: cabac_init_mn = 16'h0b26;
				11'd1661: cabac_init_mn = 16'h012d;
				11'd1662: cabac_init_mn = 16'h002e;
				11'd1663: cabac_init_mn = 16'h052c;
				11'd1664: cabac_init_mn = 16'h1f11;
				11'd1665: cabac_init_mn = 16'h0133;
				11'd1666: cabac_init_mn = 16'h0732;
				11'd1667: cabac_init_mn = 16'h1c13;
				11'd1668: cabac_init_mn = 16'h1021;
				11'd1669: cabac_init_mn = 16'h0e3e;
				11'd1670: cabac_init_mn = 16'hf36c;
				11'd1671: cabac_init_mn = 16'hf164;
				11'd1672: cabac_init_mn = 16'hf365;
				11'd1673: cabac_init_mn = 16'hf35b;
				11'd1674: cabac_init_mn = 16'hf45e;
				11'd1675: cabac_init_mn = 16'hf658;
				11'd1676: cabac_init_mn = 16'hf054;
				11'd1677: cabac_init_mn = 16'hf656;
				11'd1678: cabac_init_mn = 16'hf953;
				11'd1679: cabac_init_mn = 16'hf357;
				11'd1680: cabac_init_mn = 16'hed5e;
				11'd1681: cabac_init_mn = 16'h0146;
				11'd1682: cabac_init_mn = 16'h0048;
				11'd1683: cabac_init_mn = 16'hfb4a;
				11'd1684: cabac_init_mn = 16'h123b;
				11'd1685: cabac_init_mn = 16'hf866;
				11'd1686: cabac_init_mn = 16'hf164;
				11'd1687: cabac_init_mn = 16'h005f;
				11'd1688: cabac_init_mn = 16'hfc4b;
				11'd1689: cabac_init_mn = 16'h0248;
				11'd1690: cabac_init_mn = 16'hf54b;
				11'd1691: cabac_init_mn = 16'hfd47;
				11'd1692: cabac_init_mn = 16'h0f2e;
				11'd1693: cabac_init_mn = 16'hf345;
				11'd1694: cabac_init_mn = 16'h003e;
				11'd1695: cabac_init_mn = 16'h0041;
				11'd1696: cabac_init_mn = 16'h1525;
				11'd1697: cabac_init_mn = 16'hf148;
				11'd1698: cabac_init_mn = 16'h0939;
				11'd1699: cabac_init_mn = 16'h1036;
				11'd1700: cabac_init_mn = 16'h003e;
				11'd1701: cabac_init_mn = 16'h0c48;
				11'd1702: cabac_init_mn = 16'h1800;
				11'd1703: cabac_init_mn = 16'h0f09;
				11'd1704: cabac_init_mn = 16'h0819;
				11'd1705: cabac_init_mn = 16'h0d12;
				11'd1706: cabac_init_mn = 16'h0f09;
				11'd1707: cabac_init_mn = 16'h0d13;
				11'd1708: cabac_init_mn = 16'h0a25;
				11'd1709: cabac_init_mn = 16'h0c12;
				11'd1710: cabac_init_mn = 16'h061d;
				11'd1711: cabac_init_mn = 16'h1421;
				11'd1712: cabac_init_mn = 16'h0f1e;
				11'd1713: cabac_init_mn = 16'h042d;
				11'd1714: cabac_init_mn = 16'h013a;
				11'd1715: cabac_init_mn = 16'h003e;
				11'd1716: cabac_init_mn = 16'h073d;
				11'd1717: cabac_init_mn = 16'h0c26;
				11'd1718: cabac_init_mn = 16'h0b2d;
				11'd1719: cabac_init_mn = 16'h0f27;
				11'd1720: cabac_init_mn = 16'h0b2a;
				11'd1721: cabac_init_mn = 16'h0d2c;
				11'd1722: cabac_init_mn = 16'h102d;
				11'd1723: cabac_init_mn = 16'h0c29;
				11'd1724: cabac_init_mn = 16'h0a31;
				11'd1725: cabac_init_mn = 16'h1e22;
				11'd1726: cabac_init_mn = 16'h122a;
				11'd1727: cabac_init_mn = 16'h0a37;
				11'd1728: cabac_init_mn = 16'h1133;
				11'd1729: cabac_init_mn = 16'h112e;
				11'd1730: cabac_init_mn = 16'h0059;
				11'd1731: cabac_init_mn = 16'h1aed;
				11'd1732: cabac_init_mn = 16'h16ef;
				11'd1733: cabac_init_mn = 16'h1aef;
				11'd1734: cabac_init_mn = 16'h1ee7;
				11'd1735: cabac_init_mn = 16'h1cec;
				11'd1736: cabac_init_mn = 16'h21e9;
				11'd1737: cabac_init_mn = 16'h25e5;
				11'd1738: cabac_init_mn = 16'h21e9;
				11'd1739: cabac_init_mn = 16'h28e4;
				11'd1740: cabac_init_mn = 16'h26ef;
				11'd1741: cabac_init_mn = 16'h21f5;
				11'd1742: cabac_init_mn = 16'h28f1;
				11'd1743: cabac_init_mn = 16'h29fa;
				11'd1744: cabac_init_mn = 16'h2601;
				11'd1745: cabac_init_mn = 16'h2911;
				11'd1746: cabac_init_mn = 16'h1efa;
				11'd1747: cabac_init_mn = 16'h1b03;
				11'd1748: cabac_init_mn = 16'h1a16;
				11'd1749: cabac_init_mn = 16'h25f0;
				11'd1750: cabac_init_mn = 16'h23fc;
				11'd1751: cabac_init_mn = 16'h26f8;
				11'd1752: cabac_init_mn = 16'h26fd;
				11'd1753: cabac_init_mn = 16'h2503;
				11'd1754: cabac_init_mn = 16'h2605;
				11'd1755: cabac_init_mn = 16'h2a00;
				11'd1756: cabac_init_mn = 16'h2310;
				11'd1757: cabac_init_mn = 16'h2716;
				11'd1758: cabac_init_mn = 16'h0e30;
				11'd1759: cabac_init_mn = 16'h1b25;
				11'd1760: cabac_init_mn = 16'h153c;
				11'd1761: cabac_init_mn = 16'h0c44;
				11'd1762: cabac_init_mn = 16'h0261;
				11'd1763: cabac_init_mn = 16'hfd47;
				11'd1764: cabac_init_mn = 16'hfa2a;
				11'd1765: cabac_init_mn = 16'hfb32;
				11'd1766: cabac_init_mn = 16'hfd36;
				11'd1767: cabac_init_mn = 16'hfe3e;
				11'd1768: cabac_init_mn = 16'h003a;
				11'd1769: cabac_init_mn = 16'h013f;
				11'd1770: cabac_init_mn = 16'hfe48;
				11'd1771: cabac_init_mn = 16'hff4a;
				11'd1772: cabac_init_mn = 16'hf75b;
				11'd1773: cabac_init_mn = 16'hfb43;
				11'd1774: cabac_init_mn = 16'hfb1b;
				11'd1775: cabac_init_mn = 16'hfd27;
				11'd1776: cabac_init_mn = 16'hfe2c;
				11'd1777: cabac_init_mn = 16'h002e;
				11'd1778: cabac_init_mn = 16'hf040;
				11'd1779: cabac_init_mn = 16'hf844;
				11'd1780: cabac_init_mn = 16'hf64e;
				11'd1781: cabac_init_mn = 16'hfa4d;
				11'd1782: cabac_init_mn = 16'hf656;
				11'd1783: cabac_init_mn = 16'hf45c;
				11'd1784: cabac_init_mn = 16'hf137;
				11'd1785: cabac_init_mn = 16'hf63c;
				11'd1786: cabac_init_mn = 16'hfa3e;
				11'd1787: cabac_init_mn = 16'hfc41;
				11'd1788: cabac_init_mn = 16'hf449;
				11'd1789: cabac_init_mn = 16'hf84c;
				11'd1790: cabac_init_mn = 16'hf950;
				11'd1791: cabac_init_mn = 16'hf758;
				11'd1792: cabac_init_mn = 16'hef6e;
				11'd1793: cabac_init_mn = 16'hf561;
				11'd1794: cabac_init_mn = 16'hec54;
				11'd1795: cabac_init_mn = 16'hf54f;
				11'd1796: cabac_init_mn = 16'hfa49;
				11'd1797: cabac_init_mn = 16'hfc4a;
				11'd1798: cabac_init_mn = 16'hf356;
				11'd1799: cabac_init_mn = 16'hf360;
				11'd1800: cabac_init_mn = 16'hf561;
				11'd1801: cabac_init_mn = 16'hed75;
				11'd1802: cabac_init_mn = 16'hf84e;
				11'd1803: cabac_init_mn = 16'hfb21;
				11'd1804: cabac_init_mn = 16'hfc30;
				11'd1805: cabac_init_mn = 16'hfe35;
				11'd1806: cabac_init_mn = 16'hfd3e;
				11'd1807: cabac_init_mn = 16'hf347;
				11'd1808: cabac_init_mn = 16'hf64f;
				11'd1809: cabac_init_mn = 16'hf456;
				11'd1810: cabac_init_mn = 16'hf35a;
				11'd1811: cabac_init_mn = 16'hf261;
				11'd1812: cabac_init_mn = 16'h0000;
				11'd1813: cabac_init_mn = 16'hfa5d;
				11'd1814: cabac_init_mn = 16'hfa54;
				11'd1815: cabac_init_mn = 16'hf84f;
				11'd1816: cabac_init_mn = 16'h0042;
				11'd1817: cabac_init_mn = 16'hff47;
				11'd1818: cabac_init_mn = 16'h003e;
				11'd1819: cabac_init_mn = 16'hfe3c;
				11'd1820: cabac_init_mn = 16'hfe3b;
				11'd1821: cabac_init_mn = 16'hfb4b;
				11'd1822: cabac_init_mn = 16'hfd3e;
				11'd1823: cabac_init_mn = 16'hfc3a;
				11'd1824: cabac_init_mn = 16'hf742;
				11'd1825: cabac_init_mn = 16'hff4f;
				11'd1826: cabac_init_mn = 16'h0047;
				11'd1827: cabac_init_mn = 16'h0344;
				11'd1828: cabac_init_mn = 16'h0a2c;
				11'd1829: cabac_init_mn = 16'hf93e;
				11'd1830: cabac_init_mn = 16'h0f24;
				11'd1831: cabac_init_mn = 16'h0e28;
				11'd1832: cabac_init_mn = 16'h101b;
				11'd1833: cabac_init_mn = 16'h0c1d;
				11'd1834: cabac_init_mn = 16'h012c;
				11'd1835: cabac_init_mn = 16'h1424;
				11'd1836: cabac_init_mn = 16'h1220;
				11'd1837: cabac_init_mn = 16'h052a;
				11'd1838: cabac_init_mn = 16'h0130;
				11'd1839: cabac_init_mn = 16'h0a3e;
				11'd1840: cabac_init_mn = 16'h112e;
				11'd1841: cabac_init_mn = 16'h0940;
				11'd1842: cabac_init_mn = 16'hf468;
				11'd1843: cabac_init_mn = 16'hf561;
				11'd1844: cabac_init_mn = 16'hf060;
				11'd1845: cabac_init_mn = 16'hf958;
				11'd1846: cabac_init_mn = 16'hf855;
				11'd1847: cabac_init_mn = 16'hf955;
				11'd1848: cabac_init_mn = 16'hf755;
				11'd1849: cabac_init_mn = 16'hf358;
				11'd1850: cabac_init_mn = 16'h0442;
				11'd1851: cabac_init_mn = 16'hfd4d;
				11'd1852: cabac_init_mn = 16'hfd4c;
				11'd1853: cabac_init_mn = 16'hfa4c;
				11'd1854: cabac_init_mn = 16'h0a3a;
				11'd1855: cabac_init_mn = 16'hff4c;
				11'd1856: cabac_init_mn = 16'hff53;
				11'd1857: cabac_init_mn = 16'hf963;
				11'd1858: cabac_init_mn = 16'hf25f;
				11'd1859: cabac_init_mn = 16'h025f;
				11'd1860: cabac_init_mn = 16'h004c;
				11'd1861: cabac_init_mn = 16'hfb4a;
				11'd1862: cabac_init_mn = 16'h0046;
				11'd1863: cabac_init_mn = 16'hf54b;
				11'd1864: cabac_init_mn = 16'h0144;
				11'd1865: cabac_init_mn = 16'h0041;
				11'd1866: cabac_init_mn = 16'hf249;
				11'd1867: cabac_init_mn = 16'h033e;
				11'd1868: cabac_init_mn = 16'h043e;
				11'd1869: cabac_init_mn = 16'hff44;
				11'd1870: cabac_init_mn = 16'hf34b;
				11'd1871: cabac_init_mn = 16'h0b37;
				11'd1872: cabac_init_mn = 16'h0540;
				11'd1873: cabac_init_mn = 16'h0c46;
				11'd1874: cabac_init_mn = 16'h0f06;
				11'd1875: cabac_init_mn = 16'h0613;
				11'd1876: cabac_init_mn = 16'h0710;
				11'd1877: cabac_init_mn = 16'h0c0e;
				11'd1878: cabac_init_mn = 16'h120d;
				11'd1879: cabac_init_mn = 16'h0d0b;
				11'd1880: cabac_init_mn = 16'h0d0f;
				11'd1881: cabac_init_mn = 16'h0f10;
				11'd1882: cabac_init_mn = 16'h0c17;
				11'd1883: cabac_init_mn = 16'h0d17;
				11'd1884: cabac_init_mn = 16'h0f14;
				11'd1885: cabac_init_mn = 16'h0e1a;
				11'd1886: cabac_init_mn = 16'h0e2c;
				11'd1887: cabac_init_mn = 16'h1128;
				11'd1888: cabac_init_mn = 16'h112f;
				11'd1889: cabac_init_mn = 16'h1811;
				11'd1890: cabac_init_mn = 16'h1515;
				11'd1891: cabac_init_mn = 16'h1916;
				11'd1892: cabac_init_mn = 16'h1f1b;
				11'd1893: cabac_init_mn = 16'h161d;
				11'd1894: cabac_init_mn = 16'h1323;
				11'd1895: cabac_init_mn = 16'h0e32;
				11'd1896: cabac_init_mn = 16'h0a39;
				11'd1897: cabac_init_mn = 16'h073f;
				11'd1898: cabac_init_mn = 16'hfe4d;
				11'd1899: cabac_init_mn = 16'hfc52;
				11'd1900: cabac_init_mn = 16'hfd5e;
				11'd1901: cabac_init_mn = 16'h0945;
				11'd1902: cabac_init_mn = 16'hf46d;
				11'd1903: cabac_init_mn = 16'h24dd;
				11'd1904: cabac_init_mn = 16'h24de;
				11'd1905: cabac_init_mn = 16'h20e6;
				11'd1906: cabac_init_mn = 16'h25e2;
				11'd1907: cabac_init_mn = 16'h2ce0;
				11'd1908: cabac_init_mn = 16'h22ee;
				11'd1909: cabac_init_mn = 16'h22f1;
				11'd1910: cabac_init_mn = 16'h28f1;
				11'd1911: cabac_init_mn = 16'h21f9;
				11'd1912: cabac_init_mn = 16'h23fb;
				11'd1913: cabac_init_mn = 16'h2100;
				11'd1914: cabac_init_mn = 16'h2602;
				11'd1915: cabac_init_mn = 16'h210d;
				11'd1916: cabac_init_mn = 16'h1723;
				11'd1917: cabac_init_mn = 16'h0d3a;
				11'd1918: cabac_init_mn = 16'h1dfd;
				11'd1919: cabac_init_mn = 16'h1a00;
				11'd1920: cabac_init_mn = 16'h161e;
				11'd1921: cabac_init_mn = 16'h1ff9;
				11'd1922: cabac_init_mn = 16'h23f1;
				11'd1923: cabac_init_mn = 16'h22fd;
				11'd1924: cabac_init_mn = 16'h2203;
				11'd1925: cabac_init_mn = 16'h24ff;
				11'd1926: cabac_init_mn = 16'h2205;
				11'd1927: cabac_init_mn = 16'h200b;
				11'd1928: cabac_init_mn = 16'h2305;
				11'd1929: cabac_init_mn = 16'h220c;
				11'd1930: cabac_init_mn = 16'h270b;
				11'd1931: cabac_init_mn = 16'h1e1d;
				11'd1932: cabac_init_mn = 16'h221a;
				11'd1933: cabac_init_mn = 16'h1d27;
				11'd1934: cabac_init_mn = 16'h1342;
				11'd1935: cabac_init_mn = 16'h1f15;
				11'd1936: cabac_init_mn = 16'h1f1f;
				11'd1937: cabac_init_mn = 16'h1932;
				11'd1938: cabac_init_mn = 16'hef78;
				11'd1939: cabac_init_mn = 16'hec70;
				11'd1940: cabac_init_mn = 16'hee72;
				11'd1941: cabac_init_mn = 16'hf555;
				11'd1942: cabac_init_mn = 16'hf15c;
				11'd1943: cabac_init_mn = 16'hf259;
				11'd1944: cabac_init_mn = 16'he647;
				11'd1945: cabac_init_mn = 16'hf151;
				11'd1946: cabac_init_mn = 16'hf250;
				11'd1947: cabac_init_mn = 16'h0044;
				11'd1948: cabac_init_mn = 16'hf246;
				11'd1949: cabac_init_mn = 16'he838;
				11'd1950: cabac_init_mn = 16'he944;
				11'd1951: cabac_init_mn = 16'he832;
				11'd1952: cabac_init_mn = 16'hf54a;
				11'd1953: cabac_init_mn = 16'h17f3;
				11'd1954: cabac_init_mn = 16'h1af3;
				11'd1955: cabac_init_mn = 16'h28f1;
				11'd1956: cabac_init_mn = 16'h31f2;
				11'd1957: cabac_init_mn = 16'h2c03;
				11'd1958: cabac_init_mn = 16'h2d06;
				11'd1959: cabac_init_mn = 16'h2c22;
				11'd1960: cabac_init_mn = 16'h2136;
				11'd1961: cabac_init_mn = 16'h1352;
				11'd1962: cabac_init_mn = 16'hfd4b;
				11'd1963: cabac_init_mn = 16'hff17;
				11'd1964: cabac_init_mn = 16'h0122;
				11'd1965: cabac_init_mn = 16'h012b;
				11'd1966: cabac_init_mn = 16'h0036;
				11'd1967: cabac_init_mn = 16'hfe37;
				11'd1968: cabac_init_mn = 16'h003d;
				11'd1969: cabac_init_mn = 16'h0140;
				11'd1970: cabac_init_mn = 16'h0044;
				11'd1971: cabac_init_mn = 16'hf75c;
				default: cabac_init_mn = 16'd0;
			endcase
		end
	endfunction
	assign mn = cabac_init_mn(model_q, ictx_q);
	always @(*) begin : sv2v_autoblock_1
		reg signed [15:0] t;
		if (_sv2v_0)
			;
		t = ($signed(mn[15:8]) * $signed({10'b0000000000, init_qp})) >>> 4;
		t = t + $signed(mn[7:0]);
		if (t < 1)
			t = 1;
		if (t > 126)
			t = 126;
		pre_raw = t;
		pre = pre_raw[6:0];
	end
	wire [7:0] rlps;
	wire [8:0] r_dec;
	wire [8:0] r_mps_v;
	wire is_lps;
	wire [5:0] ps_cur;
	wire mps_cur;
	assign ps_cur = pstate[op_ctx];
	assign mps_cur = mps[op_ctx];
	function automatic [7:0] cabac_rlps;
		input reg [5:0] st;
		input reg [1:0] qi;
		(* full_case, parallel_case *)
		case ({st, qi})
			8'd0: cabac_rlps = 8'd128;
			8'd1: cabac_rlps = 8'd176;
			8'd2: cabac_rlps = 8'd208;
			8'd3: cabac_rlps = 8'd240;
			8'd4: cabac_rlps = 8'd128;
			8'd5: cabac_rlps = 8'd167;
			8'd6: cabac_rlps = 8'd197;
			8'd7: cabac_rlps = 8'd227;
			8'd8: cabac_rlps = 8'd128;
			8'd9: cabac_rlps = 8'd158;
			8'd10: cabac_rlps = 8'd187;
			8'd11: cabac_rlps = 8'd216;
			8'd12: cabac_rlps = 8'd123;
			8'd13: cabac_rlps = 8'd150;
			8'd14: cabac_rlps = 8'd178;
			8'd15: cabac_rlps = 8'd205;
			8'd16: cabac_rlps = 8'd116;
			8'd17: cabac_rlps = 8'd142;
			8'd18: cabac_rlps = 8'd169;
			8'd19: cabac_rlps = 8'd195;
			8'd20: cabac_rlps = 8'd111;
			8'd21: cabac_rlps = 8'd135;
			8'd22: cabac_rlps = 8'd160;
			8'd23: cabac_rlps = 8'd185;
			8'd24: cabac_rlps = 8'd105;
			8'd25: cabac_rlps = 8'd128;
			8'd26: cabac_rlps = 8'd152;
			8'd27: cabac_rlps = 8'd175;
			8'd28: cabac_rlps = 8'd100;
			8'd29: cabac_rlps = 8'd122;
			8'd30: cabac_rlps = 8'd144;
			8'd31: cabac_rlps = 8'd166;
			8'd32: cabac_rlps = 8'd95;
			8'd33: cabac_rlps = 8'd116;
			8'd34: cabac_rlps = 8'd137;
			8'd35: cabac_rlps = 8'd158;
			8'd36: cabac_rlps = 8'd90;
			8'd37: cabac_rlps = 8'd110;
			8'd38: cabac_rlps = 8'd130;
			8'd39: cabac_rlps = 8'd150;
			8'd40: cabac_rlps = 8'd85;
			8'd41: cabac_rlps = 8'd104;
			8'd42: cabac_rlps = 8'd123;
			8'd43: cabac_rlps = 8'd142;
			8'd44: cabac_rlps = 8'd81;
			8'd45: cabac_rlps = 8'd99;
			8'd46: cabac_rlps = 8'd117;
			8'd47: cabac_rlps = 8'd135;
			8'd48: cabac_rlps = 8'd77;
			8'd49: cabac_rlps = 8'd94;
			8'd50: cabac_rlps = 8'd111;
			8'd51: cabac_rlps = 8'd128;
			8'd52: cabac_rlps = 8'd73;
			8'd53: cabac_rlps = 8'd89;
			8'd54: cabac_rlps = 8'd105;
			8'd55: cabac_rlps = 8'd122;
			8'd56: cabac_rlps = 8'd69;
			8'd57: cabac_rlps = 8'd85;
			8'd58: cabac_rlps = 8'd100;
			8'd59: cabac_rlps = 8'd116;
			8'd60: cabac_rlps = 8'd66;
			8'd61: cabac_rlps = 8'd80;
			8'd62: cabac_rlps = 8'd95;
			8'd63: cabac_rlps = 8'd110;
			8'd64: cabac_rlps = 8'd62;
			8'd65: cabac_rlps = 8'd76;
			8'd66: cabac_rlps = 8'd90;
			8'd67: cabac_rlps = 8'd104;
			8'd68: cabac_rlps = 8'd59;
			8'd69: cabac_rlps = 8'd72;
			8'd70: cabac_rlps = 8'd86;
			8'd71: cabac_rlps = 8'd99;
			8'd72: cabac_rlps = 8'd56;
			8'd73: cabac_rlps = 8'd69;
			8'd74: cabac_rlps = 8'd81;
			8'd75: cabac_rlps = 8'd94;
			8'd76: cabac_rlps = 8'd53;
			8'd77: cabac_rlps = 8'd65;
			8'd78: cabac_rlps = 8'd77;
			8'd79: cabac_rlps = 8'd89;
			8'd80: cabac_rlps = 8'd51;
			8'd81: cabac_rlps = 8'd62;
			8'd82: cabac_rlps = 8'd73;
			8'd83: cabac_rlps = 8'd85;
			8'd84: cabac_rlps = 8'd48;
			8'd85: cabac_rlps = 8'd59;
			8'd86: cabac_rlps = 8'd69;
			8'd87: cabac_rlps = 8'd80;
			8'd88: cabac_rlps = 8'd46;
			8'd89: cabac_rlps = 8'd56;
			8'd90: cabac_rlps = 8'd66;
			8'd91: cabac_rlps = 8'd76;
			8'd92: cabac_rlps = 8'd43;
			8'd93: cabac_rlps = 8'd53;
			8'd94: cabac_rlps = 8'd63;
			8'd95: cabac_rlps = 8'd72;
			8'd96: cabac_rlps = 8'd41;
			8'd97: cabac_rlps = 8'd50;
			8'd98: cabac_rlps = 8'd59;
			8'd99: cabac_rlps = 8'd69;
			8'd100: cabac_rlps = 8'd39;
			8'd101: cabac_rlps = 8'd48;
			8'd102: cabac_rlps = 8'd56;
			8'd103: cabac_rlps = 8'd65;
			8'd104: cabac_rlps = 8'd37;
			8'd105: cabac_rlps = 8'd45;
			8'd106: cabac_rlps = 8'd54;
			8'd107: cabac_rlps = 8'd62;
			8'd108: cabac_rlps = 8'd35;
			8'd109: cabac_rlps = 8'd43;
			8'd110: cabac_rlps = 8'd51;
			8'd111: cabac_rlps = 8'd59;
			8'd112: cabac_rlps = 8'd33;
			8'd113: cabac_rlps = 8'd41;
			8'd114: cabac_rlps = 8'd48;
			8'd115: cabac_rlps = 8'd56;
			8'd116: cabac_rlps = 8'd32;
			8'd117: cabac_rlps = 8'd39;
			8'd118: cabac_rlps = 8'd46;
			8'd119: cabac_rlps = 8'd53;
			8'd120: cabac_rlps = 8'd30;
			8'd121: cabac_rlps = 8'd37;
			8'd122: cabac_rlps = 8'd43;
			8'd123: cabac_rlps = 8'd50;
			8'd124: cabac_rlps = 8'd29;
			8'd125: cabac_rlps = 8'd35;
			8'd126: cabac_rlps = 8'd41;
			8'd127: cabac_rlps = 8'd48;
			8'd128: cabac_rlps = 8'd27;
			8'd129: cabac_rlps = 8'd33;
			8'd130: cabac_rlps = 8'd39;
			8'd131: cabac_rlps = 8'd45;
			8'd132: cabac_rlps = 8'd26;
			8'd133: cabac_rlps = 8'd31;
			8'd134: cabac_rlps = 8'd37;
			8'd135: cabac_rlps = 8'd43;
			8'd136: cabac_rlps = 8'd24;
			8'd137: cabac_rlps = 8'd30;
			8'd138: cabac_rlps = 8'd35;
			8'd139: cabac_rlps = 8'd41;
			8'd140: cabac_rlps = 8'd23;
			8'd141: cabac_rlps = 8'd28;
			8'd142: cabac_rlps = 8'd33;
			8'd143: cabac_rlps = 8'd39;
			8'd144: cabac_rlps = 8'd22;
			8'd145: cabac_rlps = 8'd27;
			8'd146: cabac_rlps = 8'd32;
			8'd147: cabac_rlps = 8'd37;
			8'd148: cabac_rlps = 8'd21;
			8'd149: cabac_rlps = 8'd26;
			8'd150: cabac_rlps = 8'd30;
			8'd151: cabac_rlps = 8'd35;
			8'd152: cabac_rlps = 8'd20;
			8'd153: cabac_rlps = 8'd24;
			8'd154: cabac_rlps = 8'd29;
			8'd155: cabac_rlps = 8'd33;
			8'd156: cabac_rlps = 8'd19;
			8'd157: cabac_rlps = 8'd23;
			8'd158: cabac_rlps = 8'd27;
			8'd159: cabac_rlps = 8'd31;
			8'd160: cabac_rlps = 8'd18;
			8'd161: cabac_rlps = 8'd22;
			8'd162: cabac_rlps = 8'd26;
			8'd163: cabac_rlps = 8'd30;
			8'd164: cabac_rlps = 8'd17;
			8'd165: cabac_rlps = 8'd21;
			8'd166: cabac_rlps = 8'd25;
			8'd167: cabac_rlps = 8'd28;
			8'd168: cabac_rlps = 8'd16;
			8'd169: cabac_rlps = 8'd20;
			8'd170: cabac_rlps = 8'd23;
			8'd171: cabac_rlps = 8'd27;
			8'd172: cabac_rlps = 8'd15;
			8'd173: cabac_rlps = 8'd19;
			8'd174: cabac_rlps = 8'd22;
			8'd175: cabac_rlps = 8'd25;
			8'd176: cabac_rlps = 8'd14;
			8'd177: cabac_rlps = 8'd18;
			8'd178: cabac_rlps = 8'd21;
			8'd179: cabac_rlps = 8'd24;
			8'd180: cabac_rlps = 8'd14;
			8'd181: cabac_rlps = 8'd17;
			8'd182: cabac_rlps = 8'd20;
			8'd183: cabac_rlps = 8'd23;
			8'd184: cabac_rlps = 8'd13;
			8'd185: cabac_rlps = 8'd16;
			8'd186: cabac_rlps = 8'd19;
			8'd187: cabac_rlps = 8'd22;
			8'd188: cabac_rlps = 8'd12;
			8'd189: cabac_rlps = 8'd15;
			8'd190: cabac_rlps = 8'd18;
			8'd191: cabac_rlps = 8'd21;
			8'd192: cabac_rlps = 8'd12;
			8'd193: cabac_rlps = 8'd14;
			8'd194: cabac_rlps = 8'd17;
			8'd195: cabac_rlps = 8'd20;
			8'd196: cabac_rlps = 8'd11;
			8'd197: cabac_rlps = 8'd14;
			8'd198: cabac_rlps = 8'd16;
			8'd199: cabac_rlps = 8'd19;
			8'd200: cabac_rlps = 8'd11;
			8'd201: cabac_rlps = 8'd13;
			8'd202: cabac_rlps = 8'd15;
			8'd203: cabac_rlps = 8'd18;
			8'd204: cabac_rlps = 8'd10;
			8'd205: cabac_rlps = 8'd12;
			8'd206: cabac_rlps = 8'd15;
			8'd207: cabac_rlps = 8'd17;
			8'd208: cabac_rlps = 8'd10;
			8'd209: cabac_rlps = 8'd12;
			8'd210: cabac_rlps = 8'd14;
			8'd211: cabac_rlps = 8'd16;
			8'd212: cabac_rlps = 8'd9;
			8'd213: cabac_rlps = 8'd11;
			8'd214: cabac_rlps = 8'd13;
			8'd215: cabac_rlps = 8'd15;
			8'd216: cabac_rlps = 8'd9;
			8'd217: cabac_rlps = 8'd11;
			8'd218: cabac_rlps = 8'd12;
			8'd219: cabac_rlps = 8'd14;
			8'd220: cabac_rlps = 8'd8;
			8'd221: cabac_rlps = 8'd10;
			8'd222: cabac_rlps = 8'd12;
			8'd223: cabac_rlps = 8'd14;
			8'd224: cabac_rlps = 8'd8;
			8'd225: cabac_rlps = 8'd9;
			8'd226: cabac_rlps = 8'd11;
			8'd227: cabac_rlps = 8'd13;
			8'd228: cabac_rlps = 8'd7;
			8'd229: cabac_rlps = 8'd9;
			8'd230: cabac_rlps = 8'd11;
			8'd231: cabac_rlps = 8'd12;
			8'd232: cabac_rlps = 8'd7;
			8'd233: cabac_rlps = 8'd9;
			8'd234: cabac_rlps = 8'd10;
			8'd235: cabac_rlps = 8'd12;
			8'd236: cabac_rlps = 8'd7;
			8'd237: cabac_rlps = 8'd8;
			8'd238: cabac_rlps = 8'd10;
			8'd239: cabac_rlps = 8'd11;
			8'd240: cabac_rlps = 8'd6;
			8'd241: cabac_rlps = 8'd8;
			8'd242: cabac_rlps = 8'd9;
			8'd243: cabac_rlps = 8'd11;
			8'd244: cabac_rlps = 8'd6;
			8'd245: cabac_rlps = 8'd7;
			8'd246: cabac_rlps = 8'd9;
			8'd247: cabac_rlps = 8'd10;
			8'd248: cabac_rlps = 8'd6;
			8'd249: cabac_rlps = 8'd7;
			8'd250: cabac_rlps = 8'd8;
			8'd251: cabac_rlps = 8'd9;
			8'd252: cabac_rlps = 8'd2;
			8'd253: cabac_rlps = 8'd2;
			8'd254: cabac_rlps = 8'd2;
			8'd255: cabac_rlps = 8'd2;
			default: cabac_rlps = 8'd2;
		endcase
	endfunction
	function automatic [1:0] sv2v_cast_2;
		input reg [1:0] inp;
		sv2v_cast_2 = inp;
	endfunction
	assign rlps = cabac_rlps(ps_cur, sv2v_cast_2(range_q[8:6] - 3'd4));
	function automatic [8:0] sv2v_cast_9;
		input reg [8:0] inp;
		sv2v_cast_9 = inp;
	endfunction
	assign r_mps_v = range_q - sv2v_cast_9(rlps);
	assign is_lps = value_q >= r_mps_v;
	assign r_dec = (is_lps ? sv2v_cast_9(rlps) : r_mps_v);
	wire [8:0] v_dec;
	assign v_dec = (is_lps ? value_q - r_mps_v : value_q);
	function automatic [2:0] rshift;
		input reg [8:0] r;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if (r[8]) begin
				rshift = 3'd0;
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (r[7]) begin
					rshift = 3'd1;
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					if (r[6]) begin
						rshift = 3'd2;
						_sv2v_jump = 2'b11;
					end
					if (_sv2v_jump == 2'b00) begin
						if (r[5]) begin
							rshift = 3'd3;
							_sv2v_jump = 2'b11;
						end
						if (_sv2v_jump == 2'b00) begin
							if (r[4]) begin
								rshift = 3'd4;
								_sv2v_jump = 2'b11;
							end
							if (_sv2v_jump == 2'b00) begin
								if (r[3]) begin
									rshift = 3'd5;
									_sv2v_jump = 2'b11;
								end
								if (_sv2v_jump == 2'b00) begin
									if (r[2]) begin
										rshift = 3'd6;
										_sv2v_jump = 2'b11;
									end
									if (_sv2v_jump == 2'b00) begin
										rshift = 3'd7;
										_sv2v_jump = 2'b11;
									end
								end
							end
						end
					end
				end
			end
		end
	endfunction
	wire [8:0] r_term;
	assign r_term = range_q - 9'd2;
	wire term_hit;
	assign term_hit = value_q >= r_term;
	reg [2:0] shn;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (op)
			2'd0: shn = rshift(r_dec);
			2'd1: shn = 3'd1;
			default: shn = (term_hit ? 3'd0 : rshift(r_term));
		endcase
	end
	reg [8:0] v_shifted;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_2
		reg [6:0] hi7;
		if (_sv2v_0)
			;
		hi7 = show[23:17];
		v_shifted = sv2v_cast_9((sv2v_cast_16(v_dec) << shn) | sv2v_cast_16(hi7 >> (3'd7 - shn)));
	end
	wire [9:0] v_byp10;
	wire [8:0] v_byp;
	wire byp_one;
	assign v_byp10 = {value_q, show[23]};
	assign byp_one = v_byp10 >= {1'b0, range_q};
	assign v_byp = (byp_one ? sv2v_cast_9(v_byp10 - {1'b0, range_q}) : v_byp10[8:0]);
	wire can_run;
	function automatic [6:0] sv2v_cast_7;
		input reg [6:0] inp;
		sv2v_cast_7 = inp;
	endfunction
	assign can_run = ((st_q == 2'd0) && op_valid) && ((shn == 3'd0) || (sv2v_cast_7(shn) <= avail));
	assign op_ready = can_run;
	always @(*) begin
		if (_sv2v_0)
			;
		req_valid = 1'b0;
		req_bits = 1'sb0;
		if (st_q == 2'd2) begin
			if (avail >= 7'd9) begin
				req_valid = 1'b1;
				req_bits = 5'd9;
			end
		end
		else if (can_run && (shn != 3'd0)) begin
			req_valid = 1'b1;
			req_bits = {2'b00, shn};
		end
	end
	reg [8:0] v_term_sh;
	always @(*) begin : sv2v_autoblock_3
		reg [6:0] hi7;
		if (_sv2v_0)
			;
		hi7 = show[23:17];
		v_term_sh = sv2v_cast_9((sv2v_cast_16(value_q) << shn) | sv2v_cast_16(hi7 >> (3'd7 - shn)));
	end
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (op)
			2'd0: bin = (is_lps ? !mps_cur : mps_cur);
			2'd1: bin = byp_one;
			default: bin = term_hit;
		endcase
	end
	function automatic [5:0] cabac_tlps;
		input reg [5:0] st;
		(* full_case, parallel_case *)
		case (st)
			6'd0: cabac_tlps = 6'd0;
			6'd1: cabac_tlps = 6'd0;
			6'd2: cabac_tlps = 6'd1;
			6'd3: cabac_tlps = 6'd2;
			6'd4: cabac_tlps = 6'd2;
			6'd5: cabac_tlps = 6'd4;
			6'd6: cabac_tlps = 6'd4;
			6'd7: cabac_tlps = 6'd5;
			6'd8: cabac_tlps = 6'd6;
			6'd9: cabac_tlps = 6'd7;
			6'd10: cabac_tlps = 6'd8;
			6'd11: cabac_tlps = 6'd9;
			6'd12: cabac_tlps = 6'd9;
			6'd13: cabac_tlps = 6'd11;
			6'd14: cabac_tlps = 6'd11;
			6'd15: cabac_tlps = 6'd12;
			6'd16: cabac_tlps = 6'd13;
			6'd17: cabac_tlps = 6'd13;
			6'd18: cabac_tlps = 6'd15;
			6'd19: cabac_tlps = 6'd15;
			6'd20: cabac_tlps = 6'd16;
			6'd21: cabac_tlps = 6'd16;
			6'd22: cabac_tlps = 6'd18;
			6'd23: cabac_tlps = 6'd18;
			6'd24: cabac_tlps = 6'd19;
			6'd25: cabac_tlps = 6'd19;
			6'd26: cabac_tlps = 6'd21;
			6'd27: cabac_tlps = 6'd21;
			6'd28: cabac_tlps = 6'd22;
			6'd29: cabac_tlps = 6'd22;
			6'd30: cabac_tlps = 6'd23;
			6'd31: cabac_tlps = 6'd24;
			6'd32: cabac_tlps = 6'd24;
			6'd33: cabac_tlps = 6'd25;
			6'd34: cabac_tlps = 6'd26;
			6'd35: cabac_tlps = 6'd26;
			6'd36: cabac_tlps = 6'd27;
			6'd37: cabac_tlps = 6'd27;
			6'd38: cabac_tlps = 6'd28;
			6'd39: cabac_tlps = 6'd29;
			6'd40: cabac_tlps = 6'd29;
			6'd41: cabac_tlps = 6'd30;
			6'd42: cabac_tlps = 6'd30;
			6'd43: cabac_tlps = 6'd30;
			6'd44: cabac_tlps = 6'd31;
			6'd45: cabac_tlps = 6'd32;
			6'd46: cabac_tlps = 6'd32;
			6'd47: cabac_tlps = 6'd33;
			6'd48: cabac_tlps = 6'd33;
			6'd49: cabac_tlps = 6'd33;
			6'd50: cabac_tlps = 6'd34;
			6'd51: cabac_tlps = 6'd34;
			6'd52: cabac_tlps = 6'd35;
			6'd53: cabac_tlps = 6'd35;
			6'd54: cabac_tlps = 6'd35;
			6'd55: cabac_tlps = 6'd36;
			6'd56: cabac_tlps = 6'd36;
			6'd57: cabac_tlps = 6'd36;
			6'd58: cabac_tlps = 6'd37;
			6'd59: cabac_tlps = 6'd37;
			6'd60: cabac_tlps = 6'd37;
			6'd61: cabac_tlps = 6'd38;
			6'd62: cabac_tlps = 6'd38;
			6'd63: cabac_tlps = 6'd63;
		endcase
	endfunction
	function automatic [5:0] cabac_tmps;
		input reg [5:0] st;
		(* full_case, parallel_case *)
		case (st)
			6'd0: cabac_tmps = 6'd1;
			6'd1: cabac_tmps = 6'd2;
			6'd2: cabac_tmps = 6'd3;
			6'd3: cabac_tmps = 6'd4;
			6'd4: cabac_tmps = 6'd5;
			6'd5: cabac_tmps = 6'd6;
			6'd6: cabac_tmps = 6'd7;
			6'd7: cabac_tmps = 6'd8;
			6'd8: cabac_tmps = 6'd9;
			6'd9: cabac_tmps = 6'd10;
			6'd10: cabac_tmps = 6'd11;
			6'd11: cabac_tmps = 6'd12;
			6'd12: cabac_tmps = 6'd13;
			6'd13: cabac_tmps = 6'd14;
			6'd14: cabac_tmps = 6'd15;
			6'd15: cabac_tmps = 6'd16;
			6'd16: cabac_tmps = 6'd17;
			6'd17: cabac_tmps = 6'd18;
			6'd18: cabac_tmps = 6'd19;
			6'd19: cabac_tmps = 6'd20;
			6'd20: cabac_tmps = 6'd21;
			6'd21: cabac_tmps = 6'd22;
			6'd22: cabac_tmps = 6'd23;
			6'd23: cabac_tmps = 6'd24;
			6'd24: cabac_tmps = 6'd25;
			6'd25: cabac_tmps = 6'd26;
			6'd26: cabac_tmps = 6'd27;
			6'd27: cabac_tmps = 6'd28;
			6'd28: cabac_tmps = 6'd29;
			6'd29: cabac_tmps = 6'd30;
			6'd30: cabac_tmps = 6'd31;
			6'd31: cabac_tmps = 6'd32;
			6'd32: cabac_tmps = 6'd33;
			6'd33: cabac_tmps = 6'd34;
			6'd34: cabac_tmps = 6'd35;
			6'd35: cabac_tmps = 6'd36;
			6'd36: cabac_tmps = 6'd37;
			6'd37: cabac_tmps = 6'd38;
			6'd38: cabac_tmps = 6'd39;
			6'd39: cabac_tmps = 6'd40;
			6'd40: cabac_tmps = 6'd41;
			6'd41: cabac_tmps = 6'd42;
			6'd42: cabac_tmps = 6'd43;
			6'd43: cabac_tmps = 6'd44;
			6'd44: cabac_tmps = 6'd45;
			6'd45: cabac_tmps = 6'd46;
			6'd46: cabac_tmps = 6'd47;
			6'd47: cabac_tmps = 6'd48;
			6'd48: cabac_tmps = 6'd49;
			6'd49: cabac_tmps = 6'd50;
			6'd50: cabac_tmps = 6'd51;
			6'd51: cabac_tmps = 6'd52;
			6'd52: cabac_tmps = 6'd53;
			6'd53: cabac_tmps = 6'd54;
			6'd54: cabac_tmps = 6'd55;
			6'd55: cabac_tmps = 6'd56;
			6'd56: cabac_tmps = 6'd57;
			6'd57: cabac_tmps = 6'd58;
			6'd58: cabac_tmps = 6'd59;
			6'd59: cabac_tmps = 6'd60;
			6'd60: cabac_tmps = 6'd61;
			6'd61: cabac_tmps = 6'd62;
			6'd62: cabac_tmps = 6'd62;
			6'd63: cabac_tmps = 6'd63;
		endcase
	endfunction
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 2'd0;
			range_q <= 9'd510;
			value_q <= 1'sb0;
			ictx_q <= 1'sb0;
			model_q <= 1'sb0;
			mps <= 1'sb0;
		end
		else
			(* full_case, parallel_case *)
			case (st_q)
				2'd0:
					if (init_start) begin
						ictx_q <= 1'sb0;
						model_q <= init_model;
						st_q <= 2'd1;
					end
					else if (can_run)
						(* full_case, parallel_case *)
						case (op)
							2'd0: begin
								range_q <= r_dec << shn;
								value_q <= v_shifted;
								if (is_lps) begin
									if (ps_cur == 6'd0)
										mps[op_ctx] <= !mps_cur;
									pstate[op_ctx] <= cabac_tlps(ps_cur);
								end
								else
									pstate[op_ctx] <= cabac_tmps(ps_cur);
							end
							2'd1: value_q <= v_byp;
							default: begin
								range_q <= (term_hit ? r_term : r_term << shn);
								if (!term_hit)
									value_q <= v_term_sh;
							end
						endcase
				2'd1: begin
					pstate[ictx_q] <= (pre <= 7'd63 ? sv2v_cast_6(7'd63 - pre) : sv2v_cast_6(pre - 7'd64));
					mps[ictx_q] <= pre > 7'd63;
					if (ictx_q == 9'd435) begin
						range_q <= 9'd510;
						st_q <= 2'd2;
					end
					else
						ictx_q <= ictx_q + 9'd1;
				end
				2'd2:
					if (avail >= 7'd9) begin
						value_q <= show[23:15];
						st_q <= 2'd0;
					end
				default: st_q <= 2'd0;
			endcase
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
