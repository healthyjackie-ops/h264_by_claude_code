// mv_pred — luma MV prediction unit (P-R3c).
//
// Consumes mb_dec's P-syntax stream and derives the final quarter-pel
// MV for every 4x4 luma block, replicating the C model's mv_pred
// (8.4.1.3) and P_Skip derivation (8.4.1.1) exactly:
//
//  - one partition per mvd_valid beat: fetch neighbors A/B/C (C falls
//    back to D), apply the 16x8/8x16 directional rules, the only-A
//    rule, the single-ref-match rule, else component-wise median;
//    final MV = predictor + mvd, written over the partition's blocks.
//  - skip_go beat: P_Skip — zero MV if A or B is missing or either is
//    inter ref0 with a zero MV, else the 16x16 median predictor.
//  - the C model pre-writes ref for both/all partitions of 16x8, 8x16
//    and P_8x8 (type 3) before any mvd is read, so a forward neighbor
//    inside the MB reads as inter with the calloc'd (0,0) MV; P_8x8ref0
//    (type 4) does NOT pre-write and the same block reads undecoded.
//    Modeled here as a combinational view over not-yet-written blocks.
//
// Neighbor state is the line-buffer pattern used throughout the core:
// one row of bottom-edge blocks (mv + inter flag) across the picture,
// the left MB's right column, and the top-left corner register chain.
// Intra MBs contribute inter=0 entries (queried as mv 0, no ref match).
//
// mv_out_* is the z-scan final MV field, stable on the mb_valid beat;
// unwritten blocks (intra MBs) read back 0 to match the dump's
// "ref==-2 -> 0" convention.
module mv_pred #(
    parameter int MAX_MBW = 120
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  cfg_mb_w,
    input  logic        start,

    // P-syntax stream (mb_dec)
    input  logic [2:0]  mb_ptype,
    input  logic [7:0]  mb_sub,
    input  logic        mvd_valid,
    input  logic signed [15:0] mvd_x,
    input  logic signed [15:0] mvd_y,
    input  logic        skip_go,
    input  logic        commit,        // MB accepted (mb_valid beat)
    input  logic        mb_inter,
    input  logic        mb_skip,

    output logic signed [15:0] mv_out_x [16],   // z-scan
    output logic signed [15:0] mv_out_y [16]
);

    // ------------------------------------------------------------------
    // neighbor state
    // ------------------------------------------------------------------
    logic signed [15:0] top_mvx [MAX_MBW*4];
    logic signed [15:0] top_mvy [MAX_MBW*4];
    logic [MAX_MBW*4-1:0] top_int;

    logic signed [15:0] left_mvx [4];
    logic signed [15:0] left_mvy [4];
    logic [3:0]         left_int;

    logic signed [15:0] tl_mvx, tl_mvy;
    logic               tl_int;

    logic [7:0] mbx_q, mby_q;
    logic       have_left_q;

    // current MB blocks, raster order r = by*4 + bx
    logic signed [15:0] cur_mvx [16];
    logic signed [15:0] cur_mvy [16];
    logic [15:0]        cur_w;

    // partition counters (parse order)
    logic [1:0] b_q;                   // part / 8x8 block index
    logic [1:0] s_q;                   // sub-partition index (P_8x8)

    // ------------------------------------------------------------------
    // partition geometry from (mb_ptype, mb_sub, b_q, s_q)
    // ------------------------------------------------------------------
    logic [2:0] g_bx0, g_by0, g_w4, g_h4;
    logic [2:0] g_dir;                 // 0 none, 1/2 16x8 t/b, 3/4 8x16 l/r
    logic [1:0] sub2;
    logic [2:0] nsub;
    always_comb begin
        sub2 = mb_sub[{b_q, 1'b0} +: 2];
        nsub = (sub2 == 2'd0) ? 3'd1 : (sub2 == 2'd3) ? 3'd4 : 3'd2;
        g_bx0 = '0; g_by0 = '0; g_w4 = 3'd4; g_h4 = 3'd4; g_dir = '0;
        unique case (mb_ptype)
        3'd0: ;
        3'd1: begin                                  // 16x8 top/bottom
            g_by0 = {1'b0, b_q[0], 1'b0};
            g_h4 = 3'd2;
            g_dir = 3'd1 + 3'(b_q[0]);
        end
        3'd2: begin                                  // 8x16 left/right
            g_bx0 = {1'b0, b_q[0], 1'b0};
            g_w4 = 3'd2;
            g_dir = 3'd3 + 3'(b_q[0]);
        end
        default: begin                               // P_8x8 (ref0)
            g_bx0 = {2'b0, b_q[0]} << 1;
            g_by0 = {2'b0, b_q[1]} << 1;
            unique case (sub2)
            2'd0: begin g_w4 = 3'd2; g_h4 = 3'd2; end
            2'd1: begin                              // 8x4
                g_w4 = 3'd2; g_h4 = 3'd1;
                g_by0 = g_by0 + 3'(s_q[0]);
            end
            2'd2: begin                              // 4x8
                g_w4 = 3'd1; g_h4 = 3'd2;
                g_bx0 = g_bx0 + 3'(s_q[0]);
            end
            default: begin                           // 4x4
                g_w4 = 3'd1; g_h4 = 3'd1;
                g_bx0 = g_bx0 + 3'(s_q[0]);
                g_by0 = g_by0 + 3'(s_q[1]);
            end
            endcase
        end
        endcase
    end

    // skip derivation uses the 16x16 geometry
    logic [2:0] p_bx0, p_by0, p_w4, p_dir;
    always_comb begin
        p_bx0 = skip_go ? 3'd0 : g_bx0;
        p_by0 = skip_go ? 3'd0 : g_by0;
        p_w4  = skip_go ? 3'd4 : g_w4;
        p_dir = skip_go ? 3'd0 : g_dir;
    end

    // ------------------------------------------------------------------
    // neighbor fetch (8.4.1.3.2 mv_nbr semantics)
    // ------------------------------------------------------------------
    // C pre-writes ref over the whole MB for types 1/2/3 before the
    // first mvd: unwritten current-MB blocks then read inter mv (0,0).
    logic prewrite;
    assign prewrite = mvd_valid &&
                      (mb_ptype == 3'd1 || mb_ptype == 3'd2 ||
                       mb_ptype == 3'd3);

    typedef struct packed {
        logic has;                     // available AND decoded
        logic isinter;                 // has && inter (ref == cur_ref)
        logic signed [15:0] mx;
        logic signed [15:0] my;
    } nbr_t;

    function automatic nbr_t nbr(input int bx, input int by);
        nbr_t n;
        int r;
        n.has = 1'b0; n.isinter = 1'b0; n.mx = '0; n.my = '0;
        if (bx < 0 && by < 0) begin                  // top-left corner
            if (have_left_q && mby_q != 8'd0) begin
                n.has = 1'b1;
                n.isinter = tl_int;
                if (tl_int) begin n.mx = tl_mvx; n.my = tl_mvy; end
            end
        end else if (bx < 0) begin                   // left column
            if (have_left_q) begin
                n.has = 1'b1;
                n.isinter = left_int[by[1:0]];
                if (left_int[by[1:0]]) begin
                    n.mx = left_mvx[by[1:0]];
                    n.my = left_mvy[by[1:0]];
                end
            end
        end else if (by < 0) begin                   // top row buffer
            if (mby_q != 8'd0 &&
                (bx < 4 || mbx_q != cfg_mb_w - 8'd1)) begin
                n.has = 1'b1;
                n.isinter = top_int[32'(mbx_q)*4 + bx];
                if (n.isinter) begin
                    n.mx = top_mvx[32'(mbx_q)*4 + bx];
                    n.my = top_mvy[32'(mbx_q)*4 + bx];
                end
            end
        end else if (bx > 3) begin
            // same-row block of the MB to the right: not yet decoded
        end else begin                               // current MB
            r = by * 4 + bx;
            if (cur_w[r]) begin
                n.has = 1'b1;
                n.isinter = 1'b1;
                n.mx = cur_mvx[r];
                n.my = cur_mvy[r];
            end else if (prewrite) begin
                n.has = 1'b1;                        // ref pre-written,
                n.isinter = 1'b1;                    // mv still calloc 0
            end
        end
        return n;
    endfunction

    function automatic logic signed [15:0] med3(
        input logic signed [15:0] a, input logic signed [15:0] b,
        input logic signed [15:0] c);
        logic signed [15:0] x, y;
        x = a; y = b;
        if (x > y) begin x = b; y = a; end
        if (y > c) y = c;
        return (x > y) ? x : y;
    endfunction

    // ------------------------------------------------------------------
    // predictor (combinational over the active partition)
    // ------------------------------------------------------------------
    nbr_t na, nb, nc;
    logic signed [15:0] pmx, pmy;
    always_comb begin
        nbr_t nc0;
        logic [1:0] match;
        na = nbr(int'(p_bx0) - 1, int'(p_by0));
        nb = nbr(int'(p_bx0), int'(p_by0) - 1);
        nc0 = nbr(int'(p_bx0) + int'(p_w4), int'(p_by0) - 1);
        nc = nc0.has ? nc0 : nbr(int'(p_bx0) - 1, int'(p_by0) - 1);

        if (p_dir == 3'd1 && nb.isinter) begin
            pmx = nb.mx; pmy = nb.my;
        end else if ((p_dir == 3'd2 || p_dir == 3'd3) && na.isinter) begin
            pmx = na.mx; pmy = na.my;
        end else if (p_dir == 3'd4 && nc.isinter) begin
            pmx = nc.mx; pmy = nc.my;
        end else if (!nb.has && !nc.has && na.has) begin
            pmx = na.mx; pmy = na.my;
        end else begin
            match = 2'(na.isinter) + 2'(nb.isinter) + 2'(nc.isinter);
            if (match == 2'd1) begin
                if (na.isinter) begin pmx = na.mx; pmy = na.my; end
                else if (nb.isinter) begin pmx = nb.mx; pmy = nb.my; end
                else begin pmx = nc.mx; pmy = nc.my; end
            end else begin
                pmx = med3(na.mx, nb.mx, nc.mx);
                pmy = med3(na.my, nb.my, nc.my);
            end
        end
    end

    // P_Skip: zero MV when A/B missing or either is inter with zero MV
    logic skip_zero;
    assign skip_zero = !na.has || !nb.has ||
                       (na.isinter && na.mx == 16'sd0 && na.my == 16'sd0) ||
                       (nb.isinter && nb.mx == 16'sd0 && nb.my == 16'sd0);

    logic signed [15:0] fin_x, fin_y;
    always_comb begin
        if (skip_go) begin
            fin_x = skip_zero ? 16'sd0 : pmx;
            fin_y = skip_zero ? 16'sd0 : pmy;
        end else begin
            fin_x = pmx + mvd_x;
            fin_y = pmy + mvd_y;
        end
    end

    // ------------------------------------------------------------------
    // sequential: partition write, counters, neighbor advance
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mbx_q <= '0; mby_q <= '0;
            have_left_q <= 1'b0;
            cur_w <= '0;
            b_q <= '0; s_q <= '0;
            left_int <= '0;
            tl_int <= 1'b0; tl_mvx <= '0; tl_mvy <= '0;
        end else begin
            if (start) begin
                mbx_q <= '0; mby_q <= '0;
                have_left_q <= 1'b0;
                cur_w <= '0;
                b_q <= '0; s_q <= '0;
            end

            if (mvd_valid || skip_go) begin
                for (int j = 0; j < 4; j++)
                    for (int i = 0; i < 4; i++)
                        if (i >= int'(p_bx0) && i < int'(p_bx0) + int'(p_w4) &&
                            j >= int'(p_by0) &&
                            j < int'(p_by0) + int'(skip_go ? 3'd4 : g_h4)) begin
                            cur_mvx[j*4+i] <= fin_x;
                            cur_mvy[j*4+i] <= fin_y;
                            cur_w[j*4+i] <= 1'b1;
                        end
                if (mvd_valid) begin
                    if (mb_ptype == 3'd1 || mb_ptype == 3'd2)
                        b_q <= b_q + 2'd1;
                    else if (mb_ptype >= 3'd3) begin
                        if (3'(s_q) + 3'd1 == nsub) begin
                            s_q <= '0;
                            b_q <= b_q + 2'd1;
                        end else
                            s_q <= s_q + 2'd1;
                    end
                end
            end

            if (commit) begin
                // top-left corner for the NEXT MB: the entry this MB is
                // about to overwrite in its rightmost column
                tl_mvx <= top_mvx[32'(mbx_q)*4 + 3];
                tl_mvy <= top_mvy[32'(mbx_q)*4 + 3];
                tl_int <= top_int[32'(mbx_q)*4 + 3];

                if (mb_inter || mb_skip) begin
                    for (int j = 0; j < 4; j++) begin
                        left_mvx[j] <= cur_mvx[j*4+3];
                        left_mvy[j] <= cur_mvy[j*4+3];
                        left_int[j] <= 1'b1;
                    end
                    for (int i = 0; i < 4; i++) begin
                        top_mvx[32'(mbx_q)*4 + i] <= cur_mvx[12+i];
                        top_mvy[32'(mbx_q)*4 + i] <= cur_mvy[12+i];
                        top_int[32'(mbx_q)*4 + i] <= 1'b1;
                    end
                end else begin                       // intra MB
                    left_int <= '0;
                    for (int i = 0; i < 4; i++)
                        top_int[32'(mbx_q)*4 + i] <= 1'b0;
                end

                cur_w <= '0;
                b_q <= '0; s_q <= '0;
                if (mbx_q == cfg_mb_w - 8'd1) begin
                    mbx_q <= '0;
                    mby_q <= mby_q + 8'd1;
                    have_left_q <= 1'b0;
                end else begin
                    mbx_q <= mbx_q + 8'd1;
                    have_left_q <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // z-scan output; unwritten blocks read 0 (dump's ref==-2 rule)
    // ------------------------------------------------------------------
    localparam int Z2R [16] = '{0, 1, 4, 5, 2, 3, 6, 7,
                                8, 9, 12, 13, 10, 11, 14, 15};
    always_comb begin
        for (int k = 0; k < 16; k++) begin
            mv_out_x[k] = cur_w[Z2R[k]] ? cur_mvx[Z2R[k]] : 16'sd0;
            mv_out_y[k] = cur_w[Z2R[k]] ? cur_mvy[Z2R[k]] : 16'sd0;
        end
    end

endmodule
