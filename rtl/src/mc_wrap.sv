// mc_wrap — P-R1 unit wrapper: luma + chroma MC side by side.
module mc_wrap (
    input  logic [7:0] lwin [9][9],
    input  logic [1:0] lfx,
    input  logic [1:0] lfy,
    output logic [7:0] lpred [16],
    input  logic [7:0] cwin [5][5],
    input  logic [2:0] cfx,
    input  logic [2:0] cfy,
    output logic [7:0] cpred [16]
);
    mc4x4_luma u_l (.win(lwin), .fx(lfx), .fy(lfy), .pred(lpred));
    mc4x4_chroma u_c (.win(cwin), .fx(cfx), .fy(cfy), .pred(cpred));
endmodule
