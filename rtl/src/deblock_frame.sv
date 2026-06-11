// deblock_frame — frame-level deblocking for the baseline-I subset
// (rtl_spec.md R3b). Structure mirrors c_model h264_deblock_frame: MBs
// stream in raster order into an internal frame buffer; once the frame
// is complete an FSM walks MB by MB, vertical edges then horizontal,
// one filtered line per cycle through a deblock_edge instance. All-intra
// bS is fixed: 4 on macroblock edges, 3 inside. Cross-MB edges average
// the neighbor QPs (chroma maps through the QPc LUT per MB first).
// The frame buffer keeps R3b about correctness; the streaming line-
// buffer variant is the synthesis-stage refactor.
`include "deblock_tables.svh"

module deblock_frame #(
    parameter int MAX_W = 320,
    parameter int MAX_H = 240
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  cfg_mb_w,
    input  logic [7:0]  cfg_mb_h,
    input  logic signed [5:0] cfg_cqp_off,
    input  logic signed [5:0] cfg_a_off,   // slice alpha/beta offsets (x2'd)
    input  logic signed [5:0] cfg_b_off,

    // MB input stream (raster order)
    input  logic        mb_push,
    input  logic [7:0]  mb_x,
    input  logic [7:0]  mb_y,
    input  logic [5:0]  mb_qp,
    input  logic [7:0]  in_y [256],
    input  logic [7:0]  in_u [64],
    input  logic [7:0]  in_v [64],

    input  logic        frame_go,     // all MBs pushed: start filtering
    output logic        frame_done,
    output logic        busy,

    // frame readout (valid after frame_done)
    input  logic [16:0] rd_addr,      // luma: y*MAX_W+x ; chroma planes below
    input  logic [1:0]  rd_plane,     // 0=Y 1=U 2=V
    output logic [7:0]  rd_data
);

    // frame buffers
    logic [7:0] fy [MAX_W * MAX_H];
    logic [7:0] fu [(MAX_W/2) * (MAX_H/2)];
    logic [7:0] fv [(MAX_W/2) * (MAX_H/2)];
    logic [5:0] qmap [(MAX_W/16) * (MAX_H/16)];

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

    // ---- filtering FSM ----
    typedef enum logic [2:0] {
        S_IDLE, S_LUMA, S_CHROMA, S_NEXT, S_DONE
    } state_e;
    state_e st_q;
    logic [7:0] mbx_q, mby_q;
    logic       dir_q;                 // 0 vertical, 1 horizontal
    logic [1:0] e_q;                   // edge index (luma 0..3, chroma 0..1)
    logic [4:0] line_q;                // line within edge
    logic       comp_q;

    // per-edge derived params
    logic [5:0] qp_cur, qp_nbr, qpav;
    logic [5:0] qpc_cur, qpc_nbr, qpcav;
    always_comb begin
        logic [8:0] s;
        qp_cur = qmap[mby_q * (MAX_W/16) + mbx_q];
        qp_nbr = (dir_q == 0)
                   ? ((mbx_q != 0) ? qmap[mby_q * (MAX_W/16) + mbx_q - 1]
                                   : qp_cur)
                   : ((mby_q != 0) ? qmap[(mby_q - 1) * (MAX_W/16) + mbx_q]
                                   : qp_cur);
        s = {3'b0, qp_cur} + {3'b0, qp_nbr} + 9'd1;
        qpav = (e_q == 0) ? 6'(s >> 1) : qp_cur;
        qpc_cur = chroma_qp(clip51($signed({3'b0, qp_cur}) +
                                   9'(cfg_cqp_off)));
        qpc_nbr = chroma_qp(clip51($signed({3'b0, qp_nbr}) +
                                   9'(cfg_cqp_off)));
        s = {3'b0, qpc_cur} + {3'b0, qpc_nbr} + 9'd1;
        qpcav = (e_q == 0) ? 6'(s >> 1) : qpc_cur;
    end

    logic [5:0] ia, ib;
    logic [5:0] qsel;
    assign qsel = (st_q == S_CHROMA) ? qpcav : qpav;
    assign ia = clip51($signed({3'b0, qsel}) + 9'(cfg_a_off));
    assign ib = clip51($signed({3'b0, qsel}) + 9'(cfg_b_off));

    logic [2:0] bs;
    assign bs = (e_q == 0) ? 3'd4 : 3'd3;
    logic [4:0] tc0;
    assign tc0 = (bs < 3'd4) ? dbf_tc0(ia, 2'(bs - 3'd1)) : 5'd0;

    // ---- line sample gather / scatter (combinational addressing) ----
    // luma vertical: edge x = mbx*16 + e*4, line y = mby*16 + line_q
    // luma horizontal: edge y = mby*16 + e*4, column x = mbx*16 + line_q
    logic [16:0] base_l [8];           // p3..q3 luma addresses
    logic [16:0] base_c [8];           // chroma addresses
    always_comb begin
        int ex, ey, ln;
        ln = int'(line_q);
        if (st_q == S_LUMA) begin
            if (dir_q == 0) begin
                ex = int'(mbx_q) * 16 + int'(e_q) * 4;
                ey = int'(mby_q) * 16 + ln;
                for (int i = 0; i < 8; i++)
                    base_l[i] = 17'((ey) * MAX_W + ex - 4 + i);
            end else begin
                ey = int'(mby_q) * 16 + int'(e_q) * 4;
                ex = int'(mbx_q) * 16 + ln;
                for (int i = 0; i < 8; i++)
                    base_l[i] = 17'((ey - 4 + i) * MAX_W + ex);
            end
            for (int i = 0; i < 8; i++) base_c[i] = '0;
        end else begin
            if (dir_q == 0) begin
                ex = int'(mbx_q) * 8 + int'(e_q) * 4;
                ey = int'(mby_q) * 8 + ln;
                for (int i = 0; i < 8; i++)
                    base_c[i] = 17'((ey) * (MAX_W/2) + ex - 4 + i);
            end else begin
                ey = int'(mby_q) * 8 + int'(e_q) * 4;
                ex = int'(mbx_q) * 8 + ln;
                for (int i = 0; i < 8; i++)
                    base_c[i] = 17'((ey - 4 + i) * (MAX_W/2) + ex);
            end
            for (int i = 0; i < 8; i++) base_l[i] = '0;
        end
    end

    logic [7:0] smp [8];
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            if (st_q == S_LUMA) smp[i] = fy[base_l[i]];
            else smp[i] = comp_q ? fv[base_c[i]] : fu[base_c[i]];
        end
    end

    logic [7:0] o_p2, o_p1, o_p0, o_q0, o_q1, o_q2;
    deblock_edge u_edge (
        .p3(smp[0]), .p2(smp[1]), .p1(smp[2]), .p0(smp[3]),
        .q0(smp[4]), .q1(smp[5]), .q2(smp[6]), .q3(smp[7]),
        .alpha(dbf_alpha(ia)), .beta(dbf_beta(ib)),
        .bs(bs), .tc0(tc0), .chroma(st_q == S_CHROMA),
        .o_p2(o_p2), .o_p1(o_p1), .o_p0(o_p0),
        .o_q0(o_q0), .o_q1(o_q1), .o_q2(o_q2)
    );

    // skip rules: cross-MB edge at picture border
    logic skip_edge;
    assign skip_edge = (e_q == 0) &&
                       ((dir_q == 0) ? (mbx_q == 0) : (mby_q == 0));

    assign busy = (st_q != S_IDLE) && (st_q != S_DONE);
    assign frame_done = (st_q == S_DONE);

    // readout
    always_comb begin
        unique case (rd_plane)
            2'd0: rd_data = fy[rd_addr];
            2'd1: rd_data = fu[rd_addr];
            2'd2: rd_data = fv[rd_addr];
            default: rd_data = '0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            mbx_q <= '0; mby_q <= '0;
            dir_q <= 1'b0; e_q <= '0; line_q <= '0; comp_q <= 1'b0;
        end else begin
            // MB intake any time before frame_go
            if (mb_push) begin
                for (int yy = 0; yy < 16; yy++)
                    for (int xx = 0; xx < 16; xx++)
                        fy[(int'(mb_y)*16 + yy) * MAX_W +
                           int'(mb_x)*16 + xx] <= in_y[yy*16 + xx];
                for (int yy = 0; yy < 8; yy++)
                    for (int xx = 0; xx < 8; xx++) begin
                        fu[(int'(mb_y)*8 + yy) * (MAX_W/2) +
                           int'(mb_x)*8 + xx] <= in_u[yy*8 + xx];
                        fv[(int'(mb_y)*8 + yy) * (MAX_W/2) +
                           int'(mb_x)*8 + xx] <= in_v[yy*8 + xx];
                    end
                qmap[int'(mb_y) * (MAX_W/16) + int'(mb_x)] <= mb_qp;
            end

            unique case (st_q)
            S_IDLE: if (frame_go) begin
                mbx_q <= '0; mby_q <= '0;
                dir_q <= 1'b0; e_q <= '0; line_q <= '0;
                st_q <= S_LUMA;
            end

            S_LUMA: begin
                if (!skip_edge) begin
                    fy[base_l[1]] <= o_p2;
                    fy[base_l[2]] <= o_p1;
                    fy[base_l[3]] <= o_p0;
                    fy[base_l[4]] <= o_q0;
                    fy[base_l[5]] <= o_q1;
                    fy[base_l[6]] <= o_q2;
                end
                if (skip_edge || line_q == 5'd15) begin
                    line_q <= '0;
                    if (e_q == 2'd3) begin
                        e_q <= '0;
                        comp_q <= 1'b0;
                        st_q <= S_CHROMA;
                    end else begin
                        e_q <= e_q + 2'd1;
                    end
                end else begin
                    line_q <= line_q + 5'd1;
                end
            end

            S_CHROMA: begin
                if (!skip_edge) begin
                    if (comp_q) begin
                        fv[base_c[2]] <= o_p1;
                        fv[base_c[3]] <= o_p0;
                        fv[base_c[4]] <= o_q0;
                        fv[base_c[5]] <= o_q1;
                    end else begin
                        fu[base_c[2]] <= o_p1;
                        fu[base_c[3]] <= o_p0;
                        fu[base_c[4]] <= o_q0;
                        fu[base_c[5]] <= o_q1;
                    end
                end
                if (skip_edge || line_q == 5'd7) begin
                    line_q <= '0;
                    if (!comp_q) begin
                        comp_q <= 1'b1;
                    end else begin
                        comp_q <= 1'b0;
                        if (e_q == 2'd1) begin
                            e_q <= '0;
                            if (dir_q == 1'b0) begin
                                dir_q <= 1'b1;
                                st_q <= S_LUMA;
                            end else begin
                                dir_q <= 1'b0;
                                st_q <= S_NEXT;
                            end
                        end else begin
                            e_q <= e_q + 2'd1;
                        end
                    end
                end else begin
                    line_q <= line_q + 5'd1;
                end
            end

            S_NEXT: begin
                if (mbx_q + 8'd1 == cfg_mb_w) begin
                    mbx_q <= '0;
                    if (mby_q + 8'd1 == cfg_mb_h) st_q <= S_DONE;
                    else begin
                        mby_q <= mby_q + 8'd1;
                        st_q <= S_LUMA;
                    end
                end else begin
                    mbx_q <= mbx_q + 8'd1;
                    st_q <= S_LUMA;
                end
            end

            S_DONE: st_q <= S_DONE;
            default: st_q <= S_IDLE;
            endcase
        end
    end

endmodule
