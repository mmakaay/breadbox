.include "breadbox.inc"

.export main

greeting_message: .asciiz "Hello, world!"

.proc main
    PRINT SCHERMPJE, greeting_message

@loop:
    jsr UART::check_rx
    lda UART::byte
    beq @loop

    jsr UART::read

    jsr SCHERMPJE::clr
    lda UART::byte
    sta SCHERMPJE::byte
    jsr SCHERMPJE::write

    jsr UART::write_terminal

    jmp @loop
.endproc

