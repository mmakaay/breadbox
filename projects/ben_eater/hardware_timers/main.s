.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec16.inc"

.export main

.segment "DATA"

    message: .asciiz "BREADBOX HWticks"

.segment "CODE"

    .proc main
        ; Display the message at line 2 of the display.
        ldx #0
        ldy #1
        jsr LCD::cursor_move
        PRINT LCD::write, message

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
        CLR_BYTE TICKER::led_toggle

        jsr LED::toggle
    @done:
        rts
    .endproc

    .proc update_lcd_task
        lda TICKER::lcd_update
        beq @done
        CLR_BYTE TICKER::lcd_update

        ; Update the LCD with the current tick counter.
        jsr LCD::home
        CP_WORD fmtdec16::value, TICKER::ticks + 2
        jsr fmtdec16
        PRINT LCD::write, fmtdec16::padded
        lda #' '
        jsr LCD::write
        CP_WORD fmtdec16::value, TICKER::ticks
        jsr fmtdec16
        PRINT LCD::write, fmtdec16::padded
    @done:
        rts
    .endproc
