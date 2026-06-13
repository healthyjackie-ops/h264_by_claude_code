// mv_pred — luma MV prediction unit (P-R3c + W16-a dual-list/B).
//
// Derives the final quarter-pel MV(s) for every 4x4 luma block from
// mb_dec's syntax stream, replicating the C model's mv_pred (8.4.1.3),
// P_Skip (8.4.1.1) and B spatial direct (8.4.1.2.2) exactly.
//
// P mode (cfg_is_b=0): single-list median; one partition per mvd beat;
// skip_go = P_Skip. Behaviour is identical to the P-R3c unit.
//
// B mode (cfg_is_b=1): dual-list neighbour state (per 4x4 block, per
// list: a "used" flag and the mv). Explicit partitions predict the
// mvd_list's median and write that list's plane. Direct regions
// (bdir_go + bdir_mask, emitted by mb_dec for B_Skip / B_Direct_16x16
// / B_8x8 direct subs) run the MB-level spatial-direct derivation:
// per-list refIdxL = 0 if any of A/B/C(->D) uses that list else -1;
// direct_zero (both intra) -> zero Bi; else per-list 16x16 median;
// then per direct 8x8 the colocated corner colZero check zeroes a
// list whose ref is 0. The colocated motion comes in combinationally
// (the system holds list1[0]'s field; the bench feeds the 4 corners).
//
// Neighbour state is the usual line-buffer pattern (bottom row across
// the picture, left column, top-left corner chain), now doubled for
// list1. Intra MBs park used0=used1=0. Outputs are z-scan; unwritten
// blocks read 0 (dump's ref<0 -> 0 convention).
module mv_pred #(
    parameter int MAX_MBW = 120
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  cfg_mb_w,
    input  logic        cfg_is_b,
    input  logic        start,

    // syntax stream (mb_dec)
    input  logic [4:0]  mb_ptype,
    input  logic [15:0] mb_sub,
    input  logic        mvd_valid,
    input  logic        mvd_list,      // B: which list this mvd is for
    input  logic signed [15:0] mvd_x,
    input  logic signed [15:0] mvd_y,
    input  logic        skip_go,       // P_Skip derivation beat
    input  logic        bdir_go,       // B spatial-direct derivation beat
    input  logic [3:0]  bdir_mask,     // which 8x8 blocks are direct
    // B explicit partition rectangle (from mb_dec, valid with mvd_valid)
    input  logic [2:0]  bmvd_bx0,
    input  logic [2:0]  bmvd_by0,
    input  logic [2:0]  bmvd_w4,
    input  logic [2:0]  bmvd_h4,
    input  logic [2:0]  bmvd_dir,
    input  logic        commit,        // MB accepted (mb_valid beat)
    input  logic        mb_inter,
    input  logic        mb_skip,

    // colocated motion of the 4 MB-corner blocks (8x8 order), from
    // list1[0]; valid combinationally for the current MB (mbx/mby out)
    output logic [7:0]  col_mbx,
    output logic [7:0]  col_mby,
    input  logic signed [7:0]  col_ref0 [4],
    input  logic signed [15:0] col_mv0x [4],
    input  logic signed [15:0] col_mv0y [4],
    input  logic signed [7:0]  col_ref1 [4],
    input  logic signed [15:0] col_mv1x [4],
    input  logic signed [15:0] col_mv1y [4],

    output logic signed [15:0] mv_out_x  [16],   // list0, z-scan
    output logic signed [15:0] mv_out_y  [16],
    output logic signed [15:0] mv1_out_x [16],   // list1, z-scan
    output logic signed [15:0] mv1_out_y [16],
    output logic [1:0]         pmode_out [16]    // z-scan: b0 L0, b1 L1
);

    assign col_mbx = mbx_q;
    assign col_mby = mby_q;

    // ------------------------------------------------------------------
    // neighbour line buffers (dual list)
    // ------------------------------------------------------------------
    logic signed [15:0] top_m0x [MAX_MBW*4], top_m0y [MAX_MBW*4];
    logic signed [15:0] top_m1x [MAX_MBW*4], top_m1y [MAX_MBW*4];
    logic [MAX_MBW*4-1:0] top_u0, top_u1;

    logic signed [15:0] left_m0x [4], left_m0y [4];
    logic signed [15:0] left_m1x [4], left_m1y [4];
    logic [3:0] left_u0, left_u1;

    logic signed [15:0] tl_m0x, tl_m0y, tl_m1x, tl_m1y;
    logic tl_u0, tl_u1;

    logic [7:0] mbx_q, mby_q;
    logic       have_left_q;

    // current MB blocks, raster r = by*4 + bx, per list
    logic signed [15:0] cur_m0x [16], cur_m0y [16];
    logic signed [15:0] cur_m1x [16], cur_m1y [16];
    logic [15:0] cur_u0, cur_u1;       // list used
    logic [15:0] cur_w;                // block decoded (either list or intra-of-MB)

    logic [1:0] b_q;
    logic [1:0] s_q;

    // ------------------------------------------------------------------
    // partition geometry from (mb_ptype, mb_sub, b_q, s_q)
    // ------------------------------------------------------------------
    // P partition geometry from (mb_ptype, b_q, s_q). B uses the
    // rectangle mb_dec supplies (bmvd_*), so this is P-only.
    logic [2:0] g_bx0, g_by0, g_w4, g_h4, g_dir;
    logic [1:0] sub2;
    logic [2:0] nsub;
    always_comb begin
        sub2 = mb_sub[{b_q, 2'b0} +: 2];
        nsub = (sub2 == 2'd0) ? 3'd1 : (sub2 == 2'd3) ? 3'd4 : 3'd2;
        g_bx0 = '0; g_by0 = '0; g_w4 = 3'd4; g_h4 = 3'd4; g_dir = '0;
        unique case (mb_ptype)
        5'd0: ;
        5'd1: begin g_by0 = {1'b0, b_q[0], 1'b0}; g_h4 = 3'd2;
                    g_dir = 3'd1 + 3'(b_q[0]); end
        5'd2: begin g_bx0 = {1'b0, b_q[0], 1'b0}; g_w4 = 3'd2;
                    g_dir = 3'd3 + 3'(b_q[0]); end
        default: begin
            g_bx0 = {2'b0, b_q[0]} << 1;
            g_by0 = {2'b0, b_q[1]} << 1;
            unique case (sub2)
            2'd0: begin g_w4 = 3'd2; g_h4 = 3'd2; end
            2'd1: begin g_w4 = 3'd2; g_h4 = 3'd1;
                        g_by0 = g_by0 + 3'(s_q[0]); end
            2'd2: begin g_w4 = 3'd1; g_h4 = 3'd2;
                        g_bx0 = g_bx0 + 3'(s_q[0]); end
            default: begin g_w4 = 3'd1; g_h4 = 3'd1;
                           g_bx0 = g_bx0 + 3'(s_q[0]);
                           g_by0 = g_by0 + 3'(s_q[1]); end
            endcase
        end
        endcase
    end

    // explicit-partition predictor region: P derives from ptype/counters,
    // B uses mb_dec's supplied rectangle (the list-major walk can't be
    // reconstructed from the mvd stream alone). skip uses 16x16.
    logic [2:0] p_bx0, p_by0, p_w4, p_h4, p_dir;
    always_comb begin
        if (skip_go) begin
            p_bx0 = 3'd0; p_by0 = 3'd0; p_w4 = 3'd4; p_h4 = 3'd4;
            p_dir = 3'd0;
        end else if (cfg_is_b) begin
            p_bx0 = bmvd_bx0; p_by0 = bmvd_by0;
            p_w4 = bmvd_w4; p_h4 = bmvd_h4; p_dir = bmvd_dir;
        end else begin
            p_bx0 = g_bx0; p_by0 = g_by0;
            p_w4 = g_w4; p_h4 = g_h4; p_dir = g_dir;
        end
    end

    // ------------------------------------------------------------------
    // neighbour fetch — returns availability + per-list used/mv
    // ------------------------------------------------------------------
    typedef struct packed {
        logic has;
        logic u0; logic signed [15:0] m0x; logic signed [15:0] m0y;
        logic u1; logic signed [15:0] m1x; logic signed [15:0] m1y;
    } nbr_t;

    // P prewrite: ref pre-set for 16x8/8x16/P_8x8(type3) before mvd
    logic prewrite;
    assign prewrite = !cfg_is_b && mvd_valid &&
                      (mb_ptype == 5'd1 || mb_ptype == 5'd2 ||
                       mb_ptype == 5'd3);

    function automatic nbr_t nbr(input int bx, input int by);
        nbr_t n;
        int r;
        n = '0;
        if (bx < 0 && by < 0) begin
            if (have_left_q && mby_q != 8'd0) begin
                n.has = 1'b1;
                n.u0 = tl_u0; n.m0x = tl_u0 ? tl_m0x : '0;
                n.m0y = tl_u0 ? tl_m0y : '0;
                n.u1 = tl_u1; n.m1x = tl_u1 ? tl_m1x : '0;
                n.m1y = tl_u1 ? tl_m1y : '0;
            end
        end else if (bx < 0) begin
            if (have_left_q) begin
                n.has = 1'b1;
                n.u0 = left_u0[by[1:0]];
                n.m0x = n.u0 ? left_m0x[by[1:0]] : '0;
                n.m0y = n.u0 ? left_m0y[by[1:0]] : '0;
                n.u1 = left_u1[by[1:0]];
                n.m1x = n.u1 ? left_m1x[by[1:0]] : '0;
                n.m1y = n.u1 ? left_m1y[by[1:0]] : '0;
            end
        end else if (by < 0) begin
            if (mby_q != 8'd0 && (bx < 4 || mbx_q != cfg_mb_w - 8'd1)) begin
                n.has = 1'b1;
                n.u0 = top_u0[32'(mbx_q)*4 + bx];
                n.m0x = n.u0 ? top_m0x[32'(mbx_q)*4 + bx] : '0;
                n.m0y = n.u0 ? top_m0y[32'(mbx_q)*4 + bx] : '0;
                n.u1 = top_u1[32'(mbx_q)*4 + bx];
                n.m1x = n.u1 ? top_m1x[32'(mbx_q)*4 + bx] : '0;
                n.m1y = n.u1 ? top_m1y[32'(mbx_q)*4 + bx] : '0;
            end
        end else if (bx > 3) begin
            // right MB, same row: undecoded
        end else begin
            r = by * 4 + bx;
            if (cur_w[r]) begin
                n.has = 1'b1;
                n.u0 = cur_u0[r]; n.m0x = cur_u0[r] ? cur_m0x[r] : '0;
                n.m0y = cur_u0[r] ? cur_m0y[r] : '0;
                n.u1 = cur_u1[r]; n.m1x = cur_u1[r] ? cur_m1x[r] : '0;
                n.m1y = cur_u1[r] ? cur_m1y[r] : '0;
            end else if (prewrite) begin
                n.has = 1'b1; n.u0 = 1'b1;          // P: list0 mv (0,0)
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
    // per-list median over the active explicit partition
    // ------------------------------------------------------------------
    nbr_t na, nb, nc;
    always_comb begin
        nbr_t nc0;
        na  = nbr(int'(p_bx0) - 1, int'(p_by0));
        nb  = nbr(int'(p_bx0), int'(p_by0) - 1);
        nc0 = nbr(int'(p_bx0) + int'(p_w4), int'(p_by0) - 1);
        nc  = nc0.has ? nc0 : nbr(int'(p_bx0) - 1, int'(p_by0) - 1);
    end

    function automatic logic signed [15:0] pred_one(
        input logic axis,                 // 0 x, 1 y
        input logic ua, input logic signed [15:0] ax,
        input logic signed [15:0] ay,
        input logic ub, input logic signed [15:0] bx_,
        input logic signed [15:0] by_,
        input logic uc, input logic signed [15:0] cx,
        input logic signed [15:0] cy,
        input logic hasb, input logic hasc, input logic hasa,
        input logic [2:0] dir);
        logic signed [15:0] va, vb, vc;
        logic [1:0] match;
        va = axis ? ay : ax;
        vb = axis ? by_ : bx_;
        vc = axis ? cy : cx;
        if (dir == 3'd1 && ub) return vb;
        if ((dir == 3'd2 || dir == 3'd3) && ua) return va;
        if (dir == 3'd4 && uc) return vc;
        if (!hasb && !hasc && hasa) return va;
        match = 2'(ua) + 2'(ub) + 2'(uc);
        if (match == 2'd1) begin
            if (ua) return va;
            else if (ub) return vb;
            else return vc;
        end
        return med3(va, vb, vc);
    endfunction

    // per-list neighbour mv views for the current explicit mvd's list
    logic na_u, nb_u, nc_u;
    logic signed [15:0] na_x, na_y, nb_x, nb_y, nc_x, nc_y;
    always_comb begin
        logic L;
        L = cfg_is_b ? mvd_list : 1'b0;
        na_u = L ? na.u1 : na.u0;
        nb_u = L ? nb.u1 : nb.u0;
        nc_u = L ? nc.u1 : nc.u0;
        na_x = L ? na.m1x : na.m0x;  na_y = L ? na.m1y : na.m0y;
        nb_x = L ? nb.m1x : nb.m0x;  nb_y = L ? nb.m1y : nb.m0y;
        nc_x = L ? nc.m1x : nc.m0x;  nc_y = L ? nc.m1y : nc.m0y;
    end
    logic signed [15:0] epx, epy;
    assign epx = pred_one(1'b0, na_u, na_x, na_y, nb_u, nb_x, nb_y,
                          nc_u, nc_x, nc_y, nb.has, nc.has, na.has, p_dir);
    assign epy = pred_one(1'b1, na_u, na_x, na_y, nb_u, nb_x, nb_y,
                          nc_u, nc_x, nc_y, nb.has, nc.has, na.has, p_dir);

    logic signed [15:0] fin_x, fin_y;
    always_comb begin
        if (skip_go && !cfg_is_b) begin
            // P_Skip: zero if A/B missing or either inter with zero mv
            logic sz;
            sz = !na.has || !nb.has ||
                 (na.u0 && na.m0x == 16'sd0 && na.m0y == 16'sd0) ||
                 (nb.u0 && nb.m0x == 16'sd0 && nb.m0y == 16'sd0);
            fin_x = sz ? 16'sd0 : epx;
            fin_y = sz ? 16'sd0 : epy;
        end else begin
            fin_x = epx + mvd_x;
            fin_y = epy + mvd_y;
        end
    end

    // ------------------------------------------------------------------
    // B spatial direct (MB-level), 8.4.1.2.2
    // ------------------------------------------------------------------
    // 16x16 neighbours for direct
    nbr_t da, db, dc;
    always_comb begin
        nbr_t dc0;
        da  = nbr(-1, 0);
        db  = nbr(0, -1);
        dc0 = nbr(4, -1);
        dc  = dc0.has ? dc0 : nbr(-1, -1);
    end
    logic dir_r0, dir_r1;                 // 1 = refIdxL valid (==0)
    assign dir_r0 = da.u0 | db.u0 | dc.u0;
    assign dir_r1 = da.u1 | db.u1 | dc.u1;
    logic dir_zero;
    assign dir_zero = !dir_r0 && !dir_r1;
    // direct 16x16 median per list
    logic signed [15:0] d0x, d0y, d1x, d1y;
    assign d0x = pred_one(1'b0, da.u0, da.m0x, da.m0y, db.u0, db.m0x,
                          db.m0y, dc.u0, dc.m0x, dc.m0y,
                          db.has, dc.has, da.has, 3'd0);
    assign d0y = pred_one(1'b1, da.u0, da.m0x, da.m0y, db.u0, db.m0x,
                          db.m0y, dc.u0, dc.m0x, dc.m0y,
                          db.has, dc.has, da.has, 3'd0);
    assign d1x = pred_one(1'b0, da.u1, da.m1x, da.m1y, db.u1, db.m1x,
                          db.m1y, dc.u1, dc.m1x, dc.m1y,
                          db.has, dc.has, da.has, 3'd0);
    assign d1y = pred_one(1'b1, da.u1, da.m1x, da.m1y, db.u1, db.m1x,
                          db.m1y, dc.u1, dc.m1x, dc.m1y,
                          db.has, dc.has, da.has, 3'd0);

    // colZero per 8x8 corner q
    function automatic logic colzero(input int q);
        logic signed [7:0]  cref;
        logic signed [15:0] cmx, cmy;
        if (col_ref0[q] >= 0) begin
            cref = col_ref0[q]; cmx = col_mv0x[q]; cmy = col_mv0y[q];
        end else begin
            cref = col_ref1[q]; cmx = col_mv1x[q]; cmy = col_mv1y[q];
        end
        return (cref == 8'sd0) && (cmx >= -16'sd1) && (cmx <= 16'sd1) &&
               (cmy >= -16'sd1) && (cmy <= 16'sd1);
    endfunction

    // ------------------------------------------------------------------
    // sequential
    // ------------------------------------------------------------------
    integer ii, jj, qq;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mbx_q <= '0; mby_q <= '0; have_left_q <= 1'b0;
            cur_w <= '0; cur_u0 <= '0; cur_u1 <= '0;
            b_q <= '0; s_q <= '0;
            left_u0 <= '0; left_u1 <= '0;
            tl_u0 <= 1'b0; tl_u1 <= 1'b0;
            tl_m0x <= '0; tl_m0y <= '0; tl_m1x <= '0; tl_m1y <= '0;
        end else begin
            if (start) begin
                mbx_q <= '0; mby_q <= '0; have_left_q <= 1'b0;
                cur_w <= '0; cur_u0 <= '0; cur_u1 <= '0;
                b_q <= '0; s_q <= '0;
            end

            // ---- explicit partition write ----
            if (mvd_valid || (skip_go && !cfg_is_b)) begin
                logic L;
                L = cfg_is_b ? mvd_list : 1'b0;
                for (jj = 0; jj < 4; jj++)
                    for (ii = 0; ii < 4; ii++)
                        if (ii >= int'(p_bx0) &&
                            ii < int'(p_bx0) + int'(p_w4) &&
                            jj >= int'(p_by0) &&
                            jj < int'(p_by0) +
                                 int'(skip_go ? 3'd4 : p_h4)) begin
                            cur_w[jj*4+ii] <= 1'b1;
                            if (!cfg_is_b || L == 1'b0) begin
                                cur_m0x[jj*4+ii] <= fin_x;
                                cur_m0y[jj*4+ii] <= fin_y;
                                cur_u0[jj*4+ii] <= 1'b1;
                            end
                            if (cfg_is_b && L == 1'b1) begin
                                cur_m1x[jj*4+ii] <= fin_x;
                                cur_m1y[jj*4+ii] <= fin_y;
                                cur_u1[jj*4+ii] <= 1'b1;
                            end
                        end
                // P partition/sub counter advance (B uses mb_dec walk —
                // counters not used for geometry in B explicit beats)
                if (mvd_valid && !cfg_is_b) begin
                    if (mb_ptype == 5'd1 || mb_ptype == 5'd2)
                        b_q <= b_q + 2'd1;
                    else if (mb_ptype >= 5'd3) begin
                        if (3'(s_q) + 3'd1 == nsub) begin
                            s_q <= '0; b_q <= b_q + 2'd1;
                        end else s_q <= s_q + 2'd1;
                    end
                end
            end

            // ---- B spatial direct derivation ----
            if (cfg_is_b && bdir_go) begin
                for (qq = 0; qq < 4; qq++)
                    if (bdir_mask[qq]) begin
                        logic signed [15:0] e0x, e0y, e1x, e1y;
                        logic w0, w1;
                        logic cz;
                        cz = colzero(qq);
                        w0 = dir_zero ? 1'b1 : dir_r0;
                        w1 = dir_zero ? 1'b1 : dir_r1;
                        e0x = dir_zero ? 16'sd0 : d0x;
                        e0y = dir_zero ? 16'sd0 : d0y;
                        e1x = dir_zero ? 16'sd0 : d1x;
                        e1y = dir_zero ? 16'sd0 : d1y;
                        if (!dir_zero && cz) begin
                            if (dir_r0) begin e0x = '0; e0y = '0; end
                            if (dir_r1) begin e1x = '0; e1y = '0; end
                        end
                        for (jj = 0; jj < 2; jj++)
                            for (ii = 0; ii < 2; ii++) begin
                                int idx;
                                idx = (qq[1]*2 + jj)*4 + (qq[0]*2 + ii);
                                cur_w[idx] <= 1'b1;
                                cur_u0[idx] <= w0;
                                cur_u1[idx] <= w1;
                                cur_m0x[idx] <= e0x; cur_m0y[idx] <= e0y;
                                cur_m1x[idx] <= e1x; cur_m1y[idx] <= e1y;
                            end
                    end
            end

            // ---- commit: advance neighbours ----
            if (commit) begin
                tl_m0x <= top_m0x[32'(mbx_q)*4 + 3];
                tl_m0y <= top_m0y[32'(mbx_q)*4 + 3];
                tl_m1x <= top_m1x[32'(mbx_q)*4 + 3];
                tl_m1y <= top_m1y[32'(mbx_q)*4 + 3];
                tl_u0  <= top_u0[32'(mbx_q)*4 + 3];
                tl_u1  <= top_u1[32'(mbx_q)*4 + 3];

                if (mb_inter || mb_skip) begin
                    for (jj = 0; jj < 4; jj++) begin
                        left_m0x[jj] <= cur_m0x[jj*4+3];
                        left_m0y[jj] <= cur_m0y[jj*4+3];
                        left_m1x[jj] <= cur_m1x[jj*4+3];
                        left_m1y[jj] <= cur_m1y[jj*4+3];
                        left_u0[jj] <= cur_u0[jj*4+3];
                        left_u1[jj] <= cur_u1[jj*4+3];
                    end
                    for (ii = 0; ii < 4; ii++) begin
                        top_m0x[32'(mbx_q)*4 + ii] <= cur_m0x[12+ii];
                        top_m0y[32'(mbx_q)*4 + ii] <= cur_m0y[12+ii];
                        top_m1x[32'(mbx_q)*4 + ii] <= cur_m1x[12+ii];
                        top_m1y[32'(mbx_q)*4 + ii] <= cur_m1y[12+ii];
                        top_u0[32'(mbx_q)*4 + ii] <= cur_u0[12+ii];
                        top_u1[32'(mbx_q)*4 + ii] <= cur_u1[12+ii];
                    end
                end else begin                       // intra MB
                    left_u0 <= '0; left_u1 <= '0;
                    for (ii = 0; ii < 4; ii++) begin
                        top_u0[32'(mbx_q)*4 + ii] <= 1'b0;
                        top_u1[32'(mbx_q)*4 + ii] <= 1'b0;
                    end
                end

                cur_w <= '0; cur_u0 <= '0; cur_u1 <= '0;
                b_q <= '0; s_q <= '0;
                if (mbx_q == cfg_mb_w - 8'd1) begin
                    mbx_q <= '0; mby_q <= mby_q + 8'd1;
                    have_left_q <= 1'b0;
                end else begin
                    mbx_q <= mbx_q + 8'd1; have_left_q <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // z-scan outputs
    // ------------------------------------------------------------------
    localparam int Z2R [16] = '{0, 1, 4, 5, 2, 3, 6, 7,
                                8, 9, 12, 13, 10, 11, 14, 15};
    always_comb begin
        for (int k = 0; k < 16; k++) begin
            mv_out_x[k]  = cur_u0[Z2R[k]] ? cur_m0x[Z2R[k]] : 16'sd0;
            mv_out_y[k]  = cur_u0[Z2R[k]] ? cur_m0y[Z2R[k]] : 16'sd0;
            mv1_out_x[k] = cur_u1[Z2R[k]] ? cur_m1x[Z2R[k]] : 16'sd0;
            mv1_out_y[k] = cur_u1[Z2R[k]] ? cur_m1y[Z2R[k]] : 16'sd0;
            pmode_out[k] = {cur_u1[Z2R[k]], cur_u0[Z2R[k]]};
        end
    end

endmodule
