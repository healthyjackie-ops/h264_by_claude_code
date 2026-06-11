// intra_wrap — R2b unit wrapper: I16 + chroma predictors side by side.
module intra_wrap (
    input  logic [7:0] l16 [16],
    input  logic [7:0] t16 [16],
    input  logic [7:0] tl16,
    input  logic [7:0] lc [8],
    input  logic [7:0] tc [8],
    input  logic [7:0] tlc,
    input  logic       avail_left,
    input  logic       avail_top,
    input  logic [1:0] mode,
    output logic [7:0] p16 [256],
    output logic       ok16,
    output logic [7:0] pc [64],
    output logic       okc
);
    intra16_pred u16 (.l(l16), .t(t16), .tl(tl16), .avail_left(avail_left),
                      .avail_top(avail_top), .mode(mode), .pred(p16),
                      .ok(ok16));
    chroma_pred uch (.l(lc), .t(tc), .tl(tlc), .avail_left(avail_left),
                     .avail_top(avail_top), .mode(mode), .pred(pc),
                     .ok(okc));
endmodule
