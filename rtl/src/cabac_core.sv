// cabac_core — CABAC arithmetic decoding engine (W15-a, clause 9.3.3.2).
//
// One bin per accepted op beat. The bit source is the bitreader show
// window (same consumer protocol as expgolomb/cavlc_block): renorm
// computes its shift count combinationally from the post-decision
// range, takes that many bits from show, and consumes them on the
// same edge. Context states (436 x {pstate[5:0], mps}) live in a flop
// register file so a decision's read-modify-write fits one beat.
//
// init: a 436-cycle serial FSM loads the (m,n) ROM pair per context,
// applies preCtxState = clip3(1,126, ((m*qp)>>4)+n), then primes
// range=510 and pulls 9 offset bits from the stream.
//
// Ops: 0 = decision (ctx), 1 = bypass, 2 = terminate. bin_valid pulses
// with the result on the beat the op is accepted (window permitting).
`include "cabac_tables.svh"

module cabac_core (
    input  logic        clk,
    input  logic        rst_n,

    // bitreader window
    output logic        req_valid,
    output logic [4:0]  req_bits,
    input  logic        req_ready,
    input  logic [23:0] show,
    input  logic [6:0]  avail,

    // context init
    input  logic        init_start,
    input  logic [5:0]  init_qp,
    input  logic [1:0]  init_model,    // 0..2 = cabac_init_idc, 3 = I
    output logic        init_busy,

    // bin operations
    input  logic        op_valid,
    input  logic [1:0]  op,            // 0 decision, 1 bypass, 2 terminate
    input  logic [8:0]  op_ctx,
    output logic        op_ready,
    output logic        bin,
    output logic [8:0]  dbg_range,
    output logic [8:0]  dbg_value
);

    logic [8:0] range_q, value_q;
    logic [5:0] pstate [436];
    logic [435:0] mps;

    typedef enum logic [1:0] { S_RUN, S_INIT, S_PRIME } state_e;
    state_e st_q;
    logic [8:0] ictx_q;
    logic [1:0] model_q;

    assign init_busy = (st_q != S_RUN);
    assign dbg_range = range_q;
    assign dbg_value = value_q;

    // ---- init datapath ----
    logic [15:0] mn;
    logic signed [15:0] pre_raw;
    logic [6:0] pre;
    assign mn = cabac_init_mn(model_q, ictx_q);
    always_comb begin
        logic signed [15:0] t;
        t = ($signed(mn[15:8]) * $signed({10'b0, init_qp})) >>> 4;
        t = t + $signed(mn[7:0]);
        if (t < 1) t = 1;
        if (t > 126) t = 126;
        pre_raw = t;
        pre = pre_raw[6:0];
    end

    // ---- decision/bypass/terminate datapath (combinational) ----
    logic [7:0] rlps;
    logic [8:0] r_dec, r_mps_v;
    logic       is_lps;
    logic [5:0] ps_cur;
    logic       mps_cur;
    assign ps_cur = pstate[op_ctx];
    assign mps_cur = mps[op_ctx];
    assign rlps = cabac_rlps(ps_cur, 2'(range_q[8:6] - 3'd4));
    assign r_mps_v = range_q - 9'(rlps);
    assign is_lps = (value_q >= r_mps_v);
    assign r_dec = is_lps ? 9'(rlps) : r_mps_v;

    logic [8:0] v_dec;
    assign v_dec = is_lps ? (value_q - r_mps_v) : value_q;

    // renorm shift = leading zeros of r above bit 8 (range in [2,510])
    function automatic logic [2:0] rshift(input logic [8:0] r);
        if (r[8]) return 3'd0;
        if (r[7]) return 3'd1;
        if (r[6]) return 3'd2;
        if (r[5]) return 3'd3;
        if (r[4]) return 3'd4;
        if (r[3]) return 3'd5;
        if (r[2]) return 3'd6;
        return 3'd7;
    endfunction

    // terminate path
    logic [8:0] r_term;
    assign r_term = range_q - 9'd2;
    logic term_hit;
    assign term_hit = (value_q >= r_term);

    // per-op renorm shift and window need
    logic [2:0] shn;
    always_comb begin
        unique case (op)
        2'd0: shn = rshift(r_dec);
        2'd1: shn = 3'd1;                       // bypass always 1 bit
        default: shn = term_hit ? 3'd0 : rshift(r_term);
        endcase
    end

    // renorm fill: v = (v << shn) | top shn bits of show, MSB-first.
    // decision/terminate keep v < r through renorm, so 9 bits suffice.
    logic [8:0] v_shifted;
    always_comb begin
        logic [6:0] hi7;
        hi7 = show[23:17];
        v_shifted = 9'((16'(v_dec) << shn) |
                       16'(hi7 >> (3'd7 - shn)));
    end

    // bypass: one shifted-in bit makes a 10-bit intermediate before
    // the conditional range subtraction folds it back under 9 bits
    logic [9:0] v_byp10;
    logic [8:0] v_byp;
    logic       byp_one;
    assign v_byp10 = {value_q, show[23]};
    assign byp_one = (v_byp10 >= {1'b0, range_q});
    assign v_byp = byp_one ? 9'(v_byp10 - {1'b0, range_q})
                           : v_byp10[8:0];

    // op acceptance: enough window bits for the renorm shift
    logic can_run;
    assign can_run = (st_q == S_RUN) && op_valid &&
                     (shn == 3'd0 || 7'(shn) <= avail);
    assign op_ready = can_run;

    always_comb begin
        req_valid = 1'b0;
        req_bits = '0;
        if (st_q == S_PRIME) begin
            if (avail >= 7'd9) begin
                req_valid = 1'b1;
                req_bits = 5'd9;
            end
        end else if (can_run && shn != 3'd0) begin
            req_valid = 1'b1;
            req_bits = {2'b0, shn};
        end
    end

    // terminate renorm shifts the UNCHANGED value
    logic [8:0] v_term_sh;
    always_comb begin
        logic [6:0] hi7;
        hi7 = show[23:17];
        v_term_sh = 9'((16'(value_q) << shn) |
                       16'(hi7 >> (3'd7 - shn)));
    end

    always_comb begin
        unique case (op)
        2'd0: bin = is_lps ? !mps_cur : mps_cur;
        2'd1: bin = byp_one;
        default: bin = term_hit;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_RUN;
            range_q <= 9'd510;
            value_q <= '0;
            ictx_q <= '0;
            model_q <= '0;
            mps <= '0;
        end else begin
            unique case (st_q)
            S_RUN: begin
                if (init_start) begin
                    ictx_q <= '0;
                    model_q <= init_model;
                    st_q <= S_INIT;
                end else if (can_run) begin
                    unique case (op)
                    2'd0: begin
                        range_q <= r_dec << shn;
                        value_q <= v_shifted;
                        if (is_lps) begin
                            if (ps_cur == 6'd0)
                                mps[op_ctx] <= !mps_cur;
                            pstate[op_ctx] <= cabac_tlps(ps_cur);
                        end else begin
                            pstate[op_ctx] <= cabac_tmps(ps_cur);
                        end
                    end
                    2'd1: begin
                        value_q <= v_byp;
                    end
                    default: begin
                        // C mirrors: range is reduced even on the hit
                        // (no renorm then); keeps state-level lockstep
                        range_q <= term_hit ? r_term : (r_term << shn);
                        if (!term_hit) value_q <= v_term_sh;
                    end
                    endcase
                end
            end

            S_INIT: begin
                pstate[ictx_q] <= (pre <= 7'd63) ? 6'(7'd63 - pre)
                                                 : 6'(pre - 7'd64);
                mps[ictx_q] <= (pre > 7'd63);
                if (ictx_q == 9'd435) begin
                    range_q <= 9'd510;
                    st_q <= S_PRIME;
                end else
                    ictx_q <= ictx_q + 9'd1;
            end

            S_PRIME: if (avail >= 7'd9) begin
                value_q <= show[23:15];
                st_q <= S_RUN;
            end
            default: st_q <= S_RUN;
            endcase
        end
    end

endmodule
