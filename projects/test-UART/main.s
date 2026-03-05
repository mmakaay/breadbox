; ----------------------------------------------------------------------------
; UART test
;
; Echo test for serial communication. Received bytes are echoed back over
; the serial connection. The LCD shows status information.
;
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
        ; Try to read a byte from the receive buffer.
        jsr CONSOLE::read
        bcc @loop
        sta rxbyte               ; Save received byte.

        cmp #CTRL_D
        beq @toggle

        ; In debug mode, display the byte on LCD line 1.
        lda debug_mode
        beq @echo

        ; Wrap cursor at end of LCD line 1.
        lda cursor
        cmp #16
        bne @display
        jsr clear_line1

    @display:
        ldx cursor
        ldy #0
        jsr DISPLAY::cursor_move
        lda rxbyte
        jsr DISPLAY::write
        inc cursor

    @echo:
        ; Echo byte back via UART transmitter.
        lda rxbyte
        jsr CONSOLE::write_terminal
        jmp @loop

    @toggle:
        lda debug_mode
        eor #1
        sta debug_mode
        beq @to_normal

        ; Switching to debug mode.
        jsr DISPLAY::clr
        lda #16                  ; Force line 1 clear on first byte.
        sta cursor
        jmp @loop

    @to_normal:
        jsr show_normal_screen
        jmp @loop
    .endproc

    ; ------------------------------------------------------------------
    ; LCD display helpers
    ; ------------------------------------------------------------------

    ; Display the normal mode screen (title + hint).
    .proc show_normal_screen
        jsr DISPLAY::clr
        PRINT DISPLAY::write, msg_title
        ldx #0
        ldy #1
        jsr DISPLAY::cursor_move
        PRINT DISPLAY::write, msg_hint
        rts
    .endproc

    ; Show the UART status register bits on LCD line 2.
    .proc show_status
        ldx #0
        ldy #1
        jsr DISPLAY::cursor_move

        ; Display "S:" prefix.
        lda #'S'
        jsr DISPLAY::write
        lda #':'
        jsr DISPLAY::write

        ; Display 8 status bits, MSB first.
        ; Bit meaning: IRQ DSR DCD TXE RXF OVR FRM PAR
        jsr CONSOLE::load_status ; A = status byte
        ldx #8
    @loop:
        ; Rotate MSB into carry, keeping all bits for next iteration.
        rol
        pha
        lda #'0'
        adc #0                   ; '0' + carry = '0' or '1'
        jsr DISPLAY::write
        pla
        dex
        bne @loop

        rts
    .endproc

    ; Clear LCD line 1: write spaces and reset cursor to start.
    .proc clear_line1
        jsr DISPLAY::home
        ldx #16
    @loop:
        lda #' '
        jsr DISPLAY::write
        dex
        bne @loop
        ZERO cursor
        rts
    .endproc
