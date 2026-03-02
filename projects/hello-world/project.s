.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

greeting_message: .asciiz "Hello, world!"

.proc main
    PRINT LCD::write, greeting_message
    HALT
.endproc
