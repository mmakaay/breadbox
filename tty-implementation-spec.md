# TTY Implementation Spec

## Goal

Add a TTY layer to the existing 6502 KERNAL-style I/O stack. The TTY sits
between the application and the screen/keyboard layers, and provides:

1. **Canonical mode (on/off)** — line-buffered input with editing, vs. raw
   pass-through.
2. **Echo (on/off)** — orthogonal to canonical mode; controls whether typed
   input is automatically echoed to the screen.
3. **A `readline`-style entry point** that takes a prompt as an argument, so
   the prompt can be redrawn on `^R` (reprint) and `^L` (clear+redraw).

This is **not** a POSIX termios reimplementation. We are deliberately ignoring
parity, flow control, signal generation, tab/CR/LF translation flags,
modem-control bits, and the 30+ other settings POSIX defines. If a future need
arises we add it then.

## Layering

The stack, top to bottom. **Both output and input go through the TTY layer.**

```
  Application
     │
     │ TTY::write (output)        TTY::readline / TTY::read (input)
     ▼                                   │
  TTY layer  ──── output translation:    │
     │              CR/LF normalization, │
     │              backspace key alias  │
     │           input handling:         │
     │              line discipline,     │
     │              echo gating,         │
     │              type-ahead buffer    │
     │                                   │
     ▼                                   ▼
  Screen layer  ──── SCREEN::write, SCREEN::newline, SCREEN::backspace,
     │                SCREEN::clr, SCREEN::clreol;
     │                owns cursor state (echo_col, term_width)
     │
     ▼
  UART driver  /  LCD driver  /  keyboard driver
```

**The TTY is on both paths.** On output, it does byte-level translation
(CR/LF normalization, backspace code aliasing) and then calls down to the
screen layer's primitives. On input, it runs the line discipline and uses
the same screen-layer primitives to echo (via `TTY::write`). The
application never calls the screen layer directly; everything goes through
the TTY.

**Output translation is stateful but mode-independent.** `TTY::write` does
its CR/LF and backspace translation regardless of canonical/echo flags —
those flags only affect the input path. The TTY may keep small amounts of
state for output processing (`previous_was_cr` for `\r\n` collapsing); this
state lives in the TTY layer alongside the input-path state.

**The screen layer owns cursor state** (`echo_col`, optionally `echo_row`,
`term_width`). Every byte that reaches the terminal — application output
via `TTY::write`, or TTY echo of typed input — eventually calls the screen
layer's primitives, which update `echo_col` as a side effect. The TTY
itself does not track cursor position; it just calls down.

**`echo_col` is initialized once** when the screen layer comes up, and is
maintained continuously thereafter. The TTY does not set or reset it. When
the application prints a prompt (or `TTY::readline` prints one on the app's
behalf via `TTY::write` → screen layer), `echo_col` advances naturally to
wherever the prompt ends.

### Output translation (the existing `TTY::write`)

The TTY's output path normalizes a few byte-level conventions before
handing to the screen layer:

- **CR/LF collapse**: `\r`, `\n`, and `\r\n` all map to a single
  `SCREEN::newline`. The TTY tracks `previous_was_cr` to suppress the LF
  half of a CR+LF pair. The screen layer only ever sees "newline."
- **Backspace alias**: both `$08` (BS) and `$7F` (DEL) map to
  `SCREEN::backspace`. The screen layer only knows one backspace
  operation; the TTY hides which key code triggered it.
- **Everything else**: passed through to `SCREEN::write` unchanged.

This translation is what makes the screen layer's API minimal: it doesn't
need to care about line-ending conventions or which terminal sends which
erase code. As more translations are needed (tab expansion, control-char
display, etc.) they go here.

## TTY State

Inside the `TTY` namespace; no `tty_` prefixes needed since cc65 namespacing
handles disambiguation. Zero page where possible for the hot ones.

```
flags              ; bit 0: BIT_CANONICAL_ON
                   ; bit 1: BIT_ECHO_ON
                   ; (other bits reserved)

line_buf           ; current-line buffer, ~80 bytes
line_len           ; current length, 0..line_buf_max

completed_buf      ; ring buffer for completed lines, ~128 bytes
completed_head
completed_tail     ; standard ring-buffer indices

readline_active    ; flag: 1 while inside TTY::readline, 0 otherwise
prompt_ptr         ; pointer to current prompt string (only valid when
                   ; readline_active = 1)

previous_was_cr    ; existing flag for \r\n collapse in TTY::write
```

`line_buf_max` ≈ 80. We don't need POSIX's MAX_CANON of 255; nobody types
that much, and we're saving RAM. If the buffer fills, beep (`\a`) and ignore
further printable input until backspace or Enter.

The completed-line ring is what enables type-ahead. When the user presses
Enter, the current line gets pushed onto this ring as a `\n`-delimited
sequence of bytes; the line buffer resets to empty; further input continues
to accumulate immediately into the (now-empty again) line buffer.

## Modes

### Canonical mode ON, echo ON (the default for interactive use)

This is the line-editing mode. On each input byte:

- **Printable (`>= $20`, `!= $7F`)**: append to `line_buf` if not full;
  call `TTY::write` to echo.
- **Backspace (`$08` or `$7F`)**: if `line_len > 0`, pop from buffer and
  call `TTY::write` with the same byte (`TTY::write` translates either
  code to `SCREEN::backspace`). Otherwise ignore (or beep).
- **Enter (`$0D` or `$0A`)**: append `\n` to `completed_buf`, reset
  `line_len = 0`, call `TTY::write` with `\n` to advance the cursor visually
  (`TTY::write` translates to `SCREEN::newline`).
- **`^U` (kill, `$15`)**: empty the line buffer, then redraw — fall through
  to the `^R` handler with an emptied buffer.
- **`^R` (reprint, `$12`)**: emit `\r\n` via `TTY::write`, re-emit prompt
  via `PRINT TTY::write, prompt_ptr`, re-emit `line_buf` contents
  byte-by-byte via `TTY::write`. Cursor ends at end of buffer; `echo_col`
  is automatically correct because the screen layer tracked every byte
  underneath.
- **`^L` (clear + redraw, `$0C`)**: call `SCREEN::clr`, re-emit prompt via
  `PRINT TTY::write, prompt_ptr`, re-emit `line_buf` contents via
  `TTY::write`.
- **`^C` (`$03`)**: out of scope for now. Reserve the byte; document as
  TODO. When implemented, will probably abort the current readline and
  signal the app somehow.

### Canonical mode ON, echo OFF (password entry)

Same as above, but the `TTY::write` calls during *input echo* are
suppressed. Enter still emits `\n` via `TTY::write` so the cursor moves to
a fresh line. The prompt itself is still printed (echo-off applies only to
typed input, not to the prompt the TTY emits on the app's behalf).

The application is responsible for any "show stars instead" behavior —
that's not the TTY's job. The TTY just doesn't echo.

### Canonical mode OFF (raw)

The TTY does no input buffering and no editing. Each input byte is
delivered to the caller as soon as it arrives via `TTY::read`. There's no
readline in this mode.

Echo flag still applies: if echo is on in raw mode, every byte gets a
`TTY::write` call before being delivered to the caller; if off, no echo.

In raw mode, special characters (Enter, backspace, `^R`, etc.) are *not*
interpreted on input. They're just bytes to the caller. (Note that
`TTY::write` still does its output-side translation when echoing — so a
typed `\r` echoes as a newline via the CR/LF normalization. If the caller
wants byte-for-byte fidelity in echo, they need to disable echo and emit
the byte themselves via... well, via `TTY::write`, which is the only
output API. Acceptable for a 1980s-era system.)

## API

All entries use cc65 namespacing: `TTY::write`, `TTY::read`, etc. The
existing screen device's API is `SCREEN::write`, `SCREEN::backspace`,
`SCREEN::newline`, `SCREEN::clr`, etc. (verb-only, no putc/puts split).

### Configuration

Separate enable/disable entries per flag. Registers preserved across all
configuration calls (the existing `enable_canonical` / `disable_canonical`
implementations show the pattern: `pha`, manipulate `flags`, `pla`, `rts`).

```
TTY::enable_canonical    ; sets BIT_CANONICAL_ON in flags
TTY::disable_canonical   ; clears it
TTY::enable_echo         ; sets BIT_ECHO_ON in flags
TTY::disable_echo        ; clears it
```

No `set_flags` / `get_flags` accessor needed. Callers don't need to read
the flag state — they just enable or disable as needed. Internally, the
TTY's input-path code tests the bits directly against the `flags` variable.

### Output

```
TTY::write               ; A = byte; existing entry point.
                         ; CR/LF normalization (\r, \n, \r\n collapse to
                         ;   SCREEN::newline)
                         ; Backspace alias ($08 and $7F → SCREEN::backspace)
                         ; All other bytes → SCREEN::write
                         ; This is what the application calls for output.
```

For string output, callers use the existing `PRINT` macro:

```
PRINT TTY::write, my_string_ptr
```

No separate `TTY::puts` entry point.

### Input

```
TTY::read             ; raw single-byte read; blocks until a byte arrives;
                      ; honors echo flag; ignores canonical flag
                      ; returns byte in A

TTY::readline         ; canonical-mode line read with prompt
                      ; input:  ptr1 = pointer to prompt string (null-term)
                      ;         ptr2 = pointer to caller's line buffer
                      ;         A    = max length of caller's buffer
                      ; output: A    = actual length of returned line
                      ;         line bytes copied into caller's buffer
                      ;         (no trailing \n; caller knows length)
                      ;
                      ; Behavior:
                      ;   1. Set readline_active = 1, stash prompt ptr.
                      ;   2. Emit prompt: PRINT TTY::write, prompt_ptr
                      ;   3. If type-ahead bytes are buffered in line_buf
                      ;      from before readline was called, replay them
                      ;      via TTY::write (advances echo_col correctly via
                      ;      the screen layer underneath).
                      ;   4. Enter input loop: pull bytes from input source,
                      ;      handle per "Canonical mode ON" rules above.
                      ;   5. On Enter: copy line_buf to caller's buffer
                      ;      (truncated to caller's max length), set
                      ;      readline_active = 0, return.
                      ;
                      ; Requires canonical mode ON. If called with canonical
                      ; off, either error out or temporarily force canonical
                      ; for the duration of the call (pick one and document).
```

### Internal: input dispatch

When a byte arrives from the keyboard/UART (via ISR or polling), it goes to:

```
TTY::input_byte       ; A = byte (internal entry; not part of public API)
                      ; if BIT_CANONICAL_ON clear:
                      ;     deliver immediately to whoever is reading
                      ;     (single-byte queue or direct return)
                      ;     if BIT_ECHO_ON set: jsr TTY::write to echo
                      ; if BIT_CANONICAL_ON set:
                      ;     run through line-discipline state machine
                      ;     (printable → append + optional echo,
                      ;      backspace → pop + optional echo of $08,
                      ;      Enter → push to completed ring, etc.)
                      ;     echo only if BIT_ECHO_ON AND
                      ;       (readline_active OR we decide type-ahead
                      ;       echoes immediately — see below)
```

**Type-ahead echo decision: do NOT echo when `readline_active = 0`.**
Buffer silently. When `TTY::readline` is later called, it replays the
buffer after emitting the prompt. This avoids garbling the screen when
the app is mid-output, and gives the user a clean visual: prompt appears,
then their typed-ahead input appears after it, then they continue editing.

Backspace during type-ahead is silent — pop from buffer, no screen update.
The user sees the final state when readline replays.

## Screen Layer Notes

The screen-layer primitives the TTY relies on are listed in the Layering
section above. A few notes on what stays where:

- There is no `SCREEN::kill_line`. Implement `^U` inside the TTY as
  "empty buffer + reprint" — i.e. fall through to the same routine that
  handles `^R`, but with the line buffer pre-emptied. This avoids
  introducing a screen-layer call that's really a TTY-layer concern.

- The screen layer's wrap-crossing backspace (handled via `ESC[A` +
  `ESC[<w>G` + space + `ESC[<w>G` on the serial backend, or DDRAM
  manipulation on the LCD backend) is invoked by `SCREEN::backspace` and
  is invisible to the TTY. The TTY just calls `SCREEN::backspace` and
  trusts it to do the right thing.

- The screen layer is where `term_width` and `echo_col` live. If the TTY
  ever needs to know the column (it shouldn't, but if), it reads it via a
  read-only accessor — never writes it.

## What's NOT In Scope (Yet)

- Signal generation (`^C`, `^Z`, `^\\`)
- `^V` literal-next
- Werase (`^W`), reprint-history
- Tab expansion / CR-LF translation flags
- Flow control (`^S`/`^Q`)
- Multiple completed lines in flight beyond what the ring buffer naturally
  holds — no separate "line count" tracking
- Window-size change notifications (we query once at init; if the user
  resizes, behavior degrades gracefully but isn't corrected)
- Job control, session leadership, controlling-terminal concepts

If any of these become necessary, add them as separate flags or separate
calls; don't try to retrofit them into the canonical/echo/raw model.

## Implementation Order

1. **Skeleton + flags**: `flags` variable, `TTY::enable_canonical`,
   `TTY::disable_canonical`, `TTY::enable_echo`, `TTY::disable_echo`.
   No behavior yet, just state. (You already have the canonical pair.)
2. **`TTY::read` + raw mode**: simplest path. Pull from input source,
   optionally echo via `TTY::write`, return.
3. **Line buffer + canonical-mode echo**: printable bytes append + echo,
   backspace pops + echoes (which `TTY::write` translates to
   `SCREEN::backspace`). No Enter handling yet — just edit.
4. **Enter + completed-line ring**: pushing complete lines into the ring,
   `TTY::readline` pulling from it.
5. **Prompt parameter to `TTY::readline`**: emit prompt on entry via
   `PRINT TTY::write, prompt_ptr`, replay type-ahead buffer.
6. **`^R` reprint**: re-emit `\r\n` + prompt + line buffer.
7. **`^L` clear+redraw**: `SCREEN::clr` + prompt + line buffer.
8. **`^U` kill**: empty buffer + fall through to `^R` reprint.
9. **Type-ahead silent buffering**: gate echo on `readline_active`.
10. **Echo-off mode** (password entry): suppress echo calls but keep
    editing logic.

Each step is independently testable. After step 4 you have a usable line
reader; everything after is polish.

## Test Cases

- Type a line of length < terminal width, press Enter. Line returned correctly.
- Type a line longer than terminal width (terminal wraps). Backspace works
  across the wrap (depends on screen layer's wrap-crossing backspace).
- Press `^R` mid-line. `\r\n` + prompt + buffer reprinted, editing continues.
- Press `^L` mid-line. Screen cleared, prompt + buffer redrawn at top.
- Press `^U`. Buffer empties, prompt redrawn.
- Type ahead while app is doing other work. Bytes buffered silently. App
  calls `TTY::readline`. Prompt emitted, then type-ahead replayed, then
  cursor at end of replayed text. User can continue typing or backspace.
- Disable echo, call `TTY::readline`. User types, sees nothing. Backspace
  is silent. Enter still works, line returned correctly.
- Disable canonical mode, call `TTY::read` in a loop. Each byte returned
  immediately. Echo independently controllable.
- Buffer-full case: type 80 chars, 81st beeps and is ignored. Backspace
  still works.
- Async output during type-ahead: app prints via `TTY::write` while user is
  type-ahead-buffering. Output appears, type-ahead bytes do NOT appear
  yet (silent buffering). Later readline call replays cleanly.

## Open Questions for the Implementer

1. Where does `TTY::input_byte` get called from? Interrupt-driven (UART RX
   ISR) or polled (inside `TTY::read` / `TTY::readline`)? Polled is simpler;
   interrupt-driven is needed for true type-ahead while the app is busy.
   Pick one and document. Step 9 (silent type-ahead buffering) only does
   anything useful if input is interrupt-driven; with polling, bytes only
   arrive while the TTY is actively reading, so there's no type-ahead
   window to buffer.

2. Backspace and Enter key codes are decided: accept both `$08` and `$7F`
   for backspace (your existing `TTY::write` already does this), and
   accept `$0D` as Enter (translating to `\n` internally; ignore bare
   `$0A` or treat identically).

3. Resolved: `TTY::readline` does **not** clear the line buffer on entry.
   Whatever's already there is treated as type-ahead and replayed after
   the prompt (step 5 of `TTY::readline` behavior).

4. What happens if `TTY::readline` is called with canonical mode disabled?
   Suggest erroring out (return with carry set, or A = $FF length, or
   similar — pick a convention) rather than temporarily forcing canonical.
   The caller asked for raw, give them raw — they should be using
   `TTY::read` for that, not `TTY::readline`.
