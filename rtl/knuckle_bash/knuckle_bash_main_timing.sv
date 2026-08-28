// SPDX-License-Identifier: GPL-2.0-or-later

// Board-local MC68000 phase enables and DTACK timing.
//
// Knuckle Bash runs its 68000 at 16 MHz from the 94.5 MHz core clock.  The
// JTFrame helper takes a half-rate numerator and produces alternating Phi1 and
// Phi2 enables, so 32/189 is passed as num=32, den=189 and each phase averages
// 16 MHz.
module knuckle_bash_main_timing (
    input  logic       clk,
    input  logic       rst,
    input  logic       bus_cs,
    input  logic       bus_busy,
    input  logic       as_n,
    input  logic [1:0] ds_n,
    output logic       cpu_cen,
    output logic       cpu_cenb,
    output logic       dtack_n
);

wire [15:0] frequency_average_unused;
wire [15:0] frequency_worst_unused;

jtframe_68kdtack_cen #(
    .W        ( 8     ),
    .RECOVERY ( 1     ),
    .WD       ( 6     ),
    .WAIT1    ( 1     ),
    .MFREQ    ( 94500 )
) u_dtack (
    .rst       ( rst                      ),
    .clk       ( clk                      ),
    .cpu_cen   ( cpu_cen                  ),
    .cpu_cenb  ( cpu_cenb                 ),
    .bus_cs    ( bus_cs                   ),
    .bus_busy  ( bus_busy                 ),
    .bus_legit ( 1'b0                     ),
    .bus_ack   ( 1'b0                     ),
    .ASn       ( as_n                     ),
    .DSn       ( ds_n                     ),
    .num       ( 7'd32                    ),
    .den       ( 8'd189                   ),
    .wait2     ( 1'b0                     ),
    .wait3     ( 1'b0                     ),
    .DTACKn    ( dtack_n                  ),
    .fave      ( frequency_average_unused ),
    .fworst    ( frequency_worst_unused   )
);

endmodule
