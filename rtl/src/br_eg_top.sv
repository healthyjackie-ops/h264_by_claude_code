// br_eg_top — R1a unit-test wrapper: bitreader + expgolomb side by side
// so the Verilator testbench sees both the raw window and the decoded
// ue/se view of it.
module br_eg_top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    input  logic [7:0]  in_byte,
    output logic        in_ready,

    input  logic        req_valid,
    input  logic [4:0]  req_bits,
    output logic        req_ready,

    output logic [23:0] show,
    output logic [6:0]  avail,

    output logic [11:0] eg_ue,
    output logic [11:0] eg_se,
    output logic [4:0]  eg_len,
    output logic        eg_ok
);

    bitreader u_br (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (in_valid),
        .in_byte  (in_byte),
        .in_ready (in_ready),
        .req_valid(req_valid),
        .req_bits (req_bits),
        .req_ready(req_ready),
        .show     (show),
        .avail    (avail)
    );

    logic signed [11:0] se_s;
    expgolomb u_eg (
        .show   (show),
        .ue_val (eg_ue),
        .se_val (se_s),
        .len    (eg_len),
        .ok     (eg_ok)
    );
    assign eg_se = se_s;

endmodule
