.include "breadbox.inc"

.export main

greeting: .asciiz "Hello, world!"

.proc main
    lda #<greeting
    sta the_display::ptr
    lda #>greeting
    sta the_display::ptr + 1
    jsr the_display::print

    HALT
.endproc
