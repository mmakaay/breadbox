.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"
.include "stdlib/math/fmtdec16.inc"

.export main

.segment "DATA"

    message1: .asciiz "ticker"
    message2: .asciiz "BREADBOX HWticks"

.segment "CODE"

    .proc main
        ; Printmessages on the display.
        PRINT LCD::write, message1
        ldx #0
        ldy #1
        jsr LCD::cursor_move
        PRINT LCD::write, message2

        ; Run the execution loop, giving each task, in turn, a chance
        ; to perform some work.
    @loop:
        jsr update_led_task
        jsr update_lcd_task
        jmp @loop
    .endproc

    .proc update_led_task
        lda TICKER::led_toggle
        beq @done
        SET_BYTE TICKER::led_toggle, #0

        jsr LED::toggle
    @done:
        rts
    .endproc

    .proc update_lcd_task
        lda TICKER::lcd_update
        beq @done
        SET_BYTE TICKER::lcd_update, #0

        ; Update the LCD with the current tick counter.

        ldx #7
        ldy #0
        jsr LCD::cursor_move

        ; Print the decimal value for bits 16-23 of the ticks counter.
        CP_BYTE fmtdec::value, TICKER::ticks + 2
        jsr fmtdec
        PRINT LCD::write, fmtdec::padded
        lda #' '
        jsr LCD::write

        ; Print the decimal value for bits 0-16 of the ticks counter.
        CP_WORD fmtdec16::value, TICKER::ticks
        jsr fmtdec16
        PRINT LCD::write, fmtdec16::padded
    @done:
        rts
    .endproc
