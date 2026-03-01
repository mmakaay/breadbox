; Hello world, slightly more complex than required, but demonstrating
; clearly how to use API subroutines on the LCD.

.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

greeting_message: .asciiz "!!dlroW ,olleH"

.proc main
    ; Move the cursor to coordinate (14, 0)
    ; This is towards the end of line 1 one a 2x16 display.
    ldx #14
    ldy #0
    jsr LCD::cursor_move

    ; Set the text direction from right to left.
    jsr LCD::right_to_left

    ; Print the message. Since we're going right to left, the
    ; text will eventually show up in reverse on the screen.
    PRINT LCD::write, greeting_message

    HALT
.endproc

