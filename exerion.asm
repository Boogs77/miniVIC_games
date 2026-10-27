;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_EXERION  -  Jaleco Exerion (1983)                   ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: moon cresta (VDP, NMI + trampoline $0FD0, AY engine, ;
;   2 players taking turns) and lunar lander (8.8 inertia)     ;
;                                                              ;
;   - the fighter flies over a planet: the ground rushes       ;
;     towards you in bands (their colours are rewritten every  ;
;     frame, line by line) and the landscape on the horizon    ;
;     moves the other way when you steer (parallax)            ;
;   - joystick = 8 directions with inertia; button 1 = DUAL    ;
;     shot (unlimited, one pair at a time), button 2 (hold) =  ;
;     SINGLE rapid fire: every shot uses one CHARGE; every     ;
;     enemy hit by the dual shot gives one charge back         ;
;   - 4 landscapes (mountains, grassland, future city, ruins), ;
;     each with its enemies coming from the horizon in 5       ;
;     formations of 8: amoebae 100, birds 150 (they throw      ;
;     eggs), pterosaurs 200, UFOs 300. Destroy a whole         ;
;     formation for the BONUS: 200, doubled every time up to   ;
;     10000; every shot that misses halves it                  ;
;   - after every stage the CHALLENGING STAGE: 40 aliens,      ;
;     they cannot hurt you, shots are free, every hit +1       ;
;     charge, all 40 = 60 charges; sometimes the red hydra     ;
;     (1000)                                                   ;
;   - 3 fighters, one more at 20000 and at 50000; 1 or 2       ;
;     players taking turns (title: button 1 or button 2)       ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     engine hum, the two cannons, dives, eggs, explosions,    ;
;     bonus, start tune, stage jingle, extra fighter           ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
ALIVE       = $32      ; 2 bytes: fighters left to every player (the one flying included)
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
STAGE       = $40      ; ---- block of the player, saved: stage - 1
CHAL        = $41      ;      1 = the challenging stage
FORMN       = $42      ;      formations of the stage already over (0-5)
CHARGE      = $43      ;      shots of the single cannon (0-99)
BONI        = $44      ;      bonus of the formations: index in BON_L / BON_M / BON_H
XLIFE       = $45      ;      extra fighters given (0-2)
PBLOCK      = 6
SCRF        = $48      ; ground: position of the bands (8.8)
SCROLL      = $49
HOFF        = $4A      ; offset of the horizon drawn ($FF = draw it)
THEME       = $4B      ; landscape 0-3
PST         = $4C      ; fighter: 0 flying, 1 exploding, 2 over
PT          = $4D      ; timer of the explosion
SXL         = $4E      ; fighter: centre 8.8
SX          = $4F
SYL         = $50
SY          = $51
SVXL        = $52      ; velocity 8.8 signed
SVXH        = $53
SVYL        = $54
SVYH        = $55
FIRECD      = $56      ; frames before the next single shot
JOYC        = $57      ; both joysticks drive the player playing
JOYP        = $58      ; JOYC of the previous frame
NACT        = $59      ; enemies on the field (or waiting to come)
SPAWNT      = $5A      ; frames before the next formation
FSENT       = $5B      ; formations sent in this turn (next one)
HITS        = $5C      ; challenging stage: hits
SATB        = $5D      ; bytes of the SAT to copy
DIFF        = $5E      ; difficulty 0-3 (one more every 4 stages)
KIND        = $5F      ; enemy of this stage (0-3), 4 = aliens of the challenge

FCNT        = $80      ; 5 bytes: enemies left in every formation of the stage
PTS_L       = $85      ; points to add (BCD)
PTS_M       = $86
PTS_H       = $87
EI          = $88      ; enemy being handled
SI          = $89      ; shot being handled
CNT         = $8A
TX          = $8B
TY          = $8C
HW          = $8D      ; half size of the enemy being hit
FIRSTT      = $8E      ; 1 = first turn of the game: start tune
HYD         = $8F      ; 1 = the hydra came in this challenge
HUDD        = $90      ; 1 = the HUD changed
SPD         = $91      ; speed of the ground (8.8)
SPDH        = $96
SHOTH       = $92      ; this pair of the dual cannon hit something
RR          = $93      ; first enemy in the SAT (turns)
WAITF       = $94
BANT        = $95      ; frames of the bonus message
HROW        = $97      ; horizon: row still to draw (0 = none)
HBUF        = $98      ; 8 bytes: the tiles of one period of the skyline

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

; ---------------- enemies: E_ST 0 free, 1 waiting (formation), 2 flying
NE         = 16
E_ST       = $0300
E_MODE     = $0310       ; M_*
E_K        = $0320       ; kind 0 amoeba, 1 bird, 2 pterosaur, 3 UFO, 4 alien, 5 hydra
E_XL       = $0330       ; centre 8.8
E_X        = $0340
E_YL       = $0350
E_Y        = $0360
E_VXL      = $0370       ; dive: horizontal speed 8.8 signed
E_VXH      = $0380
E_T        = $0390       ; waiting: frames; flying: frames before it fires
E_PH       = $03A0       ; phase of the sway
E_W        = $03B0       ; phase step every frame
E_CX       = $03C0       ; centre of the sway
E_AMP      = $03D0       ; sway: 0, 64, 128 (offset in SINT)
E_F        = $03E0       ; formation (0-4), $FF = none (the hydra)
E_VY       = $03F0       ; dive: falling speed (8.8 low byte, high = 2)

M_APPROACH = 0           ; from the horizon towards the fighter, swaying
M_DIVE     = 1           ; straight at the fighter
M_SWOOP    = 2           ; past the fighter, out at the bottom

; ---------------- shots of the fighter
NS         = 8
S_ON       = $0420       ; 0 free, 1 dual (the pair), 2 single
S_X        = $0428
S_Y        = $0430

; ---------------- shots of the enemies (eggs)
NB         = 6
B_ON       = $0440
B_XL       = $0446
B_X        = $044C
B_YL       = $0452
B_Y        = $0458
B_VXL      = $045E
B_VXH      = $0464

; ---------------- explosions
NX         = 6
X_T        = $0480       ; frames left (0 = free)
X_X        = $0486
X_Y        = $048C

PSAVE      = $04A0       ; 2 x 8 bytes: block of every player
GA         = $0500       ; colours of the two bands for every line of the ground (this landscape)
GB         = $0580
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
SHIP_Y0     = 160        ; the fighter starts here
SX_MIN      = 12
SX_MAX      = 244
SY_MIN      = 120
SY_MAX      = 172
ACC         = $1C        ; inertia of the fighter (8.8)
FRIC        = $0C
VMAX        = $0240
VNEG        = $10000-VMAX
HORIZON_Y   = 64         ; first line of the ground
ENTER_Y     = 62         ; enemies appear here, far away
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
  STA SCRF
  STA SCROLL
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ ALIVE,X
  DEX
  BPL .rs_p
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the scoring table over the moving ground
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  STZ THEME
  JSR SET_THEME
  JSR DRAW_GROUND_LOW          ; ground on rows 17-22
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
  LDX #$00                     ; the enemies of the table (sprites)
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

; one frame of the title: the ground moves
TITLE_FRAME:
  JSR VDP_INT_OFF
  LDA #$C0
  STA SPD
  LDA #2
  STA SPDH
  JSR GROUND_COLOURS
  JSR READ_JOY
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: stage 1, 3 fighters, 50 charges for every player
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
  STZ STAGE
  STZ CHAL
  STZ FORMN
  LDA #50
  STA CHARGE
  STZ BONI
  STZ XLIFE
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER: "PLAYER n" and the stage, then the game
; ===============================================================
TURN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDX CURP
  JSR LOAD_PLAYER
  JSR SET_STAGE
  JSR CLEAR_OBJECTS
  JSR SHIP_RESET
  JSR CLEAR_NT
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
  JSR SHOW_STAGE
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA FIRSTT
  BEQ .ts_jingle
  STZ FIRSTT                   ; the start tune, to the end
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_SCENE
.ts_tune:
  LDA #1
  JSR WAIT_SCENE
  LDA SND_BUSY
  BNE .ts_tune
  BRA .ts_go
.ts_jingle:
  LDA #W_STAGE
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_SCENE
.ts_go:
  JSR VDP_INT_OFF
  JSR CLEAR_BANNER
  JSR VDP_INT_ON
  LDA #30
  STA SPAWNT


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR GROUND_COLOURS
  JSR HORIZON
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  JSR UPDATE_SHIP
  JSR FIRE
  JSR UPDATE_SHOTS
  JSR SEND_FORMATION
  JSR UPDATE_ENEMIES
  JSR UPDATE_EGGS
  JSR SHOT_HITS
  JSR SHIP_HITS
  JSR UPDATE_EXPL
  JSR ENGINE_HUM
  JSR UPDATE_HUD
  JSR BUILD_SAT
  LDA JOYC
  STA JOYP
  JSR VDP_INT_ON
  LDA PST
  CMP #2
  BNE .gl_alive
  JMP LOSE_LIFE
.gl_alive:
  LDA FORMN                    ; the 5 formations are over and the field is empty
  CMP #5
  BCC GAME_LOOP
  LDA NACT
  BNE GAME_LOOP
  LDA PST
  BNE GAME_LOOP
  JMP STAGE_END

; A = frames of the scene going on (ground, horizon, sprites) without the game
WAIT_SCENE:
  STA WAITF
.wsc_l:
  JSR VDP_INT_OFF
  JSR GROUND_COLOURS
  JSR HORIZON
  JSR VDP_INT_ON
  DEC WAITF
  BNE .wsc_l
  RTS


; ===============================================================
;  STAGES
; ===============================================================
; landscape, difficulty and enemies of the stage of the player
SET_STAGE:
  LDA STAGE
  AND #$03
  STA THEME
  STA KIND
  LDA CHAL
  BEQ .ss_n
  LDA #4
  STA KIND
.ss_n:
  LDA STAGE
  LSR A
  LSR A
  CMP #4
  BCC .ss_d
  LDA #3
.ss_d:
  STA DIFF
  LDA FORMN                    ; the formations not over come again
  STA FSENT
  LDX #4
.ss_f:
  STZ FCNT,X
  DEX
  BPL .ss_f
  STZ HITS
  STZ HYD
  LDA #$FF
  STA HOFF
  ; fall into SET_THEME

; the colours of the ground and the skyline of THEME
SET_THEME:
  LDA THEME                    ; colours of the bands: GCA / GCB + theme * 120
  ASL A
  TAX
  LDA GC_OFF,X
  STA PTR
  LDA GC_OFF+1,X
  STA PTR+1
  LDY #(NLINES-1)
.st_c:
  LDA (PTR),Y
  STA GB,Y
  DEY
  CPY #$FF
  BNE .st_c
  LDA PTR
  CLC
  ADC #<(GCA-GCB)
  STA PTR
  LDA PTR+1
  ADC #>(GCA-GCB)
  STA PTR+1
  LDY #(NLINES-1)
.st_a:
  LDA (PTR),Y
  STA GA,Y
  DEY
  CPY #$FF
  BNE .st_a
  LDA THEME                    ; skyline: 64 tiles of pattern and colour (tiles 128-191, third 0)
  ASL A
  ASL A
  TAX
  LDA SKY_SRC,X
  STA PTR
  LDA SKY_SRC+1,X
  STA PTR+1
  LDA #$00
  STA T0
  LDA #($40 | $04)
  STA T1
  STZ T2
  LDA #$02
  STA T3
  PHX
  JSR VCOPY
  PLX
  LDA SKY_SRC+2,X
  STA PTR
  LDA SKY_SRC+3,X
  STA PTR+1
  LDA #$00
  STA T0
  LDA #($40 | $24)
  STA T1
  STZ T2
  LDA #$02
  STA T3
  JMP VCOPY

; the stage is over: the challenge after a stage, the next stage after the challenge
STAGE_END:
  JSR VDP_INT_OFF
  LDA CHAL
  BEQ .se_stage
  LDA #<TXT_RESULT             ; ---- result of the challenge
  STA TP
  LDA #>TXT_RESULT
  STA TP+1
  JSR PRINT
  LDA HITS
  JSR BIN2BCD
  LDX #3
  LDY #18
  JSR PUT_BCD2
  LDA HITS
  CMP #40
  BCC .se_np
  LDA #<TXT_PERFECT            ; all 40: the charges become 60
  STA TP
  LDA #>TXT_PERFECT
  STA TP+1
  JSR PRINT
  LDA CHARGE
  CLC
  ADC #20
  CMP #100
  BCC .se_c
  LDA #99
.se_c:
  STA CHARGE
  LDA #1
  STA HUDD
  LDA #W_CHARGE
  LDX #2
  JSR SFX_WHISTLE
.se_np:
  STZ CHAL
  INC STAGE
  BRA .se_go
.se_stage:
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  LDA #1
  STA CHAL
.se_go:
  STZ FORMN
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #120
  JSR WAIT_SCENE
  LDX CURP
  JSR SAVE_PLAYER
  JMP TURN_START

; banner of the stage on rows 3-4 (in the sky)
SHOW_STAGE:
  LDA CHAL
  BEQ .sh_n
  LDA #<TXT_CHAL
  STA TP
  LDA #>TXT_CHAL
  STA TP+1
  JMP PRINT
.sh_n:
  LDA #<TXT_STAGE
  STA TP
  LDA #>TXT_STAGE
  STA TP+1
  JSR PRINT
  LDA STAGE
  CLC
  ADC #1
  JSR BIN2BCD
  LDX #4
  LDY #18
  JMP PUT_BCD2


; ===============================================================
;  A FIGHTER LOST: the other player, or game over
; ===============================================================
LOSE_LIFE:
  LDX CURP
  DEC ALIVE,X
  JSR SAVE_PLAYER
  LDA NPL                      ; the other player, if he still has fighters
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
  JSR VDP_INT_OFF
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the best score
.go_h:
  LDA SCH,X
  CMP HISC+2
  BCC .go_n
  BNE .go_set
  LDA SCM,X
  CMP HISC+1
  BCC .go_n
  BNE .go_set
  LDA SCL,X
  CMP HISC
  BCC .go_n
  BEQ .go_n
.go_set:
  LDA SCL,X
  STA HISC
  LDA SCM,X
  STA HISC+1
  LDA SCH,X
  STA HISC+2
.go_n:
  INX
  CPX #$02
  BNE .go_h
  JSR HIDE_SPRITES
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_SCENE
  JMP TITLE


; ===============================================================
;  THE FIGHTER: 8 directions with inertia
; ===============================================================
SHIP_RESET:
  LDA #128
  STA SX
  LDA #SHIP_Y0
  STA SY
  STZ SXL
  STZ SYL
  STZ SVXL
  STZ SVXH
  STZ SVYL
  STZ SVYH
  STZ PST
  STZ FIRECD
  LDA #$FF
  STA JOYP
  RTS

UPDATE_SHIP:
  LDA PST
  BEQ .us_fly
  DEC PT                       ; exploding
  BNE .us_r
  LDA #2
  STA PST
.us_r:
  RTS
.us_fly:
  LDA SVXL                     ; ---- horizontal
  STA T0
  LDA SVXH
  STA T1
  LDA JOYC
  AND #%00001100
  JSR AXIS
  LDA T0
  STA SVXL
  LDA T1
  STA SVXH
  LDA SVYL                     ; ---- vertical
  STA T0
  LDA SVYH
  STA T1
  LDA JOYC
  AND #%00000011
  ASL A
  ASL A                        ; up -> bit 2 (minus), down -> bit 3 (plus)
  JSR AXIS
  LDA T0
  STA SVYL
  LDA T1
  STA SVYH
  CLC                          ; ---- move, inside the field
  LDA SXL
  ADC SVXL
  STA SXL
  LDA SX
  ADC SVXH
  STA SX
  CMP #SX_MIN
  BCS .us_x1
  LDA #SX_MIN
  BRA .us_xs
.us_x1:
  CMP #(SX_MAX+1)
  BCC .us_y
  LDA #SX_MAX
.us_xs:
  STA SX
  STZ SVXL
  STZ SVXH
.us_y:
  CLC
  LDA SYL
  ADC SVYL
  STA SYL
  LDA SY
  ADC SVYH
  STA SY
  CMP #SY_MIN
  BCS .us_y1
  LDA #SY_MIN
  BRA .us_ys
.us_y1:
  CMP #(SY_MAX+1)
  BCC .us_spd
  LDA #SY_MAX
.us_ys:
  STA SY
  STZ SVYL
  STZ SVYH
.us_spd:
  LDA #$C0                     ; ---- the ground runs faster when the fighter goes up, slower down
  LDX #2
  LDY SVYH
  BPL .us_s1
  LDA #$80
  LDX #3
  BRA .us_s2
.us_s1:
  LDA SVYL
  ORA SVYH
  BEQ .us_n
  LDA #$00
  LDX #2
  BRA .us_s2
.us_n:
  LDA #$C0
.us_s2:
  STA SPD
  STX SPDH
  RTS

; T0 / T1 = speed 8.8; A bit 3 = push +, bit 2 = push -: accelerate or slow down (keeps nothing)
AXIS:
  STA T2
  AND #%00001000
  BEQ .ax_m
  LDA T2
  AND #%00000100
  BNE .ax_f                    ; both: none
  CLC
  LDA T0
  ADC #ACC
  STA T0
  LDA T1
  ADC #0
  STA T1
  SEC
  LDA T0
  SBC #<VMAX
  LDA T1
  SBC #>VMAX
  BMI .ax_r
  LDA #<VMAX
  STA T0
  LDA #>VMAX
  STA T1
.ax_r:
  RTS
.ax_m:
  LDA T2
  AND #%00000100
  BEQ .ax_f
  SEC
  LDA T0
  SBC #ACC
  STA T0
  LDA T1
  SBC #0
  STA T1
  CLC
  LDA T0
  ADC #<VMAX
  LDA T1
  ADC #>VMAX
  BPL .ax_r
  LDA #<VNEG
  STA T0
  LDA #>VNEG
  STA T1
  RTS
.ax_f:                         ; no push: friction
  LDA T1
  BMI .ax_fn
  SEC
  LDA T0
  SBC #FRIC
  STA T0
  LDA T1
  SBC #0
  STA T1
  BPL .ax_r
  STZ T0
  STZ T1
  RTS
.ax_fn:
  CLC
  LDA T0
  ADC #FRIC
  STA T0
  LDA T1
  ADC #0
  STA T1
  BMI .ax_r
  STZ T0
  STZ T1
  RTS


; ===============================================================
;  THE TWO CANNONS
; ===============================================================
FIRE:
  LDA PST
  BNE .fi_r
  LDA FIRECD
  BEQ .fi_d
  DEC FIRECD
.fi_d:
  LDA JOYC                     ; ---- dual: button 1 pressed now, one pair at a time
  AND #%00010000
  BEQ .fi_s
  LDA JOYP
  AND #%00010000
  BNE .fi_s
  LDX #(NS-1)
.fi_dl:
  LDA S_ON,X
  CMP #1
  BEQ .fi_s                    ; the pair is still flying
  DEX
  BPL .fi_dl
  JSR FREE_SHOT
  BCS .fi_s
  LDA #1
  STA S_ON,X
  LDA SX
  STA S_X,X
  LDA SY
  SEC
  SBC #10
  STA S_Y,X
  STZ SHOTH
  LDA #W_DUAL
  LDX #0
  JSR SFX_WHISTLE
.fi_s:
  LDA JOYC                     ; ---- single: button 2 held
  AND #%00100000
  BEQ .fi_r
  LDA FIRECD
  BNE .fi_r
  LDA CHAL                     ; free in the challenging stage
  BNE .fi_free
  LDA CHARGE
  BEQ .fi_r
.fi_free:
  JSR FREE_SHOT
  BCS .fi_r
  LDA #2
  STA S_ON,X
  LDA SX
  STA S_X,X
  LDA SY
  SEC
  SBC #12
  STA S_Y,X
  LDA #5
  STA FIRECD
  LDA CHAL
  BNE .fi_snd
  DEC CHARGE
  LDA #1
  STA HUDD
.fi_snd:
  LDA #W_SINGLE
  LDX #0
  JMP SFX_WHISTLE
.fi_r:
  RTS

; X = a free shot (carry clear), carry set = none
FREE_SHOT:
  LDX #(NS-1)
.fs_l:
  LDA S_ON,X
  BEQ .fs_f
  DEX
  BPL .fs_l
  SEC
  RTS
.fs_f:
  CLC
  RTS

UPDATE_SHOTS:
  LDX #(NS-1)
.uo_l:
  LDA S_ON,X
  BEQ .uo_n
  LDA S_Y,X
  SEC
  SBC #6
  STA S_Y,X
  CMP #(HORIZON_Y-4)
  BCS .uo_n
  LDA S_ON,X                   ; it reached the horizon: a shot that missed
  STZ S_ON,X
  CMP #1
  BNE .uo_miss
  LDA SHOTH                    ; the pair: a miss only if neither hit
  BNE .uo_n
.uo_miss:
  JSR MISSED
.uo_n:
  DEX
  BPL .uo_l
  RTS

; a shot missed: the bonus is halved (not in the challenge) (keeps X)
MISSED:
  LDA CHAL
  BNE .mi_r
  LDY BONI
  LDA BON_HALF,Y
  CMP BONI
  BEQ .mi_r
  STA BONI
  LDA #1
  STA HUDD
.mi_r:
  RTS


; ===============================================================
;  PLAYERS: save / load the block STAGE-XLIFE
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.sp_b:
  LDA STAGE,X
  STA PSAVE,Y
  INY
  INX
  CPX #PBLOCK
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.lp_b:
  LDA PSAVE,Y
  STA STAGE,X
  INY
  INX
  CPX #PBLOCK
  BNE .lp_b
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a fighter more at 20000 and at 50000
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
  LDY XLIFE
  CPY #2
  BCS .as_d
  LDA SCH,X
  CMP XL_AT,Y
  BCC .as_d
  INC XLIFE
  INC ALIVE,X
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
;  FORMATIONS: 8 enemies on the same path, one after the other
; ===============================================================
CLEAR_OBJECTS:
  LDX #(NE-1)
.co_e:
  STZ E_ST,X
  DEX
  BPL .co_e
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
  STZ BANT
  RTS

SEND_FORMATION:
  LDA FSENT
  CMP #5
  BCS .sf_r
  LDA SPAWNT
  BEQ .sf_go
  DEC SPAWNT
.sf_r:
  RTS
.sf_go:
  LDX #(NE-1)                  ; room for 8?
  STZ CNT
.sf_c:
  LDA E_ST,X
  BNE .sf_cn
  INC CNT
.sf_cn:
  DEX
  BPL .sf_c
  LDA CNT
  CMP #8
  BCS .sf_ok
  LDA #20
  STA SPAWNT
  RTS
.sf_ok:
  LDA STAGE                    ; the path of this formation
  ASL A
  ADC STAGE
  ADC FSENT
  AND #$07
  TAY
  LDX FSENT
  LDA #8
  STA FCNT,X
  STZ CNT
  LDX #(NE-1)
.sf_m:
  LDA E_ST,X
  BNE .sf_mn
  LDA #1
  STA E_ST,X
  STZ E_MODE,X
  LDA KIND
  STA E_K,X
  LDA FSENT
  STA E_F,X
  LDA FP_CX,Y
  STA E_CX,X
  LDA FP_AMP,Y
  STA E_AMP,X
  LDA FP_W,Y
  STA E_W,X
  LDA CHAL                     ; the aliens of the challenge sway faster
  BEQ .sf_w
  INC E_W,X
.sf_w:
  LDA FP_PH,Y
  STA E_PH,X
  LDA CNT                      ; waiting: 1 + member x 10 frames
  ASL A
  STA T0
  ASL A
  ASL A
  CLC
  ADC T0
  INC A
  STA E_T,X
  INC CNT
  LDA CNT
  CMP #8
  BEQ .sf_d
.sf_mn:
  DEX
  BPL .sf_m
.sf_d:
  INC FSENT
  LDA CHAL                     ; the next formation comes even if this one still flies
  BEQ .sf_n
  LDA #110
  BRA .sf_t
.sf_n:
  LDA DIFF
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0
  LDA #200
  SEC
  SBC T0
.sf_t:
  STA SPAWNT
  LDA CHAL                     ; sometimes the red hydra comes in the challenge
  BEQ .sf_r2
  LDA HYD
  BNE .sf_r2
  LDA FSENT
  CMP #3
  BNE .sf_r2
  LDA RND
  AND #$03
  BEQ .sf_r2
  LDX #(NE-1)
.sf_h:
  LDA E_ST,X
  BEQ .sf_hy
  DEX
  BPL .sf_h
.sf_r2:
  RTS
.sf_hy:
  LDA #1
  STA HYD
  STA E_ST,X
  LDA #90
  STA E_T,X
  STZ E_MODE,X
  LDA #5
  STA E_K,X
  LDA #$FF
  STA E_F,X
  LDA #128
  STA E_CX,X
  LDA #128
  STA E_AMP,X
  LDA #2
  STA E_W,X
  STZ E_PH,X
  RTS


; ===============================================================
;  ENEMIES: from the horizon (small) towards the fighter (big)
; ===============================================================
UPDATE_ENEMIES:
  STZ NACT
  LDX #(NE-1)
.ue_l:
  STX EI
  LDA E_ST,X
  BEQ .ue_n
  INC NACT
  CMP #1
  BNE .ue_fly
  DEC E_T,X                    ; waiting for its turn in the formation
  BNE .ue_n
  JSR START_FLY
  BRA .ue_n
.ue_fly:
  JSR MOVE_ENEMY
.ue_n:
  LDX EI
  DEX
  BPL .ue_l
  RTS

; X = enemy: it appears on the horizon
START_FLY:
  LDA #2
  STA E_ST,X
  STZ E_MODE,X
  LDA #ENTER_Y
  STA E_Y,X
  STZ E_YL,X
  STZ E_XL,X
  JSR SWAY_X
  JMP FIRE_TIME

; X = enemy: X from the centre and the phase of the sway
SWAY_X:
  LDA E_PH,X
  LSR A
  LSR A
  AND #$3F
  CLC
  ADC E_AMP,X
  TAY
  LDA SINT,Y
  BMI .sx_neg
  CLC
  ADC E_CX,X
  BCC .sx_s
  LDA #250
  BRA .sx_s
.sx_neg:
  CLC
  ADC E_CX,X
  BCS .sx_s
  LDA #6
.sx_s:
  STA E_X,X
  RTS

; X = enemy: frames before it fires
FIRE_TIME:
  LDA RND
  AND #$3F
  CLC
  ADC #30
  LDY E_K,X
  CPY #1
  BNE .ft_s
  LSR A                        ; birds throw eggs twice as often
.ft_s:
  STA E_T,X
  RTS

; X = enemy flying
MOVE_ENEMY:
  LDA E_MODE,X
  CMP #M_DIVE
  BNE .me_ns
  JMP DIVE
.me_ns:
  CMP #M_SWOOP
  BNE .me_app
  JMP SWOOP
.me_app:                       ; ---- approach: sway and come nearer
  LDA E_PH,X
  CLC
  ADC E_W,X
  STA E_PH,X
  JSR SWAY_X
  LDA E_Y,X
  LSR A
  LSR A
  LSR A
  TAY
  LDA DIFF                     ; faster in the later stages
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC APP_L,Y
  STA T0
  LDA APP_H,Y
  ADC #0
  STA T1
  CLC
  LDA E_YL,X
  ADC T0
  STA E_YL,X
  LDA E_Y,X
  ADC T1
  STA E_Y,X
  JSR ENEMY_FIRE
  LDA E_Y,X                    ; near enough: dive at the fighter or swoop past it
  CMP #118
  BCC .me_r
  LDY E_K,X
  CPY #4
  BCS .me_sw                   ; aliens and the hydra never dive
  LDA RND
  AND #$03
  CMP DIVE_P,Y
  BCS .me_sw
  LDA #M_DIVE
  STA E_MODE,X
  STZ E_VXL,X
  STZ E_VXH,X
  LDA DIFF
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA E_VY,X                   ; falling at 2 + difficulty / 8 pixels per frame
  LDA RND
  AND #$01
  BEQ .me_r
  LDA #W_DIVE
  PHX
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS
.me_sw:
  LDA #M_SWOOP                 ; it turns out, away from the fighter
  STA E_MODE,X
  STZ E_VXL,X
  STZ E_VXH,X
  LDA SX
  LDY CHAL
  BEQ .me_d
  LDA #128                     ; the aliens of the challenge: away from the middle
.me_d:
  CMP E_X,X
  LDA #0
  BCC .me_dr
  LDA #1
.me_dr:
  STA E_VY,X
.me_r:
  RTS

; X = enemy swooping past the fighter: it turns towards one side and leaves the screen there
SWOOP:
  LDA E_VXL,X
  STA T0
  LDA E_VXH,X
  STA T1
  LDA #$12
  STA T2
  LDA #$00
  STA T3
  LDA #$03
  STA T4
  LDA E_VY,X                   ; 1 = to the left
  LSR A
  JSR ACCEL16
  LDA T0
  STA E_VXL,X
  LDA T1
  STA E_VXH,X
  LDA E_X,X
  STA T5
  CLC
  LDA E_XL,X
  ADC E_VXL,X
  STA E_XL,X
  LDA E_X,X
  ADC E_VXH,X
  STA E_X,X
  LDA E_VY,X                   ; out of a side of the screen?
  BNE .sw_l
  LDA E_X,X
  CMP T5
  BCC .sw_bk
  CMP #250
  BCS .sw_bk
  BRA .sw_y
.sw_l:
  LDA E_X,X
  CMP T5
  BEQ .sw_y
  BCS .sw_bk
  CMP #6
  BCS .sw_y
.sw_bk:
  JMP ENEMY_BACK
.sw_y:
  CLC                          ; still coming nearer, slowly
  LDA E_YL,X
  ADC #$90
  STA E_YL,X
  LDA E_Y,X
  ADC #0
  STA E_Y,X
  JMP CHECK_OUT

; X = enemy diving at the fighter
DIVE:
  LDA E_VXL,X                  ; the horizontal speed turns towards the fighter
  STA T0
  LDA E_VXH,X
  STA T1
  LDA DIFF                     ; step $0C + 4 x difficulty, top speed 1.5 + difficulty / 8
  ASL A
  ASL A
  ADC #$0C
  STA T2
  LDA DIFF
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ADC #$80
  STA T3
  LDA #$01
  STA T4
  LDA SX
  SEC
  SBC E_X,X
  ASL A                        ; carry = the fighter is on the left
  JSR ACCEL16
  LDA T0
  STA E_VXL,X
  LDA T1
  STA E_VXH,X
  CLC
  LDA E_XL,X
  ADC E_VXL,X
  STA E_XL,X
  LDA E_X,X
  ADC E_VXH,X
  STA E_X,X
  CLC                          ; falling at 2 pixels + E_VY / 256
  LDA E_YL,X
  ADC E_VY,X
  STA E_YL,X
  LDA E_Y,X
  ADC #2
  STA E_Y,X
  ; fall into CHECK_OUT

; X = enemy: out at the bottom? It comes back from the horizon (it leaves in the challenge)
CHECK_OUT:
  LDA E_Y,X
  CMP #192
  BCS ENEMY_BACK
  RTS

; X = enemy out of the screen: back on the horizon (gone in the challenge)
ENEMY_BACK:
  LDA CHAL
  BNE .co_gone
  LDA E_K,X
  CMP #4
  BCS .co_gone
  STZ E_MODE,X                 ; again from the horizon, somewhere else
  LDA #ENTER_Y
  STA E_Y,X
  STZ E_YL,X
  LDA RND
  AND #$7F
  CLC
  ADC #64
  STA E_CX,X
  LDA RND
  STA E_PH,X
  AND #$C0
  CMP #$C0
  BNE .co_a
  LDA #$80
.co_a:
  LSR A                        ; 0, 32, 64... -> 0, 64, 128 of SINT
  STA E_AMP,X
  ASL E_AMP,X
  JSR SWAY_X
  JMP FIRE_TIME
.co_gone:
  STZ E_ST,X                   ; it escaped
  JMP FORM_MINUS

; T0 / T1 = speed 8.8 signed, T2 = step, T3 / T4 = top speed;
; carry clear = faster to the right, set = to the left
ACCEL16:
  BCS .ac_neg
  CLC
  LDA T0
  ADC T2
  STA T0
  LDA T1
  ADC #0
  STA T1
  SEC
  LDA T0
  SBC T3
  LDA T1
  SBC T4
  BMI .ac_r
  LDA T3
  STA T0
  LDA T4
  STA T1
.ac_r:
  RTS
.ac_neg:
  SEC
  LDA T0
  SBC T2
  STA T0
  LDA T1
  SBC #0
  STA T1
  CLC
  LDA T0
  ADC T3
  LDA T1
  ADC T4
  BPL .ac_r
  SEC
  LDA #0
  SBC T3
  STA T0
  LDA #0
  SBC T4
  STA T1
  RTS


; ===============================================================
;  EGGS AND SHOTS OF THE ENEMIES
; ===============================================================
; X = enemy approaching: when its clock runs out it fires at the fighter
ENEMY_FIRE:
  LDA CHAL
  BNE .ef_r
  LDY E_K,X
  CPY #1
  BEQ .ef_go                   ; birds always throw eggs
  LDA DIFF
  BEQ .ef_r                    ; the others from the second round of landscapes
.ef_go:
  DEC E_T,X
  BNE .ef_r
  JSR FIRE_TIME
  LDA E_Y,X
  CMP #76
  BCC .ef_r
  CMP #140
  BCS .ef_r
  LDA PST
  BNE .ef_r
  LDY #(NB-1)
.ef_f:
  LDA B_ON,Y
  BEQ .ef_new
  DEY
  BPL .ef_f
.ef_r:
  RTS
.ef_new:
  LDA #1
  STA B_ON,Y
  LDA E_X,X
  STA B_X,Y
  LDA E_Y,X
  CLC
  ADC #4
  STA B_Y,Y
  LDA #0
  STA B_XL,Y
  STA B_YL,Y
  STA T1
  LDA SX                       ; aimed: dx / 64 pixels per frame
  SEC
  SBC E_X,X
  STA T0
  BPL .ef_p
  DEC T1
.ef_p:
  ASL T0
  ROL T1
  ASL T0
  ROL T1
  LDA T0
  STA B_VXL,Y
  LDA T1
  STA B_VXH,Y
  PHX
  LDA #W_EGG
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS

UPDATE_EGGS:
  LDX #(NB-1)
.ug_l:
  LDA B_ON,X
  BEQ .ug_n
  CLC
  LDA B_XL,X
  ADC B_VXL,X
  STA B_XL,X
  LDA B_X,X
  ADC B_VXH,X
  STA B_X,X
  CLC
  LDA B_YL,X
  ADC #$40
  STA B_YL,X
  LDA B_Y,X
  ADC #2
  STA B_Y,X
  CMP #190
  BCC .ug_n
  STZ B_ON,X
.ug_n:
  DEX
  BPL .ug_l
  RTS


; ===============================================================
;  HITS
; ===============================================================
; X = enemy: HW = half its size (it grows as it comes nearer)
ENEMY_SIZE:
  LDA E_K,X
  CMP #5
  BEQ .es_big
  LDA E_Y,X
  CMP #96
  BCC .es_s
  CMP #132
  BCC .es_m
.es_big:
  LDA #7
  BRA .es_e
.es_m:
  LDA #5
  BRA .es_e
.es_s:
  LDA #3
.es_e:
  STA HW
  RTS

SHOT_HITS:
  LDX #(NS-1)
.sh_l:
  STX SI
  LDA S_ON,X
  BEQ .sh_n
  LDA S_X,X
  STA TX
  LDA S_Y,X
  STA TY
  LDA #1                       ; the pair is wider
  LDY S_ON,X
  CPY #1
  BNE .sh_w
  LDA #6
.sh_w:
  STA T6
  LDX #(NE-1)
.sh_e:
  LDA E_ST,X
  CMP #2
  BNE .sh_en
  LDA TY                       ; quick test: near enough in height and across?
  SEC
  SBC E_Y,X
  BPL .sh_y
  EOR #$FF
  INC A
.sh_y:
  CMP #11
  BCS .sh_en
  STA T5
  LDA TX
  SEC
  SBC E_X,X
  BPL .sh_x
  EOR #$FF
  INC A
.sh_x:
  CMP #14
  BCS .sh_en
  SEC                          ; then with the size of the enemy
  SBC T6
  BCC .sh_xin
  STA T4
  JSR ENEMY_SIZE
  LDA T4
  CMP HW
  BCS .sh_en
  BRA .sh_yin
.sh_xin:
  JSR ENEMY_SIZE
.sh_yin:
  LDA T5
  SEC
  SBC #3
  BCC .sh_hit
  CMP HW
  BCS .sh_en
.sh_hit:
  LDY SI                       ; ---- hit
  LDA S_ON,Y
  STA T7
  LDA #0
  STA S_ON,Y
  LDA T7
  CMP #1
  BNE .sh_k
  LDA #1
  STA SHOTH
.sh_k:
  JSR KILL_ENEMY
  BRA .sh_n
.sh_en:
  DEX
  BPL .sh_e
.sh_n:
  LDX SI
  DEX
  BMI .sh_r
  JMP .sh_l
.sh_r:
  RTS

; X = enemy hit, T7 = by the dual (1) or the single (2) cannon
KILL_ENEMY:
  LDY E_K,X
  LDA EN_PL,Y
  STA PTS_L
  LDA EN_PM,Y
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  LDA CHAL                     ; the charges: +1 for the dual cannon, +1 for any hit in the challenge
  BNE .ke_c
  LDA T7
  CMP #1
  BNE .ke_ex
.ke_c:
  LDA CHARGE
  CMP #99
  BCS .ke_h
  INC CHARGE
.ke_h:
  LDA CHAL
  BEQ .ke_ex
  LDA E_K,X
  CMP #5
  BEQ .ke_ex
  INC HITS
.ke_ex:
  LDA E_X,X
  STA T0
  LDA E_Y,X
  STA T1
  JSR NEW_EXPL
  LDA #S_SMALL
  LDY E_X,X
  PHX
  JSR BOOM_AT
  PLX
  STZ E_ST,X
  ; fall into FORM_MINUS

; X = enemy gone: one less in its formation; the whole formation gone = bonus (keeps X)
FORM_MINUS:
  LDY E_F,X
  CPY #$FF
  BEQ .fm_r
  LDA FCNT,Y
  BEQ .fm_r
  SEC
  SBC #1
  STA FCNT,Y
  BNE .fm_r
  INC FORMN
  LDA CHAL
  BNE .fm_r
  LDY BONI                     ; ---- the formation bonus, then it doubles
  LDA BON_L,Y
  STA PTS_L
  LDA BON_M,Y
  STA PTS_M
  LDA BON_H,Y
  STA PTS_H
  JSR ADD_SCORE
  JSR SHOW_BONUS
  LDY BONI
  LDA BON_DBL,Y
  STA BONI
  PHX
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  PLX
.fm_r:
  RTS

; enemies and eggs that touch the fighter (not in the challenge)
SHIP_HITS:
  LDA PST
  BNE .sx_r
  LDA CHAL
  BNE .sx_r
  LDX #(NE-1)
.sx_e:
  LDA E_ST,X
  CMP #2
  BNE .sx_en
  LDA E_Y,X
  CMP #100
  BCC .sx_en
  JSR ENEMY_SIZE
  LDA HW
  CLC
  ADC #4
  STA T6
  LDA SX
  SEC
  SBC E_X,X
  BPL .sx_x
  EOR #$FF
  INC A
.sx_x:
  CMP T6
  BCS .sx_en
  DEC T6
  LDA SY
  SEC
  SBC E_Y,X
  BPL .sx_y
  EOR #$FF
  INC A
.sx_y:
  CMP T6
  BCS .sx_en
  LDA #2                       ; rammed: both explode
  STA T7
  JSR KILL_ENEMY
  JMP SHIP_DIE
.sx_en:
  DEX
  BPL .sx_e
  LDX #(NB-1)
.sx_b:
  LDA B_ON,X
  BEQ .sx_bn
  LDA SX
  SEC
  SBC B_X,X
  BPL .sx_bx
  EOR #$FF
  INC A
.sx_bx:
  CMP #6
  BCS .sx_bn
  LDA SY
  SEC
  SBC B_Y,X
  BPL .sx_by
  EOR #$FF
  INC A
.sx_by:
  CMP #7
  BCS .sx_bn
  STZ B_ON,X
  JMP SHIP_DIE
.sx_bn:
  DEX
  BPL .sx_b
.sx_r:
  RTS

SHIP_DIE:
  LDA #1
  STA PST
  LDA #100
  STA PT
  LDA #S_BIG
  LDX #2
  JMP SFX_BOOM


; ===============================================================
;  EXPLOSIONS, ENGINE
; ===============================================================
; T0 / T1 = where (keeps X)
NEW_EXPL:
  PHX
  LDX #(NX-1)
.nx_l:
  LDA X_T,X
  BEQ .nx_f
  DEX
  BPL .nx_l
  PLX
  RTS
.nx_f:
  LDA #24
  STA X_T,X
  LDA T0
  STA X_X,X
  LDA T1
  STA X_Y,X
  PLX
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
  LDA BANT                     ; the bonus message goes away
  BEQ .ux_r
  DEC BANT
  BNE .ux_r
  JMP CLEAR_BANNER
.ux_r:
  RTS

; the hum of the engine, on the right chip when it is free
ENGINE_HUM:
  LDA PST
  BNE .eh_r
  LDA WH_ID+1
  BNE .eh_r
  LDA #W_HUM
  LDX #1
  JMP SFX_WHISTLE
.eh_r:
  RTS


; ===============================================================
;  SPRITES: fighter first, then its shots, the enemies in an
;  order that turns every frame (with more than 4 on a line they
;  flicker instead of disappearing), the eggs and the explosions
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA SX
  STA OX
  LDA SY
  STA OY
  LDA PST
  BEQ .bs_ship
  CMP #1
  BNE .bs_shots
  LDA PT                       ; the fighter explodes
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #3
  BCC .bs_x1
  LDA #2
.bs_x1:
  EOR #$FF
  CLC
  ADC #3
  TAY
  LDA EXPL_N,Y
  STA ON
  LDA EXPL_C,Y
  STA OC
  JSR ADD_SPR
  BRA .bs_shots
.bs_ship:
  LDY #0                       ; banking with the horizontal speed
  LDA SVXH
  BPL .bs_r
  CMP #$FF
  BNE .bs_l
  LDA SVXL
  CMP #$80
  BCS .bs_f
.bs_l:
  LDY #1
  BRA .bs_f
.bs_r:
  BNE .bs_rr
  LDA SVXL
  CMP #$80
  BCC .bs_f
.bs_rr:
  LDY #2
.bs_f:
  TYA
  ASL A
  ASL A
  STA T7
  CLC
  ADC #PT_SHIPD
  STA ON
  LDA #$08
  STA OC
  JSR ADD_SPR
  LDA T7
  CLC
  ADC #PT_SHIP
  STA ON
  LDA #$0F
  STA OC
  JSR ADD_SPR
.bs_shots:
  LDX #(NS-1)
.bs_s:
  LDA S_ON,X
  BEQ .bs_sn
  LDY #PT_SINGLE
  LDA #$0F
  STA OC
  LDA S_ON,X
  CMP #1
  BNE .bs_sp
  LDY #PT_DUAL
  LDA #$0B
  STA OC
.bs_sp:
  STY ON
  LDA S_X,X
  STA OX
  LDA S_Y,X
  STA OY
  PHX
  JSR ADD_SPR
  PLX
.bs_sn:
  DEX
  BPL .bs_s
  LDA FRAME_CNT                ; enemies, turning order
  AND #$0F
  STA RR
  LDY #0
.bs_e:
  STY CNT
  TYA
  CLC
  ADC RR
  AND #$0F
  TAX
  LDA E_ST,X
  CMP #2
  BNE .bs_en
  JSR ENEMY_SPR
  JSR ADD_SPR
.bs_en:
  LDY CNT
  INY
  CPY #NE
  BNE .bs_e
  LDX #(NB-1)                  ; eggs
.bs_b:
  LDA B_ON,X
  BEQ .bs_bn
  LDA B_X,X
  STA OX
  LDA B_Y,X
  STA OY
  LDA #PT_EGG
  STA ON
  LDA #$0B
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.bs_bn:
  DEX
  BPL .bs_b
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

; X = enemy: OX, OY, ON, OC (size by its distance, two frames)
ENEMY_SPR:
  LDA E_X,X
  STA OX
  LDA E_Y,X
  STA OY
  TXA                          ; frame: every enemy at its own pace
  ASL A
  ASL A
  ADC FRAME_CNT
  AND #$08
  LSR A
  STA T7                       ; 0 / 4
  LDY E_K,X
  LDA EN_COL,Y
  STA OC
  CPY #5
  BNE .sp_n
  LDA #PT_HYDRA
  CLC
  ADC T7
  STA ON
  RTS
.sp_n:
  LDA EN_BASE,Y
  CLC
  ADC T7
  STA T7
  LDA E_Y,X                    ; far, middle, near
  LDY #0
  CMP #96
  BCC .sp_s
  LDY #8
  CMP #132
  BCC .sp_s
  LDY #16
.sp_s:
  TYA
  CLC
  ADC T7
  STA ON
  RTS


; ===============================================================
;  THE GROUND: one tile per row, all the same along the row; the
;  bands are the colours of its 8 lines, rewritten every frame:
;  line i is in band A when bit 5 of (DEPTH(i) + SCROLL) is set
; ===============================================================
GROUND_COLOURS:
  CLC
  LDA SCRF
  ADC SPD
  STA SCRF
  LDA SCROLL
  ADC SPDH
  STA SCROLL
  LDA FRAME_CNT                ; the far lines move slowly: half of them in every frame
  AND #$01
  BNE .gc_odd
  LDA #$00                     ; lines 0-29
  LDX #0
  LDY #30
  BRA .gc_far
.gc_odd:
  LDA #30                      ; lines 30-59
  LDX #30
  LDY #60
.gc_far:
  JSR GC_RUN3
  LDA #60                      ; lines 60-63 (third 1)
  LDX #60
  LDY #64
  JSR GC_RUN3
  LDA #$00                     ; lines 64-119 (third 2)
  STA VREG
  LDA #($40 | $34)
  STA VREG
  LDY #NLINES
  BRA GC_RUN

; colours of lines X to Y-1 of the third 1, A = first line
GC_RUN3:
  STA VREG
  LDA #($40 | $2C)
  STA VREG
  ; fall into GC_RUN

; lines X to Y-1: band A or band B by bit 5 of (DEPTH + SCROLL)
GC_RUN:
  STY T0
  CLC
.gr_l:
  LDA DEPTH,X
  ADC SCROLL
  AND #$20
  BEQ .gr_b
  LDA GA,X
  BRA .gr_w
.gr_b:
  LDA GB,X
.gr_w:
  STA VDATA
  INX
  CPX T0
  BNE .gr_l
  RTS

; the skyline on rows 6-7 moves the other way when the fighter steers (2 pixel steps);
; one row per frame (HROW = row still to draw, 0 = none)
HORIZON:
  LDA HROW
  BNE .ho_row
  LDA SX
  LSR A
  AND #$3E
  CMP HOFF
  BNE .ho_go
  RTS
.ho_go:
  STA HOFF
  LDA #6
  STA HROW
.ho_row:
  LDA HOFF                     ; shift of the tiles: (offset / 2) and 3
  LSR A
  AND #$03
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #128
  LDX HROW
  CPX #7
  BNE .ho_t
  ORA #8                       ; row 7: the lower tiles
.ho_t:
  STA T2
  LDA HOFF
  LSR A
  LSR A
  LSR A
  STA T3                       ; whole tiles
  LDY #7                       ; the 8 tiles of the period, in order
.ho_b:
  TYA
  CLC
  ADC T3
  AND #$07
  ORA T2
  STA HBUF,Y
  DEY
  BPL .ho_b
  LDY #0
  JSR NT_XY
  LDX #4
.ho_4:
  LDA HBUF
  STA VDATA
  LDA HBUF+1
  STA VDATA
  LDA HBUF+2
  STA VDATA
  LDA HBUF+3
  STA VDATA
  LDA HBUF+4
  STA VDATA
  LDA HBUF+5
  STA VDATA
  LDA HBUF+6
  STA VDATA
  LDA HBUF+7
  STA VDATA
  DEX
  BNE .ho_4
  LDA HROW                     ; row 6 done: row 7 in the next frame
  CMP #6
  BNE .ho_end
  LDA #7
  STA HROW
  RTS
.ho_end:
  STZ HROW
  RTS

; the field: stars, horizon, ground, HUD
DRAW_FIELD:
  LDX #2                       ; stars on rows 2-5
  LDY #0
  JSR NT_XY
  LDX #0
.df_s:
  LDA STAR_NT,X
  STA VDATA
  INX
  CPX #128
  BNE .df_s
  LDA #$FF
  STA HOFF
  STZ HROW
  JSR HORIZON                  ; row 6
  JSR HORIZON                  ; row 7
  LDX #8                       ; ground rows 8-22
.df_r:
  PHX
  LDY #0
  JSR NT_XY
  PLX
  TXA
  SEC
  SBC #8
  CPX #16
  BCC .df_t
  SBC #8
.df_t:
  ORA #128
  LDY #32
.df_c:
  STA VDATA
  DEY
  BNE .df_c
  INX
  CPX #23
  BNE .df_r
  JSR DRAW_TOP
  JMP DRAW_BOTTOM

; title: the ground only on rows 17-22
DRAW_GROUND_LOW:
  LDX #17
.dg_r:
  PHX
  LDY #0
  JSR NT_XY
  PLX
  TXA
  SEC
  SBC #16
  ORA #128
  LDY #32
.dg_c:
  STA VDATA
  DEY
  BNE .dg_c
  INX
  CPX #23
  BNE .dg_r
  RTS

; the stars again on rows 3-4 (where the messages are written)
CLEAR_BANNER:
  LDX #3
  LDY #0
  JSR NT_XY
  LDX #0
.cb_l:
  LDA STAR_NT+32,X
  STA VDATA
  INX
  CPX #64
  BNE .cb_l
  RTS

; "BONUS nnnnn" in the sky for a while (keeps X)
SHOW_BONUS:
  PHX
  JSR CLEAR_BANNER
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDY BONI
  JSR PUT_BON
  LDA #90
  STA BANT
  PLX
  RTS

; Y = index of a bonus: 5 digits where the VDP points
PUT_BON:
  LDA BON_H,Y
  AND #$0F
  ORA #$30
  STA VDATA
  LDA BON_M,Y
  JSR PUT_2
  LDA BON_L,Y
  JMP PUT_2


; ===============================================================
;  HUD: rows 0-1 scores, row 23 charges, fighters, bonus
; ===============================================================
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

; row 23: CHARGE nn, the spare fighters, BONUS nnnnn
DRAW_BOTTOM:
  LDA #<TXT_BOT
  STA TP
  LDA #>TXT_BOT
  STA TP+1
  JSR PRINT
  ; fall into DRAW_BVALS

; row 23: the numbers only
DRAW_BVALS:
  LDA CHARGE
  JSR BIN2BCD
  LDX #23
  LDY #7
  JSR PUT_BCD2
  LDX #23
  LDY #11
  JSR NT_XY
  LDX CURP
  LDA ALIVE,X
  BEQ .db_z
  DEC A
.db_z:
  STA T0
  LDX #0
.db_l:
  LDA #$20
  CPX T0
  BCS .db_b
  LDA #104
.db_b:
  STA VDATA
  INX
  CPX #4
  BNE .db_l
  LDX #23
  LDY #25
  JSR NT_XY
  LDY BONI
  JMP PUT_BON

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  LDX CURP
  JSR DRAW_SCORE
  JMP DRAW_BVALS
.uh_r:
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
;  of the explosions; left chip = the fighter, right = the enemies
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
PS_OFF:     .byte 0,8                          ; block of the player in PSAVE
XL_AT:      .byte $02,$05                      ; extra fighters at 20000 and 50000 (BCD high digits)
GC_OFF:     .word GCB,GCB+120,GCB+240,GCB+360  ; colours of the bands of every landscape
SKY_SRC:    .word SKY_P0,SKY_C0,SKY_P1,SKY_C1,SKY_P2,SKY_C2,SKY_P3,SKY_C3
; the paths of the formations: centre, sway (0, 64, 128 = 24, 48, 72 pixels), phase step, first phase
FP_CX:      .byte 128,80,176,128,64,192,128,100
FP_AMP:     .byte 64,0,0,128,64,64,128,64
FP_W:       .byte 3,4,4,2,5,5,3,6
FP_PH:      .byte 0,16,48,32,0,128,64,32
; by kind: amoeba, bird, pterosaur, UFO, alien, hydra
EN_BASE:    .byte PT_EN,PT_EN+24,PT_EN+48,PT_EN+72,PT_EN+96,PT_HYDRA
EN_COL:     .byte $03,$09,$0A,$07,$0D,$08
EN_PL:      .byte $00,$50,$00,$00,$00,$00      ; points (BCD): 100, 150, 200, 300, 100, 1000
EN_PM:      .byte $01,$01,$02,$03,$01,$10
DIVE_P:     .byte 1,2,3,2,0,0                  ; chance of a dive, of 4
; the formation bonus: 200, 400, 800, 1600, 3200, 6400, 10000, 5000
BON_L:      .byte $00,$00,$00,$00,$00,$00,$00,$00
BON_M:      .byte $02,$04,$08,$16,$32,$64,$00,$50
BON_H:      .byte $00,$00,$00,$00,$00,$00,$01,$00
BON_DBL:    .byte 1,2,3,4,5,6,0,6              ; after a formation: doubled (after 10000 back to 200)
BON_HALF:   .byte 0,0,1,2,3,4,7,4              ; after a shot that missed: halved
EXPL_N:     .byte PT_EXPL,PT_EXPL+4,PT_EXPL+8
EXPL_C:     .byte $0B,$0A,$09

; title: the enemies of the table and the fighter on the ground (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 7*8-5,9*8-5,11*8-5,13*8-5,151,151
TITLE_SX:   .byte 60,60,60,60,120,120
TITLE_SN:   .byte PT_EN+16,PT_EN+40,PT_EN+64,PT_EN+88,PT_SHIPD,PT_SHIP
TITLE_SC:   .byte $03,$09,$0A,$07,$08,$0F

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 5,8,"- SCORE TABLE -",0
  .byte 7,10,"AMOEBA      100",0
  .byte 9,10,"BIRD        150",0
  .byte 11,10,"PTEROSAUR   200",0
  .byte 13,10,"UFO         300",0
  .byte 15,2,"FORMATION BONUS UP TO 10000",0
  .byte 16,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_BOT:
  .byte 23,0,"CHARGE",0
  .byte 23,19,"BONUS",0
  .byte $FF
TXT_PLAYER:
  .byte 3,12,"PLAYER ",0
  .byte $FF
TXT_STAGE:
  .byte 4,12,"STAGE",0
  .byte $FF
TXT_CHAL:
  .byte 4,7,"CHALLENGING STAGE",0
  .byte $FF
TXT_RESULT:
  .byte 3,12,"HITS",0
  .byte $FF
TXT_PERFECT:
  .byte 4,7,"PERFECT  CHARGE 60",0
  .byte $FF
TXT_CLEAR:
  .byte 3,10,"STAGE CLEAR",0
  .byte $FF
TXT_BONUS:
  .byte 3,10,"BONUS ",0
  .byte $FF
TXT_OVER:
  .byte 4,11,"GAME OVER",0
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

; the start tune of a game, in A minor (composed for this version), 210 frames
;   A4 34  B4 36  C5 37  D5 39  E5 41  F5 42  G5 44  A5 46  B5 48  C6 49
START_LEAD:
  .byte 34,6, 37,6, 41,6, 46,18, 44,6, 42,6, 41,12, 39,12, 41,24, 0,6
  .byte 37,6, 41,6, 44,6, 49,18, 48,6, 46,6, 44,12, 41,12, 46,30
  .byte $FF
START_HARM:
  .byte 29,42, 30,42, 32,42, 34,42, 34,42
  .byte $FF
START_BASS:
  .byte 10,21, 17,21, 6,21, 13,21, 8,21, 15,21, 13,21, 20,21, 10,21, 10,21
  .byte $FF
START_DRUM:
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,6, 4,12
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
; Exerion: generated by dev/gen_exerion.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4. Riders of the computer: PT_EN + kind * 24 + size * 8 + frame * 4
PT_SHIP = 0
PT_SHIPD = 12
PT_DUAL = 24
PT_SINGLE = 28
PT_EGG = 32
PT_EN = 36
PT_HYDRA = 156
PT_EXPL = 164
SPR_PAGES = 6
SPRITES:
;  0 ship, 4 ship L, 8 ship R, 12 ship detail, 16 ship detail L, 20 ship detail R, 24 dual shot, 28 single shot, 32 egg, 36 amoeba 7 0, 40 amoeba 7 1, 44 amoeba 11 0, 48 amoeba 11 1, 52 amoeba 16 0, 56 amoeba 16 1, 60 bird 7 0, 64 bird 7 1, 68 bird 11 0, 72 bird 11 1, 76 bird 16 0, 80 bird 16 1, 84 ptero 7 0, 88 ptero 7 1, 92 ptero 11 0, 96 ptero 11 1, 100 ptero 16 0, 104 ptero 16 1, 108 ufo 7 0, 112 ufo 7 1, 116 ufo 11 0, 120 ufo 11 1, 124 ufo 16 0, 128 ufo 16 1, 132 alien 7 0, 136 alien 7 1, 140 alien 11 0, 144 alien 11 1, 148 alien 16 0, 152 alien 16 1, 156 hydra 0, 160 hydra 1, 164 explosion 0, 168 explosion 1, 172 explosion 2
  .byte $01,$01,$03,$03,$07,$06,$4E,$5F,$7F,$FF,$FF,$EF,$C7,$83,$02,$00
  .byte $80,$80,$C0,$C0,$E0,$60,$72,$FA,$FE,$FF,$FF,$F7,$E3,$C1,$40,$00
  .byte $00,$00,$01,$01,$03,$03,$07,$0F,$0F,$0F,$0F,$07,$03,$01,$01,$00
  .byte $C0,$C0,$E0,$E0,$F0,$30,$39,$FD,$FF,$FF,$FF,$FB,$F1,$E0,$20,$00
  .byte $03,$03,$07,$07,$0F,$0C,$9C,$BF,$FF,$FF,$FF,$DF,$8F,$07,$04,$00
  .byte $00,$00,$80,$80,$C0,$C0,$E0,$F0,$F0,$F0,$F0,$E0,$C0,$80,$80,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$00,$00,$30,$00,$00,$00,$00,$02,$00
  .byte $00,$00,$00,$00,$00,$80,$80,$00,$00,$0C,$00,$00,$00,$00,$40,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$01,$00
  .byte $00,$00,$00,$00,$00,$C0,$C0,$00,$00,$06,$00,$00,$00,$00,$20,$00
  .byte $00,$00,$00,$00,$00,$03,$03,$00,$00,$60,$00,$00,$00,$00,$04,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$80,$00
  .byte $00,$00,$00,$00,$00,$10,$10,$10,$10,$10,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$08,$08,$08,$08,$08,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$C0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$0F,$0F,$07,$0B,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$E0,$E0,$A0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$07,$0F,$0F,$07,$05,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$E0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$03,$0F,$1F,$3F,$3B,$3F,$0F,$37,$22,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$F0,$F8,$F8,$D8,$F8,$F0,$D8,$88,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$0F,$1F,$3F,$3F,$1F,$0F,$0B,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$F0,$B8,$F8,$F8,$F0,$E0,$90,$10,$00,$00,$00,$00
  .byte $00,$07,$1F,$3D,$7D,$7F,$FF,$E7,$FF,$7F,$3F,$6F,$C7,$82,$00,$00
  .byte $00,$E0,$F8,$BC,$BE,$FE,$FF,$E7,$FF,$FE,$FC,$F6,$E3,$41,$00,$00
  .byte $00,$00,$0F,$3F,$7B,$7B,$FF,$FF,$73,$3F,$1F,$33,$22,$20,$00,$00
  .byte $00,$00,$F0,$FC,$DE,$DE,$FF,$FF,$CE,$FC,$F8,$CC,$44,$04,$00,$00
  .byte $00,$00,$00,$00,$08,$0D,$07,$03,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$E0,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$0F,$09,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$E0,$A0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$20,$30,$39,$1F,$0F,$06,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$08,$08,$98,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$3F,$3F,$3B,$23,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$F8,$F8,$D8,$88,$80,$00,$00,$00,$00,$00
  .byte $80,$C0,$E1,$73,$7F,$3F,$1F,$0E,$06,$03,$01,$02,$00,$00,$00,$00
  .byte $01,$03,$87,$CE,$FE,$FC,$F8,$70,$60,$C0,$80,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$03,$67,$FF,$FF,$77,$C6,$83,$01,$02,$00,$00,$00
  .byte $00,$00,$00,$80,$C0,$E6,$FF,$FF,$EE,$63,$C1,$80,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$0B,$0F,$07,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$A0,$E0,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$07,$0B,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$A0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$33,$3B,$3F,$0F,$05,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$80,$80,$C8,$F8,$F8,$F0,$E0,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$03,$0F,$3F,$33,$21,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$80,$80,$C0,$E0,$F8,$C8,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $01,$03,$87,$C6,$F7,$FF,$7F,$3F,$1D,$09,$01,$01,$02,$00,$00,$00
  .byte $80,$C0,$E1,$63,$EF,$FF,$FE,$FC,$B8,$90,$80,$80,$40,$00,$00,$00
  .byte $01,$03,$02,$07,$1F,$7F,$FF,$C7,$83,$01,$01,$01,$02,$00,$00,$00
  .byte $80,$C0,$40,$E0,$F8,$FE,$FF,$E3,$C1,$80,$80,$80,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$07,$0F,$07,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$07,$0F,$07,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$1F,$3F,$3F,$0F,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$E0,$F0,$F8,$F8,$E0,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$1F,$3F,$1F,$0F,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$E0,$F0,$F8,$F8,$E0,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$0D,$3F,$7F,$FF,$AA,$7F,$1F,$07,$00,$00,$00,$00
  .byte $00,$00,$C0,$E0,$B0,$FC,$FE,$FF,$AA,$FE,$F8,$E0,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$0D,$3F,$7F,$FF,$55,$7F,$1F,$07,$00,$00,$00,$00
  .byte $00,$00,$C0,$E0,$B0,$FC,$FE,$FF,$55,$FE,$F8,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$07,$0F,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$E0,$E0,$40,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0B,$0F,$04,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$E0,$40,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$07,$0F,$3F,$2F,$2C,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$E0,$B0,$F8,$F8,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$17,$1F,$1F,$08,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$E8,$B8,$F0,$20,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$10,$08,$1F,$3B,$7F,$FF,$BF,$A0,$1C,$00,$00,$00,$00,$00,$00
  .byte $00,$08,$10,$F8,$DC,$FE,$FF,$FD,$05,$38,$00,$00,$00,$00,$00,$00
  .byte $00,$08,$48,$5F,$7B,$7F,$3F,$10,$20,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$10,$12,$FA,$DE,$FE,$FC,$08,$04,$02,$00,$00,$00,$00,$00,$00
  .byte $84,$CE,$4A,$6E,$34,$1F,$3F,$77,$FF,$FF,$6F,$4D,$99,$31,$21,$00
  .byte $21,$73,$52,$76,$2C,$F8,$FC,$EE,$FF,$FF,$F6,$B2,$99,$8C,$84,$00
  .byte $42,$E7,$A5,$E7,$62,$1F,$3F,$77,$FF,$FF,$6F,$2D,$59,$61,$21,$00
  .byte $42,$73,$52,$76,$2C,$F8,$FC,$EE,$FF,$FF,$F6,$B4,$9A,$86,$84,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$03,$03,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$C0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$0E,$18,$06,$00,$06,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$00,$60,$30,$00,$30,$F0,$60,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$04,$00,$28,$40,$08,$00,$00,$00,$08,$02,$00
  .byte $00,$00,$00,$80,$00,$60,$10,$00,$00,$00,$08,$28,$80,$60,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; small tiles: 8 stars (96-103), spare ship (104)
TILE_PAT:
  .byte $20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$08,$00,$00,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10
  .byte $00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00
  .byte $18,$18,$3C,$7E,$FF,$DB,$99,$00
TILE_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $D0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $F0,$F0,$F0,$F0,$F0,$80,$80,$80

; the skylines of the 4 landscapes: tiles 128-191 of the third 0 = shift (2 pixels) * 16 + row * 8 + column
SKY_P0:
  .byte $00,$00,$00,$02,$02,$0F,$1F,$1F,$00,$00,$00,$00,$00,$80,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$21,$00,$08,$08,$3E,$7F,$7F,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$80,$C1,$00,$00,$00,$00,$00,$40,$40,$F0
  .byte $00,$00,$04,$04,$1F,$3F,$3F,$7F,$00,$00,$00,$00,$00,$80,$80,$C0
  .byte $3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$E0,$F0,$F9,$F9,$FF,$FF,$FF,$FF
  .byte $23,$FB,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $E3,$E3,$FF,$FF,$FF,$FF,$FF,$FF,$F8,$F9,$FD,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$E0,$F0,$F0,$FC,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$08,$08,$3E,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$03,$87,$00,$20,$20,$F8,$FC,$FC,$FE,$FF
  .byte $00,$00,$00,$00,$00,$01,$01,$07,$00,$00,$00,$00,$00,$00,$00,$C1
  .byte $00,$00,$10,$10,$7C,$FE,$FE,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$C3,$E7,$E7,$FF,$FF,$FF,$FF
  .byte $8F,$EF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $8F,$8F,$FF,$FF,$FF,$FF,$FF,$FF,$E3,$E7,$F7,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$C1,$C3,$F3,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$20,$20,$F8,$FC,$FC,$00,$00,$00,$00,$00,$00,$00,$02
  .byte $00,$00,$00,$03,$07,$07,$0F,$1F,$00,$80,$80,$E0,$F0,$F0,$F8,$FC
  .byte $00,$00,$00,$00,$00,$04,$04,$1F,$00,$00,$00,$00,$01,$03,$03,$07
  .byte $00,$00,$40,$40,$F0,$F8,$F8,$FC,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$02,$0F,$9F,$9F,$FF,$FF,$FF,$FF
  .byte $3F,$BF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $3F,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$8F,$9F,$DF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$03,$07,$0F,$CF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$80,$80,$E0,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$08
  .byte $00,$02,$02,$0F,$1F,$1F,$3F,$7F,$00,$00,$00,$80,$C0,$C0,$E0,$F0
  .byte $00,$00,$00,$00,$00,$10,$10,$7C,$00,$00,$01,$01,$07,$0F,$0F,$1F
  .byte $00,$00,$00,$00,$C0,$E0,$E0,$F0,$00,$00,$00,$00,$00,$03,$07,$07
  .byte $F8,$FC,$FE,$FE,$FF,$FF,$FF,$FF,$08,$3E,$7F,$7F,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F8,$F8,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$3F,$7F,$7F,$FF,$FF,$FF,$FF,$FF
  .byte $F8,$FC,$FC,$FF,$FF,$FF,$FF,$FF,$0F,$1F,$3F,$3F,$FF,$FF,$FF,$FF
SKY_C0:
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
  .byte $E0,$40,$40,$40,$40,$40,$40,$40,$E0,$40,$40,$40,$40,$40,$40,$40
SKY_P1:
  .byte $00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$60,$F0,$F8,$F0,$60
  .byte $00,$00,$00,$01,$03,$07,$03,$01,$00,$00,$00,$80,$C0,$E0,$C0,$80
  .byte $00,$00,$00,$03,$07,$0F,$07,$03,$00,$00,$00,$00,$80,$C0,$80,$00
  .byte $00,$00,$00,$30,$78,$FC,$78,$30,$00,$00,$00,$30,$78,$FC,$78,$30
  .byte $00,$00,$1F,$7F,$FF,$FF,$FF,$FF,$60,$60,$61,$FF,$FF,$FF,$FF,$FF
  .byte $01,$3D,$FF,$FF,$FF,$FF,$FF,$FF,$80,$80,$80,$C0,$FF,$FF,$FF,$FF
  .byte $03,$03,$03,$03,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$80,$E1,$FF
  .byte $30,$30,$30,$30,$30,$3F,$FF,$FF,$30,$30,$30,$30,$30,$B3,$FF,$FF
  .byte $00,$00,$00,$01,$03,$07,$03,$01,$00,$00,$00,$80,$C0,$E0,$C0,$80
  .byte $00,$00,$00,$06,$0F,$1F,$0F,$06,$00,$00,$00,$00,$00,$80,$00,$00
  .byte $00,$00,$00,$0C,$1E,$3F,$1E,$0C,$00,$00,$00,$00,$01,$03,$01,$00
  .byte $00,$00,$00,$C0,$E1,$F3,$E1,$C0,$00,$00,$00,$C0,$E0,$F0,$E0,$C0
  .byte $01,$01,$7D,$FF,$FF,$FF,$FF,$FF,$80,$80,$87,$FF,$FF,$FF,$FF,$FF
  .byte $06,$F6,$FE,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF
  .byte $0C,$0C,$0C,$0C,$FC,$FE,$FF,$FF,$00,$00,$00,$00,$00,$00,$87,$FF
  .byte $C0,$C0,$C0,$C0,$C0,$FE,$FF,$FF,$C0,$C0,$C0,$C1,$C3,$CF,$FF,$FF
  .byte $00,$00,$00,$06,$0F,$1F,$0F,$06,$00,$00,$00,$00,$00,$80,$00,$00
  .byte $00,$00,$00,$18,$3C,$7E,$3C,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$30,$78,$FC,$78,$30,$00,$00,$00,$03,$07,$0F,$07,$03
  .byte $00,$00,$00,$03,$87,$CF,$87,$03,$00,$00,$00,$00,$80,$C0,$80,$00
  .byte $06,$06,$F6,$FF,$FF,$FF,$FF,$FF,$00,$03,$1F,$FF,$FF,$FF,$FF,$FF
  .byte $18,$D8,$F8,$FC,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF
  .byte $30,$30,$30,$30,$F0,$F8,$FE,$FF,$03,$03,$03,$03,$03,$03,$1F,$FF
  .byte $03,$03,$03,$03,$03,$FB,$FF,$FF,$00,$00,$01,$07,$0F,$3F,$FF,$FF
  .byte $00,$00,$00,$18,$3C,$7E,$3C,$18,$00,$00,$00,$00,$00,$01,$00,$00
  .byte $00,$00,$00,$60,$F0,$F8,$F0,$60,$00,$00,$00,$00,$01,$03,$01,$00
  .byte $00,$00,$00,$C0,$E0,$F0,$E0,$C0,$00,$00,$00,$0C,$1E,$3F,$1E,$0C
  .byte $00,$00,$00,$0C,$1E,$3F,$1E,$0C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$D8,$FF,$FF,$FF,$FF,$FF,$00,$0F,$7F,$FF,$FF,$FF,$FF,$FF
  .byte $60,$60,$E0,$F0,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF
  .byte $C0,$C0,$C0,$C0,$C0,$E0,$F8,$FF,$0C,$0C,$0C,$0C,$0C,$0F,$7F,$FF
  .byte $0C,$0C,$0C,$0C,$0C,$EC,$FF,$FF,$00,$00,$07,$1F,$3F,$FF,$FF,$FF
SKY_C1:
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
  .byte $20,$20,$20,$20,$C0,$C0,$C0,$C0,$20,$20,$20,$20,$C0,$C0,$C0,$C0
SKY_P2:
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$00,$02,$02,$02,$02,$E2,$E2,$62
  .byte $01,$01,$01,$07,$07,$05,$07,$07,$00,$00,$00,$C0,$C0,$40,$C0,$DF
  .byte $00,$00,$08,$08,$09,$09,$09,$89,$00,$00,$00,$00,$FC,$FC,$54,$FC
  .byte $00,$00,$07,$07,$05,$07,$07,$05,$00,$00,$E0,$E0,$60,$E0,$EF,$6F
  .byte $01,$FD,$FD,$AD,$FD,$FD,$AD,$FD,$E2,$E2,$62,$E2,$EF,$6F,$EA,$EF
  .byte $05,$07,$07,$05,$F7,$F7,$B5,$F7,$5F,$D5,$DF,$5F,$D5,$DF,$5F,$DF
  .byte $89,$89,$BD,$BD,$AD,$BD,$BD,$BD,$FD,$55,$FD,$FD,$55,$FD,$FD,$FD
  .byte $F7,$F7,$55,$F7,$F7,$55,$F7,$F7,$EB,$EF,$6F,$EB,$EF,$6F,$EB,$EF
  .byte $00,$00,$00,$00,$00,$07,$07,$05,$00,$08,$08,$08,$08,$88,$88,$88
  .byte $04,$04,$04,$1F,$1F,$15,$1F,$1F,$00,$00,$00,$00,$00,$00,$00,$7E
  .byte $00,$00,$20,$20,$27,$27,$25,$27,$00,$00,$00,$00,$F0,$F0,$50,$F0
  .byte $00,$00,$1F,$1F,$15,$1F,$1F,$15,$00,$00,$80,$80,$80,$80,$BC,$BC
  .byte $07,$F7,$F5,$B7,$F7,$F5,$B7,$F7,$88,$88,$88,$88,$BF,$BF,$AA,$BF
  .byte $15,$1F,$1F,$15,$DF,$DF,$D5,$DF,$7E,$56,$7E,$7E,$56,$7E,$7E,$7E
  .byte $27,$25,$F7,$F7,$B5,$F7,$F7,$F7,$F7,$57,$F5,$F7,$57,$F5,$F7,$F7
  .byte $DF,$DF,$55,$DF,$DF,$55,$DF,$DF,$AC,$BF,$BF,$AE,$BF,$BF,$AE,$BF
  .byte $00,$00,$00,$00,$00,$1E,$1E,$16,$00,$20,$20,$20,$20,$20,$20,$20
  .byte $10,$10,$10,$7C,$7C,$54,$7C,$7D,$00,$00,$00,$00,$00,$00,$00,$F8
  .byte $00,$00,$80,$80,$9F,$9F,$95,$9F,$00,$00,$00,$00,$C0,$C0,$40,$C0
  .byte $00,$00,$7E,$7E,$56,$7E,$7E,$56,$00,$00,$00,$00,$00,$00,$F0,$F0
  .byte $1E,$DE,$D6,$DE,$DE,$D6,$DE,$DE,$20,$20,$20,$20,$FF,$FF,$AB,$FF
  .byte $55,$7D,$7D,$55,$7D,$7D,$55,$7D,$F8,$58,$FB,$FB,$5A,$FB,$FB,$FB
  .byte $9F,$95,$DF,$DF,$D5,$DF,$DF,$DF,$DF,$5F,$D5,$DF,$5F,$D5,$DF,$DF
  .byte $7E,$7E,$56,$7E,$7E,$56,$7E,$7E,$B0,$FF,$FF,$BA,$FF,$FF,$BA,$FF
  .byte $00,$00,$00,$00,$00,$78,$78,$58,$00,$80,$80,$81,$81,$81,$81,$81
  .byte $40,$40,$40,$F0,$F0,$50,$F0,$F7,$00,$00,$02,$02,$02,$02,$02,$E2
  .byte $00,$00,$00,$00,$7F,$7F,$55,$7F,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $00,$00,$F8,$F8,$58,$F8,$FB,$5B,$00,$00,$00,$00,$00,$00,$C0,$C0
  .byte $78,$78,$58,$78,$7B,$5B,$7A,$7B,$81,$81,$81,$81,$FD,$FD,$AD,$FD
  .byte $57,$F5,$F7,$57,$F5,$F7,$57,$F7,$E2,$62,$EF,$EF,$6B,$EF,$EF,$EF
  .byte $7F,$55,$7F,$7F,$55,$7F,$7F,$7F,$7D,$7D,$55,$7D,$7D,$55,$7D,$7D
  .byte $FA,$FB,$5B,$FA,$FB,$5B,$FA,$FB,$C0,$FF,$FF,$EB,$FF,$FF,$EB,$FF
SKY_C2:
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $70,$70,$70,$50,$50,$50,$50,$50,$70,$70,$70,$50,$50,$50,$50,$50
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
  .byte $50,$40,$40,$40,$40,$40,$40,$40,$50,$40,$40,$40,$40,$40,$40,$40
SKY_P3:
  .byte $00,$00,$00,$00,$1A,$1C,$1C,$1C,$00,$00,$00,$00,$00,$00,$34,$38
  .byte $00,$00,$68,$70,$70,$70,$70,$70,$00,$00,$00,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$A8,$FE,$F7,$C3,$C3,$00,$00,$00,$00,$00,$C0,$C0,$C0
  .byte $00,$00,$00,$00,$0D,$0E,$0E,$0E,$00,$00,$00,$00,$00,$00,$00,$1A
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$FF,$FF,$38,$38,$38,$38,$38,$38,$FF,$FF
  .byte $70,$70,$70,$70,$70,$70,$FF,$FF,$D1,$E1,$E1,$E1,$E1,$E1,$FF,$FF
  .byte $C3,$C3,$C3,$C3,$C3,$C3,$FF,$FF,$80,$86,$87,$87,$87,$87,$FF,$FF
  .byte $0E,$8E,$0E,$0E,$0E,$0E,$FF,$FF,$1C,$1C,$1C,$1C,$1C,$1C,$FF,$FF
  .byte $00,$00,$00,$00,$68,$70,$70,$70,$00,$00,$01,$01,$01,$01,$D1,$E1
  .byte $00,$00,$A0,$C0,$C0,$C0,$C0,$C0,$00,$00,$00,$06,$07,$07,$07,$07
  .byte $00,$00,$00,$A0,$F8,$DF,$0F,$0F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$34,$38,$38,$38,$00,$00,$00,$00,$00,$00,$00,$68
  .byte $70,$70,$70,$70,$70,$70,$FF,$FF,$E1,$E1,$E1,$E1,$E1,$E1,$FF,$FF
  .byte $C3,$C3,$C3,$C3,$C3,$C3,$FF,$FF,$47,$87,$87,$87,$87,$87,$FF,$FF
  .byte $0E,$0E,$0E,$0E,$0E,$0E,$FF,$FF,$00,$1A,$1C,$1C,$1C,$1C,$FF,$FF
  .byte $38,$38,$38,$38,$38,$38,$FF,$FF,$70,$70,$70,$70,$70,$70,$FF,$FF
  .byte $00,$00,$00,$00,$A0,$C0,$C3,$C3,$00,$00,$06,$07,$07,$07,$47,$87
  .byte $00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$1A,$1F,$1F,$1C,$1C
  .byte $00,$00,$00,$80,$E0,$7C,$3C,$3C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$D0,$E0,$E0,$E1,$00,$00,$00,$00,$01,$01,$01,$A1
  .byte $C3,$C3,$C3,$C3,$C3,$C3,$FF,$FF,$87,$87,$87,$87,$87,$87,$FF,$FF
  .byte $0D,$0E,$0E,$0E,$0E,$0E,$FF,$FF,$1C,$1C,$1C,$1C,$1C,$1C,$FF,$FF
  .byte $38,$38,$38,$38,$38,$38,$FF,$FF,$00,$68,$70,$70,$70,$70,$FF,$FF
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$FF,$FF,$C1,$C1,$C1,$C1,$C1,$C1,$FF,$FF
  .byte $00,$00,$00,$00,$80,$00,$0D,$0E,$00,$00,$1A,$1C,$1C,$1C,$1C,$1C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$6A,$7F,$7D,$70,$70
  .byte $00,$00,$00,$00,$80,$F0,$F0,$F0,$00,$00,$00,$00,$03,$03,$03,$03
  .byte $00,$00,$00,$00,$40,$80,$80,$86,$00,$00,$00,$00,$06,$07,$07,$87
  .byte $0E,$0E,$0E,$0E,$0E,$0E,$FF,$FF,$1C,$1C,$1C,$1C,$1C,$1C,$FF,$FF
  .byte $34,$38,$38,$38,$38,$38,$FF,$FF,$70,$70,$70,$70,$70,$70,$FF,$FF
  .byte $E0,$E1,$E1,$E1,$E1,$E1,$FF,$FF,$03,$A3,$C3,$C3,$C3,$C3,$FF,$FF
  .byte $87,$87,$87,$87,$87,$87,$FF,$FF,$07,$07,$07,$07,$07,$07,$FF,$FF
SKY_C3:
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$B0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60
  .byte $A0,$A0,$A0,$90,$90,$60,$60,$60,$A0,$A0,$A0,$90,$90,$60,$60,$60

; the stars of the sky, rows 2-5
STAR_NT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$67,$60,$00,$65,$00,$00,$63,$66,$64,$00,$00,$63,$65,$65,$00,$00,$00,$00,$00,$61
  .byte $00,$61,$00,$00,$65,$00,$00,$65,$00,$00,$63,$00,$00,$00,$00,$00,$62,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$67,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$61,$00,$00,$00,$00,$00,$00,$00,$00,$00,$62,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$65,$00,$00,$00,$00,$00,$67,$00,$00,$00,$00,$00,$00,$60,$00,$00,$00

; big letters of the title: E X R I O N, 4 tiles each (192-215)
BIG_P:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80
  .byte $01,$06,$06,$18,$18,$18,$18,$00,$80,$60,$60,$18,$18,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
BIG_C:
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$60,$60,$90,$90,$90,$90,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$60,$60,$90,$90,$90,$90,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$60,$60,$90,$90,$90,$90,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$60,$60,$90,$90,$90,$90,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$60,$60,$90,$90,$90,$90,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$60,$60,$90,$90,$90,$90,$80,$80,$60,$60

TXT_BIG:
  .byte 2,9,192,193,196,197,192,193,200,201,204,205,208,209,212,213,0
  .byte 3,9,194,195,198,199,194,195,202,203,206,207,210,211,214,215,0
  .byte $FF

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $00,$43, <72,>72, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$63, <72,>72, <TILE_COL,>TILE_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $00,$4B, <72,>72, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$6B, <72,>72, <TILE_COL,>TILE_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $00,$53, <72,>72, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$73, <72,>72, <TILE_COL,>TILE_COL
  .byte 2, $00,$4C, <64,>64, $FF,0
  .byte 2, $00,$54, <64,>64, $FF,0
  .byte 1, $00,$46, <192,>192, <BIG_P,>BIG_P
  .byte 1, $00,$66, <192,>192, <BIG_C,>BIG_C
  .byte 0

; ground: depth of every line (16384 / (line + 6), the bands are its bit 5)
NLINES = 120
DEPTH:
  .byte $AB,$25,$00,$1C,$66,$D1,$55,$EC,$92,$44,$00,$C4,$8E,$5E,$33,$0C
  .byte $E9,$C8,$AB,$8F,$76,$5F,$49,$35,$22,$11,$00,$F0,$E2,$D4,$C7,$BB
  .byte $AF,$A4,$9A,$90,$86,$7D,$74,$6C,$64,$5D,$55,$4E,$48,$41,$3B,$35
  .byte $2F,$2A,$25,$1F,$1A,$16,$11,$0D,$08,$04,$00,$FC,$F8,$F5,$F1,$ED
  .byte $EA,$E7,$E4,$E0,$DD,$DA,$D8,$D5,$D2,$CF,$CD,$CA,$C8,$C5,$C3,$C1
  .byte $BF,$BC,$BA,$B8,$B6,$B4,$B2,$B0,$AE,$AC,$AB,$A9,$A7,$A5,$A4,$A2
  .byte $A1,$9F,$9E,$9C,$9B,$99,$98,$96,$95,$94,$92,$91,$90,$8E,$8D,$8C
  .byte $8B,$8A,$89,$87,$86,$85,$84,$83
; colours of the two bands for every line, 4 landscapes x 120 lines
GCA:
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66
  .byte $66,$66,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC
  .byte $CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$22,$22,$22,$22,$22,$22
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$33,$33
  .byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
  .byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
  .byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
  .byte $33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33,$33
  .byte $44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44
  .byte $44,$44,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77
  .byte $77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77
  .byte $77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77
  .byte $77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77,$77
  .byte $77,$77,$77,$77,$77,$77,$77,$77,$66,$66,$66,$66,$66,$66,$66,$66
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$99,$99,$99,$99,$99,$99
  .byte $99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99
  .byte $99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
GCB:
  .byte $66,$66,$66,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66
  .byte $66,$66,$66,$66,$66,$66,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$CC,$CC,$CC,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$CC,$CC,$CC,$CC,$CC,$CC
  .byte $CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC
  .byte $CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$22,$22
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
  .byte $44,$44,$44,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44
  .byte $44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44
  .byte $44,$44,$44,$44,$44,$44,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$66,$66,$66,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$66,$66,$66,$66,$66,$66
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$99,$99
  .byte $99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99
  .byte $99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99
  .byte $99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99
  .byte $99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99,$99

; swaying of the formations: amplitude 24, 48, 72 x 64 phases (signed)
SINT:
  .byte $00,$02,$05,$07,$09,$0B,$0D,$0F,$11,$13,$14,$15,$16,$17,$18,$18
  .byte $18,$18,$18,$17,$16,$15,$14,$13,$11,$0F,$0D,$0B,$09,$07,$05,$02
  .byte $00,$FE,$FB,$F9,$F7,$F5,$F3,$F1,$EF,$ED,$EC,$EB,$EA,$E9,$E8,$E8
  .byte $E8,$E8,$E8,$E9,$EA,$EB,$EC,$ED,$EF,$F1,$F3,$F5,$F7,$F9,$FB,$FE
  .byte $00,$05,$09,$0E,$12,$17,$1B,$1E,$22,$25,$28,$2A,$2C,$2E,$2F,$30
  .byte $30,$30,$2F,$2E,$2C,$2A,$28,$25,$22,$1E,$1B,$17,$12,$0E,$09,$05
  .byte $00,$FB,$F7,$F2,$EE,$E9,$E5,$E2,$DE,$DB,$D8,$D6,$D4,$D2,$D1,$D0
  .byte $D0,$D0,$D1,$D2,$D4,$D6,$D8,$DB,$DE,$E2,$E5,$E9,$EE,$F2,$F7,$FB
  .byte $00,$07,$0E,$15,$1C,$22,$28,$2E,$33,$38,$3C,$3F,$43,$45,$47,$48
  .byte $48,$48,$47,$45,$43,$3F,$3C,$38,$33,$2E,$28,$22,$1C,$15,$0E,$07
  .byte $00,$F9,$F2,$EB,$E4,$DE,$D8,$D2,$CD,$C8,$C4,$C1,$BD,$BB,$B9,$B8
  .byte $B8,$B8,$B9,$BB,$BD,$C1,$C4,$C8,$CD,$D2,$D8,$DE,$E4,$EB,$F2,$F9
; speed of approach by line / 8 (8.8)
APP_L:
  .byte $5A,$5A,$5A,$5A,$5A,$5A,$5A,$5A,$77,$94,$B1,$CF,$EC,$09,$26,$44
  .byte $61,$7E,$9B,$B9,$D6,$F3,$10,$2E,$4B,$68,$85,$A3,$C0,$DD,$FB,$18
APP_H:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$23,$26,$2A,$30,$36,$3F,$4C,$5E,$7D,$14,$17,$1C,$71,$65,$5F
  .byte $59,$24,$24,$24,$29,$65,$6B,$77,$84,$53,$59,$59,$59,$8B,$84,$77
  .byte $71,$33,$2E,$29,$24,$53,$59,$5F,$65,$3D,$43,$4E,$53,$92,$92,$92
  .byte $8B,$4E,$43,$38,$33,$5F,$59,$53,$53,$29,$2E,$33,$3D,$1C,$1D,$1D
  .byte $1D,$1F,$20,$1F,$20,$22,$23,$22,$23,$26,$27,$26,$27,$2A,$2C,$2B
  .byte $2C,$30,$32,$31,$33,$38,$3A,$39,$3B,$42,$46,$44,$47,$52,$57,$54
  .byte $5A,$68,$52,$44,$3A,$32,$2D,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35
  .byte $35,$35,$35,$28,$28,$28,$28,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$20,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F,$50
  .byte $50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$50,$50,$50,$50,$50,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$28,$28
  .byte $28,$28,$28,$00,$00,$00,$28,$28,$28,$28,$28,$00,$00,$00,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$45,$39,$31,$2B,$26,$22,$1F,$1C,$1A,$18
  .byte $D0,$EA,$0C,$39
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01
WH_VOL:
  .byte $00,$0D,$0C,$0B,$0A,$0A,$09,$08,$07,$06,$0A,$08,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$07,$06,$05,$04,$03,$02
  .byte $01,$0A,$09,$08,$06,$05,$04,$0D,$0B,$0A,$08,$0D,$0B,$0A,$08,$0D
  .byte $0B,$0A,$08,$0D,$0B,$0A,$08,$0D,$0D,$0C,$0C,$0B,$0B,$0B,$0A,$0A
  .byte $0A,$09,$09,$08,$08,$0C,$0B,$0A,$08,$07,$0C,$0B,$0A,$08,$07,$0C
  .byte $0B,$0A,$08,$07,$0C,$0B,$0A,$08,$07,$0C,$0B,$0A,$08,$07,$0C,$0C
  .byte $0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$08,$07,$07,$0D,$0C
  .byte $0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C
  .byte $0A,$09,$08,$07,$05,$04,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06
  .byte $08,$07,$05,$04
WH_START:
  .byte $00,$01,$0A,$0D,$3D,$61,$67,$85,$AE,$C6,$D0
WH_LEN:
  .byte $00,$09,$03,$30,$24,$06,$1E,$29,$18,$0A,$04
W_DUAL = 1
W_SINGLE = 2
W_HUM = 3
W_DIVE = 4
W_EGG = 5
W_BONUS = 6
W_STAGE = 7
W_EXTRA = 8
W_CHARGE = 9
W_MISS = 10

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0C,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$05
  .byte $04,$03,$03,$02,$01,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E
  .byte $0E,$0E,$0E,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09
  .byte $09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08,$08,$07,$07,$07
  .byte $07,$07,$07,$07,$06,$06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05
  .byte $05,$05,$04,$04,$04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$03,$03
  .byte $02,$02,$02,$02,$02,$02,$02,$01,$01
EX_NP:
  .byte $00,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08
  .byte $08,$09,$09,$09,$09,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0F,$0F,$10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13
  .byte $13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15
  .byte $15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17
  .byte $17,$17,$17,$17,$17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19
  .byte $19,$19,$19,$19,$19,$1A,$1A,$1A,$1A
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$09,$09,$08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$06
  .byte $06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01
  .byte $01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$DF,$E7,$EF,$F7,$00,$0A,$15,$20,$2C,$3A,$49,$59,$6B,$7F,$96
  .byte $AF,$CC,$EC,$12,$3D,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70
EX_TH:
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$02,$02,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04
EX_START:
  .byte $00,$01,$15
EX_LEN:
  .byte $00,$14,$64
S_SMALL = 1
S_SHIP = 2
S_BIG = S_SHIP
