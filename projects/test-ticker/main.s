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
        ; Print messages on the display.
        PRINT LCD::write, message1
        ldx #1
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, message2

        ; Run the execution loop, giving each task, in turn, a chance
        ; to perform some work.
    @loop:
        jsr update_led_task
        jsr update_lcd_task
        jsr update_console_task
        jmp @loop
    .endproc

    .proc update_led_task
        IF_TIMER_TRIGGERED TICKER::led_toggle_timer
            jsr LED::toggle
        ENDIF
    @done:
        rts
    .endproc

    .proc update_lcd_task
        IF_TIMER_TRIGGERED TICKER::lcd_update_timer
            ; Place the cursor after "ticker" on the display.
            ldx #0
            ldy #7
            jsr LCD::move_cursor

            ; Print the decimal value for bits 16-23 of the ticks counter.
            COPY fmtdec::value, TICKER::ticks + 2
            jsr fmtdec
            PRINT LCD::write, fmtdec::padded

            ; Print separator character.
            lda #' '
            jsr LCD::write

            ; Print the decimal value for bits 0-16 of the ticks counter.
            COPY16 fmtdec16::value, TICKER::ticks
            jsr fmtdec16
            PRINT LCD::write, fmtdec16::padded
        ENDIF
    @done:
        rts
    .endproc

    .proc update_console_task
        jsr CONSOLE::read
        bcc :+
        jsr CONSOLE::write_terminal
    :   rts
    .endproc
