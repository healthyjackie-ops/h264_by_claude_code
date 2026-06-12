// mc_fetch — reference-window fetch engine (P-R2).
//
// One 4x4 block per request: takes the block's pixel position, the
// quarter-pel motion vector and the plane, derives the integer origin
// and fractional phase, fetches the interpolation window over a simple
// row-read channel (the system side owns the reference frame and
// implements the clamp semantics — DDR with padded frames in silicon,
// a behavioral model in the bench), then drives mc_core and hands back
// the 16 predicted samples.
//
// Row-read channel: req_x/req_y may be negative or beyond the frame;
// the responder returns w pixels of the clamped row segment, MSB first
// in rsp_data[71:0] (9 used for luma, 5 for chroma).
module mc_fetch (
    input  logic        clk,
    input  logic        rst_n,

    // block request
    input  logic        start,
    input  logic        is_chroma,
    input  logic [11:0] px,            // block pixel x in the plane
    input  logic [10:0] py,
    input  logic signed [15:0] mvx,    // quarter-pel (chroma: eighth)
    input  logic signed [15:0] mvy,
    output logic        busy,
    output logic        done,          // pred valid for one cycle

    // row-read channel
    output logic        req_valid,
    output logic signed [12:0] req_x,
    output logic signed [11:0] req_y,
    output logic [3:0]  req_w,         // 9 luma, 5 chroma
    input  logic        rsp_valid,
    input  logic [71:0] rsp_data,      // row pixels, [71:64] = first

    output logic [7:0]  pred [16]
);

    logic [7:0] lwin [9][9];
    logic [7:0] cwin [5][5];

    logic        chroma_q;
    logic signed [12:0] x0_q;
    logic signed [11:0] y0_q;
    logic [1:0]  lfx_q, lfy_q;
    logic [2:0]  cfx_q, cfy_q;
    logic [3:0]  row_q;                // rows requested / received
    logic [3:0]  got_q;

    typedef enum logic [1:0] { S_IDLE, S_FETCH, S_OUT } state_e;
    state_e st_q;

    assign busy = (st_q != S_IDLE);
    assign done = (st_q == S_OUT);

    // window dimensions per plane
    logic [3:0] nrows;
    assign nrows = chroma_q ? 4'd5 : 4'd9;

    assign req_valid = (st_q == S_FETCH) && (row_q < nrows);
    assign req_x = x0_q;
    assign req_y = y0_q + 12'(row_q);
    assign req_w = chroma_q ? 4'd5 : 4'd9;

    // interpolators (combinational over the filled windows)
    logic [7:0] lpred [16];
    logic [7:0] cpred [16];
    mc4x4_luma u_l (.win(lwin), .fx(lfx_q), .fy(lfy_q), .pred(lpred));
    mc4x4_chroma u_c (.win(cwin), .fx(cfx_q), .fy(cfy_q), .pred(cpred));
    always_comb begin
        for (int i = 0; i < 16; i++)
            pred[i] = chroma_q ? cpred[i] : lpred[i];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_q <= S_IDLE;
            row_q <= '0;
            got_q <= '0;
            chroma_q <= 1'b0;
            x0_q <= '0; y0_q <= '0;
            lfx_q <= '0; lfy_q <= '0; cfx_q <= '0; cfy_q <= '0;
        end else begin
            unique case (st_q)
            S_IDLE: if (start) begin
                chroma_q <= is_chroma;
                if (is_chroma) begin
                    x0_q <= 13'($signed({1'b0, px}) + (mvx >>> 3));
                    y0_q <= 12'($signed({1'b0, py}) + (mvy >>> 3));
                    cfx_q <= 3'(mvx & 16'sd7);
                    cfy_q <= 3'(mvy & 16'sd7);
                end else begin
                    x0_q <= 13'($signed({1'b0, px}) + (mvx >>> 2) - 13'sd2);
                    y0_q <= 12'($signed({1'b0, py}) + (mvy >>> 2) - 12'sd2);
                    lfx_q <= 2'(mvx & 16'sd3);
                    lfy_q <= 2'(mvy & 16'sd3);
                end
                row_q <= '0;
                got_q <= '0;
                st_q <= S_FETCH;
            end

            S_FETCH: begin
                if (req_valid) row_q <= row_q + 4'd1;
                if (rsp_valid) begin
                    if (chroma_q) begin
                        for (int i = 0; i < 5; i++)
                            cwin[got_q[2:0]][i] <= rsp_data[71 - i*8 -: 8];
                    end else begin
                        for (int i = 0; i < 9; i++)
                            lwin[got_q[3:0]][i] <= rsp_data[71 - i*8 -: 8];
                    end
                    got_q <= got_q + 4'd1;
                    if (got_q + 4'd1 == nrows) st_q <= S_OUT;
                end
            end

            S_OUT: st_q <= S_IDLE;
            default: st_q <= S_IDLE;
            endcase
        end
    end

endmodule
