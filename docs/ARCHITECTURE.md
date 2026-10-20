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

### 3.3 Bus Wait-State Stalls & Memory Interface Behavior (`dmem_stall`)

#### 1. Definition and Usage in RTL
The `dmem_stall` signal is implemented in the core pipeline and hazard control hierarchy as follows:
- **`hazard_unit.sv` (Lines 13, 36, 49–55):** `dmem_stall` is an active-high input port. When asserted:
  ```verilog
  if (dmem_stall) begin
    stall_pc     = 1'b1;
    stall_if_id  = 1'b1;
    stall_id_ex  = 1'b1;
    stall_ex_mem = 1'b1;
    stall_mem_wb = 1'b0;
    flush_mem_wb = 1'b1;
  end
  ```
  This control sequence freezes the Program Counter and the first four pipeline stages (`IF/ID`, `ID/EX`, and `EX/MEM`), while asserting `flush_mem_wb = 1` to inject a synchronous bubble (NOP) into the `MEM/WB` stage. This guarantees that instructions waiting on a bus access do not advance into Writeback prematurely or retire multiple times.
- **`rv32i_core.sv` (Lines 18, 396, 419):** Inputs `dmem_stall` from the external bus interface, drives `perf_bus_stall_tick` for performance counting, and connects directly to `hazard_unit`.
- **`bus_interconnect.sv` (Lines 10, 50, 128):** Connects to `cpu_stall`, where:
  ```verilog
  assign cpu_stall = (sel == SEL_ACCEL) ? accel_stall : 1'b0;
  ```

#### 2. Operational Status in Standalone CPU vs. Integrated SoC
- **In `cpu_standalone_top.sv`:** The core connects `dmem_stall` to `bus_interconnect.cpu_stall`. However, in the standalone configuration, all memory-mapped slaves (`imem`, `dmem`, `host_interface`, `timer`, `uart_lite`) respond combinationally within a single clock cycle. The accelerator port (`accel_stall`) is tied off to `1'b0` (`.accel_stall(1'b0)`).
- **Architectural Reality:** The pipeline stall and flush logic for `dmem_stall` is **fully implemented and verified in the core RTL**, but in the standalone processor build, `dmem_stall` is permanently de-asserted (`1'b0`) because all addressed slaves are single-cycle.
- **Purpose:** It serves as a pre-engineered hardware backpressure hook for heterogeneous integration (such as interfacing multi-cycle coprocessors or external bus controllers like AXI4-Lite/Wishbone).

#### 3. Single-Cycle vs. Wait-State vs. Variable-Latency Memory Interfaces
| Interface Characteristic | Single-Cycle Memory (Current Core) | Wait-State Memory (Supported via `dmem_stall`) | True Variable-Latency / Cache Miss |
| :--- | :--- | :--- | :--- |
| **Response Latency** | Strictly 1 clock cycle | Deterministic or bounded $N$ clock cycles | Dynamic and unbounded (1 to $100+$ cycles) |
| **Handshake Signals** | Request (`req`), Write Enable (`we`) | Request (`req`), Wait/Stall (`dmem_stall`) | Valid/Ready (`req`, `gnt`, `valid`, `ready`, `ack`) |
| **Pipeline Behavior** | Advances unconditionally every clock edge | Stalls IF, ID, EX, MEM; injects bubble into WB | Stalls pipeline, holds bus address, and latches response |
| **Current RTL Status** | **Implemented & Active** (IMEM & DMEM) | **Implemented in Hazard Unit; Tied to 0 in Standalone Top** | **Not Implemented** (Requires bus protocol extension) |

#### 4. Architectural Requirements for True Variable-Latency Support
To upgrade the standalone core to handle non-blocking caches or external DDR controllers with variable response times:
1. **Bus Protocol Handshaking:** Replace open-loop strobes with a standard protocol (e.g. AXI4-Lite or Wishbone B4) requiring an explicit `dmem_ready` or `dmem_ack` handshake signal from each slave.
2. **Memory Stage Request Latching:** When `dmem_stall` is active, the MEM stage must freeze its outgoing request lines (`dmem_addr`, `dmem_wdata`, `dmem_wstrb`) so that multi-cycle slaves observe stable bus inputs throughout the wait duration.
3. **Instruction Fetch Stall Integration:** Instruction cache misses would require an analogous `imem_stall` input to freeze the PC and IF stage independently from data memory stalls.

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

### 4.2 Memory Primitive Mapping: Distributed RAM vs. Block RAM

#### 1. What is FPGA Distributed RAM?
In AMD/Xilinx 7-series FPGAs (Artix-7), configurable logic blocks (CLBs) contain slices of type SLICEM (Memory-capable). The 6-input Look-Up Tables (LUTs) in SLICEMs can be configured as 64-bit or 256-bit wide static RAM cells (`RAMS64E`, `RAMD64E`, `RAM256X1S` primitives).
- **Key Advantage:** Distributed RAM supports **purely asynchronous (combinational) read operations**. An address presented on the inputs propagates to data outputs within the combinational propagation delay ($T_{AA} \approx 0.5\text{ ns}$), without requiring a clock edge.
- **Trade-off:** Consumes Slice LUT resources that would otherwise implement general logic.

#### 2. What is FPGA Block RAM (BRAM)?
AMD Artix-7 100T devices contain 135 dedicated 36 Kb Block RAM tiles (`RAMB36E1`), each divisible into two independent 18 Kb blocks (`RAMB18E1`), providing up to 4,860 Kb of dense storage with zero Slice LUT overhead.
- **Architectural Constraint:** Dedicated Block RAMs feature **strictly synchronous read ports**. Address inputs and read enables are sampled on an active clock edge (`posedge clk`), and the output data becomes available only after the subsequent clock tick ($T_{RCK} + T_{CO}$). They do **not** have combinational read ports.

#### 3. Synthesis Evidence & Resource Breakdown
Vivado 2026.1 synthesis and implementation reports provide empirical proof of how `imem` and `dmem` map onto the Artix-7 device:

| Memory Module | Instance Hierarchy | Primitive Type | LUTRAM Count | Logic LUTs | Block RAM Tiles (RAMB36/18) | Source Report |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **DMEM (16 KB)** | `u_cpu_top/u_dmem/u_ram` | `RAMS64E` (Distributed) | **2,048** | 129 | **0** (0.00%) | `fpga/reports/synth_utilization_hierarchical.rpt` |
| **IMEM (16 KB)** | `u_cpu_top/u_imem` | `RAMS64E` (Distributed) | **244** | 60 | **0** (0.00%) | `fpga/reports/synth_utilization_hierarchical.rpt` |
| **Total Memory** | — | **LUT as Distributed RAM**| **2,292** | 189 | **0 / 135 (0.00%)** | `fpga/reports/synth_utilization.rpt` |

*Verification Check:* As reported in `fpga/reports/synth_utilization.rpt` (Section 2, lines 71–80), **Block RAM Tile utilization is exactly 0.00%**. In Section 1 (lines 31–45), **LUT as Memory is 2,292 LUTs (12.06% of Artix-7 SLICEM capacity)**.

#### 4. Root Cause of Distributed RAM Inference
The synthesis tool infers Distributed RAM directly from the SystemVerilog read statements:
- In `rtl/memory/imem.sv` (Line 41):
  ```systemverilog
  assign rdata = (r_word_addr < NUM_WORDS) ? mem[r_word_addr] : 32'h00000013;
  ```
- In `rtl/memory/ram_sync.sv` used by `dmem.sv` (Line 38):
  ```systemverilog
  assign rdata = req ? mem[word_addr] : 32'h0;
  ```
Because both read ports are unclocked continuous assignments (`assign`), Vivado cannot map them to hardware Block RAMs without violating the simulation semantics of the code. Vivado automatically maps them to Distributed RAM primitives.

#### 5. Architectural Impact of Synchronous BRAM on the 5-Stage Pipeline
If `imem` or `dmem` were converted to synchronous Block RAM without pipeline adjustments, the 1-cycle read latency would alter stage timing:
- **Instruction Fetch (IF):** Presenting the Program Counter at cycle $T$ would only produce the instruction word at cycle $T+1$. In a classic 5-stage pipeline, this either:
  1. Doubles branch and jump penalties (from 2 cycles to 3 cycles) because target fetch requires an extra cycle.
  2. Requires splitting IF into two stages (`IF1: Address Issue` and `IF2: Instruction Capture`), transforming the pipeline into a 6-stage design and introducing new control hazard bubbles.
- **Memory Access (MEM):** For load instructions, presenting the effective address from EX at cycle $T$ would yield memory read data at cycle $T+2$ (the WB stage). This would:
  1. Prevent the core from forwarding load data in the MEM stage.
  2. Increase the load-use hazard penalty from 1 stall cycle to 2 stall cycles for immediately dependent instructions.

#### 6. Required Modifications for Future BRAM Migration
To adopt synchronous Block RAMs in a future iteration while preserving high clock frequency:
1. Re-code memory read blocks to use clocked sequential logic (`always_ff @(posedge clk) rdata <= mem[addr]`).
2. Add a fetch skid buffer in the IF stage to hold prefetched instructions during stalls.
3. Extend the load-use hazard interlock in `hazard_unit.sv` to stall for 2 cycles instead of 1 cycle when an instruction immediately consumes load data, or insert an explicit memory pipeline stage (`MEM1`/`MEM2`).

#### 7. Trade-Off Analysis Summary
| Design Metric | Current Design (Distributed RAM) | Alternative Design (Block RAM) |
| :--- | :--- | :--- |
| **Read Latency** | Combinational (0 cycles) | Synchronous (1 cycle minimum) |
| **FPGA Slice LUT Usage** | 2,292 LUTRAMs (7.62% of chip LUTs) | 0 LUTRAMs (storage contained in BRAM macros) |
| **FPGA BRAM Tile Usage** | 0 / 135 tiles (0.00%) | ~8 to 16 BRAM tiles depending on port width |
| **Pipeline Complexity** | Classic 5-stage textbook microarchitecture | Requires 2-cycle load hazard interlocks or skid buffers |
| **Timing Closure @ 100 MHz** | **Met (+0.178 ns WNS on Artix-7 -1)** | High array $F_{max}$, but extra hazard logic required |
| **Memory Size Scalability** | Limited to small arrays ($\le 32\text{ KB}$) | Readily scalable to hundreds of kilobytes |

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
