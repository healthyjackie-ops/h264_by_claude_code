// mc_core — motion-compensation interpolation units (P-R1).
//
// mc4x4_luma: one 4x4 luma block from a 9x9 clamped reference window
// (the caller extracts win[j][i] = ref[y-2+j][x-2+i] with edge clamping,
// exactly c_model h264_mc_luma's window). All fifteen quarter-pel
// phases per 8.4.2.2.1: 6-tap {1,-5,20,20,-5,1} half-pels, the center j
// from unclipped horizontal sums, quarter positions by averaging.
//
// mc4x4_chroma: one 4x4 chroma block from a 5x5 window, eighth-pel
// bilinear per 8.4.2.2.2.
//
// Pure combinational — the consumer stage registers the outputs (same
// discipline as transform_dec).
module mc4x4_luma (
    input  logic [7:0] win [9][9],     // [row][col], origin at (x-2,y-2)
    input  logic [1:0] fx,
    input  logic [1:0] fy,
    output logic [7:0] pred [16]       // raster 4x4
);

    function automatic logic signed [15:0] tap6(
        input logic [7:0] a, input logic [7:0] b, input logic [7:0] c,
        input logic [7:0] d, input logic [7:0] e, input logic [7:0] f);
        return 16'($signed({8'b0, a}) - 16'sd5 * $signed({8'b0, b}) +
                   16'sd20 * $signed({8'b0, c}) +
                   16'sd20 * $signed({8'b0, d}) -
                   16'sd5 * $signed({8'b0, e}) + $signed({8'b0, f}));
    endfunction
    function automatic logic [7:0] clip8(input logic signed [31:0] v);
        if (v < 0) return 8'd0;
        if (v > 255) return 8'd255;
        return v[7:0];
    endfunction
    function automatic logic [7:0] avg2(input logic [7:0] a,
                                        input logic [7:0] b);
        return 8'(({1'b0, a} + {1'b0, b} + 9'd1) >> 1);
    endfunction

    // horizontal 6-tap rows: hrow[j][i] over the window height for the
    // 4 output columns (needed unclipped for the center j computation)
    logic signed [15:0] hrow [9][4];
    always_comb begin
        for (int j = 0; j < 9; j++)
            for (int i = 0; i < 4; i++)
                hrow[j][i] = tap6(win[j][i], win[j][i+1], win[j][i+2],
                                  win[j][i+3], win[j][i+4], win[j][i+5]);
    end

    always_comb begin
        for (int idx = 0; idx < 16; idx++) pred[idx] = '0;

        if (fx == 0 && fy == 0) begin
            for (int j = 0; j < 4; j++)
                for (int i = 0; i < 4; i++)
                    pred[j*4+i] = win[j+2][i+2];
        end else if (fy == 0) begin                /* a, b, c */
            for (int j = 0; j < 4; j++)
                for (int i = 0; i < 4; i++) begin
                    logic [7:0] b, g;
                    b = clip8((32'(hrow[j+2][i]) + 32'sd16) >>> 5);
                    if (fx == 2) pred[j*4+i] = b;
                    else begin
                        g = (fx == 1) ? win[j+2][i+2] : win[j+2][i+3];
                        pred[j*4+i] = avg2(g, b);
                    end
                end
        end else if (fx == 0) begin                /* d, h, n */
            for (int j = 0; j < 4; j++)
                for (int i = 0; i < 4; i++) begin
                    logic [7:0] h, g;
                    h = clip8((32'(tap6(win[j][i+2], win[j+1][i+2],
                                        win[j+2][i+2], win[j+3][i+2],
                                        win[j+4][i+2], win[j+5][i+2]))
                               + 32'sd16) >>> 5);
                    if (fy == 2) pred[j*4+i] = h;
                    else begin
                        g = (fy == 1) ? win[j+2][i+2] : win[j+3][i+2];
                        pred[j*4+i] = avg2(g, h);
                    end
                end
        end else begin                             /* mixed: j family */
            for (int j = 0; j < 4; j++)
                for (int i = 0; i < 4; i++) begin
                    logic signed [31:0] j1;
                    logic [7:0] jj, b, h;
                    int col;
                    int row;
                    j1 = 32'(hrow[j][i]) - 32'sd5 * 32'(hrow[j+1][i]) +
                         32'sd20 * 32'(hrow[j+2][i]) +
                         32'sd20 * 32'(hrow[j+3][i]) -
                         32'sd5 * 32'(hrow[j+4][i]) + 32'(hrow[j+5][i]);
                    jj = clip8((j1 + 32'sd512) >>> 10);
                    if (fx == 2 && fy == 2) begin
                        pred[j*4+i] = jj;
                    end else if (fy == 2) begin    /* i, k */
                        col = (fx == 1) ? i + 2 : i + 3;
                        h = clip8((32'(tap6(win[j][col], win[j+1][col],
                                            win[j+2][col], win[j+3][col],
                                            win[j+4][col], win[j+5][col]))
                                   + 32'sd16) >>> 5);
                        pred[j*4+i] = avg2(h, jj);
                    end else if (fx == 2) begin    /* f, q */
                        row = (fy == 1) ? j + 2 : j + 3;
                        b = clip8((32'(hrow[row][i]) + 32'sd16) >>> 5);
                        pred[j*4+i] = avg2(b, jj);
                    end else begin                 /* e, g, p, r */
                        row = (fy == 1) ? j + 2 : j + 3;
                        col = (fx == 1) ? i + 2 : i + 3;
                        b = clip8((32'(hrow[row][i]) + 32'sd16) >>> 5);
                        h = clip8((32'(tap6(win[j][col], win[j+1][col],
                                            win[j+2][col], win[j+3][col],
                                            win[j+4][col], win[j+5][col]))
                                   + 32'sd16) >>> 5);
                        pred[j*4+i] = avg2(b, h);
                    end
                end
        end
    end

endmodule

module mc4x4_chroma (
    input  logic [7:0] win [5][5],     // [row][col], origin at (x,y)
    input  logic [2:0] fx,
    input  logic [2:0] fy,
    output logic [7:0] pred [16]
);
    always_comb begin
        logic [3:0] xf, yf, xi, yi;
        xf = {1'b0, fx};
        yf = {1'b0, fy};
        xi = 4'd8 - xf;
        yi = 4'd8 - yf;
        for (int j = 0; j < 4; j++)
            for (int i = 0; i < 4; i++) begin
                logic [17:0] s;
                s = 18'(xi * yi) * 18'(win[j][i])
                  + 18'(xf * yi) * 18'(win[j][i+1])
                  + 18'(xi * yf) * 18'(win[j+1][i])
                  + 18'(xf * yf) * 18'(win[j+1][i+1]);
                pred[j*4+i] = 8'((s + 18'd32) >> 6);
            end
    end
endmodule
