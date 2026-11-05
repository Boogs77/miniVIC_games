;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   CLOUD RAIDER  -  an original isometric shooter             ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: robert / bubbles (VDP, NMI + trampoline $0FD0, AY    ;
;   engine, 2 players taking turns)                            ;
;                                                              ;
;   - a ship flies over fortresses on islands floating among   ;
;     the clouds; the world scrolls down left at 45 degrees:   ;
;     one tile every 4 frames (two copies of the name table    ;
;     in RAM, built row by row and shown by switching R2),     ;
;     while the floor texture slides 2 pixels every frame      ;
;   - joystick: left / right = sideways, up / down = altitude  ;
;     (the shadow on the ground and the gauge show it);        ;
;     button 1 = fire (flies at the ship's altitude), button   ;
;     2 = bomb (falls straight down on the ground targets)     ;
;   - high walls: only through the gap; low walls: fly over;   ;
;     energy fences: fly low under them or pass when off;      ;
;     towers fire                                              ;
;     at the ship (more often while a radar stands), mines     ;
;     float in the air, fighters attack over the open sky      ;
;   - energy runs down: bomb the depots to fill it up          ;
;   - at the end of every fortress the Guardian: a core with   ;
;     4 turning shields, hit it at its own altitude            ;
;   - 4 fortresses, then again faster; 3 ships, one more at    ;
;     10000 and every 30000; 1 or 2 players taking turns       ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     engine, shots, falling bombs, explosions, energy alarm,  ;
;     Guardian beat, start tune, fortress clear jingle         ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
ALIVE       = $32      ; 2 bytes: ships left to every player (the one playing included)
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
FORT        = $40      ; ---- block of the player, saved: fortress 0-3
CYCLE       = $41      ;      times round the 4 fortresses
NEXTX       = $42      ;      next extra ship (BCD, ten thousands)
PBLOCK      = 3
PH          = $43      ; frame of the scroll step 0-3
STEP        = $44      ; scroll steps (a = column - row + 2 * STEP)
DSTEP       = $45      ; step of the name table shown
DA          = $46      ; next row (a) to decode
TPTR        = $47      ; 2 bytes: terrain of the fortress
TLEFT       = $49      ; rows left in this run of terrain
TW          = $4A      ; half width of the island (0 = sky)
FPTR        = $4B      ; 2 bytes: features of the fortress
FCNT        = $4D      ; rows before the next feature
WALLR       = $4E      ; the wall / fence of the row before (walls are 2 rows thick)
WALLP1      = $4F
WALLP2      = $50
SRC         = $51      ; high byte of the copy shown
DST         = $52      ; high byte of the copy being built
READY       = $53      ; 1 = DST is complete
NTSEL       = $54      ; name table shown: 0 = $3800, 1 = $3C00
SCROLL      = $55      ; 1 = the world moves
HUDD        = $56      ; 1 = the HUD changed
FIRSTT      = $57      ; 1 = first turn of the game: start tune
GSTATE      = $58      ; 0 playing, 1 ship lost, 2 fortress clear
GT          = $59      ; timer of GSTATE
ENERGY      = $5A      ; 0-255
ETIM        = $5B      ; frames before the energy drops
FENCE       = $5C      ; 1 = the energy fences are on
FENCT       = $5D      ; frames before they switch
RR          = $5E      ; first object in the SAT (turns)
SHOWP       = $5F      ; 1 = "PLAYER n" before the fortress

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
HOFF        = $70      ; name table being written: 0 = $3800, 4 = $3C00
ENGINE      = $71      ; engine sound: 0 off, 1-16 higher and higher
TP          = $72      ; 2 bytes: text records
SL          = $74      ; ship: sideways position (signed)
SH          = $75      ;       altitude 0-56
SGX         = $76      ;       ground point on the screen
SGY         = $77
CC          = $78
RW          = $79
JOYC        = $7A      ; both joysticks drive the player playing
JOYP        = $7B
DIFF        = $7C      ; difficulty 0-7
SLOT        = $7D
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $80      ; points to add (BCD)
PTS_M       = $81
PTS_H       = $82
SATB        = $83      ; bytes of the SAT to copy
GSTAT       = $84      ; Guardian: 0 none, 1 coming, 2 fighting, 3 exploding, 4 leaving
GHITS       = $85      ; hits still needed
GANG        = $86      ; angle of the shields
GL          = $87      ; sideways position
GH          = $88      ; altitude
GT2         = $89      ; its timer (4-frame units)
GDIR        = $8A      ; 1 = moving to the right
FIGHTN      = $8B      ; fighters still to come
FIGHTT      = $8C      ; frames before the next one
RADARS      = $8D      ; radars on the board
FIREI       = $8E      ; turret checked this frame
CNT         = $8F
GX          = $90      ; Guardian core: ground point on the screen
GY          = $91
ALARMT      = $92      ; frames before the next energy alarm
DIST        = $93
SHOWN_E     = $94      ; energy cells on the HUD
SHOWN_A     = $95      ; altitude cells on the HUD

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

; ---------------- objects in the air: 0-1 shots, 2 bomb, 3-13 the others
NOBJ       = 14
O_K        = $0200       ; kind K_* (0 = free)
O_X        = $0210       ; ground point on the screen (8.8)
O_XL       = $0220
O_Y        = $0230
O_YL       = $0240
O_H        = $0250       ; altitude (8.8)
O_HL       = $0260
O_VXL      = $0270       ; velocity (8.8 signed)
O_VXH      = $0280
O_VYL      = $0290
O_VYH      = $02A0
O_VHL      = $02B0
O_VHH      = $02C0
O_T        = $02D0       ; timer
K_SHOT     = 1
K_BOMB     = 2
K_SHELL    = 3
K_MINE     = 4
K_FIGHTER  = 5
K_BOOM     = 6           ; explosion in the air (moves with the world when on the ground)
K_RING     = 7           ; shot of the Guardian

; ---------------- things on the ground that act: towers, radars, mines still to come
NTUR       = 16
U_K        = $0300       ; 0 free, 1 tower, 2 radar, 3 mine waiting to come on the screen
U_A        = $0310       ; row a and column b in the map
U_B        = $0320
U_H        = $0330       ; mine: altitude

PSAVE      = $0400       ; 2 x 4 bytes: block of every player
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
MAT        = $6000       ; the map: 64 rows (a & 63) x 64 columns (b)
NTA        = $7000       ; two copies of the name table
NTB        = $7300

; ---------------- parameters ----------------
BTN_MASK    = %00110000

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 23           ; fixed zone of the game in the save area
REC_RAM     = $7C00        ; $2A0 bytes of free RAM
REC_ROW     = 8            ; table header on this row of the title, rows +1..+8 the table
REC_WIPEN   = 11           ; rows of the title that give way to the table
REC_JOY2    = $FF          ; $FF = both joysticks sign, 0 = the player's own
REC_SROW    = REC_ROW      ; table header on the sign screen
SHIP_X0     = 64         ; ground point of the ship = (SHIP_X0 + SL, SHIP_Y0 + SL)
SHIP_Y0     = 112
SL_MIN      = $C8        ; -56
SL_MAX      = 64
SH_MAX      = 56
WALL_LOW    = 24         ; a low wall is passed above this altitude
OBJ_HIGH    = 8          ; towers, radars, depots
FENCE_LOW   = 16         ; an energy fence that is on is passed below this altitude

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
  STA ENGINE
  STA HOFF
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ ALIVE,X
  DEX
  BPL .rs_p
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_HISC
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, what is worth what, the keys
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  STZ ENGINE
  JSR VDP_INT_OFF
  JSR SHOW_NT0
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JSR PRINT
  JSR TITLE_PAGE
  JSR REC_TITLE
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

; rows 8-18 of the title, the targets and the sprites beside them (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #0                       ; the ground targets as tiles
.ti_t:
  LDA TITLE_TR,X
  BEQ .ti_s0
  PHX
  TAY
  LDA TITLE_TT,X
  PHA
  TYA
  TAX
  LDY #4
  JSR NT_XY
  PLA
  STA VDATA
  PLX
  INX
  BRA .ti_t
.ti_s0:
  LDX #$00                     ; the ship, a mine, a fighter, the Guardian (sprites)
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
  CPX #6
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; every 5 s the title page and the table of the records take turns
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
  JMP VDP_INT_ON

; name table 0 on the screen (title and messages)
SHOW_NT0:
  STZ HOFF
  STZ NTSEL
  LDA #$0E
  STA VREG
  LDA #(VDP_REGISTER_BITS | 2)
  STA VREG
  RTS


; ===============================================================
;  NEW GAME
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
  STZ FORT
  STZ CYCLE
  LDA #$01
  STA NEXTX                    ; first extra ship at 10000
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then a FORTRESS from its start
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE FORT_START
  INC SHOWP

FORT_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ ENGINE
  JSR VDP_INT_OFF
  JSR SHOW_NT0
  JSR CLEAR_NT                 ; ---- the message
  JSR DRAW_TOP
  LDA SHOWP
  BEQ .fs_f
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.fs_f:
  LDA #<TXT_FORT
  STA TP
  LDA #>TXT_FORT
  STA TP+1
  JSR PRINT
  LDA FORT
  CLC
  ADC #$31
  STA VDATA
  LDX FORT
  LDA FNAME_LO,X
  STA TP
  LDA FNAME_HI,X
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA FIRSTT
  BEQ .fs_wait
  STZ FIRSTT                   ; the start tune, to the end
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.fs_tune:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .fs_tune
  BRA .fs_go
.fs_wait:
  LDA #100
  JSR WAIT_FRAMES
.fs_go:
  JSR VDP_INT_OFF              ; ---- the world (the screen stays still meanwhile)
  JSR SET_FORT
  JSR START_WORLD
  JSR START_SHIP
  JSR DRAW_HUD_BOTH
  JSR BUILD_SAT
  STZ SHOWP
  LDA #CMD_GAME
  STA SND_CMD
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
  JSR SCROLL_FRAME             ; floor texture, R2, one quarter of the next name table
  JSR FENCE_TICK
  LDA GSTATE
  BNE .gl_stop
  JSR UPDATE_SHIP
  JSR ENERGY_TICK
.gl_stop:
  JSR UPDATE_OBJECTS
  JSR TURRETS
  JSR SPAWN_FIGHTERS
  JSR GUARDIAN
  LDA GSTATE
  BNE .gl_hud
  JSR SHIP_HITS
.gl_hud:
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  CMP #2
  BEQ FORT_CLEAR
  JMP LOSE_LIFE


; ===============================================================
;  END OF A FORTRESS
; ===============================================================
; bonus: 100 per energy cell, then the next fortress (faster after the 4th)
FORT_CLEAR:
  JSR VDP_INT_OFF
  LDX #NOBJ-1                  ; the sky clears
.fc_o:
  STZ O_K,X
  DEX
  BPL .fc_o
  JSR BUILD_SAT
  STZ HOFF
  LDA NTSEL
  BEQ .fc_h
  LDA #4
  STA HOFF
.fc_h:
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA ENERGY
  LSR A
  LSR A
  LSR A
  LSR A
  STA CNT
  JSR BIN2BCD
  JSR PUT_2
  LDA #'0'
  STA VDATA
  STA VDATA
  JSR VDP_INT_ON
  LDA #W_CLEAR
  LDX #2
  JSR SFX_WHISTLE
  LDA #60
  JSR WAIT_FRAMES
.fc_b:
  LDA CNT
  BEQ .fc_n
  DEC CNT
  STZ PTS_L
  LDA #$01
  STA PTS_M
  STZ PTS_H
  JSR VDP_INT_OFF
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  LDA #6
  JSR WAIT_FRAMES
  BRA .fc_b
.fc_n:
  LDA #90
  JSR WAIT_FRAMES
  INC FORT
  LDA FORT
  CMP #4
  BCC .fc_go
  STZ FORT
  INC CYCLE
.fc_go:
  JMP FORT_START

LOSE_LIFE:
  STZ ENGINE
  LDX CURP
  DEC ALIVE,X
  JSR SAVE_PLAYER
  LDA NPL                      ; the other player, if he still has ships
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
  JSR SHOW_NT0
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
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
  LDY PS_OFF,X                 ; extra byte: the fortress reached (4 a round, from 1)
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
  JSR SHOW_NT0
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
REC_NAME:  .byte "CLOUD RAIDER    "
REC_HEAD:  .byte "BEST RAIDERS",0
REC_XLBL:  .byte "FORT ",0

; the fortress: its terrain and features, the difficulty
SET_FORT:
  LDX FORT
  LDA TERR_LO,X
  STA TPTR
  LDA TERR_HI,X
  STA TPTR+1
  LDA FEAT_LO,X
  STA FPTR
  LDA FEAT_HI,X
  STA FPTR+1
  LDA CYCLE                    ; difficulty: fortress + 4 per cycle, at most 7
  ASL A
  ASL A
  CLC
  ADC FORT
  CMP #8
  BCC .sf_d
  LDA #7
.sf_d:
  STA DIFF
  RTS


; ===============================================================
;  HUD: scores on row 0, energy / altitude / ships on row 23,
;  in both name tables
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
  BNE .dt_r
  LDX #$01
  JMP DRAW_SCORE
.dt_r:
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

DRAW_HUD_BOTH:
  STZ HOFF
  JSR DRAW_HUD
  LDA #4
  STA HOFF
  JSR DRAW_HUD
  STZ HOFF
  RTS

DRAW_HUD:
  JSR DRAW_TOP
  LDA #<TXT_BOT
  STA TP
  LDA #>TXT_BOT
  STA TP+1
  JSR PRINT
  LDA #$FF
  STA SHOWN_E
  STA SHOWN_A
  JSR DRAW_BARS
  ; fall into DRAW_SHIPS

; row 23: the spare ships
DRAW_SHIPS:
  LDX #23
  LDY #27
  JSR NT_XY
  LDX CURP
  LDA ALIVE,X
  BEQ .ds_z
  DEC A
.ds_z:
  STA T0
  LDX #0
.ds_l:
  LDA #$20
  CPX T0
  BCS .ds_b
  LDA #T_LIFE
.ds_b:
  STA VDATA
  INX
  CPX #5
  BNE .ds_l
  RTS

; row 23: energy (16 cells) and altitude (7 cells)
DRAW_BARS:
  LDA ENERGY
  LSR A
  LSR A
  LSR A
  LSR A
  STA T0
  LDX #23
  LDY #2
  JSR NT_XY
  LDX #0
.db_e:
  LDA #T_BAR_FULL
  CPX T0
  BCC .db_ew
  LDA #T_BAR_EMPTY
.db_ew:
  STA VDATA
  INX
  CPX #15
  BNE .db_e
  LDA SH
  LSR A
  LSR A
  LSR A
  STA T0
  LDX #23
  LDY #20
  JSR NT_XY
  LDX #0
.db_a:
  LDA #T_ALT_MARK
  CPX T0
  BCC .db_aw
  BEQ .db_aw
  LDA #T_BAR_EMPTY
.db_aw:
  STA VDATA
  INX
  CPX #7
  BNE .db_a
  RTS

; the HUD of both name tables, only where it changed
UPDATE_HUD:
  LDA ENERGY
  LSR A
  LSR A
  LSR A
  LSR A
  STA T1
  LDA SH
  LSR A
  LSR A
  LSR A
  CMP SHOWN_A
  BNE .uh_bars
  LDA T1
  CMP SHOWN_E
  BEQ .uh_sc
.uh_bars:
  STA SHOWN_E                  ; (both are set again below)
  LDA T1
  STA SHOWN_E
  LDA SH
  LSR A
  LSR A
  LSR A
  STA SHOWN_A
  STZ HOFF
  JSR DRAW_BARS
  LDA #4
  STA HOFF
  JSR DRAW_BARS
  STZ HOFF
.uh_sc:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  LDX CURP
  JSR DRAW_SCORE
  JSR DRAW_SHIPS
  LDA #4
  STA HOFF
  LDX CURP
  JSR DRAW_SCORE
  JSR DRAW_SHIPS
  STZ HOFF
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDA PS_OFF,X
  TAY
  LDX #$00
.sp_b:
  LDA FORT,X
  STA PSAVE,Y
  INY
  INX
  CPX #PBLOCK
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  LDA PS_OFF,X
  TAY
  LDX #$00
.lp_b:
  LDA PSAVE,Y
  STA FORT,X
  INY
  INX
  CPX #PBLOCK
  BNE .lp_b
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a ship more at 10000, then every 30000
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
  ADC #$03
  CLD
  BCC .as_x
  LDA #$FF                     ; past 990000: no more
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
;  THE WORLD: a map of 64 rows in a ring, decoded row by row from
;  the fortress; on the screen, cell (row r, column c) shows the
;  map at a = c - r + 2 * STEP, b = c + r (rows 1-22 scroll)
; ===============================================================
; a new fortress: decoder at its start, the first screen in NTA, shown in name table 0
START_WORLD:
  STZ STEP
  STZ DSTEP
  STZ PH
  STZ READY
  STZ WALLR
  STZ RADARS
  STZ FIREI
  LDA #1
  STA SCROLL
  STA FENCE
  LDA #90
  STA FENCT
  LDX #NTUR-1
.sw_u:
  STZ U_K,X
  DEX
  BPL .sw_u
  STZ TLEFT                    ; the first run is read by the first row
  STZ TW
  LDY #0                       ; the first feature: its delta
  LDA (FPTR),Y
  STA FCNT
  LDA #232                     ; rows from a = -24 to +33 (the last one not finished yet)
  STA DA
.sw_d:
  JSR DECODE_ROW
  LDA DA
  CMP #34
  BNE .sw_d
  LDA #>NTA
  STA SRC
  LDA #>NTB
  STA DST
  JSR RENDER_ALL
  LDA #$00                     ; NTA -> name table 0, rows 1-22
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $38)
  STA VREG
  LDA #<NTA
  STA PTR
  LDA #>NTA
  STA PTR+1
  LDX #3
  LDY #0
.sw_c:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .sw_c
  INC PTR+1
  DEX
  BNE .sw_c
  LDA #0
  JMP FLOOR

; ---------------------------------------------------------------
; one frame of scrolling: the floor texture first (in the vblank),
; then frame 0 shows the new name table and prepares the next
; ---------------------------------------------------------------
SCROLL_FRAME:
  LDA SCROLL
  BNE .sf_on
  RTS
.sf_on:
  LDA PH
  JSR FLOOR
  LDA PH
  BNE .sf_1
  JSR FLIP
  INC STEP
  JSR EDGES
  LDA #1
  LDX #1
  BRA .sf_rows
.sf_1:
  CMP #1
  BNE .sf_2
  JSR DECODE_ROW               ; the map one row further (twice a step)
  LDA #2
  LDX #7
  BRA .sf_rows
.sf_2:
  CMP #2
  BNE .sf_3
  JSR DECODE_ROW
  LDA #9
  LDX #7
  BRA .sf_rows
.sf_3:
  LDA #16
  LDX #7
.sf_rows:
  JSR ROWS
  LDA PH
  INC A
  AND #3
  STA PH
  RTS

; A = phase 0-3: the floor tile in the 3 thirds
FLOOR:
  ASL A
  ASL A
  ASL A
  STA T2
  LDX #0
.fl_t:
  LDA #(T_FLOOR*8)
  STA VREG
  TXA
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  LDY T2
  LDA #8
  STA T3
.fl_b:
  LDA FLOOR_PH,Y
  STA VDATA
  INY
  DEC T3
  BNE .fl_b
  TXA
  CLC
  ADC #8
  TAX
  CPX #$18
  BNE .fl_t
  RTS

; shows the name table just built and swaps the two copies in RAM
FLIP:
  LDA READY
  BEQ .fp_r
  LDA NTSEL
  EOR #1
  STA NTSEL
  ORA #$0E
  STA VREG
  LDA #(VDP_REGISTER_BITS | 2)
  STA VREG
  LDA SRC
  LDX DST
  STX SRC
  STA DST
  LDA STEP
  STA DSTEP
.fp_r:
  LDA #1
  STA READY
  RTS

; A = first row, X = rows: DST (r, c) = SRC (r - 1, c + 1), column 31 from DST
; (row 1: all from DST); every row also goes to the hidden name table
ROWS:
  STA RW
  STX T5
  ASL A                        ; VRAM: hidden name table + row * 32
  ASL A
  ASL A
  ASL A
  ASL A
  STA VREG
  STA PTR2
  LDA RW
  LSR A
  LSR A
  LSR A
  STA T4
  LDA NTSEL
  BNE .ro_h0
  LDA #$7C
  BRA .ro_h
.ro_h0:
  LDA #$78
.ro_h:
  ORA T4
  STA VREG
  LDA T4                       ; PTR2 = DST + row * 32
  CLC
  ADC DST
  STA PTR2+1
.ro_r:
  LDA RW
  CMP #1
  BNE .ro_copy
  LDY #0                       ; row 1: only out
.ro_0:
  LDA (PTR2),Y
  STA VDATA
  INY
  CPY #32
  BNE .ro_0
  BRA .ro_n
.ro_copy:
  LDA PTR2                     ; PTR = the same place - 31 in SRC
  SEC
  SBC #31
  STA PTR
  LDA PTR2+1
  SBC DST
  CLC
  ADC SRC
  STA PTR+1
  LDY #0
.ro_l:
  LDA (PTR),Y
  STA (PTR2),Y
  STA VDATA
  INY
  CPY #31
  BNE .ro_l
  LDA (PTR2),Y                 ; column 31: from the map
  STA VDATA
.ro_n:
  LDA PTR2
  CLC
  ADC #32
  STA PTR2
  BCC .ro_x
  INC PTR2+1
.ro_x:
  INC RW
  DEC T5
  BNE .ro_r
  RTS

; the new step: row 1 and column 31 (rows 2-22) of DST from the map
EDGES:
  LDA DST
  STA PTR2+1
  LDA #32
  STA PTR2
  STZ CC                       ; row 1: a = c - 1 + 2 * STEP, b = c + 1
.ed_r1:
  LDA STEP
  ASL A
  CLC
  ADC CC
  DEC A
  STA T4
  LDY CC
  INY
  LDA T4
  JSR CELL
  LDY CC
  STA (PTR2),Y
  INC CC
  LDA CC
  CMP #32
  BNE .ed_r1
  LDA #95                      ; column 31, rows 2-22: a = 31 - r + 2 * STEP, b = 31 + r
  STA PTR2
  LDA #2
  STA RW
.ed_c:
  LDA STEP
  ASL A
  CLC
  ADC #31
  SEC
  SBC RW
  STA T4
  LDA #31
  CLC
  ADC RW
  TAY
  LDA T4
  JSR CELL
  LDY #0
  STA (PTR2),Y
  LDA PTR2
  CLC
  ADC #32
  STA PTR2
  BCC .ed_n
  INC PTR2+1
.ed_n:
  INC RW
  LDA RW
  CMP #23
  BNE .ed_c
  RTS

; the whole screen (rows 1-22) into SRC
RENDER_ALL:
  LDA SRC
  STA PTR2+1
  STZ PTR2
  LDY #0                       ; row 0 and 23 stay blank here (the HUD)
  LDA #$20
.ra_z:
  STA (PTR2),Y
  INY
  CPY #32
  BNE .ra_z
  LDA #32
  STA PTR2
  LDA #1
  STA RW
.ra_r:
  STZ CC
.ra_c:
  LDA STEP                     ; a = c - r + 2 * STEP, b = c + r
  ASL A
  CLC
  ADC CC
  SEC
  SBC RW
  STA T4
  LDA CC
  CLC
  ADC RW
  TAY
  LDA T4
  JSR CELL
  LDY CC
  STA (PTR2),Y
  INC CC
  LDA CC
  CMP #32
  BNE .ra_c
  LDA PTR2
  CLC
  ADC #32
  STA PTR2
  BCC .ra_n
  INC PTR2+1
.ra_n:
  INC RW
  LDA RW
  CMP #23
  BNE .ra_r
  RTS

; A = a, Y = b: PTR points to row a of the map (keeps Y)
MAP_ROW:
  AND #$3F
  TAX
  LSR A
  LSR A
  CLC
  ADC #>MAT
  STA PTR+1
  LDA LO6,X
  STA PTR
  RTS

; A = a, Y = b: A = the tile shown there (the rows are finished by FINISH_ROW)
CELL:
  AND #$3F
  TAX
  LSR A
  LSR A
  CLC
  ADC #>MAT
  STA PTR+1
  LDA LO6,X
  STA PTR
  LDA (PTR),Y
  RTS

; row DA - 1 is finished now that row DA is there: a face under the walls (two under the high ones),
; the rock under the edges of the islands (the cell above (a, b) on the screen is (a + 1, b - 1))
FINISH_ROW:
  LDA DA
  LDY #0
  JSR MAP_ROW
  LDA PTR
  STA PTR2
  LDA PTR+1
  STA PTR2+1                   ; PTR2 = row a + 1 (= DA)
  LDA DA
  DEC A
  JSR MAP_ROW                  ; PTR = row a (= DA - 1)
  LDA DA                       ; the cells of row a: a + b even, b >= 1
  DEC A
  AND #1
  BNE .fr_y
  LDA #2
.fr_y:
  TAY
.fr_l:
  LDA (PTR),Y
  CMP #T_FLOOR
  BNE .fr_s
  DEY
  LDA (PTR2),Y
  INY
  CMP #T_HIGH_WALL
  BNE .fr_lw
  LDA #T_HIGH_FACE
  STA (PTR),Y
  BRA .fr_n
.fr_lw:
  CMP #T_LOW_WALL
  BNE .fr_n
  LDA #T_LOW_FACE
  STA (PTR),Y
  BRA .fr_n
.fr_s:
  CMP #T_CLOUD_B+1
  BCS .fr_n
  DEY
  LDA (PTR2),Y
  INY
  TAX
  LDA GROUND_T,X
  BEQ .fr_n
  LDA #T_ROCK
  STA (PTR),Y
.fr_n:
  INY
  INY
  CPY #64
  BCC .fr_l
  ; ---- the high walls look twice as tall: a second face under the face (row a - 1, b + 1);
  ; the walls still stop the ship only on their own cells
  LDA PTR                      ; PTR2 = row a
  STA PTR2
  LDA PTR+1
  STA PTR2+1
  LDA DA
  SEC
  SBC #2
  JSR MAP_ROW                  ; PTR = row a - 1
  LDY #1
.fr_2:
  LDA (PTR2),Y
  CMP #T_HIGH_FACE
  BNE .fr_2n
  INY
  LDA (PTR),Y
  DEY
  CMP #T_FLOOR
  BNE .fr_2n
  INY
  LDA #T_HIGH_FACE
  STA (PTR),Y
  DEY
.fr_2n:
  INY
  CPY #63
  BCC .fr_2
  RTS

LO6: .byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
     .byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
     .byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
     .byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192

; ---------------------------------------------------------------
; the next row of the map (a = DA): terrain, then the features
; ---------------------------------------------------------------
DECODE_ROW:
  LDA TLEFT                    ; ---- terrain: rows, half width
  BNE .dr_t
  LDY #0
  LDA (TPTR),Y
  BEQ .dr_end                  ; the end of the fortress: sky
  STA TLEFT
  INY
  LDA (TPTR),Y
  STA TW
  LDA TPTR
  CLC
  ADC #2
  STA TPTR
  BCC .dr_t
  INC TPTR+1
  BRA .dr_t
.dr_end:
  STZ TW
  LDA #1
  STA TLEFT
.dr_t:
  DEC TLEFT
  LDA DA
  LDY #0
  JSR MAP_ROW
  LDA TW                       ; island from 28 - w to 28 + w (a little wavy)
  BEQ .dr_sky
  LDX DA
  TXA
  AND #$0F
  TAX
  LDA TW
  CLC
  ADC WOBBLE,X
  STA T0
  LDA #28
  SEC
  SBC T0
  STA T1                       ; first b of the island
  LDA #28
  CLC
  ADC T0
  STA T2                       ; last b
  BRA .dr_fill
.dr_sky:
  LDA #$FF
  STA T1
  STZ T2
.dr_fill:
  LDA DA                       ; only the cells that are shown: a + b even
  AND #1
  TAY
.dr_l:
  CPY T1
  BCC .dr_c
  CPY T2
  BEQ .dr_g
  BCS .dr_c
.dr_g:
  LDA #T_FLOOR
  BRA .dr_w
.dr_c:
  TYA                          ; sky with a few clouds
  ASL A
  ASL A
  ASL A
  EOR DA
  ADC DA
  AND #$3F
  CMP #2
  BCS .dr_b
  CLC
  ADC #T_CLOUD_A
  BRA .dr_w
.dr_b:
  LDA #T_SKY
.dr_w:
  STA (PTR),Y
  INY
  INY
  CPY #64
  BCC .dr_l
  LDA WALLR                    ; ---- the second row of a wall
  BEQ .dr_f
  JSR PUT_WALL
  STZ WALLR
.dr_f:
  LDA FCNT                     ; ---- features of this row
  BNE .dr_fd
  LDY #1
  LDA (FPTR),Y
  CMP #$FF
  BNE .dr_fk
  LDA #255                     ; the end of the list: it stays there
  STA FCNT
  BRA .dr_fd
.dr_fk:
  STA T3
  INY
  LDA (FPTR),Y
  STA WALLP1
  INY
  LDA (FPTR),Y
  STA WALLP2
  LDA FPTR
  CLC
  ADC #4
  STA FPTR
  BCC .dr_fp
  INC FPTR+1
.dr_fp:
  JSR FEATURE
  LDY #0                       ; the delta of the next one
  LDA (FPTR),Y
  STA FCNT
  BRA .dr_f
.dr_fd:
  DEC FCNT
  JSR FINISH_ROW
  INC DA
  RTS

; T3 = kind, WALLP1 / WALLP2 = parameters, on row DA
FEATURE:
  LDA T3
  BEQ .fe_r
  CMP #F_HWALL
  BCC .fe_obj
  CMP #F_FIGHT
  BCS .fe_air
  STA WALLR                    ; walls and fences: this row and the next
  JMP PUT_WALL
.fe_air:
  CMP #F_FIGHT
  BNE .fe_g
  LDA WALLP1                   ; fighters: how many
  STA FIGHTN
  LDA #40
  STA FIGHTT
.fe_r:
  RTS
.fe_g:
  LDA GSTAT                    ; the Guardian comes
  BNE .fe_r
  LDA #1
  STA GSTAT
  LDA #30
  STA GT2
  RTS
.fe_obj:
  LDA DA                       ; b with the parity of the lattice: a + b even
  CLC
  ADC WALLP1
  AND #1
  CLC
  ADC WALLP1
  STA WALLP1
  LDA T3
  CMP #F_MINE
  BNE .fe_tile
  LDA #3                       ; a mine: it comes when it reaches the screen
  JMP ADD_U
.fe_tile:
  DEC A                        ; tower / radar / depot: top on (a, b), base on (a - 1, b + 1)
  ASL A
  CLC
  ADC #T_TOWER
  STA T4
  LDA DA
  LDY WALLP1
  JSR MAP_ROW
  LDA T4
  STA (PTR),Y
  LDA DA
  DEC A
  INY
  JSR MAP_ROW
  LDA T4
  INC A
  STA (PTR),Y
  LDA T3
  CMP #F_DEPOT
  BEQ .fe_r
  CMP #F_RADAR
  BNE .fe_t
  INC RADARS
  LDA #2
  JMP ADD_U
.fe_t:
  LDA #1
  ; fall into ADD_U

; A = kind: a new entry in the U list at (DA, WALLP1), altitude WALLP2
ADD_U:
  LDX #NTUR-1
.au_l:
  LDY U_K,X
  BEQ .au_f
  DEX
  BPL .au_l
  RTS
.au_f:
  STA U_K,X
  LDA DA
  STA U_A,X
  LDA WALLP1
  STA U_B,X
  LDA WALLP2
  STA U_H,X
  RTS

; the wall of kind WALLR on row DA, on the island cells T1-T2 (high wall: the gap WALLP1-WALLP2 open;
; fence: posts at the two ends)
PUT_WALL:
  LDA DA
  LDY #0
  JSR MAP_ROW
  LDA T1                       ; T5 / T7: the posts are before T1 + 2 and after T2 - 2
  CLC
  ADC #2
  STA T5
  LDA T2
  SEC
  SBC #2
  STA T7
  LDA DA                       ; only the cells that are shown
  AND #1
  TAY
.pw_l:
  LDA (PTR),Y
  CMP #T_FLOOR
  BNE .pw_n
  LDA WALLR
  CMP #F_HWALL
  BNE .pw_lw
  CPY WALLP1                   ; the gap
  BCC .pw_h
  CPY WALLP2
  BEQ .pw_n
  BCC .pw_n
.pw_h:
  LDA #T_HIGH_WALL
  BRA .pw_s
.pw_lw:
  CMP #F_LWALL
  BNE .pw_fe
  LDA #T_LOW_WALL
  BRA .pw_s
.pw_fe:
  LDA #T_POST
  CPY T5
  BCC .pw_s
  CPY T7
  BEQ .pw_b
  BCS .pw_s
.pw_b:
  LDA #T_BEAM
.pw_s:
  STA (PTR),Y
.pw_n:
  INY
  INY
  CPY #64
  BCC .pw_l
  RTS

; ---------------------------------------------------------------
; the energy fences switch on and off
; ---------------------------------------------------------------
FENCE_TICK:
  DEC FENCT
  BNE .ft_r
  LDA FENCE
  EOR #1
  STA FENCE
  LDA #90                      ; on for 1.5 s, off for 1.5 s (less at higher difficulty)
  SEC
  SBC DIFF
  SBC DIFF
  SBC DIFF
  STA FENCT
  LDX #0                       ; colour of the beam: cyan on grey, or grey on grey
.ft_t:
  LDA #<($2000+T_BEAM*8)
  STA VREG
  TXA
  ORA #(VDP_WRITE_VRAM_BIT | >($2000+T_BEAM*8))
  STA VREG
  LDA #$EE
  LDY FENCE
  BEQ .ft_c
  LDA #$7E
.ft_c:
  LDY #8
.ft_w:
  STA VDATA
  DEY
  BNE .ft_w
  TXA
  CLC
  ADC #8
  TAX
  CPX #$18
  BNE .ft_t
.ft_r:
  RTS

; ---------------------------------------------------------------
; a ground target destroyed at screen cell T0 (row), T1 (column):
; a crater in the map, in both copies and in both name tables
; ---------------------------------------------------------------
DESTROY:
  LDA T0                       ; only rows 1-22
  BEQ .de_x
  CMP #23
  BCC .de_ok
.de_x:
  RTS
.de_ok:
  LDA T1                       ; a = c - r + 2 * DSTEP, b = c + r
  SEC
  SBC T0
  CLC
  ADC DSTEP
  ADC DSTEP
  STA T6
  LDA T1
  CLC
  ADC T0
  STA T7
  TAY
  LDA T6
  JSR MAP_ROW
  LDA #T_CRATER
  STA (PTR),Y
  LDX T0                       ; shown copy, name table shown
  LDY T1
  LDA #T_CRATER
  JSR PUT_SHOWN
  LDX T0                       ; the copy being built (a row not copied yet gets it from SRC)
  INX
  CPX #23
  BCS .de_r
  LDY T1
  DEY
  BMI .de_r
  LDA #T_CRATER
  JSR PUT_BUILT
.de_r:
  LDX #NTUR-1                  ; out of the list of the turrets
.de_u:
  LDA U_K,X
  BEQ .de_un
  CMP #3
  BEQ .de_un
  LDA U_A,X
  CMP T6
  BNE .de_un
  LDA U_B,X
  CMP T7
  BNE .de_un
  LDA U_K,X
  CMP #2
  BNE .de_uz
  DEC RADARS
.de_uz:
  STZ U_K,X
.de_un:
  DEX
  BPL .de_u
  RTS

; X = row, Y = column, A = tile: into SRC and the name table shown
PUT_SHOWN:
  PHA
  STZ HOFF
  LDA NTSEL
  BEQ .ps_h
  LDA #4
  STA HOFF
.ps_h:
  JSR CELL_PTR_SRC
  PLA
  STA (PTR),Y
  PHA
  JSR NT_XY
  PLA
  STA VDATA
  STZ HOFF
  RTS

; X = row, Y = column, A = tile: into DST and the hidden name table
PUT_BUILT:
  PHA
  STZ HOFF
  LDA NTSEL
  BNE .pb_h
  LDA #4
  STA HOFF
.pb_h:
  TXA
  STA T2
  LDA DST
  STA PTR+1
  LDA T2
  JSR ROW_PTR
  PLA
  STA (PTR),Y
  PHA
  JSR NT_XY
  PLA
  STA VDATA
  STZ HOFF
  RTS
ROW_PTR:
  LSR A                        ; PTR = DST page + row * 32 (Y = column)
  LSR A
  LSR A
  CLC
  ADC PTR+1
  STA PTR+1
  LDA T2
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA PTR
  RTS

; X = row, Y = column: PTR = row in SRC (Y = column); keeps X, Y
CELL_PTR_SRC:
  TXA
  STA T2
  LDA SRC
  STA PTR+1
  LDA T2
  JMP ROW_PTR

; X = row, Y = column: A = tile shown there (0 off the playfield)
TILE_AT:
  CPX #1
  BCC .ta_0
  CPX #23
  BCS .ta_0
  CPY #32
  BCS .ta_0
  JSR CELL_PTR_SRC
  LDA (PTR),Y
  RTS
.ta_0:
  LDA #0
  RTS

; ===============================================================
;  THE SHIP
; ===============================================================
START_SHIP:
  LDX #NOBJ-1
.ss_o:
  STZ O_K,X
  DEX
  BPL .ss_o
  STZ GSTATE
  STZ GSTAT
  STZ FIGHTN
  STZ RR
  STZ ALARMT
  LDA #24
  STA SL
  STA SH
  LDA #$FF
  STA ENERGY
  LDA #8
  STA ETIM
  JMP SHIP_POS

; ground point from the sideways position, engine from the altitude
SHIP_POS:
  LDA SL
  CLC
  ADC #SHIP_X0
  STA SGX
  LDA SL
  CLC
  ADC #SHIP_Y0
  STA SGY
  LDA SH
  LSR A
  LSR A
  INC A
  STA ENGINE
  RTS

UPDATE_SHIP:
  LDA JOYC                     ; ---- sideways: 2 pixels a frame
  AND #%00000100
  BEQ .us_r
  LDA SL
  CMP #SL_MIN+2
  BEQ .us_r
  DEC SL
  DEC SL
.us_r:
  LDA JOYC
  AND #%00001000
  BEQ .us_u
  LDA SL
  CMP #SL_MAX
  BEQ .us_u
  INC SL
  INC SL
.us_u:
  LDA JOYC                     ; ---- altitude: 1 pixel a frame
  AND #%00000001
  BEQ .us_d
  LDA SH
  CMP #SH_MAX
  BCS .us_d
  INC SH
.us_d:
  LDA JOYC
  AND #%00000010
  BEQ .us_p
  LDA SH
  BEQ .us_p
  DEC SH
.us_p:
  JSR SHIP_POS
  LDA JOYC                     ; ---- button 1: fire (held: again every 10 frames)
  AND #%00010000
  BEQ .us_b
  LDA JOYP
  AND #%00010000
  BEQ .us_fire
  LDA FRAME_CNT
  AND #$07
  BNE .us_b
.us_fire:
  LDX #0
  LDA O_K
  BEQ .us_shot
  INX
  LDA O_K+1
  BNE .us_b
.us_shot:
  LDA #K_SHOT
  JSR NEW_AT_SHIP
  LDA #3                       ; up right, 3 pixels a frame
  STA O_VXH,X
  LDA #$FD
  STA O_VYH,X
  LDA #26
  STA O_T,X
  LDA #W_SHOT
  LDX #0
  JSR SFX_WHISTLE
.us_b:
  LDA JOYC                     ; ---- button 2: a bomb
  AND #%00100000
  BEQ .us_c
  LDA JOYP
  AND #%00100000
  BNE .us_c
  LDA O_K+2
  BNE .us_c
  LDX #2
  LDA #K_BOMB
  JSR NEW_AT_SHIP
  LDA #$FE                     ; down 2 pixels a frame
  STA O_VHH,X
  LDA #W_BOMB
  LDX #0
  JSR SFX_WHISTLE
.us_c:
  ; ---- what is under the shadow
  LDA SGY
  LSR A
  LSR A
  LSR A
  TAX
  LDA SGX
  LSR A
  LSR A
  LSR A
  TAY
  JSR TILE_AT
  TAX
  LDA CLASS_T,X
  BEQ .us_ok
  CMP #1
  BNE .us_lw
  LDA SH                       ; towers, radars, depots
  CMP #OBJ_HIGH
  BCC .us_crash
  RTS
.us_lw:
  CMP #2
  BNE .us_hw
  LDA SH                       ; low wall
  CMP #WALL_LOW
  BCC .us_crash
  RTS
.us_hw:
  CMP #3
  BEQ .us_crash                ; high wall
  LDA FENCE                    ; energy fence: on, it stops who flies above 16
  BEQ .us_ok
  LDA SH
  CMP #FENCE_LOW
  BCS .us_crash
.us_ok:
  RTS
.us_crash:
  JMP SHIP_DIE

; X = slot, A = kind: a new object at the ship (ground point and altitude), no velocity
NEW_AT_SHIP:
  STA O_K,X
  LDA SGX
  STA O_X,X
  LDA SGY
  STA O_Y,X
  LDA SH
  STA O_H,X
  ; fall into CLEAR_V

; X = slot: velocities and fractions to 0
CLEAR_V:
  STZ O_XL,X
  STZ O_YL,X
  STZ O_HL,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_VHL,X
  STZ O_VHH,X
  STZ O_T,X
  RTS

; the ship is lost: an explosion, the world stops
SHIP_DIE:
  LDA #1
  STA GSTATE
  LDA #150
  STA GT
  STZ SCROLL
  STZ ENGINE
  JSR FREE_SLOT
  BCS .sd_s
  LDA #K_BOOM
  JSR NEW_AT_SHIP
  LDA #40
  STA O_T,X
.sd_s:
  LDA #S_BIG
  LDX #2
  JMP SFX_BOOM

; energy: down by one every 8 frames (6 at higher difficulty), alarm below a quarter
ENERGY_TICK:
  LDA GSTAT                    ; facing the Guardian the ship hovers: no energy used
  CMP #2
  BEQ .et_r
  DEC ETIM
  BNE .et_a
  LDA #8
  LDX DIFF
  CPX #4
  BCC .et_t
  LDA #6
.et_t:
  STA ETIM
  LDA ENERGY
  BEQ .et_out
  DEC ENERGY
.et_a:
  LDA ENERGY
  CMP #64
  BCS .et_r
  DEC ALARMT
  BNE .et_r
  LDA #60
  STA ALARMT
  LDA #W_ALARM
  LDX #2
  JMP SFX_WHISTLE
.et_r:
  RTS
.et_out:
  JMP SHIP_DIE

; X = a free slot 3-13 (carry clear), carry set = none
FREE_SLOT:
  LDX #3
.fr_l:
  LDA O_K,X
  BEQ .fr_ok
  INX
  CPX #NOBJ
  BNE .fr_l
  SEC
  RTS
.fr_ok:
  CLC
  RTS


; ===============================================================
;  OBJECTS IN THE AIR
; ===============================================================
UPDATE_OBJECTS:
  LDX #NOBJ-1
.uo_l:
  STX SLOT
  LDA O_K,X
  BNE .uo_go
  JMP .uo_n
.uo_go:
  CMP #K_MINE                  ; mines and ground explosions go with the world
  BEQ .uo_world
  CMP #K_BOOM
  BNE .uo_mv
.uo_world:
  LDA SCROLL
  BEQ .uo_mv
  DEC O_X,X
  DEC O_X,X
  INC O_Y,X
  INC O_Y,X
.uo_mv:
  CLC                          ; ---- velocity
  LDA O_XL,X
  ADC O_VXL,X
  STA O_XL,X
  LDA O_X,X
  ADC O_VXH,X
  STA O_X,X
  CLC
  LDA O_YL,X
  ADC O_VYL,X
  STA O_YL,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  CLC
  LDA O_HL,X
  ADC O_VHL,X
  STA O_HL,X
  LDA O_H,X
  ADC O_VHH,X
  STA O_H,X
  LDA O_X,X                    ; ---- off the screen: gone
  CMP #4
  BCC .uo_free
  CMP #252
  BCS .uo_free
  LDA O_Y,X
  CMP #4
  BCC .uo_free
  CMP #188
  BCS .uo_free
  LDA O_K,X                    ; ---- by kind
  CMP #K_BOMB
  BNE .uo_nb
  LDA O_H,X                    ; the bomb reaches the ground
  BMI .uo_hit
  BNE .uo_n
.uo_hit:
  JSR BOMB_HIT
  BRA .uo_n
.uo_nb:
  CMP #K_FIGHTER
  BNE .uo_t
  JSR STEER                    ; fighters: towards the ship, no timer
  BRA .uo_n
.uo_t:
  CMP #K_MINE
  BEQ .uo_n
  LDA O_T,X                    ; the others live O_T frames
  BEQ .uo_free
  DEC O_T,X
  BEQ .uo_free
  LDA O_K,X
  CMP #K_SHOT
  BNE .uo_n
  JSR SHOT_HITS
  BRA .uo_n
.uo_free:
  STZ O_K,X
.uo_n:
  LDX SLOT
  DEX
  BMI .uo_e
  JMP .uo_l
.uo_e:
  RTS

; X = fighter: sideways towards the ship, half a pixel a frame (it keeps its altitude)
STEER:
  LDA O_X,X
  CLC
  ADC O_Y,X
  ROR A
  STA T0                       ; its line (x + y) / 2
  LDA SGX
  CLC
  ADC SGY
  ROR A
  CMP T0
  BEQ .st_h
  LDA FRAME_CNT
  AND #1
  BEQ .st_h
  BCC .st_l
  INC O_X,X                    ; the ship is further right
  INC O_Y,X
  BRA .st_h
.st_l:
  DEC O_X,X
  DEC O_Y,X
.st_h:
  RTS

; X = bomb on the ground: the target under it (or next to it), an explosion
BOMB_HIT:
  STZ O_K,X
  LDA O_Y,X
  LSR A
  LSR A
  LSR A
  STA T0
  LDA O_X,X
  LSR A
  LSR A
  LSR A
  STA T1
  LDY #0
.bh_l:
  LDA T0                       ; the cell and the 4 around
  CLC
  ADC BH_DR,Y
  STA SMT0
  LDA T1
  CLC
  ADC BH_DC,Y
  STA SMT1
  PHY
  LDX SMT0
  LDY SMT1
  JSR TILE_AT
  PLY
  CMP #T_TOWER
  BCC .bh_n
  CMP #T_DEPOT_BASE+1
  BCC .bh_found
.bh_n:
  INY
  CPY #5
  BNE .bh_l
  LDX SLOT                     ; nothing: a little bang on the ground
  LDA #S_SMALL
  LDY O_X,X
  JSR BOOM_AT
  JMP GROUND_BOOM
.bh_found:
  STA T5                       ; top or base: both go
  LDA SMT0
  STA T0
  LDA SMT1
  STA T1
  LDA T5
  SEC
  SBC #T_TOWER
  AND #1
  BEQ .bh_top
  DEC T0                       ; the base: the top is above
.bh_top:
  JSR DESTROY
  INC T0
  JSR DESTROY
  LDA T5                       ; points and energy
  SEC
  SBC #T_TOWER
  LSR A
  TAX
  LDA TGT_PTS,X
  LDY #0
  PHX
  TAY
  LDA #$00
  JSR ADD_PTS
  PLX
  CPX #2
  BNE .bh_b
  LDA ENERGY                   ; a depot: energy
  CLC
  ADC #80
  BCC .bh_e
  LDA #$FF
.bh_e:
  STA ENERGY
  LDA #W_FUEL
  LDX #0
  JSR SFX_WHISTLE
.bh_b:
  LDX SLOT
  LDA #S_BIG
  LDY O_X,X
  JSR BOOM_AT
  ; fall into GROUND_BOOM

; an explosion on the ground where the bomb (slot SLOT) fell
GROUND_BOOM:
  LDX SLOT
  LDA O_X,X
  STA T2
  LDA O_Y,X
  STA T3
  JSR FREE_SLOT
  BCS .gb_r
  LDA #K_BOOM
  STA O_K,X
  JSR CLEAR_V
  LDA T2
  STA O_X,X
  LDA T3
  STA O_Y,X
  STZ O_H,X
  LDA #24
  STA O_T,X
.gb_r:
  RTS

; X = shot: mines, fighters, rings, the Guardian
SHOT_HITS:
  LDY #3
.sh_l:
  LDA O_K,Y
  CMP #K_MINE
  BEQ .sh_t
  CMP #K_FIGHTER
  BEQ .sh_t
  CMP #K_RING
  BNE .sh_n
.sh_t:
  JSR NEAR3D
  BCC .sh_n
  LDA O_K,Y                    ; hit
  STZ O_K,X
  CMP #K_RING
  BEQ .sh_ring
  PHA
  LDA #K_BOOM                  ; the target explodes
  STA O_K,Y
  LDA #0
  STA O_VXH,Y
  STA O_VYH,Y
  STA O_VHH,Y
  STA O_VXL,Y
  STA O_VYL,Y
  STA O_VHL,Y
  LDA #24
  STA O_T,Y
  LDA O_X,Y
  TAY
  LDA #S_SMALL
  JSR BOOM_AT
  PLA
  LDY #$01                     ; mine 100, fighter 150 (300 when high)
  CMP #K_MINE
  BNE .sh_f
  LDA #$00
  JMP ADD_PTS
.sh_f:
  LDA #$50
  LDX SLOT
  JMP ADD_PTS
.sh_ring:
  LDA #0
  STA O_K,Y
  RTS
.sh_n:
  INY
  CPY #NOBJ
  BNE .sh_l
  LDA GSTAT                    ; ---- the Guardian
  CMP #2
  BNE .sh_r
  JMP SHOT_GUARD
.sh_r:
  RTS

; objects X and Y: carry set = close (ground within 8 pixels, altitude within 10)
NEAR3D:
  LDA O_X,X
  SEC
  SBC O_X,Y
  BPL .n3_a
  EOR #$FF
  INC A
.n3_a:
  CMP #8
  BCS .n3_no
  LDA O_Y,X
  SEC
  SBC O_Y,Y
  BPL .n3_b
  EOR #$FF
  INC A
.n3_b:
  CMP #8
  BCS .n3_no
  LDA O_H,X
  SEC
  SBC O_H,Y
  BPL .n3_c
  EOR #$FF
  INC A
.n3_c:
  CMP #10
  BCS .n3_no
  SEC                          ; close
  RTS
.n3_no:
  CLC
  RTS

; the ship against shells, mines, fighters and rings
SHIP_HITS:
  LDX #3
.si_l:
  LDA O_K,X
  CMP #K_SHELL
  BEQ .si_t
  CMP #K_MINE
  BEQ .si_t
  CMP #K_FIGHTER
  BEQ .si_t
  CMP #K_RING
  BNE .si_n
.si_t:
  LDA O_X,X
  SEC
  SBC SGX
  BPL .si_a
  EOR #$FF
  INC A
.si_a:
  CMP #8
  BCS .si_n
  LDA O_Y,X
  SEC
  SBC SGY
  BPL .si_b
  EOR #$FF
  INC A
.si_b:
  CMP #8
  BCS .si_n
  LDA O_H,X
  SEC
  SBC SH
  BPL .si_c
  EOR #$FF
  INC A
.si_c:
  CMP #10
  BCS .si_n
  STZ O_K,X
  JMP SHIP_DIE
.si_n:
  INX
  CPX #NOBJ
  BNE .si_l
  RTS


; ===============================================================
;  TOWERS, RADARS, MINES: one entry of the list every frame
; ===============================================================
TURRETS:
  LDA GSTATE
  BNE .tu_r
  INC FIREI
  LDA FIREI
  AND #NTUR-1
  STA FIREI
  TAX
  LDA U_K,X
  BEQ .tu_r
  LDA DSTEP                    ; 2c = (a - 2 * DSTEP) + b, 2r = b - (a - 2 * DSTEP)
  ASL A
  STA T0
  LDA U_A,X
  SEC
  SBC T0
  STA T0
  CLC
  ADC U_B,X
  CMP #$80
  ROR A
  STA T1                       ; column (signed)
  LDA U_B,X
  SEC
  SBC T0
  CMP #$80
  ROR A
  STA T0                       ; row (signed)
  LDA T1
  BMI .tu_gone                 ; passed on the left
  LDA T0
  BMI .tu_r                    ; not yet on the screen
  CMP #23
  BCS .tu_gone                 ; passed below
  CMP #1
  BCC .tu_r
  LDA T1
  CMP #32
  BCS .tu_r
  LDA U_K,X                    ; on the screen
  CMP #3
  BEQ .tu_mine
  CMP #1
  BNE .tu_r
  LDY DIFF                     ; a tower may fire
  LDA FIRE_P,Y
  LDY RADARS
  BEQ .tu_p
  ASL A
.tu_p:
  CMP RND
  BCC .tu_r
  JMP FIRE_SHELL
.tu_r:
  RTS
.tu_gone:
  LDA U_K,X
  CMP #2
  BNE .tu_z
  DEC RADARS
.tu_z:
  STZ U_K,X
  RTS
.tu_mine:
  STZ U_K,X                    ; the mine comes into the air
  LDA U_H,X
  STA T2
  JSR FREE_SLOT
  BCS .tu_r
  LDA #K_MINE
  STA O_K,X
  JSR CLEAR_V
  LDA T1
  ASL A
  ASL A
  ASL A
  ORA #4
  STA O_X,X
  LDA T0
  ASL A
  ASL A
  ASL A
  ORA #4
  STA O_Y,X
  LDA T2
  STA O_H,X
  RTS

; a shell from the tower at row T0, column T1 towards the ship (64 frames)
FIRE_SHELL:
  JSR FREE_SLOT
  BCS .fs_r
  LDA #K_SHELL
  STA O_K,X
  JSR CLEAR_V
  LDA T1
  ASL A
  ASL A
  ASL A
  ORA #4
  STA O_X,X
  LDA T0
  ASL A
  ASL A
  ASL A
  STA O_Y,X
  LDA #4
  STA O_H,X
  LDA #64
  STA O_T,X
  LDA SGX                      ; velocity = (target - start) * 4 / 256 per frame
  SEC
  SBC O_X,X
  JSR TIMES4
  STA O_VXH,X
  LDA T6
  STA O_VXL,X
  LDA SGY
  SEC
  SBC O_Y,X
  JSR TIMES4
  STA O_VYH,X
  LDA T6
  STA O_VYL,X
  LDA SH
  SEC
  SBC #4
  JSR TIMES4
  STA O_VHH,X
  LDA T6
  STA O_VHL,X
  LDA #W_BLOCK
  LDX #1
  JMP SFX_WHISTLE
.fs_r:
  RTS

; A = signed difference: T6 = low byte, A = high byte of A * 4 (8.8, as A / 64)
TIMES4:
  STA T6
  LDA #0
  BIT T6
  BPL .t4_p
  LDA #$FF
.t4_p:
  STA T7
  ASL T6
  ROL T7
  ASL T6
  ROL T7
  LDA T7
  RTS

; fighters over the open sky: one every 40 frames
SPAWN_FIGHTERS:
  LDA FIGHTN
  BEQ .sp_r
  LDA GSTATE
  BNE .sp_r
  DEC FIGHTT
  BNE .sp_r
  LDA #44
  SEC
  SBC DIFF
  SBC DIFF
  STA FIGHTT
  JSR FREE_SLOT
  BCS .sp_r
  DEC FIGHTN
  LDA #K_FIGHTER
  STA O_K,X
  JSR CLEAR_V
  LDA RND                      ; sideways L in -40..23: enters from the top at (168 + 2L, 8)
  AND #$3F
  SEC
  SBC #40
  ASL A
  CLC
  ADC #168
  STA O_X,X
  LDA #8
  STA O_Y,X
  LDA RND
  LSR A
  LSR A
  AND #$1F
  CLC
  ADC #12
  STA O_H,X
  LDA #$FD                     ; down left, 3 pixels a frame
  STA O_VXH,X
  LDA #3
  STA O_VYH,X
.sp_r:
  RTS


; ===============================================================
;  THE GUARDIAN: a core with 4 shields turning round it
; ===============================================================
GUARDIAN:
  LDA GSTAT
  BNE .gu_go
  RTS
.gu_go:
  CMP #1
  BNE .gu_2
  DEC GT2                      ; coming: the world stops
  BNE .gu_r
  STZ SCROLL
  LDA #2
  STA GSTAT
  LDA FORT                     ; hits: 4 + fortress / 2 + 2 per cycle
  LSR A
  CLC
  ADC #4
  ADC CYCLE
  ADC CYCLE
  STA GHITS
  STZ GL
  LDA #1
  STA GDIR
  LDA #240
  STA GT2
  LDA #24
  STA GH
.gu_r:
  RTS
.gu_2:
  CMP #2
  BEQ .gu_fight
  CMP #3
  BNE .gu_r
  DEC GT2                      ; exploding
  LDA GT2
  AND #$07
  BNE .gu_r
  JSR FREE_SLOT                ; bangs all round
  BCS .gu_e
  LDA #K_BOOM
  STA O_K,X
  JSR CLEAR_V
  LDA RND
  AND #$1F
  CLC
  ADC GX
  SEC
  SBC #16
  STA O_X,X
  LDA RND
  LSR A
  LSR A
  AND #$1F
  CLC
  ADC GY
  SEC
  SBC #16
  STA O_Y,X
  LDA GH
  STA O_H,X
  LDA #24
  STA O_T,X
  LDA #S_SMALL
  LDY GX
  JSR BOOM_AT
.gu_e:
  LDA GT2
  BNE .gu_r
  STZ GSTAT                    ; the fortress is over
  LDA #2
  STA GSTATE
  LDA #40
  STA GT
  RTS
.gu_fight:
  INC GANG
  INC GANG
  LDA FRAME_CNT                ; sideways back and forth (0-40), every other frame
  AND #1
  BNE .gu_h
  LDA GDIR
  BEQ .gu_left
  INC GL
  LDA GL
  CMP #40
  BNE .gu_h
  STZ GDIR
  BRA .gu_h
.gu_left:
  DEC GL
  BNE .gu_h
  INC GDIR
.gu_h:
  LDA GANG                     ; altitude 24 +- 16, slowly
  LSR A
  LSR A
  LSR A
  AND #$3F
  TAX
  LDA SIN16,X
  CLC
  ADC #24
  STA GH
  LDA GL
  CLC
  ADC #128
  STA GX
  LDA GL
  CLC
  ADC #48
  STA GY
  LDA FRAME_CNT                ; the beat
  AND #$1F
  BNE .gu_f
  LDA #W_BEAT
  LDX #1
  JSR SFX_WHISTLE
.gu_f:
  LDA GSTATE
  BNE .gu_t
  LDA FRAME_CNT                ; a ring towards the ship
  AND #$3F
  CMP DIFF
  BNE .gu_t
  JSR FREE_SLOT
  BCS .gu_t
  LDA #K_RING
  STA O_K,X
  JSR CLEAR_V
  LDA GX
  STA O_X,X
  LDA GY
  STA O_Y,X
  LDA GH
  STA O_H,X
  LDA #64
  STA O_T,X
  LDA SGX
  SEC
  SBC GX
  JSR TIMES4
  STA O_VXH,X
  LDA T6
  STA O_VXL,X
  LDA SGY
  SEC
  SBC GY
  JSR TIMES4
  STA O_VYH,X
  LDA T6
  STA O_VYL,X
  LDA SH
  SEC
  SBC GH
  JSR TIMES4
  STA O_VHH,X
  LDA T6
  STA O_VHL,X
.gu_t:
  LDA FRAME_CNT                ; time: it does not wait for ever
  AND #$03
  BNE .gu_x
  DEC GT2
  BNE .gu_x
  STZ GSTAT                    ; gone: no Guardian bonus
  LDA #2
  STA GSTATE
  LDA #40
  STA GT
.gu_x:
  RTS

; X = shot near the Guardian: a shield stops it, the core is hit
SHOT_GUARD:
  LDA O_Y,X                    ; T2 / T3 = shot on the screen
  SEC
  SBC O_H,X
  STA T3
  LDA O_X,X
  STA T2
  LDA GY
  SEC
  SBC GH
  STA T5                       ; core on the screen
  LDY #3
.sg_s:
  TYA                          ; shield Y: angle GANG + Y * 64
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC GANG
  LSR A
  LSR A
  STA T4
  PHY
  TAY
  LDA SIN18,Y                  ; dy
  CLC
  ADC T5
  SEC
  SBC T3
  JSR ABS8
  CMP #8
  BCS .sg_ns
  LDA T4
  CLC
  ADC #16                      ; cos = sin of angle + 16
  AND #$3F
  TAY
  LDA SIN18,Y
  CLC
  ADC GX
  SEC
  SBC T2
  JSR ABS8
  CMP #8
  BCS .sg_ns
  PLY
  STZ O_K,X                    ; stopped by a shield
  LDA #W_BLOCK
  LDX #0
  JMP SFX_WHISTLE
.sg_ns:
  PLY
  DEY
  BPL .sg_s
  LDA O_X,X                    ; the core: ground and altitude
  SEC
  SBC GX
  JSR ABS8
  CMP #8
  BCS .sg_r
  LDA O_Y,X
  SEC
  SBC GY
  JSR ABS8
  CMP #8
  BCS .sg_r
  LDA O_H,X
  SEC
  SBC GH
  JSR ABS8
  CMP #10
  BCS .sg_r
  STZ O_K,X                    ; hit
  LDA #W_HIT
  LDX #1
  JSR SFX_WHISTLE
  LDA #$00
  LDY #$01
  JSR ADD_PTS
  DEC GHITS
  BNE .sg_r
  LDA #3                       ; destroyed: 2000
  STA GSTAT
  LDA #64
  STA GT2
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
  LDA #$00
  LDY #$20
  JMP ADD_PTS
.sg_r:
  RTS

ABS8:
  BPL .ab_r
  EOR #$FF
  INC A
.ab_r:
  RTS


; ===============================================================
;  SPRITES: the ship and its shadow, the Guardian, then the
;  objects in an order that turns every frame
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA GSTATE
  CMP #1
  BEQ .bs_g
  LDA SGX                      ; ship: detail and body
  STA OX
  LDA SGY
  SEC
  SBC SH
  SEC
  SBC #4
  STA OY
  LDA #PT_SHIP
  STA ON
  LDA #$08
  STA OC
  JSR ADD_SPR
  LDA #PT_SHIP+4
  STA ON
  LDA #$0F
  STA OC
  JSR ADD_SPR
  LDA SGX                      ; the shadow
  STA OX
  LDA SGY
  STA OY
  LDA #PT_SHADOW
  STA ON
  LDA #$01
  STA OC
  JSR ADD_SPR
.bs_g:
  LDA GSTAT                    ; ---- the Guardian
  CMP #2
  BCC .bs_o
  CMP #3
  BNE .bs_gd
  LDA GT2                      ; exploding: flashing
  AND #$04
  BNE .bs_o
.bs_gd:
  LDA GX
  STA OX
  LDA GY
  SEC
  SBC GH
  STA OY
  STA T5
  LDA #PT_CORE
  STA ON
  LDA #$09
  STA OC
  JSR ADD_SPR
  LDY #3
.bs_sh:
  TYA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC GANG
  STA T4
  LSR A
  LSR A
  PHY
  TAY
  LDA SIN18,Y
  CLC
  ADC T5
  STA OY
  TYA
  CLC
  ADC #16
  AND #$3F
  TAY
  LDA SIN18,Y
  CLC
  ADC GX
  STA OX
  LDA T4                       ; the drawing of the shield: by quarter
  CLC
  ADC #32
  ROL A
  ROL A
  ROL A
  AND #$03
  ASL A
  ASL A
  ADC #PT_SHIELD
  STA ON
  LDA #$0E
  STA OC
  JSR ADD_SPR
  PLY
  DEY
  BPL .bs_sh
.bs_o:
  INC RR                       ; ---- objects
  LDA RR
  CMP #NOBJ
  BCC .bs_rr
  STZ RR
.bs_rr:
  LDA RR
  STA SLOT
  LDA #NOBJ
  STA CNT
.bs_ol:
  LDX SLOT
  LDA O_K,X
  BEQ .bs_on
  TAY
  LDA O_X,X
  STA OX
  LDA O_Y,X
  SEC
  SBC O_H,X
  BCC .bs_on                   ; above the top of the screen
  CMP #196
  BCS .bs_on
  STA OY
  LDA K_PAT-1,Y
  STA ON
  LDA K_COL-1,Y
  STA OC
  CPY #K_BOOM
  BNE .bs_add
  LDA O_T,X                    ; explosions: 3 drawings
  LSR A
  LSR A
  LSR A
  AND #$03
  CMP #3
  BCC .bs_bm
  LDA #2
.bs_bm:
  ASL A
  ASL A
  ADC #PT_BOOM
  STA ON
.bs_add:
  CPY #K_RING
  BNE .bs_a2
  LDA O_T,X                    ; rings grow
  CMP #32
  BCS .bs_a2
  LDA #PT_RING+4
  STA ON
.bs_a2:
  JSR ADD_SPR
.bs_on:
  INC SLOT
  LDA SLOT
  CMP #NOBJ
  BCC .bs_nx
  STZ SLOT
.bs_nx:
  DEC CNT
  BNE .bs_ol
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
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

; X = row, Y = column: VDP address of the name table cell (HOFF = 0: $3800, 4: $3C00)
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
;  of the explosions; left chip = the ship, right = the enemies
;  and the engine (noise B when no explosion plays there)
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
  LDA ENGINE                    ; the engine: noise on the right chip, higher with the altitude
  BEQ .st_flush
  LDA EX_ID+1
  BNE .st_flush
  LDA #24
  SEC
  SBC ENGINE
  STA SH_R+6
  LDA SND_PH
  AND #$04
  LSR A
  LSR A
  CLC
  ADC #5
  STA SH_R+9
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
;  REC_SIGN: the sign screen. UP / DOWN change the letter,
;  LEFT / RIGHT move, a button moves on (on the third letter it
;  confirms); after 30 s without a key it confirms by itself.
; ---------------------------------------------------------------
REC_SIGN:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES               ; nothing of the game over the table
  JSR REC_CLS
  LDX #REC_SROW-4
  LDY #11
  LDA #(RT_NEW-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW-2
  LDY #12
  LDA #(RT_PLAYER-REC_TXT)
  JSR REC_PUTS
  LDA REC_PL
  CLC
  ADC #'1'
  STA VDATA
  LDA #REC_SROW
  STA REC_R0
  JSR REC_SHOW_R
  LDX #REC_SROW+10
  LDY #7
  LDA #(RT_H1-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+11
  LDY #7
  LDA #(RT_H2-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+12
  LDY #7
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
  STA VDATA
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
  STA VDATA
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
  STA VDATA
  RTS

; REC_WIPEN rows from REC_ROW blank (REC_WIPE_R: from REC_R0)
REC_WIPE:
  LDA #REC_ROW
  STA REC_R0
REC_WIPE_R:
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
  STA VDATA
  INX
  BRA .pu_l
.pu_e:
  RTS

REC_TXT:
RT_NEW:    .byte "NEW RECORD",0
RT_PLAYER: .byte "PLAYER ",0
RT_H1:     .byte "UP/DOWN    LETTER",0
RT_H2:     .byte "LEFT/RIGHT MOVE",0
RT_H3:     .byte "BUTTON     NEXT/OK",0

; ===============================================================
;  TABLES
; ===============================================================
SC_COL:     .byte 4,26                         ; score of player 1 / 2: column on row 0
PS_OFF:     .byte 0,4                          ; block of the player in PSAVE

; tile -> collision: 0 nothing, 1 tower / radar / depot (low), 2 low wall, 3 high wall / post, 4 energy fence
CLASS_T:    .byte 0, 0,0,0,0,0, 3,0,2,0, 1,1,1,1,1,1, 3,4,0, 0,0,0,0
; tile -> 1 = part of an island (the sky under it shows the rock)
GROUND_T:   .byte 0, 0,0,0,1,0, 1,1,1,1, 1,1,1,1,1,1, 1,1,1, 0,0,0,0
WOBBLE:     .byte 0,0,1,1,1,1,0,0,0,0,0,1,1,0,0,0
; the bomb looks at its cell and at the 4 around (row, column)
BH_DR:      .byte 0,0,0,1,$FF
BH_DC:      .byte 0,1,$FF,0,0
TGT_PTS:    .byte $02,$05,$03                  ; tower 200, radar 500, depot 300 (BCD hundreds)
FIRE_P:     .byte 20,26,32,38,44,50,56,64      ; a tower fires when RND < this (doubled with a radar)
; objects by kind - 1: pattern and colour
K_PAT:      .byte PT_SHOT,PT_BOMB,PT_SHELL,PT_MINE,PT_FIGHTER,PT_BOOM,PT_RING
K_COL:      .byte $0B,$0F,$09,$0D,$03,$0B,$07
SIN18:      .byte $00,$02,$04,$05,$07,$08,$0A,$0B,$0D,$0E,$0F,$10,$11,$11,$12,$12,$12,$12,$12,$11,$11,$10,$0F,$0E,$0D,$0B,$0A,$08,$07,$05,$04,$02
            .byte $00,$FE,$FC,$FB,$F9,$F8,$F6,$F5,$F3,$F2,$F1,$F0,$EF,$EF,$EE,$EE,$EE,$EE,$EE,$EF,$EF,$F0,$F1,$F2,$F3,$F5,$F6,$F8,$F9,$FB,$FC,$FE
SIN16:      .byte $00,$02,$03,$05,$06,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$0F,$10,$10,$10,$10,$10,$0F,$0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$06,$05,$03,$02
            .byte $00,$FE,$FD,$FB,$FA,$F8,$F7,$F6,$F5,$F4,$F3,$F2,$F1,$F1,$F0,$F0,$F0,$F0,$F0,$F1,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$FA,$FB,$FD,$FE

; title: tiles of the ground targets (row, tile at column 4)
TITLE_TR:   .byte 10,11,12,0
TITLE_TT:   .byte T_TOWER,T_RADAR,T_DEPOT
; title sprites: mine, fighter, Guardian, the ship and its shadow (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 14*8-5,16*8-5,18*8-5,26,26,48
TITLE_SX:   .byte 26,26,26,204,204,192
TITLE_SN:   .byte PT_MINE,PT_FIGHTER,PT_CORE,PT_SHIP,PT_SHIP+4,PT_SHADOW
TITLE_SC:   .byte $0D,$03,$09,$08,$0F,$0E

FNAME_LO:   .byte <TXT_F0,<TXT_F1,<TXT_F2,<TXT_F3
FNAME_HI:   .byte >TXT_F0,>TXT_F1,>TXT_F2,>TXT_F3

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 0,12,"HI",0
  .byte 0,23,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 8,8,"- SCORE TABLE -",0
  .byte 10,7,"TOWER          200",0
  .byte 11,7,"RADAR          500",0
  .byte 12,7,"DEPOT   300 + ENERGY",0
  .byte 14,7,"MINE           100",0
  .byte 16,7,"FIGHTER        150",0
  .byte 18,7,"GUARDIAN      2000",0
  .byte 20,2,"STICK=MOVE  B1=FIRE  B2=BOMB",0
  .byte 21,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_BOT:
  .byte 23,0,"E",0
  .byte 23,18,"A",0
  .byte $FF
TXT_PLAYER:
  .byte 9,12,"PLAYER ",0
  .byte $FF
TXT_FORT:
  .byte 11,11,"FORTRESS ",0
  .byte $FF
TXT_F0:
  .byte 13,12,"OUTPOST",0
  .byte $FF
TXT_F1:
  .byte 13,13,"RELAY",0
  .byte $FF
TXT_F2:
  .byte 13,12,"FOUNDRY",0
  .byte $FF
TXT_F3:
  .byte 13,12,"CITADEL",0
  .byte $FF
TXT_BONUS:
  .byte 12,11,"BONUS ",0
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

; the start tune, a march in D minor (composed for this game), 256 frames
;   G4 32  A4 34  Bb4 35  C5 37  D5 39  E5 41  F5 42  G5 44  A5 46
START_LEAD:
  .byte 39,16, 34,8, 39,8, 42,16, 41,8, 39,8
  .byte 37,16, 32,8, 37,8, 41,16, 39,8, 37,8
  .byte 35,16, 42,8, 39,8, 44,16, 42,8, 41,8
  .byte 34,8, 37,8, 41,8, 46,8, 39,32
  .byte $FF
START_HARM:
  .byte 30,64, 29,64, 27,64, 29,32, 30,32
  .byte $FF
START_BASS:
  .byte 15,16, 10,16, 15,16, 10,16, 13,16, 8,16, 13,16, 8,16
  .byte 11,16, 6,16, 8,16, 11,16, 10,16, 10,16, 15,32
  .byte $FF
START_DRUM:
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 1,8, 2,8, 3,8
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
; Cloud Raider: generated by dev/gen_cloud_raider.js (do not edit by hand)

PT_SHIP = 0
PT_SHADOW = 8
PT_SHOT = 12
PT_BOMB = 16
PT_SHELL = 20
PT_MINE = 24
PT_FIGHTER = 28
PT_BOOM = 32
PT_CORE = 44
PT_SHIELD = 48
PT_RING = 64
SPR_PAGES = 3
SPRITES:
;  0 ship detail, 4 ship body, 8 shadow, 12 shot, 16 bomb, 20 shell, 24 mine, 28 fighter, 32 boom 0, 36 boom 1, 40 boom 2, 44 core, 48 shield 0, 52 shield 1, 56 shield 2, 60 shield 3, 64 ring 0, 68 ring 1
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$30,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$23,$37,$3F,$1F,$1F,$3F,$7C,$78,$30,$00
  .byte $00,$1C,$3C,$7C,$F0,$C0,$80,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$1F,$3E,$38,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$18,$F8,$F0,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$30,$70,$E0,$C0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$01,$02,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$C0,$80,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$07,$06,$07,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$C0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$27,$1F,$1B,$3F,$FF,$3F,$1B,$1F,$27,$01,$01,$00,$00,$00
  .byte $00,$00,$C8,$F0,$B0,$F8,$FA,$F8,$B0,$F0,$C8,$00,$00,$00,$00,$00
  .byte $00,$06,$07,$03,$1F,$3F,$7F,$27,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$C0,$E0,$E0,$F0,$F8,$FC,$FC,$38,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$07,$0E,$06,$03,$03,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$E0,$E0,$E0,$60,$E0,$C0,$C0,$80,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$0F,$3F,$3E,$3F,$1C,$0E,$0F,$07,$07,$07,$0F,$00
  .byte $00,$F0,$E0,$F0,$F8,$F8,$FC,$BC,$7E,$FE,$FE,$FC,$1C,$18,$00,$00
  .byte $00,$0E,$0F,$0F,$1F,$3F,$7C,$7E,$1E,$1D,$1F,$7F,$3F,$13,$01,$00
  .byte $00,$00,$E0,$F8,$FC,$FE,$BE,$3E,$3E,$BE,$FE,$F0,$F0,$F0,$C0,$00
  .byte $07,$1F,$3C,$73,$67,$EE,$DC,$DC,$DC,$DC,$EE,$67,$73,$3C,$1F,$07
  .byte $E0,$F8,$3C,$CE,$E6,$77,$3B,$3B,$3B,$3B,$77,$E6,$CE,$3C,$F8,$E0
  .byte $00,$00,$07,$1F,$3F,$78,$70,$60,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$E0,$F8,$FC,$1E,$0E,$06,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$E0,$F0,$78,$38,$1C,$1C,$1C,$1C,$1C,$1C,$38,$78,$F0,$E0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$60,$70,$78,$3F,$1F,$07,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$06,$0E,$1E,$FC,$F8,$E0,$00,$00
  .byte $00,$07,$0F,$1E,$1C,$38,$38,$38,$38,$38,$38,$1C,$1E,$0F,$07,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$06,$04,$04,$06,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$60,$20,$20,$60,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$0F,$18,$10,$30,$30,$30,$30,$10,$18,$0F,$03,$00,$00
  .byte $00,$00,$C0,$F0,$18,$08,$0C,$0C,$0C,$0C,$08,$18,$F0,$C0,$00,$00
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

; tiles
;   1 sky
;   2 cloud a
;   3 cloud b
;   4 floor
;   5 rock
;   6 high wall
;   7 high face
;   8 low wall
;   9 low face
;   10 tower
;   11 tower base
;   12 radar
;   13 radar base
;   14 depot
;   15 depot base
;   16 post
;   17 beam
;   18 crater
;   19 life
;   20 bar full
;   21 bar empty
;   22 alt mark
T_SKY = 1
T_CLOUD_A = 2
T_CLOUD_B = 3
T_FLOOR = 4
T_ROCK = 5
T_HIGH_WALL = 6
T_HIGH_FACE = 7
T_LOW_WALL = 8
T_LOW_FACE = 9
T_TOWER = 10
T_TOWER_BASE = 11
T_RADAR = 12
T_RADAR_BASE = 13
T_DEPOT = 14
T_DEPOT_BASE = 15
T_POST = 16
T_BEAM = 17
T_CRATER = 18
T_LIFE = 19
T_BAR_FULL = 20
T_BAR_EMPTY = 21
T_ALT_MARK = 22
NTILES = 22
TILE_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$7E,$FF,$FF,$7E,$00,$00
  .byte $00,$00,$38,$7C,$FE,$7C,$00,$00,$00,$60,$40,$00,$00,$0C,$00,$00
  .byte $FF,$B7,$4B,$D5,$52,$22,$40,$00,$FF,$88,$88,$FF,$22,$22,$FF,$88
  .byte $FF,$55,$AA,$55,$FF,$55,$AA,$FF,$FF,$81,$BD,$A5,$A5,$BD,$81,$FF
  .byte $FF,$00,$FF,$00,$FF,$00,$00,$00,$18,$18,$3C,$7E,$66,$FF,$FF,$7E
  .byte $7E,$5A,$7E,$5A,$7E,$FF,$00,$00,$81,$C3,$7E,$3C,$18,$18,$18,$3C
  .byte $3C,$18,$18,$3C,$7E,$FF,$00,$00,$3C,$7E,$DB,$FF,$FF,$DB,$FF,$FF
  .byte $FF,$DB,$FF,$7E,$3C,$00,$00,$00,$38,$7C,$38,$38,$38,$38,$38,$7C
  .byte $10,$28,$44,$82,$01,$00,$00,$00,$00,$28,$7C,$FE,$7C,$28,$00,$00
  .byte $03,$07,$0E,$BC,$78,$30,$50,$80,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00
  .byte $00,$FF,$81,$81,$81,$81,$FF,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00
TILE_COL:
  .byte $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4
  .byte $F4,$F4,$F4,$F4,$F4,$F4,$F4,$F4,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $C4,$C4,$C4,$C4,$C4,$C4,$C4,$C4,$96,$96,$96,$96,$96,$96,$96,$96
  .byte $16,$16,$16,$16,$16,$16,$16,$16,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA
  .byte $AE,$AE,$AE,$AE,$AE,$AE,$AE,$AE,$BE,$BE,$BE,$BE,$BE,$BE,$BE,$BE
  .byte $AE,$AE,$AE,$AE,$AE,$AE,$AE,$AE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$3E
  .byte $CE,$CE,$CE,$CE,$CE,$CE,$CE,$CE,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$70,$70,$70,$70,$70,$70,$70,$70
; the floor moved by 0, 2, 4, 6 pixels down left
FLOOR_PH:
  .byte $00,$60,$40,$00,$00,$0C,$00,$00,$00,$00,$00,$81,$01,$00,$00,$30
  .byte $00,$C0,$00,$00,$00,$06,$04,$00,$10,$00,$00,$03,$00,$00,$00,$18

; big letters of the title, 4 tiles each (200-235)
BIG_P:
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
BIG_C:
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40

TXT_BIG:
  .byte 3,11,200,201,204,205,208,209,212,213,216,217,0
  .byte 4,11,202,203,206,207,210,211,214,215,218,219,0
  .byte 5,10,220,221,224,225,228,229,216,217,232,233,220,221,0
  .byte 6,10,222,223,226,227,230,231,218,219,234,235,222,223,0
  .byte $FF

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <176,>176, <TILE_PAT,>TILE_PAT
  .byte 1, $08,$60, <176,>176, <TILE_COL,>TILE_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <176,>176, <TILE_PAT,>TILE_PAT
  .byte 1, $08,$68, <176,>176, <TILE_COL,>TILE_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <176,>176, <TILE_PAT,>TILE_PAT
  .byte 1, $08,$70, <176,>176, <TILE_COL,>TILE_COL
  .byte 1, $40,$46, <288,>288, <BIG_P,>BIG_P
  .byte 1, $40,$66, <288,>288, <BIG_C,>BIG_C
  .byte 0

; fortresses: terrain (rows, half width; 0,0 = end) and features (delta rows, kind, p1, p2; kind 0 = nothing)
F_TOWER = 1
F_RADAR = 2
F_DEPOT = 3
F_MINE = 4
F_HWALL = 5
F_LWALL = 6
F_FENCE = 7
F_FIGHT = 8
F_GUARD = 9
TERR_LO: .byte <TERR0,<TERR1,<TERR2,<TERR3
TERR_HI: .byte >TERR0,>TERR1,>TERR2,>TERR3
FEAT_LO: .byte <FEAT0,<FEAT1,<FEAT2,<FEAT3
FEAT_HI: .byte >FEAT0,>FEAT1,>FEAT2,>FEAT3
; OUTPOST: 920 rows, 27 features
TERR0:
  .byte $28,$00,$46,$0B,$31,$09,$4B,$0A,$42,$0C,$2B,$0D,$32,$0D,$38,$09
  .byte $45,$0A,$2A,$09,$FF,$00,$69,$00,$00,$00
FEAT0:
  .byte $46,$06,$00,$00,$1F,$01,$1D,$00,$0F,$01,$1A,$00,$16,$03,$1D,$00
  .byte $0E,$05,$1C,$20,$1F,$01,$20,$00,$14,$04,$24,$1F,$06,$04,$20,$1A
  .byte $10,$06,$00,$00,$22,$01,$1F,$00,$14,$01,$21,$00,$10,$03,$26,$00
  .byte $0E,$05,$17,$1B,$1C,$01,$1B,$00,$14,$04,$23,$16,$06,$04,$23,$09
  .byte $10,$06,$00,$00,$1E,$01,$1D,$00,$0E,$01,$17,$00,$0E,$03,$21,$00
  .byte $16,$05,$18,$1C,$18,$01,$1B,$00,$13,$04,$15,$12,$06,$04,$15,$13
  .byte $48,$08,$06,$00,$64,$08,$06,$00,$78,$09,$00,$00,$FF,$FF,$00,$00
; RELAY: 960 rows, 28 features
TERR1:
  .byte $28,$00,$42,$09,$2D,$0A,$43,$0A,$39,$0C,$4A,$09,$37,$0A,$39,$0A
  .byte $43,$0D,$48,$0B,$FF,$00,$69,$00,$00,$00
FEAT1:
  .byte $46,$07,$00,$00,$18,$02,$1D,$00,$12,$01,$20,$00,$12,$03,$19,$00
  .byte $0F,$07,$00,$00,$21,$01,$15,$00,$15,$05,$1C,$1F,$1A,$04,$1A,$0C
  .byte $06,$04,$1B,$16,$13,$07,$00,$00,$1B,$02,$20,$00,$16,$01,$18,$00
  .byte $0E,$03,$1A,$00,$12,$07,$00,$00,$22,$01,$1A,$00,$14,$05,$18,$1B
  .byte $1A,$04,$18,$24,$06,$04,$1C,$10,$0F,$07,$00,$00,$1A,$02,$1B,$00
  .byte $0F,$01,$16,$00,$15,$03,$1E,$00,$15,$07,$00,$00,$18,$01,$14,$00
  .byte $10,$05,$20,$23,$41,$08,$08,$00,$64,$08,$08,$00,$78,$09,$00,$00
  .byte $FF,$FF,$00,$00
; FOUNDRY: 1000 rows, 37 features
TERR2:
  .byte $28,$00,$3D,$0C,$3D,$0B,$50,$09,$46,$0D,$3B,$09,$35,$0B,$38,$0B
  .byte $37,$0D,$30,$0B,$39,$0B,$FF,$00,$69,$00,$00,$00
FEAT2:
  .byte $46,$05,$20,$24,$19,$01,$17,$00,$04,$01,$19,$00,$0F,$03,$1C,$00
  .byte $14,$01,$1A,$00,$04,$01,$1B,$00,$0C,$05,$19,$1D,$22,$06,$00,$00
  .byte $18,$01,$21,$00,$04,$01,$1B,$00,$11,$03,$15,$00,$11,$05,$1F,$23
  .byte $18,$01,$15,$00,$04,$01,$25,$00,$0E,$03,$18,$00,$12,$01,$1C,$00
  .byte $04,$01,$12,$00,$0A,$05,$19,$1D,$21,$06,$00,$00,$1B,$01,$22,$00
  .byte $04,$01,$18,$00,$0C,$03,$15,$00,$14,$05,$14,$18,$20,$01,$19,$00
  .byte $04,$01,$22,$00,$0F,$03,$1A,$00,$11,$01,$1B,$00,$04,$01,$13,$00
  .byte $10,$05,$1B,$1F,$1B,$06,$00,$00,$20,$01,$1A,$00,$04,$01,$13,$00
  .byte $0C,$03,$1E,$00,$10,$05,$16,$1A,$41,$08,$0A,$00,$64,$08,$0A,$00
  .byte $78,$09,$00,$00,$FF,$FF,$00,$00
; CITADEL: 1040 rows, 45 features
TERR3:
  .byte $28,$00,$39,$0A,$43,$09,$2F,$09,$43,$0D,$4C,$0C,$2E,$0B,$40,$0B
  .byte $2D,$0A,$3B,$0D,$38,$09,$2D,$0D,$0B,$0A,$FF,$00,$69,$00,$00,$00
FEAT3:
  .byte $46,$05,$1C,$1F,$1A,$07,$00,$00,$22,$01,$18,$00,$04,$01,$23,$00
  .byte $0B,$02,$20,$00,$04,$02,$15,$00,$0C,$04,$21,$16,$06,$04,$20,$1D
  .byte $06,$04,$19,$1A,$0D,$06,$00,$00,$20,$03,$1E,$00,$11,$04,$11,$18
  .byte $06,$04,$27,$24,$06,$04,$15,$29,$0A,$01,$1B,$00,$04,$01,$1E,$00
  .byte $0F,$05,$18,$1B,$1F,$07,$00,$00,$1C,$01,$26,$00,$04,$01,$1B,$00
  .byte $0D,$02,$23,$00,$04,$02,$21,$00,$11,$04,$23,$2A,$06,$04,$14,$12
  .byte $06,$04,$15,$1C,$0F,$06,$00,$00,$1E,$03,$22,$00,$16,$04,$1F,$17
  .byte $06,$04,$22,$28,$06,$04,$1C,$16,$0D,$01,$1F,$00,$04,$01,$16,$00
  .byte $0B,$05,$1F,$22,$19,$07,$00,$00,$1E,$01,$20,$00,$04,$01,$17,$00
  .byte $12,$02,$19,$00,$04,$02,$16,$00,$10,$04,$1D,$08,$06,$04,$17,$17
  .byte $06,$04,$1A,$1D,$11,$06,$00,$00,$52,$08,$0C,$00,$64,$08,$0C,$00
  .byte $78,$09,$00,$00,$FF,$FF,$00,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$1A,$1D,$21,$26,$2D,$36,$45,$23,$24,$25,$26,$27,$28,$29,$2B
  .byte $2C,$2E,$2F,$31,$33,$35,$38,$3A,$3D,$40,$43,$47,$4B,$4F,$54,$5A
  .byte $61,$69,$72,$7D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$3F,$3F,$3F,$3F
  .byte $3F,$3F,$3F,$3F,$D0,$92,$70,$5B,$4D,$42,$3A,$34,$15,$16,$17,$18
  .byte $19,$38,$38,$38,$38,$38,$00,$00,$00,$00,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $78,$78,$78,$50,$50,$50,$3C,$3C,$3C,$28,$28,$28,$78,$78,$78,$78
  .byte $78,$5F,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C
  .byte $50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$2F,$28
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
  .byte $28,$28,$28,$28,$00,$00,$00,$28,$28,$28,$28,$28,$00,$00,$00,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$B3
  .byte $B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF
  .byte $EF,$28,$28,$28,$18,$20,$20,$6A,$6A,$6A,$6A,$47,$47,$47,$47,$54
  .byte $54,$54,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$02,$02,$02,$02,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0B,$0A,$09,$08,$07,$06,$05,$09,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$07,$07,$07,$06
  .byte $06,$06,$06,$06,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A
  .byte $0A,$0A,$0A,$0A,$0D,$0C,$0C,$0B,$0A,$09,$09,$08,$0A,$09,$08,$07
  .byte $06,$0C,$0A,$08,$06,$04,$00,$00,$00,$00,$0C,$0A,$08,$07,$05,$03
  .byte $0C,$0B,$09,$0C,$0B,$09,$0C,$0B,$09,$0C,$0B,$09,$0D,$0C,$0B,$09
  .byte $08,$0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08
  .byte $0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08,$0D
  .byte $0D,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$0D
  .byte $0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D
  .byte $0C,$0A,$09,$08,$07,$05,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C
  .byte $0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C
  .byte $0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$07,$06
  .byte $06,$0C,$0A,$08,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C
  .byte $0B,$09,$0D,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$03
WH_START:
  .byte $00,$01,$08,$24,$34,$3C,$41,$50,$5C,$8F,$A7,$D1,$D4,$D7
WH_LEN:
  .byte $00,$07,$1C,$10,$08,$05,$0F,$0C,$33,$18,$2A,$03,$03,$17
W_SHOT = 1
W_BOMB = 2
W_ALARM = 3
W_HIT = 4
W_BLOCK = 5
W_BEAT = 6
W_FUEL = 7
W_CLEAR = 8
W_EXTRA = 9
W_OVER = 10
W_BONUS = 11
W_KEY = 12
W_SIGN = 13

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01
EX_NP:
  .byte $00,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C,$0D
  .byte $0D,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $0B,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $0F,$10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11,$11
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B
  .byte $0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07
  .byte $07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03
  .byte $03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00,$00
EX_TL:
  .byte $00,$87,$96,$A6,$B8,$CC,$E1,$F8,$12,$2E,$4E,$71,$99,$C6,$FA,$36
  .byte $7D,$7D,$E5,$90,$71,$82,$C7,$4A,$08,$A2,$75,$79,$AE,$1D,$31,$B9
  .byte $7D,$73,$99,$F7,$61,$D4,$88,$71,$89,$D6,$64,$F5,$98,$73,$7D,$BA
  .byte $34,$1B,$AC,$78,$76,$A3,$0B,$47,$C5,$82,$72,$91,$E7,$79,$E3,$8F
  .byte $71,$83,$C8,$4D,$06,$A1,$75,$79,$AF,$20,$2F,$B7,$7C
EX_TH:
  .byte $00,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$03
  .byte $03,$03,$02,$02,$02,$02,$02,$03,$03,$02,$02,$02,$02,$03,$03,$02
  .byte $02,$02,$02,$02,$03,$02,$02,$02,$02,$02,$03,$02,$02,$02,$02,$02
  .byte $03,$03,$02,$02,$02,$02,$03,$03,$02,$02,$02,$02,$02,$03,$02,$02
  .byte $02,$02,$02,$03,$03,$02,$02,$02,$02,$03,$03,$02,$02
EX_START:
  .byte $00,$01,$11
EX_LEN:
  .byte $00,$10,$3C
S_SMALL = 1
S_BIG = 2
