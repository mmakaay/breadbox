; UART 6551: {{ component_id }} ({{ type }})

{% set P = symbol_prefix %}

; =========================================================================
; 6551 ACIA register addresses
; =========================================================================

{{ constant("DATA") }}   = {{ address | hex }}       ; +$0 Transmit / Receive data
{{ constant("STATUS") }} = {{ (address + 1) | hex }} ; +$1 Status (write = soft reset)
{{ constant("CMD") }}    = {{ (address + 2) | hex }} ; +$2 Command register
{{ constant("CTRL") }}   = {{ (address + 3) | hex }} ; +$3 Control register

; Baud rate selector (requires internal clock, 1.8432 MHz crystal)
{{ constant("CTRL_BAUD") }}   = {{ baud_code | hex }}
