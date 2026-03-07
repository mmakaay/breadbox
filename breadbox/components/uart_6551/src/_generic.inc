; UM6551 driver: {{ component_id }}

{% if irq == "on" %}
; Mode: IRQ (RX + TX ring buffers, hardware TDRE for TX flow)
{% else %}
; Mode: polling (TDRE poll for TX, RDRF poll for RX)
{% endif %}

{% if irq == "on" %}
    ; CMD register presets for TX IRQ control.
    ;   TX_ACTIVE: TIC1 enables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    ;   TX_IDLE:   TIC2 disables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    CMD_TX_ACTIVE = CMD_TIC1 | CMD_DTR
    CMD_TX_IDLE   = CMD_TIC2 | CMD_DTR

.segment "KERNALRAM"

    {{ var("rx_buffer") }}: .res $100        ; 256-byte RX ring buffer
    {{ var("tx_buffer") }}: .res $100        ; 256-byte TX ring buffer

.segment "ZEROPAGE"

    {{ var("rx_w_ptr") }}:   .res 1          ; RX ring buffer write pointer (IRQ side)
    {{ var("rx_r_ptr") }}:   .res 1          ; RX ring buffer read pointer (main side)
    {{ var("rx_pending") }}: .res 1          ; Number of bytes waiting in RX buffer
    {{ var("rx_off") }}:     .res 1          ; RTS deasserted flag (1 = flow stopped)

    {{ var("tx_w_ptr") }}:   .res 1          ; TX ring buffer write pointer (main side)
    {{ var("tx_r_ptr") }}:   .res 1          ; TX ring buffer read pointer (IRQ side)
    {{ var("tx_pending") }}: .res 1          ; Number of bytes waiting in TX buffer

    {{ var("status") }}:     .res 1          ; Cached status register from last IRQ

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
    ; IRQ RX handler.
    ;
    ; If the receive data register is full, reads the byte and stores it
    ; in the ring buffer. Then checks whether to deassert RTS (stop flow)
    ; if the buffer is getting full.
    ;
    ; In:
    ;   A = status register value (from irq_handler)

    .proc {{ my_def("irq_handler_rx") }}
        and #SR_RDRF
        beq @done

        lda DATA
        ldx {{ var("rx_w_ptr") }}
        sta {{ var("rx_buffer") }},X
        inc {{ var("rx_w_ptr") }}
        inc {{ var("rx_pending") }}
{% if rts_pin %}

        jsr {{ my("turn_rx_off_if_buffer_almost_full") }}
{% endif %}

    @done:
        rts
    .endproc

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
        lda {{ var("tx_buffer") }},X
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
{% if rts_pin %}

    ; =====================================================================
    ; Deassert RTS if the receive buffer is almost full (~80%).
    ;
    ; Called from the IRQ handler. When rx_pending reaches $D0 (208 of 256),
    ; sets the RTS pin high (deasserted = stop sending) to prevent overflow.

    .proc {{ my_def("turn_rx_off_if_buffer_almost_full") }}
        lda {{ var("rx_off") }}
        bne @done

        lda {{ var("rx_pending") }}
        cmp #$d0
        bcc @done

        lda #1
        sta {{ var("rx_off") }}
        jsr {{ rts_pin.api("turn_on") }}

    @done:
        rts
    .endproc

    ; =====================================================================
    ; Reassert RTS if the receive buffer is draining (~30%).
    ;
    ; Called from the read proc (main context). When rx_pending drops below
    ; $50 (80 of 256) and RTS was deasserted, reasserts RTS (pin low = ready)
    ; under sei/cli to avoid races with the IRQ handler.

    .proc {{ my_def("turn_rx_on_if_buffer_emptying") }}
        lda {{ var("rx_off") }}
        beq @done

        lda {{ var("rx_pending") }}
        cmp #$50
        bcs @done

        sei
        lda #0
        sta {{ var("rx_off") }}
        jsr {{ rts_pin.api("turn_off") }}
        cli

    @done:
        rts
    .endproc
{% endif %}

    ; =====================================================================
    ; Read a byte from the receive ring buffer (non-blocking).
    ;
    ; If the buffer contains data, reads the next byte, advances the read
    ; pointer, decrements the pending count, and checks whether to reassert
    ; RTS flow control.
    ;
    ; Out:
    ;   C = 1 if byte received, 0 if buffer empty
    ;   A = received data (valid only when C=1)
    ;   X = clobbered

    .proc {{ api_def("read") }}
        clc
        lda {{ var("rx_pending") }}
        beq @done

        ldx {{ var("rx_r_ptr") }}
        lda {{ var("rx_buffer") }},X
{% if rts_pin %}
        pha
{% endif %}
        inc {{ var("rx_r_ptr") }}
        dec {{ var("rx_pending") }}
{% if rts_pin %}

        jsr {{ my("turn_rx_on_if_buffer_emptying") }}
        pla
{% endif %}
        sec

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
        sta {{ var("tx_buffer") }},X
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
    ; Check how many bytes are pending in the receive buffer.
    ;
    ; Out:
    ;   A = number of bytes waiting

    .proc {{ api_def("check_rx") }}
        lda {{ var("rx_pending") }}
        rts
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

    ; =====================================================================
    ; Load the cached ACIA status register.
    ;
    ; In IRQ mode the status register is read by the IRQ handler and
    ; cached in a ZP variable to avoid side effects from re-reading.
    ;
    ; Out:
    ;   A = cached status register contents

    .proc {{ api_def("load_status") }}
        lda {{ var("status") }}
        rts
    .endproc

{% else %}
.segment "KERNALROM"

    ; =====================================================================
    ; Initialize the UART (polling mode).
    ;
    ; Performs a soft reset, configures baud rate and command register,
    ; and asserts the RTS flow control pin (if present).
    ; Called automatically via .constructor.
    ;
    ; Out:
    ;   A = clobbered

    .proc {{ api_def("init") }}
        jsr {{ my("soft_reset") }}
{% if rts_pin %}

        ; Assert RTS: active low = ready to receive.
        jsr {{ rts_pin.api("turn_off") }}
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #(CTRL_8BIT | CTRL_1STOP | CTRL_INTCLK | CTRL_BAUD)
        sta CTRL

        ; CMD: no parity, no echo, TX IRQ disabled (/RTS asserted), DTR on.
        ;      RX IRQ disabled for polling mode.
        lda #(CMD_TIC2 | CMD_DTR | CMD_IRQOFF)
        sta CMD

        rts
    .endproc
    .constructor {{ my("init") }}

    ; =====================================================================
    ; Read a byte from the receiver (non-blocking).
    ;
    ; Checks the RDRF status bit. If a byte is waiting, reads it and
    ; returns with carry set. Otherwise returns with carry clear.
    ;
    ; Out:
    ;   C = 1 if byte received, 0 if buffer empty
    ;   A = received data (valid only when C=1)

    .proc {{ api_def("read") }}
        clc
        lda STATUS
        and #SR_RDRF
        beq @done

        lda DATA
        sec
    @done:
        rts
    .endproc

    ; =====================================================================
    ; Write a byte to the transmitter.
    ;
    ; Polls the TDRE bit until the transmit data register is empty, then
    ; writes the byte. Unlike the W65C51N, the UM6551 TDRE works correctly.
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
    ; Check whether receive data is available.
    ;
    ; Out:
    ;   A = non-zero if data available, zero if not

    .proc {{ api_def("check_rx") }}
        lda STATUS
        and #SR_RDRF
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; Polls the TDRE bit. Unlike the W65C51N, TDRE works correctly on
    ; the UM6551.
    ;
    ; Out:
    ;   A = non-zero if ready, zero if busy

    .proc {{ api_def("check_tx") }}
        lda STATUS
        and #SR_TDRE
        rts
    .endproc

    ; =====================================================================
    ; Load the ACIA status register.
    ;
    ; Out:
    ;   A = status register contents

    .proc {{ api_def("load_status") }}
        lda STATUS
        rts
    .endproc

{% endif %}
