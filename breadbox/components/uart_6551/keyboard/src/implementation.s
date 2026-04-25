; UART 6551 keyboard: {{ component_id }}
;
; Reads bytes from the UART and parses ANSI escape sequences for
; arrow keys. A standalone ESC keypress is distinguished from an
; escape sequence by polling briefly for follow-up bytes.
;
; Supported escape sequences (with optional CSI parameters):
;   ESC [ A      ESC O A      ESC [ 1;3A  →  KEY_UP
;   ESC [ B      ESC O B      ESC [ 1;3B  →  KEY_DOWN
;   ESC [ C      ESC O C      ESC [ 1;3C  →  KEY_RIGHT
;   ESC [ D      ESC O D      ESC [ 1;3D  →  KEY_LEFT
;
; CSI parameter bytes ($20-$3F: digits, semicolons) are consumed
; before checking the final byte. Unrecognized sequences are
; silently discarded and KEY_ESC is returned.

.include "__keyboard/constants.inc"

; Number of poll attempts when waiting for escape sequence bytes.
; With a local serial connection, sequence bytes arrive near-instantly
; in the IRQ ring buffer. A modest poll count provides enough margin
; without any noticeable delay on a standalone ESC keypress.
_ESC_POLLS = 200

.segment "KERNALROM"

    ; =====================================================================
    ; Read a key from the UART.
    ;
    ; Returns raw bytes for all non-ESC input. When ESC is received,
    ; polls briefly for follow-up bytes that form an ANSI escape
    ; sequence. If a recognized sequence arrives, returns the
    ; corresponding KEY_* code. Otherwise returns KEY_ESC.
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
        beq @ss3

        ; Unknown byte after ESC → discard it, return ESC.
    @return_esc:
        lda #KEY_ESC
        sec
        rts

    @csi:
        ; CSI sequence: consume parameter/intermediate bytes ($20-$3F)
        ; until a final byte (>= $40) arrives.
        jsr {{ my("poll_byte") }}
        bcc @return_esc
        cmp #$40
        bcs @map_final          ; >= $40: final byte.
        cmp #$20
        bcs @csi                ; $20-$3F: parameter byte, consume.
        bcc @return_esc         ; < $20: unexpected, bail.

    @ss3:
        ; SS3 sequence: final byte follows directly (no parameters).
        jsr {{ my("poll_byte") }}
        bcc @return_esc

    @map_final:
        sec
        sbc #'A'                ; 'A'→0, 'B'→1, 'C'→2, 'D'→3
        cmp #4
        bcs @return_esc         ; out of range → unknown sequence
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
