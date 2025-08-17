`timescale 1ns/1ps

// Testbench for async_fifo (single-module, combinational read)
module async_fifo_tb;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam integer DSIZE = 8;
  localparam integer ASIZE = 4; // depth = 2**ASIZE
  localparam integer DEPTH = (1 << ASIZE);

  // --------------------------------------------------------------------------
  // DUT I/O
  // --------------------------------------------------------------------------
  reg                  wclk, wrst_n, winc;
  reg  [DSIZE-1:0]     wdata;
  wire                 wfull;

  reg                  rclk, rrst_n, rinc;
  wire [DSIZE-1:0]     rdata;
  wire                 rempty;

  // --------------------------------------------------------------------------
  // Instantiate DUT
  // --------------------------------------------------------------------------
  async_fifo #(
    .DSIZE(DSIZE),
    .ASIZE(ASIZE)
  ) dut (
    // write
    .wclk(wclk),
    .wrst_n(wrst_n),
    .winc(winc),
    .wdata(wdata),
    .wfull(wfull),
    // read
    .rclk(rclk),
    .rrst_n(rrst_n),
    .rinc(rinc),
    .rdata(rdata),
    .rempty(rempty)
  );

  // --------------------------------------------------------------------------
  // Clocks
  // --------------------------------------------------------------------------
  initial begin
    wclk = 1'b0;
    forever #5 wclk = ~wclk;   // 100 MHz
  end

  initial begin
    rclk = 1'b0;
    forever #7 rclk = ~rclk;   // ~71.4 MHz (asynchronous to wclk)
  end

  // --------------------------------------------------------------------------
  // Resets
  // --------------------------------------------------------------------------
  initial begin
    wrst_n = 1'b0;
    rrst_n = 1'b0;
    winc   = 1'b0;
    rinc   = 1'b0;
    wdata  = '0;
    #(50);
    wrst_n = 1'b1;
    rrst_n = 1'b1;
  end

  // --------------------------------------------------------------------------
  // Scoreboard (reference model)
  // Compares read data against the exact sequence of accepted writes.
  // --------------------------------------------------------------------------
  integer ref_wr_ptr, ref_rd_ptr;
  integer total_push, total_pop, mismatch_count;
  reg [DSIZE-1:0] ref_mem [0:4095]; // enough for long sims

  // Capture rdata between rclk edges to avoid race with pointer update
  reg [DSIZE-1:0] rdata_sampled;
  always @(negedge rclk) begin
    rdata_sampled <= rdata;
  end

  // Track previous cycle's rinc/rempty for alignment
  reg prev_rinc, prev_rempty;
  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      prev_rinc   <= 1'b0;
      prev_rempty <= 1'b1;
    end else begin
      // On each posedge, check the result of the previous cycle's read attempt
      if (prev_rinc && !prev_rempty) begin
        if (rdata_sampled !== ref_mem[ref_rd_ptr]) begin
          $display("[%0t] ERROR: Read mismatch. Expected=0x%0h, Got=0x%0h (ref_rd_ptr=%0d)",
                   $time, ref_mem[ref_rd_ptr], rdata_sampled, ref_rd_ptr);
          mismatch_count = mismatch_count + 1;
        end
        ref_rd_ptr = ref_rd_ptr + 1;
        total_pop  = total_pop  + 1;
      end
      prev_rinc   <= rinc;
      prev_rempty <= rempty;
    end
  end

  // Reference capture of accepted writes
  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      ref_wr_ptr  <= 0;
      total_push  <= 0;
      mismatch_count <= 0;
    end else begin
      if (winc && !wfull) begin
        ref_mem[ref_wr_ptr] <= wdata;
        ref_wr_ptr = ref_wr_ptr + 1;
        total_push = total_push + 1;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Stimulus
  // --------------------------------------------------------------------------

  // Write data generation: increment only when write is accepted
  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      wdata <= 8'hA5; // start pattern
    end else begin
      if (winc && !wfull) begin
        wdata <= wdata + 8'h1;
      end
    end
  end

  // Write enable process: pseudo-random bursts
  initial begin : WRITE_PROC
    @(posedge wrst_n); // wait until out of reset
    repeat (10) @(posedge wclk); // settle
    repeat (600) begin
      @(posedge wclk);
      // 75% chance to attempt write; auto back off when full
      if ($random % 4 != 0) winc <= 1'b1; else winc <= 1'b0;
      if (wfull) winc <= 1'b0;
    end
    // stop writing
    @(posedge wclk);
    winc <= 1'b0;
  end

  // Read enable process: pseudo-random bursts
  initial begin : READ_PROC
    @(posedge rrst_n);
    repeat (5) @(posedge rclk); // settle
    repeat (900) begin
      @(posedge rclk);
      // 70% chance to attempt read; auto back off when empty
      if ($random % 10 < 7) rinc <= 1'b1; else rinc <= 1'b0;
      if (rempty) rinc <= 1'b0;
    end
    // drain remaining data
    while (!rempty) begin
      @(posedge rclk);
      rinc <= 1'b1;
    end
    @(posedge rclk);
    rinc <= 1'b0;
  end

  // Finish conditions and summary
  initial begin : FINISH_BLOCK
    // VCD (optional)
    $dumpfile("async_fifo_tb.vcd");
    $dumpvars(0, async_fifo_tb);

    // Run long enough for processes to complete
    #(20000);

    // Report
    $display("==============================================================");
    $display("  TEST SUMMARY");
    $display("  Pushes accepted : %0d", total_push);
    $display("  Pops accepted   : %0d", total_pop);
    $display("  Mismatches      : %0d", mismatch_count);
    $display("==============================================================");

    if (mismatch_count == 0) begin
      $display("PASS: No mismatches found.");
    end else begin
      $display("FAIL: Mismatches detected.");
    end
    $finish;
  end

endmodule
