;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   LIX  -  an original territory game                         ;
;   65C02 assembly, TMS9918A Graphics II as a bitmap           ;
;                                                              ;
;   - Flora the gardener runs along the hedges of a wild lawn  ;
;     and plants new hedge in the tall grass: when it meets    ;
;     the old hedge again, the part without the tornado        ;
;     becomes a flower bed                                     ;
;   - hold BUTTON 1 = fast hedge, BUTTON 2 = slow hedge (the   ;
;     bed is worth double); a lawn is done at 75%              ;
;   - the tornado roams the grass and pulls up the new hedge;  ;
;     the mad shears run along the hedges; standing still on   ;
;     a new hedge lets a caterpillar eat it up to Flora; when  ;
;     the timer runs out the shears turn red and follow the    ;
;     new hedge too                                            ;
;   - two tornadoes from lawn 3: splitting them gives a bonus  ;
;     and raises the points of the next lawns                  ;
;   - the lawn is a grid of 64 x 44 cells of 4 x 4 pixels; a   ;
;     row of 8 pixels covers two cells, so every cell has its  ;
;     own colour; four seasons in turn                         ;
;   - 3 lives, one more at 20000; 1 or 2 players taking turns  ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 50 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     a waltz at the title, tunes at every lawn; the hedge     ;
;     growing, the fill, the wind, the shears, the caterpillar ;
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
LEVEL       = $40      ; ---- block of the player, saved: lawn 0-98
XTRA        = $41      ;      1 = the extra life was given
MULT        = $42      ;      points x MULT (1-4): grows when the tornadoes are split
SEPAR       = $43      ;      1 = the tornadoes of this lawn are split
TWX         = $44      ;      2 bytes: the tornadoes, x of the centre (0-255)
TWY         = $46      ;      2 bytes: y of the centre (0-175)
GRL         = $48      ;      grass cells left (16 bits)
GRH         = $49
PBLOCK      = 10
GSTATE      = $50      ; 0 playing, 1 life lost, 3 the lawn is done
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 the lives, 4 the percent
FIRSTT      = $53      ; 1 = first turn of the game
FX          = $54      ; Flora: the cell (the one she is going to when she moves)
FY          = $55
FPX         = $56      ; the centre in pixels (x 0-255, y 0-175 from the top of the lawn)
FPY         = $57
FDIR        = $58      ; 0 up, 1 down, 2 left, 3 right
FSTEP       = $59      ; pixels left to the cell
FMODE       = $5A      ; 0 on the hedges, 1 planting
FSLOW       = $5B      ; 1 = only slow hedge so far
FACC        = $5C      ; fraction of the step (1/16 px)
FFACE       = $5D      ; 0 right, 1 left
FIDLE       = $5E      ; frames standing still while planting
SPRROT      = $5F      ; sprite order (more than 4 on a line take turns)
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
TRLEN       = $72      ; cells of the new hedge
TRSX        = $73      ; the cell of the hedge where Flora left it
TRSY        = $74
FUSEA       = $75      ; 1 = the caterpillar is eating
FUSEI       = $76      ; the cell of the new hedge it has reached
FUSET       = $77      ; frames to its next cell
TIMER       = $78      ; time left (units of 16 frames)
TIMET       = $79      ; frames of the unit
REDS        = $7A      ; 1 = the shears are red
NSH         = $7B      ; shears on the lawn
NTOR        = $7C      ; tornadoes (1-2)
PCT         = $7D      ; percent of the lawn tidy
LEVI        = $7E      ; lawn for the tables (0-7)
TICKS       = $7F
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
CELLR       = $86      ; text: row, column, colour (foreground << 4 | background)
CELLC       = $87
TCOL        = $88
JOYC        = $89      ; both joysticks drive the player playing
DEATHS      = $8A      ; what took the last life (tests): 1 tornado, 2 shears, 3 caterpillar
LOSTN       = $8B      ; lives lost (tests)
LAWNS       = $8C      ; lawns done (tests)
CAPS        = $8D      ; hedges closed (tests)
SPLITS      = $8E      ; tornadoes split (tests)
BARS        = $8F      ; timer bars shown
TVX         = $90      ; 2 bytes: speed of the tornadoes (signed)
TVY         = $92      ; 2 bytes
TCHG        = $94      ; 2 bytes: frames to the next change of course
TFRM        = $96      ; frame of the tornadoes
CUTL        = $97      ; cells tidied by the last fill (16 bits)
CUTH        = $98
FSP         = $99      ; fill: stack pointer
FCY         = $9A      ; fill: the row
WINDT       = $9B      ; frames to the next gust
BCD0        = $9C      ; 3 bytes: number to BCD
BIN0        = $9F      ; 2 bytes
CI          = $A1      ; shear / tornado being moved
NX          = $A2      ; a cell being tried
NY          = $A3
BESTD       = $A4      ; shears: best distance, best way
BESTW       = $A5
NCAND       = $A6
CANDS       = $A7      ; 4 bytes: candidate ways
TYV         = $AB      ; text: Y saved

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
OX         = $E0         ; sprite being added: centre x, centre y (lawn), pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4         ; sprites in OBUF

; ---------------- RAM ----------------
MAP        = $0200       ; 64 x 44 cells: 0 grass, 1 hedge, 2-3 new hedge, 4-5 bed, 6 blank, 7 mark
SAT_BUFFER = $0D00       ; 32 sprites x 4 + end of list
PSAVE      = $0D90       ; 2 x 16: block of every player
ROWD       = $0DB0       ; 22: tile rows 1-22 to draw again
WH_ID      = $0DC8       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0DCA       ; frames elapsed
EX_ID      = $0DCC       ; noise effect playing per chip (S_*)
EX_POS     = $0DCE
SMT0       = $0DD0       ; temporaries, main loop side
SMT1       = $0DD1
TR_PL      = $0DD4       ; music, 4 tracks: pointer (lo / hi), counter, active,
TR_PH      = $0DD8       ;                  note, volume, age of the note
TR_CT      = $0DDC
TR_ACT     = $0DE0
TR_NOTE    = $0DE4
TR_VOL     = $0DE8
TR_AGE     = $0DEC
SONG       = $0DF0       ; tune to play
CMD_GAME   = 1           ; silence + game effects
CMD_START  = 2           ; the tune SONG
TRX        = $0E00       ; the new hedge: cells (x, y), MAXTR at most
TRY        = $0F00
MAXTR      = 200
CPR0       = $6000       ; the cells of the season: patterns of the 4 texture rows
CPR1       = $6040
CPR2       = $6080
CPR3       = $60C0
CCR0       = $6100       ; and their colours
CCR1       = $6140
CCR2       = $6180
CCR3       = $61C0
SHX        = $6200       ; the shears (4): cell, centre in pixels, way, pixels to the cell, fraction
SHY        = $6204
SHPX       = $6208
SHPY       = $620C
SHD        = $6210
SHS        = $6214
SHA        = $6218
OBUF       = $6220       ; sprites of the frame, 4 bytes each (16)
LAWN0      = $6300       ; the lawn of player 1, 4 cells a byte (704)
LAWN1      = $6600       ; the lawn of player 2
FSX        = $6900       ; fill: stack of the cells to look at
FSY        = $6A00

; ---------------- parameters ----------------
BTN_MASK    = %00110000
ST_GRASS    = 0
ST_HEDGE    = 1
ST_TF       = 2          ; new hedge, fast
ST_TS       = 3          ; new hedge, slow
ST_BF       = 4          ; flower bed, fast
ST_BS       = 5          ; flower bed, slow
ST_BLANK    = 6
ST_MARK     = 7
GRASS0_L    = <2604      ; the grass of a new lawn: 62 x 42 cells
GRASS0_H    = >2604
SPD_EDGE    = 24         ; Flora: 1/16 px a frame on the hedges, planting fast, planting slow
SPD_FAST    = 24
SPD_SLOW    = 12
FUSE_WAIT   = 30         ; frames standing still before the caterpillar comes
FUSE_SPD    = 5          ; frames for every cell it eats
GOAL        = 75         ; percent of a lawn

; ---------------- records on the SD (lib_records.asm) ----------------
REC_BMP     = 1          ; a bitmap game: characters through REC_CHR
REC_ZONE    = 50         ; fixed zone of the game in the save area
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
  JSR CLEAR_VRAM
  JSR INIT_NAME_TABLE          ; every position its own pattern: a bitmap
  JSR LOAD_SPRITES
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  STZ DDRA_JOY
  STZ DDRB_JOY
  STZ FRAME_CNT
  STZ LAST_FRAME
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
;  TITLE: the logo, the rules, the records
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR DISPLAY_OFF
  STZ LEVEL                    ; the colours of spring
  JSR SEASON_LOAD
  JSR TITLE_MAP                ; the logo in the map, the rest blank
  JSR DRAW_LAWN
  LDA #0
  LDX #1
  JSR CLEAR_ROWS
  LDA #23
  LDX #1
  JSR CLEAR_ROWS
  JSR DRAW_TOP
  LDA #<TXT_BUTTONS
  STA TP
  LDA #>TXT_BUTTONS
  STA TP+1
  JSR PRINT
  JSR TITLE_PAGE
  JSR REC_TITLE
  JSR DISPLAY_ON
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

; one frame of the title: the sprites move;
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
  LDX #0                       ; the next frame of every sprite in turn
  LDY #0
.tf_s:
  LDA FRAME_CNT
  LSR A
  LSR A
  LSR A
  AND TITLE_SM,X
  ASL A
  ASL A
  PHA
  LDA TITLE_SA,X               ; 4 or 8 patterns from a frame to the next
  CMP #8
  PLA
  BCC .tf_4
  ASL A
.tf_4:
  CLC
  ADC TITLE_SN,X
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

; the map of the title: blank, with the logo on cell rows 2-13 (tile rows 2-7)
TITLE_MAP:
  LDA #ST_BLANK
  JSR MAP_FILL
  LDA #<LOGO
  STA PTR2
  LDA #>LOGO
  STA PTR2+1
  LDA #<(MAP+2*64)
  STA PTR
  LDA #>(MAP+2*64)
  STA PTR+1
  LDX #0                       ; 12 x 16 bytes, 4 cells each
.tm_b:
  STX T0
  LDA (PTR2)
  STA T1
  LDX #4
.tm_c:
  LDA T1
  ROL A
  ROL A
  ROL A
  AND #3
  TAY
  LDA LOGO_ST,Y
  STA (PTR)
  INC PTR
  BNE .tm_n
  INC PTR+1
.tm_n:
  ASL T1
  ASL T1
  DEX
  BNE .tm_c
  INC PTR2
  BNE .tm_k
  INC PTR2+1
.tm_k:
  LDX T0
  INX
  CPX #192
  BNE .tm_b
  RTS


; ===============================================================
;  NEW GAME: lawn 1, 3 lives for every player
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  DEX
  BPL .ng_p
  STZ LOSTN
  STZ LAWNS
  STZ CAPS
  STZ SPLITS
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ LEVEL
  STZ XTRA
  LDA #1
  STA MULT
  JSR NEW_LAWN
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his lawn as he left it
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  JSR FIND_START               ; Flora on the hedge nearest the bottom middle

LAWN_ENTER:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR DISPLAY_OFF
  JSR SET_LEVEL                ; the tables of the lawn
  JSR SEASON_LOAD
  JSR DRAW_LAWN
  JSR DRAW_HUD
  JSR MSG_LAWN
  JSR DISPLAY_ON
  JSR VDP_INT_ON
  LDA #1                       ; the tune of a lawn
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.le_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .le_t
  LDA FIRSTT
  BEQ .le_w
  STZ FIRSTT
  LDA #40
  JSR WAIT_FRAMES
.le_w:
  LDA #20
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  JSR VDP_INT_ON
  LDA #CMD_GAME
  STA SND_CMD

; ===============================================================
;  A LIFE: the timer, the shears at their place
; ===============================================================
LIFE_START:
  LDX #$FF
  TXS
  JSR LIFE_SETUP
  STZ GSTATE
  JSR VDP_INT_OFF              ; row 23 again (the timer is full)
  JSR DRAW_STATUS
  JSR VDP_INT_ON


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
  INC TICKS
  LDA GSTATE
  BNE .gl_ns
  JSR FLORA
  LDA GSTATE
  BNE .gl_ns
  JSR TWISTERS
  JSR SHEARS
  JSR FUSE
  JSR TIME_TICK
  JSR WIND
.gl_ns:
  JSR UPDATE_HUD
  JSR REDRAW_STEP              ; one tile row of the last fill
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  LDA GSTATE
  CMP #3
  BEQ .gl_done
  JMP LOSE_LIFE
.gl_done:
  JMP LAWN_DONE


; ===============================================================
;  THE LAWN IS DONE: the bonus, the tune, the next lawn
; ===============================================================
LAWN_DONE:
  INC LAWNS
  JSR VDP_INT_OFF              ; the last rows of the fill
.ld_r:
  JSR REDRAW_STEP
  BCS .ld_r
  JSR HIDE_SPRITES
  LDA PCT                      ; 1000 for every percent over 75
  SEC
  SBC #GOAL
  JSR BIN2BCD
  STA T0
  ASL A
  ASL A
  ASL A
  ASL A
  STA PTS_M
  LDA T0
  LSR A
  LSR A
  LSR A
  LSR A
  STA PTS_H
  STZ PTS_L
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR MSG_DONE
  JSR VDP_INT_ON
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
.ld_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ld_t
  LDA #40
  JSR WAIT_FRAMES
  LDA LEVEL
  CMP #98
  BCS .ld_n
  INC LEVEL
.ld_n:
  JSR NEW_LAWN
  JSR FIND_START
  JSR SAVE_PLAYER
  JMP LAWN_ENTER

LOSE_LIFE:
  INC LOSTN
  JSR VDP_INT_OFF
  JSR TRAIL_CLEAR              ; the new hedge is gone
.lz_r:
  JSR REDRAW_STEP
  BCS .lz_r
  JSR VDP_INT_ON
  LDX CURP
  DEC LIVES,X
  LDA #2
  TSB HUDD
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
  JMP LIFE_START               ; on the same lawn

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
  JSR PUT_CHAR
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
  LDA PS_OFF,X                 ; extra byte: the lawn reached
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

; hooks of lib_records.asm (bitmap)
REC_XY:                        ; X = row, Y = column
  STX CELLR
  STY CELLC
  RTS
REC_CHR:                       ; A = character: white, the cell moves on
  LDX #$F1
  STX TCOL
  JSR PUT_CHAR
  INC CELLC
  RTS
REC_CLRROWS = CLEAR_ROWS
REC_CLS:                       ; the sign screen: empty, with the scores on top
  LDA #1
  LDX #23
  JSR CLEAR_ROWS
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
REC_NAME:  .byte "LIX             "
REC_HEAD:  .byte "BEST GARDENERS",0
REC_XLBL:  .byte "LAWN ",0


; ===============================================================
;  HUD: row 0 (scores), row 23 (lives, lawn, percent, timer)
; ===============================================================
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDA #$B1
  STA TCOL
  STZ CELLR
  LDA #15
  STA CELLC
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
  STZ CELLR
  LDA SC_COLS,X
  STA CELLC
  LDA #$F1
  STA TCOL
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

; row 23: the spare lives (cols 0-4), LAWN nn (6-12), nn% (14-16), the timer (20-29), the player (31)
DRAW_STATUS:
  JSR DRAW_LIVES
  LDA #<TXT_LAWNH
  STA TP
  LDA #>TXT_LAWNH
  STA TP+1
  JSR PRINT
  LDA LEVEL
  INC A
  JSR PUT_NUM
  LDA #$20
  JSR PUT_CHAR
  JSR DRAW_PCT
  STZ BARS
  JSR DRAW_BAR
  LDA NPL                      ; the player at the right end with 2 players
  CMP #2
  BNE .ds_r
  LDA #31
  STA CELLC
  LDA #$F1
  STA TCOL
  LDA CURP
  CLC
  ADC #$31
  JMP PUT_CHAR
.ds_r:
  RTS

; the spare lives at columns 0-4 of row 23
DRAW_LIVES:
  LDA #23
  STA CELLR
  STZ CELLC
  LDA #$91
  STA TCOL
  LDX CURP                     ; the spare lives (at most 5)
  LDA LIVES,X
  BEQ .ds_z
  DEC A
.ds_z:
  STA T7
  LDY #0
.ds_i:
  LDA #$20
  CPY T7
  BCS .ds_w
  LDA #CH_LIFE
.ds_w:
  PHY
  JSR PUT_CHAR
  PLY
  INC CELLC
  INY
  CPY #5
  BNE .ds_i
  RTS

; nn% at columns 14-16
DRAW_PCT:
  LDA #23
  STA CELLR
  LDA #14
  STA CELLC
  LDA #$71
  STA TCOL
  LDA PCT
  JSR BIN2BCD
  CMP #$10
  BCS .dp_2
  PHA                          ; no leading zero
  LDA #$20
  JSR PUT_CHAR
  INC CELLC
  PLA
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  BRA .dp_p
.dp_2:
  JSR PUT_2
.dp_p:
  LDA #'%'
  JMP PUT_CHAR

; the timer: (TIMER + 23) / 24 bars at columns 20-29, red at 3 or less
DRAW_BAR:
  LDA TIMER
  CLC
  ADC #23
  LDX #0
.db_d:
  CMP #24
  BCC .db_n
  SBC #24
  INX
  BRA .db_d
.db_n:
  CPX BARS
  BEQ .db_r
  STX BARS
  LDA #23
  STA CELLR
  LDA #20
  STA CELLC
  LDA #$31
  CPX #4
  BCS .db_c
  LDA #$81
.db_c:
  STA TCOL
  LDY #0
.db_l:
  LDA #$20
  CPY BARS
  BCS .db_w
  LDA #CH_BAR
.db_w:
  PHY
  JSR PUT_CHAR
  PLY
  INC CELLC
  INY
  CPY #10
  BNE .db_l
.db_r:
  RTS

; A = 1-99: the number in the cell (no leading zero), the cell moves on
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
  JSR PUT_CHAR
  INC CELLC
  PLA
  AND #$0F
.pn_1:
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  RTS

DRAW_HUD:
  LDA #0
  LDX #1
  JSR CLEAR_ROWS
  LDA #23
  LDX #1
  JSR CLEAR_ROWS
  JSR DRAW_TOP
  JMP DRAW_STATUS

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 the lives, 4 the percent
  LDA HUDD
  BEQ .uh_t
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
  BEQ .uh_p
  JSR DRAW_LIVES
.uh_p:
  PLA
  AND #4
  BEQ .uh_t
  JSR DRAW_PCT
.uh_t:
  JMP DRAW_BAR                 ; only when the bars change

; messages in the middle of the lawn: rows 10 and 12 (MSG_CLEAR draws the lawn again there)
MSG_LAWN:
  LDA NPL
  CMP #2
  BNE .ml_l
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  JSR PUT_CHAR
.ml_l:
  LDA #<TXT_LAWNM
  STA TP
  LDA #>TXT_LAWNM
  STA TP+1
  JSR PRINT
  LDA LEVEL
  INC A
  JSR PUT_NUM
  INC CELLC
  LDA LEVEL
  AND #3
  TAX
  LDA SEAN_LO,X
  STA PTR2
  LDA SEAN_HI,X
  STA PTR2+1
  LDY #0
.ml_s:
  LDA (PTR2),Y
  BEQ .ml_e
  PHY
  JSR PUT_CHAR
  PLY
  INC CELLC
  INY
  BRA .ml_s
.ml_e:
  RTS

MSG_DONE:
  LDA #<TXT_DONE
  STA TP
  LDA #>TXT_DONE
  STA TP+1
  JMP PRINT

MSG_CLEAR:
  LDY #10
  JSR DRAW_ROW
  LDY #12
  JMP DRAW_ROW


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: his block and his lawn
  LDX CURP
  LDA PS_OFF,X
  TAX
  LDY #0
.sp_b:
  LDA LEVEL,Y
  STA PSAVE,X
  INX
  INY
  CPY #PBLOCK
  BNE .sp_b
  JMP SAVE_LAWN

LOAD_PLAYER:                   ; X = player
  LDA PS_OFF,X
  TAX
  LDY #0
.lp_b:
  LDA PSAVE,X
  STA LEVEL,Y
  INX
  INY
  CPY #PBLOCK
  BNE .lp_b
  JMP LOAD_LAWN

; the tables of the lawn LEVEL
SET_LEVEL:
  LDA LEVEL
  CMP #7
  BCC .sl_l
  LDA #7
.sl_l:
  STA LEVI
  LDX #1
  LDA LEVEL
  CMP #2
  BCC .sl_t
  INX
.sl_t:
  STX NTOR
  LDX LEVI
  LDA SH_N,X
  STA NSH
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 20000
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
  CMP #$02
  BCC .as_d
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

; BIN0 (16 bits) -> BCD0 (3 bytes BCD, low first)
BIN2BCD16:
  STZ BCD0
  STZ BCD0+1
  STZ BCD0+2
  LDX #16
  SED
.b16_l:
  ASL BIN0
  ROL BIN0+1
  LDA BCD0
  ADC BCD0
  STA BCD0
  LDA BCD0+1
  ADC BCD0+1
  STA BCD0+1
  LDA BCD0+2
  ADC BCD0+2
  STA BCD0+2
  DEX
  BNE .b16_l
  CLD
  RTS


; ===============================================================
;  TEXT ON THE BITMAP: every character writes the 8 pattern bytes
;  and the 8 colour bytes of its position
; ===============================================================
FPTR        = $AC      ; 2 bytes: the glyph
CLO         = $AE      ; low byte of the VRAM address of the cell

; A = character ($20-$5F, or $60- from FONTX) in (CELLR, CELLC) with the colour TCOL; keeps X
PUT_CHAR:
  CMP #$60
  BCS .pc_x
  SEC
  SBC #$20
  LDY #<FONT
  STY FPTR
  LDY #>FONT
  BRA .pc_a
.pc_x:
  SBC #$60
  LDY #<FONTX
  STY FPTR
  LDY #>FONTX
.pc_a:
  STY FPTR+1
  STZ T6
  ASL A
  ROL T6
  ASL A
  ROL T6
  ASL A
  ROL T6
  CLC
  ADC FPTR
  STA FPTR
  LDA T6
  ADC FPTR+1
  STA FPTR+1
  LDA CELLC
  ASL A
  ASL A
  ASL A
  STA CLO
  STA VREG
  LDA CELLR
  ORA #$40
  STA VREG
  LDY #0
.pc_p:
  LDA (FPTR),Y
  STA VDATA
  INY
  CPY #8
  BNE .pc_p
  LDA CLO
  STA VREG
  LDA CELLR
  ORA #$60
  STA VREG
  LDA TCOL
  LDY #8
.pc_c:
  STA VDATA
  NOP
  NOP
  DEY
  BNE .pc_c
  RTS

; A = BCD byte: two digits, the cell moves on by 2
PUT_2:
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  PLA
  AND #$0F
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  RTS

; text records at TP: row, column, colour, characters..., 0   (end: row = $FF);
; the cell is left after the last character
PRINT:
  LDY #$00
  LDA (TP),Y
  CMP #$FF
  BEQ .pr_e
  STA CELLR
  INY
  LDA (TP),Y
  STA CELLC
  INY
  LDA (TP),Y
  STA TCOL
.pr_c:
  INY
  LDA (TP),Y
  BEQ .pr_n
  STY TYV
  JSR PUT_CHAR
  LDY TYV
  INC CELLC
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

; A = first row, X = rows: patterns blank, colours black
CLEAR_ROWS:
  STA T0
  STX T1
  STZ VREG
  ORA #$40
  STA VREG
  LDA #0
.cr_p:
  LDY #0
.cr_pb:
  STA VDATA
  NOP
  NOP
  INY
  BNE .cr_pb
  DEX
  BNE .cr_p
  STZ VREG
  LDA T0
  ORA #$60
  STA VREG
  LDX T1
  LDA #$11
.cr_c:
  LDY #0
.cr_cb:
  STA VDATA
  NOP
  NOP
  INY
  BNE .cr_cb
  DEX
  BNE .cr_c
  RTS

; name table: tile = position (0-255 in each of the 3 thirds) => full bitmap
INIT_NAME_TABLE:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDX #$03
.in_p:
  LDY #$00
.in_b:
  TYA
  STA VDATA
  NOP
  INY
  BNE .in_b
  DEX
  BNE .in_p
  RTS

DISPLAY_OFF:                   ; R1: 16K, display off, interrupt off
  LDA #$86
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

DISPLAY_ON:                    ; R1: 16K, display on, interrupt off
  LDA #$C6
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS


; ===============================================================
;  CELLS: the map MAP (64 x 44) and its tiles
; ===============================================================
; X = column, Y = row: A = the cell (blank outside the lawn); PTR = the row, Y = the column
GETC:
  CPX #64
  BCS .gc_o
  CPY #44
  BCS .gc_o
  LDA MROW_LO,Y
  STA PTR
  LDA MROW_HI,Y
  STA PTR+1
  TXA
  TAY
  LDA (PTR),Y
  RTS
.gc_o:
  LDA #ST_BLANK
  RTS

; X = column, Y = row, A = the new state
SETC:
  PHA
  LDA MROW_LO,Y
  STA PTR
  LDA MROW_HI,Y
  STA PTR+1
  TXA
  TAY
  PLA
  STA (PTR),Y
  RTS

; Y = cell row: its tile row is drawn again by REDRAW_STEP
MARK_ROW:
  TYA
  LSR A
  TAY
  LDA #1
  STA ROWD,Y
  RTS

; X = column, Y = row of a cell: its tile now (VDP free)
DRAW_CELL:
  TXA
  LSR A
  TAX
  TYA
  LSR A
  INC A
  TAY
  ; fall into DRAW_TILE

; X = tile column (0-31), Y = tile row (1-22): 8 pattern and 8 colour bytes from the 4 cells
DRAW_TILE:
  STX T0
  STY T2
  TXA
  ASL A
  ASL A
  ASL A
  STA T1                       ; low byte of the VRAM address
  STA VREG
  TYA
  ORA #$40
  STA VREG
  LDA TROW_LO,Y
  STA PTR
  LDA TROW_HI,Y
  STA PTR+1
  LDA T0
  ASL A
  TAY
  LDA (PTR),Y                  ; the top pair
  ASL A
  ASL A
  ASL A
  INY
  ORA (PTR),Y
  TAX
  TYA
  CLC
  ADC #63
  TAY
  LDA (PTR),Y                  ; the bottom pair
  ASL A
  ASL A
  ASL A
  INY
  ORA (PTR),Y
  TAY
  LDA CPR0,X
  STA VDATA
  LDA CPR1,X
  STA VDATA
  LDA CPR2,X
  STA VDATA
  LDA CPR3,X
  STA VDATA
  LDA CPR0,Y
  STA VDATA
  LDA CPR1,Y
  STA VDATA
  LDA CPR2,Y
  STA VDATA
  LDA CPR3,Y
  STA VDATA
  LDA T1
  STA VREG
  LDA T2
  ORA #$60
  STA VREG
  LDA CCR0,X
  STA VDATA
  LDA CCR1,X
  STA VDATA
  LDA CCR2,X
  STA VDATA
  LDA CCR3,X
  STA VDATA
  LDA CCR0,Y
  STA VDATA
  LDA CCR1,Y
  STA VDATA
  LDA CCR2,Y
  STA VDATA
  LDA CCR3,Y
  STA VDATA
  LDX T0
  LDY T2
  RTS

; Y = tile row (1-22): the 32 tiles
DRAW_ROW:
  LDX #0
.dr_l:
  JSR DRAW_TILE
  INX
  CPX #32
  BNE .dr_l
  RTS

; the whole lawn (rows 1-22), nothing left to draw again
DRAW_LAWN:
  LDY #1
.dl_l:
  JSR DRAW_ROW
  INY
  CPY #23
  BNE .dl_l
  LDX #21
.dl_c:
  STZ ROWD,X
  DEX
  BPL .dl_c
  RTS

; the first tile row waiting (C = 1 if one was drawn)
REDRAW_STEP:
  LDX #0
.rs_l:
  LDA ROWD,X
  BNE .rs_d
  INX
  CPX #22
  BNE .rs_l
  CLC
  RTS
.rs_d:
  STZ ROWD,X
  INX
  TXA
  TAY
  JSR DRAW_ROW
  SEC
  RTS

; A = state: the whole map
MAP_FILL:
  LDX #<MAP
  STX PTR
  LDX #>MAP
  STX PTR+1
  LDX #11                      ; 11 pages: $0200-$0CFF
.mf_p:
  LDY #0
.mf_b:
  STA (PTR),Y
  INY
  BNE .mf_b
  INC PTR+1
  DEX
  BNE .mf_p
  RTS

; X = column, Y = row: C = 1 if a cell around (8 neighbours) is grass
IS_EDGE:
  STX NX
  STY NY
  LDA #$FF
  STA T4
.ie_y:
  LDA #$FF
  STA T5
.ie_x:
  LDA NX
  CLC
  ADC T5
  TAX
  LDA NY
  CLC
  ADC T4
  TAY
  JSR GETC
  BEQ .ie_yes
  INC T5
  LDA T5
  CMP #2
  BNE .ie_x
  INC T4
  LDA T4
  CMP #2
  BNE .ie_y
  LDX NX
  LDY NY
  CLC
  RTS
.ie_yes:
  LDX NX
  LDY NY
  SEC
  RTS


; ===============================================================
;  THE LAWN
; ===============================================================
; a new lawn: grass inside a hedge, the tornadoes in the middle
NEW_LAWN:
  LDA #ST_GRASS
  JSR MAP_FILL
  LDY #63
  LDA #ST_HEDGE
.nl_h:
  STA MAP,Y                    ; row 0
  STA MAP+43*64,Y              ; row 43
  DEY
  BPL .nl_h
  LDY #43
.nl_v:
  LDX #0
  LDA #ST_HEDGE
  PHY
  JSR SETC
  PLY
  LDX #63
  LDA #ST_HEDGE
  PHY
  JSR SETC
  PLY
  DEY
  BPL .nl_v
  LDA #GRASS0_L
  STA GRL
  LDA #GRASS0_H
  STA GRH
  STZ SEPAR
  STZ PCT
  LDA #128
  STA TWX
  LDA #88
  STA TWY
  STA TWY+1
  LDA LEVEL
  CMP #2
  BCC .nl_e
  LDA #80                      ; two tornadoes
  STA TWX
  LDA #176
  STA TWX+1
.nl_e:
  RTS

; the cells of the season LEVEL & 3 into RAM (patterns and colours, 512 bytes)
SEASON_LOAD:
  LDA LEVEL
  AND #3
  TAX
  LDA SEA_LO,X
  STA PTR
  LDA SEA_HI,X
  STA PTR+1
  LDA #<CPR0
  STA PTR2
  LDA #>CPR0
  STA PTR2+1
  LDX #2
.sl_p:
  LDY #0
.sl_b:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  BNE .sl_b
  INC PTR+1
  INC PTR2+1
  DEX
  BNE .sl_p
  RTS

; the map of the player CURP into LAWN0 / LAWN1, 4 cells a byte (the new hedge is grass)
SAVE_LAWN:
  LDX CURP
  LDA LW_LO,X
  STA PTR2
  LDA LW_HI,X
  STA PTR2+1
  LDA #<MAP
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDA #<704
  STA T2
  LDA #>704
  STA T3
.sv_b:
  STZ T0
  LDX #4
.sv_c:
  LDA (PTR)
  TAY
  LDA ENC_ST,Y
  ASL T0
  ASL T0
  ORA T0
  STA T0
  INC PTR
  BNE .sv_n
  INC PTR+1
.sv_n:
  DEX
  BNE .sv_c
  LDA T0
  STA (PTR2)
  INC PTR2
  BNE .sv_k
  INC PTR2+1
.sv_k:
  LDA T2
  BNE .sv_d
  DEC T3
.sv_d:
  DEC T2
  LDA T2
  ORA T3
  BNE .sv_b
  RTS

; the map of the player CURP back from LAWN0 / LAWN1
LOAD_LAWN:
  LDX CURP
  LDA LW_LO,X
  STA PTR2
  LDA LW_HI,X
  STA PTR2+1
  LDA #<MAP
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDA #<704
  STA T2
  LDA #>704
  STA T3
.lw_b:
  LDA (PTR2)
  STA T0
  LDX #4
.lw_c:
  LDA T0
  ROL A
  ROL A
  ROL A
  AND #3
  TAY
  LDA DEC_ST,Y
  STA (PTR)
  INC PTR
  BNE .lw_n
  INC PTR+1
.lw_n:
  ASL T0
  ASL T0
  DEX
  BNE .lw_c
  INC PTR2
  BNE .lw_k
  INC PTR2+1
.lw_k:
  LDA T2
  BNE .lw_d
  DEC T3
.lw_d:
  DEC T2
  LDA T2
  ORA T3
  BNE .lw_b
  RTS

; Flora on the hedge by the grass nearest the middle of the lowest row that has one
FIND_START:
  LDA #43
  STA FY
.fs_r:
  STZ T7                       ; distance from the middle
.fs_d:
  LDA #32
  CLC
  ADC T7
  CMP #64
  BCS .fs_m
  JSR .fs_try
  BCS .fs_ok
.fs_m:
  LDA #31
  SEC
  SBC T7
  BCC .fs_n
  JSR .fs_try
  BCS .fs_ok
.fs_n:
  INC T7
  LDA T7
  CMP #33
  BNE .fs_d
  DEC FY
  BPL .fs_r
  STZ FX                       ; (no hedge by the grass: cannot happen)
  STZ FY
.fs_ok:
  STZ FSTEP
  STZ FMODE
  STZ TRLEN
  JMP F_PIXELS
.fs_try:                       ; A = column: C = 1 if Flora can stand there
  STA FX
  TAX
  LDY FY
  JSR GETC
  CMP #ST_HEDGE
  BNE .ft_no
  LDX FX
  LDY FY
  JMP IS_EDGE
.ft_no:
  CLC
  RTS

; Flora's pixels from her cell
F_PIXELS:
  LDA FX
  ASL A
  ASL A
  ORA #2
  STA FPX
  LDA FY
  ASL A
  ASL A
  ORA #2
  STA FPY
  RTS

; the timer, the shears at their place, Flora still
LIFE_SETUP:
  LDX LEVI
  LDA TIME0,X
  STA TIMER
  LDA #16
  STA TIMET
  STZ REDS
  STZ FUSEA
  STZ FIDLE
  STZ FSTEP
  STZ FACC
  STZ FMODE
  STZ TRLEN
  LDA #1
  STA TCHG
  STA TCHG+1
  LDA #40
  STA WINDT
  JSR F_PIXELS
  LDY #0                       ; the shears on the border row far from Flora
  LDA FY
  CMP #22
  BCS .ls_t
  LDY #43
.ls_t:
  STY T0
  LDX #3
.ls_s:
  LDA SH_X0,X
  STA SHX,X
  ASL A
  ASL A
  ORA #2
  STA SHPX,X
  LDA T0
  STA SHY,X
  ASL A
  ASL A
  ORA #2
  STA SHPY,X
  LDA SH_D0,X
  STA SHD,X
  STZ SHS,X
  STZ SHA,X
  DEX
  BPL .ls_s
  RTS

; the new hedge is gone (a life lost): grass again, Flora back where she left the hedge
TRAIL_CLEAR:
  LDA TRLEN
  BEQ .tc_f
  LDX #0
.tc_l:
  PHX
  LDA TRY,X
  TAY
  LDA TRX,X
  TAX
  LDA #ST_GRASS
  PHY
  JSR SETC
  PLY
  JSR MARK_ROW
  PLX
  INX
  CPX TRLEN
  BNE .tc_l
  STZ TRLEN
.tc_f:
  LDA FMODE
  BEQ .tc_r
  LDA TRSX
  STA FX
  LDA TRSY
  STA FY
  STZ FMODE
.tc_r:
  STZ FSTEP
  JMP F_PIXELS


; ===============================================================
;  FLORA
; ===============================================================
FLORA:
  LDA FSTEP
  BNE .fl_mv
  JSR F_DECIDE
  LDA FSTEP
  BNE .fl_mv
  LDA FMODE                    ; standing still while planting
  BEQ .fl_r
  LDA FIDLE
  CMP #$FF
  BEQ .fl_r
  INC FIDLE
.fl_r:
  RTS
.fl_mv:
  STZ FIDLE
  LDA #SPD_EDGE
  LDX FMODE
  BEQ .fl_s
  LDA JOYC
  AND #$10
  BEQ .fl_sl
  LDA #SPD_FAST
  BRA .fl_s
.fl_sl:
  LDA #SPD_SLOW
.fl_s:
  CLC
  ADC FACC
  PHA
  AND #15
  STA FACC
  PLA
  LSR A
  LSR A
  LSR A
  LSR A
  TAX
  BEQ .fl_r
.fl_px:
  LDY FDIR
  LDA FPX
  CLC
  ADC DXT,Y
  STA FPX
  LDA FPY
  CLC
  ADC DYT,Y
  STA FPY
  DEC FSTEP
  BEQ F_ARRIVE
  DEX
  BNE .fl_px
  RTS

; Flora is on her new cell: a hedge closes the new hedge
F_ARRIVE:
  LDA FMODE
  BEQ .fa_r
  LDX FX
  LDY FY
  JSR GETC
  CMP #ST_HEDGE
  BNE .fa_r
  JMP CLOSE
.fa_r:
  RTS

; at a cell: the way of the joystick (the old one first) that she can take
F_DECIDE:
  LDA JOYC
  AND #$0F
  BEQ .fd_r
  STA T6
  LDA FMODE                    ; planting needs a button held
  BEQ .fd_1
  LDA JOYC
  AND #$30
  BEQ .fd_r
.fd_1:
  LDX FDIR
  LDA BITS,X
  AND T6
  BEQ .fd_o
  JSR F_TRY
  BCS .fd_r
.fd_o:
  LDX #0
.fd_l:
  CPX FDIR
  BEQ .fd_n
  LDA BITS,X
  AND T6
  BEQ .fd_n
  PHX
  JSR F_TRY
  PLX
  BCS .fd_r
.fd_n:
  INX
  CPX #4
  BNE .fd_l
.fd_r:
  RTS

; X = way: C = 1 if Flora takes it
F_TRY:
  STX T7
  LDA FX
  CLC
  ADC DXT,X
  STA NX
  LDA FY
  CLC
  ADC DYT,X
  STA NY
  LDX NX
  LDY NY
  JSR GETC
  STA T3
  LDA FMODE
  BNE .tr_p
  LDA T3                       ; on the hedges: another hedge by the grass...
  CMP #ST_HEDGE
  BNE .tr_g
  LDX NX
  LDY NY
  JSR IS_EDGE
  BCC .tr_no
  BRA .tr_go
.tr_g:
  CMP #ST_GRASS                ; ...or into the grass with a button: planting
  BNE .tr_no
  LDA JOYC
  AND #$30
  BEQ .tr_no
  JSR TRAIL_OK
  BCC .tr_no
  LDA FX
  STA TRSX
  LDA FY
  STA TRSY
  STZ TRLEN
  STZ FUSEA
  STZ FIDLE
  LDA #1
  STA FMODE
  STA FSLOW
  JSR ADD_TRAIL
  BRA .tr_go
.tr_p:
  LDA T3                       ; planting: the hedge closes it, the grass goes on
  CMP #ST_HEDGE
  BEQ .tr_go
  CMP #ST_GRASS
  BNE .tr_no
  LDA TRLEN
  CMP #MAXTR
  BCS .tr_no
  JSR TRAIL_OK
  BCC .tr_no
  JSR ADD_TRAIL
.tr_go:
  LDX T7
  STX FDIR
  LDA NX
  STA FX
  LDA NY
  STA FY
  LDA #4
  STA FSTEP
  CPX #2
  BCC .tr_f
  TXA
  AND #1
  EOR #1
  STA FFACE
.tr_f:
  SEC
  RTS
.tr_no:
  CLC
  RTS

; (NX, NY): C = 1 if no new hedge touches it, but the cell of Flora
TRAIL_OK:
  LDX #3
.to_l:
  STX T5
  LDA NX
  CLC
  ADC DXT,X
  STA T0
  LDA NY
  CLC
  ADC DYT,X
  STA T1
  LDA T0
  CMP FX
  BNE .to_c
  LDA T1
  CMP FY
  BEQ .to_n
.to_c:
  LDX T0
  LDY T1
  JSR GETC
  CMP #ST_TF
  BEQ .to_no
  CMP #ST_TS
  BEQ .to_no
.to_n:
  LDX T5
  DEX
  BPL .to_l
  SEC
  RTS
.to_no:
  CLC
  RTS

; (NX, NY) becomes new hedge: fast with button 1, slow with button 2 only
ADD_TRAIL:
  LDA JOYC
  AND #$10
  BEQ .at_s
  STZ FSLOW
  LDA #ST_TF
  BRA .at_w
.at_s:
  LDA #ST_TS
.at_w:
  LDX NX
  LDY NY
  JSR SETC
  LDY TRLEN
  LDA NX
  STA TRX,Y
  LDA NY
  STA TRY,Y
  INC TRLEN
  LDX NX
  LDY NY
  JSR DRAW_CELL
  LDA FSLOW
  BEQ .at_f
  LDA #W_SLOW
  BRA .at_p
.at_f:
  LDA #W_FAST
.at_p:
  LDX #0
  LDY FPX
  BPL .at_l
  INX
.at_l:
  JMP SFX_WHISTLE


; ===============================================================
;  THE NEW HEDGE MEETS THE OLD ONE: it becomes hedge, the grass
;  without a tornado becomes a flower bed
; ===============================================================
CLOSE:
  INC CAPS
  STZ FMODE
  STZ FUSEA
  STZ FIDLE
  LDX #0                       ; the new hedge becomes hedge
.cl_t:
  PHX
  LDA TRY,X
  TAY
  LDA TRX,X
  TAX
  LDA #ST_HEDGE
  PHY
  JSR SETC
  PLY
  JSR MARK_ROW
  PLX
  INX
  CPX TRLEN
  BNE .cl_t
  JSR VDP_INT_ON               ; a long job: the music goes on
  LDX #0                       ; the grass of the tornadoes is marked
  JSR FLOOD_TW
  LDA NTOR
  CMP #2
  BNE .cl_c
  LDA TWX+1                    ; the second one: in the same grass?
  LSR A
  LSR A
  TAX
  LDA TWY+1
  LSR A
  LSR A
  TAY
  JSR GETC
  CMP #ST_MARK
  BEQ .cl_c
  LDX #1
  JSR FLOOD_TW
  LDA SEPAR                    ; split: a bonus, the next lawns are worth more
  BNE .cl_c
  INC SEPAR
  INC SPLITS
  LDA MULT
  CMP #4
  BCS .cl_b
  INC MULT
.cl_b:
  LDA #$00
  LDY #$50
  JSR ADD_PTS
  LDA #W_SPLIT
  LDX #2
  JSR SFX_WHISTLE
.cl_c:
  JSR CONVERT
  JSR F_RESCUE                 ; no grass by Flora any more: to the nearest hedge that has some
  JSR VDP_INT_OFF
  LDA CUTL                     ; the cells: the beds and the new hedge
  CLC
  ADC TRLEN
  STA BIN0
  LDA CUTH
  ADC #0
  STA BIN0+1
  LDA BIN0                     ; x 5
  STA T0
  LDA BIN0+1
  STA T1
  ASL BIN0
  ROL BIN0+1
  ASL BIN0
  ROL BIN0+1
  LDA BIN0
  CLC
  ADC T0
  STA BIN0
  LDA BIN0+1
  ADC T1
  STA BIN0+1
  LDA FSLOW                    ; x 2 for the slow hedge
  BEQ .cl_p
  ASL BIN0
  ROL BIN0+1
.cl_p:
  JSR BIN2BCD16
  LDX MULT
.cl_m:
  LDA BCD0
  STA PTS_L
  LDA BCD0+1
  STA PTS_M
  LDA BCD0+2
  STA PTS_H
  PHX
  JSR ADD_SCORE
  PLX
  DEX
  BNE .cl_m
  STZ TRLEN
  JSR CALC_PCT
  LDA #4
  TSB HUDD
  LDA #W_FILL
  LDX #2
  JSR SFX_WHISTLE
  LDA PCT
  CMP #GOAL
  BCC .cl_r
  LDA #3
  STA GSTATE
  LDA #40
  STA GT
.cl_r:
  RTS

; Flora on a hedge with no grass around (a fill took both sides): she goes to the nearest hedge by
; the grass, looking on squares of growing size round her cell
F_RESCUE:
  LDX FX
  LDY FY
  JSR IS_EDGE
  BCS .fr_r
  LDA #1
  STA T7
.fr_g:
  LDA FY
  SEC
  SBC T7
  STA T1
  STA CANDS                    ; first row and column of the square
  LDA FY
  CLC
  ADC T7
  STA T3
  LDA FX
  SEC
  SBC T7
  STA CANDS+1
  LDA FX
  CLC
  ADC T7
  STA T2
.fr_y:
  LDA CANDS+1
  STA T0
.fr_x:
  LDA T1                       ; only the border of the square
  CMP CANDS
  BEQ .fr_t
  CMP T3
  BEQ .fr_t
  LDA T0
  CMP CANDS+1
  BEQ .fr_t
  CMP T2
  BNE .fr_n
.fr_t:
  LDX T0
  LDY T1
  JSR GETC
  CMP #ST_HEDGE
  BNE .fr_n
  LDX T0
  LDY T1
  JSR IS_EDGE
  BCS .fr_f
.fr_n:
  LDA T0
  CMP T2
  BEQ .fr_ny
  INC T0
  BRA .fr_x
.fr_ny:
  LDA T1
  CMP T3
  BEQ .fr_nr
  INC T1
  BRA .fr_y
.fr_nr:
  INC T7
  LDA T7
  CMP #64
  BNE .fr_g
.fr_r:
  RTS
.fr_f:
  STX FX
  STY FY
  JMP F_PIXELS

; X = tornado: its grass is marked
FLOOD_TW:
  LDA TWX,X
  LSR A
  LSR A
  PHA
  LDA TWY,X
  LSR A
  LSR A
  TAY
  PLX
  ; fall into FLOOD

; X = column, Y = row: the grass joined to the cell becomes ST_MARK (lines of a row at a time)
FLOOD:
  STX FSX
  STY FSY
  LDA #1
  STA FSP
.f_pop:
  LDX FSP
  BEQ .f_end
  DEX
  STX FSP
  LDA FSY,X
  STA FCY
  TAY
  LDA FSX,X
  TAX
  JSR GETC
  BNE .f_pop
.f_l:                          ; to the left end of the grass
  DEY
  LDA (PTR),Y
  BEQ .f_l
  INY
  STY T0
.f_r:                          ; marked to the right end
  LDA (PTR),Y
  BNE .f_re
  LDA #ST_MARK
  STA (PTR),Y
  INY
  BRA .f_r
.f_re:
  STY T1
  LDY FCY
  DEY
  JSR F_SCAN
  LDY FCY
  INY
  JSR F_SCAN
  BRA .f_pop
.f_end:
  RTS

; Y = row: the start of every piece of grass between columns T0 and T1-1 goes on the stack
F_SCAN:
  STY T2
  LDA MROW_LO,Y
  STA PTR2
  LDA MROW_HI,Y
  STA PTR2+1
  LDY T0
.fs_l:                         ; no grass: on
  LDA (PTR2),Y
  BEQ .fs_g
  INY
  CPY T1
  BCC .fs_l
  RTS
.fs_g:                         ; a piece of grass: its start on the stack, then past it
  LDX FSP
  CPX #$FF
  BEQ .fs_s
  TYA
  STA FSX,X
  LDA T2
  STA FSY,X
  INC FSP
.fs_s:
  INY
  CPY T1
  BCS .fs_r
  LDA (PTR2),Y
  BEQ .fs_s
  BRA .fs_l
.fs_r:
  RTS

; the grass left is a bed, the marked grass is grass again; counts both
CONVERT:
  STZ GRL
  STZ GRH
  STZ CUTL
  STZ CUTH
  LDA #ST_BF
  LDX FSLOW
  BEQ .cv_s
  LDA #ST_BS
.cv_s:
  STA T4
  LDY #1
.cv_r:
  STY FCY
  LDA MROW_LO,Y
  STA PTR
  LDA MROW_HI,Y
  STA PTR+1
  STZ T3
  LDY #62
.cv_c:
  LDA (PTR),Y
  BEQ .cv_g
  CMP #ST_MARK
  BNE .cv_n
  LDA #ST_GRASS
  STA (PTR),Y
  INC GRL
  BNE .cv_n
  INC GRH
  BRA .cv_n
.cv_g:
  LDA T4
  STA (PTR),Y
  INC T3
  INC CUTL
  BNE .cv_n
  INC CUTH
.cv_n:
  DEY
  BNE .cv_c
  LDA T3
  BEQ .cv_x
  LDA FCY
  LSR A
  TAX
  LDA #1
  STA ROWD,X
.cv_x:
  LDY FCY
  INY
  CPY #43
  BNE .cv_r
  RTS

; PCT = (2604 - grass) x 5 / 130
CALC_PCT:
  SEC
  LDA #GRASS0_L
  SBC GRL
  STA T0
  LDA #GRASS0_H
  SBC GRH
  STA T1
  LDA T0
  STA T2
  LDA T1
  STA T3
  ASL T0
  ROL T1
  ASL T0
  ROL T1
  LDA T0
  CLC
  ADC T2
  STA T0
  LDA T1
  ADC T3
  STA T1
  LDX #0
.cp_l:
  SEC
  LDA T0
  SBC #130
  TAY
  LDA T1
  SBC #0
  BCC .cp_e
  STA T1
  STY T0
  INX
  BRA .cp_l
.cp_e:
  CPX #100
  BCC .cp_s
  LDX #99
.cp_s:
  STX PCT
  RTS


; ===============================================================
;  THE TORNADOES: they roam the grass and bounce on the hedges
; ===============================================================
TWISTERS:
  LDX #0
.tw_l:
  STX CI
  JSR TW_ONE
  LDA GSTATE
  BNE .tw_r
  LDX CI
  INX
  CPX NTOR
  BNE .tw_l
.tw_r:
  RTS

TW_ONE:
  DEC TCHG,X
  BNE .to_m
  JSR NEXT_RND                 ; a new course every 12-43 frames
  AND #31
  CLC
  ADC #12
  STA TCHG,X
  JSR TW_VEL
  STA TVX,X
  JSR TW_VEL
  STA TVY,X
  ORA TVX,X
  BNE .to_m
  LDA #1
  STA TVX,X
.to_m:
  LDA TVX,X
  BEQ .to_y
  CLC
  ADC TWX,X
  STA T0
  LDA TWY,X
  STA T1
  JSR TW_BOX
  CMP #2
  BEQ .to_d
  CMP #1
  BEQ .to_bx
  LDA T0
  STA TWX,X
  BRA .to_y
.to_bx:
  LDA TVX,X
  EOR #$FF
  INC A
  STA TVX,X
.to_y:
  LDA TVY,X
  BEQ .to_f
  CLC
  ADC TWY,X
  STA T1
  LDA TWX,X
  STA T0
  JSR TW_BOX
  CMP #2
  BEQ .to_d
  CMP #1
  BEQ .to_by
  LDA T1
  STA TWY,X
  BRA .to_f
.to_by:
  LDA TVY,X
  EOR #$FF
  INC A
  STA TVY,X
.to_f:
  LDA FMODE                    ; Flora in the grass, too near
  BEQ .to_r
  LDA TWX,X
  SEC
  SBC FPX
  BCS .to_a
  EOR #$FF
  INC A
.to_a:
  CMP #7
  BCS .to_r
  LDA TWY,X
  SEC
  SBC FPY
  BCS .to_b
  EOR #$FF
  INC A
.to_b:
  CMP #7
  BCS .to_r
.to_d:
  LDA #1
  JMP DIE
.to_r:
  RTS

; A = a random speed of the lawn (keeps X)
TW_VEL:
  JSR NEXT_RND
  AND #7
  LDY LEVI
  ORA TW_SPD,Y                 ; 0 or 8: the second half is faster
  TAY
  LDA VELT,Y
  RTS

; T0, T1 = centre of a tornado: A = 0 only grass under it, 1 a hedge or a bed, 2 new hedge (keeps X)
TW_BOX:
  LDA T0
  SEC
  SBC #6
  LSR A
  LSR A
  STA T2
  LDA T0
  CLC
  ADC #5
  LSR A
  LSR A
  STA T3
  LDA T1
  SEC
  SBC #6
  LSR A
  LSR A
  STA T4
  LDA T1
  CLC
  ADC #5
  LSR A
  LSR A
  STA T5
  STZ T7
.tb_r:
  LDY T4
  LDA MROW_LO,Y
  STA PTR
  LDA MROW_HI,Y
  STA PTR+1
  LDY T2
.tb_c:
  LDA (PTR),Y
  BEQ .tb_n
  CMP #ST_TF
  BEQ .tb_t
  CMP #ST_TS
  BEQ .tb_t
  LDA #1
  STA T7
.tb_n:
  INY
  CPY T3
  BCC .tb_c
  BEQ .tb_c
  INC T4
  LDA T4
  CMP T5
  BCC .tb_r
  BEQ .tb_r
  LDA T7
  RTS
.tb_t:
  LDA #2
  RTS


; ===============================================================
;  THE SHEARS: along the hedges, after Flora
; ===============================================================
SHEARS:
  LDX #0
.sh_l:
  CPX NSH
  BEQ .sh_r
  STX CI
  JSR SH_ONE
  LDA GSTATE
  BNE .sh_r
  LDX CI
  INX
  BRA .sh_l
.sh_r:
  RTS

SH_ONE:
  LDA SHS,X
  BNE .so_m
  JSR SH_CHOOSE
  LDX CI
  LDA SHS,X
  BEQ .so_t
.so_m:
  LDY LEVI
  LDA SH_SPD,Y
  LDY REDS
  BEQ .so_s
  CLC
  ADC #4
.so_s:
  CLC
  ADC SHA,X
  PHA
  AND #15
  STA SHA,X
  PLA
  LSR A
  LSR A
  LSR A
  LSR A
  BEQ .so_t
  STA T7
.so_p:
  LDY SHD,X
  LDA SHPX,X
  CLC
  ADC DXT,Y
  STA SHPX,X
  LDA SHPY,X
  CLC
  ADC DYT,Y
  STA SHPY,X
  DEC SHS,X
  BEQ .so_t
  DEC T7
  BNE .so_p
.so_t:
  LDA SHPX,X                   ; touching Flora?
  SEC
  SBC FPX
  BCS .so_a
  EOR #$FF
  INC A
.so_a:
  CMP #6
  BCS .so_r
  LDA SHPY,X
  SEC
  SBC FPY
  BCS .so_b
  EOR #$FF
  INC A
.so_b:
  CMP #6
  BCS .so_r
  LDA #2
  JMP DIE
.so_r:
  RTS

; shear CI at a cell: the next one (not back, unless there is no other)
SH_CHOOSE:
  STZ NCAND
  LDY #0
.sc_d:
  LDX CI
  LDA SHD,X
  EOR #1                       ; the way back (0-1, 2-3)
  STA T6
  CPY T6
  BEQ .sc_n
  JSR SH_WALK
  BCC .sc_n
  LDX NCAND
  TYA
  STA CANDS,X
  INC NCAND
.sc_n:
  INY
  CPY #4
  BNE .sc_d
  LDA NCAND
  BNE .sc_c
  LDY T6                       ; a dead end: back
  JSR SH_WALK
  BCS .sc_bk
  RTS
.sc_bk:
  STY CANDS
  LDA #1
  STA NCAND
.sc_c:
  LDA CANDS                    ; one only, or now and then at random
  LDX NCAND
  CPX #1
  BEQ .sc_go
  JSR NEXT_RND
  AND #3
  BNE .sc_b
  LDA RND
  LSR A
  LSR A
.sc_m:
  CMP NCAND
  BCC .sc_rn
  SBC NCAND
  BRA .sc_m
.sc_rn:
  TAX
  LDA CANDS,X
  BRA .sc_go
.sc_b:                         ; the way nearest to Flora
  LDA #$FF
  STA BESTD
  LDX #0
.sc_bl:
  STX T5
  LDY CANDS,X
  LDX CI
  LDA SHX,X
  CLC
  ADC DXT,Y
  SEC
  SBC FX
  BCS .sc_ax
  EOR #$FF
  INC A
.sc_ax:
  STA T4
  LDA SHY,X
  CLC
  ADC DYT,Y
  SEC
  SBC FY
  BCS .sc_ay
  EOR #$FF
  INC A
.sc_ay:
  CLC
  ADC T4
  CMP BESTD
  BCS .sc_bn
  STA BESTD
  STY BESTW
.sc_bn:
  LDX T5
  INX
  CPX NCAND
  BNE .sc_bl
  LDA BESTW
.sc_go:
  LDX CI
  STA SHD,X
  TAY
  LDA SHX,X
  CLC
  ADC DXT,Y
  STA SHX,X
  LDA SHY,X
  CLC
  ADC DYT,Y
  STA SHY,X
  LDA #4
  STA SHS,X
.sc_r:
  RTS

; Y = way from the cell of the shear CI: C = 1 if they can go (a hedge, or new hedge when red); keeps Y
SH_WALK:
  PHY
  LDX CI
  LDA SHX,X
  CLC
  ADC DXT,Y
  STA NX
  LDA SHY,X
  CLC
  ADC DYT,Y
  TAY
  LDX NX
  JSR GETC
  PLY
  CMP #ST_HEDGE
  BEQ .sw_y
  LDX REDS
  BEQ .sw_n
  CMP #ST_TF
  BEQ .sw_y
  CMP #ST_TS
  BEQ .sw_y
.sw_n:
  CLC
  RTS
.sw_y:
  SEC
  RTS


; ===============================================================
;  THE CATERPILLAR, THE TIMER, THE WIND, A LIFE LOST
; ===============================================================
FUSE:
  LDA FMODE
  BEQ .fu_off
  LDA FIDLE                    ; Flora moving: it stops
  BEQ .fu_r
  LDA FUSEA
  BNE .fu_e
  LDA FIDLE
  CMP #FUSE_WAIT
  BCC .fu_r
  LDA #1
  STA FUSEA
  STZ FUSEI
  STZ FUSET
  LDA #W_BUG
  LDX #2
  JMP SFX_WHISTLE
.fu_e:
  INC FUSET
  LDA FUSET
  CMP #FUSE_SPD
  BCC .fu_r
  STZ FUSET
  INC FUSEI
  LDA FUSEI
  INC A
  CMP TRLEN
  BCC .fu_r
  LDA #3
  JMP DIE
.fu_off:
  STZ FUSEA
.fu_r:
  RTS

TIME_TICK:
  DEC TIMET
  BNE .tt_r
  LDA #16
  STA TIMET
  LDA TIMER
  BEQ .tt_r
  DEC TIMER
  BNE .tt_r
  LDA #1                       ; time is up: the shears turn red
  STA REDS
  LDA #W_ALARM
  LDX #2
  JMP SFX_WHISTLE
.tt_r:
  RTS

; a gust now and then when a tornado is near Flora
WIND:
  DEC WINDT
  BNE .wi_r
  LDA #40
  STA WINDT
  LDX NTOR
.wi_l:
  DEX
  BMI .wi_r
  LDA TWX,X
  SEC
  SBC FPX
  BCS .wi_a
  EOR #$FF
  INC A
.wi_a:
  CMP #48
  BCS .wi_l
  LDA TWY,X
  SEC
  SBC FPY
  BCS .wi_b
  EOR #$FF
  INC A
.wi_b:
  CMP #48
  BCS .wi_l
  LDY TWX,X
  LDA #S_WIND
  JMP BOOM_AT
.wi_r:
  RTS

; A = what: 1 tornado, 2 shears, 3 caterpillar
DIE:
  STA DEATHS
  LDA #1
  STA GSTATE
  LDA #90
  STA GT
  LDA #W_LOST
  LDX #2
  JSR SFX_WHISTLE
  LDA #S_LOST
  JMP SFX_BOOM


; ===============================================================
;  SPRITES: Flora, the caterpillar, the tornadoes, the shears;
;  the order turns every frame (more than 4 on a line take turns)
; ===============================================================
; OX, OY = centre on the lawn, ON = pattern, OC = colour: one sprite into OBUF
ADD_SPR:
  LDX SPRI
  LDA OY
  DEC A
  STA OBUF,X
  LDA OX
  SEC
  SBC #8
  LDY OC
  BCS .as_x
  ADC #32                      ; near the left edge: the early clock
  PHA
  TYA
  ORA #$80
  TAY
  PLA
.as_x:
  STA OBUF+1,X
  LDA ON
  STA OBUF+2,X
  TYA
  STA OBUF+3,X
  INX
  INX
  INX
  INX
  STX SPRI
  RTS

BUILD_SAT:
  STZ SPRI
  LDA GSTATE                   ; Flora blinks when a life is lost
  CMP #1
  BNE .bs_f
  LDA TICKS
  AND #4
  BNE .bs_u
.bs_f:
  LDA FPX
  STA OX
  LDA FPY
  STA OY
  LDA FPX
  CLC
  ADC FPY
  AND #4                       ; the step: 0 or 4 -> frame 0 / 1 (8 patterns each)
  ASL A
  STA T0
  LDA FFACE
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_FLORA
  STA ON
  LDA #9
  STA OC
  JSR ADD_SPR
  LDA ON
  CLC
  ADC #4
  STA ON
  LDA #11
  STA OC
  JSR ADD_SPR
.bs_u:
  LDA FUSEA                    ; the caterpillar
  BEQ .bs_t
  LDY FUSEI
  LDA TRX,Y
  ASL A
  ASL A
  ORA #2
  STA OX
  LDA TRY,Y
  ASL A
  ASL A
  ORA #2
  STA OY
  LDA TICKS
  AND #8
  LSR A
  CLC
  ADC #PT_BUG
  STA ON
  LDA #13
  STA OC
  JSR ADD_SPR
.bs_t:
  LDA #0                       ; the tornadoes
.bs_tl:
  STA CI
  CMP NTOR
  BEQ .bs_s
  TAX
  LDA TWX,X
  STA OX
  LDA TWY,X
  STA OY
  LDA TICKS
  LSR A
  LSR A
  CLC
  ADC CI
  AND #3
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_TWIST
  STA ON
  LDA #14
  STA OC
  JSR ADD_SPR
  LDA ON
  CLC
  ADC #4
  STA ON
  LDA #15
  STA OC
  JSR ADD_SPR
  LDA CI
  INC A
  BRA .bs_tl
.bs_s:
  LDA #0                       ; the shears
.bs_sl:
  STA CI
  CMP NSH
  BEQ .bs_c
  TAX
  LDA SHPX,X
  STA OX
  LDA SHPY,X
  STA OY
  LDA TICKS
  AND #8
  LSR A
  CLC
  ADC #PT_SHEARS
  STA ON
  LDA #15
  LDY REDS
  BEQ .bs_sc
  LDA #8
.bs_sc:
  STA OC
  JSR ADD_SPR
  LDA CI
  INC A
  BRA .bs_sl
.bs_c:                         ; OBUF into the SAT from SPRROT on
  LDA SPRI
  BEQ .bs_e
  LDA SPRROT
  CLC
  ADC #4
  CMP SPRI
  BCC .bs_o
  LDA #0
.bs_o:
  STA SPRROT
  TAX
  LDY #0
.bs_l:
  LDA OBUF,X
  STA SAT_BUFFER,Y
  LDA OBUF+1,X
  STA SAT_BUFFER+1,Y
  LDA OBUF+2,X
  STA SAT_BUFFER+2,Y
  LDA OBUF+3,X
  STA SAT_BUFFER+3,Y
  INY
  INY
  INY
  INY
  INX
  INX
  INX
  INX
  CPX SPRI
  BCC .bs_w
  LDX #0
.bs_w:
  CPY SPRI
  BNE .bs_l
.bs_e:
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS


; ===============================================================
;  SPRITES, NMI AND SOUND (from lighthouse keeper)
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
SC_COLS:    .byte 4,26                         ; score of player 1 / 2 on row 0
BITS:       .byte 1,2,4,8
S_BIG = S_LOST                                 ; (lib_sound: a big noise is not cut by a small one)
PS_OFF:     .byte 0,16                         ; the block of every player in PSAVE
LW_LO:      .byte <LAWN0,<LAWN1                ; the lawn of every player
LW_HI:      .byte >LAWN0,>LAWN1
ENC_ST:     .byte 0,1,0,0,2,3,0,0              ; a cell into 2 bits (the new hedge is grass)
DEC_ST:     .byte ST_GRASS,ST_HEDGE,ST_BF,ST_BS
LOGO_ST:    .byte ST_BLANK,ST_GRASS,ST_HEDGE,ST_BF
; the ways: 0 up, 1 down, 2 left, 3 right
DXT:        .byte 0,0,$FF,1
DYT:        .byte $FF,1,0,0
; the shears at the start of a life: column and way (the row is the border far from Flora)
SH_X0:      .byte 12,51,24,39
SH_D0:      .byte 2,3,3,2
; per lawn (0-7): time (units of 16 frames), shears, their speed (1/16 px a frame), tornado speed (0 slow, 8 fast)
TIME0:      .byte 240,225,210,200,190,180,170,160
SH_N:       .byte 2,2,3,3,3,4,4,4
SH_SPD:     .byte 10,11,12,13,14,15,16,16
TW_SPD:     .byte 0,0,0,8,8,8,8,8
; random speeds of a tornado: slow (-1..1), fast (-2..2, never still)
VELT:       .byte $FF,0,1,$FF,1,0,$FF,1
            .byte $FE,$FF,1,2,$FE,2,$FF,1

; title: Flora (2), the tornado (2), the shears
TITLE_NS = 5
TITLE_SY:   .byte 87,87,111,111,111
TITLE_SX:   .byte 20,20,20,20,216
TITLE_SN:   .byte PT_FLORA,PT_FLORA+4,PT_TWIST,PT_TWIST+4,PT_SHEARS
TITLE_SC:   .byte 9,11,14,15,15
TITLE_SM:   .byte 1,1,3,3,1                    ; frames - 1
TITLE_SA:   .byte 8,8,8,8,4                    ; patterns from a frame to the next

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,$71,"1UP",0
  .byte 0,12,$B1,"HI",0
  .byte $FF
TXT_TOP2:
  .byte 0,22,$71,"2UP",0,$FF
TXT_BUTTONS:
  .byte 20,6,$F1,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,$F1,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,$71,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,4,$B1,"HELP FLORA TIDY THE LAWN",0
  .byte 11,6,$F1,"BUTTON 1  FAST HEDGE",0
  .byte 12,6,$F1,"BUTTON 2  SLOW HEDGE X2",0
  .byte 14,6,$F1,"AVOID THE TORNADO",0
  .byte 15,6,$F1,"AND THE MAD SHEARS",0
  .byte 17,6,$31,"TIDY 75% OF THE LAWN",0
  .byte $FF
TXT_LAWNH:
  .byte 23,6,$F1,"LAWN ",0,$FF
TXT_PLAYER:
  .byte 10,12,$F1,"PLAYER ",0,$FF
TXT_LAWNM:
  .byte 12,9,$B1,"LAWN ",0,$FF
TXT_DONE:
  .byte 11,8,$B1,"THE LAWN IS TIDY",0,$FF
TXT_OVER:
  .byte 11,11,$F1,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 13,11,$F1,"PLAYER ",0,$FF

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
;  GRAPHICS, CELLS AND SOUND TABLES (generated)
; ===============================================================
; LIX: generated by dev/gen_lix.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; extra glyphs
CH_LIFE = 96
CH_BAR = 97
PT_FLORA = 0
PT_TWIST = 32
PT_SHEARS = 64
PT_BUG = 72
SPR_LEN = 640
SPR_PAGES = 3
SPRITES:
  .byte $00,$00,$00,$00,$00,$07,$0F,$0F,$07,$0F,$1F,$00,$00,$18,$00,$00,$00,$00,$00,$00,$00,$E0,$E0,$E0,$C0,$E0,$F0,$00,$00,$60,$00,$00
  .byte $03,$0F,$03,$03,$01,$00,$00,$00,$00,$00,$00,$08,$08,$00,$00,$00,$C0,$F0,$C0,$40,$80,$00,$18,$00,$00,$00,$00,$20,$20,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$07,$0F,$0F,$07,$0F,$1F,$00,$00,$06,$00,$00,$00,$00,$00,$00,$00,$E0,$E0,$E0,$C0,$E0,$F0,$00,$00,$C0,$00,$00
  .byte $03,$0F,$03,$03,$01,$00,$00,$00,$00,$00,$00,$02,$02,$00,$00,$00,$C0,$F0,$C0,$40,$80,$00,$18,$00,$00,$00,$00,$80,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$07,$07,$07,$03,$07,$0F,$00,$00,$06,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$F0,$F8,$00,$00,$18,$00,$00
  .byte $03,$0F,$03,$02,$01,$00,$18,$00,$00,$00,$00,$04,$04,$00,$00,$00,$C0,$F0,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$10,$10,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$07,$07,$07,$03,$07,$0F,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$F0,$F8,$00,$00,$60,$00,$00
  .byte $03,$0F,$03,$02,$01,$00,$18,$00,$00,$00,$00,$01,$01,$00,$00,$00,$C0,$F0,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$40,$40,$00,$00,$00
  .byte $00,$7F,$7E,$07,$1F,$0F,$0B,$07,$0F,$0E,$03,$0F,$0E,$03,$07,$06,$00,$E6,$7E,$FE,$F8,$9C,$FC,$F4,$D0,$F0,$E0,$80,$C0,$80,$00,$80
  .byte $00,$00,$01,$18,$00,$00,$04,$08,$00,$01,$04,$00,$01,$04,$08,$01,$00,$18,$80,$00,$06,$60,$00,$08,$20,$00,$00,$40,$00,$00,$80,$00
  .byte $00,$33,$3F,$3F,$39,$07,$1F,$1E,$17,$1F,$0E,$0B,$07,$07,$02,$02,$00,$FF,$FC,$CC,$FC,$F8,$D8,$F8,$E0,$A0,$C0,$C0,$80,$00,$C0,$C0
  .byte $00,$0C,$00,$00,$06,$18,$00,$01,$08,$00,$01,$04,$08,$00,$01,$01,$00,$00,$03,$30,$00,$00,$20,$00,$00,$40,$00,$00,$40,$80,$00,$00
  .byte $00,$7F,$7C,$4F,$7F,$3F,$37,$2F,$0F,$0D,$03,$03,$03,$01,$00,$01,$00,$E6,$FE,$F8,$E0,$30,$F0,$E0,$B0,$F0,$E0,$E0,$B0,$60,$E0,$C0
  .byte $00,$00,$03,$30,$00,$00,$08,$10,$00,$02,$04,$00,$00,$00,$01,$00,$00,$18,$00,$00,$18,$C0,$00,$10,$40,$00,$00,$10,$40,$80,$10,$20
  .byte $00,$CF,$FF,$3F,$39,$07,$1F,$1F,$03,$07,$03,$03,$01,$01,$03,$01,$00,$FC,$F8,$9C,$FC,$F8,$E8,$78,$F8,$F0,$D0,$70,$E0,$A0,$40,$C0
  .byte $00,$30,$00,$00,$06,$18,$00,$00,$04,$00,$00,$00,$02,$00,$00,$02,$00,$00,$06,$60,$00,$00,$10,$80,$00,$08,$20,$80,$10,$40,$80,$00
  .byte $00,$30,$48,$48,$34,$02,$01,$01,$02,$04,$08,$10,$20,$00,$00,$00,$00,$0C,$12,$12,$2C,$40,$80,$80,$40,$20,$10,$08,$04,$00,$00,$00
  .byte $00,$00,$0C,$12,$12,$0D,$01,$01,$01,$01,$02,$02,$04,$00,$00,$00,$00,$00,$30,$48,$48,$B0,$80,$80,$80,$80,$40,$40,$20,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$1E,$3F,$37,$19,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$D8,$FF,$FF,$24,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$1E,$3F,$37,$1A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$F6,$FF,$FC,$48,$00,$00,$00,$00,$00,$00

; the extra glyphs ($60-)
FONTX:
  .byte $38,$7C,$6C,$38,$10,$54,$38,$10
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00

; cells, per season: patterns of the pair (left << 3 | right) for the texture rows 0-3, then the colours
CSEA:
; SPRING
  .byte $00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$55,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$77,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$77,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $44,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0D,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0D,$0F,$0F
  .byte $0F,$0F,$2F,$0F,$22,$00,$0F,$0F,$0F,$0F,$0F,$2F,$00,$22,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$44
  .byte $00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$66,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $11,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$22,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0A,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0A,$0F,$0F
  .byte $0F,$0F,$5F,$0F,$55,$00,$0F,$0F,$0F,$0F,$0F,$5F,$00,$55,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$11
  .byte $33,$C3,$B3,$93,$63,$63,$13,$33,$3C,$C2,$BC,$9C,$6C,$6C,$1C,$3C,$3B,$CB,$AB,$9B,$6B,$6B,$1B,$3B,$39,$C9,$B9,$89,$69,$69,$19,$39
  .byte $36,$C6,$B6,$96,$6B,$66,$16,$36,$36,$C6,$B6,$96,$66,$69,$16,$36,$31,$C1,$B1,$91,$61,$61,$11,$31,$33,$C3,$B3,$93,$63,$63,$13,$33
  .byte $23,$C3,$B3,$93,$63,$63,$13,$23,$3C,$2C,$BC,$9C,$6C,$6C,$1C,$3C,$3B,$CB,$BB,$9B,$6B,$6B,$1B,$3B,$39,$C9,$B9,$99,$69,$69,$19,$39
  .byte $36,$C6,$B6,$96,$B6,$66,$16,$36,$36,$C6,$B6,$96,$66,$96,$16,$36,$31,$C1,$B1,$91,$61,$61,$11,$31,$23,$C3,$B3,$93,$63,$63,$13,$23
  .byte $33,$C3,$B3,$93,$63,$63,$13,$33,$3C,$C2,$BC,$9C,$6C,$6C,$1C,$3C,$3B,$CB,$AB,$9B,$6B,$6B,$1B,$3B,$39,$C9,$B9,$89,$69,$69,$19,$39
  .byte $36,$C6,$B6,$96,$66,$66,$16,$36,$36,$C6,$B6,$96,$66,$66,$16,$36,$31,$C1,$B1,$91,$61,$61,$11,$31,$33,$C3,$B3,$93,$63,$63,$13,$33
  .byte $23,$C3,$B3,$93,$63,$63,$13,$23,$3C,$2C,$BC,$9C,$6C,$6C,$1C,$3C,$3B,$CB,$BB,$9B,$6B,$6B,$1B,$3B,$39,$C9,$B9,$99,$69,$69,$19,$39
  .byte $36,$C6,$B6,$96,$B6,$66,$16,$36,$36,$C6,$B6,$96,$66,$96,$16,$36,$31,$C1,$B1,$91,$61,$61,$11,$31,$23,$C3,$B3,$93,$63,$63,$13,$23
; SUMMER
  .byte $00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$55,$0F,$0F,$0F,$0F,$50,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$77,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$77,$0F,$0F,$0F,$05,$0F,$0F,$0F,$0F,$00,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $44,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$44,$0F,$0F,$0F,$0F,$4F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0D,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$22,$00,$0F,$0F,$0F,$0F,$0F,$2F,$00,$22,$0F,$0F,$0F,$0B,$0F,$0F,$0F,$0F,$00,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$44
  .byte $00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$66,$0F,$0F,$0F,$0F,$60,$0F,$0F,$0F,$11,$0F,$1F,$1F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0E,$0F,$00,$00,$0F,$0F,$0F,$0F,$0E,$0F,$00,$00,$0F,$0F,$0F,$06,$0F,$0F,$0F,$0F,$00,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $11,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$22,$0F,$0F,$0F,$0F,$2F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0A,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$55,$00,$0F,$0F,$0F,$0F,$0F,$5F,$00,$55,$0F,$0F,$0F,$0D,$0F,$0F,$0F,$0F,$00,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$11
  .byte $22,$C2,$B2,$D2,$A2,$A2,$12,$22,$2C,$C1,$BC,$DC,$AC,$AC,$C1,$2C,$2B,$CB,$AB,$DB,$AB,$AB,$1B,$2B,$2D,$CD,$BD,$9D,$AD,$AD,$1D,$2D
  .byte $2A,$CA,$BA,$DA,$AF,$AA,$1A,$2A,$2A,$CA,$BA,$DA,$AA,$AD,$1A,$2A,$21,$C1,$B1,$D1,$A1,$A1,$11,$21,$22,$C2,$B2,$D2,$A2,$A2,$12,$22
  .byte $32,$C2,$B2,$D2,$A2,$A2,$12,$32,$2C,$1C,$BC,$DC,$AC,$AC,$1C,$2C,$2B,$CB,$BB,$DB,$AB,$AB,$1B,$2B,$2D,$CD,$BD,$DD,$AD,$AD,$1D,$2D
  .byte $2A,$CA,$BA,$DA,$FA,$AA,$1A,$2A,$2A,$CA,$BA,$DA,$AA,$DA,$1A,$2A,$21,$C1,$B1,$D1,$A1,$A1,$11,$21,$32,$C2,$B2,$D2,$A2,$A2,$12,$32
  .byte $22,$C2,$B2,$D2,$A2,$A2,$12,$22,$2C,$C1,$BC,$DC,$AC,$AC,$C1,$2C,$2B,$CB,$AB,$DB,$AB,$AB,$1B,$2B,$2D,$CD,$BD,$9D,$AD,$AD,$1D,$2D
  .byte $2A,$CA,$BA,$DA,$AA,$AA,$1A,$2A,$2A,$CA,$BA,$DA,$AA,$AA,$1A,$2A,$21,$C1,$B1,$D1,$A1,$A1,$11,$21,$22,$C2,$B2,$D2,$A2,$A2,$12,$22
  .byte $32,$C2,$B2,$D2,$A2,$A2,$12,$32,$2C,$1C,$BC,$DC,$AC,$AC,$1C,$2C,$2B,$CB,$BB,$DB,$AB,$AB,$1B,$2B,$2D,$CD,$BD,$DD,$AD,$AD,$1D,$2D
  .byte $2A,$CA,$BA,$DA,$FA,$AA,$1A,$2A,$2A,$CA,$BA,$DA,$AA,$DA,$1A,$2A,$21,$C1,$B1,$D1,$A1,$A1,$11,$21,$32,$C2,$B2,$D2,$A2,$A2,$12,$32
; AUTUMN
  .byte $00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$55,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$77,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$77,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $44,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0D,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$2F,$0F,$22,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$22,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$44
  .byte $00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$66,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $11,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$22,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0A,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$5F,$0F,$55,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$55,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$11
  .byte $AA,$6A,$BA,$7A,$CA,$CA,$1A,$AA,$A6,$69,$B6,$76,$C6,$C6,$16,$A6,$AB,$6B,$FB,$7B,$CB,$CB,$1B,$AB,$A7,$67,$B7,$57,$C7,$C7,$17,$A7
  .byte $AC,$6C,$BC,$7C,$CB,$CC,$1C,$AC,$AC,$6C,$BC,$7C,$CC,$C9,$1C,$AC,$A1,$61,$B1,$71,$C1,$C1,$11,$A1,$AA,$6A,$BA,$7A,$CA,$CA,$1A,$AA
  .byte $6A,$6A,$BA,$7A,$CA,$CA,$1A,$6A,$A6,$96,$B6,$76,$C6,$C6,$16,$A6,$AB,$6B,$BB,$7B,$CB,$CB,$1B,$AB,$A7,$67,$B7,$77,$C7,$C7,$17,$A7
  .byte $AC,$6C,$BC,$7C,$BC,$CC,$1C,$AC,$AC,$6C,$BC,$7C,$CC,$9C,$1C,$AC,$A1,$61,$B1,$71,$C1,$C1,$11,$A1,$6A,$6A,$BA,$7A,$CA,$CA,$1A,$6A
  .byte $AA,$6A,$BA,$7A,$CA,$CA,$1A,$AA,$A6,$69,$B6,$76,$C6,$C6,$16,$A6,$AB,$6B,$FB,$7B,$CB,$CB,$1B,$AB,$A7,$67,$B7,$57,$C7,$C7,$17,$A7
  .byte $AC,$6C,$BC,$7C,$CC,$CC,$1C,$AC,$AC,$6C,$BC,$7C,$CC,$CC,$1C,$AC,$A1,$61,$B1,$71,$C1,$C1,$11,$A1,$AA,$6A,$BA,$7A,$CA,$CA,$1A,$AA
  .byte $6A,$6A,$BA,$7A,$CA,$CA,$1A,$6A,$A6,$96,$B6,$76,$C6,$C6,$16,$A6,$AB,$6B,$BB,$7B,$CB,$CB,$1B,$AB,$A7,$67,$B7,$77,$C7,$C7,$17,$A7
  .byte $AC,$6C,$BC,$7C,$BC,$CC,$1C,$AC,$AC,$6C,$BC,$7C,$CC,$9C,$1C,$AC,$A1,$61,$B1,$71,$C1,$C1,$11,$A1,$6A,$6A,$BA,$7A,$CA,$CA,$1A,$6A
; WINTER
  .byte $00,$05,$0F,$0F,$0F,$0F,$0F,$00,$50,$55,$0F,$0F,$0F,$0F,$0F,$50,$0F,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$77,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$77,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$00,$05,$0F,$0F,$0F,$0F,$0F,$00
  .byte $44,$0F,$0F,$0F,$0F,$0F,$0F,$44,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$22,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$22,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$44,$0F,$0F,$0F,$0F,$0F,$0F,$44
  .byte $00,$06,$0F,$0F,$0F,$0F,$0F,$00,$60,$66,$0F,$0F,$0F,$0F,$0F,$60,$0F,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$00,$06,$0F,$0F,$0F,$0F,$0F,$00
  .byte $11,$0F,$0F,$0F,$0F,$0F,$0F,$11,$0F,$22,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$55,$00,$0F,$0F,$0F,$0F,$0F,$0F,$00,$55,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$11,$0F,$0F,$0F,$0F,$0F,$0F,$11
  .byte $FF,$CF,$5F,$9F,$EF,$EF,$1F,$FF,$CF,$CF,$5C,$9C,$EC,$EC,$1C,$CF,$F5,$C5,$45,$95,$E5,$E5,$15,$F5,$F9,$C9,$59,$89,$E9,$E9,$19,$F9
  .byte $FE,$CE,$5E,$9E,$E4,$EE,$1E,$FE,$FE,$CE,$5E,$9E,$EE,$ED,$1E,$FE,$F1,$C1,$51,$91,$E1,$E1,$11,$F1,$FF,$CF,$5F,$9F,$EF,$EF,$1F,$FF
  .byte $EF,$CF,$5F,$9F,$EF,$EF,$1F,$EF,$FC,$FC,$5C,$9C,$EC,$EC,$1C,$FC,$F5,$C5,$55,$95,$E5,$E5,$15,$F5,$F9,$C9,$59,$99,$E9,$E9,$19,$F9
  .byte $FE,$CE,$5E,$9E,$4E,$EE,$1E,$FE,$FE,$CE,$5E,$9E,$EE,$DE,$1E,$FE,$F1,$C1,$51,$91,$E1,$E1,$11,$F1,$EF,$CF,$5F,$9F,$EF,$EF,$1F,$EF
  .byte $FF,$CF,$5F,$9F,$EF,$EF,$1F,$FF,$CF,$CF,$5C,$9C,$EC,$EC,$1C,$CF,$F5,$C5,$45,$95,$E5,$E5,$15,$F5,$F9,$C9,$59,$89,$E9,$E9,$19,$F9
  .byte $FE,$CE,$5E,$9E,$EE,$EE,$1E,$FE,$FE,$CE,$5E,$9E,$EE,$EE,$1E,$FE,$F1,$C1,$51,$91,$E1,$E1,$11,$F1,$FF,$CF,$5F,$9F,$EF,$EF,$1F,$FF
  .byte $EF,$CF,$5F,$9F,$EF,$EF,$1F,$EF,$FC,$FC,$5C,$9C,$EC,$EC,$1C,$FC,$F5,$C5,$55,$95,$E5,$E5,$15,$F5,$F9,$C9,$59,$99,$E9,$E9,$19,$F9
  .byte $FE,$CE,$5E,$9E,$4E,$EE,$1E,$FE,$FE,$CE,$5E,$9E,$EE,$DE,$1E,$FE,$F1,$C1,$51,$91,$E1,$E1,$11,$F1,$EF,$CF,$5F,$9F,$EF,$EF,$1F,$EF
SEA_HI:
  .byte >(CSEA+0),>(CSEA+512),>(CSEA+1024),>(CSEA+1536)
SEA_LO:
  .byte <(CSEA+0),<(CSEA+512),<(CSEA+1024),<(CSEA+1536)
SEAN0:     .byte "SPRING",0
SEAN1:     .byte "SUMMER",0
SEAN2:     .byte "AUTUMN",0
SEAN3:     .byte "WINTER",0
SEAN_LO:
  .byte <SEAN0,<SEAN1,<SEAN2,<SEAN3
SEAN_HI:
  .byte >SEAN0,>SEAN1,>SEAN2,>SEAN3

; the logo of the title: 12 rows x 64 cells, 4 cells a byte (0 blank, 1 grass, 2 hedge, 3 flowers)
LOGO:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$15,$55,$55,$55,$55,$55,$55,$55,$55,$54,$00,$00,$00
  .byte $00,$00,$00,$55,$A9,$57,$55,$5A,$95,$6A,$55,$5A,$95,$00,$00,$00
  .byte $00,$00,$00,$55,$A9,$5D,$55,$5A,$97,$5A,$95,$6A,$55,$00,$00,$00
  .byte $00,$00,$00,$5D,$A9,$55,$55,$5A,$95,$55,$AA,$A5,$5D,$00,$00,$00
  .byte $00,$00,$00,$55,$A9,$D5,$55,$5A,$95,$55,$6A,$95,$55,$00,$00,$00
  .byte $00,$00,$00,$55,$A9,$55,$5D,$5A,$95,$55,$6A,$95,$55,$00,$00,$00
  .byte $00,$00,$00,$55,$A9,$55,$55,$5A,$95,$55,$AA,$A5,$55,$00,$00,$00
  .byte $00,$00,$00,$75,$AA,$AA,$95,$5A,$9D,$5A,$95,$6A,$75,$00,$00,$00
  .byte $00,$00,$00,$55,$AA,$AA,$97,$5A,$95,$6A,$55,$5A,$95,$00,$00,$00
  .byte $00,$00,$00,$15,$55,$55,$55,$55,$55,$55,$55,$55,$54,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; AY periods: index = MIDI note - 35
TP_LO:
  .byte $00,$BC,$86,$53,$24,$F6,$CC,$A4,$7E,$5A,$38,$18,$FA,$DE,$C3,$AA,$92,$7B,$66,$52,$3F,$2D,$1C,$0C,$FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9
  .byte $9F,$96,$8E,$86,$7F,$77,$71,$6A,$64,$5F,$59,$54,$50,$4B,$47,$43,$3F,$3C,$38,$35,$32,$2F,$2D,$2A,$28,$26,$24,$22,$20
TP_HI:
  .byte $00,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; tunes: song * 4 + track (melody, harmony, bass, drums)
SONGP_LO:
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3,<SG2_0,<SG2_1,<SG2_2,<SG2_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3,>SG2_0,>SG2_1,>SG2_2,>SG2_3
SG0_0:
  .byte $20,$0C,$24,$06,$27,$06,$2C,$0C,$2B,$06,$29,$06,$27,$0C,$24,$0C,$25,$0C,$29,$06,$2C,$06,$2E,$0C,$2C,$06,$29,$06,$27,$18,$00,$0C
  .byte $29,$0C,$27,$06,$25,$06,$24,$0C,$22,$06,$20,$06,$1F,$0C,$22,$0C,$27,$0C,$25,$06,$24,$06,$22,$0C,$1F,$0C,$20,$24,$FF
SG0_1:
  .byte $18,$24,$18,$24,$19,$24,$18,$24,$19,$24,$16,$24,$1F,$24,$1B,$24,$FF
SG0_2:
  .byte $08,$0C,$0F,$0C,$0F,$0C,$08,$0C,$0F,$0C,$0F,$0C,$0D,$0C,$14,$0C,$14,$0C,$08,$0C,$0F,$0C,$0F,$0C,$0D,$0C,$14,$0C,$14,$0C,$0F,$0C
  .byte $16,$0C,$16,$0C,$0F,$0C,$16,$0C,$16,$0C,$08,$24,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$03,$0C,$01,$0C,$03,$0C,$03,$0C,$01,$0C,$03,$0C,$03,$0C,$01,$0C,$03,$0C,$03,$0C,$01,$0C,$03,$0C,$03,$0C,$01,$0C
  .byte $03,$0C,$03,$0C,$01,$0C,$03,$0C,$03,$0C,$01,$0C,$02,$0C,$04,$0C,$FF
SG1_0:
  .byte $27,$06,$2C,$06,$30,$06,$2E,$06,$2C,$12,$FF
SG1_1:
  .byte $24,$12,$27,$18,$FF
SG1_2:
  .byte $08,$12,$08,$18,$FF
SG1_3:
  .byte $03,$06,$03,$06,$03,$06,$03,$06,$01,$12,$FF
SG2_0:
  .byte $2C,$06,$2E,$06,$30,$06,$33,$0C,$30,$06,$31,$06,$2E,$06,$30,$06,$2C,$06,$2E,$0C,$33,$06,$30,$06,$2C,$1E,$FF
SG2_1:
  .byte $27,$18,$29,$18,$2B,$18,$27,$24,$FF
SG2_2:
  .byte $14,$18,$0D,$18,$0F,$18,$08,$24,$FF
SG2_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$04,$24,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$2D,$2D,$59,$59,$59,$9C,$8A,$7C,$70,$67,$5F,$58,$52,$4C,$48,$44,$40,$3D,$3A,$37,$35,$33,$31,$2F,$2D,$2B,$2A,$28,$27,$27,$27
  .byte $27,$27,$27,$27,$3C,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$45
  .byte $47,$49,$4A,$4C,$4E,$50,$52,$54,$57,$59,$5C,$5F,$62,$65,$68,$6C,$70,$74,$78,$7D,$82,$88,$8E,$95,$9C,$A4,$AE,$B8,$C3,$D0,$DF,$F0
  .byte $04,$1C,$39,$5B,$87,$BE,$09,$18,$18,$00,$00,$16,$16,$34,$34,$34,$34,$34,$34,$00,$00,$00,$00,$34,$34,$34,$34,$34,$34,$00,$00,$00
  .byte $00,$34,$34,$34,$34,$34,$34,$D0,$D0,$D0,$F0,$F0,$F0,$D0,$D0,$D0,$28,$28,$28,$28,$1E,$1E,$1E,$1E,$28,$28,$28,$28,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$B3,$B3
  .byte $B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD
  .byte $BD,$BD,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$06,$04,$06,$05,$04,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$08,$08,$08,$0A,$08
  .byte $07,$05,$04,$02,$0D,$0C,$0C,$0B,$0A,$0D,$0C,$0C,$0B,$0A,$0D,$0C,$0C,$0B,$0A,$0D,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$03,$0D
  .byte $0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$07,$06,$06,$06,$06
  .byte $05,$05,$05,$05,$04,$04,$04,$0C,$08,$00,$00,$0C,$06,$0C,$0C,$0B,$0B,$0A,$0A,$00,$00,$00,$00,$0C,$0C,$0B,$0B,$0A,$0A,$00,$00,$00
  .byte $00,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$08,$0A,$09,$08,$0A,$08,$06,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09
  .byte $08,$07,$06,$05,$04,$03,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$0C,$0C
  .byte $0B,$0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$05,$04,$04,$03,$03
  .byte $02,$02,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$03,$06,$24,$3F,$67,$6D,$87,$90,$A6,$E2,$E5
WH_LEN:
  .byte $00,$02,$03,$1E,$1B,$28,$06,$1A,$09,$16,$3C,$03,$13
W_FAST = 1
W_SLOW = 2
W_FILL = 3
W_SPLIT = 4
W_LOST = 5
W_SNIP = 6
W_ALARM = 7
W_BUG = 8
W_EXTRA = 9
W_OVER = 10
W_KEY = 11
W_SIGN = 12

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$04,$05,$06,$06,$07,$08,$08,$09,$09,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$08,$08,$07,$06,$06,$05,$04,$0E,$0E,$0E,$0E,$0D,$0D,$0D
  .byte $0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05
  .byte $05
EX_NP:
  .byte $00,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$02,$02,$03,$03,$04,$04,$05
  .byte $05,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$0D,$0E,$0E,$0F,$0F,$10,$10,$11,$11,$12,$12,$13,$13,$14,$14,$15
  .byte $15
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01
  .byte $01
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B6,$BE,$C6,$CE,$D7,$DF,$E8
  .byte $F1,$FA,$04,$0D,$17,$21,$2C,$36,$41,$4D,$58,$64,$70,$7D,$8A,$97,$A5,$B3,$C2,$D1,$E0,$F0,$01,$12,$23,$36,$48,$5C,$70,$85,$9B,$B2
  .byte $C9
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04
EX_START:
  .byte $00,$01,$19
EX_LEN:
  .byte $00,$18,$28
S_WIND = 1
S_LOST = 2

; the rows of the map: cell rows 0-43, and the first cell row of the tile rows 0-22
MROW_LO:
  .byte $00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40
  .byte $80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0,$00,$40,$80,$C0
MROW_HI:
  .byte $02,$02,$02,$02,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07
  .byte $07,$07,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0C
TROW_LO:
  .byte $00,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80,$00,$80
TROW_HI:
  .byte $02,$02,$02,$03,$03,$04,$04,$05,$05,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C
