.feature string_escapes

.segment "ZEROPAGE"

    {{ var("previous_was_cr") }}: .res 1

.segment "KERNALROM"

    CtRL_A          = 1         ; SOH - Start Of Heading
    CTRL_D          = 4         ; EOT - End Of Transmission
    BACKSPACE       = 8
    TAB             = 9
    CTRL_U          = 21        ; NAK - Negative Acknowledge
    CURSOR_UP       = 65
    CURSOR_DOWN     = 66
    CURSOR_RIGHT    = 67
    CURSOR_LEFT     = 68
    DELETE          = 127

    ; =====================================================================
    ; Clear the screen.
    ;
    ; Out:
    ;   A = clobbered on no input, or character byte when input was read
    ;   C = clear on no input, set when input was read

    .proc {{ api_def("clr") }}
        jsr {{ output_device.api("clr") }}
    .endproc

    ; =====================================================================
    ; Process character input.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("read") }}
        jsr {{ input_device.api("read") }}
        bcs @got_input
        ; Return clobbered A + clear carry is set to flag no input.
        rts
    @got_input:
        ; NOTE: FALLTHROUGH TO `write` FROM HERE.
    .endproc

    .proc {{ api_def("write") }}
        pha

        ; Handle CR/N, by normalizing \r, \n and \r\n to a newline call to the terminal.
        cmp #'\r'
        beq @cr
        cmp #'\n'
        beq @lf

        ; Handle DEL (delete) / BS (backspace)
        cmp #DELETE            ; DEL? (backspace on many terminals)
        beq @delete
        cmp #BACKSPACE         ; BS?
        beq @delete

        ; Echo the input to the TTY output.
        jsr {{ output_device.api("write") }}

    @return:
        ; Return read character + set carry to flag input.
        sec
        pla
        rts

    @delete:
        jsr {{ output_device.api("delete") }}
        jmp @return

    @cr:
        jsr {{ output_device.api("newline") }}
        ldx #1
        stx {{ var("previous_was_cr") }}
        jmp @return

    @lf:
        ldx {{ var("previous_was_cr") }}
        beq @lone_lf
        ldx #0
        stx {{ var("previous_was_cr") }}
        jmp @return

    @lone_lf:
        jsr {{ output_device.api("newline") }}
        jmp @return
    .endproc
