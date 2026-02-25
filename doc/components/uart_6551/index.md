# BREADBOX component: UART 6551

## Features

This component can be used to add a 6551-family UART (a.k.a. ACIA) to your
computer. The component provides various features:

- **Multiple IC models** (W65C51N, UM6551, generic)
- **Configurable baud rate** (the communication speed)
- **Polling-based RX/TX** handling (not recommended)
- **IRQ-based RX/TX** handling (recommended), enabling advanced features:
  - **Hardware flow control** (RTS, signalling remote side to stop sending data)
  - **RX read buffer**
  - **TX send buffer** (when supported by the hardware)

## Configuration

### Polling mode

In polling mode, characters are sent and read one-by-one, and your code has to make sure that
the UART is ready for those operations. This is ok for low speed communication, but at higher
speeds, you will likely start losing incoming bytes (because new bytes come in before they
can be read). 

> This operation mode is therefore **not recommended**. The rationale for including this
> suboptimal driver, is that it matches the early UART communication tutorials in Ben Eater's
> videos, making it possible to reproduce the results.

```yaml
UART:
  component: uart_6551   # Selects the driver implementation
  type: w65c51n          # Selects the specific IC model (`w65c51n`, `um6551` or `generic`)
  address: $5000         # Memory-mapped base address for the device
  baudrate: 19200        # recognized are: 1200, 2400, 3600, 4800, 7200, 9600, 19200
```

### Standard full-featured mode

The recommended way to use the UART, is to enable IRQ handling (which in turn enables buffering
of incoming and/or outgoing data) and hardware flow control. These features combined arrange a
trustworthy connection between the UART and the remote system connecting to the UART.

```yaml
BUS:
  component: ....        # A BUS component (e.g. a VIA) that provides GPIO pin functionality.
  
UART:
  component: uart_6551   # Selects the driver implementation
  type: w65c51n          # Selects the specific IC model (`w65c51n`, `um6551` or `generic`)
  address: $5000         # Memory-mapped base address for the device
  baudrate: 19200        # recognized are: 1200, 2400, 3600, 4800, 7200, 9600, 19200
  irq: on                # Enable the use of IRQs, enabling buffering features
  rts:                   # Define a GPIO pin, enabling hardware flow control
    bus: BUS
    pin: PA0
```

When omitting or disabling the `irq` feature, the setup basically has to be used in polling mode:

- Polling must be used for sending and receiving data
- RX and TX buffering are disabled
- RTS is disabled (this requires the RX read buffer)

When omitting the `rts` configuration, only hardware flow  control is disabled. As a result, the
system cannot push back (when RX buffer is filling up too fast), and when the RX buffer runs out
of space, received bytes will be lost.

Possibly, problems with reading data reliably can be fixed by selecting a lower baud rate, which
will bring down the rate of incoming data. That of course, should not be the route to follow.
