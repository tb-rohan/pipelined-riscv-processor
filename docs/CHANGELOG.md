# Engineering Changelog: RV32I Processor & FPGA Implementation

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## [Release 3.0.0] - Standalone FPGA Implementation & Physical Timing Signoff

### Summary
- **Physical FPGA Wrapper (`cpu_fpga_top.sv`)**:
  - Implemented top-level wrapper reducing external physical ports from 291 simulation signals to **17 physical pins**, resolving Vivado DRC `IOCNT-1`.
  - Added 2-stage D flip-flop asynchronous reset synchronizer (`sync_rst_n`) to eliminate push-button metastability.
  - Implemented 26-bit clock divider driving `led_heartbeat` (~1.5 Hz toggle) for visual clock verification.
  - Built autonomous power-on self-test (POST) controller executing the full 37-instruction ISA suite upon reset release.
  - Added push-button trigger debounce and 4-way mode select switches (`sw_mode[1:0]`).
- **Autonomous Boot Firmware (`software/asm/standalone_boot.s`)**:
  - Developed self-contained 62-instruction assembly boot program exercising arithmetic, branches, loops, and memory accesses.
  - Verified in simulation: executes in 88 cycles, computing triangle number $\sum_{i=1}^{10} i = 55$ and writing `0x50415353` ("PASS") to status.
- **Physical Synthesis & Implementation (AMD Vivado 2026.1)**:
  - Fixed relative path handling in `fpga/scripts/run_synthesis.tcl` via `-generic IMEM_INIT_FILE=$HEX_PATH`.
  - Updated `fpga/constraints/clock.xdc` with `CFGBVS VCCO` and `CONFIG_VOLTAGE 3.3` to resolve DRC `CFGBVS-1`.
  - Created automated implementation script `fpga/scripts/run_implementation.tcl` (`opt_design`, `place_design`, `phys_opt_design`, `route_design`).
  - Achieved full timing signoff on Artix-7 `xc7a100tcsg324-1` at 100.00 MHz:
    - Post-Route WNS: **+0.178 ns**, TNS: **0.000 ns** ($F_{max} = 101.81$ MHz).
    - Post-Route WHS: **+0.159 ns**, THS: **0.000 ns**.
    - Routing: 100% completed (4,956 / 4,956 nets, 0 errors).
    - Resource Utilization: 4,834 Slice LUTs (7.62%), 2,051 Slice Registers (1.62%), 0 BRAMs, 0 DSPs.
- **Bitstream Generation Evaluation**:
  - Created `fpga/scripts/run_bitstream.tcl` and `fpga/run_bitstream.ps1`.
  - Evaluated bitstream generation on `post_route.dcp` with documented board-agnostic DRC overrides.
  - Successfully generated `fpga/checkpoints/cpu_fpga_top.bit` (3,825,992 bytes).
- **Verification & Automation Tooling**:
  - Created `scripts/run_cpu_regression.ps1` (66 standalone CPU tests).
  - Created `scripts/run_fpga_smoke_test.ps1` (`tb/cpu/tb_cpu_fpga_top.sv` smoke test).
  - Patched `scripts/run_all_regressions.py` with automatic recompilation via `ensure_compiled()`, preventing stale binary execution.
  - Created `.gitignore` ignoring temporary compilation, telemetry, and waveform artifacts.

---

## [Release 2.0.0] - Comprehensive Core Audit & Microarchitecture Upgrades

### Summary
- Multi-cycle bus stall hazard bug resolved in `hazard_unit.sv` and `pipe_reg_mem_wb.sv`.
- Added 64-bit cycle counter and microarchitectural hardware performance monitoring unit (HPMU) in `timer.sv`.
- Added Capability register (`0x01040408`) and 16-bit transaction watchdog timer in `accel_adapter.sv`.
- Full RV32I base integer 37-instruction hardware verification suite implemented in CPU firmware datapath (`interactive_cpu.s`).
- Unified timescales to `` `timescale 1ns/1ps `` across all RTL source files.
- Wrapped non-synthesizable simulation tasks in `uart_lite.sv` with `` `ifndef SYNTHESIS ``.
- Verified generic synthesis: 0 latches, 0 DRC violations.
- Verified 100% regression pass rate across all simulation suites.

---

### Detailed Microarchitectural Changes

#### 1. Core Microarchitecture (`RISC-V/rtl/core/`)
- **`hazard_unit.sv`**:
  - Added input `dmem_stall`.
  - Implemented `flush_mem_wb = dmem_stall` to inject a bubble into the WB stage during bus wait-states, eliminating duplicate instruction retirement.
  - Asserted `stall_ex_mem = dmem_stall` to freeze the active memory transaction address and data in place.
  - Connected microarchitectural event ticks: `stall_load_use_o` and `flush_branch_o`.
- **`pipe_reg_mem_wb.sv`**:
  - Added synchronous `flush` input port.
  - Clears `reg_write`, `wb_src`, and data signals to 0 when `flush` is asserted.
- **`rv32i_core.sv`**:
  - Connected `hazard_unit` signals `flush_mem_wb` to `pipe_reg_mem_wb`.
  - Routed event signals (`instret_tick`, `load_use_stall_tick`, `branch_flush_tick`, `bus_stall_tick`) to core top level.
- **`riscv_pkg.sv`**:
  - Standardized timescale to `` `timescale 1ns/1ps ``.
- **`alu.sv`, `regfile.sv`, `imm_gen.sv`, `decoder.sv`, `branch_unit.sv`, `forwarding_unit.sv`, `load_store_unit.sv`, `pipe_reg_*.sv`**:
  - Unified timescales, preserved logic, and verified clean synthesis.

#### 2. Peripherals & Interconnect (`RISC-V/rtl/peripherals/`, `interconnect/`)
- **`timer.sv`**:
  - Expanded peripheral from basic timer to full Hardware Performance Monitoring Unit (HPMU).
  - Added 64-bit cycle counter (`CYCLES_LO/HI` at `0x8000_0020/24`).
  - Added event counters: `INSTRET` (`0x8000_0028`), `LOAD_USE_STALLS` (`0x8000_002C`), `BRANCH_FLUSHES` (`0x8000_0030`), and `BUS_STALLS` (`0x8000_0034`).
- **`uart_lite.sv`**:
  - Guarded `$write` and `$fflush` with `` `ifndef SYNTHESIS `` to eliminate synthesis lint warnings.
- **`bus_interconnect.sv`**:
  - Maintained memory map decoding; preserved peripheral interconnect.

#### 3. Top-Level Physical Integration (`RISC-V/rtl/soc/`)
- **`cpu_fpga_top.sv`**:
  - Created top-level module with pin reduction (17 pins), reset synchronizer, autonomous POST FSM, and LED status indicators.
