; ---------------------------------------------------------------------------
; util.s — Shared output utilities.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"
.include "game.inc"

.segment "CODE"

    ; -----------------------------------------------------------------------
    ; Print A as a decimal number via the TTY.

    .proc print_dec_a
        sta fmtdec::value
        jsr fmtdec
        PRINT_PTR TTY::write, fmtdec::decimal
        rts
    .endproc
