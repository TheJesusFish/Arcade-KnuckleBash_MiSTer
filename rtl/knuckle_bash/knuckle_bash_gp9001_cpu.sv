// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 single-GP9001 CPU-facing register and VRAM host.
//
// The four decoded ports follow MAME's GP9001 behavior:
//   0x0: VRAM word pointer write
//   0x4: VRAM read/write with post-increment
//   0x8: low-byte scroll/control selector write (data & 8'h8f)
//   0xc: status read or selected scroll/control write
//
// VRAM words 0x1c00-0x1fff mirror sprite words 0x1800-0x1bff. The scan port
// exposes the same live memory to a future renderer; this block deliberately
// does not invent object buffering or rendering behavior.
module knuckle_bash_gp9001_cpu (
    input  logic         clk,
    input  logic         rst,
    input  logic         flush,

    input  logic         req,
    input  logic         rw,
    input  logic [ 3:0]  addr,
    input  logic [15:0]  wdata,
    input  logic [ 1:0]  be,
    output logic         accept,
    output logic         done,
    output logic [15:0]  rdata,
    output logic         idle,

    input  logic         vint_set,
    input  logic         status_bit,
    output logic         irq4,

    input  logic [12:0]  scan_addr,
    output logic [15:0]  scan_data,

    output logic [12:0]  vram_pointer,
    output logic [ 7:0]  scroll_select,
    output logic [127:0] scrolls,
    output logic [ 7:0]  scroll_flip,

    input  logic         ss_restore_enable,
    input  logic [63:0]  ss_data,
    input  logic [31:0]  ss_addr,
    input  logic [ 7:0]  ss_select,
    input  logic         ss_write,
    input  logic         ss_read,
    input  logic         ss_query,
    output logic [63:0]  ss_data_out,
    output logic         ss_ack
);

localparam logic [2:0] ST_IDLE       = 3'd0;
localparam logic [2:0] ST_DISPATCH   = 3'd1;
localparam logic [2:0] ST_READ_WAIT0 = 3'd2;
localparam logic [2:0] ST_READ_WAIT1 = 3'd3;

logic [2:0]  state;
logic        req_rw;
logic [3:0]  req_addr;
logic [15:0] req_wdata;
logic [1:0]  req_be;
logic        req_status_bit;
logic        req_seen;

logic [15:0] scroll_reg [0:7];

logic [12:0] cpu_vram_addr;

wire [3:0] op = {req_addr[3:2], 2'b00};
wire [6:0] selected_index = scroll_select[6:0];
wire       selected_scroll = selected_index <= 7'h07;
wire       selected_vint_clear =
    (selected_index == 7'h0e) || (selected_index == 7'h0f);

function automatic logic [12:0] mirror_vram_addr(
    input logic [12:0] raw_addr
);
    begin
        mirror_vram_addr =
            (raw_addr >= 13'h1c00) ? raw_addr - 13'h0400 : raw_addr;
    end
endfunction

wire [12:0] mapped_pointer = mirror_vram_addr(vram_pointer);
wire [12:0] mapped_scan_addr = mirror_vram_addr(scan_addr);
wire        vram_write_commit =
    state == ST_DISPATCH && !req_rw && op == 4'h4 && !rst && !flush;
wire [12:0] cpu_vram_port_addr =
    vram_write_commit ? mapped_pointer : cpu_vram_addr;
wire [ 1:0] vram_we = vram_write_commit ? req_be : 2'b00;
wire [15:0] cpu_vram_q;
wire ss_vram_selected = ss_select == 8'd5;
wire ss_vram_access = ss_vram_selected && !ss_query && (ss_read || ss_write);
wire ss_regs_selected = ss_select == 8'd6;
wire ss_regs_access = ss_regs_selected && !ss_query && (ss_read || ss_write);
logic [15:0] vram_port1_q;

function automatic logic [15:0] merge_word(
    input logic [15:0] old_word,
    input logic [15:0] new_word,
    input logic [ 1:0] byte_enable
);
    begin
        merge_word = {
            byte_enable[1] ? new_word[15:8] : old_word[15:8],
            byte_enable[0] ? new_word[ 7:0] : old_word[ 7:0]
        };
    end
endfunction

wire [15:0] pointer_merged = merge_word(
    {3'b000, vram_pointer},
    req_wdata,
    req_be
);

wire [15:0] scroll_merged = merge_word(
    scroll_reg[scroll_select[2:0]],
    req_wdata,
    req_be
);

always_comb begin
    idle   = state == ST_IDLE;
    accept = req && idle && !req_seen && !rst && !flush;
    scrolls = {
        scroll_reg[7], scroll_reg[6], scroll_reg[5], scroll_reg[4],
        scroll_reg[3], scroll_reg[2], scroll_reg[1], scroll_reg[0]
    };
end

// Port 0 performs the mutually exclusive CPU read/write transactions. Port 1
// is the renderer's independent synchronous scan port. Keeping both accesses
// inside the established true-dual-port template prevents Quartus from
// implementing the second read path as a 131072-register mirror.
jtframe_dual_ram16 #(.AW(13)) u_vram (
    .clk0  ( clk                ),
    .data0 ( req_wdata          ),
    .addr0 ( cpu_vram_port_addr ),
    .we0   ( vram_we            ),
    .q0    ( cpu_vram_q         ),
    .clk1  ( clk                ),
    .data1 ( ss_vram_access ? ss_data[15:0] : 16'h0000 ),
    .addr1 ( ss_vram_access ? ss_addr[12:0] : mapped_scan_addr ),
    .we1   ( ss_vram_access ? {2{ss_write && ss_restore_enable}} : 2'b00 ),
    .q1    ( vram_port1_q       )
);

assign scan_data = vram_port1_q;

logic ss_vram_read_delay = 1'b0;
always_ff @(posedge clk) begin
    ss_ack <= 1'b0;
    ss_data_out <= 64'd0;

    if (ss_vram_selected && ss_query) begin
        ss_data_out <= {8'd5, 22'd0, 2'd1, 32'd8192};
        ss_ack <= 1'b1;
        ss_vram_read_delay <= 1'b0;
    end else if (ss_vram_access) begin
        if (ss_write) begin
            ss_ack <= 1'b1;
            ss_vram_read_delay <= 1'b0;
        end else begin
            if (ss_vram_read_delay) begin
                ss_data_out <= {48'd0, vram_port1_q};
                ss_ack <= 1'b1;
            end
            ss_vram_read_delay <= 1'b1;
        end
    end else begin
        ss_vram_read_delay <= 1'b0;
    end

    if (ss_regs_selected && ss_query) begin
        ss_data_out <= {8'd6, 22'd0, 2'd3, 32'd3};
        ss_ack <= 1'b1;
    end else if (ss_regs_access) begin
        if (ss_write) begin
            ss_ack <= 1'b1;
        end else begin
            case (ss_addr[1:0])
                2'd0: ss_data_out <= {34'd0, irq4, vram_pointer,
                                      scroll_select, scroll_flip};
                2'd1: ss_data_out <= {scroll_reg[3], scroll_reg[2],
                                      scroll_reg[1], scroll_reg[0]};
                default: ss_data_out <= {scroll_reg[7], scroll_reg[6],
                                         scroll_reg[5], scroll_reg[4]};
            endcase
            ss_ack <= 1'b1;
        end
    end
end

integer i;
always_ff @(posedge clk) begin
    done <= 1'b0;

    if (rst) begin
        state          <= ST_IDLE;
        req_rw         <= 1'b1;
        req_addr       <= 4'd0;
        req_wdata      <= 16'd0;
        req_be         <= 2'b00;
        req_status_bit <= 1'b0;
        req_seen       <= 1'b0;
        cpu_vram_addr  <= 13'd0;
        rdata          <= 16'hffff;
        vram_pointer   <= 13'd0;
        scroll_select  <= 8'd0;
        scroll_flip    <= 8'd0;
        irq4           <= 1'b0;
        for (i = 0; i < 8; i = i + 1)
            scroll_reg[i] <= 16'd0;
    end else begin
        // The clear writes below deliberately have priority if a new VINT
        // arrives in the same clock, matching the audited Dogyuun latch.
        if (vint_set)
            irq4 <= 1'b1;

        if (!req)
            req_seen <= 1'b0;

        if (flush) begin
            state          <= ST_IDLE;
            req_rw         <= 1'b1;
            req_addr       <= 4'd0;
            req_wdata      <= 16'd0;
            req_be         <= 2'b00;
            req_status_bit <= 1'b0;
            req_seen       <= req;
            cpu_vram_addr  <= 13'd0;
            rdata          <= 16'hffff;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (accept) begin
                        req_seen       <= 1'b1;
                        req_rw         <= rw;
                        req_addr       <= addr;
                        req_wdata      <= wdata;
                        req_be         <= be;
                        req_status_bit <= status_bit;
                        state          <= ST_DISPATCH;
                    end
                end

                ST_DISPATCH: begin
                    if (req_rw) begin
                        case (op)
                            4'h4: begin
                                cpu_vram_addr <=
                                    mirror_vram_addr(vram_pointer);
                                state <= ST_READ_WAIT0;
                            end

                            4'hc: begin
                                rdata <= {15'd0, req_status_bit};
                                done  <= 1'b1;
                                state <= ST_IDLE;
                            end

                            default: begin
                                rdata <= 16'hffff;
                                done  <= 1'b1;
                                state <= ST_IDLE;
                            end
                        endcase
                    end else begin
                        case (op)
                            4'h0: begin
                                vram_pointer <= pointer_merged[12:0];
                            end

                            4'h4: begin
                                vram_pointer <= vram_pointer + 13'd1;
                            end

                            4'h8: begin
                                // MAME accepts only the low-byte selector.
                                if (req_be[0])
                                    scroll_select <= req_wdata[7:0] & 8'h8f;
                            end

                            4'hc: begin
                                if (selected_scroll) begin
                                    scroll_reg[scroll_select[2:0]] <=
                                        scroll_merged;
                                    scroll_flip[scroll_select[2:0]] <=
                                        scroll_select[7];
                                end

                                if (selected_vint_clear)
                                    irq4 <= 1'b0;
                            end

                            default: begin
                            end
                        endcase

                        rdata <= 16'hffff;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_READ_WAIT0: begin
                    state <= ST_READ_WAIT1;
                end

                ST_READ_WAIT1: begin
                    rdata        <= cpu_vram_q;
                    vram_pointer <= vram_pointer + 13'd1;
                    done         <= 1'b1;
                    state        <= ST_IDLE;
                end

                default: begin
                    rdata <= 16'hffff;
                    state <= ST_IDLE;
                end
            endcase

            if (ss_regs_access && ss_write && ss_restore_enable) begin
                case (ss_addr[1:0])
                    2'd0: begin
                        irq4          <= ss_data[29];
                        vram_pointer  <= ss_data[28:16];
                        scroll_select <= ss_data[15:8];
                        scroll_flip   <= ss_data[7:0];
                    end
                    2'd1: begin
                        scroll_reg[0] <= ss_data[15:0];
                        scroll_reg[1] <= ss_data[31:16];
                        scroll_reg[2] <= ss_data[47:32];
                        scroll_reg[3] <= ss_data[63:48];
                    end
                    default: begin
                        scroll_reg[4] <= ss_data[15:0];
                        scroll_reg[5] <= ss_data[31:16];
                        scroll_reg[6] <= ss_data[47:32];
                        scroll_reg[7] <= ss_data[63:48];
                    end
                endcase
            end
        end
    end
end

endmodule
