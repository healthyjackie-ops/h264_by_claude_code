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
        .init_start(ci_start), .init_qp(cfg_qp), .init_model(2'd3),
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
    logic [34:0] nrow [MAX_MBW];
    wire  [34:0] nrow_rd = nrow[mbx_q];
    logic [34:0] nrow_q;               // prefetched copy for this MB

    // left-neighbor state
    logic        l_valid;
    logic        l_cat, l_cmode;
    logic [5:0]  l_cbp;
    logic        l_ldc;
    logic [1:0]  l_cdc;
    logic [3:0]  l_cbfl;               // right column, rows 0..3
    logic [1:0]  l_cbfc [2];           // right column, rows 0..1
    logic [3:0]  l_i4m [4];

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
        S_EOS, S_EMIT, S_DONE, S_ERR
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

    // ---- coded_block_flag neighbor terms (9.3.3.1.1.9) ----
    // unavailable -> 1 (intra current), I16-vs-I4 DC rule per C model
    logic cond_a, cond_b;
    always_comb begin
        logic [1:0] bx, by;
        bx = zsx(k_q);
        by = zsy(k_q);
        cond_a = 1'b1;
        cond_b = 1'b1;
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
    logic [1:0] mbt_inc, cmd_inc;
    always_comb begin
        mbt_inc = 2'(have_left && l_cat) + 2'(have_top && nrow_q[0]);
        cmd_inc = 2'(have_left && l_cmode) + 2'(have_top && nrow_q[1]);
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
        end else begin
            ci_start <= 1'b0;
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
                st_q <= S_MBT;
            end

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
                nrow[mbx_q] <= {
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
