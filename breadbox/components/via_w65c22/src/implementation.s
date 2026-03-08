; W65C22 VIA: {{ component_id }}

.include "{{ component_path }}/constants.inc"

.constructor {{ my("init") }}, 31

.segment "KERNALROM"

    ; =====================================================================
    ; Initialize VIA interrupt state.
    ;
    ; On warm CPU reset, the VIA can retain interrupt enables/flags from the
    ; previous run. Clear all pending VIA interrupt flags and disable all VIA
    ; interrupt sources so startup begins from a known state.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("init") }}
        lda #$7F
        sta IER

        lda #$7F
        sta IFR

        rts
    .endproc
