.include "stdlib/math/divmod16.inc"

.segment "KERNALRAM"

    {{ symbol("value") }}:   .res 2
    {{ symbol("decimal") }}: .res 6 ; max "65535" + 1 null byte

; ==================================================================
; Format 16 bit value (word) into decimal representation string.
;
; In:
;   fmtdec16::value = the 16 bit value to convert
; Out:
;   fmtdec16::decimal = null-terminated decimal string, zero-padded
;   X = index into decimal of the first significant digit
;   A/Y = preserved

.segment "KERNALROM"

.proc fmtdec16

    value   = {{ symbol("value") }}
    decimal = {{ symbol("decimal") }}

    pha
    phy

    ; Pre-fill buffer with "00000\0".
    lda #'0'
    ldy #4
@fill:
    sta decimal,y
    dey
    bpl @fill
    lda #0
    sta decimal+5           ; Null terminator.

    ; Setup divmod16.
    CP_WORD divmod16::dividend, value
    SET_WORD divmod16::divisor, 10

    ldx #4                  ; Start at rightmost digit position.

@next_digit:
    jsr divmod16
    lda divmod16::remainder
    clc
    adc #'0'
    sta decimal,x

    lda divmod16::dividend
    ora divmod16::dividend+1
    beq @done

    dex
    bpl @next_digit

@done:
    ; X = index of first significant digit.
    ply
    pla
    rts

.endproc
