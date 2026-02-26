# Generic 6551 ACIA (Asynchronous Communications Interface Adapter)

As described in the [main page](index.md), the device can be used in polling
and in full-featured mode (where the latter is recommended). Required wiring 
differs for these two modes. The wiring diagrams can be found below.

## Notes

- DCDB (Data Carrier Detect) must be tied to ground to make RxD work.
- CTS (Clear To Send) must be tied to ground to make TxD work.
- DSRB (Data Set Ready) is unused, but should not be left floating (connect it to
  either +5V or GND, using a resistor).

Address decoding depends on the exact memory layout that you have implemented for
your computer. When following Ben Eater's tutorial setup, the device's address
will be at $5000.

XTAL can be:
- passive 1.8432 Mhz crystal, series resonance, on XTAL1/XTAl2,
  without any other components (like the resistor and capacitor
  as used with a W65C51N IC).
- active 1.8432 Mhz crystal module, with its output connected to
  XTAL1, leaving XTAL2 fully floating.

## Polling mode

```text
     W65C02 CPU                            UM6551 ACIA
    ┌──────────┐                          ┌──────────┐
    │          │                          │ GND      │──── GND
    │  A12     │──── address decoding ───►│ CS0      │
    │  A14-A15 │──── for chip select ────►│ CS1B     │
    │          │                          │ RESB     │◄─── RESET
    │          │                          │ RxC      │──── n/c
    │          │                          │ XTAL1/2  │◄─── 1.8432 MHz
    │          │                          │ RTSB     │──── n/c
    │          │                          │ CTSB     │──── GND
    │          │                          │ TxD      │◄─── RS232 TxD
    │          │                          │ DTRB     │──── n/c 
    │          │                          │ RxD      │───► RS232 TxD
    │  A0      │──── register select ────►│ RS0      │
    │  A1      │──── register select ────►│ RS1      │
    │          │                          │          │
    │          │                          │ Vcc      │──── +5V
    │          │                          │ DCDB     │──── GND 
    │          │                          │ DSRB     │──── GND 
    │  D0-D7   │◄────── data bus ─────────│ D0-D7    │
    │  IRQB    │──── n/c          n/c ────│ IRQB     │
    │  PHI2    │────── system clock ─────►│ PHI2     │
    │  R/WB    │─────── read/write ──────►│ R/WB     │
    └──────────┘                          └──────────┘
```

## Full-feature mode

This implementation uses various techniques to make the serial connection rock solid:

- **IRQ-driven RX and TX**: incoming bytes are buffered by the IRQ handler,
  and outgoing bytes are drained from the write buffer by the IRQ
  handler when the transmitter is ready. No polling required.
- **Read buffer**: circular 256-byte buffer for incoming bytes, so data is
  not lost when bytes arrive faster than the application processes them.
- **Write buffer**: circular 256-byte buffer for outgoing bytes. The
  application queues bytes without waiting; the IRQ handler transmits
  them one by one as the ACIA becomes ready (TXEMPTY).
- **Hardware flow control**: RTS signalling via a VIA GPIO pin, to tell the remote
  side to stop sending when the read buffer is filling up.

For the rationale behind using a GPIO pin, and not the IC's RTSB pin for driving
RTS for hardware flow control, see [the hardware flow control document](hardware_flow_control.md).

```text
     W65C02 CPU                            UM6551 ACIA
    ┌──────────┐                          ┌──────────┐
    │          │                          │ GND      │──── GND
    │  A12     │──── address decoding ───►│ CS0      │
    │  A14-A15 │──── for chip select ────►│ CS1B     │
    │          │                          │ RESB     │◄─── RESET
    │          │                          │ RxC      │──── n/c
    │          │                          │ XTAL1/2  │◄─── 1.8432 MHz
    │          │                          │ RTSB     │──── n/c
    │          │                          │ CTSB     │──── GND
    │          │                          │ TxD      │◄─── RS232 TxD
    │          │                          │ DTRB     │──── n/c
    │          │                          │ RxD      │───► RS232 TxD
    │  A0      │──── register select ────►│ RS0      │
    │  A1      │──── register select ────►│ RS1      │
    │          │                          │          │
    │          │                          │ Vcc      │──── +5V
    │          │                          │ DCDB     │──── GND 
    │          │                          │ DSRB     │──── GND 
    │  D0-D7   │◄────── data bus ─────────│ D0-D7    │
    │  IRQB    │◄─────── interrupts ──────│ IRQB *)  │
    │  PHI2    │────── system clock ─────►│ PHI2     │
    │  R/WB    │─────── read/write ──────►│ R/WB     │
    └──────────┘                          └──────────┘

     I/O *)
    ┌──────────┐
    │ GPIO PIN │───► RS232 RTS (directly drives remote CTS, active low, 1 = stop)
    └──────────┘
```
***) Differences in wiring, compared to the polling mode wiring:**

- IRQB is connected to the IRQB pin on the CPU.
- A VIA GPIO pin drives the RS232 RTS line for flow control. The pin to use must
  be set in the [build configuration](index.md).

**About the IRQB connection:**
 
- Be sure to add a pull-up resistor to IRQB on the CPU. The IRQB pin on
  the ACIA is "open drain", which means it is not driving the IRQB pin
  high when there is no IRQ to communicate. The pull up handles this.
- For good isolation (when multiple devices are connected to IRQB), add
  a diode (anode pointing to the CPU, kathode - striped side - to the
  ACIA) between ACIA and CPU. Ben uses SB140 diodes for this. I didn't
  have those on stock myself, and went for a 1N5819 instead, which seems
  to work fine.
