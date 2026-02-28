; =========================================================================
; Coding utility macros.
;
; Convenience wrappers for common 6502 byte and word operations.
; =========================================================================

; =========================================================================
; Store an 8-bit value in a memory location.
;
; In:
;   _target = target address
;   _value  = value to store (e.g. #$42)
; Out:
;   A = clobbered

.macro SET_BYTE _target, _value
    lda _value
    sta _target
.endmacro

; =========================================================================
; Store zero into a memory location.
;
; In:
;   _target = target address
; Out:
;   A = clobbered

.macro CLR_BYTE _target
    SET_BYTE _target, #0
.endmacro

; =========================================================================
; Store a 16-bit word value in two consecutive memory locations.
;
; In:
;   _target = address of the low byte
;   _value  = direct word value to sture (not contents at address)
; Out:
;   A = clobbered

.macro SET_WORD _target, _value
    SET_BYTE _target, #<(_value)
    SET_BYTE _target + 1, #>(_value)
.endmacro

; =========================================================================
; Copy a 16-bit address into two consecutive memory locations.
;
; Stores the address of _source (not the contents at that address).
; Useful for setting up indirect jump vectors and pointers.
;
; In:
;   _target = address to store into
;   _source = label whose address is stored
; Out:
;   A = clobbered

.macro CP_ADDRESS _target, _source
    SET_WORD _target, _source
.endmacro

; =========================================================================
; Store zero into a 16-bit word.
;
; In:
;   _target = address of the low byte
; Out:
;   A = clobbered

.macro CLR_WORD _target
    SET_WORD _target, $0000
.endmacro

; =========================================================================
; Copy a 16-bit word from one memory location to another.
;
; In:
;   _target = destination address
;   _source = source address
; Out:
;   A = clobbered

.macro CP_WORD _target, _source
    SET_BYTE _target, _source
    SET_BYTE _target + 1, _source + 1
.endmacro

; =========================================================================
; Increment a 16-bit word by 1.
;
; In:
;   _target = address of the word to increment
; Out:
;   C = set when word wraps ($FFFF -> $0000)
;   A = clobbered

.macro INC_WORD _target
    clc
    lda _target
    adc #1
    sta _target
    lda _target + 1
    adc #0
    sta _target + 1
.endmacro

; =========================================================================
; Decrement a 16-bit word by 1.
;
; In:
;   _target = address of the word to decrement
; Out:
;   C = clear when word wraps ($0000 -> $FFFF)
;   A = clobbered

.macro DEC_WORD _target
    sec
    lda _target
    sbc #1
    sta _target
    lda _target + 1
    sbc #0
    sta _target + 1
.endmacro

; =========================================================================
; Push A, X and Y onto the stack.

.macro PUSH_AXY
    pha
    phx
    phy
.endmacro

; =========================================================================
; Pull A, X and Y from the stack (reverse order of PUSH_AXY).

.macro PULL_AXY
    ply
    plx
    pla
.endmacro
