.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec16.inc"

.export main

; The number of ticks to wait, for each of the tasks.
LED_UPDATE_TICKS = 25  ; = 250ms
LCD_UPDATE_TICKS = 300 ; = 3s (high, to demonstrate >255 ticks delays)

.segment "RAM"

    last_led_toggle: .res 1
    last_lcd_update: .res 2

.segment "DATA"

    message: .asciiz "BREADBOX HWticks"

.segment "CODE"

    .proc main
        ; Display the message at line 2 of the display.
        ldx #0
        ldy #1
        jsr LCD::cursor_move
        PRINT LCD::write, message

        ; Initialize the timing variables.
        CP_BYTE last_led_toggle, TICKER::ticks
        CP_WORD last_lcd_update, TICKER::ticks

        ; Run the execution loop, giving each task, in turn, a chance
        ; to perform some work.
    @loop:
        jsr update_led_task
        jsr update_lcd_task
        jmp @loop
    .endproc

    .proc update_led_task
        ; Check if we have reach the next action time.
        sec
        lda TICKER::ticks
        sbc last_led_toggle
        cmp #LED_UPDATE_TICKS
        bcc @done

        ; Yes, record new toggle time and toggle the LED.
        CP_BYTE last_led_toggle, TICKER::ticks
        jsr LED::toggle
    @done:
        rts
    .endproc

    .proc update_lcd_task
        ; Check if we have reach the next action time.
        ; Since we wait for >255 ticks, here we must look at two of
        ; the ticker's counter bytes.
        sec
        lda TICKER::ticks
        sbc last_lcd_update
        tax
        lda TICKER::ticks+1
        sbc last_lcd_update+1
        cmp #>LCD_UPDATE_TICKS
        bcc @done
        bne @update
        txa
        cmp #<LCD_UPDATE_TICKS
        bcc @done

    @update:
        ; Yes, record the new lcd time.
        CP_WORD last_lcd_update, TICKER::ticks

        ; And update the LCD.
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
