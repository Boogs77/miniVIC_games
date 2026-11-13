;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   BRICK DROP  -  an original falling-block puzzle game       ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - pieces of 4 bricks fall into a well of 10 x 20 cells:    ;
;     move them, turn them, close the rows of the wall; a full ;
;     row goes away, 4 rows at once are a BRICK DROP           ;
;   - 7 pieces, the next one in the box; the statistics of the ;
;     pieces on the left; a level more every 10 rows, faster   ;
;     and with new colours; start level 0-9 from the menu      ;
;   - points: 40 / 100 / 300 / 1200 for 1-4 rows, times the    ;
;     level + 1, and 1 for every row dropped holding down      ;
;   - 1 or 2 players, one whole game each, in turn             ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 54 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     3 tunes to choose from (or none), looped while you play, ;
;     with the effects of the bricks over them                 ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: 1 while the player still has his game to play
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
GSTATE      = $50      ; 0 falling, 1 rows flashing, 2 before the next piece, 3 game over fill, 4 over
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lines and level, 4 next piece and statistics, 16 BRICK DROP
PT          = $53      ; the piece falling (0-6: I O T S Z J L)
PR          = $54      ; its rotation (0-3)
PCX         = $55      ; its pivot: column (0-9), row (0-21) of the well
PCY         = $56
NXT         = $57      ; the next piece
GCNT        = $58      ; frames since the last row down
DAS         = $59      ; frames left / right is held
OLDJ        = $5A      ; the joystick in the frame before
DNOK        = $5B      ; 1 = down was released since the piece came
SOFT        = $5C      ; rows dropped holding down
LVL         = $5D      ; the level
SLV         = $5E      ; 2 bytes: start level of every player (menu)
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
LNL         = $72      ; lines (BCD): tens and units
LNH         = $73      ; thousands and hundreds
NX          = $74      ; a place to try: column, row, rotation
NY          = $75
NR          = $76
NLIN        = $77      ; rows full at the last lock
FILLR       = $78      ; game over: the next row to fill
MUS         = $79      ; music: 0-2 the tunes, 3 none
MSEL        = $7A      ; menu: 0 level, 1 music
PCS         = $7B      ; 2 bytes: pieces of the game (tests)
BDN         = $7D      ; BRICK DROPs of the game (tests)
MT          = $7E      ; 2 bytes: frames left before the menu starts by itself
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
NEWJ        = $88      ; pressed in this frame
BDT         = $89      ; frames of the BRICK DROP sign
LNREC       = $8A      ; 2 bytes: lines of every player for the records (255 at most)
LVUP        = $8C      ; 1 = the colours of a new level to load
LASTT       = $8D      ; the last piece rolled (7 = none)
WLIM        = $8E      ; DRAW_WELL_TO: the row after the last one
Q0          = $98      ; temporaries
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
SND_MODE   = $FB         ; 0 = game effects, 1 = a tune once, 2 = the music of the game and the effects
SND_BUSY   = $FC         ; 1 while a tune played once is playing
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

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
CMD_START  = 2           ; the tune SONG once
CMD_LOOP   = 3           ; the tune SONG again and again, the effects over it
SONG       = $0730       ; tune to play

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
WELL       = $0800       ; 22 rows x 10 cells (rows 0-1 hidden): 0 empty, 1-7 bricks, 8 grey
FULLF      = $0900       ; 22: 1 = the row is full
STATS      = $0920       ; 7 x 2: pieces of every kind (BCD)

; ---------------- parameters ----------------
BTN_MASK    = %00110000
WCOL        = 11         ; the well on the screen: first column
DAS_T       = 16         ; frames before left / right repeats
DAS_R       = 6          ; frames between two repeats
SOFT_T      = 2          ; frames a row holding down
ARE_T       = 10         ; frames before the next piece comes
FLASH_T     = 24         ; frames the full rows flash
FILL_T      = 3          ; game over: frames a grey row
BDT_T       = 150        ; frames of the BRICK DROP sign
MENU_T      = 900        ; the menu starts by itself after 15 s
OVER_T      = 180        ; frames of the GAME OVER of a player

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 54         ; fixed zone of the game in the save area
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
  STZ MUS
  LDA #1
  STA NPL
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  STZ SLV,X
  STZ LNREC,X
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
  JSR PRINT_BIG
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

PRINT_BIG:
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JMP PRINT

; rows 9-18 of the title (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JMP PRINT

; one frame of the title: every 8 s the title page and the table of the records take turns
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR REC_TICK
  BCC .tf_e
  LDA REC_PG
  BEQ .tf_p
  JSR REC_SHOW
  BRA .tf_e
.tf_p:
  JSR TITLE_PAGE
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: one whole game for every player, in turn
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LNREC,X
  STZ LIVES,X
  DEX
  BPL .ng_p
  LDX NPL                      ; every player has his game to play
.ng_l:
  DEX
  LDA #1
  STA LIVES,X
  TXA
  BNE .ng_l
  STZ CURP

PLAYER_START:
  LDX #$FF
  TXS
  JSR MENU                     ; start level and music
  JSR GAME_SETUP


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
  LDA OLDJ
  EOR #$FF
  AND JOYC
  STA NEWJ
  LDA GSTATE
  BNE .gl_1
  JSR FALL
  BRA .gl_h
.gl_1:
  CMP #1
  BNE .gl_2
  JSR FLASH
  BRA .gl_h
.gl_2:
  CMP #2
  BNE .gl_3
  JSR ENTRY
  BRA .gl_h
.gl_3:
  CMP #3
  BNE .gl_h
  JSR TOPFILL
.gl_h:
  JSR UPDATE_HUD
WEND:
  LDA JOYC
  STA OLDJ
  JSR VDP_INT_ON
  LDA GSTATE
  CMP #4
  BNE GAME_LOOP
  ; fall into PLAYER_OVER


; ===============================================================
;  THE WALL IS UP TO THE TOP: the next player, or the records
; ===============================================================
PLAYER_OVER:
  JSR VDP_INT_OFF
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  LDA NPL
  CMP #2
  BNE .po_1
  LDX #13
  LDY #WCOL+1
  JSR NT_XY
  LDX #0
.po_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .po_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.po_1:
  JSR VDP_INT_ON
  LDX CURP                     ; the lines for the records: 255 at most
  STZ LIVES,X
  JSR LINES_BIN
  STA LNREC,X
  LDA #OVER_T
  JSR WAIT_FRAMES
  LDA #CMD_GAME
  STA SND_CMD
  INC CURP
  LDA CURP
  CMP NPL
  BCS GAME_OVER
  JMP PLAYER_START

; A = the lines of the game in binary, 255 at most (keeps X)
LINES_BIN:
  LDA LNH
  CMP #$03
  BCS .lb_max
  TAY                          ; hundreds: 0-2
  LDA LNL
  AND #$0F
  STA Q0
  LDA LNL                      ; tens * 10 = tens * 8 + tens * 2
  LSR A
  LSR A
  LSR A
  LSR A
  STA Q1
  ASL A
  ASL A
  CLC
  ADC Q1
  ASL A
  CLC
  ADC Q0
.lb_h:
  DEY
  BMI .lb_e
  CLC
  ADC #100
  BCS .lb_max
  BRA .lb_h
.lb_e:
  RTS
.lb_max:
  LDA #255
  RTS

GAME_OVER:
  LDA #CMD_GAME
  STA SND_CMD
  JSR HIDE_SPRITES
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
  LDA LNREC,X                  ; extra byte: the lines
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
REC_NAME:  .byte "BRICK DROP      "
REC_HEAD:  .byte "BEST BUILDERS",0
REC_XLBL:  .byte "LINES ",0


; ===============================================================
;  MENU: the start level and the music of the player CURP
; ===============================================================
MENU:
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  JSR DRAW_TOP
  JSR PRINT_BIG
  LDA #<TXT_MENU
  STA TP
  LDA #>TXT_MENU
  STA TP+1
  JSR PRINT
  LDA NPL
  CMP #2
  BNE .mn_1
  LDX #7                       ; PLAYER n
  LDY #12
  JSR NT_XY
  LDX #0
.mn_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .mn_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.mn_1:
  STZ MSEL
  JSR MENU_T0
  JSR MUSIC_GO                 ; the music chosen plays at once
  JSR VDP_INT_ON
.mn_rel:                       ; buttons released...
  JSR MENU_FRAME
  LDA JOYC
  AND #BTN_MASK
  BNE .mn_rel
.mn_l:                         ; ...then the joystick chooses, a button starts
  JSR MENU_FRAME
  LDA NEWJ
  AND #BTN_MASK
  BNE .mn_go
  LDA MT                       ; 15 s without a move: it starts by itself
  BNE .mn_d
  DEC MT+1
  BMI .mn_go
.mn_d:
  DEC MT
  LDA NEWJ
  AND #%00000011               ; up / down: the other line
  BEQ .mn_lr
  LDA MSEL
  EOR #1
  STA MSEL
  BRA .mn_snd
.mn_lr:
  LDA NEWJ
  AND #%00001100
  BEQ .mn_l
  AND #%00001000
  BNE .mn_rt
  LDA MSEL                     ; left
  BNE .mn_ml
  LDX CURP
  DEC SLV,X
  BPL .mn_snd
  LDA #9
  STA SLV,X
  BRA .mn_snd
.mn_ml:
  DEC MUS
  BPL .mn_mus
  LDA #3
  STA MUS
  BRA .mn_mus
.mn_rt:
  LDA MSEL                     ; right
  BNE .mn_mr
  LDX CURP
  LDA SLV,X
  INC A
  CMP #10
  BCC .mn_sl
  LDA #0
.mn_sl:
  STA SLV,X
  BRA .mn_snd
.mn_mr:
  LDA MUS
  INC A
  AND #3
  STA MUS
.mn_mus:
  JSR MUSIC_GO
.mn_snd:
  JSR MENU_T0
  LDA #W_MENU
  LDX #2
  JSR SFX_WHISTLE
  BRA .mn_l
.mn_go:
  JMP HIDE_SPRITES

MENU_T0:
  LDA #<MENU_T
  STA MT
  LDA #>MENU_T
  STA MT+1
  RTS

; the music MUS: a tune looped, or silence
MUSIC_GO:
  LDA MUS
  CMP #3
  BCS .mg_off
  INC A
  STA SONG
  LDA #CMD_LOOP
  STA SND_CMD
  RTS
.mg_off:
  LDA #CMD_GAME
  STA SND_CMD
  RTS

; one frame of the menu: the joystick, the two cursors (the line chosen blinks)
MENU_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  LDA OLDJ
  EOR #$FF
  AND JOYC
  STA NEWJ
  LDA JOYC
  STA OLDJ
  LDX CURP                     ; the level: row 11
  LDY SLV,X
  LDA MLV_COL,Y
  LDY #0
  LDX #11*8-5
  JSR MENU_CUR
  LDY MUS                      ; the music: row 16
  LDA MUS_COL,Y
  LDY #1
  LDX #16*8-5
  JSR MENU_CUR
  LDA #$D0
  STA SAT_BUFFER+8
  LDA #9
  STA SATB
  JMP VDP_INT_ON

; A = column, X = sprite y, Y = line (0 / 1): the cursor of that line
MENU_CUR:
  ASL A
  ASL A
  ASL A
  SEC
  SBC #4
  PHA
  TYA
  ASL A
  ASL A
  STA Q0
  TXA
  LDX Q0
  STA SAT_BUFFER,X
  PLA
  STA SAT_BUFFER+1,X
  LDA #PT_CUR
  STA SAT_BUFFER+2,X
  LDA #14                      ; the other line: grey
  CPY MSEL
  BNE .mc_c
  LDA FRAME_CNT                ; the line chosen: yellow, off 8 frames out of 32
  AND #$18
  CMP #$18
  LDA #11
  BCC .mc_c
  LDA #0
.mc_c:
  STA SAT_BUFFER+3,X
  RTS


; ===============================================================
;  HUD: row 0 (scores), the panels beside the well
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

; LINES (3 digits, row 11) and LEVEL (2 digits, row 14)
DRAW_LINES:
  LDX #11
  LDY #26
  JSR NT_XY
  LDA LNH
  AND #$0F
  ORA #$30
  STA VDATA
  LDA LNL
  JSR PUT_2
  LDX #14
  LDY #27
  JSR NT_XY
  LDA LVL
  CMP #100
  BCC .dl_n
  LDA #99
.dl_n:
  JSR BIN2BCD
  JMP PUT_2

; X = piece: its count on the left (row 4 + 2 X, columns 5-7)
DRAW_STAT:
  STX Q2
  TXA
  ASL A
  ADC #4
  TAX
  LDY #5
  JSR NT_XY
  LDA Q2
  ASL A
  TAX
  LDA STATS+1,X
  AND #$0F
  ORA #$30
  STA VDATA
  LDA STATS,X
  JMP PUT_2

; the next piece in the box (rows 5-6, columns 24-29)
DRAW_NEXT:
  LDX #5
  JSR .dn_clr
  LDX #6
  JSR .dn_clr
  LDA NXT
  ASL A
  ASL A
  ASL A
  ASL A
  STA Q2                       ; rotation 0
  LDA #4
  STA Q3
.dn_c:
  LDY Q2
  LDA PC_DY,Y
  CLC
  ADC #5
  TAX
  LDA PC_DX,Y
  CLC
  ADC #26
  TAY
  JSR NT_XY
  LDA NXT
  CLC
  ADC #T_BRICK
  STA VDATA
  INC Q2
  DEC Q3
  BNE .dn_c
  RTS
.dn_clr:
  LDY #24
  JSR NT_XY
  LDX #6
  LDA #$20
.dn_s:
  STA VDATA
  NOP
  DEX
  BNE .dn_s
  RTS

UPDATE_HUD:
  LDA BDT                      ; the BRICK DROP sign goes away
  BEQ .uh_0
  DEC BDT
  BNE .uh_0
  LDA #<TXT_NOBRICK
  STA TP
  LDA #>TXT_NOBRICK
  STA TP+1
  JSR PRINT
.uh_0:
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  STA Q1
  AND #1
  BEQ .uh_l
  LDX CURP
  JSR DRAW_SCORE
.uh_l:
  LDA Q1
  AND #2
  BEQ .uh_n
  JSR DRAW_LINES
.uh_n:
  LDA Q1
  AND #4
  BEQ .uh_b
  JSR DRAW_NEXT
  LDX PT
  JSR DRAW_STAT
.uh_b:
  LDA Q1
  AND #16
  BEQ .uh_r
  LDA #<TXT_BRICK
  STA TP
  LDA #>TXT_BRICK
  STA TP+1
  JMP PRINT
.uh_r:
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M / PTS_H (BCD) to the player playing; 999999 at most
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
  BCC .as_d
  LDA #$99
  STA SCL,X
  STA SCM,X
  STA SCH,X
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  A NEW GAME FOR THE PLAYER CURP: the empty well, the first piece
; ===============================================================
GAME_SETUP:
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the screen is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDX CURP
  LDA SLV,X
  STA LVL
  STZ LNL
  STZ LNH
  STZ GSTATE
  STZ BDT
  STZ LVUP
  STZ SOFT
  STZ DAS
  STZ HUDD
  STZ PCS
  STZ PCS+1
  STZ BDN
  LDA #$3F                     ; a button still held from the menu does not turn the piece
  STA OLDJ
  LDX #13
.gs_s:
  STZ STATS,X
  DEX
  BPL .gs_s
  LDX #219
.gs_w:
  STZ WELL,X
  DEX
  CPX #$FF
  BNE .gs_w
  LDA #7
  STA LASTT
  JSR ROLL
  STA NXT
  JSR CLEAR_NT
  JSR DRAW_TOP
  JSR DRAW_FRAME
  JSR SET_PALETTE
  JSR DRAW_WELL
  LDX #6
.gs_t:
  PHX
  JSR DRAW_STAT
  PLX
  DEX
  BPL .gs_t
  JSR DRAW_LINES
  JSR MUSIC_GO                 ; the tune from its start
  JSR SPAWN
  JSR UPDATE_HUD
  JMP VDP_INT_ON               ; (display on)

; the walls, the box of the next piece, the labels, the small pieces
DRAW_FRAME:
  LDA #1
  STA Q0
.df_w:
  LDX Q0
  LDY #WCOL-1
  JSR NT_XY
  LDA #T_WALL
  STA VDATA
  LDX Q0
  LDY #WCOL+10
  JSR NT_XY
  LDA #T_WALL
  STA VDATA
  INC Q0
  LDA Q0
  CMP #22
  BNE .df_w
  LDX #22                      ; the floor
  LDY #WCOL-1
  LDA #12
  JSR WALL_RUN
  LDX #3                       ; the box: rows 3-8, columns 23-30
  LDY #23
  LDA #8
  JSR WALL_RUN
  LDX #8
  LDY #23
  LDA #8
  JSR WALL_RUN
  LDA #4
  STA Q0
.df_b:
  LDX Q0
  LDY #23
  JSR NT_XY
  LDA #T_WALL
  STA VDATA
  LDX Q0
  LDY #30
  JSR NT_XY
  LDA #T_WALL
  STA VDATA
  INC Q0
  LDA Q0
  CMP #8
  BNE .df_b
  LDA #<TXT_GAME
  STA TP
  LDA #>TXT_GAME
  STA TP+1
  JSR PRINT
  LDA #0                       ; the small pieces: rows 4-16, columns 1-2
  STA Q0
.df_i:
  LDA Q0
  ASL A
  ADC #4
  TAX
  LDY #1
  JSR NT_XY
  LDA Q0
  ASL A
  ADC #T_ICON
  STA VDATA
  INC A
  NOP
  STA VDATA
  INC Q0
  LDA Q0
  CMP #7
  BNE .df_i
  LDA NPL                      ; PLAYER n
  CMP #2
  BNE .df_e
  LDX #17
  LDY #23
  JSR NT_XY
  LDX #0
.df_p:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .df_p
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.df_e:
  RTS

; X = row, Y = column, A = cells: a run of wall bricks
WALL_RUN:
  PHA
  JSR NT_XY
  PLX
  LDA #T_WALL
.wr_l:
  STA VDATA
  NOP
  DEX
  BNE .wr_l
  RTS

; the colours of the level LVL (palette LVL mod 10) in the three thirds
SET_PALETTE:
  LDA LVL
.sp_m:
  CMP #10
  BCC .sp_p
  SBC #10
  BRA .sp_m
.sp_p:
  TAX
  STA Q1
  ASL A                        ; * 7 for the small pieces
  ASL A
  ASL A
  SEC
  SBC Q1
  STA Q1
  LDA BRC_LO,X
  STA PTR
  LDA BRC_HI,X
  STA PTR+1
  LDA #0
  STA Q0                       ; the third: 0, 8, 16 (high byte of the VRAM address)
.sp_t:
  LDA #<(T_BRICK*8)            ; the 7 bricks
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $20 | >(T_BRICK*8))
  CLC
  ADC Q0
  STA VREG
  LDY #0
.sp_b:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #56
  BNE .sp_b
  LDA #<(T_ICON*8)             ; the small pieces: 2 tiles of one colour each
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $20 | >(T_ICON*8))
  CLC
  ADC Q0
  STA VREG
  LDY Q1
.sp_i:
  LDA ICCOL,Y
  LDX #16
.sp_c:
  STA VDATA
  DEX
  BNE .sp_c
  INY
  TYA
  SEC
  SBC Q1
  CMP #7
  BNE .sp_i
  LDA Q0
  CLC
  ADC #8
  STA Q0
  CMP #24
  BNE .sp_t
  RTS

; the rows 2-21 of the well
DRAW_WELL:
  LDA #22
  STA WLIM
DRAW_WELL_TO:                  ; rows 2 to WLIM - 1
  LDX #2
.dw_r:
  PHX
  JSR DRAW_ROW
  PLX
  INX
  CPX WLIM
  BNE .dw_r
  RTS

; X = row of the well (2-21): its 10 cells
DRAW_ROW:
  LDY #WCOL
  JSR NT_XY
  LDA ROW10,X
  TAX
  LDY #10
.dr_c:
  LDA WELL,X
  CLC
  ADC #T_EMPTY
  STA VDATA
  INX
  DEY
  BNE .dr_c
  RTS


; ===============================================================
;  THE PIECE FALLING
; ===============================================================
FALL:
  LDA NEWJ                     ; button 1: clockwise, button 2: the other way
  AND #%00010000
  BEQ .fa_b2
  LDA PR
  INC A
  JSR TRY_ROT
.fa_b2:
  LDA NEWJ
  AND #%00100000
  BEQ .fa_lr
  LDA PR
  CLC
  ADC #3
  JSR TRY_ROT
.fa_lr:
  LDA JOYC                     ; left / right: at once, then repeated
  AND #%00001100
  BEQ .fa_nolr
  CMP #%00001100
  BEQ .fa_nolr
  LDX #$FF                     ; X = the step
  CMP #%00000100
  BEQ .fa_d
  LDX #1
.fa_d:
  AND NEWJ
  BEQ .fa_held
  STZ DAS
  BRA .fa_mv
.fa_held:
  INC DAS
  LDA DAS
  CMP #DAS_T
  BCC .fa_g
  LDA #DAS_T-DAS_R
  STA DAS
.fa_mv:
  JSR SET_N
  TXA
  CLC
  ADC NX
  STA NX
  JSR TRY_MOVE
  BCC .fa_wall
  LDA #W_MOVE
  LDX #2
  JSR SFX_WHISTLE
  BRA .fa_g
.fa_wall:
  LDA #DAS_T                   ; against the wall: it moves as soon as there is room
  STA DAS
  BRA .fa_g
.fa_nolr:
  STZ DAS
.fa_g:
  LDX LVL                      ; gravity
  CPX #29
  BCC .fa_gl
  LDX #29
.fa_gl:
  LDA GRAV,X
  STA Q0
  LDA JOYC
  AND #%00000010
  BNE .fa_dn
  LDA #1                       ; down released: it may drop faster again
  STA DNOK
  STZ SOFT
  BRA .fa_t
.fa_dn:
  LDA DNOK
  BEQ .fa_t
  LDA Q0
  CMP #SOFT_T
  BCC .fa_t
  LDA #SOFT_T
  STA Q0
.fa_t:
  INC GCNT
  LDA GCNT
  CMP Q0
  BCS .fa_down
  RTS
.fa_down:
  STZ GCNT
  JSR SET_N
  INC NY
  JSR TRY_MOVE
  BCS .fa_ok
  JMP LOCK
.fa_ok:
  LDA JOYC                     ; a row dropped holding down: a point
  AND #%00000010
  BEQ .fa_r
  LDA DNOK
  BEQ .fa_r
  INC SOFT
.fa_r:
  RTS

; A = rotation (any, taken mod 4): the piece turns if it fits
TRY_ROT:
  AND #3
  PHA
  JSR SET_N
  PLA
  STA NR
  JSR TRY_MOVE
  BCC .tr_e
  LDA #W_ROT
  LDX #2
  JSR SFX_WHISTLE
.tr_e:
  RTS

SET_N:
  LDA PCX
  STA NX
  LDA PCY
  STA NY
  LDA PR
  STA NR
  RTS

; the piece to NX, NY, NR if it fits there: C = 1 moved (keeps X)
TRY_MOVE:
  PHX
  JSR FITS
  BCC .tm_e
  LDA #T_EMPTY
  JSR DRAW_PIECE
  LDA NX
  STA PCX
  LDA NY
  STA PCY
  LDA NR
  STA PR
  JSR SHOW_PIECE
  SEC
.tm_e:
  PLX
  RTS

; C = 1 if the piece PT fits at NX, NY with the rotation NR
FITS:
  LDA PT
  ASL A
  ASL A
  ADC NR
  ASL A
  ASL A
  TAY
  LDA #4
  STA Q2
.fi_c:
  LDA PC_DX,Y
  CLC
  ADC NX
  CMP #10
  BCS .fi_no
  STA Q1
  LDA PC_DY,Y
  CLC
  ADC NY
  CMP #22
  BCS .fi_no
  TAX
  LDA ROW10,X
  CLC
  ADC Q1
  TAX
  LDA WELL,X
  BNE .fi_no
  INY
  DEC Q2
  BNE .fi_c
  SEC
  RTS
.fi_no:
  CLC
  RTS

SHOW_PIECE:
  LDA PT
  CLC
  ADC #T_BRICK
  ; fall into DRAW_PIECE

; A = tile: the 4 cells of the piece on the screen (not the hidden rows 0-1)
DRAW_PIECE:
  STA Q3
  LDA PT
  ASL A
  ASL A
  ADC PR
  ASL A
  ASL A
  STA Q0
  LDA #4
  STA Q2
.dp_c:
  LDY Q0
  LDA PC_DY,Y
  CLC
  ADC PCY
  CMP #2
  BCC .dp_n
  TAX
  LDA PC_DX,Y
  CLC
  ADC PCX
  CLC
  ADC #WCOL
  TAY
  JSR NT_XY
  LDA Q3
  STA VDATA
.dp_n:
  INC Q0
  DEC Q2
  BNE .dp_c
  RTS

; the piece cannot go down: into the wall; the full rows flash
LOCK:
  LDA PT
  ASL A
  ASL A
  ADC PR
  ASL A
  ASL A
  TAY
  LDA PT
  INC A
  STA Q3
  LDA #4
  STA Q2
.lk_c:
  LDX PCY                      ; (the piece is where it fits: no checks)
  TXA
  CLC
  ADC PC_DY,Y
  TAX
  LDA ROW10,X
  CLC
  ADC PCX
  CLC
  ADC PC_DX,Y
  TAX
  LDA Q3
  STA WELL,X
  INY
  DEC Q2
  BNE .lk_c
  LDA #S_LOCK
  LDX #2
  JSR SFX_BOOM
  LDA SOFT                     ; the rows dropped holding down
  BEQ .lk_l
  JSR BIN2BCD
  STA PTS_L
  STZ PTS_M
  STZ PTS_H
  JSR ADD_SCORE
  STZ SOFT
.lk_l:
  STZ NLIN                     ; the full rows
  LDX #21
.lk_r:
  STZ FULLF,X
  LDA ROW10,X
  TAY
  LDA #10
  STA Q2
.lk_rc:
  LDA WELL,Y
  BEQ .lk_nf
  INY
  DEC Q2
  BNE .lk_rc
  INC FULLF,X
  INC NLIN
.lk_nf:
  DEX
  BPL .lk_r
  LDA NLIN
  BNE .lk_f
  LDA #2                       ; no row: the next piece
  STA GSTATE
  LDA #ARE_T
  STA GT
  RTS
.lk_f:
  LDA #1
  STA GSTATE
  LDA #FLASH_T
  STA GT
  LDA NLIN
  CMP #4
  BEQ .lk_bd
  LDA #W_LINE
  LDX #2
  JMP SFX_WHISTLE
.lk_bd:
  INC BDN                      ; 4 rows: a BRICK DROP
  LDA #BDT_T
  STA BDT
  LDA #16
  TSB HUDD
  LDA #W_BRICK
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  THE FULL ROWS: they flash, then go
; ===============================================================
FLASH:
  DEC GT
  BEQ .fl_go
  LDA GT
  AND #3
  BNE .fl_e
  LDX #2                       ; every 4 frames: white, then the bricks again
.fl_r:
  LDA FULLF,X
  BEQ .fl_n
  LDA GT
  AND #4
  BEQ .fl_b
  PHX
  LDY #WCOL
  JSR NT_XY
  LDX #10
  LDA #T_FLASH
.fl_w:
  STA VDATA
  NOP
  DEX
  BNE .fl_w
  PLX
  BRA .fl_n
.fl_b:
  PHX
  JSR DRAW_ROW
  PLX
.fl_n:
  INX
  CPX #22
  BNE .fl_r
.fl_e:
  RTS
.fl_go:
  ; the rows above come down
  LDX #21                      ; X = row read, Y = row written
  LDY #21
.fl_cp:
  LDA FULLF,X
  BNE .fl_skip
  STX Q0
  STY Q1
  CPY Q0                       ; the rows under the lowest full one stay where they are
  BEQ .fl_same
  LDA ROW10,X
  STA Q2
  LDA ROW10,Y
  TAY
  LDX Q2
  LDA #10
  STA Q3
.fl_cc:
  LDA WELL,X
  STA WELL,Y
  INX
  INY
  DEC Q3
  BNE .fl_cc
  LDX Q0
  LDY Q1
.fl_same:
  DEY
.fl_skip:
  DEX
  BPL .fl_cp
.fl_z:                         ; the rows on top: empty
  CPY #$FF
  BEQ .fl_d
  LDA ROW10,Y
  TAX
  LDA #10
  STA Q3
.fl_zc:
  STZ WELL,X
  INX
  DEC Q3
  BNE .fl_zc
  DEY
  BRA .fl_z
.fl_d:
  LDX #22                      ; the rows 2 down to the lowest full one again
.fl_lo:
  DEX
  LDA FULLF,X
  BEQ .fl_lo
  INX
  STX WLIM
  JSR DRAW_WELL_TO
  LDA #2                       ; the points in the next frame (ENTRY)
  STA GSTATE
  LDA #ARE_T
  STA GT
  RTS

; the lines, the points, the level after NLIN rows
LINE_SCORE:
  SED
  LDA LNL
  CLC
  ADC NLIN
  STA LNL
  LDA LNH
  ADC #0
  STA LNH
  CLD
  LDX NLIN
  LDA LINE_PL,X
  STA PTS_L
  LDA LINE_PM,X
  STA PTS_M
  STZ PTS_H
  LDX LVL                      ; times the level + 1
.fl_pt:
  JSR ADD_SCORE
  DEX
  CPX #$FF
  BNE .fl_pt
  LDA #2
  TSB HUDD
  JSR LINES_LV                 ; a level every 10 lines
  CMP LVL
  BCC .fl_nl
  BEQ .fl_nl
  STA LVL
  LDA #1
  STA LVUP
  LDA #W_LEVEL
  LDX #2
  JSR SFX_WHISTLE
.fl_nl:
  RTS

; A = lines / 10 (200 at most)
LINES_LV:
  LDA LNH
  CMP #$20
  BCC .ll_c
  LDA #200
  RTS
.ll_c:
  LSR A                        ; hundreds and thousands in binary...
  LSR A
  LSR A
  LSR A
  STA Q0
  ASL A
  ASL A
  ADC Q0
  ASL A
  STA Q0
  LDA LNH
  AND #$0F
  CLC
  ADC Q0
  STA Q0                       ; ...times 10, and the tens
  ASL A
  ASL A
  ADC Q0
  ASL A
  STA Q0
  LDA LNL
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC Q0
  RTS


; ===============================================================
;  THE NEXT PIECE
; ===============================================================
ENTRY:
  LDA NLIN                     ; rows gone: the points
  BEQ .en_p
  JSR LINE_SCORE
  STZ NLIN
  BRA .en_t
.en_p:
  LDA LVUP                     ; the colours of a new level
  BEQ .en_t
  STZ LVUP
  JSR SET_PALETTE
.en_t:
  DEC GT
  BNE .en_e
  JMP SPAWN
.en_e:
  RTS

; the next piece comes in on top, the one after in the box
SPAWN:
  LDA NXT
  STA PT
  JSR ROLL
  STA NXT
  STZ PR
  LDA #5
  STA PCX
  LDA #2
  STA PCY
  STZ GCNT
  STZ DNOK
  STZ SOFT
  INC PCS
  BNE .sn_c
  INC PCS+1
.sn_c:
  LDA PT                       ; the statistics (999 at most)
  ASL A
  TAX
  LDA STATS,X
  CMP #$99
  BNE .sn_i
  LDA STATS+1,X
  CMP #$09
  BEQ .sn_h
.sn_i:
  SED
  LDA STATS,X
  CLC
  ADC #1
  STA STATS,X
  LDA STATS+1,X
  ADC #0
  STA STATS+1,X
  CLD
.sn_h:
  LDA #4
  TSB HUDD
  JSR SET_N
  JSR FITS
  BCC .sn_over
  STZ GSTATE
  JMP SHOW_PIECE
.sn_over:                      ; no room: the wall is up to the top
  LDA #3
  STA GSTATE
  LDA #2
  STA GT
  LDA #21
  STA FILLR
  LDA #CMD_GAME
  STA SND_CMD
  RTS

; A = a random piece (0-6); the same as the last one is rolled once more
ROLL:
  JSR NEXT_RND
  JSR NEXT_RND
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #7
  BEQ .ro_2
  CMP LASTT
  BNE .ro_e
.ro_2:
  JSR NEXT_RND
  JSR NEXT_RND
  JSR NEXT_RND
.ro_m:
  CMP #7
  BCC .ro_e
  SBC #7
  BRA .ro_m
.ro_e:
  STA LASTT
  RTS


; ===============================================================
;  GAME OVER: the wall turns grey from the bottom
; ===============================================================
TOPFILL:
  DEC GT
  BNE .tf_r
  LDA #FILL_T
  STA GT
  LDA FILLR
  CMP #21
  BNE .tf_f
  LDA #S_FILL
  LDX #2
  JSR SFX_BOOM
  LDA #W_OVER
  JSR SFX_WHISTLE
.tf_f:
  LDX FILLR
  LDA ROW10,X
  TAY
  LDA #10
  STA Q3
  LDA #8
.tf_c:
  STA WELL,Y
  INY
  DEC Q3
  BNE .tf_c
  JSR DRAW_ROW
  DEC FILLR
  LDA FILLR
  CMP #2
  BCS .tf_r
  LDA #4
  STA GSTATE
.tf_r:
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from pastry panic)
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
  CMP #CMD_LOOP
  BNE .st_once
  JSR SND_LOOP
  BRA .st_run
.st_once:
  JSR SND_START
.st_run:
  LDA SND_MODE
  BEQ .st_sfx
  JSR MUS_TICK
  LDA SND_MODE                  ; the music of the game: the effects over it
  CMP #2
  BNE .st_flush
  JSR SFX_OVL
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
; starts the tune SONG: once (SND_START) or again and again with the
; effects of the game over it (SND_LOOP)
; ---------------------------------------------------------------
SND_START:
  JSR SND_MIX
  JSR SND_TRACKS
  LDA #$01
  STA SND_MODE
  STA SND_BUSY
  RTS

SND_LOOP:
  JSR SND_MIX
  JSR SND_TRACKS
  LDA #$02
  STA SND_MODE
  STZ SND_BUSY
  RTS

SND_MIX:
  JSR SND_CLEAR_SH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #$2A                      ; right: tone A, noise B (drums), tone C
  STA SH_R+7
  RTS

SND_TRACKS:                     ; the 4 tracks of SONG from their start
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
  LDA SND_MODE                  ; the music of the game starts again
  CMP #2
  BNE .mt_once
  JMP SND_TRACKS
.mt_once:
  JSR SND_GAME_MODE             ; silence, SND_BUSY = 0
.mt_end:
  RTS

; the effects alone: the volumes to 0, then the effects playing
SFX_TICK:
  LDA #$00
  LDX #2
.sf_z:
  STA SH_L+8,X
  STA SH_R+8,X
  DEX
  BPL .sf_z
  BRA SFX_RUN

; the effects over the music of the game: an effect takes its channels for as long as it plays
SFX_OVL:
  LDA #$38                      ; left: 3 tones (the noise only while an effect needs it)
  STA SH_L+7
SFX_RUN:
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
  LDA #$2A                      ; tone A, noise B, tone C
  STA SH_L+7,Y
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
S_BIG = S_FILL                                  ; (lib_sound: a big noise is not cut by a small one)
; frames for one row down at every level (29 and more: 1)
GRAV:       .byte 48,43,38,33,28,23,18,13,8,6,5,5,5,4,4,4,3,3,3,2,2,2,2,2,2,2,2,2,2,1
; points for 1-4 rows at once (BCD), times the level + 1
LINE_PL:    .byte $00,$40,$00,$00,$00
LINE_PM:    .byte $00,$00,$01,$03,$12
; the start of every row of the well (10 cells a row)
ROW10:      .byte 0,10,20,30,40,50,60,70,80,90,100,110,120,130,140,150,160,170,180,190,200,210
; the colours of the level: offsets of the palettes
BRC_LO:     .byte <(BRCOL+0),<(BRCOL+56),<(BRCOL+112),<(BRCOL+168),<(BRCOL+224)
            .byte <(BRCOL+280),<(BRCOL+336),<(BRCOL+392),<(BRCOL+448),<(BRCOL+504)
BRC_HI:     .byte >(BRCOL+0),>(BRCOL+56),>(BRCOL+112),>(BRCOL+168),>(BRCOL+224)
            .byte >(BRCOL+280),>(BRCOL+336),>(BRCOL+392),>(BRCOL+448),>(BRCOL+504)
; the menu: the columns of the 10 levels and of the 4 choices of the music
MLV_COL:    .byte 7,9,11,13,15,17,19,21,23,25
MUS_COL:    .byte 8,13,18,24

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 0,12,"HI",0
  .byte $FF
TXT_TOP2:
  .byte 0,22,"2UP",0,$FF
TXT_BUTTONS:
  .byte 6,6,T_BRICK,T_BRICK+1,T_BRICK+2,T_BRICK+3,T_BRICK+4,T_BRICK+5,T_BRICK+6,T_BRICK,T_BRICK+1,T_BRICK+2
  .byte T_BRICK+3,T_BRICK+4,T_BRICK+5,T_BRICK+6,T_BRICK,T_BRICK+1,T_BRICK+2,T_BRICK+3,T_BRICK+4,T_BRICK+5,0
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,1,"LAY THE BRICKS, CLOSE THE ROWS",0
  .byte 11,5,"LEFT/RIGHT   MOVE",0
  .byte 12,5,"DOWN         DROP FASTER",0
  .byte 13,5,"BUTTON 1/2   TURN",0
  .byte 15,5,"ROWS  1    2    3    4",0
  .byte 16,5,"     40  100  300 1200",0
  .byte 17,6,"TIMES THE LEVEL + 1",0
  .byte $FF
TXT_MENU:
  .byte 9,10,"START LEVEL",0
  .byte 11,7,"0 1 2 3 4 5 6 7 8 9",0
  .byte 14,13,"MUSIC",0
  .byte 16,8,"A    B    C    OFF",0
  .byte 19,5,"JOYSTICK = CHOOSE",0
  .byte 20,5,"BUTTON   = START",0
  .byte $FF
TXT_GAME:
  .byte 2,2,"STATS",0
  .byte 2,25,"NEXT",0
  .byte 10,24,"LINES",0
  .byte 13,24,"LEVEL",0
  .byte $FF
TXT_BRICK:
  .byte 20,25,"BRICK",0
  .byte 21,25,"DROP!",0
  .byte $FF
TXT_NOBRICK:
  .byte 20,25,"     ",0
  .byte 21,25,"     ",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_PLAYERH: .byte "PLAYER "

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 12, 8, 11, 0      ; volume at the attack of the note
FLOOR_TAB:     .byte 6, 4, 5, 0        ; lowest volume reached by the decay
DECMASK_TAB:   .byte 3, 7, 3, 0        ; the volume drops by 1 when (age AND mask) = 0
; drums: 1 kick, 2 snare, 3 hi-hat, 4 cymbal
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 14, 12, 7, 14
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
; BRICK DROP: generated by dev/gen_brick_drop.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; tiles
T_EMPTY = 96
T_BRICK = 97
T_GRAY = 104
T_FLASH = 105
T_WALL = 106
T_ICON = 107
PT_CUR = 0
BIGT = 200
BIGB = 220
SPR_LEN = 32
SPR_PAGES = 1
SPRITES:
  .byte $E0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$E0,$07,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; game tiles 96-120: patterns and colours
TILEP:
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE,$FE,$FE,$00,$EF,$EF,$EF,$00,$00,$00,$EE,$EE,$EE,$00,$00,$00
  .byte $00,$00,$EE,$EE,$EE,$00,$00,$00,$0E,$0E,$0E,$00,$0E,$0E,$0E,$00,$E0,$E0,$E0,$00,$E0,$E0,$E0,$00,$3B,$3B,$3B,$00,$03,$03,$03,$00
  .byte $B8,$B8,$B8,$00,$80,$80,$80,$00,$03,$03,$03,$00,$3B,$3B,$3B,$00,$B8,$B8,$B8,$00,$80,$80,$80,$00,$3B,$3B,$3B,$00,$03,$03,$03,$00
  .byte $80,$80,$80,$00,$B8,$B8,$B8,$00,$3B,$3B,$3B,$00,$00,$00,$00,$00,$B8,$B8,$B8,$00,$38,$38,$38,$00,$3B,$3B,$3B,$00,$38,$38,$38,$00
  .byte $B8,$B8,$B8,$00,$00,$00,$00,$00
TILEC:
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$F1,$71,$71,$71,$71,$71,$51,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11
  .byte $F1,$31,$31,$31,$31,$31,$21,$11,$91,$81,$81,$81,$81,$81,$61,$11,$71,$51,$51,$51,$51,$51,$41,$11,$B1,$A1,$A1,$A1,$A1,$A1,$61,$11
  .byte $F1,$E1,$E1,$E1,$E1,$E1,$41,$11,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$8E,$6E,$6E,$6E,$8E,$6E,$6E,$6E,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $71,$71,$71,$71,$71,$71,$71,$71,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
  .byte $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$31,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$51,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1

; the colours of the 7 bricks at every level (10 x 56 bytes)
BRCOL:
  .byte $F1,$71,$71,$71,$71,$71,$51,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11,$F1,$31,$31,$31
  .byte $31,$31,$21,$11,$91,$81,$81,$81,$81,$81,$61,$11,$71,$51,$51,$51,$51,$51,$41,$11,$B1,$A1,$A1,$A1,$A1,$A1,$61,$11
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$E1,$11,$F1,$91,$91,$91,$91,$91,$81,$11,$F1,$31,$31,$31,$31,$31,$21,$11,$F1,$71,$71,$71
  .byte $71,$71,$51,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$71,$51,$51,$51,$51,$51,$41,$11
  .byte $F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$31,$21,$21,$21,$21,$21,$C1,$11,$F1,$91,$91,$91,$91,$91,$81,$11,$71,$51,$51,$51
  .byte $51,$51,$41,$11,$B1,$A1,$A1,$A1,$A1,$A1,$61,$11,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11
  .byte $F1,$91,$91,$91,$91,$91,$81,$11,$F1,$71,$71,$71,$71,$71,$51,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$F1,$D1,$D1,$D1
  .byte $D1,$D1,$41,$11,$F1,$31,$31,$31,$31,$31,$21,$11,$91,$81,$81,$81,$81,$81,$61,$11,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$11
  .byte $F1,$31,$31,$31,$31,$31,$21,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11,$71,$51,$51,$51,$51,$51,$41,$11,$F1,$B1,$B1,$B1
  .byte $B1,$B1,$A1,$11,$F1,$91,$91,$91,$91,$91,$81,$11,$F1,$71,$71,$71,$71,$71,$51,$11,$31,$21,$21,$21,$21,$21,$C1,$11
  .byte $F1,$D1,$D1,$D1,$D1,$D1,$41,$11,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$11,$91,$81,$81,$81,$81,$81,$61,$11,$B1,$A1,$A1,$A1
  .byte $A1,$A1,$61,$11,$F1,$71,$71,$71,$71,$71,$51,$11,$F1,$31,$31,$31,$31,$31,$21,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11
  .byte $71,$51,$51,$51,$51,$51,$41,$11,$B1,$A1,$A1,$A1,$A1,$A1,$61,$11,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$11,$F1,$91,$91,$91
  .byte $91,$91,$81,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11,$F1,$31,$31,$31,$31,$31,$21,$11
  .byte $B1,$A1,$A1,$A1,$A1,$A1,$61,$11,$F1,$31,$31,$31,$31,$31,$21,$11,$F1,$71,$71,$71,$71,$71,$51,$11,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$E1,$11,$71,$51,$51,$51,$51,$51,$41,$11,$F1,$91,$91,$91,$91,$91,$81,$11,$91,$81,$81,$81,$81,$81,$61,$11
  .byte $91,$81,$81,$81,$81,$81,$61,$11,$71,$51,$51,$51,$51,$51,$41,$11,$F1,$B1,$B1,$B1,$B1,$B1,$A1,$11,$31,$21,$21,$21
  .byte $21,$21,$C1,$11,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$11,$B1,$A1,$A1,$A1,$A1,$A1,$61,$11,$F1,$71,$71,$71,$71,$71,$51,$11
  .byte $31,$21,$21,$21,$21,$21,$C1,$11,$91,$81,$81,$81,$81,$81,$61,$11,$B1,$A1,$A1,$A1,$A1,$A1,$61,$11,$F1,$71,$71,$71
  .byte $71,$71,$51,$11,$F1,$91,$91,$91,$91,$91,$81,$11,$F1,$31,$31,$31,$31,$31,$21,$11,$F1,$D1,$D1,$D1,$D1,$D1,$41,$11
; the colour of the small piece of the statistics at every level (10 x 7)
ICCOL:
  .byte $71,$B1,$D1,$31,$81,$51,$A1
  .byte $F1,$91,$31,$71,$D1,$B1,$51
  .byte $B1,$21,$91,$51,$A1,$F1,$D1
  .byte $91,$71,$B1,$D1,$31,$81,$F1
  .byte $31,$D1,$51,$B1,$91,$71,$21
  .byte $D1,$F1,$81,$A1,$71,$31,$B1
  .byte $51,$A1,$F1,$91,$B1,$D1,$31
  .byte $A1,$31,$71,$F1,$51,$91,$81
  .byte $81,$51,$B1,$21,$F1,$A1,$71
  .byte $21,$81,$A1,$71,$91,$31,$D1

; the pieces I O T S Z J L: 4 rotations x 4 cells (dx, dy) around the pivot (type * 16 + rot * 4 + cell)
PC_DX:
  .byte $FE,$FF,$00,$01,$00,$00,$00,$00,$FE,$FF,$00,$01,$00,$00,$00,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$01,$00,$00,$00,$00,$FF,$01,$00,$FF,$00,$00,$00,$00,$01
  .byte $00,$01,$FF,$00,$00,$00,$01,$01,$00,$01,$FF,$00,$00,$00,$01,$01
  .byte $FF,$00,$00,$01,$01,$00,$01,$00,$FF,$00,$00,$01,$01,$00,$01,$00
  .byte $FF,$00,$01,$01,$00,$00,$00,$FF,$01,$00,$FF,$FF,$00,$00,$00,$01
  .byte $FF,$00,$01,$FF,$00,$00,$00,$FF,$01,$00,$FF,$01,$00,$00,$00,$01
PC_DY:
  .byte $00,$00,$00,$00,$FE,$FF,$00,$01,$00,$00,$00,$00,$FE,$FF,$00,$01
  .byte $00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$01
  .byte $00,$00,$00,$01,$FF,$00,$01,$00,$00,$00,$00,$FF,$01,$00,$FF,$00
  .byte $00,$00,$01,$01,$FF,$00,$00,$01,$00,$00,$01,$01,$FF,$00,$00,$01
  .byte $00,$00,$01,$01,$FF,$00,$00,$01,$00,$00,$01,$01,$FF,$00,$00,$01
  .byte $00,$00,$00,$01,$FF,$00,$01,$01,$00,$00,$00,$FF,$01,$00,$FF,$FF
  .byte $00,$00,$00,$01,$FF,$00,$01,$FF,$00,$00,$00,$FF,$01,$00,$FF,$01

; big letters of the title
BIG_TOP:
  .byte $00,$FF,$FF,$E0,$E0,$E0,$E0,$FF,$00,$F0,$F0,$0E,$0E,$0E,$0E,$F0,$00,$FF,$FF,$E0,$E0,$E0,$E0,$FF,$00,$F0,$F0,$0E,$0E,$0E,$0E,$F0
  .byte $00,$1F,$1F,$03,$03,$03,$03,$03,$00,$F0,$F0,$80,$80,$80,$80,$80,$00,$1F,$1F,$E0,$E0,$E0,$E0,$E0,$00,$F0,$F0,$0E,$0E,$00,$00,$00
  .byte $00,$E0,$E0,$E0,$E0,$E3,$E3,$FC,$00,$0E,$0E,$70,$70,$80,$80,$00,$00,$FF,$FF,$E0,$E0,$E0,$E0,$E0,$00,$F0,$F0,$0E,$0E,$0E,$0E,$0E
  .byte $00,$1F,$1F,$E0,$E0,$E0,$E0,$E0,$00,$F0,$F0,$0E,$0E,$0E,$0E,$0E,$00,$FF,$FF,$E0,$E0,$E0,$E0,$FF,$00,$F0,$F0,$0E,$0E,$0E,$0E,$F0
BIG_BOT:
  .byte $FF,$E0,$E0,$E0,$E0,$FF,$FF,$00,$F0,$0E,$0E,$0E,$0E,$F0,$F0,$00,$FF,$E3,$E3,$E0,$E0,$E0,$E0,$00,$F0,$80,$80,$70,$70,$0E,$0E,$00
  .byte $03,$03,$03,$03,$03,$1F,$1F,$00,$80,$80,$80,$80,$80,$F0,$F0,$00,$E0,$E0,$E0,$E0,$E0,$1F,$1F,$00,$00,$00,$00,$0E,$0E,$F0,$F0,$00
  .byte $FC,$E3,$E3,$E0,$E0,$E0,$E0,$00,$00,$80,$80,$70,$70,$0E,$0E,$00,$E0,$E0,$E0,$E0,$E0,$FF,$FF,$00,$0E,$0E,$0E,$0E,$0E,$F0,$F0,$00
  .byte $E0,$E0,$E0,$E0,$E0,$1F,$1F,$00,$0E,$0E,$0E,$0E,$0E,$F0,$F0,$00,$FF,$E0,$E0,$E0,$E0,$E0,$E0,$00,$F0,$00,$00,$00,$00,$00,$00,$00
BIG_TOPC:
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
BIG_BOTC:
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
  .byte $81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91,$81,$91
TXT_BIG:
  .byte 3,6,200,201,202,203,204,205,206,207,208,209,32,32,210,211,202,203,212,213,214,215,0
  .byte 4,6,220,221,222,223,224,225,226,227,228,229,32,32,230,231,222,223,232,233,234,235,0
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
  .byte $20,$06,$25,$06,$29,$06,$2C,$0C,$29,$06,$2C,$06,$31,$18,$00,$06,$2E,$06,$2C,$06,$2A,$06,$29,$06,$27,$06,$25,$06,$27,$06,$29,$0C
  .byte $20,$0C,$25,$24,$FF
SG0_1:
  .byte $1D,$18,$00,$06,$1D,$0C,$20,$18,$00,$06,$1E,$18,$00,$06,$22,$0C,$20,$18,$1D,$24,$FF
SG0_2:
  .byte $0D,$0C,$08,$0C,$0D,$0C,$11,$0C,$06,$0C,$0A,$0C,$08,$0C,$0C,$0C,$0D,$24,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$06,$03,$06,$04,$24,$FF
SG1_0:
  .byte $27,$09,$2B,$09,$2E,$09,$2B,$09,$2C,$09,$30,$09,$2E,$12,$2B,$09,$2E,$09,$33,$09,$2E,$09,$30,$09,$2E,$09,$2C,$09,$2B,$09,$29,$09
  .byte $2C,$09,$30,$09,$2C,$09,$2E,$09,$32,$09,$35,$12,$33,$09,$32,$09,$30,$09,$2E,$09,$2C,$09,$29,$09,$2E,$12,$27,$09,$2B,$09,$2E,$09
  .byte $2B,$09,$2C,$09,$30,$09,$2E,$12,$2B,$09,$2E,$09,$33,$09,$2E,$09,$30,$09,$2E,$09,$2C,$09,$2B,$09,$2C,$09,$30,$09,$35,$09,$33,$09
  .byte $32,$09,$30,$09,$2E,$09,$2C,$09,$2B,$09,$29,$09,$2C,$09,$26,$09,$27,$12,$00,$12,$FF
SG1_1:
  .byte $00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$24,$09,$00,$09,$24,$09,$00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$24,$09,$00,$09,$24,$09
  .byte $00,$09,$20,$09,$00,$09,$20,$09,$00,$09,$26,$09,$00,$09,$26,$09,$00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$26,$09,$00,$09,$26,$09
  .byte $00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$24,$09,$00,$09,$24,$09,$00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$24,$09,$00,$09,$24,$09
  .byte $00,$09,$20,$09,$00,$09,$20,$09,$00,$09,$26,$09,$00,$09,$26,$09,$00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$1F,$09,$00,$09,$1F,$09
  .byte $FF
SG1_2:
  .byte $0F,$09,$00,$09,$0A,$09,$00,$09,$08,$09,$00,$09,$0F,$09,$00,$09,$0F,$09,$00,$09,$0A,$09,$00,$09,$08,$09,$00,$09,$0F,$09,$00,$09
  .byte $11,$09,$00,$09,$0C,$09,$00,$09,$0A,$09,$00,$09,$11,$09,$00,$09,$0F,$09,$00,$09,$0A,$09,$00,$09,$0A,$09,$00,$09,$11,$09,$00,$09
  .byte $0F,$09,$00,$09,$0A,$09,$00,$09,$08,$09,$00,$09,$0F,$09,$00,$09,$0F,$09,$00,$09,$0A,$09,$00,$09,$08,$09,$00,$09,$0F,$09,$00,$09
  .byte $11,$09,$00,$09,$0C,$09,$00,$09,$0A,$09,$00,$09,$11,$09,$00,$09,$0F,$09,$00,$09,$0A,$09,$00,$09,$0F,$09,$00,$09,$0A,$09,$00,$09
  .byte $FF
SG1_3:
  .byte $01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09
  .byte $01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09
  .byte $01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09
  .byte $01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09,$01,$09,$03,$09,$02,$09,$03,$09
  .byte $FF
SG2_0:
  .byte $29,$0C,$00,$06,$29,$06,$2C,$0C,$2E,$0C,$30,$12,$2E,$06,$2C,$0C,$29,$0C,$27,$0C,$00,$06,$27,$06,$2B,$0C,$2C,$0C,$2E,$18,$00,$18
  .byte $29,$0C,$00,$06,$29,$06,$2C,$0C,$2E,$0C,$30,$0C,$33,$0C,$30,$0C,$2E,$0C,$2C,$0C,$2B,$0C,$29,$0C,$27,$0C,$29,$30,$30,$06,$30,$06
  .byte $00,$06,$30,$06,$2E,$0C,$2C,$0C,$2E,$06,$2E,$06,$00,$06,$2E,$06,$2C,$0C,$2B,$0C,$2C,$06,$2C,$06,$00,$06,$2C,$06,$2B,$0C,$29,$0C
  .byte $2B,$18,$27,$18,$29,$0C,$2C,$0C,$30,$0C,$35,$0C,$33,$0C,$30,$0C,$2E,$0C,$2C,$0C,$2B,$0C,$27,$0C,$2B,$0C,$2E,$0C,$2C,$18,$29,$18
  .byte $FF
SG2_1:
  .byte $00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C
  .byte $00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C
  .byte $00,$0C,$1D,$0C,$00,$0C,$1D,$0C,$00,$0C,$1D,$0C,$00,$0C,$1D,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C
  .byte $00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$20,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C,$00,$0C,$1F,$0C
  .byte $FF
SG2_2:
  .byte $11,$0C,$11,$06,$00,$06,$0C,$0C,$11,$0C,$11,$0C,$00,$0C,$0C,$0C,$11,$0C,$0F,$0C,$0F,$06,$00,$06,$0A,$0C,$0F,$0C,$0F,$0C,$00,$0C
  .byte $0A,$0C,$0F,$0C,$11,$0C,$11,$06,$00,$06,$0C,$0C,$11,$0C,$11,$0C,$00,$0C,$0C,$0C,$11,$0C,$11,$0C,$11,$06,$00,$06,$0C,$0C,$11,$0C
  .byte $11,$0C,$00,$0C,$0C,$0C,$11,$0C,$0D,$0C,$0D,$06,$00,$06,$08,$0C,$0D,$0C,$0D,$0C,$00,$0C,$08,$0C,$0D,$0C,$0F,$0C,$0F,$06,$00,$06
  .byte $0A,$0C,$0F,$0C,$0F,$0C,$00,$0C,$0A,$0C,$0F,$0C,$11,$0C,$11,$06,$00,$06,$0C,$0C,$11,$0C,$11,$0C,$00,$0C,$0C,$0C,$11,$0C,$0F,$0C
  .byte $0F,$06,$00,$06,$0F,$0C,$0A,$0C,$11,$0C,$00,$0C,$0C,$0C,$11,$0C,$FF
SG2_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$06,$01,$06,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$06,$01,$06,$01,$0C,$03,$0C
  .byte $02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$06,$01,$06,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$06,$01,$06
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$06,$01,$06,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C
  .byte $03,$06,$01,$06,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$06,$01,$06,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C
  .byte $03,$0C,$02,$0C,$03,$06,$01,$06,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$FF
SG3_0:
  .byte $22,$30,$25,$18,$2A,$30,$29,$18,$27,$18,$25,$18,$23,$18,$22,$48,$20,$30,$22,$18,$23,$30,$27,$18,$25,$18,$23,$18,$22,$18,$20,$48
  .byte $22,$30,$25,$18,$2A,$30,$2C,$18,$2E,$18,$2C,$18,$2A,$18,$27,$48,$23,$30,$27,$18,$25,$18,$22,$18,$1E,$18,$20,$30,$1D,$18,$1E,$48
  .byte $FF
SG3_1:
  .byte $00,$18,$16,$18,$19,$18,$00,$18,$14,$18,$19,$18,$00,$18,$1B,$18,$1E,$18,$00,$18,$16,$18,$19,$18,$00,$18,$14,$18,$19,$18,$00,$18
  .byte $1B,$18,$1E,$18,$00,$18,$16,$18,$19,$18,$00,$18,$14,$18,$19,$18,$00,$18,$16,$18,$19,$18,$00,$18,$16,$18,$1B,$18,$00,$18,$16,$18
  .byte $19,$18,$00,$18,$1B,$18,$1E,$18,$00,$18,$1B,$18,$1E,$18,$00,$18,$16,$18,$19,$18,$00,$18,$14,$18,$19,$18,$00,$18,$16,$18,$19,$18
  .byte $FF
SG3_2:
  .byte $06,$18,$00,$30,$0D,$18,$00,$30,$0B,$18,$00,$30,$06,$18,$00,$30,$0D,$18,$00,$30,$0B,$18,$00,$30,$06,$18,$00,$30,$0D,$18,$00,$30
  .byte $06,$18,$00,$30,$0F,$18,$00,$30,$06,$18,$00,$30,$0B,$18,$00,$30,$0B,$18,$00,$30,$06,$18,$00,$30,$0D,$18,$00,$30,$06,$18,$00,$30
  .byte $FF
SG3_3:
  .byte $01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18
  .byte $03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18
  .byte $03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18,$01,$18,$03,$18,$03,$18
  .byte $FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$2D,$3C,$1B,$24,$18,$BD,$87,$69,$56,$48,$3F,$37,$31,$2D,$29,$26,$23,$20,$1E,$1C,$1B,$19,$18,$50,$50,$50,$50,$3C,$3C,$3C,$3C
  .byte $2F,$2F,$2F,$2F,$28,$28,$28,$28,$00,$00,$2F,$2F,$2F,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$78,$78,$78,$00,$5F,$5F,$5F,$00,$50,$50,$50,$00,$3C,$3C,$3C,$00,$2F,$2F,$2F,$00,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28
  .byte $9F,$9F,$9F,$9F,$9F,$00,$A9,$A9,$A9,$A9,$A9,$00,$B3,$B3,$B3,$B3,$B3,$00,$BD,$BD,$BD,$BD,$BD,$00,$C9,$C9,$C9,$C9,$C9,$00,$EF,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$24,$24,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35
  .byte $35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$07,$04,$09,$08,$05,$0D,$0D,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0E,$0D,$0C,$0B,$0E,$0D,$0C,$0B
  .byte $0E,$0D,$0C,$0B,$0E,$0D,$0C,$0B,$00,$00,$0D,$0C,$0A,$0D,$0C,$0A,$0E,$0D,$0D,$0C,$0B,$0B,$0A,$09,$09,$08,$08,$07,$06,$06,$05,$04
  .byte $04,$03,$0C,$0B,$09,$00,$0C,$0B,$09,$00,$0C,$0B,$09,$00,$0C,$0B,$09,$00,$0C,$0B,$09,$00,$0D,$0C,$0B,$0A,$09,$07,$06,$05,$04,$03
  .byte $0C,$0B,$0A,$08,$07,$00,$0C,$0B,$0A,$08,$07,$00,$0C,$0B,$0A,$08,$07,$00,$0C,$0B,$0A,$08,$07,$00,$0C,$0B,$0A,$08,$07,$00,$0C,$0B
  .byte $0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$09,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C
  .byte $0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$03,$06,$18,$42,$60,$92,$94,$97
WH_LEN:
  .byte $00,$02,$03,$12,$2A,$1E,$32,$02,$03,$13
W_MOVE = 1
W_ROT = 2
W_LINE = 3
W_BRICK = 4
W_LEVEL = 5
W_OVER = 6
W_MENU = 7
W_KEY = 8
W_SIGN = 9

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0B,$09,$07,$05,$03,$01,$00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08
  .byte $07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04
EX_NP:
  .byte $00,$18,$1A,$1C,$1E,$20,$22,$24,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16,$16,$16,$16,$16,$16
EX_VC:
  .byte $00,$0D,$0B,$09,$07,$05,$03,$01,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06
  .byte $05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02,$02
EX_TL:
  .byte $00,$B6,$E8,$21,$64,$B3,$12,$85,$12,$23,$36,$48,$5C,$70,$85,$9B,$B2,$C9,$E2,$FC,$16,$32,$4F,$6D,$8C,$AD,$D0,$F4,$1B,$43,$6D,$99
  .byte $C8,$FA,$2E,$66,$A1,$E0,$23,$6B,$B8,$0B,$64,$C4,$2C,$9D,$19,$A0
EX_TH:
  .byte $00,$02,$02,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05,$05,$06,$06,$06,$06
  .byte $06,$06,$07,$07,$07,$07,$08,$08,$08,$09,$09,$09,$0A,$0A,$0B,$0B
EX_START:
  .byte $00,$01,$08
EX_LEN:
  .byte $00,$07,$28
S_LOCK = 1
S_FILL = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <128,>128, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <128,>128, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$66, <128,>128, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$66, <128,>128, <BIG_BOTC,>BIG_BOTC
  .byte 1, $00,$43, <200,>200, <TILEP,>TILEP
  .byte 1, $00,$63, <200,>200, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <128,>128, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$4E, <128,>128, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$6E, <128,>128, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$6E, <128,>128, <BIG_BOTC,>BIG_BOTC
  .byte 1, $00,$4B, <200,>200, <TILEP,>TILEP
  .byte 1, $00,$6B, <200,>200, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <128,>128, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$56, <128,>128, <BIG_BOT,>BIG_BOT
  .byte 1, $40,$76, <128,>128, <BIG_TOPC,>BIG_TOPC
  .byte 1, $E0,$76, <128,>128, <BIG_BOTC,>BIG_BOTC
  .byte 1, $00,$53, <200,>200, <TILEP,>TILEP
  .byte 1, $00,$73, <200,>200, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
