.include "breadbox.inc"

.export main

greeting: .asciiz "Hello, world!"

.proc main
    lda #<greeting
    sta THE_DISPLAY::ptr
    lda #>greeting
    sta THE_DISPLAY::ptr + 1
    jsr THE_DISPLAY::print

    HALT
.endproc
