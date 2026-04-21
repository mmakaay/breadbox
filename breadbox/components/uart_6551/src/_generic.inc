; Generic 6551-specific driver code: {{ component_id }}

{% if irq == "on" %}
    ; CMD register presets for TX IRQ control.
    ;   TX_ACTIVE: TIC1 enables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    ;   TX_IDLE:   TIC2 disables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    CMD_TX_ACTIVE = CMD_TIC1 | CMD_DTR
    CMD_TX_IDLE   = CMD_TIC2 | CMD_DTR

.segment "KERNALRAM"

    {{ var("tx_buffer") }}: .res $100        ; 256-byte TX ring buffer

.segment "ZEROPAGE"

    {{ var("tx_w_ptr") }}:   .res 1          ; TX ring buffer write pointer (main side)
    {{ var("tx_r_ptr") }}:   .res 1          ; TX ring buffer read pointer (IRQ side)
    {{ var("tx_pending") }}: .res 1          ; Number of bytes waiting in TX buffer

.segment "KERNALROM"

    ; =====================================================================
    ; Initialize the UART (IRQ mode).
    ;
    ; Performs a soft reset, clears both ring buffers, configures baud rate
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
        sta {{ var("tx_r_ptr") }}
        sta {{ var("tx_w_ptr") }}
        sta {{ var("tx_pending") }}
        lda STATUS
        sta {{ var("status") }}
{% if rts_pin %}

        ; Assert RTS: active low = ready to receive.
        jsr {{ rts_pin.api("turn_off") }}
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #(CTRL_8BIT | CTRL_1STOP | CTRL_INTCLK | CTRL_BAUD)
        sta CTRL

        ; CMD: TX idle (TX IRQ disabled, /RTS asserted), DTR on, RX IRQ on.
        lda #CMD_TX_IDLE
        sta CMD


        rts
    .endproc
    .constructor {{ my("init") }}

    ; =====================================================================
    ; IRQ handler.
    ;
    ; Called by the core IRQ dispatcher when an interrupt occurs. Reads the
    ; ACIA status register (acknowledges the IRQ), caches it, and dispatches
    ; to the RX and TX handlers if this ACIA caused the interrupt.
    ;
    ; Register saving and RTI are handled by the core dispatcher.

    .proc {{ my_def("irq_handler") }}
        lda STATUS
        sta {{ var("status") }}
        and #SR_IRQ
        beq @done

        lda {{ var("status") }}
        jsr {{ my("irq_handler_rx") }}

        lda {{ var("status") }}
        jsr {{ my("irq_handler_tx") }}

    @done:
        rts
    .endproc
    .interruptor {{ my("irq_handler") }}

    ; =====================================================================
    ; IRQ TX handler.
    ;
    ; If the transmit data register is empty and the TX buffer has data,
    ; sends the next byte. If the TX buffer is empty, switches CMD to
    ; TX_IDLE to disable the TX IRQ.
    ;
    ; In:
    ;   A = status register value (from irq_handler)

    .proc {{ my_def("irq_handler_tx") }}
        and #SR_TDRE
        beq @done

        lda {{ var("tx_pending") }}
        beq @tx_stop

        ldx {{ var("tx_r_ptr") }}
        lda {{ var("tx_buffer") }},x
        sta DATA
        inc {{ var("tx_r_ptr") }}
        dec {{ var("tx_pending") }}

        lda {{ var("tx_pending") }}
        bne @done

    @tx_stop:
        lda #CMD_TX_IDLE
        sta CMD

    @done:
        rts
    .endproc

    ; =====================================================================
    ; Write a byte to the transmit ring buffer (blocking if full).
    ;
    ; Adds the byte to the TX ring buffer. If the buffer was empty, enables
    ; the TX IRQ by switching CMD to TX_ACTIVE. If the buffer is full,
    ; spins until space is available.
    ;
    ; In:
    ;   A = data byte to transmit
    ; Out:
    ;   A, X = clobbered

    .proc {{ api_def("write") }}
        sei
        pha

        lda {{ var("tx_pending") }}
        cmp #$FF
        beq @full

        pla
        ldx {{ var("tx_w_ptr") }}
        sta {{ var("tx_buffer") }},x
        inc {{ var("tx_w_ptr") }}
        inc {{ var("tx_pending") }}

        ; If this is the first byte in the buffer, enable TX IRQ.
        lda {{ var("tx_pending") }}
        cmp #1
        bne @done
        lda #CMD_TX_ACTIVE
        sta CMD

    @done:
        cli
        rts

    @full:
        ; Buffer full — re-enable interrupts, let TX IRQ drain, retry.
        pla
        cli
        nop
        jmp {{ api("write") }}
    .endproc

    ; =====================================================================
    ; Check whether the transmit buffer has space.
    ;
    ; Returns the inverted pending count: non-zero means space available,
    ; zero means the buffer is completely full.
    ;
    ; Out:
    ;   A = inverted tx_pending (non-zero = space available)

    .proc {{ api_def("check_tx") }}
        lda {{ var("tx_pending") }}
        eor #$FF
        rts
    .endproc

{% else %}

    ; =====================================================================
    ; Write a byte to the transmitter.
    ;
    ; Polls the TDRE bit until the transmit data register is empty, then
    ; writes the byte. Unlike the W65C51N, the generic 6551 TDRE works
    ; correctly.
    ;
    ; In:
    ;   A = data byte to transmit
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("write") }}
        pha
    @wait:
        lda STATUS
        and #SR_TDRE
        beq @wait

        pla
        sta DATA
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; Polls the TDRE bit. Unlike the W65C51N, TDRE works correctly on
    ; the generic 6551.
    ;
    ; Out:
    ;   A = non-zero if ready, zero if busy

    .proc {{ api_def("check_tx") }}
        lda STATUS
        and #SR_TDRE
        rts
    .endproc

{% endif %}
