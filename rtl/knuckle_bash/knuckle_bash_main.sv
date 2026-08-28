// SPDX-License-Identifier: GPL-2.0-or-later

// TP-023 main-CPU composition: real fx68k shell plus transaction-safe board
// bus. SDRAM ROM and GP9001 remain explicit accepted/completed clients.
module knuckle_bash_main (
    input  logic        clk,
    input  logic        reset,
    input  logic        run,
    input  logic        txn_flush,
    input  logic        irq4,
    input  logic        ss_irq,

    input  logic        hs_reset, hs_download, hs_upload, hs_wr, hs_rd, hs_ss_active,
    input  logic [1:0]  hs_set_id,
    input  logic [26:0] hs_addr,
    input  logic [7:0]  hs_data,
    input  logic [15:0] hs_index,
    output logic [7:0]  hs_din,
    output logic        hs_wait, hs_dirty, hs_active,

    input  logic [ 7:0] player1,
    input  logic [ 7:0] player2,
    input  logic [ 7:0] system,
    input  logic [15:0] vcount_data,

    output logic        rom_req,
    output logic [17:0] rom_addr,
    input  logic        rom_ok,
    input  logic [15:0] rom_data,

    output logic        gp_req,
    output logic        gp_rw,
    output logic [ 3:0] gp_addr,
    output logic [15:0] gp_wdata,
    output logic [ 1:0] gp_be,
    input  logic        gp_accept,
    input  logic        gp_done,
    input  logic [15:0] gp_rdata,
    input  logic        gp_idle,

    input  logic [10:0] palette_scan_addr,
    output logic [15:0] palette_scan_data,

    output logic [10:0] shared_addr,
    output logic [ 7:0] shared_din,
    output logic        shared_we,
    input  logic [ 7:0] shared_dout,

    output logic [ 7:0] coin_control,
    output logic        v25_owner_reset_n,
    output logic        state_idle,
    output logic        state_held,

    output logic        debug_cpu_cen,
    output logic        debug_cpu_cenb,
    output logic        debug_cpu_dtack_n,
    output logic        debug_cpu_bus_active,
    output logic        debug_cpu_ack_now,
    output logic        debug_cpu_iack,
    output logic        debug_cpu_rw,
    output logic        debug_cpu_as_n,
    output logic        debug_cpu_uds_n,
    output logic        debug_cpu_lds_n,
    output logic [ 2:0] debug_cpu_fc,
    output logic [23:0] debug_cpu_addr,
    output logic [15:0] debug_cpu_dout,
    output logic [15:0] debug_cpu_din,
    output logic [31:0] debug_ack_count,
    output logic [31:0] debug_unmapped_ack_count
);

logic [15:0] bus_din;
logic [15:0] cpu_din;
logic        bus_busy;
logic        cpu_halted_n;
logic        cpu_bus_idle;
logic        mapped_cycle;
logic        unmapped_cycle;
logic [ 9:0] select_vector;
logic [31:0] rom_ack_count;
logic [31:0] wram_write_count;
logic [31:0] shared_write_count;
logic [31:0] gp_ack_count;
logic [31:0] palette_write_count;
logic [31:0] coin_write_count;
logic [23:0] last_ack_addr;
logic [15:0] last_ack_wdata;
logic        last_ack_rw;
logic [ 1:0] last_ack_be;

wire hs_hold_request;
reg hs_hold_latched = 0;
// Drain the accepted transaction, then prevent a new CPU cycle on the
// acquisition edge, just like the existing video-snapshot controller.
wire hs_pause = hs_hold_request && (hs_hold_latched || state_idle);
wire cpu_run = run && !hs_pause;
always @(posedge clk) begin
    if (reset || !hs_hold_request) hs_hold_latched <= 0;
    else if (state_idle) hs_hold_latched <= 1;
end

knuckle_bash_main_cpu u_main_cpu (
    .clk               ( clk                  ),
    .reset             ( reset                ),
    .run               ( cpu_run              ),
    .irq4              ( irq4                 ),
    .ss_irq            ( ss_irq               ),
    .bus_busy          ( bus_busy             ),
    .cpu_din           ( cpu_din              ),
    .cpu_cen           ( debug_cpu_cen        ),
    .cpu_cenb          ( debug_cpu_cenb       ),
    .cpu_dtack_n       ( debug_cpu_dtack_n    ),
    .cpu_bus_active    ( debug_cpu_bus_active ),
    .cpu_iack          ( debug_cpu_iack       ),
    .cpu_rw            ( debug_cpu_rw         ),
    .cpu_as_n          ( debug_cpu_as_n       ),
    .cpu_uds_n         ( debug_cpu_uds_n      ),
    .cpu_lds_n         ( debug_cpu_lds_n      ),
    .cpu_fc            ( debug_cpu_fc         ),
    .cpu_addr          ( debug_cpu_addr       ),
    .cpu_dout          ( debug_cpu_dout       ),
    .v25_owner_reset_n ( v25_owner_reset_n    ),
    .cpu_halted_n      ( cpu_halted_n         ),
    .bus_idle          ( cpu_bus_idle         )
);

// WAIT1 provides settling time, while this register keeps the long RAM/IO
// mux out of fx68k's direct combinational input path.
always_ff @(posedge clk) begin
    if (reset || txn_flush)
        cpu_din <= 16'hffff;
    else if (debug_cpu_bus_active && debug_cpu_rw)
        cpu_din <= bus_din;
end

assign debug_cpu_din = cpu_din;

knuckle_bash_main_bus u_main_bus (
    .clk                ( clk                      ),
    .rst                ( reset                    ),
    .txn_flush          ( txn_flush                ),
    .hs_reset           ( hs_reset                 ),
    .hs_set_id          ( hs_set_id                ),
    .hs_download        ( hs_download              ),
    .hs_upload          ( hs_upload                ),
    .hs_wr              ( hs_wr                    ),
    .hs_rd              ( hs_rd                    ),
    .hs_addr            ( hs_addr                  ),
    .hs_data            ( hs_data                  ),
    .hs_index           ( hs_index                 ),
    .hs_ss_active       ( hs_ss_active             ),
    .hs_din             ( hs_din                   ),
    .hs_wait            ( hs_wait                  ),
    .hs_dirty           ( hs_dirty                 ),
    .hs_active          ( hs_active                ),
    .hs_hold_request    ( hs_hold_request          ),
    .hs_hold_ack        ( hs_pause && state_idle   ),
    .bus_active         ( debug_cpu_bus_active     ),
    .rw                 ( debug_cpu_rw             ),
    .uds_n              ( debug_cpu_uds_n          ),
    .lds_n              ( debug_cpu_lds_n          ),
    .addr               ( debug_cpu_addr           ),
    .cpu_dout           ( debug_cpu_dout           ),
    .dtack_n            ( debug_cpu_dtack_n        ),
    .cpu_din            ( bus_din                  ),
    .ack_now            ( debug_cpu_ack_now        ),
    .bus_busy           ( bus_busy                 ),
    .player1            ( player1                  ),
    .player2            ( player2                  ),
    .system             ( system                   ),
    .vcount_data        ( vcount_data              ),
    .rom_req            ( rom_req                  ),
    .rom_addr           ( rom_addr                 ),
    .rom_ok             ( rom_ok                   ),
    .rom_data           ( rom_data                 ),
    .gp_req             ( gp_req                   ),
    .gp_rw              ( gp_rw                    ),
    .gp_addr            ( gp_addr                  ),
    .gp_wdata           ( gp_wdata                 ),
    .gp_be              ( gp_be                    ),
    .gp_accept          ( gp_accept                ),
    .gp_done            ( gp_done                  ),
    .gp_rdata           ( gp_rdata                 ),
    .palette_scan_addr  ( palette_scan_addr        ),
    .palette_scan_data  ( palette_scan_data        ),
    .shared_addr        ( shared_addr              ),
    .shared_din         ( shared_din               ),
    .shared_we          ( shared_we                ),
    .shared_dout        ( shared_dout              ),
    .coin_control       ( coin_control             ),
    .mapped_cycle       ( mapped_cycle             ),
    .unmapped_cycle     ( unmapped_cycle           ),
    .select_vector      ( select_vector            ),
    .ack_count          ( debug_ack_count          ),
    .rom_ack_count      ( rom_ack_count            ),
    .wram_write_count   ( wram_write_count         ),
    .shared_write_count ( shared_write_count       ),
    .gp_ack_count       ( gp_ack_count             ),
    .palette_write_count( palette_write_count      ),
    .coin_write_count   ( coin_write_count         ),
    .unmapped_ack_count ( debug_unmapped_ack_count ),
    .last_ack_addr      ( last_ack_addr            ),
    .last_ack_wdata     ( last_ack_wdata           ),
    .last_ack_rw        ( last_ack_rw              ),
    .last_ack_be        ( last_ack_be              )
);

assign state_idle = cpu_bus_idle &&
                    !bus_busy &&
                    !rom_req &&
                    !gp_req &&
                    gp_idle;
assign state_held = !cpu_run && state_idle;

endmodule
