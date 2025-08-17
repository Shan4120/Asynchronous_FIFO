// ==========================================================================
// Async FIFO (single-module version)
// Features: dual-clock, Gray-coded pointers, 2-FF sync, active-low resets
// Params: DSIZE = data width, ASIZE = address bits (DEPTH = 2**ASIZE)
// ==========================================================================
module async_fifo #(
  parameter integer DSIZE = 8,
  parameter integer ASIZE = 4
)(
  // Write side
  input  wire                 wclk,
  input  wire                 wrst_n,   // active-low
  input  wire                 winc,
  input  wire [DSIZE-1:0]     wdata,
  output reg                  wfull,

  // Read side
  input  wire                 rclk,
  input  wire                 rrst_n,   // active-low
  input  wire                 rinc,
  output reg  [DSIZE-1:0]     rdata,
  output reg                  rempty
);

  localparam integer DEPTH = (1 << ASIZE);

  // =========================================================================
  // Memory (simple dual-port: write @ wclk, read @ rclk)
  // =========================================================================
  reg [DSIZE-1:0] mem [0:DEPTH-1];

  // =========================================================================
  // Binary and Gray pointers
  // =========================================================================
  reg [ASIZE:0] wptr_bin, wptr_bin_next;
  reg [ASIZE:0] rptr_bin, rptr_bin_next;

  reg [ASIZE:0] wptr_gray, wptr_gray_next;
  reg [ASIZE:0] rptr_gray, rptr_gray_next;

  wire [ASIZE-1:0] waddr = wptr_bin[ASIZE-1:0];
  wire [ASIZE-1:0] raddr = rptr_bin[ASIZE-1:0];

  // Synchronized Gray pointers across domains
  reg [ASIZE:0] wq1_rptr_gray, wq2_rptr_gray; // read ptr synced into write domain
  reg [ASIZE:0] rq1_wptr_gray, rq2_wptr_gray; // write ptr synced into read domain

  // =========================================================================
  // Helper functions
  // =========================================================================
  // Binary to Gray
  function [ASIZE:0] bin2gray(input [ASIZE:0] b);
    bin2gray = (b >> 1) ^ b;
  endfunction

  // =========================================================================
  // Write-domain logic
  // =========================================================================
  wire wpush = winc & ~wfull;

  always @(*) begin
    wptr_bin_next  = wptr_bin + (wpush ? 1'b1 : 1'b0);
    wptr_gray_next = bin2gray(wptr_bin_next);
  end

  // Full when next write Gray equals read Gray with MSBs inverted
  wire wfull_val = (wptr_gray_next == {~wq2_rptr_gray[ASIZE:ASIZE-1], wq2_rptr_gray[ASIZE-2:0]});

  // Write pointer & full flag registers
  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wptr_bin  <= '0;
      wptr_gray <= '0;
      wfull     <= 1'b0;
    end else begin
      wptr_bin  <= wptr_bin_next;
      wptr_gray <= wptr_gray_next;
      wfull     <= wfull_val;
    end
  end

  // Write pointer receives synchronized read pointer (Gray) from read domain
  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      {wq2_rptr_gray, wq1_rptr_gray} <= '0;
    end else begin
      wq1_rptr_gray <= rptr_gray;
      wq2_rptr_gray <= wq1_rptr_gray;
    end
  end

  // Memory write
  always @(posedge wclk) begin
    if (wpush) begin
      mem[waddr] <= wdata;
    end
  end

  // =========================================================================
  // Read-domain logic
  // =========================================================================
  wire rpop = rinc & ~rempty;

  always @(*) begin
    rptr_bin_next  = rptr_bin + (rpop ? 1'b1 : 1'b0);
    rptr_gray_next = bin2gray(rptr_bin_next);
  end

  // Empty when next read Gray equals synchronized write Gray
  wire rempty_val = (rptr_gray_next == rq2_wptr_gray);

  // Read pointer & empty flag registers
  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      rptr_bin  <= '0;
      rptr_gray <= '0;
      rempty    <= 1'b1;
      rdata     <= '0;
    end else begin
      rptr_bin  <= rptr_bin_next;
      rptr_gray <= rptr_gray_next;
      rempty    <= rempty_val;
      // Synchronous read: register output on rclk
      if (rpop) rdata <= mem[raddr];
    end
  end

  // Read side receives synchronized write pointer (Gray)
  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      {rq2_wptr_gray, rq1_wptr_gray} <= '0;
    end else begin
      rq1_wptr_gray <= wptr_gray;
      rq2_wptr_gray <= rq1_wptr_gray;
    end
  end

endmodule
