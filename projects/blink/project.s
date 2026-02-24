.include "breadbox.inc"

.export main

.proc main
    LED_on
    DELAY_MS 500
    LED_off
    DELAY_MS 500
    jmp main
.endproc
