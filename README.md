# Asynchronous_FIFO
Design of a 32×256 asynchronous FIFO with Gray code pointers and 2-flop synchronizers, featuring pessimistic full/empty flags and validated under 40 MHz write / 30 MHz read clocks with 512-burst traffic in ModelSim



# Async FIFO (Dual-Clock, Single-Module) — Verilog

A synthesizable, single-file **asynchronous FIFO** with:
- **Dual clocks** (independent write/read)
- **Gray-coded pointers** and **2-FF synchronizers**
- **Active-low async resets**
- **Parameterized** width/depth: `DSIZE` (data width), `ASIZE` (address bits), depth = `2**ASIZE`

> This version merges controller + memory into **one module** (`async_fifo.v`) and follows the classic Cummings FIFO scheme.

---

## Interface

**Write side**
- `wclk` — write clock  
- `wrst_n` — active-low async reset (write domain)  
- `winc` — write enable (assert to push when not full)  
- `wdata[DSIZE-1:0]` — write data  
- `wfull` — FIFO full

**Read side**
- `rclk` — read clock  
- `rrst_n` — active-low async reset (read domain)  
- `rinc` — read enable (assert to pop when not empty)  
- `rdata[DSIZE-1:0]` — read data  
- `rempty` — FIFO empty

---

## Parameters

- `DSIZE` *(default 8)* — data width  
- `ASIZE` *(default 4)* — address bits ⇒ depth = `2**ASIZE`

---

## How it Works (brief)

- Pointers are kept in **binary** for addressing and converted to **Gray** for crossing clock domains.
- Cross-domain communication uses **two-flip-flop synchronizers**.
- **Full**: next write Gray equals read Gray with MSBs inverted.  
- **Empty**: next read Gray equals synchronized write Gray.

---

## Example Instantiation

```verilog
async_fifo #(
  .DSIZE(32),
  .ASIZE(5) // depth = 32
) u_fifo (
  // write
  .wclk   (wclk),
  .wrst_n (wrst_n),
  .winc   (wvalid),
  .wdata  (wdata),
  .wfull  (wfull),

  // read
  .rclk   (rclk),
  .rrst_n (rrst_n),
  .rinc   (rready),
  .rdata  (rdata),
  .rempty (rempty)
);
