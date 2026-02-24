; =========================================================================
; Set the address of the NMI (Non-Maskable Interrupt) handler.
;
; In: 
;   _handler: subroutine that must handle NMI
; Out:
;   A clobbered

.macro SET_NMI _handler
    lda #<_handler
    sta nmi_vector
    lda #>_handler
    sta nmi_vector + 1
.endmacro

; =========================================================================
; Set the address of the IRQ (Interrupt ReQuest) handler.
;
; Note that interrupts are disabled (using `sei`) by default during boot.
; You will have to call `cli` to enable interrupt handling after setting
; the IRQ handler.
;
; In:
;   _handler: subroutine that must handle IRQ
; Out:
;   A = clobbered

.macro SET_IRQ _handler
    lda #<_handler
    sta irq_vector
    lda #>_handler
    sta irq_vector + 1
.endmacro


