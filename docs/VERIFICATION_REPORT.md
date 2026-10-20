# Standalone RV32I Processor Verification & Regression Report

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Executive Summary

| Verification Metric | Result |
| :--- | :--- |
| **Total Tests Executed** | **69** |
| **Total Tests Passed** | **69** |
| **Total Tests Failed** | **0** |
| **Success Rate** | **100.0%** |
| **Simulation Toolchain** | Icarus Verilog (`iverilog` / `vvp` v12.0) & Python 3.13 |
| **Architectural Model** | Dual-model comparison against independent Python reference |
| **ISA Suite Coverage** | Complete 37/37 RV32I Base Integer Instructions |
| **FPGA Wrapper Coverage** | Reset synchronization, autonomous POST, mode switching, LED status |

---

## 2. Test Results Breakdown

### 2.1 Directed Arithmetic, Logic & Corner-Case Suite (15 Tests)

| # | Test Name | Type | Expected Result | Measured Result | Cycles | Status |
| :-: | :--- | :---: | :---: | :---: | :-: | :---: |
| 1 | Addition (`25 + 17`) | Directed | 42 | 42 | 18 | **PASS** |
| 2 | Subtraction (`-15 - 8`) | Directed | -23 | -23 | 20 | **PASS** |
| 3 | Multiplication (`15 * 20`) | Software Loop | 300 | 300 | 477 | **PASS** |
| 4 | Multiplication (`-7 * 9`) | Software Loop | -63 | -63 | 483 | **PASS** |
| 5 | Division (`100 / 7`) | Restoring Loop | Q: 14, R: 2 | Q: 14, R: 2 | 429 | **PASS** |
| 6 | Division by Zero (`42 / 0`) | Corner Case | Q: -1, R: 42 | Q: -1, R: 42 | 26 | **PASS** |
| 7 | Overflow Division (`INT_MIN / -1`) | Corner Case | INT_MIN | INT_MIN | 33 | **PASS** |
| 8 | Bitwise AND (`0xFF & 0x0F`) | Directed | 15 | 15 | 26 | **PASS** |
| 9 | Bitwise OR (`0xF0 \| 0x0F`) | Directed | 255 | 255 | 28 | **PASS** |
| 10 | Bitwise XOR (`12 ^ 10`) | Directed | 6 | 6 | 30 | **PASS** |
| 11 | Bitwise NOT (`~0`) | Directed | -1 | -1 | 32 | **PASS** |
| 12 | Shift Left Logical (`1 << 4`) | Barrel Shifter | 16 | 16 | 34 | **PASS** |
| 13 | Shift Right Logical (`64 >> 3`) | Barrel Shifter | 8 | 8 | 36 | **PASS** |
| 14 | Shift Right Arithmetic (`-64 >> 3`)| Barrel Shifter | -8 | -8 | 38 | **PASS** |
| 15 | Signed Comparison (`-5 < 5`) | Comparator | 1 | 1 | 40 | **PASS** |

### 2.2 Full 37-Instruction RV32I Hardware ISA Suite (1 Test / 37 Instructions)

| Suite | Instructions Tested | Cycles | Status Word | Result Word | Status |
| :--- | :---: | :-: | :---: | :---: | :---: |
| **`interactive_cpu.s` (CMD=14)** | **37 / 37** (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI, LB, LH, LW, LBU, LHU, SB, SH, SW, BEQ, BNE, BLT, BGE, BLTU, BGEU, JAL, JALR, LUI, AUIPC) | **249** | `0x50415353` ("PASS") | `37` | **PASS** |

### 2.3 Constrained-Randomized Arithmetic Stress Suite (50 Tests)

Generated via `scripts/run_interactive_cpu.py --random --count 50 --seed 42`:
- 40% Corner-case biased operands (`0`, `1`, `-1`, `INT_MIN`, `INT_MAX`, `0x55555555`, `0xAAAAAAAA`, etc.).
- 60% Uniform 32-bit random integers.
- All 50 operations matched the Python reference model with **0 mismatches**.

### 2.4 Synthesizable FPGA Top Wrapper Suite (2 Tests)

| Test Configuration | Trigger Mechanism | Target Operation | Duration | Output Verification | Status |
| :--- | :--- | :--- | :-: | :--- | :---: |
| **Mode 00 (POST)** | Power-On Reset Release | Full 37-Instr ISA Suite | 303 cycles | `led=37`, `led_pass=1`, `led_done=1` | **PASS** |
| **Mode 01 (Add)** | Push-Button Pulse (`btn_trigger`) | Addition (`25 + 17`) | 37 cycles | `led=42`, `led_pass=1`, `led_done=1` | **PASS** |

### 2.5 Autonomous Standalone Boot Firmware (1 Test)

| Program File | Source | Description | Cycles | Verification | Status |
| :--- | :--- | :--- | :-: | :--- | :---: |
| `standalone_boot.hex` | `software/asm/standalone_boot.s` | Autonomous 62-instruction boot program calculating $\sum_{i=1}^{10} i = 55$ | 88 | `HOST_RESULT = 55`, `HOST_STATUS = 0x50415353` | **PASS** |

---

## 3. Reproduction Commands

To reproduce the complete verification suite from scratch:

```powershell
Set-Location "PP/RISC-V"

# 1. Standalone CPU Regression (66 Tests)
.\scripts\run_cpu_regression.ps1

# 2. FPGA Top Wrapper Smoke Test (2 Tests)
.\scripts\run_fpga_smoke_test.ps1
```
