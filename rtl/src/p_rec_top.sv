// p_rec_top — P-R3d differential top: full P-slice reconstruction.
//
// bitreader + mb_dec (P syntax) + cavlc_block + mv_pred + mb_recon
// with the inter MC path. The reference frame stays outside (the bench
// owns it and answers the row-read channel with clamp semantics, as in
// silicon where it lives in DDR). Reconstructed MBs stream out exactly
// like h264_top's recon stage; no deblocking here — the differential
// targets the pre-filter reconstruction layer (DUMP_PREC).
module p_rec_top #(
    parameter int MAX_MBW = 120
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
    input  logic        cfg_is_p,
    input  logic        cfg_is_b,
    input  logic        start,

    input  logic        align_valid,
    input  logic [4:0]  align_bits,

    // reconstructed MB stream
    output logic        rec_valid,
    output logic [7:0]  rec_x,
    output logic [7:0]  rec_yc,
    output logic [7:0]  rec_y [256],
    output logic [7:0]  rec_u [64],
    output logic [7:0]  rec_v [64],

    // reference-frame row-read channel
    output logic        mc_req_valid,
    output logic [1:0]  mc_req_plane,
    output logic signed [12:0] mc_req_x,
    output logic signed [11:0] mc_req_y,
    output logic [3:0]  mc_req_w,
    input  logic        mc_rsp_valid,
    input  logic [71:0] mc_rsp_data,

    output logic        slice_done,
    output logic        err
);

    logic        br_req_valid;
    logic [4:0]  br_req_bits;
    logic        br_req_ready;
    logic [23:0] show;
    logic [6:0]  avail;

    logic        m_req_valid, b_req_valid;
    logic [4:0]  m_req_bits, b_req_bits;

    assign br_req_valid = align_valid | m_req_valid | b_req_valid;
    assign br_req_bits  = align_valid ? align_bits
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

    logic        mb_valid;
    logic [7:0]  mb_x, mb_y;
    logic        mb_i16;
    logic [5:0]  mb_cbp, mb_qp;
    logic [1:0]  mb_i16_mode, mb_cmode;
    logic [63:0] mb_i4m;
    logic        coef_we;
    logic [4:0]  coef_blk;
    logic [3:0]  coef_addr;
    logic signed [15:0] coef_data;
    logic        mb_err, rec_err;
    logic        rec_accept, rec_busy;

    logic        mb_skip, mb_inter, skip_go_w, mvd_valid;
    logic [15:0] mb_nz_w;
    logic [4:0]  mb_ptype;
    logic [15:0] mb_sub;
    logic signed [15:0] mvd_x, mvd_y;

    mb_dec #(.MAX_MBW(MAX_MBW)) u_mb (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp),
        .cfg_is_p(cfg_is_p), .cfg_is_b(cfg_is_b),
        .start(start),
        .req_valid(m_req_valid), .req_bits(m_req_bits),
        .req_ready(br_req_ready), .show(show), .avail(avail),
        .blk_start(blk_start), .blk_chroma_dc(blk_chroma_dc),
        .blk_nc_class(blk_nc_class), .blk_maxc(blk_maxc),
        .blk_busy(blk_busy), .blk_done(blk_done), .blk_err(blk_err),
        .blk_tc(blk_tc), .blk_coef_we(blk_coef_we),
        .blk_coef_addr(blk_coef_addr), .blk_coef_data(blk_coef_data),
        .mb_skip(mb_skip), .mb_inter(mb_inter), .mb_ptype(mb_ptype),
        .mb_sub(mb_sub), .mvd_valid(mvd_valid), .mvd_x(mvd_x),
        .mvd_y(mvd_y), .skip_go(skip_go_w), .mb_nz(mb_nz_w), .mvd_list(),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y), .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .slice_done(slice_done), .err(mb_err),
        .rec_done(rec_accept)
    );

    logic signed [15:0] mv_x_w [16];
    logic signed [15:0] mv_y_w [16];

    // neighbor advance happens on the accept beat (parse/recon pipeline)
    mv_pred #(.MAX_MBW(MAX_MBW)) u_mv (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .start(start),
        .mb_ptype(mb_ptype), .mb_sub(mb_sub),
        .mvd_valid(mvd_valid), .mvd_x(mvd_x), .mvd_y(mvd_y),
        .skip_go(skip_go_w), .commit(rec_accept),
        .mb_inter(mb_inter), .mb_skip(mb_skip),
        .mv_out_x(mv_x_w), .mv_out_y(mv_y_w)
    );

    mb_recon #(.MAX_MBW(MAX_MBW)) u_rec (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_cqp_off(cfg_cqp_off),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y),
        .mb_inter(mb_inter), .mb_nz(mb_nz_w),
        .mb_mvx(mv_x_w), .mb_mvy(mv_y_w),
        .rec_inter(), .rec_nz(), .rec_mvx(), .rec_mvy(),
        .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .busy(rec_busy), .accepted(rec_accept), .out_ready(1'b1),
        .rec_x(rec_x), .rec_yc(rec_yc), .rec_qp(),
        .rec_valid(rec_valid),
        .rec_y(rec_y), .rec_u(rec_u), .rec_v(rec_v),
        .err(rec_err),
        .mc_req_valid(mc_req_valid), .mc_req_plane(mc_req_plane),
        .mc_req_x(mc_req_x),
        .mc_req_y(mc_req_y), .mc_req_w(mc_req_w),
        .mc_rsp_valid(mc_rsp_valid), .mc_rsp_data(mc_rsp_data)
    );

    assign err = mb_err | rec_err | blk_err;

endmodule
