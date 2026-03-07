.segment "KERNALROM"

    ; =========================================================================
    ; Halt program execution.
    ;
    ; Use the `HALT` macro to jump to this function.

    .proc {{ api_def("halt") }}
        sei                          ; Interrupts handling must not break loop.
    @loop:                           ; Loop indefinitely.
        jmp @loop
    .endproc
