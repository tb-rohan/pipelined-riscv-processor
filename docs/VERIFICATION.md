# Verification Methodology & Validation Results: Standalone RV32I Processor

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

This document details the verification methodology, testbench architecture, golden reference model comparisons, and regression test results for the **Standalone RV32I Processor**.

---

## 1. Verification Strategy Overview

Verification is organized into four complementary layers:
1. **Architectural Reference Modeling**: An independent Python golden reference model (`python_reference()` in `run_interactive_cpu.py`) emulates all 32-bit integer arithmetic, bitwise, shift, comparison, multiplication, and division operations with exact two's-complement wrap-around and signed arithmetic.
2. **Directed Corner-Case Verification**: Comprehensive test cases targeting specific microarchitectural hazards (load-use stalls, branch flushes, forwarding priority, division by zero, integer overflow).
3. **Full 37-Instruction RV32I Self-Test Suite**: An assembly-level architectural verification program (`do_isa_test` in `interactive_cpu.s`) exercising every base integer instruction defined in the RISC-V Unprivileged Specification.
4. **FPGA Wrapper Smoke Testing**: Direct simulation of the synthesizable top-level wrapper (`cpu_fpga_top.sv`), validating reset synchronization, autonomous power-on execution, push-button triggering, and LED status decoding.

---

## 2. Test Execution & Results Breakdown

All verification suites were re-executed on the fresh codebase with clean RTL compilation using Icarus Verilog v12.0 and Python 3.13.

### 2.1 Test Count Summary
| Test Suite | Environment | Test Methodology | Passed / Total | Status |
| :--- | :--- | :--- | :---: | :---: |
| **Directed Arithmetic & Logic** | `tb_cpu_interactive.sv` | Directed hardware simulation | **15 / 15** | **100% PASS** |
| **Full 37-Instruction ISA Suite**| `interactive_cpu.s` | Hardware self-test | **1 / 1** | **100% PASS** |
| **Randomized Golden Model Tests** | `run_interactive_cpu.py`| Constrained random (Seed: 42)| **50 / 50** | **100% PASS** |
| **FPGA Top Wrapper Smoke Test** | `tb_cpu_fpga_top.sv` | Top-level wrapper verification | **2 / 2** | **100% PASS** |
| **Autonomous Boot Firmware** | `standalone_boot.s` | Self-contained boot test | **1 / 1** | **100% PASS** |
| **Total Standalone CPU Tests** | — | — | **69 / 69** | **100% PASS** |

---

## 3. Detailed Test Descriptions

### 3.1 Directed Test Cases
- **Addition (`ADD`)**: Evaluates $25 + 17 = 42$. Verifies single-cycle ALU addition and register writeback.
- **Subtraction (`SUB`)**: Evaluates $-15 - 8 = -23$. Verifies negative two's-complement arithmetic.
- **Signed Multiplication (`MUL`)**: Evaluates $15 \times 20 = 300$ and $-7 \times 9 = -63$. Verifies signed 32-bit shift-and-add software subroutine.
- **Division (`DIV`/`REM`)**: Evaluates $100 / 7$, returning quotient $Q = 14$ and remainder $R = 2$.
- **Division Corner Cases**:
  - *Division by Zero*: Evaluates $42 / 0$, correctly returning $Q = -1$ and $R = 42$ in accordance with the RISC-V specification.
  - *Signed Overflow*: Evaluates $\text{INT\_MIN} / -1$ ($-2147483648 / -1$), returning $\text{INT\_MIN}$ without entering an infinite loop.
- **Bitwise Logic**:
  - `AND`: `0x0F0F & 0xFF00 = 0x0F00`
  - `OR`: `0x0F0F | 0xF0F0 = 0xFFFF`
  - `XOR`: `12 ^ 10 = 6`
- **Shifts & Comparisons**:
  - `SLL`: `1 << 4 = 16`
  - `SRL`: `64 >> 3 = 8`
  - `SRA`: `-64 >>> 2 = -16` (sign extension maintained)
  - `SLT`: `-5 < 5 = 1` (signed set-less-than)
  - `SLTU`: `5 < 10 = 1` (unsigned set-less-than)

### 3.2 Full 37-Instruction RV32I ISA Verification Suite
Case 14 of `interactive_cpu.s` executes 37 sequential checks verifying every base integer instruction:
1. `ADD`: $10 + 20 = 30$
2. `SUB`: $20 - 10 = 10$
3. `SLL`: $1 \ll 4 = 16$
4. `SLT`: $-5 < 5 = 1$
5. `SLTU`: $5 < 10 = 1$
6. `XOR`: `0xFF ^ 0x0F = 0xF0`
7. `SRL`: `0x80 >> 2 = 0x20`
8. `SRA`: `-16 >>> 2 = -4`
9. `OR`: `0xF0 | 0x0F = 0xFF`
10. `AND`: `0xFF & 0x0F = 0x0F`
11. `ADDI`: $10 + 5 = 15$
12. `SLTI`: $-10 < 0 = 1$
13. `SLTIU`: $5 < 10 = 1$
14. `XORI`: `0x55 ^ 0xFF = 0xAA`
15. `ORI`: `0x50 | 0x0A = 0x5A`
16. `ANDI`: `0xFF & 0x33 = 0x33`
17. `SLLI`: $2 \ll 3 = 16$
18. `SRLI`: $32 \gg 3 = 4$
19. `SRAI`: $-32 \ggg 3 = -4$
20. `SW`/`LW`: Full word store and load to DMEM (`0x12345678`)
21. `SH`/`LH`: Halfword store and signed load (`0x8ABC` -> `-30020`)
22. `LHU`: Halfword store and unsigned load (`0x8ABC`)
23. `SB`/`LB`: Byte store and signed load (`0xFE` -> `-2`)
24. `LBU`: Byte store and unsigned load (`0xFE`)
25. `BEQ`: Branch taken and untaken
26. `BNE`: Branch taken and untaken
27. `BLT`: Signed less-than branch
28. `BGE`: Signed greater-than branch
29. `BLTU`: Unsigned less-than branch
30. `BGEU`: Unsigned greater-than branch
31. `LUI`: Load upper immediate (`0x12345` -> `0x12345000`)
32. `AUIPC`: Add upper immediate to PC (verifies 4-byte alignment)
33. `JAL`: Unconditional jump and link
34. `JALR`: Indirect jump through register with alignment bit-clearing
35. `FENCE`: Pipeline memory ordering instruction
36. `ECALL`: Environment call trap instruction
37. `EBREAK`: Environment breakpoint instruction

**Result**: All 37 checks pass in 249 cycles, returning `CPU_RESULT_DEC = 37` and `CPU_RESULT_HI_HEX = 0x50415353` ("PASS").

### 3.3 Constrained-Randomized Testing
Using `scripts/run_interactive_cpu.py --random --count 50 --seed 42`:
- Operands are generated with a 40% bias toward corner cases (`0`, `1`, `-1`, `31`, `32`, `INT_MIN`, `INT_MAX`, `0x55555555`, `0xAAAAAAAA`, `0xFFFFFFFF`) and 60% uniform random 32-bit values.
- Shift amounts are masked to 5 bits (`0..31`).
- Results and status are compared against `python_reference()`.
- **Result**: 50 / 50 operations passed with 0 mismatches.

### 3.4 FPGA Top-Level Wrapper Smoke Test
`tb/cpu/tb_cpu_fpga_top.sv` simulates `cpu_fpga_top.sv`:
- **Mode 00**: On reset release, the autonomous controller triggers the 37-instruction ISA suite. Completes in 303 cycles with `led_done = 1`, `led_pass = 1`, `led = 37`.
- **Mode 01**: Button push triggers addition ($25 + 17$). Completes in 37 cycles with `led_done = 1`, `led_pass = 1`, `led = 42`.

---

## 4. How to Reproduce

Execute the regression scripts directly in PowerShell:

```powershell
Set-Location "PP/RISC-V"

# Run Standalone CPU Regression (Directed + ISA + 50 Random Tests)
.\scripts\run_cpu_regression.ps1

# Run FPGA Top-Level Wrapper Smoke Test
.\scripts\run_fpga_smoke_test.ps1
```
