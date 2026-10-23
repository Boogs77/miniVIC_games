;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_RADAR_SCOPE  -  Nintendo Radar Scope (1980)         ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: defender / space invaders (NMI + trampoline $0FD0,   ;
;   joystick VIA, AY sound engine, players saved in RAM)       ;
;                                                              ;
;   - the field in perspective: blue - black - blue sky, a     ;
;     curved radar grid on the floor; the shots shrink and     ;
;     run towards the vanishing point                          ;
;   - 48 Gamma Raiders in 6 rows of 8 (pre-shifted tiles),     ;
;     smaller and closer together far away; the formation      ;
;     sways left and right                                     ;
;   - the shots cannot reach the formation: hit the raiders    ;
;     when they hover forward or swoop down to attack          ;
;   - shooters dive, drop decoys and go back; rammers try to   ;
;     crash into the spaceport                                 ;
;   - decoys and rammers hitting the ground light the DAMAGE   ;
;     meter: the laser gets slower; destroy all the raiders    ;
;     to repair it                                             ;
;   - raider far 30, middle 80, near 150 (the lower the        ;
;     more), decoy 50, stage bonus 1000; 3 spaceports,         ;
;     one more at 7000                                         ;
;   - 1 or 2 players (alternating), title: button 1 = 1        ;
;     player, button 2 = 2 players                             ;
;   - joystick 1 ($D581) or joystick 2 ($D580):                ;
;       LEFT / RIGHT = move, button = rapid-fire laser         ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     every effect has the echo of the cabinet: laser,         ;
;     diving and hovering raiders, explosions, decoy, crash    ;
;     on the ground, stage start and stage clear tunes,        ;
;     extra spaceport                                          ;
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
PLX         = $82      ; ship X (centre)
PLST        = $83      ; 0 playing, 1 exploding, 3 explosion over
PLT         = $84      ; timer of the explosion
CURP        = $85      ; player playing (0 / 1)
NPL         = $86      ; number of players
LIVES       = $87      ; 2 bytes: spaceports per player
SCL         = $89      ; 2 bytes: score per player (BCD): tens and units
SCM         = $8B      ; 2 bytes: thousands and hundreds
SCH         = $8D      ; 2 bytes: hundred thousands and ten thousands
HISC        = $8F      ; 3 bytes BCD (low, middle, high)
STAGE       = $92      ; ---- block of the player, saved with the formation:
DAMAGE      = $93      ;      damage meter 0-8
ALIVEN      = $94      ;      raiders still alive
EXTRA       = $95      ;      1 = extra spaceport given
SWAY        = $96      ; formation offset 0-32 (16 = middle)
SWDIR       = $97      ; +1 / $FF
FDIRTY      = $98      ; the formation must be redrawn: bit 0 rows 0-2, bit 1 rows 3-5
ANIM        = $99      ; wings of the formation: frame 0 / 1
ATKT        = $9A      ; frames to the next attack
FIRECD      = $9B      ; frames before the laser can fire again
SATB        = $9C      ; bytes of the SAT to copy
NACT        = $9D      ; raiders out of the formation
PTS_L       = $9E      ; points to add (BCD)
PTS_M       = $9F
CNT         = $A0
DIFF        = $A1      ; difficulty: min(stage - 1, 7)
MUL_A       = $A2      ; multiplication
MUL_B       = $A3
TX          = $A4      ; position being handled
TY          = $A5
HW          = $A6      ; half width for the hits
SI          = $A7      ; shot being handled
MAXS        = $A8      ; shots allowed at the same time
DMGC        = $A9      ; decoys on the ground (2 = one light)

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
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
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

CMD_GAME   = 1           ; silence + game effects

; ---------------- formation: 6 rows x 8 columns (index = row * 8 + column)
F_ST   = $0300           ; 0 destroyed, 1 in its place, 2 out attacking
FBUF   = $0330           ; name table of the 6 formation rows (6 x 32)

; ---------------- raiders out of the formation: 0 free, 1 hover, 2 shooter, 3 rammer
NA     = 6
A_ON   = $0400
A_IDX  = $0406           ; place in the formation
A_PH   = $040C           ; phase of the flight
A_XF   = $0412           ; X 8.8
A_X    = $0418
A_YF   = $041E           ; Y 8.8
A_Y    = $0424
A_VXL  = $042A           ; speed 8.8 signed
A_VXH  = $0430
A_VYL  = $0436
A_VYH  = $043C
A_T    = $0442           ; timer
A_BMB  = $0448           ; decoys still to drop
A_COL  = $044E           ; colour

; ---------------- laser shots
NS     = 3
S_ON   = $0460
S_Y    = $0463
S_DX   = $0466           ; signed X distance from the centre where it started
S_X    = $0469

; ---------------- decoys (enemy bombs)
NB     = 4
B_ON   = $0470
B_XF   = $0474
B_X    = $0478
B_YF   = $047C
B_Y    = $0480
B_VXL  = $0484
B_VXH  = $0488
B_VYL  = $048C
B_VYH  = $0490

; ---------------- explosions
NX     = 4
X_T    = $04A0           ; frames left (0 = free)
X_X    = $04A4
X_Y    = $04A8

PSAVE      = $0500       ; 2 x 64 bytes: formation + block of every player
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
PLAYER_Y    = 168        ; ship (centre)
SHOT_Y0     = 160        ; the shots start here (perspective scale 1)
SHOT_TOP    = 92         ; the shots fade out here: they never reach the formation
GROUND_Y    = 177        ; decoys and rammers explode here
PULL_Y      = 132        ; the shooters pull up from here
X_MIN       = 16         ; ship
X_MAX       = 240
DMG_ON_T    = 96         ; HUD tiles of the third 2
DMG_OFF_T   = 97
LIFE_T      = 98
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
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  DEX
  BPL .rs_p
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
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the raiders of the table (sprites)
  LDY #$00
.ti_s:
  LDA TITLE_SY,X
  STA SAT_BUFFER,Y
  LDA #84
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
  CPX #4
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  JSR VDP_INT_ON
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
;  NEW GAME: stage 1 for every player, saved
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME
  STA SND_CMD
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  DEX
  BPL .ng_p
  LDA #$03
  STA LIVES
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #$03
  STA LIVES,X
  LDA #$01
  STA STAGE
  STZ DAMAGE
  STZ EXTRA
  JSR INIT_FORMATION
  LDX CURP
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER: "PLAYER <n>" and "STAGE <n>", then the game
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDX CURP
  JSR LOAD_PLAYER
  LDA STAGE                    ; difficulty
  DEC A
  CMP #8
  BCC .ts_d
  LDA #7
.ts_d:
  STA DIFF
  JSR CLEAR_OBJECTS
  LDA #128
  STA PLX
  STZ PLST
  LDA #16
  STA SWAY
  LDA #$01
  STA SWDIR
  LDA #$03
  STA FDIRTY
  LDA #120
  STA ATKT
  STZ DMGC
  JSR DRAW_FIELD
  JSR DRAW_FORMATION           ; both halves
  JSR DRAW_FORMATION
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
  LDA #<TXT_STAGE
  STA TP
  LDA #>TXT_STAGE
  STA TP+1
  JSR PRINT
  LDA STAGE
  JSR BIN2BCD
  LDX #15
  LDY #18
  JSR PUT_BCD2
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #W_START
  LDX #2
  JSR SFX_WHISTLE
  LDA #150
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  LDX #13                      ; the grid back under the messages
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
  JSR UPDATE_SHIP
  JSR UPDATE_FORMATION
  JSR UPDATE_ATTACKERS
  JSR UPDATE_SHOTS
  JSR UPDATE_BOMBS
  JSR UPDATE_EXPL
  JSR DRAW_FORMATION
  JSR BLINK_UP
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA PLST
  CMP #$03
  BNE .gl_n1
  JMP LOSE_LIFE
.gl_n1:
  LDA ALIVEN
  BNE .gl_n2
  JMP STAGE_CLEAR
.gl_n2:
  JMP GAME_LOOP


; ---------------------------------------------------------------
; all the raiders destroyed: bonus, the damage is repaired
; ---------------------------------------------------------------
STAGE_CLEAR:
  LDX #$FF
  TXS
  LDA #40                      ; the last explosions
  JSR WAIT_FRAMES
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  STZ PTS_L
  LDA #$10
  STA PTS_M
  JSR ADD_SCORE
  JSR VDP_INT_ON
  LDA #W_CLEAR
  LDX #2
  JSR SFX_WHISTLE
  LDA #180
  JSR WAIT_FRAMES
  INC STAGE
  STZ DAMAGE
  JSR INIT_FORMATION
  LDX CURP
  JSR SAVE_PLAYER
  JMP TURN_START

; ---------------------------------------------------------------
; the explosion of the spaceport is over
; ---------------------------------------------------------------
LOSE_LIFE:
  LDX #$FF
  TXS
  LDX CURP
  DEC LIVES,X
  JSR SAVE_PLAYER
  LDA #30
  JSR WAIT_FRAMES
  LDX CURP
  LDA LIVES,X
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
  JSR WAIT_FRAMES
.ll_alive:
  LDA NPL
  CMP #$02
  BNE .ll_same
  LDA CURP
  EOR #$01
  TAX
  LDA LIVES,X
  BEQ .ll_same
  STX CURP                     ; the other player
  JMP TURN_START
.ll_same:
  LDX CURP
  LDA LIVES,X
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
  JSR WAIT_FRAMES
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


; ===============================================================
;  SPACEPORT (the laser blaster)
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
  LDA JOYC                     ; rapid fire: holding the button keeps firing
  AND #BTN_MASK
  BEQ .us_r
  ; fall into FIRE

; a new shot from the ship (3 at the same time, 1 with the meter full)
FIRE:
  LDA #NS
  LDX DAMAGE
  CPX #8
  BCC .fi_m
  LDA #1
.fi_m:
  STA MAXS
  LDX #$00
.fi_l:
  LDA S_ON,X
  BEQ .fi_free
  INX
  CPX MAXS
  BNE .fi_l
  RTS
.fi_free:
  LDA #$01
  STA S_ON,X
  LDA #SHOT_Y0
  STA S_Y,X
  LDA PLX
  STA S_X,X
  SEC
  SBC #128
  STA S_DX,X
  LDX DAMAGE
  LDA FIRE_CD,X
  STA FIRECD
  LDA #W_SHOT
  LDX #0
  JMP SFX_WHISTLE

; the spaceport is hit: everything goes back to the formation
PLAYER_DIE:
  PHX
  PHY
  LDA #$01
  STA PLST
  LDA #120
  STA PLT
  LDA #S_SHIP
  LDX #2
  JSR SFX_BOOM
  LDX #(NA-1)
.pd_a:
  LDA A_ON,X
  BEQ .pd_n
  STZ A_ON,X
  LDY A_IDX,X
  LDA #$01
  STA F_ST,Y
.pd_n:
  DEX
  BPL .pd_a
  STZ NACT
  LDA #$03
  STA FDIRTY
  LDX #(NB-1)
.pd_b:
  STZ B_ON,X
  DEX
  BPL .pd_b
  LDX #(NS-1)
.pd_s:
  STZ S_ON,X
  DEX
  BPL .pd_s
  PLY
  PLX
  RTS


; ===============================================================
;  LASER SHOTS: they go up and towards the vanishing point
; ===============================================================
UPDATE_SHOTS:
  LDX #(NS-1)
.sh_l:
  STX SI
  LDA S_ON,X
  BEQ .sh_n
  LDY DAMAGE
  LDA S_Y,X
  SEC
  SBC SHOT_SPD,Y
  CMP #SHOT_TOP
  BCS .sh_mv
  STZ S_ON,X                   ; faded out in the distance
  BRA .sh_n
.sh_mv:
  STA S_Y,X
  TAY                          ; X = 128 + S_DX * FY(Y)
  LDA FY,Y
  STA MUL_B
  LDA S_DX,X
  BPL .sh_p
  EOR #$FF
  INC A
.sh_p:
  STA MUL_A
  JSR MUL8
  LDY S_DX,X
  BPL .sh_px
  EOR #$FF
  SEC
  ADC #128
  BRA .sh_sx
.sh_px:
  CLC
  ADC #128
.sh_sx:
  STA S_X,X
  JSR SHOT_HITS
.sh_n:
  LDX SI
  DEX
  BPL .sh_l
  RTS

; shot SI against the raiders and the decoys
SHOT_HITS:
  LDX #(NA-1)
.sx_a:
  LDA A_ON,X
  BEQ .sx_an
  LDA A_Y,X
  JSR SIZE_OF
  LDA HWID,Y
  STA HW
  LDY SI
  LDA A_X,X
  SEC
  SBC S_X,Y
  JSR ABS_A
  CMP HW
  BCS .sx_an
  LDA A_Y,X
  SEC
  SBC S_Y,Y
  JSR ABS_A
  CMP #8
  BCS .sx_an
  LDA #$00
  STA S_ON,Y
  JMP KILL_ATTACKER
.sx_an:
  DEX
  BPL .sx_a
  LDX #(NB-1)
.sx_b:
  LDA B_ON,X
  BEQ .sx_bn
  LDY SI
  LDA B_X,X
  SEC
  SBC S_X,Y
  JSR ABS_A
  CMP #5
  BCS .sx_bn
  LDA B_Y,X
  SEC
  SBC S_Y,Y
  JSR ABS_A
  CMP #8
  BCS .sx_bn
  LDA #$00                     ; decoy destroyed: 50
  STA S_ON,Y
  STZ B_ON,X
  LDA B_X,X
  STA TX
  LDA B_Y,X
  STA TY
  JSR NEW_EXPL
  LDA #$50
  STA PTS_L
  STZ PTS_M
  JSR ADD_SCORE
  LDA #W_DECOY
  LDX #1
  JMP SFX_WHISTLE
.sx_bn:
  DEX
  BPL .sx_b
  RTS

; A = Y on the screen -> Y = size of the raider (0 far, 1 middle, 2 near)
SIZE_OF:
  LDY #$00
  CMP #100
  BCC .so_r
  INY
  CMP #140
  BCC .so_r
  INY
.so_r:
  RTS

; A = |A| (signed)
ABS_A:
  BPL .ab_r
  EOR #$FF
  INC A
.ab_r:
  RTS

; MUL_A x MUL_B -> A = high byte, MUL_A = low byte (uses Y, keeps X)
MUL8:
  LDA #$00
  LDY #8
  LSR MUL_A
.ml_l:
  BCC .ml_n
  CLC
  ADC MUL_B
.ml_n:
  ROR A
  ROR MUL_A
  DEY
  BNE .ml_l
  RTS


; ===============================================================
;  FORMATION: sway, wings, who leaves to attack
; ===============================================================
INIT_FORMATION:
  LDX #47
  LDA #$01
.if_l:
  STA F_ST,X
  DEX
  BPL .if_l
  LDA #48
  STA ALIVEN
  RTS

UPDATE_FORMATION:
  LDA FRAME_CNT
  AND #$03
  BNE .uf_a
  LDA SWAY                     ; sway: 1 pixel (front row) every 4 frames
  CLC
  ADC SWDIR
  STA SWAY
  BEQ .uf_turn
  CMP #32
  BNE .uf_d
.uf_turn:
  LDA SWDIR
  EOR #$FE                     ; +1 <-> $FF
  STA SWDIR
.uf_d:
  LDA #$03
  STA FDIRTY
.uf_a:
  LDA FRAME_CNT
  AND #$0F
  BNE .uf_w
  LDA ANIM
  EOR #$01
  STA ANIM
  LDA #$03
  STA FDIRTY
.uf_w:
  LDA PLST
  BNE .uf_r
  DEC ATKT
  BNE .uf_r
  JSR NEXT_RND
  AND #$1F
  LDX DIFF
  CLC
  ADC ATK_GAP,X
  STA ATKT
  LDA MAXA,X                   ; how many can fly at the same time
  LDY ALIVEN
  CPY #8
  BCS .uf_m
  LDA #NA                      ; the last ones all attack
.uf_m:
  CMP NACT
  BEQ .uf_r
  BCC .uf_r
  JMP LAUNCH
.uf_r:
  RTS

; a raider leaves the formation: hover, shooter or rammer
LAUNCH:
  LDX #(NA-1)                  ; a free slot
.la_f:
  LDA A_ON,X
  BEQ .la_got
  DEX
  BPL .la_f
  RTS
.la_got:
  JSR NEXT_RND                 ; a column, then the front raider of it
  AND #$07
  STA T0
  LDA #8
  STA T1
.la_c:
  LDA T0
  CLC
  ADC #40                      ; front row first
  TAY
.la_r:
  LDA F_ST,Y
  CMP #$01
  BEQ .la_ok
  TYA
  SEC
  SBC #8
  TAY
  BCS .la_r
  LDA T0                       ; this column is empty: the next one
  INC A
  AND #$07
  STA T0
  DEC T1
  BNE .la_c
  RTS
.la_ok:
  TYA
  STA A_IDX,X
  LDA #$02
  STA F_ST,Y
  LDA #$03
  STA FDIRTY
  INC NACT
  TYA
  LSR A
  LSR A
  LSR A
  TAY
  LDA F_COL,Y
  STA A_COL,X
  LDA A_IDX,X
  JSR SLOT_POS
  LDA TX
  STA A_X,X
  LDA TY
  STA A_Y,X
  LDA #$80
  STA A_XF,X
  STA A_YF,X
  STZ A_PH,X
  STZ A_VXL,X
  STZ A_VXH,X
  LDY DIFF
  LDA BOMBS_N,Y
  STA A_BMB,X
  JSR NEXT_RND                 ; the kind
  CMP #90
  BCC .la_hover
  LDY #$02
  CMP #210
  BCC .la_k
  LDY #$03
.la_k:
  TYA
  STA A_ON,X
  LDA #20                      ; shooter / rammer: peel off, up and outwards
  STA A_T,X
  LDA #$00
  STA A_VYL,X
  LDA #$FF
  STA A_VYH,X
  LDA A_X,X
  BMI .la_right
  LDA #$40                     ; left half: -0.75
  STA A_VXL,X
  LDA #$FF
  STA A_VXH,X
  BRA .la_snd
.la_right:
  LDA #$C0
  STA A_VXL,X
  STZ A_VXH,X
.la_snd:
  LDA #W_DIVE
  LDX #1
  JMP SFX_WHISTLE
.la_hover:
  LDA #$01
  STA A_ON,X
  JSR NEXT_RND                 ; hover forward for 40-71 frames
  AND #$1F
  CLC
  ADC #40
  STA A_T,X
  LDA #$C0                     ; 0.75 px per frame
  STA A_VYL,X
  STZ A_VYH,X
  LDA #W_HOVER
  LDX #1
  JMP SFX_WHISTLE

; A = place in the formation -> TX, TY = its centre on the screen (keeps X)
SLOT_POS:
  PHX
  TAY
  LSR A
  LSR A
  LSR A
  TAX                          ; X = row
  LDA F_ROW,X
  ASL A
  ASL A
  ASL A
  ORA #$04
  STA TY
  LDA ROW33,X
  CLC
  ADC SWAY
  TAX
  LDA ROWOFF,X
  CLC
  ADC COLX,Y
  CLC
  ADC #$04
  STA TX
  PLX
  RTS

; the formation rows: rebuilt in FBUF and copied into the name table;
; FDIRTY bit 0 = rows 0-2, bit 1 = rows 3-5, one half per frame
DRAW_FORMATION:
  LDA FDIRTY
  BNE .df_go
  RTS
.df_go:
  LSR A
  BCC .df_bot
  LDA FDIRTY
  AND #$FE
  STA FDIRTY
  STZ T5                       ; rows 0-2
  BRA .df_h
.df_bot:
  STZ FDIRTY
  LDA #3                       ; rows 3-5
  STA T5
.df_h:
  CLC
  ADC #3
  STA T4
.df_row:
  LDY T5
  LDX ROW32,Y                  ; empty row
  LDA F_BLANK,Y
  STA FBUF+0,X
  STA FBUF+1,X
  STA FBUF+2,X
  STA FBUF+3,X
  STA FBUF+4,X
  STA FBUF+5,X
  STA FBUF+6,X
  STA FBUF+7,X
  STA FBUF+8,X
  STA FBUF+9,X
  STA FBUF+10,X
  STA FBUF+11,X
  STA FBUF+12,X
  STA FBUF+13,X
  STA FBUF+14,X
  STA FBUF+15,X
  STA FBUF+16,X
  STA FBUF+17,X
  STA FBUF+18,X
  STA FBUF+19,X
  STA FBUF+20,X
  STA FBUF+21,X
  STA FBUF+22,X
  STA FBUF+23,X
  STA FBUF+24,X
  STA FBUF+25,X
  STA FBUF+26,X
  STA FBUF+27,X
  STA FBUF+28,X
  STA FBUF+29,X
  STA FBUF+30,X
  STA FBUF+31,X
  LDA ROW33,Y                  ; offset of the row for this sway
  CLC
  ADC SWAY
  TAX
  LDA ROWOFF,X
  STA T0
  LDA F_T0,Y                   ; first tile of the row for this frame
  LDX ANIM
  BEQ .df_a0
  CLC
  ADC #8
.df_a0:
  STA T1
  LDA ROW32,Y
  STA T2
  TYA
  ASL A
  ASL A
  ASL A
  TAY                          ; Y = first raider of the row
  LDA #8
  STA T3
.df_e:
  LDA F_ST,Y
  CMP #$01
  BNE .df_en
  LDA COLX,Y                   ; left edge of the raider
  CLC
  ADC T0
  STA T6
  AND #$06                     ; shift (2 tiles per shift)
  CLC
  ADC T1
  STA T7
  LDA T6
  LSR A
  LSR A
  LSR A
  CLC
  ADC T2
  TAX
  LDA T7
  STA FBUF,X
  INC A
  STA FBUF+1,X
.df_en:
  INY
  DEC T3
  BNE .df_e
  LDY T5                       ; copy the row into the VRAM
  LDA F_ROW,Y
  TAX
  LDY #0
  JSR NT_XY
  LDY T5
  LDX ROW32,Y
  LDA FBUF+0,X
  STA VDATA
  LDA FBUF+1,X
  STA VDATA
  LDA FBUF+2,X
  STA VDATA
  LDA FBUF+3,X
  STA VDATA
  LDA FBUF+4,X
  STA VDATA
  LDA FBUF+5,X
  STA VDATA
  LDA FBUF+6,X
  STA VDATA
  LDA FBUF+7,X
  STA VDATA
  LDA FBUF+8,X
  STA VDATA
  LDA FBUF+9,X
  STA VDATA
  LDA FBUF+10,X
  STA VDATA
  LDA FBUF+11,X
  STA VDATA
  LDA FBUF+12,X
  STA VDATA
  LDA FBUF+13,X
  STA VDATA
  LDA FBUF+14,X
  STA VDATA
  LDA FBUF+15,X
  STA VDATA
  LDA FBUF+16,X
  STA VDATA
  LDA FBUF+17,X
  STA VDATA
  LDA FBUF+18,X
  STA VDATA
  LDA FBUF+19,X
  STA VDATA
  LDA FBUF+20,X
  STA VDATA
  LDA FBUF+21,X
  STA VDATA
  LDA FBUF+22,X
  STA VDATA
  LDA FBUF+23,X
  STA VDATA
  LDA FBUF+24,X
  STA VDATA
  LDA FBUF+25,X
  STA VDATA
  LDA FBUF+26,X
  STA VDATA
  LDA FBUF+27,X
  STA VDATA
  LDA FBUF+28,X
  STA VDATA
  LDA FBUF+29,X
  STA VDATA
  LDA FBUF+30,X
  STA VDATA
  LDA FBUF+31,X
  STA VDATA
  INC T5
  LDA T5
  CMP T4
  BEQ .df_r
  JMP .df_row
.df_r:
  RTS


; ===============================================================
;  RAIDERS OUT OF THE FORMATION
; ===============================================================
UPDATE_ATTACKERS:
  LDX #(NA-1)
.ua_l:
  LDA A_ON,X
  BEQ .ua_n
  CMP #$01
  BNE .ua_dive
  JSR HOVER
  BRA .ua_hit
.ua_dive:
  JSR DIVER
.ua_hit:
  LDA A_ON,X                   ; still flying: does it hit the spaceport?
  BEQ .ua_n
  LDA PLST
  BNE .ua_n
  LDA A_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #10
  BCS .ua_n
  LDA A_Y,X
  SEC
  SBC #PLAYER_Y
  JSR ABS_A
  CMP #8
  BCS .ua_n
  JSR KILL_ATTACKER
  JSR PLAYER_DIE
.ua_n:
  DEX
  BPL .ua_l
  RTS

; hover forward slowly, swaying, then back to its place
HOVER:
  LDA A_PH,X
  BEQ .ho_fw
  LDA #1
  JMP RETURN_STEP
.ho_fw:
  LDA FRAME_CNT                ; sway: +-0.5 px per frame
  AND #$20
  BEQ .ho_l
  LDA #$80
  STA A_VXL,X
  STZ A_VXH,X
  BRA .ho_m
.ho_l:
  LDA #$80
  STA A_VXL,X
  LDA #$FF
  STA A_VXH,X
.ho_m:
  JSR MOVE_A
  JSR MAY_DROP
  DEC A_T,X
  BNE .ho_r
  INC A_PH,X
.ho_r:
  RTS

; shooter (2) and rammer (3): peel off, dive towards the spaceport,
; the shooter pulls up and goes back, the rammer crashes on the ground
DIVER:
  LDA A_PH,X
  BNE .dv_p1
  CLC                          ; ---- 0: peel off (the climb slows down)
  LDA A_VYL,X
  ADC #$10
  STA A_VYL,X
  LDA A_VYH,X
  ADC #$00
  STA A_VYH,X
  JSR MOVE_A
  DEC A_T,X
  BNE .dv_r
  INC A_PH,X
.dv_r:
  RTS
.dv_p1:
  CMP #$01
  BEQ .dv_p1go
  JMP .dv_p2
.dv_p1go:
  LDY DIFF                     ; ---- 1: dive
  CLC
  LDA A_VYL,X
  ADC DIVE_ACC,Y
  STA A_VYL,X
  LDA A_VYH,X
  ADC #$00
  STA A_VYH,X
  BMI .dv_vy
  CMP VMAX_H,Y
  BCC .dv_vy
  BNE .dv_vmax
  LDA A_VYL,X
  CMP VMAX_L,Y
  BCC .dv_vy
.dv_vmax:
  LDA VMAX_L,Y
  STA A_VYL,X
  LDA VMAX_H,Y
  STA A_VYH,X
.dv_vy:
  LDA PLX                      ; steer towards the spaceport
  CMP A_X,X
  BCC .dv_sl
  CLC
  LDA A_VXL,X
  ADC #$0C
  STA A_VXL,X
  LDA A_VXH,X
  ADC #$00
  STA A_VXH,X
  BRA .dv_cl
.dv_sl:
  SEC
  LDA A_VXL,X
  SBC #$0C
  STA A_VXL,X
  LDA A_VXH,X
  SBC #$00
  STA A_VXH,X
.dv_cl:
  JSR CLAMP_VX
  JSR MOVE_A
  JSR MAY_DROP
  LDA A_ON,X
  CMP #$03
  BEQ .dv_ram
  LDA A_Y,X                    ; shooter: pull up
  CMP #PULL_Y
  BCC .dv_r1
  INC A_PH,X
.dv_r1:
  RTS
.dv_ram:
  LDA A_Y,X                    ; rammer: crash on the ground
  CMP #GROUND_Y
  BCC .dv_r1
  JMP CRASH
.dv_p2:
  CMP #$02
  BNE .dv_p3
  SEC                          ; ---- 2: pull up
  LDA A_VYL,X
  SBC #$20
  STA A_VYL,X
  LDA A_VYH,X
  SBC #$00
  STA A_VYH,X
  CMP #$FE                     ; going up at more than 1 px per frame: back
  BNE .dv_m2
  INC A_PH,X
.dv_m2:
  JMP MOVE_A
.dv_p3:
  LDA #2                       ; ---- 3: swiftly back to its place
  JMP RETURN_STEP

; X = raider: position += speed, kept inside the screen
MOVE_A:
  CLC
  LDA A_XF,X
  ADC A_VXL,X
  STA A_XF,X
  LDA A_X,X
  ADC A_VXH,X
  STA A_X,X
  CMP #8
  BCS .ma_1
  LDA #8
  BRA .ma_s
.ma_1:
  CMP #248
  BCC .ma_y
  LDA A_VXH,X                  ; past the right edge, or wrapped from the left one
  BMI .ma_w
  LDA #247
  BRA .ma_s
.ma_w:
  LDA #8
.ma_s:
  STA A_X,X
  STZ A_VXL,X
  STZ A_VXH,X
.ma_y:
  CLC
  LDA A_YF,X
  ADC A_VYL,X
  STA A_YF,X
  LDA A_Y,X
  ADC A_VYH,X
  CMP #16
  BCS .ma_ys
  LDA #16
.ma_ys:
  STA A_Y,X
  RTS

; X = raider: |VX| <= 1.5 px per frame
CLAMP_VX:
  LDA A_VXH,X
  BMI .cv_neg
  CMP #$01
  BCC .cv_r
  BNE .cv_sp
  LDA A_VXL,X
  CMP #$80
  BCC .cv_r
.cv_sp:
  LDA #$80
  STA A_VXL,X
  LDA #$01
  STA A_VXH,X
.cv_r:
  RTS
.cv_neg:
  CMP #$FE
  BCC .cv_sn
  BNE .cv_r
  LDA A_VXL,X
  CMP #$80
  BCS .cv_r
.cv_sn:
  LDA #$80
  STA A_VXL,X
  LDA #$FE
  STA A_VXH,X
  RTS

; X = raider, A = speed (px per frame): towards its place, then back in the formation
RETURN_STEP:
  STA T5
  LDA A_IDX,X
  JSR SLOT_POS
  LDA A_X,X
  SEC
  SBC TX
  BEQ .rt_xd
  BCC .rt_xr
  CMP T5                       ; on the right: to the left
  BCC .rt_xs
  LDA A_X,X
  SEC
  SBC T5
  STA A_X,X
  BRA .rt_xd
.rt_xr:
  EOR #$FF                     ; on the left: to the right
  INC A
  CMP T5
  BCC .rt_xs
  LDA A_X,X
  CLC
  ADC T5
  STA A_X,X
  BRA .rt_xd
.rt_xs:
  LDA TX
  STA A_X,X
.rt_xd:
  LDA A_Y,X
  SEC
  SBC TY
  BEQ .rt_yd
  BCC .rt_yr
  CMP T5                       ; below: up
  BCC .rt_ys
  LDA A_Y,X
  SEC
  SBC T5
  STA A_Y,X
  BRA .rt_yd
.rt_yr:
  EOR #$FF                     ; above: down
  INC A
  CMP T5
  BCC .rt_ys
  LDA A_Y,X
  CLC
  ADC T5
  STA A_Y,X
  BRA .rt_yd
.rt_ys:
  LDA TY
  STA A_Y,X
.rt_yd:
  LDA A_X,X
  CMP TX
  BNE .rt_r
  LDA A_Y,X
  CMP TY
  BNE .rt_r
  LDY A_IDX,X                  ; home
  LDA #$01
  STA F_ST,Y
  LDA #$03
  STA FDIRTY
  STZ A_ON,X
  DEC NACT
.rt_r:
  RTS

; X = raider: sometimes drops a decoy towards the spaceport
MAY_DROP:
  LDA A_BMB,X
  BEQ .md_r
  LDA A_Y,X
  CMP #56
  BCC .md_r
  CMP #150
  BCS .md_r
  JSR NEXT_RND
  AND #$1F
  BNE .md_r
  LDY #(NB-1)
.md_f:
  LDA B_ON,Y
  BEQ .md_new
  DEY
  BPL .md_f
.md_r:
  RTS
.md_new:
  DEC A_BMB,X
  LDA #$01
  STA B_ON,Y
  LDA A_X,X
  STA B_X,Y
  LDA A_Y,X
  CLC
  ADC #4
  STA B_Y,Y
  LDA #$80
  STA B_XF,Y
  STA B_YF,Y
  LDA DIFF                     ; falling speed: 0.75 px per frame and more
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #$C0
  STA B_VYL,Y
  LDA #$00
  ADC #$00
  STA B_VYH,Y
  LDA PLX                      ; aimed: VX = (spaceport X - X) / 64
  SEC
  SBC A_X,X
  STA T0
  LDA #$00
  SBC #$00                     ; $00 / $FF = sign
  STA T1
  BPL .md_cp
  LDA T0                       ; not more than 127 pixels each way
  CMP #$81
  BCS .md_sh
  LDA #$81
  STA T0
  BRA .md_sh
.md_cp:
  LDA T0
  BPL .md_sh
  LDA #$7F
  STA T0
.md_sh:
  ASL T0
  ROL T1
  ASL T0
  ROL T1
  LDA T0
  STA B_VXL,Y
  LDA T1
  STA B_VXH,Y
  RTS

; X = rammer on the ground: explosion and damage
CRASH:
  LDA A_X,X
  STA TX
  LDA #GROUND_Y
  STA TY
  JSR NEW_EXPL
  JSR ADD_DAMAGE
  LDY A_IDX,X
  LDA #$00
  STA F_ST,Y
  STZ A_ON,X
  DEC NACT
  DEC ALIVEN
  RTS

; X = raider shot down: points by the distance, explosion
KILL_ATTACKER:
  LDA A_Y,X
  JSR SIZE_OF
  LDA PTS_TL,Y
  STA PTS_L
  LDA PTS_TM,Y
  STA PTS_M
  JSR ADD_SCORE
  LDA A_X,X
  STA TX
  LDA A_Y,X
  STA TY
  JSR NEW_EXPL
  PHX
  LDY A_X,X
  LDA #S_SMALL
  JSR BOOM_AT
  PLX
  LDY A_IDX,X
  LDA #$00
  STA F_ST,Y
  STZ A_ON,X
  DEC NACT
  DEC ALIVEN
  RTS

; a decoy on the ground: one more light on the damage meter every two (keeps X)
HALF_DAMAGE:
  JSR GROUND_BOOM
  INC DMGC
  LDA DMGC
  LSR A
  BCC ADD_DMG1
  RTS

; a rammer on the ground: one more light on the damage meter (keeps X)
ADD_DAMAGE:
  JSR GROUND_BOOM
ADD_DMG1:
  LDA DAMAGE
  CMP #8
  BCS .ad_r
  INC DAMAGE
  JSR DRAW_DAMAGE
.ad_r:
  RTS

GROUND_BOOM:
  PHX
  LDY TX
  LDA #S_GROUND
  JSR BOOM_AT
  PLX
  RTS


; ===============================================================
;  DECOYS: they fall faster and faster, aimed at the spaceport
; ===============================================================
UPDATE_BOMBS:
  LDX #(NB-1)
.ub_l:
  LDA B_ON,X
  BEQ .ub_n
  CLC                          ; gravity of the perspective
  LDA B_VYL,X
  ADC #$04
  STA B_VYL,X
  BCC .ub_v
  INC B_VYH,X
.ub_v:
  CLC
  LDA B_XF,X
  ADC B_VXL,X
  STA B_XF,X
  LDA B_X,X
  ADC B_VXH,X
  STA B_X,X
  CMP #4
  BCC .ub_off
  CMP #252
  BCS .ub_off
  CLC
  LDA B_YF,X
  ADC B_VYL,X
  STA B_YF,X
  LDA B_Y,X
  ADC B_VYH,X
  STA B_Y,X
  CMP #GROUND_Y
  BCC .ub_hit
  STZ B_ON,X                   ; on the ground: damage
  LDA B_X,X
  STA TX
  LDA #GROUND_Y
  STA TY
  JSR NEW_EXPL
  JSR HALF_DAMAGE
  BRA .ub_n
.ub_hit:
  LDA PLST
  BNE .ub_n
  LDA B_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #7
  BCS .ub_n
  LDA B_Y,X
  SEC
  SBC #PLAYER_Y
  JSR ABS_A
  CMP #6
  BCS .ub_n
  STZ B_ON,X
  JSR PLAYER_DIE
  BRA .ub_n
.ub_off:
  STZ B_ON,X
.ub_n:
  DEX
  BMI .ub_r
  JMP .ub_l
.ub_r:
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
  LDX #(NA-1)
.co_a:
  STZ A_ON,X
  DEX
  BPL .co_a
  LDX #(NS-1)
.co_s:
  STZ S_ON,X
  DEX
  BPL .co_s
  LDX #(NB-1)
.co_b:
  STZ B_ON,X
  DEX
  BPL .co_b
  LDX #(NX-1)
.co_x:
  STZ X_T,X
  DEX
  BPL .co_x
  STZ NACT
  STZ FIRECD
  LDX #47                      ; raiders out of the formation go back
.co_f:
  LDA F_ST,X
  BEQ .co_fn
  LDA #$01
  STA F_ST,X
.co_fn:
  DEX
  BPL .co_f
  RTS


; ===============================================================
;  PLAYERS: save / load the formation and the block STAGE-EXTRA
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.sp_f:
  LDA F_ST,X
  STA PSAVE,Y
  INY
  INX
  CPX #48
  BNE .sp_f
  LDX #$00
.sp_b:
  LDA STAGE,X
  STA PSAVE,Y
  INY
  INX
  CPX #4
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.lp_f:
  LDA PSAVE,Y
  STA F_ST,X
  INY
  INX
  CPX #48
  BNE .lp_f
  LDX #$00
.lp_b:
  LDA PSAVE,Y
  STA STAGE,X
  INY
  INX
  CPX #4
  BNE .lp_b
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M (BCD) to the player playing; one more spaceport at 7000 (keeps X)
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
  BNE .as_x
  LDA SCM,X
  CMP #$70
  BCC .as_d
.as_x:
  LDA #$01
  STA EXTRA
  LDA LIVES,X
  CMP #9
  BCS .as_s
  INC LIVES,X
.as_s:
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
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
  JSR LOAD_SPRITES
  ; fall into CLEAR_NT

; name table: all empty (tile 0)
CLEAR_NT:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #$00
  LDX #$00
.cn_l:
  STA VDATA
  STA VDATA
  STA VDATA
  INX
  BNE .cn_l
  RTS

; the field (sky and grid) and the HUD
DRAW_FIELD:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #<BG_NT
  STA PTR
  LDA #>BG_NT
  STA PTR+1
  LDX #3                       ; 3 pages
.dfl_p:
  LDY #$00
.dfl_l:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .dfl_l
  INC PTR+1
  DEX
  BNE .dfl_p
  JSR DRAW_TOP
  LDA #<TXT_BOT
  STA TP
  LDA #>TXT_BOT
  STA TP+1
  JSR PRINT
  LDA STAGE
  JSR BIN2BCD
  LDX #22
  LDY #26
  JSR PUT_BCD2
  JSR DRAW_LIVES
  ; fall into DRAW_DAMAGE

; the damage meter: row 22, columns 8-15
DRAW_DAMAGE:
  PHX
  LDX #22
  LDY #8
  JSR NT_XY
  LDX #$00
.dd_l:
  LDA #DMG_ON_T
  CPX DAMAGE
  BCC .dd_w
  LDA #DMG_OFF_T
.dd_w:
  STA VDATA
  INX
  CPX #8
  BNE .dd_l
  PLX
  RTS

; spare spaceports of the player playing: row 23
DRAW_LIVES:
  PHX
  LDX #23
  LDY #1
  JSR NT_XY
  LDX CURP
  LDA LIVES,X
  BEQ .dl_z
  DEC A
.dl_z:
  STA T0
  LDX #$00
.dl_l:
  LDA #LIFE_T
  CPX T0
  BCC .dl_w
  LDA #0
.dl_w:
  STA VDATA
  INX
  CPX #8
  BNE .dl_l
  PLX
  RTS

; the grid back on X = first row, A = number of rows
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
;  SPRITES: the ship, the shots, the raiders, the decoys and the
;  explosions; the raiders are listed backwards on odd frames, so
;  with more than 4 sprites on a line they flicker instead of
;  disappearing
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA PLST
  BEQ .bs_ship
  CMP #$01
  BNE .bs_shots
  LDA PLX                      ; the spaceport explodes
  STA OX
  LDA #PLAYER_Y
  STA OY
  LDA PLT
  LSR A
  LSR A
  AND #$03
  TAX
  LDA EXPL_N,X
  STA ON
  LDA FRAME_CNT
  AND #$03
  TAX
  LDA FLAME_COL,X
  STA OC
  JSR ADD_SPR
  BRA .bs_shots
.bs_ship:
  LDA PLX
  STA OX
  LDA #PLAYER_Y
  STA OY
  STZ ON
  LDA #$0F
  STA OC
  JSR ADD_SPR
.bs_shots:
  LDX #(NS-1)
.bs_sl:
  LDA S_ON,X
  BEQ .bs_sn
  LDA S_X,X
  STA OX
  LDA S_Y,X
  STA OY
  LDY #28                      ; near: thick, far: thin
  CMP #128
  BCS .bs_sw
  LDY #32
.bs_sw:
  STY ON
  LDA #$0B
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.bs_sn:
  DEX
  BPL .bs_sl
  LDX #(NA-1)                  ; raiders
.bs_al:
  TXA
  TAY
  LDA FRAME_CNT
  LSR A
  BCC .bs_ao
  TXA
  EOR #$FF
  CLC
  ADC #NA
  TAY                          ; odd frames: NA-1-X
.bs_ao:
  LDA A_ON,Y
  BEQ .bs_an
  LDA A_X,Y
  STA OX
  LDA A_COL,Y
  STA OC
  LDA A_Y,Y
  STA OY
  PHY
  JSR SIZE_OF
  LDA SZ_N,Y
  PLY
  STA ON
  LDA FRAME_CNT
  AND #$08
  LSR A
  CLC
  ADC ON
  STA ON
  PHX
  JSR ADD_SPR
  PLX
.bs_an:
  DEX
  BPL .bs_al
  LDX #(NB-1)                  ; decoys
.bs_bl:
  LDA B_ON,X
  BEQ .bs_bn
  LDA B_X,X
  STA OX
  LDA B_Y,X
  STA OY
  LDA FRAME_CNT
  AND #$04
  CLC
  ADC #36
  STA ON
  LDA FRAME_CNT                ; white / red
  AND #$08
  BEQ .bs_bw
  LDA #$09
  BRA .bs_bc
.bs_bw:
  LDA #$0F
.bs_bc:
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.bs_bn:
  DEX
  BPL .bs_bl
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
;  per chip: A = tone effects, B = noise and C = low tone of the
;  explosions; the echo is written in the tables
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
PS_OFF:     .byte 0,64                         ; block of the player in PSAVE
ROW32:      .byte 0,32,64,96,128,160           ; formation row * 32 (FBUF)
ROW33:      .byte 0,33,66,99,132,165           ; formation row * 33 (ROWOFF)
; by size of the raider (0 far, 1 middle, 2 near)
SZ_N:       .byte 4,12,20                      ; sprite pattern (frame 0)
HWID:       .byte 5,7,9                        ; half width for the hits (+1)
PTS_TL:     .byte $30,$80,$50                  ; points (BCD): 30, 80, 150
PTS_TM:     .byte $00,$00,$01
EXPL_N:     .byte 44,48,52,48                  ; explosion frames
EXPL_C:     .byte $0B,$0A,$09,$0A
FLAME_COL:  .byte $0B,$0A,$09,$0F
; by damage 0-8: the laser gets slower
SHOT_SPD:   .byte 6,6,5,5,5,4,4,4,3            ; pixels per frame
FIRE_CD:    .byte 8,9,10,11,12,14,16,18,24     ; frames between two shots
; by difficulty (stage 1-8, then always 8)
ATK_GAP:    .byte 100,90,80,70,60,50,45,40     ; frames between two attacks (+ 0-31)
MAXA:       .byte 2,2,3,3,4,4,5,6              ; raiders out at the same time
DIVE_ACC:   .byte $05,$06,$07,$08,$09,$0A,$0B,$0C  ; dive: acceleration (1/256 px per frame)
VMAX_L:     .byte $00,$20,$40,$60,$80,$A0,$C0,$00  ;       top speed 8.8
VMAX_H:     .byte 2,2,2,2,2,2,2,3
BOMBS_N:    .byte 1,1,2,2,2,3,3,3              ; decoys of every attack
; title: the raiders of the scoring table (sprite Y, pattern, colour)
TITLE_SY:   .byte 9*8-6,11*8-6,13*8-6,15*8-6
TITLE_SN:   .byte 4,12,20,36
TITLE_SC:   .byte $0D,$09,$0B,$0F

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_BOT:
  .byte 22,1,"DAMAGE",0
  .byte 22,20,"STAGE",0
  .byte $FF
TXT_TITLE:
  .byte 4,10,"RADAR SCOPE",0
  .byte 7,8,"- SCORE TABLE -",0
  .byte 9,13,"FAR       30",0
  .byte 11,13,"MIDDLE    80",0
  .byte 13,13,"NEAR     150",0
  .byte 15,13,"DECOY     50",0
  .byte 18,2,"DESTROY THE 48 GAMMA RAIDERS",0
  .byte 19,3,"BONUS 1000   SPACEPORT 7000",0
  .byte 21,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_PLAYER:
  .byte 13,12,"PLAYER ",0
  .byte $FF
TXT_STAGE:
  .byte 15,12,"STAGE ",0
  .byte $FF
TXT_CLEAR:
  .byte 13,10,"STAGE CLEAR",0
  .byte 15,10,"BONUS  1000",0
  .byte $FF
TXT_OVER:
  .byte 15,11,"GAME OVER",0
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
FLD_P0:                  ; third 0: 67 tiles from 96
  .byte $00,$00,$44,$38,$7C,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$11,$0E,$1F,$15,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$03,$07,$05,$00,$00,$00,$00,$40,$80,$C0,$40,$00,$00
  .byte $00,$00,$01,$00,$01,$01,$00,$00,$00,$00,$10,$E0,$F0,$50,$00,$00
  .byte $00,$00,$10,$7C,$38,$28,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$1F,$0E,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$07,$03,$02,$00,$00,$00,$00,$00,$C0,$80,$80,$00,$00
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$40,$F0,$E0,$A0,$00,$00
  .byte $00,$00,$44,$38,$7C,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$11,$0E,$1F,$15,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$03,$07,$05,$00,$00,$00,$00,$40,$80,$C0,$40,$00,$00
  .byte $00,$00,$01,$00,$01,$01,$00,$00,$00,$00,$10,$E0,$F0,$50,$00,$00
  .byte $00,$00,$10,$7C,$38,$28,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$1F,$0E,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$07,$03,$02,$00,$00,$00,$00,$00,$C0,$80,$80,$00,$00
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$40,$F0,$E0,$A0,$00,$00
  .byte $00,$82,$54,$38,$7C,$92,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$20,$15,$0E,$1F,$24,$00,$00,$00,$80,$00,$00,$00,$80,$00,$00
  .byte $00,$08,$05,$03,$07,$09,$00,$00,$00,$20,$40,$80,$C0,$20,$00,$00
  .byte $00,$02,$01,$00,$01,$02,$00,$00,$00,$08,$50,$E0,$F0,$48,$00,$00
  .byte $00,$10,$7C,$BA,$54,$44,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$04,$1F,$2E,$15,$11,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00
  .byte $00,$01,$07,$0B,$05,$04,$00,$00,$00,$00,$C0,$A0,$40,$40,$00,$00
  .byte $00,$00,$01,$02,$01,$01,$00,$00,$00,$40,$F0,$E8,$50,$10,$00,$00
  .byte $00,$82,$54,$38,$7C,$92,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$20,$15,$0E,$1F,$24,$00,$00,$00,$80,$00,$00,$00,$80,$00,$00
  .byte $00,$08,$05,$03,$07,$09,$00,$00,$00,$20,$40,$80,$C0,$20,$00,$00
  .byte $00,$02,$01,$00,$01,$02,$00,$00,$00,$08,$50,$E0,$F0,$48,$00,$00
  .byte $00,$10,$7C,$BA,$54,$44,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$04,$1F,$2E,$15,$11,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00
  .byte $00,$01,$07,$0B,$05,$04,$00,$00,$00,$00,$C0,$A0,$40,$40,$00,$00
  .byte $00,$00,$01,$02,$01,$01,$00,$00,$00,$40,$F0,$E8,$50,$10,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
FLD_C0:
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4,$D5,$D4
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94,$94
  .byte $75,$75,$75,$75,$75,$75,$75,$75,$75,$74,$75,$74,$75,$74,$75,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74
FLD_P1:                  ; third 1: 92 tiles from 96
  .byte $00,$81,$5A,$3C,$7E,$BD,$99,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$20,$16,$0F,$1F,$2F,$26,$00,$00,$40,$80,$00,$80,$40,$40,$00
  .byte $00,$08,$05,$03,$07,$0B,$09,$00,$00,$10,$A0,$C0,$E0,$D0,$90,$00
  .byte $00,$02,$01,$00,$01,$02,$02,$00,$00,$04,$68,$F0,$F8,$F4,$64,$00
  .byte $00,$18,$3C,$FF,$BD,$24,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$06,$0F,$3F,$2F,$09,$10,$00,$00,$00,$00,$C0,$40,$00,$80,$00
  .byte $00,$01,$03,$0F,$0B,$02,$04,$00,$00,$80,$C0,$F0,$D0,$40,$20,$00
  .byte $00,$00,$00,$03,$02,$00,$01,$00,$00,$60,$F0,$FC,$F4,$90,$08,$00
  .byte $00,$81,$5A,$3C,$7E,$BD,$99,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$20,$16,$0F,$1F,$2F,$26,$00,$00,$40,$80,$00,$80,$40,$40,$00
  .byte $00,$08,$05,$03,$07,$0B,$09,$00,$00,$10,$A0,$C0,$E0,$D0,$90,$00
  .byte $00,$02,$01,$00,$01,$02,$02,$00,$00,$04,$68,$F0,$F8,$F4,$64,$00
  .byte $00,$18,$3C,$FF,$BD,$24,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$06,$0F,$3F,$2F,$09,$10,$00,$00,$00,$00,$C0,$40,$00,$80,$00
  .byte $00,$01,$03,$0F,$0B,$02,$04,$00,$00,$80,$C0,$F0,$D0,$40,$20,$00
  .byte $00,$00,$00,$03,$02,$00,$01,$00,$00,$60,$F0,$FC,$F4,$90,$08,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$01,$02,$FF,$08,$08,$10,$80,$00,$00,$0F,$F8,$00,$00,$00
  .byte $00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$03,$FE,$00,$00,$01,$01
  .byte $20,$20,$FF,$40,$80,$80,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00
  .byte $04,$0F,$F8,$08,$10,$10,$10,$20,$00,$FF,$00,$00,$00,$00,$00,$00
  .byte $01,$FF,$01,$01,$02,$02,$02,$02,$40,$FF,$40,$40,$20,$20,$20,$20
  .byte $10,$FC,$0F,$08,$04,$04,$04,$02,$02,$02,$FF,$01,$00,$00,$00,$00
  .byte $00,$00,$F0,$1F,$80,$80,$40,$40,$00,$00,$00,$FC,$07,$00,$00,$00
  .byte $80,$40,$20,$20,$FF,$08,$04,$04,$20,$40,$40,$80,$01,$FF,$00,$00
  .byte $00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$07,$FC,$00,$00,$00
  .byte $02,$04,$07,$FE,$08,$10,$10,$20,$00,$3F,$E0,$00,$00,$00,$00,$00
  .byte $20,$FF,$40,$40,$40,$80,$80,$80,$FF,$80,$00,$00,$00,$00,$00,$00
  .byte $FF,$00,$00,$00,$00,$00,$00,$00,$FF,$02,$02,$02,$02,$04,$04,$04
  .byte $FF,$20,$20,$20,$20,$10,$10,$10,$C0,$7F,$00,$00,$00,$00,$00,$00
  .byte $02,$FF,$01,$01,$01,$00,$00,$00,$00,$FF,$00,$00,$00,$80,$80,$80
  .byte $00,$FF,$01,$00,$00,$00,$00,$00,$20,$10,$F0,$1F,$08,$04,$04,$02
  .byte $00,$00,$00,$F8,$0F,$00,$00,$00,$02,$01,$00,$00,$E0,$3F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$00,$00,$00,$00,$01,$3F,$E2,$20,$40,$40,$80,$80,$03,$FE,$00
  .byte $00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$0F,$F8,$00,$00
  .byte $01,$01,$01,$07,$FE,$02,$02,$04,$00,$00,$03,$FE,$00,$00,$00,$00
  .byte $04,$04,$FF,$04,$04,$04,$04,$08,$10,$10,$FF,$10,$10,$10,$08,$08
  .byte $00,$00,$F0,$1F,$00,$00,$00,$00,$40,$40,$40,$F8,$2F,$20,$10,$10
  .byte $00,$00,$00,$00,$FC,$07,$00,$00,$02,$01,$01,$00,$00,$F0,$1F,$00
  .byte $00,$00,$00,$80,$80,$40,$FF,$21,$00,$00,$00,$00,$00,$00,$00,$E0
  .byte $07,$FC,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$04,$04,$08,$08,$10,$10,$20,$20
  .byte $04,$04,$08,$08,$08,$10,$10,$10,$08,$08,$08,$08,$08,$08,$08,$08
  .byte $10,$10,$08,$08,$08,$04,$04,$04,$10,$10,$08,$08,$04,$04,$02,$02
  .byte $3F,$00,$00,$00,$00,$00,$00,$00,$F8,$0F,$00,$00,$00,$00,$00,$00
FLD_C1:
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1,$B4,$B1
  .byte $74,$71,$74,$71,$74,$71,$74,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
FLD_P2:                  ; third 2: 87 tiles from 99
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F
  .byte $00,$00,$00,$00,$01,$02,$0F,$FC,$40,$40,$80,$80,$00,$0F,$F8,$00
  .byte $00,$00,$00,$00,$03,$FE,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00
  .byte $00,$00,$00,$7F,$C0,$00,$00,$00,$00,$00,$07,$FC,$00,$00,$00,$00
  .byte $20,$20,$FF,$40,$40,$40,$80,$80,$00,$0F,$F8,$00,$00,$00,$00,$00
  .byte $00,$FF,$00,$00,$00,$00,$00,$00,$3F,$E0,$00,$00,$00,$00,$00,$00
  .byte $FF,$10,$10,$10,$10,$10,$10,$10,$FF,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$04,$04,$04,$04,$04,$04,$04,$FF,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$FC,$07,$00,$00,$00,$00,$00,$02,$02,$FF,$01,$01,$01,$00,$00
  .byte $00,$00,$F8,$0F,$00,$00,$80,$80,$00,$00,$00,$FF,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$FF,$00,$00,$00,$00,$00,$00,$00,$F0,$1F,$00,$00
  .byte $01,$01,$00,$00,$00,$FC,$07,$00,$00,$00,$80,$80,$40,$20,$FC,$17
  .byte $00,$00,$00,$00,$00,$00,$00,$FC,$0F,$F8,$00,$00,$00,$00,$00,$00
  .byte $F8,$00,$00,$00,$00,$00,$00,$00,$04,$08,$08,$10,$10,$20,$20,$40
  .byte $00,$01,$01,$01,$02,$02,$02,$04,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $10,$20,$20,$20,$20,$20,$20,$20,$04,$02,$02,$02,$02,$02,$02,$02
  .byte $80,$40,$40,$40,$20,$20,$20,$10,$10,$08,$08,$04,$04,$02,$02,$01
  .byte $07,$00,$00,$00,$00,$00,$00,$00,$FC,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$02,$04,$04
  .byte $40,$80,$80,$00,$00,$00,$00,$00,$04,$04,$04,$08,$08,$08,$10,$FF
  .byte $00,$00,$00,$00,$00,$00,$1F,$F0,$00,$00,$00,$00,$00,$00,$FF,$00
  .byte $00,$00,$00,$00,$00,$7F,$C0,$00,$00,$00,$00,$00,$00,$FF,$00,$00
  .byte $00,$00,$00,$00,$07,$FC,$00,$00,$20,$20,$20,$40,$FF,$40,$40,$40
  .byte $00,$00,$00,$00,$FF,$00,$00,$00,$02,$02,$01,$01,$FF,$01,$01,$01
  .byte $00,$00,$00,$00,$F8,$0F,$00,$00,$00,$00,$00,$00,$00,$80,$FF,$00
  .byte $00,$00,$00,$00,$00,$00,$FE,$03,$10,$10,$08,$08,$08,$08,$04,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$40,$40,$20,$20,$10,$10,$08,$08,$10,$10,$20,$3F,$E0,$40
  .byte $00,$00,$00,$01,$FF,$80,$00,$00,$00,$00,$03,$FE,$00,$00,$00,$00
  .byte $00,$03,$FE,$00,$00,$00,$00,$00,$01,$FF,$00,$00,$00,$00,$00,$00
  .byte $FF,$00,$00,$00,$00,$00,$00,$00,$90,$20,$20,$20,$40,$40,$40,$80
  .byte $40,$40,$40,$40,$80,$80,$80,$80,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$80,$80,$80,$04,$02,$02,$02,$01,$01,$01,$00
  .byte $7F,$00,$00,$00,$00,$00,$00,$80,$E0,$3F,$00,$00,$00,$00,$00,$00
  .byte $00,$F0,$1F,$00,$00,$00,$00,$00,$00,$00,$F0,$1F,$00,$00,$00,$00
  .byte $00,$00,$00,$E0,$3F,$00,$00,$00,$08,$08,$04,$04,$C2,$7F,$01,$01
  .byte $00,$01,$01,$02,$02,$04,$04,$08,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$01,$02,$02,$02,$80,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$80,$80,$80,$80,$80,$00,$00,$00
  .byte $80,$80,$80,$80,$80,$40,$40,$40,$80,$80,$40,$40,$40,$20,$20,$20
  .byte $80,$40,$40,$20,$20,$10,$10,$08,$08,$10,$10,$20,$20,$40,$40,$80
  .byte $04,$04,$04,$08,$08,$08,$08,$10,$01,$01,$01,$01,$01,$01,$01,$02
  .byte $40,$40,$40,$40,$40,$40,$20,$20,$10,$10,$10,$08,$08,$08,$04,$04
  .byte $08,$04,$04,$02,$02,$01,$00,$00
FLD_C2:
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74,$71,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74

; HUD tiles of the third 2: damage segment on / off, spare spaceport
HUD_PAT:
  .byte $00,$7E,$7E,$7E,$7E,$7E,$7E,$00
  .byte $00,$7E,$42,$42,$42,$42,$7E,$00
  .byte $18,$18,$3C,$BD,$FF,$FF,$42,$00
HUD_COL:
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$43, <536,>536, <FLD_P0,>FLD_P0
  .byte 1, $00,$63, <536,>536, <FLD_C0,>FLD_C0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4B, <736,>736, <FLD_P1,>FLD_P1
  .byte 1, $00,$6B, <736,>736, <FLD_C1,>FLD_C1
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $18,$53, <696,>696, <FLD_P2,>FLD_P2
  .byte 1, $18,$73, <696,>696, <FLD_C2,>FLD_C2
  .byte 1, $00,$53, <24,>24, <HUD_PAT,>HUD_PAT
  .byte 1, $00,$73, <24,>24, <HUD_COL,>HUD_COL
  .byte 0

; static name table of the field (rows 0-1 and 22-23 empty)
BG_NT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2
  .byte $A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2
  .byte $A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2,$A2
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $82,$83,$84,$84,$85,$86,$87,$87,$87,$88,$89,$89,$89,$8A,$89,$89,$89,$89,$8B,$89,$89,$89,$8C,$87,$87,$87,$8D,$8E,$84,$84,$8F,$90
  .byte $91,$92,$93,$84,$94,$87,$87,$95,$89,$96,$89,$97,$98,$99,$98,$98,$98,$98,$9A,$98,$98,$9B,$9C,$9D,$9E,$87,$87,$9F,$84,$A0,$92,$A1
  .byte $81,$A2,$A3,$A4,$A5,$A6,$A7,$92,$A8,$84,$84,$A9,$87,$AA,$87,$87,$87,$87,$AB,$87,$AC,$84,$84,$AD,$92,$AE,$A6,$AF,$B0,$A3,$B1,$81
  .byte $B2,$B3,$B4,$B5,$B4,$B4,$B4,$B4,$B6,$B4,$B4,$B4,$B4,$B7,$B4,$B4,$B4,$B4,$B7,$B4,$B4,$B4,$B4,$B8,$B4,$B4,$B4,$B4,$B9,$B4,$BA,$BB
  .byte $63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6D,$6E,$6F,$70,$70,$70,$70,$71,$72,$6D,$6D,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$63
  .byte $7C,$7D,$7E,$63,$63,$63,$63,$7F,$80,$63,$63,$63,$63,$81,$63,$63,$63,$63,$82,$63,$63,$63,$63,$63,$83,$63,$63,$63,$63,$84,$85,$86
  .byte $87,$88,$89,$87,$87,$87,$87,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$91,$91,$91,$92,$93,$8E,$8E,$94,$95,$96,$97,$87,$87,$87,$98,$99,$87
  .byte $8B,$9A,$9B,$9C,$9D,$9E,$9F,$A0,$87,$87,$87,$87,$87,$A1,$87,$87,$87,$87,$A2,$A3,$87,$87,$87,$87,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$95
  .byte $AB,$AC,$87,$87,$87,$87,$AD,$AE,$87,$87,$87,$87,$AF,$B0,$87,$87,$87,$87,$87,$B1,$87,$87,$87,$87,$87,$B2,$87,$87,$87,$87,$87,$B3
  .byte $B4,$87,$87,$87,$87,$87,$B5,$87,$87,$87,$87,$87,$B6,$87,$87,$87,$87,$87,$87,$B7,$87,$87,$87,$87,$87,$B8,$87,$87,$87,$87,$87,$B9
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; formation: tile row, first tile (frame * 8 + shift * 2), colour, empty tile of every row
F_ROW:
  .byte $03,$04,$05,$06,$08,$0A
F_T0:
  .byte $60,$70,$80,$90,$60,$70
F_COL:
  .byte $0D,$0D,$09,$09,$0B,$0B
F_BLANK:
  .byte $A1,$A1,$A2,$A2,$80,$80
; left edge (centre - 4) of every column with the formation in the middle
COLX:
  .byte $44,$54,$64,$74,$84,$94,$A4,$B4
  .byte $41,$52,$63,$74,$85,$96,$A7,$B8
  .byte $3D,$4F,$61,$73,$85,$97,$A9,$BB
  .byte $36,$4A,$5E,$72,$86,$9A,$AE,$C2
  .byte $2F,$45,$5B,$71,$87,$9D,$B3,$C9
  .byte $28,$40,$58,$70,$88,$A0,$B8,$D0
; sway 0-32 (16 = middle): offset of every row
ROWOFF:
  .byte $F5,$F6,$F7,$F7,$F8,$F9,$F9,$FA,$FB,$FB,$FC,$FD,$FD,$FE,$FF,$FF,$00,$01,$01,$02,$03,$03,$04,$05,$05,$06,$07,$07,$08,$09,$09,$0A,$0B
  .byte $F5,$F5,$F6,$F7,$F8,$F8,$F9,$FA,$FA,$FB,$FC,$FC,$FD,$FE,$FF,$FF,$00,$01,$01,$02,$03,$04,$04,$05,$06,$06,$07,$08,$09,$09,$0A,$0B,$0B
  .byte $F4,$F5,$F6,$F6,$F7,$F8,$F9,$F9,$FA,$FB,$FC,$FC,$FD,$FE,$FF,$FF,$00,$01,$02,$02,$03,$04,$05,$05,$06,$07,$08,$08,$09,$0A,$0B,$0B,$0C
  .byte $F3,$F4,$F4,$F5,$F6,$F7,$F8,$F9,$F9,$FA,$FB,$FC,$FD,$FE,$FE,$FF,$00,$01,$02,$03,$03,$04,$05,$06,$07,$08,$08,$09,$0A,$0B,$0C,$0D,$0D
  .byte $F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FB,$FC,$FD,$FE,$FF,$00,$01,$02,$03,$04,$05,$06,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
  .byte $F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF,$00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10
; perspective: scale (x 255) of the X distance from the centre, by line
FY:
  .byte $49,$4A,$4B,$4C,$4D,$4F,$50,$51,$52,$53,$54,$55,$57,$58,$59,$5A
  .byte $5B,$5C,$5D,$5E,$60,$61,$62,$63,$64,$65,$66,$68,$69,$6A,$6B,$6C
  .byte $6D,$6E,$70,$71,$72,$73,$74,$75,$76,$78,$79,$7A,$7B,$7C,$7D,$7E
  .byte $80,$81,$82,$83,$84,$85,$86,$87,$89,$8A,$8B,$8C,$8D,$8E,$8F,$91
  .byte $92,$93,$94,$95,$96,$97,$99,$9A,$9B,$9C,$9D,$9E,$9F,$A1,$A2,$A3
  .byte $A4,$A5,$A6,$A7,$A8,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B2,$B3,$B4,$B5
  .byte $B6,$B7,$B8,$BA,$BB,$BC,$BD,$BE,$BF,$C0,$C2,$C3,$C4,$C5,$C6,$C7
  .byte $C8,$C9,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D3,$D4,$D5,$D6,$D7,$D8,$D9
  .byte $DB,$DC,$DD,$DE,$DF,$E0,$E1,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EB,$EC
  .byte $ED,$EE,$EF,$F0,$F1,$F2,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FC,$FD,$FE
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; sprites 16x16: ship, raider small / medium / large (2 frames each), shot near / far,
; decoy (2 frames), 3 explosion frames
SPR_PAGES = 2
SPRITES:
  .byte $00,$00,$00,$01,$01,$03,$03,$27,$77,$FF,$FF,$60,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$80,$C0,$C0,$E4,$EE,$FF,$FF,$06,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$08,$05,$03,$07,$09,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$20,$40,$80,$C0,$20,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$07,$0B,$05,$04,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$A0,$40,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$11,$0B,$07,$0F,$17,$22,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$10,$A0,$C0,$E0,$D0,$88,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$07,$1F,$2F,$22,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$F0,$E8,$88,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$61,$33,$1B,$0F,$1F,$37,$62,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$06,$0C,$98,$B0,$E0,$F0,$D8,$8C,$06,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$03,$03,$0F,$3F,$7B,$C2,$80,$02,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$80,$E0,$F8,$BC,$86,$02,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$06,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$02,$04,$02,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$40,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$03,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$E0,$E0,$E0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$00,$00,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$B0,$00,$98,$60,$00,$78,$CC,$00,$60,$00,$00,$00
  .byte $00,$00,$02,$04,$09,$08,$40,$00,$00,$04,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$00,$04,$00,$10,$00,$00,$44,$82,$00,$00,$40,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$12,$15,$1A,$20,$2A,$00,$00,$12,$15,$1A,$20,$2A,$00,$00,$12
  .byte $15,$1A,$20,$2A,$21,$21,$22,$22,$23,$23,$24,$24,$25,$26,$26,$27
  .byte $27,$28,$29,$29,$2A,$2B,$2C,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34
  .byte $35,$37,$38,$39,$3B,$3C,$3E,$3F,$41,$43,$45,$47,$49,$4B,$4D,$50
  .byte $53,$56,$59,$5C,$60,$64,$68,$6D,$72,$78,$78,$70,$68,$62,$5C,$57
  .byte $52,$4E,$4A,$47,$78,$70,$68,$62,$5C,$57,$52,$4E,$4A,$47,$78,$70
  .byte $68,$62,$5C,$57,$52,$4E,$4A,$47,$78,$78,$78,$78,$78,$78,$00,$00
  .byte $78,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F,$5F,$00,$00,$5F,$5F
  .byte $5F,$5F,$5F,$5F,$50,$50,$50,$50,$50,$50,$00,$00,$50,$50,$50,$50
  .byte $50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$00,$00,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $50,$50,$50,$50,$50,$50,$00,$00,$50,$50,$50,$50,$50,$50,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$00,$00,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$28,$28,$28,$28
  .byte $28,$28,$00,$00,$00,$00,$28,$28,$28,$28,$28,$28,$00,$00,$00,$00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1F,$1B,$18,$16,$14,$00
  .byte $00,$1F,$1B,$18,$16,$14,$50,$50,$50,$50,$50,$00,$00,$50,$50,$50
  .byte $50,$50,$3F,$3F,$3F,$3F,$3F,$00,$00,$3F,$3F,$3F,$3F,$3F,$35,$35
  .byte $35,$35,$35,$00,$00,$35,$35,$35,$35,$35,$28,$28,$28,$28,$28,$00
  .byte $00,$28,$28,$28,$28,$28,$35,$35,$35,$35,$35,$00,$00,$35,$35,$35
  .byte $35,$35,$28,$28,$28,$28,$28,$00,$00,$28,$28,$28,$28,$28,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$00,$00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
WH_TH:
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0C,$0B,$0B,$0A,$00,$00,$07,$07,$06,$06,$06,$00,$00,$03
  .byte $03,$03,$03,$03,$0B,$0B,$0B,$05,$05,$05,$0B,$0B,$0B,$05,$05,$05
  .byte $0B,$0B,$0B,$05,$05,$05,$0B,$0B,$0B,$05,$05,$05,$0B,$0B,$0B,$05
  .byte $05,$05,$0B,$0B,$0B,$05,$05,$05,$0B,$0B,$0B,$05,$05,$02,$08,$08
  .byte $08,$02,$02,$02,$08,$08,$08,$02,$02,$02,$08,$08,$08,$08,$08,$08
  .byte $03,$03,$03,$03,$08,$08,$08,$08,$08,$08,$03,$03,$03,$03,$08,$08
  .byte $08,$08,$08,$08,$03,$03,$03,$03,$0C,$0B,$0B,$0A,$0A,$09,$00,$00
  .byte $06,$06,$06,$05,$05,$05,$0C,$0B,$0B,$0A,$0A,$09,$00,$00,$06,$06
  .byte $06,$05,$05,$05,$0C,$0B,$0B,$0A,$0A,$09,$00,$00,$06,$06,$06,$05
  .byte $05,$05,$0C,$0B,$0B,$0A,$0A,$09,$00,$00,$06,$06,$06,$05,$05,$05
  .byte $0C,$0B,$0B,$0A,$0A,$09,$00,$00,$06,$06,$06,$05,$05,$05,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$00,$00,$06,$06
  .byte $06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$05,$0D,$0C,$0B,$0B
  .byte $0A,$09,$00,$00,$00,$00,$0D,$0C,$0B,$0B,$0A,$09,$00,$00,$00,$00
  .byte $0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$0B,$0A,$0A,$09,$08,$00
  .byte $00,$06,$05,$05,$05,$04,$0C,$0B,$0B,$0A,$09,$00,$00,$05,$05,$05
  .byte $05,$04,$0C,$0B,$0B,$0A,$09,$00,$00,$05,$05,$05,$05,$04,$0C,$0B
  .byte $0B,$0A,$09,$00,$00,$05,$05,$05,$05,$04,$0C,$0B,$0B,$0A,$09,$00
  .byte $00,$05,$05,$05,$05,$04,$0C,$0B,$0B,$0A,$09,$00,$00,$05,$05,$05
  .byte $05,$04,$0C,$0B,$0B,$0A,$09,$00,$00,$05,$05,$05,$05,$04,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$00,$00
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04
WH_START:
  .byte $00,$01,$14,$4A,$68,$CC,$EA,$F6
WH_LEN:
  .byte $00,$13,$36,$1E,$64,$1E,$0C,$6A
W_SHOT = 1
W_DIVE = 2
W_HOVER = 3
W_START = 4
W_EXTRA = 5
W_DECOY = 6
W_CLEAR = 7

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0D,$0C,$0B,$09,$08,$07,$06,$05,$04,$02,$01,$08,$07,$06
  .byte $05,$03,$02,$01,$04,$03,$03,$02,$01,$01,$0F,$0F,$0F,$0E,$0E,$0E
  .byte $0D,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08
  .byte $08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03
  .byte $03,$02,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0E,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0C,$08,$08,$08,$08,$08,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$08,$04,$04,$04
  .byte $04,$04,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06,$06,$06,$05,$05
  .byte $05,$05,$05,$05,$04,$00,$00,$00,$00,$00,$03,$03,$03,$03,$03,$03
  .byte $02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00
EX_NP:
  .byte $00,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$08,$08,$09
  .byte $09,$0A,$0A,$0B,$0A,$0A,$0B,$0B,$0C,$0C,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$13,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16
  .byte $16,$16,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$13,$13
  .byte $13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15
  .byte $15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17
  .byte $17,$17
EX_VC:
  .byte $00,$0A,$09,$08,$07,$07,$06,$05,$04,$03,$02,$02,$01,$06,$05,$04
  .byte $03,$02,$02,$01,$03,$02,$02,$01,$01,$00,$0E,$0E,$0E,$0D,$0D,$0D
  .byte $0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$08,$07
  .byte $07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03,$03,$02,$02
  .byte $02,$01,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B
  .byte $0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08
  .byte $07,$07,$07,$07,$07,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$04
  .byte $04,$04,$04,$04,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$01,$01
  .byte $01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00
EX_TL:
  .byte $00,$1C,$27,$32,$3F,$4C,$5B,$6B,$7D,$91,$A6,$BE,$D9,$1C,$27,$32
  .byte $3F,$4C,$5B,$6B,$1C,$27,$32,$3F,$4C,$5B,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2
  .byte $E2,$E2,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12
EX_TH:
  .byte $00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04
EX_START:
  .byte $00,$01,$1A,$42
EX_LEN:
  .byte $00,$19,$28,$60
S_SMALL = 1
S_GROUND = 2
S_SHIP = 3
S_BIG = S_SHIP
