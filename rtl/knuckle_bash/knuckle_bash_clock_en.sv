// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_clock_en (
    input  logic clk,
    input  logic rst,
    output logic pxl_cen,
    output logic v25_cen,
    output logic opm_cen,
    output logic oki_cen
);

logic [3:0] pxl_div;
logic [4:0] opm_div;
logic [7:0] v25_acc;
logic [7:0] oki_acc;

wire [8:0] v25_sum = {1'b0, v25_acc} + 9'd32;
wire [8:0] oki_sum = {1'b0, oki_acc} + 9'd2;
wire [8:0] v25_next = v25_sum - 9'd189;
wire [8:0] oki_next = oki_sum - 9'd189;

always_ff @(posedge clk) begin
    if (rst) begin
        pxl_div <= 4'd0;
        opm_div <= 5'd0;
        v25_acc <= 8'd0;
        oki_acc <= 8'd0;
        pxl_cen <= 1'b0;
        v25_cen <= 1'b0;
        opm_cen <= 1'b0;
        oki_cen <= 1'b0;
    end else begin
        pxl_cen <= pxl_div == 4'd13;
        pxl_div <= (pxl_div == 4'd13) ? 4'd0 : pxl_div + 4'd1;

        opm_cen <= opm_div == 5'd27;
        opm_div <= (opm_div == 5'd27) ? 5'd0 : opm_div + 5'd1;

        v25_cen <= v25_sum >= 9'd189;
        v25_acc <= (v25_sum >= 9'd189) ? v25_next[7:0] : v25_sum[7:0];

        oki_cen <= oki_sum >= 9'd189;
        oki_acc <= (oki_sum >= 9'd189) ? oki_next[7:0] : oki_sum[7:0];
    end
end

endmodule
