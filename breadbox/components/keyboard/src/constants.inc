; ----------------------------------------------------------------
; Codes for expressing key presses.
; ----------------------------------------------------------------

MODIFIER_CTRL = %00000001

KEY_SOH         = 1        ; Start Of Heading
KEY_CTRL_A      = KEY_SOH
KEY_SOT         = 2        ; Start Of Text
KEY_CTRL_B      = KEY_SOT
KEY_LEFT        = KEY_SOT
KEY_EOT         = 3        ; End Of Text
KEY_CTRL_C      = KEY_EOT
KEY_EOTX        = 4        ; End Of Transmission
KEY_CTRL_D      = KEY_EOTX
KEY_ENQUIRY     = 5
KEY_CTRL_E      = KEY_ENQUIRY
KEY_ACK         =  6       ; Acknowledge
KEY_RIGHT       = KEY_ACK
KEY_CTRL_F      = KEY_ACK
KEY_CTRL_G      = 7
KEY_BS          = 8        ; Backspace
KEY_CTRL_H      = KEY_BS
KEY_HTAB        = 9        ; Horizontal tab
KEY_CTRL_I      = KEY_HTAB
KEY_LF          = 10       ; Line Feed
KEY_CTRL_J      = KEY_LF
KEY_VTAB        = 11
KEY_CTRL_K      = KEY_VTAB
KEY_FF          = 12       ; Form Feed
KEY_CTRL_L      = KEY_FF
KEY_CR          = 13       ; Carriage return
KEY_CTRL_M      = KEY_CR
KEY_SO          = 14       ; Shift Out
KEY_CTRL_N      = KEY_SO
KEY_DOWN        = KEY_SO
KEY_SI          = 15       ; Shift In
KEY_CtRL_O      = KEY_SI   ; Educated guess, does not work in my terminal emulator
KEY_DLE         = 16       ; Data Link Escape
KEY_CTRL_P      = KEY_DLE
EY_UP           = KEY_DLE
KEY_CTRL_Q      = 17
KEY_CTRL_R      = 18
KEY_CTRL_S      = 19
KEY_CTRL_T      = 20
KEY_NAK         = 21       ; Negative AcKnowledgement
KEY_CTRL_U      = KEY_NAK
KEY_SI          = 22       ; Synchronous idle
KEY_CTRL_V      = KEY_SI
KEY_CTRL_W      = 23
KEY_CTRL_X      = 24
KEY_CTRL_Y      = 25
KEY_CTRL_Z      = 26
KEY_ESC         = 27       ; Escape
