// cabac_top — W15-b/c differential top: bitreader + cabac_mb.
// CABAC slice_data is byte-aligned (cabac_alignment_one_bit), so no
// align port is needed; the bench feeds from the aligned byte.
module cabac_top #(
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
    output logic        err
);

    logic        req_valid;
    logic [4:0]  req_bits;
    logic        req_ready;
    logic [23:0] show;
    logic [6:0]  avail;

    bitreader u_br (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_word(in_word), .in_bytes(in_bytes),
        .in_ready(in_ready),
        .req_valid(req_valid), .req_bits(req_bits),
        .req_ready(req_ready),
        .show(show), .avail(avail)
    );

    cabac_mb #(.MAX_MBW(MAX_MBW)) u_cm (
        .clk(clk), .rst_n(rst_n),
        .cfg_mb_w(cfg_mb_w), .cfg_mb_h(cfg_mb_h), .cfg_qp(cfg_qp),
        .start(start),
        .req_valid(req_valid), .req_bits(req_bits), .req_ready(req_ready),
        .show(show), .avail(avail),
        .mb_valid(mb_valid), .mb_x(mb_x), .mb_y(mb_y), .mb_i16(mb_i16),
        .mb_cbp(mb_cbp), .mb_qp(mb_qp), .mb_i16_mode(mb_i16_mode),
        .mb_cmode(mb_cmode), .mb_i4m(mb_i4m),
        .coef_we(coef_we), .coef_blk(coef_blk), .coef_addr(coef_addr),
        .coef_data(coef_data),
        .slice_done(slice_done), .err(err),
        .rec_done(1'b1)
    );

endmodule
