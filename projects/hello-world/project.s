.include "breadbox.inc"

.export main

greeting_message: .asciiz "Hello, world!"

.proc main
    PRINT THE_DISPLAY, greeting_message
    HALT
.endproc

