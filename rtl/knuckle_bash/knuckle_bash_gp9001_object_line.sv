// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 single-GP9001 buffered object-line builder.
//
// Object descriptors are consumed in ascending RAM order, exactly as MAME
// 0.288 draw_sprites() does. Later opaque pixels therefore replace earlier
// pixels on equal priority. The object source is the preceding-frame snapshot;
// this block owns only the two transient 320-pixel line buffers.
//
// Graphics stay in the Knuckle Bash raw 8 MiB layout:
//   n        = (code[17:0] << 3) + source_y[2:0]
//   lower    = n
//   upper    = 22'h200000 + n
//   pen      = {H[8+k], H[k], L[8+k], L[k]}, k = 7-source_x
//
// MAX_VISIBLE_CHUNKS bounds serialized SDRAM work. Once the limit is reached,
// the deterministic retained prefix is complete, so the line terminates
// immediately and publishes normally. No later descriptor can change a full
// retained prefix; capacity_overflow explicitly reports the truncation.
module knuckle_bash_gp9001_object_line #(
    // Provisional bring-up cap. Integrated tile+object contention reaches
    // 5,511/6,048 object clocks (5,529 elapsed) at 112 chunks under the
    // bounded BA endpoint model;
    // higher values remain configurable for negative/stress verification.
    parameter integer MAX_VISIBLE_CHUNKS = 112,
    parameter integer LINE_DEADLINE_CYCLES = 6048
) (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    input  logic         commit,
    input  logic [ 8:0]  target_y,
    input  logic         target_epoch,
    input  logic [127:0] scrolls,
    input  logic [ 7:0]  scroll_flip,

    output logic         busy,
    output logic         done,
    output logic         deadline_miss,
    output logic         capacity_overflow,
    output logic [15:0]  last_build_cycles,

    output logic [ 9:0]  object_addr,
    input  logic [15:0]  object_data,

    output logic         gfx_req,
    output logic [21:0]  gfx_addr,
    input  logic [15:0]  gfx_data,
    input  logic         gfx_ok,

    input  logic [ 8:0]  scan_x,
    output logic [14:0]  scan_pixel,
    output logic [ 8:0]  scan_y,
    output logic         scan_epoch,
    output logic         scan_valid
);

localparam logic [4:0] ST_IDLE         = 5'd0;
localparam logic [4:0] ST_CLEAR        = 5'd1;
localparam logic [4:0] ST_DESC_PRIME   = 5'd2;
localparam logic [4:0] ST_DESC_ATTR    = 5'd3;
localparam logic [4:0] ST_DESC_CODE    = 5'd4;
localparam logic [4:0] ST_DESC_X       = 5'd5;
localparam logic [4:0] ST_DESC_Y       = 5'd6;
localparam logic [4:0] ST_DESC_PROCESS = 5'd7;
localparam logic [4:0] ST_GFX_LO       = 5'd8;
localparam logic [4:0] ST_GFX_GAP      = 5'd9;
localparam logic [4:0] ST_GFX_HI       = 5'd10;
localparam logic [4:0] ST_DRAW_READ    = 5'd11;
localparam logic [4:0] ST_DRAW_WRITE   = 5'd12;
localparam logic [4:0] ST_DONE         = 5'd13;
localparam logic [4:0] ST_DESC_GEOM    = 5'd14;

logic [4:0] state;
logic [8:0] clear_x;
logic [7:0] descriptor;
logic [15:0] desc_attr;
logic [15:0] desc_code;
logic [15:0] desc_x;
logic [15:0] desc_y;

logic [8:0] old_x;
logic [8:0] old_y;
logic [8:0] target_y_latched;
logic       target_epoch_latched;
logic [127:0] scrolls_latched;
logic [7:0] scroll_flip_latched;

logic signed [11:0] desc_pre_x_latched;
logic signed [11:0] desc_pre_y_latched;
logic signed [11:0] sprite_x_base;
logic signed [12:0] desc_line_delta_latched;
logic               desc_hits_line_latched;
logic [4:0] sprite_x_chunks;
logic [4:0] sprite_y_chunks;
logic [17:0] sprite_code_row;
logic [3:0] sprite_priority;
logic [5:0] sprite_color;
logic       sprite_flip_x;
logic [3:0] chunk;
logic [2:0] pixel;
logic [2:0] sprite_row;
logic [15:0] fetch_lo;
logic [15:0] fetch_hi;

logic       active_bank;
logic       build_bank;
logic       build_pending;
logic [15:0] build_cycle_count;
logic [8:0] visible_chunk_count;
logic       deadline_reported;

function automatic logic signed [11:0] wrapped_base(
    input logic [8:0] coordinate,
    input logic       local_flip
);
    logic [8:0] shifted;
    begin
        shifted = local_flip ? coordinate - 9'd7 : coordinate;
        if ((!local_flip && (shifted >= 9'h180)) ||
            ( local_flip && (shifted >= 9'h1c0)))
            wrapped_base = $signed({3'b000, shifted}) - 12'sd512;
        else
            wrapped_base = $signed({3'b000, shifted});
    end
endfunction

function automatic logic [3:0] decode_pen(
    input logic [15:0] lower_word,
    input logic [15:0] upper_word,
    input logic [2:0]  source_x
);
    logic [2:0] bit_index;
    begin
        bit_index = 3'd7 - source_x;
        decode_pen = {
            upper_word[{1'b1, bit_index}],
            upper_word[{1'b0, bit_index}],
            lower_word[{1'b1, bit_index}],
            lower_word[{1'b0, bit_index}]
        };
    end
endfunction

wire global_flip_x = scroll_flip_latched[6];
wire global_flip_y = scroll_flip_latched[7];

// MAME's default GP9001 sprite offsets are -0x1cc/-0x17b in X and
// -0x1ef/-0x108 in Y. Negating the adjusted scroll values yields these
// modulo-512 origins.
wire [8:0] sprite_x_origin = global_flip_x ? 9'd379 : 9'd460;
wire [8:0] sprite_y_origin = global_flip_y ? 9'd264 : 9'd495;
wire [8:0] sprite_scroll_x = scrolls_latched[104:96];
wire [8:0] sprite_scroll_y = scrolls_latched[120:112];

`ifdef SIMULATION
wire [8:0] desc_raw_x = desc_x[15:7];
wire [8:0] desc_raw_y = desc_y[15:7];
`endif
wire [8:0] capture_raw_position = object_data[15:7];
wire [8:0] capture_position_x = desc_attr[14] ?
    old_x + capture_raw_position :
    capture_raw_position - sprite_scroll_x + sprite_x_origin;
wire [8:0] capture_position_y = desc_attr[14] ?
    old_y + capture_raw_position :
    capture_raw_position - sprite_scroll_y + sprite_y_origin;

wire desc_local_flip_x = desc_attr[12];
wire desc_local_flip_y = desc_attr[13];
wire desc_effective_flip_x = desc_local_flip_x ^ global_flip_x;
wire desc_effective_flip_y = desc_local_flip_y ^ global_flip_y;
wire [17:0] desc_code_base = {desc_attr[1:0], desc_code};

wire signed [11:0] capture_pre_x =
    wrapped_base(capture_position_x, desc_local_flip_x);
wire signed [11:0] capture_pre_y =
    wrapped_base(capture_position_y, desc_local_flip_y);
wire signed [11:0] desc_base_x = global_flip_x ?
    12'sd320 - desc_pre_x_latched : desc_pre_x_latched;
wire signed [11:0] desc_base_y = global_flip_y ?
    12'sd240 - desc_pre_y_latched : desc_pre_y_latched;

wire signed [12:0] target_y_signed =
    $signed({4'b0000, target_y_latched});
wire signed [12:0] desc_base_y_extended =
    {desc_base_y[11], desc_base_y};
wire signed [12:0] desc_line_delta = desc_effective_flip_y ?
    desc_base_y_extended + 13'sd7 - target_y_signed :
    target_y_signed - desc_base_y_extended;
wire signed [12:0] desc_height =
    $signed({5'b00000, sprite_y_chunks, 3'b000});
wire desc_hits_line = desc_attr[15] &&
    (desc_line_delta >= 13'sd0) &&
    (desc_line_delta < desc_height);

wire [8:0] desc_row_code_offset =
    {5'd0, desc_line_delta_latched[6:3]} *
    {4'd0, sprite_x_chunks};
wire [17:0] desc_code_row =
    desc_code_base + {{9{1'b0}}, desc_row_code_offset};

wire signed [11:0] chunk_offset =
    $signed({4'b0000, chunk, 3'b000});
wire signed [11:0] chunk_x = sprite_flip_x ?
    sprite_x_base - chunk_offset :
    sprite_x_base + chunk_offset;
wire signed [12:0] chunk_x_extended = {chunk_x[11], chunk_x};
wire signed [12:0] chunk_x_end = chunk_x_extended + 13'sd7;
wire chunk_visible =
    (chunk_x_end >= 13'sd0) && (chunk_x_extended < 13'sd320);
wire chunk_budget_available =
    visible_chunk_count < MAX_VISIBLE_CHUNKS;
wire last_chunk = ({1'b0, chunk} + 5'd1) >= sprite_x_chunks;

wire [17:0] current_code =
    sprite_code_row + {{14{1'b0}}, chunk};
wire [20:0] gfx_plane_word =
    {current_code, 3'b000} + {18'd0, sprite_row};

always_comb begin
    gfx_req = 1'b0;
    gfx_addr = {1'b0, gfx_plane_word};

    if ((state == ST_GFX_LO) && chunk_visible &&
        chunk_budget_available) begin
        gfx_req = 1'b1;
        gfx_addr = {1'b0, gfx_plane_word};
    end else if (state == ST_GFX_HI) begin
        gfx_req = 1'b1;
        gfx_addr = {1'b1, gfx_plane_word};
    end
end

// The object snapshot has a one-clock synchronous output. Each capture state
// presents the following word, so after the one-state prime the four words
// stream at one word per clock. During rendering, word zero of the following
// descriptor remains prefetched.
always_comb begin
    object_addr = {descriptor, 2'b00};

    case (state)
        ST_DESC_PRIME:
            object_addr = {descriptor, 2'b00};
        ST_DESC_ATTR:
            object_addr = {descriptor, 2'b01};
        ST_DESC_CODE:
            object_addr = {descriptor, 2'b10};
        ST_DESC_X:
            object_addr = {descriptor, 2'b11};
        ST_DESC_Y,
        ST_DESC_PROCESS,
        ST_DESC_GEOM,
        ST_GFX_LO,
        ST_GFX_GAP,
        ST_GFX_HI,
        ST_DRAW_READ,
        ST_DRAW_WRITE: begin
            if (descriptor != 8'hff)
                object_addr = {descriptor + 8'd1, 2'b00};
        end
        default:
            object_addr = {descriptor, 2'b00};
    endcase
end

wire signed [11:0] source_x_offset = sprite_flip_x ?
    $signed({9'b000000000, (3'd7 - pixel)}) :
    $signed({9'b000000000, pixel});
wire signed [11:0] draw_x = chunk_x + source_x_offset;
wire draw_x_visible = (draw_x >= 12'sd0) && (draw_x < 12'sd320);
wire [3:0] candidate_pen = decode_pen(fetch_lo, fetch_hi, pixel);
wire [14:0] candidate_pixel = {
    sprite_priority, 1'b0, sprite_color, candidate_pen
};

wire [8:0] line_build_addr =
    (state == ST_CLEAR) ? clear_x : draw_x[8:0];
wire [14:0] line_bank0_build_q;
wire [14:0] line_bank1_build_q;
wire [14:0] line_bank0_scan_q;
wire [14:0] line_bank1_scan_q;
wire [14:0] line_build_q =
    build_bank ? line_bank1_build_q : line_bank0_build_q;

wire line_clear_write = state == ST_CLEAR;
wire candidate_wins = draw_x_visible &&
    (candidate_pen != 4'h0) &&
    (sprite_priority >= line_build_q[14:11]);
wire line_draw_write = (state == ST_DRAW_WRITE) && candidate_wins;
wire bank0_build_write =
    !build_bank && (line_clear_write || line_draw_write);
wire bank1_build_write =
     build_bank && (line_clear_write || line_draw_write);
wire [14:0] line_build_data =
    line_clear_write ? 15'd0 : candidate_pixel;

assign scan_pixel =
    active_bank ? line_bank1_scan_q : line_bank0_scan_q;

jtframe_dual_ram #(.DW(15), .AW(9)) u_line_bank0 (
    .clk0  (clk),
    .data0 (line_build_data),
    .addr0 (line_build_addr),
    .we0   (bank0_build_write),
    .q0    (line_bank0_build_q),
    .clk1  (clk),
    .data1 (15'd0),
    .addr1 (scan_x),
    .we1   (1'b0),
    .q1    (line_bank0_scan_q)
);

jtframe_dual_ram #(.DW(15), .AW(9)) u_line_bank1 (
    .clk0  (clk),
    .data0 (line_build_data),
    .addr0 (line_build_addr),
    .we0   (bank1_build_write),
    .q0    (line_bank1_build_q),
    .clk1  (clk),
    .data1 (15'd0),
    .addr1 (scan_x),
    .we1   (1'b0),
    .q1    (line_bank1_scan_q)
);

always_ff @(posedge clk) begin
    done <= 1'b0;
    deadline_miss <= 1'b0;

    if (rst) begin
        state                 <= ST_IDLE;
        busy                  <= 1'b0;
        clear_x               <= 9'd0;
        descriptor            <= 8'd0;
        desc_attr             <= 16'd0;
        desc_code             <= 16'd0;
        desc_x                <= 16'd0;
        desc_y                <= 16'd0;
        old_x                 <= 9'd0;
        old_y                 <= 9'd0;
        target_y_latched      <= 9'd0;
        target_epoch_latched  <= 1'b0;
        scrolls_latched       <= 128'd0;
        scroll_flip_latched   <= 8'd0;
        desc_pre_x_latched    <= 12'sd0;
        desc_pre_y_latched    <= 12'sd0;
        sprite_x_base         <= 12'sd0;
        desc_line_delta_latched <= 13'sd0;
        desc_hits_line_latched <= 1'b0;
        sprite_x_chunks       <= 5'd1;
        sprite_y_chunks       <= 5'd1;
        sprite_code_row       <= 18'd0;
        sprite_priority       <= 4'd0;
        sprite_color          <= 6'd0;
        sprite_flip_x         <= 1'b0;
        chunk                 <= 4'd0;
        pixel                 <= 3'd0;
        sprite_row            <= 3'd0;
        fetch_lo              <= 16'd0;
        fetch_hi              <= 16'd0;
        active_bank           <= 1'b0;
        build_bank            <= 1'b1;
        build_pending         <= 1'b0;
        build_cycle_count     <= 16'd0;
        visible_chunk_count   <= 9'd0;
        deadline_reported     <= 1'b0;
        capacity_overflow     <= 1'b0;
        last_build_cycles     <= 16'd0;
        scan_y                <= 9'd0;
        scan_epoch            <= 1'b0;
        scan_valid            <= 1'b0;
    end else begin
        if (commit && build_pending) begin
            if (deadline_reported) begin
                // A line that missed its fixed publication deadline is not
                // safe to expose. Capacity saturation is different: it is a
                // deterministic retained prefix, already reported through
                // capacity_overflow, and is published like the bounded
                // GP9001 reference renderers.
                scan_valid    <= 1'b0;
            end else begin
                active_bank <= build_bank;
                scan_y      <= target_y_latched;
                scan_epoch  <= target_epoch_latched;
                scan_valid  <= 1'b1;
            end
            build_pending <= 1'b0;
        end else if (commit && scan_valid) begin
            deadline_miss <= 1'b1;
        end

        if (start && (state != ST_IDLE))
            deadline_miss <= 1'b1;

        if (state != ST_IDLE) begin
            build_cycle_count <= build_cycle_count + 16'd1;
            if (!deadline_reported &&
                (build_cycle_count + 16'd1 >= LINE_DEADLINE_CYCLES)) begin
                deadline_miss     <= 1'b1;
                deadline_reported <= 1'b1;
            end
        end

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    if (build_pending && !commit) begin
                        // Preserve the completed, uncommitted line rather
                        // than silently overwriting its bank.
                        deadline_miss <= 1'b1;
                    end else begin
                        busy <= 1'b1;
                        build_bank <= (commit && build_pending) ?
                            active_bank : ~active_bank;
                        target_y_latched <= target_y;
                        target_epoch_latched <= target_epoch;
                        scrolls_latched <= scrolls;
                        scroll_flip_latched <= scroll_flip;
                        clear_x <= 9'd0;
                        descriptor <= 8'd0;
                        old_x <= (scroll_flip[6] ? 9'd379 : 9'd460) -
                                 scrolls[104:96];
                        old_y <= (scroll_flip[7] ? 9'd264 : 9'd495) -
                                 scrolls[120:112];
                        build_cycle_count <= 16'd0;
                        visible_chunk_count <= 9'd0;
                        deadline_reported <= 1'b0;
                        capacity_overflow <= 1'b0;
                        state <= ST_CLEAR;
                    end
                end
            end

            ST_CLEAR: begin
                if (clear_x == 9'd319) begin
                    descriptor <= 8'd0;
                    state <= ST_DESC_PRIME;
                end else begin
                    clear_x <= clear_x + 9'd1;
                end
            end

            ST_DESC_PRIME:
                state <= ST_DESC_ATTR;

            ST_DESC_ATTR: begin
                desc_attr <= object_data;
                state <= ST_DESC_CODE;
            end

            ST_DESC_CODE: begin
                desc_code <= object_data;
                state <= ST_DESC_X;
            end

            ST_DESC_X: begin
                desc_x <= object_data;
                desc_pre_x_latched <= capture_pre_x;
                sprite_x_chunks <=
                    {1'b0, object_data[3:0]} + 5'd1;
                if (desc_attr[15])
                    old_x <= capture_position_x;
                state <= ST_DESC_Y;
            end

            ST_DESC_Y: begin
                desc_y <= object_data;
                desc_pre_y_latched <= capture_pre_y;
                sprite_y_chunks <=
                    {1'b0, object_data[3:0]} + 5'd1;
                desc_hits_line_latched <= 1'b0;
                if (desc_attr[15])
                    old_y <= capture_position_y;
                state <= desc_attr[15] ?
                    ST_DESC_GEOM : ST_DESC_PROCESS;
            end

            ST_DESC_GEOM: begin
                // The local position/wrap work was captured while the two
                // coordinate words streamed from object RAM. This stage now
                // contains only global transform and line selection.
                sprite_x_base          <= desc_base_x;
                desc_line_delta_latched <= desc_line_delta;
                desc_hits_line_latched <= desc_hits_line;
                sprite_priority     <= desc_attr[11:8];
                sprite_color        <= desc_attr[7:2];
                sprite_flip_x       <= desc_effective_flip_x;
                state               <= ST_DESC_PROCESS;
            end

            ST_DESC_PROCESS: begin
                // Registered line geometry isolates the row/code multiply
                // from scroll subtraction, wrapping, and hit comparison.
                if (desc_hits_line_latched) begin
                    sprite_code_row <= desc_code_row;
                    sprite_row <= desc_line_delta_latched[2:0];
                    chunk <= 4'd0;
                    state <= ST_GFX_LO;
                end else if (descriptor == 8'hff) begin
                    state <= ST_DONE;
                end else begin
                    descriptor <= descriptor + 8'd1;
                    state <= ST_DESC_ATTR;
                end
            end

            ST_GFX_LO: begin
                if (!chunk_visible) begin
                    if (!last_chunk) begin
                        chunk <= chunk + 4'd1;
                    end else if (descriptor == 8'hff) begin
                        state <= ST_DONE;
                    end else begin
                        descriptor <= descriptor + 8'd1;
                        state <= ST_DESC_ATTR;
                    end
                end else if (!chunk_budget_available) begin
                    // The retained prefix is already full. Continuing the
                    // serialized descriptor walk cannot alter it and can turn
                    // an otherwise bounded line into a false deadline miss.
                    capacity_overflow <= 1'b1;
                    state <= ST_DONE;
                end else if (gfx_ok) begin
                    fetch_lo <= gfx_data;
                    visible_chunk_count <= visible_chunk_count + 9'd1;
                    state <= ST_GFX_GAP;
                end
            end

            // A complete low request cycle is visible to an arbiter between
            // the two plane reads. Address and request remain unchanged in
            // each request state until gfx_ok.
            ST_GFX_GAP:
                state <= ST_GFX_HI;

            ST_GFX_HI: begin
                if (gfx_ok) begin
                    fetch_hi <= gfx_data;
                    pixel <= 3'd0;
                    state <= ST_DRAW_READ;
                end
            end

            ST_DRAW_READ:
                state <= ST_DRAW_WRITE;

            ST_DRAW_WRITE: begin
                if (pixel != 3'd7) begin
                    pixel <= pixel + 3'd1;
                    state <= ST_DRAW_READ;
                end else if (!last_chunk) begin
                    chunk <= chunk + 4'd1;
                    state <= ST_GFX_LO;
                end else if (descriptor == 8'hff) begin
                    state <= ST_DONE;
                end else begin
                    descriptor <= descriptor + 8'd1;
                    state <= ST_DESC_ATTR;
                end
            end

            ST_DONE: begin
                build_pending <= 1'b1;
                last_build_cycles <= build_cycle_count;
                busy <= 1'b0;
                done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                busy <= 1'b0;
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
