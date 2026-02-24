.import   __core_delay
.importzp __core_delay_iterations

; =========================================================================
; Delay for approximately a number of iterations * 5 CPU cycles.
;
; In:
;   iterations: word value, containing the number of iterations to perform
; Out:
;   A = clobbered

.macro DELAY iterations
    lda #<iterations
    sta __core_delay_iterations
    lda #>iterations
    sta __core_delay_iterations + 1
    jsr __core_delay
.endmacro

; =========================================================================
; Compile-time microsecond delay.
;
; Converts a compile-time constant (microseconds) into the matching
; iteration count for the CPU_CLOCK, then calls delay.
;
; In:
;   us = delay duration in microseconds (compile-time constant)
; Out:
;   A = clobbered

.macro DELAY_US us
    .local ITERATIONS
    ITERATIONS = (us * (CPU_CLOCK / 1000000)) / 5
    DELAY ITERATIONS
 .endmacro

; =========================================================================
; Compile-time millisecond delay.
;
; Converts a compile-time constant (milliseconds) into the matching
; iteration count for the CPU_CLOCK, then calls delay.
;
; In:
;   ms = delay duration in milliseconds (compile-time constant)
; Out:
;   A = clobbered

.macro DELAY_MS ms
    DELAY_US ms * 1000
.endmacro
