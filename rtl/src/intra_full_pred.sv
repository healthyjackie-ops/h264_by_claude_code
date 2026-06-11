// intra_full_pred — Intra_16x16 (8.3.3) and chroma 8x8 (8.3.4) modes as
// combinational logic over explicit neighbor ports. Mirrors intra.c:
// I16 V/H/DC/Plane (corner included for the plane i=7 reach-back) and
// chroma DC's per-4x4-quadrant availability rules plus the 34-scaled
// chroma plane.
module intra16_pred (
    input  logic [7:0] l [16],
    input  logic [7:0] t [16],
    input  logic [7:0] tl,
    input  logic       avail_left,
    input  logic       avail_top,
    input  logic [1:0] mode,
    output logic [7:0] pred [256],     // raster 16x16
    output logic       ok
);
    function automatic logic [7:0] clip8(input logic signed [31:0] v);
        if (v < 0) return 8'd0;
        if (v > 255) return 8'd255;
        return v[7:0];
    endfunction
    // plane neighbors at index -1 are the corner
    function automatic logic [7:0] txp(input int i);
        return (i < 0) ? tl : t[i];
    endfunction
    function automatic logic [7:0] lxp(input int i);
        return (i < 0) ? tl : l[i];
    endfunction

    always_comb begin
        ok = 1'b1;
        for (int i = 0; i < 256; i++) pred[i] = 8'd128;
        unique case (mode)
        2'd0: begin                                   /* Vertical */
            if (!avail_top) ok = 1'b0;
            for (int y = 0; y < 16; y++)
                for (int x = 0; x < 16; x++) pred[y*16+x] = t[x];
        end
        2'd1: begin                                   /* Horizontal */
            if (!avail_left) ok = 1'b0;
            for (int y = 0; y < 16; y++)
                for (int x = 0; x < 16; x++) pred[y*16+x] = l[y];
        end
        2'd2: begin                                   /* DC */
            logic [12:0] sum;
            logic [7:0] v;
            sum = '0;
            if (avail_top)
                for (int x = 0; x < 16; x++) sum = sum + {5'b0, t[x]};
            if (avail_left)
                for (int y = 0; y < 16; y++) sum = sum + {5'b0, l[y]};
            v = (avail_top && avail_left) ? 8'((sum + 13'd16) >> 5)
              : (avail_top || avail_left) ? 8'((sum + 13'd8) >> 4)
                                          : 8'd128;
            for (int i = 0; i < 256; i++) pred[i] = v;
        end
        2'd3: begin                                   /* Plane */
            logic signed [31:0] h, v, a, b, c;
            if (!avail_top || !avail_left) ok = 1'b0;
            h = '0;
            v = '0;
            for (int i = 0; i < 8; i++) begin
                h = h + (i + 1) * ($signed({24'b0, t[8+i]}) -
                                   $signed({24'b0, txp(6-i)}));
                v = v + (i + 1) * ($signed({24'b0, l[8+i]}) -
                                   $signed({24'b0, lxp(6-i)}));
            end
            a = 32'sd16 * ($signed({24'b0, l[15]}) + $signed({24'b0, t[15]}));
            b = (32'sd5 * h + 32'sd32) >>> 6;
            c = (32'sd5 * v + 32'sd32) >>> 6;
            for (int y = 0; y < 16; y++)
                for (int x = 0; x < 16; x++)
                    pred[y*16+x] = clip8((a + b * (x - 7) + c * (y - 7)
                                          + 32'sd16) >>> 5);
        end
        endcase
    end
endmodule

module chroma_pred (
    input  logic [7:0] l [8],
    input  logic [7:0] t [8],
    input  logic [7:0] tl,
    input  logic       avail_left,
    input  logic       avail_top,
    input  logic [1:0] mode,
    output logic [7:0] pred [64],      // raster 8x8
    output logic       ok
);
    function automatic logic [7:0] clip8(input logic signed [31:0] v);
        if (v < 0) return 8'd0;
        if (v > 255) return 8'd255;
        return v[7:0];
    endfunction
    function automatic logic [7:0] txp(input int i);
        return (i < 0) ? tl : t[i];
    endfunction
    function automatic logic [7:0] lxp(input int i);
        return (i < 0) ? tl : l[i];
    endfunction

    always_comb begin
        ok = 1'b1;
        for (int i = 0; i < 64; i++) pred[i] = 8'd128;
        unique case (mode)
        2'd0: begin                                   /* DC per quadrant */
            for (int sb = 0; sb < 4; sb++) begin
                int bx, by;
                logic use_top, use_left;
                logic [10:0] s;
                logic [7:0] v;
                bx = (sb & 1) * 4;
                by = (sb >> 1) * 4;
                if (sb == 1) begin
                    use_top = avail_top;
                    use_left = !avail_top && avail_left;
                end else if (sb == 2) begin
                    use_left = avail_left;
                    use_top = !avail_left && avail_top;
                end else begin
                    use_top = avail_top;
                    use_left = avail_left;
                end
                s = '0;
                if (use_top)
                    for (int i = 0; i < 4; i++) s = s + {3'b0, t[bx+i]};
                if (use_left)
                    for (int i = 0; i < 4; i++) s = s + {3'b0, l[by+i]};
                v = (use_top && use_left) ? 8'((s + 11'd4) >> 3)
                  : (use_top || use_left) ? 8'((s + 11'd2) >> 2)
                                          : 8'd128;
                for (int y = 0; y < 4; y++)
                    for (int x = 0; x < 4; x++)
                        pred[(by+y)*8 + bx+x] = v;
            end
        end
        2'd1: begin                                   /* Horizontal */
            if (!avail_left) ok = 1'b0;
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++) pred[y*8+x] = l[y];
        end
        2'd2: begin                                   /* Vertical */
            if (!avail_top) ok = 1'b0;
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++) pred[y*8+x] = t[x];
        end
        2'd3: begin                                   /* Plane */
            logic signed [31:0] h, v, a, b, c;
            if (!avail_top || !avail_left) ok = 1'b0;
            h = '0;
            v = '0;
            for (int i = 0; i < 4; i++) begin
                h = h + (i + 1) * ($signed({24'b0, t[4+i]}) -
                                   $signed({24'b0, txp(2-i)}));
                v = v + (i + 1) * ($signed({24'b0, l[4+i]}) -
                                   $signed({24'b0, lxp(2-i)}));
            end
            a = 32'sd16 * ($signed({24'b0, l[7]}) + $signed({24'b0, t[7]}));
            b = (32'sd34 * h + 32'sd32) >>> 6;
            c = (32'sd34 * v + 32'sd32) >>> 6;
            for (int y = 0; y < 8; y++)
                for (int x = 0; x < 8; x++)
                    pred[y*8+x] = clip8((a + b * (x - 3) + c * (y - 3)
                                         + 32'sd16) >>> 5);
        end
        endcase
    end
endmodule
