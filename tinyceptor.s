;# directives #########################################################################
;# these are given in vasm command line with -D<name>[=<expression>] ##################
; STANDALONE                 ; 0 = only build music routine at $1000
                             ; 1 = build the whole runnable program
; SIDHEADER                  ; 1 = include sid header if outputting only music

;# constants ##########################################################################
CHBUF       = $0a00         ; character buffer
CLBUF       = CHBUF + $500  ; color buffer
C3          = $08A8         ; note frequencies
D3          = $09B7
F3          = $0B8E
TICK        = 7             ; how many frames between noteupdates
LEAD_CR     = $41           ; ch1 control register
PAT1        = %00100101     ; octave up down,            1 line
PAT2        = %00000001     ; replace last two notes,    2 lines
PAT3        = %00010100     ; flip flop D D C D         16 lines

var         = $80           ; $18 values of sid-registers + variable table to zeropage

PS1         = $6c           ; petscii for BG
PS2         = $78           ; petscii for outline
PS3         = $63           ; petscii for inside

; these are initialized with values from the data block
freq        = var + 0       ; ch1 frequency
filter      = var + $16
tick        = var + $19     ; decrement once a frame and reset to TICK when 0
counter     = var + $1a     ; increment when tick goes to 0
pattern     = var + $1b     ; 3 bytes reserved for 8 bit on/off music patterns
scandal     = var + $1e     ; "scandal!" written in reverse for optimization
scancounter = var + $26     ; pointer to current "scandal!" character
charbuffer  = var + $27     ; pointer for character buffer
colorbuffer = var + $29     ; pointer for color buffer
screen      = var + $2b     ; pointer for vic screen
colormem    = var + $2d     ; pointer for color mem
round       = var + $2f     ; increase after each  filled screen

; these don't need to be initialized from the data block
temp        = var + $30     ; used for graphics fill repetitions
note_low    = var + $31     ; temp note low byte
note_high   = var + $32     ; temp note high byte

    if STANDALONE=1

    org $0801 ;"BASIC Upstart"
    byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$32,$00,$00,$00

;########################################################################################
;# init #################################################################################
;########################################################################################
    sei                     ; stop interrupts

;# music and variables init ####################
    ldx #$31                ; optimized with 1 off to get x to 0
:
    lda sid_init-1,x        ; register dump from data block
    sta $d400-1,x           ; sid values, values over $d418 overflow mirrored sid regs temporarily
    sta var-1,x             ; copy the same values to zeropage
    dex 
    bne :-  

    txa                     ; x and a are 0
    sta $d020               ; black border
    sta $d021               ; black bg


;# draw graphics to buffer ####################
.gfx
    pha                     ; put flipflop to stack, gets flipped at the end of loop
    ldy bitstream,x         ; get repetitions from bitstream table
    beq .endrows            ; zero means end of list has been reached
    sty temp                ; store repetitions to temp
    bpl :+                  ; if value is positive, skip
    lda #6                  ; color for inside fill
    pha                     ; store color in stack
    lda #PS3                ; petscii for inside fill
    bne .store              ; always jump
:       
    cmp #0                  ; bitstream flipflops for bg and outline
    beq :+  
    lda #12                 ; color for outline
    pha                     ; store color in stack
    lda #PS2                ; petscii for outline
    bne .store              ; always jump
:   
;    lda #0                  ; color for background, optimized out
    pha                     ; store color in stack
    lda #PS1                ; petscii for background

.store  
    sta (charbuffer),y      ; write petscii to current location in buffer
    dey 
    bne .store              ; loop until repetitions done
    pla                     ; get color from stack
    ldy temp                ; get repetitions from temp
:   
    sta (colorbuffer),y     ; store color to buffer
    dey 
    bne :-                  ; loop until repetitions done


    clc 
    lda temp                ; get repetitions from temp
    and #%01111111          ; take out negative flag
    adc charbuffer          ; advance buffers to next value
    sta charbuffer  
    sta colorbuffer 
    tya                     ; optimized instead of lda #0
    adc charbuffer+1        ; add possible carry bit to high byte
    sta charbuffer+1    
    adc #>(CLBUF-CHBUF)     ; high byte difference between char and color buffer
    sta colorbuffer+1       ; add difference to colorbuffer offset
    pla                     ; get flip-flip from stack
    eor #1                  ; flip it
    inx
    bne .gfx
.endrows
    lda CHBUF+$2e7+16,y     ; repeat the last identical rows
    sta CHBUF+$2e7+16+40,y
    lda CLBUF+$2e7+16,y
    sta CLBUF+$2e7+16+40,y
    iny
    bne .endrows


;# jump here when screen is filled to start new round ##################################
reset_screen:
    ldy #8
:
    lda sid_init+$26,y      ; restore original values from data section
    sta charbuffer-1,y      ; to zeropage variables
    dey
    bne :-                  ; y needs to be zero when starting new round

    inc round

;########################################################################################
;# main loop ############################################################################
;########################################################################################
main:
:
    ldx $d012               ; load current raster line
    cpx #$f0                ; compare to given number
    bne :-                  ; wait until true

    jsr music_play          ; do once per frame

.round                      ; round can be called multiple times per frame
    lda round
    and #1
    beq .copy
    lda (charbuffer),y      ; y should be 0 at on first round
    cmp #PS1
    bne .copy
                            ;scandal
    ldx scancounter
    lda scandal,x
    sta (colorbuffer),y
    dex
    bpl :+
    ldx #7
:
    stx scancounter
    sta (screen),y
    lda #2                  ; color for scandal text
    sta (colormem),y
    bne .increment          ; always jump

.copy
    lda (charbuffer),y
    sec
    sbc round               ; subtract round from character value
    sta (screen),y
    lda (colorbuffer),y
    clc
    adc round
    sta (colormem),y

.increment
    iny
    bne .skip
    inc charbuffer+1
    inc colorbuffer+1
    inc screen+1
    inc colormem+1
    lda charbuffer+1
    cmp #>(CHBUF+$400)
    beq reset_screen
.skip
    tya
    and round
    bne .round
    beq main            ; always jump

    endif               ; endif for standalone directive = 1

;########################################################################################
;# music ################################################################################
;########################################################################################

    if STANDALONE=0
;# sid header file #####################################################################
    if SIDHEADER=1
    org $1000-$7c
    ascii "PSID"                            ; magicid PSID or RSID
    byte 0,2                                ; version 1 or 2
    byte 0,$7c                              ; dataoffset - $76 for v1, 7c for v2
    byte $10,$00                            ; load address if no header
    byte $10,$00                            ; init address
    byte $10,$03                            ; playaddress
    byte 0,1                                ; songs
    byte 0,1                                ; startsong
    byte 0,0,0,0                            ; speed bit per song, 0 vblank, 1 cia
    ascii "Tinyceptor                     " ; title,    31 characters
    byte 0
    ascii "Laurikka                       " ; author,   31 characters
    byte 0
    ascii "2026 Laurikka                  " ; released, 31 characters
    byte 0
    byte 0,%00010100                        ; v2 flags, bits 4-5: 01 MOS6581, 10 = MOS8580
    byte 0                                  ; v2 startpage
    byte 0                                  ; v2 pagelength
    byte 0,0                                ; reserved, leave at 0
    org $1000
    endif                                   ; endif for sid header

;# music init ########################################################################
    jmp music_init
    jmp music_play

music_init:
    ldx #$1d
:
    lda sid_init,x
    sta $d400,x
    sta var,x
    dex
    bpl :-
    rts 

    endif               ; endif for standalone directive = 0

;# music routine ####################################################################
music_play:
    dec tick
    beq .noteupdate     ; if tick is zero, do a note
    lda tick
    cmp #TICK-2         ; gate off note after two frames
    bne :+
    ldx #LEAD_CR-1      ; turn gate off to go to decay
    stx $d404
    inx
    stx $d412           ; gate on for ch3
:
    rts                 ; otherwise return to mainloop

.noteupdate
    ldx #TICK           ; reset tick count
    stx tick
    inc counter         ; increment counter
;# every note #####################################
    ldx #0
    jsr .bitshift       ; x pointing to bit pattern 0

;# 1 in 16 note #######################################
    lda counter
    and #%00001111      ; for every 16th noteupdate
    bne .test_highnote  ; skip ahead or

    ldx #2
    jsr .bitshift       ; x pointing to bit pattern 2
    beq .test_highnote
                
    lda #<D3            ; flip flop between two notes by comparing to frequence set in sid-init
    cmp freq
    bne :+
    lda #<C3
    sta freq
    lda #>C3
    sta freq+1
    bne .test_highnote
:
    sta freq
    lda #>D3
    sta freq+1
;# 1 in 2 note #######################################
.test_highnote
    lda counter
    and #1              ; for every 2nd noteupdate
    beq :+              ; skip ahead or
    tax                 ; optimized to get x to be 1
    jsr .bitshift       ; x pointing to bit pattern 1
:
    lda pattern+1
    and #1
    beq :+
    lda #<F3
    sta note_low
    lda #>F3
    sta note_high

    inc filter          ; increase filter value
    lda filter          ; after every 8 notes
    lsr
    sta $d416
    bvc .noteon         ; always jump
:
    lda pattern
    and #1
    bne .setnote        ; if zero jump ahead
    lda freq+1          ; get current frequency
    lsr                 ; octave down by shifting right
    sta note_high
    lda freq            ; do same for high byte
    ror                 ; taking into account the possible
    sta note_low        ; carry bit from low byte
    bne .noteon         ; always jump to noteon
.setnote
    lda freq            ; restore original frequency from table
    sta note_low
    lda freq+1
    sta note_high
.noteon
    lda note_low        ; write frequency from zeropage
    sta $d400           ; to register
    lda note_high
    sta $d401
    ldx #LEAD_CR        ; turn gate on to start attack
    stx $d404
    dex
    stx $d412           ; gate off for ch3

    rts

.bitshift
    clc
    lda pattern,x       ; get bitpattern from zeropage
    rol                 ; shift left
    adc #0              ; rotate highest bit to lowest
    sta pattern,x       ; store rotated pattern back
    and #1              ; leave only first bit to accu
    rts                 ; and return from subroutine


;# sid registers init $d400-$d418 #######################################################
            ;#channel 1                  #channel 2                  #channel 3                  #filter
            ; fr      pw      cr  ad  sr  fr      pw      cr  ad  sr  fr      pw      cr   ad  sr  fco     fc  v
sid_init:   ; 0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F   10  11  12   13  14  15  16  17  18 
    byte      <D3,>D3,0,  4,  0,  0,  $f6,$c8,$04,0,  $08,$21,$00,$5f,$e2,$04,0,  $e, $41,$a0,$00,$0f,$02,$27,$3f

; music vars from +$19 to copy to zeropage
;                cnt                
;           $19, $1a,$1b, $1c, $1d, 
    byte    TICK,$00,PAT1,PAT2,PAT3

;#########################################################################################
;# data ##################################################################################
;#########################################################################################

    if STANDALONE=1

; vars from +$1e to copy to zeropage
;            !   L   A   D   N   A   C   S  sc  charbuffer,colorbuffer,screen  clmem   rnd
;           $1e,$1f,$20,$21,$22,$23,$24,$25,$26,$27,$28,   $29 ,$2a,   $2b,$2c,$2d,$2e,$2f
    byte    $21,$0c,$01,$04,$0e,$01,$03,$13,$07,$00,>CHBUF,$01,>CLBUF ,$ff,$03,$ff,$d7,$ff


;bitstream_unpacked:
;    byte %00000000,%00000000,%01111000,%00000000,%00000000
;    byte %00000000,%00000000,%01111100,%00000000,%00000000
;    byte %00000000,%00000000,%11111100,%00000000,%00000000
;    byte %00000000,%00000000,%11111110,%00000000,%00000000
;    byte %00000000,%00000000,%11111110,%00000000,%00000000
;    byte %00000000,%00000001,%10000110,%00000000,%00000000
;    byte %00000000,%00000001,%00000011,%00000000,%00000000
;    byte %00000000,%00000011,%00000001,%00000000,%00000000
;    byte %00000000,%00000100,%00000000,%10000000,%00000000
;    byte %00000000,%00000100,%00000000,%10000000,%00000000
;    byte %00000000,%00000111,%10000011,%11000000,%00000000
;    byte %00000000,%00011100,%01000100,%11111000,%00000000
;    byte %00000000,%00111110,%00111000,%11111100,%00000000
;    byte %00000000,%01110000,%00000000,%00011100,%00000000
;    byte %00000000,%01001100,%00000000,%00100010,%00000000
;    byte %00000000,%01000010,%00000000,%11000010,%00000000
;    byte %00000000,%01000001,%11111111,%00000010,%00000000
;    byte %00000000,%01000000,%01111100,%00000010,%00000000
;    byte %00000000,%01000000,%00000000,%00000010,%00000000
;    byte %00000000,%10000000,%00011000,%00000010,%00000000
;    byte %00000000,%10000000,%00011000,%00000010,%00000000
;    byte %00000000,%10000000,%00011000,%00000010,%00000000
;    byte %00000000,%10000000,%00011000,%00000010,%00000000
;    byte %00000000,%10000000,%00011000,%00000010,%00000000
;    byte %00000000,%10000000,%00011000,%00000010,%00000000

bitstream: ; packed
;   bytevalue is repetitions, flip flops between 0 and 1,
;   negative flag "+128" activates alternative value to fill the inside of shape
    byte 17+40,4,36,5,34,6,34,7,33,7,32,2,4+128,2,32,1,6+128,2,30,2,7+128,1
    byte 29,1,10+128,1,28,1,10+128,1,28,4,5+128,4,25,3,3+128,1,3+128,1,2+128,5,21,5
    byte 3+128,3,3+128,6,19,3,15+128,3,19,1,2+128,2,12+128,1,3+128,1,18,1,4+128,1
    byte 9+128,2,4+128,1,18,1,5+128,9,6+128,1,18,1,7+128,5,8+128,1
    byte 18,1,9+128,2,9+128,1,9,0

    endif   ; for standalone = 1