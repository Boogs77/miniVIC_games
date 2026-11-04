;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   DUNE RANGER  -  an original side-scrolling rover game      ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: deep space miner (VDP, NMI + trampoline $0FD0, AY    ;
;   engine, 2 players taking turns)                            ;
;                                                              ;
;   - a ranger drives a rover across a red desert planet from  ;
;     outpost to outpost: 8 legs by day, then the night run    ;
;   - the ground scrolls pixel by pixel in four bands: mesas   ;
;     at 1/4 of the speed, dunes at 1/2, track and pebbles at  ;
;     full speed (the track is a ring of column types: flat,   ;
;     crater slopes and bottom, soft sand)                     ;
;   - craters to jump, rocks to shoot (big ones take 2 hits),  ;
;     spring mines that hop when the rover comes near, sand    ;
;     worms that rise out of the track, drones that drop       ;
;     darts, sandstorms that chase the rover from behind       ;
;   - joystick: RIGHT faster, LEFT slower, button 1 = jump,    ;
;     button 2 = fire (forward and up at the same time)        ;
;   - points: rock 100 / 200, mine 150, worm 500, drone 300    ;
;     (whole wave +1000), dart 50, crater jumped 50; at every  ;
;     outpost a time bonus and PERFECT +5000 with no crash;    ;
;     3 lives, one more at 10000 and every 30000; 1 or 2       ;
;     players taking turns                                     ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 28 of the save     ;
;     area, lib_records.asm); the title shows them every 5 s   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes, engine hum, shots, jumps, mines, worms, storm,    ;
;     explosions                                               ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI) and draws the bands ;
;     first, top to bottom, before the beam gets there; the    ;
;     NMI only copies the SAT and plays the sound              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: lives left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
LEG         = $40      ; ---- block of the player, saved: leg 0-7
ROUND       = $41      ;      0 day, 1 night
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
PERF        = $43      ;      1 = no crash in this leg
FRESH       = $44      ;      1 = a new leg (the intro, the tune)
PBLOCK      = 5
PAL         = $48      ; leg + 8 x round: palette and course
GSTATE      = $49      ; 0 playing, 1 rover lost, 3 outpost reached
GT          = $4A      ; timer of GSTATE
JOYC        = $4B      ; both joysticks drive the player playing
JOYP        = $4C      ; JOYC of the frame before
HUDD        = $4D      ; to draw again: 1 score, 2 time, 4 lives and bar
FIRSTT      = $4E      ; 1 = first turn of the game
SHOWP       = $4F      ; 1 = the intro before the leg
TXF         = $50      ; track position: pixels from the start of the leg (fraction, lo, hi)
TXL         = $51
TXH         = $52
SPDL        = $53      ; speed 8.8 (pixels per frame)
SPDH        = $54
TSPD        = $55      ; target speed (whole pixels 1-3)
SH          = $56      ; track shift 0-7
COL         = $57      ; ring index of the column at the left edge
MQ          = $58      ; mesas: tile offset 0-15, shift 0-7
MR          = $59
OMR         = $5A      ; mesa shift written to the patterns ($FF = none)
DQ          = $5B      ; dunes: tile offset 0-7, shift 0-7
DR          = $5C
OPR         = $5D      ; pebble shift written ($FF = none)
RX          = $5E      ; rover: left x on the screen, top y
RY          = $5F
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
RYF         = $72      ; rover y fraction
VYL         = $73      ; rover vertical speed 8.8
VYH         = $74
AIR         = $75      ; 1 = jumping
BOUNCE      = $76      ; frames of the landing bounce
SONG        = $77      ; tune to play
WHF         = $78      ; wheel turn counter
OVERC       = $79      ; 1 = a crater passed under the rover during this jump
FIRET       = $7A      ; frames before the next shot while the button is held
FSX         = $7B      ; forward shot: x (0 = none), top pixel row
FSY         = $7C
TXCL        = $7D      ; column at the left edge (TX / 8)
TXCH        = $7E
SOFTF       = $7F      ; 1 = the rover is in soft sand
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
USX         = $87      ; 2 up shots: x (0 = none), y
USY         = $89
WCL         = $8B      ; next column to write into the ring
WCH         = $8C
EVP         = $8D      ; 2 bytes: next event of the leg (its code)
NEXTL       = $8F      ; column of that event
NEXTH       = $90
PEND        = $91      ; crater / soft sand columns still to write
PENDT       = $92      ; index into PSEQ
TIMEF       = $93      ; frames of the second
TIMEL       = $94      ; time of the leg (BCD): tens and units, hundreds
TIMEH       = $95
MRK         = $96      ; progress marker 0-24
MNL         = $97      ; column where the marker moves on
MNH         = $98
MSTEP       = $99      ; columns per marker pixel
STORM       = $9A      ; 1 = a sandstorm chases the rover
SWF         = $9B      ; storm front: world x (fraction, lo, hi)
SWL         = $9C
SWH         = $9D
STENL       = $9E      ; column where the storm dies out
STENH       = $9F
WAVEN       = $A0      ; drones in the wave
WAVEK       = $A1      ; drones shot ($80 = one got away)
MSGT        = $A2      ; frames the message of row 7 stays
RR          = $A3      ; first object in the SAT (turns)
DEATH       = $A4      ; why the rover was lost (tests): 1 crater 2 rock 3 mine 4 worm 5 dart 6 storm
SLOT        = $A5
ENGON       = $A6      ; 1 = the engine hums (read by the NMI)
TSEC        = $A7      ; time of the leg in seconds (binary, stops at 255)
BONL        = $A8
BONH        = $A9
OUTL        = $AA      ; outpost: world x
OUTH        = $AB
OUTV        = $AC      ; 1 = the outpost is on the track
DTIME       = $AD      ; frames between the darts of a drone
TRKC        = $AE      ; colour of the track (sand mounds, dust)
SSXL        = $B2      ; storm front on the screen (signed)
SSXH        = $B3
OSXL        = $B4      ; outpost on the screen (signed)
OSXH        = $B5
OSTC        = $B6      ; columns of the sandstorm wall drawn on rows 15-18

GROUND      = 136      ; rover top when on the track
SURF        = 152      ; first pixel row of the track

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
OX         = $E0         ; sprite being added: left x, top y, pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4         ; next free byte of the SAT
OXH        = $E5         ; 0 on the screen, $FF = left of it (early clock)

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

; ---------------- objects: 16 slots, one byte per field ----------------
;   0-5 on the ground (world x), 6-8 drones, 9-10 darts, 11-15 free
;   ground kinds keep the world x in O_XL/O_XH, air kinds the screen x (O_XF = fraction)
NOB        = 16
O_K        = $0200       ; kind (K_*, 0 = free)
O_XF       = $0210
O_XL       = $0220
O_XH       = $0230
O_Y        = $0240       ; air kinds: top y
O_YF       = $0250
O_VXL      = $0260       ; speed 8.8 (signed)
O_VXH      = $0270
O_VYL      = $0280
O_VYH      = $0290
O_T        = $02A0       ; timer
O_S        = $02B0       ; state
O_H        = $02C0       ; hits left / height / passes
O_SXL      = $02D0       ; ground kinds: x on the screen (signed)
O_SXH      = $02E0
O_BY       = $02F0       ; drones: base y; wave phase in O_VYL

G_AIR      = 6           ; first slot of every group
G_DART     = 9
G_BOOM     = 13

K_ROCK     = 1
K_BIG      = 2
K_MINE     = 3
K_WORM     = 4
K_GBOOM    = 5
K_PUFF     = 6
K_DRONE    = 7
K_DART     = 8
K_ABOOM    = 9

; ---------------- other RAM ----------------
TRACK      = $0300       ; ring of 256 column types
TRB        = $0400       ; ring: first tile code of the pair (this column, next column)
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player

; ---------------- parameters ----------------
BTN_MASK    = %00110000
FIRE_T      = 14         ; frames between shots with the button held

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 28         ; fixed zone of the game in the save area
REC_RAM     = $7C00      ; $2A0 bytes after the program
REC_ROW     = 9          ; table on rows 9-17 of the title
REC_JOY2    = $FF        ; both joysticks drive the player playing

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
  STA ENGON
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
;  TITLE: the name, what things are worth
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  STZ ENGON
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
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

; rows 9-17 of the title and the sprites beside them (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the rover and the others (sprites)
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
  RTS

; one frame of the title: the wheels turn, the worm and the drone move;
; every 5 s the title page and the table of the records take turns
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR REC_TICK
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
  AND #8
  LSR A                        ; 0 or 4: the second pattern
  STA T0
  CLC
  ADC #PT_WHEEL
  STA SAT_BUFFER+6
  LDA #PT_DRONE
  CLC
  ADC T0
  STA SAT_BUFFER+22
  LDA FRAME_CNT
  AND #$20
  BEQ .tf_w
  LDA #PT_WORMO-PT_WORM-12
.tf_w:
  CLC
  ADC #PT_WORM+12
  STA SAT_BUFFER+18
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: leg 1, 3 lives for every player
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
  STZ LEG
  STZ ROUND
  LDA #$01                     ; first extra life at 10000
  STA NEXTX
  LDA #1
  STA FRESH
  STA PERF
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then the leg
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

STAGE_START:
  LDX #$FF
  TXS
  STZ ENGON
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA LEG
  LDX ROUND
  BEQ .ss_d
  ORA #8
.ss_d:
  STA PAL
  LDA FRESH
  BEQ .ss_i
  LDA #1                       ; a new leg: no crash yet
  STA PERF
.ss_i:
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT                   ; the tune: first turn or a new leg
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
  LDA #40
  JSR WAIT_FRAMES
  BRA .ss_w
.ss_short:
  LDA #120
  JSR WAIT_FRAMES
.ss_w:
  JSR VDP_INT_OFF
  STZ FRESH
  STZ GSTATE
  LDA #CMD_GAME
  STA SND_CMD
  JSR LEG_START
  JSR BUILD_SAT
  JSR VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR DRAW_BANDS               ; first: the beam is still above the bands
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  LDA GSTATE
  BNE .gl_ns
  JSR ROVER_CTRL
.gl_ns:
  JSR MOVE
  JSR WRITE_COLS
  JSR ROVER
  JSR SHOTS
  JSR OBJECTS
  JSR STORM_FRAME
  JSR OUTPOST
  JSR CLOCK
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  CMP #3
  BEQ .gl_win
  DEC GT                       ; lost: the explosion goes on
  BNE GAME_LOOP
  JMP LOSE_LIFE
.gl_win:
  JMP LEG_CLEAR


; ===============================================================
;  THE OUTPOST IS REACHED: time bonus, perfect, the next leg
; ===============================================================
LEG_CLEAR:
  STZ ENGON
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #30                      ; the rover rolls to a stop
  STA GT
.lc_r:
  JSR VDP_INT_OFF
  JSR DRAW_BANDS
  JSR MOVE
  JSR WRITE_COLS
  JSR OBJECTS
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA SPDL                     ; slow down
  SEC
  SBC #24
  STA SPDL
  BCS .lc_n
  LDA SPDH
  BEQ .lc_z
  DEC SPDH
  BRA .lc_n
.lc_z:
  STZ SPDL
.lc_n:
  DEC GT
  BNE .lc_r
  STZ SPDL
  STZ SPDH
  JSR VDP_INT_OFF
  LDA #<TXT_OUT
  STA TP
  LDA #>TXT_OUT
  STA TP+1
  JSR PRINT
  LDA LEG
  INC A
  ORA #$30
  STA VDATA
  LDA #<TXT_REACHED
  STA TP
  LDA #>TXT_REACHED
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #60
  JSR WAIT_FRAMES
  ; ---- time bonus: (par - seconds) x 100
  LDX PAL
  LDA LEG_PAR,X
  SEC
  SBC TSEC
  BCS .lc_tb
  LDA #0
.lc_tb:
  CMP #100
  BCC .lc_tc
  LDA #99
.lc_tc:
  JSR BIN2BCD
  STA BONH
  JSR VDP_INT_OFF
  LDA #<TXT_TBONUS
  STA TP
  LDA #>TXT_TBONUS
  STA TP+1
  JSR PRINT
  LDA BONH
  JSR PUT_2
  LDA #'0'
  STA VDATA
  STA VDATA
  STZ PTS_L
  LDA BONH
  STA PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  LDA PERF                     ; no crash in the leg: perfect
  BEQ .lc_t
  LDA #40
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  LDA #<TXT_PERFECT
  STA TP
  LDA #>TXT_PERFECT
  STA TP+1
  JSR PRINT
  LDA #$00
  LDY #$50
  JSR ADD_PTS
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
.lc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .lc_t
  LDA #90
  JSR WAIT_FRAMES
  LDA #1                       ; the next leg; after the eighth, the night run
  STA FRESH
  INC LEG
  LDA LEG
  CMP #8
  BCC .lc_s
  STZ LEG
  LDA #1
  STA ROUND
.lc_s:
  JSR SAVE_PLAYER
  JMP STAGE_START

LOSE_LIFE:
  LDX CURP
  DEC LIVES,X
  STZ PERF
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
  STZ ENGON
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
  LDA #<TXT_OVERP
  STA TP
  LDA #>TXT_OVERP
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
  TXA                          ; extra byte: the leg reached (1-8 day, 9-16 night)
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
  LDA #W_SIGN
.rn_p:
  JSR SFX_WHISTLE
  PLX
  RTS
REC_NAME:  .byte "DUNE RANGER     "
REC_HEAD:  .byte "BEST RANGERS",0
REC_XLBL:  .byte "LEG ",0


; ===============================================================
;  INTRO: player, leg, what is new on the way
; ===============================================================
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
  LDA ROUND
  BEQ .in_d
  LDA #<TXT_NIGHT
  STA TP
  LDA #>TXT_NIGHT
  STA TP+1
  JSR PRINT
.in_d:
  LDA #<TXT_LEG
  STA TP
  LDA #>TXT_LEG
  STA TP+1
  JSR PRINT
  LDA LEG
  INC A
  ORA #$30
  STA VDATA
  LDA #<TXT_LIVES
  STA TP
  LDA #>TXT_LIVES
  STA TP+1
  JSR PRINT
  LDX CURP
  LDA LIVES,X
  ORA #$30
  STA VDATA
  LDA FRESH                    ; the hint of a new leg
  BEQ .in_r
  LDX LEG
  LDA ROUND
  BEQ .in_h
  LDX #8
.in_h:
  LDA HINT_LO,X
  STA TP
  LDA HINT_HI,X
  STA TP+1
  JMP PRINT
.in_r:
  RTS


; ===============================================================
;  HUD: rows 0-2 (scores, leg, time, lives, progress bar),
;  messages on row 7 (in the sky)
; ===============================================================
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #1
  LDY #4
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
  BNE .dt_e
  LDX #0
  LDY #20
  JSR NT_XY
  LDA #'2'
  STA VDATA
  LDA #'U'
  STA VDATA
  LDA #'P'
  STA VDATA
  LDX #$01
  JMP DRAW_SCORE
.dt_e:
  RTS

; X = player: his score on row 0 (keeps X)
DRAW_SCORE:
  PHX
  LDY SC_COL,X
  LDX #0
  JSR NT_XY
  PLX
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

; row 1: leg and time; row 2: spare lives and the progress bar
DRAW_STATUS:
  LDX #1
  LDY #12
  JSR NT_XY
  LDY #0
.ds_s:
  LDA TXT_LEGH,Y
  BEQ .ds_se
  STA VDATA
  INY
  BRA .ds_s
.ds_se:
  LDA LEG
  INC A
  ORA #$30
  STA VDATA
  LDA #' '
  LDX ROUND
  BEQ .ds_n
  LDA #'N'
.ds_n:
  STA VDATA
  JSR DRAW_TIME
  LDX #2
  LDY #0
  JSR NT_XY
  LDX CURP                     ; spare lives (at most 4)
  LDA LIVES,X
  BEQ .ds_z
  DEC A
.ds_z:
  STA T0
  LDX #0
.ds_l:
  LDA #$20
  CPX T0
  BCS .ds_b
  LDA #T_LIFE
.ds_b:
  STA VDATA
  INX
  CPX #6
  BNE .ds_l
  LDX #0                       ; the bar: columns 6-30, a tick every 3, yellow up to this leg
  LDY #0
.ds_bar:
  LDA #T_BAR
  CPY #3
  BNE .ds_bt
  LDY #0
.ds_bt:
  CPY #0
  BNE .ds_bc
  LDA #T_TICK
.ds_bc:
  STA T1
  TXA                          ; done when column < leg x 3
  STA T2
  LDA LEG
  ASL A
  ADC LEG
  CMP T2
  BCC .ds_bw
  BEQ .ds_bw
  LDA T1
  CLC
  ADC #2
  STA T1
.ds_bw:
  LDA T1
  STA VDATA
  INY
  INX
  CPX #25
  BNE .ds_bar
  RTS

DRAW_TIME:
  LDX #1
  LDY #21
  JSR NT_XY
  LDY #0
.dm_t:
  LDA TXT_TIME,Y
  BEQ .dm_te
  STA VDATA
  INY
  BRA .dm_t
.dm_te:
  LDA TIMEH
  ORA #$30
  STA VDATA
  LDA TIMEL
  JMP PUT_2

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 time, 4 lives and bar
  LDA HUDD
  BEQ .uh_m
  STZ HUDD
  PHA
  AND #1
  BEQ .uh_t
  LDX CURP
  JSR DRAW_SCORE
.uh_t:
  PLA
  PHA
  AND #2
  BEQ .uh_l
  JSR DRAW_TIME
.uh_l:
  PLA
  AND #4
  BEQ .uh_m
  JSR DRAW_STATUS
.uh_m:
  LDA MSGT                     ; the message of row 7 goes away: the sky again
  BEQ UH_R
  DEC MSGT
  BNE UH_R
CLEAR_MSG:
  LDX #7
  LDY #0
  JSR NT_XY
  LDX #0
.uh_c:
  LDA SKYROW7,X
  STA VDATA
  INX
  CPX #32
  BNE .uh_c
UH_R:
  RTS

; A = message number: on row 7 for 2 seconds
MESSAGE:
  PHA
  JSR CLEAR_MSG
  PLA
  TAX
  LDA MSG_LO,X
  STA TP
  LDA MSG_HI,X
  STA TP+1
  JSR PRINT
  LDA #120
  STA MSGT
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
  LDA LEG,Y
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
  STA LEG,Y
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

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 10000, then every 30000
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
  LDA LIVES,X                  ; at most 9 (one digit on the intro)
  CMP #9
  BCS .as_m
  INC LIVES,X
.as_m:
  SED
  LDA NEXTX
  CLC
  ADC #$03
  CLD
  BCC .as_x
  LDA #$FF                     ; past 990000: no more
.as_x:
  STA NEXTX
  LDA #4                       ; the new life in the HUD
  TSB HUDD
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS
; ===============================================================
;  WORLD: the scene, the colours of the leg, the bands that
;  scroll, the ring of track columns written from the events
; ===============================================================

; a leg starts (or starts again): the scene, the colours, the track from column 0
LEG_START:
  JSR CLEAR_NT
  JSR DRAW_TOP
  JSR DRAW_STATUS
  LDA #$60                     ; rows 3-23: the scene
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T1
  LDA #<(21*32)
  STA T2
  LDA #>(21*32)
  STA T3
  LDA #<SCENE
  STA PTR
  LDA #>SCENE
  STA PTR+1
  JSR VCOPY
  JSR SET_COLOURS
  LDX #$5C                     ; rover, track, time, storm, outpost ($50-$AC): all to 0
.ls_z:
  STZ TXF,X
  DEX
  BPL .ls_z
  LDX #NOB-1
.ls_o:
  STZ O_K,X
  DEX
  BPL .ls_o
  LDA #$FF
  STA OMR
  STA OPR
  STZ OSTC                     ; the scene has no sandstorm wall
  LDA #GROUND
  STA RY
  LDA #56
  STA RX
  LDA #2
  STA TSPD
  LDA #1
  STA ENGON
  LDX PAL                      ; darts: every 130 - 4 x (leg + 8 x round) frames
  TXA
  ASL A
  ASL A
  STA T0
  LDA #130
  SEC
  SBC T0
  STA DTIME
  LDA LEG_STEP,X
  STA MSTEP
  STA MNL
  STZ MNH
  LDA LEG_LO,X                 ; the events of the leg
  STA EVP
  LDA LEG_HI,X
  STA EVP+1
  LDA (EVP)                    ; first gap
  STA NEXTL
  STZ NEXTH
  INC EVP
  BNE .ls_e
  INC EVP+1
.ls_e:
  LDX #0                       ; the ring: all flat
.ls_r:
  STZ TRACK,X
  LDA PAIRB
  STA TRB,X
  INX
  BNE .ls_r
  JSR MOVE
  JMP WRITE_COLS

; colours of the leg PAL: mesas, dunes, track, specks
SET_COLOURS:
  LDX PAL
  LDA P_TRK,X
  STA TRKC
  LDA P_MESA,X                 ; mesa base: code 4 of third 1
  ORA #$10
  LDY #$28
  LDX #$20
  JSR FILL8
  LDX PAL                      ; dune base: code 5 of thirds 1 and 2
  LDA P_DUNE,X
  ORA #$10
  PHA
  LDY #$28
  LDX #$28
  JSR FILL8
  PLA
  LDY #$30
  LDX #$28
  JSR FILL8
  LDX PAL                      ; ground: code 6 = track colour, code 7 = specks
  LDA P_TRK,X
  ORA #$10
  LDY #$30
  LDX #$30
  JSR FILL8
  LDX PAL
  LDA P_SPK,X
  ORA #$10
  LDY #$30
  LDX #$38
  JSR FILL8
  LDX PAL                      ; sandstorm wall (tile 24): track colour on the dune colour
  LDA P_TRK,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA P_DUNE,X
  PHA
  LDY #$28
  LDX #$C0
  JSR FILL8
  PLA
  LDY #$30
  LDX #$C0
  JSR FILL8
  LDX PAL                      ; mesas 96-127: mesa on black
  LDA P_MESA,X
  ASL A
  ASL A
  ASL A
  ASL A
  STA T5
  LDA #$00
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | $2B)
  STA T1
  STZ T2
  LDA #1
  STA T3
  LDA T5
  JSR VFILL
  LDX PAL                      ; dunes 128-255: dune on mesa
  LDA P_DUNE,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA P_MESA,X
  STA T5
  LDA #$00
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | $2C)
  STA T1
  STZ T2
  LDA #4
  STA T3
  LDA T5
  JSR VFILL
  LDX PAL                      ; pebbles 8-15: specks on the track colour
  LDA P_SPK,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA P_TRK,X
  STA T5
  LDA #$40
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | $30)
  STA T1
  LDA #64
  STA T2
  STZ T3
  LDA T5
  JSR VFILL
  LDX PAL                      ; track 96-255: top line, then track, on the dune colour
  LDA P_TOP,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA P_DUNE,X
  STA T4
  LDA P_TRK,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA P_DUNE,X
  STA T5
  LDA #$00
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $33)
  STA VREG
  LDX #10                      ; 10 pairs
.sc_p:
  LDY #8                       ; row 19: 8 shifts, top line first
.sc_a:
  LDA T4
  STA VDATA
  LDA T5
  STA VDATA
  STA VDATA
  STA VDATA
  STA VDATA
  STA VDATA
  STA VDATA
  STA VDATA
  DEY
  BNE .sc_a
  LDY #64                      ; row 20: all track
.sc_b:
  STA VDATA
  DEY
  BNE .sc_b
  DEX
  BNE .sc_p
  RTS

; A = colour, X = VRAM address low, Y = high: 8 bytes
FILL8:
  STX VREG
  PHA
  TYA
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  PLA
  LDX #8
.f8_l:
  STA VDATA
  DEX
  BNE .f8_l
  RTS

SET_VADDR:                     ; A = low, X = high (without the write bit)
  STA VREG
  TXA
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  RTS

; ---------------------------------------------------------------
; the bands, top to bottom so the beam never catches up
; ---------------------------------------------------------------
DRAW_BANDS:
  LDA MR                       ; mesas: patterns of codes 96-127 for the shift
  CMP OMR
  BEQ .db_mn
  STA OMR
  CLC
  ADC #>MESA_SH
  STA PTR+1
  LDA #<MESA_SH
  STA PTR
  LDA #$00
  LDX #$0B
  JSR SET_VADDR
  LDY #0
.db_mp:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .db_mp
.db_mn:
  LDA #$40                     ; row 10: 96 + (q + c) & 15
  LDX #$39
  JSR SET_VADDR
  LDX MQ
  LDY #32
.db_m0:
  LDA ROT16,X
  ORA #96
  STA VDATA
  INX
  DEY
  BNE .db_m0
  LDX MQ                       ; row 11 follows: 112 + (q + c) & 15
  LDY #32
.db_m1:
  LDA ROT16,X
  ORA #112
  STA VDATA
  INX
  DEY
  BNE .db_m1
  LDA #$A0                     ; row 13: 128 + r * 8 + (q + c) & 7
  LDX #$39
  JSR SET_VADDR
  LDA DR
  ASL A
  ASL A
  ASL A
  ORA #128
  STA T0
  LDX DQ
  LDY #32
.db_d0:
  LDA ROT8,X
  ORA T0
  STA VDATA
  INX
  DEY
  BNE .db_d0
  LDA T0                       ; row 14: 192 + r * 8 + ...
  EOR #$40
  STA T0
  LDX DQ
  LDY #32
.db_d1:
  LDA ROT8,X
  ORA T0
  STA VDATA
  INX
  DEY
  BNE .db_d1
  LDA SH                       ; pebbles: patterns of codes 8-15 of third 2 for the shift
  CMP OPR
  BEQ .db_tn
  STA OPR
  LSR A                        ; PEB_SH + shift x 64
  LSR A
  STA T1
  LDA SH
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #<PEB_SH
  STA PTR
  LDA T1
  ADC #>PEB_SH
  STA PTR+1
  LDA #$40
  LDX #$10
  JSR SET_VADDR
  LDY #0
.db_pp:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #64
  BNE .db_pp
.db_tn:
  LDA #$60                     ; row 19: pair code + shift
  LDX #$3A
  JSR SET_VADDR
  LDX COL
  LDY #32
.db_t0:
  LDA TRB,X
  ORA SH
  STA VDATA
  INX
  DEY
  BNE .db_t0
  LDA SH                       ; row 20: + 8
  ORA #8
  STA T0
  LDX COL
  LDY #32
.db_t1:
  LDA TRB,X
  ORA T0
  STA VDATA
  INX
  DEY
  BNE .db_t1
  LDA COL                      ; row 21: pebbles, 8 + (col + c) & 7
  AND #7
  TAX
  LDY #32
.db_p:
  LDA ROT8,X
  ORA #8
  STA VDATA
  INX
  DEY
  BNE .db_p
  RTS

; ---------------------------------------------------------------
; speed towards the target, track position, shifts of the bands
; ---------------------------------------------------------------
MOVE:
  LDA GSTATE                   ; the rover lost: no more scrolling
  CMP #1
  BNE .mv_s
  STZ SPDL
  STZ SPDH
  BRA .mv_sh
.mv_s:
  CMP #3                       ; at the outpost LEG_CLEAR brakes
  BEQ .mv_go
  LDA SPDH                     ; target = TSPD.00, steps of 1/32 land on it
  CMP TSPD
  BNE .mv_ne
  LDA SPDL
  BEQ .mv_go
  BRA .mv_dn
.mv_ne:
  BCS .mv_dn
  LDA SPDL                     ; faster: + 1/32 a frame
  CLC
  ADC #8
  STA SPDL
  BCC .mv_go
  INC SPDH
  BRA .mv_go
.mv_dn:
  LDA SPDL                     ; slower: - 1/32 a frame, 1/16 in soft sand
  SEC
  SBC #8
  LDX SOFTF
  BEQ .mv_d1
  SBC #8
.mv_d1:
  STA SPDL
  BCS .mv_go
  DEC SPDH
  BPL .mv_go
  STZ SPDH
  STZ SPDL
.mv_go:
  CLC
  LDA TXF
  ADC SPDL
  STA TXF
  LDA TXL
  ADC SPDH
  STA TXL
  LDA TXH
  ADC #0
  STA TXH
.mv_sh:
  LDA TXL
  AND #7
  STA SH
  LDA TXH                      ; column = TX >> 3
  STA TXCH
  LDA TXL
  LSR TXCH
  ROR A
  LSR TXCH
  ROR A
  LSR TXCH
  ROR A
  STA TXCL
  STA COL
  LDA TXL                      ; dunes: (TX >> 1) & 63
  LSR A
  AND #63
  PHA
  AND #7
  STA DR
  PLA
  LSR A
  LSR A
  LSR A
  STA DQ
  LDA TXH                      ; mesas: (TX >> 2) & 127
  STA T0
  LDA TXL
  LSR T0
  ROR A
  LSR T0
  ROR A
  AND #127
  PHA
  AND #7
  STA MR
  PLA
  LSR A
  LSR A
  LSR A
  STA MQ
  RTS

; ---------------------------------------------------------------
; the ring of columns: written 36 columns ahead of the left edge
; ---------------------------------------------------------------
WRITE_COLS:
  LDA TXCL                     ; until WC = left column + 36
  CLC
  ADC #36
  STA T6
  LDA TXCH
  ADC #0
  STA T7
  LDA WCL
  CMP T6
  LDA WCH
  SBC T7
  BCS .wc_r
  JSR WRITE_ONE
  BRA WRITE_COLS
.wc_r:
  RTS

WRITE_ONE:
  LDA PEND                     ; events only between craters
  BNE .wo_t
.wo_ev:
  LDA WCL                      ; WC >= next event column?
  CMP NEXTL
  LDA WCH
  SBC NEXTH
  BCC .wo_t
  JSR EVENT
  LDA PEND
  BEQ .wo_ev
.wo_t:
  LDA #0
  LDX PEND
  BEQ .wo_w
  DEC PEND
  LDX PENDT
  LDA PSEQ,X
  INC PENDT
.wo_w:
  LDX WCL                      ; ring index = column & 255
  STA TRACK,X
  ASL A                        ; this column with a flat one after it (fixed by the next)
  ASL A
  ASL A
  TAY
  LDA PAIRB,Y
  STA TRB,X
  DEX                          ; the column before with this one
  LDA TRACK,X
  ASL A
  ASL A
  ASL A
  INX
  ORA TRACK,X
  TAY
  LDA PAIRB,Y
  DEX
  STA TRB,X
  INC WCL
  BNE .wo_r
  INC WCH
.wo_r:
  RTS

; the event at EVP happens at column WC: then the next gap
EVENT:
  LDA (EVP)
  STA T0
  JSR EV_NEXT
  LDA T0
  BEQ .ev_gap                  ; 0: nothing (long gaps)
  CMP #$FF
  BEQ .ev_end
  CMP #$10
  BCS .ev_obj
  TAX                          ; 1-4: craters, soft sand
  LDA PS_START,X
  STA PENDT
  LDA PS_LEN,X
  STA PEND
  BRA .ev_gap
.ev_obj:
  CMP #$20
  BCS .ev_dr
  AND #$0F                     ; $10-$13: rock, big rock, mine, worm
  TAX
  LDA EV_KIND,X
  JSR SPAWN_G
  BRA .ev_gap
.ev_dr:
  CMP #$30
  BCS .ev_st
  AND #$0F                     ; $2n: a wave of n drones
  JSR SPAWN_WAVE
  BRA .ev_gap
.ev_st:
  LDA (EVP)                    ; $30: a sandstorm, length / 8 columns
  JSR EV_NEXT
  JSR START_STORM
.ev_gap:
  LDA (EVP)                    ; the next event: column + gap
  JSR EV_NEXT
  CLC
  ADC NEXTL
  STA NEXTL
  BCC .ev_r
  INC NEXTH
.ev_r:
  RTS
.ev_end:
  LDA WCL                      ; the outpost: world x = column x 8
  STA OUTL
  LDA WCH
  ASL OUTL
  ROL A
  ASL OUTL
  ROL A
  ASL OUTL
  ROL A
  STA OUTH
  LDA #1
  STA OUTV
  LDA #$FF                     ; no more events
  STA NEXTH
  RTS

EV_NEXT:                       ; keeps A
  INC EVP
  BNE .en_r
  INC EVP+1
.en_r:
  RTS

EV_KIND:
  .byte K_ROCK, K_BIG, K_MINE, K_WORM

; ---------------------------------------------------------------
; the time of the leg and the progress marker
; ---------------------------------------------------------------
CLOCK:
  LDA GSTATE
  BNE .ck_r
  INC TIMEF
  LDA TIMEF
  CMP #60
  BCC .ck_m
  STZ TIMEF
  LDA TSEC
  CMP #255
  BEQ .ck_b
  INC TSEC
.ck_b:
  SED
  LDA TIMEL
  CLC
  ADC #1
  STA TIMEL
  LDA TIMEH
  ADC #0
  CMP #10
  BCC .ck_h
  LDA #9
.ck_h:
  STA TIMEH
  CLD
  LDA #2
  TSB HUDD
.ck_m:
  LDA TXCL                     ; the marker moves one pixel every MSTEP columns
  CMP MNL
  LDA TXCH
  SBC MNH
  BCC .ck_r
  LDA MRK
  CMP #24
  BCS .ck_r
  INC MRK
  LDA MNL
  CLC
  ADC MSTEP
  STA MNL
  BCC .ck_r
  INC MNH
.ck_r:
  RTS

; ---------------------------------------------------------------
; the outpost at the end of the leg
; ---------------------------------------------------------------
OUTPOST:
  LDA OUTV
  BEQ .op_r
  SEC                          ; on the screen: outpost - TX
  LDA OUTL
  SBC TXL
  STA OSXL
  LDA OUTH
  SBC TXH
  STA OSXH
  LDA GSTATE
  BNE .op_r
  LDA OSXH                     ; reached when it is level with the rover
  BMI .op_in
  BNE .op_r
  LDA OSXL
  CMP RX
  BCC .op_in
  BEQ .op_in
.op_r:
  RTS
.op_in:
  LDA #3
  STA GSTATE
  RTS

; ---------------------------------------------------------------
; the sandstorm: A = length / 8 columns
; ---------------------------------------------------------------
START_STORM:
  STA T1                       ; ends at WC + length x 8
  STZ T2
  ASL T1
  ROL T2
  ASL T1
  ROL T2
  ASL T1
  ROL T2
  LDA WCL
  CLC
  ADC T1
  STA STENL
  LDA WCH
  ADC T2
  STA STENH
  LDA TXL                      ; the front starts 64 pixels left of the screen
  SEC
  SBC #64
  STA SWL
  LDA TXH
  SBC #0
  STA SWH
  STZ SWF
  LDA #1
  STA STORM
  LDA #W_STORM
  LDX #0
  JSR SFX_WHISTLE
  LDA #0
  JMP MESSAGE

STORM_FRAME:
  JSR STORM_WALL
  LDA STORM
  BEQ .sf_r
  LDA GSTATE
  BNE .sf_s
  LDA TXCL                     ; over?
  CMP STENL
  LDA TXCH
  SBC STENH
  BCC .sf_go
  STZ STORM
  LDA #1
  JMP MESSAGE
.sf_go:
  LDX ROUND                    ; the front moves 2.25 pixels a frame (2.4 at night)
  LDA SWF
  CLC
  ADC STV_L,X
  STA SWF
  LDA SWL
  ADC #2
  STA SWL
  BCC .sf_s
  INC SWH
.sf_s:
  SEC                          ; on the screen
  LDA SWL
  SBC TXL
  STA SSXL
  LDA SWH
  SBC TXH
  STA SSXH
  BPL .sf_on
  CMP #$FF                     ; far behind: it keeps 48 pixels off the screen
  BNE .sf_cl
  LDA SSXL
  CMP #$D0
  BCS .sf_w
.sf_cl:
  LDA TXL
  SEC
  SBC #48
  STA SWL
  LDA TXH
  SBC #0
  STA SWH
  LDA #$D0
  STA SSXL
  LDA #$FF
  STA SSXH
  BRA .sf_w
.sf_on:
  BNE .sf_w
  LDA GSTATE                   ; it swallows the rover
  BNE .sf_w
  LDA SSXL
  CLC
  ADC #10
  BCS .sf_hit
  CMP RX
  BCC .sf_w
.sf_hit:
  LDA #6
  JMP CRASH
.sf_w:
  LDA GSTATE                   ; the wind, on the left
  BNE .sf_r
  LDA EX_ID
  BNE .sf_r
  LDA #S_WIND
  LDX #0
  JMP SFX_BOOM
.sf_r:
  RTS

STV_L:
  .byte $40, $66

; the wall of dust on rows 15-18, columns 0 .. front: drawn again when the front column changes
STORM_WALL:
  LDA #0
  LDX STORM
  BEQ .sw_c
  LDX SSXH
  BMI .sw_c
  BNE .sw_all
  LDA SSXL
  CLC
  ADC #8
  BCS .sw_all
  LSR A
  LSR A
  LSR A
  BRA .sw_c
.sw_all:
  LDA #32
.sw_c:
  CMP OSTC
  BEQ .sw_r
  STA OSTC
  LDA #$E0                     ; row 15
  LDX #$39
  JSR SET_VADDR
  LDY #4
.sw_row:
  LDX #0
.sw_col:
  LDA #T_DUST
  CPX OSTC
  BCC .sw_p
  LDA #5
.sw_p:
  STA VDATA
  INX
  CPX #32
  BNE .sw_col
  DEY
  BNE .sw_row
.sw_r:
  RTS
; ===============================================================
;  ROVER, SHOTS, OBJECTS, SPRITES
; ===============================================================

; joystick: speed, jump, fire
ROVER_CTRL:
  LDX #2                       ; cruise, RIGHT faster, LEFT slower
  LDA JOYC
  AND #8
  BEQ .rc_l
  LDX #3
.rc_l:
  LDA JOYC
  AND #4
  BEQ .rc_s
  LDX #1
.rc_s:
  STZ SOFTF                    ; soft sand holds the rover back
  LDA AIR
  BNE .rc_t
  PHX
  JSR UNDER
  PLX
  CMP #4
  BNE .rc_t
  LDX #1
  INC SOFTF
.rc_t:
  STX TSPD
  LDX SPDH                     ; the rover drifts right when it goes fast
  LDA SPDL
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC RXB,X
  STA T0
  LDA FRAME_CNT
  AND #1
  BEQ .rc_j
  LDA RX
  CMP T0
  BEQ .rc_j
  BCC .rc_i
  DEC RX
  BRA .rc_j
.rc_i:
  INC RX
.rc_j:
  LDA JOYC                     ; button 1 pressed now: jump
  AND #$10
  BEQ .rc_f
  LDA JOYP
  AND #$10
  BNE .rc_f
  LDA AIR
  BNE .rc_f
  JSR JUMP
.rc_f:
  LDA JOYC                     ; button 2: fire, again every FIRE_T frames while held
  AND #$20
  BEQ .rc_nf
  LDA JOYP
  AND #$20
  BEQ .rc_sh
  DEC FIRET
  BNE .rc_r
.rc_sh:
  LDA #FIRE_T
  STA FIRET
  JMP FIRE
.rc_nf:
  STZ FIRET
.rc_r:
  RTS

RXB:
  .byte 32, 56, 80, 104

; A = type of the track column under the rover centre
UNDER:
  CLC
  LDA TXL
  ADC RX
  STA T0
  LDA TXH
  ADC #0
  STA T1
  LDA T0
  CLC
  ADC #8
  STA T0
  BCC .un_s
  INC T1
.un_s:
  LSR T1
  ROR T0
  LSR T1
  ROR T0
  LSR T1
  ROR T0
  LDX T0
  LDA TRACK,X
  RTS

JUMP:
  LDA #1
  STA AIR
  STZ OVERC
  LDA #$40                     ; -2.75 pixels a frame
  STA VYL
  LDA #$FD
  STA VYH
  LDA #W_JUMP
  LDX #0
  JMP SFX_WHISTLE

; forward shot (one at a time) and up shot (two at a time)
FIRE:
  STZ T7
  LDA FSX
  BNE .fi_u
  LDA RX
  CLC
  ADC #14
  STA FSX
  LDA RY
  CLC
  ADC #10
  STA FSY
  LDA #W_FWD
  LDX #0
  JSR SFX_WHISTLE
  INC T7
.fi_u:
  LDY #1
.fi_l:
  LDA USX,Y
  BEQ .fi_f
  DEY
  BPL .fi_l
  RTS
.fi_f:
  LDA RX                       ; from the middle of the rover
  INC A
  STA USX,Y
  LDA RY
  SEC
  SBC #4
  STA USY,Y
  LDA T7
  BNE .fi_r
  LDA #W_UP
  LDX #0
  JMP SFX_WHISTLE
.fi_r:
  RTS

; ---------------------------------------------------------------
; the rover: wheels, jump, landing, craters
; ---------------------------------------------------------------
ROVER:
  LDA WHF                      ; wheels turn with the speed
  CLC
  ADC SPDH
  STA WHF
  LDA BOUNCE
  BEQ .ro_b
  DEC BOUNCE
.ro_b:
  LDA GSTATE
  BEQ .ro_air
  CMP #1                       ; fallen into a crater: it sinks
  BNE .ro_r
  LDA DEATH
  CMP #1
  BNE .ro_r
  LDA GT
  AND #3
  BNE .ro_r
  LDA RY
  CMP #GROUND+10
  BCS .ro_r
  INC RY
.ro_r:
  RTS
.ro_air:
  LDA AIR
  BEQ .ro_gnd
  CLC                          ; gravity 0.14
  LDA VYL
  ADC #36
  STA VYL
  LDA VYH
  ADC #0
  STA VYH
  CLC
  LDA RYF
  ADC VYL
  STA RYF
  LDA RY
  ADC VYH
  STA RY
  JSR UNDER                    ; a crater under the jump
  BEQ .ro_y
  CMP #4
  BEQ .ro_y
  LDA #1
  STA OVERC
.ro_y:
  LDA RY
  CMP #GROUND
  BCC .ro_r
  LDA #GROUND                  ; landing
  STA RY
  STZ RYF
  STZ AIR
  LDA #6
  STA BOUNCE
  LDA #S_LAND
  LDX #0
  JSR SFX_BOOM
  LDA OVERC
  BEQ .ro_gnd
  STZ OVERC
  LDA #$50                     ; a crater jumped: 50
  LDY #$00
  JSR ADD_PTS
.ro_gnd:
  JSR UNDER
  BEQ .ro_r
  CMP #4
  BEQ .ro_r
  LDA #1
  ; fall into CRASH

; A = why: the rover is lost
CRASH:
  STA DEATH
  LDA #1
  STA GSTATE
  LDA #150
  STA GT
  STZ ENGON
  STZ FSX
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
  LDA #W_DIE
  LDX #2
  JMP SFX_WHISTLE

; ---------------------------------------------------------------
; shots
; ---------------------------------------------------------------
SHOTS:
  LDA FSX                      ; forward: 6 pixels a frame, 140 pixels at most
  BEQ .sh_u
  CLC
  ADC #6
  BCS .sh_fo
  STA FSX
  SEC
  SBC RX
  BCC .sh_u
  CMP #140
  BCC .sh_u
.sh_fo:
  STZ FSX
.sh_u:
  LDX #1                       ; up: 6 pixels a frame
.sh_l:
  LDA USX,X
  BEQ .sh_n
  LDA USY,X
  SEC
  SBC #6
  STA USY,X
  BCC .sh_o
  CMP #16
  BCS .sh_n
.sh_o:
  STZ USX,X
.sh_n:
  DEX
  BPL .sh_l
  RTS

; ---------------------------------------------------------------
; collisions: object box T0 (left) .. T1 (right), T2 (top) .. T3 (bottom)
; ---------------------------------------------------------------
HIT_ROVER:                     ; rover box RX+2 .. RX+13, RY+5 .. RY+15; C = 1 hit
  LDA T1
  SEC
  SBC RX
  BCC .hr_n
  CMP #2
  BCC .hr_n
  LDA RX
  CLC
  ADC #13
  CMP T0
  BCC .hr_n
  LDA T3
  SEC
  SBC RY
  BCC .hr_n
  CMP #5
  BCC .hr_n
  LDA RY
  CLC
  ADC #15
  CMP T2
  BCC .hr_n
  SEC
  RTS
.hr_n:
  CLC
  RTS

HIT_FSHOT:                     ; forward shot FSX .. FSX+5, FSY .. FSY+1; C = 1 hit (the shot is gone)
  LDA FSX
  BEQ .hf_n
  LDA T1
  CMP FSX
  BCC .hf_n
  LDA FSX
  CLC
  ADC #5
  CMP T0
  BCC .hf_n
  LDA T3
  CMP FSY
  BCC .hf_n
  LDA FSY
  INC A
  CMP T2
  BCC .hf_n
  STZ FSX
  SEC
  RTS
.hf_n:
  CLC
  RTS

HIT_USHOT:                     ; up shots USX+4 .. USX+11, USY .. USY+4; C = 1 hit (the shot is gone)
  LDY #1
.hu_l:
  LDA USX,Y                    ; the shot hits 8 pixels wide: USX+4 .. USX+11
  BEQ .hu_n
  CLC
  ADC #11
  CMP T0
  BCC .hu_n
  SEC
  SBC #7
  CMP T1
  BEQ .hu_y
  BCS .hu_n
.hu_y:
  LDA USY,Y
  CMP T3
  BEQ .hu_z
  BCS .hu_n
.hu_z:
  CLC
  ADC #4
  CMP T2
  BCC .hu_n
  LDA #0
  STA USX,Y
  SEC
  RTS
.hu_n:
  DEY
  BPL .hu_l
  CLC
  RTS

; ---------------------------------------------------------------
; objects: one routine per kind, X = slot
; ---------------------------------------------------------------
OBJECTS:
  LDX #NOB-1
.ob_l:
  LDA O_K,X
  BEQ .ob_n
  STX SLOT
  ASL A
  TAX
  JSR .ob_go
  LDX SLOT
.ob_n:
  DEX
  BPL .ob_l
  RTS
.ob_go:
  JMP (OBJ_JT,X)

; ground kinds: x on the screen; behind the screen they go away (C = 1)
GSCREEN:
  SEC
  LDA O_XL,X
  SBC TXL
  STA O_SXL,X
  LDA O_XH,X
  SBC TXH
  STA O_SXH,X
  BPL .gs_k
  CMP #$FF
  BNE .gs_rm
  LDA O_SXL,X
  CMP #$E0
  BCS .gs_k
.gs_rm:
  STZ O_K,X
  SEC
  RTS
.gs_k:
  CLC
  RTS

; box of a ground object: A = left offset, Y = width - 1 (needs O_SXH = 0)
GBOX:
  CLC
  ADC O_SXL,X
  STA T0
  TYA
  CLC
  ADC T0
  BCC .gb_s
  LDA #255
.gb_s:
  STA T1
  RTS

; the object becomes an explosion on the ground: A = sound
TO_GBOOM:
  LDY O_SXL,X
  JSR BOOM_AT
  LDX SLOT
  LDA #K_GBOOM
  STA O_K,X
  LDA #16
  STA O_T,X
  RTS

OB_ROCK:
  LDX SLOT
  JSR GSCREEN
  BCS .rk_r
  LDA O_T,X                    ; hit flash
  BEQ .rk_f
  DEC O_T,X
.rk_f:
  LDA O_SXH,X
  BNE .rk_r
  LDA O_SXL,X
  CMP #240
  BCS .rk_r
  LDA #2
  LDY #11
  JSR GBOX
  LDA #142                     ; small: 10 rows, big: 15
  LDY O_K,X
  CPY #K_BIG
  BNE .rk_t
  LDA #137
.rk_t:
  STA T2
  LDA #151
  STA T3
  JSR HIT_FSHOT
  BCC .rk_v
  DEC O_H,X
  BEQ .rk_k
  LDA #8
  STA O_T,X
  LDA #S_PUFF
  LDY O_SXL,X
  JMP BOOM_AT
.rk_k:
  LDA O_K,X
  CMP #K_BIG
  BEQ .rk_kb
  LDA #$00                     ; 100
  LDY #$01
  BRA .rk_p
.rk_kb:
  LDA #$00                     ; 200
  LDY #$02
.rk_p:
  JSR ADD_PTS
  LDA #S_CRUMBLE
  JMP TO_GBOOM
.rk_v:
  LDA GSTATE
  BNE .rk_r
  JSR HIT_ROVER
  BCC .rk_r
  LDA #2
  JMP CRASH
.rk_r:
  RTS

OB_MINE:
  LDX SLOT
  JSR GSCREEN
  BCC .mi_g
.mi_x:
  RTS
.mi_g:
  LDA O_SXH,X
  BNE .mi_x
  LDA O_S,X
  BNE .mi_hop
  LDA O_SXL,X                  ; resting: springs when the rover is near
  SEC
  SBC RX
  BCC .mi_box
  CMP #72
  BCS .mi_box
  LDA #1
  STA O_S,X
  STZ O_T,X
  LDA #W_MINE
  LDX #1
  JSR SFX_WHISTLE
  LDX SLOT
.mi_hop:
  LDA O_T,X
  INC A
  CMP #36
  BCC .mi_t
  LDA O_SXL,X                  ; down again: still in front of the rover?
  CMP RX
  BCS .mi_ag
  STZ O_S,X
.mi_ag:
  LDA #0
.mi_t:
  STA O_T,X
  TAY
  LDA HOP,Y
  STA O_H,X
.mi_box:
  LDA O_SXL,X
  CMP #240
  BCS .mi_r
  LDA #2
  LDY #10
  JSR GBOX
  LDA #146                     ; resting: rows 146-151, hopping: 144-h .. 151-h
  LDY #151
  LDX SLOT
  LDA O_S,X
  BEQ .mi_y
  LDA #144
  SEC
  SBC O_H,X
  TAY
  CLC
  ADC #7
  STA T3
  TYA
  BRA .mi_y2
.mi_y:
  LDA #151
  STA T3
  LDA #146
.mi_y2:
  STA T2
  JSR HIT_FSHOT
  BCC .mi_v
  LDA #$50                     ; 150
  LDY #$01
  JSR ADD_PTS
  LDA #S_BOOM
  JMP TO_GBOOM
.mi_v:
  LDA GSTATE
  BNE .mi_r
  JSR HIT_ROVER
  BCC .mi_r
  LDA #3
  JMP CRASH
.mi_r:
  RTS

OB_WORM:
  LDX SLOT
  JSR GSCREEN
  BCS .wo_rr
  LDA O_SXH,X
  BNE .wo_rr
  LDA O_S,X
  ASL A
  TAY
  LDA WORM_JT,Y
  STA PTR
  LDA WORM_JT+1,Y
  STA PTR+1
  JSR .wo_go
  LDX SLOT
  LDA O_H,X                    ; out of the track: it can be hit, and it hits
  CMP #3
  BCC .wo_rr
  LDA O_SXL,X
  CMP #240
  BCS .wo_rr
  LDA #3
  LDY #9
  JSR GBOX
  LDA #SURF
  SEC
  SBC O_H,X
  STA T2
  LDA #151
  STA T3
  JSR HIT_FSHOT
  BCC .wo_v
  LDA #$00                     ; 500
  LDY #$05
  JSR ADD_PTS
  LDA #S_BOOM
  JMP TO_GBOOM
.wo_v:
  LDA GSTATE
  BNE .wo_rr
  JSR HIT_ROVER
  BCC .wo_rr
  LDA #4
  JMP CRASH
.wo_rr:
  RTS
.wo_go:
  JMP (PTR)

WORM_JT:
  .word WS_HIDE, WS_RUMBLE, WS_RISE, WS_OUT, WS_SINK, WS_WAIT

; the rover in range: 16-110 pixels ahead (C = 1)
WORM_NEAR:
  LDA O_SXL,X
  SEC
  SBC RX
  BCC .wn_n
  CMP #16
  BCC .wn_n
  CMP #110
  BCS .wn_n
  SEC
  RTS
.wn_n:
  CLC
  RTS

WS_HIDE:
  JSR WORM_NEAR
  BCC WS_R
  LDA #30
WS_ALARM:                      ; A = frames of rumbling before it rises
  STA O_T,X
  LDA #1
  STA O_S,X
  LDA #S_RUMBLE
  LDY O_SXL,X
  JMP BOOM_AT
WS_RUMBLE:
  DEC O_T,X
  BNE WS_R
  LDA #2
  STA O_S,X
WS_R:
  RTS
WS_RISE:
  INC O_H,X
  LDA O_H,X
  CMP #16
  BCC WS_R
  LDA #3
  STA O_S,X
  LDA #50
  STA O_T,X
  RTS
WS_OUT:
  DEC O_T,X
  BNE WS_R
  LDA #4
  STA O_S,X
  RTS
WS_SINK:
  DEC O_H,X
  BNE WS_R
  LDA #5
  STA O_S,X
  LDA #45
  STA O_T,X
  RTS
WS_WAIT:
  DEC O_T,X
  BNE WS_R
  STZ O_S,X
  JSR WORM_NEAR
  BCC WS_R
  LDA #20
  BRA WS_ALARM

OB_GBOOM:                      ; explosions and puffs on the ground
  LDX SLOT
  JSR GSCREEN
  BCS .gb_r
  DEC O_T,X
  BNE .gb_r
  STZ O_K,X
.gb_r:
  RTS

OB_ABOOM:
  LDX SLOT
  DEC O_T,X
  BNE .ab_r
  STZ O_K,X
.ab_r:
  RTS

OB_DRONE:
  LDX SLOT
  LDA O_S,X
  BNE .dr_fly
  DEC O_T,X                    ; waiting for its turn
  BNE .dr_r
  LDA #1
  STA O_S,X
  LDA #248
  STA O_XL,X
  STZ O_XF,X
  JSR DRONE_LEFT
  LDA DTIME
  LSR A
  STA O_T,X
.dr_r:
  RTS
.dr_fly:
  CLC
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_XL,X
  ADC O_VXH,X
  STA O_XL,X
  LDA O_VXH,X
  BMI .dr_lf
  LDA O_XL,X                   ; going right
  CMP #236
  BCC .dr_wv
  LDA O_S,X
  CMP #2
  BEQ .dr_away
  LDA O_H,X                    ; two crossings, then away
  CMP #2
  BCC .dr_tl
  LDA #2
  STA O_S,X
.dr_away:
  LDA O_XL,X
  CMP #248
  BCC .dr_wv
  STZ O_K,X                    ; got away: no wave bonus
  LDA #$80
  TSB WAVEK
  RTS
.dr_tl:
  INC O_H,X
  JSR DRONE_LEFT
  BRA .dr_wv
.dr_lf:
  LDA O_XL,X
  CMP #12
  BCS .dr_wv
  INC O_H,X
  LDY ROUND                    ; turn right
  LDA DVX_L,Y
  STA O_VXL,X
  LDA #1
  STA O_VXH,X
.dr_wv:
  INC O_VYL,X                  ; up and down round the base row
  LDA O_VYL,X
  AND #63
  TAY
  LDA WAVE,Y
  CLC
  ADC O_BY,X
  STA O_Y,X
  DEC O_T,X                    ; a dart now and then, when the rover is below
  BNE .dr_hit
  JSR NEXT_RND
  AND #31
  CLC
  ADC DTIME
  STA O_T,X
  LDA O_S,X
  CMP #1
  BNE .dr_hit
  LDA O_XL,X
  SEC
  SBC RX
  CLC
  ADC #40
  CMP #120
  BCS .dr_hit
  JSR SPAWN_DART
  LDX SLOT
.dr_hit:
  LDA O_XL,X                   ; up shots
  CLC
  ADC #1
  STA T0
  ADC #13
  STA T1
  LDA O_Y,X
  CLC
  ADC #4
  STA T2
  ADC #7
  STA T3
  JSR HIT_USHOT
  BCC .dr_e
  LDA #$00                     ; 300
  LDY #$03
  JSR ADD_PTS
  LDA #K_ABOOM
  STA O_K,X
  LDA #16
  STA O_T,X
  LDA #S_BOOM
  LDY O_XL,X
  JSR BOOM_AT
  INC WAVEK                    ; the whole wave: 1000 more
  LDA WAVEK
  CMP WAVEN
  BNE .dr_e
  LDA #$00
  LDY #$10
  JSR ADD_PTS
  LDA #W_WAVE
  LDX #2
  JSR SFX_WHISTLE
  LDA #2
  JMP MESSAGE
.dr_e:
  RTS

DRONE_LEFT:                    ; flies left: -1.25 by day, -1.5 by night
  LDY ROUND
  LDA #0
  SEC
  SBC DVX_L,Y
  STA O_VXL,X
  LDA #$FE
  STA O_VXH,X
  RTS

DVX_L:
  .byte $40, $80

OB_DART:
  LDX SLOT
  CLC                          ; x: off the screen, gone
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_XL,X
  ADC O_VXH,X
  STA O_XL,X
  LDA O_VXH,X
  BMI .da_ln
  BCS .da_gone
  BRA .da_y
.da_ln:
  BCC .da_gone
.da_y:
  CLC                          ; y: 1.25 pixels a frame
  LDA O_YF,X
  ADC #$40
  STA O_YF,X
  LDA O_Y,X
  ADC #1
  STA O_Y,X
  CMP #142
  BCC .da_box
  CLC                          ; on the ground: a puff of sand where it fell
  LDA O_XL,X
  ADC TXL
  STA O_XL,X
  LDA TXH
  ADC #0
  STA O_XH,X
  LDA #K_PUFF
  STA O_K,X
  LDA #10
  STA O_T,X
  RTS
.da_gone:
  STZ O_K,X
  RTS
.da_box:
  LDA O_XL,X
  CMP #240
  BCS .da_r
  CLC
  ADC #5
  STA T0
  ADC #4
  STA T1
  LDA O_Y,X
  CLC
  ADC #5
  STA T2
  ADC #4
  STA T3
  JSR HIT_USHOT
  BCC .da_v
  LDA #$50                     ; 50
  LDY #$00
  JSR ADD_PTS
  LDA #K_ABOOM
  STA O_K,X
  LDA #12
  STA O_T,X
  RTS
.da_v:
  LDA GSTATE
  BNE .da_r
  JSR HIT_ROVER
  BCC .da_r
  LDA #5
  JMP CRASH
.da_r:
  RTS

; ---------------------------------------------------------------
; new objects
; ---------------------------------------------------------------
SPAWN_G:                       ; A = kind, at the column WC being written
  LDY #G_AIR-1
.sg_l:
  LDX O_K,Y
  BEQ .sg_f
  DEY
  BPL .sg_l
  RTS
.sg_f:
  STA O_K,Y
  TAX
  LDA KHITS,X
  STA O_H,Y
  LDA #0
  STA O_S,Y
  STA O_T,Y
  LDA WCL
  STA T1
  LDA WCH
  ASL T1
  ROL A
  ASL T1
  ROL A
  ASL T1
  ROL A
  STA O_XH,Y
  LDA T1
  STA O_XL,Y
  RTS

KHITS:
  .byte 0, 1, 2, 0, 0

SPAWN_WAVE:                    ; A = drones (2-3), not while a wave is still flying
  STA T1
  LDA O_K+G_AIR
  ORA O_K+G_AIR+1
  ORA O_K+G_AIR+2
  BNE .sw_r
  LDA T1
  STA WAVEN
  STZ WAVEK
  LDX #G_AIR
  LDY #0
.sw_l:
  LDA #K_DRONE
  STA O_K,X
  STZ O_S,X
  STZ O_H,X
  TYA                          ; they come one after the other, at different heights
  ASL A
  ASL A
  ASL A
  STA T2
  ASL A
  ADC T2
  INC A
  STA O_T,X
  LDA T2
  ASL A
  ADC #32
  STA T2
  JSR NEXT_RND
  AND #15
  CLC
  ADC T2
  STA O_BY,X
  TYA
  ASL A
  ASL A
  ASL A
  ASL A
  STA O_VYL,X
  STA O_Y,X
  INX
  INY
  CPY T1
  BNE .sw_l
  LDA #W_DRONE
  LDX #1
  JMP SFX_WHISTLE
.sw_r:
  RTS

SPAWN_DART:                    ; from the drone X, towards the rover (two darts at most)
  LDY #G_DART+1
.sd_l:
  LDA O_K,Y
  BEQ .sd_f
  DEY
  CPY #G_DART
  BCS .sd_l
  RTS
.sd_f:
  LDA #K_DART
  STA O_K,Y
  LDA O_XL,X
  STA O_XL,Y
  LDA #0
  STA O_XF,Y
  STA O_YF,Y
  LDA O_Y,X
  CLC
  ADC #4
  STA O_Y,Y
  JSR NEXT_RND                 ; vx = (rover - drone + error -16..15) x 4 / 256
  AND #31
  SEC
  SBC #16
  CLC
  ADC RX
  SEC
  SBC O_XL,X
  STA T1
  LDA #0
  BIT T1
  BPL .sd_p
  LDA #$FF
.sd_p:
  STA T2
  ASL T1
  ROL T2
  ASL T1
  ROL T2
  LDA T1
  STA O_VXL,Y
  LDA T2
  STA O_VXH,Y
  RTS

; ---------------------------------------------------------------
; sprites: marker, rover, outpost, storm, shots, objects (in turns)
; ---------------------------------------------------------------
; OX = left x (OXH = $FF: left of the screen), OY = top y, ON = pattern, OC = colour (keeps X)
SPR:
  PHX
  LDX SPRI
  CPX #124
  BCS .sp_r
  LDA OY
  DEC A
  STA SAT_BUFFER,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OXH
  BMI .sp_ec
  LDA OX
  STA SAT_BUFFER+1,X
  LDA OC
  STA SAT_BUFFER+3,X
  BRA .sp_n
.sp_ec:
  LDA OX                       ; early clock: 32 pixels to the left
  CLC
  ADC #32
  STA SAT_BUFFER+1,X
  LDA OC
  ORA #$80
  STA SAT_BUFFER+3,X
.sp_n:
  TXA
  CLC
  ADC #4
  STA SPRI
.sp_r:
  PLX
  RTS

BUILD_SAT:
  STZ SPRI
  STZ OXH
  LDA LEG                      ; progress marker: 48 + leg x 24 + MRK - 4
  ASL A
  ASL A
  ASL A
  STA T0
  ASL A
  ADC T0
  ADC #44
  ADC MRK
  STA OX
  LDA #15
  STA OY
  STA OC
  LDA #PT_MARK
  STA ON
  JSR SPR
  LDA RX                       ; the rover (or its explosion)
  STA OX
  LDA GSTATE
  CMP #1
  BNE .bs_rv
  LDA GT
  CMP #100
  BCC .bs_o
  LDA RY
  STA OY
  LDA GT
  AND #4
  CLC
  ADC #PT_BOOM
  STA ON
  LDA #11
  STA OC
  JSR SPR
  BRA .bs_o
.bs_rv:
  LDA RY
  LDX BOUNCE
  BEQ .bs_b
  INC A
.bs_b:
  STA OY
  LDA #PT_ROVER
  STA ON
  LDA #15
  STA OC
  JSR SPR
  LDA RY                       ; wheels hang lower in the air
  LDX AIR
  BEQ .bs_w
  INC A
.bs_w:
  STA OY
  LDA WHF
  AND #8
  LSR A
  CLC
  ADC #PT_WHEEL
  STA ON
  LDA #14
  STA OC
  JSR SPR
.bs_o:
  LDA OUTV                     ; the outpost
  BEQ .bs_st
  LDA OSXH
  BEQ .bs_o1
  CMP #$FF
  BNE .bs_st
  LDA OSXL
  CMP #$E0
  BCC .bs_st
.bs_o1:
  STA OXH
  LDA OSXL
  STA OX
  LDA #GROUND
  STA OY
  LDA #PT_OUTL
  STA ON
  LDA #7
  STA OC
  JSR SPR
  LDA OX
  CLC
  ADC #16
  BCS .bs_st
  STA OX
  LDA OXH                      ; past 0: on the screen again
  BEQ .bs_o2
  LDA OX
  CMP #$F0
  BCS .bs_o2
  STZ OXH
.bs_o2:
  LDA #PT_OUTR
  STA ON
  LDA #15
  STA OC
  JSR SPR
.bs_st:
  STZ OXH
  LDA STORM                    ; the sandstorm front
  BEQ .bs_sh
  LDA SSXH
  BEQ .bs_s1
  CMP #$FF
  BNE .bs_sh
  LDA SSXL
  CMP #$E0
  BCC .bs_sh
  LDA #$FF
.bs_s1:
  STA OXH
  LDA SSXL
  STA OX
  LDA FRAME_CNT
  AND #4
  CLC
  ADC #PT_DUST
  STA ON
  LDA #11
  STA OC
  LDA #GROUND-16
  STA OY
  JSR SPR
  LDA #GROUND
  STA OY
  JSR SPR
  STZ OXH
.bs_sh:
  LDA FSX                      ; shots
  BEQ .bs_u
  STA OX
  LDA FSY
  SEC
  SBC #7
  STA OY
  LDA #PT_FSHOT
  STA ON
  LDA #11
  STA OC
  JSR SPR
.bs_u:
  LDX #1
.bs_ul:
  LDA USX,X
  BEQ .bs_un
  STA OX
  LDA USY,X
  STA OY
  LDA #PT_USHOT
  STA ON
  LDA #15
  STA OC
  JSR SPR
.bs_un:
  DEX
  BPL .bs_ul
  LDA RR                       ; objects, starting from a different one every frame
  CLC
  ADC #5
  AND #NOB-1
  STA RR
  TAX
  LDY #NOB
.bs_ol:
  LDA O_K,X
  BEQ .bs_on
  PHY
  JSR DRAW_OBJ
  PLY
.bs_on:
  INX
  TXA
  AND #NOB-1
  TAX
  DEY
  BNE .bs_ol
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; X = slot, A = kind
DRAW_OBJ:
  CMP #K_DRONE
  BCC .do_gk
  JMP .do_air
.do_gk:
  TAY
  LDA O_SXH,X                  ; ground: on the screen?
  BEQ .do_g
  CMP #$FF
  BEQ .do_g
  RTS
.do_g:
  STA OXH
  LDA O_SXL,X
  STA OX
  LDA #GROUND
  STA OY
  LDA DO_PAT,Y
  STA ON
  LDA DO_COL,Y
  STA OC
  CPY #K_ROCK                  ; rocks flash when hit
  BEQ .do_rk
  CPY #K_BIG
  BNE .do_m
.do_rk:
  LDA O_T,X
  BEQ .do_put
  LDA #15
  STA OC
  BRA .do_put
.do_m:
  CPY #K_MINE
  BNE .do_w
  LDA O_S,X
  BEQ .do_put
  LDA #PT_MINEUP
  STA ON
  LDA #8
  STA OC
  LDA #GROUND
  SEC
  SBC O_H,X
  STA OY
  BRA .do_put
.do_w:
  CPY #K_WORM
  BNE .do_b
  LDA O_H,X
  BNE .do_wu
  LDA TRKC                     ; under the track: a mound of sand that shakes
  STA OC
  LDA O_S,X
  CMP #1
  BNE .do_put
  LDA FRAME_CNT
  AND #2
  LSR A
  CLC
  ADC OX
  STA OX
  BRA .do_put
.do_wu:
  DEC A
  AND #$0C
  CLC
  ADC #PT_WORM
  STA ON
  LDA O_S,X
  CMP #3
  BNE .do_put
  LDA FRAME_CNT
  AND #16
  BEQ .do_put
  LDA #PT_WORMO
  STA ON
  BRA .do_put
.do_b:
  CPY #K_GBOOM
  BNE .do_put
  LDA O_T,X
  AND #4
  CLC
  ADC #PT_BOOM
  STA ON
.do_put:
  JSR SPR
  STZ OXH
.do_r:
  RTS
.do_air:
  TAY
  LDA O_XL,X
  STA OX
  LDA O_Y,X
  STA OY
  LDA DO_PAT,Y
  STA ON
  LDA DO_COL,Y
  STA OC
  CPY #K_DRONE
  BNE .do_ab
  LDA O_S,X
  BEQ .do_r
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_DRONE
  STA ON
  BRA .do_put
.do_ab:
  CPY #K_ABOOM
  BNE .do_put
  LDA O_T,X
  AND #4
  CLC
  ADC #PT_BOOM
  STA ON
  BRA .do_put

DO_PAT:
  .byte 0, PT_ROCK, PT_BIG, PT_MINE, PT_MOUND, PT_BOOM, PT_PUFF, PT_DRONE, PT_DART, PT_BOOM
DO_COL:
  .byte 0, $0E, $0E, $0E, $0D, $0B, $0E, $03, $0B, $0B
OBJ_JT:
  .word 0, OB_ROCK, OB_ROCK, OB_MINE, OB_WORM, OB_GBOOM, OB_GBOOM, OB_DRONE, OB_DART, OB_ABOOM


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from deep space miner)
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

; blocks at PTR2: kind (0 end, 1 copy, 2 fill), address, length, source / value
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
  JSR VCOPY
  BRA LOAD_BLOCKS
.lb_f:
  LDA PTR
  JSR VFILL
  BRA LOAD_BLOCKS
.lb_e:
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
  LDA ENGON                     ; the engine: low tone C of the left chip when no explosion uses it
  BEQ .sf_er
  LDA EX_ID
  BNE .sf_er
  LDX SPDH
  LDA ENG_PL,X
  STA SH_L+4
  LDA ENG_PH,X
  STA SH_L+5
  LDA SND_PH                    ; put-put: faster with the speed
  AND ENG_M,X
  BEQ .sf_el
  LDA #4
  BRA .sf_ev
.sf_el:
  LDA #8
.sf_ev:
  STA SH_L+10
.sf_er:
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
;               the table, +9 cleared too; the sign screen also
;               uses rows -5, -3 and +10..+12)
;    REC_JOY2   $FF = both joysticks sign, 0 = the player's own
;    REC_NAME   16 bytes: name of the game, spaces at the end
;    REC_HEAD   header of the table, 0 at the end
;    REC_XLBL   label of the extra byte ("LEG "), 0 at the end
;    REC_XY     X = row, Y = column: VDP write address
;    REC_CLS    clears the screen for the sign screen
;    REC_SND    A = 0 letter changed, 1 initials confirmed
;  and has VDATA, P_JOY (2 bytes, 1 = pressed, bits UDLR B1 B2),
;  READ_JOY, VINT, VDP_INT_OFF (waits for the next frame and
;  stops the NMI) and VDP_INT_ON.
;
;  Calls:
;    REC_INIT   at RESET (VDP interrupt off): reads the table
;    REC_CHECK  after the game over: REC_SC (4 BCD bytes, low
;               first), REC_EX (extra byte), REC_PL (player 0/1);
;               C = 1 if it entered the table (signed on the spot)
;    REC_SAVE   after the checks: one write, if anything changed
;    REC_TITLE  at the title: page 0 (the game's own) for ~5 s
;    REC_TICK   every title frame: C = 1 when the page changes,
;               REC_PG = page to draw (0 game, 1 table)
;    REC_SHOW   draws the table (VDP interrupt off)
;    REC_WIPE   clears rows REC_ROW..REC_ROW+9 (interrupt off)
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

REC_AYL    = $D384             ; AY latches (left, right) and data
REC_AYR    = $D380
REC_PAGE_T = 300               ; frames of a title page (5 s)
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
  JSR REC_CLS
  LDX #REC_ROW-5
  LDY #11
  LDA #(RT_NEW-REC_TXT)
  JSR REC_PUTS
  LDX #REC_ROW-3
  LDY #12
  LDA #(RT_PLAYER-REC_TXT)
  JSR REC_PUTS
  LDA REC_PL
  CLC
  ADC #'1'
  STA VDATA
  JSR REC_SHOW
  LDX #REC_ROW+10
  LDY #7
  LDA #(RT_H1-REC_TXT)
  JSR REC_PUTS
  LDX #REC_ROW+11
  LDY #7
  LDA #(RT_H2-REC_TXT)
  JSR REC_PUTS
  LDX #REC_ROW+12
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
  CLC
  ADC #REC_ROW+1
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
  LDA #<REC_PAGE_T
  STA REC_PT
  LDA #>REC_PAGE_T
  STA REC_PT+1
  LDA REC_PG
  EOR #1
  STA REC_PG
  SEC
  RTS

; ---------------------------------------------------------------
;  REC_SHOW: header and 8 rows
;    " 1. ABC  00123450  LEG 5"  (columns 4, 7, 12, 22)
; ---------------------------------------------------------------
REC_SHOW:
  LDA REC_POS                  ; kept: the row being signed
  PHA
  JSR REC_WIPE
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
  LDX #REC_ROW
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
  CLC
  ADC #REC_ROW+1
  TAX
  LDY #4
  JSR REC_XY
  LDA REC_K                    ; place
  CLC
  ADC #'1'
  STA VDATA
  LDA #'.'
  STA VDATA
  LDA #' '
  STA VDATA
  LDX REC_POS
  LDA REC_TAB+4,X              ; initials
  STA VDATA
  LDA REC_TAB+5,X
  STA VDATA
  LDA REC_TAB+6,X
  STA VDATA
  LDA REC_TAB,X                ; an empty row: no score
  ORA REC_TAB+1,X
  ORA REC_TAB+2,X
  ORA REC_TAB+3,X
  BEQ .ln_e
  LDA #' '
  STA VDATA
  STA VDATA
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
  STA VDATA
  STA VDATA
  LDX #0
.ln_x:
  LDA REC_XLBL,X
  BEQ .ln_v
  STA VDATA
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
  STA VDATA
  RTS
.dg_0:
  LDA #0
.dg_p:
  ORA #'0'
  STA VDATA
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
  STX VDATA
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
  STX VDATA
.dc_u:
  ORA #'0'
  STA VDATA
  RTS

; rows REC_ROW..REC_ROW+9 blank
REC_WIPE:
  LDA #REC_ROW
  STA REC_K
.wp_r:
  LDX REC_K
  LDY #0
  JSR REC_XY
  LDX #32
  LDA #' '
.wp_c:
  STA VDATA
  DEX
  BNE .wp_c
  INC REC_K
  LDA REC_K
  CMP #REC_ROW+10
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
SC_COL:     .byte 4,24                         ; score of player 1 / 2: column on row 0
; engine hum per speed 0-3: period (60 to 95 Hz) and the put-put mask
ENG_PL:     .byte $6D, $12, $41, $92
ENG_PH:     .byte $05, $04, $03, $02
ENG_M:      .byte 8, 8, 4, 2

T_LIFE = 17
T_BAR  = 18
T_TICK = 19

; title: rover (body, wheels), rock, mine, worm, drone  (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 67,67,80,94,115,131
TITLE_SX:   .byte 40,40,40,40,40,40
TITLE_SN:   .byte PT_ROVER,PT_WHEEL,PT_ROCK,PT_MINE,PT_WORM+12,PT_DRONE
TITLE_SC:   .byte $0F,$0E,$0E,$0E,$0D,$03

MSG_LO:     .byte <MSG0,<MSG1,<MSG2
MSG_HI:     .byte >MSG0,>MSG1,>MSG2
HINT_LO:    .byte <TXT_H0,<TXT_H1,<TXT_H2,<TXT_H3,<TXT_H4,<TXT_H5,<TXT_H6,<TXT_H7,<TXT_H8
HINT_HI:    .byte >TXT_H0,>TXT_H1,>TXT_H2,>TXT_H3,>TXT_H4,>TXT_H5,>TXT_H6,>TXT_H7,>TXT_H8

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 1,0,"HI",0
  .byte $FF
TXT_LEGH:
  .byte "LEG ",0
TXT_TIME:
  .byte "TIME ",0
TXT_TITLE:
  .byte 9,8,"RANGER B1 JUMP B2 FIRE",0
  .byte 11,8,"ROCK         100 / 200",0
  .byte 13,8,"SPRING MINE        150",0
  .byte 15,8,"SAND WORM          500",0
  .byte 17,8,"DRONE              300",0
  .byte 19,3,"REACH THE OUTPOSTS IN TIME",0
  .byte 20,1,"RIGHT = FASTER  LEFT = SLOWER",0
  .byte 21,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_PLAYER:
  .byte 7,12,"PLAYER ",0
  .byte $FF
TXT_NIGHT:
  .byte 9,11,"NIGHT RUN",0
  .byte $FF
TXT_LEG:
  .byte 11,13,"LEG ",0
  .byte $FF
TXT_LIVES:
  .byte 13,12,"LIVES ",0
  .byte $FF
TXT_OUT:
  .byte 4,7,"OUTPOST ",0
  .byte $FF
TXT_REACHED:
  .byte 4,16,"REACHED",0
  .byte $FF
TXT_TBONUS:
  .byte 6,9,"TIME BONUS ",0
  .byte $FF
TXT_PERFECT:
  .byte 8,10,"PERFECT 5000",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0
  .byte $FF
TXT_OVERP:
  .byte 13,12,"PLAYER ",0
  .byte $FF
TXT_H0:
  .byte 16,8,"JUMP THE CRATERS",0
  .byte 18,8,"SHOOT THE ROCKS",0
  .byte $FF
TXT_H1:
  .byte 16,8,"DRONES OVERHEAD",0
  .byte 18,8,"FIRE UP AT THEM",0
  .byte $FF
TXT_H2:
  .byte 16,10,"SPRING MINES",0
  .byte 18,6,"SHOOT THEM FROM AFAR",0
  .byte $FF
TXT_H3:
  .byte 16,8,"SAND WORMS RISE",0
  .byte 18,9,"FROM THE TRACK",0
  .byte $FF
TXT_H4:
  .byte 16,5,"A SANDSTORM IS COMING",0
  .byte 18,8,"KEEP MOVING FAST",0
  .byte $FF
TXT_H5:
  .byte 16,5,"THE TRACK GETS ROUGHER",0
  .byte $FF
TXT_H6:
  .byte 16,7,"STAY SHARP RANGER",0
  .byte $FF
TXT_H7:
  .byte 16,8,"THE LAST OUTPOST",0
  .byte $FF
TXT_H8:
  .byte 16,6,"EVERYTHING IS FASTER",0
  .byte 18,5,"WATCH THE DARK CRATERS",0
  .byte $FF
MSG0:
  .byte 7,6,"SANDSTORM BEHIND YOU",0
  .byte $FF
MSG1:
  .byte 7,7,"THE STORM IS OVER",0
  .byte $FF
MSG2:
  .byte 7,8,"WAVE BONUS 1000",0
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


; three tunes composed for this game (E minor, a galloping bass)
;   C2 1 D2 3 E2 5 G2 8 C3 13 D3 15 E3 17 G3 20 A3 22 B3 24 C4 25 D4 27 E4 29 F#4 31
;   G4 32 A4 34 B4 36 C5 37 D5 39 E5 41 F#5 43 G5 44 B5 48
; 0: a new leg (2.4 seconds), 1: outpost reached (1.4 seconds), 2: title (4.1 seconds)
M0_LEAD:
  .byte 29, 6, 32, 6, 36, 6, 41, 6, 39, 12, 41, 24, 0, 6, 36, 6, 39, 6, 41, 6, 44, 12, 41, 48
  .byte $FF
M0_HARM:
  .byte 20, 24, 22, 24, 24, 48, 20, 48
  .byte $FF
M0_BASS:
  .byte 5, 4, 5, 4, 17, 8, 5, 4, 5, 4, 17, 8, 3, 4, 3, 4, 15, 8, 3, 4, 3, 4, 15, 8
  .byte 1, 4, 1, 4, 13, 8, 1, 4, 1, 4, 13, 8, 5, 4, 5, 4, 17, 8, 5, 4, 5, 4, 17, 8
  .byte 5, 4, 5, 4, 17, 8
  .byte $FF
M0_DRUM:
  .byte 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8
  .byte 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8
  .byte 4, 16
  .byte $FF
M1_LEAD:
  .byte 32, 6, 36, 6, 39, 6, 44, 18, 0, 6, 43, 6, 44, 6, 48, 30
  .byte $FF
M1_HARM:
  .byte 27, 24, 31, 24, 32, 36
  .byte $FF
M1_BASS:
  .byte 8, 24, 3, 24, 8, 36
  .byte $FF
M1_DRUM:
  .byte 2, 6, 2, 6, 2, 6, 1, 18, 3, 6, 3, 6, 1, 12, 4, 24
  .byte $FF
M2_LEAD:
  .byte 29, 8, 32, 8, 36, 16, 34, 8, 32, 8, 31, 16, 29, 8, 31, 8, 32, 8, 34, 8, 36, 24, 0, 8
  .byte 39, 8, 37, 8, 36, 8, 34, 8, 32, 16, 31, 16, 29, 56
  .byte $FF
M2_HARM:
  .byte 24, 32, 22, 32, 20, 32, 22, 32, 24, 32, 20, 32, 24, 56
  .byte $FF
M2_BASS:
  .byte 5, 4, 5, 4, 17, 8, 5, 4, 5, 4, 17, 8, 1, 4, 1, 4, 13, 8, 3, 4, 3, 4, 15, 8
  .byte 5, 4, 5, 4, 17, 8, 5, 4, 5, 4, 17, 8, 1, 4, 1, 4, 13, 8, 3, 4, 3, 4, 15, 8
  .byte 8, 4, 8, 4, 20, 8, 8, 4, 8, 4, 20, 8, 3, 4, 3, 4, 15, 8, 3, 4, 3, 4, 15, 8
  .byte 5, 4, 5, 4, 17, 8, 5, 4, 5, 4, 17, 8, 5, 4, 5, 4, 17, 8, 5, 8
  .byte $FF
M2_DRUM:
  .byte 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8
  .byte 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8
  .byte 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8
  .byte 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 3, 4, 3, 4, 1, 8, 4, 8
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
; Dune Ranger: generated by dev/gen_dune_ranger.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_ROVER = 0
PT_WHEEL = 4
PT_ROCK = 12
PT_BIG = 16
PT_MINE = 20
PT_MINEUP = 24
PT_WORM = 28
PT_WORMO = 44
PT_MOUND = 48
PT_DRONE = 52
PT_DART = 60
PT_FSHOT = 64
PT_USHOT = 68
PT_BOOM = 72
PT_PUFF = 80
PT_OUTL = 84
PT_OUTR = 88
PT_DUST = 92
PT_MARK = 100
SPR_PAGES = 4
SPRITES:
  .byte $10,$1C,$18,$10,$13,$3E,$76,$FF,$FF,$FF,$7F,$24,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$30,$38,$FC,$FE,$FF,$FE,$24,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$77,$DD,$88,$DD,$77,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3B,$EE,$C4,$EE,$3B
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$77,$AA,$DD,$AA,$77,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3B,$D5,$EE,$D5,$3B
  .byte $00,$00,$00,$00,$00,$00,$03,$07,$0F,$0F,$1F,$3F,$3F,$7F,$7F,$FF,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$F0,$F8,$F8,$FC,$FC
  .byte $01,$03,$03,$07,$06,$0F,$0F,$1F,$1D,$3F,$3F,$7D,$7F,$FF,$FF,$FF,$00,$80,$C0,$C0,$E0,$F0,$E0,$F0,$F8,$F8,$FC,$FC,$FE,$FE,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$07,$1F,$2A,$7F,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$F0,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$12,$0F,$3F,$1A,$3F,$1F,$0F,$12,$00,$00,$00,$00,$00,$00,$00,$00,$40,$80,$E0,$C0,$E0,$C0,$80,$40
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$17,$3F,$2A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$F0,$B0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$17,$3F,$2A,$1F,$0F,$1F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$F0,$B0,$E0,$C0,$E0,$E0
  .byte $00,$00,$00,$00,$0F,$17,$3F,$2A,$1F,$0F,$1F,$1F,$0F,$1F,$1F,$0F,$00,$00,$00,$00,$C0,$A0,$F0,$B0,$E0,$C0,$E0,$E0,$C0,$E0,$E0,$C0
  .byte $0F,$17,$3F,$2A,$1F,$0F,$1F,$1F,$0F,$1F,$1F,$0F,$1F,$1F,$0F,$1F,$C0,$A0,$F0,$B0,$E0,$C0,$E0,$E0,$C0,$E0,$E0,$C0,$E0,$E0,$C0,$E0
  .byte $20,$30,$3B,$3F,$1F,$0F,$1F,$1F,$0F,$1F,$1F,$0F,$1F,$1F,$0F,$1F,$10,$30,$70,$F0,$E0,$C0,$E0,$E0,$C0,$E0,$E0,$C0,$E0,$E0,$C0,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$1F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F0
  .byte $00,$00,$00,$00,$C0,$60,$37,$1F,$3F,$37,$04,$08,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$18,$B0,$E0,$F0,$B0,$80,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$0F,$3F,$7F,$DF,$8B,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$F0,$F8,$EC,$44,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$07,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FC,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$03,$09,$03,$07,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$F0,$F0,$E8,$00,$80,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$05,$00,$41,$01,$4D,$32,$24,$11,$04,$04,$00,$00,$00,$00,$00,$10,$00,$C0,$24,$C9,$EE,$23,$50,$10,$00,$00,$40
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$26,$5F,$3F,$7F,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$A0,$C0,$E0,$F0
  .byte $00,$00,$00,$03,$0F,$1F,$3F,$3F,$7F,$FF,$FF,$DB,$FF,$CC,$CC,$FF,$00,$00,$00,$C0,$F0,$F8,$FC,$FC,$FE,$FF,$FF,$DB,$FF,$33,$33,$FF
  .byte $0F,$0F,$0E,$08,$08,$1C,$14,$1C,$3E,$2A,$3E,$7F,$55,$7F,$FF,$FF,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80
  .byte $E4,$C5,$0E,$EC,$D8,$E6,$DD,$BC,$CF,$95,$AD,$DE,$F5,$FB,$D9,$7C,$B5,$AC,$C0,$B0,$40,$D4,$A0,$00,$90,$A0,$10,$20,$71,$C0,$F0,$00
  .byte $C5,$FE,$2C,$7C,$FD,$F2,$F6,$F6,$57,$EB,$F8,$F2,$67,$AB,$C5,$EE,$B0,$50,$48,$AC,$60,$00,$63,$AA,$E0,$58,$C4,$46,$80,$00,$80,$00
  .byte $20,$7C,$FF,$5A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; mesas: 8 shifts x 256 bytes (codes 96-127 of third 1)
MESA_SH:
  .byte $00,$00,$03,$03,$07,$07,$0F,$0F,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$FE,$FE,$FE,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$3F,$00,$00,$00,$00,$00,$00,$00,$E1
  .byte $00,$3C,$3C,$7E,$7E,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3F,$3F,$7F,$00,$00,$00,$00,$00,$C0,$C0,$E0
  .byte $1F,$1F,$1F,$3F,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$C0,$C0,$E0,$E0,$FF,$FF,$FF,$3F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$E1,$F1,$F3,$FB,$FB,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$83,$C3,$C7,$C7,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$F8,$F8,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$F1,$F1,$FF,$FF,$FF,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$E0,$F0,$F0,$F8,$F8,$FF,$FF,$FF
  .byte $00,$00,$07,$07,$0F,$0F,$1F,$1F,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$FC,$FC,$FC,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$FE,$FE,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$00,$00,$00,$00,$00,$01,$01,$C3
  .byte $00,$78,$78,$FC,$FC,$FE,$FE,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$7F,$FF,$00,$00,$00,$00,$00,$80,$80,$C0
  .byte $3F,$3F,$3F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$80,$80,$C1,$C1,$FF,$FF,$FF,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$C3,$E3,$E7,$F7,$F7,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$07,$87,$8F,$8F,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$F0,$F0,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$00,$01,$01,$E3,$E3,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$C0,$E0,$E0,$F0,$F0,$FF,$FF,$FF
  .byte $00,$00,$0F,$0F,$1F,$1F,$3F,$3F,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$F8,$F8,$F8,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$FC,$FC,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$01,$01,$03,$03,$87
  .byte $00,$F0,$F0,$F8,$F8,$FC,$FC,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$80
  .byte $7F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$01,$01,$83,$83,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$87,$C7,$CF,$EF,$EF,$FF,$FF,$FF
  .byte $FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$00,$0F,$0F,$1F,$1F,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$E0,$E0,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$01,$03,$03,$C7,$C7,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$C0,$C0,$E0,$E0,$FF,$FF,$FF
  .byte $00,$00,$1F,$1F,$3F,$3F,$7F,$7F,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$F0,$F0,$F0,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$F8,$F8,$FC,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$01,$01,$03,$03,$07,$07,$0F
  .byte $00,$E0,$E0,$F0,$F0,$F8,$F8,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$03,$00,$00,$00,$00,$00,$FE,$FE,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FC,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$01,$03,$03,$07,$07,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$0F,$8F,$9F,$DF,$DF,$FF,$FF,$FF
  .byte $FC,$FC,$FE,$FE,$FE,$FF,$FF,$FF,$00,$1F,$1F,$3F,$3F,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$C0,$C0,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$03,$07,$07,$8F,$8F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$80,$80,$C1,$C1,$FF,$FF,$FF
  .byte $00,$00,$3F,$3F,$7F,$7F,$FF,$FF,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$E0,$E0,$E0,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$F0,$F0,$F8,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$FE,$00,$03,$03,$07,$07,$0F,$0F,$1F
  .byte $00,$C0,$C0,$E0,$E0,$F0,$F0,$F8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$07,$00,$00,$00,$00,$00,$FC,$FC,$FE,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F8,$FC,$FC,$FE,$FE,$FF,$FF,$FF,$03,$07,$07,$0F,$0F,$FF,$FF,$FF,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$1F,$1F,$3F,$BF,$BF,$FF,$FF,$FF
  .byte $F8,$F8,$FC,$FC,$FC,$FF,$FF,$FF,$00,$3F,$3F,$7F,$7F,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$80,$80,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$07,$0F,$0F,$1F,$1F,$FF,$FF,$FF,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$01,$01,$01,$83,$83,$FF,$FF,$FF
  .byte $00,$00,$7F,$7F,$FF,$FF,$FF,$FF,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$C0,$C0,$C0,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$E0,$E0,$F0,$00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$FC,$00,$07,$07,$0F,$0F,$1F,$1F,$3F
  .byte $00,$80,$80,$C0,$C0,$E0,$E0,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$07,$0F,$00,$00,$00,$00,$00,$F8,$F8,$FC,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F0,$F8,$F8,$FC,$FC,$FF,$FF,$FF,$07,$0F,$0F,$1F,$1F,$FF,$FF,$FF,$FC,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$3F,$3F,$7F,$7F,$7F,$FF,$FF,$FF
  .byte $F0,$F0,$F8,$F8,$F8,$FF,$FF,$FF,$00,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FE,$FE,$FF,$FF,$FF,$0F,$1F,$1F,$3F,$3F,$FF,$FF,$FF,$FC,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$03,$03,$03,$07,$07,$FF,$FF,$FF
  .byte $00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$80,$80,$80,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$C0,$C0,$E0,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$00,$00,$00,$00,$00,$00,$F8,$00,$0F,$0F,$1F,$1F,$3F,$3F,$7F
  .byte $00,$00,$00,$80,$80,$C0,$C0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$0F,$1F,$00,$00,$00,$00,$00,$F0,$F0,$F8,$00,$00,$00,$00,$01,$01,$03,$03
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $E0,$F0,$F0,$F8,$F8,$FF,$FF,$FF,$0F,$1F,$1F,$3F,$3F,$FF,$FF,$FF,$F8,$FC,$FC,$FE,$FE,$FF,$FF,$FF,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $E0,$E0,$F0,$F1,$F1,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$FC,$FC,$FF,$FF,$FF,$1F,$3F,$3F,$7F,$7F,$FF,$FF,$FF,$F8,$FC,$FC,$FE,$FE,$FF,$FF,$FF,$07,$07,$07,$0F,$0F,$FF,$FF,$FF
  .byte $00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$80,$80,$C0,$00,$00,$00,$00,$00,$00,$00,$1F,$00,$00,$00,$00,$00,$00,$00,$F0,$00,$1E,$1E,$3F,$3F,$7F,$7F,$FF
  .byte $00,$00,$00,$00,$00,$80,$80,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$1F,$3F,$00,$00,$00,$00,$00,$E0,$E0,$F0,$00,$00,$01,$01,$03,$03,$07,$07
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $C0,$E0,$E0,$F0,$F0,$FF,$FF,$FF,$1F,$3F,$3F,$7F,$7F,$FF,$FF,$FF,$F0,$F8,$F9,$FD,$FD,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $C0,$C1,$E1,$E3,$E3,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$FC,$FC,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$F8,$F8,$FF,$FF,$FF,$3F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$F0,$F8,$F8,$FC,$FC,$FF,$FF,$FF,$0F,$0F,$0F,$1F,$1F,$FF,$FF,$FF
; pebbles: 8 shifts x 64 bytes (codes 8-15 of third 2)
PEB_SH:
  .byte $00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$30,$08,$00,$04,$00,$00,$80,$B0,$60,$00,$00,$20,$00,$00,$00,$00,$00,$28,$28,$00,$31,$20
  .byte $04,$00,$00,$00,$0D,$20,$A0,$00,$00,$0C,$40,$00,$98,$04,$00,$00,$00,$20,$20,$10,$00,$00,$00,$00,$00,$00,$00,$02,$32,$00,$00,$00
  .byte $00,$00,$00,$02,$00,$00,$00,$00,$01,$01,$60,$10,$00,$08,$00,$00,$00,$60,$C0,$00,$00,$40,$00,$00,$00,$00,$00,$50,$50,$00,$63,$40
  .byte $08,$00,$00,$00,$1B,$40,$40,$00,$00,$18,$80,$00,$30,$08,$00,$00,$00,$40,$40,$20,$00,$00,$00,$00,$00,$00,$00,$04,$64,$00,$00,$00
  .byte $00,$00,$00,$04,$00,$00,$00,$00,$02,$02,$C1,$20,$00,$10,$00,$00,$00,$C0,$80,$00,$00,$80,$00,$00,$00,$00,$00,$A0,$A0,$00,$C6,$80
  .byte $10,$00,$01,$00,$36,$80,$80,$00,$00,$30,$00,$00,$60,$10,$00,$00,$00,$80,$80,$40,$00,$00,$00,$00,$00,$00,$00,$08,$C8,$00,$00,$00
  .byte $00,$00,$01,$08,$00,$00,$00,$00,$04,$05,$83,$40,$00,$21,$00,$00,$00,$80,$00,$01,$01,$00,$01,$01,$00,$00,$00,$40,$40,$01,$8D,$00
  .byte $20,$00,$02,$00,$6C,$00,$00,$00,$00,$61,$01,$00,$C0,$20,$00,$00,$00,$00,$00,$80,$01,$00,$00,$00,$00,$00,$00,$10,$90,$00,$00,$00
  .byte $00,$00,$03,$10,$00,$00,$00,$00,$08,$0B,$06,$80,$00,$42,$00,$00,$00,$00,$00,$02,$02,$00,$03,$02,$00,$00,$00,$80,$80,$02,$1A,$00
  .byte $40,$00,$04,$00,$D9,$00,$00,$00,$00,$C2,$02,$01,$80,$40,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$20,$20,$00,$00,$00
  .byte $00,$00,$06,$21,$00,$00,$00,$00,$10,$16,$0C,$00,$00,$84,$00,$00,$00,$00,$00,$05,$05,$00,$06,$04,$00,$00,$00,$00,$01,$04,$34,$00
  .byte $80,$01,$08,$00,$B3,$00,$00,$00,$00,$84,$04,$02,$00,$80,$00,$00,$00,$00,$00,$00,$06,$00,$00,$00,$00,$00,$00,$40,$40,$00,$00,$00
  .byte $00,$00,$0C,$42,$00,$01,$00,$00,$20,$2C,$18,$00,$00,$08,$00,$00,$00,$00,$00,$0A,$0A,$00,$0C,$08,$01,$00,$00,$00,$03,$08,$68,$00
  .byte $00,$03,$10,$00,$66,$01,$00,$00,$00,$08,$08,$04,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00
  .byte $00,$00,$18,$84,$00,$02,$00,$00,$40,$58,$30,$00,$00,$10,$00,$00,$00,$00,$00,$14,$14,$00,$18,$10,$02,$00,$00,$00,$06,$10,$D0,$00
  .byte $00,$06,$20,$00,$CC,$02,$00,$00,$00,$10,$10,$08,$00,$00,$00,$00,$00,$00,$00,$01,$19,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
DUNE_PAT:
  .byte $00,$00,$00,$00,$0F,$3F,$FF,$FF,$00,$00,$00,$00,$FC,$FF,$FF,$FF,$00,$00,$00,$00,$00,$C0,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$80,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .byte $00,$00,$00,$00,$1F,$7F,$FF,$FF,$00,$00,$00,$00,$F8,$FF,$FF,$FF,$00,$00,$00,$00,$00,$80,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03
  .byte $00,$00,$00,$00,$3F,$FF,$FF,$FF,$00,$00,$00,$00,$F0,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$FE,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$07
  .byte $00,$00,$00,$00,$7F,$FF,$FF,$FF,$00,$00,$00,$00,$E0,$FE,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$FC,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$0F
  .byte $00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$C0,$FC,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$F8,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0F,$1F
  .byte $00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$F8,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$F0,$FE
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$1F,$3F
  .byte $00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$F0,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$E0,$FC
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0F,$3F,$7F
  .byte $00,$00,$00,$00,$FE,$FF,$FF,$FF,$00,$00,$00,$00,$00,$E0,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$C0,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$1F,$7F,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FC,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$80,$E0,$F0,$FC,$FF,$FF,$00,$00,$00,$00,$00,$03,$FF,$FF,$03,$0F,$1F,$3F,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F8,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$C0,$E0,$F8,$FF,$FF,$00,$00,$00,$00,$01,$07,$FF,$FF,$07,$1F,$3F,$7F,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F0,$FC,$FE,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$80,$C0,$F0,$FF,$FF,$00,$00,$00,$00,$03,$0F,$FF,$FF,$0F,$3F,$7F,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $E0,$F8,$FC,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$E0,$FF,$FF,$00,$00,$00,$01,$07,$1F,$FF,$FF,$1F,$7F,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $C0,$F0,$F8,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$C0,$FF,$FF,$00,$00,$01,$03,$0F,$3F,$FF,$FF,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $80,$E0,$F0,$FC,$FE,$FF,$FF,$FF,$00,$00,$00,$00,$00,$80,$FF,$FF,$00,$01,$03,$07,$1F,$7F,$FF,$FF,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$C0,$E0,$F8,$FC,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$03,$07,$0F,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$80,$C0,$F0,$F8,$FE,$FF,$FF,$00,$00,$00,$00,$00,$01,$FF,$FF,$01,$07,$0F,$1F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
TRK_PAT:
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$FE,$FF,$FF,$FF,$FF,$FC,$FC,$FC,$FC,$FE,$FE,$FF,$FF,$F8,$F8,$F8,$F8,$FC,$FC,$FE,$FE
  .byte $F0,$F0,$F0,$F0,$F8,$F8,$FC,$FC,$E0,$E0,$E0,$E0,$F0,$F0,$F8,$F8,$C0,$C0,$C0,$C0,$E0,$E0,$F0,$F0,$80,$80,$80,$80,$C0,$C0,$E0,$E0
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$F8,$FC,$FC,$FE,$FF,$FF,$FF,$FF,$F0,$F8,$F8,$FC,$FE,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$80,$80,$C0,$C0,$00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $E0,$F0,$F0,$F8,$FC,$FE,$FF,$FF,$C0,$E0,$E0,$F0,$F8,$FC,$FF,$FF,$80,$C0,$C0,$E0,$F0,$F9,$FF,$FF,$00,$80,$80,$C0,$E1,$F3,$FF,$FF
  .byte $00,$00,$00,$81,$C3,$E7,$FF,$FF,$00,$01,$01,$03,$87,$CF,$FF,$FF,$01,$03,$03,$07,$0F,$9F,$FF,$FF,$03,$07,$07,$0F,$1F,$3F,$FF,$FF
  .byte $00,$00,$00,$00,$80,$80,$C0,$C0,$00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E0,$F0,$F0,$F8,$FC,$FE,$FF,$FF,$C0,$E0,$E0,$F0,$F8,$FD,$FF,$FF,$80,$C0,$C0,$E0,$F0,$FA,$FF,$FF,$00,$80,$80,$C0,$E0,$F4,$FF,$FF
  .byte $00,$00,$00,$80,$C0,$E9,$FF,$FF,$00,$00,$00,$00,$80,$D2,$FF,$FF,$00,$00,$00,$00,$00,$A4,$FF,$FF,$00,$00,$00,$00,$00,$49,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$92,$FF,$FF,$00,$00,$00,$00,$00,$25,$FF,$FF,$00,$00,$00,$00,$00,$4A,$FF,$FF,$00,$00,$00,$00,$00,$94,$FF,$FF
  .byte $00,$00,$00,$00,$00,$29,$FF,$FF,$00,$00,$00,$00,$00,$52,$FF,$FF,$00,$00,$00,$00,$00,$A4,$FF,$FF,$00,$00,$00,$00,$00,$49,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $00,$00,$00,$00,$00,$92,$FF,$FF,$00,$00,$00,$00,$00,$24,$FF,$FF,$00,$00,$00,$00,$00,$49,$FF,$FF,$00,$00,$00,$00,$01,$93,$FF,$FF
  .byte $00,$00,$00,$01,$03,$27,$FF,$FF,$00,$01,$01,$03,$07,$4F,$FF,$FF,$01,$03,$03,$07,$0F,$9F,$FF,$FF,$03,$07,$07,$0F,$1F,$3F,$FF,$FF
  .byte $00,$00,$00,$00,$01,$01,$03,$03,$01,$01,$01,$01,$03,$03,$07,$07,$03,$03,$03,$03,$07,$07,$0F,$0F,$07,$07,$07,$07,$0F,$0F,$1F,$1F
  .byte $0F,$0F,$0F,$0F,$1F,$1F,$3F,$3F,$1F,$1F,$1F,$1F,$3F,$3F,$7F,$7F,$3F,$3F,$3F,$3F,$7F,$7F,$FF,$FF,$7F,$7F,$7F,$7F,$FF,$FF,$FF,$FF
  .byte $07,$0F,$0F,$1F,$3F,$7F,$FF,$FF,$0F,$1F,$1F,$3F,$7F,$FF,$FF,$FF,$1F,$3F,$3F,$7F,$FF,$FF,$FF,$FF,$3F,$7F,$7F,$FF,$FF,$FF,$FF,$FF
  .byte $7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FD,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FB,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F6,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$EC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$D8,$FC,$FF,$FF,$FF,$FF,$FF,$FF,$B0,$F9,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $60,$F3,$FF,$FF,$FF,$FF,$FF,$FF,$C0,$E7,$FF,$FF,$FF,$FF,$FF,$FF,$81,$CF,$FF,$FF,$FF,$FF,$FF,$FF,$03,$9F,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $06,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$0C,$7E,$FF,$FF,$FF,$FF,$FF,$FF,$18,$FC,$FF,$FF,$FF,$FF,$FF,$FF,$30,$F9,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $60,$F3,$FF,$FF,$FF,$FF,$FF,$FF,$C1,$E7,$FF,$FF,$FF,$FF,$FF,$FF,$83,$CF,$FF,$FF,$FF,$FF,$FF,$FF,$07,$9F,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $0F,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$1F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
; the sandstorm wall: tile 24 of thirds 1 and 2
T_DUST = 24
DUST_PAT:
  .byte $B5,$6E,$DB,$77,$AD,$F6,$5B,$EE
STAR_PAT:
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00
STAR_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$50,$50,$50,$50,$50,$50,$50,$50,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
PLANET:
  .byte $00,$01,$03,$0F,$1F,$1F,$3E,$7C,$00,$FF,$FF,$FF,$FF,$FE,$FE,$7E,$00,$80,$C0,$F0,$F8,$38,$3C,$3E,$78,$7C,$7E,$7F,$7F,$7F,$7F,$7F
  .byte $3F,$7F,$FF,$FF,$F8,$F8,$F8,$F8,$FE,$FE,$FE,$FE,$3E,$3E,$3E,$3E,$7F,$3F,$1F,$1F,$0F,$03,$01,$00,$18,$1F,$1F,$FF,$FF,$FF,$FF,$00
  .byte $3E,$FC,$F8,$F8,$F0,$C0,$80,$00
PLANET_COL:
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90,$90
  .byte $90,$90,$90,$90,$90,$90,$90,$90
ICON_PAT:
  .byte $00,$20,$7C,$FF,$5A,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$80,$80,$FF,$FF,$80,$80,$00,$00,$00,$00,$FF,$FF,$00,$00,$00
  .byte $00,$80,$80,$FF,$FF,$80,$80,$00
ICON_COL:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
; the scene, rows 3-23
SCENE:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$08,$09,$0A,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0C,$0D,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0E,$0F,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00
  .byte $00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07
SKYROW7:
  .byte $02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00
; first code of the pair of column types [a * 8 + b]
PAIRB:
  .byte $60,$70,$60,$60,$D0,$60,$60,$60,$60,$60,$90,$80,$60,$60,$60,$60,$60,$60,$A0,$B0,$60,$60,$60,$60,$C0,$60,$60,$60,$60,$60,$60,$60
  .byte $F0,$60,$60,$60,$E0,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60
; column types of the craters and of the soft sand (event code 1-4)
PSEQ:
  .byte $01,$03,$01,$02,$03,$01,$02,$02,$03,$04,$04,$04,$04,$04,$04
PS_START:
  .byte $00,$00,$02,$05,$09
PS_LEN:
  .byte $00,$02,$03,$04,$06
ROT8:
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$00,$01,$02,$03,$04,$05,$06,$07,$00,$01,$02,$03,$04,$05,$06,$07,$00,$01,$02,$03,$04,$05,$06,$07
  .byte $00,$01,$02,$03,$04,$05,$06,$07
ROT16:
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F

; big letters of the title from 96 (third 0)
BIG_P:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98,$19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0,$1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18,$18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00,$18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00
BIG_C:
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
BIG_LEN = 224
TXT_BIG:
  .byte 3,12,96,97,100,101,104,105,108,109,0
  .byte 4,12,98,99,102,103,106,107,110,111,0
  .byte 6,10,112,113,116,117,104,105,120,121,108,109,112,113,0
  .byte 7,10,114,115,118,119,106,107,122,123,110,111,114,115,0
  .byte $FF

; legs: day 0-7, night 8-15 (events: gap in columns, code, [argument])
LEG_LO:
  .byte <LEG0,<LEG1,<LEG2,<LEG3,<LEG4,<LEG5,<LEG6,<LEG7,<LEG8,<LEG9,<LEG10,<LEG11,<LEG12,<LEG13,<LEG14,<LEG15
LEG_HI:
  .byte >LEG0,>LEG1,>LEG2,>LEG3,>LEG4,>LEG5,>LEG6,>LEG7,>LEG8,>LEG9,>LEG10,>LEG11,>LEG12,>LEG13,>LEG14,>LEG15
LEG_LENL:
  .byte $30,$6C,$A8,$E4,$20,$5C,$98,$D4,$58,$94,$D0,$0C,$48,$84,$C0,$FC
LEG_LENH:
  .byte $02,$02,$02,$02,$03,$03,$03,$03,$02,$02,$02,$03,$03,$03,$03,$03
; par time in seconds, columns per pixel of the progress marker
LEG_PAR:
  .byte $2B,$30,$34,$39,$3D,$42,$47,$4B,$2E,$33,$37,$3C,$40,$45,$4A,$4E
LEG_STEP:
  .byte $18,$1A,$1D,$1F,$22,$24,$27,$29,$19,$1C,$1E,$21,$23,$26,$28,$2B
LEG0:
  .byte $2C,$10,$14,$10,$16,$10,$19,$02,$18,$02,$17,$02,$16,$02,$18,$10,$15,$10,$15,$10,$1A,$01,$13,$01,$18,$02,$1D,$11,$18,$02,$1D,$01
  .byte $16,$10,$14,$02,$1B,$10,$15,$10,$1A,$01,$2F,$FF
LEG1:
  .byte $2C,$03,$19,$02,$14,$10,$1A,$10,$17,$02,$18,$01,$0D,$22,$05,$10,$18,$03,$17,$01,$17,$03,$18,$10,$13,$02,$18,$10,$14,$04,$1E,$10
  .byte $03,$22,$0F,$03,$1C,$10,$11,$10,$19,$02,$19,$10,$11,$02,$1A,$02,$13,$03,$1D,$04,$31,$FF
LEG2:
  .byte $2C,$02,$15,$02,$14,$11,$13,$10,$13,$03,$0D,$22,$09,$12,$13,$12,$11,$01,$12,$10,$15,$01,$12,$10,$18,$02,$19,$12,$11,$12,$11,$12
  .byte $09,$22,$10,$02,$14,$12,$18,$02,$18,$01,$16,$11,$10,$11,$11,$03,$1B,$10,$12,$12,$10,$12,$10,$02,$14,$22,$01,$12,$12,$12,$14,$01
  .byte $16,$12,$13,$11,$22,$FF
LEG3:
  .byte $2C,$04,$1B,$12,$0F,$13,$12,$10,$14,$10,$01,$22,$11,$02,$15,$02,$11,$12,$12,$13,$18,$02,$15,$02,$15,$04,$22,$11,$15,$10,$15,$03
  .byte $1A,$13,$0F,$22,$04,$13,$11,$03,$16,$11,$10,$03,$14,$04,$1D,$13,$10,$13,$10,$12,$18,$10,$11,$03,$15,$12,$12,$02,$0D,$22,$0B,$02
  .byte $13,$01,$12,$13,$15,$04,$1C,$01,$1D,$FF
LEG4:
  .byte $2C,$03,$18,$01,$15,$02,$18,$02,$16,$10,$10,$12,$04,$30,$1C,$0A,$12,$00,$23,$16,$10,$16,$13,$16,$03,$11,$12,$0E,$10,$16,$02,$14
  .byte $10,$12,$03,$1A,$01,$16,$02,$16,$04,$1C,$13,$02,$23,$0D,$02,$17,$10,$13,$10,$10,$11,$0E,$04,$21,$02,$15,$01,$13,$13,$13,$13,$0F
  .byte $02,$10,$10,$02,$23,$12,$03,$1A,$13,$15,$02,$18,$12,$10,$03,$1A,$13,$25,$FF
LEG5:
  .byte $2C,$12,$11,$12,$12,$10,$12,$10,$13,$13,$12,$04,$12,$30,$1C,$0B,$13,$0F,$01,$02,$23,$0E,$11,$16,$10,$10,$11,$12,$04,$1D,$10,$11
  .byte $04,$1E,$10,$0F,$01,$0F,$04,$19,$10,$00,$23,$10,$12,$0D,$10,$13,$10,$0F,$13,$11,$02,$16,$02,$11,$01,$0E,$12,$16,$04,$1E,$12,$14
  .byte $10,$0E,$12,$0F,$02,$0B,$23,$05,$11,$14,$01,$15,$13,$12,$13,$12,$02,$17,$02,$17,$13,$11,$01,$15,$12,$0D,$02,$14,$12,$23,$FF
LEG6:
  .byte $2C,$10,$0D,$13,$15,$01,$0F,$12,$13,$02,$17,$01,$10,$02,$17,$04,$05,$30,$1C,$01,$23,$15,$13,$0E,$01,$14,$10,$12,$02,$11,$13,$15
  .byte $02,$17,$03,$12,$13,$15,$01,$13,$10,$09,$23,$07,$13,$15,$03,$13,$10,$10,$03,$14,$10,$0D,$10,$13,$13,$15,$10,$13,$12,$15,$02,$16
  .byte $02,$0F,$12,$05,$23,$0E,$10,$0F,$13,$10,$02,$0F,$10,$0D,$10,$15,$01,$12,$02,$15,$13,$13,$10,$10,$13,$0F,$13,$0B,$23,$03,$01,$10
  .byte $02,$16,$10,$0C,$13,$0E,$02,$15,$02,$27,$FF
LEG7:
  .byte $2C,$02,$15,$10,$10,$04,$17,$10,$13,$13,$09,$23,$09,$13,$0C,$13,$11,$02,$00,$30,$1C,$10,$02,$13,$10,$10,$01,$0D,$10,$10,$01,$11
  .byte $03,$16,$02,$12,$10,$0B,$10,$14,$12,$0B,$10,$0C,$13,$0F,$03,$04,$23,$0D,$04,$16,$02,$15,$01,$11,$10,$11,$13,$11,$04,$1D,$10,$0C
  .byte $11,$0B,$04,$18,$02,$12,$10,$0F,$04,$0A,$23,$15,$10,$0D,$13,$0F,$02,$14,$13,$14,$02,$11,$04,$1F,$02,$13,$03,$12,$03,$13,$02,$16
  .byte $02,$16,$02,$09,$23,$0A,$12,$0B,$10,$0B,$01,$0D,$04,$1D,$02,$14,$01,$22,$FF
LEG8:
  .byte $2C,$01,$1A,$02,$16,$04,$1D,$04,$0A,$23,$11,$03,$1B,$13,$15,$01,$19,$01,$14,$10,$17,$04,$08,$23,$19,$01,$16,$01,$1A,$10,$15,$02
  .byte $13,$13,$13,$01,$13,$01,$15,$01,$0F,$23,$03,$13,$13,$10,$16,$10,$18,$04,$1D,$02,$13,$03,$19,$FF
LEG9:
  .byte $2C,$12,$18,$02,$14,$01,$12,$12,$10,$13,$11,$03,$11,$23,$03,$02,$17,$12,$16,$12,$11,$03,$15,$12,$15,$13,$10,$01,$13,$03,$14,$01
  .byte $13,$01,$0C,$23,$05,$01,$14,$10,$16,$12,$16,$03,$17,$10,$15,$10,$10,$01,$13,$01,$14,$01,$11,$23,$03,$10,$0F,$03,$1B,$13,$14,$01
  .byte $16,$04,$27,$FF
LEG10:
  .byte $2C,$10,$13,$03,$14,$02,$11,$02,$15,$11,$08,$23,$0E,$01,$14,$10,$0E,$10,$12,$12,$16,$04,$1D,$01,$15,$04,$19,$02,$19,$12,$13,$23
  .byte $01,$13,$16,$03,$19,$02,$17,$10,$10,$02,$17,$12,$14,$10,$17,$10,$0E,$13,$14,$01,$0E,$23,$04,$01,$11,$12,$13,$01,$12,$12,$10,$13
  .byte $15,$10,$13,$03,$19,$10,$2C,$FF
LEG11:
  .byte $2C,$01,$10,$02,$0F,$10,$13,$02,$12,$10,$0D,$03,$18,$13,$0C,$23,$07,$11,$0F,$10,$10,$12,$12,$12,$0F,$01,$0E,$13,$16,$01,$11,$04
  .byte $1E,$03,$14,$02,$06,$23,$0B,$12,$16,$02,$16,$13,$0F,$01,$11,$13,$0E,$10,$13,$10,$0F,$01,$05,$23,$10,$12,$13,$10,$13,$03,$17,$13
  .byte $0F,$10,$0F,$13,$15,$12,$14,$02,$14,$01,$03,$23,$14,$13,$11,$01,$11,$02,$12,$01,$16,$10,$22,$FF
LEG12:
  .byte $2C,$11,$14,$01,$10,$13,$12,$13,$14,$02,$15,$10,$0E,$12,$04,$23,$0D,$13,$02,$30,$22,$0D,$10,$0D,$11,$13,$10,$12,$10,$11,$02,$15
  .byte $12,$0D,$02,$13,$10,$0E,$02,$0F,$23,$07,$01,$14,$12,$10,$10,$10,$10,$0F,$12,$14,$10,$0F,$10,$14,$01,$10,$01,$02,$23,$0B,$10,$0F
  .byte $02,$0F,$13,$10,$02,$12,$04,$1D,$10,$15,$12,$13,$13,$10,$03,$11,$10,$12,$01,$02,$23,$0E,$13,$0D,$13,$14,$02,$17,$01,$11,$04,$20
  .byte $10,$2B,$FF
LEG13:
  .byte $2C,$02,$0D,$01,$0C,$01,$13,$12,$0B,$10,$0D,$12,$13,$04,$04,$23,$19,$02,$02,$30,$22,$10,$11,$13,$10,$0E,$12,$0C,$13,$13,$04,$1B
  .byte $01,$0F,$13,$0D,$01,$0F,$13,$08,$23,$05,$03,$0F,$02,$12,$01,$13,$04,$1A,$13,$13,$04,$1F,$10,$0F,$11,$0A,$23,$07,$02,$0D,$01,$11
  .byte $03,$16,$02,$0E,$03,$0E,$02,$10,$03,$14,$12,$11,$02,$14,$02,$0E,$04,$19,$23,$05,$12,$0F,$02,$14,$01,$10,$12,$13,$01,$11,$12,$0C
  .byte $01,$15,$10,$0B,$10,$12,$11,$11,$01,$0D,$04,$27,$FF
LEG14:
  .byte $2C,$12,$0C,$02,$14,$01,$10,$13,$10,$02,$0E,$03,$15,$03,$0E,$03,$01,$23,$13,$02,$14,$13,$14,$01,$03,$30,$22,$0D,$13,$14,$04,$1E
  .byte $13,$0B,$02,$0D,$01,$02,$23,$10,$02,$0E,$10,$10,$01,$0F,$13,$0E,$01,$15,$04,$1E,$12,$12,$23,$02,$01,$0F,$12,$0C,$02,$10,$02,$13
  .byte $04,$1F,$02,$16,$04,$1E,$12,$0C,$23,$05,$02,$10,$01,$15,$02,$0E,$10,$0E,$03,$14,$11,$13,$12,$13,$13,$0C,$13,$14,$02,$04,$23,$11
  .byte $01,$13,$04,$1E,$01,$0D,$12,$0B,$13,$11,$10,$14,$10,$14,$13,$25,$FF
LEG15:
  .byte $2C,$10,$13,$03,$14,$01,$15,$11,$10,$10,$14,$10,$0B,$10,$11,$23,$01,$13,$0C,$13,$13,$11,$08,$30,$22,$03,$01,$14,$10,$0C,$13,$10
  .byte $11,$0D,$02,$11,$02,$0E,$04,$1D,$12,$0B,$23,$02,$03,$10,$12,$0B,$10,$0E,$04,$1F,$10,$0B,$01,$11,$12,$12,$13,$11,$03,$12,$12,$0D
  .byte $23,$01,$02,$11,$04,$1A,$10,$14,$03,$10,$12,$0D,$13,$13,$03,$0F,$13,$14,$01,$0E,$10,$10,$02,$0E,$04,$0E,$23,$0C,$11,$0E,$03,$10
  .byte $01,$13,$12,$13,$12,$0B,$12,$0D,$12,$12,$02,$10,$10,$0F,$23,$03,$02,$10,$13,$13,$03,$15,$04,$17,$01,$14,$01,$11,$10,$20,$FF
; palettes: mesa, dune, track, track top, specks
P_MESA:
  .byte $0D,$06,$04,$08,$0E,$0C,$05,$0D,$04,$05,$0C,$04,$0D,$05,$0C,$04
P_DUNE:
  .byte $06,$08,$08,$0A,$06,$0A,$04,$08,$01,$04,$01,$05,$04,$01,$04,$0D
P_TRK:
  .byte $0A,$09,$09,$0B,$0A,$0B,$0D,$09,$0E,$0E,$07,$0E,$07,$0E,$07,$0E
P_TOP:
  .byte $0B,$0B,$0B,$0F,$0B,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F
P_SPK:
  .byte $06,$06,$0D,$0A,$0E,$0C,$04,$08,$04,$05,$04,$01,$05,$04,$0C,$0D
; mine hop: height for frames 0-35
HOP:
  .byte $00,$02,$05,$07,$09,$0B,$0C,$0E,$10,$11,$12,$13,$14,$15,$15,$16,$16,$16,$16,$16,$16,$15,$15,$14,$13,$12,$11,$10,$0E,$0C,$0B,$09
  .byte $07,$05,$02,$00
; drones: vertical wave (signed)
WAVE:
  .byte $00,$01,$02,$03,$05,$06,$07,$08,$08,$09,$0A,$0B,$0B,$0B,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$09,$08,$08,$07,$06,$05,$03,$02,$01
  .byte $00,$FF,$FE,$FD,$FB,$FA,$F9,$F8,$F8,$F7,$F6,$F5,$F5,$F5,$F4,$F4,$F4,$F4,$F4,$F5,$F5,$F5,$F6,$F7,$F8,$F8,$F9,$FA,$FB,$FD,$FE,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$23,$2C,$3B,$59,$45,$32,$28,$21,$1C,$18,$1C,$F7,$DA,$C3,$B1,$A2,$95,$8A,$80,$78,$16,$16,$00,$00,$13,$13,$2E,$2E,$2A,$2A,$2E
  .byte $2E,$2A,$2A,$2E,$2E,$2A,$2A,$2E,$2E,$2A,$2A,$2E,$2E,$2A,$2A,$2E,$2E,$2A,$2A,$2E,$2E,$2A,$2A,$2E,$2E,$45,$49,$45,$48,$53,$57,$53
  .byte $57,$64,$69,$64,$69,$79,$7E,$78,$7E,$91,$98,$91,$97,$AE,$B7,$AE,$B6,$D2,$DC,$D1,$DB,$FC,$08,$FB,$07,$2F,$3D,$2E,$3C,$6C,$7E,$6B
  .byte $7C,$50,$50,$50,$50,$50,$00,$00,$3C,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$28,$28,$28,$28,$BD,$BD
  .byte $BD,$BD,$BD,$BD,$BD,$BD,$C9,$C9,$C9,$C9,$C9,$C9,$C9,$C9,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD
  .byte $FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$FD,$28,$28,$28,$2F,$2F,$2F,$2F,$24,$24,$24,$24,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$FD
  .byte $FD,$FD,$FD,$BD,$BD,$BD,$BD,$FD,$FD,$FD,$FD,$BD,$BD,$BD,$BD,$FD,$FD,$FD,$FD,$BD,$BD,$BD,$BD,$18,$20,$20,$6A,$6A,$6A,$6A,$47,$47
  .byte $47,$47,$54,$54,$54,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0B,$09,$07,$05,$09,$08,$07,$06,$05,$04,$0A,$09,$09,$08,$07,$07,$06,$05,$05,$04,$0C,$0C,$00,$00,$0C,$09,$08,$08,$08,$08,$08
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$0D,$0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$08,$07,$05,$04,$0C,$0B
  .byte $0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$09
  .byte $09,$09,$09,$08,$08,$08,$07,$07,$07,$07,$06,$06,$0C,$0A,$08,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$07,$06,$05,$04,$0C
  .byte $0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B
  .byte $0A,$09,$0C,$0B,$09,$0D,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$03
WH_START:
  .byte $00,$01,$05,$0B,$15,$1B,$39,$61,$7E,$AC,$AF,$BF,$D7,$DA
WH_LEN:
  .byte $00,$04,$06,$0A,$06,$1E,$28,$1D,$2E,$03,$10,$18,$03,$17
W_FWD = 1
W_UP = 2
W_JUMP = 3
W_MINE = 4
W_DRONE = 5
W_DIE = 6
W_EXTRA = 7
W_OVER = 8
W_BONUS = 9
W_WAVE = 10
W_STORM = 11
W_KEY = 12
W_SIGN = 13

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$0E,$0E,$0D
  .byte $0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05
  .byte $05,$06,$05,$04,$03,$02,$01,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09
  .byte $09,$09,$09,$09,$09,$07,$08,$08,$09,$09,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$08,$07,$07,$06,$06,$05,$05,$04,$04,$04,$04,$04,$04
  .byte $05,$05,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$08,$08,$07,$06,$06,$05,$05,$05,$04,$04,$04,$04,$04,$05
  .byte $05,$05,$06,$07,$07,$08,$07,$06,$05,$04
EX_NP:
  .byte $00,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17
  .byte $17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19,$19,$19,$19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B,$10,$10,$10
  .byte $10,$11,$11,$11,$11,$12,$12,$12,$12,$13,$13,$13,$13,$14,$14,$14,$14,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14
  .byte $15,$1C,$1C,$1C,$1C,$1C,$1C,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$0C,$0C,$0C,$0C,$0C
EX_VC:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0C,$0B
  .byte $0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$0C,$0A,$08,$06,$04,$02,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09,$09,$0A
  .byte $0A,$0A,$0A,$0B,$0B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$7D,$B6,$7D
  .byte $B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$43,$1B,$F4,$6D,$43,$1B,$F4,$6D,$43,$1B,$F4,$6D,$43,$1B,$F4,$6D,$43,$1B,$F4,$6D,$43,$1B,$F4,$6D
  .byte $43,$1B,$F4,$6D,$43,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$05,$05,$05,$05,$05,$05,$06,$06,$06,$05,$06,$06,$06,$05,$06,$06,$06,$05,$06,$06,$06,$05,$06,$06,$06,$05,$06,$06,$06,$05,$06
  .byte $06,$06,$05,$06,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$3D,$51,$61,$67,$85,$C5
EX_LEN:
  .byte $00,$3C,$14,$10,$06,$1E,$40,$05
S_BIG = 1
S_BOOM = 2
S_CRUMBLE = 3
S_LAND = 4
S_RUMBLE = 5
S_WIND = 6
S_PUFF = 7

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$40, <24,>24, <STAR_PAT,>STAR_PAT
  .byte 1, $08,$60, <24,>24, <STAR_COL,>STAR_COL
  .byte 1, $08,$48, <24,>24, <STAR_PAT,>STAR_PAT
  .byte 1, $08,$68, <24,>24, <STAR_COL,>STAR_COL
  .byte 1, $40,$40, <72,>72, <PLANET,>PLANET
  .byte 1, $40,$60, <72,>72, <PLANET_COL,>PLANET_COL
  .byte 1, $88,$40, <40,>40, <ICON_PAT,>ICON_PAT
  .byte 1, $88,$60, <40,>40, <ICON_COL,>ICON_COL
  .byte 1, $00,$43, <224,>224, <BIG_P,>BIG_P
  .byte 1, $00,$63, <224,>224, <BIG_C,>BIG_C
  .byte 1, $00,$4C, <1024,>1024, <DUNE_PAT,>DUNE_PAT
  .byte 1, $C0,$48, <8,>8, <DUST_PAT,>DUST_PAT
  .byte 1, $C0,$50, <8,>8, <DUST_PAT,>DUST_PAT
  .byte 1, $00,$53, <1280,>1280, <TRK_PAT,>TRK_PAT
  .byte 0
