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
        .byte CR
        .byte CR
        .byte "** Welcome to BREADBOX WozMon **", CR
        .byte CR
        .byte "Commands:", CR
        .byte "-------------+------------------------------------------------", CR
        .byte "- XXXX       | Select and display value of $XXXX", CR
        .byte "- XXXX.YYYY  | Select $XXXX and display all values up to $YYYY", CR
        .byte "- XXXX:ZZ    | Store $ZZ in $XXXX", CR
        .byte "- XXXXR      | JMP to code at $XXXX", CR
        .byte "- R          } JMP to code at last selected address", CR
        .byte "-------------+------------------------------------------------", CR
        .byte CR
        .byte END

.CODE

    main:
        PRINT LCD::write, lcd_text1
        PRINT LCD::write, lcd_text2

        PRINT SERIAL::write_terminal, introduction

        jmp WOZMON
