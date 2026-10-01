# APB_SPI_Bridge

## Overview

This project implements a configurable **AMBA APB-to-SPI bridge** using Verilog RTL.

The design accepts transactions from a CPU through an APB interface and converts APB write operations into SPI master transactions. SPI data is transferred between the bridge and an external SPI slave, and received data is buffered and made available to the CPU through an APB read interface.

The design was developed to practice and demonstrate:

* APB protocol implementation
* SPI protocol implementation
* RTL architecture and module integration
* Finite State Machine (FSM) design
* FIFO design
* Register-based control
* SPI clock generation
* CPOL/CPHA-based SPI modes
* Serial-to-parallel and parallel-to-serial data conversion
* Testbench development
* RTL simulation and waveform-based debugging

---

# 1. Design Architecture

The bridge is divided into multiple functional blocks.

<img width="2644" height="956" alt="image" src="https://github.com/user-attachments/assets/9d15149c-3d95-425e-9d27-6ef6d291ba69" />


---

# 2. Why an APB-to-SPI Bridge?

APB and SPI are designed for different purposes.

**APB** is a simple on-chip peripheral bus commonly used to connect processors or bus infrastructure to low-bandwidth peripherals.

**SPI** is a synchronous serial communication protocol commonly used to communicate with external devices such as sensors, memories, displays, ADCs, DACs, and other controllers.

A processor normally cannot directly treat an SPI device as an APB peripheral. The bridge provides the required protocol conversion.

```text
CPU
 |
 | APB transaction
 v
APB-to-SPI Bridge
 |
 | SPI transaction
 v
SPI Peripheral
```

The CPU performs register accesses using APB, while the bridge handles the SPI timing and serial data transfer.

---

# 3. APB Protocol

## 3.1 What is APB?

APB (Advanced Peripheral Bus) is part of the ARM AMBA family of protocols.

It is designed for simple, low-bandwidth peripheral accesses where high throughput is not the primary requirement.

The APB interface used in this project contains signals such as:

| Signal            | Description                          |
| ----------------- | ------------------------------------ |
| `PCLK`            | APB clock                            |
| `PRESET` / `PRST` | Reset                                |
| `PSEL`            | Selects the APB slave                |
| `PENABLE`         | Indicates the access phase           |
| `PWRITE`          | Selects read/write operation         |
| `PADDR`           | Address of the register              |
| `PWDATA`          | Write data                           |
| `PRDATA`          | Read data                            |
| `PREADY`          | Indicates completion of the transfer |
| `PSLVERR`         | Indicates an APB transfer error      |

In this implementation, the APB master and APB slave are both implemented inside the project to create a complete APB transaction environment.

---

# 4. APB Transfer Phases

An APB transfer consists of two main phases:

```text
IDLE
  |
  v
SETUP
  |
  v
ACCESS
  |
  v
IDLE
```

## SETUP Phase

During the setup phase:

```text
PSEL    = 1
PENABLE = 0
```

The master places the address and control information on the APB interface.

In this design, the `apb_master` captures:

* `cpu_paddr`
* `tx_data`
* `wr_cpu`

and generates:

* `PADDR`
* `PWDATA`
* `PWRITE`
* `PSEL`

## ACCESS Phase

During the access phase:

```text
PSEL    = 1
PENABLE = 1
```

The slave processes the requested transaction.

The master waits until:

```text
PREADY = 1
```

before returning to the IDLE state.

---

# 5. APB Master FSM

The APB master contains three states:

```text
+------+
| IDLE |
+--+---+
   |
   | cpu_valid
   v
+--------+
| SETUP  |
+---+----+
    |
    v
+--------+
| ACCESS |
+---+----+
    |
    | PREADY
    v
+------+
| IDLE |
+------+
```

### IDLE

Waits for a CPU transaction.

```text
if cpu_valid
    -> SETUP
```

### SETUP

The master asserts:

```text
PSEL = 1
PENABLE = 0
```

and captures the CPU address, data, and read/write control.

### ACCESS

The master asserts:

```text
PSEL = 1
PENABLE = 1
```

and waits for `PREADY`.

For a read transaction, `PRDATA` is captured into `rx_data` when the transfer completes.

---

# 6. APB Register Map

The APB slave implements four register addresses.

| Address | Register      | Access | Description               |
| ------- | ------------- | ------ | ------------------------- |
| `0x00`  | `CONTROL_REG` | Write  | SPI control configuration |
| `0x04`  | `TX_REG`      | Write  | Transmit data             |
| `0x08`  | `STATUS_REG`  | Read   | FIFO and SPI status       |
| `0x0C`  | `RX_REG`      | Read   | Received SPI data         |

---

# 7. Control Register

The bridge stores the control configuration in `control_reg`.

The SPI control information used by the SPI master is packed into the FIFO transaction.

The implemented control fields are:

| Bits     | Signal | Description        |
| -------- | ------ | ------------------ |
| `[0]`    | `EN`   | SPI enable         |
| `[1]`    | `CPOL` | SPI clock polarity |
| `[2]`    | `CPHA` | SPI clock phase    |
| `[10:3]` | `DIV`  | SPI clock divider  |

The complete FIFO entry is:

```text
43-bit FIFO Entry

+------------------+------------------+
|   TX DATA [31:0] | CONTROL [10:0]   |
+------------------+------------------+
       32 bits             11 bits
```

Therefore:

```text
32 + 11 = 43 bits
```

This allows the SPI master to retrieve both the transmit data and its corresponding SPI configuration from the same FIFO transaction.

---

# 8. TX Register

The CPU writes transmit data to:

```text
Address = 0x04
```

Example:

```text
CPU writes:

Address = 0x04
Data    = 0x12345678
```

The APB slave stores the value in `tx_reg`.

When the APB write is accepted, the design creates a 43-bit FIFO entry:

```text
d_in = {pwdata, control_reg[10:0]}
```

This combines:

```text
TX DATA
+
SPI CONTROL
```

into one FIFO transaction.

---

# 9. FIFO

A synchronous FIFO is used between the APB side and SPI master.

### FIFO characteristics

```text
Data width : 43 bits
Depth      : 32 entries
Clock      : PCLK
```

The FIFO stores:

```text
{TX_DATA, EN, CPOL, CPHA, DIV}
```

### Why the FIFO is used

The APB side and SPI transfer side have different transaction timing requirements.

The FIFO provides temporary storage between:

```text
APB transaction
        |
        v
     FIFO
        |
        v
SPI transaction
```

This allows the APB side to submit SPI transactions without requiring the SPI transfer to complete during the same APB access.

---

# 10. FIFO Full and Empty Detection

The FIFO uses:

```text
write_pt[4:0]
read_pt[4:0]
```

The lower four bits address the 32-entry memory.

The MSB is used to distinguish between different FIFO wrap-around cycles.

### Empty

```verilog
empty = (write_pt == read_pt);
```

### Full

```verilog
full =
    (write_pt[4] != read_pt[4]) &&
    (write_pt[3:0] == read_pt[3:0]);
```

This is a standard pointer-based technique for detecting FIFO full and empty conditions.

---

# 11. SPI Protocol

## 11.1 What is SPI?

SPI (Serial Peripheral Interface) is a synchronous serial communication protocol.

A typical SPI interface contains four signals:

| Signal  | Direction      | Description                |
| ------- | -------------- | -------------------------- |
| `SCLK`  | Master → Slave | Serial clock               |
| `MOSI`  | Master → Slave | Master Out Slave In        |
| `MISO`  | Slave → Master | Master In Slave Out        |
| `SS/CS` | Master → Slave | Slave Select / Chip Select |

In this project:

```text
SPI Master
    |
    +---- SCLK ----> SPI Slave
    |
    +---- MOSI ----> SPI Slave
    |
    +---- SS ------> SPI Slave
    |
    <---- MISO ---- SPI Slave
```

---

# 12. SPI Full-Duplex Communication

SPI supports **full-duplex communication**.

During the same clock cycle:

```text
Master ---- MOSI ----> Slave
Master <---- MISO ---- Slave
```

The master can transmit one bit while simultaneously receiving one bit.

For an 8-bit transfer:

```text
Clock 1: TX bit 7 / RX bit 7
Clock 2: TX bit 6 / RX bit 6
Clock 3: TX bit 5 / RX bit 5
...
Clock 8: TX bit 0 / RX bit 0
```

Therefore, transmit and receive operations occur simultaneously at the serial interface.

### Important distinction

APB should not technically be described as a **half-duplex protocol**.

APB is a **simple request/response bus** where a transaction is either a write or a read.

SPI, on the other hand, is inherently capable of **full-duplex** transfer because MOSI and MISO operate simultaneously.

---

# 13. SPI Clock Polarity and Phase

SPI defines four common operating modes using:

* `CPOL` — Clock Polarity
* `CPHA` — Clock Phase

The four modes are:

| SPI Mode | CPOL | CPHA | Clock Idle | First Sampling Edge |
| -------- | ---: | ---: | ---------- | ------------------- |
| Mode 0   |    0 |    0 | Low        | Rising              |
| Mode 1   |    0 |    1 | Low        | Falling             |
| Mode 2   |    1 |    0 | High       | Falling             |
| Mode 3   |    1 |    1 | High       | Rising              |

---

# 14. SPI Mode 0

```text
CPOL = 0
CPHA = 0
```

Clock remains LOW when idle.

Data is sampled on the rising edge and shifted on the falling edge.

```text
SCLK:  __/‾\__/‾\__/‾\__
          ^     ^     ^
        Sample Sample Sample
```

---

# 15. SPI Mode 1

```text
CPOL = 0
CPHA = 1
```

Clock remains LOW when idle.

Data is shifted on the rising edge and sampled on the falling edge.

---

# 16. SPI Mode 2

```text
CPOL = 1
CPHA = 0
```

Clock remains HIGH when idle.

Data is sampled on the falling edge and shifted on the rising edge.

---

# 17. SPI Mode 3

```text
CPOL = 1
CPHA = 1
```

Clock remains HIGH when idle.

Data is shifted on the falling edge and sampled on the rising edge.

---

# 18. CPOL/CPHA Implementation

The SPI master generates internal edge-detection signals:

```verilog
posedge_sclk
negedge_sclk
```

The sampling edge is selected using:

```verilog
assign sample_en =
    ((cpol == cpha) && posedge_sclk) ||
    ((cpol != cpha) && negedge_sclk);
```

The shifting edge is selected using:

```verilog
assign shift_en =
    ((cpol == cpha) && negedge_sclk) ||
    ((cpol != cpha) && posedge_sclk);
```

This allows the same SPI master architecture to support the four standard SPI modes.

---

# 19. SPI Master FSM

The SPI master contains five states:

```text
             +------+
             | IDLE |
             +--+---+
                |
             FIFO data
                |
                v
             +------+
             | COPY |
             +--+---+
                |
                v
             +------+
             | LOAD |
             +--+---+
                |
                v
          +-----------+
          | TRANSFER  |
          +-----+-----+
                |
          4 bytes complete
                |
                v
             +------+
             | DONE |
             +--+---+
                |
                v
             +------+
             | IDLE |
             +------+
```

## IDLE

The SPI master waits until the FIFO contains a transaction.

```text
fifo_empty = 0
```

The FIFO read enable is asserted.

---

## COPY

The 43-bit FIFO data is captured into:

```verilog
dout_reg
```

The SPI configuration is also extracted:

```text
EN
CPOL
CPHA
DIV
```

---

## LOAD

The appropriate byte is loaded into the transmit shift register.

The design divides the 32-bit transmit data into four 8-bit transfers:

```text
Byte 0 = [31:24]
Byte 1 = [23:16]
Byte 2 = [15:8]
Byte 3 = [7:0]
```

The first MOSI bit is then presented to the SPI interface.

---

## TRANSFER

During the transfer state:

* `SS` is asserted LOW
* `SCLK` is generated
* MOSI is shifted
* MISO is sampled
* RX data is accumulated
* Transfer count is updated

The bridge performs four 8-bit SPI transfers for the 32-bit transmit word.

---

## DONE

After all four bytes have been transferred, the received byte is moved to:

```verilog
slave_data
```

The SPI transaction is then completed and the slave select returns HIGH.

---

# 20. SPI Clock Generation

The SPI clock is generated from the APB clock.

The programmable divider is obtained from:

```text
CONTROL_REG[10:3]
```

The SPI master uses:

```verilog
clk_count
```

to control the SCLK toggle rate.

Conceptually:

```text
PCLK
 |
 | clock divider
 v
SCLK
```

The SPI clock is held at the configured CPOL value when the SPI master is not transferring:

```verilog
sclk <= cpol;
```

During transfer:

```verilog
sclk <= ~sclk;
```

when the divider count reaches the programmed value.

---

# 21. SPI Slave

The project also contains an SPI slave model for simulation and verification.

The slave implements:

* MOSI reception
* MISO transmission
* TX shift register
* RX shift register
* CPOL/CPHA-dependent operation
* Slave-select handling

The SPI slave receives serial data through:

```text
MOSI
```

and transmits data through:

```text
MISO
```

The supplied testbench provides:

```text
slave_tx_data = 8'hA5
```

for SPI receive testing.

---

# 22. Receive Data Path

The SPI receive path is:

```text
SPI Slave
    |
   MISO
    |
    v
SPI Master RX Shift Register
    |
    v
slave_data
    |
    v
Buffer
    |
    v
RX Register
    |
    v
APB PRDATA
    |
    v
CPU
```

The SPI master serially samples MISO and reconstructs the received byte.

The buffer collects four received bytes.

After four bytes have been collected:

```text
4 × 8 bits = 32 bits
```

the assembled data is placed into `p_out`.

The APB slave continuously updates:

```text
RX_REG <= p_out
```

The CPU can then read the received data using:

```text
Address = 0x0C
```

---

# 23. Status Register

The status register provides information about the bridge.

|      Bit | Signal      | Description                   |
| -------: | ----------- | ----------------------------- |
|        0 | `fifo_full` | FIFO full indication          |
|        1 | `pready`    | APB transfer ready indication |
|        2 | `busy`      | SPI master busy indication    |
| `[31:3]` | —           | Reserved / zero               |

Therefore:

```text
STATUS_REG[0] = FIFO FULL
STATUS_REG[1] = APB READY
STATUS_REG[2] = SPI BUSY
```

---

# 24. APB Error Handling

The APB slave validates the requested address.

Supported addresses:

```text
0x00
0x04
0x08
0x0C
```

For an unsupported address:

```text
PSLVERR = 1
```

For a supported address:

```text
PSLVERR = 0
```

This provides basic APB address-error handling.

---

# 25. Complete Write Transaction

A typical CPU-to-SPI transaction is:

```text
CPU
 |
 | Write CONTROL_REG
 | Address = 0x00
 | Data = CPOL/CPHA/DIV
 v
APB Master
 |
 | APB SETUP
 | APB ACCESS
 v
APB Slave
 |
 | Store configuration
 v
CONTROL_REG
```

Then:

```text
CPU
 |
 | Write TX_REG
 | Address = 0x04
 | Data = 0x12345678
 v
APB Master
 |
 v
APB Slave
 |
 | Combine:
 | {TX_DATA, CONTROL}
 v
FIFO
 |
 v
SPI Master
 |
 v
SPI Slave
```

---

# 26. Complete Read Transaction

The receive path works in the opposite direction:

```text
SPI Slave
    |
    | MISO
    v
SPI Master
    |
    v
RX Shift Register
    |
    v
Buffer
    |
    v
RX_REG
    |
    | APB Read
    v
APB Slave
    |
    v
APB Master
    |
    v
CPU
```

The CPU reads:

```text
Address = 0x0C
```

to obtain the received 32-bit data.

---

# 27. Example Transaction

### Step 1 — Configure SPI

CPU writes:

```text
Address = 0x00
Data    = 0x00000019
```

The control value configures the SPI control fields.

---

### Step 2 — Write Transmit Data

CPU writes:

```text
Address = 0x04
Data    = 0x12345678
```

The APB slave creates:

```text
{32-bit TX data, 11-bit control}
```

and writes the transaction into the FIFO.

---

### Step 3 — SPI Master Reads FIFO

The SPI master detects:

```text
fifo_empty = 0
```

and reads the transaction.

---

### Step 4 — SPI Transfer

The 32-bit word is transferred as four SPI bytes:

```text
12
34
56
78
```

The SPI master simultaneously receives data through MISO.

---

### Step 5 — Receive Data

The received bytes are collected by the buffer.

After four bytes:

```text
RX data = 32 bits
```

The data becomes available through `RX_REG`.

---

### Step 6 — CPU Reads RX Register

CPU performs:

```text
Address = 0x0C
```

and receives the SPI response.

---

# 28. Verification Testbench

The testbench generates the APB-side CPU transactions and connects the complete bridge.

### Clock

```verilog
always #5 pclk = ~pclk;
```

This generates a 10-time-unit APB clock period.

### Reset

The testbench initially asserts reset:

```text
PRST = 1
```

and releases it after several clock cycles.

### Test sequence

The testbench performs:

1. Reset
2. Write control register
3. Write TX register
4. Wait for SPI transaction
5. Read status register
6. Read RX register
7. Finish simulation

The simulation also generates:

```text
top.vcd
```

for waveform analysis.

---

# 29. Verification Flow

The overall verification flow is:

```text
CPU Stimulus
     |
     v
APB Master
     |
     v
APB Slave
     |
     v
FIFO
     |
     v
SPI Master
     |
     v
SPI Slave
     |
     v
Receive Buffer
     |
     v
APB Readback
```

The testbench can be extended to verify:

* APB read/write transactions
* Invalid APB addresses
* FIFO full condition
* FIFO empty condition
* SPI transmit data
* SPI receive data
* Different CPOL values
* Different CPHA values
* Different SPI clock divider values
* Reset behavior
* Multiple SPI transactions

---

# 30. Important RTL Design Concepts Demonstrated

This project demonstrates several practical RTL design concepts.

### FSM Design

Separate FSMs are used for:

* APB master
* SPI master

The FSMs control protocol sequencing and transaction timing.

### FIFO Design

The design implements:

* Memory array
* Read pointer
* Write pointer
* Full detection
* Empty detection
* Synchronous read/write behavior

### Shift Registers

SPI serial communication is implemented using:

```text
TX Shift Register
RX Shift Register
```

This converts:

```text
Parallel → Serial
Serial → Parallel
```

### Clock Generation

A programmable divider generates SPI clock timing from the APB clock.

### Protocol Conversion

The bridge converts:

```text
APB register transaction
          ↓
    FIFO transaction
          ↓
    SPI serial transfer
```

### Modular RTL Architecture

The design is divided into independent modules:

```text
top
 ├── apb_master
 ├── apb_slave
 ├── fifo
 ├── spi_master
 ├── spi_slave
 └── buffer
```

This makes the design easier to understand, debug, modify, and verify.

---

# 31. Module Description

| Module       | Responsibility                         |
| ------------ | -------------------------------------- |
| `top`        | Integrates the complete bridge         |
| `apb_master` | Generates APB transactions             |
| `apb_slave`  | Implements APB registers and responses |
| `fifo`       | Buffers APB-to-SPI transactions        |
| `spi_master` | Generates SPI transfers                |
| `spi_slave`  | Models the external SPI device         |
| `buffer`     | Collects received SPI bytes            |
| `tb`         | Provides simulation stimulus           |

---

# 32. Design Flow

The complete data flow can be summarized as:

```text
                    WRITE PATH

CPU
 |
 | APB Write
 v
APB Master
 |
 v
APB Slave
 |
 | TX_DATA + CONTROL
 v
FIFO
 |
 v
SPI Master
 |
 | MOSI
 v
SPI Slave
```

```text
                    READ PATH

SPI Slave
 |
 | MISO
 v
SPI Master
 |
 v
RX Shift Register
 |
 v
Buffer
 |
 v
RX Register
 |
 v
APB Slave
 |
 v
APB Master
 |
 v
CPU
```

---

# 33. Design Highlights

### Protocol-Level Design

Implemented both sides of the APB transaction flow and integrated APB with SPI.

### Configurable SPI Operation

Implemented CPOL/CPHA-based edge selection supporting the four standard SPI modes.

### FIFO-Based Decoupling

Used a 32-entry × 43-bit FIFO to decouple APB transactions from SPI transfer timing.

### Multi-Byte SPI Transfer

Implemented 32-bit transmit data as four sequential 8-bit SPI transfers.

### Programmable SPI Clock

Implemented clock-divider-based SPI clock generation.

### Register-Based Architecture

Implemented dedicated control, transmit, status, and receive registers.

### Error Handling

Implemented APB invalid-address detection using `PSLVERR`.

### Modular RTL

Separated the design into protocol, storage, transfer, and buffering modules.

---

# 34. Tools and Technologies

* Verilog/SystemVerilog
* AMBA APB
* SPI
* RTL Design
* FSM Design
* FIFO Design
* Shift Registers
* Digital Logic Design
* RTL Simulation
* Waveform Debugging
* VCD Analysis
* EDA Playground / Verilog Simulator

---

# 35. Possible Future Enhancements

The current design can be extended with:

* Multiple SPI slave support
* Programmable SPI data width
* Interrupt generation
* DMA-based transfers
* Separate TX/RX FIFOs
* Configurable FIFO depth
* Additional APB status/error registers
* More extensive protocol assertions
* SystemVerilog constrained-random verification
* Functional coverage
* APB and SPI protocol checkers
* UVM-based verification environment

---

# 36. Key Skills Demonstrated

This project demonstrates practical experience in:

**RTL Design**

* Modular Verilog/SystemVerilog design
* FSM implementation
* Sequential and combinational logic
* Register-based architectures

**Protocol Design**

* AMBA APB
* SPI
* Full-duplex serial communication
* CPOL/CPHA SPI modes

**Data Path Design**

* FIFO
* Shift registers
* Parallel-to-serial conversion
* Serial-to-parallel conversion
* Data buffering

**Control Logic**

* Transaction sequencing
* Clock generation
* FIFO flow control
* Busy/ready/error handling

**Verification & Debugging**

* RTL testbench development
* Transaction-based testing
* VCD waveform generation
* Protocol timing analysis
* Debugging RTL behavior

---

**Design decisions and Challenges**
**Design decisions**
*Address encoding for control register,tx_reg,rx_reg,status reg
*SCLK generations from main PCLK
*Including all  4 SPI modes in SPI design
*Detecting Posedge and negedge for sampling and shifting
*Seperate FSM to differentaite each transfer
*Used fifo and buffer to temporarily store the data

**Design Challenges**
*While designig all 4 modes into the SPI master module,occur multi driven ports,because of based on the CPOL and CPHA edge may vary from one mode to another mode
*Logic for posedge and negedge  detection
*Loss of data,because of APB is faster than SPI,while doing SPI transfer APB can do another operation.So used fifo to avoid data loss
*Control_reg data may changes for every transfer

**Debug challenges**
*Checking CPOL and CPHA continuously to monitor shifting and sampling
*Checked whether data is shifting and sample on correct edge or not
*Monitored the empty and full condition of fifo
*Monitoring miso and mosi ports whether data is transfering according to the data or not
*Input and output data both or same or not
*Do signals are asserting according to the FSM states


# 37. Conclusion

The APB-to-SPI Bridge demonstrates how a processor-facing APB interface can be integrated with an external SPI communication interface using a modular RTL architecture.

The design combines:

```text
APB
 +
Register Interface
 +
FIFO
 +
FSM
 +
Clock Divider
 +
CPOL/CPHA Logic
 +
SPI Master
 +
SPI Slave
 +
Receive Buffer
```

to create a complete RTL-based APB-to-SPI communication subsystem.

The project provides hands-on implementation experience with **protocol conversion, RTL architecture, FSM design, FIFO design, serial communication, clock generation, and simulation-based debugging**.
