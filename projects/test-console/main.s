.feature string_escapes
.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

.segment "DATA"

    banner: .asciiz "\rBREADBOX console test\r"

.segment "CODE"

    .proc main
        jsr LCD::cursor_on
        PRINT SERIAL::write_terminal, banner

    @wait_for_input:
        jsr SERIAL::read
        bcc @wait_for_input

        pha
        jsr SERIAL::write_terminal
        pla
        jsr LCD_CONSOLE::write

        jmp @wait_for_input
    .endproc
