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
    {{ var("anchor_row") }}: .res 1          ; 1-indexed terminal row holding line start
    {{ var("prompt_len") }}: .res 1          ; Length of the current prompt (0..255)
    {{ var("scratch_x") }}: .res 1           ; Temp X save during inner calls
    {{ var("scratch_len") }}: .res 1         ; Temp length save during copy
    {{ var("target_row") }}: .res 1          ; Working row for CUP positioning
    {{ var("target_col") }}: .res 1          ; Working col for CUP positioning
    {{ var("staging_len") }}: .res 1         ; Bytes queued during DSR wait

.segment "KERNALRAM"

    ; The internal editing buffer. Lives in RAM (not ZP) since 240 bytes
    ; is too large for zero page.
    {{ var("line_buf") }}: .res LINE_BUF_MAX

    ; Staging buffer for user keystrokes that arrive during DSR waits,
    ; and for unprocessed leftover from multi-line pastes that need to
    ; flow into the next readline activation.
    ;
    ; Sized to match the UART RX ring (256 bytes), since that's the
    ; theoretical maximum amount of in-flight input we can drain in
    ; one DSR wait. The UART's RTS flow control kicks in when the
    ; ring is ~80% full, so the host pauses before our staging
    ; would even be threatened with overflow.
    STAGING_MAX = 240
    {{ var("staging_buf") }}: .res STAGING_MAX

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
        sta {{ var("staging_len") }}

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
    ;   On the first readline call we query the terminal for its
    ;   current cursor row (DSR / ESC[6n), force ourselves to column 0
    ;   with \r so the line starts at a known column, and emit the
    ;   prompt. The (row, col=0) pair becomes the *anchor* for all
    ;   subsequent cursor positioning.
    ;
    ;   For any logical position p (in 0..prompt_len + line_len) the
    ;   visible cell is computed as:
    ;
    ;       total = prompt_len + p
    ;       row   = anchor_row + (total / term_width)
    ;       col   = (total mod term_width) + 1     ; CUP is 1-indexed
    ;
    ;   The visible cursor is moved with ESC[<row>;<col>H (CUP), which
    ;   is universally supported. No more relying on terminal-quirky
    ;   wrap-cursor positioning.
    ;
    ;   Redraw flow on any state change:
    ;       1. Hide cursor.
    ;       2. CUP to anchor.
    ;       3. Emit prompt + line_buf in place (overwrites previous).
    ;       4. Wipe trailing leftovers if drawn_len > line_len.
    ;       5. CUP to (row, col) computed from cursor_pos.
    ;       6. Show cursor.
    ;
    ;   Fast paths (no full redraw):
    ;     - Typing at end of line: just emit the char; let the
    ;       terminal autowrap. Single-byte cost.
    ;     - Cursor left / right: compute new (row, col) and CUP there.
    ;
    ; KNOWN LIMITATIONS:
    ;   - If a long line scrolls the screen up, anchor_row becomes
    ;     stale. We do best-effort detection at the end of every redraw
    ;     by clamping anchor_row so it never drives row > term_height,
    ;     but exotic interleavings (e.g. another component scrolling
    ;     during readline) will desynchronize the anchor.
    ;   - Caller must not write to the screen during a readline; doing
    ;     so will desynchronize the anchor.
    ;
    ; Non-blocking contract:
    ;   - Caller sets prompt/line_buffer/line_max once.
    ;   - Each call drains whatever's in the keyboard ring, processes
    ;     bytes through the canonical state machine, and either:
    ;        C=0 — line not complete yet, call again later
    ;        C=1 — line complete, A=length, line copied to caller's buffer
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
        bne :+
        jmp @canonical_off              ; out-of-range → trampoline.
    :

        ; If readline is not yet active, set the anchor and lay down
        ; the prompt + any type-ahead.
        lda {{ var("readline_active") }}
        bne @drain

        lda #1
        sta {{ var("readline_active") }}

        ; Note: we deliberately do NOT clear staging_len here. If the
        ; previous readline finished mid-staging (e.g. multi-line
        ; paste), replay_staging shifted the unprocessed leftover to
        ; the start of staging_buf — those bytes are queued for *this*
        ; readline activation. Wiping staging_len would drop them.

        ; Compute prompt length once, so redraw can re-position by
        ; pure arithmetic without re-walking the prompt string.
        jsr {{ my("compute_prompt_len") }}

        ; The "edit cursor" sits at the end of any pre-existing buffer
        ; content (treated as type-ahead). Usually 0 → empty line.
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}

        ; Echo off → no anchor needed; just drain into the buffer.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @drain

        ; Hide the cursor across the size + position queries so the
        ; user doesn't see it briefly jump to the bottom-right corner
        ; during query_size's DSR roundtrip. Show happens after the
        ; prompt is laid down.
        jsr {{ my("emit_hide_cursor") }}

        ; Refresh terminal size on every readline activation so our
        ; row/column arithmetic stays in sync if the user resized
        ; between prompts. This is a DSR roundtrip — cheap and only
        ; fires when readline transitions from inactive to active.
        ;
        ; query_size returns C=1 for sync screens (LCD: term_width and
        ; term_height already correct), C=0 for async screens (UART:
        ; the response will arrive via KEYBOARD::dsr_pending; we
        ; collect it via wait_for_dsr and apply via apply_dsr_size).
        jsr {{ my("clear_dsr_pending") }}
        jsr {{ screen_device.api("query_size") }}
        bcs @size_done                  ; Sync — no waiting needed.
        jsr {{ my("wait_for_dsr") }}
        bcc @size_done                  ; Timeout — keep previous values.
        jsr {{ my("apply_dsr_size") }}
    @size_done:

        ; Force column 0 so the anchor sits at a known column.
        lda #'\r'
        jsr {{ api("write") }}

        ; Ask the terminal where the cursor is now (1-indexed row).
        ; Sync (LCD): row in A directly. Async (UART): wait for the
        ; response. On any failure, fall back to row 1 — positioning
        ; may be off until ^L re-anchors.
        jsr {{ my("clear_dsr_pending") }}
        jsr {{ screen_device.api("query_cursor_pos") }}
        bcs @anchor_set                 ; Sync — A holds the row.
        jsr {{ my("wait_for_dsr") }}
        bcc @anchor_fallback
        lda {{ keyboard_device.zp("dsr_row") }}
        bne @anchor_set
    @anchor_fallback:
        lda #1
    @anchor_set:
        sta {{ var("anchor_row") }}

        ; Emit the prompt from the anchor.
        PRINT_PTR {{ api("write") }}, {{ zp("prompt") }}

        lda #0
        sta {{ var("drawn_len") }}

    @show_and_drain:
        ; All initial output complete; bring the cursor back.
        jsr {{ my("emit_show_cursor") }}

        ; Replay any keystrokes that arrived during the DSR waits, now
        ; that the anchor is set and rendering can happen normally.
        ; Each staged byte goes through the canonical-mode state
        ; machine (so Enter, backspace, etc., behave as expected).
        jsr {{ my("replay_staging") }}
        bcc @drain
        ; Enter was in the staging buffer — line is already complete.
        jmp {{ my("complete_line") }}

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
    ; Internal: compute the length of the prompt string and store it in
    ; prompt_len. Walks the prompt pointer until the null terminator.
    ; Saturates at 255.

    .proc {{ my_def("compute_prompt_len") }}
        ldy #0
    @loop:
        lda ({{ zp("prompt") }}),y
        beq @done
        iny
        bne @loop                    ; saturate at 255
    @done:
        sty {{ var("prompt_len") }}
        rts
    .endproc

    ; =====================================================================
    ; Internal: clear the keyboard's DSR-pending flag.
    ;
    ; Called before each DSR query so that wait_for_dsr knows it's
    ; waiting for a fresh response, not seeing a stale one left over
    ; from a prior query.

    .proc {{ my_def("clear_dsr_pending") }}
        lda #0
        sta {{ keyboard_device.zp("dsr_pending") }}
        rts
    .endproc

    ; =====================================================================
    ; Internal: wait for a DSR response, queuing any user keystrokes
    ; that arrive in the meantime in staging_buf.
    ;
    ; The keyboard's read transparently extracts DSR responses from the
    ; UART RX stream. Regular keystrokes are returned via read; DSR
    ; responses are stashed in KEYBOARD::dsr_row/dsr_col with
    ; dsr_pending=1.
    ;
    ; This proc spins until either dsr_pending becomes 1 or the timeout
    ; budget is exhausted. While spinning, any non-DSR bytes returned
    ; by keyboard.read are appended to staging_buf — they'll be
    ; replayed through process_byte after the anchor is set, so they
    ; participate in line editing normally (Enter completes a line,
    ; backspace edits, etc.).
    ;
    ; The staging buffer matches LINE_BUF_MAX in size (240 bytes), well
    ; above the UART RX ring's RTS-drop threshold (~208 bytes), so under
    ; normal host flow control we don't overflow.
    ;
    ; Out:
    ;   C = 1 on dsr_pending arrival, 0 on timeout
    ;   A, X, Y = clobbered

    .proc {{ my_def("wait_for_dsr") }}
        ; ~64K poll iterations: at 1 MHz, ~64 ms upper bound. The
        ; response typically arrives within a few ms, so this is mostly
        ; a sanity bound for cases where the terminal didn't reply.
        ldx #0
        ldy #0
    @loop:
        lda {{ keyboard_device.zp("dsr_pending") }}
        bne @got_it

        jsr {{ keyboard_device.api("read") }}
        bcc @no_byte

        ; A non-DSR keystroke arrived. Append it to staging_buf for
        ; later replay through process_byte. Drop silently when full.
        sta {{ var("read_byte") }}
        ldy {{ var("staging_len") }}
        cpy #STAGING_MAX
        bcs @drop_byte
        lda {{ var("read_byte") }}
        sta {{ var("staging_buf") }},y
        inc {{ var("staging_len") }}
    @drop_byte:
        ldx #0
        ldy #0

    @no_byte:
        dex
        bne @loop
        dey
        bne @loop
        clc
        rts

    @got_it:
        sec
        rts
    .endproc

    ; =====================================================================
    ; Internal: replay any staged keystrokes through process_byte.
    ;
    ; Called after the anchor is established and the prompt is laid
    ; down. Each staged byte goes through the canonical-mode state
    ; machine, so Enter completes the line, backspace edits, etc. If
    ; Enter is encountered mid-staging (e.g. multi-line paste, only
    ; the first line completes here), the unprocessed tail is shifted
    ; to the start of staging_buf so it survives into the next
    ; readline activation as queued input.
    ;
    ; Out:
    ;   C = 1 if Enter was encountered (line complete), 0 otherwise
    ;   A, X, Y = clobbered

    .proc {{ my_def("replay_staging") }}
        ldx {{ var("staging_len") }}
        beq @done_no_complete
        ldx #0
    @loop:
        cpx {{ var("staging_len") }}
        beq @done_no_complete
        ; Save loop index on the hardware stack — process_byte and its
        ; callees clobber the shared scratch_x slot.
        txa
        pha
        lda {{ var("staging_buf") }},x
        jsr {{ my("process_byte") }}
        bcs @done_complete
        pla
        tax
        inx
        jmp @loop

    @done_complete:
        ; Enter mid-staging. Shift any leftover bytes (from the index
        ; *after* the Enter) down to the start of staging_buf, so they
        ; survive into the next readline as queued input.
        pla
        tax
        inx                              ; first byte after Enter
        cpx {{ var("staging_len") }}
        beq @no_leftover

        ldy #0
    @shift_loop:
        lda {{ var("staging_buf") }},x
        sta {{ var("staging_buf") }},y
        inx
        iny
        cpx {{ var("staging_len") }}
        bne @shift_loop
        sty {{ var("staging_len") }}
        sec
        rts

    @no_leftover:
        lda #0
        sta {{ var("staging_len") }}
        sec
        rts

    @done_no_complete:
        lda #0
        sta {{ var("staging_len") }}
        clc
        rts
    .endproc

    ; =====================================================================
    ; Internal: apply the DSR row/col response (parsed by the keyboard
    ; into KEYBOARD::dsr_row / dsr_col) to the screen's term_height /
    ; term_width.
    ;
    ; The DSR response from a "move-cursor-then-query" probe carries
    ; the terminal's clamped (height, width). For non-async screens
    ; this proc is never called (their query_size returned C=1
    ; synchronously without enqueueing a DSR request).

    .proc {{ my_def("apply_dsr_size") }}
        lda {{ keyboard_device.zp("dsr_row") }}
        beq @done                       ; Defensive: refuse zero.
        sta {{ screen_device.zp("term_height") }}
        lda {{ keyboard_device.zp("dsr_col") }}
        beq @done
        sta {{ screen_device.zp("term_width") }}
    @done:
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
    :   cmp #KEY_UP             ; cursor up: jump back one screen row
        bne :+
        jmp @cursor_up
    :   cmp #KEY_DOWN           ; cursor down: jump forward one screen row
        bne :+
        jmp @cursor_down
    :   cmp #KEY_STX            ; ^B - cursor left (emacs)
        bne :+
        jmp @cursor_left
    :   cmp #KEY_ACK            ; ^F - cursor right (emacs)
        bne :+
        jmp @cursor_right
    :   cmp #KEY_SOH            ; ^A - move to start of line
        bne :+
        jmp @cursor_home
    :   cmp #KEY_ENQ            ; ^E - move to end of line
        bne :+
        jmp @cursor_end
    :   cmp #KEY_HOME           ; Home key → start of line
        bne :+
        jmp @cursor_home
    :   cmp #KEY_END            ; End key → end of line
        bne :+
        jmp @cursor_end
    :   cmp #KEY_EOT            ; ^D - forward delete
        bne :+
        jmp @forward_delete
    :   cmp #KEY_DELETE         ; Delete key → forward delete
        bne :+
        jmp @forward_delete
    :   cmp #KEY_VT             ; ^K - kill to end of line
        bne :+
        jmp @kill_to_end
    :   cmp #KEY_ETB            ; ^W - kill word backward
        bne :+
        jmp @kill_word_back
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
        ; Cap at the smaller of LINE_BUF_MAX (internal limit) and the
        ; caller's line_max. Without this, the user can type past
        ; line_max and complete_line silently truncates on Enter — a
        ; nasty surprise. With this, the bell rings when the user hits
        ; their own cap.
        cpx #LINE_BUF_MAX
        bcs @full
        cpx {{ zp("line_max") }}
        bcs @full

        ; Fast path: append at end of line. cursor_pos == line_len
        ; means there's no tail to shift, and the visible result of
        ; inserting here is "advance the cursor by one cell on screen".
        ; Just emit the byte; the terminal's autowrap (DECAWM, on by
        ; default) handles wrapping correctly.
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
        ; Track that one more cell has been drawn.
        ldx {{ var("drawn_len") }}
        cpx {{ var("line_len") }}
        bcs @typed_done             ; drawn_len already covers the new char.
        inc {{ var("drawn_len") }}
    @typed_done:
        ; Wrap-boundary handling: when the char we just emitted filled
        ; the rightmost cell of a row, the terminal's delayed-wrap
        ; leaves the cursor visually parked on that cell instead of
        ; jumping to column 1 of the next row. The user's intuition is
        ; "I typed a char and the cursor should have moved." Compute
        ; the logical position of the next character; if it's at a
        ; column-0 wrap boundary, CUP there explicitly.
        ;
        ; Special case at the bottom of the screen: target_row may
        ; exceed term_height. We must NOT CUP there — that would clamp
        ; to (term_height, 1) without scrolling, which prevents the
        ; terminal from scrolling on its own. Instead, leave the
        ; cursor in delayed-wrap state and let the terminal scroll
        ; naturally on the next character. After the natural scroll,
        ; we adjust anchor_row via clamp_anchor_after_growth.
        jsr {{ my("compute_target_pos") }}
        lda {{ var("target_col") }}
        cmp #1
        bne @typed_clamp            ; Not at column 1: no boundary, just clamp.

        ; At column-1 boundary. If target_row is on-screen, CUP there
        ; so the cursor visibly moves to the start of the next row.
        ; If target_row > term_height, defer the wrap to the natural
        ; terminal scroll triggered by the *next* character.
        lda {{ var("target_row") }}
        cmp {{ screen_device.zp("term_height") }}
        beq @do_cup                 ; row == height: still on screen.
        bcs @typed_clamp            ; row > height: skip CUP, let scroll happen.
    @do_cup:
        ldx {{ var("target_row") }}
        dex                          ; SCREEN::move_cursor is 0-indexed.
        ldy #0
        jsr {{ screen_device.api("move_cursor") }}

    @typed_clamp:
        ; If the natural autowrap pushed past the bottom of the screen
        ; (typing a char after delayed-wrap on the last row scrolls),
        ; adjust anchor_row down by the overflow.
        jsr {{ my("clamp_anchor_after_growth") }}
        clc
        rts

    @insert_middle:
        ; Mid-line insert: shift line_buf[cursor_pos..line_len) right
        ; by one, drop the new char into the gap, then full redraw.
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
        ; Single-cell cursor move: just CUP to the new logical
        ; position. No redraw needed.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("position_cursor") }}
        clc
        rts

    @cursor_right:
        lda {{ var("cursor_pos") }}
        cmp {{ var("line_len") }}
        bcs @ignore             ; At end of line.
        inc {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("position_cursor") }}
        clc
        rts

    @cursor_home:
        ; ^A: jump the edit cursor to position 0 (just after the
        ; prompt). No buffer mutation, no redraw — just one CUP.
        lda {{ var("cursor_pos") }}
        beq @ignore             ; Already at start.
        lda #0
        sta {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("position_cursor") }}
        clc
        rts

    @cursor_end:
        ; ^E: jump the edit cursor to end of line.
        lda {{ var("cursor_pos") }}
        cmp {{ var("line_len") }}
        bcs @ignore             ; Already at end.
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore
        jsr {{ my("position_cursor") }}
        clc
        rts

    @cursor_up:
        ; Cursor up: jump back one visual row of the wrapped line.
        ;
        ; Refuse the move if the cursor sits on the first visual row
        ; (the row containing the prompt) — there's nowhere up to go
        ; that's still inside the buffer.
        ;
        ; First-row test: prompt_len + cursor_pos < term_width.
        ; If the sum overflows 8 bits, we're definitely past the first
        ; row (assuming term_width ≤ 255), so the overflow path skips
        ; the refuse.
        lda {{ var("prompt_len") }}
        clc
        adc {{ var("cursor_pos") }}
        bcs @cursor_up_apply_calc       ; Sum > 255: past first row.
        cmp {{ screen_device.zp("term_width") }}
        bcc @ignore_jump                ; Sum < width: on first row, refuse.

    @cursor_up_apply_calc:
        ; new_cursor_pos = cursor_pos - term_width.
        lda {{ var("cursor_pos") }}
        sec
        sbc {{ screen_device.zp("term_width") }}
        bcs @cursor_up_apply
        ; Underflow guard (cursor on first row but prompt + cursor_pos
        ; happened to overflow — possible only if prompt_len is bigger
        ; than term_width; an unusual but not invalid setup): land at 0.
        lda #0
    @cursor_up_apply:
        sta {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore_jump
        jsr {{ my("position_cursor") }}
    @ignore_jump:
        clc
        rts

    @cursor_down:
        ; Cursor down: jump forward one visual row of the wrapped line.
        ;   - If cursor_pos + term_width <= line_len: move there.
        ;   - Otherwise: if a down-move would leave the cursor on the
        ;     same visual row (i.e. the line ends on the current row),
        ;     refuse. Otherwise clamp to line_len.
        ;
        ; Visual-row equality is computed by reusing compute_target_pos:
        ; first for the current cursor position, then with cursor_pos
        ; temporarily set to line_len. If both produce the same
        ; target_row, refuse the move.

        ; Easy case: cursor_pos + term_width <= line_len → straight move.
        lda {{ var("cursor_pos") }}
        clc
        adc {{ screen_device.zp("term_width") }}
        bcs @down_check_row             ; sum overflowed 8 bits.
        cmp {{ var("line_len") }}
        beq @down_apply                 ; lands exactly on line_len.
        bcc @down_apply                 ; lands before line_len.

    @down_check_row:
        ; A down-move would overshoot. Decide between "refuse" (cursor
        ; already on last visual row) and "clamp to line_len".
        ;
        ; Compute target_row for the current cursor position.
        jsr {{ my("compute_target_pos") }}
        lda {{ var("target_row") }}
        sta {{ var("scratch_x") }}      ; row_at_cursor

        ; Now compute target_row for line_len. We temporarily rebind
        ; cursor_pos to line_len, compute, then restore.
        lda {{ var("cursor_pos") }}
        sta {{ var("scratch_len") }}    ; saved cursor_pos
        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        jsr {{ my("compute_target_pos") }}
        lda {{ var("scratch_len") }}
        sta {{ var("cursor_pos") }}     ; restored

        lda {{ var("target_row") }}
        cmp {{ var("scratch_x") }}
        beq @ignore_jump                ; same visual row → refuse.

        ; Different row → clamp to line_len.
        lda {{ var("line_len") }}

    @down_apply:
        sta {{ var("cursor_pos") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @ignore_jump
        jsr {{ my("position_cursor") }}
        clc
        rts

    @forward_delete:
        ; ^D / Delete key: erase the character AT the edit cursor,
        ; keeping the cursor in place. Mid-line is the common case;
        ; at end of line there's nothing to delete.
        lda {{ var("cursor_pos") }}
        cmp {{ var("line_len") }}
        bcc :+
        jmp @ignore             ; out-of-range → trampoline.
    :

        ; Shift line_buf[cursor_pos+1..line_len) left by one onto
        ; line_buf[cursor_pos..line_len-1), then decrement line_len.
        ldx {{ var("cursor_pos") }}
    @fwd_shift_loop:
        inx
        cpx {{ var("line_len") }}
        beq @fwd_shift_done
        lda {{ var("line_buf") }},x
        sta {{ var("line_buf") }}-1,x
        jmp @fwd_shift_loop
    @fwd_shift_done:
        dec {{ var("line_len") }}
        jmp @redraw_if_echo

    @kill_to_end:
        ; ^K: truncate the line at the cursor. Buffer state mutates;
        ; the redraw's trailing-wipe logic erases the killed tail
        ; from the visible display.
        lda {{ var("cursor_pos") }}
        cmp {{ var("line_len") }}
        bcc :+
        jmp @ignore             ; out-of-range → trampoline.
    :   sta {{ var("line_len") }}
        jmp @redraw_if_echo

    @kill_word_back:
        ; ^W: delete from the cursor back to the start of the previous
        ; word. The "word" definition mirrors readline's default: skip
        ; any whitespace immediately before the cursor, then skip the
        ; run of non-whitespace before that. Whatever's between the
        ; resulting position and the cursor gets deleted.
        lda {{ var("cursor_pos") }}
        bne :+
        jmp @ignore             ; out-of-range → trampoline.
    :

        ; Phase 1: walk back over whitespace.
        ldx {{ var("cursor_pos") }}
    @kw_skip_ws:
        dex
        bmi @kw_phase2_done     ; Hit -1 → buffer is all whitespace.
        lda {{ var("line_buf") }},x
        cmp #' '
        beq @kw_skip_ws
        cmp #KEY_HT
        beq @kw_skip_ws
        ; Found a non-whitespace char at index x.

        ; Phase 2: walk back over non-whitespace.
    @kw_skip_word:
        dex
        bmi @kw_phase2_done
        lda {{ var("line_buf") }},x
        cmp #' '
        beq @kw_phase2_advance
        cmp #KEY_HT
        beq @kw_phase2_advance
        jmp @kw_skip_word
    @kw_phase2_advance:
        ; Stopped on a whitespace. The new cursor sits one past it.
        inx
    @kw_phase2_done:
        ; X holds the new cursor position (-1 → 0). Treat the BMI exit
        ; as "delete everything before cursor".
        bpl @kw_apply
        ldx #0
    @kw_apply:
        ; new_pos in X. Delete bytes [new_pos..cursor_pos) by shifting
        ; line_buf[cursor_pos..line_len) left into line_buf[new_pos..).
        stx {{ var("scratch_x") }}      ; new_pos
        ; deleted_count = cursor_pos - new_pos.
        lda {{ var("cursor_pos") }}
        sec
        sbc {{ var("scratch_x") }}
        sta {{ var("scratch_len") }}    ; deleted_count

        ; Shift loop: for i in [cursor_pos..line_len),
        ;   line_buf[i - deleted_count] = line_buf[i].
        ldy {{ var("cursor_pos") }}
    @kw_shift_loop:
        cpy {{ var("line_len") }}
        beq @kw_shift_done
        lda {{ var("line_buf") }},y
        ; Compute destination index = y - deleted_count.
        sty {{ var("read_byte") }}      ; reuse read_byte as scratch
        tax
        lda {{ var("read_byte") }}
        sec
        sbc {{ var("scratch_len") }}
        tay                              ; y = destination
        txa
        sta {{ var("line_buf") }},y
        ldy {{ var("read_byte") }}
        iny
        jmp @kw_shift_loop
    @kw_shift_done:
        ; Update cursor_pos and line_len.
        lda {{ var("scratch_x") }}
        sta {{ var("cursor_pos") }}
        lda {{ var("line_len") }}
        sec
        sbc {{ var("scratch_len") }}
        sta {{ var("line_len") }}
        jmp @redraw_if_echo

    @enter:
        ; Always advance cursor on Enter, regardless of echo flag.
        ; Move the visible cursor to end-of-line first so the newline
        ; lands consistently below the line, not in the middle of an
        ; in-progress edit. With echo off there's nothing rendered, so
        ; just emit \n.
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        beq @enter_emit_nl

        lda {{ var("line_len") }}
        sta {{ var("cursor_pos") }}
        jsr {{ my("position_cursor") }}

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
        ; ^R: emit \n to drop to a fresh line, refresh terminal size,
        ; re-anchor, redraw.
        ;
        ; Refreshing the size here lets the user resize their terminal
        ; mid-readline and use ^R to bring the editor back in sync. The
        ; query is one DSR roundtrip and only happens on user-initiated
        ; redraw events, so the cost is negligible.
        lda #'\n'
        jsr {{ api("write") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        bne :+
        jmp @ignore                     ; out-of-range → trampoline.
    :

        ; Hide the cursor across the size + anchor queries so the user
        ; doesn't see it briefly jump to the bottom-right corner during
        ; query_size. The matching show happens at the end of redraw.
        jsr {{ my("emit_hide_cursor") }}

        ; Refresh terminal size (sync screens return C=1; async screens
        ; require a wait + apply).
        jsr {{ my("clear_dsr_pending") }}
        jsr {{ screen_device.api("query_size") }}
        bcs @reprint_size_done
        jsr {{ my("wait_for_dsr") }}
        bcc @reprint_size_done
        jsr {{ my("apply_dsr_size") }}
    @reprint_size_done:

        ; Force column 0 and re-query cursor row for the new anchor.
        lda #'\r'
        jsr {{ api("write") }}
        jsr {{ my("clear_dsr_pending") }}
        jsr {{ screen_device.api("query_cursor_pos") }}
        bcs @reprint_anchor_set         ; Sync — A holds the row.
        jsr {{ my("wait_for_dsr") }}
        bcc @reprint_fallback
        lda {{ keyboard_device.zp("dsr_row") }}
        bne @reprint_anchor_set
    @reprint_fallback:
        lda #1
    @reprint_anchor_set:
        sta {{ var("anchor_row") }}

        lda #0
        sta {{ var("drawn_len") }}
        ; redraw lays down both the prompt and the buffer from the
        ; (newly set) anchor.
        jsr {{ my("redraw") }}
        ; Replay any keystrokes that arrived during the DSR waits.
        jmp {{ my("replay_staging") }}

    @clear_redraw:
        ; ^L: clear screen, refresh terminal size, anchor at row 1,
        ; redraw.
        ;
        ; Refreshing the size here lets the user resize their terminal
        ; and use ^L to clear away leftovers from the old layout — the
        ; common reflex when the screen looks broken after a resize.
        jsr {{ api("clr") }}
        jsr {{ screen_device.api("home") }}
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        bne :+
        jmp @ignore                     ; out-of-range → trampoline.
    :

        ; Hide the cursor across the size query (matching show happens
        ; in redraw).
        jsr {{ my("emit_hide_cursor") }}

        ; Refresh terminal size. The screen is freshly cleared and the
        ; cursor is at home (row 1, col 1), so we know the cursor's
        ; position before and after the query.
        jsr {{ my("clear_dsr_pending") }}
        jsr {{ screen_device.api("query_size") }}
        bcs @clear_size_done
        jsr {{ my("wait_for_dsr") }}
        bcc @clear_size_done
        jsr {{ my("apply_dsr_size") }}
    @clear_size_done:

        lda #1
        sta {{ var("anchor_row") }}
        lda #0
        sta {{ var("drawn_len") }}

        ; redraw lays down both prompt and buffer from the anchor.
        jsr {{ my("redraw") }}
        ; Replay any keystrokes staged during the DSR wait.
        jmp {{ my("replay_staging") }}

    @redraw_if_echo:
        lda #BIT_ECHO_ON
        bit {{ var("flags") }}
        bne :+
        jmp @ignore                     ; out-of-range → trampoline.
    :   jsr {{ my("redraw") }}
        clc
        rts
    .endproc

    ; =====================================================================
    ; Internal: clamp anchor_row when the line grows past the bottom of
    ; the screen.
    ;
    ; If the visible cursor would now sit on a row > term_height, the
    ; terminal has scrolled the screen up by the difference. We adjust
    ; anchor_row by the same amount so subsequent CUP positions stay in
    ; sync with the actual display.

    .proc {{ my_def("clamp_anchor_after_growth") }}
        ; Compute logical position of cursor.
        jsr {{ my("compute_target_pos") }}
        lda {{ var("target_row") }}
        cmp {{ screen_device.zp("term_height") }}
        bcc @done                       ; row <= height: fine.
        beq @done                       ; row == height: still on screen.

        ; row > term_height — overflow. Adjust anchor_row down by the
        ; overflow so future positions land correctly. Floor at 1 to
        ; avoid underflow on extremely long lines.
        sec
        sbc {{ screen_device.zp("term_height") }}     ; A = overflow rows
        sta {{ var("scratch_x") }}
        lda {{ var("anchor_row") }}
        sec
        sbc {{ var("scratch_x") }}
        bcs @apply                       ; no underflow.
        lda #1                           ; clamp at 1.
    @apply:
        bne @store                       ; non-zero is fine.
        lda #1                           ; refuse zero (CUP rows are 1-indexed).
    @store:
        sta {{ var("anchor_row") }}
    @done:
        rts
    .endproc

    ; =====================================================================
    ; Internal: compute the (row, col) of the visible cell corresponding
    ; to the current edit cursor position.
    ;
    ;   total = prompt_len + cursor_pos
    ;   row   = anchor_row + (total / term_width)
    ;   col   = (total mod term_width) + 1   ; 1-indexed for CUP
    ;
    ; Out:
    ;   target_row, target_col = the computed position
    ;   A, X, Y = clobbered

    .proc {{ my_def("compute_target_pos") }}
        ; Compute total = prompt_len + cursor_pos (16-bit since the sum
        ; can exceed 255 for long lines past a wide prompt).
        lda {{ var("prompt_len") }}
        clc
        adc {{ var("cursor_pos") }}
        sta {{ var("scratch_len") }}    ; lo
        lda #0
        adc #0
        sta {{ var("scratch_x") }}      ; hi (carry from add)

        ; Divide [scratch_x:scratch_len] by term_width, leaving quotient
        ; in scratch_x and remainder in scratch_len. Long-division by
        ; repeated subtraction; term_width is 1 byte, total is 2 bytes
        ; up to ~480 (240 buf + 240 prompt) so quotient fits in 1 byte.
        lda #0
        sta {{ var("target_row") }}     ; quotient accumulator (rows past anchor)

    @div_loop:
        ; If hi > 0 OR (hi == 0 AND lo >= width), subtract width.
        lda {{ var("scratch_x") }}
        bne @sub                         ; hi > 0: must subtract.
        lda {{ var("scratch_len") }}
        cmp {{ screen_device.zp("term_width") }}
        bcc @div_done                    ; lo < width: stop.

    @sub:
        lda {{ var("scratch_len") }}
        sec
        sbc {{ screen_device.zp("term_width") }}
        sta {{ var("scratch_len") }}
        lda {{ var("scratch_x") }}
        sbc #0
        sta {{ var("scratch_x") }}
        inc {{ var("target_row") }}
        jmp @div_loop

    @div_done:
        ; Quotient = target_row, remainder = scratch_len.
        ; row = anchor_row + quotient.
        lda {{ var("target_row") }}
        clc
        adc {{ var("anchor_row") }}
        sta {{ var("target_row") }}

        ; col = remainder + 1 (1-indexed).
        lda {{ var("scratch_len") }}
        clc
        adc #1
        sta {{ var("target_col") }}

        rts
    .endproc

    ; =====================================================================
    ; Internal: position the visible cursor at the cell corresponding to
    ; the current edit cursor position.

    .proc {{ my_def("position_cursor") }}
        jsr {{ my("compute_target_pos") }}
        ldx {{ var("target_row") }}
        dex                              ; SCREEN::move_cursor uses 0-indexed.
        ldy {{ var("target_col") }}
        dey
        jmp {{ screen_device.api("move_cursor") }}
    .endproc

    ; =====================================================================
    ; Internal: emit ESC[?25l (hide cursor).

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
    ;   1. Hide cursor (so the user doesn't see it dart around).
    ;   2. CUP to (anchor_row, 1).
    ;   3. Emit prompt + line_buf[0..line_len) — overwrites previous in
    ;      place. The terminal's natural autowrap places each char.
    ;   4. If drawn_len > line_len, emit (drawn_len - line_len) trailing
    ;      spaces to wipe stale leftovers.
    ;   5. Update drawn_len = line_len.
    ;   6. Clamp anchor_row if the redraw scrolled the screen.
    ;   7. CUP to the cell for cursor_pos (computed via arithmetic).
    ;   8. Show cursor.
    ;
    ; Out:
    ;   C = 0 (redraw never completes a line)
    ;   A, X, Y = clobbered

    .proc {{ my_def("redraw") }}
        jsr {{ my("emit_hide_cursor") }}

        ; CUP to anchor.
        ldx {{ var("anchor_row") }}
        dex                              ; SCREEN::move_cursor is 0-indexed.
        ldy #0
        jsr {{ screen_device.api("move_cursor") }}

        ; Lay down the prompt + buffer.
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
        bne @full_loop          ; LINE_BUF_MAX < 256.
    @full_done:

        ; Wipe trailing leftovers from a previous longer render.
        sec
        lda {{ var("drawn_len") }}
        sbc {{ var("line_len") }}
        beq @no_wipe                    ; New render covers the old length.
        bcc @no_wipe                    ; Defensive: drawn_len < line_len.
        tax
    @wipe_loop:
        stx {{ var("scratch_x") }}
        lda #' '
        jsr {{ api("write") }}
        ldx {{ var("scratch_x") }}
        dex
        bne @wipe_loop
    @no_wipe:
        lda {{ var("line_len") }}
        sta {{ var("drawn_len") }}

        ; If laying down everything caused the terminal to scroll the
        ; screen up, anchor_row is now off by however many rows the
        ; screen scrolled. Clamp before computing the final cursor
        ; position.
        jsr {{ my("clamp_anchor_after_growth") }}

        ; Position the visible cursor at cursor_pos.
        jsr {{ my("position_cursor") }}

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
        ; Reset internal state for the next line. Deliberately do NOT
        ; clear staging_len: if the user pasted multiple lines, the
        ; bytes after the just-completed Enter are sitting at the
        ; start of staging_buf (replay_staging shifted them down). We
        ; want those preserved so the next readline activation picks
        ; them up as queued input.
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
