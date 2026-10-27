;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_BUBBLES  -  Williams Bubbles (1982)                 ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: exerion (VDP, NMI + trampoline $0FD0, AY engine,     ;
;   2 players taking turns, 8.8 inertia)                       ;
;                                                              ;
;   - a soap bubble cleans a kitchen sink seen from above:     ;
;     8 directions with inertia, it grows eating the dirt:     ;
;     crumbs 100, ants 150, grease 200, double near the drain; ;
;     crumbs and ants slide slowly towards the drain           ;
;   - growing, the bubble gets eyes, then a mouth: with the    ;
;     whole face sponges and brushes cannot kill it any more,  ;
;     they bounce away (the bubble shrinks a little) and give  ;
;     500 / 800 if they fall into the drain                    ;
;   - razor blades kill, always. Roaches (1000) come out of    ;
;     the drain after it flashes red: deadly, unless the       ;
;     bubble points the broom at them (one roach per broom)    ;
;   - the cleaning lady comes out of the drain: touch her      ;
;     bristles to take the broom, her body takes it back; she  ;
;     sweeps up dirt and is worth 500 + 100 for every piece    ;
;     if the bubble with the face pushes her into the drain    ;
;   - with the whole face the drain flashes green: go in for   ;
;     a bonus of 1000 x size; a drain that is not green costs  ;
;     a life; if all the dirt is gone first, the faucet runs   ;
;     and the round is lost                                    ;
;   - levels 1-99 (then 01 again), 3 bubbles, one more every   ;
;     20000; 1 or 2 players taking turns (title: button 1 or   ;
;     button 2)                                                ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     eating (higher when bigger), pop, drain gurgle, faucet,  ;
;     roach alarm, broom, bounce, start tune, level jingle     ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
ALIVE       = $32      ; 2 bytes: bubbles left to every player (the one playing included)
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
LEVEL       = $40      ; ---- block of the player, saved: level 1-99
NEXTX       = $41      ;      next extra bubble (BCD, ten thousands)
PBLOCK      = 2
BXL         = $44      ; bubble: centre 8.8
BX          = $45
BYL         = $46
BY          = $47
BVXL        = $48      ; velocity 8.8 signed
BVXH        = $49
BVYL        = $4A
BVYH        = $4B
GROW        = $4C      ; dirt eaten (minus the bounces)
SIZE        = $4D      ; 0-7
RAD         = $4E      ; radius of this size
BST         = $4F      ; 0 playing, 1 popping, 2 going down the drain, 3 lost, 4 level over
BT          = $50      ; timer of BST
FACE        = $51      ; 1 = eyes and mouth
BROOM       = $52      ; 1 = the bubble holds the broom
BDIR        = $53      ; direction the bubble faces (0 up, clockwise)
DIRTN       = $54      ; dirt left: on the floor, ants walking and ants still to come
ANTS        = $55      ; ants still to come
ANTT        = $56      ; frames before the next ant
ROACHT      = $57      ; 4-frame units before the next roach
DRW         = $58      ; frames of red flashing left (a roach is coming)
DRCOL       = $59      ; colour of the drain now
ROWSC       = $5A      ; row of the sink checked for sliding crumbs
DOWNOK      = $5B      ; 1 = the bubble went down a green drain
WAITF       = $5C
HUDD        = $5D      ; 1 = the HUD changed
FIRSTT      = $5E      ; 1 = first turn of the game: start tune
JOYC        = $5F      ; both joysticks drive the player playing

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
DIFF        = $70      ; difficulty 0-15 (level - 1, at most 15)
BASIN       = $71      ; colour of the basin
TP          = $72      ; 2 bytes: text records
RR          = $74      ; first object in the SAT (turns)
CNT         = $75
TX          = $76      ; target / point being tested
TY          = $77
NROACH      = $78      ; roaches at the same time
DRIFTM      = $79      ; a crumb slides when (random AND DRIFTM) = 0
AIMM        = $7A      ; roaches aim again when (frame AND AIMM) = 0
SPB         = $7B      ; speed bonus of the enemies
NEAR        = $7C      ; 1 = the bubble is near the drain (dirt counts double)
SHOWP       = $7D      ; 1 = "PLAYER n" at the start of the round
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)

PTS_L       = $80      ; points to add (BCD)
PTS_M       = $81
PTS_H       = $82
ROACHI      = $83      ; 4-frame units between two roaches
RLIFE       = $84      ; 8-frame units a roach stays out
BONSZ       = $85      ; size of the bubble going down the drain (1-8)
WATER       = $86      ; 1 = the faucet runs
HWX         = $87      ; half size of the object being tested
HWY         = $88
LGRACE      = $89      ; frames the lady cannot take back the broom just given
SATB        = $8A      ; bytes of the SAT to copy
ANTC        = $8B      ; colour of the ants (they must show on the basin)

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
CMD_START  = 2           ; the start tune

; ---------------- objects: 0 the lady, 1-4 sponges and brushes, 5-6 roaches, 7-13 ants
NO         = 14
O_K        = $0300       ; kind K_* (0 = free)
O_ST       = $0310       ; state ST_*
O_XL       = $0320       ; centre 8.8
O_X        = $0330
O_YL       = $0340
O_Y        = $0350
O_VXL      = $0360       ; velocity 8.8 signed
O_VXH      = $0370
O_VYL      = $0380
O_VYH      = $0390
O_T        = $03A0       ; timer of the state
O_D        = $03B0       ; direction 0-7 (0 up, clockwise)
O_SP       = $03C0       ; speed class (VEL_L / VEL_H)
O_V        = $03D0       ; the lady: dirt swept up (0-9)
O_FC       = $03E0       ; the lady: 0 faces right, 8 faces left

K_LADY     = 1
K_SPONGE   = 2
K_BRUSH    = 3
K_ROACH    = 4
K_ANT      = 5

ST_WALK    = 1           ; about its business
ST_PUSH    = 2           ; pushed away by the bubble with the face
ST_OUT     = 3           ; coming out of the drain (harmless)
ST_HOME    = 4           ; going back into the drain
ST_WAIT    = 5           ; off the field, O_T frames before it comes (back)
ST_DIE     = 6           ; a roach splashed by the broom

PSAVE      = $04A0       ; 2 x 2 bytes: block of every player
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
GRID       = $0800       ; tiles of the sink, rows 3-20 x 32 columns (576 bytes)

; ---------------- parameters ----------------
BX0         = 128        ; the bubble starts here
BY0         = 150
DRAIN_X     = 128        ; centre of the drain
DRAIN_Y     = 96
ACC         = $14        ; inertia of the bubble (8.8)
FRIC        = $08
VMAX        = $0170
VNEG        = $10000-VMAX
FACE_SIZE   = 5          ; the mouth comes with this size
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
;  TITLE: the name, the scoring table and a big bubble
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  STZ WATER
  JSR CLEAR_NT
  LDA #1                       ; dirt on black
  STA BASIN
  JSR SET_COLOURS
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
  LDX #9                       ; a crumb and a grease stain in the table
  LDY #8
  JSR NT_XY
  LDA #T_CRUMB
  STA VDATA
  LDX #13
  LDY #8
  JSR NT_XY
  LDA #T_GREASE
  STA VDATA
  LDX #$00                     ; ant, lady, roach and the bubble (sprites)
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
  CPX #9
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

; one frame of the title
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: level 1, 3 bubbles for every player
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
  LDA #1
  STA LEVEL
  LDA #$02
  STA NEXTX
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then a ROUND: the sink with new dirt
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE ROUND_START
  INC SHOWP

ROUND_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  STZ WATER
  JSR SET_LEVEL
  JSR SET_COLOURS
  JSR CLEAR_NT
  JSR DRAW_TOP
  JSR BUILD_GRID
  JSR DRAW_SINK
  JSR DRAW_BOTTOM
  JSR BUBBLE_RESET
  JSR START_OBJECTS
  LDA SHOWP
  BEQ .rs_lv
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.rs_lv:
  LDA #<TXT_LEVEL
  STA TP
  LDA #>TXT_LEVEL
  STA TP+1
  JSR PRINT
  LDA LEVEL
  JSR BIN2BCD
  JSR PUT_2
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA FIRSTT
  BEQ .rs_jingle
  STZ FIRSTT                   ; the start tune, to the end
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.rs_tune:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .rs_tune
  BRA .rs_go
.rs_jingle:
  LDA #W_LEVEL
  LDX #2
  JSR SFX_WHISTLE
  LDA #120
  JSR WAIT_FRAMES
.rs_go:
  JSR VDP_INT_OFF
  LDX #7                       ; the messages away: the sink again
  JSR DRAW_GROW
  LDX #8
  JSR DRAW_GROW
  JSR VDP_INT_ON
  STZ SHOWP


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
  JSR UPDATE_BUBBLE
  JSR UPDATE_OBJECTS
  JSR SPAWN
  JSR DRIFT
  JSR DRAIN
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA BST
  CMP #3
  BNE .gl_n3
  JMP LOSE_LIFE
.gl_n3:
  CMP #4
  BNE .gl_n4
  JMP LEVEL_END
.gl_n4:
  CMP #0
  BNE GAME_LOOP
  LDA DIRTN                    ; all the dirt gone before the drain: the faucet
  BNE GAME_LOOP
  JMP FAUCET


; ===============================================================
;  END OF A ROUND
; ===============================================================
; down a green drain: bonus 1000 x size, then the next level
LEVEL_END:
  JSR VDP_INT_OFF
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA BONSZ
  ORA #$30
  STA VDATA
  LDA #'0'
  STA VDATA
  STA VDATA
  STA VDATA
  JSR VDP_INT_ON
  LDA #40
  JSR WAIT_FRAMES
.le_b:                         ; 1000 at a time
  STZ PTS_L
  STZ PTS_H
  LDA #$10
  STA PTS_M
  JSR VDP_INT_OFF
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  LDA #10
  JSR WAIT_FRAMES
  DEC BONSZ
  BNE .le_b
  LDA #90
  JSR WAIT_FRAMES
  INC LEVEL                    ; after 99 the counter starts again from 01
  LDA LEVEL
  CMP #100
  BCC .le_n
  LDA #1
  STA LEVEL
.le_n:
  JMP ROUND_START

; all the dirt gone before the bubble went down: the faucet runs, the round is lost
FAUCET:
  LDA #1
  STA WATER
  LDA #S_WATER
  LDX #2
  JSR SFX_BOOM
  LDA #150
  STA WAITF
.fa_l:
  JSR VDP_INT_OFF
  LDA WAITF
  CMP #90
  BNE .fa_s
  LDA #5                       ; the sink fills up
  STA BASIN
  JSR SET_COLOURS
  LDA #$0E
  JSR DRAIN_COLOUR
  LDA #<TXT_NOBON
  STA TP
  LDA #>TXT_NOBON
  STA TP+1
  JSR PRINT
.fa_s:
  LDA WAITF                    ; the bubble pops in the flood
  CMP #40
  BNE .fa_p
  JSR POP
.fa_p:
  LDA BST
  BEQ .fa_b
  JSR UPDATE_BUBBLE
.fa_b:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  DEC WAITF
  BNE .fa_l
  ; fall into LOSE_LIFE

LOSE_LIFE:
  LDX CURP
  DEC ALIVE,X
  JSR SAVE_PLAYER
  LDA #40
  JSR WAIT_FRAMES
  LDA NPL                      ; the other player, if he still has bubbles
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
  JSR HIDE_SPRITES
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
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  JMP TITLE


; ===============================================================
;  LEVELS: what the sink holds (table index = difficulty 0-15)
; ===============================================================
SET_LEVEL:
  LDA LEVEL
  DEC A
  CMP #16
  BCC .sl_d
  LDA #15
.sl_d:
  STA DIFF
  TAX
  LDA LV_DRIFT,X
  STA DRIFTM
  LDA LV_AIM,X
  STA AIMM
  LDA LV_SPB,X
  STA SPB
  LDA LV_NROACH,X
  STA NROACH
  LDA LV_ROACHI,X
  STA ROACHI
  LDA LV_RLIFE,X
  STA RLIFE
  LDA LEVEL                    ; the colour of the sink changes every level
  DEC A
  AND #$03
  TAX
  LDA BASIN_COL,X
  STA BASIN
  LDA ANT_COL,X
  STA ANTC
  RTS


; ===============================================================
;  THE BUBBLE: 8 directions with inertia
; ===============================================================
BUBBLE_RESET:
  LDA #BX0
  STA BX
  LDA #BY0
  STA BY
  STZ BXL
  STZ BYL
  STZ BVXL
  STZ BVXH
  STZ BVYL
  STZ BVYH
  STZ GROW
  STZ SIZE
  STZ FACE
  STZ BROOM
  STZ BST
  STZ BDIR
  LDA RADIUS
  STA RAD
  RTS

UPDATE_BUBBLE:
  LDA BST
  BEQ .ub_play
  CMP #1
  BNE .ub_down
  DEC BT                       ; popping
  BNE .ub_r
  LDA #3
  STA BST
.ub_r:
  RTS
.ub_down:
  CMP #2
  BNE .ub_r
  LDA #DRAIN_X                 ; going down the drain: smaller and smaller
  STA BX
  LDA #DRAIN_Y
  STA BY
  DEC BT
  BEQ .ub_gone
  LDA BT
  LSR A
  LSR A
  LSR A
  CMP SIZE
  BCS .ub_r
  STA SIZE
  RTS
.ub_gone:
  LDA #3                       ; not green: a bubble lost
  LDX DOWNOK
  BEQ .ub_g
  LDA #4
.ub_g:
  STA BST
  RTS
.ub_play:
  LDA JOYC                     ; the direction it faces
  AND #$0F
  TAX
  LDA JOY_DIR,X
  BMI .ub_nd
  STA BDIR
.ub_nd:
  LDA BVXL                     ; ---- horizontal
  STA T0
  LDA BVXH
  STA T1
  LDA JOYC
  AND #%00001100
  JSR AXIS
  LDA T0
  STA BVXL
  LDA T1
  STA BVXH
  LDA BVYL                     ; ---- vertical
  STA T0
  LDA BVYH
  STA T1
  LDA JOYC
  AND #%00000011
  ASL A
  ASL A                        ; up -> bit 2 (minus), down -> bit 3 (plus)
  JSR AXIS
  LDA T0
  STA BVYL
  LDA T1
  STA BVYH
  CLC                          ; ---- move; the sides of the sink bounce it back
  LDA BXL
  ADC BVXL
  STA BXL
  LDA BX
  ADC BVXH
  STA BX
  LDA #16
  CLC
  ADC RAD
  CMP BX
  BCC .ub_x1
  STA BX                       ; left side
  BRA .ub_bx
.ub_x1:
  LDA #240
  SEC
  SBC RAD
  CMP BX
  BCS .ub_y
  STA BX                       ; right side
.ub_bx:
  LDA BVXH
  STA T1
  LDA BVXL
  JSR BOUNCE
  STA BVXL
  LDA T1
  STA BVXH
.ub_y:
  CLC
  LDA BYL
  ADC BVYL
  STA BYL
  LDA BY
  ADC BVYH
  STA BY
  LDA #24
  CLC
  ADC RAD
  CMP BY
  BCC .ub_y1
  STA BY
  BRA .ub_by
.ub_y1:
  LDA #168
  SEC
  SBC RAD
  CMP BY
  BCS .ub_e
  STA BY
.ub_by:
  LDA BVYH
  STA T1
  LDA BVYL
  JSR BOUNCE
  STA BVYL
  LDA T1
  STA BVYH
.ub_e:
  JMP EAT

; A / T1 = velocity 8.8: back at half speed (A = low byte, T1 = high byte)
BOUNCE:
  EOR #$FF
  CLC
  ADC #1
  STA T0
  LDA T1
  EOR #$FF
  ADC #0
  CMP #$80                     ; signed shift right
  ROR A
  STA T1
  LDA T0
  ROR A
  RTS

; T0 / T1 = speed 8.8; A bit 3 = push +, bit 2 = push -: accelerate or slow down
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

; the bubble pops (keeps X)
POP:
  LDA #1
  STA BST
  LDA #30
  STA BT
  STZ BROOM
  PHX
  LDA #S_POP
  LDX #2
  JSR SFX_BOOM
  PLX
  RTS


; ===============================================================
;  EATING: the tiles under the bubble (crumbs, grease, blades)
; ===============================================================
EAT:
  JSR NEAR_DRAIN
  LDX SIZE
  LDA EAT_R,X
  STA T5
  LDA BY                       ; rows T2..T3
  SEC
  SBC T5
  LSR A
  LSR A
  LSR A
  STA T2
  LDA BY
  CLC
  ADC T5
  LSR A
  LSR A
  LSR A
  STA T3
  LDA BX                       ; columns T4..T5
  CLC
  ADC T5
  LSR A
  LSR A
  LSR A
  STA T6
  LDA BX
  SEC
  SBC T5
  LSR A
  LSR A
  LSR A
  STA T4
  LDA T6
  STA T5
.ea_row:
  LDX T2
  JSR GRID_ROW                 ; PTR = the row in the grid
  LDY T4
.ea_col:
  LDA (PTR),Y
  CMP #T_CRUMB
  BEQ .ea_crumb
  CMP #T_GREASE
  BEQ .ea_grease
  CMP #T_BLADE
  BNE .ea_next
  JMP POP                      ; a razor blade
.ea_crumb:
  LDA #$01                     ; 100
  LDX #1
  BRA .ea_eat
.ea_grease:
  LDA #$02                     ; 200
  LDX #2
.ea_eat:
  STZ PTS_L
  STA PTS_M
  STZ PTS_H
  STX CNT
  LDA #T_FLOOR
  STA (PTR),Y
  PHY
  LDX T2
  JSR NT_XY
  LDA #T_FLOOR
  STA VDATA
  JSR AWARD_DIRT
  LDA CNT
  JSR ADD_GROW
  PLY
.ea_next:
  INY
  CPY T5
  BCC .ea_col
  BEQ .ea_col
  INC T2
  LDA T3
  CMP T2
  BCS .ea_row
  RTS

; X = screen row 3-20: PTR = its row in GRID (keeps Y)
GRID_ROW:
  TXA
  SEC
  SBC #3
  STA PTR+1
  LDA #0
  LSR PTR+1                    ; row * 32 = high byte row / 8, low byte (row AND 7) * 32
  ROR A
  LSR PTR+1
  ROR A
  LSR PTR+1
  ROR A
  STA PTR
  LDA PTR+1
  CLC
  ADC #>GRID
  STA PTR+1
  RTS

; NEAR = 1 when the bubble is near the drain
NEAR_DRAIN:
  STZ NEAR
  LDA BX
  SEC
  SBC #DRAIN_X-40
  CMP #80
  BCS .nd_r
  LDA BY
  SEC
  SBC #DRAIN_Y-32
  CMP #64
  BCS .nd_r
  INC NEAR
.nd_r:
  RTS

; a piece of dirt eaten: PTS (doubled near the drain), one less, the sound (keeps Y)
AWARD_DIRT:
  LDA NEAR
  BEQ .ad_s
  SED
  CLC
  LDA PTS_L
  ADC PTS_L
  STA PTS_L
  LDA PTS_M
  ADC PTS_M
  STA PTS_M
  LDA PTS_H
  ADC PTS_H
  STA PTS_H
  CLD
.ad_s:
  JSR ADD_SCORE
  DEC DIRTN
  PHX
  LDA #W_EAT
  CLC
  ADC SIZE
  LDX #0
  JSR SFX_WHISTLE
  PLX
  RTS

; A = points of growth: the size follows (the face too)
ADD_GROW:
  CLC
  ADC GROW
  CMP #40
  BCC .ag_s
  LDA #40
.ag_s:
  STA GROW
  ; fall into SET_SIZE

; the size from GROW; a sound when it changes up
SET_SIZE:
  PHX
  PHY
  LDX #7
.ss_l:
  LDA GROW
  CMP GROW_T,X
  BCS .ss_f
  DEX
  BNE .ss_l
.ss_f:
  CPX SIZE
  BEQ .ss_e
  BCC .ss_set                  ; smaller: no sound
  LDA #W_GROW
  CPX #FACE_SIZE
  BNE .ss_snd
  LDA #W_FACE                  ; the mouth: the face is complete
.ss_snd:
  PHX
  LDX #0
  JSR SFX_WHISTLE
  PLX
.ss_set:
  STX SIZE
  LDA RADIUS,X
  STA RAD
  STZ FACE
  CPX #FACE_SIZE
  BCC .ss_e
  INC FACE
.ss_e:
  PLY
  PLX
  RTS

; the bubble with the face bounced something: a little smaller
SHRINK:
  LDA GROW
  SEC
  SBC #2
  BCS .sh_s
  LDA #0
.sh_s:
  STA GROW
  JMP SET_SIZE


; ===============================================================
;  PLAYERS: save / load the block LEVEL-NEXTX
; ===============================================================
SAVE_PLAYER:                   ; X = player
  LDY PS_OFF,X
  LDX #$00
.sp_b:
  LDA LEVEL,X
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
  STA LEVEL,X
  INY
  INX
  CPX #PBLOCK
  BNE .lp_b
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a bubble more every 20000
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
  INC ALIVE,X
  SED
  LDA NEXTX
  CLC
  ADC #$02
  CLD
  BCC .as_x
  LDA #$FF                     ; past 980000: no more
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
;  OBJECTS: the lady, sponges and brushes, roaches, ants
; ===============================================================
; start of a round: the lady waits in the drain, sponges and brushes in the corners
START_OBJECTS:
  LDX #NO-1
.so_c:
  STZ O_K,X
  STZ O_ST,X
  DEX
  BPL .so_c
  LDA #K_LADY
  STA O_K
  LDA #ST_WAIT
  STA O_ST
  LDA #70
  STA O_T
  STZ O_V
  STZ O_FC
  LDX DIFF                     ; sponges and brushes
  LDA LV_ENEMY,X
  STA CNT
  LDX #1
.so_e:
  LDA SLOT_K,X
  STA O_K,X
  LDA #ST_WALK
  STA O_ST,X
  JSR KIND_SPEED
  TXA
  DEC A
  TAY
  JSR AT_CORNER
  INX
  DEC CNT
  BNE .so_e
  LDX DIFF                     ; the ants come later, one at a time
  LDA LV_ANTS,X
  STA ANTS
  CLC
  ADC DIRTN
  STA DIRTN
  LDA #90
  STA ANTT
  LDA LV_ROACH1,X
  STA ROACHT
  STZ DRW
  STZ LGRACE
  LDA #3
  STA ROWSC
  LDA #$0E
  JMP DRAIN_COLOUR

; X = object, Y = corner 0-3: there, heading inside
AT_CORNER:
  LDA CORN_X,Y
  STA O_X,X
  LDA CORN_Y,Y
  STA O_Y,X
  STZ O_XL,X
  STZ O_YL,X
  LDA CORN_D,Y
  JMP SET_VEL

; X = object: speed class of its kind (and of the level)
KIND_SPEED:
  LDY O_K,X
  LDA SPEED_K,Y
  CPY #K_ANT
  BEQ .ks_ant
  CPY #K_LADY
  BEQ .ks_s
  CPY #K_ROACH
  BNE .ks_b
  PHA                          ; roaches: half the bonus
  LDA SPB
  LSR A
  STA T0
  PLA
  CLC
  ADC T0
  BRA .ks_s
.ks_b:
  CLC
  ADC SPB
  BRA .ks_s
.ks_ant:
  LDA DIFF
  LSR A
  LSR A
  LSR A
.ks_s:
  STA O_SP,X
  RTS

; X = object, A = direction: velocity from the speed class (keeps X)
SET_VEL:
  AND #$07
  STA O_D,X
  STA T0
  LDA O_SP,X
  ASL A
  ASL A
  ASL A
  STA T1
  ORA T0
  TAY
  LDA VEL_L,Y
  STA O_VXL,X
  LDA VEL_H,Y
  STA O_VXH,X
  LDA T0                       ; Y = X of the direction turned back by 90 degrees
  CLC
  ADC #6
  AND #$07
  ORA T1
  TAY
  LDA VEL_L,Y
  STA O_VYL,X
  LDA VEL_H,Y
  STA O_VYH,X
  LDA O_K,X                    ; the lady faces where she walks
  CMP #K_LADY
  BNE .sv_r
  LDY O_D,X
  LDA FACE_D,Y
  BMI .sv_r
  STA O_FC,X
.sv_r:
  RTS

; X = object, TX / TY = target: A = direction 0-7 towards it
AIM:
  STZ T2                       ; bit 1 = right, bit 0 = down
  LDA TX
  SEC
  SBC O_X,X
  BCS .am_r
  EOR #$FF
  INC A
  BRA .am_x
.am_r:
  INC T2
  INC T2
.am_x:
  STA T0
  LDA TY
  SEC
  SBC O_Y,X
  BCS .am_d
  EOR #$FF
  INC A
  BRA .am_y
.am_d:
  INC T2
.am_y:
  STA T1
  LDA T0                       ; horizontal if dx / 2 > dy
  LSR A
  CMP T1
  BCC .am_nh
  BEQ .am_nh
  LDY T2
  BRA .am_t
.am_nh:
  LDA T1                       ; vertical if dy / 2 > dx, else diagonal
  LSR A
  CMP T0
  BCC .am_dg
  BEQ .am_dg
  LDA T2
  ORA #4
  TAY
  BRA .am_t
.am_dg:
  LDA T2
  ORA #8
  TAY
.am_t:
  LDA AIM_TAB,Y
  RTS

; X = object: aim at the drain
AIM_DRAIN:
  LDA #DRAIN_X
  STA TX
  LDA #DRAIN_Y
  STA TY
  JSR AIM
  JMP SET_VEL

; X = object: aim at the bubble
AIM_BUBBLE:
  LDA BX
  STA TX
  LDA BY
  STA TY
  JSR AIM
  JMP SET_VEL

; X = object: a random direction
RND_DIR:
  JSR NEXT_RND
  JMP SET_VEL

; X = object: one step
MOVE:
  CLC
  LDA O_XL,X
  ADC O_VXL,X
  STA O_XL,X
  LDA O_X,X
  ADC O_VXH,X
  STA O_X,X
  CLC
  LDA O_YL,X
  ADC O_VYL,X
  STA O_YL,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  RTS

; X = object: one step, the sides of the sink turn it back
MOVE_W:
  JSR MOVE
  LDA O_X,X
  CMP #24
  BCC .mw_xl
  CMP #233
  BCC .mw_y
  LDA #232
  BRA .mw_xs
.mw_xl:
  LDA #24
.mw_xs:
  STA O_X,X
  LDA O_D,X                    ; mirror left / right
  EOR #$FF
  INC A
  JSR SET_VEL
.mw_y:
  LDA O_Y,X
  CMP #32
  BCC .mw_yt
  CMP #161
  BCC .mw_r
  LDA #160
  BRA .mw_ys
.mw_yt:
  LDA #32
.mw_ys:
  STA O_Y,X
  LDA #4                       ; mirror up / down
  SEC
  SBC O_D,X
  JSR SET_VEL
.mw_r:
  RTS

; X = object: carry set if it touches the bubble
COLLIDE:
  LDY O_K,X
  LDA RAD
  CLC
  ADC HW_X,Y
  STA T1
  LDA RAD
  CLC
  ADC HW_Y,Y
  STA T2
  LDA O_X,X
  SEC
  SBC BX
  BCS .co_x
  EOR #$FF
  INC A
.co_x:
  CMP T1
  BCS .co_no
  LDA O_Y,X
  SEC
  SBC BY
  BCS .co_y
  EOR #$FF
  INC A
.co_y:
  CMP T2
  BCS .co_no
  SEC
  RTS
.co_no:
  CLC
  RTS

; X = object: carry set if it is on the drain (A = distance allowed)
ON_DRAIN:
  STA T1
  LDA O_X,X
  SEC
  SBC #DRAIN_X
  BCS .od_x
  EOR #$FF
  INC A
.od_x:
  CMP T1
  BCS .od_no
  LDA O_Y,X
  SEC
  SBC #DRAIN_Y
  BCS .od_y
  EOR #$FF
  INC A
.od_y:
  CMP T1
  BCS .od_no
  SEC
  RTS
.od_no:
  CLC
  RTS

; ---------------------------------------------------------------
UPDATE_OBJECTS:
  LDA LGRACE
  BEQ .uo_g
  DEC LGRACE
.uo_g:
  LDA BST                      ; the field stops while the bubble is not playing
  BEQ .uo_go
  RTS
.uo_go:
  LDX #NO-1
.uo_l:
  LDA O_K,X
  BEQ .uo_n
  JSR OBJ_ONE
.uo_n:
  DEX
  BPL .uo_l
  RTS

; X = object: one frame of its state
OBJ_ONE:
  LDA O_ST,X
  CMP #ST_WALK
  BNE .oo_1
  JMP OB_WALK
.oo_1:
  CMP #ST_PUSH
  BNE .oo_2
  JMP OB_PUSH
.oo_2:
  CMP #ST_OUT
  BEQ OB_OUT
  CMP #ST_HOME
  BNE .oo_3
  JMP OB_HOME
.oo_3:
  CMP #ST_WAIT
  BEQ OB_WAIT
  ; ST_DIE: the splash, then nothing
  DEC O_T,X
  BNE .oo_r
  STZ O_K,X
  STZ O_ST,X
.oo_r:
  RTS

; off the field: the lady comes out of the drain, a sponge or a brush from a corner
OB_WAIT:
  DEC O_T,X
  BNE .ow_r
  LDA O_K,X
  CMP #K_LADY
  BNE .ow_c
  LDA #DRAIN_X
  STA O_X,X
  LDA #DRAIN_Y
  STA O_Y,X
  LDA #ST_OUT
  STA O_ST,X
  LDA #40
  STA O_T,X
  JSR KIND_SPEED
  LDA #4
  JMP SET_VEL
.ow_c:
  LDA #ST_WALK
  STA O_ST,X
  JSR KIND_SPEED
  JSR NEXT_RND
  AND #$03
  TAY
  JMP AT_CORNER
.ow_r:
  RTS

; coming out of the drain: still, harmless
OB_OUT:
  DEC O_T,X
  BNE .ou_r
  LDA #ST_WALK
  STA O_ST,X
  LDA O_K,X
  CMP #K_LADY
  BNE .ou_roach
  LDA #110                     ; the lady: about 15 seconds
  STA O_T,X
  JMP RND_DIR
.ou_roach:
  LDA RLIFE
  STA O_T,X
  JMP AIM_BUBBLE
.ou_r:
  RTS

; going back down the drain
OB_HOME:
  JSR AIM_DRAIN
  JSR MOVE
  LDA #4
  JSR ON_DRAIN
  BCC .oh_hit
  STZ O_K,X                    ; gone
  STZ O_ST,X
  RTS
.oh_hit:
  LDA O_K,X
  CMP #K_ROACH
  BNE .oh_l
  JMP ROACH_HIT
.oh_l:
  JMP LADY_HIT

; pushed away by the bubble: into the drain = points
OB_PUSH:
  JSR MOVE_W
  LDA #7
  JSR ON_DRAIN
  BCS .op_drain
  DEC O_T,X
  BNE .op_r
  LDA #ST_WALK
  STA O_ST,X
  LDA #40                      ; the lady: some more time out
  STA O_T,X
  JSR KIND_SPEED
  JMP RND_DIR
.op_r:
  RTS
.op_drain:
  STZ PTS_L
  STZ PTS_H
  LDA O_K,X
  CMP #K_LADY
  BNE .op_sb
  LDA O_V,X                    ; the lady: 500 + 100 for every piece of dirt she swept
  CLC
  ADC #5
  PHX
  JSR BIN2BCD
  PLX
  STA PTS_M
  STZ O_K,X
  STZ O_ST,X
  BRA .op_pts
.op_sb:
  LDY O_K,X
  LDA DRAIN_PTS,Y
  STA PTS_M
  LDA #ST_WAIT                 ; it comes back later from a corner
  STA O_ST,X
  LDA #240
  STA O_T,X
.op_pts:
  JSR ADD_SCORE
  PHX
  LDA #S_SPLASH
  LDX #1
  JSR SFX_BOOM
  LDA #W_GURGLE
  JSR SFX_WHISTLE
  PLX
  RTS

; about its business, by kind
OB_WALK:
  LDA O_K,X
  CMP #K_ANT
  BEQ OB_ANT
  CMP #K_ROACH
  BNE .ow_1
  JMP OB_ROACH
.ow_1:
  CMP #K_LADY
  BNE .ow_2
  JMP OB_LADY
.ow_2:
  ; ---- sponge / brush: straight on, turning now and then
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC FRAME_CNT
  AND #$3F
  BNE .sb_m
  LDA O_K,X
  CMP #K_SPONGE
  BNE .sb_br
  LDA DIFF                     ; the sponge: more and more often after the bubble
  ASL A
  ASL A
  ASL A
  ADC #$50
  STA T0
  JSR NEXT_RND
  CMP T0
  BCS .sb_rnd
  JSR AIM_BUBBLE
  BRA .sb_m
.sb_rnd:
  JSR RND_DIR
  BRA .sb_m
.sb_br:
  JSR NEXT_RND                 ; the brush: diagonals
  ORA #$01
  JSR SET_VEL
.sb_m:
  JSR MOVE_W
  JSR COLLIDE
  BCC .sb_r
  LDA FACE
  BNE .sb_face
  JMP POP                      ; no face: deadly
.sb_face:
  JSR REPEL
  JMP SHRINK
.sb_r:
  RTS

; ---- ant: slowly to the drain, a little wobbling
OB_ANT:
  TXA
  ASL A
  ASL A
  ASL A
  CLC
  ADC FRAME_CNT
  AND #$1F
  BNE .an_m
  LDA #DRAIN_X
  STA TX
  LDA #DRAIN_Y
  STA TY
  JSR AIM
  STA T3
  JSR NEXT_RND
  AND #$03
  TAY
  LDA WOBBLE,Y
  CLC
  ADC T3
  JSR SET_VEL
.an_m:
  JSR MOVE
  LDA #5
  JSR ON_DRAIN
  BCC .an_eat
  STZ O_K,X                    ; down the drain: lost dirt
  STZ O_ST,X
  DEC DIRTN
  RTS
.an_eat:
  JSR COLLIDE
  BCC .an_r
  STZ O_K,X                    ; eaten: 150
  STZ O_ST,X
  JSR NEAR_DRAIN
  LDA #$50
  STA PTS_L
  LDA #$01
  STA PTS_M
  STZ PTS_H
  JSR AWARD_DIRT
  LDA #1
  JMP ADD_GROW
.an_r:
  RTS

; ---- roach: after the bubble, faster than it, then back home
OB_ROACH:
  LDA FRAME_CNT
  AND #$07
  BNE .ro_a
  DEC O_T,X
  BNE .ro_a
  LDA #ST_HOME
  STA O_ST,X
  RTS
.ro_a:
  LDA FRAME_CNT
  AND AIMM
  BNE .ro_m
  JSR AIM_BUBBLE
.ro_m:
  JSR MOVE_W
  ; fall into ROACH_HIT

; X = roach: the broom pointed at it kills it, else it pops the bubble
ROACH_HIT:
  LDA BROOM
  BEQ .rh_body
  LDA SIZE
  ASL A
  ASL A
  ASL A
  ORA BDIR
  TAY
  LDA BX                       ; the tip of the broom
  CLC
  ADC TIP_DX,Y
  STA TX
  LDA BY
  CLC
  ADC TIP_DY,Y
  STA TY
  LDA O_X,X
  SEC
  SBC TX
  BCS .rh_x
  EOR #$FF
  INC A
.rh_x:
  CMP #10
  BCS .rh_body
  LDA O_Y,X
  SEC
  SBC TY
  BCS .rh_y
  EOR #$FF
  INC A
.rh_y:
  CMP #10
  BCS .rh_body
  LDA #ST_DIE                  ; swatted: 1000, the broom is gone
  STA O_ST,X
  LDA #24
  STA O_T,X
  STZ BROOM
  STZ PTS_L
  STZ PTS_H
  LDA #$10
  STA PTS_M
  JSR ADD_SCORE
  PHX
  LDA #W_SWAT
  LDX #0
  JSR SFX_WHISTLE
  LDA #S_POP
  LDX #1
  JSR SFX_BOOM
  PLX
  RTS
.rh_body:
  JSR COLLIDE
  BCC .rh_r
  JMP POP
.rh_r:
  RTS

; ---- the lady: walks about sweeping up dirt, then back into the drain
OB_LADY:
  LDA FRAME_CNT
  AND #$07
  BNE .la_t
  DEC O_T,X
  BNE .la_t
  LDA #ST_HOME
  STA O_ST,X
  RTS
.la_t:
  LDA FRAME_CNT
  AND #$7F
  BNE .la_m
  JSR RND_DIR
.la_m:
  JSR MOVE_W
  LDA FRAME_CNT                ; every 4 frames: the dirt under the bristles
  AND #$03
  BNE LADY_HIT
  LDA O_V,X
  CMP #9
  BCS LADY_HIT
  JSR BRISTLES
  LDA TY
  LSR A
  LSR A
  LSR A
  CMP #3
  BCC LADY_HIT
  CMP #21
  BCS LADY_HIT
  STA T3
  PHX
  TAX
  JSR GRID_ROW
  LDA TX
  LSR A
  LSR A
  LSR A
  TAY
  LDA (PTR),Y
  CMP #T_CRUMB
  BEQ .la_sw
  CMP #T_GREASE
  BNE .la_n
.la_sw:
  LDA #T_FLOOR                 ; swept up
  STA (PTR),Y
  LDX T3
  JSR NT_XY
  LDA #T_FLOOR
  STA VDATA
  DEC DIRTN
  PLX
  INC O_V,X
  BRA LADY_HIT
.la_n:
  PLX
  ; fall into LADY_HIT

; X = the lady: her bristles give the broom, her body takes it back (and the face pushes her)
LADY_HIT:
  LDA BROOM
  BNE .lh_body
  JSR BRISTLES
  LDA BX
  SEC
  SBC TX
  BCS .lh_x
  EOR #$FF
  INC A
.lh_x:
  SEC
  SBC #4
  BCC .lh_xi
  CMP RAD
  BCS .lh_body
.lh_xi:
  LDA BY
  SEC
  SBC TY
  BCS .lh_y
  EOR #$FF
  INC A
.lh_y:
  SEC
  SBC #3
  BCC .lh_take
  CMP RAD
  BCS .lh_body
.lh_take:
  LDA #1                       ; the broom
  STA BROOM
  LDA #30
  STA LGRACE
  PHX
  LDA #W_BROOM
  LDX #0
  JSR SFX_WHISTLE
  PLX
  RTS
.lh_body:
  JSR COLLIDE
  BCC .lh_r
  LDA LGRACE
  BNE .lh_r
  LDA BROOM
  BEQ .lh_f
  STZ BROOM                    ; she takes it back
  PHX
  LDA #W_LOSEB
  LDX #0
  JSR SFX_WHISTLE
  PLX
.lh_f:
  LDA FACE
  BEQ .lh_r
  JMP REPEL
.lh_r:
  RTS

; X = the lady: TX / TY = middle of her bristles
BRISTLES:
  LDA O_FC,X
  BEQ .br_r
  LDA O_X,X
  SEC
  SBC #12
  BRA .br_x
.br_r:
  LDA O_X,X
  CLC
  ADC #12
.br_x:
  STA TX
  LDA O_Y,X
  CLC
  ADC #8
  STA TY
  RTS

; X = object touched by the bubble with the face: away from it, fast; the bubble bounces back
REPEL:
  JSR AIM_BUBBLE
  LDA #15
  STA O_SP,X
  LDA O_D,X
  EOR #$04
  JSR SET_VEL
  LDA #ST_PUSH
  STA O_ST,X
  LDA #40
  STA O_T,X
  LDA BVXH
  STA T1
  LDA BVXL
  JSR BOUNCE
  STA BVXL
  LDA T1
  STA BVXH
  LDA BVYH
  STA T1
  LDA BVYL
  JSR BOUNCE
  STA BVYL
  LDA T1
  STA BVYH
  PHX
  LDA #W_BOING
  LDX #0
  JSR SFX_WHISTLE
  PLX
  RTS


; ===============================================================
;  NEWCOMERS: ants from the sides, roaches from the drain
; ===============================================================
SPAWN:
  LDA BST
  BEQ .sp_go
  RTS
.sp_go:
  LDA ANTS                     ; ---- ants
  BEQ .sp_roach
  DEC ANTT
  BNE .sp_roach
  LDA #40
  STA ANTT
  LDX #7
.sp_af:
  LDA O_K,X
  BEQ .sp_ant
  INX
  CPX #NO
  BNE .sp_af
  BRA .sp_roach                ; no room: later
.sp_ant:
  DEC ANTS
  LDA DIFF
  ASL A
  ASL A
  EOR #$FF
  SEC
  ADC #150                     ; 150 - 4 x difficulty frames to the next one
  STA ANTT
  LDA #K_ANT
  STA O_K,X
  LDA #ST_WALK
  STA O_ST,X
  STZ O_XL,X
  STZ O_YL,X
  JSR KIND_SPEED
  JSR NEXT_RND                 ; a side of the sink
  AND #$03
  TAY
  JSR NEXT_RND
  AND #$7F
  STA T0
  JSR NEXT_RND
  AND #$3F
  CLC
  ADC T0
  ADC #32
  STA T0                       ; 32-222 along the side
  LDA ANT_X,Y
  BNE .sp_ax
  LDA T0
.sp_ax:
  STA O_X,X
  LDA ANT_Y,Y
  BNE .sp_ay
  LDA T0
  LSR A
  CLC
  ADC #40
.sp_ay:
  STA O_Y,X
  JSR AIM_DRAIN
.sp_roach:
  LDA FRAME_CNT                ; ---- roaches: the timer runs every 4 frames
  AND #$03
  BNE .sp_r
  LDA DRW
  BNE .sp_r
  DEC ROACHT
  BNE .sp_r
  LDA ROACHI
  STA ROACHT
  JSR FREE_ROACH
  BCC .sp_r
  LDA #100                     ; the drain flashes red, then the roach
  STA DRW
.sp_r:
  RTS

; carry set and X = a free roach slot
FREE_ROACH:
  LDX #5
.fr_l:
  LDA O_K,X
  BEQ .fr_y
  INX
  TXA
  SEC
  SBC #5
  CMP NROACH
  BCC .fr_l
  CLC
  RTS
.fr_y:
  SEC
  RTS


; ===============================================================
;  SLIDING CRUMBS: one row of the sink every frame
; ===============================================================
DRIFT:
  LDA BST
  BNE .dr_r
  LDX ROWSC
  INX
  CPX #21
  BCC .dr_s
  LDX #3
.dr_s:
  STX ROWSC
  JSR GRID_ROW
  LDY #2
.dr_l:
  LDA (PTR),Y
  CMP #T_CRUMB
  BNE .dr_n
  JSR NEXT_RND
  AND DRIFTM
  BNE .dr_n
  STY T3
  JSR SLIDE
  LDY T3
.dr_n:
  INY
  CPY #30
  BNE .dr_l
.dr_r:
  RTS

; the crumb at row ROWSC, column T3 (PTR = its row) one tile nearer the drain
SLIDE:
  STZ T4                       ; T4 = row step, T5 = column step
  STZ T5
  LDA T3
  CMP #15
  BCS .sl_c1
  INC T5
  BRA .sl_r
.sl_c1:
  CMP #17
  BCC .sl_r
  DEC T5
.sl_r:
  LDA ROWSC
  CMP #11
  BCS .sl_r1
  INC T4
  BRA .sl_one
.sl_r1:
  CMP #13
  BCC .sl_one
  DEC T4
.sl_one:
  LDA T4                       ; both: one of them at random
  BEQ .sl_go
  LDA T5
  BEQ .sl_go
  LDA RND
  AND #$10
  BEQ .sl_cz
  STZ T4
  BRA .sl_go
.sl_cz:
  STZ T5
.sl_go:
  LDA T4                       ; PTR2 = the row of the target
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A                        ; -32, 0, +32 (low byte)
  CLC
  ADC PTR
  STA PTR2
  LDA PTR+1
  ADC #0
  LDX T4
  BPL .sl_p
  DEC A                        ; going up: one page less
.sl_p:
  STA PTR2+1
  LDA T3
  CLC
  ADC T5
  STA T2                       ; target column
  TAY
  LDA (PTR2),Y
  CMP #T_FLOOR
  BEQ .sl_move
  CMP #T_DRAIN
  BCC .sl_x
  CMP #T_DRAIN+4
  BCS .sl_x
  DEC DIRTN                    ; down the drain
  BRA .sl_from
.sl_move:
  LDA #T_CRUMB
  STA (PTR2),Y
  LDA ROWSC
  CLC
  ADC T4
  TAX
  JSR NT_XY
  LDA #T_CRUMB
  STA VDATA
.sl_from:
  LDY T3
  LDA #T_FLOOR
  STA (PTR),Y
  LDX ROWSC
  JSR NT_XY
  LDA #T_FLOOR
  STA VDATA
.sl_x:
  RTS


; ===============================================================
;  THE DRAIN: red before a roach, green for the bubble with the
;  face; the bubble on it goes down
; ===============================================================
DRAIN:
  LDA DRW
  BEQ .dn_face
  DEC DRW
  BNE .dn_warn
  JSR FREE_ROACH               ; the roach comes out
  BCC .dn_grey
  LDA #K_ROACH
  STA O_K,X
  LDA #ST_OUT
  STA O_ST,X
  LDA #20
  STA O_T,X
  LDA #DRAIN_X
  STA O_X,X
  LDA #DRAIN_Y
  STA O_Y,X
  JSR KIND_SPEED
  LDA #4
  JSR SET_VEL
  LDA #W_ROACH
  LDX #1
  JSR SFX_WHISTLE
  BRA .dn_grey
.dn_warn:
  LDA DRW
  AND #$1F
  CMP #$1F
  BNE .dn_wc
  LDA #W_WARN
  LDX #1
  JSR SFX_WHISTLE
.dn_wc:
  LDA DRW
  AND #$08
  BEQ .dn_grey
  LDA #$08                     ; red
  BRA .dn_col
.dn_face:
  LDA FACE
  BEQ .dn_grey
  LDA FRAME_CNT
  AND #$10
  BEQ .dn_grey
  LDA #$03                     ; green
  BRA .dn_col
.dn_grey:
  LDA #$0E
.dn_col:
  CMP DRCOL
  BEQ .dn_in
  JSR DRAIN_COLOUR
.dn_in:
  LDA BST                      ; ---- the bubble on the drain
  BNE .dn_r
  LDA BX
  SEC
  SBC #DRAIN_X-3
  CMP #7
  BCS .dn_r
  LDA BY
  SEC
  SBC #DRAIN_Y-3
  CMP #7
  BCS .dn_r
  STZ DOWNOK                   ; green only with the face and no roach coming
  LDA FACE
  BEQ .dn_go
  LDA DRW
  BNE .dn_go
  INC DOWNOK
.dn_go:
  LDA #2
  STA BST
  STZ BROOM
  LDX SIZE
  INX
  STX BONSZ
  TXA
  ASL A
  ASL A
  ASL A
  STA BT
  LDA #W_GURGLE
  LDX #2
  JSR SFX_WHISTLE
.dn_r:
  RTS

; ===============================================================
;  THE SINK: colours, grid of the tiles, dirt, drawing
; ===============================================================
; colours of the sink tiles in the 3 thirds: low nibble 0 = the colour of the basin
SET_COLOURS:
  LDY #$60
.sc_t:
  LDA #$08
  STA VREG
  STY VREG
  LDX #0
.sc_l:
  LDA TILE_COL,X
  BIT #$0F
  BNE .sc_w
  ORA BASIN
.sc_w:
  STA VDATA
  INX
  CPX #NTILES*8
  BNE .sc_l
  TYA
  CLC
  ADC #$08
  TAY
  CPY #$78
  BNE .sc_t
  LDA #$0E
  STA DRCOL
  RTS

; A = colour of the drain plate (third 1, tiles T_DRAIN..T_DRAIN+3)
DRAIN_COLOUR:
  STA DRCOL
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA T0
  LDA #<($2000+$800+T_DRAIN*8)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >($2000+$800+T_DRAIN*8))
  STA VREG
  LDY #32
  LDA T0
.dc_l:
  STA VDATA
  DEY
  BNE .dc_l
  RTS

; the grid: rim, floor, drain, then the dirt of the level (always the same for a level)
BUILD_GRID:
  LDX #3
.bg_r:
  JSR GRID_ROW
  LDA #T_FLOOR
  LDY #29
.bg_f:
  STA (PTR),Y
  DEY
  CPY #1
  BNE .bg_f
  LDA #T_RIML
  STA (PTR),Y
  LDA #0
  DEY
  STA (PTR),Y
  LDY #31
  STA (PTR),Y
  DEY
  LDA #T_RIMR
  STA (PTR),Y
  INX
  CPX #21
  BNE .bg_r
  LDA #T_ITL                   ; rounded corners of the basin
  STA GRID+2
  LDA #T_ITR
  STA GRID+29
  LDA #T_IBL
  STA GRID+17*32+2
  LDA #T_IBR
  STA GRID+17*32+29
  LDA #T_DRAIN                 ; the drain: rows 11-12, columns 15-16
  STA GRID+8*32+15
  LDA #T_DRAIN+1
  STA GRID+8*32+16
  LDA #T_DRAIN+2
  STA GRID+9*32+15
  LDA #T_DRAIN+3
  STA GRID+9*32+16
  LDA RND                      ; the dirt: from a seed of the level
  PHA
  LDA LEVEL
  ASL A
  ASL A
  ASL A
  EOR LEVEL
  EOR #$5A
  ORA #$01
  STA RND
  STZ DIRTN
  LDX DIFF
  LDY LV_CRUMB,X
  LDA #T_CRUMB
  JSR PLACE
  LDX DIFF
  LDY LV_GREASE,X
  LDA #T_GREASE
  JSR PLACE
  LDX DIFF
  LDY LV_BLADE,X
  LDA #T_BLADE
  JSR PLACE
  PLA
  STA RND
  RTS

; A = tile, Y = how many: on free floor, not near the drain nor where the bubble starts
PLACE:
  STA T5
  STY T4
  CPY #0
  BEQ .pl_r
.pl_try:
  JSR NEXT_RND
  AND #$1F
  CMP #26
  BCS .pl_try
  ADC #3
  STA T3                       ; column 3-28
  JSR NEXT_RND
  AND #$0F
  CLC
  ADC #4
  STA T2                       ; row 4-19
  CMP #10
  BCC .pl_st
  CMP #14
  BCS .pl_st
  LDA T3                       ; around the drain
  CMP #13
  BCC .pl_ok
  CMP #19
  BCC .pl_try
  BRA .pl_ok
.pl_st:
  CMP #16                      ; where the bubble starts
  BCC .pl_ok
  LDA T3
  CMP #12
  BCC .pl_ok
  CMP #20
  BCC .pl_try
.pl_ok:
  LDA T5                       ; blades: not on the way to the drain
  CMP #T_BLADE
  BNE .pl_set
  LDA T2
  CMP #8
  BCC .pl_set
  CMP #16
  BCS .pl_set
  LDA T3
  CMP #11
  BCC .pl_set
  CMP #21
  BCC .pl_try
.pl_set:
  LDX T2
  JSR GRID_ROW
  LDY T3
  LDA (PTR),Y
  CMP #T_FLOOR
  BNE .pl_try
  LDA T5
  STA (PTR),Y
  CMP #T_BLADE
  BEQ .pl_n
  INC DIRTN
.pl_n:
  DEC T4
  BNE .pl_try
.pl_r:
  RTS

; the whole sink: top rim with the faucet, rows 3-20 from the grid, bottom rim
DRAW_SINK:
  LDX #2
  LDY #0
  JSR NT_XY
  LDA #0
  STA VDATA
  LDA #T_CTL
  STA VDATA
  LDY #2
.ds_t:
  LDA #T_RIMT
  CPY #15
  BNE .ds_t1
  LDA #T_TAP
.ds_t1:
  CPY #16
  BNE .ds_t2
  LDA #T_TAP+1
.ds_t2:
  STA VDATA
  INY
  CPY #30
  BNE .ds_t
  LDA #T_CTR
  STA VDATA
  LDX #3
.ds_r:
  JSR DRAW_GROW
  INX
  CPX #21
  BNE .ds_r
  LDX #21
  LDY #1
  JSR NT_XY
  LDA #T_CBL
  STA VDATA
  LDY #28
  LDA #T_RIMB
.ds_b:
  STA VDATA
  DEY
  BNE .ds_b
  LDA #T_CBR
  STA VDATA
  RTS

; X = screen row 3-20: the row again from the grid (keeps X)
DRAW_GROW:
  JSR GRID_ROW
  LDY #0
  JSR NT_XY
.dg_l:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #32
  BNE .dg_l
  RTS


; ===============================================================
;  HUD: rows 0-1 scores, row 23 level and spare bubbles
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

DRAW_BOTTOM:
  LDA #<TXT_BOT
  STA TP
  LDA #>TXT_BOT
  STA TP+1
  JSR PRINT
  ; fall into DRAW_BVALS

; row 23: the level and the spare bubbles
DRAW_BVALS:
  LDA LEVEL
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
  LDA #T_LIFE
.db_b:
  STA VDATA
  LDA #$20
  STA VDATA
  INX
  CPX #6
  BNE .db_l
  RTS

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
;  SPRITES: the bubble and its broom first, the water, then the
;  objects in an order that turns every frame (with more than 4
;  on a line they flicker instead of disappearing)
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA BST
  CMP #3
  BCC .bs_b0
  JMP .bs_obj
.bs_b0:
  CMP #1
  BNE .bs_bub
  LDA #30                      ; popping: 3 frames of spray
  SEC
  SBC BT
  LDX #0
  CMP #10
  BCC .bs_p1
  INX
  CMP #20
  BCC .bs_p1
  INX
.bs_p1:
  TXA
  ASL A
  ASL A
  ADC #PT_SPRAY
  STA ON
  LDA #$0F
  STA OC
  LDA SIZE
  CMP #4
  BCS .bs_p4
  JSR AT_BUBBLE
  JSR ADD_SPR
  BRA .bs_obj
.bs_p4:
  LDA #6
  JSR FOUR
  BRA .bs_obj
.bs_bub:
  LDA #$0F
  STA OC
  LDA SIZE
  CMP #4
  BCS .bs_big
  ASL A
  ASL A
  STA ON
  JSR AT_BUBBLE
  JSR ADD_SPR
  BRA .bs_broom
.bs_big:
  SEC                          ; 2 x 2 sprites
  SBC #4
  ASL A
  ASL A
  ASL A
  ASL A
  ADC #PT_BIG
  STA ON
  LDA #8
  JSR FOUR
.bs_broom:
  LDA BROOM
  BEQ .bs_obj
  LDA BST
  BNE .bs_obj
  LDA SIZE
  ASL A
  ASL A
  ASL A
  ORA BDIR
  TAY
  LDA BX
  CLC
  ADC BR_DX,Y
  STA OX
  LDA BY
  CLC
  ADC BR_DY,Y
  STA OY
  LDA BDIR
  ASL A
  ASL A
  ADC #PT_BROOM
  STA ON
  LDA #$0B
  STA OC
  JSR ADD_SPR
.bs_obj:
  LDA WATER                    ; ---- the faucet runs
  BEQ .bs_o
  LDA #DRAIN_X
  STA OX
  LDA #PT_WATER
  STA ON
  LDA #$07
  STA OC
  LDA #32
.bs_w:
  STA OY
  JSR ADD_SPR
  LDA OY
  CLC
  ADC #16
  CMP #96
  BCC .bs_w
.bs_o:
  INC RR                       ; ---- the objects
  LDA RR
  CMP #NO
  BCC .bs_rr
  STZ RR
.bs_rr:
  LDA RR
  STA T5
  LDA #NO
  STA CNT
.bs_ol:
  LDX T5
  JSR DRAW_OBJ
  INC T5
  LDA T5
  CMP #NO
  BCC .bs_on
  STZ T5
.bs_on:
  DEC CNT
  BNE .bs_ol
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

AT_BUBBLE:
  LDA BX
  STA OX
  LDA BY
  STA OY
  RTS

; ON = first of 4 patterns (or the same one 4 times if A = 6): around the bubble at +-A
FOUR:
  STA T6
  LDA BX
  SEC
  SBC T6
  STA OX
  LDA BY
  SEC
  SBC T6
  STA OY
  JSR ADD_SPR
  JSR .fo_n
  LDA OX
  CLC
  ADC T6
  ADC T6
  STA OX
  JSR ADD_SPR
  JSR .fo_n
  LDA BX
  SEC
  SBC T6
  STA OX
  LDA OY
  CLC
  ADC T6
  ADC T6
  STA OY
  JSR ADD_SPR
  JSR .fo_n
  LDA OX
  CLC
  ADC T6
  ADC T6
  STA OX
  JMP ADD_SPR
.fo_n:
  LDA T6                       ; the big bubble: next quarter
  CMP #8
  BNE .fo_r
  LDA ON
  CLC
  ADC #4
  STA ON
.fo_r:
  RTS

; X = object: its sprites
DRAW_OBJ:
  LDA O_K,X
  BNE .do_on
  RTS
.do_on:
  LDY O_ST,X
  CPY #ST_WAIT
  BNE .do_v
  RTS
.do_v:
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
  CPY #ST_DIE
  BNE .do_k
  LDA #24                      ; swatted roach: the splash
  SEC
  SBC O_T,X
  LSR A
  LSR A
  LSR A
  ASL A
  ASL A
  ADC #PT_SPRAY
  STA ON
  LDA #$0A
  STA OC
  JMP ADD_SPR
.do_k:
  LDA O_K,X
  CMP #K_LADY
  BEQ .do_lady
  CMP #K_SPONGE
  BEQ .do_sp
  CMP #K_BRUSH
  BEQ .do_br
  CMP #K_ROACH
  BEQ .do_ro
  LDA #PT_ANT                  ; ant
  LDY ANTC
  BRA .do_q
.do_ro:
  LDA #PT_ROACH
  LDY #$0A
.do_q:
  STA ON
  STY OC
  LDY O_D,X
  LDA QUAD,Y
  ASL A
  ASL A
  ASL A
  ADC ON
  STA ON
  LDA FRAME_CNT
  AND #$04
  ADC ON
  STA ON
  JMP ADD_SPR
.do_sp:
  LDA #PT_SPONGE
  LDY #$03
  BRA .do_f
.do_br:
  LDA #PT_BRUSH
  LDY #$05
.do_f:
  STA ON
  STY OC
  LDA FRAME_CNT
  LSR A
  LSR A
  AND #$04
  CLC
  ADC ON
  STA ON
  JMP ADD_SPR
.do_lady:
  LDA FRAME_CNT                ; walking: 2 frames
  LSR A
  AND #$04
  CLC
  ADC O_FC,X
  STA T6
  CLC
  ADC #PT_LADY
  STA ON
  LDA #$0D
  STA OC
  LDA O_FC,X
  STA T7
  JSR ADD_SPR
  LDA T7                       ; the broom in front of her
  BEQ .dl_r
  LDA OX
  SEC
  SBC #11
  BRA .dl_x
.dl_r:
  LDA OX
  CLC
  ADC #11
.dl_x:
  STA OX
  LDA OY
  CLC
  ADC #4
  STA OY
  LDA T6
  CLC
  ADC #PT_LBROOM
  STA ON
  LDA #$0B
  STA OC
  JMP ADD_SPR


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
PS_OFF:     .byte 0,2                          ; block of the player in PSAVE
BASIN_COL:  .byte $04,$0C,$01,$06              ; colour of the sink: dark blue, dark green, black, dark red
ANT_COL:    .byte $01,$01,$09,$01              ; ants: black, red on the black sink

; levels: index = difficulty 0-15 (level - 1, at most 15)
LV_CRUMB:   .byte 16,17,18,19,20,21,22,22,23,23,24,24,25,25,26,26
LV_GREASE:  .byte 4,4,5,5,6,6,6,7,7,7,8,8,8,8,8,8
LV_BLADE:   .byte 0,1,2,2,3,3,4,4,4,5,5,5,6,6,6,6
LV_ANTS:    .byte 5,5,6,6,6,7,7,7,8,8,8,8,9,9,9,9
LV_ENEMY:   .byte 1,2,2,3,3,3,4,4,4,4,4,4,4,4,4,4     ; sponges and brushes
LV_SPB:     .byte 0,0,0,1,1,1,1,2,2,2,2,3,3,3,4,4     ; speed bonus of the enemies
LV_ROACH1:  .byte 250,240,220,200,190,180,170,160,150,140,130,120,110,100,100,100   ; x 4 frames
LV_ROACHI:  .byte 220,210,200,190,180,170,160,150,140,130,120,110,100,90,90,90     ; x 4 frames
LV_NROACH:  .byte 1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2
LV_RLIFE:   .byte 75,75,80,80,85,85,90,90,95,95,100,100,105,105,110,110          ; x 8 frames
LV_DRIFT:   .byte 63,63,31,31,31,31,15,15,15,15,15,7,7,7,7,7
LV_AIM:     .byte 15,15,15,15,15,7,7,7,7,7,7,7,7,7,7,7

; the bubble: dirt needed for every size, reach for eating
GROW_T:     .byte 0,2,5,9,13,18,24,30
EAT_R:      .byte 2,3,5,6,8,10,12,13

; joystick (bit 0 up, 1 down, 2 left, 3 right) -> direction, $FF = none
JOY_DIR:    .byte $FF,0,4,$FF,6,7,5,6,2,1,3,2,$FF,0,4,$FF
; AIM: (horizontal 0 / vertical 4 / diagonal 8) + right * 2 + down
AIM_TAB:    .byte 6,6,2,2, 0,4,0,4, 7,5,1,3
FACE_D:     .byte $FF,0,0,0,$FF,8,8,8          ; the lady: direction -> facing (0 right, 8 left)
QUAD:       .byte 0,1,1,1,2,3,3,3              ; direction -> drawing of roaches and ants
WOBBLE:     .byte 0,1,$FF,0

; objects by kind (0, lady, sponge, brush, roach, ant)
SPEED_K:    .byte 0,4,3,5,10,0                 ; speed class
HW_X:       .byte 0,4,6,6,5,2                  ; half size - 1 for the touch
HW_Y:       .byte 0,6,4,4,5,2
DRAIN_PTS:  .byte 0,0,$05,$08                  ; into the drain: sponge 500, brush 800 (BCD hundreds)
SLOT_K:     .byte 0,K_SPONGE,K_BRUSH,K_SPONGE,K_BRUSH
CORN_X:     .byte 40,216,40,216
CORN_Y:     .byte 44,44,148,148
CORN_D:     .byte 3,5,1,7
ANT_X:      .byte 0,0,20,236                   ; 0 = along the side
ANT_Y:      .byte 28,164,0,0

; title: ant, lady and broom, roach, the big bubble (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 11*8-5,15*8-5,15*8-1,17*8-5,83,83,99,99,0
TITLE_SX:   .byte 60,58,69,60,12,28,12,28,0
TITLE_SN:   .byte PT_ANT+8,PT_LADY,PT_LBROOM,PT_ROACH+8,PT_BIG+48,PT_BIG+52,PT_BIG+56,PT_BIG+60,0
TITLE_SC:   .byte $09,$0D,$0B,$0A,$0F,$0F,$0F,$0F,$00

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,2,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,26,"2UP",0
  .byte $FF
TXT_TITLE:
  .byte 7,8,"- SCORE TABLE -",0
  .byte 9,11,"CRUMB         100",0
  .byte 11,11,"ANT           150",0
  .byte 13,11,"GREASE        200",0
  .byte 15,11,"LADY          500",0
  .byte 17,11,"ROACH        1000",0
  .byte 19,3,"FACE + GREEN DRAIN = BONUS",0
  .byte 21,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
TXT_BOT:
  .byte 23,1,"LEVEL",0
  .byte $FF
TXT_PLAYER:
  .byte 7,12,"PLAYER ",0
  .byte $FF
TXT_LEVEL:
  .byte 8,12,"LEVEL ",0
  .byte $FF
TXT_BONUS:
  .byte 8,11,"BONUS ",0
  .byte $FF
TXT_NOBON:
  .byte 8,12,"NO BONUS",0
  .byte $FF
TXT_OVER:
  .byte 8,11,"GAME OVER",0
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

; the start tune of a game, in C major (composed for this version), 256 frames
;   G4 32  A4 34  B4 36  C5 37  D5 39  E5 41  F5 42  G5 44  A5 46  C6 49
START_LEAD:
  .byte 32,8, 37,8, 41,8, 44,8, 41,8, 37,8, 32,8, 37,8
  .byte 34,8, 39,8, 42,8, 46,8, 44,8, 42,8, 41,8, 39,8
  .byte 41,8, 44,8, 49,8, 44,8, 46,8, 42,8, 39,8, 36,8
  .byte 37,16, 44,8, 41,8, 37,24, 0,8
  .byte $FF
START_HARM:
  .byte 29,64, 30,64, 29,32, 30,32, 29,64
  .byte $FF
START_BASS:
  .byte 13,16, 8,16, 13,16, 8,16, 6,16, 13,16, 6,16, 13,16
  .byte 13,16, 8,16, 6,16, 8,16, 13,16, 8,16, 13,32
  .byte $FF
START_DRUM:
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,8, 3,8, 2,8, 3,8, 1,8, 3,8, 2,8, 3,8
  .byte 1,16, 2,16, 4,32
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
; Bubbles: generated by dev/gen_bubbles.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_BUB = 0
PT_BIG = 16
PT_SPRAY = 80
PT_SPONGE = 92
PT_BRUSH = 100
PT_ROACH = 108
PT_ANT = 140
PT_LADY = 172
PT_LBROOM = 188
PT_BROOM = 204
PT_WATER = 236
SPR_PAGES = 8
SPRITES:
;  0 bubble 0, 4 bubble 1, 8 bubble 2, 12 bubble 3, 16 bubble 4 00, 20 bubble 4 10, 24 bubble 4 01, 28 bubble 4 11, 32 bubble 5 00, 36 bubble 5 10, 40 bubble 5 01, 44 bubble 5 11, 48 bubble 6 00, 52 bubble 6 10, 56 bubble 6 01, 60 bubble 6 11, 64 bubble 7 00, 68 bubble 7 10, 72 bubble 7 01, 76 bubble 7 11, 80 spray 0, 84 spray 1, 88 spray 2, 92 sponge 0, 96 sponge 1, 100 brush 0, 104 brush 1, 108 roach 0 0, 112 roach 0 1, 116 roach 1 0, 120 roach 1 1, 124 roach 2 0, 128 roach 2 1, 132 roach 3 0, 136 roach 3 1, 140 ant 0 0, 144 ant 0 1, 148 ant 1 0, 152 ant 1 1, 156 ant 2 0, 160 ant 2 1, 164 ant 3 0, 168 ant 3 1, 172 lady 0 0, 176 lady 0 1, 180 lady 1 0, 184 lady 1 1, 188 lady broom 0 0, 192 lady broom 0 1, 196 lady broom 1 0, 200 lady broom 1 1, 204 broom 0, 208 broom 1, 212 broom 2, 216 broom 3, 220 broom 4, 224 broom 5, 228 broom 6, 232 broom 7, 236 water
  .byte $00,$00,$00,$00,$00,$03,$06,$04,$04,$06,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$60,$20,$20,$60,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0C,$0A,$08,$08,$08,$0C,$07,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$E0,$30,$10,$10,$10,$10,$30,$E0,$00,$00,$00,$00
  .byte $00,$00,$03,$0C,$18,$16,$24,$20,$20,$20,$10,$18,$0C,$03,$00,$00
  .byte $00,$00,$C0,$30,$18,$28,$24,$04,$04,$04,$08,$18,$30,$C0,$00,$00
  .byte $00,$0F,$18,$34,$6C,$48,$48,$40,$40,$40,$40,$60,$30,$18,$0F,$00
  .byte $00,$F0,$18,$0C,$06,$12,$12,$02,$02,$02,$02,$06,$0C,$18,$F0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$03,$03,$03
  .byte $00,$00,$00,$00,$00,$00,$07,$1F,$70,$EC,$F0,$A0,$30,$30,$30,$00
  .byte $00,$00,$00,$00,$00,$00,$E0,$F8,$0E,$07,$03,$01,$0C,$0C,$0C,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$C0,$C0,$C0
  .byte $03,$03,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$70,$1F,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$07,$0E,$F8,$E0,$00,$00,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$06,$06,$04,$0C,$0C,$0C
  .byte $00,$00,$00,$00,$07,$3F,$70,$D8,$B0,$40,$80,$60,$60,$60,$00,$00
  .byte $00,$00,$00,$00,$E0,$FC,$0E,$03,$01,$00,$00,$06,$06,$06,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$60,$60,$20,$30,$30,$30
  .byte $0C,$0C,$0C,$04,$06,$06,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$30,$0F,$01,$80,$C0,$70,$3F,$07,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$1C,$F0,$80,$01,$03,$0E,$FC,$E0,$00,$00,$00,$00
  .byte $30,$30,$30,$20,$60,$60,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$06,$0D,$0B,$18,$10,$30,$30,$30,$30
  .byte $00,$00,$0F,$3F,$E0,$90,$60,$C0,$80,$00,$00,$C0,$C0,$C0,$00,$00
  .byte $00,$00,$F0,$FC,$07,$01,$00,$00,$00,$00,$00,$03,$03,$03,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$60,$30,$10,$18,$08,$0C,$0C,$0C,$0C
  .byte $30,$30,$30,$30,$10,$18,$08,$0C,$06,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$60,$70,$3F,$0F,$00,$00,$80,$E0,$3F,$0F,$00,$00
  .byte $00,$00,$00,$00,$02,$0E,$FC,$F8,$00,$00,$01,$07,$FC,$F0,$00,$00
  .byte $0C,$0C,$0C,$0C,$08,$18,$10,$30,$60,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$06,$0D,$1B,$36,$3C,$60,$60,$40,$C0,$C0,$C0,$C0
  .byte $0F,$7F,$E0,$B0,$E0,$80,$00,$00,$00,$00,$C0,$C0,$C0,$00,$00,$00
  .byte $F0,$FE,$07,$01,$00,$00,$00,$00,$00,$00,$03,$03,$03,$00,$00,$00
  .byte $00,$00,$80,$C0,$60,$30,$18,$0C,$0C,$06,$06,$02,$03,$03,$03,$03
  .byte $C0,$C0,$C0,$C0,$40,$60,$60,$30,$30,$18,$0C,$06,$03,$01,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$F0,$3F,$1F,$00,$00,$00,$80,$E0,$7F,$0F
  .byte $00,$00,$00,$00,$00,$03,$0F,$FE,$F8,$00,$00,$00,$01,$07,$FE,$F0
  .byte $03,$03,$03,$03,$02,$06,$06,$0C,$0C,$18,$30,$60,$C0,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$07,$06,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$E0,$60,$30,$E0,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$00,$06,$18,$0C,$00,$00,$07,$00,$00,$00,$00
  .byte $00,$00,$60,$00,$98,$00,$18,$00,$18,$00,$30,$60,$C0,$00,$00,$00
  .byte $00,$00,$08,$01,$00,$10,$00,$40,$00,$20,$00,$00,$10,$02,$00,$00
  .byte $40,$00,$00,$04,$00,$08,$00,$00,$04,$00,$00,$08,$20,$00,$80,$00
  .byte $00,$00,$00,$3F,$7F,$77,$7F,$6F,$7D,$5F,$7E,$7F,$3F,$00,$00,$00
  .byte $00,$00,$00,$FC,$FE,$DE,$7E,$DE,$FE,$D6,$FE,$FE,$FC,$00,$00,$00
  .byte $00,$00,$00,$1F,$3F,$77,$7F,$6F,$7D,$5F,$7F,$3F,$1F,$00,$00,$00
  .byte $00,$00,$00,$F8,$FC,$DE,$7E,$DE,$FE,$D6,$FE,$FC,$F8,$00,$00,$00
  .byte $00,$00,$00,$55,$BF,$7F,$DF,$60,$DF,$7F,$BF,$55,$00,$00,$00,$00
  .byte $00,$00,$00,$54,$FA,$FC,$F6,$0C,$F6,$FC,$FA,$54,$00,$00,$00,$00
  .byte $00,$00,$00,$AA,$7F,$FF,$5F,$E0,$5F,$FF,$7F,$AA,$00,$00,$00,$00
  .byte $00,$00,$00,$AA,$FC,$FC,$F6,$0C,$F6,$FC,$FC,$AA,$00,$00,$00,$00
  .byte $00,$00,$08,$04,$03,$17,$0F,$07,$17,$0F,$07,$17,$0F,$03,$00,$00
  .byte $00,$00,$20,$40,$80,$D0,$E0,$C0,$D0,$E0,$C0,$D0,$E0,$80,$00,$00
  .byte $00,$00,$04,$08,$03,$0F,$17,$07,$0F,$17,$07,$0F,$17,$03,$00,$00
  .byte $00,$00,$40,$20,$80,$E0,$D0,$C0,$E0,$D0,$C0,$E0,$D0,$80,$00,$00
  .byte $00,$00,$00,$09,$12,$1F,$3F,$3F,$3F,$1F,$12,$09,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$44,$E8,$F0,$F0,$F0,$E8,$44,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$12,$09,$1F,$3F,$3F,$3F,$1F,$09,$12,$00,$00,$00,$00
  .byte $00,$00,$00,$40,$28,$E4,$F0,$F0,$F0,$E4,$28,$40,$00,$00,$00,$00
  .byte $00,$00,$01,$07,$0B,$03,$07,$0B,$03,$07,$0B,$01,$02,$04,$00,$00
  .byte $00,$00,$C0,$F0,$E8,$E0,$F0,$E8,$E0,$F0,$E8,$C0,$20,$10,$00,$00
  .byte $00,$00,$01,$0B,$07,$03,$0B,$07,$03,$0B,$07,$01,$04,$02,$00,$00
  .byte $00,$00,$C0,$E8,$F0,$E0,$E8,$F0,$E0,$E8,$F0,$C0,$10,$20,$00,$00
  .byte $00,$00,$00,$00,$04,$22,$17,$0F,$0F,$0F,$17,$22,$04,$00,$00,$00
  .byte $00,$00,$00,$00,$90,$48,$F8,$FC,$FC,$FC,$F8,$48,$90,$00,$00,$00
  .byte $00,$00,$00,$00,$02,$14,$27,$0F,$0F,$0F,$27,$14,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$48,$90,$F8,$FC,$FC,$FC,$F8,$90,$48,$00,$00,$00
  .byte $00,$00,$00,$00,$02,$01,$03,$01,$03,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$00,$80,$00,$80,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$03,$01,$03,$03,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$80,$00,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$07,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$50,$E0,$50,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$03,$07,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$D0,$60,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$00,$01,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$C0,$80,$C0,$80,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$00,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$40,$C0,$C0,$80,$C0,$40,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0A,$07,$0A,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$E0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$06,$0B,$06,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$E0,$C0,$E0,$00,$00,$00,$00,$00,$00
  .byte $01,$03,$03,$03,$01,$07,$0F,$1B,$23,$07,$0F,$0F,$1F,$02,$02,$06
  .byte $C0,$E0,$A0,$E0,$C0,$E0,$F0,$D8,$CC,$E0,$F0,$F0,$F8,$40,$40,$60
  .byte $01,$03,$03,$03,$01,$07,$0F,$1B,$33,$07,$0F,$0F,$1F,$04,$08,$18
  .byte $C0,$E0,$A0,$E0,$C0,$E0,$F0,$D8,$C4,$E0,$F0,$F0,$F8,$20,$10,$18
  .byte $03,$07,$05,$07,$03,$07,$0F,$1B,$33,$07,$0F,$0F,$1F,$02,$02,$06
  .byte $80,$C0,$C0,$C0,$80,$E0,$F0,$D8,$C4,$E0,$F0,$F0,$F8,$40,$40,$60
  .byte $03,$07,$05,$07,$03,$07,$0F,$1B,$23,$07,$0F,$0F,$1F,$04,$08,$18
  .byte $80,$C0,$C0,$C0,$80,$E0,$F0,$D8,$CC,$E0,$F0,$F0,$F8,$20,$10,$18
  .byte $00,$00,$00,$30,$18,$0C,$06,$03,$01,$00,$03,$07,$05,$05,$0A,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$F0,$F8,$54,$54,$A8,$00
  .byte $00,$00,$00,$30,$18,$0C,$06,$03,$01,$00,$03,$07,$0A,$0A,$05,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$F0,$F8,$A8,$A8,$54,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$0F,$1F,$2A,$2A,$15,$00
  .byte $00,$00,$00,$0C,$18,$30,$60,$C0,$80,$00,$C0,$E0,$A0,$A0,$50,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$0F,$1F,$15,$15,$2A,$00
  .byte $00,$00,$00,$0C,$18,$30,$60,$C0,$80,$00,$C0,$E0,$50,$50,$A0,$00
  .byte $12,$12,$02,$02,$02,$07,$07,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $48,$48,$40,$40,$40,$E0,$E0,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$01,$00,$01,$03,$07,$0E,$1C,$38,$10,$00,$00
  .byte $40,$20,$50,$A8,$54,$AA,$D5,$E8,$A0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$03,$00,$60,$7F,$E0,$E0,$7F,$60,$00,$03,$00,$00,$00
  .byte $00,$00,$10,$38,$1C,$0E,$07,$03,$01,$00,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$A0,$E8,$D5,$AA,$54,$A8,$50,$20,$40
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$07,$07,$02,$02,$02,$12,$12
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$E0,$E0,$40,$40,$40,$48,$48
  .byte $00,$00,$00,$00,$00,$00,$00,$05,$17,$AB,$55,$2A,$15,$0A,$04,$02
  .byte $00,$00,$08,$1C,$38,$70,$E0,$C0,$80,$00,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$C0,$00,$06,$FE,$07,$07,$FE,$06,$00,$C0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$04,$0A,$15,$2A,$55,$AB,$17,$05,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$00,$80,$C0,$E0,$70,$38,$1C,$08,$00,$00
  .byte $03,$01,$01,$01,$03,$07,$07,$07,$03,$01,$01,$01,$03,$07,$07,$07
  .byte $C0,$80,$C0,$C0,$C0,$E0,$F0,$F0,$C0,$80,$C0,$C0,$C0,$E0,$F0,$F0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; tiles of the sink
;   1 floor
;   2 crumb
;   3 grease
;   4 blade
;   8 drain
;   9 rim top
;   10 rim bottom
;   11 rim left
;   12 rim right
;   13 rim corner TL
;   14 rim corner TR
;   15 rim corner BL
;   16 rim corner BR
;   17 basin corner TL
;   18 basin corner TR
;   19 basin corner BL
;   20 basin corner BR
;   21 faucet L
;   22 faucet R
;   23 spare bubble
T_FLOOR = 1
T_CRUMB = 2
T_GREASE = 3
T_BLADE = 4
T_DRAIN = 5
T_RIMT = 9
T_RIMB = 10
T_RIML = 11
T_RIMR = 12
T_CTL = 13
T_CTR = 14
T_CBL = 15
T_CBR = 16
T_ITL = 17
T_ITR = 18
T_IBL = 19
T_IBR = 20
T_TAP = 21
T_LIFE = 23
NTILES = 23
TILE_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$06,$26,$00,$62,$60,$00
  .byte $38,$7E,$FF,$FE,$7F,$7E,$36,$00,$00,$FF,$A5,$99,$A5,$FF,$00,$00
  .byte $3F,$7F,$C0,$DF,$C0,$DF,$C0,$DF,$FC,$FE,$03,$FB,$03,$FB,$03,$FB
  .byte $C0,$DF,$C0,$DF,$C0,$C0,$7F,$3F,$03,$FB,$03,$FB,$03,$03,$FE,$FC
  .byte $00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00
  .byte $1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8
  .byte $00,$00,$00,$07,$0F,$1F,$1F,$1F,$00,$00,$00,$E0,$F0,$F8,$F8,$F8
  .byte $1F,$1F,$1F,$1F,$0F,$07,$00,$00,$F8,$F8,$F8,$F8,$F0,$E0,$00,$00
  .byte $FE,$F0,$E0,$C0,$80,$80,$80,$00,$7F,$0F,$07,$03,$01,$01,$01,$00
  .byte $00,$80,$80,$80,$C0,$E0,$F0,$FE,$00,$01,$01,$01,$03,$07,$0F,$7F
  .byte $00,$01,$3F,$7F,$7F,$3F,$07,$07,$00,$80,$FC,$FE,$FE,$FC,$E0,$E0
  .byte $3C,$42,$A5,$81,$A5,$99,$42,$3C
; colours, low nibble 0 = the basin
TILE_COL:
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $E1,$E1,$E1,$EF,$EF,$EF,$EF,$EF,$E1,$E1,$E1,$EF,$EF,$EF,$EF,$EF
  .byte $71,$71,$71,$71,$71,$71,$71,$71

; big letters of the title: B U L E S, 4 tiles each (192-211)
BIG_P:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
BIG_C:
  .byte $70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0
  .byte $70,$70,$70,$50,$50,$50,$40,$40,$70,$70,$70,$50,$50,$50,$40,$40
  .byte $70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0
  .byte $70,$70,$70,$50,$50,$50,$40,$40,$70,$70,$70,$50,$50,$50,$40,$40
  .byte $70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0
  .byte $70,$70,$70,$50,$50,$50,$40,$40,$70,$70,$70,$50,$50,$50,$40,$40
  .byte $70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0
  .byte $70,$70,$70,$50,$50,$50,$40,$40,$70,$70,$70,$50,$50,$50,$40,$40
  .byte $70,$70,$70,$70,$70,$F0,$F0,$F0,$70,$70,$70,$70,$70,$F0,$F0,$F0
  .byte $70,$70,$70,$50,$50,$50,$40,$40,$70,$70,$70,$50,$50,$50,$40,$40

TXT_BIG:
  .byte 3,9,192,193,196,197,192,193,192,193,200,201,204,205,208,209,0
  .byte 4,9,194,195,198,199,194,195,194,195,202,203,206,207,210,211,0
  .byte $FF

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <184,>184, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <184,>184, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <184,>184, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$46, <160,>160, <BIG_P,>BIG_P
  .byte 1, $00,$66, <160,>160, <BIG_C,>BIG_C
  .byte 0

; velocity X (8.8 signed) for speed class * 8 + direction (0 up, clockwise); Y = X of (direction + 6) & 7
VEL_L:
  .byte $00,$2D,$40,$2D,$00,$D3,$C0,$D3,$00,$44,$60,$44,$00,$BC,$A0,$BC
  .byte $00,$5B,$80,$5B,$00,$A5,$80,$A5,$00,$71,$A0,$71,$00,$8F,$60,$8F
  .byte $00,$88,$C0,$88,$00,$78,$40,$78,$00,$9E,$E0,$9E,$00,$62,$20,$62
  .byte $00,$B5,$00,$B5,$00,$4B,$00,$4B,$00,$CC,$20,$CC,$00,$34,$E0,$34
  .byte $00,$E2,$40,$E2,$00,$1E,$C0,$1E,$00,$F9,$60,$F9,$00,$07,$A0,$07
  .byte $00,$10,$80,$10,$00,$F0,$80,$F0,$00,$26,$A0,$26,$00,$DA,$60,$DA
  .byte $00,$3D,$C0,$3D,$00,$C3,$40,$C3,$00,$53,$E0,$53,$00,$AD,$20,$AD
  .byte $00,$6A,$00,$6A,$00,$96,$00,$96,$00,$81,$20,$81,$00,$7F,$E0,$7F
VEL_H:
  .byte $00,$00,$00,$00,$00,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$FF,$FF,$FF,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $00,$00,$01,$00,$00,$FF,$FF,$FF,$00,$00,$01,$00,$00,$FF,$FE,$FF
  .byte $00,$00,$01,$00,$00,$FF,$FE,$FF,$00,$00,$01,$00,$00,$FF,$FE,$FF
  .byte $00,$01,$01,$01,$00,$FE,$FE,$FE,$00,$01,$01,$01,$00,$FE,$FE,$FE
  .byte $00,$01,$01,$01,$00,$FE,$FE,$FE,$00,$01,$01,$01,$00,$FE,$FE,$FE
  .byte $00,$01,$02,$01,$00,$FE,$FE,$FE,$00,$01,$02,$01,$00,$FE,$FD,$FE

; bubble: radius of every size
RADIUS:
  .byte $03,$04,$06,$07,$0A,$0C,$0E,$10
; broom: offset of the sprite and of the tip from the bubble, size * 8 + direction (signed)
BR_DX:
  .byte $00,$06,$09,$06,$00,$FA,$F7,$FA,$00,$07,$0A,$07,$00,$F9,$F6,$F9
  .byte $00,$08,$0C,$08,$00,$F8,$F4,$F8,$00,$09,$0D,$09,$00,$F7,$F3,$F7
  .byte $00,$0B,$10,$0B,$00,$F5,$F0,$F5,$00,$0D,$12,$0D,$00,$F3,$EE,$F3
  .byte $00,$0E,$14,$0E,$00,$F2,$EC,$F2,$00,$10,$16,$10,$00,$F0,$EA,$F0
BR_DY:
  .byte $F7,$FA,$00,$06,$09,$06,$00,$FA,$F6,$F9,$00,$07,$0A,$07,$00,$F9
  .byte $F4,$F8,$00,$08,$0C,$08,$00,$F8,$F3,$F7,$00,$09,$0D,$09,$00,$F7
  .byte $F0,$F5,$00,$0B,$10,$0B,$00,$F5,$EE,$F3,$00,$0D,$12,$0D,$00,$F3
  .byte $EC,$F2,$00,$0E,$14,$0E,$00,$F2,$EA,$F0,$00,$10,$16,$10,$00,$F0
TIP_DX:
  .byte $00,$09,$0D,$09,$00,$F7,$F3,$F7,$00,$0A,$0E,$0A,$00,$F6,$F2,$F6
  .byte $00,$0B,$10,$0B,$00,$F5,$F0,$F5,$00,$0C,$11,$0C,$00,$F4,$EF,$F4
  .byte $00,$0E,$14,$0E,$00,$F2,$EC,$F2,$00,$10,$16,$10,$00,$F0,$EA,$F0
  .byte $00,$11,$18,$11,$00,$EF,$E8,$EF,$00,$12,$1A,$12,$00,$EE,$E6,$EE
TIP_DY:
  .byte $F3,$F7,$00,$09,$0D,$09,$00,$F7,$F2,$F6,$00,$0A,$0E,$0A,$00,$F6
  .byte $F0,$F5,$00,$0B,$10,$0B,$00,$F5,$EF,$F4,$00,$0C,$11,$0C,$00,$F4
  .byte $EC,$F2,$00,$0E,$14,$0E,$00,$F2,$EA,$F0,$00,$10,$16,$10,$00,$F0
  .byte $E8,$EF,$00,$11,$18,$11,$00,$EF,$E6,$EE,$00,$12,$1A,$12,$00,$EE

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$A4,$7F,$67,$80,$62,$50,$68,$50,$41,$58,$44,$37,$4C,$3B,$30
  .byte $43,$34,$2A,$3C,$2E,$26,$36,$2A,$22,$68,$58,$4B,$42,$3B,$35,$31
  .byte $2D,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$35,$28,$28,$28
  .byte $28,$47,$47,$47,$47,$47,$47,$5F,$5F,$5F,$5F,$5F,$5F,$47,$47,$47
  .byte $47,$47,$47,$5F,$5F,$5F,$5F,$5F,$5F,$23,$1A,$23,$1A,$23,$1A,$23
  .byte $1A,$23,$1A,$23,$1A,$D0,$90,$6E,$59,$4B,$41,$39,$33,$2E,$2A,$2A
  .byte $2E,$33,$39,$41,$4B,$59,$6E,$90,$D0,$19,$1D,$22,$2A,$37,$4E,$C3
  .byte $8F,$A4,$08,$24,$B5,$8E,$AF,$1B,$11,$BE,$61,$13,$0A,$3D,$76,$63
  .byte $28,$2E,$2C,$24,$59,$82,$44,$0B,$10,$59,$AF,$3D,$16,$2A,$39,$3F
  .byte $6D,$59,$31,$0B,$1F,$84,$8E,$23,$0C,$2F,$52,$65,$46,$3D,$2A,$13
  .byte $37,$BB,$61,$12,$0A,$3F,$79,$61,$28,$28,$28,$28,$28,$28,$00,$00
  .byte $00,$28,$28,$28,$28,$28,$00,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$50
  .byte $5F,$5F,$5F,$5F,$5F,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$28
  .byte $28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00
WH_VOL:
  .byte $00,$0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07
  .byte $0C,$0A,$07,$0C,$0A,$07,$0C,$0A,$07,$0C,$0B,$0A,$09,$09,$08,$07
  .byte $06,$0D,$0C,$0A,$09,$0D,$0C,$0A,$09,$0D,$0C,$0A,$09,$0D,$0C,$0A
  .byte $09,$0C,$0C,$0B,$0B,$0A,$0A,$0C,$0C,$0B,$0B,$0A,$0A,$0C,$0C,$0B
  .byte $0B,$0A,$0A,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$09,$09,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$0C
  .byte $0B,$0B,$0A,$09,$09,$08,$07,$07,$06,$0E,$0D,$0C,$0A,$09,$08,$0D
  .byte $0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$0C,$0C,$0C,$0C,$0C,$04,$04
  .byte $04,$0B,$0B,$0B,$0B,$0B,$04,$04,$04,$0A,$0A,$0A,$0A,$0A,$04,$04
  .byte $04,$09,$09,$09,$09,$09,$04,$04,$04,$08,$08,$08,$08,$08,$04,$04
  .byte $04,$07,$07,$07,$07,$07,$04,$04,$04,$0D,$0C,$0B,$0A,$09,$00,$00
  .byte $00,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0A,$09,$08,$07,$05
  .byte $04,$0C,$0B,$0A,$08,$07,$0C,$0B,$0A,$08,$07,$0C,$0B,$0A,$08,$07
  .byte $0C,$0B,$0A,$08,$07,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$0C
  .byte $0A,$08
WH_START:
  .byte $00,$01,$04,$07,$0A,$0D,$10,$13,$16,$19,$21,$31,$49,$55,$5F,$69
  .byte $6F,$79,$A9,$C1,$DF
WH_LEN:
  .byte $00,$03,$03,$03,$03,$03,$03,$03,$03,$08,$10,$18,$0C,$0A,$0A,$06
  .byte $0A,$30,$18,$1E,$03
W_EAT = 1
W_EAT1 = 2
W_EAT2 = 3
W_EAT3 = 4
W_EAT4 = 5
W_EAT5 = 6
W_EAT6 = 7
W_EAT7 = 8
W_GROW = 9
W_FACE = 10
W_WARN = 11
W_ROACH = 12
W_BROOM = 13
W_LOSEB = 14
W_SWAT = 15
W_BOING = 16
W_GURGLE = 17
W_EXTRA = 18
W_LEVEL = 19
W_BONUS = 20

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01
  .byte $00,$00,$00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07
  .byte $07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01,$01,$00,$00,$00
  .byte $00,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B
  .byte $0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0B,$0C,$0A,$09,$08
  .byte $07,$06,$05,$04,$03,$02,$01
EX_NP:
  .byte $00,$02,$02,$02,$02,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05
  .byte $05,$06,$06,$06,$07,$08,$09,$06,$07,$08,$09,$06,$07,$08,$09,$06
  .byte $07,$08,$09,$06,$07,$08,$09,$06,$07,$08,$09,$06,$07,$08,$09,$06
  .byte $07,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02,$02,$02,$01,$01,$01,$01,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$02,$02
EX_VC:
  .byte $00,$0C,$0A,$08,$06,$04,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$45,$49,$4C,$50,$54,$59,$5F,$65,$6C,$74,$7D,$88,$95,$A4,$B8
  .byte $D0,$F0,$1C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$13,$31
EX_LEN:
  .byte $00,$12,$1E,$96
S_POP = 1
S_SPLASH = 2
S_WATER = 3
S_BIG = S_WATER
