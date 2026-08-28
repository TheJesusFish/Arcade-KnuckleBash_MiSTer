// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_savestate_schema (
    output logic [63:0] magic,
    output logic [31:0] schema_version,
    output logic [47:0] board_id,
    output logic [15:0] chunk_count
);

assign magic = 64'h4B42_5353_3030_3031; // "KBSS0001"
assign schema_version = 32'd1;
assign board_id = 48'h5450_2D30_3233; // "TP-023"
assign chunk_count = 16'd9;

endmodule
