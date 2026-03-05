; =========================================================================
; Check if a ticker timer was triggered, and jump to provided label if not.
;
; Prerequisite:
;   The timer to check must have been created in the YAML config.
;
; Usage:
;     IF_NOT_TIMER_TRIGGERED TICKER::my_timer, done
;     ; Perform actions for triggered timer.
;     ; The macro resets the trigger, so the timer will
;     ; automatically re-trigger after this.
;   done:
;     ; ...
;

.macro IF_NOT_TIMER_TRIGGERED _timer, _branch_to
    lda TICKER::lcd_update
    beq _branch_to
    STORE TICKER::lcd_update, #0
.endmacro

; =========================================================================
; Set an ad-hoc timer deadline.
;
; This can be used to implement an ad-hoc timer, using a ticks counter.
; After setting a deadline, the `TIMER_EXPIRED` macro can be used to
; check if the timer deadline has been reached.
;
; Usage:
;     future: .res 3                            ; deadline is stored in RAM
;     TIME = 6000                               ; 60x when using 10ms / tick
;     TIMER_SET TICKER::ticks, future, TIME     ; store deadline in `future`
;   loop:
;     TIMER_EXPIRED TICKER::ticks, future, TIME ; same arguments as before
;     bcc loop                                  ; Loop until `future` is reached
;
; In:
;   _ticks    = current counter (3 bytes)
;   _deadline = variable to hold target tick (3 bytes)
;   _delay    = number of ticks to wait (1, 2 or 3 bytes)
; Out:
;   A         = clobbered

.macro SET_ADHOC_TIMER _ticks, _deadline, _delay
    lda _ticks
    clc
    adc #<(_delay)
    sta _deadline

    lda _ticks+1
    adc #>(_delay)
    sta _deadline+1

    lda _ticks+2
    adc #^(_delay)
    sta _deadline+2
.endmacro

; -----------------------------------------------------------------------------
; Check if an ad-hoc timer deadline has been reached.
;
; See the `TIMER_SET` documentation for a usage example.
;
; In:
;   _ticks    = current counter (3 bytes)
;   _deadline = previously set deadline (3 bytes)
;   _delay    = delay as used for TIMER_SET (1, 2 or 3 bytes)
; Out:
;   Carry     = 1 if timer expired (ticks >= deadline), 0 otherwise
;   A         = clobbered

.macro ADHOC_TIMER_EXPIRED _ticks, _deadline, _delay
    sec
    lda _ticks
    sbc _deadline

    lda _ticks+1
    sbc _deadline+1

    lda _ticks+2
    sbc _deadline+2
.endmacro

; =========================================================================
; Check if an ad-hoc timer has expired, and reset the timer + run code
; block if it is.
;
; Prerequisite:
;   The ad-hoc timer must have been initialized using `SET_ADHOC_TIMER`.
;
; Usage:
;     IF_ADHOC_TIMER_EXPIRED TICKER::ticks, future, TIME
;         ; Perform actions for expired timer.
;         ; The macro resets the  the adhoc timer, so the timer will
;         ; automatically re-trigger after this. If you do not want this
;         ; reset behavior, then use `ADHOC_TIMER_EXPIRED` directly instead.
;     ENDIF
;         ; Code jumps here, if timer has not expired.
;
; In:
;   _ticks    = current counter (3 bytes)
;   _deadline = previously set deadline (3 bytes)
;   _delay    = delay as used for TIMER_SET (1, 2 or 3 bytes)
; Out:
;   Carry     = 1 if timer expired (ticks >= deadline), 0 otherwise
;   _deadline = Reset if timer expired
;   A         = clobbered

.macro IF_ADHOC_TIMER_EXPIRED _ticks, _deadline, _delay
    ADHOC_TIMER_EXPIRED _ticks, _deadline, _delay
    bcc @endif
    SET_ADHOC_TIMER _ticks, _deadline, _delay
.endmacro

.macro ENDIF
    @endif:
.endmacro
