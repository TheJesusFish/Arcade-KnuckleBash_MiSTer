// Adapted from MiSTer-devel/Arcade-TaitoF2_MiSTer and the local Batsugun core.
// Kept Knuckle Bash-local so the protected framework remains untouched.
interface ddr_if;
    logic        acquire;
    logic [31:0] addr;
    logic [63:0] wdata;
    logic [63:0] rdata;
    logic        read;
    logic        write;
    logic  [7:0] burstcnt;
    logic  [7:0] byteenable;
    logic        busy;
    logic        rdata_ready;

    modport to_host(
        output addr, wdata, read, write, burstcnt, byteenable, acquire,
        input rdata, busy, rdata_ready
    );

    modport from_host(
        output rdata, busy, rdata_ready,
        input addr, wdata, read, write, burstcnt, byteenable, acquire
    );
endinterface

module ddr_mux(
    input clk,
    ddr_if.to_host x,
    ddr_if.from_host a,
    ddr_if.from_host b
);

reg a_active = 0;

always_comb begin
    a.rdata = x.rdata;
    b.rdata = x.rdata;

    if (a_active) begin
        // memory_stream uses byte addresses, while MiSTer's 29-bit DDRAM_ADDR
        // port selects 64-bit words.  Keep the framebuffer client in its
        // native word-address domain and translate only the save-state client.
        x.addr = a.addr >> 3;
        x.wdata = a.wdata;
        x.read = a.read;
        x.write = a.write;
        x.burstcnt = a.burstcnt;
        x.byteenable = a.byteenable;
        a.busy = x.busy;
        a.rdata_ready = x.rdata_ready;
        b.busy = 1'b1;
        b.rdata_ready = 1'b0;
    end else begin
        x.addr = b.addr;
        x.wdata = b.wdata;
        x.read = b.read;
        x.write = b.write;
        x.burstcnt = b.burstcnt;
        x.byteenable = b.byteenable;
        b.busy = x.busy;
        b.rdata_ready = x.rdata_ready;
        a.busy = 1'b1;
        a.rdata_ready = 1'b0;
    end
end

assign x.acquire = a.acquire | b.acquire;

always_ff @(posedge clk) begin
    // Save-state traffic has priority; the framebuffer is a continuously
    // available client and resumes after the state engine releases acquire.
    if (a.acquire) a_active <= 1'b1;
    else if (b.acquire) a_active <= 1'b0;
end

endmodule
