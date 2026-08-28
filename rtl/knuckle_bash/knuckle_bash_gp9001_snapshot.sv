// SPDX-License-Identifier: GPL-2.0-or-later
//
// Single-GP9001 display snapshot.
//
// The CPU-facing GP host owns live VRAM. At the visible-to-vblank boundary
// this block copies all 8192 words and latches the eight scroll registers.
// In parallel it preserves the outgoing snapshot's 1024-word object window,
// giving the renderer current tile/scroll state with the preceding object
// state, matching MAME 0.288's update/eof ordering.
module knuckle_bash_gp9001_snapshot (
    input  logic         clk,
    input  logic         rst,
    input  logic         snapshot_start,

    output logic [12:0]  source_addr,
    input  logic [15:0]  source_data,
    input  logic [127:0] source_scrolls,
    input  logic [ 7:0]  source_scroll_flip,

    input  logic [12:0]  display_addr,
    output logic [15:0]  display_data,
    input  logic [ 9:0]  object_addr,
    output logic [15:0]  object_data,
    output logic [127:0] display_scrolls,
    output logic [ 7:0]  display_scroll_flip,

    output logic         copy_busy,
    output logic         snapshot_valid,
    output logic         copy_miss
);

logic        copy_active;
logic        copy_valid;
logic        copy_final_pending;
logic [12:0] copy_read_addr;
logic [12:0] copy_write_addr;

logic        object_copy_active;
logic        object_copy_valid;
logic        object_copy_final_pending;
logic        object_copy_source_valid;
logic [ 9:0] object_copy_read_addr;
logic [ 9:0] object_copy_write_addr;

wire [12:0] display_ram_addr = object_copy_active ?
    {3'b110, object_copy_read_addr} : display_addr;
wire [15:0] display_ram_data;
wire [15:0] object_copy_data = object_copy_source_valid ?
    display_ram_data : 16'h0000;

assign source_addr  = copy_read_addr;
assign display_data = display_ram_data;
assign copy_busy    = copy_active || object_copy_active;

jtframe_dual_ram16 #(.AW(13)) u_display_vram (
    .clk0  ( clk                                      ),
    .data0 ( source_data                              ),
    .addr0 ( copy_write_addr                          ),
    .we0   ( {2{copy_active && copy_valid}}           ),
    .q0    (                                           ),
    .clk1  ( clk                                      ),
    .data1 ( 16'h0000                                 ),
    .addr1 ( display_ram_addr                         ),
    .we1   ( 2'b00                                    ),
    .q1    ( display_ram_data                         )
);

jtframe_dual_ram16 #(.AW(10)) u_object_history (
    .clk0  ( clk                                      ),
    .data0 ( object_copy_data                         ),
    .addr0 ( object_copy_write_addr                   ),
    .we0   ( {2{object_copy_active && object_copy_valid}} ),
    .q0    (                                           ),
    .clk1  ( clk                                      ),
    .data1 ( 16'h0000                                 ),
    .addr1 ( object_addr                              ),
    .we1   ( 2'b00                                    ),
    .q1    ( object_data                              )
);

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        copy_active              <= 1'b0;
        copy_valid               <= 1'b0;
        copy_final_pending       <= 1'b0;
        copy_read_addr           <= 13'd0;
        copy_write_addr          <= 13'd0;
        object_copy_active       <= 1'b0;
        object_copy_valid        <= 1'b0;
        object_copy_final_pending <= 1'b0;
        object_copy_source_valid <= 1'b0;
        object_copy_read_addr    <= 10'd0;
        object_copy_write_addr   <= 10'd0;
        display_scrolls          <= 128'd0;
        display_scroll_flip      <= 8'd0;
        snapshot_valid           <= 1'b0;
        copy_miss                <= 1'b0;
    end else begin
        copy_miss <= 1'b0;

        if (snapshot_start) begin
            if (!copy_active && !object_copy_active) begin
                copy_active               <= 1'b1;
                copy_valid                <= 1'b0;
                copy_final_pending        <= 1'b0;
                copy_read_addr            <= 13'd0;
                copy_write_addr           <= 13'd0;
                object_copy_active        <= 1'b1;
                object_copy_valid         <= 1'b0;
                object_copy_final_pending <= 1'b0;
                object_copy_source_valid  <= snapshot_valid;
                object_copy_read_addr     <= 10'd0;
                object_copy_write_addr    <= 10'd0;
                display_scrolls           <= source_scrolls;
                display_scroll_flip       <= source_scroll_flip;
            end else begin
                copy_miss <= 1'b1;
            end
        end else if (copy_active) begin
            if (!copy_valid) begin
                copy_valid      <= 1'b1;
                copy_write_addr <= copy_read_addr;
                copy_read_addr  <= copy_read_addr + 13'd1;
            end else if (copy_final_pending) begin
                copy_active        <= 1'b0;
                copy_valid         <= 1'b0;
                copy_final_pending <= 1'b0;
                snapshot_valid     <= 1'b1;
            end else begin
                copy_write_addr <= copy_read_addr;
                if (copy_read_addr == 13'h1fff)
                    copy_final_pending <= 1'b1;
                else
                    copy_read_addr <= copy_read_addr + 13'd1;
            end
        end

        if (!snapshot_start && object_copy_active) begin
            if (!object_copy_valid) begin
                object_copy_valid      <= 1'b1;
                object_copy_write_addr <= object_copy_read_addr;
                object_copy_read_addr  <= object_copy_read_addr + 10'd1;
            end else if (object_copy_final_pending) begin
                object_copy_active        <= 1'b0;
                object_copy_valid         <= 1'b0;
                object_copy_final_pending <= 1'b0;
            end else begin
                object_copy_write_addr <= object_copy_read_addr;
                if (object_copy_read_addr == 10'h3ff)
                    object_copy_final_pending <= 1'b1;
                else
                    object_copy_read_addr <= object_copy_read_addr + 10'd1;
            end
        end
    end
end

endmodule
