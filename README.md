# FPGA-Based NMEA Parser via UART

## Overview
This project implements an **FPGA-based NMEA Parser** using Verilog HDL. The system receives standard NMEA sentences through **UART communication**, processes the incoming data streams using a **Finite State Machine (FSM)**, validates the checksum in real time, and transmits the parsed results back via UART.

A Python-based serial transmitter running on a host PC generates the NMEA messages and sends them to the FPGA through an external **FTDI USB-TTL converter**.

---

## System Architecture

```text
  [ PC / Python Serial Sender ]
               │
               ▼
   [ FTDI USB-TTL Converter ]
               │
               ▼
          [ UART RX ]
               │
               ▼
 ┌───────────────────────────┐
 │      NMEA Parser FSM      │
 │                           │
 │  • Start Detection ('$')  │
 │  • Field Extraction       │
 │  • Checksum Validation    │
 └───────────────────────────┘
               │
               ▼
          [ UART TX ]
               │
               ▼
      [ PC Serial Monitor ]
```

---

## Features
- **High-Speed UART Communication:** Configured for 115200 baud rate.
- **Robust FSM-based Parsing:** Accurately extracts individual NMEA fields.
- **Real-Time Validation:** Performs automatic XOR checksum calculations on incoming ASCII streams.
- **Bi-Directional Serial Interface:** Transmits parsed results and validation status back to the host PC.
- **Hardware Debugging:** Integrated LED status indicators for visual FSM and communication tracking.

---

## Hardware Specifications

| Component | Specification |
|-----------|---------------|
| **FPGA Board** | Digilent Zybo |
| **FPGA Device** | XC7Z010 |
| **Clock Frequency**| 125 MHz |
| **Interface** | UART (via FTDI USB-TTL) |
| **Baud Rate** | 115200 bps |

---

## Module Descriptions

### 1. UART RX
Converts incoming serial data from the FTDI module into 8-bit parallel ASCII data.
- **Functions:** Detects the UART start bit, shifts in 8 bits of data, and flags completion.
- **Key Signals:** Outputs `rx_data` (8-bit) and `rx_ready` (1-bit pulse).

### 2. NMEA Parser FSM
The core control unit responsible for interpreting the received sequence.
- **IDLE:** Waits for the NMEA start character (`$`).
- **START:** Initializes data buffering.
- **READ_FIELD:** Extracts comma-separated NMEA data fields.
- **CHECKSUM:** Captures and validates the appended checksum.
- **DONE_OUTPUT:** Triggers the transmission of processed data.

### 3. Checksum Validator
Calculates the XOR value of all characters between the `$` and `*` in the NMEA message, comparing it against the received hex checksum.
- **Key Signals:** Outputs `checksum_valid_flag` and `checksum_error_flag`.

### 4. UART TX
Sends the processed data and validation results back to the PC using standard UART framing (1 Start Bit, 8 Data Bits, 1 Stop Bit).

---

## Project Structure

```text
FPGA_NMEA_Parser/
├── src/
│   ├── nmea_parser.v
│   ├── uart_rx.v
│   ├── uart_tx.v
│   └── checksum_validator.v
├── simulation/
│   └── nmea_parser_tb.v
├── constraints/
│   └── zybo.xdc
└── python/
    └── nmea_sender.py
```

---

## Getting Started

### 1. FPGA Synthesis and Implementation
1. Open Xilinx Vivado and create a new project targeting the **Zybo (XC7Z010)** board.
2. Import all Verilog files from the `src/` directory.
3. Add the `zybo.xdc` file from the `constraints/` directory.
4. Run **Synthesis**, **Implementation**, and **Generate Bitstream**.
5. Program the Zybo board via Vivado Hardware Manager.

### 2. Running the Python Test Environment
Ensure the FTDI adapter is connected between your PC and the configured Zybo PMOD pins.

Install the required Python serial library:
```bash
pip install pyserial
```

Run the NMEA sender script:
```bash
cd python/
python nmea_sender.py
```

### Example Data Flow
**Input sent from Python:**
```text
$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0*4F
```
**Hardware Processing:**
`UART RX` → `NMEA Parser FSM` → `Checksum Validation` → `UART TX Response`

---

## Debugging Guide

The Zybo's onboard LEDs are mapped to specific internal signals for real-time hardware debugging:

| LED | Function |
|:---:|----------|
| **LED0** | FSM status indicator (active while parsing) |
| **LED1** | Checksum Valid indicator (lights up on successful match) |
| **LED2** | Checksum Error indicator (lights up on mismatch) |
| **LED3** | UART RX activity (toggles on received bytes) |

---

## Challenges and Solutions

1. **UART Communication Routing**
   * **Problem:** The base Zybo board setup required a reliable serial interface that bypassed onboard complexities for direct module testing.
   * **Solution:** Interfaced an external FTDI USB-TTL converter directly to the PMOD headers, acting as a clean UART RX/TX bridge.
2. **Constraint Configuration Issues**
   * **Problem:** Initial builds failed or behaved erratically due to an incorrect XDC pinout file sourced from a different Zybo variant.
   * **Solution:** Audited the board schematic and updated the `zybo.xdc` file to perfectly match the specific XC7Z010 pin mapping.
3. **Isolating Parsing Logic from Hardware Bugs**
   * **Problem:** When outputs were garbled, it was difficult to tell if the issue lay in the FTDI electrical connection, UART timing, or FSM logic.
   * **Solution:** Implemented the LED debug mapping described above to visually isolate the pipeline stages in real time.

---

## Conclusion
This project successfully demonstrates the deployment of a real-time, hardware-accelerated NMEA Parser on an FPGA. By integrating serial communication, rigorous digital design, and FSM-based data processing, it highlights how structured textual data can be efficiently managed at the bare-metal hardware level.
