.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"

.export main

.segment "DATA"

    message: .asciiz "BREADBOX TTYtest"

.segment "CODE"

    .proc main
        jsr TTY::clr
        PRINT LCD::write, message

    @loop:
        jsr TTY::read
        jsr TTY2::write
        bcc @loop
    .endproc
