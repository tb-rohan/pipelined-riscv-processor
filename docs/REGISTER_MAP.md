# System Register Map: Standalone RV32I Processor Subsystem

> **Mandatory Hardware Disclaimer**  
> *This project was validated using software-based RTL simulation and FPGA toolchain flows. No physical FPGA board was used for hardware testing.*

This document provides a bit-level register specification for all peripherals and memory-mapped devices across the Standalone RV32I Processor subsystem.

---

## 1. Peripheral Base Addresses

| Peripheral Subsystem | Base Address | End Address | Size | Description |
| :--- | :--- | :--- | :---: | :--- |
| `host_interface` | `0x8000_0000` | `0x8000_001F` | 32 B | Host-CPU interactive communication & control |
| `timer` / HPMU | `0x8000_0020` | `0x8000_003F` | 32 B | 64-bit cycle counter & Hardware Performance Monitor |
| `uart_lite` | `0x8000_0040` | `0x8000_005F` | 32 B | Non-blocking UART transmitter / receiver |
| `accel_adapter` | `0x8000_1000` | `0x8000_103F` | 64 B | INT8 CNN hardware accelerator control window |

---

## 2. Host Interface Register Specification (`0x8000_0000`)

### 2.1 `HOST_CTRL` (`0x8000_0000`) - Control & Command Register
- **Offset:** `0x00`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write

| Bits | Field Name | Access | Reset | Description |
| :---: | :--- | :---: | :---: | :--- |
| 31:16 | `RESERVED` | RO | 0x0 | Reserved, write as 0 |
| 15:8 | `COMMAND` | RW | 0x0 | Operation command opcode dispatched to CPU firmware:<br>`0x01` = Add, `0x02` = Sub, `0x03` = Mul, `0x04` = Div<br>`0x05` = AND, `0x06` = OR, `0x07` = XOR, `0x08` = NOT<br>`0x09` = SLL, `0x0A` = SRL, `0x0B` = SRA<br>`0x0C` = SLT, `0x0D` = SLTU<br>`0x0E` = Full 37-Instruction RV32I ISA Verification |
| 7:2 | `RESERVED` | RO | 0x0 | Reserved |
| 1 | `ACK_DONE` | RW | 0x0 | Acknowledged by host or CPU after completion |
| 0 | `REQ_START` | RW | 0x0 | Asserted by host (1) to trigger execution; cleared by CPU |

### 2.2 `HOST_OP_A` (`0x8000_0004`) - Operand A Register
- **Offset:** `0x04`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** First 32-bit operand passed to CPU computation routines.

### 2.3 `HOST_OP_B` (`0x8000_0008`) - Operand B Register
- **Offset:** `0x08`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Second 32-bit operand passed to CPU computation routines.

### 2.4 `HOST_RESULT` (`0x8000_000C`) - Result Low Register
- **Offset:** `0x0C`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Lower 32 bits of arithmetic result or classification predicted class (0..9).

### 2.5 `HOST_RESULT_HI` (`0x8000_0010`) - Result High Register
- **Offset:** `0x10`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Upper 32 bits of multiplication product, division remainder, or winning class score.

### 2.6 `HOST_STATUS` (`0x8000_0014`) - Execution Status Register
- **Offset:** `0x14`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Returns elapsed clock cycles or status flag (`0x0` = IDLE, `0x1` = BUSY, `0x2` = PASS, `0x3` = FAIL).

---

## 3. Timer & Hardware Performance Monitoring Unit (`0x8000_0020`)

### 3.1 `CYCLES_LO` (`0x8000_0020`) - System Cycle Counter Low
- **Offset:** `0x20`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Lower 32 bits of 64-bit continuous free-running hardware cycle counter.

### 3.2 `CYCLES_HI` (`0x8000_0024`) - System Cycle Counter High
- **Offset:** `0x24`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Upper 32 bits of 64-bit continuous free-running hardware cycle counter.

### 3.3 `INSTRET` (`0x8000_0028`) - Instructions Retired Counter
- **Offset:** `0x28`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** 32-bit counter incrementing each time an instruction commits at the Writeback (WB) stage without a stall. Used to calculate CPI (`CYCLES / INSTRET`).

### 3.4 `LOAD_USE_STALLS` (`0x8000_002C`) - Load-Use Hazard Stall Counter
- **Offset:** `0x2C`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Increments when the hazard detection unit injects a pipeline bubble due to a load-use RAW dependency.

### 3.5 `BRANCH_FLUSHES` (`0x8000_0030`) - Branch & Jump Flush Counter
- **Offset:** `0x30`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Increments each time a taken branch or jump mispredicts and flushes instructions from IF/ID and ID/EX stages.

### 3.6 `BUS_STALLS` (`0x8000_0034`) - Bus Wait-State Stall Counter
- **Offset:** `0x34`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Increments for every clock cycle the CPU pipeline is stalled waiting for external bus peripherals (`dmem_stall`).

---

## 4. UART Lite Register Specification (`0x8000_0040`)

### 4.1 `UART_TX_DATA` (`0x8000_0040`) - Transmit Data Register
- **Offset:** `0x40`
- **Access:** Write Only
- **Description:** Writing bits [7:0] initiates character transmission. In simulation, immediately prints to standard output.

### 4.2 `UART_STATUS` (`0x8000_0044`) - Status Register
- **Offset:** `0x44`
- **Access:** Read Only
- **Fields:**
  - `Bit 0`: `TX_READY` (1 = Transmitter buffer ready to accept next byte).
  - `Bit 1`: `RX_VALID` (1 = Valid received character in `UART_RX_DATA`).

### 4.3 `UART_RX_DATA` (`0x8000_0048`) - Receive Data Register
- **Offset:** `0x48`
- **Access:** Read Only
- **Description:** Returns received 8-bit character.

---

## 5. INT8 CNN Accelerator MMIO Register Specification (`0x8000_1000`)

### 5.1 `ACCEL_CTRL` (`0x8000_1000`) - Accelerator Control
- **Offset:** `0x00`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write

| Bits | Field Name | Access | Reset | Description |
| :---: | :--- | :---: | :---: | :--- |
| 31:3 | `RESERVED` | RO | 0x0 | Reserved |
| 2 | `AUTO_RESTART`| RW | 0x0 | Automatically process next tile in queue |
| 1 | `SOFT_RESET` | RW | 0x0 | Reset accelerator pipeline and registers |
| 0 | `START` | RW | 0x0 | Trigger layer computation pulse |

### 5.2 `ACCEL_STATUS` (`0x8000_1004`) - Accelerator Status
- **Offset:** `0x04`
- **Reset:** `0x0000_0000`
- **Access:** Read Only

| Bits | Field Name | Access | Reset | Description |
| :---: | :--- | :---: | :---: | :--- |
| 31:4 | `RESERVED` | RO | 0x0 | Reserved |
| 3 | `TIMEOUT` | RO | 0x0 | Bus watchdog triggered timeout |
| 2 | `ERROR` | RO | 0x0 | Configuration parameter error |
| 1 | `DONE` | RO | 0x0 | Layer computation finished |
| 0 | `BUSY` | RO | 0x0 | Hardware compute engine active |

### 5.3 `ACCEL_CAP` (`0x8000_1008`) - Accelerator Capability & Hardware Version
- **Offset:** `0x08`
- **Reset:** `0x0104_0408`
- **Access:** Read Only

| Bits | Field Name | Value | Description |
| :---: | :--- | :---: | :--- |
| 31:24 | `MAJOR_VER` | `0x01` | Architecture Major Revision 1.0 |
| 23:16 | `ARRAY_ROWS` | `0x04` | 4 Processing Element Rows |
| 15:8 | `ARRAY_COLS` | `0x04` | 4 Processing Element Columns |
| 7:0 | `PRECISION` | `0x08` | 8-bit Signed Quantized Integer (INT8) |

### 5.4 `ACCEL_CFG_LAYER` (`0x8000_100C`) - Layer Configuration
- **Offset:** `0x0C`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Fields:**
  - `Bits [2:0]`: `LAYER_TYPE` (`0` = 2D Convolution, `1` = 2x2 Max Pooling, `2` = Fully Connected).
  - `Bit 3`: `RELU_EN` (1 = Enable post-activation ReLU clamp).

### 5.5 `ACCEL_SRC_ADDR` (`0x8000_1010`) - Input Feature Map Base Address
- **Offset:** `0x10`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Byte address in memory storing input activation tensor.

### 5.6 `ACCEL_DST_ADDR` (`0x8000_1014`) - Output Activation Base Address
- **Offset:** `0x14`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Byte address where resulting layer activations will be stored.

### 5.7 `ACCEL_WEIGHT_ADDR` (`0x8000_1018`) - Weight Tensor Base Address
- **Offset:** `0x18`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Byte address where quantized kernel weights are located.

### 5.8 `ACCEL_BIAS_ADDR` (`0x8000_101C`) - Bias Tensor Base Address
- **Offset:** `0x1C`
- **Reset:** `0x0000_0000`
- **Access:** Read / Write
- **Description:** Byte address storing 32-bit accumulated biases.

### 5.9 `ACCEL_DIM_IN` (`0x8000_1020`) - Input Spatial Dimensions
- **Offset:** `0x20`
- **Fields:** `[15:0]` Channels In, `[31:16]` Spatial Width / Height.

### 5.10 `ACCEL_DIM_OUT` (`0x8000_1024`) - Output Spatial Dimensions
- **Offset:** `0x24`
- **Fields:** `[15:0]` Channels Out, `[31:16]` Spatial Width / Height.

### 5.11 `ACCEL_POST_SCALE` (`0x8000_1028`) - Requantization Scale Multiplier
- **Offset:** `0x28`
- **Description:** Fixed-point scalar multiplier applied during post-processing.

### 5.12 `ACCEL_POST_SHIFT` (`0x8000_102C`) - Requantization Shift Divisor
- **Offset:** `0x2C`
- **Description:** Arithmetic right-shift factor applied to rescale 32-bit accumulators back to 8-bit.

### 5.13 `ACCEL_PERF_CYCLES` (`0x8000_1030`) - Layer Cycle Counter
- **Offset:** `0x30`
- **Access:** Read Only
- **Description:** Hardware execution cycle count measured directly inside the accelerator for the last completed layer.
