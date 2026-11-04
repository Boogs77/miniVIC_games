;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   CORE RUNNER  -  an original space run and platform game    ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: special forces (VDP, NMI + trampoline $0FD0, AY      ;
;   engine, 2 players taking turns)                            ;
;                                                              ;
;   - a salvage runner visits the mining stations taken by     ;
;     rogue drones. Every station has two parts:               ;
;     1. the approach: the shuttle flies right over a star     ;
;        field, shoots rocks, fighters, gunships and mines,    ;
;        then slips into the docking bay of the station (the   ;
;        bay goes up and down; touching the hull = crash)      ;
;     2. the station: 3 fixed rooms; run, jump and climb to    ;
;        the energy core, touch it (overload) and run back to  ;
;        the hatch of the shuttle before the countdown ends    ;
;   - in the station: drones, jumpers, sparks, turrets and     ;
;     spiders; conveyors, lifts, electric arcs, presses and    ;
;     crumbling floors; the oxygen goes down all the time      ;
;     (bottles fill it up), crystals are worth 500             ;
;   - joystick: left / right = run, button 1 = jump (higher    ;
;     while held), up / down = ladders, button 2 = stunner     ;
;     (3 charges per room, a drone stops for 3 seconds);       ;
;     in space: 8 directions, button 1 = cannon                ;
;   - points: rock 50, fighter 100, mine 150, gunship 200,     ;
;     docking 1000, crystal 500, core 2000, escape 3000 +      ;
;     seconds x 50 + oxygen x 10; 3 lives, one more at 20000   ;
;     and every 50000; 1 or 2 players taking turns             ;
;   - 8 stations, then again with faster drones                ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes, cannon, jump, stunner, pickups, docking, core     ;
;     alarm, crumbling floors, explosions                      ;
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
STATION     = $40      ; ---- block of the player, saved: station 0-7
LOOPN       = $41      ;      times round the 8 stations
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
PHASE       = $43      ;      0 = space, 1 = inside the station
ROOM        = $44      ;      room 0-2
ENTX        = $45      ;      where the runner came into the room (start after a life lost)
ENTY        = $46
ESC         = $47      ;      1 = the core is overloaded: run back to the hatch
FRESH       = $48      ;      1 = a new station (the intro and the tune)
TAKEN       = $49      ;      3 bytes: pickups taken in every room (bits)
PBLOCK      = 12
DIFF        = $4C      ; difficulty 0-15
GSTATE      = $4D      ; 0 playing, 1 lost, 2 docking, 3 escaped
GT          = $4E      ; timer of GSTATE
JOYC        = $4F      ; both joysticks drive the player playing
JOYP        = $50      ; JOYC of the frame before
HUDD        = $51      ; 1 = the HUD changed
FIRSTT      = $52      ; 1 = first turn of the game
SHOWP       = $53      ; 1 = the intro before the station
GF          = $54      ; frames of play
OXY         = $55      ; oxygen 0-96
OXT         = $56      ; frames to the next unit of oxygen less
TIMEL       = $57      ; countdown of the core (BCD seconds)
TSUB        = $58      ; frames into the second
STUNC       = $59      ; stunner charges left
HZON        = $5A      ; bit 0 = arcs of phase 0 on, bit 1 = presses of phase 0 on
HZT         = $5B      ; hazard clock
CRUMT       = $5C      ; frames on the same crumbling cell
CRUMA       = $5D      ; 2 bytes: map address of that cell
APEX        = $5F      ; highest point of the jump (feet)
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
CLIMB       = $73      ; 1 = the runner is on a ladder
CNT         = $74
BONL        = $75      ; bonus (BCD)
BONH        = $76
SONG        = $77      ; tune to play
DISTL       = $78      ; space: frames flown (16 bits)
DISTH       = $79
SPAWNT      = $7A      ; space: frames to the next enemy
PORTY       = $7B      ; space: first row inside the bay (screen row)
HULLC       = $7C      ; space: first column of the hull (32 = no hull)
FIRET       = $7D      ; frames before the next shot
PORTD       = $7E      ; bay: 0 down, 1 up
PORTT       = $7F      ; frames to the next step of the bay
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
ANIMP       = $87      ; phase of the animated tiles
CX          = $88      ; new object: x / y
CY          = $89
HXI         = $8A      ; runner: x and feet (integers, copies for the checks)
HYI         = $8B
CELLP       = $8C      ; 2 bytes: map row of CLS_AT
CCOL        = $8E      ; column of CLS_AT
OYI         = $8F      ; old feet in the air
BARV        = $90      ; value of the bar on the screen ($FF = draw it again)
NPICK       = $91      ; pickups of the room
WAVEN       = $92      ; fighters still to come in the wave
WAVEY       = $93      ; their base row
SPHASE      = $94      ; space: 0 flight, 1 the station comes, 2 bay moving
DEATH       = $95      ; why the runner was lost (for the tests): 1 touch, 2 hazard, 3 fall, 4 oxygen, 5 time, 6 crash
ALRT        = $96      ; frames to the next beep of the alarm
OXRATE      = $97      ; frames per unit of oxygen
SPDB        = $98      ; speed bonus of the enemies (fraction)
DX          = $99      ; 2 bytes: sideways step of the runner (8.8)
CCLS        = $9B      ; class found by the checks
TT          = $9C      ; temporary of the checks
RR          = $9D      ; first object in the SAT (turns, 1-13)

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

; ---------------- objects: slot 0 = runner / shuttle, 1-13 the rest (16 bytes per field)
NOB        = 14
O_K        = $0200       ; kind (K_*, 0 = free)
O_X        = $0210       ; x on the screen (8.8: integer)
O_XL       = $0220       ;                  fraction
O_Y        = $0230       ; feet
O_YL       = $0240
O_VY       = $0250       ; vertical speed 8.8 (down = positive)
O_VYL      = $0260
O_VX       = $0270       ; horizontal speed 8.8
O_VXL      = $0280
O_D        = $0290       ; facing: 0 right, 1 left
O_AIR      = $02A0       ; 1 = in the air
O_T        = $02B0       ; timer
O_S        = $02C0       ; frames still stunned
O_H        = $02D0       ; hits left
O_A        = $02E0       ; animation
O_P        = $02F0       ; spider: lowest feet; fighter: base row
O_Y0       = $0300       ; spider: highest feet

K_HERO     = 1
K_DRONE    = 2           ; 2-6: the enemies of the rooms (list kind + 1)
K_JUMPER   = 3
K_SPARK    = 4
K_TURRET   = 5
K_SPIDER   = 6
K_BOLT     = 7           ; turret shot (falls)
K_ZAP      = 8           ; stunner
K_SHIP     = 9
K_ROCK     = 10          ; 10-13: the enemies in space
K_FIGHTER  = 11
K_GUNSHIP  = 12
K_MINE     = 13
K_SHOT     = 14          ; cannon of the shuttle
K_EBOLT    = 15          ; shot of a gunship
K_BOOM     = 16

; tile classes (cn_phys.js has the same numbers)
CL_EMPTY   = 0
CL_SOLID   = 1
CL_LADDER  = 2
CL_CONVL   = 3
CL_CONVR   = 4
CL_LIFT    = 5
CL_HAZA0   = 6
CL_CRUMB   = 10
CL_CORE    = 11
CL_HATCH   = 12
CL_OXY     = 13
CL_CRYS    = 14

SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
MAP        = $0800       ; the room: 21 rows x 32 tile ids (rows 2-22 of the screen)
STARS      = $0B00       ; space: row, column, step, layer of 24 stars
PICKA      = $0B80       ; addresses of the pickups of the room (lo 8, hi 8)
XLAT       = $0C00       ; material colours -> colours of the station
PSAVE      = $0D00       ; 2 x 16: block of every player

; ---------------- parameters ----------------
BTN_MASK    = %00110000

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 26           ; fixed zone of the game in the save area
REC_RAM     = $7C00        ; $2A0 bytes of free RAM
REC_ROW     = 9            ; table header on this row of the title, rows +1..+8 the table
REC_WIPEN   = 11           ; rows of the title that give way to the table
REC_JOY2    = $FF          ; $FF = both joysticks sign, 0 = the player's own
REC_SROW    = REC_ROW      ; table header on the sign screen
RUN_SP      = $80        ; runner: 1.5 pixels per frame (fraction; the integer is 1)
JUMP_V      = $FCC0      ; -3.25
G_HOLD      = $28        ; gravity going up with the button held
G_UP        = $50        ;                    without the button
G_FALL      = $40        ;           coming down
LIFT_A      = $30        ; push of a lift
FALL_MAX    = 88         ; a longer fall is fatal
NSTAR       = 24
DIST_END    = 1500       ; frames of flight before the station comes (25 seconds)

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
  STA HOFF
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  DEX
  BPL .rs_p
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_HISC
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
  JSR SET_BLACK0
  JSR CLEAR_NT
  LDA #$00                     ; big letters over the station tiles of third 0
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
  JSR TITLE_PAGE
  JSR REC_TITLE
  LDA #2                       ; the title tune
  STA SONG
  LDA #CMD_START
  STA SND_CMD
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
  LDA #CMD_GAME
  STA SND_CMD
  JMP NEW_GAME

; rows 9-19 of the title and the sprites beside them (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the runner, the stunner and the enemies (sprites)
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
  RTS

; one frame of the title: the runner runs on the spot, the others move
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR REC_TICK                 ; every 5 s the title page and the table take turns
  BCC .tf_a
  LDA REC_PG
  BEQ .tf_p
  JSR HIDE_SPRITES
  JSR REC_SHOW
  BRA .tf_a
.tf_p:
  JSR TITLE_PAGE
.tf_a:
  LDA FRAME_CNT
  AND #$08                     ; 0 or 8: the two steps
  CLC
  ADC #PT_RUN
  STA SAT_BUFFER+2
  LDA FRAME_CNT
  AND #$10
  LSR A
  LSR A                        ; 0 or 4: the second pattern
  STA T0
  LDA #PT_FIGHTER
  CLC
  ADC T0
  STA SAT_BUFFER+10
  LDA #PT_MINE
  CLC
  ADC T0
  STA SAT_BUFFER+18
  LDA #PT_DRONE
  CLC
  ADC T0
  STA SAT_BUFFER+22
  LDA #PT_SPARK
  CLC
  ADC T0
  STA SAT_BUFFER+26
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: station 1, 3 lives for every player
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
  STZ STATION
  STZ LOOPN
  STZ PHASE
  STZ ESC
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
;  TURN OF A PLAYER, then the space flight or the station
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE STAGE_START
  INC SHOWP

STAGE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$01
  JSR SET_BACKDROP
  JSR SET_STATION
  LDA FRESH
  BEQ .ss_old
  INC SHOWP                    ; a new station: the intro
  STZ PHASE
  STZ ESC
  STZ ROOM
  STZ TAKEN
  STZ TAKEN+1
  STZ TAKEN+2
.ss_old:
  LDA SHOWP
  BEQ .ss_go
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT                   ; the tune: first turn or a new station
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
.ss_go:
  STZ SHOWP
  STZ FRESH
  STZ GSTATE
  LDA #CMD_GAME
  STA SND_CMD
  LDX #NOB-1
.ss_o:
  STZ O_K,X
  DEX
  BPL .ss_o
  LDA PHASE
  BNE .ss_room
  JSR SPACE_START
  BRA .ss_on
.ss_room:
  JSR STATION_START
.ss_on:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #30
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
  INC GF
  LDA PHASE
  BNE .gl_room
  JSR SPACE_FRAME
  BRA .gl_hud
.gl_room:
  JSR ROOM_FRAME
.gl_hud:
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  CMP #2
  BEQ .gl_dock
  CMP #3
  BEQ .gl_esc
  DEC GT                       ; lost: the explosion and the fall go on
  BNE GAME_LOOP
  JMP LOSE_LIFE
.gl_dock:
  DEC GT
  BNE GAME_LOOP
  JMP DOCKED
.gl_esc:
  JMP STATION_CLEAR

; A = backdrop colour (R7)
SET_BACKDROP:
  STA VREG
  LDA #(VDP_REGISTER_BITS | 7)
  STA VREG
  RTS

; the shuttle is in the bay: into the station
DOCKED:
  LDA #1
  STA PHASE
  STZ ROOM
  STZ ESC
  LDA #28                      ; just out of the hatch
  STA ENTX
  LDA #176
  STA ENTY
  JSR SAVE_PLAYER
  JMP STAGE_START


; ===============================================================
;  THE STATION BLOWS UP: the shuttle flies away, then the bonus
; ===============================================================
STATION_CLEAR:
  JSR VDP_INT_OFF
  LDX #NOB-1
.sc_e:
  STZ O_K,X
  DEX
  BPL .sc_e
  JSR SPACE_VIEW               ; stars and the hull with the bay
  LDA #K_SHIP                  ; the shuttle comes out of the bay
  STA O_K
  LDA HULLC
  ASL A
  ASL A
  ASL A
  CLC
  ADC #12
  STA O_X
  LDA PORTY
  ASL A
  ASL A
  ASL A
  CLC
  ADC #20
  STA O_Y
  LDA #W_LAUNCH
  LDX #2
  JSR SFX_WHISTLE
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #150
  STA GT
.sc_fly:                       ; 150 frames: the shuttle flies left, explosions on the hull
  JSR VDP_INT_OFF
  JSR NEXT_RND
  LDA O_X
  CMP #20
  BCC .sc_x
  DEC O_X
  DEC O_X
.sc_x:
  JSR MOVE_STARS
  LDA GT
  CMP #120
  BCS .sc_nb
  AND #3                       ; the backdrop flashes
  BNE .sc_nb
  LDA GT
  AND #4
  BEQ .sc_k
  LDA #$0F
.sc_k:
  ORA #$01
  JSR SET_BACKDROP
  LDA GT
  AND #7
  BNE .sc_nb
  JSR HULL_BOOM
.sc_nb:
  JSR UPDATE_BOOMS
  JSR BUILD_SAT
  JSR VDP_INT_ON
  JSR WAIT_FRAME
  DEC GT
  BNE .sc_fly
  JSR VDP_INT_OFF
  LDA #$01
  JSR SET_BACKDROP
  LDX #NOB-1
.sc_c:
  STZ O_K,X
  DEX
  BPL .sc_c
  JSR BUILD_SAT
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
  LDA #60
  JSR WAIT_FRAMES
  ; ---- bonus: 3000 + seconds x 50 + oxygen x 10
  LDA #$00
  STA BONL
  LDA #$30
  STA BONH
  LDA TIMEL                    ; seconds (BCD) -> binary in X
  JSR BCD2BIN
  TAX
  BEQ .sc_o
.sc_s:
  SED
  LDA BONL
  CLC
  ADC #$50
  STA BONL
  LDA BONH
  ADC #0
  STA BONH
  CLD
  DEX
  BNE .sc_s
.sc_o:
  LDX OXY
  BEQ .sc_p
.sc_ox:
  SED
  LDA BONL
  CLC
  ADC #$10
  STA BONL
  LDA BONH
  ADC #0
  STA BONH
  CLD
  DEX
  BNE .sc_ox
.sc_p:
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
.sc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sc_t
  LDA #60
  JSR WAIT_FRAMES
  LDA #1                       ; the next station
  STA FRESH
  STZ PHASE
  STZ ESC
  INC STATION
  LDA STATION
  CMP #N_STATIONS
  BCC .sc_n
  STZ STATION
  INC LOOPN
.sc_n:
  JSR SAVE_PLAYER
  JMP STAGE_START

; A = BCD (0-99) -> A = binary
BCD2BIN:
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  STA T0
  ASL A
  ASL A
  ADC T0                       ; tens x 5
  ASL A                        ; tens x 10
  STA T0
  PLA
  AND #$0F
  CLC
  ADC T0
  RTS

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
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  LDX #$00                     ; every player: into the table of the records?
.go_r:
  STX REC_PL
  LDA SCL,X
  STA REC_SC
  LDA SCM,X
  STA REC_SC+1
  LDA SCH,X
  STA REC_SC+2
  STZ REC_SC+3
  TXA                          ; extra byte: the station reached (8 a round, from 1)
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE+1,Y
  ASL A
  ASL A
  ASL A
  SEC
  ADC PSAVE,Y
  STA REC_EX
  JSR REC_CHECK
  LDX REC_PL
  INX
  CPX NPL
  BNE .go_r
  JSR REC_SAVE                 ; one write on the SD
  JSR REC_HISC
  JMP TITLE

; the best row of the table is the record on the HUD
REC_HISC:
  LDA REC_TAB
  STA HISC
  LDA REC_TAB+1
  STA HISC+1
  LDA REC_TAB+2
  STA HISC+2
  RTS

; hooks of lib_records.asm
REC_XY = NT_XY
REC_CLS:                       ; the sign screen: empty, with the scores on top
  JSR SET_BLACK0
  JSR CLEAR_NT
  JMP DRAW_TOP
REC_SND:                       ; A = 0 a letter, 1 the initials confirmed
  PHX
  LDX #2
  CMP #0
  BNE .rn_s
  LDA #W_KEY
  BRA .rn_p
.rn_s:
  LDA #W_PICK
.rn_p:
  JSR SFX_WHISTLE
  PLX
  RTS
REC_NAME:  .byte "CORE RUNNER     "
REC_HEAD:  .byte "BEST RUNNERS",0
REC_XLBL:  .byte "STATION ",0


; ===============================================================
;  INTRO: player, station number and name, what is in it
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
  LDA #<TXT_STATION
  STA TP
  LDA #>TXT_STATION
  STA TP+1
  JSR PRINT
  LDA STATION
  CLC
  ADC #$31
  STA VDATA
  LDX STATION
  LDA SNAME_LO,X
  STA TP
  LDA SNAME_HI,X
  STA TP+1
  JSR PRINT
  LDX STATION
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

; difficulty, oxygen rate, enemy speed and the colours of the station (XLAT)
SET_STATION:
  LDA LOOPN                    ; difficulty: station + 8 per time round, at most 15
  ASL A
  ASL A
  ASL A
  CLC
  ADC STATION
  CMP #16
  BCC .st_d
  LDA #15
.st_d:
  STA DIFF
  ASL A                        ; enemies: + difficulty x 8 / 256 pixels per frame
  ASL A
  ASL A
  STA SPDB
  LDA #40                      ; oxygen: a unit every 40 - difficulty frames
  SEC
  SBC DIFF
  STA OXRATE
  LDA STATION                  ; XLAT[m] = palette[m >> 4] << 4 | palette[m & 15]
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0                       ; palette of the station: WPAL + station * 16
  LDX #0
.st_x:
  TXA
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC T0
  TAY
  LDA WPAL,Y
  ASL A
  ASL A
  ASL A
  ASL A
  STA T2
  TXA
  AND #$0F
  CLC
  ADC T0
  TAY
  LDA WPAL,Y
  ORA T2
  STA XLAT,X
  INX
  BNE .st_x
  RTS


; ===============================================================
;  HUD: scores on rows 0-1; station, lives, stunner, bar, core
;  countdown on row 23
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

; row 23: S + station, spare lives, stunner charges, oxygen / distance, countdown
DRAW_BOTTOM:
  LDX #23
  LDY #0
  JSR NT_XY
  LDA #'S'
  STA VDATA
  LDA STATION
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
  LDA PHASE                    ; stunner and its charges (station only)
  BEQ .db_ns
  LDA #T_STUN
  STA VDATA
  LDA STUNC
  ORA #$30
  STA VDATA
  LDA #$20
  STA VDATA
  LDA #T_OXY2
  BRA .db_ic
.db_ns:
  LDA #$20
  STA VDATA
  STA VDATA
  STA VDATA
  LDA #T_SHIPI
.db_ic:
  STA VDATA
  LDA #$FF                     ; the bar is drawn by UPDATE_BAR
  STA BARV
  LDX #23
  LDY #25
  JSR NT_XY
  LDA ESC
  BEQ .db_ne
  LDA PHASE
  BEQ .db_ne
  LDY #0
.db_t:
  LDA TXT_CORE,Y
  BEQ .db_te
  STA VDATA
  INY
  BRA .db_t
.db_te:
  LDA TIMEL
  JMP PUT_2
.db_ne:
  LDY #7
  LDA #$20
.db_sp:
  STA VDATA
  DEY
  BNE .db_sp
  RTS

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_b
  STZ HUDD
  LDX CURP
  JSR DRAW_SCORE
  JSR DRAW_BOTTOM
.uh_b:
  ; fall into UPDATE_BAR

; the bar of row 23 (columns 12-23): oxygen in the station, distance in space
UPDATE_BAR:
  LDA PHASE
  BEQ .ub_d
  LDA OXY
  BRA .ub_v
.ub_d:
  LDA DISTH                    ; distance x 96 / 1500 ~ DIST / 16
  STA T0
  LDA DISTL
  LSR T0
  ROR A
  LSR T0
  ROR A
  LSR T0
  ROR A
  LSR T0
  ROR A
  CMP #96
  BCC .ub_v
  LDA #96
.ub_v:
  CMP BARV
  BEQ .ub_r
  STA BARV
  STA T1
  LDX #23
  LDY #12
  JSR NT_XY
  LDX #12
.ub_c:
  LDA T1                       ; 8 pixels per cell
  CMP #8
  BCC .ub_p
  SBC #8
  STA T1
  LDA #T_BAR+8
  STA VDATA
  BRA .ub_n
.ub_p:
  CLC
  ADC #T_BAR
  STA VDATA
  STZ T1
.ub_n:
  DEX
  BNE .ub_c
.ub_r:
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
  LDA STATION,Y
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
  STA STATION,Y
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
;  SPACE: the flight to the station and the docking bay
; ===============================================================
SPACE_START:
  JSR SET_BLACK0
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #32                      ; no hull yet
  STA HULLC
  JSR INIT_STARS
  STZ DISTL
  STZ DISTH
  STZ SPHASE
  STZ WAVEN
  LDA #90
  STA SPAWNT
  STZ FIRET
  LDA #K_SHIP
  STA O_K
  LDA #40
  STA O_X
  LDA #104
  STA O_Y
  STZ O_S
  LDA #1
  STA HUDD
  RTS

; the station with its bay in the middle (end of a station)
SPACE_VIEW:
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDA #1
  STA HUDD
  STZ PHASE                    ; the HUD shows the distance bar
  LDA #26
  STA HULLC
  LDA #11
  STA PORTY
  JSR INIT_STARS
  JSR DRAW_HULL
  JSR DRAW_BOTTOM
  JMP UPDATE_BAR

SPACE_FRAME:
  LDA GSTATE
  BEQ .sp_p
  CMP #2
  BNE .sp_l
  LDA HULLC                    ; docking: the shuttle slides into the bay
  ASL A
  ASL A
  ASL A
  CLC
  ADC #20
  CMP O_X
  BCC .sp_s
  BEQ .sp_s
  INC O_X
.sp_s:
  JMP MOVE_STARS
.sp_l:
  JSR MOVE_STARS               ; lost: the explosion
  JMP UPDATE_BOOMS
.sp_p:
  JSR SHIP_MOVE
  LDA GSTATE
  BNE .sp_r
  JSR SHIP_FIRE
  JSR UPDATE_OBJS
  JSR SHIP_CHECKS
  JSR MOVE_STARS
  JSR SPACE_SPAWN
  JSR APPROACH
  INC DISTL
  BNE .sp_r
  INC DISTH
.sp_r:
  RTS

; the shuttle: 2 pixels per frame in 8 directions; the hull and the bay
SHIP_MOVE:
  LDA JOYC
  AND #1
  BEQ .sm_d
  LDA O_Y
  CMP #34
  BCC .sm_d
  DEC O_Y
  DEC O_Y
.sm_d:
  LDA JOYC
  AND #2
  BEQ .sm_l
  LDA O_Y
  CMP #182
  BCS .sm_l
  INC O_Y
  INC O_Y
.sm_l:
  LDA JOYC
  AND #4
  BEQ .sm_r
  LDA O_X
  CMP #14
  BCC .sm_r
  DEC O_X
  DEC O_X
.sm_r:
  LDA JOYC
  AND #8
  BEQ .sm_h
  LDA O_X
  CMP #236
  BCS .sm_h
  INC O_X
  INC O_X
.sm_h:
  LDA HULLC                    ; the hull: nose, top and bottom of the shuttle
  CMP #32
  BCS .sm_x
  LDA O_X
  CLC
  ADC #7
  LDY O_Y
  DEY
  DEY
  DEY
  DEY
  DEY
  DEY
  DEY
  DEY
  JSR HULL_AT
  CMP #2
  BEQ .sm_dock
  CMP #1
  BEQ .sm_crash
  LDA O_Y
  SEC
  SBC #12
  TAY
  LDA O_X
  CLC
  ADC #4
  JSR HULL_AT
  BNE .sm_crash
  LDA O_Y
  SEC
  SBC #4
  TAY
  LDA O_X
  CLC
  ADC #4
  JSR HULL_AT
  BNE .sm_crash
.sm_x:
  RTS
.sm_crash:
  LDA #6
  JMP HERO_LOST
.sm_dock:
  LDA #2                       ; in the bay: docked
  STA GSTATE
  LDA #70
  STA GT
  LDA #W_DOCK
  LDX #2
  JSR SFX_WHISTLE
  LDA #$00
  LDY #$10
  JMP ADD_PTS

; A = x, Y = y: 0 free, 1 hull, 2 the end of the bay
HULL_AT:
  LSR A
  LSR A
  LSR A
  CMP HULLC
  BCC .ha_0
  SEC
  SBC HULLC
  STA TT                       ; column inside the hull
  TYA
  LSR A
  LSR A
  LSR A
  SEC
  SBC PORTY
  CMP #3
  BCS .ha_1                    ; not in the rows of the bay
  LDA TT
  CMP #3
  BCC .ha_0
  LDA #2
  RTS
.ha_0:
  LDA #0
  RTS
.ha_1:
  LDA #1
  RTS

; button 1: a shot every 8 frames (slots 7 and 8)
SHIP_FIRE:
  LDA FIRET
  BEQ .sf_t
  DEC FIRET
  RTS
.sf_t:
  LDA JOYC
  AND #16
  BEQ .sf_r
  LDY #7
  LDA O_K,Y
  BEQ .sf_f
  INY
  LDA O_K,Y
  BNE .sf_r
.sf_f:
  LDA #K_SHOT
  STA O_K,Y
  LDA O_X
  CLC
  ADC #10
  STA O_X,Y
  LDA O_Y
  STA O_Y,Y
  LDA #0
  STA O_S,Y
  STA O_A,Y
  LDA #8
  STA FIRET
  LDA #W_SHOT
  JMP SFX_HERE
.sf_r:
  RTS

; the shuttle against enemies and their shots
SHIP_CHECKS:
  LDX #1
.sc_l:
  LDA O_K,X
  CMP #K_ROCK
  BCC .sc_n
  CMP #K_SHOT
  BEQ .sc_n
  CMP #K_BOOM
  BCS .sc_n
  LDA O_X,X
  SEC
  SBC O_X
  BCS .sc_a
  EOR #$FF
  ADC #1
.sc_a:
  CMP #11
  BCS .sc_n
  LDA O_Y,X
  SEC
  SBC O_Y
  BCS .sc_b
  EOR #$FF
  ADC #1
.sc_b:
  CMP #9
  BCS .sc_n
  STZ O_K,X
  LDA #6
  JMP HERO_LOST
.sc_n:
  INX
  CPX #NOB
  BCC .sc_l
  RTS

; enemies from the right: waves of fighters, rocks, gunships, mines
SPACE_SPAWN:
  LDA SPHASE
  BNE .ss_r
  LDA WAVEN                    ; a wave going on: a fighter every 16 frames
  BEQ .ss_t
  LDA GF
  AND #15
  BNE .ss_t
  LDA #K_FIGHTER
  JSR NEW_ENEMY
  BCS .ss_t
  DEC WAVEN
  LDA WAVEY
  STA O_P,X
  STA O_Y,X
.ss_t:
  DEC SPAWNT
  BNE .ss_r
  LDA DIFF                     ; next one in 70 - difficulty x 3 + 0-31 frames
  ASL A
  ADC DIFF
  STA T0
  LDA RND
  AND #31
  ADC #70
  SEC
  SBC T0
  STA SPAWNT
  LDA STATION                  ; kind: SPAWNK[station * 8 + random]
  ASL A
  ASL A
  ASL A
  STA T0
  JSR NEXT_RND
  AND #7
  ORA T0
  TAY
  LDA SPAWNK,Y
  CMP #K_FIGHTER
  BNE .ss_one
  LDA WAVEN
  BNE .ss_r
  LDA DIFF                     ; 3 + difficulty / 4 fighters
  LSR A
  LSR A
  CLC
  ADC #3
  STA WAVEN
  LDA RND
  AND #$5F
  CLC
  ADC #56
  STA WAVEY
  RTS
.ss_one:
  JSR NEW_ENEMY
.ss_r:
  RTS

; A = kind: a new enemy at the right edge in a free slot 1-6 (carry set = none free); X = slot
NEW_ENEMY:
  LDX #1
.ne_l:
  LDY O_K,X
  BEQ .ne_f
  INX
  CPX #7
  BCC .ne_l
  SEC
  RTS
.ne_f:
  STA O_K,X
  TAY
  LDA KHP,Y
  STA O_H,X
  LDA #250
  STA O_X,X
  JSR NEXT_RND                 ; a row between 40 and 167
  AND #$7F
  CLC
  ADC #40
  STA O_Y,X
  STZ O_XL,X
  STZ O_YL,X
  STZ O_T,X
  STZ O_S,X
  STZ O_A,X
  STZ O_VY,X
  LDA RND                      ; rocks: drift up or down, two shapes
  AND #$3F
  SEC
  SBC #$20
  STA O_VYL,X
  BPL .ne_v
  DEC O_VY,X
.ne_v:
  LDA RND
  AND #4
  STA O_A,X
  CLC
  RTS

; the station comes in from the right, then the bay goes up and down
APPROACH:
  LDA SPHASE
  BNE .ap_1
  LDA DISTH
  CMP #>DIST_END
  BCC .ap_r
  LDA DISTL
  CMP #<DIST_END
  BCC .ap_r
  INC SPHASE
  STZ WAVEN
  LDA #11
  STA PORTY
  STZ PORTD
  LDA #40
  STA PORTT
  RTS
.ap_1:
  CMP #1
  BNE .ap_2
  LDA GF
  AND #7
  BNE .ap_r
  DEC HULLC
  JSR DRAW_HULL
  LDA HULLC
  CMP #26
  BNE .ap_r
  INC SPHASE
  RTS
.ap_2:
  DEC PORTT
  BNE .ap_r
  LDA #30                      ; a row every 30 - difficulty frames
  SEC
  SBC DIFF
  STA PORTT
  LDA PORTD
  BNE .ap_up
  INC PORTY
  LDA PORTY
  CMP #18
  BCC .ap_d
  INC PORTD
  BRA .ap_d
.ap_up:
  DEC PORTY
  LDA PORTY
  CMP #5
  BCS .ap_d
  STZ PORTD
.ap_d:
  JMP DRAW_HULL
.ap_r:
  RTS

; the hull from column HULLC to 31, rows 2-22, with the bay at rows PORTY..PORTY+2
DRAW_HULL:
  LDA #2
  STA T2                       ; row
.dh_r:
  LDA T2
  LDY HULLC
  JSR SET_RC
  LDA HULLC
  STA T3                       ; column
.dh_c:
  LDA T3
  SEC
  SBC HULLC
  STA TT                       ; column inside the hull 0..
  LDA T2
  SEC
  SBC PORTY
  CLC
  ADC #1                       ; row - PORTY + 1: 0 top wall, 1-3 inside, 4 bottom wall
  CMP #5
  BCS .dh_h
  TAX
  LDA TT
  CMP #4
  BCS .dh_h
  CPX #0
  BNE .dh_b
  LDA #T_BAYT
  BRA .dh_p
.dh_b:
  CPX #4
  BNE .dh_i
  LDA #T_BAYB
  BRA .dh_p
.dh_i:
  LDA TT
  CMP #3
  LDA #T_BAYIN
  BCC .dh_p
  LDA #T_BAYEND
  BRA .dh_p
.dh_h:
  LDA TT
  BNE .dh_hh
  LDA #T_HULLE
  BRA .dh_p
.dh_hh:
  LDA #T_HULL
.dh_p:
  STA VDATA
  INC T3
  LDA T3
  CMP #32
  BCC .dh_c
  INC T2
  LDA T2
  CMP #23
  BCC .dh_r
  RTS

; A = row, Y = column: VRAM write address of the cell (keeps X)
SET_RC:
  PHA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA TT
  TYA
  ORA TT
  STA VREG
  PLA
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  RTS

; ---------------------------------------------------------------
; stars: 24 dots in 2 layers (far: 1 pixel every 2 frames, near:
; 2 pixels per frame), tiles with the dot in 8 places
; ---------------------------------------------------------------
SROW = STARS
SCOL = STARS+24
SSUB = STARS+48
SLAY = STARS+72

INIT_STARS:
  LDX #NSTAR-1
.is_l:
  JSR STAR_ROW
  JSR NEXT_RND
  AND #31
  STA SCOL,X
  STZ SSUB,X
  TXA
  AND #1
  STA SLAY,X
  JSR STAR_DRAW
  DEX
  BPL .is_l
  RTS

; a random row 2-22 for the star X
STAR_ROW:
  JSR NEXT_RND
.sr_l:
  CMP #21
  BCC .sr_ok
  SBC #21
  BRA .sr_l
.sr_ok:
  CLC
  ADC #2
  STA SROW,X
  RTS

; the star X in its cell (not behind the hull)
STAR_DRAW:
  LDA SCOL,X
  CMP HULLC
  BCS .sd_r
  TAY
  LDA SROW,X
  JSR SET_RC
  LDA SLAY,X
  BEQ .sd_f
  LDA #T_NEAR0
  BRA .sd_t
.sd_f:
  LDA #T_FAR0
.sd_t:
  CLC
  ADC SSUB,X
  STA VDATA
.sd_r:
  RTS

MOVE_STARS:
  LDX #NSTAR-1
.ms_l:
  LDA SLAY,X
  BNE .ms_near
  LDA GF
  AND #1
  BEQ .ms_n
  LDA #1
  BRA .ms_m
.ms_near:
  LDA #2
.ms_m:
  CLC
  ADC SSUB,X
  CMP #8
  BCC .ms_same
  AND #7                       ; into the next cell on the left: clear the old one
  STA SSUB,X
  LDA SCOL,X
  CMP HULLC
  BCS .ms_c
  TAY
  LDA SROW,X
  JSR SET_RC
  STZ VDATA
.ms_c:
  DEC SCOL,X
  BPL .ms_d
  LDA #31                      ; off the left edge: again from the right
  STA SCOL,X
  JSR STAR_ROW
  BRA .ms_d
.ms_same:
  STA SSUB,X
.ms_d:
  JSR STAR_DRAW
.ms_n:
  DEX
  BPL .ms_l
  RTS

; ---------------------------------------------------------------
; space objects (X = slot)
; ---------------------------------------------------------------
; rock: left 1 pixel per frame, drifting up or down
OB_ROCK:
  DEC O_X,X
  LDA GF
  AND #1
  BEQ .or_y
  DEC O_X,X
.or_y:
  CLC
  LDA O_YL,X
  ADC O_VYL,X
  STA O_YL,X
  LDA O_Y,X
  ADC O_VY,X
  STA O_Y,X
  CMP #36
  BCC .or_b
  CMP #184
  BCC .or_x
.or_b:
  SEC                          ; bounce on the edges
  LDA #0
  SBC O_VYL,X
  STA O_VYL,X
  LDA #0
  SBC O_VY,X
  STA O_VY,X
.or_x:
  JMP OFF_LEFT

; fighter: left 2 pixels per frame on a wave around its row
OB_FIGHTER:
  DEC O_X,X
  DEC O_X,X
  INC O_T,X
  LDA O_T,X
  LSR A
  AND #63
  TAY
  LDA SINE,Y
  CLC
  ADC O_P,X
  STA O_Y,X
  LDA GF
  AND #8
  LSR A
  STA O_A,X
  JMP OFF_LEFT

; gunship: comes in, stays a while following the shuttle and shooting, then goes
OB_GUNSHIP:
  INC O_T,X
  LDA O_T,X
  CMP #240
  BCS .og_go
  LDA O_X,X
  CMP #200
  BCC .og_s
  DEC O_X,X
  RTS
.og_s:
  LDA GF                       ; follows the shuttle up and down
  AND #1
  BNE .og_f
  LDA O_Y,X
  CMP O_Y
  BEQ .og_f
  BCC .og_dn
  DEC O_Y,X
  BRA .og_f
.og_dn:
  INC O_Y,X
.og_f:
  LDA O_T,X
  AND #63
  BNE .og_r
  LDA O_X,X
  SEC
  SBC #10
  STA CX
  LDA O_Y,X
  STA CY
  LDA #K_EBOLT
  JSR NEW_SHOT
  LDA #S_SHOT
  LDY O_X,X
  JSR BOOM_AT
  LDX SLOT
.og_r:
  RTS
.og_go:
  DEC O_X,X
  DEC O_X,X
  JMP OFF_LEFT

; mine: slowly left, slowly towards the row of the shuttle
OB_MINE:
  LDA GF
  AND #1
  BNE .om_y
  DEC O_X,X
.om_y:
  LDA GF
  AND #3
  BNE .om_a
  LDA O_Y,X
  CMP O_Y
  BEQ .om_a
  BCC .om_dn
  DEC O_Y,X
  BRA .om_a
.om_dn:
  INC O_Y,X
.om_a:
  LDA GF
  AND #16
  LSR A
  LSR A
  STA O_A,X
  JMP OFF_LEFT

; shot of a gunship: left 3 pixels per frame
OB_EBOLT:
  LDA O_X,X
  SEC
  SBC #3
  STA O_X,X
  ; fall into OFF_LEFT

; gone past the left edge: free the slot
OFF_LEFT:
  LDA O_X,X
  CMP #6
  BCS .ol_r
  STZ O_K,X
.ol_r:
  RTS

; shot of the shuttle: right 6 pixels per frame; hits rocks, fighters, gunships, mines
OB_SHOT:
  LDA O_X,X
  CLC
  ADC #6
  STA O_X,X
  CMP #248
  BCS .oh_k
  LSR A
  LSR A
  LSR A
  CMP HULLC
  BCS .oh_k
  LDY #1
.oh_e:
  LDA O_K,Y
  CMP #K_ROCK
  BCC .oh_n
  CMP #K_MINE+1
  BCS .oh_n
  LDA O_X,Y
  SEC
  SBC O_X,X
  BCS .oh_a
  EOR #$FF
  ADC #1
.oh_a:
  CMP #10
  BCS .oh_n
  LDA O_Y,Y
  SEC
  SBC O_Y,X
  BCS .oh_b
  EOR #$FF
  ADC #1
.oh_b:
  CMP #9
  BCS .oh_n
  STZ O_K,X                    ; the shot is spent
  LDA O_H,Y
  SEC
  SBC #1
  STA O_H,Y
  BEQ .oh_kill
  LDA #S_SHOT
  LDY O_X,X
  JMP BOOM_AT
.oh_kill:
  PHY                          ; the enemy blows up
  PLX
  LDY O_K,X
  LDA KPTS_L,Y
  PHA
  LDA KPTS_M,Y
  TAY
  PLA
  JSR ADD_PTS
  STZ O_K,X
  JSR MAKE_BOOM
  LDA #S_BOOM
  LDY O_X,X
  JSR BOOM_AT
  LDX SLOT
  RTS
.oh_n:
  INY
  CPY #NOB
  BCC .oh_e
  RTS
.oh_k:
  STZ O_K,X
  RTS

; explosion: 24 frames
OB_BOOM:
  DEC O_T,X
  BNE .bo_r
  STZ O_K,X
.bo_r:
  RTS

UPDATE_BOOMS:
  LDX #1
.ub_l:
  LDA O_K,X
  CMP #K_BOOM
  BNE .ub_n
  JSR OB_BOOM
.ub_n:
  INX
  CPX #NOB
  BCC .ub_l
  RTS

; X = slot: an explosion where it is (keeps X)
MAKE_BOOM:
  LDA O_X,X
  STA CX
  LDA O_Y,X
  STA CY
  LDA #K_BOOM
  JSR NEW_SHOT
  CPY #NOB
  BCS .mb_r
  LDA #24
  STA O_T,Y
  LDA #0
  STA O_S,Y
.mb_r:
  RTS

; an explosion somewhere on the hull (the station blows up)
HULL_BOOM:
  LDA HULLC
  ASL A
  ASL A
  ASL A
  STA CX
  LDA RND
  AND #31
  CLC
  ADC CX
  STA CX
  JSR NEXT_RND
  AND #$7F
  CLC
  ADC #40
  STA CY
  LDA #K_BOOM
  JSR NEW_SHOT
  CPY #NOB
  BCS .hb_s
  LDA #24
  STA O_T,Y
  LDA #0
  STA O_S,Y
.hb_s:
  LDA #S_BOOM
  LDX #2
  JMP SFX_BOOM


; ===============================================================
;  THE STATION: rooms, runner, enemies, hazards, oxygen, countdown
; ===============================================================
; a turn inside the station: tiles in the colours of the station, the room, the HUD
STATION_START:
  JSR SET_BLACK0
  JSR CLEAR_NT
  JSR LOAD_TILES
  JSR DRAW_TOP
  LDA #96                      ; oxygen full
  STA OXY
  LDA OXRATE
  STA OXT
  LDA ESC                      ; escaping: the countdown starts again
  BEQ .sn_e
  JSR SET_COUNT
.sn_e:
  LDA #K_HERO
  STA O_K
  LDA ENTX
  STA O_X
  LDA ENTY
  STA O_Y
  STZ O_XL
  STZ O_YL
  STZ O_VY
  STZ O_VYL
  STZ O_AIR
  STZ O_D
  STZ CLIMB
  JSR ROOM_LOAD
  LDA #1
  STA HUDD
  RTS

; the countdown of the core: 40 seconds in station 1, 2 less per station, at least 20
SET_COUNT:
  LDA DIFF
  ASL A
  STA T0
  LDA #40
  SEC
  SBC T0
  CMP #20
  BCS .sc_ok
  LDA #20
.sc_ok:
  JSR BIN2BCD
  STA TIMEL
  STZ TSUB
  LDA #1
  STA ALRT
  RTS

; ---------------------------------------------------------------
; ROOM (of STATION): the map from RLE (taken pickups left out),
; the name table, the enemies; the runner stays where he is
; ---------------------------------------------------------------
ROOM_LOAD:
  LDA STATION                  ; room number = station * 3 + room
  ASL A
  ADC STATION
  ADC ROOM
  TAX
  LDA ROOM_LO,X
  STA PTR
  LDA ROOM_HI,X
  STA PTR+1
  LDA RENM_LO,X
  STA PTR2
  LDA RENM_HI,X
  STA PTR2+1
  LDA #<MAP
  STA CELLP
  LDA #>MAP
  STA CELLP+1
  STZ NPICK
  LDX ROOM
  LDA TAKEN,X
  STA T3                       ; bits of the pickups already taken
.rl_l:
  LDA (PTR)
  JSR .rl_inc
  CMP #7
  BEQ .rl_run
  TAY                          ; one tile: a pickup?
  LDA CLASS,Y
  CMP #CL_OXY
  BCC .rl_put
  LDX NPICK                    ; its address and its bit
  LDA CELLP
  STA PICKA,X
  LDA CELLP+1
  STA PICKA+8,X
  INC NPICK
  LSR T3
  BCC .rl_put
  LDY #0                       ; taken already
.rl_put:
  TYA
  STA (CELLP)
  INC CELLP
  BNE .rl_l
  INC CELLP+1
  BRA .rl_l
.rl_run:
  LDA (PTR)                    ; 7, count, tile (count 0 = end)
  JSR .rl_inc
  TAX
  BEQ .rl_end
  LDA (PTR)
  JSR .rl_inc
.rl_r:
  STA (CELLP)
  INC CELLP
  BNE .rl_rn
  INC CELLP+1
.rl_rn:
  DEX
  BNE .rl_r
  BRA .rl_l
.rl_inc:
  INC PTR
  BNE .rl_ir
  INC PTR+1
.rl_ir:
  RTS
.rl_end:
  ; ---- the name table, rows 2-22 (a dot on the empty cells at (c & 3) = 2, (r & 3) = 2)
  LDA #$40
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #<MAP
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDX #0
.rd_r:
  LDY #0
.rd_c:
  LDA (PTR),Y
  BNE .rd_p
  TYA
  AND #3
  CMP #2
  BNE .rd_z
  TXA
  AND #3
  CMP #2
  BNE .rd_z
  LDA #T_DOT
  BRA .rd_p
.rd_z:
  LDA #0
.rd_p:
  STA VDATA
  INY
  CPY #32
  BNE .rd_c
  LDA PTR
  CLC
  ADC #32
  STA PTR
  BCC .rd_n
  INC PTR+1
.rd_n:
  INX
  CPX #21
  BNE .rd_r
  ; ---- the enemies: count, then kind, x, feet, p
  LDX #NOB-1
.rl_o:
  STZ O_K,X
  DEX
  BNE .rl_o
  LDA (PTR2)
  STA CNT
  LDY #1
  LDX #1
.rl_e:
  LDA CNT
  BEQ .rl_x
  LDA (PTR2),Y
  INC A                        ; list kind 1-5 -> K_DRONE...K_SPIDER
  STA O_K,X
  INY
  LDA (PTR2),Y
  STA O_X,X
  INY
  LDA (PTR2),Y
  STA O_Y,X
  STA O_Y0,X
  INY
  LDA (PTR2),Y
  STA O_P,X
  INY
  STZ O_XL,X
  STZ O_YL,X
  STZ O_VY,X
  STZ O_VYL,X
  STZ O_AIR,X
  STZ O_S,X
  STZ O_A,X
  TXA                          ; facing: alternate
  AND #1
  STA O_D,X
  LDA RND
  AND #63
  CLC
  ADC #30
  STA O_T,X
  JSR NEXT_RND
  INX
  DEC CNT
  BRA .rl_e
.rl_x:
  LDA #3                       ; per room: stunner charges, no crumbling cell
  STA STUNC
  STZ CRUMT
  STZ CRUMA+1
  LDA #1
  STA HUDD
  ; fall into ANIM_ALL

; every animated tile at once
ANIM_ALL:
  JSR ANIM_BELTS
  JSR ANIM_ARCS
  JSR ANIM_PRESS
  JMP ANIM_CORE


; ===============================================================
;  ONE FRAME IN THE STATION
; ===============================================================
ROOM_FRAME:
  LDA GSTATE
  BEQ .rf_p
  JMP ANIM_TILES               ; lost: only the tiles move
.rf_p:
  JSR HERO_MOVE
  JSR HERO_ZAP
  JSR UPDATE_OBJS
  JSR HERO_CHECKS
  JSR ANIM_TILES
  JMP UPDATE_AIR

; ---------------------------------------------------------------
; A = x, Y = y (pixels): A = class of the cell, Y = its tile;
; CELLP = map row, CCOL = column (keeps X)
; ---------------------------------------------------------------
CLS_AT:
  LSR A
  LSR A
  LSR A
  STA CCOL
  TYA
  LSR A
  LSR A
  LSR A
  SEC
  SBC #2
  BCC .ca_top
  CMP #21
  BCS .ca_out
  TAY
  LDA MROW_LO,Y
  STA CELLP
  LDA MROW_HI,Y
  STA CELLP+1
  LDY CCOL
  LDA (CELLP),Y
  TAY
  LDA CLASS,Y
  RTS
.ca_top:
  LDY #0
  LDA #CL_SOLID
  RTS
.ca_out:
  LDY #0
  LDA #CL_EMPTY
  RTS

; A = x, Y = y: A = 1 (not zero) if the cell is solid
SOLID_AT:
  JSR CLS_AT
  TAY
  LDA SOLIDT,Y
  RTS

; A = x, Y = y: A = 1 if one can stand on the cell (solid, or the top of a ladder)
STAND_AT:
  JSR CLS_AT
  CMP #CL_LADDER
  BEQ .sa_l
  TAY
  LDA SOLIDT,Y
  RTS
.sa_l:
  LDA CELLP                    ; the cell above
  SEC
  SBC #32
  STA CELLP
  BCS .sa_u
  DEC CELLP+1
.sa_u:
  LDY CCOL
  LDA (CELLP),Y
  TAY
  LDA CLASS,Y
  CMP #CL_LADDER
  BEQ .sa_no
  LDA #1
  RTS
.sa_no:
  LDA #0
  RTS

; A = 1 if the runner stands on something (under x - 4 or x + 3)
FEET_STAND:
  LDY HYI
  LDA HXI
  SEC
  SBC #4
  JSR STAND_AT
  BNE .fs_r
  LDY HYI
  LDA HXI
  CLC
  ADC #3
  JSR STAND_AT
.fs_r:
  RTS


; ===============================================================
;  THE RUNNER (the same steps as cn_phys.js)
; ===============================================================
HERO_MOVE:
  LDA O_X
  STA HXI
  LDA O_Y
  STA HYI
  LDA CLIMB
  BEQ .hm_w
  JMP HERO_CLIMB
.hm_w:
  ; ---- sideways step DX (8.8): run, plus the conveyor under the feet
  STZ DX
  STZ DX+1
  LDA JOYC
  AND #4
  BEQ .hm_nl
  LDA #$80                     ; -1.5
  STA DX
  LDA #$FE
  STA DX+1
  LDA #1
  STA O_D
  BRA .hm_cv
.hm_nl:
  LDA JOYC
  AND #8
  BEQ .hm_cv
  LDA #RUN_SP                  ; +1.5
  STA DX
  LDA #1
  STA DX+1
  STZ O_D
.hm_cv:
  LDA O_AIR
  BNE .hm_mv
  LDY HYI
  LDA HXI
  JSR CLS_AT
  CMP #CL_CONVL
  BNE .hm_cr
  DEC DX+1
  BRA .hm_mv
.hm_cr:
  CMP #CL_CONVR
  BNE .hm_mv
  INC DX+1
.hm_mv:
  LDA DX
  ORA DX+1
  BEQ .hm_edge
  CLC                          ; T0 / T1 = new x
  LDA O_XL
  ADC DX
  STA T0
  LDA O_X
  ADC DX+1
  STA T1
  LDA DX+1                     ; the column ahead: x - 5 or x + 4
  BPL .hm_rt
  LDA T1
  SEC
  SBC #5
  BCS .hm_cx
  LDA #0
  BRA .hm_cx
.hm_rt:
  LDA T1
  CLC
  ADC #4
  BCC .hm_cx
  LDA #255
.hm_cx:
  STA TT
  LDY HYI
  DEY
  LDA TT
  JSR SOLID_AT
  BNE .hm_edge
  LDA HYI
  SEC
  SBC #8
  TAY
  LDA TT
  JSR SOLID_AT
  BNE .hm_edge
  LDA HYI
  SEC
  SBC #15
  TAY
  LDA TT
  JSR SOLID_AT
  BNE .hm_edge
  LDA T0
  STA O_XL
  LDA T1
  STA O_X
  STA HXI
.hm_edge:
  ; ---- the edges of the room: the next room
  LDA HXI
  CMP #6
  BCS .hm_er
  LDA ROOM
  BEQ .hm_lad
  DEC ROOM
  LDA #248
  BRA .hm_new
.hm_er:
  CMP #250
  BCC .hm_lad
  LDA ROOM
  CMP #ROOMS_PER-1
  BCS .hm_lad
  INC ROOM
  LDA #8
.hm_new:
  STA O_X
  STA HXI
  STA ENTX
  LDA HYI
  STA ENTY
  JSR ROOM_LOAD
.hm_lad:
  ; ---- ladders: up on a ladder, or down from the top of one
  LDA JOYC
  AND #1
  BEQ .hm_ld
  LDA HYI
  SEC
  SBC #8
  TAY
  LDA HXI
  JSR CLS_AT
  CMP #CL_LADDER
  BEQ .hm_grab
.hm_ld:
  LDA JOYC
  AND #2
  BEQ .hm_gnd
  LDA O_AIR
  BNE .hm_gnd
  LDY HYI
  LDA HXI
  JSR CLS_AT
  CMP #CL_LADDER
  BNE .hm_gnd
.hm_grab:
  LDA HXI
  AND #$F8
  ORA #4
  STA O_X
  STA HXI
  STZ O_XL
  LDA #1
  STA CLIMB
  STZ O_AIR
  STZ O_VY
  STZ O_VYL
  RTS
.hm_gnd:
  ; ---- on the ground: an edge, a lift, a jump
  LDA O_AIR
  BNE .hm_air
  LDA HYI
  SEC
  SBC #8
  TAY
  LDA HXI
  JSR CLS_AT
  CMP #CL_LIFT
  BEQ .hm_fall
  JSR FEET_STAND
  BNE .hm_jmp
.hm_fall:
  LDA #1
  STA O_AIR
  STZ O_VY
  STZ O_VYL
  LDA HYI
  STA APEX
  BRA .hm_air
.hm_x:
  RTS
.hm_jmp:
  LDA JOYC
  AND #16
  BEQ .hm_x
  LDA JOYP
  AND #16
  BNE .hm_x
  LDA #1
  STA O_AIR
  LDA #<JUMP_V
  STA O_VYL
  LDA #>JUMP_V
  STA O_VY
  LDA HYI
  STA APEX
  LDA #W_JUMP
  JSR SFX_HERE
.hm_air:
  ; ---- in the air: a lift pushes up, else the gravity
  LDA HYI
  SEC
  SBC #8
  TAY
  LDA HXI
  JSR CLS_AT
  CMP #CL_LIFT
  BNE .hm_grav
  SEC
  LDA O_VYL
  SBC #LIFT_A
  STA O_VYL
  LDA O_VY
  SBC #0
  STA O_VY
  BPL .hm_la                   ; at most -2.0 per frame
  CMP #$FE
  BCS .hm_la
  LDA #$FE
  STA O_VY
  STZ O_VYL
.hm_la:
  LDA HYI
  STA APEX
  BRA .hm_move
.hm_grav:
  LDA O_VY
  BPL .hm_down
  LDA JOYC
  AND #16
  BEQ .hm_gu
  LDA #G_HOLD
  BRA .hm_ga
.hm_gu:
  LDA #G_UP
  BRA .hm_ga
.hm_down:
  LDA #G_FALL
.hm_ga:
  CLC
  ADC O_VYL
  STA O_VYL
  LDA O_VY
  ADC #0
  STA O_VY
  BMI .hm_move                 ; at most +4.0 per frame
  CMP #4
  BCC .hm_move
  LDA #4
  STA O_VY
  STZ O_VYL
.hm_move:
  LDA HYI
  STA OYI
  CLC
  LDA O_YL
  ADC O_VYL
  STA O_YL
  LDA O_Y
  ADC O_VY
  STA O_Y
  STA HYI
  LDA O_VY
  BPL .hm_land
  ; ---- going up: the head
  LDA HYI
  SEC
  SBC #15
  TAY
  LDA HXI
  SEC
  SBC #4
  JSR SOLID_AT
  BNE .hm_bump
  LDA HYI
  SEC
  SBC #15
  TAY
  LDA HXI
  CLC
  ADC #3
  JSR SOLID_AT
  BEQ .hm_apx
.hm_bump:
  LDA HYI
  SEC
  SBC #15
  ORA #7
  CLC
  ADC #16
  STA O_Y
  STA HYI
  STZ O_YL
  STZ O_VY
  STZ O_VYL
  BRA .hm_apx
.hm_land:
  ; ---- coming down: a tile top crossed?
  LDA HYI
  AND #$F8
  STA TT
  CMP OYI
  BCC .hm_apx
  LDY TT
  LDA HXI
  SEC
  SBC #4
  JSR STAND_AT
  BNE .hm_lnd
  LDY TT
  LDA HXI
  CLC
  ADC #3
  JSR STAND_AT
  BEQ .hm_apx
.hm_lnd:
  LDA TT
  STA O_Y
  STA HYI
  STZ O_YL
  STZ O_VY
  STZ O_VYL
  STZ O_AIR
  LDA TT
  SEC
  SBC APEX
  CMP #FALL_MAX+1
  BCC .hm_apx
  LDA #3
  JMP HERO_LOST
.hm_apx:
  LDA HYI
  CMP APEX
  BCS .hm_ah
  STA APEX
.hm_ah:
  CMP #190
  BCC .hm_r
  LDA #3
  JMP HERO_LOST
.hm_r:
  RTS

; on a ladder: up / down one pixel per frame; off at the top, at the bottom or sideways on a floor
HERO_CLIMB:
  LDA JOYC
  AND #1
  BEQ .hc_d
  LDA HYI
  AND #7
  BNE .hc_up
  LDY HYI
  LDA HXI
  JSR CLS_AT
  CMP #CL_LADDER
  BNE .hc_up
  LDA HYI
  SEC
  SBC #8
  TAY
  LDA HXI
  JSR CLS_AT
  CMP #CL_LADDER
  BEQ .hc_up
  STZ CLIMB                    ; the top
  RTS
.hc_up:
  DEC O_Y
  RTS
.hc_d:
  LDA JOYC
  AND #2
  BEQ .hc_s
  INC O_Y
  LDA O_Y
  STA HYI
  AND #7
  BNE .hc_r
  LDY HYI
  LDA HXI
  JSR CLS_AT
  TAY
  LDA SOLIDT,Y
  BEQ .hc_nf
  STZ CLIMB                    ; the floor
  RTS
.hc_nf:
  CPY #CL_LADDER
  BEQ .hc_r
  STZ CLIMB                    ; the ladder ends in the air
  LDA #1
  STA O_AIR
  STZ O_VY
  STZ O_VYL
  LDA HYI
  STA APEX
  RTS
.hc_s:
  LDA JOYC
  AND #12
  BEQ .hc_r
  LDA HYI
  AND #7
  BNE .hc_r
  JSR FEET_STAND
  BEQ .hc_r
  STZ CLIMB
.hc_r:
  RTS

; A = cause (DEATH): the runner / the shuttle is lost
HERO_LOST:
  LDX GSTATE
  BNE .hl_r
  STA DEATH
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  STZ CLIMB
  LDA #W_DIE
  LDX #2
  JSR SFX_WHISTLE
  LDA PHASE
  BNE .hl_r
  LDA #S_BIG                   ; in space: the shuttle blows up
  LDX #2
  JSR SFX_BOOM
  LDX #0
  JSR MAKE_BOOM
  STZ O_K
.hl_r:
  RTS

; A = whistle, on the side of the runner
SFX_HERE:
  LDX #0
  LDY O_X
  CPY #$80
  BCC .sh_l
  INX
.sh_l:
  JMP SFX_WHISTLE

; button 2: the stunner (slot 7)
HERO_ZAP:
  LDA JOYC
  AND #32
  BEQ .hz_r
  LDA JOYP
  AND #32
  BNE .hz_r
  LDA STUNC
  BEQ .hz_r
  LDA O_K+7
  BNE .hz_r
  DEC STUNC
  LDA #1
  STA HUDD
  LDA #K_ZAP
  STA O_K+7
  LDA O_D
  STA O_D+7
  LDA HXI
  LDX O_D
  CLC
  ADC ZAP_DX,X
  STA O_X+7
  LDA HYI
  SEC
  SBC #2
  STA O_Y+7
  LDA #18
  STA O_T+7
  STZ O_A+7
  STZ O_S+7
  LDA #W_STUN
  JSR SFX_HERE
.hz_r:
  RTS


; ===============================================================
;  WHAT THE RUNNER TOUCHES
; ===============================================================
HERO_CHECKS:
  LDA GSTATE
  BEQ .hk_go
  RTS
.hk_go:
  ; ---- 4 points of the body: hazards, the core, pickups
  LDX #3
.hk_p:
  STX CNT
  LDA HYI
  SEC
  SBC HK_DY,X
  TAY
  LDA HXI
  CLC
  ADC HK_DX,X
  JSR CLS_AT
  STA CCLS
  CMP #CL_HAZA0
  BCC .hk_n
  CMP #CL_HAZA0+4
  BCS .hk_c
  SEC                          ; (class - 6) x 4 + HZON
  SBC #CL_HAZA0
  ASL A
  ASL A
  ORA HZON
  TAX
  LDA LETHAL,X
  BEQ .hk_n
  LDA #2
  JMP HERO_LOST
.hk_c:
  CMP #CL_CORE
  BNE .hk_k
  JSR CORE_HIT
  BRA .hk_n
.hk_k:
  CMP #CL_OXY
  BCC .hk_n
  JSR PICKUP
.hk_n:
  LDX CNT
  DEX
  BPL .hk_p
  ; ---- the hatch, escaping
  LDA ESC
  BEQ .hk_e
  LDA ROOM
  BNE .hk_e
  LDA HXI
  CMP #16
  BCS .hk_e
  LDA #3
  STA GSTATE
  RTS
.hk_e:
  ; ---- enemies and bolts
  LDX #1
.hk_o:
  LDA O_K,X
  CMP #K_DRONE
  BCC .hk_on
  CMP #K_BOLT
  BEQ .hk_b
  BCS .hk_on
  LDA O_S,X                    ; a stunned enemy does no harm
  BNE .hk_on
  LDA O_X,X
  SEC
  SBC HXI
  BCS .hk_a1
  EOR #$FF
  ADC #1
.hk_a1:
  CMP #10
  BCS .hk_on
  LDA O_Y,X
  SEC
  SBC HYI
  BCS .hk_a2
  EOR #$FF
  ADC #1
.hk_a2:
  CMP #13
  BCS .hk_on
  LDA #1
  JMP HERO_LOST
.hk_b:
  LDA O_X,X
  SEC
  SBC HXI
  BCS .hk_a3
  EOR #$FF
  ADC #1
.hk_a3:
  CMP #6
  BCS .hk_on
  LDA O_Y,X                    ; bolt feet - runner feet in -16..2
  SEC
  SBC HYI
  CLC
  ADC #16
  CMP #19
  BCS .hk_on
  LDA #1
  JMP HERO_LOST
.hk_on:
  INX
  CPX #NOB
  BCC .hk_o
  ; ---- standing on a crumbling floor
  LDA O_AIR
  ORA CLIMB
  BNE .hk_r
  LDY HYI
  LDA HXI
  JSR CLS_AT
  CMP #CL_CRUMB
  BNE .hk_cz
  LDA CELLP                    ; T0 / T1 = address of the cell
  CLC
  ADC CCOL
  STA T0
  LDA CELLP+1
  ADC #0
  STA T1
  CMP CRUMA+1
  BNE .hk_cn
  LDA T0
  CMP CRUMA
  BNE .hk_cn
  INC CRUMT
  LDA CRUMT
  CMP #16
  BCC .hk_r
  STZ CRUMT
  STZ CRUMA+1                  ; the next stage of the tile (the last one is empty)
  LDA (T0)
  INC A
  CMP #T_CRUMB2+1
  BNE .hk_cs
  LDA #0
.hk_cs:
  STA (T0)
  JSR PUT_CELL
  LDA #W_CRUMB
  JMP SFX_HERE
.hk_cn:
  LDA T0
  STA CRUMA
  LDA T1
  STA CRUMA+1
.hk_cz:
  STZ CRUMT
.hk_r:
  RTS

; A = tile, T0 / T1 = its address in MAP: the same tile in the name table (MAP + $3040 = $3840 + offset)
PUT_CELL:
  PHA
  LDA T0
  CLC
  ADC #$40
  STA VREG
  LDA T1
  ADC #$30
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  PLA
  STA VDATA
  RTS

; the cell CELLP + CCOL holds a bottle or a crystal (CCLS)
PICKUP:
  LDA CELLP
  CLC
  ADC CCOL
  STA T0
  LDA CELLP+1
  ADC #0
  STA T1
  LDA #0
  STA (T0)
  JSR PUT_CELL
  LDX NPICK                    ; its bit in TAKEN
.pk_f:
  DEX
  BMI .pk_g
  LDA PICKA,X
  CMP T0
  BNE .pk_f
  LDA PICKA+8,X
  CMP T1
  BNE .pk_f
  LDA BITS,X
  LDX ROOM
  ORA TAKEN,X
  STA TAKEN,X
.pk_g:
  LDA CCLS
  CMP #CL_OXY
  BNE .pk_c
  LDA OXY                      ; a bottle: + 32 oxygen
  CLC
  ADC #32
  CMP #97
  BCC .pk_o
  LDA #96
.pk_o:
  STA OXY
  LDA #W_PICK
  JMP SFX_HERE
.pk_c:
  LDA #$00                     ; a crystal: 500
  LDY #$05
  JSR ADD_PTS
  LDA #W_CRYS
  JMP SFX_HERE

; the runner touches the core: overload, 2000 points, run back!
CORE_HIT:
  LDA ESC
  BNE .ch_r
  LDA #1
  STA ESC
  JSR SET_COUNT
  LDA #$00
  LDY #$20
  JSR ADD_PTS
  LDA #W_CORE
  LDX #2
  JSR SFX_WHISTLE
  LDA #60
  STA ALRT
.ch_r:
  RTS

; oxygen (always) and the countdown of the core (escaping)
UPDATE_AIR:
  DEC OXT
  BNE .ua_c
  LDA OXRATE
  STA OXT
  LDA OXY
  BEQ .ua_c
  DEC OXY
  BNE .ua_c
  LDA #4
  JMP HERO_LOST
.ua_c:
  LDA ESC
  BEQ .ua_r
  INC TSUB
  LDA TSUB
  CMP #60
  BCC .ua_al
  STZ TSUB
  SED
  LDA TIMEL
  SEC
  SBC #1
  STA TIMEL
  CLD
  LDA #1
  STA HUDD
  LDA TIMEL
  BNE .ua_al
  LDA #5
  JMP HERO_LOST
.ua_al:
  DEC ALRT                     ; the alarm: every half second, faster in the last 10 seconds
  BNE .ua_r
  LDA TIMEL
  CMP #$10
  LDA #30
  BCS .ua_s
  LDA #15
.ua_s:
  STA ALRT
  LDA #W_ALARM
  LDX #2
  JMP SFX_WHISTLE
.ua_r:
  RTS


; ===============================================================
;  OBJECTS: one routine per kind (X = slot), shared with space
; ===============================================================
UPDATE_OBJS:
  LDX #1
.uo_l:
  STX SLOT
  LDA O_K,X
  BEQ .uo_n
  ASL A
  TAY
  LDA OBJ_JT,Y
  STA PTR2
  LDA OBJ_JT+1,Y
  STA PTR2+1
  JSR .uo_j
.uo_n:
  LDX SLOT
  INX
  CPX #NOB
  BCC .uo_l
  RTS
.uo_j:
  JMP (PTR2)

OB_NONE:
  RTS

; T4 / T5 = speed (8.8) of the enemy in X: base of its kind + difficulty + escape
ESPEED:
  LDY O_K,X
  LDA KSPD,Y
  CLC
  ADC SPDB
  STA T4
  LDA #0
  ADC KSPDH,Y
  STA T5
  LDA ESC
  BEQ .es_r
  LDA T4
  CLC
  ADC #$40
  STA T4
  BCC .es_r
  INC T5
.es_r:
  RTS

; x of X += / -= T4 / T5 by its facing
STEP_X:
  LDA O_D,X
  BNE .sx_l
  CLC
  LDA O_XL,X
  ADC T4
  STA O_XL,X
  LDA O_X,X
  ADC T5
  STA O_X,X
  RTS
.sx_l:
  SEC
  LDA O_XL,X
  SBC T4
  STA O_XL,X
  LDA O_X,X
  SBC T5
  STA O_X,X
  RTS

; A = 1 if the enemy X must turn: wall ahead, edge of the room (and with T6 = 1: no floor ahead)
TURN_CHECK:
  LDY O_D,X
  LDA O_X,X
  CLC
  ADC AHEAD,Y
  STA TT
  CMP #8
  BCC .tc_y
  CMP #248
  BCS .tc_y
  LDA O_Y,X
  SEC
  SBC #8
  TAY
  LDA TT
  JSR SOLID_AT
  BNE .tc_y
  LDA T6
  BEQ .tc_n
  LDY O_Y,X
  LDA TT
  JSR STAND_AT
  BEQ .tc_y
.tc_n:
  LDA #0
  RTS
.tc_y:
  LDA #1
  RTS

; a stunned enemy counts down and stays: carry set
STUNNED:
  LDA O_S,X
  BEQ .su_n
  DEC O_S,X
  SEC
  RTS
.su_n:
  CLC
  RTS

; drone: back and forth on its floor
OB_DRONE:
  JSR STUNNED
  BCS .od_r
  JSR ESPEED
  JSR STEP_X
  LDA #1
  STA T6
  JSR TURN_CHECK
  BEQ .od_a
  LDA O_D,X
  EOR #1
  STA O_D,X
.od_a:
  LDA O_X,X
  LSR A
  LSR A
  AND #4
  STA O_A,X
.od_r:
  RTS

; spark: flies along its row, back at the walls
OB_SPARK:
  JSR STUNNED
  BCS .os_r
  JSR ESPEED
  JSR STEP_X
  STZ T6
  JSR TURN_CHECK
  BEQ .os_a
  LDA O_D,X
  EOR #1
  STA O_D,X
.os_a:
  LDA GF
  AND #4
  STA O_A,X
.os_r:
  RTS

; spider: up and down on its thread
OB_SPIDER:
  JSR STUNNED
  BCS .op_r
  JSR ESPEED
  LDA O_D,X
  BNE .op_u
  CLC
  LDA O_YL,X
  ADC T4
  STA O_YL,X
  LDA O_Y,X
  ADC T5
  STA O_Y,X
  CMP O_P,X
  BCC .op_a
  LDA O_P,X
  STA O_Y,X
  LDA #1
  STA O_D,X
  BRA .op_a
.op_u:
  SEC
  LDA O_YL,X
  SBC T4
  STA O_YL,X
  LDA O_Y,X
  SBC T5
  STA O_Y,X
  CMP O_Y0,X
  BEQ .op_a
  BCS .op_a
  LDA O_Y0,X
  STA O_Y,X
  STZ O_D,X
.op_a:
  LDA O_Y,X
  AND #4
  STA O_A,X
.op_r:
  RTS

; turret: a bolt down every 100 - difficulty x 4 frames
OB_TURRET:
  JSR STUNNED
  BCS .ot_r
  DEC O_T,X
  BNE .ot_r
  LDA DIFF
  ASL A
  ASL A
  STA T0
  LDA #100
  SEC
  SBC T0
  STA O_T,X
  LDA O_X,X
  STA CX
  LDA O_Y,X
  CLC
  ADC #10
  STA CY
  LDA #K_BOLT
  JSR NEW_SHOT
.ot_r:
  RTS

; jumper: waits, then jumps towards the runner
OB_JUMPER:
  JSR STUNNED
  BCS .oj_r
  LDA O_AIR,X
  BNE .oj_air
  STZ O_A,X
  DEC O_T,X
  BNE .oj_r
  LDA RND
  AND #31
  CLC
  ADC #50
  STA O_T,X
  LDA #1
  STA O_AIR,X
  LDA #$FD                     ; -3.0
  STA O_VY,X
  STZ O_VYL,X
  LDA O_X                      ; towards the runner
  CMP O_X,X
  LDA #0
  BCS .oj_d
  LDA #1
.oj_d:
  STA O_D,X
.oj_r:
  RTS
.oj_air:
  LDA #4
  STA O_A,X
  JSR ESPEED                   ; sideways, unless a wall is ahead
  STZ T6
  JSR TURN_CHECK
  BNE .oj_g
  JSR STEP_X
.oj_g:
  LDA O_VYL,X                  ; gravity
  CLC
  ADC #$30
  STA O_VYL,X
  LDA O_VY,X
  ADC #0
  STA O_VY,X
  BMI .oj_m
  CMP #4
  BCC .oj_m
  LDA #4
  STA O_VY,X
  STZ O_VYL,X
.oj_m:
  LDA O_Y,X
  STA OYI
  CLC
  LDA O_YL,X
  ADC O_VYL,X
  STA O_YL,X
  LDA O_Y,X
  ADC O_VY,X
  STA O_Y,X
  CMP #190
  BCC .oj_h
  STZ O_K,X                    ; fell out of the room
  RTS
.oj_h:
  LDA O_VY,X
  BPL .oj_l
  LDA O_Y,X                    ; going up: the head
  SEC
  SBC #15
  TAY
  LDA O_X,X
  JSR SOLID_AT
  BEQ .oj_x
  STZ O_VY,X
  STZ O_VYL,X
  RTS
.oj_l:
  LDA O_Y,X                    ; coming down: a floor?
  AND #$F8
  STA TT
  CMP OYI
  BCC .oj_x
  LDY TT
  LDA O_X,X
  JSR STAND_AT
  BEQ .oj_x
  LDA TT
  STA O_Y,X
  STZ O_YL,X
  STZ O_VY,X
  STZ O_VYL,X
  STZ O_AIR,X
.oj_x:
  RTS

; bolt of a turret: down 2 pixels per frame until something solid
OB_BOLT:
  LDA O_Y,X
  CLC
  ADC #2
  STA O_Y,X
  CMP #184
  BCS .ob_k
  TAY
  LDA O_X,X
  JSR SOLID_AT
  BEQ .ob_r
.ob_k:
  STZ O_K,X
.ob_r:
  RTS

; stunner: 4 pixels per frame for 18 frames; stops an enemy for 3 seconds
OB_ZAP:
  LDA O_D,X
  TAY
  LDA O_X,X
  CLC
  ADC ZAP_V,Y
  STA O_X,X
  CMP #4
  BCC .oz_k
  CMP #252
  BCS .oz_k
  DEC O_T,X
  BEQ .oz_k
  LDA O_Y,X
  SEC
  SBC #6
  TAY
  LDA O_X,X
  JSR SOLID_AT
  BNE .oz_k
  LDY #1                       ; an enemy close?
.oz_e:
  LDA O_K,Y
  CMP #K_DRONE
  BCC .oz_n
  CMP #K_SPIDER+1
  BCS .oz_n
  LDA O_X,Y
  SEC
  SBC O_X,X
  BCS .oz_a
  EOR #$FF
  ADC #1
.oz_a:
  CMP #10
  BCS .oz_n
  LDA O_Y,Y
  SEC
  SBC O_Y,X
  CLC
  ADC #12                      ; enemy feet - zap line in -12..12
  CMP #25
  BCS .oz_n
  LDA #180
  STA O_S,Y
  LDA #S_HIT
  PHY
  LDY O_X,X
  JSR BOOM_AT
  PLY
  LDX SLOT
.oz_k:
  STZ O_K,X
  RTS
.oz_n:
  INY
  CPY #NOB
  BCC .oz_e
  RTS

; A = kind, CX / CY: a shot in a free slot 9-13 (none free: no shot)
NEW_SHOT:
  LDY #9
.ns_l:
  PHA
  LDA O_K,Y
  BEQ .ns_f
  PLA
  INY
  CPY #NOB
  BCC .ns_l
  RTS
.ns_f:
  PLA
  STA O_K,Y
  LDA CX
  STA O_X,Y
  LDA CY
  STA O_Y,Y
  LDA #0
  STA O_XL,Y
  STA O_YL,Y
  STA O_T,Y
  STA O_S,Y
  STA O_A,Y
  RTS


; ===============================================================
;  ANIMATED TILES: conveyors and lifts, arcs, presses, the core
; ===============================================================
ANIM_TILES:
  INC HZT
  LDA HZT                      ; arcs: 64 frames on, 64 off; presses 32 / 32
  AND #$40
  BEQ .at_a
  LDA #1
.at_a:
  STA T0
  LDA HZT
  AND #$20
  BEQ .at_b
  LDA #2
.at_b:
  ORA T0
  CMP HZON
  BEQ .at_s
  STA HZON                     ; changed: arcs and presses at once
  JSR ANIM_ARCS
  JMP ANIM_PRESS
.at_s:
  LDA GF
  AND #3
  BNE .at_1
  INC ANIMP
  JMP ANIM_BELTS
.at_1:
  CMP #1
  BNE .at_2
  JMP ANIM_ARCS                ; the flicker of the arcs that are on
.at_2:
  CMP #3
  BNE .at_r
  JMP ANIM_CORE
.at_r:
  RTS

; conveyors and lifts: phase ANIMP
ANIM_BELTS:
  LDA ANIMP
  AND #3
  ASL A
  ASL A
  ASL A
  STA T7
  CLC
  ADC #<AN_CONVL
  STA PTR
  LDA #>AN_CONVL
  ADC #0
  STA PTR+1
  LDA #T_CONVL
  JSR PUT_PAT3
  LDA T7
  CLC
  ADC #<AN_CONVR
  STA PTR
  LDA #>AN_CONVR
  ADC #0
  STA PTR+1
  LDA #T_CONVR
  JSR PUT_PAT3
  LDA ANIMP                    ; the lift goes the other way round (up)
  EOR #3
  AND #3
  ASL A
  ASL A
  ASL A
  CLC
  ADC #<AN_LIFT
  STA PTR
  LDA #>AN_LIFT
  ADC #0
  STA PTR+1
  LDA #T_LIFT
  JMP PUT_PAT3

; arcs: on = pattern 0 or 1 (flicker), off = pattern 2
ANIM_ARCS:
  LDA GF
  AND #4
  LSR A
  LSR A
  STA T7                       ; 0 / 1
  LDA HZON
  AND #1
  STA CNT                      ; phase 0 on?
  LDA #T_ARCH0
  LDY #<AN_ARCH
  LDX #>AN_ARCH
  JSR .aa_one
  LDA #T_ARCV0
  LDY #<AN_ARCV
  LDX #>AN_ARCV
  JSR .aa_one
  LDA CNT
  EOR #1
  STA CNT
  LDA #T_ARCH1
  LDY #<AN_ARCH
  LDX #>AN_ARCH
  JSR .aa_one
  LDA #T_ARCV1
  LDY #<AN_ARCV
  LDX #>AN_ARCV
  ; fall into .aa_one
.aa_one:                       ; A = tile, X / Y = patterns: on (T7) or off
  PHA
  STY PTR
  STX PTR+1
  LDA #16
  LDY CNT
  BEQ .aa_o
  LDA T7
  ASL A
  ASL A
  ASL A
.aa_o:
  CLC
  ADC PTR
  STA PTR
  BCC .aa_p
  INC PTR+1
.aa_p:
  PLA
  JMP PUT_PAT3

; presses: phase 0 down when HZON bit 1 is set, phase 1 the other way round
ANIM_PRESS:
  LDA HZON
  AND #2
  EOR #2
  ASL A
  ASL A                        ; 0 = on, 8 = off
  PHA
  CLC
  ADC #<AN_PRESS
  STA PTR
  LDA #>AN_PRESS
  ADC #0
  STA PTR+1
  LDA #T_PRESS0
  JSR PUT_PAT3
  PLA
  EOR #8
  CLC
  ADC #<AN_PRESS
  STA PTR
  LDA #>AN_PRESS
  ADC #0
  STA PTR+1
  LDA #T_PRESS1
  JMP PUT_PAT3

; the core pulses (faster after the overload): colours through XLAT
ANIM_CORE:
  LDA GF
  LSR A
  LSR A
  LDY ESC
  BNE .ac_f
  LSR A
.ac_f:
  AND #3
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A                        ; phase x 32
  CLC
  ADC #<AN_CORE
  STA PTR
  LDA #>AN_CORE
  ADC #0
  STA PTR+1
  LDA #T_CORE0
  STA CNT
.ac_t:
  LDA CNT
  JSR PUT_COL3
  LDA PTR
  CLC
  ADC #8
  STA PTR
  BCC .ac_n
  INC PTR+1
.ac_n:
  INC CNT
  LDA CNT
  CMP #T_CORE3+1
  BNE .ac_t
  RTS

; A = tile: its 8 pattern bytes from PTR in the 3 thirds
PUT_PAT3:
  STA T4
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #VDP_WRITE_VRAM_BIT
  STA T5
  LDA T4
  ASL A
  ASL A
  ASL A
  STA T4
  LDA #3
  STA T6
.pp_t:
  LDA T4
  STA VREG
  LDA T5
  STA VREG
  LDY #0
.pp_b:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #8
  BNE .pp_b
  LDA T5
  CLC
  ADC #8
  STA T5
  DEC T6
  BNE .pp_t
  RTS

; A = tile: its 8 colour bytes (materials, through XLAT) from PTR in the 3 thirds
PUT_COL3:
  STA T4
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | $20)
  STA T5
  LDA T4
  ASL A
  ASL A
  ASL A
  STA T4
  LDA #3
  STA T6
.pc_t:
  LDA T4
  STA VREG
  LDA T5
  STA VREG
  LDY #0
.pc_b:
  LDA (PTR),Y
  TAX
  LDA XLAT,X
  STA VDATA
  INY
  CPY #8
  BNE .pc_b
  LDA T5
  CLC
  ADC #8
  STA T5
  DEC T6
  BNE .pc_t
  RTS


; ===============================================================
;  SPRITES: the runner / shuttle first, then the others in turn
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA O_K
  BEQ .bs_o
  LDA O_X
  STA OX
  LDA O_Y
  STA OY
  LDX #0
  JSR OBJ_SPR
  BCS .bs_o
  JSR ADD_SPR
.bs_o:
  LDA #NOB-1
  STA CNT
  LDX RR
.bs_l:
  STX SLOT
  LDA O_K,X
  BEQ .bs_n
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
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

; X = slot: ON / OC (carry set = not drawn this frame)
OBJ_SPR:
  LDY O_K,X
  LDA KCOL,Y
  STA OC
  LDA O_S,X                    ; stunned: flashes white
  BEQ .os_c
  LDA GF
  AND #4
  BEQ .os_c
  LDA #15
  STA OC
.os_c:
  CPY #K_HERO
  BEQ .os_hero
  CPY #K_SHIP
  BEQ .os_ship
  CPY #K_BOOM
  BEQ .os_boom
  LDA KPAT,Y
  CLC
  ADC O_A,X
  STA ON
  CPY #K_ZAP
  BNE .os_ok
  LDA O_D,X                    ; the stunner faces its way
  ASL A
  ASL A
  ADC ON
  STA ON
.os_ok:
  CLC
  RTS
.os_boom:
  LDA O_T,X
  AND #8
  LSR A
  ADC #PT_BOOM
  STA ON
  CLC
  RTS
.os_ship:
  LDA GF
  AND #4
  CLC
  ADC #PT_SHIP
  STA ON
  CLC
  RTS
.os_hero:
  LDA GSTATE
  CMP #1
  BNE .os_h1
  LDA PHASE                    ; the shuttle is the explosion (another slot)
  BEQ .os_no
  LDA #PT_DEAD
  STA ON
  CLC
  RTS
.os_h1:
  LDA CLIMB
  BEQ .os_h2
  LDA O_Y
  AND #4
  CLC
  ADC #PT_CLIMB
  STA ON
  CLC
  RTS
.os_h2:
  LDA O_D                      ; facing x 4
  ASL A
  ASL A
  STA T0
  LDA O_AIR
  BEQ .os_h3
  LDA #PT_JUMP
  CLC
  ADC T0
  STA ON
  CLC
  RTS
.os_h3:
  LDA JOYC                     ; running: two steps
  AND #12
  BEQ .os_h4
  LDA O_X
  AND #8
.os_h4:
  CLC
  ADC #PT_RUN
  ADC T0
  STA ON
  CLC
  RTS
.os_no:
  SEC
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from special forces)
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

; the tiles of the station in its colours (XLAT built by SET_STATION)
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
;  RECORDS ON THE SD (dev/lib_records.asm, see SD_SALVATAGGI.md)
;  8 best scores signed with 3 initials, kept in the zone
;  REC_ZONE of the save area (sector 32768 + zone * 16): two
;  copies (sectors 0 and 1 of the zone) written in turn.
;  Without the BIOS KEYB/SD ($4C at $FD18/$FD1B/$FD1E) the table
;  lives only in RAM.
;
;  The game defines:
;    REC_ZONE   fixed zone number of the game (1-127)
;    REC_RAM    $2A0 bytes of free RAM (buffer, table, variables)
;    REC_ROW    screen row of the table header (rows +1..+8 =
;               the table; the sign screen also uses rows -4,
;               -2 and +10..+12)
;    REC_WIPEN  rows cleared from REC_ROW for the table (>= 9)
;    REC_SROW   row of the table header on the sign screen (rows
;               -4, -2 and +10..+12 too); usually REC_ROW
;    REC_JOY2   $FF = both joysticks sign, 0 = the player's own
;    REC_NAME   16 bytes: name of the game, spaces at the end
;    REC_HEAD   header of the table, 0 at the end
;    REC_XLBL   label of the extra byte ("LEG "), 0 at the end
;    REC_XY     X = row, Y = column: VDP write address
;    REC_CLS    clears the screen for the sign screen
;    REC_SND    A = 0 letter changed, 1 initials confirmed
;  and has VDATA, P_JOY (2 bytes, 1 = pressed, bits UDLR B1 B2),
;  READ_JOY, HIDE_SPRITES, VINT, VDP_INT_OFF (waits for the next frame and
;  stops the NMI) and VDP_INT_ON.
;
;  Calls:
;    REC_INIT   at RESET (VDP interrupt off): reads the table
;    REC_CHECK  after the game over: REC_SC (4 BCD bytes, low
;               first), REC_EX (extra byte), REC_PL (player 0/1);
;               C = 1 if it entered the table (signed on the spot)
;    REC_SAVE   after the checks: one write, if anything changed
;    REC_TITLE  at the title: page 0 (the game's own) for 8 s
;    REC_TICK   every title frame: C = 1 when the page changes,
;               REC_PG = page to draw (0 game, 1 table)
;    REC_SHOW   draws the table (VDP interrupt off)
;    REC_WIPE   clears REC_WIPEN rows from REC_ROW (interrupt off)
;    REC_TAB    the table: 8 rows of 8 bytes, best first
;               (score 4 BCD bytes, 3 initials, extra byte)
; ===============================================================
SV_BUF     = REC_RAM           ; 512: one sector
REC_TAB    = REC_RAM+$200      ; 64: 8 rows x 8 bytes
SV_KEEP    = REC_RAM+$240      ; 31: $44-$4E and $0306-$0319 during the call
SV_OK      = REC_RAM+$260      ; 1 = the BIOS has the sector routines
SV_SEC     = REC_RAM+$261      ; sector of the zone (0-15)
SV_RW      = REC_RAM+$262      ; 0 read, 1 write
SV_VI      = REC_RAM+$263      ; VINT before the call
REC_CNT    = REC_RAM+$264      ; 2: write counter of the copy in RAM
REC_OLD    = REC_RAM+$266      ; copy to write next (the older one)
REC_V      = REC_RAM+$267      ; 1 = copy 0 was valid
REC_DIRTY  = REC_RAM+$268      ; 1 = the table changed
REC_SC     = REC_RAM+$269      ; 4: score to check (BCD, low first)
REC_EX     = REC_RAM+$26D      ; extra byte of the row
REC_PL     = REC_RAM+$26E      ; player who signs (0 / 1)
REC_POS    = REC_RAM+$26F      ; offset of the row being signed
REC_CUR    = REC_RAM+$270      ; initial being edited (0-2)
REC_J      = REC_RAM+$271      ; joystick, the one before, new presses
REC_JP     = REC_RAM+$272
REC_JN     = REC_RAM+$273
REC_RPT    = REC_RAM+$274      ; frames before the letter repeats
REC_TMO    = REC_RAM+$275      ; 2: frames before the initials confirm by themselves
REC_NZ     = REC_RAM+$277      ; 1 = a digit was printed (no more blanks)
REC_K      = REC_RAM+$278
REC_LAST   = REC_RAM+$279      ; 3: initials signed last
REC_SL     = REC_RAM+$27C      ; 2: checksum
REC_SH     = REC_RAM+$27D
REC_PT     = REC_RAM+$27E      ; 2: frames left on this title page
REC_PG     = REC_RAM+$280      ; title page shown (0 game, 1 table)
REC_T      = REC_RAM+$281
REC_R0     = REC_RAM+$282      ; row of the table header being drawn

REC_AYL    = $D384             ; AY latches (left, right) and data
REC_AYR    = $D380
REC_PAGE_T = 480               ; frames of the title page of the game (8 s)
REC_TAB_T  = 300               ; frames of the table (5 s)
REC_WAITT  = 1800              ; 30 s without a key: the initials are confirmed

; sector header: signature, version, zone, type 1 = records,
; 1 table, 8 rows, 8 bytes per row
REC_HDR:
  .byte "MVSV",1,REC_ZONE,1,1,8,8
REC_LETTERS:
  .byte "ABCDEFGHIJKLMNOPQRSTUVWXYZ ."
REC_NLET = 28

; ---------------------------------------------------------------
;  SV_CALL: A = 0 read / 1 write sector SV_SEC of the zone in
;  SV_BUF. C = 0 ok, 1 error or no BIOS. Keeps the game's RAM
;  that the BIOS driver uses; the NMI is off during the call.
; ---------------------------------------------------------------
SV_CALL:
  STA SV_RW
  LDA SV_OK
  BNE .sv_go
  SEC
  RTS
.sv_go:
  LDA VINT
  STA SV_VI
  JSR VDP_INT_OFF              ; no NMI while $44-$4E belong to the driver
  LDX #8                       ; both AYs silent (the last note would hang)
.sv_sil:
  STX REC_AYL
  STZ REC_AYL+1
  STX REC_AYR
  STZ REC_AYR+1
  INX
  CPX #11
  BNE .sv_sil
  LDX #10
.sv_k1:
  LDA $44,X
  STA SV_KEEP,X
  DEX
  BPL .sv_k1
  LDX #19
.sv_k2:
  LDA $0306,X
  STA SV_KEEP+11,X
  DEX
  BPL .sv_k2
  JSR $FD1E                    ; SD init: always (the game may have changed sd_type)
  BCS .sv_done
  LDA SV_SEC                   ; SD_LBA = 32768 + zone * 16 + sector
  AND #$0F
  ORA #((REC_ZONE<<4)&$F0)
  STA $0316
  LDA #($80+(REC_ZONE>>4))
  STA $0317
  STZ $0318
  STZ $0319
  LDX #<SV_BUF
  LDY #>SV_BUF
  LDA SV_RW
  BNE .sv_w
  JSR $FD18
  BRA .sv_done
.sv_w:
  JSR $FD1B
.sv_done:
  PHP
  LDX #10
.sv_r1:
  LDA SV_KEEP,X
  STA $44,X
  DEX
  BPL .sv_r1
  LDX #19
.sv_r2:
  LDA SV_KEEP+11,X
  STA $0306,X
  DEX
  BPL .sv_r2
  LDA SV_VI
  BEQ .sv_e
  JSR VDP_INT_ON
.sv_e:
  PLP
  RTS

; ---------------------------------------------------------------
;  REC_INIT: the BIOS check, then the newest valid copy (or the
;  empty table)
; ---------------------------------------------------------------
REC_INIT:
  STZ SV_OK
  LDA $FD18
  CMP #$4C
  BNE .ri_nb
  LDA $FD1B
  CMP #$4C
  BNE .ri_nb
  LDA $FD1E
  CMP #$4C
  BNE .ri_nb
  INC SV_OK
.ri_nb:
  LDX #63                      ; empty table: score 0, "---"
.ri_e:
  TXA
  AND #7
  CMP #4
  BCC .ri_z
  CMP #7
  BEQ .ri_z
  LDA #'-'
  BRA .ri_s
.ri_z:
  LDA #0
.ri_s:
  STA REC_TAB,X
  DEX
  BPL .ri_e
  LDA #'A'
  STA REC_LAST
  STA REC_LAST+1
  STA REC_LAST+2
  STZ REC_CNT
  STZ REC_CNT+1
  STZ REC_OLD
  STZ REC_V
  STZ REC_DIRTY
  STZ REC_PG
  STZ SV_SEC                   ; copy 0
  LDA #0
  JSR SV_CALL
  BCS .ri_1
  JSR REC_VALID
  BCS .ri_1
  JSR REC_TAKE
  LDA #1                       ; the next write goes to copy 1
  STA REC_OLD
  STA REC_V
.ri_1:
  LDA #1                       ; copy 1
  STA SV_SEC
  LDA #0
  JSR SV_CALL
  BCS .ri_e2
  JSR REC_VALID
  BCS .ri_e2
  LDA REC_V                    ; both valid: the higher counter wins
  BEQ .ri_t1
  LDA SV_BUF+11
  CMP REC_CNT+1
  BCC .ri_e2
  BNE .ri_t1
  LDA SV_BUF+10
  CMP REC_CNT
  BCC .ri_e2
  BEQ .ri_e2
.ri_t1:
  JSR REC_TAKE
  STZ REC_OLD                  ; the next write goes to copy 0
.ri_e2:
  RTS

; SV_BUF valid for this game? C = 0 yes
REC_VALID:
  LDX #9
.rv_h:
  LDA SV_BUF,X
  CMP REC_HDR,X
  BNE .rv_no
  DEX
  BPL .rv_h
  JSR REC_SUM
  LDA REC_SL
  CMP SV_BUF+510
  BNE .rv_no
  LDA REC_SH
  CMP SV_BUF+511
  BNE .rv_no
  CLC
  RTS
.rv_no:
  SEC
  RTS

; rows and counter of SV_BUF into RAM
REC_TAKE:
  LDX #63
.rt_l:
  LDA SV_BUF+32,X
  STA REC_TAB,X
  DEX
  BPL .rt_l
  LDA SV_BUF+10
  STA REC_CNT
  LDA SV_BUF+11
  STA REC_CNT+1
  RTS

; 16-bit sum of the bytes 0-509 of SV_BUF -> REC_SL / REC_SH
REC_SUM:
  STZ REC_SL
  STZ REC_SH
  LDX #0
.rs_a:
  LDA SV_BUF,X
  CLC
  ADC REC_SL
  STA REC_SL
  BCC .rs_a1
  INC REC_SH
.rs_a1:
  INX
  BNE .rs_a
.rs_b:
  LDA SV_BUF+256,X
  CLC
  ADC REC_SL
  STA REC_SL
  BCC .rs_b1
  INC REC_SH
.rs_b1:
  INX
  CPX #254
  BNE .rs_b
  RTS

; ---------------------------------------------------------------
;  REC_SAVE: if the table changed, one write into the older copy
;  (C = 1 if it could not be written: the table stays in RAM)
; ---------------------------------------------------------------
REC_SAVE:
  LDA REC_DIRTY
  BNE .rv_go
  CLC
  RTS
.rv_go:
  STZ REC_DIRTY
  LDX #0
.rw_c:
  STZ SV_BUF,X
  STZ SV_BUF+256,X
  INX
  BNE .rw_c
  LDX #9
.rw_h:
  LDA REC_HDR,X
  STA SV_BUF,X
  DEX
  BPL .rw_h
  LDA REC_CNT                  ; counter + 1
  CLC
  ADC #1
  STA SV_BUF+10
  LDA REC_CNT+1
  ADC #0
  STA SV_BUF+11
  LDX #15
.rw_n:
  LDA REC_NAME,X
  STA SV_BUF+16,X
  DEX
  BPL .rw_n
  LDX #63
.rw_t:
  LDA REC_TAB,X
  STA SV_BUF+32,X
  DEX
  BPL .rw_t
  JSR REC_SUM
  LDA REC_SL
  STA SV_BUF+510
  LDA REC_SH
  STA SV_BUF+511
  LDA REC_OLD
  STA SV_SEC
  LDA #1
  JSR SV_CALL
  BCS .rw_e
  LDA SV_BUF+10                ; written: this copy is now the newer one
  STA REC_CNT
  LDA SV_BUF+11
  STA REC_CNT+1
  LDA REC_OLD
  EOR #1
  STA REC_OLD
  CLC
.rw_e:
  RTS

; ---------------------------------------------------------------
;  REC_CHECK: REC_SC enters the table? Then the row is inserted
;  and signed (REC_SIGN). C = 1 if it entered.
; ---------------------------------------------------------------
REC_CHECK:
  LDA REC_SC
  ORA REC_SC+1
  ORA REC_SC+2
  ORA REC_SC+3
  BEQ .rc_no                   ; no points, no record
  LDX #0
.rc_f:
  LDA REC_SC+3                 ; higher than this row? (equal = below it)
  CMP REC_TAB+3,X
  BCC .rc_nx
  BNE .rc_in
  LDA REC_SC+2
  CMP REC_TAB+2,X
  BCC .rc_nx
  BNE .rc_in
  LDA REC_SC+1
  CMP REC_TAB+1,X
  BCC .rc_nx
  BNE .rc_in
  LDA REC_SC
  CMP REC_TAB,X
  BEQ .rc_nx
  BCS .rc_in
.rc_nx:
  TXA
  CLC
  ADC #8
  TAX
  CPX #64
  BNE .rc_f
.rc_no:
  CLC
  RTS
.rc_in:
  STX REC_POS
  LDY #56                      ; the rows below move down one place
.rc_sh:
  CPY REC_POS
  BEQ .rc_put
  DEY
  LDA REC_TAB,Y
  STA REC_TAB+8,Y
  BRA .rc_sh
.rc_put:
  LDA REC_SC
  STA REC_TAB,X
  LDA REC_SC+1
  STA REC_TAB+1,X
  LDA REC_SC+2
  STA REC_TAB+2,X
  LDA REC_SC+3
  STA REC_TAB+3,X
  LDA REC_LAST
  STA REC_TAB+4,X
  LDA REC_LAST+1
  STA REC_TAB+5,X
  LDA REC_LAST+2
  STA REC_TAB+6,X
  LDA REC_EX
  STA REC_TAB+7,X
  LDA #1
  STA REC_DIRTY
  JSR REC_SIGN
  LDX REC_POS
  LDA REC_TAB+4,X
  STA REC_LAST
  LDA REC_TAB+5,X
  STA REC_LAST+1
  LDA REC_TAB+6,X
  STA REC_LAST+2
  SEC
  RTS

; ---------------------------------------------------------------
;  REC_SIGN: the sign screen. UP / DOWN change the letter,
;  LEFT / RIGHT move, a button moves on (on the third letter it
;  confirms); after 30 s without a key it confirms by itself.
; ---------------------------------------------------------------
REC_SIGN:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES               ; nothing of the game over the table
  JSR REC_CLS
  LDX #REC_SROW-4
  LDY #11
  LDA #(RT_NEW-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW-2
  LDY #12
  LDA #(RT_PLAYER-REC_TXT)
  JSR REC_PUTS
  LDA REC_PL
  CLC
  ADC #'1'
  STA VDATA
  LDA #REC_SROW
  STA REC_R0
  JSR REC_SHOW_R
  LDX #REC_SROW+10
  LDY #7
  LDA #(RT_H1-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+11
  LDY #7
  LDA #(RT_H2-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+12
  LDY #7
  LDA #(RT_H3-REC_TXT)
  JSR REC_PUTS
  JSR VDP_INT_ON
  STZ REC_CUR
  STZ REC_RPT
  LDA #$FF                     ; everything held: a key counts once released
  STA REC_JP
  LDA #<REC_WAITT
  STA REC_TMO
  LDA #>REC_WAITT
  STA REC_TMO+1
.sg_l:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA P_JOY+1
  AND #REC_JOY2
  STA REC_T
  LDX REC_PL
  LDA P_JOY,X
  ORA REC_T
  AND #$3F
  STA REC_J
  LDA REC_JP
  EOR #$FF
  AND REC_J
  STA REC_JN
  LDA REC_J
  STA REC_JP
  BEQ .sg_nk
  LDA #<REC_WAITT              ; a key: the 30 s start again
  STA REC_TMO
  LDA #>REC_WAITT
  STA REC_TMO+1
.sg_nk:
  LDA REC_JN                   ; a button or RIGHT: the next letter
  AND #$38
  BEQ .sg_nr
  LDA REC_CUR
  CMP #2
  BCC .sg_mr
  LDA REC_JN
  AND #$30
  BEQ .sg_nr
  JMP .sg_end                  ; a button on the third letter: done
.sg_mr:
  INC REC_CUR
  BRA .sg_snd
.sg_nr:
  LDA REC_JN                   ; LEFT: back one letter
  AND #$04
  BEQ .sg_ud
  LDA REC_CUR
  BEQ .sg_ud
  DEC REC_CUR
  BRA .sg_snd
.sg_ud:
  LDA REC_JN                   ; UP / DOWN: at once, then repeated
  AND #$03
  BEQ .sg_hold
  LDA #18
  STA REC_RPT
  BRA .sg_chg
.sg_hold:
  LDA REC_J
  AND #$03
  BEQ .sg_draw
  DEC REC_RPT
  BNE .sg_draw
  LDA #5
  STA REC_RPT
.sg_chg:
  JSR REC_LETTER
.sg_snd:
  LDA #0
  JSR REC_SND
.sg_draw:
  LDA REC_TMO                  ; the letter being edited blinks
  AND #$10
  JSR REC_INITS
  JSR VDP_INT_ON
  LDA REC_TMO                  ; 30 s without a key: done
  BNE .sg_t
  DEC REC_TMO+1
  BMI .sg_end
.sg_t:
  DEC REC_TMO
  JMP .sg_l
.sg_end:
  JSR VDP_INT_OFF
  LDA #0
  JSR REC_INITS
  JSR VDP_INT_ON
  LDA #1
  JSR REC_SND
  LDA #90                      ; the signed table stays 1.5 s
  STA REC_T
.sg_w:
  JSR VDP_INT_OFF
  JSR VDP_INT_ON
  DEC REC_T
  BNE .sg_w
  RTS

; the letter REC_CUR of the row REC_POS: UP next, DOWN previous
REC_LETTER:
  LDA REC_POS
  CLC
  ADC REC_CUR
  TAX                          ; X = row + letter - 4: REC_TAB+4,X
  LDY #REC_NLET-1
.rl_f:
  LDA REC_LETTERS,Y
  CMP REC_TAB+4,X
  BEQ .rl_k
  DEY
  BPL .rl_f
  LDY #REC_NLET-1              ; not a letter ("---"): UP gives A
.rl_k:
  LDA REC_JN
  ORA REC_J
  AND #$01
  BEQ .rl_dn
  INY
  CPY #REC_NLET
  BCC .rl_s
  LDY #0
  BRA .rl_s
.rl_dn:
  DEY
  BPL .rl_s
  LDY #REC_NLET-1
.rl_s:
  LDA REC_LETTERS,Y
  STA REC_TAB+4,X
  RTS

; the initials of the row REC_POS; A <> 0: the letter REC_CUR as "_"
REC_INITS:
  STA REC_K
  LDA REC_POS
  LSR A
  LSR A
  LSR A
  SEC                          ; row REC_R0 + 1 + place
  ADC REC_R0
  TAX
  LDY #7
  JSR REC_XY
  LDX REC_POS
  STZ REC_T
.ri_l:
  LDA REC_TAB+4,X
  LDY REC_T
  CPY REC_CUR
  BNE .ri_p
  LDY REC_K
  BEQ .ri_p
  LDA #'_'
.ri_p:
  STA VDATA
  INX
  INC REC_T
  LDA REC_T
  CMP #3
  BNE .ri_l
  RTS

; ---------------------------------------------------------------
;  title pages
; ---------------------------------------------------------------
REC_TITLE:
  STZ REC_PG

  LDA #<REC_PAGE_T
  STA REC_PT
  LDA #>REC_PAGE_T
  STA REC_PT+1
  RTS

REC_TICK:
  LDA REC_PT
  BNE .tk_d
  LDA REC_PT+1
  BEQ .tk_sw
  DEC REC_PT+1
.tk_d:
  DEC REC_PT
  CLC
  RTS
.tk_sw:
  LDA REC_PG                   ; the other page: the table for 5 s, the game's for 8 s
  EOR #1
  STA REC_PG
  BEQ .tk_g
  LDA #<REC_TAB_T
  STA REC_PT
  LDA #>REC_TAB_T
  STA REC_PT+1
  SEC
  RTS
.tk_g:
  JSR REC_TITLE
  LDA #0
  STA REC_PG                   ; (REC_TITLE keeps page 0)
  SEC
  RTS

; ---------------------------------------------------------------
;  REC_SHOW: header and 8 rows
;    " 1. ABC  00123450  LEG 5"  (columns 4, 7, 12, 22)
; ---------------------------------------------------------------
REC_SHOW:
  LDA #REC_ROW
  STA REC_R0
REC_SHOW_R:                    ; the table with its header on row REC_R0
  LDA REC_POS                  ; kept: the row being signed
  PHA
  JSR REC_WIPE_R
  LDX #0                       ; header, centred
.sh_n:
  LDA REC_HEAD,X
  BEQ .sh_c
  INX
  BRA .sh_n
.sh_c:
  STX REC_T
  LDA #32
  SEC
  SBC REC_T
  LSR A
  TAY
  LDX REC_R0
  JSR REC_XY
  LDX #0
.sh_h:
  LDA REC_HEAD,X
  BEQ .sh_r
  STA VDATA
  INX
  BRA .sh_h
.sh_r:
  LDA #0
.sh_l:
  STA REC_POS
  JSR REC_LINE
  LDA REC_POS
  CLC
  ADC #8
  CMP #64
  BNE .sh_l
  PLA
  STA REC_POS
  RTS

; the row REC_POS
REC_LINE:
  LSR A
  LSR A
  LSR A
  STA REC_K
  SEC                          ; row REC_R0 + 1 + place
  ADC REC_R0
  TAX
  LDY #4
  JSR REC_XY
  LDA REC_K                    ; place
  CLC
  ADC #'1'
  JSR REC_OUT
  LDA #'.'
  JSR REC_OUT
  LDA #' '
  JSR REC_OUT
  LDX REC_POS
  LDA REC_TAB+4,X              ; initials
  JSR REC_OUT
  LDA REC_TAB+5,X
  JSR REC_OUT
  LDA REC_TAB+6,X
  JSR REC_OUT
  LDA REC_TAB,X                ; an empty row: no score
  ORA REC_TAB+1,X
  ORA REC_TAB+2,X
  ORA REC_TAB+3,X
  BEQ .ln_e
  LDA #' '
  JSR REC_OUT
  JSR REC_OUT
  STZ REC_NZ                   ; score: 8 digits, no leading zeros
  TXA
  CLC
  ADC #3
  TAY
  LDA #4
  STA REC_K
.ln_b:
  LDA REC_TAB,Y
  LSR A
  LSR A
  LSR A
  LSR A
  JSR REC_DIG
  LDA REC_K
  CMP #1
  BNE .ln_lo
  STA REC_NZ                   ; the last digit always shows
.ln_lo:
  LDA REC_TAB,Y
  AND #$0F
  JSR REC_DIG
  DEY
  DEC REC_K
  BNE .ln_b
  LDX REC_POS                  ; the extra byte with its label
  LDA REC_TAB+7,X
  BEQ .ln_e
  LDA #' '
  JSR REC_OUT
  JSR REC_OUT
  LDX #0
.ln_x:
  LDA REC_XLBL,X
  BEQ .ln_v
  JSR REC_OUT
  INX
  BRA .ln_x
.ln_v:
  LDX REC_POS
  LDA REC_TAB+7,X
  JMP REC_DEC
.ln_e:
  RTS

; A = digit 0-9; a blank while no digit has been printed
REC_DIG:
  CMP #0
  BNE .dg_p
  LDA REC_NZ
  BNE .dg_0
  LDA #' '
  JMP REC_OUT
.dg_0:
  LDA #0
.dg_p:
  ORA #'0'
  JSR REC_OUT
  LDA #1
  STA REC_NZ
  RTS

; A = 0-255 in decimal, no leading zeros
REC_DEC:
  STZ REC_NZ
  LDX #'0'-1
.dc_h:
  INX
  SEC
  SBC #100
  BCS .dc_h
  ADC #100
  CPX #'0'
  BEQ .dc_t
  PHA
  TXA
  JSR REC_OUT
  PLA
  INC REC_NZ
.dc_t:
  LDX #'0'-1
.dc_t1:
  INX
  SEC
  SBC #10
  BCS .dc_t1
  ADC #10
  LDY REC_NZ
  BNE .dc_tp
  CPX #'0'
  BEQ .dc_u
.dc_tp:
  PHA
  TXA
  JSR REC_OUT
  PLA
.dc_u:
  ORA #'0'
  ; fall into REC_OUT

; one character to the VDP. Every write of the table goes through here, so two writes
; are at least 14 cycles apart: while it draws the screen the TMS9918A needs about 8 us
; between two accesses, or a character is lost (the emulators do not show it)
REC_OUT:
  STA VDATA
  RTS

; REC_WIPEN rows from REC_ROW blank (REC_WIPE_R: from REC_R0)
REC_WIPE:
  LDA #REC_ROW
  STA REC_R0
REC_WIPE_R:
  LDA REC_R0
  STA REC_K
  CLC
  ADC #REC_WIPEN
  STA REC_T
.wp_r:
  LDX REC_K
  LDY #0
  JSR REC_XY
  LDX #32
  LDA #' '
.wp_c:
  STA VDATA                    ; 11 cycles per write (see REC_OUT)
  NOP
  DEX
  BNE .wp_c
  INC REC_K
  LDA REC_K
  CMP REC_T
  BNE .wp_r
  RTS

; X = row, Y = column, A = offset in REC_TXT: the text up to 0
REC_PUTS:
  PHA
  JSR REC_XY
  PLX
.pu_l:
  LDA REC_TXT,X
  BEQ .pu_e
  STA VDATA
  INX
  BRA .pu_l
.pu_e:
  RTS

REC_TXT:
RT_NEW:    .byte "NEW RECORD",0
RT_PLAYER: .byte "PLAYER ",0
RT_H1:     .byte "UP/DOWN    LETTER",0
RT_H2:     .byte "LEFT/RIGHT MOVE",0
RT_H3:     .byte "BUTTON     NEXT/OK",0
; ===============================================================
;  TABLES
; ===============================================================
SC_COL:     .byte 1,25                         ; score of player 1 / 2: column on row 1
BITS:       .byte 1,2,4,8,16,32,64,128
; class -> solid (walls, platforms, conveyors, crumbling floors, the hatch)
SOLIDT:     .byte 0,1,0,1,1,0,0,0,0,0,1,0,1,0,0,0
; arcs and presses: (class - 6) x 4 + HZON -> 1 = deadly now
LETHAL:     .byte 0,1,0,1, 1,0,1,0, 0,0,1,1, 1,1,0,0
; the 4 points of the runner checked against the tiles
HK_DX:      .byte $FD,3,$FD,3
HK_DY:      .byte 2,2,13,13
AHEAD:      .byte 7,$F8                        ; enemies: point ahead (right / left)
ZAP_DX:     .byte 10,$F6                       ; stunner: start from the runner
ZAP_V:      .byte 4,$FC                        ;          speed

; per kind:          -  hero dron jump spark turr spid bolt zap ship rock figh guns mine shot ebol boom
KSPD:       .byte 0, 0,  $C0, $C0, $80, 0,   $80, 0,   0,  0,   0,   0,   0,   0,   0,   0,   0
KSPDH:      .byte 0, 0,  0,   0,   1,   0,   0,   0,   0,  0,   0,   0,   0,   0,   0,   0,   0
KCOL:       .byte 0, 9,  7,   3,   11,  14,  13,  8,   15, 15,  10,  8,   13,  6,   11,  9,   11
KPAT:       .byte 0, 0,  PT_DRONE, PT_JUMPER, PT_SPARK, PT_TURRET, PT_SPIDER, PT_BOLT, PT_ZAP, PT_SHIP
            .byte PT_ROCK, PT_FIGHTER, PT_GUNSHIP, PT_MINE, PT_SHOT, PT_BOLT, PT_BOOM
KHP:        .byte 0, 0,  0,   0,   0,   0,   0,   0,   0,  0,   1,   1,   3,   2,   0,   0,   0
KPTS_L:     .byte 0, 0,  0,   0,   0,   0,   0,   0,   0,  0,   $50, $00, $00, $50, 0,   0,   0
KPTS_M:     .byte 0, 0,  0,   0,   0,   0,   0,   0,   0,  0,   $00, $01, $02, $01, 0,   0,   0
OBJ_JT:     .word OB_NONE, OB_NONE, OB_DRONE, OB_JUMPER, OB_SPARK, OB_TURRET, OB_SPIDER, OB_BOLT, OB_ZAP
            .word OB_NONE, OB_ROCK, OB_FIGHTER, OB_GUNSHIP, OB_MINE, OB_SHOT, OB_EBOLT, OB_BOOM

; space: kinds that come per station (8 each)
SPAWNK:     .byte 10,10,11,10,11,10,10,11
            .byte 10,11,13,10,11,13,10,11
            .byte 10,11,12,10,11,13,11,10
            .byte 11,11,12,13,10,11,12,10
            .byte 10,11,12,13,11,12,13,10
            .byte 11,12,13,11,12,13,10,11
            .byte 12,11,13,12,11,13,12,10
            .byte 11,12,13,12,11,13,12,13

; fighters: their wave around the base row
SINE:
  .byte $00,$02,$05,$07,$09,$0B,$0D,$0F,$11,$13,$14,$15,$16,$17,$18,$18
  .byte $18,$18,$18,$17,$16,$15,$14,$13,$11,$0F,$0D,$0B,$09,$07,$05,$02
  .byte $00,$FE,$FB,$F9,$F7,$F5,$F3,$F1,$EF,$ED,$EC,$EB,$EA,$E9,$E8,$E8
  .byte $E8,$E8,$E8,$E9,$EA,$EB,$EC,$ED,$EF,$F1,$F3,$F5,$F7,$F9,$FB,$FE
; the rows of the map
MROW_LO: .byte <(MAP+0),<(MAP+32),<(MAP+64),<(MAP+96),<(MAP+128),<(MAP+160),<(MAP+192),<(MAP+224),<(MAP+256),<(MAP+288),<(MAP+320),<(MAP+352),<(MAP+384),<(MAP+416),<(MAP+448),<(MAP+480),<(MAP+512),<(MAP+544),<(MAP+576),<(MAP+608),<(MAP+640)
MROW_HI: .byte >(MAP+0),>(MAP+32),>(MAP+64),>(MAP+96),>(MAP+128),>(MAP+160),>(MAP+192),>(MAP+224),>(MAP+256),>(MAP+288),>(MAP+320),>(MAP+352),>(MAP+384),>(MAP+416),>(MAP+448),>(MAP+480),>(MAP+512),>(MAP+544),>(MAP+576),>(MAP+608),>(MAP+640)

; title: runner, stunner, fighter, gunship, mine, drone, spark  (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 9*8-5,11*8-5,13*8-5,15*8-5,17*8-5,19*8-5,19*8-5
TITLE_SX:   .byte 32,32,32,32,32,24,224
TITLE_SN:   .byte PT_RUN,PT_ZAP,PT_FIGHTER,PT_GUNSHIP,PT_MINE,PT_DRONE,PT_SPARK
TITLE_SC:   .byte $09,$0F,$08,$0D,$06,$07,$0B

SHINT_LO:   .byte <TXT_H0,<TXT_H1,<TXT_H2,<TXT_H3,<TXT_H4,<TXT_H5,<TXT_H6,<TXT_H7
SHINT_HI:   .byte >TXT_H0,>TXT_H1,>TXT_H2,>TXT_H3,>TXT_H4,>TXT_H5,>TXT_H6,>TXT_H7

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 9,7,"RUNNER  B1 = JUMP",0
  .byte 11,7,"STUNNER B2 = STUN",0
  .byte 13,7,"FIGHTER         100",0
  .byte 15,7,"GUNSHIP         200",0
  .byte 17,7,"MINE            150",0
  .byte 19,8,"THEY GUARD THE CORE",0
  .byte 21,2,"TOUCH THE CORE AND RUN BACK",0
  .byte 22,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_PLAYER:
  .byte 7,12,"PLAYER ",0
  .byte $FF
TXT_STATION:
  .byte 10,11,"STATION ",0
  .byte $FF
TXT_CORE:
  .byte "CORE ",0
TXT_CLEAR:
  .byte 9,7,"STATION DESTROYED",0
  .byte $FF
TXT_BONUS:
  .byte 12,10,"BONUS ",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0
  .byte $FF
TXT_H0:
  .byte 17,4,"DRONES PATROL THE FLOORS",0
  .byte 19,7,"CLIMB THE LADDERS",0
  .byte $FF
TXT_H1:
  .byte 17,7,"CONVEYORS PUSH YOU",0
  .byte 19,6,"JUMPERS LEAP AT YOU",0
  .byte $FF
TXT_H2:
  .byte 17,4,"CROSS THE ARCS WHEN OFF",0
  .byte 19,7,"TURRETS DROP BOLTS",0
  .byte $FF
TXT_H3:
  .byte 17,7,"LIFTS CARRY YOU UP",0
  .byte 19,7,"SPARKS FLY ACROSS",0
  .byte $FF
TXT_H4:
  .byte 17,7,"OLD FLOORS CRUMBLE",0
  .byte 19,7,"DO NOT STAND STILL",0
  .byte $FF
TXT_H5:
  .byte 17,3,"PRESSES COME DOWN IN TURN",0
  .byte 19,8,"WATCH THE TIMING",0
  .byte $FF
TXT_H6:
  .byte 17,4,"SPIDERS DROP FROM ABOVE",0
  .byte 19,7,"STUN THEM AND RUN",0
  .byte $FF
TXT_H7:
  .byte 17,8,"THE LAST STATION",0
  .byte 19,7,"EVERYTHING AT ONCE",0
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
SONGP_LO:      .byte <M0_LEAD,<M0_HARM,<M0_BASS,<M0_DRUM, <M1_LEAD,<M1_HARM,<M1_BASS,<M1_DRUM, <M2_LEAD,<M2_HARM,<M2_BASS,<M2_DRUM
SONGP_HI:      .byte >M0_LEAD,>M0_HARM,>M0_BASS,>M0_DRUM, >M1_LEAD,>M1_HARM,>M1_BASS,>M1_DRUM, >M2_LEAD,>M2_HARM,>M2_BASS,>M2_DRUM

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

; three tunes composed for this game
;   C2 1 E2 5 F2 6 A2 10 B2 12 C3 13 D3 15 E3 17 F3 18 G3 20 A3 22 B3 24 C4 25 D4 27 E4 29
;   G4 32 A4 34 B4 36 C5 37 D5 39 E5 41 G5 44 A5 46 C6 49 E6 53
; a station: A minor, a cold motif over a pulsing bass (about 4.3 seconds)
M0_LEAD:
  .byte 34,8, 41,8, 39,8, 41,8, 44,16, 41,8, 39,8
  .byte 37,8, 39,8, 36,16, 34,32
  .byte 41,8, 44,8, 46,16, 44,8, 41,8, 39,16
  .byte 37,8, 36,8, 34,48
  .byte $FF
M0_HARM:
  .byte 22,64, 18,64, 17,64, 22,64
  .byte $FF
M0_BASS:
  .byte 10,12, 10,4, 22,8, 10,8, 10,12, 10,4, 22,8, 10,8
  .byte 6,12, 6,4, 18,8, 6,8, 6,12, 6,4, 18,8, 6,8
  .byte 5,12, 5,4, 17,8, 5,8, 5,12, 5,4, 17,8, 5,8
  .byte 10,12, 10,4, 22,8, 10,8, 10,32
  .byte $FF
M0_DRUM:
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8, 1,8, 4,24
  .byte $FF
; station destroyed: a short fanfare in C (about 1.6 seconds)
M1_LEAD:
  .byte 37,6, 41,6, 44,6, 49,18, 0,6, 46,6, 49,6, 53,36
  .byte $FF
M1_HARM:
  .byte 32,18, 36,18, 37,24, 41,36
  .byte $FF
M1_BASS:
  .byte 13,18, 20,18, 13,24, 1,36
  .byte $FF
M1_DRUM:
  .byte 2,6, 2,6, 2,6, 1,18, 3,6, 3,6, 1,24, 4,24
  .byte $FF
; title: E minor, a slow climb (about 3.2 seconds)
M2_LEAD:
  .byte 41,12, 44,12, 49,24, 46,12, 44,12, 41,24
  .byte 39,12, 41,12, 44,12, 39,12, 36,48
  .byte $FF
M2_HARM:
  .byte 29,48, 27,48, 25,48, 24,48
  .byte $FF
M2_BASS:
  .byte 5,24, 17,24, 3,24, 15,24, 1,24, 13,24, 12,24, 24,24
  .byte $FF
M2_DRUM:
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 4,24
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
; Core Runner: generated by dev/gen_core_runner.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_RUN = 0
PT_JUMP = 16
PT_CLIMB = 24
PT_DEAD = 32
PT_DRONE = 36
PT_JUMPER = 44
PT_SPARK = 52
PT_TURRET = 60
PT_SPIDER = 68
PT_BOLT = 76
PT_ZAP = 80
PT_SHIP = 88
PT_ROCK = 96
PT_FIGHTER = 104
PT_GUNSHIP = 112
PT_MINE = 120
PT_SHOT = 128
PT_BOOM = 132
SPR_PAGES = 5
SPRITES:
  .byte $00,$00,$03,$07,$0F,$0F,$07,$1F,$3B,$3B,$3B,$03,$06,$0C,$18,$1C
  .byte $00,$00,$C0,$E0,$10,$10,$E0,$E0,$E0,$D0,$D0,$C0,$60,$30,$18,$1C
  .byte $00,$00,$03,$07,$08,$08,$07,$07,$07,$0B,$0B,$03,$06,$0C,$18,$38
  .byte $00,$00,$C0,$E0,$F0,$F0,$E0,$F8,$DC,$DC,$DC,$C0,$60,$30,$18,$38
  .byte $00,$00,$03,$07,$0F,$0F,$07,$1F,$3B,$3B,$3B,$03,$03,$03,$03,$07
  .byte $00,$00,$C0,$E0,$10,$10,$E0,$E0,$E0,$D0,$D0,$C0,$C0,$60,$60,$70
  .byte $00,$00,$03,$07,$08,$08,$07,$07,$07,$0B,$0B,$03,$03,$06,$06,$0E
  .byte $00,$00,$C0,$E0,$F0,$F0,$E0,$F8,$DC,$DC,$DC,$C0,$C0,$C0,$C0,$E0
  .byte $00,$00,$03,$07,$0F,$0F,$07,$1F,$3B,$3B,$3B,$03,$06,$0C,$1C,$00
  .byte $00,$00,$C0,$E0,$10,$10,$E0,$E0,$E0,$D0,$D0,$C0,$30,$1C,$00,$00
  .byte $00,$00,$03,$07,$08,$08,$07,$07,$07,$0B,$0B,$03,$0C,$38,$00,$00
  .byte $00,$00,$C0,$E0,$F0,$F0,$E0,$F8,$DC,$DC,$DC,$C0,$60,$30,$38,$00
  .byte $00,$00,$23,$27,$37,$17,$0F,$07,$0F,$0F,$07,$03,$06,$06,$06,$07
  .byte $00,$00,$C4,$E4,$EC,$E8,$F0,$E0,$F0,$F0,$E0,$C0,$60,$30,$00,$00
  .byte $00,$00,$23,$27,$37,$17,$0F,$07,$0F,$0F,$07,$03,$06,$0C,$00,$00
  .byte $00,$00,$C4,$E4,$EC,$E8,$F0,$E0,$F0,$F0,$E0,$C0,$60,$60,$60,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$38,$7C,$65,$7D,$39,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$FE,$FC,$DC,$1C
  .byte $00,$00,$00,$00,$07,$0F,$1D,$1F,$3F,$2F,$3F,$1F,$08,$1C,$14,$1C
  .byte $00,$00,$00,$00,$E0,$F0,$B8,$F8,$FC,$F4,$FC,$F8,$10,$38,$28,$38
  .byte $00,$00,$00,$00,$07,$0F,$1E,$1F,$3F,$2F,$3F,$1F,$08,$1C,$1A,$1C
  .byte $00,$00,$00,$00,$E0,$F0,$D8,$F8,$FC,$F4,$FC,$F8,$10,$38,$68,$38
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0C,$1E,$16,$3F,$7F,$5F,$C0,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$30,$78,$58,$FC,$FE,$FA,$0C,$04
  .byte $00,$00,$00,$00,$00,$0C,$1E,$16,$3F,$3F,$1F,$04,$08,$10,$20,$60
  .byte $00,$00,$00,$00,$00,$30,$78,$58,$FC,$FC,$F8,$20,$10,$08,$04,$06
  .byte $00,$00,$00,$01,$11,$09,$05,$27,$1F,$FE,$1F,$27,$05,$09,$11,$01
  .byte $00,$00,$00,$00,$10,$20,$40,$C8,$F0,$FE,$F0,$C8,$40,$20,$10,$00
  .byte $00,$00,$00,$20,$11,$09,$07,$07,$6F,$1E,$6F,$07,$07,$09,$11,$20
  .byte $00,$00,$00,$08,$10,$20,$C0,$C0,$EC,$F0,$EC,$C0,$C0,$20,$10,$08
  .byte $FF,$7F,$1F,$0F,$0D,$0F,$07,$03,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $FF,$FE,$F8,$F0,$B0,$F0,$E0,$C0,$80,$80,$00,$00,$00,$00,$00,$00
  .byte $FF,$7F,$1F,$0F,$0D,$0F,$07,$03,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $FF,$FE,$F8,$F0,$B0,$F0,$E0,$C0,$80,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$43,$27,$1B,$8F,$77,$0D,$13,$20,$40
  .byte $00,$00,$00,$00,$00,$80,$80,$C2,$E4,$D8,$F1,$EE,$B0,$C8,$04,$02
  .byte $00,$00,$00,$00,$00,$01,$01,$83,$67,$1B,$0F,$F7,$0D,$33,$40,$80
  .byte $00,$00,$00,$00,$00,$80,$80,$C1,$E6,$D8,$F0,$EF,$B0,$CC,$02,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$51,$8A,$04,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$44,$2A,$11,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$22,$54,$88,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$8A,$51,$20,$00,$00,$00
  .byte $00,$00,$00,$38,$3E,$1F,$1F,$7F,$FF,$7F,$1F,$1F,$3E,$38,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$F0,$FE,$E7,$FE,$F0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$38,$3E,$1F,$9F,$7F,$FF,$7F,$9F,$1F,$3E,$38,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$F0,$FE,$E7,$FE,$F0,$80,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$0F,$3D,$38,$7D,$7F,$3F,$1F,$1F,$0F,$00,$00,$00
  .byte $00,$00,$E0,$F0,$F8,$F8,$FC,$F8,$D8,$D8,$F8,$F8,$F8,$F0,$00,$00
  .byte $00,$00,$00,$01,$07,$1D,$18,$1D,$1F,$1F,$0F,$07,$01,$00,$00,$00
  .byte $00,$00,$00,$E0,$F0,$F0,$F8,$F8,$D0,$D0,$F0,$F0,$E0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$0F,$7F,$EF,$7F,$0F,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$1C,$78,$F0,$F8,$FE,$FE,$FE,$F8,$F0,$78,$1C,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$0F,$7F,$EF,$7F,$0F,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$1C,$F8,$F8,$FE,$FE,$FE,$F8,$F8,$1C,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$3F,$FF,$DB,$FF,$3F,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$3C,$FC,$F8,$F8,$FF,$7F,$FF,$F8,$F8,$FC,$3C,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$3F,$FF,$DB,$FF,$3F,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$3C,$FC,$F8,$F8,$FF,$7F,$FF,$F8,$F8,$FC,$3C,$00,$00,$00
  .byte $00,$00,$00,$10,$0B,$07,$0E,$0C,$0C,$0E,$07,$0B,$10,$00,$00,$00
  .byte $00,$00,$00,$08,$D0,$E0,$70,$30,$30,$70,$E0,$D0,$08,$00,$00,$00
  .byte $00,$04,$04,$00,$03,$67,$0E,$0C,$0C,$0E,$67,$03,$00,$04,$04,$00
  .byte $00,$20,$20,$00,$C0,$E6,$70,$30,$30,$70,$E6,$C0,$00,$20,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$1F,$1F,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$F8,$F8,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$0D,$0F,$06,$1C,$1C,$06,$0F,$0D,$01,$00,$00,$00
  .byte $00,$00,$00,$80,$B0,$F0,$60,$38,$38,$60,$F0,$B0,$80,$00,$00,$00
  .byte $00,$06,$07,$37,$3F,$3E,$1C,$78,$78,$1C,$3E,$3F,$37,$07,$06,$00
  .byte $00,$60,$E0,$EC,$FC,$7C,$38,$1E,$1E,$38,$7C,$FC,$EC,$E0,$60,$00
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

; station tiles
T_WALL = 96
T_WALLT = 97
T_PLAT = 98
T_LAD = 99
T_LADP = 100
T_EMIT = 101
T_HOUSE = 102
T_CORE0 = 103
T_CORE1 = 104
T_CORE2 = 105
T_CORE3 = 106
T_HATCH0 = 107
T_HATCH1 = 108
T_HATCH2 = 109
T_OXY = 110
T_CRYS = 111
T_DOT = 112
T_CRUMB0 = 113
T_CRUMB1 = 114
T_CRUMB2 = 115
T_CONVL = 116
T_CONVR = 117
T_LIFT = 118
T_ARCH0 = 119
T_ARCH1 = 120
T_ARCV0 = 121
T_ARCV1 = 122
T_PRESS0 = 123
T_PRESS1 = 124
T_FAR0 = 200
T_FAR1 = 201
T_FAR2 = 202
T_FAR3 = 203
T_FAR4 = 204
T_FAR5 = 205
T_FAR6 = 206
T_FAR7 = 207
T_NEAR0 = 208
T_NEAR1 = 209
T_NEAR2 = 210
T_NEAR3 = 211
T_NEAR4 = 212
T_NEAR5 = 213
T_NEAR6 = 214
T_NEAR7 = 215
T_HULL = 216
T_HULLE = 217
T_BAYT = 218
T_BAYB = 219
T_BAYIN = 220
T_BAYEND = 221
T_LIFE = 1
T_STUN = 2
T_OXY2 = 3
T_SHIPI = 4
T_BAR = 8
N_TILES = 29
ST_PAT:
  .byte $FE,$FE,$BE,$FE,$FE,$FA,$FE,$FF,$FF,$FE,$BE,$FE,$FE,$FA,$FE,$FF
  .byte $FF,$FF,$99,$66,$66,$99,$FF,$00,$7E,$42,$42,$42,$7E,$42,$42,$42
  .byte $81,$42,$42,$42,$7E,$42,$42,$42,$7E,$FF,$C3,$DB,$DB,$C3,$FF,$7E
  .byte $FF,$FF,$AA,$55,$AA,$55,$FF,$7E,$07,$1F,$3F,$7F,$7F,$F8,$F0,$E0
  .byte $E0,$F8,$FC,$FE,$FE,$E0,$F0,$F8,$E0,$F0,$F8,$7F,$7F,$3F,$1F,$07
  .byte $F8,$F0,$E0,$FE,$FE,$FC,$F8,$E0,$FF,$81,$BD,$A5,$A5,$BD,$81,$81
  .byte $81,$81,$99,$99,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$FF
  .byte $18,$3C,$7E,$6E,$6E,$7E,$7E,$3C,$10,$38,$6C,$C6,$6C,$38,$10,$00
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$FF,$FF,$BB,$D7,$ED,$B7,$FF,$00
  .byte $EF,$DD,$AB,$6A,$D6,$AD,$DB,$00,$A5,$49,$A4,$29,$44,$92,$48,$00
  .byte $FF,$B6,$6D,$DB,$B6,$6D,$FF,$42,$FF,$6D,$B6,$DB,$6D,$B6,$FF,$42
  .byte $18,$24,$42,$00,$18,$24,$42,$00,$00,$10,$29,$46,$82,$00,$00,$00
  .byte $00,$10,$29,$46,$82,$00,$00,$00,$10,$08,$08,$10,$20,$10,$08,$10
  .byte $10,$08,$08,$10,$20,$10,$08,$10,$7E,$7E,$5A,$7E,$7E,$5A,$7E,$FF
  .byte $7E,$7E,$5A,$7E,$7E,$5A,$7E,$FF
ST_COL:
  .byte $12,$12,$12,$12,$12,$12,$12,$22,$33,$12,$12,$12,$12,$12,$12,$22
  .byte $33,$44,$40,$40,$40,$40,$44,$00,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $35,$50,$50,$50,$50,$50,$50,$50,$90,$99,$9D,$9D,$9D,$9D,$99,$90
  .byte $22,$AA,$A0,$A0,$A0,$A0,$AA,$A0,$B0,$B0,$B0,$B0,$B0,$BC,$BC,$BC
  .byte $B0,$B0,$B0,$B0,$B0,$CB,$CB,$CB,$BC,$BC,$BC,$B0,$B0,$B0,$B0,$B0
  .byte $CB,$CB,$CB,$B0,$B0,$B0,$B0,$B0,$DD,$D2,$D2,$D2,$D2,$D2,$D2,$D2
  .byte $D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$D2,$DD
  .byte $D0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$D0,$D0,$D0,$D0,$D0,$D0,$D0,$00
  .byte $00,$00,$00,$F0,$00,$00,$00,$00,$33,$44,$40,$40,$40,$40,$44,$00
  .byte $30,$40,$40,$40,$40,$40,$40,$00,$30,$40,$40,$40,$40,$40,$40,$00
  .byte $66,$60,$60,$60,$60,$60,$66,$60,$66,$60,$60,$60,$60,$60,$66,$60
  .byte $70,$70,$70,$00,$70,$70,$70,$00,$00,$80,$80,$80,$80,$00,$00,$00
  .byte $00,$80,$80,$80,$80,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$AA
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$AA
SP_PAT:
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00
  .byte $00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00
  .byte $00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00
  .byte $FF,$81,$BD,$A5,$A5,$BD,$81,$FF,$1F,$3F,$7F,$FF,$FF,$7F,$3F,$1F
  .byte $FF,$FF,$00,$AA,$00,$00,$00,$00,$00,$00,$00,$00,$AA,$00,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$A0,$90,$90,$A0,$C0,$80
SP_COL:
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
SMALL_PAT:
  .byte $38,$7C,$64,$7C,$38,$7C,$44,$44,$08,$18,$30,$7E,$0C,$18,$10,$00
  .byte $18,$3C,$7E,$5E,$5E,$7E,$7E,$3C,$00,$C0,$F0,$FE,$FF,$FE,$F0,$C0
SMALL_COL:
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
BAR_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$C0,$C0,$C0,$C0,$C0,$C0,$00,$00,$E0,$E0,$E0,$E0,$E0,$E0,$00
  .byte $00,$F0,$F0,$F0,$F0,$F0,$F0,$00,$00,$F8,$F8,$F8,$F8,$F8,$F8,$00
  .byte $00,$FC,$FC,$FC,$FC,$FC,$FC,$00,$00,$FE,$FE,$FE,$FE,$FE,$FE,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00
BAR_COL:
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71
; animated patterns: conveyors and lift 4 phases, arcs on / flicker / off, presses on / off
AN_CONVL:
  .byte $FF,$B6,$6D,$DB,$B6,$6D,$FF,$42,$FF,$6D,$DA,$B7,$6D,$DA,$FF,$42
  .byte $FF,$DA,$B5,$6F,$DA,$B5,$FF,$42,$FF,$B5,$6B,$DE,$B5,$6B,$FF,$42
AN_CONVR:
  .byte $FF,$6D,$B6,$DB,$6D,$B6,$FF,$42,$FF,$B6,$5B,$ED,$B6,$5B,$FF,$42
  .byte $FF,$5B,$AD,$F6,$5B,$AD,$FF,$42,$FF,$AD,$D6,$7B,$AD,$D6,$FF,$42
AN_LIFT:
  .byte $18,$24,$42,$00,$18,$24,$42,$00,$42,$00,$18,$24,$42,$00,$18,$24
  .byte $18,$24,$42,$00,$18,$24,$42,$00,$42,$00,$18,$24,$42,$00,$18,$24
AN_ARCH:
  .byte $00,$10,$29,$46,$82,$00,$00,$00,$00,$00,$82,$45,$28,$10,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
AN_ARCV:
  .byte $10,$08,$08,$10,$20,$10,$08,$10,$08,$10,$20,$10,$08,$04,$08,$10
  .byte $00,$00,$00,$00,$00,$00,$00,$00
AN_PRESS:
  .byte $7E,$7E,$5A,$7E,$7E,$5A,$7E,$FF,$00,$00,$00,$00,$00,$00,$00,$00
; core colours (materials), 4 phases x 4 tiles x 8 rows
AN_CORE:
  .byte $B0,$B0,$B0,$B0,$B0,$BC,$BC,$BC,$B0,$B0,$B0,$B0,$B0,$CB,$CB,$CB
  .byte $BC,$BC,$BC,$B0,$B0,$B0,$B0,$B0,$CB,$CB,$CB,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$BD,$BD,$BD,$B0,$B0,$B0,$B0,$B0,$DB,$DB,$DB
  .byte $BD,$BD,$BD,$B0,$B0,$B0,$B0,$B0,$DB,$DB,$DB,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$BC,$BC,$BC,$B0,$B0,$B0,$B0,$B0,$CB,$CB,$CB
  .byte $BC,$BC,$BC,$B0,$B0,$B0,$B0,$B0,$CB,$CB,$CB,$B0,$B0,$B0,$B0,$B0
  .byte $D0,$D0,$D0,$D0,$D0,$DC,$DC,$DC,$D0,$D0,$D0,$D0,$D0,$CD,$CD,$CD
  .byte $DC,$DC,$DC,$D0,$D0,$D0,$D0,$D0,$CD,$CD,$CD,$D0,$D0,$D0,$D0,$D0
; tile classes: 0 empty, 1 solid, 2 ladder, 3 / 4 conveyor left / right, 5 lift, 6-9 arcs and presses,
; 10 crumbling, 11 core, 12 hatch, 13 oxygen, 14 crystal
CLASS:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$02,$02,$01,$01,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0D,$0E
  .byte $00,$0A,$0A,$0A,$03,$04,$05,$06,$07,$06,$07,$08,$09,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; station palettes: material -> TMS colour
WPAL:
  .byte $01,$0E,$04,$05,$04,$0A,$0E,$04,$0F,$0E,$0E,$0B,$0A,$0F,$07,$04
  .byte $01,$0C,$01,$03,$0C,$0A,$0E,$04,$0F,$0E,$0E,$0B,$0A,$0F,$07,$0C
  .byte $01,$04,$01,$07,$04,$0A,$0E,$04,$0F,$05,$0E,$0B,$0A,$0F,$07,$04
  .byte $01,$0D,$01,$05,$0D,$0A,$0E,$0D,$0F,$0E,$0E,$0B,$0A,$0F,$07,$0D
  .byte $01,$0A,$01,$0B,$0A,$0E,$0E,$04,$0F,$0E,$0E,$07,$05,$0F,$07,$06
  .byte $01,$06,$01,$09,$06,$0E,$0E,$04,$0F,$0E,$08,$0B,$0A,$0F,$07,$06
  .byte $01,$02,$01,$03,$0C,$0E,$0E,$04,$0B,$03,$0E,$0D,$04,$0F,$07,$0C
  .byte $01,$0E,$01,$0F,$0E,$0A,$07,$04,$0B,$08,$08,$09,$06,$0F,$07,$04

; rooms: RLE tile ids of rows 2-22 (7, count, tile; end 7, 0), then the enemies: count, (kind, x, feet y, p) each
ROOM0:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$08,$00,$6F,$07
  .byte $0C,$00,$6E,$07,$08,$00,$60,$60,$00,$62,$62,$64,$07,$07,$62,$07,$08,$00,$07,$08,$62,$64,$62,$00
  .byte $60,$60,$00,$00,$00,$63,$07,$17,$00,$63,$00,$00,$60,$60,$00,$00,$00,$63,$07,$17,$00,$63,$00,$00
  .byte $60,$60,$00,$00,$00,$63,$07,$17,$00,$63,$00,$00,$60,$60,$00,$00,$00,$63,$07,$17,$00,$63,$00,$00
  .byte $60,$60,$00,$00,$00,$63,$07,$09,$00,$07,$04,$61,$07,$0A,$00,$63,$00,$00,$60,$60,$00,$00,$00,$63
  .byte $07,$09,$00,$07,$04,$60,$07,$0A,$00,$63,$00,$00,$60,$6B,$00,$00,$00,$63,$00,$00,$07,$04,$62,$00
  .byte $00,$00,$07,$04,$60,$07,$0A,$00,$63,$00,$00,$00,$6C,$00,$00,$00,$63,$07,$09,$00,$07,$04,$60,$07
  .byte $0A,$00,$63,$00,$00,$00,$6D,$00,$00,$00,$63,$07,$09,$00,$07,$04,$60,$07,$0A,$00,$63,$00,$00,$00
  .byte $07,$0E,$61,$07,$04,$60,$07,$0E,$61,$07,$00
RENM0:
  .byte $02,$01,$C4,$B0,$00,$01,$C4,$60,$00
ROOM1:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$0B,$00,$6F,$07,$12,$00,$60,$60,$00,$00,$00,$62,$62,$64
  .byte $07,$08,$62,$07,$10,$00,$60,$60,$07,$05,$00,$63,$07,$18,$00,$60,$60,$07,$05,$00,$63,$07,$19,$00
  .byte $60,$07,$05,$00,$63,$07,$19,$00,$60,$07,$05,$00,$63,$07,$16,$00,$6E,$00,$00,$60,$07,$05,$00,$63
  .byte $07,$0B,$00,$62,$62,$64,$07,$0A,$62,$61,$60,$07,$05,$00,$63,$07,$0D,$00,$63,$07,$0A,$00,$60,$60
  .byte $07,$05,$00,$63,$07,$0D,$00,$63,$07,$0A,$00,$60,$60,$07,$05,$00,$63,$07,$0D,$00,$63,$07,$0A,$00
  .byte $60,$07,$06,$00,$63,$07,$0D,$00,$63,$07,$0A,$00,$60,$07,$06,$00,$63,$07,$0D,$00,$63,$07,$0A,$00
  .byte $60,$07,$06,$00,$63,$07,$0D,$00,$63,$07,$0A,$00,$60,$07,$0C,$61,$07,$04,$00,$07,$0F,$61,$60,$07
  .byte $00
RENM1:
  .byte $02,$01,$CC,$B0,$00,$01,$D4,$78,$00
ROOM2:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$18,$00,$67,$68,$07
  .byte $04,$00,$60,$60,$07,$18,$00,$69,$6A,$07,$04,$00,$60,$60,$07,$0F,$00,$62,$62,$64,$07,$0A,$62,$00
  .byte $00,$60,$60,$07,$11,$00,$63,$07,$0C,$00,$60,$60,$07,$11,$00,$63,$07,$0C,$00,$60,$60,$07,$11,$00
  .byte $63,$07,$0C,$00,$60,$07,$12,$00,$63,$07,$0C,$00,$60,$07,$12,$00,$63,$07,$0C,$00,$60,$00,$00,$00
  .byte $6F,$07,$0E,$00,$63,$07,$0C,$00,$60,$61,$07,$09,$62,$64,$62,$62,$07,$05,$00,$63,$07,$0C,$00,$60
  .byte $60,$07,$09,$00,$63,$07,$07,$00,$63,$07,$0C,$00,$60,$60,$07,$09,$00,$63,$07,$07,$00,$63,$07,$0C
  .byte $00,$60,$60,$07,$09,$00,$63,$07,$07,$00,$63,$07,$0C,$00,$60,$60,$07,$09,$00,$63,$07,$07,$00,$63
  .byte $07,$0C,$00,$60,$60,$07,$09,$00,$63,$07,$07,$00,$63,$07,$0C,$00,$60,$60,$07,$09,$00,$63,$07,$07
  .byte $00,$63,$07,$09,$00,$6E,$00,$00,$60,$60,$07,$1E,$61,$60,$07,$00
RENM2:
  .byte $02,$01,$74,$B0,$00,$01,$AC,$40,$00
ROOM3:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$0C,$00,$6F,$07
  .byte $11,$00,$60,$60,$00,$00,$63,$07,$0B,$75,$07,$0B,$00,$6E,$07,$04,$00,$60,$60,$00,$00,$63,$07,$14
  .byte $00,$07,$05,$62,$64,$62,$60,$60,$00,$00,$63,$07,$19,$00,$63,$00,$60,$60,$00,$00,$63,$07,$19,$00
  .byte $63,$00,$60,$60,$00,$00,$63,$07,$19,$00,$63,$00,$60,$60,$00,$00,$63,$07,$19,$00,$63,$00,$60,$60
  .byte $00,$00,$63,$07,$12,$00,$61,$61,$07,$05,$00,$63,$00,$60,$6B,$00,$00,$63,$07,$0C,$00,$07,$04,$62
  .byte $00,$00,$60,$60,$07,$05,$00,$63,$00,$00,$6C,$00,$00,$63,$07,$12,$00,$60,$60,$07,$05,$00,$63,$00
  .byte $00,$6D,$00,$00,$63,$07,$12,$00,$60,$60,$07,$05,$00,$63,$00,$00,$07,$08,$61,$07,$08,$74,$07,$06
  .byte $61,$60,$60,$07,$08,$61,$07,$00
RENM3:
  .byte $01,$02,$DC,$B0,$00
ROOM4:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$11,$00,$6F,$07,$0C,$00,$60,$60,$07,$09,$00,$74,$74,$63
  .byte $07,$08,$74,$07,$0A,$00,$60,$60,$07,$0B,$00,$63,$07,$12,$00,$60,$60,$07,$0B,$00,$63,$07,$12,$00
  .byte $60,$60,$07,$0B,$00,$63,$07,$12,$00,$60,$60,$07,$0B,$00,$63,$07,$12,$00,$60,$60,$07,$0B,$00,$63
  .byte $07,$12,$00,$60,$60,$07,$05,$00,$62,$62,$64,$07,$0F,$62,$64,$62,$07,$05,$00,$60,$60,$07,$07,$00
  .byte $63,$07,$0F,$00,$63,$07,$06,$00,$60,$60,$07,$07,$00,$63,$07,$0F,$00,$63,$07,$06,$00,$60,$07,$08
  .byte $00,$63,$07,$0F,$00,$63,$07,$0F,$00,$63,$07,$0F,$00,$63,$07,$0F,$00,$63,$07,$0F,$00,$63,$07,$07
  .byte $00,$61,$61,$61,$07,$09,$75,$07,$04,$00,$07,$0D,$74,$61,$61,$61,$07,$00
RENM4:
  .byte $02,$02,$84,$80,$00,$02,$D4,$B0,$00
ROOM5:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$11,$00,$67,$68,$07,$0B,$00,$60,$60
  .byte $07,$11,$00,$69,$6A,$07,$0B,$00,$60,$60,$07,$05,$00,$62,$64,$62,$07,$07,$74,$07,$05,$62,$07,$0A
  .byte $00,$60,$60,$07,$06,$00,$63,$07,$17,$00,$60,$60,$07,$06,$00,$63,$07,$17,$00,$60,$60,$07,$06,$00
  .byte $63,$07,$17,$00,$60,$60,$07,$06,$00,$63,$07,$15,$00,$6E,$00,$60,$60,$07,$06,$00,$63,$07,$0A,$00
  .byte $07,$09,$62,$64,$62,$62,$00,$60,$60,$07,$06,$00,$63,$07,$13,$00,$63,$00,$00,$00,$60,$07,$07,$00
  .byte $63,$07,$13,$00,$63,$00,$00,$00,$60,$07,$07,$00,$63,$07,$13,$00,$63,$00,$00,$00,$60,$07,$07,$00
  .byte $63,$07,$13,$00,$63,$00,$00,$00,$60,$07,$06,$61,$07,$0A,$75,$07,$0F,$61,$60,$07,$00
RENM5:
  .byte $02,$02,$B4,$88,$00,$01,$A4,$B0,$00
ROOM6:
  .byte $07,$21,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00
  .byte $60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60
  .byte $07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$12
  .byte $00,$60,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$12,$00,$60,$60,$07,$0B,$00
  .byte $60,$07,$12,$00,$60,$60,$07,$0B,$00,$60,$07,$05,$00,$6F,$07,$08,$00,$6E,$00,$00,$00,$60,$60,$07
  .byte $0B,$00,$60,$00,$00,$00,$07,$0A,$62,$64,$62,$62,$00,$00,$60,$60,$07,$0B,$00,$60,$07,$09,$00,$61
  .byte $00,$00,$00,$63,$07,$04,$00,$60,$60,$07,$0B,$00,$60,$07,$09,$00,$60,$00,$00,$00,$63,$07,$04,$00
  .byte $60,$60,$07,$0B,$00,$65,$07,$09,$00,$65,$00,$00,$00,$63,$07,$04,$00,$60,$6B,$07,$0B,$00,$79,$07
  .byte $09,$00,$7A,$00,$00,$00,$63,$07,$05,$00,$6C,$07,$0B,$00,$79,$07,$09,$00,$7A,$00,$00,$00,$63,$07
  .byte $05,$00,$6D,$07,$0B,$00,$79,$07,$09,$00,$7A,$00,$00,$00,$63,$07,$05,$00,$07,$0C,$61,$65,$07,$09
  .byte $61,$65,$07,$09,$61,$07,$00
RENM6:
  .byte $01,$04,$A4,$28,$00
ROOM7:
  .byte $07,$21,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00
  .byte $65,$07,$0C,$00,$60,$60,$07,$11,$00,$7A,$07,$0D,$00,$60,$07,$11,$00,$7A,$07,$0D,$00,$60,$07,$11
  .byte $00,$7A,$07,$0D,$00,$60,$00,$00,$00,$62,$62,$64,$07,$0B,$62,$65,$07,$0C,$62,$61,$60,$07,$05,$00
  .byte $63,$07,$18,$00,$60,$60,$07,$05,$00,$63,$07,$18,$00,$60,$60,$07,$05,$00,$63,$07,$18,$00,$60,$60
  .byte $07,$05,$00,$63,$07,$18,$00,$60,$60,$07,$05,$00,$63,$07,$18,$00,$60,$60,$07,$05,$00,$63,$07,$0D
  .byte $00,$6E,$07,$0A,$00,$60,$60,$07,$05,$00,$63,$07,$0B,$00,$07,$0A,$62,$64,$62,$62,$60,$60,$07,$05
  .byte $00,$63,$07,$15,$00,$63,$00,$00,$60,$60,$07,$05,$00,$63,$07,$15,$00,$63,$00,$00,$60,$07,$06,$00
  .byte $63,$07,$15,$00,$63,$00,$00,$60,$07,$06,$00,$63,$00,$00,$65,$07,$06,$77,$65,$07,$0B,$00,$63,$00
  .byte $00,$60,$07,$06,$00,$63,$07,$15,$00,$63,$00,$00,$60,$07,$1F,$61,$60,$07,$00
RENM7:
  .byte $03,$04,$64,$28,$00,$01,$B4,$80,$00,$01,$54,$48,$00
ROOM8:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$07,$1F,$00,$60,$07,$1F,$00
  .byte $60,$07,$1F,$00,$60,$61,$07,$08,$62,$64,$62,$07,$14,$00,$60,$60,$07,$08,$00,$63,$07,$15,$00,$60
  .byte $60,$07,$08,$00,$63,$07,$15,$00,$60,$60,$07,$08,$00,$63,$07,$15,$00,$60,$60,$07,$08,$00,$63,$07
  .byte $12,$00,$6F,$00,$00,$60,$60,$07,$08,$00,$63,$07,$0A,$00,$62,$64,$07,$09,$62,$60,$60,$07,$08,$00
  .byte $63,$07,$0B,$00,$63,$07,$09,$00,$60,$60,$07,$08,$00,$63,$07,$0B,$00,$63,$07,$09,$00,$60,$60,$07
  .byte $08,$00,$63,$07,$0B,$00,$63,$07,$09,$00,$60,$60,$07,$08,$00,$63,$07,$0B,$00,$63,$07,$09,$00,$60
  .byte $60,$07,$08,$00,$63,$07,$0B,$00,$63,$07,$09,$00,$60,$60,$07,$08,$00,$63,$00,$00,$65,$07,$06,$77
  .byte $65,$00,$63,$07,$04,$00,$67,$68,$00,$00,$00,$60,$60,$07,$08,$00,$63,$07,$0B,$00,$63,$07,$04,$00
  .byte $69,$6A,$00,$00,$00,$60,$60,$07,$1E,$61,$60,$07,$00
RENM8:
  .byte $02,$04,$B4,$28,$00,$04,$84,$28,$00
ROOM9:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$0D,$00,$76,$76,$07,$0F,$00,$60,$60,$07
  .byte $0D,$00,$76,$76,$07,$10,$00,$60,$07,$0D,$00,$76,$76,$07,$10,$00,$60,$07,$08,$00,$6F,$07,$04,$00
  .byte $76,$76,$07,$10,$00,$60,$00,$62,$62,$64,$07,$08,$62,$00,$76,$76,$07,$0F,$62,$61,$60,$00,$00,$00
  .byte $63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60
  .byte $60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76
  .byte $07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07
  .byte $09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00
  .byte $00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F
  .byte $00,$60,$6B,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$6C,$00,$00,$00,$63,$07,$09,$00
  .byte $76,$76,$07,$0F,$00,$60,$6D,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$07,$1F,$61,$60
  .byte $07,$00
RENM9:
  .byte $01,$03,$B4,$88,$00
ROOM10:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1B,$00,$76,$76,$00,$60,$07,$1C,$00,$76
  .byte $76,$00,$60,$07,$1C,$00,$76,$6F,$00,$60,$07,$1C,$00,$76,$76,$00,$60,$61,$07,$05,$62,$64,$62,$62
  .byte $07,$13,$00,$76,$76,$00,$60,$60,$07,$05,$00,$63,$07,$15,$00,$76,$76,$00,$60,$60,$07,$05,$00,$63
  .byte $07,$04,$00,$76,$76,$07,$0F,$00,$76,$76,$00,$60,$60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$07,$0F
  .byte $00,$76,$76,$00,$60,$60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$07,$0B,$00,$6E,$00,$00,$00,$76,$76
  .byte $00,$60,$60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$00,$00,$00,$62,$64,$07,$0A,$62,$76,$76,$00,$60
  .byte $60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$07,$04,$00,$63,$07,$0A,$00,$76,$76,$00,$60,$60,$07,$05
  .byte $00,$63,$07,$04,$00,$76,$76,$07,$04,$00,$63,$07,$0A,$00,$76,$76,$00,$60,$60,$07,$05,$00,$63,$07
  .byte $04,$00,$76,$76,$07,$04,$00,$63,$07,$0A,$00,$76,$76,$00,$60,$60,$07,$05,$00,$63,$07,$04,$00,$76
  .byte $76,$07,$04,$00,$63,$07,$0A,$00,$76,$76,$00,$60,$60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$07,$04
  .byte $00,$63,$07,$0A,$00,$76,$76,$00,$00,$60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$07,$04,$00,$63,$07
  .byte $0A,$00,$76,$76,$00,$00,$60,$07,$05,$00,$63,$07,$04,$00,$76,$76,$07,$04,$00,$63,$07,$0A,$00,$76
  .byte $76,$00,$00,$60,$07,$09,$61,$00,$76,$76,$00,$07,$12,$61,$07,$00
RENM10:
  .byte $02,$03,$A4,$98,$00,$01,$A4,$70,$00
ROOM11:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$10,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$10,$00,$76,$76,$07
  .byte $06,$00,$67,$68,$07,$04,$00,$60,$60,$07,$10,$00,$76,$76,$07,$06,$00,$69,$6A,$07,$04,$00,$60,$60
  .byte $07,$10,$00,$76,$76,$00,$07,$0A,$62,$00,$60,$60,$07,$10,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$10
  .byte $00,$76,$76,$07,$0C,$00,$60,$60,$07,$10,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$10,$00,$76,$76,$07
  .byte $0C,$00,$60,$60,$07,$10,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$09,$00,$6E,$07,$06,$00,$76,$76,$07
  .byte $0C,$00,$60,$60,$00,$00,$00,$62,$62,$64,$07,$08,$62,$00,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$05
  .byte $00,$63,$07,$0A,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$05,$00,$63,$07,$0A,$00,$76,$76,$07,$0C,$00
  .byte $60,$60,$07,$05,$00,$63,$07,$0A,$00,$76,$76,$07,$0C,$00,$60,$60,$07,$05,$00,$63,$07,$0A,$00,$76
  .byte $76,$07,$0C,$00,$60,$07,$06,$00,$63,$07,$0A,$00,$76,$76,$07,$0C,$00,$60,$07,$06,$00,$63,$07,$0A
  .byte $00,$76,$76,$07,$0C,$00,$60,$07,$06,$00,$63,$07,$0A,$00,$76,$76,$07,$0C,$00,$60,$07,$1F,$61,$60
  .byte $07,$00
RENM11:
  .byte $03,$03,$54,$58,$00,$03,$C4,$90,$00,$02,$D4,$B0,$00
ROOM12:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60
  .byte $07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$13,$00,$6F,$07,$0A,$00,$60,$60
  .byte $00,$00,$62,$64,$07,$16,$62,$64,$62,$00,$00,$60,$60,$00,$00,$00,$63,$07,$16,$00,$63,$00,$00,$00
  .byte $60,$60,$00,$00,$00,$63,$07,$16,$00,$63,$00,$00,$00,$60,$6B,$00,$00,$00,$63,$07,$16,$00,$63,$07
  .byte $04,$00,$6C,$00,$00,$00,$63,$07,$16,$00,$63,$07,$04,$00,$6D,$00,$00,$00,$63,$07,$14,$00,$6E,$00
  .byte $63,$07,$04,$00,$07,$0A,$61,$07,$0C,$71,$07,$0A,$61,$07,$00
RENM12:
  .byte $01,$01,$7C,$80,$00
ROOM13:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$07,$00,$6E,$07
  .byte $16,$00,$60,$60,$00,$62,$64,$07,$18,$62,$64,$62,$00,$60,$60,$00,$00,$63,$07,$18,$00,$63,$00,$00
  .byte $60,$60,$00,$00,$63,$07,$18,$00,$63,$00,$00,$60,$60,$00,$00,$63,$07,$18,$00,$63,$00,$00,$60,$60
  .byte $00,$00,$63,$07,$18,$00,$63,$00,$00,$60,$60,$00,$00,$63,$07,$0A,$00,$6F,$07,$0D,$00,$63,$00,$00
  .byte $60,$60,$00,$00,$63,$07,$09,$00,$71,$71,$71,$07,$0C,$00,$63,$00,$00,$60,$00,$00,$00,$63,$07,$18
  .byte $00,$63,$07,$06,$00,$63,$07,$04,$00,$71,$71,$71,$07,$07,$00,$71,$71,$71,$07,$07,$00,$63,$07,$06
  .byte $00,$63,$07,$13,$00,$71,$71,$00,$00,$00,$63,$00,$00,$00,$07,$06,$61,$07,$14,$00,$07,$06,$61,$07
  .byte $00
RENM13:
  .byte $02,$02,$7C,$60,$00,$01,$E4,$B0,$00
ROOM14:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$14,$00,$67,$68,$07,$08,$00,$60,$60,$07,$14,$00,$69,$6A,$07,$08,$00,$60,$60
  .byte $07,$10,$00,$07,$0B,$62,$64,$00,$00,$60,$60,$07,$1B,$00,$63,$00,$00,$60,$60,$07,$0D,$00,$6F,$07
  .byte $0D,$00,$63,$00,$00,$60,$60,$07,$0B,$00,$07,$04,$71,$07,$0C,$00,$63,$00,$00,$60,$60,$07,$1B,$00
  .byte $63,$00,$00,$60,$60,$07,$1B,$00,$63,$00,$00,$60,$60,$00,$00,$00,$62,$64,$07,$05,$62,$07,$11,$00
  .byte $63,$00,$00,$60,$60,$07,$04,$00,$63,$07,$16,$00,$63,$00,$00,$60,$60,$07,$04,$00,$63,$07,$16,$00
  .byte $63,$00,$00,$60,$07,$05,$00,$63,$07,$16,$00,$63,$00,$00,$60,$07,$05,$00,$63,$07,$16,$00,$63,$00
  .byte $00,$60,$07,$05,$00,$63,$07,$16,$00,$63,$00,$00,$60,$07,$1F,$61,$60,$07,$00
RENM14:
  .byte $03,$02,$74,$B0,$00,$01,$C4,$50,$00,$02,$44,$80,$00
ROOM15:
  .byte $07,$21,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60
  .byte $07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07
  .byte $00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60
  .byte $07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09
  .byte $00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60
  .byte $07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00
  .byte $60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$07,$0C,$00,$60,$60,$07,$09,$00,$60,$07,$07,$00,$60,$00
  .byte $00,$00,$6F,$07,$08,$00,$60,$60,$07,$09,$00,$66,$07,$07,$00,$66,$00,$07,$08,$62,$64,$62,$00,$60
  .byte $60,$07,$09,$00,$7B,$07,$07,$00,$7C,$07,$09,$00,$63,$00,$00,$60,$60,$07,$09,$00,$7B,$07,$07,$00
  .byte $7C,$07,$09,$00,$63,$00,$00,$60,$6B,$07,$09,$00,$7B,$07,$07,$00,$7C,$07,$09,$00,$63,$00,$00,$00
  .byte $6C,$07,$09,$00,$7B,$07,$07,$00,$7C,$07,$09,$00,$63,$00,$00,$00,$6D,$07,$09,$00,$7B,$07,$07,$00
  .byte $7C,$07,$07,$00,$6E,$00,$63,$00,$00,$00,$07,$20,$61,$07,$00
RENM15:
  .byte $02,$04,$74,$28,$00,$03,$C4,$98,$00
ROOM16:
  .byte $07,$21,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$60,$07,$05,$00,$60,$60,$07,$07,$00,$60
  .byte $07,$05,$00,$60,$07,$0A,$00,$60,$07,$05,$00,$60,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00
  .byte $60,$07,$05,$00,$60,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$60,$07,$05,$00,$60,$60,$07
  .byte $07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$60,$07,$05,$00,$60,$60,$07,$07,$00,$60,$07,$05,$00,$60
  .byte $07,$0A,$00,$60,$07,$05,$00,$60,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$60,$07,$05,$00
  .byte $60,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$60,$07,$05,$00,$60,$60,$07,$07,$00,$60,$07
  .byte $05,$00,$60,$07,$0A,$00,$66,$07,$05,$00,$60,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$7B
  .byte $07,$05,$00,$60,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00,$7B,$07,$06,$00,$60,$07,$07,$00
  .byte $60,$07,$05,$00,$60,$07,$0A,$00,$7B,$07,$06,$00,$60,$07,$07,$00,$60,$07,$05,$00,$60,$07,$0A,$00
  .byte $7B,$00,$00,$00,$6E,$00,$00,$60,$07,$07,$00,$66,$07,$05,$00,$66,$00,$00,$00,$62,$64,$07,$0B,$62
  .byte $61,$60,$07,$07,$00,$7B,$07,$05,$00,$7C,$07,$04,$00,$63,$07,$0B,$00,$60,$60,$07,$07,$00,$7B,$07
  .byte $05,$00,$7C,$07,$04,$00,$63,$07,$0B,$00,$60,$07,$08,$00,$7B,$07,$05,$00,$7C,$07,$04,$00,$63,$07
  .byte $0B,$00,$60,$07,$08,$00,$7B,$07,$05,$00,$7C,$07,$04,$00,$63,$07,$0B,$00,$60,$07,$08,$00,$7B,$07
  .byte $05,$00,$7C,$07,$04,$00,$63,$07,$0B,$00,$60,$07,$1F,$61,$60,$07,$00
RENM16:
  .byte $02,$04,$AC,$28,$00,$03,$24,$B0,$00
ROOM17:
  .byte $07,$21,$60,$07,$10,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$60,$07,$10,$00,$60,$00,$00,$00,$60
  .byte $07,$09,$00,$60,$60,$07,$10,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$60,$07,$10,$00,$60,$00,$00
  .byte $00,$60,$07,$09,$00,$60,$60,$07,$10,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$60,$07,$10,$00,$60
  .byte $00,$00,$00,$60,$07,$09,$00,$60,$60,$07,$10,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$60,$07,$10
  .byte $00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$60,$07,$10,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$60
  .byte $07,$10,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$07,$11,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60
  .byte $07,$11,$00,$60,$00,$00,$00,$60,$07,$09,$00,$60,$07,$04,$00,$6E,$07,$0C,$00,$60,$00,$00,$00,$60
  .byte $07,$09,$00,$60,$61,$07,$0A,$62,$64,$62,$07,$04,$00,$66,$00,$00,$00,$66,$07,$09,$00,$60,$60,$07
  .byte $0A,$00,$63,$07,$05,$00,$7B,$00,$00,$00,$7C,$07,$09,$00,$60,$60,$07,$0A,$00,$63,$07,$05,$00,$7B
  .byte $00,$00,$00,$7C,$07,$09,$00,$60,$60,$07,$0A,$00,$63,$07,$05,$00,$7B,$00,$00,$00,$7C,$07,$09,$00
  .byte $60,$60,$07,$0A,$00,$63,$07,$05,$00,$7B,$00,$00,$00,$7C,$07,$04,$00,$67,$68,$00,$00,$00,$60,$60
  .byte $07,$0A,$00,$63,$07,$05,$00,$7B,$00,$00,$00,$7C,$07,$04,$00,$69,$6A,$00,$00,$00,$60,$60,$07,$1E
  .byte $61,$60,$07,$00
RENM17:
  .byte $02,$04,$C4,$28,$00,$03,$84,$50,$00
ROOM18:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07
  .byte $1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60,$07,$1E,$00,$60,$60
  .byte $07,$1E,$00,$60,$60,$07,$1A,$00,$6F,$00,$00,$00,$60,$60,$07,$15,$00,$62,$64,$07,$06,$62,$00,$60
  .byte $60,$07,$16,$00,$63,$07,$07,$00,$60,$60,$07,$16,$00,$63,$07,$07,$00,$60,$60,$07,$16,$00,$63,$07
  .byte $07,$00,$60,$60,$07,$16,$00,$63,$07,$07,$00,$60,$6B,$07,$16,$00,$63,$07,$08,$00,$6C,$07,$0C,$00
  .byte $65,$07,$04,$77,$65,$07,$04,$00,$63,$07,$08,$00,$6D,$07,$16,$00,$63,$07,$08,$00,$07,$20,$61,$07
  .byte $00
RENM18:
  .byte $02,$05,$54,$28,$B0,$05,$A4,$28,$B0
ROOM19:
  .byte $07,$21,$60,$07,$0E,$00,$60,$07,$0F,$00,$60,$60,$07,$0E,$00,$60,$07,$0F,$00,$60,$60,$07,$0E,$00
  .byte $60,$07,$0F,$00,$60,$60,$07,$0E,$00,$60,$07,$0F,$00,$60,$60,$07,$0E,$00,$60,$07,$0F,$00,$60,$60
  .byte $07,$0E,$00,$60,$07,$0F,$00,$60,$60,$07,$0E,$00,$60,$07,$0F,$00,$60,$60,$07,$0E,$00,$60,$07,$0F
  .byte $00,$60,$60,$07,$0E,$00,$65,$07,$0F,$00,$60,$60,$07,$0E,$00,$7A,$07,$0F,$00,$60,$60,$07,$0E,$00
  .byte $7A,$07,$0F,$00,$60,$60,$07,$0E,$00,$7A,$07,$06,$00,$6E,$07,$08,$00,$60,$60,$00,$00,$00,$62,$64
  .byte $07,$09,$62,$65,$07,$0A,$62,$64,$62,$00,$00,$00,$60,$60,$07,$04,$00,$63,$07,$14,$00,$63,$07,$04
  .byte $00,$60,$60,$07,$04,$00,$63,$07,$14,$00,$63,$07,$04,$00,$60,$60,$07,$04,$00,$63,$07,$14,$00,$63
  .byte $07,$04,$00,$60,$07,$05,$00,$63,$07,$14,$00,$63,$07,$0A,$00,$63,$07,$14,$00,$63,$07,$0A,$00,$63
  .byte $07,$14,$00,$63,$07,$05,$00,$07,$0A,$61,$07,$0C,$00,$07,$0A,$61,$07,$00
RENM19:
  .byte $02,$05,$64,$28,$78,$05,$9C,$28,$78
ROOM20:
  .byte $07,$21,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00
  .byte $60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60
  .byte $07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C
  .byte $00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00
  .byte $60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$0C,$00,$60,$60,$07,$11,$00,$60,$07,$09,$00,$6F,$00
  .byte $00,$60,$60,$07,$11,$00,$60,$00,$00,$62,$64,$07,$07,$62,$00,$60,$60,$07,$11,$00,$60,$00,$00,$00
  .byte $63,$07,$08,$00,$60,$60,$07,$11,$00,$65,$00,$00,$00,$63,$07,$08,$00,$60,$07,$12,$00,$79,$00,$00
  .byte $00,$63,$07,$08,$00,$60,$07,$12,$00,$79,$00,$00,$00,$63,$00,$00,$00,$67,$68,$00,$00,$00,$60,$07
  .byte $12,$00,$79,$00,$00,$00,$63,$00,$00,$00,$69,$6A,$00,$00,$00,$60,$07,$12,$61,$65,$07,$0C,$61,$60
  .byte $07,$00
RENM20:
  .byte $03,$05,$44,$28,$B0,$05,$74,$28,$B0,$05,$CC,$28,$80
ROOM21:
  .byte $07,$21,$60,$07,$15,$00,$60,$07,$08,$00,$60,$60,$07,$15,$00,$60,$07,$08,$00,$60,$60,$07,$0D,$00
  .byte $76,$76,$07,$06,$00,$65,$07,$08,$00,$60,$60,$07,$0D,$00,$76,$76,$07,$06,$00,$79,$07,$09,$00,$60
  .byte $07,$0D,$00,$76,$76,$07,$06,$00,$79,$07,$09,$00,$60,$07,$07,$00,$6E,$07,$05,$00,$76,$76,$07,$06
  .byte $00,$79,$07,$09,$00,$60,$00,$62,$62,$64,$07,$08,$62,$00,$76,$76,$07,$06,$62,$65,$07,$08,$62,$61
  .byte $60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76
  .byte $07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07
  .byte $09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00
  .byte $00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F
  .byte $00,$60,$60,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$60,$00,$00,$00,$63,$07,$09,$00
  .byte $76,$76,$07,$0F,$00,$60,$6B,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$6C,$00,$00,$00
  .byte $63,$07,$09,$00,$76,$76,$07,$0F,$00,$60,$6D,$00,$00,$00,$63,$07,$09,$00,$76,$76,$07,$0F,$00,$60
  .byte $07,$05,$61,$07,$08,$74,$07,$12,$61,$60,$07,$00
RENM21:
  .byte $03,$05,$4C,$28,$48,$03,$C4,$78,$00,$01,$DC,$48,$00
ROOM22:
  .byte $07,$21,$60,$07,$1A,$00,$60,$00,$00,$00,$60,$60,$07,$1A,$00,$60,$00,$00,$00,$60,$60,$07,$1A,$00
  .byte $60,$00,$00,$00,$60,$07,$1B,$00,$60,$00,$00,$00,$60,$07,$1B,$00,$60,$00,$00,$00,$60,$07,$10,$00
  .byte $6F,$07,$0A,$00,$60,$00,$00,$00,$60,$61,$62,$62,$64,$07,$09,$62,$07,$06,$71,$07,$04,$62,$64,$62
  .byte $00,$00,$60,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$60,$00,$00,$00,$60,$60
  .byte $00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$60,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00
  .byte $00,$00,$60,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$60,$00,$00,$00,$60,$60
  .byte $00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$60,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00
  .byte $00,$00,$60,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$66,$00,$00,$00,$60,$60
  .byte $00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$7C,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00
  .byte $00,$00,$7C,$00,$00,$00,$60,$60,$00,$00,$63,$07,$13,$00,$63,$00,$00,$00,$7C,$07,$04,$00,$60,$00
  .byte $00,$63,$07,$13,$00,$63,$00,$00,$00,$7C,$07,$04,$00,$60,$00,$00,$63,$07,$13,$00,$63,$00,$00,$00
  .byte $7C,$07,$04,$00,$60,$07,$1F,$61,$07,$00
RENM22:
  .byte $02,$04,$84,$28,$00,$02,$64,$B0,$00
ROOM23:
  .byte $07,$21,$60,$07,$1E,$00,$60,$60,$07,$12,$00,$76,$76,$07,$0A,$00,$60,$60,$07,$12,$00,$76,$76,$07
  .byte $04,$00,$67,$68,$07,$04,$00,$60,$60,$07,$12,$00,$76,$76,$07,$04,$00,$69,$6A,$07,$04,$00,$60,$60
  .byte $07,$12,$00,$76,$76,$07,$08,$62,$64,$00,$60,$60,$07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60
  .byte $07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60,$07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60
  .byte $07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60,$07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60
  .byte $07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60,$07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60
  .byte $07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60,$07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60
  .byte $07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$60,$07,$12,$00,$76,$76,$07,$08,$00,$63,$00,$60,$07
  .byte $13,$00,$76,$76,$07,$08,$00,$63,$00,$60,$07,$0D,$00,$65,$07,$04,$78,$65,$76,$76,$07,$08,$00,$63
  .byte $00,$60,$07,$13,$00,$76,$76,$07,$07,$00,$6E,$63,$00,$60,$07,$04,$61,$07,$09,$75,$07,$12,$61,$60
  .byte $07,$00
RENM23:
  .byte $03,$03,$54,$70,$00,$04,$C4,$28,$00,$05,$7C,$28,$A0
ROOM_LO: .byte <ROOM0,<ROOM1,<ROOM2,<ROOM3,<ROOM4,<ROOM5,<ROOM6,<ROOM7,<ROOM8,<ROOM9,<ROOM10,<ROOM11,<ROOM12,<ROOM13,<ROOM14,<ROOM15,<ROOM16,<ROOM17,<ROOM18,<ROOM19,<ROOM20,<ROOM21,<ROOM22,<ROOM23
ROOM_HI: .byte >ROOM0,>ROOM1,>ROOM2,>ROOM3,>ROOM4,>ROOM5,>ROOM6,>ROOM7,>ROOM8,>ROOM9,>ROOM10,>ROOM11,>ROOM12,>ROOM13,>ROOM14,>ROOM15,>ROOM16,>ROOM17,>ROOM18,>ROOM19,>ROOM20,>ROOM21,>ROOM22,>ROOM23
RENM_LO: .byte <RENM0,<RENM1,<RENM2,<RENM3,<RENM4,<RENM5,<RENM6,<RENM7,<RENM8,<RENM9,<RENM10,<RENM11,<RENM12,<RENM13,<RENM14,<RENM15,<RENM16,<RENM17,<RENM18,<RENM19,<RENM20,<RENM21,<RENM22,<RENM23
RENM_HI: .byte >RENM0,>RENM1,>RENM2,>RENM3,>RENM4,>RENM5,>RENM6,>RENM7,>RENM8,>RENM9,>RENM10,>RENM11,>RENM12,>RENM13,>RENM14,>RENM15,>RENM16,>RENM17,>RENM18,>RENM19,>RENM20,>RENM21,>RENM22,>RENM23
ROOMS_PER = 3
N_STATIONS = 8

; big letters of the title from 96 (third 0)
BIG_P:
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
BIG_C:
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
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
  .byte $70,$70,$70,$70,$50,$50,$50,$50,$70,$70,$70,$70,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$40,$40,$40,$40,$50,$50,$50,$50,$40,$40,$40,$40
BIG_LEN = 384
TXT_BIG:
  .byte 3,12,96,97,100,101,104,105,108,109,0
  .byte 4,12,98,99,102,103,106,107,110,111,0
  .byte 6,10,128,129,136,137,140,141,140,141,132,133,128,129,0
  .byte 7,10,130,131,138,139,142,143,142,143,134,135,130,131,0
  .byte $FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$7D,$68,$59,$4E,$45,$3F,$39,$36,$2A,$36,$2A,$36,$2A,$36,$2A
  .byte $36,$2A,$36,$2A,$36,$2A,$3C,$3C,$3C,$28,$28,$28,$1E,$1E,$1E,$24
  .byte $24,$24,$1B,$1B,$1B,$16,$16,$16,$12,$12,$12,$BD,$BD,$BD,$00,$00
  .byte $00,$00,$FD,$FD,$FD,$FD,$59,$50,$49,$43,$3E,$39,$36,$32,$2F,$2D
  .byte $00,$00,$34,$37,$34,$36,$3F,$42,$3E,$41,$4B,$4F,$4B,$4F,$5B,$5F
  .byte $5A,$5E,$6D,$72,$6C,$72,$83,$89,$82,$89,$9D,$A5,$9D,$A4,$BD,$C6
  .byte $BC,$C5,$E3,$EE,$E3,$ED,$11,$1E,$10,$1D,$50,$50,$50,$50,$50,$00
  .byte $00,$3C,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$2F,$00,$00,$28
  .byte $28,$28,$28,$28,$28,$28,$28,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$97
  .byte $97,$97,$97,$97,$97,$97,$97,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$BD
  .byte $BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD
  .byte $BD,$BD,$BD,$BD,$BD,$28,$28,$28,$21,$26,$2D,$38,$49,$68,$BE,$5B
  .byte $BE,$5B,$BE,$18,$1C,$DF,$B8,$9C,$88,$78,$6C,$62,$59,$52,$4C,$47
  .byte $1C,$DF,$B8,$9C,$88,$78,$6C,$62,$59,$52,$4C,$47,$A1,$63,$36,$13
  .byte $F7,$E0,$CD,$BD,$AF,$A3,$99,$90,$88,$81,$7A,$74,$6F,$6A,$66,$61
  .byte $5E,$5A,$57,$54,$51,$4E,$4C,$4A,$47,$45,$18,$20
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$09,$08,$07,$07,$06,$05,$04,$0B,$0B,$0A,$0A,$09,$09,$08,$08
  .byte $07,$07,$06,$06,$05,$05,$0C,$0B,$09,$0C,$0B,$09,$0C,$0B,$09,$0C
  .byte $0A,$08,$0C,$0A,$08,$0C,$0A,$08,$0C,$0A,$08,$0E,$0C,$0A,$00,$00
  .byte $00,$00,$0E,$0C,$0A,$08,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $00,$00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A
  .byte $0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06
  .byte $06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$0D,$0C,$0B,$0A,$09,$00
  .byte $00,$0D,$0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$0D
  .byte $0C,$0A,$09,$08,$07,$05,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C
  .byte $0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$07
  .byte $07,$07,$07,$06,$06,$0C,$0A,$08,$0A,$09,$08,$06,$05,$04,$08,$07
  .byte $06,$05,$04,$05,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$0C,$0C,$0C,$0B
  .byte $0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$08,$07,$07,$07,$07,$07,$06,$06,$06,$0A,$08
WH_START:
  .byte $00,$01,$08,$16,$1F,$2B,$36,$42,$6A,$87,$B5,$B8,$BE,$C3,$C4,$DC
  .byte $FA
WH_LEN:
  .byte $00,$07,$0E,$09,$0C,$0B,$0C,$28,$1D,$2E,$03,$06,$05,$01,$18,$1E
  .byte $02
W_JUMP = 1
W_STUN = 2
W_PICK = 3
W_CRYS = 4
W_DOCK = 5
W_ALARM = 6
W_DIE = 7
W_EXTRA = 8
W_OVER = 9
W_BONUS = 10
W_SHOT = 11
W_CRUMB = 12
W_STEP = 13
W_CORE = 14
W_LAUNCH = 15
W_KEY = 16

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$0B,$09,$07
  .byte $05,$03,$01,$00,$00,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09
  .byte $09,$08,$08,$07,$07,$06,$06,$05,$05,$0B,$09,$07,$05,$03,$01
EX_NP:
  .byte $00,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15
  .byte $15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17
  .byte $17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19,$19,$19
  .byte $19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B,$0E,$0E,$0E
  .byte $0E,$0E,$0E,$0E,$0E,$10,$10,$10,$10,$11,$11,$11,$11,$12,$12,$12
  .byte $12,$13,$13,$13,$13,$14,$14,$14,$14,$05,$06,$07,$08,$09,$0A
EX_VC:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0A,$08
  .byte $06,$04,$02,$00,$00,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07
  .byte $07,$06,$06,$05,$05,$04,$04,$03,$03,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$B6,$B6,$B6
  .byte $B6,$B6,$B6,$B6,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D
  .byte $B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$03,$02,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$3D,$45,$59
EX_LEN:
  .byte $00,$3C,$08,$14,$06
S_BIG = 1
S_HIT = 2
S_BOOM = 3
S_SHOT = 4
S_SMALL = S_SHOT

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <32,>32, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$60, <32,>32, <SMALL_COL,>SMALL_COL
  .byte 1, $40,$40, <72,>72, <BAR_PAT,>BAR_PAT
  .byte 1, $40,$60, <72,>72, <BAR_COL,>BAR_COL
  .byte 1, $40,$46, <176,>176, <SP_PAT,>SP_PAT
  .byte 1, $40,$66, <176,>176, <SP_COL,>SP_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <32,>32, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$68, <32,>32, <SMALL_COL,>SMALL_COL
  .byte 1, $40,$48, <72,>72, <BAR_PAT,>BAR_PAT
  .byte 1, $40,$68, <72,>72, <BAR_COL,>BAR_COL
  .byte 1, $40,$4E, <176,>176, <SP_PAT,>SP_PAT
  .byte 1, $40,$6E, <176,>176, <SP_COL,>SP_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <32,>32, <SMALL_PAT,>SMALL_PAT
  .byte 1, $08,$70, <32,>32, <SMALL_COL,>SMALL_COL
  .byte 1, $40,$50, <72,>72, <BAR_PAT,>BAR_PAT
  .byte 1, $40,$70, <72,>72, <BAR_COL,>BAR_COL
  .byte 1, $40,$56, <176,>176, <SP_PAT,>SP_PAT
  .byte 1, $40,$76, <176,>176, <SP_COL,>SP_COL
  .byte 0
TILE_LOAD:
  .byte 1, $00,$43, <232,>232, <ST_PAT,>ST_PAT
  .byte 3, $00,$63, <232,>232, <ST_COL,>ST_COL
  .byte 1, $00,$4B, <232,>232, <ST_PAT,>ST_PAT
  .byte 3, $00,$6B, <232,>232, <ST_COL,>ST_COL
  .byte 1, $00,$53, <232,>232, <ST_PAT,>ST_PAT
  .byte 3, $00,$73, <232,>232, <ST_COL,>ST_COL
  .byte 0

; station names (centred on row 12)
TXT_S0:
  .byte 12,10,"MINING POST",0
  .byte $FF
TXT_S1:
  .byte 12,11,"CARGO HALL",0
  .byte $FF
TXT_S2:
  .byte 12,10,"POWER RELAY",0
  .byte $FF
TXT_S3:
  .byte 12,10,"GRAVITY WELL",0
  .byte $FF
TXT_S4:
  .byte 12,11,"OLD QUARRY",0
  .byte $FF
TXT_S5:
  .byte 12,12,"SMELTER",0
  .byte $FF
TXT_S6:
  .byte 12,11,"DEEP NEST",0
  .byte $FF
TXT_S7:
  .byte 12,10,"CORE CITADEL",0
  .byte $FF
SNAME_LO: .byte <TXT_S0,<TXT_S1,<TXT_S2,<TXT_S3,<TXT_S4,<TXT_S5,<TXT_S6,<TXT_S7
SNAME_HI: .byte >TXT_S0,>TXT_S1,>TXT_S2,>TXT_S3,>TXT_S4,>TXT_S5,>TXT_S6,>TXT_S7
