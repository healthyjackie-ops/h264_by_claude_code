// intra4x4_pred — the nine Intra_4x4 prediction modes (8.3.1) as pure
// combinational logic over explicit neighbor sample ports. Mirrors
// c_model/src/intra.c including the z<=-2 corner substitutions that were
// verified against ffmpeg's prediction templates. Top-right substitution
// (E..H := D when TR unavailable) is the caller's job — same contract as
// the C function performs internally; here `t` arrives pre-substituted.
module intra4x4_pred (
    input  logic [7:0] l [4],          // left column I..L
    input  logic [7:0] t [8],          // above row A..H (E..H substituted)
    input  logic [7:0] tl,             // corner M
    input  logic       avail_left,
    input  logic       avail_top,
    input  logic       avail_topleft,
    input  logic [3:0] mode,
    output logic [7:0] pred [16],      // raster
    output logic       ok
);

    // t[-1] = corner handled via tx() accessor: tx(-1)=tl, tx(i)=t[i]
    function automatic logic [7:0] tx(input int i);
        return (i < 0) ? tl : t[i];
    endfunction
    function automatic logic [7:0] lx(input int i);
        return (i < 0) ? tl : l[i];
    endfunction

    function automatic logic [7:0] avg2(input logic [7:0] a,
                                        input logic [7:0] b);
        return 8'(({1'b0, a} + {1'b0, b} + 9'd1) >> 1);
    endfunction
    function automatic logic [7:0] avg3(input logic [7:0] a,
                                        input logic [7:0] b,
                                        input logic [7:0] c);
        return 8'(({2'b0, a} + {1'b0, b, 1'b0} + {2'b0, c} + 10'd2) >> 2);
    endfunction

    always_comb begin
        ok = 1'b1;
        for (int i = 0; i < 16; i++) pred[i] = 8'd128;

        unique case (mode)
        4'd0: begin                                    /* Vertical */
            if (!avail_top) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) pred[y*4+x] = t[x];
        end
        4'd1: begin                                    /* Horizontal */
            if (!avail_left) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) pred[y*4+x] = l[y];
        end
        4'd2: begin                                    /* DC */
            logic [10:0] sum;
            logic [7:0]  v;
            sum = '0;
            if (avail_top)
                sum = sum + {3'b0, t[0]} + {3'b0, t[1]} +
                      {3'b0, t[2]} + {3'b0, t[3]};
            if (avail_left)
                sum = sum + {3'b0, l[0]} + {3'b0, l[1]} +
                      {3'b0, l[2]} + {3'b0, l[3]};
            v = (avail_top && avail_left) ? 8'((sum + 11'd4) >> 3)
              : (avail_top || avail_left) ? 8'((sum + 11'd2) >> 2)
                                          : 8'd128;
            for (int i = 0; i < 16; i++) pred[i] = v;
        end
        4'd3: begin                                    /* Diag down-left */
            if (!avail_top) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) begin
                    if (x == 3 && y == 3)
                        pred[y*4+x] = avg3(t[6], t[7], t[7]);
                    else
                        pred[y*4+x] = avg3(t[x+y], t[x+y+1], t[x+y+2]);
                end
        end
        4'd4: begin                                    /* Diag down-right */
            if (!avail_top || !avail_left || !avail_topleft) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) begin
                    if (x > y)
                        pred[y*4+x] = avg3(tx(x-y-2), tx(x-y-1), tx(x-y));
                    else if (x < y)
                        pred[y*4+x] = avg3(lx(y-x-2), lx(y-x-1), lx(y-x));
                    else
                        pred[y*4+x] = avg3(t[0], tl, l[0]);
                end
        end
        4'd5: begin                                    /* Vertical-right */
            if (!avail_top || !avail_left || !avail_topleft) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) begin
                    int z;
                    z = 2*x - y;
                    if (z >= 0 && (z % 2) == 0)
                        pred[y*4+x] = avg2(tx(x-(y>>1)-1), tx(x-(y>>1)));
                    else if (z >= 0)
                        pred[y*4+x] = avg3(tx(x-(y>>1)-2), tx(x-(y>>1)-1),
                                           tx(x-(y>>1)));
                    else if (z == -1)
                        pred[y*4+x] = avg3(l[0], tl, t[0]);
                    else
                        pred[y*4+x] = avg3(lx(y-2*x-3), lx(y-2*x-2),
                                           lx(y-2*x-1));
                end
        end
        4'd6: begin                                    /* Horizontal-down */
            if (!avail_top || !avail_left || !avail_topleft) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) begin
                    int z;
                    z = 2*y - x;
                    if (z >= 0 && (z % 2) == 0)
                        pred[y*4+x] = avg2(lx(y-(x>>1)-1), lx(y-(x>>1)));
                    else if (z >= 0)
                        pred[y*4+x] = avg3(lx(y-(x>>1)-2), lx(y-(x>>1)-1),
                                           lx(y-(x>>1)));
                    else if (z == -1)
                        pred[y*4+x] = avg3(l[0], tl, t[0]);
                    else
                        pred[y*4+x] = avg3(tx(x-2*y-3), tx(x-2*y-2),
                                           tx(x-2*y-1));
                end
        end
        4'd7: begin                                    /* Vertical-left */
            if (!avail_top) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) begin
                    if ((y % 2) == 0)
                        pred[y*4+x] = avg2(t[x+(y>>1)], t[x+(y>>1)+1]);
                    else
                        pred[y*4+x] = avg3(t[x+(y>>1)], t[x+(y>>1)+1],
                                           t[x+(y>>1)+2]);
                end
        end
        4'd8: begin                                    /* Horizontal-up */
            if (!avail_left) ok = 1'b0;
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++) begin
                    int z;
                    z = x + 2*y;
                    if (z > 5)
                        pred[y*4+x] = l[3];
                    else if (z == 5)
                        pred[y*4+x] = avg3(l[2], l[3], l[3]);
                    else if ((z % 2) == 0)
                        pred[y*4+x] = avg2(l[y+(x>>1)], l[y+(x>>1)+1]);
                    else
                        pred[y*4+x] = avg3(l[y+(x>>1)], l[y+(x>>1)+1],
                                           l[y+(x>>1)+2]);
                end
        end
        default: ok = 1'b0;
        endcase
    end

endmodule
