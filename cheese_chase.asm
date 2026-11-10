;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   CHEESE CHASE  -  an original digging puzzle platformer     ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Squeak the mouse steals the cheese wheels of a dairy:    ;
;     floors of planks and stone, ladders, milk pipes to hang  ;
;     on; take every wheel, then a ladder shows up to the top  ;
;   - BUTTON 1 gnaws the planks down on the left, BUTTON 2 on  ;
;     the right: the hole closes again after 5 seconds         ;
;   - the cats chase Squeak; a cat that falls into a hole is   ;
;     stuck for a while (and drops the cheese it carries); a   ;
;     hole that closes on a cat sends it back to the top; a    ;
;     hole that closes on Squeak takes a life                  ;
;   - both buttons held for 2 s = give up (a life lost, the    ;
;     level starts again)                                      ;
;   - 16 levels, then again with faster cats; 5 lives, one     ;
;     more at every level done (9 at most); 1 or 2 players     ;
;     taking turns                                             ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 51 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at the start and at the end of a     ;
;     level; steps, gnawing, cheese, meows                     ;
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
PBLOCK      = 1
GSTATE      = $50      ; 0 playing, 1 life lost, 3 the level is done
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives and level, 4 cheese left
FIRSTT      = $53      ; 1 = first turn of the game
MX          = $54      ; Squeak: left x, top y in the level (pixels; screen y = MY + 8)
MY          = $55
MST         = $56      ; 1 = falling
MFACE       = $57      ; 0 right, 1 left
MGT         = $58      ; gnawing: frames left (0 = not gnawing)
MGX         = $59      ; the cell being gnawed
MGY         = $5A
MPOSE       = $5B      ; 0 on his feet, 1 ladder, 2 pipe, 3 falling
GIVEUP      = $5C      ; frames with both buttons held
MXC         = $5D      ; Squeak's cell (rounded), for the cats
MYC         = $5E
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
CHEESE      = $72      ; cheese wheels left in the level (carried ones too)
NCAT        = $73      ; cats in the level
LOSTN       = $74      ; lives lost (tests)
DEATHS      = $75      ; what took the last life (tests): 1 a cat, 2 a hole, 3 given up
GOD         = $76      ; tests: 1 = the cats do no harm (0 in the game)
EXITON      = $77      ; 1 = the ladder to the top is there
LEVI        = $78      ; level of the tables (0-15)
TICKS       = $79      ; frames (the holes every 4)
CSPD        = $7A      ; speed of the cats (fraction of a pixel a frame)
AX          = $7B      ; the actor being moved: left x, top y, wanted (1 up 2 down 4 left 8 right),
AY          = $7C      ;   1 = falling, 1 = moved, pose
AJ          = $7D
AST         = $7E
AMOVED      = $7F
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
APOSE       = $88
CXC         = $89      ; cell of the actor (column rounded, row)
CYC         = $8A
CC          = $8B      ; the cat being moved
TRAPN       = $8C      ; cats fallen into a hole (tests)
SHUTN       = $8D      ; cats shut in a hole (tests)
CTRAP       = $8E      ; frames a cat stays in a hole
WANT        = $8F      ; the cats: 0 a way up, 1 a way down
DL          = $90      ; distances of the way found on the left / right
DR          = $91
SQX0        = $92      ; Squeak's start (pixels)
SQY0        = $93
TAKEN       = $94      ; cheese taken (tests)
AIDONE      = $95      ; 1 = a cat has chosen its way in this frame
ACAT        = $9C      ; 1 = the actor is a cat (it stays in the holes)
CPTR        = $96      ; 2 bytes: row of the map
Q0          = $98      ; temporaries of the cells
Q1          = $99
Q2          = $9A
Q3          = $9B

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

; ---------------- the cats (5 at most) ----------------
NC         = 5
CAX        = $0200       ; left x, top y (pixels)
CAY        = $0205
CST        = $020A       ; state (K_*)
CFALL      = $020F       ; 1 = falling
CDIR       = $0214       ; the way it goes (joystick bits)
CACC       = $0219       ; fraction of the speed
CT         = $021E       ; timer
CCAR       = $0223       ; carries a cheese: cells left before it drops it (0 = none)
CFACE      = $0228       ; 0 right, 1 left
CHX        = $022D       ; the hole it is in
CHY        = $0232
CPOSE      = $0237       ; pose (as APOSE)
CSTK       = $023C       ; 1 = it could not move: a way at random next time
K_OFF      = 0
K_RUN      = 1           ; walks, climbs, falls
K_HOLE     = 3           ; stuck in a hole
K_OUT      = 4           ; climbs out of the hole
K_BACK     = 5           ; shut in a hole: back at the top soon
K_SIDE     = 6           ; steps off the hole, to the side
; ---------------- the holes (8 at most) ----------------
NH         = 8
HX         = $0250       ; cell
HY         = $0258
HT         = $0260       ; time left (4 frames a tick; 0 = no hole)
; ---------------- the hidden ladder ----------------
HLN        = $0268       ; cells
HLX        = $0270       ; 32 columns
HLY        = $0290       ; 32 rows

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
MAP        = $0800       ; 22 rows x 32 cells

; ---------------- parameters ----------------
BTN_MASK    = %00110000
HOLE_T      = 75         ; ticks of 4 frames a hole stays open (5 s)
GNAW_T      = 12         ; frames to gnaw a hole
GIVE_T      = 120        ; frames with both buttons to give up

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 51         ; fixed zone of the game in the save area
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
  STZ GOD
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
;  TITLE: the name, the buttons, the points
; ===============================================================
TITLE:
  LDX #$FF
  TXS
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

; one frame of the title: the sprites move their legs;
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
;  NEW GAME: level 1, 5 lives for every player
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
  STZ TRAPN
  STZ SHUTN
  STZ TAKEN
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #5
  STA LIVES,X
  STZ LEVEL
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his level, from the start
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

LEVEL_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the level is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_LEVEL                ; the map, Squeak and the cats at their places
  JSR CLEAR_NT
  JSR DRAW_LEVEL
  JSR DRAW_HUD
  STZ GSTATE
  JSR MSG_LEVEL
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA FIRSTT                   ; the tune at the first turn
  BEQ .ls_short
  STZ FIRSTT
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ls_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ls_t
  BRA .ls_w
.ls_short:
  LDA #90
  JSR WAIT_FRAMES
.ls_w:
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
  INC TICKS
  LDA GSTATE
  BNE .gl_ns
  JSR SQUEAK
  JSR HOLES
  JSR CATS
  JSR HITS
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
  BEQ .gl_clear
  JMP LOSE_LIFE
.gl_clear:
  JMP LEVEL_CLEAR


; ===============================================================
;  THE LEVEL IS DONE: 1500 points, a life more, the next level
; ===============================================================
LEVEL_CLEAR:
  JSR HIDE_SPRITES
  LDA #$00
  LDY #$15
  JSR ADD_PTS
  LDX CURP                     ; a life more (9 at most)
  LDA LIVES,X
  CMP #9
  BCS .lc_s
  INC LIVES,X
.lc_s:
  JSR VDP_INT_OFF
  JSR UPDATE_HUD
  JSR DRAW_STATUS
  JSR VDP_INT_ON
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
.lc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .lc_t
  LDA #20
  JSR WAIT_FRAMES
  LDA LEVEL                    ; the next level (98 at most)
  CMP #98
  BCS .lc_n
  INC LEVEL
.lc_n:
  JSR SAVE_PLAYER
  JMP LEVEL_START

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
  JMP LEVEL_START              ; the same player: the level from the start

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
  LDA #$20
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
REC_NAME:  .byte "CHEESE CHASE    "
REC_HEAD:  .byte "BEST CHEESE THIEVES",0
REC_XLBL:  .byte "LEVEL ",0


; ===============================================================
;  HUD: row 0 (scores), row 23 (lives, cheese, level)
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

; row 23: the spare lives (cols 0-7), the cheese left (12-14), LEVEL nn (22-29), the player (31)
DRAW_STATUS:
  LDX #23
  LDY #0
  JSR NT_XY
  LDX CURP                     ; the spare lives (at most 8)
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
  CPY #8
  BNE .ds_i
  LDX #23
  LDY #22
  JSR NT_XY
  LDX #0
.ds_l:
  LDA TXT_LEVELH,X
  STA VDATA
  INX
  CPX #6
  BNE .ds_l
  LDA LEVEL
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDA NPL                      ; the player at the right end with 2 players
  CMP #2
  BNE DRAW_CHEESE
  LDX #23
  LDY #31
  JSR NT_XY
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
  ; fall into DRAW_CHEESE

; row 23: a cheese and the wheels left
DRAW_CHEESE:
  LDX #23
  LDY #12
  JSR NT_XY
  LDA #T_CHEESE
  STA VDATA
  LDA CHEESE
  JSR BIN2BCD
  JMP PUT_2

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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives and level, 4 cheese left
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
  BEQ .uh_c
  JSR DRAW_STATUS
.uh_c:
  PLA
  AND #4
  BEQ .uh_r
  JSR DRAW_CHEESE
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

; PTS_L / PTS_M / PTS_H (BCD) to the player playing
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
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  THE LEVEL: map, drawing, signs
; ===============================================================
; the level LEVEL: the tables, the map, Squeak and the cats at their places, no holes
SET_LEVEL:
  LDA LEVEL
  AND #15
  STA LEVI
  TAX
  LDA TRAP_TM,X
  STA CTRAP
  LDA LEVEL                    ; the cats get faster every round of 16 levels
  LSR A
  LSR A
  LSR A
  LSR A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC CAT_SPD,X
  BCS .sl_m
  CMP #240
  BCC .sl_s
.sl_m:
  LDA #240
.sl_s:
  STA CSPD
  JSR LOAD_LEVEL
  LDA SQX0
  STA MX
  LDA SQY0
  STA MY
  STZ MST
  STZ MGT
  STZ GIVEUP
  STZ MFACE
  STZ MPOSE
  LDX #NC-1
.sl_c:
  STZ CST,X
  STZ CFALL,X
  STZ CACC,X
  STZ CCAR,X
  STZ CDIR,X
  STZ CPOSE,X
  STZ CSTK,X
  CPX NCAT
  BCS .sl_cn
  LDA #K_RUN
  STA CST,X
.sl_cn:
  DEX
  BPL .sl_c
  LDX #NH-1
.sl_h:
  STZ HT,X
  DEX
  BPL .sl_h
  STZ EXITON
  RTS

; the level LEVI into MAP: the starts of Squeak and the cats, the cells of the hidden ladder, the cheese
LOAD_LEVEL:
  LDX LEVI
  LDA LEV_LO,X
  STA PTR
  LDA LEV_HI,X
  STA PTR+1
  LDA #<MAP
  STA PTR2
  LDA #>MAP
  STA PTR2+1
  STZ CHEESE
  STZ NCAT
  STZ HLN
  STZ T2                       ; column
  STZ T3                       ; row
.ll_b:
  LDA (PTR)
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  JSR .ll_cell
  PLA
  AND #$0F
  JSR .ll_cell
  INC PTR
  BNE .ll_n
  INC PTR+1
.ll_n:
  LDA T3
  CMP #22
  BNE .ll_b
  RTS
.ll_cell:                      ; A = the cell at T2, T3
  CMP #9
  BNE .lc_c
  LDA T2                       ; Squeak
  ASL A
  ASL A
  ASL A
  STA SQX0
  LDA T3
  ASL A
  ASL A
  ASL A
  STA SQY0
  LDA #0
  BRA .lc_st
.lc_c:
  CMP #10
  BNE .lc_h
  LDX NCAT                     ; a cat
  CPX #NC
  BCS .lc_c0
  LDA T2
  ASL A
  ASL A
  ASL A
  STA CAX,X
  LDA T3
  ASL A
  ASL A
  ASL A
  STA CAY,X
  INC NCAT
.lc_c0:
  LDA #0
  BRA .lc_st
.lc_h:
  CMP #7
  BNE .lc_g
  LDX HLN                      ; the hidden ladder
  CPX #32
  BCS .lc_st
  LDA T2
  STA HLX,X
  LDA T3
  STA HLY,X
  INC HLN
  LDA #7
  BRA .lc_st
.lc_g:
  CMP #5
  BNE .lc_st
  INC CHEESE
.lc_st:
  STA (PTR2)
  INC PTR2
  BNE .lc_p
  INC PTR2+1
.lc_p:
  INC T2
  LDA T2
  CMP #32
  BNE .lc_r
  STZ T2
  INC T3
.lc_r:
  RTS

DRAW_LEVEL:
  LDY #0
.dl_r:
  PHY
  JSR DRAW_ROW
  PLY
  INY
  CPY #22
  BNE .dl_r
  RTS

; Y = row of the level (0-21): its 32 tiles on the screen row Y + 1
DRAW_ROW:
  STY T3
  TYA
  TAX
  INX
  LDY #0
  JSR NT_XY
  LDY T3
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  LDY #0
.dr_c:
  LDA (CPTR),Y
  TAX
  LDA TILE_OF,X
  STA T5
  LDA VAR_OF,X
  BEQ .dr_p
  TYA
  EOR T3
  AND #1
  CLC
  ADC T5
  STA T5
.dr_p:
  LDA T5
  STA VDATA
  INY
  CPY #32
  BNE .dr_c
  RTS

; X = column, Y = row: A = the cell (stone outside the level); keeps X and Y
; (the flags do not follow A: compare it)
GETC:
  CPX #32
  BCS .gc_s
  CPY #22
  BCS .gc_s
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  PHY
  TXA
  TAY
  LDA (CPTR),Y
  PLY
  RTS
.gc_s:
  LDA #2
  RTS

; X = column, Y = row, A = cell: into the map and on the screen (keeps X and Y)
PUTC:
  CPX #32
  BCS .pc_r
  CPY #22
  BCS .pc_r
  STA T4
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  PHY
  TXA
  TAY
  LDA T4
  STA (CPTR),Y
  PLY
  JMP DRAW_CELL
.pc_r:
  RTS

; X = column, Y = row: the tile of the cell (keeps X and Y)
DRAW_CELL:
  JSR GETC
  PHX
  PHY
  STX T2
  STY T3
  TAX
  LDA TILE_OF,X
  STA T5
  LDA VAR_OF,X
  BEQ .dc_p
  LDA T2
  EOR T3
  AND #1
  CLC
  ADC T5
  STA T5
.dc_p:
  LDX T3
  INX
  LDY T2
  JSR NT_XY
  LDA T5
  STA VDATA
  PLY
  PLX
  RTS

; X = column, Y = row, A = tile: on the screen only (keeps X and Y)
PUT_TILE:
  PHA
  PHX
  PHY
  STX T2
  TYA
  TAX
  INX
  LDY T2
  JSR NT_XY
  PLY
  PLX
  PLA
  STA VDATA
  RTS

; the sign of the level on rows 8-14: LEVEL nn, its name, PLAYER n
MSG_LEVEL:
  LDA #<TXT_SIGN
  STA TP
  LDA #>TXT_SIGN
  STA TP+1
  JSR PRINT
  LDX #9
  LDY #12
  JSR NT_XY
  LDX #0
.ml_l:
  LDA TXT_LEVELH,X
  STA VDATA
  INX
  CPX #6
  BNE .ml_l
  LDA LEVEL
  INC A
  JSR PUT_NUM
  LDX #11
  LDY #8
  JSR NT_XY
  LDA LEVI
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #16
.ml_n:
  LDA LEV_NAME,X
  STA VDATA
  INX
  DEY
  BNE .ml_n
  LDA NPL
  CMP #2
  BNE .ml_r
  LDX #13
  LDY #12
  JSR NT_XY
  LDX #0
.ml_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .ml_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ml_r:
  RTS

MSG_CLEAR:                     ; the level again on rows 8-14
  LDY #7
.mc_r:
  PHY
  JSR DRAW_ROW
  PLY
  INY
  CPY #14
  BNE .mc_r
  RTS


; ===============================================================
;  SQUEAK
; ===============================================================
SQUEAK:
  LDA JOYC                     ; both buttons held: give up
  AND #BTN_MASK
  CMP #BTN_MASK
  BNE .sq_g0
  INC GIVEUP
  LDA GIVEUP
  CMP #GIVE_T
  BCC .sq_gn
  LDA #3
  JMP DIES
.sq_g0:
  STZ GIVEUP
.sq_gn:
  LDA MGT                      ; gnawing: the planks go away in two steps
  BEQ .sq_m
  DEC MGT
  LDA MGT
  CMP #GNAW_T/2
  BNE .sq_g1
  LDX MGX
  LDY MGY
  LDA #T_GNAW2
  JMP PUT_TILE
.sq_g1:
  CMP #0
  BNE .sq_r
  JMP OPEN_HOLE
.sq_r:
  RTS
.sq_m:
  LDA MST
  BNE .sq_mv
  LDA MY
  AND #7
  BNE .sq_mv
  LDA JOYC
  AND #BTN_MASK
  BEQ .sq_mv
  CMP #BTN_MASK
  BEQ .sq_mv
  JSR TRY_GNAW
  BCC .sq_mv
  RTS
.sq_mv:
  LDA MX
  STA AX
  LDA MY
  STA AY
  LDA MST
  STA AST
  LDA JOYC
  AND #15
  STA AJ
  STZ ACAT
  JSR MOVE
  LDA AX
  STA MX
  LDA AY
  STA MY
  LDA AST
  STA MST
  LDA APOSE
  STA MPOSE
  LDA AJ                       ; facing
  AND #12
  BEQ .sq_f
  LDX #0
  AND #4
  BEQ .sq_fr
  INX
.sq_fr:
  STX MFACE
.sq_f:
  LDA AMOVED                   ; little steps
  BEQ .sq_c
  LDA MPOSE
  CMP #3
  BEQ .sq_c
  LDA MX
  CLC
  ADC MY
  AND #7
  BNE .sq_c
  LDX #0
  LDA MX
  BPL .sq_sx
  INX
.sq_sx:
  LDA WH_ID,X
  BNE .sq_c
  LDA #W_STEP
  LDY MPOSE
  BEQ .sq_sw
  LDA #W_CLIMB
.sq_sw:
  JSR SFX_WHISTLE
.sq_c:
  JSR TAKE_CHEESE
  LDA EXITON                   ; at the top with every cheese: the level is done
  BEQ .sq_e
  LDA MY
  BNE .sq_e
  LDA MST
  BNE .sq_e
  LDA GSTATE
  BNE .sq_e
  LDA #3
  STA GSTATE
  LDA #30
  STA GT
.sq_e:
  RTS

; a button: gnaw the planks down on that side (C = 1 if it starts)
TRY_GNAW:
  LDX #$FF                     ; button 1 left, button 2 right
  AND #%00010000
  BNE .tg_s
  LDX #$01
.tg_s:
  STX Q3
  LDA MX
  STA AX
  LDA MY
  STA AY
  JSR ACELL
  LDX CXC
  LDY CYC
  JSR GETC
  CMP #4                       ; not from a pipe
  BEQ .tg_no
  JSR SUPP                     ; on his feet
  BCC .tg_no
  LDA CXC
  CLC
  ADC Q3
  TAX
  CPX #32
  BCS .tg_no
  JSR GETC                     ; free above the planks
  CMP #0
  BEQ .tg_a
  CMP #7
  BNE .tg_no
.tg_a:
  INY
  JSR GETC
  CMP #1                       ; planks (not stone, not the false planks)
  BNE .tg_no
  STX MGX
  STY MGY
  DEY                          ; no cat right there
  JSR CAT_AT
  BCS .tg_no
  LDX #NH-1                    ; room for one more hole
.tg_h:
  LDA HT,X
  BEQ .tg_go
  DEX
  BPL .tg_h
.tg_no:
  CLC
  RTS
.tg_go:
  LDA CXC
  ASL A
  ASL A
  ASL A
  STA MX
  STZ MPOSE
  LDA Q3
  ROL A                        ; (bit 7 = left)
  LDA #0
  ROL A
  STA MFACE
  LDA #GNAW_T
  STA MGT
  LDX MGX
  LDY MGY
  LDA #T_GNAW1
  JSR PUT_TILE
  LDA #S_GNAW
  LDY MX
  JSR BOOM_AT
  SEC
  RTS

; X = column, Y = row: C = 1 if a cat is on that cell (keeps X and Y)
CAT_AT:
  STX Q0
  STY Q1
  PHX
  LDA Q0
  ASL A
  ASL A
  ASL A
  STA Q0
  LDA Q1
  ASL A
  ASL A
  ASL A
  STA Q1
  LDX NCAT
.ca_l:
  DEX
  BMI .ca_no
  LDA CST,X
  CMP #K_BACK
  BEQ .ca_l
  LDA CAX,X
  SEC
  SBC Q0
  BCS .ca_x
  EOR #$FF
  INC A
.ca_x:
  CMP #8
  BCS .ca_l
  LDA CAY,X
  SEC
  SBC Q1
  BCS .ca_y
  EOR #$FF
  INC A
.ca_y:
  CMP #8
  BCS .ca_l
  PLX
  SEC
  RTS
.ca_no:
  PLX
  CLC
  RTS

; the planks MGX, MGY are gone: a hole
OPEN_HOLE:
  LDX #NH-1
.oh_l:
  LDA HT,X
  BEQ .oh_f
  DEX
  BPL .oh_l
  LDX MGX                      ; (no room: the planks stay)
  LDY MGY
  JMP DRAW_CELL
.oh_f:
  LDA MGX
  STA HX,X
  LDA MGY
  STA HY,X
  LDA #HOLE_T
  STA HT,X
  LDX MGX
  LDY MGY
  LDA #8
  JMP PUTC

; a cheese where Squeak is: taken; the last one opens the way out
TAKE_CHEESE:
  LDA MX
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  TAX
  LDA MY
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  TAY
  JSR GETC
  CMP #5
  BNE .tc_r
  LDA #0
  JSR PUTC
  INC TAKEN
  LDA #$50
  LDY #$02
  JSR ADD_PTS
  LDA #W_CHEESE
  LDX #2
  JSR SFX_WHISTLE
  DEC CHEESE
  LDA #4
  TSB HUDD
  LDA CHEESE
  BEQ OPEN_EXIT
.tc_r:
  RTS

; the hidden ladder shows up
OPEN_EXIT:
  LDA #1
  STA EXITON
  LDX #0
.oe_l:
  CPX HLN
  BEQ .oe_s
  PHX
  LDA HLY,X
  TAY
  LDA HLX,X
  TAX
  LDA #3
  JSR PUTC
  PLX
  INX
  BRA .oe_l
.oe_s:
  LDA #W_EXIT
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  THE HOLES: open for 5 seconds, then the planks grow back
; ===============================================================
HOLES:
  LDA TICKS
  AND #3
  BNE .ho_r
  LDX #NH-1
.ho_l:
  LDA HT,X
  BEQ .ho_n
  DEC HT,X
  LDA HT,X
  CMP #12
  BNE .ho_1
  LDA #T_GNAW2
  BRA .ho_t
.ho_1:
  CMP #6
  BNE .ho_2
  LDA #T_GNAW1
.ho_t:
  PHX
  PHA
  LDA HY,X
  TAY
  LDA HX,X
  TAX
  PLA
  JSR PUT_TILE
  PLX
  BRA .ho_n
.ho_2:
  CMP #0
  BNE .ho_n
  JSR SHUT_HOLE
.ho_n:
  DEX
  BPL .ho_l
.ho_r:
  RTS

; X = hole: the planks are back; Squeak inside loses a life, a cat inside goes back to the top
SHUT_HOLE:
  PHX
  LDA HX,X
  STA Q0
  ASL A
  ASL A
  ASL A
  STA Q2
  LDA HY,X
  STA Q1
  ASL A
  ASL A
  ASL A
  STA Q3
  LDX Q0
  LDY Q1
  LDA #1
  JSR PUTC
  LDA #W_SHUT
  LDX #2
  JSR SFX_WHISTLE
  LDA MX
  JSR ABS_X
  CMP #8
  BCS .sh_c
  LDA MY
  JSR ABS_Y
  CMP #8
  BCS .sh_c
  LDA #2
  JSR DIES
.sh_c:
  LDX #0
.sh_l:
  CPX NCAT
  BEQ .sh_e
  LDA CST,X
  CMP #K_RUN
  BEQ .sh_t
  CMP #K_HOLE
  BEQ .sh_t
  CMP #K_OUT
  BEQ .sh_t
  CMP #K_SIDE
  BNE .sh_n
.sh_t:
  LDA CAX,X
  JSR ABS_X
  CMP #8
  BCS .sh_n
  LDA CAY,X
  JSR ABS_Y
  CMP #8
  BCS .sh_n
  LDA #K_BACK
  STA CST,X
  LDA #45
  STA CT,X
  INC SHUTN
  PHX
  LDA #$75
  LDY #0
  JSR ADD_PTS
  PLX
.sh_n:
  INX
  BRA .sh_l
.sh_e:
  PLX
  RTS

ABS_X:                         ; A = |A - Q2|
  SEC
  SBC Q2
  BCS .ax_r
  EOR #$FF
  INC A
.ax_r:
  RTS
ABS_Y:                         ; A = |A - Q3|
  SEC
  SBC Q3
  BCS .ay_r
  EOR #$FF
  INC A
.ay_r:
  RTS


; ===============================================================
;  MOVING: Squeak and the cats walk, climb, hang and fall alike
; ===============================================================
; one step of the actor AX, AY (AST = 1 falling), AJ = the way wanted (1 up 2 down 4 left 8 right);
; out: APOSE (0 on its feet, 1 ladder, 2 pipe, 3 falling), AMOVED
MOVE:
  STZ AMOVED
  LDA AST
  BEQ .mv_n
  LDA #3                       ; falling: 2 pixels, until something holds it
  STA APOSE
  INC AY
  INC AY
  INC AMOVED
  LDA AY
  AND #7
  BNE .mv_r
  JSR ACELL
  LDX CXC
  LDY CYC
  JSR HOLDS
  BCC .mv_r
  STZ AST
  JSR APOSE_SET
.mv_r:
  RTS
.mv_n:
  LDA AY
  AND #7
  BEQ .mv_al
  JMP .mv_mid
.mv_al:
  JSR ACELL
  LDX CXC
  LDY CYC
  JSR HOLDS
  BCS .mv_s
  LDA CXC                      ; nothing holds it: it falls, straight down its column
  ASL A
  ASL A
  ASL A
  STA AX
  LDA #1
  STA AST
  LDA #3
  STA APOSE
  INC AY
  INC AY
  INC AMOVED
  RTS
.mv_s:
  JSR APOSE_SET
  LDA AJ                       ; up a ladder
  AND #1
  BEQ .mv_dn
  LDX CXC
  LDY CYC
  JSR GETC
  CMP #3
  BNE .mv_dn
  DEY
  JSR GETC
  JSR IS_SOLID
  BCS .mv_dn
  JSR ALIGNX
  BCC .mv_d1
  DEC AY
.mv_v:
  LDA #1
  STA APOSE
.mv_d1:
  INC AMOVED
  RTS
.mv_dn:
  LDA AJ                       ; down a ladder, or off a pipe
  AND #2
  BEQ .mv_h
  LDX CXC
  LDY CYC
  INY
  JSR GETC
  DEY
  STA Q2
  JSR IS_SOLID
  BCS .mv_h
  JSR GETC
  CMP #4
  BEQ .mv_drop
  CMP #3
  BEQ .mv_go
  LDA Q2
  CMP #3
  BNE .mv_h
.mv_go:
  JSR ALIGNX
  BCC .mv_d1
  INC AY
  BRA .mv_v
.mv_drop:
  JSR ALIGNX
  BCC .mv_d1
  LDA #1
  STA AST
  INC AY
  INC AY
  LDA #3
  STA APOSE
  BRA .mv_d1
.mv_h:
  LDA AJ                       ; left
  AND #4
  BEQ .mv_rt
  LDA AX
  AND #7
  BNE .mv_l1
  LDA AX
  BEQ .mv_x
  LSR A
  LSR A
  LSR A
  DEC A
  TAX
  LDY CYC
  JSR GETC
  JSR IS_SOLID
  BCS .mv_x
.mv_l1:
  DEC AX
  INC AMOVED
  RTS
.mv_rt:
  LDA AJ                       ; right
  AND #8
  BEQ .mv_x
  LDA AX
  AND #7
  BNE .mv_r1
  LDA AX
  CMP #248
  BCS .mv_x
  LSR A
  LSR A
  LSR A
  INC A
  TAX
  LDY CYC
  JSR GETC
  JSR IS_SOLID
  BCS .mv_x
.mv_r1:
  INC AX
  INC AMOVED
.mv_x:
  RTS
.mv_mid:                       ; between two rows: on a ladder
  LDA #1
  STA APOSE
  LDA AJ
  AND #1
  BEQ .mm_d
  DEC AY
  INC AMOVED
  RTS
.mm_d:
  LDA AJ
  AND #2
  BEQ .mm_h
  LDA AX
  LSR A
  LSR A
  LSR A
  TAX
  LDA AY
  LSR A
  LSR A
  LSR A
  INC A
  TAY
  JSR GETC
  JSR IS_SOLID
  BCS .mm_x
  INC AY
  INC AMOVED
  RTS
.mm_h:
  LDA AJ                       ; left or right: first to the nearest row
  AND #12
  BEQ .mm_x
  LDA AY
  AND #7
  CMP #4
  BCC .mm_up
  INC AY
  INC AMOVED
  RTS
.mm_up:
  DEC AY
  INC AMOVED
.mm_x:
  RTS

; X = column, Y = row: C = 1 if the actor stops there: something holds it, or a cat in a hole
; (a cat stays stuck in a hole, Squeak falls through it)
HOLDS:
  JSR SUPP
  BCS .hd_r
  LDA ACAT
  BEQ .hd_n
  JSR GETC
  CMP #8
  BEQ .hd_y
.hd_n:
  CLC
.hd_r:
  RTS
.hd_y:
  SEC
  RTS

; CXC = column of the actor (rounded), CYC = its row
ACELL:
  LDA AX
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA CXC
  LDA AY
  LSR A
  LSR A
  LSR A
  STA CYC
  RTS

; a step toward the column CXC: C = 1 if already there
ALIGNX:
  LDA CXC
  ASL A
  ASL A
  ASL A
  CMP AX
  BEQ .al_y
  BCS .al_r
  DEC AX
  CLC
  RTS
.al_r:
  INC AX
  CLC
  RTS
.al_y:
  SEC
  RTS

APOSE_SET:
  LDX CXC
  LDY CYC
  JSR GETC
  LDX #1
  CMP #3
  BEQ .ap_s
  LDX #2
  CMP #4
  BEQ .ap_s
  LDX #0
.ap_s:
  STX APOSE
  RTS

IS_SOLID:                      ; A = cell: C = 1 for planks and stone
  CMP #1
  BEQ .is_y
  CMP #2
  BEQ .is_y
  CLC
  RTS
.is_y:
  SEC
  RTS

; X = column, Y = row: C = 1 if something holds an actor there (keeps X and Y):
; a ladder or a pipe, or below planks, stone, a ladder or a cat stuck in a hole
SUPP:
  JSR GETC
  CMP #3
  BEQ .su_y
  CMP #4
  BEQ .su_y
  INY
  JSR GETC
  DEY
  CMP #1
  BEQ .su_y
  CMP #2
  BEQ .su_y
  CMP #3
  BEQ .su_y
  CMP #8                       ; a hole below: maybe a cat stuck in it
  BEQ CAT_BELOW
  CLC
  RTS
.su_y:
  SEC
  RTS

; X = column, Y = row: C = 1 if a cat is stuck in the cell below (keeps X and Y)
CAT_BELOW:
  STX Q0
  STY Q1
  INC Q1
  PHX
  LDX NCAT
.cb_l:
  DEX
  BMI .cb_no
  LDA CST,X
  CMP #K_HOLE
  BNE .cb_l
  LDA CHX,X
  CMP Q0
  BNE .cb_l
  LDA CHY,X
  CMP Q1
  BNE .cb_l
  PLX
  SEC
  RTS
.cb_no:
  PLX
  CLC
  RTS

; X = column, Y = row: C = 1 if a ladder goes up from here (keeps X and Y)
CAN_UP:
  JSR GETC
  CMP #3
  BNE .cu_no
  CPY #0
  BEQ .cu_no
  DEY
  JSR GETC
  INY
  JSR IS_SOLID
  BCS .cu_no
  SEC
  RTS
.cu_no:
  CLC
  RTS

; X = column, Y = row: C = 1 if there is a way down from here (keeps X and Y)
CAN_DN:
  INY
  JSR GETC
  DEY
  STA Q2
  JSR IS_SOLID
  BCS .cd_no
  JSR GETC
  CMP #3
  BEQ .cd_y
  CMP #4
  BEQ .cd_y
  LDA Q2
  CMP #3
  BEQ .cd_y
.cd_no:
  CLC
  RTS
.cd_y:
  SEC
  RTS


; ===============================================================
;  THE CATS
; ===============================================================
CATS:
  LDA MX                       ; Squeak's cell
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA MXC
  LDA MY
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA MYC
  STZ AIDONE
  LDX #0
.ct_l:
  CPX NCAT
  BEQ .ct_r
  STX CC
  JSR CAT_ONE
  LDX CC
  INX
  BRA .ct_l
.ct_r:
  RTS

; X = cat
CAT_ONE:
  LDA CST,X
  CMP #K_RUN
  BNE .co_1
  JMP CAT_RUN
.co_1:
  CMP #K_HOLE
  BEQ .co_h
  CMP #K_OUT
  BEQ .co_o
  CMP #K_SIDE
  BEQ .co_s
  CMP #K_BACK
  BEQ .co_b
  RTS
.co_h:                         ; stuck in the hole for a while
  DEC CT,X
  BNE .co_r
  LDA #K_OUT
  STA CST,X
.co_r:
  RTS
.co_o:                         ; climbing out
  JSR CAT_TICK
  BCC .co_r
  DEC CAY,X
  LDA CAY,X
  AND #7
  BNE .co_r
  JSR SIDE_WAY                 ; on top: a step to the side
  LDX CC
  CMP #0
  BEQ .co_run
  STA CDIR,X
  LDA #8
  STA CT,X
  LDA #K_SIDE
  STA CST,X
  RTS
.co_run:
  LDA #K_RUN
  STA CST,X
  RTS
.co_s:                         ; the step to the side
  JSR CAT_TICK
  BCC .co_r
  LDA CDIR,X
  AND #4
  BEQ .co_sr
  DEC CAX,X
  LDA #1
  STA CFACE,X
  BRA .co_sd
.co_sr:
  INC CAX,X
  STZ CFACE,X
.co_sd:
  DEC CT,X
  BNE .co_r
  LDA #K_RUN
  STA CST,X
  RTS
.co_b:                         ; shut in a hole: back at the top
  DEC CT,X
  BNE .co_r
  JMP CAT_TOP

; X = cat: C = 1 if it moves in this frame
CAT_TICK:
  LDA CACC,X
  CLC
  ADC CSPD
  STA CACC,X
  RTS

CAT_RUN:
  JSR CAT_TICK
  BCS .cr_go
  RTS
.cr_go:
  LDA CAX,X
  STA AX
  LDA CAY,X
  STA AY
  LDA CFALL,X
  STA AST
  LDA CDIR,X
  STA AJ
  LDA AST                      ; a choice at every cell
  BNE .cr_mv
  LDA AX
  ORA AY
  AND #7
  BNE .cr_mv
  LDA AIDONE                   ; one choice a frame (the others wait)
  BEQ .cr_one
  RTS
.cr_one:
  INC AIDONE
  JSR ACELL
  LDX CXC
  LDY CYC
  JSR GETC
  CMP #8                       ; in a hole: stuck
  BNE .cr_ch
  JMP TRAP_CAT
.cr_ch:
  LDX CC                       ; with a cheese: dropped after a while, where it stands
  LDY CCAR,X
  BEQ .cr_tk
  CPY #1
  BEQ .cr_dp
  DEC CCAR,X
  BRA .cr_ai
.cr_dp:
  CMP #0
  BNE .cr_ai
  LDX CXC
  LDY CYC
  JSR SUPP
  BCC .cr_ai
  LDA #5
  JSR PUTC
  LDX CC
  STZ CCAR,X
  BRA .cr_ai
.cr_tk:
  CMP #5                       ; a cheese: it may take it
  BNE .cr_ai
  LDA GOD                      ; (tests: GOD bit 1 = the cats take no cheese)
  AND #2
  BNE .cr_ai
  JSR NEXT_RND
  AND #3
  BNE .cr_ai
  LDA RND                      ; it keeps it for 20-51 cells
  AND #31
  CLC
  ADC #20
  LDX CC
  STA CCAR,X
  LDX CXC
  LDY CYC
  LDA #0
  JSR PUTC
.cr_ai:
  JSR CAT_AI
  LDX CC
  LDA AJ
  STA CDIR,X
.cr_mv:
  LDA #1
  STA ACAT
  JSR MOVE
  LDX CC
  LDA AX
  STA CAX,X
  LDA AY
  STA CAY,X
  LDA AST
  STA CFALL,X
  LDA APOSE
  STA CPOSE,X
  LDA AMOVED                   ; it could not go: something else next time
  BNE .cr_m
  LDA #1
  STA CSTK,X
.cr_m:
  LDA AJ
  AND #12
  BEQ .cr_r
  LDY #0
  AND #4
  BEQ .cr_f
  INY
.cr_f:
  TYA
  STA CFACE,X
.cr_r:
  RTS

; the cat CC has fallen into the hole at CXC, CYC
TRAP_CAT:
  LDX CC
  LDA #K_HOLE
  STA CST,X
  LDA CXC
  STA CHX,X
  ASL A
  ASL A
  ASL A
  STA CAX,X
  LDA CYC
  STA CHY,X
  ASL A
  ASL A
  ASL A
  STA CAY,X
  STZ CFALL,X
  LDA CTRAP
  STA CT,X
  LDA CCAR,X                   ; it drops its cheese above the hole
  BEQ .tp_p
  LDX CXC
  LDY CYC
  DEY
  JSR GETC
  CMP #0
  BNE .tp_p
  LDA #5
  JSR PUTC
  LDX CC
  STZ CCAR,X
.tp_p:
  INC TRAPN
  LDA #$75
  LDY #0
  JSR ADD_PTS
  LDA #W_MEOW
  LDX #2
  JMP SFX_WHISTLE

; X = cat out of its hole: A = the side to step to (4 left, 8 right, 0 none), toward Squeak first
SIDE_WAY:
  LDA CHY,X
  DEC A
  STA Q1
  LDA CHX,X
  STA Q0
  LDA MXC
  CMP Q0
  BCC .sw_lf
  JSR .sw_r
  BNE .sw_e
  JMP .sw_l
.sw_lf:
  JSR .sw_l
  BNE .sw_e
  JMP .sw_r
.sw_e:
  RTS
.sw_r:
  LDX Q0
  INX
  LDY Q1
  JSR GETC
  JSR IS_SOLID
  BCS .sw_no
  LDA #8
  RTS
.sw_l:
  LDX Q0
  DEX
  LDY Q1
  JSR GETC
  JSR IS_SOLID
  BCS .sw_no
  LDA #4
  RTS
.sw_no:
  LDA #0
  RTS

; the cat CC comes back on the top row, on an empty cell away from Squeak
CAT_TOP:
  JSR NEXT_RND
  AND #31
  STA Q0
  LDA #32
  STA Q1
.tt_l:
  LDX Q0
  LDY #0
  JSR GETC
  CMP #0
  BNE .tt_n
  LDA Q0
  SEC
  SBC MXC
  BCS .tt_a
  EOR #$FF
  INC A
.tt_a:
  CMP #5
  BCC .tt_n
  LDX CC
  LDA Q0
  ASL A
  ASL A
  ASL A
  STA CAX,X
  STZ CAY,X
  STZ CFALL,X
  STZ CDIR,X
  LDA #K_RUN
  STA CST,X
  RTS
.tt_n:
  LDA Q0
  INC A
  AND #31
  STA Q0
  DEC Q1
  BNE .tt_l
  LDX CC                       ; no room now: later
  LDA #10
  STA CT,X
  RTS

; the cat CC at the cell CXC, CYC: AJ = the way to Squeak
CAT_AI:
  LDX CC
  LDA CSTK,X                   ; stuck last time, or now and then: a way at random
  BEQ .ai_0
  STZ CSTK,X
  BRA .ai_rnd
.ai_0:
  JSR NEXT_RND
  AND #31
  BNE .ai_1
.ai_rnd:
  JSR NEXT_RND
  AND #3
  TAX
  LDA DIRBIT,X
  STA AJ
  RTS
.ai_1:
  LDA MYC
  CMP CYC
  BNE .ai_v
  JMP .ai_h                    ; on Squeak's row: straight to him
.ai_v:
  BCS .ai_dn
  LDX CXC                      ; Squeak is higher: a ladder up, here or the nearest one
  LDY CYC
  JSR CAN_UP
  BCC .ai_su
  LDA #1
  STA AJ
  RTS
.ai_su:
  STZ WANT
  JSR SCAN
  BCC .ai_h
  STA AJ
  RTS
.ai_dn:
  LDX CXC                      ; Squeak is lower: a way down, here or the nearest one
  LDY CYC
  JSR CAN_DN
  BCC .ai_sd
  LDA #2
  STA AJ
  RTS
.ai_sd:
  LDA #1
  STA WANT
  JSR SCAN
  BCC .ai_h
  STA AJ
  RTS
.ai_h:
  LDA MXC                      ; toward Squeak's column
  CMP CXC
  BEQ .ai_rnd
  LDA #8
  BCS .ai_hs
  LDA #4
.ai_hs:
  STA AJ
  RTS

; the nearest column on the row CYC, left and right of CXC, with a way up (WANT = 0) or down (WANT = 1):
; C = 1 and A = 4 (left) or 8 (right)
SCAN:
  LDA #$FF
  STA DL
  STA DR
  LDX CXC
  LDY CYC
.sn_l:
  DEX
  CPX #32
  BCS .sn_r0
  JSR GETC
  JSR IS_SOLID
  BCS .sn_r0
  JSR SCAN_CELL
  CMP #1
  BEQ .sn_lf
  CMP #2
  BEQ .sn_r0
  BRA .sn_l
.sn_lf:
  STX Q0
  LDA CXC
  SEC
  SBC Q0
  STA DL
.sn_r0:
  LDX CXC
.sn_r:
  INX
  CPX #32
  BCS .sn_d
  JSR GETC
  JSR IS_SOLID
  BCS .sn_d
  JSR SCAN_CELL
  CMP #1
  BEQ .sn_rf
  CMP #2
  BEQ .sn_d
  BRA .sn_r
.sn_rf:
  TXA
  SEC
  SBC CXC
  STA DR
.sn_d:
  LDA DL
  AND DR
  CMP #$FF
  BEQ .sn_no
  LDA DL
  CMP DR
  BEQ .sn_t
  BCC .sn_lt
  LDA #8
  SEC
  RTS
.sn_lt:
  LDA #4
  SEC
  RTS
.sn_t:
  LDA MXC
  CMP CXC
  LDA #8
  BCS .sn_ty
  LDA #4
.sn_ty:
  SEC
  RTS
.sn_no:
  CLC
  RTS

; X, Y = a cell of the scan: A = 0 go on, 1 found, 2 stop here (keeps X and Y)
SCAN_CELL:
  JSR SUPP
  BCS .sc_s
  LDA WANT                     ; nothing holds there: a way down, or the end
  BEQ .sc_stop
  LDA #1
  RTS
.sc_stop:
  LDA #2
  RTS
.sc_s:
  LDA WANT
  BNE .sc_d
  JSR CAN_UP
  BCS .sc_f
  LDA #0
  RTS
.sc_d:
  JSR CAN_DN
  BCS .sc_f
  LDA #0
  RTS
.sc_f:
  LDA #1
  RTS

; a cat touching Squeak
HITS:
  LDA GOD
  BNE .ht_r
  LDX NCAT
.ht_l:
  DEX
  BMI .ht_r
  LDA CST,X
  CMP #K_BACK
  BEQ .ht_l
  CMP #K_OFF
  BEQ .ht_l
  LDA CAX,X
  SEC
  SBC MX
  BCS .ht_x
  EOR #$FF
  INC A
.ht_x:
  CMP #6
  BCS .ht_l
  LDA CAY,X
  SEC
  SBC MY
  BCS .ht_y
  EOR #$FF
  INC A
.ht_y:
  CMP #6
  BCS .ht_l
  LDA #1
  JMP DIES
.ht_r:
  RTS

; A = what (DEATHS): Squeak is lost
DIES:
  STA DEATHS
  LDA GSTATE
  BNE .di_r
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  STZ MGT
  LDA #W_DOWN
  LDX #2
  JSR SFX_WHISTLE
.di_r:
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  JSR SQ_SPR
  LDA SPRROT                   ; the cats, a different first one every frame
  INC A
  CMP NCAT
  BCC .bs_rot
  LDA #0
.bs_rot:
  STA SPRROT
  STA T7
  LDA NCAT
  STA T6
  BEQ .bs_e
.bs_k:
  LDX T7
  JSR CAT_SPR
  INC T7
  LDA T7
  CMP NCAT
  BCC .bs_kk
  STZ T7
.bs_kk:
  DEC T6
  BNE .bs_k
.bs_e:
  LDY SPRI
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; Squeak: 2 sprites (the pink parts on top of the fur)
SQ_SPR:
  LDA GSTATE
  CMP #1
  BNE .ss_a
  LDA GT                       ; lost: squashed, then gone
  CMP #20
  BCS .ss_d
  RTS
.ss_d:
  LDA #PT_SQD
  LDX GT
  CPX #60
  BCS .ss_k
  LDA #PT_SQD+8
  BRA .ss_k
.ss_a:
  LDA MPOSE
  BEQ .ss_w
  CMP #1
  BEQ .ss_c
  LDA MX                       ; on a pipe or falling: the hands up
  AND #4
  ASL A
  CLC
  ADC #PT_SQH
  BRA .ss_k
.ss_c:
  LDA MY                       ; on a ladder
  AND #4
  ASL A
  CLC
  ADC #PT_SQC
  BRA .ss_k
.ss_w:
  LDA MX                       ; walking
  AND #4
  ASL A
  STA T0
  LDA MFACE
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_SQ
.ss_k:
  STA ON
  LDA MX
  STA OX
  LDA MY
  CLC
  ADC #7
  STA OY
  LDA ON
  PHA
  CLC
  ADC #4
  STA ON
  LDA #9
  STA OC
  JSR ADD_SPR
  PLA
  STA ON
  LDA #14
  STA OC
  JMP ADD_SPR

; X = cat
CAT_SPR:
  LDA CST,X
  BEQ .cs_r
  CMP #K_BACK
  BEQ .cs_r
  LDA CAX,X
  STA OX
  LDA CAY,X
  CLC
  ADC #7
  STA OY
  LDA CST,X
  CMP #K_HOLE
  BNE .cs_n
  LDA CT,X                     ; stuck: it shakes before it climbs out
  CMP #30
  BCS .cs_h
  LDA FRAME_CNT
  AND #2
  LSR A
  CLC
  ADC OX
  STA OX
.cs_h:
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_CATC
  BRA .cs_k
.cs_n:
  CMP #K_OUT
  BEQ .cs_c
  LDA CPOSE,X
  BNE .cs_c
  LDA CAX,X                    ; walking
  AND #4
  STA T0
  LDA CFACE,X
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_CAT
  BRA .cs_k
.cs_c:
  LDA CAY,X                    ; climbing, hanging, falling
  AND #4
  CLC
  ADC #PT_CATC
.cs_k:
  STA ON
  LDA CAT_COL,X
  STA OC
  LDA CCAR,X                   ; with a cheese: it blinks yellow
  BEQ .cs_s
  LDA FRAME_CNT
  AND #8
  BEQ .cs_s
  LDA #CAT_CHC
  STA OC
.cs_s:
  JMP ADD_SPR
.cs_r:
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
SC_COL:     .byte 4,26                         ; score of player 1 / 2 on row 0
DIRBIT:     .byte 1,2,4,8                       ; up, down, left, right
S_BIG = S_THUD                                  ; (lib_sound: a big noise is not cut by a small one)
; the cells: tile and 1 = two variants (by column and row)
TILE_OF:    .byte $20,T_PLANK,T_STONE,T_LADDER,T_PIPE,T_CHEESE,T_PLANK,$20,$20,$20,$20
VAR_OF:     .byte 0,1,1,0,0,0,1,0,0,0,0
; MAP: the start of every row (0-21)
MR_LO:      .byte <(MAP+0),<(MAP+32),<(MAP+64),<(MAP+96),<(MAP+128),<(MAP+160),<(MAP+192),<(MAP+224)
            .byte <(MAP+256),<(MAP+288),<(MAP+320),<(MAP+352),<(MAP+384),<(MAP+416),<(MAP+448),<(MAP+480)
            .byte <(MAP+512),<(MAP+544),<(MAP+576),<(MAP+608),<(MAP+640),<(MAP+672)
MR_HI:      .byte >(MAP+0),>(MAP+32),>(MAP+64),>(MAP+96),>(MAP+128),>(MAP+160),>(MAP+192),>(MAP+224)
            .byte >(MAP+256),>(MAP+288),>(MAP+320),>(MAP+352),>(MAP+384),>(MAP+416),>(MAP+448),>(MAP+480)
            .byte >(MAP+512),>(MAP+544),>(MAP+576),>(MAP+608),>(MAP+640),>(MAP+672)

; per level (0-15): speed of the cats (fraction of a pixel a frame), frames in a hole
CAT_SPD:    .byte 150,155,160,160,165,170,170,175,180,180,185,190,190,195,200,200
TRAP_TM:    .byte 150,145,140,135,130,125,120,115,110,105,100,100,95,95,90,90
; the cats: colour (even / odd), with a cheese
CAT_COL:    .byte 10,15,10,15,10
CAT_CHC     = 11

; title: Squeak (fur, pink), a cat beside him, a cat by the points (sprite Y, X, pattern, colour, second frame)
TITLE_NS = 4
TITLE_SY:   .byte 47,47,47,119
TITLE_SX:   .byte 104,104,136,56
TITLE_SN:   .byte PT_SQ,PT_SQ+4,PT_CAT+8,PT_CAT
TITLE_SC:   .byte 14,9,10,15
TITLE_SA:   .byte 8,8,4,4

TXT_LEVELH: .byte "LEVEL "
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
  .byte 9,5,"BUTTON 1 = GNAW LEFT",0
  .byte 10,5,"BUTTON 2 = GNAW RIGHT",0
  .byte 11,5,"HOLD BOTH = GIVE UP",0
  .byte 13,7,T_CHEESE," CHEESE       250",0
  .byte 15,9,"CAT IN A HOLE  75",0
  .byte 17,9,"LEVEL DONE   1500",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 13,11,"PLAYER ",0,$FF
; the sign of the level: a box on rows 8-14
TXT_SIGN:
  .byte 8,7,"                  ",0
  .byte 9,7,"                  ",0
  .byte 10,7,"                  ",0
  .byte 11,7,"                  ",0
  .byte 12,7,"                  ",0
  .byte 13,7,"                  ",0
  .byte 14,7,"                  ",0
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
;  GRAPHICS, LEVELS AND SOUND TABLES (generated)
; ===============================================================
; CHEESE CHASE: generated by dev/gen_cheese_chase.js (do not edit by hand)

; sprite patterns (16x16 with an 8x8 figure), value = pattern number * 4; tiles
T_PLANK = 96
T_STONE = 98
T_LADDER = 100
T_PIPE = 101
T_CHEESE = 102
T_GNAW1 = 103
T_GNAW2 = 104
T_LIFE = 105
T_HOLEB = 106
PT_SQ = 0
PT_SQC = 32
PT_SQH = 48
PT_SQD = 64
PT_CAT = 80
PT_CATC = 96
PT_CHEESE = 104
NLEV = 16
BIGT = 200
BIGB = 220
SPR_LEN = 864
SPR_PAGES = 4
SPRITES:
  .byte $00,$00,$0E,$1D,$3E,$3E,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$06,$00,$80,$41,$00,$00,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0E,$1D,$3E,$3E,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$06,$00,$00,$C1,$00,$00,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$70,$B8,$7C,$7C,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$60,$00,$01,$82,$00,$00,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$70,$B8,$7C,$7C,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$60,$00,$00,$83,$00,$00,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$3C,$7E,$7E,$3C,$7E,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $24,$00,$00,$80,$00,$00,$02,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$3C,$7E,$7E,$3C,$7E,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $24,$00,$00,$01,$00,$00,$40,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$42,$3C,$3C,$3C,$3C,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$18,$00,$00,$00,$00,$00,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$42,$3C,$3C,$3C,$3C,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$18,$00,$00,$00,$00,$00,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$7E,$FF,$DB,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$42,$00,$00,$00,$81,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$7E,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$A5,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $05,$87,$85,$7E,$7E,$42,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $05,$47,$85,$7E,$7E,$24,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $A0,$E1,$A1,$7E,$7E,$42,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $A0,$E2,$A1,$7E,$7E,$24,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$7E,$7E,$3C,$7E,$BD,$24,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$7E,$7E,$3C,$7E,$BD,$24,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$1C,$3E,$76,$7E,$6E,$7E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; game tiles 96-106: patterns and colours
TILEP:
  .byte $FF,$BF,$FF,$FF,$02,$FF,$EF,$00,$FF,$FB,$FF,$FF,$20,$FF,$FE,$00,$FE,$FE,$FE,$00,$EF,$EF,$EF,$00,$EF,$EF,$EF,$00,$FE,$FE,$FE,$00
  .byte $42,$7E,$42,$42,$42,$7E,$42,$42,$00,$FF,$AA,$FF,$00,$00,$00,$00,$00,$00,$1C,$3E,$76,$7E,$6E,$7E,$00,$90,$DD,$FF,$02,$FF,$EF,$00
  .byte $00,$00,$00,$00,$44,$FF,$EF,$00,$00,$44,$6C,$38,$54,$7C,$38,$00,$00,$20,$01,$44,$00,$90,$04,$20
TILEC:
  .byte $A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$71,$71,$71,$71,$71,$71,$71,$71,$00,$00,$B1,$B1,$B1,$B1,$B1,$A1,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$61,$61,$61,$61,$61,$61,$61,$61

; the levels: 22 rows x 16 bytes, two cells a byte (left = high nibble)
LEV0:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00
  .byte $00,$00,$0A,$00,$00,$00,$05,$00,$00,$00,$70,$00,$00,$A0,$00,$50
  .byte $11,$11,$11,$11,$31,$11,$11,$11,$11,$11,$11,$11,$31,$11,$11,$11
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
  .byte $00,$05,$00,$00,$30,$00,$00,$00,$00,$50,$00,$00,$30,$00,$00,$00
  .byte $11,$11,$11,$11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$50,$00,$03,$00,$00,$00,$00,$00,$00,$50,$00
  .byte $11,$11,$31,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$13,$11,$11
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$50,$30,$00,$00,$00,$00,$00,$90,$00,$00,$00,$00,$03,$05,$00
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV1:
  .byte $00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$05,$00,$00,$44,$44,$44,$44,$44,$44,$00,$00,$50,$00,$A0
  .byte $11,$11,$31,$11,$11,$00,$00,$00,$00,$00,$00,$11,$11,$13,$11,$11
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$0A,$30,$00,$00,$00,$00,$05,$00,$00,$00,$00,$00,$03,$50,$00
  .byte $00,$01,$11,$31,$11,$11,$11,$11,$11,$11,$11,$11,$13,$11,$10,$00
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$00,$30,$50,$00,$04,$44,$44,$40,$00,$50,$03,$00,$00,$00
  .byte $11,$31,$11,$11,$11,$11,$10,$00,$00,$01,$11,$11,$11,$11,$13,$11
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00
  .byte $50,$30,$00,$00,$00,$90,$00,$05,$00,$00,$00,$00,$00,$00,$03,$05
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV2:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$A0,$00,$00,$50,$00,$00,$70,$00,$05,$00,$00,$0A,$00,$00
  .byte $11,$11,$13,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$31,$11,$11
  .byte $00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$50,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$05,$00
  .byte $11,$11,$11,$11,$31,$11,$11,$11,$11,$11,$11,$13,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$30,$00,$20,$00,$50,$00,$20,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$21,$11,$11,$12,$20,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$50,$00,$50,$00,$03,$00,$00,$00,$00
  .byte $11,$13,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$31,$11
  .byte $00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00
  .byte $05,$03,$00,$00,$00,$00,$00,$09,$00,$00,$00,$00,$00,$00,$30,$50
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV3:
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$05,$0A,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$A0,$50,$00
  .byte $13,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$31
  .byte $03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30
  .byte $03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30
  .byte $03,$44,$45,$44,$44,$44,$44,$45,$44,$44,$44,$44,$45,$44,$44,$30
  .byte $03,$11,$11,$11,$11,$03,$11,$11,$11,$11,$30,$11,$11,$11,$11,$30
  .byte $03,$00,$00,$00,$00,$03,$00,$00,$00,$00,$30,$00,$00,$00,$00,$30
  .byte $03,$00,$00,$00,$00,$03,$00,$00,$00,$00,$30,$00,$00,$00,$00,$30
  .byte $03,$00,$00,$00,$00,$03,$00,$09,$00,$00,$30,$00,$00,$00,$00,$30
  .byte $31,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$13
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $30,$00,$05,$00,$00,$00,$00,$05,$00,$00,$00,$00,$05,$00,$00,$03
  .byte $30,$11,$11,$11,$11,$00,$11,$11,$11,$11,$00,$11,$11,$11,$11,$03
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $30,$00,$00,$00,$00,$00,$00,$05,$00,$00,$A0,$00,$00,$00,$00,$03
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV4:
  .byte $00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $05,$A0,$07,$00,$00,$00,$04,$44,$44,$44,$44,$44,$44,$44,$00,$00
  .byte $11,$11,$11,$11,$11,$31,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$05,$30,$00,$00,$00,$00,$00,$05,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$11,$11,$11,$11,$11,$11,$13,$11,$10,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$A0,$50
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$31,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$05,$00,$00,$00,$00,$00,$35,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$11,$31,$11,$11,$13,$11,$11,$10,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$30,$00,$00,$03,$00,$00,$00,$00,$00,$00
  .byte $05,$00,$00,$00,$00,$00,$35,$00,$00,$03,$00,$00,$00,$00,$00,$50
  .byte $11,$13,$11,$11,$11,$11,$11,$10,$01,$11,$11,$11,$11,$11,$31,$11
  .byte $00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$00,$05,$90,$00,$00,$00,$00,$00,$30,$00
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV5:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $00,$00,$05,$00,$00,$A0,$00,$00,$00,$00,$0A,$00,$00,$50,$00,$07
  .byte $11,$11,$11,$11,$11,$11,$11,$13,$31,$11,$11,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$05,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$31,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$13,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$50,$00,$44,$44,$00,$05,$00,$00,$03,$00,$00
  .byte $11,$11,$11,$13,$11,$11,$11,$00,$00,$11,$11,$11,$31,$11,$11,$11
  .byte $00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
  .byte $00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
  .byte $05,$00,$00,$03,$00,$00,$00,$00,$00,$00,$A0,$00,$30,$00,$00,$50
  .byte $11,$31,$11,$11,$11,$11,$11,$66,$66,$11,$11,$11,$11,$11,$13,$11
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$30,$90,$00,$00,$00,$00,$05,$50,$00,$00,$00,$00,$00,$03,$00
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV6:
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$04,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$40,$00
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$0A,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$05,$00,$00
  .byte $11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$11,$31,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$50,$05,$00,$00,$30,$00,$00,$A0,$00
  .byte $11,$11,$13,$11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$31,$11,$11
  .byte $00,$00,$03,$00,$00,$00,$20,$03,$00,$02,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$20,$03,$00,$02,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$20,$03,$00,$02,$00,$00,$00,$30,$00,$00
  .byte $00,$50,$03,$00,$00,$00,$20,$03,$05,$02,$00,$00,$00,$30,$05,$00
  .byte $13,$11,$11,$11,$11,$22,$21,$11,$11,$12,$32,$11,$11,$11,$11,$31
  .byte $03,$00,$00,$00,$00,$20,$00,$00,$00,$00,$32,$00,$00,$00,$00,$30
  .byte $03,$00,$00,$00,$00,$20,$00,$00,$00,$00,$32,$00,$00,$00,$00,$30
  .byte $03,$00,$00,$00,$00,$20,$00,$00,$00,$00,$32,$00,$00,$00,$00,$30
  .byte $03,$05,$00,$90,$00,$20,$00,$05,$50,$00,$32,$00,$0A,$00,$50,$30
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV7:
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$5A,$07,$00,$05,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$31,$11,$11,$11,$11,$11,$11,$13,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$50,$00,$0A,$00,$00,$05,$03,$00,$00,$00,$00
  .byte $00,$00,$31,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$13,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00
  .byte $00,$A0,$30,$50,$00,$00,$00,$00,$00,$00,$00,$00,$05,$03,$0A,$00
  .byte $31,$11,$11,$66,$11,$11,$11,$11,$11,$11,$11,$11,$66,$11,$11,$13
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $35,$00,$00,$00,$00,$00,$04,$44,$44,$40,$00,$00,$00,$00,$00,$53
  .byte $11,$11,$11,$11,$11,$11,$30,$00,$00,$03,$11,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$00,$30,$00,$00,$03,$00,$00,$00,$00,$00,$00
  .byte $50,$00,$00,$00,$00,$00,$30,$90,$00,$03,$00,$00,$00,$00,$00,$05
  .byte $11,$11,$11,$11,$11,$11,$11,$13,$31,$11,$11,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $50,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$05
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV8:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70
  .byte $00,$05,$00,$A0,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$00,$50,$70
  .byte $11,$11,$11,$11,$11,$11,$11,$13,$31,$11,$11,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $44,$44,$45,$44,$44,$34,$44,$43,$34,$44,$43,$44,$44,$54,$44,$44
  .byte $00,$01,$11,$11,$00,$30,$00,$00,$00,$00,$03,$00,$11,$11,$10,$00
  .byte $00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$30,$0A,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $34,$44,$44,$44,$44,$34,$44,$45,$44,$44,$43,$44,$44,$44,$44,$43
  .byte $30,$00,$00,$00,$00,$00,$11,$11,$11,$11,$00,$00,$00,$00,$00,$03
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03
  .byte $34,$44,$43,$44,$45,$44,$44,$45,$44,$44,$44,$54,$44,$34,$44,$43
  .byte $30,$00,$03,$00,$01,$11,$11,$11,$11,$11,$11,$10,$00,$30,$00,$03
  .byte $30,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$03
  .byte $30,$00,$03,$00,$00,$05,$00,$09,$00,$00,$50,$00,$00,$30,$00,$03
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV9:
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$A0,$50,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$05,$0A,$00
  .byte $11,$11,$11,$11,$31,$11,$11,$11,$11,$11,$11,$13,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00
  .byte $50,$00,$A0,$00,$30,$00,$00,$00,$00,$00,$00,$03,$00,$0A,$00,$05
  .byte $11,$13,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$31,$11
  .byte $00,$03,$00,$00,$00,$02,$00,$00,$50,$00,$20,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$02,$21,$11,$11,$12,$20,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00
  .byte $50,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$05
  .byte $11,$11,$11,$11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $00,$20,$05,$00,$02,$00,$00,$03,$00,$00,$00,$20,$00,$50,$02,$00
  .byte $00,$22,$11,$11,$22,$00,$00,$03,$00,$00,$00,$22,$11,$11,$22,$00
  .byte $05,$00,$00,$00,$00,$00,$09,$03,$00,$00,$00,$00,$00,$00,$00,$50
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV10:
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$A0,$00,$00,$00,$00,$50,$00,$00,$05,$00,$00,$00,$00,$0A,$00
  .byte $11,$11,$11,$31,$11,$11,$11,$13,$11,$11,$11,$11,$13,$11,$11,$11
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$A0,$03,$00,$0A,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$14,$44,$44,$43,$44,$44,$44,$41,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$50,$00,$31,$10,$05,$00,$03,$00,$00,$50,$01,$13,$00,$05,$00
  .byte $11,$11,$11,$31,$11,$11,$11,$13,$01,$11,$11,$11,$13,$11,$11,$11
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$50,$00,$31,$10,$05,$00,$03,$00,$00,$50,$01,$13,$00,$05,$00
  .byte $11,$11,$11,$31,$11,$11,$11,$13,$01,$11,$11,$11,$13,$11,$11,$11
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $00,$00,$00,$31,$10,$00,$00,$03,$00,$00,$00,$01,$13,$00,$00,$00
  .byte $50,$00,$00,$31,$10,$05,$09,$03,$00,$00,$50,$01,$13,$00,$00,$05
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV11:
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$44,$44,$44,$44,$47,$44,$44,$44,$44,$44,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$A0,$00,$50,$00,$00,$07,$00,$00,$00,$05,$00,$0A,$00,$00
  .byte $11,$66,$11,$11,$11,$11,$31,$11,$11,$13,$11,$11,$11,$11,$66,$11
  .byte $00,$00,$00,$00,$00,$00,$30,$00,$00,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$30,$00,$00,$03,$00,$00,$00,$00,$00,$00
  .byte $00,$50,$00,$00,$00,$00,$30,$00,$00,$03,$00,$00,$00,$00,$05,$00
  .byte $11,$11,$13,$11,$11,$11,$11,$16,$61,$11,$11,$11,$11,$31,$11,$11
  .byte $00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$A0,$00,$05,$50,$00,$0A,$00,$00,$30,$00,$00
  .byte $11,$11,$11,$31,$11,$11,$11,$11,$11,$11,$11,$11,$13,$11,$11,$11
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$00,$30,$05,$00,$00,$00,$00,$00,$00,$50,$03,$00,$00,$00
  .byte $11,$16,$61,$11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$16,$61,$11
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$05,$00,$00,$00,$00,$00,$03,$00,$00,$90,$00,$00,$00,$50,$00
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV12:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $44,$44,$44,$44,$44,$44,$44,$44,$74,$44,$44,$44,$44,$44,$44,$44
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$A0,$50,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$05,$0A,$00
  .byte $11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$11,$31,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$50,$03,$00,$50,$0A,$00,$05,$00,$30,$05,$00,$00,$00
  .byte $11,$31,$11,$11,$11,$11,$11,$11,$31,$11,$11,$11,$11,$11,$13,$11
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$3A,$05,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$50,$A3,$00
  .byte $11,$11,$11,$11,$13,$11,$11,$11,$11,$11,$11,$31,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$05,$00,$03,$00,$50,$00,$90,$05,$00,$30,$00,$50,$00,$00
  .byte $11,$31,$11,$11,$11,$11,$11,$11,$31,$11,$11,$11,$11,$11,$13,$11
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$30,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$03,$00
  .byte $00,$30,$00,$50,$00,$00,$00,$00,$30,$00,$00,$00,$05,$00,$03,$00
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV13:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07
  .byte $44,$43,$44,$44,$44,$44,$40,$00,$00,$04,$44,$44,$44,$44,$34,$47
  .byte $00,$03,$00,$00,$00,$00,$02,$11,$31,$20,$00,$00,$00,$00,$30,$07
  .byte $50,$03,$00,$A0,$00,$00,$02,$00,$30,$20,$00,$00,$0A,$00,$30,$57
  .byte $11,$13,$11,$11,$11,$11,$12,$00,$30,$21,$11,$11,$11,$11,$31,$11
  .byte $00,$03,$00,$00,$00,$00,$02,$00,$30,$20,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$02,$00,$30,$20,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$50,$00,$00,$02,$00,$30,$20,$00,$00,$05,$00,$30,$00
  .byte $11,$11,$11,$11,$11,$31,$12,$00,$30,$21,$13,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$30,$02,$00,$30,$20,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$30,$02,$00,$30,$20,$03,$00,$00,$00,$00,$00
  .byte $50,$00,$00,$00,$A0,$30,$02,$00,$30,$20,$03,$0A,$00,$00,$00,$05
  .byte $11,$13,$11,$11,$11,$11,$12,$00,$30,$21,$11,$11,$11,$11,$31,$11
  .byte $00,$03,$00,$00,$00,$00,$02,$00,$30,$20,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$02,$00,$30,$20,$00,$00,$00,$00,$30,$00
  .byte $00,$03,$00,$00,$00,$00,$02,$05,$30,$20,$00,$00,$00,$00,$30,$00
  .byte $11,$11,$11,$11,$31,$11,$12,$11,$11,$21,$11,$11,$31,$11,$11,$11
  .byte $00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00
  .byte $50,$00,$09,$00,$30,$00,$00,$50,$05,$00,$00,$00,$30,$00,$00,$05
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV14:
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$50,$00,$07,$00,$00,$05,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$31,$11,$11,$11,$11,$11,$11,$11,$11,$13,$00,$00,$00
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00
  .byte $00,$00,$50,$30,$00,$00,$05,$0A,$00,$50,$00,$00,$03,$05,$00,$00
  .byte $00,$01,$11,$11,$13,$11,$11,$11,$11,$11,$11,$31,$11,$11,$10,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$50,$00,$00,$03,$A0,$00,$00,$00,$00,$0A,$30,$00,$00,$05,$00
  .byte $13,$11,$11,$11,$11,$11,$11,$66,$66,$11,$11,$11,$11,$11,$11,$31
  .byte $03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30
  .byte $03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30
  .byte $03,$00,$34,$44,$44,$44,$44,$44,$44,$44,$44,$44,$44,$43,$00,$30
  .byte $03,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$30
  .byte $03,$00,$30,$00,$50,$00,$00,$09,$00,$00,$00,$05,$00,$03,$00,$30
  .byte $13,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$31
  .byte $03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30
  .byte $03,$0A,$00,$00,$00,$00,$00,$05,$50,$00,$00,$00,$00,$00,$A0,$30
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV15:
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $70,$05,$44,$44,$44,$34,$44,$44,$44,$44,$43,$44,$44,$44,$50,$00
  .byte $70,$00,$00,$00,$00,$30,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $70,$00,$A0,$00,$00,$30,$50,$00,$00,$05,$03,$00,$00,$0A,$00,$00
  .byte $11,$11,$11,$11,$11,$31,$11,$11,$11,$11,$13,$11,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$50,$00,$A0,$30,$00,$00,$00,$00,$03,$0A,$00,$05,$00,$00
  .byte $00,$01,$13,$11,$11,$11,$11,$16,$61,$11,$11,$11,$11,$31,$10,$00
  .byte $00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$00,$05,$50,$00,$00,$00,$00,$30,$00,$00
  .byte $00,$00,$03,$00,$00,$00,$04,$44,$44,$40,$00,$00,$00,$30,$00,$00
  .byte $11,$11,$11,$11,$13,$11,$10,$00,$00,$01,$11,$31,$11,$11,$11,$11
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00
  .byte $05,$00,$00,$00,$03,$00,$09,$0A,$00,$00,$00,$30,$00,$00,$00,$50
  .byte $11,$11,$11,$66,$11,$11,$11,$13,$31,$11,$11,$11,$66,$11,$11,$11
  .byte $00,$02,$00,$50,$00,$20,$00,$03,$30,$00,$02,$00,$05,$00,$20,$00
  .byte $00,$02,$21,$11,$12,$20,$00,$03,$30,$00,$02,$21,$11,$12,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$53,$35,$00,$00,$00,$00,$00,$00,$00
  .byte $22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22,$22
LEV_LO:
  .byte <LEV0,<LEV1,<LEV2,<LEV3,<LEV4,<LEV5,<LEV6,<LEV7,<LEV8,<LEV9,<LEV10,<LEV11,<LEV12,<LEV13,<LEV14,<LEV15
LEV_HI:
  .byte >LEV0,>LEV1,>LEV2,>LEV3,>LEV4,>LEV5,>LEV6,>LEV7,>LEV8,>LEV9,>LEV10,>LEV11,>LEV12,>LEV13,>LEV14,>LEV15
LEV_NAME:
  .byte "   THE CELLAR   "
  .byte "   MILK PIPES   "
  .byte "   THE VAULT    "
  .byte "  CHEESE RACKS  "
  .byte "   THE STAIRS   "
  .byte "  THE CREAMERY  "
  .byte " THE COLD ROOM  "
  .byte "   THE WHEELS   "
  .byte "   PIPE MAZE    "
  .byte "   THE PRESS    "
  .byte "   THE TOWERS   "
  .byte "    THE DROP    "
  .byte "   THE PANTRY   "
  .byte "    THE WELL    "
  .byte "    THE LOFT    "
  .byte " THE BIG CHEESE "

; big letters of the title
BIG_TOP:
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00,$00,$18,$18,$18,$18,$18,$18,$1F,$00,$18,$18,$18,$18,$18,$18,$F8
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0,$00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
BIG_BOT:
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00,$1F,$18,$18,$18,$18,$18,$18,$00,$F8,$18,$18,$18,$18,$18,$18,$00
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00,$07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$B8,$F8,$18,$18,$18,$18,$00
TXT_BIG:
  .byte 3,4,200,201,202,203,204,205,204,205,206,207,204,205,32,32,200,201,202,203,208,209,206,207,204,205,0
  .byte 4,4,220,221,222,223,224,225,224,225,226,227,224,225,32,32,220,221,222,223,228,229,226,227,224,225,0
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
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3,<SG2_0,<SG2_1,<SG2_2,<SG2_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3,>SG2_0,>SG2_1,>SG2_2,>SG2_3
SG0_0:
  .byte $27,$04,$00,$04,$27,$04,$00,$04,$2A,$04,$00,$04,$2E,$08,$2C,$04,$2A,$04,$29,$04,$00,$04,$25,$08,$27,$04,$00,$04,$27,$04,$00,$04
  .byte $2A,$04,$00,$04,$2E,$08,$2F,$04,$2E,$04,$2C,$10,$2E,$04,$00,$04,$2E,$04,$00,$04,$31,$04,$00,$04,$2F,$08,$2E,$04,$2C,$04,$2A,$04
  .byte $00,$04,$29,$08,$2A,$04,$29,$04,$27,$04,$26,$04,$27,$04,$29,$04,$2A,$04,$29,$04,$27,$10,$FF
SG0_1:
  .byte $1E,$10,$22,$10,$20,$10,$1D,$10,$1E,$10,$22,$10,$20,$20,$22,$10,$25,$10,$23,$10,$22,$10,$22,$10,$20,$10,$1E,$20,$FF
SG0_2:
  .byte $0F,$08,$0A,$08,$0F,$08,$0A,$08,$0D,$08,$08,$08,$0D,$08,$08,$08,$0F,$08,$0A,$08,$0F,$08,$0A,$08,$08,$08,$0F,$08,$08,$08,$0F,$08
  .byte $06,$08,$0D,$08,$06,$08,$0D,$08,$08,$08,$0F,$08,$0A,$08,$11,$08,$0B,$08,$12,$08,$0A,$08,$11,$08,$0F,$08,$0A,$08,$0F,$10,$FF
SG0_3:
  .byte $03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08
  .byte $03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$03,$08,$02,$08,$01,$08,$02,$08,$04,$10,$FF
SG1_0:
  .byte $22,$04,$27,$04,$2A,$04,$2E,$08,$2C,$04,$2A,$04,$29,$04,$2C,$04,$2E,$04,$27,$10,$FF
SG1_1:
  .byte $1E,$10,$1D,$10,$1E,$14,$FF
SG1_2:
  .byte $0F,$08,$0A,$08,$0D,$08,$0A,$08,$0F,$14,$FF
SG1_3:
  .byte $01,$04,$03,$04,$02,$04,$03,$04,$01,$04,$03,$04,$02,$04,$03,$04,$01,$04,$02,$04,$04,$0C,$FF
SG2_0:
  .byte $27,$04,$2A,$04,$2E,$04,$33,$08,$31,$04,$2F,$04,$2E,$04,$2A,$04,$2C,$04,$2E,$04,$33,$14,$FF
SG2_1:
  .byte $22,$0C,$1E,$0C,$20,$0C,$1F,$14,$FF
SG2_2:
  .byte $0F,$0C,$0B,$0C,$0D,$0C,$0F,$14,$FF
SG2_3:
  .byte $02,$04,$02,$04,$02,$04,$01,$0C,$03,$04,$03,$04,$03,$04,$03,$04,$01,$04,$02,$04,$04,$10,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$24,$00,$35,$00,$28,$28,$28,$1E,$1E,$1E,$18,$18,$18,$18,$18,$18,$59,$4F,$47,$41,$3C,$39,$36,$35,$34,$34,$35,$36,$39,$3C,$41
  .byte $47,$4F,$59,$BD,$BD,$BD,$1C,$1C,$1C,$1C,$1C,$1C,$78,$78,$78,$6A,$6A,$6A,$5F,$5F,$5F,$55,$55,$55,$4B,$4B,$4B,$43,$43,$43,$3C,$3C
  .byte $3C,$35,$35,$35,$45,$48,$44,$46,$50,$53,$4E,$51,$5C,$60,$5A,$5D,$6A,$6E,$68,$6C,$7B,$7F,$78,$7C,$8E,$93,$8A,$8F,$A3,$A9,$9F,$A5
  .byte $BC,$C3,$B8,$BF,$D9,$E1,$D4,$DC,$FA,$03,$F4,$FD,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$97,$97,$97,$97,$97,$97,$97,$97,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$D5,$D5,$D5,$D5
  .byte $D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28
  .byte $28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00
WH_VOL:
  .byte $00,$04,$00,$04,$00,$0D,$0C,$0A,$0D,$0C,$0A,$0D,$0B,$09,$07,$05,$03,$08,$09,$0A,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05
  .byte $05,$04,$04,$0C,$0B,$0A,$0B,$09,$08,$06,$05,$03,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07
  .byte $06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B
  .byte $09,$08,$06,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B
  .byte $0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06
  .byte $04,$03
WH_START:
  .byte $00,$01,$03,$05,$11,$23,$2C,$44,$6C,$84,$AC,$AF
WH_LEN:
  .byte $00,$02,$02,$0C,$12,$09,$18,$28,$18,$28,$03,$13
W_STEP = 1
W_CLIMB = 2
W_CHEESE = 3
W_MEOW = 4
W_SHUT = 5
W_EXIT = 6
W_DOWN = 7
W_EXTRA = 8
W_OVER = 9
W_KEY = 10
W_SIGN = 11

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$09,$00,$08,$00,$07,$00,$06,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03
EX_NP:
  .byte $00,$02,$00,$03,$00,$02,$00,$03,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
EX_START:
  .byte $00,$01,$08
EX_LEN:
  .byte $00,$07,$0A
S_GNAW = 1
S_THUD = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$66, <80,>80, $B1,0
  .byte 2, $E0,$66, <80,>80, $A1,0
  .byte 1, $00,$43, <88,>88, <TILEP,>TILEP
  .byte 1, $00,$63, <88,>88, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$4E, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$6E, <80,>80, $B1,0
  .byte 2, $E0,$6E, <80,>80, $A1,0
  .byte 1, $00,$4B, <88,>88, <TILEP,>TILEP
  .byte 1, $00,$6B, <88,>88, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$56, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$76, <80,>80, $B1,0
  .byte 2, $E0,$76, <80,>80, $A1,0
  .byte 1, $00,$53, <88,>88, <TILEP,>TILEP
  .byte 1, $00,$73, <88,>88, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
