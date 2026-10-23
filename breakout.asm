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
  STA HIL
  STA HIH
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
  JSR DRAW_TEXT
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
  JSR WAIT_FIRE
  JMP TITLE


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
