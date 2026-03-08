.feature string_escapes

.include "CORE/coding_macros.inc"
.include "stdlib/math/fmtdec.inc"

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
    ;   A = clobbered

    .proc {{ api_def("move_cursor") }}
        lda #$1b
        jsr {{ provider_device.api("write") }}
        lda #'['
        jsr {{ provider_device.api("write") }}

        lda #'H'
        jsr {{ provider_device.api("write") }}
        rts
    .endproc
;
;    ; =====================================================================
;    ; Write a character to the display at the current cursor position.
;    ;
;    ; Special handling is implemented for carriage return (\r) and line
;    ; feed (\n) characters. These are normalized and presented as a newline
;    ; on the display. When combined like "\r\n", only a single newline is
;    ; presented on the display.
;    ;
;    ; Only printable characters are printed.
;    ;
;    ; In:
;    ;   A = the character to write
;    ;   cursor_column = the current cursor position in the active row
;    ;   row_ptr = the start of the current row in the frame buffer
;    ; Out:
;    ;   A, X, Y = clobbered
;
;    .proc {{ api_def("write") }}
;        ; Jump forward when handling CR or LF character.
;        cmp #'\r'
;        beq @cr
;        cmp #'\n'
;        beq @lf
;
;        ; Handle a standard character.
;    @char:
;        ldx #0
;        stx {{ var("previous_was_cr") }}
;
;        ; Write the character to the currently active row in the frame buffer.
;        ldy {{ var("cursor_column") }}
;        sta ({{ var("row_ptr") }}),y
;
;        ; Write the character to the display at the current cursor position.
;        jsr {{ provider_device.api("write") }}  ; Write character to the display.
;
;        ; Move the cursor right when not at the end of the row.
;        bne @move_cursor_right
;
;        ; The cursor was at the end of the row. Wrap to the next row.
;        jsr {{ api("newline") }}
;        rts
;
;    @move_cursor_down:
;        ldx {{ var("cursor_row") }}
;        inx       ; Next row
;        ldy #0    ; Column 0
;        jsr {{ api("move_cursor") }}
;        rts
;
;    @move_cursor_right:
;        inc {{ var("cursor_column") }}
;        rts
;
;    @cr:
;        jsr {{ api("newline") }}
;        ldx #1
;        stx {{ var("previous_was_cr") }}
;        rts
;
;    @lf:
;        ldx {{ var("previous_was_cr") }}
;        beq @lone_lf
;        ldx #0
;        stx {{ var("previous_was_cr") }}
;        rts
;
;    @lone_lf:
;        jsr {{ api("newline") }}
;        rts
;
;    .endproc
;
;    ; =====================================================================
;    ; Move the cursor to the new line.
;    ;
;    ; Out:
;    ;   X, Y: clobbered
;
;    .proc {{ api_def("newline") }}
;
;        rts
;
;    @move_cursor_down:
;        inx       ; Next row
;        ldy #0    ; Column 0
;        jsr {{ api("move_cursor") }}
;        rts
;
;    .endproc
;
;    ; =====================================================================
;    ; Set the row_ptr to the start of the provided row index.
;    ;
;    ; In:
;    ;   X = the row to look up
;    ; Out:
;    ;   row_ptr = pointing to the start of the row in the frame buffer
;    ;   A, Y = clobbered
;
;    .proc {{ my("select_frame_buffer_row") }}
;        lda {{ var("row_map") }},x
;        tay
;        lda {{ var("row_table_lo") }},y
;        sta {{ var("row_ptr") }}
;        lda {{ var("row_table_hi") }},y
;        sta {{ var("row_ptr") }} + 1
;        rts
;    .endproc
;
