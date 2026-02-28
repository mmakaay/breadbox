.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

greeting_message: .asciiz "Hello, world!"

.proc main
    PRINT SCHERMPJE::write, greeting_message

@loop:
    jsr UART::check_rx       ; A = pending count
    beq @loop

    jsr UART::read            ; A = received byte
    pha                        ; save for later

    jsr SCHERMPJE::clr
    pla                        ; restore byte
    pha                        ; save again
    jsr SCHERMPJE::write      ; write takes A

    pla                        ; restore byte
    jsr UART::write_terminal  ; write_terminal takes A

    jmp @loop
.endproc

