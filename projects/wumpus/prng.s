; ---------------------------------------------------------------------------
; 16-bit Galois LFSR pseudo-random number generator.
;
; Maximal-length sequence (period 65535) using taps polynomial $B400.
; Sequence loops through every non-zero 16-bit value once before
; repeating; the all-zero state is a fixed point and must never be
; the seed.
;
; Public API (all symbols exported with the prng__ prefix to avoid
; namespace clashes when imported into wumpus.s):
;   prng__seed_lo / prng__seed_hi    Current LFSR state (16-bit, non-zero).
;                                    Caller seeds these once at startup;
;                                    every step() call advances them.
;   prng__step                       Advance by one step. Updates the
;                                    seed in place; returns the new low
;                                    byte in A. X, Y preserved.
;   prng__random_in_range            A = ceiling. Returns a value in
;                                    0..A-1 in A. Modulo bias is < 1/256
;                                    for any ceiling we use (max=20),
;                                    well below anything the player
;                                    could perceive.
; ---------------------------------------------------------------------------

.include "breadbox.inc"

.exportzp prng__seed_lo
.exportzp prng__seed_hi
.export prng__step
.export prng__random_in_range

.segment "ZEROPAGE"

prng__seed_lo: .res 1
prng__seed_hi: .res 1
prng__range:   .res 1                   ; ceiling for random_in_range

.segment "CODE"

    ; -----------------------------------------------------------------------
    ; Advance the LFSR by one step (Galois form).
    ;
    ;   bit_out = state & 1
    ;   state >>= 1
    ;   if bit_out: state ^= $B400
    ;
    ; The XOR mask $B400 corresponds to taps 16, 14, 13, 11.
    ;
    ; Out:
    ;   A = new seed_lo
    ;   X, Y = preserved
    ;   N, Z reflect A

    .proc prng__step
        lda prng__seed_lo
        lsr prng__seed_hi               ; shift the whole 16-bit state right.
        ror                             ; carry-in: old hi.bit0; carry-out: old lo.bit0.
        sta prng__seed_lo
        bcc @no_xor                     ; bit_out was 0: no taps fire.
        ; Apply the tap polynomial. Low byte mask is $00 (no XOR);
        ; high byte mask is $B4.
        lda prng__seed_hi
        eor #$b4
        sta prng__seed_hi
    @no_xor:
        lda prng__seed_lo
        rts
    .endproc

    ; -----------------------------------------------------------------------
    ; Return a uniform-ish random value in [0, ceiling).
    ;
    ; In:
    ;   A = exclusive upper bound (must be > 0)
    ; Out:
    ;   A = random value, 0..ceiling-1
    ;   X, Y = preserved

    .proc prng__random_in_range
        sta prng__range
        jsr prng__step                  ; A = fresh random byte
        ; Reduce modulo `range`. Repeated subtraction is fine since
        ; ranges are small (max 20 in this game, so at most ~12 loops
        ; from a starting value of 255).
    @reduce:
        cmp prng__range
        bcc @done
        sec
        sbc prng__range
        jmp @reduce
    @done:
        rts
    .endproc
