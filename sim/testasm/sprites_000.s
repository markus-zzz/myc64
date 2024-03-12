;*************************************************
;* Create and move a simple sprite x,y           *
;*************************************************

;helpful labels
CLEAR = $E544

;sprite 0 setup
SPRITE0 = $7F8
COLOR0  = $D027
SP0X  = $D000
SP0Y  = $D001
MSBX  = $D010
SP0VAL  = $0340

ENABLE  = $D015
YEXPAND  = $D017
XEXPAND  = $D01D

    JSR CLEAR

    LDA #$0
    STA $D020 ;black border
    STA $D021 ;black background

    LDA #$1
    STA $D025 ;Sprite extra color #1
    LDA #$2
    STA $D026 ;Sprite extra color #2
    LDA #$5
    STA $D027 ;Sprite #0 color

    LDA #$1
    STA $D01C ;Sprite #0 multicolor

    LDA #$0D  ;using block 13 for sprite0
    STA SPRITE0

    LDA #01    ;enable sprite0
    STA ENABLE

    LDX #0
    LDA #0

    ;reset the spriteval data
CLEANUP:
    STA SP0VAL,X
    INX
    CPX #63
    BNE CLEANUP

    ;build the sprite
    LDX #0
BUILD:
    LDA DATA,X
    STA SP0VAL,X
    INX
    CPX #63
    BNE BUILD

    ;position
    LDA #0    ;stick with x0-255
    STA MSBX

    ;starting sprite location
    LDX #100
    LDY #70
    STX SP0X
    STY SP0Y

HALT:
    JMP HALT
    ;define the sprite

DATA:
    .BYTE %11100100,0,0
    .BYTE 0,0,0
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .BYTE 255,255,255
    .END

