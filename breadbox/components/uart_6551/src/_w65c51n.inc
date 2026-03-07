; W65C51N driver: {{ component_id }}

{% if irq == "on" %}
; Mode: IRQ (RX ring buffer, timed TX delay for TDRE bug workaround)
{% else %}
; Mode: polling (timed TX delay for TDRE bug workaround)
{% endif %}

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
.segment "KERNALRAM"

    {{ var("rx_buffer") }}: .res $100  ; 256-byte RX ring buffer

.segment "ZEROPAGE"

    {{ var("rx_w_ptr") }}:   .res 1    ; Ring buffer write pointer (IRQ side)
    {{ var("rx_r_ptr") }}:   .res 1    ; Ring buffer read pointer (main side)
    {{ var("rx_pending") }}: .res 1    ; Number of bytes waiting in buffer
    {{ var("rx_off") }}:     .res 1    ; RTS deasserted flag (1 = flow stopped)
    {{ var("status") }}:     .res 1    ; Cached status register from last IRQ

.segment "KERNALROM"

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
    ; Check how many bytes are pending in the receive buffer.
    ;
    ; Out:
    ;   A = number of bytes waiting

    .proc {{ api_def("check_rx") }}
        lda {{ var("rx_pending") }}
        rts
    .endproc

    ; =====================================================================
    ; Check whether the transmitter is ready.
    ;
    ; For the W65C51N IRQ driver, TX is always timed (no hardware TDRE),
    ; so we always report ready.
    ;
    ; Out:
    ;   A = 1 (always ready)

    .proc {{ api_def("check_tx") }}
        lda #1
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
    ; Load the ACIA status register.
    ;
    ; Out:
    ;   A = status register contents

    .proc {{ api_def("load_status") }}
        lda STATUS
        rts
    .endproc

{% endif %}
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
