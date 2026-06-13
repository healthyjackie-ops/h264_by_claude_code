// h264_core — synthesis top (rtl_spec.md R3c, deblock integrated R4g,
// P slices P-R3e): bitreader -> mb_dec -> cavlc_block -> (mv_pred) ->
// mb_recon (MC) -> deblock_stream. The complete baseline I/P decoder:
// bitstream in, filtered macroblock rows out, only line buffers inside.
// The reference frame stays system-side behind the row-read channel
// (DDR in silicon); the system feeds back decoded frames as references.
module h264_core #(
    parameter int MAX_MBW = 120        // 1080p line buffers
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    input  logic [31:0] in_word,
    input  logic [2:0]  in_bytes,
    output logic        in_ready,

    input  logic [7:0]  cfg_mb_w,
    input  logic [7:0]  cfg_mb_h,
    input  logic [5:0]  cfg_qp,
    input  logic signed [5:0] cfg_cqp_off,
    input  logic signed [5:0] cfg_a_off,
    input  logic signed [5:0] cfg_b_off,
    input  logic        cfg_deblock,
    input  logic        cfg_is_p,
    input  logic        cfg_is_b,
    input  logic        cfg_cabac,
    input  logic [1:0]  cfg_init_idc,

    input  logic        start,
    input  logic        align_valid,
    input  logic [4:0]  align_bits,

    // filtered output row stream (deblock_stream contract)
    output logic        out_valid,
    output logic [7:0]  out_mbx,
    output logic [7:0]  out_mby,
    output logic [1:0]  out_plane,
    output logic [3:0]  out_row,
    output logic [127:0] out_data,

    // reference-frame row-read channel (P slices)
    output logic        mc_req_valid,
    output logic [1:0]  mc_req_plane,
    output logic signed [12:0] mc_req_x,
    output logic signed [11:0] mc_req_y,
    output logic [3:0]  mc_req_w,
    input  logic        mc_rsp_valid,
    input  logic [71:0] mc_rsp_data,

    output logic        frame_done,
    output logic        err
);

    logic        br_req_valid;
    logic [4:0]  br_req_bits;
    logic        br_req_ready;
    logic [23:0] show;
    logic [6:0]  avail;

    logic m_req_valid, b_req_valid, c_req_valid;
    logic [4:0] m_req_bits, b_req_bits, c_req_bits;
    assign br_req_valid = align_valid | m_req_valid | b_req_valid |
                          c_req_valid;
    assign br_req_bits = align_valid ? align_bits
                         : c_req_valid ? c_req_bits
                         : (b_req_valid ? b_req_bits : m_req_bits);

    bitreader u_br (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_word(in_word), .in_bytes(in_bytes),
        .in_ready(in_ready),
        .req_valid(br_req_valid), .req_bits(br_req_bits),
        .req_ready(br_req_ready),
        .show(show), .avail(avail)
    );

    logic blk_start, blk_chroma_dc;
    logic [1:0] blk_nc_class;
    logic [4:0] blk_maxc;
    logic blk_busy, blk_done, blk_err;
    logic [4:0] blk_tc;
    logic blk_coef_we;
    logic [3:0] blk_coef_addr;
    logic signed [15:0] blk_coef_data;

    cavlc_block u_blk (
        .clk(clk), .rst_n(rst_n),
        .req_valid(b_req_valid), .req_bits(b_req_bits),
        .req_ready(br_req_ready), .show(show), .avail(avail),
        .start(blk_start), .chroma_dc(blk_chroma_dc),
        .nc_class(blk_nc_class), .maxc(blk_maxc),
        .busy(blk_busy), .done(blk_done), .tc_out(blk_tc), .err(blk_err),
        .coef_we(blk_coef_we), .coef_addr(blk_coef_addr),
        .coef_data(blk_coef_data)
    );

    logic mb_valid, mb_valid_v;
    logic [7:0] mb_x, mb_y, mb_x_v, mb_y_v;
    logic mb_i16, mb_i16_v;
    logic [5:0] mb_cbp, mb_qp, mb_cbp_v, mb_qp_v;
    logic [1:0] mb_i16_mode, mb_cmode, mb_i16_mode_v, mb_cmode_v;
    logic [63:0] mb_i4m, mb_i4m_v;
    logic coef_we, coef_we_v;
    logic [4:0] coef_blk, coef_blk_v;
    logic [3:0] coef_addr, coef_addr_v;
    logic signed [15:0] coef_data, coef_data_v;
    logic [15:0] mb_nz_v;
    logic slice_done_v, mb_err_v;
    logic mb_err, rec_valid, rec_err, rec_accept;
    logic [7:0] rec_x, rec_yc;
    logic [5:0] rec_qp;


    logic        mb_skip, mb_inter, skip_go_w, mvd_valid;
    logic [15:0] mb_nz_w;
    logic [4:0]  mb_ptype;
    logic [15:0] mb_sub;
    logic signed [15:0] mvd_x, mvd_y;
    logic signed [15:0] mv_x_w [16];
    logic signed [15:0] mv_y_w [16];

    mb_dec #(.MAX_MBW(MAX_MBW)) u_mb (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp),
        .cfg_is_p(cfg_is_p), .cfg_is_b(cfg_is_b),
        .start(start && !cfg_cabac),
        .req_valid(m_req_valid), .req_bits(m_req_bits),
        .req_ready(br_req_ready), .show(show), .avail(avail),
        .blk_start(blk_start), .blk_chroma_dc(blk_chroma_dc),
        .blk_nc_class(blk_nc_class), .blk_maxc(blk_maxc),
        .blk_busy(blk_busy), .blk_done(blk_done), .blk_err(blk_err),
        .blk_tc(blk_tc), .blk_coef_we(blk_coef_we),
        .blk_coef_addr(blk_coef_addr), .blk_coef_data(blk_coef_data),
        .mb_skip(mb_skip), .mb_inter(mb_inter), .mb_ptype(mb_ptype),
        .mb_sub(mb_sub), .mvd_valid(mvd_valid), .mvd_x(mvd_x),
        .mvd_y(mvd_y), .skip_go(skip_go_w), .mb_nz(mb_nz_v), .mvd_list(),
        .mb_valid(mb_valid_v), .mb_x(mb_x_v), .mb_y(mb_y_v),
        .mb_i16(mb_i16_v),
        .mb_cbp(mb_cbp_v), .mb_qp(mb_qp_v), .mb_i16_mode(mb_i16_mode_v),
        .mb_cmode(mb_cmode_v), .mb_i4m(mb_i4m_v),
        .coef_we(coef_we_v), .coef_blk(coef_blk_v),
        .coef_addr(coef_addr_v), .coef_data(coef_data_v),
        .slice_done(slice_done_v), .err(mb_err_v),
        .rec_done(rec_accept)
    );

    // CABAC twin: same downstream contract, selected by cfg_cabac
    logic        mb_valid_c, slice_done_c, mb_err_c, coef_we_c;
    logic [7:0]  mb_x_c, mb_y_c;
    logic        mb_i16_c;
    logic [5:0]  mb_cbp_c, mb_qp_c;
    logic [1:0]  mb_i16_mode_c, mb_cmode_c;
    logic [63:0] mb_i4m_c;
    logic [4:0]  coef_blk_c;
    logic [3:0]  coef_addr_c;
    logic signed [15:0] coef_data_c;
    logic        mb_skip_c, mb_inter_c, mvd_valid_c, skip_go_c;
    logic [4:0]  mb_ptype_c;
    logic [15:0] mb_sub_c;
    logic signed [15:0] mvd_x_c, mvd_y_c;
    logic [15:0] mb_nz_c;

    cabac_mb #(.MAX_MBW(MAX_MBW)) u_cm (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp),
        .start(start && cfg_cabac),
        .req_valid(c_req_valid), .req_bits(c_req_bits),
        .req_ready(br_req_ready), .show(show), .avail(avail),
        .cfg_is_p(cfg_is_p), .cfg_init_idc(cfg_init_idc),
        .mb_skip(mb_skip_c), .mb_inter(mb_inter_c),
        .mb_ptype(mb_ptype_c), .mb_sub(mb_sub_c),
        .mvd_valid(mvd_valid_c), .mvd_x(mvd_x_c), .mvd_y(mvd_y_c),
        .skip_go(skip_go_c), .mb_nz(mb_nz_c),
        .mb_valid(mb_valid_c), .mb_x(mb_x_c), .mb_y(mb_y_c),
        .mb_i16(mb_i16_c),
        .mb_cbp(mb_cbp_c), .mb_qp(mb_qp_c), .mb_i16_mode(mb_i16_mode_c),
        .mb_cmode(mb_cmode_c), .mb_i4m(mb_i4m_c),
        .coef_we(coef_we_c), .coef_blk(coef_blk_c),
        .coef_addr(coef_addr_c), .coef_data(coef_data_c),
        .slice_done(slice_done_c), .err(mb_err_c),
        .rec_done(rec_accept)
    );

    assign mb_valid = cfg_cabac ? mb_valid_c : mb_valid_v;
    assign mb_x = cfg_cabac ? mb_x_c : mb_x_v;
    assign mb_y = cfg_cabac ? mb_y_c : mb_y_v;
    assign mb_i16 = cfg_cabac ? mb_i16_c : mb_i16_v;
    assign mb_cbp = cfg_cabac ? mb_cbp_c : mb_cbp_v;
    assign mb_qp = cfg_cabac ? mb_qp_c : mb_qp_v;
    assign mb_i16_mode = cfg_cabac ? mb_i16_mode_c : mb_i16_mode_v;
    assign mb_cmode = cfg_cabac ? mb_cmode_c : mb_cmode_v;
    assign mb_i4m = cfg_cabac ? mb_i4m_c : mb_i4m_v;
    assign coef_we = cfg_cabac ? coef_we_c : coef_we_v;
    assign coef_blk = cfg_cabac ? coef_blk_c : coef_blk_v;
    assign coef_addr = cfg_cabac ? coef_addr_c : coef_addr_v;
    assign coef_data = cfg_cabac ? coef_data_c : coef_data_v;
    assign slice_done = cfg_cabac ? slice_done_c : slice_done_v;
    assign mb_err = cfg_cabac ? mb_err_c : mb_err_v;
    assign mb_nz_w = cfg_cabac ? mb_nz_c : mb_nz_v;

    // P syntax stream mux into mv_pred / mb_recon / deblock
    logic mb_skip_m, mb_inter_m, mvd_valid_m, skip_go_m;
    logic [4:0] mb_ptype_m;
    logic [15:0] mb_sub_m;
    logic signed [15:0] mvd_x_m, mvd_y_m;
    assign mb_skip_m = cfg_cabac ? mb_skip_c : mb_skip;
    assign mb_inter_m = cfg_cabac ? mb_inter_c : mb_inter;
    assign mb_ptype_m = cfg_cabac ? mb_ptype_c : mb_ptype;
    assign mb_sub_m = cfg_cabac ? mb_sub_c : mb_sub;
    assign mvd_valid_m = cfg_cabac ? mvd_valid_c : mvd_valid;
    assign mvd_x_m = cfg_cabac ? mvd_x_c : mvd_x;
    assign mvd_y_m = cfg_cabac ? mvd_y_c : mvd_y;
    assign skip_go_m = cfg_cabac ? skip_go_c : skip_go_w;


    mv_pred #(.MAX_MBW(MAX_MBW)) u_mv (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .start(start),
        .mb_ptype(mb_ptype_m), .mb_sub(mb_sub_m),
        .mvd_valid(mvd_valid_m), .mvd_x(mvd_x_m), .mvd_y(mvd_y_m),
        .skip_go(skip_go_m), .commit(rec_accept),
        .mb_inter(mb_inter_m), .mb_skip(mb_skip_m),
        .mv_out_x(mv_x_w), .mv_out_y(mv_y_w)
    );

    logic [7:0] rec_py [256];
    logic [7:0] rec_pu [64];
    logic [7:0] rec_pv [64];
    logic dbf_ready, rec_busy;
    logic slice_done;

    mb_recon #(.MAX_MBW(MAX_MBW)) u_rec (
        .mb_inter(mb_inter_m), .mb_nz(mb_nz_w),
        .mb_mvx(mv_x_w), .mb_mvy(mv_y_w),
        .mc_req_valid(mc_req_valid), .mc_req_plane(mc_req_plane),
        .mc_req_x(mc_req_x), .mc_req_y(mc_req_y), .mc_req_w(mc_req_w),
        .mc_rsp_valid(mc_rsp_valid), .mc_rsp_data(mc_rsp_data),
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_cqp_off(cfg_cqp_off),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y), .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .busy(rec_busy), .accepted(rec_accept), .out_ready(dbf_ready),
        .rec_x(rec_x), .rec_yc(rec_yc), .rec_qp(rec_qp),
        .rec_valid(rec_valid),
        .rec_y(rec_py), .rec_u(rec_pu), .rec_v(rec_pv),
        .rec_inter(rec_inter), .rec_nz(rec_nz),
        .rec_mvx(rec_mvx), .rec_mvy(rec_mvy),
        .err(rec_err)
    );

    logic        rec_inter;
    logic [15:0] rec_nz;
    logic signed [15:0] rec_mvx [16];
    logic signed [15:0] rec_mvy [16];

    // flush once parsing is done and the last MB has reconstructed
    logic slice_done_q, flush_q, dbf_done;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slice_done_q <= 1'b0;
            flush_q <= 1'b0;
        end else begin
            if (slice_done) slice_done_q <= 1'b1;
            if (slice_done_q && !rec_busy && !rec_valid && dbf_ready &&
                !flush_q) begin
                flush_q <= 1'b1;       // one-shot
            end
        end
    end

    deblock_stream #(.MAX_MBW(MAX_MBW)) u_dbf (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h),
        .cfg_cqp_off(cfg_cqp_off),
        .cfg_a_off(cfg_a_off), .cfg_b_off(cfg_b_off),
        .cfg_enable(cfg_deblock),
        .mb_push(rec_valid), .mb_x(rec_x), .mb_y(rec_yc), .mb_qp(rec_qp),
        .mb_inter(rec_inter), .mb_nz(rec_nz),
        .mb_mvx(rec_mvx), .mb_mvy(rec_mvy),
        .in_y(rec_py), .in_u(rec_pu), .in_v(rec_pv),
        .mb_ready(dbf_ready),
        .flush(flush_q && !dbf_done), .flush_done(dbf_done),
        .out_valid(out_valid), .out_mbx(out_mbx), .out_mby(out_mby),
        .out_plane(out_plane), .out_row(out_row), .out_data(out_data)
    );

    assign frame_done = dbf_done;
    assign err = mb_err | rec_err | blk_err;

endmodule
