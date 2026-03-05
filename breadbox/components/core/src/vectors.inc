.ifndef {{ symbol("VECTORS_S") }}  ; import + export in one module = unhappy linker
.importzp {{ symbol("nmi_vector") }}
.importzp {{ symbol("irq_vector") }}
.endif

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
; Note that interrupts are disabled (using `sei`) by default during boot.
; You will have to call `cli` to enable interrupt handling after setting
; the IRQ handler.
;
; In:
;   _handler: subroutine that must handle IRQ
; Out:
;   A = clobbered

.macro SET_IRQ _handler
    SET_POINTER irq_vector, _handler
.endmacro
