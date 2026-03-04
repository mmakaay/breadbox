.include "breadbox.inc"

.export main

message: .asciiz "Hello, world!"

main:
    ldx #0             ; Set byte position to read from.
@loop:
    lda message,x      ; Read next byte from message.
    beq @done          ; Stop at terminating null-byte.
    jsr LCD::write     ; Write the byte to the display.
    inx                ; Move to the next byte position
    jmp @loop          ; And repeat
@done:
    HALT               ; Halt the computer
