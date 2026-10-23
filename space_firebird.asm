;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_SPACE_FIREBIRD  -  Nintendo Space Firebird (1980)   ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: radar scope (NMI + trampoline $0FD0, joystick VIA,   ;
;   AY sound engine, players saved in RAM)                     ;
;                                                              ;
;   - a starfield that scrolls down (8 kinds of star tiles     ;
;     whose pattern moves, 2 speeds); the screen flashes red   ;
;     when the ship explodes, like the original                ;
;   - the Firebirds arrive as comets in a line, loop the loop  ;
;     and turn into birds; then they swoop on the ship firing, ;
;     climb, loop and fly away if they are not shot down       ;
;   - GULL 1 hit 20, EAGLE 2 hits 50 (drops a bomb), EMPEROR   ;
;     4 hits 100; the bomb bursts into shrapnel: shoot it from ;
;     right below, 50-200 (the lower the more)                 ;
;   - 50 Firebirds in every battle: all of them shot down =    ;
;     PERFECT, bonus 1000; missions GULL, EAGLE, EMPEROR, then ;
;     again faster; 3 ships, one more at 5000                  ;
;   - 1 or 2 players (alternating), title: button 1 = 1        ;
;     player, button 2 = 2 players                             ;
;   - joystick 1 ($D581) or joystick 2 ($D580):                ;
;       LEFT / RIGHT = move (near the edges the ship rises),   ;
;       button 1 = rapid fire (4 shots), button 2 or UP =      ;
;       WARP: once per ship, the shielded ship rockets up and  ;
;       rams the birds                                         ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     shot, bird hit and killed, comets arriving, transform,   ;
;     warp, falling bomb, explosions, battle start, PERFECT,   ;
;     extra ship                                               ;
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
PLX         = $82      ; ship X (centre)
PLST        = $83      ; 0 playing, 1 exploding, 3 explosion over
PLT         = $84      ; timer of the explosion
CURP        = $85      ; player playing (0 / 1)
NPL         = $86      ; number of players
LIVES       = $87      ; 2 bytes: ships per player
SCL         = $89      ; 2 bytes: score per player (BCD): tens and units
SCM         = $8B      ; 2 bytes: thousands and hundreds
SCH         = $8D      ; 2 bytes: hundred thousands and ten thousands
HISC        = $8F      ; 3 bytes BCD (low, middle, high)
BATTLE      = $92      ; ---- block of the player, saved:
LEFT        = $93      ;      Firebirds still to come in this battle
ESC         = $94      ;      Firebirds that flew away (0 = PERFECT)
EXTRA       = $95      ;      1 = extra ship given
FLKI        = $96      ;      next flock (path and side)
PLY         = $97      ; ship Y (centre)
WARP        = $98      ; 0 no, 1 going up, 2 coming back
WARPS       = $99      ; warps left to this ship
FIRECD      = $9A      ; frames before the next shot
SATB        = $9B      ; bytes of the SAT to copy
NACT        = $9C      ; Firebirds on the screen (or waiting to enter)
PTS_L       = $9D      ; points to add (BCD)
PTS_M       = $9E
DIFF        = $9F      ; difficulty: min(battle - 1, 7)
MISSION     = $A0      ; 0 gull, 1 eagle, 2 emperor
FLOCKT      = $A1      ; frames before the next flock can come
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
FLK_N       = $AD      ; birds of the flock
HW          = $AE      ; half width for the hits
CNT         = $AF

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

; ---------------- Firebirds: 0 free, 1 waiting to enter, 2 comet, 3 transforming, 4 bird
NBD    = 10
E_ST   = $0300
E_T    = $030A           ; timer (waiting, segment of the path, transform, loop, climb)
E_TYPE = $0314           ; 0 gull, 1 eagle, 2 emperor
E_HP   = $031E           ; hits still needed
E_XL   = $0328           ; X 8.8
E_X    = $0332
E_YL   = $033C           ; Y 8.8
E_Y    = $0346
E_ANG  = $0350           ; direction 0-255 (0 up, clockwise)
E_TURN = $035A           ; turn per frame (path, loop)
E_SEG  = $0364           ; next segment of the path (offset in SEGS)
E_MIR  = $036E           ; 1 = path mirrored
E_MODE = $0378           ; bird: 0 swoop, 1 climb, 2 loop, 3 leave
E_MAN  = $0382           ; swoops left before leaving
E_SPD  = $038C           ; speed 0-3
E_TGX  = $0396           ; target of the climb
E_TGY  = $03A0
E_FLSH = $03AA           ; frames of the white flash (hit)
E_BMB  = $03B4           ; 1 = can drop a bomb in this swoop
E_FT   = $03BE           ; frames to the next bullet

; ---------------- shots of the ship
NS     = 4
S_ON   = $0400
S_X    = $0404
S_Y    = $0408

; ---------------- bullets and shrapnel: L_ON = 0 free, 1 bullet, 2 shrapnel
NL     = 12
L_ON   = $0410
L_XL   = $041C
L_X    = $0428
L_YL   = $0434
L_Y    = $0440
L_VXL  = $044C
L_VXH  = $0458
L_VYL  = $0464
L_VYH  = $0470

; ---------------- bombs of the eagles
NBB    = 3
B_ON   = $0490
B_X    = $0493
B_YL   = $0496
B_Y    = $0499
B_VL   = $049C           ; falling speed 8.8
B_VH   = $049F
B_BY   = $04A2           ; it bursts at this Y

; ---------------- explosions
NX     = 6
X_T    = $04B0           ; frames left (0 = free)
X_X    = $04B6
X_Y    = $04BC

ST_Y   = $04C8           ; line of every kind of star (0-63)

PSAVE      = $0500       ; 2 x 8 bytes: block of every player
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
PLAYER_Y    = 176        ; ship (centre) in the middle of the screen
WARP_TOP    = 44         ; the warp goes up to here
X_MIN       = 12         ; ship
X_MAX       = 244
DELAY       = 10         ; frames between two comets of a flock
LIFE_T      = 96         ; HUD tiles of the third 2
WARP_T      = 97
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
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
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
  LDX #$00                     ; the Firebirds of the table (sprites)
  LDY #$00
.ti_s:
  LDA TITLE_SY,X
  STA SAT_BUFFER,Y
  LDA #76
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
;  NEW GAME: battle 1 for every player, saved
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
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #$03
  STA LIVES,X
  LDA #$01
  STA BATTLE
  LDA #50
  STA LEFT
  STZ ESC
  STZ EXTRA
  STZ FLKI
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER: "PLAYER <n>" and "BATTLE <n>", then the game
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
  STZ WARP
  STZ FLASH
  LDA #$01
  STA WARPS
  JSR SHIP_BASE
  STA PLY
  LDA #90
  STA FLOCKT
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
  LDA #<TXT_BATTLE
  STA TP
  LDA #>TXT_BATTLE
  STA TP+1
  JSR PRINT
  LDA BATTLE
  JSR BIN2BCD
  LDX #13
  LDY #18
  JSR PUT_BCD2
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #W_START
  LDX #2
  JSR SFX_WHISTLE
  LDA #150
  JSR WAIT_STARS
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
  JSR UPDATE_BIRDS
  JSR UPDATE_SHOTS
  JSR UPDATE_BULLETS
  JSR UPDATE_BOMBS
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
  LDA LEFT                     ; battle over: no more Firebirds to come or on the screen
  ORA NACT
  BNE .gl_n
  JMP BATTLE_END
.gl_n:
  JMP GAME_LOOP

; BATTLE -> DIFF = min(battle - 1, 7), MISSION = (battle - 1) mod 3
SET_LEVEL:
  LDA BATTLE
  DEC A
  CMP #8
  BCC .sl_d
  LDA #7
.sl_d:
  STA DIFF
  LDA BATTLE
  DEC A
.sl_m:
  CMP #3
  BCC .sl_s
  SBC #3
  BRA .sl_m
.sl_s:
  STA MISSION
  RTS


; ---------------------------------------------------------------
; all the Firebirds of the battle came: PERFECT if none flew away
; ---------------------------------------------------------------
BATTLE_END:
  LDX #$FF
  TXS
  LDA #40                      ; the last explosions
  JSR WAIT_STARS
  JSR HIDE_SPRITES
  LDA ESC
  BNE .be_next
  JSR VDP_INT_OFF
  LDA #<TXT_PERFECT
  STA TP
  LDA #>TXT_PERFECT
  STA TP+1
  JSR PRINT
  STZ PTS_L
  LDA #$10
  STA PTS_M
  JSR ADD_SCORE
  JSR VDP_INT_ON
  LDA #W_PERFECT
  LDX #2
  JSR SFX_WHISTLE
  LDA #150
  JSR WAIT_STARS
.be_next:
  LDA BATTLE
  CMP #99
  BCS .be_s
  INC BATTLE
.be_s:
  LDA #50
  STA LEFT
  STZ ESC
  LDX CURP
  JSR SAVE_PLAYER
  JMP TURN_START

; ---------------------------------------------------------------
; the explosion of the ship is over
; ---------------------------------------------------------------
LOSE_LIFE:
  LDX #$FF
  TXS
  LDA LEFT                     ; the Firebirds on the screen come back later
  CLC
  ADC NACT
  STA LEFT
  STZ NACT
  LDX CURP
  DEC LIVES,X
  JSR SAVE_PLAYER
  LDA #30
  JSR WAIT_STARS
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
  JSR WAIT_STARS
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


; ===============================================================
;  THE SHIP
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
  LDA WARP
  BNE .us_warp
  LDA JOYP                     ; button 2 or UP just pressed: warp
  EOR #$FF
  AND JOYC
  AND #%00100001
  BEQ .us_base
  LDA WARPS
  BEQ .us_base
  STZ WARPS
  LDA #$01
  STA WARP
  LDA #W_WARP
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
.us_base:
  JSR SHIP_BASE
  STA PLY
  BRA .us_fire
.us_warp:
  CMP #$01
  BNE .us_down
  LDA PLY                      ; rocketing up
  SEC
  SBC #4
  STA PLY
  CMP #WARP_TOP
  BCS .us_fire
  LDA #$02
  STA WARP
  BRA .us_fire
.us_down:
  LDA PLY                      ; back to its place
  CLC
  ADC #2
  STA PLY
  JSR SHIP_BASE
  CMP PLY
  BCS .us_fire
  STA PLY
  STZ WARP
.us_fire:
  LDA FIRECD
  BEQ .us_f
  DEC FIRECD
  RTS
.us_f:
  LDA JOYC                     ; rapid fire: holding the button keeps firing
  AND #$10
  BNE FIRE
  RTS

; a new shot from the ship (4 at the same time)
FIRE:
  LDX #(NS-1)
.fi_l:
  LDA S_ON,X
  BEQ .fi_free
  DEX
  BPL .fi_l
  RTS
.fi_free:
  LDA #$01
  STA S_ON,X
  LDA PLX
  STA S_X,X
  LDA PLY
  SEC
  SBC #8
  STA S_Y,X
  LDA #7
  STA FIRECD
  LDA #W_SHOT
  LDX #0
  JMP SFX_WHISTLE

; A = Y of the ship at its X (it rises near the edges)
SHIP_BASE:
  LDA PLX
  LSR A
  LSR A
  LSR A
  TAY
  LDA #PLAYER_Y
  SEC
  SBC NUDGE,Y
  RTS

; the ship is hit (keeps X and Y)
PLAYER_DIE:
  PHX
  PHY
  LDA #$01
  STA PLST
  LDA #120
  STA PLT
  LDA #48
  STA FLASH
  STZ WARP
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
;  SHOTS OF THE SHIP
; ===============================================================
UPDATE_SHOTS:
  LDX #(NS-1)
.sh_l:
  STX SI
  LDA S_ON,X
  BEQ .sh_n
  LDA S_Y,X
  SEC
  SBC #6
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

; shot SI against the Firebirds and the bombs
SHOT_HITS:
  LDX #(NBD-1)
.sx_a:
  LDA E_ST,X
  CMP #2
  BCC .sx_an
  LDY E_TYPE,X
  LDA HWID,Y
  LDY E_ST,X
  CPY #2
  BNE .sx_hw
  LDA #5                       ; comet: small
.sx_hw:
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
  JMP HIT_BIRD
.sx_an:
  DEX
  BPL .sx_a
  LDX #(NBB-1)
.sx_b:
  LDA B_ON,X
  BEQ .sx_bn
  LDY SI
  LDA B_X,X
  SEC
  SBC S_X,Y
  JSR ABS_A
  CMP #6
  BCS .sx_bn
  LDA B_Y,X
  SEC
  SBC S_Y,Y
  JSR ABS_A
  CMP #8
  BCS .sx_bn
  LDA #$00                     ; bomb shot: points by its height, then it bursts
  STA S_ON,Y
  LDA B_Y,X
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  TAY
  LDA BOMB_PL,Y
  STA PTS_L
  LDA BOMB_PM,Y
  STA PTS_M
  JSR ADD_SCORE
  JMP BURST
.sx_bn:
  DEX
  BPL .sx_b
  RTS

; A = |A| (signed)
ABS_A:
  BPL .ab_r
  EOR #$FF
  INC A
.ab_r:
  RTS


; ===============================================================
;  FLOCKS: a line of comets on one of the paths
; ===============================================================
SPAWN:
  LDA PLST
  BNE .sp_r
  LDA FLOCKT
  BEQ .sp_t
  DEC FLOCKT
.sp_r:
  RTS
.sp_t:
  LDA LEFT
  BEQ .sp_r
  LDY DIFF
  LDA NACT
  CMP SPAWN_AT,Y               ; still too many on the screen
  BCS .sp_r
  LDY MISSION
  LDA FLOCK_K,Y
  CMP LEFT
  BCC .sp_k
  LDA LEFT
.sp_k:
  STA FLK_N
  CLC
  ADC NACT
  CMP #(NBD+1)
  BCS .sp_r                    ; not enough free places
  STA NACT
  LDA LEFT
  SEC
  SBC FLK_N
  STA LEFT
  LDY DIFF
  LDA FLOCK_GAP,Y
  STA FLOCKT
  LDA FLKI                     ; path = (FLKI / 2) mod 4, mirrored on odd flocks
  INC FLKI
  TAY
  AND #$01
  STA T2
  TYA
  LSR A
  AND #$03
  STA T3
  STZ CNT                      ; bird of the flock
  LDX #(NBD-1)
.sp_l:
  LDA E_ST,X
  BEQ .sp_new
  JMP .sp_n
.sp_new:
  LDA #$01
  STA E_ST,X
  LDA CNT                      ; waits CNT * 10 + 1 frames
  ASL A
  ASL A
  ADC CNT
  ASL A
  INC A
  STA E_T,X
  LDA MISSION                  ; the kind of bird
  ASL A
  ASL A
  ASL A
  ORA CNT
  TAY
  LDA FLOCK_TY,Y
  STA E_TYPE,X
  TAY
  LDA HP_T,Y
  STA E_HP,X
  LDY T3
  LDA SCR_S,Y
  STA E_SEG,X
  LDA SCR_Y,Y
  STA E_Y,X
  LDA SCR_X,Y
  STA E_X,X
  LDA SCR_A,Y
  STA E_ANG,X
  LDA T2
  STA E_MIR,X
  BEQ .sp_m
  LDA E_X,X                    ; mirrored: X = 255 - X, angle = - angle
  EOR #$FF
  STA E_X,X
  LDA #$00
  SEC
  SBC E_ANG,X
  STA E_ANG,X
.sp_m:
  LDA #$80
  STA E_XL,X
  STA E_YL,X
  STZ E_FLSH,X
  STZ E_BMB,X
  INC CNT
  LDA CNT
  CMP FLK_N
  BEQ .sp_done
.sp_n:
  DEX
  BMI .sp_done
  JMP .sp_l
.sp_done:
  LDA #W_COMET
  LDX #1
  JMP SFX_WHISTLE


; ===============================================================
;  FIREBIRDS
; ===============================================================
UPDATE_BIRDS:
  LDX #(NBD-1)
.ub_l:
  LDA E_ST,X
  BEQ .ub_n
  LDY E_FLSH,X
  BEQ .ub_s
  DEC E_FLSH,X
.ub_s:
  CMP #$01
  BNE .ub_c
  DEC E_T,X                    ; waiting to enter
  BNE .ub_n
  LDA #$02
  STA E_ST,X
  JSR NEXT_SEG
  BRA .ub_n
.ub_c:
  CMP #$02
  BNE .ub_t
  JSR COMET
  BRA .ub_hit
.ub_t:
  CMP #$03
  BNE .ub_f
  JSR TRANSFORM
  BRA .ub_hit
.ub_f:
  JSR FLY
.ub_hit:
  JSR BIRD_SHIP
.ub_n:
  DEX
  BPL .ub_l
  RTS

; X = bird: the next segment of its path, or the transform at the end
NEXT_SEG:
  LDY E_SEG,X
  LDA SEGS,Y
  BEQ .ns_end
  STA E_T,X
  LDA SEGS+2,Y
  STA E_SPD,X
  LDA SEGS+1,Y
  PHA
  INY
  INY
  INY
  TYA
  STA E_SEG,X
  PLA
  LDY E_MIR,X
  BEQ .ns_t
  EOR #$FF                     ; mirrored: the other way round
  INC A
.ns_t:
  STA E_TURN,X
  RTS
.ns_end:
  LDA #$03
  STA E_ST,X
  LDA #24
  STA E_T,X
  STZ E_SPD,X
  PHX
  LDA #W_TRANS
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS

; X = comet: along its path
COMET:
  LDA E_ANG,X
  CLC
  ADC E_TURN,X
  STA E_ANG,X
  JSR MOVE_B
  DEC E_T,X
  BNE .co_r
  JMP NEXT_SEG
.co_r:
  RTS

; X = comet becoming a bird: slow, then it starts to fly
TRANSFORM:
  JSR MOVE_B
  DEC E_T,X
  BNE .tr_r
  LDA #$04
  STA E_ST,X
  LDY DIFF
  LDA MANS,Y
  STA E_MAN,X
  JSR NEXT_RND
  AND #$1F
  CLC
  ADC #20
  STA E_FT,X
  JSR NEXT_RND
  BMI START_LOOP
  JMP START_SWOOP
.tr_r:
  RTS

START_SWOOP:
  STZ E_MODE,X
  LDA #$01
  STA E_BMB,X
  RTS

START_LOOP:                    ; a full circle, one way or the other
  LDA #$02
  STA E_MODE,X
  LDA #64
  STA E_T,X
  LDA RND
  AND #$02
  BEQ .sl_l
  LDA #$04
  STA E_TURN,X
  RTS
.sl_l:
  LDA #$FC
  STA E_TURN,X
  RTS

START_CLIMB:                   ; back up to a random point of the sky
  LDA #$01
  STA E_MODE,X
  LDA #120
  STA E_T,X
  JSR NEXT_RND
  AND #$7F
  STA T0
  JSR NEXT_RND
  AND #$3F
  CLC
  ADC T0
  ADC #32
  STA E_TGX,X
  JSR NEXT_RND
  AND #$1F
  CLC
  ADC #32
  STA E_TGY,X
  RTS

; X = bird: swoop, climb, loop or leave
FLY:
  LDA E_FT,X
  BEQ .fy_m
  DEC E_FT,X
.fy_m:
  LDA E_MODE,X
  BEQ SWOOP
  CMP #$01
  BNE .fy_2
  JMP CLIMB
.fy_2:
  CMP #$02
  BNE .fy_3
  JMP LOOP
.fy_3:
  JMP LEAVE

; dive towards the ship, firing; the eagles drop a bomb
SWOOP:
  LDA PLX
  STA TX
  LDA PLY
  STA TY
  JSR AIM
  PHA
  LDY DIFF
  LDA TRN_T,Y
  JSR SET_TRN
  PLA
  JSR STEER
  LDY DIFF
  LDA SWS_T,Y
  STA E_SPD,X
  JSR MOVE_B
  JSR BOUNDS
  JSR MAY_FIRE
  JSR MAY_BOMB
  LDA E_Y,X
  CMP #140
  BCC .sw_r
  LDA E_MAN,X                  ; low enough: back up
  BEQ .sw_c
  DEC E_MAN,X
.sw_c:
  JMP START_CLIMB
.sw_r:
  RTS

CLIMB:
  LDA E_TGX,X
  STA TX
  LDA E_TGY,X
  STA TY
  JSR AIM
  PHA
  LDA #4
  JSR SET_TRN
  PLA
  JSR STEER
  LDA #$01
  STA E_SPD,X
  JSR MOVE_B
  JSR BOUNDS
  DEC E_T,X                    ; never reached: go on anyway
  BEQ .cl_next
  LDA E_X,X
  SEC
  SBC E_TGX,X
  JSR ABS_A
  CMP #12
  BCS .cl_r
  LDA E_Y,X
  SEC
  SBC E_TGY,X
  JSR ABS_A
  CMP #12
  BCS .cl_r
.cl_next:
  LDA E_MAN,X
  BNE .cl_more
  LDA #$03                     ; no more swoops: it flies away
  STA E_MODE,X
  RTS
.cl_more:
  JSR NEXT_RND
  BMI .cl_loop
  JMP START_SWOOP
.cl_loop:
  JMP START_LOOP
.cl_r:
  RTS

LOOP:
  LDA E_ANG,X
  CLC
  ADC E_TURN,X
  STA E_ANG,X
  LDA #$01
  STA E_SPD,X
  JSR MOVE_B
  JSR BOUNDS
  JSR MAY_FIRE
  DEC E_T,X
  BNE .lo_r
  JMP START_SWOOP
.lo_r:
  RTS

; up and out of the screen: one more Firebird got away
LEAVE:
  LDA #4
  JSR SET_TRN
  LDA #$00
  JSR STEER
  LDA #$02
  STA E_SPD,X
  JSR MOVE_B
  JSR BOUNDS_XB
  LDA E_Y,X
  CMP #14
  BCC .le_gone
  CMP #240
  BCC .le_r
.le_gone:
  STZ E_ST,X
  DEC NACT
  INC ESC
.le_r:
  RTS

; X = bird: position += speed along its direction
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

; X = bird: kept inside the field, it bounces off the edges
BOUNDS:
  LDA E_Y,X
  CMP #16
  BCC BO_TOP
  CMP #240
  BCS BO_TOP
  ; fall into BOUNDS_XB
BOUNDS_XB:                     ; sides and bottom only
  LDA E_Y,X
  CMP #185
  BCC BO_X
  CMP #240
  BCS BO_X
  LDA #184
  STA E_Y,X
  JSR FLIP_V
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
BO_TOP:
  LDA #16
  STA E_Y,X
  JSR FLIP_V
  BRA BO_X

FLIP_V:
  LDA #128
  SEC
  SBC E_ANG,X
  STA E_ANG,X
  RTS

; A = max turn per frame
SET_TRN:
  STA TRN
  EOR #$FF
  INC A
  STA TRNEG
  RTS

; X = bird, A = direction wanted: turn towards it, TRN at most
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

; X = bird, TX / TY = target -> A = direction from the bird to the target
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

; X = bird: now and then a bullet aimed at the ship
MAY_FIRE:
  LDA E_FT,X
  BNE .mf_r
  JSR NEXT_RND
  AND #$1F
  LDY DIFF
  CLC
  ADC FGAP,Y
  STA E_FT,X
  LDA PLST
  BNE .mf_r
  LDA E_Y,X
  CMP #150
  BCS .mf_r
  LDY #(NL-1)
.mf_f:
  LDA L_ON,Y
  BEQ .mf_new
  DEY
  BPL .mf_f
.mf_r:
  RTS
.mf_new:
  LDA #$01
  STA L_ON,Y
  LDA E_X,X
  STA L_X,Y
  STA SX
  LDA E_Y,X
  CLC
  ADC #4
  STA L_Y,Y
  STA SY
  LDA #$80
  STA L_XL,Y
  STA L_YL,Y
  LDA PLX
  STA TX
  LDA PLY
  STA TY
  PHY
  JSR ANGLE_TO
  PLY
  ; fall into SET_LV

; A = direction, Y = bullet: its speed (keeps X and Y)
SET_LV:
  PHX
  LSR A
  LSR A
  TAX
  LDA BVXL,X
  STA L_VXL,Y
  LDA BVXH,X
  STA L_VXH,Y
  LDA BVYL,X
  STA L_VYL,Y
  LDA BVYH,X
  STA L_VYH,Y
  PLX
  RTS

; X = eagle swooping: one bomb when it is above the ship
MAY_BOMB:
  LDA E_TYPE,X
  CMP #$01
  BNE .mb_r
  LDA E_BMB,X
  BEQ .mb_r
  LDA E_Y,X
  CMP #40
  BCC .mb_r
  CMP #110
  BCS .mb_r
  LDA E_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #40
  BCS .mb_r
  LDY #(NBB-1)
.mb_f:
  LDA B_ON,Y
  BEQ .mb_new
  DEY
  BPL .mb_f
.mb_r:
  RTS
.mb_new:
  STZ E_BMB,X
  LDA #$01
  STA B_ON,Y
  LDA E_X,X
  STA B_X,Y
  LDA E_Y,X
  CLC
  ADC #6
  STA B_Y,Y
  LDA #$00
  STA B_YL,Y
  STA B_VH,Y
  LDA #$60
  STA B_VL,Y
  JSR NEXT_RND                 ; it bursts between 124 and 155
  AND #$1F
  CLC
  ADC #124
  STA B_BY,Y
  PHX
  LDA #W_BOMB
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS

; X = bird: does it hit the ship? (the warp shield kills it)
BIRD_SHIP:
  LDA E_ST,X
  CMP #$02
  BCC .bs_r
  LDA PLST
  BNE .bs_r
  LDA WARP
  BEQ .bs_n
  LDA E_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #14
  BCS .bs_r
  LDA E_Y,X
  SEC
  SBC PLY
  JSR ABS_A
  CMP #14
  BCS .bs_r
  JMP KILL_BIRD
.bs_n:
  LDA E_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #10
  BCS .bs_r
  LDA E_Y,X
  SEC
  SBC PLY
  JSR ABS_A
  CMP #9
  BCS .bs_r
  JSR KILL_BIRD
  JMP PLAYER_DIE
.bs_r:
  RTS

; X = bird hit by a shot: one hit less, or shot down
HIT_BIRD:
  DEC E_HP,X
  BEQ KILL_BIRD
  LDA #6
  STA E_FLSH,X
  PHX
  LDA #W_HIT
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS

; X = bird shot down: points, explosion (keeps X)
KILL_BIRD:
  LDY E_TYPE,X
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
  LDY E_X,X
  LDA #S_SMALL
  JSR BOOM_AT
  LDA #W_KILL
  LDX #1
  JSR SFX_WHISTLE
  PLX
  STZ E_ST,X
  DEC NACT
  RTS


; ===============================================================
;  BULLETS AND SHRAPNEL
; ===============================================================
UPDATE_BULLETS:
  LDX #(NL-1)
.bl_l:
  LDA L_ON,X
  BEQ .bl_n
  CLC
  LDA L_XL,X
  ADC L_VXL,X
  STA L_XL,X
  LDA L_X,X
  ADC L_VXH,X
  STA L_X,X
  CMP #4
  BCC .bl_off
  CMP #252
  BCS .bl_off
  CLC
  LDA L_YL,X
  ADC L_VYL,X
  STA L_YL,X
  LDA L_Y,X
  ADC L_VYH,X
  STA L_Y,X
  CMP #12
  BCC .bl_off
  CMP #192
  BCS .bl_off
  LDA PLST
  BNE .bl_n
  LDA #5                       ; ship 5 x 6, shield 12 x 12
  LDY WARP
  BEQ .bl_w
  LDA #12
.bl_w:
  STA HW
  LDA L_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP HW
  BCS .bl_n
  LDA HW
  INC A
  STA HW
  LDA L_Y,X
  SEC
  SBC PLY
  JSR ABS_A
  CMP HW
  BCS .bl_n
  STZ L_ON,X
  LDA WARP                     ; the shield stops it
  BNE .bl_n
  JSR PLAYER_DIE
  BRA .bl_n
.bl_off:
  STZ L_ON,X
.bl_n:
  DEX
  BPL .bl_l
  RTS


; ===============================================================
;  BOMBS: they fall faster and faster and burst into shrapnel
; ===============================================================
UPDATE_BOMBS:
  LDX #(NBB-1)
.bb_l:
  LDA B_ON,X
  BEQ .bb_n
  CLC
  LDA B_VL,X
  ADC #$03
  STA B_VL,X
  BCC .bb_v
  INC B_VH,X
.bb_v:
  CLC
  LDA B_YL,X
  ADC B_VL,X
  STA B_YL,X
  LDA B_Y,X
  ADC B_VH,X
  STA B_Y,X
  CMP B_BY,X
  BCC .bb_hit
  JSR BURST
  BRA .bb_n
.bb_hit:
  LDA PLST                     ; only the warping ship can reach it
  BNE .bb_n
  LDA WARP
  BEQ .bb_n
  LDA B_X,X
  SEC
  SBC PLX
  JSR ABS_A
  CMP #12
  BCS .bb_n
  LDA B_Y,X
  SEC
  SBC PLY
  JSR ABS_A
  CMP #12
  BCS .bb_n
  JSR BURST
.bb_n:
  DEX
  BPL .bb_l
  RTS

; X = bomb: it bursts into 4 pieces flying down and outwards (keeps X)
BURST:
  STZ B_ON,X
  LDA B_X,X
  STA TX
  STA SX
  LDA B_Y,X
  STA TY
  STA SY
  JSR NEW_EXPL
  PHX
  LDY B_X,X
  LDA #S_BOMB
  JSR BOOM_AT
  PLX
  LDA #3
  STA CNT
.bu_l:
  LDY #(NL-1)
.bu_f:
  LDA L_ON,Y
  BEQ .bu_new
  DEY
  BPL .bu_f
  RTS
.bu_new:
  LDA #$02
  STA L_ON,Y
  LDA SX
  STA L_X,Y
  LDA SY
  STA L_Y,Y
  LDA #$80
  STA L_XL,Y
  STA L_YL,Y
  PHY
  LDY CNT
  LDA SHRAP_A,Y
  PLY
  JSR SET_LV
  DEC CNT
  BPL .bu_l
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
  LDX #(NBD-1)
.co_a:
  STZ E_ST,X
  DEX
  BPL .co_a
  LDX #(NS-1)
.co_s:
  STZ S_ON,X
  DEX
  BPL .co_s
  LDX #(NL-1)
.co_l:
  STZ L_ON,X
  DEX
  BPL .co_l
  LDX #(NBB-1)
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


; ===============================================================
;  PLAYERS: save / load the block BATTLE-FLKI
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.sp_b:
  LDA BATTLE,X
  STA PSAVE,Y
  INY
  INX
  CPX #5
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.lp_b:
  LDA PSAVE,Y
  STA BATTLE,X
  INY
  INX
  CPX #5
  BNE .lp_b
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M (BCD) to the player playing; one more ship at 5000 (keeps X)
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
  CMP #$50
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
  LDA BATTLE
  JSR BIN2BCD
  LDX #23
  LDY #28
  JSR PUT_BCD2
  ; fall into DRAW_LIVES

; spare ships of the player playing and the warp: row 23
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
  LDA #0
  STA VDATA
  LDA #WARP_T                  ; column 10: the warp is ready
  LDX WARPS
  BNE .dl_wp
  LDA #0
.dl_wp:
  STA VDATA
  PLX
  RTS

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
;  SPRITES: ship, bullets, bombs, Firebirds, shots, explosions;
;  the Firebirds are listed backwards on odd frames, so with more
;  than 4 sprites on a line they flicker instead of disappearing
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA PLX
  STA OX
  LDA PLY
  STA OY
  LDA PLST
  BEQ .bs_ship
  CMP #$01
  BNE .bs_bul
  LDA PLT                      ; the ship explodes
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
  BRA .bs_bul
.bs_ship:
  LDA WARP
  BEQ .bs_sh
  LDA #4                       ; the shield of the warp
  STA ON
  LDA FRAME_CNT
  LSR A
  AND #$03
  TAX
  LDA SHIELD_COL,X
  STA OC
  JSR ADD_SPR
.bs_sh:
  STZ ON
  LDA #$0F
  STA OC
  JSR ADD_SPR
.bs_bul:
  LDX #(NL-1)                  ; bullets and shrapnel
.bs_ll:
  LDA L_ON,X
  BEQ .bs_ln
  LDY #12
  LDA #$0A
  STA OC
  LDA L_ON,X
  CMP #$02
  BNE .bs_lk
  LDY #16
  LDA #$09
  STA OC
.bs_lk:
  STY ON
  LDA L_X,X
  STA OX
  LDA L_Y,X
  STA OY
  PHX
  JSR ADD_SPR
  PLX
.bs_ln:
  DEX
  BPL .bs_ll
  LDX #(NBB-1)                 ; bombs: red / white
.bs_bl:
  LDA B_ON,X
  BEQ .bs_bn
  LDA B_X,X
  STA OX
  LDA B_Y,X
  STA OY
  LDA #20
  STA ON
  LDA FRAME_CNT
  AND #$04
  BEQ .bs_bw
  LDA #$08
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
  LDX #(NBD-1)                 ; Firebirds
.bs_el:
  TXA
  TAY
  LDA FRAME_CNT
  LSR A
  BCC .bs_eo
  TXA
  EOR #$FF
  CLC
  ADC #NBD
  TAY                          ; odd frames: NBD-1-X
.bs_eo:
  LDA E_ST,Y
  CMP #$02
  BCC .bs_en
  JSR BIRD_SPR
  PHX
  JSR ADD_SPR
  PLX
.bs_en:
  DEX
  BPL .bs_el
  LDX #(NS-1)                  ; shots
.bs_sl:
  LDA S_ON,X
  BEQ .bs_sn
  LDA S_X,X
  STA OX
  LDA S_Y,X
  STA OY
  LDA #8
  STA ON
  LDA #$0B
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.bs_sn:
  DEX
  BPL .bs_sl
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

; Y = Firebird (state 2-4): OX, OY, ON, OC
BIRD_SPR:
  LDA E_X,Y
  STA OX
  LDA E_Y,Y
  STA OY
  LDA E_ST,Y
  CMP #$03
  BCC .bp_comet
  BNE .bp_bird
  LDA E_T,Y                    ; transforming: comet and bird in turn
  AND #$02
  BEQ .bp_comet
.bp_bird:
  TYA                          ; wings: every bird at its own pace
  ASL A
  ASL A
  ADC FRAME_CNT
  AND #$08
  LSR A
  STA ON
  LDA E_TYPE,Y
  PHY
  TAY
  LDA BIRD_N,Y
  CLC
  ADC ON
  STA ON
  LDA BIRD_C,Y
  PLY
  STA OC
  LDA E_FLSH,Y                 ; hit: white
  BEQ .bp_r
  LDA #$0F
  STA OC
.bp_r:
  RTS
.bp_comet:
  LDA FRAME_CNT
  AND #$04
  CLC
  ADC #24
  STA ON
  TYA                          ; every comet with its own colour
  ASL A
  ASL A
  ADC FRAME_CNT
  LSR A
  LSR A
  AND #$03
  PHY
  TAY
  LDA COMET_C,Y
  PLY
  STA OC
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
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI


; ===============================================================
;  SOUND: effects only (no music on the cabinet)
;  per chip: A = tone effects, B = noise and C = low tone of the
;  explosions; left chip = the ship, right chip = the Firebirds
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
PS_OFF:     .byte 0,8                          ; block of the player in PSAVE
; the ship rises near the edges: pixels by X / 8
NUDGE:      .byte 8,8,6,4,2,0,0,0,0,0,0,0,0,0,0,0
            .byte 0,0,0,0,0,0,0,0,0,0,0,2,4,6,8,8
; by kind of Firebird (0 gull, 1 eagle, 2 emperor)
BIRD_N:     .byte 32,40,48                     ; sprite pattern (frame 0)
BIRD_C:     .byte $07,$0D,$09                  ; colour
HP_T:       .byte 1,2,4                        ; hits needed
HWID:       .byte 7,8,9                        ; half width for the hits (+1)
PTS_TL:     .byte $20,$50,$00                  ; points (BCD): 20, 50, 100
PTS_TM:     .byte $00,$00,$01
; bomb shot: points by Y / 32 (the lower the more)
BOMB_PL:    .byte $50,$50,$00,$50,$00,$00,$00,$00
BOMB_PM:    .byte $00,$00,$01,$01,$02,$02,$02,$02
; shrapnel: 4 directions, down and outwards (nothing straight down)
SHRAP_A:    .byte 80,108,148,176
; flock of every mission: number of birds, kind of every bird
FLOCK_K:    .byte 6,5,5
FLOCK_TY:   .byte 0,0,0,0,0,0,0,0                ; GULL battle
            .byte 1,0,1,0,1,0,0,0                ; EAGLE battle
            .byte 2,1,0,1,0,0,0,0                ; EMPEROR battle
; by difficulty (battle 1-8, then always 8)
SPAWN_AT:   .byte 2,2,3,3,4,4,4,4              ; a new flock when fewer are on the screen
FLOCK_GAP:  .byte 120,110,100,90,80,70,60,60   ; frames between two flocks at least
TRN_T:      .byte 3,3,4,4,4,5,5,6              ; swoop: turn per frame
SWS_T:      .byte 2,2,2,2,3,3,3,3              ; swoop: speed
FGAP:       .byte 100,90,80,70,60,50,45,40     ; frames between two bullets (+ 0-31)
MANS:       .byte 2,2,3,3,3,4,4,4              ; swoops before flying away
; ANGLE_TO: base and sign by SGN (closer to horizontal, then to vertical)
AT_BASE:    .byte 64,64,192,192,128,0,128,0
AT_SUB:     .byte 0,1,1,0,1,0,0,1
; sprites
EXPL_N:     .byte 56,60,64,60                  ; explosion frames
EXPL_C:     .byte $0B,$0A,$09,$0A
FLAME_COL:  .byte $0B,$0A,$09,$0F
SHIELD_COL: .byte $07,$05,$0F,$0D
COMET_C:    .byte $0B,$0A,$09,$0F
; title: the Firebirds of the scoring table (sprite Y, pattern, colour)
TITLE_SY:   .byte 11*8-6,13*8-6,15*8-6,17*8-6
TITLE_SN:   .byte 32,40,48,20
TITLE_SC:   .byte $07,$0D,$09,$08

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_BOT:
  .byte 23,21,"BATTLE",0
  .byte $FF
TXT_TITLE:
  .byte 9,8,"- SCORE TABLE -",0
  .byte 11,13,"GULL       20",0
  .byte 13,13,"EAGLE      50",0
  .byte 15,13,"EMPEROR   100",0
  .byte 17,13,"BOMB   50-200",0
  .byte 19,2,"50 FIREBIRDS IN EVERY BATTLE",0
  .byte 20,4,"PERFECT 1000   SHIP 5000",0
  .byte 22,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_PLAYER:
  .byte 11,12,"PLAYER ",0
  .byte $FF
TXT_BATTLE:
  .byte 13,11,"BATTLE ",0
  .byte $FF
TXT_PERFECT:
  .byte 11,12,"PERFECT!",0
  .byte 13,10,"BONUS  1000",0
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
; starfield: 8 kinds x 8 tiles (128-191), pattern and colour (background transparent)
STAR_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00
  .byte $80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
STAR_BIT:
  .byte $01,$40,$01,$20,$20,$20,$40,$80
STAR_Y0:
  .byte $32,$1C,$21,$38,$29,$18,$3D,$00
STAR_SLOW:                ; 0 = one pixel every frame, 1 = every other frame
  .byte $00,$00,$00,$00,$01,$01,$01,$01

; name table of the field: stars on rows 2-22
BG_NT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$9C,$00,$88,$00,$96,$00,$8F,$00,$97,$AB,$00,$00,$83,$93,$B8,$00,$B0,$00,$90,$91,$00,$00,$B6,$BF,$AD,$B1,$81,$00,$00,$A5
  .byte $00,$00,$9D,$00,$89,$00,$97,$00,$88,$00,$90,$AC,$00,$00,$84,$94,$B9,$00,$B1,$00,$91,$92,$00,$00,$B7,$B8,$AE,$B2,$82,$00,$00,$A6
  .byte $00,$00,$9E,$00,$8A,$00,$90,$00,$89,$00,$91,$AD,$00,$00,$85,$95,$BA,$00,$B2,$00,$92,$93,$00,$00,$B0,$B9,$AF,$B3,$83,$00,$00,$A7
  .byte $00,$00,$9F,$00,$8B,$00,$91,$00,$8A,$00,$92,$AE,$00,$00,$86,$96,$BB,$00,$B3,$00,$93,$94,$00,$00,$B1,$BA,$A8,$B4,$84,$00,$00,$A0
  .byte $00,$00,$98,$00,$8C,$00,$92,$00,$8B,$00,$93,$AF,$00,$00,$87,$97,$BC,$00,$B4,$00,$94,$95,$00,$00,$B2,$BB,$A9,$B5,$85,$00,$00,$A1
  .byte $00,$00,$99,$00,$8D,$00,$93,$00,$8C,$00,$94,$A8,$00,$00,$80,$90,$BD,$00,$B5,$00,$95,$96,$00,$00,$B3,$BC,$AA,$B6,$86,$00,$00,$A2
  .byte $00,$00,$9A,$00,$8E,$00,$94,$00,$8D,$00,$95,$A9,$00,$00,$81,$91,$BE,$00,$B6,$00,$96,$97,$00,$00,$B4,$BD,$AB,$B7,$87,$00,$00,$A3
  .byte $00,$00,$9B,$00,$8F,$00,$95,$00,$8E,$00,$96,$AA,$00,$00,$82,$92,$BF,$00,$B7,$00,$97,$90,$00,$00,$B5,$BE,$AC,$B0,$80,$00,$00,$A4
  .byte $00,$00,$9C,$00,$88,$00,$96,$00,$8F,$00,$97,$AB,$00,$00,$83,$93,$B8,$00,$B0,$00,$90,$91,$00,$00,$B6,$BF,$AD,$B1,$81,$00,$00,$A5
  .byte $00,$00,$9D,$00,$89,$00,$97,$00,$88,$00,$90,$AC,$00,$00,$84,$94,$B9,$00,$B1,$00,$91,$92,$00,$00,$B7,$B8,$AE,$B2,$82,$00,$00,$A6
  .byte $00,$00,$9E,$00,$8A,$00,$90,$00,$89,$00,$91,$AD,$00,$00,$85,$95,$BA,$00,$B2,$00,$92,$93,$00,$00,$B0,$B9,$AF,$B3,$83,$00,$00,$A7
  .byte $00,$00,$9F,$00,$8B,$00,$91,$00,$8A,$00,$92,$AE,$00,$00,$86,$96,$BB,$00,$B3,$00,$93,$94,$00,$00,$B1,$BA,$A8,$B4,$84,$00,$00,$A0
  .byte $00,$00,$98,$00,$8C,$00,$92,$00,$8B,$00,$93,$AF,$00,$00,$87,$97,$BC,$00,$B4,$00,$94,$95,$00,$00,$B2,$BB,$A9,$B5,$85,$00,$00,$A1
  .byte $00,$00,$99,$00,$8D,$00,$93,$00,$8C,$00,$94,$A8,$00,$00,$80,$90,$BD,$00,$B5,$00,$95,$96,$00,$00,$B3,$BC,$AA,$B6,$86,$00,$00,$A2
  .byte $00,$00,$9A,$00,$8E,$00,$94,$00,$8D,$00,$95,$A9,$00,$00,$81,$91,$BE,$00,$B6,$00,$96,$97,$00,$00,$B4,$BD,$AB,$B7,$87,$00,$00,$A3
  .byte $00,$00,$9B,$00,$8F,$00,$95,$00,$8E,$00,$96,$AA,$00,$00,$82,$92,$BF,$00,$B7,$00,$97,$90,$00,$00,$B5,$BE,$AC,$B0,$80,$00,$00,$A4
  .byte $00,$00,$9C,$00,$88,$00,$96,$00,$8F,$00,$97,$AB,$00,$00,$83,$93,$B8,$00,$B0,$00,$90,$91,$00,$00,$B6,$BF,$AD,$B1,$81,$00,$00,$A5
  .byte $00,$00,$9D,$00,$89,$00,$97,$00,$88,$00,$90,$AC,$00,$00,$84,$94,$B9,$00,$B1,$00,$91,$92,$00,$00,$B7,$B8,$AE,$B2,$82,$00,$00,$A6
  .byte $00,$00,$9E,$00,$8A,$00,$90,$00,$89,$00,$91,$AD,$00,$00,$85,$95,$BA,$00,$B2,$00,$92,$93,$00,$00,$B0,$B9,$AF,$B3,$83,$00,$00,$A7
  .byte $00,$00,$9F,$00,$8B,$00,$91,$00,$8A,$00,$92,$AE,$00,$00,$86,$96,$BB,$00,$B3,$00,$93,$94,$00,$00,$B1,$BA,$A8,$B4,$84,$00,$00,$A0
  .byte $00,$00,$98,$00,$8C,$00,$92,$00,$8B,$00,$93,$AF,$00,$00,$87,$97,$BC,$00,$B4,$00,$94,$95,$00,$00,$B2,$BB,$A9,$B5,$85,$00,$00,$A1
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; big letters of the title: S P A C E F I R B D, 4 tiles each (192-231)
BIG_P:
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
BIG_C:
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $70,$70,$50,$50,$50,$50,$40,$40,$70,$70,$50,$50,$50,$50,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $70,$70,$50,$50,$50,$50,$40,$40,$70,$70,$50,$50,$50,$50,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $70,$70,$50,$50,$50,$50,$40,$40,$70,$70,$50,$50,$50,$50,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $70,$70,$50,$50,$50,$50,$40,$40,$70,$70,$50,$50,$50,$50,$40,$40
  .byte $F0,$F0,$F0,$F0,$70,$70,$70,$70,$F0,$F0,$F0,$F0,$70,$70,$70,$70
  .byte $70,$70,$50,$50,$50,$50,$40,$40,$70,$70,$50,$50,$50,$50,$40,$40
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80

; big title (text records, end = $FF)
TXT_BIG:
  .byte 2,11,192,193,196,197,200,201,204,205,208,209,0
  .byte 3,11,194,195,198,199,202,203,206,207,210,211,0
  .byte 5,8,212,213,216,217,220,221,224,225,228,229,216,217,220,221,232,233,0
  .byte 6,8,214,215,218,219,222,223,226,227,230,231,218,219,222,223,234,235,0
  .byte $FF

; HUD tiles of the third 2: spare ship, warp ready
HUD_PAT:
  .byte $18,$18,$3C,$BD,$FF,$FF,$A5,$00
  .byte $3C,$42,$99,$BD,$BD,$99,$42,$3C
HUD_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$70,$70,$70,$70,$70,$70,$70,$70

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
  .byte 1, $00,$53, <16,>16, <HUD_PAT,>HUD_PAT
  .byte 1, $00,$73, <16,>16, <HUD_COL,>HUD_COL
  .byte 1, $00,$46, <352,>352, <BIG_P,>BIG_P
  .byte 1, $00,$66, <352,>352, <BIG_C,>BIG_C
  .byte 0

; sprites 16x16: ship, shield, shot, bullet, shrapnel, bomb, comet x2, gull x2, eagle x2,
; emperor x2, 3 explosion frames
SPR_PAGES = 3
SPRITES:
  .byte $00,$01,$01,$03,$03,$07,$27,$2F,$6F,$7F,$FF,$FF,$DF,$8C,$00,$00
  .byte $00,$80,$80,$C0,$C0,$E0,$E4,$F4,$F6,$FE,$FF,$FF,$FB,$31,$00,$00
  .byte $07,$18,$20,$40,$40,$80,$80,$80,$80,$80,$80,$40,$40,$20,$18,$07
  .byte $E0,$18,$04,$02,$02,$01,$01,$01,$01,$01,$01,$02,$02,$04,$18,$E0
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$01,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$00,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$03,$07,$07,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$07,$07,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$09,$07,$07,$0F,$07,$07,$09,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$C0,$C0,$E0,$C0,$C0,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$30,$19,$0F,$07,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$0C,$98,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$07,$1F,$33,$21,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$F8,$CC,$84,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$61,$33,$3B,$1F,$0F,$07,$02,$06,$00,$00,$00,$00
  .byte $00,$00,$00,$03,$86,$CC,$DC,$F8,$F0,$E0,$40,$60,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$03,$07,$3F,$7F,$C7,$83,$02,$06,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$C0,$E0,$FC,$FE,$E3,$C1,$40,$60,$00,$00,$00,$00
  .byte $00,$00,$81,$C2,$E3,$77,$7F,$3F,$1F,$0E,$1B,$31,$60,$00,$00,$00
  .byte $00,$00,$81,$43,$C7,$EE,$FE,$FC,$F8,$70,$D8,$8C,$06,$00,$00,$00
  .byte $00,$00,$01,$02,$03,$0F,$3F,$7F,$FF,$EF,$CE,$9B,$31,$00,$00,$00
  .byte $00,$00,$80,$40,$C0,$F0,$FC,$FE,$FF,$F7,$73,$D9,$8C,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$C0,$E0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$00,$06,$0F,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$18,$F0,$00,$6C,$70,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$00,$08,$00,$10,$28,$04,$00,$00,$02,$00,$00
  .byte $00,$00,$00,$00,$44,$10,$00,$00,$20,$02,$40,$08,$60,$00,$00,$00
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

; speed of the birds: [speed * 64 + direction], speeds 0.75 1.25 1.75 2.25 px per frame (8.8 signed)
VXL:
  .byte $00,$13,$25,$38,$49,$5B,$6B,$7A,$88,$94,$A0,$A9,$B1,$B8,$BC,$BF
  .byte $C0,$BF,$BC,$B8,$B1,$A9,$A0,$94,$88,$7A,$6B,$5B,$49,$38,$25,$13
  .byte $00,$ED,$DB,$C8,$B7,$A5,$95,$86,$78,$6C,$60,$57,$4F,$48,$44,$41
  .byte $40,$41,$44,$48,$4F,$57,$60,$6C,$78,$86,$95,$A5,$B7,$C8,$DB,$ED
  .byte $00,$1F,$3E,$5D,$7A,$97,$B2,$CB,$E2,$F7,$0A,$1A,$28,$32,$3A,$3E
  .byte $40,$3E,$3A,$32,$28,$1A,$0A,$F7,$E2,$CB,$B2,$97,$7A,$5D,$3E,$1F
  .byte $00,$E1,$C2,$A3,$86,$69,$4E,$35,$1E,$09,$F6,$E6,$D8,$CE,$C6,$C2
  .byte $C0,$C2,$C6,$CE,$D8,$E6,$F6,$09,$1E,$35,$4E,$69,$86,$A3,$C2,$E1
  .byte $00,$2C,$57,$82,$AB,$D3,$F9,$1C,$3D,$5A,$74,$8B,$9E,$AD,$B7,$BE
  .byte $C0,$BE,$B7,$AD,$9E,$8B,$74,$5A,$3D,$1C,$F9,$D3,$AB,$82,$57,$2C
  .byte $00,$D4,$A9,$7E,$55,$2D,$07,$E4,$C3,$A6,$8C,$75,$62,$53,$49,$42
  .byte $40,$42,$49,$53,$62,$75,$8C,$A6,$C3,$E4,$07,$2D,$55,$7E,$A9,$D4
  .byte $00,$38,$70,$A7,$DC,$10,$40,$6D,$97,$BD,$DF,$FC,$14,$27,$35,$3D
  .byte $40,$3D,$35,$27,$14,$FC,$DF,$BD,$97,$6D,$40,$10,$DC,$A7,$70,$38
  .byte $00,$C8,$90,$59,$24,$F0,$C0,$93,$69,$43,$21,$04,$EC,$D9,$CB,$C3
  .byte $C0,$C3,$CB,$D9,$EC,$04,$21,$43,$69,$93,$C0,$F0,$24,$59,$90,$C8
VXH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FD,$FD,$FD,$FD
  .byte $FD,$FD,$FD,$FD,$FD,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF
VYL:
  .byte $40,$41,$44,$48,$4F,$57,$60,$6C,$78,$86,$95,$A5,$B7,$C8,$DB,$ED
  .byte $00,$13,$25,$38,$49,$5B,$6B,$7A,$88,$94,$A0,$A9,$B1,$B8,$BC,$BF
  .byte $C0,$BF,$BC,$B8,$B1,$A9,$A0,$94,$88,$7A,$6B,$5B,$49,$38,$25,$13
  .byte $00,$ED,$DB,$C8,$B7,$A5,$95,$86,$78,$6C,$60,$57,$4F,$48,$44,$41
  .byte $C0,$C2,$C6,$CE,$D8,$E6,$F6,$09,$1E,$35,$4E,$69,$86,$A3,$C2,$E1
  .byte $00,$1F,$3E,$5D,$7A,$97,$B2,$CB,$E2,$F7,$0A,$1A,$28,$32,$3A,$3E
  .byte $40,$3E,$3A,$32,$28,$1A,$0A,$F7,$E2,$CB,$B2,$97,$7A,$5D,$3E,$1F
  .byte $00,$E1,$C2,$A3,$86,$69,$4E,$35,$1E,$09,$F6,$E6,$D8,$CE,$C6,$C2
  .byte $40,$42,$49,$53,$62,$75,$8C,$A6,$C3,$E4,$07,$2D,$55,$7E,$A9,$D4
  .byte $00,$2C,$57,$82,$AB,$D3,$F9,$1C,$3D,$5A,$74,$8B,$9E,$AD,$B7,$BE
  .byte $C0,$BE,$B7,$AD,$9E,$8B,$74,$5A,$3D,$1C,$F9,$D3,$AB,$82,$57,$2C
  .byte $00,$D4,$A9,$7E,$55,$2D,$07,$E4,$C3,$A6,$8C,$75,$62,$53,$49,$42
  .byte $C0,$C3,$CB,$D9,$EC,$04,$21,$43,$69,$93,$C0,$F0,$24,$59,$90,$C8
  .byte $00,$38,$70,$A7,$DC,$10,$40,$6D,$97,$BD,$DF,$FC,$14,$27,$35,$3D
  .byte $40,$3D,$35,$27,$14,$FC,$DF,$BD,$97,$6D,$40,$10,$DC,$A7,$70,$38
  .byte $00,$C8,$90,$59,$24,$F0,$C0,$93,$69,$43,$21,$04,$EC,$D9,$CB,$C3
VYH:
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FD,$FD,$FD,$FD,$FD,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FD,$FD,$FD,$FD
; bullets and shrapnel: 2 px per frame
BVXL:
  .byte $00,$32,$64,$95,$C4,$F1,$1C,$45,$6A,$8C,$AA,$C4,$D9,$EA,$F6,$FE
  .byte $00,$FE,$F6,$EA,$D9,$C4,$AA,$8C,$6A,$45,$1C,$F1,$C4,$95,$64,$32
  .byte $00,$CE,$9C,$6B,$3C,$0F,$E4,$BB,$96,$74,$56,$3C,$27,$16,$0A,$02
  .byte $00,$02,$0A,$16,$27,$3C,$56,$74,$96,$BB,$E4,$0F,$3C,$6B,$9C,$CE
BVXH:
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF
BVYL:
  .byte $00,$02,$0A,$16,$27,$3C,$56,$74,$96,$BB,$E4,$0F,$3C,$6B,$9C,$CE
  .byte $00,$32,$64,$95,$C4,$F1,$1C,$45,$6A,$8C,$AA,$C4,$D9,$EA,$F6,$FE
  .byte $00,$FE,$F6,$EA,$D9,$C4,$AA,$8C,$6A,$45,$1C,$F1,$C4,$95,$64,$32
  .byte $00,$CE,$9C,$6B,$3C,$0F,$E4,$BB,$96,$74,$56,$3C,$27,$16,$0A,$02
BVYH:
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
; arctangent: (ratio * 256) / 8 -> angle (64 = 90 degrees)
ATN:
  .byte $01,$02,$03,$04,$06,$07,$08,$09,$0B,$0C,$0D,$0E,$0F,$10,$11,$12
  .byte $13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1B,$1C,$1D,$1E,$1E,$1F,$20

; entry paths: start X, Y, angle, first segment
SCR_X:
  .byte $30,$04,$04,$04
SCR_Y:
  .byte $10,$40,$28,$80
SCR_A:
  .byte $80,$40,$40,$18
SCR_S:
  .byte $00,$0D,$1D,$3C
; segments: frames, turn per frame (signed), speed; 0 = the comet becomes a bird
SEGS:
  .byte $18,$00,$02,$80,$FE,$02,$20,$FE,$02,$24,$00,$02,$00,$24,$00
  .byte $02,$80,$02,$02,$2C,$00,$02,$10,$02,$02,$0A,$00,$02,$00,$10
  .byte $00,$02,$10,$04,$02,$10,$FC,$02,$10,$FC,$02,$10,$04,$02,$10
  .byte $04,$02,$10,$FC,$02,$10,$FC,$02,$10,$04,$02,$08,$00,$02,$00
  .byte $18,$00,$02,$38,$01,$02,$80,$02,$02,$14,$00,$02,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$18,$1B,$1F,$25,$2D,$39,$4E,$1A,$1A,$1A,$23,$23,$23,$2A,$25
  .byte $2D,$28,$32,$2B,$37,$2F,$3D,$33,$45,$39,$50,$40,$5F,$49,$59,$53
  .byte $48,$44,$45,$41,$3B,$39,$3A,$38,$34,$33,$35,$34,$32,$32,$34,$35
  .byte $33,$34,$38,$3A,$39,$3B,$41,$45,$44,$48,$53,$59,$9C,$6B,$51,$41
  .byte $37,$2F,$29,$25,$FA,$7E,$8E,$5B,$63,$47,$4C,$3B,$3E,$32,$34,$2B
  .byte $2D,$26,$28,$22,$23,$1F,$20,$1C,$1D,$1A,$1B,$18,$19,$17,$17,$15
  .byte $15,$14,$14,$13,$18,$19,$19,$1A,$1A,$1B,$1B,$1C,$1D,$1E,$1E,$1F
  .byte $20,$21,$22,$23,$24,$25,$27,$28,$29,$2B,$2C,$2E,$30,$32,$35,$37
  .byte $3A,$3D,$40,$44,$48,$4D,$53,$59,$78,$78,$78,$78,$78,$78,$5F,$5F
  .byte $5F,$5F,$5F,$5F,$50,$50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $50,$50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$50,$50,$50,$50,$50,$50,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$2F,$2F,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$28,$28,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $28,$28,$28,$28,$28,$00,$00,$00,$28,$28,$28,$28,$28,$00,$00,$00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0B,$0A,$09,$07,$06,$05,$0C,$0B,$0A,$0B,$09,$06,$0D,$0D
  .byte $0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$09,$09
  .byte $09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$09,$09,$09,$09,$08,$07,$06,$05,$04,$0A,$0A,$09,$09
  .byte $08,$08,$07,$07,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0A,$09
  .byte $08,$07,$06,$05,$09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07
  .byte $07,$07,$06,$06,$06,$06,$06,$06,$0C,$0B,$0A,$0A,$09,$08,$0C,$0B
  .byte $0A,$0A,$09,$08,$0C,$0B,$0A,$0A,$09,$08,$0C,$0B,$0A,$0A,$09,$08
  .byte $0C,$0B,$0A,$0A,$09,$08,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A
  .byte $09,$09,$09,$09,$08,$08,$0C,$0B,$0A,$0A,$09,$08,$0C,$0B,$0A,$0A
  .byte $09,$08,$0C,$0B,$0A,$0A,$09,$08,$0C,$0B,$0A,$0A,$09,$08,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$00
  .byte $0D,$0C,$0A,$09,$08,$07,$05,$04
WH_START:
  .byte $00,$01,$08,$0E,$1E,$3C,$44,$64,$88,$B6,$E0
WH_LEN:
  .byte $00,$07,$06,$10,$1E,$08,$20,$24,$2E,$2A,$18
W_SHOT = 1
W_HIT = 2
W_KILL = 3
W_COMET = 4
W_TRANS = 5
W_WARP = 6
W_BOMB = 7
W_START = 8
W_PERFECT = 9
W_EXTRA = 10

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0C,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$05
  .byte $04,$03,$03,$02,$01,$0F,$0F,$0F,$0E,$0E,$0D,$0D,$0D,$0C,$0C,$0B
  .byte $0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$07,$07,$07,$06,$06,$05,$05
  .byte $05,$04,$04,$03,$03,$03,$02,$02,$01,$0F,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A
  .byte $0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06,$06,$06,$06,$05
  .byte $05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04,$03,$03,$03
  .byte $03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01
  .byte $01,$01,$00,$00,$00,$00,$00
EX_NP:
  .byte $00,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08
  .byte $08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B
  .byte $0B,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$10,$10,$10,$10,$10,$10,$10
  .byte $10,$11,$11,$11,$11,$11,$11,$11,$11,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$13,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16
  .byte $16,$17,$17,$17,$17,$17,$17,$17,$17,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$19,$19,$19,$19,$19,$19,$19,$19,$1A,$1A,$1A,$1A,$1A,$1A,$1A
  .byte $1A,$1B,$1B,$1B,$1B,$1B,$1B
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09
  .byte $09,$08,$08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04
  .byte $03,$03,$03,$02,$02,$02,$01,$01,$01,$0D,$0D,$0D,$0D,$0D,$0D,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08,$07,$07,$07
  .byte $07,$07,$07,$06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$04
  .byte $04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$DF,$E7,$EF,$F7,$00,$0A,$15,$20,$2C,$3A,$49,$59,$6B,$7F,$96
  .byte $AF,$CC,$EC,$12,$3D,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6
  .byte $B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6
  .byte $B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70
EX_TH:
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04
EX_START:
  .byte $00,$01,$15,$39
EX_LEN:
  .byte $00,$14,$24,$6E
S_SMALL = 1
S_BOMB = 2
S_SHIP = 3
S_BIG = S_SHIP
