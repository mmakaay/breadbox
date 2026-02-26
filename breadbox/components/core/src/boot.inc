.ifndef {{ symbol("API_S") }}  ; import + export in one module = unhappy linker
.import {{ symbol("halt") }}
.endif

; =========================================================================
; Halt program execution.

.macro HALT
    jmp {{ symbol("halt") }}
.endmacro
