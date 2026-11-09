;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   PAINT DUEL  -  an original paint-trail duel                ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - two painters push their rollers over a polished floor:   ;
;     a roller never stops, the joystick turns it left or      ;
;     right, and it leaves a stripe of wet paint behind        ;
;   - into wet paint (yours or the other's), the skirting      ;
;     board, a paint can or the table: the round is lost; both ;
;     at the same moment: nobody scores                        ;
;   - BUTTON = a sprint: twice as fast for 48 frames, 3 a      ;
;     round                                                    ;
;   - 4 rooms in turn, a little faster every 2 rounds; the     ;
;     first to 5 rounds wins the match                         ;
;   - BUTTON 1 = 1 player against the CPU (it drives the       ;
;     second roller through P_JOY+1, like a joystick),         ;
;     BUTTON 2 = 2 players                                     ;
;   - records: the most wins in a row against the CPU, signed  ;
;     with 3 initials, kept on the SD with the BIOS KEYB/SD    ;
;     (zone 43 of the save area, lib_records.asm)              ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     a swing at the title, jingles for the rounds; the        ;
;     rollers, one on each side; the splash                    ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- the computer player ----------------
AI_LOOK     = 14         ; cells it looks ahead
AI_ERR      = 14         ; of 256: at a cell it takes a random free way
AI_LATE     = 40         ; of 256: it does not think again at this cell
AI_SPRINT   = 24         ; of 256 a frame: a sprint when the other is near and the way is long

; ---------------- zero page: game ----------------
CPU_ON      = $30      ; 1 = player 2 is the computer
WINNER      = $31      ; who won the match (0 player 1, 1 player 2 / CPU)
SCORE       = $32      ; 2 bytes: rounds won
ROUND       = $34      ; round 1-9
GSTATE      = $35      ; 0 playing, 1 the round is over
GT          = $36      ; timer of GSTATE
CRASH       = $37      ; who crashed in this frame (bit 0 player 1, bit 1 player 2)
HUDD        = $38      ; 1 = the sprints on row 0 again
SPEED       = $39      ; 2 bytes: pixels a frame (8.8)
ARMED       = $3B      ; the end screen takes the button
PX          = $40      ; ---- per player (X = 0 / 1): left x of its cell, top y
PY          = $42
DIR         = $44      ;      0 right, 1 down, 2 left, 3 up
NDIR        = $46      ;      the turn booked
ACC         = $48      ;      fraction of the speed
SPRT        = $4A      ;      frames of sprint left
SPRN        = $4C      ;      sprints left in the round
TC          = $4E      ;      the cell it goes into (column, row)
TR          = $50
ARRF        = $52      ;      frame it got there (the same cell for both)
FRM         = $54      ;      steps (the roller turns)
BTNP        = $56      ;      button of the frame before
AI_D        = $58      ; the computer: the way chosen, the cell it was chosen for
AI_C        = $59
AI_R        = $5A
AI_BEST     = $5B
AI_SECOND   = $5C
AI_SC       = $5D      ; score of the best way
DRAWS       = $5E      ; rounds even (tests)
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
ARENA       = $72      ; the room of the round (0-3)
CB          = $73      ; the player being moved
LOSERS      = $74      ; who crashed in the last round (the splash)
STEPS       = $75      ; pixels still to move in this frame
AI_SX       = $76      ; the computer: the first cell of a way
AI_SY       = $77
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)

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
SONG       = $0730       ; tune to play

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
MAP        = $0800       ; 24 rows x 32: 0 floor, 1 wall, 2 paint of player 1, 3 paint of player 2

; ---------------- parameters ----------------
BTN_MASK    = %00110000
WIN_ROUNDS  = 5
SPRINT_F    = 48         ; frames of a sprint
SPRINTS     = 3          ; sprints a round

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 43         ; fixed zone of the game in the save area
REC_RAM     = $7D00      ; $2A0 bytes after the program
REC_ROW     = 8          ; table on rows 8-16 of the title
REC_WIPEN   = 10         ; rows 8-17 of the title give way to the table
REC_JOY2    = 0          ; the player who signs uses his own joystick
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
  JSR LOAD_GFX
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  STZ DDRA_JOY
  STZ DDRB_JOY
  STZ FRAME_CNT
  STZ LAST_FRAME
  STZ HOFF
  STZ CPU_ON
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_LOSE                 ; no run of wins yet
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, the rules, the table
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
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
.t_press:                      ; ...then button 1 = against the CPU, button 2 = 2 players
  JSR TITLE_FRAME
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BEQ .t_press
  LDX #$01
  AND #%00100000
  BEQ .t_np
  LDX #$00
.t_np:
  STX CPU_ON
  LDA FRAME_CNT                ; the moment you press seeds the random generator
  ORA #$01
  STA RND
  LDA #CMD_GAME
  STA SND_CMD
  JMP NEW_MATCH

; rows 8-17 of the title and the two rollers (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00
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
  CPX #TITLE_NS
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; one frame of the title: the rollers turn;
; every 8 s the title page and the table of the records take turns
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
  LDA SATB
  CMP #2
  BCC .tf_e
  LDX #0
  LDY #0
.tf_s:
  LDA TITLE_SN,X
  STA T0
  LDA FRAME_CNT
  AND #8
  BEQ .tf_n
  LDA T0
  CLC
  ADC #4
  STA T0
.tf_n:
  LDA T0
  STA SAT_BUFFER+2,Y
  INY
  INY
  INY
  INY
  INX
  CPX #TITLE_NS
  BNE .tf_s
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  A MATCH: rounds until one has 5
; ===============================================================
NEW_MATCH:
  STZ SCORE
  STZ SCORE+1
  STZ DRAWS
  LDA #1
  STA ROUND

ROUND_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the room is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA ROUND                    ; the room: in turn
  DEC A
  AND #3
  STA ARENA
  LDX ROUND                    ; the speed: a little more every 2 rounds
  LDA SPD_L,X
  STA SPEED
  LDA SPD_H,X
  STA SPEED+1
  JSR DRAW_ROOM
  JSR START_ROLLERS
  JSR DRAW_HUD
  JSR MSG_ROUND
  STZ GSTATE
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #90
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  JSR VDP_INT_ON
  LDA #CMD_GAME
  STA SND_CMD
  STZ GSTATE


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  LDA CPU_ON                   ; the computer drives player 2
  BEQ .gl_j
  JSR CPU_AI
.gl_j:
  LDA GSTATE
  BNE .gl_ns
  STZ CRASH
  JSR CONTROLS
  JSR ROLLERS
  LDA CRASH
  BEQ .gl_ns
  JSR ROUND_OVER
.gl_ns:
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  LDX #0                       ; the round is over: a match won?
.gl_w:
  LDA SCORE,X
  CMP #WIN_ROUNDS
  BCS .gl_m
  INX
  CPX #2
  BNE .gl_w
  LDA ROUND
  CMP #99
  BCS .gl_n
  INC ROUND
.gl_n:
  JMP ROUND_START
.gl_m:
  STX WINNER
  JMP GAME_OVER

; somebody crashed: the point, the splash, a pause
ROUND_OVER:
  LDA CRASH
  STA LOSERS
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  LDA #S_SPLAT
  LDX #2
  JSR SFX_BOOM
  LDA CRASH
  CMP #3
  BEQ .ro_d
  LSR A                        ; bit 0: player 1 crashed, player 2 scores
  LDX #1
  BCS .ro_p
  LDX #0
.ro_p:
  INC SCORE,X
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #1
  TSB HUDD
  RTS
.ro_d:
  INC DRAWS                    ; both: nobody scores
  LDA #W_DRAW
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  THE MATCH IS OVER: who won, the run of wins against the CPU
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  JSR DRAW_HUD
  LDX #11                      ; PLAYER 1 / PLAYER 2 / THE CPU  WINS
  LDY #10
  JSR NT_XY
  LDX WINNER
  BEQ .go_1
  LDX #2
  LDA CPU_ON
  BNE .go_1
  LDX #1
.go_1:
  LDA WIN_LO,X
  STA PTR
  LDA WIN_HI,X
  STA PTR+1
  LDY #0
.go_t:
  LDA (PTR),Y
  BEQ .go_s
  STA VDATA
  INY
  BRA .go_t
.go_s:
  LDX #13                      ; the score
  LDY #13
  JSR NT_XY
  LDA SCORE
  ORA #$30
  STA VDATA
  NOP
  LDA #'-'
  STA VDATA
  NOP
  NOP
  LDA SCORE+1
  ORA #$30
  STA VDATA
  JSR VDP_INT_ON
  LDA #3                       ; the tune of the winner
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  STZ ARMED
  LDA #120                     ; 2 seconds before the button counts
  JSR WAIT_FRAMES
.go_w:
  LDA #1
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR VDP_INT_ON
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BEQ .go_arm
  LDA ARMED
  BEQ .go_w
  BRA .go_rec
.go_arm:
  LDA #1
  STA ARMED
  BRA .go_w
.go_rec:
  LDA CPU_ON                   ; against the computer: the run of wins
  BEQ .go_t2
  LDA WINNER
  BNE .go_lost
  STZ REC_EX
  JSR REC_WIN                  ; one more win: signed
  BRA .go_t2
.go_lost:
  JSR REC_LOSE
.go_t2:
  JMP TITLE

; hooks of lib_records.asm
REC_XY = NT_XY
REC_CLS:                       ; the sign screen: empty
  JMP CLEAR_NT
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
REC_NAME:  .byte "PAINT DUEL      "
REC_HEAD:  .byte "MOST WINS IN A ROW",0
REC_XLBL:  .byte 0


; ===============================================================
;  HUD: row 0 (rounds won, sprints left, the round)
; ===============================================================
DRAW_HUD:
  LDX #0
  LDY #0
  JSR NT_XY
  LDA #'P'
  STA VDATA
  NOP
  LDA #'1'
  STA VDATA
  LDX #0
  LDY #26
  JSR NT_XY
  LDX #0                       ; P2 or CPU
  LDA CPU_ON
  BEQ .dh_p
  LDX #3
.dh_p:
  LDA TXT_P2,X
  STA VDATA
  INX
  LDA TXT_P2,X
  STA VDATA
  INX
  LDA TXT_P2,X
  STA VDATA
  LDX #0
  LDY #12
  JSR NT_XY
  LDX #0
.dh_r:
  LDA TXT_ROUNDH,X
  STA VDATA
  INX
  CPX #6
  BNE .dh_r
  LDA ROUND
  JSR PUT_NUM
  ; fall into DRAW_SCORES

; the rounds won and the sprints left
DRAW_SCORES:
  LDX #0
  LDY #3
  JSR NT_XY
  LDA SCORE
  ORA #$30
  STA VDATA
  LDX #0
  LDY #30
  JSR NT_XY
  LDA SCORE+1
  ORA #$30
  STA VDATA
  LDX #0
  LDY #5
  JSR NT_XY
  LDX #0
  LDA #T_PIP1
  JSR .ds_pips
  LDX #0
  LDY #22
  JSR NT_XY
  LDX #1
  LDA #T_PIP2
.ds_pips:                      ; X = player, A = tile: 3 places
  STA T0
  LDA SPRN,X
  STA T1
  LDY #0
.ds_l:
  LDA #$20
  CPY T1
  BCS .ds_w
  LDA T0
.ds_w:
  STA VDATA
  INY
  CPY #SPRINTS
  BNE .ds_l
  RTS

; A = 1-99: the number where the VDP points (no leading zero)
PUT_NUM:
  JSR BIN2BCD
  CMP #$10
  BCC .pn_1
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #$30
  STA VDATA
  PLA
  AND #$0F
.pn_1:
  ORA #$30
  STA VDATA
  RTS

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  JMP DRAW_SCORES
.uh_r:
  RTS


; ===============================================================
;  THE ROOM: floor, skirting board, the walls of the arena
; ===============================================================
; MAP: 0 floor, 2 / 3 paint of player 1 / 2, any other value = the tile of a wall
DRAW_ROOM:
  JSR CLEAR_NT
  LDX #1                       ; rows 1-23: the floor, the skirting board round it
.dr_r:
  STX T2
  JSR MAP_ROW
  LDY #0
  JSR NT_XY
  LDY #0
.dr_c:
  LDA T2
  CMP #1
  BEQ .dr_w
  CMP #23
  BEQ .dr_w
  CPY #0
  BEQ .dr_w
  CPY #31
  BEQ .dr_w
  LDA #0
  STA (PTR),Y
  TYA                          ; the parquet: two kinds of boards
  CLC
  ADC T2
  AND #1
  CLC
  ADC #T_FLOOR
  BRA .dr_s
.dr_w:
  LDA #T_WALL
  STA (PTR),Y
.dr_s:
  STA VDATA
  INY
  CPY #32
  BNE .dr_c
  LDX T2
  INX
  CPX #24
  BNE .dr_r
  LDX ARENA                    ; the walls of the arena: rectangles
  LDA AR_LO,X
  STA PTR2
  LDA AR_HI,X
  STA PTR2+1
.dr_k:
  LDY #0
  LDA (PTR2),Y
  CMP #$FF
  BEQ .dr_e
  STA T3                       ; first column
  INY
  LDA (PTR2),Y
  STA T2                       ; row
  INY
  LDA (PTR2),Y
  STA T4                       ; last column
  INY
  LDA (PTR2),Y
  STA T5                       ; last row
  INY
  LDA (PTR2),Y
  STA T1                       ; tile
.dr_kr:
  LDX T2
  JSR MAP_ROW
  LDX T2
  LDY T3
  JSR NT_XY
  LDY T3
.dr_kc:
  LDA T1
  STA (PTR),Y
  STA VDATA
  INY
  CPY T4
  BEQ .dr_kc
  BCC .dr_kc
  LDA T2
  CMP T5
  INC T2
  BCC .dr_kr
  LDA PTR2
  CLC
  ADC #5
  STA PTR2
  BCC .dr_k
  INC PTR2+1
  BRA .dr_k
.dr_e:
  RTS

; X = row: PTR = its row of MAP (keeps X)
MAP_ROW:
  LDA MAPR_LO,X
  STA PTR
  LDA MAPR_HI,X
  STA PTR+1
  RTS

; X = row: the row drawn again from MAP (after the messages)
DRAW_MAPROW:
  STX T2
  JSR MAP_ROW
  LDY #0
  JSR NT_XY
  LDY #0
.dm_c:
  LDA (PTR),Y
  BNE .dm_n
  TYA
  CLC
  ADC T2
  AND #1
  CLC
  ADC #T_FLOOR
  BRA .dm_w
.dm_n:
  CMP #2
  BNE .dm_3
  LDA #T_PAINT1
  BRA .dm_w
.dm_3:
  CMP #3
  BNE .dm_w
  LDA #T_PAINT2
.dm_w:
  STA VDATA
  INY
  CPY #32
  BNE .dm_c
  RTS

; ROUND n and the name of the room in the middle
MSG_ROUND:
  LDX #10
  LDY #12
  JSR NT_XY
  LDX #0
.mr_l:
  LDA TXT_ROUNDH,X
  STA VDATA
  INX
  CPX #6
  BNE .mr_l
  LDA ROUND
  JSR PUT_NUM
  LDX #14
  LDY #9
  JSR NT_XY
  LDX ARENA
  LDA ARN_LO,X
  STA PTR
  LDA ARN_HI,X
  STA PTR+1
  LDY #0
.mr_n:
  LDA (PTR),Y
  BEQ .mr_r
  STA VDATA
  INY
  BRA .mr_n
.mr_r:
  RTS

MSG_CLEAR:
  LDX #10
  JSR DRAW_MAPROW
  LDX #14
  JMP DRAW_MAPROW

; the two rollers at their places, facing each other; their cells are theirs
START_ROLLERS:
  LDX #1
.sr_l:
  LDA START_X,X
  STA PX,X
  LDA #96
  STA PY,X
  LDA START_D,X
  STA DIR,X
  STA NDIR,X
  STZ ACC,X
  STZ SPRT,X
  STZ FRM,X
  LDA #SPRINTS
  STA SPRN,X
  LDA #$FF
  STA BTNP,X
  STA ARRF,X
  LDA PY,X                     ; its cell: painted
  LSR A
  LSR A
  LSR A
  STA TR,X
  PHX
  TAX
  JSR MAP_ROW
  PLX
  LDA PX,X
  LSR A
  LSR A
  LSR A
  STA TC,X
  TAY
  TXA
  CLC
  ADC #2
  STA (PTR),Y
  DEX
  BPL .sr_l
  LDA #$FF
  STA AI_C
  STA AI_D
  RTS


; ===============================================================
;  THE ROLLERS
; ===============================================================
; the joysticks: a turn booked (never back), a sprint
CONTROLS:
  LDX #1
.ct_l:
  LDA P_JOY,X
  AND #$0F
  BEQ .ct_b
  TAY
  LDA JDIR,Y
  STA T0
  EOR DIR,X                    ; back: no
  CMP #2
  BEQ .ct_b
  LDA T0
  STA NDIR,X
.ct_b:
  LDA P_JOY,X                  ; the button: a sprint (a new press)
  AND #BTN_MASK
  TAY
  BEQ .ct_n
  LDA BTNP,X
  BNE .ct_n
  LDA SPRT,X
  BNE .ct_n
  LDA SPRN,X
  BEQ .ct_n
  DEC SPRN,X
  LDA #SPRINT_F
  STA SPRT,X
  LDA #1
  STA HUDD
  LDA #W_SPRINT
  PHX
  JSR SFX_WHISTLE
  PLX
.ct_n:
  TYA
  STA BTNP,X
  DEX
  BPL .ct_l
  RTS

; both rollers move: the pixels of this frame, a cell at a time
ROLLERS:
  LDX #0
.rl_p:
  STX CB
  LDA ACC,X                    ; pixels: the speed (8.8), twice in a sprint
  CLC
  ADC SPEED
  STA ACC,X
  LDA SPEED+1
  ADC #0
  STA STEPS
  LDA SPRT,X
  BEQ .rl_s
  DEC SPRT,X
  ASL STEPS
.rl_s:
  LDA STEPS
  BEQ .rl_n
.rl_px:
  LDX CB
  LDA PX,X                     ; at a cell: what comes next
  ORA PY,X
  AND #7
  BNE .rl_mv
  JSR ARRIVE
  LDX CB
  LDA CRASH
  AND BITS,X
  BNE .rl_n
.rl_mv:
  LDY DIR,X
  LDA PX,X
  CLC
  ADC DX_T,Y
  STA PX,X
  LDA PY,X
  CLC
  ADC DY_T,Y
  STA PY,X
  INC FRM,X
  DEC STEPS
  BNE .rl_px
.rl_n:
  LDX CB
  INX
  CPX #2
  BNE .rl_p
  RTS

; roller CB at a cell: the paint behind, the turn, the next cell (free, or a crash)
ARRIVE:
  LDX CB
  LDA PY,X                     ; this cell: paint
  LSR A
  LSR A
  LSR A
  STA T4
  LDA PX,X
  LSR A
  LSR A
  LSR A
  STA T5
  LDX T4
  LDY T5
  JSR NT_XY
  LDX CB
  LDA PAINT_T,X
  STA VDATA
  LDA NDIR,X                   ; the turn booked
  STA DIR,X
  TAY
  LDA T5                       ; the next cell
  CLC
  ADC DX_T,Y
  STA TC,X
  LDA T4
  CLC
  ADC DY_T,Y
  STA TR,X
  PHX
  TAX
  JSR MAP_ROW
  PLX
  LDY TC,X
  LDA (PTR),Y
  BNE .ar_hit
  TXA                          ; free: it is ours now
  CLC
  ADC #2
  STA (PTR),Y
  LDA FRAME_CNT
  STA ARRF,X
  LDA ROLL_W,X                 ; the roller on its side of the room
  PHX
  JSR SFX_WHISTLE
  PLX
  RTS
.ar_hit:
  TXA                          ; taken: the other one went there in this same frame?
  EOR #1
  TAY
  LDA ARRF,Y
  CMP FRAME_CNT
  BNE .ar_me
  LDA TC,Y
  CMP TC,X
  BNE .ar_me
  LDA TR,Y
  CMP TR,X
  BNE .ar_me
  LDA #3                       ; both
  TSB CRASH
  RTS
.ar_me:
  LDA BITS,X
  TSB CRASH
  RTS


; ===============================================================
;  THE COMPUTER: it drives player 2 through P_JOY+1
; ===============================================================
CPU_AI:
  STZ P_JOY+1
  LDA GSTATE
  BEQ .ai_go
  RTS
.ai_go:
  LDA TC+1                     ; a new cell ahead: think again
  CMP AI_C
  BNE .ai_new
  LDA TR+1
  CMP AI_R
  BEQ .ai_out
.ai_new:
  LDA TC+1
  STA AI_C
  LDA TR+1
  STA AI_R
  JSR NEXT_RND
  CMP #AI_LATE                 ; now and then it does not think: on as it was
  BCS .ai_think
  LDA AI_D
  BPL .ai_out
.ai_think:
  JSR AI_CHOOSE
.ai_out:
  LDA AI_D                     ; the joystick of the way chosen
  BMI .ai_r
  TAX
  LDA DIRBIT,X
  STA P_JOY+1
  LDA SPRN+1                   ; a sprint: the other is near and the way is long
  BEQ .ai_r
  LDA SPRT+1
  BNE .ai_r
  LDA BTNP+1
  BNE .ai_r
  JSR NEXT_RND
  CMP #AI_SPRINT
  BCS .ai_r
  LDA TC
  SEC
  SBC TC+1
  BCS .ai_x
  EOR #$FF
  INC A
.ai_x:
  STA T0
  LDA TR
  SEC
  SBC TR+1
  BCS .ai_y
  EOR #$FF
  INC A
.ai_y:
  CLC
  ADC T0
  CMP #10
  BCS .ai_r
  LDA AI_D
  JSR AI_RUN
  CMP #8
  BCC .ai_r
  LDA P_JOY+1
  ORA #%00010000
  STA P_JOY+1
.ai_r:
  RTS

; the best way from the cell ahead: straight, right or left (the longest free run, a bonus to go
; straight, away from the head of the other); now and then a random free one
; A = way: half of the free run from the first cell (AI_SX / AI_SY) to T5
AI_SIDE:
  TAY
  LDA AI_SX
  STA T0
  LDA AI_SY
  STA T1
  JSR AI_RUN0
  LSR A
  CLC
  ADC T5
  STA T5
  RTS

AI_CHOOSE:
  STZ AI_SC
  LDA #$FF
  STA AI_BEST
  STA AI_SECOND
  LDX #0
.ac_o:
  STX T7
  LDA DIR+1
  CLC
  ADC TURNS,X
  AND #3
  STA T6                       ; the way
  JSR AI_RUN
  BEQ .ac_n                    ; a wall at once: never
  STA T5
  LDY T6                       ; the room at the sides of its first cell: + half of it
  LDA AI_C
  CLC
  ADC DX_T,Y
  STA AI_SX
  LDA AI_R
  CLC
  ADC DY_T,Y
  STA AI_SY
  LDA T6
  INC A
  AND #3
  JSR AI_SIDE
  LDA T6
  CLC
  ADC #3
  AND #3
  JSR AI_SIDE
  LDA T7                       ; straight: +2
  BNE .ac_h
  INC T5
  INC T5
.ac_h:
  LDY T6                       ; the first cell next to the head of the other: -6
  LDA AI_C
  CLC
  ADC DX_T,Y
  SEC
  SBC TC
  CLC
  ADC #1
  CMP #3
  BCS .ac_s
  LDA AI_R
  CLC
  ADC DY_T,Y
  SEC
  SBC TR
  CLC
  ADC #1
  CMP #3
  BCS .ac_s
  LDA T5
  SEC
  SBC #6
  BCS .ac_hs
  LDA #1
.ac_hs:
  STA T5
.ac_s:
  LDA AI_BEST                  ; any free way, for the random choice
  STA AI_SECOND
  LDA T5
  CMP AI_SC
  BCC .ac_n
  BEQ .ac_n
  STA AI_SC
  LDA T6
  STA AI_BEST
.ac_n:
  LDX T7
  INX
  CPX #3
  BEQ .ac_d
  JMP .ac_o
.ac_d:
  LDA AI_BEST
  BMI .ac_none
  STA AI_D
  JSR NEXT_RND                 ; now and then the other way
  CMP #AI_ERR
  BCS .ac_r
  LDA AI_SECOND
  BMI .ac_r
  STA AI_D
.ac_r:
  RTS
.ac_none:
  LDA DIR+1                    ; boxed in: on
  STA AI_D
  RTS

; A = way: A = free cells from the cell ahead of the computer that way (AI_LOOK at most), Z = 1 if none
AI_RUN:
  TAY
  LDA AI_C
  STA T0
  LDA AI_R
  STA T1
  ; fall into AI_RUN0

; Y = way, T0 / T1 = a cell: A = free cells from it that way (AI_LOOK at most)
AI_RUN0:
  STZ T2
.au_l:
  LDA T0
  CLC
  ADC DX_T,Y
  STA T0
  CMP #32
  BCS .au_e
  LDA T1
  CLC
  ADC DY_T,Y
  STA T1
  CMP #24
  BCS .au_e
  TAX
  LDA MAPR_LO,X
  STA PTR2
  LDA MAPR_HI,X
  STA PTR2+1
  PHY
  LDY T0
  LDA (PTR2),Y
  PLY
  CMP #0
  BNE .au_e
  INC T2
  LDA T2
  CMP #AI_LOOK
  BCC .au_l
.au_e:
  LDA T2
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDX #0
.bs_l:
  LDA PX,X
  SEC
  SBC #4
  STA OX
  LDA PY,X
  SEC
  SBC #5
  STA OY
  LDA ROLL_C,X
  STA OC
  LDA GSTATE                   ; the round is over: a splash where it crashed
  BEQ .bs_r
  LDA LOSERS
  AND BITS,X
  BEQ .bs_r
  LDA #PT_SPLASH
  LDY GT
  CPY #60
  BCS .bs_sp
  LDA #PT_SPLASH+4
.bs_sp:
  STA ON
  BRA .bs_a
.bs_r:
  LDA DIR,X                    ; the roller: direction * 2 + the roller turning
  ASL A
  STA T0
  LDA FRM,X
  LSR A
  LSR A
  AND #1
  ORA T0
  ASL A
  ASL A
  CLC
  ADC #PT_ROLL
  STA ON
.bs_a:
  PHX
  JSR ADD_SPR
  PLX
  INX
  CPX #2
  BNE .bs_l
  LDY SPRI
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; OX, OY, ON, OC: one sprite more
ADD_SPR:
  LDY SPRI
  LDA OY
  STA SAT_BUFFER,Y
  LDA OX
  STA SAT_BUFFER+1,Y
  LDA ON
  STA SAT_BUFFER+2,Y
  LDA OC
  STA SAT_BUFFER+3,Y
  TYA
  CLC
  ADC #4
  STA SPRI
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from lighthouse keeper)
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

; the table GFX_LOAD (font, tiles, big letters, names) then the sprites
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
BITS:       .byte 1,2,4,8,16,32,64,128
S_BIG = S_SPLAT                                ; (lib_sound: a big noise is not cut by a small one)
; the four directions: right, down, left, up; the joystick bit of each; joystick -> direction
DX_T:       .byte 1,0,$FF,0
DY_T:       .byte 0,1,0,$FF
DIRBIT:     .byte 8,2,4,1
JDIR:       .byte 0,3,1,3,2,3,1,3,0,3,1,3,2,3,1,3
TURNS:      .byte 0,1,3                        ; straight, right, left
; the rows of MAP
MAPR_LO:    .byte <(MAP+0),<(MAP+32),<(MAP+64),<(MAP+96),<(MAP+128),<(MAP+160),<(MAP+192),<(MAP+224)
            .byte <(MAP+256),<(MAP+288),<(MAP+320),<(MAP+352),<(MAP+384),<(MAP+416),<(MAP+448),<(MAP+480)
            .byte <(MAP+512),<(MAP+544),<(MAP+576),<(MAP+608),<(MAP+640),<(MAP+672),<(MAP+704),<(MAP+736)
MAPR_HI:    .byte >(MAP+0),>(MAP+32),>(MAP+64),>(MAP+96),>(MAP+128),>(MAP+160),>(MAP+192),>(MAP+224)
            .byte >(MAP+256),>(MAP+288),>(MAP+320),>(MAP+352),>(MAP+384),>(MAP+416),>(MAP+448),>(MAP+480)
            .byte >(MAP+512),>(MAP+544),>(MAP+576),>(MAP+608),>(MAP+640),>(MAP+672),>(MAP+704),>(MAP+736)
; the rollers: where they start (column 6 and 25, row 12), facing; their paint, colour, sound
START_X:    .byte 48,200
START_D:    .byte 0,2
PAINT_T:    .byte T_PAINT1,T_PAINT2
ROLL_C:     .byte 7,9
ROLL_W:     .byte W_ROLL1,W_ROLL2
; the speed of a round (8.8 pixels a frame): a little more every 2 rounds
SPD_L:      .byte $20,$20,$20,$40,$40,$60,$60,$80,$80,$A0
            .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
SPD_H:      .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; title: the two rollers (sprite Y, X, pattern, colour)
TITLE_NS = 2
TITLE_SY:   .byte 83,99
TITLE_SX:   .byte 32,32
TITLE_SN:   .byte PT_ROLL,PT_ROLL+16
TITLE_SC:   .byte 7,9

TXT_ROUNDH: .byte "ROUND "
TXT_P2:     .byte "P2 CPU"
WIN_LO:     .byte <TXT_W1,<TXT_W2,<TXT_WC
WIN_HI:     .byte >TXT_W1,>TXT_W2,>TXT_WC
TXT_W1:     .byte "PLAYER 1 WINS",0
TXT_W2:     .byte "PLAYER 2 WINS",0
TXT_WC:     .byte " THE CPU WINS",0
; text records: row, column, characters, 0   (end of list: $FF)
TXT_BUTTONS:
  .byte 20,3,"BUTTON 1 = 1 PLAYER VS CPU",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 8,4,"THE ROLLERS NEVER STOP:",0
  .byte 9,4,"DO NOT ROLL INTO PAINT!",0
  .byte 11,8,"PLAYER 1",0
  .byte 13,8,"PLAYER 2 OR THE CPU",0
  .byte 15,4,"BUTTON = SPRINT, 3 A ROUND",0
  .byte 17,7,"FIRST TO 5 ROUNDS",0
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
;  GRAPHICS, ARENAS AND SOUND TABLES (generated)
; ===============================================================
; PAINT DUEL: generated by dev/gen_paint_duel.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; tiles
T_FLOOR = 96
T_PAINT1 = 98
T_PAINT2 = 99
T_PIP1 = 100
T_PIP2 = 101
T_WALL = 102
T_CAN = 103
T_TABLE = 104
PT_ROLL = 0
PT_SPLASH = 32
NARENA = 4
BIGT = 200
BIGB = 220
SPR_LEN = 320
SPR_PAGES = 2
SPRITES:
  .byte $00,$00,$00,$00,$00,$80,$40,$3E,$3E,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$F8,$A8,$F8,$A8,$F8,$A8,$70,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$40,$3E,$3E,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$A8,$F8,$A8,$F8,$A8,$F8,$70,$00,$00,$00,$00
  .byte $04,$02,$01,$01,$01,$01,$01,$00,$07,$0A,$0F,$0A,$07,$00,$00,$00,$20,$40,$80,$80,$80,$80,$80,$00,$E0,$B0,$F0,$B0,$E0,$00,$00,$00
  .byte $04,$02,$01,$01,$01,$01,$01,$00,$07,$0D,$0F,$0D,$07,$00,$00,$00,$20,$40,$80,$80,$80,$80,$80,$00,$E0,$50,$F0,$50,$E0,$00,$00,$00
  .byte $00,$00,$00,$00,$0E,$15,$1F,$15,$1F,$15,$1F,$0E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$7C,$7C,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$0E,$1F,$15,$1F,$15,$1F,$15,$0E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$7C,$7C,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$07,$0D,$0F,$0D,$07,$00,$01,$01,$01,$01,$01,$02,$04,$00,$00,$00,$E0,$50,$F0,$50,$E0,$00,$80,$80,$80,$80,$80,$40,$20
  .byte $00,$00,$00,$07,$0A,$0F,$0A,$07,$00,$01,$01,$01,$01,$01,$02,$04,$00,$00,$00,$E0,$B0,$F0,$B0,$E0,$00,$80,$80,$80,$80,$80,$40,$20
  .byte $00,$00,$04,$22,$17,$0F,$3F,$5F,$1F,$3F,$4F,$17,$24,$04,$00,$00,$00,$00,$20,$44,$E8,$F0,$F4,$F8,$FA,$F8,$F4,$E0,$90,$20,$00,$00
  .byte $80,$24,$40,$09,$80,$10,$04,$20,$84,$10,$42,$10,$84,$20,$04,$80,$81,$10,$04,$20,$02,$08,$20,$02,$84,$08,$40,$12,$80,$09,$80,$81

; game tiles 96-104: patterns and colours
TILEP:
  .byte $FF,$00,$00,$80,$00,$00,$00,$FF,$80,$80,$80,$FF,$01,$01,$01,$01,$4A,$A4,$52,$29,$94,$4A,$A4,$29,$4A,$A4,$52,$29,$94,$4A,$A4,$29
  .byte $00,$28,$14,$0A,$14,$28,$00,$00,$00,$28,$14,$0A,$14,$28,$00,$00,$FF,$81,$FF,$FF,$AA,$FF,$00,$FF,$7E,$81,$7E,$FF,$BD,$A5,$BD,$FF
  .byte $FF,$81,$BD,$A5,$A5,$BD,$81,$FF
TILEC:
  .byte $AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$74,$74,$74,$74,$74,$74,$74,$74,$98,$98,$98,$98,$98,$98,$98,$98
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$91,$91,$91,$91,$91,$91,$91,$91,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1,$F1,$E1,$DE,$DE,$DE,$E1
  .byte $6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A

; the arenas: rectangles of walls (first column, row, last column, row, tile), $FF = end
AR0:
  .byte $FF
AR1:
  .byte $09,$06,$0A,$07,$67,$15,$06,$16,$07,$67,$09,$11,$0A,$12,$67,$15,$11,$16,$12,$67,$0F,$04,$10,$05,$67,$0F,$13,$10,$14,$67,$FF
AR2:
  .byte $0D,$0A,$12,$0E,$68,$04,$04,$05,$05,$67,$1A,$13,$1B,$14,$67,$FF
AR3:
  .byte $0F,$02,$10,$09,$66,$0F,$0F,$10,$16,$66,$07,$02,$08,$05,$67,$17,$13,$18,$16,$67,$FF
AR_LO:
  .byte <AR0,<AR1,<AR2,<AR3
AR_HI:
  .byte >AR0,>AR1,>AR2,>AR3
ARN_LO:
  .byte <ARN0,<ARN1,<ARN2,<ARN3
ARN_HI:
  .byte >ARN0,>ARN1,>ARN2,>ARN3
ARN0:     .byte "THE HALL",0
ARN1:     .byte "THE STORE ROOM",0
ARN2:     .byte "THE KITCHEN",0
ARN3:     .byte "THE CORRIDOR",0

; big letters of the title
BIG_TOP:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80,$00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80,$00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
BIG_BOT:
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00,$18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00,$19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00,$18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
TXT_BIG:
  .byte 3,6,200,201,202,203,204,205,206,207,208,209,32,32,210,211,212,213,214,215,216,217,0
  .byte 4,6,220,221,222,223,224,225,226,227,228,229,32,32,230,231,232,233,234,235,236,237,0
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
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3,<SG2_0,<SG2_1,<SG2_2,<SG2_3,<SG3_0,<SG3_1,<SG3_2,<SG3_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3,>SG2_0,>SG2_1,>SG2_2,>SG2_3,>SG3_0,>SG3_1,>SG3_2,>SG3_3
SG0_0:
  .byte $23,$06,$27,$06,$2A,$06,$2C,$06,$2A,$0C,$27,$06,$23,$06,$25,$06,$28,$06,$2C,$06,$2E,$06,$2C,$0C,$28,$0C,$27,$06,$2A,$06,$2F,$06
  .byte $2E,$06,$2C,$06,$2A,$06,$28,$06,$25,$06,$23,$18,$2A,$06,$2A,$06,$2C,$06,$2A,$06,$27,$0C,$23,$0C,$28,$06,$28,$06,$2A,$06,$28,$06
  .byte $25,$0C,$22,$0C,$23,$06,$27,$06,$2A,$06,$27,$06,$25,$06,$28,$06,$22,$06,$25,$06,$23,$18,$FF
SG0_1:
  .byte $1B,$18,$1B,$18,$1C,$18,$1C,$18,$1E,$18,$1C,$18,$1B,$18,$1B,$18,$17,$18,$19,$18,$16,$18,$1B,$18,$1C,$18,$1B,$18,$FF
SG0_2:
  .byte $0B,$0C,$06,$0C,$0B,$0C,$06,$0C,$04,$0C,$0B,$0C,$04,$0C,$06,$0C,$0B,$0C,$06,$0C,$04,$0C,$06,$0C,$0B,$18,$0B,$0C,$06,$0C,$0B,$0C
  .byte $0F,$0C,$04,$0C,$0B,$0C,$06,$0C,$0D,$0C,$0B,$0C,$06,$0C,$06,$0C,$0D,$0C,$0B,$18,$FF
SG0_3:
  .byte $01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C
  .byte $03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$02,$0C
  .byte $04,$18,$FF
SG1_0:
  .byte $1E,$06,$23,$06,$27,$06,$2A,$12,$FF
SG1_1:
  .byte $1B,$12,$1E,$12,$FF
SG1_2:
  .byte $0B,$12,$0B,$12,$FF
SG1_3:
  .byte $03,$06,$03,$06,$03,$06,$01,$12,$FF
SG2_0:
  .byte $27,$04,$2A,$04,$2F,$0C,$FF
SG2_1:
  .byte $23,$14,$FF
SG2_2:
  .byte $0B,$14,$FF
SG2_3:
  .byte $02,$04,$02,$04,$01,$0C,$FF
SG3_0:
  .byte $23,$06,$27,$06,$2A,$06,$2F,$12,$2E,$06,$2C,$06,$2A,$06,$28,$06,$27,$06,$25,$06,$23,$18,$00,$06,$2A,$06,$2F,$1E,$FF
SG3_1:
  .byte $1B,$18,$1E,$18,$1C,$18,$1B,$18,$1E,$1E,$FF
SG3_2:
  .byte $0B,$18,$0B,$18,$04,$18,$06,$18,$0B,$1E,$FF
SG3_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$04,$1E,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$1C,$1C,$7B,$7B,$45,$39,$30,$7D,$66,$57,$4B,$42,$3B,$36,$31,$2D,$2A,$2F,$2F,$2F,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E,$8E,$8E
  .byte $8E,$8E,$8E,$8E,$97,$97,$97,$97,$97,$97,$97,$97,$97,$97,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28
  .byte $28,$28,$28,$28
WH_TH:
  .byte $00,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00
WH_VOL:
  .byte $00,$05,$04,$05,$04,$07,$06,$04,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0A,$09,$07,$06,$04,$0B,$0A
  .byte $0A,$09,$09,$08,$0B,$0A,$09,$08,$07,$07,$06,$05,$04,$03,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09
  .byte $07,$06,$04,$03
WH_START:
  .byte $00,$01,$03,$05,$08,$12,$1E,$2E,$31
WH_LEN:
  .byte $00,$02,$02,$03,$0A,$0C,$10,$03,$13
W_ROLL1 = 1
W_ROLL2 = 2
W_TURN = 3
W_SPRINT = 4
W_POINT = 5
W_DRAW = 6
W_KEY = 7
W_SIGN = 8

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00
EX_NP:
  .byte $00,$03,$03,$04,$04,$05,$05,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
EX_TH:
  .byte $00,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
EX_START:
  .byte $00,$01
EX_LEN:
  .byte $00,$10
S_SPLAT = 1

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$66, <144,>144, $71,0
  .byte 2, $E0,$66, <144,>144, $91,0
  .byte 1, $00,$43, <72,>72, <TILEP,>TILEP
  .byte 1, $00,$63, <72,>72, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$4E, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$6E, <144,>144, $71,0
  .byte 2, $E0,$6E, <144,>144, $91,0
  .byte 1, $00,$4B, <72,>72, <TILEP,>TILEP
  .byte 1, $00,$6B, <72,>72, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$56, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$76, <144,>144, $71,0
  .byte 2, $E0,$76, <144,>144, $91,0
  .byte 1, $00,$53, <72,>72, <TILEP,>TILEP
  .byte 1, $00,$73, <72,>72, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
