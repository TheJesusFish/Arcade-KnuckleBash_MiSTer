// SPDX-License-Identifier: GPL-2.0-or-later
//
// TP-023 sound subsystem. The ROM-based encrypted V25 owns the low 2 KiB
// shared-RAM window and reaches YM2151/OKI devices at the MAME-audited map.

module knuckle_bash_sound (
    input  logic               clk,
    input  logic               reset,
    input  logic               v25_cen,
    input  logic               opm_cen,
    input  logic               oki_cen,
    input  logic               v25_enable,
    input  logic               v25_owner_reset_n,
    input  logic [ 7:0]        dip_a,
    input  logic [ 7:0]        dip_b,
    input  logic [ 7:0]        region,
    input  logic               fm_enable,
    input  logic               fx_enable,
    input  logic [ 1:0]        fx_level,
    input  logic               state_hold,

    input  logic               ss_restore_enable,
    input  logic               ss_restore_commit,
    input  logic [63:0]        ss_data,
    input  logic [31:0]        ss_addr,
    input  logic [ 7:0]        ss_select,
    input  logic               ss_write,
    input  logic               ss_read,
    input  logic               ss_query,
    output logic [63:0]        ss_data_out,
    output logic               ss_ack,

    output logic [10:0]        shared_addr,
    output logic [ 7:0]        shared_dout,
    output logic               shared_we,
    input  logic [ 7:0]        shared_din,

    output logic [14:0]        v25_rom_addr,
    input  logic [ 7:0]        v25_rom_data,
    output logic [17:0]        oki_rom_addr,
    input  logic [ 7:0]        oki_rom_data,
    input  logic               oki_rom_ok,

    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,
    output logic               sample,

    output logic               debug_fault,
    output logic               debug_halted,
    output logic [19:0]        debug_pc,
    output logic               state_idle,
    output logic               state_held,
    output logic               debug_ym_write,
    output logic               debug_ym_a0,
    output logic [ 7:0]        debug_ym_data,
    output logic               debug_oki_write,
    output logic [ 7:0]        debug_oki_data
);

localparam [19:0] YM_ADDR    = 20'h04000;
localparam [19:0] YM_DATA    = 20'h04001;
localparam [19:0] OKI_DATA   = 20'h04002;

wire sound_chip_reset = reset || ss_restore_commit;

reg [5:0] opm_reset_count = 6'd0;
always_ff @(posedge clk or posedge sound_chip_reset) begin
    if (sound_chip_reset)
        opm_reset_count <= 6'd0;
    else if (!opm_reset_count[5] && opm_cen)
        opm_reset_count <= opm_reset_count + 6'd1;
end
wire opm_reset = sound_chip_reset || !opm_reset_count[5];
wire opm_ready = !opm_reset;

reg [1:0]  oki_reset_state = 2'd0;
reg [13:0] oki_reset_timer = 14'd0;
reg        oki_reset = 1'b1;
reg        oki_ready = 1'b0;
always_ff @(posedge clk or posedge sound_chip_reset) begin
    if (sound_chip_reset) begin
        oki_reset_state <= 2'd0;
        oki_reset_timer <= 14'd0;
        oki_reset <= 1'b1;
        oki_ready <= 1'b0;
    end else begin
        unique case (oki_reset_state)
        2'd0: begin
            oki_reset <= 1'b0;
            if (&oki_reset_timer) begin
                oki_reset_state <= 2'd1;
                oki_reset_timer <= 14'd0;
                oki_reset <= 1'b1;
            end else begin
                oki_reset_timer <= oki_reset_timer + 14'd1;
            end
        end
        2'd1: begin
            oki_reset <= 1'b1;
            if (oki_reset_timer == 14'd15) begin
                oki_reset_state <= 2'd2;
                oki_reset_timer <= 14'd0;
                oki_reset <= 1'b0;
                oki_ready <= 1'b1;
            end else begin
                oki_reset_timer <= oki_reset_timer + 14'd1;
            end
        end
        default: begin
            oki_reset <= 1'b0;
            oki_ready <= 1'b1;
        end
        endcase
    end
end

wire sound_ready = opm_ready && oki_ready && oki_rom_ok;
reg v25_started = 1'b0;
always_ff @(posedge clk or posedge reset) begin
    if (reset)
        v25_started <= 1'b0;
    else if (!v25_enable || !v25_owner_reset_n)
        v25_started <= 1'b0;
    else if (sound_ready)
        v25_started <= 1'b1;
end

wire v25_reset_async = reset || !v25_enable || !v25_owner_reset_n ||
                       !v25_started;
reg [1:0] v25_reset_pipe = 2'b11;
always_ff @(posedge clk or posedge v25_reset_async) begin
    if (v25_reset_async)
        v25_reset_pipe <= 2'b11;
    else
        v25_reset_pipe <= {v25_reset_pipe[0], 1'b0};
end
wire v25_reset_n = !v25_reset_pipe[1];

wire [19:0] v25_bus_addr;
wire [ 7:0] v25_bus_dout;
logic [7:0] v25_bus_din;
wire        v25_bus_doe;
wire        v25_bus_r_w;
wire        v25_bus_mreq_n;
wire        v25_bus_mstb_n;
wire        v25_bus_iostb_n;
wire        v25_state_idle;

wire v25_hold_boundary = state_hold && v25_state_idle;

knuckle_bash_v25_cpu #(
    .SS_IDX(8'd9)
) u_v25 (
    .clk               ( clk                         ),
    .reset             ( !v25_reset_n                ),
    .reset_n           ( v25_reset_n                 ),
    .clock_enable      ( v25_cen && !v25_hold_boundary ),
    .port0_in          ( ~dip_b                      ),
    .port1_in          ( ~region                     ),
    .portt_in          ( ~dip_a                      ),
    .bus_addr          ( v25_bus_addr                ),
    .bus_dout          ( v25_bus_dout                ),
    .bus_din           ( v25_bus_din                 ),
    .bus_doe           ( v25_bus_doe                 ),
    .bus_r_w           ( v25_bus_r_w                 ),
    .bus_mreq_n        ( v25_bus_mreq_n              ),
    .bus_mstb_n        ( v25_bus_mstb_n              ),
    .bus_iostb_n       ( v25_bus_iostb_n             ),
    .halted            ( debug_halted                ),
    .fault             ( debug_fault                 ),
    .debug_pc          ( debug_pc                    ),
    .state_idle        ( v25_state_idle              ),
    .ss_restore_enable ( ss_restore_enable           ),
    .ss_restore_commit ( ss_restore_commit           ),
    .ss_data           ( ss_data                     ),
    .ss_addr           ( ss_addr                     ),
    .ss_select         ( ss_select                   ),
    .ss_write          ( ss_write                    ),
    .ss_read           ( ss_read                     ),
    .ss_query          ( ss_query                    ),
    .ss_data_out       ( ss_data_out                 ),
    .ss_ack            ( ss_ack                      )
);

wire v25_mem_active = !v25_bus_mreq_n && !v25_bus_mstb_n;
wire v25_write_active = v25_mem_active && !v25_bus_r_w && v25_bus_doe;
reg  v25_write_active_d = 1'b0;
wire v25_write_start = v25_write_active && !v25_write_active_d;
wire v25_shared_cs = v25_bus_addr[19:11] == 9'd0;
// MAME maps 80000-87fff with mirror mask 78000. The mask mirrors the same
// 32 KiB image across the complete A19-high half of the V25 address space;
// it is not a second ROM window beginning at 78000.
wire v25_rom_cs = v25_bus_addr[19];

assign shared_addr = v25_bus_addr[10:0];
assign shared_dout = v25_bus_dout;
assign shared_we = v25_write_start && v25_shared_cs;
assign v25_rom_addr = v25_bus_addr[14:0];

wire [7:0] opm_dout;
wire signed [15:0] opm_left;
wire signed [15:0] opm_right;
wire opm_sample;
reg        opm_cs_n = 1'b1;
reg        opm_wr_n = 1'b1;
reg        opm_a0 = 1'b0;
reg [7:0]  opm_host_data = 8'h00;
reg        opm_write_pending = 1'b0;
wire       opm_read_active = v25_mem_active && v25_bus_r_w &&
                             v25_bus_addr == YM_DATA;
wire       opm_bus_cs_n = opm_read_active ? 1'b0 : opm_cs_n;
wire       opm_bus_wr_n = opm_read_active ? 1'b1 : opm_wr_n;
wire       opm_bus_a0 = opm_read_active ? 1'b1 : opm_a0;

wire [7:0] oki_dout;
wire signed [13:0] oki_sound;
wire oki_sample;
reg        oki_wr_n = 1'b1;
reg [7:0]  oki_host_data = 8'h00;
reg        oki_write_pending = 1'b0;
logic [1:0] fx_level_safe;

// Named-port historical benches that predate the level input leave it
// unconnected. Preserve their exact default/MAME behavior while production
// always supplies a known two-bit value.
always_comb begin
    case (fx_level)
        2'd0:    fx_level_safe = 2'd0;
        2'd1:    fx_level_safe = 2'd1;
        2'd3:    fx_level_safe = 2'd3;
        default: fx_level_safe = 2'd2;
    endcase
end

always_comb begin
    v25_bus_din = 8'h00;
    if (v25_mem_active && v25_bus_r_w) begin
        if (v25_shared_cs)
            v25_bus_din = shared_din;
        else if (v25_bus_addr == YM_DATA)
            v25_bus_din = opm_dout;
        else if (v25_bus_addr == OKI_DATA)
            v25_bus_din = oki_dout;
        else if (v25_rom_cs)
            v25_bus_din = v25_rom_data;
    end
end

always_ff @(posedge clk) begin
    if (!v25_reset_n || sound_chip_reset) begin
        v25_write_active_d <= 1'b0;
        opm_cs_n <= 1'b1;
        opm_wr_n <= 1'b1;
        opm_a0 <= 1'b0;
        opm_host_data <= 8'h00;
        opm_write_pending <= 1'b0;
        oki_wr_n <= 1'b1;
        oki_host_data <= 8'h00;
        oki_write_pending <= 1'b0;
        debug_ym_write <= 1'b0;
        debug_ym_a0 <= 1'b0;
        debug_ym_data <= 8'h00;
        debug_oki_write <= 1'b0;
        debug_oki_data <= 8'h00;
    end else begin
        v25_write_active_d <= v25_write_active;
        debug_ym_write <= 1'b0;
        debug_oki_write <= 1'b0;

        if (opm_write_pending) begin
            opm_cs_n <= 1'b0;
            opm_wr_n <= 1'b0;
            if (opm_cen) begin
                opm_cs_n <= 1'b1;
                opm_wr_n <= 1'b1;
                opm_write_pending <= 1'b0;
            end
        end else begin
            opm_cs_n <= 1'b1;
            opm_wr_n <= 1'b1;
        end

        if (oki_write_pending) begin
            oki_wr_n <= 1'b0;
            if (oki_cen) begin
                oki_wr_n <= 1'b1;
                oki_write_pending <= 1'b0;
            end
        end else begin
            oki_wr_n <= 1'b1;
        end

        if (v25_write_start && !v25_shared_cs) begin
            if (v25_bus_addr == YM_ADDR || v25_bus_addr == YM_DATA) begin
                opm_cs_n <= 1'b0;
                opm_wr_n <= 1'b0;
                opm_a0 <= v25_bus_addr[0];
                opm_host_data <= v25_bus_dout;
                opm_write_pending <= 1'b1;
                debug_ym_write <= 1'b1;
                debug_ym_a0 <= v25_bus_addr[0];
                debug_ym_data <= v25_bus_dout;
            end else if (v25_bus_addr == OKI_DATA) begin
                oki_wr_n <= 1'b0;
                oki_host_data <= v25_bus_dout;
                oki_write_pending <= 1'b1;
                debug_oki_write <= 1'b1;
                debug_oki_data <= v25_bus_dout;
            end
        end
    end
end

knuckle_bash_opm u_ym2151 (
    .rst    ( opm_reset     ),
    .clk    ( clk           ),
    .cen    ( opm_cen       ),
    .cs_n   ( opm_bus_cs_n  ),
    .wr_n   ( opm_bus_wr_n  ),
    .a0     ( opm_bus_a0    ),
    .din    ( opm_host_data ),
    .dout   ( opm_dout      ),
    .sample ( opm_sample    ),
    .left   ( opm_left      ),
    .right  ( opm_right     )
);

knuckle_bash_jt6295 #(.INTERPOL(0)) u_oki6295 (
    .rst      ( oki_reset     ),
    .clk      ( clk           ),
    .cen      ( oki_cen       ),
    .ss       ( 1'b1          ),
    .wrn      ( oki_wr_n      ),
    .din      ( oki_host_data ),
    .dout     ( oki_dout      ),
    .rom_addr ( oki_rom_addr  ),
    .rom_data ( oki_rom_data  ),
    .rom_ok   ( oki_rom_ok    ),
    .sound    ( oki_sound     ),
    .sample   ( oki_sample    )
);

knuckle_bash_sound_mixer u_mixer (
    .opm_l     ( opm_left  ),
    .opm_r     ( opm_right ),
    .oki_mono  ( oki_sound ),
    .fm_enable ( fm_enable ),
    .fx_enable ( fx_enable && oki_ready ),
    .fx_level  ( fx_level_safe ),
    .audio_l   ( audio_l   ),
    .audio_r   ( audio_r   )
);

assign sample = opm_sample;
assign state_idle = v25_state_idle &&
                    !v25_write_active &&
                    !opm_write_pending &&
                    !oki_write_pending &&
                    opm_cs_n &&
                    opm_wr_n &&
                    oki_wr_n;
assign state_held = state_hold && state_idle;

endmodule
