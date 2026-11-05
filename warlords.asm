;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_WARLORDS  -  Atari Warlords (1980)                  ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: breakout / space invaders (NMI + trampoline $0FD0,   ;
;   joystick VIA, bitmap shadow in RAM, AY sound engine)       ;
;                                                              ;
;   - 4 castles in the corners: a warlord behind 3 walls of    ;
;     bricks (42 bricks); in front of every castle a shield    ;
;     runs along an L-shaped track                             ;
;   - the fireball bounces around, breaks the bricks and       ;
;     kills the warlord it reaches; the last warlord alive     ;
;     wins the round; the first to win 3 rounds wins the game  ;
;   - holding the button when the fireball hits the shield     ;
;     catches it: release the button to throw it back          ;
;   - the fireball gets faster during the round                ;
;   - 1 player: bottom-left castle + 3 castles of the computer ;
;     2 players: bottom-left and bottom-right + 2 of the       ;
;     computer; on the title 4 castles of the computer play    ;
;   - joystick 1 ($D581) = player 1, joystick 2 ($D580) =      ;
;     player 2: the four directions move the shield along the  ;
;     track, any button = catch / throw                        ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     roar of the dragon at the start of a round, bounce on    ;
;     the shields, bricks, walls of the screen, catch,         ;
;     explosion of a warlord, fanfare of the winner            ;
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
NPL         = $84      ; number of human players (1-2)
WINS        = $85      ; 4 bytes: rounds won per castle
CTRL        = $89      ; 4 bytes: 0 computer, 1 joystick 1, 2 joystick 2
ALIVEC      = $8D      ; 4 bytes: 1 = the warlord is alive
SHT         = $91      ; 4 bytes: position of the shield on its track (4-84)
CPUERR      = $95      ; 4 bytes: aiming error of the computer
BXL         = $99      ; fireball 8.8 (top-left of the 3x3 ball)
BXH         = $9A
BYL         = $9B
BYH         = $9C
VXL         = $9D      ; velocity per step 8.8 signed (VY must follow VX)
VXH         = $9E
VYL         = $9F
VYH         = $A0
STEPS       = $A1      ; steps per frame = speed
STEPC       = $A2
HELD        = $A3      ; 0 free, castle + 1 = caught by that shield
HELDT       = $A4      ; frames before it is thrown anyway
SPEEDT      = $A5      ; frames to the next speed-up
NALIVE      = $A6      ; warlords alive
ATTRACT     = $A7      ; 1 = title (4 computers playing)
CC          = $A8      ; castle being handled
CX          = $A9      ; centre of the fireball
CY          = $AA
BALLON      = $AB      ; 0 = waiting in the centre
LAUNCHT     = $AC
FIRE_OLD    = $AD
SHX         = $AE      ; 4 bytes: centre of the shields
SHY         = $B2      ; 4 bytes
STYPE       = $B6      ; 4 bytes: 0 horizontal, 1 vertical, 2 corner

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_BEAT   = $DC         ; (not used by this game)
BEAT_POS   = $DD
BEAT_NOTE  = $DE
SND_UFO    = $DF
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

; ---------------- zero page: more temporaries ----------------
MPTR       = $E1         ; 2 bytes: cell of the brick map
MBX        = $E3         ; brick map: column 0-31 (8 px)
MBY        = $E4         ;            row 0-47 (4 px)
PBX        = $E5         ; brick cell before the step
PBY        = $E6
OXL        = $E7         ; position before the step (4 bytes)
OFF        = $EB         ; offset of the hit on the shield (signed)
BTN        = $EC         ; 4 bytes: buttons held, per castle
WINNER     = $F0
TMPC       = $F1
CPUSPD     = $F2         ; speed of the shields of the computer
ROUNDT     = $F3         ; 2 bytes: frames of the round
CPUT       = $F5         ; 4 bytes: target of the computer (looked again every 8 frames)

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects

; ---------------- RAM arrays ----------------
BMAP   = $0800           ; 48 rows x 32 columns of 8x4 pixels: 0 empty,
                         ; 1-4 brick of castle 0-3, 8-11 warlord of castle 0-3
SH_PAT = $4000           ; copy of the screen (pattern) in RAM
SH_COL = $6000           ; copy of the colours

; ---------------- parameters ----------------
T_MIN       = 4          ; track of a shield: 0-44 horizontal part, 44-88 vertical
T_MAX       = 84
T_CORNER    = 44
HUMAN_SPD   = 3
CPU_SPD     = 2
LATE_TIME   = 7200       ; after 2 minutes the computer gets slower
WIN_ROUNDS  = 3
SPEED_TIME  = 150        ; x 4 frames = 10 seconds between two speed-ups
MAX_STEPS   = 6
V_MAX       = $E0        ; largest component of the velocity per step
V_MIN       = $50        ; smallest component away from a shield
V_LOW       = $30        ; smallest component in any case
BTN_MASK    = %00110000

; ---------------- records on the SD (lib_records.asm, at the end of the file) ----------------
REC_ZONE    = 10           ; fixed zone of the game in the save area
REC_RAM     = $7800        ; $2A0 bytes of free RAM
REC_ROW     = 7            ; table header on this row of the title, rows +1..+8 the table
REC_WIPEN   = 9            ; rows of the title that give way to the table
REC_JOY2    = 0            ; $FF = both joysticks sign, 0 = the player's own
REC_SROW    = 6            ; table header on the sign screen
REC_BMP     = 1            ; bitmap: characters through PUT_CHAR
REC_ONEPL   = 1            ; only one player plays the computers: no PLAYER n line
DEMO_T      = REC_RAM+$29D ; 2 bytes: frames of demo before the table
HIDE_Y      = $C0

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
  STA FRAME_CNT
  STA LAST_FRAME
  STA SND_UFO
  STA SND_BEAT
  LDA #$FF
  STA BEAT_POS
  LDA #$01
  STA NPL
  LDA #$A5
  STA RND
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_LOSE                 ; no run of wins yet
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: four computers play behind the title
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR DEMO_TIME
  LDA #$01
  STA ATTRACT
  LDX #$03
.ti_c:
  STZ CTRL,X
  STZ WINS,X
  DEX
  BPL .ti_c
  LDA #$FF
  STA FIRE_OLD
  JMP ROUND_START

NEW_GAME:
  STZ ATTRACT
  LDX #$03
.ng_c:
  STZ CTRL,X
  STZ WINS,X
  DEX
  BPL .ng_c
  LDA #$01                     ; player 1: bottom-left castle
  STA CTRL+2
  LDA NPL
  CMP #$02
  BNE ROUND_START
  LDA #$02                     ; player 2: bottom-right castle
  STA CTRL+3
  ; fall into ROUND_START


; ===============================================================
;  NEW ROUND: four castles, the fireball in the centre
; ===============================================================
ROUND_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #$11
  STA CLRCOL
  JSR CLEAR_SCREEN
  JSR CLEAR_MAP
  LDA #$03
  STA CC
.rs_c:
  LDX CC
  LDA #$01
  STA ALIVEC,X
  LDA #20
  STA SHT,X
  STA CPUT,X
  STZ BTN,X
  STZ CPUERR,X
  JSR BUILD_CASTLE
  DEC CC
  BPL .rs_c
  LDA #$04
  STA NALIVE
  JSR DRAW_HUD
  LDA ATTRACT
  BEQ .rs_g
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
.rs_g:
  LDA #126                     ; the fireball waits in the centre
  STA BXH
  LDA #94
  STA BYH
  STZ BXL
  STZ BYL
  STZ BALLON
  STZ HELD
  LDA #100
  STA LAUNCHT
  LDA #$03
  STA STEPS
  LDA #SPEED_TIME
  STA SPEEDT
  LDA #CPU_SPD
  STA CPUSPD
  STZ ROUNDT
  STZ ROUNDT+1
  JSR UPDATE_SHIELDS
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #S_ROAR                  ; the dragon
  LDX #2
  JSR SFX_BOOM


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  JSR UPDATE_SHIELDS
  LDA BALLON
  BNE .gl_ball
  DEC LAUNCHT                  ; ---- the dragon throws the fireball
  BNE .gl_draw
  JSR LAUNCH_CENTRE
  BRA .gl_draw
.gl_ball:
  LDA HELD
  BEQ .gl_free
  JSR UPDATE_HELD
  BRA .gl_draw
.gl_free:
  JSR UPDATE_BALL
.gl_draw:
  JSR SPEED_UP
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA ATTRACT                  ; ---- title: a button starts the game
  BEQ .gl_end
  LDA DEMO_T                   ; every 15 s of demo the table, then a new round
  BNE .gl_dt
  DEC DEMO_T+1
  BPL .gl_dt
  JSR DEMO_TABLE
  JMP ROUND_START
.gl_dt:
  DEC DEMO_T
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  STA T0                       ; buttons now
  EOR FIRE_OLD
  AND T0                       ; pressed now and not before
  LDX T0
  STX FIRE_OLD
  CMP #$00
  BEQ .gl_end
  LDX #$01
  AND #%00100000
  BEQ .gl_np
  LDX #$02
.gl_np:
  STX NPL
  LDA FRAME_CNT
  ORA #$01
  STA RND
  JMP NEW_GAME
.gl_end:
  LDA NALIVE
  CMP #$02
  BCS .gl_loop
  JMP ROUND_END
.gl_loop:
  JMP GAME_LOOP


; ---------------------------------------------------------------
; one warlord left: he wins the round
; ---------------------------------------------------------------
ROUND_END:
  LDX #$FF
  TXS
  LDX #$03                     ; who is alive?
.re_f:
  LDA ALIVEC,X
  BNE .re_w
  DEX
  BPL .re_f
  LDX #$00
.re_w:
  STX WINNER
  STZ BALLON
  JSR BUILD_SAT
  LDA ATTRACT
  BEQ .re_game
  JSR DEMO_TABLE               ; the table for 5 s (a button starts the game)
  JMP ROUND_START
.re_game:
  LDX WINNER
  INC WINS,X
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  LDX WINNER
  LDA WIN_TL,X                 ; "RED WINS"
  STA TP
  LDA WIN_TH,X
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  LDA #W_WIN
  LDX #2
  JSR SFX_WHISTLE
  LDA #150
  JSR WAIT_FRAMES
  LDX WINNER
  LDA WINS,X
  CMP #WIN_ROUNDS
  BCS GAME_OVER
  JMP ROUND_START

GAME_OVER:
  JSR VDP_INT_OFF
  LDX WINNER
  LDA LORD_TL,X                ; "RED IS THE WARLORD"
  STA TP
  LDA LORD_TH,X
  STA TP+1
  JSR DRAW_TEXT
  LDA #<TXT_PRESS
  STA TP
  LDA #>TXT_PRESS
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  LDA #W_WIN
  LDX #2
  JSR SFX_WHISTLE
  LDA #60
  JSR WAIT_FRAMES
  JSR WAIT_FIRE
  LDA NPL                      ; one player against the computers: the run of wins
  CMP #$01
  BNE .go_t
  LDA WINNER
  CMP #$02                     ; player 1: bottom-left castle
  BNE .go_lost
  STZ REC_EX
  JSR REC_WIN                  ; one more win: signed
  BRA .go_t
.go_lost:
  JSR REC_LOSE
.go_t:
  JMP TITLE

; after a round of the title demo: the table for 5 s; a button starts the game as in the demo
DEMO_TABLE:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR REC_CLS
  JSR REC_SHOW
  LDA #<TXT_DEMO
  STA TP
  LDA #>TXT_DEMO
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  LDA #<300
  STA REC_PT
  LDA #>300
  STA REC_PT+1
.dt_l:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  STA T0                       ; buttons now
  EOR FIRE_OLD
  AND T0                       ; pressed now and not before
  LDX T0
  STX FIRE_OLD
  CMP #$00
  BNE .dt_go
  LDA REC_PT
  BNE .dt_d
  DEC REC_PT+1
  BMI .dt_e
.dt_d:
  DEC REC_PT
  BRA .dt_l
.dt_e:
  JMP DEMO_TIME
.dt_go:
  LDX #$01
  AND #%00100000
  BEQ .dt_np
  LDX #$02
.dt_np:
  STX NPL
  LDA FRAME_CNT
  ORA #$01
  STA RND
  LDX #$FF
  TXS
  JMP NEW_GAME

TXT_DEMO:
  .byte 18,7,15,"BUTTON 1 = 1 PLAYER",0
  .byte 19,7,15,"BUTTON 2 = 2 PLAYERS",0
  .byte 21,3,14,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF

DEMO_TIME:                     ; 15 s of demo before the table
  LDA #<900
  STA DEMO_T
  LDA #>900
  STA DEMO_T+1
  RTS

REC_CLR:                       ; rows of the table: black
  PHA
  LDA #$11
  STA CLRCOL
  PLA
  JMP CLEAR_ROWS
REC_CLS:                       ; the sign screen (and the table of the demo): all black
  LDA #$11
  STA CLRCOL
  JMP CLEAR_SCREEN


; hooks of lib_records.asm (bitmap: the characters in the cells)
REC_XY:                        ; X = row, Y = column
  STX CELLR
  STY CELLC
  LDA #$F1
  STA TCOL
  RTS
REC_CHR:                       ; A = character in the cell, then the next cell
  JSR PUT_CHAR
  INC CELLC
  RTS
REC_CLRROWS = REC_CLR       ; A = first row, X = rows
REC_SND:                       ; A = 0 a letter, 1 the initials confirmed (the game's whistles)
  PHX
  LDX #2
  CMP #0
  BNE .rn_s
  LDA #W_SHIELD
  BRA .rn_p
.rn_s:
  LDA #W_WIN
.rn_p:
  JSR SFX_WHISTLE
  PLX
  RTS
REC_NAME:  .byte "WARLORDS        "
REC_HEAD:  .byte "MOST WINS IN A ROW",0
REC_XLBL:  .byte "",0



; ===============================================================
;  SHIELDS
; ===============================================================
UPDATE_SHIELDS:
  LDX #$03
.us_l:
  STX CC
  LDA ALIVEC,X
  BEQ .us_n
  LDA CTRL,X
  BEQ .us_cpu
  ; ---- human: the four directions run along the track
  TAY
  LDA P_JOY-1,Y
  STA T0
  AND #BTN_MASK
  STA BTN,X
  LDA T0
  AND INC_MASK,X
  BEQ .us_dec
  LDA SHT,X
  CLC
  ADC #HUMAN_SPD
  BRA .us_clamp
.us_dec:
  LDA T0
  AND DEC_MASK,X
  BEQ .us_pos
  LDA SHT,X
  SEC
  SBC #HUMAN_SPD
  BRA .us_clamp
.us_cpu:
  LDA FRAME_CNT                ; reaction time: a new look every 8 frames
  AND #$07
  BNE .us_keep
  JSR CPU_TARGET               ; A = where it wants to be
  STA CPUT,X
.us_keep:
  LDA CPUT,X
  STA T0
  LDA SHT,X
  CMP T0
  BEQ .us_pos
  BCC .us_up
  SEC
  SBC CPUSPD
  CMP T0
  BCS .us_clamp
  LDA T0
  BRA .us_clamp
.us_up:
  CLC
  ADC CPUSPD
  CMP T0
  BCC .us_clamp
  LDA T0
.us_clamp:
  CMP #T_MIN
  BCS .us_c1
  LDA #T_MIN
.us_c1:
  CMP #(T_MAX+1)
  BCC .us_c2
  LDA #T_MAX
.us_c2:
  STA SHT,X
.us_pos:
  JSR SHIELD_POS
.us_n:
  LDX CC
  DEX
  BPL .us_l
  RTS

; centre and kind of the shield X from its place on the track
SHIELD_POS:
  LDA SHT,X
  CMP #T_CORNER
  BCC .sp_h
  LDA #T_CORNER                ; x = min(t, 44)
.sp_h:
  LDY MXF,X
  BEQ .sp_x
  EOR #$FF                     ; 255 - x
.sp_x:
  STA SHX,X
  LDA #(2*T_CORNER)            ; y = min(88 - t, 44)
  SEC
  SBC SHT,X
  CMP #T_CORNER
  BCC .sp_v
  LDA #T_CORNER
.sp_v:
  LDY MYF,X
  BEQ .sp_y
  STA T1
  LDA #191
  SEC
  SBC T1
.sp_y:
  STA SHY,X
  LDA SHT,X                    ; kind: horizontal, corner, vertical
  LDY #0
  CMP #(T_CORNER-4)
  BCC .sp_k
  LDY #2
  CMP #(T_CORNER+5)
  BCC .sp_k
  LDY #1
.sp_k:
  TYA
  STA STYPE,X
  RTS

; X = castle of the computer: A = the place on the track that faces the fireball
CPU_TARGET:
  LDA BXH                      ; fireball in the frame of the top-left castle
  CLC
  ADC #1
  LDY MXF,X
  BEQ .ct_x
  EOR #$FF
.ct_x:
  STA T1                       ; rx
  LDA BYH
  CLC
  ADC #1
  LDY MYF,X
  BEQ .ct_y
  STA T2
  LDA #191
  SEC
  SBC T2
.ct_y:
  STA T2                       ; ry
  LDA T1                       ; fireball far from this corner: back to the corner
  CMP #128
  BCS .ct_rest
  LDA T2
  CMP #96
  BCS .ct_rest
  CMP T1
  BCC .ct_v
  LDA T1                       ; below the corner: horizontal part, t = rx
  CMP #T_CORNER
  BCC .ct_e
  LDA #T_CORNER
  BRA .ct_e
.ct_v:
  LDA T2                       ; beside the corner: vertical part, t = 88 - ry
  CMP #T_CORNER
  BCC .ct_v1
  LDA #T_CORNER
.ct_v1:
  STA T3
  LDA #(2*T_CORNER)
  SEC
  SBC T3
.ct_e:
  CLC
  ADC CPUERR,X
  CMP #200                     ; (below 0)
  BCS .ct_min
  CMP #T_MIN
  BCC .ct_min
  CMP #(T_MAX+1)
  BCC .ct_r
  LDA #T_MAX
  RTS
.ct_min:
  LDA #T_MIN
.ct_r:
  RTS
.ct_rest:
  LDA #T_CORNER
  RTS


; ===============================================================
;  FIREBALL
; ===============================================================
LAUNCH_CENTRE:                 ; towards one of the four castles, at random
  LDA #$01
  STA BALLON
  JSR NEXT_RND
  LDA RND
  AND #$03
  TAX
  LDA LAUNCH_DIR,X
  JMP SET_DIR

; A = direction 0-15
SET_DIR:
  TAY
  LDA DIRX_L,Y
  STA VXL
  LDA DIRX_H,Y
  STA VXH
  LDA DIRY_L,Y
  STA VYL
  LDA DIRY_H,Y
  STA VYH
  RTS

; the fireball gets faster during the round
SPEED_UP:
  INC ROUNDT                   ; ---- long rounds: the computer gets slower
  BNE .su_t
  INC ROUNDT+1
.su_t:
  LDA ROUNDT+1
  CMP #>LATE_TIME
  BCC .su_h
  LDA #1
  STA CPUSPD
.su_h:
  LDA ATTRACT                  ; ---- no player left: the round hurries up
  BNE .su_f
  LDX #$03
.su_p:
  LDA CTRL,X
  BEQ .su_pn
  LDA ALIVEC,X
  BNE .su_f
.su_pn:
  DEX
  BPL .su_p
  LDA #1
  STA CPUSPD
  LDA #MAX_STEPS
  STA STEPS
.su_f:
  LDA FRAME_CNT
  AND #$03
  BNE .su_r
  DEC SPEEDT
  BNE .su_r
  LDA #SPEED_TIME
  STA SPEEDT
  LDA STEPS
  CMP #MAX_STEPS
  BCS .su_r
  INC STEPS
.su_r:
  RTS

UPDATE_BALL:
  LDA STEPS
  STA STEPC
.ub_l:
  JSR BALL_STEP
  LDA HELD
  BNE .ub_e
  DEC STEPC
  BNE .ub_l
.ub_e:
  RTS

BALL_STEP:
  LDX #0                       ; never purely vertical or horizontal
  JSR MIN_V
  LDX #2
  JSR MIN_V
  JSR CENTRE                   ; brick cell before the step
  LDA MBX
  STA PBX
  LDA MBY
  STA PBY
  LDX #3                       ; position before the step
.bs_o:
  LDA BXL,X
  STA OXL,X
  DEX
  BPL .bs_o
  CLC                          ; ---- move
  LDA BXL
  ADC VXL
  STA BXL
  LDA BXH
  ADC VXH
  STA BXH
  CLC
  LDA BYL
  ADC VYL
  STA BYL
  LDA BYH
  ADC VYH
  STA BYH
  ; ---- edges of the screen
  LDA VXH
  BMI .bs_l
  LDA BXH
  CMP #253
  BCC .bs_y
  LDA #252
  BRA .bs_wx
.bs_l:
  LDA BXH
  BEQ .bs_lw
  CMP #$F0                     ; (wrapped below 0)
  BCC .bs_y
.bs_lw:
  LDA #1
.bs_wx:
  STA BXH
  JSR NEG_VX
  JSR WALL_SOUND
.bs_y:
  LDA VYH
  BMI .bs_u
  LDA BYH
  CMP #189
  BCC .bs_br
  LDA #188
  BRA .bs_wy
.bs_u:
  LDA BYH
  BEQ .bs_uw
  CMP #$F0
  BCC .bs_br
.bs_uw:
  LDA #1
.bs_wy:
  STA BYH
  JSR NEG_VY
  JSR WALL_SOUND
.bs_br:
  ; ---- bricks and warlords
  JSR CENTRE
  JSR MAP_GET
  BEQ .bs_sh
  STA T7
  LDX #3                       ; back where it was, and bounce
.bs_back:
  LDA OXL,X
  STA BXL,X
  DEX
  BPL .bs_back
  LDA MBX
  CMP PBX
  BEQ .bs_ny
  JSR NEG_VX
  LDA MBY
  CMP PBY
  BEQ .bs_hit
.bs_ny:
  JSR NEG_VY
.bs_hit:
  LDA T7
  CMP #8
  BCS .bs_king
  JMP HIT_BRICK
.bs_king:
  SEC
  SBC #8
  TAX
  JMP KILL_CASTLE
.bs_sh:
  ; ---- shields
  LDX #$03
.bs_s:
  LDA ALIVEC,X
  BEQ .bs_sn
  JSR HIT_SHIELD
.bs_sn:
  DEX
  BPL .bs_s
  RTS

; CX / CY = centre of the fireball, MBX / MBY = its cell in the brick map
CENTRE:
  LDA BXH
  CLC
  ADC #1
  STA CX
  LSR A
  LSR A
  LSR A
  STA MBX
  LDA BYH
  CLC
  ADC #1
  STA CY
  LSR A
  LSR A
  STA MBY
  RTS

; A = brick map at MBX / MBY (MPTR points to it); rows past 47 are empty
MAP_GET:
  LDA MBY
  CMP #48
  BCS .mg_0
  JSR MAP_PTR
  LDA (MPTR)
  RTS
.mg_0:
  LDA #$00
  RTS

MAP_PTR:                       ; MPTR = BMAP + MBY * 32 + MBX
  LDA MBY
  LSR A
  LSR A
  LSR A
  CLC
  ADC #>BMAP
  STA MPTR+1
  LDA MBY
  AND #$07
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA MBX
  STA MPTR
  RTS

; X = castle: does the fireball touch its shield?
HIT_SHIELD:
  STX CC
  LDA CX
  SEC
  SBC SHX,X
  STA OFF                      ; offset along X
  JSR ABS_A
  STA T4
  LDA CY
  SEC
  SBC SHY,X
  STA T6                       ; offset along Y
  JSR ABS_A
  STA T5
  LDY STYPE,X
  LDA T4
  CMP HALFW,Y
  BCS .hs_no
  LDA T5
  CMP HALFH,Y
  BCS .hs_no
  CPY #1
  BNE .hs_nv
  LDA T6                       ; vertical shield: the offset that counts is along Y
  STA OFF
.hs_nv:
  ; ---- only when the fireball goes towards the castle
  CPY #1
  BEQ .hs_vert
  LDA VYH                      ; horizontal or corner: Y must go towards the castle
  EOR AWY,X
  BMI .hs_bounce
  CPY #2
  BNE .hs_no
.hs_vert:
  LDA VXH
  EOR AWX,X
  BMI .hs_bounce
.hs_no:
  LDX CC
  RTS
.hs_bounce:
  ; ---- caught? (button held, or the computer now and then)
  LDA CTRL,X
  BEQ .hs_cpu
  LDA BTN,X
  BNE .hs_catch
  BRA .hs_reflect
.hs_cpu:
  LDA ATTRACT
  BNE .hs_reflect
  JSR NEXT_RND
  LDA RND
  AND #$07
  BNE .hs_reflect
.hs_catch:
  TXA
  INC A
  STA HELD
  LDA CTRL,X                   ; the computer keeps it 20-51 frames, a player up to 3 s
  BEQ .hs_ct
  LDA #180
  BRA .hs_ht
.hs_ct:
  LDA RND
  AND #$1F
  CLC
  ADC #20
.hs_ht:
  STA HELDT
  LDA #W_CATCH
  JSR BALL_SOUND
  LDX CC
  RTS
.hs_reflect:
  JSR REFLECT
  JSR NEXT_RND                 ; the computer aims a bit differently next time
  LDA RND
  AND #$1F
  SEC
  SBC #16
  LDX CC
  STA CPUERR,X
  LDA #W_SHIELD
  JSR BALL_SOUND
  LDX CC
  RTS

; X = castle (CC), Y = kind of shield: the fireball goes away from the castle;
; the offset of the hit (OFF) bends it along the shield
REFLECT:
  LDX CC
  LDY STYPE,X
  CPY #1
  BEQ .rf_v
  JSR AWAY_Y                   ; horizontal / corner: Y away
  CPY #2
  BEQ .rf_c
  LDA OFF                      ; horizontal: X += offset * 8
  JSR ADD_OFF_X
  RTS
.rf_c:
  JSR AWAY_X
  RTS
.rf_v:
  JSR AWAY_X                   ; vertical: X away, Y += offset * 8
  LDA OFF
  JMP ADD_OFF_Y

; VY = |VY| towards AWY (at least V_MIN)
AWAY_Y:
  LDA VYH
  BPL .ay_p
  JSR NEG_VY
.ay_p:
  LDA VYL
  CMP #V_MIN
  BCS .ay_s
  LDA #V_MIN
  STA VYL
.ay_s:
  LDX CC
  LDA AWY,X
  BPL .ay_r
  JMP NEG_VY
.ay_r:
  RTS

AWAY_X:
  LDA VXH
  BPL .ax_p
  JSR NEG_VX
.ax_p:
  LDA VXL
  CMP #V_MIN
  BCS .ax_s
  LDA #V_MIN
  STA VXL
.ax_s:
  LDX CC
  LDA AWX,X
  BPL .ax_r
  JMP NEG_VX
.ax_r:
  RTS

; A = offset (signed): VX += A * 8, then |VX| <= V_MAX
ADD_OFF_X:
  JSR TIMES8
  CLC
  ADC VXL
  STA VXL
  TYA
  ADC VXH
  STA VXH
  LDX #0
  JMP CLAMP_V

ADD_OFF_Y:
  JSR TIMES8
  CLC
  ADC VYL
  STA VYL
  TYA
  ADC VYH
  STA VYH
  LDX #2
  JMP CLAMP_V

TIMES8:                        ; A (signed) * 8 -> A low, Y high
  LDY #$00
  CMP #$80
  BCC .t8_p
  LDY #$FF
.t8_p:
  ASL A
  ASL A
  ASL A
  RTS

; X = 0 (VX) / 2 (VY): the component stays within +-V_MAX
CLAMP_V:
  LDA VXH,X
  BMI .cv_n
  BNE .cv_hp
  LDA VXL,X
  CMP #(V_MAX+1)
  BCC .cv_r
.cv_hp:
  LDA #V_MAX
  STA VXL,X
  STZ VXH,X
  RTS
.cv_n:
  CMP #$FF
  BNE .cv_hn
  LDA VXL,X
  CMP #(256-V_MAX)
  BCS .cv_r
.cv_hn:
  LDA #(256-V_MAX)
  STA VXL,X
  LDA #$FF
  STA VXH,X
.cv_r:
  RTS

; X = 0 (VX) / 2 (VY): |component| >= V_LOW (a zero becomes positive)
MIN_V:
  LDA VXH,X
  BMI .mv_n
  BNE .mv_r
  LDA VXL,X
  CMP #V_LOW
  BCS .mv_r
  LDA #V_LOW
  STA VXL,X
  RTS
.mv_n:
  CMP #$FF
  BNE .mv_r
  LDA VXL,X
  CMP #(256-V_LOW+1)
  BCC .mv_r
  LDA #(256-V_LOW)
  STA VXL,X
.mv_r:
  RTS

NEG_VX:
  LDA #$00
  SEC
  SBC VXL
  STA VXL
  LDA #$00
  SBC VXH
  STA VXH
  RTS

NEG_VY:
  LDA #$00
  SEC
  SBC VYL
  STA VYL
  LDA #$00
  SBC VYH
  STA VYH
  RTS

ABS_A:                         ; A = |A| (signed)
  BPL .ab_r
  EOR #$FF
  CLC
  ADC #1
.ab_r:
  RTS

; ---------------------------------------------------------------
; the fireball stays on the shield HELD-1 until it is thrown
; ---------------------------------------------------------------
UPDATE_HELD:
  LDX HELD
  DEX
  STX CC
  LDA SHX,X
  CLC
  ADC HOLDX,X
  LDY STYPE,X
  CPY #1
  BEQ .uh_x
  CPY #2
  BEQ .uh_x
  LDA SHX,X                    ; horizontal: in front, on the same X
.uh_x:
  SEC
  SBC #1
  STA BXH
  LDA SHY,X
  CLC
  ADC HOLDY,X
  CPY #1
  BNE .uh_y
  LDA SHY,X                    ; vertical: beside, on the same Y
.uh_y:
  SEC
  SBC #1
  STA BYH
  STZ BXL
  STZ BYL
  DEC HELDT                    ; ---- thrown: time over, or the button released
  BEQ THROW
  LDA CTRL,X
  BEQ .uh_r
  LDA BTN,X
  BEQ THROW
.uh_r:
  RTS

THROW:
  LDX CC
  STZ HELD
  LDY STYPE,X
  CPY #1
  BEQ .th_v
  STZ VXL                      ; horizontal / corner: away along Y,
  STZ VXH                      ; bent by the place on the shield
  LDA #$B0
  STA VYL
  STZ VYH
  JSR AWAY_Y
  LDX CC
  LDY STYPE,X
  CPY #2
  BNE .th_h
  LDA #$90
  STA VXL
  JMP AWAY_X
.th_h:
  JSR NEXT_RND
  LDA RND
  AND #$0F
  SEC
  SBC #8
  ASL A
  JMP ADD_OFF_X
.th_v:
  STZ VYL
  STZ VYH
  LDA #$B0
  STA VXL
  STZ VXH
  JSR AWAY_X
  JSR NEXT_RND
  LDA RND
  AND #$0F
  SEC
  SBC #8
  ASL A
  JMP ADD_OFF_Y


; ===============================================================
;  CASTLES
; ===============================================================
; the brick at MPTR / MBX / MBY breaks
HIT_BRICK:
  LDA #$00
  STA (MPTR)
  LDA MBX
  STA CELLC
  LDA MBY
  JSR BRICK_CELL_SETUP
  LDA #$00
  STA (SPTR),Y
  INY
  STA (SPTR),Y
  INY
  STA (SPTR),Y
  JSR FLUSH_CELL
  LDA #W_BRICK
  ; fall into BALL_SOUND

; A = tone effect, on the speaker on the side of the fireball
BALL_SOUND:
  LDX #$00
  LDY BXH
  BPL .bsn
  LDX #$01
.bsn:
  JMP SFX_WHISTLE

WALL_SOUND:
  LDA #W_WALL
  JMP BALL_SOUND

; A = brick row 0-47, CELLC set: CELLR, CELL_SETUP, Y = first line of the brick
BRICK_CELL_SETUP:
  PHA
  LSR A
  STA CELLR
  JSR CELL_SETUP
  PLA
  AND #$01
  ASL A
  ASL A
  TAY
  RTS

; X = castle: bricks, warlord, map
BUILD_CASTLE:
  STX CC
  LDA COLC,X
  STA TCOL
  LDA #(NBRICKS-1)
  STA T6
.bc_l:
  LDY T6
  LDX CC
  LDA BRICK_BX,Y
  LDY MXF,X
  BEQ .bc_x
  EOR #$1F                     ; 31 - column
.bc_x:
  STA MBX
  LDY T6
  LDA BRICK_BY,Y
  LDY MYF,X
  BEQ .bc_y
  STA T0
  LDA #47
  SEC
  SBC T0
.bc_y:
  STA MBY
  JSR MAP_PTR
  LDA CC
  INC A
  STA (MPTR)
  LDA MBX                      ; draw: 3 lines of brick, 1 of mortar
  STA CELLC
  LDA MBY
  JSR BRICK_CELL_SETUP
  LDX #3
.bc_d:
  LDA #$FE
  CPX #0
  BNE .bc_p
  LDA #$00
.bc_p:
  STA (SPTR),Y
  LDA TCOL
  STA (PTR2),Y
  INY
  DEX
  BPL .bc_d
  JSR FLUSH_CELL
  DEC T6
  BPL .bc_l
  ; ---- the warlord: 2x2 cells in the corner, 4x2 cells of the map
  LDX CC
  LDA KCOL,X
  STA CELLC
  STA BIGC
  LDA KROW,X
  STA CELLR
  STA BIGR
  LDA #<KING_PAT
  STA PTR
  LDA #>KING_PAT
  STA PTR+1
  JSR FILL_CELL
  INC CELLC
  JSR NEXT8
  JSR FILL_CELL
  LDA BIGC
  STA CELLC
  INC CELLR
  JSR NEXT8
  JSR FILL_CELL
  INC CELLC
  JSR NEXT8
  JSR FILL_CELL
  LDA #$03                     ; map: 2 columns x 4 rows
  STA T6
.bk_l:
  LDA T6
  AND #$01
  CLC
  ADC BIGC
  STA MBX
  LDA T6
  LSR A
  STA T0
  LDA BIGR
  ASL A
  CLC
  ADC T0
  STA MBY
  JSR .bk_set
  INC MBY
  INC MBY
  JSR .bk_set
  DEC T6
  BPL .bk_l
  RTS
.bk_set:
  JSR MAP_PTR
  LDA CC
  CLC
  ADC #8
  STA (MPTR)
  RTS

NEXT8:
  LDA PTR
  CLC
  ADC #8
  STA PTR
  BCC .n8
  INC PTR+1
.n8:
  RTS

; X = castle: the warlord dies (the walls stay)
KILL_CASTLE:
  STX CC
  STZ ALIVEC,X
  DEC NALIVE
  LDA #$03                     ; erase him from the map and from the screen
  STA T6
.kc_l:
  LDX CC
  LDA T6
  AND #$01
  CLC
  ADC KCOL,X
  STA MBX
  STA CELLC
  LDA T6
  LSR A
  CLC
  ADC KROW,X
  STA CELLR
  ASL A
  STA MBY
  JSR MAP_PTR
  LDA #$00
  STA (MPTR)
  LDY #32                      ; and the map row under it
  STA (MPTR),Y
  LDA #<ZERO8
  STA PTR
  LDA #>ZERO8
  STA PTR+1
  JSR FILL_CELL
  DEC T6
  BPL .kc_l
  LDA #S_KING
  LDX #2
  JMP SFX_BOOM

CLEAR_MAP:
  LDA #<BMAP
  STA MPTR
  LDA #>BMAP
  STA MPTR+1
  LDX #6                       ; 6 pages = 1536 bytes
  LDA #$00
.cm_p:
  LDY #$00
.cm_b:
  STA (MPTR),Y
  INY
  BNE .cm_b
  INC MPTR+1
  DEX
  BNE .cm_p
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

; rounds won and who plays each castle
DRAW_HUD:
  LDX #$03
.dh_l:
  STX CC
  LDA COLC,X
  STA TCOL
  LDA HUD_ROW,X
  STA CELLR
  LDA HUD_DCOL,X
  STA CELLC
  LDA WINS,X
  ORA #$30
  JSR PUT_CHAR
  LDX CC
  LDA HUD_LCOL,X
  STA CELLC
  LDY CTRL,X                   ; "CPU", "1UP", "2UP"
  LDA LABEL_OFS,Y
  STA T6
  LDA #3
  STA T7
.dh_c:
  LDY T6
  LDA LABELS,Y
  JSR PUT_CHAR
  INC CELLC
  INC T6
  DEC T7
  BNE .dh_c
  LDX CC
  DEX
  BPL .dh_l
  RTS


; ===============================================================
;  SPRITES AND NMI:  0 fireball, 1-4 shields
; ===============================================================
BUILD_SAT:
  LDA BALLON                   ; ---- fireball (flickers like a flame)
  BNE .bs_on
  LDA LAUNCHT
  AND #$04
  BEQ .bs_hide                 ; waiting in the centre: blinking
.bs_on:
  LDA BYH
  DEC A
  STA SAT_BUFFER
  LDA BXH
  STA SAT_BUFFER+1
  LDA FRAME_CNT
  AND #$04
  STA SAT_BUFFER+2
  LDA FRAME_CNT
  AND #$02
  ORA #$09                     ; light red / light yellow
  STA SAT_BUFFER+3
  BRA .bs_sh
.bs_hide:
  LDA #HIDE_Y
  STA SAT_BUFFER
.bs_sh:
  LDX #$03                     ; ---- shields
.bs_l:
  TXA
  ASL A
  ASL A
  TAY                          ; Y = 4 * castle
  LDA ALIVEC,X
  BEQ .bs_no
  LDA SHY,X
  SEC
  SBC #9
  STA SAT_BUFFER+4,Y
  LDA STYPE,X
  ASL A
  ASL A
  CLC
  ADC #8
  STA SAT_BUFFER+6,Y
  LDA SHX,X
  SEC
  SBC #8
  BCC .bs_ec
  STA SAT_BUFFER+5,Y
  LDA SPRC,X
  STA SAT_BUFFER+7,Y
  BRA .bs_n
.bs_ec:
  CLC                          ; near the left edge: early clock
  ADC #32
  STA SAT_BUFFER+5,Y
  LDA SPRC,X
  ORA #$80
  STA SAT_BUFFER+7,Y
  BRA .bs_n
.bs_no:
  LDA #HIDE_Y
  STA SAT_BUFFER+4,Y
.bs_n:
  DEX
  BPL .bs_l
  RTS

HIDE_SPRITES:
  LDX #16
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
  CPX #21                 ; 5 sprites x 4 bytes + Y=$D0 of the 6th entry
  BNE .copy_sat
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

SAT_BUFFER:
  .byte HIDE_Y,0,0,$09
  .byte HIDE_Y,0,8,$08, HIDE_Y,0,8,$05, HIDE_Y,0,8,$03, HIDE_Y,0,8,$0B
  .byte $D0


; ===============================================================
;  SOUND: effects only (no music on the cabinet; same engine as Space Invaders,
;  the march and the siren are not used here)
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
; by castle: 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right
MXF:        .byte 0,1,0,1              ; mirrored left-right
MYF:        .byte 0,0,1,1              ; mirrored top-bottom
AWX:        .byte $01,$FF,$01,$FF      ; away from the castle along X (sign)
AWY:        .byte $01,$01,$FF,$FF      ;                      along Y
HOLDX:      .byte 6,$FA,6,$FA          ; the caught fireball, in front of the shield
HOLDY:      .byte 6,6,$FA,$FA
INC_MASK:   .byte %1001,%0101,%1010,%0110  ; joystick that moves the shield up the track
DEC_MASK:   .byte %0110,%1010,%0101,%1001  ;                               down the track
COLC:       .byte $81,$51,$31,$B1      ; red, blue, green, yellow (bricks, warlord, texts)
SPRC:       .byte $08,$05,$03,$0B      ; colour of the shield
KCOL:       .byte 0,30,0,30            ; cell of the warlord
KROW:       .byte 0,0,22,22
HUD_ROW:    .byte 0,0,23,23            ; rounds won and "CPU" / "1UP" / "2UP"
HUD_DCOL:   .byte 7,24,7,24
HUD_LCOL:   .byte 9,20,9,20
LABEL_OFS:  .byte 0,3,6
LABELS:     .byte "CPU1UP2UP"
LAUNCH_DIR: .byte 2,6,10,14            ; diagonals from the centre
HALFW:      .byte 8,3,5                ; size of a shield: horizontal, vertical, corner
HALFH:      .byte 3,8,5
ZERO8:      .byte 0,0,0,0,0,0,0,0
WIN_TL:     .byte <TXT_WIN0,<TXT_WIN1,<TXT_WIN2,<TXT_WIN3
WIN_TH:     .byte >TXT_WIN0,>TXT_WIN1,>TXT_WIN2,>TXT_WIN3
LORD_TL:    .byte <TXT_LORD0,<TXT_LORD1,<TXT_LORD2,<TXT_LORD3
LORD_TH:    .byte >TXT_LORD0,>TXT_LORD1,>TXT_LORD2,>TXT_LORD3

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_TITLE:
  .byte 11,7,15,"BUTTON 1 = 1 PLAYER",0
  .byte 12,7,15,"BUTTON 2 = 2 PLAYERS",0
  .byte 14,6,14,"HOLD THE BUTTON TO CATCH",0
  .byte 15,10,14,"THE FIREBALL",0
  .byte 17,9,11,"FIRST TO 3 WINS",0
  .byte 20,10,14,"DEVELOPED BY",0
  .byte 21,10,14,"BOOGS & CCAI",0
  .byte $FF
TXT_WIN0:   .byte 11,12,8,"RED WINS",0,$FF
TXT_WIN1:   .byte 11,12,5,"BLUE WINS",0,$FF
TXT_WIN2:   .byte 11,11,3,"GREEN WINS",0,$FF
TXT_WIN3:   .byte 11,11,11,"YELLOW WINS",0,$FF
TXT_LORD0:  .byte 11,7,8,"RED IS THE WARLORD",0,$FF
TXT_LORD1:  .byte 11,7,5,"BLUE IS THE WARLORD",0,$FF
TXT_LORD2:  .byte 11,6,3,"GREEN IS THE WARLORD",0,$FF
TXT_LORD3:  .byte 11,6,11,"YELLOW IS THE WARLORD",0,$FF
TXT_PRESS:
  .byte 13,9,15,"PRESS A BUTTON",0
  .byte $FF
; big words: row, column, number of letters, letters (W A R L O D S)
TITLE_BIG:
  .byte 8,8,8,0,1,2,3,4,2,5,6    ; WARLORDS
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
; big letters (16x16, 4 tiles each, 8 pattern + 8 colour bytes): W A R L O D S
BIGFONT:
  ; W
  .byte $00,$18,$18,$18,$18,$18,$18,$19,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$18,$18,$18,$18,$18,$18,$98,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $19,$19,$19,$1E,$1E,$18,$18,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $98,$98,$98,$78,$78,$18,$18,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  ; A
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$80,$80,$60,$60,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $18,$F8,$F8,$18,$18,$18,$18,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  ; R
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $E0,$80,$80,$60,$60,$18,$18,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  ; L
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $00,$00,$00,$00,$00,$F8,$F8,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  ; O
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  ; D
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  ; S
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$00,$00,$E0,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1
  .byte $E0,$18,$18,$18,$18,$E0,$E0,$00,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1

; bricks of the top-left castle (units of 8x4 pixels: column, row), 42 bricks
NBRICKS = 42
BRICK_BX:
  .byte $02,$02,$02,$02,$02,$02,$00,$01,$00,$01,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$00,$01,$02,$00,$01,$02,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$00,$01,$02,$03,$00,$01,$02,$03
BRICK_BY:
  .byte $00,$01,$02,$03,$04,$05,$04,$04,$05,$05,$00,$01,$02,$03,$04,$05
  .byte $06,$07,$06,$06,$06,$07,$07,$07,$00,$01,$02,$03,$04,$05,$06,$07
  .byte $08,$09,$08,$08,$08,$08,$09,$09,$09,$09

; the warlord 16x16: 4 cells (top-left, top-right, bottom-left, bottom-right)
KING_PAT:
  .byte $00,$21,$33,$3F,$3F,$1F,$0F,$0B,$00,$84,$CC,$FC,$FC,$F8,$F0,$D0
  .byte $0F,$0D,$07,$1F,$3F,$7F,$7F,$00,$F0,$B0,$E0,$F8,$FC,$FE,$FE,$00

; sprites 16x16: fireball (2 frames), shield horizontal, vertical, corner
SPR_PAGES = 1
SPRITES:
  .byte $40,$E0,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E0,$E0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$FE,$FE,$FE,$FE,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$00
  .byte $00,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$00
  .byte $00,$00,$00,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$BD,$BD,$BD,$BD,$BD,$3C,$3F,$42,$45,$7B,$7B,$7B,$5F,$5A,$56
  .byte $53,$50,$4C,$4A,$47,$78,$78,$78,$78,$78,$78,$78,$78,$5F,$5F,$5F
  .byte $5F,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$50,$50,$50,$50,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0D,$0B,$0A,$08,$06,$0C,$0A,$07,$05,$0A,$08,$06,$0C,$0B,$0B
  .byte $0A,$0A,$09,$09,$08,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$0D,$0D,$0C
  .byte $0C,$0B,$0B,$0A,$0A,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$0D,$0D,$0C
  .byte $0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$06,$05
  .byte $05,$04,$04,$03,$03
WH_START:
  .byte $00,$01,$06,$0A,$0D,$15
WH_LEN:
  .byte $00,$05,$04,$03,$08,$30
W_SHIELD = 1
W_BRICK = 2
W_WALL = 3
W_CATCH = 4
W_WIN = 5

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00
  .byte $00,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C,$0D
  .byte $0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06
EX_NP:
  .byte $00,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $0F,$10,$10,$10,$10,$10,$10,$10,$10,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$13,$13,$13
  .byte $13,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15
  .byte $15,$18,$18,$18,$18,$17,$17,$17,$17,$16,$16,$16,$16,$15,$15,$15
  .byte $15,$14,$14,$14,$14,$13,$13,$13,$13,$12,$12,$12,$12,$11,$11,$11
  .byte $11,$10,$10,$10,$10,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D
  .byte $0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B
EX_VC:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05
  .byte $05,$05,$05,$04,$04,$04,$04,$03,$03
EX_TL:
  .byte $00,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$B6,$BE,$C6,$CE,$D7,$DF,$E8,$F1,$FA,$04,$0D,$17,$21,$2C,$36
  .byte $41,$4D,$58,$64,$70,$7D,$8A,$97,$A5,$B3,$C2,$D1,$E0,$F0,$01,$12
  .byte $23,$36,$48,$5C,$70,$85,$9B,$B2,$C9,$E2,$FC,$16,$32,$4F,$6D,$8C
  .byte $AD,$D0,$F4,$1B,$43,$6D,$99,$C8,$FA
EX_TH:
  .byte $00,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$06,$06,$06,$06,$06,$06
EX_START:
  .byte $00,$01,$41
EX_LEN:
  .byte $00,$40,$38
S_KING = 1
S_ROAR = 2
S_BIG = S_KING

; no march in this game
BEAT_TL:    .byte 0
BEAT_TH:    .byte 0
BEAT_ENV:   .byte 0
BEAT_LEN = 1

; directions: 0 = up, clockwise, 16 steps; 0.8 px per step (8.8 signed)
DIRX_L:
  .byte $00,$4E,$91,$BD,$CD,$BD,$91,$4E,$00,$B2,$6F,$43,$33,$43,$6F,$B2
DIRX_H:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
DIRY_L:
  .byte $33,$43,$6F,$B2,$00,$4E,$91,$BD,$CD,$BD,$91,$4E,$00,$B2,$6F,$43
DIRY_H:
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF

; ==== RECORDS LIBRARY (dev/lib_records.asm) BEGIN ====

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
; ==== RECORDS LIBRARY END ====
