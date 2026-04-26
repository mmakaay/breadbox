; UART 6551 keyboard: {{ component_id }}
;
; Reads bytes from the UART and parses ANSI escape sequences for arrow
; keys, function keys, and DSR (Device Status Report) responses. A
; standalone ESC keypress is distinguished from an escape sequence by
; polling briefly for follow-up bytes.
;
; Supported escape sequences:
;
;   Arrow keys (return KEY_UP/DOWN/RIGHT/LEFT):
;       ESC [ A      ESC O A      ESC [ 1;3A   →  KEY_UP
;       ESC [ B      ESC O B      ESC [ 1;3B   →  KEY_DOWN
;       ESC [ C      ESC O C      ESC [ 1;3C   →  KEY_RIGHT
;       ESC [ D      ESC O D      ESC [ 1;3D   →  KEY_LEFT
;
;   Function keys:
;       ESC [ H              →  KEY_HOME
;       ESC [ F              →  KEY_END
;       ESC [ 1~  ESC [ 7~   →  KEY_HOME
;       ESC [ 4~  ESC [ 8~   →  KEY_END
;       ESC [ 3~             →  KEY_DELETE
;
;   DSR responses (extracted out-of-band — never surface as a key):
;       ESC [ <row> ; <col> R    →  stash row/col into dsr_row/dsr_col,
;                                   set dsr_pending=1.
;
; CSI parameter bytes ($20-$3F: digits, semicolons) are consumed before
; checking the final byte. Unrecognized sequences are silently dropped.
;
; Selective drainage:
;
; The read proc consumes the next byte from the UART regardless of its
; content. The drain_escapes proc, in contrast, only consumes bytes
; that are part of an ANSI escape sequence — non-ESC bytes are left
; sitting at the head of the UART ring buffer. This is used by the TTY
; layer's wait_for_dsr to extract DSR responses from the input stream
; without disturbing user input that's queued behind them. As a
; consequence, the UART's RX ring (and its RTS flow control) handles
; host-side overflow naturally: when the ring fills, RTS deasserts and
; the host pauses; we never need to mirror that backpressure in our
; own buffers.

.include "__keyboard/constants.inc"

; Number of poll attempts when waiting for escape sequence bytes.
; With a local serial connection, sequence bytes arrive near-instantly
; in the IRQ ring buffer. A modest poll count provides enough margin
; without any noticeable delay on a standalone ESC keypress.
_ESC_POLLS = 200

.segment "ZEROPAGE"

    ; -------------------------------------------------------------------
    ; Public DSR-response state, populated when an ESC[<row>;<col>R
    ; sequence is recognized in the input stream. The screen layer's
    ; query_cursor_pos and query_size procs send the request; the TTY
    ; layer waits for dsr_pending to flip and then reads the values.
    {{ zp_def("dsr_row") }}: .res 1
    {{ zp_def("dsr_col") }}: .res 1
    {{ zp_def("dsr_pending") }}: .res 1   ; 1 = a fresh response is available

    ; -------------------------------------------------------------------
    ; Internal scratch for sequence parsing.
    {{ var("csi_acc") }}: .res 1          ; running decimal accumulator
    {{ var("csi_row") }}: .res 1          ; first parameter (becomes row)
    {{ var("csi_have_row") }}: .res 1     ; 1 if csi_row was assigned
    {{ var("csi_dig") }}: .res 1          ; scratch for digit value
    {{ var("parse_key") }}: .res 1        ; key code from last sequence parse,
                                          ; or 0 if no key (DSR/dropped)

.segment "KERNALROM"

    ; =====================================================================
    ; Read the next key, consuming bytes from the UART regardless of
    ; whether they form a recognized sequence.
    ;
    ; Returns:
    ;   - Regular bytes as-is (with carry set).
    ;   - A standalone ESC keypress as KEY_ESC (with carry set), if no
    ;     follow-up byte arrives within the poll window.
    ;   - Recognized arrow/function-key sequences as their KEY_* code
    ;     (with carry set).
    ;   - DSR responses are silently extracted (dsr_row/dsr_col/dsr_pending
    ;     get updated) and we keep reading. The caller never sees them.
    ;   - Unrecognized escape sequences are silently dropped, and we keep
    ;     reading.
    ;
    ; If the UART becomes empty during loop iteration (e.g. after parsing
    ; a DSR sequence that consumed all available bytes), returns C=0.
    ;
    ; Out:
    ;   C = 1 if a key is available, 0 if no input
    ;   A = key code (valid only when C=1)
    ;   X, Y = clobbered

    .proc {{ api_def("read") }}
    @loop:
        jsr {{ provider_device.api("read") }}
        bcc @done                       ; UART empty.

        cmp #KEY_ESC
        beq @got_esc

        sec                             ; Non-ESC: return as-is.
    @done:
        rts

    @got_esc:
        ; Consumed ESC. Parse what follows. parse_key gets set to the
        ; resulting key code (or 0 if the sequence was DSR/dropped).
        jsr {{ my("consume_esc_sequence") }}
        lda {{ var("parse_key") }}
        beq @loop                       ; No key from this sequence; keep reading.
        sec
        rts
    .endproc

    ; =====================================================================
    ; Internal: parse what follows a just-consumed ESC byte.
    ;
    ; On entry, ESC has already been pulled from the UART. This proc
    ; polls for the rest of the sequence (with a brief timeout for slow
    ; hosts), recognizes CSI arrow/function/DSR sequences, and stores
    ; the resulting key code in parse_key — or 0 if the sequence was a
    ; DSR response, was unrecognized, or timed out (stale ESC).
    ;
    ; The DSR side effect is on dsr_row/dsr_col/dsr_pending.
    ;
    ; Out:
    ;   parse_key = key code or 0
    ;   A, X, Y = clobbered

    .proc {{ my_def("consume_esc_sequence") }}
        lda #0
        sta {{ var("parse_key") }}

        ; Poll for the byte after ESC.
        jsr {{ my("poll_byte") }}
        bcs :+
        ; Timed out → standalone ESC keypress.
        lda #KEY_ESC
        sta {{ var("parse_key") }}
        rts
    :   cmp #'['
        beq @csi
        cmp #'O'
        bne :+
        jmp @ss3                         ; out-of-range → trampoline.
    :   ; Unknown intro byte after ESC. Treat as a standalone ESC plus
        ; a dropped intro byte. Returning KEY_ESC matches what most
        ; users expect (e.g. an Alt-X chord on some terminals shows up
        ; as ESC + 'X'; we surface the ESC and drop X).
        lda #KEY_ESC
        sta {{ var("parse_key") }}
        rts

    @csi:
        ; CSI sequence: parse parameter/intermediate bytes ($20-$3F)
        ; while accumulating digits into csi_acc; latch the first
        ; complete parameter into csi_row when we hit ';'. When a final
        ; byte (>= $40) arrives, dispatch.
        lda #0
        sta {{ var("csi_acc") }}
        sta {{ var("csi_have_row") }}
    @csi_loop:
        jsr {{ my("poll_byte") }}
        bcs :+
        rts                              ; Timed out mid-sequence: drop.
    :   cmp #$40
        bcs @csi_final                   ; >= $40: final byte.
        cmp #';'
        beq @csi_separator
        ; Otherwise expect a decimal digit ($30..$39). Anything else in
        ; the parameter range is silently consumed.
        cmp #'0'
        bcc @csi_loop
        cmp #'9'+1
        bcs @csi_loop
        sec
        sbc #'0'
        sta {{ var("csi_dig") }}
        jsr {{ my("csi_mul10_add_dig") }}
        jmp @csi_loop

    @csi_separator:
        ; Latch the first parameter (row in DSR) and reset accumulator.
        lda {{ var("csi_acc") }}
        sta {{ var("csi_row") }}
        lda #1
        sta {{ var("csi_have_row") }}
        lda #0
        sta {{ var("csi_acc") }}
        jmp @csi_loop

    @csi_final:
        cmp #'R'
        beq @csi_dsr                     ; DSR response.
        cmp #'~'
        beq @csi_tilde                   ; Tilde-terminated function key.
        cmp #'H'
        bne :+
        lda #KEY_HOME                    ; ESC[H → Home (no parameter).
        sta {{ var("parse_key") }}
        rts
    :   cmp #'F'
        bne :+
        lda #KEY_END                     ; ESC[F → End (no parameter).
        sta {{ var("parse_key") }}
        rts
    :   ; A/B/C/D — arrow keys. Anything else falls through to drop.
        jmp @map_arrow

    @csi_dsr:
        ; DSR ESC[<row>;<col>R. csi_row holds the row (set at ';');
        ; csi_acc holds the col. Stash both publicly. parse_key stays
        ; 0 so the caller doesn't surface this as a key.
        lda {{ var("csi_have_row") }}
        beq @done                        ; Malformed (no ';'): drop.
        lda {{ var("csi_row") }}
        sta {{ zp("dsr_row") }}
        lda {{ var("csi_acc") }}
        sta {{ zp("dsr_col") }}
        lda #1
        sta {{ zp("dsr_pending") }}
    @done:
        rts

    @csi_tilde:
        ; ESC[<n>~ — function-key sequences. csi_acc holds n.
        ;   1, 7  →  KEY_HOME    (xterm/rxvt)
        ;   3     →  KEY_DELETE  (forward-delete)
        ;   4, 8  →  KEY_END     (xterm/rxvt)
        ;   anything else → drop (Insert, PageUp/Down, F-keys, …).
        ldx {{ var("csi_acc") }}
        cpx #1
        beq @ret_home
        cpx #7
        beq @ret_home
        cpx #3
        beq @ret_delete
        cpx #4
        beq @ret_end
        cpx #8
        beq @ret_end
        rts                              ; parse_key still 0 → drop.

    @ret_home:
        lda #KEY_HOME
        sta {{ var("parse_key") }}
        rts
    @ret_end:
        lda #KEY_END
        sta {{ var("parse_key") }}
        rts
    @ret_delete:
        lda #KEY_DELETE
        sta {{ var("parse_key") }}
        rts

    @ss3:
        ; SS3 sequence: final byte follows directly (no parameters).
        jsr {{ my("poll_byte") }}
        bcs @map_arrow
        rts                              ; Timed out: drop.

    @map_arrow:
        sec
        sbc #'A'                         ; 'A'→0, 'B'→1, 'C'→2, 'D'→3
        cmp #4
        bcs @done_arrow                  ; out of range → drop.
        tax
        lda @key_codes,x
        sta {{ var("parse_key") }}
    @done_arrow:
        rts

    @key_codes:
        .byte KEY_UP            ; 'A' → 0
        .byte KEY_DOWN          ; 'B' → 1
        .byte KEY_RIGHT         ; 'C' → 2
        .byte KEY_LEFT          ; 'D' → 3
    .endproc

    ; =====================================================================
    ; Internal: csi_acc = csi_acc * 10 + csi_dig, saturating at 255.

    .proc {{ my_def("csi_mul10_add_dig") }}
        lda {{ var("csi_acc") }}
        cmp #26
        bcs @saturate                    ; * 10 would overflow 8 bits.
        ; csi_acc * 10 = (csi_acc << 1) + (csi_acc << 3)
        asl                              ; *2
        sta {{ var("csi_acc") }}
        asl                              ; *4
        asl                              ; *8
        clc
        adc {{ var("csi_acc") }}         ; *2 + *8 = *10
        clc
        adc {{ var("csi_dig") }}
        sta {{ var("csi_acc") }}
        rts

    @saturate:
        lda #255
        sta {{ var("csi_acc") }}
        rts
    .endproc

    ; =====================================================================
    ; Poll briefly for a byte from the UART.
    ;
    ; Calls the UART read function in a tight loop. With IRQ-based
    ; reception, sequence bytes are typically already in the ring buffer
    ; by the time this is called.
    ;
    ; Out:
    ;   C = 1 if byte received, 0 if no byte after polling
    ;   A = received byte (valid only when C=1)
    ;   Y = clobbered

    .proc {{ my_def("poll_byte") }}
        ldy #_ESC_POLLS
    @loop:
        jsr {{ provider_device.api("read") }}
        bcs @done
        dey
        bne @loop
        clc                              ; No data after polling.
    @done:
        rts
    .endproc
