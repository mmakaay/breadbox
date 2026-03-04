.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

.segment "RAM"

    timestamp: .res 1

.segment "DATA"

    message1: .asciiz "Van links...    "
    message2: .asciiz "  ...naar rechts"

.segment "CODE"

    .proc main
        jsr LCD::home
        PRINT LCD::write, message1

        jsr delay

        jsr LCD::home
        PRINT LCD::write, message2

        jsr delay
        jmp main
    .endproc

    .proc delay
        CP_BYTE timestamp, TICKER::ticks
    @wait:
        sec
        lda TICKER::ticks
        sbc timestamp
        cmp #150  ; 150 * 10ms = 1.5s
        bcc @wait
        rts
    .endproc
