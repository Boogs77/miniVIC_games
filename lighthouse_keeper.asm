;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   LIGHTHOUSE KEEPER  -  an original climbing game            ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Gus the keeper climbs to relight his lighthouse; on top  ;
;     Squawk the seagull throws coconuts that roll down the    ;
;     sloping planks and now and then down a ladder            ;
;   - the pier (planks and ladders, a blue coconut in the pot  ;
;     lets out a crab), the cliff (lifts made of waves), the   ;
;     stairs (starfish hopping down), the lantern (8 open      ;
;     windows to shut)                                         ;
;   - BUTTON = jump (100 over a coconut); a broom sweeps for 8 ;
;     seconds (coconut and starfish 300, crab 500), but Gus    ;
;     cannot climb or jump with it                             ;
;   - falling too far, a coconut, a crab, the bonus at 0: a    ;
;     life lost; the bonus left at the end of a screen         ;
;   - level 1 pier and lantern, level 2 with the cliff, then   ;
;     all four, faster; 3 lives, one more at 10000; 1 or 2    ;
;     players taking turns                                     ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 42 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     a sea shanty at the title, tunes at every screen; steps, ;
;     jumps, the seagull, the broom                            ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: lives left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
LEVEL       = $40      ; ---- block of the player, saved: level 0-98
SCRI        = $41      ;      screen of the level (0-3)
XTRA        = $42      ;      1 = the extra life was given
WINS        = $43      ;      the windows of the lantern shut (bits 0-7)
PBLOCK      = 4
GSTATE      = $50      ; 0 playing, 1 life lost, 3 the screen is done
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives, bonus and level
FIRSTT      = $53      ; 1 = first turn of the game
GX          = $54      ; Gus: left x, feet y (the top of the plank under him), facing (0 right, 1 left)
GY          = $55
GDIR        = $56
GST         = $57      ; 0 walking, 1 climbing, 2 jumping, 3 falling, 4 on a lift
GT2         = $58      ; frames of the jump
GJDX        = $59      ; the jump: x step (signed)
GFALL       = $5A      ; pixels fallen
GLAD        = $5B      ; the ladder he climbs / the lift he rides
GFRM        = $5C      ; steps (the 2 frames)
BROOMT      = $5D      ; frames of broom left
GV          = $5E      ; speed of the fall
SPRROT      = $5F      ; sprite order (more than 4 on a line take turns)
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
BONUS       = $72      ; bonus left (hundreds, BCD)
BONT        = $73      ; frames to the next 100 less
LOSTN       = $74      ; lives lost (tests)
DEATHS      = $75      ; what took the last life (tests): 1 fall, 2 coconut, 3 crab, 4 starfish, 5 bonus, 6 lift
THROWT      = $76      ; frames to the next throw
GULLP       = $77      ; the seagull throwing (frames)
SCRN        = $78      ; the screen (0 pier, 1 cliff, 2 stairs, 3 lantern)
TICKS       = $79
CB          = $7A      ; the object being moved
SCRD        = $7B      ; screens done (tests)
BRGOT       = $7C      ; brooms taken (bits 0-1)
ITGOT       = $7D      ; things of Gus taken (bits 0-1)
LEVI        = $7E      ; level for the tables (0-9)
PIDX        = $7F      ; first plank / ladder of the screen in the tables (screen * 12, * 10)
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
JPREV       = $88      ; joystick of the frame before, new presses
JNEW        = $89
SLOPE       = $8A      ; slope of the plank found (0, 1, $FF)
LIDX        = $8B      ; first ladder of the screen (screen * 10)
PTX         = $8C      ; points shown: x, y, pattern, frames
PTY         = $8D
PTN         = $8E
PTT         = $8F
JUMPS       = $90      ; coconuts jumped (tests)
SWEPT       = $91      ; things swept by the broom (tests)
NCRAB       = $92      ; crabs on the screen
SPAWNT      = $93      ; frames to the next crab (the lantern)

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

; ---------------- the objects (8): coconuts, starfish, crabs ----------------
NO         = 8
O_T        = $0200       ; 0 none, 1 coconut, 2 blue coconut, 3 starfish, 4 crab
O_X        = $0208       ; left x, feet y
O_Y        = $0210
O_D        = $0218       ; 0 right, 1 left
O_S        = $0220       ; 0 rolling / walking, 1 falling, 2 down a ladder, 3 up a ladder
O_ACC      = $0228       ; fraction of the speed
O_V        = $0230       ; falling speed
O_L        = $0238       ; the ladder
O_J        = $0240       ; 1 = jumped over (points given)
O_H        = $0248       ; hop of the starfish
; the lifts of the cliff: 3 going up, 3 going down
NLIFT      = 6
LF_Y       = $0260       ; top y
LIFTT      = $0266       ; frames (they move every other frame)

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 8: block of every player

; ---------------- parameters ----------------
BTN_MASK    = %00110000
BONUS0      = $50        ; 5000 at every screen (BCD hundreds)
BONUSF      = 120        ; frames for 100 less

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 42         ; fixed zone of the game in the save area
REC_RAM     = $7D00      ; $2A0 bytes after the program
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
  JSR LOAD_GFX
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
  DEX
  BPL .rs_p
  JSR REC_INIT                 ; the table from the SD (or an empty one)
  JSR REC_HISC
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, who is who, the points
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #$F1                     ; the title in white
  JSR STRUCT_COL
  JSR CLEAR_NT
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

; rows 9-18 of the title and the sprites beside them (VDP interrupt off)
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

; one frame of the title: the sprites move;
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
  LDX #0                       ; the second frame of every sprite in turn
  LDY #0
.tf_s:
  LDA TITLE_SN,X
  STA T0
  LDA FRAME_CNT
  AND #16
  BEQ .tf_n
  LDA T0
  CLC
  ADC TITLE_SA,X
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
;  NEW GAME: level 1, 3 lives for every player
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
  STZ LOSTN
  STZ SCRD
  STZ JUMPS
  STZ SWEPT
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ LEVEL
  STZ SCRI
  STZ XTRA
  STZ WINS
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his screen from the start
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

SCREEN_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the screen is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_SCREEN               ; which screen, its tables, its colour
  JSR DRAW_SCREEN
  JSR DRAW_HUD
  JSR START_POS                ; Gus at the bottom, no objects
  STZ GSTATE
  JSR MSG_SCREEN
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA #1                       ; the tune of a screen (longer the first time)
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ss_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ss_t
  LDA FIRSTT
  BEQ .ss_w
  STZ FIRSTT
  LDA #40
  JSR WAIT_FRAMES
.ss_w:
  LDA #10
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
  LDA P_JOY                    ; both joysticks drive the player playing
  ORA P_JOY+1
  STA JOYC
  EOR JPREV
  AND JOYC
  STA JNEW
  LDA JOYC
  STA JPREV
  INC TICKS
  LDA GSTATE
  BNE .gl_ns
  JSR LIFTS
  JSR GUS
  LDA GSTATE
  BNE .gl_ns
  JSR GULL
  JSR OBJECTS
  JSR TOUCH
  JSR PICKUPS
  JSR BONUS_TICK
  JSR GOAL
.gl_ns:
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  LDA GSTATE
  CMP #3
  BEQ .gl_done
  JMP LOSE_LIFE
.gl_done:
  JMP SCREEN_DONE


; ===============================================================
;  THE SCREEN IS DONE: the bonus, the tune, the next screen
; ===============================================================
SCREEN_DONE:
  INC SCRD
  LDA BONUS                    ; the bonus left
  STA PTS_M
  STZ PTS_L
  STZ PTS_H
  JSR ADD_SCORE
  JSR VDP_INT_OFF
  JSR UPDATE_HUD
  JSR HIDE_SPRITES
  JSR VDP_INT_ON
  LDA #2                       ; the lantern: the light is on again
  LDX SCRN
  CPX #3
  BNE .sd_s
  LDA #3
.sd_s:
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
.sd_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sd_t
  LDA #20
  JSR WAIT_FRAMES
  INC SCRI                     ; the next screen of the level, or the next level
  JSR SEQ_SCREEN
  BPL .sd_n
  STZ SCRI
  STZ WINS
  LDA LEVEL
  CMP #98
  BCS .sd_n
  INC LEVEL
.sd_n:
  JSR SAVE_PLAYER
  JMP SCREEN_START

; A = the screen of SCRI in the level ($FF = the level is over)
SEQ_SCREEN:
  LDX LEVEL
  CPX #2
  BCC .sq_l
  LDX #2
.sq_l:
  LDA SEQ_LO,X
  STA PTR
  LDA SEQ_HI,X
  STA PTR+1
  LDY SCRI
  LDA (PTR),Y
  RTS

LOSE_LIFE:
  INC LOSTN
  LDX CURP
  DEC LIVES,X
  JSR SAVE_PLAYER
  LDA #20
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
  JMP SCREEN_START             ; the same screen again

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
  TXA                          ; extra byte: the level reached
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE,Y
  INC A
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
REC_NAME:  .byte "LIGHTHOUSE KEEP "
REC_HEAD:  .byte "BEST KEEPERS",0
REC_XLBL:  .byte "LEVEL ",0


; ===============================================================
;  HUD: row 0 (scores), row 1 (lives, bonus, level)
; ===============================================================
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
  LDX #$00
  JSR DRAW_SCORE
  LDA NPL
  CMP #2
  BNE .dt_e
  LDA #<TXT_TOP2
  STA TP
  LDA #>TXT_TOP2
  STA TP+1
  JSR PRINT
  LDX #$01
  JMP DRAW_SCORE
.dt_e:
  RTS

; X = player: his score on row 0 (keeps X)
DRAW_SCORE:
  PHX
  LDY SC_COLS,X
  LDX #0
  JSR NT_XY
  PLX
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

; row 1: the spare lives (cols 0-5), BONUS nnnn (cols 9-18), L nn (cols 24-27), the player (col 31)
DRAW_STATUS:
  LDX #1
  LDY #0
  JSR NT_XY
  LDX CURP                     ; the spare lives (at most 6)
  LDA LIVES,X
  BEQ .ds_z
  DEC A
.ds_z:
  STA T0
  LDY #0
.ds_i:
  LDA #$20
  CPY T0
  BCS .ds_w
  LDA #T_LIFE
.ds_w:
  STA VDATA
  INY
  CPY #6
  BNE .ds_i
  JSR DRAW_BONUS
  LDX #1
  LDY #24
  JSR NT_XY
  LDA #'L'
  STA VDATA
  LDA #$20
  STA VDATA
  LDA LEVEL
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDA NPL                      ; the player at the right end with 2 players
  CMP #2
  BNE .ds_r
  LDX #1
  LDY #31
  JSR NT_XY
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ds_r:
  RTS

DRAW_BONUS:
  LDX #1
  LDY #9
  JSR NT_XY
  LDX #0
.db_l:
  LDA TXT_BONUSH,X
  STA VDATA
  INX
  CPX #6
  BNE .db_l
  LDA BONUS
  JSR PUT_2
  LDA #'0'
  STA VDATA
  NOP
  NOP
  STA VDATA
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

DRAW_HUD:
  JSR DRAW_TOP
  JMP DRAW_STATUS

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives, bonus and level, 4 the bonus
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  PHA
  AND #1
  BEQ .uh_l
  LDX CURP
  JSR DRAW_SCORE
.uh_l:
  PLA
  PHA
  AND #2
  BEQ .uh_b
  JSR DRAW_STATUS
.uh_b:
  PLA
  AND #4
  BEQ .uh_r
  JSR DRAW_BONUS
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: his block
  LDA CURP
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA LEVEL,Y
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
  TAX
  LDY #0
.lp_b:
  LDA PSAVE,X
  STA LEVEL,Y
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

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 10000
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
  LDA XTRA
  BNE .as_d
  LDA SCH,X
  BEQ .as_d
  INC XTRA
  INC LIVES,X
  LDA #2
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
;  THE SCREEN: which one, its colour, its tiles
; ===============================================================
SET_SCREEN:
  JSR SEQ_SCREEN
  STA SCRN
  LDX LEVEL
  CPX #10
  BCC .ss_x
  LDX #9
.ss_x:
  STX LEVI
  LDA SCRN                     ; planks: screen * 12, ladders: screen * 10
  ASL A
  ASL A
  STA T0
  ASL A
  CLC
  ADC T0
  STA PIDX
  LDA SCRN
  ASL A
  STA T0
  ASL A
  ASL A
  CLC
  ADC T0
  STA LIDX
  LDX SCRN                     ; the colour of the planks and ladders
  LDA SC_COL,X
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #1
  ; fall into STRUCT_COL

; A = colour byte: the planks and ladders in the three thirds
STRUCT_COL:
  STA T4
  LDX #0
.sc_t:
  LDA SC_THIRD,X
  STA T1
  LDA #<($2000 + T_PU * 8)
  STA T0
  LDA #<(STRUCT_N * 8)
  STA T2
  LDA #>(STRUCT_N * 8)
  STA T3
  PHX
  LDA T4
  JSR VFILL
  PLX
  INX
  CPX #3
  BNE .sc_t
  RTS

; the name table of the screen (rows 2-23) and the windows already shut
DRAW_SCREEN:
  JSR CLEAR_NT
  ; fall into DRAW_ROWS

DRAW_ROWS:
  LDA #<(VDP_NAME_TABLE_BASE + 64)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >(VDP_NAME_TABLE_BASE + 64))
  STA VREG
  LDX SCRN
  LDA SC_NTL,X
  STA PTR
  LDA SC_NTH,X
  STA PTR+1
.dr_l:
  LDA (PTR)                    ; count (0 = end), tile
  BEQ .dr_w
  TAX
  LDY #1
  LDA (PTR),Y
.dr_t:
  STA VDATA
  DEX
  BNE .dr_t
  LDA PTR
  CLC
  ADC #2
  STA PTR
  BCC .dr_l
  INC PTR+1
  BRA .dr_l
.dr_w:
  LDA SCRN                     ; the lantern: the windows already shut
  CMP #3
  BNE .dr_r
  LDX #0
.dr_k:
  LDA BITS,X
  AND WINS
  BEQ .dr_n
  JSR DRAW_WIN
.dr_n:
  INX
  CPX #8
  BNE .dr_k
.dr_r:
  RTS

; X = window: shut (2 tiles over its floor; keeps X)
DRAW_WIN:
  STX T4
  LDA WIN_Y,X
  LSR A
  LSR A
  LSR A
  SEC
  SBC #3
  STA T5
  TAX
  LDY T4
  LDA WIN_C,Y
  TAY
  JSR NT_XY
  LDA #T_WINC
  STA VDATA
  LDX T5
  INX
  LDY T4
  LDA WIN_C,Y
  TAY
  JSR NT_XY
  LDA #T_WINC+1
  STA VDATA
  LDX T4
  RTS

; the name of the screen in the middle
MSG_SCREEN:
  LDX #12
  LDY #10
  JSR NT_XY
  LDX SCRN
  LDA SCN_LO,X
  STA PTR
  LDA SCN_HI,X
  STA PTR+1
  LDY #0
.ms_l:
  LDA (PTR),Y
  BEQ .ms_p
  STA VDATA
  INY
  BRA .ms_l
.ms_p:
  LDA NPL
  CMP #2
  BNE .ms_r
  LDX #14
  LDY #11
  JSR NT_XY
  LDX #0
.ms_n:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .ms_n
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ms_r:
  RTS

MSG_CLEAR:
  JMP DRAW_ROWS

; Gus at the bottom, the bonus full, no coconuts; the crabs of the screen; the lifts
START_POS:
  LDX SCRN
  LDA SC_SX,X
  STA GX
  LDA #184
  STA GY
  STZ GDIR
  STZ GST
  STZ BROOMT
  STZ GFRM
  STZ BRGOT
  STZ ITGOT
  STZ PTT
  STZ GULLP
  STZ NCRAB
  LDA #90
  STA THROWT
  LDA #180
  STA SPAWNT
  LDA #BONUS0
  STA BONUS
  LDA #BONUSF
  STA BONT
  LDX #NO-1
.sp_o:
  STZ O_T,X
  DEX
  BPL .sp_o
  LDX SCRN                     ; 2 crabs to start with (not on the pier)
  LDA SCRN
  ASL A
  TAY
  LDA CRAB0_X,Y
  BEQ .sp_l
  LDX #6
  JSR CRAB_AT
  LDA SCRN
  ASL A
  TAY
  INY
  LDA CRAB0_X,Y
  LDX #7
  JSR CRAB_AT
.sp_l:
  LDX #0                       ; the lifts: 3 up at 56, 104, 152; 3 down at 64, 112, 160
.sp_f:
  LDA LIFT0,X
  STA LF_Y,X
  INX
  CPX #NLIFT
  BNE .sp_f
  RTS

; X = slot, A = x, Y = index of the start tables: a crab there
CRAB_AT:
  STA O_X,X
  LDA CRAB0_Y,Y
  STA O_Y,X
  LDA #4
  STA O_T,X
  STZ O_S,X
  STZ O_ACC,X
  TYA
  AND #1
  STA O_D,X
  INC NCRAB
  RTS


; ===============================================================
;  PLANKS, LADDERS, LIFTS
; ===============================================================
; X = plank, T6 = column: A = y of its top there
PK_Y:
  LDA T6
  SEC
  SBC PK_X0,X
  LSR A
  STA T5
  LDA PK_SL,X
  BEQ .py_f
  BMI .py_u
  LDA PK_Y0,X
  CLC
  ADC T5
  RTS
.py_u:
  LDA PK_Y0,X
  SEC
  SBC T5
  RTS
.py_f:
  LDA PK_Y0,X
  RTS

; A = column, T0 = y: the plank top there within 3 pixels -> C = 1, A = its y, SLOPE (keeps nothing)
SURF_AT:
  STA T6
  LDX SCRN
  LDA PK_N,X
  STA T7
  LDX PIDX
.sa_l:
  LDA T6
  CMP PK_X0,X
  BCC .sa_n
  LDA PK_X1,X
  CMP T6
  BCC .sa_n
  JSR PK_Y
  SEC
  SBC T0
  BCS .sa_p
  EOR #$FF
  INC A
.sa_p:
  CMP #4
  BCS .sa_n
  LDA PK_SL,X
  STA SLOPE
  JSR PK_Y
  SEC
  RTS
.sa_n:
  INX
  DEC T7
  BNE .sa_l
  CLC
  RTS

; A = column, T0 = y before, T1 = y after (going down): the first plank top in between -> C = 1, A, SLOPE
SURF_BELOW:
  STA T6
  LDA #$FF
  STA T4
  LDX SCRN
  LDA PK_N,X
  STA T7
  LDX PIDX
.sb_l:
  LDA T6
  CMP PK_X0,X
  BCC .sb_n
  LDA PK_X1,X
  CMP T6
  BCC .sb_n
  JSR PK_Y
  CMP T0
  BCC .sb_n
  BEQ .sb_n
  CMP T1
  BEQ .sb_k
  BCS .sb_n
.sb_k:
  CMP T4
  BCS .sb_n
  STA T4
  LDA PK_SL,X
  STA T3
.sb_n:
  INX
  DEC T7
  BNE .sb_l
  LDA T4
  CMP #$FF
  BEQ .sb_no
  LDA T3
  STA SLOPE
  LDA T4
  SEC
  RTS
.sb_no:
  CLC
  RTS

; A = x of a 16-pixel thing: T6 = the column of its middle
MID_COL:
  CLC
  ADC #8
  LSR A
  LSR A
  LSR A
  STA T6
  RTS

; Gus at the foot (T2 = 0) or at the top (T2 = 1) of a whole ladder, in line with it: C = 1, X = ladder
LADDER_AT:
  LDX SCRN
  LDA LD_N,X
  STA T7
  LDX LIDX
.la_l:
  LDA LD_BRK,X
  BNE .la_n
  LDA GX                       ; Gus x = ladder x - 4 (3 pixels either way)
  CLC
  ADC #4
  SEC
  SBC LD_X,X
  CLC
  ADC #3
  CMP #7
  BCS .la_n
  LDA T2
  BNE .la_t
  LDA LD_B,X
  BRA .la_y
.la_t:
  LDA LD_T,X
.la_y:
  SEC
  SBC GY
  CLC
  ADC #2
  CMP #5
  BCS .la_n
  SEC
  RTS
.la_n:
  INX
  DEC T7
  BNE .la_l
  CLC
  RTS

; the cliff: Gus (x) over a lift whose top is within 3 pixels of y: C = 1, A = lift
LIFT_ON:
  LDA SCRN
  CMP #1
  BNE .lo_no
  LDX #0
.lo_l:
  CPX #3                       ; lifts 0-2 in the first shaft, 3-5 in the second
  LDY #0
  BCC .lo_s
  INY
.lo_s:
  LDA GX
  CLC
  ADC #8
  SEC
  SBC LIFT_X,Y
  CMP #16
  BCS .lo_n
  LDA LF_Y,X
  SEC
  SBC GY
  CLC
  ADC #3
  CMP #7
  BCS .lo_n
  TXA
  SEC
  RTS
.lo_n:
  INX
  CPX #NLIFT
  BNE .lo_l
.lo_no:
  CLC
  RTS

; the lifts of the cliff: one pixel every other frame, round and round; Gus rides his
LIFTS:
  LDA SCRN
  CMP #1
  BNE .lf_r
  LDA FRAME_CNT
  AND #1
  BNE .lf_r
  LDX #0
.lf_l:
  CPX #3
  BCS .lf_dn
  DEC LF_Y,X                   ; going up: back to the bottom
  LDA LF_Y,X
  CMP #40
  BCS .lf_n
  ADC #144
  STA LF_Y,X
  BRA .lf_n
.lf_dn:
  INC LF_Y,X                   ; going down: back to the top
  LDA LF_Y,X
  CMP #185
  BCC .lf_n
  SBC #144
  STA LF_Y,X
.lf_n:
  INX
  CPX #NLIFT
  BNE .lf_l
  LDA GST                      ; Gus on a lift
  CMP #4
  BNE .lf_r
  LDX GLAD
  LDA LF_Y,X
  STA GY
  CPX #3
  BCS .lf_d
  CMP #48                      ; up to the top: squashed
  BCS .lf_r
  LDA #6
  JMP KILL
.lf_d:
  CMP #184                     ; down to the bottom: on the floor
  BCC .lf_r
  LDA #184
  STA GY
  STZ GST
.lf_r:
  RTS


; ===============================================================
;  GUS
; ===============================================================
GUS:
  LDA BROOMT                   ; the broom
  BEQ .g_st
  DEC BROOMT
  LDA BROOMT
  AND #15
  BNE .g_st
  LDA #W_SWEEP
  LDX #2
  JSR SFX_WHISTLE
.g_st:
  LDA GST
  CMP #1
  BNE .g_n1
  JMP CLIMB
.g_n1:
  CMP #2
  BNE .g_n2
  JMP JUMP
.g_n2:
  CMP #3
  BNE .g_walk
  JMP FALL
.g_walk:
  LDA BROOMT                   ; with the broom: no jump, no ladder
  BNE .g_mv
  LDA JNEW                     ; jump
  AND #BTN_MASK
  BEQ .g_lad
  LDA #2
  STA GST
  STZ GT2
  STZ GJDX
  LDA JOYC
  AND #4
  BEQ .g_jr
  DEC GJDX
.g_jr:
  LDA JOYC
  AND #8
  BEQ .g_js
  INC GJDX
.g_js:
  LDX #NO-1                    ; nothing jumped yet
.g_jo:
  STZ O_J,X
  DEX
  BPL .g_jo
  LDA #W_JUMP
  LDX #2
  JMP SFX_WHISTLE
.g_lad:
  LDA JOYC                     ; a ladder up or down
  AND #3
  BEQ .g_mv
  LSR A
  LDA #0
  BCS .g_lu
  LDA #1
.g_lu:
  STA T2
  JSR LADDER_AT
  BCC .g_mv
  STX GLAD
  LDA LD_X,X
  SEC
  SBC #4
  STA GX
  LDA #1
  STA GST
  RTS
.g_mv:
  LDA JOYC                     ; left, right
  AND #$0C
  BEQ .g_r
  AND #4
  BEQ .g_rt
  LDA #1
  STA GDIR
  LDA GX
  BEQ .g_r
  DEC GX
  BRA .g_ft
.g_rt:
  STZ GDIR
  LDA GX
  CMP #240
  BCS .g_r
  INC GX
.g_ft:
  INC GFRM
  LDA GFRM
  AND #7
  BNE .g_f
  LDA #W_STEP
  LDX #2
  JSR SFX_WHISTLE
.g_f:
  JMP FOOT
.g_r:
  RTS

; after a step: the plank (or the lift) under Gus, or he falls
FOOT:
  LDA GX
  JSR MID_COL
  LDA GY
  STA T0
  LDA T6
  JSR SURF_AT
  BCC .ft_l
  STA GY
  STZ GST
  RTS
.ft_l:
  JSR LIFT_ON
  BCC .ft_f
  STA GLAD
  TAX
  LDA LF_Y,X
  STA GY
  LDA #4
  STA GST
  RTS
.ft_f:
  LDA #3                       ; nothing under him
  STA GST
  STZ GV
  STZ GFALL
  RTS

CLIMB:
  LDX GLAD
  LDA JOYC
  AND #1
  BEQ .c_dn
  DEC GY                       ; up
  LDA GY
  CMP LD_T,X
  BEQ .c_top
  BCS .c_snd
.c_top:
  LDA LD_T,X
  STA GY
  STZ GST
  RTS
.c_dn:
  LDA JOYC
  AND #2
  BEQ .c_r
  INC GY                       ; down
  LDA GY
  CMP LD_B,X
  BCC .c_snd
  LDA LD_B,X
  STA GY
  STZ GST
  RTS
.c_snd:
  LDA GY
  AND #7
  BNE .c_r
  LDA #W_CLIMB
  LDX #2
  JMP SFX_WHISTLE
.c_r:
  RTS

JUMP:
  LDA GY
  STA T0
  LDX GT2
  LDA JUMPY,X
  STA T5
  CLC
  ADC GY
  STA GY
  STA T1
  LDA GX                       ; on, inside the screen
  CLC
  ADC GJDX
  CMP #241
  BCS .j_x
  STA GX
.j_x:
  INC GT2
  JSR OVER                     ; coconuts jumped
  LDA T5                       ; coming down: a plank, a lift
  BMI .j_up
  BEQ .j_up
  JSR LAND
  BCS .j_r
.j_up:
  LDA GT2
  CMP #JUMP_LEN
  BCC .j_r
  LDA #3                       ; the jump is over: he falls
  STA GST
  LDA #1
  STA GV
  STZ GFALL
.j_r:
  RTS

FALL:
  LDA GV
  CMP #3
  BCS .f_v
  INC GV
.f_v:
  LDA GY
  STA T0
  CLC
  ADC GV
  STA GY
  STA T1
  LDA GFALL
  CLC
  ADC GV
  STA GFALL
  JSR LAND
  BCC .f_d
  LDA GFALL                    ; landed: from too high?
  CMP #21
  BCC .f_r
  LDA #1
  JMP KILL
.f_d:
  LDA GY
  CMP #200
  BCC .f_r
  LDA #1
  JMP KILL
.f_r:
  RTS

; T0 / T1 = y before / after: a plank or a lift between them: Gus stands on it (C = 1)
LAND:
  LDA GX
  JSR MID_COL
  LDA T6
  JSR SURF_BELOW
  BCC .ln_l
  STA GY
  STZ GST
  SEC
  RTS
.ln_l:
  JSR LIFT_ON
  BCC .ln_no
  STA GLAD
  TAX
  LDA LF_Y,X
  STA GY
  LDA #4
  STA GST
  SEC
  RTS
.ln_no:
  CLC
  RTS

; in a jump: a coconut (or a crab, a starfish) right under Gus: 100 once
OVER:
  LDX #0
.ov_l:
  LDA O_T,X
  BEQ .ov_n
  LDA O_J,X
  BNE .ov_n
  LDA O_X,X
  SEC
  SBC GX
  CLC
  ADC #10
  CMP #21
  BCS .ov_n
  LDA O_Y,X
  SEC
  SBC GY
  BCC .ov_n
  BEQ .ov_n
  CMP #28
  BCS .ov_n
  INC O_J,X
  INC JUMPS
  LDA #$00
  STA PTN
  LDA GX
  STA PTX
  LDA GY
  SEC
  SBC #24
  STA PTY
  LDA #40
  STA PTT
  PHX
  LDA #$00
  LDY #$01
  JSR ADD_PTS
  LDA #W_OVER100
  LDX #2
  JSR SFX_WHISTLE
  PLX
.ov_n:
  INX
  CPX #NO
  BNE .ov_l
  RTS

; A = what (DEATHS): a life lost
KILL:
  STA DEATHS
  LDA GSTATE
  BNE .k_r
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  STZ BROOMT
  LDA #W_DOWN
  LDX #2
  JSR SFX_WHISTLE
.k_r:
  RTS


; ===============================================================
;  THE SEAGULL (and the crabs of the lantern)
; ===============================================================
GULL:
  LDA SCRN
  CMP #3
  BNE .gu_th
  DEC SPAWNT                   ; the lantern: a crab now and then from a corner
  BNE .gu_r
  LDA #240
  STA SPAWNT
  LDX LEVI
  LDA NCRAB
  CMP MAXCRAB,X
  BCS .gu_r
  JSR FREE_SLOT
  BCC .gu_r
  LDA #4
  STA O_T,X
  STZ O_S,X
  LDA #184
  STA O_Y,X
  LDA RND
  AND #1
  STA O_D,X
  BEQ .gu_cl
  LDA #224
  BRA .gu_cx
.gu_cl:
  LDA #16
.gu_cx:
  STA O_X,X
  INC NCRAB
.gu_r:
  RTS
.gu_th:
  LDA GULLP                    ; throwing
  BEQ .gu_t
  DEC GULLP
  BNE .gu_r
  JMP THROW
.gu_t:
  DEC THROWT
  BNE .gu_r
  LDA #24
  STA GULLP
  LDX LEVI
  LDA RND
  AND #31
  CLC
  ADC THROW_T,X
  STA THROWT
  LDA #W_SQUAWK
  LDX #2
  JMP SFX_WHISTLE

; the seagull lets go: a coconut on the pier, a coconut falling on the cliff, a starfish on the stairs
THROW:
  JSR FREE_SLOT
  BCC .tw_r
  STZ O_S,X
  STZ O_ACC,X
  STZ O_D,X
  STZ O_V,X
  STZ O_H,X
  LDY SCRN
  LDA SC_GX,Y
  CLC
  ADC #16
  STA O_X,X
  LDA SC_GY,Y
  STA O_Y,X
  LDA #1
  STA O_T,X
  CPY #1
  BNE .tw_s
  LDA RND                      ; the cliff: from the sky, anywhere
  AND #$C0
  ADC #16
  STA O_X,X
  LDA RND
  AND #$1E
  ADC O_X,X
  STA O_X,X
  LDA #20
  STA O_Y,X
  LDA #1
  STA O_S,X
  LDA RND
  AND #1
  STA O_D,X
  RTS
.tw_s:
  CPY #2
  BNE .tw_p
  LDA #3                       ; the stairs: a starfish
  STA O_T,X
  RTS
.tw_p:
  LDA RND                      ; the pier: now and then a blue one (a crab in the pot)
  AND #3
  BNE .tw_r
  LDA NCRAB
  LDY LEVI
  CMP MAXCRAB,Y
  BCS .tw_r
  LDA #2
  STA O_T,X
.tw_r:
  RTS

; C = 1, X = a free object slot (0-5: the last two are for the crabs of the start)
FREE_SLOT:
  LDX #0
.fs_l:
  LDA O_T,X
  BEQ .fs_y
  INX
  CPX #NO
  BNE .fs_l
  CLC
  RTS
.fs_y:
  SEC
  RTS


; ===============================================================
;  THE OBJECTS: coconuts, starfish, crabs
; ===============================================================
OBJECTS:
  LDX #0
.ob_l:
  STX CB
  LDA O_T,X
  BEQ .ob_n
  CMP #4
  BNE .ob_r
  JSR CRAB_MOVE
  BRA .ob_n
.ob_r:
  CMP #3                       ; the starfish hops
  BNE .ob_s
  INC O_H,X
.ob_s:
  LDA O_S,X
  BEQ .ob_roll
  CMP #1
  BEQ .ob_fall
  INC O_Y,X                    ; down a ladder
  LDY O_L,X
  LDA O_Y,X
  CMP LD_B,Y
  BCC .ob_n
  LDA LD_B,Y
  STA O_Y,X
  STZ O_S,X
  LDA RND
  AND #1
  STA O_D,X
  BRA .ob_n
.ob_fall:
  JSR OBJ_FALL
  BRA .ob_n
.ob_roll:
  LDY LEVI                     ; 1 pixel a frame, now and then 2
  LDA O_ACC,X
  CLC
  ADC SPD_F,Y
  STA O_ACC,X
  BCC .ob_1
  JSR ROLL_STEP
  LDX CB
  LDA O_T,X
  BEQ .ob_n
  LDA O_S,X
  BNE .ob_n
.ob_1:
  JSR ROLL_STEP
.ob_n:
  LDX CB
  INX
  CPX #NO
  BNE .ob_l
  RTS

; object CB falling: it lands on a plank and rolls down its slope
OBJ_FALL:
  LDX CB
  LDA O_V,X
  CMP #3
  BCS .of_v
  INC O_V,X
.of_v:
  LDA O_Y,X
  STA T0
  CLC
  ADC O_V,X
  STA O_Y,X
  STA T1
  CMP #200
  BCC .of_l
  STZ O_T,X                    ; out of the screen
  RTS
.of_l:
  LDA O_X,X
  JSR MID_COL
  LDA T6
  JSR SURF_BELOW
  LDX CB
  BCC .of_r
  STA O_Y,X
  STZ O_S,X
  LDA SLOPE                    ; down the slope; on a flat plank the other way
  BNE .of_s
  LDA O_D,X
  EOR #1
  STA O_D,X
  RTS
.of_s:
  BMI .of_lf
  STZ O_D,X
  BRA .of_r
.of_lf:
  LDA #1
  STA O_D,X
.of_r:
  RTS

; object CB rolling: one pixel on; the pot, the edges, the ladders, the end of the plank
ROLL_STEP:
  LDX CB
  LDA O_D,X
  BNE .rl_l
  INC O_X,X
  LDA O_X,X
  CMP #240
  BCC .rl_c
  STZ O_T,X                    ; the right edge: into the sea
  RTS
.rl_l:
  DEC O_X,X
  LDA O_X,X
  CMP #8
  BCS .rl_c
  LDA SCRN                     ; the pot of the pier, at the bottom on the left
  BNE .rl_e
  LDA O_Y,X
  CMP #184
  BNE .rl_e
  LDA O_T,X
  STZ O_T,X
  CMP #2
  BNE .rl_r
  LDA #4                       ; the blue one: a crab comes out
  STA O_T,X
  STZ O_D,X
  STZ O_S,X
  LDA #8
  STA O_X,X
  INC NCRAB
.rl_r:
  RTS
.rl_e:
  LDA O_X,X
  BNE .rl_c
  STZ O_T,X                    ; the left edge: into the sea
  RTS
.rl_c:
  LDA O_X,X                    ; the plank under it
  JSR MID_COL
  LDX CB
  LDA O_Y,X
  STA T0
  LDA T6
  JSR SURF_AT
  LDX CB
  BCC .rl_f
  STA O_Y,X
  LDA O_T,X                    ; a coconut at the top of a ladder may go down it
  CMP #3
  BCS .rl_k
  JSR LADDER_TOP
.rl_k:
  RTS
.rl_f:
  LDA #1                       ; the end of the plank: it falls
  STA O_S,X
  STZ O_V,X
  RTS

; coconut CB rolling: at the top of a ladder (broken too), now and then down it
LADDER_TOP:
  LDY SCRN
  LDA LD_N,Y
  STA T7
  LDY LIDX
.lt_l:
  LDA LD_X,Y
  SEC
  SBC #4
  CMP O_X,X
  BNE .lt_n
  LDA LD_T,Y
  SEC
  SBC O_Y,X
  CLC
  ADC #1
  CMP #3
  BCS .lt_n
  STY T5                       ; going down?
  LDY LEVI
  LDA RND
  CMP LADP,Y
  LDY T5
  BCS .lt_n
  LDA #2
  STA O_S,X
  TYA
  STA O_L,X
  RTS
.lt_n:
  INY
  DEC T7
  BNE .lt_l
  RTS

; crab CB: along its plank, back at the end; at a ladder now and then up or down (more toward Gus)
CRAB_MOVE:
  LDX CB
  LDA O_ACC,X
  CLC
  ADC #$A0
  STA O_ACC,X
  BCS .cm_go
  RTS
.cm_go:
  LDA O_S,X
  CMP #2
  BNE .cm_u
  INC O_Y,X                    ; down a ladder
  LDY O_L,X
  LDA O_Y,X
  CMP LD_B,Y
  BCC .cm_r
  LDA LD_B,Y
  STA O_Y,X
  STZ O_S,X
  RTS
.cm_u:
  CMP #3
  BNE .cm_w
  DEC O_Y,X                    ; up a ladder
  LDY O_L,X
  LDA O_Y,X
  CMP LD_T,Y
  BEQ .cm_ut
  BCS .cm_r
.cm_ut:
  LDA LD_T,Y
  STA O_Y,X
  STZ O_S,X
.cm_r:
  RTS
.cm_w:
  JSR CRAB_LADDER              ; walking: a ladder here?
  LDX CB
  LDA O_S,X
  BNE .cm_r
  LDA O_X,X                    ; a step
  STA T4
  LDA O_D,X
  BNE .cm_l
  INC O_X,X
  LDA O_X,X
  CMP #241
  BCS .cm_back
  BRA .cm_f
.cm_l:
  LDA O_X,X
  BEQ .cm_back
  DEC O_X,X
.cm_f:
  LDA O_X,X                    ; still on the plank?
  JSR MID_COL
  LDX CB
  LDA O_Y,X
  STA T0
  LDA T6
  JSR SURF_AT
  LDX CB
  BCC .cm_back
  STA O_Y,X
  RTS
.cm_back:
  LDA T4
  STA O_X,X
  LDA O_D,X
  EOR #1
  STA O_D,X
  RTS

; crab CB walking: in line with a whole ladder at its foot or top: maybe up or down
CRAB_LADDER:
  LDY SCRN
  LDA LD_N,Y
  STA T7
  LDY LIDX
.cl_l:
  LDA LD_BRK,Y
  BNE .cl_n
  LDA LD_X,Y
  SEC
  SBC #4
  CMP O_X,X
  BNE .cl_n
  LDA O_Y,X                    ; at the foot: up (more often when Gus is higher)
  CMP LD_B,Y
  BNE .cl_t
  LDA GY
  CMP O_Y,X
  LDA #$40
  BCS .cl_up
  LDA #$C0
.cl_up:
  CMP RND
  BCC .cl_n
  LDA #3
  BRA .cl_go
.cl_t:
  CMP LD_T,Y                   ; at the top: down (more often when Gus is lower)
  BNE .cl_n
  LDA O_Y,X
  CMP GY
  LDA #$40
  BCS .cl_dn
  LDA #$C0
.cl_dn:
  CMP RND
  BCC .cl_n
  LDA #2
.cl_go:
  STA O_S,X
  TYA
  STA O_L,X
  RTS
.cl_n:
  INY
  DEC T7
  BNE .cl_l
  RTS


; ===============================================================
;  WHO TOUCHES WHO, WHAT GUS PICKS UP, THE BONUS, THE GOAL
; ===============================================================
TOUCH:
  LDX #0
.to_l:
  LDA O_T,X
  BEQ .to_n
  LDA O_X,X                    ; less than 9 pixels apart
  SEC
  SBC GX
  CLC
  ADC #8
  CMP #17
  BCS .to_n
  JSR OBJ_YD                   ; its feet from 14 above to 7 below Gus's feet (the starfish hops)
  SEC
  SBC GY
  CLC
  ADC #14
  CMP #22
  BCS .to_n
  LDA BROOMT
  BEQ .to_hit
  LDA O_T,X                    ; the broom sweeps it away
  STZ O_T,X
  INC SWEPT
  CMP #4
  BNE .to_c
  DEC NCRAB
  LDY #$05
  LDA #2
  BRA .to_p
.to_c:
  LDY #$03
  LDA #1
.to_p:
  STA PTN
  LDA O_X,X
  STA PTX
  LDA O_Y,X
  SEC
  SBC #17
  STA PTY
  LDA #40
  STA PTT
  LDA #0
  JSR ADD_PTS
  PHX
  LDA #W_HIT
  LDX #2
  JSR SFX_WHISTLE
  PLX
  BRA .to_n
.to_hit:
  LDA O_T,X                    ; 2 coconut, 3 crab, 4 starfish
  TAY
  LDA DK_OF,Y
  JMP KILL
.to_n:
  INX
  CPX #NO
  BNE .to_l
  RTS

; X = object: A = its y on the screen (a starfish hops)
OBJ_YD:
  LDA O_T,X
  CMP #3
  BNE .oy_y
  LDA O_H,X
  AND #31
  TAY
  LDA O_Y,X
  SEC
  SBC HOP,Y
  RTS
.oy_y:
  LDA O_Y,X
  RTS

; brooms, things of Gus, the windows of the lantern
PICKUPS:
  LDA SCRN
  ASL A
  STA T4
  LDX #0
.pk_l:
  LDA BITS,X
  AND BRGOT
  BNE .pk_i
  LDY T4
  LDA BR_X,Y
  JSR NEAR_GX
  BCS .pk_i
  LDA BR_Y,Y
  JSR NEAR_GY
  BCS .pk_i
  LDA BITS,X
  TSB BRGOT
  LDA #<480
  STA BROOMT
  LDA #W_ITEM
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
.pk_i:
  LDA BITS,X
  AND ITGOT
  BNE .pk_n
  LDY T4
  LDA IT_X,Y
  JSR NEAR_GX
  BCS .pk_n
  LDA IT_Y,Y
  JSR NEAR_GY
  BCS .pk_n
  LDA BITS,X
  TSB ITGOT
  PHX
  LDX LEVI
  LDA ITEM_N,X
  STA PTN
  LDY ITEM_M,X
  LDA GX
  STA PTX
  LDA GY
  SEC
  SBC #24
  STA PTY
  LDA #50
  STA PTT
  LDA #0
  JSR ADD_PTS
  LDA #W_ITEM
  LDX #2
  JSR SFX_WHISTLE
  PLX
.pk_n:
  INC T4
  INX
  CPX #2
  BNE .pk_l
  LDA SCRN                     ; the windows of the lantern: Gus walks over them
  CMP #3
  BNE .pk_r
  LDA GST
  BNE .pk_r
  LDX #0
.pk_w:
  LDA BITS,X
  AND WINS
  BNE .pk_wn
  LDA WIN_Y,X
  CMP GY
  BNE .pk_wn
  LDA WIN_C,X
  ASL A
  ASL A
  ASL A
  SEC
  SBC #4
  JSR NEAR_GX
  BCS .pk_wn
  LDA BITS,X
  TSB WINS
  JSR DRAW_WIN
  PHX
  LDA #$00
  LDY #$01
  JSR ADD_PTS
  LDA #W_SHUT
  LDX #2
  JSR SFX_WHISTLE
  PLX
.pk_wn:
  INX
  CPX #8
  BNE .pk_w
.pk_r:
  RTS

; A = x: C = 0 when Gus is less than 8 pixels from it (keeps X, Y)
NEAR_GX:
  SEC
  SBC GX
  CLC
  ADC #7
  CMP #15
  RTS

; A = y: C = 0 when Gus's feet are within 2 pixels of it (keeps X, Y)
NEAR_GY:
  SEC
  SBC GY
  CLC
  ADC #2
  CMP #5
  RTS

BONUS_TICK:
  DEC BONT
  BNE .bt_r
  LDA #BONUSF
  STA BONT
  SED
  LDA BONUS
  SEC
  SBC #1
  STA BONUS
  CLD
  LDA #4
  TSB HUDD
  LDA BONUS
  BNE .bt_r
  LDA #5
  JMP KILL
.bt_r:
  RTS

; the top reached (the lantern: all the windows shut): the screen is done
GOAL:
  LDA SCRN
  CMP #3
  BNE .go_t
  LDA WINS
  CMP #$FF
  BNE .go_r
  BRA .go_d
.go_t:
  LDA GST
  BNE .go_r
  LDX SCRN
  LDA GY
  CMP SC_GOAL,X
  BNE .go_r
.go_d:
  LDA #3
  STA GSTATE
  LDA #30
  STA GT
.go_r:
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA GSTATE                   ; Gus (2 sprites) and his broom
  CMP #1
  BNE .bs_g
  LDA GT
  CMP #15
  BCS .bs_gd
  JMP .bs_gull
.bs_gd:
  LDA #PT_GDOWN
  BRA .bs_gp
.bs_g:
  LDA GST
  CMP #1
  BNE .bs_nc
  LDA GY                       ; climbing
  AND #4
  ASL A
  CLC
  ADC #PT_CLIMB
  BRA .bs_gp
.bs_nc:
  LDY #3                       ; the frame: broom, jump, walking
  LDA BROOMT
  BNE .bs_fr
  DEY
  LDA GST
  CMP #2
  BEQ .bs_fr
  CMP #3
  BEQ .bs_fr
  LDA GFRM
  LSR A
  LSR A
  LSR A
  AND #1
  TAY
.bs_fr:
  TYA
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_GUS
  LDY GDIR
  BEQ .bs_gp
  CLC
  ADC #PT_GUSL-PT_GUS
.bs_gp:
  STA ON
  LDA GX
  STA OX
  LDA GY
  SEC
  SBC #17
  STA OY
  LDA #15                      ; the face and the hands
  STA OC
  LDA ON
  PHA
  CLC
  ADC #4
  STA ON
  JSR ADD_SPR
  PLA
  STA ON
  LDA #11                      ; the oilskin
  STA OC
  JSR ADD_SPR
  LDA BROOMT                   ; the broom: up and down
  BEQ .bs_gull
  LDA GSTATE
  BNE .bs_gull
  LDA FRAME_CNT
  AND #8
  LSR A
  STA T0
  LDA GDIR
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_BROOM
  STA ON
  LDA #10
  STA OC
  LDA T0
  BNE .bs_bd
  LDA GY                       ; up: over his head
  SEC
  SBC #31
  STA OY
  BRA .bs_bs
.bs_bd:
  LDA GX                       ; down: in front of him
  LDY GDIR
  BNE .bs_bl
  CLC
  ADC #12
  BRA .bs_bx
.bs_bl:
  SEC
  SBC #12
.bs_bx:
  STA OX
.bs_bs:
  JSR ADD_SPR
.bs_gull:
  LDX SCRN                     ; Squawk (2 sprites)
  LDA SC_GX,X
  STA OX
  LDA SC_GY,X
  SEC
  SBC #17
  STA OY
  LDA #PT_GULL+16              ; throwing, or flapping
  LDY GULLP
  BNE .bs_gk
  LDA FRAME_CNT
  AND #16
  LSR A
  CLC
  ADC #PT_GULL
.bs_gk:
  STA ON
  LDA #15
  STA OC
  LDA ON
  PHA
  JSR ADD_SPR
  PLA
  CLC
  ADC #4
  STA ON
  LDA #11
  STA OC
  JSR ADD_SPR
  ; the others, a different first one every frame
  LDA SPRROT
  INC A
  CMP #NOTHERS
  BCC .bs_rot
  LDA #0
.bs_rot:
  STA SPRROT
  STA T7
  LDA #NOTHERS
  STA T6
.bs_k:
  LDX T7
  CPX #NO
  BCS .bs_nl
  JSR OBJ_SPR
  BRA .bs_kn
.bs_nl:
  TXA
  SEC
  SBC #NO
  CMP #NLIFT
  BCS .bs_np
  TAX
  JSR LIFT_SPR
  BRA .bs_kn
.bs_np:
  SEC
  SBC #NLIFT
  TAX
  JSR PICK_SPR
.bs_kn:
  INC T7
  LDA T7
  CMP #NOTHERS
  BCC .bs_kk
  STZ T7
.bs_kk:
  DEC T6
  BNE .bs_k
  LDY SPRI
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; X = object
OBJ_SPR:
  LDA O_T,X
  BNE .os_on
  RTS
.os_on:
  LDA O_X,X
  STA OX
  JSR OBJ_YD
  SEC
  SBC #17
  STA OY
  LDA O_X,X                    ; 2 frames as it goes
  LSR A
  LSR A
  AND #4
  STA T0
  LDA O_T,X
  TAY
  LDA OBJ_PT,Y
  CLC
  ADC T0
  STA ON
  LDA OBJ_C,Y
  STA OC
  JMP ADD_SPR

; X = lift (the cliff only)
LIFT_SPR:
  LDA SCRN
  CMP #1
  BNE .lsp_r
  LDY #0
  CPX #3
  BCC .lsp_s
  INY
.lsp_s:
  LDA LIFT_X,Y
  STA OX
  LDA LF_Y,X
  DEC A
  STA OY
  LDA #PT_LIFT
  STA ON
  LDA #7
  STA OC
  JMP ADD_SPR
.lsp_r:
  RTS

; X = 0-1 brooms, 2-3 things of Gus, 4 the points shown
PICK_SPR:
  CPX #4
  BCC .pi_bi
  LDA PTT
  BEQ .pi_r
  DEC PTT
  LDA PTX
  STA OX
  LDA PTY
  STA OY
  LDA PTN
  ASL A
  ASL A
  CLC
  ADC #PT_PTS
  STA ON
  LDA #15
  STA OC
  JMP ADD_SPR
.pi_bi:
  CPX #2
  BCS .pi_it
  LDA BITS,X
  AND BRGOT
  BNE .pi_r
  LDA SCRN
  ASL A
  STA T0
  TXA
  CLC
  ADC T0
  TAY
  LDA BR_X,Y
  STA OX
  LDA BR_Y,Y
  SEC
  SBC #17
  STA OY
  LDA #PT_BROOMI
  STA ON
  LDA #10
  STA OC
  JMP ADD_SPR
.pi_it:
  LDA BITS-2,X
  AND ITGOT
  BNE .pi_r
  LDA SCRN
  ASL A
  STA T0
  TXA
  CLC
  ADC T0
  TAY
  LDA IT_X-2,Y
  STA OX
  LDA IT_Y-2,Y
  SEC
  SBC #17
  STA OY
  LDA LEVEL
  AND #3
  CMP #3
  BCC .pi_k
  LDA #2
.pi_k:
  ASL A
  ASL A
  CLC
  ADC #PT_ITEM
  STA ON
  LDA #13
  STA OC
  JMP ADD_SPR
.pi_r:
  RTS

; OX, OY, ON, OC: one sprite more (keeps X)
ADD_SPR:
  LDY SPRI
  CPY #128
  BCS .as_full
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
.as_full:
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from mole hole)
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
SC_COLS:    .byte 4,26                         ; score of player 1 / 2 on row 0
BITS:       .byte 1,2,4,8,16,32,64,128
S_BIG = S_CRASH                                ; (lib_sound: a big noise is not cut by a small one)
; the colour table of the planks and ladders in the three thirds (high byte, write bit)
SC_THIRD:   .byte (>($2000 + T_PU * 8)) | $40, (>($2800 + T_PU * 8)) | $40, (>($3000 + T_PU * 8)) | $40
; the screens of a level: level 1 pier and lantern, level 2 with the cliff, then all four
SEQ_LO:     .byte <SEQ0,<SEQ1,<SEQ2
SEQ_HI:     .byte >SEQ0,>SEQ1,>SEQ2
SEQ0:       .byte 0,3,$FF
SEQ1:       .byte 0,1,3,$FF
SEQ2:       .byte 0,1,2,3,$FF
; the jump: pixels up / down every frame
JUMPY:      .byte $FE,$FE,$FE,$FF,$FF,$FF,$FF,$FF,$FF,0,0,0,0,1,1,1,1,1,1,2,2,2
JUMP_LEN = 22
; the hop of a starfish (32 frames)
HOP:        .byte 0,2,4,6,7,8,9,10,10,10,9,8,7,6,4,2,0,1,2,3,4,4,5,5,5,4,4,3,2,1,0,0
; per level (0-9): extra speed of coconuts and starfish (fraction), frames between throws,
; chance (of 256) of a coconut going down a ladder, crabs at most
SPD_F:      .byte $20,$30,$40,$50,$60,$70,$80,$90,$A0,$B0
THROW_T:    .byte 150,140,130,120,110,100,92,86,80,75
LADP:       .byte 50,60,70,80,90,100,110,120,130,140
MAXCRAB:    .byte 2,2,3,3,3,4,4,4,5,5
; the things of Gus: points (hundreds, BCD) and the pattern of the points shown (1 = 300, 2 = 500, 3 = 800)
ITEM_M:     .byte $03,$05,$08,$08,$08,$08,$08,$08,$08,$08
ITEM_N:     .byte 1,2,3,3,3,3,3,3,3,3
; what takes the life by the kind of object (1 coconut, 2 blue, 3 starfish, 4 crab)
DK_OF:      .byte 0,2,2,4,3
OBJ_PT:     .byte 0,PT_COCO,PT_COCO,PT_STARF,PT_CRAB
OBJ_C:      .byte 0,6,7,9,8
NOTHERS = NO + NLIFT + 5
; the lifts of the cliff at the start: 3 going up, 3 going down
LIFT0:      .byte 56,104,152,64,112,160
; 2 crabs at the start of every screen (x, y; x = 0: none)
CRAB0_X:    .byte 0,0, 96,200, 160,40, 24,216
CRAB0_Y:    .byte 0,0, 136,104, 120,88, 148,148

; title: Gus (2), the seagull (2), coconut, broom, crab, a thing of Gus
TITLE_NS = 8
TITLE_SY:   .byte 39,39,39,39,83,99,115,131
TITLE_SX:   .byte 40,40,200,200,40,40,40,40
TITLE_SN:   .byte PT_GUS+4,PT_GUS,PT_GULL,PT_GULL+4,PT_COCO,PT_BROOMI,PT_CRAB,PT_ITEM
TITLE_SC:   .byte 15,11,15,11,6,10,8,13
TITLE_SA:   .byte 8,8,8,8,4,0,4,0

TXT_BONUSH: .byte "BONUS "
TXT_PLAYERH: .byte "PLAYER "
; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 0,12,"HI",0
  .byte $FF
TXT_TOP2:
  .byte 0,22,"2UP",0,$FF
TXT_BUTTONS:
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,4,"HELP GUS LIGHT THE LAMP",0
  .byte 11,9,"JUMP OVER       100",0
  .byte 13,9,"BROOM: COCONUT  300",0
  .byte 15,9,"       CRAB     500",0
  .byte 17,9,"GUS'S THINGS 300-800",0
  .byte $FF
TXT_OVER:
  .byte 12,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 14,11,"PLAYER ",0,$FF

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
;  GRAPHICS, SCREENS AND SOUND TABLES (generated)
; ===============================================================
; LIGHTHOUSE KEEPER: generated by dev/gen_lighthouse_keeper.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; tiles
T_PU = 96
T_PL = 104
T_LAD = 108
T_LPU = 109
T_LPL = 117
T_POT = 121
T_PILE = 125
T_WINO = 129
T_WINC = 131
T_STAR = 133
T_SEA = 134
T_LIFE = 135
T_BEAM = 136
PT_GUS = 0
PT_GUSL = 32
PT_CLIMB = 64
PT_GDOWN = 80
PT_BROOM = 88
PT_GULL = 104
PT_COCO = 128
PT_CRAB = 136
PT_STARF = 144
PT_LIFT = 152
PT_ITEM = 156
PT_BROOMI = 168
PT_PTS = 172
STRUCT_N = 25
NSCR = 4
BIGT = 200
BIGB = 228
SPR_LEN = 1504
SPR_PAGES = 6
SPRITES:
  .byte $00,$07,$0F,$1F,$00,$00,$00,$00,$0F,$1F,$3F,$1F,$0F,$0E,$0C,$1C,$00,$C0,$E0,$F8,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$E0,$E0,$60,$70
  .byte $00,$00,$00,$00,$07,$0F,$0F,$07,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$F0,$C0,$C0,$00,$00,$08,$00,$00,$00,$00,$00
  .byte $00,$07,$0F,$1F,$00,$00,$00,$00,$0F,$1F,$1F,$0F,$0F,$07,$03,$03,$00,$C0,$E0,$F8,$00,$00,$00,$00,$E0,$E0,$E0,$E0,$E0,$C0,$80,$C0
  .byte $00,$00,$00,$00,$07,$0F,$0F,$07,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$F0,$C0,$C0,$00,$00,$10,$00,$00,$00,$00,$00
  .byte $00,$07,$0F,$1F,$00,$00,$00,$00,$0F,$1F,$1F,$3F,$0F,$0F,$18,$30,$00,$C0,$E0,$F8,$00,$00,$04,$0C,$F8,$F0,$E0,$E0,$E0,$F0,$30,$18
  .byte $00,$00,$00,$00,$07,$0F,$0F,$07,$00,$00,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00,$A4,$F4,$C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$0F,$1F,$00,$00,$00,$00,$0F,$1F,$3F,$3F,$0F,$0E,$0C,$1C,$00,$C0,$E0,$F8,$00,$00,$00,$00,$F8,$F0,$E0,$C0,$E0,$E0,$60,$70
  .byte $00,$00,$00,$00,$07,$0F,$0F,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$F0,$C6,$CC,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$1F,$00,$00,$00,$00,$07,$0F,$0F,$07,$07,$07,$06,$0E,$00,$E0,$F0,$F8,$00,$00,$00,$00,$F0,$F8,$FC,$F8,$F0,$70,$30,$38
  .byte $00,$00,$00,$00,$05,$0F,$03,$03,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$00,$00,$00,$04,$00,$00,$00,$00
  .byte $00,$03,$07,$1F,$00,$00,$00,$00,$07,$07,$07,$07,$07,$03,$01,$03,$00,$E0,$F0,$F8,$00,$00,$00,$00,$F0,$F8,$F8,$F0,$F0,$E0,$C0,$C0
  .byte $00,$00,$00,$00,$05,$0F,$03,$03,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$00,$00,$00,$08,$00,$00,$00,$00
  .byte $00,$03,$07,$1F,$00,$00,$20,$30,$1F,$0F,$07,$07,$07,$0F,$0C,$18,$00,$E0,$F0,$F8,$00,$00,$00,$00,$F0,$F8,$F8,$FC,$F0,$F0,$18,$0C
  .byte $00,$00,$00,$00,$25,$2F,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$00,$00,$02,$02,$00,$00,$00,$00
  .byte $00,$03,$07,$1F,$00,$00,$00,$00,$1F,$0F,$07,$03,$07,$07,$06,$0E,$00,$E0,$F0,$F8,$00,$00,$00,$00,$F0,$F8,$FC,$FC,$F0,$70,$30,$38
  .byte $00,$00,$00,$00,$05,$0F,$63,$33,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$0F,$1F,$00,$00,$60,$3F,$0F,$0F,$0F,$0F,$0E,$0C,$0C,$1C,$00,$C0,$E0,$F0,$00,$00,$0C,$F8,$E0,$E0,$E0,$E0,$E0,$60,$70,$00
  .byte $00,$00,$00,$00,$4F,$4F,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E4,$E4,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$0F,$00,$00,$30,$1F,$07,$07,$07,$07,$07,$06,$0E,$00,$00,$E0,$F0,$F8,$00,$00,$06,$FC,$F0,$F0,$F0,$F0,$70,$30,$30,$38
  .byte $00,$00,$00,$00,$27,$27,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F2,$F2,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$F8,$FF,$6F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FC,$FF,$FF,$F6,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0E,$0F,$07,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08
  .byte $0A,$0F,$0F,$07,$02,$02,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$20,$10,$08,$04,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$7E,$FE,$AA,$00
  .byte $01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$50,$F0,$F0,$E0,$40,$40,$40,$40,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$7E,$7F,$55,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$04,$08,$10,$20,$40,$00
  .byte $00,$00,$00,$00,$20,$30,$18,$0F,$0F,$1F,$1F,$0F,$07,$00,$00,$00,$00,$00,$00,$00,$08,$18,$30,$E0,$F0,$F0,$F0,$F0,$E0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$0C,$00,$00,$40,$40,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$0F,$0F,$7F,$FF,$CF,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$F0,$F3,$E0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$0C,$00,$00,$40,$40,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$3F,$7F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$F0,$F0,$F0,$E0,$C0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$06,$00,$00,$00,$00,$00,$00,$00,$00,$08,$0C,$00,$00,$00,$40,$40,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$1F,$3B,$3F,$3F,$3B,$1F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$70,$F0,$F0,$F0,$E0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$1F,$3F,$3F,$3B,$3F,$1F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F0,$70,$F0,$F0,$E0,$C0
  .byte $00,$00,$00,$00,$00,$00,$60,$90,$64,$0A,$3F,$7F,$7F,$3F,$52,$92,$00,$00,$00,$00,$00,$00,$06,$09,$26,$50,$FC,$FE,$FE,$FC,$4A,$49
  .byte $00,$00,$00,$00,$00,$60,$90,$60,$05,$3F,$7F,$7F,$3F,$29,$49,$44,$00,$00,$00,$00,$00,$06,$09,$06,$28,$FC,$FE,$FE,$FC,$28,$24,$22
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$03,$7F,$1F,$07,$06,$0C,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$FE,$F8,$E0,$60,$30,$18
  .byte $00,$00,$00,$00,$00,$00,$00,$18,$0C,$06,$07,$1F,$7F,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$18,$30,$60,$E0,$F8,$FE,$80,$00,$00
  .byte $AA,$FF,$7F,$36,$12,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$AA,$FF,$FE,$6C,$48,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$D8,$00,$00,$00,$00,$00,$00,$00,$70,$88,$F8,$70,$20,$60,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$0F,$1F,$3F,$3F,$3F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F0,$F0,$FC,$FC,$00,$00,$00,$00
  .byte $00,$00,$03,$04,$03,$07,$08,$0B,$0B,$08,$07,$0F,$00,$00,$00,$00,$00,$00,$80,$40,$80,$C0,$20,$A0,$A0,$20,$C0,$E0,$00,$00,$00,$00
  .byte $00,$01,$01,$01,$01,$01,$01,$01,$03,$07,$0F,$0A,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$A0,$A0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$13,$32,$12,$12,$3B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3B,$0A,$3A,$0A,$3B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3B,$22,$3A,$0A,$3B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3B,$2A,$3A,$2A,$3B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00

; game tiles 96-137: patterns and colours
TILEP:
  .byte $FF,$A5,$FF,$49,$FF,$00,$00,$00,$00,$FF,$A5,$FF,$49,$FF,$00,$00,$00,$00,$FF,$A5,$FF,$49,$FF,$00,$00,$00,$00,$FF,$A5,$FF,$49,$FF
  .byte $00,$00,$00,$00,$FF,$A5,$FF,$49,$00,$00,$00,$00,$00,$FF,$A5,$FF,$00,$00,$00,$00,$00,$00,$FF,$A5,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $FF,$00,$00,$00,$00,$00,$00,$00,$49,$FF,$00,$00,$00,$00,$00,$00,$FF,$49,$FF,$00,$00,$00,$00,$00,$A5,$FF,$49,$FF,$00,$00,$00,$00
  .byte $42,$7E,$42,$42,$42,$7E,$42,$42,$FF,$FF,$FF,$4B,$FF,$7E,$42,$42,$42,$FF,$E7,$FF,$4B,$FF,$42,$42,$42,$7E,$FF,$E7,$FF,$7F,$FF,$42
  .byte $42,$7E,$42,$FF,$E7,$FF,$4B,$FF,$42,$7E,$42,$42,$FF,$FF,$FF,$4B,$42,$7E,$42,$42,$42,$FF,$E7,$FF,$42,$7E,$42,$42,$42,$7E,$FF,$E7
  .byte $42,$7E,$42,$42,$42,$7E,$42,$FF,$FF,$7E,$42,$42,$42,$7E,$42,$42,$4B,$FF,$42,$42,$42,$7E,$42,$42,$FF,$7F,$FF,$42,$42,$7E,$42,$42
  .byte $E7,$FF,$4B,$FF,$42,$7E,$42,$42,$00,$7F,$55,$7F,$2A,$7F,$55,$7F,$00,$FE,$54,$FE,$AA,$FE,$54,$FE,$2A,$7F,$55,$7F,$2A,$7F,$7F,$00
  .byte $AA,$FE,$54,$FE,$AA,$FE,$FE,$00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$1E,$3F,$3F,$1E,$7B,$FF,$FF,$7B
  .byte $78,$7C,$7E,$7C,$DE,$F7,$F7,$DE,$FF,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$FF,$FF,$AB,$D5,$AB,$D5,$AB,$D5,$AB
  .byte $D5,$AB,$D5,$AB,$D5,$AB,$D5,$FF,$00,$00,$10,$00,$00,$02,$00,$00,$00,$30,$49,$86,$00,$0C,$12,$C1,$38,$7C,$54,$7C,$38,$7C,$FE,$6C
  .byte $80,$C0,$E0,$F0,$F8,$FC,$FE,$FF,$00,$00,$00,$00,$00,$00,$00,$00
TILEC:
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6
  .byte $B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$54,$54,$54,$54,$54,$54,$54,$54,$41,$41,$F1,$F1,$F1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1

; the screens: planks (first column, last column, y at the first column, slope), ladders (column, top, bottom, broken)
SC0_NT:
  .byte $01,$7D,$01,$7E,$0A,$20,$01,$85,$13,$20,$01,$7F,$01,$80,$1E,$20,$0C,$60,$01,$6D,$03,$60,$1C,$20,$01,$6C,$1F,$20,$01,$6C,$0B,$20
  .byte $02,$67,$02,$66,$02,$65,$02,$64,$08,$20,$01,$74,$01,$67,$02,$66,$01,$72,$01,$65,$02,$64,$02,$63,$01,$6F,$01,$62,$02,$61,$02,$60
  .byte $02,$6B,$02,$6A,$02,$69,$02,$68,$04,$20,$02,$61,$02,$60,$01,$78,$01,$6B,$02,$6A,$01,$76,$01,$69,$02,$68,$02,$20,$01,$6C,$07,$20
  .byte $01,$85,$17,$20,$01,$6C,$0D,$20,$02,$64,$02,$65,$02,$66,$02,$67,$01,$6C,$09,$20,$01,$6C,$0D,$20,$02,$68,$02,$69,$02,$6A,$02,$6B
  .byte $01,$6D,$01,$60,$02,$61,$01,$6F,$01,$62,$02,$63,$02,$64,$01,$72,$01,$65,$02,$66,$01,$74,$01,$67,$14,$20,$01,$6C,$03,$20,$02,$68
  .byte $01,$76,$01,$69,$02,$6A,$01,$78,$01,$6B,$02,$60,$01,$6E,$01,$61,$0D,$20,$01,$85,$02,$20,$01,$6C,$0D,$20,$01,$6C,$11,$20,$01,$6C
  .byte $09,$20,$01,$6C,$01,$20,$02,$67,$01,$73,$01,$66,$02,$65,$02,$64,$03,$20,$01,$85,$04,$20,$02,$67,$02,$66,$01,$72,$01,$65,$02,$64
  .byte $01,$70,$01,$63,$02,$62,$02,$61,$01,$6D,$01,$60,$02,$6B,$01,$77,$01,$6A,$02,$69,$02,$68,$04,$20,$02,$61,$01,$6D,$01,$60,$02,$6B
  .byte $02,$6A,$01,$76,$01,$69,$02,$68,$01,$6C,$15,$20,$01,$6C,$19,$20,$02,$64,$02,$65,$02,$66,$01,$74,$01,$67,$08,$20,$01,$6C,$0F,$20
  .byte $02,$68,$02,$69,$02,$6A,$01,$78,$01,$6B,$02,$60,$01,$6E,$01,$61,$02,$62,$02,$63,$01,$71,$01,$64,$02,$65,$02,$66,$02,$67,$07,$20
  .byte $01,$85,$0A,$20,$01,$6C,$05,$20,$01,$75,$01,$68,$02,$69,$02,$6A,$02,$6B,$01,$6D,$01,$60,$02,$61,$04,$20,$01,$79,$01,$7A,$16,$20
  .byte $01,$6C,$07,$20,$01,$7B,$01,$7C,$08,$20,$01,$6C,$0D,$20,$01,$6C,$07,$20,$0A,$60,$01,$6D,$0D,$60,$01,$6D,$07,$60,$00
SC1_NT:
  .byte $04,$20,$01,$85,$19,$20,$01,$7D,$01,$7E,$13,$20,$01,$85,$0A,$20,$01,$7F,$01,$80,$1A,$20,$02,$60,$01,$6D,$03,$60,$1C,$20,$01,$6C
  .byte $1F,$20,$01,$6C,$0E,$20,$01,$60,$01,$6D,$06,$60,$09,$20,$01,$6C,$0F,$20,$01,$6C,$0A,$20,$05,$60,$01,$6D,$01,$60,$01,$6D,$02,$60
  .byte $01,$6D,$05,$60,$05,$20,$01,$6C,$11,$20,$01,$6C,$02,$20,$01,$6C,$0A,$20,$01,$6C,$03,$20,$01,$85,$0D,$20,$01,$6C,$02,$20,$01,$6C
  .byte $01,$20,$01,$85,$08,$20,$01,$6C,$11,$20,$01,$6C,$02,$20,$01,$6C,$07,$20,$03,$60,$01,$6D,$01,$60,$01,$6D,$06,$60,$09,$20,$01,$6C
  .byte $02,$20,$01,$6C,$0C,$20,$01,$6C,$06,$20,$01,$85,$01,$20,$03,$60,$01,$6D,$03,$60,$01,$6D,$02,$60,$01,$6D,$02,$60,$01,$6D,$02,$60
  .byte $01,$20,$01,$85,$05,$20,$01,$6C,$0B,$20,$01,$6C,$09,$20,$01,$6C,$06,$20,$01,$85,$02,$20,$01,$6C,$0B,$20,$01,$6C,$09,$20,$01,$6C
  .byte $01,$20,$01,$85,$07,$20,$01,$6C,$07,$20,$01,$85,$03,$20,$01,$6C,$09,$20,$01,$6C,$04,$20,$05,$60,$01,$6D,$06,$60,$05,$20,$01,$6C
  .byte $09,$20,$01,$6C,$15,$20,$01,$6C,$05,$20,$02,$60,$01,$6D,$01,$60,$01,$6D,$02,$60,$10,$20,$03,$60,$01,$6D,$05,$60,$02,$20,$01,$6C
  .byte $03,$20,$01,$85,$07,$20,$01,$85,$0B,$20,$01,$85,$03,$20,$01,$85,$03,$20,$01,$6C,$1F,$20,$01,$6C,$1D,$20,$02,$60,$01,$6D,$1D,$60
  .byte $00
SC2_NT:
  .byte $01,$7D,$01,$7E,$0E,$20,$01,$85,$0F,$20,$01,$7F,$01,$80,$19,$20,$01,$85,$04,$20,$09,$60,$01,$6D,$10,$20,$01,$85,$06,$20,$01,$85
  .byte $03,$20,$01,$85,$03,$20,$01,$6C,$1F,$20,$01,$6C,$1E,$20,$01,$60,$01,$6D,$02,$60,$01,$6D,$07,$60,$01,$6D,$0B,$60,$0C,$20,$01,$6C
  .byte $07,$20,$01,$6C,$17,$20,$01,$6C,$1F,$20,$01,$6C,$07,$20,$01,$6C,$0B,$20,$0C,$60,$01,$6D,$01,$60,$01,$6D,$03,$60,$01,$6D,$01,$60
  .byte $01,$6D,$03,$60,$16,$20,$01,$6C,$03,$20,$01,$6C,$03,$20,$01,$85,$1B,$20,$01,$6C,$1B,$20,$01,$6C,$03,$20,$01,$6C,$15,$20,$02,$60
  .byte $01,$6D,$03,$60,$01,$6D,$03,$60,$01,$6D,$03,$60,$01,$6D,$09,$60,$0A,$20,$01,$6C,$03,$20,$01,$85,$07,$20,$01,$6C,$12,$20,$01,$85
  .byte $01,$6C,$0E,$20,$01,$85,$03,$20,$01,$85,$0C,$20,$01,$6C,$0B,$20,$01,$6C,$09,$20,$06,$60,$01,$6D,$03,$60,$01,$6D,$09,$60,$01,$6D
  .byte $01,$60,$01,$6D,$01,$60,$0E,$20,$01,$6C,$0D,$20,$01,$6C,$1F,$20,$01,$6C,$11,$20,$01,$6C,$0D,$20,$01,$6C,$0B,$20,$06,$60,$01,$6D
  .byte $0D,$60,$01,$6D,$0B,$60,$00
SC3_NT:
  .byte $08,$20,$01,$81,$0B,$20,$01,$85,$02,$20,$01,$81,$10,$20,$01,$82,$0E,$20,$01,$82,$22,$20,$01,$85,$0B,$20,$04,$60,$01,$6D,$0A,$60
  .byte $01,$6D,$04,$60,$0C,$20,$01,$81,$03,$20,$01,$6C,$09,$20,$01,$85,$01,$6C,$03,$20,$01,$81,$0C,$20,$01,$82,$01,$85,$02,$20,$01,$6C
  .byte $0A,$20,$01,$6C,$03,$20,$01,$82,$01,$20,$01,$85,$0E,$20,$01,$6C,$0A,$20,$01,$6C,$0B,$20,$01,$85,$02,$64,$01,$71,$05,$64,$01,$71
  .byte $0A,$64,$01,$71,$05,$64,$01,$71,$02,$64,$04,$20,$02,$68,$01,$75,$05,$68,$01,$75,$0A,$68,$01,$75,$05,$68,$01,$75,$02,$68,$06,$20
  .byte $01,$6C,$01,$20,$01,$81,$12,$20,$01,$81,$01,$20,$01,$6C,$06,$20,$01,$85,$01,$20,$01,$6C,$01,$20,$01,$82,$12,$20,$01,$82,$01,$20
  .byte $01,$6C,$02,$20,$01,$85,$02,$20,$01,$85,$02,$20,$01,$6C,$16,$20,$01,$6C,$06,$20,$02,$60,$01,$6D,$03,$60,$01,$6D,$06,$60,$01,$6D
  .byte $07,$60,$01,$6D,$03,$60,$01,$6D,$02,$60,$08,$20,$01,$81,$01,$20,$01,$6C,$06,$20,$01,$6C,$07,$20,$01,$6C,$01,$20,$01,$81,$05,$20
  .byte $01,$85,$06,$20,$01,$82,$01,$20,$01,$6C,$06,$20,$01,$6C,$07,$20,$01,$6C,$01,$20,$01,$82,$07,$20,$01,$85,$06,$20,$01,$6C,$06,$20
  .byte $01,$6C,$07,$20,$01,$6C,$0A,$20,$02,$64,$01,$71,$03,$64,$01,$71,$06,$64,$01,$71,$07,$64,$01,$71,$03,$64,$01,$71,$02,$64,$04,$20
  .byte $02,$68,$01,$75,$03,$68,$01,$75,$06,$68,$01,$75,$07,$68,$01,$75,$03,$68,$01,$75,$02,$68,$06,$20,$01,$6C,$05,$20,$01,$85,$10,$20
  .byte $01,$6C,$08,$20,$01,$6C,$0C,$20,$01,$85,$09,$20,$01,$6C,$08,$20,$01,$6C,$16,$20,$01,$6C,$04,$20,$04,$60,$01,$6D,$16,$60,$01,$6D
  .byte $04,$60,$00
PK_N:
  .byte 6,11,6,5
PK_X0:
  .byte $00,$00,$04,$00,$04,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$09,$09,$0B,$17,$17,$17,$1A,$00
  .byte $00,$00,$08,$00,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$02,$02,$06,$00,$00,$00,$00,$00,$00,$00
PK_X1:
  .byte $1F,$1B,$1F,$1B,$1F,$0F,$00,$00,$00,$00,$00,$00
  .byte $1F,$06,$06,$06,$14,$14,$12,$1F,$1F,$1F,$1F,$00
  .byte $1F,$17,$1F,$17,$1F,$09,$00,$00,$00,$00,$00,$00
  .byte $1F,$1D,$1D,$1D,$19,$00,$00,$00,$00,$00,$00,$00
PK_Y0:
  .byte $B8,$94,$81,$54,$41,$20,$00,$00,$00,$00,$00,$00
  .byte $B8,$98,$70,$48,$88,$60,$38,$98,$68,$40,$20,$00
  .byte $B8,$98,$78,$58,$38,$20,$00,$00,$00,$00,$00,$00
  .byte $B8,$94,$70,$4C,$28,$00,$00,$00,$00,$00,$00,$00
PK_SL:
  .byte $00,$01,$FF,$01,$FF,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
LD_N:
  .byte 10,8,9,9
LD_X:
  .byte $50,$C0,$30,$80,$60,$B0,$D0,$40,$90,$60
  .byte $10,$20,$08,$70,$60,$D0,$F0,$E0,$00,$00
  .byte $A0,$30,$50,$B0,$90,$70,$60,$A0,$48,$00
  .byte $20,$D8,$40,$78,$B8,$20,$D8,$50,$A8,$00
LD_T:
  .byte $99,$A0,$80,$7B,$5A,$5F,$61,$3F,$3A,$20
  .byte $98,$70,$48,$60,$38,$68,$40,$20,$00,$00
  .byte $98,$98,$78,$78,$58,$58,$38,$38,$20,$00
  .byte $94,$94,$70,$70,$70,$4C,$4C,$28,$28,$00
LD_B:
  .byte $B8,$B8,$97,$9C,$7D,$78,$76,$58,$5D,$3D
  .byte $B8,$98,$70,$88,$60,$98,$68,$40,$00,$00
  .byte $B8,$B8,$98,$98,$78,$78,$58,$58,$38,$00
  .byte $B8,$B8,$94,$94,$94,$70,$70,$4C,$4C,$00
LD_BRK:
  .byte $01,$00,$00,$01,$00,$01,$00,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$00,$01,$00,$01,$00,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
SC_NTL:
  .byte <SC0_NT,<SC1_NT,<SC2_NT,<SC3_NT
SC_NTH:
  .byte >SC0_NT,>SC1_NT,>SC2_NT,>SC3_NT
SC_COL:
  .byte 6,14,11,8                ; colour of the planks and ladders
SC_KIND:
  .byte 0,1,2,3
SC_GOAL:
  .byte 32,32,32,0               ; Gus up there: done (0 = the windows)
SC_GX:
  .byte 16,224,16,120
SC_GY:
  .byte 32,32,32,40
SC_SX:
  .byte 24,24,24,120
BR_X:
  .byte 32,176,24,232,16,224,24,224        ; brooms: 2 a screen
BR_Y:
  .byte 150,95,112,104,152,120,112,76
IT_X:
  .byte 224,208,128,192,16,240,120,120        ; things of Gus: 2 a screen
IT_Y:
  .byte 117,54,136,64,88,56,148,76
WIN_C:
  .byte 6,25,6,25,6,25,8,23               ; the windows of the lantern
WIN_Y:
  .byte 148,148,112,112,76,76,40,40
LIFT_X:
  .byte 56,168
SCN_LO:
  .byte <SCN0,<SCN1,<SCN2,<SCN3
SCN_HI:
  .byte >SCN0,>SCN1,>SCN2,>SCN3
SCN0:     .byte "THE PIER",0
SCN1:     .byte "THE CLIFF",0
SCN2:     .byte "THE STAIRS",0
SCN3:     .byte "THE LANTERN",0

; big letters of the title
BIG_TOP:
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00,$00,$18,$18,$18,$18,$18,$18,$1F,$00,$18,$18,$18,$18,$18,$18,$F8
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18,$00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0,$00,$18,$18,$18,$18,$19,$19,$1E,$00,$18,$18,$60,$60,$80,$80,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
BIG_BOT:
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00,$01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00,$1F,$18,$18,$18,$18,$18,$18,$00,$F8,$18,$18,$18,$18,$18,$18,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00,$1E,$19,$19,$18,$18,$18,$18,$00,$00,$80,$80,$60,$60,$18,$18,$00
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00,$1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
TXT_BIG:
  .byte 3,6,200,201,202,203,204,205,206,207,208,209,206,207,210,211,212,213,214,215,216,217,0
  .byte 4,6,228,229,230,231,232,233,234,235,236,237,234,235,238,239,240,241,242,243,244,245,0
  .byte 6,10,218,219,216,217,216,217,220,221,216,217,222,223,0
  .byte 7,10,246,247,244,245,244,245,248,249,244,245,250,251,0
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
  .byte $27,$09,$22,$03,$27,$06,$2A,$06,$29,$09,$27,$03,$25,$06,$22,$06,$23,$09,$25,$03,$27,$06,$29,$06,$2A,$0C,$29,$0C,$27,$09,$22,$03
  .byte $27,$06,$2A,$06,$2C,$09,$2A,$03,$29,$06,$25,$06,$27,$09,$25,$03,$22,$06,$29,$06,$27,$18,$2A,$09,$2C,$03,$2E,$06,$2A,$06,$2C,$09
  .byte $2A,$03,$29,$06,$25,$06,$2A,$09,$29,$03,$27,$06,$23,$06,$22,$0C,$25,$0C,$27,$09,$29,$03,$2A,$06,$27,$06,$29,$09,$25,$03,$22,$06
  .byte $25,$06,$27,$18,$FF
SG0_1:
  .byte $1E,$18,$20,$18,$1E,$18,$22,$18,$1E,$18,$1D,$18,$1E,$0C,$1D,$0C,$1E,$18,$22,$18,$23,$18,$22,$18,$1E,$18,$1E,$18,$1D,$18,$1E,$18
  .byte $FF
SG0_2:
  .byte $0F,$0C,$0A,$0C,$0D,$0C,$08,$0C,$0B,$0C,$06,$0C,$0A,$0C,$0A,$0C,$0F,$0C,$0A,$0C,$0D,$0C,$0D,$0C,$06,$0C,$0A,$0C,$0F,$18,$06,$0C
  .byte $0D,$0C,$0D,$0C,$08,$0C,$0B,$0C,$06,$0C,$0A,$0C,$0A,$0C,$0F,$0C,$0A,$0C,$0A,$0C,$11,$0C,$0F,$18,$FF
SG0_3:
  .byte $01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C
  .byte $03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06,$03,$06,$02,$0C,$03,$0C,$01,$0C,$03,$06
  .byte $03,$06,$02,$0C,$03,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG1_0:
  .byte $22,$06,$27,$06,$2A,$06,$2E,$0C,$2C,$06,$2A,$06,$29,$06,$25,$06,$27,$18,$FF
SG1_1:
  .byte $1E,$18,$1D,$18,$1E,$18,$FF
SG1_2:
  .byte $0F,$0C,$0A,$0C,$0D,$0C,$0A,$0C,$0F,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$04,$18,$FF
SG2_0:
  .byte $27,$04,$2A,$04,$2E,$04,$33,$0C,$31,$04,$2E,$04,$2A,$04,$2C,$04,$2E,$18,$00,$04,$33,$18,$FF
SG2_1:
  .byte $1E,$10,$22,$10,$25,$18,$1E,$0C,$22,$18,$FF
SG2_2:
  .byte $0F,$10,$0A,$10,$06,$18,$0A,$0C,$0F,$18,$FF
SG2_3:
  .byte $02,$04,$02,$04,$02,$04,$01,$0C,$03,$04,$03,$04,$03,$04,$03,$04,$01,$18,$03,$04,$04,$18,$FF
SG3_0:
  .byte $27,$06,$2A,$06,$2E,$06,$33,$12,$31,$06,$2F,$06,$2E,$06,$2C,$06,$2A,$06,$29,$06,$2A,$06,$2C,$06,$2E,$0C,$33,$0C,$36,$06,$35,$06
  .byte $33,$24,$FF
SG3_1:
  .byte $22,$18,$23,$18,$25,$18,$22,$18,$2A,$18,$22,$18,$FF
SG3_2:
  .byte $0F,$18,$08,$18,$0D,$18,$06,$18,$0A,$18,$0F,$18,$FF
SG3_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$04,$18,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$BD,$BD,$78,$78,$9C,$89,$7A,$6E,$64,$5C,$55,$4F,$4A,$45,$28,$28,$28,$1E,$1E,$1E,$1E,$2D,$26,$2F,$28,$32,$2A,$36,$2C,$3A,$2F
  .byte $3F,$32,$44,$35,$23,$27,$2B,$32,$3A,$45,$18,$18,$20,$20,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$28,$28,$28,$20,$20,$20,$18,$18,$18,$18,$18
  .byte $47,$47,$5F,$5F,$5F,$5F,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$68,$6D
  .byte $71,$76,$6E,$72,$77,$7C,$90,$96,$9D,$A3,$98,$9E,$A5,$AC,$C8,$D1,$D9,$E2,$D2,$DB,$E4,$EE,$15,$21,$2D,$3A,$24,$30,$3D,$4A,$81,$91
  .byte $A1,$B3,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$EF,$EF,$EF,$EF,$EF,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$06,$05,$06,$05,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$0B,$0A,$09,$0B,$09,$07,$05,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08
  .byte $08,$08,$07,$07,$08,$07,$06,$06,$05,$04,$0C,$0A,$0C,$09,$0B,$09,$06,$04,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0A,$08,$06,$04
  .byte $0C,$0A,$0C,$09,$07,$04,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0D,$0D
  .byte $0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05
  .byte $05,$05,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A,$0A
  .byte $0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$03,$05,$0F,$16,$24,$2A,$32,$40,$46,$5E,$82,$AA,$AD
WH_LEN:
  .byte $00,$02,$02,$0A,$07,$0E,$06,$08,$0E,$06,$18,$24,$28,$03,$13
W_STEP = 1
W_CLIMB = 2
W_JUMP = 3
W_OVER100 = 4
W_SQUAWK = 5
W_SWEEP = 6
W_HIT = 7
W_ITEM = 8
W_SHUT = 9
W_EXTRA = 10
W_DOWN = 11
W_OVER = 12
W_KEY = 13
W_SIGN = 14

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0A,$08,$06,$04,$02,$00,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01
EX_NP:
  .byte $00,$14,$15,$16,$17,$18,$19,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13
EX_VC:
  .byte $00,$09,$07,$05,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$B6,$B6,$B6,$B6,$B6,$B6,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$02,$02,$02,$02,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$07
EX_LEN:
  .byte $00,$06,$0E
S_THUD = 1
S_CRASH = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <192,>192, <BIG_TOP,>BIG_TOP
  .byte 1, $20,$47, <192,>192, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$66, <192,>192, $B1,0
  .byte 2, $20,$67, <192,>192, $A1,0
  .byte 1, $00,$43, <336,>336, <TILEP,>TILEP
  .byte 1, $00,$63, <336,>336, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <192,>192, <BIG_TOP,>BIG_TOP
  .byte 1, $20,$4F, <192,>192, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$6E, <192,>192, $B1,0
  .byte 2, $20,$6F, <192,>192, $A1,0
  .byte 1, $00,$4B, <336,>336, <TILEP,>TILEP
  .byte 1, $00,$6B, <336,>336, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <192,>192, <BIG_TOP,>BIG_TOP
  .byte 1, $20,$57, <192,>192, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$76, <192,>192, $B1,0
  .byte 2, $20,$77, <192,>192, $A1,0
  .byte 1, $00,$53, <336,>336, <TILEP,>TILEP
  .byte 1, $00,$73, <336,>336, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
