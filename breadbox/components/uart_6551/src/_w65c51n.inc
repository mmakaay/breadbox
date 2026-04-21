; W65C51N-specific driver code: {{ component_id }}

; =====================================================================
; TX character time (microseconds) for the W65C51N timed-TX workaround.
;
; The W65C51N has a hardware bug: the TDRE (Transmit Data Register Empty)
; status bit is never set. Polling it would spin forever. Instead, we
; delay for one full character time (10 bits at baud rate) after each
; write to allow the shift register to drain.

_CHAR_TIME_US = 10000000 / {{ baudrate }}

.proc {{ my_def("tx_delay") }}
    DELAY_US _CHAR_TIME_US
    rts
.endproc

{% if irq == "on" %}
    ; =====================================================================
    ; Initialize the UART (IRQ mode).
    ;
    ; Performs a soft reset, clears the ring buffer, configures baud rate
    ; and command register, asserts RTS, and enables CPU interrupts.
    ; The IRQ handler is registered via .interruptor (link-time CONDES table).
    ; Called automatically via .constructor.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("init") }}
        jsr {{ my("soft_reset") }}

        ; Clear ring buffer state.
        lda #0
        sta {{ var("rx_r_ptr") }}
        sta {{ var("rx_w_ptr") }}
        sta {{ var("rx_pending") }}
        sta {{ var("rx_off") }}
        lda STATUS
        sta {{ var("status") }}
{% if rts_pin %}

        ; Assert RTS: active low = ready to receive.
        jsr {{ rts_pin.api("turn_off") }}
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #(CTRL_8BIT | CTRL_1STOP | CTRL_INTCLK | CTRL_BAUD)
        sta CTRL

        ; CMD: no parity, no echo, TX IRQ disabled (/RTS asserted), DTR on.
        ;      RX IRQ enabled.
        lda #(CMD_TIC2 | CMD_DTR)
        sta CMD


        rts
    .endproc
    .constructor {{ my("init") }}

    ; =====================================================================
    ; IRQ handler.
    ;
    ; Called by the core IRQ dispatcher when an interrupt occurs. Reads the
    ; ACIA status register (acknowledges the IRQ), caches it, and dispatches
    ; to the RX handler if this ACIA caused the interrupt.
    ;
    ; Register saving and RTI are handled by the core dispatcher.

    .proc {{ my_def("irq_handler") }}
        lda STATUS
        sta {{ var("status") }}
        and #SR_IRQ
        beq @done

        lda {{ var("status") }}
        jsr {{ my("irq_handler_rx") }}
    @done:
        rts
    .endproc
    .interruptor {{ my("irq_handler") }}

{% endif %}
    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; The W65C51N TDRE bit is broken, so we always report ready.
    ; TX timing is handled by the timed delay in write.
    ;
    ; Out:
    ;   A = 1 (always ready)

    .proc {{ api_def("check_tx") }}
        lda #1
        rts
    .endproc

    ; =====================================================================
    ; Write a byte to the transmitter.
    ;
    ; After writing, delays for one character time to work around the
    ; W65C51N TDRE bug (the shift register must drain before the next write).
    ;
    ; In:
    ;   A = data byte to transmit
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write") }}
        sta DATA
        jsr {{ my("tx_delay") }}
        rts
    .endproc
