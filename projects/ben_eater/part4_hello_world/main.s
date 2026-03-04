.include "breadbox.inc"

.export main

main:
    lda #'H'
    jsr LCD::write

    lda #'e'
    jsr LCD::write

    lda #'l'
    jsr LCD::write

    lda #'l'
    jsr LCD::write

    lda #'o'
    jsr LCD::write

    lda #','
    jsr LCD::write

    lda #' '
    jsr LCD::write

    lda #'w'
    jsr LCD::write

    lda #'o'
    jsr LCD::write

    lda #'r'
    jsr LCD::write

    lda #'l'
    jsr LCD::write

    lda #'d'
    jsr LCD::write

    lda #'!'
    jsr LCD::write

    HALT
