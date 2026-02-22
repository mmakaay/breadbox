.include "breadbox.inc"

.export main

greeting:
    .asciiz "Hello, world!"

.proc main
    TRAMPOLINE_TO jumped_upon
    HALT
.endproc

.proc jumped_upon
    STATUS_LED_ON
    DELAY_MS 500
    STATUS_LED_OFF
    DELAY_MS 500
    rts
.endproc
