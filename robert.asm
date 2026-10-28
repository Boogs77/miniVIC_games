;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ROBERT  -  an original isometric cube-hopping game         ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: bubbles (VDP, NMI + trampoline $0FD0, AY engine,     ;
;   2 players taking turns)                                    ;
;                                                              ;
;   - Robert, a little robot on a pogo stick, hops from cube   ;
;     to cube on a board floating in the void and paints the   ;
;     tops: the round is over when every top has the goal      ;
;     colour. Hopping off the board costs a life              ;
;   - joystick turned by 45 degrees: up = up right, right =    ;
;     down right, down = down left, left = up left; button +   ;
;     direction = long jump over a cube (once per round)       ;
;   - 4 boards (diamond, hourglass, ring, twin towers), 4      ;
;     rounds each; every 4 levels the colour rule changes:     ;
;     one hop, two hops, every hop switches, two hops and a    ;
;     third one undoes                                         ;
;   - Blot (an ink drop) chases Robert, Roller wipes the       ;
;     paint along a diagonal, Spark runs round the edge,       ;
;     Ghost Robert repeats Robert's hops 3 seconds later       ;
;   - gold cubes throw Robert far from the Blot (super jump),  ;
;     the bucket paints the cube and its neighbours, the star  ;
;     squashes Blot and Ghost for 4 seconds                    ;
;   - points: paint 25, goal colour 75, bucket and star 200,   ;
;     squash 300, gold cube 500, round bonus; 3 lives, one     ;
;     more at 10000 and every 20000; 1 or 2 players taking     ;
;     turns (title: button 1 or button 2)                      ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     spring boing, paint, fall, glop, super jump, items,      ;
;     start tune, round clear jingle                           ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
ALIVE       = $32      ; 2 bytes: lives left to every player (the one playing included)
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
LEVEL       = $40      ; ---- block of the player, saved: level 1-99
ROUND       = $41      ;      round 1-4
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
LJUMP       = $43      ;      1 = the long jump is still there
RCUBE       = $44      ;      cube where Robert stands (or hopped from)
FRESH       = $45      ;      1 = the round starts from the beginning
PBLOCK      = 6
BOARD       = $46      ; board 0-3
RULE        = $47      ; colour rule 0-3
DIFF        = $48      ; difficulty 0-15
NC          = $49      ; cubes on the board
GOALN       = $4A      ; cubes with the goal colour
GOLDN       = $4B      ; gold cubes left
GSTATE      = $4C      ; 0 playing, 1 caught, 2 fell, 3 round clear
GT          = $4D      ; timer of GSTATE
FREEZE      = $4E      ; frames the enemies stay still (super jump)
STARF       = $4F      ; frames of the star left
ITEMK       = $50      ; item on the board: 0 none, 1 bucket, 2 star
ITEMC       = $51      ; its cube
ITEMT       = $52      ; 4-frame units it stays
ITEMW       = $53      ; 4-frame units before the next one
SCUBE       = $54      ; start cube of the board
JOYC        = $55      ; both joysticks drive the player playing
JOYP        = $56      ; JOYC of the frame before
HUDD        = $57      ; 1 = the HUD changed
FIRSTT      = $58      ; 1 = first turn of the game: start tune
SHOWP       = $59      ; 1 = "PLAYER n" before the round
RR          = $5A      ; first object in the SAT (turns)
STAGE       = $5B      ; (level - 1) * 4 + round - 1, at most 255
GF          = $5C      ; 2 bytes: frames of play
GREC        = $5E      ; 1 = Robert's hops are recorded for the ghost
GHEAD       = $5F      ; ghost buffer: next free entry

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
GTAIL       = $70      ; ghost buffer: next entry to play
BLOTW       = $71      ; frames between two hops of the Blot
TP          = $72      ; 2 bytes: text records
ROLLW       = $74      ; 4-frame units between two Rollers
SPARKW      = $75      ; frames between two moves of the Spark
CUR         = $76      ; cube being worked on
TR          = $77      ; target of a hop: row
TC          = $78      ;                  column
PALI        = $79      ; colours of the round: board * 4 + round - 1
CNT         = $7A
SLOT        = $7B      ; creature being drawn / moved
TOPC        = $7C      ; 4 bytes: colour of the tops for every state
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
BEST        = $86      ; search: best distance / cube
BESTI       = $87
DIST        = $88
OLDS        = $89      ; state of the cube before the paint
BONL        = $8A      ; bonus of the round (BCD)
BONH        = $8B
FACEL       = $8C      ; colour of the left / right faces
FACER       = $8D

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
OX         = $E0         ; sprite being added: X on the screen, Y, pattern, colour
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
CMD_START  = 2           ; the start tune

; ---------------- the board ----------------
MAP        = $0200       ; row * 16 + column -> cube, $FF = void (10 rows)
CST        = $0300       ; state of every cube: 0 start, 1 middle, 2 goal, 3 gold
CRW        = $0328       ; row of every cube
CKC        = $0350       ; column of every cube
MAXC       = 40

; ---------------- creatures: 0 Robert, 1 Blot, 2 Roller, 3 Spark, 4 Ghost
NSLOT      = 5
C_ST       = $0400       ; state ST_*
C_ROW      = $0408       ; cube where it stands / hops from
C_COL      = $0410
C_X        = $0418       ; feet on the screen, 8.8 (the arc of the hop is apart)
C_XL       = $0420
C_Y        = $0428
C_YL       = $0430
C_VXL      = $0438       ; velocity 8.8 signed
C_VXH      = $0440
C_VYL      = $0448
C_VYH      = $0450
C_T        = $0458       ; frames into the hop
C_N        = $0460       ; kind of hop: 0 hop, 1 long jump, 2 super jump, 3 slide
C_TR       = $0468       ; target of the hop
C_TC       = $0470
C_W        = $0478       ; timer of the state
C_D        = $0480       ; direction (Roller, Spark)
C_F        = $0488       ; facing 0 up right, 1 down right, 2 down left, 3 up left
C_L        = $0490       ; Ghost: life left (4-frame units)
GB_TL      = $04A0       ; ghost buffer (16): frame of the hop (lo / hi), target, kind
GB_TH      = $04B0
GB_R       = $04C0
GB_C       = $04D0
GB_N       = $04E0

S_ROB      = 0
S_BLOT     = 1
S_ROLL     = 2
S_SPARK    = 3
S_GHOST    = 4

ST_OFF     = 0
ST_IDLE    = 1           ; on a cube
ST_HOP     = 2
ST_FALL    = 3           ; off the board, falling into the void
ST_WAIT    = 4           ; off the screen, C_W (4-frame units) before it comes
ST_SHOW    = 5           ; appearing: flashing and harmless
ST_SQUASH  = 6           ; squashed by the star
ST_PEND    = 7           ; Ghost: invisible, C_W frames before it shows

PSAVE      = $0500       ; 2 x 64 bytes: block of every player, cubes from +8
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
BTN_MASK    = %00110000
GHOST_DELAY = 180        ; frames the Ghost is behind Robert
ROB_PAUSE   = 3          ; frames on the spring between two hops
ROLL_PAUSE  = 6

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
  JSR LOAD_GFX
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY
  STA VINT                     ; VDP interrupt off (R1 = $C6)
  STA FRAME_CNT
  STA LAST_FRAME
  STA HISC
  STA HISC+1
  STA HISC+2
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ ALIVE,X
  DEX
  BPL .rs_p
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, the characters and what they do
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JSR PRINT
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the characters (sprites)
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
  CPX #9
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
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
  JMP NEW_GAME

; one frame of the title: Robert hops on the spot
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA FRAME_CNT
  AND #$10
  LSR A
  STA T0                       ; 0 or 8: in the air / on the spring
  LDA #PT_ROB+16
  CLC
  ADC T0
  STA SAT_BUFFER+2
  ADC #4
  STA SAT_BUFFER+6
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: level 1, 3 lives for every player
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ ALIVE,X
  DEX
  BPL .ng_p
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA ALIVE,X
  LDA #1
  STA LEVEL
  STA ROUND
  STA NEXTX                    ; first extra life at 10000
  STA LJUMP
  STA FRESH
  STZ RCUBE
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then a ROUND
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE ROUND_START
  INC SHOWP

ROUND_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR SET_ROUND
  JSR SET_COLOURS
  JSR LOAD_BOARD
  LDA FRESH
  BEQ .rs_old
  JSR INIT_CUBES
  INC SHOWP                    ; a new round: the intro with the rule
.rs_old:
  JSR COUNT_CUBES
  LDA SHOWP
  BNE .rs_intro
  JMP .rs_board
.rs_intro:
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT
  BEQ .rs_jingle
  STZ FIRSTT                   ; the start tune, to the end
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.rs_tune:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .rs_tune
  BRA .rs_wait
.rs_jingle:
  LDA #150
  JSR WAIT_FRAMES
.rs_wait:
  JSR VDP_INT_OFF
.rs_board:
  STZ SHOWP
  JSR CLEAR_NT
  JSR DRAW_TOP
  JSR DRAW_BOARD
  JSR DRAW_GOAL
  JSR DRAW_BOTTOM
  JSR START_CREATURES
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #40
  JSR WAIT_FRAMES


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  INC GF
  BNE .gl_f
  INC GF+1
.gl_f:
  LDA GSTATE
  BNE .gl_stop
  JSR UPDATE_ROBERT
  JSR UPDATE_ENEMIES
  JSR UPDATE_ITEM
  JSR COLLIDE
  LDA STARF
  BEQ .gl_hud
  DEC STARF
  BRA .gl_hud
.gl_stop:
  DEC GT                       ; caught or fallen: a short wait
.gl_hud:
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  CMP #3
  BNE .gl_lost
  JMP ROUND_CLEAR
.gl_lost:
  LDA GT
  BNE GAME_LOOP
  JMP LOSE_LIFE


; ===============================================================
;  END OF A ROUND
; ===============================================================
ROUND_CLEAR:
  LDA #W_CLEAR
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_OFF
  LDX #NSLOT-1                 ; the enemies go away
.rc_e:
  STZ C_ST,X
  DEX
  BNE .rc_e
  STZ ITEMK
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #16                      ; the tops flash
  STA CNT
.rc_f:
  LDA #5
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  LDX PALI
  LDA PAL_G,X
  LDY CNT
  CPY #1
  BEQ .rc_c                    ; the last time: the goal colour again
  LDA CNT
  LSR A
  LDA #$0F
  BCS .rc_c
  LDX PALI
  LDA PAL_G,X
.rc_c:
  STA TOPC+2
  LDA #2
  JSR STATE_COLOUR
  JSR VDP_INT_ON
  DEC CNT
  BNE .rc_f
  ; ---- bonus: 1000 + 250 per stage (at most 5000) + 1000 per gold cube left
  LDA #$10
  STA BONH
  STZ BONL
  LDA STAGE
  CMP #16
  BCC .rc_s
  LDA #16
.rc_s:
  TAX
  SED
.rc_b:
  CPX #0
  BEQ .rc_gold
  CLC
  LDA BONL
  ADC #$50
  STA BONL
  LDA BONH
  ADC #$02
  STA BONH
  DEX
  BRA .rc_b
.rc_gold:
  LDX GOLDN
.rc_gl:
  CPX #0
  BEQ .rc_d
  CLC
  LDA BONH
  ADC #$10
  STA BONH
  DEX
  BRA .rc_gl
.rc_d:
  CLD
  JSR VDP_INT_OFF
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA BONH
  JSR PUT_2
  LDA BONL
  JSR PUT_2
  LDA BONL
  STA PTS_L
  LDA BONH
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_FRAMES
  LDA #1                       ; the next round
  STA FRESH
  STA LJUMP
  INC ROUND
  LDA ROUND
  CMP #5
  BCC .rc_n
  LDA #1
  STA ROUND
  INC LEVEL                    ; after 99 the counter starts again from 01
  LDA LEVEL
  CMP #100
  BCC .rc_n
  LDA #1
  STA LEVEL
.rc_n:
  JMP ROUND_START

LOSE_LIFE:
  LDX CURP
  DEC ALIVE,X
  STZ FRESH                    ; the same round goes on, the cubes as they are
  JSR SAVE_PLAYER
  LDA #30
  JSR WAIT_FRAMES
  LDA NPL                      ; the other player, if he still has lives
  CMP #$02
  BNE .ll_same
  LDA CURP
  EOR #$01
  TAX
  LDA ALIVE,X
  BEQ .ll_same
  STX CURP
  JMP TURN_START
.ll_same:
  LDX CURP
  LDA ALIVE,X
  BEQ GAME_OVER
  JMP TURN_START

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
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.go_1:
  LDX #$00                     ; the best score
.go_h:
  LDA SCH,X
  CMP HISC+2
  BCC .go_n
  BNE .go_set
  LDA SCM,X
  CMP HISC+1
  BCC .go_n
  BNE .go_set
  LDA SCL,X
  CMP HISC
  BCC .go_n
  BEQ .go_n
.go_set:
  LDA SCL,X
  STA HISC
  LDA SCM,X
  STA HISC+1
  LDA SCH,X
  STA HISC+2
.go_n:
  INX
  CPX #$02
  BNE .go_h
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  JMP TITLE


; ===============================================================
;  ROUNDS: board, rule, colours and speed of the enemies
; ===============================================================
SET_ROUND:
  LDA LEVEL
  DEC A
  AND #$03
  STA BOARD
  ASL A
  ASL A
  STA PALI
  LDA ROUND
  DEC A
  CLC
  ADC PALI
  STA PALI
  LDA LEVEL                    ; rule: levels 1-4, 5-8, 9-12, 13+
  DEC A
  LSR A
  LSR A
  CMP #4
  BCC .sr_r
  LDA #3
.sr_r:
  STA RULE
  LDA LEVEL                    ; stage = (level - 1) * 4 + round - 1
  DEC A
  CMP #64
  BCC .sr_s
  LDA #63
.sr_s:
  ASL A
  ASL A
  CLC
  ADC ROUND
  DEC A
  STA STAGE
  CMP #16
  BCC .sr_d
  LDA #15
.sr_d:
  STA DIFF
  TAX
  LDA LV_BLOTW,X
  STA BLOTW
  LDA LV_ROLLW,X
  STA ROLLW
  LDA LV_SPARKW,X
  STA SPARKW
  LDX PALI                     ; colours of the tops and of the faces
  LDA PAL_S,X
  STA TOPC
  LDA PAL_M,X
  STA TOPC+1
  LDA PAL_G,X
  STA TOPC+2
  LDX BOARD
  LDA GOLD_C,X
  STA TOPC+3
  LDA FACE_L,X
  STA FACEL
  LDA FACE_R,X
  STA FACER
  RTS

; the board: cube rows and columns, MAP, start cube
LOAD_BOARD:
  LDX #159
  LDA #$FF
.lb_m:
  STA MAP,X
  DEX
  CPX #$FF
  BNE .lb_m
  LDX BOARD
  LDA BOARD_LO,X
  STA PTR
  LDA BOARD_HI,X
  STA PTR+1
  LDY #0
  LDA (PTR),Y
  STA NC
  INY
  LDA (PTR),Y
  STA SCUBE
  LDX #0
.lb_c:
  INY
  LDA (PTR),Y
  STA CRW,X
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0
  INY
  LDA (PTR),Y
  STA CKC,X
  ORA T0
  STY T1
  TAY
  TXA
  STA MAP,Y
  LDY T1
  INX
  CPX NC
  BNE .lb_c
  RTS

; a new round: all the cubes to the start colour, 1 or 2 gold cubes
INIT_CUBES:
  LDX #MAXC-1
.ic_z:
  STZ CST,X
  DEX
  BPL .ic_z
  LDA SCUBE
  STA RCUBE
  LDA #1
  STA LJUMP
  LDA ROUND
  CMP #3
  LDA #1
  BCC .ic_n
  INC A
.ic_n:
  STA CNT
.ic_g:
  JSR RANDOM_CUBE
  CPX SCUBE
  BEQ .ic_g
  LDA CST,X
  BNE .ic_g
  LDA #3
  STA CST,X
  DEC CNT
  BNE .ic_g
  RTS

; X = a cube at random
RANDOM_CUBE:
  JSR NEXT_RND
  AND #$3F
.rc_l:
  CMP NC
  BCC .rc_ok
  SBC NC
  BRA .rc_l
.rc_ok:
  TAX
  RTS

; GOALN and GOLDN from the states of the cubes
COUNT_CUBES:
  STZ GOALN
  STZ GOLDN
  LDX NC
.cc_l:
  DEX
  BMI .cc_e
  LDA CST,X
  CMP #2
  BNE .cc_g
  INC GOALN
.cc_g:
  CMP #3
  BNE .cc_l
  INC GOLDN
  BRA .cc_l
.cc_e:
  RTS

; X = cube, A = direction (0 up right, 1 down right, 2 down left, 3 up left):
; TR / TC = the cell there, A = its cube or $FF (void); keeps X
NEIGHBOUR:
  TAY
  LDA CRW,X
  CLC
  ADC DR_T,Y
  STA TR
  LDA CKC,X
  CLC
  ADC DK_T,Y
  STA TC
  ; fall into CUBE_AT

; TR / TC -> A = cube there or $FF
CUBE_AT:
  LDA TR
  CMP #10
  BCS .ca_v
  LDA TC
  CMP #15
  BCS .ca_v
  LDA TR
  ASL A
  ASL A
  ASL A
  ASL A
  ORA TC
  TAY
  LDA MAP,Y
  RTS
.ca_v:
  LDA #$FF
  RTS


; ===============================================================
;  DRAWING THE BOARD
; ===============================================================
; the colours of the cube tiles for this round
SET_COLOURS:
  LDA #3
.sc_s:
  PHA
  JSR STATE_COLOUR
  PLA
  DEC A
  BPL .sc_s
  LDA FACEL                    ; the faces under the cubes with no neighbour below
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA T2
  LDA FACER
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA T3
  LDX #0
.sc_t:
  LDA #<($2000+192*8)
  STA VREG
  TXA
  ORA #(VDP_WRITE_VRAM_BIT | >($2000+192*8))
  STA VREG
  LDY #16
  LDA T2
.sc_l:
  STA VDATA
  DEY
  BNE .sc_l
  LDY #16
  LDA T3
.sc_r:
  STA VDATA
  DEY
  BNE .sc_r
  TXA
  CLC
  ADC #$08
  TAX
  CMP #$18
  BNE .sc_t
  RTS

; A = state: the colours of its 16 tiles (128 + state * 16) in the 3 thirds
STATE_COLOUR:
  STA T5
  TAX
  LDA TOPC,X                   ; top colour in the high nibble
  ASL A
  ASL A
  ASL A
  ASL A
  STA T4
  LDA T5                       ; VRAM address: $2000 + (128 + state * 16) * 8 = $2400 + state * $80
  LSR A
  ORA #$04
  STA T6                       ; high byte (without $20)
  LDA #$00
  ROR A
  STA T5                       ; low byte: $00 or $80
  STZ T7
.st_th:
  LDA T5
  STA VREG
  LDA T6
  CLC
  ADC T7
  ORA #(VDP_WRITE_VRAM_BIT | $20)
  STA VREG
  LDY #0
.st_t:
  LDA BG_SLOT,Y                ; background: 0 = right face, 1 = black, 2 = left face
  TAX
  LDA FACER
  CPX #0
  BEQ .st_c
  LDA #$01
  CPX #1
  BEQ .st_c
  LDA FACEL
.st_c:
  ORA T4
  CPY #12
  BCC .st_w
  LDA #0
.st_w:
  LDX #8
.st_8:
  STA VDATA
  DEX
  BNE .st_8
  INY
  CPY #16
  BNE .st_t
  LDA T7
  CLC
  ADC #$08
  STA T7
  CMP #$18
  BNE .st_th
  RTS

; every cube of the board, and the faces under the cubes with no neighbour below
DRAW_BOARD:
  LDX #0
.db_l:
  PHX
  JSR DRAW_CUBE
  PLX
  STX CUR
  LDA #2                       ; nothing down left: the left face over the void
  JSR NEIGHBOUR
  CMP #$FF
  BNE .db_r
  LDY #0
  LDA #192
  JSR BELOW
.db_r:
  LDX CUR
  LDA #1                       ; nothing down right: the right face
  JSR NEIGHBOUR
  CMP #$FF
  BNE .db_n
  LDY #2
  LDA #194
  JSR BELOW
.db_n:
  LDX CUR
  INX
  CPX NC
  BNE .db_l
  RTS

; under cube CUR, Y = 0 left half / 2 right half: tiles A and A + 1
BELOW:
  STA T2
  STY T1
  LDX CUR
  LDA CKC,X
  ASL A
  CLC
  ADC T1
  TAY
  LDA CRW,X
  ASL A
  CLC
  ADC #4
  TAX
  JSR NT_XY
  LDA T2
  STA VDATA
  INC A
  STA VDATA
  RTS

; X = cube: its 8 tiles in the state of the cube (keeps nothing)
DRAW_CUBE:
  STX CUR
  LDA CST,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #128
  STA T2                       ; first tile of the state
  LDA #3                       ; up left: tiles 0,1 or 2,3
  JSR NEIGHBOUR
  LDY #0
  CMP #$FF
  BNE .dc_ul
  LDY #2
.dc_ul:
  STY T3
  LDX CUR
  LDA #0                       ; up right: tiles 4,5 or 6,7
  JSR NEIGHBOUR
  LDY #4
  CMP #$FF
  BNE .dc_ur
  LDY #6
.dc_ur:
  STY T5
  LDX CUR
  LDA CRW,X
  ASL A
  CLC
  ADC #2
  STA T0                       ; tile row
  LDA CKC,X
  ASL A
  STA T1                       ; tile column
  TAY
  LDX T0
  JSR NT_XY
  LDA T2
  ORA T3
  STA VDATA
  INC A
  STA VDATA
  LDA T2
  ORA T5
  STA VDATA
  INC A
  STA VDATA
  LDX T0
  INX
  LDY T1
  JSR NT_XY
  LDA T2
  ORA #8
  STA VDATA
  INC A
  STA VDATA
  INC A
  STA VDATA
  INC A
  STA VDATA
  RTS

; a loose cube (no neighbours) at tile row T0, column T1, state A
LOOSE_CUBE:
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #128
  STA T2
  LDX T0
  LDY T1
  JSR NT_XY
  LDA T2
  ORA #2
  STA VDATA
  INC A
  STA VDATA
  LDA T2
  ORA #6
  STA VDATA
  INC A
  STA VDATA
  LDX T0
  INX
  LDY T1
  JSR NT_XY
  LDA T2
  ORA #8
  STA VDATA
  INC A
  STA VDATA
  INC A
  STA VDATA
  INC A
  STA VDATA
  LDX T0
  INX
  INX
  LDY T1
  JSR NT_XY
  LDA #192
  STA VDATA
  INC A
  STA VDATA
  INC A
  STA VDATA
  INC A
  STA VDATA
  RTS

; the goal colour, up left
DRAW_GOAL:
  LDA #2
  STA T0
  STZ T1
  LDA #2
  JSR LOOSE_CUBE
  LDA #<TXT_GOAL
  STA TP
  LDA #>TXT_GOAL
  STA TP+1
  JMP PRINT

; before a round: player, level, round, board, the colours and the rule
INTRO:
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDX NPL
  CPX #2
  BNE .in_lv
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.in_lv:
  LDA #<TXT_LEVEL
  STA TP
  LDA #>TXT_LEVEL
  STA TP+1
  JSR PRINT
  LDA LEVEL
  JSR BIN2BCD
  JSR PUT_2
  LDX #8
  LDY #27
  JSR NT_XY
  LDA ROUND
  ORA #$30
  STA VDATA
  LDX BOARD                    ; the name of the board
  LDA BNAME_LO,X
  STA TP
  LDA BNAME_HI,X
  STA TP+1
  JSR PRINT
  LDX RULE                     ; the rule
  LDA RULE_LO,X
  STA TP
  LDA RULE_HI,X
  STA TP+1
  JSR PRINT
  LDA #<TXT_KEYS
  STA TP
  LDA #>TXT_KEYS
  STA TP+1
  JSR PRINT
  LDA #13                      ; the colours: start > (middle >) goal
  STA T0
  LDX RULE
  LDA RULE_MID,X
  BEQ .in_2
  LDA #8
  STA T1
  LDA #0
  JSR LOOSE_CUBE
  LDA #14
  STA T1
  LDA #1
  JSR LOOSE_CUBE
  LDA #20
  STA T1
  LDA #2
  JSR LOOSE_CUBE
  LDA #<TXT_ARROW3
  STA TP
  LDA #>TXT_ARROW3
  STA TP+1
  JMP PRINT
.in_2:
  LDA #11
  STA T1
  LDA #0
  JSR LOOSE_CUBE
  LDA #17
  STA T1
  LDA #2
  JSR LOOSE_CUBE
  LDA #<TXT_ARROW2
  STA TP
  LDA #>TXT_ARROW2
  STA TP+1
  LDX RULE
  CPX #2
  BNE .in_p
  LDA #<TXT_ARROWB
  STA TP
  LDA #>TXT_ARROWB
  STA TP+1
.in_p:
  JMP PRINT


; ===============================================================
;  HUD: scores on rows 0-1, level / lives / long jump on row 23
; ===============================================================
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #1
  LDY #13
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
  BNE .dt_r
  LDX #$01
  JMP DRAW_SCORE
.dt_r:
  RTS

; X = player: his score on row 1 (keeps X)
DRAW_SCORE:
  PHX
  LDY SC_COL,X
  LDX #1
  JSR NT_XY
  PLX
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

DRAW_BOTTOM:
  LDA #<TXT_BOT
  STA TP
  LDA #>TXT_BOT
  STA TP+1
  JSR PRINT
  ; fall into DRAW_BVALS

; row 23: level-round, the spare lives, the long jump
DRAW_BVALS:
  LDA LEVEL
  JSR BIN2BCD
  LDX #23
  LDY #7
  JSR PUT_BCD2
  LDA #'-'
  STA VDATA
  LDA ROUND
  ORA #$30
  STA VDATA
  LDX #23
  LDY #13
  JSR NT_XY
  LDX CURP
  LDA ALIVE,X
  BEQ .db_z
  DEC A
.db_z:
  STA T0
  LDX #0
.db_l:
  LDA #$20
  CPX T0
  BCS .db_b
  LDA #T_LIFE
.db_b:
  STA VDATA
  LDA #$20
  STA VDATA
  INX
  CPX #6
  BNE .db_l
  LDX #23
  LDY #27
  JSR NT_XY
  LDX #0
  LDA LJUMP
  BEQ .db_j
  LDX #5
.db_j:
  LDY #5
.db_jl:
  LDA TXT_JUMP,X
  STA VDATA
  INX
  DEY
  BNE .db_jl
  RTS

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  LDX CURP
  JSR DRAW_SCORE
  JMP DRAW_BVALS
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; X = player: the block and the cubes
  LDA PS_OFF,X
  TAY
  LDX #$00
.sp_b:
  LDA LEVEL,X
  STA PSAVE,Y
  INY
  INX
  CPX #PBLOCK
  BNE .sp_b
  TYA
  AND #$C0
  ORA #$08
  TAY
  LDX #$00
.sp_c:
  LDA CST,X
  STA PSAVE,Y
  INY
  INX
  CPX #MAXC
  BNE .sp_c
  RTS

LOAD_PLAYER:                   ; X = player
  LDA PS_OFF,X
  TAY
  LDX #$00
.lp_b:
  LDA PSAVE,Y
  STA LEVEL,X
  INY
  INX
  CPX #PBLOCK
  BNE .lp_b
  TYA
  AND #$C0
  ORA #$08
  TAY
  LDX #$00
.lp_c:
  LDA PSAVE,Y
  STA CST,X
  INY
  INX
  CPX #MAXC
  BNE .lp_c
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 10000, then every 20000
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
  LDA SCH,X
  CMP NEXTX
  BCC .as_d
  INC ALIVE,X
  SED
  LDA NEXTX
  CLC
  ADC #$02
  CLD
  BCC .as_x
  LDA #$FF                     ; past 980000: no more
.as_x:
  STA NEXTX
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.as_d:
  LDA #1
  STA HUDD
  PLY
  PLX
  RTS

; ===============================================================
;  CREATURES: hops on the lattice of the cubes
; ===============================================================
; at the start of a round (or after a lost life): Robert on his cube, the enemies waiting
START_CREATURES:
  LDX #NSLOT-1
.sc_z:
  STZ C_ST,X
  DEX
  BPL .sc_z
  STZ GSTATE
  STZ FREEZE
  STZ STARF
  STZ ITEMK
  STZ GREC
  STZ RR
  LDA #100                     ; first item after 400 frames
  STA ITEMW
  LDX #S_ROB
  LDA RCUBE
  JSR PLACE
  LDA #1
  STA C_F
  LDA STAGE                    ; the Blot from the second round
  BEQ .sc_r
  LDX #S_BLOT
  LDA #25
  JSR WAIT_SLOT
.sc_r:
  LDA STAGE                    ; the Roller from the third round
  CMP #2
  BCC .sc_s
  LDX #S_ROLL
  LDA ROLLW
  LSR A
  JSR WAIT_SLOT
.sc_s:
  LDA LEVEL                    ; the Spark from level 2
  CMP #2
  BCC .sc_g
  LDX #S_SPARK
  LDA #40
  JSR WAIT_SLOT
.sc_g:
  LDA LEVEL                    ; the Ghost from level 3
  CMP #3
  BCC .sc_e
  LDX #S_GHOST
  LDA #60
  JSR WAIT_SLOT
.sc_e:
  RTS

; X = slot, A = 4-frame units before it comes
WAIT_SLOT:
  STA C_W,X
  LDA #ST_WAIT
  STA C_ST,X
  RTS

; X = slot, A = cube: the creature stands on it
PLACE:
  TAY
  LDA CRW,Y
  STA C_ROW,X
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #24
  STA C_Y,X
  LDA CKC,Y
  STA C_COL,X
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #16
  STA C_X,X
  STZ C_XL,X
  STZ C_YL,X
  STZ C_W,X
  LDA #ST_IDLE
  STA C_ST,X
  RTS

; X = slot, A = kind of hop (0 hop, 1 long jump, 2 super jump, 3 slide), target in TR / TC
HOP_START:
  STA C_N,X
  STZ C_T,X
  LDA TR
  STA C_TR,X
  LDA TC
  STA C_TC,X
  LDA #ST_HOP
  STA C_ST,X
  LDY C_N,X
  LDA TC                       ; horizontal: dk * 256 >> shift
  SEC
  SBC C_COL,X
  STA T1
  STZ T0
  JSR .hs_shift
  LDA T0
  STA C_VXL,X
  LDA T1
  STA C_VXH,X
  LDA TR                       ; vertical: dr * 256 >> shift
  SEC
  SBC C_ROW,X
  STA T1
  STZ T0
  JSR .hs_shift
  LDA T0
  STA C_VYL,X
  LDA T1
  STA C_VYH,X
  LDA C_VXH,X                  ; facing: from the signs of the two moves
  ROL A
  LDA #0
  ROL A                        ; 1 = to the left
  STA T2
  LDA C_VYH,X
  BMI .hs_up
  ORA C_VYL,X
  BEQ .hs_up                   ; a jump along the row: like going up
  LDA T2                       ; down: 1 right, 2 left
  INC A
  STA C_F,X
  RTS
.hs_up:
  LDA T2                       ; up: 0 right, 3 left
  BEQ .hs_f
  LDA #3
.hs_f:
  STA C_F,X
  RTS
.hs_shift:
  LDA SHIFT_T,Y
  BEQ .hs_r
  STA T2
.hs_l:
  LDA T1
  CMP #$80                     ; arithmetic shift right of T1:T0
  ROR T1
  ROR T0
  DEC T2
  BNE .hs_l
.hs_r:
  RTS

; X = slot: one frame of the hop; carry set = landed (C_ROW / C_COL = the target)
HOP_STEP:
  INC C_T,X
  CLC
  LDA C_XL,X
  ADC C_VXL,X
  STA C_XL,X
  LDA C_X,X
  ADC C_VXH,X
  STA C_X,X
  CLC
  LDA C_YL,X
  ADC C_VYL,X
  STA C_YL,X
  LDA C_Y,X
  ADC C_VYH,X
  STA C_Y,X
  LDY C_N,X
  LDA C_T,X
  CMP LEN_T,Y
  BCC .hp_r
  LDA C_TR,X
  STA C_ROW,X
  LDA C_TC,X
  STA C_COL,X
  LDA #ST_IDLE
  STA C_ST,X
  SEC
  RTS
.hp_r:
  CLC
  RTS

; X = slot: falling into the void; carry set = gone off the bottom of the screen
FALL_STEP:
  CLC
  LDA C_VYL,X                  ; gravity
  ADC #$20
  STA C_VYL,X
  BCC .fs_v
  INC C_VYH,X
.fs_v:
  CLC
  LDA C_XL,X
  ADC C_VXL,X
  STA C_XL,X
  LDA C_X,X
  ADC C_VXH,X
  STA C_X,X
  CLC
  LDA C_YL,X
  ADC C_VYL,X
  STA C_YL,X
  LDA C_Y,X
  ADC C_VYH,X
  STA C_Y,X
  BCS .fs_out                  ; past 255
  CMP #200
  BCS .fs_out
  CLC
  RTS
.fs_out:
  LDA #ST_OFF
  STA C_ST,X
  SEC
  RTS

; X = slot: a hop that ended on the void becomes a fall
START_FALL:
  LDA #ST_FALL
  STA C_ST,X
  LDA #$80                     ; it goes on a little sideways, and down
  STZ C_VYL,X
  LDA #1
  STA C_VYH,X
  LDA C_VXH,X                  ; sideways: half the speed of the hop
  CMP #$80
  ROR C_VXH,X
  ROR C_VXL,X
  RTS

; X = slot: A = height of the hop now
ARC_OF:
  LDA C_ST,X
  CMP #ST_HOP
  BNE .ao_0
  LDY C_N,X
  LDA ARC_BASE,Y
  CLC
  ADC C_T,X
  TAY
  LDA ARC,Y
  RTS
.ao_0:
  LDA #0
  RTS

; X = slot: T0 = cube it stands on (or the target of its hop if it is on the board)
WHERE:
  LDA C_ROW,X
  STA TR
  LDA C_COL,X
  STA TC
  JSR CUBE_AT
  STA T0
  RTS


; ===============================================================
;  ROBERT
; ===============================================================
UPDATE_ROBERT:
  LDX #S_ROB
  LDA C_ST
  CMP #ST_IDLE
  BEQ .ur_idle
  CMP #ST_HOP
  BEQ .ur_hop
  CMP #ST_FALL
  BEQ .ur_fall
  RTS
.ur_fall:
  JSR FALL_STEP
  BCC .ur_r
  LDA #2                       ; gone: a life lost
  STA GSTATE
  LDA #30
  STA GT
.ur_r:
  RTS
.ur_hop:
  JSR HOP_STEP
  BCC .ur_r
  JSR WHERE
  LDA T0
  CMP #$FF
  BNE .ur_land
  JSR START_FALL               ; off the board!
  LDA #W_FALL
  LDX #2
  JMP SFX_WHISTLE
.ur_land:
  STA RCUBE
  LDA #ROB_PAUSE
  STA C_W
  JMP LAND
.ur_idle:
  LDA C_W                      ; a moment on the spring
  BEQ .ur_joy
  DEC C_W
  RTS
.ur_joy:
  LDA JOYC
  AND #$0F
  TAY
  LDA JOY_DIR,Y
  BMI .ur_r
  STA T3                       ; direction
  LDA JOYC                     ; button just pressed: the long jump
  AND #%00010000
  BEQ .ur_one
  LDA JOYP
  AND #%00010000
  BNE .ur_one
  LDA LJUMP
  BEQ .ur_one
  STZ LJUMP
  LDA #1
  STA HUDD
  LDY T3
  LDA DR_T,Y
  ASL A
  CLC
  ADC C_ROW
  STA TR
  LDA DK_T,Y
  ASL A
  CLC
  ADC C_COL
  STA TC
  LDA #W_LONG
  LDX #0
  JSR SFX_WHISTLE
  LDA #1
  BRA .ur_go
.ur_one:
  LDY T3
  LDA DR_T,Y
  CLC
  ADC C_ROW
  STA TR
  LDA DK_T,Y
  CLC
  ADC C_COL
  STA TC
  LDA #W_HOP
  LDX #0
  JSR SFX_WHISTLE
  LDA #0
.ur_go:
  LDX #S_ROB
  JSR HOP_START
  ; fall into RECORD

; Robert hops: the Ghost will do the same hop GHOST_DELAY frames later
RECORD:
  LDA GREC
  BEQ .re_r
  LDY GHEAD
  CLC
  LDA GF
  ADC #<GHOST_DELAY
  STA GB_TL,Y
  LDA GF+1
  ADC #>GHOST_DELAY
  STA GB_TH,Y
  LDA C_TR
  STA GB_R,Y
  LDA C_TC
  STA GB_C,Y
  LDA C_N
  STA GB_N,Y
  INY
  TYA
  AND #$0F
  STA GHEAD
.re_r:
  RTS

; Robert lands on cube A: paint, item, gold cube
LAND:
  STA CUR
  LDA ITEMK                    ; the item of the cube
  BEQ .la_p
  LDA ITEMC
  CMP CUR
  BNE .la_p
  JSR COLLECT
.la_p:
  LDX RCUBE
  LDA CST,X
  CMP #3
  BNE .la_n
  JSR PAINT                    ; a gold cube: painted, then the super jump
  JMP SUPER_JUMP
.la_n:
  ; fall into PAINT

; X = cube: one step of the rule of the round
PAINT:
  STX CUR
  LDA CST,X
  STA OLDS
  LDA RULE
  ASL A
  ASL A
  ORA OLDS
  TAY
  LDA RULE_NEXT,Y
  CMP OLDS
  BEQ .pa_r                    ; nothing changes
  STA CST,X
  LDY OLDS
  CPY #2
  BNE .pa_ng
  DEC GOALN                    ; away from the goal colour
.pa_ng:
  CPY #3
  BNE .pa_nd
  DEC GOLDN                    ; a gold cube used
.pa_nd:
  CMP #2
  BNE .pa_pt
  INC GOALN                    ; the goal colour: 75
  LDA #$75
  LDY #0
  JSR ADD_PTS
  LDA #W_GOAL
  LDX #0
  JSR SFX_WHISTLE
  BRA .pa_d
.pa_pt:
  LDA #$25
  LDY #0
  JSR ADD_PTS
  LDA #W_PAINT
  LDX #0
  JSR SFX_WHISTLE
.pa_d:
  LDX CUR
  JSR DRAW_CUBE
  LDA GOALN                    ; all the cubes done?
  CMP NC
  BNE .pa_r
  LDA #3
  STA GSTATE
.pa_r:
  RTS

; from the gold cube CUR to the cube farthest from the Blot (or from here)
SUPER_JUMP:
  LDA GSTATE
  BNE .sj_r
  LDX CUR
  LDA CRW,X
  STA T6
  LDA CKC,X
  STA T7
  LDA C_ST+S_BLOT
  CMP #ST_IDLE
  BCC .sj_from
  CMP #ST_FALL
  BCS .sj_from
  LDA C_ROW+S_BLOT
  STA T6
  LDA C_COL+S_BLOT
  STA T7
.sj_from:
  STZ BEST
  LDA CUR
  STA BESTI
  LDX NC
.sj_l:
  DEX
  BMI .sj_go
  LDA CRW,X
  SEC
  SBC T6
  BPL .sj_a
  EOR #$FF
  INC A
.sj_a:
  STA DIST
  LDA CKC,X
  SEC
  SBC T7
  BPL .sj_b
  EOR #$FF
  INC A
.sj_b:
  CLC
  ADC DIST
  CMP BEST
  BCC .sj_l
  STA BEST
  STX BESTI
  BRA .sj_l
.sj_go:
  LDX BESTI
  LDA CRW,X
  STA TR
  LDA CKC,X
  STA TC
  LDX #S_ROB
  LDA #2
  JSR HOP_START
  JSR RECORD
  LDA #64                      ; the enemies wait while Robert flies
  STA FREEZE
  LDA #W_SPRING
  LDX #2
  JSR SFX_WHISTLE
  LDA #$00
  LDY #$05
  JMP ADD_PTS
.sj_r:
  RTS


; ===============================================================
;  ENEMIES
; ===============================================================
UPDATE_ENEMIES:
  LDA FREEZE
  BEQ .ue_go
  DEC FREEZE
  RTS
.ue_go:
  LDX #1
.ue_l:
  STX SLOT
  LDA C_ST,X
  BEQ .ue_n
  CMP #ST_WAIT
  BNE .ue_nw
  LDA GF                       ; waiting: 4-frame units
  AND #$03
  BNE .ue_n
  DEC C_W,X
  BNE .ue_n
  JSR ENTER                    ; time to come in
  BRA .ue_n
.ue_nw:
  CMP #ST_SHOW
  BEQ .ue_show
  CMP #ST_PEND
  BEQ .ue_show
  CMP #ST_SQUASH
  BNE .ue_nsq
  DEC C_W,X
  BNE .ue_n
  LDA #200                     ; squashed: back after a while
  JSR WAIT_SLOT
  BRA .ue_n
.ue_nsq:
  CMP #ST_FALL
  BNE .ue_nf
  JSR FALL_STEP
  BCC .ue_n
  LDA ROLLW                    ; only the Roller falls
  JSR WAIT_SLOT
  BRA .ue_n
.ue_nf:
  CMP #ST_HOP
  BNE .ue_idle
  JSR HOP_STEP
  BCC .ue_n
  JSR ON_LAND
  BRA .ue_n
.ue_idle:
  JSR THINK
  BRA .ue_n
.ue_show:
  DEC C_W,X
  BNE .ue_n
  LDA C_ST,X
  CMP #ST_PEND
  BNE .ue_si
  LDA #ST_SHOW                 ; the Ghost: now it shows
  STA C_ST,X
  LDA #40
  STA C_W,X
  BRA .ue_n
.ue_si:
  LDA #ST_IDLE
  STA C_ST,X
  LDA #8
  STA C_W,X
.ue_n:
  LDX SLOT
  INX
  CPX #NSLOT
  BNE .ue_l
  RTS

; X = slot: it comes on the board (ST_WAIT is over)
ENTER:
  CPX #S_BLOT
  BNE .en_nb
  JSR RANDOM_CUBE              ; the Blot: a cube at random, far from Robert
  STX CUR
  JSR DIST_ROB
  LDX SLOT
  CMP #4
  BCC .en_retry
  LDA CUR
.en_show:
  JSR PLACE
  LDA #ST_SHOW
  STA C_ST,X
  LDA #40
  STA C_W,X
  RTS
.en_retry:
  LDA #1                       ; try again soon
  STA C_W,X
  RTS
.en_nb:
  CPX #S_ROLL
  BNE .en_nr
  JSR RANDOM_CUBE              ; the Roller: a cube on the edge, the void behind,
  STX CUR                      ; a cube in front
  JSR DIST_ROB
  CMP #2
  BCC .en_rr
  JSR NEXT_RND
  AND #$03
  STA T3
  LDA #4
  STA CNT
.en_rd:
  LDX CUR
  LDA T3
  JSR NEIGHBOUR
  CMP #$FF
  BEQ .en_rn
  LDX CUR
  LDA T3
  EOR #$02                     ; behind
  JSR NEIGHBOUR
  CMP #$FF
  BEQ .en_rok
.en_rn:
  LDA T3
  INC A
  AND #$03
  STA T3
  DEC CNT
  BNE .en_rd
.en_rr:
  LDX SLOT
  BRA .en_retry
.en_rok:
  LDX SLOT
  LDA T3
  STA C_D,X
  LDA CUR
  BRA .en_show
.en_nr:
  CPX #S_SPARK
  BNE .en_ng
  LDA #0                       ; the Spark: the first cube, going down right
  STA CUR
  JSR DIST_ROB
  LDX SLOT
  CMP #3
  BCC .en_retry
  LDA #1
  STA C_D,X
  LDA #0
  BRA .en_show
.en_ng:
  LDA C_ST                     ; the Ghost: where Robert stands now, 3 seconds later
  CMP #ST_IDLE
  BNE .en_retry
  LDA RCUBE
  JSR PLACE
  LDA #ST_PEND
  STA C_ST,X
  LDA #GHOST_DELAY
  STA C_W,X
  LDA #225                     ; 15 seconds of life once it shows
  STA C_L,X
  LDA #1
  STA GREC
  LDA GHEAD
  STA GTAIL
  RTS

; cube CUR: A = its distance (rows + columns) from Robert's cube
DIST_ROB:
  LDX CUR
  LDY RCUBE
  LDA CRW,X
  SEC
  SBC CRW,Y
  BPL .dr_a
  EOR #$FF
  INC A
.dr_a:
  STA DIST
  LDA CKC,X
  SEC
  SBC CKC,Y
  BPL .dr_b
  EOR #$FF
  INC A
.dr_b:
  CLC
  ADC DIST
  RTS

; X = slot on a cube: decide the next hop
THINK:
  CPX #S_GHOST
  BNE .th_ng
  LDA GF                       ; the Ghost: life
  AND #$03
  BNE .th_gl
  DEC C_L,X
  BNE .th_gl
  STZ GREC                     ; gone
  LDA #100
  JMP WAIT_SLOT
.th_gl:
  LDY GTAIL                    ; a hop of Robert to repeat?
  CPY GHEAD
  BEQ .th_r
  LDA GF
  CMP GB_TL,Y
  LDA GF+1
  SBC GB_TH,Y
  BCC .th_r
  LDA GB_R,Y
  STA TR
  LDA GB_C,Y
  STA TC
  LDA GB_N,Y
  PHA
  INY
  TYA
  AND #$0F
  STA GTAIL
  PLA
  JMP HOP_START
.th_r:
  RTS
.th_ng:
  LDA C_W,X                    ; the others: a pause on every cube
  BEQ .th_go
  DEC C_W,X
  RTS
.th_go:
  JSR WHERE
  LDA T0
  STA CUR
  CPX #S_BLOT
  BEQ .th_blot
  JMP .th_nb
.th_blot:
  ; ---- the Blot: the neighbour nearest to Robert
  LDY RCUBE
  LDA C_ST
  CMP #ST_HOP
  BNE .th_rob
  LDA C_TR                     ; Robert in the air: where he lands, if it is a cube
  STA TR
  LDA C_TC
  STA TC
  JSR CUBE_AT
  CMP #$FF
  BEQ .th_rob
  TAY
.th_rob:
  LDA CRW,Y
  STA T6
  LDA CKC,Y
  STA T7
  LDA #$FF
  STA BEST
  STA BESTI
  JSR NEXT_RND
  AND #$03
  STA T3
  LDA #4
  STA CNT
.th_bl:
  LDX CUR
  LDA T3
  JSR NEIGHBOUR
  CMP #$FF
  BEQ .th_bn
  LDA TR
  SEC
  SBC T6
  BPL .th_ba
  EOR #$FF
  INC A
.th_ba:
  STA DIST
  LDA TC
  SEC
  SBC T7
  BPL .th_bb
  EOR #$FF
  INC A
.th_bb:
  CLC
  ADC DIST
  CMP BEST
  BCS .th_bn
  STA BEST
  LDA T3
  STA BESTI
.th_bn:
  LDA T3
  INC A
  AND #$03
  STA T3
  DEC CNT
  BNE .th_bl
  LDX SLOT
  LDA BESTI
  BPL .th_bgo
  RTS
.th_bgo:
  LDX CUR
  JSR NEIGHBOUR
  LDX SLOT
  LDA BLOTW
  STA C_W,X
  LDA #W_BLOT
  LDX #1
  JSR SFX_WHISTLE
  LDX SLOT
  LDA #0
  JMP HOP_START
.th_nb:
  CPX #S_ROLL
  BNE .th_sp
  ; ---- the Roller: straight on, into the void at the end
  LDA C_D,X
  LDX CUR
  JSR NEIGHBOUR
  LDX SLOT
  LDA #ROLL_PAUSE
  STA C_W,X
  LDA #S_RUMBLE
  LDX #1
  JSR SFX_BOOM
  LDX SLOT
  LDA #3
  JMP HOP_START
.th_sp:
  ; ---- the Spark: along the edge (keeps the void on its left)
  LDA C_D,X
  CLC
  ADC #3
  AND #$03
  STA T3
  LDA #4
  STA CNT
.th_sl:
  LDX CUR
  LDA T3
  JSR NEIGHBOUR
  CMP #$FF
  BNE .th_sgo
  LDA T3
  INC A
  AND #$03
  STA T3
  DEC CNT
  BNE .th_sl
  RTS
.th_sgo:
  LDX SLOT
  LDA T3
  STA C_D,X
  LDA SPARKW
  STA C_W,X
  LDA #3
  JMP HOP_START

; X = slot, landed after a hop
ON_LAND:
  JSR WHERE
  LDA T0
  CMP #$FF
  BNE .ol_on
  JMP START_FALL               ; the Roller rolled off the board
.ol_on:
  CPX #S_ROLL
  BNE .ol_r
  TAX                          ; the Roller wipes the paint
  LDA CST,X
  BEQ .ol_r
  CMP #3
  BEQ .ol_r
  CMP #2
  BNE .ol_w
  DEC GOALN
.ol_w:
  STZ CST,X
  JSR DRAW_CUBE
.ol_r:
  LDX SLOT
  RTS


; ===============================================================
;  ITEMS: bucket and star
; ===============================================================
UPDATE_ITEM:
  LDA GF
  AND #$03
  BNE .ui_r
  LDA ITEMK
  BEQ .ui_w
  DEC ITEMT                    ; on the board: it goes away
  BNE .ui_r
  STZ ITEMK
  LDA #150
  STA ITEMW
.ui_r:
  RTS
.ui_w:
  DEC ITEMW
  BNE .ui_r
  JSR RANDOM_CUBE              ; a cube that is not Robert's and not gold
  CPX RCUBE
  BEQ .ui_again
  LDA CST,X
  CMP #3
  BEQ .ui_again
  STX ITEMC
  LDA #1                       ; the bucket, or the star from level 2
  STA ITEMK
  LDA LEVEL
  CMP #2
  BCC .ui_t
  LDA RND
  AND #$04
  BEQ .ui_t
  INC ITEMK
.ui_t:
  LDA #75
  STA ITEMT
  RTS
.ui_again:
  INC ITEMW
  RTS

; Robert takes the item
COLLECT:
  LDA #W_ITEM
  LDX #2
  JSR SFX_WHISTLE
  LDA #$00
  LDY #$02
  JSR ADD_PTS
  LDA ITEMK
  STZ ITEMK
  LDX #150
  STX ITEMW
  CMP #2
  BNE .co_b
  LDA #240                     ; the star: 4 seconds
  STA STARF
  RTS
.co_b:
  LDA #4                       ; the bucket: the 4 neighbours to the goal colour
  STA T3                       ; (the cube itself is painted by the landing)
.co_l:
  DEC T3
  BMI .co_e
  LDX ITEMC
  LDA T3
  JSR NEIGHBOUR
  CMP #$FF
  BEQ .co_l
  TAX
  LDA CST,X
  CMP #2
  BEQ .co_l
  CMP #3
  BEQ .co_l
  LDA #2
  STA CST,X
  INC GOALN
  PHX
  JSR DRAW_CUBE
  PLX
  BRA .co_l
.co_e:
  LDA GOALN
  CMP NC
  BNE .co_r
  LDA #3
  STA GSTATE
.co_r:
  RTS


; ===============================================================
;  COLLISIONS: Robert and the enemies (by the pixels of the sprites)
; ===============================================================
COLLIDE:
  LDA C_ST
  CMP #ST_IDLE
  BEQ .cl_ok
  CMP #ST_HOP
  BNE .cl_r
  LDA C_N
  CMP #2
  BEQ .cl_r                    ; flying high: nothing touches him
.cl_ok:
  LDX #S_ROB
  JSR ARC_OF
  STA T0
  LDA C_Y
  SEC
  SBC T0
  STA T6                       ; Robert's feet
  LDA C_X
  STA T7
  LDX #1
.cl_l:
  LDA C_ST,X
  CMP #ST_IDLE
  BEQ .cl_t
  CMP #ST_HOP
  BNE .cl_n
.cl_t:
  STX SLOT
  JSR ARC_OF
  STA T0
  LDX SLOT
  LDA C_X,X
  SEC
  SBC T7
  BPL .cl_a
  EOR #$FF
  INC A
.cl_a:
  CMP #10
  BCS .cl_n
  LDA C_Y,X
  SEC
  SBC T0
  SEC
  SBC T6
  BPL .cl_b
  EOR #$FF
  INC A
.cl_b:
  CMP #10
  BCS .cl_n
  LDA STARF                    ; the star squashes the Blot and the Ghost
  BEQ .cl_hit
  CPX #S_BLOT
  BEQ .cl_sq
  CPX #S_GHOST
  BNE .cl_hit
  STZ GREC
.cl_sq:
  LDA #ST_SQUASH
  STA C_ST,X
  LDA #30
  STA C_W,X
  LDA #W_SQUASH
  LDX #2
  JSR SFX_WHISTLE
  LDA #$00
  LDY #$03
  JSR ADD_PTS
  LDX SLOT
.cl_n:
  INX
  CPX #NSLOT
  BNE .cl_l
.cl_r:
  RTS
.cl_hit:
  LDA #1                       ; caught!
  STA GSTATE
  LDA #90
  STA GT
  LDA #S_GLOP
  LDX #2
  JMP SFX_BOOM


; ===============================================================
;  SPRITES: Robert first (2 layers), then the enemies and the item
;  in an order that turns every frame (with more than 4 on a line
;  they flicker instead of disappearing)
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA C_ST
  BEQ .bs_e
  LDA GSTATE                   ; caught: he flashes
  CMP #1
  BNE .bs_rv
  LDA GF
  AND #$04
  BNE .bs_e
.bs_rv:
  LDX #S_ROB
  JSR AT_SLOT
  BCS .bs_e
  LDA C_F
  ASL A
  LDY C_ST
  CPY #ST_IDLE
  BNE .bs_air
  INC A
.bs_air:
  ASL A
  ASL A
  ASL A
  STA T5                       ; PT_ROB + (facing * 2 + frame) * 8
  STA ON
  LDA #$08                     ; detail: red (yellow with the star, flashing)
  LDY STARF
  BEQ .bs_dc
  LDA GF
  AND #$04
  BEQ .bs_dy
  LDA #$0F
  BRA .bs_dc
.bs_dy:
  LDA #$0B
.bs_dc:
  STA OC
  JSR ADD_SPR
  LDA T5
  CLC
  ADC #4
  STA ON
  LDA #$0F
  STA OC
  JSR ADD_SPR
.bs_e:
  INC RR                       ; ---- enemies and item
  LDA RR
  CMP #NSLOT
  BCC .bs_rr
  LDA #1
  STA RR
.bs_rr:
  LDA RR
  STA SLOT
  LDA #NSLOT
  STA CNT
.bs_ol:
  LDX SLOT
  CPX #NSLOT
  BNE .bs_en
  JSR DRAW_ITEM
  BRA .bs_nx
.bs_en:
  JSR DRAW_ENEMY
.bs_nx:
  INC SLOT
  LDA SLOT
  CMP #NSLOT+1
  BCC .bs_on
  LDA #1
  STA SLOT
.bs_on:
  DEC CNT
  BNE .bs_ol
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; X = slot: OX / OY of its sprite; carry set = not on the screen
AT_SLOT:
  LDA C_X,X
  CMP #6
  BCC .at_no
  CMP #251
  BCS .at_no
  STA OX
  JSR ARC_OF
  STA T0
  LDA C_Y,X
  SEC
  SBC T0
  BCC .at_top
  SEC
  SBC #5
  BCC .at_top
  CMP #10
  BCS .at_y
.at_top:
  LDA #10                      ; high in the air at the top: it stays on the screen
.at_y:
  CMP #196
  BCS .at_no
  STA OY
  CLC
  RTS
.at_no:
  SEC
  RTS

; X = slot 1-4
DRAW_ENEMY:
  LDA C_ST,X
  BEQ .de_no
  CMP #ST_WAIT
  BEQ .de_no
  CMP #ST_PEND
  BEQ .de_no
  CMP #ST_SHOW
  BNE .de_vis
  LDA GF                       ; appearing: flashing
  AND #$04
  BNE .de_no
.de_vis:
  JSR AT_SLOT
  BCC .de_on
.de_no:
  RTS
.de_on:
  LDA C_ST,X
  CMP #ST_SQUASH
  BNE .de_k
  LDA #PT_SPLAT
  STA ON
  LDA #$01
  CPX #S_BLOT
  BEQ .de_sq
  LDA #$0E
.de_sq:
  STA OC
  JMP ADD_SPR
.de_k:
  CPX #S_BLOT
  BNE .de_nb
  LDA #PT_BLOT                 ; the Blot: black, squat on the cube
  LDY C_ST,X
  CPY #ST_HOP
  BEQ .de_b
  LDA #PT_BLOT+4
.de_b:
  STA ON
  LDA #$01
  STA OC
  JMP ADD_SPR
.de_nb:
  CPX #S_ROLL
  BNE .de_ns
  LDA GF                       ; the Roller: red, turning
  AND #$04
  ORA #PT_ROLL
  STA ON
  LDA #$08
  STA OC
  JMP ADD_SPR
.de_ns:
  CPX #S_SPARK
  BNE .de_ng
  LDA GF                       ; the Spark: yellow and white
  AND #$04
  ORA #PT_SPARK
  STA ON
  LDA GF
  AND #$08
  BEQ .de_sy
  LDA #$0F
  BRA .de_sc
.de_sy:
  LDA #$0B
.de_sc:
  STA OC
  JMP ADD_SPR
.de_ng:
  LDA C_F,X                    ; the Ghost: Robert's body, grey
  ASL A
  LDY C_ST,X
  CPY #ST_IDLE
  BNE .de_ga
  INC A
.de_ga:
  ASL A
  ASL A
  ASL A
  ORA #PT_ROB+4
  STA ON
  LDA #$0E
  STA OC
  JMP ADD_SPR
.de_r:
  RTS

DRAW_ITEM:
  LDA ITEMK
  BEQ .di_r
  LDA ITEMT                    ; the last 2 seconds: flashing
  CMP #30
  BCS .di_v
  LDA GF
  AND #$08
  BNE .di_r
.di_v:
  LDX ITEMC
  LDA CKC,X
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #16
  STA OX
  LDA CRW,X
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #19
  STA OY
  LDA #PT_BUCKET
  LDY #$0F
  LDX ITEMK
  CPX #1
  BEQ .di_k
  LDA #PT_STAR
  LDY #$0B
.di_k:
  STA ON
  STY OC
  JMP ADD_SPR
.di_r:
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, HUD
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

; the table GFX_LOAD: copy / fill blocks into the VRAM
LOAD_GFX:
  JSR CLEAR_VRAM
  LDX #$00
.lg_l:
  LDA GFX_LOAD,X               ; kind: 0 end, 1 copy, 2 fill
  BEQ .lg_e
  STA T5
  LDA GFX_LOAD+1,X
  STA T0
  LDA GFX_LOAD+2,X
  STA T1
  LDA GFX_LOAD+3,X
  STA T2
  LDA GFX_LOAD+4,X
  STA T3
  LDA GFX_LOAD+5,X
  STA PTR
  LDA GFX_LOAD+6,X
  STA PTR+1
  PHX
  LDA T5
  CMP #1
  BNE .lg_f
  JSR VCOPY
  BRA .lg_n
.lg_f:
  LDA PTR
  JSR VFILL
.lg_n:
  PLX
  TXA
  CLC
  ADC #7
  TAX
  BRA .lg_l
.lg_e:
  JMP LOAD_SPRITES

; the whole name table to tile 0
CLEAR_NT:
  LDA #$00
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T1
  LDA #$00
  STA T2
  LDA #$03
  STA T3
  LDA #$00
  JMP VFILL

; X = row, Y = column: VDP address of the name table cell
NT_XY:
  TXA
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
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
; a 16x16 sprite centred on (OX, OY), pattern ON, colour OC (32 at most)
ADD_SPR:
  LDX SPRI
  CPX #128
  BCS .as_r
  LDA OY
  SEC
  SBC #9
  STA SAT_BUFFER,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OX
  SEC
  SBC #8
  BCC .as_ec
  STA SAT_BUFFER+1,X
  LDA OC
  STA SAT_BUFFER+3,X
  BRA .as_n
.as_ec:
  CLC                          ; near the left edge: early clock
  ADC #32
  STA SAT_BUFFER+1,X
  LDA OC
  ORA #$80
  STA SAT_BUFFER+3,X
.as_n:
  TXA
  CLC
  ADC #4
  STA SPRI
.as_r:
  RTS

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
;  SOUND: the start tune (4 tracks, from tank) and the effects
;  per chip in game: A = tone effects, B = noise and C = low tone
;  of the explosions; left chip = the fighter, right = the enemies
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
; starts the tune
; ---------------------------------------------------------------
SND_START:
  JSR SND_CLEAR_SH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #$2A                      ; right: tone A, noise B (drums), tone C
  STA SH_R+7
  LDX #$03
.ss_trk:
  LDA SONGP_LO,X
  STA TR_PL,X
  LDA SONGP_HI,X
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
;  LIBRARY (from lunar_lander): joystick, frames, VDP
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
;  TABLES
; ===============================================================
SC_COL:     .byte 1,25                         ; score of player 1 / 2: column on row 1
PS_OFF:     .byte 0,64                         ; block of the player in PSAVE

; directions 0 up right, 1 down right, 2 down left, 3 up left: row and column steps
DR_T:       .byte $FF,1,1,$FF
DK_T:       .byte 1,1,$FF,$FF
; joystick (bit 0 up, 1 down, 2 left, 3 right) turned by 45 degrees -> direction, $FF = none
JOY_DIR:    .byte $FF,0,2,$FF,3,3,2,$FF,1,0,1,$FF,$FF,$FF,$FF,$FF
; kinds of hop: 0 hop, 1 long jump, 2 super jump, 3 slide
LEN_T:      .byte 16,32,64,16                  ; frames
SHIFT_T:    .byte 0,1,2,0                      ; speed = steps * 256 >> shift
ARC_BASE:   .byte 0,16,48,112                  ; first height in ARC

; colour rules: next state for rule * 4 + state (0 start, 1 middle, 2 goal, 3 gold = start)
RULE_NEXT:  .byte 2,2,2,2                      ; one hop
            .byte 1,2,2,1                      ; two hops
            .byte 2,2,0,2                      ; every hop switches
            .byte 1,2,1,1                      ; two hops, a third one undoes
RULE_MID:   .byte 0,1,0,1                      ; 1 = the rule has a middle colour

; colours: faces of every board, tops of every board * 4 + round
FACE_L:     .byte $04,$0C,$06,$0A
FACE_R:     .byte $05,$02,$08,$0B
GOLD_C:     .byte $0A,$0A,$0A,$0F
PAL_S:      .byte $0E,$03,$0B,$07, $0E,$05,$0D,$09, $0E,$05,$0B,$09, $0E,$05,$03,$0D
PAL_M:      .byte $09,$0D,$07,$03, $07,$09,$0B,$0E, $07,$03,$0D,$0E, $07,$09,$0D,$0E
PAL_G:      .byte $0B,$07,$09,$0D, $0B,$0D,$07,$03, $0B,$0D,$07,$03, $0D,$03,$07,$09
; background of the 16 tiles of a state: 0 = right face, 1 = black, 2 = left face
BG_SLOT:    .byte 0,0,1,1,2,2,1,1,2,2,0,0,1,1,1,1

; difficulty 0-15 (stage, at most 15)
LV_BLOTW:   .byte 48,44,40,38,36,34,32,30,28,26,24,22,20,19,18,16     ; frames between two hops
LV_ROLLW:   .byte 150,140,130,120,110,100,95,90,85,80,75,70,65,60,55,50   ; x 4 frames
LV_SPARKW:  .byte 30,28,26,24,22,20,18,17,16,15,14,13,12,11,10,10     ; frames between two moves

; title: Robert (2 layers), Blot, Roller, Spark, Ghost, bucket, star  (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 19,19,9*8-5,11*8-5,13*8-5,15*8-5,17*8-5,19*8-5,0
TITLE_SX:   .byte 222,222,24,24,24,24,24,24,0
TITLE_SN:   .byte PT_ROB+16,PT_ROB+20,PT_BLOT+4,PT_ROLL,PT_SPARK,PT_ROB+20,PT_BUCKET,PT_STAR,0
TITLE_SC:   .byte $08,$0F,$0E,$08,$0B,$0E,$0F,$0B,$00

; row 23: long jump used / ready
TXT_JUMP:   .byte "     ",T_JUMP,"JUMP"

BNAME_LO:   .byte <TXT_B0,<TXT_B1,<TXT_B2,<TXT_B3
BNAME_HI:   .byte >TXT_B0,>TXT_B1,>TXT_B2,>TXT_B3
RULE_LO:    .byte <TXT_R0,<TXT_R1,<TXT_R2,<TXT_R3
RULE_HI:    .byte >TXT_R0,>TXT_R1,>TXT_R2,>TXT_R3

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 6,1,"HOP ON EVERY CUBE TO PAINT IT",0
  .byte 7,7,"IN THE GOAL COLOUR",0
  .byte 9,6,"BLOT   CHASES YOU",0
  .byte 11,6,"ROLLER WIPES THE PAINT",0
  .byte 13,6,"SPARK  RUNS ROUND THE EDGE",0
  .byte 15,6,"GHOST  COPIES YOUR HOPS",0
  .byte 17,6,"BUCKET PAINTS AROUND  200",0
  .byte 19,6,"STAR   SQUASHES BLOT  300",0
  .byte 21,5,"B1 + STICK = LONG JUMP",0
  .byte 22,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_BOT:
  .byte 23,1,"LEVEL",0
  .byte $FF
TXT_GOAL:
  .byte 5,0,"GOAL",0
  .byte $FF
TXT_PLAYER:
  .byte 6,12,"PLAYER ",0
  .byte $FF
TXT_LEVEL:
  .byte 8,7,"LEVEL         ROUND",0
  .byte 8,13,0
  .byte $FF
TXT_B0:
  .byte 10,12,"DIAMOND",0
  .byte $FF
TXT_B1:
  .byte 10,11,"HOURGLASS",0
  .byte $FF
TXT_B2:
  .byte 10,14,"RING",0
  .byte $FF
TXT_B3:
  .byte 10,10,"TWIN TOWERS",0
  .byte $FF
TXT_R0:
  .byte 18,5,"ONE HOP PAINTS A CUBE",0
  .byte $FF
TXT_R1:
  .byte 18,5,"TWO HOPS PAINT A CUBE",0
  .byte $FF
TXT_R2:
  .byte 18,1,"EVERY HOP SWITCHES THE COLOUR",0
  .byte $FF
TXT_R3:
  .byte 18,1,"TWO HOPS PAINT, A THIRD UNDOES",0
  .byte $FF
TXT_KEYS:
  .byte 20,1,"UP=UP RIGHT  RIGHT=DOWN RIGHT",0
  .byte 21,2,"DOWN=DOWN LEFT  LEFT=UP LEFT",0
  .byte $FF
TXT_ARROW3:
  .byte 14,12,">",0
  .byte 14,18,">",0
  .byte 16,9,"START",0
  .byte 16,21,"GOAL",0
  .byte $FF
TXT_ARROW2:
  .byte 14,15,">",0
  .byte 16,12,"START",0
  .byte 16,18,"GOAL",0
  .byte $FF
TXT_ARROWB:
  .byte 14,15,"<>",0
  .byte 16,12,"START",0
  .byte 16,18,"GOAL",0
  .byte $FF
TXT_BONUS:
  .byte 23,13,"BONUS ",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0
  .byte $FF

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

SONGP_LO:      .byte <START_LEAD,<START_HARM,<START_BASS,<START_DRUM
SONGP_HI:      .byte >START_LEAD,>START_HARM,>START_BASS,>START_DRUM

; AY periods (1 MHz): TP = 62500 / f.  index = MIDI note - 35  (1 = C2 ... 55 = F#6), 0 = rest
TP_LO:
  .byte $00,$BC,$86,$53,$24,$F6,$CC,$A4
  .byte $7E,$5A,$38,$18,$FA,$DE,$C3,$AA
  .byte $92,$7B,$66,$52,$3F,$2D,$1C,$0C
  .byte $FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9
  .byte $9F,$96,$8E,$86,$7F,$77,$71,$6A
  .byte $64,$5F,$59,$54,$50,$4B,$47,$43
  .byte $3F,$3C,$38,$35,$32,$2F,$2D,$2A
TP_HI:
  .byte $00,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$02,$02,$02,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00

; the start tune, a bouncy tune in C major (composed for this game), 256 frames
;   E4 29  F4 30  G4 32  A4 34  B4 36  C5 37  D5 39  E5 41  F5 42  G5 44  A5 46
START_LEAD:
  .byte 37,8, 32,8, 41,8, 32,8, 44,8, 32,8, 41,16
  .byte 42,8, 34,8, 39,8, 34,8, 42,8, 41,8, 39,16
  .byte 41,8, 37,8, 44,8, 41,8, 46,8, 44,8, 41,8, 37,8
  .byte 39,8, 44,8, 36,8, 39,8, 37,24, 0,8
  .byte $FF
START_HARM:
  .byte 29,64, 30,64, 29,32, 30,32, 30,32, 29,32
  .byte $FF
START_BASS:
  .byte 13,16, 8,16, 13,16, 8,16, 6,16, 13,16, 15,16, 10,16
  .byte 13,16, 8,16, 6,16, 10,16, 8,16, 15,16, 13,32
  .byte $FF
START_DRUM:
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,16, 2,16, 4,32
  .byte $FF
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
;  GRAPHICS AND SOUND TABLES (generated)
; ===============================================================
; Robert: generated by dev/gen_robert.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_ROB = 0
PT_BLOT = 64
PT_ROLL = 72
PT_SPARK = 80
PT_BUCKET = 88
PT_STAR = 92
PT_SPLAT = 96
SPR_PAGES = 4
SPRITES:
;  0 robert 0 detail, 4 robert 0 body, 8 robert 0 detail, 12 robert 0 body, 16 robert 1 detail, 20 robert 1 body, 24 robert 1 detail, 28 robert 1 body, 32 robert 2 detail, 36 robert 2 body, 40 robert 2 detail, 44 robert 2 body, 48 robert 3 detail, 52 robert 3 body, 56 robert 3 detail, 60 robert 3 body, 64 blot, 68 blot, 72 roller, 76 roller, 80 spark 0, 84 spark 1, 88 bucket, 92 star, 96 splat
  .byte $00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$07,$00,$01,$00,$01,$00
  .byte $80,$00,$00,$00,$00,$C0,$00,$00,$00,$C0,$F0,$80,$40,$80,$40,$80
  .byte $00,$00,$07,$07,$07,$06,$03,$0D,$09,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$F0,$F0,$F0,$30,$E0,$D8,$C8,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$07,$01,$00
  .byte $00,$00,$00,$80,$00,$00,$00,$00,$C0,$00,$00,$00,$C0,$F0,$C0,$80
  .byte $00,$00,$00,$00,$00,$07,$07,$07,$06,$03,$0D,$09,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$F0,$F0,$F0,$30,$E0,$D8,$C8,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$07,$00,$01,$00,$01,$00
  .byte $80,$00,$00,$A0,$00,$E0,$00,$00,$00,$C0,$F0,$80,$40,$80,$40,$80
  .byte $00,$00,$07,$07,$07,$06,$03,$0D,$09,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$F0,$50,$F0,$10,$E0,$D8,$C8,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$07,$01,$00
  .byte $00,$00,$00,$80,$00,$00,$A0,$00,$E0,$00,$00,$00,$C0,$F0,$C0,$80
  .byte $00,$00,$00,$00,$00,$07,$07,$07,$06,$03,$0D,$09,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$F0,$50,$F0,$10,$E0,$D8,$C8,$00,$00,$00,$00
  .byte $01,$00,$00,$05,$00,$07,$00,$00,$00,$03,$0F,$01,$02,$01,$02,$01
  .byte $00,$00,$00,$00,$00,$80,$00,$00,$00,$80,$E0,$00,$80,$00,$80,$00
  .byte $00,$01,$0F,$0A,$0F,$08,$07,$1B,$13,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$E0,$E0,$E0,$60,$C0,$B0,$90,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$00,$00,$05,$00,$07,$00,$00,$00,$03,$0F,$03,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$80,$E0,$80,$00
  .byte $00,$00,$00,$00,$01,$0F,$0A,$0F,$08,$07,$1B,$13,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$E0,$E0,$E0,$60,$C0,$B0,$90,$00,$00,$00,$00
  .byte $01,$00,$00,$00,$00,$03,$00,$00,$00,$03,$0F,$01,$02,$01,$02,$01
  .byte $00,$00,$00,$00,$00,$80,$00,$00,$00,$80,$E0,$00,$80,$00,$80,$00
  .byte $00,$01,$0F,$0F,$0F,$0C,$07,$1B,$13,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$E0,$E0,$E0,$60,$C0,$B0,$90,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$03,$00,$00,$00,$03,$0F,$03,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$80,$E0,$80,$00
  .byte $00,$00,$00,$00,$01,$0F,$0F,$0F,$0C,$07,$1B,$13,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$E0,$E0,$E0,$60,$C0,$B0,$90,$00,$00,$00,$00
  .byte $01,$03,$03,$07,$0F,$1F,$3C,$3C,$7F,$7F,$7F,$3F,$1F,$07,$00,$00
  .byte $80,$C0,$C0,$E0,$F0,$F8,$CE,$CE,$FE,$FE,$FE,$FC,$F8,$E0,$00,$00
  .byte $00,$00,$00,$01,$03,$0F,$3F,$79,$79,$FF,$FF,$FF,$7F,$1F,$00,$00
  .byte $00,$00,$00,$80,$C0,$F0,$FC,$9E,$9E,$FF,$FF,$FF,$FE,$F8,$00,$00
  .byte $01,$01,$00,$00,$1F,$10,$10,$3F,$7F,$2A,$7F,$2A,$7F,$3F,$00,$00
  .byte $80,$80,$80,$80,$C0,$00,$00,$FF,$FE,$AA,$FE,$AA,$FE,$FC,$00,$00
  .byte $01,$01,$00,$00,$1F,$10,$10,$3F,$7F,$55,$7F,$55,$7F,$3F,$00,$00
  .byte $80,$80,$80,$80,$C0,$00,$00,$FF,$FE,$54,$FE,$54,$FE,$FC,$00,$00
  .byte $00,$01,$11,$30,$08,$04,$03,$63,$63,$03,$04,$08,$30,$11,$01,$00
  .byte $00,$80,$88,$0C,$10,$20,$C0,$C6,$C6,$C0,$20,$10,$0C,$88,$80,$00
  .byte $00,$00,$04,$02,$02,$20,$19,$03,$03,$19,$20,$02,$02,$04,$00,$00
  .byte $00,$00,$20,$40,$40,$04,$98,$C0,$C0,$98,$04,$40,$40,$20,$00,$00
  .byte $00,$0F,$10,$20,$3F,$3F,$30,$37,$37,$30,$3F,$3F,$1F,$18,$00,$00
  .byte $00,$F0,$08,$04,$FC,$FC,$0C,$EC,$EC,$0C,$FC,$FC,$F8,$20,$20,$00
  .byte $00,$00,$01,$01,$01,$03,$7F,$1F,$0F,$07,$07,$07,$0E,$08,$00,$00
  .byte $00,$00,$80,$80,$80,$C0,$FE,$F8,$F0,$E0,$E0,$E0,$70,$10,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$07,$1F,$3F,$0F,$0F,$1F,$09,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$E0,$FC,$FC,$FE,$FC,$38,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; cube tiles 128-191 (4 states x 16), the same drawing for every state: the colours make the state
CUBE_PAT:
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01
  .byte $FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01
  .byte $FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01
  .byte $FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $80,$E0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01
  .byte $FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; under a cube with no neighbour below (192-195)
BOT_PAT:
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01
  .byte $FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
T_LIFE = 1
T_JUMP = 2
; small tiles: life, jump
SMALL_PAT:
  .byte $10,$7C,$54,$7C,$38,$54,$10,$38,$08,$1C,$2A,$08,$08,$3E,$1C,$08
SMALL_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0

; big letters of the title: R O B E T, 4 tiles each (200-219)
BIG_P:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
BIG_C:
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$80,$80,$80,$60,$60,$90,$90,$90,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$80,$80,$80,$60,$60,$90,$90,$90,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$80,$80,$80,$60,$60,$90,$90,$90,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$80,$80,$80,$60,$60,$90,$90,$90,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$80,$80,$80,$60,$60,$90,$90,$90,$80,$80,$80,$60,$60

TXT_BIG:
  .byte 3,10,200,201,204,205,208,209,212,213,200,201,216,217,0
  .byte 4,10,202,203,206,207,210,211,214,215,202,203,218,219,0
  .byte $FF

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $00,$44, <512,>512, <CUBE_PAT,>CUBE_PAT
  .byte 1, $00,$46, <32,>32, <BOT_PAT,>BOT_PAT
  .byte 1, $08,$40, <16,>16, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$60, <16,>16, <SMALL_COL,>SMALL_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $00,$4C, <512,>512, <CUBE_PAT,>CUBE_PAT
  .byte 1, $00,$4E, <32,>32, <BOT_PAT,>BOT_PAT
  .byte 1, $08,$48, <16,>16, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$68, <16,>16, <SMALL_COL,>SMALL_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $00,$54, <512,>512, <CUBE_PAT,>CUBE_PAT
  .byte 1, $00,$56, <32,>32, <BOT_PAT,>BOT_PAT
  .byte 1, $08,$50, <16,>16, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$70, <16,>16, <SMALL_COL,>SMALL_COL
  .byte 1, $40,$46, <160,>160, <BIG_P,>BIG_P
  .byte 1, $40,$66, <160,>160, <BIG_C,>BIG_C
  .byte 0

; boards: number of cubes, start cube, then row, column of every cube (rows top to bottom)
;   0 DIAMOND: 25 cubes
;   1 HOURGLASS: 29 cubes
;   2 RING: 28 cubes
;   3 TWIN TOWERS: 33 cubes
BOARD_LO:  .byte <(BOARDS+0),<(BOARDS+52),<(BOARDS+112),<(BOARDS+170)
BOARD_HI:  .byte >(BOARDS+0),>(BOARDS+52),>(BOARDS+112),>(BOARDS+170)
BOARDS:
  .byte $19,$00,$00,$07,$01,$06,$01,$08,$02,$05,$02,$07,$02,$09,$03,$04
  .byte $03,$06,$03,$08,$03,$0A,$04,$03,$04,$05,$04,$07,$04,$09,$04,$0B
  .byte $05,$04,$05,$06,$05,$08,$05,$0A,$06,$05,$06,$07,$06,$09,$07,$06
  .byte $07,$08,$08,$07,$1D,$02,$00,$03,$00,$05,$00,$07,$00,$09,$00,$0B
  .byte $01,$04,$01,$06,$01,$08,$01,$0A,$02,$05,$02,$07,$02,$09,$03,$06
  .byte $03,$08,$04,$07,$05,$06,$05,$08,$06,$05,$06,$07,$06,$09,$07,$04
  .byte $07,$06,$07,$08,$07,$0A,$08,$03,$08,$05,$08,$07,$08,$09,$08,$0B
  .byte $1C,$00,$00,$07,$01,$06,$01,$08,$02,$05,$02,$07,$02,$09,$03,$04
  .byte $03,$06,$03,$08,$03,$0A,$04,$03,$04,$05,$04,$09,$04,$0B,$05,$04
  .byte $05,$06,$05,$0A,$05,$0C,$06,$05,$06,$07,$06,$09,$06,$0B,$07,$06
  .byte $07,$08,$07,$0A,$08,$07,$08,$09,$09,$08,$21,$00,$00,$03,$01,$02
  .byte $01,$04,$02,$01,$02,$03,$02,$05,$02,$0B,$03,$00,$03,$02,$03,$04
  .byte $03,$06,$03,$0A,$03,$0C,$04,$01,$04,$03,$04,$05,$04,$07,$04,$09
  .byte $04,$0B,$04,$0D,$05,$02,$05,$04,$05,$08,$05,$0A,$05,$0C,$05,$0E
  .byte $06,$03,$06,$09,$06,$0B,$06,$0D,$07,$0A,$07,$0C,$08,$0B

; height of the hop for every frame: 0 hop (16 frames), 16 long jump (32), 48 super jump (64), 112 slide (16)
ARC:
  .byte $00,$02,$05,$07,$08,$0A,$0B,$0C,$0C,$0C,$0B,$0A,$08,$07,$05,$02
  .byte $00,$03,$05,$08,$0A,$0C,$0E,$10,$12,$14,$16,$17,$18,$19,$1A,$1A
  .byte $1A,$1A,$1A,$19,$18,$17,$16,$14,$12,$10,$0E,$0C,$0A,$08,$05,$03
  .byte $00,$03,$05,$08,$0B,$0E,$10,$13,$15,$18,$1A,$1D,$1F,$21,$24,$26
  .byte $28,$29,$2B,$2D,$2F,$30,$31,$33,$34,$35,$36,$36,$37,$37,$38,$38
  .byte $38,$38,$38,$37,$37,$36,$36,$35,$34,$33,$31,$30,$2F,$2D,$2B,$29
  .byte $28,$26,$24,$21,$1F,$1D,$1A,$18,$15,$13,$10,$0E,$0B,$08,$05,$03
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$A4,$80,$71,$71,$7D,$94,$AA,$AA,$90,$2D,$26,$20,$1C,$28,$28
  .byte $28,$1E,$1E,$1E,$1E,$30,$32,$35,$37,$3A,$3D,$3F,$42,$45,$49,$4C
  .byte $50,$54,$57,$5C,$60,$64,$69,$6E,$73,$79,$7E,$84,$8B,$91,$98,$9F
  .byte $A7,$AF,$B7,$BF,$C8,$D2,$DC,$E6,$F1,$FC,$08,$15,$22,$2F,$3E,$4D
  .byte $5C,$6D,$D0,$94,$7F,$7F,$92,$BB,$E8,$E9,$B7,$87,$6B,$5F,$95,$76
  .byte $69,$69,$74,$87,$9A,$99,$84,$6B,$70,$5F,$58,$57,$5D,$67,$6F,$6E
  .byte $D0,$B5,$9F,$8F,$81,$76,$6C,$64,$5D,$57,$52,$4D,$49,$45,$5B,$7B
  .byte $A1,$CF,$09,$50,$50,$50,$3C,$3C,$3C,$2F,$2F,$2F,$28,$28,$28,$45
  .byte $4C,$54,$5E,$6A,$7A,$90,$B0,$E1,$39,$78,$78,$78,$78,$5F,$5F,$5F
  .byte $5F,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$50,$50,$50,$50,$3C,$3C,$3C
  .byte $3C,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$00,$00,$00,$28,$28,$28,$28,$28
  .byte $00,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$9F,$9F,$9F,$9F,$9F
  .byte $9F,$9F,$9F,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD
  .byte $BD,$BD,$BD,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$EF,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$0B,$09,$08,$06,$0C,$0B
  .byte $09,$0C,$0A,$08,$06,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B
  .byte $0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07
  .byte $07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03
  .byte $03,$02,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$0C,$0C
  .byte $0B,$0B,$0A,$0A,$09,$09,$08,$08,$0A,$0A,$09,$09,$08,$08,$07,$07
  .byte $0D,$0D,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$0A,$09
  .byte $07,$06,$04,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0D
  .byte $0C,$0B,$0B,$0A,$09,$08,$08,$07,$06,$0D,$0B,$0A,$08,$0D,$0B,$0A
  .byte $08,$0D,$0B,$0A,$08,$0D,$0B,$0A,$08,$0D,$0B,$0A,$08,$0D,$0B,$0A
  .byte $08,$0D,$0B,$0A,$08,$0D,$0D,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09
  .byte $09,$08,$08,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B,$0A,$09
  .byte $00,$00,$00,$0D,$0C,$0A,$09,$08,$07,$05,$04,$0C,$0B,$0A,$09,$09
  .byte $08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09
  .byte $08,$07,$06,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$09,$08
  .byte $08,$08,$07,$07,$07,$06,$06,$0C,$0A,$08
WH_START:
  .byte $00,$01,$0A,$0E,$15,$42,$60,$6E,$73,$7F,$89,$B3,$CB,$F7
WH_LEN:
  .byte $00,$09,$04,$07,$2D,$1E,$0E,$05,$0C,$0A,$2A,$18,$2C,$03
W_HOP = 1
W_PAINT = 2
W_GOAL = 3
W_FALL = 4
W_SPRING = 5
W_LONG = 6
W_BLOT = 7
W_ITEM = 8
W_SQUASH = 9
W_CLEAR = 10
W_EXTRA = 11
W_OVER = 12
W_BONUS = 13

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$0C
  .byte $0A,$08,$06,$04,$02,$00,$00
EX_NP:
  .byte $00,$0C,$0D,$0E,$0F,$0C,$0D,$0E,$0F,$0C,$0D,$0E,$0F,$0C,$0D,$0E
  .byte $0F,$0C,$0D,$0E,$0F,$0C,$0D,$0E,$0F,$0C,$0D,$0E,$0F,$0C,$0D,$0E
  .byte $0F,$0C,$0D,$0E,$0F,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$04
  .byte $05,$06,$07,$08,$09,$0A,$0B
EX_VC:
  .byte $00,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07
  .byte $07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$B6,$1C,$E3,$F6,$5C,$59,$F5,$E3,$1E,$B1,$19,$E3,$F7,$60,$55
  .byte $F3,$E4,$21,$AC,$17,$E2,$F9,$64,$52,$F2,$E4,$23,$A7,$15,$E2,$FA
  .byte $68,$4E,$F1,$E5,$26,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$02,$02,$01,$01,$02,$02,$01,$01,$02,$02,$02,$01,$01,$02,$02
  .byte $01,$01,$02,$02,$02,$01,$01,$02,$02,$01,$01,$02,$02,$02,$01,$01
  .byte $02,$02,$01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$25,$2F
EX_LEN:
  .byte $00,$24,$0A,$08
S_GLOP = 1
S_RUMBLE = 2
S_SPLAT = 3
S_BIG = S_GLOP
S_SMALL = S_SPLAT
