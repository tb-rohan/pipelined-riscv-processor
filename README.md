# RISC-V RV32I + INT8 CNN Accelerator SoC

> **Mandatory Hardware Disclaimer**
> *This project was developed and validated entirely using software-based RTL simulation and FPGA toolchain flows (AMD/Xilinx Vivado v2026.1 and Icarus Verilog v12.0). No physical FPGA development board was used for hardware testing.*

A complete, interview-grade System-on-Chip (SoC) integrating a 5-stage pipelined RV32I processor core with a dedicated 4×4 systolic-array INT8 convolutional neural network (CNN) inference accelerator via an AXI4-Lite memory-mapped interconnect.

---

## 1. Project Motivation & Objectives

Modern edge AI hardware systems demand tight hardware-software co-design: general-purpose control and pre/post-processing handled by an embedded RISC-V CPU, coupled with high-throughput spatial systolic arrays for dense tensor compute.

The primary objective of this project is to develop a technically rigorous, reproducible, well-verified BTech-level hardware engineering project demonstrating:
- **Pipelined Computer Architecture:** 5-stage in-order RV32I datapath with forwarding networks, hazard stalls, and multi-cycle bus wait-state interlocks.
- **Hardware Acceleration:** 2D weight-stationary (WS) $4 \times 4$ systolic array executing 16 INT8 multiply-accumulate (MAC) operations per cycle with integrated post-processing (bias addition, fixed-point requantization with convergent rounding, ReLU, and 2×2 max pooling).
- **Heterogeneous Interconnect:** Memory-mapped AXI4-Lite adapter with synchronous backpressure stall injection (`dmem_stall` + `flush_mem_wb`), hardware watchdog timer, and capability registers.
- **Hardware-Software Co-Design:** End-to-end MNIST digit classification executing microcode loading, tensor DMA streaming, accelerator execution, and software argmax prediction.
- **Transparent Engineering Realism:** Rigorous separation between measured simulation/synthesis results and design aspirations, with deep analysis of FPGA timing closure and BRAM inference.

---

## 2. High-Level SoC Architecture

The SoC integrates the RV32I processor, independent instruction/data memories, bus interconnect, peripheral mailboxes, AXI4-Lite accelerator adapter, and the 4×4 systolic array compute engine (`riscv_cnn_soc_top.sv`):

```text
+---------------------------------------------------------------------------------------------------+
|                                         riscv_cnn_soc_top                                         |
|                                                                                                   |
|   +-----------------------+              +----------------------------------------------------+   |
|   |      rv32i_core       |  Instruction |                    imem (16KB)                     |   |
|   |                       | <----------  |            (0x0000_0000 - 0x0000_3FFF)             |   |
|   |  - 5-Stage In-Order   |              +----------------------------------------------------+   |
|   |  - Full Forwarding    |                                                                       |
|   |  - Hazard Detection   |  Data Bus    +----------------------------------------------------+   |
|   |  - Load/Store Unit    | <----------> |                  bus_interconnect                  |   |
|   |  - Performance Monitor|              +-------------------------+--------------------------+   |
|   +-----------------------+                                        |                              |
|                                         +--------------------------+--------------------------+   |
|                                         |                          |                          |   |
|                                         v                          v                          v   |
|                              +---------------------+    +---------------------+    +--------------+
|                              |     dmem (16KB)     |    |  Core Peripherals   |    |    accel_    |
|                              |  (0x0000_4000 ..    |    |  (0x8000_0000 ..    |    |   adapter    |
|                              |   0x0000_7FFF)      |    |   0x8000_005F)      |    | (MMIO->AXI-L)|
|                              +---------------------+    | - Host Interface    |    +-------+------+
|                                                         | - 64-bit Timer/HPMU |            |      |
|                                                         | - UART Lite Transmit|            | AXI4 |
|                                                         +---------------------+            | Lite |
|                                                                                            v      |
|                                                                                    +--------------+
|                                                                                    |  accel_top   |
|                                                                                    | (INT8 4x4    |
|                                                                                    |  Systolic    |
|                                                                                    |  Array Engine|
|                                                                                    +--------------+
+---------------------------------------------------------------------------------------------------+
```

---

## 3. RV32I CPU Pipeline Architecture

The processor implements the unprivileged 32-bit RISC-V integer base instruction set (RV32I, 37 instructions) across a 5-stage in-order pipeline:

```text
  [IF Stage]           [ID Stage]           [EX Stage]          [MEM Stage]          [WB Stage]
+------------+       +------------+       +------------+       +------------+       +------------+
|  PC Reg    | ----> | Decode Unit| ----> | ALU / Shft | ----> | Load/Store | ----> | Reg Write  |
|  IMEM Read |       | RegFile Rd |       | Branch Cmp |       | Bus Trans  |       | Multiplexer|
+------------+       +------------+       +------------+       +------------+       +------------+
       ^                                         |                   |                     |
       |============= Hazard Stall / Flush ======|===================|                     |
       |                                         ^                   |                     |
       |=========================================+== Forwarding Data ======================|
```

- **IF (Instruction Fetch):** Generates $PC+4$ or branches/jumps; fetches 32-bit instructions from 16 KB `imem`.
- **ID (Instruction Decode):** Decodes opcodes/immediates; accesses dual-read register file (32 x 32-bit, `x0=0`).
- **EX (Execute):** 32-bit ALU (arithmetic, logic, shifts, comparisons) and branch comparator. Operands selected via forwarding multiplexers.
- **MEM (Memory Access):** Load/store unit formatting byte, halfword, and word transactions with byte-enable strobes.
- **WB (Writeback):** Commits ALU, memory, or link target values to the destination register.

### Hazard & Wait-State Control
- **Data Forwarding:** Priority 1 from EX/MEM stage; Priority 2 from MEM/WB stage.
- **Load-Use Interlock:** Freezes PC and IF/ID, injecting a 1-cycle bubble into ID/EX when an instruction depends on a load currently in EX.
- **Branch Resolution:** Taken branches resolve in EX with an exact 2-cycle penalty (flushes IF/ID and ID/EX).
- **Bus Wait-State Interlock (`dmem_stall`):** When accessing multi-cycle slaves (e.g. accelerator adapter), the hazard unit freezes PC, IF/ID, ID/EX, and EX/MEM while asserting `flush_mem_wb = dmem_stall` to inject a bubble into WB, preventing duplicate instruction retirement.

---

## 4. INT8 CNN Accelerator Microarchitecture

The accelerator (`accel_top.sv`) executes deep neural network layer pipelines with dedicated spatial hardware:
- **Systolic Array (`pe_array.sv`):** 2D mesh of 16 processing elements (PEs) organized in 4 rows and 4 columns.
  - **Dataflow:** Weight-Stationary (WS) execution. 8-bit signed weights are preloaded into PE registers via `w_load_en` and held stationary during tile computation.
  - **Feature Map Streaming:** 8-bit signed activations stream horizontally (left-to-right) through diagonal wavefront skew registers.
  - **Partial-Sum Accumulation:** 32-bit signed partial sums accumulate vertically (top-to-bottom) across columns ($P_{\text{out}} \leftarrow P_{\text{in}} + A \times W$) and exit through deskew registers directly into the post-processing pipeline.
- **Memory Subsystem (`mem_ctrl.sv`):** Manages on-chip ping-pong activation BRAMs (16 KB) and weight BRAMs (160x RAMB18E1) with registered boundary counters, driving high-throughput tensor address generation across convolutional tiles.
- **Post-Processor (`post_proc.sv`):**
  - Signed 32-bit bias addition: $\text{Acc} + \text{Bias}$.
  - Requantization: Fixed-point scaling and arithmetic right-shift with convergent rounding ($+ (1 \ll (\text{shift}-1))$) and clipping to $[-128, 127]$.
  - Activation & Pooling: ReLU activation and spatial $2 \times 2$ Max Pooling.

---

## 5. Bus Architecture & Register Map

Physical address space decoded by `bus_interconnect.sv`:

| Address Range | Device | Wait States | Function |
| :--- | :--- | :---: | :--- |
| `0x0000_0000 - 0x0000_3FFF` | `imem` (16 KB) | 0 | Instruction Memory |
| `0x0000_4000 - 0x0000_7FFF` | `dmem` (16 KB) | 0 | Data Memory |
| `0x8000_0000 - 0x8000_001F` | `host_interface` | 0 | Host control & status mailbox |
| `0x8000_0020 - 0x8000_003F` | `timer` (HPMU) | 0 | 64-bit cycle timer & event counters |
| `0x8000_0040 - 0x8000_005F` | `uart_lite` | 0 | Character debug console |
| `0x8000_1000 - 0x8000_10FF` | `accel_adapter` | Variable | INT8 Accelerator MMIO-AXI4 Window |

### Accelerator Register Space (`0x8000_1000 - 0x8000_1030`)

| Offset | Register Name | Access | Reset | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | `ACCEL_CTRL` | R/W | `0x0` | `[0]`: Start inference (self-clearing pulse), `[1]`: Soft reset |
| `0x04` | `ACCEL_STATUS` | R | `0x0` | `[0]`: Busy (active execution), `[1]`: Done (inference complete) |
| `0x08` | `ACCEL_VERSION` | R | `0x01040408` | Version: Major=1, Minor=0, 4x4 array, 8-bit precision |
| `0x0C` | `ADAPTER_STATUS`| R/W1C | `0x0` | `[0]`: Timeout error (W1C), `[1]`: Busy, `[2]`: IRQ, `[31:16]`: Watchdog count |
| `0x10` | `DMA_ADDR` | R/W | `0x0` | Accelerator input activation SRAM write address |
| `0x14` | `DMA_DATA` | R/W | `0x0` | Accelerator input activation SRAM 32-bit write data |
| `0x18` | `RES_ADDR` | R/W | `0x0` | Accelerator output result SRAM read address |
| `0x1C` | `RES_DATA` | R | `0x0` | Accelerator output result SRAM 32-bit read data |
| `0x20` | `INSTR_W0` | R/W | `0x0` | Microcode instruction word bits [31:0] |
| `0x24` | `INSTR_W1` | R/W | `0x0` | Microcode instruction word bits [63:32] |
| `0x28` | `INSTR_W2` | R/W | `0x0` | Microcode instruction word bits [95:64] |
| `0x2C` | `INSTR_W3` | R/W | `0x0` | Microcode instruction word bits [127:96] |
| `0x30` | `INSTR_ADDR` | R/W | `0x0` | Instruction write address and commit trigger |

---

## 6. Firmware Execution & Hardware-Software Co-Design

The software runtime (`software/asm/soc_cnn_inference.s`) coordinates end-to-end inference:
1. **Microcode Dispatch:** CPU writes layer control words (tile counts, dimensions, strides, quantization parameters) into `INSTR_W0..W3` and commits via `INSTR_ADDR`.
2. **Tensor Streaming:** CPU transfers 28×28 grayscale pixel data to `DMA_ADDR` and `DMA_DATA`.
3. **Execution Kickoff:** CPU asserts `ACCEL_CTRL[0]` (`START`).
4. **Hardware Execution:** The accelerator executes Conv1 (3x3), Pool1 (2x2), Conv2 (3x3), Pool2 (2x2), and Dense layers in **53,836 cycles**.
5. **Status Polling:** CPU polls `ACCEL_STATUS[0]` until busy deasserts and done asserts.
6. **Result Readback & Argmax:** CPU reads 10 class logits via `RES_ADDR` / `RES_DATA` and executes a software argmax search in RV32I assembly to classify the winning digit.
7. **Total Latency:** **80,874 clock cycles** (Accelerated compute: 66.57%, Software tensor transfer and argmax: 33.43%).

---

## 7. INT8 Quantization Semantics

- **Format:** Symmetric INT8 quantization for activations and weights ($[-128, 127]$).
- **Accumulator:** 32-bit signed two's-complement accumulator ($[-2^{31}, 2^{31}-1]$) providing headroom for up to 16,777,216 MAC accumulations without overflow.
- **Requantization Formula:**
  $$\text{Act}_{\text{out}} = \text{clip}\left(\left((Acc_{\text{int32}} + \text{Bias}_{\text{int32}}) \times \text{Scale} + (1 \ll (\text{Shift} - 1))\right) \gg \text{Shift}, -128, 127\right)$$
- **Precision Verification:** Evaluated against an independent Python golden reference model. In full MNIST inference across test samples (e.g., Digit 7 and Digit 2), all 10 hardware output logits match the integer golden model with **zero mismatch (100% bit-exact agreement)**.

---

## 8. Verification Methodology & Results

The verification framework combines unit testbenches, directed ISA suites, constrained-random testing, and end-to-end SoC regressions:

```powershell
python run_all.py
```

### Regression Summary (79/79 PASS - 100% Success)

| Verification Category | Suite / Testbench | Tests Run | Result | Details |
| :--- | :--- | :---: | :---: | :--- |
| **RV32I Core Directed** | `tb_cpu_interactive.sv` | 15 | **PASS** | Directed arithmetic, shifts, logic, corner division |
| **RV32I ISA Compliance**| `interactive_cpu.s` | 1 | **PASS** | All 37 unprivileged instructions verified (Case 14) |
| **RV32I Random Stress** | `run_interactive_cpu.py`| 50 | **PASS** | 50 randomized golden model stress vectors (Seed: 42) |
| **Accelerator Units** | `tb_pe`, `tb_pe_array`, `tb_post_proc` | 3 | **PASS** | MAC math, systolic propagation, requantization |
| **Memory & Control** | `tb_mem_ctrl_*`, `tb_ctrl_unit` | 3 | **PASS** | Tensor address generation, zero scan, FSM states |
| **Accelerator Standalone**| `tb_top`, `tb_full_cnn` | 2 | **PASS** | Standalone 5-layer CNN testbench |
| **SoC MMIO Adapter** | `tb_accel_adapter.sv` | 1 | **PASS** | Capability reg, watchdog timeout abort, W1C status reg |
| **SoC Multi-Layer** | `tb_riscv_cnn_soc.sv (+CMD=2)` | 1 | **PASS** | 3-layer deterministic workload (Conv -> Pool -> FC) |
| **SoC End-to-End MNIST**| `tb_riscv_cnn_soc.sv (+CMD=1)` | 3 | **PASS** | Samples #0 (Digit 7), #1 (Digit 2), 10 golden logits verified |
| **Total** | — | **79** | **100% PASS** | **Zero failures across all suites (Wall time: 30.41 s)** |

---

## 9. FPGA Synthesis & Timing Realities (AMD Artix-7 xc7a100tcsg324-1)

Implementation was performed in **AMD Vivado v2026.1 (64-bit)** at a 100 MHz target constraint (10.00 ns period).

### 9.1 Standalone CPU Implementation (`cpu_fpga_top.sv`)
- **Status:** **Timing Closed at 100 MHz**.
- **Post-Route Timing:** Worst Negative Slack (WNS) = **+0.178 ns** ($F_{\max} \approx 101.8\text{ MHz}$). Total Negative Slack (TNS) = **0.000 ns**.
- **Resource Utilization:**
  - Slice LUTs: 4,834 (7.62% of 63,400)
  - LUT as Distributed RAM: 2,292 (12.06% of SLICEM capacity)
  - Flip-Flops: 2,126 (1.68% of 126,800)
  - Block RAM / DSP: 0 / 135 tiles (0.00%)

### 9.2 Integrated SoC Implementation (`riscv_cnn_soc_top.sv`)
- **Status:** **Fully Placed, Routed & 100% Timing Closed at 100.00 MHz ($F_{\max} \approx 100.60\text{ MHz}$)**.
- **Before-and-After Optimization Highlights:**
  - **Memory Bottleneck (Resolved):** Weight buffer refactored into a dedicated synchronous read block with byte-write enables (`soc_mem_ctrl.sv`), inferring 76 Block RAM tiles and slashing Distributed LUTRAM from **34,304 (180.69% - physical overflow)** down to **6,144 (32.34%)** — a **-28,160 LUTRAM (-82.1%) reduction**.
  - **Combinational Path Optimization (Resolved):** Precomputed, registered spatial coordinate scaling (`scaled_tile_origin_x/y`) removed runtime stride multiplexing from the DSP multiplier input, collapsing critical path depth from **118 levels down to 11 levels**, meeting synthesis timing at **+0.219 ns WNS** (0 failing endpoints).
  - **Branch & Pipeline Timing Closure (Resolved):** Decoupled datapath registers from flush clears in `pipe_reg_id_ex.sv` and `pipe_reg_if_id.sv`, decoupled hazard stalls in `hazard_unit.sv`, and restricted late branch resolution to the PC data multiplexer in `rv32i_core.sv`. This eliminated a 322-fanout Clock Enable routing net across 50 slice columns, improving post-route WNS from **-0.491 ns** to **+0.060 ns (MET!)**, with **0.000 ns TNS** and **0 failing endpoints out of 48,287 endpoints**.
  - **Full Placement & Routing Signoff:** Executed on Artix-7 `xc7a100tcsg324-1`: **21,495 of 21,495 routable nets fully routed (100.0%, 0 routing errors)**, achieving complete timing closure at **100.00 MHz** (10.00 ns period) with positive setup (+0.060 ns), hold (+0.103 ns), and pulse width (+3.750 ns) margins.
- **Final Post-Route Utilization Breakdown (`fpga_soc/reports/post_route_utilization.rpt`):**
  - Slice LUTs: **15,348** (24.21% of 63,400) — down from 50,519 (79.68%)
  - LUT as Distributed RAM: **6,144** (32.34% of 19,000) — 100% of overflow eliminated
  - Slice Registers (FF): **12,551** (9.90% of 126,800)
  - Block RAM Tiles: **76 / 135 (56.30%)** — 128 RAMB18E1 + 12 RAMB36E1 primitives
  - DSP48E1 Multipliers: **16 / 240 (6.67%)**
  - Inferred Latches: **0 (CLEAN)**
- *For detailed analysis, traces, and before-and-after tables, see [docs/TIMING_OPTIMIZATION_REPORT.md](docs/TIMING_OPTIMIZATION_REPORT.md) and [docs/FPGA_RESULTS.md](docs/FPGA_RESULTS.md).*

---

## 10. Reproducible Build & Simulation Instructions

For complete fresh-checkout setup and reproduction steps, see [docs/REPRODUCIBILITY.md](docs/REPRODUCIBILITY.md).

### Prerequisites
- Python 3.10+ (with `numpy`)
- Icarus Verilog (`iverilog` v12.0+) and `vvp`
- Optional: AMD Vivado 2026.1+ (for FPGA synthesis/implementation flows)

### Reproduction Commands

```powershell
# 1. Run Complete Master Regression (79 tests across CPU, CNN, and Integrated SoC)
python run_all.py

# 2. Run Integrated SoC Regression Suite Alone (70 tests)
python RISC-V/scripts/run_all_regressions.py

# 3. Run Standalone CPU Interactive Regression
python RISC-V/scripts/run_interactive_cpu.py --directed
python RISC-V/scripts/run_interactive_cpu.py --random --count 50 --seed 42

# 4. Run Multi-Sample MNIST Benchmark (10 test samples)
python RISC-V/scripts/run_interactive_soc.py --benchmark

# 5. Run Standalone CPU FPGA Synthesis Flow (Vivado)
cd RISC-V/fpga
.\run_synthesis.ps1
.\run_implementation.ps1
```

---

## 11. Achievements & Future Roadmap

### Completed Milestones
1. **Synchronous Block RAM Inference:** Resolved 180.69% distributed LUTRAM spill by migrating weight memory to synchronous reads with byte-write enables (`soc_mem_ctrl.sv`), reducing LUTRAM to 32.34% and freeing 28,160 LUTRAMs.
2. **Complete 100 MHz Timing Closure:** Resolved critical path bottlenecks via registered coordinate scaling and decoupled pipeline datapath flushes, closing post-route timing at **+0.060 ns WNS**, **0.000 ns TNS**, and **0 failing endpoints** (achieving $F_{\max} \approx 100.60\text{ MHz}$).
3. **Bit-Exact Functional Equivalence:** Verified 100% test pass rate across 70 regression tests and 100% accuracy on multi-sample MNIST digit benchmarks with zero logit mismatches.

### Future Architecture Extensions
1. **Autonomous Scatter-Gather DMA:** Implementing a bus-mastering DMA controller to eliminate CPU polling and manual word streaming, reducing end-to-end SoC inference latency by 33.4%.
2. **Vectored Interrupt Support:** Hooking the accelerator irq pin into a CPU interrupt controller will eliminate CPU busy-wait spinloops.
3. **Dynamic Requantization Scaling:** Supporting per-channel scaling factors and asymmetric zero-point offsets for int8 quantizations of larger vision backbones (e.g. MobileNetV2).

---

## 12. References & Attribution

- **[arxnav18/RISCV-EDGE-AI-CNN](https://github.com/arxnav18/RISCV-EDGE-AI-CNN):** Architectural reference for 5-stage RV32I integration with LeNet-5 CNN coprocessor and line-buffer spatial caching.
- **[KakeruVon/RVCCC](https://github.com/KakeruVon/RVCCC):** CPU-controlled CNN integration on Xilinx Zynq-7020; hardware-software interface trade-offs and dual-port shared memory.
- **[Kunaalr11/RISC-V-based-Accelerated-CNN-inference](https://github.com/Kunaalr11/RISC-V-based-Accelerated-Coprocesser-for-CNN-inference):** AXI4-Lite slave coprocessor interfacing and line-buffer reuse strategies.
- **[Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC](https://github.com/Rishi192004/TPU-Lite-Systolic-Array-ML-Inference-Accelerator-SoC):** 8×8 systolic array architecture, double-buffered BRAM ping-ponging, and carry-save adder (CSA) retiming methodologies.

---

## 13. License

This project is open-source hardware and software licensed under the **MIT License** — see the [LICENSE](LICENSE) file for complete terms and copyright notices.
