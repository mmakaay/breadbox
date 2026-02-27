.include "breadbox.inc"
.include "stdlib/math/divmod16.inc"

.export main

message: .asciiz "stdlib tester"

.proc main
    PRINT LCD, message
    DELAY_MS 300
    DELAY_MS 300

    ; Single divmod16 call.
    SET_WORD divmod16::dividend, 1337
    SET_WORD divmod16::divisor, 10
    jsr divmod16

    ; Display remainder as ASCII digit (expect '9')
    jsr LCD::clr
    lda divmod16::remainder
    clc
    adc #'0'
    sta LCD::byte
    jsr LCD::write

    HALT
.endproc
