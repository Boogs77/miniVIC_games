;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   CRYSTAL GARDENS  -  an original isometric maze game        ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: robert (VDP, NMI + trampoline $0FD0, AY engine,      ;
;   2 players taking turns)                                    ;
;                                                              ;
;   - a hedgehog walks freely on the terraces of a garden      ;
;     floating in the night (3 heights, ramps, steps to jump)  ;
;     and picks up every crystal seed; the garden is over      ;
;     when no seed is left                                     ;
;   - joystick straight: up = up on the screen, the diagonals  ;
;     follow the rows of the garden; the edges stop the        ;
;     hedgehog; button 1 = jump (one step up or down),         ;
;     button 2 = pause                                         ;
;   - 4 worlds of 4 gardens: orchard, dunes (pine cones),      ;
;     ice house (slippery), night garden (portals); then the   ;
;     16 gardens again, faster                                 ;
;   - magpies steal the seeds (touch them to scare them        ;
;     away), the mole leaves its hole to chase the hedgehog,   ;
;     pine cones roll down (jump over them), the owl comes     ;
;     when the time bar is empty                               ;
;   - the golden acorn (half the seeds taken) rolls the        ;
;     hedgehog into a ball for 6 seconds: it beats moles and   ;
;     pine cones and scares the magpies                        ;
;   - points: seed 10, last seed 500, pine cone jumped 50,     ;
;     acorn 100, magpie 200, mole / pine cone hit 300, bonus   ;
;     10 per seed taken; 3 lives, one more at 20000 and every  ;
;     40000; 1 or 2 players taking turns (title: button 1/2)   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     a tune for every world, seed ticks rising in a row,      ;
;     jump, magpie, mole, owl, ball, portal, clear jingle      ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: lives left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
GARDEN      = $40      ; ---- block of the player, saved: garden 0-15
LOOPN       = $41      ;      times round the 16 gardens
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
FRESH       = $43      ;      1 = the garden starts from the beginning
GOTN        = $44      ;      seeds taken by the hedgehog (bonus)
TIMEU       = $45      ;      time units left (8 per tile of the bar)
PBLOCK      = 6
WORLD       = $46      ; world 0-3
DIFF        = $47      ; difficulty 0-15
NSEED       = $48      ; seeds of the garden
LEFT        = $49      ; seeds left
GSTATE      = $4A      ; 0 playing, 1 caught, 3 garden clear
GT          = $4B      ; timer of GSTATE
JOYC        = $4C      ; both joysticks drive the player playing
JOYP        = $4D      ; JOYC of the frame before
HUDD        = $4E      ; 1 = the HUD changed
FIRSTT      = $4F      ; 1 = first turn of the game
SHOWP       = $50      ; 1 = the intro before the garden
RR          = $51      ; first creature in the SAT (turns)
GF          = $52      ; frames of play
STREAK      = $53      ; seeds in a row (pitch of the tick)
STRT        = $54      ; frames since the last seed
TSUB        = $55      ; frames into the time unit
BALLT       = $56      ; ball: 2-frame units left
ACST        = $57      ; acorn: 0 waiting, 1 on the garden, 2 gone
PORTC       = $58      ; frames before a portal works again
SLIP        = $59      ; ice: frames the hedgehog still slides
PU          = $5A      ; point for ELEV
PV          = $5B
NU          = $5C      ; position tried by CAN_GO
NV          = $5D
CG_G        = $5E      ; CAN_GO: ground of the walker
CG_M        = $5F      ;         0 walking, 1 in the air (CG_A), 2 rolling

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
DU          = $72      ; step on U / V
DV          = $73
LDU         = $74      ; last step (ice)
LDV         = $75
CG_A        = $76      ; CAN_GO: height in the air
SLOT        = $77      ; creature being moved
CNT         = $78
BONL        = $79      ; bonus (BCD)
BONH        = $7A
HDR         = $7B      ; garden * 8 (header)
SONG        = $7C      ; tune to play (world)
JPTS        = $7D      ; 1 = this jump already scored a pine cone
PAUSED      = $7E
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HU          = $86      ; hedgehog: position on the garden (16 per cell)
HV          = $87
AH          = $88      ;           height in pixels (8.8)
AL          = $89
VZH         = $8A      ;           vertical speed (8.8, up = positive)
VZL         = $8B
AIR         = $8C      ;           1 = jumping or falling
GND         = $8D      ;           ground under the centre
FACE        = $8E      ;           0 right, 1 left
STEPS       = $8F      ;           steps walked (animation)
HX          = $90      ;           feet on the screen
HY          = $91
SX          = $92      ; screen position of a point (SCREEN_XY)
SY          = $93

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
CMD_START  = 2           ; the tune SONG

; ---------------- the garden ----------------
CELLS      = $0200       ; [v][u]: bit 7 void, 6 no seed in the centre, 4-5 ramp, 0-1 height
SLOTC      = $0240       ; seed of every cell: centre, u edge, v edge ($FF = none)
SLOTU      = $0280
SLOTV      = $02C0
MAXS       = 176
SU         = $0300       ; seeds: position, elevation
SV         = $03B0
SE         = $0460
SNL        = $0510       ; name table offset (lo / hi)
SNH        = $0740
SBARE      = $0AA0       ; tile without the seed
SALV       = $0B50       ; 1 = still there
NTB        = $0800       ; rows 2-22 of the name table (672 bytes)
XLAT       = $0C00       ; material colours -> colours of the world
PSAVE      = $0D00       ; 2 x 256: block of every player, seeds from +8

; ---------------- creatures: 0-1 magpies, 2 mole, 3 pine cone, 4 owl, 5 acorn
NOBJ       = 6
O_ST       = $0690       ; state (0 waiting)
O_U        = $0698       ; on the garden (mole, pine cone, acorn)
O_V        = $06A0
O_G        = $06A8       ; ground
O_A        = $06B0       ; height drawn (pine cone falling)
O_T        = $06B8       ; timer of the state (lo)
O_TH       = $06C0       ;                    (hi)
O_D        = $06C8       ; direction / face
O_X        = $06D0       ; on the screen (magpies, owl)
O_Y        = $06D8
O_TX       = $06E0       ; target on the screen
O_TY       = $06E8
O_S        = $06F0       ; seed of the magpie

K_MAG      = 0
K_MOLE     = 2
K_PINE     = 3
K_OWL      = 4
K_ACORN    = 5

SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
BTN_MASK    = %00110000
Y0          = 40         ; screen y of the back corner of the garden at height 0
TMAX        = 112        ; time units of a garden (14 tiles of the bar)

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
;  TITLE: the name, the creatures and what they do
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  LDA #$00                     ; big letters over the garden tiles of third 0
  STA T0
  LDA #$43
  STA T1
  LDA #<BIG_LEN
  STA T2
  LDA #>BIG_LEN
  STA T3
  LDA #<BIG_P
  STA PTR
  LDA #>BIG_P
  STA PTR+1
  JSR VCOPY
  LDA #$00
  STA T0
  LDA #$63
  STA T1
  LDA #<BIG_LEN
  STA T2
  LDA #>BIG_LEN
  STA T3
  LDA #<BIG_C
  STA PTR
  LDA #>BIG_C
  STA PTR+1
  JSR VCOPY
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
  LDX #$00                     ; the creatures (sprites)
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
  CPX #7
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

; one frame of the title: the hedgehog walks on the spot, the magpie flaps
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA FRAME_CNT
  AND #$08
  STA T0                       ; 0 or 8: the two steps
  LDA #PT_HOG
  CLC
  ADC T0
  STA SAT_BUFFER+2
  ADC #4
  STA SAT_BUFFER+6
  LSR T0
  LDA #PT_MAG
  CLC
  ADC T0
  STA SAT_BUFFER+10
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: garden 1, 3 lives for every player
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
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ GARDEN
  STZ LOOPN
  STZ GOTN
  LDA #$02                     ; first extra life at 20000
  STA NEXTX
  LDA #1
  STA FRESH
  LDA #TMAX
  STA TIMEU
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then a GARDEN
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE GARDEN_START
  INC SHOWP

GARDEN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR SET_GARDEN
  LDA FRESH
  BEQ .gs_old
  INC SHOWP                    ; a new garden: the intro
  LDA #TMAX
  STA TIMEU
  STZ GOTN
.gs_old:
  LDA SHOWP
  BEQ .gs_board
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT                   ; the tune of the world: first turn or first garden of a world
  BNE .gs_tune
  LDA FRESH
  BEQ .gs_short
  LDA GARDEN
  AND #3
  BNE .gs_short
.gs_tune:
  STZ FIRSTT
  LDA WORLD
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.gs_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .gs_t
  BRA .gs_w
.gs_short:
  LDA #120
  JSR WAIT_FRAMES
.gs_w:
  JSR VDP_INT_OFF
.gs_board:
  STZ SHOWP
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  JSR LOAD_TILES
  JSR DECODE_NT
  JSR SETUP_SEEDS
  STZ FRESH
  JSR DRAW_GARDEN
  JSR DRAW_TOP
  JSR DRAW_BOTTOM
  JSR START_CREATURES
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #40
  JSR WAIT_FRAMES


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
  AND #%00100000               ; button 2: pause
  BEQ .gl_np
  LDA JOYP
  AND #%00100000
  BNE .gl_np
  LDA PAUSED
  EOR #1
  STA PAUSED
.gl_np:
  LDA PAUSED
  BNE .gl_hud
  INC GF
  LDA GSTATE
  BNE .gl_stop
  JSR UPDATE_HOG
  JSR TAKE_SEEDS
  JSR PORTALS
  JSR UPDATE_TIME
  JSR UPDATE_CREATURES
  JSR COLLIDE
  BRA .gl_hud
.gl_stop:
  DEC GT                       ; caught: a short wait
.gl_hud:
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  CMP #3
  BNE .gl_lost
  JMP GARDEN_CLEAR
.gl_lost:
  LDA GT
  BNE GAME_LOOP
  JMP LOSE_LIFE


; ===============================================================
;  END OF A GARDEN
; ===============================================================
GARDEN_CLEAR:
  LDA #W_CLEAR
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_OFF
  LDX #NOBJ-1                  ; the creatures go away
.gc_e:
  STZ O_ST,X
  DEX
  BPL .gc_e
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #60
  JSR WAIT_FRAMES
  ; ---- bonus: 10 per seed taken by the hedgehog
  STZ BONL
  STZ BONH
  LDX GOTN
  SED
.gc_b:
  CPX #0
  BEQ .gc_d
  CLC
  LDA BONL
  ADC #$10
  STA BONL
  LDA BONH
  ADC #$00
  STA BONH
  DEX
  BRA .gc_b
.gc_d:
  CLD
  JSR VDP_INT_OFF
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA BONH
  JSR PUT_2
  LDA BONL
  JSR PUT_2
  LDA BONL
  STA PTS_L
  LDA BONH
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_FRAMES
  LDA #1                       ; the next garden
  STA FRESH
  INC GARDEN
  LDA GARDEN
  CMP #NGARDENS
  BCC .gc_n
  STZ GARDEN
  INC LOOPN
.gc_n:
  JMP GARDEN_START

LOSE_LIFE:
  LDX CURP
  DEC LIVES,X
  LDA TIMEU                    ; some time to get away from the owl
  CMP #40
  BCS .ll_t
  LDA #40
  STA TIMEU
.ll_t:
  JSR SAVE_PLAYER
  LDA #30
  JSR WAIT_FRAMES
  LDA NPL                      ; the other player, if he still has lives
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
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  LDA NPL
  CMP #2
  BNE .go_1
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.go_1:
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
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  JMP TITLE


; ===============================================================
;  GARDENS: world, difficulty, cells, colours, name table, seeds
; ===============================================================
SET_GARDEN:
  LDA GARDEN
  LSR A
  LSR A
  STA WORLD
  LDA LOOPN                    ; difficulty: garden / 2 + 8 per time round, at most 15
  ASL A
  ASL A
  ASL A
  STA T0
  LDA GARDEN
  LSR A
  CLC
  ADC T0
  CMP #16
  BCC .sg_d
  LDA #15
.sg_d:
  STA DIFF
  LDA GARDEN
  ASL A
  ASL A
  ASL A
  STA HDR
  LDA GARDEN                   ; the cells: G_CELLS + garden * 64
  LSR A
  LSR A
  CLC
  ADC #>G_CELLS
  STA PTR+1
  LDA GARDEN
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #<G_CELLS
  STA PTR
  BCC .sg_c
  INC PTR+1
.sg_c:
  LDY #63
.sg_l:
  LDA (PTR),Y
  STA CELLS,Y
  DEY
  BPL .sg_l
  LDA WORLD                    ; XLAT[m] = palette[m >> 4] << 4 | palette[m & 15]
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0
  LDX #0
.sg_x:
  TXA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T0
  TAY
  LDA WPAL,Y
  ASL A
  ASL A
  ASL A
  ASL A
  STA T1
  TXA
  AND #15
  ORA T0
  TAY
  LDA WPAL,Y
  ORA T1
  STA XLAT,X
  INX
  BNE .sg_x
  RTS

; rows 2-22 of the garden (RLE: 7, count, tile) into NTB
DECODE_NT:
  LDX GARDEN
  LDA G_NT_LO,X
  STA PTR
  LDA G_NT_HI,X
  STA PTR+1
  LDA #<NTB
  STA PTR2
  LDA #>NTB
  STA PTR2+1
  LDA #<672
  STA T2
  LDA #>672
  STA T3
.dn_l:
  LDA T2
  ORA T3
  BEQ .dn_e
  JSR .dn_get
  CMP #7
  BEQ .dn_run
  LDX #1
  BRA .dn_put
.dn_run:
  JSR .dn_get
  TAX
  JSR .dn_get
.dn_put:
  LDY #0
  STA (PTR2),Y
  INC PTR2
  BNE .dn_c
  INC PTR2+1
.dn_c:
  PHA
  LDA T2
  BNE .dn_d
  DEC T3
.dn_d:
  DEC T2
  PLA
  DEX
  BNE .dn_put
  BRA .dn_l
.dn_e:
  RTS
.dn_get:
  LDA (PTR)
  INC PTR
  BNE .dn_g
  INC PTR+1
.dn_g:
  RTS

; the seeds of the garden (same rule as the generator): the centre of every flat cell (unless
; bit 6), the middle of the edge with the flat cell of the same height at u+1 and at v+1.
; Records every seed; the alive ones get the tile with the seed in NTB
SETUP_SEEDS:
  STZ NSEED
  STZ LEFT
  LDX #0
.ss_c:
  LDA #$FF
  STA SLOTC,X
  STA SLOTU,X
  STA SLOTV,X
  LDA CELLS,X
  BMI .ss_n
  AND #$30
  BNE .ss_n
  LDA CELLS,X
  AND #$40
  BNE .ss_u
  LDA #0
  JSR ADD_SEED
  TYA
  STA SLOTC,X
.ss_u:
  TXA                          ; u < 7 and the cell at u+1 flat, same height
  AND #7
  CMP #7
  BEQ .ss_v
  LDA CELLS+1,X
  AND #$B3
  STA T0
  LDA CELLS,X
  AND #$03
  CMP T0
  BNE .ss_v
  LDA #1
  JSR ADD_SEED
  TYA
  STA SLOTU,X
.ss_v:
  CPX #56                      ; v < 7 and the cell at v+1
  BCS .ss_n
  LDA CELLS+8,X
  AND #$B3
  STA T0
  LDA CELLS,X
  AND #$03
  CMP T0
  BNE .ss_n
  LDA #2
  JSR ADD_SEED
  TYA
  STA SLOTV,X
.ss_n:
  INX
  CPX #64
  BNE .ss_c
  RTS

; A = kind (0 centre, 1 u edge, 2 v edge), X = cell -> Y = the new seed (keeps X)
ADD_SEED:
  STA T4
  LDY NSEED
  INC NSEED
  TXA
  AND #7
  STA T5                       ; u
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #8
  STA SU,Y
  TXA
  LSR A
  LSR A
  LSR A
  STA T6                       ; v
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #8
  STA SV,Y
  LDA T4
  CMP #1
  BNE .as_nu
  LDA SU,Y
  CLC
  ADC #8
  STA SU,Y
.as_nu:
  LDA T4
  CMP #2
  BNE .as_nv
  LDA SV,Y
  CLC
  ADC #8
  STA SV,Y
.as_nv:
  LDA CELLS,X
  AND #3
  STA T7                       ; h
  ASL A
  ASL A
  ASL A
  STA SE,Y
  LDA T5                       ; row = 5 + u + v - h (+1 on the edges)
  CLC
  ADC T6
  ADC #5
  SEC
  SBC T7
  LDY T4
  BEQ .as_r
  INC A
.as_r:
  STA T7                       ; row
  LDA T5                       ; column = 15 + 2 (u - v) (+1 on the u edge)
  SEC
  SBC T6
  ASL A
  CLC
  ADC #15
  CPY #1
  BNE .as_c
  INC A
.as_c:
  STA T0                       ; column
  LDA T7
  AND #7
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  LDY NSEED
  DEY
  STA SNL,Y
  LDA T7
  LSR A
  LSR A
  LSR A
  STA SNH,Y
  STA T1                       ; third
  CLC                          ; PTR = NTB - 64 + 256 * offset high
  ADC #>(NTB-64)
  STA PTR+1
  LDA #<(NTB-64)
  STA PTR
  LDA SNL,Y
  TAY
  LDA (PTR),Y
  STA T2                       ; bare tile
  LDA T1                       ; seed map of third * 3 + kind
  ASL A
  ADC T1
  ADC T4
  PHX
  TAX
  LDA SM_LO,X
  STA PTR2
  LDA SM_HI,X
  STA PTR2+1
  LDA (PTR2)                   ; pairs: bare tile, tile with the seed
  STA T3
  LDY #1
.as_f:
  LDA T3
  BEQ .as_nf
  LDA (PTR2),Y
  CMP T2
  BEQ .as_got
  INY
  INY
  DEC T3
  BRA .as_f
.as_nf:
  LDA T2                       ; not found (should not happen): no seed drawn
  BRA .as_s
.as_got:
  INY
  LDA (PTR2),Y
.as_s:
  STA T3                       ; tile with the seed
  PLX
  LDY NSEED
  DEY
  LDA T2
  STA SBARE,Y
  LDA FRESH
  BEQ .as_k
  LDA #1
  STA SALV,Y
.as_k:
  LDA SALV,Y
  BEQ .as_e
  INC LEFT
  PHY
  LDA SNL,Y
  TAY
  LDA T3
  STA (PTR),Y
  PLY
.as_e:
  RTS

; NTB to the name table, rows 2-22
DRAW_GARDEN:
  LDA #$40
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T1
  LDA #<672
  STA T2
  LDA #>672
  STA T3
  LDA #<NTB
  STA PTR
  LDA #>NTB
  STA PTR+1
  JMP VCOPY

; before a garden: player, world, garden
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
  LDX WORLD
  LDA WNAME_LO,X
  STA TP
  LDA WNAME_HI,X
  STA TP+1
  JSR PRINT
  LDA #<TXT_GARDEN
  STA TP
  LDA #>TXT_GARDEN
  STA TP+1
  JSR PRINT
  JSR PUT_WG
  LDX WORLD                    ; what is new in this world
  LDA WHINT_LO,X
  STA TP
  LDA WHINT_HI,X
  STA TP+1
  JMP PRINT

; "w-g" where the VDP points
PUT_WG:
  LDA WORLD
  CLC
  ADC #$31
  STA VDATA
  LDA #'-'
  STA VDATA
  LDA GARDEN
  AND #3
  CLC
  ADC #$31
  STA VDATA
  RTS


; ===============================================================
;  HUD: scores on rows 0-1, garden / lives / seeds / time on row 23
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
  LDA NPL
  CMP #2
  BNE .dt_r
  LDX #$01
  JMP DRAW_SCORE
.dt_r:
  RTS

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

; row 23: garden, spare lives, seeds left, time bar
DRAW_BOTTOM:
  LDX #23
  LDY #0
  JSR NT_XY
  JSR PUT_WG
  LDA #$20
  STA VDATA
  LDX CURP                     ; spare lives (at most 4)
  LDA LIVES,X
  BEQ .db_z
  DEC A
.db_z:
  STA T0
  LDX #0
.db_l:
  LDA #$20
  CPX T0
  BCS .db_b
  LDA #T_LIFE
.db_b:
  STA VDATA
  INX
  CPX #4
  BNE .db_l
  LDA #$20
  STA VDATA
  LDA #T_CRYS
  STA VDATA
  LDA LEFT                     ; seeds left, 3 digits
  JSR BIN2BCD3
  LDA T1
  ORA #$30
  STA VDATA
  LDA T0
  JSR PUT_2
  ; fall into DRAW_TIME

; the time bar: 14 tiles from column 18, one every 8 units
DRAW_TIME:
  LDX #23
  LDY #18
  JSR NT_XY
  LDA TIMEU
  STA T0
  LDX #14
.dm_l:
  LDA T0
  BEQ .dm_e
  CMP #8
  BCC .dm_z
  SBC #8
  STA T0
  LDA #T_BAR
  BRA .dm_p
.dm_z:
  STZ T0                       ; a part of a tile counts as full
  LDA #T_BAR
  BRA .dm_p
.dm_e:
  LDA #T_BARE
.dm_p:
  STA VDATA
  DEX
  BNE .dm_l
  RTS

; A (0-199) -> T1 hundreds, T0 tens and units (BCD)
BIN2BCD3:
  STZ T1
.b3_l:
  CMP #100
  BCC .b3_e
  SBC #100
  INC T1
  BRA .b3_l
.b3_e:
  JSR BIN2BCD
  STA T0
  RTS

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  LDX CURP
  JSR DRAW_SCORE
  JMP DRAW_BOTTOM
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: the block and the seeds
  LDA CURP
  CLC
  ADC #>PSAVE
  STA PTR+1
  STZ PTR
  LDY #PBLOCK-1
.sp_b:
  LDA GARDEN,Y
  STA (PTR),Y
  DEY
  BPL .sp_b
  LDA #8
  STA PTR
  LDY #MAXS-1
.sp_c:
  LDA SALV,Y
  STA (PTR),Y
  DEY
  CPY #$FF
  BNE .sp_c
  RTS

LOAD_PLAYER:                   ; X = player
  TXA
  CLC
  ADC #>PSAVE
  STA PTR+1
  STZ PTR
  LDY #PBLOCK-1
.lp_b:
  LDA (PTR),Y
  STA GARDEN,Y
  DEY
  BPL .lp_b
  LDA #8
  STA PTR
  LDY #MAXS-1
.lp_c:
  LDA (PTR),Y
  STA SALV,Y
  DEY
  CPY #$FF
  BNE .lp_c
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 20000, then every 40000
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
  INC LIVES,X
  SED
  LDA NEXTX
  CLC
  ADC #$04
  CLD
  BCC .as_x
  LDA #$FF                     ; past 960000: no more
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
;  THE GARDEN: elevation of a point, can a walker stand there
;  world: U, V = 0-127 (16 per cell); screen x = 128 + U - V,
;  y = Y0 + (U + V) / 2 - elevation
; ===============================================================
; elevation of PU, PV -> A, C = 1 outside or void (keeps X and Y; uses T0, T1)
ELEV:
  PHX
  LDA PU
  ORA PV
  BMI .el_v
  LDA PV
  AND #$70
  LSR A
  STA T0
  LDA PU
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T0
  TAX
  LDA CELLS,X
  BMI .el_v
  STA T1
  AND #3
  ASL A
  ASL A
  ASL A
  STA T0                       ; 8 * height
  LDA T1
  AND #$30
  BEQ .el_f
  CMP #$10
  BNE .el_w
  LDA PU                       ; ramp towards -u: + (15 - U & 15) / 2
  BRA .el_r
.el_w:
  LDA PV
.el_r:
  AND #15
  EOR #15
  LSR A
  CLC
  ADC T0
  PLX
  CLC
  RTS
.el_f:
  LDA T0
  PLX
  CLC
  RTS
.el_v:
  PLX
  SEC
  RTS

; can a walker stand at NU, NV? the 4 corners of its foot (+-3) must be on the garden and:
; CG_M 0 walking: within 3 of CG_G; 1 in the air: not above CG_A; 2 rolling: not above CG_G + 3
; C = 0 yes (keeps X)
CAN_GO:
  LDY #3
.cg_l:
  LDA NU
  CLC
  ADC FOOT_U,Y
  STA PU
  LDA NV
  CLC
  ADC FOOT_V,Y
  STA PV
  JSR ELEV
  BCS .cg_r
  STA T2
  LDA CG_M
  BEQ .cg_walk
  CMP #1
  BEQ .cg_air
  LDA T2                       ; rolling: any drop, up to 3 higher
  SEC
  SBC CG_G
  BCC .cg_n
  CMP #4
  BCS .cg_no
  BRA .cg_n
.cg_walk:
  LDA T2
  SEC
  SBC CG_G
  BCS .cg_p
  EOR #$FF
  INC A
.cg_p:
  CMP #4
  BCS .cg_no
  BRA .cg_n
.cg_air:
  LDA T2
  CMP CG_A                     ; elevation <= height: ok
  BEQ .cg_n
  BCS .cg_no
.cg_n:
  DEY
  BPL .cg_l
  CLC
.cg_r:
  RTS
.cg_no:
  SEC
  RTS

; PU, PV and A = elevation -> SX, SY on the screen (keeps X)
SCREEN_XY:
  STA T0
  LDA PU
  SEC
  SBC PV
  CLC
  ADC #128
  STA SX
  LDA PU
  CLC
  ADC PV
  ROR A
  CLC
  ADC #Y0
  SEC
  SBC T0
  STA SY
  RTS

; cell X -> PU, PV at its centre
CELL_CENTRE:
  TXA
  AND #7
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #8
  STA PU
  TXA
  AND #$38
  ASL A
  ORA #8
  STA PV
  RTS

; the cell of the hedgehog -> X
HOG_CELL:
  LDA HV
  AND #$70
  LSR A
  STA T0
  LDA HU
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T0
  TAX
  RTS


; ===============================================================
;  THE HEDGEHOG
; ===============================================================
UPDATE_HOG:
  LDA PORTC
  BEQ .uh_p
  DEC PORTC
.uh_p:
  LDA STRT
  INC A
  BEQ .uh_s
  STA STRT
.uh_s:
  LDA BALLT                    ; ball: 2-frame units, a rumble every 16 frames
  BEQ .uh_nb
  LDA GF
  AND #1
  BNE .uh_nb
  DEC BALLT
  LDA GF
  AND #15
  BNE .uh_nb
  LDA #S_ROLL
  LDX #0
  JSR SFX_BOOM
.uh_nb:
  JSR HOG_STEP
  LDA BALLT                    ; the ball goes twice as fast
  BEQ .uh_j
  JSR HOG_STEP
.uh_j:
  LDA AIR
  BNE .uh_air
  LDA GND                      ; walking: follow the ground (ramps)
  STA AH
  STZ AL
  LDA JOYC                     ; button 1 pressed now: jump
  AND #%00010000
  BEQ .uh_e
  LDA JOYP
  AND #%00010000
  BNE .uh_e
  LDA #1
  STA AIR
  STZ JPTS
  LDA #$02
  STA VZH
  LDA #$80
  STA VZL
  LDA #W_JUMP
  LDX #0
  JSR SFX_WHISTLE
  RTS
.uh_air:
  LDA AL                       ; height += speed, speed -= gravity
  CLC
  ADC VZL
  STA AL
  LDA AH
  ADC VZH
  STA AH
  LDA VZL
  SEC
  SBC #$40
  STA VZL
  LDA VZH
  SBC #0
  STA VZH
  BPL .uh_e                    ; still going up
  LDA AH                       ; coming down: landed?
  BMI .uh_land
  CMP GND
  BEQ .uh_land
  BCS .uh_e
.uh_land:
  LDA GND
  STA AH
  STZ AL
  STZ AIR
  LDA #S_HOP
  LDX #0
  JSR SFX_BOOM
.uh_e:
  RTS

; one step of the joystick (on ice the hedgehog slides on for a while)
HOG_STEP:
  LDA JOYC
  AND #15
  TAX
  LDA JOY_DU,X
  STA DU
  LDA JOY_DV,X
  STA DV
  ORA DU
  BNE .hs_go
  LDA SLIP                     ; nothing pressed: sliding on the ice?
  BNE .hs_sl
  RTS
.hs_sl:
  DEC SLIP
  LDA LDU
  STA DU
  LDA LDV
  STA DV
  BRA .hs_try
.hs_go:
  LDA DU
  STA LDU
  LDA DV
  STA LDV
  STZ SLIP
  LDA WORLD
  CMP #2
  BNE .hs_try
  LDA #14
  STA SLIP
.hs_try:
  LDA AIR                      ; rules of the walker: the hedgehog
  STA CG_M
  LDA GND
  STA CG_G
  LDA AH
  STA CG_A
  LDA HU                       ; the whole step
  CLC
  ADC DU
  STA NU
  LDA HV
  CLC
  ADC DV
  STA NV
  JSR CAN_GO
  BCC .hs_ok
  LDA DU                       ; blocked: one axis only (slides along the edges)
  BEQ .hs_stop
  LDA DV
  BEQ .hs_stop
  LDA HV
  STA NV
  JSR CAN_GO
  BCC .hs_ok
  LDA HU
  STA NU
  LDA HV
  CLC
  ADC DV
  STA NV
  JSR CAN_GO
  BCC .hs_ok
.hs_stop:
  STZ SLIP
  RTS
.hs_ok:
  LDA NU
  STA HU
  STA PU
  LDA NV
  STA HV
  STA PV
  INC STEPS
  JSR ELEV
  STA GND
  LDA AIR
  BNE .hs_f
  LDA GND
  STA AH
.hs_f:
  LDA DU                       ; facing: screen x = U - V
  SEC
  SBC DV
  BEQ .hs_r
  BMI .hs_fl
  STZ FACE
.hs_r:
  RTS
.hs_fl:
  LDA #1
  STA FACE
  RTS

; seeds within 4 of the centre, at the same height (on the ground only)
TAKE_SEEDS:
  LDA AIR
  BNE .ts_r
  JSR HOG_CELL
  LDA SLOTC,X
  JSR TRY_SEED
  LDA SLOTU,X
  JSR TRY_SEED
  LDA SLOTV,X
  JSR TRY_SEED
  LDA HU
  CMP #16
  BCC .ts_v
  LDA SLOTU-1,X
  JSR TRY_SEED
.ts_v:
  LDA HV
  CMP #16
  BCC .ts_r
  LDA SLOTV-8,X
  JMP TRY_SEED
.ts_r:
  RTS

; A = seed ($FF none): taken by the hedgehog if close (keeps X)
TRY_SEED:
  CMP #$FF
  BEQ .ty_r
  TAY
  LDA SALV,Y
  BEQ .ty_r
  LDA SU,Y
  SEC
  SBC HU
  CLC
  ADC #4
  CMP #9
  BCS .ty_r
  LDA SV,Y
  SEC
  SBC HV
  CLC
  ADC #4
  CMP #9
  BCS .ty_r
  LDA SE,Y
  CMP GND
  BNE .ty_r
  JSR TAKE_SEED
  INC GOTN
  LDA STRT                     ; ticks rising in a row (a second without seeds starts again)
  CMP #60
  BCC .ty_k
  STZ STREAK
.ty_k:
  STZ STRT
  LDA STREAK
  CLC
  ADC #W_SEED0
  PHX
  LDX #0
  JSR SFX_WHISTLE
  PLX
  LDA STREAK
  CMP #7
  BCS .ty_p
  INC STREAK
.ty_p:
  LDA #$10
  LDY #$00
  JSR ADD_PTS
  LDA LEFT
  BNE .ty_r
  LDA #$00                     ; the last seed: 500 and the garden is over
  LDY #$05
  JSR ADD_PTS
  LDA #3
  STA GSTATE
.ty_r:
  RTS

; Y = seed: off the garden (the tile without it)
TAKE_SEED:
  LDA #0
  STA SALV,Y
  DEC LEFT
  LDA SNL,Y
  STA VREG
  LDA SNH,Y
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA SBARE,Y
  STA VDATA
  LDA #1
  STA HUDD
  RTS

; portals: standing still in the middle of one takes the hedgehog to the other
PORTALS:
  LDA PORTC
  ORA AIR
  BNE .po_r
  LDY HDR
  LDA G_HDR+5,Y
  CMP #$FF
  BEQ .po_r
  LDA HU                       ; in the middle of the cell
  AND #15
  SEC
  SBC #5
  CMP #7
  BCS .po_r
  LDA HV
  AND #15
  SEC
  SBC #5
  CMP #7
  BCS .po_r
  JSR HOG_CELL
  TXA
  CMP G_HDR+5,Y
  BNE .po_b
  LDX G_HDR+6,Y
  BRA .po_go
.po_b:
  CMP G_HDR+6,Y
  BNE .po_r
  LDX G_HDR+5,Y
.po_go:
  JSR CELL_CENTRE
  LDA PU
  STA HU
  LDA PV
  STA HV
  JSR ELEV
  STA GND
  STA AH
  STZ SLIP
  LDA #120
  STA PORTC
  LDA #W_TELE
  LDX #2
  JMP SFX_WHISTLE
.po_r:
  RTS

; the time bar; when it is empty the owl comes
UPDATE_TIME:
  LDA TIMEU
  BEQ .ut_owl
  INC TSUB
  LDA #32
  SEC
  SBC DIFF
  CMP TSUB
  BCS .ut_r
  STZ TSUB
  DEC TIMEU
  LDA TIMEU
  AND #7
  BNE .ut_r
  LDA #1
  STA HUDD
  RTS
.ut_owl:
  LDA O_ST+K_OWL
  BNE .ut_r
  LDA #1
  STA O_ST+K_OWL
  LDA #128
  STA O_X+K_OWL
  LDA #4
  STA O_Y+K_OWL
  LDA #W_OWL
  LDX #1
  JMP SFX_WHISTLE
.ut_r:
  RTS


; ===============================================================
;  CREATURES
; ===============================================================
START_CREATURES:
  LDY HDR
  LDX G_HDR,Y                  ; the hedgehog on the start cell
  JSR CELL_CENTRE
  LDA PU
  STA HU
  LDA PV
  STA HV
  JSR ELEV
  STA GND
  STA AH
  STZ AL
  STZ AIR
  STZ FACE
  STZ STEPS
  STZ BALLT
  STZ SLIP
  STZ PORTC
  STZ GSTATE
  STZ PAUSED
  STZ STREAK
  STZ ACST
  LDA #$FF
  STA STRT
  STA JOYP                     ; no jump with the button still pressed
  LDX #NOBJ-1
.sc_l:
  STZ O_ST,X
  DEX
  BPL .sc_l
  LDA #150                     ; first magpie, second one only in the gardens that have it
  STA O_T+0
  LDA #255
  STA O_T+1
  LDA G_HDR+7,Y
  CMP #2
  BEQ .sc_m
  LDA #$FF
  STA O_ST+1
.sc_m:
  LDA #200
  STA O_T+K_MOLE
  LDA #120
  STA O_T+K_PINE
  LDA G_HDR+3,Y
  CMP #$FF
  BNE .sc_p
  LDA #$FF
  STA O_ST+K_PINE
.sc_p:
  RTS

UPDATE_CREATURES:
  LDX #0
  JSR MAGPIE
  LDX #1
  JSR MAGPIE
  LDX #K_MOLE
  JSR MOLE
  JSR PINE
  JSR OWL
  JMP ACORN

; ---- magpies: 0 waiting, 1 flying to a seed, 2 pecking, 3 flying away, $FF none
MAGPIE:
  LDA O_ST,X
  BMI .mg_r
  BNE .mg_1
  DEC O_T,X                    ; waiting
  BNE .mg_r
  JSR PICK_SEED
  BCC .mg_go
  LDA #30
  STA O_T,X
.mg_r:
  RTS
.mg_go:
  TYA
  STA O_S,X
  LDA SU,Y                     ; target: just above the seed
  STA PU
  LDA SV,Y
  STA PV
  LDA SE,Y
  JSR SCREEN_XY
  LDA SX
  STA O_TX,X
  LDA SY
  SEC
  SBC #7
  STA O_TY,X
  LDA #0                       ; in from a side, high up
  STA O_D,X
  LDA RND
  AND #$40
  BEQ .mg_s
  LDA #1
  STA O_D,X
  LDA #248
.mg_s:
  STA O_X,X
  LDA #20
  STA O_Y,X
  LDA #1
  STA O_ST,X
  LDA #W_MAG
  PHX
  LDX #1
  JSR SFX_WHISTLE
  PLX
  RTS
.mg_1:
  CMP #1
  BNE .mg_2
  LDY O_S,X                    ; flying: is the seed still there?
  LDA SALV,Y
  BNE .mg_f
  STZ O_ST,X
  LDA #1
  STA O_T,X
  RTS
.mg_f:
  JSR FLY_TO
  LDA DIFF
  CMP #8
  BCC .mg_a
  LDA GF
  AND #1
  BEQ .mg_a
  JSR FLY_TO
.mg_a:
  LDA O_X,X
  CMP O_TX,X
  BNE .mg_rr
  LDA O_Y,X
  CMP O_TY,X
  BEQ .mg_land
.mg_rr:
  RTS
.mg_land:
  LDA #2                       ; landed: pecking
  STA O_ST,X
  LDA DIFF
  ASL A
  ASL A
  STA T0
  LDA #120
  SEC
  SBC T0
  STA O_T,X
  RTS
.mg_2:
  CMP #2
  BNE .mg_3
  LDY O_S,X
  LDA SALV,Y
  BEQ .mg_away                 ; the hedgehog took it
  DEC O_T,X
  BNE .mg_rr
  JSR TAKE_SEED                ; stolen
  LDA #W_STEAL
  PHX
  LDX #1
  JSR SFX_WHISTLE
  PLX
  LDA LEFT
  BNE .mg_away
  LDA #3
  STA GSTATE
.mg_away:
  LDA #3
  STA O_ST,X
  RTS
.mg_3:
  LDA O_Y,X                    ; flying away: up and to its side
  SEC
  SBC #2
  STA O_Y,X
  BCC .mg_gone
  CMP #4
  BCC .mg_gone
  LDA O_D,X
  BNE .mg_l
  LDA O_X,X
  CLC
  ADC #2
  BCS .mg_gone
  STA O_X,X
  RTS
.mg_l:
  LDA O_X,X
  SEC
  SBC #2
  BCC .mg_gone
  STA O_X,X
  RTS
.mg_gone:
  STZ O_ST,X
  JSR NEXT_RND
  AND #63
  CLC
  ADC #160
  STA O_T,X
  RTS

; one pixel towards O_TX, O_TY on each axis; the face follows the x
FLY_TO:
  LDA O_X,X
  CMP O_TX,X
  BEQ .ft_y
  BCS .ft_l
  INC O_X,X
  STZ O_D,X
  BRA .ft_y
.ft_l:
  DEC O_X,X
  LDA #1
  STA O_D,X
.ft_y:
  LDA O_Y,X
  CMP O_TY,X
  BEQ .ft_r
  BCS .ft_u
  INC O_Y,X
  RTS
.ft_u:
  DEC O_Y,X
.ft_r:
  RTS

; a seed still there and far from the hedgehog -> Y, C = 0 (8 tries, keeps X)
PICK_SEED:
  LDA #8
  STA CNT
.pk_l:
  JSR NEXT_RND
.pk_m:
  CMP NSEED
  BCC .pk_t
  SBC NSEED
  BRA .pk_m
.pk_t:
  TAY
  LDA SALV,Y
  BEQ .pk_n
  LDA SU,Y                     ; far: |U - HU| + |V - HV| >= 40 (roughly)
  SEC
  SBC HU
  BCS .pk_a
  EOR #$FF
  INC A
.pk_a:
  STA T3
  LDA SV,Y
  SEC
  SBC HV
  BCS .pk_b
  EOR #$FF
  INC A
.pk_b:
  CLC
  ADC T3
  BCS .pk_ok
  CMP #40
  BCS .pk_ok
.pk_n:
  DEC CNT
  BNE .pk_l
  SEC
  RTS
.pk_ok:
  CLC
  RTS

; ---- mole: 0 waiting, 1 coming out, 2 chasing, 3 going back in
MOLE:
  LDA O_ST,X
  BNE .mo_1
  DEC O_T,X
  BNE .mo_r
  LDY HDR                      ; out of one of the holes
  LDA G_HDR+1,Y
  STA T4
  LDA G_HDR+2,Y
  CMP #$FF
  BEQ .mo_h
  LDA RND
  AND #$20
  BEQ .mo_h
  LDA G_HDR+2,Y
  STA T4
.mo_h:
  PHX
  LDX T4
  JSR CELL_CENTRE
  PLX
  LDA PU
  STA O_U,X
  LDA PV
  STA O_V,X
  JSR ELEV
  STA O_G,X
  LDA #1
  STA O_ST,X
  LDA #40
  STA O_T,X
  LDA #S_MOLE
  PHX
  LDX #1
  JSR SFX_BOOM
  PLX
.mo_r:
  RTS
.mo_1:
  CMP #2
  BEQ .mo_2
  DEC O_T,X                    ; coming out / going back in: harmless
  BNE .mo_r
  LDA O_ST,X
  CMP #3
  BEQ .mo_in
  LDA #2
  STA O_ST,X
  LDA DIFF
  ASL A
  ASL A
  ASL A
  CLC
  ADC #130
  STA O_T,X
  RTS
.mo_in:
  STZ O_ST,X
  LDA DIFF
  ASL A
  ASL A
  ASL A
  EOR #$FF
  SEC
  ADC #230
  STA O_T,X
  RTS
.mo_2:
  DEC O_T,X                    ; chasing
  BNE .mo_c
  LDA #3
  STA O_ST,X
  LDA #30
  STA O_T,X
  RTS
.mo_c:
  LDA DIFF                     ; every other frame until difficulty 8
  CMP #8
  BCS .mo_m
  LDA GF
  AND #1
  BNE .mo_r
.mo_m:
  STZ CG_M
  LDA O_G,X
  STA CG_G
  LDA HU                       ; one step towards the hedgehog on each axis
  CMP O_U,X
  BEQ .mo_du0
  LDA #1
  BCS .mo_du
  LDA #$FF
.mo_du:
  STA DU
  BRA .mo_dv
.mo_du0:
  STZ DU
.mo_dv:
  LDA HV
  CMP O_V,X
  BEQ .mo_dv0
  LDA #1
  BCS .mo_dv1
  LDA #$FF
.mo_dv1:
  STA DV
  BRA WALK_TRY
.mo_dv0:
  STZ DV
  ; fall into WALK_TRY

; a creature X walks by DU, DV with the rules of CG_M (or one axis of it); C = 0 moved
WALK_TRY:
  LDA O_U,X
  CLC
  ADC DU
  STA NU
  LDA O_V,X
  CLC
  ADC DV
  STA NV
  JSR CAN_GO
  BCC .wt_ok
  LDA DU
  BEQ .wt_no
  LDA DV
  BEQ .wt_no
  LDA O_V,X
  STA NV
  JSR CAN_GO
  BCC .wt_ok
  LDA O_U,X
  STA NU
  LDA O_V,X
  CLC
  ADC DV
  STA NV
  JSR CAN_GO
  BCC .wt_ok
.wt_no:
  SEC
  RTS
.wt_ok:
  LDA NU
  STA O_U,X
  STA PU
  LDA NV
  STA O_V,X
  STA PV
  JSR ELEV
  STA O_G,X
  CLC
  RTS

; ---- pine cone: 0 waiting, 1 rolling, $FF none
PINE:
  LDX #K_PINE
  LDA O_ST,X
  BMI .pn_r
  BNE .pn_1
  DEC O_T,X
  BNE .pn_r
  LDY HDR                      ; at the top of the garden
  PHX
  LDX G_HDR+3,Y
  JSR CELL_CENTRE
  PLX
  LDA PU
  STA O_U,X
  LDA PV
  STA O_V,X
  JSR ELEV
  STA O_G,X
  STA O_A,X
  JSR NEXT_RND
  AND #3
  STA O_D,X
  LDA #1
  STA O_ST,X
  LDA #250
  STA O_T,X
.pn_r:
  RTS
.pn_1:
  DEC O_T,X
  BNE .pn_roll
  STZ O_ST,X                   ; it breaks up
  LDA #150
  STA O_T,X
  LDA #S_POP
  LDX #1
  JMP SFX_BOOM
.pn_roll:
  JSR PINE_STEP
  LDA DIFF
  CMP #8
  BCC .pn_a
  LDA GF
  AND #1
  BEQ .pn_a
  JSR PINE_STEP
.pn_a:
  LDA O_A,X                    ; falls 2 pixels a frame to the ground
  SEC
  SBC #2
  BCC .pn_g
  CMP O_G,X
  BCS .pn_s
.pn_g:
  LDA O_G,X
.pn_s:
  STA O_A,X
  RTS

; one step straight on; blocked: a side (at random) or back
PINE_STEP:
  LDA #2
  STA CG_M
  LDA O_G,X
  STA CG_G
  LDY O_D,X
  JSR PINE_TRY
  BCC .ps_r
  LDA RND                      ; turn: left or right first
  AND #$10
  BEQ .ps_b
  LDA #3
  BRA .ps_c
.ps_b:
  LDA #1
.ps_c:
  STA T5
  LDA O_D,X
  CLC
  ADC T5
  AND #3
  TAY
  JSR PINE_TRY
  BCC .ps_n
  LDA O_D,X
  SEC
  SBC T5
  AND #3
  TAY
  JSR PINE_TRY
  BCC .ps_n
  LDA O_D,X
  EOR #2
  TAY
  JSR PINE_TRY
  BCS .ps_r
.ps_n:
  TYA
  STA O_D,X
  LDA #S_HOP
  PHX
  LDX #1
  JSR SFX_BOOM
  PLX
.ps_r:
  RTS

; Y = direction (0 +U, 1 +V, 2 -U, 3 -V): one step if it can (keeps X, Y)
PINE_TRY:
  STY T6
  LDA O_U,X
  CLC
  ADC PINE_DU,Y
  STA NU
  LDA O_V,X
  CLC
  ADC PINE_DV,Y
  STA NV
  JSR CAN_GO
  LDY T6
  BCS .pt_r
  LDA NU
  STA O_U,X
  STA PU
  LDA NV
  STA O_V,X
  STA PV
  JSR ELEV
  STA O_G,X
  CMP O_A,X                    ; up a ramp: at once
  BCC .pt_k
  STA O_A,X
.pt_k:
  LDY T6
  CLC
.pt_r:
  RTS

; ---- owl: 1 = hunting the hedgehog (from the empty time bar)
OWL:
  LDX #K_OWL
  LDA O_ST,X
  BEQ .ow_r
  LDA HX
  STA O_TX,X
  LDA HY
  SEC
  SBC #6
  STA O_TY,X
  LDA GF                       ; 3 frames out of 4, every frame from difficulty 8
  AND #3
  BNE .ow_m
  LDA DIFF
  CMP #8
  BCC .ow_r
.ow_m:
  JMP FLY_TO
.ow_r:
  RTS

; ---- golden acorn: on the garden from half the seeds, for a while
ACORN:
  LDX #K_ACORN
  LDA O_ST,X
  BNE .ac_1
  LDA ACST
  BNE .ac_r
  LDA LEFT
  ASL A
  BCS .ac_r
  CMP NSEED
  BEQ .ac_go
  BCS .ac_r
.ac_go:
  LDA #1
  STA ACST
  STA O_ST,X
  LDY HDR
  PHX
  LDX G_HDR+4,Y
  JSR CELL_CENTRE
  PLX
  LDA PU
  STA O_U,X
  LDA PV
  STA O_V,X
  JSR ELEV
  STA O_G,X
  LDA #0
  STA O_T,X
  LDA #W_ACORN
  LDX #2
  JMP SFX_WHISTLE
.ac_1:
  LDA GF                       ; about 8 seconds
  AND #1
  BNE .ac_r
  DEC O_T,X
  BNE .ac_r
  STZ O_ST,X
  LDA #2
  STA ACST
.ac_r:
  RTS


; ===============================================================
;  COLLISIONS
; ===============================================================
COLLIDE:
  LDX #0                       ; magpies: scared away (ball too)
.co_m:
  LDA O_ST,X
  BEQ .co_mn
  CMP #3
  BCS .co_mn
  LDA O_X,X
  SEC
  SBC HX
  CLC
  ADC #10
  CMP #21
  BCS .co_mn
  LDA HY
  SEC
  SBC #6
  SEC
  SBC O_Y,X
  CLC
  ADC #10
  CMP #21
  BCS .co_mn
  LDA #3
  STA O_ST,X
  LDA #W_SCARE
  PHX
  LDX #0
  JSR SFX_WHISTLE
  PLX
  LDA #$00
  LDY #$02
  JSR ADD_PTS
.co_mn:
  INX
  CPX #2
  BNE .co_m
  ; ---- mole (chasing)
  LDX #K_MOLE
  LDA O_ST,X
  CMP #2
  BNE .co_p
  LDA #7
  JSR NEAR_HOG
  BCS .co_p
  LDA BALLT
  BEQ .co_die
  STZ O_ST,X                   ; the ball beats it
  LDA #255
  STA O_T,X
  JSR HIT_PTS
.co_p:
  LDX #K_PINE                  ; ---- pine cone: deadly, but jumped over for 50
  LDA O_ST,X
  CMP #1
  BNE .co_o
  LDA #6
  JSR NEAR_UV
  BCS .co_o
  LDA AH
  SEC
  SBC O_A,X
  BCS .co_up
  CMP #$FB                     ; it is 6 or more above the hedgehog: no touch
  BCC .co_o
  BRA .co_ph
.co_up:
  CMP #6
  BCC .co_ph
  LDA AIR                      ; above it
  BEQ .co_o
  LDA JPTS
  BNE .co_o
  INC JPTS
  LDA #$50
  LDY #$00
  JSR ADD_PTS
  BRA .co_o
.co_ph:
  LDA BALLT
  BEQ .co_die
  STZ O_ST,X
  LDA #150
  STA O_T,X
  JSR HIT_PTS
.co_o:
  LDX #K_OWL                   ; ---- owl: always deadly
  LDA O_ST,X
  BEQ .co_a
  LDA O_X,X
  SEC
  SBC HX
  CLC
  ADC #7
  CMP #15
  BCS .co_a
  LDA HY
  SEC
  SBC #6
  SEC
  SBC O_Y,X
  CLC
  ADC #7
  CMP #15
  BCS .co_a
.co_die:
  LDA #1                       ; caught
  STA GSTATE
  LDA #100
  STA GT
  STZ BALLT
  LDA #W_DIE
  LDX #2
  JMP SFX_WHISTLE
.co_a:
  LDX #K_ACORN                 ; ---- golden acorn: the ball
  LDA O_ST,X
  BEQ .co_r
  LDA #7
  JSR NEAR_HOG
  BCS .co_r
  STZ O_ST,X
  LDA #2
  STA ACST
  LDA #180
  STA BALLT
  LDA #W_ACORN
  LDX #2
  JSR SFX_WHISTLE
  LDA #$00
  LDY #$01
  JMP ADD_PTS
.co_r:
  RTS

; creature X within A on U and V of the hedgehog -> C = 0
NEAR_UV:
  STA T3
  ASL A
  STA T4
  DEC T4                       ; |d| < A  <=>  d + A - 1 < 2A - 1
  LDA O_U,X
  SEC
  SBC HU
  CLC
  ADC T3
  DEC A
  CMP T4
  BCS .nu_r
  LDA O_V,X
  SEC
  SBC HV
  CLC
  ADC T3
  DEC A
  CMP T4
.nu_r:
  RTS

; as NEAR_UV and also at about the same height (within 6) -> C = 0
NEAR_HOG:
  JSR NEAR_UV
  BCS .nh_r
  LDA AH
  SEC
  SBC O_G,X
  CLC
  ADC #6
  CMP #13
.nh_r:
  RTS

HIT_PTS:
  LDA #W_HIT
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
  LDA #$00
  LDY #$03
  JMP ADD_PTS


; ===============================================================
;  SPRITES: the hedgehog first, then the creatures taking turns
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA HU                       ; feet on the screen
  STA PU
  LDA HV
  STA PV
  LDA AH
  JSR SCREEN_XY
  LDA SX
  STA HX
  STA OX
  LDA SY
  STA HY
  SEC
  SBC #4
  STA OY
  LDA GSTATE
  CMP #1
  BNE .bs_live
  LDA GT                       ; caught: upside down, flashing
  AND #4
  BEQ .bs_sh
  LDA #PT_DEAD
  BRA .bs_h
.bs_live:
  LDA BALLT
  BEQ .bs_walk
  CMP #30                      ; the ball flashes before it ends
  BCS .bs_ball
  LDA GF
  AND #4
  BEQ .bs_walk
.bs_ball:
  LDA GF
  AND #4
  ASL A
  CLC
  ADC #PT_BALL
  BRA .bs_h
.bs_walk:
  LDA STEPS
  LSR A
  LSR A
  LSR A
  AND #1
  STA T0
  LDA FACE
  ASL A
  ORA T0
  ASL A
  ASL A
  ASL A
.bs_h:
  STA ON
  LDA #$0E
  STA OC
  JSR ADD_SPR
  LDA ON
  CLC
  ADC #4
  STA ON
  LDA #$09
  STA OC
  JSR ADD_SPR
.bs_sh:
  LDA AIR                      ; shadow on the ground while jumping
  BEQ .bs_c
  LDA GND
  JSR SCREEN_XY
  LDA SY
  SEC
  SBC #4
  STA OY
  LDA #PT_SHADOW
  STA ON
  LDA #$01
  STA OC
  JSR ADD_SPR
.bs_c:
  INC RR                       ; the creatures, from a different one every frame
  LDA RR
  CMP #NOBJ
  BCC .bs_rr
  STZ RR
.bs_rr:
  LDA RR
  STA SLOT
  LDA #NOBJ
  STA CNT
.bs_l:
  LDX SLOT
  JSR DRAW_CREATURE
  INC SLOT
  LDA SLOT
  CMP #NOBJ
  BCC .bs_n
  STZ SLOT
.bs_n:
  DEC CNT
  BNE .bs_l
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; creature X into the SAT
DRAW_CREATURE:
  LDA O_ST,X
  BEQ .dc_x
  BPL .dc_go
.dc_x:
  RTS
.dc_go:
  CPX #K_MOLE
  BCC .dc_mag
  BEQ .dc_mole
  CPX #K_OWL
  BCC .dc_pine
  BNE .dc_acx
  JMP .dc_owl
.dc_acx:
  ; acorn: flashing gold
  JSR .dc_uvg
  LDA #PT_ACORN
  STA ON
  LDA GF
  AND #8
  BEQ .dc_ac
  LDA #$0B
  JMP .dc_put
.dc_ac:
  LDA #$0A
  JMP .dc_put
.dc_mag:
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
  LDA O_D,X                    ; face * 12 + frame * 4
  ASL A
  ADC O_D,X
  ASL A
  ASL A
  STA T0
  LDA O_ST,X
  CMP #2
  BNE .dc_fl
  LDA #8
  BRA .dc_mf
.dc_fl:
  LDA GF
  AND #8
  LSR A
.dc_mf:
  CLC
  ADC T0
  ADC #PT_MAG
  STA ON
  LDA #$0F
  BRA .dc_put
.dc_mole:
  JSR .dc_uvg
  LDA #PT_MOLE
  LDY O_ST,X
  CPY #2
  BNE .dc_mo
  LDA GF
  AND #8
  LSR A
  CLC
  ADC #PT_MOLE+4
.dc_mo:
  STA ON
  LDA #$01
  BRA .dc_put
.dc_pine:
  LDA O_U,X
  STA PU
  LDA O_V,X
  STA PV
  LDA O_A,X
  JSR SCREEN_XY
  LDA SX
  STA OX
  LDA SY
  SEC
  SBC #6
  STA OY
  LDA GF
  AND #4
  CLC
  ADC #PT_PINE
  STA ON
  LDA #$06
  BRA .dc_put
.dc_owl:
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
  LDA GF
  AND #8
  LSR A
  CLC
  ADC #PT_OWL
  STA ON
  LDA #$0A
.dc_put:
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.dc_r:
  RTS
; on the garden: feet at O_U, O_V, O_G
.dc_uvg:
  LDA O_U,X
  STA PU
  LDA O_V,X
  STA PV
  LDA O_G,X
  JSR SCREEN_XY
  LDA SX
  STA OX
  LDA SY
  SEC
  SBC #5
  STA OY
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

; the table GFX_LOAD (font, small tiles) then the sprites
LOAD_GFX:
  JSR CLEAR_VRAM
  LDA #<GFX_LOAD
  STA PTR2
  LDA #>GFX_LOAD
  STA PTR2+1
  JSR LOAD_BLOCKS
  JMP LOAD_SPRITES

; the tiles of the garden in the colours of the world (XLAT built by SET_WORLD)
LOAD_TILES:
  LDA #<TILE_LOAD
  STA PTR2
  LDA #>TILE_LOAD
  STA PTR2+1
  ; fall into LOAD_BLOCKS

; blocks at PTR2: kind (0 end, 1 copy, 2 fill, 3 copy through XLAT), address, length, source / value
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
  BCS .lb_x
  JSR VCOPY
  BRA LOAD_BLOCKS
.lb_f:
  LDA PTR
  JSR VFILL
  BRA LOAD_BLOCKS
.lb_x:
  JSR VCOPY_X
  BRA LOAD_BLOCKS
.lb_e:
  RTS

; as VCOPY, every byte through XLAT (material colours -> colours of the world)
VCOPY_X:
  LDA T0
  STA VREG
  LDA T1
  STA VREG
  LDY #$00
.vx_l:
  LDA (PTR),Y
  TAX
  LDA XLAT,X
  STA VDATA
  INY
  BNE .vx_y
  INC PTR+1
.vx_y:
  LDA T2
  BNE .vx_d
  DEC T3
.vx_d:
  DEC T2
  LDA T2
  ORA T3
  BNE .vx_l
  RTS

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
;  SOUND: the tunes of the worlds (4 tracks, from tank) and the effects
;  per chip in game: A = tone effects, B = noise and C = low tone
;  of the explosions; left chip = the hedgehog, right = the creatures
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

; joystick (bit 0 up, 1 down, 2 left, 3 right) -> step on U and V:
; up = (-1,-1), down = (1,1), left = (-1,1), right = (1,-1), up right = -V, up left = -U ...
JOY_DU:     .byte 0,-1,1,0,-1,-1,0,0,1,0,1,0,0,0,0,0
JOY_DV:     .byte 0,-1,1,0,1,0,1,0,-1,-1,0,0,0,0,0,0
; the 4 corners of a foot
FOOT_U:     .byte 3,-3,3,-3
FOOT_V:     .byte 3,3,-3,-3
; pine cone: 0 +U, 1 +V, 2 -U, 3 -V
PINE_DU:    .byte 1,0,-1,0
PINE_DV:    .byte 0,1,0,-1

; title: hedgehog (2 layers), magpie, mole, pine cone, owl, acorn  (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 11*8-5,11*8-5,13*8-5,15*8-5,17*8-5,19*8-5,21*8-5
TITLE_SX:   .byte 24,24,24,24,24,24,24
TITLE_SN:   .byte PT_HOG,PT_HOG+4,PT_MAG,PT_MOLE+4,PT_PINE,PT_OWL,PT_ACORN
TITLE_SC:   .byte $0E,$09,$0F,$0E,$06,$0A,$0B

WNAME_LO:   .byte <TXT_W0,<TXT_W1,<TXT_W2,<TXT_W3
WNAME_HI:   .byte >TXT_W0,>TXT_W1,>TXT_W2,>TXT_W3
WHINT_LO:   .byte <TXT_H0,<TXT_H1,<TXT_H2,<TXT_H3
WHINT_HI:   .byte >TXT_H0,>TXT_H1,>TXT_H2,>TXT_H3

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 9,3,"PICK UP EVERY CRYSTAL SEED",0
  .byte 11,6,"HEDGEHOG  B1 = JUMP",0
  .byte 13,6,"MAGPIE    STEALS SEEDS",0
  .byte 15,6,"MOLE      LEAVES ITS HOLE",0
  .byte 17,6,"PINE CONE JUMP OVER IT",0
  .byte 19,6,"OWL       COMES IN LATE",0
  .byte 21,6,"ACORN     ROLL INTO A BALL",0
  .byte 23,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_PLAYER:
  .byte 6,12,"PLAYER ",0
  .byte $FF
TXT_GARDEN:
  .byte 13,12,"GARDEN ",0
  .byte $FF
TXT_H0:
  .byte 17,4,"MIND THE MAGPIES AND MOLE",0
  .byte $FF
TXT_H1:
  .byte 17,4,"PINE CONES ROLL DOWN HERE",0
  .byte $FF
TXT_H2:
  .byte 17,5,"THE ICE MAKES YOU SLIDE",0
  .byte $FF
TXT_H3:
  .byte 17,3,"STOP ON A PORTAL TO TRAVEL",0
  .byte $FF
TXT_BONUS:
  .byte 23,0,"      BONUS ",0
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

; song * 4 + track
SONGP_LO:      .byte <W0_LEAD,<W0_HARM,<W0_BASS,<W0_DRUM, <W1_LEAD,<W1_HARM,<W1_BASS,<W1_DRUM
               .byte <W2_LEAD,<W2_HARM,<W2_BASS,<W2_DRUM, <W3_LEAD,<W3_HARM,<W3_BASS,<W3_DRUM
SONGP_HI:      .byte >W0_LEAD,>W0_HARM,>W0_BASS,>W0_DRUM, >W1_LEAD,>W1_HARM,>W1_BASS,>W1_DRUM
               .byte >W2_LEAD,>W2_HARM,>W2_BASS,>W2_DRUM, >W3_LEAD,>W3_HARM,>W3_BASS,>W3_DRUM

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

; four tunes composed for this game, one per world (about 3 seconds each)
;   C3 13 D3 15 E3 17 F3 18 G3 20 A3 22 B3 24  C4 25 D4 27 E4 29 F4 30 G4 32 A4 34 B4 36
;   C5 37 D5 39 E5 41 F5 42 G5 44 A5 46 B5 48  C6 49
; orchard: a skipping tune in G major
W0_LEAD:
  .byte 39,8, 44,8, 48,8, 44,8, 46,8, 42,8, 39,16
  .byte 41,8, 44,8, 46,8, 48,8, 44,24, 0,8
  .byte $FF
W0_HARM:
  .byte 32,32, 30,32, 29,32, 32,32
  .byte $FF
W0_BASS:
  .byte 8,16, 15,16, 3,16, 10,16, 5,16, 12,16, 8,32
  .byte $FF
W0_DRUM:
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,16, 4,16
  .byte $FF
; dunes: A minor, slow and swaying
W1_LEAD:
  .byte 34,12, 37,6, 39,6, 41,12, 39,12, 37,12, 36,6, 34,6, 32,24
  .byte 34,12, 41,12, 39,24, 34,24
  .byte $FF
W1_HARM:
  .byte 29,48, 27,48, 25,48, 29,48
  .byte $FF
W1_BASS:
  .byte 10,24, 17,24, 8,24, 15,24, 6,24, 13,24, 10,48
  .byte $FF
W1_DRUM:
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,12, 3,12, 2,12, 3,12, 1,24, 4,24
  .byte $FF
; ice house: E minor, high and glassy
W2_LEAD:
  .byte 41,6, 48,6, 53,6, 48,6, 46,6, 48,6, 41,12
  .byte 44,6, 48,6, 51,6, 48,6, 46,12, 44,12
  .byte 41,6, 44,6, 48,6, 53,6, 51,24, 0,8
  .byte $FF
W2_HARM:
  .byte 36,24, 34,24, 32,24, 34,24, 36,32
  .byte $FF
W2_BASS:
  .byte 5,24, 12,24, 1,24, 8,24, 5,32
  .byte $FF
W2_DRUM:
  .byte 3,6, 3,6, 2,12, 3,6, 3,6, 2,12, 3,6, 3,6, 2,12, 3,6, 3,6, 2,12
  .byte 3,6, 3,6, 2,12, 4,24
  .byte $FF
; night garden: D minor, quiet steps
W3_LEAD:
  .byte 39,16, 42,8, 46,8, 44,16, 42,16, 41,8, 42,8, 39,16, 0,16
  .byte 37,16, 39,24, 0,8
  .byte $FF
W3_HARM:
  .byte 30,32, 29,32, 27,32, 29,32, 30,24
  .byte $FF
W3_BASS:
  .byte 3,16, 3,16, 10,16, 10,16, 6,16, 8,16, 3,32, 3,24
  .byte $FF
W3_DRUM:
  .byte 1,16, 3,16, 1,16, 3,16, 1,16, 3,16, 1,16, 3,16, 1,16, 4,24
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
; Crystal Gardens: generated by dev/gen_crystal_gardens.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_HOG = 0
PT_BALL = 32
PT_DEAD = 48
PT_SHADOW = 56
PT_MAG = 60
PT_MOLE = 84
PT_PINE = 96
PT_OWL = 104
PT_ACORN = 112
PT_SPARK = 116
SPR_PAGES = 4
SPRITES:
  .byte $00,$02,$17,$2F,$7F,$FF,$7F,$FF,$7F,$FF,$7F,$3F,$00,$00,$00,$00
  .byte $00,$80,$D0,$F0,$F8,$F8,$F8,$F8,$F1,$F0,$E0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$18,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$06,$07,$0A,$0F,$1C,$18,$E0,$30,$00,$00
  .byte $00,$02,$17,$2F,$7F,$FF,$7F,$FF,$7F,$FF,$7F,$3F,$00,$00,$00,$00
  .byte $00,$80,$D0,$F0,$F8,$F8,$F8,$F8,$F1,$F0,$E0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$06,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$06,$07,$0A,$0F,$1C,$18,$E0,$60,$00,$00
  .byte $00,$01,$0B,$0F,$1F,$1F,$1F,$1F,$8F,$0F,$07,$07,$00,$00,$00,$00
  .byte $00,$40,$E8,$F4,$FE,$FF,$FE,$FF,$FE,$FF,$FE,$FC,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$E0,$50,$F0,$38,$18,$07,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$18,$00,$00
  .byte $00,$01,$0B,$0F,$1F,$1F,$1F,$1F,$8F,$0F,$07,$07,$00,$00,$00,$00
  .byte $00,$40,$E8,$F4,$FE,$FF,$FE,$FF,$FE,$FF,$FE,$FC,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$E0,$50,$F0,$38,$18,$07,$06,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$60,$00,$00
  .byte $00,$02,$06,$03,$37,$3F,$1F,$1F,$7F,$1F,$1F,$3F,$37,$03,$06,$02
  .byte $00,$40,$60,$C0,$EC,$FC,$F8,$88,$8E,$88,$F8,$FC,$EC,$C0,$60,$40
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$70,$70,$70,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$06,$03,$37,$3F,$1F,$1F,$7F,$1F,$1E,$3E,$37,$03,$06,$02
  .byte $00,$40,$60,$C0,$EC,$FC,$F8,$F8,$FE,$38,$18,$3C,$2C,$C0,$60,$40
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$C0,$C0,$00,$00,$00
  .byte $00,$00,$00,$00,$3F,$7F,$FF,$7F,$FF,$7F,$FF,$7F,$2F,$17,$02,$00
  .byte $00,$00,$00,$00,$E0,$E0,$F0,$F1,$F8,$F8,$F8,$F8,$F0,$D0,$80,$00
  .byte $00,$00,$18,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$30,$E0,$18,$1C,$0F,$0A,$07,$06,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$1F,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$FC,$F8,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$7F,$3F,$1F,$0C,$00,$00,$00,$00,$00
  .byte $00,$00,$18,$3C,$2E,$3C,$78,$E0,$F0,$F0,$E0,$30,$00,$00,$00,$00
  .byte $00,$0E,$07,$03,$01,$80,$C0,$7F,$3F,$1F,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$8C,$DE,$EE,$FC,$78,$E0,$F0,$F0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$18,$3C,$7F,$7F,$3F,$0F,$06,$05,$08,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F0,$EC,$1E,$17,$86,$00,$00
  .byte $00,$00,$18,$3C,$74,$3C,$1E,$07,$0F,$0F,$07,$0C,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$FE,$FC,$F8,$30,$00,$00,$00,$00,$00
  .byte $00,$00,$31,$7B,$77,$3F,$1E,$07,$0F,$0F,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$E0,$C0,$80,$01,$03,$FE,$FC,$F8,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$07,$0F,$37,$78,$E8,$61,$00,$00
  .byte $00,$00,$00,$00,$00,$18,$3C,$FE,$FE,$FC,$F0,$60,$A0,$10,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0F,$1B,$3F,$78,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$F0,$D8,$FC,$1E,$00
  .byte $00,$00,$00,$00,$00,$07,$0F,$1F,$1B,$1F,$3E,$3F,$7F,$6F,$48,$00
  .byte $00,$00,$00,$00,$00,$E0,$F0,$F8,$D8,$F8,$7C,$FC,$FE,$F6,$12,$00
  .byte $00,$00,$00,$00,$00,$07,$0F,$1F,$1B,$1F,$3E,$3F,$7F,$37,$28,$00
  .byte $00,$00,$00,$00,$00,$E0,$F0,$F8,$D8,$F8,$7C,$FC,$FE,$EC,$14,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$0D,$0F,$1F,$1F,$0F,$0D,$03,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$B0,$F0,$F8,$F8,$F0,$B0,$C0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$0F,$0B,$1F,$1F,$0B,$0F,$03,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$F0,$D0,$F8,$F8,$D0,$F0,$C0,$00,$00
  .byte $20,$30,$3F,$67,$5B,$5B,$67,$3F,$3F,$BF,$DF,$EF,$7B,$3F,$0A,$00
  .byte $04,$0C,$FC,$E6,$DA,$DA,$E6,$7C,$FC,$FD,$FB,$F7,$DE,$FC,$50,$00
  .byte $20,$30,$3F,$67,$5B,$5B,$67,$3F,$3F,$3F,$5F,$AF,$B7,$3F,$0A,$00
  .byte $04,$0C,$FC,$E6,$DA,$DA,$E6,$7C,$FC,$FC,$FA,$F5,$ED,$FC,$50,$00
  .byte $00,$01,$01,$1F,$3F,$35,$1F,$0F,$0F,$0F,$07,$03,$01,$00,$00,$00
  .byte $00,$80,$00,$F8,$FC,$AC,$F8,$F0,$F0,$F0,$E0,$C0,$80,$00,$00,$00
  .byte $00,$01,$01,$11,$09,$04,$00,$70,$00,$04,$09,$11,$01,$01,$00,$00
  .byte $00,$00,$00,$10,$20,$40,$00,$1C,$00,$40,$20,$10,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

T_LIFE = 1
T_BAR = 2
T_BARE = 3
T_CRYS = 4
SMALL_PAT:
  .byte $00,$28,$7C,$FC,$FE,$7A,$24,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00
  .byte $00,$FF,$81,$81,$81,$81,$FF,$00,$10,$38,$7C,$FE,$7C,$38,$10,$00
SMALL_COL:
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $40,$40,$40,$40,$40,$40,$40,$40,$70,$70,$70,$70,$70,$70,$70,$70
GT0_NLO = 24
GT0_NHI = 73
GT0_PLO:
  .byte $00,$00,$00,$00,$00,$02,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$00,$00,$00,$00
  .byte $80,$E0,$F8,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$01,$03,$07,$0F,$1F,$3F,$7F,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$07,$1F,$7F,$00,$06,$06,$00,$00,$00,$00,$03,$03,$00,$00,$00
  .byte $00,$00,$00,$C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$00,$00,$00,$00
GT0_CLO:
  .byte $00,$00,$00,$00,$00,$10,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$00
  .byte $00,$00,$00,$00,$30,$30,$30,$30,$30,$30,$30,$30,$03,$03,$03,$03
  .byte $30,$30,$30,$30,$03,$03,$03,$03,$00,$00,$00,$00,$30,$30,$30,$30
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$73,$73,$37,$37
  .byte $73,$73,$37,$37,$07,$07,$07,$07,$63,$63,$36,$36,$06,$06,$06,$06
  .byte $03,$03,$03,$03,$63,$63,$36,$36,$80,$80,$80,$80,$80,$80,$80,$08
  .byte $83,$83,$38,$38,$08,$08,$08,$08,$03,$03,$03,$03,$83,$83,$38,$38
  .byte $07,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $30,$30,$30,$30,$03,$93,$93,$03,$03,$03,$03,$93,$93,$03,$03,$03
  .byte $03,$03,$03,$93,$93,$03,$03,$03,$03,$03,$03,$03,$03,$93,$93,$03
  .byte $00,$00,$00,$00,$40,$40,$40,$40,$40,$40,$40,$40,$04,$04,$04,$04
GT0_PHI:
  .byte $80,$E0,$F8,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$03,$07,$F0,$E0,$C0,$80,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$01,$07,$1F,$7F,$00,$06,$06,$00
  .byte $00,$00,$00,$03,$03,$00,$00,$00,$00,$00,$00,$C0,$C0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$06,$06,$00,$01,$07,$E0,$80,$00,$06,$06,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$01,$03,$07,$0F,$1F,$C0,$80,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$00,$00,$00,$00
  .byte $80,$E0,$F8,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$01,$03,$07,$0F,$E0,$C0,$80,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $01,$07,$1F,$7F,$00,$06,$06,$00,$00,$00,$00,$03,$03,$00,$00,$00
  .byte $00,$00,$00,$C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$00
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$01,$07,$E0,$80,$00,$06,$06,$00
  .byte $01,$07,$1F,$7F,$01,$07,$1E,$78,$80,$E0,$F8,$FE,$80,$E0,$78,$1E
  .byte $78,$1E,$07,$01,$00,$00,$00,$00,$1E,$78,$E0,$80,$00,$00,$00,$00
  .byte $1E,$78,$E0,$03,$03,$00,$00,$00,$78,$1E,$07,$C0,$C0,$00,$00,$00
  .byte $01,$03,$07,$0F,$E0,$C0,$80,$00,$01,$07,$1F,$7F,$01,$07,$1E,$78
  .byte $80,$E0,$F8,$FE,$80,$E0,$78,$1E,$78,$1E,$07,$01,$80,$E0,$07,$01
  .byte $1E,$78,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$1E,$78,$E0,$03,$03,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$1E,$78,$80,$E0,$F8,$FE,$80,$E0,$78,$1E
  .byte $78,$1E,$07,$01,$80,$E0,$07,$01,$1E,$78,$E0,$80,$01,$07,$E0,$80
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00
GT0_CHI:
  .byte $40,$40,$40,$40,$04,$04,$04,$04,$00,$00,$00,$00,$40,$40,$40,$40
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$84,$84,$48,$48,$08,$08,$08,$08
  .byte $04,$04,$04,$04,$84,$84,$48,$48,$04,$04,$04,$04,$74,$74,$47,$47
  .byte $74,$74,$47,$47,$07,$07,$07,$07,$64,$64,$46,$46,$06,$06,$06,$06
  .byte $04,$04,$04,$04,$64,$64,$46,$46,$08,$08,$08,$08,$08,$08,$08,$08
  .byte $08,$78,$78,$78,$87,$87,$87,$87,$06,$06,$06,$06,$46,$46,$64,$64
  .byte $46,$46,$64,$64,$04,$04,$04,$04,$38,$38,$83,$83,$03,$03,$03,$03
  .byte $08,$08,$08,$08,$38,$38,$83,$83,$07,$07,$07,$07,$47,$47,$74,$74
  .byte $47,$47,$74,$74,$04,$04,$04,$04,$40,$40,$40,$40,$04,$94,$94,$04
  .byte $04,$04,$04,$94,$94,$04,$04,$04,$04,$04,$04,$94,$94,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$94,$94,$04,$46,$46,$64,$64,$04,$94,$94,$04
  .byte $47,$47,$74,$74,$04,$94,$94,$04,$80,$80,$80,$80,$80,$38,$38,$08
  .byte $00,$00,$00,$00,$50,$50,$50,$50,$50,$50,$50,$50,$05,$05,$05,$05
  .byte $50,$50,$50,$50,$05,$05,$05,$05,$00,$00,$00,$00,$50,$50,$50,$50
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$85,$85,$58,$58,$08,$08,$08,$08
  .byte $05,$05,$05,$05,$85,$85,$58,$58,$05,$05,$05,$05,$75,$75,$57,$57
  .byte $75,$75,$57,$57,$07,$07,$07,$07,$65,$65,$56,$56,$06,$06,$06,$06
  .byte $05,$05,$05,$05,$65,$65,$56,$56,$48,$48,$84,$84,$04,$04,$04,$04
  .byte $08,$08,$08,$08,$48,$48,$84,$84,$86,$86,$86,$86,$68,$68,$68,$08
  .byte $47,$47,$74,$74,$04,$04,$04,$04,$07,$07,$07,$07,$47,$47,$74,$74
  .byte $50,$50,$50,$50,$05,$95,$95,$05,$05,$05,$05,$95,$95,$05,$05,$05
  .byte $05,$05,$05,$95,$95,$05,$05,$05,$05,$05,$05,$05,$05,$95,$95,$05
  .byte $06,$06,$06,$06,$36,$36,$63,$63,$36,$36,$63,$63,$03,$03,$03,$03
  .byte $36,$36,$63,$63,$03,$93,$93,$03,$06,$06,$06,$06,$56,$56,$65,$65
  .byte $56,$56,$65,$65,$05,$05,$05,$05,$57,$57,$75,$75,$05,$05,$05,$05
  .byte $07,$07,$07,$07,$57,$57,$75,$75,$56,$56,$65,$65,$05,$95,$95,$05
  .byte $30,$30,$30,$30,$B3,$B3,$B3,$B3,$30,$30,$30,$30,$B3,$B3,$B3,$B3
  .byte $B3,$B3,$B3,$B3,$03,$03,$03,$03,$B3,$B3,$B3,$B3,$03,$03,$03,$03
  .byte $B3,$B3,$B3,$93,$93,$03,$03,$03,$B3,$B3,$B3,$93,$93,$03,$03,$03
  .byte $87,$87,$87,$87,$78,$78,$78,$08,$40,$40,$40,$40,$B4,$B4,$B4,$B4
  .byte $40,$40,$40,$40,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$64,$64,$46,$46
  .byte $B4,$B4,$B4,$B4,$04,$04,$04,$04,$36,$36,$63,$63,$03,$03,$03,$03
  .byte $06,$06,$06,$06,$36,$36,$63,$63,$B4,$B4,$B4,$94,$94,$04,$04,$04
  .byte $05,$05,$05,$05,$B5,$B5,$B5,$B5,$50,$50,$50,$50,$B5,$B5,$B5,$B5
  .byte $B5,$B5,$B5,$B5,$65,$65,$56,$56,$B5,$B5,$B5,$B5,$75,$75,$57,$57
  .byte $07,$07,$07,$07,$57,$57,$75,$75,$57,$57,$75,$75,$05,$05,$05,$05
  .byte $57,$57,$75,$75,$05,$95,$95,$05
GT1_NLO = 24
GT1_NHI = 139
GT1_PLO:
  .byte $00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00
  .byte $01,$03,$07,$0F,$1F,$3F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$03,$07,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$1F,$07,$01
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$FE,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$F8,$FE,$00,$04,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$00,$00,$00,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1F,$7F,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
GT1_CLO:
  .byte $00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$80,$08,$08,$08,$08,$08,$08,$08,$08,$08
  .byte $08,$78,$78,$78,$87,$87,$87,$87,$07,$07,$07,$07,$07,$07,$07,$07
  .byte $07,$07,$07,$07,$70,$70,$70,$70,$70,$70,$70,$70,$00,$00,$00,$00
  .byte $60,$60,$60,$60,$00,$00,$00,$00,$06,$06,$06,$06,$60,$60,$60,$60
  .byte $06,$06,$06,$06,$36,$36,$63,$63,$36,$36,$63,$63,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$30,$30,$30,$30,$03,$03,$03,$03
  .byte $00,$00,$00,$00,$30,$30,$30,$30,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$20,$20,$20,$20,$20,$20,$02,$02,$02,$02
  .byte $28,$28,$82,$82,$02,$02,$02,$02,$08,$08,$08,$08,$28,$28,$82,$82
  .byte $00,$00,$00,$00,$30,$30,$30,$30,$30,$30,$30,$30,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$73,$73,$37,$37,$73,$73,$37,$37,$07,$07,$07,$07
GT1_PHI:
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$FE,$F8,$E0,$80,$80,$E0,$F8,$FE
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$80,$E0,$F8,$FE,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$F8,$FE,$7F,$1F,$07,$01,$01,$07,$1F,$7F
  .byte $01,$07,$E0,$80,$00,$0F,$E0,$E0,$00,$00,$00,$00,$00,$F0,$07,$07
  .byte $0F,$00,$00,$00,$00,$00,$00,$00,$F0,$00,$00,$00,$01,$07,$E0,$80
  .byte $00,$00,$00,$03,$03,$00,$00,$00,$00,$00,$00,$C0,$C0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$06,$06,$00,$01,$07,$E0,$80,$00,$06,$06,$00
  .byte $01,$07,$1F,$7F,$00,$06,$06,$00,$01,$07,$1F,$7F,$00,$06,$06,$00
  .byte $00,$00,$00,$03,$03,$00,$00,$00,$00,$00,$00,$C0,$C0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$06,$06,$00,$0F,$00,$00,$C0,$C0,$00,$00,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$E0,$E0
  .byte $80,$E0,$07,$01,$00,$F0,$07,$07,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $0F,$00,$00,$00,$80,$E0,$07,$01,$F0,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$01,$03,$07,$0F,$1F,$C0,$80,$00
  .byte $01,$F8,$E0,$0F,$1F,$3F,$7F,$00,$01,$03,$07,$0F,$E0,$C0,$80,$00
  .byte $00,$00,$00,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$F0,$00,$00,$03,$03,$00,$00,$00
  .byte $80,$E0,$F8,$FE,$00,$F0,$07,$07,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$80,$E0,$F8,$FE,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$F8,$FE,$00,$00,$00,$00,$00,$F0,$07,$07
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $0F,$00,$00,$00,$00,$00,$00,$00,$01,$03,$07,$0F,$1F,$3F,$7F,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$00,$01,$03,$07,$0E,$E0,$C0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$0F,$00,$00,$C0,$C0,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$01,$03,$07,$0F,$E0,$C0,$80,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$80,$E0,$03,$01,$00,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$01,$03,$07,$0F,$E0,$C0,$80,$00
  .byte $01,$07,$E0,$80,$00,$0F,$E0,$E0,$F0,$00,$00,$00,$01,$07,$E0,$80
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $80,$C0,$E0,$F0,$F8,$03,$01,$00,$00,$80,$C0,$E0,$0F,$07,$03,$01
  .byte $80,$C0,$E0,$F0,$07,$03,$01,$00,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$00,$01,$03,$07,$0E,$E0,$C0,$80
  .byte $00,$00,$00,$00,$00,$0F,$E0,$E0,$80,$E0,$F8,$FE,$00,$F0,$07,$07
  .byte $0F,$00,$00,$00,$80,$E0,$07,$01,$0E,$03,$07,$0F,$E0,$C0,$80,$00
  .byte $7E,$1C,$07,$0F,$1F,$3F,$7F,$00,$00,$00,$00,$00,$01,$07,$1F,$7F
  .byte $01,$07,$1F,$7F,$00,$00,$00,$00,$01,$07,$E0,$80,$00,$0F,$E0,$E0
  .byte $01,$03,$07,$0F,$E0,$C0,$80,$00,$01,$07,$1F,$7F,$00,$06,$06,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$FE,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$F8,$FE,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$7F,$1F,$07,$01,$01,$07,$1F,$7F
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $01,$03,$07,$0F,$60,$C0,$80,$00,$00,$00,$00,$03,$03,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$06,$06,$00,$F0,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$00,$00,$03,$03,$00,$00,$00,$01,$07,$1F,$7F,$01,$07,$1E,$78
  .byte $80,$E0,$F8,$FE,$80,$E0,$78,$1E,$78,$1E,$07,$01,$80,$E0,$07,$01
  .byte $1E,$78,$E0,$80,$00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$1E,$78
  .byte $00,$00,$00,$00,$80,$E0,$78,$1E,$78,$1E,$07,$01,$80,$E0,$07,$01
  .byte $1E,$78,$E0,$80,$01,$07,$E0,$80,$1E,$78,$E0,$03,$03,$00,$00,$00
  .byte $01,$07,$1F,$7F,$00,$0F,$E0,$E0,$01,$07,$1F,$7F,$01,$07,$1E,$78
  .byte $00,$00,$00,$00,$80,$E0,$78,$1E,$78,$1E,$07,$01,$00,$00,$00,$00
  .byte $1E,$78,$E0,$80,$01,$07,$E0,$80,$78,$1E,$07,$C0,$C0,$00,$00,$00
  .byte $FE,$F8,$E0,$80,$80,$E0,$F8,$FE,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$F0,$07,$07
  .byte $01,$07,$E0,$80,$00,$06,$06,$00
GT1_CHI:
  .byte $63,$63,$36,$36,$06,$06,$06,$06,$03,$03,$03,$03,$63,$63,$36,$36
  .byte $00,$00,$00,$00,$00,$00,$10,$00,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $27,$27,$72,$72,$02,$02,$02,$02,$70,$70,$70,$70,$20,$20,$20,$20
  .byte $83,$83,$38,$38,$08,$08,$08,$08,$03,$03,$03,$03,$83,$83,$38,$38
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$02,$02,$02,$02,$72,$72,$27,$27
  .byte $72,$72,$27,$27,$07,$07,$07,$07,$62,$62,$26,$26,$06,$06,$06,$06
  .byte $02,$02,$02,$02,$62,$62,$26,$26,$20,$20,$20,$20,$02,$02,$02,$02
  .byte $00,$00,$00,$00,$20,$20,$20,$20,$60,$60,$60,$60,$20,$20,$20,$20
  .byte $26,$26,$62,$62,$02,$A2,$2A,$2A,$02,$02,$02,$02,$02,$A2,$2A,$2A
  .byte $A2,$02,$02,$02,$02,$02,$02,$02,$A2,$02,$02,$02,$72,$72,$27,$27
  .byte $03,$03,$03,$93,$93,$03,$03,$03,$03,$03,$03,$93,$93,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$93,$93,$03,$36,$36,$63,$63,$03,$93,$93,$03
  .byte $30,$30,$30,$30,$03,$93,$93,$03,$20,$20,$20,$20,$02,$92,$92,$02
  .byte $02,$02,$02,$92,$92,$02,$02,$02,$02,$02,$02,$92,$92,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$92,$92,$02,$A2,$02,$02,$92,$92,$02,$02,$02
  .byte $64,$64,$46,$46,$06,$06,$06,$06,$04,$04,$04,$04,$64,$64,$46,$46
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$47,$47,$74,$74,$04,$04,$04,$04
  .byte $07,$07,$07,$07,$47,$47,$74,$74,$37,$37,$73,$73,$03,$03,$03,$03
  .byte $07,$07,$07,$07,$37,$37,$73,$73,$04,$04,$04,$04,$74,$74,$47,$47
  .byte $74,$74,$47,$47,$07,$07,$07,$07,$07,$07,$07,$07,$37,$37,$73,$73
  .byte $37,$37,$73,$73,$03,$03,$03,$03,$03,$03,$03,$03,$03,$A3,$3A,$3A
  .byte $36,$36,$63,$63,$03,$A3,$3A,$3A,$06,$06,$06,$06,$36,$36,$63,$63
  .byte $A3,$03,$03,$03,$63,$63,$36,$36,$A3,$03,$03,$03,$03,$03,$03,$03
  .byte $36,$36,$63,$63,$03,$03,$03,$03,$80,$80,$80,$80,$80,$28,$28,$08
  .byte $87,$70,$70,$80,$80,$80,$80,$08,$82,$82,$82,$82,$28,$28,$28,$08
  .byte $04,$04,$04,$94,$94,$04,$04,$04,$04,$04,$04,$04,$04,$94,$94,$04
  .byte $37,$37,$73,$73,$03,$93,$93,$03,$A3,$03,$03,$93,$93,$03,$03,$03
  .byte $30,$30,$30,$30,$03,$A3,$3A,$3A,$68,$68,$86,$86,$06,$06,$06,$06
  .byte $08,$08,$08,$08,$68,$68,$86,$86,$40,$40,$40,$40,$04,$04,$04,$04
  .byte $00,$00,$00,$00,$40,$40,$40,$40,$03,$03,$03,$03,$03,$A3,$3A,$3A
  .byte $06,$06,$06,$06,$46,$46,$64,$64,$46,$46,$64,$64,$04,$04,$04,$04
  .byte $A3,$03,$03,$03,$03,$03,$03,$03,$86,$86,$86,$86,$80,$80,$80,$08
  .byte $84,$84,$48,$48,$08,$08,$08,$08,$04,$04,$04,$04,$84,$84,$48,$48
  .byte $38,$38,$83,$83,$03,$03,$03,$03,$08,$08,$08,$08,$38,$38,$83,$83
  .byte $26,$26,$62,$62,$02,$02,$02,$02,$08,$78,$78,$78,$78,$82,$82,$82
  .byte $27,$27,$72,$72,$02,$02,$02,$02,$04,$04,$04,$94,$94,$04,$04,$04
  .byte $46,$46,$64,$64,$04,$94,$94,$04,$A3,$03,$03,$93,$93,$03,$03,$03
  .byte $27,$27,$72,$72,$02,$92,$92,$02,$86,$86,$86,$86,$68,$68,$68,$08
  .byte $26,$26,$62,$62,$02,$02,$02,$02,$06,$06,$06,$06,$26,$26,$62,$62
  .byte $30,$30,$83,$83,$03,$03,$03,$03,$38,$38,$73,$73,$03,$03,$03,$03
  .byte $26,$26,$62,$62,$02,$92,$92,$02,$83,$83,$83,$83,$38,$38,$38,$08
  .byte $37,$37,$73,$73,$03,$A3,$3A,$3A,$A3,$03,$03,$03,$73,$73,$37,$37
  .byte $03,$03,$03,$03,$83,$83,$38,$38,$83,$83,$38,$38,$08,$08,$08,$08
  .byte $80,$80,$80,$80,$80,$28,$28,$08,$08,$68,$68,$68,$86,$86,$86,$86
  .byte $82,$82,$82,$82,$28,$28,$28,$08,$08,$08,$08,$08,$78,$78,$87,$87
  .byte $78,$78,$87,$87,$07,$07,$07,$07,$08,$78,$78,$78,$78,$83,$83,$83
  .byte $02,$02,$02,$02,$02,$A2,$2A,$2A,$20,$20,$20,$20,$02,$A2,$2A,$2A
  .byte $A2,$02,$02,$02,$62,$62,$26,$26,$2A,$82,$82,$82,$28,$28,$28,$08
  .byte $60,$60,$80,$80,$80,$80,$80,$08,$00,$00,$00,$00,$40,$40,$40,$40
  .byte $40,$40,$40,$40,$04,$04,$04,$04,$36,$36,$63,$63,$03,$A3,$3A,$3A
  .byte $87,$87,$87,$87,$78,$78,$78,$08,$40,$40,$40,$40,$04,$94,$94,$04
  .byte $65,$65,$56,$56,$06,$06,$06,$06,$05,$05,$05,$05,$65,$65,$56,$56
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$50,$50,$50,$50,$05,$05,$05,$05
  .byte $00,$00,$00,$00,$50,$50,$50,$50,$85,$85,$58,$58,$08,$08,$08,$08
  .byte $05,$05,$05,$05,$85,$85,$58,$58,$05,$05,$05,$05,$75,$75,$57,$57
  .byte $75,$75,$57,$57,$07,$07,$07,$07,$60,$60,$60,$60,$40,$40,$40,$40
  .byte $48,$48,$84,$84,$04,$04,$04,$04,$08,$08,$08,$08,$48,$48,$84,$84
  .byte $86,$86,$86,$86,$68,$38,$38,$08,$05,$05,$05,$95,$95,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$95,$95,$05,$A2,$02,$02,$02,$02,$02,$02,$02
  .byte $A2,$02,$02,$92,$92,$02,$02,$02,$40,$40,$40,$40,$B4,$B4,$B4,$B4
  .byte $40,$40,$40,$40,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$64,$64,$46,$46
  .byte $B4,$B4,$B4,$B4,$04,$04,$04,$04,$36,$36,$63,$63,$B3,$B3,$B3,$B3
  .byte $03,$03,$03,$03,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$63,$63,$36,$36
  .byte $B3,$B3,$B3,$B3,$73,$73,$37,$37,$B4,$B4,$B4,$94,$94,$04,$04,$04
  .byte $20,$20,$20,$20,$02,$A2,$2A,$2A,$20,$20,$20,$20,$B2,$B2,$B2,$B2
  .byte $02,$02,$02,$02,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$02,$02,$02,$02
  .byte $B2,$B2,$B2,$B2,$72,$72,$27,$27,$B2,$B2,$B2,$92,$92,$02,$02,$02
  .byte $70,$70,$70,$70,$40,$40,$40,$40,$07,$07,$07,$07,$47,$47,$74,$74
  .byte $47,$47,$74,$74,$04,$04,$04,$04,$37,$37,$73,$73,$03,$A3,$3A,$3A
  .byte $47,$47,$74,$74,$04,$94,$94,$04
GT2_NLO = 24
GT2_NHI = 36
GT2_PLO:
  .byte $7F,$1F,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$1F,$07,$01
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $FE,$F8,$E0,$80,$80,$E0,$F8,$FE,$80,$E0,$07,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$E0,$07,$01,$00,$01,$03,$07,$F0,$E0,$C0,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FE,$F8,$E0,$80
  .byte $FE,$F8,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00
  .byte $00,$00,$00,$00,$00,$02,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00
  .byte $80,$E0,$F8,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F8,$FE
  .byte $7F,$1F,$07,$01,$01,$07,$1F,$7F,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$07,$E0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$1F,$7F
GT2_CLO:
  .byte $60,$60,$60,$60,$00,$00,$00,$00,$06,$06,$06,$06,$60,$60,$60,$60
  .byte $62,$62,$26,$26,$06,$06,$06,$06,$02,$02,$02,$02,$62,$62,$26,$26
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$27,$27,$72,$72,$02,$02,$02,$02
  .byte $70,$70,$70,$70,$20,$20,$20,$20,$28,$28,$82,$82,$02,$02,$02,$02
  .byte $08,$08,$08,$08,$28,$28,$82,$82,$08,$78,$78,$78,$87,$87,$87,$87
  .byte $07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$00
  .byte $00,$00,$00,$00,$00,$10,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $20,$20,$20,$20,$02,$02,$02,$02,$00,$00,$00,$00,$20,$20,$20,$20
  .byte $60,$60,$60,$60,$20,$20,$20,$20,$26,$26,$62,$62,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$72,$72,$27,$27,$72,$72,$27,$27,$07,$07,$07,$07
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$20,$20
GT2_PHI:
  .byte $01,$07,$1F,$7F,$00,$00,$00,$00,$00,$00,$00,$03,$03,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$06,$06,$00,$00,$00,$00,$C0,$C0,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$01,$07,$1F,$7F,$00,$06,$06,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$01,$03,$07,$0E,$E0,$C0,$80,$01,$07,$E0,$80,$00,$00,$00,$00
  .byte $01,$07,$E0,$80,$00,$06,$06,$00,$01,$03,$07,$0F,$1F,$3F,$7F,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$E0,$80,$00,$0F,$E0,$E0
  .byte $00,$00,$00,$00,$00,$F0,$07,$07,$0F,$00,$00,$00,$80,$E0,$07,$01
  .byte $F0,$00,$00,$00,$01,$07,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$E0,$80
  .byte $01,$07,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$00,$00,$00
  .byte $00,$00,$00,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$00
  .byte $7E,$1C,$07,$0F,$1F,$3F,$7F,$00,$00,$00,$00,$00,$01,$07,$1E,$78
  .byte $00,$00,$00,$00,$80,$E0,$78,$1E,$78,$1E,$07,$01,$80,$E0,$07,$01
  .byte $1E,$78,$E0,$80,$01,$07,$E0,$80,$01,$03,$07,$0F,$E0,$C0,$80,$00
  .byte $80,$E0,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$07,$01
  .byte $01,$07,$E0,$80,$01,$07,$1E,$78,$80,$E0,$07,$01,$80,$E0,$78,$1E
GT2_CHI:
  .byte $20,$20,$20,$20,$02,$02,$02,$02,$02,$02,$02,$92,$92,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$92,$92,$02,$02,$02,$02,$92,$92,$02,$02,$02
  .byte $26,$26,$62,$62,$02,$92,$92,$02,$20,$20,$20,$20,$02,$92,$92,$02
  .byte $68,$68,$86,$86,$06,$06,$06,$06,$08,$08,$08,$08,$68,$68,$86,$86
  .byte $08,$78,$78,$78,$78,$82,$82,$82,$27,$27,$72,$72,$02,$02,$02,$02
  .byte $27,$27,$72,$72,$02,$92,$92,$02,$80,$80,$80,$80,$80,$80,$80,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$26,$26,$62,$62,$02,$A2,$2A,$2A
  .byte $02,$02,$02,$02,$02,$A2,$2A,$2A,$A2,$02,$02,$02,$62,$62,$26,$26
  .byte $A2,$02,$02,$02,$72,$72,$27,$27,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $63,$63,$36,$36,$06,$06,$06,$06,$03,$03,$03,$03,$63,$63,$36,$36
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$73,$73,$37,$37
  .byte $73,$73,$37,$37,$07,$07,$07,$07,$03,$03,$03,$93,$93,$03,$03,$03
  .byte $03,$03,$03,$93,$93,$03,$03,$03,$03,$03,$03,$03,$03,$93,$93,$03
  .byte $60,$60,$80,$80,$80,$80,$80,$08,$02,$02,$02,$02,$B2,$B2,$B2,$B2
  .byte $02,$02,$02,$02,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$62,$62,$26,$26
  .byte $B2,$B2,$B2,$B2,$72,$72,$27,$27,$86,$86,$86,$86,$68,$68,$68,$08
  .byte $83,$83,$38,$38,$08,$08,$08,$08,$03,$03,$03,$03,$83,$83,$38,$38
  .byte $27,$27,$72,$72,$B2,$B2,$B2,$B2,$27,$27,$72,$72,$B2,$B2,$B2,$B2
; tile 0 (void) of every third: colour material
; seed maps per third and kind (0 centre, 1 u edge, 2 v edge): count, then pairs bare tile, tile with the seed
SM_00:
  .byte $0B,$0D,$1A,$10,$1D,$1F,$71,$62,$74,$6C,$75,$70,$76,$79,$88,$7C
  .byte $8B,$8D,$8E,$90,$93,$A7,$A8
SM_01:
  .byte $05,$10,$1B,$62,$72,$7C,$89,$97,$98,$9E,$A1
SM_02:
  .byte $04,$10,$1C,$62,$73,$7C,$8A,$96,$99
SM_10:
  .byte $0D,$14,$76,$13,$77,$1D,$78,$19,$79,$63,$7C,$80,$93,$88,$94,$9D
  .byte $A8,$A6,$AA,$A4,$B0,$C2,$C5,$C8,$D4,$E8,$EA
SM_11:
  .byte $07,$14,$74,$63,$7A,$80,$92,$8D,$95,$C8,$D3,$D5,$D6,$DA,$DF
SM_12:
  .byte $06,$14,$75,$63,$7B,$72,$7D,$80,$A7,$9E,$A9,$E3,$E5
SM_20:
  .byte $05,$0C,$62,$1B,$64,$60,$65,$69,$6A,$74,$79
SM_21:
  .byte $02,$0C,$61,$74,$78
SM_22:
  .byte $02,$0C,$63,$74,$77
SM_LO: .byte <SM_00,<SM_01,<SM_02,<SM_10,<SM_11,<SM_12,<SM_20,<SM_21,<SM_22
SM_HI: .byte >SM_00,>SM_01,>SM_02,>SM_10,>SM_11,>SM_12,>SM_20,>SM_21,>SM_22
; world palettes: material -> TMS colour
WPAL:
  .byte $01,$0F,$0C,$02,$03,$03,$0A,$06,$0B,$0F,$01,$0D,$01,$01,$01,$01
  .byte $01,$0F,$0A,$0B,$0F,$0F,$08,$06,$0E,$04,$01,$0D,$01,$01,$01,$01
  .byte $01,$0F,$04,$05,$07,$07,$0F,$0E,$0B,$0D,$01,$09,$01,$01,$01,$01
  .byte $01,$0F,$0D,$05,$07,$07,$04,$06,$0E,$0B,$01,$0F,$01,$01,$01,$01
; gardens: header (start, hole, hole 2, pine cone, acorn, portal A, portal B, magpies), cells [v][u]
G_HDR:
  .byte $38,$2B,$FF,$FF,$37,$FF,$FF,$01
  .byte $39,$23,$FF,$FF,$31,$FF,$FF,$01
  .byte $39,$1A,$FF,$FF,$1C,$FF,$FF,$01
  .byte $3B,$1B,$FF,$FF,$2B,$FF,$FF,$01
  .byte $3A,$3F,$FF,$00,$37,$FF,$FF,$01
  .byte $3A,$22,$FF,$02,$32,$FF,$FF,$01
  .byte $3B,$25,$FF,$00,$35,$FF,$FF,$01
  .byte $3B,$1D,$FF,$00,$2B,$FF,$FF,$01
  .byte $3A,$1A,$FF,$FF,$37,$FF,$FF,$02
  .byte $3A,$24,$FF,$FF,$2D,$FF,$FF,$02
  .byte $3A,$23,$FF,$FF,$34,$FF,$FF,$02
  .byte $3A,$23,$FF,$FF,$35,$FF,$FF,$02
  .byte $39,$22,$FF,$FF,$31,$00,$37,$02
  .byte $3D,$1D,$FF,$FF,$37,$05,$32,$02
  .byte $3B,$22,$FF,$FF,$33,$00,$2A,$02
  .byte $3E,$2B,$FF,$FF,$32,$02,$37,$02
G_CELLS:
  .byte $01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$80,$80,$01,$80,$80,$80,$01
  .byte $01,$80,$80,$01,$80,$80,$80,$01
  .byte $20,$80,$80,$20,$80,$80,$80,$20
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$40,$80,$80,$80,$00
  .byte $00,$80,$80,$00,$80,$80,$80,$00
  .byte $40,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$02,$02,$80,$80,$01,$01,$01
  .byte $02,$80,$02,$80,$80,$01,$80,$01
  .byte $21,$80,$02,$02,$01,$01,$80,$01
  .byte $01,$80,$80,$80,$80,$80,$80,$20
  .byte $01,$01,$01,$41,$01,$80,$80,$00
  .byte $80,$80,$80,$80,$01,$80,$80,$00
  .byte $80,$00,$00,$00,$20,$00,$00,$00
  .byte $80,$40,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$80,$80,$80,$80
  .byte $01,$80,$80,$01,$01,$01,$01,$80
  .byte $01,$80,$80,$80,$80,$80,$01,$80
  .byte $01,$01,$41,$01,$01,$80,$01,$80
  .byte $80,$80,$80,$80,$01,$80,$20,$80
  .byte $80,$00,$00,$00,$20,$80,$00,$00
  .byte $80,$00,$80,$80,$80,$80,$80,$00
  .byte $80,$40,$00,$00,$00,$00,$00,$00
  .byte $02,$02,$02,$02,$02,$02,$02,$80
  .byte $02,$80,$80,$80,$80,$80,$02,$80
  .byte $21,$80,$01,$01,$01,$80,$21,$80
  .byte $01,$80,$01,$41,$01,$80,$01,$80
  .byte $01,$80,$01,$01,$01,$80,$01,$80
  .byte $20,$80,$80,$01,$80,$80,$20,$80
  .byte $00,$00,$00,$20,$00,$00,$00,$80
  .byte $80,$80,$80,$40,$80,$80,$80,$80
  .byte $02,$02,$02,$02,$02,$80,$80,$80
  .byte $02,$80,$80,$80,$21,$80,$80,$80
  .byte $21,$80,$80,$80,$20,$80,$80,$80
  .byte $20,$80,$01,$01,$01,$01,$80,$80
  .byte $00,$00,$00,$80,$80,$01,$80,$80
  .byte $80,$80,$00,$80,$80,$20,$80,$80
  .byte $80,$80,$00,$00,$00,$00,$00,$00
  .byte $80,$80,$40,$80,$80,$80,$80,$40
  .byte $80,$80,$02,$02,$02,$02,$80,$80
  .byte $80,$80,$02,$80,$80,$21,$80,$80
  .byte $01,$01,$21,$80,$80,$20,$80,$80
  .byte $01,$80,$01,$80,$00,$00,$00,$00
  .byte $20,$80,$41,$80,$00,$80,$80,$00
  .byte $00,$80,$01,$01,$10,$80,$80,$00
  .byte $00,$00,$00,$80,$80,$80,$80,$00
  .byte $80,$80,$40,$00,$00,$00,$00,$00
  .byte $03,$03,$03,$03,$80,$80,$80,$80
  .byte $03,$80,$80,$22,$80,$80,$80,$80
  .byte $22,$80,$80,$21,$01,$01,$01,$80
  .byte $02,$02,$80,$20,$80,$80,$01,$80
  .byte $21,$80,$80,$00,$00,$40,$20,$80
  .byte $20,$80,$80,$00,$80,$80,$00,$80
  .byte $00,$00,$00,$00,$80,$00,$00,$80
  .byte $80,$80,$80,$40,$00,$00,$80,$80
  .byte $02,$02,$80,$02,$02,$02,$02,$80
  .byte $02,$02,$02,$02,$80,$80,$21,$80
  .byte $21,$80,$80,$21,$80,$80,$20,$80
  .byte $20,$80,$80,$01,$01,$41,$01,$80
  .byte $00,$80,$80,$80,$80,$80,$20,$80
  .byte $00,$00,$00,$00,$80,$80,$00,$80
  .byte $80,$80,$80,$00,$00,$00,$00,$80
  .byte $80,$80,$80,$40,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$80,$80,$80
  .byte $01,$80,$80,$80,$01,$80,$80,$80
  .byte $01,$80,$80,$80,$01,$01,$01,$01
  .byte $01,$01,$41,$01,$01,$80,$80,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$20
  .byte $80,$80,$00,$00,$00,$00,$00,$00
  .byte $80,$80,$00,$80,$80,$80,$80,$00
  .byte $80,$80,$40,$80,$80,$80,$80,$80
  .byte $02,$02,$80,$80,$80,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$80,$02
  .byte $80,$80,$80,$21,$80,$80,$80,$21
  .byte $80,$01,$01,$01,$01,$01,$80,$01
  .byte $80,$01,$80,$80,$41,$01,$80,$01
  .byte $80,$20,$80,$80,$80,$01,$01,$01
  .byte $80,$00,$00,$00,$00,$80,$80,$80
  .byte $80,$80,$40,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$80,$01,$01,$01,$80
  .byte $01,$80,$01,$01,$01,$80,$01,$80
  .byte $01,$80,$80,$80,$80,$80,$01,$80
  .byte $20,$80,$01,$01,$01,$80,$20,$80
  .byte $00,$80,$01,$41,$01,$80,$00,$80
  .byte $00,$80,$20,$80,$80,$80,$00,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$80
  .byte $80,$80,$40,$80,$80,$80,$80,$80
  .byte $03,$03,$03,$03,$80,$80,$80,$80
  .byte $22,$80,$80,$03,$03,$03,$80,$80
  .byte $02,$02,$80,$80,$80,$22,$80,$80
  .byte $80,$21,$80,$80,$80,$02,$02,$80
  .byte $80,$01,$01,$41,$01,$01,$21,$80
  .byte $80,$80,$80,$80,$80,$80,$20,$80
  .byte $80,$80,$00,$00,$00,$00,$00,$80
  .byte $80,$80,$40,$80,$80,$80,$80,$80
  .byte $41,$01,$01,$80,$01,$01,$01,$01
  .byte $01,$80,$01,$80,$01,$80,$80,$01
  .byte $01,$80,$01,$01,$01,$80,$80,$01
  .byte $20,$80,$80,$80,$80,$80,$80,$20
  .byte $00,$00,$40,$00,$80,$80,$80,$00
  .byte $80,$80,$80,$00,$80,$80,$80,$00
  .byte $80,$00,$00,$00,$80,$00,$00,$40
  .byte $80,$40,$80,$80,$80,$80,$80,$80
  .byte $02,$02,$02,$80,$80,$42,$02,$02
  .byte $02,$80,$02,$80,$80,$80,$80,$02
  .byte $02,$80,$21,$80,$80,$80,$80,$21
  .byte $21,$80,$01,$01,$01,$41,$01,$01
  .byte $01,$80,$80,$80,$80,$01,$80,$80
  .byte $01,$01,$01,$80,$80,$20,$80,$80
  .byte $80,$80,$41,$80,$80,$00,$00,$00
  .byte $80,$80,$80,$80,$80,$40,$80,$80
  .byte $42,$02,$02,$02,$02,$02,$02,$80
  .byte $80,$80,$80,$80,$80,$80,$02,$80
  .byte $01,$01,$01,$01,$01,$80,$21,$80
  .byte $01,$80,$80,$80,$01,$80,$01,$80
  .byte $20,$80,$40,$00,$00,$80,$01,$80
  .byte $00,$80,$40,$80,$80,$80,$20,$80
  .byte $00,$00,$00,$00,$80,$80,$00,$80
  .byte $80,$80,$80,$40,$80,$80,$80,$80
  .byte $03,$03,$43,$80,$03,$03,$03,$80
  .byte $03,$80,$80,$80,$03,$80,$22,$80
  .byte $22,$80,$80,$80,$22,$80,$02,$80
  .byte $02,$02,$02,$80,$02,$02,$02,$80
  .byte $80,$80,$21,$80,$80,$80,$21,$80
  .byte $80,$80,$01,$41,$01,$01,$01,$80
  .byte $80,$80,$01,$80,$80,$80,$20,$40
  .byte $80,$80,$80,$80,$80,$80,$40,$80
G_NT_LO: .byte <G_NT0,<G_NT1,<G_NT2,<G_NT3,<G_NT4,<G_NT5,<G_NT6,<G_NT7,<G_NT8,<G_NT9,<G_NT10,<G_NT11,<G_NT12,<G_NT13,<G_NT14,<G_NT15
G_NT_HI: .byte >G_NT0,>G_NT1,>G_NT2,>G_NT3,>G_NT4,>G_NT5,>G_NT6,>G_NT7,>G_NT8,>G_NT9,>G_NT10,>G_NT11,>G_NT12,>G_NT13,>G_NT14,>G_NT15
G_NT0:
  .byte $07,$08,$00,$08,$07,$03,$00,$09,$0A,$07,$04,$00,$0B,$07,$03,$00,$08,$0A,$07,$06,$00,$09,$0B,$07,$13,$00,$0B,$07,$04,$00,$08,$00
  .byte $08,$07,$0B,$00,$09,$07,$07,$00,$0C,$0D,$0E,$0F,$07,$03,$00,$08,$07,$09,$00,$09,$08,$07,$0B,$00,$0C,$0D,$07,$04,$10,$0E,$0F,$07
  .byte $10,$00,$0A,$07,$05,$00,$0C,$0D,$10,$10,$11,$12,$13,$14,$10,$10,$0E,$0F,$07,$07,$00,$08,$07,$03,$00,$08,$07,$07,$00,$15,$16,$17
  .byte $11,$12,$18,$18,$19,$19,$13,$14,$10,$10,$0E,$0F,$00,$0B,$07,$05,$00,$08,$07,$04,$00,$08,$00,$09,$08,$0A,$0B,$0B,$0C,$0D,$0D,$0E
  .byte $0F,$10,$11,$12,$13,$07,$04,$14,$15,$16,$00,$00,$17,$07,$09,$00,$18,$19,$1A,$1B,$0C,$0D,$0E,$0F,$08,$08,$1C,$1D,$14,$14,$1E,$1F
  .byte $60,$61,$14,$14,$15,$16,$17,$62,$00,$00,$09,$09,$00,$08,$18,$19,$07,$04,$63,$64,$65,$00,$09,$00,$0A,$66,$67,$1E,$1F,$0D,$0D,$68
  .byte $68,$60,$61,$14,$14,$15,$16,$07,$04,$00,$18,$19,$63,$63,$69,$6A,$6B,$6C,$63,$63,$6D,$6E,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$10,$11
  .byte $68,$68,$60,$61,$14,$14,$15,$16,$18,$19,$63,$63,$69,$6A,$0E,$0F,$10,$11,$6B,$6C,$63,$63,$1A,$1B,$0C,$0D,$0E,$0F,$00,$17,$00,$00
  .byte $10,$11,$12,$13,$14,$14,$1E,$1F,$6B,$6C,$63,$63,$64,$65,$00,$62,$00,$09,$6F,$70,$71,$07,$03,$63,$64,$65,$07,$06,$00,$1C,$1D,$14
  .byte $14,$1E,$1F,$0D,$0D,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$18,$19,$63,$72,$73,$6A,$6B,$6C,$63,$63,$6D,$6E,$07,$03,$00,$0A,$66,$67,$1E
  .byte $1F,$0D,$0D,$0E,$0F,$62,$00,$10,$11,$6B,$6C,$07,$04,$63,$69,$6A,$0E,$0F,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$0A,$0B,$0B,$0C,$0D,$0D
  .byte $0E,$0F,$07,$06,$00,$08,$09,$0A,$0B,$0C,$0C,$0D,$0E,$07,$04,$00,$08,$09,$0A,$0B,$0C,$0C,$0F,$10,$11,$12,$13,$14,$07,$04,$00,$15
  .byte $15,$16,$16,$00,$17,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$15,$17,$00,$00,$1A,$1B,$0C,$0C,$1C,$1D,$13,$14,$07,$07,$00,$15,$00,$17,$1E
  .byte $07,$03,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$1F,$60,$0C,$0C,$1C,$1D,$13,$14,$07,$08,$00,$1E,$07,$03,$00,$1E,$07,$05,$00,$08,$09
  .byte $0A,$0B,$07,$04,$0C,$1C,$1D,$13,$14,$1E,$07,$06,$00,$16,$00,$17,$07,$03,$00,$1E,$15,$07,$07,$00,$08,$09,$0A,$0B,$1C,$1D,$13,$14
  .byte $07,$08,$00,$17,$07,$04,$00,$15,$07,$08,$00,$1E,$07,$03,$00,$08,$09,$13,$14,$15,$00,$00,$17,$00,$15,$00,$1E,$07,$0B,$00,$1E,$07
  .byte $05,$00,$15,$00,$00,$15,$15,$07,$03,$00,$07,$03,$1E,$00,$17,$16,$17,$16,$00,$17,$07,$03,$00
G_NT1:
  .byte $07,$15,$00,$08,$07,$0E,$00,$0B,$07,$09,$00,$1E,$1F,$60,$61,$07,$06,$00,$09,$00,$00,$09,$07,$08,$00,$0B,$00,$0A,$00,$00,$0B,$00
  .byte $00,$1E,$1F,$07,$04,$62,$60,$61,$07,$0C,$00,$09,$0B,$07,$09,$00,$15,$63,$64,$65,$66,$67,$68,$62,$62,$60,$61,$07,$0C,$00,$0A,$07
  .byte $07,$00,$15,$69,$69,$6A,$18,$18,$6B,$6C,$62,$62,$65,$66,$07,$03,$00,$08,$07,$03,$00,$08,$07,$04,$00,$0B,$00,$09,$00,$00,$09,$0C
  .byte $0D,$6D,$6E,$6A,$18,$6F,$70,$62,$62,$65,$66,$18,$18,$0B,$00,$00,$08,$07,$09,$00,$17,$17,$00,$1C,$1D,$14,$14,$1E,$1F,$0D,$0D,$7E
  .byte $7F,$80,$80,$81,$82,$0D,$0D,$07,$06,$00,$09,$07,$09,$00,$60,$61,$14,$14,$83,$84,$0E,$0F,$68,$68,$7E,$7F,$85,$86,$0E,$0F,$17,$62
  .byte $1C,$1D,$15,$16,$07,$06,$00,$17,$62,$00,$17,$68,$68,$60,$61,$14,$14,$15,$16,$07,$04,$68,$87,$88,$15,$16,$1C,$1D,$07,$04,$14,$15
  .byte $16,$17,$17,$00,$08,$07,$04,$00,$10,$11,$68,$68,$60,$61,$14,$89,$8A,$8B,$68,$68,$60,$61,$07,$04,$14,$1E,$1F,$60,$61,$14,$14,$15
  .byte $16,$07,$04,$00,$18,$19,$6D,$6E,$10,$11,$68,$68,$60,$8C,$8D,$14,$8E,$8B,$68,$68,$60,$61,$1E,$1F,$0D,$0D,$12,$13,$14,$14,$1E,$1F
  .byte $00,$00,$18,$19,$07,$04,$63,$6D,$6E,$10,$11,$12,$13,$14,$14,$1E,$1F,$10,$11,$68,$68,$0D,$0D,$87,$88,$14,$14,$1E,$1F,$0D,$0D,$00
  .byte $00,$6B,$6C,$69,$6A,$6B,$6C,$63,$63,$6D,$8F,$66,$67,$1E,$1F,$0D,$0D,$17,$00,$10,$11,$0E,$90,$66,$67,$1E,$1F,$0D,$0D,$0E,$0F,$00
  .byte $00,$10,$11,$0E,$0F,$10,$11,$6B,$6C,$91,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07,$04,$00,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07,$03,$00,$16
  .byte $00,$17,$17,$00,$15,$00,$08,$09,$66,$67,$68,$69,$0D,$0E,$07,$04,$00,$1F,$60,$0F,$10,$11,$12,$13,$14,$07,$07,$00,$17,$07,$06,$00
  .byte $08,$09,$0A,$0B,$0C,$0C,$18,$19,$1F,$60,$0C,$0C,$1C,$1D,$13,$14,$07,$04,$00,$1E,$00,$1E,$07,$03,$00,$1E,$07,$03,$00,$16,$00,$00
  .byte $1E,$08,$09,$0A,$0B,$07,$04,$0C,$1C,$1D,$13,$14,$00,$00,$15,$00,$00,$17,$07,$10,$00,$08,$09,$0A,$0B,$1C,$1D,$13,$14,$17,$07,$08
  .byte $00,$15,$07,$04,$00,$15,$00,$15,$07,$05,$00,$1E,$07,$03,$00,$08,$09,$13,$14,$17,$07,$07,$00,$15,$07,$05,$00,$15,$07,$0A,$00,$15
  .byte $00,$00,$1E,$07,$0F,$00,$1E,$07,$04,$00,$16,$00,$17,$1E,$07,$05,$00,$16,$07,$0D,$00,$1E,$07,$03,$00
G_NT2:
  .byte $00,$00,$08,$09,$07,$07,$00,$0B,$0A,$00,$00,$0B,$0A,$07,$0B,$00,$0B,$07,$0A,$00,$0A,$07,$20,$00,$0B,$07,$04,$00,$08,$0C,$0D,$0E
  .byte $0F,$09,$07,$07,$00,$0B,$07,$07,$00,$0A,$00,$09,$07,$07,$00,$0C,$0D,$07,$04,$10,$0E,$0F,$00,$0B,$00,$09,$0B,$07,$11,$00,$0C,$0D
  .byte $10,$10,$11,$12,$13,$14,$10,$10,$0E,$0F,$00,$00,$0B,$07,$04,$00,$08,$0A,$07,$09,$00,$0C,$0D,$10,$10,$11,$12,$18,$18,$19,$19,$13
  .byte $14,$10,$10,$0E,$0F,$00,$09,$07,$0A,$00,$09,$07,$03,$00,$60,$61,$14,$14,$83,$84,$0E,$0F,$10,$11,$12,$13,$14,$14,$1E,$1F,$07,$04
  .byte $00,$08,$09,$00,$08,$09,$07,$07,$00,$68,$68,$60,$61,$14,$89,$96,$16,$00,$00,$60,$61,$14,$14,$83,$84,$00,$00,$09,$07,$04,$00,$08
  .byte $00,$00,$17,$07,$05,$00,$10,$11,$68,$68,$60,$8C,$8D,$14,$15,$16,$68,$68,$60,$61,$14,$14,$15,$16,$17,$09,$07,$05,$00,$62,$00,$09
  .byte $00,$00,$18,$19,$6D,$6E,$10,$11,$68,$68,$60,$61,$14,$14,$8E,$8B,$68,$68,$60,$61,$14,$14,$15,$16,$00,$00,$62,$07,$05,$00,$18,$19
  .byte $07,$04,$63,$6D,$6E,$10,$11,$12,$13,$14,$14,$1E,$1F,$10,$11,$12,$13,$14,$14,$1E,$1F,$09,$07,$05,$00,$18,$19,$63,$63,$69,$6A,$6B
  .byte $6C,$63,$63,$6D,$8F,$66,$67,$1E,$1F,$0D,$0D,$1C,$1D,$14,$14,$1E,$1F,$0D,$0D,$07,$05,$00,$62,$6B,$6C,$63,$63,$64,$65,$10,$11,$6B
  .byte $6C,$91,$0B,$0B,$0C,$0D,$0D,$0E,$90,$66,$67,$1E,$1F,$0D,$0D,$0E,$0F,$07,$04,$00,$62,$00,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$10,$11
  .byte $97,$98,$0C,$0D,$0E,$0F,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07,$09,$00,$16,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$08,$09,$13,$14,$1F,$60
  .byte $0F,$10,$11,$12,$13,$14,$07,$07,$00,$15,$00,$15,$07,$04,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$00,$00,$0A,$0B,$0C,$0C,$0D,$0E,$1E
  .byte $07,$04,$00,$1E,$07,$04,$00,$17,$00,$15,$00,$00,$15,$00,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$1A,$1B,$0C,$0C,$1C,$1D,$00,$15,$07
  .byte $12,$00,$08,$09,$0A,$0B,$07,$04,$0C,$1C,$1D,$13,$14,$07,$04,$00,$16,$00,$00,$1E,$07,$03,$00,$16,$07,$07,$00,$16,$00,$00,$08,$09
  .byte $0A,$0B,$1C,$1D,$13,$14,$07,$08,$00,$15,$00,$00,$16,$00,$16,$00,$16,$00,$1E,$1E,$07,$06,$00,$16,$08,$09,$13,$14,$07,$0B,$00,$1E
  .byte $07,$03,$00,$16,$07,$1C,$00,$17,$00
G_NT3:
  .byte $07,$03,$00,$08,$00,$00,$0B,$09,$00,$0B,$00,$08,$07,$0B,$00,$08,$0A,$07,$06,$00,$08,$0B,$07,$0D,$00,$1E,$1F,$60,$61,$08,$07,$05
  .byte $00,$0A,$07,$07,$00,$0A,$07,$05,$00,$0A,$07,$04,$00,$0A,$1E,$1F,$07,$04,$62,$60,$61,$07,$07,$00,$0A,$0A,$0B,$07,$0A,$00,$09,$09
  .byte $00,$15,$63,$64,$65,$66,$67,$68,$62,$62,$60,$61,$00,$09,$00,$0A,$07,$04,$00,$0B,$0A,$07,$05,$00,$09,$07,$04,$00,$15,$69,$69,$6A
  .byte $18,$18,$19,$19,$67,$68,$62,$62,$60,$61,$07,$04,$00,$09,$07,$0B,$00,$0C,$0D,$6D,$6E,$6A,$07,$03,$18,$07,$04,$19,$67,$68,$62,$62
  .byte $60,$61,$0B,$0A,$07,$07,$00,$09,$00,$00,$1C,$1D,$14,$14,$1E,$1F,$0D,$0D,$87,$88,$8E,$8B,$07,$04,$68,$7E,$7F,$80,$80,$99,$9A,$62
  .byte $00,$09,$00,$17,$09,$07,$03,$00,$0A,$66,$67,$1E,$1F,$0D,$0D,$87,$88,$07,$04,$14,$8E,$8B,$07,$04,$68,$7E,$7F,$80,$80,$99,$9A,$07
  .byte $06,$00,$0A,$0B,$0B,$0C,$0D,$0D,$87,$88,$07,$03,$14,$89,$9B,$07,$03,$14,$8E,$8B,$68,$68,$9C,$9D,$80,$80,$85,$86,$07,$04,$00,$18
  .byte $19,$1A,$1B,$0C,$0D,$0E,$0F,$60,$61,$07,$03,$14,$9E,$8D,$07,$03,$14,$1E,$1F,$10,$9F,$A0,$A1,$85,$86,$0D,$0D,$07,$04,$00,$6B,$6C
  .byte $63,$63,$64,$65,$00,$00,$12,$13,$07,$06,$14,$1E,$1F,$0D,$0D,$0A,$0B,$0B,$0C,$07,$04,$0D,$09,$07,$03,$00,$10,$11,$6B,$6C,$63,$63
  .byte $6D,$8F,$66,$67,$1E,$1F,$60,$61,$1E,$1F,$0D,$0D,$87,$88,$A2,$A3,$0C,$07,$03,$0D,$0E,$0F,$07,$03,$00,$17,$00,$17,$10,$11,$6B,$6C
  .byte $91,$0B,$0B,$0C,$0D,$0D,$68,$68,$0D,$0D,$87,$88,$14,$14,$1E,$1F,$0D,$0D,$0E,$0F,$00,$09,$07,$08,$00,$6F,$A4,$1A,$1B,$A5,$A6,$64
  .byte $65,$10,$11,$0E,$90,$66,$67,$1E,$1F,$0D,$0D,$0E,$0F,$07,$03,$00,$08,$00,$00,$15,$07,$05,$00,$0A,$0B,$1C,$1D,$0A,$0B,$0C,$0C,$18
  .byte $19,$6B,$6C,$6C,$11,$12,$12,$13,$14,$00,$17,$15,$17,$07,$07,$00,$16,$00,$00,$08,$09,$13,$14,$08,$09,$0A,$0B,$0C,$0C,$0F,$10,$11
  .byte $12,$13,$14,$07,$07,$00,$1E,$00,$15,$07,$0C,$00,$08,$09,$0A,$0B,$1C,$1D,$13,$14,$07,$04,$00,$15,$07,$03,$00,$1E,$07,$0D,$00,$16
  .byte $07,$03,$00,$08,$09,$13,$14,$00,$00,$17,$07,$08,$00,$1E,$07,$03,$00,$17,$07,$0A,$00,$17,$1E,$00,$15,$07,$06,$00,$15,$07,$08,$00
  .byte $17,$1E,$1E,$07,$06,$00,$16,$1E,$07,$08,$00,$15,$07,$0E,$00,$1E,$07,$07,$00,$17,$07,$0D,$00,$17,$07,$06,$00,$17,$00
G_NT4:
  .byte $07,$04,$00,$0A,$0A,$07,$04,$00,$08,$07,$03,$00,$0A,$07,$04,$00,$0A,$00,$00,$0B,$07,$07,$00,$09,$07,$09,$00,$09,$07,$03,$00,$08
  .byte $00,$1E,$1F,$60,$61,$00,$0A,$00,$0B,$07,$07,$00,$0B,$00,$00,$0B,$00,$0A,$07,$09,$00,$1E,$1F,$07,$04,$62,$60,$61,$0A,$0A,$07,$11
  .byte $00,$0B,$07,$03,$00,$15,$63,$64,$65,$66,$67,$68,$62,$62,$60,$61,$07,$0C,$00,$0A,$07,$05,$00,$08,$00,$15,$69,$69,$6A,$18,$18,$19
  .byte $19,$67,$68,$62,$62,$60,$61,$07,$06,$00,$09,$00,$0B,$07,$08,$00,$15,$69,$69,$6A,$07,$03,$18,$07,$04,$19,$67,$68,$62,$62,$60,$61
  .byte $07,$08,$00,$08,$07,$05,$00,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$10,$11,$07,$03,$68,$AB,$A0,$A1,$85,$86,$07,$03,$00,$08,$07,$08,$00
  .byte $18,$19,$1A,$1B,$0C,$0D,$87,$88,$15,$16,$00,$00,$10,$11,$AB,$0B,$0B,$0C,$0D,$0D,$07,$07,$00,$09,$07,$03,$00,$08,$6B,$6C,$63,$63
  .byte $64,$65,$60,$61,$14,$14,$15,$16,$00,$0A,$0B,$0B,$0C,$07,$03,$0D,$62,$62,$07,$0A,$00,$10,$11,$6B,$6C,$63,$63,$AC,$AD,$60,$61,$14
  .byte $14,$AE,$A3,$0B,$0C,$0D,$0D,$0E,$0F,$07,$03,$00,$08,$07,$08,$00,$17,$00,$6F,$A4,$63,$63,$69,$6A,$68,$68,$60,$61,$14,$14,$AF,$84
  .byte $0E,$0F,$07,$0B,$00,$08,$00,$00,$18,$19,$63,$63,$69,$6A,$0E,$0F,$10,$11,$12,$13,$14,$14,$1E,$1F,$07,$08,$00,$17,$00,$00,$62,$09
  .byte $00,$18,$19,$07,$04,$63,$64,$65,$07,$03,$00,$0A,$66,$67,$1E,$1F,$0D,$0D,$00,$08,$09,$07,$0B,$00,$6B,$6C,$69,$6A,$6B,$6C,$63,$63
  .byte $6D,$6E,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07,$06,$00,$09,$00,$17,$07,$05,$00,$08,$09,$13,$14,$08,$09,$0A,$0B,$0C,$0C,$0F,$10,$11
  .byte $12,$13,$14,$07,$04,$00,$1E,$07,$09,$00,$1E,$07,$07,$00,$08,$09,$0A,$0B,$0C,$0C,$0D,$0E,$07,$06,$00,$15,$07,$04,$00,$17,$07,$08
  .byte $00,$16,$17,$00,$17,$00,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$07,$03,$00,$1E,$1E,$00,$00,$16,$00,$00,$17,$17,$00,$00,$15,$07,$06
  .byte $00,$1E,$07,$04,$00,$1A,$6D,$6E,$0C,$1C,$1D,$07,$0D,$00,$15,$00,$16,$07,$05,$00,$15,$00,$15,$15,$00,$0A,$6F,$70,$1D,$13,$14,$07
  .byte $09,$00,$15,$17,$07,$06,$00,$16,$07,$04,$00,$16,$07,$03,$00,$08,$09,$13,$14,$15,$07,$0A,$00,$16,$16,$07,$04,$00,$17,$07,$05,$00
  .byte $17,$07,$05,$00,$15,$00,$16,$07,$0A,$00,$16,$00,$15,$17
G_NT5:
  .byte $07,$0E,$00,$09,$00,$08,$07,$0A,$00,$0B,$00,$0B,$07,$10,$00,$0B,$07,$0A,$00,$0A,$0A,$07,$0C,$00,$08,$00,$08,$07,$0C,$00,$08,$07
  .byte $08,$00,$0A,$07,$12,$00,$1E,$1F,$60,$61,$00,$09,$00,$00,$0A,$07,$04,$00,$08,$00,$0B,$08,$09,$0B,$00,$00,$0A,$0A,$00,$0C,$0D,$0E
  .byte $0F,$0A,$09,$1E,$1F,$07,$04,$62,$60,$61,$00,$0B,$07,$0A,$00,$0B,$07,$03,$00,$0C,$0D,$07,$04,$10,$0E,$77,$63,$64,$65,$66,$67,$68
  .byte $62,$62,$60,$61,$07,$0B,$00,$62,$00,$0A,$66,$67,$1E,$1F,$60,$61,$B1,$0B,$0B,$0C,$0D,$0D,$68,$68,$7E,$7F,$80,$80,$99,$9A,$17,$07
  .byte $09,$00,$0A,$0B,$0B,$0C,$0D,$0D,$12,$13,$A2,$A3,$0C,$07,$03,$0D,$07,$03,$68,$AB,$A0,$A1,$85,$86,$62,$07,$06,$00,$08,$18,$19,$1A
  .byte $1B,$0C,$0D,$87,$B2,$9B,$14,$1E,$1F,$0D,$0D,$0E,$0F,$10,$11,$AB,$0B,$0B,$0C,$0D,$0D,$07,$06,$00,$18,$19,$63,$63,$69,$6A,$87,$88
  .byte $14,$9E,$B3,$1F,$0D,$0D,$0E,$0F,$07,$03,$00,$0A,$0B,$0B,$0C,$07,$03,$0D,$07,$06,$00,$6B,$6C,$63,$63,$64,$65,$60,$61,$14,$14,$83
  .byte $84,$0E,$0F,$18,$19,$6D,$6E,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07,$06,$00,$10,$11,$6B,$6C,$63,$63,$AC,$AD,$60,$61,$B4,$B5,$B6,$19
  .byte $07,$04,$63,$1A,$1B,$0C,$0D,$0E,$0F,$07,$09,$00,$17,$6F,$A4,$63,$63,$69,$6A,$68,$68,$B7,$0B,$0B,$B8,$69,$6A,$6B,$6C,$63,$63,$64
  .byte $65,$07,$03,$00,$62,$07,$08,$00,$6B,$6C,$63,$63,$64,$65,$10,$11,$68,$B7,$B9,$BA,$0E,$0F,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$00,$08
  .byte $07,$04,$00,$16,$07,$03,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$08,$09,$13,$14,$17,$17,$00,$00,$1A,$1B,$0C,$0C,$1C,$1D,$07,$05,$00
  .byte $17,$07,$03,$00,$1E,$00,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$00,$17,$1E,$00,$1F,$60,$0C,$0C,$1C,$1D,$13,$14,$07,$05,$00,$17,$07
  .byte $03,$00,$1E,$17,$07,$03,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$1F,$60,$0C,$0C,$1C,$1D,$13,$14,$07,$05,$00,$1E,$07,$05,$00,$16,$17
  .byte $07,$05,$00,$08,$09,$0A,$0B,$07,$04,$0C,$1C,$1D,$13,$14,$07,$05,$00,$16,$07,$10,$00,$08,$09,$0A,$0B,$1C,$1D,$13,$14,$07,$0D,$00
  .byte $15,$07,$05,$00,$1E,$07,$04,$00,$1E,$15,$08,$09,$13,$14,$00,$1E,$00,$16,$00,$00,$15,$00,$15,$07,$03,$00,$15,$07,$07,$00,$16,$07
  .byte $08,$00,$1E,$16,$07,$0B,$00,$17,$17,$00,$00
G_NT6:
  .byte $00,$08,$07,$04,$00,$0A,$09,$00,$00,$0B,$07,$03,$00,$78,$79,$7A,$7B,$07,$03,$00,$0A,$07,$06,$00,$0B,$07,$0D,$00,$09,$00,$78,$79
  .byte $07,$04,$7C,$7A,$7B,$00,$0A,$09,$07,$0B,$00,$09,$07,$05,$00,$0B,$00,$09,$15,$7D,$7E,$7F,$80,$81,$82,$7C,$7C,$7A,$7B,$07,$14,$00
  .byte $15,$69,$69,$6A,$18,$18,$19,$19,$81,$82,$7C,$7C,$7A,$7B,$0A,$00,$0A,$07,$03,$00,$09,$00,$0A,$00,$0B,$07,$03,$00,$0B,$00,$1E,$1F
  .byte $83,$84,$6A,$07,$03,$18,$07,$03,$19,$85,$7D,$7E,$7F,$80,$07,$0A,$00,$09,$0B,$07,$03,$00,$15,$63,$64,$62,$62,$86,$87,$18,$18,$19
  .byte $19,$85,$69,$69,$6A,$18,$18,$07,$07,$00,$0A,$07,$06,$00,$0A,$0B,$0B,$0C,$7E,$7F,$85,$86,$0E,$0F,$10,$9F,$0B,$0B,$0C,$07,$03,$0D
  .byte $07,$08,$00,$62,$07,$04,$00,$0A,$0B,$0B,$0C,$0D,$68,$68,$0D,$0D,$00,$00,$0A,$0B,$0B,$0C,$07,$04,$0D,$07,$06,$00,$62,$07,$05,$00
  .byte $0A,$0B,$0B,$0C,$0D,$0D,$68,$68,$0D,$0D,$00,$0A,$0B,$0B,$BB,$88,$83,$84,$0E,$0F,$00,$08,$00,$62,$09,$00,$62,$08,$00,$00,$18,$19
  .byte $1A,$1B,$0C,$0D,$0E,$0F,$10,$11,$0E,$0F,$0A,$0B,$0B,$0C,$60,$61,$14,$14,$15,$16,$07,$0A,$00,$6B,$6C,$63,$63,$64,$65,$07,$04,$00
  .byte $18,$19,$1A,$1B,$0C,$0D,$68,$68,$60,$61,$14,$14,$15,$16,$00,$08,$07,$06,$00,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$18,$19,$07,$04,$63
  .byte $64,$65,$10,$11,$12,$13,$14,$14,$1E,$1F,$07,$0A,$00,$10,$11,$6B,$6C,$07,$04,$63,$69,$6A,$6B,$6C,$63,$BC,$BD,$8F,$66,$67,$1E,$1F
  .byte $0D,$0D,$00,$00,$08,$00,$00,$62,$07,$06,$00,$6F,$A4,$63,$63,$69,$6A,$0E,$0F,$10,$11,$6B,$BE,$BF,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07
  .byte $05,$00,$17,$00,$16,$00,$17,$00,$00,$0A,$0B,$0C,$0C,$0D,$0E,$1F,$60,$18,$19,$1A,$1B,$0F,$10,$11,$12,$13,$14,$07,$03,$00,$1E,$07
  .byte $03,$00,$16,$07,$06,$00,$08,$09,$0A,$0B,$07,$08,$0C,$1C,$1D,$13,$14,$07,$04,$00,$17,$1E,$07,$03,$00,$17,$1E,$00,$16,$07,$05,$00
  .byte $08,$09,$0A,$0B,$1C,$1D,$0A,$0B,$1C,$1D,$13,$14,$00,$00,$16,$07,$04,$00,$1E,$00,$00,$16,$07,$06,$00,$1E,$07,$04,$00,$08,$09,$13
  .byte $14,$08,$09,$13,$14,$00,$00,$1E,$00,$00,$16,$07,$0B,$00,$16,$07,$03,$00,$17,$07,$1E,$00,$1E,$07,$06,$00,$16,$07,$12,$00,$1E,$00
  .byte $00,$15,$07,$05,$00,$1E,$00,$00,$16,$07,$04,$00,$16,$16,$07,$08,$00,$1E,$07,$03,$00,$15
G_NT7:
  .byte $09,$00,$00,$09,$07,$03,$00,$09,$07,$03,$00,$08,$07,$04,$00,$08,$07,$04,$00,$0B,$07,$0D,$00,$0A,$07,$0A,$00,$1E,$1F,$60,$61,$00
  .byte $00,$09,$07,$03,$00,$0A,$07,$0E,$00,$0A,$00,$0A,$00,$0A,$1E,$1F,$07,$04,$62,$60,$61,$0A,$07,$0D,$00,$0B,$07,$08,$00,$15,$63,$64
  .byte $07,$04,$62,$65,$66,$07,$05,$00,$09,$0B,$07,$03,$00,$09,$07,$06,$00,$0B,$07,$04,$00,$15,$69,$69,$6A,$67,$68,$62,$62,$86,$87,$1E
  .byte $1F,$60,$61,$07,$06,$00,$09,$00,$08,$07,$05,$00,$09,$0A,$08,$15,$69,$69,$6A,$18,$19,$19,$67,$68,$07,$06,$62,$60,$61,$00,$00,$0A
  .byte $09,$07,$04,$00,$08,$07,$05,$00,$0A,$0B,$0B,$0C,$0D,$0D,$07,$03,$68,$AB,$A0,$A1,$85,$86,$7E,$7F,$80,$80,$99,$9A,$07,$03,$00,$17
  .byte $07,$06,$00,$18,$19,$1A,$1B,$0C,$0D,$0E,$0F,$10,$11,$AB,$0B,$0B,$0C,$0D,$0D,$68,$68,$7E,$7F,$80,$80,$99,$9A,$07,$06,$00,$18,$19
  .byte $63,$63,$69,$6A,$0E,$0F,$00,$17,$1C,$1D,$A2,$A3,$0C,$07,$03,$0D,$07,$03,$68,$AB,$A0,$A1,$85,$86,$17,$07,$04,$00,$62,$6B,$6C,$63
  .byte $63,$64,$65,$00,$08,$00,$09,$60,$61,$14,$14,$83,$84,$0E,$0F,$10,$11,$AB,$0B,$0B,$0C,$0D,$0D,$07,$06,$00,$10,$11,$6B,$6C,$63,$63
  .byte $6D,$6E,$08,$09,$68,$68,$60,$61,$14,$89,$96,$16,$00,$0A,$0B,$0B,$0C,$07,$03,$0D,$07,$08,$00,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$10
  .byte $11,$68,$68,$60,$8C,$8D,$14,$AE,$A3,$0B,$0C,$0D,$0D,$0E,$0F,$07,$05,$00,$62,$00,$00,$62,$00,$6F,$A4,$63,$63,$69,$6A,$00,$00,$10
  .byte $11,$68,$AB,$66,$67,$1E,$1F,$0C,$0D,$0E,$0F,$07,$03,$00,$62,$62,$07,$05,$00,$18,$19,$07,$04,$63,$64,$65,$07,$04,$00,$C0,$0B,$0B
  .byte $0C,$0D,$0D,$0E,$0F,$09,$08,$07,$03,$00,$62,$07,$06,$00,$0A,$0B,$1C,$1D,$0A,$0B,$0C,$0C,$18,$19,$1F,$60,$0F,$10,$11,$12,$13,$14
  .byte $07,$04,$00,$17,$07,$09,$00,$08,$09,$13,$14,$08,$09,$0A,$0B,$07,$04,$0C,$1C,$1D,$13,$14,$07,$0C,$00,$15,$07,$04,$00,$17,$07,$04
  .byte $00,$08,$09,$0A,$0B,$1C,$1D,$13,$14,$07,$04,$00,$15,$1E,$15,$07,$03,$00,$15,$00,$1E,$00,$17,$07,$07,$00,$17,$07,$03,$00,$08,$09
  .byte $13,$14,$16,$16,$07,$0F,$00,$1E,$07,$03,$00,$1E,$00,$00,$16,$07,$0C,$00,$16,$00,$15,$07,$07,$00,$16,$07,$04,$00,$15,$07,$06,$00
  .byte $17,$07,$09,$00,$17,$1E,$07,$05,$00,$17,$07,$07,$00,$15,$07,$0A,$00,$17,$07,$0D,$00,$15
G_NT8:
  .byte $09,$07,$03,$00,$0B,$08,$0A,$07,$0C,$00,$09,$07,$04,$00,$08,$09,$07,$06,$00,$0A,$0B,$07,$08,$00,$0A,$07,$10,$00,$0B,$07,$03,$00
  .byte $0B,$07,$05,$00,$08,$07,$04,$00,$0A,$00,$09,$00,$0C,$0D,$0E,$0F,$07,$08,$00,$0A,$07,$07,$00,$09,$07,$09,$00,$0C,$0D,$07,$04,$10
  .byte $0E,$0F,$07,$16,$00,$0C,$0D,$10,$10,$11,$12,$13,$14,$10,$10,$0E,$0F,$07,$08,$00,$09,$08,$0B,$07,$07,$00,$0C,$0D,$10,$10,$11,$12
  .byte $18,$18,$19,$19,$13,$14,$10,$10,$0E,$0F,$07,$04,$00,$08,$07,$05,$00,$17,$07,$04,$00,$09,$60,$61,$14,$14,$83,$84,$0E,$0F,$10,$11
  .byte $68,$68,$60,$61,$14,$14,$15,$16,$00,$00,$17,$00,$00,$09,$07,$08,$00,$68,$68,$60,$61,$14,$89,$96,$16,$62,$62,$10,$11,$12,$13,$14
  .byte $14,$1E,$1F,$07,$04,$00,$17,$00,$00,$09,$07,$04,$00,$09,$00,$10,$11,$68,$68,$60,$8C,$8D,$14,$15,$16,$1C,$1D,$14,$14,$1E,$1F,$0D
  .byte $0D,$07,$03,$00,$17,$00,$08,$07,$08,$00,$08,$00,$10,$11,$68,$68,$60,$61,$07,$06,$14,$83,$84,$0E,$0F,$07,$04,$00,$62,$07,$09,$00
  .byte $18,$19,$6D,$6E,$10,$11,$68,$68,$60,$61,$1E,$1F,$60,$61,$14,$14,$15,$16,$07,$0C,$00,$18,$19,$07,$04,$63,$6D,$6E,$10,$11,$68,$68
  .byte $0D,$0D,$68,$68,$60,$61,$14,$14,$15,$16,$00,$00,$62,$00,$17,$62,$00,$00,$18,$19,$63,$63,$69,$6A,$6B,$6C,$63,$63,$6D,$6E,$10,$11
  .byte $0E,$0F,$10,$11,$12,$13,$14,$14,$1E,$1F,$07,$06,$00,$62,$00,$6B,$6C,$69,$6A,$0E,$0F,$10,$11,$6B,$6C,$63,$63,$6D,$6E,$07,$03,$00
  .byte $0A,$66,$67,$1E,$1F,$0D,$0D,$00,$62,$00,$00,$1E,$00,$15,$00,$08,$09,$13,$14,$00,$15,$00,$00,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$6B
  .byte $6C,$6C,$11,$12,$12,$13,$14,$1E,$07,$03,$00,$17,$07,$05,$00,$1E,$07,$07,$00,$08,$09,$0A,$0B,$0C,$0C,$0F,$10,$11,$12,$13,$14,$07
  .byte $08,$00,$16,$07,$05,$00,$17,$1E,$07,$03,$00,$15,$00,$00,$1A,$1B,$0C,$0C,$1C,$1D,$13,$14,$17,$07,$08,$00,$17,$07,$0E,$00,$0A,$0B
  .byte $1C,$1D,$13,$14,$07,$06,$00,$16,$07,$03,$00,$15,$07,$04,$00,$1E,$07,$0A,$00,$08,$09,$13,$14,$15,$1E,$07,$0E,$00,$16,$07,$04,$00
  .byte $1E,$00,$1E,$15,$1E,$07,$10,$00,$16,$00,$00,$16,$07,$0C,$00,$1E,$07,$0A,$00,$1E,$07,$04,$00,$15,$00
G_NT9:
  .byte $00,$00,$09,$07,$09,$00,$08,$08,$00,$00,$0A,$07,$06,$00,$09,$07,$0C,$00,$08,$07,$04,$00,$08,$07,$04,$00,$1E,$1F,$60,$61,$0B,$07
  .byte $04,$00,$08,$00,$00,$0B,$09,$00,$0B,$07,$04,$00,$09,$07,$05,$00,$08,$00,$00,$08,$1E,$1F,$07,$04,$62,$60,$61,$00,$00,$09,$07,$12
  .byte $00,$0A,$00,$00,$67,$68,$07,$04,$62,$65,$66,$07,$03,$00,$09,$07,$06,$00,$08,$00,$00,$0A,$07,$04,$00,$08,$07,$05,$00,$19,$19,$67
  .byte $68,$62,$62,$86,$87,$07,$03,$00,$0A,$00,$0A,$07,$03,$00,$0B,$07,$04,$00,$0B,$00,$00,$08,$07,$06,$00,$07,$04,$19,$67,$68,$62,$62
  .byte $60,$61,$07,$04,$00,$09,$07,$03,$00,$0B,$07,$04,$00,$08,$07,$06,$00,$1C,$1D,$8E,$8B,$07,$03,$68,$AB,$A0,$A1,$80,$80,$99,$9A,$C1
  .byte $C2,$99,$9A,$07,$0C,$00,$1C,$1D,$07,$04,$14,$8E,$8B,$AB,$0B,$0B,$0C,$7E,$7F,$07,$06,$80,$99,$9A,$07,$09,$00,$0A,$66,$67,$1E,$1F
  .byte $60,$61,$14,$14,$A2,$A3,$0C,$0D,$68,$68,$7E,$7F,$85,$86,$7E,$7F,$80,$80,$99,$9A,$07,$06,$00,$0A,$0B,$0B,$0C,$0D,$0D,$68,$68,$60
  .byte $61,$14,$14,$83,$84,$07,$04,$68,$0D,$0D,$9C,$9D,$80,$80,$85,$86,$07,$04,$00,$18,$19,$1A,$1B,$0C,$0D,$0E,$0F,$10,$11,$12,$C3,$9B
  .byte $07,$03,$14,$8E,$8B,$68,$68,$0D,$C4,$A0,$A1,$85,$86,$0D,$0D,$07,$04,$00,$6B,$6C,$63,$63,$64,$65,$00,$00,$17,$00,$60,$8C,$8D,$07
  .byte $03,$14,$1E,$1F,$10,$11,$C4,$0B,$0B,$0C,$07,$04,$0D,$07,$04,$00,$6F,$A4,$07,$04,$63,$6D,$6E,$09,$00,$12,$13,$14,$14,$1E,$1F,$0D
  .byte $0D,$1C,$1D,$A2,$A3,$0C,$07,$03,$0D,$0E,$0F,$00,$00,$08,$00,$6B,$6C,$69,$6A,$6B,$6C,$63,$63,$6D,$6E,$60,$61,$14,$14,$83,$84,$87
  .byte $88,$14,$14,$1E,$1F,$0D,$0D,$0E,$0F,$07,$04,$00,$16,$00,$08,$09,$13,$14,$08,$09,$0A,$0B,$1C,$1D,$71,$71,$72,$73,$07,$04,$74,$75
  .byte $76,$12,$12,$13,$14,$07,$07,$00,$17,$07,$06,$00,$08,$09,$13,$14,$08,$09,$71,$71,$72,$73,$75,$76,$12,$12,$13,$14,$07,$03,$00,$1E
  .byte $15,$07,$0A,$00,$17,$15,$07,$04,$00,$15,$08,$09,$71,$71,$12,$12,$13,$14,$00,$15,$07,$04,$00,$15,$07,$03,$00,$15,$07,$04,$00,$1E
  .byte $00,$15,$07,$08,$00,$08,$09,$13,$14,$07,$05,$00,$15,$07,$03,$00,$15,$00,$00,$16,$16,$07,$05,$00,$17,$17,$07,$07,$00,$16,$07,$05
  .byte $00,$16,$15,$07,$0D,$00,$16,$07,$06,$00,$15,$07,$07,$00,$16,$00,$00,$17,$00,$16,$07,$04,$00,$1E,$07,$04,$00,$15,$07,$06,$00,$17
  .byte $07,$04,$00,$15,$07,$0E,$00
G_NT10:
  .byte $07,$04,$00,$08,$07,$03,$00,$09,$00,$09,$07,$0B,$00,$0A,$07,$0E,$00,$0A,$07,$08,$00,$0A,$07,$04,$00,$0A,$0B,$00,$08,$07,$04,$00
  .byte $0B,$07,$09,$00,$08,$00,$00,$0A,$07,$05,$00,$0C,$0D,$0E,$0F,$00,$00,$08,$07,$0E,$00,$09,$07,$05,$00,$08,$00,$00,$0C,$0D,$07,$04
  .byte $10,$0E,$0F,$00,$00,$08,$0A,$07,$07,$00,$09,$07,$0A,$00,$0C,$0D,$10,$10,$11,$12,$13,$14,$10,$10,$0E,$0F,$07,$04,$00,$09,$07,$0E
  .byte $00,$15,$16,$17,$11,$12,$18,$18,$8C,$8D,$10,$10,$11,$12,$00,$0B,$07,$0A,$00,$09,$00,$08,$07,$03,$00,$0A,$0B,$0B,$0C,$0D,$0D,$0E
  .byte $0F,$60,$61,$14,$14,$83,$84,$1C,$1D,$15,$16,$00,$08,$07,$0A,$00,$18,$19,$1A,$1B,$0C,$0D,$87,$88,$15,$16,$68,$68,$60,$61,$07,$06
  .byte $14,$15,$16,$62,$07,$07,$00,$18,$19,$63,$63,$69,$6A,$87,$88,$07,$04,$14,$8E,$8B,$68,$68,$60,$61,$1E,$1F,$60,$61,$14,$14,$15,$16
  .byte $62,$00,$09,$62,$18,$19,$63,$63,$69,$6A,$0E,$90,$66,$67,$14,$89,$9B,$07,$03,$14,$8E,$8B,$68,$68,$0D,$0D,$12,$13,$14,$14,$1E,$1F
  .byte $07,$04,$00,$6B,$6C,$63,$63,$64,$65,$0A,$0B,$0B,$0C,$60,$8C,$8D,$07,$03,$14,$1E,$1F,$10,$11,$87,$88,$14,$14,$1E,$1F,$0D,$0D,$00
  .byte $17,$00,$17,$10,$11,$6B,$6C,$63,$63,$1A,$1B,$0C,$0D,$68,$68,$60,$61,$1E,$1F,$0D,$0D,$00,$0A,$66,$67,$1E,$1F,$0D,$0D,$0E,$0F,$07
  .byte $05,$00,$08,$6F,$A4,$07,$04,$63,$64,$65,$10,$11,$68,$68,$0D,$0D,$0E,$0F,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$07,$05,$00,$08,$00,$00
  .byte $6B,$6C,$69,$6A,$6B,$6C,$63,$63,$6D,$6E,$10,$11,$0E,$0F,$18,$19,$1A,$1B,$0C,$0D,$0E,$0F,$00,$00,$62,$00,$09,$07,$05,$00,$08,$09
  .byte $13,$14,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$1F,$60,$0C,$0C,$1C,$1D,$13,$14,$07,$06,$00,$15,$07,$03,$00,$17,$1E,$00,$00,$17,$07,$03
  .byte $00,$08,$09,$0A,$0B,$07,$04,$0C,$1C,$1D,$13,$14,$07,$03,$00,$1E,$00,$15,$07,$0A,$00,$15,$15,$07,$04,$00,$08,$09,$0A,$0B,$1C,$1D
  .byte $13,$14,$00,$1E,$07,$0A,$00,$16,$00,$00,$15,$07,$07,$00,$1E,$00,$00,$08,$09,$13,$14,$00,$00,$16,$00,$00,$17,$07,$14,$00,$1E,$07
  .byte $08,$00,$16,$00,$00,$15,$00,$00,$17,$00,$00,$16,$07,$03,$00,$1E,$07,$08,$00,$15,$00,$15,$07,$0C,$00,$17,$07,$0A,$00,$17,$16,$17
  .byte $07,$0B,$00,$17,$00,$00,$15,$00,$1E,$07,$03,$00,$16,$1E,$00,$00
G_NT11:
  .byte $07,$08,$00,$0B,$07,$03,$00,$09,$00,$78,$79,$7A,$7B,$07,$07,$00,$0A,$07,$0C,$00,$09,$07,$06,$00,$15,$7D,$7E,$7C,$7C,$7A,$7B,$07
  .byte $07,$00,$08,$00,$00,$0B,$07,$04,$00,$08,$07,$06,$00,$0A,$00,$15,$69,$69,$6A,$81,$82,$7C,$7C,$7A,$7B,$08,$07,$03,$00,$0A,$00,$00
  .byte $0A,$07,$04,$00,$08,$07,$07,$00,$1E,$1F,$83,$84,$6A,$18,$19,$19,$81,$82,$7C,$7C,$7A,$7B,$00,$00,$0A,$07,$05,$00,$0B,$07,$06,$00
  .byte $0A,$00,$00,$67,$68,$62,$62,$86,$87,$19,$19,$8F,$90,$7C,$7C,$7F,$80,$08,$0A,$07,$10,$00,$19,$85,$63,$64,$65,$66,$19,$19,$81,$82
  .byte $7C,$7C,$91,$92,$07,$04,$00,$0A,$07,$0A,$00,$08,$00,$00,$AB,$0B,$0B,$0C,$0D,$0D,$10,$11,$68,$68,$C6,$C7,$C8,$C8,$C9,$CA,$00,$17
  .byte $07,$0C,$00,$1C,$1D,$A2,$A3,$0C,$07,$03,$0D,$08,$08,$07,$03,$68,$AB,$CB,$CC,$CD,$CE,$00,$00,$62,$00,$00,$62,$07,$03,$00,$17,$00
  .byte $00,$08,$00,$60,$61,$14,$14,$83,$84,$0E,$0F,$00,$00,$68,$68,$AB,$0B,$0B,$0C,$0D,$0D,$00,$00,$17,$08,$07,$05,$00,$62,$07,$04,$00
  .byte $68,$68,$60,$61,$14,$89,$96,$16,$00,$00,$CF,$9D,$D0,$D1,$0C,$07,$03,$0D,$08,$07,$0D,$00,$10,$11,$68,$68,$60,$8C,$8D,$14,$15,$16
  .byte $7E,$7F,$80,$80,$81,$82,$0D,$0D,$00,$17,$00,$00,$08,$08,$07,$04,$00,$17,$00,$18,$19,$6D,$6E,$10,$11,$68,$68,$60,$61,$14,$14,$8E
  .byte $D2,$A0,$A1,$85,$86,$0E,$0F,$07,$03,$00,$08,$00,$62,$07,$04,$00,$18,$19,$07,$04,$63,$6D,$6E,$10,$11,$68,$68,$60,$61,$B1,$0B,$0B
  .byte $0C,$0D,$0D,$09,$07,$05,$00,$09,$07,$03,$00,$62,$00,$6B,$6C,$69,$6A,$6B,$6C,$63,$63,$6D,$6E,$10,$11,$68,$AB,$0B,$0B,$0C,$07,$03
  .byte $0D,$07,$07,$00,$09,$07,$04,$00,$08,$09,$13,$14,$08,$09,$0A,$0B,$0C,$0C,$18,$19,$7A,$6C,$6C,$11,$12,$12,$13,$14,$17,$00,$1E,$17
  .byte $07,$05,$00,$16,$00,$00,$1E,$07,$04,$00,$17,$08,$09,$0A,$0B,$0C,$0C,$0F,$10,$11,$12,$13,$14,$07,$0A,$00,$1E,$07,$0B,$00,$08,$09
  .byte $0A,$0B,$1C,$1D,$13,$14,$07,$13,$00,$16,$00,$16,$07,$03,$00,$16,$08,$09,$13,$14,$15,$15,$07,$0C,$00,$17,$00,$00,$1E,$00,$16,$07
  .byte $1C,$00,$17,$07,$05,$00,$15,$00,$1E,$07,$06,$00,$16,$07,$0E,$00,$15,$00,$00,$15,$07,$08,$00,$15,$1E,$07,$04,$00,$17,$07,$07,$00
  .byte $16,$07,$05,$00
G_NT12:
  .byte $07,$09,$00,$0A,$07,$09,$00,$0B,$07,$03,$00,$09,$00,$09,$07,$13,$00,$08,$07,$03,$00,$0B,$08,$07,$0D,$00,$0B,$07,$0D,$00,$0C,$94
  .byte $95,$0F,$07,$0B,$00,$0B,$07,$03,$00,$0A,$0A,$07,$09,$00,$0C,$0D,$10,$96,$97,$10,$0E,$0F,$00,$0B,$07,$0A,$00,$0B,$07,$05,$00,$09
  .byte $07,$03,$00,$0C,$0D,$10,$10,$11,$12,$13,$14,$10,$10,$0E,$0F,$07,$03,$00,$08,$07,$0A,$00,$0B,$07,$04,$00,$15,$16,$17,$11,$12,$18
  .byte $18,$8C,$8D,$10,$10,$11,$12,$09,$00,$0A,$00,$0A,$0B,$07,$0C,$00,$0A,$0B,$0B,$0C,$0D,$0D,$87,$88,$14,$14,$1E,$1F,$0D,$0D,$1C,$1D
  .byte $15,$16,$07,$04,$00,$09,$62,$62,$00,$00,$08,$00,$00,$18,$19,$1A,$1B,$0C,$0D,$0E,$0F,$60,$61,$14,$14,$83,$84,$87,$88,$07,$04,$14
  .byte $15,$16,$09,$07,$09,$00,$6B,$6C,$63,$63,$64,$65,$00,$00,$68,$68,$60,$61,$07,$04,$14,$1E,$1F,$60,$61,$14,$14,$15,$16,$00,$08,$07
  .byte $06,$00,$10,$11,$6B,$6C,$63,$BC,$BD,$6E,$10,$11,$68,$68,$60,$61,$1E,$1F,$0D,$0D,$68,$68,$60,$61,$14,$14,$15,$16,$07,$04,$00,$18
  .byte $19,$6D,$6E,$10,$11,$6B,$BE,$D5,$63,$6D,$6E,$10,$11,$68,$68,$0D,$0D,$0E,$0F,$10,$11,$12,$13,$14,$14,$1E,$1F,$00,$00,$18,$19,$07
  .byte $04,$63,$6D,$6E,$6F,$A4,$63,$63,$69,$6A,$00,$00,$10,$11,$0E,$0F,$62,$00,$1C,$1D,$14,$14,$1E,$1F,$0D,$0D,$00,$00,$6B,$6C,$69,$6A
  .byte $6B,$6C,$07,$04,$63,$69,$6A,$0E,$0F,$62,$00,$00,$17,$08,$08,$00,$0A,$66,$67,$1E,$1F,$0D,$0D,$0E,$0F,$00,$00,$10,$11,$0E,$0F,$10
  .byte $11,$6B,$6C,$69,$6A,$0E,$0F,$17,$07,$05,$00,$17,$00,$0A,$0B,$0B,$0C,$0D,$0D,$0E,$0F,$09,$07,$03,$00,$1E,$15,$07,$04,$00,$08,$09
  .byte $13,$14,$1F,$60,$18,$19,$00,$00,$1E,$16,$1F,$60,$0F,$10,$11,$12,$13,$14,$17,$00,$00,$17,$07,$04,$00,$16,$15,$00,$00,$16,$07,$03
  .byte $00,$0A,$0B,$0C,$0C,$18,$19,$1F,$60,$0C,$0C,$1C,$1D,$13,$14,$07,$07,$00,$16,$00,$00,$1E,$00,$15,$07,$04,$00,$17,$08,$09,$0A,$0B
  .byte $0C,$7B,$7C,$0C,$1C,$1D,$13,$14,$07,$08,$00,$15,$07,$08,$00,$1E,$07,$04,$00,$08,$09,$0A,$7D,$7E,$1D,$13,$14,$16,$00,$00,$15,$00
  .byte $00,$15,$07,$03,$00,$17,$17,$07,$0E,$00,$08,$09,$13,$14,$17,$17,$07,$0F,$00,$15,$00,$15,$00,$00,$17,$15,$07,$05,$00,$1E,$07,$04
  .byte $00,$1E,$07,$09,$00,$1E,$00,$15,$07,$0B,$00,$15,$07,$0E,$00,$15,$00,$00
G_NT13:
  .byte $00,$0B,$07,$0A,$00,$0A,$07,$0A,$00,$0A,$07,$04,$00,$09,$07,$11,$00,$1E,$1F,$60,$61,$07,$08,$00,$08,$07,$07,$00,$0B,$00,$0B,$07
  .byte $03,$00,$09,$07,$03,$00,$1E,$1F,$07,$04,$62,$60,$61,$0A,$00,$00,$09,$00,$0B,$07,$10,$00,$1E,$1F,$62,$62,$65,$66,$67,$68,$62,$62
  .byte $60,$61,$00,$00,$0A,$07,$05,$00,$0B,$07,$04,$00,$0A,$07,$04,$00,$09,$15,$63,$64,$65,$66,$18,$18,$6B,$6C,$62,$62,$65,$66,$07,$12
  .byte $00,$15,$69,$69,$6A,$07,$03,$18,$9A,$63,$64,$65,$66,$18,$18,$07,$05,$00,$0A,$0A,$07,$05,$00,$09,$00,$17,$00,$1C,$1D,$A2,$A3,$0C
  .byte $07,$03,$0D,$C4,$0B,$0B,$0C,$07,$04,$0D,$62,$00,$C1,$D7,$D8,$9A,$17,$07,$03,$00,$08,$07,$03,$00,$1C,$1D,$14,$14,$1E,$1F,$0D,$0D
  .byte $87,$88,$A2,$A3,$0C,$07,$03,$0D,$0E,$0F,$09,$17,$7E,$D9,$DA,$80,$99,$9A,$00,$17,$07,$04,$00,$60,$61,$14,$14,$83,$84,$0E,$0F,$60
  .byte $61,$14,$14,$83,$84,$0E,$0F,$08,$07,$03,$00,$68,$68,$7E,$7F,$80,$80,$99,$9A,$07,$04,$00,$68,$68,$60,$61,$14,$14,$15,$16,$68,$68
  .byte $60,$61,$14,$14,$15,$16,$07,$04,$00,$68,$68,$9C,$9D,$80,$80,$85,$86,$07,$03,$00,$09,$10,$11,$12,$DB,$DC,$14,$1E,$1F,$10,$11,$68
  .byte $68,$60,$61,$14,$89,$96,$16,$00,$00,$10,$9F,$A0,$A1,$85,$86,$0D,$0D,$07,$03,$00,$17,$00,$09,$60,$DD,$DE,$1F,$0D,$0D,$00,$00,$10
  .byte $11,$12,$13,$14,$9E,$8D,$14,$15,$16,$0A,$0B,$0B,$0C,$07,$04,$0D,$08,$07,$05,$00,$68,$68,$0D,$0D,$0E,$0F,$07,$03,$00,$0A,$66,$67
  .byte $1E,$1F,$60,$61,$14,$14,$A2,$A3,$0C,$07,$03,$0D,$0E,$0F,$00,$00,$08,$07,$03,$00,$10,$11,$0E,$0F,$07,$04,$00,$0A,$0B,$0B,$0C,$0D
  .byte $0D,$68,$68,$60,$61,$1E,$1F,$0D,$0D,$0E,$0F,$00,$17,$16,$07,$0B,$00,$1F,$60,$0F,$10,$11,$12,$13,$14,$08,$09,$71,$71,$12,$12,$13
  .byte $14,$07,$03,$00,$15,$07,$0A,$00,$1F,$60,$07,$04,$0C,$0D,$0E,$07,$04,$00,$08,$09,$13,$14,$07,$08,$00,$1E,$07,$07,$00,$0A,$0B,$1C
  .byte $1D,$0A,$0B,$0C,$0C,$18,$19,$07,$0D,$00,$17,$07,$08,$00,$08,$09,$13,$14,$08,$09,$0A,$0B,$1C,$1D,$16,$00,$00,$1E,$07,$03,$00,$17
  .byte $07,$04,$00,$16,$16,$17,$07,$05,$00,$17,$07,$07,$00,$08,$09,$13,$14,$15,$00,$00,$17,$07,$0A,$00,$17,$07,$05,$00,$17,$15,$07,$03
  .byte $00,$15,$17,$16,$16,$00,$17,$00,$17,$00,$00,$15,$17,$07,$10,$00,$15,$07,$05,$00,$16,$07,$10,$00
G_NT14:
  .byte $07,$09,$00,$0A,$00,$00,$0B,$00,$0A,$08,$00,$00,$0B,$00,$00,$0A,$00,$0B,$07,$04,$00,$08,$00,$0A,$00,$00,$0A,$07,$03,$00,$09,$00
  .byte $00,$0B,$09,$07,$04,$00,$1E,$9B,$9C,$61,$00,$0A,$07,$1A,$00,$67,$9D,$9E,$62,$60,$61,$00,$00,$08,$07,$05,$00,$09,$07,$10,$00,$0A
  .byte $19,$19,$67,$68,$62,$62,$60,$61,$07,$05,$00,$08,$00,$0A,$07,$05,$00,$0B,$07,$04,$00,$0B,$00,$0C,$0D,$0E,$0F,$07,$04,$19,$67,$68
  .byte $62,$62,$60,$61,$0A,$07,$08,$00,$08,$0B,$00,$08,$07,$03,$00,$0C,$0D,$07,$04,$10,$9F,$A0,$07,$04,$19,$67,$68,$62,$62,$60,$61,$07
  .byte $05,$00,$0A,$00,$17,$17,$00,$09,$00,$00,$0A,$66,$67,$1E,$1F,$60,$61,$14,$14,$8E,$8B,$07,$04,$68,$7E,$7F,$80,$80,$99,$9A,$07,$0A
  .byte $00,$0A,$0B,$0B,$0C,$0D,$0D,$68,$68,$60,$61,$14,$14,$8E,$8B,$07,$04,$68,$7E,$7F,$80,$80,$99,$9A,$08,$07,$05,$00,$18,$19,$1A,$1B
  .byte $0C,$0D,$0E,$0F,$10,$11,$68,$68,$60,$61,$14,$14,$8E,$8B,$68,$68,$9C,$9D,$80,$80,$85,$86,$07,$04,$00,$18,$19,$63,$63,$69,$6A,$0E
  .byte $0F,$18,$E0,$BD,$6E,$10,$11,$12,$13,$14,$14,$1E,$1F,$10,$9F,$A0,$A1,$85,$86,$0D,$0D,$00,$09,$00,$00,$6B,$6C,$63,$63,$64,$65,$18
  .byte $E1,$E2,$72,$D5,$63,$6D,$6E,$60,$61,$1E,$1F,$0D,$0D,$0A,$0B,$0B,$0C,$07,$04,$0D,$07,$04,$00,$10,$11,$6B,$6C,$07,$03,$63,$E3,$E4
  .byte $6A,$6B,$6C,$63,$63,$AC,$AD,$0D,$0D,$87,$88,$A2,$A3,$0C,$07,$03,$0D,$0E,$0F,$07,$04,$00,$09,$00,$10,$11,$6B,$6C,$63,$63,$64,$65
  .byte $10,$11,$6B,$6C,$69,$6A,$87,$88,$14,$14,$1E,$1F,$0D,$0D,$0E,$0F,$00,$00,$08,$07,$06,$00,$09,$6F,$A4,$63,$63,$69,$6A,$00,$00,$10
  .byte $11,$0E,$90,$66,$67,$1E,$1F,$0D,$0D,$0E,$0F,$00,$00,$09,$00,$00,$08,$07,$06,$00,$0A,$0B,$1C,$1D,$13,$14,$07,$03,$00,$16,$6B,$6C
  .byte $6C,$11,$12,$12,$13,$14,$00,$16,$07,$0C,$00,$08,$09,$13,$14,$00,$1E,$00,$00,$1F,$60,$0F,$10,$11,$12,$13,$14,$07,$0F,$00,$17,$00
  .byte $15,$07,$03,$00,$15,$00,$00,$0A,$0B,$1C,$1D,$13,$14,$17,$07,$04,$00,$15,$15,$07,$0E,$00,$17,$00,$00,$17,$00,$08,$09,$13,$14,$00
  .byte $00,$16,$07,$0A,$00,$15,$07,$03,$00,$16,$07,$07,$00,$16,$07,$0D,$00,$1E,$00,$00,$15,$07,$05,$00,$1E,$07,$03,$00,$1E,$00,$16,$07
  .byte $05,$00,$15,$07,$04,$00,$1E,$17,$07,$04,$00,$15,$17,$07,$0A,$00,$1E,$07,$0E,$00,$15,$07,$03,$00,$16,$00,$17,$17,$00,$00,$16,$00
G_NT15:
  .byte $07,$06,$00,$0B,$0A,$07,$06,$00,$78,$79,$7A,$7B,$00,$00,$09,$09,$00,$0B,$07,$09,$00,$08,$0A,$0A,$07,$08,$00,$78,$79,$07,$04,$7C
  .byte $7A,$7B,$07,$15,$00,$0A,$00,$15,$7D,$7E,$7F,$80,$81,$82,$7C,$A2,$A3,$7B,$07,$07,$00,$0A,$07,$0C,$00,$15,$69,$69,$6A,$18,$18,$19
  .byte $19,$81,$A4,$A5,$80,$00,$09,$00,$00,$08,$07,$06,$00,$0A,$07,$06,$00,$1E,$1F,$83,$84,$6A,$07,$03,$18,$07,$04,$19,$18,$18,$78,$79
  .byte $7A,$7B,$07,$0B,$00,$09,$00,$00,$67,$68,$62,$62,$86,$87,$18,$18,$07,$04,$19,$A6,$A7,$07,$04,$7C,$7A,$7B,$07,$07,$00,$62,$07,$04
  .byte $00,$68,$68,$7E,$7F,$80,$80,$81,$E6,$10,$11,$68,$AB,$CB,$CC,$CD,$CE,$C6,$C7,$C8,$C8,$C9,$CA,$07,$06,$00,$62,$07,$03,$00,$07,$03
  .byte $68,$AB,$A0,$A1,$85,$86,$00,$00,$C0,$0B,$0B,$0C,$0D,$0D,$68,$AB,$CB,$CC,$CD,$CE,$07,$07,$00,$08,$00,$00,$10,$11,$AB,$0B,$0B,$0C
  .byte $0D,$0D,$C1,$C2,$D0,$D1,$0C,$07,$03,$0D,$AB,$0B,$0B,$0C,$0D,$0D,$00,$17,$09,$00,$17,$62,$07,$04,$00,$1C,$1D,$A2,$A3,$0C,$07,$03
  .byte $0D,$7E,$7F,$80,$80,$81,$82,$E7,$E8,$D0,$D1,$0C,$07,$03,$0D,$07,$08,$00,$1C,$1D,$07,$03,$14,$89,$E9,$84,$0E,$0F,$68,$68,$7E,$7F
  .byte $07,$04,$80,$85,$86,$07,$04,$0D,$07,$04,$00,$62,$07,$03,$00,$60,$61,$1E,$1F,$60,$8C,$8D,$14,$15,$16,$07,$03,$68,$AB,$A0,$A1,$85
  .byte $86,$07,$04,$0D,$0E,$0F,$00,$00,$09,$07,$03,$00,$08,$00,$68,$68,$0D,$0D,$68,$68,$60,$61,$14,$14,$8E,$8B,$AB,$0B,$0B,$0C,$07,$04
  .byte $0D,$0E,$0F,$09,$07,$09,$00,$10,$11,$0E,$0F,$10,$11,$68,$68,$60,$61,$14,$14,$A2,$A3,$0C,$07,$03,$0D,$0E,$0F,$17,$07,$09,$00,$1E
  .byte $07,$07,$00,$08,$09,$71,$7F,$80,$81,$75,$76,$12,$12,$13,$14,$07,$16,$00,$7A,$6C,$6C,$11,$12,$12,$13,$14,$00,$17,$07,$0E,$00,$16
  .byte $07,$03,$00,$17,$00,$1F,$60,$0F,$10,$68,$82,$83,$0E,$07,$06,$00,$15,$00,$00,$16,$07,$0A,$00,$15,$07,$03,$00,$0A,$0B,$1C,$1D,$0A
  .byte $7D,$7E,$1D,$1E,$15,$16,$07,$04,$00,$17,$07,$05,$00,$17,$07,$06,$00,$1E,$07,$03,$00,$08,$09,$13,$14,$08,$09,$13,$14,$00,$17,$07
  .byte $08,$00,$17,$00,$16,$07,$07,$00,$16,$07,$05,$00,$17,$07,$0A,$00,$1E,$07,$05,$00,$17,$07,$20,$00

; big letters of the title from 96 (third 0): blue CRYSTAL, green GARDENS
BIG_P:
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
BIG_C:
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $40,$40,$40,$50,$50,$70,$70,$F0,$40,$40,$40,$50,$50,$70,$70,$F0
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
  .byte $30,$30,$30,$30,$30,$20,$20,$20,$30,$30,$30,$30,$30,$20,$20,$20
  .byte $20,$20,$C0,$C0,$C0,$20,$20,$30,$20,$20,$C0,$C0,$C0,$20,$20,$30
BIG_LEN = 704
TXT_BIG:
  .byte 3,9,96,97,100,101,104,105,108,109,112,113,116,117,120,121,0
  .byte 4,9,98,99,102,103,106,107,110,111,114,115,118,119,122,123,0
  .byte 6,9,168,169,160,161,144,145,172,173,176,177,180,181,152,153,0
  .byte 7,9,170,171,162,163,146,147,174,175,178,179,182,183,154,155,0
  .byte $FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$3C,$3C,$3C,$35,$35,$35,$2F,$2F,$2F,$28,$28,$28,$24,$24,$24
  .byte $1E,$1E,$1E,$1B,$1B,$1B,$18,$18,$18,$95,$80,$70,$64,$5A,$52,$4B
  .byte $45,$21,$21,$21,$00,$00,$2A,$2A,$2A,$00,$00,$21,$21,$2A,$2D,$30
  .byte $34,$39,$3F,$45,$4E,$59,$68,$45,$38,$2F,$29,$24,$20,$1D,$1A,$BD
  .byte $BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$00,$00,$00,$EF,$EF,$EF,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$34,$38,$39,$3D,$46,$4B,$4C,$52,$5D,$64
  .byte $66,$6D,$7C,$86,$88,$92,$A6,$B3,$B5,$C3,$DE,$EF,$F3,$05,$29,$40
  .byte $44,$5D,$8D,$AB,$50,$50,$50,$3F,$3F,$3F,$35,$35,$35,$5F,$5F,$5F
  .byte $5F,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$2F,$2F,$2F,$2F,$3F,$3F,$3F
  .byte $3F,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$20,$2F,$2F,$2F,$2F,$2F,$00,$00,$00,$28,$28,$28
  .byte $28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$8E,$8E,$8E,$8E,$8E,$8E
  .byte $9F,$9F,$9F,$9F,$9F,$9F,$B3,$B3,$B3,$B3,$B3,$B3,$D5,$D5,$D5,$D5
  .byte $D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$28,$28
  .byte $28,$D0,$7B,$57,$43,$37,$2E,$28,$23,$20,$1D,$1A,$18,$30,$35,$3B
  .byte $42,$4B,$57,$68,$81,$AA,$FA
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07
  .byte $0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07,$0B,$0A,$09,$08,$07,$06,$05
  .byte $04,$0B,$0A,$09,$00,$00,$0B,$0A,$09,$00,$00,$0A,$08,$0B,$0A,$09
  .byte $09,$08,$07,$06,$06,$05,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0B
  .byte $0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$00,$00,$00,$0B,$0A,$09,$09
  .byte $08,$07,$06,$06,$05,$04,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07
  .byte $07,$07,$06,$06,$0C,$0B,$09,$0C,$0B,$09,$0C,$0B,$09,$0D,$0B,$0A
  .byte $08,$0D,$0B,$0A,$08,$0D,$0B,$0A,$08,$0D,$0B,$0A,$08,$0D,$0B,$0A
  .byte $08,$0D,$0B,$0A,$08,$0D,$0B,$0A,$08,$0D,$0D,$0C,$0C,$0B,$0B,$0A
  .byte $0A,$09,$09,$08,$08,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B
  .byte $0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0C,$0B,$0A,$08,$07,$06
  .byte $0C,$0B,$0A,$08,$07,$06,$0C,$0B,$0A,$08,$07,$06,$0C,$0C,$0B,$0B
  .byte $0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$07,$06,$06,$0C,$0A
  .byte $08,$0C,$0B,$0B,$0A,$09,$09,$08,$08,$07,$06,$06,$05,$0D,$0C,$0B
  .byte $0A,$09,$09,$08,$07,$06,$05
WH_START:
  .byte $00,$01,$04,$07,$0A,$0D,$10,$13,$16,$19,$21,$2D,$37,$3F,$56,$74
  .byte $7D,$A5,$BA,$DE,$E1,$ED
WH_LEN:
  .byte $00,$03,$03,$03,$03,$03,$03,$03,$03,$08,$0C,$0A,$08,$17,$1E,$09
  .byte $28,$15,$24,$03,$0C,$0A
W_SEED0 = 1
W_SEED1 = 2
W_SEED2 = 3
W_SEED3 = 4
W_SEED4 = 5
W_SEED5 = 6
W_SEED6 = 7
W_SEED7 = 8
W_JUMP = 9
W_MAG = 10
W_STEAL = 11
W_SCARE = 12
W_OWL = 13
W_DIE = 14
W_ACORN = 15
W_CLEAR = 16
W_EXTRA = 17
W_OVER = 18
W_BONUS = 19
W_TELE = 20
W_HIT = 21

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04
  .byte $04,$03,$03,$02,$02,$01,$01,$00,$00,$03,$03,$06,$06,$03,$03,$06
  .byte $06,$03,$03,$06,$06,$03,$03,$06,$06,$0C,$0A,$08,$06,$04,$02,$00
  .byte $00,$07,$06,$05,$04,$03
EX_NP:
  .byte $00,$1A,$1B,$1C,$1D,$1A,$1B,$1C,$1D,$1A,$1B,$1C,$1D,$1A,$1B,$1C
  .byte $1D,$1A,$1B,$1C,$1D,$1A,$1B,$1C,$1D,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$06,$07,$08,$09,$0A,$0B,$0C
  .byte $0D,$03,$03,$03,$03,$03
EX_VC:
  .byte $00,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03
  .byte $03,$02,$02,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D
  .byte $B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$03,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$19,$29,$31
EX_LEN:
  .byte $00,$18,$10,$08,$05
S_MOLE = 1
S_ROLL = 2
S_POP = 3
S_HOP = 4

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <32,>32, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$60, <32,>32, <SMALL_COL,>SMALL_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <32,>32, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$68, <32,>32, <SMALL_COL,>SMALL_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <32,>32, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$70, <32,>32, <SMALL_COL,>SMALL_COL
  .byte 0
TILE_LOAD:
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $40,$40, <192,>192, <GT0_PLO,>GT0_PLO
  .byte 3, $40,$60, <192,>192, <GT0_CLO,>GT0_CLO
  .byte 1, $00,$43, <584,>584, <GT0_PHI,>GT0_PHI
  .byte 3, $00,$63, <584,>584, <GT0_CHI,>GT0_CHI
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $40,$48, <192,>192, <GT1_PLO,>GT1_PLO
  .byte 3, $40,$68, <192,>192, <GT1_CLO,>GT1_CLO
  .byte 1, $00,$4B, <1112,>1112, <GT1_PHI,>GT1_PHI
  .byte 3, $00,$6B, <1112,>1112, <GT1_CHI,>GT1_CHI
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 1, $40,$50, <192,>192, <GT2_PLO,>GT2_PLO
  .byte 3, $40,$70, <192,>192, <GT2_CLO,>GT2_CLO
  .byte 1, $00,$53, <288,>288, <GT2_PHI,>GT2_PHI
  .byte 3, $00,$73, <288,>288, <GT2_CHI,>GT2_CHI
  .byte 0
S_BIG = S_MOLE
S_SMALL = S_POP

; world names
TXT_W0:
  .byte 10,12,"ORCHARD",0
  .byte $FF
TXT_W1:
  .byte 10,13,"DUNES",0
  .byte $FF
TXT_W2:
  .byte 10,11,"ICE HOUSE",0
  .byte $FF
TXT_W3:
  .byte 10,10,"NIGHT GARDEN",0
  .byte $FF
NGARDENS = 16
