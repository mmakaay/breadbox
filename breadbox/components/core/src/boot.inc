; =========================================================================
; Halt program execution.

.import __core_halt

.macro HALT
    jmp __core_halt
.endmacro
