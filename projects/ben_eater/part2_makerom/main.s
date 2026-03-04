.include "breadbox.inc"

.export main

main:
    lda #$55
    jsr LEDS::write
    lda #$aa
    jsr LEDS::write
    jmp main
