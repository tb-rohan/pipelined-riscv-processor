# Standalone RV32I Processor: Final Verification & Test Execution Report

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Executive Test Summary

| Metric | Measured Value |
| :--- | :--- |
| **Total Test Cases** | **69** |
| **Passing Test Cases** | **69** |
| **Failing Test Cases** | **0** |
| **Overall Pass Rate** | **100.0%** |
| **Simulation Toolchain** | Icarus Verilog (`iverilog` / `vvp` v12.0) & Python 3.13.11 |
| **Architectural Model** | Dual-model comparison against independent Python reference |
| **Test Suites Covered** | Directed Arithmetic, Full 37-Instr ISA, 50 Random Ops, FPGA Wrapper, Boot Firmware |

---

## 2. Complete Test Execution Results Table

### 2.1 Directed Arithmetic, Logic & Corner-Case Suite (15 Tests)

| # | Test Name | Category | Inputs / Command | Expected Output | Measured Output | Cycles | Status |
| :-: | :--- | :---: | :---: | :---: | :---: | :-: | :---: |
| 1 | Addition | Arithmetic | $25 + 17$ | `42` | `42` | 18 | **PASS** |
| 2 | Subtraction | Arithmetic | $-15 - 8$ | `-23` | `-23` | 20 | **PASS** |
| 3 | Multiplication (Positive) | Software Subroutine | $15 \times 20$ | `300` | `300` | 477 | **PASS** |
| 4 | Multiplication (Negative) | Software Subroutine | $-7 \times 9$ | `-63` | `-63` | 483 | **PASS** |
| 5 | Division & Remainder | Software Subroutine | $100 / 7$ | $Q=14, R=2$ | $Q=14, R=2$ | 429 | **PASS** |
| 6 | Division by Zero | Corner Case Trap | $42 / 0$ | $Q=-1, R=42$ | $Q=-1, R=42$ | 26 | **PASS** |
| 7 | Signed Overflow Division | Corner Case Trap | $\text{INT\_MIN} / -1$ | $\text{INT\_MIN}, R=0$ | $\text{INT\_MIN}, R=0$ | 33 | **PASS** |
| 8 | Bitwise AND | Logic | `0x0F0F & 0xFF00` | `3840` (`0x0F00`) | `3840` (`0x0F00`) | 26 | **PASS** |
| 9 | Bitwise OR | Logic | `0x0F0F \| 0xF0F0`| `65535` (`0xFFFF`)| `65535` (`0xFFFF`)| 28 | **PASS** |
| 10 | Bitwise XOR | Logic | `12 ^ 10` | `6` | `6` | 30 | **PASS** |
| 11 | Bitwise NOT | Logic | `~0` | `-1` | `-1` | 32 | **PASS** |
| 12 | Shift Left Logical (`SLL`) | Barrel Shifter | `1 << 4` | `16` | `16` | 34 | **PASS** |
| 13 | Shift Right Logical (`SRL`) | Barrel Shifter | `64 >> 3` | `8` | `8` | 36 | **PASS** |
| 14 | Shift Right Arithmetic (`SRA`)| Barrel Shifter | `-64 >>> 2` | `-16` | `-16` | 38 | **PASS** |
| 15 | Signed Comparison (`SLT`) | Comparator | `-5 < 5` | `1` | `1` | 40 | **PASS** |

---

### 2.2 Full 37-Instruction RV32I Hardware ISA Self-Test Suite (1 Test / 37 Instructions)

Executed via `interactive_cpu.s` test case 14 (`CMD=14`). This suite executes 37 sequential assembly checks in hardware, exercising every unprivileged RV32I instruction:

| Instruction | Category | Test Operation | Expected Value | Hardware Result | Status |
| :--- | :--- | :--- | :---: | :---: | :---: |
| `ADD` | R-Type Arithmetic | $10 + 20$ | 30 | 30 | **PASS** |
| `SUB` | R-Type Arithmetic | $20 - 10$ | 10 | 10 | **PASS** |
| `SLL` | R-Type Shift | $1 \ll 4$ | 16 | 16 | **PASS** |
| `SLT` | R-Type Compare | $-5 < 5$ | 1 | 1 | **PASS** |
| `SLTU` | R-Type Compare | $5 < 10$ (unsigned) | 1 | 1 | **PASS** |
| `XOR` | R-Type Logic | `0xFF ^ 0x0F` | `0xF0` | `0xF0` | **PASS** |
| `SRL` | R-Type Shift | `0x80 >> 2` | `0x20` | `0x20` | **PASS** |
| `SRA` | R-Type Shift | `-16 >>> 2` | `-4` | `-4` | **PASS** |
| `OR` | R-Type Logic | `0xF0 \| 0x0F` | `0xFF` | `0xFF` | **PASS** |
| `AND` | R-Type Logic | `0xFF & 0x0F` | `0x0F` | `0x0F` | **PASS** |
| `ADDI` | I-Type Arithmetic | $10 + 5$ | 15 | 15 | **PASS** |
| `SLTI` | I-Type Compare | $-10 < 0$ | 1 | 1 | **PASS** |
| `SLTIU` | I-Type Compare | $5 < 10$ (unsigned) | 1 | 1 | **PASS** |
| `XORI` | I-Type Logic | `0x55 ^ 0xFF` | `0xAA` | `0xAA` | **PASS** |
| `ORI` | I-Type Logic | `0x50 \| 0x0A` | `0x5A` | `0x5A` | **PASS** |
| `ANDI` | I-Type Logic | `0xFF & 0x33` | `0x33` | `0x33` | **PASS** |
| `SLLI` | I-Type Shift | $2 \ll 3$ | 16 | 16 | **PASS** |
| `SRLI` | I-Type Shift | $32 \gg 3$ | 4 | 4 | **PASS** |
| `SRAI` | I-Type Shift | $-32 \ggg 3$ | -4 | -4 | **PASS** |
| `SW`/`LW` | Memory Access | Word store and load | `0x12345678` | `0x12345678` | **PASS** |
| `SH`/`LH` | Memory Access | Halfword store and signed load | `-30020` | `-30020` | **PASS** |
| `LHU` | Memory Access | Halfword store and unsigned load | `35516` | `35516` | **PASS** |
| `SB`/`LB` | Memory Access | Byte store and signed load | `-2` | `-2` | **PASS** |
| `LBU` | Memory Access | Byte store and unsigned load | `254` | `254` | **PASS** |
| `BEQ` | Branch | Branch taken and untaken paths | Correct PC | Correct PC | **PASS** |
| `BNE` | Branch | Branch taken and untaken paths | Correct PC | Correct PC | **PASS** |
| `BLT` | Branch | Signed less-than branch | Correct PC | Correct PC | **PASS** |
| `BGE` | Branch | Signed greater-than branch | Correct PC | Correct PC | **PASS** |
| `BLTU` | Branch | Unsigned less-than branch | Correct PC | Correct PC | **PASS** |
| `BGEU` | Branch | Unsigned greater-than branch | Correct PC | Correct PC | **PASS** |
| `LUI` | Upper Immediate | Load upper 20 bits | `0x12345000` | `0x12345000` | **PASS** |
| `AUIPC` | Upper Immediate | Add upper immediate to PC | $PC + \text{imm}$ | $PC + \text{imm}$ | **PASS** |
| `JAL` | Jump & Link | Unconditional direct jump | Link $PC+4$ | Link $PC+4$ | **PASS** |
| `JALR` | Jump & Link Reg | Indirect jump through register | Link $PC+4$ | Link $PC+4$ | **PASS** |
| `FENCE` | System / Memory | Instruction memory fence | No trap | No trap | **PASS** |
| `ECALL` | System / Trap | Environment call instruction | No trap | No trap | **PASS** |
| `EBREAK`| System / Trap | Breakpoint trap instruction | No trap | No trap | **PASS** |

- **Execution Latency**: **249 clock cycles** (2.49 µs at 100 MHz).
- **Status Word**: `0x50415353` ("PASS").
- **Final Result**: `37` (matching count of verified instructions).

---

### 2.3 Constrained-Randomized Stress Suite (50 Tests)

Generated via `scripts/run_interactive_cpu.py --random --count 50 --seed 42`:
- **Operand Generation Methodology**:
  - 40% Corner-case biased values: `0`, `1`, `-1`, `31`, `32`, `INT_MIN` (`-2147483648`), `INT_MAX` (`2147483647`), `0x55555555`, `0xAAAAAAAA`, `0xFFFFFFFF`.
  - 60% Uniformly distributed pseudo-random 32-bit signed integers.
- **Verification Rule**: Every hardware simulation output is verified against the independent Python reference model `python_reference()`.
- **Summary**: **50 / 50 operations passed with 0 mismatches**.

---

### 2.4 Synthesizable FPGA Top Wrapper Suite (2 Tests)

Simulated via `tb/cpu/tb_cpu_fpga_top.sv`:

| Test Name | Trigger Mechanism | Target Operation | Duration | Output Verification | Status |
| :--- | :--- | :--- | :---: | :--- | :---: |
| **Mode 00 (POST)** | Power-On Reset Deassertion | Full 37-Instr ISA Suite | 303 cycles | `led=37`, `led_pass=1`, `led_done=1`, `led_fail=0` | **PASS** |
| **Mode 01 (Add)** | Push-Button Pulse (`btn_trigger`) | Addition ($25 + 17$) | 37 cycles | `led=42`, `led_pass=1`, `led_done=1`, `led_fail=0` | **PASS** |

---

### 2.5 Autonomous Standalone Boot Firmware (1 Test)

| Metric | Measured Value |
| :--- | :--- |
| **Firmware Source** | `software/asm/standalone_boot.s` (62 instructions) |
| **Binary Output** | `software/asm/standalone_boot.hex` |
| **Workload** | Autonomous register init, arithmetic, loops, memory stores, $\sum_{i=1}^{10} i = 55$ |
| **Cycle Latency** | **88 clock cycles** |
| **Verification Status** | `HOST_RESULT = 55`, `HOST_STATUS = 0x50415353` ("PASS") |
| **Result** | **PASS** |

---

## 3. Reproduction Commands

```powershell
Set-Location "PP/RISC-V"

# 1. Run 66 Standalone CPU Tests
.\scripts\run_cpu_regression.ps1

# 2. Run FPGA Top-Level Wrapper Smoke Test
.\scripts\run_fpga_smoke_test.ps1
```
