// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from Jose Tejada Gomez's JTFrame jtframe_resync (2019) and the
// Batsugun-local active-low adaptation. Keep upstream sources unchanged.
// Knuckle Bash adds a real reset and pass-through while pulse history fills.
module knuckle_bash_resync (
    input  logic       clk,
    input  logic       reset,
    input  logic       pxl_cen,
    input  logic       hs_in,
    input  logic       vs_in,
    input  logic       lhbl,
    input  logic       lvbl,
    input  logic [3:0] hoffset,
    input  logic [3:0] voffset,
    output logic       hs_out,
    output logic       vs_out
);
logic [9:0] hs_pos[0:1], vs_hpos[0:1], vs_vpos[0:1];
logic [9:0] hs_len[0:1], vs_len[0:1];
logic [9:0] hs_cnt, vs_cnt, hs_hold, vs_hold;
logic last_lhbl, last_lvbl, last_hs, last_vs, field;
logic [1:0] hs_valid, vs_valid;
wire hb_edge = lhbl && !last_lhbl;
wire vb_edge = lvbl && !last_lvbl;
logic [9:0] htrip, vhtrip, vvtrip;
logic signed [10:0] hsum, vhsum, vvsum;
always_comb begin
    hsum = $signed({1'b0, hs_pos[field]}) + $signed({{7{hoffset[3]}}, hoffset});
    vhsum = $signed({1'b0, vs_hpos[field]}) + $signed({{7{hoffset[3]}}, hoffset});
    vvsum = $signed({1'b0, vs_vpos[field]}) + $signed({{7{voffset[3]}}, voffset});
    if (hsum >= 11'sd432) hsum = hsum - 11'sd432;
    if (hsum < 0) hsum = hsum + 11'sd432;
    // TP-023 VS changes at x=0. A horizontal shift must carry across the
    // actual 432-pixel line, not wrap at the ten-bit counter's 1024.
    if (vhsum >= 11'sd432) begin
        vhsum = vhsum - 11'sd432;
        vvsum = vvsum + 11'sd1;
    end
    if (vhsum < 0) begin
        vhsum = vhsum + 11'sd432;
        vvsum = vvsum - 11'sd1;
    end
    if (vvsum >= 11'sd262) vvsum = vvsum - 11'sd262;
    if (vvsum < 0) vvsum = vvsum + 11'sd262;
    htrip = hsum[9:0];
    vhtrip = vhsum[9:0];
    vvtrip = vvsum[9:0];
end

always_ff @(posedge clk) begin
    if (reset) begin
        hs_cnt <= 0;
        vs_cnt <= 0;
        hs_hold <= 0;
        vs_hold <= 0;
        hs_out <= 1;
        vs_out <= 1;
        last_lhbl <= 0;
        last_lvbl <= 0;
        last_hs <= 1;
        last_vs <= 1;
        field <= 0;
        hs_valid <= 0;
        vs_valid <= 0;
        for (integer i = 0; i < 2; i = i + 1) begin
            hs_pos[i] <= 0;
            vs_hpos[i] <= 0;
            vs_vpos[i] <= 0;
            hs_len[i] <= 0;
            vs_len[i] <= 0;
        end
    end else if (pxl_cen) begin
        last_lhbl <= lhbl;
        last_lvbl <= lvbl;
        last_hs <= hs_in;
        last_vs <= vs_in;
        hs_cnt <= hb_edge ? 10'd0 : hs_cnt + 10'd1;
        if (vb_edge) begin
            vs_cnt <= 0;
            field <= ~field;
        end else if (hb_edge) vs_cnt <= vs_cnt + 10'd1;

        if (!hs_in && last_hs) hs_pos[field] <= hs_cnt;
        if (hs_in && !last_hs) begin
            hs_len[field] <= hs_cnt - hs_pos[field];
            hs_valid[field] <= 1;
        end
        if (!hs_valid[field]) hs_out <= hs_in;
        else if (hs_cnt == htrip) begin
            hs_out <= 0;
            hs_hold <= hs_len[field] - 10'd1;
        end else begin
            if (|hs_hold) hs_hold <= hs_hold - 10'd1;
            if (hs_hold == 0) hs_out <= 1;
        end

        if (!vs_in && last_vs) begin
            vs_hpos[field] <= hs_cnt;
            vs_vpos[field] <= vs_cnt;
        end
        if (vs_in && !last_vs) begin
            vs_len[field] <= vs_cnt - vs_vpos[field];
            vs_valid[field] <= 1;
        end
        if (!vs_valid[field]) vs_out <= vs_in;
        else if (hs_cnt == vhtrip) begin
            if (vs_cnt == vvtrip) begin
                vs_out <= 0;
                vs_hold <= vs_len[field] - 10'd1;
            end else begin
                if (|vs_hold) vs_hold <= vs_hold - 10'd1;
                if (vs_hold == 0) vs_out <= 1;
            end
        end
    end
end
endmodule
