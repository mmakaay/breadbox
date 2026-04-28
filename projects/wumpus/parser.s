; ---------------------------------------------------------------------------
; parser.s — Command-line parsing and action dispatch.
; ---------------------------------------------------------------------------

.feature string_escapes

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "game.inc"

; ---------------------------------------------------------------------------
; Zero-page parser state.

.segment "ZEROPAGE"

parse_idx:  .res 1  ; cursor in line_buffer during parsing
parse_len:  .res 1  ; length returned from TTY::readline
parse_acc:  .res 1  ; running accumulator in parse_cave_arg
parse_dig:  .res 1  ; digit scratch in parse_cave_arg's *10 step

; ---------------------------------------------------------------------------
; Strings local to this module.

.segment "DATA"

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

msg_huh:      .asciiz "I don't understand that. Type H for help.\n"
msg_bad_cave: .asciiz "That isn't a valid cave number.\n"

; ---------------------------------------------------------------------------
; Main command dispatcher.

.segment "CODE"

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
        ; If nothing (or no digit) follows M, show the map.
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
        jmp do_move                     ; A = target cave (0-index  ed).

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

; ---------------------------------------------------------------------------
; Skip whitespace (spaces and tabs) from parse_idx.

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

; ---------------------------------------------------------------------------
; Skip separators (spaces, tabs, commas) from parse_idx.

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

; ---------------------------------------------------------------------------
; Parse a decimal cave number from line_buffer at parse_idx.
;
; In:
;   parse_idx points at first digit (caller calls skip_spaces first).
; Out:
;   C=0, A = 0-indexed cave (0..19), parse_idx advanced past digits.
;   C=1 on error; message already printed.

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
