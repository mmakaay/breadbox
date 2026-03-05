; =========================================================================
; TICKER_CHECK: test whether a target number of ticks have elapsed.
;
; Compares (current ticks - timestamp) against _target. After the macro,
; carry is SET if elapsed, CLEAR if not yet. The byte width of the
; comparison (1, 2, or 3 bytes) is determined at assembly time from
; _target.
;
; In:
;   _ticks  = address of the ticker's ticks counter (e.g. TICKER::ticks)
;   _stamp  = address of the timestamp variable (.res 1, 2, or 3)
;   _target = tick count to wait for (constant, without # prefix)
;
; Out:
;   C = 1 if elapsed, 0 if not yet
;   A, X = clobbered (X only for multi-byte comparisons)
;   Y = clobbered (3-byte comparisons only)

.macro TICKER_CHECK _ticks, _stamp, _target
    sec
    lda _ticks
    sbc _stamp
    .if _target > 65535
        tax
        lda _ticks + 1
        sbc _stamp + 1
        tay
        lda _ticks + 2
        sbc _stamp + 2
        cmp #^(_target)
        bne :+
        tya
        cmp #>(_target)
        bne :+
        txa
        cmp #<(_target)
    :
    .elseif _target > 255
        tax
        lda _ticks + 1
        sbc _stamp + 1
        cmp #>(_target)
        bne :+
        txa
        cmp #<(_target)
    :
    .else
        cmp #(_target)
    .endif
.endmacro

; =========================================================================
; TICKER_STAMP: snapshot the current ticks into a timestamp variable.
;
; Copies 1, 2, or 3 bytes of the ticks counter into the timestamp,
; matching the byte width needed for _target.
;
; In:
;   _ticks  = address of the ticker's ticks counter (e.g. TICKER::ticks)
;   _stamp  = address of the timestamp variable (.res 1, 2, or 3)
;   _target = tick count (determines byte width, without # prefix)
;
; Out:
;   A = clobbered

.macro TICKER_STAMP _ticks, _stamp, _target
    .if _target > 65535
        CP_WORD _stamp, _ticks
        CP_BYTE _stamp + 2, _ticks + 2
    .elseif _target > 255
        CP_WORD _stamp, _ticks
    .else
        CP_BYTE _stamp, _ticks
    .endif
.endmacro
