# Hardware flow control (RTS-based)

## Only flow control for pausing inbound data

Only inbound flow control is implemented (we tell the remote to stop).
Outbound flow control (remote tells us to stop) is not (yet) implemented,
but the write buffer would make it possible: the remote could signal us to
pause, and we would simply stop draining the TX buffer until cleared.

## RTS signalling

The component code was initially tested with the UM6551, which does have a
built-in RTSB pin. Options for the output of this pin:

- **low** = remote side can send
- **high** = remote side sending halted

Implementing RTS using the RTSB pin was not possible, unfortunately.

### Issue with using the RTSB pin

The only control option to raise this RTSB pin, also disables the UART's
transmitter, meaning that bytes cannot be sent out to the remote side while
RTSB is kept high.

This behavior has also been observed for the W65C22N, most noticeably in
Ben Eater's tutorial video about implementing flow control. Pasting data into
the serial terminal (he pastes in a large BASIC program) results in the full
program be loaded (so RX works), but during the pasting operation, not all
bytes are echoed back to the terminal (so TX loses bytes).

### Issue with abusing DTR pin for controlling the RTS signal

The IC also has a DTR pin (Data Terminal Ready, flagging the remote side that
this side is connected and ready). An experiment was done to see if abusing
this pin for the RTSB signalling was possible, but this failed. The problem
was that raising this pin disables the receiver and IRQs, which can cause lost
bits on the incoming data.

### Solved by using a GPIO pin

Since there is no pin on the UART itself that can be used for clean hardware
flow control, we have to connect the remote side's CTS pin to a GPIO pin
on the computer, e.g. a pin on an interface adapter like the W65C22 VIA,
making that pin an RTS signal source.

### TL;DR:

The UART IC has no usable pin for driving the RTS signal, but we can use a
GPIO pin on an interface adapter to perform its function.
