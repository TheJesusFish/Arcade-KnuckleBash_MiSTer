// Adapted from MiSTer-devel/Arcade-TaitoF2_MiSTer and the local Batsugun core.
interface ssbus_if();
    logic [63:0] data;
    logic [31:0] addr;
    logic [7:0] select;
    logic write;
    logic read;
    logic query;
    logic [63:0] data_out;
    logic ack;

    function logic access(int idx);
        return (select == idx[7:0]) & ~query & (read | write);
    endfunction

    task setup(int idx, input [31:0] count, int width);
        ack <= 0;
        if (select == idx[7:0] && query) begin
            data_out <= {idx[7:0], 22'b0, width[1:0], count};
            ack <= 1;
        end
    endtask

    task read_response(int idx, input [63:0] dout);
        if (select == idx[7:0]) begin
            data_out <= dout;
            ack <= 1;
        end
    endtask

    task write_ack(int idx);
        if (select == idx[7:0]) ack <= 1;
    endtask

    modport master(
        output data, addr, select, write, read, query,
        input data_out, ack
    );

    modport slave(
        input data, addr, select, write, read, query,
        output data_out, ack,
        import access, setup, read_response, write_ack
    );
endinterface

module ssbus_mux #(parameter COUNT = 4)(
    input clk,
    ssbus_if.master masters[COUNT],
    ssbus_if.slave slave
);

logic [63:0] data_out[COUNT];
logic ack[COUNT];

genvar gi;
generate
for (gi = 0; gi < COUNT; gi = gi + 1) begin: gen_loop
    always_comb begin
        ack[gi] = masters[gi].ack;
        data_out[gi] = masters[gi].data_out;
        masters[gi].data = slave.data;
        masters[gi].addr = slave.addr;
        masters[gi].select = slave.select;
        masters[gi].write = slave.write;
        masters[gi].read = slave.read;
        masters[gi].query = slave.query;
    end
end
endgenerate

int i;
always_ff @(posedge clk) begin
    slave.data_out <= 64'd0;
    slave.ack <= 1'b0;
    for (i = 0; i < COUNT; i = i + 1) begin
        if (ack[i]) begin
            slave.ack <= 1'b1;
            slave.data_out <= data_out[i];
        end
    end
end

endmodule

module save_state_data(
    input clk,
    input reset,
    ddr_if.to_host ddr,
    input read_start,
    input write_start,
    input [1:0] index,
    output busy,
    ssbus_if.master ssbus
);

localparam bit [31:0] SS_DDR_BASE = 32'h3E00_0000;

memory_stream #(.COUNT(7)) u_memory_stream (
    .clk(clk),
    .reset(reset),
    .ddr,
    .read_req(ssbus.read),
    .read_data(ssbus.data_out),
    .data_ack(ssbus.ack),
    .write_req(ssbus.write),
    .write_data(ssbus.data),
    .start_addr(SS_DDR_BASE + (index * 32'h00400000)),
    .length(32'h00400000),
    .read_start(read_start),
    .write_start(write_start),
    .busy(busy),
    .chunk_select(ssbus.select),
    .chunk_address(ssbus.addr),
    .query_req(ssbus.query)
);

endmodule
