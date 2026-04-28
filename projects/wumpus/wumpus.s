; ---------------------------------------------------------------------------
; Hunt the Wumpus — game logic.
;
; Faithful to Gregory Yob's 1973 original:
;
;   - 20 caves arranged as a dodecahedron (each cave has exactly 3 tunnels).
;   - 1 wumpus, 2 bottomless pits, 2 super bats. All start in distinct caves
;     that are also distinct from the player's start.
;   - Each turn:
;       * Show the player's current cave + its three tunnels.
;       * Sniff for hazards in adjacent caves (wumpus, pit, bat).
;       * Prompt for action: M(ove) <cave> | S(hoot) <cave>...<cave>
;                            Q(uit) | H(elp).
;   - Move:
;       * Walk into the wumpus's cave   → wumpus eats you (lose).
;       * Walk into a pit               → fall (lose).
;       * Walk into a bat               → teleport to a random cave (which
;                                         might itself be a hazard).
;   - Shoot (1..5 caves per arrow, 5 arrows total):
;       * If a path step doesn't connect, the arrow ricochets to a random
;         tunnel of the current cave.
;       * Hits wumpus  → win.
;       * Hits player  → lose ("you shot yourself").
;       * Misses       → wumpus has 75% chance to wake and shuffle to one of
;                        its three neighbours; if it shuffles into the
;                        player's cave, you're eaten.
;     Out of arrows → lose.
;
; The game runs over the SERIAL TTY using readline for input. The LCD is
; updated each turn with a small status display ("Cave NN  Arrows N").
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec.inc"

.importzp prng__seed_lo, prng__seed_hi
.import prng__step, prng__random_in_range

.export wumpus_run

LINE_MAX = 64

NUM_CAVES   = 20
INITIAL_ARROWS = 5
MAX_ARROW_PATH = 5

GAME_PLAYING = 0
GAME_WON     = 1
GAME_LOST    = 2

; ---------------------------------------------------------------------------
; Map: dodecahedron neighbour table.
;
; Cave numbering follows the canonical 1973 layout. Each row holds the
; three caves connected to cave i. The engine uses 0-indexed caves
; internally (0..19); the player sees 1-indexed numbers (1..20).

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

; ---------------------------------------------------------------------------
; Static strings.

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

msg_help:
    .byte "\n"
    .byte "Commands:\n"
    .byte "  M <cave>             Move to an adjacent cave.\n"
    .byte "  M                    Show the cave map.\n"
    .byte "  S <c1> [c2 ... c5]   Shoot a crooked arrow through up\n"
    .byte "                       to 5 caves; each must be reachable\n"
    .byte "                       from the previous, otherwise the\n"
    .byte "                       arrow ricochets randomly.\n"
    .byte "  H or ?               Show this help.\n"
    .byte "\n"
    .byte "Hazards:\n"
    .byte "  Wumpus: smell it from one cave away. If you walk into\n"
    .byte "          its cave (or it into yours), you're dinner.\n"
    .byte "  Pit:    feel a draft from one cave away. Walking in is\n"
    .byte "          fatal.\n"
    .byte "  Bats:   hear them from one cave away. Walking in gets\n"
    .byte "          you teleported somewhere random.\n"
    .byte "\n"
    .byte 0

; Schlegel-projection diagram of the dodecahedron, showing all 30 edges.
;
; Cave numbers are encoded as CAVE+N ($81..$94) so they can be
; distinguished from literal ASCII at print time. print_map walks the
; string byte by byte: bytes < $81 are sent to the TTY as-is; bytes
; $81..$94 are printed as their 1-indexed cave number, wrapped in
; parentheses if that cave is the player's current location.
;
; Using $81+ avoids any collision with printable ASCII ($20..$7E) and
; with the newline byte ($0A = 10), which also happens to be the value
; for cave 10 in a raw 1-indexed encoding.

CAVE = $80  ; base: CAVE+N encodes cave N (1-indexed, N=1..20)

msg_map:
    .byte "\n"
    .byte "       .-------", CAVE+1, "------.\n"
    .byte "      /        |       \\\n"
    .byte "     /    ", CAVE+7, "----", CAVE+8, "---", CAVE+9, "    \\\n"
    .byte "    /    / \\      / \\    \\\n"
    .byte "   ", CAVE+5, "----", CAVE+6, "  ", CAVE+17, "----", CAVE+18, "  ", CAVE+10, "---", CAVE+ 2, " \n"
    .byte "   |    |   |    |   |    |\n"
    .byte "   |   ", CAVE+15, "--", CAVE+16, "    ", CAVE+19, "--", CAVE+11, "   |\n"
    .byte "   |    |    \\  /    /    |\n"
    .byte "   |     \\    ", CAVE+20, "    /     |\n"
    .byte "    \\    ", CAVE+14, "    |   ", CAVE+12, "    /\n"
    .byte "     \\   / `--", CAVE+13, "--' \\   /\n"
    .byte "      \\ /            \\ /\n"
    .byte "       ", CAVE+4, "--------------", CAVE+3, " \n"
    .byte "\n", 0

msg_prompt:        .asciiz "> "
msg_press_enter:   .asciiz "Press Enter to start. "
msg_youre_in:      .asciiz "You are in cave "
msg_tunnels:       .asciiz "Tunnels lead to "
msg_smell_wumpus:  .asciiz "* I smell a Wumpus.\n"
msg_feel_draft:    .asciiz "* I feel a draft.\n"
msg_hear_bats:     .asciiz "* Bats nearby.\n"
msg_eaten:         .asciiz "\n** Tssht. The Wumpus eats you. **\n"
msg_pit:           .asciiz "\n** YYYAAAAaaaaaa... you fell in a pit. **\n"
msg_bat_grab:      .asciiz "\n** A super bat snatches you! Whoosh... **\n"
msg_bat_drop:      .asciiz "Dropped in cave "
msg_arrow_hit:     .asciiz "\n** You hit the Wumpus! Dinner is on you. **\n"
msg_self_shot:     .asciiz "\n** Ouch. You shot yourself. **\n"
msg_arrow_miss:    .asciiz "Missed.\n"
msg_arrow_ricochet:.asciiz "* The arrow ricochets!\n"
msg_wumpus_wakes:  .asciiz "* You hear lumbering. The Wumpus is on the move...\n"
msg_out_of_arrows: .asciiz "\n** Out of arrows. **\n"
msg_won:           .asciiz "\nYou win!\n"
msg_lost:          .asciiz "\nGame over.\n"
msg_huh:           .asciiz "I don't understand that. Type H for help.\n"
msg_not_adjacent:  .asciiz "That cave isn't connected to this one.\n"
msg_bad_cave:      .asciiz "That isn't a valid cave number.\n"
msg_too_long_path: .asciiz "An arrow can travel through at most 5 caves.\n"
msg_no_arrows:     .asciiz "You have no arrows left!\n"
msg_no_path:       .asciiz "Where would you shoot? Specify at least one cave.\n"
msg_comma:         .asciiz ", "
msg_dot_nl:        .asciiz ".\n"
msg_and:           .asciiz "and "
msg_separator:     .asciiz "\n------------------------\n"
msg_lcd_dead:      .asciiz "*** GAME OVER ***"
msg_lcd_win:       .asciiz "  YOU WIN! :-) "
msg_lcd_welcome1:  .asciiz "Hunt the Wumpus "
msg_lcd_welcome2:  .asciiz "Enter to start  "

; ---------------------------------------------------------------------------
; Game state.

.segment "RAM"

    player_cave: .res 1   ; 0..19
    wumpus_cave: .res 1
    pit1_cave:   .res 1
    pit2_cave:   .res 1
    bat1_cave:   .res 1
    bat2_cave:   .res 1
    arrows:      .res 1
    game_over:   .res 1

    line_buffer: .res LINE_MAX
    arrow_path:  .res MAX_ARROW_PATH

.segment "ZEROPAGE"

    parse_idx:   .res 1   ; cursor in line_buffer during parsing
    parse_len:   .res 1   ; length returned from readline
    arrow_count: .res 1   ; number of caves named in a shot
    arrow_idx:   .res 1   ; loop index while flying the arrow
    arrow_pos:   .res 1   ; cave the arrow is currently in (fly_arrow)
    arrow_next:  .res 1   ; next cave the arrow will travel to
    target_cave: .res 1   ; target of a move; also: cave being looked up
    probe_cave:  .res 1   ; "is this cave a neighbour of the player?"
    parse_acc:   .res 1   ; running accumulator in parse_cave_arg
    parse_dig:   .res 1   ; scratch in parse_cave_arg's *10 step
    lookup_tmp:  .res 1   ; scratch *inside* lookup_neighbour only.
    map_ptr:     .res 2   ; 16-bit pointer used by print_map.
    map_buf:     .res 1   ; one-byte look-behind buffer in print_map.

; ===========================================================================
; Public entry point.
; ===========================================================================

.segment "CODE"

    .proc wumpus_run
        ; Configure readline once.
        SET_POINTER TTY::prompt, msg_press_enter
        SET_POINTER TTY::line_buffer, line_buffer
        lda #LINE_MAX
        sta TTY::line_max

        ; Show a welcome on the LCD while we wait for the user. As soon
        ; as the game starts, lcd_show_cave_and_arrows will overwrite it with
        ; the live "Cave NN / Arrows N" status display.
        jsr lcd_show_welcome

        PRINT TTY::write, msg_banner

        ; Block on a "Press Enter" prompt so the PRNG can be seeded from
        ; the tick counter at a non-deterministic moment. Boot-to-here
        ; takes a fixed handful of microseconds, so reading ticks before
        ; any user interaction would always give the same value, and
        ; the world layout would be identical every game. Reading
        ; ticks AFTER the user has reacted gives us tens of milliseconds
        ; of variability — plenty for a casual-grade seed.
    @wait_seed_line:
        jsr TTY::readline
        bcc @wait_seed_line

        lda TICKER::ticks
        ora #1                          ; LFSR forbids the all-zero state.
        sta prng__seed_lo
        lda TICKER::ticks + 1
        sta prng__seed_hi

        ; Switch to the actual game prompt for the rest of the session.
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

        ; Game ended this turn. Show outcome, then loop back to the
        ; Press-Enter prompt for a fresh round with a new PRNG seed.
        cmp #GAME_WON
        bne @lost
        PRINT TTY::write, msg_won
        jsr lcd_show_win
        jmp @next_round
    @lost:
        PRINT TTY::write, msg_lost
        jsr lcd_show_dead
    @next_round:
        ; Turn the LED off while waiting between rounds so it doesn't
        ; mislead the player about Wumpus proximity in the new game.
        jsr LED::turn_off
        ; Re-use the same Press-Enter prompt + seed mechanism as at boot.
        ; The player takes a non-deterministic amount of time to read the
        ; outcome and press Enter, giving us fresh entropy every round.
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

; ===========================================================================
; World setup.
; ===========================================================================

    .proc setup_world
        lda #GAME_PLAYING
        sta game_over
        lda #INITIAL_ARROWS
        sta arrows

        lda #NUM_CAVES
        jsr prng__random_in_range
        sta player_cave

    @place_wumpus:
        lda #NUM_CAVES
        jsr prng__random_in_range
        cmp player_cave
        beq @place_wumpus
        sta wumpus_cave

    @place_pit1:
        lda #NUM_CAVES
        jsr prng__random_in_range
        cmp player_cave
        beq @place_pit1
        cmp wumpus_cave
        beq @place_pit1
        sta pit1_cave

    @place_pit2:
        lda #NUM_CAVES
        jsr prng__random_in_range
        cmp player_cave
        beq @place_pit2
        cmp wumpus_cave
        beq @place_pit2
        cmp pit1_cave
        beq @place_pit2
        sta pit2_cave

    @place_bat1:
        lda #NUM_CAVES
        jsr prng__random_in_range
        cmp player_cave
        beq @place_bat1
        cmp wumpus_cave
        beq @place_bat1
        cmp pit1_cave
        beq @place_bat1
        cmp pit2_cave
        beq @place_bat1
        sta bat1_cave

    @place_bat2:
        lda #NUM_CAVES
        jsr prng__random_in_range
        cmp player_cave
        beq @place_bat2
        cmp wumpus_cave
        beq @place_bat2
        cmp pit1_cave
        beq @place_bat2
        cmp pit2_cave
        beq @place_bat2
        cmp bat1_cave
        beq @place_bat2
        sta bat2_cave

        rts
    .endproc

; ===========================================================================
; Map lookup: which cave is in slot Y of cave X's neighbour list?
; ===========================================================================

    ; In:
    ;   X = cave index (0..19)
    ;   Y = neighbour slot (0..2)
    ; Out:
    ;   A = neighbour cave index
    ;   X, Y = clobbered
    ;
    ; Address = map + X*3 + Y. Computes X*3 = X<<1 + X.
    ;
    ; Uses lookup_tmp as scratch — the proc deliberately does NOT
    ; touch any of the higher-level state slots (arrow_pos, etc.) so
    ; callers can keep their state in those across multiple lookups.
    .proc lookup_neighbour
        stx lookup_tmp
        txa
        asl
        clc
        adc lookup_tmp                  ; X*2 + X = X*3
        clc
        sta lookup_tmp
        tya
        adc lookup_tmp                  ; X*3 + Y
        tax
        lda map,x
        rts
    .endproc

; ===========================================================================
; Display: current cave + tunnels + hazard warnings.
; ===========================================================================

    .proc show_room
        ; Visual break between turns so warnings, ricochet messages,
        ; and bat-teleport notices don't blur into one stream.
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
; Hazard warnings.
; ---------------------------------------------------------------------------

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

    ; Returns C=1 if probe_cave is one of the three neighbours of the
    ; player's cave. Otherwise C=0. Clobbers A, X, Y.
    .proc is_neighbour_of_player
        ldx player_cave
        ldy #0
        jsr lookup_neighbour
        cmp probe_cave
        beq @yes
        ldx player_cave
        ldy #1
        jsr lookup_neighbour
        cmp probe_cave
        beq @yes
        ldx player_cave
        ldy #2
        jsr lookup_neighbour
        cmp probe_cave
        beq @yes
        clc
        rts
    @yes:
        sec
        rts
    .endproc

; ---------------------------------------------------------------------------
; Line parsing & action dispatch.
; ---------------------------------------------------------------------------

    .proc handle_line
        lda #0
        sta parse_idx
        jsr skip_spaces

        ldx parse_idx
        cpx parse_len
        bcc :+
        jmp @huh                        ; out-of-range → trampoline.
    :   lda line_buffer,x

        cmp #'M'
        beq @move
        cmp #'m'
        beq @move
        cmp #'S'
        beq @shoot
        cmp #'s'
        beq @shoot
        cmp #'H'
        beq @help
        cmp #'h'
        beq @help
        cmp #'?'
        beq @help

        ; Bare digit? Treat as an implicit "M N".
        cmp #'0'
        bcc :+
        cmp #'9'+1
        bcc @move_parse                 ; digit ($30..$39): bare-N move.
    :   jmp @huh                        ; out-of-range → trampoline.

    @move:
        inc parse_idx
        jsr skip_spaces
        ; If nothing (or no digit) follows the M, show the map instead.
        ldx parse_idx
        cpx parse_len
        bcs @show_map
        lda line_buffer,x
        cmp #'0'
        bcc @show_map
        cmp #'9'+1
        bcs @show_map
        jmp @move_parse

    @show_map:
        jsr print_map
        rts

    @move_parse:
        jsr parse_cave_arg
        bcs @done                       ; parse error already reported.
        jmp do_move                     ; A = target cave (0-indexed)

    @shoot:
        inc parse_idx
        jmp do_shoot

    @help:
        PRINT TTY::write, msg_help
        rts

    @huh:
        PRINT TTY::write, msg_huh
    @done:
        rts
    .endproc

    .proc skip_spaces
    @loop:
        ldx parse_idx
        cpx parse_len
        bcs @done
        lda line_buffer,x
        cmp #' '
        beq @advance
        cmp #9
        beq @advance
        rts
    @advance:
        inc parse_idx
        jmp @loop
    @done:
        rts
    .endproc

    .proc skip_separators
    @loop:
        ldx parse_idx
        cpx parse_len
        bcs @done
        lda line_buffer,x
        cmp #' '
        beq @advance
        cmp #','
        beq @advance
        cmp #9
        beq @advance
        rts
    @advance:
        inc parse_idx
        jmp @loop
    @done:
        rts
    .endproc

    ; Parse a decimal cave number from the line at parse_idx.
    ;
    ; In:
    ;   parse_idx points at first digit (caller calls skip_spaces first).
    ; Out:
    ;   On success: C=0, A = 0-indexed cave (0..19), parse_idx advanced.
    ;   On failure: C=1; an error message has already been printed.
    ;   X, Y = clobbered.
    .proc parse_cave_arg
        lda #0
        sta parse_acc
        ldx parse_idx
        cpx parse_len
        bcs @bad_cave

        lda line_buffer,x
        cmp #'0'
        bcc @bad_cave
        cmp #'9'+1
        bcs @bad_cave

    @loop:
        cpx parse_len
        bcs @end
        lda line_buffer,x
        cmp #'0'
        bcc @end
        cmp #'9'+1
        bcs @end
        sec
        sbc #'0'
        sta parse_dig
        ; parse_acc = parse_acc * 10 + digit. If acc >= 26 the result
        ; would exceed 8 bits — and is way bigger than NUM_CAVES, so
        ; we can flag it out-of-range right now.
        lda parse_acc
        cmp #26
        bcs @bad_cave
        asl                             ; *2
        sta parse_acc
        asl                             ; *4
        asl                             ; *8
        clc
        adc parse_acc                   ; *2 + *8 = *10
        clc
        adc parse_dig
        sta parse_acc
        inx
        jmp @loop

    @end:
        stx parse_idx
        lda parse_acc
        beq @bad_cave                   ; "0" is not a valid cave (1..20).
        cmp #NUM_CAVES + 1
        bcs @bad_cave
        sec
        sbc #1                          ; convert to 0-indexed.
        clc
        rts

    @bad_cave:
        PRINT TTY::write, msg_bad_cave
        sec
        rts
    .endproc

; ---------------------------------------------------------------------------
; Move action.
; ---------------------------------------------------------------------------

    ; In:
    ;   A = target cave (0-indexed, validated 0..19).
    .proc do_move
        sta target_cave

        ; Validate adjacency.
        ldx player_cave
        ldy #0
        jsr lookup_neighbour
        cmp target_cave
        beq @ok
        ldx player_cave
        ldy #1
        jsr lookup_neighbour
        cmp target_cave
        beq @ok
        ldx player_cave
        ldy #2
        jsr lookup_neighbour
        cmp target_cave
        beq @ok

        PRINT TTY::write, msg_not_adjacent
        rts

    @ok:
        lda target_cave
        sta player_cave
        jmp resolve_room_hazards
    .endproc

    ; After moving (or being teleported by bats) into player_cave,
    ; check what's there.
    .proc resolve_room_hazards
        lda player_cave
        cmp wumpus_cave
        beq @wumpus
        cmp pit1_cave
        beq @pit
        cmp pit2_cave
        beq @pit
        cmp bat1_cave
        beq @bat
        cmp bat2_cave
        beq @bat
        rts                             ; safe cave.

    @wumpus:
        PRINT TTY::write, msg_eaten
        lda #GAME_LOST
        sta game_over
        rts

    @pit:
        PRINT TTY::write, msg_pit
        lda #GAME_LOST
        sta game_over
        rts

    @bat:
        PRINT TTY::write, msg_bat_grab
        lda #NUM_CAVES
        jsr prng__random_in_range
        sta player_cave
        PRINT TTY::write, msg_bat_drop
        lda player_cave
        clc
        adc #1
        jsr print_dec_a
        PRINT TTY::write, msg_dot_nl
        ; Tail-recursive — chained bats are a real possibility (and
        ; hilarious when they happen). Each landing re-resolves.
        jmp resolve_room_hazards
    .endproc

; ---------------------------------------------------------------------------
; Shoot action.
; ---------------------------------------------------------------------------

    .proc do_shoot
        lda arrows
        bne @have_arrows
        PRINT TTY::write, msg_no_arrows
        rts
    @have_arrows:

        ; Parse up to MAX_ARROW_PATH cave numbers separated by spaces or
        ; commas.
        lda #0
        sta arrow_count
    @parse_loop:
        jsr skip_separators
        ldx parse_idx
        cpx parse_len
        bcs @parse_done
        lda line_buffer,x
        cmp #'0'
        bcc @parse_done
        cmp #'9'+1
        bcs @parse_done

        ldx arrow_count
        cpx #MAX_ARROW_PATH
        bcc @room
        PRINT TTY::write, msg_too_long_path
        rts
    @room:
        jsr parse_cave_arg
        bcs @abort
        ldx arrow_count
        sta arrow_path,x
        inc arrow_count
        jmp @parse_loop

    @parse_done:
        lda arrow_count
        bne @have_path
        PRINT TTY::write, msg_no_path
        rts

    @have_path:
        dec arrows
        jmp fly_arrow

    @abort:
        rts
    .endproc

    ; Fly the arrow through arrow_path[0..arrow_count). Each step must be
    ; adjacent to the previous cave (or to player_cave for the first
    ; step). If a step isn't adjacent, the arrow ricochets to a random
    ; neighbour of the *current* cave.
    .proc fly_arrow
        lda player_cave
        sta arrow_pos
        lda #0
        sta arrow_idx

    @next:
        lda arrow_idx
        cmp arrow_count
        bcc :+
        jmp @miss                       ; out-of-range → trampoline.
    :   ldx arrow_idx
        lda arrow_path,x
        sta arrow_next                  ; intended cave

        ; Is arrow_next adjacent to arrow_pos?
        ldx arrow_pos
        ldy #0
        jsr lookup_neighbour
        cmp arrow_next
        beq @step_ok
        ldx arrow_pos
        ldy #1
        jsr lookup_neighbour
        cmp arrow_next
        beq @step_ok
        ldx arrow_pos
        ldy #2
        jsr lookup_neighbour
        cmp arrow_next
        beq @step_ok

        ; Ricochet: pick a random tunnel from the current cave.
        PRINT TTY::write, msg_arrow_ricochet
        lda #3
        jsr prng__random_in_range
        tay
        ldx arrow_pos
        jsr lookup_neighbour
        sta arrow_next

    @step_ok:
        lda arrow_next
        sta arrow_pos

        cmp wumpus_cave
        beq @hit_wumpus
        cmp player_cave
        beq @self_shot

        inc arrow_idx
        jmp @next

    @hit_wumpus:
        PRINT TTY::write, msg_arrow_hit
        lda #GAME_WON
        sta game_over
        rts

    @self_shot:
        PRINT TTY::write, msg_self_shot
        lda #GAME_LOST
        sta game_over
        rts

    @miss:
        PRINT TTY::write, msg_arrow_miss
        ; 75% chance the wumpus wakes and shuffles.
        lda #4
        jsr prng__random_in_range
        beq @still_sleeping             ; 1-in-4 stays asleep.
        jsr wake_wumpus
        lda game_over
        bne @done                       ; wumpus shuffled into us.
    @still_sleeping:
        lda arrows
        bne @done
        PRINT TTY::write, msg_out_of_arrows
        lda #GAME_LOST
        sta game_over
    @done:
        rts
    .endproc

    .proc wake_wumpus
        PRINT TTY::write, msg_wumpus_wakes
        lda #3
        jsr prng__random_in_range
        tay
        ldx wumpus_cave
        jsr lookup_neighbour
        sta wumpus_cave
        cmp player_cave
        bne @done
        PRINT TTY::write, msg_eaten
        lda #GAME_LOST
        sta game_over
    @done:
        rts
    .endproc

; ---------------------------------------------------------------------------
; Helpers.
; ---------------------------------------------------------------------------

    ; Print A as a decimal number via the TTY.
    .proc print_dec_a
        sta fmtdec::value
        jsr fmtdec
        PRINT_PTR TTY::write, fmtdec::decimal
        rts
    .endproc

    ; -----------------------------------------------------------------------
    ; Advance the map string pointer by one byte (helper for print_map).

    .proc advance_map_ptr
        inc map_ptr
        bne :+
        inc map_ptr + 1
    :   rts
    .endproc

    ; -----------------------------------------------------------------------
    ; Print the cave map, wrapping the player's cave in parentheses.
    ;
    ; The trick: use a one-byte look-behind buffer (map_buf). We stay one
    ; step behind the read head. When we hit a cave byte, the previously
    ; read char (still unprinted in map_buf) is the LEFT FLANK — a dash or
    ; space that we absorb into '(' for the active cave, or emit normally
    ; for any other cave. After printing the cave number, we peek at the
    ; next byte: if it's a dash or space (the RIGHT FLANK), we consume it
    ; and it becomes ')'. Result:
    ;
    ;    inactive cave 13 in `--13--`:  emit `-`, emit `13`, next loop: `-`
    ;    active   cave 13 in `--13--`:  emit `(`, emit `13`, emit `)`, skip `-`
    ;
    ; Both produce the same on-screen width. The diagram layout is
    ; preserved regardless of which cave the player is in.
    ;
    ; Caves 2 and 3 sit at line-ends (right neighbour = newline). A
    ; trailing space is appended to their encoded lines so the right-flank
    ; absorber always has a space to consume.

    .proc print_map
        lda #<msg_map
        sta map_ptr
        lda #>msg_map
        sta map_ptr + 1
        lda #0
        sta map_buf                 ; buffer empty at start

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

        ; Is this the player's cave? (convert 1-indexed N to 0-indexed)
        sec
        sbc #CAVE + 1               ; A = N - 1 (0-indexed)
        cmp player_cave
        bne @cave_inactive

        ; Active cave: discard left-flank buffer, emit ( N )
        lda #'('
        jsr TTY::write
        lda lookup_tmp
        sec
        sbc #CAVE                   ; A = N (1-indexed)
        jsr print_dec_a
        lda #')'
        jsr TTY::write
        jsr advance_map_ptr         ; skip past the cave byte
        ; Consume one more byte as the right flank, unless we've hit the
        ; null terminator. Every non-null byte after a cave number in the
        ; diagram is a valid flank character (dash, space, or the trailing
        ; space added to end-of-line caves 2 and 3).
        ldy #0
        lda (map_ptr),y
        beq @cave_done              ; null terminator — nothing to consume.
        jsr advance_map_ptr         ; consume right flank
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
        jsr advance_map_ptr         ; skip past the cave byte
        jmp @loop

        ; ---------- regular ASCII byte ----------
    @regular:
        ; Save the current byte across the TTY::write call (which clobbers A).
        pha
        lda map_buf
        beq :+
        jsr TTY::write
    :   pla
        sta map_buf
        jsr advance_map_ptr
        jmp @loop

    @flush_done:
        ; The null terminator was reached. map_buf holds the last byte of
        ; the string. Emit it and return.
        lda map_buf
        jsr TTY::write
        rts
    .endproc

; ---------------------------------------------------------------------------
; LCD status display.
; ---------------------------------------------------------------------------

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

    ; -----------------------------------------------------------------------
    ; Update the LED to reflect Wumpus proximity.
    ;
    ;   LED on  → Wumpus is in an adjacent cave (you can smell it).
    ;   LED off → Wumpus is not adjacent.
    ;
    ; This gives a real-world, glanceable indicator independent of the
    ; terminal output. The LED turns off automatically at round start /
    ; the Press-Enter screen so it doesn't mislead between games.

    .proc update_led
        lda wumpus_cave
        sta probe_cave
        jsr is_neighbour_of_player
        bcs @on
        jmp LED::turn_off
    @on:
        jmp LED::turn_on
    .endproc
