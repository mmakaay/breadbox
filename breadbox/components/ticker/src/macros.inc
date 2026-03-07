; =========================================================================
; Run a code block when a ticker timer has triggered.
;
; Checks the trigger flag and, if set, clears it and runs the code
; block that follows. The timer keeps running and will trigger again
; after its configured interval.
;
; Prerequisite:
;   The timer must be defined in the project's YAML config.
;
; Usage:
;     IF_TIMER_TRIGGERED TICKER::my_timer
;         ; Handle the timer event.
;     ENDIF
;     ; Execution continues here when the timer has not triggered.

.macro IF_TIMER_TRIGGERED _timer
    lda _timer
    beq @endif
    STORE _timer, #0
.endmacro

; =========================================================================
; Set a deadline for an ad-hoc timer.
;
; Computes a future tick count by adding a delay to the current ticks
; value. Use `ADHOC_TIMER_EXPIRED` to check whether the deadline has
; passed.
;
; Usage:
;     future: .res 3                            ; deadline stored in RAM
;     TIME = 6000                               ; 60s at 10 ms/tick
;     SET_ADHOC_TIMER TICKER::ticks, future, TIME
;   loop:
;     ADHOC_TIMER_EXPIRED TICKER::ticks, future, TIME
;     bcc loop                                  ; loop until deadline passes
;
; In:
;   _ticks    = current counter (3 bytes)
;   _deadline = variable to hold the target tick (3 bytes)
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
; Check whether an ad-hoc timer deadline has passed.
;
; See `SET_ADHOC_TIMER` for a usage example.
;
; In:
;   _ticks    = current counter (3 bytes)
;   _deadline = previously set deadline (3 bytes)
; Out:
;   Carry     = set if expired (ticks >= deadline), clear otherwise
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
; Run a code block when an ad-hoc timer has expired.
;
; Checks whether the deadline has passed. If so, resets the deadline
; and executes the code block that follows. To check expiry without
; automatic reset, use `ADHOC_TIMER_EXPIRED` directly.
;
; Prerequisite:
;   The deadline must have been set with `SET_ADHOC_TIMER`.
;
; Usage:
;     IF_ADHOC_TIMER_EXPIRED TICKER::ticks, future, TIME
;         ; Handle the timer event.
;     ENDIF
;     ; Execution continues here when the timer has not expired.
;
; In:
;   _ticks    = current counter (3 bytes)
;   _deadline = previously set deadline (3 bytes)
;   _delay    = delay as used for `SET_ADHOC_TIMER` (1, 2 or 3 bytes)
; Out:
;   _deadline = reset to a new deadline when expired
;   A         = clobbered

.macro IF_ADHOC_TIMER_EXPIRED _ticks, _deadline, _delay
    ADHOC_TIMER_EXPIRED _ticks, _deadline, _delay
    bcc @endif
    SET_ADHOC_TIMER _ticks, _deadline, _delay
.endmacro
