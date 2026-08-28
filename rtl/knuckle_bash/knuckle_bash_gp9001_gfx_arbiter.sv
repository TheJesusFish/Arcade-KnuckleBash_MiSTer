// SPDX-License-Identifier: GPL-2.0-or-later
//
// Fair transaction owner for the two logical GP9001 graphics clients.
//
// A renderer request remains asserted until its matching *_ok pulse.  The
// arbiter captures the selected address, drives only that client's SDRAM
// slot, and returns exactly one registered completion.  A completed or
// flushed request must fall before it can be accepted again.
//
// ST_GAP deliberately removes both chip selects and waits for both downstream
// response levels to fall.  This makes an immediate/cache-hit level response
// safe while preventing the tail of that same level from completing another
// transaction.
module knuckle_bash_gp9001_gfx_arbiter (
    input  logic         clk,
    input  logic         rst,
    input  logic         flush,

    input  logic         tile_req,
    input  logic [21:0]  tile_addr,
    output logic [15:0]  tile_data,
    output logic         tile_ok,

    input  logic         object_req,
    input  logic [21:0]  object_addr,
    output logic [15:0]  object_data,
    output logic         object_ok,

    output logic [21:0]  tile_sdram_addr,
    output logic         tile_sdram_cs,
    input  logic [15:0]  tile_sdram_data,
    input  logic         tile_sdram_ok,

    output logic [21:0]  object_sdram_addr,
    output logic         object_sdram_cs,
    input  logic [15:0]  object_sdram_data,
    input  logic         object_sdram_ok,

    output logic         idle,
    output logic         busy
);

localparam logic [1:0] ST_IDLE   = 2'd0;
localparam logic [1:0] ST_ACTIVE = 2'd1;
localparam logic [1:0] ST_GAP    = 2'd2;

logic [1:0] state;
logic       active_object;
logic       prefer_object;
logic       tile_seen;
logic       object_seen;
logic       tile_ok_q;
logic       object_ok_q;

wire tile_eligible   = tile_req   && !tile_seen;
wire object_eligible = object_req && !object_seen;

always_comb begin
    idle = state == ST_IDLE && !rst && !flush;
    busy = !idle;

    tile_sdram_cs =
        state == ST_ACTIVE && !active_object && !rst && !flush;
    object_sdram_cs =
        state == ST_ACTIVE && active_object && !rst && !flush;

    // Suppress an already-issued completion immediately when an asynchronous
    // reset/flush request arrives between clock edges.
    tile_ok   = tile_ok_q   && !rst && !flush;
    object_ok = object_ok_q && !rst && !flush;
end

always_ff @(posedge clk) begin
    tile_ok_q   <= 1'b0;
    object_ok_q <= 1'b0;

    if (rst) begin
        state              <= ST_GAP;
        active_object      <= 1'b0;
        prefer_object      <= 1'b0;
        tile_seen          <= 1'b0;
        object_seen        <= 1'b0;
        tile_sdram_addr    <= 22'd0;
        object_sdram_addr  <= 22'd0;
        tile_data          <= 16'd0;
        object_data        <= 16'd0;
    end else begin
        // A low request rearms only that owner.  This operates in every state
        // so a renderer can drop its completed request during ST_GAP.
        if (!tile_req)
            tile_seen <= 1'b0;
        if (!object_req)
            object_seen <= 1'b0;

        if (flush) begin
            state         <= ST_GAP;
            active_object <= 1'b0;

            // A request canceled by flush is blocked until its owner visibly
            // drops it.  This prevents the canceled payload from restarting.
            tile_seen   <= tile_req;
            object_seen <= object_req;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (tile_eligible && object_eligible) begin
                        if (prefer_object) begin
                            active_object     <= 1'b1;
                            object_sdram_addr <= object_addr;
                            object_seen       <= 1'b1;
                            prefer_object     <= 1'b0;
                        end else begin
                            active_object   <= 1'b0;
                            tile_sdram_addr <= tile_addr;
                            tile_seen       <= 1'b1;
                            prefer_object   <= 1'b1;
                        end
                        state <= ST_ACTIVE;
                    end else if (tile_eligible) begin
                        active_object   <= 1'b0;
                        tile_sdram_addr <= tile_addr;
                        tile_seen       <= 1'b1;
                        prefer_object   <= 1'b1;
                        state           <= ST_ACTIVE;
                    end else if (object_eligible) begin
                        active_object     <= 1'b1;
                        object_sdram_addr <= object_addr;
                        object_seen       <= 1'b1;
                        prefer_object     <= 1'b0;
                        state             <= ST_ACTIVE;
                    end
                end

                ST_ACTIVE: begin
                    if (active_object) begin
                        if (object_sdram_ok) begin
                            object_data <= object_sdram_data;
                            object_ok_q <= 1'b1;
                            state       <= ST_GAP;
                        end
                    end else if (tile_sdram_ok) begin
                        tile_data <= tile_sdram_data;
                        tile_ok_q <= 1'b1;
                        state     <= ST_GAP;
                    end
                end

                ST_GAP: begin
                    // This state always occupies at least the complete clock
                    // following a response.  Waiting for both levels protects
                    // against a non-selected stale response as well.
                    if (!tile_sdram_ok && !object_sdram_ok)
                        state <= ST_IDLE;
                end

                default: begin
                    state         <= ST_GAP;
                    active_object <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
