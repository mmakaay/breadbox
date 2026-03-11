# Component: TTY device

Provides a device that implements an abstraction layer on top of keyboard
and screen devices. It implements some of the typical TTY functionalities,
like line discipline for standard terminal use.

The device must be linked to a keyboard device, and a screen device.
The keyboard is used by the end user to enter data (e.g. a physical keyboard
or typing over an RS232 connection from a terminal emulator). The screen
device is a textual display used to present output to the end-user (e.g.
an RS232 connection or an LCD).
