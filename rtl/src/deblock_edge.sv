// deblock_edge — one 8-sample line of the 8.7 edge filter as pure
// combinational logic: strong (bS=4) and normal (bS 1..3) luma/chroma
// paths with the alpha/beta/tc0 thresholds applied per line. Mirrors
// c_model/src/deblock.c filter_edge() for a single line; the caller
// walks lines and segments. ALPHA/BETA/TC0 live in deblock_tables.svh
// (generated from the C arrays).
`include "deblock_tables.svh"

module deblock_edge (
    input  logic [7:0] p3, p2, p1, p0, q0, q1, q2, q3,
    input  logic [7:0] alpha,
    input  logic [7:0] beta,
    input  logic [2:0] bs,             // 0..4
    input  logic [4:0] tc0,
    input  logic       chroma,
    output logic [7:0] o_p2, o_p1, o_p0, o_q0, o_q1, o_q2
);

    function automatic logic [7:0] clip8(input logic signed [15:0] v);
        if (v < 0) return 8'd0;
        if (v > 255) return 8'd255;
        return v[7:0];
    endfunction
    function automatic logic signed [15:0] clip3(
        input logic signed [15:0] lo, input logic signed [15:0] hi,
        input logic signed [15:0] v);
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    endfunction
    function automatic logic signed [15:0] sabs(
        input logic signed [15:0] v);
        return v < 0 ? -v : v;
    endfunction

    logic signed [15:0] sp3, sp2, sp1, sp0, sq0, sq1, sq2, sq3;
    assign sp3 = $signed({8'b0, p3});
    assign sp2 = $signed({8'b0, p2});
    assign sp1 = $signed({8'b0, p1});
    assign sp0 = $signed({8'b0, p0});
    assign sq0 = $signed({8'b0, q0});
    assign sq1 = $signed({8'b0, q1});
    assign sq2 = $signed({8'b0, q2});
    assign sq3 = $signed({8'b0, q3});

    always_comb begin
        logic filt;
        o_p2 = p2; o_p1 = p1; o_p0 = p0;
        o_q0 = q0; o_q1 = q1; o_q2 = q2;

        filt = (bs != 3'd0) &&
               (sabs(sp0 - sq0) < $signed({8'b0, alpha})) &&
               (sabs(sp1 - sp0) < $signed({8'b0, beta})) &&
               (sabs(sq1 - sq0) < $signed({8'b0, beta}));

        if (filt && bs == 3'd4) begin
            if (chroma) begin
                o_p0 = 8'((2*sp1 + sp0 + sq1 + 16'sd2) >> 2);
                o_q0 = 8'((2*sq1 + sq0 + sp1 + 16'sd2) >> 2);
            end else begin
                logic ssmall;
                ssmall = sabs(sp0 - sq0) <
                        (($signed({8'b0, alpha}) >>> 2) + 16'sd2);
                if (ssmall && sabs(sp2 - sp0) < $signed({8'b0, beta})) begin
                    o_p0 = 8'((sp2 + 2*sp1 + 2*sp0 + 2*sq0 + sq1 + 16'sd4)
                              >> 3);
                    o_p1 = 8'((sp2 + sp1 + sp0 + sq0 + 16'sd2) >> 2);
                    o_p2 = 8'((2*sp3 + 3*sp2 + sp1 + sp0 + sq0 + 16'sd4)
                              >> 3);
                end else begin
                    o_p0 = 8'((2*sp1 + sp0 + sq1 + 16'sd2) >> 2);
                end
                if (ssmall && sabs(sq2 - sq0) < $signed({8'b0, beta})) begin
                    o_q0 = 8'((sq2 + 2*sq1 + 2*sq0 + 2*sp0 + sp1 + 16'sd4)
                              >> 3);
                    o_q1 = 8'((sq2 + sq1 + sq0 + sp0 + 16'sd2) >> 2);
                    o_q2 = 8'((2*sq3 + 3*sq2 + sq1 + sq0 + sp0 + 16'sd4)
                              >> 3);
                end else begin
                    o_q0 = 8'((2*sq1 + sq0 + sp1 + 16'sd2) >> 2);
                end
            end
        end else if (filt) begin
            logic signed [15:0] ap, aq, tc, delta;
            ap = sabs(sp2 - sp0);
            aq = sabs(sq2 - sq0);
            if (chroma) tc = $signed({11'b0, tc0}) + 16'sd1;
            else tc = $signed({11'b0, tc0}) +
                      ((ap < $signed({8'b0, beta})) ? 16'sd1 : 16'sd0) +
                      ((aq < $signed({8'b0, beta})) ? 16'sd1 : 16'sd0);
            delta = clip3(-tc, tc,
                          (((sq0 - sp0) <<< 2) + (sp1 - sq1) + 16'sd4)
                          >>> 3);
            o_p0 = clip8(sp0 + delta);
            o_q0 = clip8(sq0 - delta);
            if (!chroma) begin
                if (ap < $signed({8'b0, beta})) begin
                    o_p1 = 8'(sp1 + clip3(-$signed({11'b0, tc0}),
                                          $signed({11'b0, tc0}),
                        (sp2 + ((sp0 + sq0 + 16'sd1) >>> 1) - 2*sp1)
                        >>> 1));
                end
                if (aq < $signed({8'b0, beta})) begin
                    o_q1 = 8'(sq1 + clip3(-$signed({11'b0, tc0}),
                                          $signed({11'b0, tc0}),
                        (sq2 + ((sp0 + sq0 + 16'sd1) >>> 1) - 2*sq1)
                        >>> 1));
                end
            end
        end
    end

endmodule
