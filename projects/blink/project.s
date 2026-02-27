.include "breadbox.inc"

.export main

.proc main
    ; The delay macros use a 16-bit iteration counter to busy-wait
    ; the CPU. The iteration count scales with clock speed: faster
    ; clocks need more iterations for the same wall-clock delay.
    ;
    ; Since the counter is limited to 65535, the maximum delay
    ; per call depends on clock speed. Values that would exceed
    ; this limit are caught at assembly time.
    ;
    ; At the current clock speed, DELAY_MS 100 is safe, so we
    ; call it five times to get a 0.5 second delay. This works
    ; for clock speeds up to about 3 MHz.
    DELAY_MS 100
    DELAY_MS 100
    DELAY_MS 100
    DELAY_MS 100
    DELAY_MS 100

    jsr LED::toggle
    jmp main
.endproc
