.include "CORE/coding_macros.inc"

.constructor {{ my("init") }}

.segment "KERNALRAM"

    {{ var("framebuffer") }}:   .res {{ width * height }}
    {{ var("row_map") }}:       .res {{ height }}   ; logical row -> framebuffer row
    {{ var("cursor_column") }}: .res 1
    {{ var("cursor_row") }}:    .res 1

.segment "KERNALROM"

    {{ var("row_table_lo") }}:
        {% for y in range(height) %}
        .byte .lobyte({{ var("framebuffer") }} + {{ y * width }})
        {% endfor %}

    {{ var("row_table_hi") }}:
        {% for y in range(height) %}
        .byte .hibyte({{ var("framebuffer") }} + {{ y * width }})
        {% endfor %}

.segment "ZEROPAGE"

    {{ var("row_ptr") }}: .res 2  ; The 16-bit address of current Y

.segment "KERNALROM"

    ; =====================================================================
    ; Initialize the console.
    ;
    ; Out:
    ;   A, X = clobbered

    .proc {{ my("init") }}
        jsr {{ api("home") }}
        jsr {{ my("clear_framebuffer") }}

        ; Initialize the logical -> framebuffer row mapping.
        ldx #0
    :   txa
        sta {{ var("row_map") }},x
        inx
        cpx #{{ height }}
        bne :-

        rts
    .endproc

    ; =====================================================================
    ; Clear the screen.

    .proc {{ api_def("clr") }}
        jsr {{ my("clear_framebuffer") }}
        jsr {{ provider_device.api("clr") }}
        rts
    .endproc

    ; =====================================================================
    ; Move the cursor to the home position.

    .proc {{ api_def("home") }}
        ldx #0
        stx {{ var("cursor_column") }}
        stx {{ var("cursor_row") }}
        SET_POINTER {{ var("row_ptr") }}, {{ var("framebuffer") }}
        rts
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
        ; Move the cursor on the physical display.
        jsr {{ provider_device.api("move_cursor") }}

        ; Map the logical row to the framebuffer row.
        lda {{ var("row_map") }},x
        tax

        ; Move the row_ptr to the start of the requested row.
        lda {{ var("row_table_lo") }},X
        sta {{ var("row_ptr") }}
        lda {{ var("row_table_hi") }},X
        sta {{ var("row_ptr") }}+1

        ; Store the new coordinates.
        stx {{ var("cursor_row") }}
        sty {{ var("cursor_column") }}

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
    ; In:
    ;   A = the character to write
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write") }}
        ; Write the character to the current cursor position.
        ldy {{ var("cursor_column") }}          ; Store character in frame buffer.
        sta ({{ var("row_ptr") }}),y
        jsr {{ provider_device.api("write") }}  ; Write character to the display.

        ; Move the cursor right when not at the end of the row.
        cpy #{{ width - 1 }}
        bcc @move_cursor_right

        ; The cursor was at the end of the row. Wrap to the next row.
        ldx {{ var("cursor_row") }}
        cpx #{{ height - 1 }}
        bcc @move_cursor_down

        ; Already on the last row, scrolling the screen up.
        jsr {{ my("scroll_rows") }}             ; Scroll the rows within the frame buffer.
        ldx #{{ height - 1 }}
        jsr {{ my("clear_row") }}               ; Clear the last row in the frame buffer.
        ldx #{{ height - 1 }}
        jsr {{ my("refresh") }}                 ; Redraw the display from the frame buffer.

        ; Move cursor to the start of the last row.
        ldy #0
        ldx #{{ height - 1 }}
        jsr {{ api("move_cursor") }}

        lda $6001
        eor #$FF
        sta $6001

        rts

    @move_cursor_down:
        inx       ; Next row
        ldy #0    ; Column 0
        jsr {{ api("move_cursor") }}
        rts

    @move_cursor_right:
        inc {{ var("cursor_column") }}
        rts
    .endproc

    ; =====================================================================
    ; Clear the framebuffer, by filling it with spaces.
    ;
    ; Out:
    ;   A, X = clobbered

    .proc {{ my("clear_framebuffer") }}
        lda #' '
        ldx #{{ width * height - 1 }}
    :   sta {{ var("framebuffer") }},X
        dex
        bpl :-
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
        lda {{ var("row_map") }},X
        tax
        lda {{ var("row_table_lo") }},X
        sta {{ var("row_ptr") }}
        lda {{ var("row_table_hi") }},X
        sta {{ var("row_ptr") }} + 1

        lda #' '
        ldy #{{ width - 1}}
    :   sta ({{ var("row_ptr") }}),Y
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
        ldx #0                         ; Row index
    @row_loop:
        ; Map the logical row to the framebuffer row.
        lda {{ var("row_map") }},x
        tay

        ; Move the row_ptr to the start of the logical row.
        lda {{ var("row_table_lo") }},Y
        sta {{ var("row_ptr") }}
        lda {{ var("row_table_hi") }},Y
        sta {{ var("row_ptr") }}+1

        ; Move LCD cursor to start of this logical row.
        ldy #0
        jsr {{ provider_device.api("move_cursor") }}

        ; Write row characters.
        ldy #0
    :   lda ({{ var("row_ptr") }}),Y
        jsr {{ provider_device.api("write") }}
        iny
        cpy #{{ width }}
        bne :-

        ; Move to next logical row.
        inx
        cpx #{{ height }}
        bne @row_loop

        rts
    .endproc
