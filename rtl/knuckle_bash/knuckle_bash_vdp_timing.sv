// SPDX-License-Identifier: GPL-2.0-or-later

// TP-023 GP9001-visible raster timing derived from the raw 432 x 262 raster.
module knuckle_bash_vdp_timing (
    input  logic [ 8:0] hcnt,
    input  logic [ 8:0] vcnt,
    output logic [ 8:0] adjusted_v,
    output logic        hsync_n,
    output logic        vsync_n,
    output logic        fblank_n,
    output logic [15:0] vcount_data,
    output logic        gp_status
);

logic [9:0] adjusted_sum;

always_comb begin
    adjusted_sum = {1'b0, vcnt} + 10'd15;
    if (adjusted_sum >= 10'd262)
        adjusted_v = adjusted_sum - 10'd262;
    else
        adjusted_v = adjusted_sum[8:0];

    hsync_n  = !((hcnt >= 9'd326) && (hcnt <= 9'd379));
    vsync_n  = !((vcnt >= 9'd232) && (vcnt <= 9'd245));
    fblank_n = hsync_n && vsync_n;

    vcount_data = 16'hFFFF;
    if (adjusted_v <= 9'd255)
        vcount_data[7:0] = adjusted_v[7:0];

    if (!hsync_n)
        vcount_data[15] = 1'b0;
    if (!vsync_n)
        vcount_data[14] = 1'b0;
    if (!fblank_n)
        vcount_data[8] = 1'b0;

    gp_status = (adjusted_v >= 9'd245);
end

endmodule
