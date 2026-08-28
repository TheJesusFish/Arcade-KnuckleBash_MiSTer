// SPDX-License-Identifier: GPL-2.0-or-later
//
// Freeze the 2048-word xBGR555 palette at the same vblank boundary as GP
// state so one displayed frame cannot mix CPU palette updates.
module knuckle_bash_palette_snapshot (
    input  logic        clk,
    input  logic        rst,
    input  logic        snapshot_start,

    output logic [10:0] source_addr,
    input  logic [15:0] source_data,
    input  logic [10:0] display_addr,
    output logic [15:0] display_data,

    output logic        copy_busy,
    output logic        snapshot_valid,
    output logic        copy_miss
);

logic        copy_active;
logic        copy_valid;
logic        copy_final_pending;
logic [10:0] copy_read_addr;
logic [10:0] copy_write_addr;

assign source_addr = copy_read_addr;
assign copy_busy   = copy_active;

jtframe_dual_ram16 #(.AW(11)) u_display_palette (
    .clk0  ( clk                                    ),
    .data0 ( source_data                            ),
    .addr0 ( copy_write_addr                        ),
    .we0   ( {2{copy_active && copy_valid}}         ),
    .q0    (                                         ),
    .clk1  ( clk                                    ),
    .data1 ( 16'h0000                               ),
    .addr1 ( display_addr                           ),
    .we1   ( 2'b00                                  ),
    .q1    ( display_data                           )
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        copy_active        <= 1'b0;
        copy_valid         <= 1'b0;
        copy_final_pending <= 1'b0;
        copy_read_addr     <= 11'd0;
        copy_write_addr    <= 11'd0;
        snapshot_valid     <= 1'b0;
        copy_miss          <= 1'b0;
    end else begin
        copy_miss <= 1'b0;

        if (snapshot_start) begin
            if (!copy_active) begin
                copy_active        <= 1'b1;
                copy_valid         <= 1'b0;
                copy_final_pending <= 1'b0;
                copy_read_addr     <= 11'd0;
                copy_write_addr    <= 11'd0;
            end else begin
                copy_miss <= 1'b1;
            end
        end else if (copy_active) begin
            if (!copy_valid) begin
                copy_valid      <= 1'b1;
                copy_write_addr <= copy_read_addr;
                copy_read_addr  <= copy_read_addr + 11'd1;
            end else if (copy_final_pending) begin
                copy_active        <= 1'b0;
                copy_valid         <= 1'b0;
                copy_final_pending <= 1'b0;
                snapshot_valid     <= 1'b1;
            end else begin
                copy_write_addr <= copy_read_addr;
                if (copy_read_addr == 11'h7ff)
                    copy_final_pending <= 1'b1;
                else
                    copy_read_addr <= copy_read_addr + 11'd1;
            end
        end
    end
end

endmodule
