// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_rom_loader (
    input  logic        clk,
    input  logic        rst,
    input  logic        ioctl_download,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [ 7:0] ioctl_data,
    input  logic [15:0] ioctl_index,
    output logic        download_done,
    output logic        rom_valid,
    output logic [ 1:0] rom_set_id,
    output logic [23:0] rom_size,
    output logic [63:0] rom_crc64
);

localparam [23:0] EXPECTED_SIZE = 24'h8C8000;
localparam [63:0] KBASH_CRC64  = 64'h6BDA_A6A6_9EA9_BBD9;
localparam [63:0] KBASHK_CRC64 = 64'hDCB2_F479_2AFD_831A;
localparam [63:0] KBASHP_CRC64 = 64'hD779_10A2_8F7A_98A1;

logic downloading_d;
logic [23:0] byte_count;
logic [63:0] crc_work;

function automatic [63:0] crc64_ecma_byte(input [63:0] crc_in, input [7:0] data);
    integer i;
    reg [63:0] crc;
    begin
        crc = crc_in ^ {data, 56'd0};
        for (i = 0; i < 8; i = i + 1) begin
            if (crc[63])
                crc = {crc[62:0], 1'b0} ^ 64'h42F0_E1EB_A9EA_3693;
            else
                crc = {crc[62:0], 1'b0};
        end
        crc64_ecma_byte = crc;
    end
endfunction

wire main_downloading = ioctl_download && ioctl_index == 16'd0;
wire main_stream_wr = main_downloading && ioctl_wr;
wire [63:0] crc_next = crc64_ecma_byte(
    downloading_d ? crc_work : 64'd0,
    ioctl_data
);

always_ff @(posedge clk) begin
    if (rst) begin
        downloading_d <= 1'b0;
        byte_count <= 24'd0;
        crc_work <= 64'd0;
        download_done <= 1'b0;
        rom_valid <= 1'b0;
        rom_set_id <= 2'd0;
        rom_size <= 24'd0;
        rom_crc64 <= 64'd0;
    end else begin
        // Frame the validator only with index-zero ROM downloads. Later MRA
        // core-mod/DIP transfers are independent IOCTL frames and must not
        // clear a ROM identity that has already passed.
        downloading_d <= main_downloading;
        download_done <= 1'b0;

        if (!downloading_d && main_downloading) begin
            byte_count <= 24'd0;
            crc_work <= 64'd0;
            rom_valid <= 1'b0;
            rom_set_id <= 2'd0;
        end

        if (main_stream_wr) begin
            crc_work <= crc_next;
            byte_count <= (downloading_d ? byte_count : 24'd0) + 24'd1;
        end

        if (downloading_d && !main_downloading) begin
            download_done <= 1'b1;
            rom_size <= byte_count;
            rom_crc64 <= crc_work;
            rom_valid <= byte_count == EXPECTED_SIZE &&
                (crc_work == KBASH_CRC64 ||
                 crc_work == KBASHK_CRC64 ||
                 crc_work == KBASHP_CRC64);
            if (crc_work == KBASH_CRC64)
                rom_set_id <= 2'd1;
            else if (crc_work == KBASHK_CRC64)
                rom_set_id <= 2'd2;
            else if (crc_work == KBASHP_CRC64)
                rom_set_id <= 2'd3;
            else
                rom_set_id <= 2'd0;
        end
    end
end

endmodule
