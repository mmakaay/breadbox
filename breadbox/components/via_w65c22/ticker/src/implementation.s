; Ticker: {{ component_id }} on {{ provider_device.id }} timer T1, {{ ms_per_tick }}ms/tick

.include "CORE/macros.inc"
.include "{{ provider_device.component_path }}/constants.inc"

; Add constructor to BREADBOX, using a high prio, to allow other components
; to make use of the ticker, when required for their initialization.
; Not the highest priority of 32, because that one sets up interrupt vectors,
; which is a requirement for this component.
.constructor {{ my("init") }}, 31

; Add interrupt handler to BREADBOX.
.interruptor {{ my("irq_handler") }}

.segment "KERNALRAM"

    {{ api_def("ticks") }}: .res 4    ; 4 byte counter, for a wide range of options

.segment "KERNALROM"

    ; =========================================================================
    ; Initialize {{ component_id }}: configure timer T1 in free-running mode.
    ;
    ; Called automatically during boot via .constructor.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("init") }}
        ; Clear the ticker counter.
        lda #0
        sta {{ api("ticks") }}
        sta {{ api("ticks") }} + 1
        sta {{ api("ticks") }} + 2
        sta {{ api("ticks") }} + 3

        ; Configure T1 count down value.
        SET_WORD T1_COUNTER, {{ cycles_per_tick }}

        ; Configure T1 for free-running mode.
        lda ACR                   ; Get existing configuration.
        and #ACR_T1_MASK          ; Clear the T1 settings bits.
        ora #ACR_T1_C             ; Enable continuous interrupts.
        sta ACR                   ; Write back updated configuration.

        ; Enable T1 interrupts.
        SET_BYTE IER, #(IER_TURN_ON | IER_T1)

        cli                       ; Enable interrupts.

        rts
    .endproc

    ; =========================================================================
    ; Handle T1 timer interrupts.
    ;
    ; When the timer triggers, the ticks counter is incremented.

    .proc {{ my_def("irq_handler") }}
        lda #IFR_T1               ; Prepare bit check for T1 interrupt.
        bit IFR                   ; Check if T1 interrupt was triggered.
        beq @done                 ; No interrupt triggered? Then we're done.

        SET_BYTE IFR, #IFR_T1     ; Clear the T1 interrupt flag.

        inc {{ api("ticks") }}    ; Increment the ticks counter.
        bne @done
        inc {{ api("ticks") }} + 1
        bne @done
        inc {{ api("ticks") }} + 2
        bne @done
        inc {{ api("ticks") }} + 3
    @done:
        rts
    .endproc
