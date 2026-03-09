.feature string_escapes
.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

.segment "DATA"

    banner: .asciiz "\nBREADBOX console test\n"

.segment "CODE"

    .proc main
        jsr LCD::cursor_on

        jsr SERIAL_TERMINAL::clr
        PRINT SERIAL_TERMINAL::write, banner

    @wait_for_input:
        jsr SERIAL::read
        bcc @wait_for_input

        pha
        jsr SERIAL_TERMINAL::write
        pla
        jsr LCD_TERMINAL::write

        jmp @wait_for_input
    .endproc
