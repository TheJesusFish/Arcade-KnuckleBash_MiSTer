// SPDX-License-Identifier: GPL-2.0-or-later
//
// Whole-machine save-state sequencer. The 68000 enters a private IRQ7 handler
// that stacks every architectural register in work RAM. The handler remains
// resident while memory is streamed and later restores the frame with RTE.
module knuckle_bash_savestate_controller (
    input  logic        clk,
    input  logic        rst,
    input  logic        safe_boundary,
    input  logic        video_ready,
    input  logic        main_held,
    input  logic        sound_held,
    input  logic        save_req,
    input  logic        load_req,
    input  logic        stream_busy,
    input  logic        restore_compatible,
    input  logic [31:0] restore_ssp,
    input  logic        cpu_ack,
    input  logic        cpu_iack,
    input  logic        cpu_rw,
    input  logic        cpu_lds_n,
    input  logic [ 2:0] cpu_fc,
    input  logic [23:0] cpu_addr,
    input  logic [15:0] cpu_dout,
    output logic        save_start,
    output logic        load_start,
    output logic        active,
    output logic        ss_irq,
    output logic        ss_override,
    output logic        ss_reset,
    output logic        cpu_run,
    output logic        device_hold,
    output logic        video_reset,
    output logic        restore_commit,
    output logic [31:0] saved_ssp,
    output logic [63:0] reset_vector
);

typedef enum logic [3:0] {
    SS_IDLE,
    SS_SAVE_WAIT_SAFE,
    SS_SAVE_WAIT_IRQ,
    SS_SAVE_WAIT_SSP,
    SS_SAVE_WAIT_HOLD,
    SS_SAVE_WAIT_STREAM,
    SS_SAVE_WAIT_EXIT,
    SS_SAVE_WAIT_VIDEO,
    SS_RESTORE_WAIT_SAFE,
    SS_RESTORE_WAIT_HOLD,
    SS_RESTORE_WAIT_STREAM,
    SS_RESTORE_HOLD_RESET,
    SS_RESTORE_WAIT_RESET,
    SS_RESTORE_WAIT_VIDEO
} state_t;

state_t state = SS_IDLE;
logic [7:0] reset_counter = 8'd0;
logic video_frame_seen = 1'b0;
logic video_ready_seen = 1'b0;

always_comb begin
    active = state != SS_IDLE;
    ss_irq = state == SS_SAVE_WAIT_IRQ;
    ss_override = (state == SS_SAVE_WAIT_SSP) ||
                  (state == SS_SAVE_WAIT_EXIT) ||
                  (state == SS_RESTORE_HOLD_RESET) ||
                  (state == SS_RESTORE_WAIT_RESET);
    ss_reset = state == SS_RESTORE_HOLD_RESET;
    cpu_run = (state != SS_SAVE_WAIT_HOLD) &&
              (state != SS_SAVE_WAIT_STREAM) &&
              (state != SS_SAVE_WAIT_VIDEO) &&
              (state != SS_RESTORE_WAIT_HOLD) &&
              (state != SS_RESTORE_WAIT_STREAM) &&
              (state != SS_RESTORE_WAIT_VIDEO);
    device_hold = (state != SS_IDLE) &&
                  (state != SS_SAVE_WAIT_SAFE) &&
                  (state != SS_RESTORE_WAIT_SAFE);
    video_reset = (state == SS_RESTORE_WAIT_HOLD) ||
                  (state == SS_RESTORE_WAIT_STREAM) ||
                  (state == SS_RESTORE_HOLD_RESET);
end

always_ff @(posedge clk) begin
    if (rst) begin
        state <= SS_IDLE;
        save_start <= 1'b0;
        load_start <= 1'b0;
        restore_commit <= 1'b0;
        reset_counter <= 8'd0;
        saved_ssp <= 32'd0;
        reset_vector <= 64'd0;
        video_frame_seen <= 1'b0;
        video_ready_seen <= 1'b0;
    end else begin
        restore_commit <= 1'b0;
        if (active && safe_boundary)
            video_frame_seen <= 1'b1;
        if (active && video_ready)
            video_ready_seen <= 1'b1;

        unique case (state)
            SS_IDLE: begin
                save_start <= 1'b0;
                load_start <= 1'b0;
                video_frame_seen <= 1'b0;
                video_ready_seen <= 1'b0;
                if (save_req)
                    state <= SS_SAVE_WAIT_SAFE;
                else if (load_req)
                    state <= SS_RESTORE_WAIT_SAFE;
            end

            SS_SAVE_WAIT_SAFE: begin
                if (safe_boundary)
                    state <= SS_SAVE_WAIT_IRQ;
            end

            SS_SAVE_WAIT_IRQ: begin
                if (cpu_iack && (cpu_addr[3:1] == 3'b111) && !cpu_lds_n)
                    state <= SS_SAVE_WAIT_SSP;
            end

            SS_SAVE_WAIT_SSP: begin
                if (cpu_ack && !cpu_rw && cpu_addr == 24'hff0000)
                    saved_ssp[31:16] <= cpu_dout;
                if (cpu_ack && !cpu_rw && cpu_addr == 24'hff0002) begin
                    saved_ssp[15:0] <= cpu_dout;
                    state <= SS_SAVE_WAIT_HOLD;
                end
            end

            SS_SAVE_WAIT_HOLD: begin
                if (main_held && sound_held) begin
                    save_start <= 1'b1;
                    state <= SS_SAVE_WAIT_STREAM;
                end
            end

            SS_SAVE_WAIT_STREAM: begin
                if (stream_busy && save_start)
                    save_start <= 1'b0;
                else if (!stream_busy && !save_start)
                    state <= SS_SAVE_WAIT_EXIT;
            end

            SS_SAVE_WAIT_EXIT: begin
                if (cpu_ack && cpu_rw && (cpu_fc == 3'b110) &&
                    (cpu_addr[23:8] != 16'hff00)) begin
                    video_frame_seen <= 1'b0;
                    state <= SS_SAVE_WAIT_VIDEO;
                end
            end

            SS_SAVE_WAIT_VIDEO: begin
                if (safe_boundary && video_frame_seen)
                    state <= SS_IDLE;
            end

            SS_RESTORE_WAIT_SAFE: begin
                if (safe_boundary)
                    state <= SS_RESTORE_WAIT_HOLD;
            end

            SS_RESTORE_WAIT_HOLD: begin
                if (main_held && sound_held) begin
                    load_start <= 1'b1;
                    state <= SS_RESTORE_WAIT_STREAM;
                end
            end

            SS_RESTORE_WAIT_STREAM: begin
                if (stream_busy && load_start)
                    load_start <= 1'b0;
                else if (!stream_busy && !load_start) begin
                    video_frame_seen <= 1'b0;
                    video_ready_seen <= 1'b0;
                    if (restore_compatible) begin
                        reset_vector <= {restore_ssp[31:16], restore_ssp[15:0],
                                         16'h00ff, 16'h0008};
                        reset_counter <= 8'd0;
                        restore_commit <= 1'b1;
                        state <= SS_RESTORE_HOLD_RESET;
                    end else begin
                        state <= SS_RESTORE_WAIT_VIDEO;
                    end
                end
            end

            SS_RESTORE_HOLD_RESET: begin
                reset_counter <= reset_counter + 8'd1;
                if (&reset_counter)
                    state <= SS_RESTORE_WAIT_RESET;
            end

            SS_RESTORE_WAIT_RESET: begin
                if (cpu_ack && cpu_rw && (cpu_fc == 3'b110) &&
                    (cpu_addr[23:8] != 16'hff00) &&
                    (cpu_addr >= 24'h000008))
                    state <= SS_RESTORE_WAIT_VIDEO;
            end

            SS_RESTORE_WAIT_VIDEO: begin
                // video_ready is intentionally low on the exact frame tick
                // because the ordinary snapshot path is being rebuilt there.
                // Remember readiness, then release on the following boundary.
                if (safe_boundary && video_frame_seen && video_ready_seen)
                    state <= SS_IDLE;
            end

            default: state <= SS_IDLE;
        endcase
    end
end

endmodule
