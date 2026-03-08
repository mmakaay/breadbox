; UART 6551: {{ component_id }} ({{ type }})
;
{% if type == "w65c51n" %}
{% if irq == "on" %}
; Driver: W65C51N, IRQ on (RX ring buffer, timed TX delay for TDRE bug workaround)
{% else %}
; Driver: W65C51N, polling (timed TX delay for TDRE bug workaround)
{% endif %}
{% else %}
{% if irq == "on" %}
; Driver: {{ type | upper }}, IRQ on (RX + TX ring buffers, hardware TDRE for TX flow)
{% else %}
; Driver: {{ type | upper }}, polling (TDRE poll for TX, RDRF poll for RX)
{% endif %}
{% endif %}
; Baud rate: {{ baudrate }}

.include "CORE/delay_macros.inc"
.include "CORE/coding_macros.inc"
.include "{{ component_path }}/constants.inc"

; =========================================================================
; Shared driver code.
; =========================================================================

.segment "KERNALROM"

    ; =====================================================================
    ; Soft reset the ACIA.
    ;
    ; Writing any value to the status register triggers a programmed reset.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ my_def("soft_reset") }}
        sta STATUS
        DELAY_MS 100
        rts
    .endproc

    ; =====================================================================
    ; Write a byte to a terminal.
    ;
    ; Handles CR → CR+LF conversion for terminal-style output.
    ;
    ; In:
    ;   A = data byte to transmit
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write_terminal") }}
        cmp #$0d
        bne @raw

        ; Send CR first, then queue LF.
        jsr {{ api("write") }}
        lda #$0a
    @raw:
        jmp {{ api("write") }}
    .endproc

; =========================================================================
; IC-specific driver code.
; =========================================================================

{% if type == "w65c51n" %}
.include "{{ component_path }}/_w65c51n.inc"
{% else %}
.include "{{ component_path }}/_generic.inc"
{% endif %}
