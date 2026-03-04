; -----------------------------------------------------------------
; Mode-specific initialization hook, called by the `init` routine.
;
; No specific initialization required for 8-bit operation. The `power_up`
; routine already initializes the device for this mode.
;
; Out: A = clobbered

.proc {{ my_def("init_for_mode") }}
    rts
.endproc

; -----------------------------------------------------------------
; Write a byte to the display's data bus.
;
; The register select (RS) + write mode must already be configured by the caller.
; Sends the full byte in a single transfer, with EN pulses.
;
; In:
;   A = byte to send
; Out:
;   A = clobbered

.proc {{ my_def("write_byte") }}
    jsr {{ data_pins.api("write") }}
    jsr {{ my("pulse_en") }}
    rts
.endproc

; -----------------------------------------------------------------
; Read a byte from the display's data bus.
;
; The register select (RS) + read mode must already be configured by the caller.
;
; Out:
;   A = the byte that was read

.proc {{ my_def("read_byte") }}
    ; Pulse EN high and read the full byte from the data port.
    jsr {{ en_pin.api("turn_on") }}
    jsr {{ data_pins.api("read_port") }}
    pha
    jsr {{ en_pin.api("turn_off") }}
    pla
    rts
.endproc
