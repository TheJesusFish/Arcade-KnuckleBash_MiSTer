// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 MC68000 board-bus fabric. All CPU-visible side effects are qualified
// by the one-shot ack_now pulse. ROM and GP9001 requests retain a private copy
// of their payload until the corresponding completion is observed.
module knuckle_bash_main_bus (
    input  logic        clk,
    input  logic        rst,
    input  logic        txn_flush,

    input  logic        hs_reset, hs_download, hs_upload, hs_wr, hs_rd, hs_ss_active,
    input  logic [1:0]  hs_set_id,
    input  logic [26:0] hs_addr,
    input  logic [7:0]  hs_data,
    input  logic [15:0] hs_index,
    output logic [7:0]  hs_din,
    output logic        hs_wait, hs_dirty, hs_active, hs_hold_request,
    input  logic        hs_hold_ack,

    input  logic        bus_active,
    input  logic        rw,
    input  logic        uds_n,
    input  logic        lds_n,
    input  logic [23:0] addr,
    input  logic [15:0] cpu_dout,
    input  logic        dtack_n,
    output logic [15:0] cpu_din,
    output logic        ack_now,
    output logic        bus_busy,

    input  logic [ 7:0] player1,
    input  logic [ 7:0] player2,
    input  logic [ 7:0] system,
    input  logic [15:0] vcount_data,

    output logic        rom_req,
    output logic [17:0] rom_addr,
    input  logic        rom_ok,
    input  logic [15:0] rom_data,

    output logic        gp_req,
    output logic        gp_rw,
    output logic [ 3:0] gp_addr,
    output logic [15:0] gp_wdata,
    output logic [ 1:0] gp_be,
    input  logic        gp_accept,
    input  logic        gp_done,
    input  logic [15:0] gp_rdata,

    input  logic [10:0] palette_scan_addr,
    output logic [15:0] palette_scan_data,

    output logic [10:0] shared_addr,
    output logic [ 7:0] shared_din,
    output logic        shared_we,
    input  logic [ 7:0] shared_dout,

    output logic [ 7:0] coin_control,

    output logic        mapped_cycle,
    output logic        unmapped_cycle,
    output logic [ 9:0] select_vector,
    output logic [31:0] ack_count,
    output logic [31:0] rom_ack_count,
    output logic [31:0] wram_write_count,
    output logic [31:0] shared_write_count,
    output logic [31:0] gp_ack_count,
    output logic [31:0] palette_write_count,
    output logic [31:0] coin_write_count,
    output logic [31:0] unmapped_ack_count,
    output logic [23:0] last_ack_addr,
    output logic [15:0] last_ack_wdata,
    output logic        last_ack_rw,
    output logic [ 1:0] last_ack_be
);

logic        read_cycle;
logic        write_cycle;
logic        upper_lane;
logic        lower_lane;
logic        rom_read_cs;
logic        wram_cs;
logic        shared_cs;
logic        p1_read_cs;
logic        p2_read_cs;
logic        sys_read_cs;
logic        coin_write_cs;
logic        gp_cs;
logic        palette_cs;
logic        vcount_read_cs;
logic [17:0] decoded_rom_addr;
logic [12:0] decoded_wram_addr;
logic [10:0] decoded_shared_addr;
logic [ 3:0] decoded_gp_addr;
logic [10:0] decoded_palette_addr;
logic        mapped_cs;
logic        unmapped_cs;
logic        select_onehot;
logic        select_onehot0;

knuckle_bash_main_decode u_decode (
    .addr            (addr),
    .bus_active      (bus_active),
    .rw              (rw),
    .uds_n           (uds_n),
    .lds_n           (lds_n),
    .read_cycle      (read_cycle),
    .write_cycle     (write_cycle),
    .upper_lane      (upper_lane),
    .lower_lane      (lower_lane),
    .rom_read_cs     (rom_read_cs),
    .wram_cs         (wram_cs),
    .shared_cs       (shared_cs),
    .p1_read_cs      (p1_read_cs),
    .p2_read_cs      (p2_read_cs),
    .sys_read_cs     (sys_read_cs),
    .coin_write_cs   (coin_write_cs),
    .gp_cs           (gp_cs),
    .palette_cs      (palette_cs),
    .vcount_read_cs  (vcount_read_cs),
    .rom_addr        (decoded_rom_addr),
    .wram_addr       (decoded_wram_addr),
    .shared_addr     (decoded_shared_addr),
    .gp_addr         (decoded_gp_addr),
    .palette_addr    (decoded_palette_addr),
    .select_vector   (select_vector),
    .mapped_cs       (mapped_cs),
    .unmapped_cs     (unmapped_cs),
    .select_onehot   (select_onehot),
    .select_onehot0  (select_onehot0)
);

logic ack_seen;
logic txn_blocked;

logic        rom_pending;
logic        rom_complete;
logic [15:0] rom_latched_data;

logic        gp_pending;
logic        gp_accepted;
logic        gp_complete;
logic [15:0] gp_latched_data;

logic [15:0] wram [0:8191];
logic [15:0] wram_q;
logic [15:0] palette_q;
logic [ 1:0] wram_we;
logic [ 1:0] palette_we;
logic        commit_now;

wire hs_ram_owned;
wire [12:0] hs_ram_addr;
wire [1:0] hs_ram_we;
wire [15:0] hs_ram_data;
wire [12:0] work_address = hs_ram_owned ? hs_ram_addr : decoded_wram_addr;
wire [1:0] work_we = hs_ram_owned ? hs_ram_we : wram_we;
wire [15:0] work_data = hs_ram_owned ? hs_ram_data : cpu_dout;
knuckle_bash_highscore u_highscore (
    .clk(clk), .reset(hs_reset), .cpu_reset(rst), .set_id(hs_set_id),
    .config_download(hs_download && hs_index[5:0] == 6'd4),
    .config_wr(hs_wr), .config_addr(hs_addr), .config_data(hs_data),
    .nvram_download(hs_download && hs_index[5:0] == 6'd2),
    .nvram_upload(hs_upload && hs_index[5:0] == 6'd2),
    .nvram_wr(hs_wr), .nvram_rd(hs_rd), .nvram_addr(hs_addr), .nvram_data(hs_data),
    .nvram_q(hs_din), .nvram_wait(hs_wait), .ss_active(hs_ss_active),
    .normal_ram_addr(decoded_wram_addr), .normal_ram_we(wram_we), .normal_ram_data(cpu_dout),
    .hold_request(hs_hold_request), .hold_ack(hs_hold_ack), .ram_owned(hs_ram_owned),
    .ram_addr(hs_ram_addr), .ram_we(hs_ram_we), .ram_data(hs_ram_data), .ram_q(wram_q),
    .dirty(hs_dirty), .active(hs_active), .config_valid()
);

assign mapped_cycle   = mapped_cs;
assign unmapped_cycle = unmapped_cs;

// Keep this definition literal: it is the only edge-to-pulse conversion for
// an acknowledged 68000 transaction. bus_active must include a valid DSn.
assign ack_now = bus_active && !dtack_n && !ack_seen;

// A flush kills the current delayed transaction and blocks its still-active
// bus phase until bus_active drops. This prevents a stale response from
// reopening the request while the CPU is being held for restore/reset.
assign bus_busy =
    !txn_flush && !txn_blocked &&
    ((rom_read_cs && !rom_complete) ||
     (gp_cs       && !gp_complete));

assign rom_req = rom_pending && !rom_complete &&
                 bus_active && !txn_flush && !txn_blocked;

assign gp_req = gp_pending && !gp_accepted &&
                bus_active && !txn_flush && !txn_blocked;

assign shared_addr = decoded_shared_addr;
assign shared_din  = cpu_dout[7:0];

assign commit_now = ack_now && !rst && !txn_flush && !txn_blocked;

assign wram_we = {
    commit_now && wram_cs && write_cycle && upper_lane,
    commit_now && wram_cs && write_cycle && lower_lane
};

assign shared_we = commit_now && shared_cs &&
                   write_cycle && lower_lane;

assign palette_we = {
    commit_now && palette_cs && write_cycle && upper_lane,
    commit_now && palette_cs && write_cycle && lower_lane
};

// Registered-address/read-output templates keep the arrays compatible with a
// later refactor to explicit dual-port save-state memories.
always_ff @(posedge clk) begin
    wram_q <= wram[work_address];
    if (work_we[1])
        wram[work_address][15:8] <= work_data[15:8];
    if (work_we[0])
        wram[work_address][7:0] <= work_data[7:0];
end

// CPU byte writes/reads use port 0. The renderer owns the independent
// synchronous port 1 so palette snapshots cannot turn this RAM into a
// multi-address register array.
jtframe_dual_ram16 #(.AW(11)) u_palette (
    .clk0  ( clk                  ),
    .data0 ( cpu_dout             ),
    .addr0 ( decoded_palette_addr ),
    .we0   ( palette_we           ),
    .q0    ( palette_q            ),
    .clk1  ( clk                  ),
    .data1 ( 16'h0000             ),
    .addr1 ( palette_scan_addr    ),
    .we1   ( 2'b00                ),
    .q1    ( palette_scan_data    )
);

always_comb begin
    cpu_din = 16'hffff;

    if (rom_read_cs)
        cpu_din = rom_latched_data;
    else if (wram_cs)
        cpu_din = wram_q;
    else if (shared_cs)
        cpu_din = {8'hff, shared_dout};
    else if (p1_read_cs)
        cpu_din = {8'h00, player1};
    else if (p2_read_cs)
        cpu_din = {8'h00, player2};
    else if (sys_read_cs)
        cpu_din = {8'h00, system};
    else if (gp_cs)
        cpu_din = gp_latched_data;
    else if (palette_cs)
        cpu_din = palette_q;
    else if (vcount_read_cs)
        cpu_din = vcount_data;
end

always_ff @(posedge clk) begin
    if (rst) begin
        ack_seen       <= 1'b0;
        txn_blocked    <= 1'b0;

        rom_pending    <= 1'b0;
        rom_complete   <= 1'b0;
        rom_addr       <= 18'd0;
        rom_latched_data <= 16'hffff;

        gp_pending     <= 1'b0;
        gp_accepted    <= 1'b0;
        gp_complete    <= 1'b0;
        gp_rw          <= 1'b1;
        gp_addr        <= 4'd0;
        gp_wdata       <= 16'd0;
        gp_be          <= 2'b00;
        gp_latched_data <= 16'hffff;

        coin_control       <= 8'h00;
        ack_count          <= 32'd0;
        rom_ack_count      <= 32'd0;
        wram_write_count   <= 32'd0;
        shared_write_count <= 32'd0;
        gp_ack_count       <= 32'd0;
        palette_write_count <= 32'd0;
        coin_write_count   <= 32'd0;
        unmapped_ack_count <= 32'd0;
        last_ack_addr      <= 24'd0;
        last_ack_wdata     <= 16'd0;
        last_ack_rw        <= 1'b1;
        last_ack_be        <= 2'b00;
    end else begin
        if (txn_flush) begin
            // Suppress a held-low DTACK from becoming a post-flush side effect.
            ack_seen      <= bus_active && !dtack_n;
            txn_blocked   <= bus_active;
            rom_pending   <= 1'b0;
            rom_complete  <= 1'b0;
            gp_pending    <= 1'b0;
            gp_accepted   <= 1'b0;
            gp_complete   <= 1'b0;
        end else if (!bus_active) begin
            ack_seen      <= 1'b0;
            txn_blocked   <= 1'b0;
            rom_pending   <= 1'b0;
            rom_complete  <= 1'b0;
            gp_pending    <= 1'b0;
            gp_accepted   <= 1'b0;
            gp_complete   <= 1'b0;
        end else begin
            if (ack_now)
                ack_seen <= 1'b1;

            if (!txn_blocked) begin
                if (rom_read_cs && !rom_pending && !rom_complete) begin
                    rom_pending <= 1'b1;
                    rom_addr    <= decoded_rom_addr;
                end

                if (rom_req && rom_ok) begin
                    rom_complete     <= 1'b1;
                    rom_latched_data <= rom_data;
                end

                if (gp_cs && !gp_pending && !gp_complete) begin
                    gp_pending <= 1'b1;
                    gp_rw      <= rw;
                    gp_addr    <= decoded_gp_addr;
                    gp_wdata   <= cpu_dout;
                    gp_be      <= {upper_lane, lower_lane};
                end

                if (gp_req && gp_accept)
                    gp_accepted <= 1'b1;

                // Completion is legal only after an accepted request. A
                // gp_done pulse before acceptance is deliberately ignored.
                if ((gp_accepted || (gp_req && gp_accept)) && gp_done) begin
                    gp_complete     <= 1'b1;
                    gp_latched_data <= gp_rdata;
                end
            end
        end

        if (commit_now) begin
            ack_count      <= ack_count + 32'd1;
            last_ack_addr  <= addr;
            last_ack_wdata <= cpu_dout;
            last_ack_rw    <= rw;
            last_ack_be    <= {upper_lane, lower_lane};

            if (rom_read_cs)
                rom_ack_count <= rom_ack_count + 32'd1;
            if (|wram_we)
                wram_write_count <= wram_write_count + 32'd1;
            if (shared_we)
                shared_write_count <= shared_write_count + 32'd1;
            if (gp_cs)
                gp_ack_count <= gp_ack_count + 32'd1;
            if (|palette_we)
                palette_write_count <= palette_write_count + 32'd1;
            if (coin_write_cs) begin
                coin_control    <= cpu_dout[7:0];
                coin_write_count <= coin_write_count + 32'd1;
            end
            if (unmapped_cs)
                unmapped_ack_count <= unmapped_ack_count + 32'd1;
        end
    end
end

endmodule
