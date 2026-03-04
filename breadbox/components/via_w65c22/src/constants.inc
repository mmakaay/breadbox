; Constants for {{ component_id }}

; =========================================================================
; Register addresses
; =========================================================================

BASE             = {{ address | hex }}
PORTB            = BASE + $00      ; Port B data (in/out depending on DDRB)
PORTA            = BASE + $01      ; Port A data (in/out depending on DDRA)
DDRB             = BASE + $02      ; Data directions port B (bit 0 = in, 1 = out)
DDRA             = BASE + $03      ; Data directions port A (bit 0 = in, 1 = out)
T1CL             = BASE + $04      ; T1 counter format and operation, low byte
T1CH             = BASE + $05      ; T1 counter format and operation, high byte
T1_COUNTER       = T1CL            ; Convenience alias
T1LL             = BASE + $06      ; T1 latch format and operation, low byte
T1LH             = BASE + $07      ; T1 latch format and operation, high byte
T1_LATCH         = T1LL            ; Convenience alias
T2CL             = BASE + $08      ; T2 lower-order latches (write) / counter (read)
T2CH             = BASE + $09      ; T2 high-order counter
T2_COUNTER       = T2CL            ; Convenience alias
SR               = BASE + $0A      ; Shift register
ACR              = BASE + $0B      ; Auxiliary Control Register
PCR              = BASE + $0C      ; Peripheral Control Register
IFR              = BASE + $0D      ; Interrupt Flag Register
IER              = BASE + $0E      ; Interrupt Enable Register
PORTA_NH         = BASE + $0F      ; Same as Reg 1 except no "Handshake"

; =========================================================================
; Data sheet
; =========================================================================

; PCR register bits
; -------------------------------------------------------------------------

; CA1 control
PCR_CA1_MASK     = %11111110
PCR_CA1_NAE      = %00000000       ; Negative Action Edge (falling edge)
PCR_CA1_PAE      = %00000001       ; Positive Action Edge (rising edge)

; PCR CA2 control
PCR_CA2_MASK     = %11110001
PCR_CA2_INNE     = %00000000       ; Input-negative action edge (falling edge)
PCR_CA2_IIINE    = %00000010       ; Independent interrupt input-negative edge
PCR_CA2_IPAE     = %00000100       ; Input-positive action edge (rising edge)
PCR_CA2_IIIPE    = %00000110       ; Independent interrupt input-positive edge
PCR_CA2_HS       = %00001000       ; Handshake output
PCR_CA2_PULSE    = %00001010       ; Pulse output
PCR_CA2_LOW      = %00001100       ; Low output
PCR_CA2_HIGH     = %00001110       ; High output

; CB1 control
PCR_CB1_MASK     = %00010000
PCR_CB1_NAE      = %00000000       ; Negative Action Edge (falling edge)
PCR_CB1_PAE      = %00001000       ; Positive Action Edge (rising edge)

; PCR CB2 control
PCR_CB2_MASK     = %00011111
PCR_CB2_INAE     = %00000000       ; Input-negative action edge (falling edge)
PCR_CB2_IIINE    = %00100000       ; Independent interrupt input-negative edge
PCR_CB2_IPAE     = %01000000       ; Input-positive action edge (rising edge)
PCR_CB2_IIIPE    = %01100000       ; Independent interrupt input-positive edge
PCR_CB2_HS       = %10000000       ; Handshake output
PCR_CB2_PULSE    = %10100000       ; Pulse output
PCR_CB2_LOW      = %11000000       ; Low output
PCR_CB2_HIGH     = %11100000       ; High output

; ACR register bits
; -------------------------------------------------------------------------

; T1 timer control
ACR_T1_MASK      = %00111111
ACR_T1_T         = %00000000       ; Timed interrupt each time T1 is loaded
ACR_T1_C         = %01000000       ; Continuous interrupts
ACR_TI_TPB7      = %10000000       ; ACT_TI_T with one shot output on PB7
ACR_T1_CPB7      = %11000000       ; ACT_TI_C with aquare wave output on PB7

; T2 timer control
ACR_T2_MASK      = %11011111
ACR_T2_T         = %00000000       ; Timed interrupt
ACR_T2_CPB6      = %00100000       ; Count down with pulses on PB6

; Shift register control
ACR_SR_MASK      = %11100011
ACR_SR_OFF       = %00000000       ; Shift register disabled
ACR_SR_IT2       = %00000100       ; Shift in under control of T2
ACR_SR_IPHI2     = %00001000       ; Shift in under control of PHI2
ACR_SR_ICLK      = %00001100       ; Shift in under control of external clock
ACR_SR_OFREE     = %00010000       ; Shift out free running at T2 rate
ACR_SR_OT2       = %00010100       ; Shift out under control of T2
ACR_SR_OPHI2     = %00011000       ; Shift out under control of PHI2
ACR_SR_OCLK      = %00011100       ; Shift out under control of external clock

; Latch enable/disable
ACR_LAT_MASK     = %11111100
ACR_LAT_OFF      = %00000000       ; Latching disabled
ACR_LAT_ON       = %00000011       ; Latching enabled

; IFR register bits
; -------------------------------------------------------------------------

IFR_CA2          = %00000001       ; CA2 active edge
IFR_CA1          = %00000010       ; CA1 active edge
IFR_SR_READY     = %00000100       ; Complete 8 bit shift
IFR_CB2          = %00001000       ; CB2 active edge
IFR_CB1          = %00010000       ; CB1 active edge
IFR_T2           = %00100000       ; Time out of T2
IFR_T1           = %01000000       ; Time out of T1
IFR_ANY          = %10000000       ; Any of the above interrupts enabled

; IER register bits
;
; On write, bit 7 = 0, each logic 1 in bits 0-6 disables related interrupt.
; On write, bit 7 = 1, each logic 1 in bits 0-6 enables relaed interrupt.
; On read, bit 7 = 1 and all other bits reflect interrupt enable/disable state.
; -------------------------------------------------------------------------

IER_CA2          = %00000001       ; CA2 active edge
IER_CA1          = %00000010       ; CA1 active edge
IER_SR_READY     = %00000100       ; Complete 8 bit shift
IER_CB2          = %00001000       ; CB2 active edge
IER_CB1          = %00010000       ; CB1 active edge
IER_T2           = %00100000       ; Time out of T2
IER_T1           = %01000000       ; Time out of T1
IER_TURN_ON      = %10000000       ; On write, enable interrupts
IER_TURN_OFF     = %00000000       ; On write, disable interrupts
