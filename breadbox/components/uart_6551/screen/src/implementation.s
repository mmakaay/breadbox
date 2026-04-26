.feature string_escapes

.include "CORE/coding_macros.inc"
.include "stdlib/math/fmtdec.inc"
.include "stdlib/io/print.inc"
.include "__keyboard/constants.inc"

.constructor {{ my("init") }}

.macro SEND _character
    ; Send the provided character.
    lda #_character
    jsr {{ provider_device.api("write") }}
.endmacro

.macro ESCAPE
    ; Send the preamble of an ANSI escape sequence.
    SEND KEY_ESC  ; escape key
    SEND '['
.endmacro

.segment "ZEROPAGE"

    ; -------------------------------------------------------------------
    ; Public terminal-geometry state.
    ;
    ; Initialized at boot from the component's `width` / `height`
    ; config values, and refreshable at runtime via SCREEN::query_size.
    ; The TTY layer reads these for wrap-aware cursor positioning.
    {{ zp_def("term_width") }}: .res 1
    {{ zp_def("term_height") }}: .res 1

.segment "KERNALROM"

    ; =====================================================================
    ; Initialize terminal modes and geometry.
    ;
    ; - Forces DECAWM on (auto-wrap), so the TTY layer can rely on the
    ;   terminal wrapping printable bytes past the right margin. Most
    ;   terminals power on with DECAWM enabled, but minicom does not.
    ; - Initializes the public term_width / term_height ZP variables
    ;   from the component's config defaults.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my("init") }}
        lda #{{ width }}
        sta {{ zp("term_width") }}
        lda #{{ height }}
        sta {{ zp("term_height") }}
        ESCAPE
        SEND '?'
        SEND '7'
        SEND 'h'   ; DECAWM on
        rts
    .endproc

    ; =====================================================================
    ; Clear the screen.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("clr") }}
        ESCAPE
        SEND '2'
        SEND 'J'
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor to the home position.

    .proc {{ api_def("home") }}
        ESCAPE
        SEND 'H'
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor position.
    ;
    ; In:
    ;   X = the row to move to (0-indexed)
    ;   Y = the column to move to (0-indexed)
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ api_def("move_cursor") }}
        tya
        pha

        ; Format the row number (1-indexed).
        inx
        stx fmtdec::value
        jsr fmtdec

        ; Send escape code up to the column number.
        ESCAPE
        PRINT_PTR {{ provider_device.api("write") }}, fmtdec::decimal
        SEND ';'

        ; Format the column number (1-indexed).
        pla
        tay
        iny
        sty fmtdec::value
        jsr fmtdec

        ; Finish the escape code with the column number.
        PRINT_PTR {{ provider_device.api("write") }}, fmtdec::decimal
        SEND 'H'

        rts
    .endproc

    ; =====================================================================
    ; Move to a new line.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("newline") }}
        SEND '\r'
        SEND '\n'
        rts
    .endproc

    ; =====================================================================
    ; Delete character before cursor position.
    ;
    ; In-row only; does not cross visual wrap boundaries. Canonical-mode
    ; line editing (which needs to cross wraps) is handled in the TTY
    ; layer using direct CUP positioning that bypasses this proc.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("backspace") }}
        ESCAPE      ; Move cursor left.
        SEND 'D'
        SEND ' '    ; Delete character by typing a space over it.
        ESCAPE      ; Move cursor left.
        SEND 'D'
        rts
    .endproc

    ; =====================================================================
    ; Write a character to the display at the current cursor position.
    ;
    ; In:
    ;   A = data byte to write
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write") }}
        tax                   ; sets N from bit 7 of A
        bpl @regular          ; bit 7 clear → not a special key, fast path

        cmp #KEY_LEFT+1       ; past the arrow key codes?
        bcs @regular          ; handle as regular

        and #$03              ; mask to 0..3 (since arrow key codes are $80..$83)
        tax                   ; make value available in x for indexing the table
        lda arrow_escapes,x   ; look up the escape letter for the arrow key
        pha                   ; write the escape key code, before writing the arrow key code,
        ESCAPE
        pla
        ; fallthrough for the final write

    @regular:
        jmp {{ provider_device.api("write") }}
    .endproc

    arrow_escapes:
        .byte 'A'   ; KEY_UP    (128, index 0)
        .byte 'B'   ; KEY_DOWN  (129, index 1)
        .byte 'C'   ; KEY_RIGHT (130, index 2)
        .byte 'D'   ; KEY_LEFT  (131, index 3)

    ; =====================================================================
    ; Send a DSR (Device Status Report) request for the current cursor
    ; position.
    ;
    ; This proc only SENDS the ESC[6n request bytes; it does not wait
    ; for the response. The terminal's reply (ESC[<row>;<col>R) arrives
    ; in the UART RX ring and is parsed transparently by the keyboard
    ; layer's read proc, which stashes the row/col in the public
    ; KEYBOARD::dsr_row / dsr_col ZP slots and sets dsr_pending=1.
    ;
    ; Callers that want to know the cursor position should:
    ;   1. Clear KEYBOARD::dsr_pending.
    ;   2. Call this proc.
    ;   3. Poll KEYBOARD::read in a loop with a timeout, processing any
    ;      user keystrokes that arrive (so they're not lost), until
    ;      KEYBOARD::dsr_pending becomes 1.
    ;   4. Read KEYBOARD::dsr_row / dsr_col.
    ;
    ; Out:
    ;   C = 0 (async — caller must wait for KEYBOARD::dsr_pending)
    ;   A = clobbered

    .proc {{ api_def("query_cursor_pos") }}
        ESCAPE
        SEND '6'
        SEND 'n'
        clc
        rts
    .endproc

    ; =====================================================================
    ; Send a DSR request for the terminal size, leaving the cursor
    ; visually undisturbed.
    ;
    ; Saves the cursor (ESC[s), moves to (999;999) so the terminal
    ; clamps to (height; width), issues the DSR request (ESC[6n), and
    ; restores the cursor (ESC[u). The response carries the actual
    ; terminal dimensions.
    ;
    ; Like query_cursor_pos, this proc only sends the request bytes;
    ; the caller must wait for the response via KEYBOARD::dsr_pending
    ; (see query_cursor_pos for the polling pattern).
    ;
    ; Out:
    ;   C = 0 (async — caller must wait for KEYBOARD::dsr_pending then
    ;   apply the response to term_width/term_height)
    ;   A = clobbered

    .proc {{ api_def("query_size") }}
        ESCAPE
        SEND 's'
        ESCAPE
        SEND '9'
        SEND '9'
        SEND '9'
        SEND ';'
        SEND '9'
        SEND '9'
        SEND '9'
        SEND 'H'
        ESCAPE
        SEND '6'
        SEND 'n'
        ESCAPE
        SEND 'u'
        clc
        rts
    .endproc
