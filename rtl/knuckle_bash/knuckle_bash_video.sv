// SPDX-License-Identifier: GPL-2.0-or-later
// Separate native analog and HDMI display paths. CRT controls never enter
// the HDMI pixel/geometry/measurement pipeline.
// All game timing remains upstream of this module, including VDP/IRQ timing.
module knuckle_bash_video #(
    parameter integer REFRESH_FRAMES = 60
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [63:0] status,
    input  logic        pxl_cen,
    input  logic [7:0]  red, green, blue,
    input  logic        hs_n, vs_n, hblank, vblank,
    input  logic        direct_video,
    input  logic        forced_scandoubler,
    input  logic [11:0] hdmi_width, hdmi_height,
    inout  wire  [21:0] gamma_bus,
    output wire         ce_pixel,
    output wire  [7:0]  vga_r, vga_g, vga_b,
    output wire         vga_hs, vga_vs, vga_de,
    output wire         hdmi_ce, hdmi_hs, hdmi_vs, hdmi_de,
    output wire  [1:0]  vga_sl,
    output wire  [12:0] video_arx, video_ary,
    output wire         video_rotated,
    output logic        new_vmode,
    output logic [15:0] menu_mask,
    output wire         fb_en,
    output wire         fb_force_blank,
    output wire  [4:0]  fb_format,
    output wire  [11:0] fb_width, fb_height,
    output wire  [31:0] fb_base,
    output wire  [13:0] fb_stride,
    input  logic        fb_vbl, fb_ll,
    input  logic        ddram_busy,
    output wire  [7:0]  ddram_burstcnt,
    output wire  [28:0] ddram_addr,
    output wire  [63:0] ddram_din,
    output wire  [7:0]  ddram_be,
    output wire         ddram_we, ddram_rd
);
// Sample the game's registered RGB/blanking after its pixel edge. The /14
// input cadence also supplies a phase-locked 2x enable for jtframe_hsize.
logic [3:0] phase;
logic pixel_started;
wire ce_input = pixel_started && phase == 4'd0;
wire ce_size  = pixel_started && phase == 4'd1;
wire ce_size2 = pixel_started && (phase == 4'd1 || phase == 4'd8);
wire ce_mix   = pixel_started && phase == 4'd2;
always_ff @(posedge clk) begin
    if (reset) begin
        phase <= 4'd13;
        pixel_started <= 0;
    end else if (pxl_cen) begin
        phase <= 0;
        pixel_started <= 1;
    end else if (phase != 4'd13) phase <= phase + 4'd1;
end

// Commit video fields in vertical blank, never part-way through a picture.
logic [63:0] video_status;
logic last_vs;
always_ff @(posedge clk) begin
    if (reset) begin
        video_status <= 0;
        last_vs <= 1;
    end else if (ce_input) begin
        last_vs <= vs_n;
        if (vs_n && !last_vs) video_status <= status;
    end
end

// Native-first menu ordering is deliberate for this horizontal ROT0 game.
wire rotate = !direct_video && video_status[40:39] == 2'd1;
wire flip = !direct_video && video_status[40:39] == 2'd2;
wire [2:0] requested_fx = video_status[5:3];
wire [2:0] video_fx = rotate ? 3'd0 :
                      (requested_fx <= 3'd4 ? requested_fx : 3'd0);
wire [2:0] scale = {1'b0, video_status[47:46]};
wire crop_ok = hdmi_width == 12'd1920 && hdmi_height == 12'd1080 &&
               video_fx == 0 && !forced_scandoubler && scale == 0 &&
               !direct_video && !rotate;
wire [11:0] crop_size = (crop_ok && video_status[41]) ? 12'd216 : 12'd0;
logic signed [4:0] crop_off;
always_comb begin
    case (video_status[45:42])
        4'd0: crop_off =  5'sd0;
        4'd1: crop_off =  5'sd2;
        4'd2: crop_off =  5'sd4;
        4'd3: crop_off =  5'sd8;
        4'd4: crop_off =  5'sd10;
        4'd5: crop_off =  5'sd12;
        4'd6: crop_off = -5'sd12;
        4'd7: crop_off = -5'sd10;
        4'd8: crop_off = -5'sd8;
        4'd9: crop_off = -5'sd6;
        4'd10: crop_off = -5'sd4;
        default: crop_off = -5'sd2;
    endcase
    menu_mask = 16'd0;
    menu_mask[0] = direct_video;
    menu_mask[2] = !video_status[48];
    menu_mask[3] = rotate;
    menu_mask[4] = direct_video;
    menu_mask[5] = !crop_ok;
end

wire resync_hs, resync_vs;
knuckle_bash_resync u_resync (
    .clk(clk), .reset(reset), .pxl_cen(ce_input),
    .hs_in(hs_n), .vs_in(vs_n), .lhbl(!hblank), .lvbl(!vblank),
    .hoffset(video_status[56:53]), .voffset(video_status[60:57]),
    .hs_out(resync_hs), .vs_out(resync_vs)
);
logic [23:0] rgb_l;
logic hb_l, vb_l, hs_l, vs_l;
always_ff @(posedge clk) begin
    if (reset) begin
        rgb_l <= 0;
        hb_l <= 1;
        vb_l <= 1;
        hs_l <= 1;
        vs_l <= 1;
    end else if (ce_input) begin
        rgb_l <= {red, green, blue};
        hb_l <= hblank;
        vb_l <= vblank;
        hs_l <= hs_n;
        vs_l <= vs_n;
    end
end

wire [7:0] size_r, size_g, size_b;
wire size_hs, size_vs, size_hb, size_vb;
jtframe_hsize #(.COLORW(8)) u_hsize (
    .clk(clk), .pxl_cen(ce_size), .pxl2_cen(ce_size2),
    .scale(video_status[52:49]), .offset(5'd0), .enable(video_status[48]),
    .r_in(rgb_l[23:16]), .g_in(rgb_l[15:8]), .b_in(rgb_l[7:0]),
    .HS_in(resync_hs), .VS_in(resync_vs), .HB_in(hb_l), .VB_in(vb_l),
    .r_out(size_r), .g_out(size_g), .b_out(size_b),
    .HS_out(size_hs), .VS_out(size_vs), .HB_out(size_hb), .VB_out(size_vb)
);

// Use the same mixer as arcade_video, with the known sync polarity explicit
// and its freeze input tied off (arcade_video leaves this optional port open).
// Resync and CRT sizing above remain active-low. MiSTer mixer uses high pulses.
assign vga_sl = video_fx > 3'd1 ? video_fx[1:0] - 2'd1 : 2'd0;
// Broadcast gamma writes, with only the digital mixer advertising capability.
wire [21:0] analog_gamma_bus;
assign analog_gamma_bus[20:0] = gamma_bus[20:0];
video_mixer #(.LINE_LENGTH(324), .HALF_DEPTH(0), .GAMMA(1)) u_analog_mixer (
    .CLK_VIDEO(clk), .ce_pix(ce_mix), .CE_PIXEL(ce_pixel),
    .scandoubler(forced_scandoubler || video_fx != 0), .hq2x(video_fx == 1),
    .gamma_bus(analog_gamma_bus), .R(size_r), .G(size_g), .B(size_b),
    .HSync(!size_hs), .VSync(!size_vs), .HBlank(size_hb), .VBlank(size_vb),
    .HDMI_FREEZE(1'b0), .freeze_sync(),
    .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b),
    .VGA_HS(vga_hs), .VGA_VS(vga_vs), .VGA_DE(vga_de)
);

// Raw registered pixels, sync, and blanking bypass BOTH CRT stages. A second
// mixer preserves gamma/HQ2x/scandoubler effects without an analog dependency.
wire digital_ce, digital_hs, digital_vs, digital_de, cropped_de;
wire [23:0] digital_rgb, hdmi_rgb;
video_mixer #(.LINE_LENGTH(324), .HALF_DEPTH(0), .GAMMA(1)) u_hdmi_mixer (
    .CLK_VIDEO(clk), .ce_pix(ce_mix), .CE_PIXEL(digital_ce),
    .scandoubler(forced_scandoubler || video_fx != 0), .hq2x(video_fx == 1),
    .gamma_bus(gamma_bus), .R(rgb_l[23:16]), .G(rgb_l[15:8]), .B(rgb_l[7:0]),
    .HSync(!hs_l), .VSync(!vs_l), .HBlank(hb_l), .VBlank(vb_l),
    .HDMI_FREEZE(1'b0), .freeze_sync(),
    .VGA_R(digital_rgb[23:16]), .VGA_G(digital_rgb[15:8]), .VGA_B(digital_rgb[7:0]),
    .VGA_HS(digital_hs), .VGA_VS(digital_vs), .VGA_DE(digital_de)
);

wire [1:0] aspect = video_status[17:16];
wire [11:0] arx = aspect == 0 ? 12'd4 : {10'd0, aspect} - 12'd1;
wire [11:0] ary = aspect == 0 ? 12'd3 : 12'd0;
wire [12:0] crop_arx, crop_ary, rotate_arx, rotate_ary;
video_freak u_crop (
    .CLK_VIDEO(clk), .CE_PIXEL(digital_ce), .VGA_VS(digital_vs),
    .HDMI_WIDTH(hdmi_width), .HDMI_HEIGHT(hdmi_height),
    .VGA_DE_IN(digital_de), .VGA_DE(cropped_de),
    .ARX(arx), .ARY(ary), .CROP_SIZE(crop_size), .CROP_OFF(crop_off),
    .SCALE(scale), .VIDEO_ARX(crop_arx), .VIDEO_ARY(crop_ary)
);
// Integer dimensions must be calculated in the final framebuffer orientation.
video_scale_int u_rotated_scale (
    .CLK_VIDEO(clk), .HDMI_WIDTH(hdmi_width), .HDMI_HEIGHT(hdmi_height),
    .SCALE(scale), .hsize(fb_width), .vsize(fb_height),
    .arx_i(aspect == 0 ? 12'd3 : arx), .ary_i(aspect == 0 ? 12'd4 : ary),
    .arx_o(rotate_arx), .ary_o(rotate_ary)
);
assign video_arx = rotate ? rotate_arx : crop_arx;
assign video_ary = rotate ? rotate_ary : crop_ary;

// Framebuffer input bypasses the framework's streaming scanline stage.
scanlines #(0) u_hdmi_scanlines (
    .clk(clk), .scanlines(vga_sl), .din(digital_rgb),
    .hs_in(digital_hs), .vs_in(digital_vs), .de_in(cropped_de), .ce_in(digital_ce),
    .dout(hdmi_rgb), .hs_out(hdmi_hs), .vs_out(hdmi_vs), .de_out(hdmi_de), .ce_out(hdmi_ce)
);
wire doubled = forced_scandoubler || video_fx != 0;
wire [11:0] digital_width = video_fx == 1 ? 12'd640 : 12'd320;
wire [11:0] digital_height = doubled ? 12'd480 : crop_size != 0 ? crop_size : 12'd240;
assign video_rotated = rotate;
// FB_LL controls the framework HDMI clock/scaler mode. The writer always
// presents the latest COMPLETE frame; it never races a partially written one.
wire unused_fb_ll = fb_ll;
knuckle_bash_framebuffer u_framebuffer (
    .clk(clk), .reset(reset), .enable(!direct_video),
    .ce_pixel(hdmi_ce), .vs(hdmi_vs), .de(hdmi_de), .rgb(hdmi_rgb),
    .input_width(digital_width), .input_height(digital_height),
    .rotate_ccw(rotate), .flip(flip), .fb_vbl(fb_vbl),
    .fb_en(fb_en), .fb_force_blank(fb_force_blank),
    .fb_format(fb_format), .fb_width(fb_width), .fb_height(fb_height),
    .fb_base(fb_base), .fb_stride(fb_stride),
    .ddram_busy(ddram_busy), .ddram_burstcnt(ddram_burstcnt),
    .ddram_addr(ddram_addr), .ddram_din(ddram_din), .ddram_be(ddram_be),
    .ddram_we(ddram_we), .ddram_rd(ddram_rd)
);

// Main must remeasure after a settled mode change, including initial startup.
// CRT status [60:48] is deliberately excluded: no HDMI mode notification.
localparam [63:0] HDMI_STATUS_MASK = (64'h7 << 3) | (64'h3 << 16) | (64'h1ff << 39);
wire [63:0] hdmi_status = video_status & HDMI_STATUS_MASK;
logic [63:0] status_l;
logic [25:0] output_mode_l;
logic refresh_vs;
integer refresh_frames;
wire [25:0] output_mode = {direct_video, forced_scandoubler, hdmi_width, hdmi_height};
always_ff @(posedge clk) begin
    if (reset) begin
        status_l <= 0;
        output_mode_l <= 0;
        refresh_vs <= 0;
        new_vmode <= 0;
        refresh_frames <= REFRESH_FRAMES;
    end else begin
        status_l <= hdmi_status;
        output_mode_l <= output_mode;
        refresh_vs <= hdmi_vs;
        if (status_l != hdmi_status || output_mode_l != output_mode)
            refresh_frames <= REFRESH_FRAMES;
        else if (refresh_frames != 0 && hdmi_vs && !refresh_vs) begin
            refresh_frames <= refresh_frames - 1;
            if (refresh_frames == 1) new_vmode <= ~new_vmode;
        end
    end
end
endmodule
