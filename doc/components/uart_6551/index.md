# BREADBOX component: UART 6551

## Features

Drives a 6551-family UART (a.k.a. ACIA) for RS232 serial communication. The ACIA is
memory-mapped directly on the CPU bus (active-low chip select address decoded
from the address lines).

Features:

- **Multiple IC models** (W65C51N, UM6551, R6551, generic)
- **Configurable baud rate**
- **Polling-based RX/TX** (not recommended)
- **IRQ-based RX/TX** (recommended), enabling:
  - **Hardware flow control** (RTS, signals the remote side to stop sending)
  - **RX read buffer**
  - **TX send buffer** (when supported by the hardware)

## Model-specific documentation

For a wiring schema and model-specific information, take a look at:

- [WDC W65C51N](type_w65c51n.md) (different TX behavior, to work around a hardware bug)
- [Generic](type_generic.md) (UM6551, R6551, or other ICs that follow the same specification)

## Configuration

### Polling mode

In polling mode, characters are sent and received one by one. Your code must
ensure the UART is ready before each operation. This works for low-speed
communication, but at higher speeds incoming bytes will likely be lost.

> This mode is **not recommended**. It is included because it matches the early
> UART tutorials in Ben Eater's videos, so you can reproduce those results.

```yaml
UART:
  component: uart_6551   # Driver implementation
  type: w65c51n          # IC model: `w65c51n`, `um6551`, or `6551` (generic type, default)
  address: $5000         # Memory-mapped base address
  baudrate: 19200        # Supported: 1200, 2400, 3600, 4800, 7200, 9600, 19200 (default)
```

### Standard full-featured mode

The recommended setup enables IRQ handling (which unlocks RX/TX buffering) and
hardware flow control. Together, these provide a reliable connection between the
UART and the remote system.

```yaml
BUS:
  component: ....        # A bus component (e.g. VIA) that provides GPIO pins

UART:
  component: uart_6551   # Driver implementation
  type: w65c51n          # IC model: `w65c51n`, `um6551`, or `generic`
  address: $5000         # Memory-mapped base address
  baudrate: 19200        # Supported: 1200, 2400, 3600, 4800, 7200, 9600, 19200 (default)
  irq: on                # Enable IRQs (required for buffering)
  rts:                   # GPIO pin for RTS (hardware flow control)
    bus: BUS
    pin: PA0
```

Without `irq`, the driver falls back to polling mode:

- Polling must be used for sending and receiving
- RX and TX buffering are disabled
- RTS is disabled (requires the RX read buffer)

Without `rts`, only hardware flow control is disabled. The system cannot signal
the sender to pause when the RX buffer fills up, so received bytes may be lost.
A lower baud rate reduces the risk, but is a workaround, not a fix.
