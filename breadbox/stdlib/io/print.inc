; -----------------------------------------------------------------
; Print module
;
; Generic string printing with configurable output device.
;
; The print subroutine walks a null-terminated string via a
; 16-bit pointer, calling an output function for each byte. The
; output function is specified as a function pointer, allowing the
; same print logic to target any output device (LCD, UART, etc.).
;
; For direct use:
;
;   CP_ADDRESS PRINT::string, my_text
;   CP_ADDRESS PRINT::writer, MY_DISPLAY::write
;   jsr PRINT::print
;
; The `PRINT` macro provides a convenience wrapper for this.
; Use `PRINT_PTR` when the string address is in a pointer variable.
;
;   PRINT     MY_DISPLAY::write, my_text      ; label (direct)
;   PRINT_PTR MY_DISPLAY::write, my_pointer   ; pointer (indirect)
;
; Writer function contract:
;   In:  A = byte to write
;   Out: A, X preserved, Y may be clobbered
; -----------------------------------------------------------------

.include "breadbox.inc"

.segment "ZEROPAGE"

    {{ symbol("string") }}: .res 2     ; Pointer to null-terminated string
    {{ symbol("writer") }}: .res 2     ; Pointer to output function

.segment "KERNALROM"

    .proc print
        ; Print a null-terminated string via the configured writer.
        ;
        ; In (zero page):
        ;   PRINT::string = pointer to null-terminated string
        ;   PRINT::writer = pointer to output function
        ; Out:
        ;   A, X, Y preserved

        string = {{ symbol("string") }}
        writer = {{ symbol("writer") }}

        PUSH_AXY

        ldy #0
    @loop:
        lda (string),y
        beq @done
        jsr _call_writer
        iny
        bne @loop
        inc string+1             ; Page crossing: bump high byte
        jmp @loop

    @done:
        PULL_AXY
        rts
    .endproc

    ; Trampoline for indirect JSR.
    ;
    ; The 6502 has no `jsr (indirect)` instruction. A `jsr _call_writer`
    ; pushes the return address, then `jmp (writer)` jumps to the target
    ; function, whose `rts` returns to the original caller.
    _call_writer:
        jmp ({{ symbol("writer") }})

.macro PRINT _writer_function, _string_address
    ; PRINT - print a null-terminated string using a given writer function.
    ;
    ; In:
    ;   device = the device name (e.g. LCD or UART)
    ;   string_address = the address of the string to print
    ; Out:
    ;   A, X, Y preserved

    CP_ADDRESS print::writer, _writer_function
    CP_ADDRESS print::string, _string_address
    jsr print
.endmacro

.macro PRINT_PTR _writer_function, _pointer
    ; PRINT_PTR - print a null-terminated string via a pointer variable.
    ;
    ; In:
    ;   _writer_function = the writer function (e.g. LCD::write)
    ;   _pointer = address of a 2-byte pointer to the string
    ; Out:
    ;   A, X, Y preserved

    CP_ADDRESS print::writer, _writer_function
    CP_WORD print::string, _pointer
    jsr print
.endmacro
