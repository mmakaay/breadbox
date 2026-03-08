.feature string_escapes
.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

.segment "DATA"

    banner: .asciiz "\nBREADBOX console test\n"

.segment "CODE"

    .proc main
        jsr LCD::cursor_on

        jsr SERIAL_CONSOLE::clr
        PRINT SERIAL_CONSOLE::write, banner

    @wait_for_input:
        jsr SERIAL::read
        bcc @wait_for_input

        pha
        jsr SERIAL_CONSOLE::write
        pla
        jsr LCD_CONSOLE::write

        jmp @wait_for_input
    .endproc
