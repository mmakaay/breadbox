.include "{{ component_path }}/coding_macros.inc"

.import {{ api("delay") }}
.importzp {{ zp("delay_iterations") }}

; =========================================================================
; Delay for approximately a number of iterations * 5 CPU cycles.
;
; In:
;   iterations: word value, containing the number of iterations to perform

.macro DELAY _iterations
    .assert _iterations <= 65535, error, "DELAY overflow: iteration count exceeds 16-bit max (65535)."
    pha
    STORE16 {{ zp("delay_iterations") }}, _iterations
    jsr {{ api("delay") }}
    pla
.endmacro

; =========================================================================
; Compile-time microsecond delay.
;
; Converts a compile-time constant (microseconds) into the matching
; iteration count for the CPU clock, then calls delay.
;
; In:
;   us = delay duration in microseconds (compile-time constant)

.macro DELAY_US us
    DELAY ((us) * ({{ config.core.clock_hz }} / 1000)) / 5000
.endmacro

; =========================================================================
; Compile-time millisecond delay.
;
; Converts a compile-time constant (milliseconds) into the matching
; iteration count for the CPU clock, then calls delay.
;
; In:
;   ms = delay duration in milliseconds (compile-time constant)

.macro DELAY_MS ms
    DELAY_US (ms) * 1000
.endmacro
