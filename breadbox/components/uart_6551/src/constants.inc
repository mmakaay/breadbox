; Constants for {{ component_id }}

; =========================================================================
; Settings
; =========================================================================

CTRL_BAUD   = {{ baud_code | hex }}

; =========================================================================
; Register addresses
; =========================================================================

DATA        = {{ (address + 0) | hex }} ; +$0 Transmit / Receive data
STATUS      = {{ (address + 1) | hex }} ; +$1 Status (write = soft reset)
CMD         = {{ (address + 2) | hex }} ; +$2 Command register
CTRL        = {{ (address + 3) | hex }} ; +$3 Control register

; =========================================================================
; Data sheet constants
; =========================================================================

; Status register bits (active high, active-low pins inverted)
SR_IRQ      = %10000000  ; Interrupt occurred
SR_DSR      = %01000000  ; Data Set Ready (0 = asserted)
SR_DCD      = %00100000  ; Data Carrier Detect (0 = asserted)
SR_TDRE     = %00010000  ; TX Data Register Empty (BROKEN on W65C51N)
SR_RDRF     = %00001000  ; RX Data Register Full
SR_OVR      = %00000100  ; Overrun error
SR_FE       = %00000010  ; Framing error
SR_PE       = %00000001  ; Parity error

; Command register bits
CMD_DTR     = %00000001  ; Data Terminal Ready (1 = assert /DTR)
CMD_IRQOFF  = %00000010  ; Receiver IRQ disable (1 = disabled)
CMD_TIC0    = %00000000  ; TX IRQ off, /RTS high
CMD_TIC1    = %00000100  ; TX IRQ on  (BROKEN on W65C51N)
CMD_TIC2    = %00001000  ; TX IRQ off, /RTS low (asserted)

; Control register bits
CTRL_1STOP  = %00000000  ; 1 stop bit
CTRL_8BIT   = %00000000  ; 8 data bits
CTRL_INTCLK = %00010000  ; Internal baud rate generator
