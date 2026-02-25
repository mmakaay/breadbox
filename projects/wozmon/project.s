.include "breadbox.inc"

.import __WOZMON_START__

lcd_text:     .asciiz "Running WozMon"
introduction: .byte   $0d, $0d, "** Welcome to BREADBOX WozMon **", $0d
              .byte   $0d, "Commands:", $0d
              .byte   "-------------+------------------------------------------------", $0d
              .byte   "- XXXX       | Select and display value of $XXXX", $0d
              .byte   "- XXXX.YYYY  | Select $XXXX and display all values up to $YYYY", $0d
              .byte   "- XXXX:ZZ    | Store $ZZ in $XXXX", $0d
              .byte   "- XXXXR      | JMP to code at $XXXX", $0d
              .byte   "- R          } JMP to code at last selected address", $0d
              .byte   "-------------+------------------------------------------------", $0d, $0d, $00

main:

    .ifdef LCD
    PRINT LCD, lcd_text
    .endif
    PRINT UART, introduction
    jmp __WOZMON_START__
