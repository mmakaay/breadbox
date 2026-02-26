; =========================================================================
; Halt program execution.

{{ importfn("halt") }}

.macro HALT
    jmp {{ symbol("halt") }}
.endmacro
