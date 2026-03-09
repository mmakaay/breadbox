.include "{{ component_path }}/coding_macros.inc"

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
        PUSH_X
        PUSH_Y

        ldy {{ zp("delay_iterations") }}    ; Low byte: partial first pass
        ldx {{ zp("delay_iterations") }}+1  ; High byte: number of full 256 passes

        ; Run low-byte pass first when non-zero.
        cpy #0
        beq @full_passes
    @low_pass:
        dey
        bne @low_pass

        ; Then run X full 256-count passes.
    @full_passes:
        cpx #0
        beq @done
    @full_loop:
        dey
        bne @full_loop
        dex
        bne @full_loop

    @done:
        PULL_Y
        PULL_X
        rts
    .endproc
