.include "{{ component_path }}/macros.inc"

.ifndef {{ symbol("DELAY_S") }}  ; import + export in one module = unhappy linker
.import {{ symbol("delay") }}
.importzp {{ symbol("delay_iterations") }}
.endif

; =========================================================================
; Delay for approximately a number of iterations * 5 CPU cycles.
;
; In:
;   iterations: word value, containing the number of iterations to perform

.macro DELAY _iterations
    .assert _iterations <= 65535, error, "DELAY overflow: iteration count exceeds 16-bit max (65535)."
    pha
    SET_WORD {{ symbol("delay_iterations") }}, _iterations
    jsr {{ symbol("delay") }}
    pla
.endmacro

; =========================================================================
; Compile-time microsecond delay.
;
; Converts a compile-time constant (microseconds) into the matching
; iteration count for the CPU_CLOCK, then calls delay.
;
; In:
;   us = delay duration in microseconds (compile-time constant)

.macro DELAY_US us
    DELAY ((us) * (CPU_CLOCK / 1000)) / 5000
.endmacro

; =========================================================================
; Compile-time millisecond delay.
;
; Converts a compile-time constant (milliseconds) into the matching
; iteration count for the CPU_CLOCK, then calls delay.
;
; In:
;   ms = delay duration in milliseconds (compile-time constant)

.macro DELAY_MS ms
    DELAY_US (ms) * 1000
.endmacro
