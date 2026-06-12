// h264_core — synthesis top (rtl_spec.md R3c, deblock integrated R4g):
// bitreader -> mb_dec -> cavlc_block -> mb_recon -> deblock_stream.
// The complete baseline-I decoder: bitstream in, filtered macroblock
// rows out, with only line buffers inside (no frame storage).
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

    output logic        frame_done,
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
    logic mb_err, rec_valid, rec_err, rec_accept;
    logic [7:0] rec_x, rec_yc;
    logic [5:0] rec_qp;

    mb_dec #(.MAX_MBW(MAX_MBW)) u_mb (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp), .cfg_is_p(1'b0),
        .start(start),
        .req_valid(m_req_valid), .req_bits(m_req_bits),
        .req_ready(br_req_ready), .show(show), .avail(avail),
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
        .rec_done(rec_accept)
    );

    logic [7:0] rec_py [256];
    logic [7:0] rec_pu [64];
    logic [7:0] rec_pv [64];
    logic dbf_ready, rec_busy;
    logic slice_done;

    // I-only cores: inter path tied off
    logic signed [15:0] zero_mv [16];
    always_comb for (int zi = 0; zi < 16; zi++) zero_mv[zi] = '0;

    mb_recon #(.MAX_MBW(MAX_MBW)) u_rec (
        .mb_inter(1'b0), .mb_mvx(zero_mv), .mb_mvy(zero_mv),
        .mc_req_valid(), .mc_req_plane(), .mc_req_x(), .mc_req_y(),
        .mc_req_w(),
        .mc_rsp_valid(1'b0), .mc_rsp_data('0),
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
        .err(rec_err)
    );

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
        .in_y(rec_py), .in_u(rec_pu), .in_v(rec_pv),
        .mb_ready(dbf_ready),
        .flush(flush_q && !dbf_done), .flush_done(dbf_done),
        .out_valid(out_valid), .out_mbx(out_mbx), .out_mby(out_mby),
        .out_plane(out_plane), .out_row(out_row), .out_data(out_data)
    );

    assign frame_done = dbf_done;
    assign err = mb_err | rec_err | blk_err;

endmodule
