// SPDX-License-Identifier: GPL-2.0-or-later
//
// Single-GP9001 tagged line renderer. Tile and buffered-object engines build
// the next line in parallel, then the mixer applies the GP9001 object-over-
// tile priority rule. A metadata mismatch blanks the output instead of
// exposing a stale line.
module knuckle_bash_gp9001_video (
    input  logic         clk,
    input  logic         rst,
    input  logic         line_start,
    input  logic         line_commit,
    input  logic [ 8:0]  target_y,
    input  logic         target_epoch,
    input  logic [ 8:0]  display_x,
    input  logic [ 8:0]  display_y,
    input  logic         display_epoch,

    input  logic [127:0] scrolls,
    input  logic [ 7:0]  scroll_flip,

    output logic [12:0]  vram_addr,
    input  logic [15:0]  vram_data,
    output logic [ 9:0]  object_addr,
    input  logic [15:0]  object_data,

    output logic         tile_gfx_req,
    output logic [21:0]  tile_gfx_addr,
    input  logic [15:0]  tile_gfx_data,
    input  logic         tile_gfx_ok,

    output logic         object_gfx_req,
    output logic [21:0]  object_gfx_addr,
    input  logic [15:0]  object_gfx_data,
    input  logic         object_gfx_ok,

    output logic         line_ready,
    output logic         pixel_valid,
    output logic [10:0]  final_color,
    output logic [ 1:0]  engine_busy,
    output logic [ 1:0]  deadline_miss,
    output logic         object_capacity_overflow,
    output logic [15:0]  tile_cycles,
    output logic [15:0]  object_cycles,
    output logic [ 8:0]  debug_tile_y,
    output logic [ 8:0]  debug_object_y,
    output logic [ 1:0]  debug_line_epoch,
    output logic [ 1:0]  debug_line_valid
);

wire [14:0] tile_pixel;
wire [14:0] object_pixel;
wire [ 8:0] tile_y;
wire [ 8:0] object_y;
wire        tile_epoch;
wire        object_epoch;
wire        tile_valid;
wire        object_valid;
wire        tile_busy;
wire        object_busy;
wire        tile_deadline_miss;
wire        object_deadline_miss;
wire [14:0] mixed_pixel;
wire [10:0] mixed_palette;
wire [ 3:0] mixed_priority;
wire        mixed_valid;

assign engine_busy       = {object_busy, tile_busy};
assign deadline_miss     = {object_deadline_miss, tile_deadline_miss};
assign debug_tile_y      = tile_y;
assign debug_object_y    = object_y;
assign debug_line_epoch  = {object_epoch, tile_epoch};
assign debug_line_valid  = {object_valid, tile_valid};

assign line_ready =
    tile_valid && object_valid &&
    (tile_y == display_y) && (object_y == display_y) &&
    (tile_epoch == display_epoch) &&
    (object_epoch == display_epoch);

// MAME clears the destination bitmap to palette index zero before drawing
// nonzero GP9001 pens.  A fully transparent but correctly tagged line must
// therefore remain a valid palette-zero pixel; only stale/missing line data
// is invalid and blanked by the game wrapper.
assign pixel_valid = line_ready;
assign final_color = line_ready ? mixed_palette : 11'd0;

knuckle_bash_gp9001_tile_line u_tile (
    .clk               ( clk                         ),
    .rst               ( rst                         ),
    .start             ( line_start                  ),
    .commit            ( line_commit                 ),
    .target_y          ( target_y                    ),
    .target_epoch      ( target_epoch                ),
    .scrolls           ( scrolls                     ),
    .scroll_flip       ( scroll_flip                 ),
    .busy              ( tile_busy                   ),
    .done              (                             ),
    .deadline_miss     ( tile_deadline_miss          ),
    .last_build_cycles ( tile_cycles                 ),
    .vram_addr         ( vram_addr                   ),
    .vram_data         ( vram_data                   ),
    .gfx_req           ( tile_gfx_req                ),
    .gfx_addr          ( tile_gfx_addr               ),
    .gfx_data          ( tile_gfx_data               ),
    .gfx_ok            ( tile_gfx_ok                 ),
    .scan_x            ( display_x                   ),
    .scan_pixel        ( tile_pixel                  ),
    .scan_y            ( tile_y                      ),
    .scan_epoch        ( tile_epoch                  ),
    .scan_valid        ( tile_valid                  )
);

knuckle_bash_gp9001_object_line u_object (
    .clk               ( clk                         ),
    .rst               ( rst                         ),
    .start             ( line_start                  ),
    .commit            ( line_commit                 ),
    .target_y          ( target_y                    ),
    .target_epoch      ( target_epoch                ),
    .scrolls           ( scrolls                     ),
    .scroll_flip       ( scroll_flip                 ),
    .busy              ( object_busy                 ),
    .done              (                             ),
    .deadline_miss     ( object_deadline_miss        ),
    .capacity_overflow ( object_capacity_overflow    ),
    .last_build_cycles ( object_cycles               ),
    .object_addr       ( object_addr                 ),
    .object_data       ( object_data                 ),
    .gfx_req           ( object_gfx_req              ),
    .gfx_addr          ( object_gfx_addr             ),
    .gfx_data          ( object_gfx_data             ),
    .gfx_ok            ( object_gfx_ok               ),
    .scan_x            ( display_x                   ),
    .scan_pixel        ( object_pixel                ),
    .scan_y            ( object_y                    ),
    .scan_epoch        ( object_epoch                ),
    .scan_valid        ( object_valid                )
);

// The tile engine has already applied the layer-0/1/2 ordering. Feeding that
// result as tile 0 keeps one shared priority implementation for the final
// object comparison; the unused tile candidates are transparent.
knuckle_bash_gp9001_priority_mixer u_priority (
    .tile0_pixel    ( tile_pixel                    ),
    .tile1_pixel    ( 15'd0                         ),
    .tile2_pixel    ( 15'd0                         ),
    .object_pixel   ( object_pixel                  ),
    .mixed_pixel    ( mixed_pixel                   ),
    .palette_index  ( mixed_palette                 ),
    .mixed_priority ( mixed_priority                ),
    .mixed_valid    ( mixed_valid                   )
);

endmodule
