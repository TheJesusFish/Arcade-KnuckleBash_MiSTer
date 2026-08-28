// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 SDRAM ownership and ROM-client wrapper.
//
// Bank 0: 512 KiB 68000 program ROM, 16-bit logical reads.
// Bank 1: 8 MiB GP9001 graphics, shared tile/object 16-bit clients.
// Bank 2: 256 KiB OKI samples, 8-bit logical reads.
// Bank 3: unused.
//
// The controller and byte-stream loader use controller_reset only.  A game
// reset clears the runtime request/cache clients without interrupting SDRAM
// initialization or an accepted HPS write.
module knuckle_bash_sdram (
    input  logic        clk,
    input  logic        clk_sdram,
    input  logic        controller_reset,
    input  logic        runtime_reset,
    input  logic        runtime_enable,

    input  logic        ioctl_download,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [ 7:0] ioctl_data,
    input  logic [15:0] ioctl_index,

    output logic        ioctl_wait,
    output logic        sdram_init,
    output logic        download_drained,
    output logic        program_mode,
    output logic        runtime_ready,
    output logic        loader_range_error,
    output logic        loader_overflow_error,

    input  logic [17:0] main_rom_addr,
    input  logic        main_rom_cs,
    output logic [15:0] main_rom_data,
    output logic        main_rom_ok,

    input  logic [21:0] gp_tile_addr,
    input  logic        gp_tile_cs,
    output logic [15:0] gp_tile_data,
    output logic        gp_tile_ok,

    input  logic [21:0] gp_object_addr,
    input  logic        gp_object_cs,
    output logic [15:0] gp_object_data,
    output logic        gp_object_ok,

    input  logic [17:0] oki_rom_addr,
    output logic [ 7:0] oki_rom_data,
    output logic        oki_rom_ok,

    output wire         SDRAM_CLK,
    inout  wire  [15:0] SDRAM_DQ,
    output wire  [12:0] SDRAM_A,
    output wire  [ 1:0] SDRAM_BA,
    output wire         SDRAM_DQML,
    output wire         SDRAM_DQMH,
    output wire         SDRAM_nWE,
    output wire         SDRAM_nCAS,
    output wire         SDRAM_nRAS,
    output wire         SDRAM_nCS,
    output wire         SDRAM_CKE
);

localparam logic [4:0] POST_DRAIN_GUARD_CYCLES = 5'd16;

logic [ 1:0] prog_ba;
logic [21:0] prog_addr;
logic [15:0] prog_data;
logic [ 1:0] prog_dsn;
logic        prog_we;
logic        prog_rd;
logic        prog_ack;
logic        prog_rdy;
logic        prog_dst;
logic        prog_dok;

logic [21:0] ba0_addr;
logic [21:0] ba1_addr;
logic [21:0] ba2_addr;
logic [21:0] ba3_addr;
logic [ 3:0] ba_rd;
logic [ 3:0] ba_wr;
logic [ 3:0] ba_ack;
logic [ 3:0] ba_rdy;
logic [ 3:0] ba_dst;
logic [ 3:0] ba_dok;
logic [15:0] sdram_data;

logic        main_rom_rd;
logic        gp_rom_rd;
logic        oki_rom_rd;
logic [15:0] main_rom_data_int;
logic        main_rom_ok_int;
logic [15:0] gp_tile_data_int;
logic        gp_tile_ok_int;
logic [15:0] gp_object_data_int;
logic        gp_object_ok_int;
logic [ 7:0] oki_rom_data_int;
logic        oki_rom_ok_int;

logic [ 4:0] post_drain_count;
logic        runtime_active;
logic        client_reset;

wire         burst_ack_unused;
wire         burst_rdy_unused;
wire         burst_dst_unused;
wire         burst_dok_unused;

// The loader stores each raw GP lower/upper plane-word pair in one physical
// 32-bit cache block. Preserve the renderer's MAME-logical address while
// moving the plane selector from the MSB to the physical word LSB.
wire [21:0] gp_tile_physical_addr =
    {gp_tile_addr[20:0], gp_tile_addr[21]};
wire [21:0] gp_object_physical_addr =
    {gp_object_addr[20:0], gp_object_addr[21]};

// Programming mode must cover both phases of the local loader handshake.
// download_drained does not assert until a request has been accepted and the
// controller has subsequently reported prog_rdy.
always_comb begin
    program_mode  = ioctl_download || !download_drained;
    runtime_active = runtime_enable && runtime_ready && !program_mode &&
                     !runtime_reset && !controller_reset;
    client_reset  = controller_reset || runtime_reset || !runtime_ready ||
                    program_mode;

    ba_rd = {1'b0, oki_rom_rd, gp_rom_rd, main_rom_rd};
    ba_wr = 4'b0000;

    main_rom_data = main_rom_data_int;
    gp_tile_data  = gp_tile_data_int;
    gp_object_data = gp_object_data_int;
    oki_rom_data  = oki_rom_data_int;

    main_rom_ok  = runtime_active && main_rom_ok_int;
    gp_tile_ok   = runtime_active && gp_tile_ok_int;
    gp_object_ok = runtime_active && gp_object_ok_int;
    oki_rom_ok   = runtime_active && oki_rom_ok_int;
end

// Give the SDRAM controller a deterministic interval to leave programming
// mode before any runtime request can be emitted. A later gameplay reset only
// resets the clients; it deliberately does not reinitialize this guard.
always_ff @(posedge clk) begin
    if (controller_reset || sdram_init || !download_drained ||
        program_mode) begin
        post_drain_count <= 5'd0;
        runtime_ready    <= 1'b0;
    end else if (!runtime_ready) begin
        if (post_drain_count == POST_DRAIN_GUARD_CYCLES - 1'b1) begin
            runtime_ready <= 1'b1;
        end else begin
            post_drain_count <= post_drain_count + 1'b1;
        end
    end
end

assign SDRAM_CLK = clk_sdram;

knuckle_bash_sdram_loader u_loader (
    .clk              ( clk                   ),
    .rst              ( controller_reset      ),
    .ioctl_download   ( ioctl_download        ),
    .ioctl_wr         ( ioctl_wr              ),
    .ioctl_addr       ( ioctl_addr            ),
    .ioctl_data       ( ioctl_data            ),
    .ioctl_index      ( ioctl_index           ),
    .sdram_init       ( sdram_init            ),
    .prog_ack         ( prog_ack              ),
    .prog_rdy         ( prog_rdy              ),
    .ioctl_wait       ( ioctl_wait            ),
    .prog_ba          ( prog_ba               ),
    .prog_addr        ( prog_addr             ),
    .prog_data        ( prog_data             ),
    .prog_dsn         ( prog_dsn              ),
    .prog_we          ( prog_we               ),
    .prog_rd          ( prog_rd               ),
    .download_drained ( download_drained      ),
    .range_error      ( loader_range_error    ),
    .overflow_error   ( loader_overflow_error )
);

jtframe_rom_1slot #(
    .SDRAMW        ( 22             ),
    .SLOT0_DW      ( 16             ),
    .SLOT0_AW      ( 18             ),
    .SLOT0_LATCH   ( 0              ),
    .SLOT0_OKLATCH ( 0              ),
    .SLOT0_OFFSET  ( 22'd0          )
) u_main_rom (
    .rst        ( client_reset                    ),
    .clk        ( clk                             ),
    .slot0_addr ( main_rom_addr                   ),
    .slot0_dout ( main_rom_data_int               ),
    .slot0_cs   ( runtime_active && main_rom_cs   ),
    .slot0_ok   ( main_rom_ok_int                 ),
    .sdram_ack  ( ba_ack[0]                       ),
    .sdram_rd   ( main_rom_rd                     ),
    .sdram_addr ( ba0_addr                        ),
    .data_dst   ( ba_dst[0]                       ),
    .data_rdy   ( ba_rdy[0]                       ),
    .data_read  ( sdram_data                      )
);

jtframe_rom_2slots #(
    .SDRAMW        ( 22             ),
    .SLOT0_DW      ( 16             ),
    .SLOT1_DW      ( 16             ),
    .SLOT0_AW      ( 22             ),
    .SLOT1_AW      ( 22             ),
    .SLOT0_LATCH   ( 0              ),
    .SLOT1_LATCH   ( 0              ),
    .SLOT0_OKLATCH ( 0              ),
    .SLOT1_OKLATCH ( 0              ),
    .SLOT0_OFFSET  ( 22'd0          ),
    .SLOT1_OFFSET  ( 22'd0          )
) u_gp_rom (
    .rst        ( client_reset                    ),
    .clk        ( clk                             ),
    .slot0_addr ( gp_tile_physical_addr           ),
    .slot1_addr ( gp_object_physical_addr         ),
    .slot0_dout ( gp_tile_data_int                ),
    .slot1_dout ( gp_object_data_int              ),
    .slot0_cs   ( runtime_active && gp_tile_cs    ),
    .slot1_cs   ( runtime_active && gp_object_cs  ),
    .slot0_ok   ( gp_tile_ok_int                  ),
    .slot1_ok   ( gp_object_ok_int                ),
    .sdram_ack  ( ba_ack[1]                       ),
    .sdram_rd   ( gp_rom_rd                       ),
    .sdram_addr ( ba1_addr                        ),
    .data_dst   ( ba_dst[1]                       ),
    .data_rdy   ( ba_rdy[1]                       ),
    .data_read  ( sdram_data                      )
);

// JT6295 continuously presents its sample address. runtime_active is the
// logical chip-select, matching the controller's read-only runtime interval.
jtframe_rom_1slot #(
    .SDRAMW        ( 22             ),
    .SLOT0_DW      ( 8              ),
    .SLOT0_AW      ( 18             ),
    .SLOT0_LATCH   ( 0              ),
    .SLOT0_OKLATCH ( 0              ),
    .SLOT0_OFFSET  ( 22'd0          )
) u_oki_rom (
    .rst        ( client_reset      ),
    .clk        ( clk               ),
    .slot0_addr ( oki_rom_addr      ),
    .slot0_dout ( oki_rom_data_int  ),
    .slot0_cs   ( runtime_active    ),
    .slot0_ok   ( oki_rom_ok_int    ),
    .sdram_ack  ( ba_ack[2]         ),
    .sdram_rd   ( oki_rom_rd        ),
    .sdram_addr ( ba2_addr          ),
    .data_dst   ( ba_dst[2]         ),
    .data_rdy   ( ba_rdy[2]         ),
    .data_read  ( sdram_data        )
);

assign ba3_addr = 22'd0;

jtframe_board_sdram #(
    .SDRAMW ( 22 ),
    .MISTER ( 1  )
) u_sdram (
    .rst        ( controller_reset ),
    .clk        ( clk              ),
    .init       ( sdram_init       ),
    .prog_en    ( program_mode     ),

    .ba0_addr   ( ba0_addr         ),
    .ba1_addr   ( ba1_addr         ),
    .ba2_addr   ( ba2_addr         ),
    .ba3_addr   ( ba3_addr         ),
    .burst_addr ( 22'd0            ),
    .burst_ba   ( 2'd0             ),
    .burst_rd   ( 1'b0             ),
    .burst_wr   ( 1'b0             ),
    .ba_rd      ( ba_rd            ),
    .ba_wr      ( ba_wr            ),
    .ba0_din    ( 16'd0            ),
    .ba0_dsn    ( 2'b11            ),
    .ba1_din    ( 16'd0            ),
    .ba1_dsn    ( 2'b11            ),
    .ba2_din    ( 16'd0            ),
    .ba2_dsn    ( 2'b11            ),
    .ba3_din    ( 16'd0            ),
    .ba3_dsn    ( 2'b11            ),
    .burst_din  ( 16'd0            ),
    .burst_ack  ( burst_ack_unused ),
    .burst_rdy  ( burst_rdy_unused ),
    .burst_dst  ( burst_dst_unused ),
    .burst_dok  ( burst_dok_unused ),
    .ba_ack     ( ba_ack           ),
    .ba_rdy     ( ba_rdy           ),
    .ba_dst     ( ba_dst           ),
    .ba_dok     ( ba_dok           ),
    .dout       ( sdram_data       ),

    .prog_addr  ( prog_addr        ),
    .prog_data  ( prog_data        ),
    .prog_dsn   ( prog_dsn         ),
    .prog_ba    ( prog_ba          ),
    .prog_we    ( prog_we          ),
    .prog_rd    ( prog_rd          ),
    .prog_dok   ( prog_dok         ),
    .prog_rdy   ( prog_rdy         ),
    .prog_dst   ( prog_dst         ),
    .prog_ack   ( prog_ack         ),

    .sdram_dq   ( SDRAM_DQ         ),
    .sdram_a    ( SDRAM_A          ),
    .sdram_dqml ( SDRAM_DQML       ),
    .sdram_dqmh ( SDRAM_DQMH       ),
    .sdram_nwe  ( SDRAM_nWE        ),
    .sdram_ncas ( SDRAM_nCAS       ),
    .sdram_nras ( SDRAM_nRAS       ),
    .sdram_ncs  ( SDRAM_nCS        ),
    .sdram_ba   ( SDRAM_BA         ),
    .sdram_cke  ( SDRAM_CKE        )
);

endmodule
