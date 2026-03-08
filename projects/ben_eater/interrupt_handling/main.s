.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec16.inc"
.include "VIA/constants.inc"

.export main
.interruptor handle_irq   ; Register subroutine in BREADBOX as IRQ handler

.segment "RAM"

    counter:      .word 0
    debounce:     .word 0

.segment "DATA"

    banner:        .asciiz "BREADBOX IRQtest"
    debounce_on:   .asciiz "debounce"
    debounce_off:  .asciiz "        "

.segment "CODE"

    .proc main
        ; Write the banner to the second line of the display.
        ldx #1
        ldy #0
        jsr LCD::move_cursor
        PRINT LCD::write, banner

        ; Initialize the variables to zero.
        ZERO16 counter
        ZERO16 debounce

        ; Write the initial counter value to the display.
        jsr write_counter_to_display

        ; Activate interrupts for falling edge input on VIA's CA1 port.
        jsr activate_ca1_interrupts

    @wait_for_change:
        ; Wait until the counter value has changed. We know the counter value
        ; has changed, when a debounce countdown has been activated.
        lda debounce                 ; Check if debounce counter is 0.
        ora debounce + 1
        beq @wait_for_change         ; It is, wait some more.

        ; Count value updated! let's write it to the display.
        jsr write_counter_to_display

        ; Show debounce marker.
        ldy #8
        ldx #0
        jsr LCD::move_cursor
        sei
        PRINT LCD::write, debounce_on
        cli

        ; Run the debounce countdown.
    @debounce_countdown:
        sei
        lda debounce                 ; Check if debounce counter is 0.
        ora debounce + 1
        beq @debounce_done           ; Yes, go wait for the next change.
        DEC16 debounce            ; No, decrement the debounce counter,
        cli
        jmp @debounce_countdown      ; and debounce a bit longer.

    @debounce_done:
        ldy #8
        ldx #0
        jsr LCD::move_cursor
        sei
        PRINT LCD::write, debounce_off
        cli
        jmp @wait_for_change

    .endproc

    .proc handle_irq
        lda debounce                 ; When debounce is active, ignore the IRQ.
        ora debounce + 1
        bne @done

        STORE16 debounce, $2000     ; Enable debounce countdown.
        INC16 counter             ; Increment the interrupt counter.

    @done:
        bit $6001                    ; Read PORTA to clear interrupt.
        rts
    .endproc

    .proc write_counter_to_display
        sei
        COPY16 fmtdec16::value, counter
        jsr fmtdec16
        jsr LCD::home
        PRINT LCD::write, fmtdec16::padded
        cli
        rts
    .endproc

    .proc activate_ca1_interrupts
        ; At the time of writing, there is no abstraction layer for this yet,
        ; so here we address the VIA directly to setup the IRQ pin. We could
        ; just write #0 to PCR, since this is the only code that configures
        ; PCR here, but let's be good citizens and do it cleanly.
        lda PCR              ; Get existing configuration
        and PCR_CA1_MASK     ; Clear the CA1 settings bit
        ora #PCR_CA1_NAE     ; Configure Negative Action Edge (i.e. falling edge)
        sta PCR              ; Write back new configuration
        STORE IER, #(IER_TURN_ON | IER_CA1) ; Turn on CA1 interrupts
        cli                  ; Enable interrupts
        rts
    .endproc
