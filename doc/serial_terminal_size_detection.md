```
; Query terminal size via ANSI CPR trick
; Results: term_rows, term_cols (zero-page variables)

.zeropage
term_rows: .res 1
term_cols: .res 1

.code

; Step 1: Send ESC[999;999H  then ESC[6n
query_term_size:
    ; Send the cursor-move + CPR request
    ldx #0
@send_loop:
    lda query_seq, x
    beq @send_done
    jsr uart_putc          ; your UART transmit routine
    inx
    bra @send_loop         ; 65C02; use BNE with sentinel for plain 6502
@send_done:

    ; Step 2: Read response: ESC [ digits ; digits R
    jsr uart_getc          ; expect ESC (0x1B)
    cmp #$1B
    bne @error
    jsr uart_getc          ; expect '['
    cmp #'['
    bne @error

    ; Parse rows (decimal digits until ';')
    lda #0
    sta term_rows
@parse_rows:
    jsr uart_getc
    cmp #';'
    beq @parse_cols_init
    sec
    sbc #'0'               ; ASCII digit to value
    ; term_rows = term_rows * 10 + A
    pha
    lda term_rows
    asl a                  ; x2
    asl a                  ; x4
    adc term_rows          ; x5  (carry clear after ASL if <26)
    asl a                  ; x10
    sta term_rows
    pla
    adc term_rows
    sta term_rows
    bra @parse_rows

@parse_cols_init:
    lda #0
    sta term_cols
@parse_cols:
    jsr uart_getc
    cmp #'R'               ; end of response
    beq @done
    sec
    sbc #'0'
    pha
    lda term_cols
    asl a
    asl a
    adc term_cols
    asl a
    sta term_cols
    pla
    adc term_cols
    sta term_cols
    bra @parse_cols
@done:
    rts
@error:
    ; handle no response / unknown terminal
    rts

; Null-terminated sequence: ESC[999;999H ESC[6n
query_seq:
    .byte $1B,"[999;999H",$1B,"[6n",0
```
