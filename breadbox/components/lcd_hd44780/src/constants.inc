; HD44780 command and status constants (from datasheet).

CMD_CLEAR      = $01  ; Clear display, set DDRAM address to 0
CMD_HOME       = $02  ; Return cursor to home position
CMD_ENTRYMODE  = $06  ; Increment cursor, no display shift
CMD_DISPLAY_ON     = $0C  ; Display on, cursor off, blink off
CMD_FUNCSET_4BIT   = $28  ; 4-bit mode, 2 lines, 5x8 font
CMD_FUNCSET_8BIT   = $38  ; 8-bit mode, 2 lines, 5x8 font
CMD_SETDDRAM   = $80  ; Set DDRAM address (OR with address)
CMD_SETCGRAM   = $40  ; Set CGRAM address (OR with address)

BUSY_FLAG      = $80  ; Busy flag mask (bit 7)
