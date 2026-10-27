;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   TIMES_TABLES  -  TABELLINE (an original educational game)  ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites x2)  ;
;   Base: joust / moon cresta (VDP, NMI + trampoline $0FD0,    ;
;   AY engine, 4-track tune)                                   ;
;                                                              ;
;   - the times tables from 1 to 10: one question A X B = ?    ;
;     and four answers in a cross: push the joystick UP /      ;
;     DOWN / LEFT / RIGHT to choose one. Every game is 10      ;
;     questions                                                ;
;   - ALLENAMENTO (practice): one table or all of them, no     ;
;     time; button 2 = help (the repeated sum)                 ;
;   - SFIDA (challenge): a red 2-digit countdown like a        ;
;     basketball scoreboard (T_EASY / T_HARD seconds), points  ;
;     100 + 10 per second left, +200 every 5 right answers in  ;
;     a row, record in RAM                                     ;
;   - DUELLO: the same question for two, the first right       ;
;     answer takes the point; 1 player against the CPU         ;
;     (it presses joystick 2, AI_* constants) or 2 players     ;
;   - every wrong answer shows the right one and the           ;
;     repeated sum. What was learnt stays in RAM (FACT): the   ;
;     wrong facts come back more often, LA MIA TAVOLA shows    ;
;     them in colours                                          ;
;   - one monster per table: caught when 6 of its 10 facts     ;
;     were answered right, it evolves when all 10 were         ;
;     answered right and fast twice                            ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     title tune, right, wrong, countdown ticks, time up,      ;
;     3-2-1-VIA, series of 5, caught, evolution                ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- parameters ----------------
T_EASY      = 6        ; seconds for a question with 1, 2, 5 or 10 in it
T_HARD      = 7        ; seconds for the others (keep both >= 6: the CPU thinks up to 337 frames)
N_QUEST     = 10       ; questions in a game
CATCH_N     = 6        ; facts of a table at level 2 or more to catch its monster
LV_CATCH    = 2        ; level of a fact answered right once
LV_EVOLVE   = 4        ; level of a fact answered right and fast twice (all 10: evolution)
UP_FAST     = 2        ; level change: right and fast (half the time or more left / no help)
UP_SLOW     = 1        ;               right but slow / after the help
DOWN_WRONG  = $FC      ;               wrong or time up (-4)
BTN_MASK    = %00110000

; ---------------- zero page: game ----------------
MODE        = $30      ; 0 practice, 1 challenge, 2 duel against the CPU, 3 duel 2 players
PTABLE      = $31      ; practice: table 1-10 (0 = all)
CPU_ON      = $32      ; 1 = the CPU plays joystick 2
AILVL       = $33      ; CPU level 0 easy, 1 medium, 2 hard
QN          = $34      ; question 0-9
QA          = $35      ; the question A X B = C
QB          = $36
QC          = $37
QPOS        = $38      ; slot of the right answer (0 up, 1 down, 2 left, 3 right)
LASTPOS     = $39      ; slot of the right answer before, and how many times in a row
LASTCNT     = $3A
QSTATE      = $3B      ; 0 asking, 1 showing the result
QT          = $3C      ; frames of the result
SECS        = $3D      ; seconds left
SUBF        = $3E      ; frames to the next second
TOT         = $3F      ; seconds of this question
BARN        = $40      ; tiles of the time bar
BARF        = $41      ; frames to the next tile
BARSTEP     = $42
LOCK        = $43      ; bit 0 / 1: player 1 / 2 answered wrong (duel)
WHO         = $44      ; player who answered
RIGHT       = $46      ; right answers in this game
STREAK      = $47      ; right answers in a row
DSC         = $48      ; 2 bytes: duel points
HELPED      = $4A      ; 1 = help shown for this question
MENUSEL     = $4B
WAITBTN     = $4C      ; 1 = the result waits for the button
MASC        = $4D      ; monster of the question
JUMPT       = $4F      ; frames of the jump of the monster
BURST       = $50      ; frames of the stars
BSX         = $51      ; centre of the stars
BSY         = $52
SHOWEXP     = $53      ; 1 = the right answer blinks
OLDJ        = $54      ; 2 bytes: joysticks of the frame before
EDGE        = $56      ; 2 bytes: new presses
AI_T        = $58      ; 2 bytes: frames before the CPU answers
AI_ANS      = $5A      ; slot the CPU will choose
AI_HOLD     = $5B      ; frames the CPU keeps the direction
CURX        = $5C      ; cursor of the table
CURY        = $5D
SHAKE       = $5F      ; frames of the shake of the monster

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
FSET        = $6E      ; 2 bytes: tiles of a frame
BROW        = $70      ; cursor of the big glyphs
BCOL        = $71
TP          = $72      ; 2 bytes: texts
NH          = $74      ; a number split in hundreds, tens, ones and its digits
NTN         = $75
NO          = $76
NDIG        = $77
BL          = $78      ; length of the text buffer
FR_R        = $79      ; frame: row, column, width, height
FR_C        = $7A
FR_W        = $7B
FR_H        = $7C
TRIES       = $7D
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)

SCL         = $80      ; score (BCD): tens and units
SCM         = $81      ; thousands and hundreds
SCH         = $82      ; hundred thousands and ten thousands
HISC        = $83      ; 3 bytes BCD (low, middle, high)
PTS_L       = $86      ; points to add (BCD)
PTS_M       = $87
NSTARS      = $88
EVM         = $89      ; monster of the event
TMON        = $8A      ; 2 bytes: monsters of the title
QIDX        = $8C      ; fact of the question (a-1)*10 + b-1
NW          = $8D      ; wrong answers chosen
FORM        = $8E      ; form to show (event screens)
KEYS        = $8F      ; new presses of the frame (menus)
SATB        = $A0      ; bytes of the SAT to copy

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
OX         = $E0         ; sprite being added: X, Y (top left), pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4         ; next free byte of the SAT

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; noise playing per chip
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
CMD_START  = 2           ; the title tune

; ---------------- RAM ----------------
FACT       = $0200       ; 100 facts (a-1)*10 + b-1: bits 0-3 level, bit 7 seen
MON_ST     = $0270       ; 10 monsters: 0 not caught, 1 baby, 2 evolved
MON_OLD    = $0280       ; the same at the start of the game
USED       = $0290       ; facts asked in this game
PERM       = $02A0       ; practice of one table: the order of B
ANS        = $02B0       ; the 4 answers (slot order)
WRONG      = $02B4       ; the 3 wrong answers
CAND       = $02C0       ; candidates for the wrong answers (12)
BUF        = $0300       ; text buffer (40 bytes)
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- screen ----------------
SEG_ROW    = 2           ; the scoreboard: digits on rows 2-4, columns 24-27
SEG_COL    = 24
BAR_ROW    = 6
MASC_X     = 112         ; the monster between the four answers
MASC_Y     = 104

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
  STA VINT                     ; VDP interrupt off
  STA FRAME_CNT
  STA LAST_FRAME
  STA HISC
  STA HISC+1
  STA HISC+2
  STA MENUSEL
  STA PTABLE
  STA AILVL
  STA CPU_ON
  STA CURX
  STA CURY
  LDX #99                      ; nothing learnt yet (kept until the power goes off)
.rs_f:
  STZ FACT,X
  DEX
  BPL .rs_f
  LDX #9
.rs_m:
  STZ MON_ST,X
  DEX
  BPL .rs_m
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ---------------------------------------------------------------
; one frame: FRAME_BEGIN waits for the NMI and switches the VDP
; interrupt off (the VDP is free), reads the joysticks (the CPU
; writes joystick 2) and finds the new presses. FRAME_END closes
; the sprite list and switches the interrupt on again
; ---------------------------------------------------------------
FRAME_BEGIN:
  JSR VDP_INT_OFF
  JSR READ_JOY
  LDA CPU_ON
  BEQ .fb_e
  JSR CPU_AI
.fb_e:
  LDX #$01
.fb_l:
  LDA OLDJ,X
  EOR #$FF
  AND P_JOY,X
  STA EDGE,X
  LDA P_JOY,X
  STA OLDJ,X
  DEX
  BPL .fb_l
  JMP NEXT_RND

FRAME_END:
  JSR END_SAT
  JMP VDP_INT_ON

; new presses of both joysticks in A
EDGES:
  LDA EDGE
  ORA EDGE+1
  RTS

; the frame of the button press seeds the random numbers
SEED:
  LDA FRAME_CNT
  EOR RND
  BNE .sd_s
  LDA #$A5
.sd_s:
  STA RND
  RTS


; ===============================================================
;  TITLE: the menu
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  STZ CPU_ON
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  LDA #2                       ; TABELLINE in big letters
  STA BROW
  LDA #7
  STA BCOL
  LDX #$00
.ti_g:
  PHX
  LDA TITLE_G,X
  JSR BIG_CUR
  PLX
  INX
  CPX #TITLE_N
  BNE .ti_g
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #21
  LDY #16
  JSR NT_XY
  JSR PUT_HISC
  JSR DRAW_MENU_CUR
  JSR NEXT_RND                 ; two monsters beside the title
  AND #$07
  STA TMON
  CLC
  ADC #2
  STA TMON+1
  LDA #CMD_START
  STA SND_CMD
.ti_l:
  JSR FRAME_BEGIN
  JSR EDGES
  STA KEYS
  AND #$01                     ; up
  BEQ .ti_nu
  LDA MENUSEL
  BEQ .ti_nu
  DEC MENUSEL
  JSR DRAW_MENU_CUR
.ti_nu:
  LDA KEYS
  AND #$02                     ; down
  BEQ .ti_nd
  LDA MENUSEL
  CMP #5
  BEQ .ti_nd
  INC MENUSEL
  JSR DRAW_MENU_CUR
.ti_nd:
  STZ SPRI
  LDA #16
  STA OX
  LDA #4
  STA OY
  LDX TMON
  LDY MON_ST,X
  JSR ADD_MON
  LDA #208
  STA OX
  LDA #4
  STA OY
  LDX TMON+1
  LDY MON_ST,X
  JSR ADD_MON
  LDA KEYS
  AND #BTN_MASK
  BNE .ti_go
  JSR FRAME_END
  BRA .ti_l
.ti_go:
  JSR FRAME_END
  JSR SEED
  LDA #CMD_GAME
  STA SND_CMD
  LDA #W_SELECT
  LDX #2
  JSR SFX_WHISTLE
  LDA MENUSEL
  ASL A
  TAX
  JMP (MENU_JMP,X)

; the arrow of the menu
DRAW_MENU_CUR:
  LDA #W_MOVE
  LDX #2
  JSR SFX_WHISTLE
  LDY #$00
.dm_l:
  PHY
  LDX MENU_ROW,Y
  LDA #$20
  CPY MENUSEL
  BNE .dm_s
  LDA #$3E
.dm_s:
  PHA
  LDY #1
  JSR NT_XY
  PLA
  STA VDATA
  PLY
  INY
  CPY #6
  BNE .dm_l
  RTS


; ===============================================================
;  CHOICES BEFORE A GAME
; ===============================================================
GO_PRACTICE:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  LDA #<TXT_SELT
  STA TP
  LDA #>TXT_SELT
  STA TP+1
  JSR PRINT
  JSR DRAW_SELT
.gp_l:
  JSR FRAME_BEGIN
  JSR EDGES
  STA KEYS
  AND #$04                     ; left
  BEQ .gp_nl
  DEC PTABLE
  BPL .gp_d
  LDA #10
  STA PTABLE
  BRA .gp_d
.gp_nl:
  LDA KEYS
  AND #$08                     ; right
  BEQ .gp_nr
  INC PTABLE
  LDA PTABLE
  CMP #11
  BCC .gp_d
  STZ PTABLE
.gp_d:
  JSR DRAW_SELT
.gp_nr:
  STZ SPRI
  LDA PTABLE                   ; the monster of the table
  BEQ .gp_ns
  DEC A
  TAX
  LDA #MASC_X
  STA OX
  LDA #100
  STA OY
  LDY MON_ST,X
  JSR ADD_MON
.gp_ns:
  LDA KEYS
  AND #$10
  BNE .gp_go
  LDA KEYS
  AND #$20
  BNE .gp_back
  JSR FRAME_END
  BRA .gp_l
.gp_back:
  JMP TITLE
.gp_go:
  STZ MODE
  JMP START_GAME

; practice: the table chosen (big number or TUTTE), the name of its monster
DRAW_SELT:
  LDA #W_MOVE
  LDX #2
  JSR SFX_WHISTLE
  LDX #9
  JSR CLEAR_ROW
  LDX #10
  JSR CLEAR_ROW
  LDX #17
  JSR CLEAR_ROW
  LDA #<TXT_ARROWS
  STA TP
  LDA #>TXT_ARROWS
  STA TP+1
  JSR PRINT
  LDA PTABLE
  BNE .ds_n
  LDA #<TXT_ALL
  STA TP
  LDA #>TXT_ALL
  STA TP+1
  LDX #9
  JMP PRINT_C
.ds_n:
  JSR SPLIT_NUM
  LDA #9
  STA BROW
  LDA #16
  SEC
  SBC NDIG
  STA BCOL
  LDA PTABLE
  JSR BIG_NUM
  LDX PTABLE                   ; the name (??? if not caught)
  DEX
  JSR MON_NAME
  LDX #17
  JMP PRINT_C

; X = monster: TP = its name in the form it has (??? if not caught)
MON_NAME:
  LDA MON_ST,X
  BEQ .mn_q
  CMP #2
  BEQ .mn_2
  LDA MON_N1_LO,X
  STA TP
  LDA MON_N1_HI,X
  STA TP+1
  RTS
.mn_2:
  LDA MON_N2_LO,X
  STA TP
  LDA MON_N2_HI,X
  STA TP+1
  RTS
.mn_q:
  LDA #<TXT_QQQ
  STA TP
  LDA #>TXT_QQQ
  STA TP+1
  RTS

GO_SFIDA:
  LDA #1
  STA MODE
  JMP START_GAME

GO_DUEL2:
  LDA #3
  STA MODE
  JMP START_GAME

GO_DUELCPU:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  LDA #<TXT_SELA
  STA TP
  LDA #>TXT_SELA
  STA TP+1
  JSR PRINT
  JSR DRAW_SELA
.ga_l:
  JSR FRAME_BEGIN
  JSR EDGES
  STA KEYS
  AND #$04
  BEQ .ga_nl
  DEC AILVL
  BPL .ga_d
  LDA #2
  STA AILVL
  BRA .ga_d
.ga_nl:
  LDA KEYS
  AND #$08
  BEQ .ga_nr
  INC AILVL
  LDA AILVL
  CMP #3
  BCC .ga_d
  STZ AILVL
.ga_d:
  JSR DRAW_SELA
.ga_nr:
  STZ SPRI
  LDA KEYS
  AND #$10
  BNE .ga_go
  LDA KEYS
  AND #$20
  BNE .ga_back
  JSR FRAME_END
  BRA .ga_l
.ga_back:
  JMP TITLE
.ga_go:
  LDA #2
  STA MODE
  JMP START_GAME

DRAW_SELA:
  LDA #W_MOVE
  LDX #2
  JSR SFX_WHISTLE
  LDX #10
  JSR CLEAR_ROW
  LDA #<TXT_ARROWS2
  STA TP
  LDA #>TXT_ARROWS2
  STA TP+1
  JSR PRINT
  LDX AILVL
  LDA AI_NAME_LO,X
  STA TP
  LDA AI_NAME_HI,X
  STA TP+1
  LDX #10
  JMP PRINT_C


; ===============================================================
;  A GAME: 3-2-1-VIA, then 10 questions
; ===============================================================
START_GAME:
  LDX #$FF
  TXS
  LDA #CMD_GAME
  STA SND_CMD
  LDA #$00
  STA QN
  STA RIGHT
  STA STREAK
  STA SCL
  STA SCM
  STA SCH
  STA DSC
  STA DSC+1
  STA CPU_ON
  LDA #$FF
  STA LASTPOS
  LDX #9
.sg_m:
  LDA MON_ST,X
  STA MON_OLD,X
  LDA #$FF
  STA USED,X
  TXA                          ; practice of one table: B = 1-10 shuffled
  INC A
  STA PERM,X
  DEX
  BPL .sg_m
  LDX #9
.sg_sh:
  STX T6
  TXA
  INC A
  JSR RND_BELOW                ; j = 0..i
  TAY
  LDX T6
  LDA PERM,X
  PHA
  LDA PERM,Y
  STA PERM,X
  PLA
  STA PERM,Y
  DEX
  BNE .sg_sh
  JSR COUNTDOWN_321
  LDA MODE
  CMP #2
  BNE .sg_q
  LDA #1                       ; the CPU plays joystick 2
  STA CPU_ON
.sg_q:
  JSR NEW_QUESTION
  ; fall into GAME_LOOP

GAME_LOOP:
  JSR FRAME_BEGIN
  LDA QSTATE
  BNE .gl_res
  JSR ASK_TICK
  BRA .gl_spr
.gl_res:
  JSR RESULT_TICK
.gl_spr:
  JSR GAME_SPRITES
  JSR FRAME_END
  JMP GAME_LOOP

; A = n (1-16): random number 0..n-1 in A
RND_BELOW:
  STA T7
.rb_l:
  JSR NEXT_RND
  AND #$0F
  CMP T7
  BCS .rb_l
  RTS

; 3, 2, 1, VIA! in big glyphs
COUNTDOWN_321:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  LDX MODE
  LDA MODE_NAME_LO,X
  STA TP
  LDA MODE_NAME_HI,X
  STA TP+1
  LDX #4
  JSR PRINT_C
  LDA #3
.cd_l:
  PHA
  LDX #10
  LDY #15
  JSR DRAW_BIG
  LDA #W_BEEP
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_ON
  LDA #50
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  PLA
  DEC A
  BNE .cd_l
  LDA #10
  STA BROW
  LDA #12
  STA BCOL
  LDX #$00
.cd_v:
  PHX
  LDA VIA_G,X
  JSR BIG_CUR
  PLX
  INX
  CPX #4
  BNE .cd_v
  LDA #W_GO
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_ON
  LDA #40
  JSR WAIT_FRAMES
  JMP VDP_INT_OFF

; ---------------------------------------------------------------
; a new question: the fact, the answers, the screen (VDP free)
; ---------------------------------------------------------------
NEW_QUESTION:
  JSR PICK_FACT
  JSR MAKE_ANSWERS
  LDA #$00
  STA QSTATE
  STA LOCK
  STA HELPED
  STA SHOWEXP
  STA WAITBTN
  STA BURST
  STA JUMPT
  STA SHAKE
  LDX QA                       ; the monster of table A
  DEX
  STX MASC
  LDA #T_HARD
  JSR IS_EASY
  BCC .nq_t
  LDA #T_EASY
.nq_t:
  STA TOT
  STA SECS
  ASL A                        ; 30 tiles: one every TOT * 2 frames
  STA BARSTEP
  STA BARF
  LDA #60
  STA SUBF
  LDA #30
  STA BARN
  JSR AI_NEW
  ; ---- the screen
  JSR CLEAR_NT
  JSR DRAW_STATUS
  JSR BUF_CLR                  ; DOMANDA n DI 10
  LDA #<TXT_DOM
  STA TP
  LDA #>TXT_DOM
  STA TP+1
  JSR BUF_STR
  LDA QN
  INC A
  JSR BUF_NUM
  LDA #<TXT_DI10
  STA TP
  LDA #>TXT_DI10
  STA TP+1
  JSR BUF_STR
  LDX #1
  LDY #1
  JSR PRINT_BUF_AT
  LDA MODE
  BEQ .nq_p
  LDA #1                       ; the scoreboard with the countdown
  STA FR_R
  LDA #SEG_COL-1
  STA FR_C
  LDA #6
  STA FR_W
  LDA #5
  STA FR_H
  LDA #<FRAME_T
  STA FSET
  LDA #>FRAME_T
  STA FSET+1
  JSR DRAW_RECT
  LDA SECS
  JSR BIN2BCD
  JSR DRAW_SEG
  JSR DRAW_BAR
  BRA .nq_q
.nq_p:
  LDA #<TXT_HINTHELP
  STA TP
  LDA #>TXT_HINTHELP
  STA TP+1
  LDX #23
  JSR PRINT_C
.nq_q:
  LDA #2                       ; A X B = ?
  STA BROW
  STA BCOL
  LDA QA
  JSR BIG_NUM
  INC BCOL
  LDA #G_X
  JSR BIG_CUR
  INC BCOL
  LDA QB
  JSR BIG_NUM
  INC BCOL
  LDA #G_EQ
  JSR BIG_CUR
  INC BCOL
  LDA #G_Q
  JSR BIG_CUR
  LDA #3                       ; the four answers
.nq_b:
  PHA
  LDX #0
  JSR DRAW_BOX
  PLA
  PHA
  JSR DRAW_ANS
  PLA
  DEC A
  BPL .nq_b
  RTS

; carry set = the question has 1, 2, 5 or 10 in it
IS_EASY:
  PHA
  LDX QA
  LDA EASY_TAB,X
  BNE .ie_y
  LDX QB
  LDA EASY_TAB,X
  BNE .ie_y
  PLA
  CLC
  RTS
.ie_y:
  PLA
  SEC
  RTS

; row 0: what is being played, the points
DRAW_STATUS:
  LDX #0
  JSR CLEAR_ROW
  LDA MODE
  BNE .st_1
  JSR BUF_CLR                  ; ALLENAMENTO: TABELLINA DEL n / TUTTE
  LDA #<TXT_STP
  STA TP
  LDA #>TXT_STP
  STA TP+1
  JSR BUF_STR
  LDA PTABLE
  BEQ .st_all
  LDA #<TXT_STT
  STA TP
  LDA #>TXT_STT
  STA TP+1
  JSR BUF_STR
  LDA PTABLE
  JSR BUF_NUM
  BRA .st_pr
.st_all:
  LDA #<TXT_ALL
  STA TP
  LDA #>TXT_ALL
  STA TP+1
  JSR BUF_STR
.st_pr:
  LDX #0
  LDY #1
  JMP PRINT_BUF_AT
.st_1:
  CMP #1
  BNE .st_2
  LDA #<TXT_STS
  STA TP
  LDA #>TXT_STS
  STA TP+1
  JSR PRINT
  LDX #0
  LDY #7
  JSR NT_XY
  JSR PUT_SCORE
  LDX #0
  LDY #25
  JSR NT_XY
  JMP PUT_HISC
.st_2:
  LDA #<TXT_STD
  STA TP
  LDA #>TXT_STD
  STA TP+1
  JSR PRINT
  LDX MODE                     ; CPU or G2
  LDA P2_NAME_LO-2,X
  STA TP
  LDA P2_NAME_HI-2,X
  STA TP+1
  LDX #0
  LDY #24
  JSR PRINT_AT
  LDA DSC
  JSR BIN2BCD
  PHA
  LDX #0
  LDY #4
  JSR NT_XY
  PLA
  JSR PUT_2
  LDA DSC+1
  JSR BIN2BCD
  PHA
  LDX #0
  LDY #28
  JSR NT_XY
  PLA
  JMP PUT_2

PUT_SCORE:
  LDA SCH
  JSR PUT_2
  LDA SCM
  JSR PUT_2
  LDA SCL
  JMP PUT_2

PUT_HISC:
  LDA HISC+2
  JSR PUT_2
  LDA HISC+1
  JSR PUT_2
  LDA HISC
  JMP PUT_2


; ---------------------------------------------------------------
; asking: help, the answers of the players, the countdown
; ---------------------------------------------------------------
ASK_TICK:
  LDA MODE
  BNE .ak_p
  LDA EDGE                     ; practice: button 2 = help
  AND #$20
  BEQ .ak_p
  LDA HELPED
  BNE .ak_p
  INC HELPED
  JSR SHOW_SUM
  LDA #<TXT_CHOOSE
  STA TP
  LDA #>TXT_CHOOSE
  STA TP+1
  JSR MSG23
.ak_p:
  LDX #0
  JSR TRY_ANSWER
  LDA QSTATE
  BNE .ak_r
  LDA MODE
  CMP #2
  BCC .ak_t
  LDX #1
  JSR TRY_ANSWER
  LDA QSTATE
  BNE .ak_r
.ak_t:
  LDA MODE
  BEQ .ak_r
  DEC BARF                     ; the bar
  BNE .ak_s
  LDA BARSTEP
  STA BARF
  LDA BARN
  BEQ .ak_s
  DEC BARN
  JSR DRAW_BAR
.ak_s:
  DEC SUBF                     ; the seconds
  BNE .ak_r
  LDA #60
  STA SUBF
  DEC SECS
  LDA SECS
  JSR BIN2BCD
  JSR DRAW_SEG
  LDA SECS
  BEQ TIME_UP
  CMP #4
  BCS .ak_r
  LDA #W_TICK                  ; the last 3 seconds tick
  LDX #2
  JSR SFX_WHISTLE
.ak_r:
  RTS

TIME_UP:
  LDA #1
  STA QSTATE
  LDA #W_TIMEUP
  LDX #2
  JSR SFX_WHISTLE
  STZ STREAK
  LDA MODE
  CMP #3
  BEQ .tu_x
  LDA LOCK                     ; player 1 did not answer: as wrong
  AND #$01
  BNE .tu_x
  LDA #DOWN_WRONG
  JSR FACT_CHG
.tu_x:
  LDA #<TXT_TIMEUP
  STA TP
  LDA #>TXT_TIMEUP
  STA TP+1
  JSR SHOW_EXPL
  LDA #1
  STA SHOWEXP
  LDA #180
  STA QT
  RTS

; X = player: a new direction = his answer
TRY_ANSWER:
  LDA LOCK
  AND BITS,X
  BNE .ta_r
  LDA EDGE,X
  AND #$0F
  BEQ .ta_r
  LDY #$00                     ; first direction: 0 up, 1 down, 2 left, 3 right
.ta_f:
  LSR A
  BCS .ta_g
  INY
  BRA .ta_f
.ta_g:
  STX WHO
  CPY QPOS
  BNE .ta_w
  JMP ANS_RIGHT
.ta_w:
  JMP ANS_WRONG
.ta_r:
  RTS

; pan of the sound: the player in a duel, both sides otherwise
PAN:
  LDX #2
  LDA MODE
  CMP #2
  BCC .pn_r
  LDX WHO
.pn_r:
  RTS

; the answer of player WHO is right
ANS_RIGHT:
  LDA #1
  STA QSTATE
  LDA QPOS
  LDX #1
  JSR DRAW_BOX                 ; green
  JSR PAN
  LDA #W_OK
  JSR SFX_WHISTLE
  LDX QPOS                     ; stars from the box, the monster jumps
  LDA BOX_C,X
  CLC
  ADC #4
  ASL A
  ASL A
  ASL A
  STA BSX
  LDA BOX_R,X
  CLC
  ADC #2
  ASL A
  ASL A
  ASL A
  STA BSY
  LDA #24
  STA BURST
  STA JUMPT
  LDA MODE
  CMP #2
  BCS .ar_duel
  INC RIGHT
  INC STREAK
  JSR FACT_UP
  LDA MODE
  BEQ .ar_str
  LDA #$01                     ; challenge: 100 + 10 per second left
  STA PTS_M
  LDA SECS
  ASL A
  ASL A
  ASL A
  ASL A
  STA PTS_L
  JSR ADD_SCORE
.ar_str:
  LDA STREAK
  CMP #5
  BNE .ar_ok
  STZ STREAK
  LDA #W_STREAK
  LDX #2
  JSR SFX_WHISTLE
  LDA MODE
  BEQ .ar_s0
  LDA #$02                     ; challenge: +200
  STA PTS_M
  STZ PTS_L
  JSR ADD_SCORE
  LDA #<TXT_STREAK1
  STA TP
  LDA #>TXT_STREAK1
  STA TP+1
  BRA .ar_msg
.ar_s0:
  LDA #<TXT_STREAK0
  STA TP
  LDA #>TXT_STREAK0
  STA TP+1
  BRA .ar_msg
.ar_ok:
  LDA #<TXT_BRAVO
  STA TP
  LDA #>TXT_BRAVO
  STA TP+1
.ar_msg:
  JSR MSG23
  JSR DRAW_STATUS
  LDA #60
  STA QT
  RTS
.ar_duel:
  LDX WHO
  INC DSC,X
  LDA MODE                     ; against the CPU: what player 1 learnt
  CMP #2
  BNE .ar_d1
  CPX #0
  BNE .ar_d1
  JSR FACT_UP
.ar_d1:
  JSR DRAW_STATUS
  JSR BUF_CLR                  ; PUNTO PER <name>!
  LDA #<TXT_POINT
  STA TP
  LDA #>TXT_POINT
  STA TP+1
  JSR BUF_STR
  JSR BUF_WHO
  LDA #$21
  JSR BUF_CH
  LDX #23
  JSR PRINT_BUF_C
  LDA #90
  STA QT
  RTS

; the name of player WHO into the buffer
BUF_WHO:
  LDA WHO
  BEQ .bw_1
  LDX MODE
  LDA P2_LONG_LO-2,X
  STA TP
  LDA P2_LONG_HI-2,X
  STA TP+1
  JMP BUF_STR
.bw_1:
  LDA #<TXT_G1
  STA TP
  LDA #>TXT_G1
  STA TP+1
  JMP BUF_STR

; the right answer counts: more if fast (half the time or more left) or without help
FACT_UP:
  LDA MODE
  BNE .fu_t
  LDA #UP_FAST
  LDX HELPED
  BEQ .fu_c
  LDA #UP_SLOW
  BRA .fu_c
.fu_t:
  LDA SECS
  ASL A
  CMP TOT
  LDA #UP_FAST
  BCS .fu_c
  LDA #UP_SLOW
.fu_c:
  JMP FACT_CHG

; Y = slot: the answer of player WHO is wrong
ANS_WRONG:
  PHY
  JSR PAN
  LDA #W_BAD
  JSR SFX_WHISTLE
  PLY
  LDA MODE
  CMP #2
  BCS .aw_duel
  LDA #1
  STA QSTATE
  TYA
  LDX #2
  JSR DRAW_BOX                 ; red
  LDA #20
  STA SHAKE
  STZ STREAK
  LDA #DOWN_WRONG
  JSR FACT_CHG
  LDA #<TXT_WRONG
  STA TP
  LDA #>TXT_WRONG
  STA TP+1
  JSR SHOW_EXPL
  LDA #1
  STA SHOWEXP
  LDA MODE
  BNE .aw_ch
  STA QT                       ; practice: wait for the button
  INC WAITBTN
  LDA #<TXT_PRESS2
  STA TP
  LDA #>TXT_PRESS2
  STA TP+1
  LDX #6
  JMP PRINT_C
.aw_ch:
  LDA #180
  STA QT
  RTS
.aw_duel:
  LDX WHO
  LDA LOCK
  ORA BITS,X
  STA LOCK
  LDA #20
  STA SHAKE
  LDA MODE
  CMP #2
  BNE .aw_d1
  CPX #0
  BNE .aw_d1
  LDA #DOWN_WRONG
  JSR FACT_CHG
.aw_d1:
  LDA LOCK
  CMP #3
  BEQ .aw_none
  JSR BUF_CLR                  ; <name> SBAGLIA!
  JSR BUF_WHO
  LDA #<TXT_MISS
  STA TP
  LDA #>TXT_MISS
  STA TP+1
  JSR BUF_STR
  LDX #23
  JMP PRINT_BUF_C
.aw_none:
  LDA #1                       ; both wrong: nobody takes the point
  STA QSTATE
  LDA #<TXT_NOONE
  STA TP
  LDA #>TXT_NOONE
  STA TP+1
  JSR SHOW_EXPL
  LDA #1
  STA SHOWEXP
  LDA #180
  STA QT
  RTS

; ---------------------------------------------------------------
; the result: the right answer blinks after a mistake, then the
; next question (practice: after a mistake it waits the button)
; ---------------------------------------------------------------
RESULT_TICK:
  LDA SHOWEXP
  BEQ .rt_w
  LDA FRAME_CNT
  AND #$07
  BNE .rt_w
  LDA FRAME_CNT
  LSR A
  LSR A
  LSR A
  AND #$01                     ; blue / green
  TAX
  LDA QPOS
  JSR DRAW_BOX
.rt_w:
  LDA WAITBTN
  BEQ .rt_t
  LDA EDGE
  AND #BTN_MASK
  BNE NEXT_Q
  RTS
.rt_t:
  DEC QT
  BEQ NEXT_Q
  LDA SHOWEXP                  ; after a mistake the button skips the wait
  BEQ .rt_r
  LDA QT
  CMP #140
  BCS .rt_r
  LDA EDGE
  AND #BTN_MASK
  BNE NEXT_Q
.rt_r:
  RTS

NEXT_Q:
  INC QN
  LDA QN
  CMP #N_QUEST
  BCC .nx_q
  JMP GAME_END
.nx_q:
  JMP NEW_QUESTION

; the stars of a right answer and the monster
GAME_SPRITES:
  STZ SPRI
  LDA BURST
  BEQ .gs_m
  DEC BURST
  LDA #24
  SEC
  SBC BURST
  ASL A
  STA T5                       ; distance from the centre
  LDX #3
.gs_s:
  LDA BSX
  SEC
  SBC #5
  LDY STAR_DX,X
  BMI .gs_xl
  CLC
  ADC T5
  BRA .gs_x
.gs_xl:
  SEC
  SBC T5
.gs_x:
  STA OX
  LDA BSY
  SEC
  SBC #5
  LDY STAR_DY,X
  BMI .gs_yu
  CLC
  ADC T5
  BRA .gs_y
.gs_yu:
  SEC
  SBC T5
.gs_y:
  CMP #184                     ; off the screen (and never Y = $D0, the end of the list)
  BCS .gs_n
  STA OY
  LDA #PT_STAR
  STA ON
  LDA #$0B
  STA OC
  PHX
  JSR ADD_SPR
  PLX
.gs_n:
  DEX
  BPL .gs_s
.gs_m:
  LDA #MASC_X
  LDY SHAKE
  BEQ .gs_mx
  DEC SHAKE
  LDA FRAME_CNT
  AND #$02
  BEQ .gs_sl
  LDA #MASC_X+2
  BRA .gs_mx
.gs_sl:
  LDA #MASC_X-2
.gs_mx:
  STA OX
  LDA #MASC_Y
  LDX JUMPT
  BEQ .gs_my
  DEC JUMPT
  SEC
  SBC JUMP_Y-1,X
.gs_my:
  STA OY
  LDX MASC
  LDY MON_ST,X
  JMP ADD_MON


; a new record: copied and shown
CHECK_REC:
  LDA SCH
  CMP HISC+2
  BCC .cr_r
  BNE .cr_new
  LDA SCM
  CMP HISC+1
  BCC .cr_r
  BNE .cr_new
  LDA SCL
  CMP HISC
  BCC .cr_r
  BEQ .cr_r
.cr_new:
  LDA SCL
  STA HISC
  LDA SCM
  STA HISC+1
  LDA SCH
  STA HISC+2
  LDA #<TXT_NEWREC
  STA TP
  LDA #>TXT_NEWREC
  STA TP+1
  LDX #18
  JSR PRINT_C
  LDA #W_STREAK
  LDX #2
  JSR SFX_WHISTLE
.cr_r:
  RTS

; ===============================================================
;  END OF THE GAME: the result, then the monsters caught
; ===============================================================
GAME_END:
  LDX #$FF
  TXS
  STZ CPU_ON
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  STZ NSTARS
  LDA MODE
  CMP #2
  BCC .ge_1
  JMP .ge_duel
.ge_1:
  LDA #<TXT_END1
  STA TP
  LDA #>TXT_END1
  STA TP+1
  JSR PRINT
  LDA RIGHT                    ; big number of right answers
  JSR SPLIT_NUM
  LDA #7
  STA BROW
  LDA #16
  SEC
  SBC NDIG
  STA BCOL
  LDA RIGHT
  JSR BIG_NUM
  LDA RIGHT                    ; stars: 3 = 10, 2 = 8-9, 1 = 6-7
  LDX #3
  CMP #10
  BEQ .ge_st
  DEX
  CMP #8
  BCS .ge_st
  DEX
  CMP #6
  BCS .ge_st
  DEX
.ge_st:
  STX NSTARS
  LDA #W_CATCH
  CPX #2
  BCS .ge_snd
  LDA #W_OK
.ge_snd:
  LDX #2
  JSR SFX_WHISTLE
  LDA MODE
  BEQ .ge_jw
  LDA RIGHT                    ; challenge: 10 out of 10 = +500
  CMP #10
  BNE .ge_pt
  LDA #$05
  STA PTS_M
  STZ PTS_L
  JSR ADD_SCORE
  LDA #<TXT_PERFECT
  STA TP
  LDA #>TXT_PERFECT
  STA TP+1
  LDX #14
  JSR PRINT_C
.ge_pt:
  LDA #<TXT_PTS                ; points and record
  STA TP
  LDA #>TXT_PTS
  STA TP+1
  JSR PRINT
  LDX #16
  LDY #16
  JSR NT_XY
  JSR PUT_SCORE
  JSR CHECK_REC
.ge_jw:
  JMP .ge_wait
.ge_duel:
  LDA #<TXT_END2
  STA TP
  LDA #>TXT_END2
  STA TP+1
  JSR PRINT
  LDX MODE
  LDA P2_NAME_LO-2,X
  STA TP
  LDA P2_NAME_HI-2,X
  STA TP+1
  LDX #6
  LDY #21
  JSR PRINT_AT
  LDA #8                       ; the points in big digits
  STA BROW
  LDA #8
  STA BCOL
  LDA DSC
  JSR BIG_NUM
  LDA #21
  STA BCOL
  LDA DSC+1
  JSR BIG_NUM
  JSR BUF_CLR                  ; VINCE <name>! / PAREGGIO!
  LDA DSC
  CMP DSC+1
  BEQ .ge_draw
  LDX #0
  BCS .ge_w
  INX
.ge_w:
  STX WHO
  LDA #<TXT_WINS
  STA TP
  LDA #>TXT_WINS
  STA TP+1
  JSR BUF_STR
  JSR BUF_WHO
  LDA #$21
  JSR BUF_CH
  BRA .ge_dp
.ge_draw:
  LDA #<TXT_DRAW
  STA TP
  LDA #>TXT_DRAW
  STA TP+1
  JSR BUF_STR
.ge_dp:
  LDX #12
  JSR PRINT_BUF_C
  LDA #W_CATCH
  LDX #2
  JSR SFX_WHISTLE
.ge_wait:
  LDA #<TXT_PRESS
  STA TP
  LDA #>TXT_PRESS
  STA TP+1
  LDX #22
  JSR PRINT_C
  LDA #60
  STA QT
.ge_l:
  JSR FRAME_BEGIN
  STZ SPRI
  LDX #0                       ; the stars: gold or grey
.ge_s:
  CPX #3
  BEQ .ge_sd
  LDA STAR_X,X
  STA OX
  LDA #92
  STA OY
  LDA #PT_STAR
  STA ON
  LDA #$0B
  CPX NSTARS
  BCC .ge_c
  LDA #$0E
.ge_c:
  STA OC
  LDA MODE
  CMP #2
  BCS .ge_sd
  PHX
  JSR ADD_SPR
  PLX
  INX
  BRA .ge_s
.ge_sd:
  LDA QT
  BEQ .ge_b
  DEC QT
  BRA .ge_n
.ge_b:
  JSR EDGES
  AND #BTN_MASK
  BNE .ge_x
.ge_n:
  JSR FRAME_END
  BRA .ge_l
.ge_x:
  JSR FRAME_END
  ; fall into MONSTER_EVENTS

; ---------------------------------------------------------------
; the monsters caught or evolved in this game, one screen each
; ---------------------------------------------------------------
MONSTER_EVENTS:
  JSR UPDATE_MONSTERS
  STZ EVM
.me_l:
  LDX EVM
  LDA MON_OLD,X
  BNE .me_ev
  LDA MON_ST,X
  BEQ .me_n
  LDA #1                       ; caught
  STA FORM
  JSR EVENT_SCREEN
  LDX EVM
  LDA #1
  STA MON_OLD,X
.me_ev:
  LDA MON_OLD,X
  CMP MON_ST,X
  BEQ .me_n
  LDA #2                       ; evolved
  STA FORM
  JSR EVENT_SCREEN
.me_n:
  INC EVM
  LDA EVM
  CMP #10
  BNE .me_l
  JMP TITLE

; FORM 1: HAI CATTURATO <baby>!   FORM 2: <baby> SI EVOLVE! / ORA E' <evolved>!
EVENT_SCREEN:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  JSR BUF_CLR
  LDX EVM
  LDA FORM
  CMP #2
  BEQ .es_e
  LDA #<TXT_CATCH
  STA TP
  LDA #>TXT_CATCH
  STA TP+1
  LDX #4
  JSR PRINT_C
  LDX EVM
  LDA MON_N1_LO,X
  STA TP
  LDA MON_N1_HI,X
  STA TP+1
  JSR BUF_STR
  LDA #$21
  JSR BUF_CH
  LDX #6
  JSR PRINT_BUF_C
  LDA #W_CATCH
  BRA .es_go
.es_e:
  LDA MON_N1_LO,X
  STA TP
  LDA MON_N1_HI,X
  STA TP+1
  JSR BUF_STR
  LDA #<TXT_EVOLVE
  STA TP
  LDA #>TXT_EVOLVE
  STA TP+1
  JSR BUF_STR
  LDX #4
  JSR PRINT_BUF_C
  LDA #W_EVOLVE
.es_go:
  LDX #2
  JSR SFX_WHISTLE
  JSR BUF_CLR                  ; TABELLINA DEL n
  LDA #<TXT_STT
  STA TP
  LDA #>TXT_STT
  STA TP+1
  JSR BUF_STR
  LDA EVM
  INC A
  JSR BUF_NUM
  LDX #18
  JSR PRINT_BUF_C
  LDA #120
  STA QT
.es_l:
  JSR FRAME_BEGIN
  LDY FORM
  CPY #2
  BNE .es_draw
  LDA QT                       ; evolution: the two forms alternate, faster at the end
  CMP #20
  BCC .es_late
  LDY #1
  CMP #60
  BCS .es_slow
  AND #$02
  BRA .es_t
.es_slow:
  AND #$08
.es_t:
  BEQ .es_draw
  LDY #2
  BRA .es_draw
.es_late:
  LDY #2
  CMP #19                      ; the new name, once
  BNE .es_draw
  JSR BUF_CLR
  LDA #<TXT_NOW
  STA TP
  LDA #>TXT_NOW
  STA TP+1
  JSR BUF_STR
  LDX EVM
  LDA MON_N2_LO,X
  STA TP
  LDA MON_N2_HI,X
  STA TP+1
  JSR BUF_STR
  LDA #$21
  JSR BUF_CH
  LDX #6
  JSR PRINT_BUF_C
  LDY #2
.es_draw:
  STZ SPRI
  LDA #MASC_X
  STA OX
  LDA #72
  STA OY
  LDX EVM
  JSR ADD_MON
  LDA QT
  BEQ .es_b
  DEC QT
  BNE .es_n
  LDA #<TXT_PRESS              ; then the button
  STA TP
  LDA #>TXT_PRESS
  STA TP+1
  LDX #22
  JSR PRINT_C
  BRA .es_n
.es_b:
  JSR EDGES
  AND #BTN_MASK
  BNE .es_x
.es_n:
  JSR FRAME_END
  JMP .es_l
.es_x:
  JMP FRAME_END


; ===============================================================
;  LA MIA TAVOLA: the 10 x 10 facts in colours
; ===============================================================
GO_TAVOLA:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  LDA #<TXT_TAV
  STA TP
  LDA #>TXT_TAV
  STA TP+1
  JSR PRINT
  LDY #0                       ; the numbers of the columns (row 1) and of the rows
.tv_h:
  PHY
  TYA
  INC A
  JSR BIN2BCD
  STA T4
  PLY
  PHY
  LDX #1
  TYA
  ASL A
  CLC
  ADC #6
  TAY
  JSR NT_XY
  LDA T4
  JSR PUT_NUM2
  PLY
  PHY
  TYA
  ASL A
  CLC
  ADC #2
  TAX
  LDY #3
  JSR NT_XY
  LDA T4
  CMP #$10
  BCS .tv_2
  LDA #$20
  STA VDATA
.tv_2:
  LDA T4
  JSR PUT_NUM2
  PLY
  INY
  CPY #10
  BNE .tv_h
  LDX #0                       ; the cells
.tv_r:
  STX T2
  TXA
  ASL A
  CLC
  ADC #2
  TAX
  LDY #6
  JSR NT_XY
  LDX T2
  LDY TEN,X
  LDA #10
  STA T3
.tv_c:
  LDA FACT,Y
  JSR CELL_TILE
  STA VDATA
  LDA #$00
  STA VDATA
  INY
  DEC T3
  BNE .tv_c
  LDX T2
  INX
  CPX #10
  BNE .tv_r
  JSR TAV_INFO
.tv_l:
  JSR FRAME_BEGIN
  JSR EDGES
  STA KEYS
  LDA KEYS
  AND #$0F
  BEQ .tv_nm
  LSR A                        ; up
  BCC .tv_d
  DEC CURY
  BPL .tv_d
  LDA #9
  STA CURY
.tv_d:
  LDA KEYS
  AND #$02
  BEQ .tv_lf
  INC CURY
  LDA CURY
  CMP #10
  BCC .tv_lf
  STZ CURY
.tv_lf:
  LDA KEYS
  AND #$04
  BEQ .tv_rt
  DEC CURX
  BPL .tv_rt
  LDA #9
  STA CURX
.tv_rt:
  LDA KEYS
  AND #$08
  BEQ .tv_i
  INC CURX
  LDA CURX
  CMP #10
  BCC .tv_i
  STZ CURX
.tv_i:
  JSR TAV_INFO
.tv_nm:
  STZ SPRI                     ; the cursor around the cell
  LDA CURX
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #46
  STA OX
  LDA CURY
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #14
  STA OY
  LDA #PT_CUR
  STA ON
  LDA #$0F
  STA OC
  JSR ADD_SPR
  LDA KEYS
  AND #$10
  BNE .tv_go
  LDA KEYS
  AND #$20
  BNE .tv_back
  JSR FRAME_END
  JMP .tv_l
.tv_back:
  JMP TITLE
.tv_go:
  LDA CURY                     ; practice of the table of the row
  INC A
  STA PTABLE
  STZ MODE
  JMP START_GAME

; A = fact: its tile (grey never asked, red, yellow, green)
CELL_TILE:
  BMI .ct_s
  LDA #T_CELL0
  RTS
.ct_s:
  AND #$0F
  CMP #LV_EVOLVE
  BCS .ct_g
  CMP #LV_CATCH
  BCS .ct_y
  LDA #T_CELL1
  RTS
.ct_y:
  LDA #T_CELL2
  RTS
.ct_g:
  LDA #T_CELL3
  RTS

; A = BCD 1-10: one or two digits where the VDP points
PUT_NUM2:
  CMP #$10
  BCC .p1
  JMP PUT_2
.p1:
  ORA #$30
  STA VDATA
  RTS

; row 23: the fact under the cursor
TAV_INFO:
  LDA #W_MOVE
  LDX #2
  JSR SFX_WHISTLE
  LDA CURY
  INC A
  STA QA
  LDA CURX
  INC A
  STA QB
  LDA #0
  LDX QB
.ti_m:
  CLC
  ADC QA
  DEX
  BNE .ti_m
  STA QC
  JSR BUF_CLR
  JSR BUF_FACT
  LDX #23
  JMP PRINT_BUF_C


; ===============================================================
;  I MIEI MOSTRI: the ten monsters
; ===============================================================
GO_MOSTRI:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR CLEAR_NT
  LDA #<TXT_MON
  STA TP
  LDA #>TXT_MON
  STA TP+1
  JSR PRINT
  LDX #0
.mo_t:
  PHX
  JSR MON_NAME                 ; the name
  PLX
  PHX
  LDY ML_COL,X
  LDA ML_ROW,X
  TAX
  JSR PRINT_AT
  PLX
  PHX
  JSR BUF_CLR                  ; TAB n
  LDA #<TXT_TAB
  STA TP
  LDA #>TXT_TAB
  STA TP+1
  JSR BUF_STR
  PLX
  PHX
  TXA
  INC A
  JSR BUF_NUM
  PLX
  PHX
  LDY ML_COL,X
  LDA ML_ROW,X
  INC A
  TAX
  JSR PRINT_BUF_AT
  PLX
  INX
  CPX #10
  BNE .mo_t
.mo_l:
  JSR FRAME_BEGIN
  STZ SPRI
  LDX #0
.mo_s:
  LDA ML_X,X
  STA OX
  LDA ML_Y,X
  STA OY
  PHX
  LDY MON_ST,X
  JSR ADD_MON
  PLX
  INX
  CPX #10
  BNE .mo_s
  JSR EDGES
  AND #BTN_MASK
  BNE .mo_x
  JSR FRAME_END
  BRA .mo_l
.mo_x:
  JSR FRAME_END
  JMP TITLE

; ===============================================================
;  QUESTIONS: the fact, the wrong answers, what was learnt
; ===============================================================
; QA, QB, QC of question QN. Practice of one table: A = the table,
; B = the next of PERM. Otherwise a fact not asked yet in this game
; (nor its mirror); x1 facts and the ones already known come less often
PICK_FACT:
  LDA MODE
  BNE .pf_any
  LDA PTABLE
  BEQ .pf_any
  STA QA
  LDX QN
  LDA PERM,X
  STA QB
  BRA .pf_prod
.pf_any:
  LDA #200
  STA TRIES
.pf_try:
  JSR RND100
  STA QIDX
  LDX #$00                     ; A = idx / 10 + 1, B = idx % 10 + 1
.pf_d:
  CMP #10
  BCC .pf_dd
  SBC #10
  INX
  BRA .pf_d
.pf_dd:
  INC A
  STA QB
  INX
  STX QA
  DEC TRIES
  BEQ .pf_take
  JSR WAS_USED
  BCS .pf_try
  LDA QA
  CMP #1
  BEQ .pf_triv
  LDA QB
  CMP #1
  BNE .pf_known
.pf_triv:
  JSR NEXT_RND                 ; x1: 1 time in 4
  CMP #64
  BCS .pf_try
.pf_known:
  LDX QIDX
  LDA FACT,X
  AND #$0F
  CMP #LV_EVOLVE
  BCC .pf_take
  JSR NEXT_RND                 ; known: 1 time in 2
  BMI .pf_try
.pf_take:
  LDX QN
  LDA QIDX
  STA USED,X
.pf_prod:
  LDA #$00
  LDX QB
.pf_m:
  CLC
  ADC QA
  DEX
  BNE .pf_m
  STA QC
  RTS

; random number 0-99 in A
RND100:
  JSR NEXT_RND
  AND #$7F
  CMP #100
  BCS RND100
  RTS

; carry set = QIDX or its mirror (B x A) was already asked in this game
WAS_USED:
  LDY QB
  LDA TEN-1,Y
  CLC
  ADC QA
  SEC
  SBC #1
  STA T5
  LDX QN
  BEQ .wu_no
.wu_l:
  DEX
  LDA USED,X
  CMP QIDX
  BEQ .wu_yes
  CMP T5
  BEQ .wu_yes
  CPX #0
  BNE .wu_l
.wu_no:
  CLC
  RTS
.wu_yes:
  SEC
  RTS

; ---------------------------------------------------------------
; the 4 answers: the right one in slot QPOS (never 3 times in a row
; the same slot) and 3 wrong ones, the mistakes a child makes:
; the next / previous fact of the table, A + B, the digits swapped,
; +-1, +-2, +-10. All different, from 1 to 100
; ---------------------------------------------------------------
MAKE_ANSWERS:
  LDA QC
  SEC
  SBC QA
  STA CAND                     ; A x (B-1)
  LDA QC
  CLC
  ADC QA
  STA CAND+1                   ; A x (B+1)
  LDA QC
  SEC
  SBC QB
  STA CAND+2                   ; (A-1) x B
  LDA QC
  CLC
  ADC QB
  STA CAND+3                   ; (A+1) x B
  LDA QA
  CLC
  ADC QB
  STA CAND+4                   ; A + B
  STZ CAND+5                   ; the digits swapped (two different digits, no 0)
  LDA QC
  JSR SPLIT_NUM
  LDA NH
  BNE .ma_ns
  LDA NO
  BEQ .ma_ns
  CMP NTN
  BEQ .ma_ns
  LDA NTN
  BEQ .ma_ns
  LDX NO
  LDA TEN,X
  CLC
  ADC NTN
  STA CAND+5
.ma_ns:
  LDA QC
  INC A
  STA CAND+6
  LDA QC
  DEC A
  STA CAND+7
  LDA QC
  CLC
  ADC #10
  STA CAND+8
  LDA QC
  SEC
  SBC #10
  STA CAND+9
  LDA QC
  CLC
  ADC #2
  STA CAND+10
  LDA QC
  SEC
  SBC #2
  STA CAND+11
  LDX #11                      ; not valid -> 0
.ma_v:
  LDA CAND,X
  BEQ .ma_vn
  CMP #101
  BCS .ma_bad
  CMP QC
  BNE .ma_vn
.ma_bad:
  STZ CAND,X
.ma_vn:
  DEX
  BPL .ma_v
  STZ NW
  LDA #80
  STA TRIES
.ma_pk:
  DEC TRIES
  BEQ .ma_fill
  JSR NEXT_RND
  CMP #160                     ; mostly the near facts of the table
  BCS .ma_far
  AND #$03
  BRA .ma_c
.ma_far:
  AND #$07
  CLC
  ADC #4
.ma_c:
  TAX
  LDA CAND,X
  BEQ .ma_pk
  JSR ADD_WRONG
  LDA NW
  CMP #3
  BNE .ma_pk
  BRA .ma_place
.ma_fill:                      ; (never seen) the first numbers that are left
  STZ T5
.ma_f:
  INC T5
  LDA T5
  CMP QC
  BEQ .ma_f
  JSR ADD_WRONG
  LDA NW
  CMP #3
  BNE .ma_f
.ma_place:
  JSR NEXT_RND
  AND #$03
  CMP LASTPOS
  BNE .ma_new
  LDX LASTCNT
  CPX #2
  BCS .ma_place
  INC LASTCNT
  BRA .ma_set
.ma_new:
  STA LASTPOS
  LDX #1
  STX LASTCNT
.ma_set:
  STA QPOS
  LDY #$00
  LDX #$00
.ma_fl:
  CPX QPOS
  BNE .ma_w
  LDA QC
  BRA .ma_st
.ma_w:
  LDA WRONG,Y
  INY
.ma_st:
  STA ANS,X
  INX
  CPX #4
  BNE .ma_fl
  RTS

; A = a wrong answer: added if it is not there yet
ADD_WRONG:
  LDX NW
  BEQ .aw_add
.aw_c:
  DEX
  CMP WRONG,X
  BEQ .aw_r
  CPX #0
  BNE .aw_c
.aw_add:
  LDX NW
  STA WRONG,X
  INC NW
.aw_r:
  RTS

; ---------------------------------------------------------------
; A = change of level (+2, +1 or -4): to A x B and B x A
; ---------------------------------------------------------------
FACT_CHG:
  STA T6
  LDY QA
  LDA TEN-1,Y
  CLC
  ADC QB
  TAX
  DEX
  STX T7
  JSR FACT_ONE
  LDY QB
  LDA TEN-1,Y
  CLC
  ADC QA
  TAX
  DEX
  CPX T7
  BEQ .fc_r
  JMP FACT_ONE
.fc_r:
  RTS

; X = fact, T6 = change: level 0-15, bit 7 = seen
FACT_ONE:
  LDA FACT,X
  AND #$0F
  CLC
  ADC T6
  BMI .fo_z
  CMP #16
  BCC .fo_s
  LDA #15
  BRA .fo_s
.fo_z:
  LDA #$00
.fo_s:
  ORA #$80
  STA FACT,X
  RTS

; the monsters from what was learnt: caught with CATCH_N facts of the
; table at LV_CATCH, evolved with all 10 at LV_EVOLVE (never back)
UPDATE_MONSTERS:
  LDX #$00
.um_t:
  STZ T0
  STZ T1
  LDY TEN,X
  LDA #10
  STA T2
.um_f:
  LDA FACT,Y
  AND #$0F
  CMP #LV_CATCH
  BCC .um_n
  INC T0
  CMP #LV_EVOLVE
  BCC .um_n
  INC T1
.um_n:
  INY
  DEC T2
  BNE .um_f
  LDA #$00
  LDY T0
  CPY #CATCH_N
  BCC .um_s
  LDA #1
  LDY T1
  CPY #10
  BCC .um_s
  LDA #2
.um_s:
  CMP MON_ST,X
  BCC .um_k
  STA MON_ST,X
.um_k:
  INX
  CPX #10
  BNE .um_t
  RTS

ADD_SCORE:
  SED
  CLC
  LDA SCL
  ADC PTS_L
  STA SCL
  LDA SCM
  ADC PTS_M
  STA SCM
  LDA SCH
  ADC #$00
  STA SCH
  CLD
  RTS

; ---------------------------------------------------------------
; the CPU of the duel: it thinks AI_TMIN + random + AI_HARDT (not
; easy facts) frames, then pushes joystick 2 to the answer chosen:
; the right one with probability AI_RIGHT / 256
; ---------------------------------------------------------------
AI_NEW:
  LDA MODE
  CMP #2
  BNE .an_r
  LDX AILVL
  JSR NEXT_RND
  AND AI_MASK,X
  CLC
  ADC AI_TMIN,X
  STA AI_T
  LDA #$00
  ADC #$00
  STA AI_T+1
  JSR IS_EASY
  BCS .an_e
  LDX AILVL
  LDA AI_T
  CLC
  ADC AI_HARDT,X
  STA AI_T
  BCC .an_e
  INC AI_T+1
.an_e:
  LDX AILVL
  JSR NEXT_RND
  CMP AI_RIGHT,X
  BCS .an_w
  LDA QPOS
  BRA .an_s
.an_w:
  JSR NEXT_RND
  AND #$03
  CMP QPOS
  BEQ .an_w
.an_s:
  STA AI_ANS
  STZ AI_HOLD
.an_r:
  RTS

; after READ_JOY: joystick 2 = what the CPU pushes
CPU_AI:
  STZ P_JOY+1
  LDA QSTATE
  BNE .ca_r
  LDA LOCK
  AND #$02
  BNE .ca_r
  LDA AI_HOLD
  BEQ .ca_th
  DEC AI_HOLD
  BRA .ca_p
.ca_th:
  LDA AI_T
  ORA AI_T+1
  BEQ .ca_r
  LDA AI_T
  BNE .ca_d
  DEC AI_T+1
.ca_d:
  DEC AI_T
  LDA AI_T
  ORA AI_T+1
  BNE .ca_r
  LDA #2
  STA AI_HOLD
.ca_p:
  LDX AI_ANS
  LDA SLOT_BIT,X
  STA P_JOY+1
.ca_r:
  RTS

; ---------------------------------------------------------------
; the explanation: row 22 the repeated sum (the bigger factor added
; the smaller number of times), row 23 TP + "A X B = C"
; ---------------------------------------------------------------
SHOW_EXPL:
  JSR BUF_CLR
  JSR BUF_STR
  LDA #$20
  JSR BUF_CH
  JSR BUF_FACT
  LDX #23
  JSR PRINT_BUF_C
  ; fall into SHOW_SUM

SHOW_SUM:
  JSR BUF_CLR
  LDA QA
  LDX QB
  CMP QB
  BCS .ss_o
  LDA QB
  LDX QA
.ss_o:
  STA T6
  STX T7
.ss_l:
  LDA T6
  JSR BUF_NUM
  DEC T7
  BEQ .ss_e
  LDA #$2B
  JSR BUF_CH
  BRA .ss_l
.ss_e:
  LDA QC                       ; " = C" if it fits
  JSR SPLIT_NUM
  LDA BL
  CLC
  ADC #3
  ADC NDIG
  CMP #33
  BCS .ss_p
  LDA #<TXT_EQ
  STA TP
  LDA #>TXT_EQ
  STA TP+1
  JSR BUF_STR
  LDA QC
  JSR BUF_NUM
.ss_p:
  LDX #22
  JMP PRINT_BUF_C

; "A X B = C" into the buffer
BUF_FACT:
  LDA QA
  JSR BUF_NUM
  LDA #<TXT_X
  STA TP
  LDA #>TXT_X
  STA TP+1
  JSR BUF_STR
  LDA QB
  JSR BUF_NUM
  LDA #<TXT_EQ
  STA TP
  LDA #>TXT_EQ
  STA TP+1
  JSR BUF_STR
  LDA QC
  JMP BUF_NUM

; TP = a message centred on row 23
MSG23:
  LDX #23
  JSR CLEAR_ROW
  LDX #23
  JMP PRINT_C


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

; the whole name table to tile 0 (3 pages, tight loop)
CLEAR_NT:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #$00
  LDY #3
  LDX #$00
.cn_l:
  STA VDATA
  DEX
  BNE .cn_l
  DEY
  BNE .cn_l
  RTS

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

; X = row: the whole row blank
CLEAR_ROW:
  LDY #0
  JSR NT_XY
  LDA #$00
  LDX #32
.cr_l:
  STA VDATA
  DEX
  BNE .cr_l
  RTS

; zero-terminated text at TP on row X from column Y
PRINT_AT:
  JSR NT_XY
  LDY #$00
.pa_l:
  LDA (TP),Y
  BEQ .pa_e
  STA VDATA
  INY
  BRA .pa_l
.pa_e:
  RTS

; zero-terminated text at TP centred on row X
PRINT_C:
  LDY #$00
.pc_n:
  LDA (TP),Y
  BEQ .pc_d
  INY
  BRA .pc_n
.pc_d:
  STY T0
  LDA #32
  SEC
  SBC T0
  LSR A
  TAY
  JMP PRINT_AT

; ---------------------------------------------------------------
; text buffer: BUF_CLR, BUF_CH (A), BUF_STR (TP), BUF_NUM (A = 0-255)
; ---------------------------------------------------------------
BUF_CLR:
  STZ BL
  RTS

BUF_CH:
  LDX BL
  STA BUF,X
  INC BL
  RTS

BUF_STR:
  LDY #$00
.bs_l:
  LDA (TP),Y
  BEQ .bs_e
  JSR BUF_CH
  INY
  BRA .bs_l
.bs_e:
  RTS

BUF_NUM:
  JSR SPLIT_NUM
  LDA NH
  BEQ .bn_t
  ORA #$30
  JSR BUF_CH
  LDA NTN
  ORA #$30
  JSR BUF_CH
  BRA .bn_o
.bn_t:
  LDA NTN
  BEQ .bn_o
  ORA #$30
  JSR BUF_CH
.bn_o:
  LDA NO
  ORA #$30
  JMP BUF_CH

; the buffer on row X from column Y
PRINT_BUF_AT:
  JSR NT_XY
  LDX #$00
.pb_l:
  CPX BL
  BEQ .pb_e
  LDA BUF,X
  STA VDATA
  INX
  BRA .pb_l
.pb_e:
  RTS

; the buffer centred on row X (the row is cleared first)
PRINT_BUF_C:
  STX T5
  JSR CLEAR_ROW
  LDA #32
  SEC
  SBC BL
  LSR A
  TAY
  LDX T5
  JMP PRINT_BUF_AT

; A = 0-255: NH hundreds, NTN tens, NO ones, NDIG digits (1-3)
SPLIT_NUM:
  LDX #$00
.sn_h:
  CMP #100
  BCC .sn_h0
  SBC #100
  INX
  BRA .sn_h
.sn_h0:
  STX NH
  LDX #$00
.sn_t:
  CMP #10
  BCC .sn_o
  SBC #10
  INX
  BRA .sn_t
.sn_o:
  STA NO
  STX NTN
  LDA #3
  LDX NH
  BNE .sn_e
  LDA #2
  LDX NTN
  BNE .sn_e
  LDA #1
.sn_e:
  STA NDIG
  RTS

; ---------------------------------------------------------------
; big glyphs 16x16 (2 x 2 tiles)
; ---------------------------------------------------------------
; A = glyph, X = row, Y = column
DRAW_BIG:
  ASL A
  ASL A
  STA T4
  STX T5
  STY T3
  JSR NT_XY
  LDX T4
  LDA BIG_T,X
  STA VDATA
  LDA BIG_T+1,X
  STA VDATA
  LDX T5
  INX
  LDY T3
  JSR NT_XY
  LDX T4
  LDA BIG_T+2,X
  STA VDATA
  LDA BIG_T+3,X
  STA VDATA
  RTS

; A = glyph at the cursor BROW / BCOL, then the cursor moves 2 columns on
BIG_CUR:
  LDX BROW
  LDY BCOL
  JSR DRAW_BIG
  INC BCOL
  INC BCOL
  RTS

; A = 0-100 in big digits at the cursor
BIG_NUM:
  JSR SPLIT_NUM
  LDA NH
  BEQ .bg_t
  JSR BIG_CUR
  LDA NTN
  JSR BIG_CUR
  BRA .bg_o
.bg_t:
  LDA NTN
  BEQ .bg_o
  JSR BIG_CUR
.bg_o:
  LDA NO
  JMP BIG_CUR

; ---------------------------------------------------------------
; the scoreboard: A = BCD 00-99 in red 7-segment digits
; ---------------------------------------------------------------
DRAW_SEG:
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  LDY #SEG_COL
  JSR SEG_DIG
  PLA
  AND #$0F
  LDY #SEG_COL+2
  ; fall into SEG_DIG

; A = digit, Y = column: 2 x 3 tiles from row SEG_ROW
SEG_DIG:
  STA T4
  ASL A
  ADC T4
  ASL A                        ; digit * 6
  STA T4
  STY T3
  LDA #SEG_ROW
  STA T5
.sd_l:
  LDX T5
  LDY T3
  JSR NT_XY
  LDX T4
  LDA SEG_T,X
  STA VDATA
  LDA SEG_T+1,X
  STA VDATA
  INX
  INX
  STX T4
  INC T5
  LDA T5
  CMP #SEG_ROW+3
  BNE .sd_l
  RTS

; ---------------------------------------------------------------
; a frame of tiles: FR_R row, FR_C column, FR_W width, FR_H height,
; FSET = 8 tiles: top left, top, top right, left, right, bottom
; left, bottom, bottom right (the inside is not touched)
; ---------------------------------------------------------------
DRAW_RECT:
  LDX FR_R
  LDY FR_C
  JSR NT_XY
  LDY #0
  LDA (FSET),Y
  STA VDATA
  LDX FR_W
  DEX
  DEX
  LDY #1
  LDA (FSET),Y
.dr_t:
  STA VDATA
  DEX
  BNE .dr_t
  LDY #2
  LDA (FSET),Y
  STA VDATA
  LDA FR_R
  STA T5
  LDA FR_H
  SEC
  SBC #2
  STA T4
.dr_s:
  INC T5
  LDX T5
  LDY FR_C
  JSR NT_XY
  LDY #3
  LDA (FSET),Y
  STA VDATA
  LDA FR_C
  CLC
  ADC FR_W
  SEC
  SBC #1
  TAY
  LDX T5
  JSR NT_XY
  LDY #4
  LDA (FSET),Y
  STA VDATA
  DEC T4
  BNE .dr_s
  INC T5
  LDX T5
  LDY FR_C
  JSR NT_XY
  LDY #5
  LDA (FSET),Y
  STA VDATA
  LDX FR_W
  DEX
  DEX
  LDY #6
  LDA (FSET),Y
.dr_b:
  STA VDATA
  DEX
  BNE .dr_b
  LDY #7
  LDA (FSET),Y
  STA VDATA
  RTS

; A = slot, X = style (0 blue, 1 green, 2 red): the frame of an answer
DRAW_BOX:
  TAY
  LDA BOX_R,Y
  STA FR_R
  LDA BOX_C,Y
  STA FR_C
  LDA #8
  STA FR_W
  LDA #4
  STA FR_H
  TXA
  ASL A
  ASL A
  ASL A
  CLC
  ADC #<BOX_T
  STA FSET
  LDA #>BOX_T
  ADC #$00
  STA FSET+1
  JMP DRAW_RECT

; A = slot: its number in big digits, centred in the box
DRAW_ANS:
  TAY
  LDA ANS,Y
  JSR SPLIT_NUM
  LDA BOX_R,Y
  INC A
  STA BROW
  LDA BOX_C,Y
  CLC
  ADC #4
  SEC
  SBC NDIG
  STA BCOL
  LDA ANS,Y
  JMP BIG_NUM

; the time bar: BARN tiles of 30 (row BAR_ROW, columns 1-30)
DRAW_BAR:
  LDX #BAR_ROW
  LDY #1
  JSR NT_XY
  LDX #$00
.db_l:
  LDA #T_BAR
  CPX BARN
  BCC .db_p
  LDA #$00
.db_p:
  STA VDATA
  INX
  CPX #30
  BNE .db_l
  RTS


; ===============================================================
;  SPRITES (16x16 shown magnified: 32x32 on the screen)
; ===============================================================
; OX, OY = top left, ON = pattern, OC = colour (32 sprites at most)
ADD_SPR:
  LDX SPRI
  CPX #128
  BCS .as_r
  LDA OY
  SEC
  SBC #1
  STA SAT_BUFFER,X
  LDA OX
  STA SAT_BUFFER+1,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OC
  STA SAT_BUFFER+3,X
  TXA
  CLC
  ADC #4
  STA SPRI
.as_r:
  RTS

; X = monster, Y = form (0 not caught = dark blue shape, 1 baby,
; 2 evolved) at OX, OY: the black layer (outline, eyes) in front
ADD_MON:
  STX T0
  STY T1
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  CPY #2
  BNE .am_b
  CLC
  ADC #8
.am_b:
  STA T2
  CLC
  ADC #4
  STA ON
  LDA #$01
  STA OC
  JSR ADD_SPR
  LDA T2
  STA ON
  LDX T0
  LDA T1
  BEQ .am_s
  CMP #2
  BEQ .am_e
  LDA MON_C1,X
  BRA .am_c
.am_e:
  LDA MON_C2,X
  BRA .am_c
.am_s:
  LDA #$04
.am_c:
  STA OC
  JMP ADD_SPR

; the end of the sprite list (Y = $D0)
END_SAT:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
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
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX SATB                ; the sprites in use + Y=$D0 = end of the list
  BNE .copy_sat
  JSR SND_TICK            ; music or sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI


; ===============================================================
;  SOUND: the start tune (4 tracks, from tank) and the effects
;  per chip in game: A = tone effects, B = noise and C = low tone
;  of the explosions; left chip = player 1, right = player 2
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

; ===============================================================
;  LIBRARY (from lunar_lander): joystick, frames, VDP
;  (R1 = $C7 / $E7: sprites 16x16 magnified)
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
  LDA #$C7                ; R1: 16K + display ON + INT OFF
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA #$00
  STA VINT
.io_ret:
  RTS

VDP_INT_ON:
  LDA #$E7                ; R1: 16K + display ON + INT ON
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
   .byte $02,$C7,$0E,$FF       ;INITIALIZE G2 MODE
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
BITS:       .byte 1,2
SLOT_BIT:   .byte 1,2,4,8                      ; joystick bit of each slot (up, down, left, right)
BOX_R:      .byte 8,18,13,13                   ; the boxes of the answers: row, column
BOX_C:      .byte 12,12,2,22
TEN:        .byte 0,10,20,30,40,50,60,70,80,90
EASY_TAB:   .byte 0,1,1,0,0,1,0,0,0,0,1        ; factors of the easy facts: 1, 2, 5, 10
MENU_ROW:   .byte 8,10,12,14,16,18
MENU_JMP:   .word GO_PRACTICE,GO_SFIDA,GO_DUELCPU,GO_DUEL2,GO_TAVOLA,GO_MOSTRI
STAR_DX:    .byte $FF,$01,$FF,$01              ; the stars of a right answer: directions
STAR_DY:    .byte $FF,$FF,$01,$01
STAR_X:     .byte 88,120,152                   ; the stars of the result
; the jump of the monster (24 frames)
JUMP_Y:     .byte 0,2,4,6,7,9,10,11,12,12,13,13,13,13,12,12,11,10,9,7,6,4,2,0
; I MIEI MOSTRI: sprite X, Y, row and column of the name
ML_X:       .byte 8,8,8,8,8,136,136,136,136,136
ML_Y:       .byte 12,48,84,120,156,12,48,84,120,156
ML_ROW:     .byte 2,7,11,16,20,2,7,11,16,20
ML_COL:     .byte 6,6,6,6,6,22,22,22,22,22

; ---------------------------------------------------------------
; the CPU of the duel, by level (easy, medium, hard)
; ---------------------------------------------------------------
AI_TMIN:    .byte 150,100,60                   ; frames it thinks at least
AI_MASK:    .byte 127,127,63                   ; + random 0..mask
AI_HARDT:   .byte 60,40,20                     ; + this for the facts without 1, 2, 5, 10
AI_RIGHT:   .byte 160,200,235                  ; right answer: probability out of 256

; ---------------------------------------------------------------
; texts (Italian on the screen; the font has no accents)
; records: row, column, characters, 0   (end of list: $FF)
; ---------------------------------------------------------------
TXT_TITLE:
  .byte 5,11,"PER MATTIA",0
  .byte 8,3,"ALLENAMENTO",0
  .byte 10,3,"SFIDA",0
  .byte 12,3,"DUELLO 1 GIOCATORE CONTRO CPU",0
  .byte 14,3,"DUELLO 2 GIOCATORI",0
  .byte 16,3,"LA MIA TAVOLA",0
  .byte 18,3,"I MIEI MOSTRI",0
  .byte 21,9,"RECORD",0
  .byte 23,1,"SU/GIU' SCEGLI   TASTO 1 = VIA",0
  .byte $FF
TXT_SELT:
  .byte 3,10,"ALLENAMENTO",0
  .byte 6,6,"SCEGLI LA TABELLINA",0
  .byte 20,4,"SINISTRA/DESTRA = CAMBIA",0
  .byte 22,1,"TASTO 1 = VIA   TASTO 2 = MENU",0
  .byte $FF
TXT_SELA:
  .byte 3,6,"DUELLO CONTRO LA CPU",0
  .byte 6,6,"LIVELLO DEL COMPUTER",0
  .byte 20,4,"SINISTRA/DESTRA = CAMBIA",0
  .byte 22,1,"TASTO 1 = VIA   TASTO 2 = MENU",0
  .byte $FF
TXT_ARROWS:
  .byte 9,8,"<",0
  .byte 9,23,">",0
  .byte $FF
TXT_ARROWS2:
  .byte 10,8,"<",0
  .byte 10,23,">",0
  .byte $FF
TXT_STS:
  .byte 0,1,"PUNTI",0
  .byte 0,18,"RECORD",0
  .byte $FF
TXT_STD:
  .byte 0,1,"G1",0
  .byte $FF
TXT_END1:
  .byte 2,9,"PARTITA FINITA",0
  .byte 5,8,"RISPOSTE GIUSTE",0
  .byte 10,13,"SU 10",0
  .byte $FF
TXT_PTS:
  .byte 16,10,"PUNTI",0
  .byte $FF
TXT_END2:
  .byte 2,8,"FINE DEL DUELLO",0
  .byte 6,8,"G1",0
  .byte $FF
TXT_TAV:
  .byte 0,9,"LA MIA TAVOLA",0
  .byte 22,2,"TASTO 1 ALLENA  TASTO 2 MENU",0
  .byte $FF
TXT_MON:
  .byte 0,9,"I MIEI MOSTRI",0
  .byte 23,9,"PREMI IL TASTO",0
  .byte $FF
TXT_ALL:      .byte "TUTTE",0
TXT_QQQ:      .byte "???",0
TXT_STP:      .byte "ALLENAMENTO: ",0
TXT_STT:      .byte "TABELLINA DEL ",0
TXT_DOM:      .byte "DOMANDA ",0
TXT_DI10:     .byte " DI 10",0
TXT_HINTHELP: .byte "TASTO 2 = AIUTO",0
TXT_CHOOSE:   .byte "ORA SCEGLI LA RISPOSTA",0
TXT_BRAVO:    .byte "BRAVO!",0
TXT_STREAK1:  .byte "5 DI FILA! BONUS +200",0
TXT_STREAK0:  .byte "5 DI FILA! BRAVISSIMO!",0
TXT_WRONG:    .byte "SBAGLIATO!",0
TXT_TIMEUP:   .byte "TEMPO SCADUTO!",0
TXT_NOONE:    .byte "NESSUN PUNTO!",0
TXT_PRESS:    .byte "PREMI IL TASTO",0
TXT_PRESS2:   .byte "PREMI IL TASTO PER CONTINUARE",0
TXT_POINT:    .byte "PUNTO PER ",0
TXT_MISS:     .byte " SBAGLIA!",0
TXT_WINS:     .byte "VINCE ",0
TXT_DRAW:     .byte "PAREGGIO!",0
TXT_PERFECT:  .byte "10 SU 10! BONUS +500",0
TXT_NEWREC:   .byte "NUOVO RECORD!",0
TXT_CATCH:    .byte "HAI CATTURATO",0
TXT_EVOLVE:   .byte " SI EVOLVE!",0
TXT_NOW:      .byte "ORA E' ",0
TXT_TAB:      .byte "TAB ",0
TXT_X:        .byte " X ",0
TXT_EQ:       .byte " = ",0
TXT_G1:       .byte "G1",0
TXT_CPU:      .byte "CPU",0
TXT_G2:       .byte "G2",0
TXT_LCPU:     .byte "LA CPU",0
TXT_EASY:     .byte "FACILE",0
TXT_MED:      .byte "MEDIO",0
TXT_HARD:     .byte "DIFFICILE",0
TXT_M0:       .byte "ALLENAMENTO",0
TXT_M1:       .byte "SFIDA",0
TXT_M2:       .byte "DUELLO",0
AI_NAME_LO:   .byte <TXT_EASY,<TXT_MED,<TXT_HARD
AI_NAME_HI:   .byte >TXT_EASY,>TXT_MED,>TXT_HARD
MODE_NAME_LO: .byte <TXT_M0,<TXT_M1,<TXT_M2,<TXT_M2
MODE_NAME_HI: .byte >TXT_M0,>TXT_M1,>TXT_M2,>TXT_M2
P2_NAME_LO:   .byte <TXT_CPU,<TXT_G2           ; modes 2 and 3: the short name of player 2
P2_NAME_HI:   .byte >TXT_CPU,>TXT_G2
P2_LONG_LO:   .byte <TXT_LCPU,<TXT_G2          ; and in the messages
P2_LONG_HI:   .byte >TXT_LCPU,>TXT_G2

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

SONGP_LO:      .byte <TUNE_LEAD,<TUNE_HARM,<TUNE_BASS,<TUNE_DRUM
SONGP_HI:      .byte >TUNE_LEAD,>TUNE_HARM,>TUNE_BASS,>TUNE_DRUM
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

; the title tune: a cheerful 4-bar tune in C (composed for this game), 256 frames
;   G4 32  C5 37  D5 39  E5 41  F5 42  G5 44  A5 46  C6 49
TUNE_LEAD:
  .byte 37,8, 41,8, 44,8, 41,8, 42,8, 46,8, 44,16
  .byte 41,8, 37,8, 39,8, 41,8, 39,16, 32,16
  .byte 37,8, 41,8, 44,8, 49,8, 46,8, 44,8, 42,16
  .byte 41,8, 39,8, 41,8, 42,8, 41,8, 39,8, 37,16
  .byte $FF
TUNE_HARM:
  .byte 29,32, 30,32
  .byte 29,32, 27,32
  .byte 29,32, 30,32
  .byte 27,32, 29,32
  .byte $FF
TUNE_BASS:
  .byte 13,16, 8,16, 6,16, 13,16
  .byte 13,16, 8,16, 8,16, 15,16
  .byte 13,16, 8,16, 6,16, 10,16
  .byte 8,16, 8,16, 13,32
  .byte $FF
TUNE_DRUM:
  .byte 1,16, 3,8, 3,8, 2,16, 3,16
  .byte 1,16, 3,8, 3,8, 2,16, 3,16
  .byte 1,16, 3,8, 3,8, 2,16, 3,16
  .byte 1,16, 2,16, 1,16, 4,16
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
; Times Tables: generated by dev/gen_tt.js (do not edit by hand)

; tiles 1-31 and 96-255 (identical tiles share one id)
TPA:
  .byte $00,$07,$07,$18,$18,$18,$18,$19,$00,$E0,$E0,$18,$18,$78,$78,$98
  .byte $19,$1E,$1E,$18,$18,$07,$07,$00,$98,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$01,$01,$07,$07,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$07,$07,$18,$18,$00,$00,$01,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $01,$06,$06,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$00,$00,$00,$00,$01,$00,$F8,$F8,$18,$18,$60,$60,$E0
  .byte $01,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$00,$00,$01,$01,$06,$06,$18,$00,$60,$60,$E0,$E0,$60,$60,$60
  .byte $18,$1F,$1F,$00,$00,$00,$00,$00,$60,$F8,$F8,$60,$60,$60,$60,$00
  .byte $00,$1F,$1F,$18,$18,$1F,$1F,$00,$00,$F8,$F8,$00,$00,$E0,$E0,$18
  .byte $00,$00,$00,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$07,$07,$00,$00,$F8,$F8,$18,$18,$60,$60,$80
  .byte $01,$06,$06,$06,$06,$06,$06,$00,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07
TCA:
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
TPB:
  .byte $07,$18,$18,$18,$18,$07,$07,$00,$00,$E0,$E0,$18,$18,$18,$18,$F8
  .byte $07,$00,$00,$00,$00,$1F,$1F,$00,$F8,$18,$18,$60,$60,$80,$80,$00
  .byte $00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80
  .byte $01,$06,$06,$18,$18,$18,$18,$00,$80,$60,$60,$18,$18,$18,$18,$00
  .byte $00,$00,$00,$00,$00,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00,$00,$00,$00,$00
  .byte $00,$E0,$E0,$18,$18,$60,$60,$80,$01,$01,$01,$00,$00,$01,$01,$00
  .byte $80,$80,$80,$00,$00,$80,$80,$00,$00,$1F,$1F,$01,$01,$01,$01,$01
  .byte $00,$F8,$F8,$80,$80,$80,$80,$80,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$00,$01,$01,$06,$06,$18,$18,$18
  .byte $00,$80,$80,$60,$60,$18,$18,$18,$18,$1F,$1F,$18,$18,$18,$18,$00
  .byte $18,$F8,$F8,$18,$18,$18,$18,$00,$00,$1F,$1F,$18,$18,$18,$18,$1F
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$1F,$18,$18,$18,$18,$1F,$1F,$00
  .byte $E0,$18,$18,$18,$18,$E0,$E0,$00,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $18,$06,$06,$06,$06,$01,$01,$00,$18,$60,$60,$60,$60,$80,$80,$00
  .byte $00,$01,$01,$01,$01,$01,$01,$00,$00,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$01,$01,$01,$01,$00,$00,$00,$00,$80,$80,$80,$80,$00,$00,$00
  .byte $00,$0F,$1F,$2F,$70,$70,$70,$70,$00,$F0,$F8,$F4,$0E,$0E,$0E,$0E
  .byte $70,$70,$70,$20,$00,$20,$70,$70,$0E,$0E,$0E,$04,$00,$04,$0E,$0E
  .byte $70,$70,$70,$70,$70,$2F,$1F,$0F,$0E,$0E,$0E,$0E,$0E,$F4,$F8,$F0
  .byte $00,$00,$00,$04,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$04,$00,$00
  .byte $00,$0F,$1F,$0F,$00,$00,$00,$00,$00,$00,$00,$0F,$1F,$2F,$70,$70
  .byte $0E,$0E,$0E,$F4,$F8,$F0,$00,$00,$00,$00,$00,$00,$00,$F0,$F8,$F0
  .byte $00,$00,$00,$0F,$1F,$0F,$00,$00,$0E,$0E,$0E,$F4,$F8,$F4,$0E,$0E
  .byte $00,$00,$00,$00,$00,$0F,$1F,$0F,$00,$00,$00,$20,$70,$70,$70,$70
  .byte $70,$70,$70,$2F,$1F,$0F,$00,$00,$00,$F0,$F8,$F0,$00,$00,$00,$00
  .byte $00,$00,$00,$F0,$F8,$F4,$0E,$0E,$70,$70,$70,$2F,$1F,$2F,$70,$70
  .byte $00,$00,$00,$00,$07,$0F,$0C,$0C,$00,$00,$00,$00,$FF,$FF,$00,$00
  .byte $00,$00,$00,$00,$E0,$F0,$30,$30,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$0C,$0C,$0F,$07,$00,$00,$00,$00
  .byte $00,$00,$FF,$FF,$00,$00,$00,$00,$30,$30,$F0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0F,$0C,$0C,$00,$00,$00,$00,$FF,$FF,$00,$00
  .byte $00,$00,$00,$00,$E0,$F0,$30,$30,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$0C,$0C,$0F,$07,$00,$00,$00,$00
  .byte $00,$00,$FF,$FF,$00,$00,$00,$00,$30,$30,$F0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0F,$0C,$0C,$00,$00,$00,$00,$FF,$FF,$00,$00
  .byte $00,$00,$00,$00,$E0,$F0,$30,$30,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$0C,$0C,$0F,$07,$00,$00,$00,$00
  .byte $00,$00,$FF,$FF,$00,$00,$00,$00,$30,$30,$F0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0F,$0C,$0C,$00,$00,$00,$00,$FF,$FF,$00,$00
  .byte $00,$00,$00,$00,$E0,$F0,$30,$30,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$0C,$0C,$0F,$07,$00,$00,$00,$00
  .byte $00,$00,$FF,$FF,$00,$00,$00,$00,$30,$30,$F0,$E0,$00,$00,$00,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$10,$10,$FE,$7C,$38,$6C,$44,$00
  .byte $10,$10,$FE,$7C,$38,$6C,$44,$00,$00,$7E,$7E,$7E,$7E,$7E,$7E,$00
  .byte $00,$7E,$7E,$7E,$7E,$7E,$7E,$00,$00,$7E,$7E,$7E,$7E,$7E,$7E,$00
  .byte $00,$7E,$7E,$7E,$7E,$7E,$7E,$00
TCB:
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80
  .byte $30,$30,$30,$30,$30,$30,$30,$30,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $80,$80,$80,$80,$80,$80,$80,$80,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $20,$20,$20,$20,$20,$20,$20,$20

; big glyphs 16x16: 4 tiles each (top left, top right, bottom left, bottom right)
; 0-9 = digits
G_X = 10
G_EQ = 11
G_Q = 12
G_T = 13
G_A = 14
G_B = 15
G_E = 16
G_L = 17
G_I = 18
G_N = 19
G_V = 20
G_EX = 21
BIG_T:
  .byte $01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10
  .byte $11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$10,$0D,$1C,$1D,$1E
  .byte $1F,$0A,$60,$10,$1F,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B
  .byte $09,$6C,$6D,$6E,$6F,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A
  .byte $77,$7B,$79,$7C,$7D,$00,$7E,$7F,$80,$81,$82,$83,$84,$85,$86,$87
  .byte $7D,$7D,$88,$89,$8A,$8B,$8C,$8D

; 7-segment digits 16x24: 6 tiles each, row by row
SEG_T:
  .byte $8E,$8F,$90,$91,$92,$93
  .byte $00,$94,$00,$91,$00,$95
  .byte $96,$8F,$97,$98,$92,$99
  .byte $96,$8F,$9A,$9B,$9C,$93
  .byte $9D,$94,$9E,$9B,$00,$95
  .byte $8E,$9F,$9E,$A0,$9C,$93
  .byte $8E,$9F,$A1,$A0,$92,$93
  .byte $96,$8F,$00,$91,$00,$95
  .byte $8E,$8F,$A1,$9B,$92,$93
  .byte $8E,$8F,$9E,$9B,$9C,$93

; frame of the scoreboard: TL, top, TR, left, right, BL, bottom, BR
FRAME_T:
  .byte $A2,$A3,$A4,$A5,$A6,$A7,$A8,$A9
; boxes of the answers, same order: blue, green, red
BOX_T:
  .byte $AA,$AB,$AC,$AD,$AE,$AF,$B0,$B1
  .byte $B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9
  .byte $BA,$BB,$BC,$BD,$BE,$BF,$C0,$C1
T_BAR = 194
T_STAR = 195
T_STAR0 = 196
T_CELL0 = 197
T_CELL1 = 198
T_CELL2 = 199
T_CELL3 = 200

; the title: glyph numbers
TITLE_G:
  .byte $0D,$0E,$0F,$10,$11,$11,$12,$13,$10
TITLE_N = 9
VIA_G:
  .byte $14,$12,$0E,$15

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <248,>248, <TPA,>TPA
  .byte 1, $08,$60, <248,>248, <TCA,>TCA
  .byte 1, $00,$43, <840,>840, <TPB,>TPB
  .byte 1, $00,$63, <840,>840, <TCB,>TCB
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <248,>248, <TPA,>TPA
  .byte 1, $08,$68, <248,>248, <TCA,>TCA
  .byte 1, $00,$4B, <840,>840, <TPB,>TPB
  .byte 1, $00,$6B, <840,>840, <TCB,>TCB
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <248,>248, <TPA,>TPA
  .byte 1, $08,$70, <248,>248, <TCA,>TCA
  .byte 1, $00,$53, <840,>840, <TPB,>TPB
  .byte 1, $00,$73, <840,>840, <TCB,>TCB
  .byte 0

; sprite patterns (16x16, shown magnified x2), value = pattern number * 4
; monster m: baby body (m*16), baby black (m*16+4), evolved body (m*16+8), evolved black (m*16+12)
PT_STAR = 160
PT_CUR = 164
SPR_PAGES = 6
SPRITES:
  .byte $00,$00,$00,$00,$00,$03,$0F,$1F,$3F,$3F,$3F,$3F,$1F,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$D8,$F8,$FC,$FC,$FC,$FC,$F8,$30,$00,$00
  .byte $00,$00,$00,$00,$03,$0C,$10,$20,$40,$48,$40,$43,$20,$13,$0C,$00
  .byte $00,$00,$00,$00,$80,$58,$24,$04,$02,$82,$02,$02,$04,$C8,$30,$00
  .byte $00,$03,$1B,$3F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$3F,$1B,$00,$00
  .byte $00,$C0,$F0,$F8,$FC,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FC,$D8,$00,$00
  .byte $03,$1C,$24,$40,$80,$80,$98,$98,$80,$88,$87,$80,$40,$24,$1B,$00
  .byte $C0,$30,$08,$04,$02,$01,$61,$61,$01,$11,$E1,$01,$02,$24,$D8,$00
  .byte $00,$01,$03,$03,$07,$0F,$1F,$1F,$3F,$3F,$3F,$3F,$1F,$0F,$03,$00
  .byte $00,$80,$C0,$C0,$E0,$F0,$F8,$F8,$FC,$FC,$FC,$FC,$F8,$F0,$C0,$00
  .byte $01,$02,$04,$04,$08,$10,$20,$20,$44,$44,$42,$41,$20,$10,$0C,$03
  .byte $80,$40,$20,$20,$10,$08,$04,$04,$22,$22,$42,$82,$04,$08,$30,$C0
  .byte $00,$01,$03,$47,$6F,$3F,$3F,$3F,$1F,$1F,$1F,$3F,$6F,$47,$02,$00
  .byte $00,$80,$C0,$E2,$F6,$FC,$FC,$FC,$F8,$F8,$F8,$FC,$F6,$E2,$40,$00
  .byte $01,$02,$44,$A8,$90,$40,$46,$46,$20,$23,$20,$40,$90,$A8,$45,$02
  .byte $80,$40,$22,$15,$09,$02,$62,$62,$04,$C4,$04,$02,$09,$15,$A2,$40
  .byte $00,$00,$00,$00,$01,$01,$07,$0F,$1F,$1F,$1F,$1F,$0F,$07,$06,$00
  .byte $00,$60,$F0,$E0,$80,$00,$E0,$F0,$F8,$F8,$F8,$F8,$F0,$E0,$60,$00
  .byte $00,$00,$01,$01,$02,$06,$08,$10,$20,$24,$20,$21,$10,$08,$09,$06
  .byte $60,$90,$08,$10,$60,$E0,$10,$08,$04,$24,$04,$84,$08,$10,$90,$60
  .byte $00,$07,$1F,$3F,$7F,$7F,$3F,$0F,$0F,$4F,$6F,$3F,$0F,$0E,$1E,$00
  .byte $00,$E0,$F8,$FC,$FE,$FE,$FC,$F0,$F0,$F2,$F6,$FC,$F0,$70,$78,$00
  .byte $07,$18,$20,$40,$80,$80,$40,$32,$50,$B1,$90,$40,$30,$11,$21,$1E
  .byte $E0,$18,$04,$02,$01,$01,$02,$4C,$0A,$8D,$09,$02,$0C,$88,$84,$78
  .byte $00,$01,$03,$03,$07,$17,$1F,$1F,$3F,$3F,$3F,$3F,$1F,$0F,$07,$00
  .byte $00,$00,$10,$B0,$E0,$E0,$F8,$F8,$FC,$FC,$FC,$FC,$F8,$F0,$E0,$00
  .byte $01,$02,$04,$04,$18,$28,$20,$20,$44,$44,$40,$41,$20,$10,$08,$07
  .byte $00,$90,$A8,$48,$10,$18,$04,$04,$22,$22,$02,$82,$04,$08,$10,$E0
  .byte $00,$09,$05,$06,$07,$0F,$0F,$1F,$1F,$3F,$3F,$7F,$7F,$3B,$31,$00
  .byte $00,$90,$A0,$60,$E0,$F0,$F0,$F8,$F8,$FC,$FC,$FE,$FE,$DC,$8C,$00
  .byte $09,$16,$0A,$09,$08,$10,$12,$22,$20,$43,$40,$80,$80,$44,$4A,$31
  .byte $90,$68,$50,$90,$10,$08,$48,$44,$04,$C2,$02,$01,$01,$22,$52,$8C
  .byte $00,$01,$21,$13,$0F,$1F,$7F,$1F,$1F,$7F,$1F,$1F,$0F,$13,$21,$00
  .byte $00,$80,$84,$C8,$F0,$F8,$FE,$F8,$F8,$FE,$F8,$F8,$F0,$C8,$84,$00
  .byte $01,$22,$52,$2C,$10,$60,$88,$68,$60,$84,$63,$20,$10,$2C,$52,$21
  .byte $80,$44,$4A,$34,$08,$06,$11,$16,$06,$21,$C6,$04,$08,$34,$4A,$84
  .byte $00,$42,$66,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$1F,$0F,$0E,$1C,$18,$00
  .byte $00,$42,$66,$FC,$FC,$FC,$FC,$FC,$FC,$FC,$F8,$F2,$76,$3E,$0C,$00
  .byte $42,$A5,$99,$40,$40,$4C,$4C,$40,$47,$42,$20,$10,$11,$22,$24,$18
  .byte $42,$A5,$99,$02,$02,$32,$32,$02,$E2,$42,$06,$0D,$89,$41,$32,$0C
  .byte $00,$00,$00,$00,$00,$00,$03,$0F,$1F,$3F,$3F,$3F,$3F,$1F,$0E,$00
  .byte $00,$00,$00,$00,$00,$00,$C0,$F0,$F8,$FC,$FC,$FC,$FC,$F8,$70,$00
  .byte $00,$00,$00,$00,$00,$03,$0C,$10,$20,$44,$40,$41,$40,$20,$11,$0E
  .byte $00,$00,$00,$00,$00,$C0,$30,$88,$04,$22,$02,$82,$02,$04,$88,$70
  .byte $00,$07,$1F,$3F,$3F,$7F,$7F,$7F,$7F,$7F,$3F,$6F,$6F,$0E,$1E,$00
  .byte $00,$E0,$F8,$FC,$FC,$FE,$FE,$FE,$FE,$FE,$FC,$F6,$F6,$70,$78,$00
  .byte $07,$18,$20,$42,$41,$80,$98,$80,$8F,$80,$40,$90,$90,$71,$21,$1E
  .byte $E0,$18,$04,$02,$02,$01,$19,$01,$F1,$01,$02,$09,$09,$8E,$84,$78
  .byte $00,$05,$01,$03,$07,$0F,$1F,$1F,$1F,$0F,$0F,$07,$07,$03,$01,$00
  .byte $00,$A0,$80,$C0,$E0,$F0,$F8,$F8,$F8,$F0,$F0,$E0,$E0,$C0,$80,$00
  .byte $05,$0A,$06,$04,$08,$10,$24,$24,$20,$11,$10,$08,$08,$04,$02,$01
  .byte $A0,$50,$60,$20,$10,$08,$24,$24,$04,$88,$08,$10,$10,$20,$40,$80
  .byte $00,$24,$1B,$3F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$5F,$1F,$2E,$1E,$00
  .byte $00,$24,$D8,$FC,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FA,$F8,$74,$78,$00
  .byte $24,$5B,$24,$40,$80,$8C,$8C,$80,$88,$87,$80,$A0,$60,$51,$21,$1E
  .byte $24,$DA,$24,$02,$01,$31,$31,$01,$11,$E1,$01,$05,$06,$8A,$84,$78
  .byte $00,$00,$08,$0D,$0F,$1F,$1F,$3F,$3F,$3F,$3F,$3F,$3F,$36,$22,$00
  .byte $00,$00,$10,$B0,$F0,$F8,$F8,$FC,$FC,$FC,$FC,$FC,$FC,$6C,$44,$00
  .byte $00,$08,$15,$12,$10,$20,$20,$44,$44,$40,$41,$40,$40,$49,$55,$22
  .byte $00,$10,$A8,$48,$08,$04,$04,$22,$22,$02,$82,$02,$02,$92,$AA,$44
  .byte $00,$08,$0C,$0F,$4F,$6F,$77,$7B,$7D,$5D,$0F,$07,$03,$02,$06,$00
  .byte $00,$10,$30,$F0,$F2,$F6,$EE,$DE,$BE,$BA,$F0,$E0,$C0,$40,$60,$00
  .byte $08,$14,$13,$50,$B2,$92,$8A,$84,$82,$A2,$50,$08,$04,$05,$09,$06
  .byte $10,$28,$C8,$0A,$4D,$49,$51,$21,$41,$45,$0A,$10,$20,$A0,$90,$60
  .byte $00,$00,$03,$0C,$13,$02,$07,$0F,$1F,$1F,$1F,$0F,$07,$02,$06,$00
  .byte $00,$00,$80,$60,$10,$80,$E0,$F0,$F8,$F8,$FA,$F4,$E8,$60,$40,$00
  .byte $00,$03,$0C,$13,$2C,$15,$08,$10,$24,$20,$21,$10,$08,$05,$09,$06
  .byte $00,$80,$60,$90,$E8,$70,$10,$08,$24,$06,$85,$0A,$14,$98,$A0,$40
  .byte $00,$7F,$3F,$7F,$3F,$1F,$3F,$1F,$0F,$1F,$07,$0F,$03,$07,$03,$00
  .byte $00,$FE,$FC,$FE,$FC,$F8,$F8,$F8,$F0,$E0,$E0,$C0,$C0,$00,$00,$00
  .byte $7F,$80,$40,$80,$4C,$2C,$40,$27,$10,$20,$18,$10,$0C,$08,$04,$03
  .byte $FE,$01,$02,$01,$32,$34,$04,$E4,$08,$10,$10,$20,$20,$C0,$80,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$1F,$0F,$07,$07,$0E,$0C,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$F8,$F0,$E0,$E0,$70,$30,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$1C,$20,$12,$09,$08,$11,$12,$0C,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$38,$04,$48,$90,$10,$88,$48,$30,$00,$00
  .byte $00,$01,$03,$03,$07,$7F,$3F,$1F,$1F,$0F,$1F,$1E,$3C,$38,$60,$00
  .byte $00,$80,$C0,$C0,$E0,$FE,$FC,$F8,$F8,$F0,$F8,$78,$3C,$1C,$06,$00
  .byte $01,$02,$04,$04,$78,$80,$40,$26,$26,$11,$20,$21,$42,$44,$98,$60
  .byte $80,$40,$20,$20,$1E,$01,$02,$64,$64,$88,$04,$84,$42,$22,$19,$06
  .byte $20,$70,$F8,$70,$50,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $FC,$84,$84,$84,$84,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; monsters: colours and names
MON_C1:     .byte 15,5,2,8,11,14,7,13,3,10
MON_C2:     .byte 15,5,12,6,11,14,7,13,3,9
MON_N1_LO:  .byte <MN1_0,<MN1_1,<MN1_2,<MN1_3,<MN1_4,<MN1_5,<MN1_6,<MN1_7,<MN1_8,<MN1_9
MON_N1_HI:  .byte >MN1_0,>MN1_1,>MN1_2,>MN1_3,>MN1_4,>MN1_5,>MN1_6,>MN1_7,>MN1_8,>MN1_9
MON_N2_LO:  .byte <MN2_0,<MN2_1,<MN2_2,<MN2_3,<MN2_4,<MN2_5,<MN2_6,<MN2_7,<MN2_8,<MN2_9
MON_N2_HI:  .byte >MN2_0,>MN2_1,>MN2_2,>MN2_3,>MN2_4,>MN2_5,>MN2_6,>MN2_7,>MN2_8,>MN2_9
MN1_0: .byte "PUFFINO",0
MN2_0: .byte "PUFFONE",0
MN1_1: .byte "GOCCIOLO",0
MN2_1: .byte "ONDARO",0
MN1_2: .byte "FOGLIOTTO",0
MN2_2: .byte "ALBERONE",0
MN1_3: .byte "FIAMMINO",0
MN2_3: .byte "VULCANOTTO",0
MN1_4: .byte "SCINTILLA",0
MN2_4: .byte "FULMINATOR",0
MN1_5: .byte "SASSOLINO",0
MN2_5: .byte "MACIGNONE",0
MN1_6: .byte "GHIACCIOLO",0
MN2_6: .byte "BUFERONE",0
MN1_7: .byte "OMBRETTO",0
MN2_7: .byte "NOTTURNO",0
MN1_8: .byte "VENTOLINO",0
MN2_8: .byte "TORNADONE",0
MN1_9: .byte "STELLINO",0
MN2_9: .byte "SUPERNOVA",0

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$3C,$3C,$3C,$2F,$2F,$2F,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$00,$00,$A9,$A9
  .byte $A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$23,$23
  .byte $00,$47,$47,$47,$47,$47,$47,$47,$47,$47,$47,$24,$24,$24,$24,$24
  .byte $24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24
  .byte $24,$24,$24,$24,$24,$4E,$50,$53,$55,$57,$5A,$5D,$60,$63,$67,$6B
  .byte $6F,$73,$78,$7D,$82,$88,$8F,$97,$9F,$A8,$B2,$BE,$CB,$DA,$EB,$00
  .byte $19,$36,$5B,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$35,$28
  .byte $28,$28,$28,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$50
  .byte $3C,$3C,$3C,$3C,$3C,$50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$D0,$B1
  .byte $99,$87,$79,$6E,$64,$5C,$56,$50,$4B,$46,$42,$3F,$3B,$38,$36,$33
  .byte $31,$2F,$2D,$2C,$2A,$29,$27,$26,$25,$24,$23,$22,$21,$20,$1F,$1E
  .byte $1D,$1D,$1C,$1B,$1B,$1A,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$68,$68,$34,$34,$34,$27,$27,$27,$27
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .byte $01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0D,$0D,$0C,$0D,$0D,$0C,$0D,$0D,$0C,$0D,$0C,$0B,$0A,$08,$07
  .byte $06,$05,$0E,$0E,$0D,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$00,$00,$0E,$0D
  .byte $0D,$0C,$0B,$0B,$0A,$09,$09,$08,$07,$07,$06,$05,$05,$04,$0C,$07
  .byte $00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$0E,$0E,$0D,$0D,$0C
  .byte $0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06
  .byte $06,$05,$05,$04,$04,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $09,$09,$09,$08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$05,$04,$04
  .byte $04,$03,$03,$0C,$0B,$09,$08,$0C,$0B,$09,$08,$0C,$0B,$09,$08,$0C
  .byte $0B,$09,$08,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$08
  .byte $08,$0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08
  .byte $0D,$0C,$0B,$09,$08,$0D,$0C,$0B,$09,$08,$0D,$0D,$0C,$0C,$0C,$0C
  .byte $0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08
  .byte $08,$08,$09,$09,$09,$09,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0A,$0A
  .byte $0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$09,$09,$08,$08
  .byte $07,$06,$06,$05,$05,$04,$09,$05,$0C,$0B,$0A,$0C,$0A,$08,$06
WH_START:
  .byte $00,$01,$12,$2E,$31,$3B,$55,$73,$91,$BE,$F6,$F8
WH_LEN:
  .byte $00,$11,$1C,$03,$0A,$1A,$1E,$1E,$2D,$38,$02,$07
W_OK = 1
W_BAD = 2
W_TICK = 3
W_BEEP = 4
W_GO = 5
W_TIMEUP = 6
W_STREAK = 7
W_CATCH = 8
W_EVOLVE = 9
W_MOVE = 10
W_SELECT = 11

; noises: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0A,$06
EX_NP:
  .byte $00,$02,$02
EX_VC:
  .byte $00,$00,$00
EX_TL:
  .byte $00,$00,$00
EX_TH:
  .byte $00,$00,$00
EX_START:
  .byte $00,$01
EX_LEN:
  .byte $00,$02
S_TICK = 1
S_SMALL = S_TICK
S_BIG = S_TICK
