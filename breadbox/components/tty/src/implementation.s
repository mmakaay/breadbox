.feature string_escapes

.include "CORE/coding_macros.inc"
.include "stdlib/io/print.inc"
.include "__keyboard/constants.inc"

.constructor {{ my("init") }}

; Maximum length of the canonical-mode editing buffer.
; Any printable input beyond this beeps and is ignored until the user
; backspaces or presses Enter.
LINE_BUF_MAX = 80

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
    {{ var("readline_active") }}: .res 1     ; 1 while a readline is in progress
    {{ var("scratch_x") }}: .res 1           ; Temp X save during inner calls
    {{ var("scratch_len") }}: .res 1         ; Temp length save during copy

.segment "KERNALRAM"

    ; The internal editing buffer. Lives in RAM (not ZP) since 80 bytes
    ; is too large to spend on zero page.
    {{ var("line_buf") }}: .res LINE_BUF_MAX

.segment "KERNALROM"

    ; Option flags
    BIT_CANONICAL_ON = %00000001   ; Enable canonical mode
    BIT_ECHO_ON      = %00000010   ; Echo input characters

    ; =====================================================================
    ; Initialize the TTY.
    ;
    ; Enables canonical mode and echoing of input characters.
    ;
    ; Out:
    ;   A, X, Y = preserved

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
        sta {{ var("readline_active") }}

        jsr {{ api("enable_canonical") }}
        jsr {{ api("enable_echo") }}
        rts
    .endproc

    ; =====================================================================
    ; Enable canonical mode.
    ;
    ; Out:
    ;   A, X, Y = preserved

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
    ;
    ; Out:
    ;   A, X, Y = preserved

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
    ;
    ; Out:
    ;   A, X, Y = preserved

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
    ;
    ; Out:
    ;   A, X, Y = preserved

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
    ;
    ; Out:
    ;   A, X, Y = consider clobbered (depends on driver implementation)

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
    ; Non-blocking line read with prompt. The caller sets up the public
    ; ZP variables once, then calls TTY::readline repeatedly. Each call
    ; drains whatever is currently available from the keyboard, processes
    ; bytes through the canonical-mode line discipline (printable +
    ; backspace + ^R/^L/^U), and returns:
    ;
    ;   - C=0 if the line is not yet complete (caller does other work and
    ;          calls again later)
    ;   - C=1 with A=length if Enter was pressed (line copied into the
    ;          caller's buffer)
    ;
    ; The line buffer state persists across calls. The first call (when
    ; readline_active=0) emits the prompt and then begins draining input.
    ; Subsequent calls just drain.
    ;
    ; Type-ahead is handled "for free": bytes that arrive at the keyboard
    ; ring buffer before readline is called accumulate there and are
    ; processed (with echo) on the first readline call after the prompt
    ; is emitted.
    ;
    ; In:
    ;   {{ zp("prompt") }}      = pointer to null-terminated prompt
    ;   {{ zp("line_buffer") }} = pointer to caller's output buffer
    ;   {{ zp("line_max") }}    = max bytes the caller's buffer can hold
    ;   (Canonical mode must be on. If off, we error out with C=1, A=0.)
    ; Out:
    ;   C = 1 with A=length when a complete line has been delivered
    ;   C = 0 when no complete line is available yet (call again later)
    ;   X, Y = clobbered

    .proc {{ api_def("readline") }}
        ; Canonical mode must be on to interpret line discipline.
        lda #BIT_CANONICAL_ON
        bit {{ var("flags") }}
        beq @canonical_off

        ; If readline is not yet active, emit the prompt and replay any
        ; type-ahead bytes already in the line buffer. Then mark active.
        lda {{ var("readline_active") }}
        bne @drain

        lda #1
        sta {{ var("readline_active") }}

        ; Emit the prompt via TTY::write (which translates CR/LF + BS/DEL).
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}

        ; Replay any pre-existing line_buf contents as type-ahead.
        ; (Usually empty; only relevant if a prior caller stuffed bytes.)
        ; Set the edit cursor to end-of-line, since after replay the
        ; visible cursor sits there.
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        beq @drain
        ldx #0
    @replay_typeahead:
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        cpx {{ var("line_len") }}
        bne @replay_typeahead

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
    ;   - CR ($0D) or LF ($0A): emit '\n' to advance cursor; return C=1.
    ;   - BS ($08) or DEL ($7F): erase the character before the edit
    ;     cursor (works mid-line; tail is shifted left and redrawn).
    ;   - KEY_LEFT  ($83): move edit cursor one left (no edit).
    ;   - KEY_RIGHT ($82): move edit cursor one right (no edit).
    ;   - ^U ($15): empty buffer + reprint (\r\n + prompt).
    ;   - ^R ($12): reprint (\r\n + prompt + buffer contents).
    ;   - ^L ($0C): clear screen + redraw prompt + buffer.
    ;   - Printable ($20..$7E): insert at cursor + echo, shifting any
    ;     tail right and redrawing it. Beeps when buffer is full.
    ;   - Anything else (incl. KEY_UP/DOWN, other ^X codes): ignored.
    ;
    ; Echo is gated on the BIT_ECHO_ON flag: when off, all visible
    ; feedback is suppressed except Enter, which still emits a newline
    ; so the cursor advances.

    .proc {{ my_def("process_byte") }}
        ; Dispatch table. The proc body is too long for relative branches
        ; to reach every handler, so we use bne-skip + jmp pairs for the
        ; far jumps. The closest handler (printable, fall-through) needs
        ; no jmp.
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

        ; Printable? ($20..$7E). $7F (DEL) and $08 (BS) already handled.
    :   cmp #' '
        bcs :+                  ; >= $20: maybe printable, check upper.
        jmp @ignore             ; < $20: control char (already routed).
    :   cmp #$7F
        bcc @printable          ; $20..$7E → printable, fall through.
        jmp @ignore             ; $7F was DEL (handled); $80+ are special keys.

    @printable:
        sta {{ var("read_byte") }}
        ldx {{ var("line_len") }}
        cpx #LINE_BUF_MAX
        bcs @full

        ; Insert at cursor_pos: shift line_buf[cursor_pos..line_len) right
        ; by one, then drop the new char into the gap.
        ;
        ;   Before: [ a b c | d e ]   cursor_pos=3, line_len=5
        ;   After:  [ a b c X d e ]   cursor_pos=4, line_len=6
        ;
        ; Shift right-to-left to avoid overwriting source data.
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

        ; Echo: write the new char (advances visible cursor by 1), then
        ; redraw the tail and back the visible cursor up to where it
        ; logically belongs.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        lda {{ var("read_byte") }}
        jsr {{ api("write") }}
        jsr {{ my("redraw_tail") }}
    @ignore:
        clc
        rts

    @full:
        ; Buffer full: beep and ignore. The bell is suppressed when echo
        ; is off, since "echo" is what the user perceives as feedback.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        lda #KEY_BEL
        jsr {{ api("write") }}
        clc
        rts

    @backspace:
        lda {{ var("cursor_pos") }}
        beq @ignore             ; At line start: nothing to erase.

        ; Shift line_buf[cursor_pos..line_len) left by one, drop the
        ; character before the cursor.
        ;
        ;   Before: [ a b c | d e ]   cursor_pos=3, line_len=5
        ;   After:  [ a b | d e ]     cursor_pos=2, line_len=4
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

        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        ; SCREEN::backspace = left + space + left, leaving the cursor on
        ; the now-empty slot. Then redraw the tail (shorter by 1) and
        ; wipe the trailing character that's now stale on screen.
        lda #KEY_BS
        jsr {{ api("write") }}
        jsr {{ my("redraw_tail_shrunk") }}
        clc
        rts

    @cursor_left:
        lda {{ var("cursor_pos") }}
        beq @ignore             ; At line start: ignore.
        dec {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        ; Move visible cursor one column left, no erase.
        ; SCREEN::write maps KEY_LEFT/KEY_RIGHT to bare ESC[D / ESC[C
        ; (cursor-move escapes), which is exactly what we want here.
        lda #KEY_LEFT
        jsr {{ screen_device.api("write") }}
        clc
        rts

    @cursor_right:
        lda {{ var("cursor_pos") }}
        cmp {{ var("line_len") }}
        bcs @ignore             ; At end of line: ignore.
        inc {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        lda #KEY_RIGHT
        jsr {{ screen_device.api("write") }}
        clc
        rts

    @enter:
        ; Always advance cursor on Enter, regardless of echo flag, so the
        ; user sees something happen and the next prompt sits on a fresh
        ; line.
        lda #'\n'
        jsr {{ api("write") }}
        sec
        rts

    @kill:
        ; ^U: empty buffer first, then fall through to reprint logic
        ; (which now redraws an empty line under the prompt).
        lda #0
        sta {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        ; Fall through.

    @reprint:
        ; ^R: emit \r\n, prompt, then current buffer contents.
        lda #'\n'
        jsr {{ api("write") }}
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}
        jmp {{ my("replay_buffer") }}

    @clear_redraw:
        ; ^L: clear screen, emit prompt, then current buffer contents.
        jsr {{ api("clr") }}
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}
        jmp {{ my("replay_buffer") }}
    .endproc

    ; =====================================================================
    ; Internal: redraw line_buf[cursor_pos..line_len) and back up the
    ; visible cursor by the same amount, leaving it at cursor_pos.
    ;
    ; Used after a printable insertion in the middle of the line.
    ;
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ my_def("redraw_tail") }}
        ; Emit the tail.
        ldx {{ var("cursor_pos") }}
    @emit_loop:
        cpx {{ var("line_len") }}
        beq @emit_done
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        jmp @emit_loop
    @emit_done:
        ; Back the visible cursor up: line_len - cursor_pos cursor-lefts.
        sec
        lda {{ var("line_len") }}
        sbc {{ var("cursor_pos") }}
        beq @done
        tax
    @back_loop:
        stx {{ var("scratch_x") }}
        lda #KEY_LEFT
        jsr {{ screen_device.api("write") }}
        ldx {{ var("scratch_x") }}
        dex
        bne @back_loop
    @done:
        rts
    .endproc

    ; =====================================================================
    ; Internal: redraw line_buf[cursor_pos..line_len) after a deletion,
    ; wiping the now-stale trailing character that the deletion left
    ; behind on screen, then back up the visible cursor.
    ;
    ; Used after backspace-in-the-middle: SCREEN::backspace erased the
    ; char at the new cursor position, but the tail on screen is one
    ; column too far right. So we re-emit the tail (which lays it back
    ; down at the correct position), emit a space (to wipe what was the
    ; last char before the shrink), and back the visible cursor up by
    ; (tail_len + 1) columns.
    ;
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ my_def("redraw_tail_shrunk") }}
        ; Emit the tail.
        ldx {{ var("cursor_pos") }}
    @emit_loop:
        cpx {{ var("line_len") }}
        beq @emit_done
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        jmp @emit_loop
    @emit_done:
        ; Wipe the leftover trailing char.
        lda #' '
        jsr {{ api("write") }}

        ; Back up: (line_len - cursor_pos) + 1 cursor-lefts.
        sec
        lda {{ var("line_len") }}
        sbc {{ var("cursor_pos") }}
        clc
        adc #1
        tax
    @back_loop:
        stx {{ var("scratch_x") }}
        lda #KEY_LEFT
        jsr {{ screen_device.api("write") }}
        ldx {{ var("scratch_x") }}
        dex
        bne @back_loop
        rts
    .endproc

    ; =====================================================================
    ; Internal: re-emit the line buffer contents via TTY::write.
    ;
    ; Used by ^R, ^L and ^U to redraw after the prompt.
    ;
    ; Out:
    ;   C = 0 (line is not yet complete)
    ;   A, X, Y = clobbered

    .proc {{ my_def("replay_buffer") }}
        ; After a full reprint the visible cursor sits at end-of-line, so
        ; the edit cursor logically follows along.
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        ldx #0
    @loop:
        cpx {{ var("line_len") }}
        beq @done
        lda {{ var("line_buf") }},x
        stx {{ var("scratch_x") }}
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        inx
        bne @loop               ; Always taken (max 80 < 256).
    @done:
        clc
        rts
    .endproc

    ; =====================================================================
    ; Internal: deliver the completed line to the caller's buffer.
    ;
    ; Truncates to the caller's max length, resets state, and returns
    ; with C=1 and A=actual length.
    ;
    ; Out:
    ;   A = length of returned line (0..line_max)
    ;   C = 1
    ;   X, Y = clobbered

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
        bne @copy_loop          ; Always taken (max 80 < 256).
    @done_copy:
        ; Reset internal state for the next line.
        lda #0
        sta {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
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
        ; Handle CR/LF, by normalizing \r, \n and \r\n to a newline call to the terminal.
        cmp #'\r'
        beq @cr
        cmp #'\n'
        beq @lf

        ; Handle DEL (delete) / BS (backspace)
        cmp #KEY_DEL           ; Delete? (backspace on many terminals)
        beq @backspace
        cmp #KEY_BS            ; Backspace?
        beq @backspace

        ; Echo the input to the TTY output.
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
