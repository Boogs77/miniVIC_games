;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ROBO VAC  -  an original maze-chase game                   ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - a little robot vacuum cleans the house room by room:     ;
;     kitchen, living room, bedroom, bathroom, study, kids     ;
;     room, garage, attic; then the house again, faster        ;
;   - the joystick books the next turn, taken at the first     ;
;     crossing; it can turn back at any moment                 ;
;   - dust 10 points; the 4 wall sockets give the turbo: for   ;
;     a few seconds the dust bunnies turn pale and run, and    ;
;     the robot sucks them up (200, 400, 800, 1600); only      ;
;     their eyes go back to the laundry basket                 ;
;   - the 4 dust bunnies: FLUFF follows the robot, LINT goes   ;
;     where it is heading, FUZZ wanders and dashes when it     ;
;     sees it, GRIT guards the sockets; they take turns        ;
;     going round the room and hunting                         ;
;   - twice a room a lost thing shows up under the basket      ;
;     (cookie, remote, sock, duck, key, ball, wrench, ring);   ;
;     from the bedroom the cat of the house sits now and then  ;
;     in a corridor and the robot cannot pass                  ;
;   - row 11 goes out at one side and in at the other          ;
;   - 3 lives, one more at 10000; 1 or 2 players taking turns  ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 38 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at the start and at the end of a     ;
;     room; the motor, the dust, the turbo siren, the bunnies  ;
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
ROOM        = $40      ; ---- block of the player, saved: room 0-7
LOOPN       = $41      ;      round of the house
XTRA        = $42      ;      1 = the extra life was given
FRESH       = $43      ;      1 = a new room (all the dust)
DEATEN      = $44      ;      dust eaten in the room (stops at 255)
BONUSN      = $45      ;      lost things shown in the room (0-2)
PBLOCK      = 6
GSTATE      = $50      ; 0 playing, 1 life lost, 3 room clean
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 room and lives
FIRSTT      = $53      ; 1 = first turn of the game
NDUST       = $54      ; 2 bytes: dust and sockets left
RX          = $56      ; the robot: centre in pixels
RY          = $57
RDIR        = $58      ; 0 right, 1 down, 2 left, 3 up
RWANT       = $59      ; the turn booked ($FF = none)
RACC        = $5A      ; fraction of the speed
RPAUSE      = $5B      ; frames it stops (eating)
RMOVE       = $5C      ; 1 = it moved in this frame
SHOWN       = $5D      ; 1 = the room is new: its name at the start
LEVEL       = $5E      ; speed group 0-5
DUSTSW      = $5F      ; the two dust sounds take turns
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
TURBO       = $72      ; 2 bytes: frames of turbo left
EATN        = $74      ; bunnies eaten in this turbo
PHASE       = $75      ; 0-5: round, hunt, round, hunt, round, hunt
PHT         = $76      ; 2 bytes: frames left in the phase
CHASE       = $78      ; 0 going round, 1 hunting
RELT        = $79      ; frames without dust (the bunnies come out)
LDOTS       = $7A      ; dust eaten in this life (stops at 255)
FUZZS       = $7B      ; 1 = Fuzz sees the robot
LOSTN       = $7C      ; lives lost (tests)
DEATH       = $7D      ; what took the last life (tests): the bunny + 1
CATT        = $7E      ; 2 bytes: frames to the next cat
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
CATON       = $88      ; the cat: there, column, row, frames left
CATC        = $89
CATR        = $8A
CATD        = $8B
BONT        = $8C      ; frames the lost thing stays (0 = none)
FREEZE      = $8D      ; frames everything stops (a bunny eaten)
FRZB        = $8E      ; the bunny eaten: its points shown
FRZP        = $8F
SPRROT      = $90      ; sprite order (more than 4 on a line take turns)
CB          = $91      ; the bunny being moved
TMPX        = $92      ; tile of a decision
TMPY        = $93
TGTX        = $94      ; the target tile
TGTY        = $95
BEST        = $96      ; 2 bytes: best distance
BESTD       = $98      ; its direction
WAYS        = $99      ; directions open (random choice)
DUSTN       = $9A      ; 2 bytes: dust eaten in the game (tests)
SOCKBL      = $9C      ; the sockets: bright / dim
NSTEP       = $9D      ; pixels to move in this frame

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

; ---------------- the dust bunnies: 0 Fluff, 1 Lint, 2 Fuzz, 3 Grit ----------------
NB         = 4
B_X        = $0200       ; centre in pixels
B_Y        = $0204
B_D        = $0208       ; direction
B_M        = $020C       ; mode (M_*)
B_F        = $0210       ; 1 = scared (turbo)
B_ACC      = $0214       ; fraction of the speed
B_REV      = $0218       ; 1 = turn back at the next step
B_HT       = $021C       ; frames left in the basket after the eyes come home
PEN_T      = 180         ; the eyes rest 3 s in the basket before going out again
M_HOUSE    = 0           ; in the basket, bobbing
M_LEAVE    = 1           ; going out of the basket
M_RUN      = 2           ; in the room
M_EYES     = 3           ; only the eyes, back to the basket
M_ENTER    = 4           ; the eyes go into the basket

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
DUSTB      = $0740       ; 2 x 76: the dust left of every player (rows 3-21 x 4 bytes)
MAP        = $0800       ; the name table (rows 0-23)

; ---------------- parameters ----------------
BTN_MASK    = %00110000
T_FLOOR     = 0
T_WALLMK    = 1          ; (a wall while the room is built)
T_WALL      = 96         ; 96-111: furniture by its open sides
T_DUST      = 112
T_SOCK      = 113
T_DOOR      = 114
T_LIFE      = 115
DUSTROW     = 76         ; bytes of a dust map (19 rows x 4)

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 38         ; fixed zone of the game in the save area
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
;  TITLE: the name, the bunnies, what they do
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #$74                     ; the colours of the kitchen for the icons
  JSR WALL_COLS
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

; one frame of the title: the robot brushes, the bunnies wiggle;
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
  LDA FRAME_CNT                ; the second frame of every sprite in turn
  AND #8
  LSR A
  STA T0
  LDX #0
  LDY #0
.tf_s:
  LDA TITLE_SN,X
  ORA T0
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
;  NEW GAME: the kitchen, 3 lives for every player
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
  STZ DUSTN
  STZ DUSTN+1
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ ROOM
  STZ LOOPN
  STZ XTRA
  JSR NEW_ROOM_P
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER, then his room
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

ROOM_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the room is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_LEVEL
  JSR DRAW_ROOM
  LDA FRESH                    ; the name of a new room at its start
  STA SHOWN
  STZ FRESH
  JSR DRAW_HUD
  JSR ROOM_INIT
  JSR MSG_ROOM
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA FIRSTT                   ; the tune at the first turn
  BEQ .rs_short
  STZ FIRSTT
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.rs_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .rs_t
  BRA .rs_w
.rs_short:
  LDA #110
  JSR WAIT_FRAMES
.rs_w:
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
  LDA FRAME_CNT                ; the sockets blink
  AND #15
  BNE .gl_b
  JSR SOCK_BLINK
.gl_b:
  LDA GSTATE
  BNE .gl_ns
  LDA FREEZE                   ; a bunny eaten: everything stops a moment
  BEQ .gl_go
  DEC FREEZE
  BRA .gl_ns
.gl_go:
  JSR ROBOT
  LDA GSTATE
  BNE .gl_ns
  JSR BUNNIES
  JSR HIT
  JSR TIMERS
  JSR MOTOR
.gl_ns:
  LDA GSTATE
  CMP #3
  BNE .gl_h
  JSR FLASH
.gl_h:
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
  BEQ .gl_win
  JMP LOSE_LIFE
.gl_win:
  JMP ROOM_CLEAR


; ===============================================================
;  THE ROOM IS CLEAN: the tune, the next room
; ===============================================================
ROOM_CLEAR:
  JSR VDP_INT_OFF
  LDX ROOM                     ; (the furniture in its colours again)
  LDA ROOM_COL,X
  JSR WALL_COLS
  JSR HIDE_SPRITES
  JSR VDP_INT_ON
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
.rc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .rc_t
  LDA #30
  JSR WAIT_FRAMES
  INC ROOM                     ; the next room; after the attic, the house again
  LDA ROOM
  CMP #8
  BCC .rc_n
  STZ ROOM
  LDA LOOPN
  CMP #8
  BCS .rc_n
  INC LOOPN
.rc_n:
  JSR NEW_ROOM_P
  JSR SAVE_PLAYER
  JMP ROOM_START

; a new room for the player playing: all the dust, no lost thing yet
NEW_ROOM_P:
  LDA #1
  STA FRESH
  STZ DEATEN
  STZ BONUSN
  RTS

LOSE_LIFE:
  LDX CURP
  DEC LIVES,X
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
  TXA                          ; extra byte: the room reached (round x 8 + room + 1)
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
REC_NAME:  .byte "ROBO VAC        "
REC_HEAD:  .byte "BEST CLEANERS",0
REC_XLBL:  .byte "ROOM ",0


; ===============================================================
;  HUD: row 0 (scores), row 1 (room, lives), row 23 (player)
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

; row 1: ROOM nn and its name, the spare lives; row 23: PLAYER n
DRAW_STATUS:
  LDX #1
  LDY #0
  JSR NT_XY
  LDX #0
.ds_s:
  LDA TXT_ROOMH,X
  STA VDATA
  INX
  CPX #5
  BNE .ds_s
  LDA LOOPN                    ; round x 8 + room + 1
  ASL A
  ASL A
  ASL A
  SEC
  ADC ROOM
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDX ROOM                     ; the name, 12 characters
  LDA RNAME_LO,X
  STA PTR
  LDA RNAME_HI,X
  STA PTR+1
  LDY #0
.ds_n:
  LDA (PTR),Y
  BEQ .ds_ne
  STA VDATA
  INY
  BRA .ds_n
.ds_ne:
  LDA #$20
  STA VDATA
  INY
  CPY #12
  BCC .ds_ne
  LDX #1
  LDY #26
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
  LDA NPL
  CMP #2
  BNE .ds_r
  LDX #23
  LDY #12
  JSR NT_XY
  LDX #0
.ds_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .ds_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ds_r:
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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 room and lives
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
  AND #2
  BEQ .uh_r
  JSR DRAW_STATUS
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: his block and the dust left
  LDA CURP
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA ROOM,Y
  STA PSAVE,X
  INX
  INY
  CPY #PBLOCK
  BNE .sp_b
  JMP PACK_DUST

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
  STA ROOM,Y
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
;  THE ROOM ON THE SCREEN
; ===============================================================
; MAP and the name table: rows 0-1 and 23 spaces, the room on rows 2-22 (columns 0-30;
; column 31 only on row 11, the passage), the furniture shaped by its open sides, the
; dust: all of it in a new room, else what the player left (interrupt off)
DRAW_ROOM:
  LDX ROOM
  LDA ROOM_COL,X
  JSR WALL_COLS
  LDX #0
  LDA #$20
.dr_c:
  STA MAP,X
  STA MAP+$100,X
  STA MAP+$200,X
  INX
  BNE .dr_c
  LDX #2                       ; rows 2-22: furniture everywhere
.dr_w:
  STX T0
  JSR ROW_PTRX
  LDY #30
  LDA #T_WALLMK
.dr_wc:
  STA (PTR),Y
  DEY
  BPL .dr_wc
  LDX T0
  INX
  CPX #23
  BNE .dr_w
  LDX ROOM                     ; the open tiles: rows 3-21, 4 bytes a row
  LDA RM_LO,X
  STA PTR2
  LDA RM_HI,X
  STA PTR2+1
  LDA #3
  STA T0                       ; row
  STZ T3                       ; byte of the bitmap
.dr_r:
  LDX T0
  JSR ROW_PTRX
  STZ T1                       ; column
  LDA #4
  STA T4
.dr_b:
  LDY T3
  LDA (PTR2),Y
  STA T2
  INC T3
  LDX #8
.dr_k:
  ASL T2
  BCC .dr_n
  LDY T1
  LDA #T_FLOOR
  STA (PTR),Y
.dr_n:
  INC T1
  DEX
  BNE .dr_k
  DEC T4
  BNE .dr_b
  INC T0
  LDA T0
  CMP #22
  BNE .dr_r
  LDA #T_DOOR                  ; the door of the basket
  STA MAP+10*32+15
  ; ---- the furniture: one tile for its open sides (1 up, 2 right, 4 down, 8 left)
  LDA #2
  STA T0
.dr_fr:
  LDX T0
  JSR ROW_PTRX
  LDA PTR                      ; PTR2 = the row above, T6/T7 = the row below
  SEC
  SBC #32
  STA PTR2
  LDA PTR+1
  SBC #0
  STA PTR2+1
  LDA PTR
  CLC
  ADC #32
  STA T6
  LDA PTR+1
  ADC #0
  STA T7
  LDY #0
.dr_fc:
  LDA (PTR),Y
  CMP #T_WALLMK
  BNE .dr_fn
  STZ T2
  LDA (PTR2),Y
  JSR IS_OPEN
  BCC .dr_f1
  LDA #1
  TSB T2
.dr_f1:
  INY
  LDA (PTR),Y
  DEY
  JSR IS_OPEN
  BCC .dr_f2
  LDA #2
  TSB T2
.dr_f2:
  LDA (T6),Y
  JSR IS_OPEN
  BCC .dr_f3
  LDA #4
  TSB T2
.dr_f3:
  CPY #0
  BEQ .dr_f4
  DEY
  LDA (PTR),Y
  INY
  JSR IS_OPEN
  BCC .dr_f4
  LDA #8
  TSB T2
.dr_f4:
  LDA T2
  CLC
  ADC #T_WALL
  STA (PTR),Y
.dr_fn:
  INY
  CPY #31
  BNE .dr_fc
  INC T0
  LDA T0
  CMP #23
  BNE .dr_fr
  ; ---- the dust and the sockets
  STZ NDUST
  STZ NDUST+1
  JSR DUST_PTR                 ; PTR2 = the dust map of the player
  LDA #3
  STA T0
.dr_dr:
  LDX T0
  JSR ROW_PTRX
  LDA T0                       ; T5 = byte of the row in the dust map
  SEC
  SBC #3
  ASL A
  ASL A
  STA T5
  LDY #1
.dr_dc:
  LDA (PTR),Y
  BNE .dr_dn
  JSR DUST_OK
  BCC .dr_dn
  LDA FRESH
  BNE .dr_put
  TYA                          ; still there for this player?
  LSR A
  LSR A
  LSR A
  CLC
  ADC T5
  PHY
  TAY
  LDA (PTR2),Y
  STA T2
  PLY
  TYA
  AND #7
  TAX
  LDA BITMASK,X
  AND T2
  BEQ .dr_dn
.dr_put:
  LDA #T_DUST
  JSR IS_SOCKET
  BCC .dr_pd
  LDA #T_SOCK
.dr_pd:
  STA (PTR),Y
  INC NDUST
  BNE .dr_dn
  INC NDUST+1
.dr_dn:
  INY
  CPY #30
  BNE .dr_dc
  INC T0
  LDA T0
  CMP #22
  BNE .dr_dr
  ; ---- MAP to the name table
  LDA #$00
  STA VREG
  LDA #($38 | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDA #<MAP
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDX #3
  LDY #0
.dr_vv:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .dr_vv
  INC PTR+1
  DEX
  BNE .dr_vv
  RTS

; A = a tile while the room is built: C = 1 if it is open (floor or door)
IS_OPEN:
  CMP #T_FLOOR
  BEQ .io_y
  CMP #T_DOOR
  BEQ .io_y
  CLC
  RTS
.io_y:
  SEC
  RTS

; Y = column, T0 = row: C = 1 if dust goes there (not in the basket, not at the ends
; of the passage, not where the robot starts); keeps Y
DUST_OK:
  LDA T0
  CMP #10
  BCC .do_p
  CMP #15
  BCS .do_p
  CPY #12
  BCC .do_p
  CPY #19
  BCC .do_n
.do_p:
  LDA T0
  CMP #11
  BNE .do_s
  CPY #4
  BCC .do_n
  CPY #27
  BCS .do_n
.do_s:
  CMP #15
  BNE .do_y
  CPY #15
  BEQ .do_n
.do_y:
  SEC
  RTS
.do_n:
  CLC
  RTS

; Y = column, T0 = row: C = 1 if a socket goes there; keeps Y
IS_SOCKET:
  PHA
  CPY #1
  BEQ .is_c
  CPY #29
  BNE .is_n
.is_c:
  LDA T0
  CMP #5
  BEQ .is_y
  CMP #19
  BEQ .is_y
.is_n:
  PLA
  CLC
  RTS
.is_y:
  PLA
  SEC
  RTS

; PTR2 = the dust map of the player playing
DUST_PTR:
  LDA #<DUSTB
  LDX CURP
  BEQ .dp_0
  LDA #<(DUSTB+DUSTROW)
.dp_0:
  STA PTR2
  LDA #>DUSTB
  STA PTR2+1
  RTS

; the dust left in MAP into the map of the player playing
PACK_DUST:
  JSR DUST_PTR
  LDA #3
  STA T0
  LDY #0                       ; byte of the dust map
.pd_r:
  LDX T0
  JSR ROW_PTRX
  STZ T1                       ; column
.pd_b:
  STZ T2
  LDX #8
.pd_k:
  PHY
  LDY T1
  LDA (PTR),Y
  PLY
  CMP #T_DUST
  BEQ .pd_1
  CMP #T_SOCK
  BEQ .pd_1
  CLC
  BRA .pd_s
.pd_1:
  SEC
.pd_s:
  ROL T2
  INC T1
  DEX
  BNE .pd_k
  LDA T2
  STA (PTR2),Y
  INY
  LDA T1
  CMP #32
  BNE .pd_b
  INC T0
  LDA T0
  CMP #22
  BNE .pd_r
  RTS

; X = row: PTR = its row of MAP (keeps X, Y)
ROW_PTRX:
  TXA
  STZ PTR
  LSR A
  ROR PTR
  LSR A
  ROR PTR
  LSR A
  ROR PTR
  CLC
  ADC #>MAP
  STA PTR+1
  RTS

; T6 = column, T7 = row, A = tile: in MAP and on the screen (interrupt off)
PUT_TILE:
  PHA
  LDX T7
  JSR ROW_PTRX
  PLA
  LDY T6
  STA (PTR),Y
  PHA
  LDX T7
  LDY T6
  JSR NT_XY
  PLA
  STA VDATA
  RTS

; T6 = column, T7 = row: A = the tile of MAP there (Y = column)
GET_TILE:
  LDX T7
  JSR ROW_PTRX
  LDY T6
  LDA (PTR),Y
  RTS

; A = tile: C = 1 if the robot and the bunnies can go there
CAN_GO:
  CMP #T_FLOOR
  BEQ .cg_y
  CMP #T_DUST
  BEQ .cg_y
  CMP #T_SOCK
  BEQ .cg_y
  CLC
  RTS
.cg_y:
  SEC
  RTS

; A = colour (edge x 16 + fill): the furniture tiles in the three thirds
WALL_COLS:
  STA T5
  LDX #0
.wc_t:
  LDA #<(T_WALL*8)
  STA VREG
  LDA WALLHI,X
  STA VREG
  LDY #128
  LDA T5
.wc_b:
  STA VDATA
  NOP
  NOP
  DEY
  BNE .wc_b
  INX
  CPX #3
  BNE .wc_t
  RTS

; the sockets: bright and dim in turn
SOCK_BLINK:
  LDA SOCKBL
  EOR #1
  STA SOCKBL
  LDA #$F1
  LDY SOCKBL
  BEQ .sb_c
  LDA #$51
.sb_c:
  STA T5
  LDX #0
.sb_t:
  LDA #<(T_SOCK*8)
  STA VREG
  LDA SOCKHI,X
  STA VREG
  LDY #8
  LDA T5
.sb_b:
  STA VDATA
  NOP
  NOP
  DEY
  BNE .sb_b
  INX
  CPX #3
  BNE .sb_t
  RTS

; the room is clean: the furniture flashes white
FLASH:
  LDA GT
  AND #15
  BNE .fl_r
  LDA GT
  AND #16
  BEQ .fl_room
  LDA #$F1
  JMP WALL_COLS
.fl_room:
  LDX ROOM
  LDA ROOM_COL,X
  JMP WALL_COLS
.fl_r:
  RTS

; row 17: the name of a new room, else READY!
MSG_ROOM:
  LDA SHOWN
  BNE .mr_n
  LDA #<TXT_READY
  STA TP
  LDA #>TXT_READY
  STA TP+1
  JMP PRINT
.mr_n:
  LDX ROOM
  LDA RNAME_LO,X
  STA PTR
  LDA RNAME_HI,X
  STA PTR+1
  LDY #0
.mr_l:
  LDA (PTR),Y
  BEQ .mr_c
  INY
  BRA .mr_l
.mr_c:
  STY T0
  LDA #31
  SEC
  SBC T0
  LSR A
  TAY
  LDX #17
  JSR NT_XY
  LDY #0
.mr_p:
  LDA (PTR),Y
  BEQ .mr_r
  STA VDATA
  INY
  BRA .mr_p
.mr_r:
  RTS

MSG_CLEAR:
  LDX #17
  ; fall into PUT_MAPROW
; X = row: the row of MAP to the name table again (interrupt off)
PUT_MAPROW:
  PHX
  LDY #0
  JSR NT_XY
  PLX
  JSR ROW_PTRX
  LDY #0
.pm_c:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #32
  BNE .pm_c
  RTS


; ===============================================================
;  THE START OF A ROOM (or of a life in it)
; ===============================================================
SET_LEVEL:                     ; speeds by pairs of rooms, faster in the next rounds
  LDA LOOPN
  ASL A
  STA T0
  LDA ROOM
  LSR A
  CLC
  ADC T0
  CMP #6
  BCC .sl_x
  LDA #5
.sl_x:
  STA LEVEL
  RTS

ROOM_INIT:
  LDA #124                     ; the robot under the basket, going left
  STA RX
  STA RY
  LDA #2
  STA RDIR
  LDA #$FF
  STA RWANT
  STZ RACC
  STZ RPAUSE
  STZ RMOVE
  STZ TURBO
  STZ TURBO+1
  STZ EATN
  STZ PHASE
  STZ CHASE
  LDA PH_L
  STA PHT
  LDA PH_H
  STA PHT+1
  STZ RELT
  STZ LDOTS
  STZ FUZZS
  STZ CATON
  LDA #0                       ; the first cat after ~11 s
  STA CATT
  LDA #3
  STA CATT+1
  STZ BONT
  STZ FREEZE
  STZ SPRROT
  LDX #NB-1
.ri_b:
  LDA BX0,X
  STA B_X,X
  LDA BY0,X
  STA B_Y,X
  LDA BD0,X
  STA B_D,X
  LDA BM0,X
  STA B_M,X
  STZ B_F,X
  STZ B_ACC,X
  STZ B_REV,X
  STZ B_HT,X
  DEX
  BPL .ri_b
  RTS


; ===============================================================
;  THE ROBOT
; ===============================================================
ROBOT:
  STZ RMOVE
  LDA JOYC                     ; the joystick books the next turn
  AND #$0F
  BEQ .ro_s
  LDX #3
.ro_j:
  LSR A
  BCS .ro_jd
  DEX
  BPL .ro_j
.ro_jd:
  LDA JOYDIR,X
  STA RWANT
  EOR #2                       ; back: at once
  CMP RDIR
  BNE .ro_s
  LDA RWANT
  STA RDIR
  LDA #$FF
  STA RWANT
.ro_s:
  LDA RPAUSE                   ; it stops a moment on the dust
  BEQ .ro_go
  DEC RPAUSE
  RTS
.ro_go:
  LDX LEVEL
  LDA TURBO
  ORA TURBO+1
  BEQ .ro_n
  LDA RSPT_L,X
  LDY #1
  BRA .ro_a
.ro_n:
  LDA RSPN_L,X
  LDY #1
.ro_a:
  CLC
  ADC RACC
  STA RACC
  TYA
  ADC #0
  STA NSTEP
.ro_l:
  JSR R_STEP
  LDA GSTATE
  BNE .ro_r
  DEC NSTEP
  BNE .ro_l
.ro_r:
  RTS

; one pixel: at the centre of a tile the booked turn, or a stop at the furniture
R_STEP:
  LDA RX
  AND #7
  CMP #4
  BNE .rs_mv
  LDA RY
  AND #7
  CMP #4
  BNE .rs_mv
  LDA RWANT
  BMI .rs_ah
  JSR R_PASS
  BCC .rs_ah
  LDA RWANT
  STA RDIR
  LDA #$FF
  STA RWANT
.rs_ah:
  LDA RDIR
  JSR R_PASS
  BCS .rs_mv
  RTS
.rs_mv:
  LDX RDIR
  LDA RX
  CLC
  ADC DX_T,X
  STA RX
  LDA RY
  CLC
  ADC DY_T,X
  STA RY
  LDA #1
  STA RMOVE
  LDA RX
  AND #7
  CMP #4
  BNE .rs_r
  LDA RY
  AND #7
  CMP #4
  BNE .rs_r
  JMP R_ARRIVE
.rs_r:
  RTS

; A = direction: C = 1 if the robot can go to the tile there (not the cat)
R_PASS:
  TAX
  LDA RX
  LSR A
  LSR A
  LSR A
  CLC
  ADC DX_T,X
  AND #31
  STA T6
  LDA RY
  LSR A
  LSR A
  LSR A
  CLC
  ADC DY_T,X
  STA T7
  JSR GET_TILE
  JSR CAN_GO
  BCC .rp_r
  LDA CATON
  BEQ .rp_y
  LDA T6
  CMP CATC
  BNE .rp_y
  LDA T7
  CMP CATR
  BNE .rp_y
  CLC
  RTS
.rp_y:
  SEC
.rp_r:
  RTS

; the robot reached the centre of a tile: dust, a socket, the lost thing
R_ARRIVE:
  LDA RX
  LSR A
  LSR A
  LSR A
  STA T6
  LDA RY
  LSR A
  LSR A
  LSR A
  STA T7
  JSR GET_TILE
  CMP #T_DUST
  BEQ .ra_d
  CMP #T_SOCK
  BEQ .ra_s
  JMP .ra_b
.ra_d:
  LDA #T_FLOOR
  JSR PUT_TILE
  LDA #1
  STA RPAUSE
  LDA #$10
  LDY #0
  JSR ADD_PTS
  LDA DUSTSW                   ; the two sounds of the dust take turns
  EOR #1
  STA DUSTSW
  CLC
  ADC #W_DUST1
  LDX #2
  JSR SFX_WHISTLE
  BRA .ra_c
.ra_s:
  LDA #T_FLOOR
  JSR PUT_TILE
  LDA #3
  STA RPAUSE
  LDA #$50
  LDY #0
  JSR ADD_PTS
  JSR TURBO_ON
  LDA #W_SOCK
  LDX #2
  JSR SFX_WHISTLE
.ra_c:
  STZ RELT
  LDA LDOTS
  CMP #255
  BEQ .ra_c1
  INC LDOTS
.ra_c1:
  LDA DEATEN
  CMP #255
  BEQ .ra_c2
  INC DEATEN
.ra_c2:
  LDA DEATEN                   ; the lost thing at 70 and 170
  LDX BONUSN
  CMP BONUS_AT,X
  BNE .ra_c3
  INC BONUSN
  LDA #150
  STA BONT
.ra_c3:
  INC DUSTN
  BNE .ra_c4
  INC DUSTN+1
.ra_c4:
  LDA NDUST                    ; the last one: the room is clean
  BNE .ra_c5
  DEC NDUST+1
.ra_c5:
  DEC NDUST
  LDA NDUST
  ORA NDUST+1
  BNE .ra_b
  LDA #3
  STA GSTATE
  LDA #120
  STA GT
  RTS
.ra_b:
  LDA BONT                     ; the lost thing under the basket
  BEQ .ra_r
  LDA T6
  CMP #15
  BNE .ra_r
  LDA T7
  CMP #15
  BNE .ra_r
  STZ BONT
  LDX ROOM
  LDY ITEM_M,X
  LDA #0
  JSR ADD_PTS
  LDA #W_BONUS
  LDX #2
  JMP SFX_WHISTLE
.ra_r:
  RTS

; a socket: the turbo, the bunnies in the room turn pale and back
TURBO_ON:
  LDX LEVEL
  LDA TDUR_L,X
  STA TURBO
  LDA TDUR_H,X
  STA TURBO+1
  STZ EATN
  LDX #NB-1
.to_b:
  LDA B_M,X
  CMP #M_RUN
  BNE .to_n
  LDA #1
  STA B_F,X
  STA B_REV,X
.to_n:
  DEX
  BPL .to_b
  RTS

; a life lost now: A = why (the bunny + 1)
LOSE_NOW:
  STA DEATH
  INC LOSTN
  LDA #1
  STA GSTATE
  LDA #150
  STA GT
  STZ TURBO
  STZ TURBO+1
  LDA #W_DOWN
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  TIMERS: the turbo, round and hunt, the bunnies coming out,
;  the lost thing, the cat
; ===============================================================
TIMERS:
  LDA TURBO
  ORA TURBO+1
  BEQ .ti_ph
  LDA TURBO
  BNE .ti_t1
  DEC TURBO+1
.ti_t1:
  DEC TURBO
  LDA TURBO
  ORA TURBO+1
  BNE .ti_rel
  LDX #NB-1                    ; the turbo is over
.ti_tf:
  STZ B_F,X
  DEX
  BPL .ti_tf
  BRA .ti_rel
.ti_ph:
  LDA PHASE                    ; (the last phase hunts for ever)
  CMP #5
  BCS .ti_rel
  LDA PHT
  BNE .ti_p1
  DEC PHT+1
.ti_p1:
  DEC PHT
  LDA PHT
  ORA PHT+1
  BNE .ti_rel
  INC PHASE
  LDA CHASE
  EOR #1
  STA CHASE
  LDX PHASE
  LDA PH_L,X
  STA PHT
  LDA PH_H,X
  STA PHT+1
  LDX #NB-1                    ; a new phase: the bunnies in the room turn back
.ti_pr:
  LDA B_M,X
  CMP #M_RUN
  BNE .ti_pn
  LDA #1
  STA B_REV,X
.ti_pn:
  DEX
  BPL .ti_pr
.ti_rel:
  JSR RELEASE
  LDA BONT                     ; the lost thing stays ~10 s
  BEQ .ti_c
  LDA FRAME_CNT
  AND #3
  BNE .ti_c
  DEC BONT
.ti_c:
  JMP CAT

; the next bunny in the basket comes out: after its dust, or after 4 s without dust
RELEASE:
  LDX #NB-1                    ; the eyes resting in the basket: out when their time is up
.rl_h:
  LDA B_HT,X
  BEQ .rl_hn
  DEC B_HT,X
  BNE .rl_hn
  LDA #M_LEAVE
  STA B_M,X
.rl_hn:
  DEX
  BPL .rl_h
  LDA RELT
  CMP #255
  BEQ .rl_0
  INC RELT
.rl_0:
  LDX #1
.rl_l:
  LDA B_M,X
  CMP #M_HOUSE
  BNE .rl_n
  LDA B_HT,X                   ; resting after the eyes: not yet
  BEQ .rl_c
.rl_n:
  INX
  CPX #NB
  BNE .rl_l
  RTS
.rl_c:
  LDA LDOTS
  CMP REL_D,X
  BCS .rl_go
  LDA RELT
  CMP #240
  BCC .rl_r
.rl_go:
  LDA #M_LEAVE
  STA B_M,X
  STZ RELT
.rl_r:
  RTS

; the cat of the house: from the bedroom, now and then, 4 s in a corridor far from the robot
CAT:
  LDA LOOPN
  BNE .ca_ok
  LDA ROOM
  CMP #2
  BCS .ca_ok
.ca_x:
  RTS
.ca_ok:
  LDA CATON
  BEQ .ca_t
  DEC CATD
  BNE .ca_x
  STZ CATON
  RTS
.ca_t:
  LDA CATT
  BNE .ca_t1
  DEC CATT+1
.ca_t1:
  DEC CATT
  LDA CATT
  ORA CATT+1
  BNE .ca_x
  JSR NEXT_RND                 ; the next one in 13-17 s
  STA CATT
  LDA #3
  STA CATT+1
  LDA #12                      ; a place: 12 tries
  STA T5
.ca_try:
  JSR NEXT_RND
  AND #31
  BEQ .ca_n
  CMP #30
  BCS .ca_n
  STA T6
  JSR NEXT_RND
  AND #31
  CMP #19
  BCS .ca_n
  ADC #3
  STA T7
  CMP #11                      ; not the passage, not the basket
  BEQ .ca_n
  CMP #10
  BCC .ca_f
  CMP #15
  BCS .ca_f
  LDA T6
  CMP #12
  BCC .ca_f
  CMP #19
  BCC .ca_n
.ca_f:
  LDA RX                       ; far from the robot: 8 tiles or more
  LSR A
  LSR A
  LSR A
  SEC
  SBC T6
  BPL .ca_d1
  EOR #$FF
  INC A
.ca_d1:
  STA T4
  LDA RY
  LSR A
  LSR A
  LSR A
  SEC
  SBC T7
  BPL .ca_d2
  EOR #$FF
  INC A
.ca_d2:
  CLC
  ADC T4
  CMP #8
  BCC .ca_n
  JSR GET_TILE
  CMP #T_FLOOR
  BEQ .ca_put
  CMP #T_DUST
  BEQ .ca_put
.ca_n:
  DEC T5
  BNE .ca_try
.ca_r:
  RTS
.ca_put:
  LDA T6
  STA CATC
  LDA T7
  STA CATR
  LDA #240
  STA CATD
  LDA #1
  STA CATON
  LDA #W_MEOW
  LDX #2
  JMP SFX_WHISTLE

; the sound of the motor on the left chip while the robot moves (siren in turbo, eyes going home)
MOTOR:
  LDA RMOVE
  BEQ .mo_r
  LDA WH_ID
  BNE .mo_r
  LDX #NB-1
.mo_e:
  LDA B_M,X
  CMP #M_EYES
  BEQ .mo_eyes
  CMP #M_ENTER
  BEQ .mo_eyes
  DEX
  BPL .mo_e
  LDA TURBO
  ORA TURBO+1
  BEQ .mo_hum
  LDA #W_SIREN
  BRA .mo_p
.mo_eyes:
  LDA #W_EYES
  BRA .mo_p
.mo_hum:
  LDA #W_HUM
.mo_p:
  LDX #0
  JMP SFX_WHISTLE
.mo_r:
  RTS


; ===============================================================
;  THE DUST BUNNIES: one pixel at a time; at the centre of a tile
;  each one takes the open way (never back) nearest to its target:
;  its corner while they go round, its own aim while they hunt;
;  scared, a random way; the eyes go back to the basket
; ===============================================================
BUNNIES:
  LDX #NB-1
.bu_l:
  STX CB
  JSR B_SPEED                  ; A = fraction, Y = whole pixels
  CLC
  ADC B_ACC,X
  STA B_ACC,X
  TYA
  ADC #0
  BEQ .bu_n
  STA NSTEP
.bu_s:
  LDX CB
  JSR B_STEP
  DEC NSTEP
  BNE .bu_s
.bu_n:
  LDX CB
  DEX
  BPL .bu_l
  RTS

; X = bunny: its speed (A = fraction, Y = whole pixels); keeps X
B_SPEED:
  LDA B_M,X
  CMP #M_RUN
  BEQ .sp_run
  CMP #M_EYES
  BEQ .sp_eye
  LDA #$C0                     ; in the basket and through its door
  LDY #0
  RTS
.sp_eye:
  LDA #$80
  LDY #2
  RTS
.sp_run:
  LDY LEVEL
  LDA B_F,X
  BEQ .sp_n
  LDA BSPF_L,Y                 ; scared
  LDY #0
  RTS
.sp_n:
  LDA B_Y,X                    ; under the doors (row 11, the ends): slow
  CMP #92
  BNE .sp_nt
  LDA B_X,X
  CMP #40
  BCC .sp_tun
  CMP #208
  BCC .sp_nt
.sp_tun:
  LDA BSPT_L,Y
  LDY #0
  RTS
.sp_nt:
  LDA BSPN_H,Y
  STA WAYS                     ; (free here)
  LDA BSPN_L,Y
  CPX #2                       ; Fuzz dashes when it sees the robot
  BNE .sp_1
  LDY FUZZS
  BEQ .sp_1
  CLC
  ADC #$30
  BCC .sp_1
  INC WAYS
.sp_1:
  LDY WAYS
  RTS

; X = bunny: one pixel
B_STEP:
  LDA B_M,X
  BEQ .st_house
  CMP #M_LEAVE
  BEQ .st_leave
  CMP #M_ENTER
  BNE .st_room
  JMP .st_enter
.st_room:
  LDA B_X,X                    ; in the room: a choice at the centre of a tile
  AND #7
  CMP #4
  BNE .st_mv
  LDA B_Y,X
  AND #7
  CMP #4
  BNE .st_mv
  JSR B_CHOOSE
  LDX CB
  LDA B_M,X
  CMP #M_ENTER
  BEQ .st_r
.st_mv:
  LDY B_D,X
  LDA B_X,X
  CLC
  ADC DX_T,Y
  STA B_X,X
  LDA B_Y,X
  CLC
  ADC DY_T,Y
  STA B_Y,X
.st_r:
  RTS
.st_house:                     ; up and down in the basket
  LDA B_Y,X
  CMP #97
  BCS .sh_1
  LDA #1
  STA B_D,X
.sh_1:
  LDA B_Y,X
  CMP #104
  BCC .sh_2
  LDA #3
  STA B_D,X
.sh_2:
  LDA B_D,X
  CMP #1
  BEQ .sh_d
  DEC B_Y,X
  RTS
.sh_d:
  INC B_Y,X
  RTS
.st_leave:                     ; to the middle, then up through the door
  LDA B_X,X
  CMP #124
  BEQ .lv_y
  BCC .lv_r
  DEC B_X,X
  LDA #2
  STA B_D,X
  RTS
.lv_r:
  INC B_X,X
  LDA #0
  STA B_D,X
  RTS
.lv_y:
  LDA B_Y,X
  CMP #76
  BEQ .lv_out
  DEC B_Y,X
  LDA #3
  STA B_D,X
  RTS
.lv_out:
  LDA #M_RUN
  STA B_M,X
  LDA #2
  STA B_D,X
  STZ B_REV,X
  RTS
.st_enter:                     ; the eyes go down into the basket, then out again
  LDA B_Y,X
  CMP #100
  BEQ .en_in
  INC B_Y,X
  LDA #1
  STA B_D,X
  RTS
.en_in:                        ; home: a rest in the basket (RELEASE lets it out)
  LDA #M_HOUSE
  STA B_M,X
  LDA #PEN_T
  STA B_HT,X
  STZ B_F,X
  RTS

; X = CB at the centre of a tile: its new direction
B_CHOOSE:
  LDA B_X,X
  LSR A
  LSR A
  LSR A
  STA TMPX
  LDA B_Y,X
  LSR A
  LSR A
  LSR A
  STA TMPY
  LDA B_M,X                    ; the eyes at the door: in
  CMP #M_EYES
  BNE .ch_r
  LDA TMPX
  CMP #15
  BNE .ch_r
  LDA TMPY
  CMP #9
  BNE .ch_r
  LDA #M_ENTER
  STA B_M,X
  LDA #1
  STA B_D,X
  RTS
.ch_r:
  LDA B_REV,X                  ; a new phase or the turbo: back
  BEQ .ch_t
  STZ B_REV,X
  LDA B_D,X
  EOR #2
  STA B_D,X
  RTS
.ch_t:
  JSR B_TARGET                 ; TGTX / TGTY, C = 1 for a random way
  PHP
  STZ WAYS
  LDA #$FF
  STA BESTD
  STA BEST
  STA BEST+1
  LDY #0
.ch_k:
  LDA PREF,Y                   ; up, left, down, right
  STA T3
  LDX CB
  LDA B_D,X
  EOR #2
  CMP T3
  BEQ .ch_n
  LDX T3
  LDA TMPX
  CLC
  ADC DX_T,X
  AND #31
  STA T6
  LDA TMPY
  CLC
  ADC DY_T,X
  STA T7
  PHY
  JSR GET_TILE
  JSR CAN_GO
  PLY
  BCC .ch_n
  LDX T3
  LDA BITS,X
  TSB WAYS
  LDA T6                       ; the square of the distance to the target
  SEC
  SBC TGTX
  BPL .ch_x
  EOR #$FF
  INC A
.ch_x:
  CMP #64
  BCC .ch_x1
  LDA #63
.ch_x1:
  TAX
  LDA SQ_LO,X
  STA T4
  LDA SQ_HI,X
  STA T5
  LDA T7
  SEC
  SBC TGTY
  BPL .ch_y
  EOR #$FF
  INC A
.ch_y:
  CMP #64
  BCC .ch_y1
  LDA #63
.ch_y1:
  TAX
  LDA SQ_LO,X
  CLC
  ADC T4
  STA T4
  LDA SQ_HI,X
  ADC T5
  STA T5
  LDA T4
  CMP BEST
  LDA T5
  SBC BEST+1
  BCS .ch_n
  LDA T4
  STA BEST
  LDA T5
  STA BEST+1
  LDA T3
  STA BESTD
.ch_n:
  INY
  CPY #4
  BEQ .ch_e
  JMP .ch_k
.ch_e:
  PLP
  BCC .ch_best
  LDA WAYS                     ; a random way among the open ones
  BEQ .ch_back
  JSR NEXT_RND
  AND #3
  TAY
.ch_try:
  LDA BITS,Y
  AND WAYS
  BNE .ch_dir
  INY
  TYA
  AND #3
  TAY
  BRA .ch_try
.ch_dir:
  TYA
  BRA .ch_set
.ch_best:
  LDA BESTD
  BPL .ch_set
.ch_back:
  LDX CB                       ; (no way: back)
  LDA B_D,X
  EOR #2
.ch_set:
  LDX CB
  STA B_D,X
  RTS

; X = CB: TGTX / TGTY = where it goes; C = 1 for a random way
B_TARGET:
  LDA B_M,X
  CMP #M_EYES
  BNE .bt_1
  LDA #15                      ; the eyes: the door of the basket
  STA TGTX
  LDA #9
  STA TGTY
  CLC
  RTS
.bt_1:
  LDA B_F,X                    ; scared: at random
  BEQ .bt_2
  SEC
  RTS
.bt_2:
  LDA CHASE
  BNE .bt_ch
  LDA CORNX,X                  ; going round: its corner
  STA TGTX
  LDA CORNY,X
  STA TGTY
  CLC
  RTS
.bt_ch:
  JSR ROBOT_TILE
  CPX #1
  BEQ .bt_lint
  CPX #2
  BEQ .bt_fuzz
  CPX #3
  BEQ .bt_grit
  CLC                          ; Fluff: the robot
  RTS
.bt_lint:                      ; Lint: 4 tiles ahead of the robot
  LDY RDIR
  LDA DX_T,Y
  ASL A
  ASL A
  CLC
  ADC TGTX
  STA TGTX
  LDA DY_T,Y
  ASL A
  ASL A
  CLC
  ADC TGTY
  STA TGTY
  CLC
  RTS
.bt_fuzz:                      ; Fuzz: the robot if it sees it, else at random
  STZ FUZZS
  JSR FUZZ_SEES
  BCC .bt_fr
  LDA #1
  STA FUZZS
  CLC
  RTS
.bt_fr:
  SEC
  RTS
.bt_grit:                      ; Grit: the nearest socket left
  LDA #$FF
  STA T4
  LDY #3
.bg_s:
  LDA SOCKC,Y
  STA T6
  LDA SOCKR,Y
  STA T7
  PHY
  JSR GET_TILE
  PLY
  CMP #T_SOCK
  BNE .bg_n
  LDA SOCKC,Y
  SEC
  SBC TMPX
  BPL .bg_1
  EOR #$FF
  INC A
.bg_1:
  STA T5
  LDA SOCKR,Y
  SEC
  SBC TMPY
  BPL .bg_2
  EOR #$FF
  INC A
.bg_2:
  CLC
  ADC T5
  CMP T4
  BCS .bg_n
  STA T4
  LDA SOCKC,Y
  STA T2
  LDA SOCKR,Y
  STA T3
.bg_n:
  DEY
  BPL .bg_s
  LDA T4
  CMP #$FF
  BEQ .bg_none
  LDA T2
  STA TGTX
  LDA T3
  STA TGTY
  CLC
  RTS
.bg_none:                      ; no socket: the robot from afar, its corner when near
  LDA TGTX
  SEC
  SBC TMPX
  BPL .bg_3
  EOR #$FF
  INC A
.bg_3:
  STA T5
  LDA TGTY
  SEC
  SBC TMPY
  BPL .bg_4
  EOR #$FF
  INC A
.bg_4:
  CLC
  ADC T5
  CMP #9
  BCS .bg_r
  LDA CORNX+3
  STA TGTX
  LDA CORNY+3
  STA TGTY
.bg_r:
  CLC
  RTS

; TGTX / TGTY = the tile of the robot
ROBOT_TILE:
  LDA RX
  LSR A
  LSR A
  LSR A
  STA TGTX
  LDA RY
  LSR A
  LSR A
  LSR A
  STA TGTY
  RTS

; Fuzz at TMPX / TMPY, the robot at TGTX / TGTY: C = 1 if they are on one row or
; column with nothing in between
FUZZ_SEES:
  LDA TMPY
  CMP TGTY
  BNE .fs_col
  LDA TMPX                     ; one row: T2 = from, T3 = to
  STA T2
  LDA TGTX
  STA T3
  CMP T2
  BCS .fs_r
  LDA T2
  STA T3
  LDA TGTX
  STA T2
.fs_r:
  LDA T2
  STA T6
  LDA TMPY
  STA T7
  JSR GET_TILE
  JSR CAN_GO
  BCC .fs_no
  INC T2
  LDA T3
  CMP T2
  BCS .fs_r
  SEC
  RTS
.fs_col:
  LDA TMPX
  CMP TGTX
  BNE .fs_no
  LDA TMPY                     ; one column
  STA T2
  LDA TGTY
  STA T3
  CMP T2
  BCS .fs_c
  LDA T2
  STA T3
  LDA TGTY
  STA T2
.fs_c:
  LDA TMPX
  STA T6
  LDA T2
  STA T7
  JSR GET_TILE
  JSR CAN_GO
  BCC .fs_no
  INC T2
  LDA T3
  CMP T2
  BCS .fs_c
  SEC
  RTS
.fs_no:
  CLC
  RTS


; ===============================================================
;  THE ROBOT MEETS A BUNNY: sucked up if scared, else a life
; ===============================================================
HIT:
  LDX #NB-1
.hi_l:
  LDA B_M,X
  CMP #M_RUN
  BNE .hi_n
  LDA B_X,X
  SEC
  SBC RX
  CLC
  ADC #6
  CMP #12
  BCS .hi_n
  LDA B_Y,X
  SEC
  SBC RY
  CLC
  ADC #6
  CMP #12
  BCS .hi_n
  LDA B_F,X
  BEQ .hi_dead
  LDA #M_EYES                  ; sucked up: only the eyes are left
  STA B_M,X
  STZ B_F,X
  STX FRZB
  LDY EATN
  TYA
  ASL A
  ASL A
  CLC
  ADC #PT_PTS
  STA FRZP
  LDA EAT_M,Y
  TAY
  LDA #0
  JSR ADD_PTS
  LDA EATN
  CMP #3
  BCS .hi_e
  INC EATN
.hi_e:
  LDA #30
  STA FREEZE
  LDA #W_EATB
  LDX #2
  JMP SFX_WHISTLE
.hi_dead:
  TXA
  INC A
  JMP LOSE_NOW
.hi_n:
  DEX
  BPL .hi_l
  RTS


; ===============================================================
;  SPRITES: the robot first, then the bunnies, the cat and the lost
;  thing in an order that turns every frame (more than 4 on a line
;  flicker instead of vanishing)
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA GSTATE
  CMP #1
  BNE .bs_rob
  LDA GT                       ; a life lost: first everything stops, then the robot goes off
  CMP #110
  BCS .bs_rob
  CMP #30
  BCC .bs_end
  LDA #109
  SEC
  SBC GT
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #4
  BCC .bs_d
  LDA #3
.bs_d:
  ASL A
  ASL A
  CLC
  ADC #PT_RDIE
  STA ON
  BRA .bs_rc
.bs_rob:
  LDA RDIR
  ASL A
  ASL A
  ASL A
  STA T0
  LDA FRAME_CNT                ; the brushes turn
  AND #4
  ORA T0
  CLC
  ADC #PT_ROBOT
  STA ON
.bs_rc:
  LDA #15
  STA OC
  LDA RX
  LDY RY
  JSR SPR_XY
  LDA GSTATE                   ; the others: while playing and just after a life is lost
  BEQ .bs_o
  CMP #1
  BNE .bs_end
  LDA GT
  CMP #110
  BCC .bs_end
.bs_o:
  LDA #0
  STA T7
.bs_k:
  LDA SPRROT
  CLC
  ADC T7
  CMP #6
  BCC .bs_k1
  SBC #6
.bs_k1:
  JSR SPR_ONE
  INC T7
  LDA T7
  CMP #6
  BNE .bs_k
  INC SPRROT
  LDA SPRROT
  CMP #6
  BCC .bs_end
  STZ SPRROT
.bs_end:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; A = 0-3 a bunny, 4 the cat, 5 the lost thing
SPR_ONE:
  CMP #4
  BCC .so_b
  BEQ .so_cat
  LDA BONT
  BEQ .so_r
  LDX ROOM
  TXA
  ASL A
  ASL A
  CLC
  ADC #PT_ITEM
  STA ON
  LDA ITEM_COL,X
  STA OC
  LDA #124
  TAY
  JMP SPR_XY
.so_cat:
  LDA CATON
  BEQ .so_r
  LDA FRAME_CNT
  AND #16
  LSR A
  LSR A
  CLC
  ADC #PT_CAT
  STA ON
  LDA #14
  STA OC
  LDA CATR
  ASL A
  ASL A
  ASL A
  ORA #4
  TAY
  LDA CATC
  ASL A
  ASL A
  ASL A
  ORA #4
  JMP SPR_XY
.so_r:
  RTS
.so_b:
  TAX
  LDA FREEZE                   ; just sucked up: its points
  BEQ .so_m
  CPX FRZB
  BNE .so_m
  LDA FRZP
  STA ON
  LDA #7
  STA OC
  BRA .so_xy
.so_m:
  LDA B_M,X
  CMP #M_EYES
  BCC .so_f
  LDA B_D,X                    ; the eyes (going home or into the basket)
  ASL A
  ASL A
  CLC
  ADC #PT_EYES
  STA ON
  LDA #15
  STA OC
  BRA .so_xy
.so_f:
  LDA FRAME_CNT
  AND #8
  LSR A
  STA T0
  LDA B_F,X
  BEQ .so_n
  LDA T0                       ; scared: pale blue, white when the turbo is ending
  CLC
  ADC #PT_SCARED
  STA ON
  LDA #5
  STA OC
  LDA TURBO+1
  BNE .so_xy
  LDA TURBO
  CMP #120
  BCS .so_xy
  LDA FRAME_CNT
  AND #8
  BEQ .so_xy
  LDA #15
  STA OC
  BRA .so_xy
.so_n:
  LDA B_D,X
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_BUN
  STA ON
  LDA BCOL,X
  STA OC
.so_xy:
  LDA B_X,X
  LDY B_Y,X
  ; fall into SPR_XY
; A = x, Y = y of the centre, ON / OC: one sprite (left of the screen: the early clock); keeps X
SPR_XY:
  SEC
  SBC #8
  STA OX
  BCS .sx_y
  CLC
  ADC #32
  STA OX
  LDA OC
  ORA #$80
  STA OC
.sx_y:
  TYA
  SEC
  SBC #9
  STA OY
  ; fall into ADD_SPR
; OX, OY, ON, OC: one sprite more (keeps X)
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
;  SCREEN: VRAM, texts, sprites, sound (from wormer)
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
SC_COL:     .byte 4,26                         ; score of player 1 / 2: column on row 0
BITS:       .byte 1,2,4,8,16,32,64,128
JOYDIR:     .byte 0,2,1,3                      ; joystick bits right, left, down, up -> direction
DX_T:       .byte 1,0,$FF,0                    ; the four directions: right, down, left, up
DY_T:       .byte 0,1,0,$FF
PREF:       .byte 3,2,1,0                      ; the bunnies try up, left, down, right
; speeds (fraction of a pixel a frame, by speed group 0-5)
RSPN_L:     .byte $20,$28,$30,$38,$40,$40      ; the robot: 1 + n/256
RSPT_L:     .byte $38,$40,$48,$50,$50,$50      ;   in turbo
BSPN_L:     .byte $F0,$08,$18,$28,$38,$40      ; the bunnies (8.8)
BSPN_H:     .byte 0,1,1,1,1,1
BSPF_L:     .byte $A0,$A8,$B0,$B8,$C0,$C0      ;   scared: n/256
BSPT_L:     .byte $80,$88,$90,$98,$A0,$A0      ;   under the doors: n/256
TDUR_L:     .byte <420,<360,<300,<240,<180,<120   ; frames of turbo
TDUR_H:     .byte >420,>360,>300,>240,>180,>120
PH_L:       .byte <420,<1200,<420,<1200,<300,0    ; going round / hunting
PH_H:       .byte >420,>1200,>420,>1200,>300,0
REL_D:      .byte 0,0,30,60                    ; dust before each bunny comes out
BONUS_AT:   .byte 70,170,0                     ; dust eaten when a lost thing shows up
CORNX:      .byte 28,2,30,0                    ; the corners they go round to
CORNY:      .byte 0,0,24,24
BX0:        .byte 124,124,108,140              ; where they start: Fluff out, the others in the basket
BY0:        .byte 76,100,100,100
BD0:        .byte 2,3,3,1
BM0:        .byte M_RUN,M_HOUSE,M_HOUSE,M_HOUSE
BCOL:       .byte 8,13,7,10                    ; red, pink, cyan, orange
SOCKC:      .byte 1,29,1,29                    ; the sockets
SOCKR:      .byte 5,5,19,19
EAT_M:      .byte $02,$04,$08,$16              ; a bunny: 200 400 800 1600 (BCD hundreds)
ITEM_M:     .byte $01,$03,$05,$07,$10,$20,$30,$50   ; the lost things: 100 ... 5000
ITEM_COL:   .byte 10,14,13,11,10,9,14,11
; the rooms: furniture colours (edge x 16 + fill) and names
ROOM_COL:   .byte $74,$96,$FD,$F5,$BA,$32,$FE,$AC
WALLHI:     .byte $63,$6B,$73                  ; colours of the furniture tiles in the three thirds (write)
SOCKHI:     .byte $63,$6B,$73
RNAME_LO:   .byte <RN0,<RN1,<RN2,<RN3,<RN4,<RN5,<RN6,<RN7
RNAME_HI:   .byte >RN0,>RN1,>RN2,>RN3,>RN4,>RN5,>RN6,>RN7
RN0:        .byte "KITCHEN",0
RN1:        .byte "LIVING ROOM",0
RN2:        .byte "BEDROOM",0
RN3:        .byte "BATHROOM",0
RN4:        .byte "STUDY",0
RN5:        .byte "KIDS ROOM",0
RN6:        .byte "GARAGE",0
RN7:        .byte "ATTIC",0

; title: the robot, the four bunnies (sprite Y, X, pattern, colour)
TITLE_NS = 5
TITLE_SY:   .byte 23,83,99,115,131
TITLE_SX:   .byte 40,40,40,40,40
TITLE_SN:   .byte PT_ROBOT+24,PT_BUN,PT_BUN,PT_BUN,PT_BUN
TITLE_SC:   .byte 15,8,13,7,10

TXT_ROOMH:  .byte "ROOM "
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
  .byte 9,3,"THE ROBOT CLEANS THE HOUSE",0
  .byte 10,4,T_DUST," 10 POINTS  ",T_SOCK," 50 TURBO",0
  .byte 11,8,"FLUFF  FOLLOWS YOU",0
  .byte 13,8,"LINT   CUTS YOU OFF",0
  .byte 15,8,"FUZZ   DASHES ON SIGHT",0
  .byte 17,8,"GRIT   GUARDS SOCKETS",0
  .byte $FF
TXT_READY:
  .byte 17,13,"READY!",0,$FF
TXT_OVER:
  .byte 17,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 18,11,"PLAYER ",0,$FF

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
;  GRAPHICS, ROOMS AND SOUND TABLES (generated)
; ===============================================================
; ROBO VAC: generated by dev/gen_robo_vac.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_ROBOT = 0
PT_RDIE = 32
PT_BUN = 48
PT_SCARED = 80
PT_EYES = 88
PT_PTS = 104
PT_CAT = 120
PT_ITEM = 128
SPR_LEN = 1280
SPR_PAGES = 5
SPRITES:
  .byte $00,$00,$0F,$1F,$3F,$37,$77,$77,$77,$77,$37,$3F,$1F,$0F,$00,$00,$04,$0B,$E4,$B0,$B8,$B8,$BC,$A4,$A4,$BC,$B8,$B8,$B0,$E4,$0B,$04
  .byte $00,$00,$0F,$1F,$3F,$37,$77,$77,$77,$77,$37,$3F,$1F,$0F,$00,$00,$0A,$04,$EA,$B0,$B8,$B8,$BC,$A4,$A4,$BC,$B8,$B8,$B0,$EA,$04,$0A
  .byte $00,$03,$0F,$1F,$38,$3F,$3F,$3F,$3F,$20,$3F,$1E,$4E,$A3,$40,$40,$00,$C0,$F0,$F8,$1C,$FC,$FC,$FC,$FC,$04,$FC,$78,$72,$C5,$02,$02
  .byte $00,$03,$0F,$1F,$38,$3F,$3F,$3F,$3F,$20,$3F,$1E,$AE,$43,$A0,$00,$00,$C0,$F0,$F8,$1C,$FC,$FC,$FC,$FC,$04,$FC,$78,$75,$C2,$05,$00
  .byte $20,$D0,$27,$0D,$1D,$1D,$3D,$25,$25,$3D,$1D,$1D,$0D,$27,$D0,$20,$00,$00,$F0,$F8,$FC,$EC,$EE,$EE,$EE,$EE,$EC,$FC,$F8,$F0,$00,$00
  .byte $50,$20,$57,$0D,$1D,$1D,$3D,$25,$25,$3D,$1D,$1D,$0D,$57,$20,$50,$00,$00,$F0,$F8,$FC,$EC,$EE,$EE,$EE,$EE,$EC,$FC,$F8,$F0,$00,$00
  .byte $40,$40,$A3,$4E,$1E,$3F,$20,$3F,$3F,$3F,$3F,$38,$1F,$0F,$03,$00,$02,$02,$C5,$72,$78,$FC,$04,$FC,$FC,$FC,$FC,$1C,$F8,$F0,$C0,$00
  .byte $00,$A0,$43,$AE,$1E,$3F,$20,$3F,$3F,$3F,$3F,$38,$1F,$0F,$03,$00,$00,$05,$C2,$75,$78,$FC,$04,$FC,$FC,$FC,$FC,$1C,$F8,$F0,$C0,$00
  .byte $00,$00,$00,$07,$0F,$1F,$1F,$1F,$1F,$1F,$1F,$0F,$07,$00,$00,$00,$00,$00,$00,$E0,$F0,$F8,$F8,$F8,$F8,$F8,$F8,$F0,$E0,$00,$00,$00
  .byte $00,$08,$10,$20,$41,$07,$07,$0F,$2F,$47,$07,$01,$10,$01,$02,$00,$00,$40,$80,$08,$80,$E0,$E2,$F4,$F0,$E0,$E0,$82,$04,$08,$10,$00
  .byte $00,$00,$08,$02,$40,$10,$01,$03,$23,$01,$00,$40,$10,$04,$01,$00,$00,$40,$10,$04,$00,$00,$88,$C2,$C0,$80,$04,$00,$20,$08,$00,$00
  .byte $00,$00,$01,$00,$00,$00,$00,$20,$20,$00,$00,$00,$00,$01,$00,$00,$00,$00,$80,$00,$00,$00,$00,$04,$04,$00,$00,$00,$00,$80,$00,$00
  .byte $00,$00,$01,$01,$1F,$1F,$1C,$0C,$3F,$7F,$3F,$07,$07,$0E,$04,$08,$00,$00,$80,$80,$F8,$F8,$C8,$C0,$FC,$FE,$FC,$E0,$E0,$70,$20,$20
  .byte $00,$00,$03,$03,$07,$3F,$3C,$1C,$0F,$1F,$3F,$3F,$07,$03,$03,$02,$00,$00,$00,$30,$F0,$F0,$C0,$CC,$FE,$FC,$F0,$F0,$F8,$30,$00,$80
  .byte $00,$00,$01,$01,$1F,$1F,$1F,$09,$39,$7F,$3F,$07,$07,$0E,$04,$08,$00,$00,$80,$80,$F8,$F8,$F8,$90,$9C,$FE,$FC,$E0,$E0,$70,$20,$20
  .byte $00,$00,$03,$03,$07,$3F,$3F,$19,$09,$1F,$3F,$3F,$07,$03,$03,$02,$00,$00,$00,$30,$F0,$F0,$F0,$9C,$9E,$FC,$F0,$F0,$F8,$30,$00,$80
  .byte $00,$00,$01,$01,$1F,$1F,$13,$03,$3F,$7F,$3F,$07,$07,$0E,$04,$08,$00,$00,$80,$80,$F8,$F8,$38,$30,$FC,$FE,$FC,$E0,$E0,$70,$20,$20
  .byte $00,$00,$03,$03,$07,$3F,$33,$13,$0F,$1F,$3F,$3F,$07,$03,$03,$02,$00,$00,$00,$30,$F0,$F0,$30,$3C,$FE,$FC,$F0,$F0,$F8,$30,$00,$80
  .byte $00,$00,$01,$01,$1F,$19,$19,$0F,$3F,$7F,$3F,$07,$07,$0E,$04,$08,$00,$00,$80,$80,$F8,$98,$98,$F0,$FC,$FE,$FC,$E0,$E0,$70,$20,$20
  .byte $00,$00,$03,$03,$07,$39,$39,$1F,$0F,$1F,$3F,$3F,$07,$03,$03,$02,$00,$00,$00,$30,$F0,$90,$90,$FC,$FE,$FC,$F0,$F0,$F8,$30,$00,$80
  .byte $00,$00,$01,$01,$1F,$1F,$1B,$0B,$3F,$7F,$35,$02,$07,$0E,$04,$00,$00,$00,$80,$80,$F8,$F8,$D8,$D0,$FC,$FE,$5C,$A0,$E0,$70,$20,$00
  .byte $00,$00,$03,$03,$07,$3F,$3B,$1B,$0F,$1F,$3A,$35,$07,$03,$03,$00,$00,$00,$00,$30,$F0,$F0,$D0,$DC,$FE,$FC,$A0,$50,$F8,$30,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$18,$18,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$60,$60,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$1E,$12,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$78,$48,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$06,$06,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$18,$18,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$12,$1E,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$48,$78,$30,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3B,$0A,$3A,$22,$3B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$2B,$2A,$3A,$0A,$0B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3B,$2A,$3A,$2A,$3B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$B8,$A8,$A8,$A8,$B8,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$4E,$C8,$4E,$4A,$EE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$EE,$AA,$AA,$AA,$EE,$00,$00,$00,$00,$00,$00
  .byte $00,$20,$31,$3F,$6E,$7F,$3F,$1F,$3F,$7F,$7F,$7F,$7F,$3F,$30,$00,$00,$80,$80,$80,$C0,$C0,$80,$00,$80,$C1,$EE,$E0,$E0,$E0,$C0,$00
  .byte $00,$20,$31,$3F,$6E,$7F,$3F,$1F,$3F,$7F,$7F,$7F,$7F,$3F,$30,$00,$00,$80,$80,$80,$C0,$C0,$80,$00,$80,$C0,$E0,$E0,$E0,$FF,$C1,$00
  .byte $00,$07,$1F,$3B,$7F,$7B,$7F,$77,$7F,$7D,$3F,$1F,$07,$00,$00,$00,$00,$E0,$F8,$DC,$FE,$DE,$FE,$EE,$FE,$DE,$FC,$F8,$E0,$00,$00,$00
  .byte $00,$07,$04,$07,$05,$07,$05,$07,$05,$07,$05,$07,$07,$00,$00,$00,$00,$E0,$20,$E0,$A0,$E0,$A0,$E0,$A0,$E0,$A0,$E0,$E0,$00,$00,$00
  .byte $00,$01,$01,$01,$01,$01,$01,$01,$03,$0F,$3F,$7F,$7F,$3F,$00,$00,$00,$F8,$F8,$08,$F8,$F8,$F8,$F8,$F8,$F0,$F0,$F0,$E0,$80,$00,$00
  .byte $00,$00,$01,$01,$01,$00,$10,$1B,$1F,$1F,$0F,$07,$00,$00,$00,$00,$00,$E0,$F0,$B0,$F8,$EC,$E0,$F8,$FC,$FC,$F8,$F0,$00,$00,$00,$00
  .byte $00,$1E,$21,$4C,$4C,$40,$21,$1E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$FF,$AA,$28,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$19,$21,$23,$67,$7F,$67,$23,$21,$19,$07,$00,$00,$00,$00,$00,$E0,$98,$84,$C4,$E6,$FE,$E6,$C4,$84,$98,$E0,$00,$00,$00,$00
  .byte $00,$38,$44,$44,$36,$06,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$60,$30,$1C,$22,$22,$1C,$00
  .byte $00,$01,$03,$01,$07,$0C,$18,$10,$10,$18,$0C,$07,$00,$00,$00,$00,$00,$80,$C0,$80,$E0,$30,$18,$08,$08,$18,$30,$E0,$00,$00,$00,$00

; game tiles 96-115: patterns and colours
TILEP:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$FF,$01,$01,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$01,$01,$01,$01,$01,$01,$01,$FF,$FF,$01,$01,$01,$01,$01,$01,$FF
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$FF,$80,$80,$80,$80,$80,$80,$80,$81,$81,$81,$81,$81,$81,$81,$81,$FF,$81,$81,$81,$81,$81,$81,$81
  .byte $80,$80,$80,$80,$80,$80,$80,$FF,$FF,$80,$80,$80,$80,$80,$80,$FF,$81,$81,$81,$81,$81,$81,$81,$FF,$FF,$81,$81,$81,$81,$81,$81,$FF
  .byte $00,$00,$00,$18,$18,$00,$00,$00,$7E,$81,$A5,$A5,$81,$99,$81,$7E,$00,$00,$00,$FF,$FF,$00,$00,$00,$3C,$7E,$DB,$FF,$C3,$FF,$7E,$3C
TILEC:
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

; the rooms: open tiles, 19 rows (3-21) x 4 bytes (columns 0-31)
RM0:
  .byte $7F,$7F,$FD,$FC,$55,$41,$05,$54,$55,$F7,$DF,$54,$54,$14,$50,$54,$5F,$FF,$FF,$F4,$55,$15,$51,$54,$75,$DF,$F7,$5C,$14,$51,$14,$50
  .byte $FF,$D7,$D7,$FF,$40,$57,$D4,$04,$7F,$D7,$D7,$FC,$50,$50,$14,$14,$5F,$DF,$F7,$F4,$54,$05,$40,$54,$77,$75,$5D,$DC,$55,$55,$55,$54
  .byte $5D,$57,$D5,$74,$55,$51,$15,$54,$7D,$DF,$F7,$7C
RM1:
  .byte $7F,$F7,$DF,$FC,$44,$55,$54,$44,$7D,$F7,$DF,$7C,$41,$15,$51,$04,$7F,$75,$5D,$FC,$04,$55,$54,$40,$7D,$FF,$FF,$7C,$41,$51,$15,$04
  .byte $DF,$F7,$DF,$F7,$50,$57,$D4,$14,$57,$77,$DD,$D4,$55,$50,$15,$54,$7D,$7F,$FD,$7C,$45,$01,$01,$44,$75,$DD,$77,$5C,$55,$55,$55,$54
  .byte $5D,$75,$5D,$74,$45,$45,$45,$44,$7F,$FF,$FF,$FC
RM2:
  .byte $7F,$DF,$F7,$FC,$50,$55,$54,$14,$7F,$7D,$7D,$FC,$45,$05,$41,$44,$7D,$FD,$7F,$7C,$41,$11,$11,$04,$7D,$DF,$F7,$7C,$45,$51,$15,$44
  .byte $F7,$77,$DD,$DF,$54,$17,$D0,$54,$5D,$D7,$D7,$74,$45,$50,$15,$44,$5D,$DF,$F7,$74,$51,$55,$55,$14,$5D,$77,$DD,$74,$55,$11,$11,$54
  .byte $7D,$DF,$F7,$7C,$45,$50,$15,$44,$7F,$DF,$F7,$FC
RM3:
  .byte $7F,$FF,$FF,$FC,$44,$11,$10,$44,$7D,$F7,$DF,$7C,$11,$15,$51,$10,$7F,$7D,$7D,$FC,$40,$55,$54,$04,$7F,$DF,$F7,$FC,$51,$51,$15,$14
  .byte $DD,$77,$DD,$77,$55,$17,$D1,$54,$7D,$77,$DD,$7C,$41,$50,$15,$04,$5F,$7F,$FD,$F4,$54,$55,$54,$54,$77,$D5,$57,$DC,$50,$55,$54,$14
  .byte $77,$DD,$77,$DC,$54,$01,$00,$54,$77,$FF,$FF,$DC
RM4:
  .byte $7F,$FF,$FF,$FC,$44,$01,$00,$44,$77,$FD,$7F,$DC,$51,$45,$45,$14,$57,$77,$DD,$D4,$54,$54,$54,$54,$5D,$FF,$FF,$74,$41,$11,$11,$04
  .byte $DF,$D7,$D7,$F7,$55,$57,$D5,$54,$57,$77,$DD,$D4,$50,$50,$14,$14,$5F,$7F,$FD,$F4,$41,$51,$15,$04,$5D,$DF,$F7,$74,$54,$14,$50,$54
  .byte $77,$F7,$DF,$DC,$40,$41,$04,$04,$7F,$FF,$FF,$FC
RM5:
  .byte $7F,$FF,$FF,$FC,$54,$55,$54,$54,$77,$5D,$75,$DC,$41,$45,$45,$04,$7F,$75,$5D,$FC,$10,$15,$50,$10,$7F,$7F,$FD,$FC,$41,$51,$15,$04
  .byte $DF,$D7,$D7,$F7,$50,$17,$D0,$14,$5F,$D7,$D7,$F4,$51,$50,$15,$14,$77,$5F,$F5,$DC,$44,$41,$04,$44,$77,$7F,$FD,$DC,$55,$40,$05,$54
  .byte $5D,$7F,$FD,$74,$51,$15,$51,$14,$7F,$FF,$FF,$FC
RM6:
  .byte $7F,$FF,$FF,$FC,$41,$05,$41,$04,$7D,$FD,$7F,$7C,$45,$01,$01,$44,$5F,$FF,$FF,$F4,$50,$44,$44,$14,$5F,$DF,$F7,$F4,$40,$51,$14,$04
  .byte $FF,$77,$DD,$FF,$41,$17,$D1,$04,$7D,$F7,$DF,$7C,$54,$10,$10,$54,$75,$DF,$F7,$5C,$45,$55,$55,$44,$5D,$7D,$7D,$74,$51,$41,$05,$14
  .byte $77,$7F,$FD,$DC,$44,$11,$10,$44,$7F,$FF,$FF,$FC
RM7:
  .byte $7F,$FF,$FF,$FC,$40,$11,$10,$04,$7D,$FD,$7F,$7C,$45,$05,$41,$44,$77,$F7,$DF,$DC,$50,$54,$54,$14,$5F,$5F,$F5,$F4,$45,$51,$15,$44
  .byte $FD,$D7,$D7,$7F,$04,$17,$D0,$40,$75,$F7,$DF,$5C,$55,$50,$15,$54,$5F,$DF,$F7,$F4,$51,$11,$11,$14,$7D,$FF,$FF,$7C,$44,$11,$10,$44
  .byte $75,$F7,$DF,$5C,$55,$45,$45,$54,$7F,$7F,$FD,$FC
RM_LO:
  .byte <RM0,<RM1,<RM2,<RM3,<RM4,<RM5,<RM6,<RM7
RM_HI:
  .byte >RM0,>RM1,>RM2,>RM3,>RM4,>RM5,>RM6,>RM7

; squares 0-63 (distances of the bunnies to their target)
SQ_LO:
  .byte $00,$01,$04,$09,$10,$19,$24,$31,$40,$51,$64,$79,$90,$A9,$C4,$E1,$00,$21,$44,$69,$90,$B9,$E4,$11,$40,$71,$A4,$D9,$10,$49,$84,$C1
  .byte $00,$41,$84,$C9,$10,$59,$A4,$F1,$40,$91,$E4,$39,$90,$E9,$44,$A1,$00,$61,$C4,$29,$90,$F9,$64,$D1,$40,$B1,$24,$99,$10,$89,$04,$81
SQ_HI:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$03,$03,$03,$03
  .byte $04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$07,$07,$07,$08,$08,$09,$09,$09,$0A,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$0D,$0E,$0E,$0F,$0F

; big letters of the title
BIG_TOP:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
BIG_BOT:
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00,$18,$06,$06,$06,$06,$01,$01,$00,$18,$60,$60,$60,$60,$80,$80,$00
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
TXT_BIG:
  .byte 3,8,160,161,162,163,164,165,162,163,32,32,166,167,168,169,170,171,0
  .byte 4,8,192,193,194,195,196,197,194,195,32,32,198,199,200,201,202,203,0
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
  .byte $25,$06,$29,$06,$2C,$06,$29,$06,$2A,$06,$2E,$06,$2C,$0C,$29,$06,$2C,$06,$31,$06,$30,$06,$2E,$06,$2C,$06,$2A,$0C,$27,$06,$2A,$06
  .byte $2E,$06,$2A,$06,$2C,$06,$30,$06,$2E,$0C,$2C,$06,$29,$06,$27,$06,$29,$06,$25,$18,$2C,$06,$2E,$06,$2C,$06,$29,$06,$25,$0C,$29,$0C
  .byte $2A,$06,$2C,$06,$2A,$06,$27,$06,$24,$0C,$27,$0C,$29,$06,$2C,$06,$31,$06,$30,$06,$2E,$06,$2A,$06,$27,$06,$24,$06,$25,$18,$FF
SG0_1:
  .byte $1D,$18,$1E,$18,$1D,$18,$1E,$18,$1E,$18,$20,$18,$20,$18,$1D,$18,$1D,$18,$1B,$18,$20,$18,$1D,$18,$FF
SG0_2:
  .byte $0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$06,$0C,$0D,$0C,$0D,$0C,$08,$0C,$0F,$0C,$0A,$0C,$08,$0C,$0F,$0C,$0D,$0C,$08,$0C,$0D,$0C,$0D,$0C
  .byte $08,$0C,$0F,$0C,$0D,$0C,$06,$0C,$08,$0C,$08,$0C,$0D,$18,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG1_0:
  .byte $25,$06,$27,$06,$29,$06,$2C,$06,$29,$06,$2C,$06,$31,$0C,$30,$06,$2C,$06,$2E,$06,$2A,$06,$2C,$18,$FF
SG1_1:
  .byte $1D,$18,$19,$18,$1B,$18,$18,$18,$FF
SG1_2:
  .byte $0D,$0C,$08,$0C,$0D,$0C,$11,$0C,$06,$0C,$06,$0C,$08,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$04,$18,$FF
SG2_0:
  .byte $29,$04,$2C,$04,$31,$04,$35,$04,$38,$14,$00,$04,$35,$04,$38,$04,$3D,$18,$FF
SG2_1:
  .byte $25,$10,$29,$18,$2C,$20,$FF
SG2_2:
  .byte $0D,$10,$08,$18,$0D,$20,$FF
SG2_3:
  .byte $02,$04,$02,$04,$02,$04,$02,$04,$01,$14,$03,$04,$03,$04,$03,$04,$04,$18,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$59,$45,$39,$39,$45,$59,$78,$78,$78,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$38,$38,$38,$38,$FC,$FC,$FC,$FC,$68,$57,$4D,$47,$45
  .byte $47,$4D,$57,$68,$81,$A1,$C2,$D0,$C2,$A1,$81,$23,$1A,$23,$1A,$23,$1A,$23,$1A,$D0,$BC,$A9,$98,$89,$7C,$6F,$64,$5A,$51,$49,$42,$3C
  .byte $36,$30,$2C,$27,$23,$20,$1D,$2F,$2F,$2F,$28,$28,$28,$20,$20,$20,$18,$18,$18,$18,$18,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00
  .byte $00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$59,$5D,$5C,$61,$6B,$70,$6F,$74,$81,$87,$85,$8C,$9B,$A2,$A0,$A8,$BB,$C3,$C1
  .byte $CA,$E0,$EB,$E8,$F3,$0E,$1A,$17,$24,$44,$53,$4F,$5F,$86,$98,$93,$A6,$D4,$EB,$E5,$FB,$68,$5D,$53,$4C,$45,$45,$4A,$4E,$53,$59,$60
  .byte $68,$72,$7D,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$EF,$EF,$EF,$EF,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28
  .byte $28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00
WH_VOL:
  .byte $00,$09,$08,$06,$09,$08,$06,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0B,$09,$08,$06,$05,$05,$05,$05,$05,$05,$05,$05,$05,$07,$07,$07,$07,$07
  .byte $07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06,$06,$06,$06,$06,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A
  .byte $0A,$0A,$0A,$09,$09,$09,$09,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0A,$08,$06,$04,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00
  .byte $00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$08,$09,$0A,$0A,$0B,$0B,$0A,$09,$08,$08,$07
  .byte $06,$05,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A
  .byte $0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04
  .byte $03
WH_START:
  .byte $00,$01,$04,$07,$13,$1B,$2B,$33,$47,$55,$6D,$95,$A3,$CB,$CE
WH_LEN:
  .byte $00,$03,$03,$0C,$08,$10,$08,$14,$0E,$18,$28,$0E,$28,$03,$13
W_DUST1 = 1
W_DUST2 = 2
W_SOCK = 3
W_HUM = 4
W_SIREN = 5
W_EYES = 6
W_EATB = 7
W_BONUS = 8
W_EXTRA = 9
W_DOWN = 10
W_MEOW = 11
W_OVER = 12
W_KEY = 13
W_SIGN = 14

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03
EX_NP:
  .byte $00,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01
EX_LEN:
  .byte $00,$0A
S_BIG = 1

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$45, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$46, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$65, <96,>96, $B1,0
  .byte 2, $00,$66, <96,>96, $A1,0
  .byte 1, $00,$43, <160,>160, <TILEP,>TILEP
  .byte 1, $00,$63, <160,>160, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4D, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$4E, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$6D, <96,>96, $B1,0
  .byte 2, $00,$6E, <96,>96, $A1,0
  .byte 1, $00,$4B, <160,>160, <TILEP,>TILEP
  .byte 1, $00,$6B, <160,>160, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $00,$55, <96,>96, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$56, <96,>96, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$75, <96,>96, $B1,0
  .byte 2, $00,$76, <96,>96, $A1,0
  .byte 1, $00,$53, <160,>160, <TILEP,>TILEP
  .byte 1, $00,$73, <160,>160, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
