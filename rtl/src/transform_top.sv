// transform_top — R2a unit wrapper exposing all four transform paths to
// the Verilator differential bench through flat ports.
`include "transform_dec.sv"

module transform_top (
    input  logic [255:0] c_flat,       // 16 x s16
    input  logic [5:0]   qp,
    input  logic [127:0] pred_flat,    // 16 x u8

    output logic [511:0] dq_flat,      // dequant4x4: 16 x s32
    output logic [511:0] ldc_flat,     // luma_dc_dequant: 16 x s32
    output logic [127:0] cdc_flat,     // chroma_dc_dequant: 4 x s32 (c[0..3])
    output logic [127:0] idct_flat     // idct4x4_add: 16 x u8
);

    logic signed [15:0] c [16];
    logic [7:0]  pred [16];
    logic signed [15:0] c4 [4];
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            c[i] = c_flat[i*16 +: 16];
            pred[i] = pred_flat[i*8 +: 8];
        end
        for (int i = 0; i < 4; i++) c4[i] = c_flat[i*16 +: 16];
    end

    logic signed [31:0] dq [16];
    logic signed [31:0] ldc [16];
    logic signed [31:0] cdc [4];
    logic [7:0] idout [16];

    dequant4x4       u_dq  (.c(c), .qp(qp), .d(dq));
    luma_dc_dequant  u_ldc (.c(c), .qp(qp), .dc(ldc));
    chroma_dc_dequant u_cdc(.c(c4), .qp(qp), .dc(cdc));
    idct4x4_add      u_id  (.d(dq), .pred(pred), .out(idout));

    always_comb begin
        for (int i = 0; i < 16; i++) begin
            dq_flat[i*32 +: 32] = dq[i];
            ldc_flat[i*32 +: 32] = ldc[i];
            idct_flat[i*8 +: 8] = idout[i];
        end
        for (int i = 0; i < 4; i++) cdc_flat[i*32 +: 32] = cdc[i];
    end

endmodule
