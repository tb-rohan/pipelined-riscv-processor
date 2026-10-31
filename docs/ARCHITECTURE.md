# System Architecture: Standalone 5-Stage Pipelined RV32I Processor

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

---

## 1. Top-Level System Architecture

The standalone processor subsystem comprises the 5-stage pipelined integer core (`rv32i_core`), independent instruction and data memories (`imem` and `dmem`), memory-mapped peripheral subsystems, and an FPGA-ready physical wrapper (`cpu_fpga_top`):

```text
       +--------------------------------------------------------------------------------+
       |                               cpu_fpga_top                                     |
       |  [clk]   [rst_n]   [btn_trigger]   [sw_mode[1:0]]                              |
       |    |        |             |               |                                    |
       |    +--------+-------------+---------------+                                    |
       |    |                      |               |                                    |
       |    v                      v               v                                    |
       |  [Reset Sync]     [Heartbeat LED]   [Autonomous POST]                          |
       |    | (sync_rst_n)         | (1.5 Hz)      | (cmd=14)                           |
       |    +----------------------+---------------+                                    |
       |                           |                                                    |
       |                           v                                                    |
       |  +--------------------------------------------------------------------------+  |
       |  |                    cpu_standalone_top                                    |  |
       |  |                                                                          |  |
       |  |  +-----------------------+              +-----------------------------+  |  |
       |  |  |      rv32i_core       |  Instruction |         imem (16KB)         |  |  |
       |  |  |                       | <----------  | (0x0000_0000 - 0x0000_3FFF) |  |  |
       |  |  |  - 5-Stage In-Order   |              +-----------------------------+  |  |
       |  |  |  - Full Forwarding    |                                               |  |
       |  |  |  - Hazard Detection   |  Data Bus    +-----------------------------+  |  |
       |  |  |  - Load/Store Unit    | <----------> |      bus_interconnect       |  |  |
       |  |  |  - Performance Monitor|              +--------------+--------------+  |  |
       |  |  +-----------------------+                             |                 |  |
       |  |                                                        |                 |  |
       |  |         +----------------------------------------------+                 |  |
       |  |         |                       |                      |                 |  |
       |  |         v                       v                      v                 |  |
       |  |  +--------------+      +------------------+   +-----------------+        |  |
       |  |  | dmem (16KB)  |      |  host_interface  |   |   timer (HPMU)  |        |  |
       |  |  | (0x0000_4000 |      |  (0x8000_0000 .. |   |  (0x8000_0020 ..|        |  |
       |  |  |  0x0000_7FFF)|      |   0x8000_001F)   |   |   0x8000_003F)  |        |  |
       |  |  +--------------+      +------------------+   +-----------------+        |  |
       |  +--------------------------------------------------------------------------+  |
       |                           |                                                    |
       |                           v                                                    |
       |  [led[7:0]]   [led_done]   [led_pass]   [led_fail]   [led_heartbeat]           |
       +--------------------------------------------------------------------------------+
```

---

## 2. RV32I Processor Core Microarchitecture

The processor implements the standard unprivileged 32-bit RISC-V integer base instruction set (RV32I) using a classic 5-stage in-order pipeline:

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

### 2.1 Pipeline Stages

1. **Instruction Fetch (IF)**:
   - Maintains the 32-bit Program Counter (`pc_q`).
   - Fetches instructions combinationally from 16 KB `imem`, latching the instruction and $PC+4$ into `pipe_reg_if_id` on the rising clock edge.
   - Computes sequential $PC + 4$ or latches branch/jump target addresses from the EX stage.
2. **Instruction Decode & Register Read (ID)**:
   - Decodes opcode, register indices (`rs1`, `rs2`, `rd`), immediate fields, and instruction types.
   - Accesses dual combinational read ports of the 32-word register file (`regfile.sv`). Register `x0` is hardwired to zero.
   - Generates sign-extended 32-bit immediates via `imm_gen.sv` supporting I, S, B, U, and J formats.
3. **Execution & Address Calculation (EX)**:
   - 32-bit Arithmetic Logic Unit (`alu.sv`) computes arithmetic (ADD, SUB), logical (AND, OR, XOR), shifts (SLL, SRL, SRA), and comparisons (SLT, SLTU).
   - Branch comparator (`branch_unit.sv`) evaluates branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU) and jump target addresses (JAL, JALR).
   - Multiplexers driven by `forwarding_unit.sv` select between register operands and forwarded values from EX/MEM and MEM/WB.
4. **Memory Access (MEM)**:
   - Load/Store Unit (`load_store_unit.sv`) formats memory write strobes and extracts load data.
   - Supports signed/unsigned byte (LB, LBU), halfword (LH, LHU), and 32-bit word (LW, SW).
   - Synchronous memory wait-state stalls (`dmem_stall`) are handled when accessing peripherals.
5. **Register Writeback (WB)**:
   - Multiplexes the destination register data from ALU result, memory read data, $PC + 4$ link address, or upper immediate.
   - Commits write data to `regfile` on the rising clock edge when `reg_write` is active and $rd \neq 0$.

---

## 3. Hazard Resolution & Forwarding Network

### 3.1 Data Forwarding Network (`forwarding_unit.sv`)
To minimize Read-After-Write (RAW) pipeline stalls, the forwarding unit routes values directly to the ALU inputs in the EX stage:
- **Priority 1 (EX/MEM Forwarding)**: If the instruction currently in the MEM stage is writing to a register ($rd \neq 0$) that matches the EX stage source register (`rs1` or `rs2`), data is forwarded directly from the MEM stage ALU output (`mem_fwd_data`).
- **Priority 2 (MEM/WB Forwarding)**: If the instruction in the WB stage is writing to a register ($rd \neq 0$) that matches the EX stage source register (and was not forwarded by EX/MEM), data is forwarded from the WB stage commit value (`wb_final_data`).
- **Default**: In the absence of data dependencies, operands are sourced directly from the register file.

### 3.2 Hazard Detection Unit (`hazard_unit.sv`)
- **Load-Use Data Hazard**:
  When an instruction in ID depends on the result of a load instruction currently in EX (`mem_read_ex == 1` and `rd_ex == rs1_id || rd_ex == rs2_id`):
  1. Freezes Program Counter (`stall_pc = 1`) and IF/ID stage (`stall_if_id = 1`) for 1 clock cycle.
  2. Inserts a bubble (NOP: `addi x0, x0, 0`) into ID/EX (`flush_id_ex = 1`).
  3. In the subsequent cycle, the load advances to MEM/WB, allowing normal MEM/WB forwarding into EX.
- **Control Hazards (Branches & Jumps)**:
  Branches and jumps are evaluated in the EX stage. When a branch is taken or a jump occurs:
  1. PC is updated with the branch/jump target.
  2. Both speculative instructions currently in flight are flushed: `flush_if_id = 1` and `flush_id_ex = 1`.
  3. The branch penalty is **exactly 2 clock cycles**.
- **Bus Wait-State Stalls**:
  During multi-cycle bus transactions (`dmem_stall == 1`):
  1. Stalls `pc`, `if_id`, `id_ex`, and `ex_mem`.
  2. Asserts `flush_mem_wb = dmem_stall` to inject a bubble into the WB stage, preventing duplicate instruction retirement.

---

## 4. Memory Architecture & Physical Implementation

### 4.1 Memory Map Summary

| Address Region | Range | Device | Size | Semantics |
| :--- | :--- | :--- | :---: | :--- |
| **Instruction Memory** | `0x0000_0000 - 0x0000_3FFF` | `imem` | 16 KB | Combinational read, synchronous write |
| **Data Memory** | `0x0000_4000 - 0x0000_7FFF` | `dmem` | 16 KB | Combinational read, byte-strobe write |
| **Host Control** | `0x8000_0000 - 0x8000_001F` | `host_interface` | 32 B | Command dispatch & status |
| **Timer / HPMU** | `0x8000_0020 - 0x8000_003F` | `timer` | 32 B | 64-bit cycle counter & event monitors |
| **UART Lite** | `0x8000_0040 - 0x8000_005F` | `uart_lite` | 32 B | Character transmission peripheral |

### 4.2 Distributed RAM Mapping Rationale
- The 5-stage pipeline requires single-cycle combinational reads from `imem` in IF and `dmem` in MEM.
- AMD 7-series Block RAMs (`RAMB36E1`) enforce a mandatory 1-cycle read latency (`always_ff @(posedge clk)`).
- Consequently, `imem` and `dmem` infer as **Distributed RAM (2,292 LUTs)**.
- Distributed RAM easily meets timing at 100 MHz (+0.178 ns WNS post-route) without requiring a pipeline redesign.

---

## 5. Physical Top-Level Wrapper (`cpu_fpga_top.sv`)

| Port Name | Direction | Width | Pin Count | Function |
| :--- | :---: | :---: | :---: | :--- |
| `clk` | Input | 1 | 1 | 100 MHz primary clock |
| `rst_n` | Input | 1 | 1 | Active-low reset push-button |
| `btn_trigger`| Input | 1 | 1 | Manual re-trigger push-button |
| `sw_mode` | Input | 2 | 2 | Operation mode switches (00: ISA, 01: Add, 10: Mul, 11: Div) |
| `led` | Output | 8 | 8 | 8-bit result visualization LEDs |
| `led_done` | Output | 1 | 1 | Execution complete indicator |
| `led_pass` | Output | 1 | 1 | Test pass indicator (`0x50415353`) |
| `led_fail` | Output | 1 | 1 | Test fail / timeout indicator |
| `led_heartbeat`| Output | 1 | 1 | 26-bit clock divider heartbeat indicator (~1.5 Hz) |
| **Total** | — | — | **17** | **8.1% of Artix-7 100T package pins (210 available)** |
