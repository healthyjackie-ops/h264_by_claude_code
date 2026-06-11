// h264_core — synthesis top (rtl_spec.md R3c): the per-MB decode engine
// (bitreader -> mb_dec -> cavlc_block -> mb_recon) without the frame
// buffer; reconstructed macroblocks stream out and deblocking runs
// against external storage in a real system. deblock_edge is included
// standalone for its own timing/area numbers.
module h264_core #(
    parameter int MAX_MBW = 120        // 1080p line buffers
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    input  logic [7:0]  in_byte,
    output logic        in_ready,

    input  logic [7:0]  cfg_mb_w,
    input  logic [7:0]  cfg_mb_h,
    input  logic [5:0]  cfg_qp,
    input  logic signed [5:0] cfg_cqp_off,

    input  logic        start,
    input  logic        align_valid,
    input  logic [4:0]  align_bits,
    input  logic        rec_taken,     // downstream consumed the MB

    output logic        mb_out_valid,
    output logic [7:0]  mb_out_x,
    output logic [7:0]  mb_out_y,
    output logic [5:0]  mb_out_qp,
    output logic [7:0]  out_y [256],
    output logic [7:0]  out_u [64],
    output logic [7:0]  out_v [64],

    output logic        slice_done,
    output logic        err
);

    logic        br_req_valid;
    logic [4:0]  br_req_bits;
    logic        br_req_ready;
    logic [23:0] show;
    logic [6:0]  avail;

    logic m_req_valid, b_req_valid;
    logic [4:0] m_req_bits, b_req_bits;
    assign br_req_valid = align_valid | m_req_valid | b_req_valid;
    assign br_req_bits = align_valid ? align_bits
                         : (b_req_valid ? b_req_bits : m_req_bits);

    bitreader u_br (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_byte(in_byte), .in_ready(in_ready),
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

    logic mb_valid;
    logic [7:0] mb_x, mb_y;
    logic mb_i16;
    logic [5:0] mb_cbp, mb_qp;
    logic [1:0] mb_i16_mode, mb_cmode;
    logic [63:0] mb_i4m;
    logic coef_we;
    logic [4:0] coef_blk;
    logic [3:0] coef_addr;
    logic signed [15:0] coef_data;
    logic mb_err, rec_valid, rec_err;

    mb_dec #(.MAX_MBW(MAX_MBW)) u_mb (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp),
        .start(start),
        .req_valid(m_req_valid), .req_bits(m_req_bits),
        .req_ready(br_req_ready), .show(show),
        .blk_start(blk_start), .blk_chroma_dc(blk_chroma_dc),
        .blk_nc_class(blk_nc_class), .blk_maxc(blk_maxc),
        .blk_busy(blk_busy), .blk_done(blk_done), .blk_err(blk_err),
        .blk_tc(blk_tc), .blk_coef_we(blk_coef_we),
        .blk_coef_addr(blk_coef_addr), .blk_coef_data(blk_coef_data),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y), .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .slice_done(slice_done), .err(mb_err),
        .rec_done(rec_valid && rec_taken)
    );

    mb_recon #(.MAX_MBW(MAX_MBW)) u_rec (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_cqp_off(cfg_cqp_off),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y), .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .busy(), .rec_valid(rec_valid),
        .rec_y(out_y), .rec_u(out_u), .rec_v(out_v),
        .err(rec_err)
    );

    assign mb_out_valid = rec_valid;
    assign mb_out_x = mb_x;
    assign mb_out_y = mb_y;
    assign mb_out_qp = mb_qp;
    assign err = mb_err | rec_err | blk_err;

endmodule
