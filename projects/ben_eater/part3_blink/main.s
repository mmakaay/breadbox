.include "breadbox.inc"

.export main

main:
    lda #$50                 ; Use $50 (%01010000)
@loop:
    pha
    jsr LEDS::write          ; Update the GPIO pin output values.
    pla
    ror                      ; Shift bits in value to the right.
    jmp @loop
