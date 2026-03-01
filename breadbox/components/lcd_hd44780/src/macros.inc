; HD44780 LCD: {{ component_id }} ({{ mode }} mode)

{% set P = symbol_prefix %}

; =========================================================================
; HD44780 command constants
; =========================================================================

{{ constant("CMD_CLEAR") }}      = $01  ; Clear display, set DDRAM address to 0
{{ constant("CMD_HOME") }}       = $02  ; Return cursor to home position
{{ constant("CMD_ENTRYMODE") }}  = $06  ; Increment cursor, no display shift
{{ constant("CMD_DISPLAY_ON") }} = $0C  ; Display on, cursor off, blink off
{% if mode == "4bit" %}
{{ constant("CMD_FUNCSET") }}    = $28  ; 4-bit mode, 2 lines, 5x8 font
{% else %}
{{ constant("CMD_FUNCSET") }}    = $38  ; 8-bit mode, 2 lines, 5x8 font
{% endif %}
{{ constant("CMD_SETDDRAM") }}   = $80  ; Set DDRAM address (OR with address)
{{ constant("CMD_SETCGRAM") }}   = $40  ; Set CGRAM address (OR with address)

{{ constant("BUSY_FLAG") }}      = $80  ; Busy flag mask (bit 7)
