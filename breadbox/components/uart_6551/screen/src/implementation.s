.feature string_escapes

.include "CORE/coding_macros.inc"
.include "stdlib/math/fmtdec.inc"
.include "stdlib/io/print.inc"

.macro SEND _character
    ; Send the provided character.
    lda #_character
    jsr {{ provider_device.api("write") }}
.endmacro

.macro ESCAPE
    ; Send the preamble of an ANSI escape sequence.
    SEND $1b  ; escape key
    SEND '['
.endmacro

.segment "KERNALROM"

    ; =====================================================================
    ; Clear the screen.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("clr") }}
        ESCAPE
        SEND '2'
        SEND 'J'
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor to the home position.

    .proc {{ api_def("home") }}
        ESCAPE
        SEND 'H'
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor position.
    ;
    ; In:
    ;   X = the row to move to
    ;   Y = the column to move to
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ api_def("move_cursor") }}
        tya
        pha

        ; Format the row number (1-indexed).
        inx
        stx fmtdec::value
        jsr fmtdec

        ; Send escape code up to the column number.
        ESCAPE
        PRINT_PTR {{ provider_device.api("write") }}, fmtdec::decimal
        SEND ';'

        ; Format the column number (1-indexed).
        pla
        tay
        iny
        sty fmtdec::value
        jsr fmtdec

        ; Finish the escape code with the column number.
        PRINT_PTR {{ provider_device.api("write") }}, fmtdec::decimal
        SEND 'H'

        rts
    .endproc

    ; =====================================================================
    ; Move to a new line.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("newline") }}
        SEND '\r'
        SEND '\n'
        rts
    .endproc

    ; =====================================================================
    ; Delete character before cursor position.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("backspace") }}
        ESCAPE      ; Move cursor left.
        SEND 'D'
        SEND ' '    ; Delete character by typing a space over it.
        ESCAPE      ; Move cursor left.
        SEND 'D'
        rts
    .endproc

    ; =====================================================================
    ; Write a character to the display at the current cursor position.
    ;
    ; Out:
    ;   A = clobbered

    {{ api_def("write") }} = {{ provider_device.api("write") }}
