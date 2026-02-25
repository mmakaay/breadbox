; UM6551 driver: {{ device_id }}
;
{% if irq == "on" %}
; Mode: IRQ (RX + TX ring buffers, hardware TDRE for TX flow)
{% else %}
; Mode: polling (TDRE poll for TX, RDRF poll for RX)
{% endif %}

{% set P = macro_prefix %}

{% if irq == "on" %}
    ; CMD register presets for TX IRQ control.
    ;   TX_ACTIVE: TIC1 enables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    ;   TX_IDLE:   TIC2 disables TX IRQ, /RTS asserted, DTR on, RX IRQ on.
    {{ P }}_CMD_TX_ACTIVE = {{ P }}_CMD_TIC1 | {{ P }}_CMD_DTR
    {{ P }}_CMD_TX_IDLE   = {{ P }}_CMD_TIC2 | {{ P }}_CMD_DTR

.segment "RAM"

    {{ P }}_rx_buffer: .res $100          ; 256-byte RX ring buffer
    {{ P }}_tx_buffer: .res $100          ; 256-byte TX ring buffer

.segment "ZEROPAGE"

    {{ P }}_rx_w_ptr:   .res 1          ; RX ring buffer write pointer (IRQ side)
    {{ P }}_rx_r_ptr:   .res 1          ; RX ring buffer read pointer (main side)
    {{ P }}_rx_pending: .res 1          ; Number of bytes waiting in RX buffer
    {{ P }}_rx_off:     .res 1          ; RTS deasserted flag (1 = flow stopped)

    {{ P }}_tx_w_ptr:   .res 1          ; TX ring buffer write pointer (main side)
    {{ P }}_tx_r_ptr:   .res 1          ; TX ring buffer read pointer (IRQ side)
    {{ P }}_tx_pending: .res 1          ; Number of bytes waiting in TX buffer

    {{ P }}_status:     .res 1          ; Cached status register from last IRQ

.segment "KERNAL"

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

    .proc _{{ P }}_init
        jsr _{{ P }}_soft_reset

        ; Clear ring buffer state.
        lda #0
        sta {{ P }}_rx_r_ptr
        sta {{ P }}_rx_w_ptr
        sta {{ P }}_rx_pending
        sta {{ P }}_rx_off
        sta {{ P }}_tx_r_ptr
        sta {{ P }}_tx_w_ptr
        sta {{ P }}_tx_pending
        lda {{ P }}_STATUS
        sta {{ P }}_status
{% if pin_rts %}

        ; Assert RTS: active low = ready to receive.
        {{ P }}_PIN_RTS_off
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #({{ P }}_CTRL_8BIT | {{ P }}_CTRL_1STOP | {{ P }}_CTRL_INTCLK | {{ P }}_CTRL_BAUD)
        sta {{ P }}_CTRL

        ; CMD: TX idle (TX IRQ disabled, /RTS asserted), DTR on, RX IRQ on.
        lda #{{ P }}_CMD_TX_IDLE
        sta {{ P }}_CMD

        ; Enable CPU interrupts. The IRQ handler is registered at link time
        ; via .interruptor and dispatched by the core interruptor table.
        cli

        rts
    .endproc
    .constructor _{{ P }}_init

    ; =====================================================================
    ; IRQ handler.
    ;
    ; Called by the core IRQ dispatcher when an interrupt occurs. Reads the
    ; ACIA status register (acknowledges the IRQ), caches it, and dispatches
    ; to the RX and TX handlers if this ACIA caused the interrupt.
    ;
    ; Register saving and RTI are handled by the core dispatcher.

    .proc _{{ P }}_irq_handler
        lda {{ P }}_STATUS
        sta {{ P }}_status
        and #{{ P }}_SR_IRQ
        beq @done

        lda {{ P }}_status
        jsr _{{ P }}_irq_handler_rx

        lda {{ P }}_status
        jsr _{{ P }}_irq_handler_tx

    @done:
        rts
    .endproc
    .interruptor _{{ P }}_irq_handler

    ; =====================================================================
    ; IRQ RX handler.
    ;
    ; If the receive data register is full, reads the byte and stores it
    ; in the ring buffer. Then checks whether to deassert RTS (stop flow)
    ; if the buffer is getting full.
    ;
    ; In:
    ;   A = status register value (from irq_handler)

    .proc _{{ P }}_irq_handler_rx
        and #{{ P }}_SR_RDRF
        beq @done

        lda {{ P }}_DATA
        ldx {{ P }}_rx_w_ptr
        sta {{ P }}_rx_buffer,X
        inc {{ P }}_rx_w_ptr
        inc {{ P }}_rx_pending
{% if pin_rts %}

        jsr _{{ P }}_turn_rx_off_if_buffer_almost_full
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

    .proc _{{ P }}_irq_handler_tx
        and #{{ P }}_SR_TDRE
        beq @done

        lda {{ P }}_tx_pending
        beq @tx_stop

        ldx {{ P }}_tx_r_ptr
        lda {{ P }}_tx_buffer,X
        sta {{ P }}_DATA
        inc {{ P }}_tx_r_ptr
        dec {{ P }}_tx_pending

        lda {{ P }}_tx_pending
        bne @done

    @tx_stop:
        lda #{{ P }}_CMD_TX_IDLE
        sta {{ P }}_CMD

    @done:
        rts
    .endproc
{% if pin_rts %}

    ; =====================================================================
    ; Deassert RTS if the receive buffer is almost full (~80%).
    ;
    ; Called from the IRQ handler. When rx_pending reaches $D0 (208 of 256),
    ; sets the RTS pin high (deasserted = stop sending) to prevent overflow.

    .proc _{{ P }}_turn_rx_off_if_buffer_almost_full
        lda {{ P }}_rx_off
        bne @done

        lda {{ P }}_rx_pending
        cmp #$d0
        bcc @done

        lda #1
        sta {{ P }}_rx_off
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

    .proc _{{ P }}_turn_rx_on_if_buffer_emptying
        lda {{ P }}_rx_off
        beq @done

        lda {{ P }}_rx_pending
        cmp #$50
        bcs @done

        sei
        lda #0
        sta {{ P }}_rx_off
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
    ;   byte = received data (valid only when C=1)
    ;   A, X = clobbered

    .proc _{{ P }}_read
        clc
        lda {{ P }}_rx_pending
        beq @done

        ldx {{ P }}_rx_r_ptr
        lda {{ P }}_rx_buffer,X
        sta {{ P }}_byte
        inc {{ P }}_rx_r_ptr
        dec {{ P }}_rx_pending
{% if pin_rts %}

        jsr _{{ P }}_turn_rx_on_if_buffer_emptying
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
    ; In (zero page):
    ;   byte = data byte to transmit
    ; Out:
    ;   A, X = clobbered

    .proc _{{ P }}_write
        sei

        lda {{ P }}_tx_pending
        cmp #$FF
        beq @full

        lda {{ P }}_byte
        ldx {{ P }}_tx_w_ptr
        sta {{ P }}_tx_buffer,X
        inc {{ P }}_tx_w_ptr
        inc {{ P }}_tx_pending

        ; If this is the first byte in the buffer, enable TX IRQ.
        lda {{ P }}_tx_pending
        cmp #1
        bne @done
        lda #{{ P }}_CMD_TX_ACTIVE
        sta {{ P }}_CMD

    @done:
        cli
        rts

    @full:
        ; Buffer full — re-enable interrupts, let TX IRQ drain, retry.
        cli
        nop
        jmp _{{ P }}_write
    .endproc

    ; =====================================================================
    ; Check how many bytes are pending in the receive buffer.
    ;
    ; Out:
    ;   byte = number of bytes waiting
    ;   A = clobbered

    .proc _{{ P }}_check_rx
        lda {{ P }}_rx_pending
        sta {{ P }}_byte
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmit buffer has space.
    ;
    ; Returns the inverted pending count: non-zero means space available,
    ; zero means the buffer is completely full.
    ;
    ; Out:
    ;   byte = inverted tx_pending (non-zero = space available)
    ;   A = clobbered

    .proc _{{ P }}_check_tx
        lda {{ P }}_tx_pending
        eor #$FF
        sta {{ P }}_byte
        rts
    .endproc

    ; =====================================================================
    ; Load the cached ACIA status register into the byte variable.
    ;
    ; In IRQ mode the status register is read by the IRQ handler and
    ; cached in a ZP variable to avoid side effects from re-reading.
    ;
    ; Out:
    ;   byte = cached status register contents
    ;   A = clobbered

    .proc _{{ P }}_load_status
        lda {{ P }}_status
        sta {{ P }}_byte
        rts
    .endproc

{% else %}
.segment "KERNAL"

    ; =====================================================================
    ; Initialize the UART (polling mode).
    ;
    ; Performs a soft reset, configures baud rate and command register,
    ; and asserts the RTS flow control pin (if present).
    ; Called automatically via .constructor.
    ;
    ; Out:
    ;   A = clobbered

    .proc _{{ P }}_init
        jsr _{{ P }}_soft_reset
{% if pin_rts %}

        ; Assert RTS: active low = ready to receive.
        {{ P }}_PIN_RTS_off
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #({{ P }}_CTRL_8BIT | {{ P }}_CTRL_1STOP | {{ P }}_CTRL_INTCLK | {{ P }}_CTRL_BAUD)
        sta {{ P }}_CTRL

        ; CMD: no parity, no echo, TX IRQ disabled (/RTS asserted), DTR on.
        ;      RX IRQ disabled for polling mode.
        lda #({{ P }}_CMD_TIC2 | {{ P }}_CMD_DTR | {{ P }}_CMD_IRQOFF)
        sta {{ P }}_CMD

        rts
    .endproc
    .constructor _{{ P }}_init

    ; =====================================================================
    ; Read a byte from the receiver (non-blocking).
    ;
    ; Checks the RDRF status bit. If a byte is waiting, reads it into
    ; the byte variable and returns with carry set. Otherwise returns
    ; with carry clear.
    ;
    ; Out:
    ;   C = 1 if byte received, 0 if buffer empty
    ;   byte = received data (valid only when C=1)
    ;   A = clobbered

    .proc _{{ P }}_read
        clc
        lda {{ P }}_STATUS
        and #{{ P }}_SR_RDRF
        beq @done

        lda {{ P }}_DATA
        sta {{ P }}_byte
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
    ; In (zero page):
    ;   byte = data byte to transmit
    ; Out:
    ;   A = clobbered

    .proc _{{ P }}_write
    @wait:
        lda {{ P }}_STATUS
        and #{{ P }}_SR_TDRE
        beq @wait

        lda {{ P }}_byte
        sta {{ P }}_DATA
        rts
    .endproc

    ; =====================================================================
    ; Check whether receive data is available.
    ;
    ; Out:
    ;   byte = non-zero if data available, zero if not
    ;   A = clobbered

    .proc _{{ P }}_check_rx
        lda {{ P }}_STATUS
        and #{{ P }}_SR_RDRF
        sta {{ P }}_byte
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; Polls the TDRE bit. Unlike the W65C51N, TDRE works correctly on
    ; the UM6551.
    ;
    ; Out:
    ;   byte = non-zero if ready, zero if busy
    ;   A = clobbered

    .proc _{{ P }}_check_tx
        lda {{ P }}_STATUS
        and #{{ P }}_SR_TDRE
        sta {{ P }}_byte
        rts
    .endproc

    ; =====================================================================
    ; Load the ACIA status register into the byte variable.
    ;
    ; Out:
    ;   byte = status register contents
    ;   A = clobbered

    .proc _{{ P }}_load_status
        lda {{ P }}_STATUS
        sta {{ P }}_byte
        rts
    .endproc

{% endif %}
