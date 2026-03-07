; =========================================================================
; Halt program execution.

.macro HALT
    jmp {{ api("halt") }}
.endmacro
