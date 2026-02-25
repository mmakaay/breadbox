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

.export main

CTRL_D = $04

.segment "ZEROPAGE"

    cursor:     .res 1          ; LCD line 1 cursor position (0-15)
    debug_mode: .res 1          ; 0 = normal, 1 = debug

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
        jsr UART::read
        bcc @loop

        ; Check for CTRL+D toggle.
        lda UART::byte
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
        jsr set_cursor_line1
        lda UART::byte
        sta LCD::byte
        jsr LCD::write
        inc cursor

    @echo:
        ; Echo byte back via UART transmitter.
        jsr UART::write_terminal
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
    ; LCD display helpers
    ; ------------------------------------------------------------------

    ; Display the normal mode screen (title + hint).
    .proc show_normal_screen
        jsr LCD::clr
        PRINT LCD, msg_title
        jsr set_cursor_line2
        PRINT LCD, msg_hint
        rts
    .endproc

    ; Show the UART status register bits on LCD line 2.
    .proc show_status
        jsr set_cursor_line2

        ; Display "S:" prefix.
        lda #'S'
        sta LCD::byte
        jsr LCD::write
        lda #':'
        sta LCD::byte
        jsr LCD::write

        ; Display 8 status bits, MSB first.
        ; Bit meaning: IRQ DSR DCD TXE RXF OVR FRM PAR
        jsr UART::load_status
        lda UART::byte
        ldx #8
    @loop:
        ; Rotate MSB into carry, keeping all bits for next iteration.
        rol
        pha
        lda #'0'
        adc #0                   ; '0' + carry = '0' or '1'
        sta LCD::byte
        jsr LCD::write
        pla
        dex
        bne @loop

        rts
    .endproc

    ; Move LCD cursor to current position on line 1.
    .proc set_cursor_line1
        pha
        lda cursor
        ora #%10000000           ; Set DDRAM address command (bit 7)
        sta LCD::byte
        jsr LCD::write_cmnd
        pla
        rts
    .endproc

    ; Move LCD cursor to start of line 2.
    .proc set_cursor_line2
        pha
        lda #$c0                 ; DDRAM address = $40 (line 2)
        sta LCD::byte
        jsr LCD::write_cmnd
        pla
        rts
    .endproc

    ; Clear LCD line 1: write spaces and reset cursor to start.
    .proc clear_line1
        pha
        jsr LCD::home
        lda #' '
        sta LCD::byte
        ldx #16
    @loop:
        jsr LCD::write
        dex
        bne @loop
        CLR_BYTE cursor
        pla
        rts
    .endproc
