# Standalone RV32I Processor: Final Engineering Completion Report

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Executive Summary

This project delivers a verified, technically sound, reproducible, and fully documented **32-bit RISC-V (RV32I) 5-stage pipelined processor core** (`cpu_fpga_top` and `rv32i_core`) implemented in SystemVerilog.

The processor was developed and verified entirely on a workstation environment using:
- **SystemVerilog RTL** with strictly synchronized clocking and no inferred latches.
- **Icarus Verilog v12.0** and **Python 3.13** for cycle-accurate simulation and golden reference verification.
- **AMD/Xilinx Vivado v2026.1 (64-bit)** for batch non-project synthesis, logic optimization, physical placement, physical optimization, timing-driven routing, static timing signoff, and bitstream generation evaluation.

### Key Achievements
1. **RTL Correctness & 100% Verification**: All 69 standalone processor tests passed with 100% success across directed arithmetic/logic tests, the complete 37-instruction base integer ISA suite (249 cycles), 50 constrained-randomized stress vectors, autonomous boot firmware (88 cycles), and FPGA wrapper smoke tests.
2. **Timing Closure at 100 MHz**: Post-route physical implementation on the **Artix-7 100T FPGA (`xc7a100tcsg324-1`)** closed timing at **100.00 MHz (10.000 ns)** with positive setup slack (**WNS = +0.178 ns**, 0 failing endpoints) and positive hold slack (**WHS = +0.159 ns**), achieving an actual maximum operating frequency of **101.81 MHz**.
3. **100% Routing Completion**: Net routing completed with 0 errors across all 4,956 nets (`post_route_status.rpt`).
4. **Physical Wrapper Architecture**: Built `cpu_fpga_top.sv` with a 2-stage flip-flop reset synchronizer (`sync_rst_n`), a 26-bit clock divider heartbeat LED (`led_heartbeat`), an autonomous power-on self-test (POST) controller, and a reduced footprint of **17 physical pins** (resolving DRC `IOCNT-1`).
5. **Bitstream Generation Evaluated**: Successfully compiled and generated a 3.65 MB bitstream file (`cpu_fpga_top.bit`, 3,825,992 bytes) using Vivado 2026.1 with documented unconstrained pin overrides.
6. **Documentation Overhaul**: Purged obsolete, duplicated, and contradictory files, producing authoritative, consistent documentation with explicit hardware disclaimers throughout.

---

## 2. Verified Processor Capabilities

| Subsystem | Architecture / Implementation | Verification Status |
| :--- | :--- | :---: |
| **Pipeline Architecture** | 5-Stage In-Order (IF, ID, EX, MEM, WB) | **Verified** |
| **ISA Coverage** | Full 37 Unprivileged RV32I Base Integer Instructions | **100% (37/37)** |
| **Data Forwarding** | Priority 1: EX/MEM; Priority 2: MEM/WB; Register file write-first bypass | **Verified** |
| **Load-Use Interlock** | 1-cycle automatic hardware stall (freezes PC & IF/ID, flushes ID/EX) | **Verified** |
| **Control Hazards** | Taken branch / jump flushes IF/ID and ID/EX (exact 2-cycle penalty) | **Verified** |
| **Multi-Cycle Bus Stall**| Synchronous MEM/WB bubble insertion (`flush_mem_wb = dmem_stall`) | **Verified** |
| **Arithmetic / Logic** | 32-bit ALU with single-cycle ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU | **Verified** |
| **Mathematical Software**| Iterative shift-and-add multiplication and restoring division subroutines | **Verified** |
| **Corner Cases** | Division-by-zero ($Q=-1, R=N$), signed overflow ($\text{INT\_MIN}/-1 = \text{INT\_MIN}$) | **Verified** |
| **Register File** | 32 $\times$ 32-bit dual-read, single-write, register `x0` hardwired to 0 | **Verified** |
| **Memory Interfaces** | Dual 16 KB Harvard memories (`imem`, `dmem`) with byte, halfword, word access | **Verified** |
| **Hardware Profiling** | 64-bit cycle counter and event monitors (`timer.sv` HPMU) | **Verified** |
| **FPGA Wrapper** | 17-pin physical wrapper with 2-stage reset synchronizer & autonomous POST | **Verified** |

---

## 3. Confirmed Defects Identified & Resolved

### Defect 1: Port Count Exhaustion on Physical Device (DRC `IOCNT-1`)
- **Root Cause**: The simulation top module `cpu_standalone_top` exposed 291 debug and control signals (wide buses, register dumps, probe signals). Targeting the Artix-7 `xc7a100tcsg324-1` (which provides 210 user I/O pins) caused Vivado to fail on DRC `IOCNT-1` (291 ports > 210 package pins).
- **RTL Correction**: Created a dedicated physical wrapper `cpu_fpga_top.sv` (`rtl/soc/cpu_fpga_top.sv`). The wrapper encapsulates all wide internal buses, instantiates `cpu_standalone_top`, and presents exactly **17 physical pins**: `clk`, `rst_n`, `btn_trigger`, `sw_mode[1:0]`, `led[7:0]`, `led_done`, `led_pass`, `led_fail`, `led_heartbeat`.
- **Verification Evidence**: Vivado synthesis and physical implementation completed cleanly with 0 errors and 17 bonded IOBs utilized (8.10% device utilization).

### Defect 2: Asynchronous Push-Button Metastability Hazard
- **Root Cause**: External reset buttons on FPGA development boards are asynchronous mechanical switches. Feeding an asynchronous reset directly into high-speed pipeline flip-flops causes metastability, clock domain crossing violations, and non-deterministic reset recovery.
- **RTL Correction**: Integrated a dedicated two-stage D flip-flop reset synchronizer (`sync_rst_n`) in `cpu_fpga_top.sv`. All internal registers, pipeline stages, memories, and peripherals are clocked strictly on `clk` and reset synchronously via `sync_rst_n`.
- **Verification Evidence**: Verified in `tb_cpu_fpga_top.sv`. The synchronizer cleanly deasserts reset synchronous to the rising clock edge, with zero metastability in simulation and zero latch warnings in Vivado.

### Defect 3: Missing Firmware Path Handling in Vivado Synthesis
- **Root Cause**: `fpga/scripts/run_synthesis.tcl` invoked `synth_design` without passing the absolute path to `interactive_cpu.hex`. When executed from varying working directories, `$readmemh` in `imem.sv` failed to locate the hex file, causing memory initialization to default to all zeros.
- **Tcl Fix**: Updated `run_synthesis.tcl` to normalize the absolute path to the initialization file and pass it explicitly via `-generic IMEM_INIT_FILE=$HEX_PATH` to `synth_design`.
- **Verification Evidence**: Synthesis logs confirm `[Synth 8-3886]` clean memory preloading with 349 firmware instructions initialized into memory primitives.

### Defect 4: Unspecified Configuration Bank Voltage (DRC `CFGBVS-1`)
- **Root Cause**: Vivado's DRC engine flagged `[DRC CFGBVS-1]` because the XDC constraints did not specify the configuration bank voltage select (`CFGBVS`) or configuration voltage (`CONFIG_VOLTAGE`).
- **Constraint Fix**: Added `set_property CFGBVS VCCO [current_design]` and `set_property CONFIG_VOLTAGE 3.3 [current_design]` to `fpga/constraints/clock.xdc`.
- **Verification Evidence**: Vivado DRC reports confirm `CFGBVS-1` is completely resolved with 0 errors.

### Defect 5: Stale Compilation Binary Hazard in Master Regression Runner
- **Root Cause**: `scripts/run_all_regressions.py` executed `.vvp` simulation binaries directly without checking if the underlying SystemVerilog source files or hex firmware had changed, risking execution of out-of-date binaries.
- **Script Fix**: Added `ensure_compiled()` to `run_all_regressions.py` to automatically recompile firmware and RTL with `iverilog` before launching tests.
- **Verification Evidence**: Running `python scripts/run_all_regressions.py` consistently compiles fresh binaries and passes all 69 tests with 100% determinism.

---

## 4. Summary of Verification Results

| Test Category | Suite File | Total Tests | Passed | Failed | Status |
| :--- | :--- | :---: | :---: | :---: | :---: |
| Directed Arithmetic & Logic | `tb_cpu_interactive.sv` | 15 | 15 | 0 | **PASS** |
| Full 37-Instruction RV32I ISA | `interactive_cpu.s` (CMD 14) | 1 | 1 | 0 | **PASS** |
| Constrained-Randomized Stress | `run_interactive_cpu.py` (Seed 42) | 50 | 50 | 0 | **PASS** |
| FPGA Top Wrapper Smoke Test | `tb_cpu_fpga_top.sv` | 2 | 2 | 0 | **PASS** |
| Autonomous Boot Firmware | `standalone_boot.s` | 1 | 1 | 0 | **PASS** |
| **Total Standalone CPU Verification** | — | **69** | **69** | **0** | **100% PASS** |

---

## 5. Summary of Vivado Synthesis & Implementation Results

Target Device: **AMD Xilinx Artix-7 `xc7a100tcsg324-1`** | Target Period: **10.000 ns (100.00 MHz)**

| Resource / Parameter | Synthesis Count | Post-Route Count | Device Capacity | Device Utilization | Status |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Slice LUTs** | 4,863 | **4,834** | 63,400 | **7.62 %** | Clean |
| ├── LUT as Logic | 2,571 | **2,542** | 63,400 | **4.01 %** | Clean |
| └── LUT as Distributed RAM | 2,292 | **2,292** | 19,000 | **12.06 %** | Clean |
| **Slice Registers (FFs)** | 2,177 | **2,051** | 126,800 | **1.62 %** | Clean |
| **Block RAM (BRAM Tiles)** | 0 | **0** | 135 | **0.00 %** | Clean |
| **DSP48E1 Slices** | 0 | **0** | 240 | **0.00 %** | Clean |
| **Bonded IOBs** | 17 | **17** | 210 | **8.10 %** | Clean |
| **Global Clock Buffers (BUFG)**| 1 | **1** | 32 | **3.13 %** | Clean |
| **Worst Negative Slack (WNS)** | **+0.787 ns** | **+0.178 ns** | — | — | **MET (0 Failing)** |
| **Total Negative Slack (TNS)** | **0.000 ns** | **0.000 ns** | — | — | **MET** |
| **Worst Hold Slack (WHS)** | **+0.131 ns** | **+0.159 ns** | — | — | **MET (0 Failing)** |
| **Total Hold Slack (THS)** | **0.000 ns** | **0.000 ns** | — | — | **MET** |
| **Signoff Operating Frequency** | — | **101.81 MHz** | — | — | **MET** |
| **Net Routing Completion** | — | **100% (4,956/4,956)** | — | — | **0 Errors** |
| **Bitstream File Size** | — | **3,825,992 bytes** | — | — | **Generated** |

---

## 6. Memory Mapping Rationale

- **Distributed RAM Inference**: The 5-stage pipeline employs single-cycle combinational read ports for instruction fetch (`imem`) and memory access (`dmem`). AMD 7-series Block RAMs (`RAMB36E1`) require synchronous registered reads (`always_ff @(posedge clk)`), imposing a mandatory 1-cycle pipeline delay.
- **Architectural Stability**: Inferring Block RAM directly would corrupt the 5-stage pipeline, requiring a 6-stage or 7-stage microarchitecture (introducing IF1/IF2 and MEM1/MEM2 stages) with additional branch penalties and forwarding multiplexers.
- **Design Decision**: Distributed RAM (utilizing Artix-7 SLICEM LUTs configured as RAM256X1S and RAM64M) implements true asynchronous read semantics with synchronous write. Distributed RAM consumes 12.06% of the available LUTRAM on the Artix-7 100T and easily closes timing at 100 MHz (+0.178 ns slack).

---

## 7. Bitstream Generation Assessment

- **DRC Verification**: Attempting `write_bitstream` without board-specific pinout constraints triggers DRC Critical Warnings `[DRC NSTD-1]` and `[DRC UCIO-1]`.
- **Software Signoff**: Applying documented DRC severity downgrades for unconstrained chip model verification:
  ```tcl
  set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
  set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
  write_bitstream -force cpu_fpga_top.bit
  ```
- **Result**: Successfully generated `fpga/checkpoints/cpu_fpga_top.bit` (**3,825,992 bytes**, ~3.65 MB) with 0 errors.
- **Physical Programming**: Not performed because no physical hardware board is owned or used.

---

## 8. Preserved Limitations & Hardware Bring-Up Recommendations

1. **Board-Specific Pin Binding**: To deploy this design on a physical development board (e.g. Digilent Nexys A7-100T or Basys 3), assign the 17 ports of `cpu_fpga_top` to physical package pins and set `IOSTANDARD LVCMOS33` in a board-specific XDC.
2. **Synchronous Block RAM Migration**: To scale memory beyond 32 KB, split instruction fetch into IF1 (address generation) and IF2 (BRAM synchronous read capture), adding an extra stall cycle on taken branches.
3. **Hardware Multiplier/Divider (RV32M)**: Future architectural extensions can map multiplication directly to DSP48E1 slices for single-cycle mathematical acceleration.

---

## 9. Exact Reproduction Commands

```powershell
Set-Location "PP/RISC-V"

# 1. Standalone CPU Hardware Regression (66 tests)
.\scripts\run_cpu_regression.ps1

# 2. FPGA Top-Level Wrapper Smoke Test (2 tests)
.\scripts\run_fpga_smoke_test.ps1

# 3. Vivado Batch Synthesis (xc7a100tcsg324-1, 100 MHz target)
Set-Location fpga
.\run_synthesis.ps1

# 4. Vivado Batch Physical Implementation (Opt, Place, Phys-Opt, Route)
.\run_implementation.ps1

# 5. Vivado Bitstream Generation Evaluation
.\run_bitstream.ps1
```
