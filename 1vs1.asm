;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_003  -  DAVIDE vs ELIA, 1 on 1 basketball  + SOUND  ;
;   65C02 assembly, TMS9918A Graphics II                       ;
;   Base: arcade_002 (NMI/vblank + SAT buffer, VDP, joystick)  ;
;                                                              ;
;   - P1 (DAVIDE) on PORTA $D581, attacks the right basket     ;
;     P2 (ELIA)   on PORTB $D580, attacks the left basket      ;
;   - joystick = move; any button (bit4 or bit5):              ;
;       with the ball -> SHOT (jump, the ball leaves at        ;
;                        the top of the jump)                  ;
;       without ball  -> JUMP: steals the ball if you are      ;
;                        close, or BLOCKS the shot if you jump ;
;                        right while the opponent shoots       ;
;   - inside the line = 2 points, beyond the arc = 3 points    ;
;   - after a basket the ball goes to the opponent             ;
;   - the first to reach WIN_SCORE (21) points wins            ;
;   - title: button 1 = 1 player against the computer (the     ;
;     computer plays ELIA), button 2 = 2 players               ;
;   - SOUND (2 x AY-3-8910): title song, basket scored,        ;
;     missed shot, dribbling, applause (basket, block,         ;
;     steal); at the end applause + cheers + song              ;
;   - all the graphics of the court are in the tables at       ;
;     the bottom (generated: court, sprites, jump and          ;
;     trajectory tables)                                       ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page (used to copy the VDP blocks) ----------------
VDP_INIT                 = $30
VDP_INIT_HI              = $31

; ---------------- zero page: data of the two players ----------------
; every entry takes 2 bytes: index X = 0 (DAVIDE) or 1 (ELIA)
P_X                      = $60     ; sprite X (left edge, sprite 16 wide)
P_FY                     = $62     ; Y of the feet (position on the court)
P_FACE                   = $64     ; 0 = facing right, 1 = facing left
P_JOY                    = $66     ; joystick, 1 = pressed
P_OLD                    = $68     ; buttons in the previous frame
P_EDGE                   = $6A     ; button just pressed
P_WALK                   = $6C     ; animation counter of the legs
P_JUMP                   = $6E     ; jump frames left (0 = on the ground)
P_COOL                   = $70     ; wait after the jump
P_SHOT                   = $72     ; 1 = the jump in progress is a shot
P_SCORE                  = $74     ; score

; ---------------- zero page: ball and game state ----------------
HOLDER                   = $76     ; who has the ball (valid if BSTATE = 0)
BSTATE                   = $77     ; 0 = in hand, 1 = shot in flight, 2 = loose, 3 = in the net
B_T                      = $78     ; frame counter of the phase
B_PTS                    = $79     ; points of the shot in flight (2 or 3)
B_MAKE                   = $7A     ; 1 = the shot goes in
SHOOTER                  = $7B     ; who shot
B_GXL                    = $7C     ; position of the ball on the ground, 8.8
B_GXH                    = $7D
B_GYL                    = $7E
B_GYH                    = $7F
B_VXL                    = $80     ; velocity per frame, 8.8 signed
B_VXH                    = $81
B_VYL                    = $82
B_VYH                    = $83
B_H                      = $84     ; height of the ball above the ground (pixels)
FREEZE                   = $85     ; pause frames (after a basket / at the start)
RND                      = $86
MSG_NEW                  = $87     ; message to write ($FF = none)
MSG_TMR                  = $88
HUD_DIRTY                = $89
WINNER                   = $8A
ARMED                    = $8B
GO_DELAY                 = $8C
DRB                      = $8D     ; phase of the dribble
CPU_ON                   = $8E     ; 1 = ELIA is played by the computer
AI_HAVE                  = $8F     ; computer: 1 = shooting spot chosen for this possession
T0                       = $90
T1                       = $91
T2                       = $92
T3                       = $93
T4                       = $94
T5                       = $95
T6                       = $96
T7                       = $97
PTR                      = $98     ; 2 bytes
AI_TX                    = $9A     ; computer: where it goes (centre of the feet)
AI_TY                    = $9B
AI_TMR                   = $9C     ; computer: frames left before it shoots anyway
AI_REACT                 = $9D     ; computer: block, frames left before the jump
AI_K                     = $9E     ; computer: joystick being built

PORTB_JOY = $d580        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 2
PORTA_JOY = $d581        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 1
DDRB_JOY  = $d582        ;
DDRA_JOY  = $d583        ;

; ---------------- game parameters ----------------
WIN_SCORE     = 21       ; points to win
SPEED_X       = 2        ; horizontal pixels per frame
SPEED_Y       = 1        ; vertical pixels per frame (perspective)
JUMP_LEN      = 24       ; length of the jump (frames)
RELEASE_AT    = 12       ; the ball leaves 12 frames before the end (top of the jump)
COOL_LEN      = 12       ; wait after a jump
BLOCK_LO      = 5        ; jump window of the defender who blocks the shot:
BLOCK_HI      = 19       ;   P_JUMP of the defender between BLOCK_LO and BLOCK_HI
CONTEST_DX    = 26       ; defender "on him": largest distance along X ...
CONTEST_DY    = 14       ; ... and along Y
CONTEST_PEN   = 50       ; penalty on the probability when the shot is contested
STEAL_DX      = 18       ; steal: largest distance
STEAL_DY      = 10
STEAL_PROB    = 128      ; probability of a steal (out of 256)
PROB_KEY      = 200      ; probability of scoring: under the basket (paint)
PROB_MID      = 150      ;   from inside the arc (2 points)
PROB_FAR      = 100      ;   from beyond the arc (3 points)
FY_MIN        = 64       ; vertical limits (feet)
FY_MAX        = 188
RIM_GY        = 105      ; ground row under the rim (rim = 72, height 30, ball radius 3)
H_START       = 36       ; height of the ball when shot
BLOCK_AWAY    = 22       ; how far a blocked ball bounces back
RIM_BACK      = 18       ; bounce on the rim: minimum distance from the basket
FREEZE_FRAMES = 50
MSG_FRAMES    = 90
HIDE_Y        = $C0      ; off-screen Y (NOT $D0: it would stop the sprite list)
BTN_MASK      = %00110000
AI_STEAL      = 5        ; computer: chance of a steal attempt per frame (out of 256)

D_START_X     = 92       ; starting positions (Davide on the left, Elia on the right)
D_START_Y     = 118
E_START_X     = 132
E_START_Y     = 126

; messages (index in the MSG_TAB table)
MSG_P_DAVIDE  = 1
MSG_P_ELIA    = 2
MSG_2         = 3
MSG_3         = 4
MSG_BLOCK     = 5
MSG_STEAL     = 6

; names of the sprites (pattern = index * 4)
SPR_TOP_IDLE  = 8
SPR_TOP_SHOOT = 12
SPR_TOP_DEF   = 16
SPR_BOT_A     = 32
SPR_BOT_B     = 36
SPR_BOT_JUMP  = 40
SPR_LEFT_ADD  = 12       ; the frames facing left are 12 patterns further on

BLOCK_COUNT   = 7        ; blocchi in VDP_BLOCKS
BIG0          = $80      ; big digits 0-9: 4 tiles each (top-left, top-right, bottom-left, bottom-right)


; ---------------- sound: ports of the two AY-3-8910 (as in tank_sound.asm) ----------------
AY_R_LATCH = $D380       ; right AY  (Elia)
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY (Davide)
AY_L_WRITE = $D385

; ---------------- zero page: sound (all played by SND_TICK, called by the NMI) ----------------
SH_L       = $A0         ; shadow of the left AY registers 0-10  (11 bytes)
SH_R       = $B0         ; shadow of the right AY registers 0-10  (SH_R = SH_L + 16)
SND_STAGE  = $BB         ; ending: 0 = applause, 1 = cheers
SND_T2     = $BC         ; ending: frames elapsed in the phase
SND_CMD    = $C0         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $C1         ; 0 = game effects, 1 = song, 2 = applause + final cheers
SND_BUSY   = $C2         ; 1 while the song (or the ending) is playing
SFX_REQ    = $C3         ; effect request (EVT_*), 0 = none
SFX_EVT    = $C4         ; effect playing (0 = none)
SFX_STEP   = $C5         ; frames elapsed in the effect
SFX_DRIB   = $C6         ; dribble: 2 bytes (Davide / Elia), step 1..6 (0 = off)
SND_PH     = $C8         ; phase (counts the frames)
SND_RND    = $C9
SN0        = $CA         ; sound temporaries
SN1        = $CB
SND_T1     = $CC
SFX_APPL   = $CD         ; applause: frames elapsed (0 = off)
SFX_ADLY   = $CE         ; frames left before the applause starts
TR_PL      = $D0         ; 4 tracks: pointer (lo / hi), counter, active,
TR_PH      = $D4         ;           note, volume, age of the note
TR_CT      = $D8
TR_ACT     = $DC
TR_NOTE    = $E0
TR_VOL     = $E4
TR_AGE     = $E8
SND_PTR    = $EC         ; 2 bytes

CMD_GAME   = 1           ; silence + game effects
CMD_TITLE  = 2           ; title song
CMD_WIN    = 3           ; applause + cheers + victory song

EVT_SCORE  = 1           ; basket scored (+ applause)
EVT_MISS   = 2           ; missed shot (rim)
EVT_BLOCK  = 3           ; block (+ applause)
EVT_STEAL  = 4           ; ball stolen (+ applause)

APPL_LEN       = 96      ; length of the applause during the game (frames)
CELEB_APPL_LEN = 150     ; final applause (frames)
CHEER_LEN      = 112     ; final cheers (frames)
DRIB_LEN       = 6       ; length of the thud of the dribble (frames)

 .org $0FD0               ; trampoline called by NMI_HANDLER (bios) with JSR $0FD0
DISPATCH:
  JMP NMI_TASK


 .org $1000
VREG  = $B001                ;VDP REGISTER
VDATA = $B000                ;VDP RAM

VDP_NAME_TABLE_BASE    = $3800      ; NAME TABLE
VDP_COLOR_TABLE_BASE   = $2000      ; COLOR TABLE
VDP_PATTERN_TABLE_BASE = $0000      ; PATTERN TABLE
VDP_SPRITE_ATT_BASE    = $3B00      ; SPRITE ATT
VDP_SPRITE_TABLE_BASE  = $1800      ; SPRITE TABLE

VDP_WRITE_VRAM_BIT     = %01000000  ; pattern of second vram address write: 01AAAAAA
VDP_REGISTER_BITS      = %10000000  ; pattern of second register write: 10000RRR

RESET:
  JSR VDP_SET_REGISTERS        ; Setting VDP register
  JSR CLEAR_VRAM
  JSR VDP_LOAD_ALL             ; patterns, colours and sprites into the VRAM

  ; joystick: PORTA and PORTB as inputs
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY

  LDA #$00
  STA P_SCORE
  STA P_SCORE+1
  STA HUD_DIRTY
  STA FREEZE
  STA CPU_ON
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES

  JSR SND_INIT                 ; AY silent (the VDP interrupt is still off)

  ; enable the VDP interrupt (R1: 16K + display ON + INT ON = $E6)
  LDA #$E6
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JMP TITLE


; ===============================================================
;  START SCREEN
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF              ; from now on the main loop can write the VDP
  JSR CLEAR_NAME_TABLE
  LDA #<TITLE_REC
  STA PTR
  LDA #>TITLE_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDA #$01                     ; the title song starts ...
  STA SND_BUSY
  LDA #CMD_TITLE
  STA SND_CMD
.ti_song:
  JSR WAIT_FRAME               ; ... the button is not read while it plays
  LDA SND_BUSY
  BNE .ti_song
  JSR VDP_INT_OFF
  LDA #<TITLE_PRESS
  STA PTR
  LDA #>TITLE_PRESS
  STA PTR+1
  JSR DRAW_RECORDS             ; compare "PRESS A BUTTON"
  JSR VDP_INT_ON
  JSR WAIT_FIRE
  LDA FRAME_CNT                ; the moment you press the button seeds the random generator
  ORA #$01
  STA RND
  LDA P_JOY                    ; button 1 = against the computer, button 2 = 2 players
  ORA P_JOY+1
  AND #%00010000
  BEQ .ti_two
  LDA #$01
.ti_two:
  STA CPU_ON
  JMP NEW_GAME


; ===============================================================
;  NEW GAME
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME                ; silence, game effects
  STA SND_CMD
  LDA #$00
  STA P_SCORE
  STA P_SCORE+1
  STA HUD_DIRTY
  STA MSG_TMR
  STA P_OLD
  STA P_OLD+1
  STA DRB
  LDA #$FF
  STA MSG_NEW
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR LOAD_GAME_NAME_TABLE     ; court + names
  JSR DRAW_HUD                 ; big scores beside the names
  JSR VDP_INT_ON
  JSR NEXT_RND                 ; the first possession is random
  LDA RND
  AND #$01
  JSR START_POSS
  JSR DRAW_ALL

GAME_LOOP:
  JSR READ_JOY
  LDA CPU_ON
  BEQ .gl_human
  JSR CPU_AI                   ; the computer writes the joystick of ELIA
.gl_human:
  LDA FREEZE
  BEQ .gl_active
  DEC FREEZE                   ; pause: everything still, only the dribble
  LDA P_JOY
  AND #BTN_MASK
  STA P_OLD
  LDA P_JOY+1
  AND #BTN_MASK
  STA P_OLD+1
  JSR UPDATE_BALL
  BRA .gl_draw
.gl_active:
  JSR NEXT_RND
  LDX #0
  JSR UPDATE_PLAYER
  LDX #1
  JSR UPDATE_PLAYER
  JSR UPDATE_BALL
.gl_draw:
  JSR DRAW_ALL
  JSR WAIT_FRAME               ; syncs the loop to the vblank (NMI)
  LDA HUD_DIRTY
  BEQ .gl_msg
  LDA #$00
  STA HUD_DIRTY
  JSR UPDATE_HUD
.gl_msg:
  LDA MSG_TMR
  BEQ .gl_pend
  DEC MSG_TMR
  BNE .gl_pend
  LDA #$00                     ; time over: erase the message
  STA MSG_NEW
.gl_pend:
  LDA MSG_NEW
  CMP #$FF
  BEQ .gl_again
  JSR DRAW_MSG
  LDA #$FF
  STA MSG_NEW
.gl_again:
  JMP GAME_LOOP


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


NEXT_RND:                      ; LFSR a 8 bit
  LDA RND
  ASL A
  BCC .nr_ok
  EOR #$1D
.nr_ok:
  STA RND
  RTS


; ---------------------------------------------------------------
; computer player: writes the joystick of ELIA (P_JOY+1)
; - attack: walks to a shooting spot chosen at random (paint,
;   inside the arc, beyond the arc) and shoots there, or anyway
;   when its time is over
; - defence: stays between DAVIDE and the right basket, a bit
;   slower than him; now and then tries a steal when close; when
;   DAVIDE shoots it jumps after a random reaction time (fast
;   enough = block)
; - ball loose or in flight: runs after it
; ---------------------------------------------------------------
CPU_AI:
  LDA #$00
  STA AI_K
  LDA FREEZE                    ; pause: stands still, new spot next time
  BEQ .ai_go
  STA AI_HAVE
  STA P_JOY+1
  RTS
.ai_go:
  LDA BSTATE
  BEQ .ai_held
  STZ AI_HAVE                   ; ball loose: runs after it
  CMP #$03
  BNE .ai_loose
  JMP .ai_out                   ; in the net
.ai_loose:
  LDA B_GXH
  STA AI_TX
  LDA B_GYH
  STA AI_TY
  JSR AI_GOTO
  JMP .ai_out
.ai_held:
  LDA HOLDER
  BEQ .ai_defend
  ; ---- attack ----
  LDA AI_HAVE
  BNE .ai_att
  INC AI_HAVE                   ; new possession: shooting spot and time
  LDA RND
  AND #$07
  TAY
  LDA SPOT_X,Y
  STA AI_TX
  LDA SPOT_Y,Y
  STA AI_TY
  LDA RND
  LSR A
  LSR A
  AND #$3F
  CLC
  ADC #120
  STA AI_TMR
.ai_att:
  LDA P_JUMP+1                  ; in the air: nothing to do
  BNE .ai_out
  DEC AI_TMR
  BEQ .ai_shoot
  JSR AI_GOTO
  LDA AI_K
  BNE .ai_out                   ; not there yet
.ai_shoot:
  LDA #$01                      ; shoots (again at the next frame if refused)
  STA AI_TMR
  JSR AI_PRESS
  BRA .ai_out
  ; ---- defence ----
.ai_defend:
  STZ AI_HAVE
  LDA P_SHOT                    ; DAVIDE shoots: block after the reaction time
  BEQ .ai_noshot
  LDA AI_REACT
  BNE .ai_react
  LDA RND
  AND #$0F
  CLC
  ADC #2
  STA AI_REACT
.ai_react:
  CMP #$01
  BEQ .ai_out                   ; jump already tried
  DEC AI_REACT
  LDA AI_REACT
  CMP #$01
  BNE .ai_out
  JSR AI_PRESS
  BRA .ai_out
.ai_noshot:
  STZ AI_REACT
  LDA P_X                       ; guard spot: on the right of DAVIDE
  CLC
  ADC #(8+12)
  BCS .ai_gmax
  CMP #230
  BCC .ai_gx
.ai_gmax:
  LDA #230
.ai_gx:
  STA AI_TX
  LDA P_FY
  STA AI_TY
  LDA RND                       ; a bit slower than DAVIDE
  AND #$07
  BEQ .ai_steal
  JSR AI_GOTO
.ai_steal:
  LDX #$01                      ; close to DAVIDE: steal attempt now and then
  JSR DIST_OTHER
  LDA T0
  CMP #STEAL_DX
  BCS .ai_out
  LDA T1
  CMP #STEAL_DY
  BCS .ai_out
  LDA RND
  CMP #AI_STEAL
  BCS .ai_out
  JSR AI_PRESS
.ai_out:
  LDA AI_K
  STA P_JOY+1
  RTS

; button, only if it gives a rising edge and ELIA can act
AI_PRESS:
  LDA P_OLD+1
  ORA P_COOL+1
  ORA P_JUMP+1
  BNE .ap_end
  LDA AI_K
  ORA #%00010000
  STA AI_K
.ap_end:
  RTS

; directions towards (AI_TX, AI_TY) for the centre of the feet of ELIA
; (AI_K stays 0 when it is there)
AI_GOTO:
  LDA P_X+1
  CLC
  ADC #8
  SEC
  SBC AI_TX
  BCS .ag_r
  CMP #$FE                      ; on the left of the spot
  BCS .ag_y
  LDA #%00001000
  BRA .ag_x
.ag_r:
  CMP #$03                      ; on the right of the spot
  BCC .ag_y
  LDA #%00000100
.ag_x:
  ORA AI_K
  STA AI_K
.ag_y:
  LDA P_FY+1
  SEC
  SBC AI_TY
  BCS .ag_d
  CMP #$FF                      ; above the spot
  BCS .ag_end
  LDA #%00000010
  BRA .ag_set
.ag_d:
  CMP #$02                      ; below the spot
  BCC .ag_end
  LDA #%00000001
.ag_set:
  ORA AI_K
  STA AI_K
.ag_end:
  RTS

; shooting spots of ELIA (left basket): 2 in the paint, 3 inside the arc, 3 beyond
SPOT_X:        .byte 34, 40, 66, 50, 50, 100, 78, 78
SPOT_Y:        .byte 127, 136, 127, 100, 154, 127, 84, 170


; ---------------------------------------------------------------
; start of a possession: A = who has the ball (0 = Davide, 1 = Elia).
; Puts the players back in place: Davide attacks to the right, so
; his defender (Elia) stands on his right; and vice versa.
; ---------------------------------------------------------------
START_POSS:
  STA HOLDER
  LDA #$00
  STA BSTATE
  STA P_JUMP
  STA P_JUMP+1
  STA P_COOL
  STA P_COOL+1
  STA P_SHOT
  STA P_SHOT+1
  STA P_WALK
  STA P_WALK+1
  STA P_FACE                   ; Davide faces right
  LDA #$01
  STA P_FACE+1                 ; Elia faces left
  LDA #D_START_X
  STA P_X
  LDA #D_START_Y
  STA P_FY
  LDA #E_START_X
  STA P_X+1
  LDA #E_START_Y
  STA P_FY+1
  LDA #FREEZE_FRAMES
  STA FREEZE
  LDA HOLDER
  CLC
  ADC #MSG_P_DAVIDE            ; 1 = BALL TO DAVIDE, 2 = BALL TO ELIA
  JMP SHOW_MSG

SHOW_MSG:                      ; A = message index
  STA MSG_NEW
  LDA #MSG_FRAMES
  STA MSG_TMR
  RTS


; ---------------------------------------------------------------
; distance between player X and the other one: T0 = |dx|, T1 = |dy|  (X preserved)
; ---------------------------------------------------------------
DIST_OTHER:
  LDA P_X,X
  STA T2
  LDA P_FY,X
  STA T3
  TXA
  EOR #$01
  TAX
  LDA P_X,X
  SEC
  SBC T2
  BCS .do_x
  EOR #$FF
  CLC
  ADC #$01
.do_x:
  STA T0
  LDA P_FY,X
  SEC
  SBC T3
  BCS .do_y
  EOR #$FF
  CLC
  ADC #$01
.do_y:
  STA T1
  TXA
  EOR #$01
  TAX
  RTS

; distance between the feet of player X and the ball: T0 = |dx|, T1 = |dy|
DIST_BALL:
  LDA P_X,X
  CLC
  ADC #8                       ; centre of the sprite
  SEC
  SBC B_GXH
  BCS .db_x
  EOR #$FF
  CLC
  ADC #$01
.db_x:
  STA T0
  LDA P_FY,X
  SEC
  SBC B_GYH
  BCS .db_y
  EOR #$FF
  CLC
  ADC #$01
.db_y:
  STA T1
  RTS


; ---------------------------------------------------------------
; updates a player: X = player (0/1)
; ---------------------------------------------------------------
UPDATE_PLAYER:
  LDA P_JOY,X                  ; rising edge of the button
  AND #BTN_MASK
  STA T0
  LDA P_OLD,X
  EOR #$FF
  AND T0
  STA P_EDGE,X
  LDA T0
  STA P_OLD,X
  LDA P_COOL,X
  BEQ .up_nocool
  DEC P_COOL,X
.up_nocool:
  LDA P_JUMP,X
  BEQ .up_ground
  ; ---- in the air: no movement, the jump goes on ----
  DEC P_JUMP,X
  BNE .up_air
  LDA #COOL_LEN
  STA P_COOL,X
  LDA #$00
  STA P_SHOT,X
  RTS
.up_air:
  LDA P_SHOT,X
  BEQ .up_end
  LDA P_JUMP,X
  CMP #RELEASE_AT
  BNE .up_end
  JMP SHOT_RELEASE             ; top of the jump: the ball leaves
.up_end:
  RTS
.up_ground:
  LDA P_EDGE,X
  BEQ .up_move
  LDA P_COOL,X
  BNE .up_move
  JMP START_ACTION             ; shot or jump
.up_move:
  LDA P_JOY,X
  AND #%00001111
  BNE .up_dirs
  LDA #$00
  STA P_WALK,X                 ; standing: legs in the base position
  RTS
.up_dirs:
  LDA P_JOY,X
  AND #%00001000               ; right
  BEQ .up_nr
  LDA P_X,X
  CLC
  ADC #SPEED_X
  STA P_X,X
  LDA #$00
  STA P_FACE,X
.up_nr:
  LDA P_JOY,X
  AND #%00000100               ; left
  BEQ .up_nl
  LDA P_X,X
  SEC
  SBC #SPEED_X
  STA P_X,X
  LDA #$01
  STA P_FACE,X
.up_nl:
  LDA P_JOY,X
  AND #%00000001               ; up
  BEQ .up_nu
  LDA P_FY,X
  SEC
  SBC #SPEED_Y
  STA P_FY,X
.up_nu:
  LDA P_JOY,X
  AND #%00000010               ; giu'
  BEQ .up_nd
  LDA P_FY,X
  CLC
  ADC #SPEED_Y
  STA P_FY,X
.up_nd:
  INC P_WALK,X
  ; ---- edges of the court (a trapezoid: the sides are slanted) ----
  LDA P_FY,X
  CMP #FY_MIN
  BCS .up_c1
  LDA #FY_MIN
  STA P_FY,X
.up_c1:
  CMP #(FY_MAX+1)
  BCC .up_c2
  LDA #FY_MAX
  STA P_FY,X
.up_c2:
  LDA P_FY,X
  SEC
  SBC #FY_MIN
  TAY
  LDA XMIN_TAB,Y
  STA T0
  LDA P_X,X
  CMP T0
  BCS .up_c3
  LDA T0
  STA P_X,X
.up_c3:
  LDA #240
  SEC
  SBC T0                       ; XMAX = 240 - XMIN
  STA T0
  LDA P_X,X
  CMP T0
  BCC .up_c4
  BEQ .up_c4
  LDA T0
  STA P_X,X
.up_c4:
  RTS


; ---------------------------------------------------------------
; button pressed on the ground: X = player
;   with the ball -> starts the shot; without -> jump (steal / block)
; ---------------------------------------------------------------
START_ACTION:
  LDA #JUMP_LEN
  STA P_JUMP,X
  LDA BSTATE
  BNE .sa_def
  CPX HOLDER
  BNE .sa_def
  LDA #$01                     ; shot
  STA P_SHOT,X
  TXA                          ; turns towards his basket: Davide (0) to the right, Elia (1) to the left
  STA P_FACE,X
  RTS
.sa_def:
  LDA #$00
  STA P_SHOT,X
  LDA BSTATE
  BNE .sa_end                  ; ball in nobody's hands
  TXA
  EOR #$01
  TAX                          ; X = who has the ball
  LDA P_SHOT,X
  STA T7                       ; already shooting? (ball raised, cannot be stolen)
  TXA
  EOR #$01
  TAX                          ; X = defender
  LDA T7
  BNE .sa_end
  JSR DIST_OTHER
  LDA T0
  CMP #STEAL_DX
  BCS .sa_end
  LDA T1
  CMP #STEAL_DY
  BCS .sa_end
  JSR NEXT_RND
  LDA RND
  CMP #STEAL_PROB
  BCS .sa_end
  STX HOLDER                   ; ball stolen
  LDA #MSG_STEAL
  JSR SHOW_MSG
  LDA #EVT_STEAL               ; sound + applause
  STA SFX_REQ
.sa_end:
  RTS


; ---------------------------------------------------------------
; shooting zone of player X: A = probability (0-255), B_PTS = 2 or 3
; uses T0-T3.  Player 0 attacks to the right, player 1 to the left.
; The arc is an ellipse (ARCDX_TAB[dy] = half axis in X at distance dy
; from the centre of the arc); the paint is dx < 54 and dy < 20.
; ---------------------------------------------------------------
CALC_ZONE:
  LDA P_X,X
  CLC
  ADC #8
  STA T2                       ; X of the centre of the feet
  CPX #$00
  BNE .cz_left
  LDA #251                     ; right arc: centre at 255-4
  SEC
  SBC T2
  BRA .cz_dx
.cz_left:
  LDA T2
  SEC
  SBC #4                       ; left arc: centre at 4
.cz_dx:
  STA T0                       ; distance from the centre of the arc along X
  LDA P_FY,X
  SEC
  SBC #127                     ; vertical centre of the arc
  BCS .cz_dy
  EOR #$FF
  CLC
  ADC #$01
.cz_dy:
  STA T1
  LDA T0                       ; area
  CMP #54
  BCS .cz_notkey
  LDA T1
  CMP #20
  BCS .cz_notkey
  LDA #$02
  STA B_PTS
  LDA #PROB_KEY
  RTS
.cz_notkey:
  LDA T1
  CMP #63
  BCS .cz_three
  TAY
  LDA ARCDX_TAB,Y
  CMP T0
  BCS .cz_two                  ; inside the ellipse
.cz_three:
  LDA #$03
  STA B_PTS
  LDA #PROB_FAR
  RTS
.cz_two:
  LDA #$02
  STA B_PTS
  LDA #PROB_MID
  RTS


; (T4 - T5) << T6  ->  T1:T0  (16 bit signed; T6 = 3 or 4)
VEL_CALC:
  LDA T4
  SEC
  SBC T5
  STA T0
  LDA #$00
  SBC #$00
  STA T1
  LDY T6
.vc_sh:
  ASL T0
  ROL T1
  DEY
  BNE .vc_sh
  RTS


; ---------------------------------------------------------------
; top of the jump: the ball leaves.  X = shooter
; ---------------------------------------------------------------
SHOT_RELEASE:
  LDA #$00
  STA P_SHOT,X
  STA T6                       ; T6 = 1 if the shot is contested
  JSR DIST_OTHER               ; T0/T1 = distance from the defender
  LDA T0
  CMP #CONTEST_DX
  BCS .sr_free
  LDA T1
  CMP #CONTEST_DY
  BCS .sr_free
  LDA #$01
  STA T6
  TXA                          ; is the defender jumping at the right moment?
  EOR #$01
  TAX
  LDA P_JUMP,X
  STA T7
  TXA
  EOR #$01
  TAX
  LDA T7
  CMP #BLOCK_LO
  BCC .sr_free
  CMP #(BLOCK_HI+1)
  BCS .sr_free
  JMP BLOCK_SHOT               ; STOPPATA
.sr_free:
  JSR CALC_ZONE                ; B_PTS and base probability
  STA T7
  LDA T6
  BEQ .sr_roll
  LDA T7                       ; contested: lower probability
  SEC
  SBC #CONTEST_PEN
  BCS .sr_pen
  LDA #$00
.sr_pen:
  STA T7
.sr_roll:
  JSR NEXT_RND
  LDA RND
  CMP T7
  LDA #$00
  BCS .sr_set                  ; random >= probability: miss
  LDA #$01
.sr_set:
  STA B_MAKE
  STX SHOOTER
  LDA #$01
  STA BSTATE
  LDA #$00
  STA B_T
  STA B_GXL
  STA B_GYL
  LDA P_X,X
  CLC
  ADC #8
  STA B_GXH
  STA T5
  LDA HOOPX,X
  STA T4
  LDA #$03
  STA T6
  JSR VEL_CALC                 ; 32 frames of flight: velocity = difference * 8 (in 8.8)
  LDA T0
  STA B_VXL
  LDA T1
  STA B_VXH
  LDA P_FY,X
  STA B_GYH
  STA T5
  LDA #RIM_GY
  STA T4
  JSR VEL_CALC
  LDA T0
  STA B_VYL
  LDA T1
  STA B_VYH
  LDA #H_START
  STA B_H
  RTS


; blocked shot: the ball goes back and becomes loose. X = shooter
BLOCK_SHOT:
  STX SHOOTER
  LDA #$02
  STA BSTATE
  LDA #$00
  STA B_T
  STA B_GXL
  STA B_GYL
  LDA P_X,X
  CLC
  ADC #8
  STA B_GXH
  STA T5
  CPX #$00
  BNE .bl_l
  LDA T5
  CMP #(16+BLOCK_AWAY)
  BCC .bl_min
  SEC
  SBC #BLOCK_AWAY
  BRA .bl_x
.bl_min:
  LDA #16
  BRA .bl_x
.bl_l:
  LDA T5
  CMP #(240-BLOCK_AWAY)
  BCS .bl_max
  CLC
  ADC #BLOCK_AWAY
  BRA .bl_x
.bl_max:
  LDA #239
.bl_x:
  STA T4
  LDA #$04
  STA T6
  JSR VEL_CALC                 ; 16 frames: velocity = difference * 16
  LDA T0
  STA B_VXL
  LDA T1
  STA B_VXH
  LDA P_FY,X
  STA B_GYH
  LDA #$00
  STA B_VYL
  STA B_VYH
  LDA #30
  STA B_H
  LDA #EVT_BLOCK               ; sound + applause
  STA SFX_REQ
  LDA #MSG_BLOCK
  JMP SHOW_MSG


; ---------------------------------------------------------------
; the ball: UPDATE_BALL by BSTATE
; ---------------------------------------------------------------
UPDATE_BALL:
  LDA BSTATE
  BEQ .ub_held
  CMP #$01
  BEQ .ub_flight
  CMP #$02
  BEQ .ub_loose
  JMP .ub_net
.ub_held:
  LDX HOLDER
  LDA P_X,X
  CLC
  ADC #8
  STA T0
  LDA P_FACE,X
  BNE .ub_hl
  LDA T0
  CLC
  ADC #10
  BRA .ub_hx
.ub_hl:
  LDA T0
  SEC
  SBC #10
.ub_hx:
  STA B_GXH
  LDA P_FY,X
  CLC
  ADC #2
  STA B_GYH
  LDA P_JUMP,X
  BEQ .ub_dribble
  TAY                          ; jumping: the ball is over the head
  LDA JUMP_H,Y
  CLC
  ADC #H_START
  STA B_H
  RTS
.ub_dribble:
  INC DRB
  LDA DRB
  AND #$0F
  TAY
  LDA DRIB_TAB,Y
  STA B_H
  CPY #8                       ; the ball touches the ground: thud on the chip of the dribbling player
  BNE .ub_dr_end
  LDA #$01
  STA SFX_DRIB,X
.ub_dr_end:
  RTS

.ub_flight:
  JSR MOVE_BALL
  INC B_T
  LDY B_T
  LDA HT_TAB,Y
  STA B_H
  CPY #32
  BNE .ub_fl_end
  JSR SHOT_END
.ub_fl_end:
  RTS

.ub_loose:
  LDA B_T
  CMP #16
  BCS .ub_rest
  JSR MOVE_BALL
  INC B_T
  LDY B_T
  LDA BNC_TAB,Y
  STA B_H
  BRA .ub_pick
.ub_rest:
  LDA #$00
  STA B_H
.ub_pick:
  LDA B_T                      ; the ball can be picked up only when it is low
  CMP #9
  BCC .ub_pk_end
  LDX #$00
.ub_pk:
  LDA P_JUMP,X
  BNE .ub_pk_next
  JSR DIST_BALL
  LDA T0
  CMP #12
  BCS .ub_pk_next
  LDA T1
  CMP #9
  BCS .ub_pk_next
  STX HOLDER                   ; ball picked up
  LDA #$00
  STA BSTATE
  RTS
.ub_pk_next:
  INX
  CPX #$02
  BNE .ub_pk
.ub_pk_end:
  RTS

.ub_net:                       ; the ball falls into the net
  INC B_T
  LDY B_T
  LDA NET_TAB,Y
  STA B_H
  CPY #12
  BNE .ub_net_end
  LDX SHOOTER                  ; end of the action: victory or new possession
  LDA P_SCORE,X
  CMP #WIN_SCORE
  BCC .ub_next
  STX WINNER
  JMP GAME_OVER
.ub_next:
  TXA
  EOR #$01
  JMP START_POSS               ; the ball goes to the opponent
.ub_net_end:
  RTS

; position on the ground += velocity (16 bit signed, 8.8)
MOVE_BALL:
  LDA B_GXL
  CLC
  ADC B_VXL
  STA B_GXL
  LDA B_GXH
  ADC B_VXH
  STA B_GXH
  LDA B_GYL
  CLC
  ADC B_VYL
  STA B_GYL
  LDA B_GYH
  ADC B_VYH
  STA B_GYH
  RTS

; the shot has reached the rim
SHOT_END:
  LDA B_MAKE
  BEQ .se_miss
  LDX SHOOTER                  ; basket!
  LDA P_SCORE,X
  CLC
  ADC B_PTS
  STA P_SCORE,X
  LDA #$01
  STA HUD_DIRTY
  LDA B_PTS
  CMP #$03
  BEQ .se_3
  LDA #MSG_2
  BRA .se_m
.se_3:
  LDA #MSG_3
.se_m:
  JSR SHOW_MSG
  LDA #EVT_SCORE               ; net + chime + applause
  STA SFX_REQ
  LDA #$03
  STA BSTATE
  LDA #$00
  STA B_T
  RTS
.se_miss:                      ; miss: it bounces on the rim and the ball is loose
  LDA #EVT_MISS                ; the rim
  STA SFX_REQ
  LDX SHOOTER
  LDA #$02
  STA BSTATE
  LDA #$00
  STA B_T
  JSR NEXT_RND
  LDA RND
  AND #$0F
  CLC
  ADC #RIM_BACK
  STA T0
  CPX #$00
  BNE .se_l
  LDA HOOPX                    ; right basket: bounces towards the centre
  SEC
  SBC T0
  BRA .se_x
.se_l:
  LDA HOOPX+1
  CLC
  ADC T0
.se_x:
  STA T4
  LDA B_GXH
  STA T5
  LDA #$04
  STA T6
  JSR VEL_CALC
  LDA T0
  STA B_VXL
  LDA T1
  STA B_VXH
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC #80
  STA T4
  LDA B_GYH
  STA T5
  JSR VEL_CALC
  LDA T0
  STA B_VYL
  LDA T1
  STA B_VYH
  LDA #30
  STA B_H
  RTS


; ===============================================================
;  END OF THE GAME: the court stays, the winner panel appears
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  LDA #45                      ; the chime of the last basket finishes playing
  STA GO_DELAY
.go_w:
  JSR WAIT_FRAME
  DEC GO_DELAY
  BNE .go_w
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #<END_REC
  STA PTR
  LDA #>END_REC
  STA PTR+1
  JSR DRAW_RECORDS
  LDA WINNER
  BNE .go_elia
  LDA #<BANNER_D
  STA PTR
  LDA #>BANNER_D
  BRA .go_banner
.go_elia:
  LDA #<BANNER_E
  STA PTR
  LDA #>BANNER_E
.go_banner:
  STA PTR+1
  JSR DRAW_RECORDS
  JSR DRAW_HUD                 ; final score
  JSR VDP_INT_ON
  LDA #$01                     ; applause, cheers, then the celebration song
  STA SND_BUSY
  LDA #CMD_WIN
  STA SND_CMD
  LDA #$00
  STA ARMED
  LDA #60                      ; after the song, half a second before accepting the button
  STA GO_DELAY
.go_loop:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .go_pressed
  LDA ARMED                    ; buttons released
  BNE .go_loop
  LDA SND_BUSY                 ; ... but it is armed only when the song is over
  BNE .go_loop
  LDA GO_DELAY
  BNE .go_dec
  JSR VDP_INT_OFF
  LDA #<END_PRESS
  STA PTR
  LDA #>END_PRESS
  STA PTR+1
  JSR DRAW_RECORDS             ; compare "PRESS A BUTTON"
  JSR VDP_INT_ON
  LDA #$01
  STA ARMED
  BRA .go_loop
.go_dec:
  DEC GO_DELAY
  BRA .go_loop
.go_pressed:
  LDA ARMED
  BEQ .go_loop
  JMP TITLE


; ---------------------------------------------------------------
; waits until the buttons are released and then pressed
; ---------------------------------------------------------------
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


; ---------------------------------------------------------------
; NMI (vblank): the only point that writes the Sprite Attribute Table.
; The main loop writes only into SAT_BUFFER (RAM). When the main loop must
; write the VDP (screens, score) it switches the VDP interrupt off
; with VDP_INT_OFF, so the NMI cannot break a write sequence.
; ---------------------------------------------------------------
NMI_TASK:
  INC FRAME_CNT           ; counts the frames for WAIT_FRAME
  LDA VREG                ; read the VDP status (clears F and C and the byte latch)
  LDA #<VDP_SPRITE_ATT_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_ATT_BASE)
  STA VREG
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX #25               ; 6 sprites x 4 bytes + Y=$D0 of the 7th entry
  BNE .copy_sat
  JSR SND_TICK            ; music and sound effects (A,X,Y saved inside)
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

FRAME_CNT:     .byte $00
LAST_FRAME:    .byte $00

WAIT_FRAME:               ; waits for the next NMI (1 frame = 1/60 s)
  LDA FRAME_CNT
  CMP LAST_FRAME
  BEQ WAIT_FRAME
  STA LAST_FRAME
  RTS

; switches the VDP interrupt off just after an NMI (the next one comes in ~16 ms)
VDP_INT_OFF:
  LDA FRAME_CNT
.io_wait:
  CMP FRAME_CNT
  BEQ .io_wait
  LDA #$C6                ; R1: 16K + display ON + INT OFF
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

VDP_INT_ON:
  LDA #$E6                ; R1: 16K + display ON + INT ON
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

; SAT: decreasing priority: 0 ball, 1-2 nearer player, 3-4 farther player, 5 shadow
; (at most 4 sprites on the same line: ball + 2 players + shadow)
SAT_BUFFER:    .byte HIDE_Y,$00,0,$0A   ; 0: ball
               .byte HIDE_Y,$00,$00,$04            ; 1: nearer player, chest
               .byte HIDE_Y,$00,$00,$0F            ; 2: nearer player, legs
               .byte HIDE_Y,$00,$00,$04            ; 3: farther player, chest
               .byte HIDE_Y,$00,$00,$0F            ; 4: farther player, legs
               .byte HIDE_Y,$00,4,$01 ; 5: shadow of the ball
               .byte $D0                           ; 6: Y=$D0 = end of the list

HIDE_SPRITES:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
  STA SAT_BUFFER+16
  STA SAT_BUFFER+20
  RTS


; ---------------------------------------------------------------
; fills SAT_BUFFER (RAM only) from the game state
; ---------------------------------------------------------------
DRAW_ALL:
  ; --- ball: centre = (GX, GY - H - 3), 16x16 sprite with the centre of the ball at (7,7)
  LDA B_GXH
  SEC
  SBC #7
  STA SAT_BUFFER+1
  LDA B_GYH
  SEC
  SBC B_H
  BCC .da_by0
  SEC
  SBC #11                      ; 3 (radius) + 7 (centre) + 1 (SAT)
  BCS .da_byok
.da_by0:
  LDA #$00
.da_byok:
  STA SAT_BUFFER
  ; --- shadow on the ground, centred on the point (GX, GY)
  LDA B_GXH
  SEC
  SBC #8
  STA SAT_BUFFER+21
  LDA B_GYH
  SEC
  SBC #9
  STA SAT_BUFFER+20
  ; --- players: the one lower on the screen is nearer, so it goes in front
  LDA P_FY
  CMP P_FY+1
  BCS .da_p0
  LDX #$01
  LDY #$04
  JSR DRAW_PLAYER
  LDX #$00
  LDY #$0C
  JSR DRAW_PLAYER
  RTS
.da_p0:
  LDX #$00
  LDY #$04
  JSR DRAW_PLAYER
  LDX #$01
  LDY #$0C
  JSR DRAW_PLAYER
  RTS

; X = player, Y = offset in SAT_BUFFER of the chest sprite (legs at +4)
DRAW_PLAYER:
  STY T6
  LDA P_JUMP,X
  TAY
  LDA JUMP_H,Y                 ; how high it is above the ground
  STA T0
  LDA P_FY,X
  SEC
  SBC T0
  STA T1                       ; raised feet
  LDY T6
  SEC
  SBC #33                      ; chest: feet - 32 - 1 (SAT)
  STA SAT_BUFFER,Y
  LDA T1
  SEC
  SBC #17                      ; legs: feet - 16 - 1
  STA SAT_BUFFER+4,Y
  LDA P_X,X
  STA SAT_BUFFER+1,Y
  STA SAT_BUFFER+5,Y
  ; --- pose of the chest
  LDA P_JUMP,X
  BNE .dp_up
  LDA BSTATE
  BNE .dp_idle
  CPX HOLDER
  BEQ .dp_idle
  LDA #SPR_TOP_DEF             ; defence: arms wide
  BRA .dp_top
.dp_idle:
  LDA #SPR_TOP_IDLE
  BRA .dp_top
.dp_up:
  LDA #SPR_TOP_SHOOT           ; arms raised
.dp_top:
  STA T2
  ; --- pose of the legs
  LDA P_JUMP,X
  BNE .dp_legj
  LDA P_WALK,X
  AND #$08
  BEQ .dp_lega
  LDA #SPR_BOT_B
  BRA .dp_legs
.dp_lega:
  LDA #SPR_BOT_A
  BRA .dp_legs
.dp_legj:
  LDA #SPR_BOT_JUMP
.dp_legs:
  STA T3
  LDA P_FACE,X
  BEQ .dp_right
  LDA T2
  CLC
  ADC #SPR_LEFT_ADD
  STA T2
  LDA T3
  CLC
  ADC #SPR_LEFT_ADD
  STA T3
.dp_right:
  LDA T2
  STA SAT_BUFFER+2,Y
  LDA T3
  STA SAT_BUFFER+6,Y
  LDA TOP_COLOR,X
  STA SAT_BUFFER+3,Y
  LDA BOT_COLOR,X
  STA SAT_BUFFER+7,Y
  RTS

TOP_COLOR:     .byte $04,$08                ; shirt: Davide dark blue, Elia red
BOT_COLOR:     .byte $0F,$01                ; shorts: Davide white, Elia black
HOOPX:         .byte 233,22                 ; basket attacked by Davide (right) / by Elia (left)


; ---------------------------------------------------------------
; scores (big digits) beside the names, messages
; ---------------------------------------------------------------
UPDATE_HUD:
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  JSR VDP_INT_ON
  RTS

DRAW_HUD:
  LDX #$00
  LDA #$08                      ; row 0, column 8: beside "DAVIDE"
  JSR DRAW_SCORE
  LDX #$01
  LDA #$14                      ; row 0, column 20: beside "ELIA"
  JSR DRAW_SCORE
  RTS

; X = player, A = low byte of the name table address (row 0)
DRAW_SCORE:
  STA T4
  LDA P_SCORE,X
  LDY #$00
.ds_t:
  CMP #10
  BCC .ds_o
  SBC #10
  INY
  BRA .ds_t
.ds_o:
  STA T5                        ; units
  STY T6                        ; tens
  LDA T6
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA T4
  STA T1
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T2
  JSR DRAW_BIG
  LDA T5
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA T4
  CLC
  ADC #$02
  STA T1
  JSR DRAW_BIG
  RTS

; draws a big 2x2 tile character
; T0 = first tile (top-left), T1/T2 = VRAM write address (lo/hi with bit $40)
DRAW_BIG:
  LDA T1
  STA VREG
  LDA T2
  STA VREG
  LDA T0
  STA VDATA
  CLC
  ADC #1
  STA VDATA
  LDA T1                        ; row below = address + 32
  CLC
  ADC #32
  STA VREG
  LDA T2
  ADC #0
  STA VREG
  LDA T0
  CLC
  ADC #2
  STA VDATA
  CLC
  ADC #1
  STA VDATA
  RTS

; writes the message MSG_NEW (20 tiles) on row 2, columns 6-25
DRAW_MSG:
  LDA MSG_NEW
  ASL A
  ASL A
  STA T1                        ; n*4
  ASL A
  ASL A                         ; n*16
  CLC
  ADC T1                        ; n*20
  CLC
  ADC #<MSG_TAB
  STA PTR
  LDA #>MSG_TAB
  ADC #0
  STA PTR+1
  JSR VDP_INT_OFF
  LDA #(2*32+6)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDY #$00
.dm_c:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #20
  BNE .dm_c
  JSR VDP_INT_ON
  RTS


; ---------------------------------------------------------------
; draws the records of a screen on the name table:
;   .byte row, column, length, tile...   (terminator: row = $FF)
; PTR = start of the records. VDP free (VDP_INT_OFF).
; ---------------------------------------------------------------
DRAW_RECORDS:
.dr_next:
  LDY #0
  LDA (PTR),Y
  CMP #$FF
  BEQ .dr_end
  STA T0                        ; row
  INY
  LDA (PTR),Y
  STA T1                        ; column
  INY
  LDA (PTR),Y
  STA T2                        ; length
  LDA T0
  AND #$07
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC T1
  STA VREG                      ; low byte: (row mod 8)*32 + column
  LDA T0
  LSR A
  LSR A
  LSR A
  CLC
  ADC #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG                      ; high byte: $78 + row/8
  INY
.dr_copy:
  LDA (PTR),Y
  STA VDATA
  INY
  DEC T2
  BNE .dr_copy
  TYA                           ; PTR += 3 + length
  CLC
  ADC PTR
  STA PTR
  BCC .dr_next
  INC PTR+1
  BRA .dr_next
.dr_end:
  RTS


; ---------------------------------------------------------------
; VDP
; ---------------------------------------------------------------
CLEAR_NAME_TABLE:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDX #3                        ; 768 bytes = 3 pages of 256
.cn_page:
  LDY #0
.cn_byte:
  LDA #$00
  STA VDATA
  DEY
  BNE .cn_byte
  DEX
  BNE .cn_page
  RTS

; copies the court (VDP_NAME) into the name table
LOAD_GAME_NAME_TABLE:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #<VDP_NAME
  STA VDP_INIT
  LDA #>VDP_NAME
  STA VDP_INIT_HI
.ln_loop:
  LDA (VDP_INIT)
  STA VDATA
  INC VDP_INIT
  BNE .ln_skip
  INC VDP_INIT_HI
.ln_skip:
  LDA VDP_INIT
  CMP #<VDP_END_NAME
  BNE .ln_loop
  LDA VDP_INIT_HI
  CMP #>VDP_END_NAME
  BNE .ln_loop
  RTS

; copies all the blocks of VDP_BLOCKS into the VRAM (src, length, VRAM address):
; patterns of the 3 thirds, sprites, colours of the 3 thirds
VDP_LOAD_ALL:
  LDA #<VDP_BLOCKS
  STA PTR
  LDA #>VDP_BLOCKS
  STA PTR+1
  LDX #BLOCK_COUNT
.vl_blk:
  LDY #0
  LDA (PTR),Y
  STA VDP_INIT
  INY
  LDA (PTR),Y
  STA VDP_INIT_HI
  INY
  LDA (PTR),Y
  STA T0                        ; length, low byte
  INY
  LDA (PTR),Y
  STA T1                        ; length, high byte
  INY
  LDA (PTR),Y
  STA VREG                      ; VRAM address
  INY
  LDA (PTR),Y
  STA VREG
  LDY #0
.vl_cp:
  LDA (VDP_INIT),Y
  STA VDATA
  INY
  BNE .vl_y
  INC VDP_INIT_HI
.vl_y:
  LDA T0
  BNE .vl_d0
  DEC T1
.vl_d0:
  DEC T0
  LDA T0
  ORA T1
  BNE .vl_cp
  LDA PTR                       ; next block: PTR += 6
  CLC
  ADC #6
  STA PTR
  BCC .vl_nc
  INC PTR+1
.vl_nc:
  DEX
  BNE .vl_blk
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
   .byte $03,$76,$03,$0E       ;R0: G2 | R1: 16K, 16x16 sprite | R2: name $3800 | R3: color $2000
                               ;R4: pattern $0000 | R5: SAT $3B00 | R6: sprite pattern $1800 | R7: grey background


; ===============================================================
;  TABLES (generated)
; ===============================================================
; blocks to copy into the VRAM: source (2), length (2), VRAM address + write bit (2)
VDP_BLOCKS:
  .byte <PAT0,>PAT0,<(PAT0_END-PAT0),>(PAT0_END-PAT0),$00,$40
  .byte <PAT1,>PAT1,<(PAT1_END-PAT1),>(PAT1_END-PAT1),$00,$48
  .byte <PAT2,>PAT2,<(PAT2_END-PAT2),>(PAT2_END-PAT2),$00,$50
  .byte <VDP_SPRITE,>VDP_SPRITE,<(VDP_END_SPRITE-VDP_SPRITE),>(VDP_END_SPRITE-VDP_SPRITE),$00,$58
  .byte <COL0,>COL0,<(COL0_END-COL0),>(COL0_END-COL0),$00,$60
  .byte <COL1,>COL1,<(COL1_END-COL1),>(COL1_END-COL1),$00,$68
  .byte <COL2,>COL2,<(COL2_END-COL2),>(COL2_END-COL2),$00,$70


; ===============================================================
;  SOUND  -  two AY-3-8910 (left = Davide, right = Elia)
;  All the sound is played by SND_TICK, called by the NMI at 60 Hz.
;  The main loop never writes the AYs: it only leaves commands and flags
;  (SND_CMD, SFX_REQ, SFX_DRIB), so there are no conflicts.
;  The AYs are written from the shadows SH_L / SH_R (registers 0-10).
;
;  In partita: canale A = chime / ping, B = rumore (retina, applauso),
;  C = low thumps (dribble, rim, block).
;  Songs: 0 = title, 1 = victory (4 tracks: melody, arpeggio, bass, drums).
; ===============================================================

; called once by RESET (VDP interrupt still off)
SND_INIT:
  LDA #$A5
  STA SND_RND
  LDA #$00
  STA SND_CMD
  STA SND_PH
  LDA #$FF                      ; mixer: everything off while clearing
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
  STA SFX_REQ
  STA SFX_EVT
  STA SFX_STEP
  STA SFX_APPL
  STA SFX_ADLY
  STA SFX_DRIB
  STA SFX_DRIB+1
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
; called by the NMI: A,X,Y saved here
; ---------------------------------------------------------------
SND_TICK:
  PHA
  PHX
  PHY
  INC SND_PH
  LDA SND_CMD
  BEQ .st_run
  LDX #$00
  STX SND_CMD
  CMP #CMD_GAME
  BNE .st_t
  JSR SND_GAME_MODE
  BRA .st_run
.st_t:
  CMP #CMD_TITLE
  BNE .st_w
  LDA #$00                      ; song 0 = title
  JSR SND_START
  BRA .st_run
.st_w:
  JSR CELEB_START               ; CMD_WIN: applause, cheers, then song 1
.st_run:
  LDA SND_MODE
  BEQ .st_sfx
  CMP #$01
  BNE .st_cel
  JSR MUS_TICK
  BRA .st_flush
.st_cel:
  JSR CELEB_TICK
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
; starts a song: A = 0 title, 1 victory
; ---------------------------------------------------------------
SND_START:
  ASL A
  ASL A
  STA SN0                       ; song * 4
  JSR SND_CLEAR_SH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #$2A                      ; right: tone A, noise B (drums), tone C
  STA SH_R+7
  LDX #$03
.ss_trk:
  TXA
  CLC
  ADC SN0
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
  LDX #$02                      ; tone tracks: 0 melody, 1 arpeggio, 2 bass
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
  ;      vibrato on long notes that are not too high
  LDX TR_NOTE
  BEQ .mt_l_off
  LDA TP_LO,X
  STA SN1
  CMP #100
  BCC .mt_l_nv
  LDA TR_AGE
  CMP #14
  BCC .mt_l_nv
  LSR A
  AND #$07
  TAY
  LDA SN1
  CLC
  ADC VIB_TAB,Y
  STA SN1
.mt_l_nv:
  LDA SN1
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
  ; ---- arpeggio: left chip only, channel B
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
  ; ---- song over?
  LDA TR_ACT
  ORA TR_ACT+1
  ORA TR_ACT+2
  ORA TR_ACT+3
  BNE .mt_end
  JSR SND_GAME_MODE             ; silence, SND_BUSY = 0
.mt_end:
  RTS


; ---------------------------------------------------------------
; applause noise on a chip: A = base volume, Y = chip * 16.
; The volume is lowered by 0-7 at random every frame (crackle of the clapping)
; and the noise period changes at random (5-12). Keeps Y.
; ---------------------------------------------------------------
APPL_NOISE:
  STA SN1
  LDA SND_RND
  ASL A
  BCC .an_r
  EOR #$1D
.an_r:
  STA SND_RND
  AND #$07
  STA SN0
  LDA SN1
  SEC
  SBC SN0
  BCS .an_v
  LDA #$00
.an_v:
  STA SH_L+9,Y
  LDA SND_RND
  LSR A
  LSR A
  LSR A
  AND #$07
  CLC
  ADC #$05
  STA SH_L+6,Y
  RTS

; ---------------------------------------------------------------
; game sound effects (one frame). Chip 0 = Davide, chip 1 = Elia.
;   channel A = chime / ping, B = noise (net, applause), C = low thumps
; Priority in every channel: table effect > applause / dribble.
; ---------------------------------------------------------------
SFX_TICK:
  LDA SND_RND                   ; LFSR for the crackle
  ASL A
  BCC .sf_r
  EOR #$1D
.sf_r:
  STA SND_RND
  LDA SFX_REQ                   ; new effect request?
  BEQ .sf_noreq
  STA SFX_EVT
  TAX
  LDA #$00
  STA SFX_STEP
  STA SFX_REQ
  LDA EVT_ADLY,X
  BEQ .sf_noreq
  STA SFX_ADLY                  ; the applause starts after a while
.sf_noreq:
  LDA SFX_ADLY
  BEQ .sf_chips
  DEC SFX_ADLY
  BNE .sf_chips
  LDA #$01
  STA SFX_APPL                  ; the applause starts
.sf_chips:
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
  ; ---- dribble: thud on channel C of the chip of the dribbling player
  LDA SFX_DRIB,X
  BEQ .sf_nodr
  TAX
  DEX                           ; step 0..5
  LDA DRIB_V,X
  STA SH_L+10,Y
  LDA DRIB_TL,X
  STA SH_L+4,Y
  LDA DRIB_TH,X
  STA SH_L+5,Y
.sf_nodr:
  ; ---- applause: noise on channel B of both chips
  LDA SFX_APPL
  BEQ .sf_noap
  LSR A
  LSR A
  LSR A                         ; one value of the envelope every 8 frames
  TAX
  LDA APPL_ENV,X
  JSR APPL_NOISE
.sf_noap:
  ; ---- table effect: over everything else
  LDA SFX_EVT
  BEQ .sf_next
  TAX
  LDA EVT_OFF,X
  CLC
  ADC SFX_STEP
  TAX                           ; X = position in the EV* tables
  LDA EVA_V,X
  STA SH_L+8,Y
  LDA EVA_TL,X
  CPY #$00
  BEQ .sf_ea
  CLC
  ADC #$01                      ; the right chip is detuned by 1 step (chorus)
.sf_ea:
  STA SH_L,Y
  LDA EVA_TH,X
  STA SH_L+1,Y
  LDA EVN_V,X
  BEQ .sf_en
  STA SH_L+9,Y
  LDA EVN_P,X
  STA SH_L+6,Y
.sf_en:
  LDA EVC_V,X
  BEQ .sf_next
  STA SH_L+10,Y
  LDA EVC_TL,X
  STA SH_L+4,Y
  LDA EVC_TH,X
  STA SH_L+5,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_adv
  JMP .sf_chip
.sf_adv:
  LDA SFX_EVT                   ; advances the effect
  BEQ .sf_a1
  INC SFX_STEP
  LDX SFX_EVT
  LDA SFX_STEP
  CMP EVT_LEN,X
  BCC .sf_a1
  LDA #$00
  STA SFX_EVT
.sf_a1:
  LDA SFX_APPL                  ; advances the applause
  BEQ .sf_a2
  INC SFX_APPL
  LDA SFX_APPL
  CMP #(APPL_LEN+1)
  BCC .sf_a2
  LDA #$00
  STA SFX_APPL
.sf_a2:
  LDX #$01                      ; advances the two dribbles
.sf_a3:
  LDA SFX_DRIB,X
  BEQ .sf_a4
  INC SFX_DRIB,X
  LDA SFX_DRIB,X
  CMP #(DRIB_LEN+1)
  BCC .sf_a4
  LDA #$00
  STA SFX_DRIB,X
.sf_a4:
  DEX
  BPL .sf_a3
  RTS


; ---------------------------------------------------------------
; ending: first the applause, then the cheers, then the victory song
; ---------------------------------------------------------------
CELEB_START:
  JSR SND_GAME_MODE             ; silence, mixer = tone A + noise B + tone C
  LDA #$02
  STA SND_MODE
  LDA #$01
  STA SND_BUSY
  LDA #$00
  STA SND_STAGE
  STA SND_T2
  RTS

CELEB_TICK:
  INC SND_T2
  LDA #$00                      ; tones at zero: only those of the phase remain
  STA SH_L+8
  STA SH_L+10
  STA SH_R+8
  STA SH_R+10
  LDA SND_STAGE
  BNE .cb_cheer
  LDA SND_T2                    ; ---- phase 0: big applause
  CMP #CELEB_APPL_LEN
  BCC .cb_ap
  LDA #$01
  STA SND_STAGE
  LDA #$00
  STA SND_T2
  RTS
.cb_ap:
  LSR A
  LSR A
  LSR A
  LSR A                         ; one value of the envelope every 16 frames
  TAX
  LDA CAPPL_ENV,X
  JMP CELEB_NOISE
.cb_cheer:
  LDA SND_T2                    ; ---- phase 1: "whoo!" cheers + murmur of the crowd
  CMP #CHEER_LEN
  BCC .cb_ch
  LDA #$01                      ; done: the victory song starts
  JMP SND_START
.cb_ch:
  LSR A
  TAX                           ; step 0..55 (one every 2 frames)
  LDA CHEER_V,X
  STA SH_L+8
  STA SH_R+8
  SEC
  SBC #$03
  BCS .cb_cv
  LDA #$00
.cb_cv:
  STA SH_L+10
  STA SH_R+10
  LDA CHEER_TL,X
  STA SH_L
  CLC
  ADC #$03                      ; right chip detuned: crowd effect
  STA SH_R
  LDA CHEER_TH,X
  STA SH_L+1
  STA SH_R+1
  LDA CHEER_CTL,X
  STA SH_L+4
  CLC
  ADC #$02
  STA SH_R+4
  LDA CHEER_CTH,X
  STA SH_L+5
  STA SH_R+5
  LDA #$06
CELEB_NOISE:                    ; A = base volume of the noise, on both chips
  STA SND_T1
  LDY #$00
  JSR APPL_NOISE
  LDA SND_T1
  LDY #$10
  JSR APPL_NOISE
  RTS


; 3-point arc: half X axis of the ellipse for |dy| = 0..62 (inside = 2 points)
ARCDX_TAB:
  .byte $54,$53,$53,$53,$53,$53,$53,$53,$53,$53,$52,$52,$52,$52,$51,$51
  .byte $51,$50,$50,$4F,$4F,$4F,$4E,$4E,$4D,$4C,$4C,$4B,$4A,$4A,$49,$48
  .byte $47,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3D,$3C,$3B,$39,$38,$36
  .byte $35,$33,$31,$2F,$2D,$2B,$29,$26,$24,$21,$1D,$19,$15,$0F,$00

; left edge of the court (sprite X) for feet Y = 64..188; the right edge is 240 - value
XMIN_TAB:
  .byte $15,$15,$14,$14,$14,$14,$14,$14,$14,$13,$13,$13,$13,$13,$13,$12
  .byte $12,$12,$12,$12,$12,$11,$11,$11,$11,$11,$11,$11,$10,$10,$10,$10
  .byte $10,$10,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0E,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$08
  .byte $08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06
  .byte $06,$06,$06,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04

; height of the jump (pixels) by the frames left P_JUMP = 0..24
JUMP_H:
  .byte $00,$01,$03,$05,$07,$09,$0A,$0B,$0C,$0D,$0D,$0E,$0E
  .byte $0E,$0E,$0D,$0D,$0C,$0B,$0A,$09,$07,$05,$03,$01

; height of the ball while dribbling (16 frames)
DRIB_TAB:
  .byte $12,$12,$11,$0F,$0E,$0B,$08,$04,$00,$04,$08,$0B,$0E,$0F,$11,$12

; height of the ball in the shot: 33 steps, from 36 (hands) to 30 (rim) with an arc of 20 pixels
HT_TAB:
  .byte $24,$26,$28,$2A,$2C,$2E,$2F,$30,$32,$32,$33
  .byte $34,$34,$35,$35,$35,$35,$35,$34,$34,$33,$32
  .byte $31,$30,$2E,$2D,$2B,$29,$28,$25,$23,$21,$1E

; bounce of the loose ball: it falls from the rim and bounces a second time (17 steps)
BNC_TAB:
  .byte $1E,$1E,$1C,$1A,$16,$12,$0D,$07,$00,$03,$05,$07,$07,$07,$05,$03,$00

; ball going through the net (13 steps)
NET_TAB:
  .byte $1E,$1C,$19,$16,$14,$12,$0F,$0C,$0A,$08,$05,$02,$00

; 16x16 sprites (sprite generator): ball, shadow, 3 poses of the chest and 3 of the legs, right and left
VDP_SPRITE:
  ; BALL  (sprite name 0)
  .byte $00,$00,$00,$00,$03,$07,$0F,$0F
  .byte $0F,$07,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$E0
  .byte $E0,$C0,$80,$00,$00,$00,$00,$00
  ; SHADOW  (sprite name 4)
  .byte $00,$00,$00,$00,$00,$00,$00,$07
  .byte $0F,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$E0
  .byte $F0,$E0,$00,$00,$00,$00,$00,$00
  ; TOP_IDLE_R  (sprite name 8)
  .byte $00,$00,$00,$01,$01,$01,$00,$00
  .byte $03,$03,$07,$07,$0F,$0F,$1B,$03
  .byte $00,$00,$E0,$F0,$F0,$F0,$E0,$00
  .byte $F8,$FC,$FC,$FE,$FB,$FB,$F8,$F8
  ; TOP_SHOOT_R  (sprite name 12)
  .byte $00,$0C,$0C,$0C,$0D,$0F,$07,$07
  .byte $07,$06,$07,$07,$07,$07,$07,$07
  .byte $0C,$0C,$0C,$0C,$CC,$EC,$F8,$F8
  .byte $D8,$18,$F8,$F0,$F0,$F0,$F0,$F0
  ; TOP_DEF_R  (sprite name 16)
  .byte $00,$00,$01,$03,$03,$03,$01,$00
  .byte $07,$07,$1F,$77,$C7,$07,$07,$07
  .byte $00,$00,$C0,$E0,$E0,$E0,$C0,$00
  .byte $F0,$F8,$FC,$F6,$F3,$F0,$F0,$F0
  ; TOP_IDLE_L  (sprite name 20)
  .byte $00,$00,$07,$0F,$0F,$0F,$07,$00
  .byte $1F,$3F,$3F,$7F,$DF,$DF,$1F,$1F
  .byte $00,$00,$00,$80,$80,$80,$00,$00
  .byte $C0,$C0,$E0,$E0,$F0,$F0,$D8,$C0
  ; TOP_SHOOT_L  (sprite name 24)
  .byte $30,$30,$30,$30,$33,$37,$1F,$1F
  .byte $1B,$18,$1F,$0F,$0F,$0F,$0F,$0F
  .byte $00,$30,$30,$30,$B0,$F0,$E0,$E0
  .byte $E0,$60,$E0,$E0,$E0,$E0,$E0,$E0
  ; TOP_DEF_L  (sprite name 28)
  .byte $00,$00,$03,$07,$07,$07,$03,$00
  .byte $0F,$1F,$3F,$6F,$CF,$0F,$0F,$0F
  .byte $00,$00,$80,$C0,$C0,$C0,$80,$00
  .byte $E0,$E0,$F8,$EE,$E3,$E0,$E0,$E0
  ; BOT_A_R  (sprite name 32)
  .byte $07,$07,$07,$07,$07,$03,$03,$06
  .byte $06,$06,$0C,$0C,$0C,$0C,$18,$78
  .byte $F0,$F0,$F0,$F0,$F0,$30,$30,$18
  .byte $18,$18,$0C,$0C,$0C,$0C,$06,$0F
  ; BOT_B_R  (sprite name 36)
  .byte $07,$07,$07,$07,$07,$01,$01,$01
  .byte $01,$01,$03,$03,$03,$03,$03,$0F
  .byte $F0,$F0,$F0,$F0,$F0,$E0,$E0,$E0
  .byte $E0,$E0,$30,$30,$30,$30,$30,$78
  ; BOT_JUMP_R  (sprite name 40)
  .byte $07,$07,$07,$07,$07,$03,$06,$0C
  .byte $0C,$18,$0C,$0C,$0C,$06,$00,$00
  .byte $F0,$F0,$F0,$F0,$F0,$30,$18,$0C
  .byte $0C,$06,$0C,$0C,$0C,$18,$00,$00
  ; BOT_A_L  (sprite name 44)
  .byte $0F,$0F,$0F,$0F,$0F,$0C,$0C,$18
  .byte $18,$18,$30,$30,$30,$30,$60,$F0
  .byte $E0,$E0,$E0,$E0,$E0,$C0,$C0,$60
  .byte $60,$60,$30,$30,$30,$30,$18,$1E
  ; BOT_B_L  (sprite name 48)
  .byte $0F,$0F,$0F,$0F,$0F,$07,$07,$07
  .byte $07,$07,$0C,$0C,$0C,$0C,$0C,$1E
  .byte $E0,$E0,$E0,$E0,$E0,$80,$80,$80
  .byte $80,$80,$C0,$C0,$C0,$C0,$C0,$F0
  ; BOT_JUMP_L  (sprite name 52)
  .byte $0F,$0F,$0F,$0F,$0F,$0C,$18,$30
  .byte $30,$60,$30,$30,$30,$18,$00,$00
  .byte $E0,$E0,$E0,$E0,$E0,$C0,$60,$30
  .byte $30,$18,$30,$30,$30,$60,$00,$00
VDP_END_SPRITE:

; patterns third 0: tiles 00-F3 (8 bytes per tile)
PAT0:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $A8,$54,$A8,$54,$A8,$54,$A8,$54
  .byte $2A,$15,$2A,$15,$2A,$15,$2A,$15
  .byte $00,$00,$00,$00,$01,$01,$01,$01
  .byte $FF,$FF,$C0,$C0,$80,$80,$80,$80
  .byte $FF,$FF,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$01,$01,$01,$01,$01,$01
  .byte $FF,$FF,$80,$80,$80,$80,$80,$80
  .byte $FF,$FF,$03,$03,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 10
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 20
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
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00   ; tile 30
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
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00   ; tile 40
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
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00   ; tile 50
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 60
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 70
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$19,$19   ; tile 80
  .byte $E0,$E0,$18,$18,$78,$78,$98,$98
  .byte $1E,$1E,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $01,$01,$07,$07,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$07,$07,$00,$00
  .byte $80,$80,$80,$80,$E0,$E0,$00,$00
  .byte $07,$07,$18,$18,$00,$00,$01,$01
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $06,$06,$18,$18,$1F,$1F,$00,$00
  .byte $00,$00,$00,$00,$F8,$F8,$00,$00
  .byte $1F,$1F,$00,$00,$00,$00,$01,$01
  .byte $F8,$F8,$18,$18,$60,$60,$E0,$E0
  .byte $00,$00,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $00,$00,$01,$01,$06,$06,$18,$18   ; tile 90
  .byte $60,$60,$E0,$E0,$60,$60,$60,$60
  .byte $1F,$1F,$00,$00,$00,$00,$00,$00
  .byte $F8,$F8,$60,$60,$60,$60,$00,$00
  .byte $1F,$1F,$18,$18,$1F,$1F,$00,$00
  .byte $F8,$F8,$00,$00,$E0,$E0,$18,$18
  .byte $00,$00,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $01,$01,$06,$06,$18,$18,$1F,$1F
  .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $1F,$1F,$00,$00,$00,$00,$01,$01
  .byte $F8,$F8,$18,$18,$60,$60,$80,$80
  .byte $06,$06,$06,$06,$06,$06,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$07,$07   ; tile A0
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$07,$07
  .byte $E0,$E0,$18,$18,$18,$18,$F8,$F8
  .byte $00,$00,$00,$00,$1F,$1F,$00,$00
  .byte $18,$18,$60,$60,$80,$80,$00,$00
  .byte $1F,$1F,$01,$01,$01,$01,$01,$01
  .byte $F8,$F8,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $01,$01,$06,$06,$18,$18,$18,$18
  .byte $80,$80,$60,$60,$18,$18,$18,$18
  .byte $1F,$1F,$18,$18,$18,$18,$00,$00
  .byte $F8,$F8,$18,$18,$18,$18,$00,$00
  .byte $18,$18,$18,$18,$1E,$1E,$19,$19   ; tile B0
  .byte $18,$18,$18,$18,$18,$18,$98,$98
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $78,$78,$18,$18,$18,$18,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$1F,$1F
  .byte $18,$18,$18,$18,$18,$18,$F8,$F8
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0
  .byte $18,$18,$18,$18,$1F,$1F,$00,$00
  .byte $00,$00,$00,$00,$F8,$F8,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$01,$01,$01,$01,$01,$01   ; tile C0
  .byte $E0,$E0,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$07,$07,$00,$00
  .byte $80,$80,$80,$80,$E0,$E0,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$1F,$1F,$00,$00
  .byte $00,$00,$00,$00,$F8,$F8,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$18,$18
  .byte $E0,$E0,$18,$18,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $00,$00,$18,$18,$E0,$E0,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$18,$18
  .byte $E0,$E0,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$18,$18   ; tile D0
  .byte $E0,$E0,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$1F,$1F,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$19,$19
  .byte $18,$18,$18,$18,$18,$18,$98,$98
  .byte $19,$19,$1E,$1E,$18,$18,$00,$00
  .byte $98,$98,$78,$78,$18,$18,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$06,$06,$01,$01   ; tile E0
  .byte $18,$18,$18,$18,$60,$60,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $19,$19,$18,$18,$18,$18,$00,$00
  .byte $80,$80,$60,$60,$18,$18,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$07,$07
  .byte $E0,$E0,$18,$18,$00,$00,$E0,$E0
  .byte $00,$00,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $01,$01,$01,$01,$00,$00,$00,$00
  .byte $80,$80,$80,$80,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0   ; tile F0
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $33,$33,$33,$33,$0C,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
PAT0_END:

; colours third 0: tiles 00-F3 (8 bytes per tile)
COL0:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 10
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 20
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 30
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 40
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 50
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 60
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 70
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 80
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 90
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile A0
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile B0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile C0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile D0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile E0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile F0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
COL0_END:

; patterns third 1: tiles 00-90 (8 bytes per tile)
PAT1:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $A8,$54,$A8,$54,$A8,$54,$A8,$54
  .byte $00,$00,$00,$00,$7F,$80,$80,$7F
  .byte $00,$00,$00,$00,$E0,$10,$10,$E0
  .byte $00,$00,$00,$00,$C0,$F8,$FF,$1F
  .byte $00,$00,$00,$00,$00,$00,$80,$E0
  .byte $01,$01,$01,$01,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$01,$07
  .byte $00,$00,$00,$00,$03,$1F,$FF,$F8
  .byte $00,$00,$00,$00,$07,$08,$08,$07
  .byte $00,$00,$00,$00,$FE,$01,$01,$FE
  .byte $2A,$15,$2A,$15,$2A,$15,$2A,$15
  .byte $55,$2A,$2A,$15,$0F,$00,$00,$00
  .byte $50,$A0,$A0,$40,$C0,$00,$00,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00   ; tile 10
  .byte $FC,$7F,$0F,$01,$00,$00,$00,$00
  .byte $00,$00,$E0,$F8,$7E,$1F,$07,$01
  .byte $00,$00,$00,$00,$00,$80,$C0,$F0
  .byte $00,$00,$00,$00,$00,$01,$03,$0F
  .byte $00,$00,$07,$1F,$7E,$F8,$E0,$80
  .byte $3F,$FE,$F0,$80,$00,$00,$00,$00
  .byte $80,$00,$00,$00,$00,$00,$00,$00
  .byte $05,$02,$02,$01,$00,$00,$00,$00
  .byte $55,$AA,$AA,$54,$FC,$00,$00,$00
  .byte $A8,$54,$A8,$54,$A8,$54,$00,$00
  .byte $0C,$0C,$0C,$0C,$0C,$18,$18,$18
  .byte $F8,$3E,$0F,$07,$01,$00,$00,$00
  .byte $00,$00,$00,$C0,$E0,$F0,$7C,$3E
  .byte $00,$00,$00,$03,$07,$0F,$3E,$7C
  .byte $1F,$7C,$F0,$E0,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 20
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
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00   ; tile 30
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
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00   ; tile 40
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
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00   ; tile 50
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
  .byte $30,$30,$30,$30,$30,$18,$18,$18   ; tile 60
  .byte $2A,$15,$2A,$15,$2A,$15,$00,$00
  .byte $18,$18,$18,$18,$30,$30,$30,$30
  .byte $0F,$07,$03,$01,$00,$00,$00,$00
  .byte $00,$80,$C0,$E0,$F0,$78,$3C,$1C
  .byte $00,$01,$03,$07,$0F,$1E,$3C,$38
  .byte $F0,$E0,$C0,$80,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$0C,$0C,$0C,$0C
  .byte $30,$30,$60,$60,$60,$60,$60,$60
  .byte $0E,$0F,$07,$03,$01,$01,$00,$00
  .byte $00,$00,$80,$80,$C0,$E0,$E0,$70
  .byte $00,$00,$01,$01,$03,$07,$07,$0E
  .byte $70,$F0,$E0,$C0,$80,$80,$00,$00
  .byte $0C,$0C,$06,$06,$06,$06,$06,$06
  .byte $00,$00,$00,$00,$00,$00,$00,$01
  .byte $60,$C0,$C0,$C0,$FF,$FF,$C0,$80
  .byte $00,$00,$00,$00,$FF,$FF,$00,$00   ; tile 70
  .byte $00,$00,$00,$00,$C0,$C0,$C0,$C0
  .byte $70,$38,$38,$1C,$1C,$0E,$0E,$06
  .byte $00,$00,$00,$01,$07,$1F,$7C,$F0
  .byte $00,$00,$1F,$FF,$F0,$00,$00,$00
  .byte $01,$FF,$FF,$81,$01,$01,$01,$01
  .byte $80,$FF,$FF,$80,$80,$80,$80,$80
  .byte $00,$C0,$FE,$FF,$07,$00,$00,$00
  .byte $00,$00,$00,$E0,$F8,$7E,$1F,$07
  .byte $00,$00,$00,$00,$00,$00,$80,$C0
  .byte $0E,$1C,$1C,$38,$38,$70,$70,$60
  .byte $00,$00,$00,$00,$03,$03,$03,$03
  .byte $06,$03,$03,$03,$FF,$FF,$03,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$80
  .byte $01,$01,$01,$01,$01,$01,$03,$03
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0   ; tile 80
  .byte $07,$07,$03,$03,$03,$01,$01,$01
  .byte $00,$00,$00,$80,$80,$80,$80,$80
  .byte $03,$07,$06,$0E,$1C,$18,$18,$18
  .byte $C0,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$78,$38,$1C,$1E,$0E,$06,$06
  .byte $00,$00,$00,$01,$01,$01,$01,$01
  .byte $E0,$E0,$C0,$C0,$C0,$80,$80,$80
  .byte $03,$03,$03,$03,$03,$03,$03,$03
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$C0,$C0
  .byte $03,$03,$03,$03,$06,$06,$06,$06
  .byte $01,$01,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$1C,$1E,$0E,$07,$07,$03
  .byte $06,$06,$0E,$1C,$18,$38,$70,$E0
  .byte $80,$80,$00,$00,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$60,$60,$60,$60   ; tile 90
PAT1_END:

; colours third 1: tiles 00-90 (8 bytes per tile)
COL1:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 10
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 20
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 30
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 40
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 50
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 60
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 70
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 80
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 90
COL1_END:

; patterns third 2: tiles 00-8A (8 bytes per tile)
PAT2:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $06,$06,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$01,$01
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$80
  .byte $F8,$7E,$1F,$07,$01,$00,$00,$00
  .byte $00,$00,$80,$F8,$FF,$1F,$00,$00
  .byte $01,$01,$01,$01,$C1,$FF,$FF,$01
  .byte $80,$80,$80,$80,$80,$FF,$FF,$80
  .byte $00,$00,$00,$07,$FF,$FC,$80,$00
  .byte $07,$1F,$7C,$F0,$C0,$00,$00,$00
  .byte $80,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$03,$03,$03,$03,$03,$03,$01
  .byte $00,$00,$00,$00,$00,$00,$80,$80
  .byte $03,$03,$03,$03,$03,$03,$03,$03
  .byte $60,$60,$30,$30,$30,$30,$30,$30   ; tile 10
  .byte $0C,$18,$18,$18,$18,$18,$18,$30
  .byte $01,$01,$01,$03,$03,$03,$07,$06
  .byte $80,$80,$80,$80,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$00,$00,$00,$00
  .byte $80,$80,$80,$C0,$C0,$C0,$E0,$60
  .byte $30,$18,$18,$18,$18,$18,$18,$0C
  .byte $30,$30,$3F,$3F,$30,$30,$60,$60
  .byte $00,$00,$FF,$FF,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$00,$00,$00,$00
  .byte $06,$0E,$0C,$1C,$18,$38,$30,$70
  .byte $60,$70,$30,$38,$18,$1C,$0C,$0E
  .byte $03,$03,$03,$03,$00,$00,$00,$00
  .byte $0C,$0C,$FC,$FC,$0C,$0C,$06,$06
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 20
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
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00   ; tile 30
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
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00   ; tile 40
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
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00   ; tile 50
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
  .byte $60,$60,$60,$60,$C0,$C0,$C0,$C0   ; tile 60
  .byte $00,$00,$01,$01,$03,$07,$0E,$0C
  .byte $60,$E0,$C0,$80,$80,$00,$00,$00
  .byte $06,$07,$03,$01,$01,$00,$00,$00
  .byte $00,$00,$80,$80,$C0,$E0,$70,$30
  .byte $06,$06,$06,$06,$03,$03,$03,$03
  .byte $00,$00,$00,$01,$01,$01,$01,$01
  .byte $C0,$C0,$C0,$80,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$01,$03,$07,$0E
  .byte $1C,$38,$70,$E0,$C0,$80,$00,$00
  .byte $38,$1C,$0E,$07,$03,$01,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$70
  .byte $03,$03,$03,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$80,$80,$80,$80,$80
  .byte $01,$03,$03,$03,$03,$03,$03,$06
  .byte $00,$00,$00,$01,$07,$0E,$3C,$F0
  .byte $3C,$78,$E0,$C0,$80,$00,$00,$00   ; tile 70
  .byte $3C,$1E,$07,$03,$01,$00,$00,$00
  .byte $00,$00,$00,$80,$E0,$70,$3C,$0F
  .byte $01,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$C0,$C0,$C0,$C0,$C0,$C0,$60
  .byte $06,$06,$06,$06,$06,$06,$0C,$0C
  .byte $00,$00,$00,$00,$00,$00,$00,$01
  .byte $00,$00,$00,$00,$01,$0F,$7E,$F8
  .byte $01,$07,$1F,$7C,$F0,$C0,$00,$00
  .byte $E0,$80,$00,$00,$00,$00,$00,$00
  .byte $07,$01,$00,$00,$00,$00,$00,$00
  .byte $80,$E0,$F8,$3E,$0F,$03,$00,$00
  .byte $00,$00,$00,$00,$80,$F0,$7E,$1F
  .byte $00,$00,$00,$00,$00,$00,$00,$80
  .byte $60,$60,$60,$60,$60,$60,$30,$30
  .byte $0C,$0C,$0C,$0C,$18,$1B,$1B,$18
  .byte $00,$00,$00,$00,$01,$FF,$FF,$00   ; tile 80
  .byte $00,$00,$00,$03,$FF,$FE,$00,$00
  .byte $00,$00,$0F,$FF,$F8,$00,$00,$00
  .byte $1F,$FF,$F0,$80,$00,$00,$00,$00
  .byte $C0,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$00,$00,$00,$00,$00,$00,$00
  .byte $F8,$FF,$0F,$01,$00,$00,$00,$00
  .byte $00,$00,$F0,$FF,$1F,$00,$00,$00
  .byte $00,$00,$00,$C0,$FF,$7F,$00,$00
  .byte $00,$00,$00,$00,$80,$FF,$FF,$00
  .byte $30,$30,$30,$30,$18,$D8,$D8,$18
PAT2_END:

; colours third 2: tiles 00-8A (8 bytes per tile)
COL2:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 10
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 20
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 30
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 40
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 50
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 60
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 70
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 80
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
COL2_END:

; name table 32x24: rows 0-1 scores (big digits written by DRAW_HUD), row 1 names, row 2 messages, the rest the court
VDP_NAME:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00   ; row 0
  .byte $00,$44,$41,$56,$49,$44,$45,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$45,$4C,$49,$41,$00,$00,$00   ; row 1
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00   ; row 2
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01   ; row 3
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01   ; row 4
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01   ; row 5
  .byte $01,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$03,$01   ; row 6
  .byte $01,$02,$04,$05,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$07
  .byte $08,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$09,$0A,$03,$01   ; row 7
  .byte $01,$02,$03,$04,$05,$06,$01,$01,$01,$01,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$01,$01,$01,$01,$09,$0A,$0B,$0C,$0D,$01   ; row 8
  .byte $01,$02,$0E,$0F,$10,$11,$12,$13,$01,$01,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$01,$01,$14,$15,$16,$17,$18,$19,$0D,$01   ; row 9
  .byte $01,$1A,$1B,$01,$01,$01,$01,$1C,$1D,$01,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$01,$1E,$1F,$01,$01,$01,$01,$60,$61,$01   ; row 10
  .byte $01,$01,$62,$01,$01,$01,$01,$01,$63,$64,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$65,$66,$01,$01,$01,$01,$01,$67,$01,$01   ; row 11
  .byte $01,$01,$68,$01,$01,$01,$01,$01,$01,$69,$6A,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$6B,$6C,$01,$01,$01,$01,$01,$01,$6D,$01,$01   ; row 12
  .byte $01,$6E,$6F,$70,$70,$70,$70,$71,$01,$01,$72,$01,$01,$73,$74,$75
  .byte $76,$77,$78,$79,$01,$7A,$01,$01,$7B,$70,$70,$70,$70,$7C,$7D,$01   ; row 13
  .byte $01,$7E,$7F,$01,$01,$01,$01,$80,$01,$01,$81,$82,$83,$84,$01,$07
  .byte $08,$01,$10,$85,$86,$87,$01,$01,$88,$01,$01,$01,$01,$89,$8A,$01   ; row 14
  .byte $01,$8B,$01,$01,$01,$01,$01,$80,$01,$01,$8C,$80,$8D,$06,$01,$07
  .byte $08,$01,$6E,$8E,$88,$8F,$01,$01,$88,$01,$01,$01,$01,$01,$90,$01   ; row 15
  .byte $01,$02,$01,$01,$01,$01,$01,$03,$01,$01,$04,$05,$01,$06,$07,$08
  .byte $09,$0A,$0B,$0C,$0D,$0E,$01,$01,$0F,$01,$01,$01,$01,$01,$10,$01   ; row 16
  .byte $01,$11,$01,$01,$01,$01,$01,$03,$01,$01,$12,$13,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$16,$17,$01,$01,$0F,$01,$01,$01,$01,$01,$18,$01   ; row 17
  .byte $01,$19,$1A,$1A,$1A,$1A,$1A,$1B,$01,$01,$1C,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$1D,$01,$01,$1E,$1A,$1A,$1A,$1A,$1A,$1F,$01   ; row 18
  .byte $01,$60,$01,$01,$01,$01,$01,$01,$01,$61,$62,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$63,$64,$01,$01,$01,$01,$01,$01,$01,$65,$01   ; row 19
  .byte $66,$67,$01,$01,$01,$01,$01,$01,$68,$69,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$6A,$6B,$01,$01,$01,$01,$01,$01,$6C,$6D   ; row 20
  .byte $6E,$0C,$01,$01,$01,$01,$01,$6F,$70,$01,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$01,$71,$72,$01,$01,$01,$01,$01,$73,$74   ; row 21
  .byte $75,$01,$01,$01,$76,$77,$78,$79,$01,$01,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$01,$01,$7A,$7B,$7C,$7D,$01,$01,$01,$7E   ; row 22
  .byte $7F,$80,$81,$82,$83,$84,$01,$01,$01,$01,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$01,$01,$01,$01,$85,$86,$87,$88,$89,$8A   ; row 23
VDP_END_NAME:

TITLE_REC:
  .byte 0, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; grey border
  .byte 1, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; grey border
  .byte 22, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; grey border
  .byte 23, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; grey border
  .byte 3, 10, 12, $D0, $D1, $AC, $AD, $F0, $F1, $C0, $C1, $D0, $D1, $B8, $B9   ; DAVIDE
  .byte 4, 10, 12, $D2, $D3, $AE, $AF, $F2, $F3, $C2, $C3, $D2, $D3, $BA, $BB   ; DAVIDE
  .byte 6, 9, 14, $F0, $F1, $E8, $E9, $00, $00, $B8, $B9, $C4, $C5, $C0, $C1, $AC, $AD   ; VS ELIA
  .byte 7, 9, 14, $F2, $F3, $EA, $EB, $00, $00, $BA, $BB, $C6, $C7, $C2, $C3, $AE, $AF   ; VS ELIA
  .byte 9, 8, 15, $4A, $4F, $59, $53, $54, $49, $43, $4B, $20, $3D, $20, $4D, $4F, $56, $45   ; JOYSTICK = MOVE
  .byte 11, 5, 22, $42, $55, $54, $54, $4F, $4E, $20, $3D, $20, $53, $48, $4F, $4F, $54, $20, $4F, $52, $20, $4A, $55, $4D, $50   ; BUTTON = SHOOT OR JUMP
  .byte 13, 3, 25, $42, $45, $59, $4F, $4E, $44, $20, $54, $48, $45, $20, $41, $52, $43, $20, $3D, $20, $33, $20, $50, $4F, $49, $4E, $54, $53   ; BEYOND THE ARC = 3 POINTS
  .byte 15, 8, 16, $46, $49, $52, $53, $54, $20, $54, $4F, $20, $32, $31, $20, $57, $49, $4E, $53   ; FIRST TO 21 WINS
  .byte $FF

TITLE_PRESS:
  .byte 17, 3, 26, $42, $55, $54, $54, $4F, $4E, $20, $31, $20, $3D, $20, $31, $20, $50, $4C, $41, $59, $45, $52, $20, $56, $53, $20, $43, $50, $55   ; BUTTON 1 = 1 PLAYER VS CPU
  .byte 19, 6, 20, $42, $55, $54, $54, $4F, $4E, $20, $32, $20, $3D, $20, $32, $20, $50, $4C, $41, $59, $45, $52, $53   ; BUTTON 2 = 2 PLAYERS
  .byte $FF

END_REC:
  .byte 3, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 4, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 5, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 6, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 7, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 8, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 9, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 10, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; black panel
  .byte 2, 6, 20, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; erases the message
  .byte $FF

END_PRESS:
  .byte 9, 9, 14, $50, $52, $45, $53, $53, $20, $41, $20, $42, $55, $54, $54, $4F, $4E   ; PRESS A BUTTON
  .byte $FF

BANNER_D:
  .byte 3, 10, 12, $D0, $D1, $AC, $AD, $F0, $F1, $C0, $C1, $D0, $D1, $B8, $B9   ; DAVIDE
  .byte 4, 10, 12, $D2, $D3, $AE, $AF, $F2, $F3, $C2, $C3, $D2, $D3, $BA, $BB   ; DAVIDE
  .byte 6, 11, 10, $D8, $D9, $C0, $C1, $B0, $B1, $E8, $E9, $EC, $ED   ; WINS!
  .byte 7, 11, 10, $DA, $DB, $C2, $C3, $B2, $B3, $EA, $EB, $EE, $EF   ; WINS!
  .byte $FF

BANNER_E:
  .byte 3, 12, 8, $B8, $B9, $C4, $C5, $C0, $C1, $AC, $AD   ; ELIA
  .byte 4, 12, 8, $BA, $BB, $C6, $C7, $C2, $C3, $AE, $AF   ; ELIA
  .byte 6, 11, 10, $D8, $D9, $C0, $C1, $B0, $B1, $E8, $E9, $EC, $ED   ; WINS!
  .byte 7, 11, 10, $DA, $DB, $C2, $C3, $B2, $B3, $EA, $EB, $EE, $EF   ; WINS!
  .byte $FF

; messages on row 2 (20 characters, centred); index = MSG_* in the code
MSG_TAB:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; 0: (empty)
  .byte $00,$00,$00,$42,$41,$4C,$4C,$00,$54,$4F, $00, $44, $41, $56, $49, $44, $45, $00, $00, $00   ; 1: BALL TO DAVIDE
  .byte $00,$00,$00,$00,$42,$41,$4C,$4C,$00,$54, $4F, $00, $45, $4C, $49, $41, $00, $00, $00, $00   ; 2: BALL TO ELIA
  .byte $00,$00,$32,$2D,$50,$4F,$49,$4E,$54,$00, $42, $41, $53, $4B, $45, $54, $21, $00, $00, $00   ; 3: 2-POINT BASKET!
  .byte $00,$00,$33,$2D,$50,$4F,$49,$4E,$54,$00, $42, $41, $53, $4B, $45, $54, $21, $00, $00, $00   ; 4: 3-POINT BASKET!
  .byte $00,$00,$00,$00,$00,$00,$00,$42,$4C,$4F, $43, $4B, $21, $00, $00, $00, $00, $00, $00, $00   ; 5: BLOCK!
  .byte $00,$00,$00,$00,$42,$41,$4C,$4C,$00,$53, $54, $4F, $4C, $45, $4E, $21, $00, $00, $00, $00   ; 6: BALL STOLEN!

; ---- sound tables ----
V0_TAB:        .byte 13, 9, 12, 0      ; volume at the attack of the note
FLOOR_TAB:     .byte 9, 4, 8, 0        ; lowest volume reached by the decay
DECMASK_TAB:   .byte 7, 3, 3, 0        ; the volume drops by 1 when (age AND mask) = 0
VIB_TAB:       .byte 0, 1, 1, 0, 0, $FF, $FF, 0   ; vibrato +-1 step (signed)
; drums: 1 kick, 2 snare, 3 hi-hat, 4 cymbal
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7

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

SONGP_LO:      .byte <TITLE_LEAD,<TITLE_HARM,<TITLE_BASS,<TITLE_DRUM,<WIN_LEAD,<WIN_HARM,<WIN_BASS,<WIN_DRUM
SONGP_HI:      .byte >TITLE_LEAD,>TITLE_HARM,>TITLE_BASS,>TITLE_DRUM,>WIN_LEAD,>WIN_HARM,>WIN_BASS,>WIN_DRUM

; original songs: .byte note, length (frames); $FF = end of the track (note = MIDI - 35, 0 = rest)
TITLE_LEAD:
  .byte $29,$0F,$2C,$0F,$31,$1E,$2C,$0F,$29,$0F,$2C,$1E,$27,$0F,$2C,$0F
  .byte $30,$1E,$2C,$0F,$27,$0F,$2C,$1E,$29,$0F,$2E,$0F,$31,$1E,$2E,$0F
  .byte $29,$0F,$2E,$1E,$2A,$0F,$2E,$0F,$31,$1E,$2E,$0F,$2A,$0F,$2C,$1E
  .byte $2C,$1E,$29,$0F,$2C,$0F,$31,$3C,$30,$1E,$2C,$0F,$30,$0F,$33,$3C
  .byte $2E,$1E,$2A,$0F,$2E,$0F,$2C,$1E,$30,$1E,$31,$1E,$2C,$0F,$29,$0F
  .byte $25,$3C,$31,$78
  .byte $FF
TITLE_HARM:
  .byte $19,$0F,$1D,$0F,$20,$0F,$1D,$0F,$19,$0F,$1D,$0F,$20,$0F,$1D,$0F
  .byte $14,$0F,$18,$0F,$1B,$0F,$18,$0F,$14,$0F,$18,$0F,$1B,$0F,$18,$0F
  .byte $16,$0F,$19,$0F,$1D,$0F,$19,$0F,$16,$0F,$19,$0F,$1D,$0F,$19,$0F
  .byte $12,$0F,$16,$0F,$19,$0F,$16,$0F,$12,$0F,$16,$0F,$19,$0F,$16,$0F
  .byte $19,$0F,$1D,$0F,$20,$0F,$1D,$0F,$19,$0F,$1D,$0F,$20,$0F,$1D,$0F
  .byte $14,$0F,$18,$0F,$1B,$0F,$18,$0F,$14,$0F,$18,$0F,$1B,$0F,$18,$0F
  .byte $12,$0F,$16,$0F,$19,$0F,$16,$0F,$14,$0F,$18,$0F,$1B,$0F,$18,$0F
  .byte $19,$0F,$1D,$0F,$20,$0F,$1D,$0F,$19,$0F,$1D,$0F,$20,$0F,$1D,$0F
  .byte $1D,$78
  .byte $FF
TITLE_BASS:
  .byte $0D,$1E,$0D,$1E,$14,$1E,$0D,$1E,$08,$1E,$08,$1E,$0F,$1E,$08,$1E
  .byte $0A,$1E,$0A,$1E,$11,$1E,$0A,$1E,$06,$1E,$06,$1E,$0D,$1E,$06,$1E
  .byte $0D,$1E,$0D,$1E,$14,$1E,$0D,$1E,$08,$1E,$08,$1E,$0F,$1E,$08,$1E
  .byte $06,$1E,$06,$1E,$08,$1E,$0F,$1E,$0D,$1E,$0D,$1E,$14,$1E,$0D,$1E
  .byte $0D,$78
  .byte $FF
TITLE_DRUM:
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $04,$78
  .byte $FF
WIN_LEAD:
  .byte $2C,$0C,$2C,$0C,$31,$18,$30,$0C,$2E,$0C,$2C,$18,$2E,$0C,$2E,$0C
  .byte $31,$18,$2E,$0C,$2A,$0C,$2E,$18,$30,$0C,$30,$0C,$33,$18,$30,$0C
  .byte $2C,$0C,$30,$18,$31,$30,$2C,$18,$29,$18,$35,$18,$31,$0C,$2E,$0C
  .byte $31,$18,$35,$18,$36,$18,$31,$0C,$2E,$0C,$31,$18,$2A,$18,$33,$18
  .byte $30,$0C,$2C,$0C,$30,$18,$33,$18,$31,$0C,$35,$0C,$31,$0C,$35,$0C
  .byte $31,$30,$31,$60
  .byte $FF
WIN_HARM:
  .byte $19,$0C,$1D,$0C,$20,$0C,$1D,$0C,$19,$0C,$1D,$0C,$20,$0C,$1D,$0C
  .byte $1E,$0C,$22,$0C,$25,$0C,$22,$0C,$1E,$0C,$22,$0C,$25,$0C,$22,$0C
  .byte $20,$0C,$24,$0C,$27,$0C,$24,$0C,$20,$0C,$24,$0C,$27,$0C,$24,$0C
  .byte $19,$0C,$1D,$0C,$20,$0C,$1D,$0C,$19,$0C,$1D,$0C,$20,$0C,$1D,$0C
  .byte $22,$0C,$25,$0C,$29,$0C,$25,$0C,$22,$0C,$25,$0C,$29,$0C,$25,$0C
  .byte $1E,$0C,$22,$0C,$25,$0C,$22,$0C,$1E,$0C,$22,$0C,$25,$0C,$22,$0C
  .byte $20,$0C,$24,$0C,$27,$0C,$24,$0C,$20,$0C,$24,$0C,$27,$0C,$24,$0C
  .byte $19,$0C,$1D,$0C,$20,$0C,$1D,$0C,$19,$0C,$1D,$0C,$20,$0C,$1D,$0C
  .byte $1D,$60
  .byte $FF
WIN_BASS:
  .byte $0D,$18,$0D,$18,$14,$18,$0D,$18,$12,$18,$12,$18,$19,$18,$12,$18
  .byte $14,$18,$14,$18,$1B,$18,$14,$18,$0D,$18,$0D,$18,$14,$18,$0D,$18
  .byte $16,$18,$16,$18,$1D,$18,$16,$18,$12,$18,$12,$18,$19,$18,$12,$18
  .byte $14,$18,$14,$18,$1B,$18,$14,$18,$0D,$18,$0D,$18,$14,$18,$0D,$18
  .byte $0D,$60
  .byte $FF
WIN_DRUM:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $04,$60
  .byte $FF

; cheers: three "whoo!" going up in pitch (112 frames, one step every 2 frames)
CHEER_V:
  .byte $04,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$09,$04,$00,$00,$00,$04,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$09,$04,$00,$00,$00,$04,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$09,$04
CHEER_TL:
  .byte $B3,$A5,$9D,$97,$91,$8C,$84,$81,$81,$7F,$78,$72,$70,$71
  .byte $6F,$6A,$65,$9C,$9C,$9C,$A4,$98,$90,$8A,$85,$80,$79,$77
  .byte $76,$74,$6E,$69,$67,$67,$65,$61,$5C,$9C,$9C,$9C,$95,$87
  .byte $7F,$79,$73,$6F,$68,$65,$64,$61,$5C,$57,$55,$55,$53,$4F
CHEER_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
CHEER_CTL:
  .byte $77,$6E,$69,$64,$61,$5D,$58,$56,$56,$55,$50,$4C,$4B,$4B
  .byte $4A,$47,$43,$68,$68,$68,$6E,$65,$60,$5C,$59,$56,$51,$4F
  .byte $4F,$4D,$49,$46,$44,$45,$44,$40,$3D,$68,$68,$68,$63,$5A
  .byte $55,$51,$4D,$4A,$45,$43,$43,$41,$3D,$3A,$39,$38,$37,$34
CHEER_CTH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; effects: start of every effect in the EV* tables (1 = SCORE, 2 = MISS, 3 = BLOCK, 4 = STEAL)
EVT_OFF:
  .byte $00,$00,$2C,$48,$58
; length (frames)
EVT_LEN:
  .byte $00,$2C,$1C,$10,$16
; delay of the applause after the effect (0 = no applause)
EVT_ADLY:
  .byte $00,$1A,$00,$08,$0C
; canale A: volume / periodo
EVA_V:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A
  .byte $0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A
  .byte $0E,$0D,$0D,$0C,$0B,$0A,$09,$08,$06,$04,$02,$01,$0B,$0A,$09,$08
  .byte $07,$06,$05,$04,$03,$02,$06,$05,$04,$04,$03,$03,$02,$02,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0D,$09,$05,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0C
  .byte $0B,$0B,$0A,$09,$0D,$0D,$0C,$0C,$0B,$0A,$08,$05,$00,$00
EVA_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$2A,$2A,$2A,$2A
  .byte $2A,$2A,$2A,$2A,$2A,$2A,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$45,$45,$45,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$59,$59
  .byte $59,$59,$59,$59,$39,$39,$39,$39,$39,$39,$39,$39,$00,$00
EVA_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; rumore (canale B): volume / periodo
EVN_V:
  .byte $03,$06,$09,$0B,$0C,$0C,$0B,$0A,$08,$06,$05,$03,$02,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$09,$05,$02
  .byte $00,$00,$00,$00,$00,$00,$05,$03,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$0E,$0C,$0A,$08,$06,$04,$03
  .byte $02,$01,$00,$00,$00,$00,$00,$00,$04,$07,$09,$0A,$0A,$09,$07,$05
  .byte $03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EVN_P:
  .byte $06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02
  .byte $00,$00,$00,$00,$00,$00,$03,$03,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$04,$04,$05,$05,$05,$06,$06,$06
  .byte $07,$07,$00,$00,$00,$00,$00,$00,$03,$04,$05,$06,$07,$08,$09,$0A
  .byte $0B,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; channel C (low thump): volume / period
EVC_V:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0D,$0C,$0B,$09
  .byte $08,$06,$05,$04,$03,$02,$02,$01,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0E,$0D,$0B,$09,$07,$05,$03,$02
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EVC_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$49,$50,$57,$5D
  .byte $64,$6B,$72,$78,$7F,$86,$8D,$93,$9A,$A1,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$A1,$AD,$B8,$C4,$CF,$DB,$E6,$F2
  .byte $FD,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EVC_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; dribble: 6-frame thud on channel C of the chip of the player
DRIB_V:
  .byte $0D,$0B,$08,$05,$03,$01
DRIB_TL:
  .byte $38,$7E,$C4,$0B,$51,$97
DRIB_TH:
  .byte $02,$02,$02,$03,$03,$03
; applause: envelope (one value every 8 frames, 96 frames in all)
APPL_ENV:
  .byte $05,$09,$0C,$0D,$0E,$0E,$0E,$0D,$0C,$0A,$08,$06,$03
; final applause: envelope (one value every 16 frames, 150 frames in all)
CAPPL_ENV:
  .byte $07,$0B,$0E,$0F,$0F,$0F,$0F,$0E,$0C,$09

