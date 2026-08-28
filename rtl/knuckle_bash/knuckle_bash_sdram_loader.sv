// SPDX-License-Identifier: GPL-2.0-or-later
//
// Knuckle Bash index-0 HPS byte stream to the JTFrame SDRAM program bus.
// The V25 program occupies local BRAM and is deliberately omitted here.
// Every SDRAM payload is registered and held until the controller acknowledges
// it; no address, bank, lane, or data signal depends on live HPS inputs while
// a request is pending.
module knuckle_bash_sdram_loader (
    input  logic        clk,
    input  logic        rst,

    input  logic        ioctl_download,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic [ 7:0] ioctl_data,
    input  logic [15:0] ioctl_index,

    input  logic        sdram_init,
    input  logic        prog_ack,
    input  logic        prog_rdy,

    output logic        ioctl_wait,
    output logic [ 1:0] prog_ba,
    output logic [21:0] prog_addr,
    output logic [15:0] prog_data,
    output logic [ 1:0] prog_dsn,
    output logic        prog_we,
    output logic        prog_rd,

    output logic        download_drained,
    output logic        range_error,
    output logic        overflow_error
);

localparam logic [26:0] MAIN_END      = 27'h007_FFFF;
localparam logic [26:0] V25_START     = 27'h008_0000;
localparam logic [26:0] V25_END       = 27'h008_7FFF;
localparam logic [26:0] GFX_START     = 27'h008_8000;
localparam logic [26:0] GFX_END       = 27'h088_7FFF;
localparam logic [26:0] SAMPLE_START  = 27'h088_8000;
localparam logic [26:0] SAMPLE_END    = 27'h08C_7FFF;
localparam logic [26:0] IMAGE_END     = 27'h08C_8000;

logic        pending;
logic        await_rdy;
logic        index_zero;
logic        stream_write;
logic        sdram_target;
logic [ 1:0] decoded_ba;
logic [22:0] decoded_local_byte;
logic [21:0] decoded_prog_addr;

always_comb begin
    index_zero        = ioctl_index == 16'd0;
    stream_write      = ioctl_download && ioctl_wr && index_zero;
    sdram_target      = 1'b0;
    decoded_ba        = 2'd0;
    decoded_local_byte = 23'd0;
    decoded_prog_addr = 22'd0;

    if (ioctl_addr <= MAIN_END) begin
        sdram_target       = 1'b1;
        decoded_ba         = 2'd0;
        decoded_local_byte = ioctl_addr[22:0];
    end else if ((ioctl_addr >= V25_START) &&
                 (ioctl_addr <= V25_END)) begin
        // Local V25 BRAM consumes this range outside the SDRAM adapter.
        sdram_target       = 1'b0;
    end else if ((ioctl_addr >= GFX_START) &&
                 (ioctl_addr <= GFX_END)) begin
        sdram_target       = 1'b1;
        decoded_ba         = 2'd1;
        decoded_local_byte = ioctl_addr - GFX_START;
    end else if ((ioctl_addr >= SAMPLE_START) &&
                 (ioctl_addr <= SAMPLE_END)) begin
        sdram_target       = 1'b1;
        decoded_ba         = 2'd2;
        decoded_local_byte = ioctl_addr - SAMPLE_START;
    end

    // The raw 8 MiB GP image stores all lower-plane words followed by all
    // upper-plane words. Pack each matching 16-bit pair into one 32-bit
    // JTFrame cache block:
    //
    //   raw word {plane,n[20:0]} -> physical word {n[20:0],plane}
    //
    // The HPS stream and ROM-valid CRC remain the authoritative raw MAME
    // layout; only the physical bank-1 destination address is transformed.
    decoded_prog_addr = (decoded_ba == 2'd1) ?
                        {decoded_local_byte[21:1],
                         decoded_local_byte[22]} :
                        decoded_local_byte[22:1];
end

// JTFrame's programming handshake has two distinct phases. prog_ack accepts
// the held request and releases prog_we; prog_rdy later marks completion of
// the SDRAM write. Keep HPS backpressured through both phases so the payload
// register cannot be reused before the write has actually drained.
always_comb begin
    prog_we          = pending;
    prog_rd          = 1'b0;
    ioctl_wait       = pending || await_rdy ||
                       (ioctl_download && index_zero && sdram_init);
    download_drained = !sdram_init && !pending && !await_rdy &&
                       !ioctl_download;
end

always_ff @(posedge clk) begin
    if (rst) begin
        pending        <= 1'b0;
        await_rdy       <= 1'b0;
        prog_ba         <= 2'd0;
        prog_addr       <= 22'd0;
        prog_data       <= 16'd0;
        prog_dsn        <= 2'b11;
        range_error     <= 1'b0;
        overflow_error  <= 1'b0;
    end else begin
        if (pending) begin
            if (prog_ack) begin
                pending <= 1'b0;
                await_rdy <= !prog_rdy;
            end
        end else if (await_rdy) begin
            if (prog_rdy)
                await_rdy <= 1'b0;
        end else if (stream_write && sdram_target && !sdram_init) begin
            pending   <= 1'b1;
            prog_ba    <= decoded_ba;
            prog_addr  <= decoded_prog_addr;
            prog_data  <= {ioctl_data, ioctl_data};
            // prog_dsn is active low: even byte selects lane 0, odd lane 1.
            prog_dsn   <= decoded_local_byte[0] ? 2'b01 : 2'b10;
        end

        // IMAGE_END is a legal end-exclusive replay sentinel. The V25 window
        // and every nonzero ioctl index are intentionally ignored here.
        if (stream_write && (ioctl_addr > IMAGE_END))
            range_error <= 1'b1;

        // A valid SDRAM byte presented despite backpressure is diagnosed and
        // discarded. It can never replace an already-held payload.
        if (stream_write && sdram_target &&
            (sdram_init || pending || await_rdy))
            overflow_error <= 1'b1;
    end
end

endmodule
