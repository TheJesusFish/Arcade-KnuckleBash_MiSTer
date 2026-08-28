// SPDX-License-Identifier: GPL-2.0-or-later
// Board-owned HDMI capture. Native analog video does not pass through DDR3.
// Three 8 MiB slots use the framework screen_rotate reservation at 0x24000000.
// Only complete, accepted frames become visible, at the HDMI vblank boundary.
module knuckle_bash_framebuffer #(
    parameter integer FIFO_BITS = 8
) (
    input  logic clk, reset, enable,
    input  logic ce_pixel, vs, de,
    input  logic [23:0] rgb,
    input  logic [11:0] input_width, input_height,
    input  logic rotate_ccw, flip,
    input  logic fb_vbl,
    output wire fb_en, fb_force_blank,
    output wire [4:0] fb_format,
    output logic [11:0] fb_width, fb_height,
    output wire [31:0] fb_base,
    output logic [13:0] fb_stride,
    input  logic ddram_busy,
    output wire [7:0] ddram_burstcnt,
    output wire [28:0] ddram_addr,
    output wire [63:0] ddram_din,
    output wire [7:0] ddram_be,
    output wire ddram_we, ddram_rd
);
localparam [6:0] MEM_BASE = 7'b0010010;
localparam integer FIFO_DEPTH = 1 << FIFO_BITS;

// Packed queue entry: buffer, byte offset, 00BBGGRR. Payload remains stable
// throughout waitrequest, including when direct_video disables new capture.
(* ramstyle = "M10K, no_rw_check" *) logic [56:0] fifo [0:FIFO_DEPTH-1];
logic [FIFO_BITS-1:0] wr_ptr, rd_ptr;
logic [FIFO_BITS:0] queued;
logic [56:0] request;
logic request_valid;
wire pop = (!request_valid || !ddram_busy) && queued != 0;
// Do not read and overwrite the same full-FIFO address on one edge (the
// inferred M10K deliberately has no mixed-port read-during-write guarantee).
wire room = queued < FIFO_DEPTH;
wire drained = queued == 0 && !request_valid;

logic [1:0] read_buf, write_buf, ready_buf;
logic ready_valid, display_valid;
logic [11:0] widths [0:2], heights [0:2];
logic [13:0] strides [0:2];
(* async_reg = "true" *) logic vbl_meta, vbl_sync;
logic vbl_last, vs_last, de_last;
wire present = vbl_sync && !vbl_last && ready_valid;
wire source_boundary = ce_pixel && vs && !vs_last;
wire [1:0] next_read = present ? ready_buf : read_buf;

logic active, bad_frame;
logic [11:0] capture_width, capture_height, x, y;
logic capture_rotate, capture_flip;
logic [13:0] capture_stride;
logic [22:0] row_offset, pixel_offset;
wire [11:0] output_width = rotate_ccw ? input_height : input_width;
wire [11:0] output_height = rotate_ccw ? input_width : input_height;
wire [12:0] padded_width = {1'b0, output_width} + 13'd3;
wire [13:0] output_stride = {padded_width[11:2], 4'b0};
wire [22:0] last_row = (23'(output_height) - 23'd1) * 23'(output_stride);
wire [22:0] first_offset = rotate_ccw ? last_row :
                          flip ? last_row + ((23'(input_width)-23'd1) << 2) : 23'd0;
wire config_valid = input_width != 0 && input_height != 0 &&
                    input_width <= 640 && input_height <= 480;
wire config_same = {capture_width, capture_height, capture_rotate, capture_flip} ==
                   {input_width, input_height, rotate_ccw, flip};
wire pixel = enable && active && !bad_frame && config_same &&
             ce_pixel && de && !source_boundary && x < capture_width && y < capture_height;
wire push = pixel && room;
wire complete_frame = active && !bad_frame && config_same && drained &&
                      y == capture_height && x == 0;

function automatic [1:0] free_buffer(input [1:0] a, b);
    if (a != 0 && b != 0) free_buffer = 0;
    else if (a != 1 && b != 1) free_buffer = 1;
    else free_buffer = 2;
endfunction

assign fb_en = enable;
assign fb_force_blank = !display_valid;
assign fb_format = 5'b00110;
assign fb_base = {MEM_BASE, read_buf, 23'd0};
assign ddram_burstcnt = 8'd1;
assign ddram_addr = {MEM_BASE, request[56:55], request[54:35]};
assign ddram_din = {request[31:0], request[31:0]};
assign ddram_be = request[34] ? 8'hf0 : 8'h0f;
assign ddram_we = request_valid;
assign ddram_rd = 1'b0;

always_ff @(posedge clk) begin
    if (reset) begin
        wr_ptr <= 0;
        rd_ptr <= 0;
        queued <= 0;
        request <= 0;
        request_valid <= 0;
    end else begin
        if (push) begin
            fifo[wr_ptr] <= {write_buf, pixel_offset, 8'd0, rgb[7:0], rgb[15:8], rgb[23:16]};
            wr_ptr <= wr_ptr + 1'b1;
        end
        if (!request_valid || !ddram_busy) begin
            request_valid <= pop;
            if (pop) begin
                request <= fifo[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
        case ({push,pop})
            2'b10: queued <= queued + 1'b1;
            2'b01: queued <= queued - 1'b1;
            default: ;
        endcase
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        vbl_meta <= 0; vbl_sync <= 0; vbl_last <= 0;
        vs_last <= 0; de_last <= 0;
        read_buf <= 0; write_buf <= 1; ready_buf <= 2;
        ready_valid <= 0; display_valid <= 0;
        active <= 0; bad_frame <= 0;
        capture_width <= 0; capture_height <= 0;
        capture_rotate <= 0; capture_flip <= 0; capture_stride <= 0;
        row_offset <= 0; pixel_offset <= 0; x <= 0; y <= 0;
        fb_width <= 320; fb_height <= 240; fb_stride <= 1280;
        for (integer i = 0; i < 3; i++) begin
            widths[i] <= 320; heights[i] <= 240; strides[i] <= 1280;
        end
    end else begin
        vbl_meta <= fb_vbl;
        vbl_sync <= vbl_meta;
        vbl_last <= vbl_sync;
        if (ce_pixel) begin
            vs_last <= vs;
            de_last <= de;
        end
        if (!enable) begin
            active <= 0;
            ready_valid <= 0;
            display_valid <= 0;
        end else begin
            // Latest complete frame wins. Even in low-latency HDMI mode, never
            // display a buffer still being written; no speculative two-buffer
            // scan race. Analog timing and latency are completely independent.
            if (present) begin
                read_buf <= ready_buf;
                ready_valid <= 0;
                display_valid <= 1;
                fb_width <= widths[ready_buf];
                fb_height <= heights[ready_buf];
                fb_stride <= strides[ready_buf];
            end
            if (active && !config_same) bad_frame <= 1;
            if (ce_pixel && active) begin
                if (de) begin
                    if (x >= capture_width || y >= capture_height || !room)
                        bad_frame <= 1;
                    if (x < 12'hfff) x <= x + 1'b1;
                    pixel_offset <= capture_rotate ? pixel_offset - 23'(capture_stride) :
                                    capture_flip ? pixel_offset - 23'd4 : pixel_offset + 23'd4;
                end else if (de_last) begin
                    if (x != capture_width) bad_frame <= 1;
                    x <= 0;
                    if (y < 12'hfff) y <= y + 1'b1;
                    row_offset <= capture_rotate ? row_offset + 23'd4 :
                                  capture_flip ? row_offset - 23'(capture_stride) :
                                                 row_offset + 23'(capture_stride);
                    pixel_offset <= capture_rotate ? row_offset + 23'd4 :
                                    capture_flip ? row_offset - 23'(capture_stride) :
                                                   row_offset + 23'(capture_stride);
                end
            end
            if (source_boundary) begin
                if (complete_frame) begin
                    ready_buf <= write_buf;
                    ready_valid <= 1;
                    widths[write_buf] <= capture_rotate ? capture_height : capture_width;
                    heights[write_buf] <= capture_rotate ? capture_width : capture_height;
                    strides[write_buf] <= capture_stride;
                    write_buf <= free_buffer(next_read, write_buf);
                end
                // A stalled/overflowed frame is discarded, not shown. Wait for
                // all old transactions to drain before reusing its write slot.
                active <= drained && config_valid;
                bad_frame <= 0;
                capture_width <= input_width; capture_height <= input_height;
                capture_rotate <= rotate_ccw; capture_flip <= flip;
                capture_stride <= output_stride;
                row_offset <= first_offset; pixel_offset <= first_offset;
                x <= 0; y <= 0;
            end
        end
    end
end
endmodule
