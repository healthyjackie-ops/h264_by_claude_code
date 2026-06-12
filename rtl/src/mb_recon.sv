// mb_recon — baseline-I macroblock reconstruction (rtl_spec.md R2c).
//
// Consumes mb_dec's tagged coefficient stream into a block RAM, then on
// the header pulse rebuilds the MB: Intra16 (luma DC Hadamard + one
// 16x16 prediction + 16 AC blocks) or Intra4x4 (per-block prediction
// with the in-MB reconstruction feedback loop), then chroma (8x8
// prediction + DC + AC). Neighbor samples come from one top line buffer
// per plane, left columns, and the corner-register chain. Serial, one
// 4x4 block per cycle group — correctness first, pipelining is R3.
`include "transform_dec.sv"

module mb_recon #(
    parameter int MAX_MBW = 120
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  cfg_mb_w,
    input  logic signed [5:0] cfg_cqp_off,

    // from mb_dec
    input  logic        coef_we,
    input  logic [4:0]  coef_blk,
    input  logic [3:0]  coef_addr,
    input  logic signed [15:0] coef_data,
    input  logic        mb_valid,
    input  logic [7:0]  mb_x,
    input  logic [7:0]  mb_y,
    input  logic        mb_i16,
    input  logic [5:0]  mb_cbp,
    input  logic [5:0]  mb_qp,
    input  logic [1:0]  mb_i16_mode,
    input  logic [1:0]  mb_cmode,
    input  logic [63:0] mb_i4m,

    output logic        busy,
    output logic        accepted,      // header taken; parser may proceed
    output logic [7:0]  rec_x,         // latched coords for the consumer
    output logic [7:0]  rec_yc,
    output logic [5:0]  rec_qp,
    output logic        rec_valid,     // one-cycle pulse, planes readable
    output logic [7:0]  rec_y [256],
    output logic [7:0]  rec_u [64],
    output logic [7:0]  rec_v [64],
    output logic        err
);

    import transform_pkg::*;

    function automatic logic [5:0] chroma_qp(input logic [5:0] q);
        logic [5:0] r;
        unique case (q)
            6'd30: r = 6'd29; 6'd31: r = 6'd30; 6'd32: r = 6'd31;
            6'd33: r = 6'd32; 6'd34: r = 6'd32; 6'd35: r = 6'd33;
            6'd36: r = 6'd34; 6'd37: r = 6'd34; 6'd38: r = 6'd35;
            6'd39: r = 6'd35; 6'd40: r = 6'd36; 6'd41: r = 6'd36;
            6'd42: r = 6'd37; 6'd43: r = 6'd37; 6'd44: r = 6'd37;
            6'd45: r = 6'd38; 6'd46: r = 6'd38; 6'd47: r = 6'd38;
            6'd48: r = 6'd39; 6'd49: r = 6'd39; 6'd50: r = 6'd39;
            6'd51: r = 6'd39;
            default: r = q;
        endcase
        return r;
    endfunction

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

    // coefficient store: 27 blocks x 256b wide words (16 lanes x 16b).
    // Single lane-write port + async row reads -> yosys keeps it as a
    // memory under `memory -nomap` (R4d).
    // double-banked store (R4f): mb_dec fills one bank while this MB
    // reconstructs (and afterwards clears) the other — the serial clear
    // and the parse/reconstruct overlap instead of serializing.
    logic [255:0] cramA [27];
    logic [255:0] cramB [27];
    logic         wb_q;                // bank being written by mb_dec
    logic [4:0] clr_q;                 // serial clear row counter

    // explicit async read ports (continuous assigns keep yosys's memory
    // inference happy — a function wrapping mem reads gets inlined by
    // sv2v into an @(cram) sensitivity list the verilog frontend rejects)
    logic [4:0] dq_row;
    wire [255:0] cramA_wr_old = cramA[coef_blk];
    wire [255:0] cramB_wr_old = cramB[coef_blk];
    logic [255:0] cram_wr_new;
    always_comb begin
        cram_wr_new = wb_q ? cramB_wr_old : cramA_wr_old;
        cram_wr_new[coef_addr*16 +: 16] = coef_data;
    end
    // read side: the bank NOT being written (the accepted MB's bank)
    wire [255:0] cram_ldc_w = wb_q ? cramA[16] : cramB[16];
    wire [255:0] cram_cdc_w = wb_q ? cramA[{4'b1000, comp_q} + 5'd1]
                                   : cramB[{4'b1000, comp_q} + 5'd1];
    wire [255:0] cram_dq_w  = wb_q ? cramA[dq_row] : cramB[dq_row];

    // neighbor line buffers, one wide word per MB column (R4d: single
    // write port + async row read -> memory inference)
    logic [127:0] top_y [MAX_MBW];
    logic [63:0]  top_u [MAX_MBW];
    logic [63:0]  top_v [MAX_MBW];
    // prefetched copies for the MB being reconstructed (cur + next for
    // the I4x4 top-right reach across the MB boundary)
    logic [127:0] tyc_q, tyn_q;
    logic [63:0]  tuc_q, tvc_q;
    // async read ports (assign form keeps yosys memory inference alive)
    wire [127:0] ty_cur_w = top_y[mb_x];
    wire [127:0] ty_nxt_w = top_y[mb_x + 8'd1];
    wire [63:0]  tu_cur_w = top_u[mb_x];
    wire [63:0]  tv_cur_w = top_v[mb_x];
    logic [7:0] left_y [16];
    logic [7:0] left_u [8];
    logic [7:0] left_v [8];
    logic [7:0] tl_y, tl_u, tl_v;
    logic [7:0] tlq_y, tlq_u, tlq_v;   // staged corner for this MB

    // latched header
    logic [7:0] mbx_q, mby_q;
    logic       i16_q;
    logic [5:0] cbp_q, qp_q;
    logic [1:0] i16m_q, cmode_q;
    logic [3:0] i4m_q [16];
    logic       have_left, have_top;

    typedef enum logic [3:0] {
        S_IDLE, S_LDC, S_YPRED16, S_YBLK, S_YBLK_WR, S_CPRED, S_CDC,
        S_CBLK, S_CBLK_WR, S_UPD, S_CLR, S_OUT, S_ERR
    } state_e;
    state_e st_q;
    logic [4:0] k_q;
    logic       comp_q;

    assign busy = (st_q != S_IDLE);
    assign accepted = (st_q == S_IDLE) && mb_valid;
    assign rec_x = mbx_q;
    assign rec_yc = mby_q;
    assign rec_qp = qp_q;
    assign rec_valid = (st_q == S_OUT);
    assign err = (st_q == S_ERR);

    // ---- combinational units ----
    // luma DC
    logic signed [15:0] ldc_in [16];
    logic signed [31:0] ldc_out [16];
    always_comb
        for (int i = 0; i < 16; i++) ldc_in[i] = cram_ldc_w[i*16 +: 16];
    luma_dc_dequant u_ldc (.c(ldc_in), .qp(qp_q), .dc(ldc_out));
    logic signed [31:0] ldc_q [16];

    // chroma DC (per active component)
    logic signed [15:0] cdc_in [4];
    logic signed [31:0] cdc_out [4];
    logic [5:0] qpc;
    always_comb begin
        logic signed [7:0] qsum;
        qsum = $signed({2'b0, qp_q}) + 8'(cfg_cqp_off);
        if (qsum < 0) qsum = 0;
        if (qsum > 51) qsum = 51;
        qpc = chroma_qp(6'(qsum));
        for (int i = 0; i < 4; i++)
            cdc_in[i] = cram_cdc_w[i*16 +: 16];
    end
    chroma_dc_dequant u_cdc (.c(cdc_in), .qp(qpc), .dc(cdc_out));
    logic signed [31:0] cdc_q [4];

    always_comb begin
        if (st_q == S_CBLK || st_q == S_CBLK_WR)
            dq_row = 5'd19 + {3'b0, comp_q} * 5'd4 + (k_q & 5'd3);
        else
            dq_row = 5'(k_q);
    end

    // current 4x4 residual block -> dequant -> idct_add
    logic signed [15:0] dq_in [16];
    logic signed [31:0] dq_out [16];
    logic [5:0] dq_qp;
    assign dq_qp = (st_q == S_CBLK || st_q == S_CBLK_WR) ? qpc : qp_q;
    dequant4x4 u_dq (.c(dq_in), .qp(dq_qp), .d(dq_out));

    // R4a pipeline cut: dequant/prediction results latch one cycle
    // before the IDCT+clip-add stage, halving the critical path.
    logic signed [31:0] id_in [16];
    logic [7:0] id_pred [16];
    logic signed [31:0] id_in_q [16];
    logic [7:0] id_pred_q [16];
    logic [7:0] id_out [16];
    idct4x4_add u_id (.d(id_in_q), .pred(id_pred_q), .out(id_out));

    // ---- intra predictors ----
    // I4x4 neighbors for block k_q, from rec_y / line buffers
    logic [1:0] bx4, by4;
    assign bx4 = zsx(4'(k_q));
    assign by4 = zsy(4'(k_q));

    logic [7:0] n_l [4];
    logic [7:0] n_t [8];
    logic [7:0] n_tl;
    logic       a_l, a_t, a_tl, a_tr;
    always_comb begin
        int px, py;
        px = int'(bx4) * 4;
        py = int'(by4) * 4;
        a_l = (bx4 != 0) || have_left;
        a_t = (by4 != 0) || have_top;
        a_tl = ((bx4 != 0) || have_left) && ((by4 != 0) || have_top);
        // top-right: decoded-before in z-order, or the upper MB row
        if (by4 == 0) begin
            a_tr = have_top &&
                   ((bx4 != 2'd3) ? 1'b1
                    : ({mbx_q, 2'b0} + 8'd4 < {cfg_mb_w, 2'b0}));
        end else begin
            // inside the MB: TR block is (bx+1, by-1); decoded iff its
            // z index precedes k and it exists (bx<3)
            a_tr = (bx4 != 2'd3) &&
                   (zidx(bx4 + 2'd1, by4 - 2'd1) < 4'(k_q));
        end
        for (int i = 0; i < 4; i++) begin
            n_l[i] = (bx4 == 0) ? left_y[py + i]
                                : rec_y[(py + i) * 16 + px - 1];
        end
        for (int i = 0; i < 4; i++) begin
            n_t[i] = (by4 == 0) ? tyc_q[(px + i) * 8 +: 8]
                                : rec_y[(py - 1) * 16 + px + i];
        end
        for (int i = 0; i < 4; i++) begin
            logic [7:0] e;
            if (!a_tr) e = n_t[3];
            else if (by4 == 0) begin
                e = (px + 4 + i < 16) ? tyc_q[(px + 4 + i) * 8 +: 8]
                                      : tyn_q[(px + 4 + i - 16) * 8 +: 8];
            end else e = rec_y[(py - 1) * 16 + px + 4 + i];
            n_t[4 + i] = e;
        end
        if (bx4 == 0 && by4 == 0)      n_tl = tlq_y;
        else if (bx4 == 0)             n_tl = left_y[py - 1];
        else if (by4 == 0)             n_tl = tyc_q[(px - 1) * 8 +: 8];
        else                           n_tl = rec_y[(py - 1) * 16 + px - 1];
    end

    logic [7:0] p4 [16];
    logic       p4_ok;
    intra4x4_pred u_i4 (
        .l(n_l), .t(n_t), .tl(n_tl),
        .avail_left(a_l), .avail_top(a_t), .avail_topleft(a_tl),
        .mode(i4m_q[4'(k_q)]),
        .pred(p4), .ok(p4_ok)
    );

    // I16 prediction (whole MB)
    logic [7:0] i16_l [16];
    logic [7:0] i16_t [16];
    logic [7:0] p16 [256];
    logic       p16_ok;
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            i16_l[i] = left_y[i];
            i16_t[i] = tyc_q[i * 8 +: 8];
        end
    end
    intra16_pred u_i16 (
        .l(i16_l), .t(i16_t), .tl(tlq_y),
        .avail_left(have_left), .avail_top(have_top),
        .mode(i16m_q), .pred(p16), .ok(p16_ok)
    );

    // chroma prediction (per component)
    logic [7:0] ch_l [8];
    logic [7:0] ch_t [8];
    logic [7:0] ch_tl;
    logic [7:0] pch [64];
    logic       pch_ok;
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            ch_l[i] = comp_q ? left_v[i] : left_u[i];
            ch_t[i] = comp_q ? tvc_q[i * 8 +: 8] : tuc_q[i * 8 +: 8];
        end
        ch_tl = comp_q ? tlq_v : tlq_u;
    end
    chroma_pred u_ch (
        .l(ch_l), .t(ch_t), .tl(ch_tl),
        .avail_left(have_left), .avail_top(have_top),
        .mode(cmode_q), .pred(pch), .ok(pch_ok)
    );

    // residual routing into the shared dequant/idct
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            dq_in[i] = '0;
            id_pred[i] = '0;
        end
        if (st_q == S_YBLK || st_q == S_YBLK_WR) begin
            int px, py;
            px = int'(bx4) * 4;
            py = int'(by4) * 4;
            for (int i = 0; i < 16; i++)
                dq_in[i] = cram_dq_w[i*16 +: 16];
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++)
                    id_pred[y*4+x] = i16_q ? rec_y[(py+y)*16 + px+x]
                                           : p4[y*4+x];
        end else if (st_q == S_CBLK || st_q == S_CBLK_WR) begin
            int px, py;
            px = (int'(k_q) & 1) * 4;
            py = ((int'(k_q) >> 1) & 1) * 4;
            for (int i = 0; i < 16; i++)
                dq_in[i] = cram_dq_w[i*16 +: 16];
            for (int y = 0; y < 4; y++)
                for (int x = 0; x < 4; x++)
                    id_pred[y*4+x] = comp_q ? rec_v[(py+y)*8 + px+x]
                                            : rec_u[(py+y)*8 + px+x];
        end
    end
    always_comb begin
        for (int i = 0; i < 16; i++) id_in[i] = dq_out[i];
        if ((st_q == S_YBLK || st_q == S_YBLK_WR) && i16_q)
            id_in[0] = ldc_q[{by4, bx4}];          // raster DC position
        if (st_q == S_CBLK || st_q == S_CBLK_WR)
            id_in[0] = cdc_q[k_q & 5'd3];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            k_q <= '0;
            comp_q <= 1'b0;
            mbx_q <= '0; mby_q <= '0;
            i16_q <= 1'b0; cbp_q <= '0; qp_q <= '0;
            i16m_q <= '0; cmode_q <= '0;
            have_left <= 1'b0;
            have_top <= 1'b0;
            tl_y <= '0; tl_u <= '0; tl_v <= '0;
            tlq_y <= '0; tlq_u <= '0; tlq_v <= '0;
            clr_q <= '0;
            wb_q <= 1'b0;
        end else begin
            // per-bank single write ports: capture goes to wb_q's bank,
            // the serial clear scrubs the other (just-reconstructed) one
            if (wb_q) begin
                if (coef_we) cramB[coef_blk] <= cram_wr_new;
                if (st_q == S_CLR) cramA[clr_q] <= '0;
            end else begin
                if (coef_we) cramA[coef_blk] <= cram_wr_new;
                if (st_q == S_CLR) cramB[clr_q] <= '0;
            end

            unique case (st_q)
            S_IDLE: if (mb_valid) begin
                wb_q <= ~wb_q;                 // incoming MB fills the
                                               // other bank from now on
                mbx_q <= mb_x;
                mby_q <= mb_y;
                i16_q <= mb_i16;
                cbp_q <= mb_cbp;
                qp_q <= mb_qp;
                i16m_q <= mb_i16_mode;
                cmode_q <= mb_cmode;
                for (int i = 0; i < 16; i++)
                    i4m_q[i] <= mb_i4m[i*4 +: 4];
                have_left <= (mb_x != 8'd0);
                have_top <= (mb_y != 8'd0);
                // stage the corner for THIS MB before top_y is rewritten
                tlq_y <= tl_y;
                tlq_u <= tl_u;
                tlq_v <= tl_v;
                tl_y <= ty_cur_w[127:120];
                tl_u <= tu_cur_w[63:56];
                tl_v <= tv_cur_w[63:56];
                // prefetch the upper-row words (cur + next MB column)
                tyc_q <= ty_cur_w;
                tyn_q <= (mb_x + 8'd1 < cfg_mb_w) ? ty_nxt_w : '0;
                tuc_q <= tu_cur_w;
                tvc_q <= tv_cur_w;
                st_q <= mb_i16 ? S_LDC : S_YBLK;
                k_q <= '0;
            end

            S_LDC: begin
                for (int i = 0; i < 16; i++) ldc_q[i] <= ldc_out[i];
                st_q <= S_YPRED16;
            end

            S_YPRED16: begin
                if (!p16_ok) st_q <= S_ERR;
                else begin
                    for (int i = 0; i < 256; i++) rec_y[i] <= p16[i];
                    st_q <= S_YBLK;
                end
            end

            S_YBLK: begin
                // latch phase: dequant + prediction registered for the
                // IDCT stage (every block passes through; zero cram makes
                // the add identity for I4x4, DC-only for I16)
                if (!i16_q && !p4_ok) st_q <= S_ERR;
                else begin
                    for (int i = 0; i < 16; i++) begin
                        id_in_q[i] <= id_in[i];
                        id_pred_q[i] <= id_pred[i];
                    end
                    st_q <= S_YBLK_WR;
                end
            end

            S_YBLK_WR: begin
                int px, py;
                px = int'(bx4) * 4;
                py = int'(by4) * 4;
                for (int y = 0; y < 4; y++)
                    for (int x = 0; x < 4; x++)
                        rec_y[(py+y)*16 + px+x] <= id_out[y*4+x];
                if (k_q == 5'd15) begin
                    k_q <= '0;
                    comp_q <= 1'b0;
                    st_q <= S_CPRED;
                end else begin
                    k_q <= k_q + 5'd1;
                    st_q <= S_YBLK;
                end
            end

            S_CPRED: begin
                if (!pch_ok) st_q <= S_ERR;
                else if (!comp_q) begin
                    for (int i = 0; i < 64; i++) rec_u[i] <= pch[i];
                    comp_q <= 1'b1;
                end else begin
                    for (int i = 0; i < 64; i++) rec_v[i] <= pch[i];
                    comp_q <= 1'b0;
                    k_q <= '0;
                    st_q <= (cbp_q[5:4] != 2'd0) ? S_CDC : S_UPD;
                end
            end

            S_CDC: begin
                for (int i = 0; i < 4; i++) cdc_q[i] <= cdc_out[i];
                k_q <= '0;
                st_q <= S_CBLK;
            end

            S_CBLK: begin
                for (int i = 0; i < 16; i++) begin
                    id_in_q[i] <= id_in[i];
                    id_pred_q[i] <= id_pred[i];
                end
                st_q <= S_CBLK_WR;
            end

            S_CBLK_WR: begin
                int px, py;
                px = (int'(k_q) & 1) * 4;
                py = ((int'(k_q) >> 1) & 1) * 4;
                if (comp_q)
                    for (int y = 0; y < 4; y++)
                        for (int x = 0; x < 4; x++)
                            rec_v[(py+y)*8 + px+x] <= id_out[y*4+x];
                else
                    for (int y = 0; y < 4; y++)
                        for (int x = 0; x < 4; x++)
                            rec_u[(py+y)*8 + px+x] <= id_out[y*4+x];
                if (k_q == 5'd3) begin
                    if (comp_q) st_q <= S_UPD;
                    else begin
                        comp_q <= 1'b1;
                        st_q <= S_CDC;
                    end
                end else begin
                    k_q <= k_q + 5'd1;
                    st_q <= S_CBLK;
                end
            end

            S_UPD: begin
                logic [127:0] wy;
                logic [63:0] wu, wv;
                for (int i = 0; i < 16; i++) begin
                    wy[i*8 +: 8] = rec_y[15*16 + i];
                    left_y[i] <= rec_y[i*16 + 15];
                end
                for (int i = 0; i < 8; i++) begin
                    wu[i*8 +: 8] = rec_u[7*8 + i];
                    wv[i*8 +: 8] = rec_v[7*8 + i];
                    left_u[i] <= rec_u[i*8 + 7];
                    left_v[i] <= rec_v[i*8 + 7];
                end
                top_y[mbx_q] <= wy;
                top_u[mbx_q] <= wu;
                top_v[mbx_q] <= wv;
                clr_q <= '0;
                st_q <= S_OUT;
            end

            S_OUT: st_q <= S_CLR;

            S_CLR: begin
                clr_q <= clr_q + 5'd1;
                if (clr_q == 5'd26) st_q <= S_IDLE;
            end

            S_ERR: st_q <= S_ERR;
            default: st_q <= S_ERR;
            endcase
        end
    end

endmodule
