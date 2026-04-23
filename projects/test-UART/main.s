; ----------------------------------------------------------------------------
; UART test
;
; Test for serial communication, using the TTY component to combine the
; serial input as keyboard and the serial output as screen. Received bytes
; are echoed back over the serial connection by the TTY component.
;
; The LCD shows status information.
; Two display modes, toggled at runtime with CTRL+D:
;
; Normal mode (default):
;   Line 1: "Serial test"
;   Line 2: "^D = debug"
;   Echo runs silently; LCD is not updated per byte.
;
; Debug mode:
;   Line 1: received characters (wraps after 16 chars)
;   Line 2: UART status register bits (updated continuously)
;   Useful for diagnosing signal integrity and flow control.
; ----------------------------------------------------------------------------

.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

CTRL_D = $04

.segment "ZEROPAGE"

    cursor:     .res 1          ; LCD line 1 cursor position (0-15)
    debug_mode: .res 1          ; 0 = normal, 1 = debug
    rxbyte:     .res 1          ; Last received byte

.segment "CODE"

    msg_title:   .asciiz "Serial test"
    msg_hint:    .asciiz "^D = debug"

    .proc main
        lda #0
        sta debug_mode
        jsr show_normal_screen

    @loop:
        ; In debug mode, continuously refresh the status display.
        lda debug_mode
        beq @wait_for_rx
        jsr show_status

    @wait_for_rx:
        ; Try to read a byte from the input.
        ; The TTY component takes care of echoing the byte back to
        ; the connected serial client.
        jsr TTY::read
        bcc @loop
        sta rxbyte               ; Save received byte.

        cmp #KEY_ESC
        beq @toggle

        cmp #CTRL_D
        beq @toggle

        ; In debug mode, display the byte on LCD line 1.
        lda debug_mode
        beq @loop

        ; Wrap cursor at end of LCD line 1.
        lda cursor
        cmp #16
        bne @display
        jsr clear_line1

    @display:
        ldy cursor
        ldx #0
        jsr LCD::move_cursor
        lda rxbyte
        jsr LCD::write
        inc cursor

        jmp @loop

    @toggle:
        lda debug_mode
        eor #1
        sta debug_mode
        beq @to_normal

        ; Switching to debug mode.
        jsr LCD::clr
        lda #16                  ; Force line 1 clear on first byte.
        sta cursor
        jmp @loop

    @to_normal:
        jsr show_normal_screen
        jmp @loop
    .endproc

    ; ------------------------------------------------------------------
    ; LCD helpers
    ; ------------------------------------------------------------------

    ; Display the normal mode screen (title + hint).
    .proc show_normal_screen
        jsr LCD::clr
        PRINT LCD::write, msg_title
        ldx #1
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, msg_hint
        rts
    .endproc

    ; Show the UART status register bits on LCD line 2.
    .proc show_status
        ldx #1
        ldy #0
        jsr LCD::move_cursor

        ; LCD "S:" prefix.
        lda #'S'
        jsr LCD::write
        lda #':'
        jsr LCD::write

        ; Display 8 status bits, MSB first.
        ; Bit meaning: IRQ DSR DCD TXE RXF OVR FRM PAR
        jsr SERIAL::load_status ; A = status byte
        ldx #8
    @loop:
        ; Rotate MSB into carry, keeping all bits for next iteration.
        rol
        pha
        lda #'0'
        adc #0                   ; '0' + carry = '0' or '1'
        jsr LCD::write
        pla
        dex
        bne @loop

        rts
    .endproc

    ; Clear LCD line 1: write spaces and reset cursor to start.
    .proc clear_line1
        jsr LCD::home
        ldx #16
    @loop:
        lda #' '
        jsr LCD::write
        dex
        bne @loop
        ZERO cursor
        rts
    .endproc
