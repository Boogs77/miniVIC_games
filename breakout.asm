;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_BREAKOUT  -  Atari Breakout (1976)                  ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: lunar_lander (NMI + trampoline $0FD0, joystick VIA,  ;
;   bitmap shadow in RAM, AY sound engine)                     ;
;                                                              ;
;   - 8 rows x 14 bricks, two rows per colour as on the        ;
;     cabinet overlay: red 7, orange 5, green 3, yellow 1 pt   ;
;   - the ball speeds up after 4 and 12 paddle hits and the    ;
;     first time it reaches the orange and the red rows        ;
;   - the paddle shrinks to half when the ball breaks through  ;
;     and hits the top wall                                    ;
;   - 3 balls; clearing the first wall brings a second one,    ;
;     clearing both ends the game (896 points)                 ;
;   - 1 or 2 players taking turns, each with his own wall      ;
;   - joystick 1 ($D581) = player 1, joystick 2 ($D580) =      ;
;     player 2: LEFT / RIGHT = paddle (it speeds up while you  ;
;     hold), any button = serve                                ;
;   - title: button 1 = 1 player, button 2 = 2 players         ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     short beeps like the original: wall, paddle, a higher    ;
;     note for every brick colour, lost ball; no music, as on  ;
;     the cabinet. Stereo follows the ball.                    ;
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
CURP        = $85      ; player at the paddle (0-1)
BALLS       = $86      ; 2 bytes: balls left per player
SCL         = $88      ; 2 bytes: score per player, BCD low
SCH         = $8A      ; 2 bytes: score per player, BCD high
WALL        = $8C      ; 2 bytes: wall per player (0 first, 1 second)
LEFT        = $8E      ; 2 bytes: bricks left per player
HIL         = $90      ; hi score BCD low
HIH         = $91      ; hi score BCD high
BXL         = $92      ; ball position 8.8 (top-left corner of the 3x3 ball)
BXH         = $93
BYL         = $94
BYH         = $95
VXL         = $96      ; ball velocity per step 8.8 signed (VY must follow VX)
VXH         = $97
VYL         = $98
VYH         = $99
STEPS       = $9A      ; steps per frame = speed of the ball
HITS        = $9B      ; paddle hits of this ball
SPDF        = $9C      ; speed-ups already done: bit0 4 hits, bit1 12 hits, bit2 orange, bit3 red
PADX        = $9D      ; paddle: X of the left edge
PADW        = $9E      ; paddle width (24 or 12)
PACC        = $9F      ; paddle acceleration counter
BSTATE      = $A0      ; 0 = waiting for the serve, 1 = ball in play
ANG         = $A1      ; 0 shallow, 1 middle, 2 steep
JOYC        = $A2      ; joystick of the player at the paddle
FIRE_OLD    = $A3      ; buttons of the previous frame
LOST        = $A4      ; 1 = ball lost, 2 = both walls cleared
BRKP        = $A5      ; 2 bytes: bricks of the player at the paddle
BRK_R       = $A7      ; brick row 0-7 (0 = top)
BRK_C       = $A8      ; brick column 0-13
CX          = $A9      ; centre of the ball
CY          = $AA
STEPC       = $AB      ; steps left in this frame

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

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; not used by Breakout (kept for the shared engine)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709
PBUF       = $0710       ; 8 bytes: pattern of a cell being built

CMD_GAME   = 1           ; silence + game effects

; ---------------- RAM arrays ----------------
BRICKS = $0800           ; 112 bytes for player 1, 112 at $0880 for player 2 (1 = brick)
SH_PAT = $4000           ; copy of the screen (pattern) in RAM
SH_COL = $6000           ; copy of the colours

; ---------------- parameters ----------------
PLAY_X0     = 16         ; playfield: first X inside the side walls
BALL_XMAX   = 237        ; last X of the ball (240 - 3)
TOP_Y       = 20         ; first Y under the top wall
BRICK_Y0    = 40         ; first line of the bricks (cell row 5)
PADDLE_Y    = 176        ; top line of the paddle
SERVE_Y     = 96
PAD_COL     = $05        ; paddle colour: light blue (overlay of the cabinet)
BTN_MASK    = %00110000

; ---------------- records on the SD (lib_records.asm, at the end of the file) ----------------
REC_ZONE    = 7            ; fixed zone of the game in the save area
REC_RAM     = $7800        ; $2A0 bytes of free RAM
REC_ROW     = 10           ; table header on this row of the title, rows +1..+8 the table
REC_WIPEN   = 12           ; rows of the title that give way to the table
REC_JOY2    = 0            ; $FF = both joysticks sign, 0 = the player's own
REC_SROW    = 8            ; table header on the sign screen
REC_BMP     = 1            ; bitmap: characters through PUT_CHAR
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
SPR_PAGES = 1


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
  STA SCL
  STA SCL+1
  STA SCH
  STA SCH+1
  STA FRAME_CNT
  STA LAST_FRAME
  STA CURP
  LDA #$01
  STA NPL
  LDA #$A5
  STA RND
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_HISC
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE SCREEN
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR TITLE_PAGE
  JSR REC_TITLE
  JSR VDP_INT_ON
  BRA TITLE_REL

; the title page (VDP interrupt off)
TITLE_PAGE:
  LDA #$11
  STA CLRCOL
  JSR CLEAR_SCREEN
  JSR DRAW_BORDER
  LDA #$00
  STA CURP
  JSR SET_BRKP
  JSR FILL_BRICKS
  JSR DRAW_WALL
  LDA #$03                     ; the HUD shows "BALL 1"
  STA BALLS
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
  JMP DRAW_TEXT

; every 8 s / 5 s the title page and the table take turns (the table below the bricks)
TITLE_TICK:
  JSR WAIT_FRAME
  JSR REC_TICK
  BCC .tt_r
  JSR VDP_INT_OFF
  LDA REC_PG
  BEQ .tt_t
  JSR REC_SHOW
  BRA .tt_on
.tt_t:
  JSR TITLE_PAGE
.tt_on:
  JSR VDP_INT_ON
.tt_r:
  RTS

TITLE_REL:                     ; buttons released...
  JSR TITLE_TICK
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE TITLE_REL
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR TITLE_TICK
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
;  NEW GAME
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME
  STA SND_CMD
  LDX #$01
.ng_p:
  LDA #$00
  STA SCL,X
  STA SCH,X
  STA WALL,X
  STA BALLS,X
  LDA #112
  STA LEFT,X
  STX CURP
  JSR SET_BRKP
  JSR FILL_BRICKS
  DEX
  BPL .ng_p
  LDA #$03
  STA BALLS
  LDA NPL
  CMP #$02
  BNE .ng_1
  LDA #$03
  STA BALLS+1
.ng_1:
  LDA #$00
  STA CURP
  ; fall into PLAYER_START


; ===============================================================
;  TURN OF A PLAYER: his wall on the screen, then a new ball
; ===============================================================
PLAYER_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$11
  STA CLRCOL
  JSR CLEAR_SCREEN
  JSR DRAW_BORDER
  JSR SET_BRKP
  JSR DRAW_WALL
  JSR DRAW_HUD
  JSR VDP_INT_ON

NEW_BALL:
  LDX #$FF
  TXS
  LDA #$00
  STA BSTATE
  STA HITS
  STA SPDF
  STA PACC
  STA LOST
  LDA #$02
  STA STEPS
  LDA #24
  STA PADW
  LDA #116
  STA PADX
  LDA #BTN_MASK                ; a button already held does not serve
  STA FIRE_OLD
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  LDA #<TXT_SERVE
  STA TP
  LDA #>TXT_SERVE
  STA TP+1
  JSR DRAW_TEXT
  LDA NPL
  CMP #$02
  BNE .nb_1
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR DRAW_TEXT
  LDA #$B1
  STA TCOL
  LDA #12
  STA CELLR
  LDA #19
  STA CELLC
  LDA CURP
  CLC
  ADC #$31
  JSR PUT_CHAR
.nb_1:
  JSR BUILD_SAT
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
  JSR UPDATE_PADDLE
  LDA BSTATE
  BNE .gl_play
  JSR WAIT_SERVE
  BRA .gl_draw
.gl_play:
  JSR UPDATE_BALL
.gl_draw:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA LOST
  BNE .gl_lost
  JMP GAME_LOOP
.gl_lost:
  JMP BALL_LOST


; ---------------------------------------------------------------
; ball lost (LOST = 1) or both walls cleared (LOST = 2)
; ---------------------------------------------------------------
BALL_LOST:
  LDX #$FF
  TXS
  LDA LOST
  CMP #$02
  BEQ .bl_clear
  LDA #W_LOSE
  LDX #2
  JSR SFX_WHISTLE
  LDX CURP
  DEC BALLS,X
  BRA .bl_wait
.bl_clear:
  LDA #W_WALL2
  LDX #2
  JSR SFX_WHISTLE
  LDX CURP
  LDA #$00
  STA BALLS,X                  ; nothing left to break: this player has finished
.bl_wait:
  LDA #$00
  STA BSTATE
  JSR BUILD_SAT
  LDA #70
  JSR WAIT_FRAMES
  ; ---- who plays now?
  LDA NPL
  CMP #$02
  BNE .bl_same
  LDA CURP
  EOR #$01
  TAX
  LDA BALLS,X
  BEQ .bl_same
  STX CURP                     ; the other player: his wall on the screen
  JMP PLAYER_START
.bl_same:
  LDX CURP
  LDA BALLS,X
  BEQ .bl_over
  LDA NPL
  CMP #$02
  BNE .bl_nb
  JMP PLAYER_START             ; the other player has finished: redraw anyway
.bl_nb:
  JMP NEW_BALL
.bl_over:
  JMP GAME_OVER


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
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
  LDX #$00                     ; every player: into the table of the records?
.go_r:
  STX REC_PL
  LDA SCL,X
  STA REC_SC
  LDA SCH,X
  STA REC_SC+1
  STZ REC_SC+2
  STZ REC_SC+3
  LDA WALL,X                   ; extra byte: the wall (0 = the first)
  INC A
  STA REC_EX
  JSR REC_CHECK
  LDX REC_PL
  INX
  CPX NPL
  BNE .go_r
  LDA REC_DIRTY
  BEQ .go_press
  JSR REC_SAVE                 ; one write on the SD
  JSR REC_HISC
  JMP TITLE
.go_press:
  JSR WAIT_FIRE
  JMP TITLE

REC_CLR:                       ; rows of the table: black, then the border again
  PHA
  LDA #$11
  STA CLRCOL
  PLA
  JSR CLEAR_ROWS
  JMP DRAW_BORDER
REC_CLS:                       ; the sign screen: all black
  LDA #$11
  STA CLRCOL
  JMP CLEAR_SCREEN

; the best row of the table is the record of the title and the HUD
REC_HISC:
  LDA REC_TAB+0
  STA HIL
  LDA REC_TAB+1
  STA HIH
  RTS

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
  LDA #W_PADDLE
  BRA .rn_p
.rn_s:
  LDA #W_WALL2
.rn_p:
  JSR SFX_WHISTLE
  PLX
  RTS
REC_NAME:  .byte "BREAKOUT        "
REC_HEAD:  .byte "BEST PLAYERS",0
REC_XLBL:  .byte "WALL ",0



; ===============================================================
;  PADDLE
; ===============================================================
UPDATE_PADDLE:
  LDA JOYC
  AND #%00001100
  BNE .up_move
  STZ PACC                     ; released: starts slow again
  RTS
.up_move:
  LDA PACC
  CMP #16
  BCS .up_sp
  INC PACC
.up_sp:
  LSR A
  LSR A
  CLC
  ADC #$02
  STA T0                       ; speed 2-6 pixels per frame
  LDA JOYC
  AND #%00000100
  BEQ .up_right
  LDA PADX                     ; left
  SEC
  SBC T0
  BCC .up_lmin
  CMP #PLAY_X0
  BCS .up_set
.up_lmin:
  LDA #PLAY_X0
  BRA .up_set
.up_right:
  LDA #240                     ; right limit = 240 - width
  SEC
  SBC PADW
  STA T1
  LDA PADX
  CLC
  ADC T0
  CMP T1
  BCC .up_set
  LDA T1
.up_set:
  STA PADX
  RTS


; ===============================================================
;  SERVE
; ===============================================================
WAIT_SERVE:
  LDA JOYC
  AND #BTN_MASK
  TAX
  EOR FIRE_OLD
  AND JOYC                     ; just pressed
  STX FIRE_OLD
  AND #BTN_MASK
  BNE .ws_go
  RTS
.ws_go:
  LDA #<TXT_NOMSG              ; erase the messages
  STA TP
  LDA #>TXT_NOMSG
  STA TP+1
  JSR DRAW_TEXT
  LDA RND                      ; X = 40 + (0-127) + (0-63)
  AND #$7F
  STA T0
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC T0
  CLC
  ADC #40
  STA BXH
  LDA #SERVE_Y
  STA BYH
  LDA #$00
  STA BXL
  STA BYL
  JSR NEXT_RND
  LDA RND
  AND #$01
  STA ANG                      ; middle or shallow
  LDA RND
  AND #$02
  LSR A
  STA T6                       ; X direction at random
  LDA #$00
  STA T7                       ; downwards
  JSR SET_VEL
  LDA #$01
  STA BSTATE
  RTS


; ---------------------------------------------------------------
; velocity from ANG; T6 = 1 -> to the left, T7 = 1 -> upwards
; ---------------------------------------------------------------
SET_VEL:
  LDX ANG
  LDA VX_TAB,X
  STA VXL
  LDA #$00
  STA VXH
  LDA VY_TAB,X
  STA VYL
  LDA #$00
  STA VYH
  LDA T6
  BEQ .sv_x
  JSR NEG_VX
.sv_x:
  LDA T7
  BEQ .sv_y
  JSR NEG_VY
.sv_y:
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


; ===============================================================
;  BALL: STEPS small moves per frame (less than a pixel each)
; ===============================================================
UPDATE_BALL:
  LDA STEPS
  STA STEPC
.ub_l:
  JSR BALL_STEP
  LDA LOST
  BNE .ub_end
  DEC STEPC
  BNE .ub_l
.ub_end:
  RTS

BALL_STEP:
  ; ---- X and the side walls
  CLC
  LDA BXL
  ADC VXL
  STA BXL
  LDA BXH
  ADC VXH
  STA BXH
  LDA VXH
  BPL .bs_right
  LDA BXH
  CMP #PLAY_X0
  BCS .bs_y
  LDA #PLAY_X0
  BRA .bs_wall
.bs_right:
  LDA BXH
  CMP #(BALL_XMAX+1)
  BCC .bs_y
  LDA #BALL_XMAX
.bs_wall:
  STA BXH
  STZ BXL
  JSR NEG_VX
  LDA #W_WALL
  JSR BALL_SOUND
.bs_y:
  ; ---- Y and the top wall
  CLC
  LDA BYL
  ADC VYL
  STA BYL
  LDA BYH
  ADC VYH
  STA BYH
  LDA VYH
  BPL .bs_bricks
  LDA BYH
  CMP #TOP_Y
  BCS .bs_bricks
  LDA #TOP_Y
  STA BYH
  STZ BYL
  JSR NEG_VY
  LDA #W_WALL
  JSR BALL_SOUND
  LDA PADW                     ; broken through to the top: the paddle shrinks
  CMP #24
  BNE .bs_bricks
  LDA #12
  STA PADW
  LDA PADX
  CLC
  ADC #6                       ; keeps the centre where it was
  STA PADX
.bs_bricks:
  LDA BXH
  CLC
  ADC #1
  STA CX
  LDA BYH
  CLC
  ADC #1
  STA CY
  JSR CHECK_BRICK
  ; ---- paddle
  LDA VYH
  BMI .bs_lost
  LDA BYH
  CLC
  ADC #2                       ; bottom line of the ball
  CMP #PADDLE_Y
  BCC .bs_lost
  CMP #(PADDLE_Y+4)
  BCS .bs_lost
  LDA PADX
  SEC
  SBC #1
  CMP CX
  BEQ .bs_pok
  BCS .bs_lost                 ; ball left of the paddle
.bs_pok:
  LDA PADX
  CLC
  ADC PADW
  CMP CX
  BCC .bs_lost                 ; ball right of the paddle
  JMP PADDLE_HIT
.bs_lost:
  LDA BYH
  CMP #192
  BCC .bs_ret
  LDA #$01
  STA LOST
.bs_ret:
  RTS

; ---------------------------------------------------------------
; bounce on the paddle: 6 zones (outer = shallow, centre = steep)
; ---------------------------------------------------------------
PADDLE_HIT:
  LDA CX
  SEC
  SBC PADX
  BCS .ph_r0
  LDA #$00
.ph_r0:
  LDX PADW
  CPX #24
  BNE .ph_small
  LSR A                        ; 24 pixels: 4 per zone
.ph_small:
  LSR A                        ; 12 pixels: 2 per zone
  CMP #6
  BCC .ph_z
  LDA #5
.ph_z:
  TAX
  LDA ZONE_ANG,X
  STA ANG
  LDA ZONE_DIR,X
  STA T6
  LDA #$01
  STA T7                       ; upwards
  JSR SET_VEL
  LDA #(PADDLE_Y-3)
  STA BYH
  LDA #W_PADDLE
  JSR BALL_SOUND
  INC HITS
  LDA HITS
  CMP #4
  BNE .ph_12
  LDA #%00000001
  JMP SPEED_UP
.ph_12:
  CMP #12
  BNE .ph_ret
  LDA #%00000010
  JMP SPEED_UP
.ph_ret:
  RTS

; A = flag of the speed-up: only once per ball
SPEED_UP:
  STA T0
  AND SPDF
  BNE .su_ret
  LDA SPDF
  ORA T0
  STA SPDF
  INC STEPS
.su_ret:
  RTS

; A = whistle, on the speaker on the side of the ball
BALL_SOUND:
  LDX #$00
  LDY BXH
  BPL .bsn
  LDX #$01
.bsn:
  JMP SFX_WHISTLE


; ===============================================================
;  BRICKS
; ===============================================================
; is there a brick under (CX,CY)? then break it and bounce
CHECK_BRICK:
  LDA CY
  SEC
  SBC #BRICK_Y0
  BCC .cb_ret
  CMP #32
  BCS .cb_ret
  LSR A
  LSR A
  STA BRK_R                    ; row 0-7
  LDA CX
  SEC
  SBC #PLAY_X0
  BCC .cb_ret
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #14
  BCS .cb_ret
  STA BRK_C
  LDX BRK_R
  CLC
  ADC ROW14,X
  TAY
  LDA (BRKP),Y
  BNE .cb_hit
.cb_ret:
  RTS
.cb_hit:
  LDA #$00
  STA (BRKP),Y
  JSR NEG_VY
  JSR ERASE_BRICK
  ; ---- points and sound by colour
  LDA BRK_R
  LSR A
  TAX                          ; 0 red, 1 orange, 2 green, 3 yellow
  LDA ROW_PTS,X
  JSR ADD_POINTS
  LDA ROW_SND,X
  JSR BALL_SOUND
  ; ---- the first orange / red brick speeds the ball up
  LDA BRK_R
  CMP #4
  BCS .cb_cnt
  CMP #2
  BCS .cb_or
  LDA #%00001000
  JSR SPEED_UP
  BRA .cb_cnt
.cb_or:
  LDA #%00000100
  JSR SPEED_UP
.cb_cnt:
  LDX CURP
  DEC LEFT,X
  BNE .cb_end
  LDA WALL,X                   ; wall cleared
  BNE .cb_both
  INC WALL,X                   ; the second wall appears
  LDA #112
  STA LEFT,X
  JSR FILL_BRICKS
  JSR DRAW_WALL
  LDA #W_WALL2
  LDX #2
  JSR SFX_WHISTLE
  RTS
.cb_both:
  LDA #$02
  STA LOST
.cb_end:
  RTS

; erases the brick BRK_R / BRK_C (3 lines in two cells)
ERASE_BRICK:
  LDA BRK_R
  LSR A
  CLC
  ADC #5
  STA CELLR
  LDA BRK_C
  ASL A
  CLC
  ADC #2
  STA CELLC
  LDA BRK_R
  AND #$01
  ASL A
  ASL A
  STA T7                       ; first line inside the cell
  JSR .eb_cell
  INC CELLC
.eb_cell:
  JSR CELL_SETUP
  LDY T7
  LDA #$00
  STA (SPTR),Y
  INY
  STA (SPTR),Y
  INY
  STA (SPTR),Y
  JMP FLUSH_CELL

; all the bricks of the player at the paddle
FILL_BRICKS:
  LDY #111
  LDA #$01
.fb_l:
  STA (BRKP),Y
  DEY
  BPL .fb_l
  RTS

SET_BRKP:                      ; BRKP = bricks of CURP
  LDA #<BRICKS
  STA BRKP
  LDA CURP
  LSR A
  ROR A                        ; 0 or $80
  CLC
  ADC #<BRICKS
  STA BRKP
  LDA #>BRICKS
  STA BRKP+1
  RTS

; the whole wall of the player at the paddle (4 cell rows x 28 cells)
DRAW_WALL:
  LDA #$00
  STA T6                       ; cell row of bricks 0-3
.dw_row:
  LDA T6
  CLC
  ADC #5
  STA CELLR
  LDX T6
  LDA WALL_COL,X
  STA TCOL
  LDA #$00
  STA T5                       ; brick column 0-13
.dw_col:
  LDA T6                       ; upper brick: row 2*T6, lower: 2*T6+1
  ASL A
  TAX
  LDA ROW14,X
  CLC
  ADC T5
  TAY
  LDA (BRKP),Y
  STA T3
  LDA ROW14+1,X
  CLC
  ADC T5
  TAY
  LDA (BRKP),Y
  STA T4
  LDA T5
  ASL A
  CLC
  ADC #2
  STA CELLC
  LDA #$FF
  JSR BRICK_CELL
  INC CELLC
  LDA #$FE                     ; right half: one pixel of gap
  JSR BRICK_CELL
  INC T5
  LDA T5
  CMP #14
  BNE .dw_col
  INC T6
  LDA T6
  CMP #4
  BNE .dw_row
  RTS

; A = pattern of a full line, T3 / T4 = upper / lower brick present
BRICK_CELL:
  STA T2
  LDA #<PBUF
  STA PTR
  LDA #>PBUF
  STA PTR+1
  LDX #$00
  LDA T3
  BEQ .bc_u0
  LDA T2
.bc_u0:
  STA PBUF
  STA PBUF+1
  STA PBUF+2
  STX PBUF+3
  LDA T4
  BEQ .bc_l0
  LDA T2
.bc_l0:
  STA PBUF+4
  STA PBUF+5
  STA PBUF+6
  STX PBUF+7
  ; fall into FILL_CELL

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
;  WALLS AND HUD
; ===============================================================
DRAW_BORDER:
  LDA #$E1                     ; grey
  STA TCOL
  LDA #2
  STA CELLR
  LDA #<PAT_TOP
  STA PTR
  LDA #>PAT_TOP
  STA PTR+1
  LDA #2
  STA CELLC
.db_top:
  JSR FILL_CELL
  INC CELLC
  LDA CELLC
  CMP #30
  BNE .db_top
  LDA #<PAT_FULL
  STA PTR
  LDA #>PAT_FULL
  STA PTR+1
.db_side:
  LDA #1
  STA CELLC
  JSR FILL_CELL
  LDA #30
  STA CELLC
  JSR FILL_CELL
  INC CELLR
  LDA CELLR
  CMP #24
  BNE .db_side
  RTS

; scores, hi score, ball number (rows 0-1)
DRAW_HUD:
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR DRAW_TEXT
  LDA #0
  STA CELLR
  LDX #$00                     ; "1UP" bright for the player at the paddle
  JSR .dh_up
  LDX #$01
  JSR .dh_up
  LDA #$F1
  STA TCOL
  LDA #16
  STA CELLC
  LDA HIH
  JSR PUT_BCD
  LDA HIL
  JSR PUT_BCD
  JSR DRAW_SCORES
  LDA #1                       ; ball in play: 1-3
  STA CELLR
  LDA #18
  STA CELLC
  LDX CURP
  LDA #$34
  SEC
  SBC BALLS,X
  CMP #$34
  BCC .dh_b
  LDA #$33
.dh_b:
  JMP PUT_CHAR
.dh_up:
  LDA #$E1
  CPX CURP
  BNE .dh_c
  LDA #$B1
.dh_c:
  STA TCOL
  LDA UP_COL,X
  STA CELLC
  TXA
  CLC
  ADC #$31
  JSR PUT_CHAR
  INC CELLC
  LDA #$55
  JSR PUT_CHAR
  INC CELLC
  LDA #$50
  JMP PUT_CHAR

DRAW_SCORES:
  LDA #0
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

; A = points (BCD) for the player at the paddle
ADD_POINTS:
  PHX
  LDX CURP
  SED
  CLC
  ADC SCL,X
  STA SCL,X
  LDA SCH,X
  ADC #$00
  STA SCH,X
  CLD
  JSR DRAW_SCORES
  PLX
  RTS


; ===============================================================
;  SPRITES AND NMI
; ===============================================================
BUILD_SAT:
  LDA BSTATE                   ; ---- ball (sprite 0)
  BEQ .bs_noball
  LDA BYH
  SEC
  SBC #1
  STA SAT_BUFFER
  LDA BXH
  STA SAT_BUFFER+1
  BRA .bs_pad
.bs_noball:
  LDA #HIDE_Y
  STA SAT_BUFFER
.bs_pad:
  LDA #(PADDLE_Y-1)            ; ---- paddle (sprites 1-2)
  STA SAT_BUFFER+4
  LDA PADX
  STA SAT_BUFFER+5
  LDA PADW
  CMP #24
  BNE .bs_half
  LDA #4                       ; 16 + 8 pixels
  STA SAT_BUFFER+6
  LDA #(PADDLE_Y-1)
  STA SAT_BUFFER+8
  LDA PADX
  CLC
  ADC #16
  STA SAT_BUFFER+9
  RTS
.bs_half:
  LDA #12                      ; 12 pixels
  STA SAT_BUFFER+6
  LDA #HIDE_Y
  STA SAT_BUFFER+8
  RTS

HIDE_SPRITES:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  STA SAT_BUFFER+8
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
  CPX #13                 ; 3 sprites x 4 bytes + Y=$D0 of the 4th entry
  BNE .copy_sat
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

; SAT: 0 ball, 1-2 paddle, then Y=$D0 = end of list
SAT_BUFFER:    .byte HIDE_Y,$00,$00,$0F
               .byte HIDE_Y,$00,$04,PAD_COL
               .byte HIDE_Y,$00,$08,PAD_COL
               .byte $D0


; ===============================================================
;  SOUND: effects only (Breakout has no music)
;  Channel A of every chip plays the beeps (WH_* tables)
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
  LDA WH_ID,X
  BEQ .sf_next
  TAX
  LDA WH_START,X
  STA SN1
  LDA WH_LEN,X
  STA SN0
  LDX SND_T1
  LDA WH_POS,X
  CMP SN0
  BCS .sf_end
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
  BRA .sf_next
.sf_end:
  LDA #$00
  STA WH_ID,X
.sf_next:
  LDX SND_T1
  DEX
  BPL .sf_chip
  RTS


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
VX_TAB:     .byte $D0,$A8,$78          ; ball step 8.8: shallow, middle, steep
VY_TAB:     .byte $78,$A8,$D0
ZONE_ANG:   .byte 0,1,2,2,1,0          ; paddle zones, left to right
ZONE_DIR:   .byte 1,1,1,0,0,0          ; 1 = bounce to the left
ROW14:      .byte 0,14,28,42,56,70,84,98
ROW_PTS:    .byte $07,$05,$03,$01      ; red, orange, green, yellow (BCD)
ROW_SND:    .byte W_BRICK3,W_BRICK2,W_BRICK1,W_BRICK0
WALL_COL:   .byte $81,$91,$21,$B1      ; colour of the 4 cell rows of bricks
UP_COL:     .byte 1,23                 ; "1UP" / "2UP"
SCORE_COL:  .byte 5,27
PAT_TOP:    .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00
PAT_FULL:   .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_HUD:
  .byte 0,13,15,"HI",0
  .byte 1,13,14,"BALL",0
  .byte $FF
TXT_TITLE:
  .byte 15,6,15,"BUTTON 1 = 1 PLAYER",0
  .byte 17,6,15,"BUTTON 2 = 2 PLAYERS",0
  .byte 20,7,5,"JOYSTICK = PADDLE",0
  .byte 22,3,14,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_SERVE:
  .byte 14,10,15,"PRESS BUTTON",0
  .byte $FF
TXT_PLAYER:
  .byte 12,12,11,"PLAYER",0
  .byte $FF
TXT_NOMSG:
  .byte 12,10,15,"            ",0
  .byte 14,10,15,"            ",0
  .byte $FF
TXT_PRESS:
  .byte 18,9,15,"PRESS A BUTTON",0
  .byte $FF
; big words: row, column, number of letters, letters (B R E A K O U T G M V)
TITLE_BIG:
  .byte 11,8,8,0,1,2,3,4,5,6,7   ; BREAKOUT
  .byte $FF
OVER_BIG:
  .byte 11,12,4,8,3,9,2          ; GAME
  .byte 14,12,4,5,10,2,1         ; OVER
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
; big letters (16x16, 4 tiles each, 8 pattern + 8 colour bytes): B R E A K O U T G M V
BIGFONT:
  ; B
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $E0,$18,$18,$18,$18,$E0,$E0,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; R
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $E0,$80,$80,$60,$60,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; E
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$F8,$F8,$00,$00,$00,$00,$E0,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; A
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$80,$80,$60,$60,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $18,$F8,$F8,$18,$18,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; K
  .byte $00,$18,$18,$18,$18,$19,$19,$1E,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$18,$18,$60,$60,$80,$80,$00,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $1E,$19,$19,$18,$18,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $00,$80,$80,$60,$60,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; O
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; U
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; T
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$F8,$F8,$80,$80,$80,$80,$80,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; G
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$F8,$F8,$00,$00,$00,$00,$00,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $00,$78,$78,$18,$18,$F8,$F8,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; M
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$18,$18,$78,$78,$98,$98,$98,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $98,$18,$18,$18,$18,$18,$18,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  ; V
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$81,$81,$81,$81,$91,$91,$91,$91
  .byte $18,$06,$06,$06,$06,$01,$01,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1
  .byte $18,$60,$60,$60,$60,$80,$80,$00,$21,$21,$21,$21,$B1,$B1,$B1,$B1

; sprites 16x16: ball 3x3, paddle 16, paddle 8, paddle 12 (4 lines)
SPRITES:
  .byte $E0,$E0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$F0,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $00,$BD,$BD,$BD,$BD,$8E,$8E,$8E,$8E,$8E,$78,$78,$78,$78,$5F,$5F
  .byte $5F,$5F,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$39,$40,$47,$4F,$57,$60,$69,$73,$7D,$87,$93,$9F
  .byte $AB,$B9,$C7,$D7,$E7,$F9,$0C,$20,$36,$4E,$68,$85,$A4,$C7,$ED,$17
  .byte $47,$7D,$78,$78,$78,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F,$5F
  .byte $5F,$5F,$50,$50,$50,$50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03
  .byte $03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0A,$08,$06,$0D,$0B,$0A,$08,$06,$0D,$0B,$09,$07,$0D,$0B
  .byte $09,$07,$0D,$0B,$09,$07,$0D,$0B,$09,$07,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $07,$07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03
  .byte $02,$02,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$0C,$0C,$0B,$0B,$0A,$0A
  .byte $09,$09,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$0C,$0B,$0B,$0A,$09,$09
  .byte $08,$07,$07,$06,$05,$05,$04,$03,$03,$02
WH_START:
  .byte $00,$01,$05,$0A,$0E,$12,$16,$1A,$42
WH_LEN:
  .byte $00,$04,$05,$04,$04,$04,$04,$28,$28
W_WALL = 1
W_PADDLE = 2
W_BRICK0 = 3
W_BRICK1 = 4
W_BRICK2 = 5
W_BRICK3 = 6
W_LOSE = 7
W_WALL2 = 8

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$00
EX_NP:
  .byte $00,$00
EX_VC:
  .byte $00,$00
EX_TL:
  .byte $00,$00
EX_TH:
  .byte $00,$00
EX_START:
  .byte $00,$01
EX_LEN:
  .byte $00,$01
S_NONE = 1
S_BIG = S_NONE

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
