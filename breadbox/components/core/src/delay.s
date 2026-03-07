.include "{{ component_path }}/coding_macros.inc"
.include "{{ component_path }}/cpu_shims_macros.inc"

.segment "ZEROPAGE"

    {{ zp_def("delay_iterations") }}: .res 2   ; 16-bit iteration count (lo/hi)

.segment "KERNALROM"

    ; =========================================================================
    ; Delay for approximately a number of iterations * 5 CPU cycles.
    ;
    ; This subroutine can be called using the macros as provided by the
    ; `core/delay_macros.inc` include file, e.g. `DELAY_MS 250`.
    ;
    ; In:
    ;   iterations = 16-bit iteration counter, in zeropage

    .proc {{ api_def("delay") }}
        phx
        phy

        ldy {{ zp("delay_iterations") }}    ; Low byte: partial first pass
        ldx {{ zp("delay_iterations") }}+1  ; High byte: number of full 256 passes
        inx                                 ; Always run at least the low-byte pass
    @loop:
        dey
        bne @loop
        dex
        bne @loop

        ply
        plx
        rts
    .endproc
