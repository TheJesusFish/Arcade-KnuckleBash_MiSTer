// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_reset_sync #(
    parameter integer STAGES = 2
) (
    input  logic clk,
    input  logic async_reset,
    output logic reset_out
);

(* altera_attribute = {
    "-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW; ",
    "-name FORCE_SYNCH_CLEAR OFF; ",
    "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; ",
    "-name DONT_MERGE_REGISTER ON; ",
    "-name PRESERVE_REGISTER ON"
} *) logic [STAGES-1:0] reset_release = {STAGES{1'b0}};

always_ff @(posedge clk or posedge async_reset) begin
    if (async_reset)
        reset_release <= {STAGES{1'b0}};
    else
        reset_release <= {reset_release[STAGES-2:0], 1'b1};
end

assign reset_out = ~reset_release[STAGES-1];

// synthesis translate_off
initial begin
    if (STAGES < 2)
        $fatal(1, "knuckle_bash_reset_sync requires STAGES >= 2");
end
// synthesis translate_on

endmodule
