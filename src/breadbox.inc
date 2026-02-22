.ifndef BREADBOX_INC
BREADBOX_INC = 1

; Generatd code.
.include "generated/hardware.inc"

; Include all macros. These only have compile-time effect, so it is
; safe to simply include them all in here, allowing for a simple
; `.include "breadbox.inc"` in the code that uses macros.
.include "core/cpu_shims.inc"
.include "core/delay.inc"
.include "core/boot.inc"
.include "core/vectors.inc"

.endif
