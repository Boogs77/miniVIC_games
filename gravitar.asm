;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_GRAVITAR  -  Atari Gravitar (1982)                  ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: asteroids / lunar_lander (NMI + trampoline $0FD0,    ;
;   joystick VIA, bitmap shadow in RAM, AY sound engine)       ;
;                                                              ;
;   - joystick 1 ($D581) = player 1, joystick 2 ($D580) =      ;
;     player 2 (they take turns):                              ;
;       LEFT / RIGHT = rotate, UP = thrust                     ;
;       button 1 = fire (4 shots at a time)                    ;
;       button 2 or DOWN = shield + tractor beam               ;
;   - solar system view: the death star pulls the ship, fly    ;
;     into a planet to land on it. An alien saucer hunts the   ;
;     ship: if it gets close, a dogfight in deep space         ;
;   - planets: destroy all the bunkers (MISSION COMPLETE) and  ;
;     leave by the top to get the planet bonus, which drops    ;
;     with the time spent. Fuel cells are pulled up with the   ;
;     tractor beam. Round worlds pull towards their centre     ;
;   - red planet: down the tunnel, shoot the reactor and get   ;
;     out before the clock runs out: bonus + 7500 fuel and     ;
;     the next solar system                                    ;
;   - 3 solar systems (4 + 4 + 3 planets and a red planet      ;
;     each), then the universe changes: negative gravity,      ;
;     invisible landscape, both, and round again               ;
;   - bunker 250, saucer 100, reactor 500 points; planets      ;
;     2000-8000 in the first system, 9000 later; super bonus   ;
;     for the first mission; fuel 10000 at the start, thrust   ;
;     and shield burn it, the game ends when it runs out;      ;
;     6 ships, extra ship every 10000 points                   ;
;   - landscape, bunkers, fuel cells and planets are drawn in  ;
;     the bitmap (with a copy in RAM used for the collisions); ;
;     ship, shield, beam, saucer, shots and explosions are     ;
;     sprites                                                  ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     fire, thrust rumble, shield / tractor buzz, saucer hum,  ;
;     bunker fire, explosions, fuel pick-up, landing and take  ;
;     off sweeps, mission complete, reactor alarm, low fuel    ;
;     beeps, a short tune for every new solar system           ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page ----------------
GRAV        = $30      ; gravity of the planet (1/256 px per frame^2)
GMODE       = $31      ; 0 none, 1 down, 2 towards GCX / GCY, 3 towards the star
GCX         = $32      ; centre of a round world
GCY         = $33
GNEG        = $34      ; 1 = negative gravity (planets push)
MFLAGS      = $35      ; flags of the map (1 round, 2 no wrap, 4 reactor)
BLEFT       = $36      ; bunkers alive
NBUNK       = $37      ; bunkers of the map
NTANK       = $38      ; fuel cells of the map
MODE        = $39      ; 0 solar system, 1 planet, 2 dogfight
LX0         = $3A      ; line / circle: start or centre
LY0         = $3B
LX1         = $3C      ; line: end
LY1         = $3D
LDXV        = $3E      ; |dx|, |dy|
LDYV        = $3F
LERR        = $40
LSX         = $41      ; steps +1 / -1
LSY         = $42
LCNT        = $43
PBL         = $44      ; planet bonus (BCD): tens and units
PBH         = $45      ;                     thousands and hundreds
PBT         = $46      ; frames to the next drop of the bonus
RTIME       = $47      ; reactor clock (BCD seconds)
RTF         = $48      ; frames of the second
RHIT        = $49      ; 1 = reactor shot
MSGT        = $4A      ; frames of the message on the screen (0 = none)
ENTLK       = $4B      ; frames in which the planets cannot be entered
SAVX        = $4C      ; where the ship was before the dogfight
SAVY        = $4D
INV         = $4E      ; 1 = invisible landscape
TCOLR       = $4F      ; colour byte of the landscape
MSGR        = $50      ; screen row of the message
HSUB        = $51      ; half steps left
OBX         = $52      ; point tested by the collisions
OBY         = $53
BEAT_N      = $54      ; which alarm note
BFT         = $55      ; frames to the next bunker shot
BFI         = $56      ; frames between two bunker shots
KDIFF       = $57      ; difficulty: universe * 3 + system (0-11)
EVT         = $58      ; event for the main loop (EV_*)
PLN         = $59      ; planet of the system (0-3, 4 = red planet)
MAPP        = $5A      ; 2 bytes: map being read
ALT         = $5C      ; alarm timer
MPY         = $5D      ; index in the map
LTHK        = $5E      ; 1 = lines 2 pixels tall
SPAN        = $5F      ; phase of the death star colours

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
SPTR        = $70      ; 2 bytes: shadow pointer
TP          = $72      ; 2 bytes: text records
CELLC       = $78      ; cell column (0-31)
CELLR       = $79      ; cell row (0-23)
TCOL        = $7A      ; colour byte (fg<<4 | bg) for texts
PX          = $7B      ; pixel of the playfield
PY          = $7C
PCOL        = $7D      ; colour byte of the pixels
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)
TYV         = $80
BIGC        = $81
BIGR        = $82
NPL         = $84      ; number of players (1-2)
CURP        = $85      ; player in the game (0-1)
LIVES       = $86      ; 2 bytes: ships per player
SCA         = $88      ; 2 bytes: score per player, BCD low
SCB         = $8A      ; 2 bytes: BCD middle
SCC         = $8C      ; 2 bytes: BCD high
HIA         = $8E      ; hi score, BCD low / middle / high
HIB         = $8F
HIC         = $90
NXL         = $91      ; 2 bytes: next extra ship (BCD high digits of the score)
SHXL        = $93      ; ship position 8.8 (centre), Y = 0-175 in the playfield
SHXH        = $94
SHYL        = $95
SHYH        = $96
SVXL        = $97      ; ship velocity 8.8 signed (VY must follow VX)
SVXH        = $98
SVYL        = $99
SVYH        = $9A
SANG        = $9B      ; ship angle 0-15 (0 = up, clockwise)
ROTT        = $9C      ; rotation repeat timer
SHIPST      = $9D      ; 0 flying, 1 exploding, 2 waiting, 3 gone (screen change)
SHT         = $9E      ; timer of the ship state
THR         = $9F      ; 1 = engine on
SHLD        = $A0      ; 1 = shield and tractor beam on
JOYC        = $A1      ; joystick of the player in the game
FIRE_OLD    = $A2      ; button 1 of the previous frame
UFO_ON      = $A3      ; 1 = saucer flying
UFXL        = $A4      ; saucer position 8.8 (centre)
UFX         = $A5
UFYL        = $A6
UFY         = $A7
UFVXL       = $A8      ; saucer velocity 8.8 signed (same layout as the ship)
UFVXH       = $A9
UFVYL       = $AA
UFVYH       = $AB
UFSPN       = $AC      ; time to the next saucer (x 4 frames)
UFT         = $AD      ; frames to the next saucer shot
BI          = $AE      ; shot being moved
SPX         = $AF      ; SET_SPR: centre, pattern, colour
SPY         = $B0
SPN         = $B1
SPC         = $B2
EXI         = $B3      ; next explosion slot
PTS_L       = $B4      ; points to add (BCD)
PTS_M       = $B5
PTS_H       = $B6
PCX         = $B7      ; centre of an explosion
PCY         = $B8
BEAMD       = $B9      ; tractor beam: 0 off, 1 down, 2 up
PLAYING     = $BA      ; 1 = a game is running

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_BEAT   = $DC         ; request: 1 / 2 = alarm note
BEAT_POS   = $DD         ; NMI: frame of the alarm note ($FF = silent)
BEAT_NOTE  = $DE
SND_UFO    = $DF         ; channel A loop: 0 none, 1 shield buzz, 2 saucer hum
SND_THR    = $E0         ; 1 = thrust rumble
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

; ---------------- zero page: more game temporaries ----------------
VX2L       = $E1         ; half of the ship velocity (one half step)
VX2H       = $E2
VY2L       = $E3
VY2H       = $E4
AX0        = $E5         ; ATAN: from (AX0, AY0) to (AX1, AY1)
AY0        = $E6
AX1        = $E7
AY1        = $E8
DFW        = $E9         ; frames before leaving a won dogfight
NOFUEL     = $EA         ; 1 = the ship exploded with an empty tank
VLL        = $EC         ; CLAMPV: speed limit 8.8
VLH        = $ED
SHX        = $EE         ; DRAW_SHAPE: left (multiple of 8), top, first byte, colour, mode
SHY        = $EF
SHI        = $F0
SHCOL      = $F1
SHM        = $F2
SHN        = $F3
SHYY       = $F4
CR         = $F5         ; CIRCLE: radius, x, y, error
CXX        = $F6
CYY        = $F7
CERR       = $F8
LCNT2      = $F9         ; points left in a polyline

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects

; ---------------- data of the player in the game (swapped at every turn) ----------------
PBLOCK     = $0300
FUA        = $0300       ; fuel (BCD): units and tens
FUB        = $0301       ;             hundreds and thousands
FUC        = $0302       ;             ten thousands
UNIV       = $0303       ; universe 0-3 (bit 0 negative gravity, bit 1 invisible)
SYSN       = $0304       ; solar system 0-2
PDONE      = $0305       ; planets completed (BITMASK of the planet)
BUNKM      = $0306       ; 5 bytes: bunkers destroyed on every planet
TANKM      = $030B       ; 5 bytes: fuel cells taken on every planet
SUPERF     = $0310       ; 1 = super bonus already given
PB_LEN     = 17
PSAVE      = $0320       ; the same block of the player waiting for his turn

; ---------------- shots and explosions ----------------
NSHOT  = 8               ; 0-3 ship, 4-7 bunkers and saucer
B_T    = $0340           ; frames of life left (0 = free)
B_XL   = $0348
B_XH   = $0350
B_YL   = $0358
B_YH   = $0360
B_VXL  = $0368
B_VXH  = $0370
B_VYL  = $0378
B_VYH  = $0380
NEXPL  = 3
E_T    = $0388           ; frame of the explosion (0 = free)
E_X    = $038B
E_Y    = $038E

; ---------------- the map on the screen ----------------
MAXB   = 8
BK_X   = $0398           ; bunker: left (pixels), top, side (0 up, 1 down, 2 left, 3 right), alive
BK_Y   = $03A0
BK_O   = $03A8
BK_ON  = $03B0
TK_X   = $03B8           ; fuel cell: left, top, side (0 up, 1 hanging), still there
TK_Y   = $03BC
TK_O   = $03C0
TK_ON  = $03C4
RX     = $03C8           ; reactor: left, top
RY     = $03C9
PL_X   = $03D0           ; planets of the solar system: centre, radius, map, colour
PL_Y   = $03D5
PL_R   = $03DA
PL_M   = $03DF
PL_C   = $03E4
STX    = $03E9           ; death star
STY    = $03EA
HMX    = $03EB           ; home base
HMY    = $03EC

; copy of the playfield in RAM (screen rows 2-23 = playfield rows 0-21)
SHP0   = $4800           ; patterns ($4800-$5DFF)
SHC0   = $5E00           ; colours ($5E00-$73FF)

; ---------------- parameters ----------------
FIELD_H     = 176        ; playfield: Y 0-175 = screen lines 16-191
ROT_DELAY   = 3          ; frames between two rotation steps
SHOT_LIFE   = 36
BTN_MASK    = %00110000
HIDE_Y      = $C0
SHIP_COL    = $07
EV_LOST     = 1          ; events for the main loop
EV_ENTER    = 2
EV_EXIT     = 3
EV_FIGHT    = 4
EV_WON      = 5

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
  JSR CLEAR_VRAM
  JSR INIT_NAME_TABLE
  JSR LOAD_SPRITES
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY
  STA VINT                     ; VDP interrupt off (R1 = $C6)
  STA HIA
  STA HIB
  STA HIC
  STA FRAME_CNT
  STA LAST_FRAME
  STA CURP
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  STA SND_BEAT
  STA EXI
  STA MSGT
  STA EVT
  LDX #$01
.rs_p:
  STA SCA,X
  STA SCB,X
  STA SCC,X
  STA LIVES,X
  DEX
  BPL .rs_p
  LDA #$FF
  STA BEAT_POS
  LDA #$01
  STA NPL
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE SCREEN
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  LDA #$00
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  STA MSGT
  STA MODE
  LDA #CMD_GAME
  STA SND_CMD
  JSR SCREEN_OFF
  LDX #(PB_LEN-1)              ; a clean block: the demo landscape is complete
.t_z:
  STZ PBLOCK,X
  DEX
  BPL .t_z
  JSR SET_UNIV
  STZ PLN
  JSR CLEAR_SH
  LDA #0
  JSR LOAD_MAP
  JSR UPLOAD_FIELD
  JSR CLEAR_HUD
  JSR DRAW_HI
  JSR DRAW_SCORES
  LDA #<TITLE_BIG
  STA TP
  LDA #>TITLE_BIG
  STA TP+1
  JSR DRAW_BIGWORDS
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR DRAW_TEXT
  JSR SCREEN_ON
.t_rel:                        ; buttons released...
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR WAIT_FRAME
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
;  NEW GAME
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  LDA #$00
  STA SCA,X
  STA SCB,X
  STA SCC,X
  STA LIVES,X
  LDA #$01
  STA NXL,X
  DEX
  BPL .ng_p
  LDA #6
  STA LIVES
  LDX NPL
  CPX #$02
  BNE .ng_1
  STA LIVES+1
.ng_1:
  LDX #(PB_LEN-1)              ; both players: first system, full tank
.ng_b:
  STZ PBLOCK,X
  DEX
  BPL .ng_b
  LDA #$01
  STA FUC                      ; 10000 fuel units
  LDX #(PB_LEN-1)
.ng_c:
  LDA PBLOCK,X
  STA PSAVE,X
  DEX
  BPL .ng_c
  STZ CURP
  STZ NOFUEL
  ; fall into TURN_START


; ===============================================================
;  TURN OF A PLAYER: from the home base of his solar system
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  LDA #$01
  STA PLAYING
  JSR SET_UNIV
  JSR SYS_SCREEN
  JSR AT_HOME
  LDA NPL
  CMP #$02
  BNE .ts_on
  LDA #<TXT_P1                 ; "PLAYER n"
  STA TP
  LDA #>TXT_P1
  STA TP+1
  LDX CURP
  BEQ .ts_p
  LDA #<TXT_P2
  STA TP
  LDA #>TXT_P2
  STA TP+1
.ts_p:
  LDA #120
  JSR SHOW_MSG
.ts_on:
  JSR SCREEN_ON
  ; fall into GAME_LOOP


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  LDX CURP
  LDA P_JOY,X
  STA JOYC
  JSR UPDATE_SHIP
  JSR UPDATE_SHOTS
  JSR UPDATE_UFO
  JSR UPDATE_BUNKERS
  JSR UPDATE_EXPL
  JSR UPDATE_TIMERS
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA EVT
  BEQ GAME_LOOP
  STZ EVT
  ASL A
  TAX
  JMP (EV_TAB-2,X)

EV_TAB:     .word ON_LOST,ON_ENTER,ON_EXIT,ON_FIGHT,ON_WON


; ---------------------------------------------------------------
; the explosion of the ship is over
; ---------------------------------------------------------------
ON_LOST:
  LDX CURP
  LDA LIVES,X
  BEQ .ol_f
  DEC LIVES,X
.ol_f:
  LDA NOFUEL                   ; empty tank: the game of this player is over
  BEQ .ol_n
  STZ NOFUEL
  STZ LIVES,X
  JSR VDP_INT_OFF
  LDA #<TXT_NOFUEL
  STA TP
  LDA #>TXT_NOFUEL
  STA TP+1
  LDA #1
  JSR SHOW_MSG
  JSR VDP_INT_ON
  LDA #150
  JSR WAIT_FRAMES
.ol_n:
  JSR VDP_INT_OFF
  JSR DRAW_LIVES
  JSR VDP_INT_ON
  LDA NPL
  CMP #$02
  BNE .ol_same
  LDA CURP
  EOR #$01
  TAX
  LDA LIVES,X
  BEQ .ol_same
  JMP SWITCH_PLAYER
.ol_same:
  LDX CURP
  LDA LIVES,X
  BEQ .ol_over
  JSR SYS_SCREEN               ; next ship from the home base
  JSR AT_HOME
  JSR SCREEN_ON
  JMP GAME_LOOP
.ol_over:
  JMP GAME_OVER

; the other player: swap the data blocks
SWITCH_PLAYER:
  JSR HIDE_SPRITES
  LDA #40
  JSR WAIT_FRAMES
  LDX #(PB_LEN-1)
.sw_l:
  LDA PBLOCK,X
  LDY PSAVE,X
  STA PSAVE,X
  TYA
  STA PBLOCK,X
  DEX
  BPL .sw_l
  LDA CURP
  EOR #$01
  STA CURP
  JMP TURN_START

; ship at the home base, waiting to appear
AT_HOME:
  LDA HMX
  STA SHXH
  LDA HMY
  STA SHYH
  STZ SANG
  STZ SVXL
  STZ SVXH
  STZ SVYL
  STZ SVYH
  LDA #$02
  STA SHIPST
  LDA #60
  STA SHT
  RTS


; ---------------------------------------------------------------
; the ship flew into the planet PLN
; ---------------------------------------------------------------
ON_ENTER:
  LDA #W_ENTER
  LDX #2
  JSR SFX_WHISTLE
  JSR PLANET_SCREEN
  LDA #128                     ; from the top of the screen
  STA SHXH
  LDA #4
  STA SHYH
  STZ SHXL
  STZ SHYL
  STZ SVXL
  STZ SVXH
  LDA #$60                     ; drifting down (faster when the planet pushes)
  STA SVYL
  LDA GNEG
  STA SVYH
  JSR SHIP_APPEAR
  JSR SCREEN_ON
  JMP GAME_LOOP


; ---------------------------------------------------------------
; the ship left the planet: bonus, next system or back to the map
; ---------------------------------------------------------------
ON_EXIT:
  LDA #W_EXIT
  LDX #2
  JSR SFX_WHISTLE
  JSR SCREEN_OFF
  LDA MFLAGS
  AND #$04
  BNE .ox_red
  LDA BLEFT                    ; mission complete?
  BNE .ox_back
  JSR PLANET_DONE
  LDX SYSN
  LDA PDONE
  AND SYS_DONE,X
  CMP SYS_DONE,X
  BNE .ox_back
  JMP NEXT_SYSTEM              ; all the planets of the system
.ox_red:
  LDA RHIT
  BEQ .ox_back
  JSR PLANET_DONE
  LDA #$75                     ; 7500 fuel units
  JSR FUEL_ADD
  JMP NEXT_SYSTEM
.ox_back:
  JSR SYS_SCREEN
  LDA STX                      ; next to the planet, away from the star
  STA AX0
  LDA STY
  STA AY0
  LDX PLN
  LDA PL_X,X
  STA AX1
  LDA PL_Y,X
  STA AY1
  JSR ATAN
  TAY
  LDA AX1
  CLC
  ADC OUTX,Y
  STA SHXH
  LDA AY1
  CLC
  ADC OUTY,Y
  JSR WRAP_Y
  STA SHYH
  STZ SVXL
  STZ SVXH
  STZ SVYL
  STZ SVYH
  JSR SHIP_APPEAR
  LDA #60
  STA ENTLK
  JSR SCREEN_ON
  JMP GAME_LOOP

; mission accomplished on the planet PLN: bonus and super bonus
PLANET_DONE:
  LDX PLN
  LDA BITMASK,X
  ORA PDONE
  STA PDONE
  LDA PBL
  STA PTS_L
  LDA PBH
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  LDA SUPERF                   ; super bonus: first mission of the game,
  BNE .pd_r                    ; on the planet chosen in the first system
  LDA UNIV
  ORA SYSN
  BNE .pd_r
  LDA #$01
  STA SUPERF
  LDX PLN
  STZ PTS_L
  LDA SUP_M,X
  STA PTS_M
  LDA SUP_H,X
  STA PTS_H
  JSR ADD_SCORE
.pd_r:
  LDA #W_DONE
  LDX #2
  JMP SFX_WHISTLE

; next solar system (after the third one, the next universe)
NEXT_SYSTEM:
  LDX #$FF
  TXS
  INC SYSN
  LDA SYSN
  CMP #3
  BCC .ns_s
  STZ SYSN
  LDA UNIV
  INC A
  AND #$03
  STA UNIV
.ns_s:
  LDX #10                      ; all the planets and bunkers come back
.ns_z:
  STZ PDONE,X
  DEX
  BPL .ns_z
  LDA #W_START
  LDX #2
  JSR SFX_WHISTLE
  JSR SET_UNIV
  JSR SYS_SCREEN
  JSR AT_HOME
  LDA #90
  STA SHT
  LDA #<TXT_NEWSYS             ; new universe: its rule, otherwise "NEW SOLAR SYSTEM"
  STA TP
  LDA #>TXT_NEWSYS
  STA TP+1
  LDA SYSN
  BNE .ns_m
  LDX UNIV
  LDA UNIV_TL,X
  STA TP
  LDA UNIV_TH,X
  STA TP+1
.ns_m:
  LDA #180
  JSR SHOW_MSG
  JSR SCREEN_ON
  JMP GAME_LOOP


; ---------------------------------------------------------------
; the saucer caught the ship in the solar system: dogfight
; ---------------------------------------------------------------
ON_FIGHT:
  LDA SHXH
  STA SAVX
  LDA SHYH
  STA SAVY
  JSR SCREEN_OFF
  LDA #2
  STA MODE
  STZ GMODE
  JSR CLEAR_OBJECTS
  JSR CLEAR_SH
  LDA #40                      ; deep space: a few stars
  STA T6
.of_s:
  JSR NEXT_RND
  LDA RND
  STA PX
  JSR NEXT_RND
  LDA RND
  AND #$7F
  STA PY
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC PY
  STA PY
  LDA #$E1
  STA PCOL
  JSR PLOT_SH
  DEC T6
  BNE .of_s
  JSR UPLOAD_FIELD
  JSR DRAW_HUD
  LDA #60
  STA SHXH
  LDA #88
  STA SHYH
  LDA #4
  STA SANG
  STZ SVXL
  STZ SVXH
  STZ SVYL
  STZ SVYH
  JSR SHIP_APPEAR
  LDA #1                       ; the saucer on the other side
  STA UFO_ON
  LDA #196
  STA UFX
  LDA #88
  STA UFY
  STZ UFVXL
  STZ UFVXH
  STZ UFVYL
  STZ UFVYH
  LDA #50
  STA UFT
  STZ DFW
  LDA #W_ENTER
  LDX #2
  JSR SFX_WHISTLE
  JSR SCREEN_ON
  JMP GAME_LOOP

; dogfight won: back where the ship was
ON_WON:
  JSR SYS_SCREEN
  LDA SAVX
  STA SHXH
  LDA SAVY
  STA SHYH
  STZ SVXL
  STZ SVXH
  STZ SVYL
  STZ SVYH
  JSR SHIP_APPEAR
  LDA #60
  STA ENTLK
  JSR SCREEN_ON
  JMP GAME_LOOP


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  LDA #$00
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  STA UFO_ON
  STA MSGT
  LDX #$01                     ; hi score = best of the two players
.go_p:
  LDA SCC,X
  CMP HIC
  BCC .go_n
  BNE .go_new
  LDA SCB,X
  CMP HIB
  BCC .go_n
  BNE .go_new
  LDA SCA,X
  CMP HIA
  BCC .go_n
  BEQ .go_n
.go_new:
  LDA SCA,X
  STA HIA
  LDA SCB,X
  STA HIB
  LDA SCC,X
  STA HIC
.go_n:
  DEX
  BPL .go_p
  LDA #60
  JSR WAIT_FRAMES
  JSR SCREEN_OFF
  JSR CLEAR_SH
  JSR UPLOAD_FIELD
  JSR CLEAR_HUD
  JSR DRAW_HI
  JSR DRAW_SCORES
  LDA #<OVER_BIG
  STA TP
  LDA #>OVER_BIG
  STA TP+1
  JSR DRAW_BIGWORDS
  LDA #<TXT_PRESS
  STA TP
  LDA #>TXT_PRESS
  STA TP+1
  JSR DRAW_TEXT
  JSR SCREEN_ON
  LDA #90
  JSR WAIT_FRAMES
  JSR WAIT_FIRE
  JMP TITLE


; ===============================================================
;  SCREENS
; ===============================================================
; difficulty and rules of the universe of the player
SET_UNIV:
  LDA UNIV
  ASL A
  ADC UNIV
  ADC SYSN
  STA KDIFF                    ; universe * 3 + system
  LDA UNIV
  LSR A
  AND #$01
  STA INV
  LDA UNIV
  AND #$01
  STA GNEG
  LDA KDIFF                    ; bunkers fire every 90 - 5k frames (30 at least)
  ASL A
  ASL A
  ADC KDIFF
  STA T0
  LDA #90
  SEC
  SBC T0
  CMP #30
  BCS .su_b
  LDA #30
.su_b:
  STA BFI
  RTS

; solar system view (the screen stays off: the caller turns it on)
SYS_SCREEN:
  JSR SCREEN_OFF
  STZ MODE
  LDA #3
  STA GMODE
  JSR CLEAR_OBJECTS
  JSR CLEAR_SH
  LDA SYSN                     ; copy the system: 5 planets from SYSN * 5
  ASL A
  ASL A
  ADC SYSN
  TAY
  LDX #0
.ss_c:
  LDA SYS_PX,Y
  STA PL_X,X
  LDA SYS_PY,Y
  STA PL_Y,X
  LDA SYS_PR,Y
  STA PL_R,X
  LDA SYS_PM,Y
  STA PL_M,X
  LDA SYS_PC,Y
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA PL_C,X
  INY
  INX
  CPX #5
  BNE .ss_c
  LDX SYSN
  LDA SYS_SX,X
  STA STX
  LDA SYS_SY,X
  STA STY
  LDA SYS_HX,X
  STA HMX
  LDA SYS_HY,X
  STA HMY
  LDX #0                       ; planets still to complete
.ss_p:
  STX LCNT2
  JSR PLANET_LEFT
  BCC .ss_pn
  LDA PL_X,X
  STA LX0
  LDA PL_Y,X
  STA LY0
  LDA PL_C,X
  STA PCOL
  LDA PL_R,X
  STA CR
  JSR CIRCLE
  LDX LCNT2
  CPX #4
  BNE .ss_pn
  LDA #3                       ; the red planet: a core inside
  STA CR
  JSR CIRCLE
.ss_pn:
  LDX LCNT2
  INX
  CPX #5
  BNE .ss_p
  LDA STX                      ; death star: a ball with spikes
  STA LX0
  LDA STY
  STA LY0
  LDA #$B1
  STA PCOL
  LDA #5
  STA CR
  JSR CIRCLE
  LDA #2
  STA CR
  JSR CIRCLE
  STZ LTHK
  LDA #$81
  STA PCOL
  LDX #0
.ss_k:
  STX T7
  LDA STX
  CLC
  ADC SPK_X0,X
  STA LX0
  LDA STY
  CLC
  ADC SPK_Y0,X
  STA LY0
  LDA STX
  CLC
  ADC SPK_X1,X
  STA LX1
  LDA STY
  CLC
  ADC SPK_Y1,X
  STA LY1
  JSR DRAW_LINE
  LDX T7
  INX
  CPX #8
  BNE .ss_k
  LDA HMX                      ; home base
  AND #$F8
  STA SHX
  LDA HMY
  SEC
  SBC #4
  STA SHY
  LDA #SH_HOME
  STA SHI
  LDA #$E1
  STA SHCOL
  STZ SHM
  JSR DRAW_SHAPE
  JSR UPLOAD_FIELD
  JSR DRAW_LABELS
  JSR DRAW_HUD
  LDA #100
  STA UFSPN
  RTS

; carry = 1 when the planet X is there and not completed (X kept)
PLANET_LEFT:
  LDA PL_M,X
  CMP #$FF
  BEQ .pl_no
  LDA PDONE
  AND BITMASK,X
  BNE .pl_no
  SEC
  RTS
.pl_no:
  CLC
  RTS

; bonus of every planet under it (VRAM only)
DRAW_LABELS:
  LDX #0
.dl_l:
  STX T7
  JSR PLANET_LEFT
  BCC .dl_n
  LDA PL_C,X
  STA TCOL
  LDA PL_Y,X                   ; first screen row under the planet
  CLC
  ADC PL_R,X
  ADC #16
  LSR A
  LSR A
  LSR A
  INC A
  CMP #24
  BCC .dl_r
  LDA #23
.dl_r:
  STA CELLR
  LDA PL_X,X
  LSR A
  LSR A
  LSR A
  SEC
  SBC #2
  BCS .dl_c
  LDA #0
.dl_c:
  CMP #29
  BCC .dl_c2
  LDA #28
.dl_c2:
  STA CELLC
  JSR PLANET_BONUS
  JSR PUT_BCD
  LDA #$30
  JSR PUT_CHAR
  INC CELLC
  LDA #$30
  JSR PUT_CHAR
.dl_n:
  LDX T7
  INX
  CPX #5
  BNE .dl_l
  RTS

; A = starting bonus of the planet X (hundreds, BCD)
PLANET_BONUS:
  LDA UNIV
  ORA SYSN
  BNE .pb_9
  LDA BONUS1,X
  RTS
.pb_9:
  LDA #$90
  RTS

; planet PLN (the screen stays off)
PLANET_SCREEN:
  JSR SCREEN_OFF
  LDA #1
  STA MODE
  JSR CLEAR_OBJECTS
  JSR CLEAR_SH
  LDX PLN
  LDA PL_M,X
  JSR LOAD_MAP
  JSR UPLOAD_FIELD
  LDX PLN
  JSR PLANET_BONUS
  STA PBH
  STZ PBL
  LDA #30
  STA PBT
  STZ RHIT
  LDA #60
  STA RTF
  LDA KDIFF                    ; reactor clock: 23 s, 2 less in every later system (11 at least)
  ASL A
  STA T0
  LDA #23
  SEC
  SBC T0
  BCC .ps_t
  CMP #11
  BCS .ps_t2
.ps_t:
  LDA #11
.ps_t2:
  JSR BIN2BCD
  STA RTIME
  LDA BFI
  STA BFT
  JSR NEXT_RND                 ; first saucer in 10-14 s
  LDA RND
  AND #$3F
  CLC
  ADC #150
  STA UFSPN
  JMP DRAW_HUD

; everything that moves goes away
CLEAR_OBJECTS:
  LDX #(NSHOT-1)
.co_b:
  STZ B_T,X
  DEX
  BPL .co_b
  LDX #(NEXPL-1)
.co_e:
  STZ E_T,X
  DEX
  BPL .co_e
  STZ UFO_ON
  STZ SND_UFO
  STZ SND_THR
  STZ THR
  STZ SHLD
  STZ BEAMD
  STZ MSGT
  STZ DFW
  STZ ENTLK
  STZ BEAT_N
  STZ ALT
  RTS


; ---------------------------------------------------------------
; map A: landscape in the shadow, bunkers, fuel cells, reactor, gravity
; ---------------------------------------------------------------
LOAD_MAP:
  TAX
  LDA MAP_LO,X
  STA MAPP
  LDA MAP_HI,X
  STA MAPP+1
  LDY #0
  LDA (MAPP),Y
  STA MFLAGS
  INY
  LDA (MAPP),Y
  STA GRAV
  INY
  LDA (MAPP),Y                 ; colour of the landscape
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  LDX INV
  BEQ .lm_v
  LDA #$11                     ; invisible: black on black
.lm_v:
  STA TCOLR
  STA PCOL
  INY
  LDA (MAPP),Y
  STA GCX
  INY
  LDA (MAPP),Y
  STA GCY
  INY
  LDA #1
  STA GMODE
  STA LTHK
  LDA MFLAGS
  AND #$01
  BEQ .lm_l
  INC GMODE                    ; round world: towards the centre
.lm_l:                         ; ---- polylines
  LDA (MAPP),Y
  BEQ .lm_le
  STA LCNT2
  INY
  LDA (MAPP),Y
  STA LX1
  INY
  LDA (MAPP),Y
  STA LY1
  INY
  DEC LCNT2
.lm_seg:
  LDA LX1
  STA LX0
  LDA LY1
  STA LY0
  LDA (MAPP),Y
  STA LX1
  INY
  LDA (MAPP),Y
  STA LY1
  INY
  STY MPY
  JSR DRAW_LINE
  LDY MPY
  DEC LCNT2
  BNE .lm_seg
  BRA .lm_l
.lm_le:
  INY
  LDA (MAPP),Y                 ; ---- bunkers
  STA NBUNK
  INY
  LDX #0
.lm_b:
  CPX NBUNK
  BCS .lm_be
  LDA (MAPP),Y
  ASL A
  ASL A
  ASL A
  STA BK_X,X
  INY
  LDA (MAPP),Y
  STA BK_Y,X
  INY
  LDA (MAPP),Y
  STA BK_O,X
  INY
  INX
  BRA .lm_b
.lm_be:
  LDA (MAPP),Y                 ; ---- fuel cells
  STA NTANK
  INY
  LDX #0
.lm_t:
  CPX NTANK
  BCS .lm_te
  LDA (MAPP),Y
  ASL A
  ASL A
  ASL A
  STA TK_X,X
  INY
  LDA (MAPP),Y
  STA TK_Y,X
  INY
  LDA (MAPP),Y
  STA TK_O,X
  INY
  INX
  BRA .lm_t
.lm_te:
  LDA MFLAGS                   ; ---- reactor
  AND #$04
  BEQ .lm_ok
  LDA (MAPP),Y
  ASL A
  ASL A
  ASL A
  STA RX
  INY
  LDA (MAPP),Y
  STA RY
  STA SHY
  LDA RX
  STA SHX
  LDA #SH_REACTOR
  STA SHI
  LDA #$F1
  STA SHCOL
  STZ SHM
  JSR DRAW_SHAPE
.lm_ok:
  STZ BLEFT                    ; bunkers still there (none in the first reactor)
  LDX #0
.lm_ba:
  CPX NBUNK
  BCS .lm_ta
  STZ BK_ON,X
  LDA MFLAGS
  AND #$04
  BEQ .lm_b1
  LDA KDIFF
  BEQ .lm_bn
.lm_b1:
  LDY PLN
  LDA BUNKM,Y
  AND BITMASK,X
  BNE .lm_bn
  INC BK_ON,X
  INC BLEFT
  LDA BK_X,X
  STA SHX
  LDA BK_Y,X
  STA SHY
  LDA BK_O,X
  ASL A
  ASL A
  ASL A
  STA SHI
  LDA #$81
  STA SHCOL
  STZ SHM
  PHX
  JSR DRAW_SHAPE
  PLX
.lm_bn:
  INX
  BRA .lm_ba
.lm_ta:
  LDX #0                       ; fuel cells not taken yet
.lm_tb:
  CPX NTANK
  BCS .lm_r
  STZ TK_ON,X
  LDY PLN
  LDA TANKM,Y
  AND BITMASK,X
  BNE .lm_tn
  INC TK_ON,X
  LDA TK_X,X
  STA SHX
  LDA TK_Y,X
  STA SHY
  LDA TK_O,X
  ASL A
  ASL A
  ASL A
  ADC #SH_TANK
  STA SHI
  LDA #$51
  STA SHCOL
  STZ SHM
  PHX
  JSR DRAW_SHAPE
  PLX
.lm_tn:
  INX
  BRA .lm_tb
.lm_r:
  RTS


; ===============================================================
;  SHIP
; ===============================================================
UPDATE_SHIP:
  STZ THR
  STZ SHLD
  STZ BEAMD
  LDA SHIPST
  BEQ .us_fly
  CMP #$01
  BNE .us_n1
  DEC SHT                      ; ---- exploding
  BNE .us_r
  LDA #EV_LOST
  STA EVT
  LDA #$03
  STA SHIPST
.us_r:
  RTS
.us_n1:
  CMP #$02
  BNE .us_r
  DEC SHT                      ; ---- waiting at the home base
  BNE .us_r
  JMP SHIP_APPEAR
.us_fly:
  ; ---- rotation
  LDA ROTT
  BEQ .us_rot
  DEC ROTT
  BRA .us_thr
.us_rot:
  LDA JOYC
  AND #%00000100               ; left
  BEQ .us_nl
  LDA SANG
  SEC
  SBC #1
  BRA .us_ra
.us_nl:
  LDA JOYC
  AND #%00001000               ; right
  BEQ .us_thr
  LDA SANG
  CLC
  ADC #1
.us_ra:
  AND #$0F
  STA SANG
  LDA #ROT_DELAY
  STA ROTT
.us_thr:
  ; ---- thrust (2 fuel units per frame)
  LDA JOYC
  AND #%00000001
  BEQ .us_sh
  LDA #$02
  JSR FUEL_USE
  BCS .us_r
  LDA #$01
  STA THR
  LDY SANG
  LDA THX,Y
  LDX #0
  JSR ADD_SVEL
  LDY SANG
  LDA THY,Y
  LDX #2
  JSR ADD_SVEL
.us_sh:
  ; ---- shield and tractor beam (3 fuel units per frame)
  LDA JOYC
  AND #%00100010
  BEQ .us_gr
  LDA #$03
  JSR FUEL_USE
  BCS .us_r
  LDA #$01
  STA SHLD
  JSR TRACTOR
.us_gr:
  JSR GRAVITY
  LDA #$80                     ; at most 2.5 px per frame
  STA VLL
  LDA #$02
  STA VLH
  LDX #0
  JSR CLAMPV
  LDX #2
  JSR CLAMPV
  ; ---- two half steps, every one tested
  LDA SVXH
  CMP #$80
  ROR A
  STA VX2H
  LDA SVXL
  ROR A
  STA VX2L
  LDA SVYH
  CMP #$80
  ROR A
  STA VY2H
  LDA SVYL
  ROR A
  STA VY2L
  LDA #2
  STA HSUB
.us_mv:
  CLC
  LDA SHXL
  ADC VX2L
  STA SHXL
  LDA SHXH
  ADC VX2H
  STA SHXH
  CLC
  LDA SHYL
  ADC VY2L
  STA SHYL
  LDA SHYH
  ADC VY2H
  STA SHYH
  JSR SHIP_PLACE
  BCS .us_end
  DEC HSUB
  BNE .us_mv
  ; ---- fire on button 1
  LDA JOYC
  AND #%00010000
  TAX
  EOR FIRE_OLD
  AND JOYC                     ; just pressed
  STX FIRE_OLD
  AND #%00010000
  BEQ .us_end
  JMP SHIP_FIRE
.us_end:
  RTS

; checks after a half step; carry = 1 when the ship is gone (crash, exit, planet, dogfight)
SHIP_PLACE:
  LDA MODE
  BEQ .sp_sys
  CMP #2
  BEQ .sp_df
  LDA SHYH                     ; ---- planet: out of the field = take off
  CMP #FIELD_H
  BCS .sp_exit
  LDA MFLAGS
  AND #$02
  BEQ .sp_col
  LDA SHXH
  CMP #4
  BCC .sp_exit
  CMP #252
  BCS .sp_exit
.sp_col:
  JSR SHIP_TERRAIN
  BEQ .sp_ok
  JSR SHIP_DIE
  SEC
  RTS
.sp_exit:
  LDA #EV_EXIT
.sp_ev:
  STA EVT
  LDA #$03
  STA SHIPST
  SEC
  RTS
.sp_df:
  LDA SHYH
  JSR WRAP_Y
  STA SHYH
.sp_ok:
  CLC
  RTS
.sp_sys:
  LDA SHYH                     ; ---- solar system: wraps around
  JSR WRAP_Y
  STA SHYH
  LDA SHXH                     ; the death star
  SEC
  SBC STX
  JSR ABS_A
  CMP #7
  BCS .sp_pl
  LDA SHYH
  SEC
  SBC STY
  JSR ABS_A
  CMP #7
  BCS .sp_pl
  JSR SHIP_DIE
  SEC
  RTS
.sp_pl:
  LDA ENTLK                    ; the planets
  BNE .sp_ok
  LDX #4
.sp_pp:
  JSR PLANET_LEFT
  BCC .sp_pn
  LDA PL_R,X
  CLC
  ADC #2
  STA T0
  LDA SHXH
  SEC
  SBC PL_X,X
  JSR ABS_A
  CMP T0
  BCS .sp_pn
  LDA SHYH
  SEC
  SBC PL_Y,X
  JSR ABS_A
  CMP T0
  BCS .sp_pn
  STX PLN
  LDA #EV_ENTER
  BRA .sp_ev
.sp_pn:
  DEX
  BPL .sp_pp
  CLC
  RTS

; A <> 0 when an outline point of the ship touches something drawn
SHIP_TERRAIN:
  LDA SANG
  ASL A
  ADC SANG
  ASL A
  STA T7                       ; SANG * 6
  LDA #6
  STA T6
.st_l:
  LDX T7
  LDA SHXH
  CLC
  ADC COLPX,X
  STA PX
  LDA SHYH
  CLC
  ADC COLPY,X
  STA PY
  JSR PIXT
  BNE .st_r
  INC T7
  DEC T6
  BNE .st_l
  LDA #0
.st_r:
  RTS

SHIP_APPEAR:
  LDA #$00
  STA SHIPST
  STA SHXL
  STA SHYL
  STA ROTT
  LDA #$FF                     ; button held now does nothing
  STA FIRE_OLD
  RTS

SHIP_DIE:
  LDA #$01
  STA SHIPST
  LDA #80
  STA SHT
  LDA #$00
  STA THR
  STA SHLD
  STA BEAMD
  STA SND_THR
  LDA SHXH
  STA PCX
  LDA SHYH
  STA PCY
  JSR NEW_EXPL
  LDA #S_SHIP
  LDX #2
  JMP SFX_BOOM

; SVEL[X..X+1] += A (signed 8 bit).  X = 0 (vx), 2 (vy); the saucer: X = UFVXL - SVXL (+2)
ADD_SVEL:
  STA T1
  CLC
  ADC SVXL,X
  STA SVXL,X
  LDA T1
  BPL .av_p
  LDA #$FF
  BRA .av_h
.av_p:
  LDA #$00
.av_h:
  ADC SVXH,X
  STA SVXH,X
  RTS

; |SVEL[X..X+1]| <= VLH:VLL
CLAMPV:
  LDA SVXH,X
  BMI .cv_n
  LDA SVXL,X
  CMP VLL
  LDA SVXH,X
  SBC VLH
  BCC .cv_r
  LDA VLL
  STA SVXL,X
  LDA VLH
  STA SVXH,X
  RTS
.cv_n:
  LDA SVXL,X
  CLC
  ADC VLL
  LDA SVXH,X
  ADC VLH
  BCS .cv_r
  LDA #$00
  SEC
  SBC VLL
  STA SVXL,X
  LDA #$00
  SBC VLH
  STA SVXH,X
.cv_r:
  RTS

; gravity of the planet or of the death star
GRAVITY:
  LDA GMODE
  BEQ .gr_r
  CMP #1
  BNE .gr_pt
  LDA GRAV                     ; ---- down (up when negative)
  LDX GNEG
  BEQ .gr_d
  EOR #$FF
  INC A
.gr_d:
  LDX #2
  JMP ADD_SVEL
.gr_pt:
  LDA SHXH                     ; ---- towards a point
  STA AX0
  LDA SHYH
  STA AY0
  LDA GMODE
  CMP #2
  BNE .gr_star
  LDA GCX
  STA AX1
  LDA GCY
  STA AY1
  JSR ATAN
  LDX GNEG
  BEQ .gr_rw
  EOR #$08
.gr_rw:
  STA T6                       ; round world: twice the unit pull
  JSR .gr_add
  LDA T6
  BRA .gr_add
.gr_star:
  LDA STX
  STA AX1
  LDA STY
  STA AY1
  JSR ATAN
  STA T6
  LDA T4                       ; close to the star: twice as strong,
  CLC                          ; far from it: every other frame
  ADC T5
  CMP #24
  BCS .gr_far
  LDA T6
  JSR .gr_add
  BRA .gr_one
.gr_far:
  LDA FRAME_CNT
  LSR A
  BCC .gr_r
.gr_one:
  LDA T6
.gr_add:
  TAY
  PHY
  LDA GRX,Y
  LDX #0
  JSR ADD_SVEL
  PLY
  LDA GRY,Y
  LDX #2
  JMP ADD_SVEL
.gr_r:
  RTS

SHIP_FIRE:
  LDX #$03                     ; a free ship shot (0-3)
.sf_f:
  LDA B_T,X
  BEQ .sf_go
  DEX
  BPL .sf_f
  RTS
.sf_go:
  LDA #SHOT_LIFE
  STA B_T,X
  LDY SANG
  LDA SHXH
  CLC
  ADC NOSEX,Y
  STA B_XH,X
  LDA SHYH
  CLC
  ADC NOSEY,Y
  STA B_YH,X
  LDA #$80
  STA B_XL,X
  STA B_YL,X
  LDA BVX_L,Y
  STA B_VXL,X
  LDA BVX_H,Y
  STA B_VXH,X
  LDA BVY_L,Y
  STA B_VYL,X
  LDA BVY_H,Y
  STA B_VYH,X
  LDA #W_FIRE
  LDY SHXH
  JMP SFX_AT

; the beam takes a fuel cell under (or over) the ship
TRACTOR:
  LDA MODE
  CMP #1
  BNE .tr_r
  LDA #1
  STA BEAMD
  LDX NTANK
.tr_l:
  DEX
  BMI .tr_r
  LDA TK_ON,X
  BEQ .tr_l
  LDA TK_X,X
  CLC
  ADC #4
  SEC
  SBC SHXH
  JSR ABS_A
  CMP #12
  BCS .tr_l
  LDA TK_Y,X
  CLC
  ADC #4
  SEC
  SBC SHYH                     ; dy = cell - ship
  BMI .tr_up
  CMP #34
  BCS .tr_l
  BRA .tr_got
.tr_up:
  CMP #$DE                     ; up to 34 pixels above
  BCC .tr_l
  LDA #2
  STA BEAMD
.tr_got:
  STZ TK_ON,X
  LDY PLN
  LDA TANKM,Y
  ORA BITMASK,X
  STA TANKM,Y
  LDA TK_X,X
  STA SHX
  LDA TK_Y,X
  STA SHY
  LDA TK_O,X
  ASL A
  ASL A
  ASL A
  ADC #SH_TANK
  STA SHI
  LDA #1
  STA SHM
  JSR DRAW_SHAPE
  LDA #$25                     ; 2500 fuel units
  JSR FUEL_ADD
  LDA #W_FUEL
  LDX #2
  JMP SFX_WHISTLE
.tr_r:
  RTS

; A = hundreds of fuel units (BCD), up to 99999
FUEL_ADD:
  SED
  CLC
  ADC FUB
  STA FUB
  LDA FUC
  ADC #$00
  CLD
  CMP #$10
  BCC .fa_ok
  LDA #$99
  STA FUA
  STA FUB
  LDA #$09
.fa_ok:
  STA FUC
  RTS

; A = fuel units to burn (BCD); carry = 1 when the tank is empty (the ship explodes)
FUEL_USE:
  STA T0
  SED
  SEC
  LDA FUA
  SBC T0
  STA FUA
  LDA FUB
  SBC #$00
  STA FUB
  LDA FUC
  SBC #$00
  STA FUC
  CLD
  BCC .fu_out
  ORA FUB
  ORA FUA
  BEQ .fu_out
  CLC
  RTS
.fu_out:
  STZ FUA
  STZ FUB
  STZ FUC
  LDA #$01
  STA NOFUEL
  JSR SHIP_DIE
  SEC
  RTS


; ===============================================================
;  SHOTS
; ===============================================================
UPDATE_SHOTS:
  LDX #(NSHOT-1)
.ush_l:
  STX BI
  LDA B_T,X
  BEQ .ush_n
  DEC B_T,X
  BEQ .ush_n
  CPX #4
  BCS .ush_e
  JSR SHOT_STEP                ; ship shot: two half steps
  BCS .ush_n
  JSR PSHOT_HITS
  LDX BI
  LDA B_T,X
  BEQ .ush_n
  JSR SHOT_STEP
  BCS .ush_n
  JSR PSHOT_HITS
  BRA .ush_n
.ush_e:
  JSR SHOT_STEP                ; enemy shot: one step
  BCS .ush_n
  JSR ESHOT_HITS
.ush_n:
  LDX BI
  DEX
  BPL .ush_l
  RTS

; moves the shot BI; carry = 1 when it left the field
SHOT_STEP:
  LDX BI
  CLC
  LDA B_XL,X
  ADC B_VXL,X
  STA B_XL,X
  LDA B_XH,X
  ADC B_VXH,X
  STA B_XH,X
  CLC
  LDA B_YL,X
  ADC B_VYL,X
  STA B_YL,X
  LDA B_YH,X
  ADC B_VYH,X
  STA B_YH,X
  CMP #FIELD_H
  BCS .sst_k
  LDA MODE
  CMP #1
  BNE .sst_ok
  LDA MFLAGS
  AND #$02
  BEQ .sst_ok
  LDA B_XH,X
  CMP #2
  BCC .sst_k
  CMP #254
  BCS .sst_k
.sst_ok:
  CLC
  RTS
.sst_k:
  STZ B_T,X
  SEC
  RTS

; collisions of the ship shot BI
PSHOT_HITS:
  LDX BI
  LDA B_XH,X
  STA OBX
  LDA B_YH,X
  STA OBY
  LDA UFO_ON                   ; ---- saucer
  BEQ .ph_b
  LDA OBX
  SEC
  SBC UFX
  JSR ABS_A
  CMP #7
  BCS .ph_b
  LDA OBY
  SEC
  SBC UFY
  JSR ABS_A
  CMP #5
  BCS .ph_b
  STZ B_T,X
  LDA #$01
  JMP UFO_DESTROY
.ph_b:
  LDA MODE
  CMP #1
  BNE .ph_r
  LDX NBUNK                    ; ---- bunkers
.ph_bl:
  DEX
  BMI .ph_re
  LDA BK_ON,X
  BEQ .ph_bl
  LDA OBX
  SEC
  SBC BK_X,X
  CLC
  ADC #1
  CMP #10
  BCS .ph_bl
  LDA OBY
  SEC
  SBC BK_Y,X
  CLC
  ADC #1
  CMP #10
  BCS .ph_bl
  JSR BUNKER_HIT
  LDX BI
  STZ B_T,X
  RTS
.ph_re:
  LDA MFLAGS                   ; ---- reactor
  AND #$04
  BEQ .ph_t
  LDA OBX
  SEC
  SBC RX
  CLC
  ADC #1
  CMP #10
  BCS .ph_t
  LDA OBY
  SEC
  SBC RY
  CLC
  ADC #1
  CMP #10
  BCS .ph_t
  LDX BI
  STZ B_T,X
  LDA RHIT
  BNE .ph_r
  JMP REACTOR_HIT
.ph_t:
  LDA OBX                      ; ---- landscape
  STA PX
  LDA OBY
  STA PY
  JSR PIXT
  BEQ .ph_r
  LDX BI
  STZ B_T,X
.ph_r:
  RTS

; collisions of the enemy shot BI
ESHOT_HITS:
  LDX BI
  LDA SHIPST
  BNE .eh_t
  LDA B_XH,X
  SEC
  SBC SHXH
  JSR ABS_A
  CMP #5
  BCS .eh_t
  LDA B_YH,X
  SEC
  SBC SHYH
  JSR ABS_A
  CMP #5
  BCS .eh_t
  STZ B_T,X
  LDA SHLD                     ; the shield stops it
  BNE .eh_r
  JMP SHIP_DIE
.eh_t:
  LDA MODE
  CMP #1
  BNE .eh_r
  LDA B_XH,X
  STA PX
  LDA B_YH,X
  STA PY
  JSR PIXT
  BEQ .eh_r
  LDX BI
  STZ B_T,X
.eh_r:
  RTS


; ===============================================================
;  BUNKERS AND REACTOR
; ===============================================================
; the bunker X is destroyed
BUNKER_HIT:
  STZ BK_ON,X
  LDY PLN
  LDA BUNKM,Y
  ORA BITMASK,X
  STA BUNKM,Y
  LDA BK_X,X
  STA SHX
  CLC
  ADC #4
  STA PCX
  LDA BK_Y,X
  STA SHY
  CLC
  ADC #4
  STA PCY
  LDA BK_O,X
  ASL A
  ASL A
  ASL A
  STA SHI
  LDA #1
  STA SHM
  JSR DRAW_SHAPE
  JSR NEW_EXPL
  LDA #S_SMALL
  LDY PCX
  JSR BOOM_AT
  LDA #$50                     ; 250 points
  STA PTS_L
  LDA #$02
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  DEC BLEFT
  BNE .bh_r
  LDA MFLAGS                   ; (in the tunnel the reactor counts)
  AND #$04
  BNE .bh_r
  LDA #W_DONE
  LDX #2
  JSR SFX_WHISTLE
  LDA #<TXT_MISSION
  STA TP
  LDA #>TXT_MISSION
  STA TP+1
  LDA #240
  JMP SHOW_MSG
.bh_r:
  RTS

REACTOR_HIT:
  LDA #$01
  STA RHIT
  LDA RX
  CLC
  ADC #4
  STA PCX
  LDA RY
  CLC
  ADC #4
  STA PCY
  JSR NEW_EXPL
  LDA #$00                     ; 500 points
  STA PTS_L
  LDA #$05
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  LDA #W_REACT
  LDX #2
  JSR SFX_WHISTLE
  LDA #<TXT_ESCAPE
  STA TP
  LDA #>TXT_ESCAPE
  STA TP+1
  LDA #180
  JMP SHOW_MSG

; one bunker that sees the ship fires at it
UPDATE_BUNKERS:
  LDA MODE
  CMP #1
  BNE .ub_r
  LDA SHIPST
  BNE .ub_r
  LDA BLEFT
  BEQ .ub_r
  DEC BFT
  BNE .ub_r
  LDA BFI
  STA BFT
  JSR NEXT_RND                 ; from a bunker at random
  LDA RND
  AND #$07
  STA T6
  LDA NBUNK
  STA T7
.ub_l:
  LDX T6
  CPX NBUNK
  BCC .ub_k
  LDX #0
  STX T6
.ub_k:
  LDA BK_ON,X
  BEQ .ub_n
  JSR SEES_SHIP
  BCS .ub_fire
.ub_n:
  INC T6
  DEC T7
  BNE .ub_l
.ub_r:
  RTS
.ub_fire:
  LDY BK_O,X                   ; from the gun
  LDA BK_X,X
  CLC
  ADC BGX,Y
  STA AX0
  LDA BK_Y,X
  CLC
  ADC BGY,Y
  STA AY0
  LDA SHXH
  STA AX1
  LDA SHYH
  STA AY1
  JSR ATAN
  STA T6
  JSR NEXT_RND                 ; not always right on target
  LDA RND
  AND #$03
  TAY
  LDA T6
  CLC
  ADC SPREAD,Y
  AND #$0F
  ; fall into ENEMY_SHOT

; enemy shot from (AX0, AY0) in the direction A
ENEMY_SHOT:
  TAY
  LDX #4
.es_f:
  LDA B_T,X
  BEQ .es_go
  INX
  CPX #NSHOT
  BNE .es_f
  RTS
.es_go:
  LDA #100
  STA B_T,X
  LDA AX0
  STA B_XH,X
  LDA AY0
  STA B_YH,X
  LDA #$80
  STA B_XL,X
  STA B_YL,X
  LDA EVX_L,Y
  STA B_VXL,X
  LDA EVX_H,Y
  STA B_VXH,X
  LDA EVY_L,Y
  STA B_VYL,X
  LDA EVY_H,Y
  STA B_VYH,X
  LDA #W_EFIRE
  LDY AX0
  JMP SFX_AT

; carry = 1 when the ship is on the open side of the bunker X (X kept)
SEES_SHIP:
  LDA BK_O,X
  BEQ .se_up
  CMP #1
  BEQ .se_dn
  CMP #2
  BEQ .se_lf
  LDA SHXH                     ; right
  SEC
  SBC BK_X,X
  BMI .se_no
  CMP #10
  RTS
.se_up:
  LDA BK_Y,X
  CMP SHYH
  RTS
.se_dn:
  LDA SHYH
  SEC
  SBC #9
  CMP BK_Y,X
  RTS
.se_lf:
  LDA SHXH
  SEC
  SBC BK_X,X
  BPL .se_no
  SEC
  RTS
.se_no:
  CLC
  RTS


; ===============================================================
;  SAUCER
; ===============================================================
UPDATE_UFO:
  LDA UFO_ON
  BNE .uu_fly
  LDA MODE                     ; ---- a new one now and then (not in the dogfight)
  CMP #2
  BEQ .uu_r
  LDA SHIPST
  BNE .uu_r
  LDA FRAME_CNT
  AND #$03
  BNE .uu_r
  DEC UFSPN
  BNE .uu_r
  LDA #$01                     ; from the top edge
  STA UFO_ON
  JSR NEXT_RND
  LDA RND
  STA UFX
  LDA #2
  STA UFY
  STZ UFXL
  STZ UFYL
  STZ UFVXL
  STZ UFVXH
  STZ UFVYL
  STZ UFVYH
  LDA #60
  STA UFT
.uu_r:
  RTS
.uu_fly:
  LDA SHIPST                   ; ---- it steers towards the ship
  BNE .uu_mv
  LDA UFX
  STA AX0
  LDA UFY
  STA AY0
  LDA SHXH
  STA AX1
  LDA SHYH
  STA AY1
  JSR ATAN
  TAY
  PHY
  LDA GRX,Y
  LDX #(UFVXL-SVXL)
  JSR ADD_SVEL
  PLY
  LDA GRY,Y
  LDX #(UFVYL-SVXL)
  JSR ADD_SVEL
  LDA #$00                     ; 1 px per frame, 1.5 in the dogfight
  STA VLL
  LDA MODE
  CMP #2
  BNE .uu_v
  LDA #$80
  STA VLL
.uu_v:
  LDA #$01
  STA VLH
  LDX #(UFVXL-SVXL)
  JSR CLAMPV
  LDX #(UFVYL-SVXL)
  JSR CLAMPV
.uu_mv:
  CLC
  LDA UFXL
  ADC UFVXL
  STA UFXL
  LDA UFX
  ADC UFVXH
  STA UFX
  CLC
  LDA UFYL
  ADC UFVYL
  STA UFYL
  LDA UFY
  ADC UFVYH
  LDX MODE
  CPX #1
  BEQ .uu_pl
  JSR WRAP_Y
  STA UFY
  BRA .uu_f
.uu_pl:
  STA UFY                      ; planet: it leaves by the edges, it crashes on the landscape
  CMP #FIELD_H
  BCS .uu_gone
  STA PY
  LDA UFX
  STA PX
  JSR PIXT
  BEQ .uu_f
  LDA #$00
  JMP UFO_DESTROY
.uu_f:
  LDA MODE                     ; ---- fire (not in the solar system)
  BEQ .uu_hit
  LDA SHIPST
  BNE .uu_hit
  DEC UFT
  BNE .uu_hit
  LDA KDIFF                    ; every 70 - 2k frames (40 in the dogfight)
  ASL A
  STA T0
  LDA #70
  SEC
  SBC T0
  LDX MODE
  CPX #2
  BNE .uu_t
  LDA #40
.uu_t:
  STA UFT
  LDA UFX
  STA AX0
  LDA UFY
  STA AY0
  LDA SHXH
  STA AX1
  LDA SHYH
  STA AY1
  JSR ATAN
  JSR ENEMY_SHOT
.uu_hit:
  LDA SHIPST                   ; ---- against the ship
  BNE .uu_end
  LDA SHXH
  SEC
  SBC UFX
  JSR ABS_A
  CMP #9
  BCS .uu_end
  LDA SHYH
  SEC
  SBC UFY
  JSR ABS_A
  CMP #8
  BCS .uu_end
  LDA MODE
  BNE .uu_ram
  STZ UFO_ON                   ; solar system: dogfight
  LDA #EV_FIGHT
  STA EVT
  LDA #$03
  STA SHIPST
  RTS
.uu_ram:
  JSR SHIP_DIE                 ; rammed: the shield does not help
  LDA #$00
  JMP UFO_DESTROY
.uu_end:
  RTS
.uu_gone:
  STZ UFO_ON
  JMP UFO_TIMER

; A = 1: the player gets the points
UFO_DESTROY:
  BEQ .ud_np
  LDA #$00                     ; 100 points
  STA PTS_L
  LDA #$01
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
.ud_np:
  LDA UFX
  STA PCX
  LDA UFY
  STA PCY
  JSR NEW_EXPL
  LDA #S_MED
  LDY UFX
  JSR BOOM_AT
  STZ UFO_ON
  LDA MODE
  CMP #2
  BNE UFO_TIMER
  LDA SHIPST                   ; dogfight won: back in a second
  BNE UFO_TIMER
  LDA #60
  STA DFW
UFO_TIMER:                     ; next saucer: 7-11 s in the system, 10-14 s (less later) on a planet
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC #100
  LDX MODE
  BEQ .ut_s
  ADC #50
  SEC
  SBC KDIFF
  SBC KDIFF
  SBC KDIFF
.ut_s:
  STA UFSPN
  RTS


; ===============================================================
;  TIMERS: messages, bonus, reactor clock, colours, alarms
; ===============================================================
UPDATE_TIMERS:
  LDA ENTLK
  BEQ .ut_e
  DEC ENTLK
.ut_e:
  LDA MSGT                     ; ---- the message goes away
  BEQ .ut_m
  CMP #1
  BNE .ut_md
  LDA FRAME_CNT                ; (not with the death star or the fuel)
  AND #$03
  BEQ .ut_m
.ut_md:
  DEC MSGT
  BNE .ut_m
  LDA MSGR
  JSR RESTORE_ROW
.ut_m:
  LDA #0                       ; ---- sound requests
  LDX SHLD
  BEQ .ut_s1
  LDA #1
  BRA .ut_s2
.ut_s1:
  LDX UFO_ON
  BEQ .ut_s2
  LDA #2
.ut_s2:
  STA SND_UFO
  LDA THR
  STA SND_THR
  LDA FRAME_CNT                ; ---- fuel on the HUD (not in the frame of the death star)
  AND #$07
  CMP #$04
  BNE .ut_f
  JSR DRAW_FUEL
.ut_f:
  LDA MODE
  BEQ .ut_sys
  CMP #2
  BEQ .ut_df
  JSR PLANET_TIMERS
  BRA .ut_al
.ut_sys:
  LDA FRAME_CNT                ; ---- the death star flashes
  AND #$07
  BNE .ut_al
  JSR STAR_PULSE
  BRA .ut_al
.ut_df:
  LDA DFW                      ; ---- dogfight won
  BEQ .ut_al
  DEC DFW
  BNE .ut_al
  LDA SHIPST
  BNE .ut_al
  LDA #EV_WON
  STA EVT
  LDA #$03
  STA SHIPST
.ut_al:
  ; fall into UPDATE_ALARM

; reactor alarm (faster after the shot), low fuel beeps
UPDATE_ALARM:
  LDA SHIPST
  BNE .ua_r
  LDA MODE
  CMP #1
  BNE .ua_f
  LDA MFLAGS
  AND #$04
  BEQ .ua_f
  LDY #16
  LDA RHIT
  BEQ .ua_go
  LDY #8
  BRA .ua_go
.ua_f:
  LDA FUC                      ; under 1000 units
  BNE .ua_r
  LDA FUB
  CMP #$10
  BCS .ua_r
  LDY #30
.ua_go:
  STY T0
  INC ALT
  LDA ALT
  CMP T0
  BCC .ua_r
  STZ ALT
  LDA BEAT_N
  EOR #$01
  STA BEAT_N
  INC A
  STA SND_BEAT
.ua_r:
  RTS

; planet: the bonus drops; red planet: the clock, the reactor flashes
PLANET_TIMERS:
  LDA MFLAGS
  AND #$04
  BNE .pt_rc
  LDA BLEFT                    ; ---- planet: the bonus drops (10 every 30 frames)
  BEQ .pt_r
  DEC PBT
  BNE .pt_r
  LDA #30
  STA PBT
  SED
  SEC
  LDA PBL
  SBC #$10
  STA PBL
  LDA PBH
  SBC #$00
  STA PBH
  CLD
  BCS .pt_bd
  STZ PBL
  STZ PBH
.pt_bd:
  JSR DRAW_SLOT
  RTS
.pt_rc:
  LDA SHIPST                   ; ---- reactor clock
  BNE .pt_r
  DEC RTF
  BNE .pt_rp
  LDA #60
  STA RTF
  SED
  LDA RTIME
  SEC
  SBC #$01
  STA RTIME
  CLD
  JSR DRAW_SLOT
  LDA RTIME
  BNE .pt_rp
  JSR SHIP_DIE                 ; time is up: the reactor blows up
  LDA #S_REACT
  LDX #2
  JMP SFX_BOOM
.pt_rp:
  LDA RHIT                     ; the reactor shot flashes
  BEQ .pt_r
  LDA FRAME_CNT
  AND #$03
  BNE .pt_r
  LDA RX
  STA SHX
  LDA RY
  STA SHY
  LDA #SH_REACTOR
  STA SHI
  LDA #2
  STA SHM
  LDA FRAME_CNT
  AND #$04
  BEQ .pt_rc2
  LDA #$81
  BRA .pt_rc3
.pt_rc2:
  LDA #$F1
.pt_rc3:
  STA SHCOL
  JSR DRAW_SHAPE
  RTS
.pt_r:
  RTS

; the death star: bands of red and yellow that move
STAR_PULSE:
  INC SPAN
  LDA STY
  SEC
  SBC #11
  STA T6                       ; first line
  LDA #23
  STA T7
  LDA STX                      ; first and last byte column
  SEC
  SBC #11
  AND #$F8
  STA T0
  LDA STX
  CLC
  ADC #11
  AND #$F8
  STA T5
.sp_l:
  LDA T6
  CMP #FIELD_H
  BCS .sp_n
  LSR A
  EOR SPAN
  AND #$01
  TAX
  LDA STARC,X
  STA T3
  LDA T0
  STA T4
  LDA T6
  LSR A
  LSR A
  LSR A
  CLC
  ADC #$62                     ; colour table, write: $40 | $20 | (row + 2)
  STA T2
.sp_c:
  LDA T6
  AND #$07
  ORA T4
  STA VREG
  LDA T2
  STA VREG
  LDA T3
  STA VDATA
  LDA T4
  CMP T5
  BEQ .sp_n
  CLC
  ADC #8
  STA T4
  BRA .sp_c
.sp_n:
  INC T6
  DEC T7
  BNE .sp_l
  RTS


; ===============================================================
;  SCORE AND HUD (written in the VRAM only)
; ===============================================================
; PTS_L / PTS_M / PTS_H (BCD) to the player in the game; extra ship every 10000
ADD_SCORE:
  LDX CURP
  SED
  CLC
  LDA SCA,X
  ADC PTS_L
  STA SCA,X
  LDA SCB,X
  ADC PTS_M
  STA SCB,X
  LDA SCC,X
  ADC PTS_H
  STA SCC,X
  CLD
.as_x:
  LDA SCC,X
  CMP NXL,X
  BCC .as_d
  LDA LIVES,X                  ; extra ship
  CMP #9
  BCS .as_n
  INC LIVES,X
.as_n:
  SED
  LDA NXL,X
  CLC
  ADC #$01
  STA NXL,X
  CLD
  LDA #W_LIFE
  PHX
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
  PLX
  BRA .as_x
.as_d:
  JMP DRAW_SCORES

DRAW_HUD:
  JSR CLEAR_HUD
  JSR DRAW_HI
  JSR DRAW_SCORES
  JSR DRAW_LIVES
  LDA #<TXT_FUEL
  STA TP
  LDA #>TXT_FUEL
  STA TP+1
  JSR DRAW_TEXT
  JSR DRAW_FUEL
  ; fall into DRAW_SLOT

; right part of row 1: system, bonus, reactor clock or dogfight
DRAW_SLOT:
  LDA #21
  STA CELLC
  LDA #1
  STA CELLR
  LDA #$B1
  STA TCOL
  LDA MODE
  BEQ .dsl_sys
  CMP #2
  BEQ .dsl_df
  LDA MFLAGS
  AND #$04
  BNE .dsl_tm
  LDA #<STR_BONUS
  LDX #>STR_BONUS
  JSR PUT_STR
  LDA PBH
  JSR PUT_BCD
  LDA PBL
  JSR PUT_BCD
  LDA #$20
  JMP PUT_CHAR
.dsl_tm:
  LDA #<STR_TIME
  LDX #>STR_TIME
  JSR PUT_STR
  LDA RTIME
  JMP PUT_BCD
.dsl_df:
  LDA #<STR_FIGHT
  LDX #>STR_FIGHT
  JMP PUT_STR
.dsl_sys:
  LDA #<STR_SYS
  LDX #>STR_SYS
  JSR PUT_STR
  LDA UNIV
  CLC
  ADC #$31
  JSR PUT_CHAR
  INC CELLC
  LDA #$2D
  JSR PUT_CHAR
  INC CELLC
  LDA SYSN
  CLC
  ADC #$31
  JSR PUT_CHAR
  INC CELLC
  LDA #<STR_SP2
  LDX #>STR_SP2
  JMP PUT_STR

DRAW_HI:
  LDA #$F1
  STA TCOL
  STZ CELLR
  LDA #13
  STA CELLC
  LDA HIC
  JSR PUT_BCD
  LDA HIB
  JSR PUT_BCD
  LDA HIA
  JMP PUT_BCD

; fuel of the player in the game (red when low)
DRAW_FUEL:
  LDA #14
  STA CELLC
  LDA #1
  STA CELLR
  LDA #$71
  LDX FUC
  BNE .df_c
  LDX FUB
  CPX #$10
  BCS .df_c
  LDA #$81
.df_c:
  STA TCOL
  LDA FUC
  AND #$0F
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  LDA FUB
  JSR PUT_BCD
  LDA FUA
  JMP PUT_BCD

; one '^' per ship of the player in the game (up to 6)
DRAW_LIVES:
  LDA #1
  STA CELLR
  STA CELLC
  LDA #$F1
  STA TCOL
  LDX CURP
  LDA LIVES,X
  STA T6
  LDA #6
  STA T7
.dl_c:
  LDA #$20
  LDY T6
  BEQ .dl_s
  DEC T6
  LDA #$5E
.dl_s:
  JSR PUT_CHAR
  INC CELLC
  DEC T7
  BNE .dl_c
  RTS

DRAW_SCORES:
  STZ CELLR
  LDX #$00
.ds_p:
  CPX NPL
  BCS .ds_ret
  LDA #$E1                     ; grey, white for the player in the game
  CPX CURP
  BNE .ds_c
  LDA #$F1
.ds_c:
  STA TCOL
  LDA SCORE_COL,X
  STA CELLC
  PHX
  LDA SCC,X
  JSR PUT_BCD
  PLX
  PHX
  LDA SCB,X
  JSR PUT_BCD
  PLX
  PHX
  LDA SCA,X
  JSR PUT_BCD
  PLX
  INX
  BRA .ds_p
.ds_ret:
  RTS


; ===============================================================
;  TEXT IN THE VRAM
; ===============================================================
; A = ASCII code ($20-$5F), in (CELLC,CELLR) with colour TCOL
PUT_CHAR:
  SEC
  SBC #$20
  AND #$3F
  STA T4
  LDA #$00
  STA T5
  ASL T4
  ROL T5
  ASL T4
  ROL T5
  ASL T4
  ROL T5
  LDA T4
  CLC
  ADC #<FONT
  STA PTR
  LDA T5
  ADC #>FONT
  STA PTR+1
  LDA CELLC
  ASL A
  ASL A
  ASL A
  STA T6
  STA VREG
  LDA CELLR
  ORA #$40
  STA VREG
  LDY #$00
.pc_p:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #$08
  BNE .pc_p
  LDA T6
  STA VREG
  LDA CELLR
  ORA #$60
  STA VREG
  LDA TCOL
  LDY #$08
.pc_c:
  STA VDATA
  DEY
  BNE .pc_c
  RTS

; A = BCD byte: two digits, CELLC moves on by 2
PUT_BCD:
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

; A / X = string ending with 0, from (CELLC, CELLR); CELLC moves on
PUT_STR:
  STA TP
  STX TP+1
  LDY #$00
.pst_l:
  LDA (TP),Y
  BEQ .pst_r
  STY TYV
  JSR PUT_CHAR
  INC CELLC
  LDY TYV
  INY
  BRA .pst_l
.pst_r:
  RTS

; record: row, column, colour (fg), characters..., 0   (end of the list: row = $FF)
DRAW_TEXT:
  LDY #$00
  LDA (TP),Y
  CMP #$FF
  BEQ .dt_end
  STA CELLR
  INY
  LDA (TP),Y
  STA CELLC
  INY
  LDA (TP),Y
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA TCOL
  INY
.dt_ch:
  LDA (TP),Y
  BEQ .dt_next
  STY TYV
  JSR PUT_CHAR
  LDY TYV
  INC CELLC
  INY
  BRA .dt_ch
.dt_next:
  INY
  TYA
  CLC
  ADC TP
  STA TP
  BCC DRAW_TEXT
  INC TP+1
  BRA DRAW_TEXT
.dt_end:
  RTS

; message (one text record at TP) for A frames; the row comes back from the shadow
SHOW_MSG:
  PHA
  LDA MSGT                     ; an old message goes first
  BEQ .sm_n
  LDA MSGR
  JSR RESTORE_ROW
.sm_n:
  LDA (TP)
  STA MSGR
  PLA
  STA MSGT
  JMP DRAW_TEXT

; big words: row, column, n, letter ids... (end of the list: row = $FF)
DRAW_BIGWORDS:
  LDY #$00
  LDA (TP),Y
  CMP #$FF
  BEQ .bw_end
  STA CELLR
  INY
  LDA (TP),Y
  STA CELLC
  INY
  LDA (TP),Y
  STA T7                       ; number of letters
  INY
.bw_l:
  LDA (TP),Y
  STY TYV
  JSR BIGLET
  LDY TYV
  INC CELLC
  INC CELLC
  INY
  DEC T7
  BNE .bw_l
  TYA
  CLC
  ADC TP
  STA TP
  BCC DRAW_BIGWORDS
  INC TP+1
  BRA DRAW_BIGWORDS
.bw_end:
  RTS

BIGLET:                        ; A = letter, in (CELLC,CELLR), 2x2 tiles
  STA T4
  LDA #$00
  STA T5
  LDY #$06
.bg_sh:
  ASL T4
  ROL T5
  DEY
  BNE .bg_sh
  LDA T4
  CLC
  ADC #<BIGFONT
  STA PTR
  LDA T5
  ADC #>BIGFONT
  STA PTR+1
  JSR TILE_V
  INC CELLC
  JSR TILE_V
  DEC CELLC
  INC CELLR
  JSR TILE_V
  INC CELLC
  JSR TILE_V
  DEC CELLC
  DEC CELLR
  RTS

TILE_V:                        ; 8 pattern + 8 colour bytes at PTR -> cell (CELLC, CELLR); PTR += 16
  LDA CELLC
  ASL A
  ASL A
  ASL A
  STA T6
  STA VREG
  LDA CELLR
  ORA #$40
  STA VREG
  LDY #$00
.tv_p:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #$08
  BNE .tv_p
  LDA T6
  STA VREG
  LDA CELLR
  ORA #$60
  STA VREG
.tv_c:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #$10
  BNE .tv_c
  LDA PTR
  CLC
  ADC #$10
  STA PTR
  BCC .tv_r
  INC PTR+1
.tv_r:
  RTS


; ===============================================================
;  PLAYFIELD: copy in RAM, lines, circles, shapes
; ===============================================================
; pixel (PX, PY) of the playfield in the shadow, colour PCOL (X changed)
PLOT_SH:
  LDA PY
  CMP #FIELD_H
  BCS .ps_r
  LSR A
  LSR A
  LSR A
  CLC
  ADC #>SHP0
  STA SPTR+1
  LDA PY
  AND #$07
  STA SPTR
  LDA PX
  AND #$F8
  ORA SPTR
  STA SPTR
  LDA PX
  AND #$07
  TAX
  LDA BITMASK,X
  ORA (SPTR)
  STA (SPTR)
  LDA SPTR+1
  CLC
  ADC #(>SHC0->SHP0)
  STA SPTR+1
  LDA PCOL
  STA (SPTR)
.ps_r:
  RTS

; A <> 0 when the pixel (PX, PY) of the playfield is lit (X changed)
PIXT:
  LDA PY
  CMP #FIELD_H
  BCS .pt_no
  LSR A
  LSR A
  LSR A
  CLC
  ADC #>SHP0
  STA SPTR+1
  LDA PY
  AND #$07
  STA SPTR
  LDA PX
  AND #$F8
  ORA SPTR
  STA SPTR
  LDA PX
  AND #$07
  TAX
  LDA BITMASK,X
  AND (SPTR)
  RTS
.pt_no:
  LDA #$00
  RTS

; line (LX0,LY0) -> (LX1,LY1) in the shadow, colour PCOL; LTHK = 1: 2 pixels tall
DRAW_LINE:
  LDA #$01
  STA LSX
  LDA LX1
  SEC
  SBC LX0
  BCS .dl_xp
  EOR #$FF
  ADC #$01
  LDX #$FF
  STX LSX
.dl_xp:
  STA LDXV
  LDA #$01
  STA LSY
  LDA LY1
  SEC
  SBC LY0
  BCS .dl_yp
  EOR #$FF
  ADC #$01
  LDX #$FF
  STX LSY
.dl_yp:
  STA LDYV
  JSR LPLOT
  LDA LDXV
  CMP LDYV
  BCC .dl_ym
  STA LCNT                     ; ---- x is the long side
  LSR A
  STA LERR
.dl_xl:
  LDA LCNT
  BEQ .dl_ret
  LDA LX0
  CLC
  ADC LSX
  STA LX0
  LDA LERR
  CLC
  ADC LDYV
  BCS .dl_xs
  CMP LDXV
  BCC .dl_xn
.dl_xs:
  SBC LDXV
  STA LERR
  LDA LY0
  CLC
  ADC LSY
  STA LY0
  BRA .dl_xd
.dl_xn:
  STA LERR
.dl_xd:
  JSR LPLOT
  DEC LCNT
  BRA .dl_xl
.dl_ym:
  LDA LDYV                     ; ---- y is the long side
  STA LCNT
  LSR A
  STA LERR
.dl_yl:
  LDA LCNT
  BEQ .dl_ret
  LDA LY0
  CLC
  ADC LSY
  STA LY0
  LDA LERR
  CLC
  ADC LDXV
  BCS .dl_ys
  CMP LDYV
  BCC .dl_yn
.dl_ys:
  SBC LDYV
  STA LERR
  LDA LX0
  CLC
  ADC LSX
  STA LX0
  BRA .dl_yd
.dl_yn:
  STA LERR
.dl_yd:
  JSR LPLOT
  DEC LCNT
  BRA .dl_yl
.dl_ret:
  RTS

LPLOT:
  LDA LX0
  STA PX
  LDA LY0
  STA PY
  JSR PLOT_SH
  LDA LTHK
  BEQ .lp_r
  INC PY
  JMP PLOT_SH
.lp_r:
  RTS

; circle of radius CR around (LX0, LY0), colour PCOL, 1 pixel
CIRCLE:
  LDA CR
  STA CXX
  STZ CYY
  LDA #$01
  SEC
  SBC CR
  STA CERR
.ci_l:
  LDA CXX
  CMP CYY
  BCC .ci_r
  JSR CPLOT8
  INC CYY
  LDA CERR
  BMI .ci_neg
  DEC CXX
  LDA CYY                      ; err += 2 (y - x) + 1
  SEC
  SBC CXX
  ASL A
  SEC
  ADC CERR
  STA CERR
  BRA .ci_l
.ci_neg:
  LDA CYY                      ; err += 2 y + 1
  ASL A
  SEC
  ADC CERR
  STA CERR
  BRA .ci_l
.ci_r:
  RTS

CPLOT8:                        ; the 8 symmetric points of (CXX, CYY)
  LDA CXX
  STA T6
  LDA CYY
  STA T7
  JSR CPLOT4
  LDA CYY
  STA T6
  LDA CXX
  STA T7
CPLOT4:
  LDA LX0
  CLC
  ADC T6
  STA PX
  LDA LY0
  CLC
  ADC T7
  STA PY
  JSR PLOT_SH
  LDA LY0
  SEC
  SBC T7
  STA PY
  JSR PLOT_SH
  LDA LX0
  SEC
  SBC T6
  STA PX
  JSR PLOT_SH
  LDA LY0
  CLC
  ADC T7
  STA PY
  JMP PLOT_SH

; 8x8 shape SHI (offset in SHAPES) at (SHX multiple of 8, SHY), colour SHCOL
; SHM: 0 = drawn in the shadow, 1 = erased (shadow + VRAM, colour of the landscape),
;      2 = colour only, in the VRAM
DRAW_SHAPE:
  LDA #8
  STA SHN
  LDA SHY
  STA SHYY
.dsh_l:
  LDA SHYY
  CMP #FIELD_H
  BCS .dsh_n
  AND #$07
  ORA SHX
  STA SPTR
  LDA SHYY
  LSR A
  LSR A
  LSR A
  STA T1                       ; row of the playfield
  CLC
  ADC #>SHP0
  STA SPTR+1
  LDX SHI
  LDA SHM
  BEQ .dsh_draw
  CMP #2
  BEQ .dsh_col
  LDA SHAPES,X                 ; ---- erase
  EOR #$FF
  AND (SPTR)
  STA (SPTR)
  STA T2
  LDA SPTR
  STA VREG
  LDA T1
  CLC
  ADC #$42                     ; pattern table, write: $40 | (row + 2)
  STA VREG
  LDA T2
  STA VDATA
  LDA SPTR+1
  CLC
  ADC #(>SHC0->SHP0)
  STA SPTR+1
  LDA TCOLR
  STA (SPTR)
  STA T2
  BRA .dsh_vc
.dsh_draw:
  LDA SHAPES,X                 ; ---- draw
  ORA (SPTR)
  STA (SPTR)
  LDA SPTR+1
  CLC
  ADC #(>SHC0->SHP0)
  STA SPTR+1
  LDA SHCOL
  STA (SPTR)
  BRA .dsh_n
.dsh_col:
  LDA SHCOL                    ; ---- colour only
  STA T2
.dsh_vc:
  LDA SPTR
  STA VREG
  LDA T1
  CLC
  ADC #$62                     ; colour table, write
  STA VREG
  LDA T2
  STA VDATA
.dsh_n:
  INC SHI
  INC SHYY
  DEC SHN
  BNE .dsh_l
  RTS

; empty shadow: no pixels, white on black
CLEAR_SH:
  STZ SPTR
  LDA #>SHP0
  STA SPTR+1
  LDX #22
  LDY #$00
  TYA
.cs_p:
  STA (SPTR),Y
  INY
  BNE .cs_p
  INC SPTR+1
  DEX
  BNE .cs_p
  LDX #22
  LDA #$F1
.cs_c:
  STA (SPTR),Y
  INY
  BNE .cs_c
  INC SPTR+1
  DEX
  BNE .cs_c
  RTS

; shadow -> VRAM rows 2-23 (patterns, then colours)
UPLOAD_FIELD:
  LDA #>SHP0
  LDX #$02
  JSR UP22
  LDA #>SHC0
  LDX #$22
UP22:
  STA SPTR+1
  STZ SPTR
  STZ VREG
  TXA
  ORA #$40
  STA VREG
  LDX #22
  LDY #$00
.up_l:
  LDA (SPTR),Y
  STA VDATA
  INY
  BNE .up_l
  INC SPTR+1
  DEX
  BNE .up_l
  RTS

; screen row A (2-23) back from the shadow
RESTORE_ROW:
  STA T1
  SEC
  SBC #2
  CLC
  ADC #>SHP0
  STA SPTR+1
  STZ SPTR
  STZ VREG
  LDA T1
  ORA #$40
  STA VREG
  LDY #$00
.rr_p:
  LDA (SPTR),Y
  STA VDATA
  INY
  BNE .rr_p
  LDA SPTR+1
  CLC
  ADC #(>SHC0->SHP0)
  STA SPTR+1
  STZ VREG
  LDA T1
  ORA #$60
  STA VREG
.rr_c:
  LDA (SPTR),Y
  STA VDATA
  INY
  BNE .rr_c
  RTS

; HUD rows 0-1: no pixels, white on black
CLEAR_HUD:
  STZ VREG
  LDA #$40
  STA VREG
  LDX #2
  LDY #$00
  TYA
.ch_p:
  STA VDATA
  INY
  BNE .ch_p
  DEX
  BNE .ch_p
  STZ VREG
  LDA #$60
  STA VREG
  LDX #2
  LDA #$F1
.ch_c:
  STA VDATA
  INY
  BNE .ch_c
  DEX
  BNE .ch_c
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
  INY
  BNE .in_b
  DEX
  BNE .in_p
  RTS

; interrupt and display off, no sprites (for the long drawings)
SCREEN_OFF:
  JSR VDP_INT_OFF
  LDA #$86                     ; R1: 16K + display OFF + INT OFF
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR HIDE_SPRITES
  JMP COPY_SAT

SCREEN_ON:
  JMP VDP_INT_ON               ; R1 = $E6: display and interrupt on


; ===============================================================
;  SMALL HELPERS
; ===============================================================
ABS_A:                         ; A = |A| (signed)
  BPL .ab_r
  EOR #$FF
  CLC
  ADC #1
.ab_r:
  RTS

; A = Y (high byte after the add) -> back into 0-175
WRAP_Y:
  CMP #FIELD_H
  BCC .wy_ok
  CMP #(256-40)                ; just above the top: from below
  BCS .wy_up
  SEC
  SBC #FIELD_H
  RTS
.wy_up:
  CLC
  ADC #FIELD_H
.wy_ok:
  RTS

; A = direction 0-15 (0 = up, clockwise) from (AX0, AY0) to (AX1, AY1)
; T2 / T3 = dx / dy halved (signed), T4 / T5 = their sizes
ATAN:
  LDA AX1
  LSR A
  STA T2
  LDA AX0
  LSR A
  STA T3
  LDA T2
  SEC
  SBC T3
  STA T2
  LDA AY1
  LSR A
  STA T3
  LDA AY0
  LSR A
  STA T4
  LDA T3
  SEC
  SBC T4
  STA T3
  LDA T2
  JSR ABS_A
  STA T4
  LDA T3
  JSR ABS_A
  STA T5
  JSR FRAC19                   ; a < 0.19 b: almost vertical
  CMP T4
  BEQ .at_1
  BCS .at_k0
.at_1:
  LDA T5
  JSR FRAC66                   ; a < 0.66 b
  CMP T4
  BEQ .at_4
  BCS .at_k1
.at_4:
  LDA T4
  JSR FRAC19                   ; b < 0.19 a: almost horizontal
  CMP T5
  BEQ .at_3
  BCS .at_k4
.at_3:
  LDA T4
  JSR FRAC66                   ; b < 0.66 a
  CMP T5
  BEQ .at_k2
  BCS .at_k3
.at_k2:
  LDA #2
  BRA .at_q
.at_k0:
  LDA #0
  BRA .at_q
.at_k1:
  LDA #1
  BRA .at_q
.at_k3:
  LDA #3
  BRA .at_q
.at_k4:
  LDA #4
.at_q:
  STA T6                       ; k in the quarter
  LDA T2
  BMI .at_l
  LDA T3
  BMI .at_ur
  LDA #8                       ; right, down: 8 - k
  SEC
  SBC T6
  RTS
.at_ur:
  LDA T6                       ; right, up: k
  RTS
.at_l:
  LDA T3
  BMI .at_ul
  LDA #8                       ; left, down: 8 + k
  CLC
  ADC T6
  RTS
.at_ul:
  LDA #16                      ; left, up: 16 - k
  SEC
  SBC T6
  AND #$0F
  RTS

FRAC19:                        ; A = A * 0.1875
  LSR A
  LSR A
  LSR A
  STA T7
  LSR A
  CLC
  ADC T7
  RTS

FRAC66:                        ; A = A * 0.656
  LSR A
  STA T7
  LSR A
  LSR A
  PHA
  CLC
  ADC T7
  STA T7
  PLA
  LSR A
  LSR A
  CLC
  ADC T7
  RTS


; ===============================================================
;  EXPLOSIONS (sprites)
; ===============================================================
NEW_EXPL:                      ; at (PCX, PCY)
  LDX EXI
  LDA #$01
  STA E_T,X
  LDA PCX
  STA E_X,X
  LDA PCY
  STA E_Y,X
  INX
  CPX #NEXPL
  BCC .ne_s
  LDX #$00
.ne_s:
  STX EXI
  RTS

UPDATE_EXPL:
  LDX #(NEXPL-1)
.ue_l:
  LDA E_T,X
  BEQ .ue_n
  INC E_T,X
  LDA E_T,X
  CMP #16
  BCC .ue_n
  STZ E_T,X
.ue_n:
  DEX
  BPL .ue_l
  RTS


; ===============================================================
;  SPRITES AND NMI
;  0 ship, 1 flame, 2 shield, 3 beam, 4 saucer, 5-12 shots, 13-15 explosions
; ===============================================================
BUILD_SAT:
  LDA SHIPST                   ; ---- ship, flame, shield, beam
  BNE .bs_noship
  LDA SHXH
  STA SPX
  LDA SHYH
  STA SPY
  LDA SANG
  ASL A
  ASL A
  STA SPN
  LDA #SHIP_COL
  STA SPC
  LDX #0
  JSR SET_SPR
  LDA THR                      ; the flame flickers
  BEQ .bs_nofl
  LDA FRAME_CNT
  AND #$02
  BEQ .bs_nofl
  LDA SPN
  CLC
  ADC #64
  STA SPN
  LDA #$0B
  STA SPC
  LDX #4
  JSR SET_SPR
  BRA .bs_shl
.bs_nofl:
  LDA #HIDE_Y
  STA SAT_BUFFER+4
.bs_shl:
  LDA SHLD
  BEQ .bs_nosh
  LDA #128
  STA SPN
  LDA #$0F
  STA SPC
  LDX #8
  JSR SET_SPR
  LDA BEAMD
  BEQ .bs_nobm
  LDY #132
  LDA SHYH
  CLC
  ADC #13
  LDX BEAMD
  CPX #1
  BEQ .bs_bm
  LDY #136
  LDA SHYH
  SEC
  SBC #13
.bs_bm:
  STA SPY
  STY SPN
  LDA #$03
  STA SPC
  LDX #12
  JSR SET_SPR
  BRA .bs_ufo
.bs_noship:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
.bs_nosh:
  LDA #HIDE_Y
  STA SAT_BUFFER+8
.bs_nobm:
  LDA #HIDE_Y
  STA SAT_BUFFER+12
.bs_ufo:
  LDA UFO_ON                   ; ---- saucer
  BEQ .bs_noufo
  LDA UFX
  STA SPX
  LDA UFY
  STA SPY
  LDA #140
  STA SPN
  LDA #$08
  STA SPC
  LDX #16
  JSR SET_SPR
  BRA .bs_shots
.bs_noufo:
  LDA #HIDE_Y
  STA SAT_BUFFER+16
.bs_shots:
  LDX #$00                     ; ---- shots (2x2 pixels)
  LDY #20
.bs_sl:
  LDA B_T,X
  BEQ .bs_sh
  LDA B_YH,X
  CLC
  ADC #15
  STA SAT_BUFFER,Y
  LDA B_XH,X
  STA SAT_BUFFER+1,Y
  LDA #144
  STA SAT_BUFFER+2,Y
  LDA #$0F
  CPX #4
  BCC .bs_sc
  LDA #$09
.bs_sc:
  STA SAT_BUFFER+3,Y
  BRA .bs_sn
.bs_sh:
  LDA #HIDE_Y
  STA SAT_BUFFER,Y
.bs_sn:
  INY
  INY
  INY
  INY
  INX
  CPX #NSHOT
  BNE .bs_sl
  LDA #$00                     ; ---- explosions
  STA T6
.bs_el:
  LDX T6
  LDA E_T,X
  BEQ .bs_eh
  LSR A
  LSR A
  ASL A
  ASL A
  CLC
  ADC #148
  STA SPN
  LDA E_X,X
  STA SPX
  LDA E_Y,X
  STA SPY
  LDA #$0B
  STA SPC
  LDA T6
  ASL A
  ASL A
  CLC
  ADC #52
  TAX
  JSR SET_SPR
  BRA .bs_en
.bs_eh:
  LDA T6
  ASL A
  ASL A
  TAX
  LDA #HIDE_Y
  STA SAT_BUFFER+52,X
.bs_en:
  INC T6
  LDA T6
  CMP #NEXPL
  BNE .bs_el
  RTS

; 16x16 sprite centred on (SPX, SPY of the playfield), pattern SPN, colour SPC;
; X = offset in SAT_BUFFER. Near the left edge the early clock bit is used.
SET_SPR:
  LDA SPY
  CLC
  ADC #7                       ; + 16 (HUD) - 8 (centre) - 1 (SAT)
  STA SAT_BUFFER,X
  LDA SPN
  STA SAT_BUFFER+2,X
  LDA SPX
  SEC
  SBC #8
  BCC .ss_ec
  STA SAT_BUFFER+1,X
  LDA SPC
  STA SAT_BUFFER+3,X
  RTS
.ss_ec:
  CLC
  ADC #32
  STA SAT_BUFFER+1,X
  LDA SPC
  ORA #$80
  STA SAT_BUFFER+3,X
  RTS

HIDE_SPRITES:
  LDX #60
  LDA #HIDE_Y
.hs_l:
  STA SAT_BUFFER,X
  DEX
  DEX
  DEX
  DEX
  BPL .hs_l
  RTS

; NMI (vblank): only point that writes the Sprite Attribute Table, then the sound.
NMI_TASK:
  INC FRAME_CNT
  LDA VREG                ; read VDP status (clears F and the byte latch)
  JSR COPY_SAT
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

COPY_SAT:
  LDA #<VDP_SPRITE_ATT_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_ATT_BASE)
  STA VREG
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX #65                 ; 16 sprites x 4 bytes + Y=$D0 of the 17th entry
  BNE .copy_sat
  RTS

SAT_BUFFER:
  .byte HIDE_Y,0,0,$07, HIDE_Y,0,64,$0B, HIDE_Y,0,128,$0F, HIDE_Y,0,132,$03
  .byte HIDE_Y,0,140,$08, HIDE_Y,0,144,$0F, HIDE_Y,0,144,$0F, HIDE_Y,0,144,$0F
  .byte HIDE_Y,0,144,$0F, HIDE_Y,0,144,$09, HIDE_Y,0,144,$09, HIDE_Y,0,144,$09
  .byte HIDE_Y,0,144,$09, HIDE_Y,0,148,$0B, HIDE_Y,0,148,$0B, HIDE_Y,0,148,$0B
  .byte $D0


; ===============================================================
;  SOUND: effects only
;  per chip: A = tone effects / shield buzz / saucer hum, B = noise
;  (explosions, thrust), C = alarm / thump of the explosions
; ===============================================================
SND_TICK:
  PHA
  PHX
  PHY
  INC SND_PH
  LDA SND_CMD
  BEQ .st_run
  STZ SND_CMD
  JSR SND_GAME_MODE
  LDA #$FF
  STA BEAT_POS
.st_run:
  LDA SND_BEAT                  ; new alarm note
  BEQ .st_nb
  DEC A
  STA BEAT_NOTE
  STZ SND_BEAT
  STZ BEAT_POS
.st_nb:
  JSR SFX_TICK
  LDA BEAT_POS
  BMI .st_fl
  INC BEAT_POS
  LDA BEAT_POS
  CMP #BEAT_LEN
  BCC .st_fl
  LDA #$FF
  STA BEAT_POS
.st_fl:
  JSR AY_FLUSH
  PLY
  PLX
  PLA
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
  ; ---- channel A: tone effect, otherwise shield buzz or saucer hum
  LDA WH_ID,X
  BEQ .sf_loop
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
.sf_loop:
  LDA SND_UFO
  BEQ .sf_noise
  CMP #$02
  BEQ .sf_ufo
  LDA SND_PH                    ; shield / tractor: a fast buzz, period 70-94
  AND #$03
  ASL A
  ASL A
  ASL A
  CLC
  ADC #70
  BRA .sf_sv
.sf_ufo:
  LDA SND_PH                    ; saucer: slow wobble, period 104-149
  LSR A
  AND #$1F
  JSR TRIANGLE
  STA SN1
  ASL A
  CLC
  ADC SN1
  CLC
  ADC #104
.sf_sv:
  STA SH_L,Y
  LDA #$00
  STA SH_L+1,Y
  LDA #$09
  STA SH_L+8,Y
.sf_noise:
  ; ---- channels B and C: explosion, otherwise thrust and alarm
  LDX SND_T1
  LDA EX_ID,X
  BEQ .sf_thr
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
.sf_thr:
  LDA SND_THR
  BEQ .sf_beat
  LDA SND_RND
  AND #$03
  CLC
  ADC #$0E
  STA SH_L+6,Y                  ; thrust: low noise
  LDA #$0B
  STA SH_L+9,Y
.sf_beat:
  LDA BEAT_POS
  BMI .sf_next
  TAX
  LDA BEAT_ENV,X
  STA SH_L+10,Y
  LDX BEAT_NOTE
  LDA BEAT_TL,X
  STA SH_L+4,Y
  LDA BEAT_TH,X
  STA SH_L+5,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_done
  JMP .sf_chip
.sf_done:
  RTS

TRIANGLE:                       ; A = 0-31 -> 0-15-0
  CMP #$10
  BCC .tr_r
  EOR #$1F
.tr_r:
  RTS

; A = tone effect, Y = X of the object: on its side
SFX_AT:
  LDX #$00
  CPY #$80
  BCC .sa_l
  INX
.sa_l:
  JMP SFX_WHISTLE

; A = explosion, Y = X of the object: on its side
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
STARC:      .byte $81,$B1              ; death star bands: red, yellow
SPK_X0:     .byte 0,4,6,4,0,$FC,$FA,$FC         ; spikes of the death star: from...
SPK_Y0:     .byte $FA,$FC,0,4,6,4,0,$FC
SPK_X1:     .byte 0,8,11,8,0,$F8,$F5,$F8        ; ...to
SPK_Y1:     .byte $F5,$F8,0,8,11,8,0,$F8
BONUS1:     .byte $20,$40,$60,$80,$90  ; planet bonus in the first system (hundreds, BCD)
SUP_M:      .byte $00,$20,$60,$20,$00  ; super bonus by first planet: 0, 2000, 6000, 12000, 20000
SUP_H:      .byte $00,$00,$00,$01,$02
SCORE_COL:  .byte 1,25                 ; score of player 1 / 2
BGX:        .byte 4,4,$FE,9            ; gun of a bunker by side (up, down, left, right)
BGY:        .byte $FE,9,4,4
SPREAD:     .byte $FF,0,0,1            ; aim error of the bunkers
UNIV_TL:    .byte <TXT_U0,<TXT_U1,<TXT_U2,<TXT_U3
UNIV_TH:    .byte >TXT_U0,>TXT_U1,>TXT_U2,>TXT_U3

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_TITLE:
  .byte 5,9,8,"BUNKER    250",0
  .byte 6,9,8,"SAUCER    100",0
  .byte 7,9,11,"REACTOR   500",0
  .byte 8,9,5,"FUEL CELL 2500",0
  .byte 10,2,14,"LEFT/RIGHT ROTATE  UP THRUST",0
  .byte 11,2,14,"BTN 1 FIRE  BTN 2 SHIELD/BEAM",0
  .byte 13,6,15,"BUTTON 1 = 1 PLAYER",0
  .byte 14,6,15,"BUTTON 2 = 2 PLAYERS",0
  .byte $FF
TXT_PRESS:   .byte 15,9,15,"PRESS A BUTTON",0,$FF
TXT_FUEL:    .byte 1,9,14,"FUEL",0,$FF
TXT_P1:      .byte 3,12,11,"PLAYER 1",0,$FF
TXT_P2:      .byte 3,12,11,"PLAYER 2",0,$FF
TXT_NOFUEL:  .byte 3,10,9,"OUT OF FUEL",0,$FF
TXT_NEWSYS:  .byte 3,8,11,"NEW SOLAR SYSTEM",0,$FF
TXT_U0:      .byte 3,8,11,"POSITIVE GRAVITY",0,$FF
TXT_U1:      .byte 3,8,11,"NEGATIVE GRAVITY",0,$FF
TXT_U2:      .byte 3,6,11,"INVISIBLE LANDSCAPE",0,$FF
TXT_U3:      .byte 3,6,11,"NEGATIVE + INVISIBLE",0,$FF
TXT_MISSION: .byte 3,8,11,"MISSION COMPLETE",0,$FF
TXT_ESCAPE:  .byte 3,12,9,"ESCAPE!",0,$FF
STR_BONUS:   .byte "BONUS ",0
STR_TIME:    .byte "TIME     ",0
STR_FIGHT:   .byte "DOGFIGHT   ",0
STR_SYS:     .byte "SYSTEM ",0
STR_SP2:     .byte " ",0
; big words: row, column, number of letters, letters (G R A V I T M E O)
TITLE_BIG:
  .byte 2,8,8,0,1,2,3,4,5,2,1    ; GRAVITAR
  .byte $FF
OVER_BIG:
  .byte 8,12,4,0,2,6,7           ; GAME
  .byte 11,12,4,8,3,7,1          ; OVER
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
; big letters (16x16, 4 tiles each, 8 pattern + 8 colour bytes): G R A V I T M E O
BIGFONT:
  ; G
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$F8,$F8,$00,$00,$00,$00,$00,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $00,$78,$78,$18,$18,$F8,$F8,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; R
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $E0,$80,$80,$60,$60,$18,$18,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; A
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$80,$80,$60,$60,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $18,$F8,$F8,$18,$18,$18,$18,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; V
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $18,$06,$06,$06,$06,$01,$01,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $18,$60,$60,$60,$60,$80,$80,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; I
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$E0,$E0,$80,$80,$80,$80,$80,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $80,$80,$80,$80,$80,$E0,$E0,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; T
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$F8,$F8,$80,$80,$80,$80,$80,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; M
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$18,$18,$78,$78,$98,$98,$98,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $98,$18,$18,$18,$18,$18,$18,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; E
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$F8,$F8,$00,$00,$00,$00,$E0,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$71,$71,$51,$51,$41,$41,$41,$41
  ; O
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$51,$51,$51,$71,$71,$71,$71,$71
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$71,$71,$51,$51,$41,$41,$41,$41
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$71,$71,$51,$51,$41,$41,$41,$41

; sprites 16x16: 16 ship angles, 16 flame angles, shield, beam down, beam up, saucer, shot, 4 explosion frames
SPR_PAGES = 6
SPRITES:
  .byte $00,$00,$00,$00,$01,$01,$02,$02,$04,$04,$08,$0B,$1C,$10,$00,$00
  .byte $00,$00,$80,$80,$40,$40,$20,$20,$10,$10,$88,$68,$1C,$04,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$06,$08,$10,$27,$78,$00,$00,$00,$00,$00
  .byte $00,$00,$20,$60,$A0,$20,$20,$20,$20,$20,$A0,$A0,$60,$60,$20,$00
  .byte $00,$00,$00,$00,$00,$03,$0C,$30,$F0,$0E,$02,$01,$01,$01,$00,$00
  .byte $00,$00,$00,$18,$68,$90,$10,$10,$20,$20,$20,$40,$40,$40,$80,$80
  .byte $00,$00,$00,$00,$00,$7F,$30,$0C,$02,$02,$02,$02,$05,$06,$04,$00
  .byte $00,$00,$00,$00,$00,$FC,$08,$10,$20,$40,$40,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$18,$0E,$09,$04,$04,$02,$04,$04,$09,$0E,$18,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$60,$18,$06,$18,$60,$80,$00,$00,$00,$00
  .byte $00,$04,$06,$05,$04,$02,$02,$02,$0C,$30,$7F,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$40,$20,$10,$08,$FC,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$01,$02,$06,$38,$C0,$38,$07,$00,$00,$00,$00,$00
  .byte $80,$80,$40,$40,$40,$20,$20,$20,$10,$10,$10,$E8,$18,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$70,$2F,$10,$08,$06,$01,$00,$00,$00,$00,$00
  .byte $00,$20,$60,$60,$A0,$A0,$20,$20,$20,$20,$20,$A0,$60,$20,$00,$00
  .byte $00,$00,$00,$20,$18,$16,$09,$08,$04,$04,$02,$02,$01,$01,$00,$00
  .byte $00,$00,$04,$0C,$38,$48,$90,$10,$20,$20,$20,$40,$40,$80,$80,$00
  .byte $00,$04,$06,$06,$05,$05,$04,$04,$04,$04,$04,$05,$06,$04,$00,$00
  .byte $00,$00,$00,$00,$00,$1E,$E4,$08,$10,$60,$80,$00,$00,$00,$00,$00
  .byte $01,$01,$02,$02,$02,$04,$04,$04,$08,$08,$09,$16,$18,$00,$00,$00
  .byte $00,$00,$80,$80,$80,$40,$70,$0F,$0C,$30,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$02,$04,$08,$10,$3F,$00,$00,$00,$00,$00
  .byte $00,$20,$60,$A0,$40,$40,$40,$40,$30,$0C,$FE,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$06,$18,$30,$0C,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$18,$68,$90,$10,$20,$20,$10,$10,$C8,$38,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$3F,$10,$08,$04,$02,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$FE,$0C,$30,$40,$40,$40,$20,$A0,$60,$20,$00
  .byte $00,$00,$00,$18,$17,$08,$08,$04,$04,$04,$02,$02,$01,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$E0,$1C,$03,$1C,$60,$40,$40,$80,$80,$80,$80
  .byte $00,$00,$04,$06,$05,$04,$04,$04,$04,$04,$05,$05,$06,$06,$04,$00
  .byte $00,$00,$00,$00,$00,$80,$60,$10,$08,$F4,$0E,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$01,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$40,$40,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$04,$05,$0A,$0C,$08
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$10,$13,$2C,$30,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$10,$20,$5C,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$0C,$30,$C0,$30,$0C,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$E0,$5C,$20,$10,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$30,$2C,$13,$10,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $08,$0C,$0A,$05,$04,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$02,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$40,$40,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $10,$30,$50,$A0,$20,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0C,$34,$C8,$08,$10,$10,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$3A,$04,$08,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$1C,$03,$03,$0C,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$10,$08,$04,$3A,$07,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$10,$10,$08,$C8,$34,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$A0,$50,$30,$10
  .byte $07,$1C,$30,$60,$40,$C0,$80,$80,$80,$80,$C0,$40,$60,$30,$1C,$07
  .byte $E0,$38,$0C,$06,$02,$03,$01,$01,$01,$01,$03,$02,$06,$0C,$38,$E0
  .byte $01,$02,$00,$04,$04,$05,$08,$08,$00,$15,$10,$00,$20,$55,$00,$40
  .byte $40,$C0,$00,$20,$20,$50,$10,$10,$00,$58,$04,$00,$04,$56,$00,$01
  .byte $40,$00,$55,$20,$00,$10,$15,$00,$08,$08,$05,$04,$04,$00,$02,$01
  .byte $01,$00,$56,$04,$00,$04,$58,$00,$10,$10,$50,$20,$20,$00,$C0,$40
  .byte $00,$00,$02,$02,$01,$07,$18,$20,$7F,$20,$10,$0F,$00,$00,$00,$00
  .byte $00,$00,$20,$20,$40,$F0,$0C,$02,$FF,$02,$04,$F8,$00,$00,$00,$00
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$02,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$04,$08,$04,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$40,$00,$00,$20,$00,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$04,$00,$18,$20,$08,$00,$00,$00,$02,$00,$00
  .byte $00,$00,$00,$00,$00,$60,$00,$00,$00,$00,$10,$00,$40,$40,$00,$00
  .byte $00,$00,$00,$00,$0C,$00,$00,$30,$80,$00,$10,$00,$00,$00,$00,$02
  .byte $00,$00,$00,$00,$20,$20,$00,$00,$00,$00,$00,$04,$00,$00,$20,$00
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

; ship outline points tested against the landscape: 6 per angle (dx, dy from the centre)
COLPX:
  .byte $00,$05,$FB,$00,$02,$FD,$02,$02,$F9,$FF,$02,$FD
  .byte $04,$00,$F8,$FE,$02,$FE,$05,$FD,$F9,$FE,$01,$FF
  .byte $06,$FB,$FB,$FE,$00,$00,$05,$F9,$FD,$FE,$FF,$01
  .byte $04,$F8,$00,$FE,$FE,$02,$02,$F9,$02,$FF,$FD,$02
  .byte $00,$FA,$05,$00,$FD,$02,$FD,$FD,$06,$00,$FD,$02
  .byte $FB,$FF,$07,$01,$FD,$01,$FA,$02,$06,$01,$FE,$00
  .byte $FA,$05,$05,$02,$FF,$FF,$FA,$06,$02,$01,$00,$FE
  .byte $FB,$07,$00,$01,$01,$FD,$FD,$06,$FD,$00,$02,$FD
COLPY:
  .byte $FA,$05,$05,$02,$FF,$FF,$FA,$06,$02,$01,$00,$FE
  .byte $FB,$07,$00,$01,$01,$FD,$FD,$06,$FD,$00,$02,$FD
  .byte $00,$05,$FB,$00,$02,$FD,$02,$02,$F9,$FF,$02,$FD
  .byte $04,$00,$F8,$FE,$02,$FE,$05,$FD,$F9,$FE,$01,$FF
  .byte $06,$FB,$FA,$FE,$00,$00,$05,$F9,$FD,$FE,$FF,$01
  .byte $04,$F8,$FF,$FE,$FE,$02,$02,$F9,$02,$FF,$FD,$02
  .byte $00,$FA,$05,$00,$FD,$02,$FD,$FD,$06,$00,$FD,$02
  .byte $FB,$FF,$07,$01,$FD,$01,$FA,$02,$06,$01,$FE,$00

; bitmap shapes 8x8: bunker up / down / left / right, fuel up / down, reactor, home base
SHAPES:
  .byte $18,$18,$3C,$66,$FF,$A5,$FF,$FF
  .byte $FF,$FF,$A5,$FF,$66,$3C,$18,$18
  .byte $0F,$1B,$3F,$EB,$EB,$3F,$1B,$0F
  .byte $F0,$D8,$FC,$D7,$D7,$FC,$D8,$F0
  .byte $7E,$81,$BD,$A1,$B9,$A1,$81,$FF
  .byte $FF,$81,$A1,$B9,$A1,$BD,$81,$7E
  .byte $FF,$81,$BD,$A5,$A5,$BD,$81,$FF
  .byte $00,$24,$42,$00,$00,$42,$24,$00
SH_BUNKER = 0
SH_TANK = 32
SH_REACTOR = 48
SH_HOME = 56

; planet maps: flags (1 centre gravity, 2 no wrap, 4 reactor), gravity, colour, centre x, y;
; polylines (n, x0,y0 ...), 0; bunkers (n, col, top, side); fuel cells (n, col, top, side); reactor col, top
MAP0:
  .byte $00,$03,$03,$80,$64,$0C,$00,$96,$1E,$96,$30,$80,$48,$80,$5A,$96
  .byte $7C,$96,$88,$78,$A4,$78,$B0,$91,$D6,$91,$E8,$87,$FF,$96,$00,$02
  .byte $07,$78,$00,$12,$70,$00,$02,$0C,$8E,$00,$18,$89,$00
MAP1:
  .byte $00,$03,$0D,$80,$64,$0A,$00,$A5,$18,$A5,$28,$8C,$40,$8C,$50,$A5
  .byte $B0,$A5,$C0,$82,$D8,$82,$E8,$A5,$FF,$A5,$07,$6E,$5A,$96,$5A,$A0
  .byte $64,$8E,$6C,$76,$6C,$64,$64,$6E,$5A,$00,$04,$06,$84,$00,$0E,$52
  .byte $00,$10,$6E,$01,$19,$7A,$00,$02,$0B,$9D,$00,$13,$9D,$00
MAP2:
  .byte $00,$04,$0B,$80,$64,$0D,$00,$78,$14,$78,$1C,$A0,$34,$A0,$3C,$78
  .byte $60,$78,$68,$A5,$88,$A5,$90,$78,$A0,$78,$A8,$96,$F0,$96,$FF,$78
  .byte $07,$B0,$38,$F4,$38,$F4,$42,$EC,$48,$B8,$48,$B0,$42,$B0,$38,$00
  .byte $06,$04,$98,$00,$09,$70,$00,$0E,$9D,$00,$19,$8E,$00,$18,$4A,$01
  .byte $1C,$4A,$01,$03,$05,$98,$00,$0F,$9D,$00,$16,$8E,$00
MAP3:
  .byte $03,$03,$07,$80,$64,$09,$68,$34,$97,$34,$AF,$4C,$AF,$7C,$97,$94
  .byte $68,$94,$50,$7C,$50,$4C,$68,$34,$00,$08,$0D,$2C,$00,$12,$2C,$00
  .byte $0D,$96,$01,$12,$96,$01,$09,$58,$02,$09,$6A,$02,$16,$58,$03,$16
  .byte $6A,$03,$04,$0F,$2C,$00,$10,$2C,$00,$0F,$96,$01,$10,$96,$01
MAP4:
  .byte $00,$03,$02,$80,$64,$0C,$00,$64,$28,$64,$38,$50,$58,$50,$5F,$60
  .byte $5F,$A8,$A0,$A8,$A0,$60,$B0,$50,$D0,$50,$E0,$64,$FF,$64,$00,$05
  .byte $08,$48,$00,$0C,$78,$03,$13,$8C,$02,$10,$A0,$00,$17,$48,$00,$03
  .byte $02,$5C,$00,$0E,$A0,$00,$1D,$5C,$00
MAP5:
  .byte $00,$04,$0F,$80,$64,$08,$00,$A0,$40,$A0,$50,$8C,$78,$8C,$88,$A5
  .byte $D0,$A5,$E0,$96,$FF,$A0,$0A,$28,$3C,$C8,$3C,$C8,$50,$A8,$64,$88
  .byte $64,$68,$50,$48,$50,$38,$64,$28,$64,$28,$3C,$00,$06,$03,$98,$00
  .byte $0C,$84,$00,$14,$9D,$00,$06,$66,$01,$12,$66,$01,$0A,$34,$00,$03
  .byte $01,$98,$00,$0E,$84,$00,$17,$9D,$00
MAP6:
  .byte $00,$04,$0A,$80,$64,$0B,$00,$A8,$20,$A8,$2C,$8C,$38,$A8,$70,$A8
  .byte $7C,$84,$88,$A8,$C8,$A8,$D4,$8C,$E0,$A8,$FF,$A8,$07,$30,$50,$68
  .byte $50,$68,$5C,$60,$64,$38,$64,$30,$5C,$30,$50,$07,$98,$60,$D0,$60
  .byte $D0,$6C,$C8,$74,$A0,$74,$98,$6C,$98,$60,$00,$06,$07,$48,$00,$09
  .byte $66,$01,$14,$58,$00,$17,$76,$01,$02,$A0,$00,$14,$A0,$00,$04,$0B
  .byte $48,$00,$08,$A0,$00,$17,$58,$00,$1D,$A0,$00
MAP7:
  .byte $00,$04,$0E,$80,$64,$02,$00,$96,$FF,$96,$06,$40,$78,$50,$60,$70
  .byte $4C,$90,$4C,$B0,$60,$C0,$78,$00,$07,$02,$8E,$00,$0E,$44,$00,$0F
  .byte $4E,$01,$11,$4E,$01,$0B,$8E,$00,$14,$8E,$00,$1D,$8E,$00,$03,$05
  .byte $8E,$00,$0E,$8E,$00,$1A,$8E,$00
MAP8:
  .byte $00,$05,$0D,$80,$64,$0D,$00,$8C,$18,$64,$28,$64,$38,$A0,$50,$A0
  .byte $68,$5A,$80,$5A,$90,$96,$A8,$96,$C0,$50,$D8,$50,$E8,$8C,$FF,$8C
  .byte $05,$38,$28,$60,$28,$60,$32,$38,$32,$38,$28,$00,$07,$03,$5C,$00
  .byte $07,$98,$00,$0D,$52,$00,$13,$8E,$00,$19,$48,$00,$09,$34,$01,$1E
  .byte $84,$00,$03,$08,$98,$00,$14,$8E,$00,$0F,$52,$00
MAP9:
  .byte $03,$04,$07,$80,$68,$09,$60,$30,$9F,$30,$BF,$50,$BF,$80,$9F,$A0
  .byte $60,$A0,$40,$80,$40,$50,$60,$30,$00,$08,$0C,$28,$00,$10,$28,$00
  .byte $13,$28,$00,$0C,$A2,$01,$13,$A2,$01,$07,$60,$02,$18,$60,$03,$18
  .byte $72,$03,$03,$0E,$28,$00,$0F,$A2,$01,$10,$A2,$01
MAP10:
  .byte $00,$05,$03,$80,$64,$02,$00,$A8,$FF,$A8,$05,$18,$70,$60,$70,$60
  .byte $7A,$18,$7A,$18,$70,$05,$88,$80,$D8,$80,$D8,$8A,$88,$8A,$88,$80
  .byte $05,$88,$40,$E8,$40,$E8,$48,$88,$48,$88,$40,$00,$08,$04,$68,$00
  .byte $0A,$68,$00,$07,$7C,$01,$13,$78,$00,$18,$8C,$01,$12,$4A,$01,$1A
  .byte $4A,$01,$1C,$A0,$00,$04,$02,$A0,$00,$10,$A0,$00,$17,$A0,$00,$07
  .byte $68,$00
MAP11:
  .byte $04,$03,$09,$80,$64,$0E,$72,$00,$72,$1A,$1A,$1A,$1A,$68,$C4,$68
  .byte $C4,$7E,$46,$7E,$46,$9A,$E0,$9A,$E0,$4C,$36,$4C,$36,$36,$8E,$36
  .byte $8E,$00,$00,$03,$08,$1C,$01,$0D,$60,$00,$13,$92,$00,$00,$0A,$88
MAP_LO:
  .byte <MAP0,<MAP1,<MAP2,<MAP3,<MAP4,<MAP5,<MAP6,<MAP7,<MAP8,<MAP9,<MAP10,<MAP11
MAP_HI:
  .byte >MAP0,>MAP1,>MAP2,>MAP3,>MAP4,>MAP5,>MAP6,>MAP7,>MAP8,>MAP9,>MAP10,>MAP11

; solar systems: death star, home base; 5 planets each (the 5th is the red planet)
SYS_SX:
  .byte $96,$80,$60
SYS_SY:
  .byte $4A,$58,$50
SYS_HX:
  .byte $54,$2C,$DC
SYS_HY:
  .byte $6C,$96,$60
SYS_PX:
  .byte $DE,$D4,$34,$28,$10,$2C,$D2,$DA,$80,$78,$2C,$B0,$B4,$00,$1C
SYS_PY:
  .byte $1C,$92,$96,$20,$5C,$24,$22,$8E,$14,$A0,$96,$1C,$9C,$00,$1C
SYS_PR:
  .byte $07,$08,$09,$0A,$08,$08,$09,$09,$08,$08,$09,$0A,$09,$00,$08
SYS_PM:
  .byte $00,$01,$02,$03,$0B,$04,$05,$06,$07,$0B,$08,$09,$0A,$FF,$0B
SYS_PC:
  .byte $03,$0D,$0B,$07,$09,$02,$0F,$0A,$0E,$09,$0D,$07,$03,$00,$09
SYS_DONE:   .byte $0F,$0F,$07       ; planets to complete in every system

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$21,$25,$2B,$32,$3D,$4E,$70,$78,$81,$8B,$98,$A7,$B9,$D0,$78
  .byte $78,$78,$78,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$2D,$2E,$30,$32,$35,$37,$3A,$3D,$40,$44,$48,$4D,$52
  .byte $58,$5F,$67,$71,$7D,$8C,$9F,$B8,$DA,$0C,$5B,$5B,$00,$CB,$A8,$8F
  .byte $7D,$6F,$63,$5A,$52,$4C,$47,$42,$3E,$3A,$37,$34,$31,$2F,$2D,$24
  .byte $24,$24,$24,$00,$00,$00,$24,$24,$24,$24,$00,$00,$00,$24,$24,$24
  .byte $24,$50,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$3F,$35,$35,$35,$35,$35
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$45,$47,$6E,$71
  .byte $4C,$4E,$7B,$7E,$54,$57,$8B,$90,$5F,$62,$A0,$A7,$6C,$70,$BD,$C6
  .byte $9F,$9F,$9F,$9F,$9F,$9F,$78,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F
  .byte $5F,$5F,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$5F,$5F,$5F,$5F
  .byte $5F,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00
WH_VOL:
  .byte $00,$0D,$0C,$0A,$09,$07,$06,$0B,$0A,$09,$08,$07,$06,$05,$04,$0D
  .byte $0C,$0C,$0B,$0D,$0C,$0C,$0B,$0D,$0C,$0C,$0B,$0D,$0C,$0B,$0A,$09
  .byte $08,$07,$06,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$08,$08,$08,$09,$09
  .byte $09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0D
  .byte $0C,$0B,$0A,$00,$00,$00,$0D,$0C,$0B,$0A,$00,$00,$00,$0D,$0C,$0B
  .byte $0A,$0D,$0D,$0C,$0C,$0B,$0D,$0D,$0C,$0C,$0B,$0D,$0D,$0C,$0C,$0B
  .byte $0D,$0C,$0C,$0B,$0A,$09,$09,$08,$07,$06,$06,$05,$0D,$0D,$0D,$0D
  .byte $0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09
  .byte $0C,$0C,$0B,$0B,$0A,$0A,$0C,$0C,$0B,$0B,$0A,$0A,$0C,$0C,$0B,$0B
  .byte $0A,$0A,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$0B,$0B,$0A,$0A
  .byte $09,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05
  .byte $05
WH_START:
  .byte $00,$01,$07,$0F,$23,$3B,$4F,$61,$7C,$90
WH_LEN:
  .byte $00,$06,$08,$14,$18,$14,$12,$1B,$14,$31
W_FIRE = 1
W_EFIRE = 2
W_FUEL = 3
W_ENTER = 4
W_EXIT = 5
W_LIFE = 6
W_DONE = 7
W_REACT = 8
W_START = 9

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0D,$0C,$0B,$0B,$0A,$09,$09,$08,$07,$07,$06,$05
  .byte $05,$04,$03,$03,$02,$01,$01,$0F,$0F,$0E,$0E,$0D,$0D,$0C,$0C,$0B
  .byte $0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03
  .byte $03,$02,$02,$01,$01,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E
  .byte $0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B
  .byte $0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08
  .byte $07,$07,$07,$07,$07,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$04
  .byte $04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$01
  .byte $01,$01,$01,$01,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E
  .byte $0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$02,$02
EX_NP:
  .byte $00,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09
  .byte $09,$0A,$0A,$0A,$0A,$0B,$0B,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15,$15,$15,$15,$15
  .byte $15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16
  .byte $16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17,$17,$17,$17,$17
  .byte $17,$17,$17,$17,$17,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A
  .byte $1A,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$1C,$1D,$1D,$1D,$1D,$1D,$1D,$1D,$1D,$1D,$1D,$1D
  .byte $1D,$1D,$1D,$1D,$1D,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F
  .byte $1F,$1F,$1F,$1F,$1F,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20
EX_VC:
  .byte $00,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08
  .byte $08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01,$01,$00
  .byte $00,$00,$00,$00,$00,$0D,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A
  .byte $0A,$09,$09,$09,$08,$08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$05
  .byte $04,$04,$04,$03,$03,$03,$02,$02,$02,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$09,$08
  .byte $08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04
  .byte $04,$04,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00
EX_TL:
  .byte $00,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87
  .byte $87,$87,$87,$87,$87,$87,$87,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1B,$1B,$1B
EX_TH:
  .byte $00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06
EX_START:
  .byte $00,$01,$17,$35,$85
EX_LEN:
  .byte $00,$16,$1E,$50,$6E
S_SMALL = 1
S_MED = 2
S_SHIP = 3
S_REACT = 4
S_BIG = S_REACT

; alarm: two notes (period), volume envelope per frame
BEAT_TL:    .byte $54,$3F
BEAT_TH:    .byte $00,$00
BEAT_ENV:
  .byte $0C,$0C,$0C,$0B,$0B,$0A,$09,$08,$06,$03,$00
BEAT_LEN = 11

; directions: 0 = up, clockwise, 16 steps
; ship shot: 1.5 px per half step (8.8 signed)
BVX_L:
  .byte $00,$93,$10,$63,$80,$63,$10,$93,$00,$6D,$F0,$9D,$80,$9D,$F0,$6D
BVX_H:
  .byte $00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE,$FE,$FE,$FE,$FF
BVY_L:
  .byte $80,$9D,$F0,$6D,$00,$93,$10,$63,$80,$63,$10,$93,$00,$6D,$F0,$9D
BVY_H:
  .byte $FE,$FE,$FE,$FF,$00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE
; enemy shot: 1.25 px per frame (8.8 signed)
EVX_L:
  .byte $00,$7A,$E2,$28,$40,$28,$E2,$7A,$00,$86,$1E,$D8,$C0,$D8,$1E,$86
EVX_H:
  .byte $00,$00,$00,$01,$01,$01,$00,$00,$00,$FF,$FF,$FE,$FE,$FE,$FF,$FF
EVY_L:
  .byte $C0,$D8,$1E,$86,$00,$7A,$E2,$28,$40,$28,$E2,$7A,$00,$86,$1E,$D8
EVY_H:
  .byte $FE,$FE,$FF,$FF,$00,$00,$00,$01,$01,$01,$00,$00,$00,$FF,$FF,$FE
; thrust (1/256 px per frame^2, signed)
THX:
  .byte $00,$03,$05,$06,$07,$06,$05,$03,$00,$FD,$FB,$FA,$F9,$FA,$FB,$FD
THY:
  .byte $F9,$FA,$FB,$FD,$00,$03,$05,$06,$07,$06,$05,$03,$00,$FD,$FB,$FA
; unit pull (1/256 px per frame^2, signed): gravity and saucer steering
GRX:
  .byte $00,$01,$01,$02,$02,$02,$01,$01,$00,$FF,$FF,$FE,$FE,$FE,$FF,$FF
GRY:
  .byte $FE,$FE,$FF,$FF,$00,$01,$01,$02,$02,$02,$01,$01,$00,$FF,$FF,$FE
; nose of the ship (pixels from the centre, signed)
NOSEX:
  .byte $00,$02,$04,$06,$06,$06,$04,$02,$00,$FE,$FC,$FA,$FA,$FA,$FC,$FE
NOSEY:
  .byte $FA,$FA,$FC,$FE,$00,$02,$04,$06,$06,$06,$04,$02,$00,$FE,$FC,$FA
; where the ship leaves a planet (20 px from its centre, away from the star)
OUTX:
  .byte $00,$08,$0E,$12,$14,$12,$0E,$08,$00,$F8,$F2,$EE,$EC,$EE,$F2,$F8
OUTY:
  .byte $EC,$EE,$F2,$F8,$00,$08,$0E,$12,$14,$12,$0E,$08,$00,$F8,$F2,$EE
