.include "breadbox.inc"
.include "stdlib/io/print.inc"

.import WOZMON

.export main

.DATA

    lcd_text1:     .asciiz "BREADBOX  WozMon"
    lcd_text2:     .asciiz "Running @ serial"

    introduction: .byte   $0d, $0d, "** Welcome to BREADBOX WozMon **", $0d
                  .byte   $0d, "Commands:", $0d
                  .byte   "-------------+------------------------------------------------", $0d
                  .byte   "- XXXX       | Select and display value of $XXXX", $0d
                  .byte   "- XXXX.YYYY  | Select $XXXX and display all values up to $YYYY", $0d
                  .byte   "- XXXX:ZZ    | Store $ZZ in $XXXX", $0d
                  .byte   "- XXXXR      | JMP to code at $XXXX", $0d
                  .byte   "- R          } JMP to code at last selected address", $0d
                  .byte   "-------------+------------------------------------------------", $0d
                  .byte   $0d
                  .byte   $00

.CODE

    main:
        PRINT LCD::write, lcd_text1
        jsr LCD::
        PRINT LCD::write, lcd_text2
        PRINT CONSOLE::write_terminal, introduction
        jmp WOZMON
