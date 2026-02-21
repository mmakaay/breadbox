.include "breadbox.inc"

.export main

greeting:
    .asciiz "Hello, world!"

.proc main
;    PRINT LCD0, greeting
    HALT
.endproc
