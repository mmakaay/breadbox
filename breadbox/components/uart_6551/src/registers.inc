; 6551 UART register addresses: {{ component_id }} (base {{ address | hex }})

{{ constant("DATA") }}   = {{ address | hex }}       ; +$0 Transmit / Receive data
{{ constant("STATUS") }} = {{ (address + 1) | hex }} ; +$1 Status (write = soft reset)
{{ constant("CMD") }}    = {{ (address + 2) | hex }} ; +$2 Command register
{{ constant("CTRL") }}   = {{ (address + 3) | hex }} ; +$3 Control register
