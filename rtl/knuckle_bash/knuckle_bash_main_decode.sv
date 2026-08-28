// SPDX-License-Identifier: GPL-2.0-or-later
//
// Exact TP-023 MC68000 board-bus decode. `addr` is a byte address; because
// fx68k exposes A[23:1], integration normally supplies {eab, 1'b0}. The
// decoder normalizes bit zero so directed tests may also use the physical odd
// address associated with an LDS-only byte access.
module knuckle_bash_main_decode (
    input  logic [23:0] addr,
    input  logic        bus_active,
    input  logic        rw,
    input  logic        uds_n,
    input  logic        lds_n,

    output logic        read_cycle,
    output logic        write_cycle,
    output logic        upper_lane,
    output logic        lower_lane,

    output logic        rom_read_cs,
    output logic        wram_cs,
    output logic        shared_cs,
    output logic        p1_read_cs,
    output logic        p2_read_cs,
    output logic        sys_read_cs,
    output logic        coin_write_cs,
    output logic        gp_cs,
    output logic        palette_cs,
    output logic        vcount_read_cs,

    output logic [17:0] rom_addr,
    output logic [12:0] wram_addr,
    output logic [10:0] shared_addr,
    output logic [ 3:0] gp_addr,
    output logic [10:0] palette_addr,

    // Bit order is documented so simulation and integration diagnostics can
    // identify the selected owner without reconstructing the decode.
    // {vcount, palette, GP, coin, system, P2, P1, shared, work, ROM}
    output logic [ 9:0] select_vector,
    output logic        mapped_cs,
    output logic        unmapped_cs,
    output logic        select_onehot,
    output logic        select_onehot0
);

logic [23:0] word_addr;
logic        cycle_active;
logic [ 3:0] select_count;
integer      select_index;

always_comb begin
    word_addr = {addr[23:1], 1'b0};

    cycle_active = bus_active && (!uds_n || !lds_n);
    read_cycle   = cycle_active && rw;
    write_cycle  = cycle_active && !rw;
    upper_lane   = cycle_active && !uds_n;
    lower_lane   = cycle_active && !lds_n;

    // Direction and byte-lane restrictions are part of the decode. A cycle
    // using the wrong direction or lane is deliberately reported unmapped.
    rom_read_cs = read_cycle && (word_addr < 24'h080000);

    wram_cs = cycle_active &&
              (word_addr >= 24'h100000) &&
              (word_addr <  24'h104000);

    shared_cs = cycle_active && lower_lane &&
                (word_addr >= 24'h200000) &&
                (word_addr <  24'h201000);

    p1_read_cs  = read_cycle && (word_addr == 24'h208010);
    p2_read_cs  = read_cycle && (word_addr == 24'h208014);
    sys_read_cs = read_cycle && (word_addr == 24'h208018);

    coin_write_cs = write_cycle && lower_lane &&
                    (word_addr == 24'h20801c);

    gp_cs = cycle_active &&
            (word_addr >= 24'h300000) &&
            (word_addr <  24'h30000e);

    palette_cs = cycle_active &&
                 (word_addr >= 24'h400000) &&
                 (word_addr <  24'h401000);

    vcount_read_cs = read_cycle && (word_addr == 24'h700000);

    rom_addr     = word_addr[18:1];
    wram_addr    = word_addr[13:1];
    shared_addr  = word_addr[11:1];
    gp_addr      = word_addr[3:0];
    palette_addr = word_addr[11:1];

    select_vector = {
        vcount_read_cs,
        palette_cs,
        gp_cs,
        coin_write_cs,
        sys_read_cs,
        p2_read_cs,
        p1_read_cs,
        shared_cs,
        wram_cs,
        rom_read_cs
    };

    select_count = 4'd0;
    for (select_index = 0; select_index < 10; select_index = select_index + 1)
        select_count = select_count + select_vector[select_index];

    mapped_cs      = |select_vector;
    unmapped_cs    = cycle_active && !mapped_cs;
    select_onehot  = select_count == 4'd1;
    select_onehot0 = select_count <= 4'd1;
end

endmodule
