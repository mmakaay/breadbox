; UART 6551 keyboard: {{ component_id }}
;
; Reads bytes from the UART and parses ANSI escape sequences for arrow
; keys and DSR (Device Status Report) responses. A standalone ESC
; keypress is distinguished from an escape sequence by polling briefly
; for follow-up bytes.
;
; Supported escape sequences:
;
;   Arrow keys (return KEY_UP/DOWN/RIGHT/LEFT):
;       ESC [ A      ESC O A      ESC [ 1;3A   →  KEY_UP
;       ESC [ B      ESC O B      ESC [ 1;3B   →  KEY_DOWN
;       ESC [ C      ESC O C      ESC [ 1;3C   →  KEY_RIGHT
;       ESC [ D      ESC O D      ESC [ 1;3D   →  KEY_LEFT
;
;   DSR responses (extracted out-of-band — read does NOT return them):
;       ESC [ <row> ; <col> R    →  stash row/col into dsr_row/dsr_col,
;                                   set dsr_pending=1, return C=0.
;
; CSI parameter bytes ($20-$3F: digits, semicolons) are consumed before
; checking the final byte. Unrecognized sequences are silently
; discarded and KEY_ESC is returned.
;
; Out-of-band DSR handling: when the screen layer issues an ESC[6n
; query, the response will arrive in the UART RX ring along with any
; user keystrokes that happened to be typed during the roundtrip. The
; keyboard's read transparently extracts DSR responses (recognized by
; their 'R' final byte and digit/semicolon parameter pattern), parses
; the row;col, and surfaces it via dsr_row/dsr_col + dsr_pending. Any
; user keystrokes interleaved with the response are returned normally
; via the usual read path. This lets the TTY layer issue queries
; without losing user input or contaminating the keyboard stream with
; KEY_ESC bytes from DSR responses.

.include "__keyboard/constants.inc"

; Number of poll attempts when waiting for escape sequence bytes.
; With a local serial connection, sequence bytes arrive near-instantly
; in the IRQ ring buffer. A modest poll count provides enough margin
; without any noticeable delay on a standalone ESC keypress.
_ESC_POLLS = 200

.segment "ZEROPAGE"

    ; -------------------------------------------------------------------
    ; Public DSR-response state, populated by the read proc when an
    ; ESC[<row>;<col>R sequence is recognized. The screen layer's
    ; query_cursor_pos and query_size procs send the request; the TTY
    ; layer waits for dsr_pending to flip and then reads the values.
    {{ zp_def("dsr_row") }}: .res 1
    {{ zp_def("dsr_col") }}: .res 1
    {{ zp_def("dsr_pending") }}: .res 1   ; 1 = a fresh response is available

    ; -------------------------------------------------------------------
    ; Internal scratch for DSR parameter parsing.
    {{ var("csi_acc") }}: .res 1          ; running decimal accumulator
    {{ var("csi_row") }}: .res 1          ; first parameter (becomes row)
    {{ var("csi_have_row") }}: .res 1     ; 1 if csi_row was assigned
    {{ var("csi_dig") }}: .res 1          ; scratch for digit value

.segment "KERNALROM"

    ; =====================================================================
    ; Read a key from the UART.
    ;
    ; Returns raw bytes for all non-ESC input. When ESC is received,
    ; polls briefly for follow-up bytes that form an ANSI escape
    ; sequence. If a recognized arrow-key sequence arrives, returns the
    ; corresponding KEY_* code. If a DSR response arrives, stashes the
    ; row/col into the public ZP slots and returns C=0 (no key).
    ; Other recognized but non-arrow sequences are silently discarded.
    ;
    ; Out:
    ;   C = 1 if key received, 0 if no input available
    ;   A = key code (valid only when C=1)
    ;   X, Y = clobbered

    .proc {{ api_def("read") }}
        jsr {{ provider_device.api("read") }}
        bcc @done               ; No data available.

        cmp #KEY_ESC
        beq @got_esc

        sec                     ; Non-ESC byte → return as-is.
    @done:
        rts

    @got_esc:
        ; ESC received. Poll for a sequence prefix byte.
        jsr {{ my("poll_byte") }}
        bcc @return_esc

        cmp #'['                ; CSI prefix?
        beq @csi
        cmp #'O'                ; SS3 prefix?
        bne @return_esc
        jmp @ss3                ; out-of-range → trampoline.

        ; Unknown byte after ESC → discard it, return ESC.
    @return_esc:
        lda #KEY_ESC
        sec
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
        bcc @return_esc
        cmp #$40
        bcs @csi_final           ; >= $40: final byte.
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
        beq @csi_dsr             ; DSR response.
        cmp #'~'
        beq @csi_tilde           ; Tilde-terminated function key.
        cmp #'H'
        bne :+
        lda #KEY_HOME            ; ESC[H → Home (no parameter).
        sec
        rts
    :   cmp #'F'
        bne :+
        lda #KEY_END             ; ESC[F → End (no parameter).
        sec
        rts
    :   ; A/B/C/D — arrow keys. Anything else falls through to drop.
        jmp @map_arrow

    @csi_dsr:
        ; DSR ESC[<row>;<col>R. csi_row holds the row (set at ';');
        ; csi_acc holds the col. Stash both publicly and return "no key".
        lda {{ var("csi_have_row") }}
        beq @return_no_key       ; Malformed (no ';'): drop silently.
        lda {{ var("csi_row") }}
        sta {{ zp("dsr_row") }}
        lda {{ var("csi_acc") }}
        sta {{ zp("dsr_col") }}
        lda #1
        sta {{ zp("dsr_pending") }}
    @return_no_key:
        clc
        rts

    @csi_tilde:
        ; ESC[<n>~ — function-key sequences. csi_acc holds n.
        ;   1, 7  →  KEY_HOME    (xterm rxvt)
        ;   3     →  KEY_DELETE  (forward-delete)
        ;   4, 8  →  KEY_END     (xterm rxvt)
        ;   anything else → drop silently (Insert, PageUp/Down, F1..).
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
        jmp @return_no_key

    @ret_home:
        lda #KEY_HOME
        sec
        rts
    @ret_end:
        lda #KEY_END
        sec
        rts
    @ret_delete:
        lda #KEY_DELETE
        sec
        rts

    @ss3:
        ; SS3 sequence: final byte follows directly (no parameters).
        jsr {{ my("poll_byte") }}
        bcs @map_arrow
        jmp @return_esc                ; out-of-range → trampoline.

    @map_arrow:
        sec
        sbc #'A'                ; 'A'→0, 'B'→1, 'C'→2, 'D'→3
        cmp #4
        bcs @return_no_key      ; out of range → unknown sequence, drop.
        tax
        lda @key_codes,x
        sec
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
        bcs @saturate            ; * 10 would overflow 8 bits.
        ; csi_acc * 10 = (csi_acc << 1) + (csi_acc << 3)
        asl                      ; *2
        sta {{ var("csi_acc") }}
        asl                      ; *4
        asl                      ; *8
        clc
        adc {{ var("csi_acc") }} ; *2 + *8 = *10
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
        clc                     ; No data after polling.
    @done:
        rts
    .endproc
