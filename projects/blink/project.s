.include "breadbox.inc"

.export main

.proc main
    LED_toggle
    DELAY_MS 500
    jmp main
.endproc
