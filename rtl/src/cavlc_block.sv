// cavlc_block — one residual_block() of clause 9.2 as an FSM over the
// bitreader lookahead. Mirrors c_model/src/cavlc.c exactly: coeff_token
// (nC-classed tables / chroma-DC table), trailing-one signs, level
// prefix/suffix with adaptive suffix_length, total_zeros, run_before,
// and high-frequency-first placement. Coefficients stream out through a
// write port in scan order; `tc_out` and `done` close the block.
`include "cavlc_tables.svh"

module cavlc_block (
    input  logic        clk,
    input  logic        rst_n,

    // bitreader
    output logic        req_valid,
    output logic [4:0]  req_bits,
    input  logic        req_ready,
    input  logic [23:0] show,
    input  logic [6:0]  avail,

    // command: maxc 4 (chroma DC), 15 (AC), 16; chroma_dc selects the
    // dedicated token table (C nC == -1); nc_class 0..3 otherwise.
    input  logic        start,
    input  logic        chroma_dc,
    input  logic [1:0]  nc_class,
    input  logic [4:0]  maxc,

    output logic        busy,
    output logic        done,
    output logic [4:0]  tc_out,
    output logic        err,

    // scan-order coefficient write-out (positions 0..maxc-1)
    output logic        coef_we,
    output logic [3:0]  coef_addr,
    output logic signed [15:0] coef_data
);

    typedef enum logic [3:0] {
        S_IDLE, S_TOKEN, S_T1, S_LVL_PFX, S_LVL_SFX, S_TZ, S_RUN, S_DONE,
        S_ERR
    } state_e;
    state_e st_q;

    // single-cycle syntax elements (R4b): requests are combinational off
    // the current state; the bitreader retires them on the same edge the
    // FSM moves, so every state sees an up-to-date window.
    logic win_ok;
    assign win_ok = (avail >= 7'd24);

    always_comb begin
        req_valid = 1'b0;
        req_bits = '0;
        if (win_ok) unique case (st_q)
        S_TOKEN: if (tok[12]) begin
            req_valid = 1'b1;
            req_bits = tok[4:0];
        end
        S_T1: if (i_q < {3'b0, t1_q}) begin
            req_valid = 1'b1;
            req_bits = 5'd1;
        end
        S_LVL_PFX: if (clz < 5'd24) begin
            req_valid = 1'b1;
            req_bits = clz + 5'd1;
        end
        S_LVL_SFX: if (sfx_size != 5'd0) begin
            req_valid = 1'b1;
            req_bits = sfx_size;
        end
        S_TZ: if (tc_q < maxc_q) begin
            if (cdc_q ? ctzl[4] : tzl[8]) begin
                req_valid = 1'b1;
                req_bits = cdc_q ? {3'b0, ctzl[1:0]} : {1'b0, tzl[3:0]};
            end
        end
        S_RUN: begin
            if ((i_q != tc_q - 5'd1) && (zl_q > 5'd0) && runl[8]) begin
                req_valid = 1'b1;
                req_bits = {1'b0, runl[3:0]};
            end
        end
        default: ;
        endcase
    end

    logic [4:0]  tc_q;
    logic [1:0]  t1_q;
    logic [2:0]  sl_q;                 // suffix_length 0..6
    logic [4:0]  i_q;                  // level index
    logic [4:0]  pfx_q;
    logic signed [15:0] level_q [16];
    logic [4:0]  zl_q;                 // zeros_left
    logic signed [5:0] pos_q;          // placement position
    logic [4:0]  run_i_q;
    logic [4:0]  maxc_q;
    logic        cdc_q;
    logic [1:0]  ncc_q;

    // table lookups (combinational over show)
    logic [12:0] tok;
    assign tok = cavlc_coeff_token(cdc_q ? 3'd4 : {1'b0, ncc_q}, show[23:8]);

    logic [8:0] tzl;
    assign tzl = cavlc_total_zeros(4'(tc_q - 5'd1), show[23:15]);
    logic [4:0] ctzl;
    assign ctzl = cavlc_cdc_total_zeros(2'(tc_q - 5'd1), show[23:21]);

    logic [8:0] runl;
    logic [2:0] zl_row;
    assign zl_row = (zl_q < 5'd7) ? 3'(zl_q - 5'd1) : 3'd6;
    assign runl = cavlc_run_before(zl_row, show[23:13]);

    // CLZ over the window for the level prefix (stop at first 1)
    logic [4:0] clz;
    always_comb begin
        clz = 5'd24;
        for (int k = 0; k <= 23; k++) begin
            if (show[23 - k]) begin
                clz = 5'(k);
                break;
            end
        end
    end

    // level suffix size for the current prefix / suffix_length
    logic [4:0] sfx_size;
    always_comb begin
        if (pfx_q == 5'd14 && sl_q == 3'd0)      sfx_size = 5'd4;
        else if (pfx_q >= 5'd15)                 sfx_size = 5'(pfx_q) - 5'd3;
        else                                     sfx_size = {2'b0, sl_q};
    end

    logic signed [15:0] lvl_new;
    logic [15:0] level_code;
    always_comb begin
        logic [15:0 ] lc;
        logic [15:0] sfx;
        lc = {11'b0, (pfx_q < 5'd15) ? pfx_q : 5'd15} << sl_q;
        sfx = 16'(show[23:8] >> (5'd16 - sfx_size));
        if (sl_q > 0 || pfx_q >= 5'd14) lc = lc + sfx;
        if (pfx_q >= 5'd15 && sl_q == 3'd0) lc = lc + 16'd15;
        // pfx>=16 escape growth: + (1<<(pfx-3)) - 4096
        if (pfx_q >= 5'd16) lc = lc + (16'd1 << (pfx_q - 5'd3)) - 16'd4096;
        if (i_q == {3'b0, t1_q} && t1_q < 2'd3) lc = lc + 16'd2;
        level_code = lc;
        lvl_new = lc[0] ? -$signed({1'b0, (lc + 16'd1) >> 1})
                        : $signed({1'b0, (lc + 16'd2) >> 1});
    end

    // adaptive suffix_length update threshold: |level| > 3<<(sl-1)
    logic [15:0] abs_lvl;
    assign abs_lvl = lvl_new[15] ? 16'(-lvl_new) : 16'(lvl_new);

    assign busy = (st_q != S_IDLE) && (st_q != S_DONE) && (st_q != S_ERR);
    assign done = (st_q == S_DONE);
    assign err  = (st_q == S_ERR);
    assign tc_out = tc_q;

`ifdef CAVLC_DBG
    always_ff @(posedge clk) begin
        if (st_q != S_IDLE)
            $display("DBG st=%0d show=%06x rv=%b tc=%0d t1=%0d i=%0d sl=%0d pfx=%0d zl=%0d pos=%0d we=%b addr=%0d data=%0d",
                     st_q, show, req_valid, tc_q, t1_q, i_q, sl_q, pfx_q,
                     zl_q, pos_q, coef_we, coef_addr, $signed(coef_data));
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            coef_we <= 1'b0;
            coef_addr <= '0;
            coef_data <= '0;
            tc_q <= '0; t1_q <= '0; sl_q <= '0; i_q <= '0; pfx_q <= '0;
            zl_q <= '0; pos_q <= '0; run_i_q <= '0; maxc_q <= '0;
            cdc_q <= 1'b0; ncc_q <= '0;
        end else begin
            coef_we <= 1'b0;

            unique case (st_q)
            S_IDLE: if (start) begin
                cdc_q <= chroma_dc;
                ncc_q <= nc_class;
                maxc_q <= maxc;
                tc_q <= '0;
                st_q <= S_TOKEN;
            end

            S_TOKEN: if (win_ok) begin
                if (!tok[12]) begin
                    st_q <= S_ERR;
                end else begin
                    tc_q <= tok[11:7];
                    t1_q <= tok[6:5];
                    if (tok[11:7] == 5'd0) begin
                        st_q <= S_DONE;
                    end else begin
                        sl_q <= (tok[11:7] > 5'd10 && tok[6:5] < 2'd3)
                                    ? 3'd1 : 3'd0;
                        i_q <= '0;
                        st_q <= S_T1;
                    end
                end
            end

            S_T1: if (win_ok) begin
                if (i_q < {3'b0, t1_q}) begin
                    level_q[i_q[3:0]] <= show[23] ? -16'sd1 : 16'sd1;
                    i_q <= i_q + 5'd1;
                    if (i_q + 5'd1 == {3'b0, t1_q}) begin
                        st_q <= ({3'b0, t1_q} < tc_q) ? S_LVL_PFX : S_TZ;
                    end
                end else if (i_q < tc_q) begin
                    st_q <= S_LVL_PFX;
                end else begin
                    st_q <= S_TZ;
                end
            end

            S_LVL_PFX: if (win_ok) begin
                if (clz >= 5'd24) begin
                    st_q <= S_ERR;     // no marker in window
                end else begin
                    pfx_q <= clz;
                    st_q <= S_LVL_SFX;
                end
            end

            S_LVL_SFX: if (win_ok) begin
                level_q[i_q[3:0]] <= lvl_new;
                if (sl_q == 3'd0) begin
                    sl_q <= (abs_lvl > 16'd3) ? 3'd2 : 3'd1;
                end else if (abs_lvl > (16'd3 << (sl_q - 3'd1)) &&
                             sl_q < 3'd6) begin
                    sl_q <= sl_q + 3'd1;
                end
                i_q <= i_q + 5'd1;
                st_q <= (i_q + 5'd1 < tc_q) ? S_LVL_PFX : S_TZ;
            end

            S_TZ: if (win_ok) begin
                if (tc_q < maxc_q) begin
                    logic [4:0] tzv;
                    logic [4:0] tzlen;
                    logic       tzok;
                    if (cdc_q) begin
                        tzok = ctzl[4];
                        tzv = {3'b0, ctzl[3:2]};
                        tzlen = {3'b0, ctzl[1:0]};
                    end else begin
                        tzok = tzl[8];
                        tzv = {1'b0, tzl[7:4]};
                        tzlen = {1'b0, tzl[3:0]};
                    end
                    if (!tzok || {1'b0, tzv} > 6'(maxc_q - tc_q)) begin
                        st_q <= S_ERR;
                    end else begin
                        zl_q <= tzv;
                        pos_q <= 6'(tc_q) + 6'(tzv) - 6'd1;
                        run_i_q <= '0;
                        i_q <= '0;
                        st_q <= S_RUN;
                    end
                end else begin
                    zl_q <= '0;
                    pos_q <= 6'(tc_q) - 6'd1;
                    run_i_q <= '0;
                    i_q <= '0;
                    st_q <= S_RUN;
                end
            end

            S_RUN: if (win_ok) begin
                logic [4:0] run;
                logic       bad;
                run = '0;
                bad = 1'b0;
                if (i_q == tc_q - 5'd1) begin
                    run = zl_q;
                end else if (zl_q > 5'd0) begin
                    if (!runl[8] || {4'b0, runl[7:4]} > {4'b0, zl_q}) begin
                        bad = 1'b1;
                    end
                    run = {1'b0, runl[7:4]};
                end
                if (bad) begin
                    st_q <= S_ERR;
                end else begin
                    coef_we <= 1'b1;
                    coef_addr <= pos_q[3:0];
                    coef_data <= level_q[i_q[3:0]];
                    if (i_q + 5'd1 >= tc_q) begin
                        st_q <= S_DONE;
                    end else begin
                        pos_q <= pos_q - 6'sd1 - $signed({1'b0, run});
                        zl_q <= zl_q - run;
                        i_q <= i_q + 5'd1;
                    end
                end
            end

            S_DONE: st_q <= S_IDLE;
            S_ERR:  st_q <= S_IDLE;
            default: st_q <= S_IDLE;
            endcase
        end
    end

endmodule
