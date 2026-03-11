.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"

.export main

.segment "DATA"

    message: .asciiz "\nBREADBOX TTY tester\n\n"

.segment "CODE"

    .proc main
        jsr SERIAL_TTY::clr
        PRINT SERIAL_TTY::write, message

        jsr LCD::cursor_on
        jsr LCD_TTY::clr

    @loop:
        jsr LCD_TTY::read
        bcc @loop

        sta fmtdec::value
        jsr fmtdec
        PRINT_PTR SERIAL_TTY::write, fmtdec::decimal
        lda #'\n'
        jsr SERIAL_TTY::write

        jmp @loop
    .endproc
