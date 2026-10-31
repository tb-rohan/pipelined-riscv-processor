# Known Limitations & Hardware-Software Boundary Specification

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

This document provides an explicit, transparent delineation of the architectural boundaries, hardware implementation trade-offs, and software runtime responsibilities for the Standalone RV32I Processor.

---

## 1. Processor Core Architectural Boundaries

### 1.1 Instruction Set Architecture (RV32I Base Integer Only)
- **Supported:** 37 standard unprivileged RV32I integer instructions.
- **Hardware Multiply & Divide (M-Extension):**
  - **Not implemented in hardware datapath.** Standard RV32I specifies hardware multiply/divide as an optional extension (`RV32M`).
  - **Software Solution:** Software shift-and-add signed multiplication (`mul_core`) and restoring division (`div_core`) subroutines are implemented in firmware (`interactive_cpu.s`). Corner cases (division-by-zero returning quotient $-1$ and remainder $N$, and signed overflow $\text{INT\_MIN} / -1 = \text{INT\_MIN}$) are handled deterministically in compliance with RISC-V specifications.
- **Floating Point (F/D-Extensions):**
  - No hardware FPU is present. All operations are strictly 32-bit integer.
- **Privilege Modes & CSRs:**
  - The core executes in Machine/User unprivileged mode.
  - Privileged CSR instructions (`CSRRW`, `CSRRS`, `CSRRC`) and page tables/virtual memory are not implemented; physical addressing is utilized throughout the 32-bit address space.
  - `ECALL`, `EBREAK`, and `FENCE` are decoded as safe non-trapping instructions in standalone simulation.

### 1.2 Pipeline & Branch Resolution
- **Static Branch Not-Taken Prediction:**
  - Untaken branches continue down the sequential fetch path with **zero cycle penalty**.
  - Taken branches and jumps are resolved in the Execution (EX) stage, incurring a **2-cycle pipeline flush penalty** (IF/ID and ID/EX registers flushed).
- **Single-Issue In-Order Execution:**
  - The pipeline issues at most 1 instruction per clock cycle in strict program order.
  - No out-of-order execution, speculative execution, or register renaming is implemented.

---

## 2. Memory Subsystem & Bus Interconnect

### 2.1 Harvard Memory Architecture with Unified Addressing
- **Split Instruction & Data Ports:**
  - The CPU core provides separate instruction fetch (`imem`) and data memory (`dmem`) interfaces (16 KB each) to enable concurrent fetch and data load/store without structural pipeline stalls.
- **Single-Cycle Combinational Read Ports:**
  - Memories use single-cycle combinational read ports (`assign rdata = mem[...]`).
  - In FPGA synthesis (Vivado), this causes memories to map to **Distributed RAM (2,292 LUTs)** rather than Block RAM (which requires a synchronous 1-cycle read register).
  - Migration to Block RAM will require inserting an IF2 fetch stage and restructuring hazard interlocks.
- **Memory Coherency & Caching:**
  - There are no hardware data caches (D-Cache) or instruction caches (I-Cache); code executes directly out of SRAM.
  - Code space (`0x0000_0000 - 0x0000_3FFF`) is distinct from data space (`0x0000_4000 - 0x0000_7FFF`). Self-modifying code requires manual software synchronization.

---

## 3. Verification & FPGA Implementation Scope

### 3.1 Simulator Scope
- The design is verified using Icarus Verilog (`iverilog` / `vvp` v12.0) and Python 3.13.
- The standalone CPU suite passes **69 / 69 tests (100% success)** across directed arithmetic, the full 37-instruction ISA suite, 50 randomized golden model tests, and FPGA wrapper smoke tests.

### 3.2 FPGA Implementation Scope
- Batch synthesis and physical implementation were executed using **AMD/Xilinx Vivado v2026.1 (64-bit)** on `xc7a100tcsg324-1` at 100 MHz.
- **Synthesis:** Cleanly met timing with **+0.787 ns WNS**, 0 inferred latches, and 4,863 Slice LUTs (including 2,292 distributed RAM LUTs).
- **Physical Implementation:** `opt_design`, `place_design`, `phys_opt_design`, and `route_design` completed with **100% routable net completion (4,956 / 4,956 nets, 0 errors)** and **+0.178 ns WNS post-route** (101.81 MHz Fmax).
- **Bitstream Generation:** Evaluated in Vivado on `post_route.dcp` using standard documented DRC severity downgrades for unconstrained pin testing (`NSTD-1`, `UCIO-1`), successfully generating `cpu_fpga_top.bit` (3,825,992 bytes). Physical FPGA programming and on-board hardware testing are explicitly not performed as no physical board is owned or used.
