.feature string_escapes

.include "CORE/coding_macros.inc"

.segment "ZEROPAGE"

    {{ var("previous_was_cr") }}: .res 1
    {{ var("options") }}: .res 1

.segment "KERNALROM"

    BACKSPACE       = 8
    DELETE          = 127

    ; =====================================================================
    ; Clear the screen.
    ;
    ; Out:
    ;   A, X, Y = consider clobbered (depends on driver implementation)

    {{ api_def("clr") }} = {{ screen_device.api("clr") }}

    ; =====================================================================
    ; Read from the keyboard.
    ;
    ; Out:
    ;   A = character read, when carry is set, otherwise clobbered
    ;   C = set when character was read, clear otherwise
    ;   X, Y = preserved

    .proc {{ api_def("read") }}
        txa
        pha
        tya
        pha

        jsr {{ keyboard_device.api("read") }}
        bcc @done                   ; Return with carry clear.
        jsr {{ api_def("write") }}  ; Echo received input to the screen.
        sec                         ; Set carry to indicate "got input".
    @done:
        pla
        tay
        pla
        tax
        rts
    .endproc

    ; =====================================================================
    ; Write to the screen.
    ;
    ; In:
    ;   A = the byte to write
    ; Out:
    ;   A = the byte that was written
    ;   X, Y = consider clobbered (depends on driver implementation)

    .proc {{ api_def("write") }}
        ; Handle CR/N, by normalizing \r, \n and \r\n to a newline call to the terminal.
        cmp #'\r'
        beq @cr
        cmp #'\n'
        beq @lf

        ; Handle DEL (delete) / BS (backspace)
        cmp #DELETE            ; DEL? (backspace on many terminals)
        beq @backspace
        cmp #BACKSPACE         ; BS?
        beq @backspace

        ; Echo the input to the TTY output.
        jmp {{ screen_device.api("write") }}

    @backspace:
        jmp {{ screen_device.api("backspace") }}

    @cr:
        jsr {{ screen_device.api("newline") }}
        ldx #1
        stx {{ var("previous_was_cr") }}
        rts

    @lf:
        ldx {{ var("previous_was_cr") }}
        beq @lone_lf
        ldx #0
        stx {{ var("previous_was_cr") }}
        rts

    @lone_lf:
        jmp {{ screen_device.api("newline") }}
    .endproc
