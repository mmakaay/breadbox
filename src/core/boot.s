.scope KERNAL

    .export __core_boot = boot       ; Export to make it available to vectors.s
    .export __core_halt = halt       ; Used by macro `HALT`

    .import main                     ; The subroutine to start after initialization
    .import __INIT_TABLE__           ; Start of the constructor pointer table
    .import __INIT_COUNT__           ; Number of entries (word)
        
.segment "ZEROPAGE"        
        
    ptr:            .res 2           ; Scratch space for indirect calls
    trampoline_to:  .res 2           ; Target address for trampoline construction

.segment "KERNAL"

        ; =========================================================================
        ; KERNAL Boot sequence
        ;
        ; Provides the boot subroutine (jumped to by reset vector) and the
        ; halt loop. The boot sequence initializes hardware and then jumps
        ; to `main`, which must be implemented by the project that is
        ; built on top of BREADBOX.

        boot:
            ldx #$ff                 ; Initialize stack pointer
            txs
            jsr call_all_constructors
            jmp main                 ; Implemented by project that uses BREADBOX

        ; =========================================================================
        ; Run all constructors.
        ;
        ; Constructors are subroutines that are marked with .constructor in
        ; module code. These subroutines are all executed automatically from here.
        ;
        ; Out:
        ;  A, X, Y = clobbered

        .proc call_all_constructors
            ; Only the low byte is read here, assuming that 255 constructors
            ; ought to be enough for anyone. If we exceed 255 at some point,
            ; then we'll have to modify this code to use a word instead.
            ldx __INIT_COUNT__       ; Number of table entries
            ldy #0                   ; Index into table

            ; Set up a pointer to the start of the constructor table.
            lda #<__INIT_TABLE__
            sta ptr
            lda #>__INIT_TABLE__
            sta ptr+1
        
        @loop:
            ; Read the next subroutine address from the table.
            lda (ptr), y
            sta trampoline_to
            iny
            lda (ptr), y
            sta trampoline_to + 1

            ; Trampoline into the routine, protecting against clobbering.
            txa                      ; Store X and Y on the stack.
            pha
            tya
            pha
            jsr trampoline
            pla                      ; Restore X and Y from the stack.
            tay
            pla
            txa

            ; Move to the next table entry, if any.
            dex                      ; Decrement table size counter.  
            beq @done                ; Reached zero? Then we're done.
            iny                      ; Move to the next constructor.

        @done:
            rts
        .endproc

        ; =========================================================================
        ; Halt program execution.

        ; Can be jumped to (jmp KERNAL::halt), to halt the computer.
        halt:
            sei                      ; Disable interrupts, they must not break loop.
        @loop:                       ; Loop indefinitely.
            jmp @loop

        ; =========================================================================
        ; Classic 6502 JSR trampoline.
        ;
        ; The 6502 has no `JSR (indirect)` instruction. Work around this by
        ; doing a `jsr` into a subroutine (the trampoline) that then does a `jmp`
        ; to the target subroutine address. When that subroutine does its `rts`,
        ; the program pointer returns to the point from where the `jsr` was done.
        ;
        ; In:
        ;   trampoline_to: address, containing a pointer to the subroutine to call
        ; Out:
        ;   A = clobbered
        
        .proc trampoline
            jmp (trampoline_to)
        .endproc

        .macro TRAMPOLINE_TO _target_routine
            lda #<_target_routine
            sta trampoline_to
            lda #>_target_routine
            sta trampoline_to + 1
            jsr trampoline
        .endmacro

.segment "ZEROPAGE"



.endscope