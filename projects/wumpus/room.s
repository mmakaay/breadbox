; ---------------------------------------------------------------------------
; room.s — Per-turn room display, hazard warnings, and hardware status.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"
.include "game.inc"

; ---------------------------------------------------------------------------
; Strings local to this module.

.segment "DATA"

msg_separator:     .asciiz "\n------------------------\n"
msg_youre_in:      .asciiz "You are in cave "
msg_tunnels:       .asciiz "Tunnels lead to "
msg_comma:         .asciiz ", "
msg_dot_nl:        .asciiz ".\n"
msg_and:           .asciiz "and "
msg_smell_wumpus:  .asciiz "* I smell a Wumpus.\n"
msg_feel_draft:    .asciiz "* I feel a draft.\n"
msg_hear_bats:     .asciiz "* Bats nearby.\n"
msg_lcd_dead:      .asciiz "*** GAME OVER ***"
msg_lcd_win:       .asciiz "  YOU WIN! :-) "
msg_lcd_welcome1:  .asciiz "Hunt the Wumpus "
msg_lcd_welcome2:  .asciiz "Enter to start  "

; ---------------------------------------------------------------------------
; Room display — separator, warnings, cave number, tunnel list.

.segment "CODE"

    .proc show_room
        ; Visual break between turns so warnings, ricochet messages, and
        ; bat-teleport notices don't blur into one stream.
        PRINT TTY::write, msg_separator

        jsr maybe_warn_wumpus
        jsr maybe_warn_pit
        jsr maybe_warn_bats

        ; "You are in cave NN."
        PRINT TTY::write, msg_youre_in
        lda player_cave
        clc
        adc #1
        jsr print_dec_a
        PRINT TTY::write, msg_dot_nl

        ; "Tunnels lead to A, B, and C."
        PRINT TTY::write, msg_tunnels
        ldy #0
        jsr print_neighbour_of_player
        PRINT TTY::write, msg_comma
        ldy #1
        jsr print_neighbour_of_player
        PRINT TTY::write, msg_comma
        PRINT TTY::write, msg_and
        ldy #2
        jsr print_neighbour_of_player
        PRINT TTY::write, msg_dot_nl
        rts
    .endproc

    ; Print the (1-indexed) Y'th neighbour of the player's current cave.
    .proc print_neighbour_of_player
        ldx player_cave
        jsr lookup_neighbour
        clc
        adc #1
        jmp print_dec_a
    .endproc

; ---------------------------------------------------------------------------
; Hazard warnings — check each hazard class against player's neighbours.

    .proc maybe_warn_wumpus
        lda wumpus_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcc @done
        PRINT TTY::write, msg_smell_wumpus
    @done:
        rts
    .endproc

    .proc maybe_warn_pit
        lda pit1_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcs @yes
        lda pit2_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcc @done
    @yes:
        PRINT TTY::write, msg_feel_draft
    @done:
        rts
    .endproc

    .proc maybe_warn_bats
        lda bat1_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcs @yes
        lda bat2_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcc @done
    @yes:
        PRINT TTY::write, msg_hear_bats
    @done:
        rts
    .endproc

; ---------------------------------------------------------------------------
; LCD status display.

    .proc lcd_show_cave_and_arrows
        jsr LCD::clr

        ; Row 0: "Cave NN"
        ldx #0
        ldy #0
        jsr LCD::move_cursor
        lda #'C'
        jsr LCD::write
        lda #'a'
        jsr LCD::write
        lda #'v'
        jsr LCD::write
        lda #'e'
        jsr LCD::write
        lda #' '
        jsr LCD::write
        lda player_cave
        clc
        adc #1
        sta fmtdec::value
        jsr fmtdec
        PRINT_PTR LCD::write, fmtdec::decimal

        ; Row 1: "Arrows N"
        ldx #1
        ldy #0
        jsr LCD::move_cursor
        lda #'A'
        jsr LCD::write
        lda #'r'
        jsr LCD::write
        lda #'r'
        jsr LCD::write
        lda #'o'
        jsr LCD::write
        lda #'w'
        jsr LCD::write
        lda #'s'
        jsr LCD::write
        lda #' '
        jsr LCD::write
        lda arrows
        sta fmtdec::value
        jsr fmtdec
        PRINT_PTR LCD::write, fmtdec::decimal
        rts
    .endproc

    .proc lcd_show_welcome
        jsr LCD::clr
        ldx #0
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, msg_lcd_welcome1
        ldx #1
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, msg_lcd_welcome2
        rts
    .endproc

    .proc lcd_show_dead
        jsr LCD::clr
        ldx #0
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, msg_lcd_dead
        rts
    .endproc

    .proc lcd_show_win
        jsr LCD::clr
        ldx #0
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, msg_lcd_win
        rts
    .endproc

; ---------------------------------------------------------------------------
; LED status — on when the Wumpus is in an adjacent cave.

    .proc update_led
        lda wumpus_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcs @on
        jmp LED::turn_off
    @on:
        jmp LED::turn_on
    .endproc
