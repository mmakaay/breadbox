; -----------------------------------------------------------------
; WozMon, modified for the breadboard computer KERNAL
;
; Differences with the original:
; - No hard-coded memory addresses, but using the linker for
;   assigning these automatically.
; - Serial console is used for output, via CONSOLE::write_terminal
;   which automatically expands CR to CR+LF for correct terminal
;   line endings.
; - The Apple II only supports upper case, resulting in the
;   the original code also only working with upper case input.
;   This modified code converts all input to upper case, so
;   the user can also input lower case characters.
; - Unlike Ben Eater, I did not make sure that the ECHO routine
;   remained at $FFEF, like described in the Apple II manual.;
; -----------------------------------------------------------------

.include "breadbox.inc"

.export WOZMON

.segment "ZEROPAGE"

    XAML: .res 1                ; Last "opened" location Low
    XAMH: .res 1                ; Last "opened" location High
    STL:  .res 1                ; Store address Low
    STH:  .res 1                ; Store address High
    L:    .res 1                ; Hex value parsing Low
    H:    .res 1                ; Hex value parsing High
    YSAV: .res 1                ; Used to see if hex value is given
    MODE: .res 1                ; $00=XAM, $7F=STOR, $AE=BLOCK XAM

.segment "RAM"

    IN: .res $FF                ; Input buffer

.segment "CODE"

    WOZMON:

    ; No hardware initialization required like the original, since
    ; the KERNAL initialization already set up the hardware for us.
    RESET:
        lda #$1B               ; Begin with escape.

    NOTCR:
        cmp #$08               ; Backspace key?
        beq BACKSPACE          ; Yes.
        cmp #$1B               ; ESC?
        beq ESCAPE             ; Yes.
        iny                    ; Advance text index.
        bpl NEXTCHAR           ; Auto ESC if line longer than 127.

    ESCAPE:
        lda #$5C               ; "\".
        jsr ECHO               ; Output it.

    GETLINE:
        lda #$0D               ; CR triggers CR+LF via ECHO.
        jsr ECHO

        ldy #$01               ; Initialize text index.
    BACKSPACE:
        dey                    ; Back up text index.
        bmi GETLINE            ; Beyond start of line, reinitialize.

    NEXTCHAR:
        jsr CONSOLE::read       ; Wait for a character.
        bcc NEXTCHAR           ; No character read? Try again.
        cmp #$7F               ; DEL? (backspace on many terminals)
        bne @not_del
        lda #$08               ; Normalize to BS.
    @not_del:
        cmp #$61               ; Lowercase letter?
        bcc @upper
        sbc #$20               ; Yes, convert to uppercase (carry set from CMP).
    @upper:
        sta IN,y               ; Add to text buffer.
        jsr ECHO               ; Display character.
        lda IN,y               ; Reload character (ECHO clobbers A).
        cmp #$0D               ; CR?
        bne NOTCR              ; No.

        ldy #$FF               ; Reset text index.
        lda #$00               ; For XAM mode.
        tax                    ; X=0.
    SETBLOCK:
        asl
    SETSTOR:
        asl                    ; Leaves $7B if setting STOR mode.
        sta MODE               ; $00 = XAM, $74 = STOR, $B8 = BLOK XAM.
    BLSKIP:
        iny                    ; Advance text index.
    NEXTITEM:
        lda IN,y               ; Get character.
        cmp #$0D               ; CR?
        beq GETLINE            ; Yes, done this line.
        cmp #$2E               ; "."?
        bcc BLSKIP             ; Skip delimiter.
        beq SETBLOCK           ; Set BLOCK XAM mode.
        cmp #$3A               ; ":"?
        beq SETSTOR            ; Yes, set STOR mode.
        cmp #$52               ; "R"?
        beq RUN                ; Yes, run user program.
        stx L                  ; $00 -> L.
        stx H                  ;    and H.
        sty YSAV               ; Save Y for comparison

    NEXTHEX:
        lda IN,y               ; Get character for hex test.
        eor #$30               ; Map digits to $0-9.
        cmp #$0A               ; Digit?
        bcc DIG                ; Yes.
        adc #$88               ; Map letter "A"-"F" to $FA-FF.
        cmp #$FA               ; Hex letter?
        bcc NOTHEX             ; No, character not hex.
    DIG:
        asl
        asl                    ; Hex digit to MSD of A.
        asl
        asl

        ldx #$04               ; Shift count.
    HEXSHIFT:
        asl                    ; Hex digit left, MSB to carry.
        rol L                  ; Rotate into LSD.
        rol H                  ; Rotate into MSD's.
        dex                    ; Done 4 shifts?
        bne HEXSHIFT           ; No, loop.
        iny                    ; Advance text index.
        bne NEXTHEX            ; Always taken. Check next character for hex.

    NOTHEX:
        cpy YSAV               ; Check if L, H empty (no hex digits).
        beq ESCAPE             ; Yes, generate ESC sequence.

        bit MODE               ; Test MODE byte.
        bvc NOTSTOR            ; B6=0 is STOR, 1 is XAM and BLOCK XAM.

        lda L                  ; LSD's of hex data.
        sta (STL,x)            ; Store current 'store index'.
        inc STL                ; Increment store index.
        bne NEXTITEM           ; Get next item (no carry).
        inc STH                ; Add carry to 'store index' high order.
    TONEXTITEM:
        jmp NEXTITEM           ; Get next command item.

    RUN:
        jmp (XAML)             ; Run at current XAM index.

    NOTSTOR:
        bmi XAMNEXT            ; B7 = 0 for XAM, 1 for BLOCK XAM.

        ldx #$02               ; Byte count.
    SETADR:
        lda L-1,x              ; Copy hex data to
        sta STL-1,x            ;  'store index'.
        sta XAML-1,x           ; And to 'XAM index'.
        dex                    ; Next of 2 bytes.
        bne SETADR             ; Loop unless X = 0.

    NXTPRNT:
        bne PRDATA             ; NE means no address to print.
        lda #$0D               ; CR triggers CR+LF via ECHO.
        jsr ECHO
        lda XAMH               ; 'Examine index' high-order byte.
        jsr PRBYTE             ; Output it in hex format.
        lda XAML               ; Low-order 'examine index' byte.
        jsr PRBYTE             ; Output it in hex format.
        lda #$3A               ; ":".
        jsr ECHO               ; Output it.

    PRDATA:
        lda #$20               ; Blank.
        jsr ECHO               ; Output it.
        lda (XAML,x)           ; Get data byte at 'examine index'.
        jsr PRBYTE             ; Output it in hex format.
    XAMNEXT:
        stx MODE               ; 0 -> MODE (XAM mode).
        lda XAML
        cmp L                  ; Compare 'examine index' to hex data.
        lda XAMH
        sbc H
        bcs TONEXTITEM         ; Not less, so no more data to output.

        inc XAML
        bne MOD8CHK            ; Increment 'examine index'.
        inc XAMH

    MOD8CHK:
        lda XAML               ; Check low-order 'examine index' byte
        and #$07               ; For MOD 8 = 0
        bpl NXTPRNT            ; Always taken.

    ; Print the byte in A as two hex characters.
    PRBYTE:
        pha                    ; Save A for LSD.
        lsr
        lsr
        lsr                    ; MSD to LSD position.
        lsr
        jsr PRHEX              ; Output hex digit.
        pla                    ; Restore A.

    ; Print the lower nibble of A as a hex character.
    ; Falls through to ECHO.
    PRHEX:
        and #$0F               ; Mask LSD for hex print.
        ora #$30               ; Add "0".
        cmp #$3A               ; Digit?
        bcc ECHO               ; Yes, output it.
        adc #$06               ; Add offset for letter.

    ; Output the character in A to the serial console.
    ECHO:
        pha
        jsr CONSOLE::write_terminal
        pla
        rts
