; ---------------------------------------------------------------------------
; game.inc — Shared constants and cross-module symbol declarations.
;
; Include this in every wumpus module. Uses ca65's .globalzp / .global
; directives: a symbol is EXPORTED by the translation unit that defines
; it, and IMPORTED by every other unit that includes this header — no
; per-file .importzp/.import lists needed.
; ---------------------------------------------------------------------------

LINE_MAX       = 64
NUM_CAVES      = 20
INITIAL_ARROWS = 5
MAX_ARROW_PATH = 5
CAVE           = $80    ; CAVE+N encodes cave N (1-indexed) in msg_map

GAME_PLAYING   = 0
GAME_WON       = 1
GAME_LOST      = 2

; ---------------------------------------------------------------------------
; Zero-page state (owned by world.s).

.globalzp player_cave, wumpus_cave
.globalzp pit1_cave, pit2_cave
.globalzp bat1_cave, bat2_cave
.globalzp arrows, game_over
.globalzp probe_cave        ; scratch: caller fills before is_neighbour_of_player

; ---------------------------------------------------------------------------
; Zero-page parser state (owned by parser.s).

.globalzp parse_idx, parse_len, parse_acc, parse_dig

; ---------------------------------------------------------------------------
; Zero-page action state (owned by actions.s).

.globalzp arrow_count, arrow_idx, arrow_pos, arrow_next, target_cave

; ---------------------------------------------------------------------------
; Zero-page map state (owned by map.s).

.globalzp lookup_tmp
.globalzp map_ptr           ; 2 bytes: 16-bit string pointer for print_map
.globalzp map_buf           ; 1 byte: look-behind buffer for print_map

; ---------------------------------------------------------------------------
; RAM buffers (owned by world.s).

.global line_buffer
.global arrow_path

; ---------------------------------------------------------------------------
; PRNG (owned by prng.s).

.globalzp prng__seed_lo, prng__seed_hi
.global   prng__step, prng__random_in_range

; ---------------------------------------------------------------------------
; Shared procedures.

.global setup_world, resolve_room_hazards, wake_wumpus
.global is_neighbour_of_player
.global lookup_neighbour, print_map
.global show_room
.global lcd_show_cave_and_arrows, update_led
.global lcd_show_dead, lcd_show_win, lcd_show_welcome
.global handle_line, skip_separators, parse_cave_arg
.global do_move, do_shoot
.global print_dec_a
.global wumpus_run
