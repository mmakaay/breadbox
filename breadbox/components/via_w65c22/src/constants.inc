; Constants for {{ component_id }}

; =========================================================================
; Register addresses
; =========================================================================

BASE      = {{ address | hex }}
PORTB     = BASE + $00
PORTA     = BASE + $01
DDRB      = BASE + $02
DDRA      = BASE + $03
T1CL      = BASE + $04
T1CH      = BASE + $05
T1LL      = BASE + $06
T1LH      = BASE + $07
T2CL      = BASE + $08
T2CH      = BASE + $09
SR        = BASE + $0A
ACR       = BASE + $0B
PCR       = BASE + $0C
IFR       = BASE + $0D
IER       = BASE + $0E
PORTA_NH  = BASE + $0F
