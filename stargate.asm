;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_STARGATE  -  Williams Stargate (1981)               ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: defender (planet, scanner, landers and humanoids,    ;
;   NMI + trampoline $0FD0, AY sound engine)                   ;
;                                                              ;
;   - a planet 2048 pixels wide that wraps around, with the    ;
;     scanner on the top; the landers kidnap the humanoids,    ;
;     the ship catches them (more than one at a time) and      ;
;     brings them back to the ground                           ;
;   - the STARGATE: fly into it and you come out where a       ;
;     lander is taking a humanoid away (or where one is        ;
;     falling), otherwise on the other side of the planet;     ;
;     with 4 humanoids or more on board (waves 1-9, flying     ;
;     forwards) it warps the game 3 waves ahead                ;
;   - INVISO: the ship becomes invisible and invulnerable      ;
;     and destroys what it touches, while the energy lasts     ;
;   - new enemies: firebombers (fireballs), Yllabian space     ;
;     guppies, dynamos (they let out space hums), Phreds and   ;
;     Big Reds (they launch munchies) come with the baiters    ;
;   - wave 5, 15, 25...: Yllabian Dogfight in free space;      ;
;     wave 10, 20, 30...: Firebomber Showdown, no landers      ;
;   - lander 150, mutant 150, bomber 250, pod 1000, swarmer    ;
;     150, baiter 200, firebomber 250, fireball 100, guppy     ;
;     200, dynamo 200, space hum 100, Phred 200, Big Red 200,  ;
;     munchie 50; humanoid caught 500/1000/1500/2000,          ;
;     brought back 500, landed alone 250; wave bonus =         ;
;     humanoids x 100 x wave (up to 5); warp bonus = 2000      ;
;     per humanoid; ship, smart bomb and Inviso every 10000    ;
;   - 1 or 2 players (taking turns); high score                ;
;   - joystick 1 ($D581) or joystick 2 ($D580):                ;
;       LEFT / RIGHT = face and thrust, UP / DOWN = altitude   ;
;       button 1 = laser, button 2 = smart bomb,               ;
;       button 2 held = Inviso, both buttons = hyperspace      ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     laser, thrust, explosions, lander grabbing a humanoid,   ;
;     humanoid falling, catch and rescue, smart bomb,          ;
;     hyperspace, stargate, Inviso hum, fireballs, enemy       ;
;     shots, wave fanfare, extra ship                          ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page ----------------
NPL         = $30      ; players: 1 or 2
CURP        = $31      ; player playing: 0 / 1
INVE        = $32      ; Inviso energy (1 = 2 frames)
INVIS       = $33      ; 1 = Inviso on
B2HOLD      = $34      ; frames button 2 has been held
B2USED      = $35      ; 1 = this press of button 2 already did something
SGCOOL      = $36      ; frames before the stargate works again
WTYPE       = $37      ; 0 normal wave, 1 Yllabian Dogfight, 2 Firebomber Showdown
SPACE       = $38      ; 1 = free space (no planet on the screen)
SPKIND      = $39      ; kind of the enemies that come in groups
BAITK       = $3A      ; next timed enemy (baiter, Phred, Big Red)
LEFTL       = $3B      ; enemies of the groups still to come (saved per player)
INVBAR      = $3C      ; pixels of the Inviso bar on the screen
SND_INV     = $3D      ; 1 = Inviso hum
TPAGE       = $3E      ; title: page of the scoring table
TCNT        = $3F      ; title: frames to the next page
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
FIRE_OLD    = $81      ; buttons of the previous frame
SHXF        = $82      ; ship X on the planet: fraction, low, high (0-2047)
SHXL        = $83
SHXH        = $84
SHY         = $85      ; ship Y (centre)
SVXL        = $86      ; ship speed 8.8 signed
SVXH        = $87
FACE        = $88      ; 0 = facing right, 1 = facing left
SHSX        = $89      ; ship X on the screen (centre)
CAMXL       = $8A      ; left edge of the screen on the planet (0-2047)
CAMXH       = $8B
SHIPST      = $8C      ; 0 flying, 1 exploding, 2 waiting, 3 hyperspace
SHT         = $8D      ; timer of the ship state
LIVES       = $8E
BOMBS       = $8F      ; smart bombs
SCORE       = $90      ; 3 bytes BCD (low, middle, high)
HISC        = $93      ; 3 bytes BCD
NEXTX       = $96      ; next extra ship (BCD, tens of thousands)
WAVE        = $97
PLANET      = $98      ; 1 = the planet is there
HUMANS      = $99      ; humanoids alive
TOSPAWN     = $9A      ; group enemies still to come in this wave
SPAWNT      = $9B      ; frames to the next group (x 4)
BAITT       = $9C      ; 2 bytes: frames to the next baiter
THR         = $9E      ; 1 = thrust on
SCANPH      = $9F      ; scanner: phase 0-17 (row x 6 steps)
TERRK       = $A0      ; 2 bytes: CAMX / 2 of the mountains on the screen
LS_ON       = $A2      ; 2 lasers: on
LS_Y        = $A4      ;           Y
LS_C0       = $A6      ;           first column
LS_C1       = $A8      ;           column of the tip
LS_DIR      = $AA      ;           +1 / $FF
LS_T        = $AC      ;           frames left
SATB        = $AE      ; bytes of the SAT to copy
ROT         = $AF      ; first object of the sprite list (flicker)
CARRY       = $B0      ; humanoids carried by the ship
EI          = $B2      ; object being handled
DXL         = $B3      ; signed distance on the planet
DXH         = $B4
PTS_L       = $B6      ; points to add (BCD)
PTS_M       = $B7
MSGT        = $B8      ; frames before the message goes away
FLASH       = $B9      ; frames of white screen (smart bomb)
GAMEOV      = $BA      ; 1 = no ships left, 2 = end of the turn

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_THR    = $DC         ; 1 = thrust rumble
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

; ---------------- zero page: more temporaries ----------------
OX         = $E0         ; sprite being added: X on the screen, Y, pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4         ; next free byte of the SAT
CNT        = $E5
HI_        = $E6         ; humanoid being handled
TX         = $E7
TY         = $E8
SCR        = $E9         ; scanner row 0-2
LSA        = $EA         ; laser span (pixels) and line, for the hits
LSB        = $EB
LSYY       = $EC
BN1        = $ED         ; counters of the wave bonus
BN2        = $EE
SCH        = $EF         ; scanner: half of the row being copied (0 / 64)
HDRAWN     = $F0         ; 1 = a carried humanoid is already in the sprite list
BSTEP      = $F1         ; sprite list: step +1 / -1 and end of the loop
BEND       = $F2

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects

; ---------------- enemies: 0 free, 1 lander, 2 mutant, 3 bomber, 4 pod, 5 swarmer,
;                  6 baiter, 7 firebomber, 8 fireball, 9 guppy, 10 dynamo, 11 space hum,
;                  12 Phred, 13 Big Red, 14 munchie
NE     = 32
E_T    = $0300
E_XF   = E_T+NE*1        ; X: fraction, low, high (0-2047)
E_XL   = E_T+NE*2
E_XH   = E_T+NE*3
E_Y    = E_T+NE*4        ; Y: integer, fraction
E_YF   = E_T+NE*5
E_VXL  = E_T+NE*6        ; speed 8.8 signed
E_VXH  = E_T+NE*7
E_VYL  = E_T+NE*8
E_VYH  = E_T+NE*9
E_S    = E_T+NE*10       ; lander: 0 roaming, 1 going down to a humanoid, 2 going up with him
E_TM   = E_T+NE*11       ; timer
E_HU   = E_T+NE*12       ; humanoid aimed at / carried + 1
E_SX   = E_T+NE*13       ; X on the screen
E_ON   = E_T+NE*14       ; 1 = on the screen

; ---------------- humanoids: 0 dead, 1 walking, 2 carried by a lander, 3 falling, 4 carried by the ship
NH     = 10
H_ST   = $04E0
H_XL   = H_ST+NH*1
H_XH   = H_ST+NH*2
H_Y    = H_ST+NH*3
H_YF   = H_ST+NH*4
H_VYL  = H_ST+NH*5       ; falling speed 8.8
H_VYH  = H_ST+NH*6
H_Y0   = H_ST+NH*7       ; where the fall started
H_DIR  = H_ST+NH*8       ; walking: +1 / $FF
H_SX   = H_ST+NH*9
H_ON   = H_ST+NH*10

; ---------------- enemy shots and mines
NB     = 8
B_T    = $0550           ; frames of life (0 = free)
B_K    = B_T+NB*1        ; 0 shot, 1 mine
B_XF   = B_T+NB*2
B_XL   = B_T+NB*3
B_XH   = B_T+NB*4
B_YF   = B_T+NB*5
B_Y    = B_T+NB*6
B_VXL  = B_T+NB*7
B_VXH  = B_T+NB*8
B_VYL  = B_T+NB*9
B_VYH  = B_T+NB*10

; ---------------- explosions
NX     = 6
X_T    = $05A8           ; frame (0 = free)
X_XL   = X_T+NX*1
X_XH   = X_T+NX*2
X_Y    = X_T+NX*3

SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
TBUF       = $0690       ; 64 tiles of the mountains (rows 22-23)
PSAVE      = $0780       ; the two players: 48 bytes each (PV_LIST, then humanoids)
SCAN_P     = $0A00       ; scanner: patterns (3 rows x 16 cells x 8)
SCAN_C     = $0B80       ;          colours

; ---------------- parameters ----------------
Y_MIN       = 40         ; ship altitude
Y_MAX       = 168
E_YMIN      = 40         ; enemies
E_YMAX      = 168
GROUND_Y    = 181        ; humanoids walk here
TOP_Y       = 42         ; a lander up here with a humanoid turns into a mutant
SHIP_ACC    = $28        ; thrust per frame (8.8)
SHIP_VMAX   = 5          ; px per frame
FACE_R_X    = 56         ; where the ship sits on the screen
FACE_L_X    = 200
SG_XL       = $80        ; the stargate on the planet (X = 128) and its height
SG_XH       = $00
SG_Y        = 100
INV_START   = 200        ; Inviso energy at the start (x 2 frames)
INV_ADD     = 100        ;               every 10000 points
INV_MAX     = 250
HOLD_T      = 12         ; frames of button 2 before Inviso turns on
LASER_TILE  = 240        ; 8 tiles with a line on line 0-7
SCAN_TILE   = 128        ; 48 tiles of the scanner (rows 0-2, columns 8-23)
ICON_SHIP_T = 96
ICON_BOMB_T = 97
HLINE_T     = 98
BAR_T       = 99         ; 9 tiles: Inviso bar 0-8 pixels
BTN_MASK    = %00110000
HIDE_Y      = $C0

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
  STA SND_THR
  STA SND_INV
  STA HISC
  STA HISC+1
  STA HISC+2
  STA SCORE
  STA SCORE+1
  STA SCORE+2
  STA LIVES
  STA BOMBS
  STA WAVE
  STA INVE
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the scoring table in two pages, as in the attract mode
;  of the cabinet. Button 1 = 1 player, button 2 = 2 players
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ SND_THR
  STZ SND_INV
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_FIELD
  STZ NPL                      ; (no player label in the HUD)
  JSR DRAW_HUD
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  STZ TPAGE
  JSR TITLE_PAGE
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then pressed; the page changes every 4 seconds
  JSR WAIT_FRAME
  DEC TCNT
  BNE .t_key
  LDA TPAGE
  EOR #$01
  STA TPAGE
  JSR VDP_INT_OFF
  JSR TITLE_PAGE
  JSR VDP_INT_ON
.t_key:
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
;  NEW GAME: wave 1, 3 ships, 3 smart bombs for every player
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME
  STA SND_CMD
  LDA NPL
  STA CURP
.ng_p:
  DEC CURP                     ; player NPL-1 ... 0
  STZ SCORE
  STZ SCORE+1
  STZ SCORE+2
  STZ WAVE
  LDA #$03
  STA LIVES
  STA BOMBS
  LDA #$01
  STA NEXTX
  LDA #INV_START
  STA INVE
  JSR RESTORE_PLANET
  JSR NEXT_WAVE_SETUP
  LDX CURP
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_p
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER: his planet, his wave; a new ship
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  LDX CURP
  JSR LOAD_PLAYER
  STZ GAMEOV
  STZ CARRY
  LDA #$00                     ; the ship in the middle of the planet
  STA SHXF
  STA SHXL
  STA SVXL
  STA SVXH
  STA FACE
  STA SHIPST
  STA INVIS
  STA SGCOOL
  LDA #$04
  STA SHXH
  LDA #100
  STA SHY
  LDA #FACE_R_X
  STA SHSX
  LDA #$FF
  STA FIRE_OLD
  LDA #$01
  STA B2USED
  JMP BEGIN_WAVE


; ---------------------------------------------------------------
; the next wave: the planet comes back every 5 waves (6, 11, 16...)
; ---------------------------------------------------------------
ADV_WAVE:
  INC WAVE
  LDA WAVE
  CMP #1
  BEQ .aw_r
  SEC
  SBC #1
.aw_m5:
  CMP #5
  BCC .aw_t
  SBC #5
  BRA .aw_m5
.aw_t:
  CMP #0                       ; (wave - 1) mod 5 = 0: back
  BNE .aw_r
  JMP RESTORE_PLANET
.aw_r:
  RTS

; the next wave and how many enemies come in groups
NEXT_WAVE_SETUP:
  JSR ADV_WAVE
  JSR WAVE_TYPE
  LDA #20
  LDX WTYPE
  BNE .ns_l                    ; dogfight: 20 guppies; showdown: 20 firebombers
  LDA WAVE                     ; landers: 15, then 20
  CMP #2
  LDA #15
  BCC .ns_l
  LDA #20
.ns_l:
  CPX #2
  BNE .ns_s
  LDA #16
.ns_s:
  STA LEFTL
  RTS

; WTYPE from WAVE: wave mod 10 = 5 dogfight, = 0 showdown
WAVE_TYPE:
  LDA WAVE
.wt_m:
  CMP #10
  BCC .wt_r
  SBC #10
  BRA .wt_m
.wt_r:
  LDX #1
  CMP #5
  BEQ .wt_s
  INX
  CMP #0
  BEQ .wt_s
  LDX #0
.wt_s:
  STX WTYPE
  STZ SPACE
  CPX #1
  BNE .wt_e
  INC SPACE                    ; the dogfight is in free space
.wt_e:
  RTS


; ===============================================================
;  START OF A WAVE (also after a change of player)
; ===============================================================
BEGIN_WAVE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR WAVE_TYPE
  JSR NORMALIZE_H
  JSR VDP_INT_OFF
  JSR CLEAR_OBJECTS
  JSR CLEAR_FIELD
  LDA #$FF                     ; mountains redrawn
  STA TERRK
  STA TERRK+1
  JSR DRAW_HUD
  LDA NPL                      ; "PLAYER n"
  CMP #2
  BNE .bw_1p
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.bw_1p:
  LDA #<TXT_WAVE
  STA TP
  LDA #>TXT_WAVE
  STA TP+1
  JSR PRINT
  LDA WAVE
  JSR BIN2BCD
  LDX #9
  LDY #21
  JSR PUT_BCD2
  LDA WTYPE                    ; the special waves have their name
  BEQ .bw_nm
  LDX #<TXT_DOG
  LDY #>TXT_DOG
  CMP #1
  BEQ .bw_tx
  LDX #<TXT_SHOW
  LDY #>TXT_SHOW
.bw_tx:
  STX TP
  STY TP+1
  JSR PRINT
.bw_nm:
  LDA #150
  STA MSGT
  LDA #W_WAVE
  LDX #2
  JSR SFX_WHISTLE
  ; ---- the enemies of the wave
  LDA LEFTL
  STA TOSPAWN
  LDA WTYPE
  BEQ .bw_norm
  CMP #1
  BEQ .bw_dog
  LDA #7                       ; ---- showdown: firebombers, 2 bombers, 2 dynamos
  STA SPKIND
  JSR SPAWN_GROUP
  LDA #3
  LDX #2
  JSR SPAWN_N
  LDA #10
  LDX #2
  JSR SPAWN_N
  BRA .bw_go
.bw_dog:
  LDA #9                       ; ---- dogfight: guppies, 2 pods, 3 dynamos
  STA SPKIND
  JSR SPAWN_GROUP
  LDA #4
  LDX #2
  JSR SPAWN_N
  LDA #10
  LDX #3
  JSR SPAWN_N
  BRA .bw_go
.bw_norm:
  LDA #1                       ; ---- landers in groups of 5
  STA SPKIND
  JSR SPAWN_GROUP
  LDA WAVE                     ; bombers: wave + 1 (up to 3)
  INC A
  CMP #4
  BCC .bw_b
  LDA #3
.bw_b:
  TAX
  LDA #3
  JSR SPAWN_N
  LDA WAVE                     ; pods: wave (up to 3)
  CMP #4
  BCC .bw_p
  LDA #3
.bw_p:
  TAX
  LDA #4
  JSR SPAWN_N
  LDA WAVE                     ; firebombers: wave + 1 (up to 4)
  INC A
  CMP #5
  BCC .bw_f
  LDA #4
.bw_f:
  TAX
  LDA #7
  JSR SPAWN_N
  LDA WAVE                     ; dynamos: wave - 1 (up to 2)
  DEC A
  CMP #3
  BCC .bw_d
  LDA #2
.bw_d:
  TAX
  LDA #10
  JSR SPAWN_N
  LDA WAVE                     ; guppies from wave 3
  LDX #0
  CMP #3
  BCC .bw_y
  LDX #3
.bw_y:
  LDA #9
  JSR SPAWN_N
.bw_go:
  LDA #150
  STA SPAWNT
  STZ BAITK
  LDA #<3600                   ; baiters after one minute
  STA BAITT
  LDA #>3600
  STA BAITT+1
  JSR VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  JSR UPDATE_SHIP
  JSR UPDATE_CAMERA
  JSR DRAW_TERRAIN
  JSR UPDATE_LASERS
  JSR UPDATE_ENEMIES
  JSR UPDATE_HUMANS
  JSR UPDATE_SHOTS
  JSR UPDATE_EXPL
  JSR SHIP_HITS
  JSR WAVE_LOGIC
  JSR UPDATE_INV
  JSR UPDATE_SCANNER
  JSR UPDATE_MSG
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA GAMEOV
  BNE .gl_over
  JSR WAVE_DONE                ; carry = 1: the wave is over
  BCS .gl_next
  JMP GAME_LOOP
.gl_over:
  CMP #2
  BEQ .gl_turn
  JMP GAME_OVER
.gl_turn:
  JMP TURN_END
.gl_next:
  JMP WAVE_END


; ---------------------------------------------------------------
; end of a wave: bonus for the humanoids alive
; ---------------------------------------------------------------
WAVE_END:
  LDX #$FF
  TXS
  STZ SND_THR
  STZ SND_INV
  STZ INVIS
  JSR VDP_INT_OFF
  LDA #<TXT_DONE
  STA TP
  LDA #>TXT_DONE
  STA TP+1
  JSR PRINT
  LDA WAVE
  JSR BIN2BCD
  LDX #8
  LDY #21
  JSR PUT_BCD2
  LDA HUMANS                   ; bonus = humanoids x 100 x min(wave, 5)
  BEQ .we_nb
  STA CNT
  LDA WAVE
  CMP #6
  BCC .we_w
  LDA #5
.we_w:
  STA BN1
.we_h:
  LDA BN1
  STA BN2
.we_m:
  STZ PTS_L
  LDA #$01
  STA PTS_M
  JSR ADD_SCORE
  DEC BN2
  BNE .we_m
  DEC CNT
  BNE .we_h
.we_nb:
  LDA HUMANS
  JSR BIN2BCD
  LDX #10
  LDY #21
  JSR PUT_BCD2
  JSR VDP_INT_ON
  LDA #W_SAVE
  LDX #2
  JSR SFX_WHISTLE
  LDA #180
  JSR WAIT_FRAMES
  JSR NEXT_WAVE_SETUP
  JMP BEGIN_WAVE


; ---------------------------------------------------------------
; through the stargate with 4 humanoids or more: 3 waves ahead,
; 2000 for every humanoid alive
; ---------------------------------------------------------------
WARP:
  LDX #$FF
  TXS
  STZ SND_THR
  STZ SND_INV
  STZ INVIS
  JSR LAND_CARRIED
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_OBJECTS
  LDA #<TXT_WARP
  STA TP
  LDA #>TXT_WARP
  STA TP+1
  JSR PRINT
  LDA HUMANS
  JSR BIN2BCD
  LDX #10
  LDY #21
  JSR PUT_BCD2
  LDA HUMANS
  BEQ .wp_nb
  STA CNT
.wp_b:
  STZ PTS_L
  LDA #$20
  STA PTS_M
  JSR ADD_SCORE
  DEC CNT
  BNE .wp_b
.wp_nb:
  JSR VDP_INT_ON
  LDA #W_GATE
  LDX #2
  JSR SFX_WHISTLE
  LDA #60
  JSR WAIT_FRAMES
  LDA #W_GATE
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_FRAMES
  JSR ADV_WAVE
  JSR ADV_WAVE
  JSR NEXT_WAVE_SETUP
  JMP BEGIN_WAVE


; ---------------------------------------------------------------
; 2 players: a ship lost ends the turn
; ---------------------------------------------------------------
TURN_END:
  LDX #$FF
  TXS
  STZ SND_THR
  STZ SND_INV
  JSR CHECK_HI
  JSR COUNT_LEFT               ; the enemies of the groups come back next time
  LDX CURP
  JSR SAVE_PLAYER
  LDA LIVES
  BNE .te_alive
  JSR VDP_INT_OFF              ; this player is out
  LDA #<TXT_OVER1
  STA TP
  LDA #>TXT_OVER1
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
  JSR WAIT_FRAMES
.te_alive:
  LDA CURP                     ; the other player, if he still has ships
  EOR #$01
  TAX
  LDY PS_OFF,X
  LDA PSAVE+PV_LIVES,Y
  BEQ .te_same
  STX CURP
  JMP TURN_START
.te_same:
  LDA LIVES
  BEQ .te_over
  JMP TURN_START
.te_over:
  JMP GAME_OVER

; LEFTL = group enemies to come + those still flying (a mutant counts as a lander)
COUNT_LEFT:
  LDA TOSPAWN
  STA LEFTL
  LDX #(NE-1)
.cl_l:
  LDA E_T,X
  BEQ .cl_n
  CMP SPKIND
  BEQ .cl_y
  CMP #2
  BNE .cl_n
  LDA SPKIND
  CMP #1
  BNE .cl_n
.cl_y:
  INC LEFTL
.cl_n:
  DEX
  BPL .cl_l
  RTS

CHECK_HI:
  LDA SCORE+2                  ; hi score
  CMP HISC+2
  BCC .ch_n
  BNE .ch_new
  LDA SCORE+1
  CMP HISC+1
  BCC .ch_n
  BNE .ch_new
  LDA SCORE
  CMP HISC
  BCC .ch_n
.ch_new:
  LDA SCORE
  STA HISC
  LDA SCORE+1
  STA HISC+1
  LDA SCORE+2
  STA HISC+2
.ch_n:
  RTS


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  STZ SND_THR
  STZ SND_INV
  JSR CHECK_HI
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  JSR WAIT_FIRE
  JMP TITLE


; ===============================================================
;  PLAYERS: save / load the variables of PV_LIST and the humanoids
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDA PS_OFF,X
  STA T1
  LDX #$00
.sp_v:
  LDY PV_LIST,X
  LDA $0000,Y
  LDY T1
  STA PSAVE,Y
  INC T1
  INX
  CPX #PV_N
  BNE .sp_v
  LDX #(NH-1)                  ; humanoids (the ones in the air go back to the ground)
.sp_h:
  TXA
  CLC
  ADC T1
  TAY
  LDA H_ST,X
  CMP #2
  BCC .sp_s
  LDA #1
.sp_s:
  STA PSAVE,Y
  LDA H_XL,X
  STA PSAVE+NH,Y
  LDA H_XH,X
  STA PSAVE+NH*2,Y
  DEX
  BPL .sp_h
  RTS

LOAD_PLAYER:                   ; X = player
  LDA PS_OFF,X
  STA T1
  LDX #$00
.lp_v:
  LDY T1
  LDA PSAVE,Y
  LDY PV_LIST,X
  STA $0000,Y
  INC T1
  INX
  CPX #PV_N
  BNE .lp_v
  LDX #(NH-1)
.lp_h:
  TXA
  CLC
  ADC T1
  TAY
  LDA PSAVE,Y
  STA H_ST,X
  LDA PSAVE+NH,Y
  STA H_XL,X
  LDA PSAVE+NH*2,Y
  STA H_XH,X
  LDA #GROUND_Y
  STA H_Y,X
  DEX
  BPL .lp_h
  RTS


; ===============================================================
;  SHIP
; ===============================================================
UPDATE_SHIP:
  LDA SHIPST
  BEQ .us_fly
  CMP #$01
  BNE .us_n1
  DEC SHT                      ; ---- exploding
  BNE .us_r
  DEC LIVES
  JSR DRAW_LIVES
  LDA NPL                      ; 2 players: the turn ends
  CMP #2
  BEQ .us_turn
  LDA LIVES
  BNE .us_w
  LDA #$01
  STA GAMEOV
  RTS
.us_turn:
  LDA #$02
  STA GAMEOV
  RTS
.us_w:
  LDA #$02
  STA SHIPST
  LDA #60
  STA SHT
.us_r:
  RTS
.us_n1:
  CMP #$02
  BNE .us_hyp
  DEC SHT                      ; ---- waiting for the next ship
  BNE .us_r
  STZ SHIPST
  STZ SVXL
  STZ SVXH
  LDA #$FF
  STA FIRE_OLD
  LDA #$01
  STA B2USED
  RTS
.us_hyp:
  DEC SHT                      ; ---- hyperspace
  BNE .us_r
  JSR NEXT_RND                 ; somewhere else on the planet
  LDA RND
  STA SHXL
  AND #$07
  STA SHXH
  JSR NEXT_RND
  LDA RND
  AND #$7F
  CLC
  ADC #Y_MIN
  STA SHY
  STZ SHIPST
  STZ SVXL
  STZ SVXH
  LDA RND                      ; sometimes it goes wrong
  AND #$07
  BNE .us_r
  JMP SHIP_DIE
.us_fly:
  ; ---- left / right: face and thrust
  LDA #$00
  STA THR
  LDA JOYC
  AND #%00000100
  BEQ .us_nl
  LDA #$01
  STA FACE
  STA THR
  LDA SVXL
  SEC
  SBC #SHIP_ACC
  STA SVXL
  LDA SVXH
  SBC #$00
  STA SVXH
  BRA .us_clamp
.us_nl:
  LDA JOYC
  AND #%00001000
  BEQ .us_fr
  STZ FACE
  LDA #$01
  STA THR
  LDA SVXL
  CLC
  ADC #SHIP_ACC
  STA SVXL
  LDA SVXH
  ADC #$00
  STA SVXH
  BRA .us_clamp
.us_fr:
  LDA SVXH                     ; no thrust: the ship slows down (v -= v / 16)
  CMP #$80
  ROR A
  STA T1
  LDA SVXL
  ROR A
  STA T0
  LDX #3
.us_f4:
  LDA T1
  CMP #$80
  ROR T1
  ROR T0
  DEX
  BNE .us_f4
  LDA SVXL
  SEC
  SBC T0
  STA SVXL
  LDA SVXH
  SBC T1
  STA SVXH
  CMP #$FF                     ; very slow: stop
  BNE .us_clamp
  LDA SVXL
  CMP #$F0
  BCC .us_clamp
  STZ SVXL
  STZ SVXH
.us_clamp:
  LDA SVXH
  BMI .us_cn
  CMP #SHIP_VMAX
  BCC .us_move
  LDA #SHIP_VMAX
  STA SVXH
  STZ SVXL
  BRA .us_move
.us_cn:
  CMP #(256-SHIP_VMAX)
  BCS .us_move
  LDA #(256-SHIP_VMAX)
  STA SVXH
  STZ SVXL
.us_move:
  CLC
  LDA SHXF
  ADC SVXL
  STA SHXF
  LDA SHXL
  ADC SVXH
  STA SHXL
  LDA SVXH                     ; sign extension
  BPL .us_p
  LDA #$FF
  BRA .us_h
.us_p:
  LDA #$00
.us_h:
  ADC SHXH
  AND #$07
  STA SHXH
  LDA THR
  STA SND_THR
  ; ---- up / down
  LDA JOYC
  AND #%00000001
  BEQ .us_nu
  LDA SHY
  SEC
  SBC #2
  CMP #Y_MIN
  BCS .us_y
  LDA #Y_MIN
  BRA .us_y
.us_nu:
  LDA JOYC
  AND #%00000010
  BEQ .us_gate
  LDA SHY
  CLC
  ADC #2
  CMP #(Y_MAX+1)
  BCC .us_y
  LDA #Y_MAX
.us_y:
  STA SHY
.us_gate:
  ; ---- the stargate
  LDA SGCOOL
  BEQ .us_g
  DEC SGCOOL
  BRA .us_btn
.us_g:
  LDA SHXL
  SEC
  SBC #SG_XL
  STA T0
  LDA SHXH
  SBC #SG_XH
  AND #$07
  BEQ .us_gp
  CMP #$07
  BNE .us_btn
  LDA T0                       ; just to the left of it
  CMP #$F9
  BCC .us_btn
  BRA .us_gy
.us_gp:
  LDA T0
  CMP #8
  BCS .us_btn
.us_gy:
  LDA SHY
  SEC
  SBC #SG_Y
  JSR ABS_A
  CMP #8
  BCS .us_btn
  JMP ENTER_GATE
.us_btn:
  ; ---- buttons: laser, smart bomb, Inviso, both = hyperspace
  LDA FIRE_OLD
  STA T2                       ; buttons of the previous frame
  LDA JOYC
  AND #BTN_MASK
  STA T0
  EOR FIRE_OLD
  AND T0
  STA T1                       ; just pressed
  LDA T0
  STA FIRE_OLD
  ; ---- button 2 held: Inviso after HOLD_T frames; a short press = smart bomb
  LDA T0
  AND #%00100000
  BEQ .us_b2up
  LDA B2HOLD
  CMP #$FF
  BEQ .us_b2k
  INC B2HOLD
.us_b2k:
  LDA B2USED
  BNE .us_b1
  LDA B2HOLD
  CMP #HOLD_T
  BCC .us_b1
  LDA INVE
  BEQ .us_b1
  LDA INVIS
  BNE .us_b1
  LDA #$01
  STA INVIS
  LDA #W_INV
  LDX #2
  JSR SFX_WHISTLE
  BRA .us_b1
.us_b2up:
  STZ INVIS
  LDA T2
  AND #%00100000
  BEQ .us_b1                   ; it was not held
  LDA B2USED
  BNE .us_b2c
  LDA B2HOLD
  CMP #HOLD_T
  BCS .us_b2c
  JSR SMART_BOMB
.us_b2c:
  STZ B2HOLD
  STZ B2USED
.us_b1:
  ; ---- button 1 = laser; with button 2 just pressed (or together) = hyperspace
  LDA T1
  AND #%00010000
  BEQ .us_end                  ; button 1 not just pressed
  LDA T0
  CMP #BTN_MASK
  BNE .us_fire
  LDA B2HOLD                   ; (button 2 held for a while: button 1 fires)
  CMP #4
  BCS .us_fire
  LDA #$01
  STA B2USED
  JMP HYPERSPACE
.us_fire:
  JMP FIRE_LASER
.us_end:
  RTS

HYPERSPACE:
  LDA #$03
  STA SHIPST
  LDA #20
  STA SHT
  STZ THR
  STZ SND_THR
  STZ INVIS
  LDA #W_HYPER
  LDX #2
  JMP SFX_WHISTLE

SHIP_DIE:
  LDA #$01
  STA SHIPST
  LDA #90
  STA SHT
  STZ THR
  STZ SND_THR
  STZ INVIS
  LDA SHXL
  STA TX
  LDA SHXH
  STA TY
  LDA SHY
  JSR NEW_EXPL_AT
  LDX #(NH-1)                  ; the humanoids carried fall
.sd_h:
  LDA H_ST,X
  CMP #4
  BNE .sd_n
  PHX
  JSR HUMAN_DROP
  PLX
.sd_n:
  DEX
  BPL .sd_h
  STZ CARRY
  LDA #S_SHIP
  LDX #2
  JMP SFX_BOOM

SMART_BOMB:
  LDA BOMBS
  BEQ .sb_r
  DEC BOMBS
  JSR DRAW_BOMBS
  LDA #6
  STA FLASH
  LDX #(NE-1)                  ; every enemy on the screen explodes
.sb_l:
  LDA E_T,X
  BEQ .sb_n
  LDA E_ON,X
  BEQ .sb_n
  PHX
  JSR KILL_ENEMY
  PLX
.sb_n:
  DEX
  BPL .sb_l
  LDX #(NB-1)                  ; and the shots disappear
.sb_b:
  STZ B_T,X
  DEX
  BPL .sb_b
  LDA #S_BOMB
  LDX #2
  JMP SFX_BOOM
.sb_r:
  RTS

; ---------------------------------------------------------------
; into the stargate: warp, or where a humanoid is in danger,
; or the other side of the planet
; ---------------------------------------------------------------
ENTER_GATE:
  LDA #90
  STA SGCOOL
  LDA #W_GATE
  LDX #2
  JSR SFX_WHISTLE
  LDA CARRY                    ; ---- warp: 4 humanoids, waves 1-9, flying forwards
  CMP #4
  BCC .eg_t
  LDA WAVE
  CMP #10
  BCS .eg_t
  LDA SVXH
  BMI .eg_ml
  LDA FACE
  BNE .eg_t
  JMP WARP
.eg_ml:
  LDA FACE
  BEQ .eg_t
  JMP WARP
.eg_t:
  LDX #(NH-1)                  ; ---- a falling humanoid: under him
.eg_h:
  LDA H_ST,X
  CMP #3
  BNE .eg_hn
  LDA H_XL,X
  STA TX
  LDA H_XH,X
  STA TY
  LDA H_Y,X
  CLC
  ADC #30
  CMP #(Y_MAX+1)
  BCC .eg_hy
  LDA #Y_MAX
.eg_hy:
  STA T4
  LDA #0
  BRA .eg_go
.eg_hn:
  DEX
  BPL .eg_h
  LDY #$FF                     ; ---- the lander with a humanoid nearest the top
  LDA #$FF
  STA T6
  LDX #(NE-1)
.eg_l:
  LDA E_T,X
  CMP #1
  BNE .eg_ln
  LDA E_S,X
  CMP #2
  BNE .eg_ln
  LDA E_Y,X
  CMP T6
  BCS .eg_ln
  STA T6
  TXA
  TAY
.eg_ln:
  DEX
  BPL .eg_l
  CPY #$FF
  BEQ .eg_far
  LDA E_XL,Y
  STA TX
  LDA E_XH,Y
  STA TY
  LDA T6
  CMP #Y_MIN
  BCS .eg_ly
  LDA #Y_MIN
.eg_ly:
  STA T4
  LDA #60                      ; 60 pixels before him, facing him
.eg_go:
  STA T5
  LDA FACE
  BNE .eg_left
  LDA TX
  SEC
  SBC T5
  STA SHXL
  LDA TY
  SBC #$00
  AND #$07
  STA SHXH
  BRA .eg_y
.eg_left:
  LDA TX
  CLC
  ADC T5
  STA SHXL
  LDA TY
  ADC #$00
  AND #$07
  STA SHXH
.eg_y:
  LDA T4
  STA SHY
  BRA .eg_s
.eg_far:
  LDA SHXH                     ; ---- nobody in danger: the other side
  EOR #$04
  STA SHXH
.eg_s:
  STZ SVXL
  STZ SVXH
  LDA #FACE_R_X
  LDX FACE
  BEQ .eg_x
  LDA #FACE_L_X
.eg_x:
  STA SHSX
  RTS

; the ship glides to its side of the screen; the screen follows the ship
UPDATE_CAMERA:
  LDA #FACE_R_X
  LDX FACE
  BEQ .uc_t
  LDA #FACE_L_X
.uc_t:
  STA T0
  LDA SHSX
  CMP T0
  BEQ .uc_c
  BCC .uc_up
  SEC
  SBC #4
  CMP T0
  BCS .uc_s
  LDA T0
  BRA .uc_s
.uc_up:
  CLC
  ADC #4
  CMP T0
  BCC .uc_s
  LDA T0
.uc_s:
  STA SHSX
.uc_c:
  LDA SHXL                     ; CAMX = ship - SHSX
  SEC
  SBC SHSX
  STA CAMXL
  LDA SHXH
  SBC #$00
  AND #$07
  STA CAMXH
  RTS

; Inviso: the energy goes down while it is on; the bar in the HUD
UPDATE_INV:
  LDA INVIS
  BEQ .ui_b
  LDA FRAME_CNT
  LSR A
  BCC .ui_b
  DEC INVE
  BNE .ui_b
  STZ INVIS
.ui_b:
  LDA INVIS
  STA SND_INV
  JSR INV_PX
  CMP INVBAR
  BEQ .ui_r
  STA INVBAR
  JMP DRAW_INVBAR
.ui_r:
  RTS

; A = pixels of the Inviso bar (energy / 4, up to 56)
INV_PX:
  LDA INVE
  LSR A
  LSR A
  CMP #56
  BCC .ip_r
  LDA #56
.ip_r:
  RTS


; ===============================================================
;  LASERS: a line of tiles that grows from the nose of the ship
; ===============================================================
FIRE_LASER:
  LDX #$00
  LDA LS_ON
  BEQ .fl_go
  INX
  LDA LS_ON+1
  BEQ .fl_go
  RTS
.fl_go:
  LDA #$01
  STA LS_ON,X
  LDA SHY
  STA LS_Y,X
  LDA #14
  STA LS_T,X
  LDA FACE
  BNE .fl_l
  LDA SHSX                     ; facing right: from the nose to the right
  CLC
  ADC #8
  BCC .fl_r
  LDA #$FF
.fl_r:
  LSR A
  LSR A
  LSR A
  STA LS_C0,X
  STA LS_C1,X
  LDA #$01
  STA LS_DIR,X
  BRA .fl_s
.fl_l:
  LDA SHSX                     ; facing left
  SEC
  SBC #8
  BCS .fl_l2
  LDA #0
.fl_l2:
  LSR A
  LSR A
  LSR A
  STA LS_C0,X
  STA LS_C1,X
  LDA #$FF
  STA LS_DIR,X
.fl_s:
  LDX FACE
  LDA #W_LASER
  JMP SFX_WHISTLE

UPDATE_LASERS:
  LDX #$01
.ul_l:
  STX EI
  LDA LS_ON,X
  BEQ .ul_n
  DEC LS_T,X
  BEQ .ul_off
  LDA #3                       ; the tip moves on by 3 tiles
  STA CNT
.ul_g:
  LDX EI
  LDA LS_C1,X
  CLC
  ADC LS_DIR,X
  CMP #32
  BCS .ul_k                    ; edge of the screen
  STA LS_C1,X
  JSR LASER_TILE_AT            ; draws the tile at the tip
  DEC CNT
  BNE .ul_g
.ul_k:
  LDA FRAME_CNT                ; the hits of each laser every other frame
  EOR EI
  LSR A
  BCS .ul_n
  JSR LASER_HITS
  BRA .ul_n
.ul_off:
  JSR LASER_ERASE
  LDX EI
  STZ LS_ON,X
.ul_n:
  LDX EI
  DEX
  BPL .ul_l
  RTS

; laser EI: tile of column LS_C1 on its row
LASER_TILE_AT:
  LDX EI
  LDA LS_C1,X
  STA T0
  LDA LS_Y,X
  JSR NT_ADDR                  ; VREG set for (row of A, column T0)
  LDX EI
  LDA LS_Y,X
  AND #$07
  CLC
  ADC #LASER_TILE
  STA VDATA
  RTS

; laser EI: erase its tiles
LASER_ERASE:
  LDX EI
  LDA LS_C0,X
  STA T0
.le_l:
  LDX EI
  LDA LS_Y,X
  JSR NT_ADDR
  STZ VDATA
  LDX EI
  LDA T0
  CMP LS_C1,X
  BEQ .le_e
  CLC
  ADC LS_DIR,X
  STA T0
  BRA .le_l
.le_e:
  RTS

; A = Y on the screen, T0 = column: VDP address of that name table cell
NT_ADDR:
  LSR A
  LSR A
  LSR A                        ; row
  STA T1
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T2                       ; high: $78 + row / 8
  LDA T1
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  STA VREG                     ; low: (row mod 8) * 32 + column
  LDA T2
  STA VREG
  RTS

; laser EI: the enemies on its line between the ship and the tip
LASER_HITS:
  LDX EI
  LDA LS_C0,X                  ; T4..T5 = span in pixels
  LDY LS_C1,X
  CMP LS_C1,X
  BCC .lh_o
  TAY
  LDA LS_C1,X
.lh_o:
  ASL A
  ASL A
  ASL A
  STA LSA
  TYA
  ASL A
  ASL A
  ASL A
  ORA #$07
  STA LSB
  LDA LS_Y,X
  STA LSYY
  LDX #(NE-1)
.lh_l:
  LDA E_T,X
  BEQ .lh_n
  LDA E_ON,X
  BEQ .lh_n
  LDA E_SX,X
  CMP LSA
  BCC .lh_n
  CMP LSB
  BEQ .lh_y
  BCS .lh_n
.lh_y:
  LDA E_Y,X
  SEC
  SBC LSYY
  JSR ABS_A
  CMP #6
  BCS .lh_n
  PHX
  LDA EI                       ; (KILL_ENEMY uses EI)
  PHA
  JSR KILL_ENEMY
  PLA
  STA EI
  PLX
.lh_n:
  DEX
  BPL .lh_l
  RTS


; ===============================================================
;  ENEMIES
; ===============================================================
; A = kind: a new enemy far from the ship. X = slot, carry = 0 if no room
SPAWN_ENEMY:
  STA T7
  LDX #(NE-1)
.se_f:
  LDA E_T,X
  BEQ .se_ok
  DEX
  BPL .se_f
  CLC
  RTS
.se_ok:
  LDA T7
  STA E_T,X
  STZ E_S,X
  STZ E_HU,X
  STZ E_ON,X
  STZ E_XF,X
  STZ E_YF,X
  JSR NEXT_RND                 ; X: the side of the planet away from the ship
  LDA RND
  STA E_XL,X
  LDA SHXH
  CLC
  ADC #$03
  STA T0
  LDA RND
  AND #$01
  CLC
  ADC T0
  AND #$07
  STA E_XH,X
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC #50
  STA E_Y,X
  STA E_TM,X
  LDY T7                       ; speed by kind
  LDA SPAWN_VX,Y
  JSR RAND_SIGN
  STA E_VXL,X
  TYA
  STA E_VXH,X
  LDY T7
  LDA SPAWN_VY,Y
  JSR RAND_SIGN
  STA E_VYL,X
  TYA
  STA E_VYH,X
  SEC
  RTS

; A = kind, X = how many (0 = none)
SPAWN_N:
  STA T6
  STX CNT
  LDA CNT
  BEQ .sn_r
.sn_l:
  LDA T6
  JSR SPAWN_ENEMY
  DEC CNT
  BNE .sn_l
.sn_r:
  RTS

; A = kind: a new enemy where the enemy EI is. X = slot, carry = 0 if no room
SPAWN_AT:
  PHA
  LDX EI
  LDA E_XL,X
  STA TX
  LDA E_XH,X
  STA TY
  LDA E_Y,X
  STA T4
  PLA
  JSR SPAWN_ENEMY
  BCC .sa_r
  LDA TX
  STA E_XL,X
  LDA TY
  STA E_XH,X
  LDA T4
  STA E_Y,X
  SEC
.sa_r:
  RTS

; A = magnitude (1/256 px): A / Y = +A or -A at random (8.8)
RAND_SIGN:
  STA T0
  JSR NEXT_RND
  LDY #$00
  LDA RND
  AND #$02
  BEQ .rs_p
  LDA #$00
  SEC
  SBC T0
  LDY #$FF
  RTS
.rs_p:
  LDA T0
  RTS

; up to 5 enemies of the groups of the wave
SPAWN_GROUP:
  LDA #5
  STA CNT
.sg_l:
  LDA TOSPAWN
  BEQ .sg_r
  LDA SPKIND
  JSR SPAWN_ENEMY
  BCC .sg_r
  DEC TOSPAWN
  DEC CNT
  BNE .sg_l
.sg_r:
  RTS

UPDATE_ENEMIES:
  LDX #(NE-1)
.ue_l:
  STX EI
  LDA E_T,X
  BEQ .ue_n
  LDA E_ON,X                   ; off the screen: every other frame, two steps
  BNE .ue_go
  TXA
  EOR FRAME_CNT
  LSR A
  BCS .ue_n
.ue_go:
  LDA E_T,X
  ASL A
  TAY
  LDA E_LOGIC,Y                ; behaviour by kind
  STA PTR
  LDA E_LOGIC+1,Y
  STA PTR+1
  JSR .ue_jmp
  LDX EI
  LDA E_T,X                    ; (it may have been destroyed)
  BEQ .ue_n
  JSR MOVE_ENEMY
  LDA E_ON,X
  BNE .ue_one
  JSR MOVE_ENEMY
.ue_one:
  JSR SCREEN_POS_E
  JSR ENEMY_FIRE
.ue_n:
  LDX EI
  DEX
  BPL .ue_l
  RTS
.ue_jmp:
  JMP (PTR)

; ---- lander: roams, goes down to a humanoid, takes him up
LANDER:
  LDA E_S,X
  BNE .la_nr
  JMP .la_roam
.la_nr:
  CMP #1
  BEQ .la_down
  ; ---- going up with the humanoid
  LDA E_HU,X
  DEC A
  TAY
  LDA E_XL,X                   ; the humanoid hangs under the lander
  STA H_XL,Y
  LDA E_XH,X
  STA H_XH,Y
  LDA E_Y,X
  CLC
  ADC #10
  STA H_Y,Y
  LDA E_Y,X
  CMP #TOP_Y
  BCS .la_r
  LDA #$00                     ; at the top: the humanoid dies, a mutant is born
  STA H_ST,Y
  STZ E_HU,X
  DEC HUMANS
  LDA #2
  STA E_T,X
  STZ E_S,X
  JSR CHECK_PLANET
.la_r:
  RTS
.la_down:
  LDA E_HU,X                   ; ---- going down to the humanoid
  DEC A
  TAY
  LDA H_ST,Y
  CMP #1
  BEQ .la_d1
  STZ E_S,X                    ; someone else took him: roam again
  STZ E_HU,X
  RTS
.la_d1:
  STY HI_
  LDA H_XL,Y                   ; follow him along X
  STA DXL
  LDA H_XH,Y
  STA DXH
  JSR DIST_E
  LDA #$40
  JSR TOWARDS_X
  LDA #$90
  STA E_VYL,X
  STZ E_VYH,X
  LDY HI_
  LDA H_Y,Y
  SEC
  SBC #12
  CMP E_Y,X
  BCS .la_r
  LDA DXL                      ; low enough and above him: grabbed
  JSR ABS_A
  CMP #5
  BCS .la_r
  LDA DXH
  BEQ .la_g
  CMP #$FF
  BNE .la_r
.la_g:
  LDY HI_
  LDA #2
  STA H_ST,Y
  LDA #2
  STA E_S,X
  STZ E_VXL,X
  STZ E_VXH,X
  LDA #$A0                     ; up at 0.4 px per frame
  STA E_VYL,X
  LDA #$FF
  STA E_VYH,X
  LDA #W_GRAB
  JMP SFX_ENEMY
.la_roam:
  JSR BOUNCE_Y                 ; ---- roaming
  LDA PLANET
  BEQ .la_rr
  LDA FRAME_CNT                ; now and then looks for a humanoid below
  AND #$1F
  BNE .la_rr
  LDY #(NH-1)
.la_h:
  LDA H_ST,Y
  CMP #1
  BNE .la_hn
  LDA H_XL,Y
  STA DXL
  LDA H_XH,Y
  STA DXH
  PHY
  JSR DIST_E
  PLY
  LDA DXH
  BEQ .la_hp
  CMP #$FF
  BNE .la_hn
.la_hp:
  LDA DXL
  JSR ABS_A
  CMP #40
  BCS .la_hn
  JSR TAKEN                    ; not already wanted by another lander
  BCS .la_hn
  TYA
  INC A
  STA E_HU,X
  LDA #1
  STA E_S,X
  RTS
.la_hn:
  DEY
  BPL .la_h
.la_rr:
  RTS

; Y = humanoid: carry = 1 if another lander wants him
TAKEN:
  PHX
  STY T5
  INY
  STY T6
  LDX #(NE-1)
.tk_l:
  LDA E_T,X
  CMP #1
  BNE .tk_n
  LDA E_HU,X
  CMP T6
  BEQ .tk_y
.tk_n:
  DEX
  BPL .tk_l
  PLX
  LDY T5
  CLC
  RTS
.tk_y:
  PLX
  LDY T5
  SEC
  RTS

; ---- mutant: straight at the ship, shaking
MUTANT:
  JSR AT_SHIP
  LDA #$18
  JSR TOWARDS_X
  LDA #$0E
  LDY #$01
  JSR TOWARDS_Y
  LDA RND                      ; shaking
  AND #$03
  CMP #2
  BCS .mu_r
  TAY
  LDA E_Y,X
  CLC
  ADC JITTER,Y
  STA E_Y,X
.mu_r:
  JMP CLAMP_V2

; ---- bomber: drifts and lays mines
BOMBER:
  JSR BOUNCE_Y
  DEC E_TM,X
  LDA E_TM,X
  AND #$3F
  BNE .bo_r
  LDA E_ON,X
  BEQ .bo_r
  LDA #1                       ; a mine where it is
  JMP NEW_SHOT
.bo_r:
  RTS

; ---- pod: drifts (splits into swarmers when hit)
POD:
  JMP BOUNCE_Y

; ---- swarmer: fast, towards the ship
SWARMER:
  JSR AT_SHIP
  LDA #$20
  JSR TOWARDS_X
  LDA #$10
  LDY #$01
  JSR TOWARDS_Y
  JMP CLAMP_V2

; ---- baiter: as fast as the ship
BAITER:
  JSR AT_SHIP
  LDA #$30
  JSR TOWARDS_X
  LDA #$14
  LDY #$02
  JSR TOWARDS_Y
  LDA #$05                     ; up to 5 px per frame
  JMP CLAMP_VX

; ---- firebomber: zigzags and throws fireballs at the ship
FIREBOMBER:
  JSR BOUNCE_Y
  DEC E_TM,X
  LDA E_TM,X
  AND #$3F
  BNE .fb_f
  LDA #$90                     ; a new leg of the zigzag
  JSR RAND_SIGN
  STA E_VXL,X
  TYA
  STA E_VXH,X
  LDA #$A0
  JSR RAND_SIGN
  STA E_VYL,X
  TYA
  STA E_VYH,X
.fb_f:
  LDA E_ON,X
  BEQ .fb_r
  LDA SHIPST
  BNE .fb_r
  JSR NEXT_RND
  LDA RND
  CMP #3
  BCS .fb_r
  JSR AT_SHIP                  ; ---- a fireball: straight, fast
  JSR AIM
  STA T6
  LDA #8
  JSR SPAWN_AT
  BCC .fb_x
  LDY T6
  LDA FVX_L,Y
  STA E_VXL,X
  LDA FVX_H,Y
  STA E_VXH,X
  LDA FVY_L,Y
  STA E_VYL,X
  LDA FVY_H,Y
  STA E_VYH,X
  LDA #90
  STA E_TM,X
  LDA #W_FIREB
  JSR SFX_ENEMY
.fb_x:
  LDX EI
.fb_r:
  RTS

; ---- fireball: straight on until it burns out
FIREBALL:
  DEC E_TM,X
  BNE .fi_r
  STZ E_T,X
.fi_r:
  RTS

; ---- Yllabian space guppy: swims at the ship, undulating
GUPPY:
  JSR AT_SHIP
  LDA #$24
  JSR TOWARDS_X
  LDA #$0C
  LDY #$01
  JSR TOWARDS_Y
  TXA                          ; undulation
  ASL A
  ASL A
  ASL A
  ADC FRAME_CNT
  AND #$10
  LSR A
  LSR A
  LSR A
  LSR A
  TAY
  LDA E_Y,X
  CLC
  ADC JITTER,Y
  STA E_Y,X
  LDA #$03
  JMP CLAMP_VX

; ---- dynamo: drifts and lets out space hums
DYNAMO:
  JSR BOUNCE_Y
  DEC E_TM,X
  LDA E_TM,X
  AND #$7F
  BNE .dy_r
  LDA E_ON,X
  BEQ .dy_r
  LDA #11
  JSR SPAWN_AT
  LDX EI
.dy_r:
  RTS

; ---- space hum: slow, towards the ship
HUM:
  JSR AT_SHIP
  LDA #$10
  JSR TOWARDS_X
  LDA #$08
  LDY #$01
  JSR TOWARDS_Y
  LDA #$01
  JMP CLAMP_VX

; ---- Phred, Big Red: fast like the baiters, they launch munchies
PHRED:
  JSR AT_SHIP
  LDA #$28
  JSR TOWARDS_X
  LDA #$12
  LDY #$02
  JSR TOWARDS_Y
  LDA #$04
  JSR CLAMP_VX
  DEC E_TM,X
  LDA E_TM,X
  AND #$5F
  BNE .ph_r
  LDA E_ON,X
  BEQ .ph_r
  LDA #14
  JSR SPAWN_AT
  LDX EI
.ph_r:
  RTS

; ---- munchie: small and quick
MUNCHIE:
  JSR AT_SHIP
  LDA #$1C
  JSR TOWARDS_X
  LDA #$10
  LDY #$01
  JSR TOWARDS_Y
  JMP CLAMP_V2

; DXL/DXH = ship - enemy X
AT_SHIP:
  LDA SHXL
  STA DXL
  LDA SHXH
  STA DXH
  ; fall into DIST_E

; DXL/DXH = (DXL/DXH) - enemy X on the planet, signed (-1024..1023)
DIST_E:
  LDA DXL
  SEC
  SBC E_XL,X
  STA DXL
  LDA DXH
  SBC E_XH,X
  AND #$07
  CMP #$04
  BCC .de_p
  ORA #$F8
.de_p:
  STA DXH
  RTS

; A = acceleration (1/256 px): VX towards the sign of DXH
TOWARDS_X:
  STA T0
  LDA DXH
  BMI .tx_n
  LDA E_VXL,X
  CLC
  ADC T0
  STA E_VXL,X
  LDA E_VXH,X
  ADC #$00
  STA E_VXH,X
  RTS
.tx_n:
  LDA E_VXL,X
  SEC
  SBC T0
  STA E_VXL,X
  LDA E_VXH,X
  SBC #$00
  STA E_VXH,X
  RTS

; A = acceleration, Y = largest speed (px): VY towards the ship
TOWARDS_Y:
  STA T0
  STY T1
  LDA SHY
  CMP E_Y,X
  BCC .ty_up
  LDA E_VYL,X
  CLC
  ADC T0
  STA E_VYL,X
  LDA E_VYH,X
  ADC #$00
  STA E_VYH,X
  CMP T1
  BCC .ty_r
  LDA T1
  STA E_VYH,X
  STZ E_VYL,X
.ty_r:
  RTS
.ty_up:
  LDA E_VYL,X
  SEC
  SBC T0
  STA E_VYL,X
  LDA E_VYH,X
  SBC #$00
  STA E_VYH,X
  BPL .ty_r
  LDA #$00
  SEC
  SBC T1
  CMP E_VYH,X
  BCC .ty_r
  BEQ .ty_r
  STA E_VYH,X
  STZ E_VYL,X
  RTS

; |VX| < 2.5 px per frame
CLAMP_V2:
  LDA #$02
  ; fall into CLAMP_VX

; A = largest |VX| (px per frame)
CLAMP_VX:
  STA T0
  LDA E_VXH,X
  BMI .cv_n
  CMP T0
  BCC .cv_r
  LDA T0
  STA E_VXH,X
  STZ E_VXL,X
  RTS
.cv_n:
  EOR #$FF
  CMP T0
  BCC .cv_r
  LDA #$00
  SEC
  SBC T0
  STA E_VXH,X
  STZ E_VXL,X
.cv_r:
  RTS

; between E_YMIN and E_YMAX it bounces
BOUNCE_Y:
  LDA E_Y,X
  CMP #E_YMIN
  BCS .by_lo
  LDA E_VYH,X
  BPL .by_r
  BRA .by_neg
.by_lo:
  CMP #E_YMAX
  BCC .by_r
  LDA E_VYH,X
  BMI .by_r
.by_neg:
  LDA #$00
  SEC
  SBC E_VYL,X
  STA E_VYL,X
  LDA #$00
  SBC E_VYH,X
  STA E_VYH,X
.by_r:
  RTS

MOVE_ENEMY:
  CLC
  LDA E_XF,X
  ADC E_VXL,X
  STA E_XF,X
  LDA E_XL,X
  ADC E_VXH,X
  STA E_XL,X
  LDA E_VXH,X
  BPL .me_p
  LDA #$FF
  BRA .me_h
.me_p:
  LDA #$00
.me_h:
  ADC E_XH,X
  AND #$07
  STA E_XH,X
  CLC
  LDA E_YF,X
  ADC E_VYL,X
  STA E_YF,X
  LDA E_Y,X
  ADC E_VYH,X
  CMP #(E_YMIN-8)              ; never above the scanner
  BCS .me_y1
  LDA #(E_YMIN-8)
.me_y1:
  CMP #(GROUND_Y-4)
  BCC .me_y2
  LDA #(GROUND_Y-4)
.me_y2:
  STA E_Y,X
  RTS

; X = enemy: E_SX / E_ON from its X and the screen
SCREEN_POS_E:
  LDA E_XL,X
  SEC
  SBC CAMXL
  STA E_SX,X
  LDA E_XH,X
  SBC CAMXH
  AND #$07
  BEQ .sp_on
  STZ E_ON,X
  RTS
.sp_on:
  LDA #$01
  STA E_ON,X
  RTS

; enemies on the screen shoot now and then (mutants and baiters more)
ENEMY_FIRE:
  LDA E_ON,X
  BEQ .ef_r
  LDA SHIPST
  BNE .ef_r
  LDY E_T,X
  JSR NEXT_RND
  LDA RND
  CMP FIRE_RATE,Y
  BCS .ef_r
  LDA #0
  JMP NEW_SHOT
.ef_r:
  RTS

; X = enemy destroyed: points, explosion, what it leaves behind
KILL_ENEMY:
  STX EI
  LDA E_SX,X
  STA T5                       ; (for the sound)
  LDY E_T,X
  LDA KILL_PL,Y
  STA PTS_L
  LDA KILL_PM,Y
  STA PTS_M
  PHY
  JSR ADD_SCORE
  PLY
  LDX EI
  LDA E_XL,X
  STA TX
  LDA E_XH,X
  STA TY
  LDA E_Y,X
  JSR NEW_EXPL_AT
  LDX EI
  LDA E_HU,X                   ; a lander with a humanoid: he falls
  BEQ .ke_np
  LDA E_S,X
  CMP #2
  BNE .ke_np
  LDA E_HU,X
  DEC A
  PHX
  TAX
  JSR HUMAN_DROP
  PLX
.ke_np:
  LDA E_T,X
  CMP #4
  BNE .ke_ns
  STZ E_T,X                    ; a pod: 5 swarmers in its place
  LDA E_XL,X
  STA TX
  LDA E_XH,X
  STA TY
  LDA E_Y,X
  STA T6
  LDA #5
  STA CNT
.ke_sw:
  LDA #5
  JSR SPAWN_ENEMY
  BCC .ke_snd
  LDA TX
  STA E_XL,X
  LDA TY
  STA E_XH,X
  LDA T6
  STA E_Y,X
  DEC CNT
  BNE .ke_sw
  BRA .ke_snd
.ke_ns:
  LDX EI
  STZ E_T,X
.ke_snd:
  LDY T5
  LDA #S_SMALL
  JMP BOOM_AT

; A = sound, on the side of the enemy EI
SFX_ENEMY:
  LDX EI
  LDY E_SX,X
  JMP SFX_AT

; A = 0 shot at the ship, 1 mine: from the enemy X
NEW_SHOT:
  STA T7
  PHX
  LDY #(NB-1)
.ns_f:
  LDA B_T,Y
  BEQ .ns_ok
  DEY
  BPL .ns_f
  PLX
  RTS
.ns_ok:
  PLX
  LDA T7
  STA B_K,Y
  LDA E_XL,X
  STA B_XL,Y
  LDA E_XH,X
  STA B_XH,Y
  LDA E_Y,X
  STA B_Y,Y
  LDA #$80
  STA B_XF,Y
  STA B_YF,Y
  LDA #0
  STA B_VXL,Y
  STA B_VXH,Y
  STA B_VYL,Y
  STA B_VYH,Y
  LDA T7
  BEQ .ns_aim
  LDA #250                     ; a mine stays a while
  STA B_T,Y
  RTS
.ns_aim:
  LDA #110
  STA B_T,Y
  STY T7
  JSR AT_SHIP                  ; direction towards the ship
  JSR AIM
  TAX
  LDY T7
  LDA BVX_L,X
  STA B_VXL,Y
  LDA BVX_H,X
  STA B_VXH,Y
  LDA BVY_L,X
  STA B_VYL,Y
  LDA BVY_H,X
  STA B_VYH,Y
  LDX EI
  LDA #W_SHOT
  JMP SFX_ENEMY

; DXL/DXH = dx to the ship, enemy EI: A = direction 0-14 (even)
AIM:
  LDA DXH                      ; dx clipped to +-127
  BEQ .ai_xp
  CMP #$FF
  BEQ .ai_xn
  BMI .ai_xm
  LDA #127
  BRA .ai_xs
.ai_xm:
  LDA #$81
  BRA .ai_xs
.ai_xp:
  LDA DXL
  CMP #$80
  BCC .ai_xs
  LDA #127
  BRA .ai_xs
.ai_xn:
  LDA DXL
  CMP #$80
  BCS .ai_xs
  LDA #$81
.ai_xs:
  STA T2                       ; dx
  JSR ABS_A
  STA T4
  LDX EI
  LDA SHY
  SEC
  SBC E_Y,X
  STA T3                       ; dy
  JSR ABS_A
  STA T5
  ASL A                        ; |dx| >= 2|dy| -> horizontal
  BCS .ai_v
  CMP T4
  BCC .ai_h
  BEQ .ai_h
.ai_v:
  LDA T4                       ; |dy| >= 2|dx| -> vertical
  ASL A
  BCS .ai_d
  CMP T5
  BCC .ai_vv
  BEQ .ai_vv
.ai_d:
  LDA T2                       ; diagonal
  BMI .ai_dl
  LDA T3
  BMI .ai_ur
  LDA #6
  RTS
.ai_ur:
  LDA #2
  RTS
.ai_dl:
  LDA T3
  BMI .ai_ul
  LDA #10
  RTS
.ai_ul:
  LDA #14
  RTS
.ai_h:
  LDA T2
  BMI .ai_l
  LDA #4
  RTS
.ai_l:
  LDA #12
  RTS
.ai_vv:
  LDA T3
  BMI .ai_u
  LDA #8
  RTS
.ai_u:
  LDA #0
  RTS

ABS_A:                         ; A = |A| (signed)
  BPL .ab_r
  EOR #$FF
  CLC
  ADC #1
.ab_r:
  RTS


; ===============================================================
;  HUMANOIDS
; ===============================================================
UPDATE_HUMANS:
  LDA SPACE                    ; (free space: the planet is far away)
  BEQ .uh_go
  RTS
.uh_go:
  LDX #(NH-1)
.uh_l:
  STX HI_
  LDA H_ST,X
  BEQ .uh_n
  CMP #1
  BEQ .uh_walk
  CMP #3
  BEQ .uh_fall
  CMP #4
  BNE .uh_pos
  JSR CARRIED
  BRA .uh_pos
.uh_walk:
  LDA FRAME_CNT                ; a slow walk, turning now and then
  AND #$07
  BNE .uh_pos
  JSR NEXT_RND
  LDA RND
  AND #$3F
  BNE .uh_w
  LDA H_DIR,X
  EOR #$FE
  STA H_DIR,X
.uh_w:
  LDA H_XL,X
  CLC
  ADC H_DIR,X
  STA H_XL,X
  LDA H_DIR,X
  BMI .uh_wn
  LDA H_XH,X
  ADC #$00
  BRA .uh_wh
.uh_wn:
  LDA H_XH,X
  ADC #$FF
.uh_wh:
  AND #$07
  STA H_XH,X
  BRA .uh_pos
.uh_fall:
  JSR FALLING
.uh_pos:
  LDX HI_                      ; on the screen?
  LDA H_XL,X
  SEC
  SBC CAMXL
  STA H_SX,X
  LDA H_XH,X
  SBC CAMXH
  AND #$07
  BEQ .uh_on
  STZ H_ON,X
  BRA .uh_n
.uh_on:
  LDA #$01
  STA H_ON,X
.uh_n:
  LDX HI_
  DEX
  BPL .uh_l
  RTS

; X = humanoid falling: gravity; low enough he lands, from too high he dies
FALLING:
  LDA H_VYL,X
  CLC
  ADC #$06
  STA H_VYL,X
  LDA H_VYH,X
  ADC #$00
  CMP #2
  BCC .fa_v
  LDA #2
  STZ H_VYL,X
.fa_v:
  STA H_VYH,X
  CLC
  LDA H_YF,X
  ADC H_VYL,X
  STA H_YF,X
  LDA H_Y,X
  ADC H_VYH,X
  STA H_Y,X
  CMP #GROUND_Y
  BCC .fa_r
  LDA #GROUND_Y
  STA H_Y,X
  LDA #GROUND_Y                ; height of the fall
  SEC
  SBC H_Y0,X
  CMP #90
  BCS .fa_dead
  LDA #1                       ; landed alone: 250
  STA H_ST,X
  LDA #$50
  STA PTS_L
  LDA #$02
  STA PTS_M
  JSR ADD_SCORE
  LDA #W_SAVE
  LDX #2
  JMP SFX_WHISTLE
.fa_dead:
  STZ H_ST,X
  DEC HUMANS
  LDA H_XL,X
  STA TX
  LDA H_XH,X
  STA TY
  LDA H_Y,X
  JSR NEW_EXPL_AT
  JMP CHECK_PLANET
.fa_r:
  RTS

; X = humanoid carried by the ship: put down when near the ground
CARRIED:
  LDA SHXL
  STA H_XL,X
  LDA SHXH
  STA H_XH,X
  LDA SHY
  CLC
  ADC #10
  STA H_Y,X
  CMP #(GROUND_Y-6)
  BCC .ca_r
  LDA #GROUND_Y                ; brought back: 500
  STA H_Y,X
  LDA #1
  STA H_ST,X
  DEC CARRY
  STZ PTS_L
  LDA #$05
  STA PTS_M
  JSR ADD_SCORE
  LDA #W_SAVE
  LDX #2
  JMP SFX_WHISTLE
.ca_r:
  RTS

; X = humanoid: he starts falling from where he is
HUMAN_DROP:
  LDA #3
  STA H_ST,X
  LDA H_Y,X
  STA H_Y0,X
  STZ H_VYL,X
  STZ H_VYH,X
  STZ H_YF,X
  LDA #W_FALL
  LDX #2
  JMP SFX_WHISTLE

; the humanoids carried by the ship are put down where they are
LAND_CARRIED:
  LDX #(NH-1)
.lc_l:
  LDA H_ST,X
  CMP #4
  BNE .lc_n
  LDA #1
  STA H_ST,X
  LDA #GROUND_Y
  STA H_Y,X
.lc_n:
  DEX
  BPL .lc_l
  STZ CARRY
  RTS

; a new wave: the humanoids held by landers or falling are back on the ground
NORMALIZE_H:
  LDX #(NH-1)
.nh_l:
  LDA H_ST,X
  CMP #2
  BEQ .nh_g
  CMP #3
  BNE .nh_n
.nh_g:
  LDA #1
  STA H_ST,X
  LDA #GROUND_Y
  STA H_Y,X
.nh_n:
  DEX
  BPL .nh_l
  RTS

; no humanoid left: the planet explodes and every lander becomes a mutant
CHECK_PLANET:
  LDA HUMANS
  BNE .cp_r
  LDA PLANET
  BEQ .cp_r
  STZ PLANET
  LDA #8
  STA FLASH
  LDX #(NE-1)
.cp_l:
  LDA E_T,X
  CMP #1
  BNE .cp_n
  LDA #2
  STA E_T,X
  STZ E_S,X
  STZ E_HU,X
.cp_n:
  DEX
  BPL .cp_l
  LDA #S_BOMB
  LDX #2
  JMP SFX_BOOM
.cp_r:
  RTS

; the planet and 10 humanoids, spread along it
RESTORE_PLANET:
  LDA #$01
  STA PLANET
  LDA #NH
  STA HUMANS
  LDX #(NH-1)
.rp_l:
  LDA #1
  STA H_ST,X
  LDA HUM_XL,X                 ; spread along the planet
  STA H_XL,X
  LDA HUM_XH,X
  STA H_XH,X
  LDA #GROUND_Y
  STA H_Y,X
  LDA #1
  STA H_DIR,X
  TXA
  AND #$01
  BEQ .rp_d
  LDA #$FF
  STA H_DIR,X
.rp_d:
  DEX
  BPL .rp_l
  RTS


; ===============================================================
;  ENEMY SHOTS, MINES, EXPLOSIONS
; ===============================================================
UPDATE_SHOTS:
  LDX #(NB-1)
.us_l:
  LDA B_T,X
  BNE .us_go
  JMP .us_n
.us_go:
  DEC B_T,X
  BNE .us_mv
  JMP .us_n
.us_mv:
  CLC
  LDA B_XF,X
  ADC B_VXL,X
  STA B_XF,X
  LDA B_XL,X
  ADC B_VXH,X
  STA B_XL,X
  LDA B_VXH,X
  BPL .us_p
  LDA #$FF
  BRA .us_h
.us_p:
  LDA #$00
.us_h:
  ADC B_XH,X
  AND #$07
  STA B_XH,X
  CLC
  LDA B_YF,X
  ADC B_VYL,X
  STA B_YF,X
  LDA B_Y,X
  ADC B_VYH,X
  STA B_Y,X
  CMP #(E_YMIN-8)              ; out of the field
  BCC .us_off
  CMP #(GROUND_Y+2)
  BCS .us_off
  LDA SHIPST                   ; ---- the ship (not while invisible)
  ORA INVIS
  BNE .us_n
  LDA B_XL,X
  SEC
  SBC SHXL
  STA T0
  LDA B_XH,X
  SBC SHXH
  AND #$07
  BEQ .us_dp
  CMP #$07
  BNE .us_n
  LDA T0
  EOR #$FF
  INC A
  STA T0
  BRA .us_dc
.us_dp:
  LDA T0
.us_dc:
  CMP #8
  BCS .us_n
  LDA B_Y,X
  SEC
  SBC SHY
  JSR ABS_A
  CMP #4
  BCS .us_n
  STZ B_T,X
  JMP SHIP_DIE
.us_off:
  STZ B_T,X
.us_n:
  DEX
  BMI .us_e
  JMP .us_l
.us_e:
  RTS

; TX/TY = X on the planet, A = Y: a new explosion
NEW_EXPL_AT:
  STA T7
  LDY #(NX-1)
.ne_f:
  LDA X_T,Y
  BEQ .ne_ok
  DEY
  BPL .ne_f
  LDY #0
.ne_ok:
  LDA #1
  STA X_T,Y
  LDA TX
  STA X_XL,Y
  LDA TY
  STA X_XH,Y
  LDA T7
  STA X_Y,Y
  RTS

UPDATE_EXPL:
  LDX #(NX-1)
.ux_l:
  LDA X_T,X
  BEQ .ux_n
  INC X_T,X
  LDA X_T,X
  CMP #24
  BCC .ux_n
  STZ X_T,X
.ux_n:
  DEX
  BPL .ux_l
  RTS


; ===============================================================
;  SHIP AGAINST ENEMIES (invisible: they explode); CATCHING HUMANOIDS
; ===============================================================
SHIP_HITS:
  LDA SHIPST
  BEQ .sh_go
  RTS
.sh_go:
  LDX #(NE-1)
.sh_l:
  LDA E_T,X
  BEQ .sh_n
  LDA E_ON,X
  BEQ .sh_n
  LDA E_SX,X
  SEC
  SBC SHSX
  JSR ABS_A
  CMP #10
  BCS .sh_n
  LDA E_Y,X
  SEC
  SBC SHY
  JSR ABS_A
  CMP #6
  BCS .sh_n
  LDA INVIS
  BNE .sh_inv
  JSR KILL_ENEMY
  JMP SHIP_DIE
.sh_inv:
  PHX
  JSR KILL_ENEMY
  PLX
.sh_n:
  DEX
  BPL .sh_l
  LDA SPACE                    ; ---- falling humanoids caught
  BNE .sh_r
  LDX #(NH-1)
.sh_h:
  LDA H_ST,X
  CMP #3
  BNE .sh_hn
  LDA H_ON,X
  BEQ .sh_hn
  LDA H_SX,X
  SEC
  SBC SHSX
  JSR ABS_A
  CMP #10
  BCS .sh_hn
  LDA H_Y,X
  SEC
  SBC SHY
  JSR ABS_A
  CMP #12
  BCS .sh_hn
  LDA #4
  STA H_ST,X
  INC CARRY
  LDY CARRY                    ; caught: 500, 1000, 1500, then 2000
  CPY #4
  BCC .sh_c
  LDY #4
.sh_c:
  STZ PTS_L
  LDA CATCH_PM,Y
  STA PTS_M
  PHX
  JSR ADD_SCORE
  LDA #W_CATCH
  LDX #2
  JSR SFX_WHISTLE
  PLX
.sh_hn:
  DEX
  BPL .sh_h
.sh_r:
  RTS


; ===============================================================
;  WAVES
; ===============================================================
WAVE_LOGIC:
  LDA FRAME_CNT                ; ---- next group of enemies
  AND #$03
  BNE .wl_b
  DEC SPAWNT
  BNE .wl_b
  LDA #150
  STA SPAWNT
  JSR SPAWN_GROUP
.wl_b:
  LDA BAITT                    ; ---- baiters, Phreds and Big Reds if the wave lasts too long
  BNE .wl_d
  DEC BAITT+1
.wl_d:
  DEC BAITT
  LDA BAITT
  ORA BAITT+1
  BNE .wl_r
  LDA #<900
  STA BAITT
  LDA #>900
  STA BAITT+1
  LDY BAITK
  LDA TIMED_K,Y
  JSR SPAWN_ENEMY
  LDA BAITK
  INC A
  CMP #3
  BCC .wl_k
  LDA #0
.wl_k:
  STA BAITK
.wl_r:
  RTS

; carry = 1 when no group enemy is left to come and the enemies of the wave are gone
WAVE_DONE:
  LDA TOSPAWN
  BNE .wd_no
  LDX #(NE-1)
.wd_l:
  LDY E_T,X
  BEQ .wd_n
  LDA COUNTS,Y
  BNE .wd_no                   ; (baiters, fireballs, hums, Phreds, Big Reds, munchies do not count)
.wd_n:
  DEX
  BPL .wd_l
  SEC
  RTS
.wd_no:
  CLC
  RTS

CLEAR_OBJECTS:
  LDX #(NE-1)
.co_e:
  STZ E_T,X
  DEX
  BPL .co_e
  LDX #(NB-1)
.co_b:
  STZ B_T,X
  DEX
  BPL .co_b
  LDX #(NX-1)
.co_x:
  STZ X_T,X
  DEX
  BPL .co_x
  STZ LS_ON
  STZ LS_ON+1
  STZ MSGT
  STZ FLASH
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M (BCD): extra ship, smart bomb and Inviso every 10000
ADD_SCORE:
  PHX
  SED
  CLC
  LDA SCORE
  ADC PTS_L
  STA SCORE
  LDA SCORE+1
  ADC PTS_M
  STA SCORE+1
  LDA SCORE+2
  ADC #$00
  STA SCORE+2
  CLD
  CMP NEXTX
  BCC .as_d
  SED
  LDA NEXTX
  CLC
  ADC #$01
  STA NEXTX
  CLD
  LDA LIVES
  CMP #9
  BCS .as_b
  INC LIVES
.as_b:
  LDA BOMBS
  CMP #9
  BCS .as_i
  INC BOMBS
.as_i:
  LDA INVE
  CLC
  ADC #INV_ADD
  BCS .as_im
  CMP #INV_MAX
  BCC .as_is
.as_im:
  LDA #INV_MAX
.as_is:
  STA INVE
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
  JSR DRAW_BOMBS
.as_d:
  JSR DRAW_SCORE
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
  JSR LOAD_SPRITES
  JMP CLEAR_FIELD

; name table: scanner cells on rows 0-2, a line on row 3, the rest empty
CLEAR_FIELD:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDY #SCAN_TILE
  LDX #$00                     ; rows 0-2
.cf_r:
  LDA #0
  CPX #8
  BCC .cf_w
  CPX #24
  BCS .cf_w
  TYA
  INY
.cf_w:
  STA VDATA
  INX
  CPX #32
  BNE .cf_r
  LDX #$00
  CPY #(SCAN_TILE+48)
  BNE .cf_r
  LDX #32                      ; row 3: the line under the scanner
  LDA #HLINE_T
.cf_l:
  STA VDATA
  DEX
  BNE .cf_l
  LDX #$00                     ; rows 4-23: empty (640 bytes)
  LDA #0
.cf_e:
  STA VDATA
  STA VDATA
  INX
  CPX #160
  BNE .cf_e
  LDX #160
.cf_e2:
  STA VDATA
  STA VDATA
  DEX
  BNE .cf_e2
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
; the font is in the thirds 0 and 1 (rows 0-15)
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

DRAW_HUD:
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR PRINT
  LDA HISC+2
  LDX #0
  LDY #25
  JSR PUT_BCD2
  LDA HISC+1
  LDX #0
  LDY #27
  JSR PUT_BCD2
  LDA HISC
  LDX #0
  LDY #29
  JSR PUT_BCD2
  LDA WAVE
  JSR BIN2BCD
  LDX #1
  LDY #29
  JSR PUT_BCD2
  LDA NPL                      ; 2 players: P1 / P2
  CMP #2
  BNE .dh_1p
  LDX #1
  LDY #21
  JSR NT_XY
  LDA #'P'
  STA VDATA
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.dh_1p:
  JSR INV_PX
  STA INVBAR
  JSR DRAW_INVBAR
  JSR DRAW_SCORE
  JSR DRAW_LIVES
  ; fall into DRAW_BOMBS

DRAW_BOMBS:
  LDX #2
  LDY #1
  JSR NT_XY
  LDX #$00
.db_l:
  LDA #ICON_BOMB_T
  CPX BOMBS
  BCC .db_w
  LDA #0
.db_w:
  STA VDATA
  INX
  CPX #5
  BNE .db_l
  RTS

; the Inviso bar: row 2, columns 24-30, INVBAR pixels
DRAW_INVBAR:
  LDX #2
  LDY #24
  JSR NT_XY
  LDA INVBAR
  STA T0
  LDX #7
.di_l:
  LDA T0
  CMP #8
  BCC .di_t
  LDA #8
.di_t:
  CLC
  ADC #BAR_T
  STA VDATA
  LDA T0
  SEC
  SBC #8
  BCS .di_s
  LDA #0
.di_s:
  STA T0
  DEX
  BNE .di_l
  RTS

DRAW_LIVES:
  LDX #1
  LDY #1
  JSR NT_XY
  LDX #$00
.dl_l:
  LDA #ICON_SHIP_T
  CPX LIVES
  BCC .dl_w
  LDA #0
.dl_w:
  STA VDATA
  INX
  CPX #5
  BNE .dl_l
  RTS

DRAW_SCORE:
  PHX
  LDX #0
  LDY #1
  JSR NT_XY
  LDA SCORE+2
  JSR .ds_2
  LDA SCORE+1
  JSR .ds_2
  LDA SCORE
  JSR .ds_2
  PLX
  RTS
.ds_2:
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

; the message in the middle goes away; the white flash of a smart bomb
UPDATE_MSG:
  LDA MSGT
  BEQ .um_f
  DEC MSGT
  BNE .um_f
  LDX #7                       ; clear rows 7-12
  LDY #0
  JSR NT_XY
  LDX #96
  LDA #0
.um_c:
  STA VDATA
  STA VDATA
  DEX
  BNE .um_c
.um_f:
  LDA FLASH
  BEQ .um_r
  DEC FLASH
  LDA FLASH
  AND #$02
  BEQ .um_b
  LDA #$0F                     ; R7: white
  BRA .um_s
.um_b:
  LDA #$01                     ; R7: black
.um_s:
  STA VREG
  LDA #(VDP_REGISTER_BITS | 7)
  STA VREG
.um_r:
  RTS


; ===============================================================
;  MOUNTAINS: rows 22-23, scrolling in steps of 2 pixels
; ===============================================================
DRAW_TERRAIN:
  LDA SPACE                    ; free space: no mountains
  BNE .dt_no
  LDA PLANET
  BNE .dt_on
.dt_no:
  LDA TERRK                    ; no planet: empty rows, once
  CMP #$FE
  BNE .dt_blank
  RTS
.dt_blank:
  LDA #$FE
  STA TERRK
  LDX #63
.dt_z:
  STZ TBUF,X
  DEX
  BPL .dt_z
  JMP .dt_write
.dt_on:
  LDA CAMXH                    ; key = CAMX / 2
  LSR A
  STA T1
  LDA CAMXL
  ROR A
  STA T0
  CMP TERRK
  BNE .dt_go
  LDA T1
  CMP TERRK+1
  BEQ .dt_r
.dt_go:
  LDA T0
  STA TERRK
  LDA T1
  STA TERRK+1
  LDA CAMXL                    ; shift: (CAMX / 2) and 3 -> table of the tiles
  LSR A
  AND #$03
  TAX
  LDA TW_LO,X
  STA PTR
  LDA TW_HI,X
  STA PTR+1
  LDA CAMXH                    ; first column = CAMX / 8
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA T3
  LDA CAMXL
  LSR A
  LSR A
  LSR A
  ORA T3
  STA T3
  LDA #$C0                     ; name table $3AC0 = row 22
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $3A)
  STA VREG
  LDY T3                       ; row 22: upper tiles
  LDX #32
.dt_u:
  LDA (PTR),Y
  STA VDATA
  INY
  DEX
  BNE .dt_u
  LDY T3                       ; row 23: lower tiles (= upper + 1)
  LDX #32
.dt_d:
  LDA (PTR),Y
  INC A
  STA VDATA
  INY
  DEX
  BNE .dt_d
  RTS
.dt_write:
  LDA #$C0                     ; (no planet: empty rows)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $3A)
  STA VREG
  LDX #$00
.dt_w:
  LDA TBUF,X
  STA VDATA
  INX
  CPX #64
  BNE .dt_w
.dt_r:
  RTS


; ===============================================================
;  SCANNER: the whole planet in 128 x 24 pixels (48 tiles).
;  One step every other frame: row 0-2 x (clear, draw, patterns to VRAM
;  in two halves, colours to VRAM in two halves)
; ===============================================================
UPDATE_SCANNER:
  LDA FRAME_CNT                ; every other frame
  LSR A
  BCC .sc_go
  RTS
.sc_go:
  LDA SCANPH
  INC A
  CMP #18
  BCC .sc_p
  LDA #0
.sc_p:
  STA SCANPH
  LDX #0                       ; row = phase / 6, step = phase mod 6
.sc_d:
  CMP #6
  BCC .sc_s
  SBC #6
  INX
  BRA .sc_d
.sc_s:
  STX SCR
  TAY
  BEQ .sc_clr
  DEY
  BEQ .sc_draw
  DEY                          ; step 2-5: Y = half (0 / 64)
  TYA
  AND #$01
  BEQ .sc_h0
  LDA #64
.sc_h0:
  STA SCH
  CPY #2
  BCS .sc_c
  JMP SCAN_UP_P
.sc_c:
  JMP SCAN_UP_C
.sc_clr:
  ; ---- step 0: clear the patterns of the row (the colours only matter under a dot)
  LDA #<SCAN_P
  LDY #>SCAN_P
  JSR ROW_PTR
  LDY #127
  LDA #$00
.sc_cl:
  STA (PTR),Y
  DEY
  BPL .sc_cl
  RTS
.sc_draw:
  ; ---- step 1: draw the row in RAM
  LDA #<SCAN_C
  LDY #>SCAN_C
  JSR ROW_PTR
  LDA PTR                      ; PTR = patterns, PTR2 = colours
  STA PTR2
  LDA PTR+1
  STA PTR2+1
  LDA #<SCAN_P
  LDY #>SCAN_P
  JSR ROW_PTR
  LDA #SG_XL                   ; the stargate
  STA TX
  LDA #SG_XH
  STA TY
  LDA #SG_Y
  LDY #$B0
  JSR SCAN_PLOT
  LDA SPACE                    ; humanoids (not in free space)
  BNE .sc_hx
  LDX #(NH-1)
.sc_h:
  LDA H_ST,X
  BEQ .sc_hn
  LDA H_XL,X
  STA TX
  LDA H_XH,X
  STA TY
  LDA H_Y,X
  LDY #$D0
  JSR SCAN_PLOT
.sc_hn:
  DEX
  BPL .sc_h
.sc_hx:
  LDX #(NE-1)                  ; enemies
.sc_e:
  LDY E_T,X
  BEQ .sc_en
  LDA E_XL,X
  STA TX
  LDA E_XH,X
  STA TY
  LDA SCAN_COL,Y
  TAY
  LDA E_Y,X
  JSR SCAN_PLOT
.sc_en:
  DEX
  BPL .sc_e
  LDA SHIPST                   ; the ship, last (white)
  CMP #$01
  BEQ .sc_r
  LDA SHXL
  STA TX
  LDA SHXH
  STA TY
  LDA SHY
  LDY #$F0
  JMP SCAN_PLOT
.sc_r:
  RTS

; TX/TY = X on the planet, A = Y, Y = colour: a dot in the scanner row SCR
SCAN_PLOT:
  SEC
  SBC #32                      ; scanner line = (Y - 32) / 8 + 3
  BCC .sp_r
  LSR A
  LSR A
  LSR A
  CLC
  ADC #3
  STA T4
  LSR A
  LSR A
  LSR A
  CMP SCR
  BNE .sp_r
  STY T5
  LDA TX                       ; scanner X = ((X - ship + 1024) and 2047) / 16
  SEC
  SBC SHXL
  STA T2
  LDA TY
  SBC SHXH
  CLC
  ADC #$04
  AND #$07
  STA T3
  LDA T2
  LSR T3
  ROR A
  LSR T3
  ROR A
  LSR T3
  ROR A
  LSR T3
  ROR A                        ; 0-127
  STA T2
  AND #$78                     ; cell * 8
  STA T3
  LDA T4
  AND #$07
  ORA T3
  TAY
  LDA T2
  AND #$07
  PHX
  TAX
  LDA (PTR),Y
  ORA BITMASK,X
  STA (PTR),Y
  LDA T5
  STA (PTR2),Y
  PLX
.sp_r:
  RTS

; A/Y = base: PTR = base + row SCR * 128
ROW_PTR:
  STA PTR
  STY PTR+1
  LDA SCR
  LSR A
  ROR A
  STA T6                       ; (row * 128) low
  LDA SCR
  LSR A
  STA T7                       ;             high
  LDA PTR
  CLC
  ADC T6
  STA PTR
  LDA PTR+1
  ADC T7
  STA PTR+1
  RTS

; steps 1 and 2: the row of the scanner into the VRAM (patterns, colours)
SCAN_UP_P:
  LDA #<SCAN_P
  LDY #>SCAN_P
  LDX #($04 | VDP_WRITE_VRAM_BIT)
  BRA SCAN_UP
SCAN_UP_C:
  LDA #<SCAN_C
  LDY #>SCAN_C
  LDX #($24 | VDP_WRITE_VRAM_BIT)
SCAN_UP:
  STX T5
  JSR ROW_PTR
  LDA T6                       ; VRAM: tile 128 + row * 16 -> + row * 128, + half
  ORA SCH
  STA VREG
  LDA T5
  CLC
  ADC T7
  STA VREG
  LDY SCH
  LDX #64
.su_l:
  LDA (PTR),Y
  STA VDATA
  INY
  DEX
  BNE .su_l
  RTS


; ===============================================================
;  SPRITES: the ship first, then the objects on the screen; the list
;  starts from a different object every frame, so with more than 4
;  sprites on a line they flicker instead of disappearing
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA SHIPST
  BEQ .bs_ship
  CMP #$03
  BEQ .bs_list
  CMP #$02
  BEQ .bs_list
  JMP .bs_list                 ; (exploding: the explosion is an object)
.bs_ship:
  LDA SHSX
  STA OX
  LDA SHY
  STA OY
  LDA FACE
  ASL A
  ASL A
  STA ON
  LDA #$0F
  LDX INVIS                    ; Inviso: two shades of blue
  BEQ .bs_c
  LDA FRAME_CNT
  AND #$04
  LSR A
  LSR A
  ORA #$04
.bs_c:
  STA OC
  JSR ADD_SPR
  LDA THR                      ; flame behind the ship, flickering
  BEQ .bs_list
  LDA FRAME_CNT
  AND #$02
  BEQ .bs_list
  LDA SHSX
  LDX FACE
  BNE .bs_fl
  SEC
  SBC #16
  BCC .bs_list
  BRA .bs_fx
.bs_fl:
  CLC
  ADC #16
  BCS .bs_list
.bs_fx:
  STA OX
  LDA FACE
  ASL A
  ASL A
  CLC
  ADC #8
  STA ON
  LDA FRAME_CNT
  LSR A
  LSR A
  AND #$03
  TAX
  LDA FLAME_COL,X
  STA OC
  JSR ADD_SPR
.bs_list:
  ; ---- the stargate, its colours going round
  LDA #SG_XL
  SEC
  SBC CAMXL
  STA OX
  LDA #SG_XH
  SBC CAMXH
  AND #$07
  BNE .bs_ng
  LDA #SG_Y
  STA OY
  LDA #76
  STA ON
  LDA FRAME_CNT
  LSR A
  LSR A
  AND #$03
  TAX
  LDA GATE_COL,X
  STA OC
  JSR ADD_SPR
.bs_ng:
  ; ---- enemies, humanoids, shots, explosions: forwards on even frames,
  ;      backwards on odd ones, so the sprites dropped on a full line change
  LDA #NE
  JSR ORDER_SET
.be_l:
  LDA E_T,Y
  BEQ .be_n
  LDA E_ON,Y
  BEQ .be_n
  PHY
  TYA
  TAX
  JSR OBJ_E
  PLY
.be_n:
  TYA
  CLC
  ADC BSTEP
  TAY
  CPY BEND
  BNE .be_l
  LDA SPACE                    ; (no humanoids in free space)
  BNE .bh_x
  STZ HDRAWN
  LDA #NH
  JSR ORDER_SET
.bh_l:
  LDA H_ST,Y
  BEQ .bh_n
  CMP #4                       ; the ones carried by the ship: just one sprite
  BNE .bh_c
  LDA HDRAWN
  BNE .bh_n
  INC HDRAWN
.bh_c:
  LDA H_ON,Y
  BEQ .bh_n
  PHY
  TYA
  TAX
  JSR OBJ_H
  PLY
.bh_n:
  TYA
  CLC
  ADC BSTEP
  TAY
  CPY BEND
  BNE .bh_l
.bh_x:
  LDX #(NB-1)
.bb_l:
  LDA B_T,X
  BEQ .bb_n
  PHX
  JSR OBJ_B
  PLX
.bb_n:
  DEX
  BPL .bb_l
  LDX #(NX-1)
.bx_l:
  LDA X_T,X
  BEQ .bx_n
  PHX
  JSR OBJ_X
  PLX
.bx_n:
  DEX
  BPL .bx_l
.bs_end:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; A = number of objects: Y = first one, BSTEP = +1 on even frames, -1 on odd ones,
; BEND = where the loop stops
ORDER_SET:
  STA BEND
  LDY #$00
  LDA #$01
  STA BSTEP
  LDA FRAME_CNT
  LSR A
  BCC .os_r
  LDY BEND
  DEY
  LDA #$FF
  STA BSTEP
  STA BEND
.os_r:
  RTS

; enemy X: sprite (the list is full: nothing)
OBJ_E:
  LDA SPRI
  CMP #(31*4)
  BCS .oe_r
  LDA E_SX,X
  STA OX
  LDA E_Y,X
  STA OY
  LDY E_T,X
  LDA SPR_NAME,Y
  STA ON
  LDA ANIM,Y                   ; two frames: legs, tails, mouths, turning
  BEQ .oe_ne
  LDA FRAME_CNT
  AND #$08
  LSR A
  CLC
  ADC ON
  STA ON
.oe_ne:
  CPY #9                       ; guppies swimming to the right: mirrored
  BNE .oe_g
  LDA E_VXH,X
  BMI .oe_g
  LDA ON
  CLC
  ADC #32
  STA ON
.oe_g:
  LDA SPR_COL,Y
  CPY #8                       ; fireballs flicker
  BNE .oe_c
  LDA FRAME_CNT
  AND #$03
  TAY
  LDA FLAME_COL,Y
.oe_c:
  STA OC
  JMP ADD_SPR
.oe_r:
  RTS

; humanoid X
OBJ_H:
  LDA SPRI
  CMP #(31*4)
  BCS .o_r
  LDA H_SX,X
  STA OX
  LDA H_Y,X
  STA OY
  LDA #48
  STA ON
  LDA #$09
  STA OC
  JMP ADD_SPR

.o_r:
  RTS

; shot or mine X
OBJ_B:
  BRA .ob_go
.o_r:
  RTS
.ob_go:
  LDA SPRI
  CMP #(31*4)
  BCS .o_r
  LDA B_XL,X
  SEC
  SBC CAMXL
  STA OX
  LDA B_XH,X
  SBC CAMXH
  AND #$07
  BNE .o_r
  LDA B_Y,X
  STA OY
  LDA B_K,X
  ASL A
  ASL A
  CLC
  ADC #52
  STA ON
  LDA FRAME_CNT
  AND #$04
  BEQ .ob_w
  LDA #$0B
  BRA .ob_c
.ob_w:
  LDA #$0F
.ob_c:
  STA OC
  JMP ADD_SPR

; explosion X
OBJ_X:
  BRA .ox_go
.o_r:
  RTS
.ox_go:
  LDA SPRI
  CMP #(31*4)
  BCS .o_r
  LDA X_XL,X
  SEC
  SBC CAMXL
  STA OX
  LDA X_XH,X
  SBC CAMXH
  AND #$07
  BNE .o_r
  LDA X_Y,X
  STA OY
  LDA X_T,X
  LSR A
  LSR A
  LSR A
  ASL A
  ASL A
  CLC
  ADC #60
  STA ON
  LDA FRAME_CNT
  AND #$03
  TAY
  LDA FLAME_COL,Y
  STA OC
  ; fall into ADD_SPR

; a 16x16 sprite centred on (OX, OY), pattern ON, colour OC
ADD_SPR:
  LDX SPRI
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
  RTS

HIDE_SPRITES:
  LDA #$D0
  STA SAT_BUFFER
  LDA #1
  STA SATB
  RTS

; title: page TPAGE of the scoring table (rows 6-13), text and sprites
TITLE_PAGE:
  LDA #240
  STA TCNT
  LDX #6                       ; clear rows 6-13
  LDY #0
  JSR NT_XY
  LDX #128
  LDA #0
.tp_c:
  STA VDATA
  STA VDATA
  DEX
  BNE .tp_c
  LDX TPAGE
  LDA TPG_LO,X
  STA TP
  LDA TPG_HI,X
  STA TP+1
  JSR PRINT
  LDA TPAGE                    ; X = first entry of the page
  ASL A
  ASL A
  ASL A
  TAX
  LDY #$00
.tp_s:
  TXA
  AND #$07
  ASL A
  ASL A
  ASL A
  CLC
  ADC #(6*8-5)
  STA SAT_BUFFER,Y
  LDA #68
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
  TXA
  AND #$07
  BNE .tp_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
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
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI


; ===============================================================
;  SOUND: effects only (no music on the cabinet)
;  per chip: A = tone effects, B = noise (explosions, thrust),
;  C = low tone of the explosions
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
.st_run:
  JSR SFX_TICK
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
  ; ---- channel A: tone effect, otherwise the hum of the Inviso
  LDA WH_ID,X
  BEQ .sf_inv
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
.sf_inv:
  LDA SND_INV
  BEQ .sf_noise
  LDA SND_PH                    ; two low notes, 4 frames each
  AND #$04
  ASL A
  ASL A
  ADC #$60                      ; (period $160 / $170, about 175 Hz)
  STA SH_L,Y
  LDA #$01
  STA SH_L+1,Y
  LDA #$07
  STA SH_L+8,Y
.sf_noise:
  ; ---- channels B and C: explosion, otherwise the thrust
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
  BEQ .sf_next
  LDA SND_RND
  AND #$03
  CLC
  ADC #$0C
  STA SH_L+6,Y                  ; thrust: low noise
  LDA #$09
  STA SH_L+9,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_done
  JMP .sf_chip
.sf_done:
  RTS

; A = tone effect, Y = X on the screen: on that side
SFX_AT:
  LDX #$00
  CPY #$80
  BCC .sa_l
  INX
.sa_l:
  JMP SFX_WHISTLE

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
; by kind of enemy: 0 -, 1 lander, 2 mutant, 3 bomber, 4 pod, 5 swarmer, 6 baiter,
; 7 firebomber, 8 fireball, 9 guppy, 10 dynamo, 11 space hum, 12 Phred, 13 Big Red, 14 munchie
E_LOGIC:    .word 0,LANDER,MUTANT,BOMBER,POD,SWARMER,BAITER
            .word FIREBOMBER,FIREBALL,GUPPY,DYNAMO,HUM,PHRED,PHRED,MUNCHIE
SPR_NAME:   .byte 0,16,24,32,36,40,44,80,88,92,100,104,108,112,116
ANIM:       .byte 0,1,1,0,0,0,0,1,0,1,0,0,0,0,1                     ; 1 = two frames
SPR_COL:    .byte 0,$03,$0D,$05,$08,$09,$02,$0A,$0B,$07,$0C,$0F,$0E,$06,$0B
SCAN_COL:   .byte 0,$30,$D0,$50,$80,$90,$20,$A0,$B0,$70,$C0,$F0,$E0,$60,$B0  ; colour of the dot in the scanner
SPAWN_VX:   .byte 0,$70,$80,$60,$50,$C0,$C0,$90,0,$A0,$40,$60,$C0,$C0,$A0  ; starting speed (1/256 px per frame)
SPAWN_VY:   .byte 0,$40,$60,$50,$40,$80,$80,$A0,0,$60,$40,$60,$80,$80,$80
FIRE_RATE:  .byte 0,2,4,0,0,2,6,0,0,0,0,0,0,0,0                     ; shots per 256 frames on the screen
KILL_PL:    .byte 0,$50,$50,$50,$00,$50,$00,$50,$00,$00,$00,$00,$00,$00,$50  ; points (BCD)
KILL_PM:    .byte 0,$01,$01,$02,$10,$01,$02,$02,$01,$02,$02,$01,$02,$02,$00
COUNTS:     .byte 0,1,1,1,1,1,0,1,0,1,1,0,0,0,0                     ; 1 = must die to end the wave
TIMED_K:    .byte 6,12,13                                           ; a wave too long: baiter, Phred, Big Red
CATCH_PM:   .byte 0,$05,$10,$15,$20                                 ; humanoid caught: 500 x humanoids carried
JITTER:     .byte $FF,$01                      ; the mutants shake, the guppies swim
FLAME_COL:  .byte $08,$0A,$09,$0B
GATE_COL:   .byte $0B,$0F,$07,$0D
TW_LO:      .byte <TW0,<TW1,<TW2,<TW3       ; mountains: tiles by shift
TW_HI:      .byte >TW0,>TW1,>TW2,>TW3
HUM_XL:     .byte 20,224,172,120,68,16,220,168,116,64   ; humanoids: i * 204 + 20
HUM_XH:     .byte 0,0,1,2,3,4,4,5,6,7
; players: the variables saved for each one (zero page addresses)
PV_LIST:    .byte SCORE,SCORE+1,SCORE+2,LIVES,BOMBS,INVE,NEXTX,WAVE,PLANET,HUMANS,LEFTL
PV_N        = 11
PV_LIVES    = 3                ; (position of LIVES in PV_LIST)
PS_OFF:     .byte 0,48
; laser tiles 240-247: a line on line 0-7, colours of the laser
LASER_PAT:
  .byte $FF,0,0,0,0,0,0,0, 0,$FF,0,0,0,0,0,0, 0,0,$FF,0,0,0,0,0, 0,0,0,$FF,0,0,0,0
  .byte 0,0,0,0,$FF,0,0,0, 0,0,0,0,0,$FF,0,0, 0,0,0,0,0,0,$FF,0, 0,0,0,0,0,0,0,$FF
LASER_COLS:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0, $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $70,$70,$70,$70,$70,$70,$70,$70, $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0, $70,$70,$70,$70,$70,$70,$70,$70
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0, $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
ICON_COL:                      ; spare ship, smart bomb, line under the scanner, Inviso bar
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $90,$90,$90,$90,$90,$90,$90,$90
  .byte $50,$50,$50,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$70,$70,$70,$70,$70, $70,$70,$70,$70,$70,$70,$70,$70, $70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70, $70,$70,$70,$70,$70,$70,$70,$70, $70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70, $70,$70,$70,$70,$70,$70,$70,$70, $70,$70,$70,$70,$70,$70,$70,$70
; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT          ; font, thirds 0 and 1 (tiles 32-95)
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0                 ; white
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $00,$43, 96,0, <ICON_SHIP,>ICON_SHIP      ; tiles 96-107
  .byte 1, $00,$63, 96,0, <ICON_COL,>ICON_COL
  .byte 1, $80,$47, 64,0, <LASER_PAT,>LASER_PAT      ; laser tiles in the three thirds
  .byte 1, $80,$4F, 64,0, <LASER_PAT,>LASER_PAT
  .byte 1, $80,$57, 64,0, <LASER_PAT,>LASER_PAT
  .byte 1, $80,$67, 64,0, <LASER_COLS,>LASER_COLS
  .byte 1, $80,$6F, 64,0, <LASER_COLS,>LASER_COLS
  .byte 1, $80,$77, 64,0, <LASER_COLS,>LASER_COLS
  .byte 1, $08,$50, <(TERR_TILES*8),>(TERR_TILES*8), <TERR_PAT,>TERR_PAT   ; mountains (third 2, tile 1-)
  .byte 2, $08,$70, <(TERR_TILES*8),>(TERR_TILES*8), $90,0                 ; light red
  .byte 0
; title: the two pages of the scoring table (sprite pattern, colour; 8 per page)
TITLE_SN:   .byte 16,24,32,36,40,44,80,88
            .byte 92,100,104,108,112,116,48,132
TITLE_SC:   .byte $03,$0D,$05,$08,$09,$02,$0A,$0B
            .byte $07,$0C,$0F,$0E,$06,$0B,$09,$0B
TPG_LO:     .byte <TXT_PAGE1,<TXT_PAGE2
TPG_HI:     .byte >TXT_PAGE1,>TXT_PAGE2

; text records: row, column, characters, 0   (end of list: $FF)
TXT_HUD:
  .byte 0,22,"HI",0
  .byte 1,24,"WAVE",0
  .byte $FF
TXT_TITLE:
  .byte 4,8,"S T A R G A T E",0
  .byte 14,1,"B1 FIRE B2 BOMB  HOLD B2 INVISO",0
  .byte 15,1,"B1+B2 HYPER   B1=1 PL  B2=2 PL",0
  .byte $FF
TXT_PAGE1:
  .byte 6,11,"LANDER       150",0
  .byte 7,11,"MUTANT       150",0
  .byte 8,11,"BOMBER       250",0
  .byte 9,11,"POD         1000",0
  .byte 10,11,"SWARMER      150",0
  .byte 11,11,"BAITER       200",0
  .byte 12,11,"FIREBOMBER   250",0
  .byte 13,11,"FIREBALL     100",0
  .byte $FF
TXT_PAGE2:
  .byte 6,11,"YLLABIAN     200",0
  .byte 7,11,"DYNAMO       200",0
  .byte 8,11,"SPACE HUM    100",0
  .byte 9,11,"PHRED        200",0
  .byte 10,11,"BIG RED      200",0
  .byte 11,11,"MUNCHIE       50",0
  .byte 12,11,"HUMANOID     500",0
  .byte 13,11,"STARGATE",0
  .byte $FF
TXT_PLAYER:
  .byte 7,11,"PLAYER ",0
  .byte $FF
TXT_WAVE:
  .byte 9,9,"ATTACK WAVE",0
  .byte $FF
TXT_DOG:
  .byte 11,7,"YLLABIAN DOGFIGHT",0
  .byte $FF
TXT_SHOW:
  .byte 11,6,"FIREBOMBER SHOWDOWN",0
  .byte $FF
TXT_DONE:
  .byte 8,9,"ATTACK WAVE",0
  .byte 9,11,"COMPLETED",0
  .byte 10,9,"HUMANOIDS",0
  .byte $FF
TXT_WARP:
  .byte 8,9,"STARGATE WARP",0
  .byte 10,9,"HUMANOIDS",0
  .byte 11,9,"BONUS  X 2000",0
  .byte $FF
TXT_OVER1:
  .byte 9,11,"GAME OVER",0
  .byte $FF
TXT_OVER:
  .byte 9,11,"GAME OVER",0
  .byte 11,9,"PRESS A BUTTON",0
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
; terrain of the third 2: tile 0 blank, then 9 segments (upper, lower tile), then
; 33 joined pairs for the shifts of 2, 4, 6 pixels (upper, lower tile)
TERR_TILES = 216
TERR_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$06,$08,$10,$60,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$40,$30,$08,$04,$03,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$06,$08,$10,$60,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$40,$30,$08,$04,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$14,$22,$41,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$41,$22,$14,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$FE,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$05,$18,$20,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$04,$18,$20,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$02,$04,$18,$20,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$02,$04,$18,$20,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$05,$18,$20,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$20,$10,$0C,$03,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$20,$10,$0D,$02,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FE,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$FE,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$FE,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FE,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$05,$18,$20,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$04,$18,$20,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$20,$10,$0C,$02,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$20,$10,$0C,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$20,$10,$0D,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$20,$10,$0D,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$20,$10,$0C,$02,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FE,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$50,$88,$04,$02,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$50,$88,$04,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$50,$88,$05,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$50,$88,$05,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$50,$88,$04,$02,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$05,$88,$50,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$04,$88,$50,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$02,$04,$88,$50,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$02,$04,$88,$50,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$05,$88,$50,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$06,$F8,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$14,$63,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0F,$10,$60,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$06,$08,$10,$60,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$04,$08,$10,$60,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$14,$62,$81,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$30,$0F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$41,$36,$08,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$F8,$04,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$06,$F8,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$04,$F8,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$F8,$04,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$08,$14,$63,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$0F,$10,$60,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$30,$08,$04,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$30,$0F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$41,$36,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$81,$42,$34,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$30,$08,$04,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$F8,$04,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$20,$10,$08,$04,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$20,$10,$0F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$21,$16,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$41,$22,$14,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$20,$10,$08,$04,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$14,$23,$40,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0F,$10,$20,$40,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$06,$08,$10,$20,$40,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$04,$08,$10,$20,$40,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$14,$22,$41,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$04,$18,$E0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$50,$8C,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$3F,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$04,$18,$20,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$05,$08,$10,$20,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$50,$88,$05,$02,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$3F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$04,$D8,$20,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$E0,$10,$0C,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$04,$18,$E0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$05,$08,$10,$E0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$E0,$10,$08,$05,$02,$00,$00,$00,$00
  .byte $00,$20,$50,$8C,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$3F,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$20,$10,$0C,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$3F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$04,$D8,$20,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$05,$08,$D0,$20,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$20,$10,$08,$05,$02,$00,$00,$00,$00
  .byte $00,$E0,$10,$0C,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$20,$10,$0C,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$3F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$84,$58,$20,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$05,$88,$50,$20,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$20,$10,$08,$05,$02,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$50,$8C,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$3F,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$04,$18,$20,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$05,$08,$10,$20,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$50,$88,$05,$02,$00,$00,$00,$00
TW0:                    ; upper tile of every column, shift 0 px (lower tile = + 1)
  .byte $01,$01,$01,$03,$11,$09,$0D,$0D,$0B,$11,$09,$0B,$09,$0D,$0B,$07
  .byte $09,$0D,$0D,$0D,$0B,$09,$0D,$0D,$0D,$0D,$0B,$0F,$05,$01,$03,$0F
  .byte $05,$03,$09,$0B,$07,$0F,$09,$0B,$11,$11,$05,$03,$11,$05,$03,$11
  .byte $0F,$05,$01,$03,$05,$03,$07,$05,$03,$0F,$11,$07,$05,$03,$09,$0B
  .byte $11,$09,$0B,$07,$09,$0B,$05,$01,$03,$11,$09,$0D,$0B,$0F,$05,$03
  .byte $0F,$05,$03,$07,$05,$03,$07,$0F,$09,$0B,$05,$03,$07,$0F,$11,$05
  .byte $01,$01,$01,$03,$11,$09,$0B,$05,$01,$03,$09,$0B,$11,$07,$09,$0B
  .byte $11,$11,$09,$0D,$0B,$11,$07,$11,$11,$07,$0F,$0F,$11,$07,$0F,$11
  .byte $05,$03,$0F,$05,$03,$09,$0B,$09,$0B,$11,$0F,$05,$01,$03,$07,$09
  .byte $0D,$0B,$0F,$11,$07,$05,$01,$03,$07,$05,$01,$03,$11,$11,$09,$0B
  .byte $11,$05,$03,$05,$01,$01,$03,$05,$01,$03,$0F,$09,$0D,$0B,$09,$0B
  .byte $05,$01,$01,$03,$11,$11,$09,$0B,$05,$03,$09,$0B,$05,$01,$01,$03
  .byte $09,$0D,$0B,$11,$07,$0F,$05,$01,$01,$01,$03,$11,$0F,$07,$05,$03
  .byte $09,$0B,$0F,$05,$01,$03,$05,$03,$09,$0B,$07,$11,$11,$0F,$09,$0B
  .byte $09,$0B,$05,$01,$03,$11,$11,$09,$0B,$11,$05,$03,$11,$11,$11,$0F
  .byte $07,$0F,$11,$0F,$0F,$05,$03,$05,$03,$0F,$05,$01,$03,$05,$03,$05
TW1:                    ; upper tile of every column, shift 2 px (lower tile = + 1)
  .byte $13,$13,$15,$1F,$4F,$31,$3F,$3D,$3B,$4F,$2F,$37,$31,$3D,$35,$29
  .byte $31,$3F,$3F,$3D,$37,$31,$3F,$3F,$3F,$3D,$39,$41,$21,$15,$1D,$41
  .byte $23,$1B,$2F,$35,$2B,$45,$2F,$3B,$53,$4B,$23,$1F,$4B,$23,$1F,$51
  .byte $41,$21,$15,$17,$23,$19,$25,$23,$1D,$49,$4D,$25,$23,$1B,$2F,$3B
  .byte $4F,$2F,$35,$29,$2F,$33,$21,$15,$1F,$4F,$31,$3D,$39,$41,$23,$1D
  .byte $41,$23,$19,$25,$23,$19,$2B,$45,$2F,$33,$23,$19,$2B,$49,$4B,$21
  .byte $13,$13,$15,$1F,$4F,$2F,$33,$21,$15,$1B,$2F,$3B,$4D,$29,$2F,$3B
  .byte $53,$4F,$31,$3D,$3B,$4D,$2D,$53,$4D,$2B,$47,$49,$4D,$2B,$49,$4B
  .byte $23,$1D,$41,$23,$1B,$2F,$37,$2F,$3B,$51,$41,$21,$15,$19,$29,$31
  .byte $3D,$39,$49,$4D,$25,$21,$15,$19,$25,$21,$15,$1F,$53,$4F,$2F,$3B
  .byte $4B,$23,$17,$21,$13,$15,$17,$21,$15,$1D,$45,$31,$3D,$37,$2F,$33
  .byte $21,$13,$15,$1F,$53,$4F,$2F,$33,$23,$1B,$2F,$33,$21,$13,$15,$1B
  .byte $31,$3D,$3B,$4D,$2B,$41,$21,$13,$13,$15,$1F,$51,$43,$25,$23,$1B
  .byte $2F,$39,$41,$21,$15,$17,$23,$1B,$2F,$35,$2D,$53,$51,$45,$2F,$37
  .byte $2F,$33,$21,$15,$1F,$53,$4F,$2F,$3B,$4B,$23,$1F,$53,$53,$51,$43
  .byte $2B,$49,$51,$47,$41,$23,$17,$23,$1D,$41,$21,$15,$17,$23,$17,$21
TW2:                    ; upper tile of every column, shift 4 px (lower tile = + 1)
  .byte $55,$55,$57,$61,$91,$73,$81,$7F,$7D,$91,$71,$79,$73,$7F,$77,$6B
  .byte $73,$81,$81,$7F,$79,$73,$81,$81,$81,$7F,$7B,$83,$63,$57,$5F,$83
  .byte $65,$5D,$71,$77,$6D,$87,$71,$7D,$95,$8D,$65,$61,$8D,$65,$61,$93
  .byte $83,$63,$57,$59,$65,$5B,$67,$65,$5F,$8B,$8F,$67,$65,$5D,$71,$7D
  .byte $91,$71,$77,$6B,$71,$75,$63,$57,$61,$91,$73,$7F,$7B,$83,$65,$5F
  .byte $83,$65,$5B,$67,$65,$5B,$6D,$87,$71,$75,$65,$5B,$6D,$8B,$8D,$63
  .byte $55,$55,$57,$61,$91,$71,$75,$63,$57,$5D,$71,$7D,$8F,$6B,$71,$7D
  .byte $95,$91,$73,$7F,$7D,$8F,$6F,$95,$8F,$6D,$89,$8B,$8F,$6D,$8B,$8D
  .byte $65,$5F,$83,$65,$5D,$71,$79,$71,$7D,$93,$83,$63,$57,$5B,$6B,$73
  .byte $7F,$7B,$8B,$8F,$67,$63,$57,$5B,$67,$63,$57,$61,$95,$91,$71,$7D
  .byte $8D,$65,$59,$63,$55,$57,$59,$63,$57,$5F,$87,$73,$7F,$79,$71,$75
  .byte $63,$55,$57,$61,$95,$91,$71,$75,$65,$5D,$71,$75,$63,$55,$57,$5D
  .byte $73,$7F,$7D,$8F,$6D,$83,$63,$55,$55,$57,$61,$93,$85,$67,$65,$5D
  .byte $71,$7B,$83,$63,$57,$59,$65,$5D,$71,$77,$6F,$95,$93,$87,$71,$79
  .byte $71,$75,$63,$57,$61,$95,$91,$71,$7D,$8D,$65,$61,$95,$95,$93,$85
  .byte $6D,$8B,$93,$89,$83,$65,$59,$65,$5F,$83,$63,$57,$59,$65,$59,$63
TW3:                    ; upper tile of every column, shift 6 px (lower tile = + 1)
  .byte $97,$97,$99,$A3,$D3,$B5,$C3,$C1,$BF,$D3,$B3,$BB,$B5,$C1,$B9,$AD
  .byte $B5,$C3,$C3,$C1,$BB,$B5,$C3,$C3,$C3,$C1,$BD,$C5,$A5,$99,$A1,$C5
  .byte $A7,$9F,$B3,$B9,$AF,$C9,$B3,$BF,$D7,$CF,$A7,$A3,$CF,$A7,$A3,$D5
  .byte $C5,$A5,$99,$9B,$A7,$9D,$A9,$A7,$A1,$CD,$D1,$A9,$A7,$9F,$B3,$BF
  .byte $D3,$B3,$B9,$AD,$B3,$B7,$A5,$99,$A3,$D3,$B5,$C1,$BD,$C5,$A7,$A1
  .byte $C5,$A7,$9D,$A9,$A7,$9D,$AF,$C9,$B3,$B7,$A7,$9D,$AF,$CD,$CF,$A5
  .byte $97,$97,$99,$A3,$D3,$B3,$B7,$A5,$99,$9F,$B3,$BF,$D1,$AD,$B3,$BF
  .byte $D7,$D3,$B5,$C1,$BF,$D1,$B1,$D7,$D1,$AF,$CB,$CD,$D1,$AF,$CD,$CF
  .byte $A7,$A1,$C5,$A7,$9F,$B3,$BB,$B3,$BF,$D5,$C5,$A5,$99,$9D,$AD,$B5
  .byte $C1,$BD,$CD,$D1,$A9,$A5,$99,$9D,$A9,$A5,$99,$A3,$D7,$D3,$B3,$BF
  .byte $CF,$A7,$9B,$A5,$97,$99,$9B,$A5,$99,$A1,$C9,$B5,$C1,$BB,$B3,$B7
  .byte $A5,$97,$99,$A3,$D7,$D3,$B3,$B7,$A7,$9F,$B3,$B7,$A5,$97,$99,$9F
  .byte $B5,$C1,$BF,$D1,$AF,$C5,$A5,$97,$97,$99,$A3,$D5,$C7,$A9,$A7,$9F
  .byte $B3,$BD,$C5,$A5,$99,$9B,$A7,$9F,$B3,$B9,$B1,$D7,$D5,$C9,$B3,$BB
  .byte $B3,$B7,$A5,$99,$A3,$D7,$D3,$B3,$BF,$CF,$A7,$A3,$D7,$D7,$D5,$C7
  .byte $AF,$CD,$D5,$CB,$C5,$A7,$9B,$A7,$A1,$C5,$A5,$99,$9B,$A7,$9B,$A5

; HUD tiles 96-107: spare ship, smart bomb, line under the scanner, Inviso bar 0-8 pixels
ICON_SHIP:
  .byte $00,$80,$C0,$F8,$FF,$7C,$00,$00
ICON_BOMB:
  .byte $00,$38,$7C,$7C,$7C,$38,$00,$00
HLINE:
  .byte $00,$00,$00,$00,$00,$00,$FF,$00
BAR_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$00,$00
  .byte $00,$00,$C0,$C0,$C0,$C0,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$00,$00
  .byte $00,$00,$F0,$F0,$F0,$F0,$00,$00,$00,$00,$F8,$F8,$F8,$F8,$00,$00
  .byte $00,$00,$FC,$FC,$FC,$FC,$00,$00,$00,$00,$FE,$FE,$FE,$FE,$00,$00
  .byte $00,$00,$FF,$FF,$FF,$FF,$00,$00

; sprites 16x16: ship R/L, flame R/L, lander x2, mutant x2, bomber, pod, swarmer, baiter,
; humanoid, bullet, mine, 4 explosion frames, stargate, firebomber x2, fireball,
; guppy x2, dynamo, space hum, Phred, Big Red, munchie x2, guppy swimming right x2
SPR_PAGES = 5
SPRITES:
  .byte $00,$00,$00,$00,$00,$C0,$F0,$FE,$FF,$FF,$3F,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FE,$FC,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$7F,$3F,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$0F,$7F,$FF,$FF,$FC,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$0F,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$F0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0A,$1F,$0F,$04,$08,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$A0,$F0,$E0,$40,$20,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0D,$1F,$0F,$04,$04,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$60,$F0,$E0,$40,$40,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$13,$0F,$1B,$1F,$0A,$14,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$90,$E0,$B0,$F0,$A0,$50,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$1B,$1F,$0F,$15,$08,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$B0,$F0,$E0,$50,$20,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$0F,$0A,$0F,$09,$0F,$0A,$0F,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$F0,$50,$F0,$90,$F0,$50,$F0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$05,$0F,$05,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$E0,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$07,$03,$05,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$C0,$80,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$07,$35,$7F,$35,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$E0,$AC,$FE,$AC,$E0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$01,$03,$02,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$00,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$01,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$00,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$06,$08,$02,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$40,$40,$00,$20,$40,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$04,$02,$14,$20,$04,$00,$00,$00,$02,$00,$00
  .byte $00,$00,$00,$00,$00,$40,$60,$00,$00,$00,$10,$00,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$04,$00,$28,$80,$00,$08,$00,$00,$00,$00,$02
  .byte $00,$00,$00,$00,$20,$20,$10,$00,$00,$00,$08,$08,$00,$20,$20,$00
  .byte $00,$00,$FF,$80,$BF,$A0,$AF,$A8,$A8,$AF,$A0,$BF,$80,$FF,$00,$00
  .byte $00,$00,$FF,$01,$FD,$05,$F5,$15,$15,$F5,$05,$FD,$01,$FF,$00,$00
  .byte $00,$00,$00,$00,$08,$07,$04,$05,$04,$07,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$C0,$40,$40,$40,$C0,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$04,$0D,$04,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$60,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$C0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0F,$17,$3F,$1F,$0F,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C4,$EC,$F0,$EC,$C4,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0F,$17,$3F,$1F,$0F,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$EC,$F8,$EC,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$05,$0A,$05,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$A0,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$01,$00,$01,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$20,$40,$80,$40,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$0F,$1F,$13,$15,$1F,$18,$10,$0F,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$E0,$F0,$90,$50,$F0,$30,$10,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$1F,$17,$1B,$12,$1F,$15,$1A,$0F,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$F0,$D0,$B0,$90,$F0,$50,$B0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$07,$07,$07,$03,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$E0,$80,$00,$80,$E0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$07,$07,$07,$03,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$E0,$F0,$F0,$F0,$E0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$23,$37,$0F,$37,$23,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$F0,$E8,$FC,$F8,$F0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$37,$1F,$37,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$F0,$E8,$FC,$F8,$F0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$FF,$80,$BF,$A0,$A0,$BF,$80,$FF,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$FF,$01,$FD,$05,$05,$FD,$01,$FF,$00,$00,$00,$00
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

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$1C,$1F,$23,$28,$2E,$37,$44,$58,$7D,$D0,$AA,$90,$7D,$6E,$63
  .byte $59,$52,$4B,$45,$D0,$AA,$90,$7D,$6E,$63,$59,$52,$4B,$45,$27,$28
  .byte $29,$2B,$2C,$2D,$2F,$31,$32,$34,$36,$39,$3B,$3E,$41,$44,$47,$4B
  .byte $4F,$54,$5A,$60,$67,$6F,$79,$85,$93,$A4,$BA,$D7,$FF,$39,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$50,$50
  .byte $50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$2F,$2F
  .byte $2F,$2F,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$28,$28,$00,$00,$00,$00
  .byte $28,$28,$28,$28,$28,$28,$00,$00,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$39,$B4,$7E,$61,$4F,$43,$3A,$33,$2D,$29,$25,$22
  .byte $20,$1E,$1C,$1A,$18,$17,$16,$15,$78,$78,$78,$78,$78,$78,$78,$78
  .byte $5F,$5F,$5F,$5F,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $45,$40,$3B,$37,$33,$30,$26,$DE,$81,$6B,$80,$70,$48,$41,$52,$4B
  .byte $32,$2E,$3C,$38,$26,$24,$30,$2D,$1F,$1E,$27,$26,$1A,$19,$22,$20
  .byte $16,$16,$1D,$1C,$23,$26,$2B,$31,$38,$42,$51,$68,$23,$20,$1D,$1B
  .byte $1A,$18
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00
WH_VOL:
  .byte $00,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$0A,$0A,$0A,$0B,$0B,$0B
  .byte $0B,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$0A,$0A
  .byte $0A,$0A,$09,$09,$09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08
  .byte $08,$08,$07,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06,$0C,$0B
  .byte $0B,$0A,$0A,$09,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$0C,$0B
  .byte $0B,$0A,$0A,$09,$0C,$0B,$0B,$0A,$0A,$09,$0C,$0B,$0A,$0A,$09,$08
  .byte $07,$06,$05,$05,$04,$03,$0D,$0C,$0B,$0B,$0A,$09,$00,$00,$00,$00
  .byte $0D,$0C,$0B,$0B,$0A,$09,$00,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$08
  .byte $07,$06,$05,$04,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06
  .byte $06,$06,$05,$05,$04,$04,$03,$03,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09
  .byte $0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09
  .byte $0C,$0B,$0B,$0A,$0A,$09,$08,$08,$07,$07,$06,$05,$05,$04,$04,$03
  .byte $08,$07,$06,$05,$04,$03,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B
  .byte $0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07
  .byte $07,$06,$06,$06,$0B,$0A,$09,$08,$08,$07,$06,$05,$0A,$09,$08,$08
  .byte $07,$06
WH_START:
  .byte $00,$01,$0A,$1E,$3E,$4E,$66,$84,$98,$C0,$C6,$E4,$EC
WH_LEN:
  .byte $00,$09,$14,$20,$10,$18,$1E,$14,$28,$06,$1E,$08,$06
W_LASER = 1
W_GRAB = 2
W_FALL = 3
W_CATCH = 4
W_SAVE = 5
W_EXTRA = 6
W_HYPER = 7
W_WAVE = 8
W_SHOT = 9
W_GATE = 10
W_FIREB = 11
W_INV = 12

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0D,$0C,$0B,$0B,$0A,$09,$09,$08,$07,$07,$06,$05
  .byte $05,$04,$03,$03,$02,$01,$01,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E
  .byte $0E,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B
  .byte $0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$07
  .byte $07,$07,$07,$07,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$04,$04
  .byte $04,$04,$04,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$01,$01,$01
  .byte $01,$01,$00,$00,$00,$00,$00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D
  .byte $0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09
  .byte $09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05
  .byte $05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01
  .byte $01,$01,$01
EX_NP:
  .byte $00,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09
  .byte $09,$0A,$0A,$0A,$0A,$0B,$0B,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F
  .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$10,$10,$10,$10,$10,$10,$10,$10,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$12,$12,$12,$12,$12,$12,$12,$12,$13
  .byte $13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$15
  .byte $15,$15,$15,$15,$15,$15,$15,$14,$14,$14,$14,$14,$14,$14,$14,$15
  .byte $15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17
  .byte $17,$17,$17,$17,$17,$17,$17,$18,$18,$18,$18,$18,$18,$18,$18,$19
  .byte $19,$19,$19,$19,$19,$19,$19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1B
  .byte $1B,$1B,$1B
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B
  .byte $0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07
  .byte $07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03
  .byte $03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C
  .byte $0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08
  .byte $08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04
  .byte $04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00
  .byte $00,$00,$00
EX_TL:
  .byte $00,$D0,$D8,$DF,$E7,$F0,$FA,$04,$10,$1C,$2A,$39,$49,$5B,$70,$87
  .byte $A1,$BE,$E1,$09,$38,$71,$B6,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D
  .byte $6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D
  .byte $6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D
  .byte $6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D
  .byte $6D,$6D,$6D
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$02,$02,$02,$02,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05
EX_START:
  .byte $00,$01,$17,$67
EX_LEN:
  .byte $00,$16,$50,$3C
S_SMALL = 1
S_SHIP = 2
S_BOMB = 3
S_BIG = S_SHIP

; enemy shots: 16 directions (0 = up, clockwise), 1.7 px per frame (8.8 signed)
BVX_L:
  .byte $00,$A6,$34,$92,$B3,$92,$34,$A6,$00,$5A,$CC,$6E,$4D,$6E,$CC,$5A
BVX_H:
  .byte $00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE,$FE,$FE,$FE,$FF
BVY_L:
  .byte $4D,$6E,$CC,$5A,$00,$A6,$34,$92,$B3,$92,$34,$A6,$00,$5A,$CC,$6E
BVY_H:
  .byte $FE,$FE,$FE,$FF,$00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE
; fireballs: 16 directions, 3 px per frame
FVX_L:
  .byte $00,$26,$1F,$C6,$00,$C6,$1F,$26,$00,$DA,$E1,$3A,$00,$3A,$E1,$DA
FVX_H:
  .byte $00,$01,$02,$02,$03,$02,$02,$01,$00,$FE,$FD,$FD,$FD,$FD,$FD,$FE
FVY_L:
  .byte $00,$3A,$E1,$DA,$00,$26,$1F,$C6,$00,$C6,$1F,$26,$00,$DA,$E1,$3A
FVY_H:
  .byte $FD,$FD,$FD,$FE,$00,$01,$02,$02,$03,$02,$02,$01,$00,$FE,$FD,$FD
