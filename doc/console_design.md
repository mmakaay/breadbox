# Console Layer Design for 65C02 System

## Overview

This document describes the design decisions and implementation strategy for the `console` component in the 65C02-based system.

The console is a **text abstraction layer** that sits above device drivers (UART, LCD) and provides a uniform interface for text output.

It is **not** a full TTY implementation. It does not include:

* Line editing
* ANSI parsing
* Terminal emulation
* Job control

It provides:

* Text output
* Cursor tracking
* Optional scrolling
* Optional framebuffer

---

# Layered Architecture

```
Application (Monitor / BASIC / Kernel)
        ↓
Console Layer
        ↓
Device Driver (UART / LCD)
        ↓
Hardware
```

The UART driver remains binary-clean.
The console layer handles text semantics.

---

# Configuration Model

Console behavior is defined in YAML:

## Serial Console Example

```yaml
CONSOLE:
  component: console
  device: SERIAL
  width: 80
  height: 25
  buffered: false
```

## LCD Console Example

```yaml
CONSOLE:
  component: console
  device: LCD
  width: 20
  height: 4
  buffered: true
```

### Meaning of Fields

* `device`: logical dependency (SERIAL or LCD)
* `width`: logical console width
* `height`: logical console height
* `buffered`: whether a RAM framebuffer is used

---

# Console Modes

## 1. Stateless Console (Serial)

Used for UART-backed terminals.

Characteristics:

* No framebuffer
* Tracks cursor position only
* Emits characters directly to UART
* Terminal handles scrolling

Memory usage:

* `cursor_row`
* `cursor_col`
* `width`
* `height`

Total: a few bytes.

No screen redraws are performed.

### Rationale

At 19,200 baud:

* ~1920 bytes/sec
* 80×25 screen = 2000 bytes
* Full redraw ≈ 1 second

Therefore maintaining a serial framebuffer is inefficient and unnecessary.

---

## 2. Buffered Console (LCD)

Used for HD44780-type LCD displays.

Characteristics:

* RAM framebuffer of `width × height` bytes
* Scroll implemented in RAM
* LCD is redrawn from buffer
* Device driver remains simple

Example memory usage:

| Display | Buffer Size |
| ------- | ----------- |
| 15×2    | 30 bytes    |
| 16×4    | 64 bytes    |
| 20×4    | 80 bytes    |

The buffer size is fixed at assembly time from configuration.

---

# Why Use a Framebuffer for LCD?

Although the HD44780 controller supports reading DDRAM, buffering in RAM is preferred because:

* Fewer LCD command cycles
* Fewer address-set operations
* Simpler logic
* Hardware-independent console logic
* Deterministic redraw behavior
* Easier support for multiple display geometries

LCD operations are slow (~37µs per command).
RAM operations are significantly faster.

Buffering reduces total LCD command count during scroll operations.

---

# Scroll Implementation Strategy (Buffered Mode)

## Generic Algorithm

1. Move rows 1..(height-1) up by one row in RAM
2. Clear last row in RAM
3. Redraw all rows to LCD

This works for any configured size.

---

## Example: 20×4 Scroll (Unrolled Offsets)

Buffer layout:

```
Row 0: offset 0
Row 1: offset 20
Row 2: offset 40
Row 3: offset 60
```

Scroll operation:

* Copy 20 bytes from row 1 → row 0
* Copy 20 bytes from row 2 → row 1
* Copy 20 bytes from row 3 → row 2
* Clear row 3
* Redraw all 4 rows

All offsets are compile-time constants.

No runtime multiplication required.

---

# Driver API Requirements

The console requires a minimal device API:

```
device_putc(A)        ; Output character
device_set_cursor(X,y)
device_clear()
```

The console owns:

* Cursor logic
* Wrapping
* Scrolling
* Newline handling

The device driver remains dumb and reusable.

---

# Newline Policy

Recommended internal policy:

* `'\n'` → move to next line, column 0
* `'\r'` → optional: treat as column 0
* Serial backend emits `"\r\n"`
* LCD backend repositions cursor only

All higher-level software should use `'\n'`.

---

# Why Width/Height Are Compile-Time

Width and height are assembly-time constants because:

* Memory must be reserved statically
* No dynamic allocation is used
* 65C02 benefits from precomputed offsets
* Runtime multiplication is avoided

Jinja template expands:

```
BUFFER_SIZE = WIDTH * HEIGHT
```

and emits specialized code.

---

# Design Decisions Summary

## Serial Console

* No framebuffer
* Logical dimensions only
* Cursor tracking
* No redraw logic
* Efficient at low baud rates

## LCD Console

* Fixed-size RAM framebuffer
* Scroll implemented in RAM
* Full redraw on scroll
* Device-independent console logic

---

# Future Extensibility

This architecture supports:

* 2×15 LCD
* 16×4 LCD
* 20×4 LCD
* Serial console
* Future video display device
* Multiple console backends

The console abstraction isolates text behavior from hardware details.

---

# Final Recommendation

For this 65C02 system:

* Keep UART binary-clean
* Use stateless console for SERIAL
* Use buffered console for LCD
* Fix width/height at assembly time
* Generate optimized code via Jinja

This provides:

* Clean layering
* Predictable memory usage
* Efficient execution
* Scalable design
