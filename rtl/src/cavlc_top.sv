// cavlc_top — R1b unit wrapper: bitreader + cavlc_block.
module cavlc_top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    input  logic [7:0]  in_byte,
    output logic        in_ready,

    input  logic        start,
    input  logic        chroma_dc,
    input  logic [1:0]  nc_class,
    input  logic [4:0]  maxc,

    output logic        busy,
    output logic        done,
    output logic        err,
    output logic [4:0]  tc_out,

    output logic        coef_we,
    output logic [3:0]  coef_addr,
    output logic signed [15:0] coef_data,

    output logic [6:0]  avail
);

    logic        req_valid;
    logic [4:0]  req_bits;
    logic        req_ready;
    logic [23:0] show;

    bitreader u_br (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_byte(in_byte), .in_ready(in_ready),
        .req_valid(req_valid), .req_bits(req_bits), .req_ready(req_ready),
        .show(show), .avail(avail)
    );

    cavlc_block u_blk (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_bits(req_bits), .req_ready(req_ready),
        .show(show),
        .start(start), .chroma_dc(chroma_dc), .nc_class(nc_class),
        .maxc(maxc),
        .busy(busy), .done(done), .tc_out(tc_out), .err(err),
        .coef_we(coef_we), .coef_addr(coef_addr), .coef_data(coef_data)
    );

endmodule
