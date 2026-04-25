.feature string_escapes

.include "CORE/coding_macros.inc"
.include "__keyboard/constants.inc"

.constructor {{ my("init") }}

.segment "ZEROPAGE"

    {{ var("previous_was_cr") }}: .res 1
    {{ var("flags") }}: .res 1
    {{ var("read_byte") }}: .res 1

.segment "KERNALROM"

    ; Option flags
    BIT_CANONICAL_ON = %00000001   ; Enable canonical mode
    BIT_ECHO_ON      = %00000010   ; Echo input characters

    ; =====================================================================
    ; Initialize the TTY.
    ;
    ; Enables canonical mode and echoing of input characters.
    ;
    ; Out:
    ;   A, X, y = prserved

    .proc {{ my("init") }}
        jsr {{ api("enable_canonical") }}
        jsr {{ api("enable_echo") }}
        rts
    .endproc

    ; =====================================================================
    ; Enable canonical mode.
    ;
    ; Out:
    ;   A, X, y = prserved

    .proc {{ api("enable_canonical") }}
        pha
        lda {{ var("flags") }}
        and #BIT_CANONICAL_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Disable canonical mode.
    ;
    ; Out:
    ;   A, X, y = prserved

    .proc {{ api("disable_canonical") }}
        pha
        lda {{ var("flags") }}
        and #<~BIT_CANONICAL_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Enable echoing of input characters.
    ;
    ; Out:
    ;   A, X, y = prserved

    .proc {{ api("enable_echo") }}
        pha
        lda {{ var("flags") }}
        and #BIT_ECHO_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Disable echoing of input characters.
    ;
    ; Out:
    ;   A, X, y = prserved

    .proc {{ api("disable_echo") }}
        pha
        lda {{ var("flags") }}
        and #<~BIT_ECHO_ON
        sta {{ var("flags") }}
        pla
        rts
    .endproc

    ; =====================================================================
    ; Clear the screen.
    ;
    ; Out:
    ;   A, X, Y = consider clobbered (depends on driver implementation)

    {{ api_def("clr") }} = {{ screen_device.api("clr") }}

    ; =====================================================================
    ; Read from the keyboard.
    ;
    ; Out:
    ;   A = character read, when carry is set, otherwise clobbered
    ;   C = set when character was read, clear otherwise
    ;   X, Y = preserved

    .proc {{ api_def("read") }}
        txa
        pha
        tya
        pha

        jsr {{ keyboard_device.api("read") }}
        bcc @done                   ; Return with carry clear.
        sta {{ var("read_byte") }}  ; Save received byte before echo.
        jsr {{ api_def("write") }}  ; Echo received input to the screen.
        sec                         ; Set carry to indicate "got input".
    @done:
        pla
        tay
        pla
        tax
        lda {{ var("read_byte") }}  ; Restore received byte into A.
        rts
    .endproc

    ; =====================================================================
    ; Write to the screen.
    ;
    ; In:
    ;   A = the byte to write
    ; Out:
    ;   A = the byte that was written
    ;   X, Y = consider clobbered (depends on driver implementation)

    .proc {{ api_def("write") }}
        ; Handle CR/LF, by normalizing \r, \n and \r\n to a newline call to the terminal.
        cmp #'\r'
        beq @cr
        cmp #'\n'
        beq @lf

        ; Handle DEL (delete) / BS (backspace)
        cmp #KEY_DEL           ; Delete? (backspace on many terminals)
        beq @backspace
        cmp #KEY_BS            ; Backspace?
        beq @backspace

        ; Echo the input to the TTY output.
        jmp {{ screen_device.api("write") }}

    @backspace:
        jmp {{ screen_device.api("backspace") }}

    @cr:
        jsr {{ screen_device.api("newline") }}
        ldx #1
        stx {{ var("previous_was_cr") }}
        rts

    @lf:
        ldx {{ var("previous_was_cr") }}
        beq @lone_lf
        ldx #0
        stx {{ var("previous_was_cr") }}
        rts

    @lone_lf:
        jmp {{ screen_device.api("newline") }}
    .endproc
