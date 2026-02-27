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
;   fmtdec16::decimal = the null-terminated decimal string (reversed)
;   A/X/Y = preserved

.segment "KERNALROM"

.proc fmtdec16

    value   = {{ symbol("value") }}
    decimal = {{ symbol("decimal") }}

    PUSH_AXY
    ldx #0
    stx decimal

    ; Set the divider for divmod16 to 10, so we can use it to strip off the "ones".
    CP_WORD divmod16::dividend, value
    SET_WORD divmod16::divisor, 10

@next_digit:
    jsr divmod16

    lda divmod16::remainder   ; Get computed remainder
    clc                       ; Clear carry for clean addition
    adc #'0'                  ; Add remainder to ASCII value of "0"
    sta decimal,x             ; Store digit in output buffer
    inx

    ; Repeat until all base 10 digits have been extracted.
    lda divmod16::dividend
    ora divmod16::dividend + 1
    bne @next_digit           ; Branch if not yet at zero

    lda #0                    ; Null-terminate the string
    sta decimal,x

    PULL_AXY
    rts

.endproc
