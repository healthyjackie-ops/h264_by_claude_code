// bitreader — RBSP bit consumer for the CAVLC datapath (rtl_spec.md R1,
// input widened to 32 bits in R4e).
//
// Left-aligned 64-bit buffer: bit 63 is the next bitstream bit. Words of
// 1..4 bytes (MSB-first, in_bytes counts them) are accepted whenever the
// buffer has room; the consumer sees a 24-bit lookahead window plus the
// available-bit count and retires 1..24 bits per cycle. The widened feed
// outruns the single-cycle decode FSMs, so the avail>=24 starvation
// gates never engage mid-stream.
module bitreader (
    input  logic        clk,
    input  logic        rst_n,

    // word feed: in_word[31:24] is the first byte of the group
    input  logic        in_valid,
    input  logic [31:0] in_word,
    input  logic [2:0]  in_bytes,      // 1..4 valid bytes
    output logic        in_ready,

    // bit consume
    input  logic        req_valid,
    input  logic [4:0]  req_bits,      // 1..24
    output logic        req_ready,

    // lookahead
    output logic [23:0] show,
    output logic [6:0]  avail
);

    logic [95:0] buf_q;                // widened with the 32b feed (R4e):
    logic [6:0]  fill_q;               // a 64b buffer left the accept
                                       // window (fill<=32) colliding with
                                       // the avail>=24 starvation gate
    assign in_ready  = (fill_q <= 7'd64);
    assign req_ready = req_valid && (fill_q >= {2'b0, req_bits});
    assign show      = buf_q[95:72];
    assign avail     = fill_q;

    // one byte in and one consume can both happen in a cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_q  <= '0;
            fill_q <= '0;
        end else begin
            logic [95:0] b;
            logic [6:0]  f;
            b = buf_q;
            f = fill_q;
            if (req_valid && (f >= {2'b0, req_bits})) begin
                b = b << req_bits;
                f = f - {2'b0, req_bits};
            end
            if (in_valid && (fill_q <= 7'd64)) begin
                logic [31:0] wd;
                unique case (in_bytes)
                    3'd1: wd = {in_word[31:24], 24'b0};
                    3'd2: wd = {in_word[31:16], 16'b0};
                    3'd3: wd = {in_word[31:8], 8'b0};
                    default: wd = in_word;
                endcase
                b = b | ({64'b0, wd} << (7'd64 - f));
                f = f + {2'b0, in_bytes, 3'b0};    // bytes * 8
            end
            buf_q  <= b;
            fill_q <= f;
        end
    end

endmodule
