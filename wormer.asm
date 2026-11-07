;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   WORMER  -  an original maze game with a growing body       ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - a caterpillar lives inside a giant apple: every level    ;
;     is a slice with its tunnels and its seeds, down to the   ;
;     core: 24 slices, then again faster                       ;
;   - it never stops: the joystick books the next turn, taken  ;
;     at the first crossing; at a bend it turns by itself, at  ;
;     a wall with two ways it waits for the joystick           ;
;   - every seed makes it one piece longer; the gold seed is   ;
;     worth five, the leaf makes it 4 pieces shorter, the      ;
;     honey stops the time for 5 s; biting its own body costs  ;
;     a life                                                   ;
;   - from slice 5 the worms of the apple go round the         ;
;     tunnels: they turn back at the body of the caterpillar,  ;
;     touching their head costs a life                         ;
;   - the time bar runs out: the apple rots and there are only ;
;     10 s left; the time left at the end is a bonus           ;
;   - points: seed 10 x the group of slices, gold x5, the time ;
;     left 50 a cell; 3 lives, one more at 20000 and every     ;
;     40000; 1 or 2 players taking turns                       ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 32 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at every slice and at its end;       ;
;     seeds, turns, the bite, the rotting apple                ;
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
SLICE       = $40      ; ---- block of the player, saved: slice 0-23
LOOPN       = $41      ;      round of the apple
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
FRESH       = $43      ;      1 = a new slice (the tune)
EATEN       = $44      ;      8 bytes: the seeds of the slice already eaten
PBLOCK      = 12
GSTATE      = $50      ; 0 playing, 1 life lost, 3 slice eaten
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives, 4 the time bar
FIRSTT      = $53      ; 1 = first turn of the game
NSEED       = $54      ; seeds left in the slice
HC          = $55      ; the head: column, row of its tile
HR          = $56
DIR         = $57      ; 0 right, 1 down, 2 left, 3 up
WANT        = $58      ; the turn booked with the joystick ($FF = none)
SUB         = $59      ; frames of the step done (0 = on a tile)
STEPF       = $5A      ; frames a step lasts
MOVING      = $5B      ; 0 = waiting at a wall for the joystick
GROW        = $5C      ; pieces still to grow
BH          = $5D      ; ring of the body: head end, tail end
BT          = $5E
TCELLS      = $5F      ; time: cells of the bar left (24 = full)
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
TCF         = $72      ; frames to the next cell of the time bar
TCFMAX      = $73      ;   (frames a cell lasts in this slice)
ROTT        = $74      ; rotting: frames left (0 = not rotting)
HONEYT      = $75      ; frames the time stands still
NC          = $76      ; next tile of a move: column, row
NR          = $77
SHADE       = $78      ; the two shades of the body take turns
NWORM       = $79      ; worms in the slice
LOSTN       = $7A      ; lives lost (tests)
DEATH       = $7B      ; what took the last life (tests): 1 bite, 2 worm, 3 rot
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
SEEDS_EATEN = $88      ; (tests)

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

; ---------------- the worms: 3 slots ----------------
NWM        = 3
W_C        = $0200       ; tile: column, row
W_R        = $0203
W_D        = $0206       ; direction
W_SUB      = $0209       ; frames of the step done
W_ON       = $020C       ; 1 = in the slice

; ---------------- other RAM ----------------
BODY_C     = $0400       ; ring of 256: the tiles of the body (column, row)
BODY_R     = $0500
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
MAP        = $0800       ; the name table (rows 0-23)

; ---------------- parameters ----------------
BTN_MASK    = %00110000
T_TUNNEL    = 0
T_PULP      = 96
T_PEEL      = 97
T_SEED      = 98         ; 98 seed, 99 gold, 100 leaf, 101 honey
T_BODY      = 102        ; 102 / 103 the two shades
T_LIFE      = 104
T_TFULL     = 105
T_TEMPTY    = 106
T_TROT      = 107
START_C     = 5          ; the den: the head on row 21, column 5, going right, 4 pieces behind
START_R     = 21

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 32         ; fixed zone of the game in the save area
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
;  TITLE: the name, the seeds, what they do
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

; one frame of the title: the caterpillar chews;
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
  LDA FRAME_CNT
  AND #16
  LSR A
  LSR A
  CLC
  ADC #PT_HEAD
  STA SAT_BUFFER+2
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: slice 1, 3 lives for every player
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
  STZ SEEDS_EATEN
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ SLICE
  STZ LOOPN
  JSR NEW_SLICE_P
  LDA #$02                     ; first extra life at 20000
  STA NEXTX
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER, then his slice
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

SLICE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the slice is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR DRAW_SLICE
  JSR DRAW_HUD
  JSR SLICE_INIT
  JSR DRAW_TIME                ; (the bar full again)
  JSR MSG_SLICE
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA FIRSTT                   ; the tune: first turn or a new slice
  ORA FRESH
  BEQ .ss_short
  STZ FIRSTT
  LDA #1
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
  BRA .ss_w
.ss_short:
  LDA #90
  JSR WAIT_FRAMES
.ss_w:
  LDA #20
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  JSR VDP_INT_ON
  STZ FRESH
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
  LDA GSTATE
  BNE .gl_ns
  JSR CRAWL
  JSR WORMS
  JSR CLOCK
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
  BEQ .gl_win
  JMP LOSE_LIFE
.gl_win:
  JMP SLICE_CLEAR


; ===============================================================
;  THE SLICE IS EATEN: the time bonus, the next slice
; ===============================================================
SLICE_CLEAR:
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
.sc_b:                         ; the time left: 50 a cell, the bar empties
  LDA TCELLS
  BEQ .sc_t
  LDA #4
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  DEC TCELLS
  LDA #$50
  LDY #$00
  JSR ADD_PTS
  JSR UPDATE_HUD
  JSR DRAW_TIME
  JSR VDP_INT_ON
  LDA #W_TICK
  LDX #2
  JSR SFX_WHISTLE
  BRA .sc_b
.sc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sc_t
  LDA #60
  JSR WAIT_FRAMES
  INC SLICE                    ; the next slice; after the core, the apple again
  LDA SLICE
  CMP #24
  BCC .sc_n
  STZ SLICE
  LDA LOOPN
  CMP #8
  BCS .sc_n
  INC LOOPN
.sc_n:
  JSR NEW_SLICE_P
  JSR SAVE_PLAYER
  JMP SLICE_START

; a new slice for the player playing: no seed eaten, the tune
NEW_SLICE_P:
  LDX #7
.np_e:
  STZ EATEN,X
  DEX
  BPL .np_e
  LDA #1
  STA FRESH
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
  TXA                          ; extra byte: the slice reached (round x 24 + slice + 1)
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE+1,Y
  ASL A
  ASL A
  ASL A
  STA T0
  ASL A
  ADC T0
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
REC_NAME:  .byte "WORMER          "
REC_HEAD:  .byte "BEST WORMERS",0
REC_XLBL:  .byte "SLICE ",0


; ===============================================================
;  HUD: row 0 (scores), row 1 (slice, player, lives), row 23 (time)
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

; row 1: SLICE nn, PLAYER n, the spare lives
DRAW_STATUS:
  LDX #1
  LDY #0
  JSR NT_XY
  LDX #0
.ds_s:
  LDA TXT_SLICEH,X
  STA VDATA
  INX
  CPX #6
  BNE .ds_s
  LDA SLICE
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDA NPL
  CMP #2
  BNE .ds_l
  LDX #1
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
.ds_l:
  LDX #1
  LDY #25
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
  RTS

; row 23: TIME and the bar (24 cells, red while the apple rots)
DRAW_TIME:
  LDX #23
  LDY #0
  JSR NT_XY
  LDX #0
.dm_t:
  LDA TXT_TIMEH,X
  STA VDATA
  INX
  CPX #5
  BNE .dm_t
  LDX #0
.dm_c:
  LDA #T_TEMPTY
  CPX TCELLS
  BCS .dm_w
  LDA #T_TFULL
.dm_w:
  LDY ROTT
  BEQ .dm_x
  LDA #T_TROT
.dm_x:
  STA VDATA
  INX
  CPX #24
  BNE .dm_c
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
  JSR DRAW_STATUS
  JMP DRAW_TIME

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives, 4 the time bar
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
  BEQ .uh_t
  JSR DRAW_STATUS
.uh_t:
  PLA
  AND #4
  BEQ .uh_r
  JSR DRAW_TIME
.uh_r:
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP
  LDA CURP
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA SLICE,Y
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
  STA SLICE,Y
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

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 20000, then every 40000
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
  LDA LIVES,X                  ; at most 7
  CMP #7
  BCS .as_m
  INC LIVES,X
.as_m:
  SED
  LDA NEXTX
  CLC
  ADC #$04
  CLD
  BCC .as_x
  LDA #$FF                     ; past 990000: no more
.as_x:
  STA NEXTX
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
;  THE SLICE ON THE SCREEN
; ===============================================================
; MAP and the name table: rows 0-1 and 23 spaces, the apple on rows 2-22, its tunnels,
; the seeds not eaten yet (interrupt off)
DRAW_SLICE:
  STZ ROTT                     ; (a fresh apple)
  LDX #0
.dl_c:
  LDA #T_PULP
  STA MAP,X
  STA MAP+$100,X
  STA MAP+$200,X
  INX
  BNE .dl_c
  LDA #$20                     ; rows 0-1, 23
  LDX #63
.dl_s:
  STA MAP,X
  CPX #32
  BCS .dl_sn
  STA MAP+$2E0,X
.dl_sn:
  DEX
  BPL .dl_s
  LDA #T_PEEL                  ; the peel: rows 2 and 22, columns 0 and 30 (31 is outside: the apple is symmetric)
  LDX #30
.dl_p:
  STA MAP+2*32,X
  STA MAP+22*32,X
  DEX
  BPL .dl_p
  LDA #$20
  STA MAP+2*32+31
  STA MAP+22*32+31
  LDX #2
.dl_pr:
  STX T0
  JSR ROW_PTRX
  LDA #T_PEEL
  LDY #0
  STA (PTR),Y
  LDY #30
  STA (PTR),Y
  INY
  LDA #$20
  STA (PTR),Y
  LDX T0
  INX
  CPX #23
  BNE .dl_pr
  LDX SLICE                    ; the tunnels: 19 rows x 4 bytes
  LDA SL_LO,X
  STA PTR2
  LDA SL_HI,X
  STA PTR2+1
  LDA #3
  STA T0                       ; row
  LDY #0
.dl_tr:
  LDX T0
  JSR ROW_PTRX
  LDA #1
  STA T1                       ; column
.dl_tb:
  LDA (PTR2),Y
  STA T2
  PHY
  LDX #8
.dl_tk:
  ASL T2
  BCC .dl_tn
  LDY T1
  LDA #T_TUNNEL
  STA (PTR),Y
.dl_tn:
  INC T1
  DEX
  BNE .dl_tk
  PLY
  INY
  LDA T1
  CMP #33
  BCC .dl_tb
  INC T0
  LDA T0
  CMP #22
  BNE .dl_tr
  ; the seeds: column, row, kind, 0 = end
  STZ NSEED
  STZ T3                       ; seed number
.dl_sd:
  LDA (PTR2),Y
  BEQ .dl_v
  STA T1
  INY
  LDA (PTR2),Y
  TAX
  INY
  LDA (PTR2),Y
  INY
  STA T4
  PHY
  JSR SEED_EATEN               ; eaten already (T3)?
  BNE .dl_sx
  JSR ROW_PTRX
  LDY T1
  LDA T4
  CLC
  ADC #T_SEED
  STA (PTR),Y
  INC NSEED
.dl_sx:
  PLY
  INC T3
  BRA .dl_sd
.dl_v:
  JSR PULP_COLS                ; (fresh, not rotten)
  LDA #$00                     ; MAP to the name table
  STA VREG
  LDA #($38 | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDA #<MAP
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDX #3
  LDY #0
.dl_vv:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .dl_vv
  INC PTR+1
  DEX
  BNE .dl_vv
  RTS

; T3 = seed number: A <> 0 if the player ate it already (keeps X, Y)
SEED_EATEN:
  PHX
  LDA T3
  LSR A
  LSR A
  LSR A
  TAX
  LDA T3
  AND #7
  PHY
  TAY
  LDA BITS,Y
  PLY
  AND EATEN,X
  PLX
  CMP #0
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

; the colours of the pulp in the three thirds: fresh (ROTT = 0) or rotten
PULP_COLS:
  LDA #$AB                     ; fresh: yellow; rotten: dark yellow with red spots
  LDY ROTT
  BEQ .pc_c
  LDA #$A6
.pc_c:
  STA T5
  LDX #0
.pc_t:
  LDA #<(T_PULP*8)
  STA VREG
  LDA PULPHI,X
  STA VREG
  LDY #8
  LDA T5
.pc_b:
  STA VDATA
  NOP
  NOP
  DEY
  BNE .pc_b
  INX
  CPX #3
  BNE .pc_t
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

; T6 = column, T7 = row: A = the tile of MAP there
GET_TILE:
  LDX T7
  JSR ROW_PTRX
  LDY T6
  LDA (PTR),Y
  RTS

; SLICE n on row 12, FRESH: and a hint
MSG_SLICE:
  LDA #<TXT_SLICE
  STA TP
  LDA #>TXT_SLICE
  STA TP+1
  JSR PRINT
  LDA SLICE
  INC A
  JMP PUT_NUM

MSG_CLEAR:
  LDX #12
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
;  THE START OF A SLICE (or of a life in it)
; ===============================================================
SLICE_INIT:
  LDA SLICE                    ; speed: by groups of 8 slices, faster in the next rounds
  LSR A
  LSR A
  LSR A
  CLC
  ADC LOOPN
  CMP #3
  BCC .si_g
  LDA #3
.si_g:
  TAX
  LDA STEP_T,X
  STA STEPF
  LDA TCF_T,X
  STA TCFMAX
  STA TCF
  LDA #24
  STA TCELLS
  STZ ROTT
  STZ HONEYT
  STZ GROW
  STZ SUB
  STZ DIR
  STZ SHADE
  LDA #$FF
  STA WANT
  LDA #1
  STA MOVING
  STZ BT                       ; the body: 4 pieces in the den, the head after them
  LDA #4
  STA BH
  LDX #3
.si_b:
  TXA
  INC A
  STA BODY_C,X
  STA T6
  LDA #START_R
  STA BODY_R,X
  STA T7
  PHX
  JSR BODY_TILE
  PLX
  DEX
  BPL .si_b
  LDA #START_C
  STA HC
  LDA #START_R
  STA HR
  ; the worms: from slice 5, more with the slices
  STZ NWORM
  LDX #NWM-1
.si_w:
  STZ W_ON,X
  DEX
  BPL .si_w
  LDA SLICE
  LDX LOOPN
  BNE .si_wn
  CMP #4
  BCC .si_r
  SEC
  SBC #4
.si_wn:
  LSR A
  LSR A
  LSR A
  INC A
  CMP #NWM+1
  BCC .si_wc
  LDA #NWM
.si_wc:
  STA NWORM
  DEC A
  TAX
.si_wp:
  LDA #1
  STA W_ON,X
  LDA WORM_C,X
  STA W_C,X
  LDA #3
  STA W_R,X
  LDA WORM_D,X
  STA W_D,X
  STZ W_SUB,X
  DEX
  BPL .si_wp
.si_r:
  RTS

; T6 / T7: a piece of the body there (the two shades take turns)
BODY_TILE:
  LDA SHADE
  EOR #1
  STA SHADE
  CLC
  ADC #T_BODY
  JMP PUT_TILE


; ===============================================================
;  THE CATERPILLAR CRAWLS
; ===============================================================
CRAWL:
  LDA JOYC                     ; the joystick books the next turn
  AND #$0F
  BEQ .cr_s
  LDX #3
.cr_j:
  LSR A
  BCS .cr_jd
  DEX
  BPL .cr_j
.cr_jd:
  LDA JOYDIR,X
  STA WANT
.cr_s:
  LDA SUB                      ; between two tiles: on
  BEQ .cr_tile
  INC SUB
  LDA SUB
  CMP STEPF
  BCC .cr_r
  STZ SUB
  JMP ARRIVE
.cr_r:
  RTS
.cr_tile:                      ; ---- on a tile: where now?
  LDA WANT
  BMI .cr_ahead
  EOR #2                       ; never straight back
  CMP DIR
  BEQ .cr_nw
  LDA WANT
  JSR OPEN_DIR
  BCC .cr_ahead
  LDA WANT
  CMP DIR
  BEQ .cr_nw
  STA DIR
  LDA #W_TURN
  LDX #2
  JSR SFX_WHISTLE
.cr_nw:
  LDA #$FF
  STA WANT
.cr_ahead:
  LDA DIR
  JSR OPEN_DIR
  BCS .cr_go
  LDA DIR                      ; a wall: a bend turns by itself, two ways wait
  INC A
  AND #3
  STA T0
  JSR OPEN_DIR
  ROL T1
  LDA DIR
  DEC A
  AND #3
  STA T2
  JSR OPEN_DIR
  BCC .cr_one
  LDA T1
  AND #1
  BEQ .cr_two
  STZ MOVING                   ; both ways open: wait for the joystick
  RTS
.cr_two:
  LDA T2
  STA DIR
  BRA .cr_go
.cr_one:
  LDA T1
  AND #1
  BEQ .cr_back
  LDA T0
  STA DIR
  BRA .cr_go
.cr_back:
  LDA DIR                      ; (no way: back)
  EOR #2
  STA DIR
.cr_go:
  LDA #1
  STA MOVING
  LDX DIR                      ; the next tile: the body there = a bite
  LDA HC
  CLC
  ADC DX_T,X
  STA NC
  STA T6
  LDA HR
  CLC
  ADC DY_T,X
  STA NR
  STA T7
  JSR GET_TILE
  CMP #T_BODY
  BCC .cr_mv
  CMP #T_BODY+2
  BCS .cr_mv
  LDA GROW                     ; the end of the tail moves away now: no bite
  BNE .cr_bite
  LDX BT
  LDA BODY_C,X
  CMP NC
  BNE .cr_bite
  LDA BODY_R,X
  CMP NR
  BEQ .cr_mv
.cr_bite:
  LDA #1
  JMP LOSE_NOW
.cr_mv:
  LDA GROW                     ; ---- the tail: it grows, or the last piece goes
  BEQ .cr_tail
  DEC GROW
  BRA .cr_head
.cr_tail:
  JSR TAIL_OFF
.cr_head:
  LDX BH                       ; the tile left by the head becomes body
  LDA HC
  STA BODY_C,X
  STA T6
  LDA HR
  STA BODY_R,X
  STA T7
  INC BH
  JSR BODY_TILE
  LDA NC
  STA HC
  LDA NR
  STA HR
  LDA #1
  STA SUB
  RTS

; the last piece of the tail goes (the tunnel again)
TAIL_OFF:
  LDX BT
  LDA BODY_C,X
  STA T6
  LDA BODY_R,X
  STA T7
  INC BT
  LDA #T_TUNNEL
  JMP PUT_TILE

; A = direction: C = 1 if the tile there is not pulp or peel (keeps nothing)
OPEN_DIR:
  TAX
  LDA HC
  CLC
  ADC DX_T,X
  STA T6
  LDA HR
  CLC
  ADC DY_T,X
  STA T7
  JSR GET_TILE
  CMP #T_PULP
  BEQ .od_n
  CMP #T_PEEL
  BEQ .od_n
  SEC
  RTS
.od_n:
  CLC
  RTS

; the head reached its tile: a seed?
ARRIVE:
  LDA HC
  STA T6
  LDA HR
  STA T7
  JSR GET_TILE
  CMP #T_SEED
  BCC .ar_r
  CMP #T_SEED+4
  BCS .ar_r
  SEC
  SBC #T_SEED
  PHA
  LDA #T_TUNNEL                ; eaten: out of MAP (the head is on it)
  LDY T6
  STA (PTR),Y
  JSR MARK_EATEN
  INC SEEDS_EATEN
  PLA
  BEQ .ar_seed
  CMP #2
  BCC .ar_gold
  BEQ .ar_leaf
  LDA #250                     ; honey: the time stands still
  STA HONEYT
  LDA #W_HONEY
  BRA .ar_snd
.ar_leaf:
  LDX #4                       ; a leaf: 4 pieces shorter (not under 3)
.ar_lf:
  LDA BH
  SEC
  SBC BT
  CMP #4
  BCC .ar_lfe
  PHX
  JSR TAIL_OFF
  PLX
  DEX
  BNE .ar_lf
.ar_lfe:
  LDA #W_LEAF
  BRA .ar_snd
.ar_gold:
  INC GROW
  JSR GROUP
  LDA GOLD_M,X
  TAY
  LDA GOLD_L,X
  JSR ADD_PTS
  LDA #W_GOLD
  BRA .ar_snd
.ar_seed:
  INC GROW
  JSR GROUP
  LDA SEED_L,X
  LDY #0
  JSR ADD_PTS
  LDA #W_SEED
.ar_snd:
  LDX #2
  JSR SFX_WHISTLE
  DEC NSEED                    ; the last seed: the slice is eaten
  BNE .ar_r
  LDA #3
  STA GSTATE
  LDA #60
  STA GT
.ar_r:
  RTS

; X = the group of the slice (0-3) for the points
GROUP:
  LDA SLICE
  LSR A
  LSR A
  LSR A
  CLC
  ADC LOOPN
  CMP #4
  BCC .gr_x
  LDA #3
.gr_x:
  TAX
  RTS

; the seed at HC / HR: its bit in EATEN
MARK_EATEN:
  LDX SLICE
  LDA SL_LO,X
  CLC
  ADC #76
  STA PTR2
  LDA SL_HI,X
  ADC #0
  STA PTR2+1
  LDY #0
  STZ T3
.me_l:
  LDA (PTR2),Y
  BEQ .me_r
  CMP HC
  BNE .me_n
  INY
  LDA (PTR2),Y
  DEY
  CMP HR
  BNE .me_n
  LDA T3
  LSR A
  LSR A
  LSR A
  TAX
  LDA T3
  AND #7
  TAY
  LDA BITS,Y
  ORA EATEN,X
  STA EATEN,X
.me_r:
  RTS
.me_n:
  INY
  INY
  INY
  INC T3
  BRA .me_l

; a life lost now: A = why (1 bite, 2 worm, 3 rot)
LOSE_NOW:
  STA DEATH
  INC LOSTN
  LDA #1
  STA GSTATE
  LDA #100
  STA GT
  LDA #W_BITE
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  THE CLOCK: the time bar, the honey, the rotting apple
; ===============================================================
CLOCK:
  LDA HONEYT
  BEQ .ck_rot
  DEC HONEYT
  RTS
.ck_rot:
  LDA ROTT
  BEQ .ck_t
  DEC ROTT
  BNE .ck_ri
  LDA #3                       ; rotten: a life
  JMP LOSE_NOW
.ck_ri:
  LDA ROTT
  AND #31
  BNE .ck_r
  LDA #W_ROT
  LDX #2
  JMP SFX_WHISTLE
.ck_t:
  DEC TCF
  BNE .ck_r
  LDA TCFMAX
  STA TCF
  LDA #4
  TSB HUDD
  DEC TCELLS
  BNE .ck_r
  LDA #240                     ; the time is up: the apple rots, 4 s left
  STA ROTT
  JSR PULP_COLS
  LDA #W_ROT
  LDX #2
  JMP SFX_WHISTLE
.ck_r:
  RTS


; ===============================================================
;  THE WORMS OF THE APPLE: one tile every 8 frames, a random way at
;  every crossing, never into the body of the caterpillar
; ===============================================================
WORMS:
  LDX #NWM-1
.wo_l:
  LDA W_ON,X
  BEQ .wo_n
  PHX
  JSR WORM_ONE
  PLX
  LDA GSTATE
  BNE .wo_r
.wo_n:
  DEX
  BPL .wo_l
.wo_r:
  RTS

; X = worm
WORM_ONE:
  STX T5
  LDA W_SUB,X
  BEQ .wm_tile
  INC W_SUB,X
  LDA W_SUB,X
  CMP #8
  BCC .wm_hit
  STZ W_SUB,X
  BRA .wm_hit
.wm_tile:                      ; on a tile: the ways ahead, left, right (not the body)
  STZ T4                       ; ways found (bits 0-3 = directions)
  LDA W_D,X
  JSR WORM_WAY
  LDX T5
  LDA W_D,X
  INC A
  AND #3
  JSR WORM_WAY
  LDX T5
  LDA W_D,X
  DEC A
  AND #3
  JSR WORM_WAY
  LDX T5
  LDA T4
  BNE .wm_pick
  LDA W_D,X                    ; nothing: back
  EOR #2
  STA W_D,X
  JSR WORM_WAY
  LDX T5
  LDA T4
  BEQ .wm_hit                  ; (shut in: it waits)
.wm_pick:
  JSR NEXT_RND                 ; a random way among the ones found
  AND #3
  TAY
.wm_try:
  LDA BITS,Y
  AND T4
  BNE .wm_dir
  INY
  TYA
  AND #3
  TAY
  BRA .wm_try
.wm_dir:
  TYA
  STA W_D,X
  LDA W_C,X
  CLC
  ADC DX_T,Y
  STA W_C,X
  LDA W_R,X
  CLC
  ADC DY_T,Y
  STA W_R,X
  LDA #1
  STA W_SUB,X
.wm_hit:                       ; ---- its head against the head of the caterpillar
  LDX T5
  JSR WORM_XY
  LDA T2
  STA T6
  LDA T3
  STA T7
  JSR HEAD_XY
  LDA T2
  SEC
  SBC T6
  CLC
  ADC #10
  CMP #20
  BCS .wm_r
  LDA T3
  SEC
  SBC T7
  CLC
  ADC #10
  CMP #20
  BCS .wm_r
  LDA #2
  JMP LOSE_NOW
.wm_r:
  RTS

; T5 = worm, A = direction: its bit in T4 if the tile there is a tunnel without the body
WORM_WAY:
  STA T0
  TAY
  LDX T5
  LDA W_C,X
  CLC
  ADC DX_T,Y
  STA T6
  LDA W_R,X
  CLC
  ADC DY_T,Y
  STA T7
  JSR GET_TILE
  CMP #T_PULP
  BEQ .ww_r
  CMP #T_PEEL
  BEQ .ww_r
  CMP #T_BODY
  BEQ .ww_r
  CMP #T_BODY+1
  BEQ .ww_r
  LDY T0
  LDA BITS,Y
  TSB T4
.ww_r:
  RTS

; X = worm: T2 / T3 = the top left of its sprite (8 pixels from tile to tile)
WORM_XY:
  LDY W_D,X
  LDA W_SUB,X
  BEQ .wx_z
  LDA #8
  SEC
  SBC W_SUB,X
.wx_z:
  STA T4                       ; how far behind its tile
  LDA W_C,X
  ASL A
  ASL A
  ASL A
  SEC
  SBC #4
  STA T2
  LDA W_R,X
  ASL A
  ASL A
  ASL A
  SEC
  SBC #5
  STA T3
  JMP BACK_OFF

; the head: T2 / T3 = the top left of its sprite, between its two tiles
HEAD_XY:
  LDA SUB
  BEQ .hx_z
  LDA STEPF                    ; (row of the table for this speed)
  ASL A
  ASL A
  ASL A
  CLC
  ADC SUB
  TAY
  LDA OFFT,Y
.hx_z:
  STA T4
  LDA HC
  ASL A
  ASL A
  ASL A
  SEC
  SBC #4
  STA T2
  LDA HR
  ASL A
  ASL A
  ASL A
  SEC
  SBC #5
  STA T3
  LDY DIR
  ; fall into BACK_OFF
; T2 / T3 moved back by T4 pixels against the direction Y
BACK_OFF:
  LDA T4
  BEQ .bo_r
  CPY #0
  BNE .bo_1
  LDA T2
  SEC
  SBC T4
  STA T2
  RTS
.bo_1:
  CPY #1
  BNE .bo_2
  LDA T3
  SEC
  SBC T4
  STA T3
  RTS
.bo_2:
  CPY #2
  BNE .bo_3
  LDA T2
  CLC
  ADC T4
  STA T2
  RTS
.bo_3:
  LDA T3
  CLC
  ADC T4
  STA T3
.bo_r:
  RTS


; ===============================================================
;  SPRITES: the head, the worms
; ===============================================================
BUILD_SAT:
  STZ SPRI
  JSR HEAD_XY
  LDA T2
  STA OX
  LDA T3
  STA OY
  LDA #3
  STA OC
  LDA GSTATE                   ; a life lost: a puff
  CMP #1
  BNE .bs_h
  LDA #15
  STA OC
  LDA #PT_PUFF
  BRA .bs_p
.bs_h:
  LDA DIR                      ; the head: its direction, the mouth chews
  ASL A
  ASL A
  ASL A
  STA T0
  LDA FRAME_CNT
  AND #8
  LSR A
  ORA T0
  CLC
  ADC #PT_HEAD
.bs_p:
  STA ON
  JSR ADD_SPR
  LDX #NWM-1
.bs_w:
  LDA W_ON,X
  BEQ .bs_wn
  PHX
  JSR WORM_XY
  PLX
  LDA T2
  STA OX
  LDA T3
  STA OY
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_WORM1
  STA ON
  LDA #9
  STA OC
  JSR ADD_SPR
.bs_wn:
  DEX
  BPL .bs_w
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

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
;  SCREEN: VRAM, texts, sprites, sound (from ghost & ghust)
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
STEP_T:     .byte 8,6,5,4                      ; frames a step lasts, by group of slices
TCF_T:      .byte 200,175,150,125              ; frames a cell of the time bar lasts (24 cells)
SEED_L:     .byte $10,$20,$30,$40              ; a seed: 10 20 30 40 (BCD)
GOLD_L:     .byte $50,$00,$50,$00              ; the gold seed: 50 100 150 200
GOLD_M:     .byte $00,$01,$01,$02
WORM_C:     .byte 29,1,15                      ; where the worms come in (row 3) and where they go
WORM_D:     .byte 2,0,1
PULPHI:     .byte $63,$6B,$73                  ; colours of the pulp tile in the three thirds (write)
; how far behind its tile the head is: (steps - sub) x 8 / steps, row = frames of a step
OFFT:
  .byte 0,0,0,0,0,0,0,0
  .byte 0,0,0,0,0,0,0,0
  .byte 0,0,0,0,0,0,0,0
  .byte 0,0,0,0,0,0,0,0
  .byte 0,6,4,2,0,0,0,0
  .byte 0,6,4,3,1,0,0,0
  .byte 0,6,5,4,2,1,0,0
  .byte 0,0,0,0,0,0,0,0
  .byte 0,7,6,5,4,3,2,1

; title: the head of the caterpillar, a worm (sprite Y, X, pattern, colour)
TITLE_NS = 2
TITLE_SY:   .byte 103,127
TITLE_SX:   .byte 236,236
TITLE_SN:   .byte PT_HEAD,PT_WORM1
TITLE_SC:   .byte 3,9

TXT_SLICEH: .byte "SLICE "
TXT_PLAYERH: .byte "PLAYER "
TXT_TIMEH:  .byte "TIME "
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
  .byte 9,2,"THE CATERPILLAR NEVER STOPS",0
  .byte 10,2,"EAT THE SEEDS OF THE APPLE",0
  .byte 11,2,"AND NEVER BITE YOUR TAIL",0
  .byte 13,4,T_SEED,"  SEED   ONE MORE PIECE",0
  .byte 14,4,T_SEED+1,"  GOLD   FIVE TIMES",0
  .byte 15,4,T_SEED+2,"  LEAF   FOUR LESS",0
  .byte 16,4,T_SEED+3,"  HONEY  TIME STANDS",0
  .byte 18,4,"WORMS FROM SLICE 5",0
  .byte $FF
TXT_SLICE:
  .byte 12,11,"SLICE ",0,$FF
TXT_CLEAR:
  .byte 12,10,"SLICE EATEN!",0,$FF
TXT_OVER:
  .byte 12,11,"GAME OVER",0,$FF
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
;  GRAPHICS, SLICES AND SOUND TABLES (generated)
; ===============================================================
; WORMER: generated by dev/gen_wormer.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_HEAD = 0
PT_HEADO = 4
PT_HEAD1 = 8
PT_HEADO1 = 12
PT_HEAD2 = 16
PT_HEADO2 = 20
PT_HEAD3 = 24
PT_HEADO3 = 28
PT_WORM1 = 32
PT_WORM2 = 36
PT_PUFF = 40
SPR_LEN = 352
SPR_PAGES = 2
SPRITES:
  .byte $00,$07,$0F,$1F,$3F,$7D,$7C,$7C,$7C,$7C,$7D,$3F,$1F,$0F,$07,$00,$00,$E0,$F0,$F8,$C9,$FE,$FC,$CC,$CC,$FC,$FE,$C9,$F8,$F0,$E0,$00
  .byte $00,$07,$0F,$1F,$3F,$7F,$7F,$7F,$7F,$7F,$7F,$3F,$1F,$0F,$07,$00,$00,$F8,$F8,$F0,$C1,$F2,$F0,$C0,$C0,$F0,$F2,$C1,$F8,$F8,$FC,$00
  .byte $00,$07,$0F,$1F,$3F,$7F,$78,$7C,$7F,$7F,$76,$36,$1F,$07,$04,$08,$00,$E0,$F0,$F8,$FC,$FE,$1E,$3E,$FE,$FE,$6E,$6C,$F8,$E0,$20,$10
  .byte $00,$07,$0F,$1F,$3F,$7F,$7F,$7F,$7F,$7F,$76,$76,$70,$40,$04,$08,$00,$E0,$F0,$F8,$FC,$FE,$FE,$FE,$FE,$FE,$6E,$6E,$06,$00,$20,$10
  .byte $00,$07,$0F,$1F,$93,$7F,$3F,$33,$33,$3F,$7F,$93,$1F,$0F,$07,$00,$00,$E0,$F0,$F8,$FC,$BE,$3E,$3E,$3E,$3E,$BE,$FC,$F8,$F0,$E0,$00
  .byte $00,$3F,$1F,$1F,$83,$4F,$0F,$03,$03,$0F,$4F,$83,$0F,$1F,$1F,$00,$00,$E0,$F0,$F8,$FC,$FE,$FE,$FE,$FE,$FE,$FE,$FC,$F8,$F0,$E0,$00
  .byte $08,$04,$07,$1F,$36,$76,$7F,$7F,$7C,$78,$7F,$3F,$1F,$0F,$07,$00,$10,$20,$E0,$F8,$6C,$6E,$FE,$FE,$3E,$1E,$FE,$FC,$F8,$F0,$E0,$00
  .byte $08,$04,$00,$60,$76,$76,$7F,$7F,$7F,$7F,$7F,$3F,$1F,$0F,$07,$00,$10,$20,$02,$0E,$6E,$6E,$FE,$FE,$FE,$FE,$FE,$FC,$F8,$F0,$E0,$00
  .byte $00,$00,$07,$0F,$1B,$1F,$0F,$03,$1F,$3F,$38,$18,$00,$00,$00,$00,$00,$00,$80,$C0,$40,$E0,$EC,$FE,$9E,$C6,$70,$30,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$02,$07,$37,$7F,$79,$63,$0E,$0C,$00,$00,$00,$00,$00,$00,$E0,$F0,$D8,$F8,$F0,$C0,$F8,$FC,$1C,$18,$00,$00,$00,$00
  .byte $00,$00,$10,$08,$45,$20,$07,$CF,$07,$20,$45,$08,$10,$00,$00,$00,$00,$00,$40,$84,$10,$08,$C0,$E6,$C0,$08,$10,$84,$40,$00,$00,$00

; game tiles 96-107: patterns and colours
TILEP:
  .byte $FF,$DF,$FF,$FB,$FF,$BF,$FF,$F7,$FF,$FE,$FF,$DF,$FF,$FF,$7F,$FF,$00,$00,$18,$3C,$3C,$18,$00,$00,$00,$18,$3C,$7E,$7E,$3C,$18,$00
  .byte $02,$0E,$3E,$7E,$7C,$78,$80,$00,$10,$10,$38,$7C,$7C,$7C,$38,$00,$3C,$7E,$DB,$FF,$FF,$DB,$7E,$3C,$3C,$7E,$FF,$BD,$BD,$FF,$7E,$3C
  .byte $00,$3C,$7E,$DB,$FF,$7E,$3C,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$81,$00,$00,$00,$00,$81,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00
TILEC:
  .byte $AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$86,$86,$86,$86,$86,$86,$86,$86,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $21,$21,$21,$21,$21,$21,$21,$21,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$31,$31,$31,$31,$31,$31,$31,$31,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1
  .byte $31,$31,$31,$31,$31,$31,$31,$31,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$91,$91,$91,$91,$91,$91,$91,$91

; the slices: tunnels (19 rows x 4 bytes, columns 1-29) and the seeds (column, row, kind), 0 = end
SL0:
  .byte $EF,$FF,$FF,$B8,$AA,$0A,$82,$A8,$BB,$FA,$FE,$E8,$88,$82,$08,$88,$FF,$BA,$EF,$F8,$AA,$AA,$AA,$A8,$AB,$AF,$AE,$A8,$AA,$22,$22,$A8
  .byte $FF,$BA,$EF,$F8,$A0,$AA,$A8,$28,$EF,$EF,$BF,$B8,$AA,$22,$22,$A8,$FE,$FF,$FB,$F8,$80,$AA,$A8,$08,$FB,$BA,$EE,$F8,$8A,$02,$02,$88
  .byte $FB,$BA,$EE,$F8,$AA,$AA,$AA,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$07,$01,$0F,$0F,$00,$0D,$0D,$00,$11,$0D,$00,$0A,$03,$00,$14,$03,$00,$03,$0A,$00,$1B,$0A,$00,$01,$14,$00,$1D,$14,$00,$0C,$0F
  .byte $00,$12,$0F,$00,$0D,$14,$00,$11,$14,$00,$09,$13,$00,$15,$13,$00,$0E,$0D,$00,$10,$0D,$00,$05,$0F,$00,$19,$0F,$00,$03,$09,$00,$1B
  .byte $09,$00,$08,$09,$00,$16,$09,$00,$06,$0F,$00,$18,$0F,$00,$00
SL1:
  .byte $FF,$BF,$EF,$F8,$8A,$AA,$AA,$88,$FB,$AF,$AE,$F8,$8A,$A8,$AA,$88,$BB,$EF,$BE,$E8,$A2,$A2,$2A,$28,$AE,$FA,$FB,$A8,$AA,$0A,$82,$A8
  .byte $EB,$FA,$FE,$B8,$2A,$AA,$AA,$A0,$EE,$EF,$BB,$B8,$8A,$A2,$2A,$88,$BF,$FF,$FF,$E8,$AA,$22,$22,$A8,$EB,$BA,$EE,$B8,$A8,$AA,$A8,$A8
  .byte $EF,$AF,$AF,$B8,$A2,$A0,$2A,$28,$FF,$FF,$FF,$F8
  .byte $0F,$12,$01,$0F,$0B,$03,$0B,$04,$00,$13,$04,$00,$0A,$0F,$00,$14,$0F,$00,$01,$0E,$00,$1D,$0E,$00,$01,$14,$00,$1D,$14,$00,$0B,$0E
  .byte $00,$13,$0E,$00,$09,$0F,$00,$15,$0F,$00,$0D,$0F,$00,$11,$0F,$00,$01,$07,$00,$1D,$07,$00,$09,$04,$00,$15,$04,$00,$08,$05,$00,$16
  .byte $05,$00,$05,$11,$00,$19,$11,$00,$0B,$11,$00,$13,$11,$00,$07,$0B,$00,$17,$0B,$00,$00
SL2:
  .byte $FF,$FF,$FF,$F8,$88,$A2,$28,$88,$FB,$BF,$EE,$F8,$AA,$A2,$2A,$A8,$FF,$AF,$AF,$F8,$A8,$AA,$A8,$A8,$AE,$AA,$AB,$A8,$AA,$AA,$AA,$A8
  .byte $BA,$AF,$AA,$E8,$A2,$AA,$AA,$28,$FE,$BA,$EB,$F8,$08,$82,$08,$80,$FF,$BF,$EF,$F8,$80,$AA,$A8,$08,$FE,$BA,$EB,$F8,$A2,$8A,$8A,$28
  .byte $FA,$EF,$BA,$F8,$8A,$2A,$A2,$88,$FF,$FF,$FF,$F8
  .byte $0F,$11,$01,$0F,$03,$03,$0F,$07,$02,$0F,$09,$00,$09,$10,$00,$15,$10,$00,$0C,$03,$00,$12,$03,$00,$07,$06,$00,$17,$06,$00,$07,$0D
  .byte $00,$17,$0D,$00,$01,$12,$00,$1D,$12,$00,$07,$11,$00,$17,$11,$00,$0C,$0F,$00,$12,$0F,$00,$01,$07,$00,$1D,$07,$00,$09,$0B,$00,$15
  .byte $0B,$00,$0B,$07,$00,$13,$07,$00,$0D,$07,$00,$11,$07,$00,$0D,$13,$00,$11,$13,$00,$0D,$15,$00,$11,$15,$00,$00
SL3:
  .byte $FF,$FF,$FF,$F8,$8A,$A0,$2A,$88,$EE,$BF,$EB,$B8,$AA,$82,$0A,$A8,$BA,$FF,$FA,$E8,$A2,$82,$0A,$28,$FB,$BA,$EE,$F8,$AA,$2A,$A2,$A8
  .byte $EE,$EF,$BB,$B8,$22,$AA,$AA,$20,$EF,$AF,$AF,$B8,$AA,$28,$A2,$A8,$FB,$EF,$BE,$F8,$A8,$A2,$28,$A8,$FF,$FF,$FF,$F8,$82,$82,$0A,$08
  .byte $FE,$FF,$FB,$F8,$8A,$82,$0A,$88,$FF,$FF,$FF,$F8
  .byte $0F,$11,$01,$0F,$13,$03,$0F,$0A,$02,$0F,$14,$00,$01,$05,$00,$1D,$05,$00,$03,$08,$00,$1B,$08,$00,$05,$05,$00,$19,$05,$00,$05,$04
  .byte $00,$19,$04,$00,$06,$0B,$00,$18,$0B,$00,$02,$09,$00,$1C,$09,$00,$0D,$03,$00,$11,$03,$00,$0B,$03,$00,$13,$03,$00,$0A,$15,$00,$14
  .byte $15,$00,$03,$06,$00,$1B,$06,$00,$0C,$07,$00,$12,$07,$00,$0C,$05,$00,$12,$05,$00,$07,$0B,$00,$17,$0B,$00,$0B,$13,$00,$13,$13,$00
  .byte $00
SL4:
  .byte $FF,$FF,$FF,$F8,$A8,$82,$08,$A8,$EF,$BF,$EF,$B8,$82,$A2,$2A,$08,$FF,$AF,$AF,$F8,$AA,$2A,$A2,$A8,$AA,$EA,$BA,$A8,$AA,$8A,$8A,$A8
  .byte $EF,$BA,$EF,$B8,$A2,$A2,$2A,$28,$FE,$FF,$FB,$F8,$A0,$A0,$28,$28,$EF,$BF,$EF,$B8,$A8,$8A,$88,$A8,$EE,$FF,$FB,$B8,$A2,$88,$8A,$28
  .byte $AE,$FF,$FB,$A8,$A8,$A2,$28,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$03,$01,$0F,$0D,$03,$0F,$10,$02,$0F,$13,$00,$07,$09,$00,$17,$09,$00,$01,$14,$00,$1D,$14,$00,$05,$08,$00,$19,$08,$00,$09,$12
  .byte $00,$15,$12,$00,$0D,$11,$00,$11,$11,$00,$01,$04,$00,$1D,$04,$00,$0D,$0F,$00,$11,$0F,$00,$0B,$06,$00,$13,$06,$00,$09,$0F,$00,$15
  .byte $0F,$00,$05,$0B,$00,$19,$0B,$00,$01,$12,$00,$1D,$12,$00,$05,$14,$00,$19,$14,$00,$01,$11,$00,$1D,$11,$00,$02,$0D,$00,$1C,$0D,$00
  .byte $03,$0E,$00,$1B,$0E,$00,$00
SL5:
  .byte $FB,$FF,$FE,$F8,$AA,$AA,$AA,$A8,$EF,$AA,$AF,$B8,$80,$2A,$A0,$08,$BF,$AA,$AF,$E8,$A0,$AA,$A8,$28,$AE,$EF,$BB,$A8,$AA,$0A,$82,$A8
  .byte $EF,$FA,$FF,$B8,$88,$A2,$28,$88,$EF,$EF,$BF,$B8,$A8,$28,$A0,$A8,$EF,$FF,$FF,$B8,$A2,$82,$0A,$28,$FB,$BF,$EE,$F8,$AA,$A2,$2A,$A8
  .byte $AE,$BF,$EB,$A8,$A8,$8A,$88,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$05,$01,$0F,$0F,$03,$0F,$12,$02,$0F,$15,$00,$07,$11,$00,$17,$11,$00,$01,$03,$00,$1D,$03,$00,$01,$0E,$00,$1D,$0E,$00,$0B,$0D
  .byte $00,$13,$0D,$00,$01,$0B,$00,$1D,$0B,$00,$04,$03,$00,$1A,$03,$00,$0A,$0B,$00,$14,$0B,$00,$08,$05,$00,$16,$05,$00,$0A,$0F,$00,$14
  .byte $0F,$00,$03,$14,$00,$1B,$14,$00,$03,$13,$00,$1B,$13,$00,$0B,$08,$00,$13,$08,$00,$0A,$0D,$00,$14,$0D,$00,$0D,$0E,$00,$11,$0E,$00
  .byte $09,$14,$00,$15,$14,$00,$0D,$11,$00,$11,$11,$00,$00
SL6:
  .byte $FF,$FF,$FF,$F8,$8A,$8A,$8A,$88,$FE,$BF,$EB,$F8,$28,$A0,$28,$A0,$FF,$AF,$AF,$F8,$82,$AA,$AA,$08,$BF,$FA,$FF,$E8,$A0,$A2,$28,$28
  .byte $BB,$BF,$EE,$E8,$AA,$28,$A2,$A8,$FB,$BF,$EE,$F8,$28,$A2,$28,$A0,$FF,$BF,$EF,$F8,$80,$2A,$A0,$08,$BF,$EF,$BF,$E8,$A8,$28,$A0,$A8
  .byte $EF,$EF,$BF,$B8,$AA,$02,$02,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$03,$01,$0F,$14,$03,$0F,$10,$02,$0F,$04,$00,$09,$07,$00,$15,$07,$00,$08,$03,$00,$16,$03,$00,$05,$11,$00,$19,$11,$00,$07,$07
  .byte $00,$17,$07,$00,$02,$0D,$00,$1C,$0D,$00,$0C,$0F,$00,$12,$0F,$00,$0C,$15,$00,$12,$15,$00,$0D,$0F,$00,$11,$0F,$00,$0E,$15,$00,$10
  .byte $15,$00,$07,$05,$00,$17,$05,$00,$01,$0F,$00,$1D,$0F,$00,$03,$03,$00,$1B,$03,$00,$01,$0D,$00,$1D,$0D,$00,$0E,$13,$00,$10,$13,$00
  .byte $05,$0F,$00,$19,$0F,$00,$04,$0D,$00,$1A,$0D,$00,$05,$13,$00,$19,$13,$00,$00
SL7:
  .byte $FE,$FF,$FB,$F8,$AA,$A0,$2A,$A8,$EE,$BF,$EB,$B8,$A8,$8A,$88,$A8,$BB,$EF,$BE,$E8,$A2,$28,$A2,$28,$AF,$FF,$FF,$A8,$AA,$02,$02,$A8
  .byte $BE,$FA,$FB,$E8,$A8,$8A,$88,$A8,$EB,$BF,$EE,$B8,$8A,$2A,$A2,$88,$FA,$FA,$FA,$F8,$A2,$8A,$8A,$28,$FE,$BF,$EB,$F8,$88,$A0,$28,$88
  .byte $EE,$FF,$FB,$B8,$AA,$A2,$2A,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$0D,$01,$0F,$05,$03,$0F,$11,$02,$0F,$0B,$00,$09,$09,$00,$15,$09,$00,$07,$04,$00,$17,$04,$00,$09,$12,$00,$15,$12,$00,$0E,$03
  .byte $00,$10,$03,$00,$03,$11,$00,$1B,$11,$00,$0E,$07,$00,$10,$07,$00,$0A,$07,$00,$14,$07,$00,$0B,$0D,$00,$13,$0D,$00,$08,$0D,$00,$16
  .byte $0D,$00,$03,$05,$00,$1B,$05,$00,$02,$05,$00,$1C,$05,$00,$01,$12,$00,$1D,$12,$00,$02,$0D,$00,$1C,$0D,$00,$0B,$15,$00,$13,$15,$00
  .byte $07,$14,$00,$17,$14,$00,$04,$11,$00,$1A,$11,$00,$0C,$11,$00,$12,$11,$00,$09,$10,$00,$15,$10,$00,$00
SL8:
  .byte $FB,$FF,$FE,$F8,$AA,$88,$8A,$A8,$EE,$FF,$FB,$B8,$A8,$2A,$A0,$A8,$BF,$EF,$BF,$E8,$A0,$02,$00,$28,$BF,$FA,$FF,$E8,$82,$0A,$82,$08
  .byte $FF,$EF,$BF,$F8,$80,$22,$20,$08,$FF,$AF,$AF,$F8,$0A,$A8,$AA,$80,$EF,$EF,$BF,$B8,$A2,$AA,$AA,$28,$BB,$BF,$EE,$E8,$88,$2A,$A0,$88
  .byte $EE,$EF,$BB,$B8,$A2,$88,$8A,$28,$FF,$FF,$FF,$F8
  .byte $0F,$11,$01,$0F,$0B,$03,$0F,$03,$02,$0F,$06,$00,$07,$07,$00,$17,$07,$00,$07,$13,$00,$17,$13,$00,$05,$0B,$00,$19,$0B,$00,$0C,$09
  .byte $00,$12,$09,$00,$0E,$03,$00,$10,$03,$00,$03,$13,$00,$1B,$13,$00,$01,$06,$00,$1D,$06,$00,$01,$0F,$00,$1D,$0F,$00,$0E,$13,$00,$10
  .byte $13,$00,$0B,$15,$00,$13,$15,$00,$01,$12,$00,$1D,$12,$00,$0A,$15,$00,$14,$15,$00,$0D,$0A,$00,$11,$0A,$00,$05,$09,$00,$19,$09,$00
  .byte $0B,$06,$00,$13,$06,$00,$04,$11,$00,$1A,$11,$00,$06,$13,$00,$18,$13,$00,$0E,$0D,$00,$10,$0D,$00,$07,$05,$00,$17,$05,$00,$00
SL9:
  .byte $FF,$FF,$FF,$F8,$AA,$82,$0A,$A8,$EE,$BF,$EB,$B8,$A2,$A2,$2A,$28,$BE,$BF,$EB,$E8,$82,$AA,$AA,$08,$BF,$AA,$AF,$E8,$A2,$AA,$AA,$28
  .byte $FE,$EA,$BB,$F8,$22,$0A,$82,$20,$FF,$FF,$FF,$F8,$8A,$8A,$8A,$88,$BB,$FA,$FE,$E8,$A2,$2A,$A2,$28,$BF,$AF,$AF,$E8,$88,$A8,$A8,$88
  .byte $FB,$BF,$EE,$F8,$8A,$8A,$8A,$88,$FF,$FF,$FF,$F8
  .byte $0F,$06,$01,$0F,$09,$03,$0F,$0B,$02,$0F,$07,$00,$0B,$0D,$00,$13,$0D,$00,$0D,$14,$00,$11,$14,$00,$0D,$0A,$00,$11,$0A,$00,$09,$0A
  .byte $00,$15,$0A,$00,$09,$14,$00,$15,$14,$00,$04,$0D,$00,$1A,$0D,$00,$01,$0E,$00,$1D,$0E,$00,$06,$03,$00,$18,$03,$00,$07,$13,$00,$17
  .byte $13,$00,$07,$0C,$00,$17,$0C,$00,$06,$0B,$00,$18,$0B,$00,$08,$11,$00,$16,$11,$00,$02,$13,$00,$1C,$13,$00,$03,$0F,$00,$1B,$0F,$00
  .byte $09,$11,$00,$15,$11,$00,$0D,$11,$00,$11,$11,$00,$08,$0D,$00,$16,$0D,$00,$0E,$03,$00,$10,$03,$00,$09,$0D,$00,$15,$0D,$00,$08,$09
  .byte $00,$16,$09,$00,$00
SL10:
  .byte $FF,$EF,$BF,$F8,$80,$28,$A0,$08,$FE,$EF,$BB,$F8,$8A,$82,$0A,$88,$EB,$BF,$EE,$B8,$AA,$20,$22,$A8,$EA,$FF,$FA,$B8,$2A,$8A,$8A,$A0
  .byte $EA,$EA,$BA,$B8,$AA,$2A,$A2,$A8,$EB,$BA,$EE,$B8,$A8,$A2,$28,$A8,$FE,$FF,$FB,$F8,$8A,$22,$22,$88,$EF,$EF,$BF,$B8,$AA,$8A,$8A,$A8
  .byte $BA,$EA,$BA,$E8,$AA,$AA,$AA,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$0A,$01,$0F,$13,$03,$0F,$0F,$02,$0F,$0E,$00,$03,$0B,$00,$1B,$0B,$00,$03,$13,$00,$1B,$13,$00,$0C,$07,$00,$12,$07,$00,$01,$12
  .byte $00,$1D,$12,$00,$0D,$0C,$00,$11,$0C,$00,$09,$0A,$00,$15,$0A,$00,$0B,$11,$00,$13,$11,$00,$0B,$05,$00,$13,$05,$00,$0C,$09,$00,$12
  .byte $09,$00,$03,$07,$00,$1B,$07,$00,$0B,$08,$00,$13,$08,$00,$01,$0E,$00,$1D,$0E,$00,$09,$12,$00,$15,$12,$00,$01,$09,$00,$1D,$09,$00
  .byte $0A,$15,$00,$14,$15,$00,$0A,$13,$00,$14,$13,$00,$0C,$15,$00,$12,$15,$00,$0A,$0B,$00,$14,$0B,$00,$05,$0D,$00,$19,$0D,$00,$0A,$0F
  .byte $00,$14,$0F,$00,$0D,$14,$00,$11,$14,$00,$00
SL11:
  .byte $FE,$FF,$FB,$F8,$AA,$88,$8A,$A8,$AF,$EF,$BF,$A8,$A8,$A2,$28,$A8,$EE,$FA,$FB,$B8,$8A,$8A,$8A,$88,$FE,$EA,$BB,$F8,$02,$AA,$AA,$00
  .byte $EF,$AF,$AF,$B8,$A8,$28,$A0,$A8,$BF,$FF,$FF,$E8,$80,$A2,$28,$08,$BB,$BA,$EE,$E8,$AA,$0A,$82,$A8,$BB,$EA,$BE,$E8,$A0,$2A,$A0,$28
  .byte $BF,$EF,$BF,$E8,$A8,$2A,$A0,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$11,$01,$0F,$08,$03,$0F,$0D,$02,$0F,$09,$00,$07,$10,$00,$17,$10,$00,$09,$0D,$00,$15,$0D,$00,$08,$0F,$00,$16,$0F,$00,$0B,$0B
  .byte $00,$13,$0B,$00,$01,$0B,$00,$1D,$0B,$00,$0D,$07,$00,$11,$07,$00,$01,$0F,$00,$1D,$0F,$00,$06,$13,$00,$18,$13,$00,$03,$13,$00,$1B
  .byte $13,$00,$01,$10,$00,$1D,$10,$00,$03,$06,$00,$1B,$06,$00,$03,$07,$00,$1B,$07,$00,$02,$0B,$00,$1C,$0B,$00,$0E,$0B,$00,$10,$0B,$00
  .byte $0D,$0B,$00,$11,$0B,$00,$04,$09,$00,$1A,$09,$00,$06,$0B,$00,$18,$0B,$00,$02,$09,$00,$1C,$09,$00,$07,$08,$00,$17,$08,$00,$01,$06
  .byte $00,$1D,$06,$00,$01,$0D,$00,$1D,$0D,$00,$0D,$12,$00,$11,$12,$00,$00
SL12:
  .byte $EF,$FF,$FF,$B8,$AA,$0A,$82,$A8,$AF,$BA,$EF,$A8,$A8,$AA,$A8,$A8,$AF,$AF,$AF,$A8,$A2,$AA,$AA,$28,$AE,$FA,$FB,$A8,$A8,$2A,$A0,$A8
  .byte $BB,$EF,$BE,$E8,$82,$2A,$A2,$08,$BB,$AF,$AE,$E8,$A8,$A8,$A8,$A8,$EB,$EF,$BE,$B8,$8A,$02,$02,$88,$EE,$FF,$FB,$B8,$A2,$A2,$2A,$28
  .byte $EF,$BF,$EF,$B8,$AA,$22,$22,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$0C,$01,$0F,$13,$03,$0F,$0D,$02,$0F,$0B,$00,$08,$0F,$00,$16,$0F,$00,$01,$03,$00,$1D,$03,$00,$03,$12,$00,$1B,$12,$00,$09,$05
  .byte $00,$15,$05,$00,$09,$09,$00,$15,$09,$00,$07,$0D,$00,$17,$0D,$00,$02,$0F,$00,$1C,$0F,$00,$0A,$15,$00,$14,$15,$00,$0E,$0D,$00,$10
  .byte $0D,$00,$0B,$0D,$00,$13,$0D,$00,$06,$03,$00,$18,$03,$00,$0E,$07,$00,$10,$07,$00,$0E,$13,$00,$10,$13,$00,$0C,$05,$00,$12,$05,$00
  .byte $03,$08,$00,$1B,$08,$00,$01,$04,$00,$1D,$04,$00,$01,$14,$00,$1D,$14,$00,$0C,$13,$00,$12,$13,$00,$07,$04,$00,$17,$04,$00,$0B,$05
  .byte $00,$13,$05,$00,$0B,$14,$00,$13,$14,$00,$0B,$06,$00,$13,$06,$00,$0C,$11,$00,$12,$11,$00,$00
SL13:
  .byte $FF,$BF,$EF,$F8,$A8,$A2,$28,$A8,$EF,$BA,$EF,$B8,$0A,$0A,$82,$80,$FA,$EA,$BA,$F8,$82,$AA,$AA,$08,$FF,$FA,$FF,$F8,$28,$02,$00,$A0
  .byte $EB,$BF,$EE,$B8,$AA,$A0,$2A,$A8,$AE,$FF,$FB,$A8,$A8,$82,$08,$A8,$FF,$FF,$FF,$F8,$8A,$00,$02,$88,$EE,$FF,$FB,$B8,$AA,$8A,$8A,$A8
  .byte $AA,$FF,$FA,$A8,$AA,$A2,$2A,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$06,$01,$0F,$11,$03,$0F,$13,$02,$0F,$0F,$00,$05,$04,$00,$19,$04,$00,$07,$13,$00,$17,$13,$00,$02,$03,$00,$1C,$03,$00,$07,$09
  .byte $00,$17,$09,$00,$0E,$15,$00,$10,$15,$00,$01,$0B,$00,$1D,$0B,$00,$07,$0C,$00,$17,$0C,$00,$03,$0C,$00,$1B,$0C,$00,$0C,$0B,$00,$12
  .byte $0B,$00,$04,$0F,$00,$1A,$0F,$00,$08,$09,$00,$16,$09,$00,$09,$0E,$00,$15,$0E,$00,$02,$11,$00,$1C,$11,$00,$05,$14,$00,$19,$14,$00
  .byte $09,$0C,$00,$15,$0C,$00,$01,$07,$00,$1D,$07,$00,$01,$08,$00,$1D,$08,$00,$01,$14,$00,$1D,$14,$00,$03,$0B,$00,$1B,$0B,$00,$02,$0B
  .byte $00,$1C,$0B,$00,$0A,$11,$00,$14,$11,$00,$09,$11,$00,$15,$11,$00,$0E,$0F,$00,$10,$0F,$00,$07,$10,$00,$17,$10,$00,$00
SL14:
  .byte $EF,$FF,$FF,$B8,$A8,$82,$08,$A8,$BB,$BA,$EE,$E8,$82,$2A,$A2,$08,$FF,$EF,$BF,$F8,$8A,$8A,$8A,$88,$BE,$BA,$EB,$E8,$A8,$A2,$28,$A8
  .byte $EF,$BF,$EF,$B8,$A8,$02,$00,$A8,$EB,$FF,$FE,$B8,$2A,$0A,$82,$A0,$EB,$EF,$BE,$B8,$88,$A0,$28,$88,$FB,$EF,$BE,$F8,$2A,$0A,$82,$A0
  .byte $EB,$FA,$FE,$B8,$A8,$8A,$88,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$06,$01,$0F,$0F,$03,$0F,$0C,$02,$0F,$11,$00,$06,$0B,$00,$18,$0B,$00,$07,$07,$00,$17,$07,$00,$01,$14,$00,$1D,$14,$00,$05,$0F
  .byte $00,$19,$0F,$00,$0E,$0F,$00,$10,$0F,$00,$01,$08,$00,$1D,$08,$00,$01,$04,$00,$1D,$04,$00,$0C,$0D,$00,$12,$0D,$00,$0B,$10,$00,$13
  .byte $10,$00,$01,$05,$00,$1D,$05,$00,$03,$0D,$00,$1B,$0D,$00,$02,$07,$00,$1C,$07,$00,$05,$11,$00,$19,$11,$00,$0D,$0D,$00,$11,$0D,$00
  .byte $09,$0D,$00,$15,$0D,$00,$03,$03,$00,$1B,$03,$00,$01,$09,$00,$1D,$09,$00,$0D,$11,$00,$11,$11,$00,$09,$09,$00,$15,$09,$00,$0D,$05
  .byte $00,$11,$05,$00,$02,$0B,$00,$1C,$0B,$00,$01,$03,$00,$1D,$03,$00,$0D,$0E,$00,$11,$0E,$00,$0D,$0F,$00,$11,$0F,$00,$05,$0A,$00,$19
  .byte $0A,$00,$00
SL15:
  .byte $FF,$FF,$FF,$F8,$8A,$82,$0A,$88,$BB,$EF,$BE,$E8,$A0,$28,$A0,$28,$FE,$EF,$BB,$F8,$A2,$8A,$8A,$28,$BA,$EA,$BA,$E8,$AA,$2A,$A2,$A8
  .byte $EE,$EF,$BB,$B8,$AA,$A8,$AA,$A8,$BB,$BF,$EE,$E8,$82,$8A,$8A,$08,$BE,$FA,$FB,$E8,$A8,$22,$20,$A8,$EF,$EF,$BF,$B8,$AA,$0A,$82,$A8
  .byte $FE,$FF,$FB,$F8,$A8,$82,$08,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$0E,$01,$0F,$12,$03,$0F,$10,$02,$0F,$15,$00,$0D,$12,$00,$11,$12,$00,$03,$0D,$00,$1B,$0D,$00,$03,$11,$00,$1B,$11,$00,$0D,$08
  .byte $00,$11,$08,$00,$09,$0E,$00,$15,$0E,$00,$03,$08,$00,$1B,$08,$00,$0D,$0D,$00,$11,$0D,$00,$0E,$05,$00,$10,$05,$00,$06,$03,$00,$18
  .byte $03,$00,$03,$13,$00,$1B,$13,$00,$01,$09,$00,$1D,$09,$00,$07,$0C,$00,$17,$0C,$00,$06,$07,$00,$18,$07,$00,$02,$11,$00,$1C,$11,$00
  .byte $09,$03,$00,$15,$03,$00,$05,$05,$00,$19,$05,$00,$02,$13,$00,$1C,$13,$00,$07,$0A,$00,$17,$0A,$00,$0C,$03,$00,$12,$03,$00,$0C,$0F
  .byte $00,$12,$0F,$00,$09,$07,$00,$15,$07,$00,$02,$0B,$00,$1C,$0B,$00,$0C,$0D,$00,$12,$0D,$00,$07,$0F,$00,$17,$0F,$00,$09,$05,$00,$15
  .byte $05,$00,$01,$0D,$00,$1D,$0D,$00,$00
SL16:
  .byte $FF,$BF,$EF,$F8,$88,$AA,$A8,$88,$EB,$AA,$AE,$B8,$AA,$AA,$AA,$A8,$BE,$EF,$BB,$E8,$80,$08,$80,$08,$FF,$FF,$FF,$F8,$22,$2A,$A2,$20
  .byte $EE,$EA,$BB,$B8,$A8,$8A,$88,$A8,$BB,$BA,$EE,$E8,$A2,$A2,$2A,$28,$BA,$EF,$BA,$E8,$8A,$0A,$82,$88,$BB,$FA,$FE,$E8,$A0,$02,$00,$28
  .byte $EF,$FF,$FF,$B8,$A8,$A2,$28,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$13,$01,$0F,$10,$03,$0F,$0A,$02,$0F,$0F,$00,$04,$0F,$00,$1A,$0F,$00,$04,$11,$00,$1A,$11,$00,$01,$0F,$00,$1D,$0F,$00,$0B,$09
  .byte $00,$13,$09,$00,$02,$05,$00,$1C,$05,$00,$0D,$07,$00,$11,$07,$00,$01,$0D,$00,$1D,$0D,$00,$0C,$0D,$00,$12,$0D,$00,$0A,$15,$00,$14
  .byte $15,$00,$0D,$0F,$00,$11,$0F,$00,$09,$07,$00,$15,$07,$00,$05,$0F,$00,$19,$0F,$00,$0A,$09,$00,$14,$09,$00,$0D,$06,$00,$11,$06,$00
  .byte $07,$05,$00,$17,$05,$00,$06,$13,$00,$18,$13,$00,$0B,$04,$00,$13,$04,$00,$0D,$03,$00,$11,$03,$00,$04,$09,$00,$1A,$09,$00,$0D,$04
  .byte $00,$11,$04,$00,$03,$0A,$00,$1B,$0A,$00,$06,$03,$00,$18,$03,$00,$01,$06,$00,$1D,$06,$00,$0D,$0D,$00,$11,$0D,$00,$0D,$13,$00,$11
  .byte $13,$00,$01,$14,$00,$1D,$14,$00,$00
SL17:
  .byte $FE,$FF,$FB,$F8,$A2,$82,$0A,$28,$FA,$FF,$FA,$F8,$AA,$08,$82,$A8,$EB,$FF,$FE,$B8,$2A,$A2,$2A,$A0,$EF,$EF,$BF,$B8,$A8,$0A,$80,$A8
  .byte $BF,$EF,$BF,$E8,$80,$28,$A0,$08,$FF,$AF,$AF,$F8,$A2,$A2,$2A,$28,$EE,$BA,$EB,$B8,$8A,$8A,$8A,$88,$FB,$BF,$EE,$F8,$20,$AA,$A8,$20
  .byte $EF,$BF,$EF,$B8,$88,$20,$20,$88,$FF,$FF,$FF,$F8
  .byte $0F,$09,$01,$0F,$12,$03,$0F,$10,$02,$0F,$13,$00,$0B,$0C,$00,$13,$0C,$00,$0A,$03,$00,$14,$03,$00,$0C,$15,$00,$12,$15,$00,$01,$06
  .byte $00,$1D,$06,$00,$09,$03,$00,$15,$03,$00,$06,$09,$00,$18,$09,$00,$05,$0D,$00,$19,$0D,$00,$07,$05,$00,$17,$05,$00,$0B,$0B,$00,$13
  .byte $0B,$00,$0E,$13,$00,$10,$13,$00,$09,$0E,$00,$15,$0E,$00,$07,$08,$00,$17,$08,$00,$03,$13,$00,$1B,$13,$00,$05,$14,$00,$19,$14,$00
  .byte $07,$09,$00,$17,$09,$00,$0E,$09,$00,$10,$09,$00,$08,$07,$00,$16,$07,$00,$05,$11,$00,$19,$11,$00,$07,$04,$00,$17,$04,$00,$03,$0A
  .byte $00,$1B,$0A,$00,$0E,$11,$00,$10,$11,$00,$07,$06,$00,$17,$06,$00,$03,$11,$00,$1B,$11,$00,$0E,$0D,$00,$10,$0D,$00,$03,$0D,$00,$1B
  .byte $0D,$00,$03,$04,$00,$1B,$04,$00,$00
SL18:
  .byte $EF,$FF,$FF,$B8,$AA,$28,$A2,$A8,$EB,$EF,$BE,$B8,$A8,$8A,$88,$A8,$AE,$FA,$FB,$A8,$AA,$82,$0A,$A8,$BF,$BF,$EF,$E8,$80,$22,$20,$08
  .byte $FF,$EF,$BF,$F8,$80,$08,$80,$08,$FE,$EF,$BB,$F8,$AA,$AA,$AA,$A8,$EB,$AF,$AE,$B8,$28,$2A,$A0,$A0,$FB,$EA,$BE,$F8,$8A,$0A,$82,$88
  .byte $FA,$EA,$BA,$F8,$A2,$AA,$AA,$28,$FF,$FF,$FF,$F8
  .byte $0F,$0E,$01,$0F,$0A,$03,$0F,$13,$02,$0F,$06,$00,$0B,$07,$00,$13,$07,$00,$04,$0B,$00,$1A,$0B,$00,$0D,$09,$00,$11,$09,$00,$07,$07
  .byte $00,$17,$07,$00,$02,$03,$00,$1C,$03,$00,$07,$0E,$00,$17,$0E,$00,$09,$03,$00,$15,$03,$00,$0D,$0E,$00,$11,$0E,$00,$0C,$15,$00,$12
  .byte $15,$00,$03,$09,$00,$1B,$09,$00,$0C,$03,$00,$12,$03,$00,$05,$11,$00,$19,$11,$00,$0B,$05,$00,$13,$05,$00,$07,$04,$00,$17,$04,$00
  .byte $0D,$10,$00,$11,$10,$00,$03,$05,$00,$1B,$05,$00,$0B,$03,$00,$13,$03,$00,$09,$08,$00,$15,$08,$00,$0D,$14,$00,$11,$14,$00,$01,$14
  .byte $00,$1D,$14,$00,$07,$09,$00,$17,$09,$00,$02,$0B,$00,$1C,$0B,$00,$02,$0D,$00,$1C,$0D,$00,$01,$11,$00,$1D,$11,$00,$04,$0D,$00,$1A
  .byte $0D,$00,$0B,$0E,$00,$13,$0E,$00,$00
SL19:
  .byte $FB,$FF,$FE,$F8,$8A,$8A,$8A,$88,$BA,$FF,$FA,$E8,$AA,$02,$02,$A8,$BA,$FF,$FA,$E8,$AA,$88,$8A,$A8,$EA,$FF,$FA,$B8,$AA,$82,$0A,$A8
  .byte $EE,$EF,$BB,$B8,$82,$2A,$A2,$08,$FA,$FA,$FA,$F8,$AA,$82,$0A,$A8,$EA,$EF,$BA,$B8,$0A,$AA,$AA,$80,$FB,$AA,$AE,$F8,$82,$2A,$A2,$08
  .byte $EE,$EA,$BB,$B8,$AA,$8A,$8A,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$07,$01,$0F,$0F,$03,$0F,$0E,$02,$0F,$0D,$00,$07,$13,$00,$17,$13,$00,$0B,$15,$00,$13,$15,$00,$07,$0A,$00,$17,$0A,$00,$0D,$04
  .byte $00,$11,$04,$00,$09,$04,$00,$15,$04,$00,$0D,$09,$00,$11,$09,$00,$0A,$07,$00,$14,$07,$00,$0E,$07,$00,$10,$07,$00,$0E,$0B,$00,$10
  .byte $0B,$00,$09,$0F,$00,$15,$0F,$00,$05,$05,$00,$19,$05,$00,$05,$0A,$00,$19,$0A,$00,$01,$03,$00,$1D,$03,$00,$0E,$15,$00,$10,$15,$00
  .byte $0B,$13,$00,$13,$13,$00,$03,$07,$00,$1B,$07,$00,$07,$08,$00,$17,$08,$00,$05,$0D,$00,$19,$0D,$00,$02,$0B,$00,$1C,$0B,$00,$07,$12
  .byte $00,$17,$12,$00,$05,$0B,$00,$19,$0B,$00,$0B,$07,$00,$13,$07,$00,$0B,$11,$00,$13,$11,$00,$08,$03,$00,$16,$03,$00,$01,$11,$00,$1D
  .byte $11,$00,$0D,$0C,$00,$11,$0C,$00,$00
SL20:
  .byte $FF,$FF,$FF,$F8,$AA,$20,$22,$A8,$FB,$FF,$FE,$F8,$A8,$82,$08,$A8,$EF,$EF,$BF,$B8,$88,$2A,$A0,$88,$EF,$EA,$BF,$B8,$AA,$2A,$A2,$A8
  .byte $AB,$BF,$EE,$A8,$A8,$8A,$88,$A8,$AE,$EA,$BB,$A8,$AA,$2A,$A2,$A8,$EF,$BA,$EF,$B8,$A2,$8A,$8A,$28,$BE,$FF,$FB,$E8,$8A,$02,$02,$88
  .byte $BA,$FF,$FA,$E8,$A2,$80,$0A,$28,$FF,$FF,$FF,$F8
  .byte $0F,$0D,$01,$0F,$0E,$03,$0F,$06,$02,$0F,$0F,$00,$07,$0B,$00,$17,$0B,$00,$01,$14,$00,$1D,$14,$00,$02,$05,$00,$1C,$05,$00,$0C,$0B
  .byte $00,$12,$0B,$00,$08,$07,$00,$16,$07,$00,$01,$06,$00,$1D,$06,$00,$08,$0F,$00,$16,$0F,$00,$09,$06,$00,$15,$06,$00,$09,$13,$00,$15
  .byte $13,$00,$05,$03,$00,$19,$03,$00,$09,$03,$00,$15,$03,$00,$01,$0D,$00,$1D,$0D,$00,$05,$0B,$00,$19,$0B,$00,$0A,$0D,$00,$14,$0D,$00
  .byte $05,$0D,$00,$19,$0D,$00,$0B,$13,$00,$13,$13,$00,$05,$05,$00,$19,$05,$00,$0C,$0F,$00,$12,$0F,$00,$05,$0E,$00,$19,$0E,$00,$04,$11
  .byte $00,$1A,$11,$00,$03,$10,$00,$1B,$10,$00,$0C,$03,$00,$12,$03,$00,$03,$14,$00,$1B,$14,$00,$01,$09,$00,$1D,$09,$00,$0D,$11,$00,$11
  .byte $11,$00,$08,$05,$00,$16,$05,$00,$00
SL21:
  .byte $EF,$BF,$EF,$B8,$AA,$A2,$2A,$A8,$EA,$EF,$BA,$B8,$AA,$08,$82,$A8,$FB,$FF,$FE,$F8,$82,$2A,$A2,$08,$EF,$BF,$EF,$B8,$28,$80,$08,$A0
  .byte $FF,$FF,$FF,$F8,$80,$82,$08,$08,$EE,$BF,$EB,$B8,$AA,$A2,$2A,$A8,$AB,$AF,$AE,$A8,$A8,$AA,$A8,$A8,$AF,$AA,$AF,$A8,$AA,$AA,$AA,$A8
  .byte $AB,$AF,$AE,$A8,$A8,$A8,$A8,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$11,$01,$0F,$0C,$03,$0F,$13,$02,$0F,$12,$00,$0B,$15,$00,$13,$15,$00,$01,$06,$00,$1D,$06,$00,$0E,$0F,$00,$10,$0F,$00,$03,$05
  .byte $00,$1B,$05,$00,$07,$13,$00,$17,$13,$00,$03,$0F,$00,$1B,$0F,$00,$05,$0D,$00,$19,$0D,$00,$09,$0F,$00,$15,$0F,$00,$08,$0F,$00,$16
  .byte $0F,$00,$0B,$05,$00,$13,$05,$00,$08,$09,$00,$16,$09,$00,$07,$04,$00,$17,$04,$00,$0B,$0D,$00,$13,$0D,$00,$09,$07,$00,$15,$07,$00
  .byte $0D,$0F,$00,$11,$0F,$00,$0C,$09,$00,$12,$09,$00,$05,$06,$00,$19,$06,$00,$07,$0F,$00,$17,$0F,$00,$03,$12,$00,$1B,$12,$00,$03,$07
  .byte $00,$1B,$07,$00,$05,$03,$00,$19,$03,$00,$07,$11,$00,$17,$11,$00,$07,$07,$00,$17,$07,$00,$02,$07,$00,$1C,$07,$00,$02,$0D,$00,$1C
  .byte $0D,$00,$0A,$05,$00,$14,$05,$00,$00
SL22:
  .byte $FF,$FF,$FF,$F8,$AA,$8A,$8A,$A8,$AB,$FA,$FE,$A8,$A8,$02,$00,$A8,$AE,$FF,$FB,$A8,$A2,$88,$8A,$28,$FA,$EF,$BA,$F8,$0A,$22,$22,$80
  .byte $FB,$EF,$BE,$F8,$88,$0A,$80,$88,$BF,$FA,$FF,$E8,$AA,$02,$02,$A8,$FB,$EF,$BE,$F8,$AA,$AA,$AA,$A8,$EE,$BA,$EB,$B8,$A0,$82,$08,$28
  .byte $AE,$FF,$FB,$A8,$AA,$A2,$2A,$A8,$FF,$FF,$FF,$F8
  .byte $0F,$03,$01,$0F,$09,$03,$0F,$0D,$02,$0F,$15,$00,$0B,$0F,$00,$13,$0F,$00,$0B,$0D,$00,$13,$0D,$00,$03,$12,$00,$1B,$12,$00,$04,$0B
  .byte $00,$1A,$0B,$00,$0B,$14,$00,$13,$14,$00,$06,$0D,$00,$18,$0D,$00,$0B,$03,$00,$13,$03,$00,$0D,$07,$00,$11,$07,$00,$0A,$07,$00,$14
  .byte $07,$00,$07,$05,$00,$17,$05,$00,$0C,$13,$00,$12,$13,$00,$0A,$05,$00,$14,$05,$00,$03,$13,$00,$1B,$13,$00,$07,$10,$00,$17,$10,$00
  .byte $0C,$11,$00,$12,$11,$00,$0B,$15,$00,$13,$15,$00,$05,$13,$00,$19,$13,$00,$07,$0F,$00,$17,$0F,$00,$07,$0E,$00,$17,$0E,$00,$0B,$07
  .byte $00,$13,$07,$00,$01,$07,$00,$1D,$07,$00,$09,$11,$00,$15,$11,$00,$01,$03,$00,$1D,$03,$00,$05,$0C,$00,$19,$0C,$00,$01,$06,$00,$1D
  .byte $06,$00,$03,$04,$00,$1B,$04,$00,$00
SL23:
  .byte $FF,$FF,$FF,$F8,$A2,$00,$02,$28,$FE,$FF,$FB,$F8,$88,$A2,$28,$88,$FF,$BA,$EF,$F8,$A2,$8A,$8A,$28,$EF,$FA,$FF,$B8,$2A,$02,$02,$A0
  .byte $FE,$EF,$BB,$F8,$A0,$A8,$A8,$28,$EE,$AF,$AB,$B8,$AA,$AA,$AA,$A8,$BB,$AF,$AE,$E8,$A0,$22,$20,$28,$BF,$BF,$EF,$E8,$80,$82,$08,$08
  .byte $FF,$BF,$EF,$F8,$8A,$20,$22,$88,$FF,$FF,$FF,$F8
  .byte $0F,$12,$01,$0F,$0F,$03,$0F,$07,$02,$0F,$0B,$00,$0D,$09,$00,$11,$09,$00,$05,$05,$00,$19,$05,$00,$06,$07,$00,$18,$07,$00,$07,$03
  .byte $00,$17,$03,$00,$05,$14,$00,$19,$14,$00,$01,$04,$00,$1D,$04,$00,$0B,$0B,$00,$13,$0B,$00,$0D,$0E,$00,$11,$0E,$00,$0C,$09,$00,$12
  .byte $09,$00,$0A,$0B,$00,$14,$0B,$00,$03,$07,$00,$1B,$07,$00,$03,$0B,$00,$1B,$0B,$00,$07,$0E,$00,$17,$0E,$00,$0C,$05,$00,$12,$05,$00
  .byte $03,$0D,$00,$1B,$0D,$00,$0D,$07,$00,$11,$07,$00,$01,$0C,$00,$1D,$0C,$00,$04,$13,$00,$1A,$13,$00,$0D,$15,$00,$11,$15,$00,$09,$0F
  .byte $00,$15,$0F,$00,$07,$0F,$00,$17,$0F,$00,$0C,$07,$00,$12,$07,$00,$0B,$09,$00,$13,$09,$00,$07,$08,$00,$17,$08,$00,$0E,$0D,$00,$10
  .byte $0D,$00,$01,$0B,$00,$1D,$0B,$00,$00
SL_LO:
  .byte <SL0,<SL1,<SL2,<SL3,<SL4,<SL5,<SL6,<SL7,<SL8,<SL9,<SL10,<SL11,<SL12,<SL13,<SL14,<SL15,<SL16,<SL17,<SL18,<SL19,<SL20,<SL21,<SL22,<SL23
SL_HI:
  .byte >SL0,>SL1,>SL2,>SL3,>SL4,>SL5,>SL6,>SL7,>SL8,>SL9,>SL10,>SL11,>SL12,>SL13,>SL14,>SL15,>SL16,>SL17,>SL18,>SL19,>SL20,>SL21,>SL22,>SL23
SL_NSEED:
  .byte $1A,$1C,$1E,$20,$22,$24,$26,$28,$2A,$2C,$2E,$30,$32,$34,$36,$38,$38,$38,$38,$38,$38,$38,$38,$38

; big letters of the title
BIG_TOP:
  .byte $00,$18,$18,$18,$18,$18,$18,$19,$00,$18,$18,$18,$18,$18,$18,$98,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$18,$18,$1E,$1E,$19,$19,$19,$00,$18,$18,$78,$78,$98,$98,$98
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
BIG_BOT:
  .byte $19,$19,$19,$1E,$1E,$18,$18,$00,$98,$98,$98,$78,$78,$18,$18,$00,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00,$19,$18,$18,$18,$18,$18,$18,$00,$98,$18,$18,$18,$18,$18,$18,$00
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
TXT_BIG:
  .byte 3,10,160,161,162,163,164,165,166,167,168,169,164,165,0
  .byte 4,10,192,193,194,195,196,197,198,199,200,201,196,197,0
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
  .byte $20,$06,$24,$06,$27,$06,$2C,$06,$2B,$06,$29,$06,$27,$0C,$24,$06,$25,$06,$27,$06,$29,$06,$27,$06,$25,$06,$24,$0C,$22,$06,$24,$06
  .byte $25,$06,$29,$06,$27,$06,$25,$06,$24,$06,$22,$06,$20,$06,$22,$06,$24,$06,$27,$06,$20,$18,$29,$06,$2B,$06,$2C,$0C,$27,$0C,$29,$06
  .byte $27,$06,$25,$06,$24,$06,$22,$0C,$27,$0C,$2C,$06,$2B,$06,$29,$06,$27,$06,$25,$06,$24,$06,$22,$06,$1F,$06,$20,$18,$FF
SG0_1:
  .byte $18,$18,$18,$18,$19,$18,$14,$18,$16,$18,$1B,$18,$18,$18,$14,$18,$19,$18,$16,$18,$1B,$18,$18,$18,$FF
SG0_2:
  .byte $08,$0C,$0F,$0C,$08,$0C,$0F,$0C,$0D,$0C,$08,$0C,$08,$0C,$0F,$0C,$0F,$0C,$0A,$0C,$0F,$0C,$03,$0C,$08,$0C,$0F,$0C,$08,$0C,$08,$0C
  .byte $0D,$0C,$08,$0C,$0A,$0C,$11,$0C,$0F,$0C,$03,$0C,$08,$18,$FF
SG0_3:
  .byte $01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C
  .byte $01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG1_0:
  .byte $27,$06,$2C,$06,$30,$06,$33,$0C,$30,$06,$31,$06,$2E,$06,$2B,$06,$2C,$18,$FF
SG1_1:
  .byte $24,$18,$25,$18,$24,$18,$FF
SG1_2:
  .byte $08,$0C,$0F,$0C,$03,$0C,$0F,$0C,$08,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$02,$06,$03,$06,$01,$06,$03,$06,$02,$06,$03,$06,$04,$18,$FF
SG2_0:
  .byte $2C,$04,$2E,$04,$30,$04,$33,$04,$38,$18,$00,$04,$37,$04,$38,$18,$FF
SG2_1:
  .byte $24,$10,$27,$1C,$24,$18,$FF
SG2_2:
  .byte $08,$10,$0F,$1C,$08,$18,$FF
SG2_3:
  .byte $02,$04,$02,$04,$02,$04,$02,$04,$01,$18,$03,$04,$03,$04,$04,$18,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$2D,$2D,$45,$45,$28,$28,$28,$1E,$1E,$1E,$18,$18,$18,$18,$18,$18,$23,$25,$28,$2B,$2F,$34,$39,$40,$49,$55,$65,$7D,$50,$50,$50
  .byte $50,$3F,$3F,$3F,$3F,$35,$35,$35,$35,$35,$35,$35,$35,$D0,$D0,$68,$6E,$6B,$70,$80,$87,$83,$8A,$9D,$A5,$A1,$AA,$C1,$CB,$C6,$D0,$ED
  .byte $F9,$F3,$00,$23,$32,$2A,$3A,$65,$78,$6E,$81,$B6,$CD,$1C,$1C,$1C,$1C,$5B,$5B,$5B,$5B,$1C,$1C,$1C,$1C,$5B,$5B,$5B,$5B,$1C,$1C,$1C
  .byte $1C,$5B,$5B,$5B,$5B,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$9F,$9F,$9F
  .byte $9F,$9F,$9F,$9F,$9F,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5
  .byte $D5,$D5,$D5,$D5,$D5,$1C,$1C,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0A,$08,$08,$04,$0C,$0B,$0A,$0C,$0B,$0A,$0C,$0A,$09,$07,$06,$04,$0B,$0A,$0A,$09,$08,$08,$07,$07,$06,$05,$05,$04,$0B,$0A,$09
  .byte $08,$0B,$0A,$09,$08,$0B,$0A,$09,$08,$07,$06,$05,$04,$06,$03,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09
  .byte $09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0C,$0B,$0A
  .byte $09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08
  .byte $08,$07,$07,$06,$06,$08,$04,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$05,$11,$1D,$2D,$2F,$4D,$65,$7D,$A5,$A7,$AA
WH_LEN:
  .byte $00,$04,$0C,$0C,$10,$02,$1E,$18,$18,$28,$02,$03,$13
W_SEED = 1
W_GOLD = 2
W_LEAF = 3
W_HONEY = 4
W_TURN = 5
W_BITE = 6
W_ROT = 7
W_EXTRA = 8
W_OVER = 9
W_TICK = 10
W_KEY = 11
W_SIGN = 12

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03
EX_NP:
  .byte $00,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B
EX_VC:
  .byte $00,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01,$01
EX_TL:
  .byte $00,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71
EX_TH:
  .byte $00,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02
EX_START:
  .byte $00,$01
EX_LEN:
  .byte $00,$18
S_BIG = 1

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$45, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$46, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$65, <80,>80, $31,0
  .byte 2, $00,$66, <80,>80, $C1,0
  .byte 1, $00,$43, <96,>96, <TILEP,>TILEP
  .byte 1, $00,$63, <96,>96, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4D, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$4E, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$6D, <80,>80, $31,0
  .byte 2, $00,$6E, <80,>80, $C1,0
  .byte 1, $00,$4B, <96,>96, <TILEP,>TILEP
  .byte 1, $00,$6B, <96,>96, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $00,$55, <80,>80, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$56, <80,>80, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$75, <80,>80, $31,0
  .byte 2, $00,$76, <80,>80, $C1,0
  .byte 1, $00,$53, <96,>96, <TILEP,>TILEP
  .byte 1, $00,$73, <96,>96, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
