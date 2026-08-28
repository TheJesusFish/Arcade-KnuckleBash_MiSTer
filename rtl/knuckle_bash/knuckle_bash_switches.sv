// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_switches (
    input  logic        clk,
    input  logic        rst,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [ 7:0] ioctl_data,
    input  logic [15:0] ioctl_index,
    input  logic        rom_valid,
    input  logic [ 1:0] rom_set_id,
    output logic [31:0] dipsw
);

localparam [7:0] IDX_DIPSW = 8'd254;
localparam [1:0] SET_PARENT = 2'd1;
localparam [1:0] SET_KOREAN = 2'd2;
localparam [1:0] SET_PROTO  = 2'd3;

logic [7:0] dsw0;
logic [7:0] dsw1;
logic [7:0] dsw2;
logic [7:0] dsw3;
logic [1:0] applied_set_id;

function automatic [7:0] default_jmpr(input logic [1:0] set_id);
    begin
        unique case (set_id)
        SET_PARENT: default_jmpr = 8'h20;
        SET_KOREAN: default_jmpr = 8'h00;
        SET_PROTO:  default_jmpr = 8'h20;
        default:    default_jmpr = 8'h20;
        endcase
    end
endfunction

always_ff @(posedge clk) begin
    if (rst) begin
        dsw0 <= 8'h00;
        dsw1 <= 8'h00;
        dsw2 <= 8'h20;
        dsw3 <= 8'h00;
        applied_set_id <= 2'd0;
    end else begin
        if (rom_valid && rom_set_id != applied_set_id) begin
            dsw0 <= 8'h00;
            dsw1 <= 8'h00;
            dsw2 <= default_jmpr(rom_set_id);
            dsw3 <= 8'h00;
            applied_set_id <= rom_set_id;
        end

        if (ioctl_wr &&
            ioctl_index[7:0] == IDX_DIPSW &&
            ioctl_addr[24:2] == 23'd0) begin
            unique case (ioctl_addr[1:0])
            2'd0: dsw0 <= ioctl_data;
            2'd1: dsw1 <= ioctl_data;
            2'd2: dsw2 <= ioctl_data;
            2'd3: dsw3 <= ioctl_data;
            endcase
        end
    end
end

assign dipsw = {dsw3, dsw2, dsw1, dsw0};

endmodule
