;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   SKY TUG  -  an original vertical scrolling shooter         ;
;   65C02 assembly, TMS9918A Graphics I (tiles + sprites)      ;
;                                                              ;
;   - a space tug flies over a planet of islands, a sunken     ;
;     city, a crystal forest and an enemy base; at the end of  ;
;     every area waits a flying fortress                       ;
;   - depots on the ground hold the four numbered modules of   ;
;     the tug (2 front gun, 3 left gun, 4 right gun, 5 rear    ;
;     gun): shoot a depot open and fly over the module to dock ;
;     it; a hit costs the last module, without modules the tug ;
;   - button 2 with 2-3 modules: the formation (the modules    ;
;     circle the tug and fire all around for 6 s); with all 4: ;
;     the full ship for 15 s (wide fire, rams the enemies);    ;
;     it recharges in about 10 s (POWER on the bottom row)     ;
;   - the ground scrolls 2 pixels at a time: four pattern      ;
;     tables hold every name 0, 2, 4, 6 pixels lower (R4), and ;
;     every 8 pixels the other name table is shown (R2); the   ;
;     terrain rows are built while playing from the shapes of  ;
;     the area (material -> block -> pair of blocks -> name)   ;
;   - points: fighter 50, hawk 100, drone 150, bomber 300,     ;
;     missile 100, tank 200, turret 300, boat 200, launcher    ;
;     400, depot 500, cannon 1000, fortress 10000, 1000 for    ;
;     every module docked at the end of an area; 3 ships, one  ;
;     more at 20000 and every 50000; 1 or 2 players in turns;  ;
;     after a lost ship the game starts again from the last    ;
;     checkpoint passed                                        ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 29 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, the start and the end of an area;    ;
;     shots, docking, formation, explosions, alarm             ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI copies the ;
;     SAT, sets R4 / R2 (sprites and terrain move together)    ;
;     and plays the sound                                      ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: ships left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
AREA        = $40      ; ---- block of the player, saved: area 0-3
LOOPN       = $41      ;      round of the four areas (0 = first)
CPI         = $42      ;      checkpoint to start from
NEXTX       = $43      ;      next extra ship (BCD, ten thousands)
FRESH       = $44      ;      1 = a new area (the tune)
NMOD        = $45      ;      modules docked (0-4)
PBLOCK      = 6
GSTATE      = $48      ; 0 playing, 1 ship lost, 3 area clear
GT          = $49      ; timer of GSTATE
JOYC        = $4A      ; both joysticks drive the player playing
JOYP        = $4B      ; JOYC of the frame before
HUDD        = $4C      ; to draw again: 1 score, 2 bottom row
FIRSTT      = $4D      ; 1 = first turn of the game
SONG        = $4E      ; tune to play
VT          = $50      ; 2 bytes: map row on screen row 1 of the table shown
GS          = $52      ; 2 bytes: next material row to build
PH          = $54      ; phase 0-3: the terrain 0, 2, 4, 6 pixels lower (R4)
SCNT        = $55      ; frames to the next 2-pixel step
VIS         = $56      ; name table shown: 0 = $3800, 1 = $3C00
FILLR       = $57      ; next row (1-22) of the hidden table to write, 23 = done
VR4         = $58      ; R4 and R2 for the next NMI
VR2         = $59
PMN         = $5A      ; 2 bytes: material row GS-1 (the newest)    (pointers into $0400)
PMC         = $5C      ; 2 bytes: material row GS-2
PMS         = $5E      ; 2 bytes: material row GS-3
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
SHP         = $72      ; 2 bytes: next shape of the area
OBP         = $74      ; 2 bytes: next object of the area
NCP         = $76      ; 2 bytes: row of the next checkpoint ($FFFF = none)
SX          = $78      ; the tug: left x, top y (+32)
SY          = $79
MODE        = $7A      ; 0 normal, 1 formation, 2 full ship
MTIME       = $7B      ; time left of the mode (4-frame units)
CHG         = $7C      ; power: 0-160 (4-frame units), full = ready
ANG         = $7D      ; angle of the formation (64 a turn)
INVT        = $7E      ; frames the tug cannot be hit (blinks)
FIRET       = $7F      ; frames before the next shot while button 1 is held
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (0 = $3800, 4 = $3C00)
RR          = $87      ; first object in the SAT (turns)
BOSSI       = $88      ; slot of the fortress ($FF = none)
BCANS       = $89      ; cannons of the fortress left
FIRECH      = $8A      ; chance (of 256) that a ready enemy fires in a frame
BSPD        = $8B      ; speed code of the enemy bullets (SET_VEL)
PBN         = $8C      ; 2 bytes: block row GS-2 (pointers into $0400)
PBO         = $8E      ; 2 bytes: block row GS-3
NACT        = $90      ; shapes being drawn
CHGC        = $91      ; power cells on the HUD (CHG / 20)
LOSTN       = $92      ; ships lost (tests)
DEATH       = $93      ; what hit the tug last (kind, tests)
HSHOT       = $94      ; shot being checked by HITS
NRPEND      = $95      ; 1 = the next map row is still to build
HN          = $96      ; shots in HSX / HSY / HSI

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
OX         = $E0         ; sprite being added: left x, top y (+32), pattern, colour
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

; ---------------- objects: 20 slots, one byte per field ----------------
;   x = left pixel, y = top pixel + 32 (so -32..223 fits a byte), 8.8 speeds
NOB        = 20
O_K        = $0200       ; kind (K_*, 0 = free)
O_X        = $0214
O_XF       = $0228
O_Y        = $023C
O_YF       = $0250
O_VXL      = $0264       ; speed 8.8 (signed)
O_VXH      = $0278
O_VYL      = $028C
O_VYH      = $02A0
O_T        = $02B4       ; frames before it may fire
O_S        = $02C8       ; state
O_H        = $02DC       ; hits left
O_P        = $02F0       ; timer of the state / side of a cannon / target y
O_D        = $0304       ; direction (hawks)
O_F        = $0318       ; flags of the kind (KFLAG)

K_FIGHTER  = 1
K_HAWK     = 2
K_DRONE    = 3
K_BOMBER   = 4
K_MISSILE  = 5
K_TANK     = 6
K_TURRET   = 7
K_BOAT     = 8
K_LAUNCH   = 9
K_DEPOT    = 10
K_MODULE   = 11
K_BOOM     = 12
K_GBOOM    = 13
K_BOSS     = 14
K_BCAN     = 15
K_EBUL     = 16

F_GROUND   = 1           ; KFLAG: scrolls with the ground
F_SHOOT    = 2           ;        the shots hit it
F_HARM     = 4           ;        it hurts the tug
F_BULLET   = 8           ;        small (a bullet)

; ---------------- the shots of the tug ----------------
NPS        = 12
PS_X       = $0330
PS_Y       = $033C
PS_DX      = $0348       ; pixels a frame (signed)
PS_DY      = $0354
PS_PT      = $0360       ; pattern, 0 = free
HSX        = $0370       ; the shots checked in this frame (half of them): x, y, slot
HSY        = $0378
HSI        = $0380

; ---------------- terrain ----------------
TROWS      = $0400       ; 3 material rows ($00, $20, $40), 2 block rows ($60, $80)
A_MAT      = $04A0       ; shapes being drawn (12): material | $80 blob
A_COL      = $04AC       ;   column (signed)
A_W        = $04B8       ;   width or blob number
A_I        = $04C4       ;   row of the shape to draw next
A_H        = $04D0       ;   height
NACTMAX    = 12
VIEW       = $0800       ; ring of 32 name rows (map row & 31)

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
HUDBUF     = $06C0       ; 32: the bottom row

; ---------------- parameters ----------------
BTN_MASK    = %00110000
STEP_FR     = 2          ; frames per 2-pixel step
FIRE_T      = 8          ; frames between shots with the button held
FIRE_TF     = 6          ;   with the full ship
CHG_MAX     = 160        ; power units (4 frames each) to recharge
FORM_T      = 90         ; formation: 6 s
FULL_T      = 225        ; full ship: 15 s
TUG_X       = 120
TUG_Y       = 182        ; y + 32

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 29         ; fixed zone of the game in the save area
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
SPR_PAGES = 4           ; (LOAD_SPRITES of lib_tile is not used)


 .org $0FD0               ; trampoline called by NMI_HANDLER (bios) with JSR $0FD0
DISPATCH:
  JMP NMI_TASK


 .org $1000
RESET:
  SEI
  LDX #$FF
  TXS
  STZ VINT                     ; VDP interrupt off
  JSR VDP_INIT
  STZ AREA
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
;  TITLE: the name, the modules, what things are worth
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR SHOW_T0
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

; rows 9-18 of the title and the tug with its modules beside them (VDP interrupt off)
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

; one frame of the title: the flame of the tug flickers;
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
  LDA SATB                     ; the sprites are there: the flame
  CMP #2
  BCC .tf_e
  LDA FRAME_CNT
  AND #4
  CLC
  ADC #PT_TUG
  STA SAT_BUFFER+2
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: area 1, 3 ships for every player
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
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ AREA
  STZ LOOPN
  STZ CPI
  STZ NMOD
  LDA #$02                     ; first extra ship at 20000
  STA NEXTX
  LDA #1
  STA FRESH
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then the area from its checkpoint
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

STAGE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR SHOW_T0
  JSR LOAD_COLS                ; the colours of the area
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT                   ; the tune: first turn or a new area
  ORA FRESH
  BEQ .ss_short
  STZ FIRSTT
  LDA AREA                     ; songs 1-4: the areas
  INC A
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ss_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ss_t
  LDA #30
  JSR WAIT_FRAMES
  BRA .ss_w
.ss_short:
  LDA #W_READY
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_FRAMES
.ss_w:
  JSR VDP_INT_OFF
  STZ FRESH
  STZ GSTATE
  LDA #CMD_GAME
  STA SND_CMD
  JSR LEVEL_START
  JSR BUILD_SAT
  JSR VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR SCROLL                   ; rows of the hidden table, the 2-pixel step
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  LDA GSTATE
  BNE .gl_ns
  JSR PLAYER
.gl_ns:
  JSR SHOTS
  JSR OBJECTS
  JSR HITS
  JSR CHECKPT
  LDA FILLR                    ; the HUD waits while the hidden table is written
  CMP #23
  BCC .gl_h
  JSR UPDATE_HUD
.gl_h:
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT                       ; lost or cleared: the explosions go on
  BNE GAME_LOOP
  LDA GSTATE
  CMP #3
  BEQ .gl_win
  JMP LOSE_LIFE
.gl_win:
  JMP AREA_CLEAR


; ===============================================================
;  THE FORTRESS IS DOWN: bonus for the modules, the next area
; ===============================================================
AREA_CLEAR:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  LDA VIS                      ; the messages on the table shown (the ground stops)
  ASL A
  ASL A
  STA HOFF
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  LDA AREA
  INC A
  ORA #$30
  STA VDATA
  LDA #<TXT_CLEAR2
  STA TP
  LDA #>TXT_CLEAR2
  STA TP+1
  JSR PRINT
  LDA #5                       ; the tune of the end of the area
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
  LDA #60
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF              ; bonus: 1000 for every module docked
  LDA #<TXT_MBONUS
  STA TP
  LDA #>TXT_MBONUS
  STA TP+1
  JSR PRINT
  LDA NMOD
  ORA #$30
  STA VDATA
  LDA #<TXT_MBONUS2
  STA TP
  LDA #>TXT_MBONUS2
  STA TP+1
  JSR PRINT
  LDA NMOD
  BEQ .ac_n
  ORA #$30
  STA VDATA
  LDA #<TXT_000
  STA TP
  LDA #>TXT_000
  STA TP+1
  JSR PRINT
  LDA NMOD                     ; NMOD x 1000: BCD thousands
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA #0
  JSR ADD_PTS
  BRA .ac_s
.ac_n:
  LDA #'0'
  STA VDATA
.ac_s:
  JSR UPDATE_HUD
  STZ HOFF
  JSR VDP_INT_ON
.ac_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ac_t
  LDA #90
  JSR WAIT_FRAMES
  LDA #1                       ; the next area; after the fourth, the round again
  STA FRESH
  STZ CPI
  INC AREA
  LDA AREA
  CMP #4
  BCC .ac_e
  STZ AREA
  LDA LOOPN
  CMP #8
  BCS .ac_e
  INC LOOPN
.ac_e:
  JSR SAVE_PLAYER
  JMP STAGE_START

LOSE_LIFE:
  LDX CURP
  DEC LIVES,X
  STZ NMOD
  JSR SAVE_PLAYER
  LDA #30
  JSR WAIT_FRAMES
  LDA NPL                      ; the other player, if he still has ships
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
  JMP TURN_START

GAME_OVER:
  LDA #W_OVER
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR SHOW_T0
  JSR CLEAR_NT
  JSR DRAW_TOP
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
  TXA                          ; extra byte: the area reached (round x 4 + area + 1)
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE+1,Y
  ASL A
  ASL A
  SEC
  ADC PSAVE,Y
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
  JSR SHOW_T0
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
REC_NAME:  .byte "SKY TUG         "
REC_HEAD:  .byte "BEST PILOTS",0
REC_XLBL:  .byte "AREA ",0


; ===============================================================
;  INTRO: player, area, ships
; ===============================================================
INTRO:
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDX NPL
  CPX #2
  BNE .in_g
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.in_g:
  LDA #<TXT_AREA
  STA TP
  LDA #>TXT_AREA
  STA TP+1
  JSR PRINT
  JSR PUT_AREA
  LDX #13                      ; the name of the area (18 characters)
  LDY #7
  JSR NT_XY
  LDA AREA
  ASL A
  ASL A
  ASL A
  ASL A
  ADC AREA
  ADC AREA
  TAX
  LDY #18
.in_n:
  LDA AREA_TXT,X
  STA VDATA
  INX
  DEY
  BNE .in_n
  LDA #<TXT_SHIPS
  STA TP
  LDA #>TXT_SHIPS
  STA TP+1
  JSR PRINT
  LDX CURP
  LDA LIVES,X
  ORA #$30
  STA VDATA
  RTS

; "R-A" where the VDP points: round and area
PUT_AREA:
  LDA LOOPN
  CLC
  ADC #$31
  STA VDATA
  LDA #'-'
  NOP
  STA VDATA
  LDA AREA
  CLC
  ADC #$31
  STA VDATA
  RTS


; ===============================================================
;  HUD: row 0 (scores) and row 23 (ships, power, area), in both
;  name tables while playing
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
  LDX #0
  LDY #22
  JSR NT_XY
  LDA #'2'
  STA VDATA
  LDA #'U'
  NOP
  STA VDATA
  LDA #'P'
  NOP
  STA VDATA
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

; the bottom row into HUDBUF: SHIPS n  POWER ========  AREA r-a
MAKE_BOT:
  LDX #31
.mb_c:
  LDA TXT_BOT,X
  STA HUDBUF,X
  DEX
  BPL .mb_c
  LDX CURP
  LDA LIVES,X
  ORA #$30
  STA HUDBUF+6
  LDA LOOPN
  CLC
  ADC #$31
  STA HUDBUF+29
  LDA AREA
  CLC
  ADC #$31
  STA HUDBUF+31
  LDA MODE                     ; the label: power, or the mode running
  BEQ .mb_p
  ASL A
  ASL A
  ASL A
  TAY
  LDX #0
.mb_m:
  LDA TXT_MODES-8,Y
  STA HUDBUF+9,X
  INY
  INX
  CPX #5
  BNE .mb_m
.mb_p:
  LDX #0                       ; the cells: '=' full, '-' empty
.mb_b:
  LDA #'-'
  CPX CHGC
  BCS .mb_w
  LDA #'='
.mb_w:
  STA HUDBUF+15,X
  INX
  CPX #8
  BNE .mb_b
  RTS

; HUDBUF to row 23 of the table HOFF
PUT_BOT:
  LDX #23
  LDY #0
  JSR NT_XY
  LDX #0
.pb_c:
  LDA HUDBUF,X
  STA VDATA
  INX
  CPX #32
  BNE .pb_c
  RTS

; both rows in both tables (VDP interrupt off)
DRAW_HUD:
  JSR MAKE_BOT
  STZ HOFF
  JSR DRAW_TOP
  JSR PUT_BOT
  LDA #4
  STA HOFF
  JSR DRAW_TOP
  JSR PUT_BOT
  STZ HOFF
  RTS

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 bottom row
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  PHA
  AND #1
  BEQ .uh_b
  STZ HOFF
  LDX CURP
  JSR DRAW_SCORE
  LDA #4
  STA HOFF
  LDX CURP
  JSR DRAW_SCORE
.uh_b:
  PLA
  AND #2
  BEQ .uh_e
  JSR MAKE_BOT
  STZ HOFF
  JSR PUT_BOT
  LDA #4
  STA HOFF
  JSR PUT_BOT
.uh_e:
  STZ HOFF
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP
  LDA CURP
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA AREA,Y
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
  ASL A
  TAX
  LDY #0
.lp_b:
  LDA PSAVE,X
  STA AREA,Y
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

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a ship more at 20000, then every 50000
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
  LDA LIVES,X                  ; at most 9 (one digit on the HUD)
  CMP #9
  BCS .as_m
  INC LIVES,X
.as_m:
  SED
  LDA NEXTX
  CLC
  ADC #$05
  CLD
  BCC .as_x
  LDA #$FF                     ; past 990000: no more
.as_x:
  STA NEXTX
  LDA #2                       ; the new ship on the HUD
  TSB HUDD
  LDA #W_EXTRA
  LDX #1
  JSR SFX_WHISTLE
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  THE WORLD: the terrain built row by row, the scrolling, the
;  objects of the area, the checkpoints
; ===============================================================

; the title / intro view: name table 0 at phase 0 (VDP interrupt off)
SHOW_T0:
  STZ HOFF
  STZ VIS
  STZ VR4
  LDA #$0E
  STA VR2
  STA VREG
  LDA #(VDP_REGISTER_BITS | 2)
  STA VREG
  LDA #0
  STA VREG
  LDA #(VDP_REGISTER_BITS | 4)
  STA VREG
  RTS

; the colours of the area AREA to $2800
LOAD_COLS:
  LDA #$00
  STA VREG
  LDA #($28 | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDA AREA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #32
.lc_c:
  LDA COLTABS,X
  STA VDATA
  INX
  DEY
  BNE .lc_c
  RTS

; ---------------------------------------------------------------
; the start of a turn: the terrain from the checkpoint CPI, both
; name tables, the HUD, the tug (VDP interrupt off)
; ---------------------------------------------------------------
LEVEL_START:
  LDX #NOB-1
.ls_o:
  STZ O_K,X
  STZ O_F,X
  DEX
  BPL .ls_o
  LDX #NPS-1
.ls_s:
  STZ PS_PT,X
  DEX
  BPL .ls_s
  LDA #$FF
  STA BOSSI
  STZ BCANS
  LDX AREA                     ; the checkpoint: PTR = AR_CP + CPI * 6
  LDA AR_CP_LO,X
  STA PTR
  LDA AR_CP_HI,X
  STA PTR+1
  LDA CPI
  ASL A
  ADC CPI
  ASL A
  CLC
  ADC PTR
  STA PTR
  BCC .ls_p
  INC PTR+1
.ls_p:
  LDY #0                       ; its row: GS
  LDA (PTR),Y
  STA GS
  INY
  LDA (PTR),Y
  STA GS+1
  INY                          ; the shapes and the objects from there
  LDA (PTR),Y
  CLC
  ADC AR_SH_LO,X
  STA SHP
  INY
  LDA (PTR),Y
  ADC AR_SH_HI,X
  STA SHP+1
  INY
  LDA (PTR),Y
  CLC
  ADC AR_OB_LO,X
  STA OBP
  INY
  LDA (PTR),Y
  ADC AR_OB_HI,X
  STA OBP+1
  JSR SET_NCP
  LDX #159                     ; material and block rows: sea
.ls_m:
  STZ TROWS,X
  DEX
  CPX #$FF
  BNE .ls_m
  STZ NACT
  LDA #>TROWS
  STA PMN+1
  STA PMC+1
  STA PMS+1
  STA PBN+1
  STA PBO+1
  LDA #$00
  STA PMN
  LDA #$20
  STA PMC
  LDA #$40
  STA PMS
  LDA #$60
  STA PBN
  LDA #$80
  STA PBO
  LDA GS                       ; the view: VT = checkpoint + 21
  CLC
  ADC #21
  STA VT
  LDA GS+1
  ADC #0
  STA VT+1
  LDA #26                      ; names up to row VT + 2
  STA T7
.ls_r:
  JSR NEXT_ROW
  DEC T7
  BNE .ls_r
  STZ PH
  STZ VIS
  STZ VR4
  LDA #$0E
  STA VR2
  LDA #STEP_FR
  STA SCNT
  LDA #$38                     ; table 0: the view VT, table 1: VT + 1
  STA T1
  LDA VT
  STA T3
  JSR FILL_TABLE
  LDA #$3C
  STA T1
  LDA VT
  INC A
  STA T3
  JSR FILL_TABLE
  LDA #23
  STA FILLR
  STZ NRPEND
  LDA #$0E                     ; show table 0 now
  STA VREG
  LDA #(VDP_REGISTER_BITS | 2)
  STA VREG
  LDA #0
  STA VREG
  LDA #(VDP_REGISTER_BITS | 4)
  STA VREG
  ; the tug
  LDA #TUG_X
  STA SX
  LDA #TUG_Y
  STA SY
  STZ MODE
  STZ MTIME
  STZ FIRET
  STZ ANG
  LDA #CHG_MAX
  STA CHG
  LDA #8
  STA CHGC
  LDA #120
  STA INVT
  ; the difficulty: more fire with the area and the round
  LDA LOOPN
  ASL A
  ASL A
  ASL A
  ADC #6
  STA T0
  LDA AREA
  ASL A
  ADC T0
  CMP #40
  BCC .ls_f
  LDA #40
.ls_f:
  STA FIRECH
  LDA LOOPN
  INC A
  CMP #4
  BCC .ls_b
  LDA #4
.ls_b:
  STA BSPD
  STZ HUDD
  JMP DRAW_HUD

; NCP = row of checkpoint CPI + 1 ($FFFF after the last); X = AREA
SET_NCP:
  LDX AREA
  LDA #$FF
  STA NCP
  STA NCP+1
  LDA CPI
  INC A
  CMP AR_NCP,X
  BCS .sn_r
  STA T0
  ASL A
  ADC T0
  ASL A
  TAY
  LDA AR_CP_LO,X
  STA PTR2
  LDA AR_CP_HI,X
  STA PTR2+1
  LDA (PTR2),Y
  STA NCP
  INY
  LDA (PTR2),Y
  STA NCP+1
.sn_r:
  RTS

; the bottom row of the view passed the next checkpoint: start from there next time
CHECKPT:
  LDA GSTATE
  BNE .ck_r
  LDA VT                       ; T0/T1 = VT - 21
  SEC
  SBC #21
  STA T0
  LDA VT+1
  SBC #0
  STA T1
  LDA T0
  CMP NCP
  LDA T1
  SBC NCP+1
  BCC .ck_r
  INC CPI
  JMP SET_NCP
.ck_r:
  RTS

; ---------------------------------------------------------------
; one more row of the map: material row GS (from the shapes),
; block row GS-1, name row GS-2 into VIEW; then GS + 1
; ---------------------------------------------------------------
NEXT_ROW:
  LDA PMS                      ; the oldest material row becomes the newest
  LDX PMC
  STX PMS
  LDX PMN
  STX PMC
  STA PMN
  LDY #31
  LDA #0
.nr_z:
  STA (PMN),Y
  DEY
  BPL .nr_z
.nr_ev:                        ; the shapes that start on row GS
  LDY #1
  LDA (SHP),Y
  CMP GS+1
  BNE .nr_evd
  DEY
  LDA (SHP),Y
  CMP GS
  BNE .nr_evd
  LDX NACT
  CPX #NACTMAX
  BCS .nr_skip
  LDY #2
  LDA (SHP),Y
  STA A_MAT,X
  INY
  LDA (SHP),Y
  STA A_COL,X
  INY
  LDA (SHP),Y
  STA A_W,X
  INY
  LDA (SHP),Y
  STA A_H,X
  STZ A_I,X
  INC NACT
.nr_skip:
  LDA SHP
  CLC
  ADC #6
  STA SHP
  BCC .nr_ev
  INC SHP+1
  BRA .nr_ev
.nr_evd:
  LDX #0                       ; ---- paint the shapes, in their order
.nr_sh:
  CPX NACT
  BCC .nr_sh1
  JMP .nr_blk
.nr_sh1:
  LDA A_MAT,X
  BPL .nr_rect
  LDY A_W,X                    ; a blob: row A_I of shape A_W (left offset, width)
  LDA SHAPE_LO,Y
  STA PTR
  LDA SHAPE_HI,Y
  STA PTR+1
  LDA A_I,X
  ASL A
  TAY
  LDA (PTR),Y
  CLC
  ADC A_COL,X
  STA T0
  INY
  LDA (PTR),Y
  STA T1
  BRA .nr_pt
.nr_rect:
  LDA A_COL,X
  STA T0
  LDA A_W,X
  STA T1
.nr_pt:
  LDA T0                       ; end = left + width (signed), at most 32
  CLC
  ADC T1
  BMI .nr_nx
  CMP #33
  BCC .nr_e
  LDA #32
.nr_e:
  STA T2
  LDA T0                       ; start at least 0
  BPL .nr_s
  LDA #0
.nr_s:
  CMP T2
  BCS .nr_nx
  TAY
  LDA T2
  SEC
  SBC T0
  BIT T0
  BPL .nr_c
  CLC                          ; started left of the screen: fewer cells
  ADC T0
.nr_c:
  STA T4
  LDA A_MAT,X
  AND #$7F
.nr_pl:
  STA (PMN),Y
  INY
  DEC T4
  BNE .nr_pl
.nr_nx:
  INC A_I,X                    ; next row of the shape; done: out of the list
  LDA A_I,X
  CMP A_H,X
  BCC .nr_keep
  PHX
.nr_rm:
  INX
  CPX NACT
  BCS .nr_rmd
  LDA A_MAT,X
  STA A_MAT-1,X
  LDA A_COL,X
  STA A_COL-1,X
  LDA A_W,X
  STA A_W-1,X
  LDA A_I,X
  STA A_I-1,X
  LDA A_H,X
  STA A_H-1,X
  BRA .nr_rm
.nr_rmd:
  PLX
  DEC NACT
  JMP .nr_sh
.nr_keep:
  INX
  JMP .nr_sh
.nr_blk:                       ; ---- block row GS-1 (material PMC, north PMN, south PMS)
  LDA PBO
  LDX PBN
  STX PBO
  STA PBN
  LDA GS
  SEC
  SBC #1
  AND #1
  STA T5                       ; parity of the row: the two variants
  LDY #0
.nr_bc:
  LDA (PMC),Y
  BNE .nr_bl
  TYA                          ; sea
  EOR T5
  AND #1
  BRA .nr_bput
.nr_bl:
  CMP #1
  BEQ .nr_land
  TAX                          ; road, metal, roof
  LDA MATBLK,X
  BRA .nr_bput
.nr_land:                      ; land: its corners cut where the sea is beside
  LDX #0
  LDA (PMN),Y
  BEQ .nr_n
  LDX #8
.nr_n:
  STX T6
  LDA (PMS),Y
  BEQ .nr_so
  LDA #4
  TSB T6
.nr_so:
  CPY #0
  BEQ .nr_wl
  DEY
  LDA (PMC),Y
  INY
  TAX
  BEQ .nr_ws
.nr_wl:
  LDA #2
  TSB T6
.nr_ws:
  CPY #31
  BEQ .nr_el
  INY
  LDA (PMC),Y
  DEY
  TAX
  BEQ .nr_es
.nr_el:
  LDA #1
  TSB T6
.nr_es:
  LDX T6
  LDA LANDCUT,X
  CMP #$FF
  BNE .nr_bput
  TYA
  EOR T5
  AND #1
  ORA #2
.nr_bput:
  STA (PBN),Y
  INY
  CPY #32
  BNE .nr_bc
  LDA GS                       ; ---- names of row GS-2: pair (block above, block)
  SEC
  SBC #2
  JSR VIEW_PTR
  LDY #0
.nr_nc:
  LDA (PBN),Y
  ASL A
  ASL A
  ASL A
  ASL A
  ORA (PBO),Y
  TAX
  LDA PAIRNAME,X
  STA (PTR),Y
  INY
  CPY #32
  BNE .nr_nc
  INC GS
  BNE .nr_r
  INC GS+1
.nr_r:
  RTS

; A = map row: PTR = its row in VIEW
VIEW_PTR:
  AND #31
  PHA
  LSR A
  LSR A
  LSR A
  CLC
  ADC #>VIEW
  STA PTR+1
  PLA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA PTR
  RTS

; ---------------------------------------------------------------
; row FILLR (1-22) of the table at page T1 ($38 / $3C) from the
; VIEW row T2
; ---------------------------------------------------------------
PUT_VROW:
  LDA FILLR
  LSR A
  LSR A
  LSR A
  CLC
  ADC T1
  ORA #VDP_WRITE_VRAM_BIT
  TAX
  LDA FILLR
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA VREG
  STX VREG
  LDA T2
  JSR VIEW_PTR
  LDY #0
.pv_c:
  LDA (PTR),Y                  ; 12 cycles between the writes
  STA VDATA
  INY
  CPY #32
  BNE .pv_c
  RTS

; every row 1-22 of the table at page T1, map row T3 on screen row 1
FILL_TABLE:
  LDA #1
  STA FILLR
.ft_l:
  LDA T3
  INC A
  SEC
  SBC FILLR
  STA T2
  JSR PUT_VROW
  INC FILLR
  LDA FILLR
  CMP #23
  BNE .ft_l
  RTS

; ---------------------------------------------------------------
; every frame: 4 rows of the hidden table (the view VT + 1), then
; the 2-pixel step; every 4 steps the hidden table is shown, the
; next map row is built and the objects that come into view start
; ---------------------------------------------------------------
SCROLL:
  LDA #4
  STA T7
  LDA FILLR                    ; the table ready since the frame before: the map row
  CMP #23
  BCS .sc_nr
.sc_f:
  LDA FILLR
  CMP #23
  BCS .sc_st
  LDA VIS                      ; the hidden table
  EOR #1
  ASL A
  ASL A
  ORA #$38
  STA T1
  LDA VT
  CLC
  ADC #2
  SEC
  SBC FILLR
  STA T2
  JSR PUT_VROW
  INC FILLR
  DEC T7
  BNE .sc_f
  BRA .sc_st
.sc_nr:
  LDA NRPEND                   ; the table is ready: the next map row (VT + 2)
  BEQ .sc_st
  STZ NRPEND
  JSR NEXT_ROW
.sc_st:
  DEC SCNT
  BNE .sc_r
  LDA #STEP_FR
  STA SCNT
  LDA PH
  CMP #3
  BNE .sc_ph
  LDA FILLR                    ; the hidden table not ready yet: wait a frame
  CMP #23
  BCC .sc_late
  LDA NRPEND
  BNE .sc_late
  JSR GROUND_STEP
  STZ PH
  STZ VR4
  INC VT
  BNE .sc_v
  INC VT+1
.sc_v:
  LDA VIS
  EOR #1
  STA VIS
  CLC
  ADC #$0E
  STA VR2
  LDA #1
  STA NRPEND
  STA FILLR
  JMP SPAWN
.sc_ph:
  INC PH
  LDA PH
  STA VR4
  JMP GROUND_STEP
.sc_late:
  LDA #1
  STA SCNT
.sc_r:
  RTS

; the ground objects go down with the terrain
GROUND_STEP:
  LDX #NOB-1
.gs_l:
  LDY O_K,X
  BEQ .gs_n
  LDA KFLAG,Y
  AND #F_GROUND
  BEQ .gs_n
  LDA O_Y,X
  CLC
  ADC #2
  STA O_Y,X
  CMP #224
  BCC .gs_n
  STZ O_K,X
  STZ O_F,X
.gs_n:
  DEX
  BPL .gs_l
  RTS

; ---------------------------------------------------------------
; the objects of the area whose row came into view (row <= VT + 1)
; ---------------------------------------------------------------
SPAWN:
  LDY #1
  LDA (OBP),Y
  CMP #$FF
  BEQ .sp_r
  STA T1
  DEY
  LDA (OBP),Y
  STA T0
  LDA VT                       ; VT + 1 - row: borrow = not yet
  CLC
  ADC #1
  STA T2
  LDA VT+1
  ADC #0
  STA T3
  LDA T2
  CMP T0
  LDA T3
  SBC T1
  BCC .sp_r
  LDY #2
  LDA (OBP),Y
  STA T4                       ; type
  INY
  LDA (OBP),Y
  STA T5                       ; x
  JSR SPAWN_ONE
  LDA OBP
  CLC
  ADC #4
  STA OBP
  BCC SPAWN
  INC OBP+1
  BRA SPAWN
.sp_r:
  RTS

; T4 = type, T5 = x: a wave in the air, an object on the ground, the fortress
SPAWN_ONE:
  LDA T4
  CMP #K_FIGHTER
  BEQ SP_FIGHTERS
  CMP #K_HAWK
  BEQ SP_HAWKS
  CMP #K_DRONE
  BNE .so_1
  JMP SP_DRONES
.so_1:
  CMP #K_BOMBER
  BNE .so_2
  JMP SP_BOMBER
.so_2:
  CMP #K_BOSS
  BNE .so_3
  JMP SP_BOSS
.so_3:
  LDA T5                       ; on the ground: just in view (y = -8)
  STA T2
  LDA #24
  STA T3
  LDA T4
  JSR NEW_OBJ
  BCS .so_r
  LDA T4                       ; tanks and boats: a side and a time
  CMP #K_TANK
  BEQ .so_m
  CMP #K_BOAT
  BNE .so_r
.so_m:
  JSR NEXT_RND
  AND #63
  ORA #64
  STA O_P,X
  AND #1
  TAY
  LDA T4
  CMP #K_BOAT
  BNE .so_t
  INY
  INY
.so_t:
  LDA GVX_L,Y
  STA O_VXL,X
  LDA GVX_H,Y
  STA O_VXH,X
.so_r:
  RTS

; five fighters in a V
SP_FIGHTERS:
  LDX #4
.sf_l:
  PHX
  LDA T5
  CLC
  ADC VWAVE_X,X
  STA T2
  LDA VWAVE_Y,X
  STA T3
  LDA #K_FIGHTER
  JSR NEW_OBJ
  BCS .sf_n
  LDA #$40                     ; 1.25 pixels a frame down
  STA O_VYL,X
  LDA #1
  STA O_VYH,X
.sf_n:
  PLX
  DEX
  BPL .sf_l
  RTS

; three hawks side by side
SP_HAWKS:
  LDX #2
.sh_l:
  PHX
  LDA T5
  CLC
  ADC HWAVE_X,X
  STA T2
  LDA #16
  STA T3
  LDA #K_HAWK
  JSR NEW_OBJ
  BCS .sh_n
  LDA #2
  STA O_VYH,X
  PLA
  PHA
  ASL A
  ASL A
  ASL A
  ADC #24
  STA O_P,X                    ; frames down before the spiral
  LDA #8
  STA O_D,X
.sh_n:
  PLX
  DEX
  BPL .sh_l
  RTS

; three drones that stop and fire
SP_DRONES:
  LDX #2
.sd_l:
  PHX
  LDA T5
  CLC
  ADC DWAVE_X,X
  STA T2
  LDA #16
  STA T3
  LDA #K_DRONE
  JSR NEW_OBJ
  BCS .sd_n
  LDA #$80
  STA O_VYL,X
  LDA #1
  STA O_VYH,X
  JSR NEXT_RND
  AND #31
  ADC #60
  STA O_P,X                    ; where it stops
.sd_n:
  PLX
  DEX
  BPL .sd_l
  RTS

SP_BOMBER:
  LDA T5
  STA T2
  LDA #16
  STA T3
  LDA #K_BOMBER
  JSR NEW_OBJ
  BCS .sb_r
  LDA #$80
  STA O_VYL,X
.sb_r:
  RTS

; the flying fortress and its two cannons
SP_BOSS:
  LDA T5
  STA T2
  LDA #8
  STA T3
  LDA #K_BOSS
  JSR NEW_OBJ
  BCS .sbo_r
  STX BOSSI
  LDA #$80
  STA O_VYL,X
  LDA LOOPN                    ; harder in the later rounds
  ASL A
  ASL A
  ASL A
  CLC
  ADC O_H,X
  STA O_H,X
  STZ T7
.sbo_c:
  LDA #K_BCAN
  JSR NEW_OBJ
  BCS .sbo_n
  LDA T7
  STA O_P,X
  LDA LOOPN
  ASL A
  ASL A
  CLC
  ADC O_H,X
  STA O_H,X
  INC BCANS
.sbo_n:
  INC T7
  LDA T7
  CMP #2
  BNE .sbo_c
  LDA #W_ALARM
  LDX #1
  JSR SFX_WHISTLE
.sbo_r:
  RTS

; A = kind, T2 = x, T3 = y: a new object in X (C = 1: no free slot)
NEW_OBJ:
  PHA
  LDX #NOB-1
.no_f:
  LDA O_K,X
  BEQ .no_ok
  DEX
  BPL .no_f
  PLA
  SEC
  RTS
.no_ok:
  PLA
  STA O_K,X
  TAY
  LDA KHITS,Y
  STA O_H,X
  LDA KFLAG,Y
  STA O_F,X
  LDA T2
  STA O_X,X
  LDA T3
  STA O_Y,X
  STZ O_XF,X
  STZ O_YF,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_S,X
  STZ O_P,X
  STZ O_D,X
  JSR NEXT_RND                 ; the first shot: not at once
  AND #63
  ADC #30
  STA O_T,X
  CLC
  RTS


; ===============================================================
;  THE TUG: moves, power, formation, full ship, fire
; ===============================================================
PLAYER:
  LDA JOYC                     ; 2 pixels a frame, 8 directions
  AND #1
  BEQ .pl_d
  LDA SY
  CMP #50
  BCC .pl_d
  SBC #2
  STA SY
.pl_d:
  LDA JOYC
  AND #2
  BEQ .pl_l
  LDA SY
  CMP #198
  BCS .pl_l
  ADC #2
  STA SY
.pl_l:
  LDA JOYC
  AND #4
  BEQ .pl_r
  LDA SX
  CMP #6
  BCC .pl_r
  SBC #2
  STA SX
.pl_r:
  LDA JOYC
  AND #8
  BEQ .pl_i
  LDA SX
  CMP #234
  BCS .pl_i
  ADC #2
  STA SX
.pl_i:
  LDA INVT
  BEQ .pl_t
  DEC INVT
.pl_t:
  LDA FRAME_CNT                ; every 4 frames: the mode runs out or the power grows
  AND #3
  BNE .pl_b
  LDA MODE
  BEQ .pl_c
  DEC MTIME
  BNE .pl_b
  JSR END_MODE
  BRA .pl_b
.pl_c:
  LDA CHG
  CMP #CHG_MAX
  BCS .pl_b
  INC CHG
  JSR CHG_CELLS
.pl_b:
  LDA JOYC                     ; button 2 pressed now: formation or full ship
  AND #$20
  BEQ .pl_f
  LDA JOYP
  AND #$20
  BNE .pl_f
  LDA MODE
  BNE .pl_f
  LDA CHG
  CMP #CHG_MAX
  BCC .pl_f
  LDA NMOD
  CMP #2
  BCC .pl_f
  STZ CHG
  STZ CHGC
  CMP #4
  BEQ .pl_full
  LDA #1
  STA MODE
  LDA #FORM_T
  STA MTIME
  LDA #W_FORM
  BRA .pl_ms
.pl_full:
  LDA #2
  STA MODE
  LDA #FULL_T
  STA MTIME
  LDA #W_FULL
.pl_ms:
  LDX #1
  JSR SFX_WHISTLE
  LDA #2
  TSB HUDD
.pl_f:
  INC ANG                      ; the formation turns
  LDA FIRET
  BEQ .pl_k
  DEC FIRET
.pl_k:
  LDA JOYC                     ; button 1 held: fire
  AND #$10
  BEQ .pl_e
  LDA FIRET
  BNE .pl_e
  LDA #FIRE_T
  LDX MODE
  CPX #2
  BNE .pl_ft
  LDA #FIRE_TF
.pl_ft:
  STA FIRET
  JMP FIRE
.pl_e:
  RTS

END_MODE:
  STZ MODE
  STZ MTIME
  LDA #2
  TSB HUDD
  RTS

; CHGC = CHG / 20 (cells of the power bar); the HUD again if it changed
CHG_CELLS:
  LDA CHG
  LDX #0
.cc_l:
  CMP #20
  BCC .cc_d
  SBC #20
  INX
  BRA .cc_l
.cc_d:
  CPX CHGC
  BEQ .cc_r
  STX CHGC
  LDA #2
  TSB HUDD
.cc_r:
  RTS

; the tug fires up; every module fires its own way
FIRE:
  LDA #W_SHOT
  LDX #0
  JSR SFX_WHISTLE
  LDA MODE
  CMP #2
  BEQ .fi_full
  LDA SX
  STA T0
  LDA SY
  SEC
  SBC #6
  STA T1
  LDA #0
  JSR ADD_SHOT
  LDX #0
.fi_m:
  CPX NMOD
  BCS .fi_r
  JSR MODPOS
  LDA MODE
  BEQ .fi_fix
  JSR MOD_ANGLE                ; formation: out from the tug
  LSR A
  LSR A
  BRA .fi_a
.fi_fix:
  LDA MOD_DIR,X
.fi_a:
  PHX
  JSR ADD_SHOT
  PLX
  INX
  BRA .fi_m
.fi_r:
  RTS
.fi_full:                      ; the full ship: a fan of six
  LDX #0
.fi_fl:
  LDA SX
  CLC
  ADC FULL_OX,X
  STA T0
  LDA SY
  CLC
  ADC FULL_OY,X
  STA T1
  LDA FULL_D,X
  PHX
  JSR ADD_SHOT
  PLX
  INX
  CPX #6
  BNE .fi_fl
  RTS

; A = direction 0-15, T0 / T1 = x / y: a shot (if a slot is free)
ADD_SHOT:
  AND #15
  TAY
  LDX #NPS-1
.as_f:
  LDA PS_PT,X
  BEQ .as_ok
  DEX
  BPL .as_f
  RTS
.as_ok:
  LDA T0
  STA PS_X,X
  LDA T1
  STA PS_Y,X
  LDA SDX,Y
  STA PS_DX,X
  LDA SDY,Y
  STA PS_DY,X
  LDA SPAT,Y
  STA PS_PT,X
  RTS

; X = module 0-3: T0 / T1 = where it is (keeps X)
MODPOS:
  LDA MODE
  CMP #1
  BEQ .mp_o
  LDA SX
  CLC
  ADC MOFX,X
  STA T0
  LDA SY
  CLC
  ADC MOFY,X
  STA T1
  RTS
.mp_o:
  JSR MOD_ANGLE
  TAY
  LDA SX
  CLC
  ADC SIN24,Y
  STA T0
  TYA
  CLC
  ADC #16
  AND #63
  TAY
  LDA SY
  SEC
  SBC SIN24,Y
  STA T1
  RTS

; X = module: A = its angle in the formation (keeps X)
MOD_ANGLE:
  LDY NMOD
  LDA FSPC,Y
  STA T2
  LDA ANG
  PHX
.ma_l:
  DEX
  BMI .ma_d
  CLC
  ADC T2
  BRA .ma_l
.ma_d:
  PLX
  AND #63
  RTS

; the shots of the tug fly on
SHOTS:
  LDX #NPS-1
.sh_l:
  LDA PS_PT,X
  BEQ .sh_n
  LDA PS_X,X
  CLC
  ADC PS_DX,X
  STA PS_X,X
  CMP #248
  BCS .sh_k
  LDA PS_Y,X
  CLC
  ADC PS_DY,X
  STA PS_Y,X
  CMP #12
  BCC .sh_k
  CMP #224
  BCC .sh_n
.sh_k:
  STZ PS_PT,X
.sh_n:
  DEX
  BPL .sh_l
  RTS


; ===============================================================
;  HITS: shots against the objects, the objects against the tug
; ===============================================================
HITS:
  LDX #0                       ; the shots of this frame: even or odd slots (they
  LDA FRAME_CNT                ; move 6 pixels, the boxes are 20 wide)
  AND #1
  TAY
.hi_sl:
  LDA PS_PT,Y
  BEQ .hi_sn
  LDA PS_X,Y
  STA HSX,X
  LDA PS_Y,Y
  STA HSY,X
  TYA
  STA HSI,X
  INX
.hi_sn:
  INY
  INY
  CPY #NPS
  BCC .hi_sl
  STX HN
  CPX #0
  BEQ .hi_tug
  LDX #NOB-1
.hi_o:
  LDA O_F,X
  AND #F_SHOOT
  BEQ .hi_on
  LDA #20                      ; the box: 20 x 20, the fortress 32 x 32
  STA T1
  LDA #10
  STA T3
  LDA O_K,X
  CMP #K_BOSS
  BNE .hi_nb
  LDA #32
  STA T1
  LDA #8
  STA T3
.hi_nb:
  LDA O_X,X
  SEC
  SBC T3
  STA T0
  LDA O_Y,X
  SEC
  SBC T3
  STA T2
  LDY HN
.hi_s:
  DEY
  BMI .hi_on
  LDA HSX,Y
  SEC
  SBC T0
  CMP T1
  BCS .hi_s
  LDA HSY,Y
  SEC
  SBC T2
  CMP T1
  BCS .hi_s
  LDA #$80                     ; hit: the shot goes
  STA HSY,Y
  LDA HSI,Y
  TAY
  LDA #0
  STA PS_PT,Y
  JSR HIT_OBJ
.hi_on:
  DEX
  BPL .hi_o
.hi_tug:
  LDA GSTATE                   ; ---- the tug
  BNE .hi_r
  LDA INVT
  BNE .hi_r
  LDX #NOB-1
.hi_t:
  LDA O_F,X
  AND #F_HARM
  BEQ .hi_tn
  LDA O_K,X
  CMP #K_BOSS
  BEQ .hi_tb
  LDA O_F,X
  AND #F_BULLET
  BNE .hi_tbu
  LDA SX                       ; an enemy: 11 pixels
  SEC
  SBC O_X,X
  CLC
  ADC #11
  CMP #22
  BCS .hi_tn
  LDA SY
  SEC
  SBC O_Y,X
  CLC
  ADC #11
  CMP #22
  BCS .hi_tn
  JMP TUG_TOUCH
.hi_tbu:                       ; a bullet: 6 pixels
  LDA SX
  SEC
  SBC O_X,X
  CLC
  ADC #6
  CMP #12
  BCS .hi_tn
  LDA SY
  SEC
  SBC O_Y,X
  CLC
  ADC #6
  CMP #12
  BCS .hi_tn
  JMP TUG_TOUCH
.hi_tb:                        ; the fortress
  LDA SX
  SEC
  SBC O_X,X
  CLC
  ADC #10
  CMP #36
  BCS .hi_tn
  LDA SY
  SEC
  SBC O_Y,X
  CLC
  ADC #10
  CMP #34
  BCS .hi_tn
  JMP TUG_TOUCH
.hi_tn:
  DEX
  BPL .hi_t
.hi_r:
  RTS

; X = what touched the tug
TUG_TOUCH:
  LDA O_K,X
  STA DEATH
  LDA O_F,X
  AND #F_BULLET
  BEQ .tt_e
  STZ O_K,X                    ; a bullet
  STZ O_F,X
  LDA MODE
  CMP #2
  BNE TUG_HIT
  JSR END_MODE                 ; the full ship: it only ends the mode
  LDA #60
  STA INVT
  LDA #W_CLINK
  LDX #1
  JMP SFX_WHISTLE
.tt_e:
  LDA O_K,X
  CMP #K_BOSS
  BEQ .tt_b
  CMP #K_BCAN
  BEQ .tt_b
  LDA #1                       ; the enemy goes down too
  STA O_H,X
  JSR HIT_OBJ
  LDA MODE
  CMP #2
  BNE TUG_HIT
  RTS                          ; the full ship rams it
.tt_b:
  LDA MODE
  CMP #2
  BNE TUG_HIT
  RTS

; a hit: the last module goes, without modules the tug
TUG_HIT:
  LDA NMOD
  BEQ SHIP_LOST
  DEC NMOD
  LDA #90
  STA INVT
  LDA #2
  TSB HUDD
  LDA #W_LOSE
  LDX #1
  JSR SFX_WHISTLE
  LDA MODE
  CMP #1
  BNE .th_r
  LDA NMOD
  CMP #2
  BCS .th_r
  JMP END_MODE
.th_r:
  RTS

SHIP_LOST:
  LDA #1
  STA GSTATE
  LDA #150
  STA GT
  INC LOSTN
  STZ MODE
  LDA SX
  STA T2
  LDA SY
  STA T3
  LDA #K_BOOM
  JSR NEW_OBJ
  LDA #W_DIE
  LDX #1
  JSR SFX_WHISTLE
  LDA #S_BIG
  LDY SX
  JMP BOOM_AT

; X = object hit by a shot (keeps X)
HIT_OBJ:
  LDA O_K,X
  CMP #K_BOSS
  BNE .ho_h
  LDA BCANS                    ; the fortress is shielded while a cannon is left
  BEQ .ho_h
  PHX
  LDA #W_CLINK
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS
.ho_h:
  DEC O_H,X
  BEQ KILL_OBJ
  BMI KILL_OBJ
  PHX
  LDA #S_HIT
  LDY O_X,X
  JSR BOOM_AT
  PLX
  RTS

; X = object destroyed: points, explosion (keeps X)
KILL_OBJ:
  LDY O_K,X
  LDA KPTS_L,Y
  STA PTS_L
  LDA KPTS_M,Y
  STA PTS_M
  LDA KPTS_H,Y
  STA PTS_H
  JSR ADD_SCORE
  LDA O_K,X
  CMP #K_DEPOT
  BEQ .ko_dep
  CMP #K_BOSS
  BEQ .ko_boss
  CMP #K_BCAN
  BNE .ko_bm
  DEC BCANS
.ko_bm:
  PHX
  LDA #S_SMALL
  LDY O_X,X
  JSR BOOM_AT
  PLX
.ko_set:
  LDA O_F,X
  AND #F_GROUND
  BEQ .ko_air
  LDA #K_GBOOM
  JMP SET_KIND
.ko_air:
  LDA #K_BOOM
  JMP SET_KIND
.ko_dep:                       ; a depot: the module that comes next
  LDA NMOD
  CMP #4
  BCS .ko_full
  PHX
  LDA #W_CLINK
  LDX #1
  JSR SFX_WHISTLE
  PLX
  LDA #K_MODULE
  JMP SET_KIND
.ko_full:                      ; all four docked: 1000 more
  LDA #0
  LDY #$10
  JSR ADD_PTS
  PHX
  LDA #W_BONUS
  LDX #1
  JSR SFX_WHISTLE
  PLX
  BRA .ko_bm
.ko_boss:                      ; the fortress: four explosions, the area is clear
  LDA #$FF
  STA BOSSI
  LDA O_X,X
  STA T0
  LDA O_Y,X
  STA T1
  STZ O_K,X
  STZ O_F,X
  PHX
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
  LDA GSTATE
  BNE .ko_bq
  LDA #3
  STA GSTATE
  LDA #150
  STA GT
.ko_bq:
  LDY #3
.ko_bl:
  PHY
  LDA BOSS_QX,Y
  CLC
  ADC T0
  STA T2
  LDA BOSS_QY,Y
  CLC
  ADC T1
  STA T3
  LDA #K_BOOM
  JSR NEW_OBJ
  PLY
  DEY
  BPL .ko_bl
  PLX
  RTS

; X = object, A = its new kind (same place, still)
SET_KIND:
  STA O_K,X
  TAY
  LDA KFLAG,Y
  STA O_F,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_P,X
  STZ O_S,X
  RTS


; ===============================================================
;  OBJECTS: one routine per kind, X = slot (kept)
; ===============================================================
OBJECTS:
  LDX #NOB-1
.ob_l:
  LDA O_K,X
  BEQ .ob_n
  ASL A
  TAY
  LDA OBJ_JT-2,Y
  STA PTR
  LDA OBJ_JT-1,Y
  STA PTR+1
  JSR .ob_c
.ob_n:
  DEX
  BPL .ob_l
  RTS
.ob_c:
  JMP (PTR)

; fighters: down, then they turn towards the tug
OB_FIGHTER:
  LDA O_S,X
  BNE .of_m
  LDA SY
  SEC
  SBC #64
  BCC .of_m
  CMP O_Y,X
  BCS .of_m
  INC O_S,X
  LDA SX
  CMP O_X,X
  LDA #$C0
  LDY #0
  BCS .of_v
  LDA #$40
  LDY #$FF
.of_v:
  STA O_VXL,X
  TYA
  STA O_VXH,X
.of_m:
  JSR MAYBE_FIRE
  JMP MOVE_AIR

; hawks: down, a spiral, then a dive
OB_HAWK:
  LDA O_S,X
  BEQ .oh_dn
  CMP #1
  BEQ .oh_sp
  BRA .oh_mv
.oh_dn:
  DEC O_P,X
  BNE .oh_mv
  INC O_S,X
  LDA #64
  STA O_P,X
  BRA .oh_mv
.oh_sp:
  LDA FRAME_CNT
  AND #3
  BNE .oh_s2
  LDA O_X,X
  BMI .oh_ccw
  LDA O_D,X
  DEC A
  BRA .oh_sd
.oh_ccw:
  LDA O_D,X
  INC A
.oh_sd:
  AND #15
  STA O_D,X
  LDY #2
  JSR SET_VEL
.oh_s2:
  DEC O_P,X
  BNE .oh_mv
  INC O_S,X
  LDA #8
  LDY #4
  JSR SET_VEL
.oh_mv:
  JSR MAYBE_FIRE
  JMP MOVE_AIR

; drones: down to their place, hover and fire, then away
OB_DRONE:
  LDA O_S,X
  BNE .od_1
  LDA O_Y,X
  CMP O_P,X
  BCC .od_mv
  INC O_S,X
  LDA #180
  STA O_P,X
  STZ O_VYL,X
  STZ O_VYH,X
  BRA .od_mv
.od_1:
  CMP #1
  BNE .od_mv
  LDA #$80                     ; sway: +-0.5
  STA O_VXL,X
  LDA FRAME_CNT
  AND #32
  BEQ .od_l
  LDA #0
  BRA .od_s
.od_l:
  LDA #$FF
.od_s:
  STA O_VXH,X
  DEC O_P,X
  BNE .od_mv
  INC O_S,X
  STZ O_VXL,X
  STZ O_VXH,X
  LDA #2
  STA O_VYH,X
.od_mv:
  JSR MAYBE_FIRE
  JMP MOVE_AIR

OB_BOMBER:
  JSR MAYBE_FIRE
OB_MISSILE:
OB_EBUL:
  JMP MOVE_AIR

; tanks and boats: to and fro on the ground
OB_TANK:
OB_BOAT:
  DEC O_P,X
  BNE .ot_m
  JSR NEG_VX
  LDA #96
  STA O_P,X
.ot_m:
  CLC
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_X,X
  ADC O_VXH,X
  STA O_X,X
  CMP #8
  BCC .ot_rev
  CMP #232
  BCC OB_TURRET
.ot_rev:
  JSR NEG_VX
OB_TURRET:
  JMP MAYBE_FIRE

; launchers: one missile when they get near the tug
OB_LAUNCH:
  LDA O_S,X
  BNE .ol_r
  LDA O_Y,X
  CMP #96
  BCC .ol_r
  INC O_S,X
  LDA GSTATE
  BNE .ol_r
  LDA O_X,X
  STA T2
  LDA O_Y,X
  STA T3
  PHX
  LDA #K_MISSILE
  JSR NEW_OBJ
  BCS .ol_x
  JSR AIM_DIR
  LDY #2
  JSR SET_VEL
  LDA #S_LAUNCH
  LDY O_X,X
  JSR BOOM_AT
.ol_x:
  PLX
.ol_r:
OB_DEPOT:
  RTS

; a module: the tug docks it flying over it
OB_MODULE:
  LDA GSTATE
  BNE .om_r
  LDA SX
  SEC
  SBC O_X,X
  CLC
  ADC #12
  CMP #24
  BCS .om_r
  LDA SY
  SEC
  SBC O_Y,X
  CLC
  ADC #12
  CMP #24
  BCS .om_r
  STZ O_K,X
  STZ O_F,X
  LDA NMOD
  CMP #4
  BCS .om_s
  INC NMOD
.om_s:
  LDA #2
  TSB HUDD
  PHX
  LDA #W_DOCK
  LDX #1
  JSR SFX_WHISTLE
  PLX
.om_r:
  RTS

; explosions: 3 pictures, 8 frames each
OB_BOOM:
OB_GBOOM:
  INC O_P,X
  LDA O_P,X
  CMP #24
  BCC .ob_r
  STZ O_K,X
  STZ O_F,X
.ob_r:
  RTS

; the fortress: down, then to and fro; it fires when the cannons are gone
OB_BOSS:
  LDA O_S,X
  BNE .os_1
  LDA O_Y,X
  CMP #56
  BCC .os_mv
  INC O_S,X
  STZ O_VYL,X
  STZ O_VYH,X
  LDA #$C0
  STA O_VXL,X
  STZ O_VXH,X
.os_1:
  LDA O_X,X
  CMP #16
  BCS .os_2
  LDA #$C0
  STA O_VXL,X
  STZ O_VXH,X
  BRA .os_mv
.os_2:
  CMP #208
  BCC .os_mv
  LDA #$40
  STA O_VXL,X
  LDA #$FF
  STA O_VXH,X
.os_mv:
  LDA BCANS
  BNE .os_nf
  JSR MAYBE_FIRE
.os_nf:
  JMP MOVE_AIR

; the cannons of the fortress: beside it
OB_BCAN:
  LDY BOSSI
  BMI .oc_g
  LDA O_P,X
  BNE .oc_r
  LDA O_X,Y
  SEC
  SBC #12
  BRA .oc_x
.oc_r:
  LDA O_X,Y
  CLC
  ADC #28
.oc_x:
  STA O_X,X
  LDA O_Y,Y
  CLC
  ADC #12
  STA O_Y,X
  JMP MAYBE_FIRE
.oc_g:
  STZ O_K,X
  STZ O_F,X
  RTS

; ---------------------------------------------------------------
; helpers of the objects (all keep X)
; ---------------------------------------------------------------
; 8.8 speed added to the position; out of the screen: gone
MOVE_AIR:
  CLC
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_X,X
  ADC O_VXH,X
  STA O_X,X
  CMP #248
  BCS .ma_k
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  CMP #224
  BCS .ma_k
  CMP #4
  BCC .ma_k
  RTS
.ma_k:
  STZ O_K,X
  STZ O_F,X
  RTS

NEG_VX:
  LDA #0
  SEC
  SBC O_VXL,X
  STA O_VXL,X
  LDA #0
  SBC O_VXH,X
  STA O_VXH,X
  RTS

; a ready enemy on the screen fires now and then
MAYBE_FIRE:
  LDA O_T,X
  BEQ .mf_t
  DEC O_T,X
  RTS
.mf_t:
  LDA O_Y,X
  CMP #40
  BCC .mf_r
  CMP #184
  BCS .mf_r
  JSR NEXT_RND
  CMP FIRECH
  BCS .mf_r
  LDA #60
  STA O_T,X
  JMP FIRE_AT
.mf_r:
  RTS

; a bullet from object X at the tug
FIRE_AT:
  LDA GSTATE
  BNE .fa_r
  LDA O_X,X
  STA T2
  LDA O_Y,X
  STA T3
  LDA O_K,X
  CMP #K_BOSS
  BNE .fa_p
  LDA T2                       ; the fortress: from its core
  CLC
  ADC #8
  STA T2
  LDA T3
  CLC
  ADC #16
  STA T3
.fa_p:
  PHX
  LDA #K_EBUL
  JSR NEW_OBJ
  BCS .fa_x
  JSR AIM_DIR
  LDY BSPD
  JSR SET_VEL
.fa_x:
  PLX
.fa_r:
  RTS

; X = object: A = the direction 0-15 to the tug
AIM_DIR:
  LDA SX                       ; dx / 2 and dy / 2, signed
  SEC
  SBC O_X,X
  ROR A
  EOR #$80
  STA T0
  LDA SY
  SEC
  SBC O_Y,X
  ROR A
  EOR #$80
  STA T1
  ; fall into AIM
; T0 = dx, T1 = dy (signed): A = direction 0-15 clockwise from up
AIM:
  LDA T0
  BPL .ai_x
  EOR #$FF
  INC A
.ai_x:
  STA T4
  LDA T1
  BPL .ai_y
  EOR #$FF
  INC A
.ai_y:
  STA T5
.ai_sc:                        ; small enough for x 5 in a byte
  LDA T4
  CMP #51
  BCS .ai_h
  LDA T5
  CMP #51
  BCC .ai_go
.ai_h:
  LSR T4
  LSR T5
  BRA .ai_sc
.ai_go:
  STZ T6                       ; steps away from the vertical: tan 11, 34, 56, 79 degrees
  LDA T4
  ASL A
  ASL A
  ADC T4
  CMP T5
  BCC .ai_d
  INC T6
  LDA T5
  ASL A
  STA T7
  LDA T4
  ASL A
  ADC T4
  CMP T7
  BCC .ai_d
  INC T6
  LDA T5
  ASL A
  ADC T5
  STA T7
  LDA T4
  ASL A
  CMP T7
  BCC .ai_d
  INC T6
  LDA T5
  ASL A
  ASL A
  ADC T5
  STA T7
  LDA T4
  CMP T7
  BCC .ai_d
  INC T6
.ai_d:
  LDA T1
  BMI .ai_up
  LDA T0
  BMI .ai_dl
  LDA #8
  SEC
  SBC T6
  RTS
.ai_dl:
  LDA #8
  CLC
  ADC T6
  RTS
.ai_up:
  LDA T0
  BMI .ai_ul
  LDA T6
  RTS
.ai_ul:
  LDA #16
  SEC
  SBC T6
  AND #15
  RTS

; X = object, A = direction 0-15, Y = speed code (0 = 1, 1 = 1.5,
; 2 = 2, 3 = 2.5, 4 = 3 pixels a frame)
SET_VEL:
  STY T6
  TAY
  LDA DIRX_L,Y
  STA T2
  LDA DIRX_H,Y
  STA T3
  JSR MULV
  LDA T4
  STA O_VXL,X
  LDA T5
  STA O_VXH,X
  LDA DIRY_L,Y
  STA T2
  LDA DIRY_H,Y
  STA T3
  JSR MULV
  LDA T4
  STA O_VYL,X
  LDA T5
  STA O_VYH,X
  RTS

; T4/T5 = T2/T3 x (T6 + 2) / 2
MULV:
  STZ T4
  STZ T5
  LDA T6
  CLC
  ADC #2
  STA SMT1
.mu_l:
  CLC
  LDA T4
  ADC T2
  STA T4
  LDA T5
  ADC T3
  STA T5
  DEC SMT1
  BNE .mu_l
  LDA T5
  CMP #$80
  ROR T5
  ROR T4
  RTS


; ===============================================================
;  SPRITES: the tug group and the objects take turns at the front
;  (more than 4 on a line: they flicker instead of vanishing)
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA FRAME_CNT
  AND #1
  BEQ .bs_t
  JSR SAT_OBJS
  JSR SAT_TUG
  BRA .bs_e
.bs_t:
  JSR SAT_TUG
  JSR SAT_OBJS
.bs_e:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  INC RR
  LDA RR
  CMP #NOB
  BCC .bs_r
  STZ RR
.bs_r:
  RTS

; OX, OY (+32), ON, OC: one sprite more, if there is room (keeps X)
ADD_SPR:
  LDY SPRI
  CPY #128
  BCS .ad_r
  LDA OY
  SEC
  SBC #33
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
.ad_r:
  RTS

; the tug (blinking after a hit), its modules, its shots
SAT_TUG:
  LDA GSTATE
  BNE .st_sh
  LDA INVT
  AND #4
  BNE .st_sh
  LDA SX
  STA OX
  LDA SY
  STA OY
  LDA FRAME_CNT                ; the flame
  AND #4
  CLC
  ADC #PT_TUG
  STA ON
  LDA #15
  LDY MODE
  CPY #2
  BNE .st_c
  LDA FRAME_CNT
  AND #8
  BEQ .st_w
  LDA #11
  BRA .st_c
.st_w:
  LDA #15
.st_c:
  STA OC
  JSR ADD_SPR
  LDX #0
.st_m:
  CPX NMOD
  BCS .st_sh
  JSR MODPOS
  LDA T0
  STA OX
  LDA T1
  STA OY
  TXA
  ASL A
  ASL A
  CLC
  ADC #PT_MOD2
  STA ON
  LDA #7
  LDY MODE
  BEQ .st_mc
  LDA #11
.st_mc:
  STA OC
  JSR ADD_SPR
  INX
  BRA .st_m
.st_sh:
  LDA #11
  STA OC
  LDX #NPS-1
.st_s:
  LDA PS_PT,X
  BEQ .st_sn
  STA ON
  LDA PS_X,X
  STA OX
  LDA PS_Y,X
  STA OY
  JSR ADD_SPR
.st_sn:
  DEX
  BPL .st_s
  RTS

; the objects, starting from RR
SAT_OBJS:
  LDX RR
  LDA #NOB
  STA T7
.so_l:
  LDA O_K,X
  BEQ .so_n
  TAY
  LDA KCOL,Y
  STA OC
  LDA KPAT,Y
  STA ON
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
  CPY #K_BOSS
  BEQ .so_boss
  CPY #K_HAWK
  BNE .so_1
  LDA FRAME_CNT                ; the wings
  AND #8
  BEQ .so_put
  LDA #PT_HAWK1
  STA ON
  BRA .so_put
.so_1:
  CPY #K_BOOM
  BEQ .so_bm
  CPY #K_GBOOM
  BNE .so_2
.so_bm:
  LDA O_P,X                    ; the three pictures of an explosion
  LSR A
  LSR A
  LSR A
  ASL A
  ASL A
  ADC #PT_BOOM
  STA ON
  BRA .so_put
.so_2:
  CPY #K_MODULE
  BNE .so_put
  LDA NMOD                     ; the number of the module that comes
  CMP #4
  BCC .so_mn
  LDA #3
.so_mn:
  ASL A
  ASL A
  ADC #PT_MOD2
  STA ON
  LDA FRAME_CNT
  AND #8
  BEQ .so_put
  LDA #15
  STA OC
.so_put:
  JSR ADD_SPR
.so_n:
  INX
  CPX #NOB
  BCC .so_w
  LDX #0
.so_w:
  DEC T7
  BNE .so_l
  RTS
.so_boss:                      ; four quarters
  JSR ADD_SPR
  LDA OX
  CLC
  ADC #16
  STA OX
  LDA #PT_BOSS1
  STA ON
  JSR ADD_SPR
  LDA OY
  CLC
  ADC #16
  STA OY
  LDA #PT_BOSS3
  STA ON
  JSR ADD_SPR
  LDA OX
  SEC
  SBC #16
  STA OX
  LDA #PT_BOSS2
  STA ON
  JSR ADD_SPR
  BRA .so_n


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from dune ranger)
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

; the table GFX_LOAD (four pattern tables with the font and the big
; letters, sprites, name tables), then the pairs of the terrain and the colours
LOAD_GFX:
  LDA #<GFX_LOAD
  STA PTR2
  LDA #>GFX_LOAD
  STA PTR2+1
  JSR LOAD_BLOCKS
  JSR BUILD_PAIRS
  JMP LOAD_COLS

; every pair of blocks in the four pattern tables: table o shows the
; 16 rows (upper block, lower block) from row 8 - 2o
BUILD_PAIRS:
  LDA #<PMASK
  STA PTR
  LDA #>PMASK
  STA PTR+1
  LDX #0
.bp_p:
  LDA PNAME,X
  ASL A
  ASL A
  ASL A
  STA T1                       ; low byte of name * 8
  LDA PNAME,X
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  STA T2                       ; high byte of name * 8
  STZ T3
.bp_o:
  LDA T1
  STA VREG
  LDA T3
  ASL A
  ASL A
  ASL A
  CLC
  ADC T2
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  LDA T3
  ASL A
  STA T5
  LDA #8
  SEC
  SBC T5
  TAY
  LDA #8
  STA T4
.bp_b:
  LDA (PTR),Y
  STA VDATA
  INY
  DEC T4
  BNE .bp_b
  INC T3
  LDA T3
  CMP #4
  BNE .bp_o
  LDA PTR
  CLC
  ADC #16
  STA PTR
  BCC .bp_n
  INC PTR+1
.bp_n:
  INX
  CPX #NPAIRS
  BNE .bp_p
  RTS

; the registers (interrupt off): Graphics I, 16x16 sprites, names $3800,
; colours $2800, patterns $0000, SAT $3B00, sprite patterns $2000, black
VDP_INIT:
  LDX #0
.vi_r:
  LDA VREGS,X
  STA VREG
  TXA
  ORA #VDP_REGISTER_BITS
  STA VREG
  INX
  CPX #8
  BNE .vi_r
  STZ VR4
  LDA #$0E
  STA VR2
  RTS
VREGS:      .byte $00,$C2,$0E,$A0,$00,$76,$04,$01

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
  LDA VR4                 ; the terrain: phase and name table, with the sprites
  STA VREG
  LDA #(VDP_REGISTER_BITS | 4)
  STA VREG
  LDA VR2
  STA VREG
  LDA #(VDP_REGISTER_BITS | 2)
  STA VREG
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
SC_COL:     .byte 4,26                         ; score of player 1 / 2: column on row 0

; per kind (0-16): flags, hits, pattern, colour, points (BCD)
;                 -   FIG HAWK DRN BOMB MIS TANK TUR BOAT LNCH DEP MOD BOOM GBM BOSS CAN BUL
KFLAG:      .byte 0,   6,  6,  6,  6,  6,  3,  3,  3,  3,  3,  1,  0,  1,  6,  6,  12
KHITS:      .byte 0,   1,  1,  2,  6,  1,  1,  2,  2,  2,  4,  0,  0,  0,  24, 10, 0
KPAT:       .byte 0,PT_FIGHTER,PT_HAWK,PT_DRONE,PT_BOMBER,PT_MISSILE,PT_TANK,PT_TURRET,PT_BOAT
            .byte PT_LAUNCH,PT_DEPOT,PT_MOD2,PT_BOOM,PT_BOOM,PT_BOSS,PT_CANNON,PT_EBUL
KCOL:       .byte 0,   9, 13,  7, 14, 15,  1,  6, 15,  1, 11,  7, 10, 10, 14,  6,  15
KPTS_L:     .byte 0, $50,$00,$50,$00,$00,$00,$00,$00,$00,$00,  0,  0,  0,$00,$00,  0
KPTS_M:     .byte 0, $00,$01,$01,$03,$01,$02,$03,$02,$04,$05,  0,  0,  0,$00,$10,  0
KPTS_H:     .byte 0,   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,$01,  0,  0
OBJ_JT:     .word OB_FIGHTER,OB_HAWK,OB_DRONE,OB_BOMBER,OB_MISSILE,OB_TANK,OB_TURRET,OB_BOAT
            .word OB_LAUNCH,OB_DEPOT,OB_MODULE,OB_BOOM,OB_GBOOM,OB_BOSS,OB_BCAN,OB_EBUL

; ground speeds: tank right / left, boat right / left (8.8)
GVX_L:      .byte $80,$80,$40,$C0
GVX_H:      .byte $00,$FF,$00,$FF
; waves: offsets of the fighters (a V), the hawks, the drones
VWAVE_X:    .byte $E0,$F0,$00,$10,$20
VWAVE_Y:    .byte 8,16,24,16,8
HWAVE_X:    .byte $E8,$00,$18
DWAVE_X:    .byte $E0,$00,$20

; the shots of the tug in 16 directions: pixels a frame, pattern
SDX:        .byte 0,2,4,6,6,6,4,2,0,$FE,$FC,$FA,$FA,$FA,$FC,$FE
SDY:        .byte $FA,$FA,$FC,$FE,0,2,4,6,6,6,4,2,0,$FE,$FC,$FA
SPAT:       .byte PT_SHOT,PT_BALL,PT_BALL,PT_BALL,PT_BALL,PT_BALL,PT_BALL,PT_BALL
            .byte PT_SHOT,PT_BALL,PT_BALL,PT_BALL,PT_BALL,PT_BALL,PT_BALL,PT_BALL
; the modules docked: front, left, right, rear (offsets, direction of fire)
MOFX:       .byte $00,$F4,$0C,$00
MOFY:       .byte $F4,$04,$04,$0C
MOD_DIR:    .byte 0,14,2,8
FSPC:       .byte 0,0,32,21,16                 ; formation: angle between the modules
; the full ship: six shots
FULL_OX:    .byte $FA,$06,$F4,$0C,$F4,$0C
FULL_OY:    .byte $F8,$F8,$04,$04,$04,$04
FULL_D:     .byte 0,0,15,1,14,2
BOSS_QX:    .byte 0,16,0,16
BOSS_QY:    .byte 0,0,16,16

; title: the tug and its four modules (sprite Y, X, pattern, colour)
TITLE_NS = 5
TITLE_SY:   .byte 95,83,99,99,107
TITLE_SX:   .byte 208,208,196,220,208
TITLE_SN:   .byte PT_TUG,PT_MOD2,PT_MOD3,PT_MOD4,PT_MOD5
TITLE_SC:   .byte 15,7,7,7,7

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 0,12,"HI",0
  .byte $FF
TXT_BUTTONS:
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,2,"DOCK THE MODULES",0
  .byte 10,2,"FROM THE DEPOTS",0
  .byte 12,2,"B1 FIRE",0
  .byte 13,2,"B2 FORMATION",0
  .byte 14,2,"   4 MODULES FULL SHIP",0
  .byte 16,2,"FIGHTER  50  HAWK  100",0
  .byte 17,2,"DRONE   150  TANK  200",0
  .byte 18,2,"TURRET  300  BOSS 10000",0
  .byte $FF
TXT_BOT:
  .byte "SHIPS 0  POWER -------- AREA 1-1"
TXT_MODES:
  .byte "FORM    FULL    "
TXT_PLAYER:
  .byte 8,12,"PLAYER ",0,$FF
TXT_AREA:
  .byte 11,12,"AREA ",0,$FF
TXT_SHIPS:
  .byte 16,12,"SHIPS ",0,$FF
TXT_CLEAR:
  .byte 9,10,"AREA ",0,$FF
TXT_CLEAR2:
  .byte 9,16," CLEAR",0,$FF
TXT_MBONUS:
  .byte 12,7,"MODULES ",0,$FF
TXT_MBONUS2:
  .byte 12,16,"  BONUS ",0,$FF
TXT_000:
  .byte 12,25,"000",0,$FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 13,11,"PLAYER ",0,$FF

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
;  GRAPHICS, TERRAIN, AREAS AND SOUND TABLES (generated)
; ===============================================================
; SKY TUG: generated by dev/gen_sky_tug.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_TUG = 0
PT_TUG1 = 4
PT_MOD2 = 8
PT_MOD3 = 12
PT_MOD4 = 16
PT_MOD5 = 20
PT_SHOT = 24
PT_BALL = 28
PT_EBUL = 32
PT_FIGHTER = 36
PT_HAWK = 40
PT_HAWK1 = 44
PT_DRONE = 48
PT_BOMBER = 52
PT_MISSILE = 56
PT_TANK = 60
PT_TURRET = 64
PT_BOAT = 68
PT_LAUNCH = 72
PT_DEPOT = 76
PT_BOOM = 80
PT_BOOM1 = 84
PT_BOOM2 = 88
PT_BOSS = 92
PT_BOSS1 = 96
PT_BOSS2 = 100
PT_BOSS3 = 104
PT_CANNON = 108
SPR_LEN = 896
SPRITES:
  .byte $01,$03,$02,$06,$07,$0D,$1D,$3F,$7F,$77,$67,$07,$02,$06,$00,$00,$80,$C0,$40,$60,$E0,$B0,$B8,$FC,$FE,$EE,$E6,$E0,$40,$60,$00,$00
  .byte $01,$03,$02,$06,$07,$0D,$1D,$3F,$7F,$77,$67,$07,$02,$06,$01,$02,$80,$C0,$40,$60,$E0,$B0,$B8,$FC,$FE,$EE,$E6,$E0,$40,$60,$80,$40
  .byte $04,$04,$04,$0F,$1F,$1F,$1C,$1F,$1C,$1D,$1C,$1F,$1F,$0F,$00,$00,$20,$20,$20,$F0,$F8,$F8,$78,$78,$78,$F8,$78,$F8,$F8,$F0,$00,$00
  .byte $C0,$E0,$60,$0F,$1F,$1F,$1C,$1F,$1C,$1F,$1C,$1F,$1F,$0F,$00,$00,$00,$00,$00,$F0,$F8,$F8,$78,$78,$78,$78,$78,$F8,$F8,$F0,$00,$00
  .byte $00,$00,$00,$0F,$1F,$1F,$1D,$1D,$1C,$1F,$1F,$1F,$1F,$0F,$00,$00,$03,$07,$06,$F0,$F8,$F8,$78,$78,$78,$78,$78,$F8,$F8,$F0,$00,$00
  .byte $00,$00,$00,$0F,$1F,$1F,$1C,$1D,$1C,$1F,$1C,$1F,$1F,$0F,$03,$01,$00,$00,$00,$F0,$F8,$F8,$78,$F8,$78,$78,$78,$F8,$F8,$F0,$C0,$80
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$03,$07,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$20,$30,$38,$3F,$1F,$0E,$07,$03,$01,$00,$00,$00,$00,$00,$00,$00,$04,$0C,$1C,$FC,$F8,$70,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$40,$60,$39,$1E,$0F,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$02,$06,$9C,$78,$F0,$C0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$3F,$7F,$FB,$C3,$83,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$FC,$FE,$DF,$C3,$C1,$80,$00,$00,$00,$00
  .byte $00,$00,$07,$1F,$38,$73,$73,$38,$1F,$07,$11,$20,$00,$00,$00,$00,$00,$00,$E0,$F8,$1C,$CE,$CE,$1C,$F8,$E0,$88,$04,$00,$00,$00,$00
  .byte $00,$01,$03,$07,$8F,$DF,$FF,$FF,$7F,$1F,$0E,$0C,$07,$03,$00,$00,$00,$80,$C0,$E0,$F1,$FB,$FF,$FF,$FE,$F8,$70,$30,$E0,$C0,$00,$00
  .byte $00,$00,$01,$0D,$07,$03,$03,$03,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$80,$B0,$E0,$C0,$C0,$C0,$C0,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$3F,$2A,$3F,$30,$33,$37,$37,$33,$31,$31,$3F,$2A,$3F,$00,$00,$00,$FC,$54,$FC,$0C,$CC,$EC,$EC,$CC,$8C,$8C,$FC,$54,$FC,$00,$00
  .byte $00,$0F,$18,$33,$67,$4F,$4F,$67,$33,$19,$0E,$03,$01,$01,$00,$00,$00,$F0,$18,$CC,$E6,$F2,$F2,$E6,$CC,$98,$70,$C0,$80,$80,$00,$00
  .byte $00,$01,$03,$06,$04,$07,$05,$07,$06,$07,$04,$07,$03,$01,$00,$00,$00,$80,$C0,$60,$20,$E0,$A0,$E0,$60,$E0,$20,$E0,$C0,$80,$00,$00
  .byte $00,$1F,$30,$27,$2C,$29,$2B,$2B,$29,$2C,$27,$30,$1F,$00,$00,$00,$00,$F8,$0C,$E4,$34,$94,$D4,$D4,$94,$34,$E4,$0C,$F8,$00,$00,$00
  .byte $00,$00,$00,$07,$1F,$3B,$7B,$7F,$FF,$AA,$FF,$C0,$FF,$00,$00,$00,$00,$00,$00,$E0,$F8,$DC,$DE,$FE,$FF,$AA,$FF,$03,$FF,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$0F,$0F,$0F,$06,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$70,$E0,$70,$C0,$60,$00,$00,$00,$00,$00
  .byte $00,$02,$09,$03,$0E,$10,$08,$1A,$04,$48,$07,$26,$02,$0A,$04,$00,$00,$30,$40,$00,$54,$44,$90,$06,$44,$A4,$C0,$74,$CC,$50,$80,$00
  .byte $02,$0B,$10,$08,$25,$08,$41,$C2,$23,$0A,$00,$42,$04,$32,$08,$00,$40,$00,$00,$84,$02,$00,$99,$00,$02,$00,$04,$28,$44,$08,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$0F,$1F,$1B,$3B,$3F,$7F,$7F,$7F,$7F,$7F,$03,$03,$3F,$FF,$FF,$FF,$FF,$FF,$BB,$BB,$FF,$FF,$FF,$F8,$F3,$E7
  .byte $C0,$C0,$FC,$FF,$FF,$FF,$FF,$FF,$BB,$BB,$FF,$FF,$FF,$1F,$CF,$E7,$00,$00,$00,$00,$C0,$E0,$F0,$F8,$B8,$BC,$FC,$FE,$FE,$FE,$FE,$FE
  .byte $7F,$7F,$7F,$7F,$3F,$3F,$1F,$1F,$0F,$03,$03,$00,$00,$00,$00,$00,$E7,$EF,$E7,$E7,$F3,$F8,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$41,$41,$00
  .byte $E7,$F7,$E7,$E7,$CF,$1F,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$82,$82,$00,$FE,$FE,$FE,$FE,$FC,$FC,$F8,$F8,$F0,$C0,$C0,$00,$00,$00,$00,$00
  .byte $00,$0F,$1F,$38,$33,$37,$37,$33,$38,$1F,$0E,$06,$06,$06,$02,$00,$00,$F0,$F8,$1C,$CC,$EC,$EC,$CC,$1C,$F8,$70,$60,$60,$60,$40,$00

; terrain: 55 pairs of blocks, 12 colour pairs, 15 groups of 8 names
NPAIRS = 55
; name of every pair, then its masks (upper block, lower block)
PNAME:
  .byte $60,$68,$69,$6A,$6B,$6C,$61,$6D,$6E,$6F,$70,$71,$72,$88,$73,$74,$90,$98,$A0,$75,$89,$76,$77,$91,$99,$A1,$78,$79,$7A,$7B,$7C,$7D
  .byte $7E,$7F,$80,$81,$82,$83,$84,$85,$92,$93,$A8,$B0,$B8,$9A,$9B,$B1,$C0,$C8,$A2,$A3,$B9,$C9,$D0
PMASK:
  .byte $00,$00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$FC,$FE,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$7F,$FF,$FF,$7F,$3F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$FC,$FE,$FF,$FF,$FE,$FC,$F8
  .byte $00,$00,$00,$00,$00,$00,$0E,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$FC,$FE,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$7F,$FF,$FF,$7F,$3F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$FC,$FE,$FF,$FF,$FE,$FC,$F8
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$02,$00,$00,$00,$02,$00,$00,$00,$20,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$00,$00,$00,$20,$00,$00,$00,$20,$00,$00,$00,$02,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$F8,$FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F8,$FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F8,$FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8
  .byte $FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $1F,$3F,$7F,$FF,$FF,$7F,$3F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$7F,$FF,$FF,$7F,$3F,$1F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $F8,$FC,$FE,$FF,$FF,$FE,$FC,$F8,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$FC,$FE,$FF,$FF,$FE,$FC,$F8,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$00,$00,$00,$00,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$80,$80,$80,$88,$80,$80,$80,$FF,$80,$80,$80,$88,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$11,$01,$01,$01,$FF,$01,$01,$01,$11,$01,$01,$01,$FF
; name of the pair (block above * 16 + block)
PAIRNAME:
  .byte $61,$60,$61,$68,$69,$6A,$61,$61,$61,$61,$6B,$6C,$61,$61,$61,$61,$61,$61,$6D,$61,$6E,$6F,$61,$61,$61,$61,$70,$71,$61,$61,$61,$61
  .byte $61,$72,$61,$88,$61,$61,$73,$74,$61,$61,$61,$61,$61,$90,$98,$A0,$75,$61,$89,$61,$61,$61,$76,$77,$61,$61,$61,$61,$61,$91,$99,$A1
  .byte $61,$61,$78,$79,$61,$61,$7A,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$7B,$7C,$61,$61,$61,$7D,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $7E,$7F,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$80,$81,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $82,$83,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$84,$85,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$92,$93,$61,$61,$61,$61,$61,$61,$61,$61,$61,$A8,$B0,$B8
  .byte $61,$61,$9A,$9B,$61,$61,$61,$61,$61,$61,$61,$61,$61,$B1,$C0,$C8,$61,$61,$A2,$A3,$61,$61,$61,$61,$61,$61,$61,$61,$61,$B9,$C9,$D0
; block of a land cell from its neighbours (n s w e, 1 = land), $FF = plain land
LANDCUT:
  .byte $0C,$0A,$0B,$FF,$08,$04,$05,$FF,$09,$06,$07,$FF,$FF,$FF,$FF,$FF
MATBLK:
  .byte $00,$00,$0D,$0E,$0F
; colour tables of the four areas
COLTABS:
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$54,$24,$24,$24,$24,$C2,$E2,$E2,$62,$FE,$EE,$6E,$1E,$6E,$16,$F1,$B1,$B1,$91,$91
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$75,$A5,$A5,$A5,$A5,$BA,$EA,$7A,$EA,$FE,$7E,$EE,$47,$E7,$1E,$F1,$B1,$B1,$91,$91
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$41,$C1,$C1,$C1,$C1,$2C,$AC,$EC,$DC,$BA,$EA,$DA,$1E,$DE,$4D,$F1,$B1,$B1,$91,$91
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$41,$E1,$E1,$E1,$E1,$FE,$1E,$4E,$6E,$B1,$41,$61,$54,$64,$16,$F1,$B1,$B1,$91,$91
; blob shapes (islands): per row the left offset (signed) and the width
SHAPE_LO:
  .byte <SHP0,<SHP1,<SHP2,<SHP3,<SHP4,<SHP5,<SHP6,<SHP7,<SHP8,<SHP9,<SHP10,<SHP11,<SHP12,<SHP13,<SHP14,<SHP15
SHAPE_HI:
  .byte >SHP0,>SHP1,>SHP2,>SHP3,>SHP4,>SHP5,>SHP6,>SHP7,>SHP8,>SHP9,>SHP10,>SHP11,>SHP12,>SHP13,>SHP14,>SHP15
SHP0:
  .byte $FE,$06,$FD,$09,$FD,$09,$FD,$09,$FE,$09,$FF,$08,$FE,$07,$FD,$09,$FD,$09,$FC,$09,$FE,$06
SHP1:
  .byte $00,$05,$FE,$07,$FE,$07,$FF,$05,$FD,$08,$FD,$07,$FC,$07,$FA,$0B,$FB,$09,$FB,$08,$FB,$07,$FD,$05,$FD,$05,$FD,$07,$FE,$06
SHP2:
  .byte $FF,$03,$FD,$05,$FE,$03,$FD,$04,$FC,$05,$FB,$07,$FC,$07,$FC,$07,$FD,$08,$FE,$05,$FF,$05,$FF,$05,$FF,$05,$FF,$08,$FF,$07,$FF,$05
  .byte $FF,$05,$00,$03,$FF,$04,$FE,$05,$FD,$05,$FE,$03
SHP3:
  .byte $FE,$03,$FF,$01,$FE,$04,$FF,$03,$FE,$05,$FE,$07,$FE,$07,$FF,$06,$00,$05,$00,$05,$FF,$05,$FE,$07,$FD,$0A,$FD,$07,$FD,$07,$FD,$05
  .byte $FD,$05,$FB,$08,$FB,$07,$FC,$07,$FB,$09,$FD,$05,$FF,$04,$FF,$03,$00,$03,$00,$03,$FF,$05
SHP4:
  .byte $FF,$05,$FE,$08,$FC,$0B,$FB,$0F,$FB,$0F,$FA,$0F,$FB,$0E,$FC,$09,$FC,$09,$FC,$07
SHP5:
  .byte $FF,$06,$FE,$07,$FB,$0B,$FA,$0D,$F9,$0D,$F9,$0E,$F9,$0D,$F9,$0B,$F8,$0D,$F8,$0F,$F8,$10,$F9,$0D,$FB,$0B,$FC,$09,$FF,$05,$FF,$06
SHP6:
  .byte $FD,$05,$FB,$09,$F9,$0B,$F9,$0B,$FA,$0C,$FB,$09,$FA,$0B,$FA,$0D,$FA,$0D,$FA,$10,$FA,$0F,$FC,$0D,$FC,$0D,$FD,$0B,$FC,$0C,$FB,$0D
  .byte $FA,$0D,$FB,$0B,$FB,$09,$FC,$08,$FE,$03
SHP7:
  .byte $FD,$05,$FB,$09,$FC,$09,$FE,$08,$FD,$09,$FD,$09,$FE,$09,$FC,$0D,$FB,$0E,$FB,$0D,$FB,$0D,$FB,$0B,$FB,$0B,$F9,$0E,$F9,$0D,$F9,$0D
  .byte $F7,$0F,$F9,$0B,$FB,$0A,$FA,$0B,$FA,$0B,$FB,$0B,$FA,$0D,$FC,$0C,$FE,$07,$FF,$07,$00,$05,$00,$03
SHP8:
  .byte $FC,$0B,$FB,$0F,$FA,$12,$FA,$0F,$F9,$11,$F9,$11,$F9,$0F,$FB,$0C
SHP9:
  .byte $FE,$07,$FC,$0A,$FA,$0D,$F9,$0D,$F8,$0F,$F5,$13,$F5,$14,$F6,$11,$F7,$11,$F8,$0F,$F9,$0F,$F8,$12,$FA,$0F,$FA,$0F,$FB,$0D,$00,$05
SHP10:
  .byte $FC,$06,$FB,$07,$FA,$0B,$F9,$0D,$F8,$0F,$F8,$12,$F8,$11,$FA,$0F,$FA,$0F,$F9,$11,$FA,$12,$F9,$13,$F8,$13,$F9,$11,$FA,$0F,$F9,$10
  .byte $FA,$0D,$F9,$0D,$F9,$0D,$F9,$0B,$FB,$08
SHP11:
  .byte $FE,$05,$FD,$07,$FC,$0B,$FA,$0F,$FA,$10,$FB,$0F,$FB,$0F,$FB,$0D,$FA,$0F,$F8,$14,$F7,$13,$F6,$13,$F6,$13,$F7,$11,$F7,$10,$F6,$11
  .byte $F7,$11,$F6,$13,$F6,$13,$F8,$12,$F9,$0F,$FA,$0F,$FB,$0D,$FA,$0F,$FB,$10,$FC,$0D,$FC,$0B,$FD,$09,$00,$03
SHP12:
  .byte $FE,$09,$FA,$11,$F7,$15,$F6,$18,$F5,$17,$F6,$15,$F5,$15,$F5,$15,$F6,$14,$F5,$13,$F9,$0B
SHP13:
  .byte $FC,$09,$F7,$11,$F7,$12,$F6,$13,$F5,$13,$F5,$13,$F5,$15,$F4,$18,$F4,$17,$F5,$17,$F6,$15,$F9,$11,$FA,$10,$FC,$0D,$FE,$09
SHP14:
  .byte $FB,$07,$F9,$0E,$F9,$0D,$F9,$0D,$F9,$0F,$F8,$11,$F8,$14,$F6,$17,$F8,$15,$F9,$13,$F8,$13,$F8,$14,$F8,$13,$F5,$17,$F5,$17,$F5,$15
  .byte $F6,$14,$F7,$11,$F7,$0F,$F7,$0F,$F8,$0F,$FA,$0C,$FB,$09
SHP15:
  .byte $FE,$08,$FC,$0B,$FB,$0D,$FC,$0D,$FA,$11,$F7,$16,$F7,$15,$F7,$15,$F6,$15,$F7,$13,$F5,$16,$F4,$17,$F4,$17,$F2,$19,$F2,$19,$F5,$16
  .byte $F6,$13,$F6,$15,$F7,$13,$F7,$15,$F7,$16,$F9,$11,$FB,$0F,$FC,$0D,$FD,$09,$FE,$08

; areas: shapes (s0, material | $80 blob, column, id / width, height), objects (s0, type, x),
; checkpoints (row, offset of the shapes, offset of the objects)
AR_SH_LO:
  .byte <AR0_SH,<AR1_SH,<AR2_SH,<AR3_SH
AR_SH_HI:
  .byte >AR0_SH,>AR1_SH,>AR2_SH,>AR3_SH
AR_OB_LO:
  .byte <AR0_OB,<AR1_OB,<AR2_OB,<AR3_OB
AR_OB_HI:
  .byte >AR0_OB,>AR1_OB,>AR2_OB,>AR3_OB
AR_CP_LO:
  .byte <AR0_CP,<AR1_CP,<AR2_CP,<AR3_CP
AR_CP_HI:
  .byte >AR0_CP,>AR1_CP,>AR2_CP,>AR3_CP
AR_NCP:
  .byte $06,$05,$05,$05
AR0_SH:
  .byte $22,$00,$81,$11,$0D,$0F,$24,$00,$02,$13,$01,$05,$28,$00,$02,$11,$01,$05,$2A,$00,$04,$13,$02,$02
  .byte $41,$00,$81,$11,$0D,$0F,$43,$00,$04,$09,$02,$02,$44,$00,$02,$11,$01,$05,$4A,$00,$04,$11,$02,$02
  .byte $5B,$00,$81,$0D,$06,$15,$5F,$00,$81,$0C,$0F,$1A,$60,$00,$04,$0F,$02,$02,$63,$00,$04,$0A,$02,$02
  .byte $64,$00,$04,$0E,$02,$02,$67,$00,$02,$0E,$01,$05,$67,$00,$02,$13,$01,$05,$6B,$00,$02,$08,$01,$05
  .byte $6F,$00,$04,$05,$02,$02,$75,$00,$04,$0A,$02,$02,$A5,$00,$81,$14,$0A,$15,$C8,$00,$81,$13,$00,$0B
  .byte $C9,$00,$04,$14,$02,$02,$CC,$00,$04,$13,$02,$02,$CF,$00,$04,$12,$02,$02,$E2,$00,$81,$0E,$03,$1B
  .byte $23,$01,$81,$12,$0B,$1D,$26,$01,$04,$13,$02,$02,$27,$01,$02,$11,$01,$05,$2A,$01,$81,$0E,$07,$1C
  .byte $2D,$01,$04,$0E,$02,$02,$30,$01,$04,$14,$02,$02,$37,$01,$04,$0D,$02,$02,$3A,$01,$02,$0B,$01,$05
  .byte $56,$01,$81,$09,$07,$1C,$61,$01,$04,$0C,$02,$02,$61,$01,$04,$08,$02,$02,$64,$01,$04,$08,$02,$02
  .byte $6C,$01,$04,$0B,$02,$02,$7A,$01,$81,$15,$01,$0F,$80,$01,$81,$0E,$0C,$0B,$80,$01,$04,$14,$02,$02
  .byte $82,$01,$02,$0D,$01,$05,$83,$01,$04,$12,$02,$02,$84,$01,$04,$10,$02,$02,$B0,$01,$81,$04,$03,$1B
  .byte $D4,$01,$81,$0A,$08,$08,$D7,$01,$04,$08,$02,$02,$D8,$01,$04,$06,$02,$02,$D9,$01,$04,$0A,$02,$02
  .byte $EB,$01,$81,$0D,$0F,$1A,$EB,$01,$81,$17,$00,$0B,$ED,$01,$02,$0A,$01,$05,$EF,$01,$04,$0F,$02,$02
  .byte $F4,$01,$04,$06,$02,$02,$F4,$01,$02,$14,$01,$05,$FB,$01,$02,$13,$01,$05,$00,$02,$04,$13,$02,$02
  .byte $34,$02,$81,$14,$07,$1C,$3C,$02,$02,$15,$01,$05,$42,$02,$02,$13,$01,$05,$FF,$FF
AR0_OB:
  .byte $1E,$00,$08,$98,$20,$00,$01,$90,$28,$00,$06,$78,$2E,$00,$06,$A0,$33,$00,$02,$78,$39,$00,$01,$88,$46,$00,$03,$98,$49,$00,$07,$B8
  .byte $54,$00,$08,$70,$56,$00,$02,$98,$5C,$00,$04,$70,$68,$00,$06,$78,$69,$00,$06,$40,$6D,$00,$01,$B8,$80,$00,$02,$98,$A4,$00,$08,$40
  .byte $A5,$00,$06,$80,$A6,$00,$01,$28,$AA,$00,$06,$B0,$B9,$00,$03,$20,$C9,$00,$0A,$90,$C9,$00,$02,$68,$CA,$00,$08,$10,$D8,$00,$04,$50
  .byte $E4,$00,$01,$B0,$EE,$00,$06,$60,$EF,$00,$08,$B8,$F3,$00,$02,$20,$04,$01,$01,$88,$26,$01,$07,$68,$28,$01,$03,$30,$29,$01,$08,$10
  .byte $33,$01,$07,$60,$3A,$01,$02,$C0,$4E,$01,$04,$48,$54,$01,$08,$10,$56,$01,$01,$78,$64,$01,$02,$88,$6C,$01,$07,$40,$71,$01,$01,$A8
  .byte $7C,$01,$08,$80,$7D,$01,$03,$60,$83,$01,$06,$38,$90,$01,$02,$20,$AE,$01,$04,$58,$BB,$01,$0A,$30,$C0,$01,$01,$60,$C2,$01,$08,$C0
  .byte $CE,$01,$02,$50,$D4,$01,$01,$80,$D5,$01,$07,$30,$D8,$01,$07,$80,$E2,$01,$02,$90,$E5,$01,$03,$30,$F2,$01,$07,$48,$F2,$01,$04,$C0
  .byte $FF,$01,$07,$88,$FF,$01,$01,$B8,$09,$02,$08,$A8,$0B,$02,$02,$38,$2B,$02,$01,$70,$33,$02,$08,$28,$38,$02,$03,$68,$3F,$02,$07,$90
  .byte $45,$02,$02,$88,$46,$02,$06,$80,$59,$02,$04,$B0,$82,$02,$0E,$60,$FF,$FF
AR0_CP:
  .byte $00,$00,$00,$00,$00,$00,$86,$00,$6C,$00,$3C,$00,$09,$01,$90,$00,$74,$00,$93,$01,$02,$01,$B0,$00
  .byte $10,$02,$50,$01,$F0,$00,$5A,$02,$62,$01,$0C,$01
AR1_SH:
  .byte $1E,$00,$01,$05,$14,$13,$20,$00,$04,$0B,$02,$02,$20,$00,$04,$0F,$02,$02,$20,$00,$04,$13,$02,$02
  .byte $24,$00,$04,$07,$02,$02,$24,$00,$04,$0B,$02,$02,$28,$00,$04,$07,$02,$02,$28,$00,$04,$0B,$02,$02
  .byte $28,$00,$04,$0F,$02,$02,$2C,$00,$04,$07,$02,$02,$2C,$00,$04,$0F,$02,$02,$2C,$00,$04,$13,$02,$02
  .byte $36,$00,$81,$0D,$02,$16,$53,$00,$01,$0E,$0C,$0C,$55,$00,$04,$14,$02,$02,$6B,$00,$01,$02,$13,$0C
  .byte $6D,$00,$04,$08,$02,$02,$6D,$00,$04,$0C,$02,$02,$71,$00,$04,$04,$02,$02,$71,$00,$04,$0C,$02,$02
  .byte $71,$00,$04,$10,$02,$02,$79,$00,$81,$1A,$00,$0B,$A6,$00,$01,$0D,$0C,$0C,$A8,$00,$04,$0F,$02,$02
  .byte $A8,$00,$04,$13,$02,$02,$AC,$00,$04,$0F,$02,$02,$AC,$00,$04,$13,$02,$02,$B4,$00,$81,$07,$00,$0B
  .byte $CB,$00,$01,$05,$14,$14,$CD,$00,$04,$07,$02,$02,$CD,$00,$04,$0F,$02,$02,$D1,$00,$04,$07,$02,$02
  .byte $D1,$00,$04,$0B,$02,$02,$D1,$00,$04,$13,$02,$02,$D5,$00,$04,$0F,$02,$02,$D5,$00,$04,$13,$02,$02
  .byte $D9,$00,$04,$0B,$02,$02,$E4,$00,$81,$11,$01,$0F,$FD,$00,$01,$07,$0F,$16,$FF,$00,$04,$09,$02,$02
  .byte $FF,$00,$04,$0D,$02,$02,$FF,$00,$04,$11,$02,$02,$03,$01,$04,$0D,$02,$02,$03,$01,$04,$11,$02,$02
  .byte $07,$01,$04,$09,$02,$02,$07,$01,$04,$0D,$02,$02,$07,$01,$04,$11,$02,$02,$0B,$01,$04,$09,$02,$02
  .byte $0B,$01,$04,$0D,$02,$02,$0B,$01,$04,$11,$02,$02,$0F,$01,$04,$11,$02,$02,$19,$01,$81,$06,$02,$16
  .byte $57,$01,$01,$05,$14,$14,$59,$01,$04,$07,$02,$02,$59,$01,$04,$0B,$02,$02,$59,$01,$04,$0F,$02,$02
  .byte $59,$01,$04,$13,$02,$02,$5D,$01,$04,$07,$02,$02,$61,$01,$04,$0B,$02,$02,$61,$01,$04,$0F,$02,$02
  .byte $61,$01,$04,$13,$02,$02,$65,$01,$04,$07,$02,$02,$65,$01,$04,$13,$02,$02,$77,$01,$01,$05,$0E,$15
  .byte $79,$01,$04,$07,$02,$02,$79,$01,$04,$0B,$02,$02,$79,$01,$04,$0F,$02,$02,$7D,$01,$04,$07,$02,$02
  .byte $7D,$01,$04,$0B,$02,$02,$7D,$01,$04,$0F,$02,$02,$81,$01,$04,$07,$02,$02,$81,$01,$04,$0F,$02,$02
  .byte $85,$01,$04,$07,$02,$02,$85,$01,$04,$0B,$02,$02,$92,$01,$81,$09,$05,$10,$AE,$01,$01,$07,$14,$12
  .byte $B0,$01,$04,$0D,$02,$02,$B0,$01,$04,$11,$02,$02,$B0,$01,$04,$15,$02,$02,$B4,$01,$04,$09,$02,$02
  .byte $B4,$01,$04,$0D,$02,$02,$B4,$01,$04,$11,$02,$02,$B4,$01,$04,$15,$02,$02,$B8,$01,$04,$09,$02,$02
  .byte $B8,$01,$04,$0D,$02,$02,$B8,$01,$04,$11,$02,$02,$B8,$01,$04,$15,$02,$02,$BC,$01,$04,$09,$02,$02
  .byte $BC,$01,$04,$11,$02,$02,$BC,$01,$04,$15,$02,$02,$E6,$01,$01,$05,$0A,$13,$E8,$01,$04,$07,$02,$02
  .byte $E8,$01,$04,$0B,$02,$02,$EC,$01,$04,$07,$02,$02,$EC,$01,$04,$0B,$02,$02,$F0,$01,$04,$07,$02,$02
  .byte $F0,$01,$04,$0B,$02,$02,$F4,$01,$04,$07,$02,$02,$F4,$01,$04,$0B,$02,$02,$05,$02,$01,$0D,$0B,$13
  .byte $07,$02,$04,$0F,$02,$02,$07,$02,$04,$13,$02,$02,$0B,$02,$04,$0F,$02,$02,$0F,$02,$04,$0F,$02,$02
  .byte $0F,$02,$04,$13,$02,$02,$13,$02,$04,$0F,$02,$02,$13,$02,$04,$13,$02,$02,$23,$02,$01,$09,$10,$10
  .byte $25,$02,$04,$0B,$02,$02,$25,$02,$04,$0F,$02,$02,$25,$02,$04,$13,$02,$02,$29,$02,$04,$0F,$02,$02
  .byte $29,$02,$04,$13,$02,$02,$2D,$02,$04,$0F,$02,$02,$2D,$02,$04,$13,$02,$02,$FF,$FF
AR1_OB:
  .byte $1F,$00,$06,$28,$24,$00,$02,$B0,$2A,$00,$06,$58,$36,$00,$01,$B0,$46,$00,$03,$A8,$56,$00,$07,$B0,$56,$00,$04,$38,$57,$00,$02,$80
  .byte $5D,$00,$07,$B8,$63,$00,$01,$60,$6B,$00,$06,$90,$70,$00,$02,$68,$75,$00,$06,$10,$7C,$00,$01,$40,$A8,$00,$02,$60,$AF,$00,$06,$70
  .byte $B4,$00,$08,$C8,$B7,$00,$04,$40,$C9,$00,$01,$20,$CB,$00,$06,$A0,$CB,$00,$02,$C0,$CF,$00,$0A,$70,$DC,$00,$01,$C0,$E8,$00,$06,$78
  .byte $F0,$00,$03,$80,$FE,$00,$04,$60,$00,$01,$02,$58,$0A,$01,$01,$20,$11,$01,$06,$68,$1B,$01,$02,$20,$20,$01,$06,$38,$27,$01,$01,$48
  .byte $33,$01,$08,$38,$35,$01,$03,$B8,$58,$01,$02,$80,$60,$01,$06,$38,$65,$01,$07,$88,$69,$01,$04,$40,$6F,$01,$08,$18,$76,$01,$01,$38
  .byte $7C,$01,$02,$90,$86,$01,$06,$80,$8F,$01,$01,$80,$98,$01,$06,$40,$9D,$01,$03,$30,$A8,$01,$08,$60,$A9,$01,$02,$A0,$B0,$01,$04,$40
  .byte $BB,$01,$0A,$60,$BD,$01,$07,$98,$C3,$01,$01,$A0,$C6,$01,$08,$50,$E6,$01,$02,$78,$EE,$01,$06,$38,$F5,$01,$08,$88,$F5,$01,$01,$A0
  .byte $04,$02,$03,$88,$08,$02,$02,$70,$10,$02,$06,$B0,$18,$02,$08,$D0,$18,$02,$04,$A8,$25,$02,$01,$58,$2B,$02,$07,$98,$2C,$02,$07,$58
  .byte $37,$02,$02,$20,$39,$02,$08,$28,$67,$02,$0E,$60,$FF,$FF
AR1_CP:
  .byte $00,$00,$00,$00,$00,$00,$8C,$00,$84,$00,$38,$00,$3D,$01,$38,$01,$88,$00,$CC,$01,$1C,$02,$D0,$00
  .byte $3F,$02,$B2,$02,$08,$01
AR2_SH:
  .byte $1E,$00,$81,$11,$08,$08,$22,$00,$04,$15,$02,$01,$22,$00,$04,$10,$02,$03,$22,$00,$04,$0F,$02,$02
  .byte $24,$00,$04,$15,$02,$01,$2D,$00,$81,$12,$0F,$1A,$2E,$00,$04,$11,$02,$02,$33,$00,$81,$12,$0B,$1D
  .byte $35,$00,$04,$18,$02,$01,$35,$00,$04,$16,$02,$03,$36,$00,$04,$0B,$01,$03,$38,$00,$04,$0B,$01,$01
  .byte $39,$00,$04,$10,$02,$01,$3B,$00,$04,$13,$02,$03,$41,$00,$04,$12,$01,$01,$41,$00,$04,$16,$01,$02
  .byte $4B,$00,$04,$16,$01,$01,$57,$00,$81,$0C,$0B,$1D,$5A,$00,$04,$0E,$01,$03,$5B,$00,$81,$0D,$06,$15
  .byte $5C,$00,$04,$0D,$01,$03,$5F,$00,$04,$0A,$02,$02,$62,$00,$04,$0B,$01,$02,$66,$00,$04,$11,$01,$03
  .byte $66,$00,$04,$06,$01,$03,$66,$00,$04,$0C,$01,$03,$66,$00,$04,$07,$02,$01,$69,$00,$04,$0F,$02,$03
  .byte $6D,$00,$04,$0B,$01,$03,$96,$00,$81,$0E,$0A,$15,$9A,$00,$04,$12,$01,$01,$9D,$00,$04,$15,$01,$01
  .byte $A8,$00,$04,$0B,$02,$02,$B3,$00,$81,$0F,$0B,$1D,$B4,$00,$04,$10,$01,$03,$B8,$00,$04,$10,$01,$01
  .byte $B8,$00,$04,$0D,$01,$03,$BA,$00,$81,$11,$0A,$15,$C0,$00,$04,$16,$01,$03,$C4,$00,$04,$16,$01,$03
  .byte $C9,$00,$04,$15,$02,$03,$D8,$00,$81,$0C,$0D,$0F,$D9,$00,$04,$0D,$01,$01,$DA,$00,$04,$09,$02,$01
  .byte $DC,$00,$81,$13,$08,$08,$DC,$00,$04,$12,$02,$02,$DC,$00,$04,$0F,$02,$01,$DE,$00,$04,$03,$01,$02
  .byte $DF,$00,$04,$0D,$01,$03,$E2,$00,$04,$07,$02,$02,$F2,$00,$81,$0C,$0E,$17,$F9,$00,$04,$12,$01,$02
  .byte $FA,$00,$04,$0B,$01,$02,$FC,$00,$04,$0D,$02,$03,$FE,$00,$04,$12,$02,$01,$FE,$00,$04,$0D,$01,$01
  .byte $00,$01,$04,$13,$02,$02,$01,$01,$04,$0A,$01,$01,$04,$01,$04,$09,$01,$01,$05,$01,$04,$0B,$02,$02
  .byte $2D,$01,$81,$11,$0D,$0F,$34,$01,$81,$12,$07,$1C,$37,$01,$04,$16,$02,$02,$38,$01,$04,$0D,$01,$01
  .byte $57,$01,$81,$10,$09,$10,$5D,$01,$04,$09,$01,$02,$5E,$01,$04,$0F,$01,$01,$5E,$01,$04,$0C,$01,$01
  .byte $65,$01,$04,$12,$01,$01,$6D,$01,$81,$11,$0B,$1D,$74,$01,$04,$15,$01,$01,$80,$01,$04,$17,$01,$02
  .byte $81,$01,$04,$0F,$01,$03,$81,$01,$04,$14,$02,$03,$B2,$01,$81,$10,$08,$08,$B5,$01,$04,$11,$02,$02
  .byte $B8,$01,$04,$15,$01,$01,$BB,$01,$81,$0B,$09,$10,$C1,$01,$04,$0B,$01,$02,$C3,$01,$04,$05,$02,$03
  .byte $D5,$01,$81,$0F,$0A,$15,$DA,$01,$04,$14,$01,$02,$DC,$01,$04,$0C,$02,$01,$DD,$01,$81,$0C,$09,$10
  .byte $E2,$01,$04,$0E,$02,$02,$E4,$01,$04,$0E,$02,$01,$E4,$01,$04,$11,$01,$02,$E8,$01,$04,$13,$01,$02
  .byte $E9,$01,$04,$0D,$02,$03,$F5,$01,$81,$0E,$0D,$0F,$F8,$01,$04,$0F,$01,$03,$FD,$01,$04,$12,$02,$01
  .byte $01,$02,$81,$0C,$0B,$1D,$03,$02,$04,$0D,$01,$01,$0C,$02,$04,$05,$02,$01,$14,$02,$04,$0F,$01,$02
  .byte $15,$02,$04,$0D,$02,$01,$15,$02,$04,$0F,$01,$02,$24,$02,$81,$11,$0E,$17,$2C,$02,$04,$19,$02,$02
  .byte $2F,$02,$04,$11,$01,$03,$2F,$02,$04,$14,$01,$03,$30,$02,$81,$10,$09,$10,$30,$02,$04,$0A,$02,$01
  .byte $30,$02,$04,$12,$01,$02,$31,$02,$04,$0D,$02,$01,$36,$02,$04,$0F,$02,$01,$39,$02,$04,$0C,$02,$01
  .byte $FF,$FF
AR2_OB:
  .byte $1F,$00,$09,$A8,$21,$00,$07,$68,$21,$00,$01,$20,$2D,$00,$02,$A8,$32,$00,$03,$58,$33,$00,$09,$88,$3B,$00,$07,$C8,$3D,$00,$04,$A0
  .byte $47,$00,$09,$90,$4A,$00,$01,$68,$59,$00,$01,$30,$5B,$00,$02,$78,$64,$00,$09,$40,$65,$00,$03,$A0,$68,$00,$07,$18,$6D,$00,$09,$80
  .byte $78,$00,$02,$28,$99,$00,$07,$68,$9A,$00,$04,$90,$A1,$00,$09,$B0,$A1,$00,$07,$80,$AD,$00,$01,$28,$B3,$00,$02,$40,$B8,$00,$07,$98
  .byte $C1,$00,$07,$50,$C4,$00,$07,$28,$C4,$00,$01,$20,$D7,$00,$03,$88,$DA,$00,$02,$88,$DB,$00,$0A,$50,$DF,$00,$09,$78,$DF,$00,$07,$20
  .byte $E0,$00,$07,$40,$EC,$00,$04,$A8,$F5,$00,$01,$20,$FD,$00,$09,$30,$01,$01,$07,$30,$03,$01,$07,$70,$04,$01,$02,$48,$31,$01,$09,$40
  .byte $33,$01,$03,$90,$38,$01,$07,$88,$3F,$01,$07,$B0,$46,$01,$02,$70,$58,$01,$04,$A0,$58,$01,$01,$98,$5B,$01,$09,$50,$65,$01,$02,$30
  .byte $71,$01,$03,$20,$73,$01,$01,$30,$74,$01,$09,$68,$79,$01,$07,$A0,$7E,$01,$02,$80,$8B,$01,$04,$68,$B3,$01,$0A,$B8,$B4,$01,$09,$78
  .byte $B8,$01,$09,$70,$B8,$01,$01,$C0,$BC,$01,$07,$48,$C9,$01,$02,$58,$D6,$01,$01,$38,$D8,$01,$09,$78,$E2,$01,$07,$A8,$E6,$01,$03,$50
  .byte $E7,$01,$07,$48,$F6,$01,$04,$88,$F7,$01,$02,$30,$07,$02,$09,$90,$07,$02,$01,$78,$14,$02,$02,$70,$24,$02,$01,$70,$25,$02,$03,$58
  .byte $2C,$02,$07,$88,$31,$02,$09,$50,$37,$02,$07,$98,$39,$02,$02,$50,$4A,$02,$04,$28,$76,$02,$0E,$60,$FF,$FF
AR2_CP:
  .byte $00,$00,$00,$00,$00,$00,$7C,$00,$AE,$00,$44,$00,$13,$01,$68,$01,$9C,$00,$98,$01,$BC,$01,$D8,$00
  .byte $4E,$02,$88,$02,$34,$01
AR3_SH:
  .byte $1E,$00,$01,$03,$1C,$17,$1F,$00,$04,$05,$02,$02,$20,$00,$03,$15,$04,$0F,$21,$00,$02,$0E,$02,$08
  .byte $21,$00,$04,$16,$02,$02,$22,$00,$02,$14,$02,$08,$22,$00,$04,$05,$02,$02,$23,$00,$02,$0A,$02,$08
  .byte $26,$00,$02,$13,$02,$08,$27,$00,$04,$12,$02,$02,$29,$00,$04,$1B,$02,$02,$2A,$00,$04,$0E,$02,$02
  .byte $2C,$00,$04,$10,$02,$02,$2C,$00,$04,$0B,$02,$02,$2D,$00,$04,$18,$02,$02,$2E,$00,$04,$09,$02,$02
  .byte $31,$00,$04,$09,$02,$02,$32,$00,$04,$0D,$02,$02,$3D,$00,$01,$06,$12,$14,$3E,$00,$04,$12,$02,$02
  .byte $3F,$00,$03,$11,$04,$0A,$3F,$00,$04,$13,$02,$02,$40,$00,$02,$08,$02,$08,$46,$00,$04,$09,$02,$02
  .byte $4B,$00,$04,$0E,$02,$02,$5A,$00,$01,$03,$1B,$14,$5C,$00,$03,$16,$04,$0D,$5C,$00,$04,$0B,$02,$02
  .byte $66,$00,$04,$18,$02,$02,$66,$00,$04,$0B,$02,$02,$68,$00,$04,$15,$02,$02,$96,$00,$01,$0C,$11,$13
  .byte $97,$00,$04,$10,$02,$02,$97,$00,$02,$1A,$02,$08,$98,$00,$03,$0E,$04,$08,$9B,$00,$04,$12,$02,$02
  .byte $9F,$00,$04,$1A,$02,$02,$B2,$00,$01,$08,$11,$10,$B4,$00,$03,$0F,$04,$08,$B5,$00,$04,$10,$02,$02
  .byte $B6,$00,$04,$0C,$02,$02,$B7,$00,$04,$16,$02,$02,$B7,$00,$04,$0C,$02,$02,$B8,$00,$02,$13,$02,$08
  .byte $BA,$00,$04,$13,$02,$02,$BC,$00,$04,$0C,$02,$02,$BC,$00,$04,$0F,$02,$02,$BD,$00,$04,$0D,$02,$02
  .byte $BF,$00,$04,$12,$02,$02,$C9,$00,$01,$08,$15,$17,$CB,$00,$03,$14,$04,$09,$CD,$00,$02,$12,$02,$08
  .byte $CD,$00,$02,$09,$02,$08,$D0,$00,$02,$0E,$02,$08,$D2,$00,$04,$17,$02,$02,$D3,$00,$04,$14,$02,$02
  .byte $D3,$00,$04,$17,$02,$02,$D5,$00,$04,$19,$02,$02,$D7,$00,$02,$09,$02,$08,$D7,$00,$04,$15,$02,$02
  .byte $DB,$00,$04,$0D,$02,$02,$DB,$00,$04,$18,$02,$02,$DC,$00,$04,$14,$02,$02,$E7,$00,$01,$04,$19,$19
  .byte $E9,$00,$03,$17,$04,$0D,$EB,$00,$02,$1A,$02,$08,$EB,$00,$04,$06,$02,$02,$F1,$00,$02,$10,$02,$08
  .byte $F5,$00,$04,$09,$02,$02,$F6,$00,$04,$1A,$02,$02,$F9,$00,$04,$17,$02,$02,$FA,$00,$04,$08,$02,$02
  .byte $28,$01,$01,$08,$15,$11,$29,$01,$04,$14,$02,$02,$29,$01,$04,$1A,$02,$02,$2A,$01,$03,$17,$04,$05
  .byte $2D,$01,$04,$15,$02,$02,$2E,$01,$04,$0C,$02,$02,$2F,$01,$02,$19,$02,$08,$33,$01,$04,$19,$02,$02
  .byte $33,$01,$04,$09,$02,$02,$34,$01,$04,$13,$02,$02,$41,$01,$01,$0B,$14,$14,$42,$01,$02,$11,$02,$08
  .byte $42,$01,$04,$10,$02,$02,$43,$01,$03,$10,$04,$0A,$43,$01,$04,$14,$02,$02,$43,$01,$04,$13,$02,$02
  .byte $47,$01,$02,$17,$02,$08,$47,$01,$04,$1C,$02,$02,$48,$01,$04,$18,$02,$02,$48,$01,$04,$18,$02,$02
  .byte $48,$01,$02,$12,$02,$08,$4C,$01,$04,$0E,$02,$02,$4D,$01,$04,$1B,$02,$02,$61,$01,$01,$04,$11,$14
  .byte $62,$01,$04,$0C,$02,$02,$63,$01,$03,$06,$04,$0D,$63,$01,$04,$07,$02,$02,$66,$01,$04,$0E,$02,$02
  .byte $69,$01,$02,$11,$02,$08,$6C,$01,$04,$08,$02,$02,$6E,$01,$04,$0A,$02,$02,$72,$01,$04,$09,$02,$02
  .byte $80,$01,$01,$05,$16,$19,$81,$01,$02,$0F,$02,$08,$82,$01,$03,$10,$04,$07,$82,$01,$04,$07,$02,$02
  .byte $85,$01,$04,$0F,$02,$02,$87,$01,$04,$09,$02,$02,$88,$01,$04,$17,$02,$02,$8D,$01,$04,$0B,$02,$02
  .byte $93,$01,$04,$10,$02,$02,$96,$01,$04,$07,$02,$02,$96,$01,$04,$0C,$02,$02,$BE,$01,$01,$02,$1B,$19
  .byte $BF,$01,$04,$08,$02,$02,$BF,$01,$02,$0F,$02,$08,$C0,$01,$03,$0B,$04,$0F,$C6,$01,$04,$0B,$02,$02
  .byte $C7,$01,$04,$0E,$02,$02,$CF,$01,$04,$09,$02,$02,$D3,$01,$04,$1A,$02,$02,$D3,$01,$04,$1A,$02,$02
  .byte $D3,$01,$04,$0F,$02,$02,$DD,$01,$01,$01,$1C,$13,$DF,$01,$03,$07,$04,$09,$DF,$01,$04,$14,$02,$02
  .byte $DF,$01,$02,$0D,$02,$08,$E3,$01,$02,$0D,$02,$08,$EA,$01,$04,$0C,$02,$02,$EC,$01,$04,$09,$02,$02
  .byte $FC,$01,$01,$0E,$11,$15,$FD,$01,$02,$1A,$02,$08,$FE,$01,$03,$12,$04,$06,$01,$02,$02,$15,$02,$08
  .byte $03,$02,$04,$1B,$02,$02,$04,$02,$04,$14,$02,$02,$06,$02,$04,$1A,$02,$02,$07,$02,$04,$16,$02,$02
  .byte $0C,$02,$04,$1C,$02,$02,$0D,$02,$04,$18,$02,$02,$0E,$02,$04,$18,$02,$02,$1D,$02,$01,$05,$18,$1A
  .byte $1E,$02,$02,$12,$02,$08,$1E,$02,$04,$10,$02,$02,$1F,$02,$03,$17,$04,$0C,$20,$02,$04,$16,$02,$02
  .byte $21,$02,$02,$18,$02,$08,$23,$02,$04,$0B,$02,$02,$24,$02,$02,$06,$02,$08,$26,$02,$04,$16,$02,$02
  .byte $27,$02,$02,$06,$02,$08,$27,$02,$02,$19,$02,$08,$29,$02,$02,$11,$02,$08,$29,$02,$04,$1A,$02,$02
  .byte $31,$02,$04,$0A,$02,$02,$FF,$FF
AR3_OB:
  .byte $20,$00,$09,$D8,$21,$00,$03,$C0,$2C,$00,$06,$48,$2D,$00,$07,$20,$2D,$00,$02,$A8,$3B,$00,$04,$70,$40,$00,$01,$70,$45,$00,$06,$68
  .byte $4B,$00,$07,$98,$4F,$00,$07,$40,$51,$00,$02,$40,$5B,$00,$03,$38,$5D,$00,$01,$50,$5E,$00,$06,$90,$61,$00,$09,$20,$6A,$00,$09,$C0
  .byte $6D,$00,$02,$80,$97,$00,$06,$B8,$9B,$00,$04,$70,$A4,$00,$09,$68,$A7,$00,$07,$C0,$AE,$00,$01,$28,$B3,$00,$02,$48,$C0,$00,$07,$48
  .byte $C5,$00,$01,$50,$C9,$00,$07,$D0,$CD,$00,$03,$88,$D9,$00,$09,$D0,$D9,$00,$07,$90,$D9,$00,$02,$30,$DE,$00,$0A,$C8,$EA,$00,$04,$70
  .byte $EA,$00,$01,$B0,$EE,$00,$06,$A0,$EE,$00,$06,$68,$F7,$00,$02,$90,$FA,$00,$09,$C8,$09,$01,$01,$58,$28,$01,$07,$C0,$28,$01,$06,$50
  .byte $29,$01,$03,$78,$31,$01,$09,$80,$37,$01,$02,$38,$41,$01,$09,$A0,$41,$01,$04,$38,$48,$01,$07,$D0,$50,$01,$06,$88,$52,$01,$01,$98
  .byte $61,$01,$02,$48,$65,$01,$06,$80,$69,$01,$09,$98,$6C,$01,$09,$60,$74,$01,$01,$68,$84,$01,$03,$50,$8B,$01,$09,$48,$8B,$01,$06,$C8
  .byte $8F,$01,$06,$28,$92,$01,$02,$38,$A3,$01,$04,$98,$BE,$01,$01,$98,$BF,$01,$09,$D0,$C3,$01,$09,$40,$CD,$01,$0A,$C0,$D0,$01,$02,$40
  .byte $D2,$01,$07,$B0,$DF,$01,$09,$D8,$E0,$01,$01,$90,$E3,$01,$03,$28,$E4,$01,$09,$78,$ED,$01,$09,$88,$F3,$01,$02,$50,$FD,$01,$04,$28
  .byte $FF,$01,$06,$70,$0C,$02,$07,$B0,$10,$02,$01,$B0,$1F,$02,$02,$88,$22,$02,$07,$30,$25,$02,$09,$70,$31,$02,$01,$40,$33,$02,$06,$98
  .byte $6C,$02,$0E,$60,$FF,$FF
AR3_CP:
  .byte $00,$00,$00,$00,$00,$00,$7C,$00,$BA,$00,$44,$00,$0E,$01,$B0,$01,$98,$00,$A4,$01,$B2,$02,$EC,$00
  .byte $44,$02,$AE,$03,$40,$01

; names of the areas (16 characters)
AREA_TXT:
  .byte "THE ARCHIPELAGO   "
  .byte "THE SUNKEN CITY   "
  .byte "THE CRYSTAL FOREST"
  .byte "THE ENEMY BASE    "

; big letters of the title
BIG_TOP:
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0,$00,$18,$18,$18,$18,$19,$19,$1E,$00,$18,$18,$60,$60,$80,$80,$00
  .byte $00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80,$00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18,$00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00
BIG_BOT:
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00,$1E,$19,$19,$18,$18,$18,$18,$00,$00,$80,$80,$60,$60,$18,$18,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00,$01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00
TXT_BIG:
  .byte 2,9,224,225,226,227,228,229,32,32,230,231,232,233,234,235,0
  .byte 3,9,240,241,242,243,244,245,32,32,246,247,248,249,250,251,0
  .byte $FF

; 16 directions clockwise from up, speed 1 (8.8)
DIRX_L:
  .byte $00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13,$00,$13,$4B,$9E
DIRX_H:
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
DIRY_L:
  .byte $00,$13,$4B,$9E,$00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13
DIRY_H:
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF
; sines (64 steps a turn): radius 24, radius 72
SIN24:
  .byte $00,$02,$05,$07,$09,$0B,$0D,$0F,$11,$13,$14,$15,$16,$17,$18,$18,$18,$18,$18,$17,$16,$15,$14,$13,$11,$0F,$0D,$0B,$09,$07,$05,$02
  .byte $00,$FE,$FB,$F9,$F7,$F5,$F3,$F1,$EF,$ED,$EC,$EB,$EA,$E9,$E8,$E8,$E8,$E8,$E8,$E9,$EA,$EB,$EC,$ED,$EF,$F1,$F3,$F5,$F7,$F9,$FB,$FE
SIN72:
  .byte $00,$07,$0E,$15,$1C,$22,$28,$2E,$33,$38,$3C,$3F,$43,$45,$47,$48,$48,$48,$47,$45,$43,$3F,$3C,$38,$33,$2E,$28,$22,$1C,$15,$0E,$07
  .byte $00,$F9,$F2,$EB,$E4,$DE,$D8,$D2,$CD,$C8,$C4,$C1,$BD,$BB,$B9,$B8,$B8,$B8,$B9,$BB,$BD,$C1,$C4,$C8,$CD,$D2,$D8,$DE,$E4,$EB,$F2,$F9

; AY periods: index = MIDI note - 35
TP_LO:
  .byte $00,$BC,$86,$53,$24,$F6,$CC,$A4,$7E,$5A,$38,$18,$FA,$DE,$C3,$AA,$92,$7B,$66,$52,$3F,$2D,$1C,$0C,$FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9
  .byte $9F,$96,$8E,$86,$7F,$77,$71,$6A,$64,$5F,$59,$54,$50,$4B,$47,$43,$3F,$3C,$38,$35,$32,$2F,$2D,$2A,$28,$26,$24,$22,$20
TP_HI:
  .byte $00,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; tunes: song * 4 + track (melody, harmony, bass, drums)
SONGP_LO:
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3,<SG2_0,<SG2_1,<SG2_2,<SG2_3,<SG3_0,<SG3_1,<SG3_2,<SG3_3,<SG4_0,<SG4_1,<SG4_2,<SG4_3,<SG5_0,<SG5_1,<SG5_2,<SG5_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3,>SG2_0,>SG2_1,>SG2_2,>SG2_3,>SG3_0,>SG3_1,>SG3_2,>SG3_3,>SG4_0,>SG4_1,>SG4_2,>SG4_3,>SG5_0,>SG5_1,>SG5_2,>SG5_3
SG0_0:
  .byte $1B,$08,$1F,$08,$22,$08,$27,$10,$26,$08,$24,$08,$22,$10,$20,$08,$24,$08,$27,$08,$2C,$10,$2B,$08,$29,$08,$27,$10,$29,$08,$2B,$08
  .byte $2C,$08,$2E,$10,$2C,$08,$2B,$08,$29,$08,$26,$08,$27,$20,$FF
SG0_1:
  .byte $16,$20,$16,$20,$18,$20,$18,$20,$1A,$20,$16,$10,$14,$10,$13,$20,$FF
SG0_2:
  .byte $0F,$08,$0F,$08,$0A,$08,$0A,$08,$07,$08,$07,$08,$0A,$08,$0A,$08,$08,$08,$08,$08,$0F,$08,$0F,$08,$08,$08,$08,$08,$0C,$08,$0C,$08
  .byte $0A,$08,$0A,$08,$11,$08,$11,$08,$0A,$08,$0A,$08,$0E,$08,$0A,$08,$0F,$10,$03,$10,$FF
SG0_3:
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$04,$20,$FF
SG1_0:
  .byte $20,$06,$24,$06,$27,$06,$2C,$0C,$2B,$06,$27,$06,$29,$0C,$25,$06,$29,$06,$2C,$06,$31,$0C,$30,$06,$2C,$06,$2E,$18,$30,$18,$FF
SG1_1:
  .byte $18,$18,$19,$18,$1D,$18,$1B,$18,$20,$18,$FF
SG1_2:
  .byte $08,$0C,$08,$0C,$0D,$0C,$0D,$0C,$0A,$0C,$0A,$0C,$0F,$18,$08,$18,$FF
SG1_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$04,$18,$FF
SG2_0:
  .byte $1D,$06,$21,$06,$24,$06,$29,$0C,$28,$06,$24,$06,$26,$0C,$22,$06,$26,$06,$29,$06,$2E,$0C,$2D,$06,$29,$06,$2B,$18,$2D,$18,$FF
SG2_1:
  .byte $11,$18,$13,$18,$16,$18,$13,$18,$18,$18,$FF
SG2_2:
  .byte $05,$06,$11,$06,$05,$06,$11,$06,$0A,$06,$16,$06,$0A,$06,$16,$06,$07,$06,$13,$06,$07,$06,$13,$06,$0C,$18,$05,$18,$FF
SG2_3:
  .byte $01,$06,$03,$06,$03,$06,$03,$06,$02,$06,$03,$06,$03,$06,$03,$06,$01,$06,$03,$06,$03,$06,$03,$06,$02,$06,$03,$06,$03,$06,$03,$06
  .byte $04,$18,$FF
SG3_0:
  .byte $22,$06,$26,$06,$29,$06,$2E,$0C,$2D,$06,$29,$06,$2B,$0C,$27,$06,$2B,$06,$2E,$06,$33,$0C,$32,$06,$2E,$06,$30,$18,$32,$18,$FF
SG3_1:
  .byte $1D,$18,$1F,$18,$22,$18,$21,$18,$26,$18,$FF
SG3_2:
  .byte $0A,$18,$0F,$18,$0C,$18,$11,$0C,$11,$0C,$0A,$18,$FF
SG3_3:
  .byte $01,$18,$02,$18,$01,$18,$02,$18,$04,$18,$FF
SG4_0:
  .byte $1B,$06,$1F,$06,$22,$06,$27,$0C,$26,$06,$22,$06,$24,$0C,$20,$06,$24,$06,$27,$06,$2C,$0C,$2B,$06,$27,$06,$29,$18,$2B,$18,$FF
SG4_1:
  .byte $13,$0C,$13,$0C,$14,$0C,$14,$0C,$18,$0C,$18,$0C,$1A,$18,$1B,$18,$FF
SG4_2:
  .byte $03,$08,$03,$08,$03,$08,$08,$08,$08,$08,$08,$08,$05,$08,$05,$08,$05,$08,$0A,$0C,$0A,$0C,$03,$18,$FF
SG4_3:
  .byte $01,$08,$01,$08,$02,$08,$01,$08,$01,$08,$02,$08,$01,$08,$01,$08,$02,$08,$02,$0C,$02,$0C,$04,$18,$FF
SG5_0:
  .byte $25,$06,$29,$06,$2C,$06,$31,$12,$00,$06,$30,$06,$31,$06,$33,$06,$35,$1E,$FF
SG5_1:
  .byte $1D,$18,$20,$18,$20,$2A,$FF
SG5_2:
  .byte $0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$0D,$2A,$FF
SG5_3:
  .byte $02,$06,$02,$06,$02,$06,$01,$12,$03,$06,$03,$06,$03,$06,$03,$06,$04,$1E,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$18,$1C,$21,$2A,$77,$77,$77,$5F,$5F,$5F,$50,$50,$50,$3C,$3C,$3C,$2F,$2F,$2F,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$34
  .byte $26,$21,$23,$2C,$41,$6A,$7A,$52,$34,$26,$21,$23,$2C,$42,$6B,$79,$51,$33,$25,$21,$23,$2C,$43,$EF,$EF,$EF,$BE,$BE,$BE,$9F,$9F,$9F
  .byte $77,$77,$77,$5F,$5F,$5F,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$14,$14,$1A,$1A,$2D,$30,$33,$37,$3B,$40,$46
  .byte $4D,$56,$62,$71,$85,$A3,$D0,$45,$4B,$49,$4E,$5D,$64,$62,$69,$7C,$85,$82,$8C,$A6,$B2,$AE,$BB,$DE,$EE,$E9,$FB,$28,$3F,$38,$4F,$8C
  .byte $AA,$50,$50,$50,$50,$00,$00,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$28,$28,$BD,$BD,$BD,$BD,$BD,$BD,$BD
  .byte $C9,$C9,$C9,$C9,$C9,$C9,$C9,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$47,$47,$47,$47
  .byte $47,$5F,$5F,$5F,$5F,$5F,$47,$47,$47,$47,$47,$5F,$5F,$5F,$5F,$5F,$47,$47,$47,$47,$47,$5F,$5F,$5F,$5F,$5F,$28,$28,$28,$24,$24,$24
  .byte $00,$00,$1B,$1B,$1B,$1B,$1B,$18,$20,$20,$6A,$6A,$6A,$6A,$47,$47,$47,$47,$54,$54,$54,$35,$35,$35,$35,$35,$35,$35,$35
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$07,$06,$04,$03,$0D,$0C,$0A,$0D,$0C,$0A,$0D,$0C,$0A,$0D,$0C,$0A,$0D,$0C,$0A,$0D,$0C,$0A,$0D,$0C,$0A,$09,$08,$07,$05,$04,$0B
  .byte $0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$09,$08,$07,$06,$05,$04,$0D,$0C,$0B,$0D,$0C,$0B,$0D,$0C,$0B
  .byte $0D,$0C,$0B,$0D,$0C,$0B,$0D,$0C,$0B,$0D,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$03,$0A,$08,$07,$04,$0C,$0B,$0B,$0A,$0A,$09,$09
  .byte $08,$08,$07,$07,$06,$06,$05,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$02
  .byte $02,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0C,$0B,$0A,$09,$08,$07,$06
  .byte $0C,$0B,$0A,$09,$08,$07,$06,$0C,$0B,$0A,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0A,$08,$0A,$09,$08
  .byte $00,$00,$0A,$09,$07,$06,$04,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$05,$1F,$37,$55,$59,$67,$81,$99,$BC,$DA,$DD,$E7,$EA
WH_LEN:
  .byte $00,$04,$1A,$18,$1E,$04,$0E,$1A,$18,$23,$1E,$03,$0A,$03,$13
W_SHOT = 1
W_DOCK = 2
W_FORM = 3
W_FULL = 4
W_CLINK = 5
W_LOSE = 6
W_DIE = 7
W_EXTRA = 8
W_OVER = 9
W_ALARM = 10
W_BONUS = 11
W_READY = 12
W_KEY = 13
W_SIGN = 14

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$0D,$0D,$0C,$0C,$0A,$0A,$09
  .byte $09,$07,$07,$06,$06,$04,$04,$03,$03,$09,$07,$05,$03,$01,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06
  .byte $06,$06,$05,$05,$05,$05
EX_NP:
  .byte $00,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17
  .byte $17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19,$19,$19,$19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$0C,$0C,$0C,$0C,$0D,$0D,$0D
  .byte $0D,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$04,$04,$04,$04,$04,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07
  .byte $07,$07,$08,$08,$08,$08
EX_VC:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00,$00,$0A,$09,$08,$07,$06,$05,$04
  .byte $03,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$B6,$38,$B6,$38,$B6,$38,$B6
  .byte $38,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$39,$49,$4E
EX_LEN:
  .byte $00,$38,$10,$05,$18
S_BIG = 1
S_SMALL = 2
S_HIT = 3
S_LAUNCH = 4

GFX_LOAD:
  .byte 2, $00,$40, <2048,>2048, $00,0
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 1, $00,$47, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $80,$47, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$48, <2048,>2048, $00,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 1, $00,$4F, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $80,$4F, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$50, <2048,>2048, $00,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 1, $00,$57, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $80,$57, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$58, <2048,>2048, $00,0
  .byte 1, $00,$59, <512,>512, <FONT,>FONT
  .byte 1, $00,$5F, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $80,$5F, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$60, <2048,>2048, $00,0
  .byte 1, $00,$60, <896,>896, <SPRITES,>SPRITES
  .byte 2, $00,$78, <2048,>2048, $20,0
  .byte 0
