.export   __core_delay = delay
.exportzp __core_delay_iterations = iterations
.include "core/cpu_shims.inc"

.segment "ZEROPAGE"

    iterations: .res 2               ; 16-bit iteration count (lo/hi)

.segment "KERNAL"

    ; =========================================================================
    ; Delay for approximately a number of iterations * 5 CPU cycles.
    ;
    ; This subroutine can be called using the macros as provided by the
    ; `core/delay.inc` include file, e.g. `DELAY_MS 250`.
    ;
    ; In:
    ;   iterations = 16-bit iteration counter, in zeropage

    .proc delay
        phx
        phy

        ldy iterations               ; Low byte: partial first pass
        ldx iterations+1             ; High byte: number of full 256 passes
        inx                          ; Always run at least the low-byte pass
    @loop:
        dey
        bne @loop
        dex
        bne @loop

        ply
        plx
        rts
    .endproc
