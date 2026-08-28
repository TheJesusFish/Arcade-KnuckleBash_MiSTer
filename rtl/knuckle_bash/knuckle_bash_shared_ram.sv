// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_shared_ram (
    input  logic        clk,

    input  logic [10:0] main_addr,
    input  logic [ 7:0] main_din,
    input  logic        main_we,
    output logic [ 7:0] main_dout,

    input  logic [10:0] sound_addr,
    input  logic [ 7:0] sound_din,
    input  logic        sound_we,
    output logic [ 7:0] sound_dout
);

(* ramstyle = "no_rw_check" *) logic [7:0] ram [0:2047];

always_ff @(posedge clk) begin
    main_dout <= ram[main_addr];
    if (main_we)
        ram[main_addr] <= main_din;
end

always_ff @(posedge clk) begin
    sound_dout <= ram[sound_addr];
    if (sound_we)
        ram[sound_addr] <= sound_din;
end

endmodule
