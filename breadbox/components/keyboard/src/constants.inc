; ----------------------------------------------------------------
; Codes for expressing key presses.
;
; All keyboard implementations must use these codes when
; interpreting key presses.
;
; Codes 0 - 127 follow the ASCII standard
;     0 -  31 : control keys, with their own KEY_* constants
;    32 - 126 : printable ASCII, no constant defined for these,
;               we use the literal values like `#"A"`.
;   127       : delete key, defined with KEY_DEL
; Codes 128 - 255 are custom codes
;   128 - 255 : all keys have a KEY_* constant
; ----------------------------------------------------------------

; Control codes from the ASCII definition.
; These relate to a "CTRL + <key>" combination.
KEY_NUL         = 0        ; Null                     - CTRL + @
KEY_SOH         = 1        ; Start Of Heading         - CTRL + A
KEY_STX         = 2        ; Start Of Text            - CTRL + B
KEY_ETX         = 3        ; End Of Text              - CTRL + C
KEY_EOT         = 4        ; End Of Transmission      - CTRL + D
KEY_ENQ         = 5        ; Enquiry                  - CTRL + E
KEY_ACK         = 6        ; Acknowledge              - CTRL + F
KEY_BEL         = 7        ; Bell                     - CTRL + G
KEY_BS          = 8        ; Backspace                - CTRL + H
KEY_HT          = 9        ; Horizontal tab           - CTRL + I
KEY_LF          = 10       ; Line Feed                - CTRL + J
KEY_VT          = 11       ; Vertical tab             - CTRL + K
KEY_FF          = 12       ; Form Feed                - CTRL + L
KEY_CR          = 13       ; Carriage return          - CTRL + M
KEY_SO          = 14       ; Shift Out                - CTRL + N
KEY_SI          = 15       ; Shift In                 - CTRL + O
KEY_DLE         = 16       ; Data Link Escape         - CTRL + P
KEY_DC1         = 17       ; Device Control 1         - CTRL + Q
KEY_DC2         = 18       ; Device Control 2         - CTRL + R
KEY_DC3         = 19       ; Device Control 3         - CTRL + S
KEY_DC4         = 20       ; Device Control 4         - CTRL + T
KEY_NAK         = 21       ; Negative AcKnowledgement - CTRL + U
KEY_SYN         = 22       ; Synchronous idle         - CTRL + V
KEY_ETB         = 23       ; End of xmit block        - CTRL + W
KEY_CAN         = 24       ; Cancel                   - CTRL + X
KEY_EM          = 25       ; End of Medium            - CTRL + Y
KEY_SUB         = 26       ; Substitute               - CTRL + Z
KEY_ESC         = 27       ; Escape                   - CTRL + [
KEY_FS          = 28       ; File Separator           - CTRL + \
KEY_GS          = 29       ; Group Separator          - CTRL + ]
KEY_RS          = 30       ; Record Separator         - CTRL + ^
KEY_US          = 31       ; Unit Separator           - CTRL + _


; The remaining ASCII codes from 32 up, except for delete, can be
; written as literal references in code.
KEY_DEL         = 127      ; Delete

; Custom control codes, outside the ASCII range (>= 128).
KEY_UP          = 128
KEY_DOWN        = 129
KEY_RIGHT       = 130
KEY_LEFT        = 131
KEY_HOME        = 132
KEY_END         = 133
KEY_DELETE      = 134      ; Forward-delete (the "delete" key on most keyboards;
                           ; on macOS this is fn+backspace). Distinct from
                           ; KEY_DEL ($7F) which is the legacy backspace code.
