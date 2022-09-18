Start:
       lda #$80
       sta $07f8


;       lda #$11
;       sta $2000
;       lda #$22
;       sta $2001
;       lda #$33
;       sta $2002
;       lda #$44
;       sta $2003

       lda #$03
       sta $d027 ; Color
       lda #$20
       sta $d000 ; X
       lda #$40
       sta $d001 ; Y

       lda #$1
       sta $d015
loop:
        jmp loop

        lda #$fe ; make sure we reached
loop3:  cmp $d012 ; the next raster line so next time we
        bne loop3 ; should catch the same line next frame

       inc $d000 ; X

        lda $d012 ; make sure we reached
loop4:  cmp $d012 ; the next raster line so next time we
        beq loop4 ; should catch the same line next frame

       jmp loop

.segment "GFXDATA"
.byte $90, $91, $92
.byte $93, $94, $95
.byte $96, $97, $98
.byte $ff, $ff, $ff
.byte $00, $ff, $00
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $ff, $ff, $ff
.byte $ff, $ff, $ff
.byte $ff, $ff, $ff
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $0f, $ff, $f0
.byte $00, $ff, $00
.byte $ff, $ff, $ff
.byte $a2, $a3, $a4
.byte $a5, $a6, $a7
