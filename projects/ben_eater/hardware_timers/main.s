.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"
.include "stdlib/math/fmtdec16.inc"

.export main

LED_TIME = 25  ; 250ms
LCD_TIME = 100 ; 1s

.segment "RAM"

    led_timer: .res 3
    lcd_timer: .res 3

.segment "CODE"

    ; =========================================================================
    ; The main application.
    ;
    ; Runs the execution loop, giving each task, in turn, a chance to
    ; perform some work. The tasks don't block while waiting for their
    ; timer to expire, allowing multiple tasks to run concurrently.

    .proc main
        ; Schedule intitial adhoc timers.
        SET_ADHOC_TIMER TICKER::ticks, led_timer, LED_TIME
        SET_ADHOC_TIMER TICKER::ticks, lcd_timer, LCD_TIME

    @loop:
        jsr update_led_task
        jsr update_lcd_task
        jmp @loop
    .endproc

    ; =========================================================================
    ; Toggle the LED, if the LED timer has expired.

    .proc update_led_task
        ; This macro will run the code block and reset the timer when the
        ; timer has expired. Because of the reset,the toggle will happen
        ; about every <LED_TIME> ticks.
        IF_ADHOC_TIMER_EXPIRED TICKER::ticks, led_timer, LED_TIME
            jsr LED::toggle
        ENDIF
        rts
    .endproc

    ; =========================================================================
    ; Update the LCD display if the LCD timer has expired.

    .proc update_lcd_task
        IF_ADHOC_TIMER_EXPIRED TICKER::ticks, lcd_timer, LCD_TIME
            jsr LCD::home

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
        rts
    .endproc
