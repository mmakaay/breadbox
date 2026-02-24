.ifndef __CORE_BOOT_INC
__CORE_BOOT_INC = 1

; =========================================================================
; Halt program execution.

.import __core_halt

.macro HALT
    jmp __core_halt
.endmacro


; =========================================================================
; Classic 6502 JSR trampoline.
;
; The 6502 has no `JSR (indirect)` instruction. Work around this by
; doing a `jsr` into a subroutine (the trampoline) that then does a `jmp`
; to the target subroutine address. When that subroutine does its `rts`,
; the program pointer returns to the point from where the `jsr` was done.
;
; In:
;   trampoline_to: address, containing a pointer to the subroutine to call
; Out:
;   A = clobbered

.importzp __core_trampoline_to
.import __core_trampoline

.macro TRAMPOLINE_TO _target_routine
    lda #<_target_routine
    sta __core_trampoline_to
    lda #>_target_routine
    sta __core_trampoline_to + 1
    jsr __core_trampoline
.endmacro

.endif
