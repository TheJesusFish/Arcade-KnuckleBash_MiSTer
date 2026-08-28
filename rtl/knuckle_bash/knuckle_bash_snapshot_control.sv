// SPDX-License-Identifier: GPL-2.0-or-later
//
// Atomic video-snapshot ownership.
//
// The main CPU continues running while a hold request drains toward a proven
// idle board-bus boundary.  Only then is the CPU stopped.  The snapshot pulse
// is accepted at the visible-to-vblank boundary and the CPU remains stopped
// until both state copies finish, preventing GP VRAM, scroll, or palette
// writes from mixing two emulated frames in one snapshot.
module knuckle_bash_snapshot_control (
    input  logic clk,
    input  logic rst,

    input  logic snapshot_prepare,
    input  logic snapshot_boundary,
    input  logic main_idle,
    input  logic main_held,
    input  logic gp_copy_busy,
    input  logic palette_copy_busy,
    input  logic gp_copy_valid,
    input  logic palette_copy_valid,

    output logic main_run,
    output logic snapshot_start,
    output logic snapshot_hold,
    output logic frame_valid,
    output logic snapshot_miss
);

localparam logic [1:0] ST_IDLE    = 2'd0;
localparam logic [1:0] ST_DRAIN   = 2'd1;
localparam logic [1:0] ST_HELD    = 2'd2;
localparam logic [1:0] ST_COPYING = 2'd3;

logic [1:0] state;
logic       gp_busy_seen;
logic       palette_busy_seen;

wire acquire_hold_now =
    main_idle &&
    ((state == ST_DRAIN) ||
     ((state == ST_IDLE) && snapshot_prepare));

always_comb begin
    // The combinational acquisition term prevents fx68k from starting a new
    // cycle on the same edge at which an idle boundary is accepted.
    main_run       = ((state == ST_IDLE) || (state == ST_DRAIN)) &&
                     !acquire_hold_now;
    snapshot_hold  = (state == ST_HELD) || (state == ST_COPYING) ||
                     acquire_hold_now;
    snapshot_start = !rst && (state == ST_HELD) &&
                     main_held && snapshot_boundary;
end

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state         <= ST_IDLE;
        frame_valid   <= 1'b0;
        snapshot_miss <= 1'b0;
        gp_busy_seen  <= 1'b0;
        palette_busy_seen <= 1'b0;
    end else begin
        snapshot_miss <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (snapshot_prepare) begin
                    if (main_idle)
                        state <= ST_HELD;
                    else
                        state <= ST_DRAIN;
                end else if (snapshot_boundary) begin
                    // A boundary without a completed hold cannot produce an
                    // atomic frame. Retain any prior complete snapshot; the
                    // renderer itself is invalidated unconditionally at the
                    // boundary before rebuilding from that stable image.
                    snapshot_miss <= 1'b1;
                end
            end

            ST_DRAIN: begin
                if (snapshot_boundary) begin
                    state         <= ST_IDLE;
                    snapshot_miss <= 1'b1;
                end else if (main_idle) begin
                    state <= ST_HELD;
                end
            end

            ST_HELD: begin
                if (snapshot_boundary) begin
                    if (main_held) begin
                        state             <= ST_COPYING;
                        gp_busy_seen      <= 1'b0;
                        palette_busy_seen <= 1'b0;
                    end else begin
                        state         <= ST_IDLE;
                        snapshot_miss <= 1'b1;
                    end
                end
            end

            ST_COPYING: begin
                if (gp_copy_busy)
                    gp_busy_seen <= 1'b1;
                if (palette_copy_busy)
                    palette_busy_seen <= 1'b1;

                if (gp_busy_seen && palette_busy_seen &&
                    !gp_copy_busy && !palette_copy_busy &&
                    gp_copy_valid && palette_copy_valid) begin
                    state             <= ST_IDLE;
                    frame_valid       <= 1'b1;
                    gp_busy_seen      <= 1'b0;
                    palette_busy_seen <= 1'b0;
                end
            end

            default: begin
                state         <= ST_IDLE;
                frame_valid   <= 1'b0;
                snapshot_miss <= 1'b1;
                gp_busy_seen  <= 1'b0;
                palette_busy_seen <= 1'b0;
            end
        endcase
    end
end

endmodule
