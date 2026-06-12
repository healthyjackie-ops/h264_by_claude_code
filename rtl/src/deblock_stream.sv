// deblock_stream — line-buffered streaming deblocker (rtl_spec R4g).
//
// Replaces the frame-buffer architecture for synthesis: macroblocks
// stream in raster order; vertical edges filter immediately against the
// left-neighbor register copy, horizontal edge 0 filters against the
// row buffer (the MB above, already vertically filtered), and finished
// macroblocks stream out one row per cycle with a one-MB-row lag:
// after MB(x,y) completes, row_buf[x] holds MB(x,y-1) in its final
// state and is emitted, then the (now right-filtered) left neighbor
// MB(x-1,y) takes its place in the buffer.
//
// All-intra bS as in deblock_frame: 4 on MB edges, 3 inside. Chroma
// QPs map per MB before cross-edge averaging. Memories are wide-word
// single-port (inference-friendly): row_buf_y [MBW*16]x128b etc.
`include "deblock_tables.svh"

module deblock_stream #(
    parameter int MAX_MBW = 120
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  cfg_mb_w,
    input  logic [7:0]  cfg_mb_h,
    input  logic signed [5:0] cfg_cqp_off,
    input  logic signed [5:0] cfg_a_off,
    input  logic signed [5:0] cfg_b_off,
    input  logic        cfg_enable,    // 0 = pass-through (no filtering)

    // MB input (raster); accepted only when idle
    input  logic        mb_push,
    input  logic [7:0]  mb_x,
    input  logic [7:0]  mb_y,
    input  logic [5:0]  mb_qp,
    input  logic        mb_inter,      // P MB (skip incl.): bS 0..2 rules
    input  logic [15:0] mb_nz,         // raster 4x4 luma nz bitmap
    input  logic signed [15:0] mb_mvx [16],   // raster 4x4 MVs
    input  logic signed [15:0] mb_mvy [16],
    input  logic [7:0]  in_y [256],
    input  logic [7:0]  in_u [64],
    input  logic [7:0]  in_v [64],
    output logic        mb_ready,

    input  logic        flush,         // after the last MB: drain buffers
    output logic        flush_done,

    // finished-MB row stream: plane 0=Y(16x128b) 1=U(8x64b) 2=V(8x64b)
    output logic        out_valid,
    output logic [7:0]  out_mbx,
    output logic [7:0]  out_mby,
    output logic [1:0]  out_plane,
    output logic [3:0]  out_row,
    output logic [127:0] out_data      // U/V rows in [63:0]
);

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
    function automatic logic [5:0] clip51(input logic signed [8:0] v);
        if (v < 0) return 6'd0;
        if (v > 51) return 6'd51;
        return v[5:0];
    endfunction

    // ---- state buffers ----
    logic [7:0] cur_y [256];
    logic [7:0] cur_u [64];
    logic [7:0] cur_v [64];
    logic [7:0] lft_y [256];
    logic [7:0] lft_u [64];
    logic [7:0] lft_v [64];
    logic       lft_valid;
    logic [5:0] cur_qp, lft_qp;
    logic [7:0] cur_x, cur_yc;

    // row buffer: one wide word per MB row line (inference-friendly)
    logic [127:0] row_y [MAX_MBW * 16];
    logic [63:0]  row_u [MAX_MBW * 8];
    logic [63:0]  row_v [MAX_MBW * 8];
    logic [5:0]   row_qp [MAX_MBW];
    logic [MAX_MBW-1:0] row_vld;       // packed: not a memory, so the
                                       // async-reset clear is legal

    // motion/nz sideband (P bS): current MB, left MB, and the bottom
    // row of the MB above (133b packed words in row_mi)
    logic        cur_int, lft_int, top_int;
    logic [15:0] cur_nz, lft_nz;
    logic [3:0]  top_nz;
    logic signed [15:0] cur_mvx [16];
    logic signed [15:0] cur_mvy [16];
    logic signed [15:0] lft_mvx [16];
    logic signed [15:0] lft_mvy [16];
    logic signed [15:0] top_mvx [4];
    logic signed [15:0] top_mvy [4];
    logic [132:0] row_mi [MAX_MBW];
    wire  [132:0] row_mi_rd = row_mi[cur_x];
    logic [132:0] lft_mi_pack;
    always_comb begin
        lft_mi_pack[0] = lft_int;
        for (int i = 0; i < 4; i++) begin
            lft_mi_pack[1 + i] = lft_nz[12 + i];
            lft_mi_pack[5  + i*32 +: 16] = lft_mvx[12 + i];
            lft_mi_pack[21 + i*32 +: 16] = lft_mvy[12 + i];
        end
    end

    // top-rows working copy for horizontal edge 0 — byte-array form:
    // dynamic part-selects on array words turn into $shl cells sv2v/yosys
    // choke on, so these are plain byte registers
    logic [7:0] top_y_q [4][16];
    logic [7:0] top_u_q [4][8];
    logic [7:0] top_v_q [4][8];

    typedef enum logic [3:0] {
        S_IDLE, S_VL, S_VC, S_H0RD, S_HL, S_HC,
        S_WB, S_EMIT, S_STORE, S_SHIFT, S_ROWEND, S_FLUSH_COL, S_DONE
    } state_e;
    state_e st_q;
    logic       dir_h;                 // 0 during S_VL/S_VC, 1 during S_HL/S_HC
    logic [1:0] e_q;
    logic [4:0] line_q;
    logic       comp_q;
    logic [4:0] emit_q;                // emit/store row counter
    logic [7:0] fl_x;                  // flush column

    assign mb_ready = (st_q == S_IDLE);
    assign flush_done = (st_q == S_DONE);

    // ---- edge parameter derivation ----
    logic [5:0] qpav, qpcav;
    always_comb begin
        logic [8:0] s;
        logic [5:0] qn;
        logic [5:0] qc, qcn;
        qn = dir_h ? row_qp[cur_x] : lft_qp;
        s = {3'b0, cur_qp} + {3'b0, qn} + 9'd1;
        qpav = (e_q == 0) ? 6'(s >> 1) : cur_qp;
        qc  = chroma_qp(clip51($signed({3'b0, cur_qp}) + 9'(cfg_cqp_off)));
        qcn = chroma_qp(clip51($signed({3'b0, qn}) + 9'(cfg_cqp_off)));
        s = {3'b0, qc} + {3'b0, qcn} + 9'd1;
        qpcav = (e_q == 0) ? 6'(s >> 1) : qc;
    end
    logic chroma_phase;
    assign chroma_phase = (st_q == S_VC) || (st_q == S_HC);
    logic [5:0] ia, ib;
    assign ia = clip51($signed({3'b0, chroma_phase ? qpcav : qpav}) +
                       9'(cfg_a_off));
    assign ib = clip51($signed({3'b0, chroma_phase ? qpcav : qpav}) +
                       9'(cfg_b_off));
    // boundary strength (8.7.2.1, single-list subset): intra -> 4/3,
    // any nz -> 2, |dmv| >= 4 quarter-pel -> 1, else 0 (no filtering).
    // All-I streams reduce to the old constant 4/3.
    logic [2:0] bs;
    always_comb begin
        logic [1:0] brow, bcol;
        logic p_intra, q_intra, p_nz, q_nz;
        logic signed [15:0] pmx, pmy, qmx, qmy;
        logic signed [16:0] dmx, dmy;
        logic [3:0] qi;
        brow = '0; bcol = '0;
        unique case (st_q)
        S_VL: begin brow = line_q[3:2]; bcol = e_q; end
        S_VC: begin brow = line_q[2:1]; bcol = {e_q[0], 1'b0}; end
        S_HL: begin brow = e_q; bcol = line_q[3:2]; end
        S_HC: begin brow = {e_q[0], 1'b0}; bcol = line_q[2:1]; end
        default: ;
        endcase
        qi = {brow, bcol};
        q_intra = !cur_int;
        q_nz = cur_nz[qi];
        qmx = cur_mvx[qi]; qmy = cur_mvy[qi];
        if (!dir_h) begin
            if (bcol == 2'd0) begin
                p_intra = !lft_int;
                p_nz = lft_nz[{brow, 2'd3}];
                pmx = lft_mvx[{brow, 2'd3}];
                pmy = lft_mvy[{brow, 2'd3}];
            end else begin
                p_intra = !cur_int;
                p_nz = cur_nz[{brow, bcol - 2'd1}];
                pmx = cur_mvx[{brow, bcol - 2'd1}];
                pmy = cur_mvy[{brow, bcol - 2'd1}];
            end
        end else begin
            if (brow == 2'd0) begin
                p_intra = !top_int;
                p_nz = top_nz[bcol];
                pmx = top_mvx[bcol];
                pmy = top_mvy[bcol];
            end else begin
                p_intra = !cur_int;
                p_nz = cur_nz[{brow - 2'd1, bcol}];
                pmx = cur_mvx[{brow - 2'd1, bcol}];
                pmy = cur_mvy[{brow - 2'd1, bcol}];
            end
        end
        dmx = 17'(pmx) - 17'(qmx);
        if (dmx < 0) dmx = -dmx;
        dmy = 17'(pmy) - 17'(qmy);
        if (dmy < 0) dmy = -dmy;
        if (p_intra || q_intra) bs = (e_q == 2'd0) ? 3'd4 : 3'd3;
        else if (p_nz || q_nz) bs = 3'd2;
        else if (dmx >= 17'sd4 || dmy >= 17'sd4) bs = 3'd1;
        else bs = 3'd0;
    end
    logic [4:0] tc0;
    assign tc0 = (bs != 3'd0 && bs < 3'd4) ? dbf_tc0(ia, 2'(bs - 3'd1))
                                           : 5'd0;

    // ---- sample gather (p3..p0 q0..q3 for the current line) ----
    logic [7:0] smp [8];
    always_comb begin
        int e4, ln;
        e4 = int'(e_q) * 4;
        ln = int'(line_q);
        for (int i = 0; i < 8; i++) smp[i] = '0;
        unique case (st_q)
        S_VL: begin
            for (int i = 0; i < 8; i++) begin
                int x;
                x = e4 - 4 + i;
                smp[i] = (x < 0) ? lft_y[ln * 16 + 16 + x]
                                 : cur_y[ln * 16 + x];
            end
        end
        S_VC: begin
            for (int i = 0; i < 8; i++) begin
                int x;
                x = e4 - 4 + i;
                if (comp_q)
                    smp[i] = (x < 0) ? lft_v[ln * 8 + 8 + x]
                                     : cur_v[ln * 8 + x];
                else
                    smp[i] = (x < 0) ? lft_u[ln * 8 + 8 + x]
                                     : cur_u[ln * 8 + x];
            end
        end
        S_HL: begin
            for (int i = 0; i < 8; i++) begin
                int y;
                y = e4 - 4 + i;
                smp[i] = (y < 0) ? top_y_q[4 + y][ln]
                                 : cur_y[y * 16 + ln];
            end
        end
        S_HC: begin
            for (int i = 0; i < 8; i++) begin
                int y;
                y = e4 - 4 + i;
                if (comp_q)
                    smp[i] = (y < 0) ? top_v_q[4 + y][ln]
                                     : cur_v[y * 8 + ln];
                else
                    smp[i] = (y < 0) ? top_u_q[4 + y][ln]
                                     : cur_u[y * 8 + ln];
            end
        end
        default: ;
        endcase
    end

    logic [7:0] o_p2, o_p1, o_p0, o_q0, o_q1, o_q2;
    deblock_edge u_edge (
        .p3(smp[0]), .p2(smp[1]), .p1(smp[2]), .p0(smp[3]),
        .q0(smp[4]), .q1(smp[5]), .q2(smp[6]), .q3(smp[7]),
        .alpha(dbf_alpha(ia)), .beta(dbf_beta(ib)),
        .bs(bs), .tc0(tc0), .chroma(chroma_phase),
        .o_p2(o_p2), .o_p1(o_p1), .o_p0(o_p0),
        .o_q0(o_q0), .o_q1(o_q1), .o_q2(o_q2)
    );

    // skip cross-MB edge at the picture border; bypass skips everything
    logic skip_v0, skip_h0;
    assign skip_v0 = !lft_valid || !cfg_enable;
    assign skip_h0 = !row_vld[cur_x] || !cfg_enable;

    // emit bookkeeping (out of row_buf[cur_x] / flush column)
    logic [7:0] emit_x;
    assign emit_x = (st_q == S_FLUSH_COL) ? fl_x : cur_x;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            dir_h <= 1'b0;
            e_q <= '0; line_q <= '0; comp_q <= 1'b0; emit_q <= '0;
            lft_valid <= 1'b0;
            cur_qp <= '0; lft_qp <= '0;
            cur_x <= '0; cur_yc <= '0;
            fl_x <= '0;
            out_valid <= 1'b0;
            row_vld <= '0;
        end else begin
            out_valid <= 1'b0;

            unique case (st_q)
            S_IDLE: begin
                if (flush) begin
                    fl_x <= '0;
                    emit_q <= '0;
                    st_q <= S_FLUSH_COL;
                end else if (mb_push) begin
                    for (int i = 0; i < 256; i++) cur_y[i] <= in_y[i];
                    for (int i = 0; i < 64; i++) begin
                        cur_u[i] <= in_u[i];
                        cur_v[i] <= in_v[i];
                    end
                    cur_qp <= mb_qp;
                    cur_int <= mb_inter;
                    cur_nz <= mb_nz;
                    for (int i = 0; i < 16; i++) begin
                        cur_mvx[i] <= mb_mvx[i];
                        cur_mvy[i] <= mb_mvy[i];
                    end
                    cur_x <= mb_x;
                    cur_yc <= mb_y;
                    if (mb_x == 8'd0) lft_valid <= 1'b0;
                    dir_h <= 1'b0;
                    e_q <= '0;
                    line_q <= '0;
                    st_q <= S_VL;
                end
            end

            S_VL: begin
                if (cfg_enable && !(e_q == 0 && skip_v0)) begin if (bs != 3'd0) begin
                    int e4, ln;
                    e4 = int'(e_q) * 4;
                    ln = int'(line_q);
                    // writeback p2..q2 across the boundary split
                    for (int i = 1; i < 7; i++) begin
                        int x;
                        logic [7:0] v;
                        x = e4 - 4 + i;
                        unique case (i)
                            1: v = o_p2;
                            2: v = o_p1;
                            3: v = o_p0;
                            4: v = o_q0;
                            5: v = o_q1;
                            default: v = o_q2;
                        endcase
                        if (x < 0) lft_y[ln * 16 + 16 + x] <= v;
                        else cur_y[ln * 16 + x] <= v;
                    end
                end end
                if ((e_q == 0 && skip_v0) || line_q == 5'd15) begin
                    line_q <= '0;
                    if (e_q == 2'd3) begin
                        e_q <= '0;
                        comp_q <= 1'b0;
                        st_q <= S_VC;
                    end else e_q <= e_q + 2'd1;
                end else line_q <= line_q + 5'd1;
            end

            S_VC: begin
                if (cfg_enable && !(e_q == 0 && skip_v0)) begin if (bs != 3'd0) begin
                    int e4, ln;
                    e4 = int'(e_q) * 4;
                    ln = int'(line_q);
                    for (int i = 2; i < 6; i++) begin
                        int x;
                        logic [7:0] v;
                        x = e4 - 4 + i;
                        unique case (i)
                            2: v = o_p1;
                            3: v = o_p0;
                            4: v = o_q0;
                            default: v = o_q1;
                        endcase
                        if (x < 0) begin
                            if (comp_q) lft_v[ln * 8 + 8 + x] <= v;
                            else lft_u[ln * 8 + 8 + x] <= v;
                        end else begin
                            if (comp_q) cur_v[ln * 8 + x] <= v;
                            else cur_u[ln * 8 + x] <= v;
                        end
                    end
                end end
                if ((e_q == 0 && skip_v0) || line_q == 5'd7) begin
                    line_q <= '0;
                    if (!comp_q) comp_q <= 1'b1;
                    else begin
                        comp_q <= 1'b0;
                        if (e_q == 2'd1) begin
                            e_q <= '0;
                            emit_q <= '0;
                            dir_h <= 1'b1;
                            st_q <= S_H0RD;
                        end else e_q <= e_q + 2'd1;
                    end
                end else line_q <= line_q + 5'd1;
            end

            S_H0RD: begin
                // latch the bottom rows of the MB above (already final
                // on its upper 12 rows; these 4 participate in H0)
                for (int r = 0; r < 4; r++) begin
                    for (int c = 0; c < 16; c++)
                        top_y_q[r][c] <= row_y[{cur_x, 4'b0} +
                                               12'(12 + r)][c*8 +: 8];
                    for (int c = 0; c < 8; c++) begin
                        top_u_q[r][c] <= row_u[{cur_x, 3'b0} +
                                               11'(4 + r)][c*8 +: 8];
                        top_v_q[r][c] <= row_v[{cur_x, 3'b0} +
                                               11'(4 + r)][c*8 +: 8];
                    end
                end
                top_int <= row_mi_rd[0];
                for (int i = 0; i < 4; i++) begin
                    top_nz[i] <= row_mi_rd[1 + i];
                    top_mvx[i] <= row_mi_rd[5  + i*32 +: 16];
                    top_mvy[i] <= row_mi_rd[21 + i*32 +: 16];
                end
                dir_h <= 1'b1;
                e_q <= '0;
                line_q <= '0;
                st_q <= S_HL;
            end

            S_HL: begin
                if (cfg_enable && !(e_q == 0 && skip_h0)) begin if (bs != 3'd0) begin
                    int e4, ln;
                    e4 = int'(e_q) * 4;
                    ln = int'(line_q);
                    for (int i = 1; i < 7; i++) begin
                        int y;
                        logic [7:0] v;
                        y = e4 - 4 + i;
                        unique case (i)
                            1: v = o_p2;
                            2: v = o_p1;
                            3: v = o_p0;
                            4: v = o_q0;
                            5: v = o_q1;
                            default: v = o_q2;
                        endcase
                        if (y < 0) top_y_q[4 + y][ln] <= v;
                        else cur_y[y * 16 + ln] <= v;
                    end
                end end
                if ((e_q == 0 && skip_h0) || line_q == 5'd15) begin
                    line_q <= '0;
                    if (e_q == 2'd3) begin
                        e_q <= '0;
                        comp_q <= 1'b0;
                        st_q <= S_HC;
                    end else e_q <= e_q + 2'd1;
                end else line_q <= line_q + 5'd1;
            end

            S_HC: begin
                if (cfg_enable && !(e_q == 0 && skip_h0)) begin if (bs != 3'd0) begin
                    int e4, ln;
                    e4 = int'(e_q) * 4;
                    ln = int'(line_q);
                    for (int i = 2; i < 6; i++) begin
                        int y;
                        logic [7:0] v;
                        y = e4 - 4 + i;
                        unique case (i)
                            2: v = o_p1;
                            3: v = o_p0;
                            4: v = o_q0;
                            default: v = o_q1;
                        endcase
                        if (y < 0) begin
                            if (comp_q) top_v_q[4 + y][ln] <= v;
                            else top_u_q[4 + y][ln] <= v;
                        end else begin
                            if (comp_q) cur_v[y * 8 + ln] <= v;
                            else cur_u[y * 8 + ln] <= v;
                        end
                    end
                end end
                if ((e_q == 0 && skip_h0) || line_q == 5'd7) begin
                    line_q <= '0;
                    if (!comp_q) comp_q <= 1'b1;
                    else begin
                        comp_q <= 1'b0;
                        if (e_q == 2'd1) begin
                            e_q <= '0;
                            emit_q <= '0;
                            st_q <= S_WB;
                        end else e_q <= e_q + 2'd1;
                    end
                end else line_q <= line_q + 5'd1;
            end

            S_WB: begin
                // write the H0-modified bottom rows back, then emit
                for (int r = 0; r < 4; r++) begin
                    logic [127:0] wy;
                    logic [63:0] wu, wv;
                    for (int c = 0; c < 16; c++)
                        wy[c*8 +: 8] = top_y_q[r][c];
                    for (int c = 0; c < 8; c++) begin
                        wu[c*8 +: 8] = top_u_q[r][c];
                        wv[c*8 +: 8] = top_v_q[r][c];
                    end
                    row_y[{cur_x, 4'b0} + 12'(12 + r)] <= wy;
                    row_u[{cur_x, 3'b0} + 11'(4 + r)] <= wu;
                    row_v[{cur_x, 3'b0} + 11'(4 + r)] <= wv;
                end
                emit_q <= '0;
                st_q <= row_vld[cur_x] ? S_EMIT : S_STORE;
            end

            S_EMIT: begin
                // stream MB(cur_x, cur_yc-1): 16 Y rows then 8 U + 8 V
                out_valid <= 1'b1;
                out_mbx <= cur_x;
                out_mby <= cur_yc - 8'd1;
                if (emit_q < 5'd16) begin
                    out_plane <= 2'd0;
                    out_row <= 4'(emit_q);
                    out_data <= row_y[{cur_x, 4'b0} + 12'(emit_q)];
                end else if (emit_q < 5'd24) begin
                    out_plane <= 2'd1;
                    out_row <= 4'(emit_q - 5'd16);
                    out_data <= {64'b0,
                                 row_u[{cur_x, 3'b0} + 11'(emit_q - 5'd16)]};
                end else begin
                    out_plane <= 2'd2;
                    out_row <= 4'(emit_q - 5'd24);
                    out_data <= {64'b0,
                                 row_v[{cur_x, 3'b0} + 11'(emit_q - 5'd24)]};
                end
                if (emit_q == 5'd31) begin
                    emit_q <= '0;
                    st_q <= S_STORE;
                end else emit_q <= emit_q + 5'd1;
            end

            S_STORE: begin
                // left MB (right-filtered by our V0) moves into row_buf;
                // the current MB becomes the new left neighbor
                if (lft_valid) begin
                    if (emit_q < 5'd16) begin
                        logic [127:0] w;
                        for (int i = 0; i < 16; i++)
                            w[i*8 +: 8] = lft_y[int'(emit_q) * 16 + i];
                        row_y[{cur_x - 8'd1, 4'b0} + 12'(emit_q)] <= w;
                        emit_q <= emit_q + 5'd1;
                    end else if (emit_q < 5'd24) begin
                        logic [63:0] wu, wv;
                        for (int i = 0; i < 8; i++) begin
                            wu[i*8 +: 8] = lft_u[(int'(emit_q) - 16) * 8 + i];
                            wv[i*8 +: 8] = lft_v[(int'(emit_q) - 16) * 8 + i];
                        end
                        row_u[{cur_x - 8'd1, 3'b0} + 11'(emit_q - 5'd16)] <= wu;
                        row_v[{cur_x - 8'd1, 3'b0} + 11'(emit_q - 5'd16)] <= wv;
                        emit_q <= emit_q + 5'd1;
                    end else begin
                        row_qp[cur_x - 8'd1] <= lft_qp;
                        row_mi[cur_x - 8'd1] <= lft_mi_pack;
                        row_vld[cur_x - 8'd1] <= 1'b1;
                        emit_q <= '0;
                        st_q <= S_SHIFT;
                    end
                end else begin
                    emit_q <= '0;
                    st_q <= S_SHIFT;
                end
            end

            S_SHIFT: begin
                for (int i = 0; i < 256; i++) lft_y[i] <= cur_y[i];
                for (int i = 0; i < 64; i++) begin
                    lft_u[i] <= cur_u[i];
                    lft_v[i] <= cur_v[i];
                end
                lft_qp <= cur_qp;
                lft_int <= cur_int;
                lft_nz <= cur_nz;
                for (int i = 0; i < 16; i++) begin
                    lft_mvx[i] <= cur_mvx[i];
                    lft_mvy[i] <= cur_mvy[i];
                end
                lft_valid <= 1'b1;
                // row end: the rightmost MB also enters the row buffer
                if (cur_x + 8'd1 == cfg_mb_w) begin
                    emit_q <= '0;
                    st_q <= S_ROWEND;
                end else begin
                    st_q <= S_IDLE;
                end
            end

            // rightmost MB of the row: store CUR (now in lft after shift)
            S_ROWEND: begin
                if (emit_q < 5'd16) begin
                    logic [127:0] w;
                    for (int i = 0; i < 16; i++)
                        w[i*8 +: 8] = lft_y[int'(emit_q) * 16 + i];
                    row_y[{cur_x, 4'b0} + 12'(emit_q)] <= w;
                    emit_q <= emit_q + 5'd1;
                end else if (emit_q < 5'd24) begin
                    logic [63:0] wu, wv;
                    for (int i = 0; i < 8; i++) begin
                        wu[i*8 +: 8] = lft_u[(int'(emit_q) - 16) * 8 + i];
                        wv[i*8 +: 8] = lft_v[(int'(emit_q) - 16) * 8 + i];
                    end
                    row_u[{cur_x, 3'b0} + 11'(emit_q - 5'd16)] <= wu;
                    row_v[{cur_x, 3'b0} + 11'(emit_q - 5'd16)] <= wv;
                    emit_q <= emit_q + 5'd1;
                end else begin
                    row_qp[cur_x] <= lft_qp;
                    row_mi[cur_x] <= lft_mi_pack;
                    row_vld[cur_x] <= 1'b1;
                    lft_valid <= 1'b0;
                    emit_q <= '0;
                    st_q <= S_IDLE;
                end
            end

            S_FLUSH_COL: begin
                // drain the final MB row out of the row buffer
                if (!row_vld[fl_x]) begin
                    if (fl_x + 8'd1 == cfg_mb_w) st_q <= S_DONE;
                    else fl_x <= fl_x + 8'd1;
                end else begin
                    out_valid <= 1'b1;
                    out_mbx <= fl_x;
                    out_mby <= cur_yc;     // last pushed row
                    if (emit_q < 5'd16) begin
                        out_plane <= 2'd0;
                        out_row <= 4'(emit_q);
                        out_data <= row_y[{fl_x, 4'b0} + 12'(emit_q)];
                    end else if (emit_q < 5'd24) begin
                        out_plane <= 2'd1;
                        out_row <= 4'(emit_q - 5'd16);
                        out_data <= {64'b0,
                                     row_u[{fl_x, 3'b0} + 11'(emit_q - 5'd16)]};
                    end else begin
                        out_plane <= 2'd2;
                        out_row <= 4'(emit_q - 5'd24);
                        out_data <= {64'b0,
                                     row_v[{fl_x, 3'b0} + 11'(emit_q - 5'd24)]};
                    end
                    if (emit_q == 5'd31) begin
                        emit_q <= '0;
                        row_vld[fl_x] <= 1'b0;
                        if (fl_x + 8'd1 == cfg_mb_w) st_q <= S_DONE;
                        else fl_x <= fl_x + 8'd1;
                    end else emit_q <= emit_q + 5'd1;
                end
            end

            S_DONE: st_q <= S_DONE;
            default: st_q <= S_IDLE;
            endcase
        end
    end

endmodule
