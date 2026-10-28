# System Architecture: Integrated RISC-V CPU + INT8 CNN Accelerator SoC

> **Mandatory Hardware Disclaimer**  
> *This project was developed and validated entirely using software-based RTL simulation and FPGA toolchain flows (AMD Vivado v2026.1 and Icarus Verilog v12.0). No physical FPGA board was used for hardware testing.*

This document provides a comprehensive technical specification of the processor microarchitecture, memory subsystem, bus interconnect, accelerator adapter, systolic array compute engine, and hardware-software co-design interfaces.

---

## 1. Top-Level System Architecture

The System-on-Chip (SoC) integrates a 5-stage pipelined RV32I processor core with a dedicated INT8 2D systolic array neural-network accelerator via a memory-mapped AXI4-Lite interconnect (`riscv_cnn_soc_top.sv`):

```text
+---------------------------------------------------------------------------------------------------+
|                                         riscv_cnn_soc_top                                         |
|                                                                                                   |
|   +-----------------------+              +----------------------------------------------------+   |
|   |      rv32i_core       |  Instruction |                    imem (16KB)                     |   |
|   |                       | <----------  |            (0x0000_0000 - 0x0000_3FFF)             |   |
|   |  - 5-Stage In-Order   |              +----------------------------------------------------+   |
|   |  - Data Forwarding    |                                                                       |
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
|                                                                                    | accel_top /  |
|soc_accel_top |
|                                                                                    | (INT8 4x4    |
|                                                                                    |  Systolic    |
|                                                                                    |  Array Engine|
|                                                                                    +--------------+
+---------------------------------------------------------------------------------------------------+
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

### 2.2 Data Forwarding Network (`forwarding_unit.sv`)
To minimize Read-After-Write (RAW) pipeline stalls, the forwarding unit routes values directly to the ALU inputs in the EX stage:
- **Priority 1 (EX/MEM Forwarding)**: If the instruction currently in the MEM stage is writing to a register ($rd \neq 0$) that matches the EX stage source register (`rs1` or `rs2`), data is forwarded directly from the MEM stage ALU output (`mem_fwd_data`).
- **Priority 2 (MEM/WB Forwarding)**: If the instruction in the WB stage is writing to a register ($rd \neq 0$) that matches the EX stage source register (and was not forwarded by EX/MEM), data is forwarded from the WB stage commit value (`wb_final_data`).
- **Default**: In the absence of data dependencies, operands are sourced directly from the register file.

### 2.3 Hazard Detection & Multi-Cycle Stall Resolution (`hazard_unit.sv`)
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
- **Multi-Cycle Bus Stall Resolution (`dmem_stall`)**:
  When accessing multi-cycle peripherals (such as the accelerator adapter over AXI-Lite), `dmem_stall` asserts:
  1. Stalls `pc`, `if_id`, `id_ex`, and `ex_mem` to freeze processor pipeline state.
  2. **Architectural Fix:** Asserts `flush_mem_wb = dmem_stall` to inject a synchronous bubble into the WB stage, preventing duplicate instruction retirement and register corruption while waiting for bus completion.

---

## 3. Bus Interconnect & Physical Address Space

The system bus interconnect (`bus_interconnect.sv`) decodes 32-bit physical addresses across memory-mapped targets:

| Address Range | Target Device | Width | Wait States | Description |
| :--- | :--- | :---: | :---: | :--- |
| `0x0000_0000 - 0x0000_3FFF` | `imem` (16 KB) | 32-bit | 0 | Instruction SRAM (combinational read) |
| `0x0000_4000 - 0x0000_7FFF` | `dmem` (16 KB) | 32-bit | 0 | Data SRAM (byte-write strobes) |
| `0x8000_0000 - 0x8000_001F` | `host_interface` | 32-bit | 0 | Host control & command mailbox |
| `0x8000_0020 - 0x8000_003F` | `timer` (HPMU) | 32-bit | 0 | 64-bit cycle counter & event monitors |
| `0x8000_0040 - 0x8000_005F` | `uart_lite` | 32-bit | 0 | Debug character transmission peripheral |
| `0x8000_1000 - 0x8000_10FF` | `accel_adapter` | 32-bit | Variable | INT8 CNN Accelerator MMIO-AXI4 Window |

---

## 4. INT8 CNN Hardware Accelerator Microarchitecture

The standalone accelerator (`accel_top.sv`) contains four primary hardware blocks:

```text
                      +---------------------------------------+
                      |             accel_top                 |
                      |                                       |
    AXI4-Lite Write   |   +-------------------------------+   |
    & Read Channels   |   |          ctrl_unit            |   |
  ==================> |   |  - Layer sequencer (FSM)      |   |
                      |   |  - Configuration registers    |   |
                      |   +---------------+---------------+   |
                      |                   |                   |
                      |                   v                   |
                      |   +---------------+---------------+   |
                      |   |          mem_ctrl             |   |
                      |   |  - Tensor address generator   |   |
                      |   |  - Weight & activation SRAMs  |   |
                      |   +---------------+---------------+   |
                      |                   | (INT8 data)       |
                      |                   v                   |
                      |   +---------------+---------------+   |
                      |   |          pe_array             |   |
                      |   |  - 4x4 Systolic Array (16 PEs)|   |
                      |   |  - 16 INT8 MACs / cycle       |   |
                      |   +---------------+---------------+   |
                      |                   | (INT32 accum)     |
                      |                   v                   |
                      |   +---------------+---------------+   |
                      |   |          post_proc            |   |
                      |   |  - Bias addition              |   |
                      |   |  - Scale & right-shift        |   |
                      |   |  - ReLU & 2x2 Max Pooling     |   |
                      |   +---------------+---------------+   |
                      |                   |                   |
                      |                   v                   |
                      |       Output Activations (INT8)       |
                      +---------------------------------------+
```

### 4.1 Processing Element (`pe.sv`) & Systolic Array (`pe_array.sv`)
- **Processing Element (PE)**:
  - Multiplies an 8-bit signed feature map input with an 8-bit signed weight: $A_{\text{int8}} \times W_{\text{int8}}$.
  - Accumulates incoming partial sum: $P_{\text{out}} \leftarrow P_{\text{in}} + (A_{\text{int8}} \times W_{\text{int8}})$.
  - Systolic forwarding: registers feature map activations horizontally to the right neighbor PE each clock cycle, while partial sums stream vertically down to the bottom neighbor PE.
- **Array Architecture**:
  - $4 \times 4$ 2D mesh of 16 PEs performing 16 multiply-accumulate (MAC) operations per clock cycle in a **Weight-Stationary (WS)** dataflow.
  - Weights are preloaded into PE registers via `w_load_en` and held stationary during tile computation.
  - Skewed input registers synchronize activation wavefront propagation across rows, and deskew registers realign partial sum outputs exiting columns.

### 4.2 Post-Processor (`post_proc.sv`)
- Performs fixed-point requantization:
  $$\text{Act}_{\text{out}} = \text{clip}\left(\left((Acc_{\text{int32}} + \text{Bias}_{\text{int32}}) \times \text{Scale}\right) \gg \text{Shift}, -128, 127\right)$$
- Integrates a hardware $2 \times 2$ Max Pooling unit to downsample spatial activations without CPU software intervention.

---

## 5. Accelerator MMIO-to-AXI-Lite Adapter (`accel_adapter.sv`)

Acts as the communication bridge between the single-cycle CPU data bus and the pipelined accelerator core:
- **Capability Register (`0x08`)**: Reports `32'h01040408` (Major Version 1.0, 4x4 array, 8-bit precision).
- **Adapter Status & Watchdog Register (`0x0C`)**:
  - Bit `[0]`: `timeout_err` (Sticky bus transaction timeout; write 1 to clear).
  - Bit `[1]`: `busy` (Active AXI transaction state).
  - Bit `[2]`: `irq_status` (Accelerator interrupt status).
  - Bits `[31:16]`: `watchdog_cnt` (Live 16-bit transaction cycle counter).
- **AXI4-Lite Master Interface**: Drives write address (`awaddr`), write data (`wdata`), write strobe (`wstrb`), read address (`araddr`), and samples response channels (`bvalid`, `rvalid`).
- **Hardware Watchdog**: 16-bit cycle timer (`WATCHDOG_LIMIT = 65535` cycles = ~655 µs @ 100 MHz) automatically aborts hung transactions, releases `dmem_stall`, returns `32'hDEAD_DEAD`, and flags `timeout_err`.

---

## 6. End-to-End Inference Execution Flow

```text
[CPU: Load Microcode] -> [CPU: DMA Image Stream] -> [CPU: Write START] -> [ACCEL: Compute 5 Layers] -> [CPU: Poll STATUS] -> [CPU: Read Logits & Argmax]
```

1. **Microcode Programming**: CPU executes loop writing 128-bit microcode words into `INSTR_W0..W3` (`0x8000_1020..0x8000_102C`) and commits via `INSTR_ADDR` (`0x8000_1030`).
2. **Input Tensor Streaming**: CPU writes 28x28 grayscale image pixels via `DMA_ADDR` (`0x8000_1010`) and `DMA_DATA` (`0x8000_1014`).
3. **Inference Trigger**: CPU writes `0x0000_0001` to `ACCEL_CTRL` (`0x8000_1000`).
4. **Autonomous Accelerator Execution**: The 4x4 systolic array and post-processor compute Conv1 -> Pool1 -> Conv2 -> Pool2 -> Dense layers in 53,836 clock cycles.
5. **Completion Polling**: CPU polls `ACCEL_STATUS` (`0x8000_1004`) until busy bit [0] de-asserts and done bit [1] asserts.
6. **Result Readback & Argmax**: CPU reads 10 output class logits via `RES_ADDR` (`0x8000_1018`) and `RES_DATA` (`0x8000_101C`), computing the predicted class index in software. Total SoC latency is 80,874 clock cycles.
