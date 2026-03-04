.include "breadbox.inc"
.include "stdlib/math/fmtdec16.inc"
.include "stdlib/io/print.inc"

.export main

binary_value:  .word 1729

main:
    ; Convert value into decimal.
    CP_WORD fmtdec16::value, binary_value
    jsr fmtdec16

    ; Print the zero-padded string buffer, "01729".
    PRINT LCD::write, fmtdec16::padded

    ; Move to the second line.
    ldx #0
    ldy #1
    jsr LCD::cursor_move

    ; Print the pointer that points at the start of the first significant digit, "1729".
    PRINT_PTR LCD::write, fmtdec16::decimal

    HALT
