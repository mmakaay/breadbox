.segment "KERNALRAM"

    {{ symbol("dividend") }}:  .res 2
    {{ symbol("divisor") }}:   .res 2
    {{ symbol("remainder") }}: .res 2

; ==================================================================
; Perform divmod operation on a 2 byte word.
;
; In:
;   dividend = the word to divide
;   divisor = the word to divide by
; Out:
;   quotient = input div divide_by
;   dividend = same as quotient
;   remainder = input mod divide_by
;   A/X/Y = preserved

.segment "KERNALROM"

.proc divmod16

    dividend  = {{ symbol("dividend") }}
    divisor   = {{ symbol("divisor") }}
    remainder = {{ symbol("remainder") }}
    quotient  = {{ symbol("dividend") }}

    PUSH_AXY

    ; Initialize the remainder.
    CLR_WORD remainder

    ldx #16

    clc ; Make sure the first carry rol'ed in below is a 0.
@divloop:
    ; Shift the 32-bit [remainder:dividend] register left by one bit.
    ; The carry from the previous subtraction comparison enters bit 0
    ; of the dividend, building up the quotient bit by bit.
    rol dividend            ; Low byte << 1
    rol dividend + 1        ; High byte << 1
    rol remainder           ; Carry from dividend enters remainder
    rol remainder + 1       ; High byte of remainder

    ; See if we can subtract the divisor from the bit value that is currently
    ; shifted into the remainder bytes. When remainder < divisor, then the
    ; result will become negative, and the carry bit will be set to 0
    ; (due to borrowing).
    sec                       ; Set carry bit, to detect carry borrow for sbc
    lda remainder             ; Load low byte of remainder
    sbc divisor               ; Subtract low byte of divisor -> A
    tay                       ; A -> Y
    lda remainder + 1         ; Load high byte of remainder
    sbc divisor + 1           ; Subtract high byte of divisor -> A

    ; If carry bit is cleared, then division was not possible. We continue
    ; with shifting another bit, to see if that makes a division possible.
    bcc @no_div_possible

    ; Dividing was possible. Like with long tail divisions (on paper), we continue
    ; with the new remainder and the rest of the digits, which in this case can be
    ; accomplished by updating the remainder word with the remainder from the
    ; subtraction from above.
    sty remainder             ; Update remainder low byte <- Y
    sta remainder + 1         ; Update remainder high byte <- A

@no_div_possible:
    dex
    bne @divloop              ; Process all 16 bits, before continuing.

    rol quotient              ; Shift last carry bit (representing if the last
    rol quotient + 1          ; division was possible or not) into the quotient.

    PULL_AXY
    rts

.endproc
