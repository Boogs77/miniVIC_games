;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ROOM  -  an original first person maze shooter            ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - a mining base on a moon has gone mad: a technician goes  ;
;     down level by level to the reactor, 8 levels of 16 x 16  ;
;     cells, then the base again, faster                       ;
;   - the view in first person: a step of a cell, a quarter    ;
;     turn; the walls are stamps drawn far to near into a      ;
;     buffer, copied to the name table just after the NMI      ;
;   - UP / DOWN = a step forward / back, LEFT / RIGHT = a      ;
;     quarter turn, button 1 = fire; button 2 + LEFT / RIGHT = ;
;     a step aside, button 2 + UP = the next weapon            ;
;   - pulse pistol (no energy), rifle (energy, 2 damage),      ;
;     plasma cannon (3 energy, it hits every foe in the line)  ;
;   - guard robots, tunnel spiders, drones that shoot from     ;
;     afar, the keeper of the reactor; red, blue and yellow    ;
;     cards open the doors; the lift ends the level            ;
;   - health 100, 3 lives; records: the 8 best scores signed   ;
;     with 3 initials, kept on the SD with the BIOS KEYB/SD    ;
;     (zone 34 of the save area, lib_records.asm)              ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz)      ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
LEVEL       = $30      ; level 0-7
LOOPN       = $31      ; round of the base
LIVES       = $32
SCL         = $34      ; score (BCD): tens and units
SCM         = $35      ; thousands and hundreds
SCH         = $36      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
PCX         = $40      ; the player: column, row
PCY         = $41
DIR         = $42      ; 0 north, 1 east, 2 south, 3 west
HEALTH      = $43      ; 0-100
AMMO        = $44      ; energy 0-99
WEAP        = $45      ; weapon 0-2
GOTW        = $46      ; weapons got (bits)
KEYS        = $47      ; cards got (bit 0 red, 1 blue, 2 yellow)
FS          = $48      ; render: the first wall on the middle line
DEP         = $49      ;         depth being drawn
PLN         = $4A      ;         its far plane
REDRAW      = $4B      ; 1 = the view must be drawn again
HUDD        = $4C      ; to draw again: 1 score, 2 health and energy, 4 weapon and cards, 8 lives
FIRET       = $4D      ; frames before the next shot
MOVET       = $4E      ; frames before the next step or turn (a held joystick repeats)
FLASHT      = $4F      ; frames of the red frame (hurt)
GSTATE      = $50      ; 0 playing, 1 dead, 2 the lift
GT          = $51
SHOTT       = $52      ; frames of the flash of the shot
SEEK        = $53      ; the thing in view: 0 none, 1-4 a foe, $80+ cell value of a thing
SEED        = $54      ;   its depth (1-3)
SEEI        = $55      ;   the foe slot
MSGT        = $56      ; frames the message stays
NFOE        = $57      ; foes alive
LOSTN       = $58      ; lives lost (tests)
KILLS       = $59      ; foes downed (tests)
FLASHS      = $5A      ; the frame is red now
DEATH       = $5B      ; what took the last life (kind, tests)
FRAME_CNT   = $60
LAST_FRAME  = $61
RND         = $62
VINT        = $63
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
JOYC        = $72      ; both joysticks
JOYP        = $73      ;   the frame before
PRESS       = $74      ;   pressed now
OI          = $75      ; foe being handled
HITW        = $76      ; frames the foe in view is white (hit)
HUDW        = $77      ; UPDATE_HUD: the bits still to draw
MAPON       = $78      ; 1 = the map is shown (the game waits)
KEEPMAP     = $79      ; 1 = the level again after a life lost: the map stays
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85
HOFF        = $86
CELLV       = $90      ; 15 cells in front (depth 0-4 x left, middle, right)

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380
AY_R_WRITE = $D381
AY_L_LATCH = $D384
AY_L_WRITE = $D385
SND_PTR    = $B0
SN1        = $BB
SND_T1     = $BC
SH_L       = $C0
SH_R       = $D0
SND_CMD    = $FA
SND_MODE   = $FB
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF
OX         = $E0
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4
WH_ID      = $0700
WH_POS     = $0702
EX_ID      = $0704
EX_POS     = $0706
SMT0       = $0708
SMT1       = $0709
TR_PL      = $0710
TR_PH      = $0714
TR_CT      = $0718
TR_ACT     = $071C
TR_NOTE    = $0720
TR_VOL     = $0724
TR_AGE     = $0728
CMD_GAME   = 1
CMD_START  = 2
SONG       = $0730

; ---------------- the foes: 12 slots ----------------
NFO        = 12
F_K        = $0200       ; kind (1 guard, 2 spider, 3 drone, 4 keeper; 0 = free)
F_X        = $020C
F_Y        = $0218
F_HP       = $0224
F_T        = $0230       ; frames to the next move
F_ST       = $023C       ; 0 alive, else frames of its puff left

; ---------------- other RAM ----------------
SAT_BUFFER = $0600
VBUF       = $0900       ; the view, 24 x 16
MAZE_RAM   = $0C00       ; the maze of the level
SEENM      = $0D00       ; 1 = the cell is known (the map)
CELLX      = $0E00       ; the 15 cells looked at: column, row
CELLY      = $0E10

; ---------------- parameters ----------------
BTN_MASK    = %00110000
VIEW_R0     = 2          ; the view: rows 2-17, columns 4-27
VIEW_C0     = 4
STEP_T      = 10         ; frames between two steps with the joystick held
TURN_T      = 12

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 34
REC_RAM     = $7D00
REC_ROW     = 9
REC_WIPEN   = 10
REC_JOY2    = $FF
REC_SROW    = REC_ROW
REC_ONEPL   = 1

PORTB_JOY = $d580
PORTA_JOY = $d581
DDRB_JOY  = $d582
DDRA_JOY  = $d583
VDP_SPRITE_ATT_BASE = $3B00
VDP_NAME_TABLE_BASE = $3800
VREG  = $B001
VDATA = $B000
VDP_WRITE_VRAM_BIT = %01000000
VDP_REGISTER_BITS  = %10000000


 .org $0FD0
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
  JSR SND_INIT
  STZ DDRA_JOY
  STZ DDRB_JOY
  STZ FRAME_CNT
  STZ LAST_FRAME
  STZ HOFF
  STZ SCL
  STZ SCM
  STZ SCH
  STZ LIVES
  JSR REC_INIT
  JSR REC_HISC
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE
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
  STZ SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
.t_rel:
  JSR TITLE_FRAME
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:
  JSR TITLE_FRAME
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BEQ .t_press
  LDA FRAME_CNT
  ORA #$01
  STA RND
  LDA #CMD_GAME
  STA SND_CMD
  JMP NEW_GAME

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

TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR REC_TICK
  BCC .tf_e
  LDA REC_PG
  BEQ .tf_p
  JSR HIDE_SPRITES
  JSR REC_SHOW
  BRA .tf_e
.tf_p:
  JSR TITLE_PAGE
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  A NEW GAME, A LEVEL
; ===============================================================
NEW_GAME:
  STZ KEEPMAP
  STZ SCL
  STZ SCM
  STZ SCH
  STZ LEVEL
  STZ LOOPN
  STZ LOSTN
  STZ KILLS
  LDA #3
  STA LIVES
  JSR FRESH_PLAYER

LEVEL_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while it is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR LOAD_LEVEL
  JSR CLEAR_NT
  JSR DRAW_TOP
  JSR DRAW_FRAME
  JSR DRAW_HUD
  JSR RENDER
  JSR VIEW_COPY
  JSR MSG_LEVEL
  JSR VDP_INT_ON
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
  LDA #40
  JSR WAIT_FRAMES
  LDA #CMD_GAME
  STA SND_CMD
  STZ GSTATE
  LDA #1                       ; the view without the message
  STA REDRAW
  LDA #1                       ; the message line: empty
  STA MSGT


; ===============================================================
;  GAME LOOP
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR NEXT_RND
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  EOR JOYP
  AND JOYC
  STA PRESS
  LDA GSTATE
  BNE .gl_nm
  LDA JOYC                     ; button 2 + DOWN held: the map, the game waits
  AND #$22
  CMP #$22
  BNE .gl_nm
  LDA MAPON
  BNE .gl_mh
  INC MAPON
  JSR HIDE_SPRITES
  JSR DRAW_MAP
  JSR VDP_INT_ON
  JSR VDP_INT_OFF
  JSR VIEW_COPY
.gl_mh:
  JMP WEND
.gl_nm:
  LDA MAPON                    ; the map let go: the view again
  BEQ .gl_go
  STZ MAPON
  LDA #1
  STA REDRAW
  LDA #STEP_T
  STA MOVET
.gl_go:
  LDA GSTATE
  BNE .gl_ns
  JSR PLAYER
  JSR FOES
.gl_ns:
  JSR TIMERS
  JSR SEE
  JSR BUILD_SAT
  JSR UPDATE_HUD
  LDA REDRAW
  BEQ WEND
  STZ REDRAW
  JSR RENDER                   ; the view again: the copy just after the next NMI
  JSR VDP_INT_ON
  JSR VDP_INT_OFF
  JSR VIEW_COPY
WEND:
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  LDA GSTATE
  CMP #2
  BEQ .gl_lift
  JMP LIFE_LOST
.gl_lift:
  JMP LEVEL_DONE


; ===============================================================
;  THE LIFT: the bonus, the next level
; ===============================================================
LEVEL_DONE:
  JSR HIDE_SPRITES
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #<TXT_DONE
  STA TP
  LDA #>TXT_DONE
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #30
  JSR WAIT_FRAMES
  LDA #10                      ; 1000
  STA T5
.ld_b:
  LDA #4
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  LDA #$00
  LDY #$01
  JSR ADD_PTS
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_TICK
  LDX #2
  JSR SFX_WHISTLE
  DEC T5
  BNE .ld_b
.ld_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ld_t
  LDA #40
  JSR WAIT_FRAMES
  INC LEVEL
  LDA LEVEL
  CMP #8
  BCC .ld_n
  STZ LEVEL                    ; the reactor is safe: the base again, faster
  JSR BASE_DONE
.ld_n:
  STZ KEYS
  JMP LEVEL_START

BASE_DONE:
  JSR VDP_INT_OFF
  LDA #<TXT_SAFE
  STA TP
  LDA #>TXT_SAFE
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #3
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.bd_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .bd_t
  LDA #60
  JSR WAIT_FRAMES
  LDA LOOPN
  CMP #7
  BCS .bd_r
  INC LOOPN
.bd_r:
  RTS

; a life lost: the level again from its start, or the game is over
LIFE_LOST:
  DEC LIVES
  BEQ GAME_OVER
  LDA AMMO                     ; health full, some energy, the cards to find again
  CMP #10
  BCS .lf_a
  LDA #10
  STA AMMO
.lf_a:
  LDA #100
  STA HEALTH
  STZ KEYS
  LDA #1                       ; the map of the level stays
  STA KEEPMAP
  JMP LEVEL_START

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
  JSR VDP_INT_ON
  LDA #180
  JSR WAIT_FRAMES
  STZ REC_PL
  LDA SCL
  STA REC_SC
  LDA SCM
  STA REC_SC+1
  LDA SCH
  STA REC_SC+2
  STZ REC_SC+3
  LDA LOOPN                    ; extra byte: the level reached (round x 8 + level + 1)
  ASL A
  ASL A
  ASL A
  SEC
  ADC LEVEL
  STA REC_EX
  JSR REC_CHECK
  JSR REC_SAVE
  JSR REC_HISC
  JMP TITLE

; a new game: the pistol, some energy, full health
FRESH_PLAYER:
  LDA #100
  STA HEALTH
  LDA #10
  STA AMMO
  STZ WEAP
  LDA #1
  STA GOTW
  STZ KEYS
  RTS

REC_HISC:
  LDA REC_TAB
  STA HISC
  LDA REC_TAB+1
  STA HISC+1
  LDA REC_TAB+2
  STA HISC+2
  RTS

REC_XY = NT_XY
REC_CLS:
  JSR CLEAR_NT
  JMP DRAW_TOP
REC_SND:
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
REC_NAME:  .byte "ROOM            "
REC_HEAD:  .byte "BEST TECHNICIANS",0
REC_XLBL:  .byte "LEVEL ",0


; ===============================================================
;  THE SCREEN AROUND THE VIEW, THE HUD
; ===============================================================
; the frame: row 1 and row 18 (columns 3-28), columns 3 and 28 (rows 2-17)
DRAW_FRAME:
  LDX #1
  JSR FR_ROW
  LDX #18
  JSR FR_ROW
  LDX #2
.df_s:
  PHX
  LDY #3
  JSR NT_XY
  LDA #T_FRAME
  STA VDATA
  PLX
  PHX
  LDY #28
  JSR NT_XY
  LDA #T_FRAME
  STA VDATA
  PLX
  INX
  CPX #18
  BNE .df_s
  RTS
FR_ROW:
  LDY #3
  JSR NT_XY
  LDX #26
  LDA #T_FRAME
.fr_l:
  STA VDATA
  DEX
  BNE .fr_l
  RTS

; the frame red while hurt (the colours of its tile in the three thirds)
FRAME_COL:
  LDX #2
.fc_t:
  LDA #<(T_FRAME*8)
  STA VREG
  LDA FC_HI,X
  STA VREG
  LDA #$E1
  LDY FLASHS
  BEQ .fc_c
  LDA #$81
.fc_c:
  LDY #8
.fc_w:
  STA VDATA
  DEY
  BNE .fc_w
  DEX
  BPL .fc_t
  RTS
FC_HI:      .byte $60|>(T_FRAME*8),$68|>(T_FRAME*8),$70|>(T_FRAME*8)

; row 0: score, record, lives
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #0
  LDY #16
  JSR NT_XY
  LDA HISC+2
  JSR PUT_2
  LDA HISC+1
  JSR PUT_2
  LDA HISC
  JSR PUT_2
DRAW_SCORE:
  LDX #0
  LDY #6
  JSR NT_XY
  LDA SCH
  JSR PUT_2
  LDA SCM
  JSR PUT_2
  LDA SCL
  JMP PUT_2

DRAW_LIVES:
  LDX #0
  LDY #29
  JSR NT_XY
  LDA LIVES
  ORA #$30
  STA VDATA
  RTS

; rows 19-21: health and its bar, energy, weapon, cards, level, facing
DRAW_HUD:
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR PRINT
  JSR DRAW_LIVES
  JSR DRAW_HEALTH
  JSR DRAW_WEAP
  ; fall into DRAW_LEVEL
DRAW_LEVEL:
  LDX #21
  LDY #9
  JSR NT_XY
  LDA LOOPN
  ASL A
  ASL A
  ASL A
  SEC
  ADC LEVEL
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDA LEVEL
  ASL A
  ASL A
  STA T0
  ASL A
  ADC T0
  TAX                          ; x 12
  LDY #12
.dl_n:
  LDA LV_TXT,X
  STA VDATA
  INX
  DEY
  BNE .dl_n
DRAW_FACING:
  LDX #21
  LDY #27
  JSR NT_XY
  LDX DIR
  LDA COMPASS,X
  STA VDATA
  RTS

DRAW_HEALTH:
  LDX #19
  LDY #10
  JSR NT_XY
  LDA HEALTH                   ; 10 cells of 10 (a half cell for 5 or more)
  STA T0
  LDY #10
.dh_c:
  LDA T0
  CMP #10
  BCC .dh_h
  SBC #10
  STA T0
  LDA #T_BARF
  BRA .dh_w
.dh_h:
  LDX #T_BARE
  CMP #5
  BCC .dh_e
  LDX #T_BARH
.dh_e:
  STZ T0
  TXA
.dh_w:
  STA VDATA
  DEY
  BNE .dh_c
  LDX #19
  LDY #27
  JSR NT_XY
  LDA AMMO
  JSR BIN2BCD
  JMP PUT_2

DRAW_WEAP:
  LDX #20
  LDY #10
  JSR NT_XY
  LDA WEAP
  ASL A
  ASL A
  ASL A
  TAX
  LDY #7
.dw_n:
  LDA WEAP_TXT,X
  STA VDATA
  INX
  DEY
  BNE .dw_n
  LDX #20
  LDY #25
  JSR NT_XY
  LDX #0
.dw_k:
  LDA KEYS
  AND BITS,X
  BEQ .dw_nk
  LDA KEYT,X
  BRA .dw_kw
.dw_nk:
  LDA #T_NOKEY
.dw_kw:
  STA VDATA
  INX
  CPX #3
  BNE .dw_k
  RTS

; A = 1-99: the number where the VDP points
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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 health and energy, 4 weapon and cards, 8 lives, 16 facing
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  STA HUDW
  LSR HUDW
  BCC .uh_2
  JSR DRAW_SCORE
.uh_2:
  LSR HUDW
  BCC .uh_4
  JSR DRAW_HEALTH
.uh_4:
  LSR HUDW
  BCC .uh_8
  JSR DRAW_WEAP
.uh_8:
  LSR HUDW
  BCC .uh_16
  JSR DRAW_LIVES
.uh_16:
  LSR HUDW
  BCC .uh_r
  JSR DRAW_FACING
.uh_r:
  RTS

; LEVEL n and its name over the view
MSG_LEVEL:
  LDA #<TXT_LEVEL
  STA TP
  LDA #>TXT_LEVEL
  STA TP+1
  JSR PRINT
  LDA LOOPN
  ASL A
  ASL A
  ASL A
  SEC
  ADC LEVEL
  JSR PUT_NUM
  LDX #10                      ; the name of the level
  LDY #10
  JSR NT_XY
  LDA LEVEL
  ASL A
  ASL A
  STA T0
  ASL A
  ADC T0
  TAX
  LDY #12
.ml_n:
  LDA LV_TXT,X
  STA VDATA
  INX
  DEY
  BNE .ml_n
  RTS

; A = message number: on row 22 for 2 s
MESSAGE:
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A                        ; x 32 (26 characters used)
  TAX
  LDY #3
  PHX
  LDX #22
  JSR NT_XY
  PLX
  LDY #26
.ms_c:
  LDA MSG_TXT,X
  STA VDATA
  INX
  DEY
  BNE .ms_c
  LDA #120
  STA MSGT
  RTS


; ===============================================================
;  SCORE
; ===============================================================
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
ADD_SCORE:
  PHX
  PHY
  SED
  CLC
  LDA SCL
  ADC PTS_L
  STA SCL
  LDA SCM
  ADC PTS_M
  STA SCM
  LDA SCH
  ADC PTS_H
  STA SCH
  CLD
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  THE LEVEL: the maze into RAM, the foes, the start
; ===============================================================
LOAD_LEVEL:
  LDA KEEPMAP                  ; a new level: nothing known
  BNE .ll_k
  LDX #0
.ll_z:
  STZ SEENM,X
  INX
  BNE .ll_z
.ll_k:
  STZ KEEPMAP
  STZ MAPON
  LDX LEVEL
  LDA LV_LO,X
  STA PTR
  LDA LV_HI,X
  STA PTR+1
  LDY #0
.ll_m:
  LDA (PTR),Y
  STA MAZE_RAM,Y
  INY
  BNE .ll_m
  INC PTR+1
  LDA (PTR),Y
  STA PCX
  INY
  LDA (PTR),Y
  STA PCY
  INY
  LDA (PTR),Y
  STA DIR
  INY
  LDX #0
  STZ NFOE
.ll_f:
  LDA (PTR),Y                  ; kind (0 = end)
  BEQ .ll_c
  STA F_K,X
  INY
  LDA (PTR),Y
  STA F_X,X
  INY
  LDA (PTR),Y
  STA F_Y,X
  INY
  PHY
  LDY F_K,X
  LDA FHP_T,Y
  STA F_HP,X
  JSR NEXT_RND
  AND #63
  CLC
  ADC #30
  STA F_T,X
  STZ F_ST,X
  PLY
  INC NFOE
  INX
  CPX #NFO
  BNE .ll_f
.ll_c:
  CPX #NFO
  BCS .ll_r
  STZ F_K,X
  INX
  BRA .ll_c
.ll_r:
  STZ FIRET
  STZ MOVET
  STZ FLASHT
  STZ SHOTT
  STZ HITW
  LDA FLASHS
  BEQ .ll_x
  STZ FLASHS
  JSR FRAME_COL
.ll_x:
  RTS


; ===============================================================
;  THE PLAYER: steps, turns, weapons, shots
; ===============================================================
PLAYER:
  LDA JOYC                     ; the joystick let go: the next move at once
  AND #$0F
  BNE .pl_t
  STZ MOVET
.pl_t:
  LDA MOVET
  BEQ .pl_mv
  DEC MOVET
  JMP .pl_f
.pl_mv:
  LDA JOYC
  AND #$20
  BEQ .pl_n
  ; ---- button 2 held: a step aside, or the next weapon
  LDA PRESS
  AND #$01
  BEQ .pl_s
  JSR NEXT_WEAPON
  JMP .pl_f
.pl_s:
  LDA JOYC
  AND #$0C
  BEQ .pl_f
  LDX DIR
  DEX
  CMP #$04
  BEQ .pl_sd
  INX
  INX
.pl_sd:
  TXA
  AND #3
  TAX
  JSR STEP
  LDA #STEP_T
  STA MOVET
  BRA .pl_f
.pl_n:
  ; ---- steps and turns
  LDA JOYC
  LSR A
  BCC .pl_d
  LDX DIR                      ; up: forwards
  JSR STEP
  LDA #STEP_T
  STA MOVET
  BRA .pl_f
.pl_d:
  LSR A
  BCC .pl_l
  LDA DIR                      ; down: back
  EOR #2
  TAX
  JSR STEP
  LDA #STEP_T
  STA MOVET
  BRA .pl_f
.pl_l:
  LSR A
  BCC .pl_r
  LDA DIR                      ; left
  DEC A
  BRA .pl_turn
.pl_r:
  LSR A
  BCC .pl_f
  LDA DIR                      ; right
  INC A
.pl_turn:
  AND #3
  STA DIR
  LDA #1
  STA REDRAW
  LDA #16
  TSB HUDD
  LDA #TURN_T
  STA MOVET
.pl_f:
  ; ---- button 1: a shot
  LDA FIRET
  BEQ .pl_fb
  DEC FIRET
  RTS
.pl_fb:
  LDA JOYC
  AND #$10
  BEQ .pl_x
  JMP FIRE
.pl_x:
  RTS

; X = direction: a step there (a door opens with its card, the lift ends the level, a thing is taken)
STEP:
  LDA PCX
  CLC
  ADC DXT,X
  STA T3
  LDA PCY
  CLC
  ADC DYT,X
  STA T4
  JSR CELL_T34
  CMP #1
  BEQ .st_r
  BCC .st_free
  CMP #5
  BCC .st_door
  BEQ .st_lift
.st_free:
  JSR FOE_AT                   ; a foe there: no way
  BCS .st_r
  LDA T3
  STA PCX
  LDA T4
  STA PCY
  LDA #1
  STA REDRAW
  LDA #W_STEP
  LDX #2
  JSR SFX_WHISTLE
  JSR CELL_T34
  CMP #6
  BCC .st_r
  JMP PICK
.st_r:
  RTS
.st_lift:
  LDA #2
  STA GSTATE
  LDA #60
  STA GT
  LDA #W_LIFT
  LDX #2
  JMP SFX_WHISTLE
.st_door:
  SEC                          ; a door: kind 0-2
  SBC #2
  STA T5
  TAX
  LDA BITS,X
  AND KEYS
  BEQ .st_lock
  JSR CELL_PTR                 ; open: the cell is free now
  LDA #0
  STA MAZE_RAM,Y
  LDA #1
  STA REDRAW
  LDA #W_DOOR
  LDX #2
  JMP SFX_WHISTLE
.st_lock:
  LDA #W_DENY
  LDX #2
  JSR SFX_WHISTLE
  LDA T5
  INC A
  JMP MESSAGE

; T3 / T4 = column / row inside the maze: Y = its place in MAZE_RAM
CELL_PTR:
  LDA T4
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T3
  TAY
  RTS

; A = the thing on the cell T3 / T4 (6-12): taken
PICK:
  STA T5
  JSR CELL_PTR
  LDA #0
  STA MAZE_RAM,Y
  LDA #$50
  LDY #$00
  JSR ADD_PTS
  LDA T5
  CMP #6
  BNE .pk_m
  LDA AMMO                     ; an energy cell: +10
  CLC
  ADC #10
  JSR SET_AMMO
  LDA #4
  BRA .pk_msg
.pk_m:
  CMP #7
  BNE .pk_c
  LDA HEALTH                   ; a medical kit: +30
  CLC
  ADC #30
  CMP #101
  BCC .pk_h
  LDA #100
.pk_h:
  STA HEALTH
  LDA #2
  TSB HUDD
  LDA #5
  BRA .pk_msg
.pk_c:
  CMP #11
  BCS .pk_w
  SEC                          ; a card
  SBC #8
  TAX
  LDA BITS,X
  TSB KEYS
  LDA #4
  TSB HUDD
  LDA #W_CARD
  LDX #2
  JSR SFX_WHISTLE
  LDA #6
  JMP MESSAGE
.pk_w:
  SEC                          ; a weapon: 1 the rifle, 2 the plasma cannon
  SBC #10
  STA WEAP
  TAX
  LDA BITS,X
  TSB GOTW
  LDA AMMO
  CLC
  ADC #20
  JSR SET_AMMO
  LDA #4
  TSB HUDD
  LDA #7
.pk_msg:
  PHA
  LDA #W_PICK
  LDX #2
  JSR SFX_WHISTLE
  PLA
  JMP MESSAGE

; A = energy (at most 99)
SET_AMMO:
  CMP #100
  BCC .sa_s
  LDA #99
.sa_s:
  STA AMMO
  LDA #2
  TSB HUDD
  RTS

; button 2 + UP: the next weapon the player has
NEXT_WEAPON:
  LDX WEAP
.nw_l:
  INX
  CPX #3
  BCC .nw_c
  LDX #0
.nw_c:
  LDA BITS,X
  AND GOTW
  BEQ .nw_l
  STX WEAP
  LDA #4
  TSB HUDD
  LDA #W_KEY
  LDX #2
  JMP SFX_WHISTLE

; X = foe, or C = 1: is a foe (alive) on T3 / T4? (keeps T3, T4)
FOE_AT:
  LDX #NFO-1
.fa_l:
  LDA F_K,X
  BEQ .fa_n
  LDA F_ST,X
  BNE .fa_n
  LDA F_X,X
  CMP T3
  BNE .fa_n
  LDA F_Y,X
  CMP T4
  BNE .fa_n
  SEC
  RTS
.fa_n:
  DEX
  BPL .fa_l
  CLC
  RTS


; ===============================================================
;  A SHOT: along the line until a wall, the first foe (the plasma: every foe)
; ===============================================================
FIRE:
  LDX WEAP
  LDA AMMO                     ; enough energy?
  CMP WCOST,X
  BCS .fi_go
  STZ WEAP                     ; no: back to the pistol
  LDA #4
  TSB HUDD
  LDA #W_DENY
  LDX #2
  JMP SFX_WHISTLE
.fi_go:
  SEC
  SBC WCOST,X
  STA AMMO
  LDA #2
  TSB HUDD
  LDA WCOOL,X
  STA FIRET
  LDA WDMG,X
  STA T6
  LDA #6
  STA SHOTT
  LDA WSND,X
  LDX #2
  JSR SFX_WHISTLE
  LDA PCX
  STA T3
  LDA PCY
  STA T4
  LDA #8                       ; 8 cells at most
  STA T7
.fi_c:
  LDX DIR
  LDA T3
  CLC
  ADC DXT,X
  STA T3
  LDA T4
  CLC
  ADC DYT,X
  STA T4
  JSR CELL_T34
  CMP #1                       ; a wall, a door, the lift stop the shot
  BCC .fi_o
  CMP #6
  BCC .fi_r
.fi_o:
  JSR FOE_AT
  BCC .fi_n
  JSR HIT_FOE
  LDA WEAP
  CMP #2
  BNE .fi_r
.fi_n:
  DEC T7
  BNE .fi_c
.fi_r:
  RTS

; X = foe hit by T6 damage
HIT_FOE:
  LDA #8
  STA HITW
  LDA F_HP,X
  SEC
  SBC T6
  STA F_HP,X
  BEQ .hf_d
  BCC .hf_d
  LDA F_T,X                    ; hit: it waits a little
  CLC
  ADC #10
  STA F_T,X
  LDA #W_MHIT
  PHX
  LDX #0
  JSR SFX_WHISTLE
  PLX
  RTS
.hf_d:
  LDA #24                      ; down: a puff, the points
  STA F_ST,X
  DEC NFOE
  INC KILLS
  LDY F_K,X
  LDA FPTS_M,Y
  PHX
  TAY
  LDA #$00
  STA PTS_L
  STY PTS_M
  LDY F_K,X
  LDA FPTS_H,Y
  STA PTS_H
  JSR ADD_SCORE
  LDA #S_POP
  LDY F_K,X
  CPY #4
  BNE .hf_s
  LDA #S_BIG
.hf_s:
  LDX #2
  JSR SFX_BOOM
  PLX
  RTS


; ===============================================================
;  THE FOES: a move now and then; they come when they see the player
; ===============================================================
FOES:
  LDX #NFO-1
.fo_l:
  STX OI
  LDA F_K,X
  BEQ .fo_n
  LDA F_ST,X                   ; a puff: it goes away
  BEQ .fo_a
  DEC F_ST,X
  BNE .fo_n
  STZ F_K,X
  BRA .fo_n
.fo_a:
  DEC F_T,X
  BNE .fo_n
  JSR FOE_MOVE
.fo_n:
  LDX OI
  DEX
  BPL .fo_l
  RTS

; X = foe: its time has come
FOE_MOVE:
  LDA LEVEL                    ; the next time: by kind, faster in the deeper levels
  ASL A
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  STA T0
  LDY F_K,X
  LDA FSPD,Y
  SEC
  SBC T0
  BCC .fm_8
  CMP #8
  BCS .fm_t
.fm_8:
  LDA #8
.fm_t:
  STA F_T,X
  LDA F_X,X                    ; next to the player: it strikes
  SEC
  SBC PCX
  BPL .fm_ax
  EOR #$FF
  INC A
.fm_ax:
  STA T0
  LDA F_Y,X
  SEC
  SBC PCY
  BPL .fm_ay
  EOR #$FF
  INC A
.fm_ay:
  CLC
  ADC T0
  CMP #1
  BNE .fm_far
  LDY F_K,X
  LDA FHIT,Y
  JMP HURT
.fm_far:
  JSR SEES                     ; in sight: drones and the keeper fire, the others come
  BCC .fm_wander
  LDY F_K,X
  CPY #3
  BCC .fm_go
  JSR NEXT_RND                 ; a shot from afar: half of them hit
  CMP #128
  LDA #W_ZAP
  PHP
  PHX
  LDX #1
  JSR SFX_WHISTLE
  PLX
  PLP
  BCC .fm_r
  LDY F_K,X
  LDA FHIT,Y
  JMP HURT
.fm_go:
  LDA T5                       ; T5 = the direction towards the player
  JMP FOE_STEP
.fm_wander:
  JSR NEXT_RND                 ; a random way
  AND #3
  JMP FOE_STEP
.fm_r:
  RTS

; X = foe: C = 1 if it sees the player (same row or column, nothing between, 7 cells at most);
; then T5 = the direction to him (keeps X)
SEES:
  LDA F_X,X
  CMP PCX
  BNE .se_row
  LDA F_Y,X                    ; same column: north or south
  CMP PCY
  LDA #0
  BCS .se_d
  LDA #2
.se_d:
  STA T5
  BRA .se_walk
.se_row:
  LDA F_Y,X
  CMP PCY
  BNE .se_no
  LDA F_X,X                    ; same row: west or east
  CMP PCX
  LDA #3
  BCS .se_d2
  LDA #1
.se_d2:
  STA T5
.se_walk:
  LDA F_X,X
  STA T3
  LDA F_Y,X
  STA T4
  LDA #7
  STA T6
.se_s:
  LDY T5
  LDA T3
  CLC
  ADC DXT,Y
  STA T3
  LDA T4
  CLC
  ADC DYT,Y
  STA T4
  CMP PCY
  BNE .se_c
  LDA T3
  CMP PCX
  BNE .se_c
  SEC                          ; the player
  RTS
.se_c:
  PHX
  JSR CELL_T34
  PLX
  CMP #1
  BCC .se_o
  CMP #6
  BCC .se_no
.se_o:
  DEC T6
  BNE .se_s
.se_no:
  CLC
  RTS

; X = foe, A = direction: a step there if the cell is free (no wall, door, lift, foe, player)
FOE_STEP:
  TAY
  LDA F_X,X
  CLC
  ADC DXT,Y
  STA T3
  LDA F_Y,X
  CLC
  ADC DYT,Y
  STA T4
  CMP PCY
  BNE .fs_c
  LDA T3
  CMP PCX
  BEQ .fs_r
.fs_c:
  PHX
  JSR CELL_T34
  PLX
  CMP #1
  BCC .fs_o
  CMP #6
  BCC .fs_r
.fs_o:
  PHX
  JSR FOE_AT
  PLX
  BCS .fs_r
  LDA T3
  STA F_X,X
  LDA T4
  STA F_Y,X
.fs_r:
  RTS

; A = damage to the player (a red frame); at 0 the life is lost (global: the tests)
HURT:
  STA T0
  LDA #12
  STA FLASHT
  LDA #2
  TSB HUDD
  LDA #W_HURT
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
  LDA HEALTH
  SEC
  SBC T0
  BEQ LOSE_NOW
  BCC LOSE_NOW
  STA HEALTH
  RTS
LOSE_NOW:
  STZ HEALTH
  LDY OI
  LDA F_K,Y
  STA DEATH
  INC LOSTN
  LDA #1
  STA GSTATE
  LDA #120
  STA GT
  LDA #W_OVER
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  TIMERS: the flash of the shot, the red frame, the message
; ===============================================================
TIMERS:
  LDA SHOTT
  BEQ .tm_h
  DEC SHOTT
.tm_h:
  LDA HITW
  BEQ .tm_f
  DEC HITW
.tm_f:
  LDA FLASHT                   ; the frame: red while FLASHT counts
  BEQ .tm_fz
  DEC FLASHT
  LDA #1
.tm_fz:
  CMP FLASHS
  BEQ .tm_m
  STA FLASHS
  JSR FRAME_COL
.tm_m:
  LDA MSGT
  BEQ .tm_r
  DEC MSGT
  BNE .tm_r
  LDA #0                       ; the empty message
  JSR MESSAGE
  STZ MSGT
.tm_r:
  RTS


; ===============================================================
;  WHAT IS IN VIEW: the first foe or thing on the middle line, depth 1-3
; ===============================================================
SEE:
  STZ SEEK
  LDA PCX
  STA T3
  LDA PCY
  STA T4
  LDA #1
  STA SEED
.se_l:
  LDX DIR
  LDA T3
  CLC
  ADC DXT,X
  STA T3
  LDA T4
  CLC
  ADC DYT,X
  STA T4
  JSR CELL_T34
  CMP #1
  BEQ .se_r
  BCC .se_c                    ; open
  CMP #6
  BCC .se_r                    ; a door, the lift
.se_c:
  STA T5
  LDX #NFO-1                   ; a foe (or its puff) there?
.se_f:
  LDA F_K,X
  BEQ .se_fn
  LDA F_X,X
  CMP T3
  BNE .se_fn
  LDA F_Y,X
  CMP T4
  BNE .se_fn
  LDA F_K,X
  STA SEEK
  STX SEEI
  RTS
.se_fn:
  DEX
  BPL .se_f
  LDA T5                       ; a thing on the floor
  BEQ .se_n
  ORA #$80
  STA SEEK
  RTS
.se_n:
  INC SEED
  LDA SEED
  CMP #4
  BCC .se_l
.se_r:
  RTS


; ===============================================================
;  SPRITES: the flash, the weapon, what is in view
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA SHOTT                    ; the flash of the shot
  BEQ .bs_w
  LDA #120
  STA OX
  LDA #106
  STA OY
  LDA #PT_FLASH
  STA ON
  LDA #11
  STA OC
  JSR ADD_SPR
.bs_w:
  LDX WEAP                     ; the weapon: two sprites
  LDA WCOL,X
  STA OC
  TXA
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_WEAP0
  STA ON
  LDA #112
  STA OX
  LDA #128
  LDY SHOTT                    ; it kicks when it fires
  BEQ .bs_k
  LDA #130
.bs_k:
  STA OY
  JSR ADD_SPR
  LDA #128
  STA OX
  LDA ON
  CLC
  ADC #4
  STA ON
  JSR ADD_SPR
  LDA SEEK
  BEQ .bs_e
  BMI .bs_t
  JSR SAT_FOE
  BRA .bs_e
.bs_t:
  JSR SAT_THING
.bs_e:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; a foe in view: 4 sprites near, 1 at the middle, 1 small far; its puff when downed
SAT_FOE:
  LDX SEEI
  LDA F_ST,X
  BEQ .sf_a
  LDY SEED                     ; the puff
  LDA PUFF_Y,Y
  STA OY
  LDA #120
  STA OX
  LDA #PT_PUFF
  STA ON
  LDA #11
  STA OC
  JMP ADD_SPR
.sf_a:
  LDY SEEK
  LDA FCOL,Y
  LDX HITW                     ; hit: white
  BEQ .sf_c
  LDA #15
.sf_c:
  STA OC
  LDA SEED
  CMP #2
  BCS .sf_m
  LDA FPTN,Y                   ; near: 32 x 32
  STA ON
  LDA #112
  STA OX
  LDA #77
  STA OY
  JSR ADD_SPR
  LDA #128
  STA OX
  JSR SF_NEXT
  LDA #112
  STA OX
  LDA #93
  STA OY
  JSR SF_NEXT
  LDA #128
  STA OX
  JMP SF_NEXT
.sf_m:
  BNE .sf_f
  LDA FPTM,Y                   ; depth 2
  STA ON
  LDA #80
  BRA .sf_p
.sf_f:
  LDA FPTF,Y                   ; depth 3
  STA ON
  LDA #72
.sf_p:
  STA OY
  LDA #120
  STA OX
  JMP ADD_SPR

; the next pattern of a near foe
SF_NEXT:
  LDA ON
  CLC
  ADC #4
  STA ON
  JMP ADD_SPR

; a thing on the floor in view
SAT_THING:
  LDA SEEK
  AND #$7F
  SEC
  SBC #6
  TAY
  LDA ITC,Y
  STA OC
  LDA #120
  STA OX
  LDX SEED
  CPX #2
  BCS .st_f
  LDA ITN,Y
  STA ON
  LDA #93
  BRA .st_p
.st_f:
  LDA ITF,Y
  STA ON
  LDA THING_Y,X
.st_p:
  STA OY
  JMP ADD_SPR

; OX, OY, ON, OC: one sprite more (keeps X, Y)
ADD_SPR:
  PHY
  LDY SPRI
  CPY #128
  BCS .ad_r
  LDA OY
  DEC A
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
.ad_r:
  PLY
  RTS


; ===============================================================
;  THE VIEW: the stamps of the walls, far to near, into VBUF, then
;  VBUF to the name table (24 x 16 tiles from row VIEW_R0, column VIEW_C0)
; ===============================================================
; CELLV: 15 cells in front of the player: depth 0-4 x side left, middle, right
; (0 open, 1 wall, 2-5 doors and the exit; outside the maze = wall)
LOOK:
  LDX #0
  LDY #0                       ; depth
.lk_d:
  STY T2
  LDA DIR                      ; the cell at depth Y on the middle line
  TAX
  LDA PCX
  STA T0
  LDA PCY
  STA T1
  LDY T2
  BEQ .lk_m
.lk_f:
  LDA T0
  CLC
  ADC DXT,X
  STA T0
  LDA T1
  CLC
  ADC DYT,X
  STA T1
  DEY
  BNE .lk_f
.lk_m:
  LDA DIR                      ; left: the direction - 1
  DEC A
  AND #3
  TAX
  LDA T0
  CLC
  ADC DXT,X
  STA T3
  LDA T1
  CLC
  ADC DYT,X
  STA T4
  JSR CELL_V
  LDY T2
  LDX LOOK3,Y
  STA CELLV,X
  LDA T3
  STA CELLX,X
  LDA T4
  STA CELLY,X
  LDA T0
  STA T3
  LDA T1
  STA T4
  JSR CELL_V
  LDY T2
  LDX LOOK3,Y
  STA CELLV+1,X
  LDA T3
  STA CELLX+1,X
  LDA T4
  STA CELLY+1,X
  LDA DIR                      ; right: the direction + 1
  INC A
  AND #3
  TAX
  LDA T0
  CLC
  ADC DXT,X
  STA T3
  LDA T1
  CLC
  ADC DYT,X
  STA T4
  JSR CELL_V
  LDY T2
  LDX LOOK3,Y
  STA CELLV+2,X
  LDA T3
  STA CELLX+2,X
  LDA T4
  STA CELLY+2,X
  LDY T2
  INY
  CPY #5
  BEQ .lk_x
  JMP .lk_d
.lk_x:
  RTS

; T3 / T4 = column / row: A = the cell of the maze (outside = a wall)
CELL_T34:
  LDA T3
  CMP #16
  BCS .ct_w
  LDA T4
  CMP #16
  BCS .ct_w
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T3
  TAY
  LDA MAZE_RAM,Y
  RTS
.ct_w:
  LDA #1
  RTS

; T3 / T4: the cell as the view sees it (the things on the floor are open floor)
CELL_V:
  JSR CELL_T34
  CMP #6
  BCC .cv_r
  LDA #0
.cv_r:
  RTS

; the view into VBUF (no VDP)
RENDER:
  JSR LOOK
  LDX #0                       ; the background: every row its tile
.rn_b:
  LDA VROW_LO,X
  STA PTR2
  LDA VROW_HI,X
  STA PTR2+1
  LDA VBG,X
  LDY #23
.rn_bc:
  STA (PTR2),Y
  DEY
  BPL .rn_bc
  INX
  CPX #16
  BNE .rn_b
  LDY #1                       ; FS = the first depth with a wall on the middle line (5 = none)
.rn_fs:
  LDX LOOK3,Y
  LDA CELLV+1,X
  BNE .rn_fe
  INY
  CPY #5
  BNE .rn_fs
.rn_fe:
  STY FS
  JSR MARK_SEEN
  LDA #3                       ; depth 3 to 0, open cells only
  STA DEP
.rn_d:
  LDA DEP
  CMP FS
  BCC .rn_ok
  JMP .rn_n
.rn_ok:
  INC A                        ; the plane behind the cell
  STA PLN
  CMP FS
  BNE .rn_lf
  TAY                          ; the wall that closes the middle line
  LDA STF_LO,Y
  LDX STF_HI,Y
  JSR STAMP
  LDY PLN
  LDX LOOK3,Y
  LDA CELLV+1,X
  CMP #2
  BCC .rn_lf
  CPY #4
  BCS .rn_lf
  SEC                          ; a door: kind 0-3
  SBC #2
  STA T5
  TYA
  ASL A
  ASL A
  ORA T5
  TAY
  LDA STD_LO,Y
  LDX STD_HI,Y
  JSR STAMP
.rn_lf:
  LDY DEP                      ; the fronts of the side cells behind open side cells
  LDX LOOK3,Y
  LDA CELLV,X
  BNE .rn_rf
  LDY PLN
  LDX LOOK3,Y
  LDA CELLV,X
  BEQ .rn_rf
  LDA STLF_LO,Y
  LDX STLF_HI,Y
  JSR STAMP
.rn_rf:
  LDY DEP
  LDX LOOK3,Y
  LDA CELLV+2,X
  BNE .rn_s
  LDY PLN
  LDX LOOK3,Y
  LDA CELLV+2,X
  BEQ .rn_s
  LDA STRF_LO,Y
  LDX STRF_HI,Y
  JSR STAMP
.rn_s:
  LDY DEP                      ; the side walls of this cell
  LDX LOOK3,Y
  LDA CELLV,X
  BEQ .rn_sr
  LDA STLS_LO,Y
  LDX STLS_HI,Y
  JSR STAMP
.rn_sr:
  LDY DEP
  LDX LOOK3,Y
  LDA CELLV+2,X
  BEQ .rn_n
  LDA STRS_LO,Y
  LDX STRS_HI,Y
  JSR STAMP
.rn_n:
  DEC DEP
  BMI .rn_x
  JMP .rn_d
.rn_x:
  RTS

; the cells the view shows become known on the map: the middle line up to its wall, the sides
MARK_SEEN:
  LDY #0
.mk_d:
  STY T2
  LDX LOOK3,Y
  JSR MARK_X
  LDY T2
  LDX LOOK3,Y
  INX
  JSR MARK_X
  LDY T2
  LDX LOOK3,Y
  INX
  INX
  JSR MARK_X
  LDY T2
  CPY FS
  BCS .mk_r
  INY
  CPY #5
  BNE .mk_d
.mk_r:
  RTS

; X = one of the 15 cells looked at: known (if inside the maze)
MARK_X:
  LDA CELLX,X
  CMP #16
  BCS .mx_r
  LDA CELLY,X
  CMP #16
  BCS .mx_r
  ASL A
  ASL A
  ASL A
  ASL A
  ORA CELLX,X
  TAY
  LDA #1
  STA SEENM,Y
.mx_r:
  RTS

; the map of the known cells into VBUF (16 x 16 in the middle of the view), the player's arrow
DRAW_MAP:
  LDX #0
.dm_r:
  LDA VROW_LO,X
  STA PTR2
  LDA VROW_HI,X
  STA PTR2+1
  LDA #$20
  LDY #23
.dm_s:
  STA (PTR2),Y
  DEY
  BPL .dm_s
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0                       ; the first cell of the row
  LDY #4
.dm_c:
  TYA
  SEC
  SBC #4
  ORA T0
  PHY
  TAY
  LDA SEENM,Y
  BEQ .dm_u
  LDA MAZE_RAM,Y
  TAY
  LDA MAPT,Y
  BRA .dm_p
.dm_u:
  LDA #$20
.dm_p:
  PLY
  STA (PTR2),Y
  INY
  CPY #20
  BNE .dm_c
  INX
  CPX #16
  BNE .dm_r
  LDX PCY                      ; the player
  LDA VROW_LO,X
  STA PTR2
  LDA VROW_HI,X
  STA PTR2+1
  LDA PCX
  CLC
  ADC #4
  TAY
  LDA DIR
  CLC
  ADC #MT_PN
  STA (PTR2),Y
  RTS

; A / X = a stamp: its runs into VBUF
STAMP:
  STA PTR
  STX PTR+1
.sm_r:
  LDY #0
  LDA (PTR),Y                  ; row ($FF = end)
  CMP #$FF
  BEQ .sm_e
  TAX
  INY
  LDA (PTR),Y                  ; column
  CLC
  ADC VROW_LO,X
  STA PTR2
  LDA VROW_HI,X
  ADC #0
  STA PTR2+1
  INY
  LDA (PTR),Y                  ; count
  STA T6
  LDA PTR                      ; past the head of the run
  CLC
  ADC #3
  STA PTR
  BCC .sm_c
  INC PTR+1
.sm_c:
  LDY #0
.sm_t:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  CPY T6
  BNE .sm_t
  TYA
  CLC
  ADC PTR
  STA PTR
  BCC .sm_r
  INC PTR+1
  BRA .sm_r
.sm_e:
  RTS

; VBUF to the name table (interrupt off)
VIEW_COPY:
  LDX #0
.vc_r:
  LDA VROW_LO,X
  STA PTR2
  LDA VROW_HI,X
  STA PTR2+1
  LDA VNT_LO,X
  STA VREG
  LDA VNT_HI,X
  STA VREG
  LDY #0
.vc_c:
  LDA (PTR2),Y
  STA VDATA
  INY
  CPY #24
  BNE .vc_c
  INX
  CPX #16
  BNE .vc_r
  RTS

; the map: the tile of every kind of cell (0-12)
MAPT:       .byte MT_FLOOR,MT_WALL,MT_DOORR,MT_DOORB,MT_DOORY,MT_LIFT,MT_FLOOR,MT_FLOOR
            .byte MT_CARDR,MT_CARDB,MT_CARDY,MT_FLOOR,MT_FLOOR
; the four directions: north, east, south, west
DXT:        .byte 0,1,0,$FF
DYT:        .byte $FF,0,1,0
LOOK3:      .byte 0,3,6,9,12               ; depth x 3
VROW_LO:
  .byte <(VBUF+0*24),<(VBUF+1*24),<(VBUF+2*24),<(VBUF+3*24),<(VBUF+4*24),<(VBUF+5*24),<(VBUF+6*24),<(VBUF+7*24)
  .byte <(VBUF+8*24),<(VBUF+9*24),<(VBUF+10*24),<(VBUF+11*24),<(VBUF+12*24),<(VBUF+13*24),<(VBUF+14*24),<(VBUF+15*24)
VROW_HI:
  .byte >(VBUF+0*24),>(VBUF+1*24),>(VBUF+2*24),>(VBUF+3*24),>(VBUF+4*24),>(VBUF+5*24),>(VBUF+6*24),>(VBUF+7*24)
  .byte >(VBUF+8*24),>(VBUF+9*24),>(VBUF+10*24),>(VBUF+11*24),>(VBUF+12*24),>(VBUF+13*24),>(VBUF+14*24),>(VBUF+15*24)
VNT_LO:
  .byte <(VIEW_R0*32+VIEW_C0),<((VIEW_R0+1)*32+VIEW_C0),<((VIEW_R0+2)*32+VIEW_C0),<((VIEW_R0+3)*32+VIEW_C0)
  .byte <((VIEW_R0+4)*32+VIEW_C0),<((VIEW_R0+5)*32+VIEW_C0),<((VIEW_R0+6)*32+VIEW_C0),<((VIEW_R0+7)*32+VIEW_C0)
  .byte <((VIEW_R0+8)*32+VIEW_C0),<((VIEW_R0+9)*32+VIEW_C0),<((VIEW_R0+10)*32+VIEW_C0),<((VIEW_R0+11)*32+VIEW_C0)
  .byte <((VIEW_R0+12)*32+VIEW_C0),<((VIEW_R0+13)*32+VIEW_C0),<((VIEW_R0+14)*32+VIEW_C0),<((VIEW_R0+15)*32+VIEW_C0)
VNT_HI:
  .byte $78|>(VIEW_R0*32),$78|>((VIEW_R0+1)*32),$78|>((VIEW_R0+2)*32),$78|>((VIEW_R0+3)*32)
  .byte $78|>((VIEW_R0+4)*32),$78|>((VIEW_R0+5)*32),$78|>((VIEW_R0+6)*32),$78|>((VIEW_R0+7)*32)
  .byte $78|>((VIEW_R0+8)*32),$78|>((VIEW_R0+9)*32),$78|>((VIEW_R0+10)*32),$78|>((VIEW_R0+11)*32)
  .byte $78|>((VIEW_R0+12)*32),$78|>((VIEW_R0+13)*32),$78|>((VIEW_R0+14)*32),$78|>((VIEW_R0+15)*32)


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from sky squirrel)
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
BITS:       .byte 1,2,4,8
COMPASS:    .byte "NESW"
KEYT:       .byte T_KEYR,T_KEYB,T_KEYY
; the weapons: pistol, rifle, plasma cannon
WCOST:      .byte 0,1,3                        ; energy a shot
WCOOL:      .byte 20,12,30                     ; frames between shots
WDMG:       .byte 1,2,4
WSND:       .byte W_PISTOL,W_RIFLE,W_PLASMA
WCOL:       .byte 14,15,7
WEAP_TXT:   .byte "PISTOL  RIFLE   PLASMA  "
; the foes (index = kind 1-4: guard, spider, drone, keeper)
FHP_T:      .byte 0,3,1,2,16                   ; hits it takes
FSPD:       .byte 0,40,16,30,36                ; frames between two moves
FHIT:       .byte 0,9,6,7,14                   ; damage of a strike
FPTS_M:     .byte 0,$02,$01,$03,$00            ; points: 200, 100, 300, 5000
FPTS_H:     .byte 0,$00,$00,$00,$05
FCOL:       .byte 0,11,13,3,8
FPTN:       .byte 0,PT_GUARDN,PT_SPIDERN,PT_DRONEN,PT_KEEPERN
FPTM:       .byte 0,PT_GUARDM,PT_SPIDERM,PT_DRONEM,PT_KEEPERM
FPTF:       .byte 0,PT_GUARDF,PT_SPIDERF,PT_DRONEF,PT_KEEPERF
PUFF_Y:     .byte 0,85,80,72
; the things on the floor (cell 6-12): energy, medical kit, cards red, blue, yellow, rifle, plasma
ITN:        .byte PT_AMMON,PT_MEDN,PT_CARDN,PT_CARDN,PT_CARDN,PT_RIFLEN,PT_PLASMAN
ITF:        .byte PT_AMMOF,PT_MEDF,PT_CARDF,PT_CARDF,PT_CARDF,PT_RIFLEF,PT_PLASMAF
ITC:        .byte 10,15,8,5,11,14,7
THING_Y:    .byte 0,93,80,72

; title: a guard, a spider, a drone (sprite Y, X, pattern, colour)
TITLE_NS = 3
TITLE_SY:   .byte 103,103,103
TITLE_SX:   .byte 40,120,200
TITLE_SN:   .byte PT_GUARDM,PT_SPIDERM,PT_DRONEM
TITLE_SC:   .byte 11,13,3

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"SCORE",0
  .byte 0,13,"HI",0
  .byte 0,23,"LIVES",0
  .byte $FF
TXT_BUTTONS:
  .byte 6,5,"THE MOON BASE HAS GONE MAD",0
  .byte 20,7,"BUTTON 1 = START",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,1,"UP DOWN STEP, LEFT RIGHT TURN",0
  .byte 10,1,"BUTTON 1 = FIRE",0
  .byte 11,1,"BUTTON 2 + LEFT RIGHT = ASIDE",0
  .byte 12,1,"BUTTON 2 + UP WEAPON, DOWN MAP",0
  .byte 15,3,"GUARD",0
  .byte 15,13,"SPIDER",0
  .byte 15,23,"DRONE",0
  .byte 17,1,"FIND THE CARDS, REACH THE LIFT",0
  .byte $FF
TXT_HUD:
  .byte 19,3,"HEALTH",0
  .byte 19,20,"ENERGY",0
  .byte 20,3,"WEAPON",0
  .byte 20,19,"CARDS",0
  .byte 21,3,"LEVEL",0
  .byte $FF
TXT_LEVEL:
  .byte 8,12,"LEVEL ",0,$FF
TXT_DONE:
  .byte 8,9,"THE LIFT GOES DOWN",0
  .byte 10,11,"BONUS 1000",0
  .byte $FF
TXT_SAFE:
  .byte 13,8,"THE REACTOR IS SAFE",0,$FF
TXT_OVER:
  .byte 9,11,"GAME OVER",0,$FF
; messages on row 22 (26 characters, 32 apart)
MSG_TXT:
  .byte "                          ","      "
  .byte "THE RED DOOR IS LOCKED    ","      "
  .byte "THE BLUE DOOR IS LOCKED   ","      "
  .byte "THE YELLOW DOOR IS LOCKED ","      "
  .byte "ENERGY CELL               ","      "
  .byte "MEDICAL KIT               ","      "
  .byte "A CARD                    ","      "
  .byte "A NEW WEAPON              ","      "

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 13, 9, 12, 0
FLOOR_TAB:     .byte 8, 5, 7, 0
DECMASK_TAB:   .byte 3, 7, 3, 0
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
; ROOM: generated by dev/gen_room.js (do not edit by hand)

; view tiles 96-178: patterns and colours
VTILEP:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$F7,$F7,$F7,$F7,$F7,$F7,$F7,$F7
  .byte $7F,$7F,$7F,$00,$00,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$F7,$F7,$F7,$00,$00,$F7,$F7,$F7,$7F,$7F,$7F,$7F,$00,$00,$7F,$7F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$F7,$F7,$F7,$F7,$00,$00,$F7,$F7,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$00,$7F,$7F,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $7F,$7F,$7F,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $7F,$7F,$7F,$7F,$00,$00,$7F,$7F,$7F,$7F,$7F,$00,$00,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$F0,$F8,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F8,$FC,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$E0,$F0,$FC,$FE,$E7,$E7,$E7,$E7,$E7,$E7,$E7,$E7,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$00,$00,$00,$00,$00,$FC,$F8
  .byte $00,$00,$00,$FE,$F8,$F0,$C0,$80,$E0,$C0,$00,$00,$00,$00,$00,$00,$FE,$FC,$F0,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$07
  .byte $01,$03,$0F,$1F,$7F,$00,$00,$00,$00,$00,$00,$01,$07,$0F,$3F,$7F,$1F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3F,$1F
  .byte $07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$1F,$0F,$03,$01,$7F,$3F,$0F,$07,$01,$00,$00,$00,$00,$00,$00,$80,$E0,$F0,$FC,$FE
  .byte $80,$C0,$F0,$F8,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$E7,$E7,$E7,$E7,$E7,$E7,$E7,$E7,$F8,$FC,$00,$00,$00,$00,$00,$00
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$00,$00,$00,$00,$00,$FC,$F8,$00,$00,$00,$FE,$F8,$F0,$C0,$80,$E0,$C0,$00,$00,$00,$00,$00,$00
  .byte $FE,$FC,$F0,$E0,$80,$00,$00,$00,$00,$00,$00,$01,$07,$0F,$3F,$7F,$00,$00,$00,$00,$00,$00,$03,$07,$01,$03,$0F,$1F,$7F,$00,$00,$00
  .byte $1F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3F,$1F,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7F,$1F,$0F,$03,$01
  .byte $7F,$3F,$0F,$07,$01,$00,$00,$00,$00,$00,$00,$80,$E0,$F0,$FC,$FE,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$7E,$80,$C0,$F0,$F8,$FE,$00,$00,$00
  .byte $00,$00,$00,$01,$07,$0F,$3F,$7F,$01,$03,$0F,$1F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F8,$FC,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$07,$1F,$3F,$00,$00,$00,$00,$00,$00,$7F,$7F,$7F,$00,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $7F,$7F,$7F,$00,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$00,$7F,$7F,$7F,$7F,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$00,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
VTILEC:
  .byte $11,$11,$11,$EE,$EE,$EE,$EE,$EE,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5
  .byte $E5,$E5,$E5,$55,$55,$E5,$E5,$E5,$EE,$EE,$EE,$55,$55,$EE,$EE,$EE,$E5,$E5,$E5,$55,$55,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$55,$55,$E5,$E5
  .byte $EE,$EE,$EE,$EE,$55,$55,$EE,$EE,$E5,$E5,$E5,$E5,$55,$55,$E5,$E5,$EE,$EE,$EE,$EE,$EE,$44,$44,$44,$11,$11,$11,$55,$55,$55,$55,$55
  .byte $54,$54,$54,$54,$54,$54,$54,$54,$55,$55,$55,$55,$55,$55,$55,$55,$54,$44,$54,$54,$54,$54,$54,$54,$55,$44,$55,$55,$55,$55,$55,$55
  .byte $54,$54,$54,$54,$54,$54,$54,$44,$55,$55,$55,$55,$55,$55,$55,$44,$55,$55,$55,$55,$55,$44,$44,$44,$11,$11,$11,$11,$11,$44,$44,$44
  .byte $41,$41,$41,$41,$11,$11,$41,$41,$41,$41,$41,$11,$11,$41,$41,$41,$44,$44,$44,$44,$44,$44,$44,$44,$11,$11,$11,$44,$44,$44,$44,$44
  .byte $44,$44,$44,$44,$44,$11,$44,$44,$E1,$E1,$E1,$E1,$E1,$EE,$EE,$EE,$11,$11,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$EE,$EE,$EE,$EE,$EE,$EE
  .byte $11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$E5,$EE,$EE,$EE,$EE,$EE,$EE,$E4,$E4
  .byte $EE,$EE,$EE,$E4,$E4,$E4,$E4,$E4,$E4,$E4,$44,$44,$44,$44,$44,$44,$E4,$E4,$E4,$E4,$E4,$44,$44,$44,$11,$11,$11,$11,$11,$11,$E1,$E1
  .byte $E1,$E1,$E1,$E1,$E1,$EE,$EE,$EE,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$EE,$E4,$E4
  .byte $E4,$E4,$44,$44,$44,$44,$44,$44,$EE,$EE,$EE,$E4,$E4,$E4,$E4,$E4,$E4,$E4,$E4,$E4,$E4,$44,$44,$44,$11,$11,$11,$51,$51,$51,$51,$51
  .byte $51,$51,$51,$51,$51,$55,$55,$55,$11,$11,$11,$11,$11,$11,$51,$51,$54,$54,$54,$54,$54,$54,$54,$54,$51,$51,$55,$55,$55,$55,$55,$55
  .byte $54,$54,$54,$54,$54,$54,$54,$54,$55,$55,$55,$55,$55,$55,$54,$54,$55,$55,$55,$54,$54,$54,$54,$54,$54,$54,$44,$44,$44,$44,$44,$44
  .byte $54,$54,$54,$54,$54,$44,$44,$44,$11,$11,$11,$51,$51,$51,$51,$51,$11,$11,$11,$11,$11,$11,$51,$51,$51,$51,$51,$51,$51,$55,$55,$55
  .byte $51,$51,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$54,$54,$54,$54,$44,$44,$44,$44,$44,$44,$55,$55,$55,$54,$54,$54,$54,$54
  .byte $54,$54,$54,$54,$54,$44,$44,$44,$11,$11,$11,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$44,$44,$44
  .byte $11,$11,$11,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$44,$44,$44,$11,$11,$11,$11,$11,$11,$41,$41,$41,$41,$44,$44,$44,$44,$44,$44
  .byte $11,$11,$11,$11,$11,$11,$41,$41,$41,$41,$44,$44,$44,$44,$44,$44,$86,$86,$86,$66,$86,$86,$86,$86,$88,$88,$88,$88,$88,$44,$44,$44
  .byte $54,$54,$54,$44,$54,$54,$54,$54,$BA,$BA,$BA,$AA,$BA,$BA,$BA,$BA,$BB,$BB,$BB,$BB,$BB,$44,$44,$44,$C3,$C3,$C3,$CC,$C3,$C3,$C3,$C3
  .byte $33,$33,$33,$33,$33,$44,$44,$44,$88,$88,$88,$44,$44,$44,$44,$44,$55,$55,$55,$44,$44,$44,$44,$44,$BB,$BB,$BB,$44,$44,$44,$44,$44
  .byte $33,$33,$33,$44,$44,$44,$44,$44,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$44,$44
VTILE_FIRST = 96
VTILE_N = 83
VTILE_BYTES = 664
; the background tile of every view row
VBG:
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B2,$76,$76,$76,$76,$76,$76,$76

; HUD tiles 179-199
T_FRAME = 179
T_BARF = 180
T_BARH = 181
T_BARE = 182
T_KEYR = 183
T_KEYB = 184
T_KEYY = 185
T_NOKEY = 186
MT_WALL = 187
MT_FLOOR = 188
MT_DOORR = 189
MT_DOORB = 190
MT_DOORY = 191
MT_LIFT = 192
MT_CARDR = 193
MT_CARDB = 194
MT_CARDY = 195
MT_PN = 196
MT_PE = 197
MT_PS = 198
MT_PW = 199
HTILEP:
  .byte $FF,$81,$A5,$81,$81,$A5,$81,$FF,$00,$FE,$FE,$FE,$FE,$FE,$FE,$00,$00,$E0,$E0,$E0,$E0,$E0,$E0,$00,$00,$AA,$00,$AA,$00,$AA,$00,$00
  .byte $00,$7E,$42,$7E,$7E,$66,$7E,$00,$00,$7E,$42,$7E,$7E,$66,$7E,$00,$00,$7E,$42,$7E,$7E,$66,$7E,$00,$00,$00,$00,$18,$18,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7E,$42,$42,$42,$42,$7E,$00,$00,$7E,$42,$42,$42,$42,$7E,$00
  .byte $00,$7E,$42,$42,$42,$42,$7E,$00,$00,$7E,$5A,$66,$5A,$66,$7E,$00,$00,$00,$7E,$42,$7E,$7E,$00,$00,$00,$00,$7E,$42,$7E,$7E,$00,$00
  .byte $00,$00,$7E,$42,$7E,$7E,$00,$00,$18,$3C,$7E,$FF,$18,$18,$18,$00,$08,$0C,$FE,$FF,$FE,$0C,$08,$00,$18,$18,$18,$FF,$7E,$3C,$18,$00
  .byte $10,$30,$7F,$FF,$7F,$30,$10,$00
HTILEC:
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$31,$31,$31,$31,$31,$31,$31,$31,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$51,$51,$51,$51,$51,$51,$51,$51,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$14,$14,$14,$14,$14,$14,$14,$14,$84,$84,$84,$84,$84,$84,$84,$84,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$34,$34,$34,$34,$34,$34,$34,$34,$84,$84,$84,$84,$84,$84,$84,$84,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4
  .byte $B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4
HTILE_FIRST = 179

; stamps: runs of row, first column, count, tiles...; $FF = end
ST_FRONT1:
  .byte $03,$05,$0E,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$04,$05,$0E,$61,$62,$62,$63,$62,$62,$62,$61,$62,$62,$63,$62
  .byte $62,$62,$05,$05,$0E,$61,$62,$62,$63,$62,$62,$62,$61,$62,$62,$63,$62,$62,$62,$06,$05,$0E,$64,$65,$65,$66,$65,$65,$65,$64,$65,$65
  .byte $66,$65,$65,$65,$07,$05,$0E,$61,$62,$62,$63,$62,$62,$62,$61,$62,$62,$63,$62,$62,$62,$08,$05,$0E,$61,$62,$62,$63,$62,$62,$62,$61
  .byte $62,$62,$63,$62,$62,$62,$09,$05,$0E,$67,$68,$68,$69,$68,$68,$68,$67,$68,$68,$69,$68,$68,$68,$0A,$05,$0E,$61,$62,$62,$63,$62,$62
  .byte $62,$61,$62,$62,$63,$62,$62,$62,$0B,$05,$0E,$61,$62,$62,$63,$62,$62,$62,$61,$62,$62,$63,$62,$62,$62,$0C,$05,$0E,$6A,$6A,$6A,$6A
  .byte $6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$6A,$FF
ST_LFRONT1:
  .byte $03,$00,$05,$60,$60,$60,$60,$60,$04,$00,$05,$62,$63,$62,$62,$62,$05,$00,$05,$62,$63,$62,$62,$62,$06,$00,$05,$65,$66,$65,$65,$65
  .byte $07,$00,$05,$62,$63,$62,$62,$62,$08,$00,$05,$62,$63,$62,$62,$62,$09,$00,$05,$68,$69,$68,$68,$68,$0A,$00,$05,$62,$63,$62,$62,$62
  .byte $0B,$00,$05,$62,$63,$62,$62,$62,$0C,$00,$05,$6A,$6A,$6A,$6A,$6A,$FF
ST_RFRONT1:
  .byte $03,$13,$05,$60,$60,$60,$60,$60,$04,$13,$05,$61,$62,$62,$63,$62,$05,$13,$05,$61,$62,$62,$63,$62,$06,$13,$05,$64,$65,$65,$66,$65
  .byte $07,$13,$05,$61,$62,$62,$63,$62,$08,$13,$05,$61,$62,$62,$63,$62,$09,$13,$05,$67,$68,$68,$69,$68,$0A,$13,$05,$61,$62,$62,$63,$62
  .byte $0B,$13,$05,$61,$62,$62,$63,$62,$0C,$13,$05,$6A,$6A,$6A,$6A,$6A,$FF
ST_FRONT2:
  .byte $05,$08,$08,$6B,$6B,$6B,$6B,$6B,$6B,$6B,$6B,$06,$08,$08,$6C,$6D,$6C,$6D,$6C,$6D,$6C,$6D,$07,$08,$08,$6E,$6F,$6E,$6F,$6E,$6F,$6E
  .byte $6F,$08,$08,$08,$70,$71,$70,$71,$70,$71,$70,$71,$09,$08,$08,$6C,$6D,$6C,$6D,$6C,$6D,$6C,$6D,$0A,$08,$08,$72,$72,$72,$72,$72,$72
  .byte $72,$72,$FF
ST_LFRONT2:
  .byte $05,$00,$08,$6B,$6B,$6B,$6B,$6B,$6B,$6B,$6B,$06,$00,$08,$6C,$6D,$6C,$6D,$6C,$6D,$6C,$6D,$07,$00,$08,$6E,$6F,$6E,$6F,$6E,$6F,$6E
  .byte $6F,$08,$00,$08,$70,$71,$70,$71,$70,$71,$70,$71,$09,$00,$08,$6C,$6D,$6C,$6D,$6C,$6D,$6C,$6D,$0A,$00,$08,$72,$72,$72,$72,$72,$72
  .byte $72,$72,$FF
ST_RFRONT2:
  .byte $05,$10,$08,$6B,$6B,$6B,$6B,$6B,$6B,$6B,$6B,$06,$10,$08,$6C,$6D,$6C,$6D,$6C,$6D,$6C,$6D,$07,$10,$08,$6E,$6F,$6E,$6F,$6E,$6F,$6E
  .byte $6F,$08,$10,$08,$70,$71,$70,$71,$70,$71,$70,$71,$09,$10,$08,$6C,$6D,$6C,$6D,$6C,$6D,$6C,$6D,$0A,$10,$08,$72,$72,$72,$72,$72,$72
  .byte $72,$72,$FF
ST_FRONT3:
  .byte $06,$0A,$04,$73,$73,$73,$73,$07,$0A,$04,$74,$74,$74,$74,$08,$0A,$04,$75,$75,$75,$75,$09,$0A,$04,$76,$76,$76,$76,$FF
ST_LFRONT3:
  .byte $06,$06,$04,$73,$73,$73,$73,$07,$06,$04,$74,$74,$74,$74,$08,$06,$04,$75,$75,$75,$75,$09,$06,$04,$76,$76,$76,$76,$FF
ST_RFRONT3:
  .byte $06,$0E,$04,$73,$73,$73,$73,$07,$0E,$04,$74,$74,$74,$74,$08,$0E,$04,$75,$75,$75,$75,$09,$0E,$04,$76,$76,$76,$76,$FF
ST_FRONT4:
  .byte $07,$0B,$02,$77,$77,$08,$0B,$02,$78,$78,$FF
ST_LFRONT4:
  .byte $07,$09,$02,$77,$77,$08,$09,$02,$78,$78,$FF
ST_RFRONT4:
  .byte $07,$0D,$02,$77,$77,$08,$0D,$02,$78,$78,$FF
ST_LSIDE0:
  .byte $00,$00,$02,$79,$7A,$01,$00,$03,$61,$7B,$7C,$02,$00,$05,$61,$62,$7D,$79,$7A,$03,$00,$05,$61,$62,$7D,$62,$7B,$04,$00,$05,$61,$62
  .byte $7D,$62,$7E,$05,$00,$05,$61,$62,$7D,$62,$7E,$06,$00,$05,$61,$62,$7D,$62,$7E,$07,$00,$05,$61,$62,$7D,$62,$7E,$08,$00,$05,$61,$62
  .byte $7D,$62,$7E,$09,$00,$05,$61,$62,$7D,$62,$7E,$0A,$00,$05,$61,$62,$7D,$62,$7E,$0B,$00,$05,$61,$62,$7D,$62,$7E,$0C,$00,$05,$61,$62
  .byte $7D,$62,$7F,$0D,$00,$05,$61,$62,$7D,$80,$81,$0E,$00,$03,$61,$7F,$82,$0F,$00,$02,$80,$81,$FF
ST_RSIDE0:
  .byte $00,$16,$02,$83,$84,$01,$15,$03,$85,$86,$7E,$02,$13,$05,$83,$84,$7D,$62,$7E,$03,$13,$05,$86,$62,$7D,$62,$7E,$04,$13,$05,$61,$62
  .byte $7D,$62,$7E,$05,$13,$05,$61,$62,$7D,$62,$7E,$06,$13,$05,$61,$62,$7D,$62,$7E,$07,$13,$05,$61,$62,$7D,$62,$7E,$08,$13,$05,$61,$62
  .byte $7D,$62,$7E,$09,$13,$05,$61,$62,$7D,$62,$7E,$0A,$13,$05,$61,$62,$7D,$62,$7E,$0B,$13,$05,$61,$62,$7D,$62,$7E,$0C,$13,$05,$87,$62
  .byte $7D,$62,$7E,$0D,$13,$05,$88,$89,$7D,$62,$7E,$0E,$15,$03,$8A,$87,$7E,$0F,$16,$02,$88,$89,$FF
ST_LSIDE1:
  .byte $03,$05,$01,$8B,$04,$05,$03,$6C,$8C,$8D,$05,$05,$03,$6C,$8E,$8F,$06,$05,$03,$6C,$8E,$90,$07,$05,$03,$6C,$8E,$90,$08,$05,$03,$6C
  .byte $8E,$90,$09,$05,$03,$6C,$8E,$90,$0A,$05,$03,$6C,$8E,$91,$0B,$05,$03,$6C,$92,$93,$0C,$05,$01,$94,$FF
ST_RSIDE1:
  .byte $03,$12,$01,$95,$04,$10,$03,$96,$97,$90,$05,$10,$03,$98,$8E,$90,$06,$10,$03,$6C,$8E,$90,$07,$10,$03,$6C,$8E,$90,$08,$10,$03,$6C
  .byte $8E,$90,$09,$10,$03,$6C,$8E,$90,$0A,$10,$03,$99,$8E,$90,$0B,$10,$03,$9A,$9B,$90,$0C,$12,$01,$9C,$FF
ST_LSIDE2:
  .byte $05,$08,$01,$9D,$06,$08,$02,$9E,$9F,$07,$08,$02,$9E,$9E,$08,$08,$02,$9E,$9E,$09,$08,$02,$9E,$76,$0A,$08,$01,$76,$FF
ST_RSIDE2:
  .byte $05,$0F,$01,$A0,$06,$0E,$02,$A1,$9E,$07,$0E,$02,$9E,$9E,$08,$0E,$02,$9E,$9E,$09,$0E,$02,$76,$9E,$0A,$0F,$01,$76,$FF
ST_LSIDE3:
  .byte $06,$0A,$01,$A2,$07,$0A,$01,$A3,$08,$0A,$01,$76,$09,$0A,$01,$76,$FF
ST_RSIDE3:
  .byte $06,$0D,$01,$A4,$07,$0D,$01,$A5,$08,$0D,$01,$76,$09,$0D,$01,$76,$FF
ST_DOOR1_0:
  .byte $06,$08,$08,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$07,$08,$08,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$08,$08,$08,$A6,$A6,$A6,$A6,$A6,$A6,$A6
  .byte $A6,$09,$08,$08,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$0A,$08,$08,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$0B,$08,$08,$A6,$A6,$A6,$A6,$A6,$A6
  .byte $A6,$A6,$0C,$08,$08,$A7,$A7,$A7,$A7,$A7,$A7,$A7,$A7,$FF
ST_DOOR1_1:
  .byte $06,$08,$08,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$07,$08,$08,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$08,$08,$08,$A8,$A8,$A8,$A8,$A8,$A8,$A8
  .byte $A8,$09,$08,$08,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$0A,$08,$08,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$0B,$08,$08,$A8,$A8,$A8,$A8,$A8,$A8
  .byte $A8,$A8,$0C,$08,$08,$72,$72,$72,$72,$72,$72,$72,$72,$FF
ST_DOOR1_2:
  .byte $06,$08,$08,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$07,$08,$08,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$08,$08,$08,$A9,$A9,$A9,$A9,$A9,$A9,$A9
  .byte $A9,$09,$08,$08,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$0A,$08,$08,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$0B,$08,$08,$A9,$A9,$A9,$A9,$A9,$A9
  .byte $A9,$A9,$0C,$08,$08,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$FF
ST_DOOR1_3:
  .byte $06,$08,$08,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$07,$08,$08,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$08,$08,$08,$AB,$AB,$AB,$AB,$AB,$AB,$AB
  .byte $AB,$09,$08,$08,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$0A,$08,$08,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$AB,$0B,$08,$08,$AB,$AB,$AB,$AB,$AB,$AB
  .byte $AB,$AB,$0C,$08,$08,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$FF
ST_DOOR2_0:
  .byte $07,$0A,$04,$A6,$A6,$A6,$A6,$08,$0A,$04,$A6,$A6,$A6,$A6,$09,$0A,$04,$A6,$A6,$A6,$A6,$0A,$0A,$04,$A7,$A7,$A7,$A7,$FF
ST_DOOR2_1:
  .byte $07,$0A,$04,$A8,$A8,$A8,$A8,$08,$0A,$04,$A8,$A8,$A8,$A8,$09,$0A,$04,$A8,$A8,$A8,$A8,$0A,$0A,$04,$72,$72,$72,$72,$FF
ST_DOOR2_2:
  .byte $07,$0A,$04,$A9,$A9,$A9,$A9,$08,$0A,$04,$A9,$A9,$A9,$A9,$09,$0A,$04,$A9,$A9,$A9,$A9,$0A,$0A,$04,$AA,$AA,$AA,$AA,$FF
ST_DOOR2_3:
  .byte $07,$0A,$04,$AB,$AB,$AB,$AB,$08,$0A,$04,$AB,$AB,$AB,$AB,$09,$0A,$04,$AB,$AB,$AB,$AB,$0A,$0A,$04,$AC,$AC,$AC,$AC,$FF
ST_DOOR3_0:
  .byte $07,$0B,$02,$A6,$A6,$08,$0B,$02,$A6,$A6,$09,$0B,$02,$AD,$AD,$FF
ST_DOOR3_1:
  .byte $07,$0B,$02,$A8,$A8,$08,$0B,$02,$A8,$A8,$09,$0B,$02,$AE,$AE,$FF
ST_DOOR3_2:
  .byte $07,$0B,$02,$A9,$A9,$08,$0B,$02,$A9,$A9,$09,$0B,$02,$AF,$AF,$FF
ST_DOOR3_3:
  .byte $07,$0B,$02,$AB,$AB,$08,$0B,$02,$AB,$AB,$09,$0B,$02,$B0,$B0,$FF
; by depth: FRONT and the side fronts 1-4 (index 0 unused), the sides 0-3, the doors 1-3 x 4 kinds
STF_LO:
  .byte <ST_FRONT1,<ST_FRONT1,<ST_FRONT2,<ST_FRONT3,<ST_FRONT4
STF_HI:
  .byte >ST_FRONT1,>ST_FRONT1,>ST_FRONT2,>ST_FRONT3,>ST_FRONT4
STLF_LO:
  .byte <ST_LFRONT1,<ST_LFRONT1,<ST_LFRONT2,<ST_LFRONT3,<ST_LFRONT4
STLF_HI:
  .byte >ST_LFRONT1,>ST_LFRONT1,>ST_LFRONT2,>ST_LFRONT3,>ST_LFRONT4
STRF_LO:
  .byte <ST_RFRONT1,<ST_RFRONT1,<ST_RFRONT2,<ST_RFRONT3,<ST_RFRONT4
STRF_HI:
  .byte >ST_RFRONT1,>ST_RFRONT1,>ST_RFRONT2,>ST_RFRONT3,>ST_RFRONT4
STLS_LO:
  .byte <ST_LSIDE0,<ST_LSIDE1,<ST_LSIDE2,<ST_LSIDE3
STLS_HI:
  .byte >ST_LSIDE0,>ST_LSIDE1,>ST_LSIDE2,>ST_LSIDE3
STRS_LO:
  .byte <ST_RSIDE0,<ST_RSIDE1,<ST_RSIDE2,<ST_RSIDE3
STRS_HI:
  .byte >ST_RSIDE0,>ST_RSIDE1,>ST_RSIDE2,>ST_RSIDE3
STD_LO:
  .byte <ST_DOOR1_0,<ST_DOOR1_1,<ST_DOOR1_2,<ST_DOOR1_3,<ST_DOOR1_0,<ST_DOOR1_1,<ST_DOOR1_2,<ST_DOOR1_3,<ST_DOOR2_0,<ST_DOOR2_1,<ST_DOOR2_2,<ST_DOOR2_3,<ST_DOOR3_0,<ST_DOOR3_1,<ST_DOOR3_2,<ST_DOOR3_3
STD_HI:
  .byte >ST_DOOR1_0,>ST_DOOR1_1,>ST_DOOR1_2,>ST_DOOR1_3,>ST_DOOR1_0,>ST_DOOR1_1,>ST_DOOR1_2,>ST_DOOR1_3,>ST_DOOR2_0,>ST_DOOR2_1,>ST_DOOR2_2,>ST_DOOR2_3,>ST_DOOR3_0,>ST_DOOR3_1,>ST_DOOR3_2,>ST_DOOR3_3

; sprite patterns (16x16), value = pattern number * 4
PT_GUARDN = 0
PT_GUARDN1 = 4
PT_GUARDN2 = 8
PT_GUARDN3 = 12
PT_GUARDM = 16
PT_GUARDF = 20
PT_SPIDERN = 24
PT_SPIDERN1 = 28
PT_SPIDERN2 = 32
PT_SPIDERN3 = 36
PT_SPIDERM = 40
PT_SPIDERF = 44
PT_DRONEN = 48
PT_DRONEN1 = 52
PT_DRONEN2 = 56
PT_DRONEN3 = 60
PT_DRONEM = 64
PT_DRONEF = 68
PT_KEEPERN = 72
PT_KEEPERN1 = 76
PT_KEEPERN2 = 80
PT_KEEPERN3 = 84
PT_KEEPERM = 88
PT_KEEPERF = 92
PT_AMMON = 96
PT_AMMOF = 100
PT_MEDN = 104
PT_MEDF = 108
PT_CARDN = 112
PT_CARDF = 116
PT_RIFLEN = 120
PT_RIFLEF = 124
PT_PLASMAN = 128
PT_PLASMAF = 132
PT_WEAP0 = 136
PT_WEAP0R = 140
PT_WEAP1 = 144
PT_WEAP1R = 148
PT_WEAP2 = 152
PT_WEAP2R = 156
PT_FLASH = 160
PT_PUFF = 164
SPR_LEN = 1344
SPR_PAGES = 6
SPRITES:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1E,$1E,$1E,$1E,$1E,$00,$00,$00,$1F,$1F,$13,$13,$1F,$1F,$1F,$07,$FF,$FF,$FF,$F0,$F3
  .byte $80,$80,$80,$F8,$F8,$C8,$C8,$F8,$F8,$F8,$E0,$FF,$FF,$FF,$0F,$CF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$78,$78,$78,$78
  .byte $1E,$1E,$1E,$1E,$1E,$3F,$3F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$F3,$F3,$F0,$FF,$FF,$FF,$FF,$3E,$3E,$3E,$3E,$3E,$3E,$3E,$FE,$FE
  .byte $CF,$CF,$0F,$FF,$FF,$FF,$FF,$7C,$7C,$7C,$7C,$7C,$7C,$7C,$7F,$7F,$78,$78,$78,$78,$78,$FC,$FC,$FC,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$07,$07,$2F,$7F,$7D,$7D,$7F,$7F,$7F,$07,$07,$07,$0F,$80,$C0,$E0,$E0,$E0,$F4,$FE,$BE,$BE,$FE,$FE,$FE,$E0,$E0,$E0,$F0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$07,$07,$07,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$E0,$E0,$E0,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$1C,$1E,$17,$17,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0F,$1F,$19,$19,$1F,$8F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$F0,$F8,$C8,$C8,$F8,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06,$0E,$1C,$3C,$7C
  .byte $23,$27,$27,$27,$25,$24,$24,$24,$28,$49,$49,$49,$49,$49,$09,$01,$9F,$FF,$FF,$FF,$FF,$FF,$FF,$7F,$FF,$FF,$C7,$00,$00,$00,$00,$00
  .byte $F8,$FC,$FF,$FF,$FF,$FF,$FF,$FE,$FD,$F9,$E0,$00,$00,$00,$00,$00,$72,$FA,$FA,$F2,$F2,$D2,$92,$12,$CA,$E9,$E9,$49,$49,$49,$48,$40
  .byte $00,$00,$00,$00,$01,$03,$67,$73,$5F,$7F,$6F,$6F,$2F,$B9,$B0,$10,$00,$00,$00,$00,$80,$C0,$A2,$C6,$ED,$FD,$FD,$F5,$FB,$8B,$0B,$08
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$05,$07,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$90,$E0,$E0,$B0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$1F,$3F,$7F,$00,$00,$00,$00,$07,$0F,$1F,$3C,$3C,$3C,$3F,$7F,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$E0,$F0,$F8,$3C,$3C,$3C,$FC,$FE,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F8,$FC,$FE
  .byte $66,$3F,$1F,$07,$07,$07,$07,$07,$0F,$0F,$00,$00,$00,$00,$00,$00,$66,$FF,$FF,$FF,$FF,$81,$81,$81,$C1,$C1,$01,$00,$00,$00,$00,$00
  .byte $66,$FF,$FF,$FF,$FF,$81,$81,$81,$83,$83,$80,$00,$00,$00,$00,$00,$66,$FC,$F8,$E0,$E0,$E0,$E0,$E0,$F0,$F0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$06,$07,$3F,$7F,$7F,$3F,$3F,$39,$39,$00,$00,$00,$00,$00,$C0,$E0,$60,$E0,$FC,$FE,$FE,$FC,$FC,$9C,$9C,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$07,$07,$04,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$20,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$C0,$E0,$E0,$77,$7F,$3F,$7F,$E3,$E3,$E3,$FF,$7F,$38,$1F,$7F,$FF
  .byte $01,$03,$03,$E7,$FF,$FE,$FE,$E3,$E3,$E3,$FF,$FE,$0C,$F8,$FE,$FF,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80
  .byte $1B,$1F,$3F,$3F,$3F,$7F,$7F,$7F,$6F,$EF,$C7,$C3,$01,$00,$00,$00,$FF,$FF,$FC,$FD,$FD,$FD,$FD,$FD,$FD,$FC,$FF,$FF,$FF,$FF,$FF,$FC
  .byte $FF,$FF,$3F,$BF,$BF,$BF,$BF,$BF,$BF,$3F,$FF,$FF,$FF,$FF,$FF,$3F,$CC,$EC,$FE,$F6,$FE,$FF,$FF,$FB,$F3,$F3,$E1,$C1,$80,$00,$00,$00
  .byte $08,$0D,$07,$0F,$0D,$0F,$07,$0F,$7F,$7E,$7F,$FF,$FE,$9F,$0F,$0F,$18,$90,$F0,$F0,$D0,$F0,$E0,$F0,$FA,$7F,$FF,$FF,$7D,$F9,$F0,$F0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$02,$03,$03,$03,$07,$0F,$0F,$03,$00,$00,$00,$00,$00,$00,$00,$00,$40,$C0,$C0,$C0,$F0,$F0,$E0,$C0
  .byte $00,$00,$01,$01,$07,$07,$04,$07,$04,$04,$07,$04,$04,$07,$07,$07,$00,$00,$80,$80,$E0,$E0,$20,$E0,$20,$20,$E0,$20,$20,$E0,$E0,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$03,$02,$03,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$40,$C0,$C0,$C0
  .byte $00,$00,$00,$00,$03,$03,$3F,$3E,$3E,$3E,$30,$30,$3E,$3E,$3E,$3F,$00,$00,$00,$00,$C0,$C0,$FC,$7C,$7C,$7C,$0C,$0C,$7C,$7C,$7C,$FC
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$07,$04,$07,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$E0,$20,$E0,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1F,$1F,$10,$10,$1F,$1F,$1F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$F8,$08,$08,$F8,$88,$88,$F8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$04,$07,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$20,$E0,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$38,$38,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$FF,$FF,$FF,$70,$70,$70
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$0F,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$F0,$F0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$7F,$60,$6F,$6F,$60,$7F,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$FE,$06,$F6,$F6,$06,$FE,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$0F,$0F,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$F0,$F0,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$03,$03,$03,$03,$03,$03,$0F,$08,$0F,$0F,$0F,$0F
  .byte $80,$80,$80,$80,$C0,$C0,$C0,$C0,$C0,$C0,$F0,$10,$F0,$F0,$F0,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$03,$03,$03,$03,$0F,$0F,$00,$00,$0F,$3F,$3F,$3F,$3F,$3F
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$F0,$F0,$00,$00,$F0,$FC,$FC,$FC,$FC,$FC,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$1C,$1C,$1C,$1F,$7F,$7F,$7F,$7F,$60,$60,$7F,$70,$70,$7F,$7F
  .byte $F0,$38,$38,$38,$F8,$FE,$FE,$FE,$FE,$06,$06,$FE,$0E,$0E,$FE,$FE,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$23,$0F,$1F,$1C,$38,$38,$B8,$38,$1C,$1F,$0F,$23,$00,$00,$80,$00,$C4,$F0,$F8,$38,$1C,$1C,$1D,$1C,$38,$F8,$F0,$C4,$00,$80
  .byte $00,$00,$00,$10,$08,$04,$01,$03,$7F,$01,$00,$04,$08,$10,$00,$00,$00,$80,$80,$84,$88,$90,$80,$C0,$DF,$80,$00,$90,$88,$84,$80,$80

; the levels: the maze (256 cells), then start column, row, direction, the foes (kind, column, row), 0
LV0:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$01,$06,$01,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$02,$01,$01,$01,$01,$01,$00,$01,$05,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$07,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$00,$00,$01,$07,$00,$00,$01,$00,$00,$00,$01,$08,$01,$01
  .byte $01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$01,$01,$01,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$02,$01,$0B,$02,$01,$06,$01,$01,$03,$0B,$02,$0D,$09,$00
LV1:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$06,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$02,$01,$01,$01,$01,$01,$00,$01,$01,$01,$01,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$00,$01,$00,$01,$01,$01,$07,$01,$07,$01,$00,$00,$0B,$01,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$01,$00,$00,$05,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$00,$06,$01,$00,$00,$00,$01,$08,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $0D,$01,$02,$01,$0D,$07,$01,$07,$01,$01,$02,$01,$02,$03,$09,$02,$01,$04,$00
LV2:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$07,$00,$00,$00,$00,$00,$00,$00,$07,$01,$06,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$06,$01,$01,$01,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$08,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$03,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$01,$00,$00,$00,$01,$09,$01,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$01,$00,$06,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$01,$00,$01,$00,$00,$00,$01,$05,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$01,$00,$02,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$0D,$00,$01,$01,$05,$01,$05,$04,$01,$0D,$0D,$02,$05,$0C,$02,$09,$05,$03,$07,$03,$00
LV3:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$09,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$03,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$00,$00,$01,$06,$01,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$01,$06,$01,$00,$01,$05,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$01,$08,$01,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$06,$01,$00,$02,$00,$00,$00,$01,$07,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$01,$07,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $0D,$0D,$00,$01,$09,$07,$01,$03,$06,$02,$0D,$01,$02,$03,$07,$02,$03,$05,$02,$08,$0B,$03,$0D,$06,$03,$03,$0D,$00
LV4:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$06,$02,$00,$00,$00,$00,$00,$00,$09,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$03,$01,$00,$01,$01,$01,$00,$00,$07,$01,$08,$00,$00,$01,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$01,$01,$00,$01,$01,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$00,$00,$00,$00,$01,$00,$00,$0C,$01,$00,$06,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$00,$01,$01,$01,$04,$01,$00,$01,$01,$01,$00,$00,$00,$01,$00,$00,$07,$01,$00,$00,$00,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$01,$06,$01,$05,$01,$00,$01,$0A,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$00,$01,$01,$01,$06,$01,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$0D,$0B,$01,$0B,$07,$01,$0D,$0D,$02,$05,$0A,$02,$05,$0D,$02,$07,$03,$03,$01,$0B,$03,$02,$09,$00
LV5:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$02,$01,$00,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$01,$06,$01,$05,$01,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$07,$01,$06,$01,$01,$01,$00,$01,$01,$01,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$06,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$00,$06,$01,$00,$00,$0A,$04,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$00,$00,$03,$00,$01,$00,$00,$00,$00,$07,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$00,$09,$01,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $0D,$01,$02,$01,$06,$01,$01,$0A,$05,$01,$03,$05,$01,$02,$0D,$02,$03,$01,$02,$03,$08,$02,$0B,$0D,$03,$05,$05,$03,$0A,$07,$03,$02
  .byte $05,$00
LV6:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$04,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$01,$01,$01,$00,$06,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$03,$01,$01,$01,$01,$01,$06,$01,$00,$01,$06,$00,$00,$00,$09,$01,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$00,$01,$01,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$05,$01,$00,$00,$00,$01,$06,$06,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$01,$00,$01,$00,$02,$00,$01,$08,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$00,$07,$01,$00,$07,$00,$01,$00,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$0D,$00,$01,$0C,$03,$01,$0D,$02,$01,$09,$0D,$01,$05,$0C,$02,$08,$0D,$02,$07,$03,$02,$0C,$0D,$02,$09,$03,$03,$03,$03,$03,$08
  .byte $03,$03,$0C,$01,$00
LV7:
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$06,$03,$00,$00,$00,$01,$06,$00,$00,$01,$06,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$01,$00,$01,$00,$01,$01,$01,$00,$01,$00,$01,$08,$01,$00,$00,$00,$01,$0A,$01,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$00,$01,$01,$01,$01,$01,$04,$01,$00,$01,$01,$01,$00,$01,$09,$01,$00,$01,$00,$00,$05,$01,$00,$00,$00,$01,$01
  .byte $01,$07,$01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$06,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$01,$01,$01,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$01,$01
  .byte $01,$00,$01,$01,$01,$01,$01,$01,$01,$00,$01,$00,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$06,$01,$00,$00,$00,$00,$00,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $0D,$0D,$03,$01,$0A,$09,$01,$04,$0B,$01,$01,$01,$01,$0D,$03,$02,$03,$03,$02,$0B,$05,$02,$03,$08,$03,$08,$03,$03,$07,$09,$03,$06
  .byte $09,$04,$08,$05,$00
LV_LO:
  .byte <LV0,<LV1,<LV2,<LV3,<LV4,<LV5,<LV6,<LV7
LV_HI:
  .byte >LV0,>LV1,>LV2,>LV3,>LV4,>LV5,>LV6,>LV7
; names of the levels (12 characters)
LV_TXT:
  .byte "DOCKING BAY "
  .byte "STORAGE     "
  .byte "HYDROPONICS "
  .byte "MINE SHAFT  "
  .byte "LABORATORY  "
  .byte "SECURITY    "
  .byte "REFINERY    "
  .byte "THE REACTOR "

; big letters of the title
BIG_TOP:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$00,$18,$18,$78,$78,$98,$98,$98
BIG_BOT:
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$18,$18,$18,$18,$18,$18,$00
TXT_BIG:
  .byte 3,12,224,225,226,227,226,227,228,229,0
  .byte 4,12,232,233,234,235,234,235,236,237,0
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
  .byte $27,$0C,$2A,$0C,$2E,$18,$2C,$0C,$2A,$0C,$29,$18,$2A,$0C,$29,$0C,$27,$0C,$26,$0C,$27,$24,$00,$0C,$2E,$0C,$31,$0C,$33,$18,$31,$0C
  .byte $2E,$0C,$2F,$18,$2E,$0C,$2C,$0C,$2A,$0C,$29,$0C,$27,$30,$FF
SG0_1:
  .byte $22,$30,$22,$30,$22,$30,$22,$30,$1E,$30,$20,$30,$22,$30,$1E,$30,$FF
SG0_2:
  .byte $0F,$18,$0F,$18,$0D,$18,$0D,$18,$0B,$18,$0A,$18,$0F,$18,$0F,$18,$12,$18,$12,$18,$14,$18,$14,$18,$0A,$18,$0A,$18,$0F,$30,$FF
SG0_3:
  .byte $01,$18,$03,$18,$01,$18,$03,$18,$01,$18,$03,$18,$01,$18,$03,$18,$01,$18,$03,$18,$01,$18,$03,$18,$01,$18,$03,$18,$04,$30,$FF
SG1_0:
  .byte $27,$08,$27,$08,$2A,$08,$2E,$10,$2D,$08,$2E,$18,$FF
SG1_1:
  .byte $22,$18,$25,$10,$26,$20,$FF
SG1_2:
  .byte $0F,$18,$12,$10,$0A,$20,$FF
SG1_3:
  .byte $01,$08,$01,$08,$02,$08,$01,$10,$02,$08,$04,$18,$FF
SG2_0:
  .byte $2E,$06,$33,$06,$36,$06,$3A,$12,$38,$06,$36,$06,$35,$06,$33,$18,$FF
SG2_1:
  .byte $2A,$12,$2E,$12,$26,$12,$27,$18,$FF
SG2_2:
  .byte $0F,$12,$0F,$12,$0A,$12,$0F,$18,$FF
SG2_3:
  .byte $02,$06,$03,$06,$03,$06,$02,$12,$03,$06,$02,$06,$03,$06,$04,$18,$FF
SG3_0:
  .byte $27,$0C,$2E,$0C,$33,$18,$31,$0C,$2E,$0C,$2A,$18,$2C,$0C,$2E,$0C,$2F,$0C,$31,$0C,$33,$30,$FF
SG3_1:
  .byte $1E,$18,$1E,$18,$22,$18,$22,$18,$20,$18,$1D,$18,$1F,$30,$FF
SG3_2:
  .byte $0F,$18,$0F,$18,$12,$18,$12,$18,$14,$18,$16,$18,$0F,$30,$FF
SG3_3:
  .byte $01,$18,$02,$18,$01,$18,$02,$18,$01,$18,$02,$18,$04,$30,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$23,$27,$2D,$34,$3F,$4E,$68,$34,$41,$55,$7D,$39,$47,$5E,$8B,$D0,$8E,$6C,$57,$49,$3F,$37,$31,$2C,$28,$25,$22,$20,$1D,$1C,$1A
  .byte $38,$38,$38,$39,$13,$F6,$DE,$CA,$BA,$AC,$A0,$95,$8C,$84,$7D,$7D,$7D,$7D,$7D,$1C,$1C,$1C,$1C,$1C,$1C,$00,$00,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$1E,$1E,$1E,$1E,$A1,$A1,$5B,$5B,$A1,$A1,$5B,$5B,$A1,$A1,$5B
  .byte $5B,$59,$64,$72,$84,$9C,$53,$92,$53,$92,$53,$92,$53,$92,$53,$92,$53,$92,$53,$92,$18,$1B,$1E,$21,$26,$2D,$37,$45,$39,$1B,$03,$EE
  .byte $DD,$CE,$C1,$B5,$AB,$A2,$9A,$92,$8B,$85,$80,$7A,$76,$71,$6D,$69,$66,$63,$5F,$5C,$5A,$57,$55,$52,$50,$4E,$D5,$D5,$D5,$D5,$D5,$D5
  .byte $D5,$D5,$D5,$D5,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$E2,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$1C,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$28,$28,$18,$20,$20,$6A,$6A,$6A
  .byte $6A,$54,$54,$54,$54,$47,$47,$47,$47,$47,$47,$1E,$1E
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$02,$02,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$00,$00,$01,$01,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$00,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0C,$0B,$09,$08,$07,$05,$04,$0D,$0C,$0A,$09,$0B,$09,$06,$04,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05
  .byte $07,$05,$03,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$07,$05,$03,$0C,$0C,$0B,$0B,$0A,$0A,$00,$00,$0C,$0B,$0A,$08,$07
  .byte $06,$0C,$0B,$0A,$0C,$0A,$08,$06,$04,$0D,$0C,$0A,$09,$0D,$0C,$0A,$09,$0D,$0C,$0A,$09,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08
  .byte $08,$0B,$0A,$09,$07,$06,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$0A,$09,$08,$07,$07,$06,$05,$04,$0A,$0A,$0A,$0A
  .byte $09,$09,$09,$09,$09,$09,$09,$08,$08,$08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06,$0C,$0B,$0B,$0A,$09,$09
  .byte $08,$07,$07,$06,$0C,$0B,$0B,$0A,$09,$09,$08,$07,$07,$06,$0C,$0B,$0B,$0A,$09,$09,$08,$07,$07,$06,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $09,$09,$09,$09,$08,$08,$08,$07,$07,$07,$06,$06,$0D,$0C,$0A,$09,$0D,$0C,$0A,$09,$0D,$0B,$09,$08,$06,$04,$0A,$08,$05,$0C,$0B,$0A
  .byte $09,$0C,$0B,$0A,$09,$0D,$0B,$09,$07,$05,$03,$0A,$06
WH_START:
  .byte $00,$01,$08,$10,$20,$23,$33,$41,$49,$55,$61,$66,$74,$7C,$9A,$CC,$DA,$DD,$EB
WH_LEN:
  .byte $00,$07,$08,$10,$03,$10,$0E,$08,$0C,$0C,$05,$0E,$08,$1E,$32,$0E,$03,$0E,$02
W_PISTOL = 1
W_RIFLE = 2
W_PLASMA = 3
W_STEP = 4
W_DOOR = 5
W_DENY = 6
W_PICK = 7
W_CARD = 8
W_HURT = 9
W_MHIT = 10
W_GROWL = 11
W_ZAP = 12
W_LIFT = 13
W_OVER = 14
W_EXTRA = 15
W_KEY = 16
W_SIGN = 17
W_TICK = 18

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$0F,$0F,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05
  .byte $05,$04,$04,$03,$03,$02,$02,$01,$01
EX_NP:
  .byte $00,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0C,$0C,$0C,$0C,$0D
  .byte $0D,$0D,$0D,$0E,$0E,$0E,$0E,$0F,$0F
EX_VC:
  .byte $00,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03
  .byte $03,$02,$02,$01,$01,$00,$00,$00,$00
EX_TL:
  .byte $00,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D
  .byte $B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6
EX_TH:
  .byte $00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$03,$02
EX_START:
  .byte $00,$01,$0B
EX_LEN:
  .byte $00,$0A,$1E
S_POP = 1
S_BIG = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$43, <664,>664, <VTILEP,>VTILEP
  .byte 1, $00,$63, <664,>664, <VTILEC,>VTILEC
  .byte 1, $98,$45, <168,>168, <HTILEP,>HTILEP
  .byte 1, $98,$65, <168,>168, <HTILEC,>HTILEC
  .byte 1, $00,$47, <48,>48, <BIG_TOP,>BIG_TOP
  .byte 1, $40,$47, <48,>48, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$67, <48,>48, $81,0
  .byte 2, $40,$67, <48,>48, $61,0
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4B, <664,>664, <VTILEP,>VTILEP
  .byte 1, $00,$6B, <664,>664, <VTILEC,>VTILEC
  .byte 1, $98,$4D, <168,>168, <HTILEP,>HTILEP
  .byte 1, $98,$6D, <168,>168, <HTILEC,>HTILEC
  .byte 1, $00,$4F, <48,>48, <BIG_TOP,>BIG_TOP
  .byte 1, $40,$4F, <48,>48, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$6F, <48,>48, $81,0
  .byte 2, $40,$6F, <48,>48, $61,0
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $00,$53, <664,>664, <VTILEP,>VTILEP
  .byte 1, $00,$73, <664,>664, <VTILEC,>VTILEC
  .byte 1, $98,$55, <168,>168, <HTILEP,>HTILEP
  .byte 1, $98,$75, <168,>168, <HTILEC,>HTILEC
  .byte 1, $00,$57, <48,>48, <BIG_TOP,>BIG_TOP
  .byte 1, $40,$57, <48,>48, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$77, <48,>48, $81,0
  .byte 2, $40,$77, <48,>48, $61,0
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
