; =========================================================================
; Coding utility macros.
;
; Convenience wrappers for common operations.
; =========================================================================

; =========================================================================
; Store a byte value in a memory location.
;
; In:
;   _target = target address
;   _value  = value to store (e.g. #$42)
; Out:
;   A = clobbered

.macro STORE _target, _value
    lda _value
    sta _target
.endmacro

; =========================================================================
; Copy a byte value from one memory location to another.
;
; In:
;   _target = destination address
;   _source = source address (e.g. $1234)
; Out:
;   A = clobbered

.macro COPY _target, _source
    ; This is the same as the implementation for STORE.
    ; The difference between STORE and COPY is purely semantic,
    ; and choosing the one to use is purely based on intent.
    lda _source
    sta _target
.endmacro

; =========================================================================
; Store zero into a memory location.
;
; In:
;   _target = target address
; Out:
;   A = consider it clobbered (depends on CPU type)

.macro ZERO _target
    .if .ismnemonic(stz)
        stz _target
    .else
        lda #0
        sta _target
    .endif
.endmacro

; =========================================================================
; Store a 16-bit word value in two consecutive memory locations.
;
; In:
;   _target = address of the low byte
;   _value  = the word value to store
; Out:
;   A = clobbered

.macro STORE16 _target, _value
    lda #<(_value)    ; parentheses make sure that macro computations
    sta _target       ; will be evaluated, before extracting the lo/hi bytes.
    lda #>(_value)
    sta _target + 1
.endmacro

; =========================================================================
; Copy a 16-bit address into two consecutive memory locations.
;
; Useful for setting up indirect jump vectors and pointers.
;
; In:
;   _target = address to store into
;   _source = the pointer address value (e.g. label or #$1234)
; Out:
;   A = clobbered

.macro SET_POINTER _target, _source
    STORE16 _target, _source
.endmacro

; =========================================================================
; Store zero into a 16-bit word.
;
; In:
;   _target = address of the low byte
; Out:
;   A = consider it clobbered (depends on CPU type)

.macro ZERO16 _target
    .if .ismnemonic(stz)
        stz _target
        stz _target + 1
    .else
        lda #0
        sta _target
        sta _target + 1
    .endif
.endmacro

; =========================================================================
; Store zero into a 24-bit 3 byte value.
;
; In:
;   _target = address of the low byte
; Out:
;   A = consider it clobbered (depends on CPU type)

.macro ZERO24 _target
    .if .ismnemonic(stz)
        stz _target
        stz _target + 1
        stz _target + 2
    .else
        lda #0
        sta _target
        sta _target + 1
        sta _target + 2
    .endif
.endmacro

; =========================================================================
; Copy a 16-bit word value from one memory location to another.
;
; In:
;   _target = destination address
;   _source = source address (e.g. label or @$1234)
; Out:
;   A = clobbered

.macro COPY16 _target, _source
    COPY _target, _source
    COPY _target + 1, _source + 1
.endmacro

; =========================================================================
; Increment a 16-bit word by 1.
;
; In:
;   _target = address of the word to increment
; Out:
;   C = set when word wraps ($FFFF -> $0000)
;   A = clobbered

.macro INC16 _target
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

.macro DEC16 _target
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
    txa
    pha
    tya
    pha
.endmacro

; =========================================================================
; Pull A, X and Y from the stack (reverse order of PUSH_AXY).

.macro PULL_AXY
    pla
    tay
    pla
    tax
    pla
.endmacro

; =========================================================================
; ENDIF can be used by other macros to implement an optional code block.
;
; Example macro:
;
;     .macro IF_A_EQ value
;         cmp value
;         bne @endif
;
; Example usage:
;
;     IF_A_EQ #10
;         ... code to run if A = 10 ...
;     ENDIF

.macro ENDIF
    @endif:
.endmacro
