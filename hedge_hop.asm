;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   HEDGE HOP  -  an original crossing game                    ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Spike the hedgehog goes home to the hedge: first a       ;
;     country road (milk truck, motorbike, car, tractor),      ;
;     then a stream crossed on logs and lily pads; some pads   ;
;     go under now and then                                    ;
;   - one hop a lane (up, down) or half a lane (left, right);  ;
;     a new lane forward 10 points                             ;
;   - 5 holes in the hedge: 50 points and 10 every half second ;
;     left; all 5 full: 1000 and the next level                ;
;   - a beetle in a hole 200 more; the little hedgehog waiting ;
;     on a log, brought home, 200 more                         ;
;   - from level 2 a fox on the bank, from level 3 a heron     ;
;     in the hedge, from level 4 a snake on the logs           ;
;   - morning, afternoon, sunset, night, then morning again,   ;
;     faster                                                   ;
;   - 30 seconds a hedgehog; 3 lives, one more at 10000;       ;
;     1 or 2 players taking turns                              ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 40 of the save     ;
;     area, lib_records.asm)                                   ;
;   - the lanes are tiles that scroll 2 pixels at a time: a    ;
;     lane is redrawn (2 rows of the name table) only when it  ;
;     moved, top to bottom just after the vertical blank       ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at the start, at home and at the end ;
;     of a level; hops, horns, splashes                        ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: lives left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
LEVEL       = $40      ; ---- block of the player, saved: level 0-98
HOMES       = $41      ;      the holes with a hedgehog (bits 0-4)
XTRA        = $42      ;      1 = the extra life was given
PBLOCK      = 3
GSTATE      = $50      ; 0 playing, 1 life lost, 2 at home, 3 the hedge is full
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives and level, 4 the hedge
FIRSTT      = $53      ; 1 = first turn of the game
HX          = $54      ; Spike: left x, sprite y, lane step (0 meadow .. 10 hedge)
HPY         = $55
HY          = $56
HDIR        = $57      ; 0 up, 1 right, 2 down, 3 left
HT          = $58      ; frames of the hop left (0 = sitting)
HDX         = $59      ; pixels a frame of the hop (signed)
HDY         = $5A
HMAX        = $5B      ; the step reached in this trip (10 points a new one)
DEATHK      = $5C      ; 0 squashed, 1 in the water
JPREV       = $5D      ; joystick of the frame before, new presses
JNEW        = $5E
HOLD        = $5F      ; frames a direction is held (repeat)
FRAME_CNT   = $60
LAST_FRAME  = $61
RND         = $62
VINT        = $63      ; 1 = VDP interrupt on
T0          = $64
T1          = $65
T2          = $66
T3          = $67
T4          = $68
T5          = $69
T6          = $6A
T7          = $6B
PTR         = $6C      ; 2 bytes
PTR2        = $6E      ; 2 bytes
TP          = $70      ; 2 bytes: text records
TIME        = $72      ; 2 bytes: frames left for this hedgehog
BARPX       = $74      ; the time bar drawn (pixels, $FF = draw it)
PAL         = $75      ; palette: 0 morning, 1 afternoon, 2 sunset, 3 night
SET         = $76      ; set of tapes of the level (0-3)
WATERC      = $77      ; colour of the water in this palette
DIVES       = $78      ; the diving pads: 0 up .. 3 under
DIVET       = $79      ; frames left in this state
DIVEI       = $7A      ; step of the cycle (0-5)
LOSTN       = $7B      ; lives lost (tests)
BABY        = $7C      ; the little hedgehog: 0 away, 1 waiting on its log, 2 carried
BABT        = $7D      ; its timer (frames / 4)
OUTF        = $7E      ; 1 = carried off the screen
HLANE       = $7F      ; the lane Spike sits on ($FF = none)
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
FOXON       = $88      ; the fox: there, x, direction (0 right), fraction
FOXX        = $89
FOXD        = $8A
FOXF        = $8B
HERH        = $8C      ; the heron: hole ($FF = none), timer (frames / 4)
HERT        = $8D
BEETH       = $8E      ; the beetle: hole ($FF = none), timer (frames / 4)
BEETT       = $8F
SNON        = $90      ; the snake: there, offset on its log, direction, fraction
SNO         = $91
SND         = $92
SNF         = $93
SNX         = $94      ; 2 bytes: screen x of the snake (high byte 0 = on the screen)
BABX        = $96      ; 2 bytes: screen x of the little hedgehog
TICKS       = $98      ; frames of the slow timers (every 4 frames)
HOMEN       = $99      ; hole reached (tests)
BONUSF      = $9A      ; points of this home: 1 beetle, 2 little one (tests)
NSTEP       = $9B      ; lanes drawn in this frame (tests)
HOLED       = $9D      ; holes of the hedge to draw again (bits 0-4)
DEATHS      = $9C      ; what took the last life (tests): 1 car, 2 water, 3 off the screen, 4 hedge, 5 fox, 6 heron, 7 snake, 8 time

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SND_PTR    = $B0         ; 2 bytes: music
SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; 0 = game effects, 1 = music
SND_BUSY   = $FC         ; 1 while the tune is playing
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

; ---------------- zero page: sprite list ----------------
OX         = $E0         ; sprite being added: left x, top y, pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4         ; next free byte of the SAT

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; noise effect playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709
TR_PL      = $0710       ; music, 4 tracks: pointer (lo / hi), counter, active,
TR_PH      = $0714       ;                  note, volume, age of the note
TR_CT      = $0718
TR_ACT     = $071C
TR_NOTE    = $0720
TR_VOL     = $0724
TR_AGE     = $0728

CMD_GAME   = 1           ; silence + game effects
CMD_START  = 2           ; the tune SONG
SONG       = $0730       ; tune to play

; ---------------- the lanes: 0-3 the stream (top down), 4-7 the road ----------------
NLANE      = 8
P_F        = $0200       ; position: fraction, pixels (0-511: low, high)
P_L        = $0208
P_H        = $0210
Q_L        = $0218       ; position drawn (even pixels)
Q_H        = $0220
LDIRTY     = $0228       ; 1 = draw the lane again
SP_L       = $0230       ; speed (8.8)
SP_H       = $0238
LTP_LO      = $0240       ; its tape (64 parts)
LTP_HI      = $0248
LTY        = $0250       ; its type * 8 (SOLID)

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 8: block of every player
KT         = $0800       ; 8 x 96: base tile of the cell pair under every column (64 + 32 again)
REMAP      = $0B00       ; 256: colour byte through the palette

; ---------------- parameters ----------------
BTN_MASK    = %00110000
TIME0       = 1800       ; frames for a hedgehog (30 s)
HX0         = 120        ; where Spike starts
NHOLE       = 5
MAXDRAW     = 6          ; lanes redrawn in a frame at most

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 40         ; fixed zone of the game in the save area
REC_RAM     = $7D00      ; $2A0 bytes after the program
REC_ROW     = 9          ; table on rows 9-17 of the title
REC_WIPEN   = 10         ; rows 9-18 of the title give way to the table
REC_JOY2    = $FF        ; both joysticks drive the player playing
REC_SROW    = REC_ROW    ; table header on the sign screen

PORTB_JOY = $d580        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 2
PORTA_JOY = $d581        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 1
DDRB_JOY  = $d582
DDRA_JOY  = $d583

VDP_SPRITE_ATT_BASE = $3B00
VDP_NAME_TABLE_BASE = $3800
VREG  = $B001           ; VDP REGISTER
VDATA = $B000           ; VDP RAM
VDP_WRITE_VRAM_BIT = %01000000
VDP_REGISTER_BITS  = %10000000


 .org $0FD0               ; trampoline called by NMI_HANDLER (bios) with JSR $0FD0
DISPATCH:
  JMP NMI_TASK


 .org $1000
RESET:
  SEI
  LDX #$FF
  TXS
  JSR VDP_SET_REGISTERS
  STZ VINT
  JSR LOAD_GFX
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  STZ DDRA_JOY
  STZ DDRB_JOY
  STZ FRAME_CNT
  STZ LAST_FRAME
  STZ HOFF
  LDA #1
  STA NPL
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  DEX
  BPL .rs_p
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_HISC
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, who is who, the points
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #<GFX_TITLE              ; the big letters (third 0)
  STA PTR2
  LDA #>GFX_TITLE
  STA PTR2+1
  JSR LOAD_BLOCKS
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JSR PRINT
  LDA #<TXT_BUTTONS
  STA TP
  LDA #>TXT_BUTTONS
  STA TP+1
  JSR PRINT
  JSR TITLE_PAGE
  JSR REC_TITLE
  STZ SONG                     ; the title tune
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR TITLE_FRAME
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR TITLE_FRAME
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BEQ .t_press
  LDX #$01
  AND #%00100000
  BEQ .t_np
  LDX #$02
.t_np:
  STX NPL
  LDA FRAME_CNT                ; the moment you press seeds the random generator
  ORA #$01
  STA RND
  LDA #CMD_GAME
  STA SND_CMD
  JMP NEW_GAME

; rows 9-18 of the title and the sprites beside them (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00
  LDY #$00
.ti_s:
  LDA TITLE_SY,X
  STA SAT_BUFFER,Y
  LDA TITLE_SX,X
  STA SAT_BUFFER+1,Y
  LDA TITLE_SN,X
  STA SAT_BUFFER+2,Y
  LDA TITLE_SC,X
  STA SAT_BUFFER+3,Y
  INY
  INY
  INY
  INY
  INX
  CPX #TITLE_NS
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; one frame of the title: Spike hops on the spot, the others move;
; every 8 s the title page and the table of the records take turns
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR REC_TICK
  BCC .tf_a
  LDA REC_PG
  BEQ .tf_p
  JSR HIDE_SPRITES
  JSR REC_SHOW
  BRA .tf_a
.tf_p:
  JSR TITLE_PAGE
.tf_a:
  LDA SATB
  CMP #2
  BCC .tf_e
  LDX #0                       ; the second frame of every sprite in turn
  LDY #0
.tf_s:
  LDA TITLE_SN,X
  STA T0
  LDA FRAME_CNT
  AND #16
  BEQ .tf_n
  LDA T0
  CLC
  ADC TITLE_SA,X
  STA T0
.tf_n:
  LDA T0
  STA SAT_BUFFER+2,Y
  INY
  INY
  INY
  INY
  INX
  CPX #TITLE_NS
  BNE .tf_s
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: level 1, 3 lives for every player
; ===============================================================
NEW_GAME:
  JSR VDP_INT_OFF
  LDA #<GFX_GAME               ; the tiles of the lanes (the title used some)
  STA PTR2
  LDA #>GFX_GAME
  STA PTR2+1
  JSR LOAD_BLOCKS
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  DEX
  BPL .ng_p
  STZ LOSTN
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ LEVEL
  STZ HOMES
  STZ XTRA
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his level, then a hedgehog at the meadow
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

LEVEL_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the level is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_LEVEL                ; palette, tapes, speeds, the animals
  JSR DRAW_FIELD
  JSR DRAW_HUD
  JSR TRIP_INIT
  STZ GSTATE                   ; (Spike shows while the level is announced)
  JSR MSG_LEVEL
  JSR LANES_DRAW
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA FIRSTT                   ; the tune at the first turn
  BEQ .ls_short
  STZ FIRSTT
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ls_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ls_t
  BRA .ls_w
.ls_short:
  LDA #100
  JSR WAIT_FRAMES
.ls_w:
  LDA #10
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  JSR VDP_INT_ON
  LDA #CMD_GAME
  STA SND_CMD
  STZ GSTATE


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR LANES_DRAW               ; the lanes that moved, top to bottom, ahead of the beam
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  EOR JPREV
  AND JOYC
  STA JNEW
  LDA JOYC
  STA JPREV
  JSR LANES_MOVE               ; where the lanes go (Spike rides his log)
  JSR DIVE_TICK
  INC TICKS
  LDA GSTATE
  BNE .gl_ns
  JSR HERO
  LDA GSTATE
  BNE .gl_ns
  JSR ANIMALS
  JSR HERO_CHECK
  JSR TIMER_TICK
.gl_ns:
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  LDA GSTATE
  CMP #2
  BEQ .gl_home
  CMP #3
  BEQ .gl_full
  JMP LOSE_LIFE
.gl_home:
  JSR TRIP_INIT                ; the next hedgehog from the meadow
  STZ GSTATE
  JMP GAME_LOOP
.gl_full:
  JMP LEVEL_CLEAR


; ===============================================================
;  THE HEDGE IS FULL: the tune, the next level
; ===============================================================
LEVEL_CLEAR:
  JSR HIDE_SPRITES
  LDA #3
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
.lc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .lc_t
  LDA #20
  JSR WAIT_FRAMES
  LDA LEVEL                    ; the next level (98 at most)
  CMP #98
  BCS .lc_n
  INC LEVEL
.lc_n:
  STZ HOMES
  JSR SAVE_PLAYER
  JMP LEVEL_START

LOSE_LIFE:
  INC LOSTN
  LDX CURP
  DEC LIVES,X
  JSR SAVE_PLAYER
  LDA #20
  JSR WAIT_FRAMES
  LDA NPL                      ; the other player, if he still has lives
  CMP #$02
  BNE .ll_same
  LDA CURP
  EOR #$01
  TAX
  LDA LIVES,X
  BEQ .ll_same
  STX CURP
  JMP TURN_START
.ll_same:
  LDX CURP
  LDA LIVES,X
  BEQ GAME_OVER
  JSR VDP_INT_OFF              ; the same player: a new hedgehog, the lanes go on
  JSR TRIP_INIT
  LDX CURP
  JSR DRAW_STATUS
  JSR VDP_INT_ON
  STZ GSTATE
  JMP GAME_LOOP

GAME_OVER:
  LDA #W_OVER
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  LDA NPL
  CMP #2
  BNE .go_1
  LDA #<TXT_OVERP
  STA TP
  LDA #>TXT_OVERP
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.go_1:
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  LDX #$00                     ; every player: into the table of the records?
.go_r:
  STX REC_PL
  LDA SCL,X
  STA REC_SC
  LDA SCM,X
  STA REC_SC+1
  LDA SCH,X
  STA REC_SC+2
  STZ REC_SC+3
  TXA                          ; extra byte: the level reached
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE,Y
  INC A
  STA REC_EX
  JSR REC_CHECK
  LDX REC_PL
  INX
  CPX NPL
  BNE .go_r
  JSR REC_SAVE                 ; one write on the SD
  JSR REC_HISC
  JMP TITLE

; the best row of the table is the record on the HUD
REC_HISC:
  LDA REC_TAB
  STA HISC
  LDA REC_TAB+1
  STA HISC+1
  LDA REC_TAB+2
  STA HISC+2
  RTS

; hooks of lib_records.asm
REC_XY = NT_XY
REC_CLS:                       ; the sign screen: empty, with the scores on top
  JSR CLEAR_NT
  JMP DRAW_TOP
REC_SND:                       ; A = 0 a letter, 1 the initials confirmed
  PHX
  LDX #2
  CMP #0
  BNE .rn_s
  LDA #W_KEY
  BRA .rn_p
.rn_s:
  LDA #W_SIGN
.rn_p:
  JSR SFX_WHISTLE
  PLX
  RTS
REC_NAME:  .byte "HEDGE HOP       "
REC_HEAD:  .byte "BEST HOPPERS",0
REC_XLBL:  .byte "LEVEL ",0


; ===============================================================
;  HUD: row 0 (scores), row 23 (lives, time, level)
; ===============================================================
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #0
  LDY #15
  JSR NT_XY
  LDA HISC+2
  JSR PUT_2
  LDA HISC+1
  JSR PUT_2
  LDA HISC
  JSR PUT_2
  LDX #$00
  JSR DRAW_SCORE
  LDA NPL
  CMP #2
  BNE .dt_e
  LDA #<TXT_TOP2
  STA TP
  LDA #>TXT_TOP2
  STA TP+1
  JSR PRINT
  LDX #$01
  JMP DRAW_SCORE
.dt_e:
  RTS

; X = player: his score on row 0 (keeps X)
DRAW_SCORE:
  PHX
  LDY SC_COL,X
  LDX #0
  JSR NT_XY
  PLX
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

; row 23: the spare lives (cols 0-5), LEVEL nn (cols 23-30), the player (col 31)
DRAW_STATUS:
  LDX #23
  LDY #0
  JSR NT_XY
  LDX CURP                     ; the spare lives (at most 6)
  LDA LIVES,X
  BEQ .ds_z
  DEC A
.ds_z:
  STA T0
  LDY #0
.ds_i:
  LDA #$20
  CPY T0
  BCS .ds_w
  LDA #T_LIFE
.ds_w:
  STA VDATA
  INY
  CPY #6
  BNE .ds_i
  LDX #23
  LDY #23
  JSR NT_XY
  LDX #0
.ds_l:
  LDA TXT_LEVELH,X
  STA VDATA
  INX
  CPX #6
  BNE .ds_l
  LDA LEVEL
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDA NPL                      ; P1 / P2 at the right end with 2 players
  CMP #2
  BNE .ds_r
  LDX #23
  LDY #31
  JSR NT_XY
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ds_r:
  RTS

; A = 1-99: the number where the VDP points (no leading zero)
PUT_NUM:
  JSR BIN2BCD
  CMP #$10
  BCC .pn_1
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #$30
  STA VDATA
  PLA
  AND #$0F
.pn_1:
  ORA #$30
  STA VDATA
  RTS

DRAW_HUD:
  JSR DRAW_TOP
  JMP DRAW_STATUS

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives and level, 4 the hedge; the time bar; the holes
  JSR DRAW_BAR
  LDA HOLED
  BEQ .uh_0
  LDX #0
.uh_k:
  LSR HOLED
  BCC .uh_n
  JSR DRAW_HOLE
.uh_n:
  INX
  CPX #NHOLE
  BNE .uh_k
  STZ HOLED
.uh_0:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  PHA
  AND #1
  BEQ .uh_l
  LDX CURP
  JSR DRAW_SCORE
.uh_l:
  PLA
  PHA
  AND #2
  BEQ .uh_h
  JSR DRAW_STATUS
.uh_h:
  PLA
  AND #4
  BEQ .uh_r
  JSR DRAW_HEDGE
.uh_r:
  RTS

; the time bar on row 23, columns 7-20: TIME / 16 pixels (14 tiles), red under 5 seconds
DRAW_BAR:
  LDA TIME+1                   ; pixels = TIME / 16
  STA T0
  LDA TIME
  LSR T0
  ROR A
  LSR T0
  ROR A
  LSR T0
  ROR A
  LSR T0
  ROR A
  CMP BARPX
  BEQ .db_r
  STA BARPX
  STA T1                       ; pixels left to draw
  LDA #T_BAR                   ; green, or red under 300 frames
  LDX TIME+1
  BNE .db_g
  LDX TIME
  CPX #<300
  BCS .db_g
  LDA #T_BAR+9
.db_g:
  STA T2
  LDX #23
  LDY #7
  JSR NT_XY
  LDX #14
.db_t:
  LDA T1
  CMP #8
  BCC .db_p
  LDA #8
.db_p:
  STA T3
  CLC
  ADC T2
  STA VDATA
  LDA T1
  SEC
  SBC T3
  STA T1
  DEX
  BNE .db_t
.db_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: his block
  LDA CURP
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA LEVEL,Y
  STA PSAVE,X
  INX
  INY
  CPY #PBLOCK
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  TXA
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.lp_b:
  LDA PSAVE,X
  STA LEVEL,Y
  INX
  INY
  CPY #PBLOCK
  BNE .lp_b
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 10000
ADD_SCORE:
  PHX
  PHY
  LDX CURP
  SED
  CLC
  LDA SCL,X
  ADC PTS_L
  STA SCL,X
  LDA SCM,X
  ADC PTS_M
  STA SCM,X
  LDA SCH,X
  ADC PTS_H
  STA SCH,X
  CLD
  LDA XTRA
  BNE .as_d
  LDA SCH,X
  BEQ .as_d
  INC XTRA
  INC LIVES,X
  LDA #2
  TSB HUDD
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  THE LEVEL: palette, tapes, speeds, animals
; ===============================================================
SET_LEVEL:
  LDA LEVEL
  AND #3
  STA PAL
  LDX LEVEL                    ; speeds and tapes stop growing at level NLEV
  CPX #NLEV
  BCC .sl_x
  LDX #NLEV-1
.sl_x:
  STX T4
  LDA SETOF,X
  STA SET
  JSR BUILD_REMAP
  JSR LOAD_COLOURS
  LDA REMAP+$04                ; the water in this palette
  AND #$0F
  STA WATERC
  ; the lanes
  LDA T4                       ; T4 = level * 8, T5 = set * 8
  ASL A
  ASL A
  ASL A
  STA T4
  LDA SET
  ASL A
  ASL A
  ASL A
  STA T5
  LDX #0
.sl_l:
  TXA
  CLC
  ADC T5
  TAY
  LDA TAPE_LO,Y
  STA LTP_LO,X
  LDA TAPE_HI,Y
  STA LTP_HI,X
  TXA
  CLC
  ADC T4
  TAY
  LDA SPD_L,Y
  STA SP_L,X
  LDA SPD_H,Y
  STA SP_H,X
  LDA LANE_T,X
  ASL A
  ASL A
  ASL A
  STA LTY,X
  STZ P_F,X
  JSR NEXT_RND                 ; every lane starts somewhere else
  STA P_L,X
  AND #1
  STA P_H,X
  LDA #$FF                     ; (drawn at the first move)
  STA Q_L,X
  LDA #1
  STA LDIRTY,X
  INX
  CPX #NLANE
  BNE .sl_l
  JSR BUILD_KT
  JSR LANES_MOVE0
  ; the diving pads
  STZ DIVEI
  STZ DIVES
  LDA DSEQ_T
  STA DIVET
  JSR DIVE_SET
  ; the animals
  STZ FOXON
  LDA LEVEL
  BEQ .sl_f
  INC FOXON                    ; the fox from level 2
.sl_f:
  STZ FOXX
  STZ FOXD
  LDA #$FF
  STA HERH
  STA BEETH
  LDA #50
  STA HERT
  LDA #30
  STA BEETT
  STZ SNON
  LDA LEVEL
  CMP #3
  BCC .sl_s
  INC SNON                     ; the snake from level 4
.sl_s:
  STZ SNO
  STZ SND
  STZ BABY
  LDA #60
  STA BABT
  STZ HOLED
  RTS

; REMAP = every colour byte through the palette PAL
BUILD_REMAP:
  LDA PAL
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0
  LDX #0
.br_l:
  TXA                          ; the high nibble
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T0
  TAY
  LDA PALS,Y
  ASL A
  ASL A
  ASL A
  ASL A
  STA T1
  TXA                          ; the low nibble
  AND #$0F
  ORA T0
  TAY
  LDA PALS,Y
  ORA T1
  STA REMAP,X
  INX
  BNE .br_l
  RTS

; the colour blocks GFX_GAMEC through REMAP (display off)
LOAD_COLOURS:
  LDA #<GFX_GAMEC
  STA PTR2
  LDA #>GFX_GAMEC
  STA PTR2+1
.lc_b:
  LDY #$00
  LDA (PTR2),Y
  BEQ .lc_e
  INY
  LDA (PTR2),Y
  STA VREG
  INY
  LDA (PTR2),Y
  STA VREG
  INY
  LDA (PTR2),Y
  STA T2
  INY
  LDA (PTR2),Y
  STA T3
  INY
  LDA (PTR2),Y
  STA PTR
  INY
  LDA (PTR2),Y
  STA PTR+1
  LDA PTR2
  CLC
  ADC #7
  STA PTR2
  BCC .lc_k
  INC PTR2+1
.lc_k:
  LDY #0
.lc_c:
  LDA (PTR),Y
  TAX
  LDA REMAP,X
  STA VDATA
  INY
  BNE .lc_y
  INC PTR+1
.lc_y:
  LDA T2
  BNE .lc_d
  DEC T3
.lc_d:
  DEC T2
  LDA T2
  ORA T3
  BNE .lc_c
  BRA .lc_b
.lc_e:
  RTS

; KT of every lane: the base tile of the pair of parts (cell j, cell j+1), j = 0-95
BUILD_KT:
  LDX #0
.bk_l:
  STX T4
  LDA LTP_LO,X
  STA PTR
  LDA LTP_HI,X
  STA PTR+1
  LDA KT_LO,X
  STA TP
  LDA KT_HI,X
  STA TP+1
  LDA LANE_T,X                 ; PTR2 = PAIRC + type * 64
  STZ T1
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ROL T1
  ASL A
  ROL T1
  CLC
  ADC #<PAIRC
  STA PTR2
  LDA T1
  ADC #>PAIRC
  STA PTR2+1
  LDX #0
.bk_j:
  TXA
  AND #63
  TAY
  LDA (PTR),Y
  ASL A
  ASL A
  ASL A
  STA T0
  TXA
  INC A
  AND #63
  TAY
  LDA (PTR),Y
  ORA T0
  TAY
  LDA (PTR2),Y
  STA T0
  TXA
  TAY
  LDA T0
  STA (TP),Y
  INX
  CPX #96
  BNE .bk_j
  LDX T4
  INX
  CPX #NLANE
  BNE .bk_l
  RTS


; ===============================================================
;  THE FIELD: hedge, bank, meadow (display off)
; ===============================================================
DRAW_FIELD:
  JSR CLEAR_NT
  JSR DRAW_HEDGE
  LDX #11
  JSR GRASS_ROW
  LDX #12
  JSR GRASS_ROW
  LDX #21
  JSR GRASS_ROW
  LDX #22
  JMP GRASS_ROW

; X = row: grass tiles, a few tufts and flowers
GRASS_ROW:
  STX T2
  LDY #0
  JSR NT_XY
  LDA T2
  ASL A
  ASL A
  ADC T2
  STA T3
  LDX #0
.gr_c:
  TXA
  CLC
  ADC T3
  AND #15
  TAY
  LDA GRASSP,Y
  STA VDATA
  INX
  CPX #32
  BNE .gr_c
  RTS

; rows 1-2: the hedge, the holes (empty, a hedgehog at home, a beetle)
DRAW_HEDGE:
  LDX #1
  JSR .dh_row
  LDX #2
.dh_row:
  STX T2
  LDY #0
  JSR NT_XY
  LDA T2                       ; row 2: the bottom half (+2)
  DEC A
  ASL A
  STA T3
  LDX #0
.dh_c:
  LDA HEDGE_MAP,X
  BMI .dh_h
  PHA                          ; hole h * 2 + right half
  LSR A
  TAY
  LDA #T_HOLE
  CPY BEETH
  BNE .dh_b
  LDA #T_BEET
.dh_b:
  STA T4
  LDA BITS,Y
  AND HOMES
  BEQ .dh_o
  LDA #T_HOME
  STA T4
.dh_o:
  PLA
  AND #1
  ORA T3
  CLC
  ADC T4
  BRA .dh_w
.dh_h:
  LDA #T_HEDGE
.dh_w:
  STA VDATA
  INX
  CPX #32
  BNE .dh_c
  RTS

; X = hole: its 2 x 2 tiles (empty, a hedgehog at home, a beetle)
DRAW_HOLE:
  STX T4
  LDA #T_HOLE
  CPX BEETH
  BNE .dho_b
  LDA #T_BEET
.dho_b:
  STA T5
  LDA BITS,X
  AND HOMES
  BEQ .dho_o
  LDA #T_HOME
  STA T5
.dho_o:
  LDA HOLE_X,X                 ; column = x / 8
  LSR A
  LSR A
  LSR A
  STA T3
  LDX #1
  TAY
  JSR NT_XY
  LDA T5
  STA VDATA
  INC A
  NOP
  NOP
  STA VDATA
  LDX #2
  LDY T3
  JSR NT_XY
  LDA T5
  CLC
  ADC #2
  STA VDATA
  INC A
  NOP
  NOP
  STA VDATA
  LDX T4
  RTS

; rows 11-12 (the bank): LEVEL nn and the time of the day; PLAYER n with 2 players
MSG_LEVEL:
  LDX #11
  LDY #12
  JSR NT_XY
  LDX #0
.ml_l:
  LDA TXT_LEVELH,X
  STA VDATA
  INX
  CPX #6
  BNE .ml_l
  LDA LEVEL
  INC A
  JSR PUT_NUM
  LDX #12
  LDY #12
  JSR NT_XY
  LDX PAL
  LDA DAY_LO,X
  STA PTR
  LDA DAY_HI,X
  STA PTR+1
  LDY #0
.ml_d:
  LDA (PTR),Y
  BEQ .ml_p
  STA VDATA
  INY
  BRA .ml_d
.ml_p:
  LDA NPL
  CMP #2
  BNE .ml_r
  LDX #11
  LDY #2
  JSR NT_XY
  LDX #0
.ml_n:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .ml_n
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ml_r:
  RTS

MSG_CLEAR:
  LDX #11
  JSR GRASS_ROW
  LDX #12
  JMP GRASS_ROW


; ===============================================================
;  THE LANES
; ===============================================================
; the lanes that moved: their 2 rows of the name table (top to bottom)
LANES_DRAW:
  STZ NSTEP
  LDX #0
.ld_l:
  LDA LDIRTY,X
  BNE .ld_go
  JMP .ld_n
.ld_go:
  STZ LDIRTY,X
  INC NSTEP
  STX T4
  LDA Q_H,X                    ; k = Q >> 3 (0-63): the first cell; s = (Q AND 6) / 2
  LSR A
  LDA Q_L,X
  ROR A
  LSR A
  LSR A
  CLC
  ADC KT_LO,X
  STA PTR
  LDA KT_HI,X
  ADC #0
  STA PTR+1
  LDA Q_L,X
  AND #6
  LSR A
  STA T5
  LDA LANE_ROW,X
  STA T3
  TAX
  LDY #0
  JSR NT_XY
  LDY #0
  CLC
.ld_a:
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  CPY #32
  BNE .ld_a
  LDX T3
  INX
  LDY #0
  JSR NT_XY
  LDA T5
  CLC
  ADC #4
  STA T5
  LDY #0
  CLC
.ld_b:
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  LDA (PTR),Y
  ADC T5
  STA VDATA
  INY
  CPY #32
  BNE .ld_b
  LDX T4
.ld_n:
  INX
  CPX #NLANE
  BEQ .ld_x
  JMP .ld_l
.ld_x:
  RTS

; the lanes move: position + or - speed; a new even position is drawn at the next frame
; and Spike, sitting on a log or a pad, goes with it
LANES_MOVE:
  STZ T7                       ; lanes moved in this frame (at most MAXDRAW: the others catch up)
  STZ T6
.lm_l:
  LDA FRAME_CNT                ; a different lane first every frame
  CLC
  ADC T6
  AND #7
  TAX
  LDA LANE_LEFT,X
  BEQ .lm_r
  LDA P_F,X                    ; the things go left: the window moves right
  CLC
  ADC SP_L,X
  STA P_F,X
  LDA P_L,X
  ADC SP_H,X
  STA P_L,X
  LDA P_H,X
  ADC #0
  AND #1
  STA P_H,X
  BRA .lm_q
.lm_r:
  LDA P_F,X
  SEC
  SBC SP_L,X
  STA P_F,X
  LDA P_L,X
  SBC SP_H,X
  STA P_L,X
  LDA P_H,X
  SBC #0
  AND #1
  STA P_H,X
.lm_q:
  LDA P_L,X                    ; even position: moved?
  AND #$FE
  CMP Q_L,X
  BEQ .lm_n
  LDY T7
  CPY #MAXDRAW
  BCS .lm_n
  INC T7
  STA T0
  SEC                          ; T1 = how far (signed, a few pixels)
  SBC Q_L,X
  STA T1
  LDA T0
  STA Q_L,X
  LDA P_H,X
  STA Q_H,X
  LDA #1
  STA LDIRTY,X
  LDA GSTATE                   ; Spike rides it?
  BNE .lm_n
  LDA HT
  BEQ .lm_s
  LDA HDY                      ; (a hop to the side rides too)
  BNE .lm_n
.lm_s:
  CPX HLANE
  BNE .lm_n
  LDA HX
  SEC
  SBC T1
  STA HX
  CMP #241                     ; off the screen: lost
  BCC .lm_n
  LDA #1
  STA OUTF
  LDA HX                       ; (stays at the edge)
  CMP #248
  BCS .lm_0
  LDA #240
  BRA .lm_e
.lm_0:
  LDA #0
.lm_e:
  STA HX
.lm_n:
  INC T6
  LDA T6
  CMP #NLANE
  BEQ .lm_x
  JMP .lm_l
.lm_x:
  RTS

; the first position of every lane (no ride, all drawn)
LANES_MOVE0:
  LDX #0
.l0_l:
  LDA P_L,X
  AND #$FE
  STA Q_L,X
  LDA P_H,X
  STA Q_H,X
  LDA #1
  STA LDIRTY,X
  INX
  CPX #NLANE
  BNE .l0_l
  RTS

; A = x on the screen, T5 = lane: A = what is there (0 nothing, 1 solid, 2 a diving pad)
PART_AT:
  LDX T5
  CLC
  ADC Q_L,X
  STA T0
  LDA Q_H,X
  ADC #0
  LSR A
  LDA T0
  ROR A
  LSR A
  LSR A
  AND #63
  TAY
  LDA LTP_LO,X
  STA PTR2
  LDA LTP_HI,X
  STA PTR2+1
  LDA (PTR2),Y
  CLC
  ADC LTY,X
  TAY
  LDA SOLID,Y
  RTS

; the diving pads: up, sinking, ripples, under, and back
DIVE_TICK:
  DEC DIVET
  BNE .dt_r
  LDX DIVEI
  INX
  CPX #6
  BCC .dt_i
  LDX #0
.dt_i:
  STX DIVEI
  LDA DSEQ_S,X
  STA DIVES
  LDA DSEQ_T,X
  STA DIVET
  JMP DIVE_SET
.dt_r:
  RTS

; the colour of the diving pads (third 0): state colour on the water, through the palette
DIVE_SET:
  LDX DIVES
  LDA DIVE_FG,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #4
  TAX
  LDA REMAP,X
  PHA
  LDA #<($2000 + DIVE_LO * 8)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >($2000 + DIVE_LO * 8))
  STA VREG
  PLA
  LDX #<(DIVE_N * 64)
.ds_l:
  STA VDATA
  DEX
  BNE .ds_l
  RTS


; ===============================================================
;  SPIKE
; ===============================================================
; a new hedgehog at the meadow
TRIP_INIT:
  LDA #HX0
  STA HX
  STZ HY
  LDA #167
  STA HPY
  STZ HDIR
  STZ HT
  STZ HMAX
  STZ OUTF
  STZ HOLD
  LDA #$FF
  STA HLANE
  STA BARPX
  LDA #$0F                     ; a direction held does not hop at once
  STA JPREV
  LDA #<TIME0
  STA TIME
  LDA #>TIME0
  STA TIME+1
  RTS

HERO:
  LDA HT
  BEQ .h_sit
  LDA HX                       ; in the air
  CLC
  ADC HDX
  STA HX
  LDA HPY
  CLC
  ADC HDY
  STA HPY
  DEC HT
  BNE .h_r
  LDA HDY                      ; landed: a lane to ride (after a hop to the side, the same one)
  BEQ .h_side
  LDX HY
  LDA HY_LANE,X
  STA HLANE
.h_side:
  LDA HY                       ; a new step forward: 10 points
  CMP HMAX
  BEQ .h_l
  BCC .h_l
  STA HMAX
  LDA #$10
  LDY #0
  JSR ADD_PTS
.h_l:
  LDA HY
  CMP #10
  BNE .h_r
  JMP AT_HEDGE
.h_r:
  RTS
.h_sit:
  LDA JNEW                     ; a new press, or a direction held (one hop every 10 frames)
  AND #$0F
  BNE .h_go
  LDA JOYC
  AND #$0F
  BEQ .h_rel
  INC HOLD
  LDA HOLD
  CMP #12
  BCC .h_r
  LDA #4
  STA HOLD
  LDA JOYC
  AND #$0F
  BRA .h_dir
.h_rel:
  STZ HOLD
  RTS
.h_go:
  STZ HOLD
.h_dir:
  LSR A
  BCS .h_up
  LSR A
  BCS .h_down
  LSR A
  BCS .h_left
  LSR A
  BCS .h_right
  RTS
.h_up:
  LDA HY
  CMP #10
  BCS .h_r
  INC HY
  LDA #$FE
  STA HDY
  STZ HDX
  LDA #8
  STA HT
  STZ HDIR
  BRA .h_v
.h_down:
  LDA HY
  BEQ .h_r
  DEC HY
  LDA #2
  STA HDY
  STZ HDX
  LDA #8
  STA HT
  LDA #2
  STA HDIR
.h_v:
  LDA #$FF                     ; between two lanes: rides nothing
  STA HLANE
  BRA .h_snd
.h_left:
  LDA HX
  CMP #8
  BCC .h_r
  LDA #$FE
  STA HDX
  STZ HDY
  LDA #4
  STA HT
  LDA #3
  STA HDIR
  BRA .h_snd
.h_right:
  LDA HX
  CMP #233
  BCS .h_r
  LDA #2
  STA HDX
  STZ HDY
  LDA #4
  STA HT
  LDA #1
  STA HDIR
.h_snd:
  LDA #W_HOP                   ; the two hop sounds take turns
  LDX HY
  CPX #5
  BCC .h_s1
  LDA #W_HOP2
.h_s1:
  LDX #2
  JMP SFX_WHISTLE

; what Spike meets: the traffic, the water, the edge, the animals
HERO_CHECK:
  LDA OUTF
  BEQ .hc_road
  STZ OUTF
  LDA #3
  LDY #1
  JMP KILL
.hc_road:
  LDA HPY                      ; the lane under his middle (in the air too)
  CLC
  ADC #9
  LSR A
  LSR A
  LSR A
  TAX
  LDA ROW_LANE,X
  CMP #4
  BCC .hc_river
  CMP #8
  BCS .hc_bank
  STA T5
  LDA HX
  CLC
  ADC #3
  JSR PART_AT
  BNE .hc_sq
  LDA HX
  CLC
  ADC #12
  JSR PART_AT
  BEQ .hc_bank
.hc_sq:
  LDA #1
  LDY #0
  JMP KILL
.hc_river:
  LDX HT                       ; in the air: not yet
  BNE .hc_bank
  LDA HLANE
  CMP #4
  BCS .hc_bank
  STA T5
  LDA HX
  CLC
  ADC #8
  JSR PART_AT
  BEQ .hc_wet
  CMP #2
  BNE .hc_bank
  LDA DIVES
  CMP #3
  BNE .hc_bank
.hc_wet:
  LDA #2
  LDY #1
  JMP KILL
.hc_bank:
  LDA FOXON                    ; the fox on the bank
  BEQ .hc_sn
  LDA HY
  CMP #5
  BNE .hc_sn
  LDA FOXX
  JSR NEAR
  BCS .hc_sn
  LDA #5
  LDY #0
  JMP KILL
.hc_sn:
  LDA SNON                     ; the snake on its log
  BEQ .hc_by
  LDA HLANE
  CMP #2
  BNE .hc_by
  LDA SNX+1
  BNE .hc_by
  LDA SNX
  JSR NEAR
  BCS .hc_by
  LDA #7
  LDY #0
  JMP KILL
.hc_by:
  LDA BABY                     ; the little hedgehog: he takes it on his back
  CMP #1
  BNE .hc_r
  LDA HLANE
  CMP #3
  BNE .hc_r
  LDA HT
  BNE .hc_r
  LDA BABX+1
  BNE .hc_r
  LDA BABX
  JSR NEAR
  BCS .hc_r
  LDA #2
  STA BABY
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
.hc_r:
  RTS

; A = x of something: C = 0 when it is less than 12 pixels from Spike
NEAR:
  SEC
  SBC HX
  BCS .nr_p
  EOR #$FF
  INC A
.nr_p:
  CMP #12
  RTS

; A = what (DEATHS), Y = 0 squashed, 1 in the water: a life is lost
KILL:
  STA DEATHS
  STY DEATHK
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  STZ HT
  LDA BABY                     ; the little one carried goes back to its log later
  CMP #2
  BNE .k_s
  STZ BABY
  LDA #60
  STA BABT
.k_s:
  LDX #2
  LDA DEATHS
  CMP #8
  BEQ .k_t
  LDA DEATHK
  BEQ .k_q
  LDA #S_SPLASH
  JMP SFX_BOOM
.k_q:
  LDA #S_CRUNCH
  JSR SFX_BOOM
  LDA #W_SQUASH
  JMP SFX_WHISTLE
.k_t:
  LDA #W_TIMEUP
  JMP SFX_WHISTLE

; Spike landed on the hedge row: a free hole, or the hedge
AT_HEDGE:
  LDX #0
.ah_h:
  LDA HX
  SEC
  SBC HOLE_X,X
  BCS .ah_p
  EOR #$FF
  INC A
.ah_p:
  CMP #9
  BCC .ah_f
  INX
  CPX #NHOLE
  BNE .ah_h
  LDA #W_BUMP                  ; into the hedge
  LDX #2
  JSR SFX_WHISTLE
  LDA #4
  LDY #0
  JMP KILL
.ah_f:
  STX HOMEN
  LDA HOLE_X,X
  STA HX
  LDA BITS,X
  AND HOMES
  BEQ .ah_e
  LDA #4                       ; somebody is already there
  LDY #0
  JMP KILL
.ah_e:
  CPX HERH
  BNE .ah_ok
  LDA #6                       ; the heron
  LDY #0
  JMP KILL
.ah_ok:
  LDA BITS,X
  TSB HOMES
  STZ BONUSF
  LDA #$50                     ; 50 points
  LDY #0
  JSR ADD_PTS
  JSR TIME_BONUS
  LDX HOMEN
  CPX BEETH
  BNE .ah_b
  LDA #$FF
  STA BEETH
  LDA #1
  TSB BONUSF
  LDA #0                       ; 200
  LDY #2
  JSR ADD_PTS
.ah_b:
  LDA BABY
  CMP #2
  BNE .ah_c
  STZ BABY
  LDA #80
  STA BABT
  LDA #2
  TSB BONUSF
  LDA #0
  LDY #2
  JSR ADD_PTS
.ah_c:
  LDX HOMEN                    ; that hole again
  LDA BITS,X
  TSB HOLED
  LDA BONUSF
  BEQ .ah_s
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
.ah_s:
  LDA HOMES
  CMP #%00011111
  BEQ .ah_all
  LDA #2
  STA GSTATE
  LDA #40
  STA GT
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  RTS
.ah_all:
  LDA #0                       ; 1000 for the full hedge
  LDY #$10
  JSR ADD_PTS
  LDA #3
  STA GSTATE
  LDA #20
  STA GT
  LDA #W_HOME
  LDX #2
  JMP SFX_WHISTLE

; 10 points every half second left
TIME_BONUS:
  LDA TIME+1                   ; TIME / 32 (0-56)
  STA T1
  LDA TIME
  LDX #5
.tb_l:
  LSR T1
  ROR A
  DEX
  BNE .tb_l
  CMP #0
  BEQ .tb_r
  JSR BIN2BCD
  PHA
  ASL A
  ASL A
  ASL A
  ASL A
  STA PTS_L
  PLA
  LSR A
  LSR A
  LSR A
  LSR A
  STA PTS_M
  STZ PTS_H
  JMP ADD_SCORE
.tb_r:
  RTS

; the clock of the hedgehog; the last 5 seconds tick
TIMER_TICK:
  LDA TIME
  ORA TIME+1
  BNE .tt_d
  LDA #8
  LDY #0
  JMP KILL
.tt_d:
  LDA TIME
  BNE .tt_l
  DEC TIME+1
.tt_l:
  DEC TIME
  LDA TIME+1
  BNE .tt_r
  LDA TIME
  CMP #<300
  BCS .tt_r
  AND #63
  BNE .tt_r
  LDA #W_TICK
  LDX #2
  JMP SFX_WHISTLE
.tt_r:
  RTS


; ===============================================================
;  THE ANIMALS: fox, heron, beetle, snake, little hedgehog
; ===============================================================
ANIMALS:
  LDA FOXON                    ; the fox trots along the bank
  BEQ .an_sn
  LDA FOXF
  CLC
  ADC #$A0
  STA FOXF
  BCC .an_sn
  LDA FOXD
  BNE .an_fl
  INC FOXX
  LDA FOXX
  CMP #240
  BCC .an_sn
  INC FOXD
  BRA .an_y
.an_fl:
  DEC FOXX
  BNE .an_sn
  STZ FOXD
.an_y:
  LDA #W_YIP
  LDX #2
  JSR SFX_WHISTLE
.an_sn:
  LDA SNON                     ; the snake goes up and down its log
  BEQ .an_bb
  LDA SNF
  CLC
  ADC #$70
  STA SNF
  BCC .an_sx
  LDX SET
  LDA SND
  BNE .an_sd
  INC SNO
  LDA SNO
  CMP SNK_LEN,X
  BCC .an_sx
  INC SND
  BRA .an_sx
.an_sd:
  DEC SNO
  BNE .an_sx
  STZ SND
.an_sx:
  LDX SET                      ; on the screen: its world x minus the lane
  LDA SNK_A,X
  CLC
  ADC SNO
  STA T0
  LDA SNK_AH,X
  ADC #0
  STA T1
  LDX #2
  JSR TO_SCREEN
  STA SNX
  STY SNX+1
.an_bb:
  LDA BABY                     ; the little hedgehog on its log
  CMP #1
  BNE .an_t
  LDX SET
  LDA BAB_X,X
  STA T0
  LDA BAB_XH,X
  STA T1
  LDX #3
  JSR TO_SCREEN
  STA BABX
  STY BABX+1
.an_t:
  LDA TICKS                    ; the slow timers: every 4 frames
  AND #3
  BEQ .an_slow
  RTS
.an_slow:
  ; the heron (from level 3): lands in a free hole, stays, goes
  LDA LEVEL
  CMP #2
  BCC .an_be
  DEC HERT
  BNE .an_be
  LDA HERH
  BMI .an_hl
  LDA #$FF
  STA HERH
  JSR NEXT_RND
  AND #63
  ADC #50
  STA HERT
  BRA .an_be
.an_hl:
  JSR FREE_HOLE
  STA HERH
  LDA #70
  STA HERT
.an_be:
  ; the beetle: a few seconds in a free hole
  DEC BEETT
  BNE .an_ba
  LDA BEETH
  BMI .an_bl
  TAX
  LDA BITS,X                    ; its hole again
  TSB HOLED
  LDA #$FF
  STA BEETH
  JSR NEXT_RND
  AND #63
  ADC #90
  STA BEETT
  BRA .an_bh
.an_bl:
  JSR FREE_HOLE
  STA BEETH
  LDA #75
  STA BEETT
  LDX BEETH
  BMI .an_ba
  LDA BITS,X
  TSB HOLED
  BRA .an_ba
.an_bh:
.an_ba:
  ; the little hedgehog: waits on its log for 10 seconds now and then
  LDA BABY
  CMP #2
  BEQ .an_r
  DEC BABT
  BNE .an_r
  LDA BABY
  BEQ .an_bon
  STZ BABY
  JSR NEXT_RND
  AND #63
  ADC #100
  STA BABT
  RTS
.an_bon:
  INC BABY
  LDA #150
  STA BABT
.an_r:
  RTS

; A = a free hole (no hedgehog, no heron, no beetle), or $FF
FREE_HOLE:
  JSR NEXT_RND
  AND #7
  CMP #NHOLE
  BCC .fh_s
  SBC #3
.fh_s:
  STA T0
  LDY #NHOLE
.fh_l:
  LDX T0
  LDA BITS,X
  AND HOMES
  BNE .fh_n
  CPX HERH
  BEQ .fh_n
  CPX BEETH
  BEQ .fh_n
  TXA
  RTS
.fh_n:
  INX
  CPX #NHOLE
  BCC .fh_k
  LDX #0
.fh_k:
  STX T0
  DEY
  BNE .fh_l
  LDA #$FF
  RTS

; T0 / T1 = world x (0-511), X = lane: A = x on the screen, Y = 0 if on the screen (0-240)
TO_SCREEN:
  LDA T0
  SEC
  SBC Q_L,X
  STA T0
  LDA T1
  SBC Q_H,X
  AND #1
  TAY
  BNE .ts_r
  LDA T0
  CMP #241
  BCC .ts_r
  INY
.ts_r:
  LDA T0
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA GSTATE
  CMP #2                       ; at home: Spike is a tile of the hedge
  BCS .bs_an
  CMP #1
  BNE .bs_sp
  LDA GT                       ; a life lost
  CMP #25
  BCC .bs_an
  LDA DEATHK
  BNE .bs_wet
  LDA #PT_SQUASH
  STA ON
  JMP .bs_two
.bs_wet:
  LDA HX
  STA OX
  LDA HPY
  STA OY
  LDA #PT_SPLASH
  LDX GT
  CPX #70
  BCS .bs_w1
  LDA #PT_SPLASH+4
.bs_w1:
  STA ON
  LDA #15
  STA OC
  JSR ADD_SPR
  BRA .bs_an
.bs_sp:
  LDA HDIR                     ; Spike: direction * 2 + hopping
  ASL A
  LDX HT
  BEQ .bs_h
  INC A
.bs_h:
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_SPIKE
  STA ON
.bs_two:
  LDA HX
  STA OX
  LDA HPY
  STA OY
  LDA #11                      ; the face
  STA OC
  LDA ON
  PHA
  CLC
  ADC #4
  STA ON
  JSR ADD_SPR
  PLA
  STA ON
  LDA #6                       ; the spikes
  STA OC
  JSR ADD_SPR
  LDA BABY                     ; the little one on his back
  CMP #2
  BNE .bs_an
  LDA HPY
  CLC
  ADC #4
  STA OY
  LDA #PT_BABY
  STA ON
  LDA #10
  STA OC
  JSR ADD_SPR
.bs_an:
  LDA BABY                     ; waiting on its log, blinking
  CMP #1
  BNE .bs_sn
  LDA BABX+1
  BNE .bs_sn
  LDA BABX
  STA OX
  LDA #9*8-1
  STA OY
  LDA #PT_BABY
  STA ON
  LDA #6
  LDX FRAME_CNT
  CPX #128
  BCC .bs_bc
  LDA #11
.bs_bc:
  STA OC
  JSR ADD_SPR
.bs_sn:
  LDA SNON                     ; the snake
  BEQ .bs_fx
  LDA SNX+1
  BNE .bs_fx
  LDA SNX
  STA OX
  LDA #7*8-1
  STA OY
  LDA SND
  ASL A
  ASL A
  ASL A
  STA T0
  LDA FRAME_CNT
  AND #8
  LSR A
  ORA T0
  CLC
  ADC #PT_SNAKE
  STA ON
  LDA #3
  STA OC
  JSR ADD_SPR
.bs_fx:
  LDA FOXON                    ; the fox
  BEQ .bs_hr
  LDA FOXX
  STA OX
  LDA #11*8-1
  STA OY
  LDA FOXD
  ASL A
  ASL A
  ASL A
  STA T0
  LDA FOXX
  AND #8
  LSR A
  ORA T0
  CLC
  ADC #PT_FOX
  STA ON
  LDA #9
  STA OC
  JSR ADD_SPR
.bs_hr:
  LDX HERH                     ; the heron in its hole
  BMI .bs_e
  LDA HOLE_X,X
  STA OX
  LDA #7
  STA OY
  LDA FRAME_CNT
  AND #32
  LSR A
  LSR A
  LSR A
  CLC
  ADC #PT_HERON
  STA ON
  LDA #15
  STA OC
  JSR ADD_SPR
.bs_e:
  LDY SPRI
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; OX, OY, ON, OC: one sprite more (keeps X)
ADD_SPR:
  LDY SPRI
  LDA OY
  STA SAT_BUFFER,Y
  LDA OX
  STA SAT_BUFFER+1,Y
  LDA ON
  STA SAT_BUFFER+2,Y
  LDA OC
  STA SAT_BUFFER+3,Y
  TYA
  CLC
  ADC #4
  STA SPRI
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from robo vac)
; ===============================================================
; PTR = source, T0/T1 = VRAM address (high with the write bit), T2/T3 = length
VCOPY:
  LDA T0
  STA VREG
  LDA T1
  STA VREG
  LDY #$00
.vc_l:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .vc_y
  INC PTR+1
.vc_y:
  LDA T2
  BNE .vc_d
  DEC T3
.vc_d:
  DEC T2
  LDA T2
  ORA T3
  BNE .vc_l
  RTS

; A = value, T0/T1 = VRAM address, T2/T3 = length
VFILL:
  STA T4
  LDA T0
  STA VREG
  LDA T1
  STA VREG
.vf_l:
  LDA T4
  STA VDATA
  LDA T2
  BNE .vf_d
  DEC T3
.vf_d:
  DEC T2
  LDA T2
  ORA T3
  BNE .vf_l
  RTS

; the table GFX_LOAD (font, tiles, big letters, names) then the sprites
LOAD_GFX:
  JSR CLEAR_VRAM
  LDA #<GFX_LOAD
  STA PTR2
  LDA #>GFX_LOAD
  STA PTR2+1
  JSR LOAD_BLOCKS
  JMP LOAD_SPRITES

; blocks at PTR2: kind (0 end, 1 copy, 2 fill), address, length, source / value
LOAD_BLOCKS:
  LDY #$00
  LDA (PTR2),Y
  BEQ .lb_e
  STA T5
  INY
  LDA (PTR2),Y
  STA T0
  INY
  LDA (PTR2),Y
  STA T1
  INY
  LDA (PTR2),Y
  STA T2
  INY
  LDA (PTR2),Y
  STA T3
  INY
  LDA (PTR2),Y
  STA PTR
  INY
  LDA (PTR2),Y
  STA PTR+1
  LDA PTR2
  CLC
  ADC #7
  STA PTR2
  BCC .lb_k
  INC PTR2+1
.lb_k:
  LDA T5
  CMP #2
  BEQ .lb_f
  JSR VCOPY
  BRA LOAD_BLOCKS
.lb_f:
  LDA PTR
  JSR VFILL
  BRA LOAD_BLOCKS
.lb_e:
  RTS

; the name table HOFF to spaces (black)
CLEAR_NT:
  LDA #$00
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  CLC
  ADC HOFF
  STA T1
  LDA #$00
  STA T2
  LDA #$03
  STA T3
  LDA #$20
  JMP VFILL

; X = row, Y = column: VDP address of the cell in the name table HOFF (0: $3800, 4: $3C00)
NT_XY:
  TXA
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  CLC
  ADC HOFF
  STA T6
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA T7
  TYA
  ORA T7
  STA VREG
  LDA T6
  STA VREG
  RTS

; text records at TP: row, column, characters..., 0   (end: row = $FF)
PRINT:
  LDY #$00
  LDA (TP),Y
  CMP #$FF
  BEQ .pr_e
  TAX
  INY
  LDA (TP),Y
  STY T5
  TAY
  JSR NT_XY
  LDY T5
.pr_c:
  INY
  LDA (TP),Y
  BEQ .pr_n
  STA VDATA
  BRA .pr_c
.pr_n:
  INY
  TYA
  CLC
  ADC TP
  STA TP
  BCC PRINT
  INC TP+1
  BRA PRINT
.pr_e:
  RTS

; A = BCD byte, X = row, Y = column: two digits
PUT_BCD2:
  PHA
  JSR NT_XY
  PLA
  ; fall into PUT_2

; A = BCD byte: two digits where the VDP points
PUT_2:
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #$30
  STA VDATA
  PLA
  AND #$0F
  ORA #$30
  STA VDATA
  RTS

; ===============================================================
;  SPRITES
; ===============================================================
HIDE_SPRITES:
  LDA #$D0
  STA SAT_BUFFER
  LDA #1
  STA SATB
  RTS

; NMI (vblank): only point that writes the Sprite Attribute Table, then the sound.
NMI_TASK:
  INC FRAME_CNT
  LDA VREG                ; read VDP status (clears F and the byte latch)
  LDA #<VDP_SPRITE_ATT_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_ATT_BASE)
  STA VREG
  LDX SATB                ; the sprites in use (4 bytes each), then Y=$D0 = end of the list
  DEX
  STX SN1
  LDX #$00
  CPX SN1
  BEQ .copy_end
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  LDA SAT_BUFFER+1,X
  STA VDATA
  LDA SAT_BUFFER+2,X
  STA VDATA
  LDA SAT_BUFFER+3,X
  STA VDATA
  INX
  INX
  INX
  INX
  CPX SN1
  BNE .copy_sat
.copy_end:
  LDA #$D0
  STA VDATA
  JSR SND_TICK            ; music or sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI


; ===============================================================
;  SOUND: the tunes (4 tracks, from tank) and the effects
;  per chip in game: A = tone effects, B = noise and C = low tone
;  of the explosions; sounds go to the side of the screen they come from
; ===============================================================
SND_TICK:
  PHA
  PHX
  PHY
  INC SND_PH
  LDA SND_CMD
  BEQ .st_run
  STZ SND_CMD
  CMP #CMD_GAME
  BNE .st_song
  JSR SND_GAME_MODE
  BRA .st_run
.st_song:
  JSR SND_START
.st_run:
  LDA SND_MODE
  BEQ .st_sfx
  JSR MUS_TICK
  BRA .st_flush
.st_sfx:
  JSR SFX_TICK
.st_flush:
  JSR AY_FLUSH
  PLY
  PLX
  PLA
  RTS

; ---------------------------------------------------------------
; starts the tune SONG
; ---------------------------------------------------------------
SND_START:
  JSR SND_CLEAR_SH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #$2A                      ; right: tone A, noise B (drums), tone C
  STA SH_R+7
  LDA SONG                      ; 4 tracks of the song SONG
  ASL A
  ASL A
  STA SN1
  LDX #$03
.ss_trk:
  TXA
  CLC
  ADC SN1
  TAY
  LDA SONGP_LO,Y
  STA TR_PL,X
  LDA SONGP_HI,Y
  STA TR_PH,X
  LDA #$01
  STA TR_CT,X                   ; the first DEC brings it to 0 -> reads the first note at once
  STA TR_ACT,X
  LDA #$00
  STA TR_NOTE,X
  STA TR_VOL,X
  STA TR_AGE,X
  DEX
  BPL .ss_trk
  LDA #$01
  STA SND_MODE
  STA SND_BUSY
  RTS

; ---------------------------------------------------------------
; reads the next event of track X: .byte note, length (frames); $FF = end
; ---------------------------------------------------------------
MUS_FETCH:
  LDA TR_PL,X
  STA SND_PTR
  LDA TR_PH,X
  STA SND_PTR+1
  LDY #$00
  LDA (SND_PTR),Y
  CMP #$FF
  BNE .mf_note
  LDA #$00                      ; end of the track
  STA TR_ACT,X
  STA TR_NOTE,X
  STA TR_VOL,X
  RTS
.mf_note:
  STA TR_NOTE,X
  INY
  LDA (SND_PTR),Y
  STA TR_CT,X
  LDA TR_PL,X
  CLC
  ADC #$02
  STA TR_PL,X
  BCC .mf_nc
  INC TR_PH,X
.mf_nc:
  LDA #$00
  STA TR_AGE,X
  LDA TR_NOTE,X
  BEQ .mf_vol                   ; rest: volume 0
  CPX #$03
  BEQ .mf_drum
  LDA V0_TAB,X
  BRA .mf_vol
.mf_drum:
  TAY
  LDA DRUM_V0,Y
.mf_vol:
  STA TR_VOL,X
  RTS

; ---------------------------------------------------------------
; one frame of music: advances the 4 tracks and fills the shadows
; ---------------------------------------------------------------
MUS_TICK:
  LDX #$02                      ; tone tracks: 0 melody, 1 harmony, 2 bass
.mt_trk:
  LDA TR_ACT,X
  BEQ .mt_next
  DEC TR_CT,X
  BNE .mt_age
  JSR MUS_FETCH
  BRA .mt_next
.mt_age:
  INC TR_AGE,X
  LDA TR_AGE,X
  AND DECMASK_TAB,X
  BNE .mt_next
  LDA TR_VOL,X
  CMP FLOOR_TAB,X
  BCC .mt_next
  BEQ .mt_next
  DEC TR_VOL,X
.mt_next:
  DEX
  BPL .mt_trk
  LDX #$03                      ; track 3: drums
  LDA TR_ACT,X
  BEQ .mt_dr_end
  DEC TR_CT,X
  BNE .mt_dr_age
  JSR MUS_FETCH
  BRA .mt_dr_end
.mt_dr_age:
  INC TR_AGE,X
  LDY TR_NOTE,X
  LDA TR_AGE,X
  AND DRUM_MASK,Y
  BNE .mt_dr_end
  LDA TR_VOL,X
  BEQ .mt_dr_end
  DEC TR_VOL,X
.mt_dr_end:
  ; ---- melody: on both chips, the right one detuned by 1 step (chorus effect)
  LDX TR_NOTE
  BEQ .mt_l_off
  LDA TP_LO,X
  STA SH_L
  CLC
  ADC #$01
  STA SH_R
  LDA TP_HI,X
  STA SH_L+1
  STA SH_R+1
  LDA TR_VOL
  BRA .mt_l_v
.mt_l_off:
  LDA #$00
.mt_l_v:
  STA SH_L+8
  STA SH_R+8
  ; ---- harmony: left chip only, channel B
  LDX TR_NOTE+1
  BEQ .mt_h_off
  LDA TP_LO,X
  STA SH_L+2
  LDA TP_HI,X
  STA SH_L+3
  LDA TR_VOL+1
  BRA .mt_h_v
.mt_h_off:
  LDA #$00
.mt_h_v:
  STA SH_L+9
  ; ---- bass: both chips, channel C
  LDX TR_NOTE+2
  BEQ .mt_b_off
  LDA TP_LO,X
  STA SH_L+4
  STA SH_R+4
  LDA TP_HI,X
  STA SH_L+5
  STA SH_R+5
  LDA TR_VOL+2
  BRA .mt_b_v
.mt_b_off:
  LDA #$00
.mt_b_v:
  STA SH_L+10
  STA SH_R+10
  ; ---- drums: right chip, noise on channel B
  LDX TR_NOTE+3
  LDA DRUM_NP,X
  STA SH_R+6
  LDA TR_VOL+3
  STA SH_R+9
  ; ---- tune over?
  LDA TR_ACT
  ORA TR_ACT+1
  ORA TR_ACT+2
  ORA TR_ACT+3
  BNE .mt_end
  JSR SND_GAME_MODE             ; silence, SND_BUSY = 0
.mt_end:
  RTS

SFX_TICK:
  LDA SND_RND                   ; LFSR for the crackle of the explosions
  ASL A
  BCC .sf_r
  EOR #$1D
.sf_r:
  STA SND_RND
  LDX #$01
.sf_chip:
  STX SND_T1
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  TAY                           ; Y = chip * 16 = offset of the shadow (SH_R = SH_L + 16)
  LDA #$00
  STA SH_L+8,Y
  STA SH_L+9,Y
  STA SH_L+10,Y
  ; ---- channel A: tone effect
  LDA WH_ID,X
  BEQ .sf_noise
  TAX
  LDA WH_START,X
  STA SN1
  LDA WH_LEN,X
  STA SN0
  LDX SND_T1
  LDA WH_POS,X
  CMP SN0
  BCS .sf_whend
  CLC
  ADC SN1
  TAX
  LDA WH_TL,X
  STA SH_L,Y
  LDA WH_TH,X
  STA SH_L+1,Y
  LDA WH_VOL,X
  STA SH_L+8,Y
  LDX SND_T1
  INC WH_POS,X
  BRA .sf_noise
.sf_whend:
  LDA #$00
  STA WH_ID,X
.sf_noise:
  ; ---- channels B and C: explosion
  LDX SND_T1
  LDA EX_ID,X
  BEQ .sf_next
  TAX
  LDA EX_START,X
  STA SN1
  LDA EX_LEN,X
  STA SN0
  LDX SND_T1
  LDA EX_POS,X
  CMP SN0
  BCS .sf_exend
  CLC
  ADC SN1
  TAX
  LDA EX_NV,X
  BEQ .sf_e1
  LDA SND_RND                   ; crackle: -1 at random
  LSR A
  LDA EX_NV,X
  SBC #$00
.sf_e1:
  STA SH_L+9,Y
  LDA EX_NP,X
  STA SH_L+6,Y
  LDA EX_VC,X
  STA SH_L+10,Y
  LDA EX_TL,X
  STA SH_L+4,Y
  LDA EX_TH,X
  STA SH_L+5,Y
  LDX SND_T1
  INC EX_POS,X
  BRA .sf_next
.sf_exend:
  LDA #$00
  STA EX_ID,X
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_done
  JMP .sf_chip
.sf_done:
  RTS

; A = explosion, Y = X on the screen: on that side
BOOM_AT:
  LDX #$00
  CPY #$80
  BCC .ba_l
  INX
.ba_l:
  JMP SFX_BOOM

; ===============================================================
;  LIBRARY: joystick, frames, VDP
; ===============================================================
; ---------------------------------------------------------------
; reads both joysticks (1 = pressed)
; ---------------------------------------------------------------
READ_JOY:
  LDA PORTA_JOY
  EOR #$FF
  AND #$3F
  STA P_JOY
  LDA PORTB_JOY
  EOR #$FF
  AND #$3F
  STA P_JOY+1
  RTS

NEXT_RND:                      ; 8-bit LFSR
  LDA RND
  ASL A
  BCC .nr_ok
  EOR #$1D
.nr_ok:
  STA RND
  RTS

; wait until the buttons are released and then pressed
WAIT_FIRE:
.wf_rel:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .wf_rel
.wf_press:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BEQ .wf_press
  RTS

WAIT_FRAMES:                   ; A = number of frames (VDP interrupt on)
  STA T0
.wfs_l:
  JSR WAIT_FRAME
  DEC T0
  BNE .wfs_l
  RTS

BIN2BCD:                       ; A (0-99) -> A (BCD)
  LDY #$00
.bb_l:
  CMP #10
  BCC .bb_e
  SEC
  SBC #10
  INY
  BRA .bb_l
.bb_e:
  STA T0
  TYA
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  RTS

WAIT_FRAME:               ; wait for the next NMI (1 frame = 1/60 s)
  LDA FRAME_CNT
  CMP LAST_FRAME
  BEQ WAIT_FRAME
  STA LAST_FRAME
  RTS

; switches the VDP interrupt off just after an NMI (the next one comes in ~16 ms)
VDP_INT_OFF:
  LDA VINT
  BEQ .io_ret             ; already off
  LDA FRAME_CNT
.io_wait:
  CMP FRAME_CNT
  BEQ .io_wait
  LDA #$C6                ; R1: 16K + display ON + INT OFF
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA #$00
  STA VINT
.io_ret:
  RTS

VDP_INT_ON:
  LDA #$E6                ; R1: 16K + display ON + INT ON
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA #$01
  STA VINT
  RTS

LOAD_SPRITES:                  ; sprite patterns at $1800 (SPR_PAGES pages of 256 bytes)
  LDA #$00
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $18)
  STA VREG
  LDA #<SPRITES
  STA PTR
  LDA #>SPRITES
  STA PTR+1
  LDX #SPR_PAGES
.ls_p:
  LDY #$00
.ls_l:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .ls_l
  INC PTR+1
  DEX
  BNE .ls_p
  RTS

VDP_SET_REGISTERS:
  PHA
  PHY
  LDY #$87                     ;REGISTER SELECT
  LDX #$07                     ;INITIALIZE COUNTER

INIT1:
  LDA ITAB,X                   ;LOAD INIT TABLE
  JSR SREG                     ;WRITE TO VDP
  DEY                          ;DECREMENT REGISTER
  DEX                          ;DECREMENT COUNTER
  BNE INIT1                    ;DONE?
  LDA ITAB                     ;R0 = ITAB[0]
  JSR SREG
  PLY
  PLA
  RTS

SREG:                 ;STORE VIDEO REGISTER
  PHA
  PHY
  STA VREG
  STY VREG
  PLY
  PLA
  RTS

CLEAR_VRAM:
   PHA
   PHX
   PHY
   LDY #$40                    ; SETUP VRAM ADDRESS
   LDA #0
   STA VREG
   STY VREG
   LDX #$C0                    ; COUNT HIGH

NEXF:
   LDY #0                      ; COUNT LOW

FILL_:
   LDA #$00
   STA VDATA                   ; WRITE A ZERO TO VRAM
   INY                         ; NEXT LOC
   BNE FILL_                   ; KEEP GOING UNTIL PAGE DONE
   INX                         ; DONE ALL 40 PAGES?
   BNE NEXF                    ; NO, KEEP GOING
   PLY
   PLX
   PLA
   RTS

ITAB:
   .byte $02,$C6,$0E,$FF       ;INITIALIZE G2 MODE
   .byte $03,$76,$03,$01       ;R0: G2 | R1: 16K, 16x16 spr | R2: name $3800 | R3: color $2000
                               ;R4: pattern $0000 | R5: SAT $3B00 | R6: sprite pattern $1800 | R7: black background

; ===============================================================
;  SOUND  -  two AY-3-8910 (left / right = stereo)
;  All the sound is played by SND_TICK, called by the NMI at 60 Hz.
;  The main loop never writes the AYs: it only leaves requests
;  (SND_CMD, SND_THR, SFX_WHISTLE, SFX_BOOM), so there are no conflicts.
;  Channels per chip in game: A = tone effects, B = noise (engine,
;  explosion), C = low tone (engine rumble, explosion thump).
; ===============================================================

; called once by RESET (VDP interrupt still off)
SND_INIT:
  LDA #$A5
  STA SND_RND
  LDA #$00
  STA SND_CMD
  STA SND_PH
  JMP SND_GAME_MODE

SND_CLEAR_SH:                   ; all the shadow registers to 0
  LDX #10
  LDA #$00
.cs_l:
  STA SH_L,X
  STA SH_R,X
  DEX
  BPL .cs_l
  RTS

; game mode: silence, mixer = tone A + noise B + tone C
SND_GAME_MODE:
  JSR SND_CLEAR_SH
  LDA #$2A
  STA SH_L+7
  STA SH_R+7
  LDA #$00
  STA SND_MODE
  STA SND_BUSY
  STA WH_ID
  STA WH_ID+1
  STA WH_POS
  STA WH_POS+1
  STA EX_ID
  STA EX_ID+1
  STA EX_POS
  STA EX_POS+1
  JMP AY_FLUSH

; writes registers 0-10 of the two shadows to the two AYs
AY_FLUSH:
  LDX #10
.af_l:
  LDA SH_L,X
  STX AY_L_LATCH
  STA AY_L_WRITE
  LDA SH_R,X
  STX AY_R_LATCH
  STA AY_R_WRITE
  DEX
  BPL .af_l
  RTS


; ---------------------------------------------------------------
; requests from the main loop (they keep A, X, Y)
;   pan: X = 0 left, 1 right, 2 both
; ---------------------------------------------------------------
SFX_WHISTLE:                    ; A = whistle id (W_*), X = pan
  PHA
  PHX
  STA SMT0
  CPX #$02
  BEQ .sw_both
  LDA #$00
  STA WH_POS,X
  LDA SMT0
  STA WH_ID,X
  BRA .sw_end
.sw_both:
  LDA #$00
  STA WH_POS
  STA WH_POS+1
  LDA SMT0
  STA WH_ID
  STA WH_ID+1
.sw_end:
  PLX
  PLA
  RTS

SB_SET:                         ; X = chip, SMT0 = explosion id
  LDA EX_ID,X
  CMP #S_BIG
  BNE .sbs_set
  LDA SMT0                      ; a small bang does not stop a big one
  CMP #S_BIG
  BNE .sbs_ret
.sbs_set:
  LDA #$00
  STA EX_POS,X
  LDA SMT0
  STA EX_ID,X
.sbs_ret:
  RTS

SFX_BOOM:                       ; A = id (S_SMALL / S_BIG), X = pan
  PHA
  PHX
  STA SMT0
  CPX #$02
  BEQ .sb_both
  JSR SB_SET
  BRA .sb_end
.sb_both:
  LDX #$00
  JSR SB_SET
  LDX #$01
  JSR SB_SET
.sb_end:
  PLX
  PLA
  RTS


; ===============================================================
;  RECORDS ON THE SD (dev/lib_records.asm, see SD_SALVATAGGI.md)
;  8 best scores signed with 3 initials, kept in the zone
;  REC_ZONE of the save area (sector 32768 + zone * 16): two
;  copies (sectors 0 and 1 of the zone) written in turn.
;  Without the BIOS KEYB/SD ($4C at $FD18/$FD1B/$FD1E) the table
;  lives only in RAM.
;
;  The game defines:
;    REC_ZONE   fixed zone number of the game (1-127)
;    REC_RAM    $2A0 bytes of free RAM (buffer, table, variables)
;    REC_ROW    screen row of the table header (rows +1..+8 =
;               the table; the sign screen also uses rows -4,
;               -2 and +10..+12)
;    REC_WIPEN  rows cleared from REC_ROW for the table (>= 9)
;    REC_SROW   row of the table header on the sign screen (rows
;               -4, -2 and +10..+12 too); usually REC_ROW
;    REC_JOY2   $FF = both joysticks sign, 0 = the player's own
;    REC_NAME   16 bytes: name of the game, spaces at the end
;    REC_HEAD   header of the table, 0 at the end
;    REC_XLBL   label of the extra byte ("LEG "), 0 at the end
;    REC_XY     X = row, Y = column: VDP write address
;    REC_CLS    clears the screen for the sign screen
;    REC_SND    A = 0 letter changed, 1 initials confirmed
;  and optionally (defined before the library):
;    REC_ITALIAN  the texts of the sign screen in Italian
;    REC_ONEPL    one player only: no "PLAYER n" line
;    REC_BMP      a bitmap game: REC_XY only sets the cell, every
;                 character goes to REC_CHR (A = ASCII, may change
;                 A, X, Y; the cell moves on by itself or here) and
;                 REC_CLRROWS (A = first row, X = rows) clears rows
;  and has VDATA, P_JOY (2 bytes, 1 = pressed, bits UDLR B1 B2),
;  READ_JOY, HIDE_SPRITES, VINT, VDP_INT_OFF (waits for the next frame and
;  stops the NMI) and VDP_INT_ON.
;
;  Calls:
;    REC_INIT   at RESET (VDP interrupt off): reads the table
;    REC_CHECK  after the game over: REC_SC (4 BCD bytes, low
;               first), REC_EX (extra byte), REC_PL (player 0/1);
;               C = 1 if it entered the table (signed on the spot)
;    REC_SAVE   after the checks: one write, if anything changed
;    REC_TITLE  at the title: page 0 (the game's own) for 8 s
;    REC_TICK   every title frame: C = 1 when the page changes,
;               REC_PG = page to draw (0 game, 1 table)
;    REC_SHOW   draws the table (VDP interrupt off)
;    REC_WIPE   clears REC_WIPEN rows from REC_ROW (interrupt off)
;    REC_TAB    the table: 8 rows of 8 bytes, best first
;  One against one (wins in a row against the CPU):
;    REC_LOSE   at RESET and when the CPU wins: the run starts again
;    REC_WIN    the player beat the CPU (REC_EX set): the run grows
;               by one and is signed, in place of its own row
;               (score 4 BCD bytes, 3 initials, extra byte)
; ===============================================================
SV_BUF     = REC_RAM           ; 512: one sector
REC_TAB    = REC_RAM+$200      ; 64: 8 rows x 8 bytes
SV_KEEP    = REC_RAM+$240      ; 31: $44-$4E and $0306-$0319 during the call
SV_OK      = REC_RAM+$260      ; 1 = the BIOS has the sector routines
SV_SEC     = REC_RAM+$261      ; sector of the zone (0-15)
SV_RW      = REC_RAM+$262      ; 0 read, 1 write
SV_VI      = REC_RAM+$263      ; VINT before the call
REC_CNT    = REC_RAM+$264      ; 2: write counter of the copy in RAM
REC_OLD    = REC_RAM+$266      ; copy to write next (the older one)
REC_V      = REC_RAM+$267      ; 1 = copy 0 was valid
REC_DIRTY  = REC_RAM+$268      ; 1 = the table changed
REC_SC     = REC_RAM+$269      ; 4: score to check (BCD, low first)
REC_EX     = REC_RAM+$26D      ; extra byte of the row
REC_PL     = REC_RAM+$26E      ; player who signs (0 / 1)
REC_POS    = REC_RAM+$26F      ; offset of the row being signed
REC_CUR    = REC_RAM+$270      ; initial being edited (0-2)
REC_J      = REC_RAM+$271      ; joystick, the one before, new presses
REC_JP     = REC_RAM+$272
REC_JN     = REC_RAM+$273
REC_RPT    = REC_RAM+$274      ; frames before the letter repeats
REC_TMO    = REC_RAM+$275      ; 2: frames before the initials confirm by themselves
REC_NZ     = REC_RAM+$277      ; 1 = a digit was printed (no more blanks)
REC_K      = REC_RAM+$278
REC_LAST   = REC_RAM+$279      ; 3: initials signed last
REC_SL     = REC_RAM+$27C      ; 2: checksum
REC_SH     = REC_RAM+$27D
REC_PT     = REC_RAM+$27E      ; 2: frames left on this title page
REC_PG     = REC_RAM+$280      ; title page shown (0 game, 1 table)
REC_T      = REC_RAM+$281
REC_R0     = REC_RAM+$282      ; row of the table header being drawn
REC_STK    = REC_RAM+$283      ; one-against-one games: wins in a row against the CPU (BCD)
REC_RUN    = REC_RAM+$284      ; offset of the row of this run in the table ($FF = none)

REC_AYL    = $D384             ; AY latches (left, right) and data
REC_AYR    = $D380
REC_PAGE_T = 480               ; frames of the title page of the game (8 s)
REC_TAB_T  = 300               ; frames of the table (5 s)
REC_WAITT  = 1800              ; 30 s without a key: the initials are confirmed

; sector header: signature, version, zone, type 1 = records,
; 1 table, 8 rows, 8 bytes per row
REC_HDR:
  .byte "MVSV",1,REC_ZONE,1,1,8,8
REC_LETTERS:
  .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ ."
REC_NLET = 28

; ---------------------------------------------------------------
;  SV_CALL: A = 0 read / 1 write sector SV_SEC of the zone in
;  SV_BUF. C = 0 ok, 1 error or no BIOS. Keeps the game's RAM
;  that the BIOS driver uses; the NMI is off during the call.
; ---------------------------------------------------------------
SV_CALL:
  STA SV_RW
  LDA SV_OK
  BNE .sv_go
  SEC
  RTS
.sv_go:
  LDA VINT
  STA SV_VI
  JSR VDP_INT_OFF              ; no NMI while $44-$4E belong to the driver
  LDX #8                       ; both AYs silent (the last note would hang)
.sv_sil:
  STX REC_AYL
  STZ REC_AYL+1
  STX REC_AYR
  STZ REC_AYR+1
  INX
  CPX #11
  BNE .sv_sil
  LDX #10
.sv_k1:
  LDA $44,X
  STA SV_KEEP,X
  DEX
  BPL .sv_k1
  LDX #19
.sv_k2:
  LDA $0306,X
  STA SV_KEEP+11,X
  DEX
  BPL .sv_k2
  JSR $FD1E                    ; SD init: always (the game may have changed sd_type)
  BCS .sv_done
  LDA SV_SEC                   ; SD_LBA = 32768 + zone * 16 + sector
  AND #$0F
  ORA #((REC_ZONE<<4)&$F0)
  STA $0316
  LDA #($80+(REC_ZONE>>4))
  STA $0317
  STZ $0318
  STZ $0319
  LDX #<SV_BUF
  LDY #>SV_BUF
  LDA SV_RW
  BNE .sv_w
  JSR $FD18
  BRA .sv_done
.sv_w:
  JSR $FD1B
.sv_done:
  PHP
  LDX #10
.sv_r1:
  LDA SV_KEEP,X
  STA $44,X
  DEX
  BPL .sv_r1
  LDX #19
.sv_r2:
  LDA SV_KEEP+11,X
  STA $0306,X
  DEX
  BPL .sv_r2
  LDA SV_VI
  BEQ .sv_e
  JSR VDP_INT_ON
.sv_e:
  PLP
  RTS

; ---------------------------------------------------------------
;  REC_INIT: the BIOS check, then the newest valid copy (or the
;  empty table)
; ---------------------------------------------------------------
REC_INIT:
  STZ SV_OK
  LDA $FD18
  CMP #$4C
  BNE .ri_nb
  LDA $FD1B
  CMP #$4C
  BNE .ri_nb
  LDA $FD1E
  CMP #$4C
  BNE .ri_nb
  INC SV_OK
.ri_nb:
  LDX #63                      ; empty table: score 0, "---"
.ri_e:
  TXA
  AND #7
  CMP #4
  BCC .ri_z
  CMP #7
  BEQ .ri_z
  LDA #'-'
  BRA .ri_s
.ri_z:
  LDA #0
.ri_s:
  STA REC_TAB,X
  DEX
  BPL .ri_e
  LDA #'A'
  STA REC_LAST
  STA REC_LAST+1
  STA REC_LAST+2
  STZ REC_CNT
  STZ REC_CNT+1
  STZ REC_OLD
  STZ REC_V
  STZ REC_DIRTY
  STZ REC_PG
  STZ SV_SEC                   ; copy 0
  LDA #0
  JSR SV_CALL
  BCS .ri_1
  JSR REC_VALID
  BCS .ri_1
  JSR REC_TAKE
  LDA #1                       ; the next write goes to copy 1
  STA REC_OLD
  STA REC_V
.ri_1:
  LDA #1                       ; copy 1
  STA SV_SEC
  LDA #0
  JSR SV_CALL
  BCS .ri_e2
  JSR REC_VALID
  BCS .ri_e2
  LDA REC_V                    ; both valid: the higher counter wins
  BEQ .ri_t1
  LDA SV_BUF+11
  CMP REC_CNT+1
  BCC .ri_e2
  BNE .ri_t1
  LDA SV_BUF+10
  CMP REC_CNT
  BCC .ri_e2
  BEQ .ri_e2
.ri_t1:
  JSR REC_TAKE
  STZ REC_OLD                  ; the next write goes to copy 0
.ri_e2:
  RTS

; SV_BUF valid for this game? C = 0 yes
REC_VALID:
  LDX #9
.rv_h:
  LDA SV_BUF,X
  CMP REC_HDR,X
  BNE .rv_no
  DEX
  BPL .rv_h
  JSR REC_SUM
  LDA REC_SL
  CMP SV_BUF+510
  BNE .rv_no
  LDA REC_SH
  CMP SV_BUF+511
  BNE .rv_no
  CLC
  RTS
.rv_no:
  SEC
  RTS

; rows and counter of SV_BUF into RAM
REC_TAKE:
  LDX #63
.rt_l:
  LDA SV_BUF+32,X
  STA REC_TAB,X
  DEX
  BPL .rt_l
  LDA SV_BUF+10
  STA REC_CNT
  LDA SV_BUF+11
  STA REC_CNT+1
  RTS

; 16-bit sum of the bytes 0-509 of SV_BUF -> REC_SL / REC_SH
REC_SUM:
  STZ REC_SL
  STZ REC_SH
  LDX #0
.rs_a:
  LDA SV_BUF,X
  CLC
  ADC REC_SL
  STA REC_SL
  BCC .rs_a1
  INC REC_SH
.rs_a1:
  INX
  BNE .rs_a
.rs_b:
  LDA SV_BUF+256,X
  CLC
  ADC REC_SL
  STA REC_SL
  BCC .rs_b1
  INC REC_SH
.rs_b1:
  INX
  CPX #254
  BNE .rs_b
  RTS

; ---------------------------------------------------------------
;  REC_SAVE: if the table changed, one write into the older copy
;  (C = 1 if it could not be written: the table stays in RAM)
; ---------------------------------------------------------------
REC_SAVE:
  LDA REC_DIRTY
  BNE .rv_go
  CLC
  RTS
.rv_go:
  STZ REC_DIRTY
  LDX #0
.rw_c:
  STZ SV_BUF,X
  STZ SV_BUF+256,X
  INX
  BNE .rw_c
  LDX #9
.rw_h:
  LDA REC_HDR,X
  STA SV_BUF,X
  DEX
  BPL .rw_h
  LDA REC_CNT                  ; counter + 1
  CLC
  ADC #1
  STA SV_BUF+10
  LDA REC_CNT+1
  ADC #0
  STA SV_BUF+11
  LDX #15
.rw_n:
  LDA REC_NAME,X
  STA SV_BUF+16,X
  DEX
  BPL .rw_n
  LDX #63
.rw_t:
  LDA REC_TAB,X
  STA SV_BUF+32,X
  DEX
  BPL .rw_t
  JSR REC_SUM
  LDA REC_SL
  STA SV_BUF+510
  LDA REC_SH
  STA SV_BUF+511
  LDA REC_OLD
  STA SV_SEC
  LDA #1
  JSR SV_CALL
  BCS .rw_e
  LDA SV_BUF+10                ; written: this copy is now the newer one
  STA REC_CNT
  LDA SV_BUF+11
  STA REC_CNT+1
  LDA REC_OLD
  EOR #1
  STA REC_OLD
  CLC
.rw_e:
  RTS

; ---------------------------------------------------------------
;  REC_CHECK: REC_SC enters the table? Then the row is inserted
;  and signed (REC_SIGN). C = 1 if it entered.
; ---------------------------------------------------------------
REC_CHECK:
  LDA REC_SC
  ORA REC_SC+1
  ORA REC_SC+2
  ORA REC_SC+3
  BEQ .rc_no                   ; no points, no record
  LDX #0
.rc_f:
  LDA REC_SC+3                 ; higher than this row? (equal = below it)
  CMP REC_TAB+3,X
  BCC .rc_nx
  BNE .rc_in
  LDA REC_SC+2
  CMP REC_TAB+2,X
  BCC .rc_nx
  BNE .rc_in
  LDA REC_SC+1
  CMP REC_TAB+1,X
  BCC .rc_nx
  BNE .rc_in
  LDA REC_SC
  CMP REC_TAB,X
  BEQ .rc_nx
  BCS .rc_in
.rc_nx:
  TXA
  CLC
  ADC #8
  TAX
  CPX #64
  BNE .rc_f
.rc_no:
  CLC
  RTS
.rc_in:
  STX REC_POS
  LDY #56                      ; the rows below move down one place
.rc_sh:
  CPY REC_POS
  BEQ .rc_put
  DEY
  LDA REC_TAB,Y
  STA REC_TAB+8,Y
  BRA .rc_sh
.rc_put:
  LDA REC_SC
  STA REC_TAB,X
  LDA REC_SC+1
  STA REC_TAB+1,X
  LDA REC_SC+2
  STA REC_TAB+2,X
  LDA REC_SC+3
  STA REC_TAB+3,X
  LDA REC_LAST
  STA REC_TAB+4,X
  LDA REC_LAST+1
  STA REC_TAB+5,X
  LDA REC_LAST+2
  STA REC_TAB+6,X
  LDA REC_EX
  STA REC_TAB+7,X
  LDA #1
  STA REC_DIRTY
  JSR REC_SIGN
  LDX REC_POS
  LDA REC_TAB+4,X
  STA REC_LAST
  LDA REC_TAB+5,X
  STA REC_LAST+1
  LDA REC_TAB+6,X
  STA REC_LAST+2
  SEC
  RTS

; ---------------------------------------------------------------
;  REC_WIN / REC_LOSE: a run of wins against the CPU. Every win
;  signs the run again (the initials of the last signature are
;  offered), and the row of the run moves up instead of a new row:
;  the table keeps the run even if the power goes off before it ends.
; ---------------------------------------------------------------
REC_LOSE:
  STZ REC_STK
  LDA #$FF
  STA REC_RUN
  RTS

REC_WIN:
  SED                          ; one more win (99 at most)
  LDA REC_STK
  CMP #$99
  BEQ .rw_m
  CLC
  ADC #1
  STA REC_STK
.rw_m:
  CLD
  LDX REC_RUN                  ; the old row of the run goes away
  BMI .rw_c
.rw_sh:
  CPX #56
  BCS .rw_e
  LDA REC_TAB+8,X
  STA REC_TAB,X
  INX
  BRA .rw_sh
.rw_e:
  LDX #7                       ; the last row is empty
.rw_z:
  LDA #0
  CPX #4
  BCC .rw_zb
  CPX #7
  BCS .rw_zb
  LDA #'-'
.rw_zb:
  STA REC_TAB+56,X
  DEX
  BPL .rw_z
.rw_c:
  LDA REC_STK
  STA REC_SC
  STZ REC_SC+1
  STZ REC_SC+2
  STZ REC_SC+3
  STZ REC_PL
  JSR REC_CHECK
  LDA #$FF
  BCC .rw_p
  LDA REC_POS
.rw_p:
  STA REC_RUN
  JMP REC_SAVE

; ---------------------------------------------------------------
;  REC_SIGN: the sign screen. UP / DOWN change the letter,
;  LEFT / RIGHT move, a button moves on (on the third letter it
;  confirms); after 30 s without a key it confirms by itself.
; ---------------------------------------------------------------
REC_SIGN:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES               ; nothing of the game over the table
  JSR REC_CLS
  LDX #REC_SROW-4
  LDY #RT_NEWX
  LDA #(RT_NEW-REC_TXT)
  JSR REC_PUTS
  .ifndef REC_ONEPL
  LDX #REC_SROW-2
  LDY #RT_PLX
  LDA #(RT_PLAYER-REC_TXT)
  JSR REC_PUTS
  LDA REC_PL
  CLC
  ADC #'1'
  JSR REC_OUT
  .endif
  LDA #REC_SROW
  STA REC_R0
  JSR REC_SHOW_R
  LDX #REC_SROW+10
  LDY #RT_HX
  LDA #(RT_H1-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+11
  LDY #RT_HX
  LDA #(RT_H2-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+12
  LDY #RT_HX
  LDA #(RT_H3-REC_TXT)
  JSR REC_PUTS
  JSR VDP_INT_ON
  STZ REC_CUR
  STZ REC_RPT
  LDA #$FF                     ; everything held: a key counts once released
  STA REC_JP
  LDA #<REC_WAITT
  STA REC_TMO
  LDA #>REC_WAITT
  STA REC_TMO+1
.sg_l:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA P_JOY+1
  AND #REC_JOY2
  STA REC_T
  LDX REC_PL
  LDA P_JOY,X
  ORA REC_T
  AND #$3F
  STA REC_J
  LDA REC_JP
  EOR #$FF
  AND REC_J
  STA REC_JN
  LDA REC_J
  STA REC_JP
  BEQ .sg_nk
  LDA #<REC_WAITT              ; a key: the 30 s start again
  STA REC_TMO
  LDA #>REC_WAITT
  STA REC_TMO+1
.sg_nk:
  LDA REC_JN                   ; a button or RIGHT: the next letter
  AND #$38
  BEQ .sg_nr
  LDA REC_CUR
  CMP #2
  BCC .sg_mr
  LDA REC_JN
  AND #$30
  BEQ .sg_nr
  JMP .sg_end                  ; a button on the third letter: done
.sg_mr:
  INC REC_CUR
  BRA .sg_snd
.sg_nr:
  LDA REC_JN                   ; LEFT: back one letter
  AND #$04
  BEQ .sg_ud
  LDA REC_CUR
  BEQ .sg_ud
  DEC REC_CUR
  BRA .sg_snd
.sg_ud:
  LDA REC_JN                   ; UP / DOWN: at once, then repeated
  AND #$03
  BEQ .sg_hold
  LDA #18
  STA REC_RPT
  BRA .sg_chg
.sg_hold:
  LDA REC_J
  AND #$03
  BEQ .sg_draw
  DEC REC_RPT
  BNE .sg_draw
  LDA #5
  STA REC_RPT
.sg_chg:
  JSR REC_LETTER
.sg_snd:
  LDA #0
  JSR REC_SND
.sg_draw:
  LDA REC_TMO                  ; the letter being edited blinks
  AND #$10
  JSR REC_INITS
  JSR VDP_INT_ON
  LDA REC_TMO                  ; 30 s without a key: done
  BNE .sg_t
  DEC REC_TMO+1
  BMI .sg_end
.sg_t:
  DEC REC_TMO
  JMP .sg_l
.sg_end:
  JSR VDP_INT_OFF
  LDA #0
  JSR REC_INITS
  JSR VDP_INT_ON
  LDA #1
  JSR REC_SND
  LDA #90                      ; the signed table stays 1.5 s
  STA REC_T
.sg_w:
  JSR VDP_INT_OFF
  JSR VDP_INT_ON
  DEC REC_T
  BNE .sg_w
  RTS

; the letter REC_CUR of the row REC_POS: UP next, DOWN previous
REC_LETTER:
  LDA REC_POS
  CLC
  ADC REC_CUR
  TAX                          ; X = row + letter - 4: REC_TAB+4,X
  LDY #REC_NLET-1
.rl_f:
  LDA REC_LETTERS,Y
  CMP REC_TAB+4,X
  BEQ .rl_k
  DEY
  BPL .rl_f
  LDY #REC_NLET-1              ; not a letter ("---"): UP gives A
.rl_k:
  LDA REC_JN
  ORA REC_J
  AND #$01
  BEQ .rl_dn
  INY
  CPY #REC_NLET
  BCC .rl_s
  LDY #0
  BRA .rl_s
.rl_dn:
  DEY
  BPL .rl_s
  LDY #REC_NLET-1
.rl_s:
  LDA REC_LETTERS,Y
  STA REC_TAB+4,X
  RTS

; the initials of the row REC_POS; A <> 0: the letter REC_CUR as "_"
REC_INITS:
  STA REC_K
  LDA REC_POS
  LSR A
  LSR A
  LSR A
  SEC                          ; row REC_R0 + 1 + place
  ADC REC_R0
  TAX
  LDY #7
  JSR REC_XY
  LDX REC_POS
  STZ REC_T
.ri_l:
  LDA REC_TAB+4,X
  LDY REC_T
  CPY REC_CUR
  BNE .ri_p
  LDY REC_K
  BEQ .ri_p
  LDA #'_'
.ri_p:
  JSR REC_OUT
  INX
  INC REC_T
  LDA REC_T
  CMP #3
  BNE .ri_l
  RTS

; ---------------------------------------------------------------
;  title pages
; ---------------------------------------------------------------
REC_TITLE:
  STZ REC_PG

  LDA #<REC_PAGE_T
  STA REC_PT
  LDA #>REC_PAGE_T
  STA REC_PT+1
  RTS

REC_TICK:
  LDA REC_PT
  BNE .tk_d
  LDA REC_PT+1
  BEQ .tk_sw
  DEC REC_PT+1
.tk_d:
  DEC REC_PT
  CLC
  RTS
.tk_sw:
  LDA REC_PG                   ; the other page: the table for 5 s, the game's for 8 s
  EOR #1
  STA REC_PG
  BEQ .tk_g
  LDA #<REC_TAB_T
  STA REC_PT
  LDA #>REC_TAB_T
  STA REC_PT+1
  SEC
  RTS
.tk_g:
  JSR REC_TITLE
  LDA #0
  STA REC_PG                   ; (REC_TITLE keeps page 0)
  SEC
  RTS

; ---------------------------------------------------------------
;  REC_SHOW: header and 8 rows
;    " 1. ABC  00123450  LEG 5"  (columns 4, 7, 12, 22)
; ---------------------------------------------------------------
REC_SHOW:
  LDA #REC_ROW
  STA REC_R0
REC_SHOW_R:                    ; the table with its header on row REC_R0
  LDA REC_POS                  ; kept: the row being signed
  PHA
  JSR REC_WIPE_R
  LDX #0                       ; header, centred
.sh_n:
  LDA REC_HEAD,X
  BEQ .sh_c
  INX
  BRA .sh_n
.sh_c:
  STX REC_T
  LDA #32
  SEC
  SBC REC_T
  LSR A
  TAY
  LDX REC_R0
  JSR REC_XY
  LDX #0
.sh_h:
  LDA REC_HEAD,X
  BEQ .sh_r
  JSR REC_OUT
  INX
  BRA .sh_h
.sh_r:
  LDA #0
.sh_l:
  STA REC_POS
  JSR REC_LINE
  LDA REC_POS
  CLC
  ADC #8
  CMP #64
  BNE .sh_l
  PLA
  STA REC_POS
  RTS

; the row REC_POS
REC_LINE:
  LSR A
  LSR A
  LSR A
  STA REC_K
  SEC                          ; row REC_R0 + 1 + place
  ADC REC_R0
  TAX
  LDY #4
  JSR REC_XY
  LDA REC_K                    ; place
  CLC
  ADC #'1'
  JSR REC_OUT
  LDA #'.'
  JSR REC_OUT
  LDA #' '
  JSR REC_OUT
  LDX REC_POS
  LDA REC_TAB+4,X              ; initials
  JSR REC_OUT
  LDA REC_TAB+5,X
  JSR REC_OUT
  LDA REC_TAB+6,X
  JSR REC_OUT
  LDA REC_TAB,X                ; an empty row: no score
  ORA REC_TAB+1,X
  ORA REC_TAB+2,X
  ORA REC_TAB+3,X
  BEQ .ln_e
  LDA #' '
  JSR REC_OUT
  JSR REC_OUT
  STZ REC_NZ                   ; score: 8 digits, no leading zeros
  TXA
  CLC
  ADC #3
  TAY
  LDA #4
  STA REC_K
.ln_b:
  LDA REC_TAB,Y
  LSR A
  LSR A
  LSR A
  LSR A
  JSR REC_DIG
  LDA REC_K
  CMP #1
  BNE .ln_lo
  STA REC_NZ                   ; the last digit always shows
.ln_lo:
  LDA REC_TAB,Y
  AND #$0F
  JSR REC_DIG
  DEY
  DEC REC_K
  BNE .ln_b
  LDX REC_POS                  ; the extra byte with its label
  LDA REC_TAB+7,X
  BEQ .ln_e
  LDA #' '
  JSR REC_OUT
  JSR REC_OUT
  LDX #0
.ln_x:
  LDA REC_XLBL,X
  BEQ .ln_v
  JSR REC_OUT
  INX
  BRA .ln_x
.ln_v:
  LDX REC_POS
  LDA REC_TAB+7,X
  JMP REC_DEC
.ln_e:
  RTS

; A = digit 0-9; a blank while no digit has been printed
REC_DIG:
  CMP #0
  BNE .dg_p
  LDA REC_NZ
  BNE .dg_0
  LDA #' '
  JMP REC_OUT
.dg_0:
  LDA #0
.dg_p:
  ORA #'0'
  JSR REC_OUT
  LDA #1
  STA REC_NZ
  RTS

; A = 0-255 in decimal, no leading zeros
REC_DEC:
  STZ REC_NZ
  LDX #'0'-1
.dc_h:
  INX
  SEC
  SBC #100
  BCS .dc_h
  ADC #100
  CPX #'0'
  BEQ .dc_t
  PHA
  TXA
  JSR REC_OUT
  PLA
  INC REC_NZ
.dc_t:
  LDX #'0'-1
.dc_t1:
  INX
  SEC
  SBC #10
  BCS .dc_t1
  ADC #10
  LDY REC_NZ
  BNE .dc_tp
  CPX #'0'
  BEQ .dc_u
.dc_tp:
  PHA
  TXA
  JSR REC_OUT
  PLA
.dc_u:
  ORA #'0'
  ; fall into REC_OUT

; one character to the VDP. Every write of the table goes through here, so two writes
; are at least 14 cycles apart: while it draws the screen the TMS9918A needs about 8 us
; between two accesses, or a character is lost (the emulators do not show it)
REC_OUT:
  .ifdef REC_BMP
  PHA                          ; a bitmap game draws the character in its cell
  PHX
  PHY
  JSR REC_CHR
  PLY
  PLX
  PLA
  .else
  STA VDATA
  .endif
  RTS

; REC_WIPEN rows from REC_ROW blank (REC_WIPE_R: from REC_R0)
REC_WIPE:
  LDA #REC_ROW
  STA REC_R0
REC_WIPE_R:
  .ifdef REC_BMP
  LDA REC_R0
  LDX #REC_WIPEN
  JMP REC_CLRROWS
  .endif
  LDA REC_R0
  STA REC_K
  CLC
  ADC #REC_WIPEN
  STA REC_T
.wp_r:
  LDX REC_K
  LDY #0
  JSR REC_XY
  LDX #32
  LDA #' '
.wp_c:
  STA VDATA                    ; 11 cycles per write (see REC_OUT)
  NOP
  DEX
  BNE .wp_c
  INC REC_K
  LDA REC_K
  CMP REC_T
  BNE .wp_r
  RTS

; X = row, Y = column, A = offset in REC_TXT: the text up to 0
REC_PUTS:
  PHA
  JSR REC_XY
  PLX
.pu_l:
  LDA REC_TXT,X
  BEQ .pu_e
  JSR REC_OUT
  INX
  BRA .pu_l
.pu_e:
  RTS

REC_TXT:
  .ifdef REC_ITALIAN
RT_NEW:    .byte "NUOVO RECORD",0
RT_PLAYER: .byte "GIOCATORE ",0
RT_H1:     .byte "SU/GIU'         LETTERA",0
RT_H2:     .byte "SINISTRA/DESTRA SPOSTA",0
RT_H3:     .byte "TASTO           AVANTI/OK",0
RT_NEWX    = 10                ; columns of the texts
RT_PLX     = 10
RT_HX      = 4
  .else
RT_NEW:    .byte "NEW RECORD",0
RT_PLAYER: .byte "PLAYER ",0
RT_H1:     .byte "UP/DOWN    LETTER",0
RT_H2:     .byte "LEFT/RIGHT MOVE",0
RT_H3:     .byte "BUTTON     NEXT/OK",0
RT_NEWX    = 11
RT_PLX     = 12
RT_HX      = 7
  .endif
; ===============================================================
;  TABLES
; ===============================================================
SC_COL:     .byte 4,26                         ; score of player 1 / 2 on row 0
BITS:       .byte 1,2,4,8,16,32,64,128
S_BIG = S_SPLASH                               ; (lib_sound: a big noise is not cut by a small one)

; the lane under every screen row ($FF = none); the stream lane of every step of Spike
ROW_LANE:   .byte $FF,$FF,$FF,0,0,1,1,2,2,3,3,$FF,$FF,4,4,5,5,6,6,7,7,$FF,$FF,$FF
HY_LANE:    .byte $FF,$FF,$FF,$FF,$FF,$FF,3,2,1,0,$FF     ; (only the stream carries him)
; the holes: x of Spike in them; the hedge row: hole * 2 + right half, $FF = hedge
HOLE_X:     .byte 24,72,120,168,216
HEDGE_MAP:  .byte $FF,$FF,$FF,0,1,$FF,$FF,$FF,$FF,2,3,$FF,$FF,$FF,$FF,4,5,$FF,$FF,$FF,$FF,6,7,$FF,$FF,$FF,$FF,8,9,$FF,$FF,$FF
; grass: mostly plain, a few tufts and flowers
GRASSP:     .byte T_GRASS,T_GRASS+1,T_GRASS,T_GRASS,T_GRASS+2,T_GRASS,T_GRASS+1,T_GRASS
            .byte T_GRASS,T_GRASS,T_GRASS+1,T_GRASS,T_GRASS,T_GRASS+2,T_GRASS,T_GRASS+1
; KT of every lane
KT_LO:      .byte <(KT+0),<(KT+96),<(KT+192),<(KT+288),<(KT+384),<(KT+480),<(KT+576),<(KT+672)
KT_HI:      .byte >(KT+0),>(KT+96),>(KT+192),>(KT+288),>(KT+384),>(KT+480),>(KT+576),>(KT+672)
; the diving pads: state and frames of every step of the cycle
DSEQ_S:     .byte 0,1,2,3,2,1
DSEQ_T:     .byte 200,24,24,80,24,24

; the time of the day
DAY_LO:     .byte <TXT_D0,<TXT_D1,<TXT_D2,<TXT_D3
DAY_HI:     .byte >TXT_D0,>TXT_D1,>TXT_D2,>TXT_D3
TXT_D0:     .byte "MORNING",0
TXT_D1:     .byte "AFTERNOON",0
TXT_D2:     .byte "SUNSET",0
TXT_D3:     .byte "NIGHT",0

; title: Spike (2), the beetle, the little one, fox, heron, snake (sprite Y, X, pattern, colour, second frame)
TITLE_NS = 7
TITLE_SY:   .byte 23,23,91,107,123,123,123
TITLE_SX:   .byte 24,24,56,56,32,56,80
TITLE_SN:   .byte PT_SPIKE,PT_SPIKE+4,PT_BEETLE,PT_BABY,PT_FOX,PT_HERON,PT_SNAKE
TITLE_SC:   .byte 6,11,8,6,9,15,3
TITLE_SA:   .byte 8,8,0,0,4,4,4

TXT_LEVELH: .byte "LEVEL "
TXT_PLAYERH: .byte "PLAYER "
; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 0,12,"HI",0
  .byte $FF
TXT_TOP2:
  .byte 0,22,"2UP",0,$FF
TXT_BUTTONS:
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,6,"SPIKE IS GOING HOME",0
  .byte 10,3,"50 A HOLE  1000 THE HEDGE",0
  .byte 12,10,"BEETLE        200",0
  .byte 14,10,"LITTLE ONE    200",0
  .byte 16,13,"LOOK OUT!",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 12,11,"PLAYER ",0,$FF

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 13, 9, 12, 0      ; volume at the attack of the note
FLOOR_TAB:     .byte 8, 5, 7, 0        ; lowest volume reached by the decay
DECMASK_TAB:   .byte 3, 7, 3, 0        ; the volume drops by 1 when (age AND mask) = 0
; drums: 1 kick, 2 snare, 3 hi-hat, 4 cymbal
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7
BITMASK:    .byte $80,$40,$20,$10,$08,$04,$02,$01

; font 5x7: ASCII $20-$5F, 8 bytes each
FONT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$20,$20,$00,$20,$20,$00,$00
  .byte $50,$50,$50,$00,$00,$00,$00,$00
  .byte $50,$50,$F8,$50,$F8,$50,$50,$00
  .byte $20,$78,$A0,$70,$28,$F0,$20,$00
  .byte $C0,$C8,$10,$20,$40,$98,$18,$00
  .byte $40,$A0,$A0,$40,$A8,$90,$68,$00
  .byte $20,$20,$40,$00,$00,$00,$00,$00
  .byte $20,$40,$80,$80,$80,$40,$20,$00
  .byte $20,$10,$08,$08,$08,$10,$20,$00
  .byte $20,$A8,$70,$20,$70,$A8,$20,$00
  .byte $00,$20,$20,$F8,$20,$20,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$40,$00
  .byte $00,$00,$00,$F8,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$00,$00
  .byte $00,$08,$10,$20,$40,$80,$00,$00
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00
  .byte $20,$60,$20,$20,$20,$20,$70,$00
  .byte $70,$88,$08,$30,$40,$80,$F8,$00
  .byte $F8,$08,$10,$30,$08,$88,$70,$00
  .byte $10,$30,$50,$90,$F8,$10,$10,$00
  .byte $F8,$80,$F0,$08,$08,$88,$70,$00
  .byte $38,$40,$80,$F0,$88,$88,$70,$00
  .byte $F8,$08,$10,$20,$40,$40,$40,$00
  .byte $70,$88,$88,$70,$88,$88,$70,$00
  .byte $70,$88,$88,$78,$08,$10,$E0,$00
  .byte $00,$00,$20,$00,$20,$00,$00,$00
  .byte $00,$00,$20,$00,$20,$20,$40,$00
  .byte $10,$20,$40,$80,$40,$20,$10,$00
  .byte $00,$00,$F8,$00,$F8,$00,$00,$00
  .byte $40,$20,$10,$08,$10,$20,$40,$00
  .byte $70,$88,$10,$20,$20,$00,$20,$00
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00
  .byte $20,$50,$88,$88,$F8,$88,$88,$00
  .byte $F0,$88,$88,$F0,$88,$88,$F0,$00
  .byte $70,$88,$80,$80,$80,$88,$70,$00
  .byte $F0,$88,$88,$88,$88,$88,$F0,$00
  .byte $F8,$80,$80,$F0,$80,$80,$F8,$00
  .byte $F8,$80,$80,$F0,$80,$80,$80,$00
  .byte $78,$80,$80,$80,$98,$88,$78,$00
  .byte $88,$88,$88,$F8,$88,$88,$88,$00
  .byte $70,$20,$20,$20,$20,$20,$70,$00
  .byte $08,$08,$08,$08,$08,$88,$70,$00
  .byte $88,$90,$A0,$C0,$A0,$90,$88,$00
  .byte $80,$80,$80,$80,$80,$80,$F8,$00
  .byte $88,$D8,$A8,$A8,$88,$88,$88,$00
  .byte $88,$88,$C8,$A8,$98,$88,$88,$00
  .byte $70,$88,$88,$88,$88,$88,$70,$00
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00
  .byte $70,$88,$88,$88,$A8,$90,$68,$00
  .byte $F0,$88,$88,$F0,$A0,$90,$88,$00
  .byte $70,$88,$80,$70,$08,$88,$70,$00
  .byte $F8,$20,$20,$20,$20,$20,$20,$00
  .byte $88,$88,$88,$88,$88,$88,$70,$00
  .byte $88,$88,$88,$88,$50,$50,$20,$00
  .byte $88,$88,$88,$A8,$A8,$D8,$88,$00
  .byte $88,$88,$50,$20,$50,$88,$88,$00
  .byte $88,$88,$50,$20,$20,$20,$20,$00
  .byte $F8,$08,$10,$20,$40,$80,$F8,$00
  .byte $F8,$C0,$C0,$C0,$C0,$C0,$F8,$00
  .byte $00,$80,$40,$20,$10,$08,$00,$00
  .byte $F8,$18,$18,$18,$18,$18,$F8,$00
  .byte $00,$00,$20,$50,$88,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$F8,$00

; ===============================================================
;  GRAPHICS, LANES AND SOUND TABLES (generated)
; ===============================================================
; HEDGE HOP: generated by dev/gen_hedge_hop.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; fixed tiles
T_HEDGE = 1
T_HOLE = 2
T_HOME = 6
T_BEET = 10
T_GRASS = 1
T_BAR = 4
T_LIFE = 22
PT_SPIKE = 0
PT_SQUASH = 64
PT_SPLASH = 72
PT_FOX = 80
PT_HERON = 96
PT_SNAKE = 104
PT_BABY = 120
PT_BEETLE = 124
DIVE_LO = 144
DIVE_N = 4
NLEV = 10
SPR_LEN = 1024
SPR_PAGES = 4
SPRITES:
  .byte $00,$00,$00,$00,$00,$10,$38,$5F,$6D,$FF,$5B,$FF,$6D,$3F,$16,$00,$00,$00,$00,$00,$00,$08,$1C,$FA,$B6,$FF,$6D,$FF,$B6,$FC,$D0,$00
  .byte $00,$01,$03,$07,$0B,$0F,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$D0,$F0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$10,$38,$5F,$6D,$FF,$5B,$FF,$2D,$3F,$16,$00,$00,$00,$00,$00,$00,$08,$1C,$FA,$B6,$FF,$6D,$FF,$B4,$FC,$D0,$00
  .byte $00,$01,$03,$07,$0B,$4F,$87,$00,$00,$00,$00,$00,$40,$80,$00,$00,$00,$80,$C0,$E0,$D0,$F2,$E1,$00,$00,$00,$00,$00,$02,$01,$00,$00
  .byte $0A,$1F,$3B,$6E,$3F,$7B,$6E,$3F,$7B,$6E,$3F,$7B,$2E,$3F,$1B,$0E,$00,$80,$40,$E0,$C0,$80,$80,$80,$80,$80,$80,$C0,$E0,$40,$80,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$68,$7C,$7E,$7E,$7C,$68,$30,$00,$00,$00,$00
  .byte $0A,$0F,$3B,$6E,$3F,$7B,$6E,$3F,$7B,$6E,$3F,$7B,$2E,$3F,$0B,$0E,$00,$80,$40,$E0,$C0,$80,$80,$80,$80,$80,$80,$C0,$E0,$40,$80,$00
  .byte $20,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$20,$40,$20,$00,$00,$30,$68,$7C,$7E,$7E,$7C,$68,$30,$00,$00,$20,$40
  .byte $00,$0B,$3F,$6D,$FF,$B6,$FF,$6D,$5F,$38,$10,$00,$00,$00,$00,$00,$00,$68,$FC,$B6,$FF,$DA,$FF,$B6,$FA,$1C,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$0F,$0B,$07,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$D0,$E0,$C0,$80,$00
  .byte $00,$0B,$3F,$2D,$FF,$B6,$FF,$6D,$5F,$38,$10,$00,$00,$00,$00,$00,$00,$68,$FC,$B4,$FF,$DA,$FF,$B6,$FA,$1C,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$80,$40,$00,$00,$00,$00,$00,$87,$4F,$0B,$07,$03,$01,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$E1,$F2,$D0,$E0,$C0,$80,$00
  .byte $00,$01,$02,$07,$03,$01,$01,$01,$01,$01,$01,$03,$07,$02,$01,$00,$70,$D8,$FC,$74,$DE,$FC,$76,$DE,$FC,$76,$DE,$FC,$76,$DC,$F8,$50
  .byte $00,$00,$00,$00,$0C,$16,$3E,$7E,$7E,$3E,$16,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$02,$07,$03,$01,$01,$01,$01,$01,$01,$03,$07,$02,$01,$00,$70,$D0,$FC,$74,$DE,$FC,$76,$DE,$FC,$76,$DE,$FC,$76,$DC,$F0,$50
  .byte $02,$04,$00,$00,$0C,$16,$3E,$7E,$7E,$3E,$16,$0C,$00,$00,$04,$02,$04,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$04
  .byte $00,$00,$00,$00,$00,$54,$FF,$CF,$FF,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$AA,$FF,$F3,$FF,$54,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$02,$05,$02,$06,$05,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$60,$40,$A0,$40,$00,$00,$00,$00,$00
  .byte $00,$03,$06,$0D,$18,$30,$60,$50,$30,$60,$50,$30,$0D,$0B,$06,$00,$00,$60,$D0,$B0,$0C,$0A,$06,$0C,$0A,$06,$0C,$18,$B0,$60,$C0,$00
  .byte $00,$00,$00,$50,$70,$F8,$78,$3F,$1F,$1F,$14,$12,$22,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$FE,$FC,$F8,$28,$48,$44,$00,$00,$00
  .byte $00,$00,$00,$50,$70,$F8,$78,$3F,$1F,$1F,$0A,$0A,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$FE,$FC,$F8,$50,$50,$50,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$F0,$7F,$3F,$1F,$14,$12,$22,$00,$00,$00,$00,$00,$00,$0A,$0E,$1F,$1E,$FC,$F8,$F8,$28,$48,$44,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$F0,$7F,$3F,$1F,$0A,$0A,$0A,$00,$00,$00,$00,$00,$00,$0A,$0E,$1F,$1E,$FC,$F8,$F8,$50,$50,$50,$00,$00,$00
  .byte $0C,$1E,$17,$07,$06,$0C,$0C,$1F,$3F,$3F,$1F,$0F,$02,$02,$02,$06,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$F8,$E0,$80,$80,$80,$C0
  .byte $00,$70,$3F,$07,$06,$0C,$0C,$1F,$3F,$3F,$1F,$0F,$02,$02,$02,$06,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$F8,$E0,$80,$80,$80,$C0
  .byte $00,$00,$00,$00,$00,$00,$03,$87,$4C,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$9F,$F6,$60,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$30,$4C,$87,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$F6,$9F,$0C,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$30,$F9,$6F,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E1,$32,$0C,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$06,$6F,$F9,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$32,$E1,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0A,$1F,$3F,$1F,$3F,$1F,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$F0,$F8,$FA,$FA,$F0,$A0,$00,$00,$00,$00
  .byte $00,$00,$04,$02,$07,$0D,$1F,$17,$1E,$1F,$17,$0F,$07,$00,$00,$00,$00,$00,$20,$40,$E0,$B0,$F8,$E8,$78,$F8,$E8,$F0,$E0,$00,$00,$00

; the tiles of the game, per third
TP0_1:
  .byte $92,$66,$B5,$24,$59,$96,$64,$93,$FF,$FF,$F0,$E0,$C0,$C0,$80,$80,$FF,$FF,$0F,$07,$03,$03,$01,$01,$80,$80,$80,$C0,$C0,$E0,$F0,$FF
  .byte $01,$01,$01,$03,$03,$07,$0F,$FF,$00,$2A,$7F,$7F,$73,$6D,$36,$1C,$00,$54,$FE,$FE,$CE,$B6,$6C,$38,$0D,$07,$03,$01,$00,$00,$00,$00
  .byte $B0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$04,$02,$07,$0D,$1F,$17,$00,$00,$20,$40,$E0,$B0,$F8,$E8,$1E,$1F,$17,$0F,$07,$00,$00,$00
  .byte $78,$F8,$E8,$F0,$E0,$00,$00,$00
TC0_1:
  .byte $2C,$2C,$2C,$2C,$2C,$2C,$2C,$2C,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1
  .byte $C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$61,$61,$61,$61,$B1,$B1,$B1,$B1,$61,$61,$61,$61,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$11,$11,$11,$11,$11
  .byte $B1,$B1,$B1,$11,$11,$11,$11,$11,$11,$11,$E1,$E1,$81,$81,$81,$81,$11,$11,$E1,$E1,$81,$81,$81,$81,$81,$81,$81,$81,$81,$11,$11,$11
  .byte $81,$81,$81,$81,$81,$11,$11,$11
TP0_96:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$02,$02,$02,$00,$01,$07,$0F,$0F,$09,$0B,$0B,$00,$07,$1F,$3F,$3E,$27,$2D,$2D
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$03,$03,$03,$01,$00,$00,$0B,$09,$0F,$0F,$0F,$07,$01,$00,$2D,$27,$3E,$3F,$3F,$1F,$07,$00
  .byte $00,$1F,$7F,$FF,$FB,$9F,$B7,$B7,$00,$7F,$FF,$FF,$EF,$7F,$DF,$DD,$00,$FF,$FF,$FF,$BF,$FF,$7F,$77,$00,$FF,$FF,$FF,$FF,$FF,$FF,$DF
  .byte $B7,$9F,$FB,$FF,$FF,$7F,$1F,$00,$DF,$7F,$EF,$FD,$FF,$FF,$7F,$00,$7F,$FF,$BF,$F7,$FF,$FF,$FF,$00,$FF,$FF,$FF,$DF,$FF,$FF,$FF,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FD,$00,$FF,$FF,$FF,$FF,$FF,$FF,$F7,$00,$FF,$FF,$FF,$FF,$FF,$FF,$DF
  .byte $FE,$FF,$FF,$7F,$FF,$FF,$FF,$00,$FB,$FF,$FF,$FD,$FF,$FF,$FF,$00,$EF,$FF,$FF,$F7,$FF,$FF,$FF,$00,$BF,$FF,$FF,$DF,$FF,$FF,$FF,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FD,$FF,$FE,$FE,$00,$FE,$FF,$FF,$F7,$FE,$FB,$FB
  .byte $FE,$FF,$FF,$7F,$FF,$FF,$FF,$00,$FB,$FF,$FF,$FF,$FF,$FF,$FF,$00,$EE,$FF,$FD,$FF,$FF,$FF,$FF,$00,$BB,$FE,$F7,$FF,$FF,$FF,$FE,$00
  .byte $00,$F8,$FE,$FF,$DF,$F9,$ED,$ED,$00,$E0,$F8,$FC,$7C,$E4,$B4,$B4,$00,$80,$E0,$F0,$F0,$90,$D0,$D0,$00,$00,$80,$C0,$C0,$40,$40,$40
  .byte $ED,$F9,$DF,$FF,$FF,$FE,$F8,$00,$B4,$E4,$7C,$FC,$FC,$F8,$E0,$00,$D0,$90,$F0,$F0,$F0,$E0,$80,$00,$40,$40,$C0,$C0,$C0,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$01,$03,$05,$06,$07,$07,$00,$01,$07,$0F,$17,$1B,$1D,$1F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$07,$07,$07,$02,$03,$01,$00,$00,$1F,$1E,$1D,$0B,$0F,$07,$01,$00
  .byte $00,$07,$1F,$3F,$5F,$6F,$76,$7F,$00,$1F,$7E,$FE,$7D,$BD,$DB,$FC,$00,$7E,$FB,$FB,$F7,$F7,$6F,$F3,$00,$F8,$EE,$EF,$DF,$DE,$BD,$CF
  .byte $7E,$7B,$77,$2F,$3F,$1F,$07,$00,$FB,$ED,$DD,$BD,$FD,$7F,$1F,$00,$EF,$B5,$76,$F7,$F7,$FF,$7E,$00,$BF,$D7,$DB,$DD,$DF,$FE,$F8,$00
  .byte $00,$E0,$B8,$BC,$7C,$7A,$F6,$3E,$00,$80,$E0,$F0,$F0,$E8,$D8,$F8,$00,$00,$80,$C0,$C0,$A0,$60,$E0,$00,$00,$00,$00,$00,$80,$80,$80
  .byte $FE,$5E,$6E,$74,$7C,$F8,$E0,$00,$F8,$78,$B8,$D0,$F0,$E0,$80,$00,$E0,$E0,$E0,$40,$C0,$80,$00,$00,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$E0,$B8,$BC,$7C,$7A,$F6,$3E,$00,$80,$E0,$F0,$F1,$E9,$D9,$F9,$00,$00,$81,$C3,$C5,$A6,$67,$E7,$00,$01,$07,$0F,$17,$9B,$9D,$9F
  .byte $FE,$5E,$6E,$74,$7C,$F8,$E0,$00,$F9,$79,$B9,$D0,$F0,$E0,$80,$00,$E7,$E7,$E7,$42,$C3,$81,$00,$00,$9F,$9E,$9D,$0B,$0F,$07,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$01,$03,$05,$06,$07,$07,$00,$01,$07,$0F,$17,$1B,$1D,$1F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$07,$07,$07,$02,$03,$01,$00,$00,$1F,$1E,$1D,$0B,$0F,$07,$01,$00
  .byte $00,$07,$1F,$3F,$5F,$6F,$76,$7F,$00,$1F,$7E,$FE,$7D,$BD,$DB,$FC,$00,$7E,$FB,$FB,$F7,$F7,$6F,$F3,$00,$F8,$EE,$EF,$DF,$DE,$BD,$CF
  .byte $7E,$7B,$77,$2F,$3F,$1F,$07,$00,$FB,$ED,$DD,$BD,$FD,$7F,$1F,$00,$EF,$B5,$76,$F7,$F7,$FF,$7E,$00,$BF,$D7,$DB,$DD,$DF,$FE,$F8,$00
  .byte $00,$E0,$B8,$BC,$7C,$7A,$F6,$3E,$00,$80,$E0,$F0,$F0,$E8,$D8,$F8,$00,$00,$80,$C0,$C0,$A0,$60,$E0,$00,$00,$00,$00,$00,$80,$80,$80
  .byte $FE,$5E,$6E,$74,$7C,$F8,$E0,$00,$F8,$78,$B8,$D0,$F0,$E0,$80,$00,$E0,$E0,$E0,$40,$C0,$80,$00,$00,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$E0,$B8,$BC,$7C,$7A,$F6,$3E,$00,$80,$E0,$F0,$F1,$E9,$D9,$F9,$00,$00,$81,$C3,$C5,$A6,$67,$E7,$00,$01,$07,$0F,$17,$9B,$9D,$9F
  .byte $FE,$5E,$6E,$74,$7C,$F8,$E0,$00,$F9,$79,$B9,$D0,$F0,$E0,$80,$00,$E7,$E7,$E7,$42,$C3,$81,$00,$00,$9F,$9E,$9D,$0B,$0F,$07,$01,$00
TC0_96:
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
  .byte $44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24,$44,$34,$34,$34,$24,$24,$24,$24
  .byte $24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44,$24,$24,$24,$C4,$C4,$C4,$C4,$44
TP1_1:
  .byte $00,$10,$28,$00,$02,$05,$00,$00,$00,$00,$40,$A4,$0A,$00,$00,$00,$00,$30,$48,$30,$00,$04,$0A,$04
TC1_1:
  .byte $C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3
TP1_96:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$02,$02,$02,$00,$01,$07,$0F,$0F,$09,$0B,$0B,$00,$07,$1F,$3F,$3E,$27,$2D,$2D
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$03,$03,$03,$01,$00,$00,$0B,$09,$0F,$0F,$0F,$07,$01,$00,$2D,$27,$3E,$3F,$3F,$1F,$07,$00
  .byte $00,$1F,$7F,$FF,$FB,$9F,$B7,$B7,$00,$7F,$FF,$FF,$EF,$7F,$DF,$DD,$00,$FF,$FF,$FF,$BF,$FF,$7F,$77,$00,$FF,$FF,$FF,$FF,$FF,$FF,$DF
  .byte $B7,$9F,$FB,$FF,$FF,$7F,$1F,$00,$DF,$7F,$EF,$FD,$FF,$FF,$7F,$00,$7F,$FF,$BF,$F7,$FF,$FF,$FF,$00,$FF,$FF,$FF,$DF,$FF,$FF,$FF,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FD,$00,$FF,$FF,$FF,$FF,$FF,$FF,$F7,$00,$FF,$FF,$FF,$FF,$FF,$FF,$DF
  .byte $FE,$FF,$FF,$7F,$FF,$FF,$FF,$00,$FB,$FF,$FF,$FD,$FF,$FF,$FF,$00,$EF,$FF,$FF,$F7,$FF,$FF,$FF,$00,$BF,$FF,$FF,$DF,$FF,$FF,$FF,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FD,$FF,$FE,$FE,$00,$FE,$FF,$FF,$F7,$FE,$FB,$FB
  .byte $FE,$FF,$FF,$7F,$FF,$FF,$FF,$00,$FB,$FF,$FF,$FF,$FF,$FF,$FF,$00,$EE,$FF,$FD,$FF,$FF,$FF,$FF,$00,$BB,$FE,$F7,$FF,$FF,$FF,$FE,$00
  .byte $00,$F8,$FE,$FF,$DF,$F9,$ED,$ED,$00,$E0,$F8,$FC,$7C,$E4,$B4,$B4,$00,$80,$E0,$F0,$F0,$90,$D0,$D0,$00,$00,$80,$C0,$C0,$40,$40,$40
  .byte $ED,$F9,$DF,$FF,$FF,$FE,$F8,$00,$B4,$E4,$7C,$FC,$FC,$F8,$E0,$00,$D0,$90,$F0,$F0,$F0,$E0,$80,$00,$40,$40,$C0,$C0,$C0,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$00,$00,$00,$00,$00,$00,$07,$0F,$00,$00,$00,$00,$00,$00,$1E,$3F
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$03,$01,$00,$00,$00,$00,$00,$FC,$0F,$07,$00,$00,$00,$00,$00,$F0,$3F,$1E,$00,$00,$00,$00,$00,$C0
  .byte $00,$00,$00,$00,$01,$03,$7B,$FF,$00,$00,$00,$00,$06,$0F,$EF,$FF,$00,$00,$00,$00,$18,$3C,$BD,$FF,$00,$00,$00,$00,$60,$F0,$F6,$FF
  .byte $FF,$7B,$03,$01,$00,$00,$00,$00,$FF,$EF,$0F,$06,$00,$00,$00,$00,$FF,$BD,$3C,$18,$00,$00,$00,$00,$FF,$F6,$F0,$60,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$D8,$FD,$00,$00,$00,$00,$00,$00,$60,$F4,$00,$00,$00,$00,$00,$00,$80,$D0,$00,$00,$00,$00,$00,$00,$00,$40
  .byte $FD,$D8,$C0,$80,$00,$00,$00,$00,$F4,$60,$00,$00,$00,$00,$00,$03,$D0,$80,$00,$00,$00,$00,$00,$0F,$40,$00,$00,$00,$00,$00,$00,$3F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$02,$02,$02,$02,$00,$03,$07,$08,$0A,$0A,$0A,$0A,$00,$0E,$1F,$23,$2B,$2B,$2B,$2B
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$02,$02,$02,$02,$02,$01,$00,$FC,$0A,$0A,$0A,$0A,$08,$07,$03,$F0,$2B,$2B,$2B,$2B,$23,$1F,$0E,$C0
  .byte $00,$38,$7F,$8F,$AE,$AE,$AE,$AE,$00,$E0,$FF,$3F,$BB,$BB,$BB,$BB,$00,$83,$FF,$FF,$EF,$EE,$EE,$EE,$00,$0E,$FF,$FF,$BF,$B8,$BB,$BB
  .byte $AE,$AE,$AE,$AE,$8F,$7F,$38,$00,$BB,$BB,$BB,$BB,$3F,$FF,$E0,$00,$EE,$EE,$EE,$EF,$FF,$FF,$83,$00,$BB,$BB,$B8,$BF,$FF,$FF,$0E,$00
  .byte $00,$38,$FF,$FF,$FF,$E0,$EF,$EF,$00,$E0,$FF,$FF,$FF,$80,$BF,$BF,$00,$80,$FF,$FF,$FF,$00,$FF,$FF,$00,$00,$FF,$FF,$FF,$00,$FF,$FF
  .byte $EF,$EF,$E0,$FF,$FF,$FF,$38,$00,$BF,$BF,$80,$FF,$FF,$FF,$E0,$00,$FF,$FF,$00,$FF,$FF,$FF,$80,$00,$FF,$FF,$00,$FF,$FF,$FF,$00,$00
  .byte $00,$03,$FF,$FF,$FF,$00,$FF,$FF,$00,$0E,$FF,$FF,$FF,$00,$FF,$FF,$00,$3B,$FF,$FF,$FF,$00,$FF,$FF,$00,$EE,$FF,$FF,$FF,$00,$FF,$FF
  .byte $FF,$FF,$00,$FF,$FF,$FF,$03,$00,$FF,$FF,$00,$FF,$FF,$FF,$0E,$00,$FF,$FF,$00,$FF,$FF,$FF,$3B,$00,$FF,$FF,$00,$FF,$FF,$FF,$EE,$00
  .byte $00,$B8,$FC,$FC,$FE,$01,$FD,$FD,$00,$E0,$F0,$F0,$F8,$04,$F4,$F4,$00,$80,$C0,$C0,$E0,$10,$D0,$D0,$00,$00,$00,$00,$80,$40,$40,$40
  .byte $FD,$FD,$01,$FE,$FC,$FC,$B8,$00,$F4,$F4,$04,$F8,$F0,$F0,$E0,$03,$D0,$D0,$10,$E0,$C0,$C0,$80,$0F,$40,$40,$40,$80,$00,$00,$00,$3F
TC1_96:
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4,$44,$A4,$A4,$A4,$64,$A4,$A4,$A4
  .byte $A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44,$A4,$A4,$64,$A4,$A4,$A4,$A4,$44
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1
  .byte $11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81
  .byte $81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1
  .byte $11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81
  .byte $81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1
  .byte $11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81
  .byte $81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11
  .byte $11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81
  .byte $81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11
  .byte $11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81
  .byte $81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$11
  .byte $11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81,$11,$11,$F1,$F1,$F1,$F1,$81,$81
  .byte $81,$81,$F1,$F1,$F1,$F1,$11,$11,$81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1,$81,$81,$F1,$F1,$F1,$F1,$11,$E1
TP2_1:
  .byte $00,$10,$28,$00,$02,$05,$00,$00,$00,$00,$40,$A4,$0A,$00,$00,$00,$00,$30,$48,$30,$00,$04,$0A,$04,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$80,$80,$80,$00,$00,$00,$C0,$C0,$C0,$C0,$C0,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00,$00,$00,$F0,$F0,$F0,$F0,$F0,$00,$00
  .byte $00,$F8,$F8,$F8,$F8,$F8,$00,$00,$00,$FC,$FC,$FC,$FC,$FC,$00,$00,$00,$FE,$FE,$FE,$FE,$FE,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$00,$00,$00,$C0,$C0,$C0,$C0,$C0,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$00,$00
  .byte $00,$F0,$F0,$F0,$F0,$F0,$00,$00,$00,$F8,$F8,$F8,$F8,$F8,$00,$00,$00,$FC,$FC,$FC,$FC,$FC,$00,$00,$00,$FE,$FE,$FE,$FE,$FE,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$00,$00,$28,$7E,$FE,$DC,$7E,$24,$00,$00
TC2_1:
  .byte $C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$C3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$F1,$81,$F1,$11,$11
TP2_96:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$03,$03,$00,$00,$03,$07,$0F,$0E,$0C,$0C,$00,$00,$0E,$1F,$3F,$39,$31,$31
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$03,$03,$03,$03,$01,$00,$00,$FC,$0C,$0C,$0E,$0F,$07,$03,$00,$F0,$31,$31,$39,$3F,$1F,$0E,$00,$C0
  .byte $00,$00,$38,$7F,$FF,$E7,$C7,$C7,$00,$00,$E0,$FF,$FF,$9F,$1F,$1F,$00,$00,$81,$FF,$FF,$7F,$7F,$7F,$00,$00,$07,$FF,$FF,$FD,$FC,$FC
  .byte $C7,$C7,$E7,$FF,$7F,$38,$00,$00,$1F,$1F,$9F,$FF,$FF,$E0,$00,$00,$7F,$7F,$7F,$FF,$FF,$81,$00,$00,$FC,$FC,$FD,$FF,$FF,$07,$00,$00
  .byte $00,$00,$1C,$FE,$FF,$F7,$F3,$F3,$00,$00,$70,$F8,$FC,$DC,$CC,$CC,$00,$00,$C0,$E0,$F0,$70,$30,$30,$00,$00,$00,$80,$C0,$C0,$C0,$C0
  .byte $F3,$F3,$F7,$FF,$FE,$1C,$00,$00,$CC,$CC,$DC,$FC,$F8,$70,$00,$03,$30,$30,$70,$F0,$E0,$C0,$00,$0F,$C0,$C0,$C0,$C0,$80,$00,$00,$3F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$07,$07,$07,$03,$02,$02,$02,$00,$1F,$1F,$1F,$0F,$08,$0B,$0B
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$01,$01,$01,$FC,$02,$02,$02,$03,$07,$07,$07,$F0,$0B,$0B,$08,$0F,$1F,$1F,$1F,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$00,$00,$00,$00,$00,$00,$07,$0F,$00,$00,$00,$00,$00,$00,$1E,$3F
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$03,$01,$00,$00,$00,$00,$00,$FC,$0F,$07,$00,$00,$00,$00,$00,$F0,$3F,$1E,$00,$00,$00,$00,$00,$C0
  .byte $00,$00,$00,$00,$01,$03,$7B,$FF,$00,$00,$00,$00,$06,$0F,$EF,$FF,$00,$00,$00,$00,$18,$3C,$BD,$FF,$00,$00,$00,$00,$60,$F0,$F6,$FF
  .byte $FF,$7B,$03,$01,$00,$00,$00,$00,$FF,$EF,$0F,$06,$00,$00,$00,$00,$FF,$BD,$3C,$18,$00,$00,$00,$00,$FF,$F6,$F0,$60,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$D8,$FD,$00,$00,$00,$00,$00,$00,$60,$F4,$00,$00,$00,$00,$00,$00,$80,$D0,$00,$00,$00,$00,$00,$00,$00,$40
  .byte $FD,$D8,$C0,$80,$00,$00,$00,$00,$F4,$60,$00,$00,$00,$00,$00,$03,$D0,$80,$00,$00,$00,$00,$00,$0F,$40,$00,$00,$00,$00,$00,$00,$3F
  .byte $00,$7E,$7E,$7E,$3F,$21,$2D,$2D,$00,$F8,$F8,$F8,$FF,$87,$B7,$B7,$00,$E0,$E0,$E0,$FF,$1F,$DF,$DF,$00,$80,$80,$80,$FF,$7F,$7F,$7F
  .byte $2D,$2D,$21,$3F,$7E,$7E,$7E,$00,$B7,$B7,$87,$FF,$F8,$F8,$F8,$00,$DF,$DF,$1F,$FF,$E0,$E0,$E0,$00,$7F,$7F,$7F,$FF,$80,$80,$80,$00
  .byte $00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$01,$01,$01,$FF,$FF,$FF,$FF,$00,$07,$07,$07,$FF,$FF,$FF,$FF,$00,$1E,$1E,$1E,$FF,$FF,$FE,$FF
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$01,$01,$01,$00,$FF,$FF,$FF,$FF,$07,$07,$07,$00,$FF,$FE,$FF,$FF,$1E,$1E,$1E,$00
  .byte $00,$78,$78,$78,$FC,$FC,$F8,$FD,$00,$E0,$E0,$E0,$F0,$F0,$E0,$F4,$00,$80,$80,$80,$C0,$C0,$80,$D0,$00,$00,$00,$00,$00,$00,$00,$40
  .byte $FD,$F8,$FC,$FC,$78,$78,$78,$00,$F4,$E0,$F0,$F0,$E0,$E0,$E0,$03,$D0,$80,$C0,$C0,$80,$80,$80,$0F,$40,$00,$00,$00,$00,$00,$00,$3F
TC2_96:
  .byte $11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1
  .byte $11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1
  .byte $11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11
  .byte $11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$11,$11,$11,$81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1,$81,$81,$81,$81,$81,$11,$11,$E1
  .byte $11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21
  .byte $21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21
  .byte $21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1,$11,$11,$11,$11,$B1,$B1,$D1,$D1
  .byte $D1,$D1,$B1,$B1,$11,$11,$11,$11,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1,$D1,$D1,$B1,$B1,$11,$11,$11,$E1
  .byte $11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21
  .byte $21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21
  .byte $21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21
  .byte $21,$21,$21,$21,$11,$11,$11,$11,$21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1,$21,$21,$21,$21,$11,$11,$11,$E1

; patterns of the game tiles (loaded after the title)
GFX_GAME:
  .byte 1, $08,$40, <104,>104, <TP0_1,>TP0_1
  .byte 1, $00,$43, <960,>960, <TP0_96,>TP0_96
  .byte 1, $08,$48, <24,>24, <TP1_1,>TP1_1
  .byte 1, $00,$4B, <1024,>1024, <TP1_96,>TP1_96
  .byte 1, $08,$50, <176,>176, <TP2_1,>TP2_1
  .byte 1, $00,$53, <832,>832, <TP2_96,>TP2_96
  .byte 0
; colours of the game tiles (copied through the palette)
GFX_GAMEC:
  .byte 1, $08,$60, <104,>104, <TC0_1,>TC0_1
  .byte 1, $00,$63, <960,>960, <TC0_96,>TC0_96
  .byte 1, $08,$68, <24,>24, <TC1_1,>TC1_1
  .byte 1, $00,$6B, <1024,>1024, <TC1_96,>TC1_96
  .byte 1, $08,$70, <176,>176, <TC2_1,>TC2_1
  .byte 1, $00,$73, <832,>832, <TC2_96,>TC2_96
  .byte 0

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
GFX_TITLE:
  .byte 1, $00,$45, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$46, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$65, <96,>96, $A1,0
  .byte 2, $00,$66, <96,>96, $61,0
  .byte 0

; big letters of the title
BIG_TOP:
  .byte $00,$18,$18,$18,$18,$18,$18,$1F,$00,$18,$18,$18,$18,$18,$18,$F8,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18,$00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
BIG_BOT:
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$F8,$18,$18,$18,$18,$18,$18,$00,$1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
TXT_BIG:
  .byte 3,7,160,161,162,163,164,165,166,167,162,163,32,32,160,161,168,169,170,171,0
  .byte 4,7,192,193,194,195,196,197,198,199,194,195,32,32,192,193,200,201,202,203,0
  .byte $FF

; lanes: type, top row, 1 = the things go left
LANE_T:
  .byte 0,0,1,1,2,3,4,5
LANE_ROW:
  .byte 3,5,7,9,13,15,17,19
LANE_LEFT:
  .byte 1,0,1,0,1,0,1,0
; base tile of every pair of parts: type * 64 + part a * 8 + part b
PAIRC:
  .byte $B0,$B8,$00,$90,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$C8,$D0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$98,$00,$00,$00
  .byte $A0,$00,$00,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $60,$68,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00,$78,$80,$00,$00,$00,$00,$88,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $B0,$B8,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$C8,$00,$00,$00,$00,$00,$00,$00,$00,$D0,$00,$00,$00
  .byte $D8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $90,$98,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$00,$00,$00,$00,$00,$A8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $60,$68,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$78,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$88,$00,$00,$00,$00,$00,$00,$00,$00,$B0,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; what a part is: type * 8 + part (0 empty, 1 solid, 2 diving pad)
SOLID:
  .byte $00,$01,$01,$02,$02,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$01,$01,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00
; the tapes: set * 8 + lane, 64 parts each
TAPE0_0:
  .byte $01,$02,$01,$02,$01,$02,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00,$01,$02,$01,$02
  .byte $01,$02,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00
TAPE0_1:
  .byte $01,$02,$01,$02,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00
  .byte $03,$04,$03,$04,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00
TAPE0_2:
  .byte $01,$02,$02,$02,$02,$03,$00,$00,$00,$01,$02,$02,$02,$02,$02,$03,$00,$00,$00,$01,$02,$02,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02
  .byte $02,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00,$00
TAPE0_3:
  .byte $01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$03
  .byte $00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00
TAPE0_4:
  .byte $01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03
  .byte $04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE0_5:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE0_6:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00
TAPE0_7:
  .byte $01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE1_0:
  .byte $01,$02,$01,$02,$01,$02,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00,$01,$02,$01,$02,$01
  .byte $02,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00,$00
TAPE1_1:
  .byte $01,$02,$01,$02,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$03,$04
  .byte $03,$04,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$00
TAPE1_2:
  .byte $01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02
  .byte $02,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00,$00
TAPE1_3:
  .byte $01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00
  .byte $00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00,$00
TAPE1_4:
  .byte $01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE1_5:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .byte $02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE1_6:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00
TAPE1_7:
  .byte $01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE2_0:
  .byte $01,$02,$01,$02,$01,$02,$00,$00,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$01,$02,$01,$02,$01,$02,$00,$00,$00,$00,$00
  .byte $03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$00,$00
TAPE2_1:
  .byte $01,$02,$01,$02,$00,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$03,$04,$03,$04,$00
  .byte $00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$00,$00
TAPE2_2:
  .byte $01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02
  .byte $03,$00,$00,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00
TAPE2_3:
  .byte $01,$02,$03,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$01,$02
  .byte $02,$03,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00
TAPE2_4:
  .byte $01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00
TAPE2_5:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE2_6:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00
  .byte $00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00
TAPE2_7:
  .byte $01,$02,$03,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00
TAPE3_0:
  .byte $01,$02,$01,$02,$01,$02,$00,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$03
  .byte $04,$03,$04,$03,$04,$00,$00,$00,$00,$00,$03,$04,$03,$04,$03,$04,$00,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$00,$00,$00
TAPE3_1:
  .byte $01,$02,$01,$02,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00
  .byte $00,$03,$04,$03,$04,$00,$00,$00,$00,$00,$00,$03,$04,$03,$04,$00,$00,$00,$00,$00,$00,$01,$02,$01,$02,$00,$00,$00,$00,$00,$00,$00
TAPE3_2:
  .byte $01,$02,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00
  .byte $01,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00
TAPE3_3:
  .byte $01,$02,$02,$03,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00
  .byte $00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00
TAPE3_4:
  .byte $01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$01,$02,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE3_5:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TAPE3_6:
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$01,$02,$00
  .byte $00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00
TAPE3_7:
  .byte $01,$02,$03,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00
  .byte $00,$00,$01,$02,$03,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00,$01,$02,$03,$00,$00,$00,$00,$00
TAPE_LO:
  .byte <TAPE0_0,<TAPE0_1,<TAPE0_2,<TAPE0_3,<TAPE0_4,<TAPE0_5,<TAPE0_6,<TAPE0_7,<TAPE1_0,<TAPE1_1,<TAPE1_2,<TAPE1_3,<TAPE1_4,<TAPE1_5,<TAPE1_6,<TAPE1_7,<TAPE2_0,<TAPE2_1,<TAPE2_2,<TAPE2_3,<TAPE2_4,<TAPE2_5,<TAPE2_6,<TAPE2_7,<TAPE3_0,<TAPE3_1,<TAPE3_2,<TAPE3_3,<TAPE3_4,<TAPE3_5,<TAPE3_6,<TAPE3_7
TAPE_HI:
  .byte >TAPE0_0,>TAPE0_1,>TAPE0_2,>TAPE0_3,>TAPE0_4,>TAPE0_5,>TAPE0_6,>TAPE0_7,>TAPE1_0,>TAPE1_1,>TAPE1_2,>TAPE1_3,>TAPE1_4,>TAPE1_5,>TAPE1_6,>TAPE1_7,>TAPE2_0,>TAPE2_1,>TAPE2_2,>TAPE2_3,>TAPE2_4,>TAPE2_5,>TAPE2_6,>TAPE2_7,>TAPE3_0,>TAPE3_1,>TAPE3_2,>TAPE3_3,>TAPE3_4,>TAPE3_5,>TAPE3_6,>TAPE3_7
SETOF:
  .byte 0,0,1,1,2,2,3,3,3,3
; lane speeds: level * 8 + lane (8.8 pixels per frame)
SPD_L:
  .byte $8D,$73,$B3,$80,$80,$1A,$B3,$66,$99,$7E,$C3,$8C,$8C,$33,$C3,$70,$A6,$88,$D3,$97,$97,$4C,$D3,$79,$B3,$92,$E4,$A3,$A3,$66,$E4,$82
  .byte $BF,$9D,$F4,$AE,$AE,$7F,$F4,$8B,$CC,$A7,$04,$BA,$BA,$98,$04,$94,$D9,$B1,$14,$C5,$C5,$B2,$14,$9E,$E6,$BC,$24,$D1,$D1,$CB,$24,$A7
  .byte $F2,$C6,$34,$DC,$DC,$E4,$34,$B0,$FF,$D1,$44,$E8,$E8,$FE,$44,$B9
SPD_H:
  .byte $00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$01,$00,$00,$01,$01,$00,$00,$00,$01,$00,$00,$01,$01,$00,$00,$00,$01,$00,$00,$01,$01,$00
  .byte $00,$00,$01,$00,$00,$01,$01,$00,$00,$00,$01,$00,$00,$01,$01,$00
; the snake walks on a log of lane 2, the little hedgehog waits on a log of lane 3 (world pixels, per set)
SNK_A:
  .byte <0,<0,<0,<0
SNK_AH:
  .byte >0,>0,>0,>0
SNK_LEN:
  .byte 32,24,24,16
BAB_X:
  .byte <84,<88,<60,<72
BAB_XH:
  .byte >84,>88,>60,>72

; palettes: colour nibble maps (morning, afternoon, sunset, night)
PALS:
  .byte $00,$01,$02,$03,$05,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
  .byte $00,$01,$02,$03,$07,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
  .byte $00,$01,$0C,$0A,$0D,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
  .byte $00,$01,$0C,$0C,$04,$05,$01,$07,$08,$06,$0E,$0E,$0C,$06,$04,$0E
DIVE_FG:
  .byte 2,12,7,4

; AY periods: index = MIDI note - 35
TP_LO:
  .byte $00,$BC,$86,$53,$24,$F6,$CC,$A4,$7E,$5A,$38,$18,$FA,$DE,$C3,$AA,$92,$7B,$66,$52,$3F,$2D,$1C,$0C,$FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9
  .byte $9F,$96,$8E,$86,$7F,$77,$71,$6A,$64,$5F,$59,$54,$50,$4B,$47,$43,$3F,$3C,$38,$35,$32,$2F,$2D,$2A,$28,$26,$24,$22,$20
TP_HI:
  .byte $00,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; tunes: song * 4 + track (melody, harmony, bass, drums)
SONGP_LO:
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3,<SG2_0,<SG2_1,<SG2_2,<SG2_3,<SG3_0,<SG3_1,<SG3_2,<SG3_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3,>SG2_0,>SG2_1,>SG2_2,>SG2_3,>SG3_0,>SG3_1,>SG3_2,>SG3_3
SG0_0:
  .byte $20,$06,$24,$06,$27,$06,$24,$06,$20,$06,$24,$06,$27,$0C,$29,$06,$27,$06,$25,$06,$24,$06,$22,$0C,$1F,$0C,$20,$06,$22,$06,$24,$06
  .byte $25,$06,$27,$06,$29,$06,$2B,$06,$2C,$06,$29,$06,$27,$06,$24,$06,$22,$06,$20,$18,$27,$06,$27,$06,$29,$06,$2B,$06,$2C,$0C,$27,$0C
  .byte $25,$06,$24,$06,$25,$06,$29,$06,$27,$0C,$24,$0C,$22,$06,$24,$06,$25,$06,$22,$06,$24,$06,$20,$06,$22,$06,$1F,$06,$20,$18,$FF
SG0_1:
  .byte $18,$18,$18,$18,$19,$18,$16,$18,$18,$18,$19,$18,$1B,$18,$18,$18,$18,$18,$19,$18,$18,$18,$16,$18,$14,$18,$FF
SG0_2:
  .byte $08,$0C,$0F,$0C,$08,$0C,$0F,$0C,$0D,$0C,$08,$0C,$0F,$0C,$0A,$0C,$08,$0C,$0F,$0C,$0D,$0C,$11,$0C,$0F,$0C,$0F,$0C,$08,$18,$08,$0C
  .byte $0F,$0C,$0D,$0C,$08,$0C,$08,$0C,$0F,$0C,$0F,$0C,$03,$0C,$08,$18,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG1_0:
  .byte $27,$06,$24,$06,$20,$06,$24,$06,$27,$06,$2C,$0C,$2B,$06,$29,$06,$25,$06,$22,$06,$1F,$06,$20,$18,$FF
SG1_1:
  .byte $18,$18,$18,$18,$19,$18,$18,$18,$FF
SG1_2:
  .byte $08,$0C,$0F,$0C,$08,$0C,$0F,$0C,$0D,$0C,$0F,$0C,$08,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$04,$18,$FF
SG2_0:
  .byte $2C,$04,$30,$04,$33,$04,$38,$0C,$FF
SG2_1:
  .byte $24,$0C,$27,$0C,$FF
SG2_2:
  .byte $08,$0C,$08,$0C,$FF
SG2_3:
  .byte $02,$04,$02,$04,$02,$04,$01,$0C,$FF
SG3_0:
  .byte $2C,$04,$2B,$04,$2C,$04,$30,$04,$33,$08,$30,$04,$33,$04,$38,$18,$00,$04,$33,$04,$35,$04,$37,$04,$38,$18,$FF
SG3_1:
  .byte $24,$10,$27,$10,$2C,$18,$24,$0C,$27,$18,$FF
SG3_2:
  .byte $08,$10,$0F,$10,$08,$18,$0F,$0C,$08,$18,$FF
SG3_3:
  .byte $02,$04,$02,$04,$02,$04,$02,$04,$01,$08,$03,$08,$01,$18,$03,$04,$03,$04,$03,$04,$03,$04,$04,$18,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$7D,$63,$52,$45,$70,$58,$49,$3F,$50,$50,$50,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$2F,$2F,$2F,$28,$28,$28,$20,$20
  .byte $20,$18,$18,$18,$18,$18,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$1F,$2A
  .byte $9F,$9F,$A9,$A9,$9F,$9F,$A9,$A9,$9F,$9F,$A9,$A9,$D0,$E4,$FB,$18,$3D,$6D,$AD,$09,$45,$4A,$50,$56,$5D,$66,$71,$7E,$8F,$A4,$C1,$EC
  .byte $2D,$A1,$45,$3B,$33,$2D,$2D,$34,$3F,$4E,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD
  .byte $BD,$BD,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$EF,$EF,$EF,$EF,$BD,$BD,$BD,$BD,$EF,$EF,$EF,$EF,$BD,$BD,$BD,$BD,$EF,$EF,$EF,$EF,$BD,$BD,$BD,$BD
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0A,$09,$07,$06,$0A,$09,$07,$06,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0A,$09,$07,$06,$04,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0B
  .byte $0A,$0C,$0A,$08,$06,$04,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$09,$06
  .byte $0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0C,$0B,$0A,$09,$07,$06,$05,$04,$0D,$0C,$0B,$0B,$0A,$09,$08,$08,$07,$06,$05,$05
  .byte $04,$03,$0A,$0B,$0B,$0C,$0C,$0A,$07,$05,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08
  .byte $07,$06,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09
  .byte $0D,$0C,$0A,$09,$07,$06,$04,$03,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07
WH_START:
  .byte $00,$01,$05,$09,$18,$26,$3E,$40,$4C,$54,$62,$6A,$92,$95,$A8
WH_LEN:
  .byte $00,$04,$04,$0F,$0E,$18,$02,$0C,$08,$0E,$08,$28,$03,$13,$18
W_HOP = 1
W_HOP2 = 2
W_HOME = 3
W_BONUS = 4
W_EXTRA = 5
W_TICK = 6
W_HONK = 7
W_BUMP = 8
W_SQUASH = 9
W_YIP = 10
W_OVER = 11
W_KEY = 12
W_SIGN = 13
W_TIMEUP = 14

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$0E,$0C,$0A,$08,$06,$04,$02,$00
EX_NP:
  .byte $00,$02,$02,$02,$02,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$0C,$0D,$0E,$0F,$10,$11,$12,$13
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$13
EX_LEN:
  .byte $00,$12,$08
S_SPLASH = 1
S_CRUNCH = 2
