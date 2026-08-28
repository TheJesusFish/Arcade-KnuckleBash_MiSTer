// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_sound_roms (
    input  logic        clk,
    input  logic        ioctl_download,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [ 7:0] ioctl_data,
    input  logic [15:0] ioctl_index,

    input  logic [14:0] v25_rom_addr,
    output logic [ 7:0] v25_rom_data
);

localparam [26:0] V25_STREAM_BASE = 27'h080000;
localparam [26:0] V25_STREAM_END  = 27'h088000;

(* ramstyle = "no_rw_check" *) logic [7:0] v25_rom [0:32767];

wire stream_wr = ioctl_download && ioctl_wr && ioctl_index[7:0] == 8'd0;
wire v25_wr = stream_wr &&
              ioctl_addr >= V25_STREAM_BASE &&
              ioctl_addr < V25_STREAM_END;

wire [14:0] v25_write_addr = ioctl_addr[14:0] - V25_STREAM_BASE[14:0];

always_ff @(posedge clk) begin
    if (v25_wr)
        v25_rom[v25_write_addr] <= ioctl_data;
    v25_rom_data <= v25_rom[v25_rom_addr];
end

endmodule
