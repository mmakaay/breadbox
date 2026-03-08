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
        .byte "\n"
        .byte "\n"
        .byte "** Welcome to BREADBOX WozMon **\n"
        .byte "\n"
        .byte "Commands:\n"
        .byte "-------------+------------------------------------------------\n"
        .byte "- XXXX       | Select and display value of $XXXX\n"
        .byte "- XXXX.YYYY  | Select $XXXX and display all values up to $YYYY\n"
        .byte "- XXXX:ZZ    | Store $ZZ in $XXXX\n"
        .byte "- XXXXR      | JMP to code at $XXXX\n"
        .byte "- R          } JMP to code at last selected address\n"
        .byte "-------------+------------------------------------------------\n"
        .byte "\n"
        .byte END

.CODE

    main:
        PRINT CONSOLE::write, introduction

        PRINT LCD::write, lcd_text1
        PRINT LCD::write, lcd_text2

        jmp WOZMON
