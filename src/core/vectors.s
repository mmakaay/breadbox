.include "breadbox.inc"

.import __core_boot                  ; Import KERNAL boot subprocedure.

.constructor init_vectors, 32        ; Add constructor, max prio to run early.

.segment "ZEROPAGE"

    ; Address vectors, that can be modified in order to point
    ; to a custom interrupt handler.
    nmi_vector: .res 2
    irq_vector: .res 2

.segment "KERNAL"

    ; =========================================================================
    ; Setup the default vectors and interrupt handling.
    ; 
    ; - Interrupts disabled (call `cli` to enable interrupts)
    ; - Reset vector pointing to boot subroutine
    ; - Null NMI handler
    ; - Null IRQ handler
    ;
    ; Out:
    ;   A = clobbered

    .proc init_vectors
        sei
        SET_NMI null_interrupt_handler
        SET_IRQ null_interrupt_handler
        rts
    .endproc

    dispatch_nmi:
        jmp (nmi_vector)       ; Forward to configured NMI handler
    
    dispatch_irq:
        jmp (irq_vector)       ; Forward to configured IRQ handler

    null_interrupt_handler:
        rti

.segment "VECTORS"

    .word dispatch_nmi         ; Non-Maskable Interrupt vector
    .word __core_boot          ; Reset vector
    .word dispatch_irq         ; IRQ vector
