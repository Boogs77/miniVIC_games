;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   TURBO HORIZON  -  an original race against the clock       ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - a pseudo-3D road seen from behind the car: curves that   ;
;     push the car out, crests that hide the road beyond,      ;
;     light and dark bands that run towards you                ;
;   - five stages in a row (meadow, desert, coast at sunset,   ;
;     snowy mountains, city at night): every checkpoint gives  ;
;     more time; then the road starts again, faster            ;
;   - slow cars to pass; touching one or driving on the grass  ;
;     costs speed; low and high gear                           ;
;   - 1 or 2 players, one whole race each, in turn             ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 55 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz): the ;
;     engine follows the speed, a looped tune, the effects     ;
;     over them                                                ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player driving (0 / 1)
LIVES       = $32      ; 2 bytes: 1 while the player still has his race to drive
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
GSTATE      = $3D      ; 0 countdown, 1 racing, 2 time up (the car stops), 3 over
GT          = $3E      ; 2 bytes: frames in the state
SPDL        = $40      ; speed 8.8 (units per frame)
SPDH        = $41
POSF        = $42      ; distance 8.8 (low byte of the units: the bands)
POSL        = $43
CV          = $44      ; curvature now (signed)
CVT         = $45      ; curvature of the segment
SEGF        = $46      ; units left in the segment (8.16)
SEGL        = $47
SEGH        = $48
PX          = $49      ; car side position (signed, pixels at the bottom row)
PXF         = $4A
MXF         = $4B      ; backdrop offset 8.8 (pixels, 128 period)
MX          = $4C
OMX         = $4D      ; backdrop drawn: offset / 2 ($FF = draw it)
GEAR        = $4E      ; 0 low, 1 high
STG         = $4F      ; stage 0-4
LAP         = $50      ; laps done
TIMEB       = $51      ; seconds left (BCD)
TFR         = $52      ; frames of the second
SEGP        = $53      ; 2 bytes: the next segment of the track
HZ          = $55      ; first road row on the screen (12-14: a crest hides the far rows)
HZT         = $56      ; crest of the segment (0-2)
HZA         = $57      ; distance since the last step of the crest (units)
OLDJ        = $58
JOYC        = $59      ; both joysticks drive the player driving
NEWJ        = $5A      ; pressed in this frame
HUDD        = $5B      ; to draw again: 1 score, 2 time, 4 speed, 8 gear, 16 stage
MSGT        = $5C      ; frames left of the message
OFFR        = $5D      ; 1 = on the grass
SHK         = $5E      ; frames of the crash
DISTA       = $5F      ; distance for the points (units)
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
COL         = $72      ; road drawing: column + 64
FILLT       = $73      ; tile of the run
EK          = $74      ; event column + 64
ET          = $75      ; event tile
NF          = $76      ; tile after the event
J           = $77      ; road row (0-11)
CL          = $78      ; centre of the row (16 bits, +512)
CH          = $79
ZKL         = $7A      ; row being drawn: left edge first cell + 64
ZTLI        = $7B      ;   its index in TLT
ZNL         = $7C      ;   its cells
ZKR         = $7D      ; right edge
ZTRI        = $7E
ZNR         = $7F
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
ZKD         = $87      ; dash cell + 64 ($FF = none)
ZTD         = $88      ; dash tile
ZG          = $89      ; ground tile
STREC       = $8A      ; 2 bytes: stages reached by every player (records)
NRIV        = $8C      ; rivals on the road (2-4)
OHZ         = $8D      ; HZ drawn
SI          = $8E      ; next free SAT byte
CRV         = $8F      ; rival hit (index)
ENGL        = $90      ; engine: period and volume, read by the NMI
ENGH        = $91
ENGV        = $92
SKT         = $93      ; frames to the next squeal
PROD        = $94      ; 2 bytes: |CV| * speed
RORD        = $96      ; 4 bytes: the rivals, nearest first
Q0          = $9A      ; temporaries
Q1          = $9B
Q2          = $9C
Q3          = $9D
STGN        = $9E      ; stages reached in this race
HUDC        = $9F      ; HUD: the next item to draw

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
SND_MODE   = $FB         ; 0 = game effects, 1 = a tune once, 2 = the music of the game and the effects
SND_BUSY   = $FC         ; 1 while a tune played once is playing
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

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
CMD_START  = 2           ; the tune SONG once
CMD_LOOP   = 3           ; the tune SONG again and again, the effects over it
SONG       = $0730       ; tune to play

; ---------------- other RAM ----------------
RCL        = $0200       ; road rows: centre (+512), low / high byte
RCH        = $0210
RB         = $0220       ; band * 96
RG         = $0230       ; ground tile
SLLT       = $0240       ; left edge slope 0-2
SLRT       = $0250       ; right edge slope 0-2
RDF        = $0300       ; rivals (4): distance 8.8, 0-220 ahead, 232-255 behind
RDI        = $0304
RSPL       = $0308       ; speed 8.8
RSPH       = $030C
RLN        = $0310       ; side position (signed, like PX)
RLT        = $0314       ; side position it moves to
RCO        = $0318       ; colour
RPS        = $031C       ; 1 = already passed
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
BTN_MASK    = %00110000
B_ACC       = %00010000  ; button 1: accelerate
B_BRK       = %00100000  ; button 2: brake
TIME0       = $60        ; seconds at the start (BCD)
OVER_T      = 180        ; frames of the GAME OVER of a player
MSG_T       = 120        ; frames of a message
GRASS_X     = 96         ; |PX| above this: on the grass
GRASS_V     = 114        ; top speed on the grass (8.8, about 80 km/h)
STEER       = 384        ; side speed of the steering (8.8 pixels per frame), at most
LANE_W      = 26         ; |PX - lane| below this: the cars touch

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 55         ; fixed zone of the game in the save area
REC_RAM     = $7D60      ; $2A0 bytes after the program
REC_ROW     = 9          ; table on rows 9-17 of the title
REC_WIPEN   = 10         ; rows 9-18 of the title give way to the table
REC_JOY2    = $FF        ; both joysticks drive the player playing
REC_SROW    = REC_ROW    ; table header on the sign screen

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
  STZ VINT
  JSR CLEAR_VRAM
  JSR LOAD_SPRITES
  STZ ENGV
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  STZ DDRA_JOY
  STZ DDRB_JOY
  STZ FRAME_CNT
  STZ LAST_FRAME
  STZ HOFF
  LDA #1
  STA NPL
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  STZ STREC,X
  DEX
  BPL .rs_p
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_HISC
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, the buttons, the points
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ ENGV
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR LOAD_TITLE
  JSR DRAW_TOP
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JSR PRINT
  LDA #<TXT_BUTTONS
  STA TP
  LDA #>TXT_BUTTONS
  STA TP+1
  JSR PRINT
  JSR TITLE_PAGE
  JSR REC_TITLE
  STZ SONG                     ; the title tune
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

; rows 9-18 of the title (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JMP PRINT

; one frame of the title: every 8 s the title page and the table of the records take turns
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR REC_TICK
  BCC .tf_e
  LDA REC_PG
  BEQ .tf_p
  JSR REC_SHOW
  BRA .tf_e
.tf_p:
  JSR TITLE_PAGE
.tf_e:
  JMP VDP_INT_ON

; the font in the three thirds, the big letters, the name table empty (VDP interrupt off)
LOAD_TITLE:
  LDA #<GFX_TITLE
  STA PTR2
  LDA #>GFX_TITLE
  STA PTR2+1
  JMP LOAD_BLOCKS


; ===============================================================
;  NEW GAME: one whole race for every player, in turn
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ STREC,X
  STZ LIVES,X
  DEX
  BPL .ng_p
  LDX NPL                      ; every player has his race to drive
.ng_l:
  DEX
  LDA #1
  STA LIVES,X
  TXA
  BNE .ng_l
  STZ CURP

PLAYER_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR RACE_SETUP
  JSR VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
WSTART:
  JSR DRAW_SKY                 ; a crest moved the horizon
  JSR DRAW_MTN
  JSR DRAW_ROAD
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY                    ; both joysticks drive the player driving
  ORA P_JOY+1
  STA JOYC
  LDA OLDJ
  EOR #$FF
  AND JOYC
  STA NEWJ
  JSR DRIVE                    ; speed, gear, steering, track, time
  JSR ROAD_CENT
  JSR RIVALS
  JSR UPDATE_HUD
WEND:
  LDA JOYC
  STA OLDJ
  JSR VDP_INT_ON
  LDA GSTATE
  CMP #3
  BNE GAME_LOOP
  ; fall into PLAYER_OVER


; ===============================================================
;  THE TIME IS UP: the next player, or the records
; ===============================================================
PLAYER_OVER:
  STZ ENGV
  LDA #CMD_GAME
  STA SND_CMD
  LDX CURP
  STZ LIVES,X
  LDA STGN
  STA STREC,X
  INC CURP
  LDA CURP
  CMP NPL
  BCS GAME_OVER
  JMP PLAYER_START

GAME_OVER:
  LDA #CMD_GAME
  STA SND_CMD
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR LOAD_TITLE               ; the font for the table of the records
  JSR VDP_INT_ON
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
  LDA STREC,X                  ; extra byte: the stages reached
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
REC_NAME:  .byte "TURBO HORIZON   "
REC_HEAD:  .byte "BEST DRIVERS",0
REC_XLBL:  .byte "STAGE ",0


; ===============================================================
;  HUD: rows 0-1
; ===============================================================
; row 0: 1UP score, HI record (title and records too)
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #0
  LDY #15
  JSR NT_XY
  LDA HISC+2
  JSR PUT_2
  LDA HISC+1
  JSR PUT_2
  LDA HISC
  JSR PUT_2
  LDX CURP
  JMP DRAW_SCORE

; X = player: "1UP" / "2UP" and his score on row 0
DRAW_SCORE:
  PHX
  LDX #0
  LDY #0
  JSR NT_XY
  PLX
  TXA
  CLC
  ADC #$31
  STA VDATA
  LDA #'U'
  NOP
  STA VDATA
  LDA #'P'
  NOP
  STA VDATA
  LDA #' '
  NOP
  STA VDATA
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

; one item of the HUD a frame, the ones marked in HUDD
UPDATE_HUD:
  LDA HUDD
  BEQ .uh_r
  LDX HUDC
.uh_f:
  INX                          ; the next item marked
  CPX #5
  BCC .uh_k
  LDX #0
.uh_k:
  LDA HUDBIT,X                 ; bits 1, 2, 4, 8, 16
  AND HUDD
  BEQ .uh_f
  STX HUDC
  EOR HUDD
  STA HUDD
  TXA
  ASL A
  TAX
  JMP (HUD_JT,X)
.uh_r:
  RTS
HUD_JT: .word HUD_SC, HUD_TIME, HUD_SPD, HUD_GEAR, HUD_STG
HUDBIT: .byte 1, 2, 4, 8, 16

HUD_SC:
  LDX CURP
  JMP DRAW_SCORE
HUD_TIME:
  LDA TIMEB
  LDX #1
  LDY #5
  JMP PUT_BCD2
HUD_SPD:
  LDX #1
  LDY #12
  JSR NT_XY
  LDA SPDH                     ; km/h from the speed
  LSR A
  LDA SPDL
  ROR A
  LSR A
  TAY
  LDA KMH_H,Y
  ORA #$30
  STA VDATA
  LDA KMH_L,Y
  JMP PUT_2
HUD_GEAR:
  LDX #1
  LDY #27
  JSR NT_XY
  LDA GEAR
  BNE .hg_h
  LDA #'L'
  STA VDATA
  LDA #'O'
  NOP
  STA VDATA
  RTS
.hg_h:
  LDA #'H'
  STA VDATA
  LDA #'I'
  NOP
  STA VDATA
  RTS
HUD_STG:
  LDA STG
  INC A
  ORA #$30
  PHA
  LDX #0
  LDY #29
  JSR NT_XY
  PLA
  STA VDATA
  RTS

; the whole HUD (VDP interrupt off)
DRAW_HUD:
  JSR DRAW_TOP
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR PRINT
  JSR HUD_TIME
  JSR HUD_SPD
  JSR HUD_GEAR
  JMP HUD_STG


; ===============================================================
;  MESSAGES: two rows of 10 letters in the sky (rows 5-6, columns 11-20)
; ===============================================================
; TP = text records; the message stays MSG_T frames
MESSAGE:
  JSR CLR_MSG
  JSR PRINT
  LDA #MSG_T
  STA MSGT
  RTS

; the sky again where the message was
CLR_MSG:
  LDX #5
  JSR .cm_r
  LDX #6
.cm_r:
  LDY #11
  JSR NT_XY
  LDX #10
  LDA #4
.cm_l:
  STA VDATA
  NOP
  DEX
  BNE .cm_l
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M / PTS_H (BCD) to the player driving; 999999 at most
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
  BCC .as_d
  LDA #$99
  STA SCL,X
  STA SCM,X
  STA SCH,X
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  RACE SETUP: the road tiles, the first stage, the car on the line
;  (VDP interrupt off)
; ===============================================================
RACE_SETUP:
  LDA #<GFX_RACE
  STA PTR2
  LDA #>GFX_RACE
  STA PTR2+1
  JSR LOAD_BLOCKS
  LDX #(DISTA-SPDL)            ; the race variables to 0 ($40-$5F)
.rs_z:
  STZ SPDL,X
  DEX
  BPL .rs_z
  STZ GEAR
  STZ STG
  STZ LAP
  STZ HUDD
  STZ HUDC
  STZ MSGT
  STZ SHK
  STZ OFFR
  STZ GSTATE
  STZ GT
  STZ GT+1
  STZ PX
  STZ PXF
  LDA #1
  STA STGN
  LDA #TIME0
  STA TIMEB
  LDA #60
  STA TFR
  LDA #12
  STA HZ
  LDA #$FF
  STA OHZ
  STA OMX
  LDA #2
  STA NRIV
  JSR STAGE_TRACK
  JSR LOAD_STAGE
  LDA #2                       ; rows 2-11: sky (the backdrop comes with the first frame)
  JSR ROW_ADDR
  LDY #10*32/16
.rs_s:
  LDX #16
  LDA #4
.rs_sk:
  STA VDATA
  NOP
  DEX
  BNE .rs_sk
  DEY
  BNE .rs_s
  JSR DRAW_HUD
  LDX #3                       ; the rivals ahead, the last two wait far away
.rs_r:
  JSR NEW_RIVAL
  LDA RIV_D0,X
  STA RDI,X
  DEX
  BPL .rs_r
  LDA #6                       ; the engine idles
  STA ENGV
  LDA #<TP_IDLE
  STA ENGL
  LDA #>TP_IDLE
  STA ENGH
  JSR ROAD_CENT
  JMP RIVALS
RIV_D0: .byte 30, 75, 200, 210

; the track of the stage STG from its first segment
STAGE_TRACK:
  LDX STG
  LDA TRK_LO,X
  STA SEGP
  LDA TRK_HI,X
  STA SEGP+1
  ; fall into NEXT_SEG

; the next segment: length * 4 units, curvature, crest (0 = end of the stage: carry set)
NEXT_SEG:
  LDA (SEGP)
  BEQ .ns_end
  STZ SEGH
  ASL A
  ROL SEGH
  ASL A
  ROL SEGH
  STA SEGL
  LDY #1
  LDA (SEGP),Y
  STA CVT
  INY
  LDA (SEGP),Y
  STA HZT
  CLC
  LDA SEGP
  ADC #3
  STA SEGP
  BCC .ns_c
  INC SEGP+1
.ns_c:
  CLC
  RTS
.ns_end:
  SEC
  RTS


; ===============================================================
;  STAGE COLOURS AND BACKDROP (VDP interrupt off; about 6 frames,
;  the sound goes on: SND_TICK is called by hand)
; ===============================================================
LOAD_STAGE:
  LDX STG
  LDA STG_SKY,X                ; sky: third 0 and third 1
  LDY #$20
  JSR FILL8_0
  LDY #($28 | VDP_WRITE_VRAM_BIT)
  STY T1
  LDY #$20
  LDA STG_SKY,X
  JSR FILL8
  LDA STG_G0,X                 ; ground light / dark, third 1 and 2
  LDY #$08
  JSR FILL8_12
  LDA STG_G1,X
  LDY #$10
  JSR FILL8_12
  LDA #<768                    ; the edges of band 0 (codes 8-103), third 1 and 2
  STA T2
  LDA #>768
  STA T3
  LDA #$40
  STA T0
  LDA #($28 | VDP_WRITE_VRAM_BIT)
  STA T1
  LDX STG
  LDA STG_G0,X
  JSR VFILL
  LDA #<768
  STA T2
  LDA #>768
  STA T3
  LDA #$40
  STA T0
  LDA #($30 | VDP_WRITE_VRAM_BIT)
  STA T1
  LDX STG
  LDA STG_G0,X
  JSR VFILL
  LDA #<768                    ; the edges of band 1 (codes 128-223), third 2
  STA T2
  LDA #>768
  STA T3
  STZ T0
  LDA #($34 | VDP_WRITE_VRAM_BIT)
  STA T1
  LDX STG
  LDA STG_G1,X
  JSR VFILL
  JSR SND_TICK
  ; ---- the backdrop: 4 sets shifted by 0, 2, 4, 6 pixels (codes 128-255 of third 1)
  LDX STG
  LDY STG_BD,X
  LDA BD_LO,Y
  STA PTR
  LDA BD_HI,Y
  STA PTR+1
  LDA #$00
  STA VREG
  LDA #($0C | VDP_WRITE_VRAM_BIT)
  STA VREG
  STZ Q0                       ; shift in pixels
.lsb_s:
  STZ Q1                       ; byte 0-255 of the backdrop: row * 128 + tile * 8 + line
.lsb_b:
  LDA Q1
  TAY
  CLC                          ; the same line of the next tile of the row
  ADC #8
  AND #$7F
  STA Q2
  TYA
  AND #$80
  ORA Q2
  TAY
  LDA (PTR),Y
  STA Q3
  LDY Q1
  LDA (PTR),Y
  LDX Q0
  BEQ .lsb_w
.lsb_sh:
  ASL Q3
  ROL A
  DEX
  BNE .lsb_sh
.lsb_w:
  STA VDATA
  INC Q1
  BNE .lsb_b
  JSR SND_TICK
  LDA Q0
  CLC
  ADC #2
  STA Q0
  CMP #8
  BCC .lsb_s
  ; ---- the colours of the backdrop: per line of the two rows
  LDA #$00
  STA VREG
  LDA #($2C | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDX STG
  LDA STG_BD,X
  ASL A
  ASL A
  ASL A
  ASL A
  STA Q0                       ; colours of the backdrop: BD_COL + bd * 16
  LDA #4
  STA Q2                       ; 4 shifts
.lsc_s:
  LDA Q0
  STA Q3                       ; upper row, then lower row
  LDX #2
.lsc_r:
  LDY #16                      ; 16 tiles
.lsc_t:
  PHY
  LDY Q3
  LDA #8
  STA Q1
.lsc_l:
  LDA BD_COL,Y
  STA VDATA
  INY
  DEC Q1
  BNE .lsc_l
  PLY
  DEY
  BNE .lsc_t
  LDA Q3
  CLC
  ADC #8
  STA Q3
  DEX
  BNE .lsc_r
  DEC Q2
  BNE .lsc_s
  JSR SND_TICK
  LDA #$FF
  STA OMX
  RTS

; A = colour byte, Y = low byte of the address in the colour table of third 0 ($20xx): 8 bytes
FILL8_0:
  PHA
  LDA #($20 | VDP_WRITE_VRAM_BIT)
  STA T1
  PLA
FILL8:                         ; A = colour, Y = low byte, T1 = high byte with the write bit
  STY VREG
  LDY T1
  STY VREG
  LDY #8
.f8_l:
  STA VDATA
  NOP
  DEY
  BNE .f8_l
  RTS
; the same 8 bytes in the colour tables of thirds 1 and 2
FILL8_12:
  PHA
  PHY
  LDY #($28 | VDP_WRITE_VRAM_BIT)
  STY T1
  PLY
  PHY
  JSR FILL8
  LDY #($30 | VDP_WRITE_VRAM_BIT)
  STY T1
  PLY
  PLA
  JMP FILL8


; ===============================================================
;  SKY: a crest moved the horizon; rows 8 to HZ-3 back to sky
; ===============================================================
DRAW_SKY:
  LDA HZ
  CMP OHZ
  BEQ .ds_e
  LDX OHZ
  STA OHZ
  LDA #$FF                     ; the backdrop on its new rows
  STA OMX
  CPX #$FF                     ; first frame: the sky is there already
  BEQ .ds_e
  STX T0                       ; the horizon went up: the road and the backdrop cover the sky
  TXA
  CMP HZ
  BCS .ds_e
  DEC A                        ; down: rows OHZ-2 .. HZ-3 become sky
  DEC A
  JSR ROW_ADDR
  LDA HZ
  SEC
  SBC T0
  TAY
.ds_r:
  LDX #32
  LDA #4
.ds_l:
  STA VDATA
  NOP
  DEX
  BNE .ds_l
  DEY
  BNE .ds_r
.ds_e:
  RTS


; ===============================================================
;  DRIVE: one frame of the race
; ===============================================================
DRIVE:
  INC GT
  BNE .dv_g
  INC GT+1
.dv_g:
  LDA MSGT                     ; the message goes away
  BEQ .dv_m
  DEC MSGT
  BNE .dv_m
  JSR CLR_MSG
.dv_m:
  LDA FRAME_CNT                ; the speed on the HUD every 4 frames
  AND #3
  BNE .dv_k
  LDA #4
  TSB HUDD
.dv_k:
  LDA GSTATE
  BNE .dv_1
  JSR COUNTDOWN
  BRA .dv_mv
.dv_1:
  CMP #1
  BNE .dv_2
  JSR CONTROLS
  JSR CLOCK
  BRA .dv_mv
.dv_2:
  JSR STOPPING
.dv_mv:
  JSR PHYSICS
  JSR MOVE
  JMP ENGINE

; ---- state 0: 3, 2, 1, GO
COUNTDOWN:
  LDA GT+1
  BNE .cd_e
  LDX #3
.cd_f:
  LDA GT
  CMP CD_T,X
  BEQ .cd_go
  DEX
  BPL .cd_f
.cd_e:
  RTS
.cd_go:
  TXA
  ASL A
  TAY
  LDA CD_TXT,Y
  STA TP
  LDA CD_TXT+1,Y
  STA TP+1
  JSR MESSAGE
  LDA NPL                      ; 2 players: whose race it is
  CMP #2
  BNE .cd_s
  CPX #3
  BEQ .cd_s
  LDX #5
  LDY #12
  JSR NT_XY
  LDX #0
.cd_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .cd_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.cd_s:
  LDA GT
  CMP CD_T+3
  BEQ .cd_start
  LDA #W_BEEP
  LDX #2
  JMP SFX_WHISTLE
.cd_start:
  LDA #W_GO                    ; GO: the race and its music
  LDX #2
  JSR SFX_WHISTLE
  LDA #1
  STA GSTATE
  STA SONG
  LDA #CMD_LOOP
  STA SND_CMD
  LDA #60
  STA MSGT
  RTS
CD_T:   .byte 30, 90, 150, 210
CD_TXT: .word TXT_C3, TXT_C2, TXT_C1, TXT_GO

; ---- state 1: gear, throttle, brake, steering
CONTROLS:
  LDA NEWJ                     ; up: low gear, down: high gear
  AND #%00000011
  BEQ .ct_t
  LDX #0
  AND #%00000010
  BEQ .ct_g
  INX
.ct_g:
  CPX GEAR
  BEQ .ct_t
  STX GEAR
  LDA #8
  TSB HUDD
  LDA #W_GEAR
  LDX #0
  JSR SFX_WHISTLE
.ct_t:
  LDA SHK                      ; after a crash the car only rolls
  BEQ .ct_a
  DEC SHK
  BRA .ct_c
.ct_a:
  LDA JOYC
  AND #B_ACC
  BEQ .ct_b
  LDA GEAR
  BNE .ct_hi
  LDA #3                       ; low gear: strong up to MAXL
  LDX #<MAXL
  LDY #>MAXL
  BRA .ct_up
.ct_hi:
  LDA SPDH                     ; high gear: weak below 140, then up to MAXH
  BNE .ct_h2
  LDA SPDL
  CMP #140
  BCS .ct_h2
  LDA #1
  BRA .ct_h3
.ct_h2:
  LDA #2
.ct_h3:
  LDX #<MAXH
  LDY #>MAXH
.ct_up:
  STX T0
  STY T1
  PHA
  LDA SPDL                     ; already at the top of the gear: no more
  CMP T0
  LDA SPDH
  SBC T1
  PLA
  BCS .ct_s
  CLC
  ADC SPDL
  STA SPDL
  BCC .ct_cap
  INC SPDH
.ct_cap:
  LDA SPDL                     ; not above the top of the gear
  CMP T0
  LDA SPDH
  SBC T1
  BCC .ct_s
  LDA T0
  STA SPDL
  LDA T1
  STA SPDH
  BRA .ct_s
.ct_b:
  LDA JOYC
  AND #B_BRK
  BEQ .ct_c
  LDA #6
  JSR SLOWER
  BRA .ct_s
.ct_c:
  LDA #1                       ; rolling
  JSR SLOWER
.ct_s:
  LDA GEAR                     ; low gear above its top: the engine brakes
  BNE .ct_st
  LDA SPDL
  CMP #<MAXL
  LDA SPDH
  SBC #>MAXL
  BCC .ct_st
  LDA #3
  JSR SLOWER
.ct_st:
  LDA SPDH                     ; steering: SPD pixels per frame, STEER at most
  CMP #>STEER
  BCC .ct_sv
  BNE .ct_sm
  LDA SPDL
  CMP #<STEER
  BCC .ct_sv
.ct_sm:
  LDA #<STEER
  STA T0
  LDA #>STEER
  STA T1
  BRA .ct_sd
.ct_sv:
  LDA SPDL
  STA T0
  LDA SPDH
  STA T1
.ct_sd:
  LDA JOYC
  AND #%00000100
  BEQ .ct_rt
  SEC                          ; left
  LDA PXF
  SBC T0
  STA PXF
  LDA PX
  SBC T1
  STA PX
  RTS
.ct_rt:
  LDA JOYC
  AND #%00001000
  BEQ .ct_e
  CLC                          ; right
  LDA PXF
  ADC T0
  STA PXF
  LDA PX
  ADC T1
  STA PX
.ct_e:
  RTS

; A = less speed (8.8 low byte), not below 0
SLOWER:
  STA T0
  SEC
  LDA SPDL
  SBC T0
  STA SPDL
  LDA SPDH
  SBC #0
  STA SPDH
  BCS .sl_e
  STZ SPDL
  STZ SPDH
.sl_e:
  RTS

; ---- state 1: the seconds
CLOCK:
  DEC TFR
  BNE .ck_e
  LDA #60
  STA TFR
  LDA #2
  TSB HUDD
  SED
  LDA TIMEB
  SEC
  SBC #1
  STA TIMEB
  CLD
  BEQ .ck_up
  CMP #$11                     ; the last 10 seconds tick
  BCS .ck_e
  LDA #W_TICK
  LDX #2
  JMP SFX_WHISTLE
.ck_e:
  RTS
.ck_up:
  LDA #2                       ; time up: the car stops
  STA GSTATE
  STZ GT
  STZ GT+1
  LDA #CMD_GAME
  STA SND_CMD
  LDA #W_OVER
  LDX #2
  JSR SFX_WHISTLE
  LDA #<TXT_TUP
  STA TP
  LDA #>TXT_TUP
  STA TP+1
  JSR MESSAGE
  STZ MSGT                     ; it stays
  RTS

; ---- state 2: the car brakes, then GAME OVER, then the next player
STOPPING:
  LDA #3
  JSR SLOWER
  LDA GT+1
  BNE .sp_t
  LDA GT
  CMP #120
  BNE .sp_t
  LDA #<TXT_OVR                ; GAME OVER (and the player)
  STA TP
  LDA #>TXT_OVR
  STA TP+1
  JSR MESSAGE
  STZ MSGT
  LDA NPL
  CMP #2
  BNE .sp_e
  LDX #6
  LDY #12
  JSR NT_XY
  LDX #0
.sp_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .sp_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.sp_e:
  RTS
.sp_t:
  LDA GT                       ; 120 + OVER_T frames: over
  CMP #<(120+OVER_T)
  LDA GT+1
  SBC #>(120+OVER_T)
  BCC .sp_x
  LDA #3
  STA GSTATE
.sp_x:
  RTS

; ---- every state: the curve pushes the car out, the grass slows it
PHYSICS:
  LDA CV                       ; PROD = |CV| * speed / 2
  BPL .ph_a
  EOR #$FF
  INC A
.ph_a:
  STA T0
  LDA SPDH
  LSR A
  LDA SPDL
  ROR A
  JSR MUL8                     ; PROD = T0 * A
  LDA PROD+1                   ; drift = PROD / 64 (8.8 pixels)
  STA T1
  LDA PROD
  LDX #6
.ph_d:
  LSR T1
  ROR A
  DEX
  BNE .ph_d
  STA T0
  BIT CV
  BMI .ph_l
  SEC                          ; right bend: out to the left
  LDA PXF
  SBC T0
  STA PXF
  LDA PX
  SBC T1
  STA PX
  BRA .ph_c
.ph_l:
  CLC
  LDA PXF
  ADC T0
  STA PXF
  LDA PX
  ADC T1
  STA PX
.ph_c:
  LDA PX                       ; not beyond the grass
  BMI .ph_n
  CMP #121
  BCC .ph_g
  LDA #120
  STA PX
  BRA .ph_g
.ph_n:
  CMP #-120
  BCS .ph_g
  LDA #-120
  STA PX
.ph_g:
  STZ OFFR
  LDA PX
  BPL .ph_p
  EOR #$FF
  INC A
.ph_p:
  CMP #GRASS_X+1
  BCC .ph_e
  INC OFFR
  LDA SPDH                     ; on the grass: down to GRASS_V
  BNE .ph_s
  LDA SPDL
  CMP #GRASS_V
  BCC .ph_e
.ph_s:
  LDA #5
  JMP SLOWER
.ph_e:
  RTS

; PROD = T0 * A (unsigned 8 x 8)
MUL8:
  STA T2
  STZ PROD
  STZ PROD+1
  LDX #8
.mu_l:
  ASL PROD
  ROL PROD+1
  ASL T2
  BCC .mu_n
  CLC
  LDA PROD
  ADC T0
  STA PROD
  BCC .mu_n
  INC PROD+1
.mu_n:
  DEX
  BNE .mu_l
  RTS

; ---- every state: distance, track, curve, crest, backdrop, points
MOVE:
  LDA POSL
  STA T3
  CLC
  LDA POSF
  ADC SPDL
  STA POSF
  LDA POSL
  ADC SPDH
  STA POSL
  EOR T3                       ; every 4 units: 10 points
  AND #$FC
  BEQ .mv_s
  LDA GSTATE
  CMP #1
  BNE .mv_s
  STZ PTS_H
  STZ PTS_M
  LDA #$10
  STA PTS_L
  JSR ADD_SCORE
.mv_s:
  SEC                          ; the segment
  LDA SEGF
  SBC SPDL
  STA SEGF
  LDA SEGL
  SBC SPDH
  STA SEGL
  LDA SEGH
  SBC #0
  STA SEGH
  BPL .mv_c
  JSR NEXT_SEG
  BCC .mv_c
  JSR CHECKPOINT
.mv_c:
  LDA CV                       ; the curve comes in slowly
  CMP CVT
  BEQ .mv_h
  BMI .mv_up
  DEC CV
  BRA .mv_h
.mv_up:
  INC CV
.mv_h:
  LDA FRAME_CNT                ; the crest: one row every 8 frames while moving
  AND #7
  BNE .mv_b
  LDA SPDH
  ORA SPDL
  CMP #48
  BCC .mv_b
  LDA HZT
  CLC
  ADC #12
  CMP HZ
  BEQ .mv_b
  BCC .mv_hd
  INC HZ
  BRA .mv_b
.mv_hd:
  DEC HZ
.mv_b:
  LDA PROD+1                   ; backdrop: PROD / 128 pixels, with the bend
  STA T1
  LDA PROD
  ASL A
  ROL T1
  LDA T1                       ; T1 = PROD / 128 (8.8: high byte / fraction)
  STA T0
  STZ T1
  BIT CV
  BMI .mv_bl
  CLC
  LDA MXF
  ADC T0
  STA MXF
  LDA MX
  ADC T1
  STA MX
  RTS
.mv_bl:
  SEC
  LDA MXF
  SBC T0
  STA MXF
  LDA MX
  SBC T1
  STA MX
  RTS

; ---- the end of a stage: more time, the next stage
CHECKPOINT:
  INC STGN
  LDA #$50                     ; 5000 points
  STA PTS_M
  STZ PTS_L
  STZ PTS_H
  JSR ADD_SCORE
  LDX #<TXT_CHK
  LDY #>TXT_CHK
  INC STG
  LDA STG
  CMP #NSTG
  BCC .cp_n
  STZ STG                      ; a new lap: 20000 points more
  INC LAP
  LDA #$02
  STA PTS_H
  STZ PTS_M
  JSR ADD_SCORE
  LDX #<TXT_LAP
  LDY #>TXT_LAP
.cp_n:
  STX TP
  STY TP+1
  JSR MESSAGE
  LDA #$45                     ; time: +45 s, +40 from the second lap
  LDX LAP
  BEQ .cp_t
  LDA #$40
.cp_t:
  STA T4
  LDX #6
  LDY #17
  JSR NT_XY
  LDA T4
  JSR PUT_2
  SED
  CLC
  LDA TIMEB
  ADC T4
  STA TIMEB
  CLD
  BCC .cp_tm
  LDA #$99
  STA TIMEB
.cp_tm:
  LDA #2+16
  TSB HUDD
  LDA #W_CHECK
  LDX #2
  JSR SFX_WHISTLE
  LDA STG                      ; more rivals: 2 + stage / 2 + lap, 4 at most
  LSR A
  CLC
  ADC #2
  ADC LAP
  CMP #4
  BCC .cp_r
  LDA #4
.cp_r:
  STA NRIV
  JSR STAGE_TRACK
  JMP LOAD_STAGE

; ---- the engine: its pitch from the speed and the gear
ENGINE:
  LDA SPDH
  LSR A
  LDA SPDL
  ROR A
  LSR A
  TAY
  LDA GEAR
  BNE .en_h
  LDA ENGL_LO,Y
  STA ENGL
  LDA ENGL_HI,Y
  STA ENGH
  BRA .en_v
.en_h:
  LDA ENGH_LO,Y
  STA ENGL
  LDA ENGH_HI,Y
  STA ENGH
.en_v:
  LDA #6                       ; volume: 6 idle or stopping, 7 rolling, 9 throttle
  LDX GSTATE
  CPX #2
  BCS .en_s
  LDA JOYC
  AND #B_ACC
  BEQ .en_s0
  LDA #9
  BRA .en_s
.en_s0:
  LDA #7
.en_s:
  STA ENGV
  LDA FRAME_CNT                ; squeal in a hard bend, rumble on the grass
  AND #15
  BNE .en_e
  LDA OFFR
  BEQ .en_q
  LDA SPDH
  ORA SPDL
  CMP #40
  BCC .en_e
  LDA #S_GRASS
  LDX #2
  JMP SFX_BOOM
.en_q:
  LDA SPDH
  BEQ .en_e
  LDA CV
  BPL .en_qa
  EOR #$FF
  INC A
.en_qa:
  CMP #60
  BCC .en_e
  LDA #W_SKID
  LDX #0
  JMP SFX_WHISTLE
.en_e:
  RTS


; ===============================================================
;  RIVALS: move, pass, crash, place on the road, write the SAT
; ===============================================================
; X = rival: a new car far ahead (keeps X)
NEW_RIVAL:
  LDA #190
  STA RDI,X
  STZ RDF,X
  STZ RPS,X
  JSR NEXT_RND
  AND #3
  TAY
  LDA LANES,Y
  STA RLN,X
  STA RLT,X
  JSR NEXT_RND                 ; speed: 140-203 + 24 a lap + 6 a stage (8.8)
  AND #$3F
  CLC
  ADC #140
  STA T0
  LDA #0
  STA RSPH,X
  LDA LAP
  ASL A
  ASL A
  ASL A
  STA T1
  ASL A
  ADC T1                       ; lap * 24
  CLC
  ADC T0
  BCC .nr_1
  INC RSPH,X
.nr_1:
  STA T0
  LDA STG
  ASL A
  ADC STG
  ASL A                        ; stage * 6
  CLC
  ADC T0
  STA RSPL,X
  BCC .nr_2
  INC RSPH,X
.nr_2:
  JSR NEXT_RND
  AND #7
  TAY
  LDA RIV_COL,Y
  STA RCO,X
  RTS
LANES:   .byte -56, 0, 56, 0
RIV_COL: .byte $0B, $07, $0F, $0D, $0A, $05, $0B, $0F

RIVALS:
  LDX #12                      ; the player's car: dark parts above the body
.pc_l:
  LDA PCAR,X
  STA SAT_BUFFER,X
  LDA PCAR+1,X
  STA SAT_BUFFER+1,X
  LDA PCAR+2,X
  STA SAT_BUFFER+2,X
  LDA PCAR+3,X
  STA SAT_BUFFER+3,X
  DEX
  DEX
  DEX
  DEX
  BPL .pc_l
  LDA OFFR                     ; on the grass the car shakes
  BEQ .pc_c
  LDA FRAME_CNT
  AND #2
  LSR A
  CLC
  ADC #167
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
.pc_c:
  LDA SHK                      ; after a crash it blinks white
  AND #4
  BEQ .pc_d
  LDA #$0F
  STA SAT_BUFFER+11
  STA SAT_BUFFER+15
.pc_d:
  LDA #16
  STA SI
  LDX #3                       ; move the rivals
.rv_m:
  CPX NRIV
  BCS .rv_mn
  JSR RIVAL_MOVE
.rv_mn:
  DEX
  BPL .rv_m
  JSR RIVAL_SORT
  LDY #0                       ; draw them, the nearest first
.rv_d:
  STY Q3
  LDX RORD,Y
  CPX NRIV
  BCS .rv_dn
  STX T3
  JSR RIVAL_SPR
.rv_dn:
  LDY Q3
  INY
  CPY #4
  BNE .rv_d
  LDX SI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

PCAR:
  .byte 167, 112, 8, $01
  .byte 167, 128, 12, $01
  .byte 167, 112, 0, $08
  .byte 167, 128, 4, $08

; X = rival: distance, lane, pass, crash (keeps X)
RIVAL_MOVE:
  SEC                          ; distance -= car speed - rival speed
  LDA RDF,X
  SBC SPDL
  STA RDF,X
  LDA RDI,X
  SBC SPDH
  STA RDI,X
  CLC
  LDA RDF,X
  ADC RSPL,X
  STA RDF,X
  LDA RDI,X
  ADC RSPH,X
  STA RDI,X
  CMP #221                     ; it ran away: it waits beyond the horizon
  BCC .rm_v
  CMP #232
  BCS .rm_b
  LDA #220
  STA RDI,X
  STZ RDF,X
  BRA .rm_l
.rm_b:
  CMP #240                     ; far behind: a new car ahead
  BCS .rm_p
  JMP NEW_RIVAL
.rm_p:
  CMP #248                     ; just passed: points
  BCC .rm_l
  LDA RPS,X
  BNE .rm_l
  INC RPS,X
  LDA GSTATE
  CMP #1
  BNE .rm_l
  STZ PTS_L
  STZ PTS_H
  LDA #$01                     ; 100 points
  STA PTS_M
  JSR ADD_SCORE
  LDA #W_PASS
  PHX
  LDX #1
  JSR SFX_WHISTLE
  PLX
  BRA .rm_l
.rm_v:
  CMP #2                       ; touching the car? (0 <= d < 2)
  BCS .rm_l
  LDA SHK
  BNE .rm_l
  LDA PX
  SEC
  SBC RLN,X
  BVC .rm_o
  EOR #$80
.rm_o:
  BPL .rm_ab
  EOR #$FF
  INC A
.rm_ab:
  CMP #LANE_W
  BCS .rm_l
  JSR CRASH
.rm_l:
  LDA RLN,X                    ; the lane: one pixel every other frame
  CMP RLT,X
  BEQ .rm_lc
  LDA FRAME_CNT
  AND #1
  BNE .rm_e
  LDA RLN,X
  SEC
  SBC RLT,X
  BVC .rm_lo
  EOR #$80
.rm_lo:
  BMI .rm_li
  DEC RLN,X
  RTS
.rm_li:
  INC RLN,X
  RTS
.rm_lc:
  LDA STG                      ; from stage 2 they change lane now and then
  BEQ .rm_e
  JSR NEXT_RND
  AND #$7F
  BNE .rm_e
  JSR NEXT_RND
  AND #3
  TAY
  LDA LANES,Y
  STA RLT,X
.rm_e:
  RTS

; X = rival hit: the car slows to its speed, the rival goes ahead (keeps X)
CRASH:
  LDA #40
  STA SHK
  LDA RDI,X                    ; pushed 3 units ahead
  CLC
  ADC #3
  STA RDI,X
  SEC                          ; the car: the rival's speed - 64, if slower
  LDA RSPL,X
  SBC #64
  STA T0
  LDA RSPH,X
  SBC #0
  BCS .cr_s
  LDA #0
  STA T0
.cr_s:
  STA T1
  LDA T0
  CMP SPDL
  LDA T1
  SBC SPDH
  BCS .cr_p
  LDA T0
  STA SPDL
  LDA T1
  STA SPDH
.cr_p:
  LDA PX                       ; and bounces to the side
  SEC
  SBC RLN,X
  BMI .cr_l
  LDA PX
  CLC
  ADC #12
  BVS .cr_x
  STA PX
  BRA .cr_x
.cr_l:
  LDA PX
  SEC
  SBC #12
  BVS .cr_x
  STA PX
.cr_x:
  LDA #S_CRASH
  PHX
  LDX #2
  JSR SFX_BOOM
  PLX
  RTS

; RORD = the 4 rivals by distance, nearest first (behind = last)
RIVAL_SORT:
  LDX #3                       ; keys: the distance, 255 behind
.so_i:
  TXA
  STA RORD,X
  LDA RDI,X
  CMP #232
  BCC .so_k
  LDA #255
.so_k:
  STA Q0,X
  DEX
  BPL .so_i
  LDA Q0+1                    ; (0,1)
  CMP Q0+0
  BCS .so_01
  LDX Q0+0
  STA Q0+0
  STX Q0+1
  LDA RORD+0
  LDX RORD+1
  STA RORD+1
  STX RORD+0
.so_01:
  LDA Q0+3                    ; (2,3)
  CMP Q0+2
  BCS .so_23
  LDX Q0+2
  STA Q0+2
  STX Q0+3
  LDA RORD+2
  LDX RORD+3
  STA RORD+3
  STX RORD+2
.so_23:
  LDA Q0+2                    ; (0,2)
  CMP Q0+0
  BCS .so_02
  LDX Q0+0
  STA Q0+0
  STX Q0+2
  LDA RORD+0
  LDX RORD+2
  STA RORD+2
  STX RORD+0
.so_02:
  LDA Q0+3                    ; (1,3)
  CMP Q0+1
  BCS .so_13
  LDX Q0+1
  STA Q0+1
  STX Q0+3
  LDA RORD+1
  LDX RORD+3
  STA RORD+3
  STX RORD+1
.so_13:
  LDA Q0+2                    ; (1,2)
  CMP Q0+1
  BCS .so_12
  LDX Q0+1
  STA Q0+1
  STX Q0+2
  LDA RORD+1
  LDX RORD+2
  STA RORD+2
  STX RORD+1
.so_12:
  RTS

; rival T3: on the screen if ahead, in sight and not behind a crest
RIVAL_SPR:
  LDX T3
  LDA RDI,X
  CMP #184
  BCS .rs_e
  CMP #64
  BCS .rs_b
  ASL A                        ; near: quarter units
  ASL A
  STA T0
  LDA RDF,X
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T0
  TAY
  LDA DYA,Y
  STA T1
  LDA SZA,Y
  STA T2
  BRA .rs_p
.rs_b:
  TAY
  LDA DYB,Y
  STA T1
  LDA SZB,Y
  STA T2
  CMP #$FF
  BEQ .rs_e
.rs_p:
  LDA T1                       ; road row of its bottom line
  LSR A
  LSR A
  LSR A
  CMP #12
  BCC .rs_j
  LDA #11
.rs_j:
  STA J
  CLC                          ; behind the crest?
  ADC #12
  CMP HZ
  BCC .rs_e
  LDA J
  CLC                          ; side offset at that row
  ADC #>OFFP
  STA PTR+1
  STZ PTR
  LDY RLN,X
  LDA (PTR),Y
  EOR #$80                     ; the table is + 128
  PHA
  LDY J
  LDA RCL,Y
  STA CL
  LDA RCH,Y
  STA CH
  PLA
  JSR ADDS
  JMP SPR_X
.rs_e:
  RTS

ADDS:                          ; CH:CL += A (signed)
  PHA
  CLC
  ADC CL
  STA CL
  PLA
  BMI .as_n
  LDA CH
  ADC #0
  STA CH
  RTS
.as_n:
  LDA CH
  ADC #$FF
  STA CH
  RTS

; rival T3: CH:CL = centre + 512, T1 = line below the horizon, T2 = size 0-7
SPR_X:
  LDA T2
  CMP #6
  BCS .sx_2
  ASL A                        ; one sprite: pattern 16 + size * 4
  ASL A
  ADC #16
  STA T0
  LDA #8
  JMP ONE_SPR
.sx_2:
  SEC                          ; two halves: 40/44 or 48/52
  SBC #6
  ASL A
  ASL A
  ASL A
  ADC #40
  STA T0
  LDA #16
  JSR ONE_SPR
  LDA T0
  CLC
  ADC #4
  STA T0
  LDA #0
  ; fall into ONE_SPR

; one sprite T0 with its left edge at centre - A
ONE_SPR:
  STA T2
  SEC
  LDA CL
  SBC T2
  STA PTR2
  LDA CH
  SBC #0
  CMP #2                       ; x 0-255 only (+512)
  BNE .on_x
  LDX SI
  CPX #48
  BCS .on_x
  LDA T1
  CLC
  ADC #80
  STA SAT_BUFFER,X
  LDA PTR2
  STA SAT_BUFFER+1,X
  LDA T0
  STA SAT_BUFFER+2,X
  LDY T3
  LDA RCO,Y
  STA SAT_BUFFER+3,X
  TXA
  CLC
  ADC #4
  STA SI
.on_x:
  RTS


; ===============================================================
;  ROAD: backdrop, road rows, their centres (from the prototype)
; ===============================================================
; ---------------------------------------------------------------
; backdrop: rows HZ-2 and HZ-1, tile = 128 + shift*32 + row*16 + cell
; (drawn only when its offset moved, or OMX = $FF)
; ---------------------------------------------------------------
; A = row: the VDP points to its first cell in the name table
ROW_ADDR:
  PHA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA VREG
  PLA
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | $38)
  STA VREG
  RTS

DRAW_MTN:
  LDA MX                       ; only when the offset moved
  LSR A
  CMP OMX
  BNE .dm_go
  RTS
.dm_go:
  STA OMX
  LDA HZ                       ; name table row HZ - 2
  DEC A
  DEC A
  JSR ROW_ADDR
  LDA MX                       ; Y = shift * 48 + first cell
  AND #$06
  TAX
  LDA MX
  LSR A
  LSR A
  LSR A
  AND #$0F
  CLC
  ADC M48X,X
  PHA
  TAY
  JSR MTN_U                    ; upper row
  PLY
  JMP MTN_L                    ; lower row (the VDP address runs on)

; ---------------------------------------------------------------
; road: rows HZ-23 (road rows HZ-12 to 11), 32 tiles each, top to bottom
; ---------------------------------------------------------------
DRAW_ROAD:
  LDA HZ
  JSR ROW_ADDR
  LDA HZ
  SEC
  SBC #12
  TAX
.dr_r:
  STX J
  LDA RCL,X
  STA CL
  LDA RCH,X
  STA CH
  LDA RB,X
  STA T1                       ; band * 96
  LDA RG,X
  STA ZG
  LDA SLLT,X                   ; outward slopes from the centre step
  STA T2
  INC A
  STA ZNL
  LDA SLRT,X
  STA T3
  INC A
  STA ZNR
  SEC                          ; left edge top = centre - LW
  LDA CL
  SBC LW,X
  TAY
  LDA CH
  SBC #0
  TAX
  LDA CELLLO,Y
  ORA CELLHI,X
  SEC
  SBC T2
  STA ZKL
  LDX T2                       ; index = band*96 + slope*32 + phase*4
  LDA PH4,Y
  ORA SL32,X
  CLC
  ADC T1
  STA ZTLI
  LDX J
  CLC                          ; right edge top = centre + LW
  LDA CL
  ADC LW,X
  TAY
  LDA CH
  ADC #0
  TAX
  LDA CELLLO,Y
  ORA CELLHI,X
  STA ZKR
  LDX T3
  LDA PH4,Y
  ORA SL32,X
  CLC
  ADC T1
  STA ZTRI
  LDA #$FF                     ; dash only on the light band of the near rows
  STA ZKD
  LDA T1
  BNE .dr_c
  LDX J
  CPX #3
  BCC .dr_c
  SEC                          ; dash left = centre - 1
  LDA CL
  SBC #1
  TAY
  LDA CH
  SBC #0
  TAX
  LDA CELLLO,Y
  ORA CELLHI,X
  STA ZKD
  TYA
  AND #7
  ORA #104
  STA ZTD
.dr_c:
  LDA ZKL                      ; whole row on the screen?
  CMP #64
  BCC .dr_slow
  LDA ZKR
  CLC
  ADC ZNR
  CMP #97
  BCC .dr_fast
.dr_slow:
  JSR SLOW_ROW
  JMP .dr_n
.dr_fast:
  STA T0                       ; first grass cell on the right
  LDA ZKL                      ; grass
  SEC
  SBC #64
  BEQ .dr_1
  TAY
  LDA ZG
.dr_l1:
  STA VDATA
  DEY
  BNE .dr_l1
.dr_1:
  LDX ZNL                      ; left edge cells
  LDY ZTLI
.dr_le:
  LDA TLT,Y
  STA VDATA
  INY
  DEX
  BNE .dr_le
  LDA ZKL                      ; first asphalt cell
  CLC
  ADC ZNL
  STA T2
  LDA ZKD
  CMP #$FF
  BEQ .dr_nd
  SEC                          ; asphalt, dash
  SBC T2
  BEQ .dr_2
  TAY
  LDA #3
.dr_l2:
  STA VDATA
  DEY
  BNE .dr_l2
.dr_2:
  LDA ZTD
  STA VDATA
  CLC
  ADC #8
  NOP
  STA VDATA
  LDA ZKD
  CLC
  ADC #2
  STA T2
.dr_nd:
  LDA ZKR                      ; asphalt up to the right edge
  SEC
  SBC T2
  BEQ .dr_3
  TAY
  LDA #3
.dr_l3:
  STA VDATA
  DEY
  BNE .dr_l3
.dr_3:
  LDX ZNR                      ; right edge cells
  LDY ZTRI
.dr_re:
  LDA TRT,Y
  STA VDATA
  INY
  DEX
  BNE .dr_re
  LDA #96                      ; grass
  SEC
  SBC T0
  BEQ .dr_n
  TAY
  LDA ZG
.dr_l4:
  STA VDATA
  DEY
  BNE .dr_l4
.dr_n:
  LDX J
  INX
  CPX #12
  BEQ .dr_x
  JMP .dr_r
.dr_x:
  RTS

; a row that leaves the screen: the 6 boundaries clamped to columns 64-96, then the same runs
; T2 left edge, T3 asphalt, T4 dash, T5 asphalt, T6 right edge, T7 grass
SLOW_ROW:
  LDA ZKL
  CMP #64
  BCS .c1a
  LDA #64
.c1a:
  CMP #96
  BCC .c1b
  LDA #96
.c1b:
  STA T2
  LDA ZKL
  CLC
  ADC ZNL
  CMP #64
  BCS .c2a
  LDA #64
.c2a:
  CMP #96
  BCC .c2b
  LDA #96
.c2b:
  STA T3
  LDA ZKD
  CMP #$FF
  BNE .sr_d
  LDA T3                       ; no dash
  STA T4
  BRA .sr_e
.sr_d:
  CMP #64
  BCS .c3a
  LDA #64
.c3a:
  CMP #96
  BCC .c3b
  LDA #96
.c3b:
  STA T4
  LDA ZKD
  CLC
  ADC #2
  CMP #64
  BCS .c4a
  LDA #64
.c4a:
  CMP #96
  BCC .c4b
  LDA #96
.c4b:
.sr_e:
  STA T5
  LDA ZKR
  CMP #64
  BCS .c5a
  LDA #64
.c5a:
  CMP #96
  BCC .c5b
  LDA #96
.c5b:
  STA T6
  LDA ZKR
  CLC
  ADC ZNR
  CMP #64
  BCS .c6a
  LDA #64
.c6a:
  CMP #96
  BCC .c6b
  LDA #96
.c6b:
  STA T7
  LDA T2
  SEC
  SBC #64
  BEQ .g1x
  TAY
  LDA ZG
.g1l:
  STA VDATA
  DEY
  BNE .g1l
.g1x:
  LDA T3
  SEC
  SBC T2
  BEQ .lex
  TAX
  LDA T2                      ; first visible cell of the edge
  SEC
  SBC ZKL
  CLC
  ADC ZTLI
  TAY
.lel:
  LDA TLT,Y
  STA VDATA
  INY
  DEX
  BNE .lel
.lex:
  LDA T4
  SEC
  SBC T3
  BEQ .a1x
  TAY
  LDA #3
.a1l:
  STA VDATA
  DEY
  BNE .a1l
.a1x:
  LDA T5                       ; dash cells
  SEC
  SBC T4
  BEQ .sr_dx
  TAX
  LDA T4
  SEC
  SBC ZKD
  ASL A
  ASL A
  ASL A
  CLC
  ADC ZTD
.sr_dl:
  STA VDATA
  CLC
  ADC #8
  DEX
  BNE .sr_dl
.sr_dx:
  LDA T6
  SEC
  SBC T5
  BEQ .a2x
  TAY
  LDA #3
.a2l:
  STA VDATA
  DEY
  BNE .a2l
.a2x:
  LDA T7
  SEC
  SBC T6
  BEQ .rex
  TAX
  LDA T6                      ; first visible cell of the edge
  SEC
  SBC ZKR
  CLC
  ADC ZTRI
  TAY
.rel:
  LDA TRT,Y
  STA VDATA
  INY
  DEX
  BNE .rel
.rex:
  LDA #96
  SEC
  SBC T7
  BEQ .g2x
  TAY
  LDA ZG
.g2l:
  STA VDATA
  DEY
  BNE .g2l
.g2x:
  RTS

; ---------------------------------------------------------------
; centre, band and edge slopes of each road row
; ---------------------------------------------------------------
ROAD_CENT:                     ; unrolled: 12 rows, then the bands and the slopes
  LDA CV
  STA Q0
  LDA PX
  STA Q1
  LDY Q0                       ; row 0: centre = 640 + curve - side (both + 128)
  LDA OFFC+0*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+0*256,Y
  BCC .rc_0a
  INX
.rc_0a:
  EOR #$80
  BMI .rc_0b
  INX
.rc_0b:
  STA RCL+0
  STX RCH+0
  LDY Q0                       ; row 1: centre = 640 + curve - side (both + 128)
  LDA OFFC+1*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+1*256,Y
  BCC .rc_1a
  INX
.rc_1a:
  EOR #$80
  BMI .rc_1b
  INX
.rc_1b:
  STA RCL+1
  STX RCH+1
  LDY Q0                       ; row 2: centre = 640 + curve - side (both + 128)
  LDA OFFC+2*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+2*256,Y
  BCC .rc_2a
  INX
.rc_2a:
  EOR #$80
  BMI .rc_2b
  INX
.rc_2b:
  STA RCL+2
  STX RCH+2
  LDY Q0                       ; row 3: centre = 640 + curve - side (both + 128)
  LDA OFFC+3*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+3*256,Y
  BCC .rc_3a
  INX
.rc_3a:
  EOR #$80
  BMI .rc_3b
  INX
.rc_3b:
  STA RCL+3
  STX RCH+3
  LDY Q0                       ; row 4: centre = 640 + curve - side (both + 128)
  LDA OFFC+4*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+4*256,Y
  BCC .rc_4a
  INX
.rc_4a:
  EOR #$80
  BMI .rc_4b
  INX
.rc_4b:
  STA RCL+4
  STX RCH+4
  LDY Q0                       ; row 5: centre = 640 + curve - side (both + 128)
  LDA OFFC+5*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+5*256,Y
  BCC .rc_5a
  INX
.rc_5a:
  EOR #$80
  BMI .rc_5b
  INX
.rc_5b:
  STA RCL+5
  STX RCH+5
  LDY Q0                       ; row 6: centre = 640 + curve - side (both + 128)
  LDA OFFC+6*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+6*256,Y
  BCC .rc_6a
  INX
.rc_6a:
  EOR #$80
  BMI .rc_6b
  INX
.rc_6b:
  STA RCL+6
  STX RCH+6
  LDY Q0                       ; row 7: centre = 640 + curve - side (both + 128)
  LDA OFFC+7*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+7*256,Y
  BCC .rc_7a
  INX
.rc_7a:
  EOR #$80
  BMI .rc_7b
  INX
.rc_7b:
  STA RCL+7
  STX RCH+7
  LDY Q0                       ; row 8: centre = 640 + curve - side (both + 128)
  LDA OFFC+8*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+8*256,Y
  BCC .rc_8a
  INX
.rc_8a:
  EOR #$80
  BMI .rc_8b
  INX
.rc_8b:
  STA RCL+8
  STX RCH+8
  LDY Q0                       ; row 9: centre = 640 + curve - side (both + 128)
  LDA OFFC+9*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+9*256,Y
  BCC .rc_9a
  INX
.rc_9a:
  EOR #$80
  BMI .rc_9b
  INX
.rc_9b:
  STA RCL+9
  STX RCH+9
  LDY Q0                       ; row 10: centre = 640 + curve - side (both + 128)
  LDA OFFC+10*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+10*256,Y
  BCC .rc_10a
  INX
.rc_10a:
  EOR #$80
  BMI .rc_10b
  INX
.rc_10b:
  STA RCL+10
  STX RCH+10
  LDY Q0                       ; row 11: centre = 640 + curve - side (both + 128)
  LDA OFFC+11*256,Y
  LDY Q1
  LDX #1
  SEC
  SBC OFFP+11*256,Y
  BCC .rc_11a
  INX
.rc_11a:
  EOR #$80
  BMI .rc_11b
  INX
.rc_11b:
  STA RCL+11
  STX RCH+11
  LDA #0                       ; far rows: no bands
  STA RB
  STA RB+1
  STA RB+2
  STA RB+3
  LDA #1
  STA RG
  STA RG+1
  STA RG+2
  STA RG+3
  LDA ZT+4                     ; row 4: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+4
  LDA BANDG,Y
  STA RG+4
  LDA ZT+5                     ; row 5: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+5
  LDA BANDG,Y
  STA RG+5
  LDA ZT+6                     ; row 6: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+6
  LDA BANDG,Y
  STA RG+6
  LDA ZT+7                     ; row 7: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+7
  LDA BANDG,Y
  STA RG+7
  LDA ZT+8                     ; row 8: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+8
  LDA BANDG,Y
  STA RG+8
  LDA ZT+9                     ; row 9: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+9
  LDA BANDG,Y
  STA RG+9
  LDA ZT+10                     ; row 10: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+10
  LDA BANDG,Y
  STA RG+10
  LDA ZT+11                     ; row 11: band from bit 2 of depth + distance
  CLC
  ADC POSL
  AND #4
  TAY
  LDA BANDB,Y
  STA RB+11
  LDA BANDG,Y
  STA RG+11
  LDA RCL+1                    ; row 0: slopes from the centre step to the row below
  SEC
  SBC RCL+0
  TAY
  LDA SLOPE_L,Y
  STA SLLT+0
  LDA SLOPE_R,Y
  STA SLRT+0
  LDA RCL+2                    ; row 1: slopes from the centre step to the row below
  SEC
  SBC RCL+1
  TAY
  LDA SLOPE_L,Y
  STA SLLT+1
  LDA SLOPE_R,Y
  STA SLRT+1
  LDA RCL+3                    ; row 2: slopes from the centre step to the row below
  SEC
  SBC RCL+2
  TAY
  LDA SLOPE_L,Y
  STA SLLT+2
  LDA SLOPE_R,Y
  STA SLRT+2
  LDA RCL+4                    ; row 3: slopes from the centre step to the row below
  SEC
  SBC RCL+3
  TAY
  LDA SLOPE_L,Y
  STA SLLT+3
  LDA SLOPE_R,Y
  STA SLRT+3
  LDA RCL+5                    ; row 4: slopes from the centre step to the row below
  SEC
  SBC RCL+4
  TAY
  LDA SLOPE_L,Y
  STA SLLT+4
  LDA SLOPE_R,Y
  STA SLRT+4
  LDA RCL+6                    ; row 5: slopes from the centre step to the row below
  SEC
  SBC RCL+5
  TAY
  LDA SLOPE_L,Y
  STA SLLT+5
  LDA SLOPE_R,Y
  STA SLRT+5
  LDA RCL+7                    ; row 6: slopes from the centre step to the row below
  SEC
  SBC RCL+6
  TAY
  LDA SLOPE_L,Y
  STA SLLT+6
  LDA SLOPE_R,Y
  STA SLRT+6
  LDA RCL+8                    ; row 7: slopes from the centre step to the row below
  SEC
  SBC RCL+7
  TAY
  LDA SLOPE_L,Y
  STA SLLT+7
  LDA SLOPE_R,Y
  STA SLRT+7
  LDA RCL+9                    ; row 8: slopes from the centre step to the row below
  SEC
  SBC RCL+8
  TAY
  LDA SLOPE_L,Y
  STA SLLT+8
  LDA SLOPE_R,Y
  STA SLRT+8
  LDA RCL+10                    ; row 9: slopes from the centre step to the row below
  SEC
  SBC RCL+9
  TAY
  LDA SLOPE_L,Y
  STA SLLT+9
  LDA SLOPE_R,Y
  STA SLRT+9
  LDA RCL+11                    ; row 10: slopes from the centre step to the row below
  SEC
  SBC RCL+10
  TAY
  LDA SLOPE_L,Y
  STA SLLT+10
  LDA SLOPE_R,Y
  STA SLRT+10
  STA SLRT+11                  ; the last row like the one above
  LDA SLLT+10
  STA SLLT+11
  RTS

BANDB: .byte 0,0,0,0,96         ; band * 96, by bit 2
BANDG: .byte 1,0,0,0,2          ; grass tile


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from brick drop; the engine added)
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
  CMP #CMD_LOOP
  BNE .st_once
  JSR SND_LOOP
  BRA .st_run
.st_once:
  JSR SND_START
.st_run:
  LDA SND_MODE
  BEQ .st_sfx
  JSR MUS_TICK
  LDA SND_MODE                  ; the music of the game: the engine, then the effects over it
  CMP #2
  BNE .st_flush
  JSR SND_ENGINE
  JSR SFX_OVL
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
; starts the tune SONG: once (SND_START) or again and again with the
; effects of the game over it (SND_LOOP)
; ---------------------------------------------------------------
SND_START:
  JSR SND_MIX
  JSR SND_TRACKS
  LDA #$01
  STA SND_MODE
  STA SND_BUSY
  RTS

SND_LOOP:
  JSR SND_MIX
  JSR SND_TRACKS
  LDA #$02
  STA SND_MODE
  STZ SND_BUSY
  RTS

SND_MIX:
  JSR SND_CLEAR_SH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #$2A                      ; right: tone A, noise B (drums), tone C
  STA SH_R+7
  RTS

SND_TRACKS:                     ; the 4 tracks of SONG from their start
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
  LDA SND_MODE                  ; the music of the game starts again
  CMP #2
  BNE .mt_once
  JMP SND_TRACKS
.mt_once:
  JSR SND_GAME_MODE             ; silence, SND_BUSY = 0
.mt_end:
  RTS

; the effects alone: the volumes to 0, the engine, then the effects playing
SFX_TICK:
  LDA #$00
  LDX #2
.sf_z:
  STA SH_L+8,X
  STA SH_R+8,X
  DEX
  BPL .sf_z
  JSR SND_ENGINE
  BRA SFX_RUN

; the engine: a tone on channel A of the right chip (ENGV = 0: silent)
SND_ENGINE:
  LDA ENGV
  BEQ .se_e
  STA SH_R+8
  LDA ENGL
  STA SH_R
  LDA ENGH
  STA SH_R+1
.se_e:
  RTS

; the effects over the music of the game: an effect takes its channels for as long as it plays
SFX_OVL:
  LDA #$38                      ; left: 3 tones (the noise only while an effect needs it)
  STA SH_L+7
SFX_RUN:
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
  LDA #$2A                      ; tone A, noise B, tone C
  STA SH_L+7,Y
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
;  LIBRARY: joystick, frames, VDP
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
;  and optionally (defined before the library):
;    REC_ITALIAN  the texts of the sign screen in Italian
;    REC_ONEPL    one player only: no "PLAYER n" line
;    REC_BMP      a bitmap game: REC_XY only sets the cell, every
;                 character goes to REC_CHR (A = ASCII, may change
;                 A, X, Y; the cell moves on by itself or here) and
;                 REC_CLRROWS (A = first row, X = rows) clears rows
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
;  One against one (wins in a row against the CPU):
;    REC_LOSE   at RESET and when the CPU wins: the run starts again
;    REC_WIN    the player beat the CPU (REC_EX set): the run grows
;               by one and is signed, in place of its own row
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
REC_STK    = REC_RAM+$283      ; one-against-one games: wins in a row against the CPU (BCD)
REC_RUN    = REC_RAM+$284      ; offset of the row of this run in the table ($FF = none)

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
;  REC_WIN / REC_LOSE: a run of wins against the CPU. Every win
;  signs the run again (the initials of the last signature are
;  offered), and the row of the run moves up instead of a new row:
;  the table keeps the run even if the power goes off before it ends.
; ---------------------------------------------------------------
REC_LOSE:
  STZ REC_STK
  LDA #$FF
  STA REC_RUN
  RTS

REC_WIN:
  SED                          ; one more win (99 at most)
  LDA REC_STK
  CMP #$99
  BEQ .rw_m
  CLC
  ADC #1
  STA REC_STK
.rw_m:
  CLD
  LDX REC_RUN                  ; the old row of the run goes away
  BMI .rw_c
.rw_sh:
  CPX #56
  BCS .rw_e
  LDA REC_TAB+8,X
  STA REC_TAB,X
  INX
  BRA .rw_sh
.rw_e:
  LDX #7                       ; the last row is empty
.rw_z:
  LDA #0
  CPX #4
  BCC .rw_zb
  CPX #7
  BCS .rw_zb
  LDA #'-'
.rw_zb:
  STA REC_TAB+56,X
  DEX
  BPL .rw_z
.rw_c:
  LDA REC_STK
  STA REC_SC
  STZ REC_SC+1
  STZ REC_SC+2
  STZ REC_SC+3
  STZ REC_PL
  JSR REC_CHECK
  LDA #$FF
  BCC .rw_p
  LDA REC_POS
.rw_p:
  STA REC_RUN
  JMP REC_SAVE

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
  LDY #RT_NEWX
  LDA #(RT_NEW-REC_TXT)
  JSR REC_PUTS
  .ifndef REC_ONEPL
  LDX #REC_SROW-2
  LDY #RT_PLX
  LDA #(RT_PLAYER-REC_TXT)
  JSR REC_PUTS
  LDA REC_PL
  CLC
  ADC #'1'
  JSR REC_OUT
  .endif
  LDA #REC_SROW
  STA REC_R0
  JSR REC_SHOW_R
  LDX #REC_SROW+10
  LDY #RT_HX
  LDA #(RT_H1-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+11
  LDY #RT_HX
  LDA #(RT_H2-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+12
  LDY #RT_HX
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
  JSR REC_OUT
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
  JSR REC_OUT
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
  .ifdef REC_BMP
  PHA                          ; a bitmap game draws the character in its cell
  PHX
  PHY
  JSR REC_CHR
  PLY
  PLX
  PLA
  .else
  STA VDATA
  .endif
  RTS

; REC_WIPEN rows from REC_ROW blank (REC_WIPE_R: from REC_R0)
REC_WIPE:
  LDA #REC_ROW
  STA REC_R0
REC_WIPE_R:
  .ifdef REC_BMP
  LDA REC_R0
  LDX #REC_WIPEN
  JMP REC_CLRROWS
  .endif
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
  JSR REC_OUT
  INX
  BRA .pu_l
.pu_e:
  RTS

REC_TXT:
  .ifdef REC_ITALIAN
RT_NEW:    .byte "NUOVO RECORD",0
RT_PLAYER: .byte "GIOCATORE ",0
RT_H1:     .byte "SU/GIU'         LETTERA",0
RT_H2:     .byte "SINISTRA/DESTRA SPOSTA",0
RT_H3:     .byte "TASTO           AVANTI/OK",0
RT_NEWX    = 10                ; columns of the texts
RT_PLX     = 10
RT_HX      = 4
  .else
RT_NEW:    .byte "NEW RECORD",0
RT_PLAYER: .byte "PLAYER ",0
RT_H1:     .byte "UP/DOWN    LETTER",0
RT_H2:     .byte "LEFT/RIGHT MOVE",0
RT_H3:     .byte "BUTTON     NEXT/OK",0
RT_NEWX    = 11
RT_PLX     = 12
RT_HX      = 7
  .endif
; ===============================================================
;  TABLES
; ===============================================================
S_BIG = S_CRASH                                 ; (lib_sound: a big noise is not cut by a small one)
TP_IDLE = 1645                                  ; engine period when the car stands (38 Hz)

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,12,"HI",0
  .byte $FF
TXT_HUD:
  .byte 0,23,"STAGE",0
  .byte 1,0,"TIME",0
  .byte 1,16,"KM/H",0
  .byte 1,22,"GEAR",0
  .byte $FF
TXT_BUTTONS:
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,1,"RACE THE CLOCK TO THE HORIZON",0
  .byte 11,3,"LEFT/RIGHT  STEER",0
  .byte 12,3,"BUTTON 1    ACCELERATE",0
  .byte 13,3,"BUTTON 2    BRAKE",0
  .byte 14,3,"UP / DOWN   LOW / HIGH GEAR",0
  .byte 16,3,"EVERY CHECKPOINT GIVES TIME",0
  .byte 17,3,"PASS THE CARS, KEEP OFF",0
  .byte 18,3,"THE GRASS",0
  .byte $FF
TXT_C3:  .byte 6,11,"    3     ",0,$FF
TXT_C2:  .byte 6,11,"    2     ",0,$FF
TXT_C1:  .byte 6,11,"    1     ",0,$FF
TXT_GO:  .byte 6,11,"   GO!    ",0,$FF
TXT_TUP: .byte 5,11," TIME UP  ",0,$FF
TXT_OVR: .byte 5,11,"GAME  OVER",0,$FF
TXT_CHK: .byte 5,11,"CHECKPOINT",0
         .byte 6,11,"TIME +    ",0,$FF
TXT_LAP: .byte 5,11," NEW LAP  ",0
         .byte 6,11,"TIME +    ",0,$FF
TXT_PLAYERH: .byte "PLAYER "

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 11, 7, 10, 0      ; volume at the attack of the note
FLOOR_TAB:     .byte 6, 4, 5, 0        ; lowest volume reached by the decay
DECMASK_TAB:   .byte 3, 7, 3, 0        ; the volume drops by 1 when (age AND mask) = 0
; drums: 1 kick, 2 snare, 3 hi-hat, 4 cymbal
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 13, 11, 6, 13
DRUM_MASK:     .byte 0, 0, 0, 0, 7
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
;  GRAPHICS, ROAD, TRACKS AND SOUND TABLES (generated)
; ===============================================================
; TURBO HORIZON: generated by dev/gen_turbo_horizon.js (do not edit by hand)

BIGT = 200
BIGB = 220
NBIG = 9
SPR_PAGES = 2
MAXL = 228
MAXH = 412
NSTG = 5
 .align 8
OFFC:
  .byte $80,$81,$81,$82,$83,$84,$84,$85,$86,$86,$87,$88,$89,$89,$8A,$8B,$8B,$8C,$8D,$8D,$8E,$8F,$90,$90,$91,$92,$92,$93,$94,$95,$95,$96
  .byte $97,$97,$98,$99,$9A,$9A,$9B,$9C,$9C,$9D,$9E,$9E,$9F,$A0,$A1,$A1,$A2,$A3,$A3,$A4,$A5,$A6,$A6,$A7,$A8,$A8,$A9,$AA,$AB,$AB,$AC,$AD
  .byte $AD,$AE,$AF,$B0,$B0,$B1,$B2,$B2,$B3,$B4,$B4,$B5,$B6,$B7,$B7,$B8,$B9,$B9,$BA,$BB,$BC,$BC,$BD,$BE,$BE,$BF,$C0,$C1,$C1,$C2,$C3,$C3
  .byte $C4,$C5,$C5,$C6,$C7,$C8,$C8,$C9,$CA,$CA,$CB,$CC,$CD,$CD,$CE,$CF,$CF,$D0,$D1,$D2,$D2,$D3,$D4,$D4,$D5,$D6,$D6,$D7,$D8,$D9,$D9,$DA
  .byte $25,$26,$27,$27,$28,$29,$2A,$2A,$2B,$2C,$2C,$2D,$2E,$2E,$2F,$30,$31,$31,$32,$33,$33,$34,$35,$36,$36,$37,$38,$38,$39,$3A,$3B,$3B
  .byte $3C,$3D,$3D,$3E,$3F,$3F,$40,$41,$42,$42,$43,$44,$44,$45,$46,$47,$47,$48,$49,$49,$4A,$4B,$4C,$4C,$4D,$4E,$4E,$4F,$50,$50,$51,$52
  .byte $53,$53,$54,$55,$55,$56,$57,$58,$58,$59,$5A,$5A,$5B,$5C,$5D,$5D,$5E,$5F,$5F,$60,$61,$62,$62,$63,$64,$64,$65,$66,$66,$67,$68,$69
  .byte $69,$6A,$6B,$6B,$6C,$6D,$6E,$6E,$6F,$70,$70,$71,$72,$73,$73,$74,$75,$75,$76,$77,$77,$78,$79,$7A,$7A,$7B,$7C,$7C,$7D,$7E,$7F,$7F
  .byte $80,$81,$81,$82,$82,$83,$84,$84,$85,$85,$86,$86,$87,$88,$88,$89,$89,$8A,$8B,$8B,$8C,$8C,$8D,$8D,$8E,$8F,$8F,$90,$90,$91,$92,$92
  .byte $93,$93,$94,$95,$95,$96,$96,$97,$97,$98,$99,$99,$9A,$9A,$9B,$9C,$9C,$9D,$9D,$9E,$9E,$9F,$A0,$A0,$A1,$A1,$A2,$A3,$A3,$A4,$A4,$A5
  .byte $A6,$A6,$A7,$A7,$A8,$A8,$A9,$AA,$AA,$AB,$AB,$AC,$AD,$AD,$AE,$AE,$AF,$AF,$B0,$B1,$B1,$B2,$B2,$B3,$B4,$B4,$B5,$B5,$B6,$B6,$B7,$B8
  .byte $B8,$B9,$B9,$BA,$BB,$BB,$BC,$BC,$BD,$BE,$BE,$BF,$BF,$C0,$C0,$C1,$C2,$C2,$C3,$C3,$C4,$C5,$C5,$C6,$C6,$C7,$C7,$C8,$C9,$C9,$CA,$CA
  .byte $35,$36,$36,$37,$37,$38,$39,$39,$3A,$3A,$3B,$3B,$3C,$3D,$3D,$3E,$3E,$3F,$40,$40,$41,$41,$42,$42,$43,$44,$44,$45,$45,$46,$47,$47
  .byte $48,$48,$49,$4A,$4A,$4B,$4B,$4C,$4C,$4D,$4E,$4E,$4F,$4F,$50,$51,$51,$52,$52,$53,$53,$54,$55,$55,$56,$56,$57,$58,$58,$59,$59,$5A
  .byte $5B,$5B,$5C,$5C,$5D,$5D,$5E,$5F,$5F,$60,$60,$61,$62,$62,$63,$63,$64,$64,$65,$66,$66,$67,$67,$68,$69,$69,$6A,$6A,$6B,$6B,$6C,$6D
  .byte $6D,$6E,$6E,$6F,$70,$70,$71,$71,$72,$73,$73,$74,$74,$75,$75,$76,$77,$77,$78,$78,$79,$7A,$7A,$7B,$7B,$7C,$7C,$7D,$7E,$7E,$7F,$7F
  .byte $80,$80,$81,$81,$82,$82,$83,$83,$84,$84,$85,$85,$86,$86,$87,$87,$88,$88,$89,$89,$89,$8A,$8A,$8B,$8B,$8C,$8C,$8D,$8D,$8E,$8E,$8F
  .byte $8F,$90,$90,$91,$91,$92,$92,$93,$93,$93,$94,$94,$95,$95,$96,$96,$97,$97,$98,$98,$99,$99,$9A,$9A,$9B,$9B,$9C,$9C,$9C,$9D,$9D,$9E
  .byte $9E,$9F,$9F,$A0,$A0,$A1,$A1,$A2,$A2,$A3,$A3,$A4,$A4,$A5,$A5,$A5,$A6,$A6,$A7,$A7,$A8,$A8,$A9,$A9,$AA,$AA,$AB,$AB,$AC,$AC,$AD,$AD
  .byte $AE,$AE,$AF,$AF,$AF,$B0,$B0,$B1,$B1,$B2,$B2,$B3,$B3,$B4,$B4,$B5,$B5,$B6,$B6,$B7,$B7,$B8,$B8,$B8,$B9,$B9,$BA,$BA,$BB,$BB,$BC,$BC
  .byte $43,$44,$44,$45,$45,$46,$46,$47,$47,$48,$48,$48,$49,$49,$4A,$4A,$4B,$4B,$4C,$4C,$4D,$4D,$4E,$4E,$4F,$4F,$50,$50,$51,$51,$51,$52
  .byte $52,$53,$53,$54,$54,$55,$55,$56,$56,$57,$57,$58,$58,$59,$59,$5A,$5A,$5B,$5B,$5B,$5C,$5C,$5D,$5D,$5E,$5E,$5F,$5F,$60,$60,$61,$61
  .byte $62,$62,$63,$63,$64,$64,$64,$65,$65,$66,$66,$67,$67,$68,$68,$69,$69,$6A,$6A,$6B,$6B,$6C,$6C,$6D,$6D,$6D,$6E,$6E,$6F,$6F,$70,$70
  .byte $71,$71,$72,$72,$73,$73,$74,$74,$75,$75,$76,$76,$77,$77,$77,$78,$78,$79,$79,$7A,$7A,$7B,$7B,$7C,$7C,$7D,$7D,$7E,$7E,$7F,$7F,$80
  .byte $80,$80,$81,$81,$82,$82,$82,$83,$83,$83,$84,$84,$85,$85,$85,$86,$86,$86,$87,$87,$88,$88,$88,$89,$89,$89,$8A,$8A,$8B,$8B,$8B,$8C
  .byte $8C,$8C,$8D,$8D,$8E,$8E,$8E,$8F,$8F,$8F,$90,$90,$91,$91,$91,$92,$92,$92,$93,$93,$94,$94,$94,$95,$95,$95,$96,$96,$97,$97,$97,$98
  .byte $98,$98,$99,$99,$9A,$9A,$9A,$9B,$9B,$9B,$9C,$9C,$9D,$9D,$9D,$9E,$9E,$9E,$9F,$9F,$A0,$A0,$A0,$A1,$A1,$A1,$A2,$A2,$A3,$A3,$A3,$A4
  .byte $A4,$A4,$A5,$A5,$A6,$A6,$A6,$A7,$A7,$A7,$A8,$A8,$A9,$A9,$A9,$AA,$AA,$AA,$AB,$AB,$AC,$AC,$AC,$AD,$AD,$AD,$AE,$AE,$AF,$AF,$AF,$B0
  .byte $50,$50,$51,$51,$52,$52,$52,$53,$53,$53,$54,$54,$55,$55,$55,$56,$56,$56,$57,$57,$58,$58,$58,$59,$59,$59,$5A,$5A,$5B,$5B,$5B,$5C
  .byte $5C,$5C,$5D,$5D,$5E,$5E,$5E,$5F,$5F,$5F,$60,$60,$61,$61,$61,$62,$62,$62,$63,$63,$64,$64,$64,$65,$65,$65,$66,$66,$67,$67,$67,$68
  .byte $68,$68,$69,$69,$6A,$6A,$6A,$6B,$6B,$6B,$6C,$6C,$6D,$6D,$6D,$6E,$6E,$6E,$6F,$6F,$70,$70,$70,$71,$71,$71,$72,$72,$73,$73,$73,$74
  .byte $74,$74,$75,$75,$76,$76,$76,$77,$77,$77,$78,$78,$79,$79,$79,$7A,$7A,$7A,$7B,$7B,$7C,$7C,$7C,$7D,$7D,$7D,$7E,$7E,$7F,$7F,$7F,$80
  .byte $80,$80,$81,$81,$81,$81,$82,$82,$82,$83,$83,$83,$83,$84,$84,$84,$85,$85,$85,$85,$86,$86,$86,$87,$87,$87,$87,$88,$88,$88,$89,$89
  .byte $89,$89,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8C,$8C,$8C,$8D,$8D,$8D,$8D,$8E,$8E,$8E,$8F,$8F,$8F,$90,$90,$90,$90,$91,$91,$91,$92,$92,$92
  .byte $92,$93,$93,$93,$94,$94,$94,$94,$95,$95,$95,$96,$96,$96,$96,$97,$97,$97,$98,$98,$98,$98,$99,$99,$99,$9A,$9A,$9A,$9A,$9B,$9B,$9B
  .byte $9C,$9C,$9C,$9C,$9D,$9D,$9D,$9E,$9E,$9E,$9E,$9F,$9F,$9F,$A0,$A0,$A0,$A0,$A1,$A1,$A1,$A2,$A2,$A2,$A2,$A3,$A3,$A3,$A4,$A4,$A4,$A4
  .byte $5B,$5C,$5C,$5C,$5C,$5D,$5D,$5D,$5E,$5E,$5E,$5E,$5F,$5F,$5F,$60,$60,$60,$60,$61,$61,$61,$62,$62,$62,$62,$63,$63,$63,$64,$64,$64
  .byte $64,$65,$65,$65,$66,$66,$66,$66,$67,$67,$67,$68,$68,$68,$68,$69,$69,$69,$6A,$6A,$6A,$6A,$6B,$6B,$6B,$6C,$6C,$6C,$6C,$6D,$6D,$6D
  .byte $6E,$6E,$6E,$6E,$6F,$6F,$6F,$70,$70,$70,$70,$71,$71,$71,$72,$72,$72,$73,$73,$73,$73,$74,$74,$74,$75,$75,$75,$75,$76,$76,$76,$77
  .byte $77,$77,$77,$78,$78,$78,$79,$79,$79,$79,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7C,$7C,$7C,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$80
  .byte $80,$80,$80,$81,$81,$81,$81,$81,$82,$82,$82,$82,$83,$83,$83,$83,$83,$84,$84,$84,$84,$84,$85,$85,$85,$85,$85,$86,$86,$86,$86,$87
  .byte $87,$87,$87,$87,$88,$88,$88,$88,$88,$89,$89,$89,$89,$89,$8A,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8B,$8C,$8C,$8C,$8C,$8C,$8D,$8D,$8D,$8D
  .byte $8E,$8E,$8E,$8E,$8E,$8F,$8F,$8F,$8F,$8F,$90,$90,$90,$90,$90,$91,$91,$91,$91,$92,$92,$92,$92,$92,$93,$93,$93,$93,$93,$94,$94,$94
  .byte $94,$94,$95,$95,$95,$95,$96,$96,$96,$96,$96,$97,$97,$97,$97,$97,$98,$98,$98,$98,$98,$99,$99,$99,$99,$9A,$9A,$9A,$9A,$9A,$9B,$9B
  .byte $65,$65,$65,$66,$66,$66,$66,$66,$67,$67,$67,$67,$68,$68,$68,$68,$68,$69,$69,$69,$69,$69,$6A,$6A,$6A,$6A,$6A,$6B,$6B,$6B,$6B,$6C
  .byte $6C,$6C,$6C,$6C,$6D,$6D,$6D,$6D,$6D,$6E,$6E,$6E,$6E,$6E,$6F,$6F,$6F,$6F,$70,$70,$70,$70,$70,$71,$71,$71,$71,$71,$72,$72,$72,$72
  .byte $73,$73,$73,$73,$73,$74,$74,$74,$74,$74,$75,$75,$75,$75,$75,$76,$76,$76,$76,$77,$77,$77,$77,$77,$78,$78,$78,$78,$78,$79,$79,$79
  .byte $79,$79,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7B,$7C,$7C,$7C,$7C,$7C,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F,$80,$80
  .byte $80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$82,$82,$82,$82,$82,$82,$82,$83,$83,$83,$83,$83,$83,$84,$84,$84,$84,$84,$84,$84,$85
  .byte $85,$85,$85,$85,$85,$85,$86,$86,$86,$86,$86,$86,$86,$87,$87,$87,$87,$87,$87,$87,$88,$88,$88,$88,$88,$88,$88,$89,$89,$89,$89,$89
  .byte $89,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8D,$8D,$8D,$8D,$8D,$8D,$8D,$8E,$8E,$8E
  .byte $8E,$8E,$8E,$8F,$8F,$8F,$8F,$8F,$8F,$8F,$90,$90,$90,$90,$90,$90,$90,$91,$91,$91,$91,$91,$91,$91,$92,$92,$92,$92,$92,$92,$92,$93
  .byte $6D,$6D,$6E,$6E,$6E,$6E,$6E,$6E,$6E,$6F,$6F,$6F,$6F,$6F,$6F,$6F,$70,$70,$70,$70,$70,$70,$70,$71,$71,$71,$71,$71,$71,$71,$72,$72
  .byte $72,$72,$72,$72,$73,$73,$73,$73,$73,$73,$73,$74,$74,$74,$74,$74,$74,$74,$75,$75,$75,$75,$75,$75,$75,$76,$76,$76,$76,$76,$76,$76
  .byte $77,$77,$77,$77,$77,$77,$78,$78,$78,$78,$78,$78,$78,$79,$79,$79,$79,$79,$79,$79,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7B
  .byte $7B,$7B,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7D,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$83,$83,$83,$83,$83
  .byte $83,$83,$83,$83,$83,$83,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$85,$85,$85,$85,$85,$85,$85,$85,$85,$85,$85,$86,$86,$86,$86,$86
  .byte $86,$86,$86,$86,$86,$86,$87,$87,$87,$87,$87,$87,$87,$87,$87,$87,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$89,$89,$89,$89,$89
  .byte $89,$89,$89,$89,$89,$89,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8C,$8C,$8C,$8C,$8C
  .byte $74,$74,$74,$74,$74,$74,$75,$75,$75,$75,$75,$75,$75,$75,$75,$75,$76,$76,$76,$76,$76,$76,$76,$76,$76,$76,$76,$77,$77,$77,$77,$77
  .byte $77,$77,$77,$77,$77,$77,$78,$78,$78,$78,$78,$78,$78,$78,$78,$78,$79,$79,$79,$79,$79,$79,$79,$79,$79,$79,$79,$7A,$7A,$7A,$7A,$7A
  .byte $7A,$7A,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7D,$7D,$7D,$7D,$7D
  .byte $7D,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$82,$82,$82
  .byte $82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83
  .byte $83,$83,$83,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$84,$85,$85,$85,$85,$85,$85,$85,$85,$85,$85
  .byte $85,$85,$85,$85,$85,$85,$85,$85,$85,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$86,$87,$87,$87,$87
  .byte $79,$79,$79,$79,$79,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B
  .byte $7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7D,$7D
  .byte $7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $7E,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82
  .byte $82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$82,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83,$83
  .byte $7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E
  .byte $7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F
  .byte $7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F
  .byte $7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
OFFP:
  .byte $80,$80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$81,$82,$82,$82,$82,$82,$82,$82,$82,$83,$83,$83,$83,$83,$83,$83,$83,$83,$84,$84
  .byte $84,$84,$84,$84,$84,$84,$85,$85,$85,$85,$85,$85,$85,$85,$86,$86,$86,$86,$86,$86,$86,$86,$86,$87,$87,$87,$87,$87,$87,$87,$87,$88
  .byte $88,$88,$88,$88,$88,$88,$88,$89,$89,$89,$89,$89,$89,$89,$89,$89,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8B,$8B,$8B,$8B
  .byte $8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8D,$8D,$8D,$8D,$8D,$8D,$8D,$8D,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8F,$8F,$8F,$8F,$8F,$8F,$8F
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$72,$72,$72,$72,$72,$72,$72,$72,$73,$73,$73,$73,$73,$73,$73,$73,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$75,$75,$75,$75,$75,$75,$75,$75,$76,$76,$76,$76,$76,$76,$76,$76,$77,$77,$77,$77,$77,$77,$77,$77,$77,$78,$78,$78,$78,$78,$78
  .byte $78,$78,$79,$79,$79,$79,$79,$79,$79,$79,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7B,$7C,$7C,$7C,$7C,$7C
  .byte $7C,$7C,$7C,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$80,$80,$80,$80
  .byte $80,$80,$80,$81,$81,$81,$81,$81,$82,$82,$82,$82,$82,$83,$83,$83,$83,$83,$84,$84,$84,$84,$84,$85,$85,$85,$85,$85,$86,$86,$86,$86
  .byte $86,$87,$87,$87,$87,$87,$88,$88,$88,$88,$88,$89,$89,$89,$89,$89,$8A,$8A,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8B,$8C,$8C,$8C,$8C,$8C,$8D
  .byte $8D,$8D,$8D,$8D,$8E,$8E,$8E,$8E,$8E,$8F,$8F,$8F,$8F,$8F,$90,$90,$90,$90,$90,$91,$91,$91,$91,$91,$92,$92,$92,$92,$92,$93,$93,$93
  .byte $93,$93,$94,$94,$94,$94,$94,$95,$95,$95,$95,$95,$96,$96,$96,$96,$96,$97,$97,$97,$97,$97,$98,$98,$98,$98,$98,$99,$99,$99,$99,$99
  .byte $66,$67,$67,$67,$67,$67,$68,$68,$68,$68,$68,$69,$69,$69,$69,$69,$6A,$6A,$6A,$6A,$6A,$6B,$6B,$6B,$6B,$6B,$6C,$6C,$6C,$6C,$6C,$6D
  .byte $6D,$6D,$6D,$6D,$6E,$6E,$6E,$6E,$6E,$6F,$6F,$6F,$6F,$6F,$70,$70,$70,$70,$70,$71,$71,$71,$71,$71,$72,$72,$72,$72,$72,$73,$73,$73
  .byte $73,$73,$74,$74,$74,$74,$74,$75,$75,$75,$75,$75,$76,$76,$76,$76,$76,$77,$77,$77,$77,$77,$78,$78,$78,$78,$78,$79,$79,$79,$79,$79
  .byte $7A,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7B,$7B,$7C,$7C,$7C,$7C,$7C,$7D,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$7F,$80,$80
  .byte $80,$80,$81,$81,$81,$81,$82,$82,$82,$83,$83,$83,$83,$84,$84,$84,$84,$85,$85,$85,$86,$86,$86,$86,$87,$87,$87,$88,$88,$88,$88,$89
  .byte $89,$89,$8A,$8A,$8A,$8A,$8B,$8B,$8B,$8B,$8C,$8C,$8C,$8D,$8D,$8D,$8D,$8E,$8E,$8E,$8F,$8F,$8F,$8F,$90,$90,$90,$91,$91,$91,$91,$92
  .byte $92,$92,$92,$93,$93,$93,$94,$94,$94,$94,$95,$95,$95,$96,$96,$96,$96,$97,$97,$97,$98,$98,$98,$98,$99,$99,$99,$99,$9A,$9A,$9A,$9B
  .byte $9B,$9B,$9B,$9C,$9C,$9C,$9D,$9D,$9D,$9D,$9E,$9E,$9E,$9F,$9F,$9F,$9F,$A0,$A0,$A0,$A0,$A1,$A1,$A1,$A2,$A2,$A2,$A2,$A3,$A3,$A3,$A4
  .byte $5C,$5C,$5D,$5D,$5D,$5E,$5E,$5E,$5E,$5F,$5F,$5F,$60,$60,$60,$60,$61,$61,$61,$61,$62,$62,$62,$63,$63,$63,$63,$64,$64,$64,$65,$65
  .byte $65,$65,$66,$66,$66,$67,$67,$67,$67,$68,$68,$68,$68,$69,$69,$69,$6A,$6A,$6A,$6A,$6B,$6B,$6B,$6C,$6C,$6C,$6C,$6D,$6D,$6D,$6E,$6E
  .byte $6E,$6E,$6F,$6F,$6F,$6F,$70,$70,$70,$71,$71,$71,$71,$72,$72,$72,$73,$73,$73,$73,$74,$74,$74,$75,$75,$75,$75,$76,$76,$76,$76,$77
  .byte $77,$77,$78,$78,$78,$78,$79,$79,$79,$7A,$7A,$7A,$7A,$7B,$7B,$7B,$7C,$7C,$7C,$7C,$7D,$7D,$7D,$7D,$7E,$7E,$7E,$7F,$7F,$7F,$7F,$80
  .byte $80,$80,$81,$81,$81,$82,$82,$83,$83,$83,$84,$84,$84,$85,$85,$85,$86,$86,$86,$87,$87,$88,$88,$88,$89,$89,$89,$8A,$8A,$8A,$8B,$8B
  .byte $8C,$8C,$8C,$8D,$8D,$8D,$8E,$8E,$8E,$8F,$8F,$8F,$90,$90,$91,$91,$91,$92,$92,$92,$93,$93,$93,$94,$94,$95,$95,$95,$96,$96,$96,$97
  .byte $97,$97,$98,$98,$98,$99,$99,$9A,$9A,$9A,$9B,$9B,$9B,$9C,$9C,$9C,$9D,$9D,$9E,$9E,$9E,$9F,$9F,$9F,$A0,$A0,$A0,$A1,$A1,$A1,$A2,$A2
  .byte $A3,$A3,$A3,$A4,$A4,$A4,$A5,$A5,$A5,$A6,$A6,$A7,$A7,$A7,$A8,$A8,$A8,$A9,$A9,$A9,$AA,$AA,$AA,$AB,$AB,$AC,$AC,$AC,$AD,$AD,$AD,$AE
  .byte $52,$52,$53,$53,$53,$54,$54,$54,$55,$55,$56,$56,$56,$57,$57,$57,$58,$58,$58,$59,$59,$59,$5A,$5A,$5B,$5B,$5B,$5C,$5C,$5C,$5D,$5D
  .byte $5D,$5E,$5E,$5F,$5F,$5F,$60,$60,$60,$61,$61,$61,$62,$62,$62,$63,$63,$64,$64,$64,$65,$65,$65,$66,$66,$66,$67,$67,$68,$68,$68,$69
  .byte $69,$69,$6A,$6A,$6A,$6B,$6B,$6B,$6C,$6C,$6D,$6D,$6D,$6E,$6E,$6E,$6F,$6F,$6F,$70,$70,$71,$71,$71,$72,$72,$72,$73,$73,$73,$74,$74
  .byte $74,$75,$75,$76,$76,$76,$77,$77,$77,$78,$78,$78,$79,$79,$7A,$7A,$7A,$7B,$7B,$7B,$7C,$7C,$7C,$7D,$7D,$7D,$7E,$7E,$7F,$7F,$7F,$80
  .byte $80,$80,$81,$81,$82,$82,$83,$83,$84,$84,$84,$85,$85,$86,$86,$87,$87,$87,$88,$88,$89,$89,$8A,$8A,$8B,$8B,$8B,$8C,$8C,$8D,$8D,$8E
  .byte $8E,$8F,$8F,$8F,$90,$90,$91,$91,$92,$92,$92,$93,$93,$94,$94,$95,$95,$96,$96,$96,$97,$97,$98,$98,$99,$99,$9A,$9A,$9A,$9B,$9B,$9C
  .byte $9C,$9D,$9D,$9D,$9E,$9E,$9F,$9F,$A0,$A0,$A1,$A1,$A1,$A2,$A2,$A3,$A3,$A4,$A4,$A5,$A5,$A5,$A6,$A6,$A7,$A7,$A8,$A8,$A8,$A9,$A9,$AA
  .byte $AA,$AB,$AB,$AC,$AC,$AC,$AD,$AD,$AE,$AE,$AF,$AF,$B0,$B0,$B0,$B1,$B1,$B2,$B2,$B3,$B3,$B3,$B4,$B4,$B5,$B5,$B6,$B6,$B7,$B7,$B7,$B8
  .byte $48,$48,$49,$49,$49,$4A,$4A,$4B,$4B,$4C,$4C,$4D,$4D,$4D,$4E,$4E,$4F,$4F,$50,$50,$50,$51,$51,$52,$52,$53,$53,$54,$54,$54,$55,$55
  .byte $56,$56,$57,$57,$58,$58,$58,$59,$59,$5A,$5A,$5B,$5B,$5B,$5C,$5C,$5D,$5D,$5E,$5E,$5F,$5F,$5F,$60,$60,$61,$61,$62,$62,$63,$63,$63
  .byte $64,$64,$65,$65,$66,$66,$66,$67,$67,$68,$68,$69,$69,$6A,$6A,$6A,$6B,$6B,$6C,$6C,$6D,$6D,$6E,$6E,$6E,$6F,$6F,$70,$70,$71,$71,$71
  .byte $72,$72,$73,$73,$74,$74,$75,$75,$75,$76,$76,$77,$77,$78,$78,$79,$79,$79,$7A,$7A,$7B,$7B,$7C,$7C,$7C,$7D,$7D,$7E,$7E,$7F,$7F,$80
  .byte $80,$81,$81,$82,$82,$83,$83,$84,$84,$85,$85,$86,$86,$87,$87,$88,$88,$89,$89,$8A,$8A,$8B,$8B,$8C,$8C,$8D,$8E,$8E,$8F,$8F,$90,$90
  .byte $91,$91,$92,$92,$93,$93,$94,$94,$95,$95,$96,$96,$97,$97,$98,$98,$99,$99,$9A,$9B,$9B,$9C,$9C,$9D,$9D,$9E,$9E,$9F,$9F,$A0,$A0,$A1
  .byte $A1,$A2,$A2,$A3,$A3,$A4,$A4,$A5,$A5,$A6,$A6,$A7,$A8,$A8,$A9,$A9,$AA,$AA,$AB,$AB,$AC,$AC,$AD,$AD,$AE,$AE,$AF,$AF,$B0,$B0,$B1,$B1
  .byte $B2,$B2,$B3,$B3,$B4,$B5,$B5,$B6,$B6,$B7,$B7,$B8,$B8,$B9,$B9,$BA,$BA,$BB,$BB,$BC,$BC,$BD,$BD,$BE,$BE,$BF,$BF,$C0,$C0,$C1,$C2,$C2
  .byte $3D,$3E,$3E,$3F,$40,$40,$41,$41,$42,$42,$43,$43,$44,$44,$45,$45,$46,$46,$47,$47,$48,$48,$49,$49,$4A,$4A,$4B,$4B,$4C,$4D,$4D,$4E
  .byte $4E,$4F,$4F,$50,$50,$51,$51,$52,$52,$53,$53,$54,$54,$55,$55,$56,$56,$57,$57,$58,$58,$59,$5A,$5A,$5B,$5B,$5C,$5C,$5D,$5D,$5E,$5E
  .byte $5F,$5F,$60,$60,$61,$61,$62,$62,$63,$63,$64,$64,$65,$65,$66,$67,$67,$68,$68,$69,$69,$6A,$6A,$6B,$6B,$6C,$6C,$6D,$6D,$6E,$6E,$6F
  .byte $6F,$70,$70,$71,$71,$72,$72,$73,$74,$74,$75,$75,$76,$76,$77,$77,$78,$78,$79,$79,$7A,$7A,$7B,$7B,$7C,$7C,$7D,$7D,$7E,$7E,$7F,$7F
  .byte $80,$81,$81,$82,$82,$83,$84,$84,$85,$85,$86,$87,$87,$88,$88,$89,$8A,$8A,$8B,$8B,$8C,$8D,$8D,$8E,$8E,$8F,$90,$90,$91,$91,$92,$93
  .byte $93,$94,$94,$95,$96,$96,$97,$97,$98,$99,$99,$9A,$9A,$9B,$9C,$9C,$9D,$9D,$9E,$9F,$9F,$A0,$A0,$A1,$A2,$A2,$A3,$A3,$A4,$A5,$A5,$A6
  .byte $A6,$A7,$A8,$A8,$A9,$A9,$AA,$AB,$AB,$AC,$AC,$AD,$AE,$AE,$AF,$AF,$B0,$B1,$B1,$B2,$B2,$B3,$B4,$B4,$B5,$B5,$B6,$B7,$B7,$B8,$B8,$B9
  .byte $BA,$BA,$BB,$BB,$BC,$BD,$BD,$BE,$BE,$BF,$C0,$C0,$C1,$C1,$C2,$C3,$C3,$C4,$C4,$C5,$C6,$C6,$C7,$C7,$C8,$C9,$C9,$CA,$CA,$CB,$CC,$CC
  .byte $33,$34,$34,$35,$36,$36,$37,$37,$38,$39,$39,$3A,$3A,$3B,$3C,$3C,$3D,$3D,$3E,$3F,$3F,$40,$40,$41,$42,$42,$43,$43,$44,$45,$45,$46
  .byte $46,$47,$48,$48,$49,$49,$4A,$4B,$4B,$4C,$4C,$4D,$4E,$4E,$4F,$4F,$50,$51,$51,$52,$52,$53,$54,$54,$55,$55,$56,$57,$57,$58,$58,$59
  .byte $5A,$5A,$5B,$5B,$5C,$5D,$5D,$5E,$5E,$5F,$60,$60,$61,$61,$62,$63,$63,$64,$64,$65,$66,$66,$67,$67,$68,$69,$69,$6A,$6A,$6B,$6C,$6C
  .byte $6D,$6D,$6E,$6F,$6F,$70,$70,$71,$72,$72,$73,$73,$74,$75,$75,$76,$76,$77,$78,$78,$79,$79,$7A,$7B,$7B,$7C,$7C,$7D,$7E,$7E,$7F,$7F
  .byte $80,$81,$81,$82,$83,$83,$84,$85,$85,$86,$87,$87,$88,$89,$8A,$8A,$8B,$8C,$8C,$8D,$8E,$8E,$8F,$90,$90,$91,$92,$92,$93,$94,$94,$95
  .byte $96,$96,$97,$98,$98,$99,$9A,$9B,$9B,$9C,$9D,$9D,$9E,$9F,$9F,$A0,$A1,$A1,$A2,$A3,$A3,$A4,$A5,$A5,$A6,$A7,$A7,$A8,$A9,$A9,$AA,$AB
  .byte $AC,$AC,$AD,$AE,$AE,$AF,$B0,$B0,$B1,$B2,$B2,$B3,$B4,$B4,$B5,$B6,$B6,$B7,$B8,$B8,$B9,$BA,$BA,$BB,$BC,$BD,$BD,$BE,$BF,$BF,$C0,$C1
  .byte $C1,$C2,$C3,$C3,$C4,$C5,$C5,$C6,$C7,$C7,$C8,$C9,$C9,$CA,$CB,$CB,$CC,$CD,$CE,$CE,$CF,$D0,$D0,$D1,$D2,$D2,$D3,$D4,$D4,$D5,$D6,$D6
  .byte $29,$2A,$2A,$2B,$2C,$2C,$2D,$2E,$2E,$2F,$30,$30,$31,$32,$32,$33,$34,$35,$35,$36,$37,$37,$38,$39,$39,$3A,$3B,$3B,$3C,$3D,$3D,$3E
  .byte $3F,$3F,$40,$41,$41,$42,$43,$43,$44,$45,$46,$46,$47,$48,$48,$49,$4A,$4A,$4B,$4C,$4C,$4D,$4E,$4E,$4F,$50,$50,$51,$52,$52,$53,$54
  .byte $54,$55,$56,$57,$57,$58,$59,$59,$5A,$5B,$5B,$5C,$5D,$5D,$5E,$5F,$5F,$60,$61,$61,$62,$63,$63,$64,$65,$65,$66,$67,$68,$68,$69,$6A
  .byte $6A,$6B,$6C,$6C,$6D,$6E,$6E,$6F,$70,$70,$71,$72,$72,$73,$74,$74,$75,$76,$76,$77,$78,$79,$79,$7A,$7B,$7B,$7C,$7D,$7D,$7E,$7F,$7F
  .byte $80,$81,$82,$82,$83,$84,$85,$85,$86,$87,$88,$88,$89,$8A,$8B,$8B,$8C,$8D,$8E,$8E,$8F,$90,$91,$91,$92,$93,$94,$95,$95,$96,$97,$98
  .byte $98,$99,$9A,$9B,$9B,$9C,$9D,$9E,$9E,$9F,$A0,$A1,$A1,$A2,$A3,$A4,$A4,$A5,$A6,$A7,$A8,$A8,$A9,$AA,$AB,$AB,$AC,$AD,$AE,$AE,$AF,$B0
  .byte $B1,$B1,$B2,$B3,$B4,$B4,$B5,$B6,$B7,$B7,$B8,$B9,$BA,$BB,$BB,$BC,$BD,$BE,$BE,$BF,$C0,$C1,$C1,$C2,$C3,$C4,$C4,$C5,$C6,$C7,$C7,$C8
  .byte $C9,$CA,$CA,$CB,$CC,$CD,$CE,$CE,$CF,$D0,$D1,$D1,$D2,$D3,$D4,$D4,$D5,$D6,$D7,$D7,$D8,$D9,$DA,$DA,$DB,$DC,$DD,$DD,$DE,$DF,$E0,$E1
  .byte $1F,$1F,$20,$21,$22,$23,$23,$24,$25,$26,$26,$27,$28,$29,$29,$2A,$2B,$2C,$2C,$2D,$2E,$2F,$2F,$30,$31,$32,$32,$33,$34,$35,$36,$36
  .byte $37,$38,$39,$39,$3A,$3B,$3C,$3C,$3D,$3E,$3F,$3F,$40,$41,$42,$42,$43,$44,$45,$45,$46,$47,$48,$49,$49,$4A,$4B,$4C,$4C,$4D,$4E,$4F
  .byte $4F,$50,$51,$52,$52,$53,$54,$55,$55,$56,$57,$58,$58,$59,$5A,$5B,$5C,$5C,$5D,$5E,$5F,$5F,$60,$61,$62,$62,$63,$64,$65,$65,$66,$67
  .byte $68,$68,$69,$6A,$6B,$6B,$6C,$6D,$6E,$6F,$6F,$70,$71,$72,$72,$73,$74,$75,$75,$76,$77,$78,$78,$79,$7A,$7B,$7B,$7C,$7D,$7E,$7E,$7F
  .byte $80,$81,$82,$83,$83,$84,$85,$86,$87,$88,$88,$89,$8A,$8B,$8C,$8D,$8D,$8E,$8F,$90,$91,$92,$92,$93,$94,$95,$96,$97,$98,$98,$99,$9A
  .byte $9B,$9C,$9D,$9D,$9E,$9F,$A0,$A1,$A2,$A2,$A3,$A4,$A5,$A6,$A7,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AD,$AE,$AF,$B0,$B1,$B2,$B2,$B3,$B4,$B5
  .byte $B6,$B7,$B7,$B8,$B9,$BA,$BB,$BC,$BC,$BD,$BE,$BF,$C0,$C1,$C2,$C2,$C3,$C4,$C5,$C6,$C7,$C7,$C8,$C9,$CA,$CB,$CC,$CC,$CD,$CE,$CF,$D0
  .byte $D1,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D7,$D8,$D9,$DA,$DB,$DC,$DC,$DD,$DE,$DF,$E0,$E1,$E1,$E2,$E3,$E4,$E5,$E6,$E6,$E7,$E8,$E9,$EA,$EB
  .byte $14,$15,$16,$17,$18,$19,$1A,$1A,$1B,$1C,$1D,$1E,$1F,$1F,$20,$21,$22,$23,$24,$24,$25,$26,$27,$28,$29,$29,$2A,$2B,$2C,$2D,$2E,$2F
  .byte $2F,$30,$31,$32,$33,$34,$34,$35,$36,$37,$38,$39,$39,$3A,$3B,$3C,$3D,$3E,$3E,$3F,$40,$41,$42,$43,$44,$44,$45,$46,$47,$48,$49,$49
  .byte $4A,$4B,$4C,$4D,$4E,$4E,$4F,$50,$51,$52,$53,$53,$54,$55,$56,$57,$58,$59,$59,$5A,$5B,$5C,$5D,$5E,$5E,$5F,$60,$61,$62,$63,$63,$64
  .byte $65,$66,$67,$68,$68,$69,$6A,$6B,$6C,$6D,$6E,$6E,$6F,$70,$71,$72,$73,$73,$74,$75,$76,$77,$78,$78,$79,$7A,$7B,$7C,$7D,$7D,$7E,$7F
  .byte $80,$81,$82,$83,$84,$85,$86,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D
  .byte $9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B4,$B5,$B6,$B7,$B8,$B9,$BA
  .byte $BB,$BC,$BD,$BE,$BF,$BF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D6,$D7
  .byte $D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,$E0,$E1,$E2,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$ED,$EE,$EF,$F0,$F1,$F2,$F3,$F4,$F5
  .byte $0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1E,$1F,$20,$21,$22,$23,$24,$25,$26,$27
  .byte $28,$29,$2A,$2A,$2B,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34,$35,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F,$40,$41,$41,$42,$43,$44
  .byte $45,$46,$47,$48,$49,$4A,$4B,$4C,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F,$60,$61,$62
  .byte $63,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7A,$7B,$7C,$7D,$7E,$7F
  .byte $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F
  .byte $A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF
  .byte $C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF
  .byte $E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF,$F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F
  .byte $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F
  .byte $40,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$5B,$5C,$5D,$5E,$5F
  .byte $60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F
CELLLO:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$06,$06,$06,$06,$06,$06,$06,$06,$07,$07,$07,$07,$07,$07,$07,$07
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$09,$09,$09,$09,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11,$11,$11,$11,$11,$11,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$13,$13,$13,$13
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17,$17
  .byte $18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19,$19,$19,$19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1D,$1D,$1D,$1D,$1D,$1D,$1D,$1D,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F
PH4:
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
  .byte $00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C,$00,$04,$08,$0C,$10,$14,$18,$1C
SLOPE_L:
  .byte $01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01
SLOPE_R:
  .byte $01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
DYA:
  .byte $58,$57,$55,$54,$53,$51,$50,$4F,$4E,$4D,$4B,$4A,$49,$48,$47,$46,$45,$44,$44,$43,$42,$41,$40,$3F,$3F,$3E,$3D,$3C,$3C,$3B,$3A,$3A
  .byte $39,$38,$38,$37,$36,$36,$35,$35,$34,$33,$33,$32,$32,$31,$31,$30,$30,$2F,$2F,$2E,$2E,$2D,$2D,$2D,$2C,$2C,$2B,$2B,$2B,$2A,$2A,$29
  .byte $29,$29,$28,$28,$28,$27,$27,$26,$26,$26,$25,$25,$25,$25,$24,$24,$24,$23,$23,$23,$22,$22,$22,$22,$21,$21,$21,$21,$20,$20,$20,$20
  .byte $1F,$1F,$1F,$1F,$1E,$1E,$1E,$1E,$1D,$1D,$1D,$1D,$1D,$1C,$1C,$1C,$1C,$1C,$1B,$1B,$1B,$1B,$1B,$1A,$1A,$1A,$1A,$1A,$1A,$19,$19,$19
  .byte $19,$19,$19,$18,$18,$18,$18,$18,$18,$17,$17,$17,$17,$17,$17,$17,$16,$16,$16,$16,$16,$16,$16,$15,$15,$15,$15,$15,$15,$15,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$13,$13,$13,$13,$13,$13,$13,$13,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$10,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $0E,$0E,$0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
SZA:
  .byte $07,$07,$07,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
DYB:
  .byte $58,$53,$4E,$49,$45,$42,$3F,$3C,$39,$36,$34,$32,$30,$2E,$2C,$2B,$29,$28,$26,$25,$24,$22,$21,$20,$1F,$1E,$1D,$1D,$1C,$1B,$1A,$1A
  .byte $19,$18,$18,$17,$16,$16,$15,$15,$14,$14,$13,$13,$12,$12,$12,$11,$11,$10,$10,$10,$0F,$0F,$0F,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C
  .byte $0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$07,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SZB:
  .byte $07,$06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
CELLHI:
  .byte $00,$20,$40,$60,$80,$A0,$C0,$E0
SL32:
  .byte $00,$20,$40
TLT:
  .byte $08,$00,$00,$00,$09,$00,$00,$00,$0A,$00,$00,$00,$0B,$00,$00,$00,$0C,$00,$00,$00,$0D,$00,$00,$00,$0E,$00,$00,$00,$0F,$00,$00,$00
  .byte $10,$11,$00,$00,$12,$13,$00,$00,$14,$15,$00,$00,$16,$17,$00,$00,$18,$19,$00,$00,$1A,$1B,$00,$00,$1C,$1D,$00,$00,$1E,$1F,$00,$00
  .byte $20,$21,$22,$00,$23,$24,$25,$00,$26,$27,$28,$00,$29,$2A,$2B,$00,$2C,$2D,$2E,$00,$2F,$30,$31,$00,$32,$33,$34,$00,$35,$36,$37,$00
  .byte $80,$00,$00,$00,$81,$00,$00,$00,$82,$00,$00,$00,$83,$00,$00,$00,$84,$00,$00,$00,$85,$00,$00,$00,$86,$00,$00,$00,$87,$00,$00,$00
  .byte $88,$89,$00,$00,$8A,$8B,$00,$00,$8C,$8D,$00,$00,$8E,$8F,$00,$00,$90,$91,$00,$00,$92,$93,$00,$00,$94,$95,$00,$00,$96,$97,$00,$00
  .byte $98,$99,$9A,$00,$9B,$9C,$9D,$00,$9E,$9F,$A0,$00,$A1,$A2,$A3,$00,$A4,$A5,$A6,$00,$A7,$A8,$A9,$00,$AA,$AB,$AC,$00,$AD,$AE,$AF,$00
TRT:
  .byte $38,$00,$00,$00,$39,$00,$00,$00,$3A,$00,$00,$00,$3B,$00,$00,$00,$3C,$00,$00,$00,$3D,$00,$00,$00,$3E,$00,$00,$00,$3F,$00,$00,$00
  .byte $40,$41,$00,$00,$42,$43,$00,$00,$44,$45,$00,$00,$46,$47,$00,$00,$48,$49,$00,$00,$4A,$4B,$00,$00,$4C,$4D,$00,$00,$4E,$4F,$00,$00
  .byte $50,$51,$52,$00,$53,$54,$55,$00,$56,$57,$58,$00,$59,$5A,$5B,$00,$5C,$5D,$5E,$00,$5F,$60,$61,$00,$62,$63,$64,$00,$65,$66,$67,$00
  .byte $B0,$00,$00,$00,$B1,$00,$00,$00,$B2,$00,$00,$00,$B3,$00,$00,$00,$B4,$00,$00,$00,$B5,$00,$00,$00,$B6,$00,$00,$00,$B7,$00,$00,$00
  .byte $B8,$B9,$00,$00,$BA,$BB,$00,$00,$BC,$BD,$00,$00,$BE,$BF,$00,$00,$C0,$C1,$00,$00,$C2,$C3,$00,$00,$C4,$C5,$00,$00,$C6,$C7,$00,$00
  .byte $C8,$C9,$CA,$00,$CB,$CC,$CD,$00,$CE,$CF,$D0,$00,$D1,$D2,$D3,$00,$D4,$D5,$D6,$00,$D7,$D8,$D9,$00,$DA,$DB,$DC,$00,$DD,$DE,$DF,$00
ZT:
  .byte $75,$40,$29,$1C,$14,$0F,$0B,$08,$05,$03,$01,$00
LW:
  .byte $08,$10,$18,$20,$28,$30,$38,$40,$48,$50,$58,$60
SEQ16:
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F
BDTU:
  .byte $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F
  .byte $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF
  .byte $A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9,$AA,$AB,$AC,$AD,$AE,$AF
  .byte $C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF
  .byte $C0,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF,$E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF
  .byte $E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF,$E0,$E1,$E2,$E3,$E4,$E5,$E6,$E7,$E8,$E9,$EA,$EB,$EC,$ED,$EE,$EF
BDTL:
  .byte $90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F,$90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F
  .byte $90,$91,$92,$93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF
  .byte $B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF,$B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$BA,$BB,$BC,$BD,$BE,$BF
  .byte $D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,$D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF
  .byte $D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$DB,$DC,$DD,$DE,$DF,$F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF
  .byte $F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF,$F0,$F1,$F2,$F3,$F4,$F5,$F6,$F7,$F8,$F9,$FA,$FB,$FC,$FD,$FE,$FF
M48X:
  .byte $00,$00,$30,$00,$60,$00,$90
MTN_U:
  LDA BDTU+0,Y
  STA VDATA
  LDA BDTU+1,Y
  STA VDATA
  LDA BDTU+2,Y
  STA VDATA
  LDA BDTU+3,Y
  STA VDATA
  LDA BDTU+4,Y
  STA VDATA
  LDA BDTU+5,Y
  STA VDATA
  LDA BDTU+6,Y
  STA VDATA
  LDA BDTU+7,Y
  STA VDATA
  LDA BDTU+8,Y
  STA VDATA
  LDA BDTU+9,Y
  STA VDATA
  LDA BDTU+10,Y
  STA VDATA
  LDA BDTU+11,Y
  STA VDATA
  LDA BDTU+12,Y
  STA VDATA
  LDA BDTU+13,Y
  STA VDATA
  LDA BDTU+14,Y
  STA VDATA
  LDA BDTU+15,Y
  STA VDATA
  LDA BDTU+16,Y
  STA VDATA
  LDA BDTU+17,Y
  STA VDATA
  LDA BDTU+18,Y
  STA VDATA
  LDA BDTU+19,Y
  STA VDATA
  LDA BDTU+20,Y
  STA VDATA
  LDA BDTU+21,Y
  STA VDATA
  LDA BDTU+22,Y
  STA VDATA
  LDA BDTU+23,Y
  STA VDATA
  LDA BDTU+24,Y
  STA VDATA
  LDA BDTU+25,Y
  STA VDATA
  LDA BDTU+26,Y
  STA VDATA
  LDA BDTU+27,Y
  STA VDATA
  LDA BDTU+28,Y
  STA VDATA
  LDA BDTU+29,Y
  STA VDATA
  LDA BDTU+30,Y
  STA VDATA
  LDA BDTU+31,Y
  STA VDATA
  RTS
MTN_L:
  LDA BDTL+0,Y
  STA VDATA
  LDA BDTL+1,Y
  STA VDATA
  LDA BDTL+2,Y
  STA VDATA
  LDA BDTL+3,Y
  STA VDATA
  LDA BDTL+4,Y
  STA VDATA
  LDA BDTL+5,Y
  STA VDATA
  LDA BDTL+6,Y
  STA VDATA
  LDA BDTL+7,Y
  STA VDATA
  LDA BDTL+8,Y
  STA VDATA
  LDA BDTL+9,Y
  STA VDATA
  LDA BDTL+10,Y
  STA VDATA
  LDA BDTL+11,Y
  STA VDATA
  LDA BDTL+12,Y
  STA VDATA
  LDA BDTL+13,Y
  STA VDATA
  LDA BDTL+14,Y
  STA VDATA
  LDA BDTL+15,Y
  STA VDATA
  LDA BDTL+16,Y
  STA VDATA
  LDA BDTL+17,Y
  STA VDATA
  LDA BDTL+18,Y
  STA VDATA
  LDA BDTL+19,Y
  STA VDATA
  LDA BDTL+20,Y
  STA VDATA
  LDA BDTL+21,Y
  STA VDATA
  LDA BDTL+22,Y
  STA VDATA
  LDA BDTL+23,Y
  STA VDATA
  LDA BDTL+24,Y
  STA VDATA
  LDA BDTL+25,Y
  STA VDATA
  LDA BDTL+26,Y
  STA VDATA
  LDA BDTL+27,Y
  STA VDATA
  LDA BDTL+28,Y
  STA VDATA
  LDA BDTL+29,Y
  STA VDATA
  LDA BDTL+30,Y
  STA VDATA
  LDA BDTL+31,Y
  STA VDATA
  RTS
KMH_H:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
KMH_L:
  .byte $00,$03,$06,$08,$11,$14,$17,$20,$22,$25,$28,$31,$34,$37,$39,$42,$45,$48,$51,$53,$56,$59,$62,$65,$67,$70,$73,$76,$79,$82,$84,$87
  .byte $90,$93,$96,$98,$01,$04,$07,$10,$12,$15,$18,$21,$24,$27,$29,$32,$35,$38,$41,$43,$46,$49,$52,$55,$57,$60,$63,$66,$69,$72,$74,$77
  .byte $80,$83,$86,$88,$91,$94,$97,$00,$02,$05,$08,$11,$14,$17,$19,$22,$25,$28,$31,$33,$36,$39,$42,$45,$47,$50,$53,$56,$59,$62,$64,$67
  .byte $70,$73,$76,$78,$81,$84,$87,$90,$92,$95,$98,$01,$04,$07,$09,$12,$15,$18,$21,$23,$26,$29,$32,$35,$37,$40,$43,$46,$49,$52,$54,$57
ENGL_LO:
  .byte $6D,$1D,$D5,$93,$57,$20,$ED,$BD,$92,$69,$43,$1F,$FE,$DF,$C1,$A6,$8B,$73,$5B,$45,$30,$1C,$09,$F7,$E5,$D5,$C5,$B6,$A7,$99,$8C,$7F
  .byte $73,$67,$5B,$50,$46,$3B,$31,$28,$1F,$16,$0D,$05,$FC,$F5,$ED,$E6,$DE,$D7,$D1,$CA,$C4,$BE,$B7,$B2,$AC,$A6,$A1,$9C,$96,$91,$8C,$88
  .byte $83,$7E,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C
  .byte $7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C
ENGL_HI:
  .byte $06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
ENGH_LO:
  .byte $6D,$40,$15,$ED,$C7,$A2,$7F,$5E,$3F,$21,$04,$E8,$CE,$B5,$9C,$85,$6F,$59,$44,$30,$1D,$0A,$F8,$E7,$D6,$C6,$B6,$A7,$98,$8A,$7C,$6F
  .byte $62,$55,$49,$3D,$32,$26,$1B,$11,$06,$FC,$F2,$E9,$DF,$D6,$CD,$C5,$BC,$B4,$AC,$A4,$9C,$95,$8D,$86,$7F,$78,$71,$6B,$64,$5E,$58,$52
  .byte $4C,$46,$40,$3A,$35,$30,$2A,$25,$20,$1B,$16,$11,$0C,$08,$03,$FF,$FA,$F6,$F2,$EE,$E9,$E5,$E1,$DD,$DA,$D6,$D2,$CE,$CB,$C7,$C4,$C0
  .byte $BD,$B9,$B6,$B3,$B0,$AC,$A9,$A6,$A3,$A0,$9D,$9A,$98,$95,$92,$8F,$8D,$8A,$87,$85,$82,$80,$7D,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7C
ENGH_HI:
  .byte $06,$06,$06,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
RD_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FC,$F0,$C0,$FF,$FC,$F0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FE,$F8,$E0
  .byte $FF,$FE,$F8,$E0,$80,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$F0,$FF,$FF,$FC,$F0,$C0,$00,$00,$00
  .byte $C0,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$F8,$FF,$FF,$FE,$F8,$E0,$80,$00,$00,$E0,$80,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$F0,$C0,$00,$00,$F0,$C0,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE
  .byte $FF,$FF,$FF,$FE,$F8,$E0,$80,$00,$F8,$E0,$80,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$F0,$C0,$00
  .byte $FC,$F0,$C0,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F
  .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$07,$07,$07,$07,$07,$07,$07,$07,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $FF,$7F,$3F,$1F,$0F,$07,$03,$01,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$0F,$07,$03,$01,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $3F,$1F,$0F,$07,$03,$01,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$0F,$07,$03,$01,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F
  .byte $0F,$07,$03,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$07,$03,$01,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$0F
  .byte $03,$01,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$7F,$3F,$1F,$0F,$07,$01,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$7F,$3F,$1F,$0F,$07,$03
  .byte $FF,$3F,$0F,$03,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$3F,$0F,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$7F,$1F,$07,$01,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$3F,$0F,$03,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$3F,$0F,$03,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$1F,$07,$01,$00,$00,$00,$00,$00,$FF,$FF,$FF,$7F,$1F,$07,$01,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F
  .byte $0F,$03,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$3F,$0F,$03,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$3F,$07,$01,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$7F,$1F,$07,$01,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$03,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$3F,$0F,$03,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$3F,$0F,$01,$00,$00,$00,$00,$00,$00,$00,$FF,$7F,$1F,$07,$01,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$07
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$60,$60,$60,$60,$60,$60,$60,$60,$30,$30,$30,$30,$30,$30,$30,$30,$18,$18,$18,$18,$18,$18,$18,$18
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$06,$06,$06,$06,$06,$06,$06,$06,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80
RD_PATB:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$80,$80,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0,$E0,$C0,$80,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FC,$F0,$C0,$FF,$FC,$F0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FE,$F8,$E0
  .byte $FF,$FE,$F8,$E0,$80,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$F0,$FF,$FF,$FC,$F0,$C0,$00,$00,$00
  .byte $C0,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$F8,$FF,$FF,$FE,$F8,$E0,$80,$00,$00,$E0,$80,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$FF,$FF,$FF,$FC,$F0,$C0,$00,$00,$F0,$C0,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE
  .byte $FF,$FF,$FF,$FE,$F8,$E0,$80,$00,$F8,$E0,$80,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$F0,$C0,$00
  .byte $FC,$F0,$C0,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$F8,$E0,$80,$FE,$F8,$E0,$80,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F
  .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$07,$07,$07,$07,$07,$07,$07,$07,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $FF,$7F,$3F,$1F,$0F,$07,$03,$01,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$0F,$07,$03,$01,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $3F,$1F,$0F,$07,$03,$01,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$0F,$07,$03,$01,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$3F
  .byte $0F,$07,$03,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$07,$03,$01,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$7F,$3F,$1F,$0F
  .byte $03,$01,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$7F,$3F,$1F,$0F,$07,$01,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$7F,$3F,$1F,$0F,$07,$03
  .byte $FF,$3F,$0F,$03,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$3F,$0F,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$07,$01,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$7F,$1F,$07,$01,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$3F,$0F,$03,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$3F,$0F,$03,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$1F,$07,$01,$00,$00,$00,$00,$00,$FF,$FF,$FF,$7F,$1F,$07,$01,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F
  .byte $0F,$03,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$3F,$0F,$03,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$3F,$07,$01,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$7F,$1F,$07,$01,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$03,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$3F,$0F,$03,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$3F,$0F,$01,$00,$00,$00,$00,$00,$00,$00,$FF,$7F,$1F,$07,$01,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$7F,$1F,$07
BD0:
  .byte $00,$00,$00,$00,$01,$01,$03,$03,$00,$00,$00,$00,$C0,$C0,$E0,$FC,$00,$00,$00,$00,$1C,$1C,$3E,$3E,$00,$00,$00,$00,$00,$00,$03,$03
  .byte $00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$71,$71,$FB
  .byte $00,$00,$00,$00,$00,$C0,$C7,$FF,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$C0
  .byte $00,$00,$00,$00,$00,$00,$E0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$07,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$BE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$07,$07,$07,$87,$FF,$FF,$FF,$FF
  .byte $C0,$C0,$C1,$CF,$FF,$FF,$FF,$FF,$00,$1C,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$C0,$F8,$FF,$FF,$FF,$FF,$FB,$FB,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F8,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$01,$03,$C3,$F3,$FF,$FF,$FF,$FF,$C1,$E1,$E1,$E7,$FF,$FF,$FF,$FF
  .byte $F1,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$C0,$FC,$FF,$FF,$FF,$FF,$FF,$FF,$1C,$3E,$BE,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF
BD1:
  .byte $00,$00,$00,$00,$03,$03,$03,$03,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$F0,$F0,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $00,$00,$F8,$F8,$F8,$F8,$FC,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3F,$3F,$3F,$00,$00,$00,$00,$00,$E0,$E0,$E0
  .byte $07,$07,$0F,$0F,$1F,$1F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F8,$F8,$FC,$FC,$FE,$FE,$FF,$FF,$00,$00,$00,$01,$01,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$03,$03,$07,$87,$87,$C7,$FF,$FF
  .byte $FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$01,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$C0,$C0,$C0,$C0,$E1,$FF,$FF,$3F,$7F,$7F,$FF,$FF,$FF,$FF,$FF,$E0,$F0,$F0,$F8,$F8,$FC,$FF,$FF
BD2:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$FF,$7B,$FF,$FF,$00,$00,$01,$07,$FF,$6F,$FF,$FF,$3E,$FF,$FF,$FF,$FF,$6D,$FF,$FF,$00,$80,$C7,$FF,$FF,$ED,$FF,$FF
  .byte $00,$00,$00,$C0,$FF,$BD,$FF,$FF,$00,$00,$00,$00,$FF,$B7,$FF,$FF,$00,$00,$00,$00,$FF,$B6,$FF,$FF,$00,$00,$00,$00,$FF,$F6,$FF,$FF
  .byte $00,$00,$00,$01,$FF,$DE,$FF,$FF,$00,$1C,$7F,$FF,$FF,$DB,$FF,$FF,$00,$00,$00,$C0,$FF,$DB,$FF,$FF,$00,$00,$00,$00,$FF,$7B,$FF,$FF
  .byte $00,$00,$00,$00,$FF,$6F,$FF,$FF,$00,$00,$00,$00,$FF,$6D,$FF,$FF,$00,$00,$00,$00,$FF,$ED,$FF,$FF,$00,$00,$00,$00,$FF,$BD,$FF,$FF
BD3:
  .byte $00,$00,$00,$00,$00,$00,$01,$07,$00,$00,$00,$20,$70,$F8,$FC,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$01,$03,$0F,$00,$08,$1C,$7F,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$80,$C0,$E0,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$1C,$3E,$7F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$1C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $0F,$1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$80,$C0,$E0,$F0,$F8,$FC,$FE,$FF,$00,$00,$00,$01,$03,$07,$07,$FF
  .byte $70,$70,$F8,$FD,$FF,$FF,$FF,$FF,$1F,$3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$C0,$E0,$F0,$F8,$FF,$00,$10,$10,$38,$7C,$7C,$FE,$FF,$00,$01,$03,$07,$0F,$1F,$3F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $80,$C0,$E0,$F0,$F8,$FC,$FE,$FF,$00,$00,$00,$00,$01,$03,$07,$FF,$3E,$3E,$7F,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$80,$C0,$E1,$F3,$FF
BD4:
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$C0,$C0,$C0,$C0,$C0,$C0,$FF,$00,$00,$00,$00,$00,$07,$07,$FF,$00,$00,$00,$00,$00,$FE,$FE,$FE
  .byte $00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$0F,$FF,$FF,$00,$1F,$1F,$1F,$1F,$FF,$FF,$FF,$00,$FC,$FC,$FC,$FC,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$FC,$FC,$FC,$00,$00,$00,$0F,$0F,$0F,$0F,$0F,$00,$00,$00,$E0,$E0,$E0,$E0,$FF,$00,$00,$00,$00,$0F,$0F,$0F,$EF
  .byte $00,$00,$00,$00,$FF,$FF,$FF,$FF,$00,$00,$00,$0F,$EF,$EF,$EF,$EF,$00,$00,$00,$FE,$FE,$FE,$FE,$FE,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$09,$00,$08,$00,$00,$00,$48,$00,$00,$00,$04,$00,$20,$00,$00,$00,$90,$00,$10,$00,$10,$00,$90,$00,$01,$00,$01,$00,$49,$00,$41
  .byte $00,$00,$00,$24,$00,$00,$00,$00,$00,$02,$00,$92,$00,$82,$00,$02,$00,$49,$00,$01,$00,$41,$00,$49,$00,$00,$00,$20,$00,$24,$00,$24
  .byte $00,$80,$00,$92,$00,$12,$00,$82,$00,$41,$00,$49,$00,$49,$00,$09,$00,$24,$00,$04,$00,$00,$00,$24,$00,$12,$00,$12,$00,$92,$00,$02
  .byte $00,$09,$00,$09,$00,$00,$00,$08,$00,$04,$00,$24,$00,$24,$00,$20,$00,$92,$00,$90,$00,$10,$00,$12,$00,$48,$00,$09,$00,$00,$00,$49
BD_LO: .byte <BD0,<BD1,<BD2,<BD3,<BD4
BD_HI: .byte >BD0,>BD1,>BD2,>BD3,>BD4
BD_COL:
  .byte $C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C5
  .byte $67,$67,$67,$67,$67,$67,$67,$67,$67,$A7,$A7,$A7,$A7,$A7,$A7,$A7
  .byte $D9,$D9,$D9,$D9,$D9,$D9,$D9,$D9,$D9,$D9,$D9,$D9,$49,$49,$49,$49
  .byte $F5,$F5,$F5,$F5,$F5,$F5,$45,$45,$45,$45,$45,$45,$45,$45,$45,$45
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4
STG_SKY:
  .byte $15,$17,$19,$15,$11
STG_G0:
  .byte $3E,$BE,$2E,$FE,$4E
STG_G1:
  .byte $2E,$AE,$CE,$7E,$1E
STG_BD:
  .byte $00,$01,$02,$03,$04
TRK0:
  .byte 60, $00, 0
  .byte 50, $23, 0
  .byte 40, $00, 0
  .byte 60, $D3, 0
  .byte 30, $00, 1
  .byte 30, $00, 0
  .byte 70, $37, 0
  .byte 50, $00, 0
  .byte 40, $00, 2
  .byte 30, $00, 1
  .byte 60, $C4, 0
  .byte 40, $1E, 0
  .byte 50, $E2, 0
  .byte 70, $00, 0
  .byte 60, $32, 0
  .byte 50, $00, 0
  .byte 0
TRK1:
  .byte 80, $00, 0
  .byte 60, $C9, 0
  .byte 30, $00, 1
  .byte 30, $00, 2
  .byte 30, $00, 1
  .byte 70, $00, 0
  .byte 60, $46, 0
  .byte 40, $00, 0
  .byte 50, $BA, 0
  .byte 80, $00, 0
  .byte 40, $00, 2
  .byte 40, $28, 0
  .byte 60, $D8, 0
  .byte 50, $00, 1
  .byte 60, $00, 0
  .byte 0
TRK2:
  .byte 80, $00, 0
  .byte 40, $46, 0
  .byte 40, $BA, 0
  .byte 40, $4B, 0
  .byte 60, $00, 0
  .byte 50, $B0, 0
  .byte 40, $3C, 0
  .byte 30, $00, 1
  .byte 50, $B5, 0
  .byte 40, $00, 0
  .byte 60, $55, 0
  .byte 40, $00, 0
  .byte 50, $C4, 0
  .byte 50, $3C, 0
  .byte 80, $00, 0
  .byte 0
TRK3:
  .byte 80, $00, 0
  .byte 50, $5A, 0
  .byte 60, $00, 1
  .byte 60, $A1, 0
  .byte 40, $00, 2
  .byte 50, $64, 0
  .byte 40, $00, 0
  .byte 50, $A6, 0
  .byte 30, $00, 1
  .byte 40, $00, 2
  .byte 60, $64, 0
  .byte 40, $CE, 0
  .byte 50, $9C, 0
  .byte 100, $00, 0
  .byte 0
TRK4:
  .byte 80, $00, 0
  .byte 30, $AB, 0
  .byte 30, $55, 0
  .byte 60, $00, 0
  .byte 30, $00, 2
  .byte 50, $5F, 0
  .byte 30, $A1, 0
  .byte 40, $00, 1
  .byte 60, $A6, 0
  .byte 40, $00, 0
  .byte 30, $5A, 0
  .byte 30, $A6, 0
  .byte 40, $00, 2
  .byte 60, $46, 0
  .byte 100, $00, 0
  .byte 0
TRK_LO: .byte <TRK0,<TRK1,<TRK2,<TRK3,<TRK4
TRK_HI: .byte >TRK0,>TRK1,>TRK2,>TRK3,>TRK4
SPRITES:
  .byte $00,$00,$00,$00,$01,$03,$0F,$3F,$7F,$FF,$FF,$FF,$FF,$00,$00,$00,$3F,$7F,$E0,$C0,$C0,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00
  .byte $FC,$FE,$07,$03,$03,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$F0,$FC,$FE,$FF,$FF,$FF,$FF,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7E,$7E,$7E,$00,$00,$1F,$3F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$F8,$FC,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7E,$7E,$7E
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$07,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$E0,$F0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$07,$0F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F0,$F8,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$0C,$1F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$18,$F8,$FC,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$0F,$18,$3F,$7F,$FF,$FF,$60,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$08,$F8,$FC,$FE,$FE,$0E
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$07,$0F,$0F,$00,$07,$00,$00,$00,$00,$07,$1F,$3F,$60,$E0,$FF,$FF,$FF,$FF,$FF,$00,$80
  .byte $00,$00,$00,$00,$F0,$FC,$FC,$03,$03,$FF,$FF,$FF,$FF,$FF,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$80,$C0,$E0,$E0,$00,$C0
  .byte $00,$00,$00,$01,$03,$07,$0F,$1F,$3F,$7F,$FF,$FF,$FF,$00,$7C,$7C,$1F,$7F,$FF,$80,$80,$80,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00
  .byte $F8,$FE,$FF,$01,$01,$01,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$C0,$E0,$F0,$F8,$FC,$FC,$FC,$00,$F8,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BIG_TOP:
  .byte $00,$FF,$FF,$03,$03,$03,$03,$03,$00,$FE,$FE,$80,$80,$80,$80,$80,$00,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$00,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $00,$FF,$FF,$E0,$E0,$E0,$E0,$FF,$00,$F0,$F0,$0E,$0E,$0E,$0E,$F0,$00,$FF,$FF,$E0,$E0,$E0,$E0,$FF,$00,$F0,$F0,$0E,$0E,$0E,$0E,$F0
  .byte $00,$1F,$1F,$E0,$E0,$E0,$E0,$E0,$00,$F0,$F0,$0E,$0E,$0E,$0E,$0E,$00,$E0,$E0,$E0,$E0,$E0,$E0,$FF,$00,$0E,$0E,$0E,$0E,$0E,$0E,$FE
  .byte $00,$1F,$1F,$03,$03,$03,$03,$03,$00,$F0,$F0,$80,$80,$80,$80,$80,$00,$FF,$FF,$00,$00,$00,$00,$03,$00,$FE,$FE,$0E,$0E,$70,$70,$80
  .byte $00,$E0,$E0,$E0,$E0,$FC,$FC,$E3,$00,$0E,$0E,$0E,$0E,$0E,$0E,$8E
BIG_BOT:
  .byte $03,$03,$03,$03,$03,$03,$03,$00,$80,$80,$80,$80,$80,$80,$80,$00,$E0,$E0,$E0,$E0,$E0,$1F,$1F,$00,$0E,$0E,$0E,$0E,$0E,$F0,$F0,$00
  .byte $FF,$E3,$E3,$E0,$E0,$E0,$E0,$00,$F0,$80,$80,$70,$70,$0E,$0E,$00,$FF,$E0,$E0,$E0,$E0,$FF,$FF,$00,$F0,$0E,$0E,$0E,$0E,$F0,$F0,$00
  .byte $E0,$E0,$E0,$E0,$E0,$1F,$1F,$00,$0E,$0E,$0E,$0E,$0E,$F0,$F0,$00,$FF,$E0,$E0,$E0,$E0,$E0,$E0,$00,$FE,$0E,$0E,$0E,$0E,$0E,$0E,$00
  .byte $03,$03,$03,$03,$03,$1F,$1F,$00,$80,$80,$80,$80,$80,$F0,$F0,$00,$03,$1C,$1C,$E0,$E0,$FF,$FF,$00,$80,$00,$00,$00,$00,$FE,$FE,$00
  .byte $E3,$E0,$E0,$E0,$E0,$E0,$E0,$00,$8E,$7E,$7E,$0E,$0E,$0E,$0E,$00
BIG_TOPC:
  .byte $B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
BIG_BOTC:
  .byte $A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81
  .byte $A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81
  .byte $A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81
  .byte $A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81
  .byte $A1,$91,$91,$91,$91,$81,$81,$81,$A1,$91,$91,$91,$91,$81,$81,$81
TXT_BIG:
  .byte 2,11,200,201,202,203,204,205,206,207,208,209,0
  .byte 3,11,220,221,222,223,224,225,226,227,228,229,0
  .byte 5,9,210,211,208,209,204,205,212,213,214,215,208,209,216,217,0
  .byte 6,9,230,231,228,229,224,225,232,233,234,235,228,229,236,237,0
  .byte $FF

; AY periods: index = MIDI note - 35
TP_LO:
  .byte $00,$BC,$86,$53,$24,$F6,$CC,$A4,$7E,$5A,$38,$18,$FA,$DE,$C3,$AA,$92,$7B,$66,$52,$3F,$2D,$1C,$0C,$FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9
  .byte $9F,$96,$8E,$86,$7F,$77,$71,$6A,$64,$5F,$59,$54,$50,$4B,$47,$43,$3F,$3C,$38,$35,$32,$2F,$2D,$2A,$28,$26,$24,$22,$20
TP_HI:
  .byte $00,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; tunes: song * 4 + track (melody, harmony, bass, drums)
SONGP_LO:
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3
SG0_0:
  .byte $29,$08,$2E,$08,$32,$08,$35,$10,$32,$08,$35,$18,$00,$08,$33,$08,$32,$08,$30,$08,$2E,$08,$30,$08,$32,$08,$30,$10,$29,$10,$2E,$28
  .byte $FF
SG0_1:
  .byte $26,$18,$00,$08,$26,$10,$29,$18,$00,$08,$27,$18,$00,$08,$29,$18,$27,$10,$26,$28,$FF
SG0_2:
  .byte $0A,$10,$11,$10,$0A,$10,$0E,$10,$0F,$10,$0C,$10,$11,$10,$05,$10,$0A,$28,$FF
SG0_3:
  .byte $01,$10,$03,$10,$02,$10,$03,$10,$01,$10,$03,$10,$02,$10,$03,$08,$03,$08,$04,$28,$FF
SG1_0:
  .byte $29,$08,$2C,$08,$30,$10,$2E,$08,$2C,$08,$29,$10,$2C,$08,$29,$08,$25,$10,$27,$08,$29,$08,$2C,$10,$2B,$08,$2E,$08,$33,$10,$31,$08
  .byte $30,$08,$2E,$10,$30,$20,$00,$10,$29,$10,$29,$08,$2C,$08,$30,$10,$2E,$08,$2C,$08,$29,$10,$2C,$08,$2E,$08,$31,$10,$30,$08,$2E,$08
  .byte $2C,$10,$2B,$08,$2C,$08,$2E,$10,$30,$08,$2E,$08,$2B,$10,$28,$20,$24,$20,$25,$10,$29,$10,$2E,$10,$2C,$08,$2E,$08,$29,$10,$2C,$10
  .byte $31,$10,$30,$08,$31,$08,$33,$10,$30,$10,$2C,$10,$30,$08,$33,$08,$2B,$20,$27,$20,$25,$10,$29,$10,$2E,$10,$2C,$08,$2E,$08,$2C,$10
  .byte $31,$10,$35,$10,$33,$08,$31,$08,$30,$10,$2B,$10,$28,$10,$2B,$08,$2E,$08,$30,$30,$00,$10,$FF
SG1_1:
  .byte $00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08
  .byte $00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$20,$08
  .byte $00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$20,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08
  .byte $00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08
  .byte $00,$08,$25,$08,$00,$08,$25,$08,$00,$08,$25,$08,$00,$08,$25,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08
  .byte $00,$08,$24,$08,$00,$08,$24,$08,$00,$08,$24,$08,$00,$08,$24,$08,$00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1F,$08,$00,$08,$1F,$08
  .byte $00,$08,$25,$08,$00,$08,$25,$08,$00,$08,$25,$08,$00,$08,$25,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08,$00,$08,$1D,$08
  .byte $00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08,$00,$08,$1C,$08
  .byte $FF
SG1_2:
  .byte $11,$08,$11,$08,$0C,$08,$11,$08,$11,$08,$11,$08,$0C,$08,$11,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08
  .byte $0F,$08,$0F,$08,$0A,$08,$0F,$08,$0F,$08,$0F,$08,$0A,$08,$0F,$08,$11,$08,$11,$08,$0C,$08,$11,$08,$11,$08,$11,$08,$0C,$08,$11,$08
  .byte $11,$08,$11,$08,$0C,$08,$11,$08,$11,$08,$11,$08,$0C,$08,$11,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08
  .byte $0F,$08,$0F,$08,$0A,$08,$0F,$08,$0F,$08,$0F,$08,$0A,$08,$0F,$08,$0C,$08,$0C,$08,$13,$08,$0C,$08,$0C,$08,$0C,$08,$13,$08,$0C,$08
  .byte $0A,$08,$0A,$08,$11,$08,$0A,$08,$0A,$08,$0A,$08,$11,$08,$0A,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08
  .byte $08,$08,$08,$08,$0F,$08,$08,$08,$08,$08,$08,$08,$0F,$08,$08,$08,$0F,$08,$0F,$08,$0A,$08,$0F,$08,$0F,$08,$0F,$08,$0A,$08,$0F,$08
  .byte $0A,$08,$0A,$08,$11,$08,$0A,$08,$0A,$08,$0A,$08,$11,$08,$0A,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08,$0D,$08,$0D,$08,$08,$08,$0D,$08
  .byte $0C,$08,$0C,$08,$13,$08,$0C,$08,$0C,$08,$0C,$08,$13,$08,$0C,$08,$0C,$08,$0C,$08,$13,$08,$0C,$08,$0C,$08,$0C,$08,$13,$08,$0C,$08
  .byte $FF
SG1_3:
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$01,$08,$02,$08,$03,$08
  .byte $FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$D0,$D0,$1C,$1C,$1C,$5F,$5F,$5F,$5F,$5F,$00,$50,$50,$50,$50,$50,$00,$3F,$3F
  .byte $3F,$3F,$3F,$00,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F
  .byte $27,$29,$2B,$2D,$30,$32,$35,$39,$78,$78,$78,$78,$78,$78,$78,$00,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$00,$86,$86,$86,$86,$86,$86,$86,$00
  .byte $8E,$8E,$8E,$8E,$8E,$8E,$8E,$00,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F
  .byte $9F,$9F,$9F,$9F,$9F,$9F,$50,$50,$50,$50,$00,$3F,$3F,$3F,$3F,$00,$35,$35,$35,$35,$00,$28,$28,$28,$28,$00,$35,$35,$35,$35,$00,$28
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$1D,$1B,$1D,$1B,$1D,$1B,$1D
  .byte $1B,$1D,$1B,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$08,$08,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$07
  .byte $07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03,$0B,$09,$09,$07,$04,$0D,$0C,$0C,$0B,$0A,$00,$0D,$0C,$0C,$0B,$0A,$00,$0D,$0C
  .byte $0C,$0B,$0A,$00,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$0B,$09,$08,$06
  .byte $07,$06,$06,$05,$04,$03,$03,$02,$0C,$0B,$0B,$0A,$09,$09,$08,$00,$0C,$0B,$0B,$0A,$09,$09,$08,$00,$0C,$0B,$0B,$0A,$09,$09,$08,$00
  .byte $0C,$0B,$0B,$0A,$09,$09,$08,$00,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$08,$07,$07,$06,$06,$06,$05,$05,$05,$04,$04
  .byte $04,$03,$03,$03,$02,$02,$0D,$0C,$0B,$0A,$00,$0D,$0C,$0B,$0A,$00,$0D,$0C,$0B,$0A,$00,$0D,$0C,$0B,$0A,$00,$0D,$0C,$0B,$0A,$00,$0E
  .byte $0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$07,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$0F,$2D,$32,$5C,$60,$68,$A6,$D9,$E3,$E6
WH_LEN:
  .byte $00,$0E,$1E,$05,$2A,$04,$08,$3E,$33,$0A,$03,$13
W_BEEP = 1
W_GO = 2
W_GEAR = 3
W_CHECK = 4
W_TICK = 5
W_PASS = 6
W_OVER = 7
W_LAP = 8
W_SKID = 9
W_KEY = 10
W_SIGN = 11

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01,$01,$06
  .byte $09,$06,$09,$06,$09,$06,$09
EX_NP:
  .byte $00,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0E,$0E,$0E,$0E,$0F,$0F,$1A
  .byte $1A,$1A,$1A,$1A,$1A,$1A,$1A
EX_VC:
  .byte $00,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$7D,$8A,$97,$A5,$B3,$C2,$D1,$E0,$F0,$01,$12,$23,$36,$48,$5C,$70,$85,$9B,$B2,$C9,$E2,$FC,$16,$32,$4F,$6D,$8C,$AD,$D0,$F4,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$03,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$1F
EX_LEN:
  .byte $00,$1E,$08
S_CRASH = 1
S_GRASS = 2

GFX_TITLE:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 1, $40,$46, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$66, <144,>144, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$66, <144,>144, <BIG_BOTC,>BIG_BOTC
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
GFX_RACE:
  .byte 1, $00,$48, <960,>960, <RD_PAT,>RD_PAT
  .byte 1, $00,$50, <960,>960, <RD_PAT,>RD_PAT
  .byte 1, $00,$54, <768,>768, <RD_PATB,>RD_PATB
  .byte 2, $20,$40, <8,>8, $00,0
  .byte 2, $20,$60, <8,>8, $15,0
  .byte 2, $18,$68, <8,>8, $1E,0
  .byte 2, $18,$70, <8,>8, $1E,0
  .byte 2, $40,$6B, <128,>128, $FE,0
  .byte 2, $40,$73, <128,>128, $FE,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
