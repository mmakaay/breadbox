; ---------------------------------------------------------------------------
; map.s — Dodecahedron neighbour table and cave-map display.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "game.inc"

; ---------------------------------------------------------------------------
; Zero-page map state.

.segment "ZEROPAGE"

lookup_tmp: .res 1  ; scratch *inside* lookup_neighbour only
map_ptr:    .res 2  ; 16-bit string pointer for print_map
map_buf:    .res 1  ; one-byte look-behind buffer for print_map

; ---------------------------------------------------------------------------
; Dodecahedron neighbour table.
;
; Each row holds the three 0-indexed caves connected to cave i.
; Displayed to the player as 1-indexed (1..20).

.segment "DATA"

map:
    ;       neighbour 0, 1, 2 (0-indexed)
    .byte    1,  4,  7   ; Cave 1  (index 0)
    .byte    0,  2,  9   ; Cave 2  (index 1)
    .byte    1,  3, 11   ; Cave 3  (index 2)
    .byte    2,  4, 13   ; Cave 4  (index 3)
    .byte    0,  3,  5   ; Cave 5  (index 4)
    .byte    4,  6, 14   ; Cave 6  (index 5)
    .byte    5,  7, 16   ; Cave 7  (index 6)
    .byte    0,  6,  8   ; Cave 8  (index 7)
    .byte    7,  9, 17   ; Cave 9  (index 8)
    .byte    1,  8, 10   ; Cave 10 (index 9)
    .byte    9, 11, 18   ; Cave 11 (index 10)
    .byte    2, 10, 12   ; Cave 12 (index 11)
    .byte   11, 13, 19   ; Cave 13 (index 12)
    .byte    3, 12, 14   ; Cave 14 (index 13)
    .byte    5, 13, 15   ; Cave 15 (index 14)
    .byte   14, 16, 19   ; Cave 16 (index 15)
    .byte    6, 15, 17   ; Cave 17 (index 16)
    .byte    8, 16, 18   ; Cave 18 (index 17)
    .byte   10, 17, 19   ; Cave 19 (index 18)
    .byte   12, 15, 18   ; Cave 20 (index 19)

; Schlegel-projection diagram of the dodecahedron.
;
; Cave numbers are encoded as CAVE+N ($81..$94) so they can be
; distinguished from literal ASCII at print time. print_map walks the
; string byte by byte: bytes < $81 are sent to the TTY as-is; bytes
; $81..$94 are printed as their 1-indexed cave number, wrapped in
; parentheses when that cave is the player's current location.
;
; Trailing spaces on the cave-2 and cave-3 lines give the right-flank
; absorber a character to consume without eating the newline.

msg_map:
    .byte "\n"
    .byte "       .-------", CAVE+ 1, "------.\n"
    .byte "      /        |       \\\n"
    .byte "     /    ", CAVE+ 7, "----", CAVE+ 8, "---", CAVE+ 9, "    \\\n"
    .byte "    /    / \\      / \\    \\\n"
    .byte "   ", CAVE+ 5, "----", CAVE+ 6, "  ", CAVE+17, "----", CAVE+18, "  ", CAVE+10, "---", CAVE+ 2, " \n"
    .byte "   |    |   |    |   |    |\n"
    .byte "   |   ", CAVE+15, "--", CAVE+16, "    ", CAVE+19, "--", CAVE+11, "   |\n"
    .byte "   |    |    \\  /    /    |\n"
    .byte "   |     \\    ", CAVE+20, "    /     |\n"
    .byte "    \\    ", CAVE+14, "    |   ", CAVE+12, "    /\n"
    .byte "     \\   / `--", CAVE+13, "--' \\   /\n"
    .byte "      \\ /            \\ /\n"
    .byte "       ", CAVE+ 4, "--------------", CAVE+ 3, " \n"
    .byte "\n", 0

; ---------------------------------------------------------------------------
; Lookup which cave is in slot Y of cave X's neighbour list.
;
; In:
;   X = cave index (0..19)
;   Y = neighbour slot (0..2)
; Out:
;   A = neighbour cave index
;   X, Y = clobbered
;
; Address = map + X*3 + Y. Computes X*3 = X<<1 + X.
; Uses lookup_tmp as scratch (never touches caller-visible state).

.segment "CODE"

    .proc lookup_neighbour
        stx lookup_tmp
        txa
        asl
        clc
        adc lookup_tmp              ; X*2 + X = X*3
        clc
        sta lookup_tmp
        tya
        adc lookup_tmp              ; X*3 + Y
        tax
        lda map,x
        rts
    .endproc

; ---------------------------------------------------------------------------
; Advance the map string pointer by one byte.

    .proc advance_map_ptr
        inc map_ptr
        bne :+
        inc map_ptr + 1
    :   rts
    .endproc

; ---------------------------------------------------------------------------
; Print the cave map, wrapping the player's cave in parentheses while
; preserving the diagram's line widths.
;
; Uses a one-byte look-behind buffer (map_buf): when a cave byte is
; encountered, the previously read char (still unprinted in map_buf) is
; the LEFT FLANK — it gets replaced by '(' for the active cave, or
; emitted normally for any other cave. Then one more byte is consumed
; as the RIGHT FLANK (replaced by ')'). Width is unchanged:
;
;   inactive  `--13--`  →  emit `-`, emit `13`, next `-` processed normally
;   active    `--13--`  →  emit `(`, emit `13`, emit `)`, skip one `-`

    .proc print_map
        lda #<msg_map
        sta map_ptr
        lda #>msg_map
        sta map_ptr + 1
        lda #0
        sta map_buf

    @loop:
        ldy #0
        lda (map_ptr),y
        beq @flush_done

        cmp #CAVE + 1
        bcc @regular
        cmp #CAVE + 21
        bcs @regular

        ; ---------- cave byte CAVE+N ----------
        sta lookup_tmp              ; save encoded byte

        sec
        sbc #CAVE + 1               ; A = N - 1 (0-indexed)
        cmp player_cave
        bne @cave_inactive

        ; Active cave: discard left-flank buffer, emit ( N ).
        lda #'('
        jsr TTY::write
        lda lookup_tmp
        sec
        sbc #CAVE                   ; A = N (1-indexed)
        jsr print_dec_a
        lda #')'
        jsr TTY::write
        jsr advance_map_ptr         ; skip past the cave byte
        ; Consume one more byte as the right flank (null terminator check
        ; only — every non-null byte following a cave is a valid flank).
        ldy #0
        lda (map_ptr),y
        beq @cave_done
        jsr advance_map_ptr
    @cave_done:
        lda #0
        sta map_buf
        jmp @loop

    @cave_inactive:
        ; Emit buffered left flank normally, then emit the cave number.
        lda map_buf
        beq :+
        jsr TTY::write
    :   lda #0
        sta map_buf
        lda lookup_tmp
        sec
        sbc #CAVE                   ; A = N (1-indexed)
        jsr print_dec_a
        jsr advance_map_ptr
        jmp @loop

    ; ---------- regular ASCII byte ----------
    @regular:
        ; Save current byte across write (TTY::write clobbers A).
        pha
        lda map_buf
        beq :+
        jsr TTY::write
    :   pla
        sta map_buf
        jsr advance_map_ptr
        jmp @loop

    @flush_done:
        ; Null terminator reached. map_buf holds the final newline — emit it.
        lda map_buf
        jsr TTY::write
        rts
    .endproc
