.ifndef {{ symbol("vectors_s") }}
{{ importzp("nmi_vector") }}
{{ importzp("irq_vector") }}
.endif

.include "macros.inc"

; =========================================================================
; Set the address of the NMI (Non-Maskable Interrupt) handler.
;
; In:
;   _handler: subroutine that must handle NMI
; Out:
;   A clobbered

.macro SET_NMI _handler
    CP_ADDRESS nmi_vector, _handler
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
    CP_ADDRESS irq_vector, _handler
.endmacro
