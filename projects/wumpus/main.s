; ---------------------------------------------------------------------------
; Hunt the Wumpus — boot entry.
;
; Hands off to `wumpus_run` which owns the readline-driven game loop.
; If `wumpus_run` ever returns (the user quits), we just halt the CPU
; with a tight infinite loop so the LCD's final message stays visible.
; ---------------------------------------------------------------------------

.include "breadbox.inc"

.import wumpus_run
.export main

.segment "CODE"

    .proc main
        jmp wumpus_run              ; never returns — the game loops forever.
    .endproc
