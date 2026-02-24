.export   __core_boot = boot         ; Export to make it available to vectors.s
.export   __core_halt = halt
.exportzp __core_trampoline_to = trampoline_to
.export   __core_trampoline = trampoline

.import   main                       ; The subroutine to start after initialization

.segment "ZEROPAGE"        
        
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
        ldx #$ff                     ; Initialize stack pointer.
        txs
        cld                          ; Make sure decimal mode is disabled.
        jmp main                     ; Call main (must be exported by project).

    ; =========================================================================
    ; Halt program execution.
    ;
    ; Use the `HALT` macro to jump to this function.

    .proc halt
        sei                          ; Interrupts handling must not break loop.
    @loop:                           ; Loop indefinitely.
        jmp @loop
    .endproc

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
