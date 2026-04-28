; ---------------------------------------------------------------------------
; wumpus.s — Main game loop for Hunt the Wumpus.
;
; This file is intentionally thin: it owns only the top-level game flow
; and the strings that belong to it. All game logic lives in the other
; modules (world.s, map.s, room.s, parser.s, actions.s, util.s).
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "game.inc"

.export wumpus_run

; ---------------------------------------------------------------------------
; Strings local to this module.

.segment "DATA"

msg_banner:
    .byte "\n"
    .byte "=============================================\n"
    .byte "        H U N T   T H E   W U M P U S\n"
    .byte "=============================================\n"
    .byte "\n"
    .byte "You are in a cave system shaped like a\n"
    .byte "dodecahedron. Each cave has three tunnels.\n"
    .byte "Hidden in the maze: 1 Wumpus, 2 pits, 2 bats.\n"
    .byte "\n"
    .byte "Type H or ? at the prompt for help.\n"
    .byte "\n"
    .byte 0

msg_prompt:      .asciiz "> "
msg_press_enter: .asciiz "Press Enter to start. "
msg_won:         .asciiz "\nYou win!\n"
msg_lost:        .asciiz "\nGame over.\n"

; ---------------------------------------------------------------------------
; Main game loop.

.segment "CODE"

    .proc wumpus_run
        ; Configure readline once — pointers and cap stay valid across all
        ; readline calls for the lifetime of the program.
        SET_POINTER TTY::prompt, msg_press_enter
        SET_POINTER TTY::line_buffer, line_buffer
        lda #LINE_MAX
        sta TTY::line_max

        ; Welcome screen on the LCD while we wait for the first keypress.
        jsr lcd_show_welcome
        PRINT TTY::write, msg_banner

        ; Block on "Press Enter to start" so the PRNG is seeded from the
        ; tick counter at a non-deterministic moment. Reading ticks after
        ; the user reacts gives tens of milliseconds of variability —
        ; enough for a casual-grade random seed.
    @wait_seed_line:
        jsr TTY::readline
        bcc @wait_seed_line

        lda TICKER::ticks
        ora #1                          ; LFSR forbids the all-zero state.
        sta prng__seed_lo
        lda TICKER::ticks + 1
        sta prng__seed_hi

        SET_POINTER TTY::prompt, msg_prompt

    @new_game:
        jsr setup_world
        jsr lcd_show_cave_and_arrows
        jsr update_led
        jsr show_room

    @turn_loop:
    @wait_line:
        jsr TTY::readline
        bcc @wait_line
        sta parse_len

        lda parse_len
        beq @turn_loop                  ; empty line → re-prompt only.

        jsr handle_line
        lda game_over
        beq @after_action

        ; Game ended this turn.
        cmp #GAME_WON
        bne @lost
        PRINT TTY::write, msg_won
        jsr lcd_show_win
        jmp @next_round
    @lost:
        PRINT TTY::write, msg_lost
        jsr lcd_show_dead

    @next_round:
        ; LED off between rounds so it doesn't mislead on the next game.
        jsr LED::turn_off
        SET_POINTER TTY::prompt, msg_press_enter
    @wait_next:
        jsr TTY::readline
        bcc @wait_next
        lda TICKER::ticks
        ora #1
        sta prng__seed_lo
        lda TICKER::ticks + 1
        sta prng__seed_hi
        SET_POINTER TTY::prompt, msg_prompt
        jsr lcd_show_welcome
        jmp @new_game

    @after_action:
        jsr lcd_show_cave_and_arrows
        jsr update_led
        jsr show_room
        jmp @turn_loop
    .endproc
