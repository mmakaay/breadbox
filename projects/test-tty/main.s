; ---------------------------------------------------------------------------
; TTY readline demo (non-blocking, canonical mode)
;
; Demonstrates the non-blocking behavior of TTY::readline: the main loop
; toggles the on-board LED on every iteration, calling readline each time.
; The LED keeps blinking visibly while the user types, because readline
; returns immediately when no complete line is available. When the user
; presses Enter, the line is printed back over the serial port and the
; loop continues.
;
; The LCD shows a count of completed lines so far.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"

.export main

; Caller-side buffer cap. The TTY internally caps at 240 bytes; this
; sets the demo's ceiling to 200 chars per line. The TTY beeps and
; refuses to accept further input when the user hits this cap (rather
; than silently truncating on Enter, which is the legacy POSIX behavior
; we deliberately don't replicate here).
LINE_MAX = 200

.segment "ZEROPAGE"

    line_count:      .res 1
    last_len:        .res 1
    echo_x:          .res 1

.segment "DATA"

    msg_banner:    .asciiz "\nTTY readline demo. Type a line and press Enter.\n\n"
    msg_prompt:    .asciiz "> "
    msg_you_typed: .asciiz "\nyou typed: \""
    msg_quote_nl:  .byte '"', '\n', 0
    msg_lcd_label: .asciiz "Lines: "

.segment "RAM"

    line_buffer: .res LINE_MAX

.segment "CODE"

    .proc main
        ; Initial banner over serial.
        jsr SERIAL_TTY::clr
        PRINT SERIAL_TTY::write, msg_banner

        ; LCD: display a "Lines: " label on row 0.
        jsr LCD::clr
        ldx #0
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, msg_lcd_label

        ; Initialize per-readline configuration. Pointers and the buffer
        ; cap stay valid across all readline calls.
        SET_POINTER SERIAL_TTY::prompt, msg_prompt
        SET_POINTER SERIAL_TTY::line_buffer, line_buffer
        lda #LINE_MAX
        sta SERIAL_TTY::line_max

        lda #0
        sta line_count
        jsr update_lcd_count

    @loop:
        jsr update_led_task

        ; Try to read a line. C=0 → not yet complete, keep looping.
        jsr SERIAL_TTY::readline
        bcc @loop

        ; A = length of the received line. Save it, then echo:
        ;   you typed: "<line>"
        sta last_len
        PRINT SERIAL_TTY::write, msg_you_typed

        ldx #0
    @echo_loop:
        cpx last_len
        beq @echo_done
        lda line_buffer,x
        stx echo_x                ; preserve X across write
        jsr SERIAL_TTY::write
        ldx echo_x
        inx
        bne @echo_loop            ; always taken, max 64 < 256

    @echo_done:
        PRINT SERIAL_TTY::write, msg_quote_nl

        inc line_count
        jsr update_lcd_count

        jmp @loop
    .endproc

    .proc update_led_task
        IF_TIMER_TRIGGERED TICKER::led_toggle_timer
            jsr LED::toggle
        ENDIF
    @done:
        rts
    .endproc

    ; ------------------------------------------------------------------
    ; Update the LCD line count (row 0, after the "Lines: " label).

    .proc update_lcd_count
        ldx #0
        ldy #7                  ; column right after "Lines: " label
        jsr LCD::move_cursor

        lda line_count
        sta fmtdec::value
        jsr fmtdec
        PRINT_PTR LCD::write, fmtdec::decimal

        rts
    .endproc
