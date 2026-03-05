.include "stdlib/math/divmod16.inc"

.segment "KERNALRAM"

    {{ symbol("value") }}:   .res 2
    {{ symbol("decimal") }}: .res 2
    {{ symbol("padded") }}:  .res 6 ; max "65535" + 1 null byte

; ==================================================================
; Format 16 bit value (word) into decimal representation string.
;
; Usage:
;   ; Set the binary number to $0539.
;   lda #$39
;   sta fmtdec16::value
;   lda #05
;   sta fmtdec16::value + 1
;
;   ; Execute the formatting.
;   jsr fmtdec16
;
;   `fmtdec16::padded` buffer now contains "01337<null>"
;   `fmtdec16::decimal` now points at "1337<null>"
;
; In:
;   fmtdec16::value = the value to convert
; Out:
;   fmtdec16::padded  = null-terminated decimal string, zero-padded
;   fmtdec16::decimal = pointer to first significant digit in padded
;   A/X/Y = preserved

.segment "KERNALROM"

.proc fmtdec16

    value   = {{ symbol("value") }}
    decimal = {{ symbol("decimal") }}
    padded  = {{ symbol("padded") }}

    PUSH_AXY

    ; Pre-fill buffer with "00000\0".
    lda #'0'
    ldy #4
@fill:
    sta padded,y
    dey
    bpl @fill
    lda #0
    sta padded+5            ; Null terminator.

    ; Setup divmod16.
    CP_WORD divmod16::dividend, value
    SET_WORD divmod16::divisor, 10

    ldx #4                  ; Start at rightmost digit position.

@next_digit:
    jsr divmod16
    lda divmod16::remainder
    clc
    adc #'0'
    sta padded,x

    lda divmod16::dividend
    ora divmod16::dividend+1
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
