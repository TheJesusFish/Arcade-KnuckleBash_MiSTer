// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 single-GP9001 pixel priority mixer.
//
// Each candidate is packed as {priority[3:0], palette_index[10:0]}. The low
// four palette-index bits are the graphics pen, and pen zero is transparent
// regardless of priority. GP9001 tile priorities ignore bit zero, so this
// block masks each tile priority with 4'he before comparing or forwarding it.
// Object priority is used exactly as supplied.
//
// Candidates are considered in GP9001 drawing order: tile 0, tile 1, tile 2,
// then object. An opaque later candidate wins on greater-than-or-equal
// priority, so later tile layers and objects win equal-priority ties.
module knuckle_bash_gp9001_priority_mixer (
    input  logic [14:0] tile0_pixel,
    input  logic [14:0] tile1_pixel,
    input  logic [14:0] tile2_pixel,
    input  logic [14:0] object_pixel,

    output logic [14:0] mixed_pixel,
    output logic [10:0] palette_index,
    output logic [ 3:0] mixed_priority,
    output logic         mixed_valid
);

logic [14:0] tile0_masked;
logic [14:0] tile1_masked;
logic [14:0] tile2_masked;
logic [14:0] winner;

function automatic logic [14:0] select_later(
    input logic [14:0] current_pixel,
    input logic [14:0] candidate_pixel
);
    begin
        if ((candidate_pixel[3:0] != 4'h0) &&
            ((current_pixel[3:0] == 4'h0) ||
             (candidate_pixel[14:11] >= current_pixel[14:11])))
            select_later = candidate_pixel;
        else
            select_later = current_pixel;
    end
endfunction

always_comb begin
    tile0_masked = {
        tile0_pixel[14:11] & 4'he, tile0_pixel[10:0]
    };
    tile1_masked = {
        tile1_pixel[14:11] & 4'he, tile1_pixel[10:0]
    };
    tile2_masked = {
        tile2_pixel[14:11] & 4'he, tile2_pixel[10:0]
    };

    winner = 15'd0;
    winner = select_later(winner, tile0_masked);
    winner = select_later(winner, tile1_masked);
    winner = select_later(winner, tile2_masked);
    winner = select_later(winner, object_pixel);

    mixed_pixel    = winner;
    palette_index  = winner[10:0];
    mixed_priority = winner[14:11];
    mixed_valid    = winner[3:0] != 4'h0;
end

endmodule
