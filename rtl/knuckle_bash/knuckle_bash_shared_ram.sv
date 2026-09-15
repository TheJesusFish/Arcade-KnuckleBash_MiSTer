// SPDX-License-Identifier: GPL-2.0-or-later

module knuckle_bash_shared_ram (
    input  logic        clk,

    input  logic [10:0] main_addr,
    input  logic [ 7:0] main_din,
    input  logic        main_we,
    output logic [ 7:0] main_dout,

    input  logic [10:0] sound_addr,
    input  logic [ 7:0] sound_din,
    input  logic        sound_we,
    output logic [ 7:0] sound_dout,

    input  logic        ss_restore_enable,
    input  logic [63:0] ss_data,
    input  logic [31:0] ss_addr,
    input  logic [ 7:0] ss_select,
    input  logic        ss_write,
    input  logic        ss_read,
    input  logic        ss_query,
    output logic [63:0] ss_data_out,
    output logic        ss_ack
);

(* ramstyle = "no_rw_check" *) logic [7:0] ram [0:2047];

always_ff @(posedge clk) begin
    main_dout <= ram[main_addr];
    if (main_we)
        ram[main_addr] <= main_din;
end

wire ss_selected = ss_select == 8'd3;
wire ss_access = ss_selected && !ss_query && (ss_read || ss_write);
wire [10:0] port1_addr = ss_access ? ss_addr[10:0] : sound_addr;
wire [7:0] port1_data = ss_access ? ss_data[7:0] : sound_din;
wire port1_we = ss_access ? (ss_write && ss_restore_enable) : sound_we;

always_ff @(posedge clk) begin
    sound_dout <= ram[port1_addr];
    if (port1_we)
        ram[port1_addr] <= port1_data;
end

logic ss_read_delay = 1'b0;
always_ff @(posedge clk) begin
    ss_ack <= 1'b0;
    if (ss_selected && ss_query) begin
        ss_data_out <= {8'd3, 22'd0, 2'd0, 32'd2048};
        ss_ack <= 1'b1;
        ss_read_delay <= 1'b0;
    end else if (ss_access) begin
        if (ss_write) begin
            ss_ack <= 1'b1;
            ss_read_delay <= 1'b0;
        end else begin
            if (ss_read_delay) begin
                ss_data_out <= {56'd0, sound_dout};
                ss_ack <= 1'b1;
            end
            ss_read_delay <= 1'b1;
        end
    end else begin
        ss_read_delay <= 1'b0;
    end
end

endmodule
