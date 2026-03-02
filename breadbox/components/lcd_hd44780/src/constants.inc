; Constants for {{ component_id }}

; =========================================================================
; Data sheet
; =========================================================================

; Command bases
CMD_CLEAR         = $01         ; Clear display, set DDRAM address to 0
CMD_HOME          = $02         ; Return cursor to home, reset display shift
CMD_ENTRYMODE     = $04         ; Entry mode set (base)
CMD_DISPLAY       = $08         ; Display on/off control (base)
CMD_SHIFT         = $10         ; Cursor/display shift (base)
CMD_FUNCSET       = $20         ; Function set (base, init only)
CMD_SETCGRAM      = $40         ; Set CGRAM address (OR with 6-bit address)
CMD_SETDDRAM      = $80         ; Set DDRAM address (OR with 7-bit address)

; Entry Mode Set option bits (OR with CMD_ENTRYMODE)
BIT_ENTRY_INC     = %00000010   ; I/D=1: increment cursor (moves right after write)
BIT_ENTRY_SHIFT   = %00000001   ; S=1: shift entire display with each write

; Display Control option bits (OR with CMD_DISPLAY)
BIT_DISPLAY_ON    = %00000100   ; D=1: display on
BIT_CURSOR_ON     = %00000010   ; C=1: cursor visible
BIT_BLINK_ON      = %00000001   ; B=1: cursor blink on

; Cursor/Display Shift option bits (OR with CMD_SHIFT)
BIT_SHIFT_DISPLAY = %00001000   ; S/C=1: shift display (0: move cursor)
BIT_SHIFT_RIGHT   = %00000100   ; R/L=1: right (0: left)

; Status read
BUSY_FLAG         = %10000000   ; Busy flag (bit 7 of status read)
