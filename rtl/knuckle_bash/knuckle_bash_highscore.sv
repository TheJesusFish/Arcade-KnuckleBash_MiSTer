// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Batsugun's board-local high-score manager. The MRA supplies
// MAME's exact descriptor at index 4 and a 264-byte NVRAM image at index 2.
// Knuckle Bash: 60 bytes at 0x100080; readiness bytes 00 / 30.
module knuckle_bash_highscore (
    input clk, reset, cpu_reset,
    input [1:0] set_id,
    input config_download, config_wr,
    input [26:0] config_addr,
    input [7:0] config_data,
    input nvram_download, nvram_upload, nvram_wr, nvram_rd,
    input [26:0] nvram_addr,
    input [7:0] nvram_data,
    output [7:0] nvram_q,
    output nvram_wait,
    input ss_active,
    input [12:0] normal_ram_addr,
    input [1:0] normal_ram_we,
    input [15:0] normal_ram_data,
    output hold_request,
    input hold_ack,
    output ram_owned,
    output [12:0] ram_addr,
    output [1:0] ram_we,
    output [15:0] ram_data,
    input [15:0] ram_q,
    output dirty, active, config_valid
);
localparam [8:0] NVRAM_SIZE = 9'd264;
localparam [8:0] SCORE_WINDOW_SIZE = 9'd256;
localparam [7:0] SCORE_DATA_SIZE = 8'd60;
localparam [3:0] ST_IDLE = 0, ST_RESTORE_HOLD = 3,
    ST_RESTORE_BUFFER_READ = 4, ST_RESTORE_RAM_WRITE = 5,
    ST_CAPTURE_HOLD = 6, ST_CAPTURE_RAM_READ = 7,
    ST_CAPTURE_BUFFER_WRITE = 8;

function automatic [7:0] expected_config_byte(input [2:0] address);
    case (address)
        0: expected_config_byte = 8'h00;
        1: expected_config_byte = 8'h10;
        2: expected_config_byte = 8'h00;
        3: expected_config_byte = 8'h80;
        4: expected_config_byte = 8'h00;
        5: expected_config_byte = 8'h3c;
        6: expected_config_byte = 8'h00;
        7: expected_config_byte = 8'h30;
    endcase
endfunction

function automatic [7:0] expected_trailer_byte(input [2:0] address);
    case (address)
        0: expected_trailer_byte = 8'h4b; // K
        1: expected_trailer_byte = 8'h42; // B
        2: expected_trailer_byte = 8'h48; // H
        3: expected_trailer_byte = 8'h53; // S
        4: expected_trailer_byte = 8'h01; // schema
        5: expected_trailer_byte = 8'h08; // trailer length
        6: expected_trailer_byte = {6'd0, set_id};
        7: expected_trailer_byte = 8'h3c; // payload length
    endcase
endfunction

reg config_download_d = 0, config_error = 0, config_valid_r = 0;
reg [3:0] config_count = 0;
reg nvram_download_d = 0, nvram_error = 0, nvram_valid = 0;
reg [8:0] nvram_count = 0;
wire [3:0] config_position = config_download_d ? config_count : 4'd0;
wire [8:0] nvram_position = nvram_download_d ? nvram_count : 9'd0;
reg [3:0] state = ST_IDLE;
reg [7:0] score_offset = 0;
reg [1:0] sentinel_seen = 0;
reg scores_ready = 0, restore_applied = 0, dirty_r = 0;
reg snapshot_valid = 0, nvram_upload_d = 0, upload_started = 0;
reg capture_ready = 0, upload_read_error = 0, changed_after_capture = 0;
reg [8:0] upload_read_count = 0;
// The committed bank survives CPU reset. Capture uses the other bank and
// publishes it only after a complete upload, preserving the previous save
// even if a later capture/upload is interrupted by reset.
reg restore_bank = 0, snapshot_bank = 1;
wire [13:0] score_byte_address = 14'h0080 + {6'd0, score_offset};
wire normal_score_write = (normal_ram_addr >= 13'h0040) &&
    (normal_ram_addr < 13'h005e) && (|normal_ram_we);
wire [7:0] load_buffer_cpu_q, snapshot_buffer_cpu_q;
wire [7:0] load_buffer_hps_q, snapshot_buffer_hps_q;
wire [7:0] restore_byte = restore_bank ? snapshot_buffer_cpu_q : load_buffer_cpu_q;
wire upload_complete = !nvram_upload && nvram_upload_d && capture_ready &&
    snapshot_valid && !upload_read_error && upload_read_count == NVRAM_SIZE;
wire [7:0] capture_byte = score_byte_address[0] ? ram_q[7:0] : ram_q[15:8];

// Batsugun-style synchronous buffers, with atomic bank promotion so an OSD
// reset restores the latest completed save rather than the startup image.
jtframe_dual_ram #(.DW(8), .AW(8)) u_load_buffer (
    .clk0(clk), .data0(nvram_data), .addr0(nvram_addr[7:0]),
    .we0(nvram_download && nvram_wr && nvram_addr < {18'd0, SCORE_WINDOW_SIZE}), .q0(load_buffer_hps_q),
    .clk1(clk), .data1(capture_byte), .addr1(score_offset),
    .we1(state == ST_CAPTURE_BUFFER_WRITE && !snapshot_bank), .q1(load_buffer_cpu_q)
);
jtframe_dual_ram #(.DW(8), .AW(8)) u_snapshot_buffer (
    .clk0(clk), .data0(8'd0), .addr0(nvram_addr[7:0]), .we0(1'b0), .q0(snapshot_buffer_hps_q),
    .clk1(clk), .data1(capture_byte), .addr1(score_offset),
    .we1(state == ST_CAPTURE_BUFFER_WRITE && snapshot_bank), .q1(snapshot_buffer_cpu_q)
);

always @(posedge clk) begin
    config_download_d <= config_download;
    nvram_download_d <= nvram_download;
    if (reset) begin
        config_download_d <= 0;
        config_count <= 0;
        config_error <= 0;
        config_valid_r <= 0;
        nvram_download_d <= 0;
        nvram_count <= 0;
        nvram_error <= 0;
        nvram_valid <= 0;
        restore_bank <= 0;
    end else begin
        if (upload_complete && !config_download && !nvram_download) begin
            nvram_valid <= 1;
            restore_bank <= snapshot_bank;
        end
        if (config_download && !config_download_d) begin
            config_count <= 0;
            config_error <= 0;
            config_valid_r <= 0;
        end
        if (config_download && config_wr) begin
            if (config_addr == {23'd0, config_position} && config_position < 8 &&
                config_data == expected_config_byte(config_position[2:0]))
                config_count <= config_position + 4'd1;
            else config_error <= 1;
        end
        if (!config_download && config_download_d)
            config_valid_r <= !config_error && config_count == 8;

        if (nvram_download && !nvram_download_d) begin
            nvram_count <= 0;
            nvram_error <= 0;
            nvram_valid <= 0;
        end
        if (nvram_download && nvram_wr) begin
            if (nvram_addr == {18'd0, nvram_position} && nvram_position < NVRAM_SIZE) begin
                nvram_count <= nvram_position + 9'd1;
                if (nvram_position >= SCORE_WINDOW_SIZE &&
                    nvram_data != expected_trailer_byte(nvram_position[2:0]))
                    nvram_error <= 1;
            end else nvram_error <= 1;
        end
        if (!nvram_download && nvram_download_d) begin
            nvram_valid <= config_valid_r && !nvram_error && nvram_count == NVRAM_SIZE;
            restore_bank <= 0;
        end
    end
end

always @(posedge clk) begin
    nvram_upload_d <= nvram_upload;
    if (reset || cpu_reset) begin
        state <= ST_IDLE;
        score_offset <= 0;
        sentinel_seen <= 0;
        scores_ready <= 0;
        restore_applied <= 0;
        dirty_r <= 0;
        snapshot_valid <= 0;
        nvram_upload_d <= 0;
        upload_started <= 0;
        capture_ready <= 0;
        upload_read_count <= 0;
        upload_read_error <= 0;
        changed_after_capture <= 0;
        snapshot_bank <= 1;
    end else begin
        // As in Batsugun, observe the initialization writes; these sentinel
        // values need not remain in the table after gameplay updates it.
        if (normal_ram_we[1] && normal_ram_addr == 13'h0040 && normal_ram_data[15:8] == 0)
            sentinel_seen[0] <= 1;
        if (normal_ram_we[0] && normal_ram_addr == 13'h005d && normal_ram_data[7:0] == 8'h30)
            sentinel_seen[1] <= 1;
        if (&sentinel_seen) scores_ready <= 1;

        if (config_download || nvram_download) begin
            state <= ST_IDLE;
            restore_applied <= 0;
            dirty_r <= 0;
            snapshot_valid <= 0;
            upload_started <= 0;
            capture_ready <= 0;
        end else begin
            if (scores_ready && (restore_applied || !nvram_valid) && normal_score_write)
                dirty_r <= 1;
            if (capture_ready && normal_score_write) changed_after_capture <= 1;

            if (nvram_upload && !nvram_upload_d) begin
                upload_started <= 1;
                capture_ready <= !config_valid_r;
                snapshot_valid <= 0;
                upload_read_count <= 0;
                upload_read_error <= 0;
            end
            // hps_io increments ioctl_addr on the edge producing ioctl_rd;
            // count completed reads, not the already-advanced address.
            if (nvram_upload && nvram_rd) begin
                if (capture_ready && snapshot_valid && upload_read_count < NVRAM_SIZE)
                    upload_read_count <= upload_read_count + 9'd1;
                else upload_read_error <= 1;
            end
            if (!nvram_upload && nvram_upload_d) begin
                if (capture_ready && snapshot_valid && !upload_read_error &&
                    upload_read_count == NVRAM_SIZE && !changed_after_capture && !normal_score_write)
                    dirty_r <= 0;
                // Promoting a new backing image must not restore it over
                // live game RAM (which can already contain a newer score).
                if (upload_complete) restore_applied <= 1;
                upload_started <= 0;
                capture_ready <= 0;
                upload_read_count <= 0;
                upload_read_error <= 0;
            end

            case (state)
                ST_IDLE: begin
                    if (config_valid_r && nvram_valid && scores_ready && !restore_applied && !ss_active)
                        state <= ST_RESTORE_HOLD;
                    else if (nvram_upload && upload_started && !capture_ready &&
                             config_valid_r && scores_ready && !ss_active)
                        state <= ST_CAPTURE_HOLD;
                end
                ST_RESTORE_HOLD: if (hold_ack) begin
                    score_offset <= 0;
                    state <= ST_RESTORE_BUFFER_READ;
                end
                ST_RESTORE_BUFFER_READ: state <= ST_RESTORE_RAM_WRITE;
                ST_RESTORE_RAM_WRITE: begin
                    if (score_offset == SCORE_DATA_SIZE - 8'd1) begin
                        restore_applied <= 1;
                        dirty_r <= 0;
                        state <= ST_IDLE;
                    end else begin
                        score_offset <= score_offset + 8'd1;
                        state <= ST_RESTORE_BUFFER_READ;
                    end
                end
                ST_CAPTURE_HOLD: if (hold_ack) begin
                    score_offset <= 0;
                    snapshot_bank <= !restore_bank;
                    changed_after_capture <= 0;
                    state <= ST_CAPTURE_RAM_READ;
                end
                ST_CAPTURE_RAM_READ: state <= ST_CAPTURE_BUFFER_WRITE;
                ST_CAPTURE_BUFFER_WRITE: begin
                    if (score_offset == SCORE_DATA_SIZE - 8'd1) begin
                        snapshot_valid <= 1;
                        capture_ready <= 1;
                        state <= ST_IDLE;
                    end else begin
                        score_offset <= score_offset + 8'd1;
                        state <= ST_CAPTURE_RAM_READ;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
end

assign hold_request = state != ST_IDLE;
assign ram_owned = state == ST_RESTORE_BUFFER_READ || state == ST_RESTORE_RAM_WRITE ||
                   state == ST_CAPTURE_RAM_READ || state == ST_CAPTURE_BUFFER_WRITE;
assign ram_addr = score_byte_address[13:1];
assign ram_we = state == ST_RESTORE_RAM_WRITE ?
    (score_byte_address[0] ? 2'b01 : 2'b10) : 2'b00;
assign ram_data = score_byte_address[0] ? {8'd0, restore_byte} : {restore_byte, 8'd0};
assign nvram_q = !snapshot_valid ? 8'd0 : nvram_addr < {19'd0, SCORE_DATA_SIZE} ?
    (snapshot_bank ? snapshot_buffer_hps_q : load_buffer_hps_q) :
    nvram_addr < {18'd0, SCORE_WINDOW_SIZE} ? 8'd0 :
    nvram_addr < {18'd0, NVRAM_SIZE} ? expected_trailer_byte(nvram_addr[2:0]) : 8'd0;
assign nvram_wait = nvram_upload && config_valid_r && !capture_ready;
assign dirty = dirty_r;
assign active = hold_request || (upload_started && !capture_ready);
assign config_valid = config_valid_r;
endmodule
