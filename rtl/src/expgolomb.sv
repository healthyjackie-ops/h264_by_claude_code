// expgolomb — combinational ue(v)/se(v) decode over the 24-bit lookahead.
//
// Supports leading-zero runs up to 11 (codes up to 23 bits), which covers
// every syntax element of the baseline-I CAVLC subset. `len` is the bits
// to retire through the bitreader; `ok` deasserts when the window holds
// no marker bit within range (truncated stream).
module expgolomb (
    input  logic [23:0]      show,
    output logic [11:0]      ue_val,
    output logic signed [11:0] se_val,
    output logic [4:0]       len,
    output logic             ok
);

    logic [3:0] lz;
    always_comb begin
        lz = 4'd12;                     // sentinel: no marker found
        // priority: the FIRST set bit from the MSB side
        for (int i = 0; i <= 11; i++) begin
            if (show[23 - i]) begin
                lz = 4'(i);
                break;
            end
        end
    end

    logic [11:0] suffix;
    always_comb begin
        // suffix = lz bits following the marker
        logic [23:0] sh;
        sh = show << (lz + 4'd1);
        suffix = sh[23 -: 12] >> (4'd12 - lz);
    end

    assign ok     = (lz <= 4'd11);
    assign len    = 5'(lz) * 5'd2 + 5'd1;
    assign ue_val = ((12'd1 << lz) - 12'd1) + suffix;
    // se: odd k -> +(k+1)/2, even k -> -(k/2)
    assign se_val = ue_val[0] ? $signed({1'b0, ue_val[11:1]} + 12'd1)
                              : -$signed({1'b0, ue_val[11:1]});

endmodule
