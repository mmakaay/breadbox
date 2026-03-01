; UM6551 driver: {{ component_id }}
;
{% if irq == "on" %}
; Mode: IRQ (RX + TX ring buffers, hardware TDRE for TX flow)
{% else %}
; Mode: polling (TDRE poll for TX, RDRF poll for RX)
{% endif %}

{% set P = symbol_prefix %}

{% if irq == "on" %}
    ; CMD register presets for TX IRQ control.
    ;   TX_ACTIVE: TIC1 enables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    ;   TX_IDLE:   TIC2 disables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    {{ constant("CMD_TX_ACTIVE") }} = {{ constant("CMD_TIC1") }} | {{ constant("CMD_DTR") }}
    {{ constant("CMD_TX_IDLE") }}   = {{ constant("CMD_TIC2") }} | {{ constant("CMD_DTR") }}

.segment "KERNALRAM"

    {{ var("rx_buffer") }}: .res $100          ; 256-byte RX ring buffer
    {{ var("tx_buffer") }}: .res $100          ; 256-byte TX ring buffer

.segment "ZEROPAGE" : zeropage

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
        lda {{ constant("STATUS") }}
        sta {{ var("status") }}
{% if pin_rts %}

        ; Assert RTS: active low = ready to receive.
        {{ P }}_PIN_RTS_off
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #({{ constant("CTRL_8BIT") }} | {{ constant("CTRL_1STOP") }} | {{ constant("CTRL_INTCLK") }} | {{ constant("CTRL_BAUD") }})
        sta {{ constant("CTRL") }}

        ; CMD: TX idle (TX IRQ disabled, /RTS asserted), DTR on, RX IRQ on.
        lda #{{ constant("CMD_TX_IDLE") }}
        sta {{ constant("CMD") }}

        ; Enable CPU interrupts. The IRQ handler is registered at link time
        ; via .interruptor and dispatched by the core interruptor table.
        cli

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
        lda {{ constant("STATUS") }}
        sta {{ var("status") }}
        and #{{ constant("SR_IRQ") }}
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
        and #{{ constant("SR_RDRF") }}
        beq @done

        lda {{ constant("DATA") }}
        ldx {{ var("rx_w_ptr") }}
        sta {{ var("rx_buffer") }},X
        inc {{ var("rx_w_ptr") }}
        inc {{ var("rx_pending") }}
{% if pin_rts %}

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
        and #{{ constant("SR_TDRE") }}
        beq @done

        lda {{ var("tx_pending") }}
        beq @tx_stop

        ldx {{ var("tx_r_ptr") }}
        lda {{ var("tx_buffer") }},X
        sta {{ constant("DATA") }}
        inc {{ var("tx_r_ptr") }}
        dec {{ var("tx_pending") }}

        lda {{ var("tx_pending") }}
        bne @done

    @tx_stop:
        lda #{{ constant("CMD_TX_IDLE") }}
        sta {{ constant("CMD") }}

    @done:
        rts
    .endproc
{% if pin_rts %}

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
        {{ P }}_PIN_RTS_on

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
        {{ P }}_PIN_RTS_off
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
{% if pin_rts %}
        pha
{% endif %}
        inc {{ var("rx_r_ptr") }}
        dec {{ var("rx_pending") }}
{% if pin_rts %}

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
        lda #{{ constant("CMD_TX_ACTIVE") }}
        sta {{ constant("CMD") }}

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
{% if pin_rts %}

        ; Assert RTS: active low = ready to receive.
        {{ P }}_PIN_RTS_off
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #({{ constant("CTRL_8BIT") }} | {{ constant("CTRL_1STOP") }} | {{ constant("CTRL_INTCLK") }} | {{ constant("CTRL_BAUD") }})
        sta {{ constant("CTRL") }}

        ; CMD: no parity, no echo, TX IRQ disabled (/RTS asserted), DTR on.
        ;      RX IRQ disabled for polling mode.
        lda #({{ constant("CMD_TIC2") }} | {{ constant("CMD_DTR") }} | {{ constant("CMD_IRQOFF") }})
        sta {{ constant("CMD") }}

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
        lda {{ constant("STATUS") }}
        and #{{ constant("SR_RDRF") }}
        beq @done

        lda {{ constant("DATA") }}
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
        lda {{ constant("STATUS") }}
        and #{{ constant("SR_TDRE") }}
        beq @wait

        pla
        sta {{ constant("DATA") }}
        rts
    .endproc

    ; =====================================================================
    ; Check whether receive data is available.
    ;
    ; Out:
    ;   A = non-zero if data available, zero if not

    .proc {{ api_def("check_rx") }}
        lda {{ constant("STATUS") }}
        and #{{ constant("SR_RDRF") }}
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
        lda {{ constant("STATUS") }}
        and #{{ constant("SR_TDRE") }}
        rts
    .endproc

    ; =====================================================================
    ; Load the ACIA status register.
    ;
    ; Out:
    ;   A = status register contents

    .proc {{ api_def("load_status") }}
        lda {{ constant("STATUS") }}
        rts
    .endproc

{% endif %}
