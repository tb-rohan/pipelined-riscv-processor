# FPGA Synthesis & Implementation Guide: Standalone RV32I Processor

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

This directory contains the automated AMD/Xilinx Vivado synthesis and physical implementation flow for the **Standalone RV32I 5-Stage Pipelined Processor** (`cpu_fpga_top`) targeting the **Artix-7 100T FPGA (`xc7a100tcsg324-1`)**.

---

## 1. Directory Structure

```text
RISC-V/fpga/
├── constraints/
│   └── clock.xdc                  # 100 MHz clock constraint, CFGBVS & CONFIG_VOLTAGE properties
├── scripts/
│   ├── run_synthesis.tcl          # Batch non-project synthesis script for cpu_fpga_top
│   ├── run_implementation.tcl    # Batch non-project implementation script (opt, place, phys-opt, route)
│   └── run_bitstream.tcl         # Bitstream evaluation script with unconstrained pin DRC handling
├── checkpoints/
│   ├── post_synth.dcp             # Synthesized design checkpoint (828 KB)
│   ├── post_place.dcp             # Placed design checkpoint (2.33 MB)
│   ├── post_route.dcp             # Fully routed design checkpoint (2.89 MB)
│   └── cpu_fpga_top.bit           # Evaluated bitstream file (3,825,992 bytes)
├── reports/
│   ├── synth_utilization.rpt      # Synthesis resource utilization (LUTs, FFs, BRAM, DSP)
│   ├── synth_utilization_hierarchical.rpt # Submodule area breakdown
│   ├── synth_timing_summary.rpt   # Synthesis timing closure report
│   ├── synth_timing_max_paths.rpt # Critical timing paths report
│   ├── synth_drc.rpt              # Synthesis design rule check
│   ├── synth_latches.rpt          # Latch audit report (0 inferred latches)
│   ├── post_route_utilization.rpt # Post-implementation resource utilization
│   ├── post_route_timing_summary.rpt # Signoff post-route timing report
│   ├── post_route_timing_max_paths.rpt # Post-route critical paths
│   ├── post_route_status.rpt      # Net routing completion status (100% routed)
│   └── post_route_drc.rpt         # Post-route design rule check
├── run_synthesis.ps1              # Automated PowerShell synthesis runner
├── run_synthesis.bat              # Batch runner wrapper
├── run_implementation.ps1         # Automated PowerShell physical implementation runner
└── run_bitstream.ps1              # Automated PowerShell bitstream evaluation runner
```

---

## 2. Top-Level Design: `cpu_fpga_top`

The standalone FPGA implementation uses `rtl/soc/cpu_fpga_top.sv` as the top-level module:
- **Pin Reduction**: Eliminates the 291 simulation/debug ports of `cpu_standalone_top`, exposing exactly **17 physical I/O pins**.
- **Reset Hardening**: Incorporates a 2-stage flip-flop synchronizer (`sync_rst_n`) to prevent metastability from asynchronous reset buttons.
- **Visual Heartbeat**: Integrates a 26-bit counter providing a steady ~1.5 Hz toggle on `led_heartbeat` to confirm active clocking on hardware.
- **Autonomous POST Controller**: Automatically asserts `host_req` with `cmd=14` upon reset release, executing all 37 RV32I ISA self-tests and asserting `led_done` and `led_pass` when complete.
- **Interactive Mode Switching**: Supports push-button re-triggering (`btn_trigger`) and arithmetic mode selection (`sw_mode[1:0]` for ISA test, addition, multiplication, or division).

---

## 3. Measured Hardware Results

All measurements are extracted from fresh tool runs executed on **AMD/Xilinx Vivado v2026.1 (64-bit)**:

| Implementation Metric | Synthesis Run | Post-Route Implementation | Target Device Capacity (`xc7a100tcsg324-1`) | Device Utilization |
| :--- | :---: | :---: | :---: | :---: |
| **Top-Level Module** | `cpu_fpga_top` | `cpu_fpga_top` | — | — |
| **Target Clock Constraint** | 100.0 MHz (10.0 ns) | 100.0 MHz (10.0 ns) | — | — |
| **Status** | **Passed (0 Errors)** | **Passed (0 Errors)** | — | — |
| **Slice LUTs** | 4,863 | **4,834** | 63,400 | **7.62 %** |
| ├── LUT as Logic | 2,571 | **2,542** | 63,400 | **4.01 %** |
| └── LUT as Distributed RAM | 2,292 | **2,292** | 19,000 | **12.06 %** |
| **Slice Registers (FFs)** | 2,177 | **2,051** | 126,800 | **1.62 %** |
| **Block RAM (BRAM)** | 0 | **0** | 135 Tiles | **0.00 %** |
| **DSP48E1 Slices** | 0 | **0** | 240 | **0.00 %** |
| **Bonded IOBs** | 17 | **17** | 210 | **8.10 %** |
| **Global Clock Buffers (BUFG)**| 1 | **1** | 32 | **3.13 %** |
| **Worst Negative Slack (WNS)** | **+0.787 ns** | **+0.178 ns** | — | **TIMING MET** |
| **Total Negative Slack (TNS)** | **0.000 ns** | **0.000 ns** | — | **TIMING MET** |
| **Worst Hold Slack (WHS)** | **+0.131 ns** | **+0.159 ns** | — | **TIMING MET** |
| **Total Hold Slack (THS)** | **0.000 ns** | **0.000 ns** | — | **TIMING MET** |
| **Maximum Operating Frequency**| — | **101.81 MHz** | — | — |
| **Net Routing Completion** | — | **100% (4,956/4,956)** | — | **0 Errors** |

---

## 4. Bitstream Generation Evaluation

- **Evaluation Script**: `fpga/scripts/run_bitstream.tcl` executed via `fpga/run_bitstream.ps1`.
- **DRC Rules**: Standard Vivado DRC flags `[DRC NSTD-1]` and `[DRC UCIO-1]` when physical pin location constraints (`LOC`) and I/O standards (`IOSTANDARD`) are omitted for a board-agnostic chip model.
- **Software Signoff**: Applying documented DRC severity downgrades for software model verification:
  ```tcl
  set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
  set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
  write_bitstream -force cpu_fpga_top.bit
  ```
- **Generated File**: `fpga/checkpoints/cpu_fpga_top.bit` (**3,825,992 bytes**).
- **Physical Programming**: Not performed because no physical hardware board is owned or used.

---

## 5. Automated Execution Commands

Execute the following commands from PowerShell in `PP/RISC-V/fpga`:

```powershell
Set-Location "PP/RISC-V/fpga"

# 1. Run Vivado Synthesis
.\run_synthesis.ps1

# 2. Run Physical Implementation (Opt, Place, Phys-Opt, Route)
.\run_implementation.ps1

# 3. Run Bitstream Generation Evaluation
.\run_bitstream.ps1
```
