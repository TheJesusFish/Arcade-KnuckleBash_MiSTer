// SPDX-License-Identifier: GPL-3.0-or-later
//
// Knuckle Bash-local copy of the standard MiSTer pause frontend used by
// Arcade-IGSPGM_MiSTer. The board wrapper consumes pause_cpu; only video
// presentation remains live so the display retains sync while emulation is
// stopped.
//
// Based on JimmyStones/Pause_MiSTer, copyright (c) 2021 Jim Gregory.

module knuckle_bash_pause #(
    parameter integer RW = 8,
    parameter integer GW = 8,
    parameter integer BW = 8,
    parameter integer CLKSPD = 94
) (
    input  wire          clk_sys,
    input  wire          reset,
    input  wire          user_button,
    input  wire          pause_request,
    input  wire [1:0]    options,
    input  wire          osd_status,
    input  wire [RW-1:0] r,
    input  wire [GW-1:0] g,
    input  wire [BW-1:0] b,
    output wire          pause_cpu,
    output wire [RW-1:0] r_out,
    output wire [GW-1:0] g_out,
    output wire [BW-1:0] b_out
);

localparam integer PAUSE_IN_OSD = 0;
localparam integer DIM_VIDEO = 1;

reg        pause_toggle = 1'b0;
reg        user_button_last = 1'b0;
reg [31:0] pause_timer = 32'd0;
localparam [31:0] DIM_TIMEOUT = CLKSPD * 32'd10000000;

assign pause_cpu =
    (pause_request || pause_toggle ||
     (osd_status && options[PAUSE_IN_OSD])) && !reset;

wire dim_video = pause_timer >= DIM_TIMEOUT;

always @(posedge clk_sys) begin
    user_button_last <= user_button;

    if (reset) begin
        pause_toggle <= 1'b0;
        pause_timer <= 32'd0;
    end else begin
        if (!user_button_last && user_button)
            pause_toggle <= !pause_toggle;

        if (pause_cpu && options[DIM_VIDEO] && !dim_video)
            pause_timer <= pause_timer + 32'd1;
        else if (!pause_cpu || !options[DIM_VIDEO])
            pause_timer <= 32'd0;
    end
end

assign r_out = dim_video ? (r >> 1) : r;
assign g_out = dim_video ? (g >> 1) : g;
assign b_out = dim_video ? (b >> 1) : b;

endmodule
