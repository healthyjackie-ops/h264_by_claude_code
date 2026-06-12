// mb_top — R1c integration: bitreader + mb_dec + cavlc_block. The two
// consumers share the bitreader through a strict mux: while the residual
// engine is busy (or starting) its requests win; otherwise the MB layer
// drives. Both never request in the same cycle by construction (mb_dec
// parks in S_RES_WAIT while the block engine runs).
module mb_top #(
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
    input  logic        start,

    // bit-alignment: consume n residue bits before starting (slice_data
    // rarely begins byte-aligned); pulse align_valid with align_bits
    input  logic        align_valid,
    input  logic [4:0]  align_bits,

    output logic        mb_valid,
    output logic [7:0]  mb_x,
    output logic [7:0]  mb_y,
    output logic        mb_i16,
    output logic [5:0]  mb_cbp,
    output logic [5:0]  mb_qp,
    output logic [1:0]  mb_i16_mode,
    output logic [1:0]  mb_cmode,
    output logic [63:0] mb_i4m,

    output logic        coef_we,
    output logic [4:0]  coef_blk,
    output logic [3:0]  coef_addr,
    output logic signed [15:0] coef_data,

    output logic        slice_done,
    output logic        err,
    output logic [6:0]  avail
);

    logic        br_req_valid;
    logic [4:0]  br_req_bits;
    logic        br_req_ready;
    logic [23:0] show;

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

    mb_dec #(.MAX_MBW(MAX_MBW)) u_mb (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp),
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
        .slice_done(slice_done), .err(err),
        .rec_done(1'b1)
    );

endmodule
