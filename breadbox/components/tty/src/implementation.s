.feature string_escapes

.include "CORE/coding_macros.inc"
.include "stdlib/io/print.inc"
.include "__keyboard/constants.inc"

.constructor {{ my("init") }}

; Maximum length of the canonical-mode editing buffer.
; Any printable input beyond this beeps and is ignored until the user
; backspaces or presses Enter. Sized for a few rows of an 80-col
; terminal, which is plenty for typical command lines and lets the
; editor cross visual wraps comfortably.
LINE_BUF_MAX = 240

.segment "ZEROPAGE"

    ; -------------------------------------------------------------------
    ; Public zero-page API for TTY::readline.
    ;
    ; Callers set these once before the first readline call and leave
    ; them stable across all subsequent (non-blocking) readline calls
    ; until the line is delivered.
    ;
    ;   prompt      = pointer to a null-terminated prompt string
    ;   line_buffer = pointer to the caller's line buffer
    ;   line_max    = max number of bytes the buffer can hold
    {{ zp_def("prompt") }}: .res 2
    {{ zp_def("line_buffer") }}: .res 2
    {{ zp_def("line_max") }}: .res 1

    ; -------------------------------------------------------------------
    ; Internal state.
    {{ var("previous_was_cr") }}: .res 1
    {{ var("flags") }}: .res 1
    {{ var("read_byte") }}: .res 1
    {{ var("line_len") }}: .res 1            ; Bytes currently in line_buf
    {{ var("cursor_pos") }}: .res 1          ; Edit cursor position (0..line_len)
    {{ var("drawn_len") }}: .res 1           ; Bytes laid down by the last redraw
    {{ var("readline_active") }}: .res 1     ; 1 while a readline is in progress
    {{ var("scratch_x") }}: .res 1           ; Temp X save during inner calls
    {{ var("scratch_len") }}: .res 1         ; Temp length save during copy

.segment "KERNALRAM"

    ; The internal editing buffer. Lives in RAM (not ZP) since 240 bytes
    ; is too large for zero page.
    {{ var("line_buf") }}: .res LINE_BUF_MAX

.segment "KERNALROM"

    ; Option flags
    BIT_CANONICAL_ON = %00000001   ; Enable canonical mode
    BIT_ECHO_ON      = %00000010   ; Echo input characters

    ; =====================================================================
    ; Initialize the TTY.
    ;
    ; Enables canonical mode and echoing of input characters.

    .proc {{ my("init") }}
        ; Explicitly zero state. The 6502 doesn't clear SRAM at power-on,
        ; so we cannot rely on ZP starting at 0. Without this, garbage in
        ; readline_active would skip the first prompt emission, garbage
        ; in line_len/cursor_pos would corrupt the first readline call.
        lda #0
        sta {{ var("flags") }}
        sta {{ var("previous_was_cr") }}
        sta {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        sta {{ var("drawn_len") }}
        sta {{ var("readline_active") }}

        jsr {{ api("enable_canonical") }}
        jsr {{ api("enable_echo") }}
        rts
    .endproc

    ; =====================================================================
    ; Enable canonical mode.

    .proc {{ api_def("enable_canonical") }}
        pha
        lda {{ var("flags") }}
        ora #BIT_CANONICAL_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Disable canonical mode.

    .proc {{ api_def("disable_canonical") }}
        pha
        lda {{ var("flags") }}
        and #<~BIT_CANONICAL_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Enable echoing of input characters.

    .proc {{ api_def("enable_echo") }}
        pha
        lda {{ var("flags") }}
        ora #BIT_ECHO_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Disable echoing of input characters.

    .proc {{ api_def("disable_echo") }}
        pha
        lda {{ var("flags") }}
        and #<~BIT_ECHO_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Clear the screen.

    {{ api_def("clr") }} = {{ screen_device.api("clr") }}

    ; =====================================================================
    ; Read a single byte from the keyboard (raw, non-blocking).
    ;
    ; Pass-through to the keyboard driver, with optional echo. Ignores
    ; canonical mode; intended for raw-mode callers. Canonical-mode line
    ; reading is done via TTY::readline.
    ;
    ; Out:
    ;   A = character read, when carry is set, otherwise clobbered
    ;   C = set when character was read, clear otherwise
    ;   X, Y = preserved

    .proc {{ api_def("read") }}
        txa
        pha
        tya
        pha

        jsr {{ keyboard_device.api("read") }}
        bcc @done                   ; No input, return with carry clear.
        sta {{ var("read_byte") }}  ; Save received byte before echo.
        lda #BIT_ECHO_ON            ; Check if echo is enabled.
        bit {{ var("flags") }}
        beq @done_with_carry
        lda {{ var("read_byte") }}  ; Yes, echo received input to the screen.
        jsr {{ api("write") }}
    @done_with_carry:
        sec                         ; Set carry to indicate "got input".
    @done:
        pla
        tay
        pla
        tax
        lda {{ var("read_byte") }}  ; Restore received byte into A.
        rts
    .endproc

    ; =====================================================================
    ; Read a line of input with editing (non-blocking, canonical mode).
    ;
    ; Editing model:
    ;   On the first readline call we emit ESC[s (save cursor) just
    ;   before the prompt. That position becomes the *anchor*. After any
    ;   visible state change (insert, delete, cursor move), we redraw
    ;   the entire line by:
    ;
    ;       ESC[u                    ; restore to anchor
    ;       ESC[J                    ; erase from cursor to end of screen
    ;       emit prompt + line_buf   ; renders the full line; terminal
    ;                                ; auto-wraps as needed (DECAWM is on
    ;                                ; by default, and we leave it alone)
    ;       ESC[u                    ; restore to anchor again
    ;       emit prompt + line_buf[0..cursor_pos)  ; positions visible cursor
    ;
    ;   This sidesteps wrap math entirely: the terminal's natural
    ;   autowrap places each character correctly, and our notion of
    ;   "where the cursor is" is reduced to "how many characters past
    ;   the anchor". No echo_col tracking, no ESC[A row counting, no
    ;   ESC[<col>G — just emit and restore.
    ;
    ; Non-blocking contract:
    ;   - Caller sets prompt/line_buffer/line_max once.
    ;   - Each call drains whatever's in the keyboard ring, processes
    ;     bytes through the canonical state machine, and either:
    ;        C=0 — line not complete yet, call again later
    ;        C=1 — line complete, A=length, line copied to caller's buffer
    ;
    ; Type-ahead just works: bytes that arrive at the keyboard before
    ; readline runs sit in the UART RX ring; the first call after the
    ; prompt is emitted drains them through the state machine.
    ;
    ; In:
    ;   {{ zp("prompt") }}      = pointer to null-terminated prompt
    ;   {{ zp("line_buffer") }} = pointer to caller's output buffer
    ;   {{ zp("line_max") }}    = max bytes the caller's buffer can hold
    ;   (Canonical mode must be on. If off, returns C=1, A=0.)
    ; Out:
    ;   C=1 with A=length when a complete line has been delivered
    ;   C=0 when no complete line is available yet (call again later)
    ;   X, Y = clobbered

    .proc {{ api_def("readline") }}
        ; Canonical mode must be on to interpret line discipline.
        lda #BIT_CANONICAL_ON
        bit {{ var("flags") }}
        beq @canonical_off

        ; If readline is not yet active, set the anchor (ESC[s) and do an
        ; initial redraw so the prompt + any type-ahead bytes appear.
        lda {{ var("readline_active") }}
        bne @drain

        lda #1
        sta {{ var("readline_active") }}

        ; The "edit cursor" sits at the end of any pre-existing buffer
        ; content (treated as type-ahead). Usually 0 → empty line.
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}

        ; Set the anchor and emit the initial prompt + any type-ahead.
        ; We don't call redraw() here because there's nothing to clear
        ; yet — just lay everything down once. Only when echo is on; if
        ; echo is off the user wants invisible input.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @drain
        jsr {{ my("emit_save_cursor") }}
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}

        ; Anchor is set; nothing of the buffer drawn yet (we're about to
        ; replay any type-ahead).
        lda #0
        sta {{ var("drawn_len") }}

        ; Replay any pre-existing line_buf as type-ahead.
        lda {{ var("line_len") }}
        beq @drain
        ldx #0
    @replay:
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        cpx {{ var("line_len") }}
        bne @replay
        ; All replayed bytes are now on screen.
        stx {{ var("drawn_len") }}

    @drain:
        ; Pull the next byte from the keyboard, if any.
        jsr {{ keyboard_device.api("read") }}
        bcs @got_byte

        ; No more input: line not complete yet.
        clc
        rts

    @got_byte:
        jsr {{ my("process_byte") }}
        bcc @drain                  ; Line not complete; try more bytes.

        ; Line complete: copy out + reset state.
        jmp {{ my("complete_line") }}

    @canonical_off:
        ; Caller misuse: readline requires canonical mode.
        lda #0
        sec                         ; Return "complete" with zero length.
        rts
    .endproc

    ; =====================================================================
    ; Internal: process one input byte via the canonical-mode line
    ; discipline state machine.
    ;
    ; In:
    ;   A = the input byte
    ; Out:
    ;   C = 1 if Enter was pressed (line is now complete)
    ;   C = 0 otherwise (continue draining)
    ;   X, Y = clobbered
    ;
    ; Behavior:
    ;   - CR / LF       → emit '\n', signal complete (C=1)
    ;   - BS / DEL      → erase char before edit cursor (mid-line OK)
    ;   - KEY_LEFT      → move edit cursor one left
    ;   - KEY_RIGHT     → move edit cursor one right
    ;   - ^U (NAK)      → kill line: empty buffer, redraw
    ;   - ^R (DC2)      → reprint: redraw on a fresh line
    ;   - ^L (FF)       → clear screen, redraw
    ;   - $20..$7E      → insert at cursor, redraw
    ;   - everything else (incl. KEY_UP/DOWN, $80+, other ^X) → ignored
    ;
    ; Echo gating: when BIT_ECHO_ON is off we never call redraw and
    ; never emit visible feedback, but we still mutate buffer state.
    ; Enter is special: it always emits a newline so the cursor advances
    ; even with echo off.

    .proc {{ my_def("process_byte") }}
        ; Dispatch table. The proc is too long for a single relative
        ; branch to reach every handler; use bne-skip + jmp pairs.
        cmp #'\r'
        bne :+
        jmp @enter
    :   cmp #'\n'
        bne :+
        jmp @enter
    :   cmp #KEY_BS
        bne :+
        jmp @backspace
    :   cmp #KEY_DEL
        bne :+
        jmp @backspace
    :   cmp #KEY_LEFT
        bne :+
        jmp @cursor_left
    :   cmp #KEY_RIGHT
        bne :+
        jmp @cursor_right
    :   cmp #KEY_NAK            ; ^U - kill line
        bne :+
        jmp @kill
    :   cmp #KEY_DC2            ; ^R - reprint
        bne :+
        jmp @reprint
    :   cmp #KEY_FF             ; ^L - clear + redraw
        bne :+
        jmp @clear_redraw

        ; Printable? ($20..$7E). DEL and BS already handled above.
    :   cmp #' '
        bcs :+                  ; >= $20
        jmp @ignore             ; < $20: control char, dropped.
    :   cmp #$7F
        bcc @printable
        jmp @ignore             ; $80+ are special keys; ignore.

    @printable:
        sta {{ var("read_byte") }}
        ldx {{ var("line_len") }}
        cpx #LINE_BUF_MAX
        bcs @full

        ; Fast path: append at end of line. cursor_pos == line_len means
        ; there's no tail to shift, and the visible result of inserting
        ; here is just "advance the cursor by one character on screen".
        ; That's exactly what `write`-ing the byte does: the terminal's
        ; natural autowrap (DECAWM, on by default) places it correctly
        ; even at the right margin. No redraw needed → no cursor flicker
        ; while typing, no \r\n scaffolding, just one byte per keystroke.
        cpx {{ var("cursor_pos") }}
        bne @insert_middle

        sta {{ var("line_buf") }},x
        inc {{ var("line_len") }}
        inc {{ var("cursor_pos") }}

        ; Echo if echo on.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        lda {{ var("read_byte") }}
        jsr {{ api("write") }}
        ; Track that one more cell has been drawn (only when echo is on,
        ; since we only actually wrote to the screen in that case).
        ldx {{ var("drawn_len") }}
        cpx {{ var("line_len") }}
        bcs @typed_done             ; drawn_len already covers the new char.
        inc {{ var("drawn_len") }}
    @typed_done:
        clc
        rts

    @insert_middle:
        ; Mid-line insert: shift line_buf[cursor_pos..line_len) right by
        ; one, drop the new char into the gap, then full redraw. Redraw
        ; is the only sane way to reflect the inserted-and-shifted tail
        ; correctly across row wraps.
        ldx {{ var("line_len") }}
    @shift_right_loop:
        cpx {{ var("cursor_pos") }}
        beq @shift_right_done
        lda {{ var("line_buf") }}-1,x
        sta {{ var("line_buf") }},x
        dex
        jmp @shift_right_loop
    @shift_right_done:
        lda {{ var("read_byte") }}
        ldx {{ var("cursor_pos") }}
        sta {{ var("line_buf") }},x
        inc {{ var("line_len") }}
        inc {{ var("cursor_pos") }}

        jmp @redraw_if_echo

    @full:
        ; Buffer full: beep and ignore. The bell only sounds when echo
        ; is on (consistent with "echo = visible feedback").
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        lda #KEY_BEL
        jsr {{ api("write") }}
    @ignore:
        clc
        rts

    @backspace:
        lda {{ var("cursor_pos") }}
        beq @ignore             ; At line start: nothing to erase.

        ; Shift line_buf[cursor_pos..line_len) left by one, drop the
        ; char before the cursor.
        ldx {{ var("cursor_pos") }}
    @shift_left_loop:
        cpx {{ var("line_len") }}
        beq @shift_left_done
        lda {{ var("line_buf") }},x
        sta {{ var("line_buf") }}-1,x
        inx
        jmp @shift_left_loop
    @shift_left_done:
        dec {{ var("cursor_pos") }}
        dec {{ var("line_len") }}
        jmp @redraw_if_echo

    @cursor_left:
        lda {{ var("cursor_pos") }}
        beq @ignore             ; At line start.
        dec {{ var("cursor_pos") }}
        jmp @redraw_if_echo

    @cursor_right:
        lda {{ var("cursor_pos") }}
        cmp {{ var("line_len") }}
        bcs @ignore             ; At end of line.
        inc {{ var("cursor_pos") }}
        jmp @redraw_if_echo

    @enter:
        ; Always advance cursor on Enter, regardless of echo flag.
        ; First, position the visible cursor at the END of the line
        ; (so the newline lands on a row that doesn't overlap an
        ; in-progress edit cursor mid-line). With echo off there's
        ; nothing rendered, so just emit \n.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @enter_emit_nl

        ; Move visible cursor to end-of-line by re-rendering with
        ; cursor_pos = line_len.
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        jsr {{ my("redraw") }}

    @enter_emit_nl:
        lda #'\n'
        jsr {{ api("write") }}
        sec
        rts

    @kill:
        ; ^U: empty buffer, redraw.
        lda #0
        sta {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        jmp @redraw_if_echo

    @reprint:
        ; ^R: emit \n to drop to a fresh line, set new anchor, redraw.
        lda #'\n'
        jsr {{ api("write") }}
        lda #0
        sta {{ var("drawn_len") }}     ; Fresh row below; nothing yet at the new anchor.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("emit_save_cursor") }}
        jmp {{ my("redraw") }}    ; tail-call; ends with rts, C=0 from redraw.

    @clear_redraw:
        ; ^L: clear screen, set anchor at top-left, redraw.
        jsr {{ api("clr") }}
        lda #0
        sta {{ var("drawn_len") }}     ; Screen is blank; nothing previously laid down.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("emit_save_cursor") }}
        jmp {{ my("redraw") }}

    @redraw_if_echo:
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("redraw") }}
        clc
        rts
    .endproc

    ; =====================================================================
    ; Internal: emit ESC[s (save cursor — DECSC variant supported by
    ; xterm and friends).

    .proc {{ my_def("emit_save_cursor") }}
        lda #KEY_ESC
        jsr {{ screen_device.api("write") }}
        lda #'['
        jsr {{ screen_device.api("write") }}
        lda #'s'
        jmp {{ screen_device.api("write") }}
    .endproc

    ; =====================================================================
    ; Internal: emit ESC[u (restore cursor).

    .proc {{ my_def("emit_restore_cursor") }}
        lda #KEY_ESC
        jsr {{ screen_device.api("write") }}
        lda #'['
        jsr {{ screen_device.api("write") }}
        lda #'u'
        jmp {{ screen_device.api("write") }}
    .endproc

    ; =====================================================================
    ; Internal: emit ESC[?25l (hide cursor).
    ;
    ; Used to bracket the redraw routine so the user doesn't see the
    ; cursor briefly jump to the anchor and back during a full repaint.
    ; The result is that the line content updates "atomically" from the
    ; user's perspective, with only the cursor's final position visible.

    .proc {{ my_def("emit_hide_cursor") }}
        lda #KEY_ESC
        jsr {{ screen_device.api("write") }}
        lda #'['
        jsr {{ screen_device.api("write") }}
        lda #'?'
        jsr {{ screen_device.api("write") }}
        lda #'2'
        jsr {{ screen_device.api("write") }}
        lda #'5'
        jsr {{ screen_device.api("write") }}
        lda #'l'
        jmp {{ screen_device.api("write") }}
    .endproc

    ; =====================================================================
    ; Internal: emit ESC[?25h (show cursor).

    .proc {{ my_def("emit_show_cursor") }}
        lda #KEY_ESC
        jsr {{ screen_device.api("write") }}
        lda #'['
        jsr {{ screen_device.api("write") }}
        lda #'?'
        jsr {{ screen_device.api("write") }}
        lda #'2'
        jsr {{ screen_device.api("write") }}
        lda #'5'
        jsr {{ screen_device.api("write") }}
        lda #'h'
        jmp {{ screen_device.api("write") }}
    .endproc

    ; =====================================================================
    ; Internal: redraw the prompt + line buffer from the saved anchor.
    ;
    ; Algorithm:
    ;   1. ESC[u  → restore cursor to anchor (set just before initial prompt).
    ;   2. ESC[J  → erase from cursor to end of screen (wipes any prior render).
    ;   3. emit prompt
    ;   4. emit line_buf[0..line_len)        — full line laid down.
    ;   5. ESC[u  → restore cursor to anchor again.
    ;   6. emit prompt
    ;   7. emit line_buf[0..cursor_pos)      — visible cursor lands at edit point.
    ;
    ; Steps 5–7 are the trick that handles wrapping cleanly: by emitting
    ; the prefix again from the anchor, the terminal's natural autowrap
    ; places the cursor exactly where the edit cursor logically is, with
    ; no row-count math on our end.
    ;
    ; The two prompt emissions are redundant on the wire but very cheap
    ; for typical prompts ("> ", "$ ") and worth the simplicity.
    ;
    ; Out:
    ;   C = 0 (redraw never completes a line)
    ;   A, X, Y = clobbered

    .proc {{ my_def("redraw") }}
        ; Hide the cursor for the duration of the repaint so the user
        ; doesn't see it dart around between the anchor and the final
        ; position. Most terminals (including minicom) honor ESC[?25l/h;
        ; the ones that don't will simply show the unhidden behavior.
        jsr {{ my("emit_hide_cursor") }}

        ; Pass 1: from the anchor, write the prompt and the new line
        ; contents *over* whatever's already there. No pre-clear: we
        ; want overwrites to look in-place. If the previous render was
        ; longer than the new one (e.g. just deleted a char), we trail
        ; with spaces to wipe the leftover; otherwise nothing extra.
        jsr {{ my("emit_restore_cursor") }}
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}

        ldx #0
    @full_loop:
        cpx {{ var("line_len") }}
        beq @full_done
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        bne @full_loop          ; LINE_BUF_MAX < 256, always taken in range.
    @full_done:
        ; Wipe trailing leftovers from a previous longer render. We've
        ; just laid down line_len cells. If drawn_len was bigger, emit
        ; (drawn_len - line_len) spaces to overwrite the stale tail.
        sec
        lda {{ var("drawn_len") }}
        sbc {{ var("line_len") }}
        beq @no_wipe                ; New render covers the old length.
        bcc @no_wipe                ; Defensive: drawn_len < line_len; nothing to wipe.
        tax
    @wipe_loop:
        stx {{ var("scratch_x") }}
        lda #' '
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        dex
        bne @wipe_loop
    @no_wipe:
        ; Update drawn_len = line_len. Whether we wiped or not, what's
        ; visible after this pass spans exactly line_len cells.
        lda {{ var("line_len") }}
        sta {{ var("drawn_len") }}

        ; Pass 2: position the visible cursor at cursor_pos by re-emitting
        ; the prompt + line_buf[0..cursor_pos). This relies on the
        ; terminal's natural autowrap to land the cursor exactly where
        ; the edit cursor logically is, with no row/column math here.
        jsr {{ my("emit_restore_cursor") }}
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}

        ldx #0
    @prefix_loop:
        cpx {{ var("cursor_pos") }}
        beq @done
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        bne @prefix_loop
    @done:
        jsr {{ my("emit_show_cursor") }}
        clc
        rts
    .endproc

    ; =====================================================================
    ; Internal: deliver the completed line to the caller's buffer.
    ;
    ; Truncates to the caller's max length, resets state, returns C=1
    ; with A=actual length.

    .proc {{ my_def("complete_line") }}
        ; len = min(line_len, line_max)
        lda {{ var("line_len") }}
        cmp {{ zp("line_max") }}
        bcc @save_len
        lda {{ zp("line_max") }}
    @save_len:
        sta {{ var("scratch_len") }}

        ; Copy line_buf[0..len) into the caller's buffer.
        ldy #0
    @copy_loop:
        cpy {{ var("scratch_len") }}
        beq @done_copy
        lda {{ var("line_buf") }},y
        sta ({{ zp("line_buffer") }}),y
        iny
        bne @copy_loop          ; LINE_BUF_MAX < 256.
    @done_copy:
        ; Reset internal state for the next line.
        lda #0
        sta {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        sta {{ var("drawn_len") }}
        sta {{ var("readline_active") }}

        lda {{ var("scratch_len") }}
        sec
        rts
    .endproc

    ; =====================================================================
    ; Write a byte to the screen (with terminal-style translation).
    ;
    ; In:
    ;   A = the byte to write
    ; Out:
    ;   A = the byte that was written
    ;   X, Y = consider clobbered (depends on driver implementation)

    .proc {{ api_def("write") }}
        ; Handle CR/LF, by normalizing \r, \n and \r\n to a single
        ; newline call.
        cmp #'\r'
        beq @cr
        cmp #'\n'
        beq @lf

        ; Handle DEL (delete) / BS (backspace).
        cmp #KEY_DEL           ; Delete? (backspace on many terminals)
        beq @backspace
        cmp #KEY_BS            ; Backspace?
        beq @backspace

        jmp {{ screen_device.api("write") }}

    @backspace:
        jmp {{ screen_device.api("backspace") }}

    @cr:
        jsr {{ screen_device.api("newline") }}
        ldx #1
        stx {{ var("previous_was_cr") }}
        rts

    @lf:
        ldx {{ var("previous_was_cr") }}
        beq @lone_lf
        ldx #0
        stx {{ var("previous_was_cr") }}
        rts

    @lone_lf:
        jmp {{ screen_device.api("newline") }}
    .endproc
