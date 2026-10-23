;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_ASTEROIDS  -  Atari Asteroids (1979)                ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: lunar_lander (NMI + trampoline $0FD0, joystick VIA,  ;
;   bitmap shadow in RAM, AY sound engine)                     ;
;                                                              ;
;   - joystick 1 ($D581) = player 1, joystick 2 ($D580) =      ;
;     player 2 (they take turns, each with his own field):     ;
;       LEFT / RIGHT = rotate, UP = thrust                     ;
;       button 1 = fire (4 shots at a time)                    ;
;       button 2 or DOWN = hyperspace                          ;
;   - large asteroid 20, medium 50, small 100 points;          ;
;     large saucer 200, small saucer 1000; extra ship every    ;
;     10000 points; 3 ships                                    ;
;   - waves start with 4 large asteroids, 2 more every wave    ;
;     (up to 11); large -> 2 medium -> 2 small                 ;
;   - the large saucer fires at random, the small one aims at  ;
;     the ship and comes more often as the score grows         ;
;   - everything wraps around the screen (saucers excepted)    ;
;   - asteroids are outlines XOR-ed on the bitmap (vector      ;
;     look): drawing twice erases them and leaves what was     ;
;     under; shapes are pre-shifted 0-7 pixels and only a few  ;
;     are redrawn every frame (budget), the rest next frame    ;
;   - ship, flame, saucer, shots and explosions are sprites    ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     the heartbeat of two low notes that speeds up, fire,     ;
;     thrust rumble, three explosions by size, ship explosion, ;
;     the siren of the saucers (large slow, small fast),       ;
;     saucer fire, extra ship beeps. No music, as on the       ;
;     cabinet. Stereo follows the objects.                     ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
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
PTR2        = $6E      ; 2 bytes: colour pointer of the cell (shadow)
SPTR        = $70      ; 2 bytes: pattern pointer of the cell (shadow)
TP          = $72      ; 2 bytes: text records
CELLC       = $78      ; cell column (0-31)
CELLR       = $79      ; cell row (0-23)
TCOL        = $7A      ; colour byte (fg<<4 | bg) for texts
PX          = $7B      ; pixel to draw
PY          = $7C
PCOL        = $7D
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)
TYV         = $80
BIGC        = $81
BIGR        = $82
CLRCOL      = $83      ; colour used by CLEAR_ROWS
NPL         = $84      ; number of players (1-2)
CURP        = $85      ; player in the game (0-1)
LIVES       = $86      ; 2 bytes: ships per player
SCA         = $88      ; 2 bytes: score per player, BCD low
SCB         = $8A      ; 2 bytes: BCD middle
SCC         = $8C      ; 2 bytes: BCD high
HIA         = $8E      ; hi score, BCD low / middle / high
HIB         = $8F
HIC         = $90
WAVE        = $91      ; 2 bytes: wave per player
NXL         = $93      ; 2 bytes: next extra ship (BCD high digits of the score)
SHXL        = $95      ; ship position 8.8 (centre), Y = 0-175 in the playfield
SHXH        = $96
SHYL        = $97
SHYH        = $98
SVXL        = $99      ; ship velocity 8.8 signed (VY must follow VX)
SVXH        = $9A
SVYL        = $9B
SVYH        = $9C
SANG        = $9D      ; ship angle 0-15 (0 = up, clockwise)
ROTT        = $9E      ; rotation repeat timer
SHIPST      = $9F      ; 0 flying, 1 exploding, 2 waiting, 3 hyperspace, 4 life over
SHT         = $A0      ; timer of the ship state
THR         = $A1      ; 1 = engine on
UFO_ON      = $A2      ; saucer: 0 none, 1 large, 2 small
UFX         = $A3      ; saucer X (centre) 8.8
UFXL        = $A4
UFY         = $A5      ; saucer Y (centre)
UFVXL       = $A6      ; saucer horizontal speed 8.8 signed
UFVXH       = $A7
UFDY        = $A8      ; saucer vertical step: $FF, 0, 1 (every other frame)
UFT         = $A9      ; frames to the next change of course
UFSPN       = $AA      ; time to the next saucer (x 4 frames)
BEAT_I      = $AB      ; frames between two beats
BEAT_T      = $AC
BEAT_N      = $AD      ; which of the two notes
ACOUNT      = $AE      ; asteroids alive
WAVET       = $AF      ; frames before the next wave
RR          = $B0      ; first asteroid to look at when redrawing
BUDGET      = $B1      ; redraw budget of this frame
JOYC        = $B2      ; joystick of the player in the game
FIRE_OLD    = $B3      ; buttons and DOWN of the previous frame
XCOL        = $B4      ; XOR_SHAPE: byte column
XCUR        = $B5      ;            current line (0-175)
XREM        = $B6      ;            lines left in the column
XRUN        = $B7      ;            lines in this cell
XNC         = $B8      ;            columns left
XHGT        = $B9      ;            height of the shape
XSHI        = $BA      ;            index in the shape

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_BEAT   = $DC         ; request: 1 / 2 = beat note
BEAT_POS   = $DD         ; NMI: frame of the beat ($FF = silent)
BEAT_NOTE  = $DE
SND_UFO    = $DF         ; siren: 0 none, 1 large saucer, 2 small saucer
SND_THR    = $E0         ; 1 = thrust rumble
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

; ---------------- zero page: more game temporaries ----------------
XSZ        = $E1         ; XOR_SHAPE input: size 1-3
XSH        = $E2         ;                  shape 0-2
XXX        = $E3         ;                  X (left)
XYY        = $E4         ;                  Y (top, 0-175)
ACUR       = $E5         ; asteroid being handled
HITBY      = $E6         ; 1 = destroyed by the player (points)
PTS_L      = $E7         ; points to add (BCD)
PTS_M      = $E8
PCX        = $E9         ; centre of a destroyed object
PCY        = $EA
NEWSZ      = $EB
OBX        = $EC         ; object tested by the collisions (centre)
OBY        = $ED
OBR        = $EE         ; its radius
PLAYING    = $EF         ; 1 = a game is running (beat)
BI         = $F0         ; shot being moved
SPX        = $F1         ; SET_SPR: centre, pattern, colour
SPY        = $F2
SPN        = $F3
SPC        = $F4
KSPD       = $F5         ; speed multiplier of a new asteroid
EXI        = $F6         ; next explosion slot

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects

; ---------------- shots and explosions ----------------
NSHOT  = 6               ; 0-3 ship, 4-5 saucer
B_T    = $0720           ; frames of life left (0 = free)
B_XL   = $0726
B_XH   = $072C
B_YL   = $0732
B_YH   = $0738
B_VXL  = $073E
B_VXH  = $0744
B_VYL  = $074A
B_VYH  = $0750
NEXPL  = 3
E_T    = $0756           ; frame of the explosion (0 = free)
E_X    = $0759
E_Y    = $075C

; ---------------- asteroids: 13 arrays of MAXA bytes, one block ----------------
MAXA     = 24
A_SZ     = $0800         ; 0 free, 1 small, 2 medium, 3 large
A_SH     = $0818         ; shape 0-2
A_XL     = $0830         ; position 8.8 of the top-left corner (Y = 0-175)
A_XH     = $0848
A_YL     = $0860
A_YH     = $0878
A_VXL    = $0890         ; velocity 8.8 signed
A_VXH    = $08A8
A_VYL    = $08C0
A_VYH    = $08D8
A_DX     = $08F0         ; where it is drawn now
A_DY     = $0908
A_DRAWN  = $0920         ; 1 = on the screen at A_DX / A_DY
A_END    = $0938
A_SAVE   = $0A00         ; the same block for the player waiting for his turn

SH_PAT = $4000           ; copy of the screen (pattern) in RAM
SH_COL = $6000           ; copy of the colours

; ---------------- parameters ----------------
FIELD_H     = 176        ; playfield: Y 0-175 = screen lines 16-191
ROT_DELAY   = 3          ; frames between two rotation steps
SHOT_LIFE   = 40
BUDGET_MAX  = 7          ; redraw units per frame (small 1, medium 2, large 3 per drawing)
BTN_MASK    = %00110000
HIDE_Y      = $C0
SHIP_COL    = $0F
CX0         = 128        ; where the ship appears
CY0         = 88

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
;  TITLE SCREEN (asteroids drifting behind the text)
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  JSR HIDE_SPRITES
  LDA #$00
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_ALL
  JSR CLEAR_FIELD
  JSR DRAW_HUD
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
  LDA #6
  JSR SPAWN_WAVE
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR ATTRACT_FRAME
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR ATTRACT_FRAME
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

ATTRACT_FRAME:
  JSR VDP_INT_OFF
  JSR MOVE_ASTEROIDS
  JSR REDRAW_ASTEROIDS
  JSR VDP_INT_ON
  JMP READ_JOY


; ===============================================================
;  NEW GAME
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME
  STA SND_CMD
  LDX #$01
.ng_p:
  LDA #$00
  STA SCA,X
  STA SCB,X
  STA SCC,X
  STA WAVE,X
  STA LIVES,X
  LDA #$01
  STA NXL,X
  DEX
  BPL .ng_p
  LDA #$03
  STA LIVES
  LDA NPL
  CMP #$02
  BNE .ng_1
  LDA #$03
  STA LIVES+1
.ng_1:
  LDA #$00
  STA CURP
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  JSR CLEAR_FIELD
  LDX #$00                     ; the field of player 2 starts empty
  LDA #$00
.ng_z:
  STA A_SAVE,X
  STA A_SAVE+$100,X
  INX
  BNE .ng_z
  ; fall into TURN_START


; ===============================================================
;  TURN OF A PLAYER
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #$00
  STA UFO_ON
  STA SND_UFO
  STA SND_THR
  STA THR
  LDX #(NSHOT-1)
.ts_b:
  STZ B_T,X
  DEX
  BPL .ts_b
  LDX #(NEXPL-1)
.ts_e:
  STZ E_T,X
  DEX
  BPL .ts_e
  JSR COUNT_AST
  LDA #60
  STA WAVET
  LDA #50
  STA BEAT_I
  STA BEAT_T
  LDA #150
  STA UFSPN
  LDA #$02                     ; the ship waits for a free centre
  STA SHIPST
  LDA #90
  STA SHT
  LDA #$01
  STA PLAYING
  LDA #BTN_MASK
  STA FIRE_OLD
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  LDA NPL
  CMP #$02
  BNE .ts_on
  LDA #<TXT_PLAYER             ; "PLAYER n" in the middle of the HUD
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR DRAW_TEXT
  LDA #$B1
  STA TCOL
  LDA #1
  STA CELLR
  LDA #19
  STA CELLC
  LDA CURP
  CLC
  ADC #$31
  JSR PUT_CHAR
.ts_on:
  JSR VDP_INT_ON


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
  JSR MOVE_ASTEROIDS
  JSR REDRAW_ASTEROIDS
  JSR UPDATE_EXPL
  JSR UPDATE_BEAT
  JSR WAVE_CHECK
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA SHIPST
  CMP #$04
  BEQ SHIP_LOST
  JMP GAME_LOOP


; ---------------------------------------------------------------
; the explosion of the ship is over
; ---------------------------------------------------------------
SHIP_LOST:
  LDX CURP
  DEC LIVES,X
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  JSR VDP_INT_ON
  LDA NPL
  CMP #$02
  BNE .sl_same
  LDA CURP
  EOR #$01
  TAX
  LDA LIVES,X
  BEQ .sl_same
  JMP SWITCH_PLAYER
.sl_same:
  LDX CURP
  LDA LIVES,X
  BEQ .sl_over
  LDA #$02                     ; next ship of the same player
  STA SHIPST
  LDA #60
  STA SHT
  JMP GAME_LOOP
.sl_over:
  JMP GAME_OVER

; the other player: his asteroids on a clean screen
SWITCH_PLAYER:
  JSR HIDE_SPRITES
  LDA #40
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  JSR UNDRAW_FLAGS
  LDX #$00                     ; swap the asteroid blocks ($0800-$0937 <-> $0A00-$0B37)
.sw_a:
  LDA A_SZ,X
  LDY A_SAVE,X
  STA A_SAVE,X
  TYA
  STA A_SZ,X
  INX
  BNE .sw_a
.sw_b:
  LDA A_SZ+$100,X
  LDY A_SAVE+$100,X
  STA A_SAVE+$100,X
  TYA
  STA A_SZ+$100,X
  INX
  CPX #(A_END-A_SZ-$100)
  BNE .sw_b
  JSR UNDRAW_FLAGS
  LDA CURP
  EOR #$01
  STA CURP
  JMP TURN_START

UNDRAW_FLAGS:                  ; the screen has been cleared: nothing is drawn
  LDX #(MAXA-1)
.uf_l:
  STZ A_DRAWN,X
  DEX
  BPL .uf_l
  RTS


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
  JSR HIDE_SPRITES
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
  JSR VDP_INT_OFF
  JSR DRAW_HUD
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
  JSR VDP_INT_ON
  LDA #90
  JSR WAIT_FRAMES
  JSR WAIT_FIRE
  JMP TITLE


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
  LDA #$04
  STA SHIPST
.us_r:
  RTS
.us_n1:
  CMP #$02
  BNE .us_hyp
  LDA SHT                      ; ---- waiting: first the pause, then a free centre
  BEQ .us_wait
  DEC SHT
  BNE .us_r
  LDA NPL                      ; erase "PLAYER n"
  CMP #$02
  BNE .us_r
  LDA #<TXT_NOMSG
  STA TP
  LDA #>TXT_NOMSG
  STA TP+1
  JMP DRAW_TEXT
.us_wait:
  JSR CENTER_FREE
  BCC .us_r
  LDA #CX0
  STA SHXH
  LDA #CY0
  STA SHYH
  STZ SANG                     ; a new ship points up
  JMP SHIP_APPEAR
.us_hyp:
  DEC SHT                      ; ---- hyperspace
  BNE .us_r
  JSR NEXT_RND                 ; back somewhere at random
  LDA RND
  AND #$7F
  STA T0
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC T0
  CLC
  ADC #32
  STA SHXH
  JSR NEXT_RND
  LDA RND
  AND #$7F
  CLC
  ADC #24
  STA SHYH
  JSR SHIP_APPEAR
  JSR NEXT_RND
  LDA RND                      ; sometimes the jump goes wrong
  AND #$07
  BNE .us_r
  JMP SHIP_DIE
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
  ; ---- thrust
  LDA #$00
  STA THR
  STA SND_THR
  LDA JOYC
  AND #%00000001               ; up
  BEQ .us_fric
  LDA #$01
  STA THR
  STA SND_THR
  LDY SANG
  LDA THX,Y
  LDX #0
  JSR ADD_SVEL
  LDY SANG
  LDA THY,Y
  LDX #2
  JSR ADD_SVEL
.us_fric:
  ; ---- friction: v -= v / 128, then speed limit
  LDX #0
  JSR FRICTION
  LDX #2
  JSR FRICTION
  ; ---- position
  CLC
  LDA SHXL
  ADC SVXL
  STA SHXL
  LDA SHXH
  ADC SVXH
  STA SHXH
  CLC
  LDA SHYL
  ADC SVYL
  STA SHYL
  LDA SHYH
  ADC SVYH
  JSR WRAP_Y
  STA SHYH
  ; ---- buttons: fire on button 1, hyperspace on button 2 or DOWN
  LDA JOYC
  AND #%00110010
  TAX
  EOR FIRE_OLD
  AND JOYC                     ; just pressed
  STX FIRE_OLD
  STA T7
  AND #%00010000
  BEQ .us_nf
  JSR SHIP_FIRE
.us_nf:
  LDA T7
  AND #%00100010
  BEQ .us_hit
  LDA #$03                     ; into hyperspace
  STA SHIPST
  LDA #40
  STA SHT
  LDA #$00
  STA THR
  STA SND_THR
  RTS
.us_hit:
  ; ---- collisions with the asteroids
  LDA SHXH
  STA OBX
  LDA SHYH
  STA OBY
  LDA #3
  STA OBR
  JSR HIT_ASTEROID
  BCC .us_ok
  LDA #$01                     ; the player gets the points of the rock
  STA HITBY
  JSR ASTEROID_HIT
  JMP SHIP_DIE
.us_ok:
  RTS

SHIP_APPEAR:
  LDA #$00
  STA SHIPST
  STA SHXL
  STA SHYL
  STA SVXL
  STA SVXH
  STA SVYL
  STA SVYH
  STA ROTT
  LDA #$FF                     ; buttons held now do nothing
  STA FIRE_OLD
  RTS

SHIP_DIE:
  LDA #$01
  STA SHIPST
  LDA #80
  STA SHT
  LDA #$00
  STA THR
  STA SND_THR
  LDA SHXH
  STA PCX
  LDA SHYH
  STA PCY
  JSR NEW_EXPL
  LDA #S_SHIP
  LDX #2
  JMP SFX_BOOM

; SVEL[X..X+1] += A (signed 8 bit).  X = 0 (vx) or 2 (vy)
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

; SVEL[X..X+1] -= SVEL / 128, then |SVEL| < 3 px per frame.  X = 0 / 2
FRICTION:
  LDA SVXL,X
  ASL A
  LDA SVXH,X
  ROL A                        ; A = v / 128 (low byte)
  STA T0
  LDA SVXH,X
  BPL .fr_p
  LDA #$FF
  BRA .fr_s
.fr_p:
  LDA #$00
.fr_s:
  STA T1                       ; sign
  LDA SVXL,X
  SEC
  SBC T0
  STA SVXL,X
  LDA SVXH,X
  SBC T1
  STA SVXH,X
  BMI .fr_neg
  CMP #3
  BCC .fr_ret
  LDA #2
  STA SVXH,X
  LDA #$FF
  STA SVXL,X
  RTS
.fr_neg:
  CMP #$FD
  BCS .fr_ret
  LDA #$FD
  STA SVXH,X
  LDA #$00
  STA SVXL,X
.fr_ret:
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

; carry = 1 when no asteroid is near the centre
CENTER_FREE:
  LDX #(MAXA-1)
.cf_l:
  LDY A_SZ,X
  BEQ .cf_n
  LDA A_XH,X
  CLC
  ADC SZ_HALF,Y
  SEC
  SBC #CX0
  JSR ABS_A
  CMP #40
  BCS .cf_n
  LDA A_YH,X
  CLC
  ADC SZ_HALF,Y
  SEC
  SBC #CY0
  JSR ABS_A
  CMP #40
  BCS .cf_n
  CLC
  RTS
.cf_n:
  DEX
  BPL .cf_l
  LDA UFO_ON                   ; nor a saucer around
  BEQ .cf_ok
  LDA UFY
  SEC
  SBC #CY0
  JSR ABS_A
  CMP #40
  BCS .cf_ok
  CLC
  RTS
.cf_ok:
  SEC
  RTS

ABS_A:                         ; A = |A| (signed)
  BPL .ab_r
  EOR #$FF
  CLC
  ADC #1
.ab_r:
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
  JSR WRAP_Y
  STA B_YH,X
  LDA #$80
  STA B_XL,X
  STA B_YL,X
  LDA SVXL                     ; speed = ship + shot
  CLC
  ADC BVX_L,Y
  STA B_VXL,X
  LDA SVXH
  ADC BVX_H,Y
  STA B_VXH,X
  LDA SVYL
  CLC
  ADC BVY_L,Y
  STA B_VYL,X
  LDA SVYH
  ADC BVY_H,Y
  STA B_VYH,X
  LDA #W_FIRE
  LDY SHXH
  JMP SFX_AT


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
  JSR WRAP_Y
  STA B_YH,X
  JSR SHOT_HITS
.ush_n:
  LDX BI
  DEX
  BPL .ush_l
  RTS

; collisions of the shot BI
SHOT_HITS:
  LDX BI
  LDA B_XH,X
  STA OBX
  LDA B_YH,X
  STA OBY
  LDA #0
  STA OBR
  JSR HIT_ASTEROID
  BCC .sh_ufo
  LDX BI
  STZ B_T,X
  LDA #$00
  CPX #$04
  BCS .sh_who
  LDA #$01
.sh_who:
  STA HITBY                    ; points only for the ship shots
  JMP ASTEROID_HIT
.sh_ufo:
  LDX BI
  CPX #$04
  BCS .sh_ship
  LDA UFO_ON                   ; ship shot against the saucer
  BEQ .sh_ret
  LDA B_XH,X
  SEC
  SBC UFX
  JSR ABS_A
  CMP #7
  BCS .sh_ret
  LDA B_YH,X
  SEC
  SBC UFY
  JSR ABS_A
  CMP #5
  BCS .sh_ret
  STZ B_T,X
  LDA #$01
  JMP UFO_DESTROY
.sh_ship:
  LDA SHIPST                   ; saucer shot against the ship
  BNE .sh_ret
  LDA B_XH,X
  SEC
  SBC SHXH
  JSR ABS_A
  CMP #5
  BCS .sh_ret
  LDA B_YH,X
  SEC
  SBC SHYH
  JSR ABS_A
  CMP #5
  BCS .sh_ret
  STZ B_T,X
  JMP SHIP_DIE
.sh_ret:
  RTS


; ===============================================================
;  ASTEROIDS
; ===============================================================
; is an asteroid within OBR pixels of (OBX,OBY)?  carry = 1 and ACUR = it
HIT_ASTEROID:
  LDX #(MAXA-1)
.ha_l:
  LDY A_SZ,X
  BEQ .ha_n
  LDA SZ_R,Y
  CLC
  ADC OBR
  STA T2
  LDA A_XH,X
  CLC
  ADC SZ_HALF,Y
  SEC
  SBC OBX
  JSR ABS_A
  CMP T2
  BCS .ha_n
  LDA A_YH,X
  CLC
  ADC SZ_HALF,Y
  SEC
  SBC OBY
  JSR ABS_A
  CMP T2
  BCS .ha_n
  STX ACUR
  SEC
  RTS
.ha_n:
  DEX
  BPL .ha_l
  CLC
  RTS

; the asteroid ACUR is destroyed: erase, explosion, points (HITBY), two smaller ones
ASTEROID_HIT:
  LDX ACUR
  LDA A_DRAWN,X
  BEQ .ah_nd
  JSR XOR_OLD
  LDX ACUR
  STZ A_DRAWN,X
.ah_nd:
  LDY A_SZ,X
  LDA A_XH,X
  CLC
  ADC SZ_HALF,Y
  STA PCX
  LDA A_YH,X
  CLC
  ADC SZ_HALF,Y
  STA PCY
  STZ A_SZ,X
  DEC ACOUNT
  STY NEWSZ
  JSR NEW_EXPL
  LDY NEWSZ
  LDA SZ_SND,Y
  LDX #0
  LDY PCX
  BPL .ah_pan
  INX
.ah_pan:
  JSR SFX_BOOM
  LDA HITBY
  BEQ .ah_split
  LDY NEWSZ
  LDA SZ_PTSL,Y
  STA PTS_L
  LDA SZ_PTSM,Y
  STA PTS_M
  JSR ADD_SCORE
.ah_split:
  DEC NEWSZ
  BEQ .ah_ret                  ; a small one just disappears
  JSR SPAWN_CHILD
  JSR SPAWN_CHILD
.ah_ret:
  RTS

; a new asteroid of size NEWSZ centred on (PCX,PCY), random course
SPAWN_CHILD:
  JSR FREE_SLOT
  BCC .sc_ret
  LDY NEWSZ
  TYA
  STA A_SZ,X
  LDA PCX
  SEC
  SBC SZ_HALF,Y
  STA A_XH,X
  LDA PCY
  SEC
  SBC SZ_HALF,Y
  JSR WRAP_Y
  STA A_YH,X
  LDA SZ_K,Y
  STA KSPD
  JSR NEXT_RND
  LDA RND
  AND #$01
  CLC
  ADC KSPD
  STA KSPD
  JMP SET_COURSE
.sc_ret:
  RTS

; X = free slot, carry = 1 (carry = 0: none)
FREE_SLOT:
  LDX #(MAXA-1)
.fs_l:
  LDA A_SZ,X
  BEQ .fs_ok
  DEX
  BPL .fs_l
  CLC
  RTS
.fs_ok:
  SEC
  RTS

; asteroid X: random shape and direction, speed = KSPD x 0.5 px
SET_COURSE:
  STX ACUR
  INC ACOUNT
  STZ A_DRAWN,X
  STZ A_XL,X
  STZ A_YL,X
  JSR NEXT_RND
  LDA RND
  AND #$03
  CMP #3
  BCC .co_s
  LDA #1
.co_s:
  STA A_SH,X
  JSR NEXT_RND
  LDA RND
  AND #$0F
  TAY
  STZ A_VXL,X
  STZ A_VXH,X
  STZ A_VYL,X
  STZ A_VYH,X
  LDA KSPD
  STA T3
.co_k:
  CLC
  LDA A_VXL,X
  ADC DIRX_L,Y
  STA A_VXL,X
  LDA A_VXH,X
  ADC DIRX_H,Y
  STA A_VXH,X
  CLC
  LDA A_VYL,X
  ADC DIRY_L,Y
  STA A_VYL,X
  LDA A_VYH,X
  ADC DIRY_H,Y
  STA A_VYH,X
  DEC T3
  BNE .co_k
  RTS

; A = number of large asteroids, along the edges of the screen
SPAWN_WAVE:
  STA T6
.sw_l:
  JSR FREE_SLOT
  BCC .sw_ret
  LDA #3
  STA A_SZ,X
  JSR NEXT_RND
  LDA RND
  LSR A
  BCC .sw_side
  STA A_XH,X                   ; top edge, X at random
  STZ A_YH,X
  BRA .sw_c
.sw_side:
  STZ A_XH,X                   ; left edge, Y at random
  CMP #(FIELD_H-16)
  BCC .sw_y
  SBC #(FIELD_H-16)
.sw_y:
  STA A_YH,X
.sw_c:
  LDA #1
  STA KSPD
  LDY CURP                     ; from the 4th wave some large rocks are faster
  LDA WAVE,Y
  CMP #3
  BCC .sw_k
  LDA RND
  AND #$01
  CLC
  ADC #1
  STA KSPD
.sw_k:
  JSR SET_COURSE
  DEC T6
  BNE .sw_l
.sw_ret:
  RTS

COUNT_AST:
  STZ ACOUNT
  LDX #(MAXA-1)
.ca_l:
  LDA A_SZ,X
  BEQ .ca_n
  INC ACOUNT
.ca_n:
  DEX
  BPL .ca_l
  RTS

; all the asteroids move (the drawing follows in REDRAW_ASTEROIDS)
MOVE_ASTEROIDS:
  LDX #(MAXA-1)
.ma_l:
  LDA A_SZ,X
  BEQ .ma_n
  CLC
  LDA A_XL,X
  ADC A_VXL,X
  STA A_XL,X
  LDA A_XH,X
  ADC A_VXH,X
  STA A_XH,X
  CLC
  LDA A_YL,X
  ADC A_VYL,X
  STA A_YL,X
  LDA A_YH,X
  ADC A_VYH,X
  JSR WRAP_Y
  STA A_YH,X
.ma_n:
  DEX
  BPL .ma_l
  RTS

; redraws the asteroids that have moved, within the budget of the frame
REDRAW_ASTEROIDS:
  LDA #BUDGET_MAX
  STA BUDGET
  LDA #MAXA
  STA T7                       ; slots to look at
  LDX RR
.ra_l:
  STX ACUR
  LDY A_SZ,X
  BEQ .ra_n
  LDA A_DRAWN,X
  BEQ .ra_new
  LDA A_DX,X
  CMP A_XH,X
  BNE .ra_mv
  LDA A_DY,X
  CMP A_YH,X
  BEQ .ra_n                    ; still in the same place
.ra_mv:
  LDA SZ_COST,Y                ; erase + draw
  ASL A
  CMP BUDGET
  BEQ .ra_go2
  BCS .ra_stop
.ra_go2:
  EOR #$FF
  SEC
  ADC BUDGET
  STA BUDGET
  JSR XOR_OLD
  BRA .ra_draw
.ra_new:
  LDA SZ_COST,Y                ; draw only
  CMP BUDGET
  BEQ .ra_go1
  BCS .ra_stop
.ra_go1:
  EOR #$FF
  SEC
  ADC BUDGET
  STA BUDGET
.ra_draw:
  LDX ACUR
  LDA A_SZ,X
  STA XSZ
  LDA A_SH,X
  STA XSH
  LDA A_XH,X
  STA XXX
  STA A_DX,X
  LDA A_YH,X
  STA XYY
  STA A_DY,X
  LDA #$01
  STA A_DRAWN,X
  JSR XOR_SHAPE
.ra_n:
  LDX ACUR
  INX
  CPX #MAXA
  BCC .ra_w
  LDX #$00
.ra_w:
  DEC T7
  BNE .ra_l
.ra_stop:
  LDX ACUR                     ; next frame starts from here
  STX RR
  RTS

; XOR the asteroid ACUR where it is drawn now (= erase it)
XOR_OLD:
  LDX ACUR
  LDA A_SZ,X
  STA XSZ
  LDA A_SH,X
  STA XSH
  LDA A_DX,X
  STA XXX
  LDA A_DY,X
  STA XYY
  ; fall into XOR_SHAPE

; ---------------------------------------------------------------
; XOR of the shape XSZ / XSH at (XXX, XYY) on the bitmap and on its copy
; in RAM. Byte columns wrap at the right edge, lines at the bottom of
; the playfield. The inner loop is self-modified (shape and copy).
; ---------------------------------------------------------------
XOR_SHAPE:
  LDY XSZ
  LDA SZ_H,Y
  STA XHGT
  LDA SZ_C,Y
  STA XNC
  LDA XSH
  ASL A
  ASL A
  ASL A
  CLC
  ADC SZ_BASE,Y
  STA T0
  LDA XXX
  AND #$07
  CLC
  ADC T0
  TAY
  LDA SHP_LO,Y
  STA XS_LDA+1
  LDA SHP_HI,Y
  STA XS_LDA+2
  LDA XXX
  LSR A
  LSR A
  LSR A
  STA XCOL
  STZ XSHI
XS_COL:
  LDA XYY
  STA XCUR
  LDA XHGT
  STA XREM
XS_RUN:
  LDA XCUR                     ; lines in this cell: up to the cell end,
  AND #$07                     ; the end of the column, the bottom of the field
  STA T0
  LDA #8
  SEC
  SBC T0
  CMP XREM
  BCC XS_R1
  LDA XREM
XS_R1:
  STA XRUN
  LDA #FIELD_H
  SEC
  SBC XCUR
  CMP XRUN
  BCS XS_R2
  STA XRUN
XS_R2:
  LDA XCOL                     ; address: low = column*8 + line, high = cell row + 2
  ASL A
  ASL A
  ASL A
  ORA T0
  STA VREG
  STA XS_EOR+1
  STA XS_STA+1
  LDA XCUR
  LSR A
  LSR A
  LSR A
  CLC
  ADC #2
  TAX
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  TXA
  CLC
  ADC #>SH_PAT
  STA XS_EOR+2
  STA XS_STA+2
  LDY XSHI
  LDX #$00
XS_LOOP:
XS_LDA:
  LDA $FFFF,Y                  ; shape
XS_EOR:
  EOR $FFFF,X                  ; copy of the screen
XS_STA:
  STA $FFFF,X
  STA VDATA
  INY
  INX
  CPX XRUN
  BNE XS_LOOP
  STY XSHI
  LDA XCUR
  CLC
  ADC XRUN
  CMP #FIELD_H
  BCC XS_Y
  LDA #$00                     ; wrapped to the top of the field
XS_Y:
  STA XCUR
  LDA XREM
  SEC
  SBC XRUN
  STA XREM
  BNE XS_RUN
  LDA XCOL
  INC A
  AND #$1F
  STA XCOL
  DEC XNC
  BEQ XS_END
  JMP XS_COL
XS_END:
  RTS


; ===============================================================
;  WAVES AND HEARTBEAT
; ===============================================================
WAVE_CHECK:
  LDA ACOUNT
  BEQ .wc_empty
  LDA #90
  STA WAVET
  RTS
.wc_empty:
  DEC WAVET
  BNE .wc_ret
  LDX CURP                     ; 4, 6, 8, 10, 11, 11 ... large asteroids
  LDA WAVE,X
  ASL A
  CLC
  ADC #4
  CMP #12
  BCC .wc_n
  LDA #11
.wc_n:
  JSR SPAWN_WAVE
  LDX CURP
  LDA WAVE,X
  CMP #20
  BCS .wc_w
  INC WAVE,X
.wc_w:
  LDA #50                      ; the heartbeat starts slow again
  STA BEAT_I
  STA BEAT_T
.wc_ret:
  RTS

UPDATE_BEAT:
  LDA ACOUNT
  BEQ .ub_ret
  LDA SHIPST                   ; silent while the ship is not there
  CMP #$02
  BCS .ub_ret
  DEC BEAT_T
  BNE .ub_ret
  LDA BEAT_I
  STA BEAT_T
  LDA BEAT_N
  INC A
  STA SND_BEAT                 ; 1 / 2
  LDA BEAT_N
  EOR #$01
  STA BEAT_N
  BNE .ub_ret
  LDA BEAT_I                   ; faster every two beats
  CMP #15
  BCC .ub_ret
  DEC BEAT_I
.ub_ret:
  RTS


; ===============================================================
;  SAUCERS
; ===============================================================
UPDATE_UFO:
  LDA UFO_ON
  BNE .uu_fly
  LDA SHIPST                   ; ---- a new one now and then
  BNE .uu_ret
  LDA FRAME_CNT
  AND #$03
  BNE .uu_ret
  DEC UFSPN
  BEQ .uu_new
.uu_ret:
  RTS
.uu_new:
  LDX CURP                     ; small: always from 40000, often from 10000,
  LDA SCC,X                    ; sometimes before
  CMP #$04
  BCS .uu_small
  LDY #40
  CMP #$01
  BCC .uu_ch
  LDY #128
.uu_ch:
  STY T0
  JSR NEXT_RND
  LDA RND
  CMP T0
  BCC .uu_small
  LDA #$01
  BRA .uu_t
.uu_small:
  LDA #$02
.uu_t:
  STA UFO_ON
  STA SND_UFO
  JSR NEXT_RND
  LDA RND
  AND #$7F
  CLC
  ADC #20
  STA UFY
  STZ UFXL
  STZ UFDY
  LDA #40
  STA UFT
  LDY UFO_ON                   ; speed: large 1 px, small 1.5 px per frame
  LDA UFO_SPL,Y
  STA UFVXL
  LDA #$01
  STA UFVXH
  LDA RND
  BMI .uu_left
  STZ UFX                      ; from the left edge
  RTS
.uu_left:
  LDA #$FF                     ; from the right edge
  STA UFX
  LDA #$00
  SEC
  SBC UFVXL
  STA UFVXL
  LDA #$00
  SBC UFVXH
  STA UFVXH
  RTS
.uu_fly:
  ; ---- across the screen; it leaves on the other side
  CLC
  LDA UFXL
  ADC UFVXL
  STA UFXL
  LDA UFX
  ADC UFVXH
  STA UFX
  LDA UFVXH
  BMI .uu_ml
  BCS .uu_gone
  BRA .uu_y
.uu_ml:
  BCC .uu_gone
.uu_y:
  LDA FRAME_CNT
  AND #$01
  BNE .uu_c
  LDA UFY
  CLC
  ADC UFDY
  JSR WRAP_Y
  STA UFY
.uu_c:
  DEC UFT                      ; ---- change of course
  BNE .uu_f
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC #30
  STA UFT
  LDA RND
  AND #$03
  TAX
  LDA UFO_DY,X
  STA UFDY
.uu_f:
  LDA FRAME_CNT                ; ---- fire
  LDY UFO_ON
  AND UFO_FMASK,Y
  BNE .uu_hit
  JSR UFO_FIRE
.uu_hit:
  ; ---- against the asteroids
  LDA UFX
  STA OBX
  LDA UFY
  STA OBY
  LDA #5
  STA OBR
  JSR HIT_ASTEROID
  BCC .uu_ship
  STZ HITBY
  JSR ASTEROID_HIT
  LDA #$00
  JMP UFO_DESTROY
.uu_ship:
  LDA SHIPST                   ; against the ship
  BNE .uu_end
  LDA SHXH
  SEC
  SBC UFX
  JSR ABS_A
  CMP #10
  BCS .uu_end
  LDA SHYH
  SEC
  SBC UFY
  JSR ABS_A
  CMP #7
  BCS .uu_end
  JSR SHIP_DIE
  LDA #$01
  JMP UFO_DESTROY
.uu_end:
  RTS
.uu_gone:
  STZ UFO_ON
  STZ SND_UFO
  JMP UFO_TIMER

; A = 1: the player gets the points
UFO_DESTROY:
  BEQ .ud_np
  LDY UFO_ON
  LDA UFO_PTSL,Y
  STA PTS_L
  LDA UFO_PTSM,Y
  STA PTS_M
  JSR ADD_SCORE
.ud_np:
  LDA UFX
  STA PCX
  LDA UFY
  STA PCY
  JSR NEW_EXPL
  LDA #S_LARGE
  LDY UFX
  JSR BOOM_AT
  STZ UFO_ON
  STZ SND_UFO
UFO_TIMER:                     ; next saucer in 7-14 seconds
  JSR NEXT_RND
  LDA RND
  AND #$7F
  CLC
  ADC #100
  STA UFSPN
  RTS

UFO_FIRE:
  LDX #$04                     ; saucer shots: 4-5
  LDA B_T,X
  BEQ .uf_go
  INX
  LDA B_T,X
  BEQ .uf_go
  RTS
.uf_go:
  LDA #SHOT_LIFE
  STA B_T,X
  LDA UFX
  STA B_XH,X
  LDA UFY
  STA B_YH,X
  LDA #$80
  STA B_XL,X
  STA B_YL,X
  JSR NEXT_RND
  LDA UFO_ON
  CMP #$02
  BNE .uf_rnd
  LDA SHIPST
  BNE .uf_rnd
  JSR AIM                      ; small saucer: at the ship
  BRA .uf_dir
.uf_rnd:
  LDA RND                      ; large saucer: anywhere
  AND #$0F
.uf_dir:
  TAY
  LDA BVX_L,Y
  STA B_VXL,X
  LDA BVX_H,Y
  STA B_VXH,X
  LDA BVY_L,Y
  STA B_VYL,X
  LDA BVY_H,Y
  STA B_VYH,X
  LDA #W_UFOFIRE
  LDY UFX
  JMP SFX_AT

; A = direction (0-15, even) from the saucer to the ship
AIM:
  LDA SHXH
  SEC
  SBC UFX
  STA T2                       ; dx
  JSR ABS_A
  STA T4
  LDA SHYH
  SEC
  SBC UFY
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


; ===============================================================
;  SCORE AND HUD
; ===============================================================
; PTS_L / PTS_M (BCD) to the player in the game; extra ship every 10000
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
  ADC #$00
  STA SCC,X
  CLD
  CMP NXL,X
  BCC .as_d
  INC LIVES,X                  ; extra ship
  SED
  LDA NXL,X
  CLC
  ADC #$01
  STA NXL,X
  CLD
  LDA #W_LIFE
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
.as_d:
  JMP DRAW_SCORES

DRAW_HUD:
  LDA #$F1
  STA TCOL
  LDA #0
  STA CELLR
  LDA #13
  STA CELLC
  LDA HIC
  JSR PUT_BCD
  LDA HIB
  JSR PUT_BCD
  LDA HIA
  JSR PUT_BCD
  JSR DRAW_SCORES
  ; fall into DRAW_LIVES

; one '^' per ship under the score (up to 6)
DRAW_LIVES:
  LDA #1
  STA CELLR
  LDX #$00
.dl_p:
  CPX NPL
  BCS .dl_ret
  LDA SCORE_COL,X
  STA CELLC
  LDA #$F1
  STA TCOL
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
  PHX
  JSR PUT_CHAR
  PLX
  INC CELLC
  DEC T7
  BNE .dl_c
  INX
  BRA .dl_p
.dl_ret:
  RTS

DRAW_SCORES:
  LDA #0
  STA CELLR
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
  LDA SCC,X
  PHX
  JSR PUT_BCD
  PLX
  LDA SCB,X
  PHX
  JSR PUT_BCD
  PLX
  LDA SCA,X
  PHX
  JSR PUT_BCD
  PLX
  INX
  BRA .ds_p
.ds_ret:
  RTS


; ===============================================================
;  SCREEN
; ===============================================================
CLEAR_ALL:                     ; HUD black, playfield white on black
  LDA #$11
  STA CLRCOL
  LDA #0
  LDX #2
  JSR CLEAR_ROWS
  ; fall into CLEAR_PLAYFIELD
CLEAR_PLAYFIELD:
  LDA #$F1
  STA CLRCOL
  LDA #2
  LDX #22
  JMP CLEAR_ROWS

CLEAR_FIELD:                   ; no asteroids, shots, explosions, saucer
  LDX #(MAXA-1)
.cl_a:
  STZ A_SZ,X
  STZ A_DRAWN,X
  DEX
  BPL .cl_a
  LDX #(NSHOT-1)
.cl_b:
  STZ B_T,X
  DEX
  BPL .cl_b
  LDX #(NEXPL-1)
.cl_e:
  STZ E_T,X
  DEX
  BPL .cl_e
  STZ UFO_ON
  STZ SND_UFO
  STZ ACOUNT
  STZ RR
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
;  0 ship, 1 flame, 2 saucer, 3-8 shots, 9-11 explosions
; ===============================================================
BUILD_SAT:
  LDA SHIPST                   ; ---- ship and flame
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
  LDA THR                      ; the flame flickers, as on the cabinet
  BEQ .bs_nofl
  LDA FRAME_CNT
  AND #$02
  BEQ .bs_nofl
  LDA SPN
  CLC
  ADC #64
  STA SPN
  LDX #4
  JSR SET_SPR
  BRA .bs_ufo
.bs_noship:
  LDA #HIDE_Y
  STA SAT_BUFFER
.bs_nofl:
  LDA #HIDE_Y
  STA SAT_BUFFER+4
.bs_ufo:
  LDA UFO_ON                   ; ---- saucer
  BEQ .bs_noufo
  LDA UFX
  STA SPX
  LDA UFY
  STA SPY
  LDY UFO_ON
  LDA UFO_SPR,Y
  STA SPN
  LDX #8
  JSR SET_SPR
  BRA .bs_shots
.bs_noufo:
  LDA #HIDE_Y
  STA SAT_BUFFER+8
.bs_shots:
  LDX #$00                     ; ---- shots (2x2 pixels)
  LDY #12
.bs_sl:
  LDA B_T,X
  BEQ .bs_sh
  LDA B_YH,X
  CLC
  ADC #15
  STA SAT_BUFFER,Y
  LDA B_XH,X
  STA SAT_BUFFER+1,Y
  LDA #136
  STA SAT_BUFFER+2,Y
  LDA #$0F
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
  ADC #140
  STA SPN
  LDA E_X,X
  STA SPX
  LDA E_Y,X
  STA SPY
  LDA #$0F
  STA SPC
  LDA T6
  ASL A
  ASL A
  CLC
  ADC #36
  TAX
  JSR SET_SPR
  BRA .bs_en
.bs_eh:
  LDA T6
  ASL A
  ASL A
  TAX
  LDA #HIDE_Y
  STA SAT_BUFFER+36,X
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
  LDX #44
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
  LDA #<VDP_SPRITE_ATT_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_ATT_BASE)
  STA VREG
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX #49                 ; 12 sprites x 4 bytes + Y=$D0 of the 13th entry
  BNE .copy_sat
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

SAT_BUFFER:
  .byte HIDE_Y,0,0,$0F, HIDE_Y,0,64,$0F, HIDE_Y,0,128,$0F
  .byte HIDE_Y,0,136,$0F, HIDE_Y,0,136,$0F, HIDE_Y,0,136,$0F
  .byte HIDE_Y,0,136,$0F, HIDE_Y,0,136,$0F, HIDE_Y,0,136,$0F
  .byte HIDE_Y,0,140,$0F, HIDE_Y,0,140,$0F, HIDE_Y,0,140,$0F
  .byte $D0


; ===============================================================
;  SOUND: effects only (Asteroids has no music)
;  per chip: A = tone effects / saucer siren, B = noise (explosions,
;  thrust), C = heartbeat / thump of the explosions
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
  LDA SND_BEAT                  ; new beat
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
  ; ---- channel A: tone effect, otherwise the siren of the saucer
  LDA WH_ID,X
  BEQ .sf_siren
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
.sf_siren:
  LDA SND_UFO
  BEQ .sf_noise
  CMP #$02
  BEQ .sf_small
  LDA SND_PH                    ; large: slow and low, period 104-149
  LSR A
  AND #$1F
  JSR TRIANGLE
  STA SN1
  ASL A
  CLC
  ADC SN1
  CLC
  ADC #104
  BRA .sf_sv
.sf_small:
  LDA SND_PH                    ; small: fast and high, period 48-63
  AND #$0F
  ASL A
  JSR TRIANGLE
  CLC
  ADC #48
.sf_sv:
  STA SH_L,Y
  LDA #$00
  STA SH_L+1,Y
  LDA #$09
  STA SH_L+8,Y
.sf_noise:
  ; ---- channels B and C: explosion, otherwise thrust and heartbeat
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
;  LIBRARY (from lunar_lander): joystick, text, cells, VDP
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

; SAT: 0 lander, 1 flame, 2-5 explosion (2x2 sprites), then Y=$D0 = end of list

; ===============================================================
;  PIXEL (with a copy of the bitmap and of the colours in RAM)
; ===============================================================
; cell / line address: T0 = (x & $F8) | (y & 7), T1 = y / 8
PIX_ADDR:
  LDA PX
  AND #$F8
  STA T0
  LDA PY
  AND #$07
  ORA T0
  STA T0
  LDA PY
  LSR A
  LSR A
  LSR A
  STA T1
  RTS

PLOT_SET:                      ; lights (PX,PY) with colour PCOL
  JSR PIX_ADDR
  LDA PX
  AND #$07
  TAY
  LDA BITMASK,Y
  STA T2
  LDA T0
  STA SPTR
  LDA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA (SPTR)
  ORA T2
  STA (SPTR)
  STA T3
  LDA SPTR+1
  CLC
  ADC #(>SH_COL-(>SH_PAT))
  STA SPTR+1
  LDA PCOL
  STA (SPTR)
  LDA T0
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDA T3
  STA VDATA
  LDA T0
  STA VREG
  LDA T1
  ORA #$60
  STA VREG
  LDA PCOL
  STA VDATA
  RTS

PLOT_CLR:                      ; clears (PX,PY)
  JSR PIX_ADDR
  LDA PX
  AND #$07
  TAY
  LDA BITMASK,Y
  EOR #$FF
  STA T2
  LDA T0
  STA SPTR
  LDA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA (SPTR)
  AND T2
  STA (SPTR)
  STA T3
  LDA T0
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDA T3
  STA VDATA
  RTS


; ===============================================================
;  8x8 CELLS (copy in RAM + VRAM)
; ===============================================================
; from CELLC/CELLR: T0 = col*8, T1 = row, SPTR = pattern in RAM, PTR2 = colours in RAM
CELL_SETUP:
  LDA CELLC
  ASL A
  ASL A
  ASL A
  STA T0
  STA SPTR
  STA PTR2
  LDA CELLR
  STA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA T1
  CLC
  ADC #>SH_COL
  STA PTR2+1
  RTS

; copies the cell (copy in RAM) into the VRAM: needs CELL_SETUP
FLUSH_CELL:
  LDA T0
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDY #$00
.fl_p:
  LDA (SPTR),Y
  STA VDATA
  INY
  CPY #$08
  BNE .fl_p
  LDA T0
  STA VREG
  LDA T1
  ORA #$60
  STA VREG
  LDY #$00
.fl_c:
  LDA (PTR2),Y
  STA VDATA
  INY
  CPY #$08
  BNE .fl_c
  RTS

; draws the tile at PTR (8 pattern + 8 colour bytes) in (CELLC,CELLR); PTR moves on by 16
BLIT_CELL:
  JSR CELL_SETUP
  LDY #$00
.bl_p:
  LDA (PTR),Y
  STA (SPTR),Y
  INY
  CPY #$08
  BNE .bl_p
  LDA PTR
  CLC
  ADC #$08
  STA PTR
  BCC .bl_n1
  INC PTR+1
.bl_n1:
  LDY #$00
.bl_c:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  CPY #$08
  BNE .bl_c
  LDA PTR
  CLC
  ADC #$08
  STA PTR
  BCC .bl_n2
  INC PTR+1
.bl_n2:
  JMP FLUSH_CELL

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
  JSR CELL_SETUP
  LDY #$00
.pc_l:
  LDA (PTR),Y
  STA (SPTR),Y
  LDA TCOL
  STA (PTR2),Y
  INY
  CPY #$08
  BNE .pc_l
  JMP FLUSH_CELL

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

BIGLET:                        ; A = lettera, in (CELLC,CELLR), 2x2 tile
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
  LDA CELLC
  STA BIGC
  LDA CELLR
  STA BIGR
  JSR BLIT_CELL
  INC CELLC
  JSR BLIT_CELL
  LDA BIGC
  STA CELLC
  INC CELLR
  JSR BLIT_CELL
  INC CELLC
  JSR BLIT_CELL
  LDA BIGC
  STA CELLC
  LDA BIGR
  STA CELLR
  RTS



; first row in A, number of rows in X: clears the patterns, colours = CLRCOL
CLEAR_ROWS:
  STA T0
  STX T1
  LDA #$00
  STA SPTR
  STA PTR2
  LDA T0
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA T0
  CLC
  ADC #>SH_COL
  STA PTR2+1
  LDX T1
.cr_pg:
  LDY #$00
.cr_by:
  LDA #$00
  STA (SPTR),Y
  LDA CLRCOL
  STA (PTR2),Y
  INY
  BNE .cr_by
  INC SPTR+1
  INC PTR2+1
  DEX
  BNE .cr_pg
  LDA #$00
  STA VREG
  LDA T0
  ORA #$40
  STA VREG
  LDX T1
.cr_vp:
  LDY #$00
.cr_vpb:
  LDA #$00
  STA VDATA
  INY
  BNE .cr_vpb
  DEX
  BNE .cr_vp
  LDA #$00
  STA VREG
  LDA T0
  ORA #$60
  STA VREG
  LDX T1
.cr_vc:
  LDY #$00
.cr_vcb:
  LDA CLRCOL
  STA VDATA
  INY
  BNE .cr_vcb
  DEX
  BNE .cr_vc
  RTS

CLEAR_SCREEN:
  LDA #$00
  LDX #24
  JMP CLEAR_ROWS


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
; by size: 0 -, 1 small, 2 medium, 3 large
SZ_H:       .byte 0,6,10,16            ; height of the shape
SZ_C:       .byte 0,2,3,3              ; byte columns of the pre-shifted shape
SZ_BASE:    .byte 0,0,24,48            ; first entry in SHP_LO / SHP_HI
SZ_HALF:    .byte 0,3,5,8              ; centre from the top-left corner
SZ_R:       .byte 0,4,6,8              ; radius for the collisions
SZ_COST:    .byte 0,1,2,3              ; redraw cost
SZ_PTSL:    .byte 0,$00,$50,$20        ; points (BCD): 100, 50, 20
SZ_PTSM:    .byte 0,$01,$00,$00
SZ_SND:     .byte 0,S_SMALL,S_MED,S_LARGE
SZ_K:       .byte 0,3,2,1              ; speed x 0.5 px (plus 0-1 at random)
SCORE_COL:  .byte 1,25                 ; score and ships of player 1 / 2
; saucers: 0 -, 1 large, 2 small
UFO_SPL:    .byte 0,$00,$80            ; speed 1.0 / 1.5 px (low byte, high = 1)
UFO_DY:     .byte 0,1,$FF,0            ; vertical course
UFO_FMASK:  .byte 0,$3F,$1F            ; fires every 64 / 32 frames
UFO_PTSL:   .byte 0,$00,$00            ; 200 / 1000 points (BCD)
UFO_PTSM:   .byte 0,$02,$10
UFO_SPR:    .byte 0,128,132

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_TITLE:
  .byte 11,6,15,"BUTTON 1 = 1 PLAYER",0
  .byte 13,6,15,"BUTTON 2 = 2 PLAYERS",0
  .byte 17,2,14,"LEFT/RIGHT ROTATE  UP THRUST",0
  .byte 19,2,14,"BTN 1 FIRE  BTN 2 HYPERSPACE",0
  .byte $FF
TXT_PLAYER:
  .byte 1,12,11,"PLAYER",0
  .byte $FF
TXT_NOMSG:
  .byte 1,12,15,"        ",0
  .byte $FF
TXT_PRESS:
  .byte 16,9,15,"PRESS A BUTTON",0
  .byte $FF
; big words: row, column, number of letters, letters (A S T E R O I D G M V)
TITLE_BIG:
  .byte 6,7,9,0,1,2,3,4,5,6,7,1  ; ASTEROIDS
  .byte $FF
OVER_BIG:
  .byte 9,12,4,8,0,9,3           ; GAME
  .byte 12,12,4,5,10,3,4         ; OVER
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
; big letters (16x16, 4 tiles each, 8 pattern + 8 colour bytes): A S T E R O I D G M V
BIGFONT:
  ; A
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$80,$80,$60,$60,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $18,$F8,$F8,$18,$18,$18,$18,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; S
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$E0,$E0,$18,$18,$00,$00,$E0,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E0,$18,$18,$18,$18,$E0,$E0,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; T
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$F8,$F8,$80,$80,$80,$80,$80,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; E
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$F8,$F8,$00,$00,$00,$00,$E0,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; R
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E0,$80,$80,$60,$60,$18,$18,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; O
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; I
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$E0,$E0,$80,$80,$80,$80,$80,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $80,$80,$80,$80,$80,$E0,$E0,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; D
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; G
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$F8,$F8,$00,$00,$00,$00,$00,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $00,$78,$78,$18,$18,$F8,$F8,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; M
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$18,$18,$78,$78,$98,$98,$98,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $98,$18,$18,$18,$18,$18,$18,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  ; V
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $18,$06,$06,$06,$06,$01,$01,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $18,$60,$60,$60,$60,$80,$80,$00,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1

; sprites 16x16: 16 ship angles, 16 flame angles, big saucer, small saucer, shot, 4 explosion frames
SPR_PAGES = 5
SPRITES:
  .byte $00,$00,$00,$00,$01,$01,$01,$02,$02,$04,$04,$07,$08,$08,$00,$00
  .byte $00,$00,$80,$80,$40,$40,$40,$20,$20,$10,$10,$F0,$08,$08,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$02,$02,$04,$0C,$13,$20,$00,$00,$00,$00
  .byte $00,$00,$20,$60,$A0,$20,$20,$20,$40,$40,$40,$C0,$40,$40,$40,$00
  .byte $00,$00,$00,$00,$00,$01,$06,$18,$70,$08,$06,$01,$00,$01,$01,$00
  .byte $00,$00,$00,$18,$68,$90,$10,$20,$20,$40,$40,$80,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$7F,$08,$04,$04,$03,$02,$04,$08,$00,$00
  .byte $00,$00,$00,$00,$00,$FC,$08,$10,$20,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$18,$07,$04,$04,$04,$04,$04,$07,$18,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$38,$06,$38,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$08,$04,$02,$03,$04,$04,$08,$7F,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$20,$10,$08,$FC,$00,$00,$00,$00,$00
  .byte $00,$01,$01,$00,$01,$02,$04,$68,$18,$06,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$80,$40,$40,$20,$20,$10,$90,$68,$18,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$13,$0C,$04,$02,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$40,$40,$40,$C0,$40,$40,$40,$20,$20,$20,$A0,$60,$20,$00,$00
  .byte $00,$00,$00,$10,$10,$0F,$08,$04,$04,$02,$02,$01,$01,$00,$00,$00
  .byte $00,$00,$08,$08,$10,$F0,$10,$20,$20,$20,$40,$40,$40,$80,$80,$00
  .byte $00,$02,$02,$02,$03,$02,$02,$02,$04,$04,$04,$05,$06,$04,$00,$00
  .byte $00,$00,$00,$00,$04,$C8,$30,$20,$40,$40,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$01,$02,$02,$04,$04,$08,$09,$16,$18,$00,$00,$00
  .byte $00,$80,$80,$80,$40,$20,$20,$16,$18,$60,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$04,$08,$10,$3F,$00,$00,$00,$00,$00
  .byte $00,$00,$10,$20,$40,$C0,$20,$20,$10,$FE,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$0C,$30,$0E,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$0C,$30,$D0,$10,$10,$10,$10,$90,$70,$0C,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3F,$10,$08,$04,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$FE,$10,$20,$20,$C0,$40,$20,$10,$00,$00
  .byte $00,$00,$00,$18,$16,$09,$08,$04,$04,$02,$02,$01,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$60,$18,$16,$20,$20,$40,$80,$80,$80,$00
  .byte $00,$00,$04,$06,$05,$04,$04,$04,$02,$02,$02,$03,$02,$02,$02,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$40,$20,$30,$C8,$04,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$40,$40,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$08,$09,$0E,$08
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$10,$20,$26,$38,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$10,$20,$40,$40,$FC,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$08,$30,$C0,$30,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$FC,$40,$40,$20,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$38,$26,$20,$10,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $08,$0E,$09,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$40,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $10,$70,$90,$10,$10,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$1C,$64,$04,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$3F,$02,$02,$04,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$08,$06,$01,$03,$04,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$04,$02,$02,$3F,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$04,$64,$1C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$10,$10,$90,$70,$10
  .byte $00,$00,$00,$00,$01,$01,$02,$0F,$30,$7F,$20,$18,$07,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$40,$20,$F8,$06,$FF,$02,$0C,$F0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$07,$0F,$07,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$80,$E0,$F0,$E0,$00,$00,$00,$00,$00
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$02,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$40,$40,$40,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$02,$0C,$00,$00,$02,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$20,$10,$20,$00,$10,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$00,$08,$20,$00,$00,$00,$04,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$00,$08,$00,$10,$00,$00,$0C,$80,$00,$00,$00,$00
  .byte $00,$00,$04,$00,$00,$90,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$00,$02,$00,$00,$08,$00,$00,$02,$01,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; asteroid shapes (small 6x6, medium 10x10, large 16x16), 3 variants, pre-shifted 0-7 pixels.
; every shape: byte columns one after the other, one byte per line
; SHP_LO/HI index = size * 24 + variant * 8 + shift
SHP_LO:
  .byte <SHP_0_0_0,<SHP_0_0_1,<SHP_0_0_2,<SHP_0_0_3,<SHP_0_0_4,<SHP_0_0_5,<SHP_0_0_6,<SHP_0_0_7,<SHP_0_1_0,<SHP_0_1_1,<SHP_0_1_2,<SHP_0_1_3
  .byte <SHP_0_1_4,<SHP_0_1_5,<SHP_0_1_6,<SHP_0_1_7,<SHP_0_2_0,<SHP_0_2_1,<SHP_0_2_2,<SHP_0_2_3,<SHP_0_2_4,<SHP_0_2_5,<SHP_0_2_6,<SHP_0_2_7
  .byte <SHP_1_0_0,<SHP_1_0_1,<SHP_1_0_2,<SHP_1_0_3,<SHP_1_0_4,<SHP_1_0_5,<SHP_1_0_6,<SHP_1_0_7,<SHP_1_1_0,<SHP_1_1_1,<SHP_1_1_2,<SHP_1_1_3
  .byte <SHP_1_1_4,<SHP_1_1_5,<SHP_1_1_6,<SHP_1_1_7,<SHP_1_2_0,<SHP_1_2_1,<SHP_1_2_2,<SHP_1_2_3,<SHP_1_2_4,<SHP_1_2_5,<SHP_1_2_6,<SHP_1_2_7
  .byte <SHP_2_0_0,<SHP_2_0_1,<SHP_2_0_2,<SHP_2_0_3,<SHP_2_0_4,<SHP_2_0_5,<SHP_2_0_6,<SHP_2_0_7,<SHP_2_1_0,<SHP_2_1_1,<SHP_2_1_2,<SHP_2_1_3
  .byte <SHP_2_1_4,<SHP_2_1_5,<SHP_2_1_6,<SHP_2_1_7,<SHP_2_2_0,<SHP_2_2_1,<SHP_2_2_2,<SHP_2_2_3,<SHP_2_2_4,<SHP_2_2_5,<SHP_2_2_6,<SHP_2_2_7
SHP_HI:
  .byte >SHP_0_0_0,>SHP_0_0_1,>SHP_0_0_2,>SHP_0_0_3,>SHP_0_0_4,>SHP_0_0_5,>SHP_0_0_6,>SHP_0_0_7,>SHP_0_1_0,>SHP_0_1_1,>SHP_0_1_2,>SHP_0_1_3
  .byte >SHP_0_1_4,>SHP_0_1_5,>SHP_0_1_6,>SHP_0_1_7,>SHP_0_2_0,>SHP_0_2_1,>SHP_0_2_2,>SHP_0_2_3,>SHP_0_2_4,>SHP_0_2_5,>SHP_0_2_6,>SHP_0_2_7
  .byte >SHP_1_0_0,>SHP_1_0_1,>SHP_1_0_2,>SHP_1_0_3,>SHP_1_0_4,>SHP_1_0_5,>SHP_1_0_6,>SHP_1_0_7,>SHP_1_1_0,>SHP_1_1_1,>SHP_1_1_2,>SHP_1_1_3
  .byte >SHP_1_1_4,>SHP_1_1_5,>SHP_1_1_6,>SHP_1_1_7,>SHP_1_2_0,>SHP_1_2_1,>SHP_1_2_2,>SHP_1_2_3,>SHP_1_2_4,>SHP_1_2_5,>SHP_1_2_6,>SHP_1_2_7
  .byte >SHP_2_0_0,>SHP_2_0_1,>SHP_2_0_2,>SHP_2_0_3,>SHP_2_0_4,>SHP_2_0_5,>SHP_2_0_6,>SHP_2_0_7,>SHP_2_1_0,>SHP_2_1_1,>SHP_2_1_2,>SHP_2_1_3
  .byte >SHP_2_1_4,>SHP_2_1_5,>SHP_2_1_6,>SHP_2_1_7,>SHP_2_2_0,>SHP_2_2_1,>SHP_2_2_2,>SHP_2_2_3,>SHP_2_2_4,>SHP_2_2_5,>SHP_2_2_6,>SHP_2_2_7
SHP_0_0_0:
  .byte $00,$FC,$84,$88,$68,$10,$00,$00,$00,$00,$00,$00
SHP_0_0_1:
  .byte $00,$7E,$42,$44,$34,$08,$00,$00,$00,$00,$00,$00
SHP_0_0_2:
  .byte $00,$3F,$21,$22,$1A,$04,$00,$00,$00,$00,$00,$00
SHP_0_0_3:
  .byte $00,$1F,$10,$11,$0D,$02,$00,$80,$80,$00,$00,$00
SHP_0_0_4:
  .byte $00,$0F,$08,$08,$06,$01,$00,$C0,$40,$80,$80,$00
SHP_0_0_5:
  .byte $00,$07,$04,$04,$03,$00,$00,$E0,$20,$40,$40,$80
SHP_0_0_6:
  .byte $00,$03,$02,$02,$01,$00,$00,$F0,$10,$20,$A0,$40
SHP_0_0_7:
  .byte $00,$01,$01,$01,$00,$00,$00,$F8,$08,$10,$D0,$20
SHP_0_1_0:
  .byte $10,$68,$44,$48,$58,$20,$00,$00,$00,$00,$00,$00
SHP_0_1_1:
  .byte $08,$34,$22,$24,$2C,$10,$00,$00,$00,$00,$00,$00
SHP_0_1_2:
  .byte $04,$1A,$11,$12,$16,$08,$00,$00,$00,$00,$00,$00
SHP_0_1_3:
  .byte $02,$0D,$08,$09,$0B,$04,$00,$00,$80,$00,$00,$00
SHP_0_1_4:
  .byte $01,$06,$04,$04,$05,$02,$00,$80,$40,$80,$80,$00
SHP_0_1_5:
  .byte $00,$03,$02,$02,$02,$01,$80,$40,$20,$40,$C0,$00
SHP_0_1_6:
  .byte $00,$01,$01,$01,$01,$00,$40,$A0,$10,$20,$60,$80
SHP_0_1_7:
  .byte $00,$00,$00,$00,$00,$00,$20,$D0,$88,$90,$B0,$40
SHP_0_2_0:
  .byte $00,$78,$48,$88,$90,$70,$00,$00,$00,$00,$00,$00
SHP_0_2_1:
  .byte $00,$3C,$24,$44,$48,$38,$00,$00,$00,$00,$00,$00
SHP_0_2_2:
  .byte $00,$1E,$12,$22,$24,$1C,$00,$00,$00,$00,$00,$00
SHP_0_2_3:
  .byte $00,$0F,$09,$11,$12,$0E,$00,$00,$00,$00,$00,$00
SHP_0_2_4:
  .byte $00,$07,$04,$08,$09,$07,$00,$80,$80,$80,$00,$00
SHP_0_2_5:
  .byte $00,$03,$02,$04,$04,$03,$00,$C0,$40,$40,$80,$80
SHP_0_2_6:
  .byte $00,$01,$01,$02,$02,$01,$00,$E0,$20,$20,$40,$C0
SHP_0_2_7:
  .byte $00,$00,$00,$01,$01,$00,$00,$F0,$90,$10,$20,$E0
SHP_1_0_0:
  .byte $00,$06,$19,$60,$40,$80,$81,$72,$0A,$04,$00,$00,$00,$80,$40,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_1:
  .byte $00,$03,$0C,$30,$20,$40,$40,$39,$05,$02,$00,$00,$80,$40,$20,$40
  .byte $80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_2:
  .byte $00,$01,$06,$18,$10,$20,$20,$1C,$02,$01,$00,$80,$40,$20,$10,$20
  .byte $40,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_3:
  .byte $00,$00,$03,$0C,$08,$10,$10,$0E,$01,$00,$00,$C0,$20,$10,$08,$10
  .byte $20,$40,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_4:
  .byte $00,$00,$01,$06,$04,$08,$08,$07,$00,$00,$00,$60,$90,$08,$04,$08
  .byte $10,$20,$A0,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_5:
  .byte $00,$00,$00,$03,$02,$04,$04,$03,$00,$00,$00,$30,$C8,$04,$02,$04
  .byte $08,$90,$50,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_6:
  .byte $00,$00,$00,$01,$01,$02,$02,$01,$00,$00,$00,$18,$64,$82,$01,$02
  .byte $04,$C8,$28,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_0_7:
  .byte $00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$0C,$32,$C1,$80,$01
  .byte $02,$E4,$14,$08,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00
SHP_1_1_0:
  .byte $00,$0C,$72,$41,$40,$40,$21,$11,$16,$08,$00,$00,$00,$00,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_1:
  .byte $00,$06,$39,$20,$20,$20,$10,$08,$0B,$04,$00,$00,$00,$80,$40,$40
  .byte $80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_2:
  .byte $00,$03,$1C,$10,$10,$10,$08,$04,$05,$02,$00,$00,$80,$40,$20,$20
  .byte $40,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_3:
  .byte $00,$01,$0E,$08,$08,$08,$04,$02,$02,$01,$00,$80,$40,$20,$10,$10
  .byte $20,$20,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_4:
  .byte $00,$00,$07,$04,$04,$04,$02,$01,$01,$00,$00,$C0,$20,$10,$08,$08
  .byte $10,$10,$60,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_5:
  .byte $00,$00,$03,$02,$02,$02,$01,$00,$00,$00,$00,$60,$90,$08,$04,$04
  .byte $08,$88,$B0,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_6:
  .byte $00,$00,$01,$01,$01,$01,$00,$00,$00,$00,$00,$30,$C8,$04,$02,$02
  .byte $84,$44,$58,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_1_7:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$E4,$82,$81,$81
  .byte $42,$22,$2C,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_0:
  .byte $00,$00,$3F,$40,$40,$81,$81,$62,$1E,$00,$00,$00,$00,$80,$80,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_1:
  .byte $00,$00,$1F,$20,$20,$40,$40,$31,$0F,$00,$00,$00,$80,$40,$40,$80
  .byte $80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_2:
  .byte $00,$00,$0F,$10,$10,$20,$20,$18,$07,$00,$00,$00,$C0,$20,$20,$40
  .byte $40,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_3:
  .byte $00,$00,$07,$08,$08,$10,$10,$0C,$03,$00,$00,$00,$E0,$10,$10,$20
  .byte $20,$40,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_4:
  .byte $00,$00,$03,$04,$04,$08,$08,$06,$01,$00,$00,$00,$F0,$08,$08,$10
  .byte $10,$20,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_5:
  .byte $00,$00,$01,$02,$02,$04,$04,$03,$00,$00,$00,$00,$F8,$04,$04,$08
  .byte $08,$10,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_6:
  .byte $00,$00,$00,$01,$01,$02,$02,$01,$00,$00,$00,$00,$FC,$02,$02,$04
  .byte $04,$88,$78,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_1_2_7:
  .byte $00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$7E,$81,$81,$02
  .byte $02,$C4,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_0_0:
  .byte $00,$00,$00,$0F,$70,$40,$40,$40,$40,$40,$20,$38,$06,$01,$00,$00
  .byte $00,$00,$E0,$18,$06,$02,$01,$01,$02,$04,$04,$08,$10,$A0,$40,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_0_1:
  .byte $00,$00,$00,$07,$38,$20,$20,$20,$20,$20,$10,$1C,$03,$00,$00,$00
  .byte $00,$00,$70,$8C,$03,$01,$00,$00,$01,$02,$02,$04,$08,$D0,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_0_2:
  .byte $00,$00,$00,$03,$1C,$10,$10,$10,$10,$10,$08,$0E,$01,$00,$00,$00
  .byte $00,$00,$38,$C6,$01,$00,$00,$00,$00,$01,$01,$02,$84,$68,$10,$00
  .byte $00,$00,$00,$00,$80,$80,$40,$40,$80,$00,$00,$00,$00,$00,$00,$00
SHP_2_0_3:
  .byte $00,$00,$00,$01,$0E,$08,$08,$08,$08,$08,$04,$07,$00,$00,$00,$00
  .byte $00,$00,$1C,$E3,$00,$00,$00,$00,$00,$00,$00,$01,$C2,$34,$08,$00
  .byte $00,$00,$00,$00,$C0,$40,$20,$20,$40,$80,$80,$00,$00,$00,$00,$00
SHP_2_0_4:
  .byte $00,$00,$00,$00,$07,$04,$04,$04,$04,$04,$02,$03,$00,$00,$00,$00
  .byte $00,$00,$0E,$F1,$00,$00,$00,$00,$00,$00,$00,$80,$61,$1A,$04,$00
  .byte $00,$00,$00,$80,$60,$20,$10,$10,$20,$40,$40,$80,$00,$00,$00,$00
SHP_2_0_5:
  .byte $00,$00,$00,$00,$03,$02,$02,$02,$02,$02,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$07,$78,$80,$00,$00,$00,$00,$00,$00,$C0,$30,$0D,$02,$00
  .byte $00,$00,$00,$C0,$30,$10,$08,$08,$10,$20,$20,$40,$80,$00,$00,$00
SHP_2_0_6:
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$3C,$C0,$00,$00,$00,$00,$00,$80,$E0,$18,$06,$01,$00
  .byte $00,$00,$80,$60,$18,$08,$04,$04,$08,$10,$10,$20,$40,$80,$00,$00
SHP_2_0_7:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$1E,$E0,$80,$80,$80,$80,$80,$40,$70,$0C,$03,$00,$00
  .byte $00,$00,$C0,$30,$0C,$04,$02,$02,$04,$08,$08,$10,$20,$40,$80,$00
SHP_2_1_0:
  .byte $00,$00,$01,$3E,$20,$20,$20,$20,$20,$20,$10,$10,$08,$04,$03,$00
  .byte $00,$80,$40,$30,$08,$04,$04,$02,$04,$04,$08,$08,$30,$C0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_1_1:
  .byte $00,$00,$00,$1F,$10,$10,$10,$10,$10,$10,$08,$08,$04,$02,$01,$00
  .byte $00,$40,$A0,$18,$04,$02,$02,$01,$02,$02,$04,$04,$18,$60,$80,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_1_2:
  .byte $00,$00,$00,$0F,$08,$08,$08,$08,$08,$08,$04,$04,$02,$01,$00,$00
  .byte $00,$20,$50,$8C,$02,$01,$01,$00,$01,$01,$02,$02,$0C,$30,$C0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_1_3:
  .byte $00,$00,$00,$07,$04,$04,$04,$04,$04,$04,$02,$02,$01,$00,$00,$00
  .byte $00,$10,$28,$C6,$01,$00,$00,$00,$00,$00,$01,$01,$06,$98,$60,$00
  .byte $00,$00,$00,$00,$00,$80,$80,$40,$80,$80,$00,$00,$00,$00,$00,$00
SHP_2_1_4:
  .byte $00,$00,$00,$03,$02,$02,$02,$02,$02,$02,$01,$01,$00,$00,$00,$00
  .byte $00,$08,$14,$E3,$00,$00,$00,$00,$00,$00,$00,$00,$83,$4C,$30,$00
  .byte $00,$00,$00,$00,$80,$40,$40,$20,$40,$40,$80,$80,$00,$00,$00,$00
SHP_2_1_5:
  .byte $00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$04,$0A,$F1,$00,$00,$00,$00,$00,$00,$80,$80,$41,$26,$18,$00
  .byte $00,$00,$00,$80,$40,$20,$20,$10,$20,$20,$40,$40,$80,$00,$00,$00
SHP_2_1_6:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$05,$F8,$80,$80,$80,$80,$80,$80,$40,$40,$20,$13,$0C,$00
  .byte $00,$00,$00,$C0,$20,$10,$10,$08,$10,$10,$20,$20,$C0,$00,$00,$00
SHP_2_1_7:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$02,$7C,$40,$40,$40,$40,$40,$40,$20,$20,$10,$09,$06,$00
  .byte $00,$00,$80,$60,$10,$08,$08,$04,$08,$08,$10,$10,$60,$80,$00,$00
SHP_2_2_0:
  .byte $00,$00,$00,$0F,$10,$20,$20,$20,$40,$40,$20,$20,$10,$10,$0F,$00
  .byte $00,$00,$00,$F0,$08,$08,$04,$08,$08,$10,$10,$20,$20,$40,$C0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_2_1:
  .byte $00,$00,$00,$07,$08,$10,$10,$10,$20,$20,$10,$10,$08,$08,$07,$00
  .byte $00,$00,$00,$F8,$04,$04,$02,$04,$04,$08,$08,$10,$10,$20,$E0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_2_2:
  .byte $00,$00,$00,$03,$04,$08,$08,$08,$10,$10,$08,$08,$04,$04,$03,$00
  .byte $00,$00,$00,$FC,$02,$02,$01,$02,$02,$04,$04,$08,$08,$10,$F0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_2_3:
  .byte $00,$00,$00,$01,$02,$04,$04,$04,$08,$08,$04,$04,$02,$02,$01,$00
  .byte $00,$00,$00,$FE,$01,$01,$00,$01,$01,$02,$02,$04,$04,$08,$F8,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
SHP_2_2_4:
  .byte $00,$00,$00,$00,$01,$02,$02,$02,$04,$04,$02,$02,$01,$01,$00,$00
  .byte $00,$00,$00,$FF,$00,$00,$00,$00,$00,$01,$01,$02,$02,$04,$FC,$00
  .byte $00,$00,$00,$00,$80,$80,$40,$80,$80,$00,$00,$00,$00,$00,$00,$00
SHP_2_2_5:
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$02,$02,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$7F,$80,$00,$00,$00,$00,$00,$00,$01,$81,$82,$7E,$00
  .byte $00,$00,$00,$80,$40,$40,$20,$40,$40,$80,$80,$00,$00,$00,$00,$00
SHP_2_2_6:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$3F,$40,$80,$80,$80,$00,$00,$80,$80,$40,$41,$3F,$00
  .byte $00,$00,$00,$C0,$20,$20,$10,$20,$20,$40,$40,$80,$80,$00,$00,$00
SHP_2_2_7:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$1F,$20,$40,$40,$40,$80,$80,$40,$40,$20,$20,$1F,$00
  .byte $00,$00,$00,$E0,$10,$10,$08,$10,$10,$20,$20,$40,$40,$80,$80,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$30,$34,$39,$3F,$45,$4E,$59,$68,$45,$4B,$51,$58,$61,$6C,$7A
  .byte $8B,$24,$24,$24,$24,$24,$00,$00,$00,$00,$24,$24,$24,$24,$24,$00
  .byte $00,$00,$00,$24,$24,$24,$24,$24,$00,$00,$00,$00,$24,$24,$24,$24
  .byte $24
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00
WH_VOL:
  .byte $00,$0C,$0B,$0A,$09,$07,$06,$05,$04,$0B,$0A,$09,$08,$07,$06,$05
  .byte $04,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$00
  .byte $00,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$00,$0D,$0C,$0B,$0A
  .byte $09
WH_START:
  .byte $00,$01,$09,$11
WH_LEN:
  .byte $00,$08,$08,$20
W_FIRE = 1
W_UFOFIRE = 2
W_LIFE = 3

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00
  .byte $00,$0E,$0E,$0D,$0D,$0C,$0B,$0B,$0A,$0A,$09,$08,$08,$07,$07,$06
  .byte $05,$05,$04,$04,$03,$02,$02,$01,$01,$0F,$0F,$0F,$0E,$0E,$0D,$0D
  .byte $0C,$0C,$0B,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$06
  .byte $05,$05,$04,$04,$03,$03,$02,$02,$02,$01,$01,$0F,$0F,$0F,$0F,$0F
  .byte $0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0B,$0B
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$08
  .byte $07,$07,$07,$07,$06,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$04,$03,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$01
  .byte $00
EX_NP:
  .byte $00,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A
  .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$16,$16,$16,$16,$16
  .byte $16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17
  .byte $17,$17,$17,$17,$17,$17,$17,$17,$17,$17,$17,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19
  .byte $19,$19,$19,$19,$19,$19,$19,$19,$19,$19,$19,$1A,$1A,$1A,$1A,$1A
  .byte $1A
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0B,$0A,$09,$08,$07,$06
  .byte $05,$04,$03,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0D,$0D,$0D,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$08,$07,$07,$07
  .byte $06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03,$03,$02,$02,$02,$01
  .byte $01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$7D,$7D,$7D,$7D,$7D,$7D,$7D
  .byte $7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D
  .byte $7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04
EX_START:
  .byte $00,$01,$11,$29,$4B
EX_LEN:
  .byte $00,$10,$18,$22,$46
S_SMALL = 1
S_MED = 2
S_LARGE = 3
S_SHIP = 4
S_BIG = S_SHIP

; heartbeat: two low notes (period), volume envelope per frame
BEAT_TL:    .byte $36,$B2
BEAT_TH:    .byte $04,$04
BEAT_ENV:
  .byte $0F,$0F,$0E,$0D,$0C,$0A,$08,$06,$04,$02,$00
BEAT_LEN = 11

; directions: 0 = up, clockwise, 16 steps
; asteroid drift 0.5 px per frame (8.8 signed)
DIRX_L:
  .byte $00,$31,$5B,$76,$80,$76,$5B,$31,$00,$CF,$A5,$8A,$80,$8A,$A5,$CF
DIRX_H:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
DIRY_L:
  .byte $80,$8A,$A5,$CF,$00,$31,$5B,$76,$80,$76,$5B,$31,$00,$CF,$A5,$8A
DIRY_H:
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF
; shot speed 3.5 px per frame (8.8 signed)
BVX_L:
  .byte $00,$57,$7A,$3C,$80,$3C,$7A,$57,$00,$A9,$86,$C4,$80,$C4,$86,$A9
BVX_H:
  .byte $00,$01,$02,$03,$03,$03,$02,$01,$00,$FE,$FD,$FC,$FC,$FC,$FD,$FE
BVY_L:
  .byte $80,$C4,$86,$A9,$00,$57,$7A,$3C,$80,$3C,$7A,$57,$00,$A9,$86,$C4
BVY_H:
  .byte $FC,$FC,$FD,$FE,$00,$01,$02,$03,$03,$03,$02,$01,$00,$FE,$FD,$FC
; thrust (1/256 px per frame^2, signed)
THX:
  .byte $00,$03,$06,$08,$09,$08,$06,$03,$00,$FD,$FA,$F8,$F7,$F8,$FA,$FD
THY:
  .byte $F7,$F8,$FA,$FD,$00,$03,$06,$08,$09,$08,$06,$03,$00,$FD,$FA,$F8
; nose of the ship (pixels from the centre, signed)
NOSEX:
  .byte $00,$02,$04,$06,$06,$06,$04,$02,$00,$FE,$FC,$FA,$FA,$FA,$FC,$FE
NOSEY:
  .byte $FA,$FA,$FC,$FE,$00,$02,$04,$06,$06,$06,$04,$02,$00,$FE,$FC,$FA
