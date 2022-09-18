; setup raster interrupt and service
Start:

       sei ; disable interrupts
       lda #%101
       sta $0001 ; Get rid of KERNAL ROM
       lda #$00
       sta $dc0e ; Disable interrupts from CIA1

       lda #$00
       sta $d012 ; Set raster line to generate interrupt for

       lda #$01
       sta $d01a ; Enable raster interrupt

       lda #.lobyte(raster_isr_1)
       sta $fffe
       lda #.hibyte(raster_isr_1)
       sta $ffff

       cli ; enable interrupts

loop:
       jmp loop

raster_isr_1:
        ; XXX: Need to push/pop A but since main loop is not doing anything it still flies
        lda #$01
        sta $d019 ; Acknowledge interrupt
        inc $d020 ; Cycle background color
        lda #.lobyte(raster_isr_2)
        sta $fffe
        lda #.hibyte(raster_isr_2)
        sta $ffff
        lda #$10
        sta $d012 ; Set raster line to generate interrupt for
        rti

raster_isr_2:
        lda #$01
        sta $d019 ; Acknowledge interrupt
        dec $d020 ; Cycle background color
        lda #.lobyte(raster_isr_1)
        sta $fffe
        lda #.hibyte(raster_isr_1)
        sta $ffff
        lda #$00
        sta $d012 ; Set raster line to generate interrupt for
        rti
