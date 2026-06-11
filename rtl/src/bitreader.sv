// bitreader — RBSP bit consumer for the CAVLC datapath (rtl_spec.md R1).
//
// Left-aligned 64-bit buffer: bit 63 is the next bitstream bit. Bytes are
// accepted whenever 8 bits of room exist; the consumer sees a 24-bit
// lookahead window (`show`) plus the available-bit count and retires
// 1..24 bits per cycle through the req interface. Starting bit offsets
// that are not byte-aligned (CAVLC slice_data) are handled by consuming
// the residue bits up front.
module bitreader (
    input  logic        clk,
    input  logic        rst_n,

    // byte feed
    input  logic        in_valid,
    input  logic [7:0]  in_byte,
    output logic        in_ready,

    // bit consume
    input  logic        req_valid,
    input  logic [4:0]  req_bits,      // 1..24
    output logic        req_ready,

    // lookahead
    output logic [23:0] show,
    output logic [6:0]  avail
);

    logic [63:0] buf_q;
    logic [6:0]  fill_q;               // 0..64 valid bits, left-aligned

    assign in_ready  = (fill_q <= 7'd56);
    assign req_ready = req_valid && (fill_q >= {2'b0, req_bits});
    assign show      = buf_q[63:40];
    assign avail     = fill_q;

    // one byte in and one consume can both happen in a cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_q  <= '0;
            fill_q <= '0;
        end else begin
            logic [63:0] b;
            logic [6:0]  f;
            b = buf_q;
            f = fill_q;
            if (req_valid && (f >= {2'b0, req_bits})) begin
                b = b << req_bits;
                f = f - {2'b0, req_bits};
            end
            if (in_valid && (fill_q <= 7'd56)) begin
                b = b | ({56'b0, in_byte} << (7'd56 - f));
                f = f + 7'd8;
            end
            buf_q  <= b;
            fill_q <= f;
        end
    end

endmodule
