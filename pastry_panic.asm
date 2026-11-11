;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   PASTRY PANIC  -  an original platform game                 ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Chef Pip builds 4 cakes: the layers (sponge, cream,      ;
;     chocolate, icing) lie on the shelves of the pastry shop  ;
;   - walk over a layer from end to end: it falls to the next  ;
;     shelf; a layer falling on another one pushes it down;    ;
;     under the last shelf the layers pile up on the plates    ;
;   - the rebel fruit (strawberries, bananas, lemons) chase    ;
;     him on the shelves and the ladders: a falling layer      ;
;     squashes them, or takes them down for more points        ;
;   - the button shakes icing sugar: it stuns the fruit; 5     ;
;     doses a level, a cherry now and then gives one more      ;
;   - 6 layouts, then again with more and faster fruit; 3      ;
;     lives, one more at 10000 points; 1 or 2 players taking   ;
;     turns, every one with his own cakes                      ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 53 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     a bouncy tune at the title, the layers, the sugar, the   ;
;     splat of the fruit, the bell of the cherry               ;
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
XLIF        = $3D      ; 2 bytes: 1 = the life at 10000 points is given
GSTATE      = $50      ; 0 playing, 1 a life lost
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives, sugar and level
FIRSTT      = $53      ; 1 = first turn of the game
PX          = $54      ; Chef Pip: left x, top y (screen pixels)
PY          = $55
PFACE       = $56      ; 0 right, 1 left
PFLR        = $57      ; the shelf he stands on (0-4), $FF on a ladder
PSTEP       = $58      ; pixels walked (the legs)
LVI         = $59      ; danger of the level (0-15)
SIGN        = $5A      ; 1 = the sign of the level at its start
CLT         = $5B      ; frames of the cloud of sugar
CLX         = $5C      ; the cloud: left x, top y
CLY         = $5D
OLDB        = $5E      ; the buttons in the frame before
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
LAYOUT      = $72      ; the layout of the level (0-5)
DONE        = $73      ; 1 = the 16 layers are on the plates
LOSTN       = $74      ; lives lost (tests)
DEATHS      = $75      ; what took the last life (tests): 1 a fruit
GOD         = $76      ; tests: 1 = the fruit does no harm (0 in the game)
NEN         = $77      ; fruit in the level
ESPD        = $78      ; speed of the fruit (fraction of a pixel a frame)
SMART       = $79      ; chance the fruit takes the way to Chef Pip (/256)
STUNT       = $7A      ; frames the sugar stuns
CHT         = $7B      ; the cherry: frames / 2 it stays (0 = none)
NFALL       = $7C      ; layers falling
CF          = $7D      ; the shelf nearest to Chef Pip
TICKS       = $7E      ; frames of the level
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
KILLS       = $90      ; fruit squashed or taken down (tests)
DROPS       = $91      ; layers landed (tests)
SUGN        = $92      ; doses shaken (tests)
EI          = $93      ; the fruit being moved
EF          = $94      ; its shelf
OPTS        = $95      ; the ways it can take (1 right, 2 left, 4 up, 8 down)
LVN         = $96      ; levels finished (tests)
Q0          = $98      ; temporaries
Q1          = $99
Q2          = $9A
Q3          = $9B
CPTR        = $9C      ; 2 bytes: row of the map

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

; ---------------- the fruit (6 at most) ----------------
NE         = 6
EXP        = $0200       ; left x, top y (pixels)
EYP        = $0206
ES         = $020C       ; state: 0 waiting, 1 walking, 2 stunned, 3 squashed, 4 riding a layer
ED         = $0212       ; way: 0 right, 1 left, 2 up, 3 down
EACC       = $0218       ; fraction of the speed
ET         = $021E       ; frames: before it comes in / stunned / squashed
ERL        = $0224       ; the layer it rides
; ---------------- the layers falling ----------------
LYY        = $0240       ; 16: top y (pixels)
LYT        = $0250       ; 16: the row it lands on
LYN        = $0260       ; 16: fruit riding it
FLY        = $0270       ; 20: the layer lying on shelf f, cake k (f * 4 + k), $FF none
SPANC      = $0288       ; 5: the spans of the shelves of this layout
LADS       = $0290       ; 4: the ladders between shelf f and f + 1
; ---------------- block of the player playing (saved) ----------------
PB         = $0300
LV         = $0300       ; the level (0-...)
DOSE       = $0301       ; doses of sugar
FALLS      = $0302       ; layers fallen in the level (the cherry comes at 4 and 10)
STK        = $0304       ; 4: layers on every plate (the next free row too)
LYS        = $0308       ; 16: 0 on a shelf, 1 falling, 2 on the plate
LYR        = $0318       ; 16: the row it lies on
LYF        = $0328       ; 16: its shelf (5 = the plate)
LYP        = $0338       ; 16: pieces pressed (bits 0-3)
PBLOCK     = $48
PSAVE      = $0400       ; 2 x $80: block of every player

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
MAP        = $0800       ; 24 rows x 32 tiles: the screen of the level

; ---------------- parameters ----------------
BTN_MASK    = %00110000
DIE_T       = 100        ; frames of a life lost
FALL_SPD    = 2          ; pixels a frame of a falling layer
CLOUD_T     = 24         ; frames of the cloud of sugar
CHERRY_T    = 240        ; frames / 2 of the cherry
CHERRY_X    = 120        ; the cherry on shelf 2
CHERRY_Y    = 72
START_X     = 120        ; Chef Pip starts on the bottom shelf, by the middle ladder
START_Y     = 120
RESPAWN_T   = 150        ; frames before a fruit comes back
ENTER_T     = 80         ; frames between two fruit at the start

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 53         ; fixed zone of the game in the save area
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
;  NEW GAME: the first level, 3 lives for every player
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  STZ XLIF,X
  DEX
  BPL .ng_p
  STZ LOSTN
  STZ KILLS
  STZ DROPS
  STZ SUGN
  STZ LVN
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ LV
  JSR NEW_LEVEL
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his cakes as he left them
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  LDA #1
  STA SIGN
  JSR ALL_DOWN                 ; the cakes were finished as he lost the life
  BCC ROUND_START
  JMP LEVEL_NEXT

ROUND_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the level is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_LEVEL                ; the tables, the map, Chef Pip and the fruit at their places
  JSR CLEAR_NT
  JSR DRAW_LEVEL
  JSR DRAW_HUD
  STZ HUDD
  STZ GSTATE
  LDA SIGN
  BEQ .rs_ns
  JSR MSG_LEVEL
.rs_ns:
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA SIGN
  BEQ .rs_go
  STZ SIGN
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
  LDA #90
  JSR WAIT_FRAMES
.rs_w:
  LDA #10
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  JSR VDP_INT_ON
  LDA #CMD_GAME
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
  BRA .rs_g
.rs_go:
  LDA #20
  JSR WAIT_FRAMES
.rs_g:
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
  JSR CHEF
  JSR FRUITS
  JSR SUGAR_HITS
  JSR CHERRY
  JSR HITS
.gl_ns:
  JSR LAYERS                   ; the layers fall on also while a life is lost
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA GSTATE
  BNE .gl_dead
  LDA DONE
  BEQ GAME_LOOP
  LDA NFALL
  BNE GAME_LOOP
  JMP LEVEL_DONE
.gl_dead:
  LDA GT
  CMP #1
  BNE .gl_dec
  LDA NFALL                    ; the last frame waits for the layers to land
  BNE GAME_LOOP
.gl_dec:
  DEC GT
  BNE GAME_LOOP
  JMP LOSE_LIFE


; ===============================================================
;  THE CAKES ARE READY: the tune, the next level
; ===============================================================
LEVEL_DONE:
  INC LVN
  JSR HIDE_SPRITES
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ld_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ld_t
  LDA #30
  JSR WAIT_FRAMES
  LDA #CMD_GAME
  STA SND_CMD
LEVEL_NEXT:
  LDA LV
  CMP #99
  BCS .ln_s
  INC LV
.ln_s:
  JSR NEW_LEVEL
  JSR SAVE_PLAYER
  LDA #1
  STA SIGN
  JMP ROUND_START

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
  LDA #1                       ; the same player: from the bottom shelf, the cakes as they are
  STA SIGN
  JSR ALL_DOWN
  BCC .ll_r
  JMP LEVEL_NEXT
.ll_r:
  JMP ROUND_START

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
  LDY #0                       ; extra byte: the level reached
  CPX #0
  BEQ .go_x
  LDY #$80
.go_x:
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
REC_NAME:  .byte "PASTRY PANIC    "
REC_HEAD:  .byte "BEST CHEFS",0
REC_XLBL:  .byte "LEVEL ",0


; ===============================================================
;  HUD: row 0 (scores), row 23 (lives, sugar, level)
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

; row 23: the spare lives (cols 0-5), the sugar (8-16), LEVEL nn (21-28), the player (31)
DRAW_STATUS:
  LDX #23
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
  CPY #8
  BNE .ds_i
  LDY #0                       ; the doses of sugar
.ds_s:
  LDA #$20
  CPY DOSE
  BCS .ds_t
  LDA #T_SUGAR
.ds_t:
  STA VDATA
  INY
  CPY #13
  BNE .ds_s
  LDX #0
.ds_l:
  LDA TXT_LEVELH,X
  STA VDATA
  INX
  CPX #6
  BNE .ds_l
  LDA LV                       ; the level (99 at most on the screen)
  INC A
  CMP #100
  BCC .ds_n
  LDA #99
.ds_n:
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  STA VDATA
  LDA NPL                      ; the player at the right end with 2 players
  CMP #2
  BNE .ds_e
  LDX #23
  LDY #31
  JSR NT_XY
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ds_e:
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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives, sugar and level
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
  JMP DRAW_STATUS
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: his block
  LDY #0
  LDA CURP
  BEQ .sp_0
  LDY #$80
.sp_0:
  LDX #0
.sp_b:
  LDA PB,X
  STA PSAVE,Y
  INY
  INX
  CPX #PBLOCK
  BNE .sp_b
  RTS

LOAD_PLAYER:                   ; X = player
  LDY #0
  CPX #0
  BEQ .lp_0
  LDY #$80
.lp_0:
  LDX #0
.lp_b:
  LDA PSAVE,Y
  STA PB,X
  INY
  INX
  CPX #PBLOCK
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
  LDA #1
  TSB HUDD
  LDA SCH,X
  BEQ .as_r
  LDA XLIF,X
  BNE .as_r
  INC XLIF,X
  LDA LIVES,X
  CMP #9
  BCS .as_r
  INC LIVES,X
  LDA #2
  TSB HUDD
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.as_r:
  PLY
  PLX
  RTS
; ===============================================================
;  THE LEVEL: layouts, map, drawing, signs
; ===============================================================

; LAYOUT = LV mod 6
LAYOUT_OF:
  LDA LV
.lo_l:
  CMP #NLAYOUT
  BCC .lo_r
  SBC #NLAYOUT
  BRA .lo_l
.lo_r:
  STA LAYOUT
  RTS

; a new level for the player playing: every layer on its shelf, 5 doses of sugar
NEW_LEVEL:
  JSR LAYOUT_OF
  LDA #5
  STA DOSE
  STZ FALLS
  LDX #3
.nl_s:
  STZ STK,X
  DEX
  BPL .nl_s
  LDA LAYOUT
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDX #0
.nl_l:
  LDA LO_LY,Y
  STA LYF,X
  PHY
  TAY
  LDA FL_R,Y
  DEC A
  STA LYR,X
  PLY
  STZ LYS,X
  STZ LYP,X
  INY
  INX
  CPX #16
  BNE .nl_l
  RTS

; C = 1 if the 16 layers are on the plates (keeps X)
ALL_DOWN:
  LDY #15
.ad_l:
  LDA LYS,Y
  CMP #2
  BNE .ad_n
  DEY
  BPL .ad_l
  SEC
  RTS
.ad_n:
  CLC
  RTS

; the level LV of the player playing: the tables, the map, Chef Pip and the fruit
SET_LEVEL:
  JSR LAYOUT_OF
  LDA LV
  CMP #15
  BCC .sl_v
  LDA #15
.sl_v:
  STA LVI
  TAY
  LDA NEN_T,Y
  STA NEN
  LDA ESPD_T,Y
  STA ESPD
  LDA SMART_T,Y
  STA SMART
  LDA STUN_T,Y
  STA STUNT
  LDA LAYOUT                   ; the shelves and the ladders of the layout
  ASL A
  ASL A
  ASL A
  TAY
  LDX #0
.sl_c:
  LDA LO_SPAN,Y
  STA SPANC,X
  LDA LO_LAD,Y
  STA LADS,X
  INY
  INX
  CPX #5
  BNE .sl_c
  LDX #19                      ; which layer lies where
  LDA #$FF
.sl_f:
  STA FLY,X
  DEX
  BPL .sl_f
  LDX #15
.sl_g:
  LDA LYS,X
  BNE .sl_gn
  LDA LYF,X
  ASL A
  ASL A
  STA T0
  TXA
  LSR A
  LSR A
  ORA T0
  TAY
  TXA
  STA FLY,Y
.sl_gn:
  DEX
  BPL .sl_g
  STZ DONE
  STZ NFALL
  STZ CLT
  STZ CHT
  STZ TICKS
  LDA #BTN_MASK                ; a button held from before does not shake
  STA OLDB
  LDA #START_X
  STA PX
  LDA #START_Y
  STA PY
  STZ PFACE
  STZ PSTEP
  LDA #4
  STA PFLR
  LDX #NE-1                    ; the fruit come in one after the other
.sl_e:
  STZ ES,X
  STZ EACC,X
  LDA ENTER_D,X
  STA ET,X
  DEX
  BPL .sl_e
  ; fall into BUILD_MAP

; the screen of the level in MAP: shelves, ladders, plates, layers
BUILD_MAP:
  LDA #<MAP
  STA CPTR
  LDA #>MAP
  STA CPTR+1
  LDX #3
  LDY #0
  LDA #$20
.bm_cl:
  STA (CPTR),Y
  INY
  BNE .bm_cl
  INC CPTR+1
  DEX
  BNE .bm_cl
  STZ Q0                       ; the shelves: span k from ladder column k to ladder column k + 1
.bm_f:
  LDX Q0
  LDA FL_R,X
  STA Q1
  LDA SPANC,X
  STA Q2
  STZ Q3
.bm_k:
  LSR Q2
  BCC .bm_kn
  LDX Q3
  LDA LADCOL,X
  STA T0
  LDA LADCOL+1,X
  INC A
  STA T1
.bm_c:
  LDX T0
  LDY Q1
  LDA #T_SHELF
  JSR MSET
  INC T0
  LDA T1
  CMP T0
  BCS .bm_c
.bm_kn:
  INC Q3
  LDA Q3
  CMP #4
  BNE .bm_k
  INC Q0
  LDA Q0
  CMP #5
  BNE .bm_f
  STZ Q0                       ; the ladders: rows shelf - 2 ... shelf + 2
.bm_g:
  LDX Q0
  LDA LADS,X
  STA Q2
  LDA FL_R,X
  STA Q1
  STZ Q3
.bm_p:
  LSR Q2
  BCC .bm_pn
  LDX Q3
  LDA LADCOL,X
  TAX
  LDA Q1
  SEC
  SBC #2
  TAY
.bm_r:
  LDA #T_LADL
  CPY Q1
  BNE .bm_rl
  LDA #T_LADFL
.bm_rl:
  JSR MSET
  INX
  INC A
  JSR MSET
  DEX
  INY
  TYA
  SEC
  SBC Q1
  CMP #3
  BNE .bm_r
.bm_pn:
  INC Q3
  LDA Q3
  CMP #5
  BNE .bm_p
  INC Q0
  LDA Q0
  CMP #4
  BNE .bm_g
  LDX #3                       ; the plates
.bm_pl:
  PHX
  LDA CKC,X
  TAX
  DEX
  LDY #22
  LDA #T_PLATE
  JSR MSET
  INX
  INC A
  JSR MSET
  INX
  JSR MSET
  INX
  JSR MSET
  INX
  JSR MSET
  INX
  INC A
  JSR MSET
  PLX
  DEX
  BPL .bm_pl
  LDX #15                      ; the layers
.bm_l:
  LDA LYS,X
  CMP #1
  BEQ .bm_ln
  JSR LAYER_MAP
.bm_ln:
  DEX
  BPL .bm_l
  RTS

; A = tile, X = column, Y = row: into MAP (keeps A, X, Y)
MSET:
  PHA
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  STY T6
  TXA
  TAY
  PLA
  STA (CPTR),Y
  LDY T6
  RTS

; A = tile, X = column, Y = row: into MAP and on the screen (keeps A, X, Y)
PUTT:
  JSR MSET
  PHA
  PHX
  PHY
  PHX
  TYA
  TAX
  PLY
  JSR NT_XY
  PLY
  PLX
  PLA
  STA VDATA
  RTS

; X = layer: its 4 tiles (pressed or not) in MAP only / in MAP and on the screen (keep X)
LAYER_MAP:
  LDA #0
  BRA LAYER_T
LAYER_TILES:
  LDA #1
LAYER_T:
  STA T5
  PHX
  TXA
  AND #3
  ASL A
  ASL A
  ASL A
  CLC
  ADC #T_LY
  STA Q0                       ; the first tile of the kind
  LDA LYP,X
  STA Q1
  LDA LYR,X
  STA Q2
  TXA
  LSR A
  LSR A
  TAY
  LDA CKC,Y
  STA Q3                       ; the first column
  STZ T4                       ; the piece
.lt_l:
  LDA Q0
  LSR Q1
  BCC .lt_u
  ADC #3                       ; (carry set: + 4) the piece pressed
.lt_u:
  CLC
  ADC T4
  PHA
  LDA Q3
  CLC
  ADC T4
  TAX
  LDY Q2
  PLA
  LDY T5
  BEQ .lt_m
  LDY Q2
  JSR PUTT
  BRA .lt_n
.lt_m:
  LDY Q2
  JSR MSET
.lt_n:
  INC T4
  LDA T4
  CMP #4
  BNE .lt_l
  PLX
  RTS

; X = layer: off the screen (keeps X)
ERASE_LAYER:
  PHX
  TXA
  LSR A
  LSR A
  TAY
  LDA CKC,Y
  STA T4
  LDY LYR,X
  LDX T4
  LDA #$20
  JSR PUTT
  INX
  JSR PUTT
  INX
  JSR PUTT
  INX
  JSR PUTT
  PLX
  RTS

DRAW_LEVEL:
  LDY #1
.dl_r:
  PHY
  JSR DRAW_ROW
  PLY
  INY
  CPY #23
  BNE .dl_r
  RTS

; Y = row (1-22): its 32 tiles from MAP
DRAW_ROW:
  STY T3
  TYA
  TAX
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
  STA VDATA
  INY
  CPY #32
  BNE .dr_c
  RTS

; the sign of the level on rows 9-13: LEVEL nn, CHEF PIP or PLAYER n
MSG_LEVEL:
  LDA #<TXT_SIGN
  STA TP
  LDA #>TXT_SIGN
  STA TP+1
  JSR PRINT
  LDX #10
  LDY #12
  JSR NT_XY
  LDX #0
.ml_l:
  LDA TXT_LEVELH,X
  STA VDATA
  INX
  CPX #6
  BNE .ml_l
  LDA LV
  INC A
  CMP #100
  BCC .ml_n
  LDA #99
.ml_n:
  JSR PUT_NUM
  LDX #12
  LDY #12
  JSR NT_XY
  LDA NPL
  CMP #2
  BEQ .ml_p
  LDX #0
.ml_s:
  LDA TXT_CHEF,X
  STA VDATA
  INX
  CPX #8
  BNE .ml_s
  RTS
.ml_p:
  LDX #0
.ml_q:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .ml_q
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
  RTS

MSG_CLEAR:                     ; the level again on rows 9-13
  LDY #9
.mc_r:
  PHY
  JSR DRAW_ROW
  PLY
  INY
  CPY #14
  BNE .mc_r
  RTS


; ===============================================================
;  PLACES: shelves, spans, ladders (they keep X)
; ===============================================================
; A = y: A = the shelf at that height, $FF between two shelves (flags of A)
FLOOR_OF:
  LDY #4
.fo_l:
  CMP FL_Y,Y
  BEQ .fo_k
  DEY
  BPL .fo_l
  LDA #$FF
  RTS
.fo_k:
  TYA
  RTS

; A = x: A = the span from that x to x + 1 (0-3), $FF past the last ladder
SPANIDX:
  LDY #0
.si_l:
  CMP LADX+1,Y
  BCC .si_k
  INY
  CPY #4
  BNE .si_l
  LDA #$FF
  RTS
.si_k:
  TYA
  RTS

; A = x: A = the ladder within 3 pixels, $FF none
LAD_NEAR:
  STA T3
  LDY #4
.ln_l:
  LDA T3
  SEC
  SBC LADX,Y
  BCS .ln_p
  EOR #$FF
  INC A
.ln_p:
  CMP #4
  BCC .ln_k
  DEY
  BPL .ln_l
  LDA #$FF
  RTS
.ln_k:
  TYA
  RTS

; A = x: A = the ladder just there, $FF none
LAD_AT:
  LDY #4
.la_l:
  CMP LADX,Y
  BEQ .la_k
  DEY
  BPL .la_l
  LDA #$FF
  RTS
.la_k:
  TYA
  RTS

; X = shelf, Y = ladder: C = 1 if the ladder goes up / down from there
HAS_UP:
  CPX #0
  BEQ .hu_n
  LDA LADS-1,X
  AND BITS,Y
  BEQ .hu_n
  SEC
  RTS
.hu_n:
  CLC
  RTS
HAS_DN:
  CPX #4
  BEQ .hd_n
  LDA LADS,X
  AND BITS,Y
  BEQ .hd_n
  SEC
  RTS
.hd_n:
  CLC
  RTS


; ===============================================================
;  CHEF PIP
; ===============================================================
CHEF:
  LDA JOYC                     ; a button pressed now: a dose of sugar
  AND #BTN_MASK
  TAX
  LDA OLDB
  EOR #$FF
  STX OLDB
  STX T0
  AND T0
  BEQ .ch_nb
  LDA CLT
  BNE .ch_nb
  LDA PFLR
  BMI .ch_nb
  LDA DOSE
  BNE .ch_sh
  LDA #W_EMPTY
  LDX #2
  JSR SFX_WHISTLE
  BRA .ch_nb
.ch_sh:
  DEC DOSE
  INC SUGN
  LDA #2
  TSB HUDD
  LDA #CLOUD_T
  STA CLT
  LDA PY
  STA CLY
  LDA PFACE
  BNE .ch_cl
  LDA PX
  CLC
  ADC #16
  CMP #241
  BCC .ch_cs
  LDA #240
  BRA .ch_cs
.ch_cl:
  LDA PX
  SEC
  SBC #16
  BCS .ch_cs
  LDA #0
.ch_cs:
  STA CLX
  LDA #S_PUFF
  LDY PX
  JSR BOOM_AT
.ch_nb:
  LDA CLT                      ; he stands still while he shakes
  BEQ CHEF_MOVE
  DEC CLT
  LDA CLT
  CMP #CLOUD_T-12
  BCC CHEF_MOVE
  RTS

CHEF_MOVE:
  LDA PY
  JSR FLOOR_OF
  STA PFLR
  LDA JOYC
  AND #3
  BEQ .cm_h
  LDA PFLR
  BMI .cm_lad
  LDA PX                       ; on a shelf: a ladder near him?
  JSR LAD_NEAR
  BMI .cm_h
  STA T2
  LDA JOYC
  AND #1
  BEQ .cm_dn
  LDX PFLR
  LDY T2
  JSR HAS_UP
  BCC .cm_dn
  LDA LADX,Y
  STA PX
  DEC PY
  RTS
.cm_dn:
  LDA JOYC
  AND #2
  BEQ .cm_h
  LDX PFLR
  LDY T2
  JSR HAS_DN
  BCC .cm_h
  LDA LADX,Y
  STA PX
  INC PY
  RTS
.cm_lad:                       ; on a ladder: up or down
  LDA JOYC
  AND #1
  BEQ .cm_ld
  DEC PY
  RTS
.cm_ld:
  INC PY
  RTS
.cm_h:
  LDA JOYC
  AND #12
  BEQ .cm_r
  LDA PFLR
  BPL .cm_w
  LDA PY                       ; on a ladder: on to the nearest shelf
  SEC
  SBC #24
.cm_m:
  CMP #24
  BCC .cm_mm
  SBC #24
  BRA .cm_m
.cm_mm:
  CMP #12
  BCS .cm_mi
  DEC PY
  RTS
.cm_mi:
  INC PY
  RTS
.cm_w:
  LDA JOYC
  AND #8
  BEQ .cm_l
  LDA PX
  JSR SPANIDX
  BMI .cm_r
  TAY
  LDX PFLR
  LDA SPANC,X
  AND BITS,Y
  BEQ .cm_r
  INC PX
  STZ PFACE
  BRA .cm_st
.cm_l:
  LDA PX
  BEQ .cm_r
  DEC A
  JSR SPANIDX
  TAY
  LDX PFLR
  LDA SPANC,X
  AND BITS,Y
  BEQ .cm_r
  DEC PX
  LDA #1
  STA PFACE
.cm_st:
  INC PSTEP
  LDA PSTEP
  AND #7
  BNE .cm_p
  LDA #W_STEP
  LDX #2
  JSR SFX_WHISTLE
.cm_p:
  JMP PRESS
.cm_r:
  RTS

; Chef Pip on a shelf: the piece of layer under his middle goes down
PRESS:
  LDA PX
  CLC
  ADC #8
  STA T0
  JSR SPANIDX
  BMI .pr_r
  TAY
  STY T2
  LDA T0
  SEC
  SBC CKX,Y
  CMP #32
  BCS .pr_r
  LSR A
  LSR A
  LSR A
  STA T1                       ; the piece
  LDA PFLR
  ASL A
  ASL A
  ORA T2
  TAY
  LDA FLY,Y
  BMI .pr_r
  TAX
  LDY T1
  LDA BITS,Y
  AND LYP,X
  BNE .pr_r
  LDA BITS,Y
  ORA LYP,X
  STA LYP,X
  JSR LAYER_TILES
  PHX
  LDA #W_PRESS
  LDX #2
  JSR SFX_WHISTLE
  PLX
  LDA LYP,X
  CMP #15
  BNE .pr_r
  JMP START_FALL
.pr_r:
  RTS


; ===============================================================
;  THE LAYERS
; ===============================================================
; X = layer: it leaves its shelf; the fruit on it ride down (keeps X)
START_FALL:
  PHX
  LDA #1
  STA LYS,X
  LDA LYR,X
  ASL A
  ASL A
  ASL A
  STA LYY,X
  STZ LYN,X
  LDA LYF,X
  STA T3                       ; the shelf it leaves
  ASL A
  ASL A
  STA T0
  TXA
  LSR A
  LSR A
  STA T1                       ; the cake
  ORA T0
  TAY
  LDA #$FF
  STA FLY,Y
  JSR ERASE_LAYER
  LDY T3                       ; where it lands: the next shelf with this span, or the plate
.sf_n:
  INY
  CPY #5
  BEQ .sf_p
  STY T2
  LDY T1
  LDA BITS,Y
  LDY T2
  AND SPANC,Y
  BEQ .sf_n
  TYA
  STA LYF,X
  LDA FL_R,Y
  DEC A
  STA LYT,X
  BRA .sf_r
.sf_p:
  LDA #5
  STA LYF,X
  LDY T1
  LDA STK,Y                    ; the row on the plate is kept for it now
  STA T2
  INC A
  STA STK,Y
  LDA #21
  SEC
  SBC T2
  STA LYT,X
.sf_r:
  LDY T3                       ; the riders: fruit on the shelf, over the layer
  LDA FL_Y,Y
  STA T4
  LDY T1
  LDA CKX,Y
  STA T5
  LDY #NE-1
.sf_e:
  LDA ES,Y
  CMP #1
  BEQ .sf_ey
  CMP #2
  BNE .sf_en
.sf_ey:
  LDA EYP,Y
  CMP T4
  BNE .sf_en
  LDA EXP,Y
  CLC
  ADC #8
  SEC
  SBC T5
  CMP #32
  BCS .sf_en
  LDA #4
  STA ES,Y
  TXA
  STA ERL,Y
  INC LYN,X
.sf_en:
  DEY
  BPL .sf_e
  INC NFALL
  INC FALLS                    ; the cherry after 4 and 10 layers
  LDA FALLS
  CMP #4
  BEQ .sf_ch
  CMP #10
  BNE .sf_s
.sf_ch:
  LDA #CHERRY_T
  STA CHT
.sf_s:
  LDA #W_FALL
  LDX #2
  JSR SFX_WHISTLE
  PLX
  RTS

LAYERS:
  LDX #15
.ly_l:
  LDA LYS,X
  CMP #1
  BNE .ly_n
  JSR FALL1
.ly_n:
  DEX
  BPL .ly_l
  RTS

; X = layer falling (keeps X)
FALL1:
  LDA LYY,X
  CLC
  ADC #FALL_SPD
  STA LYY,X
  LDA LYT,X
  ASL A
  ASL A
  ASL A
  STA T0
  LDA LYY,X
  CMP T0
  BCC .fa_m
  LDA T0
  STA LYY,X
  JSR RIDERS_Y
  JMP LAND
.fa_m:
  JSR RIDERS_Y
  ; fall into SQUASH

; X = layer falling: the fruit under it are squashed
SQUASH:
  TXA
  LSR A
  LSR A
  TAY
  LDA CKX,Y
  STA T0
  LDA LYY,X
  CLC
  ADC #7
  STA T1
  LDY #NE-1
.sq_l:
  LDA ES,Y
  CMP #1
  BEQ .sq_t
  CMP #2
  BNE .sq_n
.sq_t:
  LDA EXP,Y                    ; its middle under the layer
  CLC
  ADC #8
  SEC
  SBC T0
  CMP #32
  BCS .sq_n
  LDA T1
  SEC
  SBC EYP,Y
  CMP #22
  BCS .sq_n
  LDA #3
  STA ES,Y
  LDA #40
  STA ET,Y
  INC KILLS
  LDA #$00
  PHY
  LDY #$05
  JSR ADD_PTS
  PLY
  LDA #S_SPLAT
  PHX
  PHY
  LDX #2
  JSR SFX_BOOM
  PLY
  PLX
.sq_n:
  DEY
  BPL .sq_l
  RTS

; X = layer: the fruit riding it go down with it
RIDERS_Y:
  LDA LYN,X
  BEQ .ry_r
  LDY #NE-1
.ry_l:
  LDA ES,Y
  CMP #4
  BNE .ry_n
  TXA
  CMP ERL,Y
  BNE .ry_n
  LDA LYY,X
  SEC
  SBC #8
  STA EYP,Y
.ry_n:
  DEY
  BPL .ry_l
.ry_r:
  RTS

; X = layer: it lands on the next shelf (the layer lying there falls on) or on the plate
LAND:
  LDA LYT,X
  STA LYR,X
  STZ LYP,X
  DEC NFALL
  INC DROPS
  LDA LYF,X
  CMP #5
  BNE .la_sh
  LDA #2
  STA LYS,X
  JSR LAYER_TILES
  BRA .la_p
.la_sh:
  STZ LYS,X
  ASL A
  ASL A
  STA T0
  TXA
  LSR A
  LSR A
  ORA T0
  TAY
  LDA FLY,Y
  BMI .la_e
  PHX
  PHY
  TAX
  JSR START_FALL
  PLY
  PLX
.la_e:
  TXA
  STA FLY,Y
  JSR LAYER_TILES
.la_p:
  LDA #$50
  LDY #0
  JSR ADD_PTS
  PHX
  LDA #S_LAND
  LDY T5
  LDX #2
  JSR SFX_BOOM
  PLX
  LDA LYN,X                    ; the riders: 500, 1000, 2000, 4000
  BEQ .la_al
  STZ LYN,X
  CMP #5
  BCC .la_rp
  LDA #4
.la_rp:
  TAY
  LDA RIDE_PTS-1,Y
  TAY
  LDA #0
  JSR ADD_PTS
  LDY #NE-1
.la_rl:
  LDA ES,Y
  CMP #4
  BNE .la_rn
  TXA
  CMP ERL,Y
  BNE .la_rn
  LDA #3
  STA ES,Y
  LDA #40
  STA ET,Y
  INC KILLS
.la_rn:
  DEY
  BPL .la_rl
  PHX
  LDA #S_SPLAT
  LDX #2
  JSR SFX_BOOM
  PLX
.la_al:
  JSR ALL_DOWN
  BCC .la_r
  LDA #1
  STA DONE
.la_r:
  RTS


; ===============================================================
;  THE FRUIT
; ===============================================================
FRUITS:
  LDA PY                       ; the shelf nearest to Chef Pip
  CLC
  ADC #12
  LDY #$FF
.fr_c:
  INY
  SEC
  SBC #24
  BCS .fr_c
  DEY
  BPL .fr_c0
  LDY #0
.fr_c0:
  CPY #5
  BCC .fr_c1
  LDY #4
.fr_c1:
  STY CF
  LDX #0
.fr_l:
  CPX NEN
  BCS .fr_e
  STX EI
  JSR FRUIT1
  LDX EI
  INX
  BRA .fr_l
.fr_e:
  RTS

; X = fruit
FRUIT1:
  LDA ES,X
  BEQ .f1_w
  CMP #1
  BEQ .f1_go
  CMP #2
  BEQ .f1_st
  CMP #3
  BEQ .f1_sq
  RTS
.f1_w:                         ; waiting (the frames count by 2)
  LDA TICKS
  AND #1
  BNE .f1_r
  LDA ET,X
  BEQ SPAWN
  DEC ET,X
  RTS
.f1_st:                        ; stunned
  DEC ET,X
  BNE .f1_r
  LDA #1
  STA ES,X
  RTS
.f1_sq:                        ; squashed
  DEC ET,X
  BNE .f1_r
  STZ ES,X
  LDA #RESPAWN_T
  STA ET,X
  RTS
.f1_go:
  LDA EACC,X
  CLC
  ADC ESPD
  STA EACC,X
  BCC .f1_r
  JMP STEP
.f1_r:
  RTS

; X = fruit: it comes in at an end of the top or of the bottom shelf, away from Chef Pip
SPAWN:
  JSR NEXT_RND
  AND #1
  BEQ .sp_f
  LDA #4
.sp_f:
  STA EF
  TAY
  LDA FL_Y,Y
  STA EYP,X
  JSR NEXT_RND
  AND #2
  LSR A
  STA T0                       ; 0 from the left, 1 from the right
  LDA EF
  CMP PFLR
  BNE .sp_s
  LDY T0                       ; Chef Pip near that end: the other one
  LDA PX
  SEC
  SBC SPX,Y
  BCS .sp_a
  EOR #$FF
  INC A
.sp_a:
  CMP #72
  BCS .sp_s
  LDA T0
  EOR #1
  STA T0
.sp_s:
  LDY T0
  LDA SPX,Y
  STA EXP,X
  TYA
  STA ED,X
  LDA #1
  STA ES,X
  STZ EACC,X
  RTS

; X = fruit: one pixel on its way; at a ladder on a shelf it chooses again
STEP:
  LDA EYP,X
  JSR FLOOR_OF
  BMI .st_go
  STA EF
  LDA EXP,X
  JSR LAD_AT
  BMI .st_go
  JSR DECIDE
.st_go:
  LDA ED,X
  BEQ .st_r
  CMP #1
  BEQ .st_l
  CMP #2
  BEQ .st_u
  INC EYP,X
  RTS
.st_u:
  DEC EYP,X
  RTS
.st_l:
  DEC EXP,X
  RTS
.st_r:
  INC EXP,X
  RTS

; X = fruit (EI), A = the ladder, EF = the shelf: the way to go
DECIDE:
  STA T0
  STZ OPTS
  TAY
  LDX EF
  CPY #4
  BEQ .de_nr
  LDA SPANC,X
  AND BITS,Y
  BEQ .de_nr
  LDA #1
  TSB OPTS
.de_nr:
  CPY #0
  BEQ .de_nl
  LDA SPANC,X
  AND BITS-1,Y
  BEQ .de_nl
  LDA #2
  TSB OPTS
.de_nl:
  JSR HAS_UP
  BCC .de_nu
  LDA #4
  TSB OPTS
.de_nu:
  JSR HAS_DN
  BCC .de_nd
  LDA #8
  TSB OPTS
.de_nd:
  LDX EI
  LDY ED,X                     ; not back, if it can go on
  LDA REVB,Y
  EOR #$FF
  AND OPTS
  BEQ .de_k
  STA OPTS
.de_k:
  JSR NEXT_RND
  CMP SMART
  BCS .de_rnd
  LDA CF                       ; the way to Chef Pip
  CMP EF
  BEQ .de_h
  BCS .de_dw
  LDA OPTS
  AND #4
  BEQ .de_h
  LDA #2
  BRA .de_set
.de_dw:
  LDA OPTS
  AND #8
  BEQ .de_h
  LDA #3
  BRA .de_set
.de_h:
  LDA PX
  CMP EXP,X
  BEQ .de_rnd
  BCC .de_hl
  LDA OPTS
  AND #1
  BEQ .de_rnd
  LDA #0
  BRA .de_set
.de_hl:
  LDA OPTS
  AND #2
  BEQ .de_rnd
  LDA #1
  BRA .de_set
.de_rnd:                       ; at random among the ways it can take
  JSR NEXT_RND
  AND #3
  TAY
  LDA #4
  STA T1
.de_rl:
  LDA DIRB,Y
  AND OPTS
  BNE .de_ry
  INY
  TYA
  AND #3
  TAY
  DEC T1
  BNE .de_rl
  LDY ED,X
  LDA REVD,Y
  BRA .de_set
.de_ry:
  TYA
.de_set:
  STA ED,X
  RTS


; ===============================================================
;  SUGAR, CHERRY, HITS
; ===============================================================
SUGAR_HITS:
  LDA CLT
  BEQ .sh_r
  LDX NEN
.sh_l:
  DEX
  BMI .sh_r
  LDA ES,X
  CMP #1
  BNE .sh_l
  LDA EXP,X
  SEC
  SBC CLX
  BCS .sh_x
  EOR #$FF
  INC A
.sh_x:
  CMP #14
  BCS .sh_l
  LDA EYP,X
  SEC
  SBC CLY
  BCS .sh_y
  EOR #$FF
  INC A
.sh_y:
  CMP #14
  BCS .sh_l
  LDA #2
  STA ES,X
  LDA STUNT
  STA ET,X
  BRA .sh_l
.sh_r:
  RTS

CHERRY:
  LDA CHT
  BEQ .cy_r
  LDA TICKS
  AND #1
  BNE .cy_t
  DEC CHT
  BEQ .cy_r
.cy_t:
  LDA PY
  CMP #CHERRY_Y
  BNE .cy_r
  LDA PX
  SEC
  SBC #CHERRY_X
  BCS .cy_x
  EOR #$FF
  INC A
.cy_x:
  CMP #10
  BCS .cy_r
  STZ CHT
  LDY #$05                     ; 500, 1000 from level 3, 1500 from level 5
  LDA LV
  CMP #2
  BCC .cy_p
  LDY #$10
  CMP #4
  BCC .cy_p
  LDY #$15
.cy_p:
  LDA #0
  JSR ADD_PTS
  LDA DOSE
  CMP #9
  BCS .cy_d
  INC DOSE
.cy_d:
  LDA #2
  TSB HUDD
  LDA #W_CHERRY
  LDX #2
  JSR SFX_WHISTLE
.cy_r:
  RTS

HITS:
  LDA GOD
  AND #1
  BNE .ht_r
  LDX NEN
.ht_l:
  DEX
  BMI .ht_r
  LDA ES,X
  CMP #1
  BNE .ht_l
  LDA EXP,X
  SEC
  SBC PX
  BCS .ht_x
  EOR #$FF
  INC A
.ht_x:
  CMP #10
  BCS .ht_l
  LDA EYP,X
  SEC
  SBC PY
  BCS .ht_y
  EOR #$FF
  INC A
.ht_y:
  CMP #12
  BCS .ht_l
  LDA #1
  JMP DIES
.ht_r:
  RTS

; A = what (DEATHS): Chef Pip is caught
DIES:
  PHX
  STA DEATHS
  LDA GSTATE
  BNE .di_r
  LDA #1
  STA GSTATE
  LDA #DIE_T
  STA GT
  STZ CLT
  LDA #S_SPLAT
  LDX #2
  JSR SFX_BOOM
  LDA #W_DOWN
  LDX #2
  JSR SFX_WHISTLE
.di_r:
  PLX
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  JSR CHEF_SPR
  LDA CLT                      ; the cloud of sugar
  BEQ .bs_c
  LDA CLX
  STA OX
  LDA CLY
  DEC A
  STA OY
  LDA CLT
  AND #4
  CLC
  ADC #PT_CLOUD
  STA ON
  LDA #15
  STA OC
  JSR ADD_SPR
.bs_c:
  LDA CHT                      ; the cherry (it blinks before it goes)
  BEQ .bs_y
  CMP #40
  BCS .bs_ys
  LDA FRAME_CNT
  AND #4
  BNE .bs_y
.bs_ys:
  LDA #CHERRY_X
  STA OX
  LDA #CHERRY_Y-1
  STA OY
  LDA #PT_CHERRY
  STA ON
  LDA #8
  STA OC
  JSR ADD_SPR
.bs_y:
  LDX #15                      ; the layers falling: 2 sprites each
.bs_l:
  LDA LYS,X
  CMP #1
  BNE .bs_ln
  TXA
  LSR A
  LSR A
  TAY
  LDA CKX,Y
  STA OX
  LDA LYY,X
  DEC A
  STA OY
  TXA
  AND #3
  TAY
  LDA LYCOL,Y
  STA OC
  TYA
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_LY
  STA ON
  JSR ADD_SPR
  LDA OX
  CLC
  ADC #16
  STA OX
  LDA ON
  CLC
  ADC #4
  STA ON
  JSR ADD_SPR
.bs_ln:
  DEX
  BPL .bs_l
  LDA SPRROT                   ; the fruit, a different first one every frame
  INC A
  CMP #NE
  BCC .bs_r
  LDA #0
.bs_r:
  STA SPRROT
  STA T7
  LDA #NE
  STA T6
.bs_k:
  LDX T7
  JSR FRUIT_SPR
  LDA T7
  INC A
  CMP #NE
  BCC .bs_kn
  LDA #0
.bs_kn:
  STA T7
  DEC T6
  BNE .bs_k
  LDY SPRI
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; Chef Pip: 2 sprites (the face, the hands and the shoes on top of the white)
CHEF_SPR:
  LDA #15
  STA T4
  LDA #9
  STA T5
  LDA GSTATE
  BEQ .cs_a
  LDA GT                       ; caught: he flashes, then he is gone
  CMP #24
  BCS .cs_d
  RTS
.cs_d:
  LSR A
  AND #7
  TAX
  LDA DIE_COL,X
  STA T4
  STA T5
.cs_a:
  LDA PFLR
  BPL .cs_f
  LDA PY                       ; on a ladder
  AND #4
  ASL A
  CLC
  ADC #PT_PC
  BRA .cs_k
.cs_f:
  LDA CLT
  CMP #CLOUD_T-12+1
  BCC .cs_w
  LDA PFACE                    ; shaking the sugar
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_PS
  BRA .cs_k
.cs_w:
  LDA PSTEP                    ; walking
  AND #8
  STA T0
  LDA PFACE
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_PW
.cs_k:
  STA ON
  LDA PX
  STA OX
  LDA PY
  DEC A
  STA OY
  LDA ON
  PHA
  CLC
  ADC #4
  STA ON
  LDA T5
  STA OC
  JSR ADD_SPR
  PLA
  STA ON
  LDA T4
  STA OC
  JMP ADD_SPR

; X = fruit
FRUIT_SPR:
  CPX NEN
  BCS .fs_r
  LDA ES,X
  BEQ .fs_r
  LDA EXP,X
  STA OX
  LDA EYP,X
  DEC A
  STA OY
  LDY ETYP,X
  LDA ECOL,Y
  STA OC
  LDA ES,X
  CMP #3
  BEQ .fs_sq
  CMP #2
  BEQ .fs_st
  LDA EXP,X                    ; walking (or riding)
  CLC
  ADC EYP,X
  AND #8
  LSR A
  BRA .fs_k
.fs_st:
  LDA FRAME_CNT                ; stunned: it flashes white
  AND #8
  BEQ .fs_s8
  LDA #15
  STA OC
.fs_s8:
  LDA #8
.fs_k:
  CLC
  ADC ETYB,Y
  STA ON
  JMP ADD_SPR
.fs_sq:
  LDA #PT_SPLAT
  STA ON
  JMP ADD_SPR
.fs_r:
  RTS

; OX, OY, ON, OC: one sprite more (keeps X)
ADD_SPR:
  LDY SPRI
  CPY #128
  BCS .ad_full
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
.ad_full:
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from haunted keep)
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
S_BIG = S_SPLAT                                 ; (lib_sound: a big noise is not cut by a small one)
BITS:       .byte 1,2,4,8,16
; the ways of the fruit: 0 right, 1 left, 2 up, 3 down
DIRB:       .byte 1,2,4,8                       ; its bit in OPTS
REVB:       .byte 2,1,8,4                       ; the bit of the way back
REVD:       .byte 1,0,3,2                       ; the way back
; the 5 shelves: tile row, y of Chef Pip and of the fruit standing on it
FL_R:       .byte 5,8,11,14,17
FL_Y:       .byte 24,48,72,96,120
; the 5 ladder places: x in pixels, column; one more for the end of the last span
LADX:       .byte 0,56,120,184,240,255
LADCOL:     .byte 0,7,15,23,30
; the 4 cakes: first column, x in pixels
CKC:        .byte 2,10,18,26
CKX:        .byte 16,80,144,208
; colour of a layer falling: sponge, cream, chocolate, icing
LYCOL:      .byte 10,15,6,13
; the fruit: kind of every one, first pattern and colour of every kind (strawberry, banana, lemon)
ETYP:       .byte 0,1,2,0,1,2
ETYB:       .byte PT_ST,PT_BA,PT_LE
ECOL:       .byte 8,11,3
SPX:        .byte 0,240                         ; where a fruit comes in (left, right)
ENTER_D:    .byte 20,60,100,140,180,220         ; frames / 2 before every fruit comes in
RIDE_PTS:   .byte $05,$10,$20,$40               ; fruit riding a layer down: hundreds (BCD)
; MAP: the start of every row (0-23)
MR_LO:      .byte <(MAP+0),<(MAP+32),<(MAP+64),<(MAP+96),<(MAP+128),<(MAP+160),<(MAP+192),<(MAP+224)
            .byte <(MAP+256),<(MAP+288),<(MAP+320),<(MAP+352),<(MAP+384),<(MAP+416),<(MAP+448),<(MAP+480)
            .byte <(MAP+512),<(MAP+544),<(MAP+576),<(MAP+608),<(MAP+640),<(MAP+672),<(MAP+704),<(MAP+736)
MR_HI:      .byte >(MAP+0),>(MAP+32),>(MAP+64),>(MAP+96),>(MAP+128),>(MAP+160),>(MAP+192),>(MAP+224)
            .byte >(MAP+256),>(MAP+288),>(MAP+320),>(MAP+352),>(MAP+384),>(MAP+416),>(MAP+448),>(MAP+480)
            .byte >(MAP+512),>(MAP+544),>(MAP+576),>(MAP+608),>(MAP+640),>(MAP+672),>(MAP+704),>(MAP+736)
; Chef Pip caught: his colours
DIE_COL:    .byte 15,9,8,15,13,9,15,8

; danger of the level (15 at most)
NEN_T:      .byte 3,3,4,4,4,5,5,5,5,6,6,6,6,6,6,6          ; fruit
ESPD_T:     .byte 140,150,160,165,170,175,180,185,190,195,200,205,210,215,220,230 ; speed (/256 of a pixel a frame)
SMART_T:    .byte 96,112,128,140,150,160,170,180,190,200,205,210,215,220,225,230 ; they take the way to Chef Pip (/256)
STUN_T:     .byte 180,175,170,165,160,150,140,130,120,115,110,105,100,95,90,90 ; frames stunned by the sugar

; title: Chef Pip (white, face), a strawberry, a banana, a lemon (sprite Y, X, pattern, colour, second frame)
TITLE_NS = 5
TITLE_SY:   .byte 47,47,40,50,56
TITLE_SX:   .byte 56,56,112,160,208
TITLE_SN:   .byte PT_PW,PT_PW+4,PT_ST,PT_BA,PT_LE
TITLE_SC:   .byte 15,9,8,11,3
TITLE_SA:   .byte 8,8,4,4,4

TXT_LEVELH: .byte "LEVEL "
TXT_PLAYERH: .byte "PLAYER "
TXT_CHEF:   .byte "CHEF PIP"
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
  .byte 9,3,"WALK OVER THE CAKE LAYERS",0
  .byte 10,3,"TO DROP THEM ON THE PLATES",0
  .byte 11,3,"BUTTON = ICING SUGAR",0
  .byte 13,5,"LAYER DOWN            50",0
  .byte 14,5,"FRUIT SQUASHED       500",0
  .byte 15,5,"FRUIT RIDING DOWN   500+",0
  .byte 16,5,"CHERRY          500-1500",0
  .byte 18,5,"A CHEF MORE AT     10000",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 13,11,"PLAYER ",0,$FF
; the sign of the level: a box on rows 9-13
TXT_SIGN:
  .byte 9,9,"              ",0
  .byte 10,9,"              ",0
  .byte 11,9,"              ",0
  .byte 12,9,"              ",0
  .byte 13,9,"              ",0
  .byte $FF

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 13, 9, 12, 0      ; volume at the attack of the note
FLOOR_TAB:     .byte 7, 5, 6, 0        ; lowest volume reached by the decay
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
;  GRAPHICS, LAYOUTS AND SOUND TABLES (generated)
; ===============================================================
; PASTRY PANIC: generated by dev/gen_pastry_panic.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; tiles
T_SHELF = 96
T_LADL = 97
T_LADFL = 99
T_PLATE = 101
T_LY = 104
T_LIFE = 136
T_SUGAR = 137
PT_PW = 0
PT_PC = 32
PT_PS = 48
PT_ST = 64
PT_BA = 76
PT_LE = 88
PT_SPLAT = 100
PT_CLOUD = 104
PT_CHERRY = 112
PT_LY = 116
BIGT = 200
BIGB = 220
NLAYOUT = 6
SPR_LEN = 1184
SPR_PAGES = 5
SPRITES:
  .byte $07,$1F,$1F,$0F,$00,$00,$00,$00,$0F,$1F,$0F,$0F,$0C,$18,$30,$00,$80,$E0,$E0,$C0,$00,$00,$00,$00,$C0,$E0,$C0,$C0,$C0,$60,$30,$00
  .byte $00,$00,$00,$00,$0F,$0E,$0F,$07,$00,$00,$20,$00,$00,$00,$00,$70,$00,$00,$00,$00,$C0,$A0,$E0,$80,$00,$00,$10,$00,$00,$00,$00,$38
  .byte $07,$1F,$1F,$0F,$00,$00,$00,$00,$0F,$1F,$0F,$0F,$07,$06,$06,$00,$80,$E0,$E0,$C0,$00,$00,$00,$00,$C0,$E0,$C0,$C0,$80,$C0,$C0,$00
  .byte $00,$00,$00,$00,$0F,$0E,$0F,$07,$00,$00,$10,$00,$00,$00,$00,$0E,$00,$00,$00,$00,$C0,$A0,$E0,$80,$00,$00,$20,$00,$00,$00,$00,$E0
  .byte $01,$07,$07,$03,$00,$00,$00,$00,$03,$07,$03,$03,$03,$06,$0C,$00,$E0,$F8,$F8,$F0,$00,$00,$00,$00,$F0,$F8,$F0,$F0,$30,$18,$0C,$00
  .byte $00,$00,$00,$00,$03,$05,$07,$01,$00,$00,$08,$00,$00,$00,$00,$1C,$00,$00,$00,$00,$F0,$70,$F0,$E0,$00,$00,$04,$00,$00,$00,$00,$0E
  .byte $01,$07,$07,$03,$00,$00,$00,$00,$03,$07,$03,$03,$01,$03,$03,$00,$E0,$F8,$F8,$F0,$00,$00,$00,$00,$F0,$F8,$F0,$F0,$E0,$60,$60,$00
  .byte $00,$00,$00,$00,$03,$05,$07,$01,$00,$00,$04,$00,$00,$00,$00,$07,$00,$00,$00,$00,$F0,$70,$F0,$E0,$00,$00,$08,$00,$00,$00,$00,$70
  .byte $07,$1F,$1F,$0F,$00,$00,$00,$00,$0F,$7F,$0F,$0F,$0C,$0C,$0C,$00,$80,$E0,$E0,$C0,$00,$00,$00,$00,$C0,$E0,$F0,$C0,$C0,$C0,$60,$00
  .byte $00,$00,$00,$00,$0F,$0F,$0F,$07,$40,$00,$00,$00,$00,$00,$00,$1C,$00,$00,$00,$00,$C0,$C0,$C0,$80,$00,$00,$08,$00,$00,$00,$00,$70
  .byte $01,$07,$07,$03,$00,$00,$00,$00,$03,$07,$0F,$03,$03,$03,$06,$00,$E0,$F8,$F8,$F0,$00,$00,$00,$00,$F0,$FE,$F0,$F0,$30,$30,$30,$00
  .byte $00,$00,$00,$00,$03,$03,$03,$01,$00,$00,$10,$00,$00,$00,$00,$0E,$00,$00,$00,$00,$F0,$F0,$F0,$E0,$02,$00,$00,$00,$00,$00,$00,$38
  .byte $07,$1F,$1F,$0F,$00,$00,$00,$00,$0F,$1F,$1F,$0F,$0C,$18,$30,$00,$80,$E0,$E0,$C0,$00,$00,$00,$00,$C0,$F8,$C0,$C0,$C0,$60,$30,$00
  .byte $00,$00,$00,$00,$0F,$0E,$0F,$07,$00,$00,$00,$00,$00,$00,$00,$70,$00,$00,$00,$00,$C0,$A0,$E0,$80,$00,$04,$0E,$0A,$00,$00,$00,$38
  .byte $01,$07,$07,$03,$00,$00,$00,$00,$03,$1F,$03,$03,$03,$06,$0C,$00,$E0,$F8,$F8,$F0,$00,$00,$00,$00,$F0,$F8,$F8,$F0,$30,$18,$0C,$00
  .byte $00,$00,$00,$00,$03,$05,$07,$01,$00,$20,$70,$50,$00,$00,$00,$1C,$00,$00,$00,$00,$F0,$70,$F0,$E0,$00,$00,$00,$00,$00,$00,$00,$0E
  .byte $02,$0D,$07,$3F,$6D,$7F,$73,$73,$5F,$3F,$1B,$0F,$07,$03,$0C,$18,$40,$B0,$E0,$FC,$B6,$FE,$CE,$CE,$FA,$FC,$D8,$F0,$E0,$C0,$30,$18
  .byte $02,$0D,$07,$3F,$6D,$7F,$73,$73,$5F,$3F,$1B,$0F,$07,$03,$06,$06,$40,$B0,$E0,$FC,$B6,$FE,$CE,$CE,$FA,$FC,$D8,$F0,$E0,$C0,$60,$60
  .byte $02,$0D,$07,$3F,$6D,$7F,$7F,$77,$5F,$3F,$1B,$0F,$07,$03,$10,$20,$40,$B0,$E0,$FC,$B6,$FE,$EE,$BE,$FA,$FC,$D8,$F0,$E0,$C0,$08,$04
  .byte $00,$00,$00,$00,$00,$01,$03,$07,$0F,$1F,$33,$27,$1F,$0F,$0C,$18,$18,$38,$78,$78,$F8,$98,$98,$FC,$FC,$F8,$F0,$F0,$E0,$C0,$30,$18
  .byte $00,$00,$00,$00,$00,$01,$03,$07,$0F,$1F,$33,$27,$1F,$0F,$06,$06,$18,$38,$78,$78,$F8,$98,$98,$FC,$FC,$F8,$F0,$F0,$E0,$C0,$60,$60
  .byte $00,$00,$00,$00,$00,$03,$03,$07,$0F,$1F,$33,$27,$1F,$0F,$10,$20,$18,$38,$78,$78,$F8,$FE,$FE,$FC,$FC,$F8,$F0,$F0,$E0,$C0,$08,$04
  .byte $00,$01,$07,$1F,$3F,$79,$F9,$FF,$FB,$7C,$3F,$1F,$07,$01,$0C,$18,$00,$80,$E0,$F8,$FC,$9E,$9F,$FF,$DF,$3E,$FC,$F8,$E0,$80,$30,$18
  .byte $00,$01,$07,$1F,$3F,$79,$F9,$FF,$FB,$7C,$3F,$1F,$07,$01,$06,$06,$00,$80,$E0,$F8,$FC,$9E,$9F,$FF,$DF,$3E,$FC,$F8,$E0,$80,$60,$60
  .byte $00,$01,$07,$1F,$3F,$7F,$F7,$FF,$FB,$7C,$3F,$1F,$07,$01,$10,$20,$00,$80,$E0,$F8,$FC,$FE,$EF,$FF,$DF,$3E,$FC,$F8,$E0,$80,$08,$04
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$22,$1F,$7F,$FF,$5B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$84,$F8,$FE,$FF,$DA
  .byte $00,$04,$12,$4F,$37,$7F,$BF,$7F,$3B,$4F,$13,$04,$00,$00,$00,$00,$00,$40,$90,$E4,$D8,$FC,$FA,$FC,$B8,$E4,$90,$40,$00,$00,$00,$00
  .byte $00,$10,$45,$0B,$5F,$3F,$2F,$BF,$3F,$27,$45,$10,$00,$00,$00,$00,$00,$40,$10,$A0,$F4,$F8,$E8,$FA,$F8,$C8,$44,$10,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$04,$08,$3C,$7E,$DF,$BF,$FF,$7E,$3C,$00,$00,$30,$58,$80,$00,$40,$40,$20,$20,$78,$7E,$6E,$7E,$7E,$3C,$00,$00
  .byte $00,$3F,$7F,$5D,$7F,$77,$7F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$EE,$FF,$BB,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$FF,$F7,$FF,$DD,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FC,$FE,$7A,$FE,$EE,$FE,$FC,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$19,$7F,$FF,$FF,$7F,$33,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$99,$FF,$FF,$FF,$FF,$33,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$99,$FF,$FF,$FF,$FF,$33,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$98,$FE,$FF,$FF,$FE,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$7F,$5A,$7F,$7F,$6E,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$D6,$FF,$FF,$EE,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$FF,$B5,$FF,$FF,$EE,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FE,$AC,$FE,$FE,$EC,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$1F,$3F,$7F,$5B,$49,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$FF,$FF,$FF,$FF,$B7,$12,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$C0,$FF,$FF,$FF,$FF,$6E,$24,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F8,$FC,$FE,$DD,$49,$00,$00,$00,$00,$00,$00,$00,$00

; game tiles 96-137: patterns and colours
TILEP:
  .byte $FF,$FF,$AA,$00,$00,$00,$00,$00,$60,$60,$7F,$60,$60,$60,$7F,$60,$06,$06,$FE,$06,$06,$06,$FE,$06,$FF,$FF,$AA,$60,$60,$60,$7F,$60
  .byte $FF,$FF,$AA,$06,$06,$06,$FE,$06,$3F,$FF,$7F,$1F,$07,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$FC,$FF,$FE,$F8,$E0,$00,$00,$00
  .byte $00,$3F,$7F,$5D,$7F,$77,$7F,$3F,$00,$FF,$FF,$EE,$FF,$BB,$FF,$FF,$00,$FF,$FF,$F7,$FF,$DD,$FF,$FF,$00,$FC,$FE,$7A,$FE,$EE,$FE,$FC
  .byte $00,$00,$00,$3F,$7F,$5D,$7F,$77,$00,$00,$00,$FF,$FF,$EE,$FF,$BB,$00,$00,$00,$FF,$FF,$F7,$FF,$DD,$00,$00,$00,$FC,$FE,$7A,$FE,$EE
  .byte $00,$19,$7F,$FF,$FF,$7F,$33,$00,$00,$99,$FF,$FF,$FF,$FF,$33,$00,$00,$99,$FF,$FF,$FF,$FF,$33,$00,$00,$98,$FE,$FF,$FF,$FE,$30,$00
  .byte $00,$00,$00,$19,$7F,$FF,$FF,$7F,$00,$00,$00,$99,$FF,$FF,$FF,$FF,$00,$00,$00,$99,$FF,$FF,$FF,$FF,$00,$00,$00,$98,$FE,$FF,$FF,$FE
  .byte $00,$7F,$5A,$7F,$7F,$6E,$7F,$00,$00,$FF,$D6,$FF,$FF,$EE,$FF,$00,$00,$FF,$B5,$FF,$FF,$EE,$FF,$00,$00,$FE,$AC,$FE,$FE,$EC,$FE,$00
  .byte $00,$00,$00,$7F,$5A,$7F,$7F,$6E,$00,$00,$00,$FF,$D6,$FF,$FF,$EE,$00,$00,$00,$FF,$B5,$FF,$FF,$EE,$00,$00,$00,$FE,$AC,$FE,$FE,$EC
  .byte $00,$00,$07,$1F,$3F,$7F,$5B,$49,$01,$03,$FF,$FF,$FF,$FF,$B7,$12,$80,$C0,$FF,$FF,$FF,$FF,$6E,$24,$00,$00,$E0,$F8,$FC,$FE,$DD,$49
  .byte $00,$00,$00,$00,$07,$1F,$3F,$7F,$00,$00,$01,$03,$FF,$FF,$FF,$FF,$00,$00,$80,$C0,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$E0,$F8,$FC,$FE
  .byte $38,$7C,$7C,$38,$38,$7C,$54,$00,$38,$28,$7C,$7C,$7C,$7C,$7C,$00
TILEC:
  .byte $B1,$A1,$A1,$61,$61,$61,$61,$61,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$B1,$A1,$A1,$E1,$E1,$E1,$E1,$E1
  .byte $B1,$A1,$A1,$E1,$E1,$E1,$E1,$E1,$F1,$F1,$E1,$E1,$41,$11,$11,$11,$F1,$F1,$E1,$E1,$41,$11,$11,$11,$F1,$F1,$E1,$E1,$41,$11,$11,$11
  .byte $B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1
  .byte $11,$11,$B1,$B1,$B1,$A1,$A1,$A1,$11,$11,$B1,$B1,$B1,$A1,$A1,$A1,$11,$11,$B1,$B1,$B1,$A1,$A1,$A1,$11,$11,$B1,$B1,$B1,$A1,$A1,$A1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1
  .byte $11,$11,$F1,$F1,$F1,$F1,$F1,$F1,$11,$11,$F1,$F1,$F1,$F1,$F1,$F1,$11,$11,$F1,$F1,$F1,$F1,$F1,$F1,$11,$11,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $61,$91,$61,$61,$61,$61,$61,$61,$61,$91,$61,$61,$61,$61,$61,$61,$61,$91,$61,$61,$61,$61,$61,$61,$61,$91,$61,$61,$61,$61,$61,$61
  .byte $11,$11,$61,$91,$61,$61,$61,$61,$11,$11,$61,$91,$61,$61,$61,$61,$11,$11,$61,$91,$61,$61,$61,$61,$11,$11,$61,$91,$61,$61,$61,$61
  .byte $81,$81,$D1,$D1,$D1,$D1,$D1,$D1,$81,$81,$D1,$D1,$D1,$D1,$D1,$D1,$81,$81,$D1,$D1,$D1,$D1,$D1,$D1,$81,$81,$D1,$D1,$D1,$D1,$D1,$D1
  .byte $11,$11,$81,$81,$D1,$D1,$D1,$D1,$11,$11,$81,$81,$D1,$D1,$D1,$D1,$11,$11,$81,$81,$D1,$D1,$D1,$D1,$11,$11,$81,$81,$D1,$D1,$D1,$D1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1

; the layouts (8 bytes each): the spans of the 5 shelves (bit k = span k)
LO_SPAN:
  .byte $0F,$0F,$0F,$0F,$0F,$00,$00,$00,$0F,$0F,$0D,$0F,$0F,$00,$00,$00
  .byte $0F,$0F,$0F,$0F,$0F,$00,$00,$00,$0F,$05,$0F,$0F,$0F,$00,$00,$00
  .byte $0F,$02,$0F,$0D,$0F,$00,$00,$00,$0F,$0D,$0A,$0F,$0F,$00,$00,$00
; the ladders between shelf f and f + 1 (bit p = ladder column p)
LO_LAD:
  .byte $15,$1C,$0E,$19,$00,$00,$00,$00,$0E,$0B,$0C,$0C,$00,$00,$00,$00
  .byte $0C,$03,$0B,$1A,$00,$00,$00,$00,$09,$07,$12,$12,$00,$00,$00,$00
  .byte $06,$06,$0E,$15,$00,$00,$00,$00,$06,$1A,$16,$07,$00,$00,$00,$00
; the shelf of every layer (16 each: cake * 4 + layer, 0 = sponge at the bottom)
LO_LY:
  .byte $03,$02,$01,$00,$04,$03,$02,$01,$04,$03,$02,$01,$04,$02,$01,$00
  .byte $04,$03,$02,$01,$04,$03,$01,$00,$04,$03,$02,$01,$04,$02,$01,$00
  .byte $04,$03,$01,$00,$03,$02,$01,$00,$04,$03,$01,$00,$04,$03,$02,$00
  .byte $04,$03,$02,$00,$04,$03,$02,$00,$04,$03,$02,$01,$04,$03,$02,$00
  .byte $04,$03,$02,$00,$04,$02,$01,$00,$04,$03,$02,$00,$04,$03,$02,$00
  .byte $04,$03,$01,$00,$04,$03,$02,$00,$04,$03,$01,$00,$04,$03,$02,$00

; big letters of the title
BIG_TOP:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0,$00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98,$00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
BIG_BOT:
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00,$18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00,$01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00,$01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00,$01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
BIG_TOPC:
  .byte $D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1
  .byte $D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1
  .byte $D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1
  .byte $D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1
  .byte $D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1
BIG_BOTC:
  .byte $B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1
  .byte $B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1
  .byte $B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1
  .byte $B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1
  .byte $B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1,$B1,$B1,$A1,$A1,$B1,$A1,$A1,$A1
TXT_BIG:
  .byte 3,4,200,201,202,203,204,205,206,207,208,209,210,211,32,32,200,201,202,203,212,213,214,215,216,217,0
  .byte 4,4,220,221,222,223,224,225,226,227,228,229,230,231,32,32,220,221,222,223,232,233,234,235,236,237,0
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
  .byte $25,$06,$2A,$06,$2E,$06,$2A,$06,$31,$0C,$2E,$0C,$2F,$06,$2E,$06,$2C,$06,$2A,$06,$2C,$18,$27,$06,$2C,$06,$2F,$06,$2C,$06,$33,$0C
  .byte $2F,$0C,$31,$06,$2F,$06,$2E,$06,$2C,$06,$2E,$18,$2A,$06,$2E,$06,$31,$06,$2E,$06,$33,$0C,$31,$0C,$2F,$06,$2E,$06,$2C,$06,$29,$06
  .byte $2A,$06,$2E,$06,$2C,$06,$29,$06,$2A,$18,$FF
SG0_1:
  .byte $22,$18,$1E,$18,$1D,$18,$25,$18,$23,$18,$20,$18,$1D,$18,$25,$18,$22,$18,$1E,$18,$20,$18,$25,$18,$22,$18,$FF
SG0_2:
  .byte $12,$0C,$0D,$0C,$12,$0C,$0D,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$08,$0C,$0F,$0C,$08,$0C,$0F,$0C,$0D,$0C,$08,$0C,$0D,$0C,$11,$0C
  .byte $12,$0C,$0D,$0C,$12,$0C,$0A,$0C,$0B,$0C,$12,$0C,$0D,$0C,$0D,$0C,$12,$18,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$04,$18,$FF
SG1_0:
  .byte $25,$06,$29,$06,$2C,$06,$31,$06,$2E,$06,$2A,$06,$31,$18,$FF
SG1_1:
  .byte $1D,$0C,$20,$0C,$1E,$0C,$22,$18,$FF
SG1_2:
  .byte $0D,$0C,$08,$0C,$06,$0C,$0D,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$02,$06,$04,$18,$FF
SG2_0:
  .byte $2C,$06,$2E,$06,$2C,$06,$29,$06,$31,$0C,$2C,$06,$29,$06,$2A,$06,$27,$06,$24,$06,$25,$24,$FF
SG2_1:
  .byte $29,$18,$25,$0C,$27,$0C,$20,$0C,$1D,$24,$FF
SG2_2:
  .byte $0D,$0C,$08,$0C,$0A,$0C,$05,$0C,$08,$0C,$0D,$24,$FF
SG2_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$04,$24,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$24,$2F,$2D,$2F,$32,$34,$38,$3B,$3F,$44,$4A,$50,$58,$62,$6E,$7D,$1E,$1E,$1E,$18,$18,$18,$14,$14,$14,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $0F,$0F,$5B,$5B,$5B,$5B,$5B,$5B,$00,$00,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$BD,$2A,$2C,$26,$28,$33,$36,$2F,$32,$3F,$42,$3A,$3D,$4D
  .byte $51,$47,$4B,$5F,$64,$57,$5C,$74,$7A,$6B,$71,$8F,$96,$84,$8B,$AF,$B8,$A2,$AA,$D7,$E2,$C7,$D1,$08,$16,$F4,$01,$3C,$3C,$3C,$3C,$00
  .byte $00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$78,$78,$78,$78,$78,$78,$78,$78,$7F,$7F,$7F,$7F,$7F
  .byte $7F,$7F,$7F,$86,$86,$86,$86,$86,$86,$86,$86,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$18,$20,$20,$50,$50
  .byte $50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$07,$05,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$07,$06,$06,$05,$05,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0C,$0B,$09,$08,$06,$05
  .byte $03,$02,$0A,$0A,$09,$09,$08,$08,$00,$00,$0A,$09,$08,$07,$07,$06,$05,$04,$04,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A
  .byte $0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$0D,$0C,$0A,$09,$00
  .byte $00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09
  .byte $08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B
  .byte $0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$03,$11,$22,$32,$33,$5B,$73,$9B,$9E
WH_LEN:
  .byte $00,$02,$0E,$11,$10,$01,$28,$18,$28,$03,$13
W_PRESS = 1
W_FALL = 2
W_CHERRY = 3
W_EMPTY = 4
W_STEP = 5
W_DOWN = 6
W_EXTRA = 7
W_OVER = 8
W_KEY = 9
W_SIGN = 10

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$06,$08,$0A,$09,$08,$07,$06
  .byte $05,$04,$03,$02,$01,$00,$00
EX_NP:
  .byte $00,$14,$15,$16,$17,$18,$19,$1A,$1B,$04,$04,$05,$05,$06,$06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02
EX_VC:
  .byte $00,$0C,$0A,$08,$06,$04,$02,$00,$00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$7D,$B3,$F0,$36,$85,$E2,$4F,$D0,$87,$96,$A6,$B8,$CC,$E1,$F8,$12,$2E,$4E,$71,$99,$C6,$FA,$36,$7D,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_TH:
  .byte $00,$03,$03,$03,$04,$04,$04,$05,$05,$01,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$03,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$09,$19
EX_LEN:
  .byte $00,$08,$10,$0E
S_LAND = 1
S_SPLAT = 2
S_PUFF = 3

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$66, <144,>144, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$66, <144,>144, <BIG_BOTC,>BIG_BOTC
  .byte 1, $00,$43, <336,>336, <TILEP,>TILEP
  .byte 1, $00,$63, <336,>336, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$4E, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$6E, <144,>144, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$6E, <144,>144, <BIG_BOTC,>BIG_BOTC
  .byte 1, $00,$4B, <336,>336, <TILEP,>TILEP
  .byte 1, $00,$6B, <336,>336, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$56, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$76, <144,>144, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$76, <144,>144, <BIG_BOTC,>BIG_BOTC
  .byte 1, $00,$53, <336,>336, <TILEP,>TILEP
  .byte 1, $00,$73, <336,>336, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
