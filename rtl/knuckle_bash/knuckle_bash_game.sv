// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_game (
    input  logic        clk,
    input  logic        reset_cold,
    input  logic        reset_game,
    input  logic [127:0] status,
    input  logic [ 31:0] joy1,
    input  logic [ 31:0] joy2,
    input  logic        pause,
    input  logic        ioctl_download,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [ 7:0] ioctl_data,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_upload,
    input  logic        hs_download,
    input  logic        ioctl_rd,
    output logic [7:0]  hs_din,
    output logic        hs_wait, hs_dirty, hs_active,
    input  logic        sdram_ready,
    output logic        rom_valid_out,
    output logic        main_rom_req,
    output logic [17:0] main_rom_addr,
    input  logic [15:0] main_rom_data,
    input  logic        main_rom_ok,
    output logic        gp_tile_req,
    output logic [21:0] gp_tile_addr,
    input  logic [15:0] gp_tile_data,
    input  logic        gp_tile_ok,
    output logic        gp_object_req,
    output logic [21:0] gp_object_addr,
    input  logic [15:0] gp_object_data,
    input  logic        gp_object_ok,
    output logic [17:0] oki_rom_addr,
    input  logic [ 7:0] oki_rom_data,
    input  logic        oki_rom_ok,
    input  logic        ss_save_req,
    input  logic        ss_load_req,
    input  logic        ss_stream_busy,
    input  logic        ss_format_valid,
    input  logic [63:0] ss_data,
    input  logic [31:0] ss_addr,
    input  logic [ 7:0] ss_select,
    input  logic        ss_write,
    input  logic        ss_read,
    input  logic        ss_query,
    output logic [63:0] ss_data_out,
    output logic        ss_ack,
    output logic        ss_save_start,
    output logic        ss_load_start,
    output logic        ss_active,
    output logic [ 7:0] red,
    output logic [ 7:0] green,
    output logic [ 7:0] blue,
    output logic        hs,
    output logic        vs,
    output logic        de,
    output logic        hblank,
    output logic        vblank,
    output logic        pxl_cen,
    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r
);

logic v25_cen;
logic opm_cen;
logic oki_cen;

knuckle_bash_clock_en u_clock_en (
    .clk     ( clk     ),
    .rst     ( reset_game ),
    .pxl_cen ( pxl_cen ),
    .v25_cen ( v25_cen ),
    .opm_cen ( opm_cen ),
    .oki_cen ( oki_cen )
);

logic        rom_download_done;
logic        rom_valid;
logic [ 1:0] rom_set_id;
logic [23:0] rom_size;
logic [63:0] rom_crc64;
logic [31:0] dipsw;

knuckle_bash_rom_loader u_rom_loader (
    .clk            ( clk               ),
    .rst            ( reset_cold        ),
    .ioctl_download ( ioctl_download    ),
    .ioctl_wr       ( ioctl_wr          ),
    .ioctl_addr     ( ioctl_addr        ),
    .ioctl_data     ( ioctl_data        ),
    .ioctl_index    ( ioctl_index       ),
    .download_done  ( rom_download_done ),
    .rom_valid      ( rom_valid         ),
    .rom_set_id     ( rom_set_id        ),
    .rom_size       ( rom_size          ),
    .rom_crc64      ( rom_crc64         )
);

assign rom_valid_out = rom_valid;

knuckle_bash_switches u_switches (
    .clk         ( clk         ),
    .rst         ( reset_cold  ),
    .ioctl_wr    ( ioctl_wr    ),
    .ioctl_addr  ( ioctl_addr  ),
    .ioctl_data  ( ioctl_data  ),
    .ioctl_index ( ioctl_index ),
    .rom_valid   ( rom_valid   ),
    .rom_set_id  ( rom_set_id  ),
    .dipsw       ( dipsw       )
);

logic [7:0] player1_inputs;
logic [7:0] player2_inputs;
logic [7:0] system_inputs;

knuckle_bash_inputs u_inputs (
    .joy1     ( joy1            ),
    .joy2     ( joy2            ),
    .service1 ( 1'b0            ),
    .tilt     ( 1'b0            ),
    .test     ( dipsw[2]        ),
    .player1  ( player1_inputs  ),
    .player2  ( player2_inputs  ),
    .system   ( system_inputs   )
);

logic safe_boundary;

wire [63:0] ss_magic;
wire [31:0] ss_schema;
wire [47:0] ss_board;
wire [15:0] ss_chunks;
wire [63:0] ss_sound_data_out;
wire        ss_sound_ack;

knuckle_bash_savestate_schema u_ss_schema (
    .magic          ( ss_magic  ),
    .schema_version ( ss_schema ),
    .board_id       ( ss_board  ),
    .chunk_count    ( ss_chunks )
);

logic [8:0] hcnt;
logic [8:0] vcnt;
logic       video_epoch;
logic       gp_snapshot_busy;
logic       gp_snapshot_valid;
logic       palette_snapshot_busy;
logic       palette_snapshot_valid;
logic [1:0] video_engine_busy;
logic       video_snapshot_frame_valid;

always_ff @(posedge clk) begin
    if (reset_game) begin
        hcnt        <= 9'd0;
        vcnt        <= 9'd0;
        video_epoch <= 1'b0;
    end else if (pxl_cen) begin
        if (hcnt == 9'd431) begin
            hcnt <= 9'd0;
            if (vcnt == 9'd261) begin
                vcnt        <= 9'd0;
                video_epoch <= ~video_epoch;
            end else begin
                vcnt <= vcnt + 9'd1;
            end
        end else begin
            hcnt <= hcnt + 9'd1;
        end
    end
end

wire state_boundary_tick = pxl_cen && hcnt == 9'd0 && vcnt == 9'd240;

wire visible = hcnt < 9'd320 && vcnt < 9'd240;
wire hsync_n = !(hcnt >= 9'd336 && hcnt < 9'd368);
wire vsync_n = !(vcnt >= 9'd244 && vcnt < 9'd248);
wire video_snapshot_prepare =
    pxl_cen && hcnt == 9'd0 && vcnt == 9'd239;
wire video_snapshot_boundary =
    pxl_cen && hcnt == 9'd431 && vcnt == 9'd239;
wire video_line_event = pxl_cen && hcnt == 9'd431;
wire video_snapshot_ready =
    video_snapshot_frame_valid &&
    gp_snapshot_valid && palette_snapshot_valid &&
    !gp_snapshot_busy && !palette_snapshot_busy;
wire video_line_start =
    video_snapshot_ready &&
    !(|video_engine_busy) &&
    video_line_event &&
    ((vcnt < 9'd238) || (vcnt >= 9'd260));
wire video_line_commit =
    video_snapshot_ready && video_line_event &&
    ((vcnt < 9'd239) || (vcnt == 9'd261));
wire [8:0] video_target_y =
    (vcnt >= 9'd260) ? vcnt - 9'd260 : vcnt + 9'd2;
wire video_target_epoch =
    (vcnt >= 9'd260) ? ~video_epoch : video_epoch;

logic [ 8:0] vdp_adjusted_v;
logic        vdp_hsync_n;
logic        vdp_vsync_n;
logic        vdp_fblank_n;
logic [15:0] vdp_count_data;
logic        gp_status;
logic        gp_req;
logic        gp_rw;
logic [ 3:0] gp_addr;
logic [15:0] gp_wdata;
logic [ 1:0] gp_be;
logic        gp_accept;
logic        gp_done;
logic [15:0] gp_rdata;
logic        gp_idle;
logic        gp_irq4;
logic [12:0] gp_snapshot_addr;
logic [15:0] gp_snapshot_data;
logic [127:0] gp_live_scrolls;
logic [ 7:0] gp_live_scroll_flip;

logic [12:0] video_vram_addr;
logic [15:0] video_vram_data;
logic [ 9:0] video_object_addr;
logic [15:0] video_object_data;
logic [127:0] video_scrolls;
logic [ 7:0] video_scroll_flip;
logic        gp_snapshot_miss;

logic [10:0] palette_snapshot_addr;
logic [15:0] palette_snapshot_data;
logic [10:0] video_palette_addr;
logic [15:0] video_palette_data;
logic        palette_snapshot_miss;

logic        video_line_ready;
logic        video_pixel_valid;
logic [ 1:0] video_deadline_miss;
logic        video_object_overflow;
logic [15:0] video_tile_cycles;
logic [15:0] video_object_cycles;
logic        video_snapshot_main_run;
logic        video_snapshot_start;
logic        video_snapshot_hold;
logic        video_snapshot_control_miss;
logic        video_renderer_fault;

knuckle_bash_vdp_timing u_vdp_timing (
    .hcnt        ( hcnt           ),
    .vcnt        ( vcnt           ),
    .adjusted_v  ( vdp_adjusted_v ),
    .hsync_n     ( vdp_hsync_n    ),
    .vsync_n     ( vdp_vsync_n    ),
    .fblank_n    ( vdp_fblank_n   ),
    .vcount_data ( vdp_count_data ),
    .gp_status   ( gp_status      )
);

logic [10:0] shared_sound_addr;
logic [ 7:0] shared_sound_dout;
logic        shared_sound_we;
logic [ 7:0] shared_sound_din;
logic [10:0] shared_main_addr;
logic [ 7:0] shared_main_din;
logic        shared_main_we;
logic [ 7:0] shared_main_dout;
logic [14:0] v25_rom_addr;
logic [ 7:0] v25_rom_data;
logic        v25_owner_reset_n;
logic        main_state_idle;
logic        main_state_held;
logic        main_ready;
logic        main_reset;
logic        main_cpu_ack;
logic        main_cpu_iack;
logic        main_cpu_rw;
logic        main_cpu_uds_n;
logic        main_cpu_lds_n;
logic [ 2:0] main_cpu_fc;
logic [23:0] main_cpu_addr;
logic [15:0] main_cpu_dout;
logic        ss_irq;
logic        ss_override;
logic        ss_cpu_reset;
logic        ss_cpu_run;
logic        ss_device_hold;
logic        ss_video_reset;
logic        ss_restore_commit;
logic        ss_restore_compatible;
logic [31:0] ss_saved_ssp;
logic [31:0] ss_restore_ssp;
logic [63:0] ss_reset_vector;
logic [63:0] ss_restore_rom_signature;
logic [63:0] ss_global_data_out;
logic        ss_global_ack;
logic [63:0] ss_main_data_out;
logic        ss_main_ack;
logic [63:0] ss_shared_data_out;
logic        ss_shared_ack;
logic [63:0] ss_gp_data_out;
logic        ss_gp_ack;
logic [ 7:0] coin_control;
logic        v25_owner_reset_n_live;
logic        v25_owner_reset_n_saved;
logic        ss_restore_v25_owner;
logic [ 7:0] sound_bgm_pending_argument;
logic [ 7:0] sound_bgm_command;
logic [ 7:0] sound_bgm_argument;
logic        sound_bgm_valid;
logic [ 7:0] ss_restore_bgm_command;
logic [ 7:0] ss_restore_bgm_argument;
logic        ss_restore_bgm_valid;
wire         sound_sample;
wire         sound_state_idle;
wire         sound_state_held;
wire         sound_debug_fault;
wire         sound_debug_halted;
wire [19:0]  sound_debug_pc;
wire         sound_debug_ym_write;
wire         sound_debug_ym_a0;
wire [ 7:0]  sound_debug_ym_data;
wire         sound_debug_oki_write;
wire [ 7:0]  sound_debug_oki_data;

always_comb begin
    ss_ack = ss_global_ack || ss_main_ack || ss_shared_ack || ss_gp_ack;
    if (ss_global_ack)
        ss_data_out = ss_global_data_out;
    else if (ss_main_ack)
        ss_data_out = ss_main_data_out;
    else if (ss_shared_ack)
        ss_data_out = ss_shared_data_out;
    else if (ss_gp_ack)
        ss_data_out = ss_gp_data_out;
    else
        ss_data_out = 64'd0;
end

// Chunk 1 is deliberately ahead of every mutable RAM chunk. A restore does
// not enable any write port until both the top-level schema and this loaded
// ROM identity have matched the running set.
always_ff @(posedge clk) begin
    ss_global_ack <= 1'b0;
    if (main_reset || ss_load_start) begin
        ss_restore_ssp <= 32'd0;
        ss_restore_rom_signature <= 64'd0;
        ss_restore_compatible <= 1'b0;
        ss_restore_bgm_command <= 8'd0;
        ss_restore_bgm_argument <= 8'd0;
        ss_restore_bgm_valid <= 1'b0;
        ss_restore_v25_owner <= 1'b0;
    end else if (ss_select == 8'd1) begin
        if (ss_query) begin
            ss_global_data_out <= {8'd1, 22'd0, 2'd3, 32'd2};
            ss_global_ack <= 1'b1;
        end else if (ss_read) begin
            if (ss_addr[0])
                ss_global_data_out <= rom_crc64;
            else
                ss_global_data_out <= {
                    14'd0, sound_bgm_valid, sound_bgm_argument,
                    sound_bgm_command, v25_owner_reset_n_saved, ss_saved_ssp
                };
            ss_global_ack <= 1'b1;
        end else if (ss_write) begin
            if (ss_addr[0]) begin
                ss_restore_rom_signature <= ss_data;
                ss_restore_compatible <=
                    ss_format_valid && (ss_data == rom_crc64);
            end else begin
                ss_restore_ssp <= ss_data[31:0];
                ss_restore_v25_owner <= ss_data[32];
                ss_restore_bgm_command <= ss_data[40:33];
                ss_restore_bgm_argument <= ss_data[48:41];
                ss_restore_bgm_valid <= ss_data[49];
            end
            ss_global_ack <= 1'b1;
        end
    end
end

// Preserve the 68000-owned sound reset line across the temporary CPU reset
// used for architectural restore.
always_ff @(posedge clk) begin
    if (main_reset)
        v25_owner_reset_n_saved <= 1'b0;
    else if (ss_restore_commit)
        v25_owner_reset_n_saved <= ss_restore_v25_owner;
    else if (!ss_active)
        v25_owner_reset_n_saved <= v25_owner_reset_n_live;
end

// Knuckle Bash uses shared byte 1 as the command argument and byte 0 as the
// command/ack. Captured gameplay traffic matches Batsugun: argument 00 is
// durable BGM intent, while command 00 with argument 01 stops the music.
always_ff @(posedge clk) begin
    if (main_reset) begin
        sound_bgm_pending_argument <= 8'd0;
        sound_bgm_command <= 8'd0;
        sound_bgm_argument <= 8'd0;
        sound_bgm_valid <= 1'b0;
    end else if (ss_restore_commit) begin
        sound_bgm_pending_argument <= ss_restore_bgm_argument;
        sound_bgm_command <= ss_restore_bgm_command;
        sound_bgm_argument <= ss_restore_bgm_argument;
        sound_bgm_valid <= ss_restore_bgm_valid;
    end else if (shared_main_we) begin
        if (shared_main_addr == 11'd1) begin
            sound_bgm_pending_argument <= shared_main_din;
        end else if (shared_main_addr == 11'd0 && shared_main_din != 8'hff) begin
            if (shared_main_din == 8'h00 &&
                sound_bgm_pending_argument == 8'h01) begin
                sound_bgm_valid <= 1'b0;
            end else if (sound_bgm_pending_argument == 8'h00) begin
                sound_bgm_command <= shared_main_din;
                sound_bgm_argument <= sound_bgm_pending_argument;
                sound_bgm_valid <= 1'b1;
            end
        end
    end
end

assign main_ready = rom_valid && sdram_ready &&
                    !reset_game && !ioctl_download;
assign main_reset = reset_game || !rom_valid || !sdram_ready;
logic ss_main_hold_latched = 1'b0;
wire ss_main_hold = !ss_cpu_run &&
                    (ss_main_hold_latched || main_state_idle);
wire main_run = main_ready && video_snapshot_main_run && !pause &&
                !ss_main_hold;
wire video_renderer_reset = main_reset || video_snapshot_boundary || ss_video_reset;

// A state request may arrive in the middle of an acknowledged 68000 cycle.
// Let that cycle drain, then prevent the next one from starting. This keeps
// the private IRQ handler parked immediately after its SSP mailbox write and
// gives restore the same clean between-transactions acquisition point.
always_ff @(posedge clk) begin
    if (main_reset || ss_cpu_run)
        ss_main_hold_latched <= 1'b0;
    else if (main_state_idle)
        ss_main_hold_latched <= 1'b1;
end

wire gp_vint_set =
    !pause && !ss_active && pxl_cen && hcnt == 9'd0 && vcnt == 9'd230;

// Acquire the machine at the start of vertical blank, then let each domain
// drain to its own idle boundary in the controller's WAIT_HOLD phase. Requiring
// every independently clock-enabled domain to be idle on this single raster
// tick makes a legitimate request probabilistic and can starve it forever.
assign safe_boundary = state_boundary_tick;

knuckle_bash_savestate_controller u_ss_controller (
    .clk                ( clk                       ),
    .rst                ( main_reset                ),
    .safe_boundary      ( safe_boundary             ),
    .video_ready        ( video_snapshot_ready      ),
    .main_held          ( main_state_held            ),
    .sound_held         ( sound_state_held           ),
    .save_req           ( ss_save_req               ),
    .load_req           ( ss_load_req               ),
    .stream_busy        ( ss_stream_busy            ),
    .restore_compatible ( ss_restore_compatible     ),
    .restore_ssp        ( ss_restore_ssp            ),
    .cpu_ack            ( main_cpu_ack              ),
    .cpu_iack           ( main_cpu_iack             ),
    .cpu_rw             ( main_cpu_rw               ),
    .cpu_lds_n          ( main_cpu_lds_n            ),
    .cpu_fc             ( main_cpu_fc               ),
    .cpu_addr           ( main_cpu_addr             ),
    .cpu_dout           ( main_cpu_dout             ),
    .save_start         ( ss_save_start             ),
    .load_start         ( ss_load_start             ),
    .active             ( ss_active                 ),
    .ss_irq             ( ss_irq                    ),
    .ss_override        ( ss_override               ),
    .ss_reset           ( ss_cpu_reset              ),
    .cpu_run            ( ss_cpu_run                ),
    .device_hold        ( ss_device_hold            ),
    .video_reset        ( ss_video_reset            ),
    .restore_commit     ( ss_restore_commit         ),
    .saved_ssp          ( ss_saved_ssp              ),
    .reset_vector       ( ss_reset_vector           )
);

knuckle_bash_snapshot_control u_snapshot_control (
    .clk               ( clk                         ),
    .rst               ( main_reset || ss_video_reset ),
    .snapshot_prepare  ( video_snapshot_prepare      ),
    .snapshot_boundary ( video_snapshot_boundary     ),
    .main_idle         ( main_state_idle             ),
    .main_held         ( main_state_held             ),
    .gp_copy_busy      ( gp_snapshot_busy            ),
    .palette_copy_busy ( palette_snapshot_busy       ),
    .gp_copy_valid     ( gp_snapshot_valid           ),
    .palette_copy_valid( palette_snapshot_valid      ),
    .main_run          ( video_snapshot_main_run     ),
    .snapshot_start    ( video_snapshot_start        ),
    .snapshot_hold     ( video_snapshot_hold         ),
    .frame_valid       ( video_snapshot_frame_valid  ),
    .snapshot_miss     ( video_snapshot_control_miss )
);

knuckle_bash_gp9001_cpu u_gp9001_cpu (
    .clk           ( clk          ),
    .rst           ( main_reset   ),
    .flush         ( !main_ready  ),
    .req           ( gp_req       ),
    .rw            ( gp_rw        ),
    .addr          ( gp_addr      ),
    .wdata         ( gp_wdata     ),
    .be            ( gp_be        ),
    .accept        ( gp_accept    ),
    .done          ( gp_done      ),
    .rdata         ( gp_rdata     ),
    .idle          ( gp_idle      ),
    .vint_set      ( gp_vint_set  ),
    .status_bit    ( gp_status    ),
    .irq4          ( gp_irq4      ),
    .scan_addr     ( gp_snapshot_addr ),
    .scan_data     ( gp_snapshot_data ),
    .vram_pointer  (              ),
    .scroll_select (              ),
    .scrolls       ( gp_live_scrolls ),
    .scroll_flip   ( gp_live_scroll_flip ),
    .ss_restore_enable( ss_restore_compatible ),
    .ss_data       ( ss_data          ),
    .ss_addr       ( ss_addr          ),
    .ss_select     ( ss_select        ),
    .ss_write      ( ss_write         ),
    .ss_read       ( ss_read          ),
    .ss_query      ( ss_query         ),
    .ss_data_out   ( ss_gp_data_out   ),
    .ss_ack        ( ss_gp_ack        )
);

knuckle_bash_gp9001_snapshot u_gp9001_snapshot (
    .clk                 ( clk                 ),
    .rst                 ( main_reset || ss_video_reset ),
    .snapshot_start      ( video_snapshot_start),
    .source_addr         ( gp_snapshot_addr    ),
    .source_data         ( gp_snapshot_data    ),
    .source_scrolls      ( gp_live_scrolls     ),
    .source_scroll_flip  ( gp_live_scroll_flip ),
    .display_addr        ( video_vram_addr     ),
    .display_data        ( video_vram_data     ),
    .object_addr         ( video_object_addr   ),
    .object_data         ( video_object_data   ),
    .display_scrolls     ( video_scrolls       ),
    .display_scroll_flip ( video_scroll_flip   ),
    .copy_busy           ( gp_snapshot_busy    ),
    .snapshot_valid      ( gp_snapshot_valid   ),
    .copy_miss           ( gp_snapshot_miss    )
);

knuckle_bash_palette_snapshot u_palette_snapshot (
    .clk            ( clk                      ),
    .rst            ( main_reset || ss_video_reset ),
    .snapshot_start ( video_snapshot_start     ),
    .source_addr    ( palette_snapshot_addr    ),
    .source_data    ( palette_snapshot_data    ),
    .display_addr   ( video_palette_addr       ),
    .display_data   ( video_palette_data       ),
    .copy_busy      ( palette_snapshot_busy    ),
    .snapshot_valid ( palette_snapshot_valid   ),
    .copy_miss      ( palette_snapshot_miss    )
);

knuckle_bash_gp9001_video u_gp9001_video (
    .clk                      ( clk                       ),
    .rst                      ( video_renderer_reset      ),
    .line_start               ( video_line_start          ),
    .line_commit              ( video_line_commit         ),
    .target_y                 ( video_target_y            ),
    .target_epoch             ( video_target_epoch        ),
    .display_x                ( hcnt                      ),
    .display_y                ( vcnt                      ),
    .display_epoch            ( video_epoch               ),
    .scrolls                  ( video_scrolls             ),
    .scroll_flip              ( video_scroll_flip         ),
    .vram_addr                ( video_vram_addr           ),
    .vram_data                ( video_vram_data           ),
    .object_addr              ( video_object_addr         ),
    .object_data              ( video_object_data         ),
    .tile_gfx_req             ( gp_tile_req               ),
    .tile_gfx_addr            ( gp_tile_addr              ),
    .tile_gfx_data            ( gp_tile_data              ),
    .tile_gfx_ok              ( gp_tile_ok                ),
    .object_gfx_req           ( gp_object_req             ),
    .object_gfx_addr          ( gp_object_addr            ),
    .object_gfx_data          ( gp_object_data            ),
    .object_gfx_ok            ( gp_object_ok              ),
    .line_ready               ( video_line_ready          ),
    .pixel_valid              ( video_pixel_valid         ),
    .final_color              ( video_palette_addr        ),
    .engine_busy              ( video_engine_busy         ),
    .deadline_miss            ( video_deadline_miss       ),
    .object_capacity_overflow ( video_object_overflow     ),
    .tile_cycles              ( video_tile_cycles         ),
    .object_cycles            ( video_object_cycles       ),
    .debug_tile_y             (                           ),
    .debug_object_y           (                           ),
    .debug_line_epoch         (                           ),
    .debug_line_valid         (                           )
);

knuckle_bash_main u_main (
    .clk                      ( clk                      ),
    .reset                    ( main_reset               ),
    .run                      ( main_run                 ),
    .txn_flush                ( !main_ready              ),
    .irq4                     ( gp_irq4                  ),
    .ss_irq                   ( ss_irq                   ),
    .ss_override              ( ss_override              ),
    .ss_reset                 ( ss_cpu_reset              ),
    .ss_reset_vector          ( ss_reset_vector           ),
    .ss_restore_enable        ( ss_restore_compatible     ),
    .ss_data                  ( ss_data                   ),
    .ss_addr                  ( ss_addr                   ),
    .ss_select                ( ss_select                 ),
    .ss_write                 ( ss_write                  ),
    .ss_read                  ( ss_read                   ),
    .ss_query                 ( ss_query                  ),
    .ss_data_out              ( ss_main_data_out          ),
    .ss_ack                   ( ss_main_ack               ),
    .hs_reset                 ( reset_cold || (ioctl_download && ioctl_index == 16'd0) ),
    .hs_set_id                ( rom_set_id               ),
    .hs_download              ( hs_download              ),
    .hs_upload                ( ioctl_upload             ),
    .hs_wr                    ( ioctl_wr                 ),
    .hs_rd                    ( ioctl_rd                 ),
    .hs_addr                  ( ioctl_addr               ),
    .hs_data                  ( ioctl_data               ),
    .hs_index                 ( ioctl_index              ),
    .hs_ss_active             ( ss_active                ),
    .hs_din                   ( hs_din                   ),
    .hs_wait                  ( hs_wait                  ),
    .hs_dirty                 ( hs_dirty                 ),
    .hs_active                ( hs_active                ),
    .player1                  ( player1_inputs           ),
    .player2                  ( player2_inputs           ),
    .system                   ( system_inputs            ),
    .vcount_data              ( vdp_count_data           ),
    .rom_req                  ( main_rom_req             ),
    .rom_addr                 ( main_rom_addr            ),
    .rom_ok                   ( main_rom_ok              ),
    .rom_data                 ( main_rom_data            ),
    .gp_req                   ( gp_req                   ),
    .gp_rw                    ( gp_rw                    ),
    .gp_addr                  ( gp_addr                  ),
    .gp_wdata                 ( gp_wdata                 ),
    .gp_be                    ( gp_be                    ),
    .gp_accept                ( gp_accept                ),
    .gp_done                  ( gp_done                  ),
    .gp_rdata                 ( gp_rdata                 ),
    .gp_idle                  ( gp_idle                  ),
    .palette_scan_addr       ( palette_snapshot_addr    ),
    .palette_scan_data       ( palette_snapshot_data    ),
    .shared_addr              ( shared_main_addr         ),
    .shared_din               ( shared_main_din          ),
    .shared_we                ( shared_main_we           ),
    .shared_dout              ( shared_main_dout         ),
    .coin_control             ( coin_control             ),
    .v25_owner_reset_n        ( v25_owner_reset_n_live   ),
    .state_idle               ( main_state_idle          ),
    .state_held               ( main_state_held          ),
    .debug_cpu_cen            (                          ),
    .debug_cpu_cenb           (                          ),
    .debug_cpu_dtack_n        (                          ),
    .debug_cpu_bus_active     (                          ),
    .debug_cpu_ack_now        ( main_cpu_ack             ),
    .debug_cpu_iack           ( main_cpu_iack            ),
    .debug_cpu_rw             ( main_cpu_rw              ),
    .debug_cpu_as_n           (                          ),
    .debug_cpu_uds_n          ( main_cpu_uds_n           ),
    .debug_cpu_lds_n          ( main_cpu_lds_n           ),
    .debug_cpu_fc             ( main_cpu_fc              ),
    .debug_cpu_addr           ( main_cpu_addr            ),
    .debug_cpu_dout           ( main_cpu_dout            ),
    .debug_cpu_din            (                          ),
    .debug_ack_count          (                          ),
    .debug_unmapped_ack_count (                          )
);

knuckle_bash_sound_roms u_sound_roms (
    .clk            ( clk            ),
    .ioctl_download ( ioctl_download ),
    .ioctl_wr       ( ioctl_wr       ),
    .ioctl_addr     ( ioctl_addr     ),
    .ioctl_data     ( ioctl_data     ),
    .ioctl_index    ( ioctl_index    ),
    .v25_rom_addr   ( v25_rom_addr   ),
    .v25_rom_data   ( v25_rom_data   )
);

knuckle_bash_shared_ram u_shared_ram (
    .clk        ( clk               ),
    .main_addr  ( shared_main_addr  ),
    .main_din   ( shared_main_din   ),
    .main_we    ( shared_main_we    ),
    .main_dout  ( shared_main_dout  ),
    .sound_addr ( shared_sound_addr ),
    .sound_din  ( shared_sound_dout ),
    .sound_we   ( shared_sound_we   ),
    .sound_dout ( shared_sound_din  ),
    .ss_restore_enable( ss_restore_compatible ),
    .ss_data    ( ss_data           ),
    .ss_addr    ( ss_addr           ),
    .ss_select  ( ss_select         ),
    .ss_write   ( ss_write          ),
    .ss_read    ( ss_read           ),
    .ss_query   ( ss_query          ),
    .ss_data_out( ss_shared_data_out),
    .ss_ack     ( ss_shared_ack     )
);

knuckle_bash_sound u_sound (
    .clk               ( clk                  ),
    .reset             ( reset_game           ),
    .v25_cen           ( v25_cen              ),
    .opm_cen           ( opm_cen              ),
    .oki_cen           ( oki_cen              ),
    .v25_enable        ( main_ready            ),
    .v25_owner_reset_n ( v25_owner_reset_n_saved ),
    .dip_a             ( dipsw[ 7: 0]         ),
    .dip_b             ( dipsw[15: 8]         ),
    .region            ( dipsw[23:16]         ),
    .fm_enable         ( !status[9]           ),
    .fx_enable         ( !status[8]           ),
    .fx_level          ( 2'b10 ^ status[7:6]  ),
    .state_hold        ( ss_device_hold       ),
    .pause             ( pause                ),
    .ss_restore_enable ( ss_restore_compatible),
    .ss_restore_commit ( ss_restore_commit    ),
    .ss_restore_bgm_valid( ss_restore_bgm_valid ),
    .ss_restore_bgm_command( ss_restore_bgm_command ),
    .ss_restore_bgm_argument( ss_restore_bgm_argument ),
    .ss_data           ( 64'd0                ),
    .ss_addr           ( 32'd0                ),
    .ss_select         ( 8'd0                 ),
    .ss_write          ( 1'b0                 ),
    .ss_read           ( 1'b0                 ),
    .ss_query          ( 1'b0                 ),
    .ss_data_out       ( ss_sound_data_out    ),
    .ss_ack            ( ss_sound_ack         ),
    .shared_addr       ( shared_sound_addr    ),
    .shared_dout       ( shared_sound_dout    ),
    .shared_we         ( shared_sound_we      ),
    .shared_din        ( shared_sound_din     ),
    .v25_rom_addr      ( v25_rom_addr         ),
    .v25_rom_data      ( v25_rom_data         ),
    .oki_rom_addr      ( oki_rom_addr         ),
    .oki_rom_data      ( oki_rom_data         ),
    .oki_rom_ok        ( oki_rom_ok           ),
    .audio_l           ( audio_l              ),
    .audio_r           ( audio_r              ),
    .sample            ( sound_sample         ),
    .debug_fault       ( sound_debug_fault    ),
    .debug_halted      ( sound_debug_halted   ),
    .debug_pc          ( sound_debug_pc       ),
    .state_idle        ( sound_state_idle     ),
    .state_held        ( sound_state_held     ),
    .debug_ym_write    ( sound_debug_ym_write ),
    .debug_ym_a0       ( sound_debug_ym_a0    ),
    .debug_ym_data     ( sound_debug_ym_data  ),
    .debug_oki_write   ( sound_debug_oki_write),
    .debug_oki_data    ( sound_debug_oki_data )
);

// True renderer failures are sticky until the gameplay reset. A pause may
// intentionally interrupt an in-flight snapshot acquisition, so its transient
// ownership/deadline flags are not renderer failures. Object-capacity
// saturation is recoverable bounded rendering with its own telemetry; it must
// not turn legitimate boot diagnostics into a permanent magenta output.
always_ff @(posedge clk or posedge main_reset) begin
    if (main_reset) begin
        video_renderer_fault <= 1'b0;
    end else if (!pause && !ss_active &&
                 (video_snapshot_control_miss ||
                  gp_snapshot_miss ||
                  palette_snapshot_miss ||
                  (|video_deadline_miss) ||
                  (video_snapshot_hold &&
                   (main_run || !main_state_held)))) begin
        video_renderer_fault <= 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (reset_game) begin
        red <= 8'd0;
        green <= 8'd0;
        blue <= 8'd0;
        hs <= 1'b1;
        vs <= 1'b1;
        de <= 1'b0;
        hblank <= 1'b1;
        vblank <= 1'b1;
    end else if (pxl_cen) begin
        hs <= hsync_n;
        vs <= vsync_n;
        de <= visible;
        hblank <= hcnt >= 9'd320;
        vblank <= vcnt >= 9'd240;
        if (!visible) begin
            red <= 8'd0;
            green <= 8'd0;
            blue <= 8'd0;
        end else if (!rom_valid) begin
            red <= {hcnt[4:0], 3'b000};
            green <= {vcnt[4:0], 3'b000};
            blue <= 8'h30;
        end else if (video_renderer_fault) begin
            red <= 8'hff;
            green <= 8'h00;
            blue <= 8'hff;
        end else if (!video_snapshot_ready ||
                     !video_line_ready ||
                     !video_pixel_valid) begin
            red <= 8'h00;
            green <= 8'h00;
            blue <= 8'h00;
        end else begin
            red <= {
                video_palette_data[4:0],
                video_palette_data[4:2]
            };
            green <= {
                video_palette_data[9:5],
                video_palette_data[9:7]
            };
            blue <= {
                video_palette_data[14:10],
                video_palette_data[14:12]
            };
        end
    end
end

endmodule
