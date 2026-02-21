.include "breadbox.inc"

.export main

greeting:
    .asciiz "Hello, world!"

.proc main
    TRAMPOLINE_TO jumped_upon
    HALT
.endproc

.proc jumped_upon
    rts
.endproc
