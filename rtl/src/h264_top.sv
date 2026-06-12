// h264_top — the full baseline-I decode chain (rtl_spec.md R3b):
// bitreader -> mb_dec -> cavlc_block (residuals) -> mb_recon ->
// deblock_frame. One slice per frame; mb_dec stalls after each MB until
// reconstruction completes, the reconstructed MB streams into the
// deblock frame buffer, and slice_done triggers the filter pass.
module h264_top #(
    parameter int MAX_MBW = 20,        // 320 wide
    parameter int MAX_W = 320,
    parameter int MAX_H = 240
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
    input  logic        cfg_deblock,   // 0 = bypass filter

    input  logic        start,
    input  logic        align_valid,
    input  logic [4:0]  align_bits,

    output logic        frame_done,
    output logic        err,

    input  logic [16:0] rd_addr,
    input  logic [1:0]  rd_plane,
    output logic [7:0]  rd_data
);

    // ---- bitreader with three requesters (align / mb_dec / cavlc) ----
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

    // ---- residual engine ----
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

    // ---- MB layer ----
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
    logic slice_done, mb_err;
    logic rec_valid, rec_err, rec_accept;
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

    // ---- reconstruction ----
    logic [7:0] rec_y [256];
    logic [7:0] rec_u [64];
    logic [7:0] rec_v [64];

    mb_recon #(.MAX_MBW(MAX_MBW)) u_rec (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_cqp_off(cfg_cqp_off),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y), .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .busy(rec_busy), .accepted(rec_accept), .out_ready(1'b1),
        .rec_x(rec_x), .rec_yc(rec_yc), .rec_qp(rec_qp),
        .rec_valid(rec_valid),
        .rec_y(rec_y), .rec_u(rec_u), .rec_v(rec_v),
        .err(rec_err)
    );

    // deblock push uses mb_recon's LATCHED coords/qp — with parsing
    // pipelined ahead, mb_dec's live ports already show the next MB
    logic frame_go;
    logic dbf_done;
    logic [7:0] dbf_rd;
    // the parser finishes ahead of the last reconstruction: hold the
    // filter launch until recon is idle again
    logic rec_busy;
    logic slice_done_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) slice_done_q <= 1'b0;
        else if (slice_done) slice_done_q <= 1'b1;
        else if (frame_go) slice_done_q <= 1'b0;
    end
    assign frame_go = slice_done_q && !rec_busy;

    deblock_frame #(.MAX_W(MAX_W), .MAX_H(MAX_H)) u_dbf (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h),
        .cfg_cqp_off(cfg_cqp_off),
        .cfg_a_off(cfg_a_off), .cfg_b_off(cfg_b_off),
        .mb_push(rec_valid), .mb_x(rec_x), .mb_y(rec_yc), .mb_qp(rec_qp),
        .in_y(rec_y), .in_u(rec_u), .in_v(rec_v),
        .frame_go(frame_go && cfg_deblock),
        .frame_done(dbf_done), .busy(),
        .rd_addr(rd_addr), .rd_plane(rd_plane), .rd_data(dbf_rd)
    );
    assign frame_done = cfg_deblock ? dbf_done
                                    : (slice_done_q && !rec_busy);
    assign rd_data = dbf_rd;           // buffer holds unfiltered pixels
                                       // when cfg_deblock=0 (no filter ran)
    assign err = mb_err | rec_err | blk_err;

endmodule
