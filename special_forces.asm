;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   SPECIAL FORCES  -  an original side-scrolling action game  ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: crystal gardens (VDP, NMI + trampoline $0FD0, AY     ;
;   engine, 2 players taking turns)                            ;
;                                                              ;
;   - a commando crosses an enemy camp from left to right,     ;
;     sector after sector: ground and two floors of steel      ;
;     walkways joined by ladders; the camp scrolls in steps    ;
;     of 8 pixels (two name tables: the hidden one is built    ;
;     in 3 frames, one band of 7 rows each, then shown)        ;
;   - joystick: left / right = run, up = jump or climb,        ;
;     down = kneel (the bullets fly over) or climb down,       ;
;     button 1 = knife (or plant a charge on a target),        ;
;     button 2 = the special weapon                            ;
;   - sentries, riflemen (kneel and shoot), sappers (jump      ;
;     between the floors), shield men (only from above or      ;
;     behind), machine-gun nests (3 knife hits), couriers      ;
;     (drop a machine gun, a mortar or a timed charge),        ;
;     rolling barrels, barbed wire and mines                   ;
;   - 4 sectors: perimeter, barracks, fuel depot, command      ;
;     bunker; at the end of each one plant the charges on      ;
;     the targets, then the objective blows up; 2 gates per    ;
;     sector to start again after a life lost                  ;
;   - points: sentry 100, sapper 150, rifleman 200, courier    ;
;     300, shield man 500, nest 800, charge planted 500,       ;
;     sector 5000 + time x 10; 3 lives, one more at 20000      ;
;     and every 50000; 1 or 2 players taking turns             ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     sector tune, fanfare, knife, clank, shots, mortar,       ;
;     ticks of the charges, explosions                         ;
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
SECTOR      = $40      ; ---- block of the player, saved: sector 0-3
LOOPN       = $41      ;      times round the 4 sectors
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
CHECKP      = $43      ;      column of the last gate passed (start of the view)
FRESH       = $44      ;      1 = the sector starts from the beginning
PBLOCK      = 5
DIFF        = $45      ; difficulty 0-11
GSTATE      = $46      ; 0 playing, 1 hit, 2 charges ticking, 3 objective blowing up
GT          = $47      ; timer of GSTATE
JOYC        = $48      ; both joysticks drive the player playing
JOYP        = $49      ; JOYC of the frame before
HUDD        = $4A      ; 1 = the HUD changed
FIRSTT      = $4B      ; 1 = first turn of the game
SHOWP       = $4C      ; 1 = the intro before the sector
RR          = $4D      ; first object in the SAT (turns, 1-13)
GF          = $4E      ; frames of play
TIMEH       = $4F      ; time left (BCD): hundreds
TIMEL       = $50      ;                  tens and units
TSUB        = $51      ; frames into the second
WX          = $52      ; first column of the camp on the screen
SCPH        = $53      ; scroll: 0 idle, 1-3 band being built
HOFF        = $54      ; name table of NT_XY and CLEAR_NT (0 / 4)
VIS         = $55      ; name table shown (0 = $3800, 4 = $3C00)
WEAP        = $56      ; special weapon: 0 none, 1 machine gun, 2 mortar, 3 timed charge
AMMO        = $57      ; shots left
STAB        = $58      ; knife: frames left
STRM        = $59      ; frames to the next soldier from the edges
TGTN        = $5A      ; targets of the sector
TGTD        = $5B      ; targets with the charge (bit mask)
FLIPP       = $5D      ; 1 = show the hidden name table at the next frame
FLP         = $5E      ; 2 bytes: flags of the columns of the sector

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
SLOT        = $72      ; object being moved
KNEEL       = $73      ; 1 = the commando is kneeling
CNT         = $74
BONL        = $75      ; bonus (BCD)
BONH        = $76
SONG        = $77      ; tune to play
FIREC       = $78      ; frames before the next special shot
NEN         = $79      ; soldiers on the screen
HFL         = $7A      ; floor of the commando ($FF = in the air or on a ladder)
LADB        = $7B      ; ladder: floor at its foot
SPNP        = $7C      ; 2 bytes: next spawn of the sector
CX          = $7E      ; new object: x
CY          = $7F      ;             y / old y in BODY_AIR
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
BOFF        = $86      ; name table being built (0 / 4)
WXB         = $87      ; first column of the view being built
FL          = $88      ; new object: floor
TMPK        = $89      ; kind being checked
DXA         = $8A      ; ADIFF: the other value
LADDER      = $8B      ; 1 = the commando is on a ladder
MAXE        = $8C      ; most soldiers at the same time
HX          = $8D      ; commando: x and feet (copies for the checks)
HY          = $8E
VT          = $90      ; 32 bytes: band type of the 32 columns being built
MP0         = $E6      ; 2 bytes each: band maps of the sector
MP1         = $E8
MP2         = $EA

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
OX         = $E0         ; sprite being added: X on the screen, feet, pattern, colour
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

; ---------------- objects: slot 0 = the commando, 1-13 the rest (16 bytes per field)
NOB        = 14
O_K        = $0200       ; kind (K_*, 0 = free)
O_X        = $0210       ; x on the screen (8.8: integer)
O_XL       = $0220       ;                  fraction
O_Y        = $0230       ; feet (bullets: their line)
O_YL       = $0240
O_VY       = $0250       ; vertical speed 8.8 (down = positive)
O_VYL      = $0260
O_VX       = $0270       ; horizontal speed 8.8
O_VXL      = $0280
O_D        = $0290       ; facing: 0 right, 1 left
O_AIR      = $02A0       ; 1 = in the air
O_T        = $02B0       ; timer
O_S        = $02C0       ; state
O_H        = $02D0       ; hits left / weapon of a pickup
O_A        = $02E0       ; animation
O_FL       = $02F0       ; floor 0-2 while standing

K_HERO     = 1
K_SENT     = 2           ; 2-8: soldiers and the rest that kills by touch
K_RIFLE    = 3
K_SAPPER   = 4
K_SHIELD   = 5
K_NEST     = 6
K_COUR     = 7
K_BARREL   = 8
K_BULLET   = 9
K_HSHOT    = 10
K_SHELL    = 11
K_CHARGE   = 12          ; O_S = 0 timed charge, 1 charge on a target
K_BOOM     = 13
K_PICK     = 14
K_DEAD     = 15

SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
XLAT       = $0C00       ; material colours -> colours of the sector
PSAVE      = $0D00       ; 2 x 16: block of every player

; ---------------- parameters ----------------
BTN_MASK    = %00110000
GRAV        = $3C        ; gravity (8.8 fraction per frame)
STAB_T      = 12         ; frames of a knife thrust (it hits in frames 10-4)
GATE1       = 64         ; gates: first column of the view after a life lost
GATE2       = 128

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
  STA VIS
  STA HOFF
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
;  TITLE: the name, the enemies and what they are worth
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR SHOW_TABLE0
  JSR CLEAR_NT
  LDA #$00                     ; big letters over the camp tiles of third 0
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
  LDX #$00                     ; the commando and the enemies (sprites)
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

; one frame of the title: the soldiers run on the spot
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA FRAME_CNT
  AND #$08                     ; 0 or 8: the two steps
  STA T0
  LDA #PT_RUN
  CLC
  ADC T0
  STA SAT_BUFFER+2
  LDA #PT_SOL+4
  CLC
  ADC T0
  STA SAT_BUFFER+6
  LDA #PT_SHD+4
  CLC
  ADC T0
  STA SAT_BUFFER+18
  LDA #PT_COU+4
  CLC
  ADC T0
  STA SAT_BUFFER+22
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: sector 1, 3 lives for every player
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
  STZ SECTOR
  STZ LOOPN
  STZ CHECKP
  LDA #$02                     ; first extra life at 20000
  STA NEXTX
  LDA #1
  STA FRESH
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then a SECTOR
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE SECTOR_START
  INC SHOWP

SECTOR_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR SHOW_TABLE0
  JSR SET_SECTOR
  LDA FRESH
  BEQ .ss_old
  INC SHOWP                    ; a new sector: the intro
  STZ CHECKP
.ss_old:
  LDA SHOWP
  BEQ .ss_board
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT                   ; the tune: first turn or a new sector
  ORA FRESH
  BEQ .ss_short
  STZ FIRSTT
  STZ SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ss_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ss_t
  BRA .ss_w
.ss_short:
  LDA #120
  JSR WAIT_FRAMES
.ss_w:
  JSR VDP_INT_OFF
.ss_board:
  STZ SHOWP
  STZ FRESH
  JSR HIDE_SPRITES
  LDA #4                       ; both name tables to spaces (the HUD rows stay black)
  STA HOFF
  JSR CLEAR_NT
  STZ HOFF
  JSR CLEAR_NT
  JSR LOAD_TILES
  JSR START_SECTOR
  JSR DRAW_HUD_BOTH
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #30
  JSR WAIT_FRAMES


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR DO_FLIP                  ; the view built in the frames before
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  INC GF
  LDA GSTATE
  CMP #1
  BEQ .gl_hit
  CMP #3
  BEQ .gl_boom
  JSR UPDATE_HERO
  JSR UPDATE_OBJS
  JSR HERO_CHECKS
  JSR SCROLL
  JSR SPAWN
  JSR UPDATE_TIME
  LDA GSTATE
  CMP #2
  BNE .gl_hud
  JSR COUNTDOWN
  BRA .gl_hud
.gl_hit:
  DEC GT                       ; hit: the commando falls, the rest stops
  BRA .gl_hud
.gl_boom:
  JSR BLOW_UP
.gl_hud:
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  CMP #1
  BEQ .gl_lost
  CMP #3
  BNE GAME_LOOP
  LDA GT
  BNE GAME_LOOP
  JMP SECTOR_CLEAR
.gl_lost:
  LDA GT
  BNE GAME_LOOP
  JMP LOSE_LIFE

; the charges are ticking: the objective blows up when the time is over
COUNTDOWN:
  DEC GT
  BEQ .cd_go
  LDA GT
  AND #15
  BNE .cd_r
  LDA #W_TICK
  LDX #2
  JMP SFX_WHISTLE
.cd_go:
  LDA #3
  STA GSTATE
  LDA #120
  STA GT
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
  LDX #NOB-1                   ; the soldiers run away
.cd_k:
  LDA O_K,X
  CMP #K_CHARGE
  BEQ .cd_n
  STZ O_K,X
.cd_n:
  DEX
  BNE .cd_k
.cd_r:
  RTS

; the objective blows up: an explosion on every target, the backdrop flashes
BLOW_UP:
  DEC GT
  LDA GT
  AND #3
  BNE .bu_r
  LDA GT                       ; backdrop: white / black
  AND #4
  BEQ .bu_k
  LDA #$0F
.bu_k:
  ORA #$01
  JSR SET_BACKDROP
  LDA GT
  AND #15
  BNE .bu_r
  LDX #NOB-1                   ; the charges become explosions
.bu_c:
  LDA O_K,X
  CMP #K_CHARGE
  BEQ .bu_e
  CMP #K_BOOM
  BNE .bu_n
.bu_e:
  LDA #K_BOOM
  STA O_K,X
  LDA #20
  STA O_T,X
.bu_n:
  DEX
  BNE .bu_c
  LDA GT
  CMP #64
  BCC .bu_r
  LDA #S_BOOM
  LDX #2
  JMP SFX_BOOM
.bu_r:
  RTS

; A = backdrop colour (R7)
SET_BACKDROP:
  STA VREG
  LDA #(VDP_REGISTER_BITS | 7)
  STA VREG
  RTS


; ===============================================================
;  END OF A SECTOR
; ===============================================================
SECTOR_CLEAR:
  JSR VDP_INT_OFF
  LDA #$01
  JSR SET_BACKDROP
  LDX #NOB-1
.sc_e:
  STZ O_K,X
  DEX
  BPL .sc_e
  JSR BUILD_SAT
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  LDA VIS
  STA HOFF
  JSR PRINT
  STZ HOFF
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
  LDA #90
  JSR WAIT_FRAMES
  ; ---- bonus: 5000 + time x 10
  LDA TIMEL
  ASL A
  ASL A
  ASL A
  ASL A
  STA BONL
  LDA TIMEL
  LSR A
  LSR A
  LSR A
  LSR A
  STA T0
  LDA TIMEH
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  SED
  CLC
  ADC #$50
  CLD
  STA BONH
  JSR VDP_INT_OFF
  LDA VIS
  STA HOFF
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA BONH
  JSR PUT_2
  LDA BONL
  JSR PUT_2
  STZ HOFF
  LDA BONL
  STA PTS_L
  LDA BONH
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
.sc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sc_t
  LDA #60
  JSR WAIT_FRAMES
  LDA #1                       ; the next sector
  STA FRESH
  STZ CHECKP
  INC SECTOR
  LDA SECTOR
  CMP #4
  BCC .sc_n
  STZ SECTOR
  INC LOOPN
.sc_n:
  JMP SECTOR_START

LOSE_LIFE:
  LDX CURP
  DEC LIVES,X
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
  LDA VIS
  STA HOFF
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
  STZ HOFF
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
;  INTRO: player, sector name, what to do
; ===============================================================
INTRO:
  JSR SET_BLACK0
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
  LDA #<TXT_SECTOR
  STA TP
  LDA #>TXT_SECTOR
  STA TP+1
  JSR PRINT
  LDA SECTOR
  CLC
  ADC #$31
  STA VDATA
  LDX SECTOR
  LDA SNAME_LO,X
  STA TP
  LDA SNAME_HI,X
  STA TP+1
  JSR PRINT
  LDX SECTOR
  LDA SHINT_LO,X
  STA TP
  LDA SHINT_HI,X
  STA TP+1
  JMP PRINT

; tile 0 black in the 3 thirds (title, intro)
SET_BLACK0:
  LDX #2
.sb_l:
  PHX
  STZ T0
  TXA
  ASL A
  ASL A
  ASL A
  ORA #$60                     ; colour table $2000 + third * $800, write bit
  STA T1
  LDA #8
  STA T2
  STZ T3
  LDA #$11
  JSR VFILL
  PLX
  DEX
  BPL .sb_l
  RTS


; ===============================================================
;  HUD: scores on rows 0-1, sector / lives / weapon / time on row 23
;  (written in both name tables)
; ===============================================================
DRAW_HUD_BOTH:
  STZ HOFF
  JSR DRAW_TOP
  JSR DRAW_BOTTOM
  LDA #4
  STA HOFF
  JSR DRAW_TOP
  JSR DRAW_BOTTOM
  STZ HOFF
  RTS

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

; row 23: S + sector, spare lives, weapon and shots, time
DRAW_BOTTOM:
  LDX #23
  LDY #0
  JSR NT_XY
  LDA #'S'
  STA VDATA
  LDA SECTOR
  CLC
  ADC #$31
  STA VDATA
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
  STA VDATA
  LDA WEAP                     ; weapon icon and shots
  CLC
  ADC #T_KNIFE
  STA VDATA
  LDA WEAP
  BEQ .db_nw
  LDA AMMO
  ORA #$30
  BRA .db_w
.db_nw:
  LDA #$20
.db_w:
  STA VDATA
  LDX #23
  LDY #21
  JSR NT_XY
  LDA #<TXT_TIME
  STA TP
  LDA #>TXT_TIME
  STA TP+1
  LDY #0
.db_t:
  LDA (TP),Y
  BEQ .db_te
  STA VDATA
  INY
  BRA .db_t
.db_te:
  LDA TIMEH
  ORA #$30
  STA VDATA
  LDA TIMEL
  JMP PUT_2

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  STZ HOFF
  LDX CURP
  JSR DRAW_SCORE
  JSR DRAW_BOTTOM
  LDA #4
  STA HOFF
  LDX CURP
  JSR DRAW_SCORE
  JSR DRAW_BOTTOM
  STZ HOFF
.uh_r:
  RTS

; a second less; at zero the commando is lost
UPDATE_TIME:
  INC TSUB
  LDA TSUB
  CMP #60
  BCC .ut_r
  STZ TSUB
  LDA TIMEH
  ORA TIMEL
  BEQ .ut_r
  SED
  LDA TIMEL
  SEC
  SBC #1
  STA TIMEL
  LDA TIMEH
  SBC #0
  STA TIMEH
  CLD
  LDA #1
  STA HUDD
  LDA TIMEH
  ORA TIMEL
  BNE .ut_r
  JMP HERO_DIE
.ut_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP
  LDA CURP
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA SECTOR,Y
  STA PSAVE,X
  INX
  INY
  CPY #PBLOCK
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.lp_b:
  LDA PSAVE,X
  STA SECTOR,Y
  INX
  INY
  CPY #PBLOCK
  BNE .lp_b
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 20000, then every 50000
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
  ADC #$05
  CLD
  BCC .as_x
  LDA #$FF                     ; past 950000: no more
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
;  THE CAMP: sector, view, scroll in steps of 8 pixels, spawns
; ===============================================================
; difficulty, colours, maps and flags of the sector
SET_SECTOR:
  LDA LOOPN                    ; difficulty: sector + 4 per time round, at most 11
  ASL A
  ASL A
  CLC
  ADC SECTOR
  CMP #12
  BCC .se_d
  LDA #11
.se_d:
  STA DIFF
  LSR A                        ; soldiers at the same time: 3 + difficulty / 3 (at most 6)
  LSR A
  CLC
  ADC #3
  CMP #7
  BCC .se_m
  LDA #6
.se_m:
  STA MAXE
  LDA SECTOR                   ; the 3 band maps: MAP_LO/HI[sector * 3 + band]
  ASL A
  ADC SECTOR
  TAY
  LDX #0
.se_b:
  LDA MAP_LO,Y
  STA MP0,X
  LDA MAP_HI,Y
  STA MP0+1,X
  INY
  INX
  INX
  CPX #6
  BNE .se_b
  LDX SECTOR
  LDA FLG_LO,X
  STA FLP
  LDA FLG_HI,X
  STA FLP+1
  LDA TG_N,X
  STA TGTN
  LDA SECTOR                   ; XLAT[m] = palette[m >> 4] << 4 | palette[m & 15]
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0
  LDX #0
.se_x:
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
  BNE .se_x
  RTS

; the commando at the last gate, the view, the spawns from there
START_SECTOR:
  LDX #NOB-1
.st_o:
  STZ O_K,X
  DEX
  BPL .st_o
  LDA #K_HERO
  STA O_K
  LDA #24
  STA CX
  STZ FL
  LDX #0
  JSR NEW_OBJ
  LDA #K_HERO
  STA O_K
  STZ HFL
  STZ LADDER
  STZ STAB
  STZ KNEEL
  STZ FIREC
  STZ WEAP
  STZ AMMO
  STZ TGTD
  STZ GSTATE
  STZ TSUB
  STZ HUDD
  LDA #$01                     ; 180 seconds
  STA TIMEH
  LDA #$80
  STA TIMEL
  LDA #120
  STA STRM
  LDA #1
  STA RR
  LDA #$01
  JSR SET_BACKDROP
  LDA CHECKP
  STA WX
  LDX SECTOR                   ; skip the spawns before the view and in its first 24 columns
  LDA SPN_LO,X
  STA SPNP
  LDA SPN_HI,X
  STA SPNP+1
  LDA WX
  CLC
  ADC #24
  STA T0
.st_s:
  LDA (SPNP)
  CMP #$FF
  BEQ .st_v
  CMP T0
  BCS .st_v
  JSR NEXT_SPAWN
  BRA .st_s
.st_v:
  ; fall into DRAW_VIEW

; the whole view in the name table shown
DRAW_VIEW:
  LDA VIS
  STA BOFF
  LDA WX
  STA WXB
  LDA #0
  JSR BUILD_BAND
  LDA #1
  JSR BUILD_BAND
  LDA #2
  JMP BUILD_BAND

NEXT_SPAWN:
  LDA SPNP
  CLC
  ADC #3
  STA SPNP
  BCC .ns_r
  INC SPNP+1
.ns_r:
  RTS

; A = band (0-2): its 7 rows of the view from column WXB into the name table BOFF
BUILD_BAND:
  STA T5
  ASL A
  TAX
  LDA MP0,X
  STA PTR2
  LDA MP0+1,X
  STA PTR2+1
  LDY WXB                      ; band type of the 32 columns
  LDX #0
.bb_v:
  LDA (PTR2),Y
  STA VT,X
  INY
  INX
  CPX #32
  BNE .bb_v
  LDA T5                       ; first row = 2 + band * 7
  ASL A
  ASL A
  ASL A
  SEC
  SBC T5
  CLC
  ADC #2
  STA T4
  LDA #7
  STA T3
  LDA BOFF
  STA HOFF
.bb_r:
  LDX T4
  LDY #0
  JSR NT_XY
  LDX T4
  LDA CR_LO-2,X
  STA PTR
  LDA CR_HI-2,X
  STA PTR+1
  JSR COPY_ROW
  INC T4
  DEC T3
  BNE .bb_r
  STZ HOFF
  RTS

; the 32 tiles of a row: ROWr[VT[c]] where the VDP points
COPY_ROW:
  LDY VT+0
  LDA (PTR),Y
  STA VDATA
  LDY VT+1
  LDA (PTR),Y
  STA VDATA
  LDY VT+2
  LDA (PTR),Y
  STA VDATA
  LDY VT+3
  LDA (PTR),Y
  STA VDATA
  LDY VT+4
  LDA (PTR),Y
  STA VDATA
  LDY VT+5
  LDA (PTR),Y
  STA VDATA
  LDY VT+6
  LDA (PTR),Y
  STA VDATA
  LDY VT+7
  LDA (PTR),Y
  STA VDATA
  LDY VT+8
  LDA (PTR),Y
  STA VDATA
  LDY VT+9
  LDA (PTR),Y
  STA VDATA
  LDY VT+10
  LDA (PTR),Y
  STA VDATA
  LDY VT+11
  LDA (PTR),Y
  STA VDATA
  LDY VT+12
  LDA (PTR),Y
  STA VDATA
  LDY VT+13
  LDA (PTR),Y
  STA VDATA
  LDY VT+14
  LDA (PTR),Y
  STA VDATA
  LDY VT+15
  LDA (PTR),Y
  STA VDATA
  LDY VT+16
  LDA (PTR),Y
  STA VDATA
  LDY VT+17
  LDA (PTR),Y
  STA VDATA
  LDY VT+18
  LDA (PTR),Y
  STA VDATA
  LDY VT+19
  LDA (PTR),Y
  STA VDATA
  LDY VT+20
  LDA (PTR),Y
  STA VDATA
  LDY VT+21
  LDA (PTR),Y
  STA VDATA
  LDY VT+22
  LDA (PTR),Y
  STA VDATA
  LDY VT+23
  LDA (PTR),Y
  STA VDATA
  LDY VT+24
  LDA (PTR),Y
  STA VDATA
  LDY VT+25
  LDA (PTR),Y
  STA VDATA
  LDY VT+26
  LDA (PTR),Y
  STA VDATA
  LDY VT+27
  LDA (PTR),Y
  STA VDATA
  LDY VT+28
  LDA (PTR),Y
  STA VDATA
  LDY VT+29
  LDA (PTR),Y
  STA VDATA
  LDY VT+30
  LDA (PTR),Y
  STA VDATA
  LDY VT+31
  LDA (PTR),Y
  STA VDATA
  RTS

; the hidden name table becomes the one shown (just after the NMI, still in the vblank)
DO_FLIP:
  LDA FLIPP
  BEQ .df_r
  STZ FLIPP
  LDA VIS
  EOR #4
  STA VIS
  JMP SET_R2
.df_r:
  RTS

SHOW_TABLE0:
  STZ VIS
  STZ FLIPP
  STZ SCPH
  ; fall into SET_R2

SET_R2:                        ; R2 = name table VIS ($0E = $3800, $0F = $3C00)
  LDA VIS
  LSR A
  LSR A
  ORA #$0E
  STA VREG
  LDA #(VDP_REGISTER_BITS | 2)
  STA VREG
  RTS

; the commando past the middle: the next view is built in the hidden table in 3 frames,
; then everything moves 8 pixels to the left and the hidden table is shown
SCROLL:
  LDA SCPH
  BNE .sc_b
  LDA O_X
  CMP #128
  BCC .sc_r
  LDA WX
  CMP #WXMAX
  BCS .sc_r
  LDA #1
  STA SCPH
  LDA WX
  INC A
  STA WXB
  LDA VIS
  EOR #4
  STA BOFF
.sc_b:
  LDA SCPH
  DEC A
  JSR BUILD_BAND
  INC SCPH
  LDA SCPH
  CMP #4
  BCC .sc_r
  STZ SCPH
  INC WX
  LDA #1
  STA FLIPP
  LDX #NOB-1                   ; everything 8 pixels to the left; gone past the left edge
.sc_o:
  LDA O_K,X
  BEQ .sc_n
  LDA O_X,X
  SEC
  SBC #8
  STA O_X,X
  BCC .sc_g
  CMP #4
  BCS .sc_n
.sc_g:
  CPX #0
  BEQ .sc_n
  STZ O_K,X
.sc_n:
  DEX
  BPL .sc_o
  LDA WX                       ; the gates
  CMP #GATE1
  BEQ .sc_c
  CMP #GATE2
  BNE .sc_r
.sc_c:
  STA CHECKP
.sc_r:
  RTS

; A = screen x -> A = flags of that column (uses Y)
FLAGS_X:
  LSR A
  LSR A
  LSR A
  CLC
  ADC WX
  TAY
  LDA (FLP),Y
  RTS

; the soldiers of the map when their column comes into view, and more from the edges
SPAWN:
  LDA GSTATE
  BEQ .sp_go
  RTS
.sp_go:
  LDA (SPNP)
  CMP #$FF
  BEQ .sp_st
  SEC
  SBC WX
  BCC .sp_skip                 ; already behind: never mind
  CMP #32
  BCS .sp_st
  ASL A
  ASL A
  ASL A
  ORA #4
  STA CX
  LDY #1
  LDA (SPNP),Y
  STA TMPK
  INY
  LDA (SPNP),Y
  STA FL
  JSR FREE_SLOT
  BCS .sp_st                   ; no room: again next frame
  LDA TMPK
  JSR NEW_SOLDIER
.sp_skip:
  JSR NEXT_SPAWN
.sp_st:
  DEC STRM
  BNE .sp_r
  LDX DIFF
  LDA STRM_T,X
  STA STRM
  JSR NEXT_RND
  AND #63
  CLC
  ADC STRM
  STA STRM
  LDA NEN
  CMP MAXE
  BCS .sp_r
  LDA SECTOR                   ; kind: STREAM_K[sector * 8 + random]
  ASL A
  ASL A
  ASL A
  STA T0
  JSR NEXT_RND
  AND #7
  ORA T0
  TAX
  LDA STREAM_K,X
  STA TMPK
  LDA #250                     ; from the right (barrels and couriers always)
  STA CX
  LDA TMPK
  CMP #K_COUR
  BCS .sp_f
  JSR NEXT_RND
  AND #1
  BEQ .sp_f
  LDA #6
  STA CX
.sp_f:
  JSR NEXT_RND                 ; a floor that is there
  AND #3
  CMP #3
  BNE .sp_fl
  LDA #0
.sp_fl:
  STA FL
  BEQ .sp_ok
  LDA CX
  JSR FLAGS_X
  LDY FL
  AND FMASK,Y
  BNE .sp_ok
  STZ FL
.sp_ok:
  JSR FREE_SLOT
  BCS .sp_r
  LDA TMPK
  JMP NEW_SOLDIER
.sp_r:
  RTS

; -> X = a free slot (1-13), C clear; C set if none
FREE_SLOT:
  LDX #1
.fs_l:
  LDA O_K,X
  BEQ .fs_y
  INX
  CPX #NOB
  BNE .fs_l
  SEC
  RTS
.fs_y:
  CLC
  RTS

; A = kind, X = slot: a new object at CX on the floor FL, everything else at 0
NEW_OBJ:
  STA O_K,X
  LDA CX
  STA O_X,X
  STZ O_XL,X
  STZ O_YL,X
  STZ O_VY,X
  STZ O_VYL,X
  STZ O_VX,X
  STZ O_VXL,X
  STZ O_AIR,X
  STZ O_T,X
  STZ O_S,X
  STZ O_A,X
  STZ O_H,X
  STZ O_D,X
  LDA FL
  STA O_FL,X
  TAY
  LDA FLOOR_Y,Y
  STA O_Y,X
  RTS

; A = kind, X = slot: a soldier facing the commando
NEW_SOLDIER:
  JSR NEW_OBJ
  LDA O_X                      ; the commando on the left: face left
  CMP CX
  BCS .nw_d
  LDA #1
  STA O_D,X
.nw_d:
  LDA O_K,X
  CMP #K_COUR
  BCC .nw_n
  LDA #1                       ; couriers and barrels go left
  STA O_D,X
.nw_n:
  LDA O_K,X
  CMP #K_NEST
  BNE .nw_v
  LDA #3
  STA O_H,X
  LDA #60
  STA O_T,X
  RTS                          ; nests do not move
.nw_v:
  ; fall into SET_VX

; X = slot: horizontal speed of its kind (+ difficulty), towards O_D
SET_VX:
  LDY O_K,X
  LDA DIFF
  ASL A
  ASL A
  CLC
  ADC SPD_L,Y
  STA O_VXL,X
  LDA SPD_H,Y
  ADC #0
  STA O_VX,X
  LDA O_D,X
  BEQ .sv_r
  SEC
  LDA #0
  SBC O_VXL,X
  STA O_VXL,X
  LDA #0
  SBC O_VX,X
  STA O_VX,X
.sv_r:
  RTS

; ===============================================================
;  THE COMMANDO (slot 0)
; ===============================================================
UPDATE_HERO:
  LDA LADDER
  BEQ .uh_nl
  JMP HERO_LADDER
.uh_nl:
  LDA STAB
  BEQ .uh_s
  DEC STAB
.uh_s:
  LDA FIREC
  BEQ .uh_f
  DEC FIREC
.uh_f:
  STZ KNEEL
  LDA JOYP                     ; T7 = buttons just pressed
  EOR #$FF
  AND JOYC
  STA T7
  LDA O_AIR
  BEQ .uh_g
  JMP HERO_AIR
.uh_g:
  LDA T7                       ; button 1: plant a charge on a target, or the knife
  AND #$10
  BEQ .uh_b2
  JSR TRY_PLANT
  BCS .uh_b2
  LDA STAB
  BNE .uh_b2
  JSR START_STAB
.uh_b2:
  LDA T7                       ; button 2: the special weapon
  AND #$20
  BEQ .uh_d
  JSR FIRE_WEAPON
.uh_d:
  LDA JOYC                     ; down: a ladder below, or kneel
  AND #2
  BEQ .uh_u
  LDY HFL
  BEQ .uh_kn
  LDA O_X
  JSR FLAGS_X
  LDY HFL
  AND LAD_DN,Y
  BEQ .uh_kn
  LDA HFL
  DEC A
  STA LADB
  JSR SNAP_LADDER
  INC O_Y
  BRA .uh_lad
.uh_kn:
  LDA #1
  STA KNEEL
  JMP HAZARDS
.uh_u:
  LDA JOYC                     ; up: a ladder above, or jump
  AND #1
  BEQ .uh_w
  LDY HFL
  LDA O_X
  JSR FLAGS_X
  LDY HFL
  AND LAD_UP,Y
  BEQ .uh_jump
  LDA HFL
  STA LADB
  JSR SNAP_LADDER
  DEC O_Y
.uh_lad:
  LDA #1
  STA LADDER
  LDA #$FF
  STA HFL
  STZ STAB
  RTS
.uh_jump:
  LDA #1
  STA O_AIR
  LDA #$FC                     ; -3.44 pixels per frame
  STA O_VY
  LDA #$90
  STA O_VYL
  LDA #$FF
  STA HFL
  BRA .uh_mv
.uh_w:
  LDA STAB                     ; no steps while the knife is out
  BNE HAZARDS
.uh_mv:
  JSR HERO_WALK
  LDA O_AIR
  BNE .uh_r
  LDY HFL                      ; walked off the end of a walkway
  BEQ HAZARDS
  LDA O_X
  JSR FLAGS_X
  LDY HFL
  AND FMASK,Y
  BNE HAZARDS
  LDA #1
  STA O_AIR
  STZ O_VY
  STZ O_VYL
  LDA #$FF
  STA HFL
.uh_r:
  RTS

; on the ground: barbed wire and mines
HAZARDS:
  LDA HFL
  BNE .hz_r
  LDA O_X
  JSR FLAGS_X
  AND #(16 | 32)
  BEQ .hz_r
  AND #32
  BEQ .hz_d
  JSR FREE_SLOT                ; a mine: an explosion under the feet
  BCS .hz_d
  LDA O_X
  STA CX
  STZ FL
  LDA #K_BOOM
  JSR NEW_OBJ
  LDA #24
  STA O_T,X
  LDA #S_BOOM
  LDX #2
  JSR SFX_BOOM
.hz_d:
  JMP HERO_DIE
.hz_r:
  RTS

; left / right: a step of 1 pixel (also in the air)
HERO_WALK:
  LDA JOYC
  AND #4
  BEQ .hw_r
  LDA #1
  STA O_D
  LDA O_X
  CMP #9
  BCC .hw_a
  DEC O_X
  BRA .hw_a
.hw_r:
  LDA JOYC
  AND #8
  BEQ .hw_n
  STZ O_D
  LDA O_X
  CMP #244
  BCS .hw_a
  INC O_X
.hw_a:
  INC O_A
  RTS
.hw_n:
  STZ O_A
  RTS

HERO_AIR:
  LDA T7
  AND #$10
  BEQ .ha_2
  LDA STAB
  BNE .ha_2
  JSR START_STAB
.ha_2:
  LDA T7
  AND #$20
  BEQ .ha_m
  JSR FIRE_WEAPON
.ha_m:
  JSR HERO_WALK
  LDX #0
  JSR BODY_AIR
  BCC .ha_r
  LDA O_FL                     ; landed
  STA HFL
  JMP HAZARDS
.ha_r:
  RTS

START_STAB:
  LDA #STAB_T
  STA STAB
  LDA #W_KNIFE
  LDX #2
  JMP SFX_WHISTLE

; on a ladder: up and down only, off at the floor above or below
HERO_LADDER:
  LDA JOYC
  AND #1
  BEQ .hl_d
  DEC O_Y
  INC O_A
  LDY LADB
  LDA FLOOR_Y+1,Y
  CMP O_Y
  BNE .hl_r
  INY
  STY HFL
  STZ LADDER
  RTS
.hl_d:
  LDA JOYC
  AND #2
  BEQ .hl_r
  INC O_Y
  INC O_A
  LDY LADB
  LDA FLOOR_Y,Y
  CMP O_Y
  BNE .hl_r
  STY HFL
  STZ LADDER
.hl_r:
  RTS

; the commando in the middle of the ladder (ladders start at even columns)
SNAP_LADDER:
  LDA O_X
  LSR A
  LSR A
  LSR A
  CLC
  ADC WX
  AND #$FE
  SEC
  SBC WX
  ASL A
  ASL A
  ASL A
  CLC
  ADC #8
  STA O_X
  RTS

; button 2: machine gun, mortar or timed charge
FIRE_WEAPON:
  LDA WEAP
  BEQ .fw_x
  LDA FIREC
  BNE .fw_x
  JSR FREE_SLOT
  BCC .fw_go
.fw_x:
  RTS
.fw_go:
  LDA O_X
  STA CX
  STZ FL
  LDA WEAP
  CMP #2
  BEQ .fw_m
  BCS .fw_c
  LDA #K_HSHOT                 ; machine gun: a fast shot at chest height
  JSR NEW_OBJ
  LDA O_Y
  SEC
  SBC #10
  LDY KNEEL
  BEQ .fw_k
  CLC
  ADC #5
.fw_k:
  STA O_Y,X
  LDA O_D
  STA O_D,X
  TAY
  LDA SHOT_VX,Y
  STA O_VX,X
  LDA #8
  STA FIREC
  LDA #S_GUN
  LDX #2
  JSR SFX_BOOM
  BRA .fw_use
.fw_m:
  LDA #K_SHELL                 ; mortar: a shell on a curve
  JSR NEW_OBJ
  LDA O_Y
  SEC
  SBC #12
  STA O_Y,X
  LDA #1
  STA O_AIR,X
  LDA #$FD
  STA O_VY,X
  LDA O_D
  STA O_D,X
  TAY
  LDA SHELL_VX,Y
  STA O_VX,X
  LDA #24
  STA FIREC
  LDA #W_MORT
  LDX #2
  JSR SFX_WHISTLE
  BRA .fw_use
.fw_c:
  LDA HFL                      ; timed charge: only standing on a floor
  CMP #$FF
  BNE .fw_cf
  RTS
.fw_cf:
  STA FL
  LDA #K_CHARGE
  JSR NEW_OBJ
  LDA #100
  STA O_T,X
  LDA #30
  STA FIREC
  LDA #W_PLANT
  LDX #2
  JSR SFX_WHISTLE
.fw_use:
  DEC AMMO
  BNE .fw_h
  STZ WEAP
.fw_h:
  LDA #1
  STA HUDD
.fw_r:
  RTS

; button 1 in front of a target of this floor: the charge goes on it (C set)
TRY_PLANT:
  LDA HFL
  CMP #$FF
  BEQ .tp_x
  LDA O_X
  JSR FLAGS_X
  AND #64
  BNE .tp_go
.tp_x:
  CLC
  RTS
.tp_go:
  LDA SECTOR
  ASL A
  ASL A
  STA T6
  LDX #0
.tp_l:
  CPX TGTN
  BCC .tp_c
  JMP .tp_no
.tp_c:
  LDA BITS,X
  AND TGTD
  BNE .tp_n
  TXA
  CLC
  ADC T6
  TAY
  LDA TG_F,Y
  CMP HFL
  BNE .tp_n
  LDA TG_C,Y                   ; middle of the target on the screen
  SEC
  SBC WX
  BCC .tp_n
  CMP #31
  BCS .tp_n
  ASL A
  ASL A
  ASL A
  CLC
  ADC #8
  STA CX
  LDA O_X
  STA DXA
  LDA CX
  JSR ADIFF
  CMP #10
  BCS .tp_n
  LDA BITS,X
  ORA TGTD
  STA TGTD
  JSR FREE_SLOT
  BCS .tp_s
  LDA HFL
  STA FL
  LDA #K_CHARGE
  JSR NEW_OBJ
  LDA #1
  STA O_S,X
  LDA O_Y,X
  SEC
  SBC #2
  STA O_Y,X
.tp_s:
  LDA #W_PLANT
  LDX #2
  JSR SFX_WHISTLE
  LDA #$00                     ; 500 points
  LDY #$05
  JSR ADD_PTS
  LDX TGTN
  LDA FULLM,X
  CMP TGTD
  BNE .tp_y
  LDA #2                       ; all the charges: the countdown
  STA GSTATE
  LDA #180
  STA GT
  LDA #W_ALARM
  LDX #2
  JSR SFX_WHISTLE
.tp_y:
  SEC
  RTS
.tp_n:
  INX
  JMP .tp_l
.tp_no:
  CLC
  RTS

HERO_DIE:
  LDA GSTATE
  CMP #1
  BEQ .hd_r
  CMP #3
  BEQ .hd_r
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  STZ LADDER
  STZ STAB
  LDA #W_DIE
  LDX #2
  JSR SFX_WHISTLE
.hd_r:
  RTS


; ===============================================================
;  BODIES: falling and landing on the floors
; ===============================================================
; X = slot in the air: gravity, then it lands on the first floor crossed
; going down that is there at its x (C set = landed, O_FL = floor)
BODY_AIR:
  CLC
  LDA O_VYL,X
  ADC #GRAV
  STA O_VYL,X
  LDA O_VY,X
  ADC #0
  STA O_VY,X
  BMI .ba_y
  CMP #4                       ; at most 4 pixels per frame
  BCC .ba_y
  LDA #4
  STA O_VY,X
  STZ O_VYL,X
.ba_y:
  LDA O_Y,X
  STA CY
  CLC
  LDA O_YL,X
  ADC O_VYL,X
  STA O_YL,X
  LDA O_Y,X
  ADC O_VY,X
  STA O_Y,X
  LDA O_VY,X
  BMI .ba_no
  LDY #2
.ba_f:
  LDA FLOOR_Y,Y
  CMP CY
  BCC .ba_n                    ; already under this floor
  LDA O_Y,X
  CMP FLOOR_Y,Y
  BCC .ba_n                    ; not there yet
  CPY #0
  BEQ .ba_land
  PHY
  LDA O_X,X
  JSR FLAGS_X
  PLY
  AND FMASK,Y
  BEQ .ba_n
.ba_land:
  LDA FLOOR_Y,Y
  STA O_Y,X
  STZ O_YL,X
  STZ O_VY,X
  STZ O_VYL,X
  STZ O_AIR,X
  TYA
  STA O_FL,X
  SEC
  RTS
.ba_n:
  DEY
  BPL .ba_f
.ba_no:
  CLC
  RTS

; X = slot: x += vx (C set = past an edge of the screen)
MOVE_X:
  CLC
  LDA O_XL,X
  ADC O_VXL,X
  STA O_XL,X
  LDA O_X,X
  ADC O_VX,X
  STA O_X,X
  CMP #4
  BCC .mx_o
  CMP #252
  BCS .mx_r
  CLC
  RTS
.mx_o:
  SEC
.mx_r:
  RTS

; X = slot: a step, gone past the edges, falling off the end of a walkway
WALK_BODY:
  INC O_A,X
  JSR MOVE_X
  BCS .wb_gone
  LDA O_AIR,X
  BNE .wb_air
  LDY O_FL,X
  BEQ .wb_r
  LDA O_X,X
  JSR FLAGS_X
  LDY O_FL,X
  AND FMASK,Y
  BNE .wb_r
  LDA #1
  STA O_AIR,X
  STZ O_VY,X
  STZ O_VYL,X
  RTS
.wb_air:
  JMP BODY_AIR
.wb_gone:
  STZ O_K,X
.wb_r:
  RTS

; X = slot: turn towards the commando if he stands on the same floor
FACE_HERO:
  LDA O_AIR,X
  BNE .fh_r
  LDA HFL
  CMP O_FL,X
  BNE .fh_r
  LDA O_X
  CMP O_X,X
  LDA #0
  BCS .fh_s
  LDA #1
.fh_s:
  CMP O_D,X
  BEQ .fh_r
  STA O_D,X
  JMP SET_VX
.fh_r:
  RTS

; A = |A - DXA|
ADIFF:
  SEC
  SBC DXA
  BCS .ad_r
  EOR #$FF
  INC A
.ad_r:
  RTS


; ===============================================================
;  OBJECTS 1-13
; ===============================================================
UPDATE_OBJS:
  STZ NEN
  LDX #1
.uo_l:
  STX SLOT
  LDA O_K,X
  BEQ .uo_n
  CMP #K_BULLET
  BCS .uo_k
  INC NEN                      ; soldiers, nests and barrels on the screen
.uo_k:
  ASL A
  TAY
  LDA OBJ_JT,Y
  STA PTR
  LDA OBJ_JT+1,Y
  STA PTR+1
  JSR .uo_go
  LDX SLOT
.uo_n:
  INX
  CPX #NOB
  BNE .uo_l
  RTS
.uo_go:
  JMP (PTR)

OB_NONE:
  RTS

; sentry and shield man: towards the commando on his floor, straight on otherwise
OB_SENT:
  JSR FACE_HERO
  JMP WALK_BODY

; rifleman: comes closer, kneels and shoots along the floor
OB_RIFLE:
  LDA O_S,X
  BNE .or_aim
  LDA O_T,X
  BEQ .or_c
  DEC O_T,X
.or_c:
  JSR FACE_HERO
  LDA O_T,X
  BNE .or_w
  LDA O_AIR,X
  BNE .or_w
  LDA HFL
  CMP O_FL,X
  BNE .or_w
  LDA O_X
  STA DXA
  LDA O_X,X
  JSR ADIFF
  CMP #88
  BCS .or_w
  LDA #1
  STA O_S,X
  LDA #44
  STA O_T,X
  RTS
.or_w:
  JMP WALK_BODY
.or_aim:
  DEC O_T,X
  LDA O_T,X
  CMP #22
  BNE .or_t
  JMP ENEMY_FIRE
.or_t:
  CMP #0
  BNE .or_r
  STZ O_S,X
  LDA #90
  STA O_T,X
.or_r:
  RTS

; sapper: jumps up to the floor of the commando when he is close above
OB_SAPPER:
  LDA O_T,X
  BEQ .os_c
  DEC O_T,X
.os_c:
  JSR FACE_HERO
  LDA O_AIR,X
  BNE .os_w
  LDA O_T,X
  BNE .os_w
  LDA HFL
  CMP #$FF
  BEQ .os_w
  CMP O_FL,X
  BEQ .os_w
  BCC .os_w
  LDA O_X
  STA DXA
  LDA O_X,X
  JSR ADIFF
  CMP #56
  BCS .os_w
  LDY O_FL,X                   ; the walkway above is there
  INY
  PHY
  LDA O_X,X
  JSR FLAGS_X
  PLY
  AND FMASK,Y
  BEQ .os_w
  LDA #1
  STA O_AIR,X
  LDA #$FA                     ; -5.4 pixels per frame: up 60 pixels
  STA O_VY,X
  LDA #$A0
  STA O_VYL,X
  LDA #90
  STA O_T,X
.os_w:
  JMP WALK_BODY

; machine-gun nest: turns to the commando and shoots when he is on its floor
OB_NEST:
  LDA O_X
  CMP O_X,X
  LDA #0
  BCS .on_d
  LDA #1
.on_d:
  STA O_D,X
  DEC O_T,X
  BNE .on_r
  LDA DIFF
  ASL A
  ASL A
  STA T0
  LDA #100
  SEC
  SBC T0
  STA O_T,X
  LDA HFL
  CMP O_FL,X
  BNE .on_r
  JMP ENEMY_FIRE
.on_r:
  RTS

; X = shooter: a bullet from its chest along O_D
ENEMY_FIRE:
  LDY O_D,X
  LDA O_X,X
  CLC
  ADC FIRE_DX,Y
  STA CX
  LDA O_Y,X
  SEC
  SBC #10
  STA CY
  LDA O_D,X
  STA T5
  PHX
  JSR FREE_SLOT
  BCS .ef_n
  STZ FL
  LDA #K_BULLET
  JSR NEW_OBJ
  LDA CY
  STA O_Y,X
  LDY T5
  TYA
  STA O_D,X
  LDA BUL_VX,Y
  STA O_VX,X
  LDA #$80
  STA O_VXL,X
  LDA #S_SHOT
  LDY CX
  JSR BOOM_AT
.ef_n:
  PLX
  RTS

OB_BULLET:
  JSR MOVE_X
  BCC .ob_r
  STZ O_K,X
.ob_r:
  RTS

; the shot of the machine gun: the first soldier it meets
OB_HSHOT:
  JSR MOVE_X
  BCS .oh_g
  LDA O_X,X
  STA CX
  LDA O_Y,X
  STA CY
  LDY #1
.oh_l:
  LDA O_K,Y
  CMP #K_SENT
  BCC .oh_n
  CMP #K_BULLET
  BCS .oh_n
  LDA O_X,Y
  STA DXA
  LDA CX
  JSR ADIFF
  CMP #8
  BCS .oh_n
  LDA O_Y,Y
  SEC
  SBC #8
  STA DXA
  LDA CY
  JSR ADIFF
  CMP #10
  BCS .oh_n
  STZ O_K,X
  LDA #3
  JMP DAMAGE
.oh_n:
  INY
  CPY #NOB
  BNE .oh_l
  RTS
.oh_g:
  STZ O_K,X
  RTS

; the mortar shell: explodes on a floor or on a soldier
OB_SHELL:
  JSR MOVE_X
  BCS .sh_g
  JSR BODY_AIR
  BCS .sh_x
  LDA O_X,X
  STA CX
  LDA O_Y,X
  STA CY
  LDY #1
.sh_l:
  LDA O_K,Y
  CMP #K_SENT
  BCC .sh_n
  CMP #K_BULLET
  BCS .sh_n
  LDA O_X,Y
  STA DXA
  LDA CX
  JSR ADIFF
  CMP #10
  BCS .sh_n
  LDA O_Y,Y
  SEC
  SBC #8
  STA DXA
  LDA CY
  JSR ADIFF
  CMP #12
  BCC .sh_x
.sh_n:
  INY
  CPY #NOB
  BNE .sh_l
  RTS
.sh_x:
  JMP EXPLODE
.sh_g:
  STZ O_K,X
  RTS

; timed charge: ticks, then clears the soldiers of its floor; on a target it waits
OB_CHARGE:
  LDA O_S,X
  BNE .oc_r
  DEC O_T,X
  BEQ .oc_go
  LDA O_T,X
  AND #15
  BNE .oc_r
  LDA #W_TICK
  LDX #2
  JSR SFX_WHISTLE
  LDX SLOT
.oc_r:
  RTS
.oc_go:
  LDA O_Y,X
  STA CY
  LDY #1
.oc_l:
  LDA O_K,Y
  CMP #K_SENT
  BCC .oc_n
  CMP #K_BULLET
  BCS .oc_n
  LDA O_Y,Y
  STA DXA
  LDA CY
  JSR ADIFF
  CMP #6
  BCS .oc_n
  JSR KILL
.oc_n:
  INY
  CPY #NOB
  BNE .oc_l
  LDA #K_BOOM
  STA O_K,X
  LDA #24
  STA O_T,X
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
  LDX SLOT
  RTS

OB_BOOM:
  DEC O_T,X
  BNE .bo_r
  STZ O_K,X
.bo_r:
  RTS

; a weapon left by a courier: goes away after a while
OB_PICK:
  LDA O_AIR,X
  BEQ .pk_t
  JSR BODY_AIR
.pk_t:
  LDA GF
  AND #1
  BEQ .pk_r
  DEC O_T,X
  BNE .pk_r
  STZ O_K,X
.pk_r:
  RTS

OB_DEAD:
  LDA O_AIR,X
  BEQ .dd_t
  JSR BODY_AIR
.dd_t:
  DEC O_T,X
  BNE .dd_r
  STZ O_K,X
.dd_r:
  RTS

; X = slot: becomes an explosion that takes the soldiers around it
EXPLODE:
  LDA #K_BOOM
  STA O_K,X
  LDA #20
  STA O_T,X
  STZ O_AIR,X
  LDA O_X,X
  STA CX
  LDA O_Y,X
  STA CY
  PHX
  LDA #S_BOOM
  LDY CX
  JSR BOOM_AT
  PLX
  LDY #1
.ex_l:
  LDA O_K,Y
  CMP #K_SENT
  BCC .ex_n
  CMP #K_BULLET
  BCS .ex_n
  LDA O_X,Y
  STA DXA
  LDA CX
  JSR ADIFF
  CMP #24
  BCS .ex_n
  LDA O_Y,Y
  STA DXA
  LDA CY
  JSR ADIFF
  CMP #24
  BCS .ex_n
  JSR KILL
.ex_n:
  INY
  CPY #NOB
  BNE .ex_l
  RTS

; Y = victim, A = damage: nests take 3 hits (keeps X and Y)
DAMAGE:
  STA T5
  LDA O_K,Y
  CMP #K_NEST
  BNE KILL
  LDA O_H,Y
  SEC
  SBC T5
  STA O_H,Y
  BEQ KILL
  BMI KILL
  PHX
  PHY
  LDA #W_CLANK
  LDX #2
  JSR SFX_WHISTLE
  PLY
  PLX
  RTS

; Y = victim: points, then a body, a pickup (courier) or an explosion (keeps X and Y)
KILL:
  PHX
  LDX O_K,Y
  LDA KPTS_L,X
  STA PTS_L
  LDA KPTS_M,X
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  LDA #0
  STA O_VX,Y
  STA O_VXL,Y
  LDA O_K,Y
  CMP #K_COUR
  BEQ .k_pick
  CMP #K_NEST
  BEQ .k_boom
  CMP #K_BARREL
  BEQ .k_boom
  LDA #K_DEAD
  STA O_K,Y
  LDA #30
  STA O_T,Y
  LDA #S_HIT
  BRA .k_snd
.k_pick:
  LDA #K_PICK
  STA O_K,Y
  LDA #250
  STA O_T,Y
  JSR NEXT_RND                 ; machine gun, mortar or charge
  AND #3
  BNE .k_w
  LDA #1
.k_w:
  STA O_H,Y
  LDA #S_HIT
  BRA .k_snd
.k_boom:
  LDA #K_BOOM
  STA O_K,Y
  LDA #20
  STA O_T,Y
  LDA #0
  STA O_AIR,Y
  LDA #S_BOOM
.k_snd:
  PHY
  PHA
  LDA O_X,Y
  TAY
  PLA
  JSR BOOM_AT
  PLY
  PLX
  RTS


; ===============================================================
;  THE COMMANDO AGAINST THE REST: knife, touches, bullets, pickups
; ===============================================================
HERO_CHECKS:
  LDA O_X
  STA HX
  LDA O_Y
  STA HY
  LDA STAB                     ; the knife hits in frames 10-4 of the thrust
  CMP #11
  BCS .hc_t
  CMP #4
  BCC .hc_t
  LDY O_D
  LDA HX
  CLC
  ADC STAB_DX,Y
  STA CX
  LDY #1
.hk_l:
  LDA O_K,Y
  CMP #K_SENT
  BCC .hk_n
  CMP #K_BARREL
  BCS .hk_n
  LDA O_X,Y
  STA DXA
  LDA CX
  JSR ADIFF
  CMP #13
  BCS .hk_n
  LDA O_Y,Y
  STA DXA
  LDA HY
  JSR ADIFF
  CMP #12
  BCS .hk_n
  LDA O_K,Y                    ; shield man: only from above or from behind
  CMP #K_SHIELD
  BNE .hk_hit
  LDA O_AIR
  BNE .hk_hit
  LDA O_D,Y
  CMP O_D
  BEQ .hk_hit
  STZ STAB
  LDA #W_CLANK
  LDX #2
  JSR SFX_WHISTLE
  BRA .hc_t
.hk_hit:
  LDA #1
  JSR DAMAGE
  LDA #3                       ; one victim per thrust
  STA STAB
  BRA .hc_t
.hk_n:
  INY
  CPY #NOB
  BNE .hk_l
.hc_t:
  LDY #1
.ht_l:
  LDA O_K,Y
  CMP #K_SENT
  BCC .ht_n
  STA TMPK
  LDA O_X,Y
  STA DXA
  LDA HX
  JSR ADIFF
  STA T4
  LDA TMPK
  CMP #K_BULLET
  BCC .ht_body
  BEQ .ht_bul
  CMP #K_PICK
  BEQ .ht_pick
.ht_n:
  INY
  CPY #NOB
  BNE .ht_l
  RTS
.ht_body:
  LDA T4
  CMP #10
  BCS .ht_n
  LDA O_Y,Y
  STA DXA
  LDA HY
  JSR ADIFF
  CMP #12
  BCS .ht_n
  JMP HERO_DIE
.ht_bul:
  LDA T4                       ; a bullet between the head and the feet
  CMP #6
  BCS .ht_n
  LDA HY
  SEC
  SBC #15
  LDX KNEEL
  BEQ .ht_k
  CLC
  ADC #8
.ht_k:
  STA T5
  LDA O_Y,Y
  CMP T5
  BCC .ht_n
  CMP HY
  BCS .ht_n
  LDA #0
  STA O_K,Y
  JMP HERO_DIE
.ht_pick:
  LDA T4
  CMP #12
  BCS .ht_n
  LDA O_Y,Y
  STA DXA
  LDA HY
  JSR ADIFF
  CMP #14
  BCS .ht_n
  LDA O_H,Y
  STA WEAP
  TAX
  LDA AMMO_T,X
  STA AMMO
  LDA #0
  STA O_K,Y
  LDA #1
  STA HUDD
  LDA #W_PICK
  LDX #2
  JSR SFX_WHISTLE
  BRA .ht_n


; ===============================================================
;  SPRITES: the commando first, the rest in turns (flicker past 4 per line)
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA O_K
  BEQ .bs_o
  LDA O_X
  STA OX
  LDA O_Y
  STA OY
  JSR HERO_PAT
  STA ON
  LDA #$03
  STA OC
  JSR ADD_SPR
.bs_o:
  LDA #NOB-1
  STA CNT
  LDX RR
.bs_l:
  STX SLOT
  LDA O_K,X
  BEQ .bs_n
  JSR OBJ_SPR
  BCS .bs_n
  JSR ADD_SPR
.bs_n:
  LDX SLOT
  INX
  CPX #NOB
  BCC .bs_w
  LDX #1
.bs_w:
  DEC CNT
  BNE .bs_l
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  INC RR
  LDA RR
  CMP #NOB
  BCC .bs_r
  LDA #1
  STA RR
.bs_r:
  RTS

HERO_PAT:
  LDA GSTATE
  CMP #1
  BNE .hp_a
  LDA #PT_HDEAD
  RTS
.hp_a:
  LDA LADDER
  BEQ .hp_b
  LDA O_Y
  AND #4
  CLC
  ADC #PT_CLIMB
  RTS
.hp_b:
  LDA O_D
  ASL A
  ASL A
  STA T0
  LDA O_AIR
  BEQ .hp_g
  LDA #PT_JUMP
  LDY STAB
  BEQ .hp_f
  LDA #PT_JSTAB
  BRA .hp_f
.hp_g:
  LDA KNEEL
  BEQ .hp_s
  LDA #PT_KNEEL
  LDY STAB
  BEQ .hp_f
  LDA #PT_KNEEL+8
  BRA .hp_f
.hp_s:
  LDA #PT_STAB
  LDY STAB
  BNE .hp_f
  LDA O_A
  AND #8
  CLC
  ADC #PT_RUN
.hp_f:
  CLC
  ADC T0
  RTS

; X = slot: OX, OY, ON, OC of its sprite (C set = not shown this frame)
OBJ_SPR:
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
  LDA SECTOR
  ASL A
  ASL A
  ASL A
  ASL A
  ORA O_K,X
  TAY
  LDA KCOL,Y
  STA OC
  LDA O_D,X
  ASL A
  ASL A
  STA T0
  LDA O_A,X
  AND #8
  STA T1
  LDA O_K,X
  CMP #K_RIFLE
  BNE .os_1
  LDA O_S,X
  BNE .os_1a
  JMP .os_sol
.os_1a:
  LDA #PT_AIM
  JMP .os_f
.os_1:
  CMP #K_SHIELD
  BNE .os_2
  LDA #PT_SHD
  JMP .os_st
.os_2:
  CMP #K_COUR
  BNE .os_3
  LDA GF
  AND #4
  BEQ .os_2c
  LDA #$0F
  STA OC
.os_2c:
  LDA #PT_COU
  JMP .os_st
.os_3:
  CMP #K_NEST
  BNE .os_4
  LDA #PT_NEST
  JMP .os_f
.os_4:
  CMP #K_BARREL
  BNE .os_5
  LDA O_A,X
  AND #4
  CLC
  ADC #PT_BARREL
  JMP .os_k
.os_5:
  CMP #K_BULLET
  BEQ .os_bul
  CMP #K_HSHOT
  BNE .os_6
.os_bul:
  LDA OY
  CLC
  ADC #9
  STA OY
  LDA #PT_BULLET
  JMP .os_k
.os_6:
  CMP #K_SHELL
  BNE .os_7
  LDA OY
  CLC
  ADC #8
  STA OY
  LDA #PT_SHELL
  JMP .os_k
.os_7:
  CMP #K_CHARGE
  BNE .os_8
  LDA GF
  AND #8
  BEQ .os_7c
  LDA #$0F
  STA OC
.os_7c:
  INC OY
  LDA #PT_CHARGE
  JMP .os_k
.os_8:
  CMP #K_BOOM
  BNE .os_9
  LDA GF
  AND #2
  BEQ .os_8c
  LDA #$09
  STA OC
.os_8c:
  LDA GF
  AND #4
  CLC
  ADC #PT_BOOM
  JMP .os_k
.os_9:
  CMP #K_PICK
  BNE .os_10
  LDA O_T,X                    ; blinks before going away
  CMP #60
  BCS .os_9s
  LDA GF
  AND #4
  BEQ .os_9s
  SEC
  RTS
.os_9s:
  INC OY
  INC OY
  LDA O_H,X
  DEC A
  ASL A
  ASL A
  CLC
  ADC #PT_PICK
  JMP .os_k
.os_10:
  CMP #K_DEAD
  BNE .os_sol
  LDA #PT_EDEAD
  JMP .os_f
.os_sol:
  LDA #PT_SOL
.os_st:
  CLC
  ADC T1
.os_f:
  CLC
  ADC T0
.os_k:
  STA ON
  CLC
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

; the tiles of the camp in the colours of the sector (XLAT built by SET_SECTOR)
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

; as VCOPY, every byte through XLAT (material colours -> colours of the sector)
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

; the name table HOFF to spaces (black)
CLEAR_NT:
  LDA #$00
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  CLC
  ADC HOFF
  STA T1
  LDA #$00
  STA T2
  LDA #$03
  STA T3
  LDA #$20
  JMP VFILL

; X = row, Y = column: VDP address of the cell in the name table HOFF (0: $3800, 4: $3C00)
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
; a 16x16 sprite with the feet at (OX, OY): x = OX - 8, last line = OY - 1; pattern ON, colour OC
ADD_SPR:
  LDX SPRI
  CPX #128
  BCS .as_r
  LDA OY
  SEC
  SBC #17
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
;  SOUND: the tunes (4 tracks, from tank) and the effects
;  per chip in game: A = tone effects, B = noise and C = low tone
;  of the explosions; sounds go to the side of the screen they come from
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
FLOOR_Y:    .byte 168,120,72                   ; feet on the ground, floor 1, floor 2
FMASK:      .byte 0,1,2                        ; flag of the walkway of a floor (0: the ground is everywhere)
LAD_UP:     .byte 4,8,0                        ; flag of the ladder going up from a floor
LAD_DN:     .byte 0,4,8                        ; flag of the ladder going down from a floor
BITS:       .byte 1,2,4,8
FULLM:      .byte 0,1,3,7,15                   ; all the targets planted
AMMO_T:     .byte 0,8,2,1                      ; shots of machine gun, mortar, charge
SHOT_VX:    .byte 4,$FC                        ; right / left
SHELL_VX:   .byte 2,$FE
FIRE_DX:    .byte 10,$F6
BUL_VX:     .byte $02,$FD                      ; with the fraction $80: +2.5 / -2.5
STAB_DX:    .byte 8,$F8

; per kind: speed (8.8, + difficulty x 4 / 256), points (BCD)
;                 -  hero sent rifl sapp shld nest cour barr bull hsht shel chrg boom pick dead
SPD_L:      .byte 0, 0,  $C0, $A0, $D0, $60, 0,   $40, $20, 0,   0,   0,   0,   0,   0,   0
SPD_H:      .byte 0, 0,  0,   0,   0,   0,   0,   1,   1,   0,   0,   0,   0,   0,   0,   0
KPTS_L:     .byte 0, 0,  $00, $00, $50, $00, $00, $00, $00, 0,   0,   0,   0,   0,   0,   0
KPTS_M:     .byte 0, 0,  $01, $02, $01, $05, $08, $03, $01, 0,   0,   0,   0,   0,   0,   0
; sprite colour per sector and kind
KCOL:       .byte 0, 3,  6,   1,   13,  15,  1,   11,  6,   15,  11,  1,   8,   11,  11,  6
            .byte 0, 3,  4,   1,   13,  15,  1,   11,  6,   15,  11,  1,   8,   11,  11,  4
            .byte 0, 3,  4,   1,   12,  14,  1,   11,  6,   1,   4,   1,   8,   11,  11,  4
            .byte 0, 3,  11,  9,   13,  15,  10,  7,   6,   15,  11,  15,  8,   11,  11,  9
OBJ_JT:     .word OB_NONE, OB_NONE, OB_SENT, OB_RIFLE, OB_SAPPER, OB_SENT, OB_NEST, WALK_BODY
            .word WALK_BODY, OB_BULLET, OB_HSHOT, OB_SHELL, OB_CHARGE, OB_BOOM, OB_PICK, OB_DEAD

; soldiers from the edges: frames between two (+ random 0-63) by difficulty, kinds per sector
STRM_T:     .byte 150,140,130,120,110,100,92,86,80,74,68,62
STREAM_K:   .byte 2,2,3,2,3,2,7,2
            .byte 2,4,3,5,2,4,7,3
            .byte 8,2,3,8,4,5,7,8
            .byte 3,4,5,2,3,4,5,7

; title: commando, sentry, rifleman, sapper, shield man, courier  (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 9*8-5,11*8-5,13*8-5,15*8-5,17*8-5,19*8-5
TITLE_SX:   .byte 32,32,32,32,32,32
TITLE_SN:   .byte PT_RUN,PT_SOL+4,PT_AIM+4,PT_SOL+4,PT_SHD+4,PT_COU+4
TITLE_SC:   .byte $03,$09,$0A,$0D,$0F,$0B

SNAME_LO:   .byte <TXT_S0,<TXT_S1,<TXT_S2,<TXT_S3
SNAME_HI:   .byte >TXT_S0,>TXT_S1,>TXT_S2,>TXT_S3
SHINT_LO:   .byte <TXT_H0,<TXT_H1,<TXT_H2,<TXT_H3
SHINT_HI:   .byte >TXT_H0,>TXT_H1,>TXT_H2,>TXT_H3

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 9,7,"COMMANDO   B1 = KNIFE",0
  .byte 11,7,"SENTRY         100",0
  .byte 13,7,"RIFLEMAN       200",0
  .byte 15,7,"SAPPER         150",0
  .byte 17,7,"SHIELD MAN     500",0
  .byte 19,7,"COURIER   B2 = WEAPON",0
  .byte 21,3,"B1 ON A TARGET = CHARGE",0
  .byte 23,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_PLAYER:
  .byte 7,12,"PLAYER ",0
  .byte $FF
TXT_SECTOR:
  .byte 13,12,"SECTOR ",0
  .byte $FF
TXT_H0:
  .byte 17,3,"JUMP OVER THE BARBED WIRE",0
  .byte 19,2,"3 CHARGES ON THE RADIO TOWER",0
  .byte $FF
TXT_H1:
  .byte 17,1,"MIND THE GAPS IN THE WALKWAYS",0
  .byte 19,4,"BLOW UP THE ARMORY DOOR",0
  .byte $FF
TXT_H2:
  .byte 17,3,"MINES AND ROLLING BARRELS",0
  .byte 19,3,"3 CHARGES ON THE BIG TANK",0
  .byte $FF
TXT_H3:
  .byte 17,4,"THE LAST POST  GOOD LUCK",0
  .byte 19,3,"4 CHARGES ON THE CONSOLES",0
  .byte $FF
TXT_TIME:
  .byte "TIME ",0
TXT_CLEAR:
  .byte 9,6,"OBJECTIVE DESTROYED",0
  .byte $FF
TXT_BONUS:
  .byte 12,10,"BONUS ",0
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
SONGP_LO:      .byte <M0_LEAD,<M0_HARM,<M0_BASS,<M0_DRUM, <M1_LEAD,<M1_HARM,<M1_BASS,<M1_DRUM
SONGP_HI:      .byte >M0_LEAD,>M0_HARM,>M0_BASS,>M0_DRUM, >M1_LEAD,>M1_HARM,>M1_BASS,>M1_DRUM

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

; two tunes composed for this game
;   F2 6 G2 8 A2 10 Bb2 11 C3 13 D3 15 E3 17 F3 18 G3 20 A3 22
;   C4 25 D4 27 F4 30 G4 32 A4 34 C5 37 D5 39 E5 41 F5 42 G5 44 A5 46 Bb5 47 C6 49 D6 51
; sector: D minor, a driving tune over a syncopated bass (about 4.7 seconds)
M0_LEAD:
  .byte 39,8, 42,8, 46,16, 44,8, 42,8, 41,8, 39,8
  .byte 37,8, 39,8, 41,8, 42,16, 41,8, 37,8, 39,24, 0,8
  .byte 46,8, 47,8, 46,8, 44,8, 42,8, 44,8, 46,16, 49,16, 46,16, 39,32
  .byte $FF
M0_HARM:
  .byte 27,64, 25,64, 30,64, 32,32, 27,56
  .byte $FF
M0_BASS:
  .byte 15,12, 15,4, 22,8, 15,8, 13,12, 13,4, 15,16
  .byte 13,12, 13,4, 20,8, 13,8, 11,12, 11,4, 13,16
  .byte 11,12, 11,4, 18,8, 11,8, 8,12, 8,4, 10,16
  .byte 10,12, 10,4, 17,8, 10,8, 15,32
  .byte 15,24
  .byte $FF
M0_DRUM:
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 4,16
  .byte $FF
; objective destroyed: a short fanfare in D (about 2 seconds)
M1_LEAD:
  .byte 39,6, 39,6, 39,6, 46,18, 44,6, 46,6, 49,24, 0,6, 46,6, 49,6, 51,36
  .byte $FF
M1_HARM:
  .byte 34,24, 37,24, 41,24, 42,18, 46,36
  .byte $FF
M1_BASS:
  .byte 15,24, 13,24, 11,24, 10,18, 15,36
  .byte $FF
M1_DRUM:
  .byte 2,6, 2,6, 2,6, 1,18, 3,6, 3,6, 1,24, 2,6, 2,6, 2,6, 4,36
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
; Special Forces: generated by dev/gen_special_forces.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_RUN = 0
PT_JUMP = 16
PT_STAB = 24
PT_JSTAB = 32
PT_KNEEL = 40
PT_CLIMB = 56
PT_HDEAD = 64
PT_SOL = 68
PT_AIM = 84
PT_SHD = 92
PT_COU = 108
PT_NEST = 124
PT_EDEAD = 132
PT_BARREL = 140
PT_BULLET = 148
PT_SHELL = 152
PT_BOOM = 156
PT_CHARGE = 164
PT_PICK = 168
SPR_PAGES = 6
SPRITES:
  .byte $03,$07,$07,$07,$03,$07,$0F,$0D,$09,$19,$01,$06,$0C,$18,$10,$30
  .byte $C0,$E0,$20,$E0,$C0,$E0,$F0,$E0,$E0,$E0,$E0,$60,$30,$18,$08,$0C
  .byte $03,$07,$04,$07,$03,$07,$0F,$07,$07,$07,$07,$06,$0C,$18,$10,$30
  .byte $C0,$E0,$E0,$E0,$C0,$E0,$F0,$B0,$90,$98,$80,$60,$30,$18,$08,$0C
  .byte $03,$07,$07,$07,$03,$07,$0F,$0D,$09,$19,$01,$07,$03,$03,$06,$07
  .byte $C0,$E0,$20,$E0,$C0,$E0,$F0,$E0,$E0,$E0,$E0,$E0,$60,$60,$60,$70
  .byte $03,$07,$04,$07,$03,$07,$0F,$07,$07,$07,$07,$07,$06,$06,$06,$0E
  .byte $C0,$E0,$E0,$E0,$C0,$E0,$F0,$B0,$90,$98,$80,$E0,$C0,$C0,$60,$E0
  .byte $03,$07,$07,$07,$03,$07,$0F,$0D,$09,$19,$01,$0C,$18,$30,$20,$00
  .byte $C0,$E0,$20,$E0,$C0,$E0,$F0,$E0,$E0,$E0,$E0,$60,$38,$10,$00,$00
  .byte $03,$07,$04,$07,$03,$07,$0F,$07,$07,$07,$07,$06,$1C,$08,$00,$00
  .byte $C0,$E0,$E0,$E0,$C0,$E0,$F0,$B0,$90,$98,$80,$30,$18,$0C,$04,$00
  .byte $03,$07,$07,$07,$03,$07,$0F,$0F,$07,$07,$07,$07,$03,$03,$06,$07
  .byte $C0,$E0,$20,$E0,$C0,$E0,$FC,$DF,$C0,$80,$C0,$E0,$60,$60,$60,$70
  .byte $03,$07,$04,$07,$03,$07,$3F,$FB,$03,$01,$03,$07,$06,$06,$06,$0E
  .byte $C0,$E0,$E0,$E0,$C0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$C0,$C0,$60,$E0
  .byte $03,$07,$07,$07,$03,$07,$0F,$0F,$07,$07,$07,$0C,$18,$30,$20,$00
  .byte $C0,$E0,$20,$E0,$C0,$E0,$FC,$DF,$C0,$80,$C0,$60,$38,$10,$00,$00
  .byte $03,$07,$04,$07,$03,$07,$3F,$FB,$03,$01,$03,$06,$1C,$08,$00,$00
  .byte $C0,$E0,$E0,$E0,$C0,$E0,$F0,$F0,$E0,$E0,$E0,$30,$18,$0C,$04,$00
  .byte $00,$00,$00,$00,$00,$03,$07,$07,$07,$03,$07,$0F,$0D,$0F,$1F,$30
  .byte $00,$00,$00,$00,$00,$C0,$E0,$20,$E0,$C0,$E0,$F0,$E0,$E0,$80,$C0
  .byte $00,$00,$00,$00,$00,$03,$07,$04,$07,$03,$07,$0F,$07,$07,$01,$03
  .byte $00,$00,$00,$00,$00,$C0,$E0,$E0,$E0,$C0,$E0,$F0,$B0,$F0,$F8,$0C
  .byte $00,$00,$00,$00,$00,$03,$07,$07,$07,$03,$07,$0F,$0F,$0F,$1F,$30
  .byte $00,$00,$00,$00,$00,$C0,$E0,$20,$E0,$C0,$E0,$FC,$DF,$E0,$80,$C0
  .byte $00,$00,$00,$00,$00,$03,$07,$04,$07,$03,$07,$3F,$FB,$07,$01,$03
  .byte $00,$00,$00,$00,$00,$C0,$E0,$E0,$E0,$C0,$E0,$F0,$F0,$F0,$F8,$0C
  .byte $03,$07,$07,$07,$03,$2F,$3F,$07,$07,$03,$02,$06,$04,$0C,$04,$00
  .byte $C0,$E0,$20,$E0,$C0,$C0,$F0,$EC,$E4,$C0,$40,$60,$30,$10,$00,$00
  .byte $03,$07,$07,$07,$03,$03,$0F,$37,$27,$03,$02,$06,$0C,$08,$00,$00
  .byte $C0,$E0,$20,$E0,$C0,$F4,$FC,$E0,$E0,$C0,$40,$60,$20,$30,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$FF,$7F,$19
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0E,$FE,$FE,$8C
  .byte $07,$0F,$05,$07,$03,$07,$0F,$0F,$0B,$03,$03,$06,$0C,$18,$10,$30
  .byte $E0,$F0,$C0,$C0,$80,$E0,$F0,$FE,$C0,$C0,$C0,$60,$30,$18,$08,$0C
  .byte $07,$0F,$03,$03,$01,$07,$0F,$7F,$03,$03,$03,$06,$0C,$18,$10,$30
  .byte $E0,$F0,$A0,$E0,$C0,$E0,$F0,$F0,$D0,$C0,$C0,$60,$30,$18,$08,$0C
  .byte $07,$0F,$05,$07,$03,$07,$0F,$0F,$0B,$03,$03,$07,$03,$03,$06,$07
  .byte $E0,$F0,$C0,$C0,$80,$E0,$F0,$FE,$C0,$C0,$C0,$E0,$60,$60,$60,$70
  .byte $07,$0F,$03,$03,$01,$07,$0F,$7F,$03,$03,$03,$07,$06,$06,$06,$0E
  .byte $E0,$F0,$A0,$E0,$C0,$E0,$F0,$F0,$D0,$C0,$C0,$E0,$C0,$C0,$60,$E0
  .byte $00,$00,$00,$00,$00,$07,$0F,$05,$07,$03,$07,$0F,$0F,$1F,$30,$20
  .byte $00,$00,$00,$00,$00,$E0,$F0,$C0,$C0,$80,$E0,$FF,$C0,$80,$C0,$C0
  .byte $00,$00,$00,$00,$00,$07,$0F,$03,$03,$01,$07,$FF,$03,$01,$03,$03
  .byte $00,$00,$00,$00,$00,$E0,$F0,$A0,$E0,$C0,$E0,$F0,$F0,$F8,$0C,$04
  .byte $07,$0F,$05,$07,$03,$07,$0F,$0F,$0B,$03,$03,$06,$0C,$18,$10,$30
  .byte $E0,$F0,$C0,$CC,$98,$EC,$DC,$DC,$DC,$DC,$D8,$60,$30,$18,$08,$0C
  .byte $07,$0F,$03,$33,$19,$37,$3B,$3B,$3B,$3B,$1B,$06,$0C,$18,$10,$30
  .byte $E0,$F0,$A0,$E0,$C0,$E0,$F0,$F0,$D0,$C0,$C0,$60,$30,$18,$08,$0C
  .byte $07,$0F,$05,$07,$03,$07,$0F,$0F,$0B,$03,$03,$07,$03,$03,$06,$07
  .byte $E0,$F0,$C0,$CC,$98,$EC,$DC,$DC,$DC,$DC,$D8,$E0,$60,$60,$60,$70
  .byte $07,$0F,$03,$33,$19,$37,$3B,$3B,$3B,$3B,$1B,$07,$06,$06,$06,$0E
  .byte $E0,$F0,$A0,$E0,$C0,$E0,$F0,$F0,$D0,$C0,$C0,$E0,$C0,$C0,$60,$E0
  .byte $07,$0F,$05,$07,$03,$3D,$3F,$3F,$3D,$03,$03,$06,$0C,$18,$10,$30
  .byte $E0,$F0,$C0,$C0,$80,$E0,$F0,$FE,$E0,$C0,$C0,$60,$30,$18,$08,$0C
  .byte $07,$0F,$03,$03,$01,$07,$0F,$7F,$07,$03,$03,$06,$0C,$18,$10,$30
  .byte $E0,$F0,$A0,$E0,$C0,$BC,$FC,$FC,$BC,$C0,$C0,$60,$30,$18,$08,$0C
  .byte $07,$0F,$05,$07,$03,$3D,$3F,$3F,$3D,$03,$03,$07,$03,$03,$06,$07
  .byte $E0,$F0,$C0,$C0,$80,$E0,$F0,$FE,$E0,$C0,$C0,$E0,$60,$60,$60,$70
  .byte $07,$0F,$03,$03,$01,$07,$0F,$7F,$07,$03,$03,$07,$06,$06,$06,$0E
  .byte $E0,$F0,$A0,$E0,$C0,$BC,$FC,$FC,$BC,$C0,$C0,$E0,$C0,$C0,$60,$E0
  .byte $00,$00,$00,$07,$0F,$05,$07,$0F,$FF,$0F,$3F,$7F,$FF,$FE,$FF,$7F
  .byte $00,$00,$00,$E0,$F0,$C0,$C0,$FC,$FC,$F0,$FC,$FE,$FF,$FF,$FF,$FE
  .byte $00,$00,$00,$07,$0F,$03,$03,$3F,$3F,$0F,$3F,$7F,$FF,$FF,$FF,$7F
  .byte $00,$00,$00,$E0,$F0,$A0,$E0,$F0,$FF,$F0,$FC,$FE,$FF,$7F,$FF,$FE
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7E,$FF,$7F,$36
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FE,$FC,$6C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$3F,$36
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7E,$FF,$FE,$6C
  .byte $00,$00,$03,$0F,$1E,$3E,$3F,$7F,$67,$67,$7F,$3F,$3E,$1E,$0F,$03
  .byte $00,$00,$C0,$F0,$78,$7C,$FC,$FE,$E6,$E6,$FE,$FC,$7C,$78,$F0,$C0
  .byte $00,$00,$03,$0F,$1F,$37,$3B,$7D,$7F,$7F,$7D,$3B,$37,$1F,$0F,$03
  .byte $00,$00,$C0,$F0,$F8,$EC,$DC,$BE,$FE,$FE,$BE,$DC,$EC,$F8,$F0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$C0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$0D,$0F,$07,$1F,$1F,$07,$0F,$0D,$01,$00,$00,$00
  .byte $00,$00,$00,$80,$B0,$F0,$E0,$F8,$F8,$E0,$F0,$B0,$80,$00,$00,$00
  .byte $00,$06,$07,$37,$3F,$3F,$1F,$7F,$7F,$1F,$3F,$3F,$37,$07,$06,$00
  .byte $00,$60,$E0,$EC,$FC,$FC,$F8,$FE,$FE,$F8,$FC,$FC,$EC,$E0,$60,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$00,$0F,$08,$0B,$0B,$08,$0F,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$F0,$10,$D0,$D0,$10,$F0,$00
  .byte $00,$00,$00,$00,$00,$00,$7F,$40,$5F,$5F,$4D,$49,$40,$7F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$FE,$02,$C2,$E2,$02,$02,$02,$FE,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$7F,$40,$40,$40,$43,$45,$48,$7F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$FE,$1A,$3A,$E2,$82,$02,$82,$FE,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$7F,$41,$47,$44,$45,$47,$40,$7F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$FE,$02,$C2,$42,$42,$C2,$02,$FE,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

T_LIFE = 1
T_KNIFE = 2
SMALL_PAT:
  .byte $30,$78,$30,$78,$B4,$30,$48,$48,$00,$00,$02,$06,$0C,$58,$30,$50
  .byte $00,$00,$FE,$FF,$68,$48,$40,$00,$02,$07,$0E,$1C,$38,$50,$88,$00
  .byte $10,$08,$7E,$42,$5A,$42,$7E,$00
SMALL_COL:
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $90,$90,$90,$90,$90,$90,$90,$90
GT0_PLO:
  .byte $0F,$0F,$0F,$00,$00,$00,$00,$00,$F0,$F0,$F0,$00,$00,$00,$00,$00
  .byte $0F,$0F,$0F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$F0,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$0F,$0F,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$F0,$F0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$04,$05,$06,$07,$06,$05,$04,$04,$04,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$0A,$0C,$00,$C0,$A0,$90,$88,$84,$82,$81
  .byte $81,$82,$04,$08,$10,$20,$40,$80,$00,$80,$40,$40,$10,$08,$04,$02
  .byte $01,$02,$04,$08,$20,$40,$00,$00,$00,$00,$00,$40,$20,$10,$04,$02
  .byte $07,$07,$00,$E0,$E0,$E0,$E0,$E0,$00,$03,$05,$09,$11,$21,$41,$81
GT0_CLO:
  .byte $10,$10,$10,$11,$11,$11,$11,$00,$10,$10,$10,$11,$11,$11,$11,$00
  .byte $80,$80,$80,$80,$00,$00,$00,$00,$88,$88,$88,$88,$66,$66,$66,$66
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$99,$99,$99,$99,$99,$99,$99,$99
  .byte $80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$10,$10,$10,$11
  .byte $11,$11,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$10,$10,$11
  .byte $00,$00,$00,$00,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$00
  .byte $00,$00,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$55,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$55,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$00,$00,$55,$00,$00,$50,$50,$50,$50,$50
  .byte $DC,$DC,$CC,$CF,$CF,$CF,$CF,$CF,$55,$50,$50,$50,$50,$50,$50,$50
GT0_PHI:
  .byte $81,$41,$20,$10,$08,$04,$02,$01,$00,$01,$02,$02,$08,$10,$20,$40
  .byte $80,$40,$20,$10,$04,$02,$00,$00,$00,$00,$00,$02,$04,$08,$20,$40
  .byte $E0,$E0,$00,$07,$07,$07,$07,$07,$00,$00,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40,$20,$A0,$60
  .byte $E0,$60,$A0,$20,$20,$20,$10,$10,$10,$10,$10,$10,$10,$10,$50,$30
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$04,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
GT0_CHI:
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$55,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$00,$00,$55,$00,$00,$50,$50,$50,$50,$50
  .byte $DC,$DC,$CC,$CF,$CF,$CF,$CF,$CF,$00,$00,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00
  .byte $77,$66,$66,$66,$66,$66,$66,$66
GT1_PLO:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$38,$34,$31,$30,$30,$30,$30,$30
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$00,$00,$00,$80,$20,$10,$04,$02
  .byte $80,$40,$10,$08,$02,$01,$00,$00,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$4C,$2C,$80,$80,$C3,$43,$43,$C3,$80,$00
  .byte $00,$00,$C3,$3C,$3C,$C3,$00,$00,$00,$00,$18,$18,$E0,$18,$18,$18
  .byte $E0,$18,$24,$3C,$C0,$24,$18,$00,$00,$00,$18,$18,$07,$18,$18,$18
  .byte $07,$18,$24,$3C,$03,$24,$18,$00,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $E0,$18,$18,$18,$E0,$18,$18,$18,$07,$18,$18,$18,$07,$18,$18,$18
  .byte $01,$01,$C3,$C2,$C2,$C3,$01,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$02,$03,$02,$02,$02,$02,$02,$02,$02
  .byte $E0,$18,$12,$11,$10,$10,$10,$10,$C0,$30,$24,$42,$40,$40,$40,$40
  .byte $40,$40,$40,$40,$81,$84,$90,$C0,$00,$A0,$88,$82,$80,$80,$00,$00
GT1_CLO:
  .byte $66,$66,$66,$66,$66,$66,$66,$66,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$00,$00,$00,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$00,$00,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$54,$54,$54,$45,$45,$54,$54,$55
  .byte $44,$44,$54,$54,$54,$54,$44,$55,$00,$00,$50,$50,$05,$50,$50,$50
  .byte $45,$54,$45,$54,$45,$45,$54,$55,$00,$00,$50,$50,$05,$50,$50,$50
  .byte $45,$54,$45,$54,$45,$45,$54,$55,$40,$40,$40,$40,$40,$40,$40,$40
  .byte $05,$50,$50,$50,$05,$50,$50,$50,$05,$50,$50,$50,$05,$50,$50,$50
  .byte $54,$54,$54,$45,$45,$54,$54,$55,$00,$00,$00,$00,$00,$00,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $05,$50,$50,$50,$50,$50,$50,$50,$05,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$55,$50,$50,$50,$50,$50,$00,$00
GT1_PHI:
  .byte $00,$00,$00,$00,$01,$04,$10,$80,$00,$80,$20,$08,$01,$00,$00,$00
  .byte $E0,$E0,$E0,$E0,$E0,$00,$00,$00,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $07,$07,$00,$E0,$E0,$E0,$E0,$E0,$07,$07,$07,$07,$07,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$04,$10,$40,$80,$40,$10,$04,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$04,$08,$20,$E0,$E0,$00,$07,$07,$07,$07,$07
  .byte $07,$18,$48,$88,$08,$08,$08,$08,$03,$0C,$24,$42,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$81,$21,$09,$03,$00,$05,$11,$41,$01,$01,$00,$00
  .byte $00,$00,$00,$00,$80,$20,$08,$01,$00,$01,$04,$10,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$80,$40
  .byte $C0,$40,$40,$40,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$00,$00,$18,$18,$E0,$18,$18,$18
  .byte $00,$00,$18,$18,$07,$18,$18,$18,$E0,$18,$18,$18,$E0,$18,$18,$18
  .byte $E0,$18,$18,$18,$E0,$18,$18,$18,$07,$18,$18,$18,$07,$18,$18,$18
  .byte $07,$18,$18,$18,$07,$18,$18,$18,$00,$00,$18,$18,$E0,$18,$18,$18
  .byte $00,$00,$18,$18,$07,$18,$18,$18,$1C,$1C,$18,$18,$E0,$18,$18,$18
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$81,$81,$81,$81,$00,$00
  .byte $00,$00,$40,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$04,$00,$00,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$E0,$18,$18,$18,$E0,$18,$18,$18
  .byte $E0,$18,$18,$18,$E0,$18,$18,$18,$07,$18,$18,$18,$07,$18,$18,$18
  .byte $07,$18,$18,$18,$07,$18,$18,$18,$00,$00,$18,$18,$E0,$18,$18,$18
  .byte $00,$00,$18,$18,$07,$18,$18,$18
GT1_CHI:
  .byte $00,$00,$00,$00,$50,$50,$50,$50,$55,$50,$50,$50,$50,$00,$00,$00
  .byte $CF,$CF,$CF,$CF,$CF,$CC,$CC,$CC,$45,$40,$40,$40,$40,$40,$40,$40
  .byte $DC,$DC,$CC,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CC,$CC,$CC
  .byte $55,$00,$00,$00,$50,$50,$50,$50,$50,$50,$50,$50,$00,$00,$00,$00
  .byte $55,$00,$00,$00,$50,$50,$50,$50,$DC,$DC,$CC,$CF,$CF,$CF,$CF,$CF
  .byte $05,$50,$50,$50,$50,$50,$50,$50,$05,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$55,$50,$50,$50,$50,$50,$00,$00
  .byte $00,$00,$00,$00,$50,$50,$50,$50,$55,$50,$50,$50,$50,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $BB,$BB,$AA,$AA,$AA,$AA,$AA,$AA,$4A,$4A,$4A,$4A,$4A,$4A,$4A,$4A
  .byte $4B,$4B,$4A,$4A,$4A,$4A,$4A,$4A,$BB,$BB,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $BB,$BB,$5A,$5A,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $B5,$5B,$5A,$5A,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $B5,$5B,$5A,$5A,$A5,$5A,$5A,$5A,$AA,$AA,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $AA,$AA,$5A,$5A,$A5,$5A,$5A,$5A,$4A,$4A,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $77,$66,$66,$66,$66,$66,$66,$66,$7F,$6F,$6F,$6F,$66,$66,$66,$66
  .byte $7F,$6F,$6F,$6F,$66,$66,$66,$66,$66,$66,$6E,$6E,$6E,$6E,$66,$66
  .byte $00,$00,$10,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$10,$00,$00,$46,$46,$46,$46,$46,$46,$46,$46
  .byte $47,$46,$46,$46,$46,$46,$46,$46,$65,$56,$56,$56,$65,$56,$56,$56
  .byte $75,$56,$56,$56,$65,$56,$56,$56,$65,$56,$56,$56,$65,$56,$56,$56
  .byte $75,$56,$56,$56,$65,$56,$56,$56,$66,$66,$56,$56,$65,$56,$56,$56
  .byte $66,$66,$56,$56,$65,$56,$56,$56
GT2_PLO:
  .byte $00,$00,$00,$00,$00,$00,$CC,$33,$C1,$C2,$E4,$D8,$D8,$E4,$C2,$C1
  .byte $00,$00,$00,$40,$00,$00,$00,$00,$00,$80,$00,$00,$00,$01,$00,$00
  .byte $81,$42,$24,$18,$18,$24,$42,$81,$00,$00,$00,$00,$00,$00,$00,$80
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$30,$30,$30,$30,$30,$30,$30,$30
  .byte $38,$34,$31,$30,$30,$30,$30,$30,$00,$00,$00,$80,$20,$10,$04,$02
  .byte $80,$40,$10,$08,$02,$01,$00,$00,$0C,$0C,$0C,$0C,$0C,$0C,$4C,$2C
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$23,$C0,$62,$A1,$3C,$1C,$1C,$3C,$A1,$62
  .byte $E0,$18,$18,$18,$E0,$18,$18,$18,$07,$18,$18,$18,$07,$18,$18,$18
  .byte $22,$21,$03,$23,$23,$03,$21,$22,$00,$00,$00,$66,$66,$66,$00,$00
  .byte $07,$05,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$10,$10,$10,$14
  .byte $E0,$14,$10,$10,$10,$20,$20,$20,$20,$20,$20,$20,$20,$20,$21,$50
GT2_CLO:
  .byte $00,$00,$00,$00,$00,$00,$40,$40,$40,$40,$40,$40,$40,$40,$40,$40
  .byte $33,$33,$22,$32,$22,$22,$22,$22,$22,$32,$22,$22,$22,$32,$22,$22
  .byte $40,$40,$40,$40,$40,$40,$40,$40,$33,$33,$22,$22,$22,$22,$22,$32
  .byte $22,$22,$22,$32,$22,$22,$22,$22,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$00,$00,$00,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$00,$00,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$40,$40,$40,$40,$40,$40,$40,$40
  .byte $40,$40,$40,$40,$40,$40,$04,$04,$04,$04,$40,$40,$40,$40,$04,$04
  .byte $05,$50,$50,$50,$05,$50,$50,$50,$05,$50,$50,$50,$05,$50,$50,$50
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$00,$44,$44,$40,$40,$40,$44,$44
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $05,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
GT2_PHI:
  .byte $80,$50,$42,$40,$40,$40,$40,$40,$00,$00,$40,$10,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$20,$80,$00,$00,$00,$80,$20,$04,$01,$00,$00
  .byte $00,$00,$00,$01,$08,$20,$00,$00,$00,$00,$00,$40,$08,$01,$00,$00
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$07,$07,$00,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$01,$08,$20
  .byte $80,$20,$04,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$20
  .byte $E0,$E0,$00,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$00,$00,$00
  .byte $00,$00,$02,$08,$40,$00,$00,$00,$00,$00,$00,$00,$20,$04,$01,$00
  .byte $00,$00,$01,$04,$20,$80,$00,$00,$00,$00,$00,$80,$10,$04,$00,$00
  .byte $00,$00,$00,$02,$10,$80,$00,$00,$E0,$A0,$10,$10,$10,$10,$10,$10
  .byte $10,$10,$10,$10,$08,$08,$08,$28,$07,$28,$08,$08,$08,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$84,$0A,$01,$0A,$42,$02,$02,$02,$02,$02
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$E0,$18,$18,$18,$E0,$18,$18,$18
  .byte $E0,$18,$18,$18,$E0,$18,$18,$18,$07,$18,$18,$18,$07,$18,$18,$18
  .byte $07,$18,$18,$18,$07,$18,$18,$18,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$E0,$18,$18,$18,$E0,$18,$18,$18
  .byte $07,$18,$18,$18,$07,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $00,$00,$00,$18,$3C,$81,$81,$81,$E0,$18,$18,$18,$E0,$18,$18,$18
  .byte $E0,$18,$18,$18,$E0,$18,$18,$18,$07,$18,$18,$18,$07,$18,$18,$18
  .byte $07,$18,$18,$18,$07,$18,$18,$18,$00,$00,$00,$18,$3C,$81,$81,$81
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $00,$00,$00,$99,$99,$99,$00,$00,$E0,$18,$18,$18,$E0,$18,$18,$18
  .byte $07,$18,$18,$18,$07,$18,$18,$18,$00,$00,$00,$18,$3C,$81,$81,$81
  .byte $80,$80,$80,$80,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00,$00
GT2_CHI:
  .byte $05,$50,$50,$50,$50,$50,$50,$50,$55,$00,$50,$50,$50,$00,$00,$00
  .byte $00,$00,$00,$00,$50,$50,$50,$00,$55,$00,$50,$50,$50,$50,$00,$00
  .byte $00,$00,$00,$50,$50,$50,$00,$00,$55,$00,$00,$50,$50,$50,$00,$00
  .byte $45,$40,$40,$40,$40,$40,$40,$40,$DC,$DC,$CC,$CF,$CF,$CF,$CF,$CF
  .byte $CF,$CF,$CF,$CF,$CF,$CC,$CC,$CC,$55,$00,$00,$00,$00,$50,$50,$50
  .byte $50,$50,$50,$50,$00,$00,$00,$00,$55,$00,$00,$00,$00,$00,$50,$50
  .byte $DC,$DC,$CC,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CC,$CC,$CC
  .byte $55,$00,$50,$50,$50,$00,$00,$00,$00,$00,$00,$00,$50,$50,$50,$00
  .byte $55,$00,$50,$50,$50,$50,$00,$00,$00,$00,$00,$50,$50,$50,$00,$00
  .byte $55,$00,$00,$50,$50,$50,$00,$00,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$05,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$05,$50,$50,$50,$50,$50,$50,$50
  .byte $88,$88,$88,$88,$88,$88,$88,$88,$66,$66,$66,$66,$66,$66,$66,$66
  .byte $69,$69,$69,$69,$69,$69,$69,$69,$48,$48,$48,$48,$48,$48,$48,$48
  .byte $46,$46,$46,$46,$46,$46,$46,$46,$85,$58,$58,$58,$85,$58,$58,$58
  .byte $65,$56,$56,$56,$65,$56,$56,$56,$85,$58,$58,$58,$85,$58,$58,$58
  .byte $65,$56,$56,$56,$65,$56,$56,$56,$67,$67,$67,$67,$67,$67,$67,$67
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$BB,$BB,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $4B,$4B,$4B,$4B,$4B,$4B,$4B,$4B,$B5,$5B,$5B,$5B,$B5,$5B,$5B,$5B
  .byte $B5,$5B,$5B,$5B,$B5,$5B,$5B,$5B,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB
  .byte $4A,$4A,$4A,$4A,$4A,$4A,$4A,$4A,$4B,$4B,$4A,$4A,$4A,$4A,$4A,$4A
  .byte $BB,$BB,$AA,$CA,$FA,$AF,$AF,$AF,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $B5,$5B,$5A,$5A,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A,$A5,$5A,$5A,$5A
  .byte $B5,$5B,$5A,$5A,$A5,$5A,$5A,$5A,$00,$00,$00,$C0,$F0,$0F,$0F,$0F
  .byte $77,$66,$66,$66,$66,$66,$66,$66,$47,$46,$46,$46,$46,$46,$46,$46
  .byte $66,$44,$44,$64,$64,$64,$44,$44,$75,$56,$56,$56,$65,$56,$56,$56
  .byte $75,$56,$56,$56,$65,$56,$56,$56,$66,$66,$66,$C6,$F6,$6F,$6F,$6F
  .byte $7F,$6F,$6F,$6F,$66,$66,$66,$66,$7F,$6F,$6F,$6F,$66,$66,$66,$66
ZERO8: .byte 0,0,0,0,0,0,0,0
; sector palettes: material -> TMS colour
WPAL:
  .byte $05,$0F,$0A,$06,$0E,$01,$0A,$06,$06,$01,$0F,$0E,$08,$0F,$0B,$01
  .byte $07,$0F,$0A,$06,$0E,$01,$0C,$01,$06,$01,$0F,$0E,$08,$0F,$0B,$01
  .byte $09,$0B,$0A,$06,$0E,$01,$0D,$01,$06,$01,$0F,$0E,$06,$0F,$0B,$01
  .byte $04,$0F,$0E,$01,$0E,$01,$0E,$01,$01,$01,$0F,$0E,$08,$0F,$09,$01

; 3 bands of 7 rows (108 / 146 / 77 types): ROWr = tile of screen row r for every type of its band
ROW2:
  .byte $00,$00,$00,$00,$00,$00,$00,$0F,$11,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$12,$11,$00,$19,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$6D,$6C,$00,$00,$00,$00,$00,$6B,$00
  .byte $00,$00,$00,$00,$00,$6C,$6C,$00,$00,$00,$6B,$00,$6B,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$6D,$6C,$6D,$6D,$6B,$00,$00
  .byte $00,$00,$00,$00,$6D,$00,$00,$00,$00,$00,$00,$00,$00,$6B,$00,$00
  .byte $00,$6B,$00,$6D,$00,$00,$6B,$00,$00,$00,$00,$6C
ROW3:
  .byte $00,$00,$00,$00,$00,$00,$00,$10,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$10,$10,$14,$1A,$60,$65,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$6C,$00,$6D,$00,$00,$00,$00,$6B,$00,$6B,$00,$00
  .byte $6B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $6D,$00,$6B,$00,$00,$00,$00,$6B,$00,$00,$00,$6C,$00,$00,$00,$00
  .byte $6C,$00,$00,$00,$00,$00,$6B,$00,$6C,$00,$00,$00,$6D,$00,$00,$00
  .byte $00,$00,$00,$00,$6D,$00,$6C,$6D,$00,$00,$00,$00
ROW4:
  .byte $00,$08,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$13,$00
  .byte $08,$09,$00,$00,$15,$1B,$61,$66,$08,$00,$00,$08,$13,$00,$00,$00
  .byte $00,$00,$00,$6B,$00,$00,$6B,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $6D,$00,$6D,$6D,$00,$00,$00,$00,$00,$6C,$00,$6D,$00,$6D,$00,$00
  .byte $00,$00,$00,$00,$00,$6D,$00,$00,$6C,$6B,$00,$00,$00,$00,$00,$00
  .byte $00,$6D,$6D,$00,$6D,$00,$00,$00,$00,$6B,$00,$00,$00,$00,$00,$6D
  .byte $00,$6C,$6B,$00,$00,$00,$00,$6B,$6B,$00,$6C,$00
ROW5:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$12,$11,$00,$11
  .byte $00,$00,$00,$00,$16,$1C,$62,$67,$00,$12,$11,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$6C,$6B,$6D,$00,$00,$6D
  .byte $00,$00,$00,$00,$6B,$00,$00,$6C,$00,$6B,$00,$6B,$00,$6B,$00,$6C
  .byte $00,$00,$00,$00,$00,$00,$6D,$6D,$00,$6B,$6D,$6C,$00,$6D,$00,$00
  .byte $00,$00,$6D,$6B,$00,$00,$00,$00,$00,$00,$6B,$00,$00,$00,$6C,$00
  .byte $00,$00,$00,$00,$00,$6D,$00,$00,$00,$00,$00,$00
ROW6:
  .byte $00,$00,$00,$0A,$0B,$0B,$0E,$00,$00,$00,$00,$10,$10,$10,$00,$10
  .byte $0B,$0E,$00,$00,$17,$1D,$63,$68,$00,$10,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$6B,$00,$6D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$6D,$6D
  .byte $00,$00,$00,$00,$00,$6B,$6C,$00,$00,$6C,$6B,$00,$00,$00,$6C,$00
  .byte $6D,$00,$00,$00,$00,$6C,$00,$00,$6C,$6D,$6C,$00,$00,$6C,$00,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
ROW7:
  .byte $00,$00,$00,$00,$0C,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $0C,$00,$00,$00,$18,$1E,$64,$69,$00,$00,$00,$00,$00,$00,$00,$6A
  .byte $1E,$64,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$6D,$00,$00,$6C,$00,$6B,$00,$00,$00,$00,$6D
  .byte $6C,$6B,$00,$6D,$00,$00,$00,$00,$00,$6D,$00,$00,$6D,$6B,$00,$6C
  .byte $00,$6C,$00,$00,$6C,$00,$6D,$6B,$00,$00,$6B,$6B,$00,$00,$00,$6E
  .byte $6E,$6E,$6E,$6E,$6E,$6E,$6E,$6E,$1E,$64,$6E,$6E
ROW8:
  .byte $00,$00,$00,$00,$08,$08,$00,$00,$00,$11,$13,$00,$00,$00,$00,$11
  .byte $08,$00,$00,$11,$1C,$62,$65,$6A,$13,$11,$13,$11,$13,$7D,$7E,$73
  .byte $62,$65,$73,$00,$00,$84,$00,$00,$00,$86,$00,$85,$86,$00,$00,$00
  .byte $00,$84,$00,$00,$00,$00,$86,$11,$00,$00,$84,$11,$13,$00,$00,$00
  .byte $85,$00,$85,$00,$85,$00,$84,$00,$00,$00,$00,$00,$00,$84,$86,$13
  .byte $84,$00,$00,$84,$00,$00,$00,$86,$85,$00,$00,$85,$00,$00,$13,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$62,$65,$08,$08
ROW9:
  .byte $00,$09,$0B,$00,$0D,$00,$00,$00,$00,$0F,$10,$12,$14,$10,$18,$00
  .byte $09,$0B,$00,$0D,$10,$10,$10,$10,$10,$18,$10,$10,$10,$10,$10,$10
  .byte $12,$14,$18,$10,$10,$00,$00,$00,$00,$0F,$10,$10,$10,$10,$18,$00
  .byte $00,$00,$00,$12,$14,$12,$14,$00,$00,$00,$12,$14,$10,$10,$10,$10
  .byte $10,$10,$18,$00,$00,$00,$00,$85,$00,$00,$85,$00,$00,$00,$0F,$10
  .byte $12,$14,$10,$10,$18,$00,$00,$0F,$10,$10,$10,$10,$10,$18,$00,$00
  .byte $00,$86,$00,$00,$00,$00,$85,$10,$10,$10,$10,$10,$10,$10,$10,$10
  .byte $18,$86,$12,$14,$10,$18,$00,$00,$00,$00,$84,$86,$85,$0F,$10,$10
  .byte $10,$10,$10,$10,$10,$18,$00,$84,$00,$85,$86,$00,$86,$10,$10,$10
  .byte $10,$18
ROW10:
  .byte $00,$0A,$00,$0C,$0E,$00,$00,$00,$00,$15,$15,$16,$17,$00,$00,$00
  .byte $0A,$00,$0C,$0E,$00,$15,$00,$00,$00,$00,$00,$1D,$63,$66,$6B,$00
  .byte $16,$17,$00,$15,$00,$00,$00,$00,$00,$15,$15,$00,$00,$15,$00,$00
  .byte $00,$00,$00,$16,$17,$16,$17,$00,$00,$00,$7A,$7C,$74,$76,$74,$74
  .byte $74,$76,$74,$08,$08,$08,$83,$08,$08,$08,$00,$00,$86,$00,$15,$15
  .byte $16,$17,$00,$00,$00,$08,$08,$87,$87,$08,$08,$83,$08,$08,$86,$00
  .byte $00,$86,$00,$84,$00,$84,$00,$00,$00,$00,$84,$85,$08,$08,$83,$87
  .byte $08,$08,$89,$8B,$86,$00,$85,$00,$00,$85,$00,$00,$00,$15,$15,$00
  .byte $00,$00,$85,$00,$00,$00,$00,$86,$84,$00,$00,$00,$00,$08,$08,$08
  .byte $08,$08
ROW11:
  .byte $00,$09,$0B,$00,$0D,$00,$00,$00,$00,$15,$15,$16,$17,$00,$00,$00
  .byte $09,$0B,$00,$0D,$00,$15,$00,$00,$00,$00,$00,$1E,$15,$67,$6C,$00
  .byte $16,$17,$00,$15,$00,$00,$73,$00,$73,$75,$15,$00,$73,$75,$73,$73
  .byte $73,$00,$73,$79,$17,$16,$7B,$00,$00,$73,$79,$7B,$73,$75,$73,$73
  .byte $73,$75,$73,$80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$86,$15,$15
  .byte $16,$17,$00,$00,$00,$80,$80,$88,$88,$80,$80,$80,$80,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$85,$85,$84,$00,$00,$80,$80,$80,$88
  .byte $80,$80,$8A,$8C,$00,$00,$00,$84,$00,$00,$85,$00,$00,$15,$15,$00
  .byte $00,$85,$84,$00,$85,$00,$00,$00,$85,$85,$86,$86,$00,$80,$80,$80
  .byte $80,$80
ROW12:
  .byte $00,$0A,$00,$0C,$0E,$00,$00,$00,$00,$15,$15,$16,$17,$00,$00,$00
  .byte $0A,$00,$0C,$0E,$00,$15,$00,$00,$00,$00,$19,$1F,$63,$68,$6D,$70
  .byte $16,$17,$00,$15,$00,$73,$73,$73,$73,$75,$75,$73,$73,$75,$73,$73
  .byte $73,$73,$73,$79,$7B,$79,$7B,$73,$73,$73,$79,$7B,$73,$75,$73,$73
  .byte $73,$75,$73,$08,$08,$08,$08,$08,$08,$08,$00,$08,$08,$08,$87,$87
  .byte $89,$8B,$08,$83,$08,$08,$08,$87,$87,$08,$08,$08,$08,$08,$00,$08
  .byte $83,$08,$08,$08,$08,$00,$00,$08,$00,$00,$08,$83,$08,$08,$08,$87
  .byte $08,$08,$89,$8B,$00,$83,$08,$00,$00,$00,$00,$00,$00,$15,$15,$00
  .byte $00,$00,$00,$08,$08,$00,$83,$08,$08,$08,$00,$00,$00,$08,$08,$08
  .byte $08,$08
ROW13:
  .byte $00,$09,$0B,$00,$0D,$00,$00,$00,$00,$15,$15,$16,$17,$00,$00,$00
  .byte $09,$0B,$00,$0D,$00,$15,$00,$00,$00,$00,$1A,$60,$64,$69,$6E,$71
  .byte $16,$17,$00,$15,$00,$73,$73,$73,$73,$75,$75,$73,$73,$75,$73,$73
  .byte $73,$73,$73,$79,$7B,$79,$7B,$73,$73,$73,$7A,$7C,$74,$76,$74,$64
  .byte $69,$76,$74,$80,$81,$82,$80,$80,$80,$80,$00,$80,$80,$80,$88,$88
  .byte $8A,$8C,$80,$80,$80,$80,$80,$88,$88,$81,$82,$80,$80,$80,$00,$80
  .byte $80,$80,$80,$80,$80,$00,$00,$80,$00,$00,$80,$80,$81,$82,$80,$88
  .byte $80,$80,$8A,$8C,$00,$80,$80,$00,$00,$00,$00,$00,$00,$15,$15,$00
  .byte $00,$00,$00,$80,$80,$00,$80,$80,$80,$80,$00,$00,$00,$80,$80,$64
  .byte $69,$80
ROW14:
  .byte $00,$0A,$00,$0C,$0E,$00,$00,$11,$13,$15,$15,$16,$17,$00,$00,$00
  .byte $0A,$00,$0C,$0E,$00,$15,$00,$00,$11,$13,$1B,$61,$62,$65,$6F,$72
  .byte $16,$17,$00,$15,$13,$74,$74,$74,$74,$76,$76,$74,$74,$76,$74,$74
  .byte $77,$78,$74,$7A,$7C,$7A,$7C,$74,$77,$78,$79,$7B,$73,$7F,$7E,$62
  .byte $65,$75,$73,$08,$08,$08,$08,$08,$08,$08,$00,$08,$08,$08,$87,$87
  .byte $89,$8B,$08,$08,$08,$8D,$8E,$87,$87,$08,$08,$08,$08,$08,$00,$08
  .byte $08,$08,$08,$08,$08,$00,$13,$08,$00,$00,$08,$08,$08,$08,$08,$87
  .byte $08,$08,$89,$8B,$00,$08,$08,$00,$08,$08,$08,$8D,$8E,$87,$87,$08
  .byte $83,$08,$08,$08,$08,$00,$08,$08,$08,$08,$00,$00,$13,$8D,$8E,$62
  .byte $65,$08
ROW15:
  .byte $00,$09,$0B,$00,$0D,$0F,$10,$12,$14,$10,$10,$10,$10,$10,$10,$18
  .byte $10,$10,$10,$10,$18,$15,$00,$0F,$12,$14,$10,$10,$10,$10,$10,$10
  .byte $12,$14,$18,$18,$14,$73,$73,$10,$10,$10,$10,$10,$10,$10,$10,$0F
  .byte $12,$14,$18,$10,$10,$10,$10,$18,$12,$14,$10,$10,$10,$12,$14,$10
  .byte $10,$10,$18,$80,$80,$80,$80,$80,$0F,$10,$10,$10,$10,$10,$10,$10
  .byte $10,$10,$10,$10,$18,$12,$14,$10,$10,$10,$10,$10,$10,$10,$10,$18
  .byte $80,$80,$80,$80,$0F,$10,$14,$10,$10,$10,$10,$10,$18,$80,$80,$88
  .byte $80,$80,$10,$10,$10,$10,$10,$00,$80,$0F,$10,$12,$14,$10,$10,$10
  .byte $10,$10,$10,$18,$80,$00,$10,$10,$10,$10,$00,$0F,$14,$12,$14,$10
  .byte $10,$18
ROW16:
  .byte $08,$08,$08,$00,$0F,$00,$12,$13,$15,$16,$18,$19,$16,$08,$08,$00
  .byte $08,$1C,$61,$66,$69,$6E,$73,$78,$78,$7B,$7B,$7D,$7F,$78,$78,$15
  .byte $7C,$79,$79,$79,$7C,$79,$82,$82,$15,$15,$18,$19,$00,$00,$88,$82
  .byte $88,$8B,$8D,$00,$88,$82,$82,$82,$82,$8B,$8D,$79,$79,$7C,$7C,$00
  .byte $79,$7E,$80,$79,$79,$79,$79,$79,$79,$00,$79,$79,$7C
ROW17:
  .byte $09,$0C,$0C,$00,$10,$11,$00,$14,$15,$17,$18,$19,$1A,$09,$0C,$00
  .byte $0C,$1D,$62,$15,$6A,$6F,$74,$79,$79,$7C,$7C,$7E,$80,$79,$79,$15
  .byte $7C,$7A,$79,$79,$7C,$79,$83,$83,$15,$15,$18,$19,$00,$00,$89,$83
  .byte $89,$8C,$8E,$00,$88,$82,$82,$82,$82,$8B,$8D,$90,$90,$91,$91,$00
  .byte $90,$93,$94,$90,$96,$97,$96,$97,$90,$00,$90,$90,$91
ROW18:
  .byte $09,$0C,$0C,$00,$0F,$00,$12,$13,$15,$17,$18,$19,$1A,$09,$0C,$00
  .byte $0C,$1E,$63,$66,$6B,$70,$75,$79,$7A,$7C,$7C,$7E,$80,$79,$81,$15
  .byte $7C,$79,$79,$79,$7C,$79,$82,$82,$15,$15,$18,$19,$00,$00,$88,$82
  .byte $88,$8B,$8D,$00,$88,$82,$82,$82,$82,$8B,$8D,$79,$79,$7C,$7C,$00
  .byte $79,$7E,$80,$79,$79,$79,$79,$79,$79,$00,$79,$79,$7C
ROW19:
  .byte $09,$0C,$0C,$00,$10,$11,$00,$14,$15,$17,$18,$19,$1A,$09,$0C,$00
  .byte $0C,$1F,$64,$67,$6C,$71,$76,$79,$79,$7C,$7C,$7E,$80,$79,$81,$15
  .byte $7C,$79,$79,$79,$67,$6C,$82,$82,$84,$84,$85,$86,$87,$87,$88,$82
  .byte $88,$8B,$8D,$87,$89,$83,$83,$67,$6C,$8C,$8E,$90,$90,$91,$91,$00
  .byte $90,$93,$94,$90,$90,$90,$90,$90,$90,$00,$67,$6C,$67
ROW20:
  .byte $09,$0C,$0C,$00,$0F,$00,$12,$13,$15,$17,$18,$19,$1A,$1B,$1B,$00
  .byte $1B,$60,$65,$68,$6D,$72,$77,$79,$79,$7C,$7C,$7E,$80,$79,$81,$15
  .byte $7C,$79,$79,$79,$68,$6D,$83,$83,$15,$15,$18,$19,$00,$00,$89,$8A
  .byte $89,$8C,$8E,$8F,$88,$82,$82,$68,$6D,$8B,$8D,$79,$79,$7C,$7C,$1B
  .byte $92,$7E,$80,$95,$95,$79,$79,$79,$92,$8F,$68,$6D,$68
ROW21:
  .byte $0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0A,$0D,$0A
  .byte $0A,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0D,$0A,$0D
  .byte $0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0D,$0A,$0A,$0A
  .byte $0D,$0A,$0D,$0A,$0A,$0D,$0A,$0A,$0D,$0A,$0D,$0A,$0D,$0A,$0D,$0A
  .byte $0D,$0A,$0D,$0A,$0A,$0D,$0D,$0A,$0A,$0A,$0A,$0D,$0A
ROW22:
  .byte $0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0B,$0E,$0B
  .byte $0B,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0E,$0B,$0E
  .byte $0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0E,$0B,$0B,$0B
  .byte $0E,$0B,$0E,$0B,$0B,$0E,$0B,$0B,$0E,$0B,$0E,$0B,$0E,$0B,$0E,$0B
  .byte $0E,$0B,$0E,$0B,$0B,$0E,$0E,$0B,$0B,$0B,$0B,$0E,$0B
CR_LO: .byte <ROW2,<ROW3,<ROW4,<ROW5,<ROW6,<ROW7,<ROW8,<ROW9,<ROW10,<ROW11,<ROW12,<ROW13,<ROW14,<ROW15,<ROW16,<ROW17,<ROW18,<ROW19,<ROW20,<ROW21,<ROW22
CR_HI: .byte >ROW2,>ROW3,>ROW4,>ROW5,>ROW6,>ROW7,>ROW8,>ROW9,>ROW10,>ROW11,>ROW12,>ROW13,>ROW14,>ROW15,>ROW16,>ROW17,>ROW18,>ROW19,>ROW20,>ROW21,>ROW22
SECLEN = 224
WXMAX = 192
; maps: band type of every column, per sector * 3 + band; flags of every column per sector
; flags: 1 walkway at floor 1, 2 walkway at floor 2, 4 ladder 0-1, 8 ladder 1-2, 16 wire, 32 mine, 64 target
MAP_LO: .byte <MAP00,<MAP01,<MAP02,<MAP10,<MAP11,<MAP12,<MAP20,<MAP21,<MAP22,<MAP30,<MAP31,<MAP32
MAP_HI: .byte >MAP00,>MAP01,>MAP02,>MAP10,>MAP11,>MAP12,>MAP20,>MAP21,>MAP22,>MAP30,>MAP31,>MAP32
MAP00:
  .byte $00,$00,$01,$02,$00,$03,$04,$05,$05,$04,$06,$00,$00,$00,$00,$00,$00,$07,$08,$00,$00,$00,$00,$00,$09,$0A,$00,$00,$00,$00,$00,$0B
  .byte $0C,$0D,$00,$00,$00,$00,$00,$00,$01,$0E,$02,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0F,$0A,$00,$00,$00,$00,$00,$00,$00,$03,$04,$05
  .byte $05,$10,$11,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$0E,$02,$00,$00,$09,$0A,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$0E,$02,$00,$00,$00,$00,$00,$00,$09,$0A,$00,$00,$07,$08,$00,$00,$00,$03
  .byte $04,$05,$05,$04,$06,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$07,$12,$13,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$08,$00,$00,$00,$00,$00,$00,$00,$0B,$0C,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$07,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$09,$0A,$00,$00,$00,$00,$00,$14,$15,$16,$17,$00,$00,$00,$00,$00,$00,$00,$09,$0A,$00,$00,$00,$00,$00,$00,$00,$00
MAP01:
  .byte $00,$00,$00,$00,$00,$00,$01,$02,$03,$04,$05,$06,$07,$08,$06,$06,$06,$06,$06,$06,$06,$06,$09,$0A,$0B,$0C,$0D,$0D,$0A,$0D,$0D,$0D
  .byte $0D,$0E,$06,$06,$06,$0F,$00,$00,$00,$00,$00,$00,$05,$06,$07,$08,$06,$06,$09,$0A,$0B,$0C,$0D,$0D,$0D,$0D,$0D,$0D,$0A,$0E,$10,$11
  .byte $12,$13,$06,$06,$06,$06,$06,$0F,$00,$00,$00,$00,$05,$06,$07,$08,$06,$06,$06,$06,$09,$0A,$0B,$0C,$0D,$0D,$0D,$0D,$0A,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$14,$15,$16,$16,$16,$17,$0D,$18,$19,$06,$06,$06,$06,$06,$06,$06,$06,$09,$0A,$0B,$0C,$0D,$0D,$0D,$0D,$0A,$0E,$06,$06
  .byte $10,$11,$12,$13,$06,$0F,$00,$00,$00,$00,$00,$00,$05,$06,$07,$08,$06,$06,$09,$0A,$0B,$0C,$0D,$0D,$0D,$0D,$0D,$0D,$0A,$0D,$0D,$0D
  .byte $0D,$0E,$06,$06,$06,$06,$06,$0F,$00,$00,$00,$00,$05,$06,$06,$06,$07,$08,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $09,$0A,$0D,$0D,$0B,$0C,$0D,$0D,$0D,$0D,$1A,$1B,$1C,$1D,$1E,$1F,$0D,$0D,$0D,$0D,$0A,$0D,$20,$21,$0D,$0D,$0D,$0D,$0A,$0D,$0D,$22
MAP02:
  .byte $00,$01,$02,$01,$00,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$01
  .byte $00,$01,$02,$01,$0C,$01,$02,$01,$0D,$0E,$02,$01,$0C,$09,$0A,$0B,$00,$01,$02,$01,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$03,$04,$05
  .byte $06,$07,$0F,$01,$0C,$01,$02,$01,$00,$01,$10,$0E,$0C,$09,$0A,$0B,$00,$01,$02,$01,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$01
  .byte $00,$01,$02,$01,$0C,$01,$02,$01,$0C,$09,$0A,$0B,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$03
  .byte $04,$05,$06,$07,$08,$01,$02,$01,$0D,$0E,$02,$01,$0C,$09,$0A,$0B,$00,$01,$02,$01,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$01
  .byte $00,$01,$02,$01,$0C,$01,$02,$01,$00,$01,$10,$0E,$0C,$09,$02,$01,$0A,$0B,$02,$01,$0C,$01,$02,$01,$00,$01,$02,$01,$0C,$01,$02,$01
  .byte $00,$01,$02,$01,$0C,$01,$02,$01,$0F,$03,$11,$12,$13,$14,$15,$16,$0F,$03,$0F,$03,$08,$03,$0A,$0B,$0F,$03,$0F,$03,$08,$03,$0F,$03
MAP10:
  .byte $00,$00,$01,$0E,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$0E,$02,$00,$00
  .byte $09,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0D,$09,$0A,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$0E,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$0E,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$18
  .byte $02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$12,$08,$00,$00,$00,$00,$00,$00,$00,$00,$01,$0E,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$08,$00,$00,$00,$00,$00,$00,$00,$0B,$19,$1A,$00,$00,$00,$00,$00,$00,$07,$12,$08,$00,$00,$00,$00,$00,$00,$00,$1B,$1C,$02,$00
  .byte $00,$00,$00,$00,$00,$00,$0B,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
MAP11:
  .byte $00,$00,$00,$00,$05,$06,$07,$08,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$0F,$00,$00,$05,$06,$07,$08,$06,$06,$06,$06,$09,$0A
  .byte $0B,$0C,$0D,$0D,$0A,$0D,$0D,$14,$16,$16,$16,$17,$0A,$0E,$07,$08,$09,$0A,$0D,$0E,$06,$06,$09,$0A,$0B,$0C,$0D,$0D,$23,$16,$16,$16
  .byte $17,$0D,$18,$19,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$0F,$00,$00,$05,$06,$07,$08,$06,$06,$09,$0A,$0B,$0C
  .byte $0D,$0D,$0D,$0D,$0A,$0D,$0D,$14,$16,$16,$16,$17,$0A,$0D,$18,$24,$0D,$0D,$0D,$0E,$06,$06,$06,$06,$06,$06,$06,$06,$0F,$00,$00,$00
  .byte $05,$06,$07,$08,$06,$06,$06,$06,$09,$0A,$0B,$0C,$0A,$0D,$0D,$0D,$0D,$0D,$0D,$0E,$06,$06,$09,$23,$16,$16,$16,$17,$0B,$0C,$0D,$0D
  .byte $18,$24,$0D,$0D,$0A,$0E,$06,$06,$06,$06,$06,$06,$06,$06,$06,$0F,$00,$00,$05,$06,$07,$08,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$07,$08,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$0F
MAP12:
  .byte $17,$18,$17,$18,$19,$1A,$1B,$1C,$17,$1D,$0F,$03,$08,$03,$17,$18,$17,$18,$1E,$18,$17,$18,$19,$1A,$0A,$0B,$0F,$03,$19,$18,$17,$1D
  .byte $17,$1D,$17,$18,$19,$1D,$0F,$03,$0F,$03,$17,$1A,$19,$18,$1B,$1C,$17,$1D,$17,$1D,$08,$03,$0F,$03,$17,$1D,$17,$18,$19,$18,$17,$18
  .byte $19,$1A,$0A,$0B,$08,$03,$17,$18,$17,$18,$1E,$18,$19,$18,$17,$1D,$0F,$03,$0F,$03,$17,$18,$19,$1A,$1B,$1C,$17,$18,$19,$1D,$0F,$03
  .byte $0F,$03,$17,$18,$19,$18,$1E,$18,$17,$18,$17,$1A,$08,$03,$0A,$0B,$17,$18,$17,$18,$19,$18,$17,$18,$17,$1D,$0F,$03,$08,$03,$17,$18
  .byte $19,$1A,$1B,$1C,$19,$18,$17,$1D,$0F,$03,$0F,$03,$19,$18,$17,$18,$1E,$18,$17,$18,$19,$1D,$0F,$03,$0F,$03,$17,$1A,$19,$1D,$1E,$18
  .byte $1B,$1C,$17,$1D,$08,$03,$0F,$03,$17,$18,$17,$18,$19,$18,$17,$18,$17,$1D,$08,$1F,$0A,$0B,$17,$18,$17,$18,$1E,$18,$19,$18,$17,$1D
  .byte $0F,$03,$0F,$03,$08,$03,$0F,$03,$0A,$0B,$0F,$03,$20,$21,$22,$21,$22,$23,$22,$23,$24,$25,$22,$21,$22,$21,$22,$03,$08,$03,$0F,$03
MAP20:
  .byte $00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0D,$00,$00,$00,$00,$00,$09,$0A,$00,$00,$00,$00,$07,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$12,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0C,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$12,$08,$00,$00,$00,$00,$00,$09,$0A,$00,$00,$00,$00,$00,$00,$07,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0C,$0D,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$09,$0A,$00,$07,$12,$08,$00,$00,$00,$00,$00,$00,$0B,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $12,$08,$00,$00,$00,$00,$09,$0A,$00,$00,$00,$00,$00,$00,$0B,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0C,$0D,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$12,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$1D,$1E,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$20,$21,$1F,$1F,$1F,$1F,$22,$22
MAP21:
  .byte $00,$00,$25,$26,$26,$26,$26,$25,$05,$06,$07,$08,$06,$06,$27,$28,$28,$28,$29,$2A,$0B,$0C,$0D,$0D,$0D,$0D,$2B,$2C,$2D,$2E,$28,$27
  .byte $06,$06,$06,$0F,$00,$00,$25,$26,$2F,$28,$30,$31,$06,$06,$06,$06,$06,$06,$27,$28,$28,$28,$28,$27,$06,$06,$06,$06,$06,$06,$27,$32
  .byte $26,$26,$2F,$27,$07,$08,$09,$0A,$0B,$0C,$2B,$2C,$2D,$2C,$2C,$2B,$0D,$0D,$0D,$0D,$0A,$0E,$27,$28,$28,$32,$26,$25,$00,$00,$05,$06
  .byte $07,$08,$27,$28,$29,$2D,$33,$34,$0D,$0D,$0D,$0D,$0A,$0D,$2B,$2C,$2C,$2E,$28,$27,$06,$06,$06,$06,$06,$0F,$25,$26,$2F,$28,$30,$31
  .byte $06,$06,$06,$06,$09,$0A,$35,$36,$2C,$2C,$2C,$2B,$0A,$0D,$0D,$0E,$06,$06,$27,$28,$28,$28,$28,$37,$00,$00,$00,$00,$05,$06,$38,$39
  .byte $28,$28,$28,$27,$06,$06,$06,$06,$06,$06,$27,$28,$28,$28,$28,$27,$06,$06,$06,$06,$06,$06,$27,$32,$26,$26,$26,$25,$05,$06,$07,$08
  .byte $06,$06,$09,$0A,$3A,$3B,$3C,$3C,$3C,$3C,$3C,$3C,$3D,$3E,$3C,$3C,$3F,$40,$3C,$3C,$41,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$41,$3C,$3C,$42
MAP22:
  .byte $0F,$03,$26,$27,$26,$27,$26,$27,$28,$29,$2A,$2B,$28,$2C,$26,$27,$26,$27,$26,$27,$28,$2C,$2D,$2C,$2D,$2C,$26,$27,$2E,$27,$26,$27
  .byte $2D,$2C,$2D,$2C,$2D,$2C,$2F,$27,$2E,$30,$31,$32,$28,$2C,$2D,$2C,$2D,$2C,$26,$27,$2E,$27,$26,$27,$2D,$2C,$2D,$2C,$28,$2C,$26,$27
  .byte $2F,$27,$2E,$30,$2A,$2B,$2D,$2C,$2D,$2C,$26,$27,$2E,$27,$26,$27,$2D,$2C,$2D,$2C,$28,$2C,$26,$27,$26,$27,$26,$27,$33,$2C,$28,$29
  .byte $2A,$2B,$26,$27,$2E,$27,$26,$27,$2D,$2C,$2D,$2C,$28,$2C,$26,$27,$26,$27,$26,$27,$28,$2C,$2D,$2C,$2D,$2C,$2F,$27,$2E,$30,$31,$32
  .byte $2D,$2C,$2D,$2C,$28,$2C,$26,$27,$26,$27,$26,$27,$28,$2C,$2D,$2C,$2D,$2C,$26,$27,$2E,$27,$26,$27,$2D,$2C,$33,$2C,$28,$29,$31,$32
  .byte $26,$27,$26,$27,$28,$2C,$2D,$2C,$2D,$2C,$26,$27,$2E,$27,$26,$27,$2D,$2C,$2D,$2C,$28,$2C,$26,$27,$26,$27,$2F,$27,$28,$29,$2A,$2B
  .byte $2D,$2C,$0F,$03,$34,$35,$36,$35,$37,$38,$36,$35,$39,$3A,$36,$35,$36,$35,$36,$35,$34,$35,$36,$35,$36,$35,$36,$35,$34,$35,$36,$35
MAP30:
  .byte $23,$24,$00,$00,$25,$25,$00,$00,$26,$27,$28,$00,$29,$2A,$00,$2B,$09,$0A,$2C,$00,$2D,$2E,$2F,$00,$00,$30,$31,$00,$00,$00,$00,$32
  .byte $00,$23,$33,$34,$25,$00,$34,$35,$27,$36,$37,$0A,$00,$00,$24,$00,$2E,$24,$38,$00,$00,$00,$00,$00,$25,$32,$00,$39,$28,$00,$3A,$00
  .byte $34,$38,$00,$2A,$2D,$27,$3B,$3C,$00,$00,$3D,$00,$00,$3E,$24,$00,$3F,$00,$00,$38,$00,$40,$41,$42,$00,$00,$43,$23,$00,$44,$2E,$43
  .byte $00,$45,$46,$00,$41,$00,$47,$2E,$09,$0A,$38,$48,$34,$00,$00,$49,$00,$4A,$00,$27,$00,$00,$4B,$00,$4C,$00,$32,$2D,$4D,$4E,$00,$00
  .byte $00,$27,$09,$4F,$50,$00,$51,$00,$52,$33,$41,$53,$00,$54,$55,$00,$00,$00,$56,$57,$00,$43,$58,$00,$00,$24,$41,$00,$2A,$59,$24,$00
  .byte $00,$2A,$00,$2D,$24,$2F,$00,$00,$34,$00,$27,$47,$38,$5A,$28,$00,$2F,$00,$00,$25,$00,$00,$3E,$5B,$5C,$43,$5D,$00,$28,$00,$48,$00
  .byte $09,$5E,$5F,$60,$61,$60,$62,$60,$63,$60,$64,$65,$66,$63,$60,$60,$60,$60,$67,$5F,$60,$60,$68,$69,$64,$60,$60,$60,$6A,$6B,$60,$60
MAP31:
  .byte $43,$44,$45,$46,$47,$43,$48,$49,$07,$08,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$0D,$0A,$0D,$52,$52,$52,$53,$52,$52,$4F,$54,$00,$00
  .byte $00,$43,$48,$49,$55,$56,$49,$49,$57,$0A,$0B,$0C,$58,$59,$5A,$5B,$5C,$5C,$5C,$5D,$4A,$5E,$06,$4B,$4B,$5F,$60,$61,$62,$63,$64,$65
  .byte $07,$66,$4B,$4B,$4E,$4F,$50,$51,$52,$67,$68,$69,$0A,$6A,$52,$52,$6B,$6A,$52,$52,$4F,$0D,$0D,$0D,$5C,$6C,$6D,$6E,$6F,$70,$71,$43
  .byte $05,$06,$07,$56,$49,$49,$57,$58,$72,$73,$5C,$74,$0A,$0D,$52,$52,$52,$75,$4B,$4B,$76,$4B,$4A,$0F,$77,$78,$78,$78,$79,$7A,$7B,$7C
  .byte $7D,$0A,$0B,$0C,$7E,$7F,$7F,$80,$7F,$81,$82,$7F,$0A,$0D,$0D,$52,$52,$52,$53,$52,$4F,$83,$84,$16,$16,$85,$43,$44,$45,$46,$48,$49
  .byte $55,$56,$06,$06,$06,$4B,$4B,$4B,$86,$4B,$87,$88,$89,$06,$65,$06,$4B,$4B,$4B,$86,$4B,$4B,$4B,$5F,$00,$8A,$8B,$06,$07,$8C,$09,$0A
  .byte $0B,$0C,$5C,$5C,$58,$5C,$5C,$5C,$5C,$5C,$8D,$8E,$58,$5C,$8F,$90,$5C,$5C,$5C,$5C,$58,$5C,$5C,$5C,$5C,$5C,$5C,$5C,$58,$5C,$5C,$91
MAP32:
  .byte $3B,$3C,$3B,$3C,$3B,$3C,$3D,$3E,$0A,$0B,$0F,$3C,$3D,$3C,$3B,$3C,$3B,$3C,$3B,$03,$08,$03,$3B,$3C,$3B,$3C,$3B,$3C,$3D,$3C,$0F,$03
  .byte $3F,$40,$3D,$3E,$41,$42,$3B,$3C,$3B,$03,$0F,$03,$3D,$3C,$3B,$3C,$3B,$3C,$3B,$3C,$08,$03,$0F,$3C,$3B,$3C,$3B,$3C,$43,$3C,$3D,$1F
  .byte $0A,$0B,$3B,$3C,$3D,$3C,$3B,$3C,$3B,$3C,$0F,$03,$08,$3C,$3B,$3C,$3B,$3C,$3B,$3C,$3D,$03,$0F,$03,$3B,$3C,$3B,$3C,$3D,$3C,$43,$3C
  .byte $08,$1F,$0A,$42,$3D,$3C,$3B,$3C,$3B,$3C,$3B,$03,$08,$03,$3B,$3C,$3B,$3C,$3B,$3C,$3D,$3C,$0F,$03,$0F,$3C,$44,$45,$3D,$3E,$41,$42
  .byte $3B,$03,$0F,$03,$3D,$46,$47,$3C,$3B,$3C,$3B,$3C,$08,$03,$0F,$3C,$3B,$3C,$3B,$3C,$3D,$3C,$3B,$03,$0F,$03,$48,$40,$3B,$3C,$3D,$3E
  .byte $41,$42,$0F,$03,$08,$3C,$3B,$3C,$3B,$3C,$3B,$3C,$3D,$03,$0F,$03,$3B,$3C,$3B,$3C,$3D,$3C,$3B,$3C,$49,$03,$08,$1F,$0A,$0B,$0F,$03
  .byte $0F,$03,$3B,$3C,$3D,$3C,$4A,$4B,$3B,$3C,$41,$42,$3D,$3C,$3B,$3C,$3B,$3C,$3B,$3C,$3D,$3C,$3B,$3C,$3B,$3C,$3B,$3C,$4C,$4B,$3B,$3C
FLG_LO: .byte <FLG0,<FLG1,<FLG2,<FLG3
FLG_HI: .byte >FLG0,>FLG1,>FLG2,>FLG3
FLG0:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$01,$01,$01,$01,$00,$00,$10,$10,$00,$00,$01,$01,$05,$05,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$10,$10,$01,$01,$05,$05,$01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$02,$02,$02,$02,$03,$03,$07,$07,$01,$01,$01,$01,$01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$00,$00,$10,$10,$00,$00,$01,$01,$05,$05,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$01,$01,$01,$01,$01,$01,$00,$00,$10,$10,$01,$01,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $03,$03,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$43,$43,$03,$03,$03,$03,$03,$03,$03,$03,$0F,$0F,$03,$03,$03,$03,$03,$03,$03,$03
FLG1:
  .byte $00,$00,$00,$00,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$01,$01,$05,$05,$01,$01,$01,$01,$03,$03
  .byte $0B,$0B,$03,$03,$03,$03,$03,$03,$02,$02,$02,$03,$03,$03,$05,$05,$03,$03,$03,$03,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$02,$02,$02
  .byte $03,$03,$07,$07,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$01,$01,$05,$05,$01,$01,$03,$03,$0B,$0B
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$03,$03,$03,$07,$07,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00
  .byte $01,$01,$05,$05,$01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$03,$03,$02,$02,$02,$03,$0B,$0B,$03,$03
  .byte $07,$07,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$41,$41,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
FLG2:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01
  .byte $01,$01,$01,$01,$00,$00,$20,$00,$01,$01,$05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $20,$00,$01,$01,$05,$05,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$00,$00,$20,$00,$01,$01
  .byte $05,$05,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01,$20,$00,$01,$01,$05,$05
  .byte $01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$20,$00,$01,$01,$05,$05
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$20,$00,$01,$01,$05,$05
  .byte $01,$01,$03,$03,$0B,$0B,$03,$03,$43,$43,$03,$03,$07,$07,$03,$03,$43,$43,$03,$03,$03,$03,$03,$03,$43,$43,$03,$03,$03,$03,$03,$03
FLG3:
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$05,$05,$01,$01,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$00,$00
  .byte $10,$10,$01,$01,$05,$05,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$00,$00,$20,$00,$01,$01
  .byte $05,$05,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$20,$00
  .byte $01,$01,$05,$05,$01,$01,$03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$00,$00,$20,$00,$01,$01,$05,$05
  .byte $03,$03,$0B,$0B,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$10,$10,$00,$00,$01,$01
  .byte $05,$05,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$20,$00,$01,$01,$05,$05,$03,$03
  .byte $0B,$0B,$03,$03,$03,$03,$43,$43,$03,$03,$07,$07,$03,$03,$43,$43,$03,$03,$03,$03,$03,$03,$43,$43,$03,$03,$03,$03,$43,$43,$03,$03
; spawns: column, kind, floor (end: $FF)
SPAWN0:
  .byte $10,$02,$00,$1E,$02,$01,$30,$03,$00,$3C,$07,$01,$46,$02,$02
  .byte $58,$03,$01,$60,$02,$00,$6E,$07,$00,$7C,$03,$02,$96,$02,$01
  .byte $9E,$03,$00,$B4,$07,$00,$C8,$02,$01,$CE,$03,$02,$FF
SPAWN1:
  .byte $14,$02,$00,$22,$04,$01,$2C,$06,$00,$3A,$02,$02,$48,$05,$00
  .byte $54,$07,$01,$60,$04,$00,$74,$03,$02,$7E,$06,$00,$8C,$05,$01
  .byte $A2,$07,$00,$AE,$04,$01,$C0,$03,$00,$C8,$06,$00,$FF
SPAWN2:
  .byte $16,$08,$01,$1E,$02,$00,$2E,$03,$01,$3A,$08,$00,$4C,$07,$02
  .byte $54,$04,$01,$64,$08,$01,$70,$05,$00,$82,$03,$02,$8E,$08,$00
  .byte $A0,$07,$01,$AA,$04,$00,$B8,$08,$01,$C6,$02,$00,$D2,$03,$02
  .byte $FF
SPAWN3:
  .byte $12,$03,$00,$1A,$06,$01,$28,$05,$00,$32,$04,$02,$42,$07,$00
  .byte $4C,$03,$01,$56,$06,$02,$64,$05,$00,$6E,$04,$01,$84,$07,$02
  .byte $8C,$03,$00,$96,$06,$01,$A8,$05,$00,$B4,$04,$01,$C4,$03,$00
  .byte $CC,$06,$02,$FF
SPN_LO: .byte <SPAWN0,<SPAWN1,<SPAWN2,<SPAWN3
SPN_HI: .byte >SPAWN0,>SPAWN1,>SPAWN2,>SPAWN3
; targets: count, then 4 x (column, floor)
TG_N: .byte 3,1,3,4
TG_C:
  .byte $CC,$CC,$CC,$00
  .byte $D4,$00,$00,$00
  .byte $C8,$D0,$D8,$00
  .byte $C6,$CE,$D6,$DC
TG_F:
  .byte $00,$01,$02,$00
  .byte $00,$00,$00,$00
  .byte $00,$01,$02,$00
  .byte $00,$01,$02,$00

; big letters of the title from 96 (third 0): yellow SPECIAL, white FORCES
BIG_P:
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
BIG_C:
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $A0,$A0,$A0,$A0,$60,$60,$60,$60,$A0,$A0,$A0,$A0,$60,$60,$60,$60
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$F0,$F0
BIG_LEN = 640
TXT_BIG:
  .byte 3,9,96,97,100,101,104,105,108,109,112,113,116,117,120,121,0
  .byte 4,9,98,99,102,103,106,107,110,111,114,115,118,119,122,123,0
  .byte 6,10,164,165,168,169,172,173,148,149,144,145,136,137,0
  .byte 7,10,166,167,170,171,174,175,150,151,146,147,138,139,0
  .byte $FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$18,$1C,$21,$28,$32,$45,$23,$18,$23,$18,$23,$47,$47,$47,$38
  .byte $38,$38,$2F,$2F,$2F,$24,$24,$24,$28,$28,$28,$28,$00,$00,$00,$28
  .byte $28,$28,$28,$1E,$1E,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$20,$21
  .byte $23,$25,$27,$29,$2C,$2F,$32,$36,$3B,$40,$47,$4F,$59,$45,$49,$4D
  .byte $51,$4C,$50,$54,$59,$69,$6E,$74,$7A,$73,$79,$7F,$86,$9E,$A6,$AF
  .byte $B8,$AD,$B6,$C0,$CA,$EE,$FA,$08,$15,$05,$12,$21,$30,$66,$79,$8D
  .byte $A2,$3C,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$2F,$00,$00,$28
  .byte $28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$9F,$9F
  .byte $9F,$9F,$9F,$9F,$9F,$9F,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$B3,$B3
  .byte $B3,$B3,$B3,$B3,$B3,$B3,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5
  .byte $D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$24,$24
  .byte $24,$68,$61,$5A,$55,$50,$4B,$47,$44,$40,$3E,$3B,$38,$36,$34,$68
  .byte $61,$5A,$55,$50,$4B,$47,$44,$40,$3E,$3B,$38,$36,$34
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$09,$08,$07,$05,$04,$03,$0C,$0B,$0A,$09,$08,$0C,$0B,$09,$0C
  .byte $0B,$09,$0C,$0B,$09,$0C,$0B,$09,$0C,$0B,$0B,$0A,$00,$00,$00,$0C
  .byte $0B,$0B,$0A,$0A,$08,$08,$08,$08,$08,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0D,$0D,$0D
  .byte $0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05
  .byte $05,$0D,$0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$0D
  .byte $0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$08,$07,$05,$04,$0C,$0B
  .byte $0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B
  .byte $0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A
  .byte $09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$0C,$0A
  .byte $08,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $0B,$0A,$0A,$09,$09,$09,$08,$08,$08,$07,$07,$06,$06
WH_START:
  .byte $00,$01,$07,$0C,$18,$23,$25,$3D,$61,$7E,$AE,$B1
WH_LEN:
  .byte $00,$06,$05,$0C,$0B,$02,$18,$24,$1D,$30,$03,$1C
W_KNIFE = 1
W_CLANK = 2
W_PICK = 3
W_PLANT = 4
W_TICK = 5
W_MORT = 6
W_DIE = 7
W_EXTRA = 8
W_OVER = 9
W_BONUS = 10
W_ALARM = 11

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$0B,$09,$07,$05,$03,$01,$00
  .byte $00,$0D,$0A,$07,$04,$0C,$0A,$08,$06,$04,$02,$0E,$0E,$0D,$0D,$0C
  .byte $0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04
  .byte $04
EX_NP:
  .byte $00,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15
  .byte $15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17
  .byte $17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19,$19,$19
  .byte $19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $0E,$03,$03,$03,$03,$06,$07,$08,$09,$0A,$0B,$10,$10,$10,$10,$11
  .byte $11,$11,$11,$12,$12,$12,$12,$13,$13,$13,$13,$14,$14,$14,$14,$15
  .byte $15
EX_VC:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$00,$00,$00,$00,$0C,$0A,$08,$06,$04,$02,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0C,$0B,$0B,$0A
  .byte $0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02
  .byte $02
EX_TL:
  .byte $00,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$B6,$B6,$B6,$B6,$B6,$B6,$B6
  .byte $B6,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7D,$B6,$7D,$B6,$7D
  .byte $B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D
  .byte $B6
EX_TH:
  .byte $00,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$02,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02
EX_START:
  .byte $00,$01,$39,$41,$45,$4B
EX_LEN:
  .byte $00,$38,$08,$04,$06,$16
S_BIG = 1
S_HIT = 2
S_GUN = 3
S_SHOT = 4
S_BOOM = 5
S_SMALL = S_SHOT

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <40,>40, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$60, <40,>40, <SMALL_COL,>SMALL_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <40,>40, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$68, <40,>40, <SMALL_COL,>SMALL_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <40,>40, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$70, <40,>40, <SMALL_COL,>SMALL_COL
  .byte 0
TILE_LOAD:
  .byte 3, $00,$60, <8,>8, <ZERO8,>ZERO8
  .byte 1, $40,$40, <192,>192, <GT0_PLO,>GT0_PLO
  .byte 3, $40,$60, <192,>192, <GT0_CLO,>GT0_CLO
  .byte 1, $00,$43, <120,>120, <GT0_PHI,>GT0_PHI
  .byte 3, $00,$63, <120,>120, <GT0_CHI,>GT0_CHI
  .byte 3, $00,$68, <8,>8, <ZERO8,>ZERO8
  .byte 1, $40,$48, <192,>192, <GT1_PLO,>GT1_PLO
  .byte 3, $40,$68, <192,>192, <GT1_CLO,>GT1_CLO
  .byte 1, $00,$4B, <376,>376, <GT1_PHI,>GT1_PHI
  .byte 3, $00,$6B, <376,>376, <GT1_CHI,>GT1_CHI
  .byte 3, $00,$70, <8,>8, <ZERO8,>ZERO8
  .byte 1, $40,$50, <192,>192, <GT2_PLO,>GT2_PLO
  .byte 3, $40,$70, <192,>192, <GT2_CLO,>GT2_CLO
  .byte 1, $00,$53, <448,>448, <GT2_PHI,>GT2_PHI
  .byte 3, $00,$73, <448,>448, <GT2_CHI,>GT2_CHI
  .byte 0

; sector names
TXT_S0:
  .byte 11,11,"PERIMETER",0
  .byte $FF
TXT_S1:
  .byte 11,12,"BARRACKS",0
  .byte $FF
TXT_S2:
  .byte 11,11,"FUEL DEPOT",0
  .byte $FF
TXT_S3:
  .byte 11,9,"COMMAND BUNKER",0
  .byte $FF
