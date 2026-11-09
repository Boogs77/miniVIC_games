;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   MOLE HOLE  -  an original digging game                     ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Mole the mole digs under the vegetable garden: soil,     ;
;     clay, gravel and rock; every new piece of tunnel 10      ;
;   - grubs follow the tunnels and now and then creep through  ;
;     the earth (only their eyes show); the mole cricket digs  ;
;     new tunnels of its own                                   ;
;   - BUTTON = the ice ray, in the tunnels only: every hit     ;
;     freezes a little more, the third time the bug becomes a  ;
;     block of ice and breaks (200 to 500 by the depth, the    ;
;     cricket twice); left alone the ice melts                 ;
;   - potatoes and stones fall when the earth below is gone    ;
;     and squash whoever is under them; after two of them a    ;
;     vegetable shows in the middle for a few seconds          ;
;   - the last bug left runs to the surface and away           ;
;   - 8 gardens, then again, faster; 3 lives, one more at      ;
;     10000; 1 or 2 players taking turns, each with his garden ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 41 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at the start and at the end of a     ;
;     level; steps, the ray, ice, thuds                        ;
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
XTRA        = $41      ;      1 = the extra life was given
ALIVE       = $42      ;      the bugs still there (bits 0-6)
RKGONE      = $43      ;      the rocks fallen (bits 0-3)
DROPS       = $44      ;      rocks fallen in this garden
VEGD        = $45      ;      1 = the vegetable was shown
FRESH       = $46      ;      1 = a new garden (dig it again)
PBLOCK      = 7
GSTATE      = $50      ; 0 playing, 1 life lost, 3 the garden is clear
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives and level
FIRSTT      = $53      ; 1 = first turn of the game
MX          = $54      ; Mole: left x, top y (8 + 16 x cell row), direction (0 right, 1 down, 2 left, 3 up)
MY          = $55
MDIR        = $56
MSLOW       = $57      ; digging: a step missed every 4 frames
MMOVE       = $58      ; 1 = Mole moved in this frame
MFRM        = $59      ; steps (the 2 frames of Mole)
RAYL        = $5A      ; the ice ray: length (0-32), bug it touches ($FF = none), frames on it
RAYE        = $5B
RAYT        = $5C
DIGN        = $5D      ; tiles dug in this frame
MNEXT       = $5E      ; the direction asked ($FF = none)
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
VEGT        = $72      ; the vegetable: frames / 4 left (0 = none)
KILLN       = $73      ; bugs frozen to pieces (tests)
LOSTN       = $74      ; lives lost (tests)
DEATHS      = $75      ; what took the last life (tests): 1 a bug, 2 a rock
NLEFT       = $76      ; bugs left
LAYOUT      = $77      ; garden of the level (0-7)
LEVI        = $78      ; level for the tables (0-9)
TICKS       = $79      ; frames (the slow timers every 4)
CB          = $7A      ; the bug being moved
TGX         = $7B      ; its target (pixels)
TGY         = $7C
BEST        = $7D      ; its best distance and direction
BESTD       = $7E
ESCOUT      = $7F      ; bugs that ran away (tests)
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
TROW        = $88      ; tile being drawn: row (1-22), column
TCOL        = $89
DX0         = $8A      ; a box of tiles to dig: first / last column, first / last row
DX1         = $8B
DY0         = $8C
DY1         = $8D
DIGP        = $8E      ; 1 = points for the digging (Mole), 0 = a cricket
CRUSHN      = $8F      ; bugs squashed by the rock falling

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

; ---------------- the bugs (7 at most) ----------------
NE         = 7
E_X        = $0200       ; left x, top y (pixels)
E_Y        = $0207
E_D        = $020E       ; direction
E_M        = $0215       ; mode (M_*)
E_F        = $021C       ; frozen 0-3
E_FT       = $0223       ; frames since the last hit / of the ice block
E_ACC      = $022A       ; fraction of the speed
E_GT       = $0231       ; frames / 4 before going into the earth (or out of it)
E_T        = $0238       ; 0 grub, 1 cricket
E_HX       = $023F       ; its den (start)
E_HY       = $0246
M_OFF      = 0           ; gone
M_RUN      = 1           ; in the tunnels
M_EARTH    = 2           ; through the earth (a grub: the eyes; the cricket digs)
M_ICE      = 3           ; a block of ice, then pieces
M_ESC      = 4           ; the last one runs away
; the rocks (4)
R_X        = $0250       ; left x, top y
R_Y        = $0254
R_S        = $0258       ; 0 gone, 1 still, 2 shaking, 3 falling, 4 broken
R_T        = $025C       ; timer
R_N        = $0260       ; bugs squashed

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
PDIG       = $0740       ; 2 x 80: the tunnels of every player (rows 3-22, a bit a tile)
DIG        = $0800       ; 22 rows x 32 (tile rows 1-22): 0 earth, 1 dug, 2 rock

; ---------------- parameters ----------------
BTN_MASK    = %00110000
MX0         = 112        ; where Mole starts (the top of the shaft)
MY0         = 8

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 41         ; fixed zone of the game in the save area
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
  STZ KILLN
  STZ ESCOUT
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ LEVEL
  STZ XTRA
  JSR NEW_GARDEN_P
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his garden as he left it
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

LEVEL_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the garden is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_LEVEL                ; the garden: new, or the tunnels of the player
  JSR DRAW_FIELD
  JSR DRAW_HUD
  JSR START_POS                ; Mole at the top, the bugs in their dens
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
  JSR MOLE
  JSR RAY
  JSR BUGS
  JSR ROCKS
  JSR VEGGIE
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
;  THE GARDEN IS CLEAR: the tune, the next level
; ===============================================================
LEVEL_CLEAR:
  JSR HIDE_SPRITES
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
  JSR NEW_GARDEN_P
  JSR SAVE_PLAYER
  JMP LEVEL_START

; a new garden for the player playing: all the bugs of the level, the rocks, no vegetable yet
NEW_GARDEN_P:
  LDA #1
  STA FRESH
  STZ RKGONE
  STZ DROPS
  STZ VEGD
  LDX LEVEL
  CPX #10
  BCC .ngp_l
  LDX #9
.ngp_l:
  LDA NBUGS,X                  ; the bugs of the level: bits 0 .. n-1
  TAX
  LDA LOWBITS,X
  STA ALIVE
  RTS

LOSE_LIFE:
  INC LOSTN
  LDX CURP
  DEC LIVES,X
  JSR ROCKS_SETTLE             ; a rock on its way is gone
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
  JSR VDP_INT_OFF              ; the same player: Mole at the top, the bugs home again
  JSR START_POS
  LDX CURP
  JSR DRAW_STATUS
  JSR VDP_INT_ON
  STZ GSTATE
  JMP GAME_LOOP

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
REC_NAME:  .byte "MOLE HOLE       "
REC_HEAD:  .byte "BEST DIGGERS",0
REC_XLBL:  .byte "LEVEL ",0


; ===============================================================
;  HUD: row 0 (scores), row 23 (lives, level)
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

; row 23: the spare lives (cols 0-5), LEVEL nn (cols 23-30), the player (col 31)
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
  CPY #6
  BNE .ds_i
  LDX #23
  LDY #23
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
  BNE .ds_r
  LDX #23
  LDY #31
  JSR NT_XY
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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives and level
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
SAVE_PLAYER:                   ; player CURP: his block and his tunnels
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
  JMP PACK_DIG

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
;  THE GARDEN: the tunnels, the rocks
; ===============================================================
SET_LEVEL:
  LDA LEVEL
  AND #7
  STA LAYOUT
  LDX LEVEL
  CPX #10
  BCC .sl_x
  LDX #9
.sl_x:
  STX LEVI
  LDA FRESH
  BEQ .sl_old
  STZ FRESH
  JSR BUILD_DIG
  BRA .sl_r
.sl_old:
  JSR UNPACK_DIG
.sl_r:
  ; the rocks still in their place (tiles = 2)
  LDA LAYOUT
  ASL A
  ASL A
  STA T4
  LDX #0
.sl_k:
  STX T5
  LDY T4
  LDA RK_C0,Y
  ASL A
  ASL A
  ASL A
  ASL A
  STA R_X,X
  LDA RK_R0,Y
  STA T0
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #8
  STA R_Y,X
  STZ R_S,X
  LDA BITS,X
  AND RKGONE
  BNE .sl_g
  LDA #1
  STA R_S,X
  LDA RK_C0,Y                  ; its 4 tiles
  ASL A
  STA TCOL
  LDA T0
  ASL A
  INC A
  STA TROW
  LDA #2
  JSR SET_CELL
.sl_g:
  INC T4
  LDX T5
  INX
  CPX #NROCK
  BNE .sl_k
  STZ VEGT
  RTS

; a new garden: earth everywhere, the surface open, the shaft and the dens of the bugs dug
BUILD_DIG:
  LDX #0                       ; rows 1-2 open, the rest earth (704 bytes)
.bd_c:
  LDA #0
  CPX #64
  BCS .bd_z
  LDA #1
.bd_z:
  STA DIG,X
  STZ DIG+256,X
  INX
  BNE .bd_c
.bd_c2:
  STZ DIG+512,X
  INX
  CPX #192
  BNE .bd_c2
  LDA #14                      ; the shaft: column 7, cell rows 1-5
  STA TCOL
  LDA #3
  STA TROW
.bd_s:
  LDA #1
  JSR SET_CELL
  INC TROW
  INC TROW
  LDA TROW
  CMP #13
  BCC .bd_s
  LDA LAYOUT                   ; the dens of the bugs of this garden
  STA T4
  ASL A
  ASL A
  ASL A
  SEC
  SBC T4
  STA T4                       ; layout * 7
  LDX #0
.bd_d:
  STX T5
  LDA BITS,X
  AND ALIVE
  BEQ .bd_n
  LDY T4
  LDA DEN_C,Y
  ASL A
  STA TCOL
  LDA DEN_R,Y
  ASL A
  INC A
  STA TROW
  LDA #1                       ; the middle cell, then the two at its sides
  JSR SET_CELL
  LDY T4
  LDA DEN_H,Y
  BEQ .bd_v
  DEC TCOL
  DEC TCOL
  LDA #1
  JSR SET_CELL
  INC TCOL
  INC TCOL
  INC TCOL
  INC TCOL
  LDA #1
  JSR SET_CELL
  BRA .bd_n
.bd_v:
  DEC TROW
  DEC TROW
  LDA #1
  JSR SET_CELL
  INC TROW
  INC TROW
  INC TROW
  INC TROW
  LDA #1
  JSR SET_CELL
.bd_n:
  INC T4
  LDX T5
  INX
  CPX #NE
  BNE .bd_d
  RTS

; A = value, TROW / TCOL = the top left tile of a cell: its 4 tiles (keeps TROW, TCOL)
SET_CELL:
  STA T0
  LDX TROW
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  LDY TCOL
  LDA T0
  STA (PTR),Y
  INY
  STA (PTR),Y
  TYA
  CLC
  ADC #31
  TAY
  LDA T0
  STA (PTR),Y
  INY
  STA (PTR),Y
  RTS

; the tunnels of the player playing into PDIG (rows 3-22, a bit a tile: 1 = dug)
PACK_DIG:
  LDA #<(DIG+64)
  STA PTR
  LDA #>(DIG+64)
  STA PTR+1
  LDX CURP
  LDA PD_LO,X
  STA PTR2
  LDA PD_HI,X
  STA PTR2+1
  LDY #0
.pk_b:
  LDX #8
.pk_t:
  LDA (PTR)
  CMP #1
  BEQ .pk_1
  CLC
  BRA .pk_r
.pk_1:
  SEC
.pk_r:
  ROL T0
  INC PTR
  BNE .pk_i
  INC PTR+1
.pk_i:
  DEX
  BNE .pk_t
  LDA T0
  STA (PTR2),Y
  INY
  CPY #80
  BNE .pk_b
  RTS

; and back: the surface open, the tunnels from the bits
UNPACK_DIG:
  LDX #63
  LDA #1
.uk_s:
  STA DIG,X
  DEX
  BPL .uk_s
  LDA #<(DIG+64)
  STA PTR
  LDA #>(DIG+64)
  STA PTR+1
  LDX CURP
  LDA PD_LO,X
  STA PTR2
  LDA PD_HI,X
  STA PTR2+1
  LDY #0
.uk_b:
  LDA (PTR2),Y
  STA T0
  LDX #8
.uk_t:
  LDA #0
  ASL T0
  ROL A
  STA (PTR)
  INC PTR
  BNE .uk_i
  INC PTR+1
.uk_i:
  DEX
  BNE .uk_t
  INY
  CPY #80
  BNE .uk_b
  RTS

; the whole screen of the garden (display off)
DRAW_FIELD:
  JSR CLEAR_NT
  LDX #1
  LDY #0
  JSR NT_XY
  LDX #0
.df_s:
  LDA SURF,X
  STA VDATA
  INX
  CPX #64
  BNE .df_s
  LDA #3
.df_r:
  PHA
  TAX
  JSR DRAW_ROW
  PLA
  INC A
  CMP #23
  BNE .df_r
  RTS

; X = tile row (3-22): the whole row
DRAW_ROW:
  STX TROW
  LDY #0
  JSR NT_XY
  STZ TCOL
.dr_c:
  JSR TILE_CODE
  STA VDATA
  INC TCOL
  LDA TCOL
  CMP #32
  BNE .dr_c
  RTS

; TROW / TCOL: the tile to show there (keeps TROW, TCOL)
TILE_CODE:
  LDX TROW
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  LDY TCOL
  LDA (PTR),Y
  BEQ .tc_e
  CMP #2
  BEQ .tc_rk
  STZ T0                       ; a tunnel: which sides are open
  LDA DR_LO-1,X                ; up (row 2 is the open surface)
  STA PTR2
  LDA DR_HI-1,X
  STA PTR2+1
  LDA (PTR2),Y
  CMP #1
  BNE .tc_d
  INC T0
.tc_d:
  CPX #22                      ; down
  BEQ .tc_l
  TYA
  CLC
  ADC #32
  TAY
  LDA (PTR),Y
  LDY TCOL
  CMP #1
  BNE .tc_l
  LDA #4
  TSB T0
.tc_l:
  CPY #0                       ; left
  BEQ .tc_rt
  DEY
  LDA (PTR),Y
  INY
  CMP #1
  BNE .tc_rt
  LDA #8
  TSB T0
.tc_rt:
  CPY #31                      ; right
  BEQ .tc_t
  INY
  LDA (PTR),Y
  CMP #1
  BNE .tc_t
  LDA #2
  TSB T0
.tc_t:
  LDA LBASE,X
  CLC
  ADC T0
  ADC #T_TUN
  RTS
.tc_e:
  TXA                          ; the earth: two kinds of specks
  CLC
  ADC TCOL
  AND #1
  CLC
  ADC LBASE,X
  ADC #T_EARTH
  RTS
.tc_rk:
  LDA TCOL                     ; a rock: its quarter (the cell starts on an odd row)
  AND #1
  STA T0
  TXA
  AND #1
  BNE .tc_rq
  LDA #2
  TSB T0
.tc_rq:
  LDA LROCK,X
  CLC
  ADC T0
  ADC #T_ROCK
  RTS

; TROW / TCOL: draw the tile and the 4 around it (a tunnel border changes)
REDRAW5:
  LDA TROW
  PHA
  LDA TCOL
  PHA
  JSR .r5_one
  DEC TROW
  JSR .r5_one
  INC TROW
  INC TROW
  JSR .r5_one
  DEC TROW
  DEC TCOL
  JSR .r5_one
  INC TCOL
  INC TCOL
  JSR .r5_one
  PLA
  STA TCOL
  PLA
  STA TROW
  RTS
.r5_one:
  LDA TROW
  CMP #3
  BCC .r5_r
  CMP #23
  BCS .r5_r
  LDA TCOL
  CMP #32
  BCS .r5_r
  LDX TROW
  LDY TCOL
  JSR NT_XY
  JSR TILE_CODE
  STA VDATA
.r5_r:
  RTS

; A = x: DX0 / DX1 the columns of a 16-pixel box
BOX_X:
  PHA
  LSR A
  LSR A
  LSR A
  STA DX0
  PLA
  CLC
  ADC #15
  LSR A
  LSR A
  LSR A
  STA DX1
  RTS

; A = y: DY0 / DY1 the rows of a 16-pixel box
BOX_Y:
  PHA
  LSR A
  LSR A
  LSR A
  STA DY0
  PLA
  CLC
  ADC #15
  LSR A
  LSR A
  LSR A
  STA DY1
  RTS

; dig the earth in the box DX0-DX1 / DY0-DY1 (rows 3-22): DIGN tiles, 10 points each if DIGP
DIG_BOX:
  LDA DY0
  STA TROW
.dg_r:
  LDA TROW
  CMP #3
  BCC .dg_n
  CMP #23
  BCS .dg_e
  LDA DX0
  STA TCOL
.dg_c:
  LDX TROW
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  LDY TCOL
  LDA (PTR),Y
  BNE .dg_k
  LDA #1
  STA (PTR),Y
  JSR REDRAW5
  INC DIGN
  LDA DIGP
  BEQ .dg_k
  LDA #$10
  LDY #0
  JSR ADD_PTS
.dg_k:
  LDA TCOL
  CMP DX1
  INC TCOL
  BCC .dg_c
.dg_n:
  LDA TROW
  CMP DY1
  INC TROW
  BCC .dg_r
.dg_e:
  RTS

; LEVEL nn (and PLAYER n) on row 11
MSG_LEVEL:
  LDX #11
  LDY #11
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
  LDA NPL
  CMP #2
  BNE .ml_r
  LDX #13
  LDY #11
  JSR NT_XY
  LDX #0
.ml_n:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .ml_n
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ml_r:
  RTS

MSG_CLEAR:
  LDX #11
  JSR DRAW_ROW
  LDX #13
  JMP DRAW_ROW

; Mole at the top of the shaft, the bugs in their dens, no ray
START_POS:
  LDA #MX0
  STA MX
  LDA #MY0
  STA MY
  LDA #1
  STA MDIR
  STZ MSLOW
  STZ MFRM
  STZ RAYL
  LDA #$FF
  STA RAYE
  STZ NLEFT
  LDA LAYOUT
  STA T4
  ASL A
  ASL A
  ASL A
  SEC
  SBC T4
  STA T4                       ; layout * 7
  LDX #0
.sp_e:
  STZ E_M,X
  LDA BITS,X
  AND ALIVE
  BEQ .sp_n
  INC NLEFT
  LDY T4
  LDA DEN_C,Y
  ASL A
  ASL A
  ASL A
  ASL A
  STA E_X,X
  STA E_HX,X
  LDA DEN_R,Y
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #8
  STA E_Y,X
  STA E_HY,X
  LDA DEN_H,Y                  ; along its den
  EOR #1
  STA E_D,X
  LDA #M_RUN
  STA E_M,X
  STZ E_F,X
  STZ E_FT,X
  STZ E_ACC,X
  JSR NEXT_RND
  AND #63
  LDY LEVI
  CLC
  ADC GHOST_T,Y
  STA E_GT,X
  STZ E_T,X                    ; the last ones are crickets
  TXA
  CMP NGRUB,Y
  BCC .sp_n
  INC E_T,X
.sp_n:
  INC T4
  INX
  CPX #NE
  BNE .sp_e
  RTS

; a life lost: the rocks on their way are gone
ROCKS_SETTLE:
  LDX #0
.rs_k:
  LDA R_S,X
  CMP #2
  BCC .rs_n
  STZ R_S,X
  LDA BITS,X
  TSB RKGONE
.rs_n:
  INX
  CPX #NROCK
  BNE .rs_k
  RTS


; ===============================================================
;  MOLE
; ===============================================================
MOLE:
  STZ MMOVE
  LDA JOYC                     ; the ray: Mole stands still
  AND #BTN_MASK
  BEQ .mo_j
  RTS
.mo_j:
  LDA JOYC
  AND #$0F
  BNE .mo_d
  RTS
.mo_d:
  TAX
  LDA JDIR,X
  STA MNEXT
  EOR MDIR                     ; turning back: at once
  CMP #2
  BNE .mo_g
  LDA MNEXT
  STA MDIR
  BRA .mo_go
.mo_g:
  LDA MX                       ; between two cells: on
  AND #15
  BNE .mo_go
  LDA MY
  SEC
  SBC #8
  AND #15
  BNE .mo_go
  LDA MNEXT                    ; at a cell: the new direction, or on, or stop
  JSR CAN_GO
  BCC .mo_k
  LDA MNEXT
  STA MDIR
  BRA .mo_go
.mo_k:
  LDA MDIR
  JSR CAN_GO
  BCS .mo_go
  RTS
.mo_go:
  LDA MSLOW                    ; digging: a step missed every 4 frames
  BEQ .mo_s
  LDA FRAME_CNT
  AND #3
  BNE .mo_s
  RTS
.mo_s:
  LDX MDIR
  LDA MX
  CLC
  ADC DX_T,X
  STA MX
  LDA MY
  CLC
  ADC DY_T,X
  STA MY
  INC MMOVE
  INC MFRM
  STZ DIGN                     ; the earth under Mole
  LDA #1
  STA DIGP
  LDA MX
  JSR BOX_X
  LDA MY
  JSR BOX_Y
  JSR DIG_BOX
  LDA DIGN
  STA MSLOW
  BEQ .mo_st
  LDA FRAME_CNT
  AND #7
  BNE .mo_st
  LDA #S_DIG
  LDX #2
  JSR SFX_BOOM
.mo_st:
  LDA MFRM                     ; the steps
  AND #15
  BNE .mo_r
  LDA #W_STEP1
  LDX MFRM
  CPX #128
  BCC .mo_w
  LDA #W_STEP2
.mo_w:
  LDX #2
  JMP SFX_WHISTLE
.mo_r:
  RTS

; A = direction, Mole at a cell: C = 1 if he can go (inside the garden, no rock)
CAN_GO:
  TAX
  LDA MX
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC DX_T,X
  CMP #16
  BCS .cg_no
  STA T2
  LDA MY
  SEC
  SBC #8
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC DY_T,X
  CMP #11
  BCS .cg_no
  STA T3
  ; a rock in that cell?
  LDA T3
  ASL A
  INC A
  TAX
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  LDA T2
  ASL A
  TAY
  LDA (PTR),Y
  CMP #2
  BEQ .cg_no
  SEC
  RTS
.cg_no:
  CLC
  RTS


; ===============================================================
;  THE ICE RAY
; ===============================================================
RAY:
  LDA JOYC
  AND #BTN_MASK
  BNE .ry_on
  STZ RAYL
  LDA #$FF
  STA RAYE
  RTS
.ry_on:
  LDA RAYL                     ; a new ray: its sound
  BNE .ry_g
  LDA #W_RAY
  LDX #2
  JSR SFX_WHISTLE
.ry_g:
  LDX RAYE                     ; on a bug: it freezes a little more every 12 frames
  BMI .ry_grow
  LDA E_M,X
  CMP #M_RUN
  BEQ .ry_h
  CMP #M_ESC
  BEQ .ry_h
  LDA #$FF
  STA RAYE
  BRA .ry_grow
.ry_h:
  STZ E_FT,X
  INC RAYT
  LDA RAYT
  CMP #12
  BCC .ry_r
  STZ RAYT
  INC E_F,X
  LDA #W_FREEZE
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
  LDA E_F,X
  CMP #3
  BCC .ry_r
  LDA #M_ICE                   ; a block of ice
  STA E_M,X
  STZ E_FT,X
  LDA #$FF
  STA RAYE
.ry_r:
  RTS
.ry_grow:
  LDA RAYL                     ; 4 pixels a frame, as long as the tip is in a tunnel
  CMP #32
  BCS .ry_t
  CLC
  ADC #4
  STA T4
  JSR RAY_OPEN
  BCC .ry_t
  LDA T4
  STA RAYL
.ry_t:
  LDA RAYL
  BEQ .ry_r
  JSR RAY_BOX                  ; a bug in the ray?
  LDX #0
.ry_b:
  LDA E_M,X
  CMP #M_RUN
  BEQ .ry_c
  CMP #M_ESC
  BNE .ry_n
.ry_c:
  LDA E_X,X
  CLC
  ADC #13
  CMP T0
  BCC .ry_n
  LDA E_X,X
  CLC
  ADC #3
  CMP T1
  BCS .ry_n
  LDA E_Y,X
  CLC
  ADC #13
  CMP T2
  BCC .ry_n
  LDA E_Y,X
  CLC
  ADC #3
  CMP T3
  BCS .ry_n
  STX RAYE
  STZ RAYT
  RTS
.ry_n:
  INX
  CPX #NE
  BNE .ry_b
  RTS

; T4 = a length: C = 1 if the tip of the ray is in a tunnel (or in the garden on top)
RAY_OPEN:
  LDX MDIR
  LDA MX
  CLC
  ADC #7
  STA T0
  LDA MY
  CLC
  ADC #7
  STA T1
  CPX #0
  BNE .ro_d
  LDA T0                       ; right: x + 8 + length
  CLC
  ADC #8
  BCS .ro_no
  ADC T4
  BCS .ro_no
  STA T0
  BRA .ro_t
.ro_d:
  CPX #1
  BNE .ro_l
  LDA T1
  CLC
  ADC #8
  ADC T4
  CMP #184
  BCS .ro_no
  STA T1
  BRA .ro_t
.ro_l:
  CPX #2
  BNE .ro_u
  LDA T0
  SEC
  SBC #8
  BCC .ro_no
  SBC T4
  BCC .ro_no
  STA T0
  BRA .ro_t
.ro_u:
  LDA T1
  SEC
  SBC #8
  BCC .ro_no
  SBC T4
  BCC .ro_no
  CMP #8
  BCC .ro_no
  STA T1
.ro_t:
  LDA T1                       ; the tile there
  LSR A
  LSR A
  LSR A
  TAX
  CPX #3
  BCC .ro_yes
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  LDA T0
  LSR A
  LSR A
  LSR A
  TAY
  LDA (PTR),Y
  CMP #1
  BNE .ro_no
.ro_yes:
  SEC
  RTS
.ro_no:
  CLC
  RTS

; the box of the ray: T0-T1 (x), T2-T3 (y)
RAY_BOX:
  LDX MDIR
  LDA MX
  STA T0
  CLC
  ADC #16
  STA T1
  LDA MY
  CLC
  ADC #6
  STA T2
  ADC #4
  STA T3
  CPX #0
  BNE .rb_l
  LDA T1                       ; right
  STA T0
  CLC
  ADC RAYL
  BCC .rb_r
  LDA #255
.rb_r:
  STA T1
  RTS
.rb_l:
  CPX #2
  BNE .rb_v
  LDA MX                       ; left
  STA T1
  SEC
  SBC RAYL
  BCS .rb_lx
  LDA #0
.rb_lx:
  STA T0
  RTS
.rb_v:
  LDA MX
  CLC
  ADC #6
  STA T0
  ADC #4
  STA T1
  CPX #1
  BNE .rb_u
  LDA MY                       ; down
  CLC
  ADC #16
  STA T2
  ADC RAYL
  STA T3
  RTS
.rb_u:
  LDA MY                       ; up
  STA T3
  SEC
  SBC RAYL
  BCS .rb_ux
  LDA #0
.rb_ux:
  STA T2
  RTS


; ===============================================================
;  THE BUGS
; ===============================================================
BUGS:
  LDA NLEFT                    ; none left: the garden is clear
  BNE .bg_1
  LDA #3
  STA GSTATE
  LDA #40
  STA GT
  RTS
.bg_1:
  CMP #1                       ; the last one runs away
  BNE .bg_go
  LDX #0
.bg_f:
  LDA E_M,X
  CMP #M_RUN
  BEQ .bg_es
  CMP #M_EARTH
  BNE .bg_fn
.bg_es:
  LDA E_F,X
  BNE .bg_fn
  LDA #M_ESC
  STA E_M,X
  LDA #W_RUN
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
.bg_fn:
  INX
  CPX #NE
  BNE .bg_f
.bg_go:
  LDX #0
.bg_l:
  STX CB
  LDA E_M,X
  BEQ .bg_n
  CMP #M_ICE
  BNE .bg_fz
  INC E_FT,X                   ; the ice breaks
  LDA E_FT,X
  CMP #20
  BNE .bg_ic
  LDA #W_SHATTER
  LDX #2
  JSR SFX_WHISTLE
  LDX CB
.bg_ic:
  CMP #36
  BCC .bg_n
  JSR BUG_POINTS
  JSR BUG_GONE
  INC KILLN
  BRA .bg_n
.bg_fz:
  LDA E_F,X                    ; frozen: still; the ice melts slowly
  BEQ .bg_mv
  INC E_FT,X
  LDA E_FT,X
  CMP #60
  BCC .bg_n
  STZ E_FT,X
  DEC E_F,X
  BRA .bg_n
.bg_mv:
  JSR BUG_MOVE
.bg_n:
  LDX CB
  INX
  CPX #NE
  BNE .bg_l
  LDA TICKS                    ; the slow timer: into the earth now and then
  AND #3
  BNE .bg_r
  LDX #0
.bg_t:
  LDA E_GT,X
  BEQ .bg_tn
  DEC E_GT,X
.bg_tn:
  INX
  CPX #NE
  BNE .bg_t
.bg_r:
  RTS

; bug CB: gone (frozen to pieces, squashed, run away)
BUG_GONE:
  LDX CB
  STZ E_M,X
  LDA BITS,X
  TRB ALIVE
  DEC NLEFT
  RTS

; bug CB frozen to pieces: 200-500 by the depth, the cricket twice
BUG_POINTS:
  LDX CB
  LDA E_Y,X
  CLC
  ADC #8
  LSR A
  LSR A
  LSR A
  TAY
  LDA LAYER_OF,Y
  LDY E_T,X
  BEQ .bp_g
  CLC
  ADC #4
.bp_g:
  TAY
  LDA ICE_M,Y
  TAY
  LDA #0
  JMP ADD_PTS

; bug CB (X): one frame of moving
BUG_MOVE:
  LDA E_M,X                    ; speed: in the earth half, running away more
  LDY LEVI
  CMP #M_EARTH
  BNE .bm_s1
  LDA SPD_E,Y
  LSR A
  BRA .bm_a
.bm_s1:
  CMP #M_ESC
  BNE .bm_s2
  LDA SPD_E,Y
  CLC
  ADC #$40
  BCC .bm_a
  LDA #$FF
  BRA .bm_a
.bm_s2:
  LDA SPD_E,Y
.bm_a:
  CLC
  ADC E_ACC,X
  STA E_ACC,X
  BCS .bm_step
  RTS
.bm_step:
  LDA E_X,X                    ; at a cell: choose
  AND #15
  BNE .bm_go
  LDA E_Y,X
  SEC
  SBC #8
  AND #15
  BNE .bm_go
  JSR BUG_CHOOSE
  LDX CB
  LDA E_D,X
  BMI .bm_r                    ; (nowhere to go)
.bm_go:
  LDY E_D,X
  LDA E_X,X
  CLC
  ADC DX_T,Y
  STA E_X,X
  LDA E_Y,X
  CLC
  ADC DY_T,Y
  STA E_Y,X
  LDA E_M,X                    ; the cricket digs its way
  CMP #M_EARTH
  BNE .bm_r
  LDA E_T,X
  BEQ .bm_r
  STZ DIGP
  LDA E_X,X
  JSR BOX_X
  LDX CB
  LDA E_Y,X
  JSR BOX_Y
  JMP DIG_BOX
.bm_r:
  RTS

; bug CB at a cell: its new direction
BUG_CHOOSE:
  LDX CB
  LDA E_M,X
  CMP #M_RUN
  BEQ .bc_run
  CMP #M_ESC
  BNE .bc_ea
  JMP .bc_esc
.bc_ea:
  ; in the earth: out again when the time is over and the cell is a tunnel
  LDA E_GT,X
  BNE .bc_ed
  JSR CELL_OPEN0
  BCC .bc_ed
  LDA #M_RUN
  STA E_M,X
  JSR NEXT_RND
  AND #63
  LDY LEVI
  CLC
  ADC GHOST_T,Y
  STA E_GT,X
  BRA .bc_run
.bc_ed:
  ; straight to Mole: on the longer way first (no rock)
  JSR TOWARD
  RTS
.bc_run:
  ; in the tunnels: time to go into the earth?
  LDA E_GT,X
  BNE .bc_t
  LDA #M_EARTH
  STA E_M,X
  LDA #40
  STA E_GT,X
  JMP TOWARD
.bc_t:
  LDA MX
  STA TGX
  LDA MY
  STA TGY
  LDA #$FF
  STA BEST
  STA BESTD
  LDA E_D,X                    ; never back, unless nothing else
  EOR #2
  STA T5
  LDY #0
.bc_d:
  CPY T5
  BEQ .bc_dn
  JSR CELL_OPEN
  BCC .bc_dn
  JSR DIST                     ; A = distance from the target after that step
  CMP BEST
  BCS .bc_dn
  STA BEST
  STY BESTD
.bc_dn:
  INY
  CPY #4
  BNE .bc_d
  LDA BESTD
  BPL .bc_ok
  LDY T5                       ; a dead end: back
  JSR CELL_OPEN
  BCC .bc_no
  STY BESTD
  BRA .bc_ok
.bc_no:
  LDA #$FF
  STA E_D,X
  RTS
.bc_ok:
  JSR NEXT_RND                 ; now and then a random way
  AND #7
  BNE .bc_set
  LDY #0
.bc_rn:
  CPY T5
  BEQ .bc_rx
  JSR CELL_OPEN
  BCC .bc_rx
  JSR NEXT_RND
  AND #1
  BEQ .bc_rx
  STY BESTD
  BRA .bc_set
.bc_rx:
  INY
  CPY #4
  BNE .bc_rn
.bc_set:
  LDA BESTD
  STA E_D,X
  RTS
.bc_esc:
  ; running away: up to the surface, then left; gone at the left edge
  LDA E_Y,X
  CMP #8
  BNE .bc_up
  LDA E_X,X
  BNE .bc_lf
  INC ESCOUT
  JMP BUG_GONE
.bc_lf:
  LDA #2
  STA E_D,X
  RTS
.bc_up:
  LDY #3
  JSR CELL_ROCK
  BCS .bc_sd
  TYA
  STA E_D,X
  RTS
.bc_sd:
  LDY #2                       ; a rock above: aside
  LDA E_X,X
  BNE .bc_sx
  LDY #0
.bc_sx:
  TYA
  STA E_D,X
  RTS

; bug CB in the earth: toward Mole on the longer way (no rock, inside the garden)
TOWARD:
  LDX CB
  LDA MX
  SEC
  SBC E_X,X
  STA T0                       ; dx
  BCS .tw_xp
  EOR #$FF
  INC A
.tw_xp:
  STA T2
  LDA MY
  SEC
  SBC E_Y,X
  STA T1                       ; dy
  BCS .tw_yp
  EOR #$FF
  INC A
.tw_yp:
  STA T3
  CMP T2
  BCC .tw_h
  ; vertical first
  LDY #1
  LDA T1
  BPL .tw_v1
  LDY #3
.tw_v1:
  LDA T3
  BEQ .tw_h
  JSR CELL_ROCK
  BCC .tw_set
.tw_h:
  LDY #0
  LDA T0
  BPL .tw_h1
  LDY #2
.tw_h1:
  LDA T2
  BEQ .tw_any
  JSR CELL_ROCK
  BCC .tw_set
.tw_any:
  LDA E_D,X                    ; else on, if it can
  AND #3
  TAY
  JSR CELL_ROCK
  BCC .tw_set
  LDA E_D,X
  AND #3
  EOR #2
  TAY
.tw_set:
  TYA
  STA E_D,X
  RTS

; bug CB at a cell, Y = direction: C = 1 if the next cell is a tunnel (4 tiles dug) or the surface (keeps X, Y)
CELL_OPEN:
  PHY
  JSR NEXT_CELL
  BCC .co_no
  LDA T7
  BEQ .co_yes                  ; the surface
  JSR CELL_DUG
  PLY
  RTS
.co_yes:
  PLY
  SEC
  RTS
.co_no:
  PLY
  CLC
  RTS

; bug CB: C = 1 if the cell where it is now is a tunnel (keeps X)
CELL_OPEN0:
  LDA E_X,X
  LSR A
  LSR A
  LSR A
  LSR A
  STA T6
  LDA E_Y,X
  SEC
  SBC #8
  LSR A
  LSR A
  LSR A
  LSR A
  STA T7
  BEQ .c0_y
  JMP CELL_DUG
.c0_y:
  SEC
  RTS

; bug CB at a cell, Y = direction: C = 1 if the next cell is inside the garden and has no rock (keeps X, Y)
CELL_ROCK:
  PHY
  JSR NEXT_CELL
  BCC .cr_no
  LDA T7
  ASL A
  INC A
  PHX
  TAX
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  PLX
  LDA T6
  ASL A
  TAY
  LDA (PTR),Y
  CMP #2
  BEQ .cr_no
  PLY
  CLC
  RTS
.cr_no:
  PLY
  SEC
  RTS

; bug CB, Y = direction: T6 / T7 = the next cell (column, row); C = 0 if outside the garden (keeps X)
NEXT_CELL:
  LDA E_X,X
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC DX_T,Y
  CMP #16
  BCS .nc_no
  STA T6
  LDA E_Y,X
  SEC
  SBC #8
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC DY_T,Y
  CMP #11
  BCS .nc_no
  STA T7
  SEC
  RTS
.nc_no:
  CLC
  RTS

; T6 / T7 = a cell: C = 1 if its 4 tiles are dug (keeps X)
CELL_DUG:
  PHX
  LDA T7
  ASL A
  INC A
  TAX
  LDA DR_LO,X
  STA PTR
  LDA DR_HI,X
  STA PTR+1
  PLX
  LDA T6
  ASL A
  TAY
  LDA (PTR),Y
  CMP #1
  BNE .cd_no
  INY
  LDA (PTR),Y
  CMP #1
  BNE .cd_no
  TYA
  CLC
  ADC #31
  TAY
  LDA (PTR),Y
  CMP #1
  BNE .cd_no
  INY
  LDA (PTR),Y
  CMP #1
  BNE .cd_no
  SEC
  RTS
.cd_no:
  CLC
  RTS

; bug CB (X), Y = direction: A = |x + 16 dx - TGX| + |y + 16 dy - TGY| / 2 (keeps X, Y)
DIST:
  LDA DX_T,Y
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC E_X,X
  SEC
  SBC TGX
  BCS .di_x
  EOR #$FF
  INC A
.di_x:
  LSR A
  STA T6
  LDA DY_T,Y
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC E_Y,X
  SEC
  SBC TGY
  BCS .di_y
  EOR #$FF
  INC A
.di_y:
  LSR A
  CLC
  ADC T6
  RTS


; ===============================================================
;  ROCKS, THE VEGETABLE, WHO TOUCHES WHO
; ===============================================================
ROCKS:
  LDX #0
.rk_l:
  STX T5
  LDA R_S,X
  BEQ .rk_n
  CMP #1
  BNE .rk_2
  JSR ROCK_LOOSE               ; still: the earth below is gone?
  BRA .rk_n
.rk_2:
  CMP #2
  BNE .rk_3
  DEC R_T,X                    ; shaking
  BNE .rk_n
  LDA #3
  STA R_S,X
  STZ R_N,X
  BRA .rk_n
.rk_3:
  CMP #3
  BNE .rk_4
  JSR ROCK_FALL
  BRA .rk_n
.rk_4:
  DEC R_T,X                    ; broken: gone after a while
  BNE .rk_n
  STZ R_S,X
.rk_n:
  LDX T5
  INX
  CPX #NROCK
  BNE .rk_l
  RTS

; rock T5 still: it shakes when the cell below is a tunnel and Mole is not right under it
ROCK_LOOSE:
  LDX T5
  LDA R_X,X
  LSR A
  LSR A
  LSR A
  LSR A
  STA T6
  LDA R_Y,X
  SEC
  SBC #8
  LSR A
  LSR A
  LSR A
  LSR A
  INC A
  CMP #11
  BCS .rl_r
  STA T7
  JSR CELL_DUG
  BCC .rl_r
  LDX T5
  LDA MX                       ; Mole holds it up from below
  SEC
  SBC R_X,X
  BCS .rl_p
  EOR #$FF
  INC A
.rl_p:
  CMP #16
  BCS .rl_go
  LDA MY
  SEC
  SBC R_Y,X
  BCC .rl_go
  CMP #32
  BCC .rl_r
.rl_go:
  LDA #2                       ; shakes; its cell is a tunnel now
  STA R_S,X
  LDA #30
  STA R_T,X
  LDA R_X,X
  LSR A
  LSR A
  LSR A
  STA TCOL
  LDA R_Y,X
  LSR A
  LSR A
  LSR A
  STA TROW
  LDA #1
  JSR SET_CELL
  JSR REDRAW_CELL
  LDA #W_WOBBLE
  LDX #2
  JSR SFX_WHISTLE
.rl_r:
  RTS

; TROW / TCOL = the top left tile of a cell: its tiles and the ones around
REDRAW_CELL:
  JSR REDRAW5
  INC TCOL
  JSR REDRAW5
  INC TROW
  JSR REDRAW5
  DEC TCOL
  JMP REDRAW5

; rock T5 falling: 2 pixels a frame; it squashes; it stops on the earth
ROCK_FALL:
  LDX T5
  LDA R_Y,X
  CLC
  ADC #2
  STA R_Y,X
  LDY #0                       ; the bugs under it
.rf_b:
  LDA E_M,Y
  BEQ .rf_bn
  CMP #M_ICE
  BEQ .rf_bn
  LDA E_X,Y
  SEC
  SBC R_X,X
  BCS .rf_bx
  EOR #$FF
  INC A
.rf_bx:
  CMP #12
  BCS .rf_bn
  LDA E_Y,Y
  SEC
  SBC R_Y,X
  BCC .rf_bn
  CMP #14
  BCS .rf_bn
  STY CB                       ; squashed: 500, 1000, 1500 ...
  PHX
  LDA R_N,X
  TAX
  LDY CRUSH_M,X
  LDA #0
  JSR ADD_PTS
  PLX
  INC R_N,X
  JSR BUG_GONE
  LDX T5
  LDY CB
  LDA #W_SHATTER
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
.rf_bn:
  INY
  CPY #NE
  BNE .rf_b
  LDA MX                       ; Mole under it
  SEC
  SBC R_X,X
  BCS .rf_mx
  EOR #$FF
  INC A
.rf_mx:
  CMP #12
  BCS .rf_c
  LDA MY
  SEC
  SBC R_Y,X
  BCC .rf_c
  CMP #14
  BCS .rf_c
  LDA #2
  JMP MOLE_DIES
.rf_c:
  LDA R_Y,X                    ; at a cell: the next one is a tunnel?
  SEC
  SBC #8
  AND #15
  BNE .rf_r
  LDA R_X,X
  LSR A
  LSR A
  LSR A
  LSR A
  STA T6
  LDA R_Y,X
  SEC
  SBC #8
  LSR A
  LSR A
  LSR A
  LSR A
  INC A
  CMP #11
  BCS .rf_land
  STA T7
  JSR CELL_DUG
  BCS .rf_r
.rf_land:
  LDX T5
  LDA #4
  STA R_S,X
  LDA #40
  STA R_T,X
  LDA BITS,X
  TSB RKGONE
  INC DROPS
  LDA #S_THUD
  LDX #2
  JSR SFX_BOOM
.rf_r:
  RTS

; the vegetable: after two rocks, in the middle for 10 seconds
VEGGIE:
  LDA VEGD
  BNE .vg_on
  LDA DROPS
  CMP #2
  BCC .vg_r
  INC VEGD
  LDA #150
  STA VEGT
.vg_on:
  LDA VEGT
  BEQ .vg_r
  LDA TICKS
  AND #3
  BNE .vg_t
  DEC VEGT
.vg_t:
  LDA MX                       ; Mole takes it
  SEC
  SBC #112
  BCS .vg_x
  EOR #$FF
  INC A
.vg_x:
  CMP #12
  BCS .vg_r
  LDA MY
  SEC
  SBC #88
  BCS .vg_y
  EOR #$FF
  INC A
.vg_y:
  CMP #12
  BCS .vg_r
  STZ VEGT
  LDA LEVEL
  AND #7
  TAX
  LDY VEGP_M,X
  LDA #0
  JSR ADD_PTS
  LDA #W_VEG
  LDX #2
  JMP SFX_WHISTLE
.vg_r:
  RTS

; a bug that is not frozen touches Mole: a life lost
HITS:
  LDX #0
.ht_l:
  LDA E_M,X
  BEQ .ht_n
  CMP #M_ICE
  BEQ .ht_n
  LDA E_F,X
  BNE .ht_n
  LDA E_X,X
  SEC
  SBC MX
  BCS .ht_x
  EOR #$FF
  INC A
.ht_x:
  CMP #11
  BCS .ht_n
  LDA E_Y,X
  SEC
  SBC MY
  BCS .ht_y
  EOR #$FF
  INC A
.ht_y:
  CMP #11
  BCS .ht_n
  LDA #1
  JMP MOLE_DIES
.ht_n:
  INX
  CPX #NE
  BNE .ht_l
  RTS

; A = what (DEATHS): Mole is caught
MOLE_DIES:
  STA DEATHS
  LDA GSTATE
  BNE .md_r
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  STZ RAYL
  LDA #W_DOWN
  LDX #2
  JSR SFX_WHISTLE
.md_r:
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA GSTATE                   ; Mole (2 sprites, always first)
  CMP #3
  BEQ .bs_o
  CMP #1
  BNE .bs_m
  LDA GT
  CMP #20
  BCC .bs_o
  LDA #PT_MDIE
  LDX GT
  CPX #60
  BCS .bs_mk
  LDA #PT_MDIE+8
  BRA .bs_mk
.bs_m:
  LDA MDIR
  ASL A
  STA T0
  LDA MFRM
  LSR A
  LSR A
  AND #1
  ORA T0
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_MOLE
.bs_mk:
  STA ON
  LDA MX
  STA OX
  LDA MY
  DEC A
  STA OY
  LDA #13                      ; the nose and the paws
  STA OC
  LDA ON
  PHA
  CLC
  ADC #4
  STA ON
  JSR ADD_SPR
  PLA
  STA ON
  LDA #14                      ; the fur
  STA OC
  JSR ADD_SPR
  JSR RAY_SPR
.bs_o:
  LDA SPRROT                   ; the others, a different first one every frame
  INC A
  CMP #NE+NROCK+1
  BCC .bs_rot
  LDA #0
.bs_rot:
  STA SPRROT
  STA T7
  LDA #NE+NROCK+1
  STA T6
.bs_k:
  LDX T7
  CPX #NE
  BCS .bs_nb
  JSR BUG_SPR
  BRA .bs_kn
.bs_nb:
  TXA
  SEC
  SBC #NE
  CMP #NROCK
  BCS .bs_vg
  TAX
  JSR ROCK_SPR
  BRA .bs_kn
.bs_vg:
  JSR VEG_SPR
.bs_kn:
  INC T7
  LDA T7
  CMP #NE+NROCK+1
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

; the ice ray: 1 or 2 sprites from the side Mole looks at
RAY_SPR:
  LDA RAYL
  BEQ .rs_r
  LDA MX
  STA OX
  LDA MY
  DEC A
  STA OY
  LDA #7
  STA OC
  LDA RAYL                     ; the first piece: up to 16 pixels
  CMP #16
  BCC .rs_1
  LDA #16
.rs_1:
  JSR .rs_one
  LDA RAYL
  SEC
  SBC #16
  BEQ .rs_r
  BCC .rs_r
.rs_one:                       ; A = length (4-16): one more piece, 16 pixels further
  LSR A
  LSR A
  DEC A
  STA T0
  LDA MDIR
  ASL A
  ASL A
  ORA T0
  ASL A
  ASL A
  CLC
  ADC #PT_RAY
  STA ON
  LDX MDIR
  LDA OX
  CLC
  ADC RAYDX,X
  STA OX
  LDA OY
  CLC
  ADC RAYDY,X
  STA OY
  JMP ADD_SPR
.rs_r:
  RTS

; X = bug: its sprite
BUG_SPR:
  LDA E_M,X
  BNE .bu_on
  RTS
.bu_on:
  LDA E_X,X
  STA OX
  LDA E_Y,X
  DEC A
  STA OY
  LDA E_M,X
  CMP #M_ICE
  BNE .bu_n
  LDA #PT_ICE                  ; the ice block, then the pieces
  LDY #7
  PHA
  LDA E_FT,X
  CMP #20
  PLA
  BCC .bu_set
  LDA #PT_SHARD
  LDY #15
  BRA .bu_set
.bu_n:
  CMP #M_EARTH                 ; a grub in the earth: the eyes
  BNE .bu_b
  LDA E_T,X
  BNE .bu_b
  LDA FRAME_CNT
  AND #16
  LSR A
  LSR A
  CLC
  ADC #PT_EYES
  LDY #15
  BRA .bu_set
.bu_b:
  LDA #0                       ; facing: left or right
  LDY E_D,X
  CPY #2
  BNE .bu_d
  LDA #8
.bu_d:
  STA T0
  LDA E_X,X
  EOR E_Y,X
  AND #8
  LSR A
  ORA T0
  LDY E_T,X
  BEQ .bu_g
  CLC
  ADC #PT_CRICKET
  LDY #12
  BRA .bu_c
.bu_g:
  CLC
  ADC #PT_GRUB
  LDY #15
.bu_c:
  PHA                          ; frozen: pale blue, then cyan
  LDA E_F,X
  BEQ .bu_f
  LDY #5
  CMP #2
  BCC .bu_f
  LDY #7
.bu_f:
  PLA
.bu_set:
  STA ON
  STY OC
  JMP ADD_SPR

; X = rock: shaking, falling or broken
ROCK_SPR:
  LDA R_S,X
  CMP #2
  BCS .rk_on
  RTS
.rk_on:
  STA T0
  LDA R_X,X
  STA OX
  LDA R_Y,X
  DEC A
  STA OY
  LDA T0
  CMP #2
  BNE .rk_k
  LDA FRAME_CNT                ; shaking
  AND #2
  LSR A
  CLC
  ADC OX
  STA OX
.rk_k:
  LDA #PT_POTATO               ; a potato in soil and clay, a stone below
  LDY #10
  LDA R_Y,X
  CMP #104
  LDA #PT_POTATO
  BCC .rk_p
  LDA #PT_STONE
  LDY #14
.rk_p:
  STY OC
  LDY T0
  CPY #4
  BNE .rk_s
  LDA #PT_CRUMB
.rk_s:
  STA ON
  JMP ADD_SPR

; the vegetable
VEG_SPR:
  LDA VEGT
  BNE .vs_on
  RTS
.vs_on:
  LDA #112
  STA OX
  LDA #87
  STA OY
  LDA LEVEL
  AND #7
  TAX
  LDA VEGC,X
  STA OC
  TXA
  ASL A
  ASL A
  CLC
  ADC #PT_VEG
  STA ON
  JMP ADD_SPR

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
;  SCREEN: VRAM, texts, sprites, sound (from hedge hop)
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
BITS:       .byte 1,2,4,8,16,32,64,128
LOWBITS:    .byte 0,1,3,7,15,31,63,127          ; the first n bugs
S_BIG = S_THUD                                  ; (lib_sound: a big noise is not cut by a small one)
; the four directions: right, down, left, up
DX_T:       .byte 1,0,$FF,0
DY_T:       .byte 0,1,0,$FF
RAYDX:      .byte 16,0,$F0,0                    ; the pieces of the ray, from Mole
RAYDY:      .byte 0,16,0,$F0
; joystick bits (1 up, 2 down, 4 left, 8 right) -> direction (up and down first)
JDIR:       .byte $FF,3,1,3,2,3,1,3,0,3,1,3,2,3,1,3
; the ground: layer of every tile row (0 soil .. 3 rock), its first tile (layer * 18), its rock tiles (layer * 4)
LAYER_OF:   .byte 0,0,0,0,0,0,0,0,1,1,1,1,1,2,2,2,2,2,3,3,3,3,3,3
LBASE:      .byte 0,0,0,0,0,0,0,0,18,18,18,18,18,36,36,36,36,36,54,54,54,54,54,54
LROCK:      .byte 0,0,0,0,0,0,0,0,4,4,4,4,4,8,8,8,8,8,12,12,12,12,12,12
; DIG: the start of every tile row (rows 1-22; rows 0 and 23 point to row 1)
DR_LO:      .byte <(DIG+0),<(DIG+0),<(DIG+32),<(DIG+64),<(DIG+96),<(DIG+128),<(DIG+160),<(DIG+192),<(DIG+224),<(DIG+256),<(DIG+288),<(DIG+320),<(DIG+352),<(DIG+384),<(DIG+416),<(DIG+448),<(DIG+480),<(DIG+512),<(DIG+544),<(DIG+576),<(DIG+608),<(DIG+640),<(DIG+672),<(DIG+672)
DR_HI:      .byte >(DIG+0),>(DIG+0),>(DIG+32),>(DIG+64),>(DIG+96),>(DIG+128),>(DIG+160),>(DIG+192),>(DIG+224),>(DIG+256),>(DIG+288),>(DIG+320),>(DIG+352),>(DIG+384),>(DIG+416),>(DIG+448),>(DIG+480),>(DIG+512),>(DIG+544),>(DIG+576),>(DIG+608),>(DIG+640),>(DIG+672),>(DIG+672)
PD_LO:      .byte <PDIG,<(PDIG+80)                ; the tunnels saved of every player
PD_HI:      .byte >PDIG,>(PDIG+80)
; the garden on top: rows 1 and 2
SURF:       .byte T_SKY+3,T_SKY+1,T_SKY+1,T_SKY+0,T_SKY+2,T_SKY+0,T_SKY+0,T_SKY+1,T_SKY+1,T_SKY+0,T_SKY+2,T_SKY+0,T_SKY+0,T_SKY+0,T_SKY+0,T_SKY+0
            .byte T_SKY+0,T_SKY+0,T_SKY+0,T_SKY+1,T_SKY+1,T_SKY+0,T_SKY+2,T_SKY+0,T_SKY+0,T_SKY+1,T_SKY+1,T_SKY+0,T_SKY+2,T_SKY+0,T_SKY+0,T_SKY+3
            .byte T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1
            .byte T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0,T_TOP+0,T_TOP+1,T_TOP+0

; per level (0-9): bugs, of them grubs (the others are crickets), speed of the bugs (fraction of a pixel),
; frames / 4 in the tunnels before going into the earth
NBUGS:      .byte 4,4,5,5,6,6,7,7,7,7
NGRUB:      .byte 3,3,4,4,4,4,5,5,5,5
SPD_E:      .byte $80,$88,$90,$98,$A0,$A8,$B0,$B8,$C0,$C8
GHOST_T:    .byte 120,110,100,90,80,70,60,55,50,45
; points (hundreds, BCD): frozen to pieces by the layer, then the cricket; squashed 1st, 2nd ...; vegetables
ICE_M:      .byte $02,$03,$04,$05,$04,$06,$08,$10
CRUSH_M:    .byte $05,$10,$15,$20,$25,$30,$35
VEGP_M:     .byte $04,$06,$08,$10,$20,$30,$40,$50
VEGC:       .byte 8,13,15,9,8,13,2,12              ; carrot, radish, onion, pumpkin, tomato, aubergine, pepper, cabbage

; title: Mole (2), grub, cricket, potato, a vegetable (sprite Y, X, pattern, colour, second frame)
TITLE_NS = 6
TITLE_SY:   .byte 22,22,83,99,115,131
TITLE_SX:   .byte 24,24,56,56,56,56
TITLE_SN:   .byte PT_MOLE+4,PT_MOLE,PT_GRUB,PT_CRICKET,PT_POTATO,PT_VEG
TITLE_SC:   .byte 13,14,15,12,10,8
TITLE_SA:   .byte 8,8,4,4,0,0

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
  .byte 9,3,"BUTTON = ICE RAY, 3 HITS",0
  .byte 11,10,"GRUB      200-500",0
  .byte 13,10,"CRICKET  400-1000",0
  .byte 15,10,"SQUASHED  500 +",0
  .byte 17,10,"VEGETABLE 400 +",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 13,11,"PLAYER ",0,$FF

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
;  GRAPHICS, GARDENS AND SOUND TABLES (generated)
; ===============================================================
; MOLE HOLE: generated by dev/gen_mole_hole.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; tiles
T_EARTH = 96
T_TUN = 98
T_SKY = 168
T_TOP = 172
T_ROCK = 174
T_LIFE = 190
PT_MOLE = 0
PT_MDIE = 64
PT_GRUB = 80
PT_CRICKET = 96
PT_EYES = 112
PT_ICE = 120
PT_SHARD = 124
PT_RAY = 128
PT_POTATO = 192
PT_STONE = 196
PT_CRUMB = 200
PT_VEG = 204
PER_LAYER = 18
NLAY = 8
NDEN = 7
NROCK = 4
BIGT = 200
BIGB = 220
SPR_LEN = 1888
SPR_PAGES = 8
SPRITES:
  .byte $00,$00,$07,$1F,$3F,$7F,$7F,$FF,$FF,$FF,$7F,$7F,$3F,$00,$00,$00,$00,$00,$E0,$F8,$FC,$EC,$FE,$F8,$FC,$F8,$F8,$F0,$F0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$38,$00,$00,$00,$00,$00,$00,$00,$01,$07,$02,$00,$04,$0E,$04,$30,$70,$00
  .byte $00,$00,$07,$1F,$3F,$7F,$7F,$FF,$FF,$FF,$7F,$7F,$3F,$00,$00,$00,$00,$00,$E0,$F8,$FC,$EC,$FE,$F8,$FC,$F8,$F8,$F8,$F0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$1C,$00,$00,$00,$00,$00,$00,$00,$01,$07,$02,$04,$07,$04,$00,$60,$E0,$00
  .byte $03,$0F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$07,$01,$00,$00,$80,$E0,$F0,$F8,$F8,$FC,$FC,$FC,$FC,$FC,$FC,$D8,$F8,$70,$40,$00
  .byte $00,$00,$40,$60,$60,$00,$00,$00,$00,$40,$60,$60,$08,$1C,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$C0
  .byte $03,$0F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$1F,$0F,$01,$00,$00,$80,$E0,$F0,$F8,$F8,$FC,$FC,$FC,$FC,$FC,$FC,$D8,$F8,$70,$40,$00
  .byte $00,$00,$00,$40,$60,$60,$00,$00,$40,$60,$60,$00,$00,$0E,$05,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$C0
  .byte $00,$00,$07,$1F,$3F,$37,$7F,$1F,$3F,$1F,$1F,$0F,$0F,$00,$00,$00,$00,$00,$E0,$F8,$FC,$FE,$FE,$FF,$FF,$FF,$FE,$FE,$FC,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$E0,$40,$00,$20,$70,$20,$0C,$0E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$1C,$00
  .byte $00,$00,$07,$1F,$3F,$37,$7F,$1F,$3F,$1F,$1F,$1F,$0F,$00,$00,$00,$00,$00,$E0,$F8,$FC,$FE,$FE,$FF,$FF,$FF,$FE,$FE,$FC,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$E0,$40,$20,$E0,$20,$00,$06,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$38,$00
  .byte $00,$02,$0E,$1F,$1B,$3F,$3F,$3F,$3F,$3F,$3F,$1F,$1F,$0F,$07,$01,$00,$00,$80,$E0,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F0,$C0
  .byte $03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$90,$38,$10,$06,$06,$02,$00,$00,$00,$00,$06,$06,$02,$00,$00
  .byte $00,$02,$0E,$1F,$1B,$3F,$3F,$3F,$3F,$3F,$3F,$1F,$1F,$0F,$07,$01,$00,$00,$80,$F0,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F8,$F0,$C0
  .byte $03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$A0,$70,$00,$00,$06,$06,$02,$00,$00,$06,$06,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$7F,$EF,$FF,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$FC,$EE,$FF,$FE,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$28,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$14,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3F,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FC,$FF,$FF,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$54,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$2A,$00,$00
  .byte $00,$00,$00,$00,$00,$19,$3D,$7F,$FF,$FF,$7F,$36,$00,$00,$00,$00,$00,$00,$00,$00,$00,$98,$BC,$F6,$F6,$FE,$FD,$D8,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$66,$FF,$FF,$FF,$7F,$2A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$6C,$F6,$F6,$FE,$FD,$A8,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$19,$3D,$6F,$6F,$7F,$BF,$1B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$98,$BC,$FE,$FF,$FF,$FE,$6C,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$36,$6F,$6F,$7F,$BF,$15,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$66,$FF,$FF,$FF,$FE,$54,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$10,$0F,$3F,$7F,$FF,$7F,$34,$24,$49,$00,$00,$00,$00,$00,$00,$08,$10,$F0,$FC,$FF,$FF,$FF,$96,$96,$24,$00,$00,$00
  .byte $00,$00,$00,$10,$10,$0F,$3F,$7F,$FF,$7F,$32,$12,$24,$00,$00,$00,$00,$00,$00,$10,$10,$F0,$FC,$FF,$FF,$FF,$4A,$4B,$90,$00,$00,$00
  .byte $00,$00,$00,$10,$08,$0F,$3F,$FF,$FF,$FF,$69,$69,$24,$00,$00,$00,$00,$00,$00,$04,$08,$F0,$FC,$FE,$FF,$FE,$2C,$24,$92,$00,$00,$00
  .byte $00,$00,$00,$08,$08,$0F,$3F,$FF,$FF,$FF,$52,$D2,$09,$00,$00,$00,$00,$00,$00,$08,$08,$F0,$FC,$FE,$FF,$FE,$4C,$48,$24,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$18,$3C,$2C,$3C,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$F0,$B0,$F0,$60,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0C,$1E,$1A,$1E,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$78,$68,$78,$30,$00,$00,$00,$00,$00,$00
  .byte $00,$3F,$40,$58,$50,$40,$40,$40,$40,$42,$40,$40,$40,$40,$3F,$00,$00,$FC,$02,$02,$02,$02,$42,$02,$02,$02,$02,$0A,$1A,$02,$FC,$00
  .byte $40,$10,$82,$20,$04,$50,$02,$80,$12,$40,$08,$82,$20,$02,$48,$00,$08,$81,$10,$08,$82,$08,$20,$12,$00,$44,$02,$40,$09,$80,$04,$80
  .byte $00,$00,$00,$00,$00,$00,$90,$F0,$F0,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$92,$FF,$FF,$92,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$92,$FF,$FF,$92,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$F0,$F0,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$92,$FF,$FF,$92,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$49,$FF,$FF,$49,$00,$00,$00,$00,$00,$00
  .byte $03,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$80,$80,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$01,$01,$03,$01,$01,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$80,$80,$C0,$80,$80,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$01,$01,$00,$00,$00,$00,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$00,$00,$00,$00
  .byte $03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$0F,$0F,$09,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$49,$FF,$FF,$49,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$0F,$0F,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$49,$FF,$FF,$49,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$92,$FF,$FF,$92,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$49,$FF,$FF,$49,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$80,$80,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$01,$01,$03,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$80,$80,$C0,$80,$80,$C0
  .byte $00,$00,$00,$00,$01,$01,$03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$00,$00,$00,$00,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0
  .byte $03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$01,$01,$03,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0,$80,$80,$C0
  .byte $00,$07,$1F,$3B,$7F,$7F,$7F,$6F,$3F,$3F,$1F,$1F,$0F,$03,$00,$00,$00,$E0,$F8,$F8,$F8,$7C,$FE,$FE,$FE,$DE,$FC,$F8,$F0,$C0,$00,$00
  .byte $00,$03,$0F,$1F,$3E,$7F,$7F,$7F,$7F,$7E,$3F,$3F,$1F,$07,$00,$00,$00,$E0,$F8,$FC,$FE,$FE,$FE,$FA,$FE,$FE,$FE,$FC,$F8,$E0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$32,$7B,$FF,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$3C,$F6,$FE,$00,$00
  .byte $00,$00,$00,$02,$01,$03,$07,$07,$03,$03,$03,$01,$01,$00,$00,$00,$00,$00,$00,$80,$00,$80,$C0,$C0,$80,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$02,$01,$07,$0F,$0F,$0F,$07,$03,$01,$00,$00,$00,$00,$00,$00,$40,$80,$00,$C0,$E0,$E0,$E0,$C0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$01,$03,$07,$0F,$0F,$0F,$07,$02,$04,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$E0,$C0,$80,$40,$00,$00,$00
  .byte $00,$00,$00,$01,$09,$3F,$7F,$7F,$7F,$7F,$3F,$0F,$00,$00,$00,$00,$00,$00,$00,$80,$20,$F8,$FC,$FC,$FC,$FC,$F8,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$0F,$1F,$3F,$3F,$3F,$1F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F0,$F8,$F8,$F8,$F0,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$03,$01,$03,$07,$07,$0F,$0F,$0F,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$F0,$F0,$E0,$C0,$00,$00,$00
  .byte $00,$00,$00,$01,$02,$0F,$1F,$1F,$1F,$0F,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$E0,$C0,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$0F,$15,$3F,$55,$7F,$55,$3F,$15,$0F,$00,$00,$00,$00,$00,$00,$00,$E0,$50,$F8,$54,$FC,$54,$F8,$50,$E0,$00,$00,$00,$00

; game tiles 96-190: patterns and colours
TILEP:
  .byte $00,$40,$04,$00,$20,$02,$10,$00,$00,$08,$80,$02,$00,$44,$00,$10,$FF,$C3,$81,$81,$81,$81,$C3,$FF,$81,$81,$81,$81,$81,$81,$C3,$FF
  .byte $FF,$C0,$80,$80,$80,$80,$C0,$FF,$80,$80,$80,$80,$80,$80,$C0,$FF,$FF,$C3,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $FF,$C0,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$FF,$03,$01,$01,$01,$01,$03,$FF,$01,$01,$01,$01,$01,$01,$03,$FF
  .byte $FF,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$04,$00,$20,$02,$10,$00,$00,$08,$80,$02,$00,$44,$00,$10
  .byte $FF,$C3,$81,$81,$81,$81,$C3,$FF,$81,$81,$81,$81,$81,$81,$C3,$FF,$FF,$C0,$80,$80,$80,$80,$C0,$FF,$80,$80,$80,$80,$80,$80,$C0,$FF
  .byte $FF,$C3,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$FF,$C0,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $FF,$03,$01,$01,$01,$01,$03,$FF,$01,$01,$01,$01,$01,$01,$03,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $FF,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$60,$64,$00,$18,$1A,$40,$00,$08,$01,$60,$66,$06,$80,$18,$18,$FF,$C3,$81,$81,$81,$81,$C3,$FF,$81,$81,$81,$81,$81,$81,$C3,$FF
  .byte $FF,$C0,$80,$80,$80,$80,$C0,$FF,$80,$80,$80,$80,$80,$80,$C0,$FF,$FF,$C3,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81
  .byte $FF,$C0,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$FF,$03,$01,$01,$01,$01,$03,$FF,$01,$01,$01,$01,$01,$01,$03,$FF
  .byte $FF,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$64,$00,$18,$1A,$40,$00,$08,$01,$60,$66,$06,$80,$18,$18
  .byte $FF,$C3,$81,$81,$81,$81,$C3,$FF,$81,$81,$81,$81,$81,$81,$C3,$FF,$FF,$C0,$80,$80,$80,$80,$C0,$FF,$80,$80,$80,$80,$80,$80,$C0,$FF
  .byte $FF,$C3,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$FF,$C0,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $FF,$03,$01,$01,$01,$01,$03,$FF,$01,$01,$01,$01,$01,$01,$03,$FF,$FF,$00,$00,$00,$00,$00,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $FF,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$38,$54,$12,$2A,$49,$00,$00,$00,$3C,$7E,$DB,$FF,$7E,$00,$80,$A0,$E2,$27,$22,$22,$22
  .byte $48,$AD,$FF,$FF,$FF,$B7,$FF,$DF,$20,$52,$FF,$FF,$EF,$FF,$FB,$FF,$00,$07,$1F,$3B,$7F,$7F,$7F,$6F,$00,$E0,$F8,$F8,$F8,$7C,$FE,$FE
  .byte $3F,$3F,$1F,$1F,$0F,$03,$00,$00,$FE,$DE,$FC,$F8,$F0,$C0,$00,$00,$00,$07,$1F,$3B,$7F,$7F,$7F,$6F,$00,$E0,$F8,$F8,$F8,$7C,$FE,$FE
  .byte $3F,$3F,$1F,$1F,$0F,$03,$00,$00,$FE,$DE,$FC,$F8,$F0,$C0,$00,$00,$00,$03,$0F,$1F,$3E,$7F,$7F,$7F,$00,$E0,$F8,$FC,$FE,$FE,$FE,$FA
  .byte $7F,$7E,$3F,$3F,$1F,$07,$00,$00,$FE,$FE,$FE,$FC,$F8,$E0,$00,$00,$00,$03,$0F,$1F,$3E,$7F,$7F,$7F,$00,$E0,$F8,$FC,$FE,$FE,$FE,$FA
  .byte $7F,$7E,$3F,$3F,$1F,$07,$00,$00,$FE,$FE,$FE,$FC,$F8,$E0,$00,$00,$00,$3C,$7E,$DB,$FF,$79,$48,$00
TILEC:
  .byte $AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$91,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$C7,$27,$27,$27,$27,$27,$27,$27,$27,$E7,$E7,$E7,$E7,$E7,$E7,$E7,$E7
  .byte $2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$2A,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB
  .byte $AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA
  .byte $BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$BA,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9
  .byte $E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E9,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6
  .byte $E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E6,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1

; the gardens: dens (column, row, horizontal) and rocks (column, row)
DEN_C:
  .byte $03,$09,$0B,$0E,$01,$0F,$09
  .byte $0B,$0D,$00,$09,$06,$02,$02
  .byte $0B,$0A,$03,$05,$0E,$03,$01
  .byte $01,$03,$0A,$06,$00,$0D,$0D
  .byte $08,$02,$0C,$0C,$04,$0F,$02
  .byte $02,$07,$0C,$00,$0D,$0D,$08
  .byte $03,$0D,$02,$0C,$0C,$0F,$0B
  .byte $02,$07,$02,$02,$0E,$0B,$0D
DEN_R:
  .byte $08,$08,$03,$08,$09,$04,$0A
  .byte $03,$09,$03,$0A,$09,$07,$09
  .byte $03,$09,$02,$0A,$05,$08,$0A
  .byte $03,$07,$08,$0A,$06,$06,$02
  .byte $09,$05,$09,$05,$09,$08,$02
  .byte $04,$08,$05,$06,$02,$09,$0A
  .byte $02,$07,$08,$0A,$04,$08,$07
  .byte $04,$09,$09,$07,$03,$09,$09
DEN_H:
  .byte $00,$01,$00,$00,$00,$00,$01
  .byte $00,$01,$00,$01,$00,$01,$01
  .byte $01,$01,$01,$01,$00,$01,$01
  .byte $01,$00,$01,$01,$00,$00,$01
  .byte $01,$01,$01,$00,$00,$00,$01
  .byte $00,$01,$00,$00,$01,$00,$01
  .byte $01,$00,$00,$01,$01,$00,$00
  .byte $00,$00,$01,$01,$01,$00,$00
RK_C0:
  .byte $02,$0C,$05,$01
  .byte $0D,$04,$00,$0F
  .byte $0F,$0B,$0A,$0F
  .byte $0E,$01,$0F,$04
  .byte $00,$0E,$0A,$05
  .byte $0C,$03,$05,$0F
  .byte $05,$04,$01,$0A
  .byte $00,$0A,$0E,$0C
RK_R0:
  .byte $01,$06,$01,$04
  .byte $04,$02,$06,$04
  .byte $07,$07,$01,$01
  .byte $04,$05,$08,$06
  .byte $05,$07,$01,$01
  .byte $07,$08,$01,$01
  .byte $03,$06,$06,$04
  .byte $02,$05,$07,$07

; big letters of the title
BIG_TOP:
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$00,$18,$18,$78,$78,$98,$98,$98,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $00,$18,$18,$18,$18,$18,$18,$1F,$00,$18,$18,$18,$18,$18,$18,$F8
BIG_BOT:
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00,$1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$F8,$18,$18,$18,$18,$18,$18,$00
TXT_BIG:
  .byte 3,7,200,201,202,203,204,205,206,207,32,32,208,209,202,203,204,205,206,207,0
  .byte 4,7,220,221,222,223,224,225,226,227,32,32,228,229,222,223,224,225,226,227,0
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
  .byte $1E,$06,$22,$06,$25,$06,$22,$06,$1E,$06,$25,$06,$2A,$0C,$29,$06,$27,$06,$25,$06,$23,$06,$22,$0C,$20,$0C,$22,$06,$23,$06,$25,$06
  .byte $27,$06,$29,$06,$2A,$06,$2C,$06,$29,$06,$2A,$18,$25,$06,$25,$06,$27,$06,$25,$06,$23,$0C,$20,$0C,$22,$06,$22,$06,$23,$06,$22,$06
  .byte $20,$0C,$1D,$0C,$1E,$06,$20,$06,$22,$06,$23,$06,$25,$06,$1D,$06,$20,$06,$1D,$06,$1E,$18,$FF
SG0_1:
  .byte $16,$18,$16,$18,$17,$18,$19,$18,$16,$18,$19,$18,$16,$18,$14,$18,$12,$18,$11,$18,$12,$18,$14,$18,$16,$18,$FF
SG0_2:
  .byte $06,$0C,$0D,$0C,$06,$0C,$0D,$0C,$0B,$0C,$06,$0C,$0D,$0C,$08,$0C,$06,$0C,$0D,$0C,$0B,$0C,$0D,$0C,$0D,$0C,$0D,$0C,$06,$18,$06,$0C
  .byte $0D,$0C,$0B,$0C,$06,$0C,$01,$0C,$0D,$0C,$0D,$0C,$01,$0C,$06,$18,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG1_0:
  .byte $25,$06,$2A,$06,$2E,$06,$31,$0C,$2E,$06,$2A,$06,$2C,$06,$29,$06,$25,$06,$2A,$18,$FF
SG1_1:
  .byte $22,$18,$23,$18,$22,$18,$FF
SG1_2:
  .byte $06,$0C,$0D,$0C,$0B,$0C,$0D,$0C,$06,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$04,$18,$FF
SG2_0:
  .byte $2A,$04,$2E,$04,$31,$04,$36,$0C,$35,$04,$36,$04,$38,$04,$3A,$18,$00,$04,$31,$04,$36,$18,$FF
SG2_1:
  .byte $22,$10,$25,$10,$2A,$18,$22,$0C,$25,$18,$FF
SG2_2:
  .byte $06,$10,$0D,$10,$06,$18,$0D,$0C,$06,$18,$FF
SG2_3:
  .byte $02,$04,$02,$04,$02,$04,$01,$0C,$03,$04,$03,$04,$03,$04,$01,$18,$03,$04,$03,$04,$04,$18,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$9F,$9F,$9F,$8E,$8E,$8E,$2A,$26,$22,$1F,$1D,$1B,$19,$17,$16,$15,$18,$18,$14,$14,$1E,$1E,$1E,$15,$12,$17,$14,$1A,$16,$1E,$19
  .byte $23,$1C,$2A,$20,$34,$26,$45,$2E,$7E,$38,$7E,$38,$7E,$38,$7E,$38,$2F,$2F,$2F,$28,$28,$28,$20,$20,$20,$18,$18,$18,$18,$18,$3C,$3C
  .byte $3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$68,$6D,$71,$76,$6E,$72,$77,$7C,$90,$96
  .byte $9D,$A3,$98,$9E,$A5,$AC,$C8,$D1,$D9,$E2,$D2,$DB,$E4,$EE,$15,$21,$2D,$3A,$24,$30,$3D,$4A,$81,$91,$A1,$B3,$45,$45,$34,$34,$45,$45
  .byte $34,$34,$45,$45,$34,$34,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$EF,$EF
  .byte $EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28
  .byte $28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00
WH_VOL:
  .byte $00,$06,$06,$05,$06,$06,$05,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$0B,$09,$0B,$09,$0A,$07,$04,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09
  .byte $08,$08,$07,$07,$06,$06,$05,$05,$08,$08,$08,$08,$08,$08,$08,$08,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0A,$08,$06,$04,$0D,$0C
  .byte $0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$09,$09,$09,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C
  .byte $0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09
  .byte $07,$06,$04,$03
WH_START:
  .byte $00,$01,$04,$07,$11,$18,$28,$30,$3E,$56,$7A,$86,$AE,$B1
WH_LEN:
  .byte $00,$03,$03,$0A,$07,$10,$08,$0E,$18,$24,$0C,$28,$03,$13
W_STEP1 = 1
W_STEP2 = 2
W_RAY = 3
W_FREEZE = 4
W_SHATTER = 5
W_WOBBLE = 6
W_VEG = 7
W_EXTRA = 8
W_DOWN = 9
W_RUN = 10
W_OVER = 11
W_KEY = 12
W_SIGN = 13

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$06,$04,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03
EX_NP:
  .byte $00,$03,$05,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D
EX_VC:
  .byte $00,$00,$00,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01
EX_TL:
  .byte $00,$00,$00,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D
EX_TH:
  .byte $00,$00,$00,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
EX_START:
  .byte $00,$01,$03
EX_LEN:
  .byte $00,$02,$0C
S_DIG = 1
S_THUD = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$66, <80,>80, $B1,0
  .byte 2, $E0,$66, <80,>80, $91,0
  .byte 1, $00,$43, <760,>760, <TILEP,>TILEP
  .byte 1, $00,$63, <760,>760, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$4E, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$6E, <80,>80, $B1,0
  .byte 2, $E0,$6E, <80,>80, $91,0
  .byte 1, $00,$4B, <760,>760, <TILEP,>TILEP
  .byte 1, $00,$6B, <760,>760, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$56, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$76, <80,>80, $B1,0
  .byte 2, $E0,$76, <80,>80, $91,0
  .byte 1, $00,$53, <760,>760, <TILEP,>TILEP
  .byte 1, $00,$73, <760,>760, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
