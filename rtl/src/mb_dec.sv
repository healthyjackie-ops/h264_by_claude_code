// mb_dec — baseline-I CAVLC macroblock layer (rtl_spec.md R1c).
//
// Walks slice_data MB by MB: mb_type, intra-4x4 mode prediction (min of
// left/top with line buffers), chroma mode, CBP (intra table / I16
// implied), the qp chain, and the full residual sequence through a
// cavlc_block instance with nC derived from nz line buffers. Output is
// the coefficient-layer contract of the C model's H264_RTL_DUMP record:
// a header pulse per MB plus raster-order coefficient writes tagged by
// block index (0..15 luma, 16 luma DC, 17/18 chroma DC, 19..26 chroma
// AC in component-major order). I_PCM is out of subset and errors.
`include "cavlc_tables.svh"

module mb_dec #(
    parameter int MAX_MBW = 120        // <=1080p
)(
    input  logic        clk,
    input  logic        rst_n,

    // configuration (held stable while running)
    input  logic [7:0]  cfg_mb_w,
    input  logic [7:0]  cfg_mb_h,
    input  logic [5:0]  cfg_qp,        // SliceQPy
    input  logic        cfg_is_p,      // P slice (P-R3b)

    input  logic        start,         // begin slice_data (bitreader primed)

    // bitreader
    output logic        req_valid,
    output logic [4:0]  req_bits,
    input  logic        req_ready,
    input  logic [23:0] show,
    input  logic [6:0]  avail,

    // cavlc_block residual engine
    output logic        blk_start,
    output logic        blk_chroma_dc,
    output logic [1:0]  blk_nc_class,
    output logic [4:0]  blk_maxc,
    input  logic        blk_busy,
    input  logic        blk_done,
    input  logic        blk_err,
    input  logic [4:0]  blk_tc,
    input  logic        blk_coef_we,
    input  logic [3:0]  blk_coef_addr,
    input  logic signed [15:0] blk_coef_data,

    // P-syntax output stream: skip/type/sub on the header pulse, mvd
    // pairs as they parse (consumer: MV prediction / golden compare)
    output logic        mb_skip,
    output logic        mb_inter,
    output logic [2:0]  mb_ptype,      // 0..4 when inter
    output logic [7:0]  mb_sub,        // 4 x 2b sub types (P_8x8)
    output logic        mvd_valid,
    output logic signed [15:0] mvd_x,
    output logic signed [15:0] mvd_y,
    output logic        skip_go,       // P_Skip MB derivation beat
    output logic [15:0] mb_nz,         // 4x4 luma nz bitmap, raster

    // per-MB header pulse
    output logic        mb_valid,
    output logic [7:0]  mb_x,
    output logic [7:0]  mb_y,
    output logic        mb_i16,        // 0 = I_4x4, 1 = I_16x16
    output logic [5:0]  mb_cbp,        // chroma<<4 | luma
    output logic [5:0]  mb_qp,
    output logic [1:0]  mb_i16_mode,
    output logic [1:0]  mb_cmode,
    output logic [63:0] mb_i4m,        // 16 x 4-bit modes, z-scan order

    // raster-order coefficient stream
    output logic        coef_we,
    output logic [4:0]  coef_blk,
    output logic [3:0]  coef_addr,
    output logic signed [15:0] coef_data,

    output logic        slice_done,
    output logic        err,

    // reconstruction handshake: after the header pulse, parsing stalls
    // only until the consumer ACCEPTS the header (R4f pipelining: the
    // next MB parses while the previous reconstructs); tie high unused
    input  logic        rec_done
);

    // z-scan position of 4x4 block k within the MB
    function automatic logic [1:0] zsx(input logic [3:0] k);
        return {k[2], k[0]};
    endfunction
    function automatic logic [1:0] zsy(input logic [3:0] k);
        return {k[3], k[1]};
    endfunction
    // inverse: z-scan index of position (bx,by)
    function automatic logic [3:0] zidx(input logic [1:0] bx,
                                        input logic [1:0] by);
        return {by[1], bx[1], by[0], bx[0]};
    endfunction

    typedef enum logic [4:0] {
        S_IDLE, S_PRE, S_MBTYPE, S_I4MODE, S_CMODE, S_CBP, S_QPD,
        S_LDC_GO, S_LAC_GO, S_RES_WAIT, S_CDC_GO, S_CAC_GO,
        S_EMIT, S_WAIT_REC, S_DONE, S_ERR,
        S_SKIPRUN, S_PSUB, S_PMVD_X, S_PMVD_Y, S_PSKIP_FILL
    } state_e;
    state_e st_q, ret_q;               // ret_q: state after S_RES_WAIT

    logic [7:0] mbx_q, mby_q;
    logic [15:0] skip_q;               // remaining skip MBs
    logic        coded_next_q;         // next MB is the coded MB after a
                                       // skip run (no mb_skip_run field)
    logic        skip_rd_q;            // skip_run consumed this slice pos
    logic        inter_q;
    logic [2:0]  ptype_q;
    logic [7:0]  sub_q;                // packed 4 x 2b
    logic [2:0]  part_q;               // partition / sub-block counter
    logic [4:0]  nmvd_q;
    logic signed [15:0] mvdx_q;
    logic        skip_flag_q;
    logic       i16_q;
    logic [1:0] i16m_q;
    logic [1:0] cmode_q;
    logic [5:0] cbp_q;                 // chroma<<4 | luma
    logic [5:0] qp_q;
    logic [3:0] k_q;                   // 4x4 / chroma block counter
    logic [1:0] comp_q;                // chroma component
    logic [3:0] i4m_q [16];            // modes, z-scan
    logic [4:0] nz_q  [16];            // luma nz, z-scan position

    // neighbor line buffer, ONE word per MB column (R4h merge): the
    // four small arrays packed into 56 bits so the memory tiles onto a
    // single fakeram macro instead of three flop register files.
    // Layout: [15:0] i4 modes, [35:16] nz luma, [45:36] nzc Cb,
    // [55:46] nzc Cr.
    logic [55:0] nbr_top [MAX_MBW];
    logic [15:0] i4t_q;                // prefetched upper-row words
    logic [19:0] nzlt_q;
    logic [9:0]  nzct_q [2];
    wire [55:0] nbr_w = nbr_top[mbx_q];
    logic [3:0] i4_left  [4];
    logic [4:0] nzl_left [4];
    logic [4:0] nzc_left [2][2];
    logic       have_left;             // mbx>0
    logic [4:0] nzc_q [2][4];          // chroma nz this MB

    // single-cycle syntax (R4c): requests combinational off the state,
    // gated on a full window like cavlc_block
    logic win_ok;
    assign win_ok = (avail >= 7'd24);

    always_comb begin
        req_valid = 1'b0;
        req_bits = '0;
        if (win_ok) unique case (st_q)
        S_MBTYPE, S_SKIPRUN, S_PSUB, S_PMVD_X, S_PMVD_Y: if (eg_ok) begin
            req_valid = 1'b1;
            req_bits = eg_len;
        end
        S_I4MODE: begin
            req_valid = 1'b1;
            req_bits = show[23] ? 5'd1 : 5'd4;
        end
        S_CMODE: if (eg_ok && eg_ue <= 12'd3) begin
            req_valid = 1'b1;
            req_bits = eg_len;
        end
        S_CBP: if (eg_ok && eg_ue <= 12'd47) begin
            req_valid = 1'b1;
            req_bits = eg_len;
        end
        S_QPD: if (eg_ok) begin
            req_valid = 1'b1;
            req_bits = eg_len;
        end
        default: ;
        endcase
    end

    // exp-golomb view
    logic [11:0]        eg_ue;
    logic signed [11:0] eg_se;
    logic [4:0]         eg_len;
    logic               eg_ok;
    expgolomb u_eg (.show(show), .ue_val(eg_ue), .se_val(eg_se),
                    .len(eg_len), .ok(eg_ok));

    // ---- i4 mode prediction for block k_q ----
    logic [3:0] predA, predB;
    logic       availA, availB;
    always_comb begin
        logic [1:0] bx, by;
        bx = zsx(k_q);
        by = zsy(k_q);
        availA = (bx != 0) || have_left;
        availB = (by != 0) || (mby_q != 0);
        if (bx != 0) begin
            predA = i4m_q[zidx(bx - 2'd1, by)];
        end else begin
            predA = i4_left[by];
        end
        if (by != 0) begin
            predB = i4m_q[zidx(bx, by - 2'd1)];
        end else begin
            predB = i4t_q[bx * 4 +: 4];
        end
    end
    logic [3:0] i4_pred;
    assign i4_pred = (!availA || !availB) ? 4'd2
                     : (predA < predB ? predA : predB);

    // ---- nC for the current residual block ----
    logic [4:0] nc_l;
    always_comb begin
        logic [1:0] bx, by;
        logic [4:0] nA, nB;
        logic       aA, aB;
        bx = zsx(k_q);
        by = zsy(k_q);
        aA = (bx != 0) || have_left;
        aB = (by != 0) || (mby_q != 0);
        nA = (bx != 0) ? nz_q[zidx(bx - 2'd1, by)] : nzl_left[by];
        nB = (by != 0) ? nz_q[zidx(bx, by - 2'd1)]
                       : nzlt_q[bx * 5 +: 5];
        if (aA && aB)      nc_l = 5'(({1'b0, nA} + {1'b0, nB} + 6'd1) >> 1);
        else if (aA)       nc_l = nA;
        else if (aB)       nc_l = nB;
        else               nc_l = '0;
    end

    logic [4:0] nc_c;
    always_comb begin
        logic cx, cy;
        logic [4:0] nA, nB;
        logic aA, aB;
        cx = k_q[0];
        cy = k_q[1];
        aA = cx || have_left;
        aB = cy || (mby_q != 0);
        nA = cx ? nzc_q[comp_q][{cy, 1'b0}] : nzc_left[comp_q][cy];
        nB = cy ? nzc_q[comp_q][{1'b0, cx}]
                : nzct_q[comp_q][cx * 5 +: 5];
        // raster idx: {cy,cx}; A=(cx-1,cy) -> {cy,0} when cx==1; B={0,cx}
        if (aA && aB)      nc_c = 5'(({1'b0, nA} + {1'b0, nB} + 6'd1) >> 1);
        else if (aA)       nc_c = nA;
        else if (aB)       nc_c = nB;
        else               nc_c = '0;
    end

    function automatic logic [1:0] nc_class_of(input logic [4:0] nc);
        if (nc < 5'd2) return 2'd0;
        else if (nc < 5'd4) return 2'd1;
        else if (nc < 5'd8) return 2'd2;
        else return 2'd3;
    endfunction

    // residual forwarding: de-zigzag (AC tables shift by one)
    logic ac15_q;                      // current block uses maxc 15
    assign coef_we   = blk_coef_we && (st_q == S_RES_WAIT);
    assign coef_blk  = cur_blk_q;
    assign coef_addr = blk_chroma_dc ? blk_coef_addr
                       : zz4(ac15_q ? blk_coef_addr + 4'd1 : blk_coef_addr);
    assign coef_data = blk_coef_data;
    logic [4:0] cur_blk_q;

    assign mb_x = mbx_q;
    assign mb_y = mby_q;
    assign mb_i16 = i16_q;
    assign mb_cbp = cbp_q;
    assign mb_qp = qp_q;
    assign mb_i16_mode = i16m_q;
    assign mb_cmode = cmode_q;
    always_comb begin
        for (int i = 0; i < 16; i++) mb_i4m[i*4 +: 4] = i4m_q[i];
    end
    assign mb_valid = (st_q == S_EMIT) || (st_q == S_WAIT_REC);
    assign mb_skip = skip_flag_q;
    assign skip_go = (st_q == S_PSKIP_FILL);
    always_comb
        for (int r = 0; r < 16; r++)
            mb_nz[r] = (nz_q[zidx(2'(r & 3), 2'(r >> 2))] != 5'd0);
    assign mvd_valid = (st_q == S_PMVD_Y) && win_ok && eg_ok;
    assign mvd_x = mvdx_q;
    assign mvd_y = 16'(eg_se);
    assign mb_inter = inter_q;
    assign mb_ptype = ptype_q;
    assign mb_sub = sub_q;
    assign slice_done = (st_q == S_DONE);
    assign err = (st_q == S_ERR);

    // luma cbp bit for 8x8 group of z-block k
    function automatic logic cbp_l_bit(input logic [3:0] k);
        return cbp_q[{k[3], k[2]}];
    endfunction

`ifdef MB_DBG
    always_ff @(posedge clk) begin
        if (st_q == S_RES_WAIT && blk_done)
            $display("BLKDONE mb=(%0d,%0d) blk=%0d tc=%0d",
                     mbx_q, mby_q, cur_blk_q, blk_tc);
        if (st_q != S_IDLE && st_q != S_RES_WAIT)
            $display("MBDBG st=%0d mb=(%0d,%0d) k=%0d show=%06x rv=%b ue=%0d cbp=%02x ncl=%0d",
                     st_q, mbx_q, mby_q, k_q, show, req_valid, eg_ue,
                     cbp_q, nc_l);
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            ret_q <= S_IDLE;
            blk_start <= 1'b0;
            blk_chroma_dc <= 1'b0;
            blk_nc_class <= '0;
            blk_maxc <= '0;
            mbx_q <= '0; mby_q <= '0;
            i16_q <= 1'b0; i16m_q <= '0; cmode_q <= '0;
            cbp_q <= '0; qp_q <= '0;
            k_q <= '0; comp_q <= '0;
            have_left <= 1'b0;
            ac15_q <= 1'b0;
            cur_blk_q <= '0;
        end else begin
            blk_start <= 1'b0;

            unique case (st_q)
            S_IDLE: if (start) begin
                mbx_q <= '0;
                mby_q <= '0;
                qp_q <= cfg_qp;
                have_left <= 1'b0;
                skip_q <= '0;
                coded_next_q <= 1'b0;
                st_q <= S_PRE;
            end

            S_PRE: begin
                i4t_q <= nbr_w[15:0];
                nzlt_q <= nbr_w[35:16];
                nzct_q[0] <= nbr_w[45:36];
                nzct_q[1] <= nbr_w[55:46];
                skip_flag_q <= 1'b0;
                inter_q <= 1'b0;
                ptype_q <= '0;
                sub_q <= '0;
                if (cfg_is_p && skip_q != 16'd0) begin
                    // inside a skip run: this MB is skipped
                    skip_q <= skip_q - 16'd1;
                    if (skip_q == 16'd1) coded_next_q <= 1'b1;
                    skip_flag_q <= 1'b1;
                    inter_q <= 1'b1;
                    st_q <= S_PSKIP_FILL;
                end else begin
                    // the coded MB terminating a skip run carries no
                    // mb_skip_run of its own (7.3.4 do/while shape)
                    st_q <= (cfg_is_p && !coded_next_q) ? S_SKIPRUN
                                                        : S_MBTYPE;
                    coded_next_q <= 1'b0;
                end
            end

            S_SKIPRUN: if (win_ok && eg_ok) begin
                if (eg_ue != 12'd0) begin
                    skip_q <= 12'(eg_ue) - 12'd1;
                    if (eg_ue == 12'd1) coded_next_q <= 1'b1;
                    skip_flag_q <= 1'b1;
                    inter_q <= 1'b1;
                    st_q <= S_PSKIP_FILL;
                end else begin
                    st_q <= S_MBTYPE;
                end
            end

            // skip MB: neighbor state (nz 0, modes DC) then emit
            S_PSKIP_FILL: begin
                for (int k = 0; k < 16; k++) begin
                    i4m_q[k] <= 4'd2;
                    nz_q[k] <= '0;
                end
                nzc_q[0][0] <= '0; nzc_q[0][1] <= '0;
                nzc_q[0][2] <= '0; nzc_q[0][3] <= '0;
                nzc_q[1][0] <= '0; nzc_q[1][1] <= '0;
                nzc_q[1][2] <= '0; nzc_q[1][3] <= '0;
                cbp_q <= '0;
                i16_q <= 1'b0;
                cmode_q <= '0;
                st_q <= S_EMIT;
            end

            S_MBTYPE: if (win_ok) begin
                logic [11:0] eff;
                eff = (cfg_is_p && eg_ue >= 12'd5) ? (eg_ue - 12'd5)
                                                   : eg_ue;
                if (!eg_ok) st_q <= S_ERR;
                else if (cfg_is_p && eg_ue < 12'd5) begin
                    // inter MB: partition shape, then mvds
                    inter_q <= 1'b1;
                    ptype_q <= 3'(eg_ue);
                    i16_q <= 1'b0;
                    for (int i = 0; i < 16; i++) i4m_q[i] <= 4'd2;
                    part_q <= '0;
                    if (eg_ue >= 12'd3) begin  /* P_8x8 / ref0 */
                        nmvd_q <= '0;
                        st_q <= S_PSUB;
                    end else begin
                        nmvd_q <= (eg_ue == 12'd0) ? 5'd1 : 5'd2;
                        st_q <= S_PMVD_X;
                    end
                end
                else begin
                    if (eff == 12'd0) begin
                        i16_q <= 1'b0;
                        i16m_q <= '0;          // dump field is 0 for I_4x4
                        k_q <= '0;
                        st_q <= S_I4MODE;
                    end else if (eff <= 12'd24) begin
                        logic [11:0] m;
                        logic [1:0]  cc;
                        m = eff - 12'd1;
                        cc = 2'((m >> 2) % 12'd3);
                        i16_q <= 1'b1;
                        i16m_q <= 2'(m & 12'd3);
                        cbp_q <= {cc, (m >= 12'd12) ? 4'hF : 4'h0};
                        for (int i = 0; i < 16; i++) i4m_q[i] <= 4'd2;
                        st_q <= S_CMODE;
                    end else begin
                        st_q <= S_ERR;     // I_PCM / invalid: out of subset
                    end
                end
            end

            S_PSUB: if (win_ok) begin
                if (!eg_ok || eg_ue > 12'd3) st_q <= S_ERR;
                else begin
                    logic [4:0] add;
                    sub_q[part_q[1:0]*2 +: 2] <= 2'(eg_ue);
                    add = (eg_ue == 12'd0) ? 5'd1
                        : (eg_ue == 12'd3) ? 5'd4 : 5'd2;
                    nmvd_q <= nmvd_q + add;
                    if (part_q == 3'd3) begin
                        part_q <= '0;
                        st_q <= S_PMVD_X;
                    end else part_q <= part_q + 3'd1;
                end
            end

            S_PMVD_X: if (win_ok) begin
                if (!eg_ok) st_q <= S_ERR;
                else begin
                    mvdx_q <= 16'(eg_se);
                    st_q <= S_PMVD_Y;
                end
            end

            S_PMVD_Y: if (win_ok) begin
                if (!eg_ok) st_q <= S_ERR;
                else begin
                    // mvd pair complete (pulse handled combinationally)
                    nmvd_q <= nmvd_q - 5'd1;
                    st_q <= (nmvd_q == 5'd1) ? S_CBP : S_PMVD_X;
                end
            end

            S_I4MODE: if (win_ok) begin
                logic [3:0] mode;
                if (show[23]) begin            // prev_intra4x4_pred_mode
                    mode = i4_pred;
                end else begin
                    logic [3:0] rem;
                    rem = {1'b0, show[22:20]};
                    mode = (rem < i4_pred) ? rem : rem + 4'd1;
                end
                i4m_q[k_q] <= mode;
                if (k_q == 4'd15) st_q <= S_CMODE;
                k_q <= k_q + 4'd1;
            end

            S_CMODE: if (win_ok) begin
                if (!eg_ok || eg_ue > 12'd3) st_q <= S_ERR;
                else begin
                    cmode_q <= 2'(eg_ue);
                    st_q <= i16_q ? S_QPD : S_CBP;
                end
            end

            S_CBP: if (win_ok) begin
                logic [5:0] cbp;
                cbp = inter_q ? cavlc_inter_cbp(6'(eg_ue))
                              : cavlc_intra_cbp(6'(eg_ue));
                if (!eg_ok || eg_ue > 12'd47 || cbp == 6'd63) st_q <= S_ERR;
                else begin
                    cbp_q <= cbp;
                    if (cbp == 6'd0) begin
                        for (int k = 0; k < 16; k++) nz_q[k] <= '0;
                        for (int k = 0; k < 4; k++) begin
                            nzc_q[0][k[1:0]] <= '0;
                            nzc_q[1][k[1:0]] <= '0;
                        end
                        st_q <= S_EMIT;
                    end else st_q <= S_QPD;
                end
            end

            S_QPD: if (win_ok) begin
                if (!eg_ok) st_q <= S_ERR;
                else begin
                    qp_q <= 6'((13'($signed({1'b0, qp_q})) +
                                13'(eg_se) + 13'd52) % 13'd52);
                    k_q <= '0;
                    st_q <= i16_q ? S_LDC_GO : S_LAC_GO;
                end
            end

            S_LDC_GO: begin
                blk_start <= 1'b1;
                blk_chroma_dc <= 1'b0;
                blk_nc_class <= nc_class_of(nc_l);   // k_q==0: block (0,0)
                blk_maxc <= 5'd16;
                ac15_q <= 1'b0;
                cur_blk_q <= 5'd16;
                ret_q <= S_LAC_GO;
                st_q <= S_RES_WAIT;
            end

            S_LAC_GO: begin
                if (cbp_l_bit(k_q)) begin
                    blk_start <= 1'b1;
                    blk_chroma_dc <= 1'b0;
                    blk_nc_class <= nc_class_of(nc_l);
                    blk_maxc <= i16_q ? 5'd15 : 5'd16;
                    ac15_q <= i16_q;
                    cur_blk_q <= {1'b0, k_q};
                    ret_q <= S_LAC_GO;        // resume here; advance below
                    st_q <= S_RES_WAIT;
                end else begin
                    nz_q[k_q] <= '0;
                    if (k_q == 4'd15) begin
                        k_q <= '0;
                        comp_q <= '0;
                        st_q <= (cbp_q[5:4] != 2'd0) ? S_CDC_GO : S_EMIT;
                    end else begin
                        k_q <= k_q + 4'd1;
                    end
                end
            end

            S_CDC_GO: begin
                blk_start <= 1'b1;
                blk_chroma_dc <= 1'b1;
                blk_nc_class <= '0;
                blk_maxc <= 5'd4;
                ac15_q <= 1'b0;
                cur_blk_q <= 5'd17 + {4'b0, comp_q[0]};
                ret_q <= S_CDC_GO;
                st_q <= S_RES_WAIT;
            end

            S_CAC_GO: begin
                if (cbp_q[5:4] == 2'd2) begin
                    blk_start <= 1'b1;
                    blk_chroma_dc <= 1'b0;
                    blk_nc_class <= nc_class_of(nc_c);
                    blk_maxc <= 5'd15;
                    ac15_q <= 1'b1;
                    cur_blk_q <= 5'd19 + {2'b0, comp_q[0], 2'b0} +
                                 {3'b0, k_q[1:0]};
                    ret_q <= S_CAC_GO;
                    st_q <= S_RES_WAIT;
                end else begin
                    nzc_q[comp_q][k_q[1:0]] <= '0;
                    if (k_q[1:0] == 2'd3) begin
                        k_q <= '0;
                        if (comp_q[0]) st_q <= S_EMIT;
                        comp_q <= comp_q + 2'd1;
                    end else begin
                        k_q <= k_q + 4'd1;
                    end
                end
            end

            S_RES_WAIT: begin
                if (blk_err) st_q <= S_ERR;
                else if (blk_done) begin
                    unique case (ret_q)
                    S_LAC_GO: begin
                        if (cur_blk_q == 5'd16) begin
                            // luma DC done; AC pass starts at k 0
                            k_q <= '0;
                            st_q <= S_LAC_GO;
                        end else begin
                            nz_q[k_q] <= blk_tc;
                            if (k_q == 4'd15) begin
                                k_q <= '0;
                                comp_q <= '0;
                                st_q <= (cbp_q[5:4] != 2'd0) ? S_CDC_GO
                                                             : S_EMIT;
                            end else begin
                                k_q <= k_q + 4'd1;
                                st_q <= S_LAC_GO;
                            end
                        end
                    end
                    S_CDC_GO: begin
                        if (comp_q[0]) begin
                            comp_q <= '0;
                            k_q <= '0;
                            st_q <= (cbp_q[5:4] == 2'd2) ? S_CAC_GO : S_EMIT;
                        end else begin
                            comp_q <= 2'd1;
                            st_q <= S_CDC_GO;
                        end
                    end
                    S_CAC_GO: begin
                        nzc_q[comp_q][k_q[1:0]] <= blk_tc;
                        if (k_q[1:0] == 2'd3) begin
                            k_q <= '0;
                            if (comp_q[0]) st_q <= S_EMIT;
                            else st_q <= S_CAC_GO;
                            comp_q <= comp_q + 2'd1;
                        end else begin
                            k_q <= k_q + 4'd1;
                            st_q <= S_CAC_GO;
                        end
                    end
                    default: st_q <= S_ERR;
                    endcase
                end
            end

            S_EMIT: begin
                // update neighbor state, advance MB
                begin
                    logic [55:0] w;
                    for (int b = 0; b < 4; b++) begin
                        w[b*4 +: 4] = i4m_q[zidx(2'(b), 2'd3)];
                        w[16 + b*5 +: 5] = nz_q[zidx(2'(b), 2'd3)];
                        i4_left[b] <= i4m_q[zidx(2'd3, 2'(b))];
                        nzl_left[b] <= nz_q[zidx(2'd3, 2'(b))];
                    end
                    for (int b = 0; b < 2; b++) begin
                        w[36 + b*5 +: 5] = (cbp_q[5:4] == 2'd2)
                                            ? nzc_q[0][{1'b1, b[0]}] : 5'd0;
                        w[46 + b*5 +: 5] = (cbp_q[5:4] == 2'd2)
                                            ? nzc_q[1][{1'b1, b[0]}] : 5'd0;
                        nzc_left[0][b] <= (cbp_q[5:4] == 2'd2)
                                              ? nzc_q[0][{b[0], 1'b1}] : 5'd0;
                        nzc_left[1][b] <= (cbp_q[5:4] == 2'd2)
                                              ? nzc_q[1][{b[0], 1'b1}] : 5'd0;
                    end
                    nbr_top[mbx_q] <= w;
                end
                // the consumer may accept on this very cycle (it idles
                // while we parse): advance straight through, else hold
                // valid in S_WAIT_REC
                if (rec_done) begin
                    if (mbx_q + 8'd1 == cfg_mb_w) begin
                        have_left <= 1'b0;
                        mbx_q <= '0;
                        if (mby_q + 8'd1 == cfg_mb_h) st_q <= S_DONE;
                        else begin
                            mby_q <= mby_q + 8'd1;
                            st_q <= S_PRE;
                        end
                    end else begin
                        have_left <= 1'b1;
                        mbx_q <= mbx_q + 8'd1;
                        st_q <= S_PRE;
                    end
                end else begin
                    st_q <= S_WAIT_REC;
                end
            end

            // hold the header valid until accepted, then advance
            S_WAIT_REC: if (rec_done) begin
                if (mbx_q + 8'd1 == cfg_mb_w) begin
                    have_left <= 1'b0;
                    mbx_q <= '0;
                    if (mby_q + 8'd1 == cfg_mb_h) st_q <= S_DONE;
                    else begin
                        mby_q <= mby_q + 8'd1;
                        st_q <= S_PRE;
                    end
                end else begin
                    have_left <= 1'b1;
                    mbx_q <= mbx_q + 8'd1;
                    st_q <= S_PRE;
                end
            end

            S_DONE: st_q <= S_IDLE;
            S_ERR:  st_q <= S_ERR;
            default: st_q <= S_ERR;
            endcase
        end
    end

endmodule
