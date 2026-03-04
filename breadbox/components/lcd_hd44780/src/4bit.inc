; -----------------------------------------------------------------
; Mode-specific initialization hook, called by the `init` routine.
;
; Switch the display to 4-bit mode.
; After this, all commands are sent as two-nibble transfers.
;
; Out: A = clobbered

.proc {{ my_def("init_for_mode") }}
    lda #$20
    jsr {{ my("write_init") }}
    DELAY_US 200

    rts
.endproc

; -----------------------------------------------------------------
; Write a byte to the display's data bus.
;
; The register select (RS) + write mode must already be configured by the caller.
; Sends the high nibble first, then the low nibble, with EN pulses.
;
; In:
;   A = byte to send
; Out:
;   A = clobbered

.proc {{ my_def("write_byte") }}
    ; High nibble: upper 4 bits are already in position.
    pha
    jsr {{ data_pins.api("write") }}
    jsr {{ my("pulse_en") }}

    ; Low nibble: shift lower 4 bits into upper position.
    pla
    asl
    asl
    asl
    asl
    jsr {{ data_pins.api("write") }}
    jsr {{ my("pulse_en") }}

    rts
.endproc

; -----------------------------------------------------------------
; Read a byte from the display's data bus.
;
; The register select (RS) + read mode must already be configured by the caller.
; Only the high nibble is used in the implementation. This routine reads the
; high nibble, and then clocks out the low nibble, saving four shift operations
; to construct the full byte.
;
; Out:
;   A = the byte that was read

.proc {{ my_def("read_byte") }}
    ; Pulse EN high and read the high nibble from the data port.
    jsr {{ en_pin.api("turn_on") }}
    jsr {{ data_pins.api("read_port") }}
    pha
    jsr {{ en_pin.api("turn_off") }}

    ; Pulse to clock out the low nibble (ignored).
    jsr {{ my("pulse_en") }}
    pla

    rts
.endproc
