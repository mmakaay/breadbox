; From: Interrupt handling
; ------------------------
;
; Tutorial : https://www.youtube.com/watch?v=oOYA-jsWTmc
; Result   : https://www.youtube.com/watch?v=oOYA-jsWTmc&t=1276
;
; I implemented the debounce countdown different from how Ben did it in
; the video. I moved the debounce countdown outside the interrupt subroutine,
; but have it set and checked from inside the interrupt subroutine. This has
; some advantages over handling the full countdown in the IRQ handler:
;
; - As was mentioned in the video, having the countdown in the handler
;   makes the button presses feel laggy, because the LCD display is only
;   updated after the debounce has completed. In my implementation, the
;   IRQ handler quickly returns after starting the debounce countdown,
;   allowing for immediate feedback to the user, while the deboucing is
;   running in the background.
;
; - Starting the debounce countdown can also be seen as a signal that
;   the interrupt counter value has changed. Only when a new countdown
;   is started, the LCD display is updated with the new value. This
;   saves a lot of resources, compared to continuously updating the LCD,
;   even when there is no new counter value to display.

.include "breadbox.inc"
.include "stdlib/io/print.inc"
.include "stdlib/math/fmtdec16.inc"
.include "VIA/constants.inc"

.export main
.interruptor handle_irq   ; Registers the subroutine as IRQ handler with BREADBOX

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
        ldx #0
        ldy #1
        jsr LCD::cursor_move
        PRINT LCD::write, banner

        ; Initialize the variables to zero.
        CLR_WORD counter
        CLR_WORD debounce

        ; Activate interrupts for falling edge input on VIA's CA1 port.
        jsr activate_ca1_interrupts

    @wait_for_change:
        ; Wait until the counter value has changed. We know the counter value
        ; has changed, when a debounce countdown has been activated.
        lda debounce                 ; Check if debounce counter is 0.
        ora debounce + 1
        beq @wait_for_change         ; It is, wait some more.

        ; Count value updated! let's write it to the display.
        CP_WORD fmtdec16::value, counter
        jsr fmtdec16
        jsr LCD::home
        PRINT LCD::write, fmtdec16::decimal

        ; Show debounce marker.
        ldy #0
        ldx #8
        jsr LCD::cursor_move
        PRINT LCD::write, debounce_on

        ; Run the debounce countdown.
    @debounce_countdown:
        lda debounce                 ; Check if debounce counter is 0.
        ora debounce + 1
        beq @debounce_done           ; Yes, go wait for the next change.
        DEC_WORD debounce            ; No, decrement the debounce counter,
        jmp @debounce_countdown      ; and debounce a bit longer.

    @debounce_done:
        ldy #0
        ldx #8
        jsr LCD::cursor_move
        PRINT LCD::write, debounce_off
        jmp @wait_for_change

    .endproc

    .proc handle_irq
        lda debounce                 ; When debounce is active, ignore the IRQ.
        ora debounce + 1
        bne @done

        SET_WORD debounce, $2000     ; Enable debounce countdown.
        INC_WORD counter             ; Increment the interrupt counter.

    @done:
        bit $6001                    ; Read PORTA to clear interrupt.
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
        SET_BYTE IER, #(IER_TURN_ON | IER_CA1) ; Turn on CA1 interrupts
        cli                  ; Enable interrupts
        rts
    .endproc
