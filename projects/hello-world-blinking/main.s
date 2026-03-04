; Hello world, slightly more complex than required, but demonstrating
; how to use (some of the) API subroutines on the LCD.

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

    ; Blink the message on the LCD.
    ; The display_off command will only blank the screen. The backlight
    ; is not controlled by the HD44780, and would require a separate power
    ; circuit to be driven using a GPIO pin for example.
    ; Without such circuit, the backlight stays on, and the code from below
    ; results in <blink> re-invented.
@loop:
    jsr _delay
    jsr LCD::display_off
    jsr _delay
    jsr LCD::display_on
    jmp @loop

.endproc

.proc _delay
    ldx #5
@wait1:
    DELAY_MS 100
    dex
    bne @wait1
    rts
.endproc
