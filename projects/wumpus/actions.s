; ---------------------------------------------------------------------------
; actions.s — Move and shoot mechanics.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "game.inc"

; ---------------------------------------------------------------------------
; Zero-page action state.

.segment "ZEROPAGE"

arrow_count: .res 1  ; number of caves named in a shot
arrow_idx:   .res 1  ; loop index while flying the arrow
arrow_pos:   .res 1  ; cave the arrow is currently in
arrow_next:  .res 1  ; next cave the arrow will travel to
target_cave: .res 1  ; target of a move command

; ---------------------------------------------------------------------------
; Strings local to this module.

.segment "DATA"

msg_not_adjacent:  .asciiz "That cave isn't connected to this one.\n"
msg_arrow_hit:     .asciiz "\n** You hit the Wumpus! Dinner is on you. **\n"
msg_self_shot:     .asciiz "\n** Ouch. You shot yourself. **\n"
msg_arrow_miss:    .asciiz "Missed.\n"
msg_arrow_ricochet:.asciiz "* The arrow ricochets!\n"
msg_out_of_arrows: .asciiz "\n** Out of arrows. **\n"
msg_no_arrows:     .asciiz "You have no arrows left!\n"
msg_no_path:       .asciiz "Where would you shoot? Specify at least one cave.\n"
msg_too_long_path: .asciiz "An arrow can travel through at most 5 caves.\n"

; ---------------------------------------------------------------------------
; Move action.
;
; In:
;   A = target cave (0-indexed, already validated as 0..19).

.segment "CODE"

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

; ---------------------------------------------------------------------------
; Shoot action — parse cave path, then fly the arrow.

    .proc do_shoot
        lda arrows
        bne @have_arrows
        PRINT TTY::write, msg_no_arrows
        rts
    @have_arrows:

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

; ---------------------------------------------------------------------------
; Arrow flight — step through arrow_path, ricocheting on invalid steps.

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
        sta arrow_next

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
        ; 75% chance the Wumpus wakes and shuffles.
        lda #4
        jsr prng__random_in_range
        beq @still_sleeping             ; 1-in-4 stays asleep.
        jsr wake_wumpus
        lda game_over
        bne @done                       ; Wumpus shuffled into us.
    @still_sleeping:
        lda arrows
        bne @done
        PRINT TTY::write, msg_out_of_arrows
        lda #GAME_LOST
        sta game_over
    @done:
        rts
    .endproc
