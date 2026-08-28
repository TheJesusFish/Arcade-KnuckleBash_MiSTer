// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 raw GP9001 graphics address and bitplane helper.
//
// The 8 MiB graphics stream is kept in its original linear byte order. SDRAM
// word bits [7:0] therefore hold the even byte and bits [15:8] hold the odd
// byte. There is no Dogyuun/Batsugun graphics repack in this path.
//
// Tile mode:
//   q = (pixel_y[3] ? 16 : 0) +
//       (pixel_x[3] ?  8 : 0) + pixel_y[2:0]
//   n = (code[15:0] << 5) + q
//
// Object mode:
//   n = (code[17:0] << 3) + pixel_y[2:0]
//
// In both modes the lower and upper plane pairs are words n and 0x200000+n.
// pixel_x[2:0] selects one of the eight pixels in the fetched word pair.
module knuckle_bash_gp9001_gfx (
    input  logic        object_mode,
    input  logic [17:0] code,
    input  logic [ 3:0] pixel_x,
    input  logic [ 3:0] pixel_y,

    input  logic [15:0] lower_word,
    input  logic [15:0] upper_word,

    output logic [21:0] lower_addr,
    output logic [21:0] upper_addr,
    output logic [ 3:0] pen
);

logic [ 4:0] tile_q;
logic [20:0] plane_word;
integer bit_index;

always_comb begin
    // Concatenation is the exact 16*y3 + 8*x3 + y[2:0] expression.
    tile_q = {pixel_y[3], pixel_x[3], pixel_y[2:0]};

    // Preserve the complete 21-bit plane-local word index. The maximum for
    // either path is 0x1fffff, so upper_addr reaches the final 0x3fffff word
    // of the raw 8 MiB graphics region without wrapping.
    if (object_mode)
        plane_word = {code, 3'b000} +
                     {18'd0, pixel_y[2:0]};
    else
        plane_word = {code[15:0], 5'b00000} +
                     {16'd0, tile_q};

    lower_addr = {1'b0, plane_word};
    upper_addr = {1'b1, plane_word};

    bit_index = 7 - pixel_x[2:0];
    pen = {
        upper_word[8 + bit_index],
        upper_word[    bit_index],
        lower_word[8 + bit_index],
        lower_word[    bit_index]
    };
end

endmodule
