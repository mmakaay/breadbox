# Ben Eater tutorial: Subroutine calls, now with RAM

Tutorial : https://youtu.be/omI0MrTWiMU \
Result   : https://youtu.be/omI0MrTWiMU?t=927 \
Code     : https://eater.net/downloads/hello-world-final.s

When comparing this code to the raw-dogged code as used
in the tutorial video, it might become clear what advantage
the kernal project brings. The hardware initialization and
interaction are encapsulated by BREADBOX, and in the code,
we can make use of the high level `LCD::write` subroutine.

## Even simpler

While the version of the code in `main.s` is already nice
and small, there is a method that is even simpler, by
leveraging functionality from `stdlib/io/print.inc`:

```6502 assembly
.include "breadbox.inc"
.include "stdlib/io/print.inc"

.export main

message: .asciiz "Hello, world!"

main:
    PRINT LCD::print, message
    HALT
```
