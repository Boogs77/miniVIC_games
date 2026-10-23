;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_MOON_CRESTA  -  Nichibutsu Moon Cresta (1980)       ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: space firebird (starfield, flight of the aliens,     ;
;   NMI + trampoline $0FD0, AY engine) and tank (music)        ;
;                                                              ;
;   - a rocket in 3 stages: you fly stage I, stages II and     ;
;     III wait below; after waves 4 and 8 they DOCK: the ship  ;
;     comes down on the next stage, button = retro rockets,    ;
;     LEFT / RIGHT = line up; bonus = seconds left x 100; a    ;
;     bad docking destroys the stage waiting                   ;
;   - every stage is a life: when one is hit it is lost and    ;
;     the others go on; stage I fires 1 shot, II 2, III 2      ;
;   - waves: COLD EYE (they split in two when hit) 50, SUPER   ;
;     FLY 30, FOUR-D 60, METEOR 200, ATOMIC PILE 100; after    ;
;     10 waves the rocket comes apart and the cycle starts     ;
;     again faster; a lost stage comes back at 30000           ;
;   - 1 or 2 players (alternating), title: button 1 = 1        ;
;     player, button 2 = 2 players                             ;
;   - joystick 1 ($D581) or joystick 2 ($D580):                ;
;       LEFT / RIGHT = move, button = fire (one volley at a    ;
;       time)                                                  ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     start tune, shot, split, alien hit, dive, retro rockets, ;
;     docking, explosions, extra stage                         ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page ----------------
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
TP          = $72      ; 2 bytes: text records
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)
JOYC        = $80      ; both joysticks together
JOYP        = $81      ; JOYC of the previous frame
PLX         = $82      ; rocket X (centre)
PLST        = $83      ; 0 playing, 1 exploding, 3 explosion over
PLT         = $84      ; timer of the explosion
CURP        = $85      ; player playing (0 / 1)
NPL         = $86      ; number of players
ALIVE       = $87      ; 2 bytes: stages left to every player (0 = out)
SCL         = $89      ; 2 bytes: score per player (BCD): tens and units
SCM         = $8B      ; 2 bytes: thousands and hundreds
SCH         = $8D      ; 2 bytes: hundred thousands and ten thousands
HISC        = $8F      ; 3 bytes BCD (low, middle, high)
WAVE        = $92      ; ---- block of the player, saved: wave of the cycle (0-9)
CYC         = $93      ;      cycle (0 = the first)
WAVEN       = $94      ;      number of the wave on the screen (1-99)
AVAIL       = $95      ;      stages not destroyed (bit 0 = I, 1 = II, 2 = III)
ACTIVE      = $96      ;      stages docked together and flying
EXTRA       = $97      ;      1 = the stage at 30000 was given
LEFT        = $98      ;      aliens still to come in this wave
FIRECD      = $9A      ; frames before the next volley
SATB        = $9B      ; bytes of the SAT to copy
NACT        = $9C      ; aliens on the screen (or waiting to enter)
PTS_L       = $9D      ; points to add (BCD)
PTS_M       = $9E
DIFF        = $9F      ; difficulty: min(cycle, 3)
KIND        = $A0      ; kind of alien of the wave
SPAWNT      = $A1      ; frames before the next group can come
SI          = $A2      ; shot being handled
TX          = $A3      ; target of an angle / position
TY          = $A4
SX          = $A5      ; source of an angle
SY          = $A6
FLASH       = $A7      ; frames of the red flash
AX          = $A8      ; |dx| / 2, |dy| / 2 of ANGLE_TO
AY          = $A9
SGN         = $AA      ; bit 1 = dx negative, bit 0 = dy negative
TRN         = $AB      ; max turn per frame, and its negative
TRNEG       = $AC
HITSTG      = $AD      ; stage hit (0-2)
HW          = $AE      ; half width for the hits
CNT         = $AF
SND_PTR     = $B0      ; 2 bytes: music
NSTG        = $B2      ; stages in the rocket
STG_LIST    = $B3      ; 3 bytes: the stages from the top down
STKY        = $B6      ; Y of the lowest stage (centre)
TOPY        = $B7      ; Y of the highest stage
DVYL        = $B8      ; docking: falling speed 8.8 (signed)
DVYH        = $B9
DYL         = $BA      ; docking: fraction of STKY
DOCKV       = $BD      ; 1 = docking: the stage waiting is shown
THR         = $BE      ; 1 = retro rockets on
DOCKS       = $BF      ; stage waiting to dock (0-2)
DSEC        = $CB      ; docking: seconds left
DFR         = $CC      ; docking: frames to the next second
FIRSTT      = $CD      ; 1 = first turn of the game: start tune
GRP         = $CE      ; groups sent (side of the super flies)
MAXA        = $CF      ; highest stage flying

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

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
EX_ID      = $0704       ; explosion playing per chip (S_*)
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

; ---------------- aliens: E_ST 0 free, 1 waiting to enter, 2 flying
NE     = 10
E_ST   = $0300
E_K    = $030A           ; kind (K_*)
E_T    = $0314           ; timer of the mode
E_HP   = $031E           ; hits still needed
E_XL   = $0328           ; X 8.8
E_X    = $0332
E_YL   = $033C           ; Y 8.8
E_Y    = $0346
E_ANG  = $0350           ; direction 0-255 (0 up, clockwise)
E_TURN = $035A           ; turn per frame
E_MODE = $0364           ; M_*
E_SPD  = $036E           ; speed 0-3
E_TGX  = $0378           ; centre of the atomic pile
E_TGY  = $0382
E_FLSH = $038C           ; frames of the white flash (hit)
E_PH   = $0396           ; atom: phase around the centre
E_AUX  = $03A0           ; atom: the pile drifts this way (+1 / -1)

K_EYE   = 0              ; kinds of alien
K_SMALL = 1
K_FLY   = 2
K_FOURD = 3
K_ROCK  = 4
K_ATOM  = 5

M_ENTER  = 0             ; modes of flight
M_WANDER = 1
M_DIVE   = 2
M_SWAY   = 3
M_EXIT   = 4
M_ORBIT  = 5
M_APPEAR = 6

; ---------------- shots of the rocket: 0 stage I, 1-2 stage II, 3-4 stage III
NS     = 5
S_ON   = $0400
S_X    = $0405
S_Y    = $040A

; ---------------- explosions
NX     = 6
X_T    = $04B0           ; frames left (0 = free)
X_X    = $04B6
X_Y    = $04BC

ST_Y   = $04C8           ; line of every kind of star (0-63)

PSAVE      = $0500       ; 2 x 8 bytes: block of every player
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
BASE_Y      = 174        ; lowest stage of the rocket (centre)
FIELD_TOP   = 24         ; highest Y of the aliens (below the scores)
STG_H       = 12         ; height of a stage
DOCK_X      = 128        ; the stage waiting to dock
X_MIN       = 12         ; rocket
X_MAX       = 244
HUD_T       = 96         ; HUD tiles of the third 2: stage I, II, III
BTN_MASK    = %00110000

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
  STA FLASH
  STA DOCKV
  STA THR
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ ALIVE,X
  DEX
  BPL .rs_p
  LDX #7                       ; the stars where the patterns have them
.rs_s:
  LDA STAR_Y0,X
  STA ST_Y,X
  DEX
  BPL .rs_s
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the scoring table; button 1 = 1 player, 2 = 2 players
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR BACKDROP_BLACK
  JSR DRAW_STARS
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
  LDX #$00                     ; the aliens of the table (sprites)
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
  CPX #8
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR STAR_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR STAR_FRAME
  JSR READ_JOY
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
  ; fall into NEW_GAME


; ===============================================================
;  NEW GAME: wave 1 and the three stages for every player
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
  STZ WAVE
  STZ CYC
  LDA #$01
  STA WAVEN
  LDA #%00000111
  STA AVAIL
  LDA #%00000001
  STA ACTIVE
  STZ EXTRA
  LDA WAVE_N
  STA LEFT
  LDX CURP
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  STZ GRP
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER: "PLAYER <n>" and "WAVE <n>", then the game
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDX CURP
  JSR LOAD_PLAYER
  JSR SET_LEVEL
  JSR CLEAR_OBJECTS
  LDA #128
  STA PLX
  STZ PLST
  STZ FLASH
  STZ DOCKV
  STZ THR
  LDA #BASE_Y
  STA STKY
  JSR SET_STACK
  LDA #90
  STA SPAWNT
  JSR BACKDROP_BLACK
  JSR DRAW_FIELD
  LDA NPL
  CMP #$02
  BNE .ts_1p
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ts_1p:
  LDA #<TXT_WAVE
  STA TP
  LDA #>TXT_WAVE
  STA TP+1
  JSR PRINT
  LDA WAVEN
  JSR BIN2BCD
  LDX #13
  LDY #17
  JSR PUT_BCD2
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA FIRSTT
  BEQ .ts_jingle
  STZ FIRSTT                   ; the start tune, to the end
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_STARS
.ts_tune:
  JSR STAR_FRAME
  LDA SND_BUSY
  BNE .ts_tune
  LDA #20
  JSR WAIT_STARS
  BRA .ts_go
.ts_jingle:
  LDA #W_WAVE
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_STARS
.ts_go:
  JSR VDP_INT_OFF
  LDX #11                      ; the stars back under the messages
  LDA #3
  JSR RESTORE_ROWS
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
  JSR SCROLL_STARS
  JSR DO_FLASH
  JSR UPDATE_SHIP
  JSR SPAWN
  JSR UPDATE_ALIENS
  JSR UPDATE_SHOTS
  JSR UPDATE_EXPL
  JSR BLINK_UP
  JSR BUILD_SAT
  LDA JOYC
  STA JOYP
  JSR VDP_INT_ON
  LDA PLST
  BEQ .gl_end
  CMP #$03
  BNE .gl_n
  JMP LOSE_LIFE
.gl_end:
  LDA LEFT                     ; wave over: no more aliens to come or on the screen
  ORA NACT
  BNE .gl_n
  JMP WAVE_END
.gl_n:
  JMP GAME_LOOP

; WAVE / CYC -> KIND, DIFF = min(cycle, 3)
SET_LEVEL:
  LDX WAVE
  LDA WAVE_K,X
  STA KIND
  LDA CYC
  CMP #4
  BCC .sl_d
  LDA #3
.sl_d:
  STA DIFF
  RTS

; ACTIVE -> STG_LIST (from the top down), NSTG, MAXA, TOPY
SET_STACK:
  STZ NSTG
  STZ MAXA
  LDX #$00
.ss_l:
  LDA ACTIVE
  AND BIT_T,X
  BEQ .ss_n
  LDY NSTG
  TXA
  STA STG_LIST,Y
  STA MAXA
  INC NSTG
.ss_n:
  INX
  CPX #3
  BNE .ss_l
  ; fall into SET_TOPY

; TOPY = STKY - (NSTG - 1) * STG_H
SET_TOPY:
  LDA STKY
  LDX NSTG
  BEQ .st_r
.st_l:
  DEX
  BEQ .st_r
  SEC
  SBC #STG_H
  BRA .st_l
.st_r:
  STA TOPY
  RTS

; A = lowest stage of the mask in A (bit), 0 if the mask is empty
LOW_BIT:
  LDX #$00
.lb_l:
  LSR A
  BCS .lb_f
  INX
  CPX #3
  BNE .lb_l
  LDA #$00
  RTS
.lb_f:
  LDA BIT_T,X
  RTS


; ---------------------------------------------------------------
; the wave is over: docking after waves 4 and 8, a new cycle after 10
; ---------------------------------------------------------------
WAVE_END:
  LDX #$FF
  TXS
  LDA #40                      ; the last explosions
  JSR WAIT_ANIM
  JSR HIDE_SPRITES
  LDA WAVE
  CMP #3
  BEQ .we_dock
  CMP #7
  BNE .we_next
.we_dock:
  JSR TRY_DOCK
.we_next:
  INC WAVE
  LDA WAVE
  CMP #10
  BNE .we_s
  STZ WAVE                     ; a new cycle: the rocket comes apart
  LDA CYC
  CMP #99
  BCS .we_c
  INC CYC
.we_c:
  LDA AVAIL
  JSR LOW_BIT
  STA ACTIVE
.we_s:
  LDA WAVEN
  CMP #99
  BCS .we_w
  INC WAVEN
.we_w:
  LDX WAVE
  LDA WAVE_N,X
  STA LEFT
  LDX CURP
  JSR SAVE_PLAYER
  JMP TURN_START


; ---------------------------------------------------------------
; the explosion of a stage is over
; ---------------------------------------------------------------
LOSE_LIFE:
  LDX #$FF
  TXS
  JSR COUNT_BACK               ; the aliens on the screen come back later
  CLC
  ADC LEFT
  STA LEFT
  STZ NACT
  LDX HITSTG                   ; that stage is lost
  LDA BIT_T,X
  EOR #$FF
  PHA
  AND AVAIL
  STA AVAIL
  PLA
  AND ACTIVE
  STA ACTIVE
  BNE .ll_sv
  LDA AVAIL                    ; nothing flying: the next stage takes off
  JSR LOW_BIT
  STA ACTIVE
.ll_sv:
  LDX CURP
  JSR SAVE_PLAYER
  LDA #30
  JSR WAIT_STARS
  LDX CURP
  LDA ALIVE,X
  BNE .ll_alive
  LDA NPL                      ; this player is out
  CMP #$02
  BNE .ll_over
  JSR VDP_INT_OFF
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
  JSR VDP_INT_ON
  LDA #150
  JSR WAIT_STARS
.ll_alive:
  LDA NPL
  CMP #$02
  BNE .ll_same
  LDA CURP
  EOR #$01
  TAX
  LDA ALIVE,X
  BEQ .ll_same
  STX CURP                     ; the other player
  JMP TURN_START
.ll_same:
  LDX CURP
  LDA ALIVE,X
  BEQ .ll_over
  JMP TURN_START
.ll_over:
  ; fall into GAME_OVER


; ===============================================================
;  GAME OVER: the hi score, back to the title
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  LDX #$00
  JSR HI_CHECK
  LDX #$01
  JSR HI_CHECK
  JSR VDP_INT_OFF
  JSR DRAW_TOP
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #240
  JSR WAIT_STARS
  JMP TITLE

; X = player: his score becomes the hi score if it is higher
HI_CHECK:
  LDA SCH,X
  CMP HISC+2
  BCC .hc_r
  BNE .hc_new
  LDA SCM,X
  CMP HISC+1
  BCC .hc_r
  BNE .hc_new
  LDA SCL,X
  CMP HISC
  BCC .hc_r
.hc_new:
  LDA SCL,X
  STA HISC
  LDA SCM,X
  STA HISC+1
  LDA SCH,X
  STA HISC+2
.hc_r:
  RTS

; A = aliens to send again: one per alien, one per two small eyes
COUNT_BACK:
  STZ T0
  STZ T1
  LDX #(NE-1)
.cb_l:
  LDA E_ST,X
  BEQ .cb_n
  LDA E_K,X
  CMP #K_SMALL
  BNE .cb_o
  INC T1
  BRA .cb_n
.cb_o:
  INC T0
.cb_n:
  DEX
  BPL .cb_l
  LDA T1
  INC A
  LSR A
  CLC
  ADC T0
  RTS


; ===============================================================
;  DOCKING: the rocket comes down on the next stage
; ===============================================================
; after waves 4 and 8: the first stage waiting that goes below the rocket
TRY_DOCK:
  LDA AVAIL
  EOR ACTIVE
  STA T0                       ; stages waiting
  LDX MAXA
.td_l:
  INX
  CPX #3
  BCS .td_r
  LDA T0
  AND BIT_T,X
  BEQ .td_l
  STX DOCKS
  JMP DOCKING
.td_r:
  RTS

DOCKING:
  JSR VDP_INT_OFF
  JSR CLEAR_OBJECTS
  JSR DRAW_FIELD
  LDA #<TXT_DOCK
  STA TP
  LDA #>TXT_DOCK
  STA TP+1
  JSR PRINT
  LDA #30
  STA DSEC
  LDA #60
  STA DFR
  JSR DRAW_TIME
  JSR NEXT_RND                 ; the rocket comes from up there
  AND #$7F
  CLC
  ADC #40
  STA PLX
  LDA NSTG                     ; its highest stage at Y = 36
  DEC A
  STA T0
  LDA #36
.dk_y:
  DEC T0
  BMI .dk_y0
  CLC
  ADC #STG_H
  BRA .dk_y
.dk_y0:
  STA STKY
  STZ DYL
  LDA #$40
  STA DVYL
  STZ DVYH
  JSR SET_TOPY
  LDA #$01
  STA DOCKV
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #W_ALARM
  LDX #2
  JSR SFX_WHISTLE
.dk_loop:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  JSR SCROLL_STARS
  JSR DOCK_MOVE
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA STKY                     ; down on the stage waiting?
  CMP #(BASE_Y-STG_H)
  BCC .dk_loop
  LDA PLX
  SEC
  SBC #DOCK_X
  JSR ABS_A
  CMP #4
  BCS .dk_fail
  LDA DVYH
  BNE .dk_fail
  LDA DVYL
  CMP #$C0
  BCS .dk_fail
  ; ---- docked: bonus = seconds left x 100
  LDA #DOCK_X
  STA PLX
  LDA #BASE_Y
  STA STKY
  STZ DOCKV
  STZ THR
  LDX DOCKS
  LDA BIT_T,X
  ORA ACTIVE
  STA ACTIVE
  JSR SET_STACK
  JSR VDP_INT_OFF
  LDA DSEC
  JSR BIN2BCD
  STA PTS_M
  STZ PTS_L
  JSR ADD_SCORE
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA PTS_M
  JSR PUT_2
  LDA #$30
  STA VDATA
  STA VDATA
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #W_DOCK
  LDX #2
  JSR SFX_WHISTLE
  BRA .dk_end
.dk_fail:
  ; ---- crashed: the stage waiting is destroyed
  STZ DOCKV
  STZ THR
  LDX DOCKS
  LDA BIT_T,X
  EOR #$FF
  AND AVAIL
  STA AVAIL
  LDA #DOCK_X
  STA TX
  LDA #BASE_Y
  STA TY
  JSR NEW_EXPL
  LDA #48
  STA FLASH
  LDA #S_SHIP
  LDX #2
  JSR SFX_BOOM
  JSR VDP_INT_OFF
  LDA #<TXT_FAIL
  STA TP
  LDA #>TXT_FAIL
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
.dk_end:
  LDA #150
  JSR WAIT_ANIM
  JSR BACKDROP_BLACK
  LDA #BASE_Y
  STA STKY
  JMP SET_STACK

; one frame of the docking: LEFT / RIGHT, retro rockets, gravity, the time
DOCK_MOVE:
  LDA JOYC
  AND #$04                     ; left
  BEQ .dm_nl
  LDA PLX
  CMP #(X_MIN+8)
  BCC .dm_nl
  DEC PLX
.dm_nl:
  LDA JOYC
  AND #$08                     ; right
  BEQ .dm_nr
  LDA PLX
  CMP #(X_MAX-8)
  BCS .dm_nr
  INC PLX
.dm_nr:
  STZ THR
  LDA DSEC                     ; no more time: no more rockets
  BEQ .dm_grav
  LDA JOYC
  AND #BTN_MASK
  BEQ .dm_grav
  LDA #$01
  STA THR
  SEC                          ; retro rockets: up
  LDA DVYL
  SBC #12
  STA DVYL
  LDA DVYH
  SBC #$00
  STA DVYH
  LDA FRAME_CNT
  AND #$07
  BNE .dm_lim
  LDA #W_THRUST
  LDX #0
  JSR SFX_WHISTLE
  BRA .dm_lim
.dm_grav:
  CLC                          ; gravity: down
  LDA DVYL
  ADC #5
  STA DVYL
  LDA DVYH
  ADC #$00
  STA DVYH
.dm_lim:
  LDA DVYH                     ; speed from -0.5 to +2 px per frame
  BPL .dm_pos
  CMP #$FF
  BNE .dm_up
  LDA DVYL
  CMP #$80
  BCS .dm_add
.dm_up:
  LDA #$80
  STA DVYL
  LDA #$FF
  STA DVYH
  BRA .dm_add
.dm_pos:
  CMP #$02
  BCC .dm_add
  LDA #$FF
  STA DVYL
  LDA #$01
  STA DVYH
.dm_add:
  CLC
  LDA DYL
  ADC DVYL
  STA DYL
  LDA STKY
  ADC DVYH
  STA STKY
  JSR SET_TOPY
  LDA TOPY                     ; not out of the top of the screen
  CMP #28
  BCS .dm_time
  LDA STKY
  CLC
  ADC #(28)
  SEC
  SBC TOPY
  STA STKY
  STZ DVYL
  STZ DVYH
  JSR SET_TOPY
.dm_time:
  DEC DFR
  BNE .dm_r
  LDA #60
  STA DFR
  LDA DSEC
  BEQ .dm_r
  DEC DSEC
  JMP DRAW_TIME
.dm_r:
  RTS


; ===============================================================
;  THE ROCKET
; ===============================================================
UPDATE_SHIP:
  LDA PLST
  BEQ .us_play
  CMP #$01
  BNE .us_r
  DEC PLT
  BNE .us_r
  LDA #$03
  STA PLST
.us_r:
  RTS
.us_play:
  LDA JOYC
  AND #$04                     ; left
  BEQ .us_nl
  LDA PLX
  SEC
  SBC #2
  CMP #X_MIN
  BCS .us_sl
  LDA #X_MIN
.us_sl:
  STA PLX
.us_nl:
  LDA JOYC
  AND #$08                     ; right
  BEQ .us_nr
  LDA PLX
  CLC
  ADC #2
  CMP #X_MAX
  BCC .us_sr
  LDA #X_MAX
.us_sr:
  STA PLX
.us_nr:
  LDA FIRECD
  BEQ .us_f
  DEC FIRECD
  RTS
.us_f:
  LDA JOYC                     ; holding the button fires a new volley when the last is gone
  AND #BTN_MASK
  BNE FIRE
  RTS

; a volley: one shot from stage I, two from stage II and from stage III
FIRE:
  LDX #(NS-1)
.fi_c:
  LDA S_ON,X
  BNE .fi_r
  DEX
  BPL .fi_c
  LDY #$00                     ; stage of the list (from the top)
  LDA TOPY
  STA T0                       ; Y of that stage
.fi_l:
  LDA STG_LIST,Y
  TAX
  LDA SHOT_FIRST,X             ; slots of the stage
  STA T1
  LDA SHOT_LAST,X
  STA T2
  LDX T1
.fi_s:
  LDA #$01
  STA S_ON,X
  LDA PLX
  CLC
  ADC SHOT_DX,X
  STA S_X,X
  LDA T0
  SEC
  SBC #7
  STA S_Y,X
  INX
  CPX T2
  BCC .fi_s
  BEQ .fi_s
  LDA T0
  CLC
  ADC #STG_H
  STA T0
  INY
  CPY NSTG
  BNE .fi_l
  LDA #4
  STA FIRECD
  LDA #W_SHOT
  LDX #0
  JMP SFX_WHISTLE
.fi_r:
  RTS

; X = alien that hit stage HITSTG: that stage explodes (keeps X and Y)
PLAYER_DIE:
  PHX
  PHY
  LDA #$01
  STA PLST
  LDA #120
  STA PLT
  LDA #48
  STA FLASH
  LDA #S_SHIP
  LDX #2
  JSR SFX_BOOM
  LDX #(NS-1)
.pd_s:
  STZ S_ON,X
  DEX
  BPL .pd_s
  PLY
  PLX
  RTS

; the red flash of the background (backdrop colour)
DO_FLASH:
  LDA FLASH
  BEQ .fl_r
  DEC FLASH
  LDA FLASH
  AND #$04
  BEQ BACKDROP_BLACK
  LDA #$08
  JMP BACKDROP
.fl_r:
  RTS
BACKDROP_BLACK:
  LDA #$01
BACKDROP:                      ; A = colour of the background (register 7)
  STA VREG
  LDA #(VDP_REGISTER_BITS | 7)
  STA VREG
  RTS


; ===============================================================
;  SHOTS OF THE ROCKET
; ===============================================================
UPDATE_SHOTS:
  LDX #(NS-1)
.sh_l:
  STX SI
  LDA S_ON,X
  BEQ .sh_n
  LDA S_Y,X
  SEC
  SBC #7
  STA S_Y,X
  CMP #12
  BCC .sh_off
  CMP #200
  BCS .sh_off
  JSR SHOT_HITS
  BRA .sh_n
.sh_off:
  STZ S_ON,X
.sh_n:
  LDX SI
  DEX
  BPL .sh_l
  RTS

; shot SI against the aliens
SHOT_HITS:
  LDX #(NE-1)
.sx_a:
  LDA E_ST,X
  CMP #2
  BNE .sx_an
  LDA E_MODE,X                 ; not while a Four-D takes shape
  CMP #M_APPEAR
  BEQ .sx_an
  LDY E_K,X
  LDA HWK,Y
  STA HW
  LDY SI
  LDA E_X,X
  SEC
  SBC S_X,Y
  JSR ABS_A
  CMP HW
  BCS .sx_an
  LDA E_Y,X
  SEC
  SBC S_Y,Y
  JSR ABS_A
  CMP #9
  BCS .sx_an
  LDA #$00
  STA S_ON,Y
  JMP HIT_ALIEN
.sx_an:
  DEX
  BPL .sx_a
  RTS

; A = |A| (signed)
ABS_A:
  BPL .ab_r
  EOR #$FF
  INC A
.ab_r:
  RTS


; ===============================================================
;  SPAWN: the aliens of the wave come one or a group at a time
; ===============================================================
SPAWN:
  LDA PLST
  BNE .sp_r
  LDA SPAWNT
  BEQ .sp_t
  DEC SPAWNT
.sp_r:
  RTS
.sp_t:
  LDA LEFT
  BEQ .sp_r
  LDY KIND
  LDA NACT
  CMP SIM_T,Y                  ; still too many on the screen
  BCS .sp_r
  LDA GROUP_T,Y                ; aliens in the group
  CMP LEFT
  BCC .sp_k
  LDA LEFT
.sp_k:
  STA T5                       ; units taken from LEFT
  STA T4                       ; aliens to place
  CPY #K_EYE
  BNE .sp_free
  LDA CYC                      ; from the second cycle the eyes come already split
  BEQ .sp_free
  LDA #2
  STA T4
.sp_free:
  LDX #(NE-1)                  ; enough free places?
  STZ T0
.sp_fc:
  LDA E_ST,X
  BNE .sp_fn
  INC T0
.sp_fn:
  DEX
  BPL .sp_fc
  LDA T0
  CMP T4
  BCC .sp_r
  LDA LEFT
  SEC
  SBC T5
  STA LEFT
  LDA NACT
  CLC
  ADC T4
  STA NACT
  LDA GAP_T,Y
  SEC
  SBC DIFF
  SBC DIFF
  SBC DIFF
  SBC DIFF
  STA SPAWNT
  INC GRP
  JSR NEXT_RND                 ; what the group shares: X, side
  AND #$7F
  CLC
  ADC #64
  STA TX
  STZ CNT                      ; alien of the group
  LDX #(NE-1)
.sp_l:
  LDA E_ST,X
  BNE .sp_n
  JSR NEW_ALIEN
  INC CNT
  LDA CNT
  CMP T4
  BEQ .sp_done
.sp_n:
  DEX
  BPL .sp_l
.sp_done:
  RTS

; X = free place, CNT = alien of the group: a new alien of KIND (keeps X)
NEW_ALIEN:
  LDA #$02
  STA E_ST,X
  LDA #$80
  STA E_XL,X
  STA E_YL,X
  STZ E_FLSH,X
  STZ E_TURN,X
  LDA #$01
  STA E_HP,X
  LDA #FIELD_TOP
  STA E_Y,X
  LDA #128
  STA E_ANG,X
  LDA KIND
  STA E_K,X
  CMP #K_EYE
  BNE .na_ne
  JMP .na_eye
.na_ne:
  CMP #K_FLY
  BNE .na_nf
  JMP .na_fly
.na_nf:
  CMP #K_FOURD
  BNE .na_nd
  JMP FOURD_PLACE
.na_nd:
  CMP #K_ROCK
  BNE .na_atom
  JMP .na_rock
.na_atom:
  ; ---- atomic pile: 4 atoms around the same centre
  LDA TX
  STA E_TGX,X
  LDA #40
  STA E_TGY,X
  LDA CNT
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA E_PH,X
  LDA GRP
  AND #$01
  BEQ .na_ad
  LDA #$FF
  BRA .na_as
.na_ad:
  LDA #$01
.na_as:
  STA E_AUX,X
  LDA CNT                      ; they leave the pile one after the other
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ADC #70
  STA E_T,X
  LDA #M_ORBIT
  STA E_MODE,X
  LDA #$02
  STA E_SPD,X
  JMP ORBIT_POS
.na_eye:
  LDA CYC
  BEQ .na_big
  LDA #K_SMALL                 ; already split: a pair
  STA E_K,X
  LDA #$02
  STA E_SPD,X
  LDA CNT
  BEQ .na_e1
  LDA #160
  BRA .na_e2
.na_e1:
  LDA #96
.na_e2:
  STA E_ANG,X
  BRA .na_epos
.na_big:
  LDA #$01
  STA E_SPD,X
.na_epos:
  JSR NEXT_RND
  AND #$7F
  CLC
  ADC #64
  STA E_X,X
  JSR NEXT_RND
  AND #$03
  SEC
  SBC #2
  STA E_TURN,X
  LDA #30
  STA E_T,X
  LDA #M_ENTER
  STA E_MODE,X
  RTS
.na_fly:
  LDA #$01                     ; waits its turn in the line
  STA E_ST,X
  LDA CNT
  ASL A
  ASL A
  ASL A
  ADC CNT
  ADC CNT
  INC A
  STA E_T,X
  LDA #$01
  STA E_SPD,X
  LDA GRP
  AND #$01
  BEQ .na_fl
  LDA #232                     ; from the top right, down and left
  STA E_X,X
  LDA #164
  STA E_ANG,X
  LDA #$FF
  STA E_TURN,X
  BRA .na_fm
.na_fl:
  LDA #24                      ; from the top left, down and right
  STA E_X,X
  LDA #92
  STA E_ANG,X
  LDA #$01
  STA E_TURN,X
.na_fm:
  LDA #M_ENTER
  STA E_MODE,X
  RTS
.na_rock:
  LDA #$02
  STA E_HP,X
  JSR NEXT_RND
  AND #$7F
  STA T0
  JSR NEXT_RND
  AND #$3F
  CLC
  ADC T0
  ADC #32
  STA E_X,X
  JSR NEXT_RND
  AND #$1F
  CLC
  ADC #112
  STA E_ANG,X
  JSR NEXT_RND
  AND #$01
  LDY DIFF
  CPY #2
  ADC #$00
  STA E_SPD,X
  LDA #M_EXIT
  STA E_MODE,X
  RTS

; X = Four-D: it takes shape somewhere in the sky (keeps X)
FOURD_PLACE:
  JSR NEXT_RND
  AND #$7F
  STA T0
  JSR NEXT_RND
  AND #$3F
  CLC
  ADC T0
  ADC #36
  STA E_X,X
  JSR NEXT_RND
  AND #$3F
  CLC
  ADC #32
  STA E_Y,X
  LDA #40
  STA E_T,X
  LDA #$03
  STA E_SPD,X
  LDA #M_APPEAR
  STA E_MODE,X
  RTS


; ===============================================================
;  ALIENS
; ===============================================================
UPDATE_ALIENS:
  LDX #(NE-1)
.ua_l:
  LDA E_ST,X
  BEQ .ua_n
  LDY E_FLSH,X
  BEQ .ua_s
  DEC E_FLSH,X
.ua_s:
  CMP #$01
  BNE .ua_fly
  DEC E_T,X                    ; waiting to enter
  BNE .ua_n
  LDA #$02
  STA E_ST,X
  LDA #50
  STA E_T,X
  BRA .ua_n
.ua_fly:
  LDA E_MODE,X
  ASL A
  TAY
  LDA MODE_JMP,Y
  STA PTR2
  LDA MODE_JMP+1,Y
  STA PTR2+1
  JSR .ua_go
  LDA E_ST,X                   ; still there?
  BEQ .ua_n
  JSR ALIEN_SHIP
.ua_n:
  DEX
  BPL .ua_l
  RTS
.ua_go:
  JMP (PTR2)

MODE_JMP:
  .word MO_ENTER, MO_WANDER, MO_DIVE, MO_SWAY, MO_EXIT, MO_ORBIT, MO_APPEAR

; along the way in: then the eyes wander and the super flies sway
MO_ENTER:
  LDA E_ANG,X
  CLC
  ADC E_TURN,X
  STA E_ANG,X
  JSR MOVE_B
  JSR BO_X
  JSR BO_TOP
  DEC E_T,X
  BNE .me_r
  LDA E_K,X
  CMP #K_FLY
  BNE START_WANDER
  JMP START_SWAY
.me_r:
  RTS

START_WANDER:
  LDA #M_WANDER
  STA E_MODE,X
  JSR NEXT_RND
  AND #$1F
  CLC
  ADC #16
  STA E_T,X
  JSR NEXT_RND
  AND #$07
  TAY
  LDA WTURN,Y
  STA E_TURN,X
  RTS

; a curve one way and the other; now and then a dive on the rocket
MO_WANDER:
  LDA E_ANG,X
  CLC
  ADC E_TURN,X
  STA E_ANG,X
  JSR MOVE_B
  JSR BO_X
  JSR BO_TOP
  JSR WRAP
  DEC E_T,X
  BNE .mw_r
  JSR NEXT_RND
  LDY DIFF
  CMP DIVEP,Y
  BCS START_WANDER
  LDA E_Y,X
  CMP #120
  BCS START_WANDER
  JMP START_DIVE
.mw_r:
  RTS

START_SWAY:
  LDA #M_SWAY
  STA E_MODE,X
  JSR NEXT_RND
  AND #$7F
  CLC
  ADC #50
  STA E_T,X
  STZ E_SPD,X
  RTS

; small circles in the air, then a dive
MO_SWAY:
  LDA E_ANG,X
  CLC
  ADC #8
  STA E_ANG,X
  JSR MOVE_B
  JSR BO_X
  JSR BO_TOP
  DEC E_T,X
  BNE .ms_r
  JMP START_DIVE
.ms_r:
  RTS

START_DIVE:
  LDA #M_DIVE
  STA E_MODE,X
  LDY E_K,X
  LDA DSPD,Y
  LDY DIFF
  CPY #2
  BCC .sd_s
  CMP #3
  BCS .sd_s
  INC A
.sd_s:
  STA E_SPD,X
  PHX
  LDA #W_DIVE
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS

; towards the rocket; close to it, straight on
MO_DIVE:
  LDA PLX
  STA TX
  LDA STKY
  STA TY
  JSR AIM
  PHA
  LDY DIFF
  LDA DTRN,Y
  JSR SET_TRN
  PLA
  JSR STEER
  JSR MOVE_B
  JSR BO_X
  LDA E_Y,X
  CMP #240
  BCS .md_r
  LDA TOPY
  SEC
  SBC #24
  CMP E_Y,X
  BCS .md_r
  LDA #M_EXIT
  STA E_MODE,X
.md_r:
  RTS

; straight on and out of the bottom: back from the top (the meteors are gone)
MO_EXIT:
  JSR MOVE_B
  JSR BO_X
  LDA E_Y,X
  CMP #188
  BCC .mx_r
  CMP #240
  BCS .mx_r
  LDA E_K,X
  CMP #K_ROCK
  BNE .mx_back
  STZ E_ST,X                   ; the meteor is gone
  DEC NACT
.mx_r:
  RTS
.mx_back:
  LDA #FIELD_TOP
  STA E_Y,X
  LDA #128
  STA E_ANG,X
  LDA E_K,X
  CMP #K_FOURD
  BNE .mx_nf
  JMP FOURD_PLACE
.mx_nf:
  CMP #K_ATOM
  BNE .mx_na
  JMP START_DIVE
.mx_na:
  CMP #K_FLY
  BNE .mx_eye
  STZ E_TURN,X
  LDA #40
  STA E_T,X
  LDA #$01
  STA E_SPD,X
  LDA #M_ENTER
  STA E_MODE,X
  RTS
.mx_eye:
  JMP START_WANDER

; the atoms turn around the centre of the pile, that drifts down and sideways
MO_ORBIT:
  LDA E_PH,X
  CLC
  ADC #3
  STA E_PH,X
  LDA FRAME_CNT
  AND #$03
  BNE .mo_x
  LDA E_TGY,X
  CMP #84
  BCS .mo_x
  INC A
  STA E_TGY,X
.mo_x:
  LDA FRAME_CNT
  LSR A
  BCC .mo_p
  LDA E_TGX,X
  CLC
  ADC E_AUX,X
  STA E_TGX,X
  CMP #40
  BCC .mo_flip
  CMP #217
  BCC .mo_p
.mo_flip:
  LDA E_AUX,X
  EOR #$FF
  INC A
  STA E_AUX,X
.mo_p:
  JSR ORBIT_POS
  DEC E_T,X
  BNE .mo_r
  LDA PLX                      ; it leaves the pile and dives
  STA TX
  LDA STKY
  STA TY
  JSR AIM
  STA E_ANG,X
  LDA #$80
  STA E_XL,X
  STA E_YL,X
  JMP START_DIVE
.mo_r:
  RTS

; X = atom: its place on the circle
ORBIT_POS:
  LDA E_PH,X
  LSR A
  LSR A
  TAY
  LDA E_TGX,X
  CLC
  ADC ORB_DX,Y
  STA E_X,X
  LDA E_TGY,X
  CLC
  ADC ORB_DY,Y
  STA E_Y,X
  RTS

; a Four-D takes shape, then it dives on the rocket
MO_APPEAR:
  DEC E_T,X
  BNE .ma_r
  LDA PLX
  STA TX
  LDA STKY
  STA TY
  JSR AIM
  STA E_ANG,X
  JMP START_DIVE
.ma_r:
  RTS

; X = alien: out of the bottom -> back at the top
WRAP:
  LDA E_Y,X
  CMP #188
  BCC .wr_r
  CMP #240
  BCS .wr_r
  LDA #FIELD_TOP
  STA E_Y,X
.wr_r:
  RTS

; X = alien: position += speed along its direction
MOVE_B:
  LDA E_ANG,X
  LSR A
  LSR A
  STA T0
  LDA E_SPD,X
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  TAY
  CLC
  LDA E_XL,X
  ADC VXL,Y
  STA E_XL,X
  LDA E_X,X
  ADC VXH,Y
  STA E_X,X
  CLC
  LDA E_YL,X
  ADC VYL,Y
  STA E_YL,X
  LDA E_Y,X
  ADC VYH,Y
  STA E_Y,X
  RTS

; X = alien: it bounces off the sides
BO_X:
  LDA E_X,X
  CMP #8
  BCC .bo_l
  CMP #248
  BCC .bo_r
  LDA E_ANG,X                  ; past the right edge, or wrapped from the left one
  BMI .bo_wl
.bo_wr:
  LDA #247
  BRA .bo_sx
.bo_l:
  LDA E_ANG,X                  ; past the left edge, or wrapped from the right one
  BPL .bo_wr
.bo_wl:
  LDA #8
.bo_sx:
  STA E_X,X
  LDA #$00                     ; mirror the direction
  SEC
  SBC E_ANG,X
  STA E_ANG,X
.bo_r:
  RTS

; X = alien: it bounces off the top
BO_TOP:
  LDA E_Y,X
  CMP #FIELD_TOP
  BCC .bt_f
  CMP #240
  BCC .bt_r
.bt_f:
  LDA #FIELD_TOP
  STA E_Y,X
  LDA #128
  SEC
  SBC E_ANG,X
  STA E_ANG,X
.bt_r:
  RTS

; A = max turn per frame
SET_TRN:
  STA TRN
  EOR #$FF
  INC A
  STA TRNEG
  RTS

; X = alien, A = direction wanted: turn towards it, TRN at most
STEER:
  SEC
  SBC E_ANG,X
  BMI .st_neg
  CMP TRN
  BCC .st_add
  LDA TRN
  BRA .st_add
.st_neg:
  CMP TRNEG
  BCS .st_add
  LDA TRNEG
.st_add:
  CLC
  ADC E_ANG,X
  STA E_ANG,X
  RTS

; X = alien, TX / TY = target -> A = direction from the alien to the target
AIM:
  LDA E_X,X
  STA SX
  LDA E_Y,X
  STA SY
  ; fall into ANGLE_TO

; direction from SX, SY to TX, TY (0 up, clockwise, 0-255), keeps X
ANGLE_TO:
  STZ SGN
  LDA TX
  SEC
  SBC SX
  JSR HALF9
  STA AX
  ROL SGN
  LDA TY
  SEC
  SBC SY
  JSR HALF9
  STA AY
  ROL SGN
  ORA AX
  BNE .at_go
  LDA #128                     ; the same point: down
  RTS
.at_go:
  LDA AX
  CMP AY
  BCC .at_steep
  LDA AY                       ; closer to horizontal
  LDY AX
  JSR FRAC
  LSR A
  LSR A
  LSR A
  TAY
  LDA ATN,Y
  STA T4
  LDY SGN
  BRA .at_comb
.at_steep:
  LDA AX                       ; closer to vertical
  LDY AY
  JSR FRAC
  LSR A
  LSR A
  LSR A
  TAY
  LDA ATN,Y
  STA T4
  LDA SGN
  ORA #$04
  TAY
.at_comb:
  LDA AT_SUB,Y
  BNE .at_minus
  LDA AT_BASE,Y
  CLC
  ADC T4
  RTS
.at_minus:
  LDA AT_BASE,Y
  SEC
  SBC T4
  RTS

; A = low byte of a difference, carry = 1 if it is positive -> A = |difference| / 2,
; carry = 1 if it is negative
HALF9:
  BCS .h9_p
  EOR #$FF
  ADC #$01
  LSR A
  SEC
  RTS
.h9_p:
  LSR A
  CLC
  RTS

; A = numerator, Y = denominator (A <= Y < 128) -> A = A * 256 / Y (255 if equal)
FRAC:
  STA T6
  STY T7
  LDY #8
.fr_l:
  ASL T6
  LDA T6
  CMP T7
  BCC .fr_0
  SBC T7
  STA T6
.fr_0:
  ROL T5
  DEY
  BNE .fr_l
  LDA T5
  RTS

; X = alien: does it hit a stage of the rocket?
ALIEN_SHIP:
  LDA PLST
  BNE .as_r
  LDA E_MODE,X
  CMP #M_APPEAR
  BEQ .as_r
  LDA E_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #13
  BCS .as_r
  STA HW                       ; |dx|
  LDA E_Y,X
  CMP #240
  BCS .as_r
  CLC
  ADC #10
  SEC
  SBC TOPY                     ; Y - (TOPY - 10)
  BCC .as_r
  LDY #$00                     ; which stage: 16 pixels for the first, 12 for the others
  CMP #16
  BCC .as_st
  SBC #16
.as_lo:
  INY
  CPY NSTG
  BCS .as_bot
  CMP #STG_H
  BCC .as_st
  SBC #STG_H
  BRA .as_lo
.as_bot:
  CMP #10                      ; below the lowest stage
  BCS .as_r
  DEY
.as_st:
  LDA STG_LIST,Y
  STA HITSTG
  TAY
  LDA HW
  CMP HWS,Y
  BCS .as_r
  JSR KILL_ALIEN
  JMP PLAYER_DIE
.as_r:
  RTS

; X = alien hit by a shot: split, one hit less or shot down
HIT_ALIEN:
  LDA E_K,X
  CMP #K_EYE
  BEQ SPLIT_EYE
  CMP #K_ROCK
  BNE KILL_ALIEN
  DEC E_HP,X
  BEQ KILL_ALIEN
  LDA #6
  STA E_FLSH,X
  PHX
  LDA #W_SPLIT
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS

; X = alien shot down: points, explosion (keeps X)
KILL_ALIEN:
  LDY E_K,X
  LDA PTS_TL,Y
  STA PTS_L
  LDA PTS_TM,Y
  STA PTS_M
  JSR ADD_SCORE
  LDA E_X,X
  STA TX
  LDA E_Y,X
  STA TY
  JSR NEW_EXPL
  PHX
  LDA #S_SMALL
  LDY E_K,X
  CPY #K_ROCK
  BNE .ka_b
  LDA #S_ROCK
.ka_b:
  LDY E_X,X
  JSR BOOM_AT
  LDA #W_KILL
  LDX #1
  JSR SFX_WHISTLE
  PLX
  STZ E_ST,X
  DEC NACT
  RTS

; X = big Cold Eye hit: 50 points and two small eyes flying apart
SPLIT_EYE:
  LDA #$50
  STA PTS_L
  STZ PTS_M
  JSR ADD_SCORE
  LDA #K_SMALL
  STA E_K,X
  LDA #$02
  STA E_SPD,X
  LDA #6
  STA E_FLSH,X
  LDA E_ANG,X
  SEC
  SBC #40
  STA T0                       ; direction of the other one
  CLC
  ADC #80
  STA E_ANG,X
  JSR START_WANDER
  PHX
  LDA #W_SPLIT
  LDX #1
  JSR SFX_WHISTLE
  PLX
  LDY #(NE-1)                  ; a free place for the other eye
.se_f:
  LDA E_ST,Y
  BEQ .se_new
  DEY
  BPL .se_f
  RTS
.se_new:
  LDA #$02
  STA E_ST,Y
  LDA #K_SMALL
  STA E_K,Y
  LDA #$01
  STA E_HP,Y
  LDA #$02
  STA E_SPD,Y
  LDA #6
  STA E_FLSH,Y
  LDA E_X,X
  STA E_X,Y
  LDA E_Y,X
  STA E_Y,Y
  LDA E_XL,X
  STA E_XL,Y
  LDA E_YL,X
  STA E_YL,Y
  LDA T0
  STA E_ANG,Y
  LDA #M_WANDER
  STA E_MODE,Y
  LDA E_T,X
  STA E_T,Y
  LDA E_TURN,X
  EOR #$FF
  INC A
  STA E_TURN,Y
  INC NACT
  RTS


; ===============================================================
;  EXPLOSIONS
; ===============================================================
; TX, TY: a new explosion (keeps X)
NEW_EXPL:
  LDY #(NX-1)
.ne_l:
  LDA X_T,Y
  BEQ .ne_f
  DEY
  BPL .ne_l
  RTS
.ne_f:
  LDA #24
  STA X_T,Y
  LDA TX
  STA X_X,Y
  LDA TY
  STA X_Y,Y
  RTS

UPDATE_EXPL:
  LDX #(NX-1)
.ux_l:
  LDA X_T,X
  BEQ .ux_n
  DEC X_T,X
.ux_n:
  DEX
  BPL .ux_l
  RTS

CLEAR_OBJECTS:
  LDX #(NE-1)
.co_a:
  STZ E_ST,X
  DEX
  BPL .co_a
  LDX #(NS-1)
.co_s:
  STZ S_ON,X
  DEX
  BPL .co_s
  LDX #(NX-1)
.co_x:
  STZ X_T,X
  DEX
  BPL .co_x
  STZ NACT
  STZ FIRECD
  STZ JOYP
  RTS


; ===============================================================
;  STARS: every kind moves down one line (the slow ones every
;  other frame); the line is cleared and set in the 3 thirds
; ===============================================================
SCROLL_STARS:
  LDX #7
.ss_l:
  LDA STAR_SLOW,X
  BEQ .ss_go
  LDA FRAME_CNT
  LSR A
  BCC .ss_n
.ss_go:
  LDA ST_Y,X
  JSR STAR_ADDR
  LDA #$00
  JSR STAR_PUT
  LDA ST_Y,X
  INC A
  AND #63
  STA ST_Y,X
  JSR STAR_ADDR
  LDA STAR_BIT,X
  JSR STAR_PUT
.ss_n:
  DEX
  BPL .ss_l
  RTS

; X = kind, A = line 0-63 -> T0 / T1 = VRAM address in the third 0 ($400 + kind * 64 + line)
STAR_ADDR:
  STA T0
  TXA
  AND #$03
  LSR A
  ROR A
  ROR A
  ORA T0
  STA T0
  TXA
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | $04)
  STA T1
  RTS

; A = byte written at T0 / T1 in the 3 thirds
STAR_PUT:
  STA T2
  LDA T0
  STA VREG
  LDA T1
  STA VREG
  LDA T2
  STA VDATA
  LDA T0
  STA VREG
  LDA T1
  CLC
  ADC #$08
  STA VREG
  LDA T2
  STA VDATA
  LDA T0
  STA VREG
  LDA T1
  CLC
  ADC #$10
  STA VREG
  LDA T2
  STA VDATA
  RTS

; one frame with the stars moving (VDP interrupt on)
STAR_FRAME:
  JSR VDP_INT_OFF
  JSR SCROLL_STARS
  JMP VDP_INT_ON

; A = frames to wait with the stars moving
WAIT_STARS:
  STA CNT
.ws_l:
  JSR STAR_FRAME
  DEC CNT
  BNE .ws_l
  RTS

; A = frames to wait with the stars, the explosions and the flash moving
WAIT_ANIM:
  STA CNT
.wa_l:
  JSR VDP_INT_OFF
  JSR SCROLL_STARS
  JSR DO_FLASH
  JSR UPDATE_EXPL
  JSR BUILD_SAT
  JSR VDP_INT_ON
  DEC CNT
  BNE .wa_l
  RTS


; ===============================================================
;  PLAYERS: save / load the block WAVE-LEFT
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDA AVAIL
  STA ALIVE,X
  LDY PS_OFF,X
  LDX #$00
.sp_b:
  LDA WAVE,X
  STA PSAVE,Y
  INY
  INX
  CPX #7
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.lp_b:
  LDA PSAVE,Y
  STA WAVE,X
  INY
  INX
  CPX #7
  BNE .lp_b
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M (BCD) to the player playing; a lost stage comes back at 30000 (keeps X)
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
  ADC #$00
  STA SCH,X
  CLD
  LDA EXTRA
  BNE .as_d
  LDA SCH,X
  CMP #$03
  BCC .as_d
  LDA #$01
  STA EXTRA
  LDA AVAIL                    ; the highest stage lost
  EOR #$07
  STA T0
  LDY #$02
.as_h:
  LDA BIT_T,Y
  AND T0
  BNE .as_got
  DEY
  BPL .as_h
  BRA .as_d
.as_got:
  ORA AVAIL
  STA AVAIL
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_RESERVE
.as_d:
  LDX CURP
  JSR DRAW_SCORE
  PLY
  PLX
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

; the starfield on the whole name table (rows 0-1 and 23 empty)
DRAW_STARS:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #<BG_NT
  STA PTR
  LDA #>BG_NT
  STA PTR+1
  LDX #3                       ; 3 pages
.ds_p:
  LDY #$00
.ds_l:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .ds_l
  INC PTR+1
  DEX
  BNE .ds_p
  RTS

; the field and the HUD
DRAW_FIELD:
  JSR DRAW_STARS
  JSR DRAW_TOP
  LDA #<TXT_BOT
  STA TP
  LDA #>TXT_BOT
  STA TP+1
  JSR PRINT
  LDA WAVEN
  JSR BIN2BCD
  LDX #23
  LDY #27
  JSR PUT_BCD2
  ; fall into DRAW_RESERVE

; the stages waiting to dock: row 23, columns 1-3 (keeps X)
DRAW_RESERVE:
  PHX
  LDX #23
  LDY #1
  JSR NT_XY
  LDA AVAIL
  EOR ACTIVE
  STA T0
  LDX #$00
.dr_l:
  LDA T0
  AND BIT_T,X
  BEQ .dr_w
  TXA
  CLC
  ADC #HUD_T
.dr_w:
  STA VDATA
  INX
  CPX #3
  BNE .dr_l
  PLX
  RTS

; the seconds left of the docking
DRAW_TIME:
  LDA DSEC
  JSR BIN2BCD
  LDX #7
  LDY #16
  JMP PUT_BCD2

; the stars back on X = first row, A = number of rows
RESTORE_ROWS:
  STA T1
  STX T0
  LDA #<BG_NT                  ; PTR = BG_NT + row * 32
  STA PTR
  LDA #>BG_NT
  STA PTR+1
  TXA
  LSR A
  LSR A
  LSR A
  CLC
  ADC PTR+1
  STA PTR+1
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC PTR
  STA PTR
  BCC .rr_p
  INC PTR+1
.rr_p:
  LDY #0
  JSR NT_XY
  LDA T1                       ; T1 x 32 bytes
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #$00
.rr_l:
  LDA (PTR),Y
  STA VDATA
  INY
  DEX
  BNE .rr_l
  RTS

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

; rows 0-1: 1UP, HIGH SCORE, 2UP and the three scores
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
  LDX #$01
  ; fall into DRAW_SCORE

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

; the label of the player playing blinks
BLINK_UP:
  LDA FRAME_CNT
  AND #$1F
  BEQ .bu_on
  CMP #$10
  BEQ .bu_off
  RTS
.bu_on:
  LDX CURP
  LDY UP_COL,X
  LDX #0
  JSR NT_XY
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
  LDA #$55                     ; U
  STA VDATA
  LDA #$50                     ; P
  STA VDATA
  RTS
.bu_off:
  LDX CURP
  LDY UP_COL,X
  LDX #0
  JSR NT_XY
  LDA #$20
  STA VDATA
  STA VDATA
  STA VDATA
  RTS


; ===============================================================
;  SPRITES: rocket, stage waiting, shots, aliens, explosions;
;  the aliens are listed backwards on odd frames, so with more
;  than 4 sprites on a line they flicker instead of disappearing
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA PLX                      ; the stages of the rocket, from the top down
  STA OX
  LDA TOPY
  STA OY
  LDX #$00
.bs_st:
  CPX NSTG
  BCS .bs_dock
  LDY STG_LIST,X
  LDA PLST
  BEQ .bs_stg
  CPY HITSTG
  BNE .bs_stg
  LDA PLT                      ; this stage explodes
  LSR A
  LSR A
  AND #$03
  TAY
  LDA EXPL_N,Y
  STA ON
  LDA FRAME_CNT
  AND #$03
  TAY
  LDA FLAME_COL,Y
  STA OC
  BRA .bs_add
.bs_stg:
  LDA STG_N,Y
  STA ON
  LDA STG_COL,Y
  STA OC
.bs_add:
  PHX
  JSR ADD_SPR
  PLX
  LDA OY
  CLC
  ADC #STG_H
  STA OY
  INX
  BRA .bs_st
.bs_dock:
  LDA DOCKV                    ; docking: the stage waiting and the retro rockets
  BEQ .bs_shots
  LDA #DOCK_X
  STA OX
  LDA #BASE_Y
  STA OY
  LDY DOCKS
  LDA STG_N,Y
  STA ON
  LDA STG_COL,Y
  STA OC
  JSR ADD_SPR
  LDA THR
  BEQ .bs_shots
  LDA PLX
  STA OX
  LDA STKY
  CLC
  ADC #12
  STA OY
  LDA #92
  STA ON
  LDA FRAME_CNT
  AND #$03
  TAY
  LDA FLAME_COL,Y
  STA OC
  JSR ADD_SPR
.bs_shots:
  LDA #$0B                     ; shots: a pair of the same stage is one sprite
  STA OC
  LDA S_ON
  BEQ .bs_p2
  LDA S_X
  STA OX
  LDA S_Y
  STA OY
  LDA #12
  STA ON
  JSR ADD_SPR
.bs_p2:
  LDX #1
  LDA #16
  JSR PAIR_SPR
  LDX #3
  LDA #20
  JSR PAIR_SPR
  LDX #(NE-1)                  ; aliens
.bs_el:
  TXA
  TAY
  LDA FRAME_CNT
  LSR A
  BCC .bs_eo
  TXA
  EOR #$FF
  CLC
  ADC #NE
  TAY                          ; odd frames: NE-1-X
.bs_eo:
  LDA E_ST,Y
  CMP #$02
  BNE .bs_en
  JSR ALIEN_SPR
  PHX
  JSR ADD_SPR
  PLX
.bs_en:
  DEX
  BPL .bs_el
  LDX #(NX-1)                  ; explosions
.bs_xl:
  LDA X_T,X
  BEQ .bs_xn
  LDA X_X,X
  STA OX
  LDA X_Y,X
  STA OY
  LDA #24
  SEC
  SBC X_T,X
  LSR A
  LSR A
  LSR A
  TAY
  LDA EXPL_N,Y
  STA ON
  LDA EXPL_C,Y
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.bs_xn:
  DEX
  BPL .bs_xl
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; X = first shot of a pair, A = pattern of the pair: one sprite for both, or the one left
PAIR_SPR:
  STA ON
  LDA S_ON,X
  AND S_ON+1,X
  BEQ .ps_one
  LDA S_X,X                    ; both: in the middle
  CLC
  ADC S_X+1,X
  ROR A
  STA OX
  LDA S_Y,X
  STA OY
  JMP ADD_SPR
.ps_one:
  LDA #12
  STA ON
  LDA S_ON,X
  BNE .ps_put
  INX
  LDA S_ON,X
  BEQ .ps_r
.ps_put:
  LDA S_X,X
  STA OX
  LDA S_Y,X
  STA OY
  JMP ADD_SPR
.ps_r:
  RTS

; Y = alien (flying): OX, OY, ON, OC
ALIEN_SPR:
  LDA E_X,Y
  STA OX
  LDA E_Y,Y
  STA OY
  LDA E_MODE,Y
  CMP #M_APPEAR
  BNE .ap_fly
  LDA #13                      ; a Four-D takes shape: four pieces closing in
  STA OC
  LDA E_T,Y
  CMP #27
  BCC .ap_near
  LDA #56
  STA ON
  RTS
.ap_near:
  CMP #14
  BCC .ap_whole
  LDA #60
  STA ON
  RTS
.ap_whole:
  LDA #48
  STA ON
  RTS
.ap_fly:
  TYA                          ; two frames, every alien at its own pace
  ASL A
  ASL A
  ADC FRAME_CNT
  AND #$08
  LSR A
  STA ON
  LDA E_K,Y
  PHY
  TAY
  LDA ALIEN_N,Y
  CLC
  ADC ON
  STA ON
  LDA ALIEN_C,Y
  PLY
  STA OC
  LDA E_FLSH,Y                 ; hit: white
  BEQ .ap_r
  LDA #$0F
  STA OC
.ap_r:
  RTS

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
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX SATB                ; the sprites in use + Y=$D0 = end of the list
  BNE .copy_sat
  JSR SND_TICK            ; music or sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI


; ===============================================================
;  SOUND: the start tune (4 tracks, from tank) and the effects
;  per chip in game: A = tone effects, B = noise and C = low tone
;  of the explosions; left chip = the rocket, right = the aliens
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
UP_COL:     .byte 2,26                         ; 1UP / 2UP: column on row 0
PS_OFF:     .byte 0,8                          ; block of the player in PSAVE
BIT_T:      .byte 1,2,4                        ; stage -> bit
; by stage (0 = I, 1 = II, 2 = III)
STG_N:      .byte 0,4,8                        ; sprite pattern
STG_COL:    .byte $0F,$08,$05                  ; colour
HWS:        .byte 8,11,12                      ; half width for the hits (+ the alien)
SHOT_FIRST: .byte 0,1,3                        ; its shots
SHOT_LAST:  .byte 0,2,4
SHOT_DX:    .byte 0,$FB,5,$F9,7                    ; X of every shot from the centre
; the waves of a cycle: kind of alien, how many
WAVE_K:     .byte K_EYE,K_EYE,K_FLY,K_FLY,K_FOURD,K_FOURD,K_ROCK,K_ROCK,K_ATOM,K_ATOM
WAVE_N:     .byte 4,4,8,8,8,8,12,12,8,8
; by kind (eye, small eye, super fly, Four-D, meteor, atom)
SIM_T:      .byte 4,4,5,3,5,5                  ; a new group when fewer are on the screen
GROUP_T:    .byte 1,1,4,1,1,4                  ; aliens in a group
GAP_T:      .byte 50,50,120,45,28,150          ; frames between two groups at least (- 4 x difficulty)
DSPD:       .byte 1,2,2,3,1,3                  ; speed of the dive
HWK:        .byte 8,6,8,8,9,8                  ; half width for the shots (+1)
ALIEN_N:    .byte 24,32,40,48,64,72            ; sprite pattern (frame 0)
ALIEN_C:    .byte $07,$05,$03,$0D,$0A,$09      ; colour
PTS_TL:     .byte $50,$50,$30,$60,$00,$00      ; points (BCD): 50, 50, 30, 60, 200, 100
PTS_TM:     .byte $00,$00,$00,$00,$02,$01
; by difficulty (cycle 1-4, then always 4)
DIVEP:      .byte 70,90,110,130                ; wandering eyes: chance of a dive (of 256)
DTRN:       .byte 2,3,3,4                      ; dive: turn per frame
WTURN:      .byte $FD,$FE,$FF,1,2,3,$FE,2      ; wandering: turn per frame
; ANGLE_TO: base and sign by SGN (closer to horizontal, then to vertical)
AT_BASE:    .byte 64,64,192,192,128,0,128,0
AT_SUB:     .byte 0,1,1,0,1,0,0,1
; sprites
EXPL_N:     .byte 80,84,88,84                  ; explosion frames
EXPL_C:     .byte $0B,$0A,$09,$0A
FLAME_COL:  .byte $0B,$0A,$09,$0F
; title: the aliens of the scoring table and the rocket (sprite Y, pattern, colour)
TITLE_SX:   .byte 68,68,68,68,68,40,40,40
TITLE_SY:   .byte 10*8-5,12*8-5,14*8-5,16*8-5,18*8-5,3*8-5,3*8+7,3*8+19
TITLE_SN:   .byte 24,40,48,64,72,0,4,8
TITLE_SC:   .byte $07,$03,$0D,$0A,$09,$0F,$08,$05

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_BOT:
  .byte 23,22,"WAVE",0
  .byte $FF
TXT_TITLE:
  .byte 8,8,"- SCORE TABLE -",0
  .byte 10,12,"COLD EYE     50",0
  .byte 12,12,"SUPER FLY    30",0
  .byte 14,12,"FOUR-D       60",0
  .byte 16,12,"METEOR      200",0
  .byte 18,12,"ATOMIC PILE 100",0
  .byte 20,3,"DOCKING BONUS: TIME X 100",0
  .byte 21,6,"EXTRA STAGE AT 30000",0
  .byte 22,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_PLAYER:
  .byte 11,12,"PLAYER ",0
  .byte $FF
TXT_WAVE:
  .byte 13,12,"WAVE ",0
  .byte $FF
TXT_DOCK:
  .byte 5,12,"DOCKING",0
  .byte 7,11,"TIME",0
  .byte $FF
TXT_BONUS:
  .byte 11,11,"BONUS ",0
  .byte $FF
TXT_FAIL:
  .byte 11,9,"DOCKING FAILED",0
  .byte $FF
TXT_OVER:
  .byte 15,11,"GAME OVER",0
  .byte $FF

; ---------------------------------------------------------------
; music (from tank): per track 0 melody / 1 harmony / 2 bass
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

; the start tune: a fanfare in C, 4 bars of 80 frames (a 16th = 5 frames)
;   G4 32  A4 34  B4 36  C5 37  D5 39  E5 41  F5 42  G5 44  A5 46  B5 48  C6 49  D6 51  E6 53
START_LEAD:
  .byte 32,5, 37,5, 41,5, 44,5, 49,15, 44,5, 41,10, 44,10, 49,20
  .byte 48,5, 46,5, 44,5, 42,5, 41,10, 39,10, 37,10, 39,5, 41,5, 39,20
  .byte 34,5, 39,5, 42,5, 46,5, 51,15, 46,5, 42,10, 46,10, 51,20
  .byte 48,5, 49,5, 51,5, 48,5, 49,15, 44,5, 53,20, 49,20
  .byte $FF
START_HARM:
  .byte 29,40, 32,40
  .byte 24,40, 27,40
  .byte 30,40, 34,40
  .byte 32,40, 29,40
  .byte $FF
START_BASS:
  .byte 13,20, 20,20, 13,20, 20,20
  .byte 8,20, 15,20, 8,20, 12,20
  .byte 6,20, 13,20, 15,20, 10,20
  .byte 8,20, 8,20, 13,40
  .byte $FF
START_DRUM:
  .byte 1,10, 3,10, 2,10, 3,10, 1,10, 3,10, 2,10, 3,10
  .byte 1,10, 3,10, 2,10, 3,10, 1,10, 3,10, 2,10, 3,10
  .byte 1,10, 3,10, 2,10, 3,10, 1,10, 3,10, 2,10, 3,10
  .byte 1,10, 3,10, 2,10, 3,10, 1,10, 1,10, 4,20
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
; starfield: 8 kinds x 8 tiles (128-191), pattern and colour (background transparent)
STAR_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
STAR_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
  .byte $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
  .byte $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
  .byte $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
STAR_BIT:
  .byte $08,$02,$02,$04,$10,$01,$02,$08
STAR_Y0:
  .byte $2F,$2B,$1C,$05,$23,$1C,$27,$10
STAR_SLOW:                ; 0 = one pixel every frame, 1 = every other frame
  .byte $00,$00,$00,$00,$01,$01,$01,$01

; name table of the field: stars on rows 2-22
BG_NT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $8D,$00,$AF,$9A,$86,$B0,$80,$00,$00,$82,$B6,$00,$00,$A5,$00,$83,$00,$00,$A9,$AE,$A8,$A8,$00,$00,$9A,$99,$00,$8F,$B9,$96,$80,$95
  .byte $8E,$00,$A8,$9B,$87,$B1,$81,$00,$00,$83,$B7,$00,$00,$A6,$00,$84,$00,$00,$AA,$AF,$A9,$A9,$00,$00,$9B,$9A,$00,$88,$BA,$97,$81,$96
  .byte $8F,$00,$A9,$9C,$80,$B2,$82,$00,$00,$84,$B0,$00,$00,$A7,$00,$85,$00,$00,$AB,$A8,$AA,$AA,$00,$00,$9C,$9B,$00,$89,$BB,$90,$82,$97
  .byte $88,$00,$AA,$9D,$81,$B3,$83,$00,$00,$85,$B1,$00,$00,$A0,$00,$86,$00,$00,$AC,$A9,$AB,$AB,$00,$00,$9D,$9C,$00,$8A,$BC,$91,$83,$90
  .byte $89,$00,$AB,$9E,$82,$B4,$84,$00,$00,$86,$B2,$00,$00,$A1,$00,$87,$00,$00,$AD,$AA,$AC,$AC,$00,$00,$9E,$9D,$00,$8B,$BD,$92,$84,$91
  .byte $8A,$00,$AC,$9F,$83,$B5,$85,$00,$00,$87,$B3,$00,$00,$A2,$00,$80,$00,$00,$AE,$AB,$AD,$AD,$00,$00,$9F,$9E,$00,$8C,$BE,$93,$85,$92
  .byte $8B,$00,$AD,$98,$84,$B6,$86,$00,$00,$80,$B4,$00,$00,$A3,$00,$81,$00,$00,$AF,$AC,$AE,$AE,$00,$00,$98,$9F,$00,$8D,$BF,$94,$86,$93
  .byte $8C,$00,$AE,$99,$85,$B7,$87,$00,$00,$81,$B5,$00,$00,$A4,$00,$82,$00,$00,$A8,$AD,$AF,$AF,$00,$00,$99,$98,$00,$8E,$B8,$95,$87,$94
  .byte $8D,$00,$AF,$9A,$86,$B0,$80,$00,$00,$82,$B6,$00,$00,$A5,$00,$83,$00,$00,$A9,$AE,$A8,$A8,$00,$00,$9A,$99,$00,$8F,$B9,$96,$80,$95
  .byte $8E,$00,$A8,$9B,$87,$B1,$81,$00,$00,$83,$B7,$00,$00,$A6,$00,$84,$00,$00,$AA,$AF,$A9,$A9,$00,$00,$9B,$9A,$00,$88,$BA,$97,$81,$96
  .byte $8F,$00,$A9,$9C,$80,$B2,$82,$00,$00,$84,$B0,$00,$00,$A7,$00,$85,$00,$00,$AB,$A8,$AA,$AA,$00,$00,$9C,$9B,$00,$89,$BB,$90,$82,$97
  .byte $88,$00,$AA,$9D,$81,$B3,$83,$00,$00,$85,$B1,$00,$00,$A0,$00,$86,$00,$00,$AC,$A9,$AB,$AB,$00,$00,$9D,$9C,$00,$8A,$BC,$91,$83,$90
  .byte $89,$00,$AB,$9E,$82,$B4,$84,$00,$00,$86,$B2,$00,$00,$A1,$00,$87,$00,$00,$AD,$AA,$AC,$AC,$00,$00,$9E,$9D,$00,$8B,$BD,$92,$84,$91
  .byte $8A,$00,$AC,$9F,$83,$B5,$85,$00,$00,$87,$B3,$00,$00,$A2,$00,$80,$00,$00,$AE,$AB,$AD,$AD,$00,$00,$9F,$9E,$00,$8C,$BE,$93,$85,$92
  .byte $8B,$00,$AD,$98,$84,$B6,$86,$00,$00,$80,$B4,$00,$00,$A3,$00,$81,$00,$00,$AF,$AC,$AE,$AE,$00,$00,$98,$9F,$00,$8D,$BF,$94,$86,$93
  .byte $8C,$00,$AE,$99,$85,$B7,$87,$00,$00,$81,$B5,$00,$00,$A4,$00,$82,$00,$00,$A8,$AD,$AF,$AF,$00,$00,$99,$98,$00,$8E,$B8,$95,$87,$94
  .byte $8D,$00,$AF,$9A,$86,$B0,$80,$00,$00,$82,$B6,$00,$00,$A5,$00,$83,$00,$00,$A9,$AE,$A8,$A8,$00,$00,$9A,$99,$00,$8F,$B9,$96,$80,$95
  .byte $8E,$00,$A8,$9B,$87,$B1,$81,$00,$00,$83,$B7,$00,$00,$A6,$00,$84,$00,$00,$AA,$AF,$A9,$A9,$00,$00,$9B,$9A,$00,$88,$BA,$97,$81,$96
  .byte $8F,$00,$A9,$9C,$80,$B2,$82,$00,$00,$84,$B0,$00,$00,$A7,$00,$85,$00,$00,$AB,$A8,$AA,$AA,$00,$00,$9C,$9B,$00,$89,$BB,$90,$82,$97
  .byte $88,$00,$AA,$9D,$81,$B3,$83,$00,$00,$85,$B1,$00,$00,$A0,$00,$86,$00,$00,$AC,$A9,$AB,$AB,$00,$00,$9D,$9C,$00,$8A,$BC,$91,$83,$90
  .byte $89,$00,$AB,$9E,$82,$B4,$84,$00,$00,$86,$B2,$00,$00,$A1,$00,$87,$00,$00,$AD,$AA,$AC,$AC,$00,$00,$9E,$9D,$00,$8B,$BD,$92,$84,$91
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; big letters of the title: M O N C R E S T A, 4 tiles each (192-227)
BIG_P:
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$00,$18,$18,$78,$78,$98,$98,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$18,$18,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
BIG_C:
  .byte $F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0,$F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$A0,$A0,$A0,$A0,$A0,$A0,$B0,$B0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0,$F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$A0,$A0,$A0,$A0,$A0,$A0,$B0,$B0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0,$F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$A0,$A0,$A0,$A0,$A0,$A0,$B0,$B0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70
  .byte $70,$50,$50,$50,$50,$40,$40,$40,$70,$50,$50,$50,$50,$40,$40,$40
  .byte $F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70
  .byte $70,$50,$50,$50,$50,$40,$40,$40,$70,$50,$50,$50,$50,$40,$40,$40
  .byte $F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70
  .byte $70,$50,$50,$50,$50,$40,$40,$40,$70,$50,$50,$50,$50,$40,$40,$40
  .byte $F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70
  .byte $70,$50,$50,$50,$50,$40,$40,$40,$70,$50,$50,$50,$50,$40,$40,$40
  .byte $F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70
  .byte $70,$50,$50,$50,$50,$40,$40,$40,$70,$50,$50,$50,$50,$40,$40,$40
  .byte $F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70
  .byte $70,$50,$50,$50,$50,$40,$40,$40,$70,$50,$50,$50,$50,$40,$40,$40

; big title (text records, end = $FF)
TXT_BIG:
  .byte 2,12,192,193,196,197,196,197,200,201,0
  .byte 3,12,194,195,198,199,198,199,202,203,0
  .byte 5,10,204,205,208,209,212,213,216,217,220,221,224,225,0
  .byte 6,10,206,207,210,211,214,215,218,219,222,223,226,227,0
  .byte $FF

; HUD tiles of the third 2: stage I, II, III waiting
HUD_PAT:
  .byte $18,$18,$3C,$3C,$7E,$FF,$A5,$00
  .byte $42,$42,$DB,$FF,$FF,$BD,$81,$00
  .byte $81,$81,$BD,$FF,$FF,$DB,$99,$00
HUD_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $50,$50,$50,$50,$50,$50,$50,$50

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $00,$44, <512,>512, <STAR_PAT,>STAR_PAT
  .byte 1, $00,$64, <512,>512, <STAR_COL,>STAR_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $00,$4C, <512,>512, <STAR_PAT,>STAR_PAT
  .byte 1, $00,$6C, <512,>512, <STAR_COL,>STAR_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $00,$54, <512,>512, <STAR_PAT,>STAR_PAT
  .byte 1, $00,$74, <512,>512, <STAR_COL,>STAR_COL
  .byte 1, $00,$53, <24,>24, <HUD_PAT,>HUD_PAT
  .byte 1, $00,$73, <24,>24, <HUD_COL,>HUD_COL
  .byte 1, $00,$46, <288,>288, <BIG_P,>BIG_P
  .byte 1, $00,$66, <288,>288, <BIG_C,>BIG_C
  .byte 0

; sprites 16x16 (pattern = index * 4):
;  0 stage I, 4 stage II, 8 stage III, 12 shot, 16 pair 5, 20 pair 7, 24 cold eye, 28 cold eye 2, 32 small eye, 36 small eye 2, 40 super fly, 44 super fly 2, 48 four-d, 52 four-d 2, 56 four-d far, 60 four-d near, 64 meteor, 68 meteor 2, 72 atom, 76 atom 2, 80 explosion 0, 84 explosion 1, 88 explosion 2, 92 flame
SPR_PAGES = 3
SPRITES:
  .byte $00,$00,$01,$01,$03,$03,$06,$07,$07,$0F,$1B,$13,$12,$02,$00,$00
  .byte $00,$00,$00,$00,$80,$80,$C0,$C0,$C0,$E0,$B0,$90,$90,$80,$00,$00
  .byte $00,$00,$20,$20,$20,$70,$77,$7F,$FF,$EF,$EB,$CB,$88,$08,$00,$00
  .byte $00,$00,$08,$08,$08,$1C,$DC,$FC,$FE,$EE,$AE,$A6,$22,$20,$00,$00
  .byte $00,$00,$80,$80,$80,$C7,$CF,$EF,$FF,$FF,$DB,$9B,$8A,$08,$00,$00
  .byte $00,$00,$02,$02,$02,$C6,$E6,$EE,$FE,$FE,$B6,$B2,$A2,$20,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$20,$20,$20,$20,$20,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$08,$08,$08,$08,$08,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02,$00,$00,$00,$00,$00
  .byte $00,$07,$1F,$3F,$38,$73,$77,$76,$77,$73,$38,$3F,$1F,$07,$00,$00
  .byte $00,$C0,$F0,$F8,$38,$9C,$DC,$DC,$DC,$9C,$38,$F8,$F0,$C0,$00,$00
  .byte $00,$47,$1F,$3F,$38,$77,$77,$75,$77,$77,$38,$3F,$1F,$47,$00,$00
  .byte $00,$C4,$F0,$F8,$38,$1C,$9C,$9C,$9C,$1C,$38,$F8,$F0,$C4,$00,$00
  .byte $00,$00,$00,$07,$0F,$18,$13,$12,$13,$18,$0F,$07,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$E0,$30,$90,$90,$90,$30,$E0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$07,$0F,$18,$17,$15,$17,$18,$0F,$07,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$E0,$30,$10,$10,$10,$30,$E0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$60,$70,$39,$1E,$0F,$07,$0B,$12,$22,$00,$00,$00,$00
  .byte $00,$00,$00,$0C,$1C,$38,$F0,$E0,$C0,$A0,$90,$88,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$0B,$1F,$3D,$7B,$67,$4B,$0A,$12,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$A0,$F0,$78,$BC,$CC,$A4,$A0,$90,$00,$00,$00,$00
  .byte $00,$00,$18,$3C,$3E,$1E,$06,$01,$06,$1E,$3E,$3C,$18,$00,$00,$00
  .byte $00,$00,$30,$78,$F8,$F0,$C0,$00,$C0,$F0,$F8,$78,$30,$00,$00,$00
  .byte $00,$00,$03,$03,$07,$13,$72,$7C,$72,$13,$07,$03,$03,$00,$00,$00
  .byte $00,$00,$80,$80,$C0,$90,$9C,$7C,$9C,$90,$C0,$80,$80,$00,$00,$00
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0
  .byte $03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03
  .byte $18,$1C,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$1C,$18,$00
  .byte $18,$38,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$38,$18,$00
  .byte $00,$03,$0F,$1F,$3D,$38,$7D,$7F,$7F,$3F,$3F,$1F,$0F,$03,$00,$00
  .byte $00,$C0,$F0,$F8,$FC,$FC,$FE,$FE,$DE,$8C,$DC,$F8,$E0,$80,$00,$00
  .byte $00,$01,$0F,$1F,$3E,$3F,$7F,$7B,$71,$3B,$3F,$1F,$07,$01,$00,$00
  .byte $00,$E0,$F0,$78,$3C,$7C,$FE,$FE,$FE,$F8,$F8,$F8,$F0,$C0,$00,$00
  .byte $00,$00,$07,$18,$27,$4F,$5F,$5F,$5F,$4F,$27,$18,$07,$00,$00,$00
  .byte $00,$00,$C0,$30,$C8,$E4,$F4,$F4,$F4,$E4,$C8,$30,$C0,$00,$00,$00
  .byte $00,$00,$40,$27,$0F,$1F,$3F,$3F,$3F,$1F,$0F,$27,$40,$00,$00,$00
  .byte $00,$00,$04,$C8,$E0,$F0,$F8,$F8,$F8,$F0,$E0,$C8,$04,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$C0,$E0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$00,$06,$0F,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$18,$F0,$00,$6C,$70,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$00,$08,$00,$10,$28,$04,$00,$00,$02,$00,$00
  .byte $00,$00,$00,$00,$44,$10,$00,$00,$20,$02,$40,$08,$60,$00,$00,$00
  .byte $05,$07,$03,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$C0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; speed of the aliens: [speed * 64 + direction], speeds 0.75 1.25 2.0 3.0 px per frame (8.8 signed)
VXL:
  .byte $00,$13,$25,$38,$49,$5B,$6B,$7A,$88,$94,$A0,$A9,$B1,$B8,$BC,$BF
  .byte $C0,$BF,$BC,$B8,$B1,$A9,$A0,$94,$88,$7A,$6B,$5B,$49,$38,$25,$13
  .byte $00,$ED,$DB,$C8,$B7,$A5,$95,$86,$78,$6C,$60,$57,$4F,$48,$44,$41
  .byte $40,$41,$44,$48,$4F,$57,$60,$6C,$78,$86,$95,$A5,$B7,$C8,$DB,$ED
  .byte $00,$1F,$3E,$5D,$7A,$97,$B2,$CB,$E2,$F7,$0A,$1A,$28,$32,$3A,$3E
  .byte $40,$3E,$3A,$32,$28,$1A,$0A,$F7,$E2,$CB,$B2,$97,$7A,$5D,$3E,$1F
  .byte $00,$E1,$C2,$A3,$86,$69,$4E,$35,$1E,$09,$F6,$E6,$D8,$CE,$C6,$C2
  .byte $C0,$C2,$C6,$CE,$D8,$E6,$F6,$09,$1E,$35,$4E,$69,$86,$A3,$C2,$E1
  .byte $00,$32,$64,$95,$C4,$F1,$1C,$45,$6A,$8C,$AA,$C4,$D9,$EA,$F6,$FE
  .byte $00,$FE,$F6,$EA,$D9,$C4,$AA,$8C,$6A,$45,$1C,$F1,$C4,$95,$64,$32
  .byte $00,$CE,$9C,$6B,$3C,$0F,$E4,$BB,$96,$74,$56,$3C,$27,$16,$0A,$02
  .byte $00,$02,$0A,$16,$27,$3C,$56,$74,$96,$BB,$E4,$0F,$3C,$6B,$9C,$CE
  .byte $00,$4B,$96,$DF,$26,$6A,$AB,$E7,$1F,$52,$7F,$A5,$C6,$DF,$F1,$FC
  .byte $00,$FC,$F1,$DF,$C6,$A5,$7F,$52,$1F,$E7,$AB,$6A,$26,$DF,$96,$4B
  .byte $00,$B5,$6A,$21,$DA,$96,$55,$19,$E1,$AE,$81,$5B,$3A,$21,$0F,$04
  .byte $00,$04,$0F,$21,$3A,$5B,$81,$AE,$E1,$19,$55,$96,$DA,$21,$6A,$B5
VXH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $03,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD
  .byte $FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FE,$FE,$FE,$FE,$FF,$FF,$FF
VYL:
  .byte $40,$41,$44,$48,$4F,$57,$60,$6C,$78,$86,$95,$A5,$B7,$C8,$DB,$ED
  .byte $00,$13,$25,$38,$49,$5B,$6B,$7A,$88,$94,$A0,$A9,$B1,$B8,$BC,$BF
  .byte $C0,$BF,$BC,$B8,$B1,$A9,$A0,$94,$88,$7A,$6B,$5B,$49,$38,$25,$13
  .byte $00,$ED,$DB,$C8,$B7,$A5,$95,$86,$78,$6C,$60,$57,$4F,$48,$44,$41
  .byte $C0,$C2,$C6,$CE,$D8,$E6,$F6,$09,$1E,$35,$4E,$69,$86,$A3,$C2,$E1
  .byte $00,$1F,$3E,$5D,$7A,$97,$B2,$CB,$E2,$F7,$0A,$1A,$28,$32,$3A,$3E
  .byte $40,$3E,$3A,$32,$28,$1A,$0A,$F7,$E2,$CB,$B2,$97,$7A,$5D,$3E,$1F
  .byte $00,$E1,$C2,$A3,$86,$69,$4E,$35,$1E,$09,$F6,$E6,$D8,$CE,$C6,$C2
  .byte $00,$02,$0A,$16,$27,$3C,$56,$74,$96,$BB,$E4,$0F,$3C,$6B,$9C,$CE
  .byte $00,$32,$64,$95,$C4,$F1,$1C,$45,$6A,$8C,$AA,$C4,$D9,$EA,$F6,$FE
  .byte $00,$FE,$F6,$EA,$D9,$C4,$AA,$8C,$6A,$45,$1C,$F1,$C4,$95,$64,$32
  .byte $00,$CE,$9C,$6B,$3C,$0F,$E4,$BB,$96,$74,$56,$3C,$27,$16,$0A,$02
  .byte $00,$04,$0F,$21,$3A,$5B,$81,$AE,$E1,$19,$55,$96,$DA,$21,$6A,$B5
  .byte $00,$4B,$96,$DF,$26,$6A,$AB,$E7,$1F,$52,$7F,$A5,$C6,$DF,$F1,$FC
  .byte $00,$FC,$F1,$DF,$C6,$A5,$7F,$52,$1F,$E7,$AB,$6A,$26,$DF,$96,$4B
  .byte $00,$B5,$6A,$21,$DA,$96,$55,$19,$E1,$AE,$81,$5B,$3A,$21,$0F,$04
VYH:
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FE,$FE,$FE,$FE,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $03,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD
; arctangent: (ratio * 256) / 8 -> angle (64 = 90 degrees)
ATN:
  .byte $01,$02,$03,$04,$06,$07,$08,$09,$0B,$0C,$0D,$0E,$0F,$10,$11,$12
  .byte $13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1B,$1C,$1D,$1E,$1E,$1F,$20
; orbit of the atoms around the centre of the pile (signed, radius 14)
ORB_DX:
  .byte $00,$01,$03,$04,$05,$07,$08,$09,$0A,$0B,$0C,$0C,$0D,$0D,$0E,$0E
  .byte $0E,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0A,$09,$08,$07,$05,$04,$03,$01
  .byte $00,$FF,$FD,$FC,$FB,$F9,$F8,$F7,$F6,$F5,$F4,$F4,$F3,$F3,$F2,$F2
  .byte $F2,$F2,$F2,$F3,$F3,$F4,$F4,$F5,$F6,$F7,$F8,$F9,$FB,$FC,$FD,$FF
ORB_DY:
  .byte $F2,$F2,$F2,$F3,$F3,$F4,$F4,$F5,$F6,$F7,$F8,$F9,$FB,$FC,$FD,$FF
  .byte $00,$01,$03,$04,$05,$07,$08,$09,$0A,$0B,$0C,$0C,$0D,$0D,$0E,$0E
  .byte $0E,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0A,$09,$08,$07,$05,$04,$03,$01
  .byte $00,$FF,$FD,$FC,$FB,$F9,$F8,$F7,$F6,$F5,$F4,$F4,$F3,$F3,$F2,$F2

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$15,$17,$19,$1C,$20,$25,$2C,$36,$45,$21,$21,$21,$18,$18,$18
  .byte $18,$2D,$26,$32,$2A,$38,$2E,$40,$34,$4A,$3A,$59,$43,$70,$4F,$23
  .byte $23,$22,$23,$25,$26,$25,$25,$28,$29,$28,$28,$2B,$2C,$2B,$2C,$2F
  .byte $30,$2F,$30,$34,$35,$33,$35,$3A,$3C,$39,$3A,$41,$43,$40,$42,$4A
  .byte $4D,$49,$4B,$57,$5B,$54,$58,$B6,$1F,$B6,$1F,$B6,$1F,$50,$50,$50
  .byte $50,$50,$3F,$3F,$3F,$3F,$3F,$35,$35,$35,$35,$35,$28,$28,$28,$28
  .byte $28,$35,$35,$35,$35,$35,$28,$28,$28,$28,$28,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$28
  .byte $28,$28,$28,$28,$00,$00,$00,$28,$28,$28,$28,$28,$00,$00,$00,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$50
  .byte $50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$45
  .byte $45,$45,$45,$34,$34,$34,$34,$45,$45,$45,$45
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0B,$0A,$09,$09,$08,$07,$06,$05,$0C,$0B,$0A,$0B,$09,$08
  .byte $06,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
  .byte $07,$06,$05,$04,$03,$02,$01,$09,$08,$07,$06,$05,$04,$0C,$0B,$0A
  .byte $09,$08,$0C,$0B,$0A,$09,$08,$0C,$0B,$0A,$09,$08,$0C,$0B,$0A,$09
  .byte $08,$0C,$0B,$0A,$09,$08,$0C,$0B,$0A,$09,$08,$0C,$0C,$0C,$0B,$0B
  .byte $0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$08,$08,$08,$0D
  .byte $0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D
  .byte $0C,$0A,$09,$08,$07,$05,$04,$0B,$0A,$08,$07,$0B,$0A,$08,$07,$0B
  .byte $0A,$08,$07,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$0A
  .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A
WH_START:
  .byte $00,$01,$0A,$11,$1F,$47,$4D,$7F,$97,$AF
WH_LEN:
  .byte $00,$09,$07,$0E,$28,$06,$32,$18,$18,$0C
W_SHOT = 1
W_SPLIT = 2
W_KILL = 3
W_DIVE = 4
W_THRUST = 5
W_DOCK = 6
W_EXTRA = 7
W_WAVE = 8
W_ALARM = 9

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0C,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$05
  .byte $04,$03,$03,$02,$01,$0F,$0F,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A
  .byte $0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02
  .byte $02,$01,$01,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $0E,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0B
  .byte $0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$09,$09,$09,$08,$08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07
  .byte $07,$07,$06,$06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$05
  .byte $04,$04,$04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$03,$03,$02,$02
  .byte $02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00
EX_NP:
  .byte $00,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08
  .byte $08,$09,$09,$09,$09,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$13
  .byte $13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15
  .byte $15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17
  .byte $17,$17,$17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19
  .byte $19,$19,$19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B,$1B
  .byte $1B
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08
  .byte $08,$08,$07,$07,$06,$06,$06,$05,$05,$04,$04,$04,$03,$03,$02,$02
  .byte $02,$01,$01,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0B
  .byte $0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$06,$06,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$03
  .byte $03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00
EX_TL:
  .byte $00,$DF,$E7,$EF,$F7,$00,$0A,$15,$20,$2C,$3A,$49,$59,$6B,$7F,$96
  .byte $AF,$CC,$EC,$12,$3D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D
  .byte $7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D
  .byte $7D,$7D,$7D,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70
EX_TH:
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$02,$02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04
EX_START:
  .byte $00,$01,$15,$33
EX_LEN:
  .byte $00,$14,$1E,$6E
S_SMALL = 1
S_ROCK = 2
S_SHIP = 3
S_BIG = S_SHIP
