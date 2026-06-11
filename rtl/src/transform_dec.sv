// transform_dec — combinational dequant + inverse transforms for the
// baseline-I subset (flat weightScale = 16, so the <<4 cancels the >>4).
// Mirrors c_model/src/transform.c exactly:
//   dequant4x4:    d = c * V(qp%6, class(pos)) << (qp/6)
//   luma DC:       4x4 Hadamard then ((f*16*V0 << p) + 32) >> 6
//   chroma DC:     2x2 Hadamard then ((f*16*V0 << p)) >> 5
//   idct4x4_add:   two butterfly passes, (g+32)>>6, clip-add onto pred
`ifndef TRANSFORM_DEC_SV
`define TRANSFORM_DEC_SV

package transform_pkg;

    function automatic logic [4:0] dq_v(input logic [2:0] rem,
                                        input logic [1:0] cls);
        logic [4:0] r;
        unique case ({rem, cls})
            {3'd0, 2'd0}: r = 5'd10;
            {3'd0, 2'd1}: r = 5'd16;
            {3'd0, 2'd2}: r = 5'd13;
            {3'd1, 2'd0}: r = 5'd11;
            {3'd1, 2'd1}: r = 5'd18;
            {3'd1, 2'd2}: r = 5'd14;
            {3'd2, 2'd0}: r = 5'd13;
            {3'd2, 2'd1}: r = 5'd20;
            {3'd2, 2'd2}: r = 5'd16;
            {3'd3, 2'd0}: r = 5'd14;
            {3'd3, 2'd1}: r = 5'd23;
            {3'd3, 2'd2}: r = 5'd18;
            {3'd4, 2'd0}: r = 5'd16;
            {3'd4, 2'd1}: r = 5'd25;
            {3'd4, 2'd2}: r = 5'd20;
            {3'd5, 2'd0}: r = 5'd18;
            {3'd5, 2'd1}: r = 5'd29;
            {3'd5, 2'd2}: r = 5'd23;
            default:      r = 5'd0;
        endcase
        return r;
    endfunction

    // position class: 0 both-even, 1 both-odd, 2 mixed
    function automatic logic [1:0] vclass(input logic [3:0] pos);
        logic re, ce;
        re = ~pos[2];                  // row even (pos>>2 bit0)
        ce = ~pos[0];
        if (re && ce) return 2'd0;
        if (!re && !ce) return 2'd1;
        return 2'd2;
    endfunction

endpackage

// 4x4 AC/full dequant, flat weights. qp 0..51.
module dequant4x4 (
    input  logic signed [15:0] c [16],
    input  logic [5:0]         qp,
    output logic signed [31:0] d [16]
);
    import transform_pkg::*;
    logic [2:0] rem;
    logic [3:0] per;
    // qp/6 and qp%6 as small LUT-friendly logic
    always_comb begin
        per = 4'(qp / 6);
        rem = 3'(qp % 6);
        for (int i = 0; i < 16; i++) begin
            d[i] = (32'(c[i]) *
                    $signed({27'b0, dq_v(rem, vclass(4'(i)))})) <<< per;
        end
    end
endmodule

// Intra16 luma DC: inverse Hadamard + JM-form dequant.
module luma_dc_dequant (
    input  logic signed [15:0] c [16],     // raster
    input  logic [5:0]         qp,
    output logic signed [31:0] dc [16]
);
    import transform_pkg::*;
    always_comb begin
        logic signed [31:0] t [16];
        logic signed [31:0] f [16];
        logic [2:0] rem;
        logic [3:0] per;
        // rows
        for (int i = 0; i < 4; i++) begin
            logic signed [31:0] s0, s1, s2, s3;
            s0 = 32'(c[i*4+0]) + 32'(c[i*4+2]);
            s1 = 32'(c[i*4+0]) - 32'(c[i*4+2]);
            s2 = 32'(c[i*4+1]) - 32'(c[i*4+3]);
            s3 = 32'(c[i*4+1]) + 32'(c[i*4+3]);
            t[i*4+0] = s0 + s3;
            t[i*4+1] = s1 + s2;
            t[i*4+2] = s1 - s2;
            t[i*4+3] = s0 - s3;
        end
        // cols
        for (int j = 0; j < 4; j++) begin
            logic signed [31:0] s0, s1, s2, s3;
            s0 = t[0*4+j] + t[2*4+j];
            s1 = t[0*4+j] - t[2*4+j];
            s2 = t[1*4+j] - t[3*4+j];
            s3 = t[1*4+j] + t[3*4+j];
            f[0*4+j] = s0 + s3;
            f[1*4+j] = s1 + s2;
            f[2*4+j] = s1 - s2;
            f[3*4+j] = s0 - s3;
        end
        per = 4'(qp / 6);
        rem = 3'(qp % 6);
        for (int i = 0; i < 16; i++) begin
            dc[i] = (((f[i] * $signed({27'b0, dq_v(rem, 2'd0)}) * 32'sd16)
                      <<< per) + 32'sd32) >>> 6;
        end
    end
endmodule

// Chroma DC: 2x2 Hadamard + dequant (no rounding term — JM verified).
module chroma_dc_dequant (
    input  logic signed [15:0] c [4],      // raster c00 c01 c10 c11
    input  logic [5:0]         qp,         // QPc
    output logic signed [31:0] dc [4]
);
    import transform_pkg::*;
    always_comb begin
        logic signed [31:0] f0, f1, f2, f3;
        logic [2:0] rem;
        logic [3:0] per;
        f0 = 32'(c[0]) + 32'(c[1]) + 32'(c[2]) + 32'(c[3]);
        f1 = 32'(c[0]) - 32'(c[1]) + 32'(c[2]) - 32'(c[3]);
        f2 = 32'(c[0]) + 32'(c[1]) - 32'(c[2]) - 32'(c[3]);
        f3 = 32'(c[0]) - 32'(c[1]) - 32'(c[2]) + 32'(c[3]);
        per = 4'(qp / 6);
        rem = 3'(qp % 6);
        dc[0] = ((f0 * $signed({27'b0, dq_v(rem, 2'd0)}) * 32'sd16)
                 <<< per) >>> 5;
        dc[1] = ((f1 * $signed({27'b0, dq_v(rem, 2'd0)}) * 32'sd16)
                 <<< per) >>> 5;
        dc[2] = ((f2 * $signed({27'b0, dq_v(rem, 2'd0)}) * 32'sd16)
                 <<< per) >>> 5;
        dc[3] = ((f3 * $signed({27'b0, dq_v(rem, 2'd0)}) * 32'sd16)
                 <<< per) >>> 5;
    end
endmodule

// 4x4 inverse transform + clip-add onto the prediction block.
module idct4x4_add (
    input  logic signed [31:0] d [16],
    input  logic [7:0]         pred [16],
    output logic [7:0]         out [16]
);
    always_comb begin
        logic signed [31:0] t [16];
        for (int i = 0; i < 4; i++) begin
            logic signed [31:0] e0, e1, e2, e3;
            e0 = d[i*4+0] + d[i*4+2];
            e1 = d[i*4+0] - d[i*4+2];
            e2 = (d[i*4+1] >>> 1) - d[i*4+3];
            e3 = d[i*4+1] + (d[i*4+3] >>> 1);
            t[i*4+0] = e0 + e3;
            t[i*4+1] = e1 + e2;
            t[i*4+2] = e1 - e2;
            t[i*4+3] = e0 - e3;
        end
        for (int j = 0; j < 4; j++) begin
            logic signed [31:0] e0, e1, e2, e3, g0, g1, g2, g3;
            e0 = t[0*4+j] + t[2*4+j];
            e1 = t[0*4+j] - t[2*4+j];
            e2 = (t[1*4+j] >>> 1) - t[3*4+j];
            e3 = t[1*4+j] + (t[3*4+j] >>> 1);
            g0 = e0 + e3;
            g1 = e1 + e2;
            g2 = e1 - e2;
            g3 = e0 - e3;
            out[0*4+j] = clip8($signed({24'b0, pred[0*4+j]}) +
                               ((g0 + 32'sd32) >>> 6));
            out[1*4+j] = clip8($signed({24'b0, pred[1*4+j]}) +
                               ((g1 + 32'sd32) >>> 6));
            out[2*4+j] = clip8($signed({24'b0, pred[2*4+j]}) +
                               ((g2 + 32'sd32) >>> 6));
            out[3*4+j] = clip8($signed({24'b0, pred[3*4+j]}) +
                               ((g3 + 32'sd32) >>> 6));
        end
    end

    function automatic logic [7:0] clip8(input logic signed [31:0] v);
        if (v < 0) return 8'd0;
        if (v > 255) return 8'd255;
        return v[7:0];
    endfunction
endmodule

`endif  // TRANSFORM_DEC_SV
