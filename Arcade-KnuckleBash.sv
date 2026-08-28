// SPDX-License-Identifier: GPL-2.0-or-later
//
// Knuckle Bash MiSTer shell. This starts from the proven Batsugun/Dogyuun OSD
// contract while the board-local implementation is brought up underneath it.

module emu
(
    `include "sys/emu_ports.vh"
);

`include "build_id.v"
localparam CONF_STR = {
    "KNUCKLEBASH;SS3E000000:400000;",
    "P1,Video Settings;",
    "H0P1OGH,Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
    "H4P1o78,Rotate Screen,No (Original),Yes,No (Flip);",
    "P1-;",
    "d3P1O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
    "P1-;",
    "P1oLO,CRT H Offset,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P1oPS,CRT V Offset,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P1oG,CRT Scale Enable,Off,On;",
    "H2P1oHK,CRT scale factor,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
    "P1-;",
    "d5P1o9,Vertical Crop,Disabled,216p(5x);",
    "d5P1oAD,Crop Offset,0,2,4,8,10,12,-12,-10,-8,-6,-4,-2;",
    "P1oEF,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
    "DIP;",
    "-;",
    "o5,User Port,Off,DB15 Joystick;",
    "O67,FX Volume, High, Very High, Very Low, Low;",
    "O8,FX,On,Off;",
    "O9,FM,On,Off;",
    "-;",
    "O[65:64],Savestate Slot,1,2,3,4;",
    "O[66],Autoincrement Slot,Off,On;",
    "R[67],Save state (Alt-F1);",
    "R[68],Restore state (F1);",
    "-;",
    "O[69],Autosave NVRAM,Off,On;",
    "T[70],Save NVRAM;",
    "-;",
    "R0,Reset;",
    "I,",
    "Load=DPAD Up|Save=Down|Slot=L+R,",
    "Active Slot 1,",
    "Active Slot 2,",
    "Active Slot 3,",
    "Active Slot 4,",
    "Save to state 1,",
    "Restore state 1,",
    "Save to state 2,",
    "Restore state 2,",
    "Save to state 3,",
    "Restore state 3,",
    "Save to state 4,",
    "Restore state 4;",
    "V,v",`BUILD_DATE
};

wire clk_47, clk_47sh, clk_27, clk_6p75, clk_94, clk_94sh;
wire clk_sys = clk_94;
wire clk_rom = clk_94;
wire pll_locked;

raizingpll pll (
    .refclk   ( CLK_50M    ),
    .rst      ( RESET      ),
    .outclk_0 ( clk_47     ),
    .outclk_1 ( clk_47sh   ),
    .outclk_2 ( clk_27     ),
    .outclk_3 ( clk_6p75   ),
    .outclk_4 ( clk_94     ),
    .outclk_5 ( clk_94sh   ),
    .locked   ( pll_locked )
);

wire [31:0] joyusb_1_full;
wire [31:0] joyusb_2_full;
wire [31:0] joyusb_3_full;
wire [31:0] joyusb_4_full;
wire [31:0] joyusb_5_full;
wire [31:0] joyusb_6_full;
wire [15:0] joyana_l1, joyana_l2, joyana_l3, joyana_l4, joyana_l5, joyana_l6;
wire [15:0] joyana_r1, joyana_r2, joyana_r3, joyana_r4, joyana_r5, joyana_r6;
wire [ 7:0] raw_paddle_1, raw_paddle_2, raw_paddle_3, raw_paddle_4, raw_paddle_5, raw_paddle_6;
wire [ 8:0] raw_spinner_1, raw_spinner_2, raw_spinner_3, raw_spinner_4, raw_spinner_5, raw_spinner_6;
wire [10:0] ps2_key;
wire [ 1:0] buttons;
wire [127:0] status;
wire [ 1:0] ss_slot;
wire        ss_save;
wire        ss_load;
wire        ss_info_req;
wire [ 7:0] ss_info;
wire        ss_status_set;
// The schema/controller reservation is not yet a state transport. Keep the
// user-facing save/load controls disabled until every live client can quiesce
// and serialize transactionally.
wire        savestate_ready = 1'b0;
wire [15:0] status_menumask;
wire [127:0] status_in = {status[127:66], ss_slot, status[63:0]};

wire        hps_download;
wire        hps_upload;
wire        hps_wr;
wire        hps_rd;
wire [7:0]  hs_nvram_din;
wire        hs_nvram_wait, hs_dirty, hs_active;
reg         hs_upload_req = 0, hs_osd_status_d = 0, hs_manual_save_d = 0;
wire [26:0] hps_addr;
wire [ 7:0] hps_dout;
wire [15:0] hps_index;
wire        rom_download = hps_download && (hps_index == 16'd0);
wire [21:0] gamma_bus;
wire        direct_video;
wire        forced_scandoubler;
wire        video_rotated;
wire        video_mode_refresh;
wire        sdram_ioctl_wait;
wire        sdram_runtime_ready;
wire        sdram_init;
wire        sdram_download_drained;
wire        sdram_program_mode;
wire        sdram_loader_range_error;
wire        sdram_loader_overflow_error;

wire        game_rom_valid;
wire        main_rom_req;
wire [17:0] main_rom_addr;
wire [15:0] main_rom_data;
wire        main_rom_ok;
wire        gp_tile_req;
wire [21:0] gp_tile_addr;
wire [15:0] gp_tile_data;
wire        gp_tile_ok;
wire        gp_object_req;
wire [21:0] gp_object_addr;
wire [15:0] gp_object_data;
wire        gp_object_ok;
wire [17:0] oki_rom_addr;
wire [ 7:0] oki_rom_data;
wire        oki_rom_ok;

hps_io #(
    .CONF_STR ( CONF_STR ),
    .PS2DIV   ( 32       ),
    .WIDE     ( 0        ),
    .BLKSZ    ( 1        )
) hps_io (
    .clk_sys              ( clk_rom          ),
    // Upper video-measurement bits are inputs to hps_io. Keep them on the
    // unadjusted HDMI stream; lower protocol/inout bits stay connected intact.
    .HPS_BUS              ( {HPS_BUS[45:43], clk_sys,
                            hdmi_measure_ce, hdmi_measure_de,
                            hdmi_measure_hs, hdmi_measure_vs, HPS_BUS[37:0]} ),
    .buttons              ( buttons          ),
    .status               ( status           ),
    .status_in            ( status_in        ),
    .status_set           ( ss_status_set    ),
    .status_menumask      ( status_menumask  ),
    .gamma_bus            ( gamma_bus        ),
    .direct_video         ( direct_video     ),
    .forced_scandoubler   ( forced_scandoubler ),
    .video_rotated        ( video_rotated    ),
    .new_vmode            ( video_mode_refresh ),
    .ioctl_download       ( hps_download     ),
    .ioctl_upload         ( hps_upload       ),
    .ioctl_wr             ( hps_wr           ),
    .ioctl_rd             ( hps_rd           ),
    .ioctl_addr           ( hps_addr         ),
    .ioctl_dout           ( hps_dout         ),
    .ioctl_index          ( hps_index        ),
    .ioctl_wait           ( sdram_ioctl_wait | hs_nvram_wait ),
    .ioctl_upload_req     ( hs_upload_req    ),
    .ioctl_upload_index   ( 8'd2             ),
    .ioctl_din            ( hs_nvram_din     ),
    .joystick_0           ( joyusb_1_full    ),
    .joystick_1           ( joyusb_2_full    ),
    .joystick_2           ( joyusb_3_full    ),
    .joystick_3           ( joyusb_4_full    ),
    .joystick_4           ( joyusb_5_full    ),
    .joystick_5           ( joyusb_6_full    ),
    .joystick_l_analog_0  ( joyana_l1        ),
    .joystick_l_analog_1  ( joyana_l2        ),
    .joystick_l_analog_2  ( joyana_l3        ),
    .joystick_l_analog_3  ( joyana_l4        ),
    .joystick_l_analog_4  ( joyana_l5        ),
    .joystick_l_analog_5  ( joyana_l6        ),
    .joystick_r_analog_0  ( joyana_r1        ),
    .joystick_r_analog_1  ( joyana_r2        ),
    .joystick_r_analog_2  ( joyana_r3        ),
    .joystick_r_analog_3  ( joyana_r4        ),
    .joystick_r_analog_4  ( joyana_r5        ),
    .joystick_r_analog_5  ( joyana_r6        ),
    .joystick_0_rumble    ( 16'd0            ),
    .joystick_1_rumble    ( 16'd0            ),
    .joystick_2_rumble    ( 16'd0            ),
    .joystick_3_rumble    ( 16'd0            ),
    .joystick_4_rumble    ( 16'd0            ),
    .joystick_5_rumble    ( 16'd0            ),
    .paddle_0             ( raw_paddle_1     ),
    .paddle_1             ( raw_paddle_2     ),
    .paddle_2             ( raw_paddle_3     ),
    .paddle_3             ( raw_paddle_4     ),
    .paddle_4             ( raw_paddle_5     ),
    .paddle_5             ( raw_paddle_6     ),
    .spinner_0            ( raw_spinner_1    ),
    .spinner_1            ( raw_spinner_2    ),
    .spinner_2            ( raw_spinner_3    ),
    .spinner_3            ( raw_spinner_4    ),
    .spinner_4            ( raw_spinner_5    ),
    .spinner_5            ( raw_spinner_6    ),
    .ps2_key              ( ps2_key          ),
    .info_req             ( ss_info_req      ),
    .info                 ( ss_info          ),
    .EXT_BUS              (                  )
);

wire cold_reset_request = RESET | ~pll_locked;
wire cold_reset;
wire game_reset_request =
    cold_reset | status[0] | buttons[1] | rom_download;
wire game_reset;

// Match Batsugun: automatic save when opening OSD, plus an explicit command.
always @(posedge clk_sys) begin
    hs_osd_status_d <= OSD_STATUS;
    hs_manual_save_d <= status[70];
    if (cold_reset || rom_download) begin
        hs_upload_req <= 0;
        hs_osd_status_d <= 0;
        hs_manual_save_d <= 0;
    end else begin
        hs_upload_req <= (status[69] && hs_dirty && OSD_STATUS && !hs_osd_status_d) ||
                         (status[70] && !hs_manual_save_d);
    end
end

knuckle_bash_reset_sync u_reset_cold (
    .clk         ( clk_sys            ),
    .async_reset ( cold_reset_request ),
    .reset_out   ( cold_reset         )
);

knuckle_bash_reset_sync u_reset_game (
    .clk         ( clk_sys            ),
    .async_reset ( game_reset_request ),
    .reset_out   ( game_reset         )
);

knuckle_bash_sdram u_sdram_mem (
    .clk                   ( clk_sys                     ),
    .clk_sdram             ( clk_94sh                    ),
    .controller_reset      ( cold_reset                  ),
    .runtime_reset         ( game_reset                  ),
    .runtime_enable        ( game_rom_valid              ),
    .ioctl_download        ( rom_download                ),
    .ioctl_wr              ( hps_wr                      ),
    .ioctl_addr            ( hps_addr                    ),
    .ioctl_data            ( hps_dout                    ),
    .ioctl_index           ( hps_index                   ),
    .ioctl_wait            ( sdram_ioctl_wait            ),
    .sdram_init            ( sdram_init                  ),
    .download_drained      ( sdram_download_drained      ),
    .program_mode          ( sdram_program_mode          ),
    .runtime_ready         ( sdram_runtime_ready         ),
    .loader_range_error    ( sdram_loader_range_error    ),
    .loader_overflow_error ( sdram_loader_overflow_error ),
    .main_rom_addr         ( main_rom_addr               ),
    .main_rom_cs           ( main_rom_req                ),
    .main_rom_data         ( main_rom_data               ),
    .main_rom_ok           ( main_rom_ok                 ),
    .gp_tile_addr          ( gp_tile_addr                ),
    .gp_tile_cs            ( gp_tile_req                 ),
    .gp_tile_data          ( gp_tile_data                ),
    .gp_tile_ok            ( gp_tile_ok                  ),
    .gp_object_addr        ( gp_object_addr              ),
    .gp_object_cs          ( gp_object_req               ),
    .gp_object_data        ( gp_object_data              ),
    .gp_object_ok          ( gp_object_ok                ),
    .oki_rom_addr          ( oki_rom_addr                ),
    .oki_rom_data          ( oki_rom_data                ),
    .oki_rom_ok            ( oki_rom_ok                  ),
    .SDRAM_CLK             ( SDRAM_CLK                   ),
    .SDRAM_DQ              ( SDRAM_DQ                    ),
    .SDRAM_A               ( SDRAM_A                     ),
    .SDRAM_BA              ( SDRAM_BA                    ),
    .SDRAM_DQML            ( SDRAM_DQML                  ),
    .SDRAM_DQMH            ( SDRAM_DQMH                  ),
    .SDRAM_nWE             ( SDRAM_nWE                   ),
    .SDRAM_nCAS            ( SDRAM_nCAS                  ),
    .SDRAM_nRAS            ( SDRAM_nRAS                  ),
    .SDRAM_nCS             ( SDRAM_nCS                   ),
    .SDRAM_CKE             ( SDRAM_CKE                   )
);

wire [31:0] ss_joystick = joyusb_1_full | joyusb_2_full;

savestate_ui #(.INFO_TIMEOUT_BITS(25)) u_savestate_ui (
    .clk            ( clk_rom          ),
    .ps2_key        ( ps2_key          ),
    .allow_ss       ( savestate_ready && !hs_active ),
    .joySS          ( ss_joystick[13]  ),
    .joyRight       ( ss_joystick[0]   ),
    .joyLeft        ( ss_joystick[1]   ),
    .joyDown        ( ss_joystick[2]   ),
    .joyUp          ( ss_joystick[3]   ),
    .joyStart       ( 1'b0             ),
    .joyRewind      ( 1'b0             ),
    .rewindEnable   ( 1'b0             ),
    .status_slot    ( status[65:64]    ),
    .autoincslot    ( status[66]       ),
    .OSD_saveload   ( status[68:67]    ),
    .ss_save        ( ss_save          ),
    .ss_load        ( ss_load          ),
    .ss_info_req    ( ss_info_req      ),
    .ss_info        ( ss_info          ),
    .statusUpdate   ( ss_status_set    ),
    .selected_slot  ( ss_slot          )
);

wire [7:0] game_r, game_g, game_b;
wire       game_hs, game_vs, game_de, game_pxl_cen;
wire       game_hblank, game_vblank;
wire       ss_active;
wire signed [15:0] game_audio_l, game_audio_r;

knuckle_bash_game u_game (
    .clk              ( clk_sys       ),
    .reset_cold       ( cold_reset    ),
    .reset_game       ( game_reset    ),
    .status           ( status        ),
    .joy1             ( joyusb_1_full ),
    .joy2             ( joyusb_2_full ),
    .ioctl_download   ( rom_download  ),
    .ioctl_wr         ( hps_wr        ),
    .ioctl_addr       ( hps_addr      ),
    .ioctl_data       ( hps_dout      ),
    .ioctl_index      ( hps_index     ),
    .ioctl_upload     ( hps_upload    ),
    .hs_download      ( hps_download  ),
    .ioctl_rd         ( hps_rd        ),
    .hs_din           ( hs_nvram_din  ),
    .hs_wait          ( hs_nvram_wait ),
    .hs_dirty         ( hs_dirty      ),
    .hs_active        ( hs_active     ),
    .sdram_ready      ( sdram_runtime_ready ),
    .rom_valid_out    ( game_rom_valid ),
    .main_rom_req     ( main_rom_req  ),
    .main_rom_addr    ( main_rom_addr ),
    .main_rom_data    ( main_rom_data ),
    .main_rom_ok      ( main_rom_ok   ),
    .gp_tile_req      ( gp_tile_req   ),
    .gp_tile_addr     ( gp_tile_addr  ),
    .gp_tile_data     ( gp_tile_data  ),
    .gp_tile_ok       ( gp_tile_ok    ),
    .gp_object_req    ( gp_object_req ),
    .gp_object_addr   ( gp_object_addr),
    .gp_object_data   ( gp_object_data),
    .gp_object_ok     ( gp_object_ok  ),
    .oki_rom_addr     ( oki_rom_addr  ),
    .oki_rom_data     ( oki_rom_data  ),
    .oki_rom_ok       ( oki_rom_ok    ),
    .ss_save_req      ( ss_save       ),
    .ss_load_req      ( ss_load       ),
    .ss_active        ( ss_active     ),
    .red              ( game_r        ),
    .green            ( game_g        ),
    .blue             ( game_b        ),
    .hs               ( game_hs       ),
    .vs               ( game_vs       ),
    .de               ( game_de       ),
    .hblank           ( game_hblank   ),
    .vblank           ( game_vblank   ),
    .pxl_cen          ( game_pxl_cen  ),
    .audio_l          ( game_audio_l  ),
    .audio_r          ( game_audio_r  )
);

assign CLK_VIDEO = clk_sys;
wire hdmi_measure_ce, hdmi_measure_hs, hdmi_measure_vs, hdmi_measure_de;
knuckle_bash_video u_video (
    .clk(clk_sys), .reset(game_reset), .status(status[63:0]),
    .pxl_cen(game_pxl_cen), .red(game_r), .green(game_g), .blue(game_b),
    .hs_n(game_hs), .vs_n(game_vs),
    .hblank(game_hblank), .vblank(game_vblank),
    .direct_video(direct_video), .forced_scandoubler(forced_scandoubler),
    .hdmi_width(HDMI_WIDTH), .hdmi_height(HDMI_HEIGHT), .gamma_bus(gamma_bus),
    .ce_pixel(CE_PIXEL), .vga_r(VGA_R), .vga_g(VGA_G), .vga_b(VGA_B),
    .vga_hs(VGA_HS), .vga_vs(VGA_VS), .vga_de(VGA_DE), .vga_sl(VGA_SL),
    .hdmi_ce(hdmi_measure_ce), .hdmi_hs(hdmi_measure_hs),
    .hdmi_vs(hdmi_measure_vs), .hdmi_de(hdmi_measure_de),
    .video_arx(VIDEO_ARX), .video_ary(VIDEO_ARY),
    .video_rotated(video_rotated), .new_vmode(video_mode_refresh),
    .menu_mask(status_menumask),
`ifdef MISTER_FB
    .fb_en(FB_EN), .fb_format(FB_FORMAT),
    .fb_force_blank(FB_FORCE_BLANK),
    .fb_width(FB_WIDTH), .fb_height(FB_HEIGHT),
    .fb_base(FB_BASE), .fb_stride(FB_STRIDE), .fb_vbl(FB_VBL), .fb_ll(FB_LL),
`else
    .fb_en(), .fb_format(), .fb_width(), .fb_height(),
    .fb_force_blank(),
    .fb_base(), .fb_stride(), .fb_vbl(1'b0), .fb_ll(1'b0),
`endif
    .ddram_busy(DDRAM_BUSY), .ddram_burstcnt(DDRAM_BURSTCNT),
    .ddram_addr(DDRAM_ADDR), .ddram_din(DDRAM_DIN), .ddram_be(DDRAM_BE),
    .ddram_we(DDRAM_WE), .ddram_rd(DDRAM_RD)
);
assign VGA_F1    = 1'b0;
assign VGA_SCALER = 1'b0;
assign VGA_DISABLE = 1'b0;
assign HDMI_FREEZE = ss_active;
assign HDMI_BLACKOUT = 1'b0;
assign HDMI_BOB_DEINT = 1'b0;

assign AUDIO_L = game_audio_l;
assign AUDIO_R = game_audio_r;
assign AUDIO_S = 1'b1;
assign AUDIO_MIX = 2'b00;

assign LED_USER = rom_download;
assign LED_POWER = 2'b00;
assign LED_DISK = 2'b00;
assign BUTTONS = 2'b00;

assign DDRAM_CLK = clk_sys;

assign ADC_BUS = 4'bzzzz;
assign {SD_SCK, SD_MOSI, SD_CS} = 3'b111;
assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
assign USER_OUT = status[5] ? 7'h7f : 7'h7f;

endmodule
