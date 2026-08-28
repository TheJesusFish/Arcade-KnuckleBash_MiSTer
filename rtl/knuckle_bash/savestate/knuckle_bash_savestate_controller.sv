// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_savestate_controller (
    input  logic clk,
    input  logic rst,
    input  logic safe_boundary,
    input  logic save_req,
    input  logic load_req,
    output logic save_start,
    output logic load_start,
    output logic active
);

typedef enum logic [1:0] {
    ST_IDLE,
    ST_PENDING_SAVE,
    ST_PENDING_LOAD,
    ST_ACTIVE
} state_t;

state_t state;
logic [3:0] active_count;

always_ff @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        active_count <= 4'd0;
        save_start <= 1'b0;
        load_start <= 1'b0;
        active <= 1'b0;
    end else begin
        save_start <= 1'b0;
        load_start <= 1'b0;

        unique case (state)
        ST_IDLE: begin
            active <= 1'b0;
            if (save_req)
                state <= ST_PENDING_SAVE;
            else if (load_req)
                state <= ST_PENDING_LOAD;
        end

        ST_PENDING_SAVE: begin
            active <= 1'b1;
            if (safe_boundary) begin
                save_start <= 1'b1;
                active_count <= 4'd8;
                state <= ST_ACTIVE;
            end
        end

        ST_PENDING_LOAD: begin
            active <= 1'b1;
            if (safe_boundary) begin
                load_start <= 1'b1;
                active_count <= 4'd8;
                state <= ST_ACTIVE;
            end
        end

        default: begin
            active <= 1'b1;
            if (active_count == 4'd0) begin
                active <= 1'b0;
                state <= ST_IDLE;
            end else begin
                active_count <= active_count - 4'd1;
            end
        end
        endcase
    end
end

endmodule
