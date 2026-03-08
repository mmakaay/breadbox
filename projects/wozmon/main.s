.feature string_escapes
.include "breadbox.inc"
.include "stdlib/io/print.inc"

.import WOZMON

.export main

.DATA

    CR = $0d
    END = $00

    lcd_text1:
        .asciiz "BREADBOX  WozMon"

    lcd_text2:
        .asciiz "Running @ serial"

    introduction:
        .byte "\r"
        .byte "\r"
        .byte "** Welcome to BREADBOX WozMon **\r"
        .byte "\r"
        .byte "Commands:\r"
        .byte "-------------+------------------------------------------------\r"
        .byte "- XXXX       | Select and display value of $XXXX\r"
        .byte "- XXXX.YYYY  | Select $XXXX and display all values up to $YYYY\r"
        .byte "- XXXX:ZZ    | Store $ZZ in $XXXX\r"
        .byte "- XXXXR      | JMP to code at $XXXX\r"
        .byte "- R          } JMP to code at last selected address\r"
        .byte "-------------+------------------------------------------------\r"
        .byte "\r"
        .byte END

.CODE

    main:
        PRINT CONSOLE::write_terminal, introduction

        PRINT LCD::write, lcd_text1
        PRINT LCD::write, lcd_text2

        jmp WOZMON
