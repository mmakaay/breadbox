.include "CORE/coding_macros.inc"
.include "stdlib/math/divmod.inc"

.segment "KERNALRAM"

    {{ symbol("value") }}:   .res 1
    {{ symbol("decimal") }}: .res 2
    {{ symbol("padded") }}:  .res 4 ; max "255" + 1 null byte

; ==================================================================
; Format 8 bit value (byte) into decimal representation string.
;
; Usage:
;   ; Set the binary number to 73.
;   lda #$73
;   sta fmtdec::value
;
;   ; Execute the formatting.
;   jsr fmtdec
;
;   `fmtdec::padded` buffer now contains "073<null>"
;   `fmtdec::decimal` now points at "73<null>"
;
; In:
;   fmtdec::value = the value to convert
; Out:
;   fmtdec::padded  = null-terminated decimal string, zero-padded
;   fmtdec::decimal = pointer to first significant digit in padded
;   A/X/Y = preserved

.segment "KERNALROM"

.proc fmtdec
    value   = {{ symbol("value") }}
    decimal = {{ symbol("decimal") }}
    padded  = {{ symbol("padded") }}

    PUSH_AXY

    ; Pre-fill buffer with "000\0".
    lda #'0'                ; Literal zero
    sta padded
    sta padded+1
    sta padded+2
    lda #0                  ; Null terminator
    sta padded+3

    ; Setup divmod.
    COPY divmod::dividend, value
    ZERO divmod::dividend + 1
    STORE16 divmod::divisor, 10

    ldx #2                  ; Start at rightmost digit position.

@next_digit:
    jsr divmod
    lda divmod::remainder
    clc
    adc #'0'
    sta padded,x

    lda divmod::dividend
    beq @done

    dex
    bpl @next_digit

@done:
    ; Compute decimal pointer = address of padded + X.
    clc
    txa
    adc #<padded
    sta decimal
    lda #>padded
    adc #0
    sta decimal+1

    PULL_AXY
    rts

.endproc
