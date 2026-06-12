// cabac_mb — CABAC I-slice MB-layer parser (W15-b/c).
//
// The CABAC twin of mb_dec's CAVLC path: walks slice_data one bin per
// beat through an embedded cabac_core, producing the same downstream
// interface (header + coefficient write stream + rec_done handshake)
// so mb_recon and the benches are reused unchanged.
//
// Coverage: baseline-style I slices (I_4x4 / I_16x16, no PCM, no t8).
// Syntax per 9.3.3.1: mb_type tree (ctx 3..10 with the neighbor
// ctxIdxInc), prev/rem intra4x4 modes (68/69), chroma mode (64..67),
// CBP (73..84), mb_qp_delta (60..63), per-block coded_block_flag
// (85+cat*4+condA+2*condB) with the spec neighbor terms, significance
// and last maps (105/166 + offset + scanpos), the level node machine
// at 227+ with the EG0 bypass escape, sign bypass, and the
// end_of_slice terminate after every MB.
//
// Neighbor context state mirrors the C model's arrays as line buffers:
// per-MB cat/cmode/cbp/cbf_ldc/cbf_cdc plus per-4x4 cbf_l, per-2x2
// cbf_c and the i4 mode row (for min(A,B) prediction).
`include "cavlc_tables.svh"

module cabac_mb #(
    parameter int MAX_MBW = 120
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  cfg_mb_w,
    input  logic [7:0]  cfg_mb_h,
    input  logic [5:0]  cfg_qp,
    input  logic        cfg_is_p,
    input  logic [1:0]  cfg_init_idc,
    input  logic        start,

    // bitreader window (shared decoder front end)
    output logic        req_valid,
    output logic [4:0]  req_bits,
    input  logic        req_ready,
    input  logic [23:0] show,
    input  logic [6:0]  avail,

    // decoded MB header (mb_dec-compatible)
    output logic        mb_valid,
    output logic [7:0]  mb_x,
    output logic [7:0]  mb_y,
    output logic        mb_i16,
    output logic [5:0]  mb_cbp,
    output logic [5:0]  mb_qp,
    output logic [1:0]  mb_i16_mode,
    output logic [1:0]  mb_cmode,
    output logic [63:0] mb_i4m,

    // P syntax stream (mb_dec-compatible, drives mv_pred)
    output logic        mb_skip,
    output logic        mb_inter,
    output logic [4:0]  mb_ptype,
    output logic [15:0] mb_sub,
    output logic        mvd_valid,
    output logic signed [15:0] mvd_x,
    output logic signed [15:0] mvd_y,
    output logic        skip_go,
    output logic [15:0] mb_nz,         // cbf bitmap, raster (deblock bS)

    // coefficient write stream (mb_dec conventions)
    output logic        coef_we,
    output logic [4:0]  coef_blk,
    output logic [3:0]  coef_addr,
    output logic signed [15:0] coef_data,

    output logic        slice_done,
    output logic        err,
    input  logic        rec_done
);

    function automatic logic [1:0] zsx(input logic [3:0] k);
        return {k[2], k[0]};
    endfunction
    function automatic logic [1:0] zsy(input logic [3:0] k);
        return {k[3], k[1]};
    endfunction
    function automatic logic [3:0] zidx(input logic [1:0] bx,
                                        input logic [1:0] by);
        return {by[1], bx[1], by[0], bx[0]};
    endfunction

    // ------------------------------------------------------------------
    // embedded arithmetic engine
    // ------------------------------------------------------------------
    logic        ci_start, ci_busy;
    logic        op_valid, op_ready, bin;
    logic [1:0]  op;                   // 0 decision 1 bypass 2 terminate
    logic [8:0]  op_ctx;

    cabac_core u_core (
        .clk(clk), .rst_n(rst_n),
        .req_valid(req_valid), .req_bits(req_bits), .req_ready(req_ready),
        .show(show), .avail(avail),
        .init_start(ci_start), .init_qp(cfg_qp),
        .init_model(cfg_is_p ? cfg_init_idc : 2'd3),
        .init_busy(ci_busy),
        .op_valid(op_valid), .op(op), .op_ctx(op_ctx),
        .op_ready(op_ready), .bin(bin),
        .dbg_range(), .dbg_value()
    );

    logic step;
    assign step = op_valid && op_ready;

    // ------------------------------------------------------------------
    // neighbor line buffers (one packed word per MB column)
    //  [0] cat (1 = I16), [1] cmode != 0, [7:2] cbp, [8] cbf_ldc,
    //  [10:9] cbf_cdc, [14:11] cbf_l bottom row, [16:15] cbf_c U bottom,
    //  [18:17] cbf_c V bottom, [34:19] i4 modes of the bottom row
    // ------------------------------------------------------------------
    // [35] mb_skip, [91:36] amvd bottom row (4 x {ay[6:0], ax[6:0]})
    logic [91:0] nrow [MAX_MBW];
    wire  [91:0] nrow_rd = nrow[mbx_q];
    logic [91:0] nrow_q;               // prefetched copy for this MB

    // left-neighbor state
    logic        l_valid;
    logic        l_cat, l_cmode;
    logic [5:0]  l_cbp;
    logic        l_ldc;
    logic [1:0]  l_cdc;
    logic [3:0]  l_cbfl;               // right column, rows 0..3
    logic [1:0]  l_cbfc [2];           // right column, rows 0..1
    logic [3:0]  l_i4m [4];
    logic        l_skip;
    logic [6:0]  l_avx [4];            // right-column |mvd| (clip 70)
    logic [6:0]  l_avy [4];

    // current MB state
    logic [7:0]  mbx_q, mby_q;
    logic        i16_q;
    logic [1:0]  i16m_q, cmode_q;
    logic [5:0]  cbp_q, qp_q;
    logic [3:0]  i4m_q [16];
    logic [15:0] cbfl_q;               // per 4x4, raster
    logic [3:0]  cbfc_q [2];           // per 2x2, raster
    logic [1:0]  cdc_q;
    logic        ldc_q;
    logic        lastqpd_q;

    // P-mode state
    logic        skip_q, inter_q;
    logic [4:0]  ptype_q;
    logic [15:0] sub_q;
    logic [1:0]  pb_q, ps_q;           // partition / sub counters
    logic        axis_q;               // 0 = mvd x, 1 = mvd y
    logic [15:0] uegv_q;               // UEG3 |mvd| accumulator
    logic [2:0]  uctx_q;               // unary ctx offset 3..6
    logic [4:0]  egk3_q;
    logic [15:0] egv3_q;
    logic signed [15:0] mvdx_q, mvdy_q;
    logic        mvdv_q;               // registered mvd_valid pulse
    logic [6:0]  cur_avx [16];         // |mvd| per 4x4, raster
    logic [6:0]  cur_avy [16];
    logic [15:0] av_w;                 // written mask

    logic have_left, have_top;
    assign have_left = (mbx_q != 8'd0);
    assign have_top = (mby_q != 8'd0);

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    typedef enum logic [4:0] {
        S_IDLE, S_CINIT, S_PRE,
        S_MBT, S_I4M, S_CMD, S_CBP, S_QPD,
        R_NEXT, R_CBF, R_SIG, R_LAST, R_L1, R_GT1, R_EGP, R_EGS, R_SIGN,
        S_EOS, S_EMIT, S_DONE, S_ERR,
        S_SKIPF, S_PMBT, S_ISUF, S_PSUB,
        M_B0, M_U, M_EGP, M_EGS, M_SGN
    } state_e;
    state_e st_q;

    logic [2:0]  bcnt_q;               // bin index inside an element
    logic [4:0]  t_q;                  // mb_type accumulator (1..24)
    logic [3:0]  k_q;                  // block counter (z order)
    logic [2:0]  m_q;                  // rem intra mode accumulator
    logic [6:0]  uval_q;               // qp_delta unary value

    // residual phase: 0 luma DC, 1 luma 4x4, 2 chroma DC, 3 chroma AC
    logic [1:0]  rph_q;
    logic        comp_q;
    logic [2:0]  rcat;                 // ctxBlockCat of the current block
    logic [4:0]  rmax;                 // max_coeffs
    logic [3:0]  ridx [16];            // significance position stack
    logic [4:0]  rcnt_q;
    logic [4:0]  rsig_q;               // scan position in the sig map
    logic [2:0]  node_q;
    logic [4:0]  abs_q;
    logic [4:0]  egk_q;
    logic [15:0] egv_q;

    // ---- residual block descriptor (combinational off rph/k/comp) ----
    always_comb begin
        unique case (rph_q)
        2'd0: begin rcat = 3'd0; rmax = 5'd16; end
        2'd1: begin rcat = i16_q ? 3'd1 : 3'd2;
                    rmax = i16_q ? 5'd15 : 5'd16; end
        2'd2: begin rcat = 3'd3; rmax = 5'd4; end
        default: begin rcat = 3'd4; rmax = 5'd15; end
        endcase
    end

    localparam logic [5:0] SIG_OFF [5] = '{0, 15, 29, 44, 47};
    localparam logic [5:0] LVL_OFF [5] = '{0, 10, 20, 30, 39};
    function automatic logic [3:0] l1ctx(input logic [2:0] n);
        unique case (n)
        3'd0: return 4'd1; 3'd1: return 4'd2; 3'd2: return 4'd3;
        3'd3: return 4'd4; default: return 4'd0;
        endcase
    endfunction
    function automatic logic [3:0] gt1ctx(input logic [2:0] n);
        return (n < 3'd4) ? 4'd5 : 4'(4'd2 + 4'(n));
    endfunction
    function automatic logic [2:0] tr_eq1(input logic [2:0] n);
        unique case (n)
        3'd0: return 3'd1; 3'd1: return 3'd2; 3'd2: return 3'd3;
        3'd3: return 3'd3; 3'd4: return 3'd4; 3'd5: return 3'd5;
        3'd6: return 3'd6; default: return 3'd7;
        endcase
    endfunction
    function automatic logic [2:0] tr_gt1(input logic [2:0] n);
        return (n < 3'd4) ? 3'd4 : ((n == 3'd7) ? 3'd7 : n + 3'd1);
    endfunction

    // ---- P partition geometry from (ptype_q, sub_q, pb_q, ps_q) ----
    logic [2:0] g_bx0, g_by0, g_w4, g_h4;
    logic [1:0] sub2;
    logic [2:0] nsub;
    always_comb begin
        sub2 = sub_q[{pb_q, 2'b0} +: 2];
        nsub = (sub2 == 2'd0) ? 3'd1 : (sub2 == 2'd3) ? 3'd4 : 3'd2;
        g_bx0 = '0; g_by0 = '0; g_w4 = 3'd4; g_h4 = 3'd4;
        unique case (ptype_q)
        5'd0: ;
        5'd1: begin g_by0 = {1'b0, pb_q[0], 1'b0}; g_h4 = 3'd2; end
        5'd2: begin g_bx0 = {1'b0, pb_q[0], 1'b0}; g_w4 = 3'd2; end
        default: begin
            g_bx0 = {2'b0, pb_q[0]} << 1;
            g_by0 = {2'b0, pb_q[1]} << 1;
            unique case (sub2)
            2'd0: begin g_w4 = 3'd2; g_h4 = 3'd2; end
            2'd1: begin g_w4 = 3'd2; g_h4 = 3'd1;
                        g_by0 = g_by0 + 3'(ps_q[0]); end
            2'd2: begin g_w4 = 3'd1; g_h4 = 3'd2;
                        g_bx0 = g_bx0 + 3'(ps_q[0]); end
            default: begin g_w4 = 3'd1; g_h4 = 3'd1;
                           g_bx0 = g_bx0 + 3'(ps_q[0]);
                           g_by0 = g_by0 + 3'(ps_q[1]); end
            endcase
        end
        endcase
    end

    // |mvd| neighbor sum for the UEG3 bin0 ctxInc: A=(bx0-1,by0),
    // B=(bx0,by0-1); unwritten/unavailable blocks read 0 (calloc rule)
    logic [8:0] amvd;
    always_comb begin
        logic [6:0] aa, bb;
        logic [1:0] bx, by;
        bx = g_bx0[1:0];
        by = g_by0[1:0];
        aa = '0; bb = '0;
        if (bx != 2'd0) begin
            if (av_w[{by, bx - 2'd1}])
                aa = axis_q ? cur_avy[{by, bx - 2'd1}]
                            : cur_avx[{by, bx - 2'd1}];
        end else if (have_left)
            aa = axis_q ? l_avy[by] : l_avx[by];
        if (by != 2'd0) begin
            if (av_w[{by - 2'd1, bx}])
                bb = axis_q ? cur_avy[{by - 2'd1, bx}]
                            : cur_avx[{by - 2'd1, bx}];
        end else if (have_top)
            bb = axis_q ? nrow_q[36 + bx*14 + 7 +: 7]
                        : nrow_q[36 + bx*14 +: 7];
        amvd = 9'(aa) + 9'(bb);
    end
    logic [1:0] mvd_inc;
    assign mvd_inc = 2'(amvd > 9'd2) + 2'(amvd > 9'd32);

    // ---- coded_block_flag neighbor terms (9.3.3.1.1.9) ----
    // unavailable -> 1 (intra current), I16-vs-I4 DC rule per C model
    logic cond_a, cond_b;
    always_comb begin
        logic [1:0] bx, by;
        bx = zsx(k_q);
        by = zsy(k_q);
        cond_a = !inter_q;
        cond_b = !inter_q;
        unique case (rph_q)
        2'd0: begin                                  // luma DC, MB level
            if (have_left) cond_a = l_cat ? l_ldc : 1'b0;
            if (have_top)  cond_b = nrow_q[0] ? nrow_q[8] : 1'b0;
        end
        2'd1: begin                                  // luma 4x4 block
            if (bx != 2'd0)      cond_a = cbfl_q[{by, bx - 2'd1}];
            else if (have_left)  cond_a = l_cbfl[by];
            if (by != 2'd0)      cond_b = cbfl_q[{by - 2'd1, bx}];
            else if (have_top)   cond_b = nrow_q[11 + bx];
        end
        2'd2: begin                                  // chroma DC, MB level
            if (have_left) cond_a = l_cdc[comp_q];
            if (have_top)  cond_b = nrow_q[9 + comp_q];
        end
        default: begin                               // chroma 2x2 block
            if (k_q[0])          cond_a = cbfc_q[comp_q][{k_q[1], 1'b0}];
            else if (have_left)  cond_a = l_cbfc[comp_q][k_q[1]];
            if (k_q[1])          cond_b = cbfc_q[comp_q][{1'b0, k_q[0]}];
            else if (have_top)   cond_b = nrow_q[15 + comp_q*2 + k_q[0]];
        end
        endcase
    end

    // ---- ctxIdxInc terms for the header elements ----
    logic [1:0] mbt_inc, cmd_inc, skp_inc;
    always_comb begin
        mbt_inc = 2'(have_left && l_cat) + 2'(have_top && nrow_q[0]);
        cmd_inc = 2'(have_left && l_cmode) + 2'(have_top && nrow_q[1]);
        skp_inc = 2'(have_left && !l_skip) + 2'(have_top && !nrow_q[35]);
    end

    // CBP neighbor words (unavailable reads as 0x0F)
    logic [5:0] cbp_a, cbp_b;
    assign cbp_a = have_left ? l_cbp : 6'h0F;
    assign cbp_b = have_top ? nrow_q[7:2] : 6'h0F;
    logic [1:0] cbp_ctx;
    always_comb begin
        unique case (bcnt_q)
        3'd0: cbp_ctx = 2'(!cbp_a[1]) + {!cbp_b[2], 1'b0};
        3'd1: cbp_ctx = 2'(!cbp_q[0]) + {!cbp_b[3], 1'b0};
        3'd2: cbp_ctx = 2'(!cbp_a[3]) + {!cbp_q[0], 1'b0};
        3'd3: cbp_ctx = 2'(!cbp_q[2]) + {!cbp_q[1], 1'b0};
        3'd4: cbp_ctx = 2'(cbp_a[5:4] != 2'd0) + {cbp_b[5:4] != 2'd0, 1'b0};
        default: cbp_ctx = 2'(cbp_a[5:4] == 2'd2) + {cbp_b[5:4] == 2'd2, 1'b0};
        endcase
    end

    // ---- i4 mode prediction (min rule, same buffers as mb_dec) ----
    logic [3:0] predA, predB;
    logic       availA, availB;
    always_comb begin
        logic [1:0] bx, by;
        bx = zsx(k_q);
        by = zsy(k_q);
        availA = (bx != 0) || have_left;
        availB = (by != 0) || have_top;
        predA = (bx != 0) ? i4m_q[zidx(bx - 2'd1, by)] : l_i4m[by];
        predB = (by != 0) ? i4m_q[zidx(bx, by - 2'd1)]
                          : nrow_q[19 + bx*4 +: 4];
    end
    logic [3:0] i4_pred;
    assign i4_pred = (!availA || !availB) ? 4'd2
                     : (predA < predB ? predA : predB);

    // ------------------------------------------------------------------
    // per-state op selection
    // ------------------------------------------------------------------
    always_comb begin
        op_valid = 1'b0;
        op = 2'd0;
        op_ctx = '0;
        unique case (st_q)
        S_MBT: begin
            op_valid = 1'b1;
            unique case (bcnt_q)
            3'd0: op_ctx = 9'd3 + 9'(mbt_inc);
            3'd1: op = 2'd2;                         // PCM terminate
            3'd2: op_ctx = 9'd6;
            3'd3: op_ctx = 9'd7;
            3'd4: op_ctx = 9'd8;
            3'd5: op_ctx = 9'd9;
            default: op_ctx = 9'd10;
            endcase
        end
        S_SKIPF: begin
            op_valid = 1'b1;
            op_ctx = 9'd11 + 9'(skp_inc);
        end
        S_PMBT: begin
            op_valid = 1'b1;
            unique case (bcnt_q)
            3'd0: op_ctx = 9'd14;
            3'd1: op_ctx = 9'd15;
            3'd2: op_ctx = 9'd16;
            default: op_ctx = 9'd17;
            endcase
        end
        S_ISUF: begin                                // intra suffix @17
            op_valid = 1'b1;
            unique case (bcnt_q)
            3'd0: op_ctx = 9'd17;
            3'd1: op = 2'd2;                         // PCM terminate
            3'd2: op_ctx = 9'd18;
            3'd3: op_ctx = 9'd19;
            3'd4: op_ctx = 9'd19;
            3'd5: op_ctx = 9'd20;
            default: op_ctx = 9'd20;
            endcase
        end
        S_PSUB: begin
            op_valid = 1'b1;
            op_ctx = (bcnt_q == 3'd0) ? 9'd21
                     : (bcnt_q == 3'd1) ? 9'd22 : 9'd23;
        end
        M_B0: begin
            op_valid = 1'b1;
            op_ctx = (axis_q ? 9'd47 : 9'd40) + 9'(mvd_inc);
        end
        M_U: begin
            op_valid = 1'b1;
            op_ctx = (axis_q ? 9'd47 : 9'd40) + 9'd3 + 9'(uctx_q);
        end
        M_EGP, M_EGS, M_SGN: begin
            op_valid = 1'b1;
            op = 2'd1;                               // bypass
        end
        S_I4M: begin
            op_valid = 1'b1;
            op_ctx = (bcnt_q == 3'd0) ? 9'd68 : 9'd69;
        end
        S_CMD: begin
            op_valid = 1'b1;
            op_ctx = (bcnt_q == 3'd0) ? 9'd64 + 9'(cmd_inc) : 9'd67;
        end
        S_CBP: begin
            op_valid = 1'b1;
            op_ctx = (bcnt_q < 3'd4) ? 9'd73 + 9'(cbp_ctx)
                     : (bcnt_q == 3'd4) ? 9'd77 + 9'(cbp_ctx)
                                        : 9'd81 + 9'(cbp_ctx);
        end
        S_QPD: begin
            op_valid = 1'b1;
            op_ctx = (bcnt_q == 3'd0) ? (lastqpd_q ? 9'd61 : 9'd60)
                     : (bcnt_q == 3'd1) ? 9'd62 : 9'd63;
        end
        R_CBF: begin
            op_valid = 1'b1;
            op_ctx = 9'd85 + 9'(rcat)*4 + 9'(cond_a) + 9'(cond_b)*2;
        end
        R_SIG: begin
            op_valid = 1'b1;
            op_ctx = 9'd105 + 9'(SIG_OFF[rcat]) + 9'(rsig_q);
        end
        R_LAST: begin
            op_valid = 1'b1;
            op_ctx = 9'd166 + 9'(SIG_OFF[rcat]) + 9'(rsig_q);
        end
        R_L1: begin
            op_valid = 1'b1;
            op_ctx = 9'd227 + 9'(LVL_OFF[rcat]) + 9'(l1ctx(node_q));
        end
        R_GT1: begin
            op_valid = 1'b1;
            op_ctx = 9'd227 + 9'(LVL_OFF[rcat]) + 9'(gt1ctx(node_q));
        end
        R_EGP, R_EGS, R_SIGN: begin
            op_valid = 1'b1;
            op = 2'd1;                               // bypass
        end
        S_EOS: begin
            op_valid = 1'b1;
            op = 2'd2;
        end
        default: ;
        endcase
    end

    // ------------------------------------------------------------------
    // coefficient output (one write on the sign beat)
    // ------------------------------------------------------------------
    logic [3:0] wpos;
    assign wpos = ridx[rcnt_q - 5'd1];
    always_comb begin
        coef_we = (st_q == R_SIGN) && step;
        unique case (rph_q)
        2'd0: begin coef_blk = 5'd16;          coef_addr = zz4(wpos); end
        2'd1: begin coef_blk = 5'(k_q);
                    coef_addr = i16_q ? zz4(wpos + 4'd1) : zz4(wpos); end
        2'd2: begin coef_blk = 5'd17 + 5'(comp_q); coef_addr = wpos; end
        default: begin
            coef_blk = 5'd19 + 5'(comp_q)*4 + 5'(k_q);
            coef_addr = zz4(wpos + 4'd1);
        end
        endcase
        coef_data = bin ? -16'(abs_q) : 16'(abs_q);
        if (st_q == R_SIGN && abs_q == 5'd15 && egv_q != 16'd0)
            coef_data = bin ? -(16'(egv_q) + 16'd14)
                            : (16'(egv_q) + 16'd14);
    end

    // ------------------------------------------------------------------
    // outputs
    // ------------------------------------------------------------------
    assign mb_x = mbx_q;
    assign mb_y = mby_q;
    assign mb_i16 = i16_q;
    assign mb_cbp = cbp_q;
    assign mb_qp = qp_q;
    assign mb_i16_mode = i16m_q;
    assign mb_cmode = cmode_q;
    always_comb
        for (int i = 0; i < 16; i++) mb_i4m[i*4 +: 4] = i4m_q[i];
    assign mb_valid = (st_q == S_EMIT);
    assign slice_done = (st_q == S_DONE);
    assign err = (st_q == S_ERR);
    assign mb_skip = skip_q;
    assign mb_inter = inter_q;
    assign mb_ptype = ptype_q;
    assign mb_sub = sub_q;
    assign mvd_valid = mvdv_q;
    assign mvd_x = mvdx_q;
    assign mvd_y = mvdy_q;
    assign mb_nz = cbfl_q;
    // P_Skip derivation beat for mv_pred: the skip decision just
    // landed, neighbor state is still pre-advance
    assign skip_go = skipgo_q;
    logic skipgo_q;

    // I16 derivation from mb_type t (1..24): eff = t-1
    logic [4:0] eff;
    assign eff = t_q - 5'd1;

    // ------------------------------------------------------------------
    // sequential
    // ------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            ci_start <= 1'b0;
            mbx_q <= '0; mby_q <= '0;
            qp_q <= '0; lastqpd_q <= 1'b0;
            l_valid <= 1'b0;
            bcnt_q <= '0; t_q <= '0; k_q <= '0; m_q <= '0;
            rph_q <= '0; comp_q <= 1'b0;
            rcnt_q <= '0; rsig_q <= '0; node_q <= '0;
            abs_q <= '0; egk_q <= '0; egv_q <= '0; uval_q <= '0;
            i16_q <= 1'b0; i16m_q <= '0; cmode_q <= '0; cbp_q <= '0;
            cbfl_q <= '0; cdc_q <= '0; ldc_q <= 1'b0;
            l_cat <= 1'b0; l_cmode <= 1'b0; l_cbp <= '0;
            l_ldc <= 1'b0; l_cdc <= '0; l_cbfl <= '0;
            nrow_q <= '0;
            skip_q <= 1'b0; inter_q <= 1'b0;
            ptype_q <= '0; sub_q <= '0;
            pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
            uegv_q <= '0; uctx_q <= '0; egk3_q <= '0; egv3_q <= '0;
            mvdx_q <= '0; mvdy_q <= '0; mvdv_q <= 1'b0;
            av_w <= '0; avxc_q <= '0;
            skipgo_q <= 1'b0; l_skip <= 1'b0;
        end else begin
            ci_start <= 1'b0;
            mvdv_q <= 1'b0;
            skipgo_q <= 1'b0;
            unique case (st_q)
            S_IDLE: if (start) begin
                mbx_q <= '0; mby_q <= '0;
                qp_q <= cfg_qp;
                lastqpd_q <= 1'b0;
                l_valid <= 1'b0;
                ci_start <= 1'b1;
                st_q <= S_CINIT;
            end

            S_CINIT: if (!ci_start && !ci_busy) st_q <= S_PRE;

            S_PRE: begin
                nrow_q <= nrow_rd;
                for (int k = 0; k < 16; k++) i4m_q[k] <= 4'd2;
                cbfl_q <= '0;
                cbfc_q[0] <= '0; cbfc_q[1] <= '0;
                cdc_q <= '0; ldc_q <= 1'b0;
                cmode_q <= '0; cbp_q <= '0;
                i16_q <= 1'b0; i16m_q <= '0;
                t_q <= '0; bcnt_q <= '0; k_q <= '0;
                skip_q <= 1'b0; inter_q <= 1'b0;
                ptype_q <= '0; sub_q <= '0;
                pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
                av_w <= '0;
                for (int i = 0; i < 16; i++) begin
                    cur_avx[i] <= '0;
                    cur_avy[i] <= '0;
                end
                st_q <= cfg_is_p ? S_SKIPF : S_MBT;
            end

            S_SKIPF: if (step) begin
                if (bin) begin                       // P_Skip
                    skip_q <= 1'b1;
                    inter_q <= 1'b1;
                    cbp_q <= '0;
                    lastqpd_q <= 1'b0;
                    skipgo_q <= 1'b1;
                    st_q <= S_EOS;
                end else
                    st_q <= S_PMBT;
            end

            S_PMBT: if (step) begin
                unique case (bcnt_q)
                3'd0: begin
                    if (bin) begin                   // intra in P
                        bcnt_q <= '0;
                        st_q <= S_ISUF;
                    end else begin
                        inter_q <= 1'b1;
                        bcnt_q <= 3'd1;
                    end
                end
                3'd1: bcnt_q <= bin ? 3'd3 : 3'd2;
                3'd2: begin                          // P_8x8 : 16x16
                    ptype_q <= bin ? 5'd3 : 5'd0;
                    bcnt_q <= '0;
                    pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
                    st_q <= bin ? S_PSUB : M_B0;
                end
                default: begin                       // 16x8 : 8x16
                    ptype_q <= bin ? 5'd1 : 5'd2;
                    bcnt_q <= '0;
                    pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
                    st_q <= M_B0;
                end
                endcase
            end

            S_ISUF: if (step) begin                  // intra suffix @17
                unique case (bcnt_q)
                3'd0: begin
                    if (!bin) begin
                        k_q <= '0; bcnt_q <= '0;
                        st_q <= S_I4M;
                    end else begin
                        t_q <= 5'd1;
                        bcnt_q <= 3'd1;
                    end
                end
                3'd1: begin
                    if (bin) st_q <= S_ERR;          // I_PCM unsupported
                    else bcnt_q <= 3'd2;
                end
                3'd2: begin
                    if (bin) t_q <= t_q + 5'd12;
                    bcnt_q <= 3'd3;
                end
                3'd3: bcnt_q <= bin ? 3'd4 : 3'd5;
                3'd4: begin
                    t_q <= t_q + (bin ? 5'd8 : 5'd4);
                    bcnt_q <= 3'd5;
                end
                3'd5: begin
                    if (bin) t_q <= t_q + 5'd2;
                    bcnt_q <= 3'd6;
                end
                default: begin
                    i16_q <= 1'b1;
                    st_q <= S_CMD;
                    bcnt_q <= '0;
                    if (bin) t_q <= t_q + 5'd1;
                end
                endcase
            end

            S_PSUB: if (step) begin
                unique case (bcnt_q)
                3'd0: begin
                    if (bin) begin                   // sub 0 (8x8)
                        sub_q[{pb_q, 2'b0} +: 4] <= 4'd0;
                        if (pb_q == 2'd3) begin
                            pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
                            st_q <= M_B0;
                        end else pb_q <= pb_q + 2'd1;
                    end else bcnt_q <= 3'd1;
                end
                3'd1: begin
                    if (!bin) begin                  // sub 1 (8x4)
                        sub_q[{pb_q, 2'b0} +: 4] <= 4'd1;
                        bcnt_q <= '0;
                        if (pb_q == 2'd3) begin
                            pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
                            st_q <= M_B0;
                        end else pb_q <= pb_q + 2'd1;
                    end else bcnt_q <= 3'd2;
                end
                default: begin                       // 2 (4x8) : 3 (4x4)
                    sub_q[{pb_q, 2'b0} +: 4] <= bin ? 4'd2 : 4'd3;
                    bcnt_q <= '0;
                    if (pb_q == 2'd3) begin
                        pb_q <= '0; ps_q <= '0; axis_q <= 1'b0;
                        st_q <= M_B0;
                    end else pb_q <= pb_q + 2'd1;
                end
                endcase
            end

            // ---- mvd component (UEG3) ----
            M_B0: if (step) begin
                if (!bin) finish_comp(16'd0, 7'd0);  // zero, no sign bin
                else begin
                    uegv_q <= 16'd1;
                    uctx_q <= '0;
                    st_q <= M_U;
                end
            end

            M_U: if (step) begin
                if (bin) begin
                    if (uegv_q == 16'd8) begin       // escape to EG3
                        uegv_q <= 16'd9;
                        egk3_q <= 5'd3;
                        st_q <= M_EGP;
                    end else begin
                        if (uegv_q < 16'd4) uctx_q <= uctx_q + 3'd1;
                        uegv_q <= uegv_q + 16'd1;
                    end
                end else
                    st_q <= M_SGN;
            end

            M_EGP: if (step) begin
                if (bin) begin
                    uegv_q <= uegv_q + (16'd1 << egk3_q);
                    egk3_q <= egk3_q + 5'd1;
                    if (egk3_q > 5'd24) st_q <= S_ERR;
                end else begin
                    if (egk3_q == 5'd0) st_q <= M_SGN;
                    else st_q <= M_EGS;
                end
            end

            M_EGS: if (step) begin
                uegv_q <= uegv_q + (16'(bin) << (egk3_q - 5'd1));
                if (egk3_q == 5'd1) st_q <= M_SGN;
                else egk3_q <= egk3_q - 5'd1;
            end

            M_SGN: if (step)
                finish_comp(bin ? -uegv_q : uegv_q,
                            (uegv_q < 16'd70) ? uegv_q[6:0] : 7'd70);

            S_MBT: if (step) begin
                unique case (bcnt_q)
                3'd0: begin
                    if (!bin) begin                  // I_4x4
                        k_q <= '0; bcnt_q <= '0;
                        st_q <= S_I4M;
                    end else begin
                        t_q <= 5'd1;
                        bcnt_q <= 3'd1;
                    end
                end
                3'd1: begin                          // PCM terminate
                    if (bin) st_q <= S_ERR;          // I_PCM unsupported
                    else bcnt_q <= 3'd2;
                end
                3'd2: begin
                    if (bin) t_q <= t_q + 5'd12;
                    bcnt_q <= 3'd3;
                end
                3'd3: bcnt_q <= bin ? 3'd4 : 3'd5;
                3'd4: begin
                    t_q <= t_q + (bin ? 5'd8 : 5'd4);
                    bcnt_q <= 3'd5;
                end
                3'd5: begin
                    if (bin) t_q <= t_q + 5'd2;
                    bcnt_q <= 3'd6;
                end
                default: begin                       // last bin: finalize
                    i16_q <= 1'b1;
                    // eff uses the post-add t; compute inline
                    st_q <= S_CMD;
                    bcnt_q <= '0;
                    if (bin) t_q <= t_q + 5'd1;
                end
                endcase
            end

            S_I4M: if (step) begin
                unique case (bcnt_q)
                3'd0: begin
                    if (bin) begin                   // prev flag: use pred
                        i4m_q[k_q] <= i4_pred;
                        if (k_q == 4'd15) begin
                            bcnt_q <= '0;
                            st_q <= S_CMD;
                        end else k_q <= k_q + 4'd1;
                    end else begin
                        m_q <= '0;
                        bcnt_q <= 3'd1;
                    end
                end
                3'd1: begin
                    m_q[0] <= bin;
                    bcnt_q <= 3'd2;
                end
                3'd2: begin
                    m_q[1] <= bin;
                    bcnt_q <= 3'd3;
                end
                default: begin
                    logic [3:0] m;
                    m = {1'b0, bin, m_q[1], m_q[0]};
                    i4m_q[k_q] <= m + 4'({1'b0, m} >= {1'b0, i4_pred});
                    bcnt_q <= '0;
                    if (k_q == 4'd15) st_q <= S_CMD;
                    else k_q <= k_q + 4'd1;
                end
                endcase
            end

            S_CMD: if (step) begin
                unique case (bcnt_q)
                3'd0: begin
                    if (!bin) begin
                        cmode_q <= 2'd0;
                        st_q <= i16_q ? S_QPD : S_CBP;
                        bcnt_q <= '0;
                        if (i16_q) begin
                            // I16 header fields from mb_type
                            i16m_q <= eff[1:0];
                            cbp_q <= {chroma_part(eff), luma_part(eff)};
                        end
                    end else bcnt_q <= 3'd1;
                end
                3'd1: begin
                    if (!bin) begin
                        cmode_q <= 2'd1;
                        st_q <= i16_q ? S_QPD : S_CBP;
                        bcnt_q <= '0;
                        if (i16_q) begin
                            i16m_q <= eff[1:0];
                            cbp_q <= {chroma_part(eff), luma_part(eff)};
                        end
                    end else bcnt_q <= 3'd2;
                end
                default: begin
                    cmode_q <= bin ? 2'd3 : 2'd2;
                    st_q <= i16_q ? S_QPD : S_CBP;
                    bcnt_q <= '0;
                    if (i16_q) begin
                        i16m_q <= eff[1:0];
                        cbp_q <= {chroma_part(eff), luma_part(eff)};
                    end
                end
                endcase
            end

            S_CBP: if (step) begin
                unique case (bcnt_q)
                3'd0, 3'd1, 3'd2, 3'd3: begin
                    cbp_q[2'(bcnt_q)] <= bin;
                    bcnt_q <= bcnt_q + 3'd1;
                end
                3'd4: begin
                    if (!bin) begin
                        bcnt_q <= '0;
                        if (cbp_q[3:0] != 4'd0) st_q <= S_QPD;
                        else begin                   // no residual at all
                            lastqpd_q <= 1'b0;
                            rph_q <= 2'd1;
                            k_q <= '0; comp_q <= 1'b0;
                            st_q <= R_NEXT;
                        end
                    end else bcnt_q <= 3'd5;
                end
                default: begin
                    cbp_q[5:4] <= bin ? 2'd2 : 2'd1;
                    bcnt_q <= '0;
                    st_q <= S_QPD;
                end
                endcase
            end

            S_QPD: if (step) begin
                unique case (bcnt_q)
                3'd0: begin
                    if (!bin) begin
                        lastqpd_q <= 1'b0;
                        st_q <= R_NEXT;
                        rph_q <= i16_q ? 2'd0 : 2'd1;
                        k_q <= '0; comp_q <= 1'b0;
                    end else begin
                        uval_q <= 7'd1;
                        bcnt_q <= 3'd1;
                    end
                end
                default: begin
                    if (bin) begin
                        uval_q <= uval_q + 7'd1;
                        bcnt_q <= 3'd2;
                        if (uval_q > 7'd104) st_q <= S_ERR;
                    end else begin
                        logic signed [7:0] d;
                        d = uval_q[0] ? 8'(({1'b0, uval_q} + 8'd1) >> 1)
                                      : -8'(({1'b0, uval_q} + 8'd1) >> 1);
                        if (d < -26 || d > 25) st_q <= S_ERR;
                        else begin
                            qp_q <= 6'((13'($signed({1'b0, qp_q})) +
                                        13'(d) + 13'd52) % 13'd52);
                            lastqpd_q <= 1'b1;
                            st_q <= R_NEXT;
                            rph_q <= i16_q ? 2'd0 : 2'd1;
                            k_q <= '0; comp_q <= 1'b0;
                        end
                    end
                end
                endcase
            end

            // ---- residual scheduling ----
            R_NEXT: begin
                logic skip_blk;
                skip_blk = 1'b0;
                unique case (rph_q)
                2'd0: ;                              // luma DC: always
                2'd1: skip_blk = !cbp_q[{k_q[3], k_q[2]}];
                2'd2: skip_blk = (cbp_q[5:4] == 2'd0);
                default: skip_blk = (cbp_q[5:4] != 2'd2);
                endcase
                if (skip_blk) begin
                    // cbf stays 0; advance
                    adv_block();
                end else begin
                    rsig_q <= '0;
                    rcnt_q <= '0;
                    node_q <= '0;
                    st_q <= R_CBF;
                end
            end

            R_CBF: if (step) begin
                if (!bin) begin
                    adv_block();                     // cbf = 0
                end else begin
                    set_cbf();
                    st_q <= (rmax == 5'd1) ? R_L1 : R_SIG;
                    if (rmax == 5'd1) begin
                        ridx[0] <= '0;
                        rcnt_q <= 5'd1;
                    end
                end
            end

            R_SIG: if (step) begin
                if (bin) begin
                    ridx[rcnt_q[3:0]] <= 4'(rsig_q);
                    rcnt_q <= rcnt_q + 5'd1;
                    st_q <= R_LAST;
                end else begin
                    if (rsig_q == rmax - 5'd2) begin
                        // final position is implicitly significant
                        ridx[rcnt_q[3:0]] <= 4'(rmax - 5'd1);
                        rcnt_q <= rcnt_q + 5'd1;
                        st_q <= R_L1;
                    end else
                        rsig_q <= rsig_q + 5'd1;
                end
            end

            R_LAST: if (step) begin
                if (bin) st_q <= R_L1;
                else begin
                    if (rsig_q == rmax - 5'd2) begin
                        ridx[rcnt_q[3:0]] <= 4'(rmax - 5'd1);
                        rcnt_q <= rcnt_q + 5'd1;
                        st_q <= R_L1;
                    end else begin
                        rsig_q <= rsig_q + 5'd1;
                        st_q <= R_SIG;
                    end
                end
            end

            R_L1: if (step) begin
                egv_q <= '0;
                if (!bin) begin
                    abs_q <= 5'd1;
                    node_q <= tr_eq1(node_q);
                    st_q <= R_SIGN;
                end else begin
                    abs_q <= 5'd2;
                    st_q <= R_GT1;
                end
            end

            R_GT1: if (step) begin
                if (bin) begin
                    if (abs_q == 5'd14) begin
                        abs_q <= 5'd15;
                        egk_q <= '0;
                        node_q <= tr_gt1(node_q);
                        st_q <= R_EGP;
                    end else
                        abs_q <= abs_q + 5'd1;
                end else begin
                    node_q <= tr_gt1(node_q);
                    st_q <= R_SIGN;
                end
            end

            R_EGP: if (step) begin
                if (bin && egk_q < 5'd23)
                    egk_q <= egk_q + 5'd1;
                else begin
                    egv_q <= 16'd1;
                    if (egk_q == 5'd0) st_q <= R_SIGN;
                    else st_q <= R_EGS;
                end
            end

            R_EGS: if (step) begin
                egv_q <= {egv_q[14:0], bin};
                if (egk_q == 5'd1) st_q <= R_SIGN;
                else egk_q <= egk_q - 5'd1;
            end

            R_SIGN: if (step) begin
                rcnt_q <= rcnt_q - 5'd1;
                if (rcnt_q == 5'd1) adv_block();
                else st_q <= R_L1;
            end

            S_EOS: if (step) begin
                // end_of_slice must be 0 before the last MB
                if (bin && !(mbx_q == cfg_mb_w - 8'd1 &&
                             mby_q == cfg_mb_h - 8'd1))
                    st_q <= S_ERR;
                else if (!bin && (mbx_q == cfg_mb_w - 8'd1 &&
                                  mby_q == cfg_mb_h - 8'd1))
                    st_q <= S_ERR;
                else
                    st_q <= S_EMIT;
            end

            S_EMIT: if (rec_done) begin
                // neighbor advance
                l_valid <= 1'b1;
                l_cat <= i16_q;
                l_cmode <= (cmode_q != 2'd0);
                l_cbp <= cbp_q;
                l_ldc <= ldc_q;
                l_cdc <= cdc_q;
                for (int j = 0; j < 4; j++) begin
                    l_cbfl[j] <= cbfl_q[{2'(j), 2'd3}];
                    l_i4m[j] <= i4m_q[zidx(2'd3, 2'(j))];
                end
                l_cbfc[0] <= {cbfc_q[0][3], cbfc_q[0][1]};
                l_cbfc[1] <= {cbfc_q[1][3], cbfc_q[1][1]};
                l_skip <= skip_q;
                for (int j = 0; j < 4; j++) begin
                    l_avx[j] <= cur_avx[j*4+3];
                    l_avy[j] <= cur_avy[j*4+3];
                end
                nrow[mbx_q] <= {
                    cur_avy[15], cur_avx[15], cur_avy[14], cur_avx[14],
                    cur_avy[13], cur_avx[13], cur_avy[12], cur_avx[12],
                    skip_q,
                    i4m_q[zidx(2'd3, 2'd3)], i4m_q[zidx(2'd2, 2'd3)],
                    i4m_q[zidx(2'd1, 2'd3)], i4m_q[zidx(2'd0, 2'd3)],
                    cbfc_q[1][3:2], cbfc_q[0][3:2],
                    cbfl_q[15:12], cdc_q, ldc_q, cbp_q,
                    (cmode_q != 2'd0), i16_q };
                if (mbx_q == cfg_mb_w - 8'd1 &&
                    mby_q == cfg_mb_h - 8'd1) begin
                    st_q <= S_DONE;
                end else begin
                    if (mbx_q == cfg_mb_w - 8'd1) begin
                        mbx_q <= '0;
                        mby_q <= mby_q + 8'd1;
                        l_valid <= 1'b0;
                    end else
                        mbx_q <= mbx_q + 8'd1;
                    st_q <= S_PRE;
                end
            end

            S_DONE: st_q <= S_DONE;
            S_ERR: st_q <= S_ERR;
            default: st_q <= S_ERR;
            endcase
        end
    end

    logic [6:0] avxc_q;                // clipped |mvd_x| awaiting store

    // one mvd component decoded: latch it, store the pair on y, and
    // advance the partition walk (mirrors the C parse order)
    task automatic finish_comp(input logic signed [15:0] v,
                               input logic [6:0] vclip);
        if (!axis_q) begin
            mvdx_q <= v;
            avxc_q <= vclip;
            axis_q <= 1'b1;
            st_q <= M_B0;
        end else begin
            mvdy_q <= v;
            mvdv_q <= 1'b1;
            // store |mvd| over the partition blocks
            for (int j = 0; j < 4; j++)
                for (int i = 0; i < 4; i++)
                    if (i >= int'(g_bx0) && i < int'(g_bx0) + int'(g_w4) &&
                        j >= int'(g_by0) && j < int'(g_by0) + int'(g_h4))
                    begin
                        cur_avx[j*4+i] <= avxc_q;
                        cur_avy[j*4+i] <= vclip;
                        av_w[j*4+i] <= 1'b1;
                    end
            axis_q <= 1'b0;
            // partition advance
            if (ptype_q == 5'd0) st_q <= S_CBP;
            else if (ptype_q == 5'd1 || ptype_q == 5'd2) begin
                if (pb_q[0]) st_q <= S_CBP;
                else begin pb_q <= 2'd1; st_q <= M_B0; end
            end else begin
                if (3'(ps_q) + 3'd1 == nsub) begin
                    if (pb_q == 2'd3) st_q <= S_CBP;
                    else begin
                        pb_q <= pb_q + 2'd1;
                        ps_q <= '0;
                        st_q <= M_B0;
                    end
                end else begin
                    ps_q <= ps_q + 2'd1;
                    st_q <= M_B0;
                end
            end
        end
    endtask

    // advance to the next residual block / finish the MB
    task automatic adv_block();
        unique case (rph_q)
        2'd0: begin rph_q <= 2'd1; k_q <= '0; st_q <= R_NEXT; end
        2'd1: begin
            if (k_q == 4'd15) begin
                rph_q <= 2'd2; comp_q <= 1'b0; st_q <= R_NEXT;
            end else begin
                k_q <= k_q + 4'd1; st_q <= R_NEXT;
            end
        end
        2'd2: begin
            if (!comp_q) begin comp_q <= 1'b1; st_q <= R_NEXT; end
            else begin
                rph_q <= 2'd3; comp_q <= 1'b0; k_q <= '0;
                st_q <= R_NEXT;
            end
        end
        default: begin
            if (k_q == 4'd3 && comp_q) st_q <= S_EOS;
            else if (k_q == 4'd3) begin
                comp_q <= 1'b1; k_q <= '0; st_q <= R_NEXT;
            end else begin
                k_q <= k_q + 4'd1; st_q <= R_NEXT;
            end
        end
        endcase
    endtask

    // record cbf=1 for the block that just produced coefficients
    task automatic set_cbf();
        unique case (rph_q)
        2'd0: ldc_q <= 1'b1;
        2'd1: cbfl_q[{zsy(k_q), zsx(k_q)}] <= 1'b1;
        2'd2: cdc_q[comp_q] <= 1'b1;
        default: cbfc_q[comp_q][{k_q[1], k_q[0]}] <= 1'b1;
        endcase
    endtask

    // I16 cbp parts from eff = mb_type-1 (0..23)
    function automatic logic [3:0] luma_part(input logic [4:0] e);
        return (e >= 5'd12) ? 4'hF : 4'h0;
    endfunction
    function automatic logic [1:0] chroma_part(input logic [4:0] e);
        logic [4:0] r;
        r = (e >= 5'd12) ? (e - 5'd12) : e;
        return (r < 5'd4) ? 2'd0 : (r < 5'd8) ? 2'd1 : 2'd2;
    endfunction

endmodule
