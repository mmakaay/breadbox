.importzp {{ api("nmi_vector") }}
.importzp {{ api("irq_vector") }}

; =========================================================================
; Set the address of the NMI (Non-Maskable Interrupt) handler.
;
; In:
;   _handler: subroutine that must handle NMI
; Out:
;   A clobbered

.macro SET_NMI _handler
    SET_POINTER nmi_vector, _handler
.endmacro

; =========================================================================
; Set the address of the IRQ (Interrupt ReQuest) handler.
;
; Note that interrupts are automatically enabled by the boot sequence when
; interruptors are registered. Use SET_IRQ to override the default IRQ
; handler, which dispatches through the CONDES interruptor table.
;
; In:
;   _handler: subroutine that must handle IRQ
; Out:
;   A = clobbered

.macro SET_IRQ _handler
    SET_POINTER irq_vector, _handler
.endmacro
