; W65C51N driver: {{ device_id }}
;
{% if irq == "on" %}
; Mode: IRQ (RX ring buffer, timed TX delay for TDRE bug workaround)
{% else %}
; Mode: polling (timed TX delay for TDRE bug workaround)
{% endif %}

{% set P = macro_prefix %}

    ; =====================================================================
    ; TX character time (microseconds) for the W65C51N timed-TX workaround.
    ;
    ; The W65C51N has a hardware bug: the TDRE (Transmit Data Register Empty)
    ; status bit is never set. Polling it would spin forever. Instead, we
    ; delay for one full character time (10 bits at baud rate) after each
    ; write to allow the shift register to drain.

    _CHAR_TIME_US = 10000000 / {{ baudrate }}

    .proc {{ symbol("tx_delay") }}
        DELAY_US _CHAR_TIME_US
        rts
    .endproc

{% if irq == "on" %}
.segment "RAM"

    {{ symbol("rx_buffer") }}: .res $100  ; 256-byte RX ring buffer

.segment "ZEROPAGE"

    {{ symbol("rx_w_ptr") }}:   .res 1    ; Ring buffer write pointer (IRQ side)
    {{ symbol("rx_r_ptr") }}:   .res 1    ; Ring buffer read pointer (main side)
    {{ symbol("rx_pending") }}: .res 1    ; Number of bytes waiting in buffer
    {{ symbol("rx_off") }}:     .res 1    ; RTS deasserted flag (1 = flow stopped)
    {{ symbol("status") }}:     .res 1    ; Cached status register from last IRQ

.segment "KERNAL"

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

    .proc {{ symbol("init") }}
        jsr {{ symbol("soft_reset") }}

        ; Clear ring buffer state.
        lda #0
        sta {{ symbol("rx_r_ptr") }}
        sta {{ symbol("rx_w_ptr") }}
        sta {{ symbol("rx_pending") }}
        sta {{ symbol("rx_off") }}
        lda {{ symbol("STATUS") }}
        sta {{ symbol("status") }}
{% if pin_rts %}

        ; Assert RTS: active low = ready to receive.
        {{ P }}_PIN_RTS_off
{% endif %}

        ; CTRL: 8N1, internal baud rate generator.
        lda #({{ P }}_CTRL_8BIT | {{ P }}_CTRL_1STOP | {{ P }}_CTRL_INTCLK | {{ P }}_CTRL_BAUD)
        sta {{ P }}_CTRL

        ; CMD: no parity, no echo, TX IRQ disabled (/RTS asserted), DTR on.
        ;      RX IRQ enabled.
        lda #({{ P }}_CMD_TIC2 | {{ P }}_CMD_DTR)
        sta {{ P }}_CMD

        ; Enable CPU interrupts. The IRQ handler is registered at link time
        ; via .interruptor and dispatched by the core interruptor table.
        cli

        rts
    .endproc
    .constructor {{ symbol("init") }}

    ; =====================================================================
    ; IRQ handler.
    ;
    ; Called by the core IRQ dispatcher when an interrupt occurs. Reads the
    ; ACIA status register (acknowledges the IRQ), caches it, and dispatches
    ; to the RX handler if this ACIA caused the interrupt.
    ;
    ; Register saving and RTI are handled by the core dispatcher.

    .proc {{ symbol("irq_handler") }}
        lda {{ P }}_STATUS
        sta {{ P }}_status
        and #{{ P }}_SR_IRQ
        beq @done
        lda {{ P }}_status
        jsr {{ symbol("irq_handler_rx") }}
    @done:
        rts
    .endproc
    .interruptor {{ symbol("irq_handler") }}

    ; =====================================================================
    ; IRQ RX handler.
    ;
    ; If the receive data register is full, reads the byte and stores it
    ; in the ring buffer. Then checks whether to deassert RTS (stop flow)
    ; if the buffer is getting full.
    ;
    ; In:
    ;   A = status register value (from irq_handler)

    .proc {{ symbol("irq_handler_rx") }}
        and #{{ P }}_SR_RDRF
        beq @done

        lda {{ P }}_DATA
        ldx {{ symbol("rx_w_ptr") }}
        sta {{ symbol("rx_buffer,X") }}
        inc {{ symbol("rx_w_ptr") }}
        inc {{ symbol("rx_pending") }}
{% if pin_rts %}

        jsr {{ symbol("turn_rx_off_if_buffer_almost_full") }}
{% endif %}

    @done:
        rts
    .endproc
{% if pin_rts %}

    ; =====================================================================
    ; Deassert RTS if the receive buffer is almost full (~80%).
    ;
    ; Called from the IRQ handler. When rx_pending reaches $D0 (208 of 256),
    ; sets the RTS pin high (deasserted = stop sending) to prevent overflow.

    .proc {{ symbol("turn_rx_off_if_buffer_almost_full") }}
        lda {{ symbol("rx_off") }}
        bne @done

        lda {{ symbol("rx_pending") }}
        cmp #$d0
        bcc @done

        lda #1
        sta {{ symbol("rx_off") }}
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

    .proc {{ symbol("turn_rx_on_if_buffer_emptying") }}
        lda {{ symbol("rx_off") }}
        beq @done

        lda {{ symbol("rx_pending") }}
        cmp #$50
        bcs @done

        sei
        lda #0
        sta {{ symbol("rx_off") }}
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

    .proc {{ symbol("read") }}
        clc
        lda {{ symbol("rx_pending") }}
        beq @done

        ldx {{ symbol("rx_r_ptr") }}
        lda {{ symbol("rx_buffer,X") }}
        sta {{ symbol("byte") }}
        inc {{ symbol("rx_r_ptr") }}
        dec {{ symbol("rx_pending") }}
{% if pin_rts %}

        jsr {{ symbol("turn_rx_on_if_buffer_emptying") }}
{% endif %}
        sec

    @done:
        rts
    .endproc

    ; =====================================================================
    ; Check how many bytes are pending in the receive buffer.
    ;
    ; Out:
    ;   byte = number of bytes waiting
    ;   A = clobbered

    .proc {{ symbol("check_rx") }}
        lda {{ symbol("rx_pending") }}
        sta {{ symbol("byte") }}
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; For the W65C51N IRQ driver, TX is always timed (no hardware TDRE),
    ; so we always report ready.
    ;
    ; Out:
    ;   byte = 1 (always ready)
    ;   A = clobbered

    .proc {{ symbol("check_tx") }}
        lda #1
        sta {{ symbol("byte") }}
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

    .proc {{ symbol("load_status") }}
        lda {{ symbol("status") }}
        sta {{ symbol("byte") }}
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

    .proc {{ symbol("init") }}
        jsr {{ symbol("soft_reset") }}
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
    .constructor {{ symbol("init") }}

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

    .proc {{ symbol("read") }}
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
    ; Check whether receive data is available.
    ;
    ; Out:
    ;   byte = non-zero if data available, zero if not
    ;   A = clobbered

    .proc {{ symbol("check_rx") }}
        lda {{ P }}_STATUS
        and #{{ P }}_SR_RDRF
        sta {{ symbol("byte") }}
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; The W65C51N TDRE bit is broken, so we always report ready.
    ; TX timing is handled by the timed delay in _write.
    ;
    ; Out:
    ;   byte = 1 (always ready)
    ;   A = clobbered

    .proc {{ symbol("check_tx") }}
        lda #1
        sta {{ symbol("byte") }}
        rts
    .endproc

    ; =====================================================================
    ; Load the ACIA status register into the byte variable.
    ;
    ; Out:
    ;   byte = status register contents
    ;   A = clobbered

    .proc {{ symbol("load_status") }}
        lda {{ P }}_STATUS
        sta {{ symbol("byte") }}
        rts
    .endproc

{% endif %}
    ; =====================================================================
    ; Write a byte to the transmitter.
    ;
    ; After writing, delays for one character time to work around the
    ; W65C51N TDRE bug (the shift register must drain before the next write).
    ;
    ; In (zero page):
    ;   byte = data byte to transmit
    ; Out:
    ;   A = clobbered

    .proc {{ symbol("write") }}
        lda {{ symbol("byte") }}
        sta {{ P }}_DATA
        jsr {{ symbol("tx_delay") }}
        rts
    .endproc
