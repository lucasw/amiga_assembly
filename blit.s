; adapted from https://github.com/alpine9000/amiga_examples
 include "include/registers.i"
 include "hardware/dmabits.i"
 include "hardware/intbits.i"

LVL3_INT_VECTOR  equ $6c
PLAYFIELD_WIDTH  equ 640
PLAYFIELD_HEIGHT  equ 200
PLAYFIELD_WIDTH_BYTES equ (PLAYFIELD_WIDTH/8)
PLAYFIELD_BIT_DEPTH equ 3
PLAYFIELD_RES  equ 8  ; 8=lo resolution, 4=hi resolution
RASTER_X_START  equ $81 ; hard coded coordinates from hardware manual
RASTER_Y_START  equ $2c
SCREEN_WIDTH equ 320
SCREEN_HEIGHT equ 256
RASTER_X_STOP  equ RASTER_X_START+SCREEN_WIDTH
RASTER_Y_STOP  equ RASTER_Y_START+SCREEN_HEIGHT

entry:
  move.l $4,a6
  move.l #gfxname,a1
  moveq  #0,d0
  jsr  -552(a6)
  move.l d0,gfxbase
  move.l d0,a6
  ;move.l 34(a6),oldview
  ;move.l 38(a6),oldcopper

  move.l #0,a1
  jsr -222(a6)  ; LoadView
  jsr -270(a6)  ; WaitTOF
  jsr -270(a6)  ; WaitTOF
  move.l $4,a6
  jsr -132(a6)  ; Forbid


 ;; custom chip base globally in a6
 lea  CUSTOM,a6

 move #$7ff,DMACON(a6) ; disable all dma
 move #$7fff,INTENA(a6) ; disable all interrupts

 include "out/image-palette.s"

 ;; set up playfield
 move.w #(RASTER_Y_START<<8)|RASTER_X_START,DIWSTRT(a6)
 move.w #((RASTER_Y_STOP-256)<<8)|(RASTER_X_STOP-256),DIWSTOP(a6)

 move.w #(RASTER_X_START/2-PLAYFIELD_RES),DDFSTRT(a6)
 move.w #(RASTER_X_START/2-PLAYFIELD_RES)+(8*((SCREEN_WIDTH/16)-1)),DDFSTOP(a6)
 ;move.w #$0038,DDFSTRT(a6)
 ;move.w #$00d0,DDFSTOP(a6)

 move.w #(PLAYFIELD_BIT_DEPTH<<12)|$200,BPLCON0(a6)
 move.w #PLAYFIELD_WIDTH_BYTES-TC_WIDTH_BYTES,BLTDMOD(a6) ;D modulo
 ; where is BPL1MOD?
 ; using vertical memory arrangement- 32x96
 ; move.w #PLAYFIELD_WIDTH_BYTES*PLAYFIELD_BIT_DEPTH-PLAYFIELD_WIDTH_BYTES,BPL2MOD(a6)
 move.w #0,BPL2MOD(a6)

 ;; poke bitplane pointers
 lea bitplanes(pc),a1
 lea     copper(pc),a2
 moveq #PLAYFIELD_BIT_DEPTH-1,d0
.bitplaneloop:
 move.l  a1,d1
 move.w d1,2(a2)
 swap d1
 move.w  d1,6(a2)
 lea PLAYFIELD_WIDTH_BYTES(a1),a1 ; bit plane data is interleaved
 addq #8,a2
 dbra d0,.bitplaneloop

 ;; install copper list, then enable dma and selected interrupts
 lea copper(pc),a0
 move.l a0,COP1LC(a6)
  move.w  COPJMP1(a6),d0
 move.w #(DMAF_BLITTER|DMAF_SETCLR!DMAF_COPPER!DMAF_RASTER!DMAF_MASTER),DMACON(a6)
 move.w #(INTF_SETCLR|INTF_INTEN|INTF_EXTER),INTENA(a6)

 bsr.s  doblit

.mainLoop:
 move.w  #$02a,d0  ;wait for EOFrame
 bsr.s  waitRaster
 bra.s .mainLoop


waitRaster:  ;wait for rasterline d0.w. Modifies d0-d2/a0.
 move.l #$1ff00,d2
 lsl.l #8,d0
 and.l d2,d0
 lea $dff004,a0
.wr: move.l (a0),d1
 and.l d2,d1
 cmp.l d1,d0
 bne.s .wr
 rts

blitWait:
 tst DMACONR(a6)  ;for compatibility
.waitblit:
 btst #6,DMACONR(a6)
 bne.s .waitblit
 rts

TC_WIDTH  equ 32
TC_HEIGHT equ 32
TC_WIDTH_BYTES equ TC_WIDTH/8
TC_WIDTH_WORDS equ TC_WIDTH/16
TC_XPOS  equ 16
TC_YPOS  equ 16
TC_XPOS_BYTES equ  (TC_XPOS)/8

;; BLTCON? configuration

;; http://amigadev.elowar.com/read/ADCD_2.1/Hardware_Manual_guide/node011C.html
;; blitter logic function minterm truth table
;; fill in D column for desired function
;;       A       B       C       D
;;       -       -       -       -
;;       0       0       0       0
;;       0       0       1       0
;;       0       1       0       0
;;       0       1       1       0
;;       1       0       0       1
;;       1       0       1       1
;;       1       1       0       1
;;       1       1       1       1
;;
;; then read D column from bottom up = 11110000 = $f0
;; this is used in the LF? bits
BLIT_LF_MINTERM  equ $f0
BLIT_A_SOURCE_SHIFT equ 0
BLIT_DEST  equ $100
BLIT_SRCC      equ $200
BLIT_SRCB      equ $400
BLIT_SRCA      equ $800
BLIT_ASHIFTSHIFT equ 12   ;Bit index of ASH? bits
BLIT_BLTCON1  equ 0    ;BSH?=0, DOFF=0, EFE=0, IFE=0, FCI=0, DESC=0, LINE=0

doblit:
 movem.l d0-a6,-(sp)
 bsr blitWait
 move.w #(BLIT_SRCA|BLIT_DEST|BLIT_LF_MINTERM|BLIT_A_SOURCE_SHIFT<<BLIT_ASHIFTSHIFT),BLTCON0(A6)
 move.w #BLIT_BLTCON1,BLTCON1(a6)
 move.l #$ffffffff,BLTAFWM(a6)  ;no masking of first/last word
 move.w #0,BLTAMOD(a6)        ;A modulo=bytes to skip between lines
 move.w #PLAYFIELD_WIDTH_BYTES-TC_WIDTH_BYTES,BLTDMOD(a6) ;D modulo
 move.l #tc,BLTAPTH(a6)  ;source graphic top left corner
 ;move.l #bitplanes+TC_XPOS_BYTES+(PLAYFIELD_WIDTH_BYTES*PLAYFIELD_BIT_DEPTH*TC_YPOS),BLTDPTH(a6) ;destination top left corner
 move.l #bitplanes+TC_XPOS_BYTES+(PLAYFIELD_WIDTH_BYTES*TC_YPOS),BLTDPTH(a6) ;destination top left corner
 move.w #(TC_HEIGHT*PLAYFIELD_BIT_DEPTH)<<6|(TC_WIDTH_WORDS),BLTSIZE(a6) ;rectangle size, starts blit
 movem.l (sp)+,d0-a6
 rts

copper:
 ;; bitplane pointers must be first else poking addresses will be incorrect
 dc.w BPL1PTL,0
 dc.w BPL1PTH,0
 dc.w BPL2PTL,0
 dc.w BPL2PTH,0
 dc.w BPL3PTL,0
 dc.w BPL3PTH,0
 dc.w BPL4PTL,0
 dc.w BPL4PTH,0
 dc.w BPL5PTL,0
 dc.w BPL5PTH,0


 dc.l $fffffffe
bitplanes:
 incbin "gimp/mountains.data.raw"

tc:
 incbin "gimp/explosion.data.raw"

gfxbase: dc.l 0 ; TODO(lucasw) moved this from other misc register above, does it matter?
gfxname:
  dc.b 'graphics.library',0
  Section ChipRAM,Data_c
  CNOP 0,4