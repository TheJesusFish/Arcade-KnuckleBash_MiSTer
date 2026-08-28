// SPDX-License-Identifier: GPL-2.0-or-later

// TP-023 MC68000 shell. Board decode and memories live outside this module so
// the real fx68k cadence/reset/interrupt contract can be verified in isolation.
module knuckle_bash_main_cpu (
    input  logic        clk,
    input  logic        reset,
    input  logic        run,
    input  logic        irq4,
    input  logic        ss_irq,
    input  logic        bus_busy,
    input  logic [15:0] cpu_din,

    output logic        cpu_cen,
    output logic        cpu_cenb,
    output logic        cpu_dtack_n,
    output logic        cpu_bus_active,
    output logic        cpu_iack,
    output logic        cpu_rw,
    output logic        cpu_as_n,
    output logic        cpu_uds_n,
    output logic        cpu_lds_n,
    output logic [ 2:0] cpu_fc,
    output logic [23:0] cpu_addr,
    output logic [15:0] cpu_dout,
    output logic        v25_owner_reset_n,
    output logic        cpu_halted_n,
    output logic        bus_idle
);

logic [23:1] cpu_word_addr;
logic        cpu_fc0;
logic        cpu_fc1;
logic        cpu_fc2;
logic        cpu_bg_n;
logic        cpu_vpa_n;

assign cpu_addr       = {cpu_word_addr, 1'b0};
assign cpu_fc         = {cpu_fc2, cpu_fc1, cpu_fc0};
assign cpu_bus_active = !cpu_as_n && (!cpu_uds_n || !cpu_lds_n);
assign cpu_iack       = !cpu_as_n && cpu_fc0 && cpu_fc1 && cpu_fc2;
assign cpu_vpa_n      = ~&{cpu_fc0, cpu_fc1, cpu_fc2, ~cpu_as_n};
assign bus_idle       = cpu_as_n && cpu_dtack_n;

knuckle_bash_main_timing u_timing (
    .clk      ( clk                         ),
    .rst      ( reset                       ),
    .bus_cs   ( cpu_bus_active              ),
    .bus_busy ( bus_busy                    ),
    .as_n     ( cpu_as_n                    ),
    .ds_n     ( {cpu_uds_n, cpu_lds_n}      ),
    .cpu_cen  ( cpu_cen                     ),
    .cpu_cenb ( cpu_cenb                    ),
    .dtack_n  ( cpu_dtack_n                 )
);

fx68k u_cpu (
    .clk        ( clk                       ),
    .HALTn      ( run                       ),
    .extReset   ( reset                     ),
    .pwrUp      ( reset                     ),
    .enPhi1     ( cpu_cen  && run            ),
    .enPhi2     ( cpu_cenb && run            ),
    .eRWn       ( cpu_rw                    ),
    .ASn        ( cpu_as_n                  ),
    .LDSn       ( cpu_lds_n                 ),
    .UDSn       ( cpu_uds_n                 ),
    .E          (                           ),
    .VMAn       (                           ),
    .FC0        ( cpu_fc0                   ),
    .FC1        ( cpu_fc1                   ),
    .FC2        ( cpu_fc2                   ),
    .BGn        ( cpu_bg_n                  ),
    .oRESETn    ( v25_owner_reset_n         ),
    .oHALTEDn   ( cpu_halted_n              ),
    .DTACKn     ( cpu_dtack_n               ),
    .VPAn       ( cpu_vpa_n                 ),
    .BERRn      ( 1'b1                      ),
    .BRn        ( 1'b1                      ),
    .BGACKn     ( 1'b1                      ),
    .IPL0n      ( ~ss_irq                   ),
    .IPL1n      ( ~ss_irq                   ),
    .IPL2n      ( ~(ss_irq || irq4)         ),
    .iEdb       ( cpu_din                   ),
    .oEdb       ( cpu_dout                  ),
    .eab        ( cpu_word_addr             )
);

endmodule
