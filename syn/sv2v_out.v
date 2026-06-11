module h264_core (
	clk,
	rst_n,
	in_valid,
	in_byte,
	in_ready,
	cfg_mb_w,
	cfg_mb_h,
	cfg_qp,
	cfg_cqp_off,
	start,
	align_valid,
	align_bits,
	rec_taken,
	mb_out_valid,
	mb_out_x,
	mb_out_y,
	mb_out_qp,
	out_y,
	out_u,
	out_v,
	slice_done,
	err
);
	parameter signed [31:0] MAX_MBW = 120;
	input wire clk;
	input wire rst_n;
	input wire in_valid;
	input wire [7:0] in_byte;
	output wire in_ready;
	input wire [7:0] cfg_mb_w;
	input wire [7:0] cfg_mb_h;
	input wire [5:0] cfg_qp;
	input wire signed [5:0] cfg_cqp_off;
	input wire start;
	input wire align_valid;
	input wire [4:0] align_bits;
	input wire rec_taken;
	output wire mb_out_valid;
	output wire [7:0] mb_out_x;
	output wire [7:0] mb_out_y;
	output wire [5:0] mb_out_qp;
	output wire [2047:0] out_y;
	output wire [511:0] out_u;
	output wire [511:0] out_v;
	output wire slice_done;
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
		.in_byte(in_byte),
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
	mb_dec #(.MAX_MBW(MAX_MBW)) u_mb(
		.clk(clk),
		.rst_n(rst_n),
		.cfg_mb_w(cfg_mb_w),
		.cfg_mb_h(cfg_mb_h),
		.cfg_qp(cfg_qp),
		.start(start),
		.req_valid(m_req_valid),
		.req_bits(m_req_bits),
		.req_ready(br_req_ready),
		.show(show),
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
		.rec_done(rec_valid && rec_taken)
	);
	mb_recon #(.MAX_MBW(MAX_MBW)) u_rec(
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
		.busy(),
		.rec_valid(rec_valid),
		.rec_y(out_y),
		.rec_u(out_u),
		.rec_v(out_v),
		.err(rec_err)
	);
	assign mb_out_valid = rec_valid;
	assign mb_out_x = mb_x;
	assign mb_out_y = mb_y;
	assign mb_out_qp = mb_qp;
	assign err = (mb_err | rec_err) | blk_err;
endmodule
module bitreader (
	clk,
	rst_n,
	in_valid,
	in_byte,
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
	input wire [7:0] in_byte;
	output wire in_ready;
	input wire req_valid;
	input wire [4:0] req_bits;
	output wire req_ready;
	output wire [23:0] show;
	output wire [6:0] avail;
	reg [63:0] buf_q;
	reg [6:0] fill_q;
	assign in_ready = fill_q <= 7'd56;
	assign req_ready = req_valid && (fill_q >= {2'b00, req_bits});
	assign show = buf_q[63:40];
	assign avail = fill_q;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			buf_q <= 1'sb0;
			fill_q <= 1'sb0;
		end
		else begin : sv2v_autoblock_1
			reg [63:0] b;
			reg [6:0] f;
			b = buf_q;
			f = fill_q;
			if (req_valid && (f >= {2'b00, req_bits})) begin
				b = b << req_bits;
				f = f - {2'b00, req_bits};
			end
			if (in_valid && (fill_q <= 7'd56)) begin
				b = b | ({56'b00000000000000000000000000000000000000000000000000000000, in_byte} << (7'd56 - f));
				f = f + 7'd8;
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
	start,
	req_valid,
	req_bits,
	req_ready,
	show,
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
	input wire start;
	output reg req_valid;
	output reg [4:0] req_bits;
	input wire req_ready;
	input wire [23:0] show;
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
	reg [3:0] st_q;
	reg [3:0] ret_q;
	reg [7:0] mbx_q;
	reg [7:0] mby_q;
	reg i16_q;
	reg [1:0] i16m_q;
	reg [1:0] cmode_q;
	reg [5:0] cbp_q;
	reg [5:0] qp_q;
	reg [3:0] k_q;
	reg [1:0] comp_q;
	reg [3:0] i4m_q [0:15];
	reg [4:0] nz_q [0:15];
	reg [3:0] i4_top [0:(MAX_MBW * 4) - 1];
	reg [4:0] nzl_top [0:(MAX_MBW * 4) - 1];
	reg [4:0] nzc_top [0:1][0:(MAX_MBW * 2) - 1];
	reg [3:0] i4_left [0:3];
	reg [4:0] nzl_left [0:3];
	reg [4:0] nzc_left [0:1][0:1];
	reg have_left;
	reg [4:0] nzc_q [0:1][0:3];
	wire [11:0] eg_ue;
	wire signed [11:0] eg_se;
	wire [4:0] eg_len;
	wire eg_ok;
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
			predB = i4_top[{mbx_q, 2'b00} + {6'b000000, bx}];
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
		nB = (by != 0 ? nz_q[zidx(bx, by - 2'd1)] : nzl_top[{mbx_q, 2'b00} + {6'b000000, bx}]);
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
		nB = (cy ? nzc_q[comp_q][{1'b0, cx}] : nzc_top[comp_q][{mbx_q, 1'b0} + {7'b0000000, cx}]);
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
	assign coef_we = blk_coef_we && (st_q == 4'd8);
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
	assign mb_valid = st_q == 4'd11;
	assign slice_done = st_q == 4'd13;
	assign err = st_q == 4'd14;
	function automatic cbp_l_bit;
		input reg [3:0] k;
		cbp_l_bit = cbp_q[{k[3], k[2]}];
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
	function automatic signed [1:0] sv2v_cast_2_signed;
		input reg signed [1:0] inp;
		sv2v_cast_2_signed = inp;
	endfunction
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			st_q <= 4'd0;
			ret_q <= 4'd0;
			req_valid <= 1'b0;
			req_bits <= 1'sb0;
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
			req_valid <= 1'b0;
			blk_start <= 1'b0;
			(* full_case, parallel_case *)
			case (st_q)
				4'd0:
					if (start) begin
						mbx_q <= 1'sb0;
						mby_q <= 1'sb0;
						qp_q <= cfg_qp;
						have_left <= 1'b0;
						st_q <= 4'd1;
					end
				4'd1:
					if (!req_valid) begin
						if (!eg_ok)
							st_q <= 4'd14;
						else begin
							req_valid <= 1'b1;
							req_bits <= eg_len;
							if (eg_ue == 12'd0) begin
								i16_q <= 1'b0;
								i16m_q <= 1'sb0;
								k_q <= 1'sb0;
								st_q <= 4'd2;
							end
							else if (eg_ue <= 12'd24) begin : sv2v_autoblock_5
								reg [11:0] m;
								reg [1:0] cc;
								m = eg_ue - 12'd1;
								cc = sv2v_cast_2((m >> 2) % 12'd3);
								i16_q <= 1'b1;
								i16m_q <= sv2v_cast_2(m & 12'd3);
								cbp_q <= {cc, (m >= 12'd12 ? 4'hf : 4'h0)};
								begin : sv2v_autoblock_6
									reg signed [31:0] i;
									for (i = 0; i < 16; i = i + 1)
										i4m_q[i] <= 4'd2;
								end
								st_q <= 4'd3;
							end
							else
								st_q <= 4'd14;
						end
					end
				4'd2:
					if (!req_valid) begin : sv2v_autoblock_7
						reg [3:0] mode;
						if (show[23]) begin
							mode = i4_pred;
							req_valid <= 1'b1;
							req_bits <= 5'd1;
						end
						else begin : sv2v_autoblock_8
							reg [3:0] rem;
							rem = {1'b0, show[22:20]};
							mode = (rem < i4_pred ? rem : rem + 4'd1);
							req_valid <= 1'b1;
							req_bits <= 5'd4;
						end
						i4m_q[k_q] <= mode;
						if (k_q == 4'd15)
							st_q <= 4'd3;
						k_q <= k_q + 4'd1;
					end
				4'd3:
					if (!req_valid) begin
						if (!eg_ok || (eg_ue > 12'd3))
							st_q <= 4'd14;
						else begin
							cmode_q <= sv2v_cast_2(eg_ue);
							req_valid <= 1'b1;
							req_bits <= eg_len;
							st_q <= (i16_q ? 4'd5 : 4'd4);
						end
					end
				4'd4:
					if (!req_valid) begin : sv2v_autoblock_9
						reg [5:0] cbp;
						cbp = cavlc_intra_cbp(sv2v_cast_6(eg_ue));
						if ((!eg_ok || (eg_ue > 12'd47)) || (cbp == 6'd63))
							st_q <= 4'd14;
						else begin
							cbp_q <= cbp;
							req_valid <= 1'b1;
							req_bits <= eg_len;
							st_q <= (cbp == 6'd0 ? 4'd11 : 4'd5);
						end
					end
				4'd5:
					if (!req_valid) begin
						if (!eg_ok)
							st_q <= 4'd14;
						else begin
							qp_q <= sv2v_cast_6(((sv2v_cast_13_signed($signed({1'b0, qp_q})) + sv2v_cast_13_signed(eg_se)) + 13'd52) % 13'd52);
							req_valid <= 1'b1;
							req_bits <= eg_len;
							k_q <= 1'sb0;
							st_q <= (i16_q ? 4'd6 : 4'd7);
						end
					end
				4'd6: begin
					blk_start <= 1'b1;
					blk_chroma_dc <= 1'b0;
					blk_nc_class <= nc_class_of(nc_l);
					blk_maxc <= 5'd16;
					ac15_q <= 1'b0;
					cur_blk_q <= 5'd16;
					ret_q <= 4'd7;
					st_q <= 4'd8;
				end
				4'd7:
					if (cbp_l_bit(k_q)) begin
						blk_start <= 1'b1;
						blk_chroma_dc <= 1'b0;
						blk_nc_class <= nc_class_of(nc_l);
						blk_maxc <= (i16_q ? 5'd15 : 5'd16);
						ac15_q <= i16_q;
						cur_blk_q <= {1'b0, k_q};
						ret_q <= 4'd7;
						st_q <= 4'd8;
					end
					else begin
						nz_q[k_q] <= 1'sb0;
						if (k_q == 4'd15) begin
							k_q <= 1'sb0;
							comp_q <= 1'sb0;
							st_q <= (cbp_q[5:4] != 2'd0 ? 4'd9 : 4'd11);
						end
						else
							k_q <= k_q + 4'd1;
					end
				4'd9: begin
					blk_start <= 1'b1;
					blk_chroma_dc <= 1'b1;
					blk_nc_class <= 1'sb0;
					blk_maxc <= 5'd4;
					ac15_q <= 1'b0;
					cur_blk_q <= 5'd17 + {4'b0000, comp_q[0]};
					ret_q <= 4'd9;
					st_q <= 4'd8;
				end
				4'd10:
					if (cbp_q[5:4] == 2'd2) begin
						blk_start <= 1'b1;
						blk_chroma_dc <= 1'b0;
						blk_nc_class <= nc_class_of(nc_c);
						blk_maxc <= 5'd15;
						ac15_q <= 1'b1;
						cur_blk_q <= (5'd19 + {2'b00, comp_q[0], 2'b00}) + {3'b000, k_q[1:0]};
						ret_q <= 4'd10;
						st_q <= 4'd8;
					end
					else begin
						nzc_q[comp_q][k_q[1:0]] <= 1'sb0;
						if (k_q[1:0] == 2'd3) begin
							k_q <= 1'sb0;
							if (comp_q[0])
								st_q <= 4'd11;
							comp_q <= comp_q + 2'd1;
						end
						else
							k_q <= k_q + 4'd1;
					end
				4'd8:
					if (blk_err)
						st_q <= 4'd14;
					else if (blk_done)
						(* full_case, parallel_case *)
						case (ret_q)
							4'd7:
								if (cur_blk_q == 5'd16) begin
									k_q <= 1'sb0;
									st_q <= 4'd7;
								end
								else begin
									nz_q[k_q] <= blk_tc;
									if (k_q == 4'd15) begin
										k_q <= 1'sb0;
										comp_q <= 1'sb0;
										st_q <= (cbp_q[5:4] != 2'd0 ? 4'd9 : 4'd11);
									end
									else begin
										k_q <= k_q + 4'd1;
										st_q <= 4'd7;
									end
								end
							4'd9:
								if (comp_q[0]) begin
									comp_q <= 1'sb0;
									k_q <= 1'sb0;
									st_q <= (cbp_q[5:4] == 2'd2 ? 4'd10 : 4'd11);
								end
								else begin
									comp_q <= 2'd1;
									st_q <= 4'd9;
								end
							4'd10: begin
								nzc_q[comp_q][k_q[1:0]] <= blk_tc;
								if (k_q[1:0] == 2'd3) begin
									k_q <= 1'sb0;
									if (comp_q[0])
										st_q <= 4'd11;
									else
										st_q <= 4'd10;
									comp_q <= comp_q + 2'd1;
								end
								else begin
									k_q <= k_q + 4'd1;
									st_q <= 4'd10;
								end
							end
							default: st_q <= 4'd14;
						endcase
				4'd11: begin
					begin : sv2v_autoblock_10
						reg signed [31:0] b;
						for (b = 0; b < 4; b = b + 1)
							begin
								i4_top[{mbx_q, 2'b00} + b] <= i4m_q[zidx(sv2v_cast_2_signed(b), 2'd3)];
								nzl_top[{mbx_q, 2'b00} + b] <= nz_q[zidx(sv2v_cast_2_signed(b), 2'd3)];
								i4_left[b] <= i4m_q[zidx(2'd3, sv2v_cast_2_signed(b))];
								nzl_left[b] <= nz_q[zidx(2'd3, sv2v_cast_2_signed(b))];
							end
					end
					begin : sv2v_autoblock_11
						reg signed [31:0] c2;
						for (c2 = 0; c2 < 2; c2 = c2 + 1)
							begin : sv2v_autoblock_12
								reg signed [31:0] b;
								for (b = 0; b < 2; b = b + 1)
									begin
										nzc_top[c2][{mbx_q, 1'b0} + b] <= (cbp_q[5:4] == 2'd2 ? nzc_q[c2][{1'b1, b[0]}] : 5'd0);
										nzc_left[c2][b] <= (cbp_q[5:4] == 2'd2 ? nzc_q[c2][{b[0], 1'b1}] : 5'd0);
									end
							end
					end
					st_q <= 4'd12;
				end
				4'd12:
					if (rec_done) begin
						if ((mbx_q + 8'd1) == cfg_mb_w) begin
							have_left <= 1'b0;
							mbx_q <= 1'sb0;
							if ((mby_q + 8'd1) == cfg_mb_h)
								st_q <= 4'd13;
							else begin
								mby_q <= mby_q + 8'd1;
								st_q <= 4'd1;
							end
						end
						else begin
							have_left <= 1'b1;
							mbx_q <= mbx_q + 8'd1;
							st_q <= 4'd1;
						end
					end
				4'd13: st_q <= 4'd0;
				4'd14: st_q <= 4'd14;
				default: st_q <= 4'd14;
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
	mb_i16,
	mb_cbp,
	mb_qp,
	mb_i16_mode,
	mb_cmode,
	mb_i4m,
	busy,
	rec_valid,
	rec_y,
	rec_u,
	rec_v,
	err
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
	input wire mb_i16;
	input wire [5:0] mb_cbp;
	input wire [5:0] mb_qp;
	input wire [1:0] mb_i16_mode;
	input wire [1:0] mb_cmode;
	input wire [63:0] mb_i4m;
	output wire busy;
	output wire rec_valid;
	output reg [2047:0] rec_y;
	output reg [511:0] rec_u;
	output reg [511:0] rec_v;
	output wire err;
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
	reg signed [15:0] cram [0:26][0:15];
	reg [7:0] top_y [0:(MAX_MBW * 16) - 1];
	reg [7:0] top_u [0:(MAX_MBW * 8) - 1];
	reg [7:0] top_v [0:(MAX_MBW * 8) - 1];
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
	reg comp_q;
	assign busy = st_q != 4'd0;
	assign rec_valid = st_q == 4'd10;
	assign err = st_q == 4'd11;
	reg signed [255:0] ldc_in;
	wire signed [511:0] ldc_out;
	always @(*) begin : sv2v_autoblock_1
		reg signed [31:0] i;
		if (_sv2v_0)
			;
		for (i = 0; i < 16; i = i + 1)
			ldc_in[(15 - i) * 16+:16] = cram[16][i];
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
	always @(*) begin : sv2v_autoblock_2
		reg signed [7:0] qsum;
		if (_sv2v_0)
			;
		qsum = $signed({2'b00, qp_q}) + sv2v_cast_8_signed(cfg_cqp_off);
		if (qsum < 0)
			qsum = 0;
		if (qsum > 51)
			qsum = 51;
		qpc = chroma_qp(sv2v_cast_6_signed(qsum));
		begin : sv2v_autoblock_3
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				cdc_in[(3 - i) * 16+:16] = cram[17 + comp_q][i];
		end
	end
	chroma_dc_dequant u_cdc(
		.c(cdc_in),
		.qp(qpc),
		.dc(cdc_out)
	);
	reg signed [31:0] cdc_q [0:3];
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
	function automatic signed [11:0] sv2v_cast_12_signed;
		input reg signed [11:0] inp;
		sv2v_cast_12_signed = inp;
	endfunction
	function automatic signed [31:0] sv2v_cast_32_signed;
		input reg signed [31:0] inp;
		sv2v_cast_32_signed = inp;
	endfunction
	always @(*) begin : sv2v_autoblock_4
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
		begin : sv2v_autoblock_5
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				n_l[(3 - i) * 8+:8] = (bx4 == 0 ? left_y[py + i] : rec_y[(256 - (((py + i) * 16) + px)) * 8+:8]);
		end
		begin : sv2v_autoblock_6
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				n_t[(7 - i) * 8+:8] = (by4 == 0 ? top_y[{mbx_q, 4'b0000} + sv2v_cast_12_signed(px + i)] : rec_y[(255 - ((((py - 1) * 16) + px) + i)) * 8+:8]);
		end
		begin : sv2v_autoblock_7
			reg signed [31:0] i;
			for (i = 0; i < 4; i = i + 1)
				begin : sv2v_autoblock_8
					reg [7:0] e;
					if (!a_tr)
						e = n_t[32+:8];
					else if (by4 == 0)
						e = top_y[{mbx_q, 4'b0000} + sv2v_cast_12_signed((px + 4) + i)];
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
			n_tl = top_y[{mbx_q, 4'b0000} + sv2v_cast_12_signed(px - 1)];
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
		begin : sv2v_autoblock_9
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				begin
					i16_l[(15 - i) * 8+:8] = left_y[i];
					i16_t[(15 - i) * 8+:8] = top_y[{mbx_q, 4'b0000} + sv2v_cast_12_signed(i)];
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
	function automatic signed [10:0] sv2v_cast_11_signed;
		input reg signed [10:0] inp;
		sv2v_cast_11_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_10
			reg signed [31:0] i;
			for (i = 0; i < 8; i = i + 1)
				begin
					ch_l[(7 - i) * 8+:8] = (comp_q ? left_v[i] : left_u[i]);
					ch_t[(7 - i) * 8+:8] = (comp_q ? top_v[{mbx_q, 3'b000} + sv2v_cast_11_signed(i)] : top_u[{mbx_q, 3'b000} + sv2v_cast_11_signed(i)]);
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
		begin : sv2v_autoblock_11
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				begin
					dq_in[(15 - i) * 16+:16] = 1'sb0;
					id_pred[i] = 1'sb0;
				end
		end
		if ((st_q == 4'd3) || (st_q == 4'd4)) begin : sv2v_autoblock_12
			reg signed [31:0] px;
			reg signed [31:0] py;
			px = sv2v_cast_32_signed(bx4) * 4;
			py = sv2v_cast_32_signed(by4) * 4;
			begin : sv2v_autoblock_13
				reg signed [31:0] i;
				for (i = 0; i < 16; i = i + 1)
					dq_in[(15 - i) * 16+:16] = cram[k_q][i];
			end
			begin : sv2v_autoblock_14
				reg signed [31:0] y;
				for (y = 0; y < 4; y = y + 1)
					begin : sv2v_autoblock_15
						reg signed [31:0] x;
						for (x = 0; x < 4; x = x + 1)
							id_pred[(y * 4) + x] = (i16_q ? rec_y[(255 - ((((py + y) * 16) + px) + x)) * 8+:8] : p4[(15 - ((y * 4) + x)) * 8+:8]);
					end
			end
		end
		else if ((st_q == 4'd7) || (st_q == 4'd8)) begin : sv2v_autoblock_16
			reg signed [31:0] px;
			reg signed [31:0] py;
			px = (sv2v_cast_32_signed(k_q) & 1) * 4;
			py = ((sv2v_cast_32_signed(k_q) >> 1) & 1) * 4;
			begin : sv2v_autoblock_17
				reg signed [31:0] i;
				for (i = 0; i < 16; i = i + 1)
					dq_in[(15 - i) * 16+:16] = cram[(19 + ({3'b000, comp_q} * 4)) + (k_q & 5'd3)][i];
			end
			begin : sv2v_autoblock_18
				reg signed [31:0] y;
				for (y = 0; y < 4; y = y + 1)
					begin : sv2v_autoblock_19
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
		begin : sv2v_autoblock_20
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
		end
		else begin
			if (coef_we)
				cram[coef_blk][coef_addr] <= coef_data;
			(* full_case, parallel_case *)
			case (st_q)
				4'd0:
					if (mb_valid) begin
						mbx_q <= mb_x;
						mby_q <= mb_y;
						i16_q <= mb_i16;
						cbp_q <= mb_cbp;
						qp_q <= mb_qp;
						i16m_q <= mb_i16_mode;
						cmode_q <= mb_cmode;
						begin : sv2v_autoblock_21
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								i4m_q[i] <= mb_i4m[i * 4+:4];
						end
						have_left <= mb_x != 8'd0;
						have_top <= mb_y != 8'd0;
						tlq_y <= tl_y;
						tlq_u <= tl_u;
						tlq_v <= tl_v;
						tl_y <= top_y[{mb_x, 4'b0000} + 12'd15];
						tl_u <= top_u[{mb_x, 3'b000} + 11'd7];
						tl_v <= top_v[{mb_x, 3'b000} + 11'd7];
						st_q <= (mb_i16 ? 4'd1 : 4'd3);
						k_q <= 1'sb0;
					end
				4'd1: begin
					begin : sv2v_autoblock_22
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							ldc_q[i] <= ldc_out[(15 - i) * 32+:32];
					end
					st_q <= 4'd2;
				end
				4'd2:
					if (!p16_ok)
						st_q <= 4'd11;
					else begin
						begin : sv2v_autoblock_23
							reg signed [31:0] i;
							for (i = 0; i < 256; i = i + 1)
								rec_y[(255 - i) * 8+:8] <= p16[(255 - i) * 8+:8];
						end
						st_q <= 4'd3;
					end
				4'd3:
					if (!i16_q && !p4_ok)
						st_q <= 4'd11;
					else begin
						begin : sv2v_autoblock_24
							reg signed [31:0] i;
							for (i = 0; i < 16; i = i + 1)
								begin
									id_in_q[(15 - i) * 32+:32] <= id_in[i];
									id_pred_q[(15 - i) * 8+:8] <= id_pred[i];
								end
						end
						st_q <= 4'd4;
					end
				4'd4: begin : sv2v_autoblock_25
					reg signed [31:0] px;
					reg signed [31:0] py;
					px = sv2v_cast_32_signed(bx4) * 4;
					py = sv2v_cast_32_signed(by4) * 4;
					begin : sv2v_autoblock_26
						reg signed [31:0] y;
						for (y = 0; y < 4; y = y + 1)
							begin : sv2v_autoblock_27
								reg signed [31:0] x;
								for (x = 0; x < 4; x = x + 1)
									rec_y[(255 - ((((py + y) * 16) + px) + x)) * 8+:8] <= id_out[(15 - ((y * 4) + x)) * 8+:8];
							end
					end
					if (k_q == 5'd15) begin
						k_q <= 1'sb0;
						comp_q <= 1'b0;
						st_q <= 4'd5;
					end
					else begin
						k_q <= k_q + 5'd1;
						st_q <= 4'd3;
					end
				end
				4'd5:
					if (!pch_ok)
						st_q <= 4'd11;
					else if (!comp_q) begin
						begin : sv2v_autoblock_28
							reg signed [31:0] i;
							for (i = 0; i < 64; i = i + 1)
								rec_u[(63 - i) * 8+:8] <= pch[(63 - i) * 8+:8];
						end
						comp_q <= 1'b1;
					end
					else begin
						begin : sv2v_autoblock_29
							reg signed [31:0] i;
							for (i = 0; i < 64; i = i + 1)
								rec_v[(63 - i) * 8+:8] <= pch[(63 - i) * 8+:8];
						end
						comp_q <= 1'b0;
						k_q <= 1'sb0;
						st_q <= (cbp_q[5:4] != 2'd0 ? 4'd6 : 4'd9);
					end
				4'd6: begin
					begin : sv2v_autoblock_30
						reg signed [31:0] i;
						for (i = 0; i < 4; i = i + 1)
							cdc_q[i] <= cdc_out[(3 - i) * 32+:32];
					end
					k_q <= 1'sb0;
					st_q <= 4'd7;
				end
				4'd7: begin
					begin : sv2v_autoblock_31
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							begin
								id_in_q[(15 - i) * 32+:32] <= id_in[i];
								id_pred_q[(15 - i) * 8+:8] <= id_pred[i];
							end
					end
					st_q <= 4'd8;
				end
				4'd8: begin : sv2v_autoblock_32
					reg signed [31:0] px;
					reg signed [31:0] py;
					px = (sv2v_cast_32_signed(k_q) & 1) * 4;
					py = ((sv2v_cast_32_signed(k_q) >> 1) & 1) * 4;
					if (comp_q) begin : sv2v_autoblock_33
						reg signed [31:0] y;
						for (y = 0; y < 4; y = y + 1)
							begin : sv2v_autoblock_34
								reg signed [31:0] x;
								for (x = 0; x < 4; x = x + 1)
									rec_v[(63 - ((((py + y) * 8) + px) + x)) * 8+:8] <= id_out[(15 - ((y * 4) + x)) * 8+:8];
							end
					end
					else begin : sv2v_autoblock_35
						reg signed [31:0] y;
						for (y = 0; y < 4; y = y + 1)
							begin : sv2v_autoblock_36
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
				4'd9: begin
					begin : sv2v_autoblock_37
						reg signed [31:0] i;
						for (i = 0; i < 16; i = i + 1)
							begin
								top_y[{mbx_q, 4'b0000} + sv2v_cast_12_signed(i)] <= rec_y[(255 - (240 + i)) * 8+:8];
								left_y[i] <= rec_y[(255 - ((i * 16) + 15)) * 8+:8];
							end
					end
					begin : sv2v_autoblock_38
						reg signed [31:0] i;
						for (i = 0; i < 8; i = i + 1)
							begin
								top_u[{mbx_q, 3'b000} + sv2v_cast_11_signed(i)] <= rec_u[(63 - (56 + i)) * 8+:8];
								top_v[{mbx_q, 3'b000} + sv2v_cast_11_signed(i)] <= rec_v[(63 - (56 + i)) * 8+:8];
								left_u[i] <= rec_u[(63 - ((i * 8) + 7)) * 8+:8];
								left_v[i] <= rec_v[(63 - ((i * 8) + 7)) * 8+:8];
							end
					end
					st_q <= 4'd10;
				end
				4'd10: begin
					begin : sv2v_autoblock_39
						reg signed [31:0] b;
						for (b = 0; b < 27; b = b + 1)
							begin : sv2v_autoblock_40
								reg signed [31:0] i;
								for (i = 0; i < 16; i = i + 1)
									cram[b][i] <= 1'sb0;
							end
					end
					st_q <= 4'd0;
				end
				4'd11: st_q <= 4'd11;
				default: st_q <= 4'd11;
			endcase
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
