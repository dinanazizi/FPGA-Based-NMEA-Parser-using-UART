# FPGA-Based NMEA Parser using UART

## Overview

This project implements an **FPGA-based NMEA Parser** using Verilog HDL.  
The system receives NMEA sentences through **UART communication**, processes the incoming data using a **Finite State Machine (FSM)**, validates the checksum, and transmits the processed information back through UART.

The NMEA message is generated from a PC using a Python serial transmitter and sent to the FPGA through an **FTDI USB-TTL converter**.

---

## System Architecture


PC / Python Serial Sender
          |
          |
   FTDI USB-TTL Converter
          |
          |
       UART RX
          |
          v
+----------------------+
|    NMEA Parser FSM   |
|                      |
| - Start Detection    |
| - Field Extraction   |
| - Checksum Checking  |
+----------------------+
          |
          |
       UART TX
          |
          v
    PC Serial Monitor

---

# Features

- UART communication using 115200 baud rate
- FSM-based NMEA message parsing
- Serial ASCII data reception
- NMEA field extraction
- XOR checksum validation
- UART response transmission
- LED indicators for debugging

---

# Hardware Specification

| Component | Specification |
|-----------|---------------|
| FPGA Board | Digilent Zybo |
| FPGA Device | XC7Z010 |
| Clock Frequency | 125 MHz |
| Communication Interface | UART |
| UART Converter | FTDI USB-TTL |
| Baud Rate | 115200 bps |

---

# NMEA Processing Flow


UART RX
   |
   v
Receive ASCII Character
   |
   v
Detect '$' Start Character
   |
   v
Read NMEA Fields
   |
   v
Calculate XOR Checksum
   |
   v
Compare Received Checksum
   |
   v
Transmit Result Through UART TX

---

# Module Description

## 1. UART RX

The UART receiver converts serial data from FTDI into 8-bit parallel data.

Functions:

- Detect UART start bit
- Receive 8-bit ASCII data
- Generate `rx_ready` signal when a byte is received

Output:


rx_data
rx_ready

---

## 2. NMEA Parser FSM

The main processing module responsible for interpreting the received NMEA sentence.

FSM States:

| State | Function |
|---|---|
| IDLE | Waiting for NMEA start character |
| START | Detect beginning of message |
| READ_FIELD | Extract NMEA data fields |
| CHECKSUM | Validate received checksum |
| DONE_OUTPUT | Send processed data |

---

## 3. Checksum Validator

The checksum module calculates the XOR value of the received NMEA message and compares it with the checksum provided in the message.

Output:


checksum_valid_flag
checksum_error_flag

---

## 4. UART TX

UART transmitter sends processed data back to the PC.

UART frame format:


Start Bit (0)
      |
8-bit Data
      |
Stop Bit (1)

---

# Project Structure


FPGA_NMEA_Parser/
│
├── src/
│   ├── nmea_parser.v
│   ├── uart_rx.v
│   ├── uart_tx.v
│   └── checksum_validator.v
│
├── simulation/
│   └── nmea_parser_tb.v
│
├── constraints/
│   └── zybo.xdc
│
└── python/
    └── nmea_sender.py

---

# Implementation Steps

## FPGA Implementation

1. Open the project using Vivado
2. Select Zybo FPGA board
3. Add Verilog source files
4. Add the Zybo constraint file (.xdc)
5. Run:
   - Synthesis
   - Implementation
   - Generate Bitstream
6. Program the FPGA

---

## Serial Communication

Install Python serial library:

```bash
pip install pyserial

Run:
python nmea_sender.py

The Python program sends NMEA sentences through FTDI USB-TTL to the FPGA.
Example NMEA Data
Input:
$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0*4F

Processing:
UART RX
   |
   v
NMEA Parser FSM
   |
   v
Checksum Validation
   |
   v
UART TX Response

LED Debug Indicator
LED	Function
LED0	FSM status indicator
LED1	Checksum valid
LED2	Checksum error
LED3	UART RX activity


Challenges and Solutions
1. UART Communication
Problem:
The Zybo board required an external serial interface for communication.
Solution:
FTDI USB-TTL converter was used as a UART RX/TX bridge between PC and FPGA.
2. Constraint Configuration
Problem:
The initial implementation used an incorrect XDC constraint file from another Zybo variant.
Solution:
The constraint file was updated according to the actual Zybo board pin mapping.
3. UART and Parser Debugging
Problem:
It was difficult to identify whether the issue came from hardware, UART communication, or parser logic.
Solution:
The system was tested step-by-step:
UART RX
   |
NMEA Parser FSM
   |
Checksum Validation
   |
UART TX

LED indicators and serial monitoring were used during debugging.
Result
The FPGA successfully receives NMEA messages through UART communication, processes the message using an FSM-based parser, validates the checksum, and transmits processed data back through UART.
Conclusion
This project demonstrates the implementation of a real-time NMEA Parser on FPGA using UART communication and FSM-based processing.
The system integrates serial communication, digital design, and hardware-based data processing to create an embedded FPGA application capable of handling structured NMEA data.