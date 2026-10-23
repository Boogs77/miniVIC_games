;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_SPACE_INVADERS  -  Taito Space Invaders (1978)      ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: asteroids / breakout (NMI + trampoline $0FD0,        ;
;   joystick VIA, bitmap shadow in RAM, AY sound engine)       ;
;                                                              ;
;   - 5 rows x 11 invaders: squid 30, crab 20, octopus 10      ;
;     points; mystery saucer 50-300 (300 on the 8th shot,      ;
;     then every 15 shots, as on the original)                 ;
;   - the invaders move ONE AT A TIME (one per frame, 2 px):   ;
;     the fewer they are, the faster they march; at the edge   ;
;     they drop 8 px; they stop while one of them explodes     ;
;   - 4 shields that crumble pixel by pixel under shots and    ;
;     bombs, and are eaten by the invaders passing through     ;
;   - 3 kinds of bombs: rolling (aimed at the cannon),         ;
;     plunger and squiggly (fixed column sequences); they      ;
;     come faster as the score grows                           ;
;   - every new wave starts lower; 3 cannons, one more at      ;
;     1500 points; if the invaders land the game is over       ;
;   - colours of the cabinet overlay: red band at the top      ;
;     (saucer), green band at the bottom (shields, cannon)     ;
;   - 1 or 2 players taking turns, each with his own invaders  ;
;     and shields; joystick 1 / joystick 2:                    ;
;       LEFT / RIGHT = move, any button = fire (one shot)      ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     the march of four low notes, one per step of the         ;
;     formation; shot; invader hit; saucer siren and saucer    ;
;     hit; cannon explosion; extra cannon                      ;
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
CURP        = $85      ; player at the cannon (0-1)
LIVES       = $86      ; 2 bytes: cannons per player
SCL         = $88      ; 2 bytes: score per player, BCD low
SCH         = $8A      ; 2 bytes: BCD high
HIL         = $8C      ; hi score
HIH         = $8D
PLX         = $8E      ; cannon X (left edge)
PLST        = $8F      ; cannon: 0 ok, 1 exploding, 2 waiting, 3 explosion over
PLT         = $90      ; timer of the cannon state
SHOT_ON     = $91      ; shot of the cannon
SHX         = $92
SHY         = $93      ; top line of the shot
EXT         = $94      ; invader explosion: frames left (the march stops)
EXX         = $95
EXY         = $96
B_ON        = $97      ; 3 bombs: 0 rolling, 1 plunger, 2 squiggly
B_X         = $9A
B_Y         = $9D
BOMBT       = $A0      ; frames to the next bomb
BTYPE       = $A1      ; next kind of bomb
PCI         = $A2      ; position in the plunger column sequence
SCI         = $A3      ; position in the squiggly column sequence
UFO_ON      = $A4      ; 0 none, 1 flying, 2 hit, 3 showing the points
UFX         = $A5
UFDX        = $A6      ; +1 / $FF
UFT         = $A7      ; 2 bytes: frames to the next saucer
UFOT        = $A9      ; timer of the hit / points
UFPI        = $AA      ; which points (0-3)
JOYC        = $AB      ; joystick of the player at the cannon
FIRE_OLD    = $AC
LANDED      = $AD      ; 1 = the invaders have reached the cannon
BX          = $AE      ; BLIT: X (even), cell row, shape, operation
BR          = $AF
BIDX        = $B0
BOP         = $B1      ;       0 = draw (OR), 1 = erase
AI          = $B2      ; invader being handled
PTS_L       = $B3      ; points to add (BCD)
PTS_M       = $B4
OBX         = $B5      ; ERODE: top-left corner
OBY         = $B6
BI          = $B7      ; bomb being handled
LOOPC       = $B8
WAITT       = $B9

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_BEAT   = $DC         ; request: 1-4 = note of the march
BEAT_POS   = $DD         ; NMI: frame of the note ($FF = silent)
BEAT_NOTE  = $DE
SND_UFO    = $DF         ; 1 = saucer siren
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects

; ---------------- the invaders of the player at the cannon ----------------
; one block $0800-$09FF, saved for each player at $7800 / $7C00
ALIVE   = $0800          ; 55 invaders, index = row * 11 + column (row 0 = bottom)
AXA     = $0840          ; X (left of the 16 pixel cell, even)
AYA     = $0880          ; Y (top, multiple of 8)
AFR     = $08C0          ; frame it is drawn with
ATYPE   = $0900          ; 0 squid, 1 crab, 2 octopus
RIP     = $0940          ; next invader to move
DXV     = $0941          ; +2 / -2
DROP    = $0942          ; 1 = this pass drops 8 px
EDGE    = $0943          ; 1 = an invader reached the edge in this pass
FRM     = $0944          ; frame of this pass
ALIVEN  = $0945          ; invaders alive
MARCH   = $0946          ; next note of the march
SHOTS   = $0947          ; shots fired, 0-14 (points of the saucer)
WAVEV   = $0948          ; wave
EXTRAG  = $0949          ; 1 = extra cannon already given
BLOCK   = $0800
SHIELD_SH = $5200        ; shields: rows 18-19 of the screen copy (512 bytes)
SAVE_B0 = $7800          ; player 1: block, shields
SAVE_S0 = $7A00
SAVE_B1 = $7C00          ; player 2
SAVE_S1 = $7E00

SH_PAT = $4000           ; copy of the screen (pattern) in RAM
SH_COL = $6000           ; copy of the colours

; ---------------- parameters ----------------
INV_Y0      = 40         ; top row of the first wave
SHIELD_Y    = 144        ; shields: lines 144-159 (cell rows 18-19)
PLAYER_Y    = 168        ; cannon
GROUND_Y    = 183        ; green line
LAND_Y      = 168        ; an invader here has landed
UFO_Y       = 24
X_LEFT      = 10         ; the formation turns here
X_RIGHT     = 232
BOMB_SPD    = 2
BTN_MASK    = %00110000
HIDE_Y      = $C0
COL_RED     = $81
COL_WHITE   = $F1
COL_GREEN   = $21

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
  STA HIL
  STA HIH
  STA FRAME_CNT
  STA LAST_FRAME
  STA CURP
  STA SND_UFO
  STA SND_BEAT
  LDX #$01
.rs_p:
  STA SCL,X
  STA SCH,X
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
;  TITLE SCREEN: the score advance table, as on the cabinet
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  JSR HIDE_SPRITES
  STZ SND_UFO
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR SETUP_SCREEN
  JSR DRAW_HUD
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR DRAW_TEXT
  STZ BOP                      ; the three invaders of the table
  LDA #84
  STA BX
  LDA #13
  STA BR
  LDA #0
  STA BIDX
  JSR BLIT
  LDA #15
  STA BR
  LDA #2
  STA BIDX
  JSR BLIT
  LDA #17
  STA BR
  LDA #4
  STA BIDX
  JSR BLIT
  LDA #(11*8-1)                ; the saucer (sprite)
  STA SAT_BUFFER+20
  LDA #84
  STA SAT_BUFFER+21
  LDA #64
  STA SAT_BUFFER+22
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
  JMP NEW_GAME


; ===============================================================
;  NEW GAME: the first wave of every player, saved
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME
  STA SND_CMD
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDX #$01
.ng_p:
  STZ SCL,X
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
  BEQ .ng_l1
  LDA #$03
  STA LIVES+1
.ng_l1:
  STZ WAVEV
  STZ EXTRAG
  STZ SHOTS
  JSR INIT_WAVE
  JSR BUILD_SHIELDS
  LDX CURP
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER: "PLAY PLAYER<n>", then his invaders and shields
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ SND_UFO
  JSR VDP_INT_OFF
  JSR SETUP_SCREEN
  JSR DRAW_HUD
  LDA #<TXT_PLAY
  STA TP
  LDA #>TXT_PLAY
  STA TP+1
  JSR DRAW_TEXT
  LDA #$F1
  STA TCOL
  LDA #12
  STA CELLR
  LDA #21
  STA CELLC
  LDA CURP
  CLC
  ADC #$31
  JSR PUT_CHAR
  JSR VDP_INT_ON
  LDA #120
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  LDA #<TXT_NOPLAY
  STA TP
  LDA #>TXT_NOPLAY
  STA TP+1
  JSR DRAW_TEXT
WAVE_SHOW:                     ; (VDP free) the field of the player at the cannon
  LDX CURP
  JSR LOAD_PLAYER
  JSR FLUSH_SHIELDS
  JSR DRAW_ALIENS
  LDA #24
  STA PLX
  STZ PLST
  STZ SHOT_ON
  STZ B_ON
  STZ B_ON+1
  STZ B_ON+2
  STZ UFO_ON
  STZ EXT
  STZ LANDED
  LDA #48
  STA BOMBT
  LDA #<1536
  STA UFT
  LDA #>1536
  STA UFT+1
  LDA #$FF
  STA FIRE_OLD
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
  JSR UPDATE_PLAYER
  LDA PLST
  BNE .gl_frozen               ; everything stops while the cannon explodes
  JSR UPDATE_SHOT
  JSR UPDATE_ALIENS
  JSR UPDATE_BOMBS
  JSR UPDATE_UFO
.gl_frozen:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA LANDED                   ; ---- invaded: the cannon blows up, game over for him
  BEQ .gl_n1
  STZ LANDED
  LDX CURP
  LDA #$01
  STA LIVES,X
  JSR PLAYER_HIT
.gl_n1:
  LDA PLST
  CMP #$03
  BNE .gl_n2
  JMP LOSE_LIFE
.gl_n2:
  LDA ALIVEN
  ORA EXT
  BNE .gl_n3
  JMP NEXT_WAVE
.gl_n3:
  JMP GAME_LOOP


; ---------------------------------------------------------------
; all the invaders are gone: a new wave, a bit lower, new shields
; ---------------------------------------------------------------
NEXT_WAVE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ SND_UFO
  LDA #60
  JSR WAIT_FRAMES
  INC WAVEV
  JSR VDP_INT_OFF
  JSR INIT_WAVE
  JSR BUILD_SHIELDS
  LDX CURP
  JSR SAVE_PLAYER
  JSR CLEAR_FIELD
  JSR DRAW_HUD                 ; the lives row was cleared too
  JMP WAVE_SHOW

; ---------------------------------------------------------------
; the explosion of the cannon is over
; ---------------------------------------------------------------
LOSE_LIFE:
  LDX #$FF
  TXS
  LDX CURP
  DEC LIVES,X
  STZ SHOT_ON
  STZ B_ON
  STZ B_ON+1
  STZ B_ON+2
  STZ UFO_ON
  STZ SND_UFO
  JSR VDP_INT_OFF
  JSR DRAW_LIVES
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #60
  JSR WAIT_FRAMES
  LDA NPL
  CMP #$02
  BNE .ll_same
  LDA CURP
  EOR #$01
  TAX
  LDA LIVES,X
  BEQ .ll_same
  LDX CURP                     ; the other player
  JSR SAVE_PLAYER
  LDA CURP
  EOR #$01
  STA CURP
  JMP TURN_START
.ll_same:
  LDX CURP
  LDA LIVES,X
  BEQ .ll_over
  LDA #24                      ; a new cannon on the left
  STA PLX
  STZ PLST
  LDA #$FF
  STA FIRE_OLD
  JMP GAME_LOOP
.ll_over:
  JMP GAME_OVER


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  STZ SND_UFO
  JSR HIDE_SPRITES
  LDX #$01                     ; hi score = best of the two players
.go_p:
  LDA SCH,X
  CMP HIH
  BCC .go_n
  BNE .go_new
  LDA SCL,X
  CMP HIL
  BCC .go_n
  BEQ .go_n
.go_new:
  LDA SCL,X
  STA HIL
  LDA SCH,X
  STA HIH
.go_n:
  DEX
  BPL .go_p
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  LDA #120
  JSR WAIT_FRAMES
  JSR WAIT_FIRE
  JMP TITLE


; ===============================================================
;  CANNON AND SHOT
; ===============================================================
UPDATE_PLAYER:
  LDA PLST
  BEQ .up_ok
  CMP #$01
  BNE .up_ret
  DEC PLT                      ; ---- exploding
  BNE .up_ret
  LDA #$03
  STA PLST
.up_ret:
  RTS
.up_ok:
  LDA JOYC                     ; ---- move: 1 px per frame
  AND #%00000100
  BEQ .up_r
  LDA PLX
  CMP #9
  BCC .up_fire
  DEC PLX
  BRA .up_fire
.up_r:
  LDA JOYC
  AND #%00001000
  BEQ .up_fire
  LDA PLX
  CMP #233
  BCS .up_fire
  INC PLX
.up_fire:
  LDA JOYC                     ; ---- fire: one shot at a time
  AND #BTN_MASK
  TAX
  EOR FIRE_OLD
  AND JOYC
  STX FIRE_OLD
  AND #BTN_MASK
  BEQ .up_ret
  LDA SHOT_ON
  BNE .up_ret
  LDA #$01
  STA SHOT_ON
  LDA PLX
  CLC
  ADC #6
  STA SHX
  LDA #(PLAYER_Y-4)
  STA SHY
  INC SHOTS                    ; shot counter for the saucer: 0-14
  LDA SHOTS
  CMP #15
  BCC .up_s
  STZ SHOTS
.up_s:
  LDA #W_SHOT
  LDY PLX
  JMP SFX_AT

PLAYER_HIT:
  LDA #$01
  STA PLST
  LDA #70
  STA PLT
  STZ SHOT_ON
  LDA #S_PLAYER
  LDX #2
  JMP SFX_BOOM

; the shot climbs 4 px per frame, one pixel at a time on the copy of the screen
UPDATE_SHOT:
  LDA SHOT_ON
  BNE .us_go
  RTS
.us_go:
  LDA #4
  STA LOOPC
.us_l:
  DEC SHY
  LDA SHY
  CMP #UFO_Y
  BCS .us_t
  STZ SHOT_ON                  ; out at the top
  RTS
.us_t:
  LDA SHX
  STA PX
  LDA SHY
  STA PY
  JSR PIX_GET
  BEQ .us_n
  JMP SHOT_HIT
.us_n:
  DEC LOOPC
  BNE .us_l
  ; ---- saucer (sprite)
  LDA UFO_ON
  CMP #$01
  BNE .us_bombs
  LDA SHY
  CMP #(UFO_Y+8)
  BCS .us_bombs
  LDA SHX
  SEC
  SBC UFX
  CMP #16
  BCS .us_bombs
  JMP UFO_HIT
.us_bombs:
  ; ---- bombs (sprites): shot and bomb destroy each other
  LDX #$02
.us_b:
  LDA B_ON,X
  BEQ .us_bn
  LDA SHX
  SEC
  SBC B_X,X
  CMP #3
  BCS .us_bn
  LDA SHY
  SEC
  SBC B_Y,X
  BCC .us_bn
  CMP #8
  BCS .us_bn
  STZ B_ON,X
  STZ SHOT_ON
  RTS
.us_bn:
  DEX
  BPL .us_b
  RTS

; the shot found a lit pixel at (PX, PY): invader or shield
SHOT_HIT:
  STZ SHOT_ON
  LDX #54
.sh_l:
  LDA ALIVE,X
  BEQ .sh_n
  LDA PX
  SEC
  SBC AXA,X
  CMP #16
  BCS .sh_n
  LDA PY
  SEC
  SBC AYA,X
  CMP #8
  BCS .sh_n
  JMP ALIEN_KILL
.sh_n:
  DEX
  BPL .sh_l
  LDA PY                       ; no invader: the shield crumbles
  CMP #SHIELD_Y
  BCC .sh_ret
  LDA PX
  SEC
  SBC #3
  STA OBX
  LDA PY
  SEC
  SBC #5
  STA OBY
  LDA #<SHOT_MASK
  STA PTR
  LDA #>SHOT_MASK
  STA PTR+1
  JMP ERODE
.sh_ret:
  RTS


; ===============================================================
;  INVADERS
; ===============================================================
; X = invader hit by the shot
ALIEN_KILL:
  STX AI
  LDA EXT                      ; the previous explosion goes away first
  BEQ .ak_go
  JSR CLEAR_BOOM
  LDX AI
.ak_go:
  STZ ALIVE,X
  DEC ALIVEN
  LDA #$01                     ; erase it
  STA BOP
  JSR BLIT_ALIEN
  LDX AI                       ; explosion in its place
  LDA AXA,X
  STA EXX
  STA BX
  LDA AYA,X
  STA EXY
  LSR A
  LSR A
  LSR A
  STA BR
  LDA #6
  STA BIDX
  STZ BOP
  JSR BLIT
  LDA #16
  STA EXT
  LDX AI
  LDY ATYPE,X
  LDA TYPE_PTS,Y
  STA PTS_L
  STZ PTS_M
  JSR ADD_SCORE
  LDA #S_ALIEN
  LDY EXX
  JMP BOOM_AT

; one invader per frame (the one after the last that moved)
UPDATE_ALIENS:
  LDA EXT                      ; an explosion freezes the march
  BEQ .ua_go
  DEC EXT
  BNE .ua_ret
  JMP CLEAR_BOOM
.ua_go:
  LDA ALIVEN
  BEQ .ua_ret
  LDA #56
  STA LOOPC                    ; at most one full pass (plus the end of the pass)
.ua_l:
  LDX RIP
  CPX #55
  BCC .ua_i
  JSR PASS_END
  LDX #$00
.ua_i:
  INX
  STX RIP
  DEX
  LDA ALIVE,X
  BNE MOVE_ALIEN
  DEC LOOPC
  BNE .ua_l
.ua_ret:
  RTS

CLEAR_BOOM:                    ; the explosion goes away
  STZ EXT
  LDA EXX
  STA BX
  LDA EXY
  LSR A
  LSR A
  LSR A
  STA BR
  LDA #6
  STA BIDX
  LDA #$01
  STA BOP
  JMP BLIT

; X = invader: erase, step (2 px sideways or 8 px down), draw with the frame of the pass
MOVE_ALIEN:
  STX AI
  LDA #$01
  STA BOP
  JSR BLIT_ALIEN
  LDX AI
  LDA DROP
  BEQ .mv_side
  LDA AYA,X
  CLC
  ADC #8
  STA AYA,X
  CMP #LAND_Y
  BCC .mv_draw
  LDA #$01
  STA LANDED
  BRA .mv_draw
.mv_side:
  LDA AXA,X
  CLC
  ADC DXV
  STA AXA,X
  LDY DXV
  BMI .mv_left
  CMP #X_RIGHT
  BCC .mv_draw
  BRA .mv_edge
.mv_left:
  CMP #X_LEFT
  BCS .mv_draw
.mv_edge:
  LDA #$01
  STA EDGE
.mv_draw:
  LDA FRM
  STA AFR,X
  STZ BOP
  ; fall into BLIT_ALIEN

; draws / erases (BOP) the invader AI with its frame AFR
BLIT_ALIEN:
  LDX AI
  LDA AXA,X
  STA BX
  LDA AYA,X
  LSR A
  LSR A
  LSR A
  STA BR
  LDA ATYPE,X
  ASL A
  ORA AFR,X
  STA BIDX
  JMP BLIT

; end of a pass of the formation: drop / turn, next frame, note of the march
PASS_END:
  STZ RIP
  LDA DROP
  BEQ .pe_edge
  STZ DROP
  BRA .pe_f
.pe_edge:
  LDA EDGE
  BEQ .pe_f
  STZ EDGE
  LDA #$01
  STA DROP
  LDA #$00
  SEC
  SBC DXV
  STA DXV
.pe_f:
  LDA FRM
  EOR #$01
  STA FRM
  LDA MARCH
  INC A
  STA SND_BEAT
  AND #$03
  STA MARCH
  RTS

; a new wave of the player at the cannon (arrays and variables of the block)
INIT_WAVE:
  LDA WAVEV                    ; every wave starts 8 px lower (up to 4)
  CMP #4
  BCC .iw_w
  LDA #4
.iw_w:
  ASL A
  ASL A
  ASL A
  CLC
  ADC #(INV_Y0+64)
  STA T2                       ; Y of the bottom row
  LDX #$00
  STZ T0                       ; row 0-4 (0 = bottom)
.iw_r:
  STZ T1                       ; column 0-10
  LDA #24
  STA T3                       ; X
.iw_c:
  LDA #$01
  STA ALIVE,X
  STZ AFR,X
  LDA T3
  STA AXA,X
  LDA T2
  STA AYA,X
  LDY T0
  LDA ROW_TYPE,Y
  STA ATYPE,X
  INX
  LDA T3
  CLC
  ADC #16
  STA T3
  INC T1
  LDA T1
  CMP #11
  BNE .iw_c
  LDA T2
  SEC
  SBC #16
  STA T2
  INC T0
  LDA T0
  CMP #5
  BNE .iw_r
  STZ RIP
  LDA #2
  STA DXV
  STZ DROP
  STZ EDGE
  STZ FRM
  LDA #55
  STA ALIVEN
  STZ MARCH
  RTS

DRAW_ALIENS:
  STZ BOP
  LDX #54
.da_l:
  LDA ALIVE,X
  BEQ .da_n
  STX AI
  JSR BLIT_ALIEN
  LDX AI
.da_n:
  DEX
  BPL .da_l
  RTS


; ===============================================================
;  BOMBS
; ===============================================================
UPDATE_BOMBS:
  LDX #$02
.ub_l:
  STX BI
  LDA B_ON,X
  BEQ .ub_n
  LDA #BOMB_SPD
  STA LOOPC
.ub_s:
  LDX BI
  INC B_Y,X
  LDA B_Y,X
  CLC
  ADC #6
  CMP #GROUND_Y
  BCS .ub_off                  ; on the ground
  STA PY
  LDA B_X,X
  INC A
  STA PX
  JSR PIX_GET
  BEQ .ub_ns
  LDA PY                       ; a shield: it crumbles
  CMP #SHIELD_Y
  BCC .ub_ns
  CMP #(SHIELD_Y+16)
  BCS .ub_ns
  LDA PX
  SEC
  SBC #3
  STA OBX
  LDA PY
  SEC
  SBC #1
  STA OBY
  LDA #<BOMB_MASK
  STA PTR
  LDA #>BOMB_MASK
  STA PTR+1
  JSR ERODE
  LDX BI
  BRA .ub_off
.ub_ns:
  DEC LOOPC
  BNE .ub_s
  LDX BI                       ; ---- the cannon
  LDA B_Y,X
  CLC
  ADC #6
  CMP #PLAYER_Y
  BCC .ub_n
  LDA B_Y,X
  CMP #(PLAYER_Y+8)
  BCS .ub_n
  LDA B_X,X
  CLC
  ADC #2
  SEC
  SBC PLX
  CMP #15
  BCS .ub_n
  STZ B_ON,X
  JMP PLAYER_HIT
.ub_off:
  STZ B_ON,X
.ub_n:
  LDX BI
  DEX
  BPL .ub_l
  ; ---- a new bomb?
  DEC BOMBT
  BNE .ub_ret
  JSR RELOAD
  STA BOMBT
  LDX BTYPE
  INX
  CPX #3
  BCC .ub_t
  LDX #$00
.ub_t:
  STX BTYPE
  LDA B_ON,X
  BNE .ub_ret
  JMP FIRE_BOMB
.ub_ret:
  RTS

; frames between two bombs, by score (as on the original)
RELOAD:
  LDX CURP
  LDA SCH,X
  LDY #0
.rl_l:
  CMP RELOAD_SC,Y
  BCC .rl_f
  INY
  CPY #4
  BNE .rl_l
.rl_f:
  LDA RELOAD_T,Y
  RTS

; X = kind of bomb: from the lowest invader of a column
FIRE_BOMB:
  STX BI
  CPX #$00
  BNE .fb_tab
  JSR AIM_COLUMN               ; rolling: the column over the cannon
  BRA .fb_col
.fb_tab:
  CPX #$01
  BNE .fb_sq
  LDY PCI                      ; plunger
  INY
  TYA
  AND #$0F
  STA PCI
  TAY
  LDA PLUNGER_COLS,Y
  BRA .fb_col
.fb_sq:
  LDY SCI                      ; squiggly
  INY
  TYA
  AND #$0F
  STA SCI
  TAY
  LDA SQUIG_COLS,Y
.fb_col:
  JSR LOWEST                   ; X = invader, carry = 0 if the column is empty
  BCC .fb_ret
  LDY BI
  LDA AXA,X
  CLC
  ADC #7
  STA B_X,Y
  LDA AYA,X
  CLC
  ADC #8
  STA B_Y,Y
  LDA #$01
  STA B_ON,Y
.fb_ret:
  RTS

; A = column: X = lowest invader alive, carry = 1 (0 = empty column)
LOWEST:
  TAX
.lo_l:
  LDA ALIVE,X
  BNE .lo_ok
  TXA
  CLC
  ADC #11
  TAX
  CMP #55
  BCC .lo_l
  CLC
  RTS
.lo_ok:
  SEC
  RTS

; A = column with an invader closest to the cannon
AIM_COLUMN:
  LDA #$FF
  STA T6                       ; best distance
  STZ T7                       ; best column
  LDA #10
  STA T5
.ac_l:
  LDA T5
  JSR LOWEST
  BCC .ac_n
  LDA AXA,X
  CLC
  ADC #1
  SEC
  SBC PLX
  JSR ABS_A
  CMP T6
  BCS .ac_n
  STA T6
  LDA T5
  STA T7
.ac_n:
  DEC T5
  BPL .ac_l
  LDA T7
  RTS

ABS_A:                         ; A = |A| (signed)
  BPL .ab_r
  EOR #$FF
  CLC
  ADC #1
.ab_r:
  RTS


; ===============================================================
;  MYSTERY SAUCER
; ===============================================================
UPDATE_UFO:
  LDA UFO_ON
  BNE .uu_on
  JMP .uu_wait
.uu_on:
  CMP #$01
  BNE .uu_hit
  JMP .uu_fly
.uu_hit:
  DEC UFOT                     ; ---- hit: explosion, then the points
  BNE .uu_ret
  LDA UFO_ON
  CMP #$03
  BEQ .uu_clr
  LDA #$03
  STA UFO_ON
  LDA #60
  STA UFOT
  LDA #<TXT_UFOPTS             ; the points where the saucer was
  STA TP
  LDA UFPI
  ASL A
  ASL A
  CLC
  ADC #<TXT_UFOPTS
  STA TP
  LDA #>TXT_UFOPTS
  ADC #0
  STA TP+1
  BRA .uu_txt
.uu_clr:
  STZ UFO_ON
  LDA #<TXT_UFOCLR
  STA TP
  LDA #>TXT_UFOCLR
  STA TP+1
.uu_txt:
  LDA #COL_RED
  STA TCOL
  LDA #3
  STA CELLR
  LDA UFX
  LSR A
  LSR A
  LSR A
  STA CELLC
  LDY #$00
.uu_c:
  LDA (TP),Y
  STY TYV
  JSR PUT_CHAR
  INC CELLC
  LDY TYV
  INY
  CPY #3
  BNE .uu_c
.uu_ret:
  RTS
.uu_wait:
  LDA ALIVEN                   ; ---- every 25 seconds, with 8 invaders or more
  CMP #8
  BCC .uu_ret
  LDA UFT
  BNE .uu_d
  DEC UFT+1
.uu_d:
  DEC UFT
  LDA UFT
  ORA UFT+1
  BNE .uu_ret
  LDA #<1536
  STA UFT
  LDA #>1536
  STA UFT+1
  LDA #$01
  STA UFO_ON
  STA SND_UFO
  LDA SHOTS                    ; side by the shot counter
  LSR A
  BCC .uu_r
  STZ UFX
  LDA #$01
  STA UFDX
  RTS
.uu_r:
  LDA #224
  STA UFX
  LDA #$FF
  STA UFDX
  RTS
.uu_fly:
  LDA UFX
  CLC
  ADC UFDX
  STA UFX
  BEQ .uu_gone
  CMP #225
  BCS .uu_gone
  RTS
.uu_gone:
  STZ UFO_ON
  STZ SND_UFO
  RTS

UFO_HIT:
  STZ SHOT_ON
  STZ SND_UFO
  LDA #$02
  STA UFO_ON
  LDA #24
  STA UFOT
  LDA UFX                      ; the points stay on whole cells
  AND #$F8
  STA UFX
  LDY SHOTS                    ; points by the number of the shot
  DEY
  BPL .uh_i
  LDY #14
.uh_i:
  LDA UFO_SEQ,Y
  STA UFPI
  TAY
  LDA UFO_PL,Y
  STA PTS_L
  LDA UFO_PM,Y
  STA PTS_M
  JSR ADD_SCORE
  LDA #W_UFOHIT
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  BITMAP: invaders, shields, erosion
; ===============================================================
; BX (even), BR (cell row), BIDX (shape), BOP (0 draw, 1 erase):
; 3 cells x 8 lines, on the copy and on the screen
BLIT:
  LDY BIDX
  LDA BX
  LSR A
  AND #$03
  TAX
  LDA SHAPE_LO,Y
  CLC
  ADC SHIFT24,X
  STA PTR
  LDA SHAPE_HI,Y
  ADC #0
  STA PTR+1
BLIT_PTR:                      ; same, with the data at PTR (24 bytes)
  LDA BX
  AND #$F8
  STA SPTR
  STA VREG
  LDA BR
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  LDA BR
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDY #$00
  LDA BOP
  BNE .bl_clr
.bl_or:
  LDA (PTR),Y
  ORA (SPTR),Y
  STA (SPTR),Y
  STA VDATA
  INY
  CPY #24
  BNE .bl_or
  RTS
.bl_clr:
  LDA (PTR),Y
  EOR #$FF
  AND (SPTR),Y
  STA (SPTR),Y
  STA VDATA
  INY
  CPY #24
  BNE .bl_clr
  RTS

; the 4 shields, on a clean shield band
BUILD_SHIELDS:
  LDA #COL_GREEN
  STA CLRCOL
  LDA #18
  LDX #2
  JSR CLEAR_ROWS
  STZ BOP
  LDA #32
  STA BX
.bs_l:
  LDA #18
  STA BR
  LDA #<SHIELD_TOP
  STA PTR
  LDA #>SHIELD_TOP
  STA PTR+1
  JSR BLIT_PTR
  LDA #19
  STA BR
  LDA #<SHIELD_BOT
  STA PTR
  LDA #>SHIELD_BOT
  STA PTR+1
  JSR BLIT_PTR
  LDA BX
  CLC
  ADC #56
  STA BX
  BCC .bs_l                    ; 32, 88, 144, 200
  RTS

; the shield band of the copy -> screen
FLUSH_SHIELDS:
  LDA #$00
  STA VREG
  LDA #(18 | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDX #$00
.fs_a:
  LDA SHIELD_SH,X
  STA VDATA
  INX
  BNE .fs_a
.fs_b:
  LDA SHIELD_SH+$100,X
  STA VDATA
  INX
  BNE .fs_b
  RTS

; pixels of the 8x8 mask at PTR removed at (OBX, OBY), only inside the shield band
ERODE:
  LDA #$00
  STA LOOPC                    ; line of the mask
.er_l:
  LDA OBY
  CLC
  ADC LOOPC
  CMP #SHIELD_Y
  BCC .er_n
  CMP #(SHIELD_Y+16)
  BCS .er_n
  STA PY
  LDY LOOPC
  LDA (PTR),Y
  BEQ .er_n
  STA T4                       ; mask, left byte
  STZ T5                       ;       right byte
  LDA OBX
  AND #$07
  TAX
  BEQ .er_s
.er_sh:
  LSR T4
  ROR T5
  DEX
  BNE .er_sh
.er_s:
  LDA OBX
  AND #$F8
  STA PX
  LDA T4
  JSR .er_byte
  LDA PX
  CMP #$F8
  BCS .er_n
  CLC
  ADC #8
  STA PX
  LDA T5
  JSR .er_byte
.er_n:
  INC LOOPC
  LDA LOOPC
  CMP #8
  BNE .er_l
  RTS
.er_byte:                      ; A = bits to remove at (PX, PY)
  BEQ .eb_r
  EOR #$FF
  STA T3
  JSR PIX_ADDR
  LDA T0
  STA SPTR
  STA VREG
  LDA T1
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  LDA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA (SPTR)
  AND T3
  STA (SPTR)
  STA VDATA
.eb_r:
  RTS

; Z = 0 when the pixel (PX, PY) is lit on the copy of the screen
PIX_GET:
  JSR PIX_ADDR
  LDA T0
  STA SPTR
  LDA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA PX
  AND #$07
  TAY
  LDA (SPTR)
  AND BITMASK,Y
  RTS


; ===============================================================
;  PLAYERS: save / load the block and the shields
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDA #<BLOCK
  STA PTR
  LDA #>BLOCK
  STA PTR+1
  LDA SAVEB_HI,X
  STA PTR2+1
  PHX
  JSR .sp_cp
  PLX
  LDA #<SHIELD_SH
  STA PTR
  LDA #>SHIELD_SH
  STA PTR+1
  LDA SAVES_HI,X
  STA PTR2+1
.sp_cp:
  STZ PTR2
  LDX #$02                     ; 2 pages
.sp_p:
  LDY #$00
.sp_b:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  BNE .sp_b
  INC PTR+1
  INC PTR2+1
  DEX
  BNE .sp_p
  RTS

LOAD_PLAYER:                   ; X = player
  LDA SAVEB_HI,X
  STA PTR+1
  LDA #>BLOCK
  STA PTR2+1
  PHX
  JSR .lp_cp
  PLX
  LDA SAVES_HI,X
  STA PTR+1
  LDA #>SHIELD_SH
  STA PTR2+1
.lp_cp:
  STZ PTR
  STZ PTR2
  LDX #$02
.lp_p:
  LDY #$00
.lp_b:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  BNE .lp_b
  INC PTR+1
  INC PTR2+1
  DEX
  BNE .lp_p
  RTS


; ===============================================================
;  SCORE AND SCREEN
; ===============================================================
; PTS_L / PTS_M (BCD) to the player at the cannon; one more cannon at 1500
ADD_SCORE:
  LDX CURP
  SED
  CLC
  LDA SCL,X
  ADC PTS_L
  STA SCL,X
  LDA SCH,X
  ADC PTS_M
  STA SCH,X
  CLD
  LDA EXTRAG
  BNE .as_d
  LDA SCH,X
  CMP #$15
  BCC .as_d
  LDA #$01
  STA EXTRAG
  INC LIVES,X
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
.as_d:
  JMP DRAW_SCORES

; colour bands of the overlay, green line, empty field
SETUP_SCREEN:
  LDA #$11
  STA CLRCOL
  LDA #0
  LDX #2
  JSR CLEAR_ROWS
CLEAR_FIELD:                   ; (rows 2-23, shields included)
  LDA #COL_RED
  STA CLRCOL
  LDA #2
  LDX #2
  JSR CLEAR_ROWS
  LDA #COL_WHITE
  STA CLRCOL
  LDA #4
  LDX #14
  JSR CLEAR_ROWS
  LDA #COL_GREEN
  STA CLRCOL
  LDA #18
  LDX #6
  JSR CLEAR_ROWS
  LDA #22                      ; the green line
  STA CELLR
  STZ CELLC
.ss_g:
  JSR CELL_SETUP
  LDY #7
  LDA #$FF
  STA (SPTR),Y
  JSR FLUSH_CELL
  INC CELLC
  LDA CELLC
  CMP #32
  BNE .ss_g
  RTS

DRAW_HUD:
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR DRAW_TEXT
  LDA #$F1
  STA TCOL
  LDA #1
  STA CELLR
  LDA #13
  STA CELLC
  LDA HIH
  JSR PUT_BCD
  LDA HIL
  JSR PUT_BCD
  JSR DRAW_SCORES
  ; fall into DRAW_LIVES

; row 23: cannons left, then the spare cannons
DRAW_LIVES:
  LDA #COL_GREEN
  STA TCOL
  LDA #23
  STA CELLR
  LDA #1
  STA CELLC
  LDX CURP
  LDA LIVES,X
  STA T6
  ORA #$30
  JSR PUT_CHAR
  LDA #3
  STA CELLC
  DEC T6                       ; spare cannons = cannons - 1 (up to 5)
  LDA #5
  STA T7
.dl_l:
  LDA T6
  BEQ .dl_blank
  BMI .dl_blank
  DEC T6
  LDA #<LIFE_ICON
  STA PTR
  LDA #>LIFE_ICON
  STA PTR+1
  JSR FILL_CELL
  INC CELLC
  LDA #<(LIFE_ICON+8)
  STA PTR
  LDA #>(LIFE_ICON+8)
  STA PTR+1
  JSR FILL_CELL
  BRA .dl_n
.dl_blank:
  LDA #<ZERO8
  STA PTR
  LDA #>ZERO8
  STA PTR+1
  JSR FILL_CELL
  INC CELLC
  JSR FILL_CELL
.dl_n:
  INC CELLC
  DEC T7
  BNE .dl_l
  RTS

DRAW_SCORES:
  LDA #1
  STA CELLR
  LDA #$F1
  STA TCOL
  LDX #$00
.ds_p:
  LDA SCORE_COL,X
  STA CELLC
  LDA SCH,X
  PHX
  JSR PUT_BCD
  PLX
  LDA SCL,X
  PHX
  JSR PUT_BCD
  PLX
  INX
  CPX #$02
  BNE .ds_p
  RTS

; 8 pattern bytes at PTR, colour TCOL, into (CELLC,CELLR)
FILL_CELL:
  JSR CELL_SETUP
  LDY #$00
.fc_l:
  LDA (PTR),Y
  STA (SPTR),Y
  LDA TCOL
  STA (PTR2),Y
  INY
  CPY #$08
  BNE .fc_l
  JMP FLUSH_CELL


; ===============================================================
;  SPRITES AND NMI
;  0 cannon, 1 shot, 2-4 bombs, 5 saucer
; ===============================================================
BUILD_SAT:
  LDA PLST                     ; ---- cannon
  CMP #$02
  BCS .bs_nopl
  LDA #(PLAYER_Y-1)
  STA SAT_BUFFER
  LDA PLX
  STA SAT_BUFFER+1
  LDA #0
  LDX PLST
  BEQ .bs_pn
  LDA FRAME_CNT                ; exploding: two patterns
  AND #$04
  CLC
  ADC #4
.bs_pn:
  STA SAT_BUFFER+2
  BRA .bs_shot
.bs_nopl:
  LDA #HIDE_Y
  STA SAT_BUFFER
.bs_shot:
  LDA SHOT_ON                  ; ---- shot
  BEQ .bs_nosh
  LDA SHY
  DEC A
  STA SAT_BUFFER+4
  LDA SHX
  STA SAT_BUFFER+5
  LDA #$0F
  LDX SHY
  CPX #SHIELD_Y
  BCC .bs_sc
  LDA #$02
.bs_sc:
  STA SAT_BUFFER+7
  BRA .bs_bombs
.bs_nosh:
  LDA #HIDE_Y
  STA SAT_BUFFER+4
.bs_bombs:
  LDX #$00                     ; ---- bombs (4 frames each)
  LDY #8
.bs_bl:
  LDA B_ON,X
  BEQ .bs_bh
  LDA B_Y,X
  DEC A
  STA SAT_BUFFER,Y
  LDA B_X,X
  STA SAT_BUFFER+1,Y
  TXA
  ASL A
  ASL A
  STA T0
  LDA FRAME_CNT
  LSR A
  LSR A
  AND #$03
  CLC
  ADC T0
  ASL A
  ASL A
  CLC
  ADC #16
  STA SAT_BUFFER+2,Y
  LDA B_Y,X                    ; green in the band of the overlay
  CMP #(SHIELD_Y-4)
  LDA #$0F
  BCC .bs_bc
  LDA #$02
.bs_bc:
  STA SAT_BUFFER+3,Y
  BRA .bs_bn
.bs_bh:
  LDA #HIDE_Y
  STA SAT_BUFFER,Y
.bs_bn:
  INY
  INY
  INY
  INY
  INX
  CPX #3
  BNE .bs_bl
  LDA UFO_ON                   ; ---- saucer
  BEQ .bs_nou
  CMP #$03
  BEQ .bs_nou
  LDX #64
  CMP #$01
  BEQ .bs_un
  LDX #68
.bs_un:
  STX SAT_BUFFER+22
  LDA #(UFO_Y-1)
  STA SAT_BUFFER+20
  LDA UFX
  STA SAT_BUFFER+21
  RTS
.bs_nou:
  LDA #HIDE_Y
  STA SAT_BUFFER+20
  RTS

HIDE_SPRITES:
  LDX #20
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
  CPX #25                 ; 6 sprites x 4 bytes + Y=$D0 of the 7th entry
  BNE .copy_sat
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

SAT_BUFFER:
  .byte HIDE_Y,0,0,$02, HIDE_Y,0,12,$0F
  .byte HIDE_Y,0,16,$0F, HIDE_Y,0,32,$0F, HIDE_Y,0,48,$0F
  .byte HIDE_Y,0,64,$08
  .byte $D0


; ===============================================================
;  SOUND: effects only (no music on the cabinet)
;  per chip: A = tone effects / saucer siren, B = noise (explosions),
;  C = notes of the march / tone of the explosions
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
  LDA SND_BEAT                  ; new note of the march
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
  LDA SND_PH                    ; high warble, period 36-66
  AND #$1F
  CMP #$10
  BCC .sf_tri
  EOR #$1F
.sf_tri:
  ASL A
  CLC
  ADC #36
  STA SH_L,Y
  LDA #$00
  STA SH_L+1,Y
  LDA #$08
  STA SH_L+8,Y
.sf_noise:
  ; ---- channels B and C: explosion, otherwise the march
  LDX SND_T1
  LDA EX_ID,X
  BEQ .sf_beat
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
;  PIXEL (con copia in RAM della bitmap e dei colori)
; ===============================================================
; indirizzo cella/riga: T0 = (x & $F8) | (y & 7), T1 = y / 8
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

PLOT_SET:                      ; accende (PX,PY) con colore PCOL
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

PLOT_CLR:                      ; spegne (PX,PY)
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
;  CELLE 8x8 (copia in RAM + VRAM)
; ===============================================================
; da CELLC/CELLR: T0 = col*8, T1 = riga, SPTR = pattern in RAM, PTR2 = colori in RAM
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

; copia la cella (copia in RAM) nella VRAM: richiede CELL_SETUP
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

; disegna il tile a PTR (8 pattern + 8 colori) in (CELLC,CELLR); PTR avanza di 16
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

; A = codice ASCII ($20-$5F), in (CELLC,CELLR) con colore TCOL
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

; A = byte BCD: due cifre, CELLC avanza di 2
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

; record: riga, colonna, colore (fg), caratteri..., 0   (fine lista: riga = $FF)
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

; parole grandi: riga, colonna, n, id lettere... (fine lista: riga = $FF)
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
  STA T7                       ; numero di lettere
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



; riga di inizio in A, numero di righe in X: azzera i pattern, colori = CLRCOL
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


; name table: tile = posizione (0-255 in ognuno dei 3 terzi) => bitmap piena
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
                               ;R4: pattern $0000 | R5: SAT $3B00 | R6: sprite pattern $1800 | R7: sfondo nero


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

SND_CLEAR_SH:                   ; tutti i registri shadow a 0
  LDX #10
  LDA #$00
.cs_l:
  STA SH_L,X
  STA SH_R,X
  DEX
  BPL .cs_l
  RTS

; modalita' gioco: silenzio, mixer = tono A + rumore B + tono C
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

; scrive i registri 0-10 dei due shadow sui due AY
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
SFX_WHISTLE:                    ; A = id fischio (W_*), X = pan
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

SB_SET:                         ; X = chip, SMT0 = id esplosione
  LDA EX_ID,X
  CMP #S_BIG
  BNE .sbs_set
  LDA SMT0                      ; un botto piccolo non interrompe uno grande
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
ROW_TYPE:     .byte 2,2,1,1,0          ; rows from the bottom: octopus, octopus, crab, crab, squid
TYPE_PTS:     .byte $30,$20,$10        ; squid, crab, octopus (BCD)
SHIFT24:      .byte 0,24,48,72         ; 0/2/4/6 pixel versions of a shape
SHAPE_LO:     .byte <(INV_SHAPES+0*96),<(INV_SHAPES+1*96),<(INV_SHAPES+2*96),<(INV_SHAPES+3*96),<(INV_SHAPES+4*96),<(INV_SHAPES+5*96),<INV_BOOM
SHAPE_HI:     .byte >(INV_SHAPES+0*96),>(INV_SHAPES+1*96),>(INV_SHAPES+2*96),>(INV_SHAPES+3*96),>(INV_SHAPES+4*96),>(INV_SHAPES+5*96),>INV_BOOM
SCORE_COL:    .byte 2,24               ; score of player 1 / 2 (row 1)
RELOAD_SC:    .byte $02,$10,$20,$30    ; score (BCD hundreds): 200, 1000, 2000, 3000
RELOAD_T:     .byte 48,16,11,8,7       ; frames between two bombs
PLUNGER_COLS: .byte 0,6,0,0,0,3,10,0,5,2,0,0,10,8,1,7
SQUIG_COLS:   .byte 10,0,5,2,0,0,10,8,1,7,1,10,3,6,9,5
UFO_SEQ:      .byte 1,0,0,1,2,1,1,3,1,1,1,0,2,1,0   ; points of the saucer by shot number (mod 15)
UFO_PL:       .byte $50,$00,$50,$00    ; 50, 100, 150, 300 (BCD)
UFO_PM:       .byte $00,$01,$01,$03
SAVEB_HI:     .byte >SAVE_B0,>SAVE_B1
SAVES_HI:     .byte >SAVE_S0,>SAVE_S1
ZERO8:        .byte 0,0,0,0,0,0,0,0

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_HUD:
  .byte 0,1,15,"SCORE<1>",0
  .byte 0,12,15,"HI-SCORE",0
  .byte 0,23,15,"SCORE<2>",0
  .byte 23,22,2,"CREDIT 00",0
  .byte $FF
TXT_TITLE:
  .byte 4,14,15,"PLAY",0
  .byte 6,9,15,"SPACE INVADERS",0
  .byte 9,5,15,"*SCORE ADVANCE TABLE*",0
  .byte 11,13,15,"=? MYSTERY",0
  .byte 13,13,15,"=30 POINTS",0
  .byte 15,13,15,"=20 POINTS",0
  .byte 17,13,15,"=10 POINTS",0
  .byte 20,6,2,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,2,"BUTTON 2 = 2 PLAYERS",0
  .byte $FF
TXT_PLAY:
  .byte 12,9,15,"PLAY PLAYER<",0
  .byte 12,22,15,">",0
  .byte $FF
TXT_NOPLAY:
  .byte 12,9,15,"              ",0
  .byte $FF
TXT_OVER:
  .byte 3,11,8,"GAME OVER",0
  .byte 21,9,2,"PRESS A BUTTON",0
  .byte $FF
TXT_UFOPTS:                    ; 4 bytes each
  .byte " 50",0,"100",0,"150",0,"300",0
TXT_UFOCLR:
  .byte "   ",0

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
BIGFONT:                ; not used

; invaders 16x8 (squid, crab, octopus) x 2 frames, then the explosion;
; each: 4 versions shifted by 0/2/4/6 pixels, 3 cells x 8 lines (24 bytes)
INV_SHAPES:
  .byte $01,$03,$07,$0D,$0F,$02,$05,$0A,$80,$C0,$E0,$B0,$F0,$40,$A0,$50
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$00,$01,$02
  .byte $60,$F0,$F8,$6C,$FC,$90,$68,$94,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$18,$3C,$7E,$DB,$FF,$24,$5A,$A5
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $06,$0F,$1F,$36,$3F,$09,$16,$29,$00,$00,$80,$C0,$C0,$00,$80,$40
  .byte $01,$03,$07,$0D,$0F,$05,$08,$04,$80,$C0,$E0,$B0,$F0,$A0,$10,$20
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$01,$02,$01
  .byte $60,$F0,$F8,$6C,$FC,$68,$04,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$18,$3C,$7E,$DB,$FF,$5A,$81,$42
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $06,$0F,$1F,$36,$3F,$16,$20,$10,$00,$00,$80,$C0,$C0,$80,$40,$80
  .byte $08,$04,$0F,$1B,$3F,$2F,$28,$06,$20,$40,$E0,$B0,$F8,$E8,$28,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$03,$06,$0F,$0B,$0A,$01
  .byte $08,$10,$F8,$EC,$FE,$FA,$0A,$B0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$03,$02,$02,$00,$82,$44,$FE,$BB,$FF,$FE,$82,$6C
  .byte $00,$00,$00,$00,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$11,$3F,$6E,$FF,$BF,$A0,$1B,$80,$00,$80,$C0,$E0,$A0,$A0,$00
  .byte $08,$24,$2F,$3B,$3F,$1F,$08,$10,$20,$48,$E8,$B8,$F8,$F0,$20,$10
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$09,$0B,$0E,$0F,$07,$02,$04
  .byte $08,$12,$FA,$EE,$FE,$FC,$08,$04,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$02,$03,$03,$01,$00,$01,$82,$44,$FE,$BB,$FF,$FF,$82,$01
  .byte $00,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$91,$BF,$EE,$FF,$7F,$20,$40,$80,$20,$A0,$E0,$E0,$C0,$80,$40
  .byte $03,$1F,$3F,$39,$3F,$06,$0D,$30,$C0,$F8,$FC,$9C,$FC,$60,$B0,$0C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$0F,$0E,$0F,$01,$03,$0C
  .byte $F0,$FE,$FF,$67,$FF,$98,$6C,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$03,$03,$03,$00,$00,$03,$3C,$FF,$FF,$99,$FF,$66,$DB,$00
  .byte $00,$80,$C0,$C0,$C0,$00,$00,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $0F,$7F,$FF,$E6,$FF,$19,$36,$C0,$00,$E0,$F0,$70,$F0,$80,$C0,$30
  .byte $03,$1F,$3F,$39,$3F,$0E,$19,$0C,$C0,$F8,$FC,$9C,$FC,$70,$98,$30
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$0F,$0E,$0F,$03,$06,$03
  .byte $F0,$FE,$FF,$67,$FF,$9C,$66,$0C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$03,$03,$03,$00,$01,$00,$3C,$FF,$FF,$99,$FF,$E7,$99,$C3
  .byte $00,$80,$C0,$C0,$C0,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $0F,$7F,$FF,$E6,$FF,$39,$66,$30,$00,$E0,$F0,$70,$F0,$C0,$60,$C0
INV_BOOM:
  .byte $04,$22,$10,$08,$60,$08,$14,$24,$40,$88,$10,$20,$0C,$20,$50,$48
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$08,$04,$02,$18,$02,$05,$09
  .byte $10,$A2,$04,$08,$03,$08,$14,$12,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$01,$00,$06,$00,$01,$02,$44,$28,$01,$82,$00,$82,$45,$44
  .byte $00,$80,$00,$00,$C0,$00,$00,$80,$00,$00,$00,$00,$01,$00,$00,$00
  .byte $11,$8A,$40,$20,$80,$20,$51,$91,$00,$20,$40,$80,$30,$80,$40,$20

; shield 24x16: upper and lower cell row, 3 cells x 8 lines each
SHIELD_TOP:
  .byte $07,$0F,$1F,$3F,$7F,$7F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $E0,$F0,$F8,$FC,$FE,$FE,$FE,$FE
SHIELD_BOT:
  .byte $7F,$7F,$7F,$7F,$7F,$7E,$7C,$7C,$FF,$FF,$FF,$FF,$00,$00,$00,$00
  .byte $FE,$FE,$FE,$FE,$FE,$7E,$3E,$3E

; spare cannon for the lives row (2 cells)
LIFE_ICON:
  .byte $02,$07,$07,$7F,$FF,$FF,$FF,$FF,$00,$00,$00,$F0,$F8,$F8,$F8,$F8

; erosion of the shields: shot explosion and bomb explosion (8x8, 1 = pixel removed)
SHOT_MASK:
  .byte $89,$22,$7E,$FF,$FF,$7E,$24,$91
BOMB_MASK:
  .byte $44,$28,$7C,$FC,$78,$B4,$28,$44

; sprites 16x16: cannon, 2 cannon explosions, shot, bombs (rolling, plunger, squiggly x 4 frames), saucer, saucer hit
SPR_PAGES = 3
SPRITES:
  .byte $02,$07,$07,$7F,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$F0,$F8,$F8,$F8,$F8,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$10,$14,$03,$5F,$3F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$90,$40,$80,$40,$E0,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$08,$13,$1B,$3F,$6F,$3F,$7F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $10,$40,$00,$A0,$80,$60,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$80,$40,$20,$40,$80,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$40,$40,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$20,$40,$80,$40,$20,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$40,$40,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$40,$40,$40,$40,$40,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$40,$E0,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$40,$40,$40,$E0,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E0,$40,$40,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$80,$40,$20,$40,$80,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$40,$80,$40,$20,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$20,$40,$80,$40,$20,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$40,$20,$40,$80,$40,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$1F,$3F,$6D,$FF,$39,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E0,$F8,$FC,$B6,$FF,$9C,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $94,$40,$1B,$BF,$3F,$9A,$50,$92,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $94,$09,$D8,$FD,$FC,$58,$0A,$49,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $00,$2D,$30,$34,$39,$3F,$45,$4E,$59,$68,$7D,$23,$24,$26,$28,$2A
  .byte $2D,$30,$33,$37,$3B,$40,$45,$23,$24,$26,$28,$2A,$2D,$30,$33,$37
  .byte $3B,$40,$45,$23,$24,$26,$28,$2A,$2D,$30,$33,$37,$3B,$40,$45,$23
  .byte $24,$26,$28,$2A,$2D,$30,$33,$37,$3B,$40,$45,$28,$28,$28,$28,$28
  .byte $28,$00,$00,$00,$28,$28,$28,$28,$28,$28,$00,$00,$00,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$0C,$0C,$0C,$0B,$0B
  .byte $0B,$0B,$0B,$0B,$0A,$0A,$0A,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$09
  .byte $08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$0D,$0C,$0C,$0B,$0B
  .byte $0A,$00,$00,$00,$0D,$0C,$0C,$0B,$0B,$0A,$00,$00,$00,$0D,$0C,$0B
  .byte $0B,$0A,$09,$08,$07,$06,$06,$05,$04
WH_START:
  .byte $00,$01,$0B,$3B
WH_LEN:
  .byte $00,$0A,$30,$1E
W_SHOT = 1
W_UFOHIT = 2
W_EXTRA = 3

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00
  .byte $00
EX_NP:
  .byte $00,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06
  .byte $06,$10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$13,$13,$13
  .byte $13,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15
  .byte $15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17
  .byte $17
EX_VC:
  .byte $00,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00
  .byte $00,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05
  .byte $05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00
EX_TL:
  .byte $00,$68,$6D,$72,$77,$7D,$84,$8B,$93,$9C,$A7,$B3,$C0,$D0,$E3,$FA
  .byte $16,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03
EX_START:
  .byte $00,$01,$11
EX_LEN:
  .byte $00,$10,$40
S_ALIEN = 1
S_PLAYER = 2
S_BIG = S_PLAYER

; march: four low notes going down (period), volume envelope per frame
BEAT_TL:    .byte $38,$7E,$CE,$FA
BEAT_TH:    .byte $02,$02,$02,$02
BEAT_ENV:
  .byte $0F,$0F,$0E,$0D,$0B,$09,$06,$03,$00
BEAT_LEN = 9
