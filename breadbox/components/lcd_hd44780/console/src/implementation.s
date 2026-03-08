.feature string_escapes

.include "CORE/coding_macros.inc"

.constructor {{ my("init") }}

.segment "KERNALRAM"

    ; The frame buffer is used to store the printed characters in a memory buffer,
    ; making this a shadow of the characters that are visible on the physical display.
    ; This buffer can be used to referesh the full display, exmaple when the text in
    ; the display display must be scrolled.
    {{ var("frame_buffer") }}:  .res {{ width * height }}

    ; To make scrolling a light-weight operation, a mapping is used between logical
    ; row numbers (as visible on the display), and rows numbers in the frame buffer.
    ; This map makes it possible to change the order of logical rows, without having
    ; to swap out data in the frame buffer. E.g. when the `row_map` starts out as
    ; [0, 1, 2, 3], the rows can be scrolled by updating the `row_map` to
    ; [1, 2, 3, 0] and then redrawing the display output.
    {{ var("row_map") }}:       .res {{ height }}

    ; Keeps track of the active cursor position.
    {{ var("cursor_column") }}: .res 1
    {{ var("cursor_row") }}:    .res 1

.segment "KERNALROM"

    ; These tables provide a mapping from a given row number (0-indexed)
    ; to the start of that row in the frame buffer. This is used as a quick
    ; lookup table, instead of having to compute the offsets on-the-fly.
    {{ var("row_table_lo") }}:
        {% for y in range(height) %}
        .byte .lobyte({{ var("frame_buffer") }} + {{ y * width }})
        {% endfor %}
    {{ var("row_table_hi") }}:
        {% for y in range(height) %}
        .byte .hibyte({{ var("frame_buffer") }} + {{ y * width }})
        {% endfor %}

.segment "ZEROPAGE"

    ; A pointer too the start of the currently selected row in the frame buffer.
    {{ var("row_ptr") }}:         .res 2

    ; A register for tracking "\r" state.
    {{ var("previous_was_cr") }}: .res 1

.segment "KERNALROM"

    ; =====================================================================
    ; Initialize the console.
    ;
    ; Out:
    ;   A, X = clobbered

    .proc {{ my("init") }}
        jsr {{ my("clear_frame_buffer") }}
        jsr {{ api("home") }}

        lda #0
        sta {{ var("previous_was_cr") }}

        ; Initialize the logical -> frame buffer row mapping:
        ;   row 0 -> framebuffer row 0
        ;   row 1 -> framebuffer row 1
        ;   ...
        ;   row n -> framebuffer row n
        ldx #0
    @loop:
        txa
        sta {{ var("row_map") }},x
        inx
        cpx #{{ height }}
        bne @loop

        rts
    .endproc

    ; =====================================================================
    ; Clear the screen.

    .proc {{ api_def("clr") }}
        jsr {{ my("clear_frame_buffer") }}
        jsr {{ provider_device.api("clr") }}
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor to the home position.

    .proc {{ api_def("home") }}
        ldx #0
        ldy #0
        jmp {{ api_def("move_cursor") }}
    .endproc

    ; =====================================================================
    ; Move the cursor position.
    ;
    ; In:
    ;   X = the row to move to
    ;   Y = the column to move to
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("move_cursor") }}
        ; Store logical coordinates.
        stx {{ var("cursor_row") }}
        sty {{ var("cursor_column") }}

        ; Move the cursor on the physical display.
        jsr {{ provider_device.api("move_cursor") }}

        ; Map the logical row to the framebuffer.
        jsr {{ my("select_frame_buffer_row") }}

        rts
    .endproc

    ; =====================================================================
    ; Retrieve the current cursor position.
    ;
    ; Out:
    ;   X = the cursor's row
    ;   Y = the cursor's column

    .proc {{ api_def("get_cursor") }}
        ldx {{ var("cursor_row") }}
        ldy {{ var("cursor_column") }}
        rts
    .endproc

    ; =====================================================================
    ; Write a character to the display at the current cursor position.
    ;
    ; Special handling is implemented for carriage return (\r) and line
    ; feed (\n) characters. These are normalized and presented as a newline
    ; on the display. When combined like "\r\n", only a single newline is
    ; presented on the display.
    ;;
    ; In:
    ;   A = the character to write
    ;   cursor_column = the current cursor position in the active row
    ;   row_ptr = the start of the current row in the frame buffer
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

        ; Write the character to the currently active row in the frame buffer.
        ldy {{ var("cursor_column") }}
        sta ({{ var("row_ptr") }}),y

        ; Write the character to the display at the current cursor position.
        jsr {{ provider_device.api("write") }}  ; Write character to the display.

        ; Move the cursor right when not at the end of the row.
        cpy #{{ width - 1 }}
        bne @move_cursor_right

        ; The cursor was at the end of the row. Wrap to the next row.
        jsr {{ api("newline") }}
        rts

    @move_cursor_right:
        inc {{ var("cursor_column") }}
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

    ; =====================================================================
    ; Move the cursor to the new line.
    ;
    ; Out:
    ;   X, Y: clobbered

    .proc {{ api_def("newline") }}
        ldx {{ var("cursor_row") }}             ; Get the current row.
        cpx #{{ height - 1 }}                   ; On the last row?
        bne @move_cursor_down                   ; No, the cursor can be moved down.

        ; Already on the last row, scrolling the screen up.
        jsr {{ my("scroll_rows") }}             ; Scroll the rows within the frame buffer.
        ldx #{{ height - 1 }}
        jsr {{ my("clear_row") }}               ; Clear the last row in the frame buffer.
        jsr {{ my("refresh") }}                 ; Redraw the display from the frame buffer.

        ; Move cursor to the start of the last row.
        ldx #{{ height - 1 }}
        ldy #0
        jsr {{ api("move_cursor") }}

        rts

    @move_cursor_down:
        inx       ; Next row
        ldy #0    ; Column 0
        jsr {{ api("move_cursor") }}
        rts

    .endproc

    ; =====================================================================
    ; Set the row_ptr to the start of the provided row index.
    ;
    ; In:
    ;   X = the row to look up
    ; Out:
    ;   row_ptr = pointing to the start of the row in the frame buffer
    ;   A, Y = clobbered

    .proc {{ my("select_frame_buffer_row") }}
        lda {{ var("row_map") }},x
        tay
        lda {{ var("row_table_lo") }},y
        sta {{ var("row_ptr") }}
        lda {{ var("row_table_hi") }},y
        sta {{ var("row_ptr") }} + 1
        rts
    .endproc

    ; =====================================================================
    ; Clear the framebuffer, by filling it with spaces.
    ;
    ; Out:
    ;   A, X = clobbered

    .proc {{ my("clear_frame_buffer") }}
        lda #'1'
        ldx #{{ width * height - 1 }}
    @loop:
        sta {{ var("frame_buffer") }},x
        dex
        bpl @loop
        rts
    .endproc

    ; =====================================================================
    ; Scroll the rows.
    ;
    ; We do not copy around actual memory for this. We just change the
    ; logical row ordering, so the logical rows will point to other
    ; rows in the framebuffer.
    ;
    ; 0,1,2,3 -> 1,2,3,0 -> 2,3,0,1 -> etc.
    ;
    ; Out:
    ;   A, X, Y = clobbered

    .proc {{ my("scroll_rows") }}
        lda {{ var("row_map") }}
        tay

        ldx #0
    @loop:
        lda {{ var("row_map") }}+1,x
        sta {{ var("row_map") }},x
        inx
        cpx #{{ height - 1 }}
        bcc @loop

        tya
        sta {{ var("row_map") }}+{{ height - 1 }}

        rts
    .endproc

    ; =====================================================================
    ; Clear row.
    ;
    ; In:
    ;   X = the row to clear
    ; Out:
    ;   row_ptr, A, X, Y = clobbered

    .proc {{ my("clear_row") }}
        jsr {{ my("select_frame_buffer_row") }}   ; Point at row X in the frame buffer.

        lda #' '                      ; Fill the row with spaces.
        ldy #{{ width - 1}}
    :   sta ({{ var("row_ptr") }}),y
        dey
        bpl :-

        rts
    .endproc

    ; =====================================================================
    ; Refresh screen, based on screen buffer.
    ;
    ; Out:
    ;   row_ptr, A, X, Y = clobbered

    .proc {{ my("refresh") }}
        ldx #0
    @row_loop:
        jsr {{ my("select_frame_buffer_row") }}

        ; Move LCD cursor to start of this logical row.
        ldy #0
        jsr {{ provider_device.api("move_cursor") }}

        ; Write row characters.
        ldy #0
    @column_loop:
        lda ({{ var("row_ptr") }}),y
        jsr {{ provider_device.api("write") }}
        iny
        cpy #{{ width }}
        bne @column_loop

        ; Move to next logical row.
        inx
        cpx #{{ height }}
        bne @row_loop

        rts
    .endproc
