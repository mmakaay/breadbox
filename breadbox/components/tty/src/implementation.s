.feature string_escapes

.include "CORE/coding_macros.inc"

.segment "ZEROPAGE"

    {{ var("previous_was_cr") }}: .res 1

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
    ; Process character input.
    ;
    ; Out:
    ;   A = character read, when carry is set, otherwise clobbered
    ;   C = set when character was read, clear otherwise
    ;   X, Y = preserved

    .proc {{ api_def("read") }}
        PUSH_X
        PUSH_Y
        jsr {{ keyboard_device.api("read") }}
        bcc @done

        ; Input received, send it to the output.
        PULL_Y
        PULL_X
        jmp {{ api_def("write") }}

    @done:
        ; Return with carry clear to indicate "no input".
        PULL_Y
        PULL_X
        rts
    .endproc

    ; =====================================================================
    ; Process character output.
    ;
    ; In:
    ;   A = the byte to write
    ; Out:
    ;   A = the byte that was written
    ;   X, Y = preserved

    .proc {{ api_def("write") }}
        PUSH_AXY

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
        jsr {{ screen_device.api("write") }}

    @return:
        ; Return read character + set carry to flag input.
        sec
        PULL_AXY
        rts

    @backspace:
        jsr {{ screen_device.api("backspace") }}
        jmp @return

    @cr:
        jsr {{ screen_device.api("newline") }}
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
        jsr {{ screen_device.api("newline") }}
        jmp @return
    .endproc
