// SPDX-License-Identifier: GPL-2.0-or-later

// Convert MiSTer's active-high HPS joystick words to the active-high TP-023
// input bytes exposed by MAME.
module knuckle_bash_inputs (
    input  logic [31:0] joy1,
    input  logic [31:0] joy2,
    input  logic        service1,
    input  logic        tilt,
    input  logic        test,
    output logic [ 7:0] player1,
    output logic [ 7:0] player2,
    output logic [ 7:0] system
);

function automatic logic [7:0] player_port(input logic [31:0] joy);
    begin
        // MAME: unknown, B3, B2, B1, right, left, down, up.
        player_port = {
            1'b0,
            joy[6:4],
            joy[0],
            joy[1],
            joy[2],
            joy[3]
        };
    end
endfunction

assign player1 = player_port(joy1);
assign player2 = player_port(joy2);

// MiSTer BUTTONS=3 convention: start is joy[7], coin is joy[8].
// MAME: unknown, start2, start1, coin2, coin1, test, tilt, service1.
assign system = {
    1'b0,
    joy2[7],
    joy1[7],
    joy2[8],
    joy1[8],
    test,
    tilt,
    service1
};

endmodule
