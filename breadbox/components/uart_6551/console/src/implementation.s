.feature string_escapes

.include "CORE/coding_macros.inc"
.include "stdlib/math/fmtdec.inc"
.include "stdlib/io/print.inc"

.segment "KERNALRAM"

    {{ var("previous_was_cr") }}: .res 1

.segment "ZEROPAGE"

    {{ var("decimal_ptr") }}: .res 2

.segment "KERNALROM"

    ; =====================================================================
    ; Clear the screen.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("clr") }}
        lda #$1b
        jsr {{ provider_device.api("write") }}
        lda #'['
        jsr {{ provider_device.api("write") }}
        lda #'2'
        jsr {{ provider_device.api("write") }}
        lda #'J'
        jsr {{ provider_device.api("write") }}
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor to the home position.

    .proc {{ api_def("home") }}
        lda #$1b
        jsr {{ provider_device.api("write") }}
        lda #'['
        jsr {{ provider_device.api("write") }}
        lda #'H'
        jsr {{ provider_device.api("write") }}
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor position.
    ;
    ; With a serial console we don't really have a width and height for
    ; the screen. It's up to the caller to use sensible values.
    ;
    ; In:
    ;   X = the row to move to
    ;   Y = the column to move to
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ api_def("move_cursor") }}
        phy

        ; Format the row number (1-indexed).
        inx
        stx fmtdec::value
        jsr fmtdec

        ; Send escape code up to the column number.
        lda #$1b
        jsr {{ provider_device.api("write") }}
        lda #'['
        jsr {{ provider_device.api("write") }}
        PRINT_PTR {{ provider_device.api("write") }}, fmtdec::decimal
        lda #';'
        jsr {{ provider_device.api("write") }}

        ; Format the column number (1-indexed).
        ply
        iny
        sty fmtdec::value
        jsr fmtdec

        ; Finish the escape code with the column number.
        PRINT_PTR {{ provider_device.api("write") }}, fmtdec::decimal
        lda #'H'
        jsr {{ provider_device.api("write") }}

        rts
    .endproc

    ; =====================================================================
    ; Move to a new line.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("newline") }}
        lda #'\r'
        jsr {{ provider_device.api("write") }}
        lda #'\n'
        jsr {{ provider_device.api("write") }}

        rts
    .endproc

    ; =====================================================================
    ; Write a character to the display at the current cursor position.
    ;
    ; Special handling is implemented for carriage return (\r) and line
    ; feed (\n) characters. These are normalized and presented as a newline
    ; on the display. When combined like "\r\n", only a single newline is
    ; presented on the display.
    ;
    ; In:
    ;   A = the character to write
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ api_def("write") }}
        ; Jump forward when handling CR or LF character.
        cmp #'\r'
        beq @cr
        cmp #'\n'
        beq @lf

        ; Handle a standard character.
    @char:
        ldx #0
        stx {{ var("previous_was_cr") }}
        ; Write the character to the display at the current cursor positoinr.
        jsr {{ provider_device.api("write") }}
        rts

    @cr:
        jsr {{ api("newline") }}
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
        jsr {{ api("newline") }}
        rts

    .endproc
