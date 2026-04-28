; ---------------------------------------------------------------------------
; world.s — Game state, world setup, hazard resolution, and adjacency query.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "game.inc"

; ---------------------------------------------------------------------------
; Zero-page game state.

.segment "ZEROPAGE"

player_cave: .res 1     ; 0..19
wumpus_cave: .res 1
pit1_cave:   .res 1
pit2_cave:   .res 1
bat1_cave:   .res 1
bat2_cave:   .res 1
arrows:      .res 1
game_over:   .res 1
probe_cave:  .res 1     ; scratch: caller fills before is_neighbour_of_player

; ---------------------------------------------------------------------------
; RAM buffers.

.segment "RAM"

line_buffer: .res LINE_MAX
arrow_path:  .res MAX_ARROW_PATH

; ---------------------------------------------------------------------------
; Strings local to this module.

.segment "DATA"

msg_eaten:       .asciiz "\n** Tssht. The Wumpus eats you. **\n"
msg_pit:         .asciiz "\n** YYYAAAAaaaaaa... you fell in a pit. **\n"
msg_bat_grab:    .asciiz "\n** A super bat snatches you! Whoosh... **\n"
msg_bat_drop:    .asciiz "Dropped in cave "
msg_dot_nl:      .asciiz ".\n"
msg_wumpus_wakes:.asciiz "* You hear lumbering. The Wumpus is on the move...\n"

; ---------------------------------------------------------------------------
; World setup — place player, Wumpus, pits, bats in distinct caves.

.segment "CODE"

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

; ---------------------------------------------------------------------------
; Hazard resolution — called after every move or bat-teleport.

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
        ; Tail-recursive — chained bats are hilarious when they happen.
        jmp resolve_room_hazards
    .endproc

; ---------------------------------------------------------------------------
; Wumpus waking — called after a missed shot (75% chance).

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
; Adjacency query.
;
; Caller fills probe_cave with the cave to test, then calls this proc.
; Returns C=1 if probe_cave is adjacent to player_cave, C=0 otherwise.

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
