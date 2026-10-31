# Standalone 5-Stage Pipelined RV32I Processor

> **Mandatory Hardware Disclaimer**  
> *This project was developed, synthesized, and verified using software-based cycle-accurate RTL simulation (Icarus Verilog v12.0) and industrial FPGA toolchain flows (AMD/Xilinx Vivado v2026.1 targeting Artix-7 `xc7a100tcsg324-1`). No physical FPGA development board was used for hardware testing.*

A synthesizable, 32-bit RISC-V (RV32I) 5-stage in-order pipelined processor core designed in SystemVerilog, verified with 67 directed and randomized testbenches against an independent Python architectural golden reference, and timing-closed at 100 MHz on AMD Artix-7 FPGA.

---

## 1. Architectural Highlights

- **Full RV32I Base Integer ISA Coverage:** Implements all 37 unprivileged integer instructions (R-type, I-type, S-type, B-type, U-type, and J-type).
- **Textbook 5-Stage In-Order Pipeline:** Decoupled `IF` (Fetch), `ID` (Decode), `EX` (Execute), `MEM` (Memory Access), and `WB` (Writeback) stages with registered pipeline boundaries.
- **Priority Data Forwarding Networks:** Resolves Read-After-Write (RAW) data hazards combinationally by bypassing results from EX/MEM (Priority 1) and MEM/WB (Priority 2) stages directly into EX ALU operands.
- **Automated Hazard Interlocks & Branch Resolution:**
  - **Load-Use Hazard Stall:** Automatically detects load-use dependencies, freezing PC and IF/ID stages while injecting a 1-cycle bubble into ID/EX.
  - **Branch / Jump Resolution:** Evaluates branch comparators and jump targets in EX, flushing IF/ID and ID/EX with an exact 2-cycle branch penalty.
  - **Multi-Cycle Bus Wait-State Interlock (`dmem_stall`):** Supports multi-cycle slaves by freezing PC, IF/ID, ID/EX, and EX/MEM while asserting `flush_mem_wb` to prevent duplicate instruction retirement in WB.
- **Integrated Memory-Mapped Subsystems:** Dual 16 KB Harvard memories (`imem` and `dmem`) with byte, halfword, and word access formatting (`LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW`), a 64-bit hardware cycle timer / HPMU, UART Lite character debug output, and host mailbox registers.
- **Software Math Runtime:** Emulated 32×32 signed shift-and-add multiplication and restoring integer division executing purely on the integer datapath without hardware multiplier/divider requirements.
- **FPGA Static Timing Closure:** Fully placed and routed at **100.00 MHz** on AMD Artix-7 with **+0.178 ns WNS**, **0.000 ns TNS**, and **0 inferred latches**.

---

## 2. Processor Pipeline Microarchitecture

```text
       +--------------------------------------------------------------------------------+
       |                               CORE PIPELINE                                    |
       |                                                                                |
       |  +-------+     +-------+     +-------+     +-------+     +-------+             |
       |  |  IF   | --> |  ID   | --> |  EX   | --> |  MEM  | --> |  WB   |             |
       |  | Stage |     | Stage |     | Stage |     | Stage |     | Stage |             |
       |  +-------+     +-------+     +-------+     +-------+     +-------+             |
       |      |             |             ^             |             |                 |
       |      |             |             |             |             |                 |
       |      |             |             +=============+=============+                 |
       |      |             |             EX/MEM & MEM/WB Forwarding                    |
       |      |             |                                                           |
       |      |             +---------> [ Hazard Unit ] ----------------+               |
       |      |                           (Load-Use Stalls,             |               |
       |      |                            Branch Flush,                v               |
       |      |                            dmem_stall)             PC Update            |
       |      v                                                         |               |
       |  [ IMEM ] (16 KB)                                              v               |
       |                                                     [ DMEM ] (16 KB)           |
       +--------------------------------------------------------------------------------+
                                           |
                              +------------+------------+
                              |                         |
                              v                         v
                       [ Host Mailbox ]          [ Timer / HPMU ]
                         (0x80000000)              (0x80000020)
```

### Pipeline Stage Details

1. **IF (Instruction Fetch):** Maintains Program Counter (`pc_q`), fetches instructions combinationally from 16 KB `imem`, and computes $PC+4$ or latches branch/jump target addresses from EX.
2. **ID (Instruction Decode):** Decodes 32-bit opcodes, immediate formats (I, S, B, U, J), and accesses dual-read register file (32 × 32-bit, `x0 = 0` hardwired).
3. **EX (Execute):** 32-bit ALU executing arithmetic (`ADD`, `SUB`), bitwise logic (`AND`, `OR`, `XOR`), comparisons (`SLT`, `SLTU`), and barrel shifting (`SLL`, `SRL`, `SRA`). Operands selected via forwarding muxes. Branch comparator evaluates conditions in EX.
4. **MEM (Memory Access):** Formats byte, halfword, and word reads/writes to DMEM and memory-mapped peripherals.
5. **WB (Writeback):** Multiplexes ALU result, memory read data, or PC+4 link target into the destination register `rd`.

---

## 3. Memory Map & Peripheral Interface

| Address Range | Size | Destination | Description |
| :--- | :---: | :--- | :--- |
| `0x0000_0000 - 0x0000_3FFF` | 16 KB | Instruction Memory (`imem`) | Program code storage |
| `0x0000_4000 - 0x0000_7FFF` | 16 KB | Data Memory (`dmem`) | Stack, heap, and static data |
| `0x8000_0000 - 0x8000_001F` | 32 B | Host Interface Mailbox | Command, operand, and status handshaking |
| `0x8000_0020 - 0x8000_003F` | 32 B | Hardware Timer / HPMU | 64-bit cycle counter and performance ticks |
| `0x8000_0040 - 0x8000_005F` | 32 B | UART Lite | Character transmission debug port |

---

## 4. FPGA Synthesis & Static Timing Closure

Implementation was targeted to the **AMD Artix-7 `xc7a100tcsg324-1`** using **Vivado 2026.1 (64-bit)** at a 100 MHz target constraint (10.00 ns period):

- **Target Clock:** 100.00 MHz (Period = 10.000 ns)
- **Worst Negative Slack (WNS):** **+0.178 ns (MET)** ($F_{\max} \approx 101.81\text{ MHz}$)
- **Total Negative Slack (TNS):** **0.000 ns** (0 failing endpoints)
- **Worst Hold Slack (WHS):** **+0.052 ns (MET)**
- **Resource Utilization:**
  - Slice LUTs: **4,834** (7.62% of 63,400)
  - LUT as Distributed RAM: **2,292** (12.06% of SLICEM capacity)
  - Slice Registers (FF): **2,051** (1.62% of 126,800)
  - Block RAM / DSP: **0 / 135 tiles (0.00%)**
  - Inferred Latches: **0 (Clean synchronous design)**

---

## 5. Verification & Testing

The CPU is verified via a 67-test automated regression suite comparing RTL outputs against an independent Python architectural simulator:

```powershell
# Run directed ISA tests
python scripts/run_interactive_cpu.py --directed

# Run full 37-instruction hardware compliance verification
python scripts/run_interactive_cpu.py --directed

# Run 50 randomized stress tests
python scripts/run_interactive_cpu.py --random --count 50 --seed 42
```

### Verification Matrix Summary

| Test Category | Tests | Status | Verification Mechanism |
| :--- | :---: | :---: | :--- |
| Directed Arithmetic & Logic | 16 | **PASS** | Directed corner cases (division by zero, overflow, shift-add multiplication) |
| Full RV32I ISA Verification | 37 | **PASS** | 37/37 instructions exercised with self-checking assertions |
| Constrained-Randomized Stress | 50 | **PASS** | Random instructions & operands matching Python reference bit-exact |
| **Total CPU Tests** | **67** | **100% PASS** | Zero mismatches |

---

## 6. Companion SoC System

This standalone processor core is designed to operate both independently and as the host CPU in the integrated **[riscv-int8-cnn-soc](https://github.com/tb-rohan/riscv-int8-cnn-soc)** repository, where it interfaces with a 4×4 weight-stationary INT8 CNN systolic array accelerator over memory-mapped AXI4-Lite and autonomous streaming DMA.
