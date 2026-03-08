.include "CORE/coding_macros.inc"

.segment "KERNALRAM"

    {{ symbol("dividend") }}:  .res 1
    {{ symbol("divisor") }}:   .res 1
    {{ symbol("remainder") }}: .res 1

; ==================================================================
; Perform divmod operation on a byte value.
;
; Usage:
;   ; Set the dividend value to 42.
;   lda #422
;   sta divmod::dividend
;
;   ; Set the divisor to 5.
;   lda #5
;   sta divmod::divisor
;
;   ; Execute the division.
;   jsr divmod
;
;   `divmod::quotient` now contains 8
;   `divmod::remainder` now contains 2
;
; In:
;   dividend = the value to divide
;   divisor = the value to divide by
; Out:
;   quotient = input div divide_by
;   dividend = same as quotient
;   remainder = input mod divide_by
;   A/X/Y = preserved

.segment "KERNALROM"

.proc divmod

    dividend  = {{ symbol("dividend") }}
    divisor   = {{ symbol("divisor") }}
    remainder = {{ symbol("remainder") }}
    quotient  = {{ symbol("dividend") }}

    PUSH_AXY

    ; Initialize the remainder.
    ZERO remainder

    ldx #8

    clc ; Make sure the first carry rol'ed in below is a 0.
@divloop:
    ; Shift the 16-bit [remainder:dividend] register left by one bit.
    ; The carry from the previous subtraction comparison enters bit 0
    ; of the dividend, building up the quotient bit by bit.
    rol dividend            ; Low byte << 1
    rol remainder           ; Carry from dividend enters remainder

    ; See if we can subtract the divisor from the bit value that is currently
    ; shifted into the remainder bytes. When remainder < divisor, then the
    ; result will become negative, and the carry bit will be set to 0
    ; (due to borrowing).
    sec                       ; Set carry bit, to detect carry borrow for sbc
    lda remainder             ; Load low byte of remainder
    sbc divisor               ; Subtract low byte of divisor -> A

    ; If carry bit is cleared, then division was not possible. We continue
    ; with shifting another bit, to see if that makes a division possible.
    bcc @no_div_possible

    ; Dividing was possible. Like with long tail divisions (on paper), we continue
    ; with the new remainder and the rest of the digits, which in this case can be
    ; accomplished by updating the remainder word with the remainder from the
    ; subtraction from above.
    sta remainder

@no_div_possible:
    dex
    bne @divloop              ; Process all 8 bits, before continuing.

    rol quotient              ; Shift last carry bit (representing if the last
                              ; division was possible or not) into the quotient.

    PULL_AXY
    rts

.endproc
