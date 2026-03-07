# Ben Eater tutorial: How do hardware timers work?

Tutorial : https://www.youtube.com/watch?v=g_koa00MBLg \
Result   : https://youtu.be/g_koa00MBLg?t=1822

The code from `main.s` implements the final result from the tutorial, using
BREADBOX for handling the hardware interaction and timer logic.

## Blinking LED using simple delay loops

The tutorial also shows a blinking LED implementation, that uses delay loops to get the timing right. For completion’s sake, here is
what this code could look like, using BREADBOX:

```6502 assembly
.include "breadbox.inc"

.export main

.proc main
    LED::turn_on
    jsr delay
    LED::turn_off
    jsr delay
    jmp main
.endproc

.proc delay
    ldy #$ff
@delay2:
    ldx $#ff
@delay1:
    nop
    dex
    bne @delay1
    dey
    bne @delay2
    rts
.endproc
```

If I computed things correctly, this delay loop takes 457ms when running at a 1MHz clock speed.
Yet another way to implement this, is to make use of the delay functionality (based on the same
principle of a busy loop on the CPU) as provided by BREADBOX:

```6502 assembly
.include "breadbox.inc"

.export main

.proc main
    LED::turn_on
    DELAY_MS 200
    DELAY_MS 257
    LED::turn_off
    DELAY_MS 200
    DELAY_MS 257
    jmp main
.endproc
```

The delay is split up into two separate delay calls. The delay as implemented in BREADBOX,
uses fewer cycles per iteration than Ben's delay loop. This provides a higher resolution for
timing, at the cost of a lower maximum delay time (max 327ms when running at 1MHz).
Therefore, to get to 457ms, two delay calls have to be used here.
