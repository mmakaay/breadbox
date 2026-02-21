.include "breadbox.inc"

.export main

greeting:
    .asciiz "Hello, world!"

.proc main
    TRAMPOLINE_TO other
    HALT
.endproc

.proc other
    lda #$ff
    nop
    nop
    nop
    rts
.endproc
